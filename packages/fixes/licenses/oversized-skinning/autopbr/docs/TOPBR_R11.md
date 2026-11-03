# R11 ToPBR

## R12 feature matching and player overrides

`game_matching.inl` compares UV-coordinate spatial edge distributions from base images against
normal/packed families. Canonical `_D` stems remain authoritative. Renamed bases need raw spatial
correlation >= .28, supported score >= .36 and runner-up margin >= .12. Vocabulary support adds
at most .08 and cannot rescue a mismatched layout. Flat images, differing aspects, ambiguous
families and exhausted/incomplete scans abstain. Every attempted automatic pairing logs its base,
family, score, margin, spatial evidence and reason. Names-hidden measurement uses this same function.
No rotations, translations or UV warps are searched. Original PMX face/eye/skin masks remain in force.

Worker-local discovery caches at most eight folders. Each has <=4096 entries, depth <=6, <=64
family stems, <=96 feature decodes, <=256 MiB compressed inputs and <=256 million source pixels.
Descriptors are <=128 pixels on the long edge; source image dimensions remain <=4096 squared.
Descriptor reuse is per worker; clear/restart observes source edits. Source bytes, semantic map roles
and game layout participate in generator v6's DDS key.

`game_overrides.h` atomically saves `game_overrides.registry` beside the automatic registry. Choices
are keyed by live `mmd/t/<16 hex>` identities and take precedence over fresh/cached automatic maps.
Manual maps record source/base/map paths, explicit layout, generator, live-hash provenance and
published DDS filenames/byte counts/digests/constants. None is durable; automatic removes the choice.
Only current drawn hashes register. Missing/changed DDS suppress an override without falling back.
Unreadable/unknown choices remain intact and suppress automatic use until readable. A failed save
retains the current choice. Registry edits are preserved through the shared durable writer.
Changing a choice retracts/refreshes all observed aliases, including while game maps are switched off.
The ordinary authored-hash guard and runtime patch 0020 still rank every authored mod first.

The R12 panel section in `cl_rtx_topbr_conversion.lua` adds the Imported game PBR panel to the RTX menu and the console command
`rtx_topbr_game_editor`. It lists the looked-at character's materials, drawn-only thumbnails/states,
candidate families and individual source-folder files, with explicit layout/none/automatic actions.
It uses the bundle i18n function and supplies the new GPL phrases for all six bundled languages.
Native work is asynchronous. The standalone DForm and spawn-menu wrapper both use the common
`Clear` method; the polling hook preserves their base Think behavior. The engine resolves material identity only after drawn-hash evidence,
preventing unseen library materials from loading textures during Lua enumeration.

The SDK-free `game_matching_test.cpp` covers spatial abstention and override precedence, persistence,
source-less restoration, invalid DDS, durable failure and drawn-before-load ordering. The CLI
`game_match_probe.cpp` measures actual production discovery; see `tests/game_match_probe.md`.

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

## R11-B: source-less game-map records

Runtime patch 0020 now supplies authored-first fallback ranking outside this repository. R11-B keeps
using the fixes' conservative hash guard as well. The shared `FallbackGuard::Select` drives publication
for both freshly converted and restored game materials, including switch-off and uncertain scans.

`source/material_pipeline/to_pbr/game_registry.h` is a worker-only persistent table, written as
`game_materials.registry` beside the output texture directory. The client captures the actual
`$basetexture` name, requiring a content identity `mmd/t/<16 hex>` and current live Remix hashes.
Lua queues hotloader materials even without source/base metadata. A readable source with metadata
always runs today's content/recipe-keyed converter. An absent/unreadable source can only restore
a known identity whose four published DDS channels still have valid headers/full mip payload sizes,
the recorded byte counts and streaming FNV-1a content digests. These digests detect accidental edits;
they are not a cryptographic trust mechanism. Original albedo/alpha and protected texels remain untouched.
Saved hashes are diagnostic provenance, never a source of live registrations. Source rejection or an
empty safe conversion does not revive the previous output.

The record format/version (1, minimum 1) is independent of the generator (5): generator updates
must not expire source-less materials that cannot be regenerated. Raise the minimum record version
only for records with a known correctness defect. Limits: 4096 records, 64 hashes per record, 8 MiB
registry input, 4096 bytes per row, existing DDS dimension bounds. All file references are plain DDS
filenames under the known textures directory; reparse-point textures/directories are rejected.
Missing/truncated records are pruned on load; digest failures prune on restoration. Only another
well-formed decimal schema version or a file over 8 MiB stays read-only and intact. Other unreadable
files (including empty/torn headers, duplicate identities and excess rows) start empty and writable,
with one damage log line. The next save preserves the damaged bytes in the same content-named
`.before-r11b-<digest>.bak` path used for pre-existing or later edited registries. Staging uses
CreateFileW/WriteFile, FlushFileBuffers, CloseHandle, then write-through MoveFileExW; failures remove
the staging file. An unsavable registry warns once per module session, across worker restarts/jobs.

`rtx_topbr_clear` drops/requeues live registrations but retains the registry and DDS, including over
map changes and worker cancellation. A prior successful conversion with R11-B is required: cached
textures written before the registry existed are not guessed back into materials. AO is retained
as ordinary unused cache data, not a published material dependency.

Compile `tests/game_registry_test.cpp` with MSVC C++17 `/EHsc /UNDEBUG /W4 /WX /DNOMINMAX` and pass
a fresh scratch directory under `out`. It exercises atomic read/write and failed replacement,
preserved user edits, damaged-file recovery/backups, unchanged read-only versions/oversized input,
replacement failure/staging cleanup, current identity/hash checks, missing/invalid/edited DDS, bounded malformed input,
record/generator versions, source refresh/rejection, switch-off and authored-hash exclusion. No SDK,
game, network or user character is needed. The native loader repository's Release suite builds and
runs this test from its GPL corresponding-source copy, as well as the Lua source-less queue harness.

## R11-B second review

Each worker invocation owns a bounded `GameRegistry::Session`. The first enabled job for a live
texture identity resolves its present source or persistent record and saves the registry. Later
materials with that identity reuse the result with their own live hashes, without source probing,
conversion, DDS hashing or registry access. No-maps/rejected results also stay resolved. Clearing
ToPBR stops the worker, so clear/restart starts a new session; persistent records/DDS remain.

USD publication records the successfully published byte count and streaming FNV-1a digest in
`<target>.last-published`, using a flushed/closed staging file and write-through atomic replacement
after the USD replacement. Every publication reads that record afresh: an exact match needs no
backup across process restarts. Missing, damaged or stale records and edited/foreign USD require
the existing content-named backup first. No existing backup is removed. A failed USD publication
cannot advance the record; a failed record write falls back to preservation on the next publication.
These digests detect accidental changes, not adversarial modification.

`game_registry_test.cpp` covers repeated identities with new live hashes and unavailable disk
inputs, distinct identities, no-maps/rejection, disabled/invalid jobs and a new worker session.
`to_pbr_test.cpp` republishes in separate child processes to verify restart ownership, same-size
USD edits, missing/damaged/stale records and failed USD/sidecar replacement with staging cleanup.
