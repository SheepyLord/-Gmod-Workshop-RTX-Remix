#pragma once
#include "nl/config.h"
#include "nl/journal.h"
#include <filesystem>
#include <optional>
#include <stdexcept>
#include <string>
#include <string_view>

namespace nl::guard {
inline constexpr std::string_view kInit = "garrysmod/lua/includes/init.lua";
inline constexpr std::string_view kGuard = "nativeloader/autorun/_nativeloader_guard.lua";
inline constexpr std::string_view kMarker = "NATIVELOADER_RENDER_GUARD_V2";
// Hash of the untouched current x86-64 Steam client initializer. Unknown bytes are not replaced.
inline constexpr std::string_view kStockInitSha256 = "04a0d82fa01f39c7470ae266aabfd1b38fce6ee9abbe01e93d2b70bf561ed276";
struct Redirect {
  std::filesystem::path source;
  std::filesystem::path replacement;
};
// Only emitted after catalog verification establishes this shipment requires the V2 early guard.
class RequiredUnavailable : public std::runtime_error {
 public:
  using std::runtime_error::runtime_error;
};

// Produces plain Lua with an isolated client-only guard call after the original stock initializer.
std::string append_client_guard(std::string_view original, std::string_view guard);

// Only configured sessions selecting our RTX runtime and catalog-verified owner source are eligible.
// A verified V2 shipment raises RequiredUnavailable if stock/cache preparation fails. expected_stock_hash
// is explicit for generated fixture tests; startup always supplies the pinned Steam hash above.
// Throws on changed source, links or a cache collision; writes only a new protected cache entry.
std::optional<Redirect> prepare(const std::filesystem::path& root, const config::Config& config,
                               const journal::Generation& generation, std::string_view selected_runtime,
                               std::string_view expected_stock_hash = kStockInitSha256);
}
