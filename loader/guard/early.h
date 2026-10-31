#pragma once
#include "nl/config.h"
#include "nl/journal.h"
#include <filesystem>
#include <optional>
#include <string>
#include <string_view>

namespace nl::guard {
inline constexpr std::string_view kInit = "garrysmod/lua/includes/init.lua";
inline constexpr std::string_view kGuard = "nativeloader/autorun/_nativeloader_guard.lua";
inline constexpr std::string_view kMarker = "NATIVELOADER_RENDER_GUARD_V2";
// Hash of the untouched current x86-64 Steam client initializer. Unknown bytes are not replaced.
inline constexpr std::string_view kStockInitSha256 = "04a0d82fa01f39c7470ae266aabfd1b38fce6ee9abbe01e93d2b70bf561ed276";
inline constexpr std::string_view kCacheFolder = "native-loader/presentation";
// A changed cache file is moved here, never deleted (ADR 0056).
inline constexpr std::string_view kKeptFolder = "native-loader/backup/render-guard";
struct Redirect {
  std::filesystem::path source;
  std::filesystem::path replacement;
  std::string kept;  // where a changed earlier cache file was moved, relative to the root; empty if none
};

// Produces plain Lua with an isolated client-only guard call after the original stock initializer.
// The guard is installed early only on a machine where `proof` (a path relative to the game root,
// the cache file itself) exists: a listen host serves this view to its remote clients too.
std::string append_client_guard(std::string_view original, std::string_view guard, std::string_view proof);

// Only configured sessions selecting our RTX runtime and catalog-verified owner source are eligible;
// others get nullopt without any read. Any failure throws: the session then runs RTX with the
// companion's autorun guard instead (ADR 0056). expected_stock_hash is explicit for generated fixture
// tests; startup always supplies the pinned Steam hash above. Writes only the protected cache entry,
// moving a changed one aside first.
std::optional<Redirect> prepare(const std::filesystem::path& root, const config::Config& config,
                               const journal::Generation& generation, std::string_view selected_runtime,
                               std::string_view expected_stock_hash = kStockInitSha256);
}
