# remix_defaults.py

The shipped layer clears captured rtx.playerModelTextures and rtx.playerModelBodyTextures lists
([ADR 0043](../docs/decisions/0043-player-body-viewmodel-and-shadows.md)). Local first-person proxies
receive private categories instead; the primary-space body default is false. Shared arms/player/ragdoll textures stay ordinary world
materials. User config files are only read; the player's own layers still override the shipment.

Merges Remix config files into the single defaults layer a runtime package ships
([ADR 0021](../docs/decisions/0021-remix-defaults-in-one-low-layer.md)).

## Regenerating the shipped layer

The layer in the package is `packages\runtime\layers\classic_remix_defaults.conf`. It was first merged
from the classic install's `dxvk.conf`, `rtx.conf` and `user.conf`; that install no longer exists as
such (`GarrysMod_RTX_c` holds this project's implementation since 2026-10-30, AGENTS.md rule 1), so the
packaged layer is now the record of its values and is regenerated from itself. Then import it, as
every package input is changed ([inputs.py](inputs.py.md)), and compare the package:

```powershell
python tools\remix_defaults.py packages\runtime\layers\classic_remix_defaults.conf --out out\layers\classic_remix_defaults.conf
python tools\inputs.py import runtime --file "out\layers\classic_remix_defaults.conf=layers/classic_remix_defaults.conf"
python tools\inputs.py verify
python tools\build_package.py --compare out\workshop\published.json
```

The runtime part's packager reads the layer from `out\inputs\runtime\layers\`
([`tools/workshop.json`](workshop.json)), as one `--dxvk-conf` of
[`package_runtime.py`](package_runtime.py.md). A regeneration of the unchanged layer is byte for byte
the same (a test checks it), so a value typed into the layer by hand that the generator would set
otherwise fails the tests: change the generator instead.

## Inputs

Config files (`key = value` lines; `#` comments), **weakest first**. With a classic install's
`dxvk.conf`, `rtx.conf` and `user.conf` in that order, the result has the same effective values
that install has at start-up (apart from the pinned options below).

## How values combine

- **An ordinary option:** the later file's value wins.
- **A texture-hash set** (a value made only of `0x...` and `-0x...` hashes, such as
  `rtx.decalTextures`): combined the way Remix combines layers. A later file adds its hashes and
  removes its `-0x...` ones. Net removals are kept as `-0x...` tokens, so they still remove from the
  runtime's built-in lists.
- **Legacy option names** are copied as they are; the runtime migrates them as it would from the
  original files.
- **Pinned options** (`PINNED`) are set whatever the files say, in the place the files had them (or
  at the end):
  - options that depend on the GPU (`GPU_DEPENDENT`): `rtx.frameGenerationType = 0`,
    `rtx.dlfg.enable = False`, `rtx.dlfg.maxInterpolatedFrames = 1`. The classic install's DLSS-G at
    3x crashed RTX 30, RTX 40 and AMD GPUs
    ([ADR 0037](../docs/decisions/0037-frame-generation-off-by-default.md)); the header says so;
  - player categories (`PLAYER_CATEGORIES`): empty `rtx.playerModelTextures` and
    `rtx.playerModelBodyTextures`, `rtx.playerModel.enableInPrimarySpace = False` (ADR 0043);
  - path bounces (`PATH_BOUNCES`): `rtx.pathMinBounces = 1`, `rtx.pathMaxBounces = 12`
    ([ADR 0051](../docs/decisions/0051-path-bounce-defaults.md)).

## Output

`--out`: a header naming the sources, then one `key = value` line per option, in the order the keys
were first seen. Prints the count per source file.

## Exit codes

0 on success; 1 when an input file is missing.

Tests: [`tests/test_remix_defaults.py`](tests/test_remix_defaults.py.md).
