# test_hotloader_server.py

Runs [hotloader_server_harness.lua](hotloader_server_harness.lua.md) under LuaJIT, once per scenario, without
starting Garry's Mod (R19, the pre-release review). It loads Model Hotloader's shipped
`packages/model-hotloader/mmd_hotloader/lua/mmdhl/server.lua`, `props/server.lua` and `scene_sharing.lua`
whole, and two slices of production code it cuts out of files the harness cannot load whole (written to a
scratch file under `out\tmp`): `mmdhl.CanEdit` and `mmdhl.OwnsEntity` from `sharing.lua` (its server part
reads the cache when it loads) and the collision mesh receiver from `carrier.lua` (it uses Garry's Mod's
`continue`).

```powershell
python -I -m unittest discover -s tools/tests -p test_hotloader_server.py    # from the repository root
```

| Test | Checks |
|---|---|
| `test_only_the_owner_or_an_admin_removes_or_replaces_a_character` | L-02: removing and replacing are asked as the `remover` property and need the owner (prop protection's CPPI owner, else the creator) or an admin; other edits stay with `CanProperty` |
| `test_a_prop_attaches_only_to_a_target_within_reach` | L-07: an attachment to a target farther than 4096 units is refused with `props.attach.aim_target`; one within reach goes on |
| `test_collision_meshes_keep_the_clients_pace` | L-08: one mesh per entity every 1.5 s and four a second per player; players do not hold each other up |
| `test_remote_shapes_the_module_dropped_are_asked_for_again` | MH-05: a shape `PublishRemoteScene` says it dropped is requested again when a frame names it; one the module refused waits ten seconds |

LuaJIT is optional: without it (CI) the tests are skipped. Writes only its scratch file. Exit code 0 on success.
