# 0030: Non-NVIDIA GPUs get Remix's own preset; the runtime's late DLLs load with it

- Status: Accepted 2026-10-29
- Decided by: the user (asked "Is AMD graphics cards users compatible?" in a side session, read its
  findings and chose to fold "the FSR loading fix and the non-NVIDIA preset fix" into round 8),
  Claude choosing how
- Builds on: [0008](0008-activation-at-startup.md) (activation); amends [0010](0010-rtx-session-extras.md)
  point 4 (the runtime folder on `PATH` does not reach the runtime's late loads),
  [0020](0020-classic-rtx-settings-as-defaults.md) and [0021](0021-remix-defaults-in-one-low-layer.md):
  their classic settings stay the defaults, except the graphics preset on a computer without an NVIDIA GPU

## Context

- **The runtime's late DLLs were never found under the loader** ([RESEARCH.md](../RESEARCH.md)
  section 27). The runtime lives in `native-loader\packages\...\runtime`, not beside `gmod.exe`. Its
  static imports load with it (`LOAD_WITH_ALTERED_SEARCH_PATH`), but four DLLs are loaded later by
  bare name: `amd_fidelityfx_vk.dll` (the fork's FSR probe when it creates the device,
  `rtx_fork_fsr.cpp:537`), and `cudart64_13.dll`, `nvrtc64_130_0.dll` and `nvrtc-builtins64_133.dll`
  (CUDA, which NVIDIA's NRC library loads seconds later). In every loader session the Remix log says FSR
  "could not be loaded" and NRC "Failed to initialize"; the classic install (runtime in `bin\win64`)
  loads all four, with FSR on and NRC running.
- **No search finds the runtime folder by then.** The game's loads use Windows' standard search
  (`gmod.exe`'s folder, System32, the working directory, `PATH`). The runtime folder has been first on
  `PATH` since M5, but the process's `PATH` is rewritten before those loads, from the value the process
  started with and with the Steam folder in front: a running game's `PATH` holds neither the runtime
  folder nor `gmod.exe`'s own `bin\win64` entry. The standard search never reads `AddDllDirectory`
  folders, so a first version of this decision, which added the folder that way, changed nothing (the
  end-to-end run still logged both failures). `gmod.exe`'s copy of Chromium's sandbox code switches a
  process to the safe set (System32 and user folders) only when its DLL-search mitigation is asked for.
- **The files themselves are fine.** In a fresh process all four load from the runtime folder: by bare
  name with the folder first on `PATH`, by bare name after `AddDllDirectory` and the sandbox's
  `SetDefaultDllDirectories` call, and by absolute path.
- **The package pins `rtx.graphicsPreset = 4` (Custom)** in its classic defaults layer: the classic
  install's look, tuned for an RTX 5090. The runtime picks a preset per GPU only when the preset is
  Auto (5): for a non-NVIDIA GPU, Low with its non-NVIDIA defaults (half resolution, TAA-U or NIS at
  Performance). Its per-GPU overrides (`rtx.gpuOverride.graphicsPreset.VVVV_DDDD`) name single devices
  and apply only under Auto, so they cannot say "every AMD GPU".
- **What else holds on AMD** (the side session's reading of the fork): only the KHR ray-tracing
  extensions are required, so Radeon RX 6000 and newer qualify; DLSS falls back to TAA-U, NRC to
  ReSTIR GI; DLSS frame generation and Reflex are NVIDIA-only; FSR and XeSS run on AMD.

## Decision

1. **The late DLLs load with the runtime.** Right after the runtime's `d3d9.dll`, the bootstrap loads
   the runtime package's deployed `amd_fidelityfx_vk.dll`, `cudart64_*.dll`, `nvrtc64_*.dll` and
   `nvrtc-builtins64_*.dll` at the top of its folder (`activate::late_runtime_dll`), by absolute path
   (`LOAD_WITH_ALTERED_SEARCH_PATH`), after checking them as deployed like every runtime file. A later
   load by bare name of a DLL already loaded binds to that module, whatever the search and `PATH`. A
   DLL that does not load costs its feature, as before, and a note in `session.notes`; rollback frees
   them. `status.json` lists what loaded (`activation.preloaded`), `nlctl activation` the plan's list.
   The runtime folder also stays first on `PATH` and becomes an `AddDllDirectory` folder, for loads
   that do read those.
2. **No NVIDIA GPU: Remix's automatic preset.** At activation the bootstrap lists the hardware graphics
   adapters through DXGI (loaded from System32 at run time; the import table stays KERNEL32-only).
   When none is NVIDIA (vendor `0x10DE`), it writes `native-loader\remix\non-nvidia.conf`
   (`rtx.graphicsPreset = 5`) and lists it in `DXVK_CONFIG_FILE` above the package's layers and below
   the user's `dxvk.conf`; `rtx.conf` and `user.conf` win over it too. With an NVIDIA GPU, or when the
   adapters cannot be read, nothing changes. `status.json` reports `activation.gpu_vendors` and
   `non_nvidia`; `nlctl activation` prints them.

## Consequences

- FSR's DLL loads under the loader (FSR upscaling and frame generation, for AMD players above all), and
  the Neural Radiance Cache runs again on NVIDIA GPUs, as in the classic install: measured on the RTX
  5090, and FSR's DLL also on the integrated Radeon (RESEARCH.md section 27).
- The four DLLs (about 113 MB, most of it `nvrtc64_130_0.dll`) are mapped in every RTX session from
  the start, where the classic install mapped them on first use.
- A runtime that loads another DLL late by bare name needs its name in `late_runtime_dll`; the Remix
  log names the feature that misses it.
- An AMD or Intel player starts from Remix's choice for their GPU; their own preset in Remix's menu,
  saved to `user.conf`, still wins. An NVIDIA player sees no change.
- On a computer with an NVIDIA and another GPU, Remix normally takes the NVIDIA one; the classic preset
  stays, which matches.
- The adapter list costs one DXGI factory at the start of an RTX session (a few milliseconds).

## Alternatives considered

- **`AddDllDirectory` alone** (this decision's first version): the standard search never reads it.
- **`SetDllDirectoryW`** (M4, which found them): it also takes the working directory out of the search,
  which the RTX fixes need ([0010](0010-rtx-session-extras.md)), and the fixes' module calls
  `SetDllDirectoryW` itself.
- **Setting `PATH` again later**: nothing marks the moment, and another rewrite would undo it.
- **Loading them from `d3d9.dll`'s own folder in the fork**: right for FSR, but needs a runtime rebuild,
  and NRC's CUDA loads happen inside NVIDIA's NRC library.
- **The names in the package manifest**: they would travel with the runtime, but need a new manifest
  field and a rebuilt runtime part, for four names of the runtime's own.
- **Every DLL of the runtime folder**: would run the start-up code of DLLs that load only on demand
  (DLSS, NRD) for nothing.
- **Per-GPU overrides in the defaults layer**: one entry per device, and only under Auto, which would
  change the preset of every NVIDIA GPU not listed.
- **`DXVK_CONFIG` in the environment**: the environment wins over the user's own files, so a player
  could not keep a preset of their own.
- **Listing the GPUs through Vulkan, as Remix does**: an extra Vulkan instance at start-up would load
  every driver and implicit layer (overlays) once more.
