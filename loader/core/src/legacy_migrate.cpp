#include "nl/legacy_migrate.h"

#include "legacy_stock_data.h"
#include "nl/discovery.h"
#include "nl/json.h"
#include "nl/legacy_detect.h"
#include "nl/paths.h"
#include "nl/vdf.h"

#include <algorithm>
#include <map>
#include <stdexcept>

namespace nl::legacy {
namespace {
using Path = std::filesystem::path;
constexpr std::string_view kRuntimeRoots[] = {"bin/win64", "bin/win64/.trex"};
constexpr std::string_view kEntries[] = {"d3d9.dll", "d3d9.dll.disabled", "d3d9_remix.dll"};
constexpr std::string_view kConfigs[] = {"rtx.conf", "dxvk.conf"};
constexpr std::string_view kLooseFiles[] = {
    "garrysmod/lua/bin/gmcl_rtxfixesbinary_win32.dll", "garrysmod/lua/bin/gmcl_rtxfixesbinary_win64.dll",
    "bin/win64/stdshader_dx6.pdb", "bin/win64/stdshader_dx6_readme.txt",
    "bin/win64/astra-startup/astra_rtx_prepare_assets.exe", "bin/win64/astra-startup/proxy_renderer_exports.json",
    "bin/win64/astra-startup/d3d9.dll", "bin/win64/astra-startup/README.md",
    "bin/win64/astra-startup/generate_proxy_exports.py"};
constexpr std::size_t kMaxFiles = 100000;

bool protected_file(std::string_view path) {
  const auto folded = paths::fold(path);
  return folded == "user.conf" || folded.ends_with("/user.conf");
}

// Check every ancestor, including the external source's root. External recovery may never read
// through the launcher's directory links into some other game, or accept a .. path.
void ordinary(const Path& path) {
  const auto absolute = std::filesystem::absolute(path);
  for (const auto& component : absolute) {
    if (component == L"..") throw std::runtime_error("legacy recovery source contains '..'");
  }
  Path at;
  for (const auto& component : absolute) {
    at /= component;
    if (fs::stat(at).link) throw std::runtime_error("legacy migration refuses a linked path: " + fs::utf8(at));
  }
}

bool matches(const Path& path, const stock::File& expected) {
  ordinary(path);
  const auto s = fs::stat(path);
  return s.exists && !s.directory && !s.link && s.size == expected.size && fs::hash_file(path).sha256 == expected.sha256;
}

void add_file(const Path& root, std::string path, const std::set<std::string>& owned,
              std::map<std::string, SavedFile>& files) {
  if (protected_file(path) || owned.count(paths::fold(path))) return;
  if (!paths::is_safe(path)) throw std::runtime_error("unsafe legacy path: " + path);
  fs::refuse_links(root, path);
  const auto s = fs::stat(fs::join(root, path));
  if (!s.exists) return;
  if (s.directory) throw std::runtime_error("legacy file is a directory: " + path);
  const std::string key = paths::fold(path);
  if (files.count(key)) return;
  if (files.size() >= kMaxFiles) throw std::runtime_error("legacy installation has too many files to migrate");
  auto hash = fs::hash_file(fs::join(root, path));
  files.emplace(key, SavedFile{std::move(path), std::move(hash), {}, {}, {}});
}

void add_tree(const Path& root, const std::string& relative, const std::set<std::string>& owned,
              std::map<std::string, SavedFile>& files, std::size_t depth = 0) {
  if (depth > 64) throw std::runtime_error("legacy add-on nesting exceeds 64 directories");
  fs::refuse_links(root, relative);
  const auto s = fs::stat(fs::join(root, relative));
  if (!s.exists) return;
  if (!s.directory) throw std::runtime_error("legacy add-on root is not a directory: " + relative);
  for (const auto& item : fs::list(fs::join(root, relative))) {
    const std::string child = relative + "/" + fs::utf8(item.name);
    if (item.link) throw std::runtime_error("legacy migration refuses a linked path: " + child);
    if (item.directory) add_tree(root, child, owned, files, depth + 1);
    else add_file(root, child, owned, files);
  }
}

std::vector<Path> sources(const Path& root, const std::optional<Path>& supplied) {
  std::vector<Path> out;
  if (supplied) {
    ordinary(*supplied);
    if (!fs::stat(*supplied).directory) throw std::runtime_error("legacy stock source is not a directory");
    out.push_back(*supplied);
  }
  // A separate vanilla Steam install is useful when RTXLauncher copied the game outside Steam.
  // Registry/discovery failures merely leave the verified local backups as candidates.
  if (!supplied) try {
    const auto env = discovery::environment_for(root);
    if (env.workshop_content) {
      const auto steamapps = env.workshop_content->parent_path().parent_path().parent_path();
      const auto appmanifest = steamapps / L"appmanifest_4000.acf";
      ordinary(appmanifest);
      const auto tree = vdf::load(appmanifest);
      const auto* app = tree.find("AppState");
      const auto* id = app ? app->find("appid") : nullptr;
      const auto* dir = app ? app->find("installdir") : nullptr;
      if (id && !id->block && id->value == "4000" && dir && !dir->block && paths::is_safe(dir->value) &&
          dir->value.find('/') == std::string::npos && dir->value.find('\\') == std::string::npos) {
        const auto candidate = fs::join(steamapps / L"common", dir->value);
        ordinary(candidate);
        if (fs::stat(candidate).directory) out.push_back(candidate);
      }
    }
  } catch (const std::exception&) {
    // A missing or untrusted source is never used. The planner fails if recovery actually needs it.
  }
  for (const auto& item : fs::list(root)) {
    const std::string name = fs::utf8(item.name);
    if (item.directory && !item.link && name.starts_with("backup_patches_")) out.push_back(root / item.name);
  }
  return out;
}

Path recovery(const Path& root, const std::vector<Path>& candidates, const stock::File& file) {
  for (const auto& base : candidates) {
    const Path at = fs::join(base, file.path);
    if (matches(at, file)) return at;
  }
  const auto sibling = Path(fs::join(root, file.path).native() + L".bak");
  if (matches(sibling, file)) return sibling;
  throw std::runtime_error("legacy migration needs a verified vanilla copy of " + std::string(file.path) +
                           "; no files were replaced. Verify the Steam install or use nlctl apply --legacy-source <vanilla root>");
}
}  // namespace

bool step_path(std::string_view path) {
  const auto key = paths::fold(path);
  for (const auto file : kLooseFiles) if (key == paths::fold(file)) return true;
  for (const auto& file : stock::kFiles) if (key == paths::fold(file.path)) return true;
  for (const auto base : kRuntimeRoots) {
    for (const auto file : stock::kRuntimeFiles) if (key == paths::fold(std::string(base) + "/" + std::string(file))) return true;
    for (const auto file : kEntries) if (key == std::string(base) + "/" + std::string(file)) return true;
  }
  for (const auto file : kConfigs) if (key == file) return true;
  // Only these known factory configs can be removed; the planner additionally checks their hash.
  return key == "garrysmod/cfg/autoexec.cfg" || key == "garrysmod/cfg/client.vdf" || key == "garrysmod/cfg/server.vdf";
}

bool installed_path(std::string_view path) {
  if (protected_file(path)) return false;
  if (step_path(path)) return true;
  for (const auto base : stock::kAddonRoots) if (paths::within(path, base)) return true;
  for (const auto base : stock::kModRoots) if (paths::within(path, base)) return true;
  return false;
}

Migration plan(const Path& root, const std::set<std::string>& owned, std::uint64_t transaction,
               const std::optional<Path>& source) {
  Migration result;
  ordinary(root);
  std::set<std::string> runtime_roots;
  for (const auto base : kRuntimeRoots) {
    for (const auto entry : kEntries) {
      const std::string path = std::string(base) + "/" + std::string(entry);
      if (owned.count(paths::fold(path))) continue;
      fs::refuse_links(root, path);
      if (is_remix_runtime(fs::join(root, path))) runtime_roots.emplace(base);
    }
  }
  if (runtime_roots.empty()) return result;
  result.archive = std::string(kBackups) + "/" + std::to_string(transaction);
  // Uninstall removes the generation journal while permanent legacy archives stay. A subsequent
  // migration may start at transaction 1 again; choose a new folder instead of reusing its backup.
  for (unsigned suffix = 1;; ++suffix) {
    if (suffix > 10000) throw std::runtime_error("too many prior legacy backup folders");
    const std::string candidate = std::string(kBackups) + "/" + std::to_string(transaction) +
                                  (suffix == 1 ? "" : "-" + std::to_string(suffix));
    fs::refuse_links(root, candidate);
    if (!fs::stat(fs::join(root, candidate)).exists) { result.archive = candidate; break; }
  }
  std::map<std::string, SavedFile> files;
  for (const auto& base : runtime_roots) {
    for (const auto file : stock::kRuntimeFiles) {
      const auto path = base + "/" + std::string(file);
      // An inactive Remix may sit next to an unrelated active D3D proxy. Preserve that proxy.
      if (file == "d3d9.dll" && !is_remix_runtime(fs::join(root, path))) continue;
      add_file(root, path, owned, files);
    }
    for (const auto entry : kEntries) {
      const auto path = base + "/" + std::string(entry);
      if (is_remix_runtime(fs::join(root, path))) add_file(root, path, owned, files);
    }
  }
  for (const auto path : kConfigs) add_file(root, std::string(path), owned, files);
  for (const auto path : kLooseFiles) add_file(root, std::string(path), owned, files);
  for (const auto path : stock::kAddonRoots) add_tree(root, std::string(path), owned, files);
  for (const auto path : stock::kModRoots) add_tree(root, std::string(path), owned, files);

  // Factory launcher configs force RTX-only cvars even in a later vanilla session. An edited
  // config belongs to the player: retain it and report it instead of discarding personal binds.
  constexpr stock::File configs[] = {
      {"garrysmod/cfg/autoexec.cfg", 653, "c14ab289beef45771f9b71d401ccbe9717b7d5d49d349fc55dcd10d88074fdf2", ""},
      {"garrysmod/cfg/client.vdf", 343, "86bcd0b0772ea4090bb14bcf89be2c7e68444cea65c1615cc8915b040befbdce", ""},
      {"garrysmod/cfg/server.vdf", 376, "bb6600d80a4ffde055d4fc9839b226e01bd66e8b739b2ce872d6eccf2766dff3", ""}};
  for (const auto& file : configs) {
    if (matches(fs::join(root, file.path), file)) add_file(root, std::string(file.path), owned, files);
    else if (fs::stat(fs::join(root, file.path)).exists)
      result.notes.push_back(std::string(file.path) + ": custom config retained; any RTX-specific commands in it remain active");
  }

  const auto candidates = sources(root, source);
  bool build_checked = false;
  for (const auto& file : stock::kFiles) {
    const auto target = fs::join(root, file.path);
    fs::refuse_links(root, file.path);
    const auto s = fs::stat(target);
    if (!s.exists || owned.count(paths::fold(file.path))) continue;
    const auto before = fs::hash_file(target);
    if (before.sha256 == file.sha256) continue;
    if (before.sha256 != file.legacy_sha256) {
      throw std::runtime_error("legacy migration cannot identify the edited Steam file " + std::string(file.path) +
                               "; nothing was replaced. Verify this install in Steam first");
    }
    if (!build_checked) {
      // A patched old DLL can be copied into a newer game. Exact unmodified executable/client/
      // server anchors prevent combining this catalog's recovered bytes with another build.
      for (const auto& anchor : stock::kBuildFiles) {
        if (!matches(fs::join(root, anchor.path), anchor))
          throw std::runtime_error("legacy migration cannot confirm GMod build " + std::string(stock::kBuild) +
                                   "; verify this install in Steam before replacing its files");
      }
      build_checked = true;
    }
    const auto from = recovery(root, candidates, file);
    add_file(root, std::string(file.path), owned, files);
    auto& saved = files.at(paths::fold(file.path));
    saved.stock_source = from;
    saved.stock = {std::string(file.sha256), file.size};
  }
  for (auto& [key, file] : files) { (void)key; result.files.push_back(std::move(file)); }
  result.notes.push_back("previous RTX Remix installation archived at " + result.archive +
                          "; user.conf and unrelated user files are preserved. This archive stays after uninstall");
  return result;
}

std::string backup_manifest(const Migration& migration) {
  std::string out = "{\n  \"schema\": 1,\n  \"reason\": \"previous RTX Remix installation\",\n  \"files\": [";
  bool first = true;
  for (const auto& file : migration.files) {
    out += first ? "\n    {" : ",\n    {";
    first = false;
    out += "\"path\": " + json::quote(file.path) + ", \"sha256\": " + json::quote(file.before.sha256) +
           ", \"size\": " + std::to_string(file.before.size);
    if (!file.restore_target.empty()) out += ", \"restore_target\": " + json::quote(file.restore_target);
    if (!file.stock_source.empty()) out += ", \"restored_stock_sha256\": " + json::quote(file.stock.sha256) +
                                          ", \"source\": " + json::quote(fs::utf8(file.stock_source));
    out += "}";
  }
  return out + "\n  ]\n}\n";
}
}  // namespace nl::legacy
