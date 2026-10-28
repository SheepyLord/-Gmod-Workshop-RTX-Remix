# third_party/lzma

The LZMA decoder from Igor Pavlov's LZMA SDK. `nl_core` uses it to read LZMA-wrapped `.gma`
archives: the Workshop's older `<hash>_legacy.bin` items, which `gmpublish.exe` uploads produce.
Decoder only; nothing here can compress.

| | |
|---|---|
| Source | <https://github.com/ip7z/7zip>, tag `26.05`, folder `C/` |
| Fetched | 2026-10-27 from `raw.githubusercontent.com/ip7z/7zip/26.05/C/<file>` |
| Licence | Public domain, stated in every file's header ("Igor Pavlov : Public domain"); see [LICENSE](LICENSE) |
| Changes | None. The files are byte-identical to the tag |

| File | SHA-256 |
|---|---|
| `LzmaDec.c` | `4E6EC665A6DF01F1722E2B2FC36DC5E3AA7C3890E0F8CB11C6A07C9A01F3309B` |
| `LzmaDec.h` | `3AAF07B4AE4173A2D103179455DC7089B5DDBC7FC3DB3C0E40964A7499C69266` |
| `7zTypes.h` | `A5D03B8CB65CD3A2A56BDE46DD68FB356D2EBACD9D70283E7D4D20B4E0A64713` |
| `Precomp.h` | `C8903F2E36A771A272D8981E1E9FFED5BA16CA3D2F3DCA6D1414D2340A6829D0` |
| `Compiler.h` | `D5E42BE77D26BEAA8C81D3E62EF99FC5685736CFC079779FDB9154D05FA8BC4A` |

These five files are the decoder's whole include closure (`LzmaDec.c` → `Precomp.h` →
`Compiler.h`; `LzmaDec.h` → `7zTypes.h`). No Windows headers are pulled in.

## Build

[`CMakeLists.txt`](CMakeLists.txt) compiles `LzmaDec.c` as C into the static library `nl_lzma`, at
`/W3` and without `/WX` (third-party code keeps its own warning level). `nl_core` links it privately;
the only caller is `loader/core/src/lzma.cpp`.

## Updating

Fetch the same five files at a newer tag into a new folder under `out\downloads\`, diff them against
these, confirm the headers still say public domain, copy them over, update the tag and hashes here,
and add a line to CHANGELOG.md. Run `tools\test.ps1`; the LZMA unit tests and the real-data scan
(`nlctl scan` over the Workshop folder) must still pass.
