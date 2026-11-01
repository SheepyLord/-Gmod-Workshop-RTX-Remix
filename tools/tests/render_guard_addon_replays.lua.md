# render_guard_addon_replays.lua

Eighteen authored API-call replay scenarios for the R8-C graphics audit. Invoked only by
[render_guard_harness.lua](render_guard_harness.lua.md) with its fake engine context; it is not a
standalone program and never loads or executes downloaded/installed add-on Lua.

Inputs: scenario name and the harness's tables, native-call counters and assertions. Minimal
original snippets use audited call signatures and virtual chunk names for GShader, FXAA, SSDO,
SSR, NikNaks, Quick Bloom, Real CSM and Life Mod. Provenance and limitations are in
[the audit](../../docs/audits/R8-C-addon-compat.md).

Assertions check initialization continuing, real texture/material fallbacks, no native custom
shader load, no unsafe copy/MRT/draw, world/material preservation, private light-metatable
readback and repeated projector-cache retirement, memory/name limits, balanced ignored scopes and blocked backbuffer escapes, normal controls, cached multiplayer
dispatch and unrelated server error behavior. Renderer-disabled calls delegate to the originals.
No file/config writes, game launch, GPU calls, network, Steam or Workshop changes occur. A failed
assertion raises in the harness process; its nonzero exit fails unittest. GPU/real multiplayer
timing and the original crash require Claude's separate QA.
