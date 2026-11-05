// GPL-2.0. R19 regression for source/lua_path_policy.h: the paths the module's Lua functions accept.
// Compiles alone (no SDK): cl /EHsc /std:c++17 /W4 /WX /UNDEBUG tests/lua_path_policy_test.cpp
#include <cassert>
#include <iostream>
#include <string>
#include "../source/lua_path_policy.h"

using namespace LuaPathPolicy;
namespace fs = std::filesystem;

static void RelativePaths() {
    std::string why;
    for (const char* good : {"models/props_c17/furniture_metal001a", "materials\\maps\\gm_construct\\water.vmt",
                             "rtx-remix/mods/rtx_water/textures/ripple_normal.n.rtex.dds", "a/./b", "a//b", ".",
                             "x.dds", "tex/\xE8\xBA\xAB\xE4\xBD\x93.png", "console/net", "com10", "lpt", "..x", "x..y"})
        assert(RelativePath(good, &why) && "a plain relative path is accepted");
    struct Bad { const char* path; const char* reason; };
    for (const Bad& bad : {Bad{"", "empty"}, Bad{"\\\\host\\share\\x.dds", "root"}, Bad{"//host/share/x.dds", "root"},
                           Bad{"\\\\?\\C:\\Windows\\x", "root"}, Bad{"\\\\.\\pipe\\x", "root"}, Bad{"/etc/x", "root"},
                           Bad{"\\Windows\\x", "root"}, Bad{"C:\\Windows\\x", "':'"}, Bad{"C:x", "':'"},
                           Bad{"x.dds:stream", "':'"}, Bad{"a/../../x", "\"..\""}, Bad{"..", "\"..\""},
                           Bad{"a\\..\\b", "\"..\""}, Bad{"a/b./c", "ends with"}, Bad{"a/b /c", "ends with"},
                           Bad{"...", "ends with"}, Bad{"a/con", "device"}, Bad{"NUL.txt", "device"},
                           Bad{"x/COM1.dds", "device"}, Bad{"lpt\xC2\xB9", "device"}, Bad{"aux .png", "device"},
                           Bad{"CONOUT$", "device"}, Bad{"a\tb", "control"}, Bad{"a\x7F", "control"}}) {
        why.clear();
        assert(!RelativePath(bad.path, &why) && "a path that leaves the folder is refused");
        assert(why.find(bad.reason) != std::string::npos && "the refusal says why");
    }
    assert(!RelativePath(std::string(1025, 'a')) && RelativePath(std::string(1024, 'a')));
}

static void LocalDrivePaths() {
    assert(LocalDrivePath("D:\\MMD\\Models\\miku\\miku.pmx"));
    assert(LocalDrivePath("c:/models/\xE6\xB4\x9B/x.pmx"));
    for (const char* bad : {"\\\\nas\\models\\x.pmx", "//nas/models/x.pmx", "\\\\?\\D:\\x.pmx", "D:", "D:x.pmx",
                            "D:\\", "D:\\a\\..\\..\\x.pmx", "D:\\a:b\\x.pmx", "1:\\x.pmx", "relative\\x.pmx",
                            "D:\\CON\\x.pmx", "Server approved"})
        assert(!LocalDrivePath(bad) && "only a file on a local drive");
}

static void ValuesAndOptions() {
    for (const char* value : {"\\\\host\\share", "//host/share", "C:\\x", "c:/x", "D:", "/x", "\\x"})
        assert(AbsolutePathValue(value));
    for (const char* value : {"", "1", "True", "0.5, 0.25", "0xABCDEF, 0x123", "zh-CN", "~gmod_topbr", "a:b", "ab:\\x"})
        assert(!AbsolutePathValue(value));
    for (const char* key : {"rtx.neuralRadianceCache.cudaDllDepsDirectoryPath", "RTX.NSIGHT.GRAPHICSCAPTUREINSTALLPATH",
                            "rtx.nsight.graphicsCaptureOutputDir", "rtx.nsight.graphicsCaptureOutputFile",
                            "rtx.cameraSequence.filePath", "rtx.atmosphere.moonAlbedoTexture",
                            "rtx.atmosphere.starMapTexture", "rtx.captureInstanceStageName", "rtx.baseGameModPathRegex",
                            " rtx.baseGameModRegex "})
        assert(RemixPathOption(key) && "an option naming a file or folder is left to rtx.conf");
    for (const char* key : {"rtx.atmosphere.starMapEnable", "rtx.atmosphere.nubis3InteriorTexture", "rtx.showUI",
                            "rtx.enablePreservePath", "rtx.gmod.fallbackMods", "rtx.debugView.debugViewIdx"})
        assert(!RemixPathOption(key) && "other options stay settable");
}

static void Folders() {
    const fs::path root = L"C:\\Games\\GarrysMod\\rtx-remix\\mods\\~gmod_topbr\\textures";
    std::string why;
    assert(Inside(root, "", &why) == root.lexically_normal());
    assert(Inside(root, ".", &why) == root.lexically_normal());
    const auto sub = Inside(root, "test/run 2", &why);
    assert(sub && *sub == (root / L"test" / L"run 2").lexically_normal());
    assert(Inside(root, "a\\.\\b//c", &why) == (root / L"a" / L"b" / L"c").lexically_normal());
    for (const char* bad : {"..", "../x", "a/../../..", "\\\\host\\share", "//host/share", "\\\\?\\C:\\x", "C:\\x",
                            "D:x", "/x", "x:y", "nul", "a/b."}) {
        why.clear();
        assert(!Inside(root, bad, &why) && !why.empty() && "nothing outside the converter's folder");
    }
    // The recheck compares the normal result with the root, component by component and without case.
    assert(Inside(L"C:\\Games\\GarrysMod\\", "x", &why) == fs::path(L"C:\\Games\\GarrysMod\\x"));
    assert(Inside(L"c:\\games\\garrysmod", "X", &why) == fs::path(L"c:\\games\\garrysmod\\X"));
}

int main() {
    RelativePaths();
    LocalDrivePaths();
    ValuesAndOptions();
    Folders();
    std::cout << "PASS lua path policy: relative game paths (roots, UNC, \\\\?\\, drives, streams, \"..\", "
                 "shortened names, devices, control characters, length), local model files, absolute option values, "
                 "Remix path options and folders inside the converter's own\n";
    return 0;
}
