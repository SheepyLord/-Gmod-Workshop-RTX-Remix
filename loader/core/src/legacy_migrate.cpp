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
#include <utility>

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
constexpr std::size_t kNamed = 3;  // paths a note names before it counts the rest

bool protected_file(std::string_view path) {
  const auto folded = paths::fold(path);
  return folded == "user.conf" || folded.ends_with("/user.conf");
}

// True if `relative` passes through a link (junction, symbolic link, mount point) below `base`.
// Links are checked below the folder the caller trusts, as everywhere the deployer works; the game
// root itself may be reached through one (a library on another drive).
bool linked(const Path& base, std::string_view relative) {
  try {
    fs::refuse_links(base, relative);
    return false;
  } catch (const fs::Error&) {
    return true;
  }
}

// An external recovery root (an explicit --legacy-source, Steam's registered install), checked as
// given: '.' and '..' are refused before absolute() resolves them away, and no component of its
// absolute path, from the volume root, may be a link, so recovery never reads through the
// launcher's directory links into some other game.
void external(const Path& path) {
  for (const auto& part : path) {
    if (part == L"." || part == L"..") throw std::runtime_error("legacy recovery source contains '.' or '..': " + fs::utf8(path));
  }
  const auto absolute = std::filesystem::absolute(path);
  const auto below = absolute.relative_path().generic_u8string();
  if (linked(absolute.root_path(), std::string(below.begin(), below.end())))
    throw std::runtime_error("legacy recovery source passes through a link: " + fs::utf8(path));
}

// The file at `base`/`relative` is an ordinary file with exactly this size and SHA-256. A path
// through a link below `base` never matches: it is not followed.
bool matches(const Path& base, std::string_view relative, std::uint64_t size, std::string_view sha256) {
  if (linked(base, relative)) return false;
  const auto at = fs::join(base, relative);
  const auto s = fs::stat(at);
  return s.exists && !s.directory && !s.link && s.size == size && fs::hash_file(at).sha256 == sha256;
}

// What the scan of the game root finds: the files it archives, and what it leaves where it is.
struct Scan {
  const Path& root;
  const std::set<std::string>& owned;
  std::map<std::string, SavedFile> files;  // by folded path
  std::vector<std::string> links;          // never followed, and never moved
  std::vector<std::string> unusual;        // a folder where a file belongs (or the reverse), a name Windows aliases
};

void add_file(Scan& scan, std::string path) {
  if (protected_file(path) || scan.owned.count(paths::fold(path))) return;
  // A transaction step must pass the journal's path rules, so such a name stays where it is.
  if (!paths::is_safe(path)) {
    scan.unusual.push_back(std::move(path));
    return;
  }
  if (linked(scan.root, path)) {
    scan.links.push_back(std::move(path));
    return;
  }
  const auto at = fs::join(scan.root, path);
  const auto s = fs::stat(at);
  if (!s.exists) return;
  if (s.directory) {
    scan.unusual.push_back(std::move(path));
    return;
  }
  std::string key = paths::fold(path);
  if (scan.files.count(key)) return;
  if (scan.files.size() >= kMaxFiles) throw std::runtime_error("legacy installation has too many files to migrate");
  auto hash = fs::hash_file(at);
  scan.files.emplace(std::move(key), SavedFile{std::move(path), std::move(hash), {}, {}, {}});
}

// A link inside a catalogued root (RTXLauncher's Mount HL2 RTX links mount-hl2rtx/models,
// materials and maps to another game) is neither followed nor archived: it stays, with a note.
void add_tree(Scan& scan, const std::string& relative, std::size_t depth = 0) {
  if (depth > 64) throw std::runtime_error("legacy add-on nesting exceeds 64 directories");
  if (linked(scan.root, relative)) {
    scan.links.push_back(relative);
    return;
  }
  const auto s = fs::stat(fs::join(scan.root, relative));
  if (!s.exists) return;
  if (!s.directory) {
    scan.unusual.push_back(relative);
    return;
  }
  for (const auto& item : fs::list(fs::join(scan.root, relative))) {
    std::string child = relative + "/" + fs::utf8(item.name);
    if (item.link) scan.links.push_back(std::move(child));
    else if (item.directory) add_tree(scan, child, depth + 1);
    else add_file(scan, std::move(child));
  }
}

// One note for the paths of the former installation the scan leaves where they are.
std::string left_note(const std::vector<std::string>& left, std::string_view why) {
  std::string named;
  for (std::size_t i = 0; i < left.size() && i < kNamed; ++i) named += (i ? ", " : "") + left[i];
  if (left.size() > kNamed) named += " and " + std::to_string(left.size() - kNamed) + " more";
  return named + ": left in place; " + std::string(why);
}

// Where stock copies may come from: an external root, or a folder of the launcher's below the game
// root (`below`: its path relative to the root, which is what the manifest records).
struct Source {
  Path base;
  std::string below;
};

std::vector<Source> sources(const Path& root, const std::optional<Path>& supplied) {
  std::vector<Source> out;
  if (supplied) {
    external(*supplied);
    if (!fs::stat(*supplied).directory) throw std::runtime_error("legacy stock source is not a directory");
    out.push_back({*supplied, {}});
  }
  // A separate vanilla Steam install is useful when RTXLauncher copied the game outside Steam.
  // Registry/discovery failures merely leave the verified local backups as candidates.
  if (!supplied) try {
    const auto env = discovery::environment_for(root);
    if (env.workshop_content) {
      const auto steamapps = env.workshop_content->parent_path().parent_path().parent_path();
      const auto appmanifest = steamapps / L"appmanifest_4000.acf";
      external(appmanifest);
      const auto tree = vdf::load(appmanifest);
      const auto* app = tree.find("AppState");
      const auto* id = app ? app->find("appid") : nullptr;
      const auto* dir = app ? app->find("installdir") : nullptr;
      if (id && !id->block && id->value == "4000" && dir && !dir->block && paths::is_safe(dir->value) &&
          dir->value.find('/') == std::string::npos && dir->value.find('\\') == std::string::npos) {
        const auto candidate = fs::join(steamapps / L"common", dir->value);
        external(candidate);
        if (fs::stat(candidate).directory) out.push_back({candidate, {}});
      }
    }
  } catch (const std::exception&) {
    // A missing or untrusted source is never used. The planner fails if recovery actually needs it.
  }
  // The launcher's own backups are below the game root: links are refused below it, as for any file there.
  for (const auto& item : fs::list(root)) {
    const std::string name = fs::utf8(item.name);
    if (item.directory && !item.link && name.starts_with("backup_patches_")) out.push_back({root / item.name, name});
  }
  return out;
}

// The verified stock copy of `file`, and how the manifest names it.
std::pair<Path, std::string> recovery(const Path& root, const std::vector<Source>& candidates, const DepotFile& file) {
  for (const auto& source : candidates) {
    if (!matches(source.base, file.path, file.size, file.sha256)) continue;
    const auto at = fs::join(source.base, file.path);
    return {at, source.below.empty() ? fs::utf8(at) : source.below + "/" + file.path};
  }
  if (matches(root, file.path + ".bak", file.size, file.sha256)) return {fs::join(root, file.path + ".bak"), file.path + ".bak"};
  throw std::runtime_error("legacy migration needs a verified vanilla copy of " + file.path +
                           "; no files were replaced. Verify the Steam install or use nlctl apply --legacy-source <vanilla root>");
}
}  // namespace

const Catalog& builtin_catalog() {
  static const Catalog catalog = [] {
    Catalog c;
    c.build = std::string(stock::kBuild);
    for (const auto& file : stock::kFiles) {
      c.files.push_back({std::string(file.path), file.size, std::string(file.sha256), std::string(file.legacy_sha256)});
    }
    for (const auto& file : stock::kBuildFiles) c.anchors.push_back({std::string(file.path), file.size, std::string(file.sha256), {}});
    return c;
  }();
  return catalog;
}

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
  return plan(root, owned, transaction, source, builtin_catalog());
}

Migration plan(const Path& root, const std::set<std::string>& owned, std::uint64_t transaction,
               const std::optional<Path>& source, const Catalog& catalog) {
  for (const auto& file : catalog.files) {
    if (std::none_of(stock::kFiles.begin(), stock::kFiles.end(),
                     [&](const stock::File& known) { return paths::fold(known.path) == paths::fold(file.path); }))
      throw std::invalid_argument("a legacy catalog may only describe the built-in catalog's depot files, not " + file.path);
  }
  for (const auto& anchor : catalog.anchors) {
    if (!paths::is_safe(anchor.path)) throw std::invalid_argument("unsafe legacy build anchor: " + anchor.path);
  }
  Migration result;
  // Only below the game root, and only for these entries: a root reached through a junction is
  // ordinary, and a linked entry (a symbolic-link DXVK or ReShade d3d9.dll) is not Remix.
  std::set<std::string> runtime_roots;
  for (const auto base : kRuntimeRoots) {
    for (const auto entry : kEntries) {
      const std::string path = std::string(base) + "/" + std::string(entry);
      if (!owned.count(paths::fold(path)) && is_remix_runtime(root, path)) runtime_roots.emplace(base);
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
  Scan scan{root, owned, {}, {}, {}};
  for (const auto& base : runtime_roots) {
    for (const auto file : stock::kRuntimeFiles) {
      const auto path = base + "/" + std::string(file);
      // An inactive Remix may sit next to an unrelated active D3D proxy. Preserve that proxy.
      if (file == "d3d9.dll" && !is_remix_runtime(root, path)) continue;
      add_file(scan, path);
    }
    for (const auto entry : kEntries) {
      const auto path = base + "/" + std::string(entry);
      if (is_remix_runtime(root, path)) add_file(scan, path);
    }
  }
  for (const auto path : kConfigs) add_file(scan, std::string(path));
  for (const auto path : kLooseFiles) add_file(scan, std::string(path));
  for (const auto path : stock::kAddonRoots) add_tree(scan, std::string(path));
  for (const auto path : stock::kModRoots) add_tree(scan, std::string(path));

  // Factory launcher configs force RTX-only cvars even in a later vanilla session. An edited
  // config belongs to the player: retain it and report it instead of discarding personal binds.
  constexpr stock::File configs[] = {
      {"garrysmod/cfg/autoexec.cfg", 653, "c14ab289beef45771f9b71d401ccbe9717b7d5d49d349fc55dcd10d88074fdf2", ""},
      {"garrysmod/cfg/client.vdf", 343, "86bcd0b0772ea4090bb14bcf89be2c7e68444cea65c1615cc8915b040befbdce", ""},
      {"garrysmod/cfg/server.vdf", 376, "bb6600d80a4ffde055d4fc9839b226e01bd66e8b739b2ce872d6eccf2766dff3", ""}};
  for (const auto& file : configs) {
    const std::string path(file.path);
    if (linked(root, path)) scan.links.push_back(path);
    else if (matches(root, path, file.size, file.sha256)) add_file(scan, path);
    else if (fs::stat(fs::join(root, path)).exists)
      result.notes.push_back(path + ": custom config retained; any RTX-specific commands in it remain active");
  }

  // Steam's files are rule 2's one exception: recognized edits of the catalogued build go back to
  // verified stock bytes, all of them or none. On another build, or beside a change the catalog
  // cannot account for, every depot file stays as it is, the rest is archived all the same, and
  // Steam's verification repairs them. A missing stock copy stops the migration instead (thrown):
  // with the old runtime still in place, a later start or --legacy-source can still complete it.
  const auto candidates = sources(root, source);
  std::vector<const DepotFile*> edited;
  std::string unknown;  // the first depot file the catalog cannot account for, and why
  for (const auto& file : catalog.files) {
    if (owned.count(paths::fold(file.path))) continue;
    if (linked(root, file.path)) {
      if (unknown.empty()) unknown = file.path + " is reached through a link";
      continue;
    }
    const auto at = fs::join(root, file.path);
    const auto s = fs::stat(at);
    if (!s.exists) continue;
    const auto hash = s.directory ? std::string() : fs::hash_file(at).sha256;
    if (hash == file.sha256) continue;
    if (hash == file.legacy_sha256) edited.push_back(&file);
    else if (unknown.empty()) unknown = file.path + (s.directory ? " is a folder" : " holds changes the loader does not recognize");
  }
  if (!edited.empty() || !unknown.empty()) {
    // The build first: a newer build's stock files are unknown to the catalog, not edits.
    std::string kept;  // why every depot file stays as it is
    for (const auto& anchor : catalog.anchors) {
      if (!matches(root, anchor.path, anchor.size, anchor.sha256)) {
        kept = "this is not GMod build " + catalog.build + " as the loader knows it (" + anchor.path + " differs)";
        break;
      }
    }
    if (kept.empty()) kept = unknown;
    if (!kept.empty()) {
      result.notes.push_back("Steam's files stay as they are, because " + kept +
                             "; verify this install in Steam to undo any change to them");
    } else {
      for (const auto* file : edited) {
        auto [from, named] = recovery(root, candidates, *file);
        add_file(scan, file->path);
        const auto saved = scan.files.find(paths::fold(file->path));
        if (saved == scan.files.end()) throw std::runtime_error(file->path + " changed while the legacy migration was planned");
        saved->second.stock_source = std::move(from);
        saved->second.source = std::move(named);
        saved->second.stock = {file->sha256, file->size};
      }
    }
  }
  for (auto& [key, file] : scan.files) { (void)key; result.files.push_back(std::move(file)); }
  if (!scan.links.empty()) result.notes.push_back(left_note(scan.links, "the loader never follows or moves a link"));
  if (!scan.unusual.empty()) result.notes.push_back(left_note(scan.unusual, "not an ordinary file the loader can archive"));
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
                                          ", \"source\": " + json::quote(file.source);
    out += "}";
  }
  return out + "\n  ]\n}\n";
}
}  // namespace nl::legacy
