# test_glass_interaction.py

R7-C offline unittest entry point. From `tools`, run
`python -m unittest discover -s tests -p test_glass_interaction.py -v`.

Uses installed LuaJIT, skipping when absent; no downloads. Six scene/bullet cases execute the real
helpers in `glass_interaction_harness.lua`. Six manager cases execute `glass_debris_harness.lua`:
bounded damage bursts, oldest-first replacement/minimum-size refusal, inherited expiry and changed
lifetimes, disabling during a worker step while preserving blast pushes, and bounded/expiring rays.
The sixth runs the QA add-on's real client fixture and stats formatter, and checks per-pane size metadata.
Other glass tests cover the menu/translations and actual server break-region registration.
No game launches, install writes, network or package imports. Exit status follows unittest.
