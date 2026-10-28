# gmapack.py

Dependency-free Python reader and writer for Garry's Mod `.gma` archives (GMAD format v1 to v3).
Vendored as-is from the user's GMA File Packer project; full documentation is in
[README.md](README.md) and the format in [GMA_FORMAT.md](GMA_FORMAT.md).

| Command | Does |
|---|---|
| `create --folder DIR --out FILE.gma` | Packs every file (stock `gmad.exe` only packs whitelisted types; `--strict` restores that) |
| `extract --file FILE.gma --out DIR` | Extracts with path-traversal, duplicate and CRC checks |
| `list` / `verify --file FILE.gma` | Lists entries / checks every CRC |

It also reads the LZMA-wrapped form that `gmpublish.exe` uploads produce.

In this repo it is the reference implementation the C++ GMA reader (M2) is tested against, and the
packer for building test packages and the Remix runtime package (M4). Stock `gmad`/`gmpublish`
refuse `.dll`/`.exe`, and producing an archive here does not mean the Workshop accepts it
([ADR 0002](../../docs/decisions/0002-source-agnostic-payloads.md)).

Tests: [`tests/test_gmapack.py`](tests/test_gmapack.py.md). Drag-and-drop wrapper: [`gmapack.bat`](gmapack.bat.md).
