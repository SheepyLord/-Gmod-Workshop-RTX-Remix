# package_workshop.py

Combines native packages into one package, so a single Workshop item can carry everything a
subscriber needs: the RTX Remix runtime and the RTX fixes, for example
([ADR 0016](../docs/decisions/0016-one-workshop-item-kept-current.md)).
[`publish_workshop.py`](publish_workshop.py.md) uses it; it also runs on its own.

```powershell
python tools\package_workshop.py --part out\packages\m5\runtime-b.gma --part out\fixes-pkg `
  --id gmod-rtx-remix --version 0.0.0-dev.1 --title "RTX Remix for Garry's Mod" --type effects --tag realism `
  --gma out\workshop\gmod-rtx-remix.gma
```

## Inputs

- `--part PATH`, at least twice. Each is a package folder (`native/manifest.json` beside the files,
  as `package_runtime.py --out` and `package_fixes.py --out` write it) or a `.gma` archive, which is
  read in place and never extracted whole.
- `--id`, `--version`, `--name`: the combined package's identity.
- `--title`, `--description`, `--type`, `--tag`: written to `addon.json`. `gmapack` puts them in the
  archive header, and `gmpublish` takes the type and tags from there. `--tag` is repeatable, at most
  two; `--type` defaults to `tool`.
- `--out FOLDER` and/or `--gma FILE`; `--force` replaces an earlier one.
- `--nlctl`: the `nlctl.exe` that validates the result (default: the built one in `out\build`, if
  any). `--no-validate` skips that check, for tests with partial manifests.

## How parts are merged

| Manifest key | Rule |
|---|---|
| `schema` | Every part must be schema 1 |
| `kinds` | United, in order |
| `requires_loader` | The highest `>=X.Y.Z` |
| `requires_remix` | True if any part has it |
| `files` | United. A path in two parts (compared without case) is refused |
| `remix` | At most one part may carry a runtime |
| `reshade` | At most one part may carry ReShade ([ADR 0028](../docs/decisions/0028-reshade-in-rtx-sessions.md)) |
| `root_files`, `module_overrides`, `patch_sets`, `module_dependencies` | Concatenated. The manifest parser then refuses overlaps and duplicates (a module two parts give dependencies for, for example) |
| `session_cvars` | United. The same variable with two values is refused |
| any other key | Refused: the tool does not know how to merge it |

Every file is copied from its part and checked against that part's manifest (size and SHA-256). A
mismatch stops the run before anything is written to `--out` or `--gma`.

## Outputs

- The package folder and/or the archive (packed by [`gmapack`](gmapack/gmapack.py.md)).
- A summary: id, version, file count and bytes, kinds, the parts, which `nlctl` validated it, and
  the archive's size and SHA-256.
  - The summary also has a **content digest**: the SHA-256 of the merged manifest without `version`
    and `name`, plus the Workshop metadata. Every file's SHA-256 is in that manifest, so two builds
    with the same digest deliver the same item.
- Scratch goes to `out\tmp` and is removed afterwards.

Exit 0 on success, 1 when the parts cannot be combined, a file does not match, `gmapack` fails or
`nlctl` refuses the result.

Tests: [`tests/test_package_workshop.py`](tests/test_package_workshop.py.md).
