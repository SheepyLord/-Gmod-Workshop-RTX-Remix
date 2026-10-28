// nl_fault_host: runs one deployer command with fault injection, for deploy_faults.py (a CTest).
//
//   nl_fault_host <apply|rollback|uninstall|recover> <game root> [--kill-at N | --fail-at N]
//
// --kill-at N ends the process (exit code 99) just before the Nth file-system change, as a crash or a
// power cut at that moment would; --fail-at N makes that change fail with an error instead. Prints
// the outcome, the number of changes made and the error as one JSON line. Exit 0 ok, 1 refused or
// failed, 2 bad usage or invalid input. Test-only: nlctl has no such switches.

#include "nl/config.h"
#include "nl/core.h"
#include "nl/deploy.h"
#include "nl/discovery.h"
#include "nl/fs.h"
#include "nl/json.h"
#include "nl/manifest.h"
#include "nl/planner.h"

#include <windows.h>

#include <cstdio>
#include <optional>
#include <string>
#include <vector>

namespace {

int usage() {
  std::fputs("usage: nl_fault_host <apply|rollback|uninstall|recover> <game root> [--kill-at N | --fail-at N]\n", stderr);
  return 2;
}

}  // namespace

int wmain(int argc, wchar_t** argv) {
  std::vector<std::wstring> args(argv + 1, argv + argc);
  std::optional<std::uint64_t> kill_at;
  std::optional<std::uint64_t> fail_at;
  for (std::size_t i = 0; i + 1 < args.size();) {
    if (args[i] == L"--kill-at" || args[i] == L"--fail-at") {
      (args[i] == L"--kill-at" ? kill_at : fail_at) = std::stoull(args[i + 1]);
      args.erase(args.begin() + static_cast<std::ptrdiff_t>(i), args.begin() + static_cast<std::ptrdiff_t>(i) + 2);
    } else {
      ++i;
    }
  }
  if (args.size() != 2) return usage();
  const std::filesystem::path root(args[1]);
  nl::fs::Counting disk(nl::fs::win32(), [&](std::uint64_t change, std::string_view what) {
    if (kill_at && change == *kill_at) {
      std::fflush(stdout);
      TerminateProcess(GetCurrentProcess(), 99);
    }
    if (fail_at && change == *fail_at) {
      throw nl::fs::Error("injected failure before change " + std::to_string(change) + " (" + std::string(what) + ")", 0);
    }
  });
  nl::deploy::Options options;
  options.filesystem = &disk;
  options.allow_running_game = true;  // no game runs from the scratch folders this is used on; saves a process scan per run
  try {
    nl::deploy::Report report;
    if (args[0] == L"apply") {
      const nl::config::Config config = nl::config::load(root);
      const auto env = nl::discovery::environment_for(root, root / "no-steam");
      report = nl::deploy::apply(root, nl::planner::consider(nl::discovery::discover(config, env)), config,
                                 *nl::manifest::parse_version(nl::version()), options);
    } else if (args[0] == L"rollback") {
      report = nl::deploy::rollback(root, options);
    } else if (args[0] == L"uninstall") {
      report = nl::deploy::uninstall(root, options);
    } else if (args[0] == L"recover") {
      report = nl::deploy::recover(root, options);
    } else {
      return usage();
    }
    const std::string line = "{\"outcome\": " + nl::json::quote(report.outcome) + ", \"operations\": " +
                             std::to_string(disk.operations()) + ", \"error\": " + nl::json::quote(report.error) + "}\n";
    std::fwrite(line.data(), 1, line.size(), stdout);
    return report.ok() ? 0 : 1;
  } catch (const std::exception& e) {
    std::fprintf(stderr, "error: %s\n", e.what());
    return 2;
  }
}
