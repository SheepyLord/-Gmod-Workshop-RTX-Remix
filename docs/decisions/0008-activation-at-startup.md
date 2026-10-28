# 0008: Activation at start-up — preload, config layers, environment and launch arguments

- Status: Accepted 2026-10-27. Revised before merge on 2026-10-27: validate and restore complete
  command-line descriptors, prepend package layers to user lists, and apply activation in a
  reversible order with preload last (M4 handover section 4.1).
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

Before activation, require the working directory to be the game root, the runtime entry and all
package layer files to exist with their journaled sizes, and the absolute runtime DLL path to fit
in `MAX_PATH`. With RTX off or no deployed runtime, none of the following steps runs.

Apply these steps in order:

1. **Environment and config layers.** When the package declares layers, set `DXVK_RTX_CONFIG_FILE`
   to the package's layers (lowest first), followed by the user's existing nonempty list verbatim.
   If the variable is absent or empty, append `rtx.conf`, preserving the runtime's default editable
   root layer. Do the same for `DXVK_CONFIG_FILE` and `dxvk.conf`. With no package layers leave the
   variable alone. Package paths are relative to the game root; user paths and order stay intact.
   Other `DXVK_*` / `RTX_*` package variables are set only when absent, including preserving an
   existing empty value. Remember every modified variable's prior presence and value for undo.
   The user's final layer remains the Remix menu's save target, and `user.conf` is untouched.
2. **Launch arguments.** `append_arguments` adds only manifest arguments not already present,
   preserving user values such as `-dxlevel 95`. Validate the kernelbase W/A getter shape and the
   `Buffer`, `Length`, `MaximumLength` of both caches and the PEB before any write. All new lengths
   include room for the terminator in a `USHORT`. Update the complete descriptors transactionally;
   any failed/partial write rolls back attempted slots. The result supports explicit or scoped
   restore until activation commits. A refused swap **prevents activation**; restore environment
   and report the exact fallback launch options, which only the user may choose to add to Steam.
   If those options were supplied already, there is no swap to perform and activation can proceed.
3. **System Vulkan.** If requested, load System32's `vulkan-1.dll` by full path and retain our
   reference only on successful activation.
4. **Delay-load search.** `SetDllDirectoryW(<absolute runtime folder>)` makes the bare-name
   delay-loaded `amd_fidelityfx_vk.dll` resolvable from the package.
5. **Runtime preload.** `LoadLibraryExW(<absolute runtime d3d9.dll>, nullptr,
   LOAD_WITH_ALTERED_SEARCH_PATH)` runs last. The path must be absolute. On success, retain the
   runtime and Vulkan references, environment and committed command line for process lifetime.
6. **Report.** Atomically write `garrysmod\data\native-loader\status.json` and append matching
   `key=value` log fields, including inactive reasons and fallback arguments.

Any failed step undoes the earlier ones and continues vanilla. In particular, a failed runtime
load records the Windows error and which of `msvcp140.dll`, `vcruntime140.dll`,
`vcruntime140_1.dll` and `vulkan-1.dll` are missing from System32, then resets the DLL directory
with `SetDllDirectoryW(nullptr)`, releases our Vulkan reference, restores all command-line
descriptors and restores the prior environment. C++ exceptions and SEH faults are contained at
the start-up boundary; no partially applied activation is accepted.

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
