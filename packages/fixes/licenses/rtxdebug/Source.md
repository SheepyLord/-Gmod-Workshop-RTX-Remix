# RTXDebug 0.2.1 source and build provenance

This directory is documentation/corresponding source, not a second package input. The runtime
inputs remain packages/fixes/modules/gmcl_rtxdebug_win64.dll and source/debug/addon. The native
module source, public external RPC client and tests are all included in checkout/ as plain text.

## Source identity

- Origin: https://github.com/SheepyLord/garrys-mod-rtx-debug-module.git
- Base: ff009d71a5c3d22cd5c400941fb09e7e905b8a73 (the origin's main).
- Patched source: 359b51bcd15eef18dfdb45482367ef43ffcf71c7, on top of
  bc0c698c1b55f3ceb3ec4d2d573a81d100f52fea and 6105f0b545145dc7781f7ae94af76619c2a6e3d4. None of
  the patched commits is on the origin; the three patches below reproduce them from the base.
- checkout/ is the complete tracked text tree at the patched commit; it is already patched.
  Its .gitattributes is stored byte-for-byte as gitattributes.upstream so that its rules cannot
  override this repository's no-conversion package policy. provenance.json records that path alias.
- Apply the patches in order to the base, for review or rebuilding from the originating repository:
  - 0001-Support-multiplayer-client-rendering-diagnostics-wit.patch (base to 6105f0b): the
    multiplayer rendering boundary, and the CLI, protocol and test changes.
  - 0002-Decide-single-player-natively-for-the-developer-muta.patch (6105f0b to bc0c698): the
    native single-player decision for the developer mutation gate (see below), version 0.2.1.
  - 0003-Restrict-read-only-diagnostics-to-local-single-playe.patch (bc0c698 to 359b51b): gate the
    information-disclosure read-only queries on local single-player (see below).
  Applied with `git apply` to the base's tree, the three reproduce checkout/ byte for byte.
- provenance.json lists the SHA-256 and size of every source file, all three patches, dependency
  pins, the tested DLL and the engine vtable slots the gate calls. No binaries, generated projects,
  PDBs or intermediate files are stored here.

The recorded RTXDebug repository commits contain no separate LICENSE file. This source copy retains
their existing notices and does not assert or grant a new module license. The dependency notices
under dependencies/ are copied from the pinned common SDK; their terms remain their own. Source
availability and this provenance notice do not replace the originating rights or license terms.

## Build inputs

- garrysmod_common: https://github.com/danielga/garrysmod_common at
  a854f237b79087826aa9a98a05de5e0d2b4502b6, with the recursive submodule commits in provenance.json.
- Remix headers: public/include from https://github.com/SheepyLord/garrys-mod-rtx-remixed.git at
  fc478c06ec5ae0a94f64aec19df8610a46c51c35, Remix API 0.1000.1.
- Premake 5.0.0-beta2, official Windows archive:
  https://github.com/premake/premake-core/releases/download/v5.0.0-beta2/premake-5.0.0-beta2-windows.zip
  SHA-256 87cfa10ed52fd1f4e835f738ac1033ff302035758671400fec078b700c622c54.
  Premake 5.0.0 is incompatible with this pinned common generator's removed flags API.
- Tested toolchain: Visual Studio 2022 Build Tools, MSVC 14.44.35207, Windows SDK 10.0.26100.0;
  Release/x64, C++17. Generated project references build the pinned SDK helper libraries.

From checkout/, substitute actual dependency/tool paths:

```powershell
& '<premake-beta2>/premake5.exe' --os=windows '--gmcommon=<garrysmod_common>' '--remixinclude=<fixes-fork>/public/include' vs2022
& '<VS2022>/MSBuild/Current/Bin/amd64/MSBuild.exe' RTXDebugModule.sln -t:gmcl_rtxdebug -p:Configuration=Release -p:Platform=x64 -m:2
```

If the workspace path contains an exclamation mark, the pinned generator can emit an incorrect
absolute IntDir. Once the SDK helper libraries are built, build the module project itself with
`-p:BuildProjectReferences=false` and the explicit relative override `-p:IntDir=obj\Release\`.
This is the invocation used for the tested module. Keep worktrees, dependencies and build output
under this project's out directory during agent work. Link/PDB stamps and build paths can change
the resulting binary hash; source reproducibility does not claim byte-identical PE output.

Tested artifact: gmcl_rtxdebug_win64.dll 0.2.1, 428032 bytes, SHA-256
73edd9156bd155e4d9cb70cd75f07da798364b89ea146326f983927218f58e91 (a full rebuild of the module
project with the invocation above).

## Offline checks

Python 3.12 and lupa 2.8 ran `python -m unittest discover -s tests -v`: 20 cases passed. Compile
tests/render_policy_test.cpp and tests/session_policy_test.cpp with a C++17 compiler (MSVC
`/std:c++17 /EHsc /W4 /WX`) and execute them: the renderer policy checks (including the
IsRenderingConVar allowlist) and the mutation gate checks pass. A copy of the session policy that
ignores the loopback condition fails the remote-server cases. The protocol tests cover PID-bound
requests and the target-selection tests refuse ambiguous clients without controlling any game
windows. Run scratch under out/tmp via TEMP/TMP.

The gate's virtual calls were checked offline against the vanilla GMod x64 engine.dll (5707088
bytes, SHA-256 d8f74db72412ffa91c1f01a633d108331145d0a7dff6cffabe1b67ed5abe4fcb), with the
vtables found through RTTI: CEngineClient slot 21 GetMaxClients and 27 IsConnected read the
client state, 72 GetNetChannelInfo returns its channel pointer, 76 IsPlayingDemo asks the demo
player; CNetChan slot 6 IsLoopback tests its remote address for type NA_LOOPBACK. The built DLL
calls exactly those slots (vtable offsets 0xA8, 0xD8, 0x240, 0x260 and 0x30). A game session with
this DLL has not been run yet.

## Multiplayer boundary and external client

Read-only client diagnostics remain available after the verified RTX client payload loads.
Remix.SetConfig and SetDebugView accept local rtx.* renderer options in the module's current client
realm, on its game thread, with a live RemixConfig API. These do not require single-player,
sv_cheats or -insecure. They retain explicit restore values and the owned override ledger.

Lua.Eval, engine/gameplay mutations, memory access and detours retain the original developer gate:
local single-player, sv_cheats 1 and -insecure. The remote server realm is not exposed locally.
The module does not enable sv_allowcslua or load unrelated client code.

Since 0.2.1 the gate reads nothing from Lua. 0.2.0 asked the client realm's game.SinglePlayer,
which a remote server's client scripts can replace, and the server replicates sv_cheats: for a
player launched with -insecure, a malicious insecure server could open the gate and reach the
memory, detour and Lua.Eval functions. Single-player now means the engine client is connected
through the in-process loopback channel to the server this game runs, with one player slot and no
demo playing (IVEngineClient IsConnected, GetNetChannelInfo()->IsLoopback(), GetMaxClients and
IsPlayingDemo). A remote server cannot make the client's channel loopback. -insecure still comes
from the process command line and sv_cheats from the cvar system. The rendering gate's client-realm
check likewise compares the module's state with lua_shared's client state instead of reading the
CLIENT_DLL/SERVER/MENU_DLL globals. The read-only and rtx.* rendering surface is unchanged.

Patch 0003 then closes the read-only information leaks reachable by server-sent client Lua in
multiplayer. Outside local single-player (the same native decision): Interfaces.Resolve (module and
vtable addresses), Interfaces.FileExists and Engine.ListConsole are refused; Engine.GetConVar reads
only rendering convars, by the short case-insensitive allowlist Policy::IsRenderingConVar in
render_policy.h (rtx*, r_*, mat_*, cl_draw*); and Lua.Global/Lua.Hooks read only the module's own
client state, not the menu or server realm. Read-only client diagnostics and the rtx.* rendering
query/config calls a multiplayer RTX session uses stay available.

Use checkout/tools/rtxdebug_client.py with --pid or --root. It refuses multiple matching processes,
uses pointer-sized Windows handle signatures and binds each request/reply to its selected PID and
request ID. The updated DLL and companion are required for PID binding. The transport reads no
console logs and removes its own request/response files when finished.

This directory can be shipped at rtx_debug/source using the packager's add-to-addon mapping.
The checkout's Lua/test files are inside source/checkout, outside the add-on's executable lua root.
