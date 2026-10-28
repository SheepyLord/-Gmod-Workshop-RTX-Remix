# Package format (draft, schema 1)

> **Draft.** Fixed in M2 together with the parser and its tests. Change it only with a note in
> [CHANGELOG.md](../CHANGELOG.md) and, for breaking changes, a decision record.

A **package** is an ordinary `.gma` (GMAD v1-v3, optionally LZMA-wrapped) that contains
`native/manifest.json`. GMod mounts the rest of it as usual; the loader reads the `.gma` file
directly from disk. Archives are built with [`tools/gmapack`](../tools/gmapack/gmapack.py.md);
container format: [tools/gmapack/GMA_FORMAT.md](../tools/gmapack/GMA_FORMAT.md).

## Layout inside the .gma

```
native/manifest.json        what the package is and how to activate it (below)
native/payload/**           extracted to native-loader\packages\<id>\<version>\  (runtime DLLs, configs)
native/root/**              deployed to the game root, same relative path, allowed prefixes only
lua/**, materials/**, ...   normal GMod content, mounted by GMod; the loader ignores it
```

Paths in GMA files are lowercase by convention (`gmad` lowercases); the loader compares
case-insensitively, as Windows does.

## manifest.json

```json
{
  "schema": 1,
  "id": "rtx-remix-runtime",
  "name": "RTX Remix runtime for GMod x64",
  "version": "1.6.1+gmod.20261025",
  "kinds": ["remix-runtime"],
  "requires_loader": ">=0.1.0",
  "files": {
    "native/payload/runtime/d3d9.dll": { "size": 338675200, "sha256": "…" },
    "native/payload/config/rtx.conf":  { "size": 161131,    "sha256": "…" }
  },
  "remix": {
    "entry": "runtime/d3d9.dll",
    "rtx_conf_layers": ["config/rtx.conf"],
    "dxvk_conf_layers": ["config/dxvk.conf"],
    "env": { "DXVK_LOG_LEVEL": "info" },
    "launch_args": ["-dxlevel", "90", "-nod3d9ex", "+mat_disable_d3d9ex", "1"],
    "prefer_system_vulkan_loader": true
  },
  "root_files": [
    { "path": "rtx-remix/mods/base_mod", "policy": "replace-owned" }
  ]
}
```

| Field | Meaning |
|---|---|
| `schema` | Manifest schema version; the loader refuses schemas it does not know |
| `id` | Stable package id, `[a-z0-9-]+`; one installed version per id is active |
| `version` | SemVer-like; compared to choose and to roll back |
| `kinds` | One or more of the kinds below |
| `requires_loader` | Minimum loader version |
| `files` | Every file under `native/` with size and SHA-256 (integrity; the authenticity of the manifest itself is a later milestone) |
| `remix` | Only for `remix-runtime`: entry DLL and config layers relative to the payload folder, env vars, launch arguments |
| `root_files` | Paths under `native/root/` and how to deploy them |

## Kinds

| Kind | Deploys | Activation |
|---|---|---|
| `remix-runtime` | payload to `native-loader\packages\<id>\<version>\` | Preload `remix.entry` as `d3d9.dll`, set config layers, env, launch args. At most one active. |
| `lua-binary-module` | `gmcl_*` / `gmsv_*` DLLs (and helper EXEs) to `garrysmod\lua\bin\` | None: Lua `require` loads them as usual |
| `root-files` | files under the game root (e.g. `rtx-remix\mods\<mod>`) | None |
| `patch-set` | nothing on disk | Data-only byte patches (module, signature, expected bytes, replacement) applied in memory when the module loads (M5) |
| `module-override` | replacement for an engine DLL such as `stdshader_dx6.dll` | Redirected load or journaled on-disk override, decided in M5 |

## Root-file rules

- Allowed prefixes (initial): `rtx-remix/mods/`, `garrysmod/lua/bin/`, `garrysmod/cfg/` (new files
  only). Anything else is refused.
- No absolute paths, drive letters, `..`, reparse points or Windows device names.
- Policies: `replace-owned` (the loader may replace files it deployed earlier and the user has not
  edited), `create-only` (never replace an existing file).
- Steam depot files are never written by root files.
- `user.conf` is never deployed or replaced.
