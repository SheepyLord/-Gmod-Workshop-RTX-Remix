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
#include "nl/performance.h"
#include "nl/memory_profile.h"
#include "nl/gpu_diagnostics.h"

#include <cstdint>
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

// Hardware adapters and their dedicated VRAM; empty when DXGI cannot read them. Only queried at RTX
// activation. The class/VRAM policy itself lives in the pure performance::classify function.
using GpuGet = std::function<std::vector<performance::Adapter>()>;

// Win32 adapter shared by the CLI and bootstrap: DXGI, loaded from System32 at run time, software
// adapters left out.
std::vector<performance::Adapter> graphics_adapters();
// A driver description is optional; invalid UTF-16/allocation failure becomes an empty name.
std::string adapter_description(std::wstring_view description) noexcept;

// The total physical memory in bytes, 0 when unknown (R13 memory profile, ADR 0101). Only queried at
// RTX activation; the profile policy itself lives in the pure memory_profile::plan function.
using RamGet = std::function<std::uint64_t()>;
std::uint64_t physical_memory() noexcept;  // Win32 GlobalMemoryStatusEx

inline constexpr unsigned kNvidia = 0x10DE;

// The folder of the Remix layers the bootstrap writes. The package's config layers reach the runtime
// as copies here with short fixed names, dxvk-<n>.conf and rtx-<n>.conf (ADR 0036): the runtime reads
// DXVK_CONFIG_FILE and DXVK_RTX_CONFIG_FILE into a 260-character buffer and takes a longer value as
// empty (RESEARCH.md sections 19 and 32), and the published package's payload folder path alone is 74.
inline constexpr std::string_view kLayerFolder = "native-loader/remix";

// Remix's defaults on a computer without an NVIDIA GPU (ADR 0030). The package's classic settings pin
// the graphics preset to Custom, tuned for NVIDIA GPUs; this layer, written by the bootstrap above the
// package's layers and below the user's own files, gives Remix its automatic choice for the GPU back.
inline constexpr std::string_view kNonNvidiaLayer = "native-loader/remix/non-nvidia.conf";
std::string non_nvidia_layer_text();

inline constexpr std::string_view kTierLayer = "native-loader/remix/tier.conf";
std::string low_tier_layer_text();  // old runtime packages without config/dxvk-tiers/low.conf

// The memory profile's runtime budgets (ADR 0101; memory_profile::layer_text). D3D9 options only, read by
// DXVK's merged config: listed after the package's layers and before the user's dxvk.conf (ADR 0062).
inline constexpr std::string_view kMemoryLayer = "native-loader/remix/memory.conf";

// The runtime's DLLs that load late by bare name (ADR 0030): the fork's FSR probe (amd_fidelityfx_vk.dll)
// and NRC's CUDA runtime and compiler (cudart64_*, nvrtc64_*, nvrtc-builtins64_*). In GMod no search
// finds them in the runtime folder by then (RESEARCH.md section 27), so the bootstrap loads them by
// absolute path right after the runtime and the late loads bind to those modules. A file name, ASCII,
// any case.
bool late_runtime_dll(std::string_view file_name);

struct Plan {
  bool activate = false;  // false: the runtime is not loaded and nothing below is applied
  std::string reason;     // why not, or (when active) a short note
  std::string runtime_id;
  std::string runtime_version;

  std::string runtime_dll;  // deployed d3d9.dll, relative to root; metadata may be present while RTX is off
  std::string runtime_dir;  // folder added to the DLL search for late bare-name loads (relative)
  // The runtime package's deployed late_runtime_dll files at the top of runtime_dir, relative to root,
  // sorted; loaded after the runtime. Only filled when the plan activates.
  std::vector<std::string> preload;
  bool prefer_system_vulkan = false;
  std::vector<unsigned> gpu_vendors;  // the hardware adapters' vendor ids, when the plan activates
  bool non_nvidia = false;            // none of them is NVIDIA: kNonNvidiaLayer goes into DXVK_CONFIG_FILE
  performance::Selection performance_tier;  // R6 interface I2
  bool low_tier_fallback = false;
  // R13 (ADR 0101), chosen when the plan activates with a RAM reader; its layer is kMemoryLayer then.
  memory_profile::Budget memory;
  bool gpu_crash_dumps = false;
  bool gpu_crash_dumps_once = false;
  bool reset_gpu_crash_dumps = false;  // off on an RTX start re-arms next_start, best effort
  std::optional<std::string> gpu_dump_package_value;  // restore this request if diagnostics preparation fails

  // SetEnvironmentVariable calls, in order: the two config-file layer lists first (only when the
  // package adds layers, retaining the user's list last), then the package's own variables
  // (only those the user has not set). Manifest values are ASCII; user values may be UTF-8.
  std::vector<std::pair<std::string, std::string>> env;
  std::vector<std::pair<std::string, std::string>> user_env;
  std::vector<std::string> rtx_layers;
  std::vector<std::string> dxvk_layers;
  // The package's layers in those lists are copies (ADR 0036): `copy`, in kLayerFolder, holds the bytes
  // of `source`, in the payload folder. The bootstrap writes each at every RTX start, after checking
  // `source` against the journal.
  struct LayerCopy {
    std::string source;
    std::string copy;
  };
  std::vector<LayerCopy> layer_copies;

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
  // Binary modules that need files loaded before them (ADR 0024). They apply in every session; a
  // start without a runtime installs them itself (proxy startup.cpp).
  std::vector<manifest::ModuleDependency> module_dependencies;
  std::vector<std::string> notes;  // e.g. a module two packages override (the first wins)
  bool patch_sets_need_insecure = true;  // config patch_sets.require_insecure
  bool allow_secure_rtx_render_patches = true;
};

// The runtime package is the deployed package that has a remix section and a payload. With none, or
// with remix.enabled false, the plan is inactive. `command_line` is the process command line, read
// only to skip launch arguments the user set. `display` is called at most once, and only when the
// plan sizes the window. `gpus` is called once when the plan activates; without it (or with no
// adapter found) auto applies neither loader GPU layer; an explicit tier still applies. `ram` is
// called once when the plan activates; without it the plan chooses no memory profile and lists no
// memory layer, and the runtime sizes its own budgets.
Plan plan(const journal::Generation& generation, const config::Config& config, const EnvGet& env,
          std::wstring_view command_line, const DisplayGet& display, const GpuGet& gpus = {},
          const gpu_diagnostics::Probe& diagnostics = {}, const RamGet& ram = {});

// For the copies the bootstrap could not write: their sources go into the lists and variables
// instead, and they leave layer_copies, with a note when a list is then too long for the runtime.
void use_sources(Plan& plan, const std::vector<std::string>& unwritten);

// A built-in fallback that cannot be written must not load an older tier.conf from disk.
void disable_performance_tier(Plan& plan, const std::string& reason);

// A memory layer that cannot be written must not load an older memory.conf from disk: the runtime
// then sizes its own budgets. The profile stays in status for the hotloader.
void disable_memory_layer(Plan& plan, const std::string& reason);

// A diagnostics preparation failure costs diagnostics, not RTX. Removes its layer/environment
// request, retaining any package DXVK layers and the user's original config-list suffix.
void disable_gpu_crash_dumps(Plan& plan, const std::string& reason);

}  // namespace nl::activate
