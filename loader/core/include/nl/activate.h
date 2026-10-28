#pragma once
// Working out what the bootstrap does at start-up once the runtime is deployed (M4): which
// environment variables to set, the config-file layer lists, the d3d9.dll to preload and the launch
// arguments to add. activate::plan() is a pure function of the journal's current generation, the
// config and the process environment and command line; it reads nothing from disk. The bootstrap
// (loader/proxy) applies the plan with Win32 calls. Paths it returns are relative to the game root,
// which is the runtime's working directory, so the install path never enters a comma-separated list.

#include "nl/config.h"
#include "nl/journal.h"

#include <functional>
#include <string>
#include <string_view>
#include <utility>
#include <vector>

namespace nl::activate {

// Is an environment variable set in this process? The bootstrap wraps GetEnvironmentVariableW; tests
// pass a set of names. A variable the user already set is left as it is: the user wins.
using EnvHas = std::function<bool(const std::string& name)>;

struct Plan {
  bool activate = false;  // false: the runtime is not loaded and nothing below is applied
  std::string reason;     // why not, or (when active) a short note

  std::string runtime_dll;  // d3d9.dll to preload, relative to the game root; empty unless active
  std::string runtime_dir;  // folder added to the DLL search for late bare-name loads (relative)
  bool prefer_system_vulkan = false;

  // SetEnvironmentVariable calls, in order: the two config-file layer lists first (only when the
  // package adds layers and the user has not set the variable), then the package's own variables
  // (only those the user has not set). Names and values are ASCII.
  std::vector<std::pair<std::string, std::string>> env;

  // Arguments to append to the command line, the package's launch_args minus any the user already
  // passed. ASCII, in the manifest's order.
  std::vector<std::string> launch_args;
};

// The runtime package is the deployed package that has a remix section and a payload. With none, or
// with remix.enabled false, the plan is inactive. `command_line` is the process command line, read
// only to skip launch arguments the user set.
Plan plan(const journal::Generation& generation, const config::Config& config, const EnvHas& env,
          std::wstring_view command_line);

}  // namespace nl::activate
