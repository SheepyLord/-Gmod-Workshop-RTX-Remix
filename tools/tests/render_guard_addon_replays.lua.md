# render_guard_addon_replays.lua

Twenty-four authored regression replay scenarios for the R8-C graphics audit, plus a timing
variant of the material-cost scenario. Invoked only by
[render_guard_harness.lua](render_guard_harness.lua.md) with its fake engine context; it is not a
standalone program and never loads or executes downloaded/installed add-on Lua.

Inputs: scenario name and the harness's tables, native-call counters and assertions. Minimal
original snippets use audited call signatures and virtual chunk names for GShader, FXAA, SSDO,
SSR, NikNaks, Quick Bloom, Real CSM and Life Mod. Provenance and limitations are in
[the audit](../../docs/audits/R8-C-addon-compat.md).

Assertions check initialization continuing, real texture/material fallbacks, native material
loading/inspection and scoped custom-shader bindings, no unsafe copy/MRT/draw, world/material preservation, private light-metatable
readback and repeated projector-cache retirement, memory/name limits, balanced ignored scopes and blocked backbuffer escapes, normal controls, cached multiplayer
dispatch and unrelated server error behavior. Renderer-disabled calls delegate to the originals.
No file/config writes, game launch, GPU calls, network, Steam or Workshop changes occur. A failed
assertion raises in the harness process; its nonzero exit fails unittest. GPU/real multiplayer
timing and the original crash require Claude's separate QA.

Review regressions cover real ExoPBR/GPBR fields at both fixes-reader virtual paths, MMDHL's
screenspace_general/mmdhl_vs20/mmdhl_ps20b creation and owned drawing, all 344 exact bundled
paths, untrusted reuse, source-name lookalikes and an identical-path collision. Material-cache
reuse and mutations cannot lose custom-program checks. Cost assertions use 1,200 mixed paths,
1,200 PNG/JPG icons, trusted calls and repeated loads/bindings: no guard disk reads, repeated
entity names add no native resolution or metadata query, and trusted bindings need none.
`r8_material_bench` uses the same workload without current-policy assertions so the older guard
can run too; BENCH JSON rows report elapsed time and counters. The optional slow file.Read double
and [benchmark driver](bench_render_guard.py.md) do not measure actual mounted archives.
