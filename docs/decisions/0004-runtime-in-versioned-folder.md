# 0004: The Remix runtime is preloaded from a versioned folder, not copied into `bin\win64`

- Status: Accepted 2026-10-27
- Decided by: follows from ADR 0001 and the M0 plan the user approved

## Context

The classic install copies the runtime (`d3d9.dll` and about 40 dependencies) into `bin\win64`. That
mixes our files with Steam's, clobbers any `d3d9.dll` already there (the field install uses DXVK for
non-RTX play), and makes switching or rolling back runtime versions a file-by-file affair.

Facts ([RESEARCH.md §1-2](../RESEARCH.md)): an import binds to an already-loaded module of the same
name; the runtime's static dependencies resolve from its own folder when it is loaded with an altered
search path; DLSS, NRD and USD locate their files relative to `d3d9.dll`; configs, mods and logs
follow the working directory (the game root) and can be redirected with environment variables.

## Decision

- Each runtime version is extracted to `native-loader\packages\<id>\<version>\`.
- At start-up the bootstrap loads `<that folder>\runtime\d3d9.dll` with `LOAD_WITH_ALTERED_SEARCH_PATH`
  before any engine DLL; `shaderapidx9.dll` then binds to it.
- Package config files become lower layers through `DXVK_CONFIG_FILE` / `DXVK_RTX_CONFIG_FILE`; the
  user's root `rtx.conf` stays the top, editable layer and `user.conf` is untouched.
- Optionally System32's `vulkan-1.dll` is preloaded first, so a non-system copy in `bin\win64`
  (GModPatchTool ships one) cannot shadow it.
- Fallback if M4 finds a dependency that only works beside `gmod.exe`: a journaled side-by-side
  deployment into `bin\win64`, recorded as a new decision.

## Consequences

- Version switch and rollback are a pointer change; `bin\win64` holds only `winmm.dll` from us.
- With RTX off nothing is preloaded and the install behaves exactly as before.
- Late `LoadLibrary` calls by bare name inside the runtime would search `bin\win64`, System32 and
  `PATH`, not the runtime folder: M4 must check the runtime's lazily loaded DLLs (DLSS-FG, Reflex,
  XeSS, FSR) and add the folder to the search path if needed.
