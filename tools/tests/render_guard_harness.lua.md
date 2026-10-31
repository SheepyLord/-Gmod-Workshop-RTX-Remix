# render_guard_harness.lua

Runs the actual self-contained early guard with mocked native interfaces. Arguments are guard
source and scenario; test_render_guard.py invokes it through LuaJIT. Checks no mutation without
verified early/native-client RTX proof, idempotence, immediate
off switch, legacy PostFX/motion-blur behavior, typed/multi-command pins, early enum snapshots,
reserved/invalid allocations, normal texture UI and importer copies, unsupported shaders/depth/MRT,
sequential and nested views, hook registry/function identity, object self and return values,
quarantine, timer/cvar callback arguments and private diagnostics. Embedded-NUL console names,
command bodies, material names/shaders and material paths must be refused before native mocks.

The multiplayer fixture executes the actual source in a non-global environment with the native
bootstrap's raw verified marker and a scoped hook proxy with its own Add forwarding function.
It requires the real global dispatcher to change, retains loading-hook identity, does not consult
the temporary catalog API, and reports its later installation provenance. Early-mode registry
identity stays unchanged; late-mode render registrations deliberately contain wrappers.
Global/inherited marker counterexamples must perform no mutations; server/menu cases preserve
their existing behavior. This fixture proves neither pre-autorun timing nor pristine MP enums.

A separate multiplayer fixture captures hook.Call before guard installation. Existing and future
render callbacks must still quarantine a failing function once, run healthy callbacks, and unwind
the failed callback's RT push through that cached dispatcher. It checks object self/returns,
same-function re-registration, replacement recovery, the off switch, and original function identity
for existing and future InitPostEntity entries used by native bootstrap replay.

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
