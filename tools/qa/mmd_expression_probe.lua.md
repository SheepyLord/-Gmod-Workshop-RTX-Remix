# mmd_expression_probe.lua

Server half of [mmd_hotloader_session.py](mmd_hotloader_session.py.md), injected
through console Lua into a locked PoC session. Never install as an autorun.

Exports `R10MMDQA.Spawn(prefix, role)`, `Menu(prefix)`, `Build(smile|wink|blink)`,
`Play()` and `Stop()`. Spawns the existing library character through the real
hotloader path; exercises the stock NPC menu path too. Builds three generated
facial motion JSONs with the importer's actual client/server builder and plays
them with its real sampler. The motions test `笑い`, `ウィンク`, and `まばたき`.
Logs actual morph identity, controller, geometry side and resolution reason.
Records every server tick from countdown to frame 30, then pauses playback for
a stable screenshot; records native and overflow weights through GetMorphWeight.

Inputs: the current PoC's existing library and add-ons. Outputs: `R10_QA_*`
console events; generated `mmd_vmd_npc/motions/r10_h_<time>_*.json`, corresponding
`built/*_fm2.json`, and `data/r10_mmd_qa/*.json` probes. The driver copies probes
to worktree evidence. Generated paths are enumerated in those probes. Existing
motion files are never overwritten; manual mapping overrides are respected.

Side effects: QA NPCs/ragdolls and undo entries, paused playback/target selection,
hooks/timers lasting this map; generated QA data and built caches. A new own
spawn removes the preceding probe-owned entity. `Stop()` drops
playback. Normal game exit ends hooks and actors. No native binaries, network
publication, settings files or original model files are changed. Lua assertions
and `R10_QA_ERROR` indicate failure; there is no process exit code.
