#include "nl/discovery.h"
#include "nl/gma.h"

#include "nl/manifest.h"
#include "nl/paths.h"
#include "nl/vdf.h"

#include <windows.h>

#include <algorithm>
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

// The reasons a content-only candidate's Workshop item no longer counts (ADR 0025, ADR 0111).
constexpr std::string_view kGone =
    "not subscribed: Steam no longer has the item (appworkshop_4000.acf), so a package it deployed is removed";
constexpr std::string_view kNotSubscribed =
    "not subscribed: Steam has it only because the game or a server downloaded it (or it was unsubscribed); "
    "content packages come only from subscriptions, so a package it deployed is removed";

}  // namespace

std::optional<bool> subscribed_by_an_account(std::string_view subscribedby) {
  bool account = false;
  std::size_t start = 0;
  for (;;) {
    const std::size_t comma = subscribedby.find(',', start);
    std::string_view part = subscribedby.substr(start, comma == std::string_view::npos ? std::string_view::npos : comma - start);
    while (!part.empty() && (part.front() == ' ' || part.front() == '\t')) part.remove_prefix(1);
    while (!part.empty() && (part.back() == ' ' || part.back() == '\t')) part.remove_suffix(1);
    if (!part.empty()) {
      // Steam writes 32-bit account ids; up to 20 digits also takes a 64-bit one. Anything else is a
      // record this code does not understand, which must neither add nor remove a package.
      if (part.size() > 20 || !std::all_of(part.begin(), part.end(), [](char ch) { return ch >= '0' && ch <= '9'; })) {
        return std::nullopt;
      }
      if (part.find_first_not_of('0') != std::string_view::npos) account = true;
    }
    if (comma == std::string_view::npos) return account;
    start = comma + 1;
  }
}

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

namespace {

Environment environment(const fs::path& game_root, bool ask_steam, const std::optional<fs::path>& steam_root) {
  Environment env;
  env.game_root = game_root;
  env.disabled_workshop = read_addonnomount(game_root);
  std::optional<fs::path> steamapps;
  const fs::path root = fs::absolute(game_root);
  if (paths::fold(utf8(root.parent_path().filename())) == "common" &&
      paths::fold(utf8(root.parent_path().parent_path().filename())) == "steamapps") {
    steamapps = root.parent_path().parent_path();
  } else if (const auto steam = !ask_steam ? std::nullopt : steam_root ? steam_root : steam_from_registry()) {
    steamapps = library_from_steam(*steam);
  }
  if (steamapps) {
    env.workshop_content = *steamapps / "workshop" / "content" / "4000";
    env.appworkshop_acf = *steamapps / "workshop" / "appworkshop_4000.acf";
  }
  return env;
}

}  // namespace

Environment environment_for(const fs::path& game_root, const std::optional<fs::path>& steam_root) {
  return environment(game_root, true, steam_root);
}

Environment environment_in_library(const fs::path& game_root) {
  return environment(game_root, false, std::nullopt);
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

  // Content-only packages from the subscribed items, without the allowlist (ADR 0027, ADR 0111).
  const bool subscribed = config.subscribed_content && env.workshop_content.has_value();
  vdf::Node acf;
  bool have_acf = false;
  if ((!config.workshop.empty() || subscribed) && !env.appworkshop_acf.empty() && is_file(env.appworkshop_acf)) {
    try {
      acf = vdf::load(env.appworkshop_acf);
      have_acf = true;
    } catch (const std::exception&) {
      // Without Steam's record the items still work; only the update details are missing, and no
      // installed item can be shown to be subscribed, so none is new content (ADR 0111).
    }
  }
  // Steam's record: installed items (with the version), and the items it keeps details for, which
  // include every subscribed one, even while its first download runs (RESEARCH.md section 22).
  const vdf::Node* app = have_acf ? acf.find("AppWorkshop") : nullptr;
  const vdf::Node* installed = app ? app->find("WorkshopItemsInstalled") : nullptr;
  const vdf::Node* details = app ? app->find("WorkshopItemDetails") : nullptr;
  // Whether an account on this computer subscribed to the item (ADR 0111). An item the game or a
  // server downloaded (client Lua's steamworks.DownloadUGC, which any server may call) is installed
  // and listed in both sections too, but its details have no `subscribedby`. Without a record that
  // has the details section, or with a value this code does not understand, Steam cannot tell us.
  const auto subscription = [&](const std::string& id) -> std::optional<bool> {
    if (!details || !details->block) return std::nullopt;
    const vdf::Node* item = details->find(id);
    if (!item) return false;  // Steam keeps no details for it: no account here subscribes
    if (!item->block) return std::nullopt;
    const vdf::Node* by = item->find("subscribedby");
    if (!by) return false;  // what a download without a subscription leaves (RESEARCH.md)
    if (by->block) return std::nullopt;
    return subscribed_by_an_account(by->value);
  };

  const auto workshop = [&](const std::string& id, bool content_only) {
    Candidate c{Source::workshop, id, {}, {}, {}, {}};
    c.content_only = content_only;
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
      const bool recorded = (installed && installed->find(id)) || (details && details->find(id));
      if (content_only && subscription(id) == false) {
        // Content without the allowlist comes only from a subscription (ADR 0111). Steam's record
        // names no subscriber here: a server or the game downloaded the item, or the user
        // unsubscribed. Removed like an unsubscribed item (ADR 0025); the allowlist is unaffected.
        c.unsubscribed = true;
        c.problem = std::string(!recorded && !is_dir(folder) ? kGone : kNotSubscribed);
      } else if (!is_dir(folder) && app && !recorded) {
        // Steam lists it nowhere and its files are gone: the user unsubscribed (ADR 0025).
        c.unsubscribed = true;
        c.problem = std::string(kGone);
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
    return c;
  };
  for (const std::string& id : config.workshop) out.push_back(workshop(id, false));
  if (!subscribed) return out;

  // Every other subscribed item whose single .gma is a package, and every other deployed one, by id.
  const std::set<std::string> listed(config.workshop.begin(), config.workshop.end());
  const auto workshop_id = [](const std::string& name) {
    return !name.empty() && name.size() <= 20 && name[0] != '0' &&
           std::all_of(name.begin(), name.end(), [](char ch) { return ch >= '0' && ch <= '9'; });
  };
  std::set<std::string> found;
  std::error_code ec;
  for (const auto& entry : fs::directory_iterator(*env.workshop_content, ec)) {
    const std::string id = utf8(entry.path().filename());
    if (!workshop_id(id) || listed.count(id) || !is_dir(entry.path())) continue;
    const bool deployed = env.deployed_workshop.count(id) > 0;
    if (env.disabled_workshop.count(id) && !deployed) continue;
    // Installed is not subscribed (ADR 0111): any server can make the game download an item here.
    // Only an item Steam's record shows an account of this computer subscribed to is new content;
    // without a readable record nothing is, and the deployed ones keep their candidates below.
    if (!deployed && subscription(id) != true) continue;
    std::vector<fs::path> archives;
    std::error_code inner;
    for (const auto& file : fs::directory_iterator(entry.path(), inner)) {
      if (ends_with_folded(utf8(file.path().filename()), ".gma") && is_file(file.path())) archives.push_back(file.path());
    }
    if (archives.size() == 1 && lists_native_manifest(archives.front())) found.insert(id);
  }
  for (const std::string& id : env.deployed_workshop) {
    if (workshop_id(id) && !listed.count(id)) found.insert(id);
  }
  std::vector<std::string> order(found.begin(), found.end());
  std::sort(order.begin(), order.end(), [](const std::string& a, const std::string& b) {
    return a.size() != b.size() ? a.size() < b.size() : a < b;  // numeric: no leading zeros
  });
  for (const std::string& id : order) out.push_back(workshop(id, true));
  return out;
}

bool lists_native_manifest(const fs::path& archive) {
  try {
    gma::FileSource source(archive);
    const gma::Index index = gma::read_index(source);
    return std::any_of(index.entries.begin(), index.entries.end(),
                       [](const gma::Entry& e) { return paths::fold(e.path) == manifest::kManifestPath; });
  } catch (const std::exception&) {
    return false;  // unreadable, not a GMAD archive, or beyond the reader's limits
  }
}

}  // namespace nl::discovery
