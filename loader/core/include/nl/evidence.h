#pragma once
// Local previous-session evidence (ADR 0063). Source files are never changed.
#include <cstdint>
#include <filesystem>
#include <functional>
#include <optional>
#include <string>
#include <string_view>
#include <vector>

namespace nl::evidence {
inline constexpr std::string_view kStart = "native-loader/logs/session-start.json";
inline constexpr std::string_view kSessions = "native-loader/logs/sessions";
struct PreviousSession {
  std::string reason = "unknown";
  std::string time_utc;
  std::string folder;  // relative to the game root, empty when nothing was saved
};
struct Limits {
  std::size_t sessions = 5;
  std::uint64_t bytes = 200ull << 20;
  std::size_t files = 256;
  std::size_t tail_bytes = 256u << 10;
};
struct Result {
  PreviousSession previous;
  std::vector<std::string> notes;
  double elapsed_ms = 0;
};
struct Exit {
  std::uint32_t code = 0;
  bool commit_exhausted = false;  // recent, same-session sample; inference only
};
std::uint64_t now_filetime();
std::string utc(std::uint64_t filetime);
// More specific failure evidence wins over generic exceptions/exit messages. Missing or malformed
// structured data is harmless; its fields are optional (R6 I7).
std::string classify(std::string_view log, std::string_view gpu_json = {}, bool crash = false, bool oom = false,
                     std::optional<Exit> exit = {});
bool needs_report(std::string_view reason) noexcept;
std::string serialize(const PreviousSession& previous);
// Best effort. Run on a worker. Calls log_ready exactly once, after the old Remix log has been
// copied (or skipped), so the caller may then load a runtime that truncates it. Remaining dump work
// can overlap activation. Only finished, unchanged, receipted archives are eligible for retention.
Result collect(const std::filesystem::path& root, std::uint64_t start, std::uint32_t process_id,
               const std::function<void()>& log_ready = {}, const Limits& limits = {});
// External observer only, after its pinned process handle signals. Does not advance the start
// record; refuses a different/newer session. Saves exit-report.json in the evidence archive and
// records the same conclusion for collect() at the next start. Clean ends make only an end marker.
Result finish(const std::filesystem::path& root, std::uint64_t start, std::uint32_t process_id,
              std::uint32_t exit_code, std::string_view process_token, bool quiet, const Limits& limits = {});
void retain(const std::filesystem::path& root, const Limits& limits = {});
}  // namespace nl::evidence
