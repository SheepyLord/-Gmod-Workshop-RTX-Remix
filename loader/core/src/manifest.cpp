#include "nl/manifest.h"

#include "nl/json.h"
#include "nl/utf8.h"

#include <algorithm>
#include <charconv>
#include <initializer_list>
#include <map>
#include <set>

namespace nl::manifest {

namespace {

using json::Value;

[[noreturn]] void fail(const std::string& message) {
  throw Error("manifest: " + message);
}

void only_keys(const Value& object, std::string_view where, std::initializer_list<std::string_view> allowed) {
  for (const auto& [key, value] : object.as_object(where)) {
    if (std::find(allowed.begin(), allowed.end(), key) == allowed.end()) {
      fail("unknown key \"" + key + "\" in " + std::string(where));
    }
  }
}

const Value& required(const Value& object, std::string_view key) {
  const Value* value = object.find(key);
  if (!value) fail("missing \"" + std::string(key) + "\"");
  return *value;
}

bool valid_id(std::string_view id) {
  if (id.empty() || id.size() > 64) return false;
  if (!((id[0] >= 'a' && id[0] <= 'z') || (id[0] >= '0' && id[0] <= '9'))) return false;
  return std::all_of(id.begin(), id.end(), [](char c) { return (c >= 'a' && c <= 'z') || (c >= '0' && c <= '9') || c == '-'; });
}

bool is_hex64(std::string_view text) {
  return text.size() == 64 &&
         std::all_of(text.begin(), text.end(), [](char c) { return (c >= '0' && c <= '9') || (c >= 'a' && c <= 'f'); });
}

bool numeric_identifier(std::string_view s) {
  return !s.empty() && std::all_of(s.begin(), s.end(), [](char c) { return c >= '0' && c <= '9'; });
}

bool valid_identifier(std::string_view s) {
  return !s.empty() && std::all_of(s.begin(), s.end(), [](char c) {
    return (c >= '0' && c <= '9') || (c >= 'a' && c <= 'z') || (c >= 'A' && c <= 'Z') || c == '-';
  });
}

std::optional<std::uint64_t> parse_number_part(std::string_view s) {
  if (!numeric_identifier(s) || (s.size() > 1 && s[0] == '0')) return std::nullopt;
  std::uint64_t value = 0;
  const auto [end, ec] = std::from_chars(s.data(), s.data() + s.size(), value);
  if (ec != std::errc() || end != s.data() + s.size()) return std::nullopt;
  return value;
}

std::vector<std::string_view> split(std::string_view text, char sep) {
  std::vector<std::string_view> parts;
  std::size_t start = 0;
  for (;;) {
    const std::size_t at = text.find(sep, start);
    parts.push_back(text.substr(start, at == std::string_view::npos ? std::string_view::npos : at - start));
    if (at == std::string_view::npos) return parts;
    start = at + 1;
  }
}

std::string payload_path(std::string_view relative) {
  return "native/payload/" + std::string(relative);
}

// Launch arguments a package may add (schema 1): an explicit list, so a package cannot slip in
// commands such as +exec.
void check_launch_args(const std::vector<std::string>& args) {
  for (std::size_t i = 0; i < args.size(); ++i) {
    const std::string& a = args[i];
    if (a == "-nod3d9ex" || a == "-insecure") continue;
    if (a == "-dxlevel" || a == "+mat_disable_d3d9ex") {
      if (i + 1 >= args.size() || args[i + 1].empty() || args[i + 1].size() > 3 ||
          !std::all_of(args[i + 1].begin(), args[i + 1].end(), [](char c) { return c >= '0' && c <= '9'; })) {
        fail("launch argument \"" + a + "\" needs a number after it");
      }
      ++i;
      continue;
    }
    fail("launch argument \"" + a + "\" is not allowed (schema 1 allows -dxlevel N, -nod3d9ex, -insecure, +mat_disable_d3d9ex N)");
  }
}

bool valid_env_name(std::string_view name) {
  const auto rest = [&](std::size_t from) {
    const std::string_view tail = name.substr(from);
    return !tail.empty() && tail.size() <= 64 &&
           std::all_of(tail.begin(), tail.end(), [](char c) { return (c >= 'A' && c <= 'Z') || (c >= '0' && c <= '9') || c == '_'; });
  };
  if (name.substr(0, 5) == "DXVK_") return rest(5);
  if (name.substr(0, 4) == "RTX_") return rest(4);
  return false;
}

std::vector<std::string> string_list(const Value& value, std::string_view what) {
  std::vector<std::string> out;
  for (const Value& item : value.as_array(what)) out.push_back(item.as_string(std::string(what) + " entries"));
  return out;
}

// Paths of files the loader deploys or loads. They must also be ASCII: NTFS compares names without
// case for every letter, the loader only for ASCII ones (paths::fold), and two spellings of one name
// would make the loader's own file look like someone else's.
std::string safe_path(const std::string& path, std::string_view what) {
  const std::string reason = paths::problem(path);
  if (!reason.empty()) fail(std::string(what) + " \"" + path + "\": " + reason);
  if (std::any_of(path.begin(), path.end(), [](char c) { return static_cast<unsigned char>(c) >= 0x80; })) {
    fail(std::string(what) + " \"" + path + "\" must be ASCII");
  }
  return path;
}

bool lower_hex(char c) { return (c >= '0' && c <= '9') || (c >= 'a' && c <= 'f'); }

int hex_value(char c) { return c <= '9' ? c - '0' : c - 'a' + 10; }

bool snake_name(std::string_view name) {
  return !name.empty() && name.size() <= 64 &&
         std::all_of(name.begin(), name.end(), [](char c) { return (c >= 'a' && c <= 'z') || (c >= '0' && c <= '9') || c == '_'; });
}

std::size_t as_size(const Value& value, std::string_view what) {
  const std::int64_t n = value.as_int(what);
  if (n < 0) fail(std::string(what) + " is negative");
  return static_cast<std::size_t>(n);
}

}  // namespace

bool valid_module_name(std::string_view name) {
  if (name.size() < 5 || name.size() > 64 || name.substr(name.size() - 4) != ".dll") return false;
  const std::string_view stem = name.substr(0, name.size() - 4);
  return std::all_of(stem.begin(), stem.end(), [](char c) { return (c >= 'a' && c <= 'z') || (c >= '0' && c <= '9') || c == '_'; });
}

bool valid_cvar_name(std::string_view name) {
  return !name.empty() && name.size() <= 64 && std::all_of(name.begin(), name.end(), [](char c) {
    return (c >= 'a' && c <= 'z') || (c >= 'A' && c <= 'Z') || (c >= '0' && c <= '9') || c == '_';
  });
}

bool valid_cvar_value(std::string_view value) {
  return value.size() <= 32 && std::all_of(value.begin(), value.end(), [](char c) {
    return (c >= 'a' && c <= 'z') || (c >= 'A' && c <= 'Z') || (c >= '0' && c <= '9') || c == '_' || c == '.' || c == '+' || c == '-';
  });
}

std::vector<int> parse_pattern(std::string_view text) {
  if (text.empty() || text.size() % 2 || text.size() > 512) return {};
  std::vector<int> bytes;
  bool concrete = false;
  for (std::size_t i = 0; i < text.size(); i += 2) {
    if (text[i] == '?' && text[i + 1] == '?') {
      bytes.push_back(-1);
      continue;
    }
    if (!lower_hex(text[i]) || !lower_hex(text[i + 1])) return {};
    bytes.push_back(hex_value(text[i]) * 16 + hex_value(text[i + 1]));
    concrete = true;
  }
  return concrete ? bytes : std::vector<int>{};
}

std::vector<std::uint8_t> parse_hex(std::string_view text) {
  if (text.empty() || text.size() % 2 || text.size() > 512) return {};
  std::vector<std::uint8_t> bytes;
  for (std::size_t i = 0; i < text.size(); i += 2) {
    if (!lower_hex(text[i]) || !lower_hex(text[i + 1])) return {};
    bytes.push_back(static_cast<std::uint8_t>(hex_value(text[i]) * 16 + hex_value(text[i + 1])));
  }
  return bytes;
}

std::optional<Version> parse_version(std::string_view text) {
  if (text.empty() || text.size() > 128) return std::nullopt;
  Version v;
  v.text = std::string(text);
  std::string_view core = text;
  if (const std::size_t plus = core.find('+'); plus != std::string_view::npos) {
    const std::string_view build = core.substr(plus + 1);
    for (const auto part : split(build, '.')) {
      if (!valid_identifier(part)) return std::nullopt;
    }
    v.build = std::string(build);
    core = core.substr(0, plus);
  }
  if (const std::size_t dash = core.find('-'); dash != std::string_view::npos) {
    for (const auto part : split(core.substr(dash + 1), '.')) {
      if (!valid_identifier(part)) return std::nullopt;
      if (numeric_identifier(part) && part.size() > 1 && part[0] == '0') return std::nullopt;
      v.prerelease.emplace_back(part);
    }
    core = core.substr(0, dash);
  }
  const auto numbers = split(core, '.');
  if (numbers.size() != 3) return std::nullopt;
  const auto major = parse_number_part(numbers[0]);
  const auto minor = parse_number_part(numbers[1]);
  const auto patch = parse_number_part(numbers[2]);
  if (!major || !minor || !patch) return std::nullopt;
  v.major = *major;
  v.minor = *minor;
  v.patch = *patch;
  return v;
}

int compare(const Version& a, const Version& b) {
  if (a.major != b.major) return a.major < b.major ? -1 : 1;
  if (a.minor != b.minor) return a.minor < b.minor ? -1 : 1;
  if (a.patch != b.patch) return a.patch < b.patch ? -1 : 1;
  if (a.prerelease.empty() != b.prerelease.empty()) return a.prerelease.empty() ? 1 : -1;
  for (std::size_t i = 0; i < std::min(a.prerelease.size(), b.prerelease.size()); ++i) {
    const std::string& x = a.prerelease[i];
    const std::string& y = b.prerelease[i];
    const bool xn = numeric_identifier(x), yn = numeric_identifier(y);
    if (xn && yn) {
      if (x.size() != y.size()) return x.size() < y.size() ? -1 : 1;  // no leading zeros: length orders
      if (x != y) return x < y ? -1 : 1;
    } else if (xn != yn) {
      return xn ? -1 : 1;  // numeric identifiers sort first
    } else if (x != y) {
      return x < y ? -1 : 1;
    }
  }
  if (a.prerelease.size() != b.prerelease.size()) return a.prerelease.size() < b.prerelease.size() ? -1 : 1;
  return 0;
}

const char* kind_name(Kind kind) {
  switch (kind) {
    case Kind::remix_runtime: return "remix-runtime";
    case Kind::lua_binary_module: return "lua-binary-module";
    case Kind::root_files: return "root-files";
    case Kind::lua_addon: return "lua-addon";
    case Kind::patch_set: return "patch-set";
    case Kind::module_override: return "module-override";
  }
  return "?";
}

const char* policy_name(Policy policy) {
  return policy == Policy::create_only ? "create-only" : "replace-owned";
}

bool Manifest::has(Kind kind) const noexcept {
  return std::find(kinds.begin(), kinds.end(), kind) != kinds.end();
}

Manifest parse(std::string_view json_text) {
  Value root;
  try {
    root = json::parse(json_text);
  } catch (const json::Error& e) {
    fail(e.what());
  }
  try {
    if (!root.is_object()) fail("the document must be a JSON object");
    only_keys(root, "the manifest", {"schema", "id", "name", "version", "kinds", "requires_loader", "requires_remix", "files", "remix",
                                     "root_files", "patch_sets", "module_overrides", "session_cvars"});

    const std::int64_t schema = required(root, "schema").as_int("schema");
    if (schema != kSchema) fail("schema " + std::to_string(schema) + " is not supported (this loader reads schema 1)");

    Manifest m;
    m.id = required(root, "id").as_string("id");
    if (!valid_id(m.id)) fail("id \"" + m.id + "\" must be 1-64 characters of a-z, 0-9 and '-', starting with a letter or digit");

    m.name = m.id;
    if (const Value* name = root.find("name")) {
      m.name = name->as_string("name");
      if (m.name.empty() || m.name.size() > 128 || !utf8::valid(m.name)) fail("name must be 1-128 bytes of UTF-8");
    }

    const std::string& version = required(root, "version").as_string("version");
    const auto parsed = parse_version(version);
    if (!parsed) fail("version \"" + version + "\" is not a semantic version (MAJOR.MINOR.PATCH[-pre][+build])");
    m.version = *parsed;

    for (const Value& kind : required(root, "kinds").as_array("kinds")) {
      const std::string& name = kind.as_string("kinds entries");
      Kind k{};
      if (name == "remix-runtime") k = Kind::remix_runtime;
      else if (name == "lua-binary-module") k = Kind::lua_binary_module;
      else if (name == "root-files") k = Kind::root_files;
      else if (name == "lua-addon") k = Kind::lua_addon;
      else if (name == "patch-set") k = Kind::patch_set;
      else if (name == "module-override") k = Kind::module_override;
      else fail("unknown kind \"" + name + "\"");
      if (m.has(k)) fail("kind \"" + name + "\" is listed twice");
      m.kinds.push_back(k);
    }
    if (m.kinds.empty()) fail("kinds must not be empty");

    if (const Value* req = root.find("requires_loader")) {
      const std::string& text = req->as_string("requires_loader");
      const auto min = text.substr(0, 2) == ">=" ? parse_version(std::string_view(text).substr(2)) : std::nullopt;
      if (!min) fail("requires_loader \"" + text + "\" must be \">=MAJOR.MINOR.PATCH\"");
      m.requires_loader = min;
    }
    if (const Value* flag = root.find("requires_remix")) m.requires_remix = flag->as_bool("requires_remix");

    std::set<std::string> listed;
    for (const auto& [path, info] : required(root, "files").as_object("files")) {
      safe_path(path, "file");
      const std::string folded = paths::fold(path);
      if (folded == manifest::kManifestPath) fail("files must not list the manifest itself");
      if (!paths::within(folded, "native/payload") && !paths::within(folded, "native/root")) {
        fail("file \"" + path + "\" must be under native/payload/ or native/root/");
      }
      if (folded == "native/payload" || folded == "native/root") fail("file \"" + path + "\" names a folder");
      if (!listed.insert(folded).second) fail("file \"" + path + "\" is listed twice (paths compare without case)");
      only_keys(info, "file \"" + path + "\"", {"size", "sha256"});
      FileInfo fi;
      const std::int64_t size = required(info, "size").as_int("size of " + path);
      if (size < 0) fail("size of \"" + path + "\" is negative");
      fi.size = static_cast<std::uint64_t>(size);
      fi.sha256 = required(info, "sha256").as_string("sha256 of " + path);
      if (!is_hex64(fi.sha256)) fail("sha256 of \"" + path + "\" must be 64 lowercase hex digits");
      m.files.emplace_back(path, std::move(fi));
    }
    if (m.files.empty()) fail("files must not be empty");
    const auto in_payload = [&](std::string_view relative) { return listed.count(paths::fold(payload_path(relative))) > 0; };

    if (const Value* remix = root.find("remix")) {
      if (!m.has(Kind::remix_runtime)) fail("\"remix\" is only allowed with kind remix-runtime");
      only_keys(*remix, "remix", {"entry", "rtx_conf_layers", "dxvk_conf_layers", "env", "launch_args", "prefer_system_vulkan_loader"});
      Remix r;
      r.entry = safe_path(required(*remix, "entry").as_string("remix.entry"), "remix.entry");
      const std::string folded_entry = paths::fold(r.entry);
      const std::size_t slash = folded_entry.rfind('/');
      if (folded_entry.substr(slash == std::string::npos ? 0 : slash + 1) != "d3d9.dll") {
        fail("remix.entry \"" + r.entry + "\" must be a file named d3d9.dll");
      }
      if (!in_payload(r.entry)) fail("remix.entry \"" + r.entry + "\" is not listed under native/payload/");
      for (const auto& [key, layers] : {std::pair{"rtx_conf_layers", &r.rtx_conf_layers}, std::pair{"dxvk_conf_layers", &r.dxvk_conf_layers}}) {
        if (const Value* list = remix->find(key)) {
          *layers = string_list(*list, std::string("remix.") + key);
          for (const std::string& layer : *layers) {
            safe_path(layer, std::string("remix.") + key + " entry");
            if (paths::fold(layer).size() < 5 || paths::fold(layer).substr(paths::fold(layer).size() - 5) != ".conf") {
              fail(std::string("remix.") + key + " entry \"" + layer + "\" must be a .conf file");
            }
            if (!in_payload(layer)) fail(std::string("remix.") + key + " entry \"" + layer + "\" is not listed under native/payload/");
          }
        }
      }
      if (const Value* env = remix->find("env")) {
        for (const auto& [name, value] : env->as_object("remix.env")) {
          if (!valid_env_name(name)) fail("remix.env name \"" + name + "\" must be DXVK_* or RTX_* (A-Z, 0-9, _)");
          const std::string& text = value.as_string("remix.env." + name);
          if (text.size() > 1024 || !std::all_of(text.begin(), text.end(), [](char c) { return c >= 0x20 && c < 0x7F; })) {
            fail("remix.env." + name + " must be at most 1024 printable ASCII characters");
          }
          r.env.emplace_back(name, text);
        }
      }
      if (const Value* args = remix->find("launch_args")) {
        r.launch_args = string_list(*args, "remix.launch_args");
        check_launch_args(r.launch_args);
      }
      if (const Value* vk = remix->find("prefer_system_vulkan_loader")) {
        r.prefer_system_vulkan_loader = vk->as_bool("remix.prefer_system_vulkan_loader");
      }
      m.remix = std::move(r);
    }
    if (m.has(Kind::remix_runtime) && !m.remix) fail("kind remix-runtime needs a \"remix\" section");

    if (const Value* roots = root.find("root_files")) {
      for (const Value& item : roots->as_array("root_files")) {
        only_keys(item, "root_files entry", {"path", "policy"});
        RootFile rf;
        rf.path = safe_path(required(item, "path").as_string("root_files path"), "root file");
        if (const Value* policy = item.find("policy")) {
          const std::string& p = policy->as_string("root_files policy");
          if (p == "replace-owned") rf.policy = Policy::replace_owned;
          else if (p == "create-only") rf.policy = Policy::create_only;
          else fail("root file \"" + rf.path + "\": policy must be replace-owned or create-only");
        }
        rf.area = paths::root_area(rf.path);
        switch (rf.area) {
          case paths::RootArea::none:
            fail("root file \"" + rf.path + "\" is outside rtx-remix/mods/, garrysmod/lua/bin/, garrysmod/cfg/, garrysmod/data/ and garrysmod/addons/");
          case paths::RootArea::lua_addons:
            if (!m.has(Kind::lua_addon)) fail("root file \"" + rf.path + "\" in garrysmod/addons needs kind lua-addon");
            if (rf.policy != Policy::replace_owned) fail("root file \"" + rf.path + "\" in garrysmod/addons must use policy replace-owned");
            if (split(rf.path, '/').size() < 3) fail("root file \"" + rf.path + "\" must name an add-on folder: garrysmod/addons/<addon>");
            break;
          case paths::RootArea::lua_bin:
            if (!m.has(Kind::lua_binary_module)) fail("root file \"" + rf.path + "\" in garrysmod/lua/bin needs kind lua-binary-module");
            break;
          case paths::RootArea::cfg:
            if (rf.policy != Policy::create_only) fail("root file \"" + rf.path + "\" in garrysmod/cfg must use policy create-only");
            [[fallthrough]];
          case paths::RootArea::data:
            if (rf.policy != Policy::create_only) fail("root file \"" + rf.path + "\" in garrysmod/data must use policy create-only");
            if (split(rf.path, '/').size() < 3) fail("root file \"" + rf.path + "\" must be below a folder of garrysmod/data");
            [[fallthrough]];
          case paths::RootArea::rtx_remix_mods:
            if (!m.has(Kind::root_files)) fail("root file \"" + rf.path + "\" needs kind root-files");
            break;
        }
        for (const RootFile& other : m.root_files) {
          if (paths::within(rf.path, other.path) || paths::within(other.path, rf.path)) {
            fail("root files \"" + other.path + "\" and \"" + rf.path + "\" overlap");
          }
        }
        // The package must ship something for it.
        const std::string source = "native/root/" + paths::fold(rf.path);
        if (std::none_of(listed.begin(), listed.end(), [&](const std::string& f) { return paths::within(f, source); })) {
          fail("root file \"" + rf.path + "\" has nothing under native/root/" + rf.path);
        }
        m.root_files.push_back(std::move(rf));
      }
    }
    for (const Kind k : {Kind::lua_binary_module, Kind::root_files, Kind::lua_addon}) {
      if (!m.has(k)) continue;
      const bool used = std::any_of(m.root_files.begin(), m.root_files.end(), [k](const RootFile& rf) {
        if (k == Kind::lua_binary_module) return rf.area == paths::RootArea::lua_bin;
        if (k == Kind::lua_addon) return rf.area == paths::RootArea::lua_addons;
        return rf.area == paths::RootArea::rtx_remix_mods || rf.area == paths::RootArea::cfg || rf.area == paths::RootArea::data;
      });
      if (!used) fail(std::string("kind ") + kind_name(k) + " is declared but no root file uses it");
    }

    // RTX-session extras (ADR 0010).
    if (const Value* sets = root.find("patch_sets")) {
      if (!m.has(Kind::patch_set)) fail("\"patch_sets\" needs kind patch-set");
      std::set<std::string> names;
      std::size_t total = 0;
      for (const Value& item : sets->as_array("patch_sets")) {
        only_keys(item, "patch_sets entry", {"module", "patches"});
        PatchSet set;
        set.module = required(item, "module").as_string("patch_sets module");
        if (!valid_module_name(set.module)) fail("patch_sets module \"" + set.module + "\" must be a lowercase DLL name: [a-z0-9_]+.dll");
        for (const PatchSet& other : m.session.patch_sets) {
          if (other.module == set.module) fail("patch_sets module \"" + set.module + "\" is listed twice");
        }
        for (const Value& entry : required(item, "patches").as_array("patch_sets patches")) {
          only_keys(entry, "patch", {"name", "find", "offset", "replace"});
          Patch patch;
          patch.name = required(entry, "name").as_string("patch name");
          if (!snake_name(patch.name)) fail("patch name \"" + patch.name + "\" must be 1-64 characters of a-z, 0-9 and _");
          if (!names.insert(patch.name).second) fail("patch name \"" + patch.name + "\" is used twice");
          patch.find = required(entry, "find").as_string("patch find");
          const auto pattern = parse_pattern(patch.find);
          if (pattern.empty()) fail("patch \"" + patch.name + "\": find must be 1-256 lowercase hex bytes or ??, not all ??");
          patch.replace = required(entry, "replace").as_string("patch replace");
          const auto bytes = parse_hex(patch.replace);
          if (bytes.empty()) fail("patch \"" + patch.name + "\": replace must be 1-256 lowercase hex bytes");
          if (const Value* offset = entry.find("offset")) patch.offset = as_size(*offset, "patch offset");
          if (patch.offset > pattern.size() || bytes.size() > pattern.size() - patch.offset) {
            fail("patch \"" + patch.name + "\": replace must lie inside the matched bytes (offset + length <= find length)");
          }
          set.patches.push_back(std::move(patch));
          if (++total > 256) fail("patch_sets: at most 256 patches");
        }
        if (set.patches.empty()) fail("patch_sets module \"" + set.module + "\" has no patches");
        m.session.patch_sets.push_back(std::move(set));
      }
      if (m.session.patch_sets.empty()) fail("patch_sets must not be empty");
    }
    if (m.has(Kind::patch_set) && m.session.patch_sets.empty()) fail("kind patch-set needs \"patch_sets\"");

    if (const Value* overrides = root.find("module_overrides")) {
      if (!m.has(Kind::module_override)) fail("\"module_overrides\" needs kind module-override");
      for (const Value& item : overrides->as_array("module_overrides")) {
        only_keys(item, "module_overrides entry", {"module", "file"});
        ModuleOverride o;
        o.module = required(item, "module").as_string("module_overrides module");
        if (!valid_module_name(o.module)) fail("module_overrides module \"" + o.module + "\" must be a lowercase DLL name: [a-z0-9_]+.dll");
        for (const ModuleOverride& other : m.session.module_overrides) {
          if (other.module == o.module) fail("module_overrides module \"" + o.module + "\" is listed twice");
        }
        const std::string file = safe_path(required(item, "file").as_string("module_overrides file"), "module_overrides file");
        const std::string folded = paths::fold(file);
        if (!paths::within(folded, "native/payload") || folded == "native/payload") {
          fail("module_overrides file \"" + file + "\" must be under native/payload/");
        }
        if (!listed.count(folded)) fail("module_overrides file \"" + file + "\" is not listed in files");
        if (folded.substr(folded.rfind('/') + 1) != o.module) fail("module_overrides file \"" + file + "\" must be named " + o.module);
        o.file = file.substr(std::string_view("native/payload/").size());
        m.session.module_overrides.push_back(std::move(o));
      }
      if (m.session.module_overrides.empty()) fail("module_overrides must not be empty");
    }
    if (m.has(Kind::module_override) && m.session.module_overrides.empty()) fail("kind module-override needs \"module_overrides\"");

    if (const Value* cvars = root.find("session_cvars")) {
      for (const auto& [name, value] : cvars->as_object("session_cvars")) {
        if (!valid_cvar_name(name)) fail("session_cvars name \"" + name + "\" must be 1-64 characters of A-Z, a-z, 0-9 and _");
        // Only rendering variables: a name such as exec or bind would run a command from the cfg.
        const std::string folded = paths::fold(name);
        const bool allowed = folded == "sv_cheats" || folded.rfind("r_", 0) == 0 || folded.rfind("mat_", 0) == 0 ||
                             folded.rfind("cl_", 0) == 0 || folded.rfind("gmod_", 0) == 0 || folded.rfind("rtx_", 0) == 0 ||
                             folded.rfind("studio_", 0) == 0;
        if (!allowed) fail("session_cvars name \"" + name + "\" must start with r_, mat_, cl_, gmod_, rtx_ or studio_ (or be sv_cheats)");
        const std::string& text = value.as_string("session_cvars." + name);
        if (!valid_cvar_value(text)) fail("session_cvars." + name + " must be at most 32 characters of A-Z, a-z, 0-9 and _ . + -");
        m.session.cvars.emplace_back(name, text);
      }
      if (m.session.cvars.size() > 256) fail("session_cvars: at most 256 entries");
    }
    // Every file under native/root/ must belong to a declared root file.
    for (const std::string& f : listed) {
      if (!paths::within(f, "native/root")) continue;
      const std::string target = f.substr(std::string_view("native/root/").size());
      if (std::none_of(m.root_files.begin(), m.root_files.end(), [&](const RootFile& rf) { return paths::within(target, rf.path); })) {
        fail("file \"" + f + "\" is under native/root/ but no root_files entry covers it");
      }
    }
    return m;
  } catch (const json::Error& e) {  // a value of the wrong type
    fail(e.what());
  }
}

void check_contents(const Manifest& manifest, const std::vector<ContentEntry>& entries) {
  std::map<std::string, std::uint64_t> present;
  for (const ContentEntry& e : entries) present.emplace(paths::fold(e.path), e.size);
  for (const auto& [path, info] : manifest.files) {
    const auto it = present.find(paths::fold(path));
    if (it == present.end()) fail("\"" + path + "\" is listed but not in the package");
    if (it->second != info.size) {
      fail("\"" + path + "\" is " + std::to_string(it->second) + " bytes, the manifest says " + std::to_string(info.size));
    }
  }
  std::set<std::string> listed;
  for (const auto& [path, info] : manifest.files) listed.insert(paths::fold(path));
  for (const auto& [path, size] : present) {
    if (!paths::within(path, "native") || path == kManifestPath) continue;
    if (!listed.count(path)) fail("\"" + path + "\" is in the package but not listed in the manifest");
  }
}

}  // namespace nl::manifest
