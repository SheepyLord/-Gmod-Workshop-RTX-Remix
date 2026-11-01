# test_glass_interaction.py

R7-C offline unittest entry point. From `tools`, run
`python -m unittest discover -s tests -p test_glass_interaction.py -v`.

Uses installed LuaJIT, skipping when absent; no downloads. Six scene/bullet cases execute the real
helpers in `glass_interaction_harness.lua`. Six manager cases execute `glass_debris_harness.lua`:
bounded damage bursts, oldest-first replacement/minimum-size refusal, inherited expiry and changed
lifetimes, disabling during a worker step while preserving blast pushes, and bounded/expiring rays.
The sixth runs the QA add-on's real client fixture and stats formatter, and checks per-pane size metadata.
Other glass tests cover the menu/translations and actual server break-region registration.

The fast-body follow-up adds lookahead/direction/distance/upgrade checks and an end-to-end replay:
real Lua capture of 3600-unit/s and crowded 650-unit/s boxes at 60/30 Hz feeds the built native
`nl_glass_scene_replay.exe` via stdin. Its generated settled nine-piece pile must move and receive
body damage; every kinematic target stays exact. The same rows with interaction off must do nothing.
Both scenarios fail before the fix (zero moved pieces/body hits). The replay test prefers Release,
then Debug, and skips only when neither executable is built; the full gate builds it first.
No game launches, install writes, network or package imports. Exit status follows unittest.
