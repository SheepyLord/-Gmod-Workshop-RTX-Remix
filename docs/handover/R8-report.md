# R8: the user's report after R7 (report)

The user's requests (plan: [R8-plan.md](R8-plan.md)): (1, severe) frame-to-frame noise on characters since
the alpha fix, worst with DLSS; (2, high) vanilla graphics add-ons, GShader Library above all, still crash or
destabilize a tester's game; (3-5, low) the falling-glass frame cost, glass collision levels with living
entities off by default, bullets and crowbars that do not break fractured glass. Later the same day: deploy
the Backrooms work's fixes from the modern_house session; and (severe) vanilla characters' bones and meshes
broken again. Claude diagnosed (1) and the bones, wrote three Codex briefs ([R8-C](R8-C-addon-compat.md),
[R8-G](R8-G-glass.md), [R8-B](R8-B-backrooms-fixes.md)), reviewed and integrated on `r8-int`, and ran the
game QA on the PoC (`out/qa-poc/r8`).

## Character noise (runtime patch 0018)

Patch 0017 marked a tagged Model Hotloader instance's material as changed whenever its MMD alpha state
differed from the stored state, which a later draw of the same frame or a new instance had replaced; the
geometry resolver then discards DLSS-RR history (and uses the alternate threshold without RR) on every pixel
of the character, every frame. Remix's debug view 128 on Robin: history discarded on 37.1 % of the frame
centre with R7, 0 % with the G1 runtime, with the companion stopped, or with tracking but no tags, 31.4 % with
only her 15 texture hashes tagged, and **0 % with patch 0018**, which compares the first draws of consecutive
frames and never flags a new instance. The grain inside her surfaces is gone (`noise-compare.png`). Fork unit
tests 29/29. This part shipped first: `main` `e8602be`, Workshop `0.0.0-dev.20261101203841+06aebd23`.

## Vanilla characters in bind pose (again)

The Backrooms add-on `gm_br_rtx`, installed in the field by the modern_house session at 21:01 UTC, forces
`r_forcehwlight 1` on `gm_br_complex`/`gm_br_pitfalls`: R3-016's cause (GPU-skinned meshes reach Remix
without bones when `mat_softwareskin` is 0). The user's next session started at 21:02 and was closed as not
responding at 21:20. The add-on no longer sets it (fixes clone, `claude/rtx-remix-map-enhancement-bda9ac`,
`98d7682`; the field copy replaced, the old one in `out/field-backup/2026-11-01-r8`), and the guard pins
`r_forcehwlight` at 0 against every Lua caller. PoC (`17-vanilla`): a citizen and the Kleiner and Alyx
player-model ragdolls render right, and both add-on-style attempts were refused ("kept session value 0");
on the published package the same attempt sets 1 (`18-vanilla-control`). A run meant to also reset
`mat_softwareskin` through `sv_cheats 0` crashed at start-up on the published package (the intermittent
Remix start-up crash; driver crashes are deferred by the user).

## Vanilla graphics add-ons (R8-C)

The guard now returns safe fallbacks instead of raising, keeps GShader-style screen-space effects inert under
RTX ([ADR 0086](../decisions/0086-inert-shader-effects-and-safe-guard-fallbacks.md)), keeps material loads
native and exempts the package's own Lua by exact paths (Claude's review: the first version made our fixes'
ExoPBR/GPBR conversion and Model Hotloader's shaders inert). PoC with GShader Library, FXAA, SSDO, SSR,
NikNaks, Quick Bloom, Real CSM and Life Mod: gm_construct and gm_flatgrass load and quit normally with no Lua
errors and 22 bounded guard notes; the 26 "Failed to create shader" lines appear without any add-on too.
Robin renders with all eight. The tester's crash remains unreproduced on this machine. Details:
[R8-C-report.md](R8-C-report.md).

## Glass (R8-G)

| 50-pane scene | R7 off | R8 off | R7 on | R8 on |
|---|---|---|---|---|
| While falling, mean / p99 | 26.28 / 134.30 ms | 10.94 / 35.20 ms | 28.60 / 134.33 ms | 11.85 / 36.30 ms |
| Settled, mean | 9.17 ms | 8.34 ms | 9.32 ms | 8.86 ms |

Creation is spread over frames and crowded distant fragments fall as grouped bodies (about 300 rigid bodies
for the 2,000-fragment budget); near-field detail looks the same (`falling-compare.png`). Collision levels:
the default (objects and ragdolls) leaves a pile alone when a player walks through it (9 → 9 fragments);
with players enabled it splits (9 → 21). Follow-up hits, found in game and fixed at integration: clients'
interest updates were always refused (the server required 128 bits per region; `net.WriteVector` sends 3-66),
so bullets reached pieces only for 2 s after a break; and 12,000 energy per damage point split only small
pieces. Now (`22-glass-r8`, a pile settled for 61 s): a pistol round splits it (1 → 2), an SMG burst 4 more
times (→ 6), a crowbar a fresh slab into 12. Details: [R8-G-report.md](R8-G-report.md),
[ADR 0085](../decisions/0085-glass-load-collision-and-hits.md).

## The Backrooms fixes (R8-B)

The modern_house session's three RTXFixesBinary changes (missing SW VTX cache, lazy model transforms,
default-off PAS visibility for the room next door) are ported onto the packaged fixes source without
conflicts, rebuilt with the recorded pins (`18e1ebc7...`) and imported. The package's Lua already offers what
`gm_br_rtx` calls. Vanilla characters render right with the new DLL (above). Details:
[R8-B-report.md](R8-B-report.md).

## Tests and field

TESTS

FIELD

## Open issues

- The tester's GShader crash is not reproduced; untested GShader effects stay inert by the generic rule.
- Distant falling fragments move as rigid groups and only split on later hits.
- The intermittent Remix start-up crash (seen once on the PoC in R8) is not investigated (deferred).
