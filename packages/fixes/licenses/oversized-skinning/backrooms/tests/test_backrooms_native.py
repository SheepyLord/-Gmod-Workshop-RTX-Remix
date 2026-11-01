"""Compile production Backrooms native code in offline Windows/fake-filesystem harnesses."""
import argparse
from pathlib import Path
import subprocess


def function(text, signature):
    start = text.index(signature)
    brace = text.index('{', start)
    depth, end = 1, brace + 1
    while depth:
        depth += (text[end] == '{') - (text[end] == '}')
        end += 1
    return text[start:end]


COMMON = r'''
#define WIN32_LEAN_AND_MEAN
#define NOMINMAX
#include <Windows.h>
#include <cassert>
#include <cmath>
#include <cstdint>
#include <cstdio>
#include <cstring>
#include <limits>
#include <string>
#include <vector>
#include <unordered_map>
#include <unordered_set>
#include <chrono>
#include <thread>
#include <mutex>
#include <cctype>
#include <atomic>
static int reads = 0;
static BOOL TestReadProcessMemory(HANDLE process, const void* from, void* to, SIZE_T bytes, SIZE_T* count) {
    ++reads;
    return ReadProcessMemory(process, from, to, bytes, count);
}
#define ReadProcessMemory TestReadProcessMemory
#define HWSKIN_DBG(...) ((void)0)
#define HWSKIN_ERROR(...) ((void)0)
#define Msg(...) ((void)0)
#define Warning(...) ((void)0)
'''

MODEL = r'''
struct ResolvedFileLocation { std::string filename; const char* pathID = nullptr; };
struct OptimizedModelFileHeader_t { int checkSum; };
struct File { int checksum; bool shortRead; };
using FileHandle_t = File*;
using OpenExFunc = FileHandle_t(*)(void*, const char*, const char*, int, const char*, void*);
static std::unordered_map<std::string, File> files;
static std::unordered_map<std::string, File> allPathsFiles;
static std::atomic<int> swAttempts{0};
static std::string Key(std::string name) {
    for (char& c : name) c = c == '\\' ? '/' : static_cast<char>(std::tolower(static_cast<unsigned char>(c)));
    return name;
}
static FileHandle_t Open(void*, const char* name, const char*, int, const char* pathID, void*) {
    const std::string key = Key(name);
    if (key.find(".sw.vtx") != std::string::npos) ++swAttempts;
    if (!pathID) {
        const auto extra = allPathsFiles.find(key);
        if (extra != allPathsFiles.end()) return new File(extra->second);
    }
    const auto it = files.find(key);
    return it == files.end() ? nullptr : new File(it->second);
}
class IFileSystem {
public:
    size_t Read(void* target, size_t bytes, File* file) {
        if (file->shortRead) return 0;
        static_cast<OptimizedModelFileHeader_t*>(target)->checkSum = file->checksum;
        return bytes;
    }
    void Close(File* file) { delete file; }
};
static bool ResolveCompatibilityFileLocation(const char*, ResolvedFileLocation&) { return false; }
struct ConVar { bool GetBool() const { return false; } };
namespace GlobalConvars { static ConVar* r_hwskin_debug = nullptr; }
static std::vector<std::string> g_gameSearchPaths;
constexpr const char* kSoftwareVtxExtension = ".sw.vtx";
@CACHE@
int GetVtxFileChecksum(void*, const char*, const char*, void*, bool* missing = nullptr);
@CHECKSUM@
@RESOLVER@
int main() {
    IFileSystem fs;
    void* open = reinterpret_cast<void*>(&Open);
    ResolvedFileLocation out;
    auto resolve = [&](const char* path, const char* mount = "GAME") {
        return ResolveMatchingSoftwareVtxPath(&fs, path, mount, open, out);
    };
    files["models/a.dx90.vtx"] = {42, false};
    assert(!resolve("models/a.dx90.vtx"));
    assert(swAttempts == 1 && g_missingSoftwareVtx.size() == 1);
    assert(!resolve("MODELS\\A.DX90.VTX", "gAmE"));
    assert(swAttempts == 1 && g_missingSoftwareVtxHits == 1);
    allPathsFiles["models/a.sw.vtx"] = {42, false};
    assert(resolve("models/a.dx90.vtx", nullptr)); // a GAME-only miss cannot hide another path ID
    assert(swAttempts == 2);
    allPathsFiles.clear();
    assert(!resolve("models/a.dx90.vtx", "MOD"));
    assert(swAttempts == 3); // specific mounts do not consult the GAME miss cache
    ClearMissingSoftwareVtx();
    assert(g_missingSoftwareVtx.empty() && !g_missingSoftwareVtxHits && !g_missingSoftwareVtxLookupNs);
    files["models/a.sw.vtx"] = {42, false};
    assert(resolve("models/a.dx90.vtx") && out.filename == "models/a.sw.vtx");
    assert(g_missingSoftwareVtx.empty());
    g_gameSearchPaths = {"alternate"};
    files["alternate/models/a.sw.vtx"] = {42, false};
    for (File bad : {File{7, false}, File{0, false}, File{0, true}}) {
        files["models/a.sw.vtx"] = bad;
        assert(resolve("models/a.dx90.vtx"));
        assert(out.filename == "alternate\\models/a.sw.vtx" && out.pathID == nullptr);
        assert(g_missingSoftwareVtx.empty());
    }
    files["models/a.dx90.vtx"] = {0, true};
    assert(!resolve("models/a.dx90.vtx") && g_missingSoftwareVtx.empty());
    assert(!resolve("models/a.mdl"));
    assert(!ResolveMatchingSoftwareVtxPath(nullptr, "a.dx90.vtx", "GAME", open, out));
    files["models/a.dx90.vtx"] = {42, false};
    files.erase("models/a.sw.vtx");
    files.erase("alternate/models/a.sw.vtx");
    assert(!resolve("models/a.dx90.vtx"));
    const int before = swAttempts;
    const uint64_t hits = g_missingSoftwareVtxHits;
    std::vector<std::thread> threads;
    for (int i = 0; i < 8; ++i) threads.emplace_back([&] {
        for (int n = 0; n < 1000; ++n) {
            ResolvedFileLocation local;
            assert(!ResolveMatchingSoftwareVtxPath(&fs, "models/a.dx90.vtx", "GAME", open, local));
        }
    });
    for (auto& thread : threads) thread.join();
    assert(swAttempts == before && g_missingSoftwareVtxHits == hits + 8000);
    ClearMissingSoftwareVtx();
    for (int i = 0; i < 65536; ++i) g_missingSoftwareVtx.emplace("cap" + std::to_string(i));
    assert(!resolve("models/a.dx90.vtx") && g_missingSoftwareVtx.size() == 65536);
    ClearMissingSoftwareVtx();
    assert(TestReadProcessMemory(GetCurrentProcess(), &reads, &reads, sizeof(reads), nullptr));
    std::puts("PASS: SW VTX misses, path aliases, specific mounts, malformed/zero checksums, alternate mounts, 8000 concurrent hits, bounded cache and reset");
}
'''

LAZY = r'''
using matrix3x4_t = float[3][4];
static bool HardwareSkinningDebugEnabled() { return false; }
@RESOLVER@
using OriginalFn = __int64(*)(void*, void*, int, __int64, void*, void*, int, unsigned int, void*);
static __int64 Original(void*, void*, int, __int64, void*, void*, int, unsigned int, void*);
static OriginalFn R_StudioRenderFinal_trampoline() { return Original; }
#define Define_method_Hook(ret, name, self, ...) ret name(self _this, __VA_ARGS__)
@HOOK@
static int mode = 0;
static bool expectValid = true;
static void* inner = nullptr;
static __int64 Draw(void* renderable) {
    return R_StudioRenderFinal(reinterpret_cast<void*>(1), reinterpret_cast<void*>(2), 3, 4,
        renderable, reinterpret_cast<void*>(6), 7, 8, reinterpret_cast<void*>(9));
}
static __int64 Original(void* self, void* context, int skin, __int64 body, void* entity,
    void* materials, int flags, unsigned int mask, void* colors) {
    assert(self == reinterpret_cast<void*>(1) && context == reinterpret_cast<void*>(2));
    assert(skin == 3 && body == 4 && entity && materials == reinterpret_cast<void*>(6));
    assert(flags == 7 && mask == 8 && colors == reinterpret_cast<void*>(9));
    assert(g_bInRenderFinal);
    if (mode == 1) {
        const int before = reads;
        assert(ResolveModelToWorld() == expectValid);
        assert(ResolveModelToWorld() == expectValid);
        assert(reads == before + 1);
    } else if (mode == 2 || mode == 3) {
        const int outerMode = mode;
        if (outerMode == 2) assert(ResolveModelToWorld() && g_modelToWorld[0][3] == 10);
        mode = 1;
        assert(Draw(inner) == 1234);
        mode = outerMode;
        assert(ResolveModelToWorld() && g_modelToWorld[0][3] == 10);
    } else if (mode == 4) {
        assert(ResolveModelToWorld());
        RaiseException(0xe0420001, 0, 0, nullptr);
    }
    return 1234;
}
int main() {
    auto* outer = static_cast<unsigned char*>(VirtualAlloc(nullptr, 4096, MEM_COMMIT | MEM_RESERVE, PAGE_READWRITE));
    inner = VirtualAlloc(nullptr, 4096, MEM_COMMIT | MEM_RESERVE, PAGE_READWRITE);
    auto* denied = VirtualAlloc(nullptr, 4096, MEM_COMMIT | MEM_RESERVE, PAGE_NOACCESS);
    assert(outer && inner && denied);
    auto* matrix = reinterpret_cast<matrix3x4_t*>(outer + 1008);
    (*matrix)[0][0] = (*matrix)[1][1] = (*matrix)[2][2] = 1;
    (*matrix)[0][3] = 10;
    std::memcpy(static_cast<unsigned char*>(inner) + 1008, matrix, sizeof(*matrix));
    g_modelToWorld[0][3] = 99;
    assert(Draw(outer) == 1234 && reads == 0); // the ordinary draw never needs the transform
    mode = 1;
    assert(Draw(outer) == 1234 && reads == 1);
    assert(!g_bInRenderFinal && !g_bHaveModelToWorld && !g_pPendingModelToWorldRenderable && g_modelToWorld[0][3] == 99);
    mode = 2;
    reinterpret_cast<float*>(static_cast<unsigned char*>(inner) + 1008)[3] = 20;
    assert(Draw(outer) == 1234 && reads == 3); // preserve a resolved outer transform
    mode = 3;
    assert(Draw(outer) == 1234 && reads == 5); // preserve an unresolved outer renderable
    mode = 4;
    assert(Draw(outer) == 0 && !g_bInRenderFinal && g_modelToWorld[0][3] == 99);
    mode = 1;
    expectValid = false;
    assert(Draw(denied) == 1234);
    for (int r = 0; r < 3; ++r) for (int c = 0; c < 4; ++c) {
        const float old = (*matrix)[r][c];
        (*matrix)[r][c] = std::numeric_limits<float>::quiet_NaN();
        assert(Draw(outer) == 1234);
        (*matrix)[r][c] = old;
    }
    (*matrix)[0][0] = 2;
    assert(Draw(outer) == 1234);
    (*matrix)[0][0] = 1;
    (*matrix)[0][3] = 100000;
    assert(Draw(outer) == 1234);
    g_pPendingModelToWorldRenderable = nullptr;
    assert(!ResolveModelToWorld());
    VirtualFree(outer, 0, MEM_RELEASE);
    VirtualFree(inner, 0, MEM_RELEASE);
    VirtualFree(denied, 0, MEM_RELEASE);
    std::puts("PASS: lazy read, once per renderable (including failed reads), finite/range checks, nine draw arguments, nested resolved/pending transforms and SEH restoration");
}
'''

VIS = r'''
#include "vis_pas_policy.h"
struct ConVar { bool value = false; bool GetBool() const { return value; } };
static ConVar* cv_vis_pas = nullptr;
struct DynLibInfo { void* baseAddress; size_t memorySize; };
static unsigned char* fakeModule = nullptr;
static bool duplicate = false, found = true;
static HMODULE FakeGetModuleHandleA(const char*) { return reinterpret_cast<HMODULE>(fakeModule); }
#define GetModuleHandleA FakeGetModuleHandleA
static bool GetLibraryInfo(HMODULE, DynLibInfo& info) { info = {fakeModule, 4096}; return true; }
static void* ScanSign(HMODULE, const char*, size_t, const void* start = nullptr) {
    return found && (!start || duplicate) ? fakeModule + 64 : nullptr;
}
class IVEngineClient {
public:
    const char* map = "maps/first.bsp";
    const char* GetLevelName() { return map; }
};
static IVEngineClient engineClient;
#define VENGINE_CLIENT_INTERFACE_VERSION "fake"
namespace SourceSDK {
class FactoryLoader {
public:
    explicit FactoryLoader(const char*) {}
    template <typename T> T* GetInterface(const char*) { return &engineClient; }
};
}
@ADAPTER@
int main() {
    using VisPAS::Result;
    VisPAS::State policy;
    int identity = 0;
    int rows[] = {20, 21, 22, 23};
    for (int n = 0; n < 1000; ++n) {
        assert(policy.Sync(&identity, "first", 24, 2, rows, false) == Result::Unchanged);
        assert(policy.Sync(&identity, "first", 24, 2, rows, true) == Result::Widened);
        assert(policy.Sync(&identity, "first", 24, 2, rows, true) == Result::Unchanged);
        assert(rows[0] == 21 && rows[2] == 23);
        assert(policy.Sync(&identity, "first", 24, 2, rows, false) == Result::Restored);
        assert(rows[0] == 20 && rows[2] == 22);
    }
    assert(policy.Sync(&identity, "first", 24, 2, rows, true) == Result::Widened);
    rows[0] = 22; // another owner changed a PVS row
    assert(policy.Sync(&identity, "first", 24, 2, rows, false) == Result::OwnershipLost && rows[0] == 22);
    rows[0] = 20;
    assert(policy.Sync(&identity, "first", 24, 2, rows, true) == Result::Widened);
    assert(policy.Sync(&identity, "second", 24, 2, rows, false) == Result::Unchanged && rows[0] == 21);
    rows[0] = 20;
    assert(policy.Sync(&identity, "first", 24, 2, rows, true) == Result::Widened);
    rows[1] = 22; // changed PAS offsets: never restore the previous map's rows
    assert(policy.Sync(&identity, "first", 24, 2, rows, false) == Result::OwnershipLost);
    rows[0] = rows[1] = 20;
    rows[2] = rows[3] = 22;
    assert(policy.Sync(&identity, "first", 24, 2, rows, true) == Result::Unchanged && !policy.Active());
    for (int bad : {-1, 0, 19, 24, INT_MAX}) {
        rows[1] = bad;
        assert(policy.Sync(&identity, "first", 24, 2, rows, true) == Result::Invalid);
    }
    assert(policy.Sync(&identity, "first", 24, 65537, rows, true) == Result::Invalid);
    assert(policy.Sync(&identity, "first", 24, 0, rows, true) == Result::Invalid);
    assert(policy.Sync(&identity, "first", 19, 2, rows, true) == Result::Invalid);
    assert(policy.Sync(&identity, "first", 0x1000001, 2, rows, true) == Result::Invalid);
    std::vector<int> maximum(65536 * 2, 4 + 65536 * 8);
    assert(policy.Sync(&identity, "max", 4 + 65536 * 8 + 1, 65536, maximum.data(), true) == Result::Unchanged);

    fakeModule = static_cast<unsigned char*>(VirtualAlloc(nullptr, 4096, MEM_COMMIT | MEM_RESERVE, PAGE_EXECUTE_READWRITE));
    auto* table = static_cast<int*>(VirtualAlloc(nullptr, 4096, MEM_COMMIT | MEM_RESERVE, PAGE_READWRITE));
    assert(fakeModule && table);
    const int32_t numDisplacement = 256 - (64 + 7), tableDisplacement = 264 - (64 + 20);
    std::memcpy(fakeModule + 66, &numDisplacement, 4);
    std::memcpy(fakeModule + 80, &tableDisplacement, 4);
    *reinterpret_cast<int*>(fakeModule + 256) = 24;
    *reinterpret_cast<int**>(fakeModule + 264) = table;
    table[0] = 2;
    table[1] = 20; table[2] = 21; table[3] = 22; table[4] = 23;
    ConVar cv;
    cv_vis_pas = &cv;
    ResolveVisData();
    assert(g_pNumVisibility && g_ppMapVis);
    ShutdownCullingPatches();
    const int32_t outside = 8192;
    std::memcpy(fakeModule + 66, &outside, 4);
    ResolveVisData();
    assert(!g_ppMapVis); // reject RIP-relative globals outside the module
    std::memcpy(fakeModule + 66, &numDisplacement, 4);
    ResolveVisData();
    reads = 0;
    SyncVisPAS();
    assert(reads == 0 && table[1] == 20);
    cv.value = true;
    SyncVisPAS();
    assert(table[1] == 21 && g_visSaved.Active());
    cv.value = false;
    SyncVisPAS();
    assert(table[1] == 20 && !g_visSaved.Active());
    cv.value = true;
    SyncVisPAS();
    ShutdownCullingPatches();
    assert(table[1] == 20 && !g_ppMapVis && !g_visSaved.Active());
    duplicate = true;
    ResolveVisData();
    assert(!g_ppMapVis);
    duplicate = false;
    found = false;
    ResolveVisData();
    assert(!g_ppMapVis);
    found = true;
    DWORD old = 0;
    assert(VirtualProtect(fakeModule, 4096, PAGE_READWRITE, &old));
    ResolveVisData();
    assert(!g_ppMapVis); // refuse a signature outside executable memory
    assert(VirtualProtect(fakeModule, 4096, PAGE_EXECUTE_READWRITE, &old));
    ResolveVisData();
    assert(g_ppMapVis);
    *reinterpret_cast<int*>(fakeModule + 256) = 0x1000001;
    SyncVisPAS();
    assert(table[1] == 20 && !g_visSaved.Active());
    *reinterpret_cast<int*>(fakeModule + 256) = 24;
    assert(VirtualProtect(table, 4096, PAGE_READONLY, &old));
    SyncVisPAS();
    assert(table[1] == 20 && !g_visSaved.Active());
    assert(VirtualProtect(table, 4096, PAGE_NOACCESS, &old));
    SyncVisPAS(); // inaccessible header is rejected without an access violation
    assert(VirtualProtect(table, 4096, PAGE_READWRITE, &old));
    SyncVisPAS();
    assert(g_visSaved.Active());
    engineClient.map = "maps/second.bsp";
    cv.value = false;
    SyncVisPAS();
    assert(table[1] == 21 && !g_visSaved.Active()); // allocation address was reused
    cv.value = true;
    table[1] = 20;
    SyncVisPAS();
    assert(g_visSaved.Active());
    VirtualFree(table, 0, MEM_RELEASE);
    ShutdownCullingPatches(); // a map already freed its table
    assert(!g_visSaved.Active());
    VirtualFree(fakeModule, 0, MEM_RELEASE);
    std::puts("PASS: PAS bounds/max clusters, 1000 toggles, ownership, map/allocation changes, signature guards, default-off zero reads, read-only/inaccessible/freed tables and module-close restoration");
}
'''


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--source', type=Path, default=Path(__file__).resolve().parents[1])
    parser.add_argument('--out', type=Path, required=True)
    args = parser.parse_args()
    args.out.mkdir(parents=True, exist_ok=True)
    native = args.source / 'source'
    model = (native / 'modelload_fixes.cpp').read_text()
    skin = (native / 'HardwareSkinningHooks.cpp').read_text()
    vis = (native / 'culling_patches.cpp').read_text()
    assert 'ClearMissingSoftwareVtx();' in function(model, 'void ModelLoadHooks::Shutdown()')
    assert 'ShutdownCullingPatches();' in (native / 'module.cpp').read_text()
    assert 'SyncVisPAS();' in function(vis, 'void SyncCullingPatches()')
    cases = {
        'model_misses': MODEL.replace('@CACHE@', model[model.index('    std::mutex g_missingSoftwareVtxMutex;'):model.index('    std::string g_hl2MiscCompatibilityRoot')])
            .replace('@CHECKSUM@', function(model, 'int GetVtxFileChecksum(void* fs, const char* filename, const char* pathID, void* openFunc,\n    bool* missing)'))
            .replace('@RESOLVER@', function(model, 'bool ResolveMatchingSoftwareVtxPath(void* fs, const char* hardwareFilename,\n    const char* pathID, void* openFunc, ResolvedFileLocation& softwareFile)')),
        'lazy_transform': LAZY.replace('@RESOLVER@', skin[skin.index('static bool g_bInRenderFinal'):skin.index('// D3D9 device for setting bone transforms')])
            .replace('@HOOK@', function(skin, 'Define_method_Hook(__int64, R_StudioRenderFinal, void*,')),
        'vis_pas': VIS.replace('@ADAPTER@', vis[vis.index('struct dvis_t {'):vis.index('// ===================================================================\n//      APPLY INITIAL PATCHES')]),
    }
    for name, case in cases.items():
        source = args.out.resolve() / (name + '.cpp')
        exe = source.with_suffix('.exe')
        source.write_text(COMMON + case)
        subprocess.run(['cl.exe', '/nologo', '/EHsc', '/std:c++17', '/W4', '/WX', '/UNDEBUG',
                        '/I' + str(native.resolve()), str(source), '/Fo' + str(source.with_suffix('.obj')),
                        '/Fe' + str(exe)], check=True)
        subprocess.run([str(exe)], check=True)


if __name__ == '__main__':
    main()
