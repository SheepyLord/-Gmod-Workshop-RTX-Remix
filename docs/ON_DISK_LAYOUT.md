# On-disk layout (game side)

What the loader adds to a Garry's Mod install. Everything except `bin\win64\winmm.dll` is created
by the loader itself and listed in its journal, so it can all be removed again.

```
GarrysMod\
├─ bin\win64\winmm.dll                     the bootstrap (installed by the user or install-loader.ps1)
├─ native-loader\
│  ├─ config.json                          user policy: allowlist, switches, options (created with defaults)
│  ├─ state.json                           journal: packages, deployed files with SHA-256, backups
│  ├─ disable                              optional empty file: loader stays a pass-through
│  ├─ packages\<id>\<version>\...          extracted payloads, e.g. ...\rtx-remix-runtime\1.6.1+gmod.20261025\runtime\d3d9.dll
│  ├─ staging\                             in-progress extractions (deleted after each run)
│  ├─ backup\<timestamp>\...               files the loader replaced, with original paths
│  └─ logs\loader.log                      start-up step log (rotated)
├─ rtx-remix\mods\<mod>\...                root files from packages (journaled)
├─ rtx.conf, dxvk.conf, user.conf          the user's own Remix configs (top layers; never overwritten)
└─ garrysmod\
   ├─ lua\bin\gmcl_*_win64.dll             binary modules from packages (journaled)
   └─ data\native-loader\status.json       written each start for the Lua companion
```

## config.json (schema 1)

Implemented by `nl::config` (`loader/core/src/config.cpp`). Check what the loader would do with
`nlctl plan <game root>`.

```json
{
  "schema": 1,
  "enabled": true,
  "allow": {
    "workshop": ["3600000000"],
    "local": ["garrysmod/addons/rtx-remix-runtime.gma"],
    "dev_folders": ["D:/dev/rtx-remix-runtime"]
  },
  "remix": { "enabled": true },
  "patch_sets": { "require_insecure": true }
}
```

| Key | Default | Rule |
|---|---|---|
| `schema` | required | the integer `1` |
| `enabled` | `true` | `false`: nothing is activated |
| `allow.workshop` | `[]` | Workshop item ids **as strings** (large numbers lose digits in some editors), no repeats |
| `allow.local` | `[]` | `.gma` / `.bin` archives, relative to the game root or absolute |
| `allow.dev_folders` | `[]` | unpacked package folders (with `native/manifest.json`), relative or absolute |
| `remix.enabled` | `true` | `false`: runtime packages stay planned but no runtime is loaded (vanilla rendering) |
| `patch_sets.require_insecure` | `true` | in-memory patch sets (M5) only with `-insecure` |

- `allow` is the native-code allowlist ([ADR 0003](decisions/0003-native-trust-allowlist.md)).
  Nothing else is opened as a package; without a config file nothing is allowlisted.
- Strict JSON; **unknown keys are errors** (a typo such as `"alow"` stops the loader instead of
  silently allowing nothing or something else). An invalid file leaves the loader inactive.
- Which allowlisted package wins when several qualify: [ADR 0006](decisions/0006-package-precedence-and-planning.md).

## Off switches (any one)

| Switch | Effect |
|---|---|
| Launch option `-nonativeloader` | Pure pass-through for this launch |
| Environment variable `NATIVE_LOADER_DISABLE=1` | Same |
| File `native-loader\disable` | Same, until the file is deleted |
| Delete `bin\win64\winmm.dll` | Loader gone; deployed files stay inert until `uninstall-loader.ps1` removes them |
