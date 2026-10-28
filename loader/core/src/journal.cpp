#include "nl/journal.h"

#include "nl/json.h"
#include "nl/paths.h"

#include <algorithm>
#include <initializer_list>

namespace nl::journal {

namespace {

using json::Value;

constexpr std::size_t kMaxBytes = std::size_t{64} << 20;
// The loader's own paths put a folder of the loader's (native-loader/backup/<gen>/, a payload
// folder, a staging folder: under 200 bytes) in front of a package path of up to 1,024 bytes.
constexpr std::size_t kMaxPathBytes = 4096;

[[noreturn]] void fail(const std::string& message) {
  throw Error("native-loader/state.json: " + message);
}

void only_keys(const Value& object, std::string_view what, std::initializer_list<std::string_view> keys) {
  for (const auto& member : object.as_object(what)) {
    if (std::find(keys.begin(), keys.end(), member.first) == keys.end()) {
      fail(std::string(what) + " has an unknown key \"" + member.first + "\"");
    }
  }
}

const Value& required(const Value& object, std::string_view key, std::string_view what) {
  const Value* value = object.find(key);
  if (!value) fail(std::string(what) + " has no \"" + std::string(key) + "\"");
  return *value;
}

std::uint64_t count(const Value& value, std::string_view what) {
  const std::int64_t n = value.as_int(what);
  if (n < 0) fail(std::string(what) + " is negative");
  return static_cast<std::uint64_t>(n);
}

bool is_hex64(std::string_view s) {
  return s.size() == 64 && std::all_of(s.begin(), s.end(), [](char c) { return (c >= '0' && c <= '9') || (c >= 'a' && c <= 'f'); });
}

std::string sha(const Value& value, std::string_view what) {
  const std::string& s = value.as_string(what);
  if (!is_hex64(s)) fail(std::string(what) + " is not a SHA-256 (64 lowercase hex digits)");
  return s;
}

// Where the loader can own files: its payload and backup folders, and the root areas.
bool file_area(std::string_view path) {
  return paths::within(path, "native-loader/packages") || paths::within(path, "native-loader/backup") ||
         paths::root_area(path) != paths::RootArea::none;
}

// Folders it may create: those, and the folders above the root areas.
bool folder_area(std::string_view path) {
  static constexpr std::string_view kParents[] = {"garrysmod",     "garrysmod/lua",          "garrysmod/lua/bin",
                                                  "garrysmod/cfg", "rtx-remix",              "rtx-remix/mods",
                                                  "native-loader/packages", "native-loader/backup"};
  const std::string folded = paths::fold(path);
  return std::find(std::begin(kParents), std::end(kParents), folded) != std::end(kParents) || file_area(path);
}

// What a transaction may touch: those, and its staging folder.
bool step_area(std::string_view path) {
  return folder_area(path) || paths::within(path, "native-loader/staging");
}

std::string checked_path(const Value& value, std::string_view what, bool (*allowed)(std::string_view)) {
  const std::string& p = value.as_string(what);
  if (const std::string why = paths::problem(p, kMaxPathBytes); !why.empty()) fail(std::string(what) + " \"" + p + "\": " + why);
  if (!allowed(p)) fail(std::string(what) + " \"" + p + "\" is outside the folders the loader manages");
  return p;
}

std::vector<std::string> strings(const Value& value, std::string_view what) {
  std::vector<std::string> out;
  for (const Value& item : value.as_array(what)) out.push_back(item.as_string(what));
  return out;
}

File file_of(const Value& value, std::string_view what) {
  only_keys(value, what, {"path", "package", "sha256", "size", "mtime", "adopted"});
  File f;
  f.path = checked_path(required(value, "path", what), std::string(what) + " path", file_area);
  f.package = required(value, "package", what).as_string(std::string(what) + " package");
  f.sha256 = sha(required(value, "sha256", what), std::string(what) + " sha256");
  f.size = count(required(value, "size", what), std::string(what) + " size");
  f.mtime = count(required(value, "mtime", what), std::string(what) + " mtime");
  f.adopted = required(value, "adopted", what).as_bool(std::string(what) + " adopted");
  return f;
}

std::vector<File> files_of(const Value& value, std::string_view what) {
  std::vector<File> out;
  for (const Value& item : value.as_array(what)) out.push_back(file_of(item, what));
  return out;
}

// Paths inside a payload folder (M4 loads and layers them): they must pass the path rules too.
std::vector<std::string> payload_paths(const Value& value, std::string_view what) {
  std::vector<std::string> out = strings(value, what);
  for (const std::string& p : out) {
    if (const std::string why = paths::problem(p); !why.empty()) fail(std::string(what) + " \"" + p + "\": " + why);
  }
  return out;
}

manifest::Remix remix_of(const Value& value) {
  only_keys(value, "remix", {"entry", "rtx_conf_layers", "dxvk_conf_layers", "env", "launch_args", "prefer_system_vulkan_loader"});
  manifest::Remix r;
  r.entry = required(value, "entry", "remix").as_string("remix entry");
  if (const std::string why = paths::problem(r.entry); !why.empty()) fail("remix entry \"" + r.entry + "\": " + why);
  r.rtx_conf_layers = payload_paths(required(value, "rtx_conf_layers", "remix"), "remix rtx_conf_layers");
  r.dxvk_conf_layers = payload_paths(required(value, "dxvk_conf_layers", "remix"), "remix dxvk_conf_layers");
  for (const auto& member : required(value, "env", "remix").as_object("remix env")) {
    r.env.emplace_back(member.first, member.second.as_string("remix env value"));
  }
  r.launch_args = strings(required(value, "launch_args", "remix"), "remix launch_args");
  r.prefer_system_vulkan_loader = required(value, "prefer_system_vulkan_loader", "remix").as_bool("remix prefer_system_vulkan_loader");
  return r;
}

Package package_of(const Value& value) {
  only_keys(value, "package", {"id", "version", "manifest_sha256", "source", "location", "payload", "remix"});
  Package p;
  p.id = required(value, "id", "package").as_string("package id");
  if (p.id.empty() || p.id.find('/') != std::string::npos || !paths::is_safe(p.id)) fail("package id \"" + p.id + "\" is invalid");
  p.version = required(value, "version", "package").as_string("package version");
  p.manifest_sha256 = sha(required(value, "manifest_sha256", "package"), "package manifest_sha256");
  p.source = required(value, "source", "package").as_string("package source");
  if (p.source != "dev_folder" && p.source != "local" && p.source != "workshop") {
    fail("package source \"" + p.source + "\" is not dev_folder, local or workshop");
  }
  p.location = required(value, "location", "package").as_string("package location");
  const Value& payload = required(value, "payload", "package");
  if (!payload.as_string("package payload").empty()) {
    p.payload = checked_path(payload, "package payload", [](std::string_view path) {
      return paths::within(path, "native-loader/packages") && paths::fold(path) != "native-loader/packages";
    });
  }
  if (const Value& remix = required(value, "remix", "package"); !remix.is_null()) p.remix = remix_of(remix);
  return p;
}

Generation generation_of(const Value& value, std::string_view what) {
  only_keys(value, what, {"generation", "packages", "files"});
  Generation g;
  g.number = count(required(value, "generation", what), std::string(what) + " generation");
  for (const Value& item : required(value, "packages", what).as_array(std::string(what) + " packages")) {
    g.packages.push_back(package_of(item));
  }
  g.files = files_of(required(value, "files", what), std::string(what) + " file");
  return g;
}

Step step_of(const Value& value) {
  const std::string& op = required(value, "op", "step").as_string("step op");
  Step s;
  if (op == "make_dir") {
    only_keys(value, "make_dir step", {"op", "path"});
    s.op = Step::Op::make_dir;
    s.to = checked_path(required(value, "path", "step"), "step path", step_area);
  } else if (op == "move") {
    only_keys(value, "move step", {"op", "from", "to", "sha256"});
    s.op = Step::Op::move;
    s.from = checked_path(required(value, "from", "step"), "step from", step_area);
    s.to = checked_path(required(value, "to", "step"), "step to", step_area);
    s.sha256 = required(value, "sha256", "step").as_string("step sha256");
    if (!s.sha256.empty() && !is_hex64(s.sha256)) fail("step sha256 is not a SHA-256");
  } else {
    fail("step op \"" + op + "\" is not make_dir or move");
  }
  return s;
}

Pending pending_of(const Value& value) {
  only_keys(value, "pending", {"transaction", "action", "steps"});
  Pending p;
  p.transaction = count(required(value, "transaction", "pending"), "pending transaction");
  p.action = required(value, "action", "pending").as_string("pending action");
  if (p.action != "apply" && p.action != "rollback") fail("pending action \"" + p.action + "\" is not apply or rollback");
  for (const Value& item : required(value, "steps", "pending").as_array("pending steps")) p.steps.push_back(step_of(item));
  return p;
}

std::string q(std::string_view text) {
  return json::quote(text);
}

std::string strings_json(const std::vector<std::string>& items) {
  std::string out = "[";
  for (std::size_t i = 0; i < items.size(); ++i) out += (i ? ", " : "") + q(items[i]);
  return out + "]";
}

std::string file_json(const File& f) {
  return "{\"path\": " + q(f.path) + ", \"package\": " + q(f.package) + ", \"sha256\": " + q(f.sha256) +
         ", \"size\": " + std::to_string(f.size) + ", \"mtime\": " + std::to_string(f.mtime) +
         ", \"adopted\": " + (f.adopted ? "true" : "false") + "}";
}

std::string files_json(const std::vector<File>& files, const std::string& indent) {
  if (files.empty()) return "[]";
  std::string out = "[";
  for (std::size_t i = 0; i < files.size(); ++i) out += (i ? ",\n" : "\n") + indent + "  " + file_json(files[i]);
  return out + "\n" + indent + "]";
}

std::string remix_json(const manifest::Remix& r) {
  std::string out = "{\"entry\": " + q(r.entry) + ", \"rtx_conf_layers\": " + strings_json(r.rtx_conf_layers) +
                    ", \"dxvk_conf_layers\": " + strings_json(r.dxvk_conf_layers) + ", \"env\": {";
  for (std::size_t i = 0; i < r.env.size(); ++i) out += (i ? ", " : "") + q(r.env[i].first) + ": " + q(r.env[i].second);
  return out + "}, \"launch_args\": " + strings_json(r.launch_args) +
         ", \"prefer_system_vulkan_loader\": " + (r.prefer_system_vulkan_loader ? "true" : "false") + "}";
}

std::string package_json(const Package& p) {
  return "{\"id\": " + q(p.id) + ", \"version\": " + q(p.version) + ", \"manifest_sha256\": " + q(p.manifest_sha256) +
         ", \"source\": " + q(p.source) + ", \"location\": " + q(p.location) + ", \"payload\": " + q(p.payload) +
         ", \"remix\": " + (p.remix ? remix_json(*p.remix) : std::string("null")) + "}";
}

std::string generation_json(const std::optional<Generation>& g) {
  if (!g) return "null";
  std::string out = "{\n    \"generation\": " + std::to_string(g->number) + ",\n    \"packages\": [";
  for (std::size_t i = 0; i < g->packages.size(); ++i) out += (i ? ",\n      " : "\n      ") + package_json(g->packages[i]);
  out += g->packages.empty() ? "]" : "\n    ]";
  return out + ",\n    \"files\": " + files_json(g->files, "    ") + "\n  }";
}

std::string step_json(const Step& s) {
  if (s.op == Step::Op::make_dir) return "{\"op\": \"make_dir\", \"path\": " + q(s.to) + "}";
  return "{\"op\": \"move\", \"from\": " + q(s.from) + ", \"to\": " + q(s.to) + ", \"sha256\": " + q(s.sha256) + "}";
}

std::string pending_json(const std::optional<Pending>& p) {
  if (!p) return "null";
  std::string out = "{\n    \"transaction\": " + std::to_string(p->transaction) + ",\n    \"action\": " + q(p->action) +
                    ",\n    \"steps\": [";
  for (std::size_t i = 0; i < p->steps.size(); ++i) out += (i ? ",\n      " : "\n      ") + step_json(p->steps[i]);
  out += p->steps.empty() ? "]" : "\n    ]";
  return out + "\n  }";
}

}  // namespace

Journal parse(std::string_view text) {
  try {
    json::ParseLimits limits;
    limits.max_bytes = kMaxBytes;
    limits.max_values = 4'000'000;
    const Value root = json::parse(text, limits);
    only_keys(root, "the journal",
              {"schema", "loader", "next", "current", "previous", "previous_backup", "retired", "dirs", "hold", "pending"});
    if (required(root, "schema", "the journal").as_int("schema") != kSchema) fail("schema must be 1");
    Journal j;
    j.loader = required(root, "loader", "the journal").as_string("loader");
    j.next = count(required(root, "next", "the journal"), "next");
    if (j.next == 0) fail("next must be at least 1");
    if (const Value& v = required(root, "current", "the journal"); !v.is_null()) j.current = generation_of(v, "current");
    if (const Value& v = required(root, "previous", "the journal"); !v.is_null()) j.previous = generation_of(v, "previous");
    const Value& backup = required(root, "previous_backup", "the journal");
    if (!backup.as_string("previous_backup").empty()) {
      j.previous_backup = checked_path(backup, "previous_backup", [](std::string_view path) {
        return paths::within(path, "native-loader/backup") && paths::fold(path) != "native-loader/backup";
      });
    }
    j.retired = files_of(required(root, "retired", "the journal"), "retired file");
    for (const Value& item : required(root, "dirs", "the journal").as_array("dirs")) {
      j.dirs.push_back(checked_path(item, "dirs entry", folder_area));
    }
    if (const Value& v = required(root, "hold", "the journal"); !v.is_null()) j.hold = strings(v, "hold");
    if (const Value& v = required(root, "pending", "the journal"); !v.is_null()) j.pending = pending_of(v);
    return j;
  } catch (const json::Error& e) {  // a syntax error, or a value of the wrong type
    fail(e.what());
  }
}

std::string serialize(const Journal& j) {
  std::string out = "{\n  \"schema\": " + std::to_string(kSchema) + ",\n  \"loader\": " + q(j.loader) +
                    ",\n  \"next\": " + std::to_string(j.next);
  out += ",\n  \"current\": " + generation_json(j.current);
  out += ",\n  \"previous\": " + generation_json(j.previous);
  out += ",\n  \"previous_backup\": " + q(j.previous_backup);
  out += ",\n  \"retired\": " + files_json(j.retired, "  ");
  out += ",\n  \"dirs\": " + strings_json(j.dirs);
  out += ",\n  \"hold\": " + (j.hold ? strings_json(*j.hold) : std::string("null"));
  out += ",\n  \"pending\": " + pending_json(j.pending);
  return out + "\n}\n";
}

std::optional<Journal> load(const std::filesystem::path& root) {
  const std::filesystem::path file = fs::join(root, kPath);
  std::string text;
  try {
    if (!fs::stat(file).exists) return std::nullopt;
    text = fs::read_file(file, kMaxBytes);
  } catch (const fs::Error& e) {
    throw Error(std::string("native-loader/state.json cannot be read: ") + e.what());
  }
  return parse(text);
}

void save(fs::FileSystem& disk, const std::filesystem::path& root, const Journal& journal) {
  fs::write_atomic(disk, fs::join(root, kPath), serialize(journal));
}

}  // namespace nl::journal
