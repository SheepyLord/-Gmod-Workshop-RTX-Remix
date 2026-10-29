# remix_defaults.py

Merges Remix config files into the single defaults layer a runtime package ships
([ADR 0021](../docs/decisions/0021-remix-defaults-in-one-low-layer.md)).

```powershell
$c = 'H:\SteamLibrary\steamapps\common\GarrysMod_RTX_c'
python tools\remix_defaults.py "$c\dxvk.conf" "$c\rtx.conf" "$c\user.conf" --out out\layers\classic_remix_defaults.conf
python tools\package_runtime.py --runtime <runtime> --gma out\packages\runtime.gma --dxvk-conf out\layers\classic_remix_defaults.conf --env DXVK_FORCE_WINDOWED=1 --insecure
```

## Inputs

Config files (`key = value` lines; `#` comments), **weakest first**. With the classic install's
`dxvk.conf`, `rtx.conf` and `user.conf` in that order, the result has the same effective values
that install has at start-up.

## How values combine

- **An ordinary option:** the later file's value wins.
- **A texture-hash set** (a value made only of `0x...` and `-0x...` hashes, such as
  `rtx.decalTextures`): combined the way Remix combines layers. A later file adds its hashes and
  removes its `-0x...` ones. Net removals are kept as `-0x...` tokens, so they still remove from the
  runtime's built-in lists.
- **Legacy option names** are copied as they are; the runtime migrates them as it would from the
  original files.

## Output

`--out`: a header naming the sources, then one `key = value` line per option, in the order the keys
were first seen. Prints the count per source file.

## Exit codes

0 on success; 1 when an input file is missing.

Tests: [`tests/test_remix_defaults.py`](tests/test_remix_defaults.py.md).
