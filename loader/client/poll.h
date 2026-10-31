#pragma once
#include <cstdint>

namespace nl::client {
// The menu realm polls the client realm from its Think hook (ADR 0052). Checks run at most every
// kPollIntervalMs, and one client realm gets at most kMaxClientAttempts runs of the initializer,
// which declines while the local player is not valid yet (ADR 0056): two minutes, then it gives up.
inline constexpr std::uint64_t kPollIntervalMs = 250;
inline constexpr unsigned kMaxClientAttempts = 480;

struct PollGate {
  std::uint64_t next = 0;
  bool due(std::uint64_t now_ms) noexcept {
    if (now_ms < next) return false;
    next = now_ms + kPollIntervalMs;
    return true;
  }
};

// `attempt` counts from 1 for each client realm.
inline bool attempt_allowed(unsigned attempt) noexcept { return attempt >= 1 && attempt <= kMaxClientAttempts; }
}  // namespace nl::client
