# gmapack.py

Dependency-free Python reader and writer for Garry's Mod `.gma` archives (GMAD format v1 to v3).
Vendored as-is from the user's GMA File Packer project; full documentation is in
[README.md](README.md) and the format in [GMA_FORMAT.md](GMA_FORMAT.md).

**Provenance:** the user's own code, covered by this repository's MIT [LICENSE](../../LICENSE). The
user confirmed this on 2026-10-28 (R1-025), which is why it lives in `tools/` and not in
`third_party/`. The upstream revision it was copied from is not recorded.

| Command | Does |
|---|---|
| `create --folder DIR --out FILE.gma` | Packs every file (stock `gmad.exe` only packs whitelisted types; `--strict` restores that) |
| `extract --file FILE.gma --out DIR` | Extracts with path-traversal, duplicate and CRC checks |
| `list` / `verify --file FILE.gma` | Lists entries / checks every CRC |

It also reads the LZMA-wrapped form that `gmpublish.exe` uploads produce. It decodes that form into a
spool that stays in memory up to 8 MiB and then spills to a temporary file (`TEMP`, which
`tools\test.ps1` and `tools\build.ps1` point into `out\tmp`).

**Changed here** (review R19, F-08): the decoded size is capped at 8 GiB (`MAX_LZMA_OUTPUT_SIZE`). A
wrapper that declares more stops before decoding, and one that declares no size stops when its output
passes the cap, so a small crafted wrapper can no longer fill the drive. Before, only a declared size
bounded the output, and an undeclared one did not. The largest real archive these tools read, the RTX
package, is about 1.8 GB.

In this repo it is the reference implementation the C++ GMA reader (M2) is tested against, and the
packer for building test packages and the Remix runtime package (M4).

Stock `gmad` refuses `.dll`/`.exe`. A native package packed here can still go to the Workshop:
`gmpublish` uploaded one and Steam served it back byte for byte. GMod itself will not mount such an
archive, though, so its Lua must reach the game another way
([ADR 0015](../../docs/decisions/0015-workshop-route-for-native-packages.md)).

Tests: [`tests/test_gmapack.py`](tests/test_gmapack.py.md). Drag-and-drop wrapper: [`gmapack.bat`](gmapack.bat.md).
