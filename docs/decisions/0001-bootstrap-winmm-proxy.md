# 0001: The bootstrap is a `winmm.dll` proxy that works at the EXE entry point

- Status: Accepted 2026-10-27
- Decided by: the user (SheepyLord), on the recommendation in the M0 plan

## Context

The user installs one native module into `GarrysMod\bin\win64`. It must run before the engine creates
its Direct3D 9 device (to load the Remix runtime) and ideally before any engine DLL reads its
configuration (to deploy files in time). Lua binary modules (`gmcl_*`) load far too late.

`bin\win64\gmod.exe` statically imports `WINMM.dll` and `dbghelp.dll`; neither is a KnownDLL, so a
DLL of that name in `bin\win64` is loaded instead of the system one, before `launcher.dll`, `tier0`
or `engine.dll` ([RESEARCH.md §1](../RESEARCH.md)). `shaderapidx9.dll` imports `d3d9.dll`, the hook
point Remix itself normally uses.

## Decision

The bootstrap is `bin\win64\winmm.dll`:

- It forwards every export of `%SystemRoot%\System32\winmm.dll` (export list generated from the
  system DLL at build time).
- `DllMain` does almost nothing (loader lock): checks the host is `bin\win64\gmod.exe` and the off
  switches, then hooks the EXE entry point.
- The real work runs at the EXE entry point, where all static imports are loaded and the loader
  lock is free, before `WinMain`.

## Consequences

- Runs before every engine DLL, so it can deploy root files, preload the runtime as `d3d9.dll`
  ([ADR 0004](0004-runtime-in-versioned-folder.md)) and register patches for DLLs not loaded yet.
- The user's own `d3d9.dll` in `bin\win64` (DXVK in the field install) keeps working for non-RTX launches.
- `winmm` is used by `tier0`, `engine` and others: forwarding must be complete and correct (M1
  acceptance test).
- Any GMod tool in `bin\win64` that pulls in `winmm` also loads the proxy; the host check keeps it inert there.
- Another mod that also ships a `winmm.dll` proxy would conflict; none is installed today.

## Alternatives considered

- **`d3d9.dll` shim**: loads with `shaderapidx9.dll`, after the engine reads its start-up files; must
  re-export the runtime's ~116 `d3d9` and `remixapi_*` exports, which change between runtime
  versions; would replace the field install's DXVK `d3d9.dll`. The earlier Astra startup loader in
  `garrys-mod-rtx-remixed` took this route.
- **`dbghelp.dll` proxy**: equally early, but crash reporting and the runtime itself use it, and
  its API is larger and stateful.
- **Lua binary module**: loads after device creation; cannot load the runtime for the current session.
