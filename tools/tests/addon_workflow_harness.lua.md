# addon_workflow_harness.lua

LuaJIT harness invoked by test_addon_workflow.py. Arguments are scenario (ame or normals),
production source and optional extracted navigation methods. Minimal GMod stubs assert observable
selection, names and transient hash writes. The Motion importer tab has its own harness,
[motion_tab_harness.lua](motion_tab_harness.lua.md). It performs no filesystem writes, rendering or
networking. Prints PASS and exits zero, or fails an assertion.
