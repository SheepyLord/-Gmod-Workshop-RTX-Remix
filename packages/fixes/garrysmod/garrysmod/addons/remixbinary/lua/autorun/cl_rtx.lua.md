# cl_rtx.lua

GPL-2.0 RTX fixes client entry point. Requires RTXFixesBinary and NikNaks, loads the shared/client
rendering scripts, restores rendering cvars and registers model-reload and shutdown cleanup hooks.
It runs through the engine in ordinary sessions, or through the verified RTX catalog in multiplayer.
No standalone command-line interface; failures are reported locally.

The verified late multiplayer initializer sets NATIVELOADER_VERIFIED_MULTIPLAYER only in its
scoped script environment. In that context the initial/final model hardware-cache flushes are
skipped: the world already holds static-prop mesh references. Existing meshes stay valid and
the native VTX hooks serve subsequent loads. Ordinary early engine loading keeps both reloads.
