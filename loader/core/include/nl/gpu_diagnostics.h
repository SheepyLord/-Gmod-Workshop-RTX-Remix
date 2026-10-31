#pragma once
// Local, opt-in GPU crash diagnostics (ADR 0062). Never edits config.json or journal state.
#include <filesystem>
#include <string>
#include <string_view>

namespace nl::gpu_diagnostics {
inline constexpr std::string_view kLayer = "native-loader/remix/diagnostics.conf";
inline constexpr std::string_view kDumpFolder = "native-loader/logs/gpu";
inline constexpr std::string_view kUsed = "native-loader/remix/gpu-crash-dumps.used";
inline constexpr std::string_view kDumpVariable = "DXVK_AFTERMATH_DUMP_PATH";
struct Probe {
  bool consumed = false;
  std::string dump_path;  // absolute, with a trailing slash, ready for the runtime
  std::string note;       // a probe failure disables next_start, not RTX
};
Probe probe(const std::filesystem::path& root);
std::string layer_text();
// Creates only loader-owned folders/layer. Returns the absolute dump folder. Refuses links.
std::string prepare(const std::filesystem::path& root);
// Atomically claims next_start. False: another start already claimed it. An incomplete marker
// also counts as consumed, so a crash during runtime initialization cannot enable a second start.
bool consume_next_start(const std::filesystem::path& root);
}  // namespace nl::gpu_diagnostics
