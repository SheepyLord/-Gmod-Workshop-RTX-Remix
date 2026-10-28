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

## config.json (draft)

```json
{
  "schema": 1,
  "enabled": true,
  "allow": {
    "workshop": ["3600000000"],
    "local": ["garrysmod/addons/rtx-remix-runtime.gma"],
    "dev_folders": []
  },
  "remix": { "enabled": true },
  "patch_sets": { "require_insecure": true }
}
```

- `allow` is the native-code allowlist ([ADR 0003](decisions/0003-native-trust-allowlist.md)).
  Workshop items not listed are never opened as packages.
- `remix.enabled = false` keeps packages deployed but loads no runtime (vanilla rendering).

## Off switches (any one)

| Switch | Effect |
|---|---|
| Launch option `-nonativeloader` | Pure pass-through for this launch |
| Environment variable `NATIVE_LOADER_DISABLE=1` | Same |
| File `native-loader\disable` | Same, until the file is deleted |
| Delete `bin\win64\winmm.dll` | Loader gone; deployed files stay inert until `uninstall-loader.ps1` removes them |
