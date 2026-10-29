#include "nl/startup.h"
#include "nl/fs.h"
#include "nl/core.h"
#include "nl_test.h"
#include <windows.h>
#include <filesystem>
#include <fstream>

namespace {
namespace fs = std::filesystem;
void write(const fs::path& path, const std::string& text) {
  fs::create_directories(path.parent_path());
  std::ofstream(path, std::ios::binary) << text;
}
nl::journal::Generation current(const std::string& source = "local", const std::string& location = "C:/packages/runtime.gma") {
  nl::journal::Generation generation;
  generation.number = 1;
  nl::journal::Package package;
  package.id = "runtime";
  package.version = "1.0.0";
  package.manifest_sha256 = std::string(64, 'a');
  package.source = source;
  package.location = location;
  generation.packages.push_back(package);
  return generation;
}
nl::planner::Decision unavailable() {
  nl::planner::Decision decision;
  decision.item.candidate.source = nl::discovery::Source::local;
  decision.item.candidate.label = "C:/packages/runtime.gma";
  decision.item.candidate.location = L"c:\\PACKAGES\\runtime.gma";
  decision.item.problem = "file not found";
  decision.reason = decision.item.problem;
  return decision;
}
}  // namespace

TEST_CASE("startup: missing or invalid allowlisted sources keep the deployed generation") {
  nl::planner::Plan proposed;
  proposed.decisions.push_back(unavailable());
  REQUIRE(nl::startup::keep_last_good_reason(current(), proposed).has_value());
  proposed.decisions[0].item.problem = "cannot be deployed: SHA-256 differs";
  CHECK(nl::startup::keep_last_good_reason(current(), proposed).has_value());
  auto fallback = std::make_shared<nl::package::Package>();
  fallback->manifest.id = "runtime";
  fallback->manifest_sha256 = std::string(64, 'b');
  nl::planner::Decision other;
  other.active = true;
  other.item.package = fallback;
  proposed.decisions.push_back(other);
  CHECK(nl::startup::keep_last_good_reason(current(), proposed).has_value());
  fallback->manifest_sha256 = std::string(64, 'a');
  CHECK(!nl::startup::keep_last_good_reason(current(), proposed));
}

TEST_CASE("startup: removed sources and disabled Workshop items are deliberate removals") {
  CHECK(!nl::startup::keep_last_good_reason(current(), nl::planner::Plan{}));
  auto deployed = current("workshop", "H:/steamapps/workshop/content/4000/123/old_legacy.bin");
  auto missing = unavailable();
  missing.item.candidate.source = nl::discovery::Source::workshop;
  missing.item.candidate.label = "123";
  missing.item.candidate.location.clear();
  nl::planner::Plan proposed;
  proposed.decisions.push_back(missing);
  CHECK(nl::startup::keep_last_good_reason(deployed, proposed).has_value());
  proposed.decisions[0].item.candidate.disabled_by_user = true;
  CHECK(!nl::startup::keep_last_good_reason(deployed, proposed));
  // Unsubscribed (Steam lists the item nowhere and its files are gone) is the user's removal too (ADR 0025).
  proposed.decisions[0].item.candidate.disabled_by_user = false;
  proposed.decisions[0].item.candidate.unsubscribed = true;
  CHECK(!nl::startup::keep_last_good_reason(deployed, proposed));
}

TEST_CASE("startup: only a package removed because its Workshop item was unsubscribed loses its rollback copy") {
  const auto deployed = current("workshop", "H:/steamapps/workshop/content/4000/123/old_legacy.bin");
  auto gone = unavailable();
  gone.item.candidate.source = nl::discovery::Source::workshop;
  gone.item.candidate.label = "123";
  gone.item.candidate.location.clear();
  nl::planner::Plan plan;
  plan.decisions.push_back(gone);
  CHECK(nl::startup::unsubscribed_packages(deployed, plan).empty());  // only missing: it may come back
  plan.decisions[0].item.candidate.unsubscribed = true;
  CHECK(nl::startup::unsubscribed_packages(deployed, plan) == std::set<std::string>{"runtime"});
  plan.decisions[0].item.candidate.label = "124";  // another item
  CHECK(nl::startup::unsubscribed_packages(deployed, plan).empty());
  plan.decisions[0].item.candidate.label = "123";
  CHECK(nl::startup::unsubscribed_packages(current(), plan).empty());  // deployed from a local archive
  // Still deployed, from another source: not removed, so nothing to delete either.
  auto copy = std::make_shared<nl::package::Package>();
  copy->manifest.id = "runtime";
  nl::planner::Decision local;
  local.active = true;
  local.item.package = copy;
  plan.decisions.push_back(local);
  CHECK(nl::startup::unsubscribed_packages(deployed, plan).empty());
}

TEST_CASE("startup: an incompatible replacement cannot discard the last good runtime") {
  auto decision = unavailable();
  decision.item.problem.clear();
  auto replacement = std::make_shared<nl::package::Package>();
  replacement->manifest.id = "runtime";
  replacement->manifest.requires_loader = nl::manifest::parse_version("99.0.0");
  replacement->manifest_sha256 = std::string(64, 'b');
  decision.item.package = replacement;
  nl::planner::Plan plan;
  plan.decisions.push_back(decision);
  CHECK(nl::startup::keep_last_good_reason(current(), plan).has_value());
}

TEST_CASE("startup: after a deployment, only a pending transaction prevents activation") {
  nl::deploy::Report report;
  report.outcome = "deployed";
  CHECK(nl::startup::after_deployment(report, false).may_activate);
  CHECK(!nl::startup::after_deployment(report, true).may_activate);
  report.outcome = "refused";
  report.blocked_by = nl::deploy::Report::BlockedBy::deployer_lock;
  CHECK(nl::startup::after_deployment(report, false).may_activate);
  // A failed transaction is undone in process: the committed generation is still the last good one.
  report.outcome = "failed";
  report.blocked_by = nl::deploy::Report::BlockedBy::none;
  report.error = "move failed";
  const auto failed = nl::startup::after_deployment(report, false);
  CHECK(failed.may_activate);
  CHECK(failed.reason.find("move failed") != std::string::npos);
  CHECK(!nl::startup::after_deployment(report, true).may_activate);
}

TEST_CASE("startup: absent disabled or invalid configuration never deploys or removes") {
  const auto root = nl::test::scratch_dir("startup_config");
  auto result = nl::startup::prepare(root, GetCurrentProcessId());
  CHECK(!result.may_activate);
  CHECK(result.deployment.outcome == "skipped");
  CHECK(!fs::exists(root / "native-loader"));
  write(root / "native-loader/config.json", R"({"schema":1,"enabled":false})");
  write(root / "native-loader/state.json", "do not touch this invalid journal");
  result = nl::startup::prepare(root, GetCurrentProcessId());
  CHECK(!result.may_activate && result.deployment.outcome == "skipped");
  CHECK(!fs::exists(root / "native-loader/lock"));
  write(root / "native-loader/config.json", "invalid config");
  result = nl::startup::prepare(root, GetCurrentProcessId());
  CHECK(!result.may_activate && result.deployment.outcome == "failed");
  CHECK(nl::fs::read_file(root / "native-loader/state.json", 1024) == "do not touch this invalid journal");
  fs::remove_all(root);
}

TEST_CASE("startup: an invalid journal is refused before lock creation") {
  const auto root = nl::test::scratch_dir("startup_invalid_journal");
  write(root / "native-loader/config.json", R"({"schema":1})");
  write(root / "native-loader/state.json", "invalid journal");
  const auto result = nl::startup::prepare(root, GetCurrentProcessId());
  CHECK(!result.may_activate && result.deployment.outcome == "failed");
  CHECK(!fs::exists(root / "native-loader/lock"));
  CHECK(nl::fs::read_file(root / "native-loader/state.json", 1024) == "invalid journal");
  fs::remove_all(root);
}

TEST_CASE("startup: lock contention permits only a journal with no pending transaction") {
  const auto root = nl::test::scratch_dir("startup_lock");
  write(root / "native-loader/config.json", R"({"schema":1})");
  nl::journal::Journal journal;
  journal.loader = std::string(nl::version());
  journal.next = 2;
  journal.current = nl::journal::Generation{1, {}, {}};
  write(root / "native-loader/state.json", nl::journal::serialize(journal));
  const HANDLE lock = CreateFileW((root / L"native-loader/lock").c_str(), GENERIC_READ | GENERIC_WRITE,
                                 0, nullptr, OPEN_ALWAYS, FILE_ATTRIBUTE_NORMAL, nullptr);
  REQUIRE(lock != INVALID_HANDLE_VALUE);
  auto result = nl::startup::prepare(root, GetCurrentProcessId());
  CHECK(result.may_activate);
  CHECK(result.deployment.blocked_by == nl::deploy::Report::BlockedBy::deployer_lock);
  journal.pending = nl::journal::Pending{2, "apply", {{nl::journal::Step::Op::make_dir, "", "native-loader/backup/2", ""}}};
  const auto pending = nl::journal::serialize(journal);
  write(root / "native-loader/state.json", pending);
  result = nl::startup::prepare(root, GetCurrentProcessId());
  CHECK(!result.may_activate);
  CHECK(result.reason.find("pending") != std::string::npos);
  CHECK(nl::fs::read_file(root / "native-loader/state.json", 4096) == pending);
  CloseHandle(lock);
  fs::remove_all(root);
}
