# 0011: Packages may deploy GMod add-on folders (`garrysmod/addons/<addon>/`)

- Status: Accepted 2026-10-28. **Confirmed by the user on 2026-10-28** ("This should address 0011",
  with the approval of the Workshop distribution test). The test showed that a native package on the
  Workshop also needs these folders, because GMod does not mount such an item itself
  ([ADR 0015](0015-workshop-route-for-native-packages.md)). [ADR 0014](0014-r1-hardening.md) narrows
  the area: every file must be inside the add-on's folder.
- **Superseded in part by [0035](0035-restore-automatically.md)** (2026-10-29, the user): a player's
  folder of the same name no longer blocks the package (its files at the package's paths are kept
  aside and put back later), and a changed file is put back. The rest of this record stands.
- Decided by: Claude, implementing M5 under the user's 2026-10-28 instruction to finish M5-M7 without
  further approvals. This widens the package path rules, which AGENTS.md rule 4 reserves for a record
  the user agreed to; the user has since confirmed it (above).
- Builds on: [0003](0003-native-trust-allowlist.md); the areas of [PACKAGE_FORMAT.md](../PACKAGE_FORMAT.md)

## Context

The RTX fixes are half Lua: add-ons such as `remixbinary` (which `require`s the binary module),
`rtx_water`, `niknaks`. The classic install keeps them as add-on folders in `garrysmod/addons`. A
Workshop package gets its Lua mounted by GMod (M6), but a local package does not: GMod x64 mounts
add-on **folders** in `garrysmod/addons` and does not mount a loose `.gma` placed there (tested on
the PoC: "Adding Filesystem Addon 'addons/nl_probe_folder'" for a folder, nothing for a plain-Lua
`.gma`; [RESEARCH.md](../RESEARCH.md) section 13). Without the Lua, the fixes' binary module is never
loaded.

## Decision

A new root-file area, `garrysmod/addons/<addon>/...`, for a new kind `lua-addon`:

- each root file names a folder at least one level below `garrysmod/addons`;
- policy `replace-owned` only, with M3's ownership rules: a folder file someone else placed blocks
  the package unless identical (adopted), files the user changed stay and are reported;
- the allowlist still decides which packages may deploy at all; Lua add-ons are not native code, so
  this adds less power than the native code those packages already carry.

## Consequences

- A local fixes package works like the classic install, with no manual copying.
- The add-on folders are visible in GMod's add-on list as legacy add-ons, and are removed by uninstall.
- An add-on folder name a user already has (a manual copy of the fixes) blocks the package until the
  user removes the copy or it matches exactly.

## Alternatives considered

- **Workshop-only Lua.** Leaves local packages (development, M6's fallback route) without their Lua.
- **`garrysmod/lua/autorun`.** Refused by the path rules on purpose: one shared folder, every file
  runs everywhere, and it holds Steam's files.
- **A loose `.gma` in `garrysmod/addons`.** GMod x64 does not mount it.
