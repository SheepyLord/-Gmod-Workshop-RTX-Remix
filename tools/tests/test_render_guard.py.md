# test_render_guard.py

Seventeen unittest cases run eighteen LuaJIT scenarios against the complete production guard,
rather than a policy reimplementation. Run from the repository root:

    python -m unittest discover -s tools/tests -p test_render_guard.py -v

The normal tools/test.ps1 flow also discovers these tests. LuaJIT absence skips them. No game/GPU
or user config is needed; subprocesses only read repository fixtures and print results. These
tests prove Lua policy/contracts, not recovery from native SEH, GPU faults or loops. Exit zero
means success; a failed assertion or subprocess error makes unittest exit nonzero.

The NUL scenario checks native C-string boundaries before dispatch. The stack-ownership scenario
checks unowned/active-parent protection, successful Pre/Post balancing, recorded RT restoration
after an error, and explicit reporting when a popped completed camera cannot be safely replayed.
Nested cleanup also checks chronological action propagation from successful children, without
double restoration of failed children's already-cleaned actions.
The verified multiplayer scenario reproduces the bootstrap's private marker and scoped hook
proxy, while global/inherited-marker and server/menu scenarios must not install client wrappers.
The installation label explicitly distinguishes this later path from early startup protection.
The cached-dispatcher scenario captures original hook.Call before installation and requires
existing/future late render wrappers to contain failures while healthy callbacks and loading-hook
identity survive. Early registry callback identity remains covered by its original scenario.
