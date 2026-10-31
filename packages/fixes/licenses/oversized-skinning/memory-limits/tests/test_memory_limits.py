"""Compile the production compatibility methods in a stand-alone fake SDK harness."""
import argparse
from pathlib import Path
import subprocess


def function(text, signature):
    start = text.index(signature)
    brace = text.index('{', start)
    depth = 1
    end = brace + 1
    while depth:
        depth += (text[end] == '{') - (text[end] == '}')
        end += 1
    return text[start:end]


HARNESS = r'''
#include <atomic>
#include <cstddef>
#include <cstring>
#include <limits>
#include <thread>
#include <vector>
#include <cstdio>
using std::size_t;
static std::atomic<int> messages{0};
static bool messageIsExplicit = false;
void Msg(const char* text) {
    messageIsExplicit = std::strstr(text, "no-op") && std::strstr(text, "no limits were changed");
    ++messages;
}
struct FakeRemix {
    int writes = 0;
    void SetConfigVariable(const char*, const char*) { ++writes; }
};
namespace GarrysMod { namespace Lua {
enum class Type { Number };
class ILuaBase {
public:
    bool number[2] = {true, true};
    double values[2] = {256, 1024};
    int errors = 0;
    bool result = false;
    bool IsType(int i, Type) { return number[i - 1]; }
    void ThrowError(const char*) { ++errors; }
    double GetNumber(int i) { return values[i - 1]; }
    void PushBool(bool value) { result = value; }
};
}}
using namespace GarrysMod::Lua;
#define LUA_FUNCTION(name) int name(ILuaBase* LUA)
namespace RemixAPI {
class ResourceManager {
public:
    FakeRemix* m_remixInterface;
    explicit ResourceManager(FakeRemix* api = nullptr) : m_remixInterface(api) {}
    void SetMemoryLimits(size_t maxCacheSize, size_t maxVRAM);
};
class RemixAPI {
public:
    static RemixAPI& Instance() { static RemixAPI api; return api; }
    ResourceManager& GetResourceManager() { return manager; }
    ResourceManager manager;
};
@METHOD@
@BINDING@
}
int main() {
    FakeRemix api;
    RemixAPI::ResourceManager live(&api), disconnected;
    std::vector<std::thread> workers;
    for (int i = 0; i < 8; ++i) {
        workers.emplace_back([&] {
            for (int n = 0; n < 1000; ++n) live.SetMemoryLimits(256, 1024);
        });
    }
    for (auto& worker : workers) worker.join();
    disconnected.SetMemoryLimits(0, std::numeric_limits<size_t>::max());
    ILuaBase lua;
    if (RemixAPI::RemixResource_SetMemoryLimits(&lua) != 1 || !lua.result || lua.errors) return 1;
    for (int i = 0; i < 2; ++i) {
        ILuaBase invalid;
        invalid.number[i] = false;
        if (RemixAPI::RemixResource_SetMemoryLimits(&invalid) != 0 || invalid.errors != 1 || invalid.result) return 2;
    }
    if (api.writes || messages != 1 || !messageIsExplicit) return 3;
    std::puts("PASS: 8000 concurrent calls, disconnected API, Lua compatibility; one log, zero config writes");
}
'''


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--source', type=Path, default=Path(__file__).resolve().parents[1])
    parser.add_argument('--out', type=Path, required=True, help='scratch folder under the aggregate worktree out/')
    args = parser.parse_args()
    native = args.source / 'source'
    module = (native / 'module.cpp').read_text()
    if 'SetMemoryLimits(' in module:
        raise RuntimeError('module startup still calls SetMemoryLimits')
    for p in (native / 'remixapi').glob('*.cpp'):
        if 'rtx.resourceLimits.' in p.read_text():
            raise RuntimeError(f'{p}: unsupported runtime keys remain')
    method = function((native / 'remixapi/remixapi.cpp').read_text(), 'void ResourceManager::SetMemoryLimits(')
    binding = function((native / 'remixapi/resource_lua_bindings.cpp').read_text(), 'LUA_FUNCTION(RemixResource_SetMemoryLimits)')
    args.out.mkdir(parents=True, exist_ok=True)
    source = args.out.resolve() / 'memory_limits_test.cpp'
    source.write_text(HARNESS.replace('@METHOD@', method).replace('@BINDING@', binding))
    exe = args.out.resolve() / 'memory_limits_test.exe'
    subprocess.run(['cl.exe', '/nologo', '/EHsc', '/std:c++17', '/W4', '/WX', str(source),
                    '/Fo' + str(source.with_suffix('.obj')), '/Fe' + str(exe)], check=True)
    subprocess.run([str(exe)], check=True)


if __name__ == '__main__':
    main()
