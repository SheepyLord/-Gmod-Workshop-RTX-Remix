# Testing a map remaster

The user decides changes to a standard from measured evidence. Pick the level that fits:

| Situation | Tool | Evidence |
| --- | --- | --- |
| A build or a fix, quick look | `tour.py <map> <label>` | the contact sheet of every region |
| What the remaster changes | `stock.py on/off`, `tour.py`, `compare.py` | stacked stock / remaster pairs and the gallery |
| A material, light or grade choice | an A/B from fixed cameras with repeats (below) | difference against the repeat noise and the drift |
| Frame time | `perf.py`, `abtest.py`; on the PoC `poc_session.py --fps` | median and 99th percentile per camera, stock in the same session, the run-to-run noise |
| What reaches the ray tracer | `cullcheck.py` / `vischeck.py` | entity counts per room, locked-PVS views from above |
| Loading | a launch with the timeline (`restart.py`), `loadprof.py` | seconds from `map` to the addon's `created` line, the longest silences |

## Before a session

- **Which game.** A test session you start on the PoC (or the install the user named), launched with
  `-multirun`. Never a game you did not start, unless the user hands it to you for this task. Set
  `MHRTX_GAME` (or `BRRTX_GAME`, `POOLRTX_GAME`) to that install's root: `game.py` sends console text only to
  a `gmod.exe` of that install.
- **Workshop maps.** With Workshop add-ons mounted, never put `+map` on the command line or send `map` while
  "Fetching Subscriptions" and the mounting run (the user has seen agents hang the game this way nine
  times). Either start at the menu and wait for the second "Mounted N of M workshop addons!" line and a quiet
  log, or start with `-noworkshop` and mount just the map: `poc_session.py run --mount-workshop <id>
  --change-map <map>` (from client Lua, `steamworks.DownloadUGC` then `game.MountGMA`).
- **The addon is up.** Wait for its log line (`[MHRTX] applied 9 Remix settings; sky: physical atmosphere`
  and `created: 341 lights in the house, 341 on, the atmosphere's sun, 8 mirrors` on modern_house;
  `[BRRTX] created ...`; `[PoolRTX] created ...`) and no Lua errors, read from your session's part of
  `console.log` only.
- **Tools in the game.** `rtx_agent` (camera holds, frame timing) and `niknaks` (vis clusters) come with the
  RTX package's fixes part. `lua_run_cl` needs single player.
- **Other sessions.** Tell sessions that use the same game before a capture (camera hooks, Remix toggles,
  `mat_reloadtexture` and debug views spoiled three captures on 2026-10-26), and again when it is free.
  Check `console.log` (your part) for foreign `Remix config ... set` or `mat_reload` lines afterwards.
- **After a crash** the next start waits on the Remix crash-report prompt (it looks like a hang after
  "Parsed config file"): let that launch time out. Never set `RTX_AUTOMATION_DISABLE_BLOCKING_DIALOG_BOXES`;
  it also gives upload consent.

## Cameras

`tools/cameras_<map>.json` (gm_poolrooms: `cameras.json`) maps a camera name to:

```json
{"living": {"region": "Living room, towards the glass wall", "pos": [x, y, z], "ang": [pitch, yaw, 0],
            "fov": 90, "settle": 4.0}}
```

`fov` and `settle` are optional. One camera per region, inside the lit part of the room, looking along its
longest open line. Ways to get them:

- `survey.py <label> [count]` (Modern House): candidate spots at eye height on the map's `info_node` and
  player-start positions, a farthest-point spread, each looking down its longest sightline; shoots them and
  writes `work/survey_cameras.json` as a starting point.
- `find_cameras.py <map> [radius]` (Backrooms): from "anchor" positions (teleport destinations, player
  starts), candidates under the remaster's lights near each anchor, scored by the light reaching them over
  distance squared and by view depth; writes the best per region and keeps the anchor. Teleport
  destinations alone sat in dark corners or in other vis clusters.
- By hand from `getpos` in the console.

`util.PointContents` (1 everywhere) and `render.GetLightColor` (0) were useless for placing cameras on
Backrooms. Drop a camera that sits outside the map or faces a wall (gm_poolrooms kept 27 of 28).

Modern House used 25 cameras (grounds, terrace, driveway, every room), Backrooms 12 on gm_br_complex and 32
on gm_br_pitfalls, gm_poolrooms 27.

## Tours

`python tour.py <map> <label> [camera ...]` (gm_poolrooms: `tour.py <label>`): hides the HUD (`cl_drawhud 0`),
switches to the physics gun (the toolgun's info panel ignores `cl_drawhud`), holds each camera with
`RTXAgent.View` (HUD and view model hidden), points the remaster's light manager at the held camera
(`viewPos`), waits `settle` seconds (4 s by default, 2.5-7 s in the sessions; a camera cut needs about 4 s
for the denoiser), takes the engine's
`jpeg` screenshot (the presented, path-traced frame at the game's resolution) and moves it to
`work/shots/<map>/<label>/<camera>.jpg`, then writes `_sheet.jpg` (three thumbnails a row, labelled) and
puts the HUD and view back. `times_tour.py` (Modern House) shoots a few cameras at golden hour, dusk and
night and returns the sun to the afternoon. Keep labels simple: a label with slashes broke the path.

Go through every region on the sheet. The three remasters were judged region by region this way, and
what was wrong was fixed and shot again (`v1` to `v19` on gm_poolrooms, `wip2` to `wip5` on Backrooms).

## Stock against remaster

- `python stock.py on` turns the running map into stock GMod RTX: the addon's lights and Remix options off,
  its scoped engine settings back to the user's (the whole map drawn, the game's lights handed to Remix the
  user's way) and `rtx.enableReplacementMaterials False`. `stock.py off` brings the remaster back (the
  replacement materials on, the engine settings applied, the addon reloaded).
- gm_poolrooms took its `before` tour from stock Remix before anything was installed.
- `python compare.py <after> [before]` reads `gallery.json` (`"gallery"`: cameras for the gallery, entries
  like `time_dusk/ext_lawn` taking a shot from another label; `"compare"`: cameras for pairs) and writes
  `docs/<map>_rtx/gallery/<camera>.jpg`, the contact sheet `docs/<map>_rtx/gallery.jpg` and
  `docs/<map>_rtx/compare/<camera>.jpg`, stock above and remaster below, labelled, 1600 px wide, after clearing
  the old images.

## A/B of a material, light or grade choice

None of the three map sessions ran a measured A/B on materials: recipes, kelvins and grades were tuned from
tour sheets, and the user confirmed the result by eye. For a change you want to call a standard, measure it
the way the user's character work does (`mmd-remix-pbr/references/testing-protocol.md`), adapted to a map:

1. Build each variant as a complete mod (`build_mod.py --no-prune`, a copy of `materials.usda` per variant),
   or as one Remix option or Lua switch.
2. From each fixed camera, shoot A twice back to back, then B twice, then A again (A2). Swap with one
   `mod.usda` reload per variant, not per view, and wait after each swap: auto-exposure re-adapts for
   several seconds (with 8 s of settle the first shot of a variant came out 8/255 darker than its repeat;
   20 s after a swap and 6 s after a camera cut kept the repeat noise at 1-2/255).
3. Quote the change |B - A| with the repeat noise |A - A'| and the drift |A2 - A| next to it, on the region
   that matters (a mask or a crop for measuring; the frames themselves stay whole).
4. Present the pairs and the numbers, recommend the conservative option when nothing beats the original by
   more than the noise, and let the user choose.

## Noise floors

- **The user's block difference** (`tools/compare_frames.py` in this repository, a reimplementation of the
  user's own measure): the mean absolute difference of 32x32 block means over the RGB channels, 0-255.
  The user's reading: about 1 between repeated captures of one install, 1.5-3.6 "close", 16-26 "broken".
  `--mask x0,y0,x1,y1` leaves out regions expected to differ; it also prints mean RGB and luminance
  percentiles (exposure and black frames show there first).
- **`cullcheck.py`'s measure:** each shot reduced to 480 px wide; the largest mean difference over 15x15
  blocks (a local change, such as a room missing from a reflection), next to the same number for a repeat.
- **Moving clouds and path-tracing noise:** Modern House's frame times vary by about 2 ms run to run, and its
  shots change with the clouds; repeat every capture that you compare.
- **Lighting drifts over minutes:** compare only shots from one run, and bracket (A..B..A2) when the effect is
  small.

## Frame times

`python perf.py <map> [label] [camera ...]`: holds each camera, lets it settle (4 s), runs
`rtx_agent_frames 4 <name>` (engine frames: median, 99th percentile, hitches) and reads the result from
`garrysmod/data/rtx_agent/<name>.json`, counts the remaster's lights on, prints a table and the median of
medians and the worst, and writes `work/perf_<map>_<label>.json`.

- Measure stock and remaster in the same session (`stock.py on`, `perf.py <map> stock`, `stock.py off`).
- **Engine frames, not the overlay.** The user plays with DLSS frame generation 4x (`user.conf`
  `rtx.dlfg.maxInterpolatedFrames 3`); an FPS overlay shows four times the engine rate. Measure with frame
  generation off, or count engine frames as `rtx_agent` does.
- **A quiet machine.** No other game, no build, no AI batch, no NVTT encode: a concurrent encode put stock
  modern_house at 90+ ms against 37.2 ms idle, and the first load at 389 s against 150 s. Check before and
  during each run, alternate the cases, ask other sessions to hold heavy work.
- **Not right after a reload or a load.** Texture streaming after a mod reload read 18 fps against a steady
  12.7 ms (Backrooms). The first variant after a restart is unreliable.
- **A normal session.** `sv_cheats 0` puts every cheat variable that gmRTX's `autoexec.cfg` set back to its
  default (`r_novis`, `mat_softwareskin`, ...); numbers from such a session are not GMod RTX's (Backrooms'
  first stock figure, 128 ms, was one).
- **Slow frames:** GMod clamps `FrameTime()` at 100 ms, so very slow cases are timed by wall clock
  (`SysTime()` in a `PostRender` hook), as Backrooms' `wall_fps` and `poc_session.py --fps` do.
- On the PoC: `poc_session.py run ... --fps 30 --console "engine_no_focus_sleep 0" --console "fps_max 0"`
  (a window without focus sleeps between frames).

`python abtest.py <camera> [variant ...]` (Modern House): holds one camera and measures 4 s of frames per
variant, each switching one thing and putting it back: `base`, `skybox` (`rtx.skyMode 0`), `noclouds`,
`nolights`, `cull_lights`, `nopom` (`rtx.displacement.mode 0`), `pvs` (the engine's PVS on),
`novolumetrics`; writes `work/ab_<camera>.json`. Measured there: haze about 3 ms on the grounds, parallax
about 1 ms, the physical sky and clouds nothing measurable, culling nothing measurable.

When the frame is CPU-bound (low GPU use, game threads pegged), profile: `stackprof.py <seconds>
<out.json> auto` and `--report`. Backrooms with the whole map drawn: 46 ms a frame, the D3D9-issuing thread
busy the whole frame (about 40 % Source model rendering, 30 % Remix per-draw preparation, 12 % of it one
global lock taken by every `RtxOption` read, 11 % one `ReadProcessMemory` per model render in a gmRTX hook).

Results to quote, all at 4K with DLSS on an RTX 5090 and a Ryzen 9 9950X3D:

| Map | Stock GMod RTX | Remaster, median of the regions | Slowest region |
| --- | --- | --- | --- |
| modern_house, 25 regions | 37.2 ms (CPU-bound by 991 fill lights) | 16.6 ms | 21.2 ms (the lawn) |
| gm_br_pitfalls, 32 regions | 121 ms | 13.2 ms | 16.6 ms median, 19.4 ms p99 |
| gm_br_complex, 12 regions | not given | 12.8 ms (11.8-13.7) | 13.7 ms |
| gm_poolrooms, 27 views | not given | about 15-16 ms | not given |

## Visibility checks

- `python cullcheck.py <label> [room ...] [--views] [--lights] [--ab]` (Modern House): for each room camera it
  moves the player there (noclip) and holds the view, then counts the map's networked entities (doors,
  glass, fixtures) the client has and draws. `--views` also shoots the room and, with the client's vis
  locked there (`r_lockpvs 1`), the house from above: whatever is missing there was missing from the
  ray-traced scene. `--lights` shoots the room twice with the light manager on and once with every light on;
  `--ab` without culling, with the old culling, and without again; both compare against the repeat (worst
  15-pixel block). Writes `work/cull_<label>.json` and `work/shots/modern_house/cull_<label>/`. Result after
  the fix: all 381 pieces from every room (as few as 39 before).
- `python vischeck.py <map> <label> [camera ...] [--shots] [--frames]` (Backrooms): the same counts per camera
  for PVS against PAS, with shots and frame times. Proof image: standing in the room next to a camera with
  `r_lockpvs 1`, the room is absent before and present after.
- The engine recomputes the visible set only when the view enters another cluster: after changing
  visibility settings, move the camera to another room and back before you judge or measure.

## Load time

A launch with the timeline (`restart.py`, or `loadprof.py` with a CPU profile of the stalling part) polls
`console.log` by byte offset, stamps each line and writes `work/loadtime_<map>.txt` with the marker times
and the twelve longest silences. Modern House: about 2.5 min from `map` (3 min from launch) with about 250
add-ons; the longest pause, about 35 s, was the client's Lua start-up of the installed add-ons; the BSP is
136 MB, 126 MB of it a lightmap lump path tracing never uses. "Couldn't write cache/map_pack.bsp to mount
embedded content!" is harmless. Only measure cold loads on a quiet machine.

## What to present

- The gallery and the stock/remaster pairs (sent as files), named by region.
- Per region: what changed, what still looks wrong, and what was not checked (times of day, rooms you did
  not visit, multiplayer).
- The frame-time table with the noise, stock and remaster from one session; the cost of each feature from
  `abtest.py` when it matters.
- Hash coverage, the light count, the visibility counts, the load time.
- For a choice: the options with their measured trade-offs, the conservative one first.

Keep evidence frames whole: no cropping in place of the full frame (an enlarged inset beside it is fine).

## On the PoC with the native loader

The fork's tools were only used against the classic install. On the PoC the same tools should work once
`*_GAME` points at the PoC and a game launched there is running (unverified as a whole). This repository's
`tools\poc_session.py` handles the launch, the Workshop wait, the camera, screenshots, frame timing and the
quit, and only ends what it started:

```powershell
$e = 'out\poc-sessions\<map>-rtx'
python tools\poc_session.py --evidence $e install --allow-workshop 3829070317 --allow-local <abs path to out\packages\<map>-rtx.gma> --remix on
python tools\poc_session.py --evidence $e run --name 01-look --mount-workshop <map id> --change-map <map> --camera x,y,z,pitch,yaw,roll --hide-hud --settle 30 --screenshots 2
python tools\poc_session.py --evidence $e run --name 02-fps --mount-workshop <map id> --change-map <map> --camera x,y,z,pitch,yaw,roll --fps 30 --console "engine_no_focus_sleep 0" --console "fps_max 0"
python tools\poc_session.py --evidence $e uninstall
```

`--lua FILE` and `--lua-shots SECONDS` run a client Lua tour in one session (each `NL_SHOT <label>` line it
prints becomes a screenshot). Modern House's Workshop item was checked in the field install this way: the
map mounted with `--mount-workshop 3495468649`, then `--change-map`, the add-on's lines present, the terrace
camera within 0.4 of the gallery shot's mean RGB.
