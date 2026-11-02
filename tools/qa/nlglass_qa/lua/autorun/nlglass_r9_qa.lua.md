# nlglass_r9_qa.lua

Development-only R9 QA autorun, packaged with `nlglass_qa`, never shipped. Run as the listen host:

- `nlglass_qa r9-latency`: four spawned and four engine-owned gm_construct map-window pistol/SMG
  energy bursts, in 26 seconds. `NL_R9 latency` rows contain server damage/sent tick, game/wall time,
  client receipt frame, hole build/draw, first draw and last body completion. Compare a fresh map
  for each build. Server health and native break ownership are retained.
- `nlglass_qa r9-velocity`: 250/700/3600-unit/s props, a running player and a bullet break. Native diagnostic samples
  print velocity dot the incoming direction, negative count and worst speed. Before any real map
  bounce the negative count should be zero. The old module lacks the diagnostic API.
- `nlglass_qa r9`: a 25-piece settled pile, an empty-space util blast, env_explosion, grenade,
  explosive barrel and a gm_construct pool water sample (BSP-verified surface -160; initial height -128). `NL_R9 stats` JSON includes blast/split,
  native water, sound and queue counters. A blast must wake/move/split a pile without a Source
  victim; water must report volumes/entries/applied impulses and retain negative slower sinking.
  Stock sound paths must exist and sound counts must obey four/frame, 24/s and per-piece limits.

The fixture owns/removes only its test props/panes, clears local cosmetic debris and restores saved
client convars and server settings at completion. `NL_SHOT_DONE` ends poc_session.py's wait. Optional
camera hooks live only during the fixture. This has game/network/render side effects, no direct
filesystem writes or exit code. Capture raw console only from the session started for this task.

`nlglass_qa r9-water` runs just the water fixture for seven seconds. Moving diagnostic reads poll
a completed worker non-blockingly, so PostRender can sample an active world without waiting. The
full r9 mode also clicks the actual Derma local/everyone buttons and reports before/after counts.

`nlglass_qa r9-perf` runs the same 50 96x64 panes, positions and 0.03-second blast spacing as
field mode, with 6/4/15-second empty/falling/settled measurement windows and no per-hit logging.
It prints mean/p99 and the full counters. Treat a settled window with awake pieces as still
settling; repeat longer before accepting a sleeping-pile baseline.
