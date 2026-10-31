# test_companion_stability.py

Builds the shipping gettext catalogs under `out/tmp`, then runs the actual menu, guide and i18n
module under LuaJIT with [`companion_stability_harness.lua`](companion_stability_harness.lua.md).
Checks all three tiers and selection sources, missing hardware placeholders, fresh reads when the
panel reopens, and direct guide-page navigation in English and all six translated languages.
Missing/invalid reports show no tier line. Building/opening these controls must send no Remix or
configuration writes. Guide text stays wrapped and vertically stretchable; first-run/default guide
navigation still opens Welcome.

Run `python -m unittest discover -s tools/tests -p test_companion_stability.py -v` from the repository,
or `tools/test.ps1 -Config Release`. Requires an existing LuaJIT installation; skips if unavailable.
Inputs are companion Lua and catalogs. Only temporary generated catalog code under `out/tmp` is
written and cleaned up. No game, GPU, network or installed-game files. Exit 0 passes/skips; a
catalog error, timeout or failed assertion exits nonzero.
