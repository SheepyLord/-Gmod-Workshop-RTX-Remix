# hotloader_server_harness.lua

The LuaJIT side of [test_hotloader_server.py](test_hotloader_server.py.md): stubs the parts of Garry's Mod
that Model Hotloader's server and client Lua use (hooks, net messages read from a queue and counted when
sent, entities whose unknown methods do nothing, `CanProperty` recording the property asked), loads the
production slices the test wrote, then runs one scenario.

```powershell
luajit tools\tests\hotloader_server_harness.lua <scenario> packages\model-hotloader\mmd_hotloader\lua\mmdhl <slices file>
```

The slices file holds `-- slice <name>` ... `-- end <name>` blocks: `sharing` (`mmdhl.CanEdit`,
`mmdhl.OwnsEntity`) and `carrier` (the `mmdhl_collision_mesh` receiver).

Scenarios: `remove` (loads `server.lua`), `attach` (`props/server.lua`), `mesh` (the carrier slice), `scene`
(`scene_sharing.lua` as the client).

**Output:** `PASS <scenario>`, exit 0; a failed check raises `FAIL <scenario>: <why>` (exit 1).
**Writes:** nothing on disk.
