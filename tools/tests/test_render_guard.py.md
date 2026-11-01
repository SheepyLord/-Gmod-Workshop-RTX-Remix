# test_render_guard.py

Twenty-two unittest cases run twenty-five LuaJIT scenarios against the complete production guard,
rather than a policy reimplementation. Run from the repository root:

    python -m unittest discover -s tools/tests -p test_render_guard.py -v

The normal tools/test.ps1 flow also discovers these tests. LuaJIT absence skips them. No game/GPU
or user config is needed; subprocesses only read repository fixtures and print results. These
tests prove Lua policy/contracts, not recovery from native SEH, GPU faults or loops. Exit zero
means success; a failed assertion or subprocess error makes unittest exit nonzero.

Refused calls now return safely (ADR 0086); the NUL scenario checks native C-string boundaries before dispatch. The stack-ownership scenario
checks unowned/active-parent protection, successful Pre/Post balancing, recorded RT restoration
after an error, and explicit reporting when a popped completed camera cannot be safely replayed.
Nested cleanup also checks chronological action propagation from successful children, without
double restoration of failed children's already-cleaned actions.
The verified multiplayer scenario reproduces the bootstrap's private marker and scoped hook
proxy, while global/inherited-marker and server/menu scenarios must not install client wrappers.
The installation label explicitly distinguishes this later path from early startup protection.
The cached-dispatcher scenario captures original hook.Call before installation and requires
existing/future owned late render wrappers to contain failures while healthy callbacks, server
callbacks and loading-hook identity survive. Early registry callback identity remains covered by
its original scenario.

[ADR 0056](../../docs/decisions/0056-guard-and-startup-fallbacks.md) cases: the autorun install
of a local RTX start without the early view; a served initializer (early flag without this
machine's active start) and an RTX-off start installing nothing; error reports with the original
message and quarantine only after three consecutive failures within ten seconds, never for a
gamemode method; per-category report caps; scopes leaked outside protected callbacks at
FrameNumber and PreRender boundaries; and the hot-path contracts (no switch read for unprotected
events, lazy entry render target, cached shader names).

R8 adds a separate eighteen-case suite in [test_render_guard_addons.py](test_render_guard_addons.py.md).
Together the suites run 40 methods/43 scenario invocations. Existing refusal assertions now require
no escaped error and verify native-call counters; deliberate add-on errors still test containment,
reporting and quarantine. The leaked-scope limit test balances ignored pushes/pops instead of
relying on a guard-created exception to unwind a successful callback.
