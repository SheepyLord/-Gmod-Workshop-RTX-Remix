#pragma once
// Package manifests: native/manifest.json, schema 1 (docs/PACKAGE_FORMAT.md). The manifest is
// untrusted input. parse() validates every field strictly (unknown keys are errors), and
// check_contents() matches it against the files the package actually holds.

#include "nl/paths.h"

#include <cstdint>
#include <optional>
#include <stdexcept>
#include <string>
#include <string_view>
#include <utility>
#include <vector>

namespace nl::manifest {

class Error : public std::runtime_error {
 public:
  using std::runtime_error::runtime_error;
};

inline constexpr int kSchema = 1;

// Semantic Versioning 2.0.0.
struct Version {
  std::uint64_t major{};
  std::uint64_t minor{};
  std::uint64_t patch{};
  std::vector<std::string> prerelease;  // dot-separated identifiers
  std::string build;                    // ignored for precedence
  std::string text;                     // as written
};
std::optional<Version> parse_version(std::string_view text);
int compare(const Version& a, const Version& b);  // SemVer precedence: negative, 0 or positive

enum class Kind { remix_runtime, lua_binary_module, root_files, lua_addon, patch_set, module_override };
const char* kind_name(Kind kind);

enum class Policy { replace_owned, create_only };
const char* policy_name(Policy policy);

struct FileInfo {
  std::uint64_t size{};
  std::string sha256;  // 64 lowercase hex digits; checked when the file is deployed (M3)
};

struct RootFile {
  std::string path;  // relative to the game root; deployed from native/root/<path>
  Policy policy = Policy::replace_owned;
  paths::RootArea area = paths::RootArea::none;
};

struct Remix {
  std::string entry;                         // relative to native/payload/; file name d3d9.dll
  std::vector<std::string> rtx_conf_layers;  // relative to native/payload/
  std::vector<std::string> dxvk_conf_layers;
  std::vector<std::pair<std::string, std::string>> env;
  std::vector<std::string> launch_args;
  bool prefer_system_vulkan_loader = false;
};

// What a package changes in RTX sessions only (M5, ADR 0010): applied when a runtime activates.
struct Patch {
  std::string name;     // [a-z0-9_]{1,64}, unique in the package
  std::string find;     // lowercase hex byte pairs or "??", 1-256 bytes; must match exactly once
  std::size_t offset = 0;
  std::string replace;  // lowercase hex, written at `offset` inside the matched bytes
};
struct PatchSet {
  std::string module;  // DLL base name, lowercase: engine.dll
  std::vector<Patch> patches;
};
struct ModuleOverride {
  std::string module;  // DLL base name the game loads from bin/win64: stdshader_dx6.dll
  std::string file;    // relative to native/payload/; same file name as `module`
};
struct Session {
  std::vector<PatchSet> patch_sets;
  std::vector<ModuleOverride> module_overrides;
  std::vector<std::pair<std::string, std::string>> cvars;  // console variable assignments
  bool empty() const noexcept { return patch_sets.empty() && module_overrides.empty() && cvars.empty(); }
};

// Checks used by the manifest and the journal.
bool valid_module_name(std::string_view name);
bool valid_cvar_name(std::string_view name);
bool valid_cvar_value(std::string_view value);
// Parses a `find` pattern: one entry per byte, -1 for a wildcard. Empty if invalid.
std::vector<int> parse_pattern(std::string_view text);
// Parses `replace` bytes. Empty if invalid.
std::vector<std::uint8_t> parse_hex(std::string_view text);

struct Manifest {
  std::string id;
  std::string name;
  Version version;
  std::vector<Kind> kinds;
  std::optional<Version> requires_loader;               // minimum loader version
  std::vector<std::pair<std::string, FileInfo>> files;  // package path -> info, document order
  std::optional<Remix> remix;
  std::vector<RootFile> root_files;
  Session session;  // patch_sets, module_overrides, session_cvars
  bool requires_remix = false;  // its add-on folders are hidden from sessions without a runtime (ADR 0013)
  bool has(Kind kind) const noexcept;
};

// Parses and validates manifest.json text. Throws Error naming the offending field.
Manifest parse(std::string_view json_text);

// A file the package holds, as listed by its archive index or folder.
struct ContentEntry {
  std::string path;
  std::uint64_t size{};
};

// Throws Error unless: every file the manifest lists is in the package with that size, every
// package file under native/ (except the manifest) is listed, and payload references exist.
// Files outside native/ are ordinary GMod content and are not checked.
void check_contents(const Manifest& manifest, const std::vector<ContentEntry>& entries);

inline constexpr std::string_view kManifestPath = "native/manifest.json";

}  // namespace nl::manifest
