# Package format (schema 1)

> Implemented in M2 by `loader/core/src/manifest.cpp` (`nl::manifest::parse`, `check_contents`) and
> tested in `loader/tests/test_manifest.cpp`. Change it only together with the code and tests, a
> note in [CHANGELOG.md](../CHANGELOG.md) and, for breaking changes, a new schema number.

A **package** is an ordinary `.gma` (GMAD v1-v3, plain or LZMA-wrapped like the Workshop's
`*_legacy.bin`) that contains `native/manifest.json`, or an unpacked **development folder** with the
same layout. GMod mounts the rest of an archive as usual; the loader reads the file directly.
Archives are built with [`tools/gmapack`](../tools/gmapack/gmapack.py.md); container details are in
[tools/gmapack/GMA_FORMAT.md](../tools/gmapack/GMA_FORMAT.md) and [RESEARCH.md](RESEARCH.md) §5.

`nlctl manifest <file.gma|folder>` validates a package and prints its manifest.

## Layout

```
native/manifest.json        what the package is and how to activate it (below), at most 1 MiB
native/payload/**           extracted to native-loader\packages\<id>\<version>_<generation>\  (runtime DLLs, configs)
native/root/<path>/**       deployed to <game root>\<path>, only in the allowed areas (below)
lua/**, materials/**, ...   normal GMod content, mounted by GMod; the loader ignores it
```

Paths compare without case, as Windows does; `gmad` lowercases them anyway.

## manifest.json

```json
{
  "schema": 1,
  "id": "rtx-remix-runtime",
  "name": "RTX Remix runtime for GMod x64",
  "version": "1.6.1+gmod.20261025",
  "kinds": ["remix-runtime", "root-files"],
  "requires_loader": ">=0.1.0",
  "files": {
    "native/payload/runtime/d3d9.dll": { "size": 338675200, "sha256": "4e6e…" },
    "native/payload/config/rtx.conf":  { "size": 161131,    "sha256": "a5d0…" },
    "native/root/rtx-remix/mods/base_mod/mod.usda": { "size": 2048, "sha256": "c890…" }
  },
  "remix": {
    "entry": "runtime/d3d9.dll",
    "rtx_conf_layers": ["config/rtx.conf"],
    "dxvk_conf_layers": [],
    "env": { "DXVK_LOG_LEVEL": "info" },
    "launch_args": ["-dxlevel", "90", "-nod3d9ex", "+mat_disable_d3d9ex", "1"],
    "prefer_system_vulkan_loader": true
  },
  "root_files": [
    { "path": "rtx-remix/mods/base_mod", "policy": "replace-owned" }
  ]
}
```

The manifest is strict JSON (RFC 8259, UTF-8, no comments, trailing commas or duplicate keys).
**Unknown keys are errors** at every level, so a typo cannot silently drop a setting.

| Field | Required | Rule |
|---|---|---|
| `schema` | yes | the integer `1` |
| `id` | yes | 1-64 characters of `a-z 0-9 -`, starting with a letter or digit; one active version per id |
| `name` | no | 1-128 bytes of UTF-8; defaults to `id` |
| `version` | yes | [Semantic Versioning 2.0.0](https://semver.org); compared by SemVer precedence, build metadata ignored |
| `kinds` | yes | non-empty, no repeats; `remix-runtime`, `lua-binary-module`, `root-files` |
| `requires_loader` | no | `">=MAJOR.MINOR.PATCH"`: the minimum loader version |
| `files` | yes | every file under `native/` except the manifest, each `{ "size": N, "sha256": "<64 lowercase hex>" }` |
| `remix` | with `remix-runtime` only | see below |
| `root_files` | for `root-files` / `lua-binary-module` | see below |

`files` keys must pass the path rules (below), lie under `native/payload/` or `native/root/`, and be
unique without case. When a package is loaded, `check_contents` requires every listed file to be in
it with the listed size, and every file under `native/` to be listed: nothing native can ride along
unlisted. When a package is deployed, every file it places is checked while it is extracted: its
size, its CRC-32 in the archive and its SHA-256 here. A package that fails is not deployed
([ADR 0007](decisions/0007-transactional-deployment.md)). The SHA-256 of `manifest.json` itself
identifies the package version in the journal.

### `remix` (kind `remix-runtime`)

| Field | Rule |
|---|---|
| `entry` | path under `native/payload/`, listed in `files`, file name `d3d9.dll` (it is preloaded under that name) |
| `rtx_conf_layers`, `dxvk_conf_layers` | paths under `native/payload/` ending in `.conf`, listed in `files`; become lower layers below the user's own configs |
| `env` | names `DXVK_*` or `RTX_*` (`A-Z 0-9 _`, at most 64 after the prefix); values at most 1,024 printable ASCII characters |
| `launch_args` | only `-dxlevel N`, `-nod3d9ex`, `+mat_disable_d3d9ex N` (N: 1-3 digits) in schema 1, so a package cannot add commands such as `+exec` |
| `prefer_system_vulkan_loader` | boolean: preload System32's `vulkan-1.dll` first |

### `root_files`

Each entry is `{ "path": "<relative to the game root>", "policy": "replace-owned" | "create-only" }`
(policy defaults to `replace-owned`). The files come from `native/root/<path>`, and `path` may name
a folder or a single file.

| Area | Kind needed | Policy |
|---|---|---|
| `rtx-remix/mods/<mod>/...` | `root-files` | either |
| `garrysmod/lua/bin/...` (binary Lua modules) | `lua-binary-module` | either |
| `garrysmod/cfg/...` | `root-files` | `create-only` (never replaces the user's configs) |

Anything else is refused, including `bin/`, the game root itself (`rtx.conf`, `dxvk.conf`,
`user.conf`) and `garrysmod/lua/autorun`. Root files may not overlap each other; each must have
files under `native/root/<path>`; every file under `native/root/` must belong to one; and a declared
`root-files` or `lua-binary-module` kind must be used.

`replace-owned` lets the loader replace files it deployed earlier that the user has not edited;
`create-only` never replaces an existing file. Ownership is tracked in the journal
(`native-loader\state.json`, [ON_DISK_LAYOUT.md](ON_DISK_LAYOUT.md)):

- A file someone else placed at a `replace-owned` target blocks the package, unless it already has
  the right content (then it is adopted and never moved or deleted).
- At a `create-only` target, someone else's file is simply kept.
- A file the loader placed that has changed since stays as it is and is reported.

### Planned kinds

`patch-set` (in-memory byte patches applied as engine DLLs load) and `module-override` (e.g.
`stdshader_dx6.dll`) are planned for M5. A schema-1 loader refuses manifests that use them.

## Path rules

Every path in a manifest, and every package path that is deployed, must pass `nl::paths::problem`:
relative and `/`-separated; at most 1,024 bytes and 255 per component; valid UTF-8 with no control
characters; no `\`, `:`, `< > " | ? *`; no empty, `.` or `..` components; no component that starts
with a space or ends with `.` or a space; no Windows device names in any folder or with any extension
(`con`, `nul.txt`, `com0`-`com9`, `lpt0`-`lpt9`, superscript ports, `conin$`, `conout$`); no `~`
followed by a digit (8.3 short names). These close escapes from the target folder and aliases of
other files on Windows.
