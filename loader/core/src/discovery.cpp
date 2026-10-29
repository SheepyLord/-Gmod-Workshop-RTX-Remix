#include "nl/discovery.h"

#include "nl/manifest.h"
#include "nl/paths.h"
#include "nl/vdf.h"

#include <windows.h>

#include <charconv>
#include <system_error>

namespace nl::discovery {

namespace {

namespace fs = std::filesystem;

bool is_dir(const fs::path& p) {
  std::error_code ec;
  return fs::is_directory(p, ec);
}

bool is_file(const fs::path& p) {
  std::error_code ec;
  return fs::is_regular_file(p, ec);
}

fs::path from_utf8(const std::string& text) {
  return fs::path(std::u8string(reinterpret_cast<const char8_t*>(text.data()), text.size()));
}

std::optional<fs::path> steam_from_registry() {
  // The bootstrap links this code in M4 and must retain a KERNEL32-only import table.
  wchar_t system[32768]{};
  const UINT length = GetSystemDirectoryW(system, 32768);
  if (!length || length >= 32768) return std::nullopt;
  const auto path = fs::path(system) / L"advapi32.dll";
  const HMODULE library = LoadLibraryW(path.c_str());
  if (!library) return std::nullopt;
  const auto get_value = reinterpret_cast<decltype(&RegGetValueW)>(GetProcAddress(library, "RegGetValueW"));
  wchar_t buffer[1024];
  DWORD size = sizeof(buffer);
  const auto result = get_value ? get_value(HKEY_CURRENT_USER, L"Software\\Valve\\Steam", L"SteamPath", RRF_RT_REG_SZ,
                                           nullptr, buffer, &size) : ERROR_PROC_NOT_FOUND;
  FreeLibrary(library);
  if (result != ERROR_SUCCESS) {
    return std::nullopt;
  }
  return fs::path(buffer);
}

// The library from libraryfolders.vdf that lists app 4000, else any library with GMod's Workshop folder.
std::optional<fs::path> library_from_steam(const fs::path& steam_root) {
  const fs::path list = steam_root / "steamapps" / "libraryfolders.vdf";
  if (!is_file(list)) return std::nullopt;
  vdf::Node root;
  try {
    root = vdf::load(list);
  } catch (const std::exception&) {
    return std::nullopt;
  }
  const vdf::Node* folders = root.find("libraryfolders");
  if (!folders) return std::nullopt;
  std::optional<fs::path> fallback;
  for (const auto& [key, folder] : folders->children) {
    const vdf::Node* path = folder.find("path");
    if (!path || path->value.empty()) continue;
    const fs::path steamapps = from_utf8(path->value) / "steamapps";
    const vdf::Node* apps = folder.find("apps");
    if (apps && apps->find("4000")) return steamapps;
    if (!fallback && is_dir(steamapps / "workshop" / "content" / "4000")) fallback = steamapps;
  }
  return fallback;
}

// Always absolute: the journal records this location, and start-up (keep-last-good) compares it with
// the location it finds itself, so a root given relative to some other working directory (nlctl)
// must not produce a different spelling of the same folder.
fs::path resolve(const fs::path& game_root, const std::string& configured) {
  const fs::path p = from_utf8(configured);
  return (p.is_absolute() ? p : fs::absolute(game_root) / p).lexically_normal();
}

bool ends_with_folded(const std::string& text, std::string_view suffix) {
  const std::string folded = paths::fold(text);
  return folded.size() >= suffix.size() && folded.compare(folded.size() - suffix.size(), suffix.size(), suffix) == 0;
}

std::string utf8(const fs::path& path) {
  const std::u8string text = path.u8string();
  return std::string(text.begin(), text.end());
}

}  // namespace

const char* source_name(Source source) {
  switch (source) {
    case Source::dev_folder: return "dev_folder";
    case Source::local: return "local";
    case Source::workshop: return "workshop";
  }
  return "?";
}

std::set<std::string> read_addonnomount(const fs::path& game_root) {
  std::set<std::string> ids;
  const fs::path file = game_root / "garrysmod" / "cfg" / "addonnomount.txt";
  if (!is_file(file)) return ids;
  try {
    const vdf::Node root = vdf::load(file);
    if (const vdf::Node* list = root.find("addonnomount")) {
      for (const auto& [key, item] : list->children) {
        if (!item.block && !item.value.empty()) ids.insert(item.value);
      }
    }
  } catch (const std::exception&) {
    // An unreadable list disables nothing; GMod itself would mount everything too.
  }
  return ids;
}

Environment environment_for(const fs::path& game_root, const std::optional<fs::path>& steam_root) {
  Environment env;
  env.game_root = game_root;
  env.disabled_workshop = read_addonnomount(game_root);
  std::optional<fs::path> steamapps;
  const fs::path root = fs::absolute(game_root);
  if (paths::fold(utf8(root.parent_path().filename())) == "common" &&
      paths::fold(utf8(root.parent_path().parent_path().filename())) == "steamapps") {
    steamapps = root.parent_path().parent_path();
  } else if (const auto steam = steam_root ? steam_root : steam_from_registry()) {
    steamapps = library_from_steam(*steam);
  }
  if (steamapps) {
    env.workshop_content = *steamapps / "workshop" / "content" / "4000";
    env.appworkshop_acf = *steamapps / "workshop" / "appworkshop_4000.acf";
  }
  return env;
}

std::vector<Candidate> discover(const config::Config& config, const Environment& env) {
  std::vector<Candidate> out;

  for (const std::string& entry : config.dev_folders) {
    Candidate c{Source::dev_folder, entry, resolve(env.game_root, entry), {}, {}, {}};
    if (!is_dir(c.location)) {
      c.problem = "folder not found";
    } else if (!is_file(c.location / fs::path(std::string(manifest::kManifestPath)))) {
      c.problem = "no native/manifest.json in the folder";
    }
    out.push_back(std::move(c));
  }

  for (const std::string& entry : config.local) {
    Candidate c{Source::local, entry, resolve(env.game_root, entry), {}, {}, {}};
    if (!is_file(c.location)) {
      c.problem = "file not found";
    } else if (!ends_with_folded(entry, ".gma") && !ends_with_folded(entry, ".bin")) {
      c.problem = "not a .gma or .bin archive";
    }
    out.push_back(std::move(c));
  }

  vdf::Node acf;
  bool have_acf = false;
  if (!config.workshop.empty() && !env.appworkshop_acf.empty() && is_file(env.appworkshop_acf)) {
    try {
      acf = vdf::load(env.appworkshop_acf);
      have_acf = true;
    } catch (const std::exception&) {
      // Without Steam's record the items still work; only the update details are missing.
    }
  }
  // Steam's record: installed items (with the version), and the items it keeps details for, which
  // include every subscribed one, even while its first download runs (RESEARCH.md section 22).
  const vdf::Node* app = have_acf ? acf.find("AppWorkshop") : nullptr;
  const vdf::Node* installed = app ? app->find("WorkshopItemsInstalled") : nullptr;
  const vdf::Node* details = app ? app->find("WorkshopItemDetails") : nullptr;

  for (const std::string& id : config.workshop) {
    Candidate c{Source::workshop, id, {}, {}, {}, {}};
    if (installed) {
      if (const vdf::Node* item = installed->find(id)) {
        if (const vdf::Node* t = item->find("timeupdated")) {
          std::uint64_t value = 0;
          const auto [end, ec] = std::from_chars(t->value.data(), t->value.data() + t->value.size(), value);
          if (ec == std::errc() && end == t->value.data() + t->value.size()) c.time_updated = value;
        }
        if (const vdf::Node* m = item->find("manifest")) c.workshop_manifest = m->value;
      }
    }
    if (env.disabled_workshop.count(id)) {
      c.disabled_by_user = true;
      c.problem = "disabled in GMod's addon list (garrysmod/cfg/addonnomount.txt)";
    } else if (!env.workshop_content) {
      c.problem = "the Steam library holding GMod's Workshop folder was not found";
    } else {
      const fs::path folder = *env.workshop_content / fs::path(id);
      std::vector<fs::path> archives;
      std::error_code ec;
      if (is_dir(folder)) {
        for (const auto& item : fs::directory_iterator(folder, ec)) {
          const std::string name = utf8(item.path().filename());
          if (is_file(item.path()) && (ends_with_folded(name, ".gma") || ends_with_folded(name, "_legacy.bin"))) {
            archives.push_back(item.path());
          }
        }
      }
      if (!is_dir(folder) && app && !(installed && installed->find(id)) && !(details && details->find(id))) {
        // Steam lists it nowhere and its files are gone: the user unsubscribed (ADR 0025).
        c.unsubscribed = true;
        c.problem = "not subscribed: Steam no longer has the item (appworkshop_4000.acf), so a package it deployed is removed";
      } else if (!is_dir(folder)) {
        c.problem = "not installed (subscribe in Steam and let it download)";
      } else if (archives.empty()) {
        c.problem = "no .gma or _legacy.bin archive in the item folder";
      } else if (archives.size() > 1) {
        c.problem = std::to_string(archives.size()) + " archives in the item folder; expected one";
      } else {
        c.location = archives.front();
      }
    }
    out.push_back(std::move(c));
  }
  return out;
}

}  // namespace nl::discovery
