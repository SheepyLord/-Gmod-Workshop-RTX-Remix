#pragma once
// Local memory diagnostics (ADR 0063). No static DXGI/PSAPI dependency.
#include <cstdint>
#include <filesystem>
#include <memory>
#include <optional>
#include <string>
#include <string_view>

namespace nl::memory {
inline constexpr std::string_view kCsv = "native-loader/logs/memory.csv";
inline constexpr std::string_view kRotated = "native-loader/logs/memory.1.csv";
inline constexpr std::string_view kIndex = "native-loader/logs/memory-index.json";
inline constexpr std::string_view kCommit = "garrysmod/data/native-loader/memory.json";
inline constexpr unsigned kIntervalMs = 10000;
struct Sample {
  std::string time_utc;
  std::optional<std::uint64_t> private_bytes, working_set;
  std::optional<std::uint64_t> commit_total, commit_limit, available_ram;
  std::optional<std::uint64_t> gpu_local_usage, gpu_local_budget, gpu_nonlocal_usage, gpu_nonlocal_budget;
};
// A zero limit means the query failed. Both thresholds are strict, with overflow-safe arithmetic.
bool commit_warning(std::uint64_t used, std::uint64_t limit) noexcept;
std::string process_token();
class Sampler {
 public:
  explicit Sampler(bool gpu = true);
  ~Sampler();
  Sampler(const Sampler&) = delete;
  Sampler& operator=(const Sampler&) = delete;
  Sample query(bool process = true) const;
 private:
  struct State;
  std::unique_ptr<State> state_;
};
std::string_view csv_header();
// Missing counters are empty fields, not invented zeroes. Values are bytes, timestamp is UTC.
std::string csv_line(const Sample& sample);
struct Limits {
  std::size_t rows = 360;  // one hour per file: about the last one to two hours in the two files
  std::size_t bytes = 256u << 10;
};
// Appends and flushes one row, rotates only hash-verified owned files. Throws on locked/foreign/
// edited files; their bytes stay intact. A receipt tolerates one flushed row after an interrupted
// receipt update, or a rotation interrupted before the new receipt. Caller runs off startup path.
// Recovered, unmatched bytes are also kept under backup/edits before being adopted for rotation.
void append(const std::filesystem::path& root, const Sample& sample, const Limits& limits = {});
// Only the latest system commit observation, for the home-menu warning; no history or GPU data.
void write_commit(const std::filesystem::path& root, const Sample& sample, std::string_view token);
}  // namespace nl::memory
