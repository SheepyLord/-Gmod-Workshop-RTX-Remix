# game_dds_probe

R13-M evidence for compact imported game maps on real characters. Runs production
`GamePBR::Convert` (with the real octahedral encoder from `vtf.cpp`) for each PMX/base pair of a
UTF-8 descriptor (two lines per pair: absolute PMX path, then the base texture exactly as the
hotloader submits it, since its bytes are part of the content key) and writes the compact maps into
`<scratch>/compact`. Prints per map its size, format, bytes and the uncompressed size it replaces,
plus the maximum and RMS BC error against the uncompressed map and whether every block kept the
(max - min) / 14 bound; per family the disk bytes before (with the AO map) and after and the
conversion time; and a total.

With a third argument, a folder of earlier outputs (read only, for example a game's
`rtx-remix/mods/~gmod_topbr/textures`), it computes the v7, v6 and v5 keys by their shipped
formulas, reports which finished families exist, and checks that each one's stored base levels
equal today's conversion and that today's uncompressed writer reproduces its files byte for byte.

From an x64 MSVC shell inside an `out` scratch folder (the same include paths and sources as
`game_pbr_test.cpp`):

```powershell
cl /nologo /std:c++17 /EHsc /O2 /UNDEBUG /DNOMINMAX /utf-8 /I<repo>/tests/vtf_parser/stubs /I<repo>/public/include /I<deps>/garrysmod_common/include <repo>/tests/game_dds_probe.cpp <repo>/source/material_pipeline/to_pbr/vtf.cpp <repo>/source/vtf_parser.cpp /Fegame_dds_probe.exe
./game_dds_probe.exe descriptor.txt scratch [earlier-outputs]
```

Writes only into the scratch folder; sources and earlier outputs are read. Exit 0 when every block
kept its bound, 1 otherwise, 2 on a bad argument count. Per-base failures print `REJECT` lines.
