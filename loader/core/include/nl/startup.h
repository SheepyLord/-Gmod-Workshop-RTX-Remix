#pragma once
// M4 start-up deployment policy. The CLI keeps M3 behavior; only prepare() opts into keep-last-good.
#include "nl/config.h"
#include "nl/deploy.h"
#include "nl/journal.h"
#include "nl/planner.h"
#include <cstdint>
#include <filesystem>
#include <optional>
#include <string>

namespace nl::startup {

// Pure: if a proposed change would lose a current package because its still-allowlisted source
// failed, return the reason to defer the entire deployment. Explicit removals/disabled items win.
std::optional<std::string> keep_last_good_reason(const journal::Generation& current, const planner::Plan& proposed);

// Pure: may start-up activate the committed generation after this deployment result? Not while the
// journal has a pending transaction. Otherwise yes: after a deployment, a deferral (contention or
// keep-last-good) or a failure M3 has undone, the committed generation is the last good one.
struct AfterDeployment {
  bool may_activate = false;
  std::string reason;
};
AfterDeployment after_deployment(const deploy::Report& deployment, bool pending);

struct Prepared {
  config::Config config;
  deploy::Report deployment;
  std::optional<journal::Journal> journal;
  bool may_activate = false;
  std::string reason;
  double elapsed_ms = 0;
};

// Missing/disabled/invalid config or invalid journal never reaches the deployer. Successful
// deployment (including held/kept generations), or contention with no pending transaction, may
// activate the current generation. No environment, command-line or DLL changes here.
Prepared prepare(const std::filesystem::path& root, std::uint32_t process_id);

}  // namespace nl::startup
