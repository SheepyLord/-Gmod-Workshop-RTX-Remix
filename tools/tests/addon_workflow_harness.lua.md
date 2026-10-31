# addon_workflow_harness.lua

LuaJIT harness invoked by test_addon_workflow.py. Arguments are scenario (ame, normals or motion),
production source and optional extracted navigation methods. Minimal GMod stubs assert observable
selection, names, transient hash writes and opening the existing motion manager. It performs no
filesystem writes, rendering or networking. Prints PASS and exits zero, or fails an assertion.
