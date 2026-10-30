# build_package.py

Builds the combined RTX package, what Workshop item 3829070317 carries, from this repository alone
([ADR 0033](../docs/decisions/0033-one-repository-package-inputs-in-git-lfs.md)). Uploads nothing;
[`publish_workshop.py`](publish_workshop.py.md) does that, with the same build.

```powershell
git lfs pull
python tools\build_package.py                                        # into out\dist
python tools\build_package.py --compare out\workshop\published.json  # and say whether the content changed
python tools\build_package.py --require-nlctl --json                 # what CI runs
```

| Option | Meaning |
|---|---|
| `--config` | The package and its parts (default [`workshop.json`](workshop.json)) |
| `--out` | Where the `.gma` and its summary go (default `out\dist`) |
| `--version` | The package version (default `0.0.0-dev.<UTC time>+<input fingerprint, 8 digits>`, as a publish) |
| `--require-nlctl` | Fail unless a built `out\build\win64-release` or `-debug` `nlctl.exe` checks the parts and the result. Without it, a checkout with no loader build skips that check and says so |
| `--compare RECORD` | A publish record (`out\workshop\published.json` or `build.json`): report whether this build has the same content digest. Exit 3 if not |
| `--keep-work` | Keep the built part folders in `out\tmp\package-work` |
| `--json` | Print the summary as JSON (progress goes to stderr) |

## What it does

`publish_workshop.build()`: unpacks the parts the config reads (`out/inputs/<part>/...` paths) from
`packages\` ([`inputs.py`](inputs.py.md) `unpack`, checked against the indexes), runs each part's
packager into `out\tmp\package-work\<part>`, and combines everything with
[`package_workshop.py`](package_workshop.py.md) into `<out>\gmod-rtx-remix-<version>.gma`. The
summary (`id`, `version`, `digest`, `files`, `gma`, `gma_bytes`, `gma_sha256`, `nlctl`, and
`compared_with`) goes beside it as `<name>.json`. The content digest leaves out versions, so two
builds of the same inputs have the same digest.

**Exit:** 0; 1 on an error (`build_package: ...`); 3 when `--compare` finds other content.
**Writes:** `out\inputs\`, `out\tmp\package-work\` (removed afterwards), the `.gma`, its inventory and
summary in `--out`.

First run, 2026-10-30, from the parts imported that day: 877 files, 1,798,746,608 bytes, digest
`942d0083...`, the same content as the item's upload from `bbab69e`.
