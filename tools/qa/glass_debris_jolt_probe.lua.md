# glass_debris_jolt_probe.lua

G1-B client performance probe for Claude's game acceptance. Load this client Lua through the existing
QA driver in a scene with a flat floor under the eye trace. This task's implementation never runs it.
Requires `NLGlassDebris` and its `Stats()` extension; no panes, server entities or assets are created.

Optional client globals before execution:

- `NL_GLASS_PROBE_COUNT = 4000` (1-8192), `NL_GLASS_PROBE_SECONDS = 20` (5-120 seconds of falling).
- `NL_GLASS_PROBE_ORIGIN = Vector(...)` chooses the floor centre instead of the player's eye trace.
- `NL_GLASS_PROBE_KEEP = true` retains the pieces at the end; default clears them.

The probe clears cosmetic glass, temporarily sets the client budget to N and lifetime to zero, imports
the backend with one piece, clears it, warms for two seconds and samples five seconds with no pieces.
Then N rectangular shards fall in four layers (the same geometry as the native benchmark); it samples
the falling interval and a final ten-second interval. Consecutive `SysTime()` samples measure full
wall frame intervals, including stalls. Each phase prints `NL_GLASS_PROBE` mean, p50,
p95, p99 and maximum frame time in ms, backend and manager/body/draw counts. At most 30000 samples
are kept per phase. The final interval is labelled `settled`; check its moving count rather than
assuming the pile slept. A fallback run keeps at most 64 pieces and reports the actual count.

Use the same position, view, graphics settings and quiet scene for baseline/measurement. Frame
times include rendering and the game's other work, unlike CTest's physics-only CPU timings.
Compare the baseline and settled means/p95s and retain the console log with the scene description.

Cleanup restores settings only if they still equal the probe's temporary values, preserving a
player's intervening edits. `NLGlassDebrisProbe.Cancel()` stops early and does the same cleanup.
No disk, Steam, launch-option, network or package writes. Lua prints an error and stops if the
manager/player is missing or the backend never initializes within 60 seconds; success prints
`NL_GLASS_PROBE done`. No process exit code is used inside the game.
