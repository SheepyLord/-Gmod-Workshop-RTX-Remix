#pragma once
// Rules for paths that come from packages: entries inside a .gma, paths in a manifest, and
// deployment targets under the game root. A path that passes is relative, '/'-separated, cannot
// escape its base, and cannot alias another file on Windows (device names, trailing dots or spaces,
// 8.3 short names, alternate data streams, drive letters).

#include <cstddef>
#include <string>
#include <string_view>

namespace nl::paths {

inline constexpr std::size_t kMaxPathBytes = 1024;
inline constexpr std::size_t kMaxComponentBytes = 255;

// Empty if `path` is a safe relative path, otherwise the reason it is not. `max_bytes` limits the
// length: kMaxPathBytes for anything a package names; the journal also holds the loader's own
// paths, which put a folder of the loader's in front of a package path.
std::string problem(std::string_view path, std::size_t max_bytes = kMaxPathBytes);
inline bool is_safe(std::string_view path) { return problem(path).empty(); }

// ASCII-lowercased copy. Windows compares paths case-insensitively; non-ASCII bytes are kept.
std::string fold(std::string_view path);

// True if `path` equals `prefix` or lies below it (case-insensitive, '/'-separated).
bool within(std::string_view path, std::string_view prefix);

// Where under the game root a package may deploy files (manifest schema 1). None of these folders
// holds a Steam depot file; garrysmod/cfg does, so it is not an area (ADR 0014).
enum class RootArea {
  none,            // anywhere else: never written by packages
  rtx_remix_mods,  // rtx-remix/mods/<mod>/...
  lua_bin,         // garrysmod/lua/bin/... (binary Lua modules)
  lua_addons,      // garrysmod/addons/<addon>/... (Lua add-on folders, M5)
  data,            // garrysmod/data/<folder>/... (seed data, new files only; not native-loader, M5)
};
RootArea root_area(std::string_view safe_path);
const char* area_name(RootArea area);

// True if a file may be at `safe_path`: inside an area and, in the areas that hold named folders
// (rtx-remix/mods, garrysmod/addons, garrysmod/data), inside one of those folders.
bool file_depth_ok(std::string_view safe_path);

}  // namespace nl::paths
