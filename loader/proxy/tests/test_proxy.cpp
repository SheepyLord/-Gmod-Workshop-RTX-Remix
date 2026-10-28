#include <windows.h>
#include <mmsystem.h>
#include "nl_test.h"
#include <algorithm>
#include <cstdio>
#include <cwchar>
#include <filesystem>
#include <fstream>
#include <iterator>
#include <string>
#include <vector>

namespace {
namespace fs = std::filesystem;

struct Module {
  HMODULE handle{};
  explicit Module(const fs::path& path) : handle(LoadLibraryW(path.c_str())) {}
  ~Module() { if (handle) FreeLibrary(handle); }
  Module(const Module&) = delete;
  Module& operator=(const Module&) = delete;
};

fs::path system_winmm() {
  wchar_t path[32768]{};
  const auto size = GetSystemDirectoryW(path, 32768);
  REQUIRE(size && size < 32768);
  return fs::path(path) / L"winmm.dll";
}

std::string read(const fs::path& path) {
  std::ifstream stream(path, std::ios::binary);
  return {std::istreambuf_iterator<char>(stream), std::istreambuf_iterator<char>()};
}

struct TempGame {
  fs::path root;
  fs::path host;
  fs::path log;
  fs::path marker;
  TempGame(const wchar_t* name = L"gmod.exe", const wchar_t* directory = L"bin\\win64") {
    static unsigned counter = 0;
    // Keep generated executables beside the build, inside the user's output root.
    root = fs::path(NL_PROXY_SCRATCH_ROOT) / (L"nl-proxy-测试-" + std::to_wstring(GetCurrentProcessId()) + L"-" + std::to_wstring(++counter));
    REQUIRE(!fs::exists(root));
    host = root / directory / name;
    log = root / L"native-loader/logs/loader.log";
    marker = root / L"host-main.txt";
    try {
      fs::create_directories(host.parent_path());
      fs::copy_file(fs::path(NL_PROXY_HOST_PATH), host);
      fs::copy_file(fs::path(NL_PROXY_DLL_PATH), host.parent_path() / L"winmm.dll");
    } catch (...) {
      std::error_code error;
      fs::remove_all(root, error);
      throw;
    }
  }
  ~TempGame() {
    std::error_code error;
    fs::remove_all(root, error);
  }
  TempGame(const TempGame&) = delete;
  TempGame& operator=(const TempGame&) = delete;

  DWORD run(const std::wstring& arguments = L"", const std::wstring& disable_env = L"") {
    std::vector<std::wstring> variables;
    wchar_t* inherited = GetEnvironmentStringsW();
    REQUIRE(inherited != nullptr);
    for (const wchar_t* value = inherited; *value; value += std::wcslen(value) + 1) {
      if (_wcsnicmp(value, L"NATIVE_LOADER_DISABLE=", 22) != 0) variables.emplace_back(value);
    }
    FreeEnvironmentStringsW(inherited);
    if (!disable_env.empty()) variables.push_back(L"NATIVE_LOADER_DISABLE=" + disable_env);
    std::sort(variables.begin(), variables.end(), [](const auto& a, const auto& b) { return _wcsicmp(a.c_str(), b.c_str()) < 0; });
    std::vector<wchar_t> block;
    for (const auto& variable : variables) { block.insert(block.end(), variable.begin(), variable.end()); block.push_back(0); }
    block.push_back(0);
    std::wstring command = L"\"" + host.wstring() + L"\" \"" + marker.wstring() + L"\" \"" + log.wstring() + L"\" " + arguments;
    STARTUPINFOW startup{sizeof(startup)};
    PROCESS_INFORMATION process{};
    REQUIRE(CreateProcessW(host.c_str(), command.data(), nullptr, nullptr, FALSE, CREATE_NO_WINDOW | CREATE_UNICODE_ENVIRONMENT,
                           block.data(), root.c_str(), &startup, &process));
    CloseHandle(process.hThread);
    const DWORD wait = WaitForSingleObject(process.hProcess, 15000);
    if (wait != WAIT_OBJECT_0) TerminateProcess(process.hProcess, 99);
    DWORD exit_code{};
    const bool got_exit_code = GetExitCodeProcess(process.hProcess, &exit_code) != FALSE;
    CloseHandle(process.hProcess);
    REQUIRE(wait == WAIT_OBJECT_0);
    REQUIRE(got_exit_code);
    if (exit_code || !fs::exists(marker)) std::printf("host exited 0x%08lx; marker=%d; log=%s\n", exit_code,
        fs::exists(marker), fs::exists(log) ? read(log).c_str() : "<none>");
    REQUIRE(fs::exists(marker));
    return exit_code;
  }
};

unsigned long long number(const std::string& text, const std::string& key) {
  const auto pos = text.find(key + "=");
  REQUIRE(pos != std::string::npos);
  return std::stoull(text.substr(pos + key.size() + 1));
}
}  // namespace

TEST_CASE("proxy exports every system name and ordinal including ordinal-only entries") {
  Module system(system_winmm());
  Module proxy{fs::path(NL_PROXY_DLL_PATH)};
  REQUIRE(system.handle && proxy.handle && system.handle != proxy.handle);
  const auto* base = reinterpret_cast<const unsigned char*>(system.handle);
  const auto* dos = reinterpret_cast<const IMAGE_DOS_HEADER*>(base);
  const auto* nt = reinterpret_cast<const IMAGE_NT_HEADERS64*>(base + dos->e_lfanew);
  const auto* exports = reinterpret_cast<const IMAGE_EXPORT_DIRECTORY*>(base + nt->OptionalHeader.DataDirectory[IMAGE_DIRECTORY_ENTRY_EXPORT].VirtualAddress);
  const auto* functions = reinterpret_cast<const DWORD*>(base + exports->AddressOfFunctions);
  const auto* names = reinterpret_cast<const DWORD*>(base + exports->AddressOfNames);
  const auto* indices = reinterpret_cast<const WORD*>(base + exports->AddressOfNameOrdinals);
  unsigned count = 0;
  for (DWORD i = 0; i < exports->NumberOfFunctions; ++i) {
    if (!functions[i]) continue;
    ++count;
    CHECK(GetProcAddress(proxy.handle, MAKEINTRESOURCEA(exports->Base + i)) != nullptr);
  }
  for (DWORD i = 0; i < exports->NumberOfNames; ++i) {
    const auto by_name = GetProcAddress(proxy.handle, reinterpret_cast<const char*>(base + names[i]));
    REQUIRE(by_name != nullptr);
    CHECK(by_name == GetProcAddress(proxy.handle, MAKEINTRESOURCEA(exports->Base + indices[i])));
  }
  std::printf("covered %u system ordinals and %lu names\n", count, exports->NumberOfNames);
}

TEST_CASE("forwarded multimedia calls reach the separate system module") {
  Module system(system_winmm());
  Module proxy{fs::path(NL_PROXY_DLL_PATH)};
  REQUIRE(system.handle && proxy.handle && system.handle != proxy.handle);
  const auto proxy_time = reinterpret_cast<DWORD(WINAPI*)()>(GetProcAddress(proxy.handle, "timeGetTime"));
  const auto system_time = reinterpret_cast<DWORD(WINAPI*)()>(GetProcAddress(system.handle, "timeGetTime"));
  const auto begin = reinterpret_cast<MMRESULT(WINAPI*)(UINT)>(GetProcAddress(proxy.handle, "timeBeginPeriod"));
  const auto end = reinterpret_cast<MMRESULT(WINAPI*)(UINT)>(GetProcAddress(proxy.handle, "timeEndPeriod"));
  const auto proxy_devices = reinterpret_cast<UINT(WINAPI*)()>(GetProcAddress(proxy.handle, "waveOutGetNumDevs"));
  const auto system_devices = reinterpret_cast<UINT(WINAPI*)()>(GetProcAddress(system.handle, "waveOutGetNumDevs"));
  const auto proxy_version = reinterpret_cast<UINT(WINAPI*)()>(GetProcAddress(proxy.handle, "mmsystemGetVersion"));
  const auto system_version = reinterpret_cast<UINT(WINAPI*)()>(GetProcAddress(system.handle, "mmsystemGetVersion"));
  REQUIRE(proxy_time && system_time && begin && end && proxy_devices && system_devices && proxy_version && system_version);
  const DWORD before = system_time();
  const DWORD through_proxy = proxy_time();
  const DWORD after = system_time();
  CHECK(through_proxy - before <= after - before);
  CHECK(begin(1) == TIMERR_NOERROR);
  CHECK(end(1) == TIMERR_NOERROR);
  CHECK(proxy_devices() == system_devices());
  CHECK(proxy_version() == system_version());
}

TEST_CASE("entry hook logs before main and restores the executable entry point") {
  TempGame game;
  REQUIRE(game.run() == 0);
  REQUIRE(fs::exists(game.log));
  const auto log = read(game.log);
  const auto marker = read(game.marker);
  CHECK(number(marker, "log_present_at_main") == 1);
  CHECK(number(log, "startup_filetime") <= number(marker, "host_main_filetime"));
  CHECK(log.find("phase=exe_entry_point\nentry_point_restored=1") != std::string::npos);
  CHECK(log.find("module.engine.dll=0\nmodule.shaderapidx9.dll=0\nmodule.d3d9.dll=0") != std::string::npos);
  CHECK(number(log, "exports.resolved") == number(log, "exports.total"));
  CHECK(log.find("off_switch.command_line=0\noff_switch.environment=0\noff_switch.disable_file=0") != std::string::npos);
  CHECK(log.find("startup.complete=1") != std::string::npos);
}

TEST_CASE("command line off switch leaves the host a pure pass through") {
  TempGame game;
  CHECK(game.run(L"\"-nonativeloader\"") == 0);
  CHECK(!fs::exists(game.root / L"native-loader"));
  CHECK(number(read(game.marker), "log_present_at_main") == 0);
}

TEST_CASE("environment off switch leaves the host a pure pass through") {
  TempGame game;
  CHECK(game.run(L"", L"1") == 0);
  CHECK(!fs::exists(game.root / L"native-loader"));
}

TEST_CASE("disable file off switch leaves the host a pure pass through") {
  TempGame game;
  fs::create_directory(game.root / L"native-loader");
  std::ofstream(game.root / L"native-loader/disable") << "test";
  CHECK(game.run() == 0);
  CHECK(!fs::exists(game.log));
  CHECK(!fs::exists(game.log.parent_path()));
}

TEST_CASE("another host name and the x86 bin path stay inert") {
  TempGame tool(L"hlmv.exe");
  CHECK(tool.run() == 0);
  CHECK(!fs::exists(tool.root / L"native-loader"));
  TempGame x86_path(L"gmod.exe", L"bin");
  CHECK(x86_path.run() == 0);
  CHECK(!fs::exists(x86_path.root / L"native-loader"));
}

TEST_CASE("logging failures cannot prevent the host from reaching main") {
  TempGame game;
  std::ofstream(game.root / L"native-loader") << "block directory creation";
  CHECK(game.run() == 0);
  CHECK(!fs::exists(game.log));
  CHECK(number(read(game.marker), "log_present_at_main") == 0);
}

TEST_CASE("Chromium child roles never hook or write logs") {
  for (const auto* arguments : {L"--type=renderer", L"--type=gpu-process", L"--type=utility", L"--type renderer"}) {
    TempGame game;
    CHECK(game.run(arguments) == 0);
    CHECK(!fs::exists(game.root / L"native-loader"));
    CHECK(number(read(game.marker), "log_present_at_main") == 0);
  }
}

TEST_CASE("log rotation keeps the current log and five previous logs") {
  TempGame game;
  for (int i = 0; i < 8; ++i) REQUIRE(game.run() == 0);
  CHECK(fs::exists(game.log));
  for (int i = 1; i <= 5; ++i) CHECK(fs::exists(fs::path(game.log.wstring() + L"." + std::to_wstring(i))));
  CHECK(!fs::exists(fs::path(game.log.wstring() + L".6")));
  CHECK(std::distance(fs::directory_iterator(game.log.parent_path()), fs::directory_iterator{}) == 6);
}
