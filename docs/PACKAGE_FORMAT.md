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
    "launch_args": ["-dxlevel", "90", "-nod3d9ex"],
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
| `kinds` | yes | non-empty, no repeats; `remix-runtime`, `lua-binary-module`, `root-files`, and from loader 0.2.0 (M5) `lua-addon`, `patch-set`, `module-override` |
| `requires_loader` | no | `">=MAJOR.MINOR.PATCH"`: the minimum loader version |
| `requires_remix` | no (loader 0.2.0) | `true`: the package only makes sense with a Remix runtime; in a start without an active runtime its add-on folders (`garrysmod/addons/<name>/`) are left out of GMod's searches, in memory ([ADR 0013](decisions/0013-rtx-only-addons-hidden-without-rtx.md)). Default `false` |
| `files` | yes | every file under `native/` except the manifest, each `{ "size": N, "sha256": "<64 lowercase hex>" }` |
| `remix` | with `remix-runtime` only | see below |
| `root_files` | for `root-files` / `lua-binary-module` / `lua-addon` | see below |
| `patch_sets`, `module_overrides`, `session_cvars` | M5, optional | RTX-session extras, see below |

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
| `launch_args` | only `-dxlevel N`, `-nod3d9ex`, `+mat_disable_d3d9ex N` (N: 1-3 digits) in schema 1, so a package cannot add commands such as `+exec`. A `+` variable the game archives (such as `mat_disable_d3d9ex`) is saved into `config.cfg` and reaches later sessions, RTX off included ([RESEARCH.md](RESEARCH.md) section 11) |
| `prefer_system_vulkan_loader` | boolean: preload System32's `vulkan-1.dll` first |

M4 applies `remix.entry` from the journaled versioned payload, validates its and the package layer
files' recorded sizes, and requires cwd=game root and an absolute DLL path below MAX_PATH. The
`rtx_conf_layers` / `dxvk_conf_layers` precede the user's environment lists (or root conf defaults);
other `env` entries fill only absent variables. `launch_args` fill only missing arguments, preserving
user values. `prefer_system_vulkan_loader` loads System32 Vulkan before the runtime. Process changes
are reversible and preload is last; see [ADR 0008](decisions/0008-activation-at-startup.md).

### `root_files`

Each entry is `{ "path": "<relative to the game root>", "policy": "replace-owned" | "create-only" }`
(policy defaults to `replace-owned`). The files come from `native/root/<path>`, and `path` may name
a folder or a single file.

| Area | Kind needed | Policy |
|---|---|---|
| `rtx-remix/mods/<mod>/...` | `root-files` | either |
| `garrysmod/lua/bin/...` (binary Lua modules) | `lua-binary-module` | either |
| `garrysmod/data/<folder>/...` (seed data; not `native-loader`) | `root-files` | `create-only` (what the game writes there later stays the user's) |
| `garrysmod/addons/<addon>/...` (Lua add-on folders) | `lua-addon` | `replace-owned` ([ADR 0011](decisions/0011-lua-addon-folders.md)) |

Anything else is refused, including `bin/`, the game root itself (`rtx.conf`, `dxvk.conf`,
`user.conf`), `garrysmod/lua/autorun` and `garrysmod/cfg`. `garrysmod/cfg` holds Steam's own files,
and a package could recreate one that happened to be missing
([ADR 0014](decisions/0014-r1-hardening.md)).

In `rtx-remix/mods`, `garrysmod/data` and `garrysmod/addons`, every file must be inside a named
folder: `garrysmod/data/<folder>/<file>`, never `garrysmod/data/<file>`.

Root files may not overlap each other. Each must have files under `native/root/<path>`, every file
under `native/root/` must belong to one, and a declared `root-files` or `lua-binary-module` kind must
be used.

`replace-owned` lets the loader replace files it deployed earlier that the user has not edited;
`create-only` never replaces an existing file. Ownership is tracked in the journal
(`native-loader\state.json`, [ON_DISK_LAYOUT.md](ON_DISK_LAYOUT.md)):

- A file someone else placed at a `replace-owned` target blocks the package, unless it already has
  the right content (then it is adopted and never moved or deleted).
- At a `create-only` target, someone else's file is simply kept.
- A file the loader placed that has changed since stays as it is and is reported.

### RTX-session extras (loader 0.2.0, M5)

Applied only in sessions where a runtime activates, so RTX off stays vanilla
([ADR 0010](decisions/0010-rtx-session-extras.md)). An older loader refuses manifests that use them.

```json
"patch_sets": [{ "module": "engine.dll", "patches": [
  { "name": "mod_loadlighting_hdr", "find": "ff90????????85c0742b", "offset": 0, "replace": "b80200000090" } ] }],
"module_overrides": [{ "module": "stdshader_dx6.dll", "file": "native/payload/shaders/stdshader_dx6.dll" }],
"session_cvars": { "r_3dsky": "0", "mat_softwareskin": "1" }
```

| Field | Rule |
|---|---|
| `patch_sets` | kind `patch-set`; `module` a lowercase DLL base name (`[a-z0-9_]+.dll`), each once; per patch: `name` `[a-z0-9_]{1,64}` unique in the package, `find` 1-256 bytes as lowercase hex pairs or `??` (not all `??`), `offset` (default 0) and `replace` (lowercase hex) entirely inside the matched bytes; at most 256 patches. The bootstrap writes a patch when the DLL is mapped, only if its pattern occurs exactly once across the module's sections, and only in `-insecure` sessions unless `config.json` sets `patch_sets.require_insecure: false` |
| `module_overrides` | kind `module-override`; `module` a lowercase DLL base name the game loads from `bin/win64` by full path; `file` a payload path listed in `files`, with the same file name. A load of exactly `<root>\bin\win64\<module>` by a game module loads `file` instead |
| `session_cvars` | console variable assignments run through a generated `cfg/nativeloader_session.cfg`: names `[A-Za-z0-9_]{1,64}` starting with `r_`, `mat_`, `cl_`, `gmod_`, `rtx_` or `studio_` (or `sv_cheats`), values `[A-Za-z0-9_.+-]{0,32}`, at most 256. The user's archived values are recorded first and put back at the next start without RTX |

`remix.launch_args` also accepts `-insecure` from loader 0.2.0.

A package's own files are on disk in every session, RTX or not. Lua add-ons that only make sense with
Remix (the RTX fixes') belong in a package marked `"requires_remix": true`: without an active runtime
the bootstrap hides its add-on folders from GMod, so their Lua does not run
([ADR 0013](decisions/0013-rtx-only-addons-hidden-without-rtx.md)).

## Path rules

Every path in a manifest, and every package path that is deployed, must pass `nl::paths::problem`:
relative and `/`-separated; at most 1,024 bytes and 255 per component; valid UTF-8 with no control
characters; no `\`, `:`, `< > " | ? *`; no empty, `.` or `..` components; no component that starts
with a space or ends with `.` or a space; no Windows device names in any folder or with any extension
(`con`, `nul.txt`, `com0`-`com9`, `lpt0`-`lpt9`, superscript ports, `conin$`, `conout$`); no `~`
followed by a digit (8.3 short names). These close escapes from the target folder and aliases of
other files on Windows.

The paths the loader deploys or loads must also be **ASCII**: the `files` keys, `root_files`
paths, `remix.entry` and the conf layers. NTFS compares names without case for every letter, but
the loader only for ASCII letters, so a non-ASCII name spelled two ways would make the loader's own
file look like someone else's. Added on 2026-10-27, before any package used schema 1.
