# game_match_probe

Measures production `GamePBR::Discover` with normal name support and with pair names hidden.
Takes a UTF-8 descriptor and an output TSV path. Each pair of descriptor lines is an absolute
PMX filename followed by a base texture path relative to that PMX. No user source is written.
The report includes source/base, accepted family, score/margin/spatial feature, reason and selected
normal/packed paths, the winning evidence image and skipped-family/auxiliary warnings.
Discovery/decode limits are identical to conversion; the folder cache is local.
An optional third argument `--blur` measures a single 3x3 edge blur; ordinary conversion
keeps the original unblurred edges. Corpus review found additional wrong matches with blur.
Names-hidden runs never
use auxiliary evidence, including when a mask shares the base's vocabulary group.

From an x64 MSVC shell inside repository `out` scratch:

```powershell
cl /nologo /std:c++17 /EHsc /DNOMINMAX /utf-8 <repo>/tests/game_match_probe.cpp /Fegame_match_probe.exe
./game_match_probe.exe corpus.txt pairings.tsv
```

Windows WIC/COM libraries are linked by the production header. No game/SDK is needed:
`game_pbr_types.h` supplies unused converter transport types. Decoding, discovery, scoring and
acceptance are production code. Exit 0 on completion, 2 on bad argument count, 3 if an input/output
cannot open. Per-base failures become abstention rows.
