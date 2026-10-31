# RTXDebug

Developer introspection module for Garry's Mod RTX Remix, including multiplayer client diagnostics.
The DLL is independent of `RTXFixesBinary`; it uses the existing `RemixConfig`,
`RemixResource`, and `RemixMaterial` Lua APIs when that module is loaded. It is
compiled against the fork's Remix API headers at version **0.1000.1** and is
64-bit only.

## Build

This repository is checked out at `source/debug` in
`garrys-mod-rtx-remixed`. From the parent repo root:

```powershell
./premake5.exe --os=windows --gmcommon=./garrysmod_common vs2022
& 'C:\Program Files (x86)\Microsoft Visual Studio\2022\BuildTools\MSBuild\Current\Bin\amd64\MSBuild.exe' RTXFixesBinary.sln -t:gmcl_rtxdebug -p:Configuration=Release -p:Platform=x64
```

The project is `gmcl_rtxdebug`; its output is `x86_64/Release/gmcl_rtxdebug_win64.dll`.
It has no Win32 configuration, so a Win32 build of the solution skips it, and the
parent workspace leaves it out when `source/debug` is not checked out.
`premake5.lua` in this folder builds the module alone: run
`premake5.exe --os=windows --gmcommon=../../garrysmod_common vs2022` here and
build `RTXDebugModule.sln`. A standalone worktree can pass
`--remixinclude=<fork>/public/include` as well as `--gmcommon=<fork>/garrysmod_common`.
The pinned common SDK works with Premake 5.0.0-beta2; Premake 5.0.0 removes its legacy flags API.
When the workspace contains `!`, build the project with `-p:IntDir=obj\Release\`
to keep intermediates relative to it. Use `-p:BuildProjectReferences=false` only when the pinned
SDK helper libraries have already been built.

## Install

The build has no install or copy step. Copy the DLL to `garrysmod/lua/bin/` and
the contents of `addon/` to `garrysmod/addons/rtx_debug/`. Replace the DLL only
while the game is closed or before a map has loaded it: a loaded module locks
the file. New addon folders are mounted when the game starts.

Read-only client diagnostics and local Remix configuration work without `-insecure`,
including on a multiplayer server with `sv_allowcslua 0`, once the RTX package's verified
client bootstrap has loaded this addon. The addon loads the DLL with `require("rtxdebug")`.
`RTXDebug.Status()` distinguishes the full developer mutation gate from the client rendering gate.
Arbitrary Lua evaluation, engine/gameplay mutations, memory and detours still require local
single-player, `sv_cheats 1` and `-insecure`. The module decides single-player from the engine
client's own connection, never from Lua. A remote server realm is unavailable locally.

## Conventions

- Functions return their result, or `nil` and an error message.
- Everything runs on the game thread. Detour callbacks never touch entities or Lua.
- Anything that changes engine/gameplay state needs the mutation gate: local single-player,
  `sv_cheats 1` and the `-insecure` launch option. Memory reads need it too.
  Restoring and listing this module's own changes do not, so they still work
  after `sv_cheats` is turned off.
- The mutation gate reads nothing from Lua (`source/session_policy.h`). Single-player means the
  engine client is connected through the in-process loopback channel to the server this game runs,
  with one player slot and no demo playing: `IVEngineClient::IsConnected`,
  `GetNetChannelInfo()->IsLoopback()`, `GetMaxClients()` and `IsPlayingDemo()`. `-insecure` comes
  from the process command line and `sv_cheats` from the cvar system. A remote server's client
  scripts can replace `game.SinglePlayer`, and the server replicates `sv_cheats`, but it cannot
  make the client's channel loopback.
- Outside local single-player, read-only queries that could disclose information to a remote
  server's client scripts are refused: `Interfaces.Resolve` and `Interfaces.FileExists`,
  `Engine.ListConsole`, `Engine.GetConVar` for non-rendering convars (allowlist `IsRenderingConVar`
  in `source/render_policy.h`: `rtx*`, `r_*`, `mat_*`, `cl_draw*`), and `Lua.Global`/`Lua.Hooks` for
  any realm other than the module's own client state. The read-only client diagnostics and the
  `rtx.*` rendering query/config surface a multiplayer RTX session uses stay available.
- Local Remix-only writes have their own gate: the module's live client realm (the state that
  lua_shared reports as the client's, not the `CLIENT_DLL`/`SERVER` globals), the game thread,
  and an available RemixConfig.SetConfigVariable function. Without the full developer gate,
  only `rtx.*` option keys are accepted. This does not change server cvars or enable Lua Eval.
- Addresses and 64-bit values are hex strings, which Lua numbers cannot hold exactly.
- Realms are `"client"`, `"server"` (the listen server in single-player) and `"menu"`.
  Results from other realms are copied as plain data: vectors and angles become
  arrays, entities become `{index, class}`, other userdata becomes `"<type>"`,
  and nesting stops at 6 levels or 20000 values.

## Lua API

The global table is `RTXDebug`:

```lua
RTXDebug.Status()       -- process_id, gate inputs, can_configure_rendering, active change counts
RTXDebug.RestoreAll()   -- undo every change below; returns counts and failures

RTXDebug.Engine.ListConsole("mat_", 0, 200)      -- local single-player only; prefix, offset, limit (max 1000)
RTXDebug.Engine.GetConVar("mat_queue_mode")      -- rendering convars anywhere; other names local single-player only
RTXDebug.Engine.SetConVar("mat_queue_mode", "0") -- gated; restored on RestoreAll/unload
RTXDebug.Engine.RestoreConVar("mat_queue_mode")
RTXDebug.Engine.ConVarOverrides()
RTXDebug.Engine.Exec("mat_reloadallmaterials")   -- gated; outside the restore ledger
RTXDebug.Engine.World()
RTXDebug.Engine.Entities("client", "prop_physics", 0, 200)
RTXDebug.Engine.Entity("client", 1)              -- materials, submaterials, bodygroups, NW vars

RTXDebug.Interfaces.Status()                     -- which Source interfaces are exported
RTXDebug.Interfaces.Resolve("engine", "VEngineClient015")  -- local single-player only; address, vtable, vtable_rva
RTXDebug.Interfaces.Material("models/debug/debugwhite")    -- shader, flags, shader params
RTXDebug.Interfaces.Materials("models/", 0, 200) -- loaded materials by prefix
RTXDebug.Interfaces.FileExists("materials/debug/debugwhite.vmt", "GAME")  -- local single-player only

RTXDebug.Lua.Realms()
RTXDebug.Lua.Eval("menu", "return collectgarbage('count')")  -- gated; {value, values, n}
RTXDebug.Lua.Global("client", "RemixRenderCore._handlers")  -- other realms local single-player only
RTXDebug.Lua.Hooks("client", "Think")                      -- other realms local single-player only
RTXDebug.Lua.GCStats("client")

RTXDebug.Remix.Vram()
RTXDebug.Remix.ConfigFile("rtx.graphicsPreset")  -- the rtx.conf value, not the live one
RTXDebug.Remix.SetConfig("rtx.graphicsPreset", "3", "2")  -- client rendering gate; explicit restore value
RTXDebug.Remix.RestoreConfig("rtx.graphicsPreset")
RTXDebug.Remix.SessionConfig("rtx.graphicsPreset")
RTXDebug.Remix.Overrides()
RTXDebug.Remix.DebugViewFile()
RTXDebug.Remix.SetDebugView(3, 0)                -- client rendering gate; index, restore index
RTXDebug.Remix.MaterialHashes("models/debug/debugwhite")
RTXDebug.Remix.FindMaterialByHash("0x29BF18C8B6EC2F40")  -- {materials, revision}
RTXDebug.Remix.TrackedTextures()
RTXDebug.Remix.HashStats()
RTXDebug.Remix.ExpectedApiVersion()

RTXDebug.Memory.Modules()
RTXDebug.Memory.Scan("engine.dll", "48 8B ?? 24", ".text")
RTXDebug.Memory.Read("0x7FF600001000", "u32", 1)
RTXDebug.Memory.Write("0x7FF600001000", "u32", 7, "01000000")  -- returns a write ID
RTXDebug.Memory.RestoreWrite(1)
RTXDebug.Memory.Writes()
RTXDebug.Memory.PatchDefine("my_patch", "engine.dll", "48 8B ?? 24", 4, "11223344", "90909090")
RTXDebug.Memory.PatchApply("my_patch")
RTXDebug.Memory.PatchRestore("my_patch")
RTXDebug.Memory.PatchList()

RTXDebug.Detours.List()
RTXDebug.Detours.Enable("client_cmd")            -- gated
RTXDebug.Detours.Events(50)                      -- newest captured events, up to 128
RTXDebug.Detours.Disable("client_cmd")
```

`Memory.Read` supports `u8/i8/u16/i16/u32/i32/u64/i64/f32/f64/bytes` and reads at
most 4096 bytes. `Write` takes at most 64 bytes and requires the current bytes as
`expectedHex`. Patches require a signature with exactly one match in an executable
section, and the expected bytes at the patched address.

`Interfaces.Material` reports only materials that are already loaded. Texture
parameters show their texture name once the material is precached; the query
never loads textures.

The Source interfaces come from `garrysmod_common`'s `sourcesdk-minimal`, which
does not match GMod x64 everywhere. Every virtual call this module makes was
checked against the game's DLLs (vtables found through their RTTI). Two places
differ: vstdlib's cvar iterator has a virtual destructor in front of its
methods, so `ListConsole` uses its own iterator declaration, and
`CMatSystemSurface::GetScreenSize` sits one slot later than `ISurfaceV30`
declares it, so there is no VGUI surface query (`Engine.World` reports the
screen size). Check new interface calls the same way before using them. The
single-player check uses `CEngineClient` slots 21 (`GetMaxClients`), 27
(`IsConnected`), 72 (`GetNetChannelInfo`) and 76 (`IsPlayingDemo`), and
`CNetChan` slot 6 (`IsLoopback`, a test for address type `NA_LOOPBACK`), all
where `sourcesdk-minimal` declares them.

The `client_cmd` detour records calls to `IVEngineClient::ClientCmd` in a
128-entry ring buffer (sequence, tick, thread, command text).

## Restoring

Convar changes, Remix session overrides, typed writes, applied patches and the
detour are recorded when they are made. `RestoreAll()` undoes them in reverse
order and reports anything it could not restore, such as a write whose bytes
were changed by something else. Patch definitions survive it.

The addon calls `RestoreAll()` from the `ShutDown` hook (map change, disconnect,
quit). That matters for Remix overrides: they go through `RemixConfig`, which stops
working once RTXFixesBinary has closed. On unload the module restores whatever is
still recorded, but it skips Remix overrides if RTXFixesBinary is already gone and
logs that they stay in effect until the game restarts. Lua code run through
`Lua.Eval` and commands run through `Engine.Exec` are outside this ledger.

## External request protocol

Write a JSON file at `garrysmod/data/rtx_debug/requests/<id>.json`:

```json
{"id":"probe_42","method":"Engine.Entities","args":["client","prop_physics",0,100]}
```

Send `rtx_debug_request probe_42` through the game's console channel. The
module executes the request on the game thread. The addon writes
`garrysmod/data/rtx_debug/results/probe_42.json` and prints
`[RTXDebug] DONE probe_42` to `garrysmod/console.log`. The result has `ok`,
`result` or `error`, `id`, `time` and `protocol` (1) fields. `method` is `Status`,
`RestoreAll` or `<Section>.<Function>`. IDs contain only letters, numbers, `_`,
and `-`; request files are capped at 1 MiB and results at 8 MiB.

`tools/rtxdebug_client.py` does all of this from outside the game; it sends the
command as a `WM_COPYDATA` message to the game window, the same channel the
`rtx_agent` harness uses:

```powershell
python tools/rtxdebug_client.py Engine.Entity client 1
```

No network listener is opened.

## Tests

`python tests/test_transport.py` checks the request protocol without starting
GMod (`lupa` required; it uses LuaJIT when lupa has it). `python -m unittest
discover -s tests` also runs the external client's target-selection tests.
`tests/render_policy_test.cpp` and `tests/session_policy_test.cpp` check the
rendering and mutation gates: compile each with a C++17 compiler (for example
`cl /std:c++17 /EHsc /W4`) and run it.

## Lifecycle

`GMOD_MODULE_OPEN` registers one `RTXDebug` table and the native
`rtx_debug_request` command. `GMOD_MODULE_CLOSE` stops requests, unregisters
the command, disables detours, restores Remix overrides (see above), convars,
patches and typed writes, then removes the Lua table.
