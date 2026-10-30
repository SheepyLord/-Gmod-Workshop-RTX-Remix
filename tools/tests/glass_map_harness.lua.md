# glass_map_harness.lua

LuaJIT assertions for the shipped glass brush geometry, native-break integration and packet writer.
Run through test_glass_map.py. Generated thin, horizontal and rotated boxes exercise fracture count,
closed hull volume and invalid geometry. Engine stubs cover native event ordering, duplicate events,
non-glass entities, ordinary removal, cleanup, persistent independent pieces and the debris budget.
The actual network writer sends a generated late-join pile in bounded messages. No game is launched.
