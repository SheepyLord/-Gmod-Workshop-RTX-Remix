#pragma once
#include "nl/activate.h"
#include "nl/config.h"
#include "nl/journal.h"
#include <filesystem>
#include <map>
#include <string>
#include <string_view>

namespace nl::client {
inline constexpr std::string_view kPackage = "gmod-rtx-remix";
inline constexpr std::string_view kModule = "garrysmod/lua/bin/gmsv_nlrtxclient_win64.dll";
struct Script {
  std::string addon;
  std::string path;
  std::string text;
};
struct Catalog {
  std::string identity;
  std::string runtime;
  std::map<std::string, Script> scripts;
};
// Only exact Lua files owned by the allowlisted RTX package enter the snapshot. Every byte is
// checked against the committed generation; no virtual filesystem or writable DATA code is used.
Catalog prepare(const std::filesystem::path& root, const config::Config& config,
                const journal::Generation& generation);
bool native_bootstrap_present(const journal::Generation& generation);
// Exact distribution item or an explicitly allowlisted local/development source (ADR 0052).
bool allowed_runtime_source(const std::filesystem::path& root, const config::Config& config,
                            const journal::Package& package);
bool secure_render_patch_set(std::string_view owner, const manifest::PatchSet& set);
// Why an activating plan must fall back to vanilla, or empty. With patch_sets.allow_rtx_render_patches
// false and the general gate closed (require_insecure, no -insecure in `command_line` nor in the
// arguments the plan adds), the reviewed rendering recipes would be skipped: the renderer crashed
// without them (ADR 0052, ADR 0056).
std::string render_recipes_refusal(const activate::Plan& plan, std::wstring_view command_line);
}
