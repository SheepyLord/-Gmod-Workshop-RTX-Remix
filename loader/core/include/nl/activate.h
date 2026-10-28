#pragma once
// Working out what the bootstrap does at start-up once the runtime is deployed (M4): which
// environment variables to set, the config-file layer lists, the d3d9.dll to preload and the launch
// arguments to add. activate::plan() is a pure function of the journal's current generation, the
// config and the process environment and command line; it reads nothing from disk. The bootstrap
// (loader/proxy) applies the plan with Win32 calls. Paths it returns are relative to the game root,
// which is the runtime's working directory, so the install path never enters a comma-separated list.

#include "nl/config.h"
#include "nl/manifest.h"
#include "nl/journal.h"

#include <functional>
#include <optional>
#include <string>
#include <string_view>
#include <utility>
#include <vector>

namespace nl::activate {

// Existing environment values, in UTF-8. nullopt means absent; an empty string is a present value.
// Package config layers precede the user's nonempty list; ordinary package variables never replace
// a value the user already set (including an empty one).
using EnvGet = std::function<std::optional<std::string>(const std::string& name)>;

// Win32 environment adapter shared by the CLI and bootstrap; absent and empty stay distinct.
std::optional<std::string> environment_value(const std::string& name);

// The primary display's current mode in pixels; 0 x 0 when it cannot be read. The plan reads it only
// when it sizes the RTX session's window (ADR 0018).
struct Display {
  unsigned width = 0;
  unsigned height = 0;
};
using DisplayGet = std::function<Display()>;

// Win32 display adapter shared by the CLI and bootstrap (EnumDisplaySettingsW, physical pixels).
Display primary_display();

struct Plan {
  bool activate = false;  // false: the runtime is not loaded and nothing below is applied
  std::string reason;     // why not, or (when active) a short note
  std::string runtime_id;
  std::string runtime_version;

  std::string runtime_dll;  // deployed d3d9.dll, relative to root; metadata may be present while RTX is off
  std::string runtime_dir;  // folder added to the DLL search for late bare-name loads (relative)
  bool prefer_system_vulkan = false;

  // SetEnvironmentVariable calls, in order: the two config-file layer lists first (only when the
  // package adds layers, retaining the user's list last), then the package's own variables
  // (only those the user has not set). Manifest values are ASCII; user values may be UTF-8.
  std::vector<std::pair<std::string, std::string>> env;
  std::vector<std::pair<std::string, std::string>> user_env;
  std::vector<std::string> rtx_layers;
  std::vector<std::string> dxvk_layers;

  // Arguments to append to the command line: the package's launch_args minus any the user already
  // passed, in the manifest's order, then a borderless window the size of the primary display unless
  // the user chose a window mode (ADR 0018). ASCII.
  std::vector<std::string> launch_args;
  std::vector<std::string> present_args;

  // RTX-session extras from every deployed package (M5, ADR 0010), in generation order. Only
  // filled when the plan activates; the bootstrap applies them for this session only.
  struct PatchSet {
    std::string package;
    manifest::PatchSet set;
  };
  struct Override {
    std::string package;
    std::string module;  // DLL base name the game loads from bin/win64
    std::string file;    // the replacement, relative to the game root
  };
  std::vector<PatchSet> patch_sets;
  std::vector<Override> module_overrides;
  std::vector<std::pair<std::string, std::string>> session_cvars;  // a later package wins a name
  std::vector<std::string> notes;  // e.g. a module two packages override (the first wins)
  bool patch_sets_need_insecure = true;  // config patch_sets.require_insecure
};

// The runtime package is the deployed package that has a remix section and a payload. With none, or
// with remix.enabled false, the plan is inactive. `command_line` is the process command line, read
// only to skip launch arguments the user set. `display` is called at most once, and only when the
// plan sizes the window.
Plan plan(const journal::Generation& generation, const config::Config& config, const EnvGet& env,
          std::wstring_view command_line, const DisplayGet& display);

}  // namespace nl::activate
