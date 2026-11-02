#include "observer.h"
#include "bootstrap.h"
#include "exit_report.h"
#include "nl/cmdline.h"
#include "nl/evidence.h"
#include "nl/fs.h"
#include "nl/session.h"
#include <tlhelp32.h>
#include <charconv>
#include <cstdio>
#include <cwchar>
#include <iterator>
#include <filesystem>
#include <stdexcept>
#include <vector>

namespace nl::proxy::observer {
namespace {
struct Handle {
  HANDLE value = nullptr;
  ~Handle() { if (value) CloseHandle(value); }
};
struct Attributes {
  std::vector<unsigned char> storage;
  LPPROC_THREAD_ATTRIBUTE_LIST value = nullptr;
  explicit Attributes(HANDLE* handles, SIZE_T count) {
    SIZE_T bytes = 0;
    InitializeProcThreadAttributeList(nullptr, 1, 0, &bytes);
    storage.resize(bytes);
    value = reinterpret_cast<LPPROC_THREAD_ATTRIBUTE_LIST>(storage.data());
    if (!InitializeProcThreadAttributeList(value, 1, 0, &bytes)) { value = nullptr; throw std::runtime_error("observer attribute list failed"); }
    if (!UpdateProcThreadAttribute(value, 0, PROC_THREAD_ATTRIBUTE_HANDLE_LIST, handles, count * sizeof(HANDLE), nullptr, nullptr)) {
      DeleteProcThreadAttributeList(value); value = nullptr; throw std::runtime_error("observer handle list failed");
    }
  }
  ~Attributes() { if (value) DeleteProcThreadAttributeList(value); }
};
std::uint64_t creation(HANDLE process) {
  FILETIME created{}, exited{}, kernel{}, user{};
  if (!GetProcessTimes(process, &created, &exited, &kernel, &user)) return 0;
  return (std::uint64_t(created.dwHighDateTime) << 32) | created.dwLowDateTime;
}
std::uint64_t number(std::wstring_view value) {
  if (value.empty() || value.size() > 20) throw std::runtime_error("invalid observer argument");
  std::string text;
  for (const auto c : value) {
    if (c < L'0' || c > L'9') throw std::runtime_error("invalid observer number");
    text.push_back(static_cast<char>(c));
  }
  std::uint64_t result = 0;
  const auto parsed = std::from_chars(text.data(), text.data() + text.size(), result);
  if (parsed.ec != std::errc{} || parsed.ptr != text.data() + text.size() || !result)
    throw std::runtime_error("invalid observer number");
  return result;
}
std::filesystem::path module_path() {
  HMODULE module = nullptr;
  if (!GetModuleHandleExW(GET_MODULE_HANDLE_EX_FLAG_FROM_ADDRESS | GET_MODULE_HANDLE_EX_FLAG_UNCHANGED_REFCOUNT,
                         reinterpret_cast<LPCWSTR>(&module_path), &module)) throw std::runtime_error("observer DLL unavailable");
  wchar_t path[kPathCapacity]{};
  const auto size = GetModuleFileNameW(module, path, kPathCapacity);
  if (!size || size >= kPathCapacity) throw std::runtime_error("observer DLL path unavailable");
  return std::filesystem::path(path);
}
bool parent_is(DWORD pid) {
  Handle snapshot{CreateToolhelp32Snapshot(TH32CS_SNAPPROCESS, 0)};
  if (snapshot.value == INVALID_HANDLE_VALUE) { snapshot.value = nullptr; return false; }
  PROCESSENTRY32W process{}; process.dwSize = sizeof(process);
  if (!Process32FirstW(snapshot.value, &process)) return false;
  do {
    if (process.th32ProcessID == GetCurrentProcessId()) return process.th32ParentProcessID == pid;
  } while (Process32NextW(snapshot.value, &process));
  return false;
}
std::string environment() {
  wchar_t value[64]{};
  const auto size = GetEnvironmentVariableW(L"NATIVE_LOADER_EXIT_REPORT", value, 64);
  return size && size < 64 ? fs::utf8(std::filesystem::path(value)) : "";
}
std::wstring wide(std::string_view text) {
  if (text.empty()) return {};
  const auto size = MultiByteToWideChar(CP_UTF8, MB_ERR_INVALID_CHARS, text.data(), static_cast<int>(text.size()), nullptr, 0);
  if (!size) throw std::runtime_error("observer UTF-8 conversion failed");
  std::wstring result(static_cast<std::size_t>(size), L'\0');
  MultiByteToWideChar(CP_UTF8, MB_ERR_INVALID_CHARS, text.data(), static_cast<int>(text.size()), result.data(), size);
  return result;
}
std::string language(const std::filesystem::path& root, std::string_view override_code) {
  std::string config;
  try {
    fs::refuse_links(root, session::kConfigCfg);
    config = fs::read_file(fs::join(root, session::kConfigCfg), 1u << 20);
  } catch (const std::exception&) { }
  wchar_t locale[LOCALE_NAME_MAX_LENGTH]{};
  GetUserDefaultLocaleName(locale, LOCALE_NAME_MAX_LENGTH);
  return exit_report::language(config, override_code, fs::utf8(std::filesystem::path(locale)));
}
void show(const evidence::PreviousSession& previous, DWORD code, const std::filesystem::path& root, std::string_view locale) {
  const auto text = wide(exit_report::message(previous, code, root, locale));
  const auto title = wide(exit_report::title(locale));
  // Keep the proxy's import table KERNEL32-only and do not initialize UI inside the game.
  const auto user32 = LoadLibraryExW(L"user32.dll", nullptr, LOAD_LIBRARY_SEARCH_SYSTEM32);
  if (!user32) return;
  using Message = int(WINAPI*)(HWND, LPCWSTR, LPCWSTR, UINT);
  const auto message = reinterpret_cast<Message>(GetProcAddress(user32, "MessageBoxW"));
  if (message) message(nullptr, text.c_str(), title.c_str(), MB_OK | MB_ICONWARNING | MB_SETFOREGROUND);
  FreeLibrary(user32);
}
// A refusal ends the rundll32 host with kRefused + its reason, so start() names it at once instead of
// waiting out its budget (R8 CI: observers refused the clock check below and the test saw no note).
constexpr DWORD kRefused = 0x4E4C0000;  // "NL"
enum Refusal : DWORD {
  kBound, kArguments, kProcessId, kParent, kCreation, kStartBeforeCreation, kInheritance, kImagePath, kReadyEvent, kException,
};
constexpr const char* kRefusals[] = {"bound", "arguments", "process id", "parent process", "creation time",
    "session start before process creation", "inherited handle", "image path", "ready event", "exception"};
std::string refusal(DWORD code) {
  if (code > kRefused && code - kRefused < std::size(kRefusals)) return kRefusals[code - kRefused];
  char text[32]{};
  std::snprintf(text, sizeof(text), "exit code 0x%08lX", static_cast<unsigned long>(code));
  return text;
}
Refusal observe(std::wstring_view command) {
  if (!host()) return kBound;  // not rundll32: nothing to observe, and no exit code to set
  const auto args = cmdline::tokenize(command);
  if (args.size() != 6) return kArguments;
  std::uint64_t values[5]{};
  try {
    for (std::size_t index = 0; index < 5; ++index) values[index] = number(args[index]);
  } catch (const std::exception&) { return kArguments; }
  Handle game{reinterpret_cast<HANDLE>(values[0])};
  Handle ready{reinterpret_cast<HANDLE>(values[1])};
  const auto pid = values[2], created = values[3], start = values[4];
  const auto root = module_path().parent_path().parent_path().parent_path();
  DWORD flags = 0;
  wchar_t image[kPathCapacity]{}; DWORD size = kPathCapacity;
  const auto expected = (root / L"bin" / L"win64" / L"gmod.exe").wstring();
  if (pid > MAXDWORD || GetProcessId(game.value) != pid) return kProcessId;
  if (!parent_is(static_cast<DWORD>(pid))) return kParent;
  if (!created || creation(game.value) != created) return kCreation;
  if (!exit_report::session_after_creation(start, created)) return kStartBeforeCreation;
  if (!GetHandleInformation(game.value, &flags) || !(flags & HANDLE_FLAG_INHERIT)) return kInheritance;
  if (!QueryFullProcessImageNameW(game.value, 0, image, &size) ||
      CompareStringOrdinal(image, static_cast<int>(size), expected.c_str(), static_cast<int>(expected.size()), TRUE) != CSTR_EQUAL)
    return kImagePath;
  if (!SetEvent(ready.value)) return kReadyEvent;
  CloseHandle(ready.value); ready.value = nullptr;
  SetThreadPriority(GetCurrentThread(), THREAD_PRIORITY_BELOW_NORMAL);
  if (WaitForSingleObject(game.value, INFINITE) != WAIT_OBJECT_0) return kBound;
  DWORD code = 0;
  if (!GetExitCodeProcess(game.value, &code)) return kBound;
  const bool quiet = exit_report::quiet(environment());
  const auto result = evidence::finish(root, start, static_cast<DWORD>(pid), code,
      std::to_string(pid) + '-' + std::to_string(created), quiet);
  CloseHandle(game.value); game.value = nullptr;
  if (!quiet && evidence::needs_report(result.previous.reason))
    show(result.previous, code, root, language(root, args[5] == L"-" ? "" : fs::utf8(std::filesystem::path(args[5]))));
  return kBound;
}
}  // namespace
bool host() noexcept {
  wchar_t exe[kPathCapacity]{}, expected[MAX_PATH]{};
  const auto size = GetModuleFileNameW(nullptr, exe, kPathCapacity);
  const auto system = GetSystemDirectoryW(expected, MAX_PATH);
  constexpr std::wstring_view suffix = L"\\rundll32.exe";
  if (!size || size >= kPathCapacity || !system || system + suffix.size() >= MAX_PATH) return false;
  std::wmemcpy(expected + system, suffix.data(), suffix.size());
  return CompareStringOrdinal(exe, static_cast<int>(size), expected, static_cast<int>(system + suffix.size()), TRUE) == CSTR_EQUAL;
}
std::string start(std::uint64_t session_start) noexcept {
  try {
    if (environment() == "off") return "exit observer disabled by automation";
    Handle game;
    if (!DuplicateHandle(GetCurrentProcess(), GetCurrentProcess(), GetCurrentProcess(), &game.value,
                         SYNCHRONIZE | PROCESS_QUERY_LIMITED_INFORMATION, TRUE, 0)) return "exit observer: cannot pin game process";
    SECURITY_ATTRIBUTES security{sizeof(security), nullptr, TRUE};
    Handle ready{CreateEventW(&security, TRUE, FALSE, nullptr)};
    if (!ready.value) return "exit observer: cannot create ready event";
    HANDLE handles[] = {game.value, ready.value};
    Attributes attributes(handles, 2);
    wchar_t system[kPathCapacity]{};
    const auto size = GetSystemDirectoryW(system, kPathCapacity);
    if (!size || size >= kPathCapacity) return "exit observer: System32 unavailable";
    const auto executable = std::filesystem::path(system) / L"rundll32.exe";
    const auto selected = exit_report::command_language(GetCommandLineW());
    auto command = L"\"" + executable.wstring() + L"\" \"" + std::wstring(g_bootstrap.module) + L"\",NativeLoaderObserve " +
        std::to_wstring(reinterpret_cast<std::uintptr_t>(game.value)) + L" " +
        std::to_wstring(reinterpret_cast<std::uintptr_t>(ready.value)) + L" " + std::to_wstring(GetCurrentProcessId()) + L" " +
        std::to_wstring(creation(GetCurrentProcess())) + L" " + std::to_wstring(session_start) + L" " +
        wide(selected.empty() ? "-" : exit_report::language({}, selected, {}));
    STARTUPINFOEXW info{}; info.StartupInfo.cb = sizeof(info); info.lpAttributeList = attributes.value;
    info.StartupInfo.dwFlags = STARTF_USESHOWWINDOW; info.StartupInfo.wShowWindow = SW_HIDE;
    PROCESS_INFORMATION process{};
    if (!CreateProcessW(executable.c_str(), command.data(), nullptr, nullptr, TRUE,
                        EXTENDED_STARTUPINFO_PRESENT | CREATE_NO_WINDOW, nullptr, g_bootstrap.root, &info.StartupInfo, &process))
      return "exit observer: CreateProcess failed (" + std::to_string(GetLastError()) + ')';
    Handle child{process.hProcess}, thread{process.hThread};
    // Ready, or the observer gone first (a refusal's exit code says why), or the 3 s budget spent.
    HANDLE signals[] = {ready.value, child.value};
    const auto wait = WaitForMultipleObjects(2, signals, FALSE, 3000);
    const auto id = "pid=" + std::to_string(process.dwProcessId);
    if (wait == WAIT_OBJECT_0) return "exit observer ready: " + id;
    DWORD code = 0;
    if (wait == WAIT_OBJECT_0 + 1 && GetExitCodeProcess(child.value, &code)) return "exit observer refused: " + id + ", " + refusal(code);
    return "exit observer not ready: " + id;
  } catch (const std::exception&) { return "exit observer: initialization failed"; }
}
std::string disable_window_ghosting() noexcept {
  try {
    wchar_t value[8]{};
    const auto size = GetEnvironmentVariableW(L"NATIVE_LOADER_WINDOW_GHOSTING", value, 8);
    if (exit_report::keep_window_ghosting(size && size < 8 ? fs::utf8(std::filesystem::path(value)) : ""))
      return "window ghosting kept (NATIVE_LOADER_WINDOW_GHOSTING=1)";
    // As in show(): the import table stays KERNEL32-only. user32 stays loaded; the game loads it anyway.
    const auto user32 = LoadLibraryExW(L"user32.dll", nullptr, LOAD_LIBRARY_SEARCH_SYSTEM32);
    using Disable = void(WINAPI*)();
    const auto disable = user32 ? reinterpret_cast<Disable>(GetProcAddress(user32, "DisableProcessWindowsGhosting")) : nullptr;
    if (!disable) return "window ghosting unchanged: DisableProcessWindowsGhosting unavailable";
    disable();
    return "window ghosting off: long loads no longer show the window as Not Responding";
  } catch (const std::exception&) { return "window ghosting unchanged"; }
}
}  // namespace nl::proxy::observer

extern "C" __declspec(dllexport) void CALLBACK NativeLoaderObserveW(HWND, HINSTANCE, LPWSTR command, int) {
  using namespace nl::proxy::observer;
  Refusal refused = kBound;
  try { if (command) refused = observe(command); }
  catch (...) { refused = kException; OutputDebugStringW(L"Native Loader: exit observer could not report.\n"); }
  // The game's start-up waits on this process too: a refusal's exit code names the reason there.
  if (refused != kBound) ExitProcess(kRefused + refused);
}
extern "C" __declspec(dllexport) void CALLBACK NativeLoaderExitPreviewW(HWND, HINSTANCE, LPWSTR command, int) {
  using namespace nl::proxy;
  try {
    if (!observer::host() || !command || exit_report::quiet(observer::environment())) return;
    const auto args = nl::cmdline::tokenize(command);
    if (args.empty() || args.size() > 2) return;
    const auto reason = nl::fs::utf8(std::filesystem::path(args[0]));
    if (reason != "crash" && reason != "device_lost" && reason != "out_of_memory" && reason != "allocation_failed" &&
        reason != "cs_exception" && reason != "likely_out_of_memory") return;
    const auto root = observer::module_path().parent_path().parent_path().parent_path();
    const auto locale = observer::language(root, args.size() == 2 ? nl::fs::utf8(std::filesystem::path(args[1])) : "");
    // Preview is read-only: no fake evidence or next-session classification is written.
    observer::show({reason, {}, std::string(nl::evidence::kSessions)}, reason == "out_of_memory" ? 0xC0000017u :
        reason == "crash" ? 0xC0000005u : 1u, root, locale);
  } catch (...) { OutputDebugStringW(L"Native Loader: exit preview unavailable.\n"); }
}
