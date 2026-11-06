# effect_categories_harness.lua

Fake Source/Remix engine running the complete production effect category observer in LuaJIT.
Invoked by test_effect_categories.py, with observer path and scenario arguments. Scenarios:
normal, off, server, no_api, changes, wrappers, retry, bounded and late_hash. Asserts category
contents, API behavior, no cold material loads, malformed/shared texture exclusion, lookup
budgets and failed-publication backoff. Prints PASS on success; exits nonzero on assertion.
No files, game sessions, configs, Steam state or network are changed.
