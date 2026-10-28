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

AfterDeployment after_deployment(const deploy::Report& deployment, bool pending) {
  if (pending) return {false, "journal has a pending transaction; activation is unsafe until recovery"};
  if (deployment.ok()) return {true, "deployment state is ready"};
  if (deployment.blocked_by != deploy::Report::BlockedBy::none)
    return {true, "deployment deferred; using the current committed generation"};
  // M3 undoes a failed transaction in process; with no pending transaction left, the committed
  // generation is intact and runs as the last good one (ADR 0009).
  return {true, "deployment failed (" + (deployment.error.empty() ? std::string("did not complete") : deployment.error) +
                    "); using the current committed generation"};
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
      std::vector<discovery::Candidate> candidates;
      for (const auto& item : considered) candidates.push_back(item.candidate);
      deploy::Options options;
      options.exclude_process_id = process_id;
      options.keep_last_good = true;
      const auto loader = manifest::parse_version(nl::version());
      if (!loader) throw std::runtime_error("loader version is invalid");
      result.deployment = deploy::apply(root, std::move(considered), result.config,
                                       *loader, options);
      result.journal = journal::load(root);
      if (result.journal && result.journal->current) {
        for (const auto& package : result.journal->current->packages) {
          status::PackageSource entry{package.id, package.version, package.source, package.location, std::nullopt};
          for (const auto& candidate : candidates) {
            if (!same_source(package, candidate)) continue;
            entry.label = candidate.label;
            entry.time_updated = candidate.time_updated;
            break;
          }
          result.sources.push_back(std::move(entry));
        }
      }
      const auto next = after_deployment(result.deployment, result.journal && result.journal->pending);
      result.may_activate = next.may_activate;
      result.reason = next.reason;
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
