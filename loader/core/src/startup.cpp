#include "nl/startup.h"
#include "nl/core.h"
#include "nl/discovery.h"
#include "nl/fs.h"
#include <windows.h>
#include <algorithm>
#include <chrono>

namespace nl::startup {
namespace {
bool same_source(const journal::Package& deployed, const discovery::Candidate& candidate) {
  if (deployed.source != discovery::source_name(candidate.source)) return false;
  auto original = fs::join({}, deployed.location).lexically_normal().make_preferred();
  if (candidate.source == discovery::Source::workshop) {
    return fs::utf8(original.parent_path().filename()) == candidate.label;
  }
  auto proposed = candidate.location.lexically_normal().make_preferred();
  return CompareStringOrdinal(original.c_str(), -1, proposed.c_str(), -1, TRUE) == CSTR_EQUAL;
}
}  // namespace

std::optional<std::string> keep_last_good_reason(const journal::Generation& current, const planner::Plan& proposed) {
  for (const auto& deployed : current.packages) {
    const bool remains = std::any_of(proposed.decisions.begin(), proposed.decisions.end(), [&](const auto& decision) {
      return decision.active && decision.item.package && decision.item.package->manifest.id == deployed.id &&
             decision.item.package->manifest_sha256 == deployed.manifest_sha256;
    });
    if (remains) continue;
    for (const auto& decision : proposed.decisions) {
      const auto& item = decision.item;
      if (!same_source(deployed, item.candidate) || item.candidate.disabled_by_user) continue;
      const auto loader = manifest::parse_version(nl::version());
      const bool incompatible = item.package && item.package->manifest.requires_loader && loader &&
          manifest::compare(*loader, *item.package->manifest.requires_loader) < 0;
      if (!item.problem.empty() || !item.package || incompatible) {
        const auto problem = !item.problem.empty() ? item.problem : incompatible ? "requires a newer loader" : "not loaded";
        return "kept " + deployed.id + " " + deployed.version + ": allowlisted source " + item.candidate.label +
               " is unavailable or invalid (" + problem + ")";
      }
    }
  }
  return std::nullopt;
}

Prepared prepare(const std::filesystem::path& root, std::uint32_t process_id) {
  Prepared result;
  result.deployment.action = "apply";
  result.deployment.outcome = "skipped";
  const auto started = std::chrono::steady_clock::now();
  try {
    fs::refuse_links(root, config::kConfigPath);
    result.config = config::load(root);
    if (!result.config.from_file) {
      result.reason = "native-loader/config.json is absent";
    } else if (!result.config.enabled) {
      result.reason = "enabled is false in native-loader/config.json";
    } else {
      // Check before any deployment-side writes, including lock creation or stale-file cleanup.
      fs::refuse_links(root, journal::kPath);
      result.journal = journal::load(root);
      discovery::Environment environment;
      if (result.config.workshop.empty()) environment.game_root = root;
      else environment = discovery::environment_for(root);
      auto considered = planner::consider(discovery::discover(result.config, environment));
      deploy::Options options;
      options.exclude_process_id = process_id;
      options.keep_last_good = true;
      const auto loader = manifest::parse_version(nl::version());
      if (!loader) throw std::runtime_error("loader version is invalid");
      result.deployment = deploy::apply(root, std::move(considered), result.config,
                                       *loader, options);
      result.journal = journal::load(root);
      if (result.journal && result.journal->pending) {
        result.reason = "journal has a pending transaction; activation is unsafe until recovery";
      } else if (result.deployment.ok() || result.deployment.blocked_by != deploy::Report::BlockedBy::none) {
        result.may_activate = true;
        result.reason = result.deployment.blocked_by == deploy::Report::BlockedBy::none ?
            "deployment state is ready" : "deployment deferred; using the current committed generation";
      } else {
        result.reason = result.deployment.error.empty() ? "deployment did not complete" : result.deployment.error;
      }
    }
  } catch (const std::exception& error) {
    result.may_activate = false;
    result.reason = error.what();
    result.deployment.outcome = "failed";
    result.deployment.error = error.what();
  }
  if (result.deployment.outcome == "skipped" && !result.reason.empty()) result.deployment.notes.push_back(result.reason);
  result.elapsed_ms = std::chrono::duration<double, std::milli>(std::chrono::steady_clock::now() - started).count();
  return result;
}
}  // namespace nl::startup
