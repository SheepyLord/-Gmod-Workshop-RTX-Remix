# package_runtime.py

Builds an RTX Remix runtime package ([docs/PACKAGE_FORMAT.md](../docs/PACKAGE_FORMAT.md)) from a
build of the user's `dxvk-remix-gmod` fork. The output is a package folder (allowlist it under
`dev_folders` in `native-loader\config.json`), a `.gma` (allowlist it under `local`), or both. Every
file is hashed while it is copied, so the manifest's sizes and SHA-256s describe exactly the bytes
in the package.

```powershell
# The fork's complete runtime, as a package folder and an archive:
python tools\package_runtime.py --runtime H:\BACKUP_20260815\Modding\dxvk-remix-gmod\_output `
  --out out\packages\rtx-remix-runtime --gma out\packages\rtx-remix-runtime.gma

# The same runtime with a newer d3d9.dll and a base rtx.conf layer:
python tools\package_runtime.py --runtime ...\_output --d3d9-from ...\built-A8E39D93-lockfree-options `
  --rtx-conf my-defaults.conf --gma out\packages\runtime-b.gma --force
```

## What goes in

| Package path | From |
|---|---|
| `native/payload/runtime/**` | every file under `--runtime`, keeping its folders (`usd\` must stay beside `d3d9.dll`); `.exp .lib .ilk .bak` never, `.pdb` only with `--with-pdbs` |
| `native/payload/runtime/d3d9.dll` | `--runtime`, or `--d3d9-from` (which also supplies `d3d9.pdb` with `--with-pdbs`) |
| `native/payload/config/rtx/NN_<name>.conf` | each `--rtx-conf`, in the order given (lowest layer first) |
| `native/payload/config/dxvk/NN_<name>.conf` | each `--dxvk-conf`, likewise |
| `native/manifest.json` | written last: schema 1, kind `remix-runtime`, `requires_loader` `>=0.1.0` |

The manifest's `remix` section names `runtime/d3d9.dll` as the entry, lists the config layers, the
`--env` variables, the launch arguments `-dxlevel 90 -nod3d9ex` (unless `--no-launch-args`; RTXLauncher's
`+mat_disable_d3d9ex 1` is left out because the game archives it into `config.cfg`, where it would
reach later RTX-off sessions: [RESEARCH.md](../docs/RESEARCH.md) section 11) and `prefer_system_vulkan_loader: true` (unless
`--no-system-vulkan`). How the loader applies them: [docs/ARCHITECTURE.md](../docs/ARCHITECTURE.md).

The VC++ 2015-2022 runtime that `d3d9.dll` imports is not packaged; it comes from System32.

## Options

- `--runtime <folder>` (required): the fork's complete runtime folder, normally `_output`.
- `--out <folder>`, `--gma <file>`: what to write; at least one.
- `--d3d9-from <folder>`: take `d3d9.dll` from another build folder (the fork's `built-*` folders and
  `_CompRelease_x64\src\d3d9` hold only `d3d9.dll` and its PDB).
- `--with-pdbs`: include `.pdb` files.
- `--rtx-conf <file>`, `--dxvk-conf <file>` (repeatable): config layers, each a `.conf` file.
- `--env NAME=VALUE` (repeatable): `DXVK_*` or `RTX_*` variables for the runtime, values at most
  1,024 printable ASCII characters. `DXVK_CONFIG_FILE` and `DXVK_RTX_CONFIG_FILE` are refused: the
  layers set them.
- `--id <id>` (default `rtx-remix-runtime`), `--name <text>`, `--version <semver>`. The default
  version is `0.0.0-dev.<UTC build time of d3d9.dll, yyyymmddhhmm>+<first 8 digits of its SHA-256>`,
  so two builds never share a version, and the same build always gets the same one.
- `--no-launch-args`, `--no-system-vulkan`: leave those out of the manifest.
- `--insecure`: add `-insecure` to the launch arguments. In-memory patch sets (M5, the fixes package)
  apply only in insecure sessions unless `config.json` says otherwise, as the classic RTX launch line
  does; secure (VAC) servers then cannot be joined in RTX sessions.
- `--force`: replace an earlier package folder (only one that holds `native/manifest.json`) or archive.
- `--json`: print the summary as JSON (`id`, `version`, `files`, `bytes`, `manifest_sha256`, `d3d9`,
  `d3d9_sha256`, `pdbs`, `folder`, `gma`).

## Outputs and side effects

- The package is built in `<output>.partial-<pid>` beside the output and renamed into place, so a
  loader never reads half a package; an existing folder is swapped out and then deleted. On failure
  the partial folder is removed. The `.gma` is written by [`gmapack`](gmapack/gmapack.py.md) through
  a temporary file, with paths in their original case and d3d9.dll's time as the archive timestamp:
  the same inputs give the same bytes.
- Refuses: deployed paths the loader's path rules reject (non-ASCII, reserved names, ...), links or
  special files in the runtime, two paths that differ only in case, an output inside the runtime
  folder (or the reverse), a non-empty output folder without `--force`.
- Reads the runtime and layer files; writes only the outputs. Never touches a game install.
- Check the result with `nlctl manifest <folder or .gma>`.

## Exit codes

0 success; 1 refused or failed (the reason on stderr); 2 bad command line (argparse).

Tests: [tests/test_package_runtime.py](tests/test_package_runtime.py.md).
