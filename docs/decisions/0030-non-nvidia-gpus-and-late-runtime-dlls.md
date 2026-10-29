# 0030: Non-NVIDIA GPUs get Remix's own preset; the runtime's late DLLs are found again

- Status: Accepted 2026-10-29
- Decided by: the user (asked "Is AMD graphics cards users compatible?" in a side session, read its
  findings and chose to fold "the FSR loading fix and the non-NVIDIA preset fix" into round 8),
  Claude choosing how
- Builds on: [0008](0008-activation-at-startup.md) (activation), [0010](0010-rtx-session-extras.md)
  (the runtime folder on `PATH`); amends [0020](0020-classic-rtx-settings-as-defaults.md) and
  [0021](0021-remix-defaults-in-one-low-layer.md): their classic settings stay the defaults, except the
  graphics preset on a computer without an NVIDIA GPU

## Context

- **The runtime's late DLLs were never found under the loader** ([RESEARCH.md](../RESEARCH.md)
  section 26). The runtime lives in `native-loader\packages\...\runtime`, not beside `gmod.exe`. Its
  static imports load with it (`LOAD_WITH_ALTERED_SEARCH_PATH`), but four DLLs are loaded later by
  bare name: `amd_fidelityfx_vk.dll` (FSR, `rtx_fork_fsr.cpp:537`), and `cudart64_13.dll`,
  `nvrtc64_130_0.dll` and `nvrtc-builtins64_133.dll` (CUDA, for the Neural Radiance Cache). Since M5 the
  runtime folder was on `PATH` only. In every loader session the Remix log says FSR "could not be
  loaded" and NRC "Failed to initialize", and the process has none of the four, nor the driver's
  `nvcuda.dll`; the classic install (runtime in `bin\win64`) has all of them, with FSR loaded and NRC
  running. Those loads search the "safe" folder set, which never reads `PATH`.
- **The package pins `rtx.graphicsPreset = 4` (Custom)** in its classic defaults layer: the classic
  install's look, tuned for an RTX 5090. The runtime picks a preset per GPU only when the preset is
  Auto (5): for a non-NVIDIA GPU, Low with its non-NVIDIA defaults (half resolution, TAA-U or NIS at
  Performance). Its per-GPU overrides (`rtx.gpuOverride.graphicsPreset.VVVV_DDDD`) name single devices
  and apply only under Auto, so they cannot say "every AMD GPU".
- **What else holds on AMD** (the side session's reading of the fork): only the KHR ray-tracing
  extensions are required, so Radeon RX 6000 and newer qualify; DLSS falls back to TAA-U, NRC to
  ReSTIR GI; DLSS frame generation and Reflex are NVIDIA-only; FSR and XeSS run on AMD.

## Decision

1. **The runtime folder is a user DLL folder too.** At activation, after `PATH`, the bootstrap calls
   `AddDllDirectory` for the runtime folder (removed again on rollback), so searches that use the safe
   folder set find the runtime's late DLLs. `PATH` stays for searches that read it.
2. **No NVIDIA GPU: Remix's automatic preset.** At activation the bootstrap lists the hardware graphics
   adapters through DXGI (loaded from System32 at run time; the import table stays KERNEL32-only).
   When none is NVIDIA (vendor `0x10DE`), it writes `native-loader\remix\non-nvidia.conf`
   (`rtx.graphicsPreset = 5`) and lists it in `DXVK_CONFIG_FILE` above the package's layers and below
   the user's `dxvk.conf`; `rtx.conf` and `user.conf` win over it too. With an NVIDIA GPU, or when the
   adapters cannot be read, nothing changes. `status.json` reports `activation.gpu_vendors` and
   `non_nvidia`; `nlctl activation` prints them.

## Consequences

- FSR (upscaling and frame generation) works under the loader, for AMD players above all, and the Neural
  Radiance Cache runs again on NVIDIA GPUs, as in the classic install.
- An AMD or Intel player starts from Remix's choice for their GPU; their own preset in Remix's menu,
  saved to `user.conf`, still wins. An NVIDIA player sees no change.
- On a computer with an NVIDIA and another GPU, Remix normally takes the NVIDIA one; the classic preset
  stays, which matches.
- The adapter list costs one DXGI factory at the start of an RTX session (a few milliseconds).

## Alternatives considered

- **Preloading the four DLLs by absolute path**: fixes these four names only, and a runtime update
  could load others.
- **Loading them from `d3d9.dll`'s own folder in the fork**: right for FSR, but needs a runtime rebuild,
  and NRC's CUDA loads happen inside NVIDIA's NRC library.
- **Per-GPU overrides in the defaults layer**: one entry per device, and only under Auto, which would
  change the preset of every NVIDIA GPU not listed.
- **`DXVK_CONFIG` in the environment**: the environment wins over the user's own files, so a player
  could not keep a preset of their own.
- **Listing the GPUs through Vulkan, as Remix does**: an extra Vulkan instance at start-up would load
  every driver and implicit layer (overlays) once more.
