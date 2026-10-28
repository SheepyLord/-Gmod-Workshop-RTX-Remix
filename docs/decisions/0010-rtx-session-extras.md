# 0010: RTX-session extras: in-memory patch sets, module overrides and session console variables

- Status: Accepted 2026-10-28
- Decided by: Claude, implementing M5 under the user's 2026-10-28 instruction to plan, build and test
  M5-M7 without further approvals. Review it: it gives allowlisted packages three new powers.
- Builds on: [0002](0002-source-agnostic-payloads.md), [0003](0003-native-trust-allowlist.md),
  [0008](0008-activation-at-startup.md); facts in [RESEARCH.md](../RESEARCH.md) sections 11-12

## Context

The classic RTX install renders as it does because of three things besides the runtime
([RESEARCH.md](../RESEARCH.md) section 12):

- seven byte patches RTXLauncher writes into `engine`, `shaderapidx9`, `materialsystem` and `datacache`
  on disk (`patches64`);
- the fixes' fixed-function `stdshader_dx6.dll` replacing the game's on disk;
- an `autoexec.cfg` with the RTX console variables, archived into that install's own `config.cfg`.

None of these can be copied as they are: rule 2 forbids writing Steam's files, and in one install with
RTX on and off they would also change RTX-off sessions. M4 showed the runtime alone does not path-trace
the stock shaders (with `d3d9.shaderModel = 0` they are rejected; with 3 the frame stays raster).

## Decision

Three new manifest fields (schema 1, additive), applied **only in sessions where a runtime activates**:

1. **`patch_sets`** (kind `patch-set`): per DLL base name, patches of the form find-pattern (hex with
   `??`, 1-256 bytes), offset, replacement inside the match. The bootstrap registers a DLL-load watcher
   (`LdrRegisterDllNotification`, resolved from ntdll at run time) and patches each game DLL when it is
   mapped, before its code runs (its imports are bound by then: section 11). A pattern must occur
   **exactly once** across the module's sections, as RTXLauncher requires on disk; otherwise that patch
   is skipped and reported. Patch sets apply only in `-insecure` sessions unless `config.json` sets
   `patch_sets.require_insecure: false`; `package_runtime.py --insecure` adds `-insecure` to the
   runtime's launch arguments (now allowed), like the classic launch line.
2. **`module_overrides`** (kind `module-override`): a DLL the game loads from `bin\win64` by full path
   (`stdshader_dx6.dll`) is loaded from the package's payload instead. The watcher hooks the
   `LoadLibraryA/W` and `LoadLibraryExA/W` imports of every game module as it is mapped (and of those
   already mapped), and redirects a load of exactly `<root>\bin\win64\<module>`. The replacement keeps
   the module's file name, which the fixes' module looks up by name.
3. **`session_cvars`**: console variable assignments (names `[A-Za-z0-9_]{1,64}`, values
   `[A-Za-z0-9_.+-]{0,32}`: no commands, quotes or separators). The bootstrap writes them to
   `garrysmod/cfg/nativeloader_session.cfg` and adds `+exec nativeloader_session.cfg`. Because the game
   archives most variables into `config.cfg` when it quits, the bootstrap first records the user's
   archived values for those names (`native-loader/session_cvars.json`), and at the next start
   **without** RTX writes `nativeloader_restore.cfg` with them and adds `+exec nativeloader_restore.cfg`,
   once; the start after that forgets the record. The generated files start with a header line and are
   only ever replaced or removed when they carry it.

4. **The runtime folder goes on `PATH`, not `SetDllDirectoryW`** (supersedes point 4 of
   [ADR 0008](0008-activation-at-startup.md)). `SetDllDirectoryW` also removes the working directory
   from the DLL search, and the fixes' module finds GMod's own modules with
   `GetModuleHandleExA("bin/win64/lua_shared.dll")`, a path relative to the working directory
   (garrysmod_common `ModuleLoader.cpp`): on the PoC that lookup failed, the module got neither
   `LUACONVARS001` nor `VEngineCvar007`, and the game ended with `0xC0000409` after the map loaded.
   Putting the runtime folder first among the `PATH` entries keeps the working directory in the
   search and still resolves the runtime's late bare-name loads (the delay-loaded
   `amd_fidelityfx_vk.dll`, CUDA's `nvrtc`). The old `PATH` is restored on rollback like every other
   variable.

Results go to `garrysmod/data/native-loader/session.json` (patches applied or skipped with reasons,
loads redirected) and the start-up summary to `status.json` (`session`).

## Consequences

- RTX off stays vanilla: no watcher, no patches, no override, and the variables an RTX session changed
  are put back at the first RTX-off start.
- A GMod update that moves a pattern makes that patch skip (reported), not misapply.
- An RTX session that crashes before quitting writes no `config.cfg`, so nothing leaks; if the RTX-off
  session that runs the restore crashes, the RTX values stay archived (reported; rare).
- Uninstalling the loader removes the generated cfgs and `session.json`, but cannot run a pending
  restore; `nlctl uninstall` keeps the record so a reinstall can.
- In-memory patches are what VAC looks for; that is why they need `-insecure` by default.
- `winmm.dll` still imports only KERNEL32.

## Alternatives considered

- **Patching the DLLs on disk (journaled, with backups).** Rejected: rule 2, Steam verify and updates.
- **Hooking `IFileSystem::LoadModule` or adding an `EXECUTABLE_PATH` folder for the shader DLL.** The
  first needs the interface before `materialsystem` runs, the second a writable search path; an import
  hook at map time is simpler and catches every caller.
- **An inline hook on kernelbase's `LoadLibraryExW`.** Needs an instruction-length decoder (third-party
  code) and changes every load in the process; import hooks change only the game's modules.
- **Setting the console variables from Lua.** Too late for some and blocked for others (`sv_cheats`),
  and it would not solve the archiving.
- **Writing the user's `config.cfg`.** It is the user's file (rule 3's spirit); a cfg the game runs
  itself changes nothing on disk that the user owns.
