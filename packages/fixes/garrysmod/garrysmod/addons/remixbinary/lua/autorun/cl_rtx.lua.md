# cl_rtx.lua

GPL-2.0 RTX fixes client entry point. Requires RTXFixesBinary and NikNaks, loads the shared/client
rendering scripts, restores rendering cvars and registers model-reload and shutdown cleanup hooks.
It runs through the engine in ordinary sessions, or through the verified RTX catalog in multiplayer.
No standalone command-line interface; failures are reported locally.

The verified late multiplayer initializer sets NATIVELOADER_VERIFIED_MULTIPLAYER only in its
scoped script environment. In that context the initial/final model hardware-cache flushes are
skipped: the world already holds static-prop mesh references. Existing meshes stay valid and
the native VTX hooks serve subsequent loads. Ordinary early engine loading keeps both reloads.

Loaded normally (outside that environment, once the binary module is installed), it sets the
global NATIVELOADER_RTX_NORMAL_LOAD. The verified initializer then finishes without running the
payload a second time: on a listen host, an sv_allowcslua 1 server or a server that ships these
add-ons, the normal load already ran it.
