# R11 ToPBR

GPL-2.0. Phase 1 snapshots one live IMaterial per client frame and hands value-only jobs to the
worker. It caps images/queues, validates offsets before decoding, keys DDS on source content and
conversion recipe, atomically publishes complete USD snapshots and retracts output on disable.
The conservative fallback guard excludes authored hashes independent of directory order; binary
or uncertain inputs fail closed. Absolute concurrent runtime hot-reload precedence still needs a
runtime fallback-rank change; the fixes do not claim that guarantee.

Native regression: tests/to_pbr_test.cpp with production format_source.cpp, vtf.cpp, vtf_parser.cpp
and usda.cpp, tests/vtf_parser/stubs first on the include path, the normal module SDK/public include
paths, MSVC C++17 /EHsc /UNDEBUG /DWIN32_LEAN_AND_MEAN /DNOMINMAX. Pass a scratch folder under out.
Tests cover shader roughness/metal policy, exact/truncated/oversized/animated/resource VTF input,
Unicode-later competing mods, changed conflicts, binary USD suppression and complete USD removal.
Build uses the recorded ReleaseWithSymbols x64 projects; all intermediates stay under out.


The independent default-on `rtx_topbr_game_maps` uses existing local hotloader metadata. The Lua
sweep checks eight material slots per frame and retries unresolved live hashes. The native worker
reads bounded local PMX geometry, rasterizes named classes into shared UV sheets, and converts
WuWa RG normals, Endfield RG normals / _P (R metallic, A smoothness, B AO) and Silver Palace XYZ
normals / MRA. Endfield green is flipped; sampled UE families retain DirectX Y. Authored channels
remain raw, class constants follow the aggressive preset, and skin/face/eye texels stay neutral.
Original albedo and alpha are never rebound. AO is retained as data rather than baked into albedo.
The Source path excludes public and soft-copy hotloader materials even with world conversion on.

New DDS writes are capped at 1 GiB per module session, preserve 64 MiB of free space, and have a
complete mip chain. Converted character maps are capped at 2048; source decode bounds are 4096.
Content-keyed valid DDS plus a completed marker bypass image decoding and UV rasterization on later
sessions. Prefer companions beside the base; identical duplicate exports are safe to reuse, while
differing ambiguous alternatives fail closed. Generated USD edits are byte-compared and retained
in `.before-r11-<id>.bak` snapshots before replacement; malformed DDS candidates are quarantined.
The former darkness-based metallic switch is retained only for compatibility.

`tests/game_pbr_test.cpp`, with fixtures from `tests/make_game_pbr_fixtures.py`, exercises channel
values, green convention, Unicode PMX names, shared skin masks, malformed PMX, duplicate discovery,
image sanity and bounds. The same executable can read a UTF8 two-line-per-material corpus list,
printing per-map means without writing source models. Compile with the module public/common include
paths, vtf.cpp + vtf_parser.cpp, tests/vtf_parser/stubs, C++17 /EHsc /UNDEBUG /utf-8 /DNOMINMAX;
WIC/COM are Windows system libraries. Pass all scratch/evidence paths below out.


A measured 23.553 ms client snapshot exposed VMT reads and companion filesystem probes still on
the frame. The follow-up prepares owned VMT metadata on the worker (two slots), snapshots only
live engine values/hashes on the client (one per frame), then derives/maps on the worker (two
ready slots). A thread-local scoped value override lets the existing extractor reuse already-parsed
VMT values without file access. Explicit inspection retains its diagnostic read path. Construct
retest: maximum snapshot 0.830 ms, conversion p99 9.133 ms versus 23.472 ms before this split.
Unconditional authored-mod priority still needs the runtime change described above.
