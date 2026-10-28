# 0013: Add-ons of RTX-only packages are hidden from sessions without RTX, in memory

- Status: Accepted 2026-10-28
- Decided by: Claude, implementing M5 under the user's 2026-10-28 instruction to plan, build and test
  M5-M7 without further approvals. It narrows what a package does (nothing is loosened); review it
  with [ADR 0011](0011-lua-addon-folders.md), which it completes.
- Builds on: [0010](0010-rtx-session-extras.md) ("RTX off stays vanilla"), [0011](0011-lua-addon-folders.md);
  facts in [RESEARCH.md](../RESEARCH.md) section 13

## Context

ADR 0010 keeps the loader's own RTX extras (patch sets, the shader override, session variables) out
of sessions without a runtime. ADR 0011 lets a package deploy Lua add-on folders, and those are on
disk whatever the session: in a PoC start with `remix.enabled: false`, GMod mounted all nine add-ons
of the fixes package, their server Lua ran ("[RTX Flashlight] Default flashlight override:
ENABLED"), and the client Lua loaded the fixes' binary module. The module noticed Remix was missing
("remix::loadRemixDllAndInitialize() failed"), applied none of its own engine patches and shut down,
but the session was not vanilla.

Undeploying the package whenever RTX is off was considered and rejected. The fixes write into their
own deployed files at run time (the ToPBR converter rewrote `rtx-remix/mods/~gmod_topbr/materials.usda`
during the first PoC session), and the deployer leaves a file it placed but that changed since in place
and stops tracking it (M3). The next RTX start would then find a file "not placed by the loader" and
refuse the whole package: one off/on toggle would break the fixes. It would also copy 1.4 GB at every
toggle.

GMod mounts add-on folders from the searches `filesystem_stdio.dll` makes of `garrysmod\addons`; that
DLL imports `FindFirstFileA`, `FindNextFileA`, `FindFirstFileExW` and `FindNextFileW` from KERNEL32.

## Decision

1. A new optional manifest flag, `"requires_remix": true`: the package only makes sense with a Remix
   runtime. The journal keeps it per package (written only when true). `package_fixes.py` sets it.
2. In a start where no runtime is active (RTX off, no runtime package, activation failed or deferred),
   with the loader enabled, the bootstrap leaves the `garrysmod/addons/<name>/` folders of those
   packages out of `filesystem_stdio.dll`'s searches of `<root>\garrysmod\addons`: import hooks on its
   `FindFirstFileA/W/ExW`, `FindNextFileA/W` and `FindClose`, installed through the M5 DLL-load watcher
   when the DLL maps. Other folders, other add-ons and other modules' searches are not touched; the
   files stay on disk and in the journal.
3. Reported in `status.json` (`session.hidden_addons`) and `session.json` (`hidden_addons`: the folders,
   the ones a search actually left out, and the hooked module).

## Consequences

- RTX off is vanilla for such a package's Lua as well; toggling RTX costs nothing on disk, and the
  deployer and its journal are unchanged.
- The package's other files (its `gmcl_` modules in `garrysmod/lua/bin`, `rtx-remix/mods`) stay on
  disk. Nothing loads them in an RTX-off session once the add-ons are hidden, unless another add-on
  `require`s the module: the fixes' module then shuts itself down without Remix (observed).
- With the loader disabled (`enabled: false` in `config.json`, or an off switch) the bootstrap does
  nothing, so the add-ons are visible. Uninstalling removes them.
- If GMod ever searches `garrysmod\addons` from another module or with other functions, the folders
  would show up again; the M5 synthetic test (`nl_session_integration`) and the PoC check
  (`Adding Filesystem Addon` lines in `console.log`) would show it.

## Alternatives considered

- **Undeploy RTX-only packages while RTX is off.** Rejected above: an off/on toggle breaks the
  package once the fixes have written into their files, and every toggle copies the package.
- **Teach the fixes' Lua to check for Remix.** Their code, not this repo's (GPL-2.0, rule 7), and it
  would not help other packages.
- **Hide the add-ons with `addonnomount.txt`.** A user file the loader must not edit (rule 3), and
  GMod archives it.
