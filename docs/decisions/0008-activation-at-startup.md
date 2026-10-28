# 0008: Activation at start-up — preload, config layers, environment and launch arguments

- Status: Accepted 2026-10-27
- Decided by: Claude, implementing M4 within the plan the user approved on 2026-10-27
- Builds on: [ADR 0001](0001-bootstrap-winmm-proxy.md) (the entry-point hook),
  [ADR 0004](0004-runtime-in-versioned-folder.md) (the runtime in a versioned folder),
  [ADR 0007](0007-transactional-deployment.md) (the journal the activation reads)

## Context

M3 deploys a runtime package into `native-loader\packages\<id>\<version>_<generation>\` and records
it in the journal. M4 must make that runtime the one `gmod.exe` uses, with the configuration the RTX
fixes need, and do it from inside the process before the engine creates its D3D9 device — the
bootstrap's entry-point hook runs there, after all static imports are loaded and the loader lock is
free ([ADR 0001](0001-bootstrap-winmm-proxy.md)).

Facts ([RESEARCH.md](../RESEARCH.md) §1-2, §8):

- Windows binds an import to a module already loaded under the same base name. `shaderapidx9.dll`
  imports `d3d9.dll`; if `d3d9.dll` is already loaded, that is what it binds to.
- The runtime's dependencies (`usd_*`, NRC, NRD, DLSS, `libxess`, ...) resolve from the folder of
  `d3d9.dll` when it is loaded with `LOAD_WITH_ALTERED_SEARCH_PATH`, except its one delay-loaded
  `amd_fidelityfx_vk.dll`, which is searched by bare name (so the runtime folder must be on the DLL
  search path).
- `d3d9.dll` also imports the VC++ 2015-2022 runtime (`MSVCP140`, `VCRUNTIME140`, `VCRUNTIME140_1`)
  and `vulkan-1.dll`; on this machine those live only in System32, not in `bin\win64`.
- The runtime reads config layers lowest-first; `DXVK_RTX_CONFIG_FILE` / `DXVK_CONFIG_FILE` give
  comma-separated lists, and the **last** `rtx.conf` layer is the one the Remix menu saves to. With
  the variable unset it reads `.\rtx.conf` only. Layer paths are opened relative to the working
  directory, which is the game root. `user.conf` has no override and is never touched.
- All engine modules link the C runtime statically and read the command line after the entry point,
  through kernelbase's `GetCommandLineW`/`GetCommandLineA` (KERNEL32 forwards to them) and the PEB.
  On this Windows build both getters are `mov rax,[rip+disp]; ret`: they return a pointer held at a
  fixed address.
- RTXLauncher starts GMod with `-dxlevel 90 +mat_disable_d3d9ex 1 -nod3d9ex`.

## Decision

At the entry point, after deploying (one `nl::deploy::apply` in automatic mode), the bootstrap
activates the runtime of the journal's current generation. `nl::activate::plan` works out the steps
as a pure function; the bootstrap applies them with Win32 calls, each guarded, so any failure leaves
the game vanilla and logged. Activation happens only with a runtime deployed and `remix.enabled`
true.

1. **Preload.** `LoadLibraryExW(<payload>\runtime\d3d9.dll, LOAD_WITH_ALTERED_SEARCH_PATH)`, and
   `SetDllDirectoryW(<payload>\runtime)` first so the delay-loaded `amd_fidelityfx_vk.dll` is found
   there. `shaderapidx9.dll` then binds to this module. With RTX off, nothing is preloaded and the
   DLL search is not touched.
2. **Config layers.** When the package declares layers and the user has not set the variable,
   `DXVK_RTX_CONFIG_FILE` = the package's `rtx.conf` layers (lowest first), then `rtx.conf`; likewise
   `DXVK_CONFIG_FILE`. The user's root `rtx.conf` stays the top, editable layer the menu saves to,
   and `user.conf` is untouched. Paths are **relative to the game root**, so the install path — which
   may hold spaces or commas — never enters the comma-separated list. With no package layers the
   variable is left unset, so discovery is exactly the runtime's default.
3. **Environment.** The package's own `DXVK_*` / `RTX_*` variables are set, except any the user has
   already set: the user wins.
4. **System Vulkan.** When the package asks (`prefer_system_vulkan_loader`), System32's `vulkan-1.dll`
   is preloaded first, so a non-system copy in `bin\win64` (GModPatchTool ships one) cannot shadow it.
5. **Launch arguments.** `nl::cmdline::append_arguments` adds the package's `launch_args`
   (`-dxlevel 90 -nod3d9ex +mat_disable_d3d9ex 1`), minus any the user already passed, by pointing
   kernelbase's two command-line caches and the PEB at longer strings. It verifies each getter is the
   `mov rax,[rip+disp]; ret` shape and currently points at this process's command line; if not, it
   changes nothing and the loader reports the arguments to add as Steam launch options instead.
6. **Report.** `garrysmod\data\native-loader\status.json` and `loader.log` record what was done.

The VC++ runtime is not packaged; the loader relies on the system redistributable (as the classic
install does) and reports it in the log if the preload fails for a missing dependency.

## Consequences

- With RTX on, the runtime loads from its versioned folder and `bin\win64` still holds only our
  `winmm.dll`; a version switch or rollback is a journal change, picked up at the next launch.
- With RTX off, or on any activation failure, the preload, the environment and the command line are
  untouched (or undone) and the game renders exactly as vanilla.
- Launch arguments depend on kernelbase's getter shape. It is validated at run time, not assumed; a
  future Windows build that changes it makes the loader fall back to documented launch options rather
  than patch the wrong memory.
- `-dxlevel 90` may persist in GMod's saved video settings; the PoC acceptance run checks that an
  RTX-off launch afterwards is still vanilla, and this record is revised if a mitigation is needed.
- The runtime folder goes on the process DLL search path while RTX is on (`SetDllDirectoryW`), which
  also removes the current directory from that search; acceptable because it happens only with RTX on.

## Alternatives considered

- **IAT patching of `GetCommandLine*` in each engine module.** Rejected: modules load at different
  times (some after the device is up), and tier0 caches the command line, so one early, process-wide
  change to the kernelbase cache is simpler and catches every reader.
- **Relaunching `gmod.exe` with the extra arguments.** Rejected: it doubles start-up, fights Steam's
  process tracking, and loses the already-initialised process.
- **Only documented Steam launch options.** Kept as the fallback, not the default: it needs the user
  to edit Steam every time and cannot adapt per package.
- **Absolute layer paths.** Rejected: they reintroduce the install path (spaces, commas) into the
  comma-separated list; relative-to-cwd paths avoid it and match how the runtime finds `rtx.conf`.
- **Copying the runtime into `bin\win64`.** Rejected by [ADR 0004](0004-runtime-in-versioned-folder.md).
