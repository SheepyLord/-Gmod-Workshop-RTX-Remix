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

`tools\test.ps1 -Config Release` on `r8-int` before each merge (part 1; parts 2 and 3 on the final
tree): 26 of 26 CTests, 504 Python tests (two skipped, as before), "All checks passed". The runtime
fork's unit tests: 29 of 29, with the new MMD alpha history cases (`test_remix_categories` needs the
runtime's DLLs staged next to the built `d3d9.dll`). The guard's 47 tests include the `r_forcehwlight`
pin (refused for every Lua caller), the remaster `r_novis` exemption through `pcall` and the merged trusted
paths; the glass interaction tests size interest messages as the game does.

Published three times from `main`: part 1 `e8602be` as `0.0.0-dev.20261101203841+06aebd23` (the noise
fix), part 2 `7156baf` as `0.0.0-dev.20261101215410+29d7ea98`, part 3 `a663f85` as
`0.0.0-dev.20261101220757+bd6ea7cd`. The field loader stays `0.12.0+74536d3c` (no loader change in R8).
The Backrooms add-on's field copy no longer sets `r_forcehwlight` (the old file in
`out/field-backup/2026-11-01-r8`). Field sessions (`out/qa-field/r8`):

- `gm_br_complex` with part 2 (`03-backrooms`): 1682 lights created, the PAS switch on, `r_forcehwlight` 0,
  but 9 FPS: the guard kept the session's `r_novis 1` against the remaster (150 refused retries), which part
  3 fixes. The map takes minutes to load with the user's 765 add-ons; `poc_session.py`'s 120 s hang grace
  and 300 s map wait cut two attempts short (`02-backrooms`, `07-backrooms`), and a one-off runner
  (`out/qa-field/r8/long_load_session.py`, 900 s) plus `--timeout 900` got through.
- `gm_br_complex` with part 3 (`08-backrooms`): `r_novis 1 -> 0` applied once, "the PVS of 2273 clusters is
  their PAS", 1682 lights with 172 on around the camera, **25.1 FPS (median 39 ms, p99 73 ms) instead of 9**;
  Kleiner and Alyx player-model ragdolls and a citizen render right; quit normally.
- During those loads the window shows "Not Responding" while the menu and Remix still draw: GMod's main
  thread does not pump window messages while it remounts the add-ons and loads the map. The user's 21:02
  session ended with `0xCFFFFFFF` (Windows closed it as not responding), probably during such a load.

A field game launched by another project's tool (`ipg\zzz_34\tools\kafka_runtime.py`) was running at
22:07 UTC; it was left alone and the check waited (the user then closed all games).

## After the report: "Not Responding" during long loads (loader 0.12.1)

The user confirmed the game still drew and its menu updated while Windows called the window
unresponsive, and asked for it to stop. `8a24a9c` makes the loader turn off Windows' window ghosting
for the game process at start-up. The game window still hangs during a load, but Windows no longer
hides it behind a greyed "(Not Responding)" copy that offers to close the game.
`NATIVE_LOADER_WINDOW_GHOSTING=1` keeps the old behaviour. The bootstrap still imports only KERNEL32.
`poc_session.py` takes `--hang-grace` in place of the one-off runner. Release suite: 26 of 26 CTests
(KERNEL32-only imports included), 506 Python tests (skips as before), "All checks passed". Workshop item unchanged (`unchanged-inputs`).
Loader `0.12.1+8a24a9ca` is in the field; `0.12.0`'s DLL, PDB, receipt and config are in
`out/field-backup/2026-11-01-r8-ghosting`.

A watcher (`out/r8-ghosting/ghost_watch.py`) polled the game window with `IsHungAppWindow` and listed
top-level `Ghost` windows. While the window was hung, it invalidated it every 5 s; this sends no
message.

| Run | Loader | Hang episodes (longest) | Ghost windows |
|---|---|---|---|
| PoC `a-kept`: gm_construct, 25 s Lua stall, `NATIVE_LOADER_WINDOW_GHOSTING=1` | 0.12.1 | 2 (20.1 s) | 2 |
| PoC `b-fixed`: the same stall | 0.12.1 | 1 (20.1 s) | **0** |
| Field `02-br-complex-kept`: gm_br_complex, 765 add-ons, `=1` | 0.12.1 | 5 (8.0 s) | 5 |
| Field `01-br-complex`: the same load | 0.12.1 | 6 (12.1 s) | **0** |

Every field run mounted the Workshop and loaded the map (29.8-37.7 s this time; minutes earlier the same
day, with colder caches) and quit normally. Evidence: `out/r8-ghosting/poc` and `out/qa-field/r8-ghost`.

## Open issues

- The tester's GShader crash is not reproduced; untested GShader effects stay inert by the generic rule.
- Distant falling fragments move as rigid groups and only split on later hits.
- The intermittent Remix start-up crash (seen once on the PoC in R8) is not investigated (deferred).
