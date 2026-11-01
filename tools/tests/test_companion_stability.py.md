# test_companion_stability.py

Builds the shipping gettext catalogs under `out/tmp`, then runs the actual menu, guide and i18n
module under LuaJIT with [`companion_stability_harness.lua`](companion_stability_harness.lua.md).
Checks all three tiers and selection sources, hidden non-NVIDIA/empty hardware, reasons for
unapplied tiers, fresh reads when the panel reopens, and direct guide-page navigation in English
and all six translated languages. Older loaders get update/manual-evidence guidance without
R6-only config keys or collection promises. R6 guide and docs JSON examples must parse and retain
the shipped `allow` list. Building/opening these controls must send no Remix or
configuration writes. Guide text stays wrapped and vertically stretchable; first-run/default guide
navigation still opens Welcome. Six integration scenarios serialize complete schema-1 status
documents (including T1's real non-NVIDIA/query-failed/no-layer shapes) and use an actual JSON
decoder for both menu and guide instead of the Lua table stub. The test-only helper mode
`--decode-status <path>` parses JSON and prints a Lua return table for the harness.

Run `python -m unittest discover -s tools/tests -p test_companion_stability.py -v` from the repository,
or `tools/test.ps1 -Config Release`. Requires an existing LuaJIT installation; skips if unavailable.
Inputs are companion Lua, catalogs, the shipped config and player docs. Only temporary generated
catalog/status files under `out/tmp` are written and cleaned up (and usual Python bytecode caches).
No game, GPU, network or installed-game files. Exit 0 passes/skips; a
catalog error, timeout or failed assertion exits nonzero.
