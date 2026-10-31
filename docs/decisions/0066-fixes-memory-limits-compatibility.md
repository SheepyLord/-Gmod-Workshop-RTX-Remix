# 0066: Keep the fixes' unsupported memory-limit API as a compatibility no-op

- Status: Accepted 2026-10-31
- Decided by: the user's approval of R5 stability proposal 9, recorded in the R6 plan

## Context

The fixes module submitted `rtx.resourceLimits.maxCacheSize` and `.maxVRAM` at every map load.
Remix has never supported these options; they produced two rejections and imposed no limits.
Lua add-ons can also call the exported `RemixResource.SetMemoryLimits` function. Actual budget
options written through the configuration API enter the User layer, which Remix Save can persist
to `user.conf`. See [the proposal](../handover/R5-stability-proposal.md#21-where-the-rtxresourcelimits-keys-come-from)
and [R6 T5 research](../RESEARCH.md#r6-t5-fixes-memory-limit-compatibility).

## Decision

Remove the module-open call. Retain the C++ method and Lua binding as documented no-ops: Lua
still requires two numbers and returns `true` for compatibility. Log once per loaded module
lifetime, on an explicit call, that Remix has no cache/VRAM limit options and no limits changed.
Perform no configuration writes; performance defaults belong in package layers.

Rebuild from the preceding packaged DLL's recorded native source commit, preserving its
oversized-skinning changes, dependency pins, generated projects and build configuration. Keep
the patch, complete changed GPL sources, regression test and new build pins in the fixes part's
existing source bundle. Import only the rebuilt DLL through `inputs.py`.

## Consequences

Map loads stop producing the unsupported-option warnings. Existing callers retain their API
shape without a false claim that a cache/VRAM limit was applied. A DLL unload/reload can produce
one new explanatory notice when explicitly called again. No memory saving is claimed for this
change: the old settings were rejected. Renderer acceptance remains an integration check.

## Alternatives considered

- Removing the Lua function would unnecessarily break existing add-ons.
- Returning `false` would change the legacy result without adding useful capability.
- Substituting real budget settings would change behavior and risk saving them to `user.conf`.
