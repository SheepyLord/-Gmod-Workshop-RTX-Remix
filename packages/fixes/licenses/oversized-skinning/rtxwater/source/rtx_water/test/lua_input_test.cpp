// GPL-2.0. R19 regression for source/rtx_water/lua_input.h: the polygons and texture paths
// RTXWaterNative accepts from Lua. Standard C++ only:
//   cl /EHsc /std:c++17 /W4 /WX /UNDEBUG source/rtx_water/test/lua_input_test.cpp
#include <cassert>
#include <iostream>
#include <limits>
#include "../lua_input.h"

using rtxwater_input::GameRelativePath;
using rtxwater_input::UsablePolygon;

int main() {
    // F-01: SetSurface read poly[n] past a polygon of odd length (seven floats read an eighth).
    assert(UsablePolygon({0, 0, 1, 0, 1, 1}));
    assert(UsablePolygon({0, 0, 64, 0, 64, 64, 0, 64}));
    assert(!UsablePolygon({}));
    assert(!UsablePolygon({0, 0, 1, 0}));
    assert(!UsablePolygon({0, 0, 1, 0, 1, 1, 0}));
    assert(!UsablePolygon({0, 0, 1, 0, 1, 1, 0, 1, 5}));
    assert(!UsablePolygon({0, 0, 1, 0, std::numeric_limits<float>::quiet_NaN(), 1}));
    assert(!UsablePolygon({0, 0, std::numeric_limits<float>::infinity(), 0, 1, 1}));
    assert(!UsablePolygon({0, 0, 1, -std::numeric_limits<float>::infinity(), 1, 1}));

    // SetMaterial's textures stay below the game folder, as the shipped presets name them.
    for (const char* good : {"rtx-remix/mods/rtx_water/textures/murky_diffuse_cccc36ad44.t.rtex.dds",
                             "rtx-remix\\mods\\rtx_water\\textures\\ripple_normal_def6fb397e.n.rtex.dds", "x.dds", "a/./b.dds"})
        assert(GameRelativePath(good));
    for (const char* bad : {"", "\\\\host\\share\\x.dds", "//host/share/x.dds", "\\\\?\\C:\\x.dds", "C:\\x.dds", "C:x.dds",
                            "/x.dds", "\\x.dds", "../x.dds", "a/../../x.dds", "x.dds:stream", "a/b./x.dds", "a/b /x.dds",
                            "a/nul/x.dds", "COM1.dds", "a\tb.dds"})
        assert(!GameRelativePath(bad));
    assert(!GameRelativePath(std::string(1025, 'a')));

    std::cout << "PASS rtxwater lua input: polygons of an even length of at least six finite numbers, texture paths below "
                 "the game folder\n";
    return 0;
}
