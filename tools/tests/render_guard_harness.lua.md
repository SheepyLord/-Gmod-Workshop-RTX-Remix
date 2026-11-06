# render_guard_harness.lua

Runs the actual self-contained early guard with mocked native interfaces. Arguments are guard
source and scenario; test_render_guard.py invokes it through LuaJIT. Checks no mutation without
verified early/native-client RTX proof, idempotence, immediate
off switch, legacy PostFX/motion-blur behavior, typed/multi-command pins, reviewed numeric enums,
reserved/invalid allocations, normal texture UI and importer copies, unsupported shaders/depth/MRT,
sequential and nested views, hook registry/function identity, object self and return values,
quarantine, timer/cvar callback arguments and private diagnostics. Embedded-NUL console names,
command bodies, material names/shaders and material paths must be refused before native mocks.

The local proof is a mocked `native-loader/status.json` (DATA) in the loader's own format: an
active outcome for local RTX starts, another outcome for an RTX-off start, none for a remote
client. `AddCSLuaFile` is counted and must never be called. `ErrorNoHaltWithStack`, `SysTime` and
`FrameNumber` are mocks, so error reports, the quarantine window and frame boundaries are
deterministic.

The multiplayer fixture executes the actual source in a non-global environment with the native
bootstrap's raw verified marker and a scoped hook proxy with its own Add forwarding function.
It requires the real global dispatcher to stay unchanged in the late route, protects only functions whose
environment is that private one (server callbacks, timers and their errors keep vanilla
behaviour), retains loading-hook identity, does not consult the temporary catalog API or
status.json, and reports its later installation provenance. Early-mode registry identity stays
unchanged; late-mode owned render registrations deliberately contain wrappers.
Global/inherited marker counterexamples must perform no mutations; server/menu cases preserve
their existing behavior. This fixture proves neither pre-autorun timing nor pristine MP enums.

A separate multiplayer fixture captures hook.Call before guard installation. Existing and future
owned render callbacks must still quarantine a failing function after three consecutive failures,
run healthy callbacks, and unwind the failed callback's RT push through that cached dispatcher. It
checks object self/returns, same-function re-registration, replacement recovery, the off switch,
an unchanged server entry and original function identity for existing and future InitPostEntity
entries used by native bootstrap replay.

The cleanup fixture preserves a caller's RT/camera/clip/model stacks and viewmodel depth range,
and asserts mesh.End is never used as an abort. No game, GPU, native fault, filesystem/network
write or user configuration is involved. Exit zero prints PASS; assertion failures exit nonzero.

Stack-ownership cases reject consuming unowned caller or active-ancestor layers, preserve a
successful Pre/Post cross-callback balance, and replay a completed RT push after its permitted pop
is followed by an error. A completed camera pop followed by an error instead reports the explicit
unreplayable-state limitation; the fixture does not claim to reconstruct unknown camera defaults.
Nested cases require a parent's failure to unwind a successful child's extra pushes and to undo
a successful child's completed-scope pop once, and restore a child's direct RT change to its
parent's recorded entry target. A failed child's already-cleaned restoration log
must not be propagated and replayed again when its parent fails.

The leak cases model the stock toolgun screen (RT plus 2D camera left open by a failing
DrawToolScreen) over forty frames and forty failing ENT:Draw scopes in one frame: later pushes are
never refused, scopes from earlier frames cannot satisfy a later pop, and a protected callback's
own 33rd scope is still refused and unwound. The hooks case keeps the original error message out
of the guard's records and MsgN lines while the mocked engine error output receives it.

R8 scenarios prefixed r8_ dispatch to [render_guard_addon_replays.lua](render_guard_addon_replays.lua.md)
with shared fake-engine state and counters. Fixtures include VMT text, cached native materials,
material/entity/projector metatables (including native projector removal), render/surface draws,
copies and a failing native allocator. Native bind doubles require material objects, so an invalid
fallback cannot pass silently. One r8_mp_ scenario runs
through the private late installation while invoking the pre-installation dispatcher. The harness
never loads third-party Lua or starts a game. Current combined count: 47 methods, including one
static inventory/hash check, and 49 LuaJIT invocations (24 R8 replay scenarios).
The MATERIAL_RT_DEPTH fixture uses the official shared=0, separate=1, none=2, only=3 constants.

Material review scenarios check real ExoPBR/GPBR reading, hotloader custom-program creation/draws,
all 344 exact bundled virtual paths, untrusted reuse, lookalike labels and the documented identical
source-label collision. Native shader/program metadata is cached and invalidated on mutation.
The r8_material_cost scenario asserts zero added file.Read calls across mixed paths, PNG/JPG,
trusted calls, repeated misses and bindings. Entity repeats add no native resolution or metadata
queries while objects remain live; trusted entity bindings add no resolution. An optional third
argument models minimum milliseconds per failed VMT lookup across 761 mounts. The nonasserting
r8_material_bench scenario permits comparison with an older guard; it emits BENCH JSON rows and
uses QueryPerformanceCounter through LuaJIT FFI on Windows (os.clock elsewhere). See
[bench_render_guard.py](bench_render_guard.py.md) for measurement scope and output.

R20-D: ordinary camera closers End/End2D/End3D share tracked scopes; Start3D2D requires
End3D2D. Regression scenario `camera_aliases` checks 257 icon-style pairs, every ordinary
start/closer combination, nested calls, cross-family refusal, virtual pushes and error cleanup.

R20-D also loads the real effect observer on top of the real guard (`effect_observer`), rejects
an untrusted screenspace binding and draw with the original virtual caller, then permits a normal
UnlitGeneric sprite. The observer's renderer forwarding stays in tail position.

Native-mode correction (ADR 0122): End and End3D are equivalent 3D pops, while End2D, End3D2D and
EndOrthoView have separate native counters. Generic Start's type selects its family and cleanup.
The harness models independent modes, checks generic 2D cleanup and optional orthographic scopes,
and refuses wrong-mode closers without a native call. Native color-material helpers also clear
stale inert shader state; forwarding through the observer preserves caller policy.

R20-D raster preview compatibility: suppressed-lighting PostRender model previews use bounded,
cached UnlitGeneric base-texture studio overrides (256 materials, 32 slots) and restore every
owned override on success/error. Entity submaterial strings are untouched. Explicit caller
material overrides retain precedence. The wrapper catches late render.Model definitions and
startup replacements; suppression intent is retained for the protected callback because stock
helpers can reset the flag between draws. Early/late definitions, multiple parts, caller overrides,
returns and exception cleanup are exercised by preview_materials / preview_late.

Preview cache follow-up: use stable material/texture names rather than weak Lua userdata keys;
native lookups can return transient wrappers. The regression repeats 300 preview draws with new
wrappers without exhausting the material budget. The DX7 fallback uses a representative base map
through the global studio override; entity submaterials are untouched and explicit indexed/global
caller overrides retain precedence. Multi-material/custom-shader thumbnails are approximate.
