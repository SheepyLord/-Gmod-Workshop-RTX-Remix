# effect_categories_harness.lua

Fake Source/Remix engine running the complete production effect category observer in LuaJIT.
Invoked by test_effect_categories.py, with observer path and scenario arguments. Scenarios:
normal, off, server, no_api, changes, wrappers, retry, bounded and late_hash. Asserts category
contents, API behavior, no cold material loads, malformed/shared texture exclusion, lookup
budgets and failed-publication backoff. Prints PASS on success; exits nonzero on assertion.
No files, game sessions, configs, Steam state or network are changed.

R20-D bounds animated/hash-heavy materials to 64 input hashes each and each published category
to 4,096 hashes. `hash_budget` checks a 10,000-hash response; no unbounded CSV reaches the API.

Live DX7 coverage: normalize shader _DX suffixes, read packed $flags, recognize standard white
aliases and clear stale observer bindings on both color-material helpers. The packed_flags and
color_helper scenarios supplement the hash budgets and normal classifications.
