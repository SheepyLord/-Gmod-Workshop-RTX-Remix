# motion_tab_harness.lua

LuaJIT harness for [test_motion_tab.py](test_motion_tab.py.md): the companion's Motion importer
creation tab and the Character Motion Importer's builders (`MMDVMDNPC.BuildMotionImporter`,
`MMDVMDNPC.BuildMotionManager`) and windows, under mocked Garry's Mod and Derma.

```powershell
luajit tools\tests\motion_tab_harness.lua <scenario> <tab .lua> <add-on lua\mmd_vmd_npc folder>
```

Scenarios: `late`, `unavailable`, `windows`, `shared`, `fallback`, `broken`, `scale`, `guiscaler`, `translations` (what each checks:
the test's table). The add-on's catalogs and lookups are loaded from `sh_core.lua` (the text between
`MMDVMDNPC.I18N =` and its `if CLIENT then` block), then its client files run whole. Panels record
what is set on them; layout is checked from their docking, order (ZPos, then creation), visibility,
enabled state and texts, not from pixels. GMod's hook rule is mocked: a panel identifier is passed
first and dropped once the panel is removed. Model Hotloader's file access is a mock that records
picks. Unmocked globals are inert stubs (numeric enums are 0); `MMDVMDNPC`, `mmdhl` and `g_SpawnMenu`
stay absent until a scenario sets them.

Writes nothing, sends nothing, renders nothing. Prints `PASS <scenario>` and exits 0, or fails an
assertion with a message (non-zero exit).
