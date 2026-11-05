#include "modules.h"

#include "nl/fs.h"
#include "nl/json.h"
#include "nl/patch.h"
#include "nl/status.h"

#include <windows.h>
#include <tlhelp32.h>

#include <algorithm>
#include <atomic>
#include <cstddef>
#include <cstdio>
#include <cstring>
#include <memory>
#include <mutex>

namespace nl::proxy::modules {
namespace {

// LdrRegisterDllNotification (ntdll; documented, resolved at run time so winmm.dll keeps importing
// only KERNEL32). The loaded and unloaded data share this layout.
struct LdrString {
  USHORT length;
  USHORT maximum_length;
  PWSTR buffer;
};
struct LdrData {
  ULONG flags;
  const LdrString* full_name;
  const LdrString* base_name;
  PVOID base;
  ULONG size;
};
using Callback = VOID(CALLBACK*)(ULONG reason, const LdrData* data, PVOID context);
using Register = LONG(NTAPI*)(ULONG flags, Callback callback, PVOID context, PVOID* cookie);
using Unregister = LONG(NTAPI*)(PVOID cookie);
constexpr ULONG kLoaded = 1;

using LoadA = HMODULE(WINAPI*)(LPCSTR);
using LoadW = HMODULE(WINAPI*)(LPCWSTR);
using LoadExA = HMODULE(WINAPI*)(LPCSTR, HANDLE, DWORD);
using LoadExW = HMODULE(WINAPI*)(LPCWSTR, HANDLE, DWORD);
using FindFirstA = HANDLE(WINAPI*)(LPCSTR, LPWIN32_FIND_DATAA);
using FindFirstW = HANDLE(WINAPI*)(LPCWSTR, LPWIN32_FIND_DATAW);
using FindFirstExW = HANDLE(WINAPI*)(LPCWSTR, FINDEX_INFO_LEVELS, LPVOID, FINDEX_SEARCH_OPS, LPVOID, DWORD);
using FindNextA = BOOL(WINAPI*)(HANDLE, LPWIN32_FIND_DATAA);
using FindNextW = BOOL(WINAPI*)(HANDLE, LPWIN32_FIND_DATAW);
using FindCloseFn = BOOL(WINAPI*)(HANDLE);
using CreateA = HANDLE(WINAPI*)(LPCSTR, DWORD, DWORD, LPSECURITY_ATTRIBUTES, DWORD, DWORD, HANDLE);
using CreateW = HANDLE(WINAPI*)(LPCWSTR, DWORD, DWORD, LPSECURITY_ATTRIBUTES, DWORD, DWORD, HANDLE);
using AttributesA = BOOL(WINAPI*)(LPCSTR, GET_FILEEX_INFO_LEVELS, LPVOID);
using AttributesW = BOOL(WINAPI*)(LPCWSTR, GET_FILEEX_INFO_LEVELS, LPVOID);

// The module whose searches mount GMod's add-on folders (it imports FindFirstFileA/ExW and
// FindNextFileA/W: docs/RESEARCH.md section 13).
constexpr std::wstring_view kSearchModule = L"filesystem_stdio.dll";

struct Hooked {
  void** slot;
  void* original;
};

struct State {
  Setup setup;
  // False once uninstall() has run: every hook then only calls the original function. A hook that a
  // slot still points at (its restore failed) or that another thread is running stays valid.
  std::atomic<bool> active{true};
  std::wstring root_prefix;    // "<root>\" lower-case, for "is this a game module"
  std::wstring loader_prefix;  // "<root>\native-loader\" lower-case: never touched
  std::wstring bin_folder;     // "<root>\bin\win64" lower-case: where overridden modules are expected
  std::vector<std::pair<std::wstring, std::wstring>> overrides;  // lower-case module -> replacement path
  PVOID cookie = nullptr;
  Unregister unregister = nullptr;
  LoadA load_a = nullptr;
  LoadW load_w = nullptr;
  LoadExA load_ex_a = nullptr;
  LoadExW load_ex_w = nullptr;
  std::vector<Hooked> hooked;  // for uninstall
  SRWLOCK lock = SRWLOCK_INIT;
  std::vector<patch::Result> patches;
  std::vector<std::string> overrides_done;  // JSON objects
  std::vector<std::string> modules_seen;    // game modules the watcher handled
  std::vector<std::string> notes;           // what did not work as planned
  // Sessions without a runtime (ADR 0013).
  std::vector<std::wstring> hidden;          // lower-case add-on folder names left out of searches
  std::wstring addons_folder;                // "<root>\garrysmod\addons" lower-case
  FindFirstA find_first_a = nullptr;
  FindFirstW find_first_w = nullptr;
  FindFirstExW find_first_ex_w = nullptr;
  FindNextA find_next_a = nullptr;
  FindNextW find_next_w = nullptr;
  FindCloseFn find_close = nullptr;
  std::vector<HANDLE> searches;              // open searches of the add-ons folder
  std::vector<std::string> hidden_seen;      // folders a search actually left out
  std::vector<std::string> search_hooked;    // modules whose searches are filtered
  // Every session (ADR 0024): binary modules and what is loaded before them.
  std::vector<std::pair<std::wstring, std::vector<std::wstring>>> dependencies;  // lower-case module path -> paths
  std::vector<std::wstring> loaded_first;     // lower-case paths loaded once: not loaded again
  std::vector<std::wstring> failed_first;     // lower-case paths that failed once: tried again, reported once
  std::vector<std::string> dependencies_done; // JSON objects
  struct ReadRedirect {
    std::wstring source, replacement;
    std::string relative;
    std::uint64_t size, mtime;
  };
  std::vector<ReadRedirect> read_redirects;
  CreateA create_a = nullptr;
  CreateW create_w = nullptr;
  AttributesA attributes_a = nullptr;
  AttributesW attributes_w = nullptr;
  std::vector<std::string> reads_seen, read_hooked;
};
// Published before the first import slot points at a hook, and never cleared or freed: a hook reads
// it once and keeps using that state, even while uninstall() runs on another thread (R1-003). An
// install() after uninstall() publishes a new state (a failed RTX activation followed by the add-on
// hiding of a start without a runtime); the old one stays allocated.
std::atomic<State*> g_state{nullptr};

State* state() noexcept { return g_state.load(std::memory_order_acquire); }

std::wstring lower(std::wstring text) {
  for (auto& c : text) {
    if (c >= L'A' && c <= L'Z') c = static_cast<wchar_t>(c - L'A' + L'a');
    else if (c == L'/') c = L'\\';
  }
  return text;
}

std::string narrow(std::wstring_view text) {
  if (text.empty()) return {};
  const int size = WideCharToMultiByte(CP_UTF8, 0, text.data(), static_cast<int>(text.size()), nullptr, 0, nullptr, nullptr);
  std::string out(static_cast<std::size_t>(size > 0 ? size : 0), '\0');
  if (size > 0) WideCharToMultiByte(CP_UTF8, 0, text.data(), static_cast<int>(text.size()), out.data(), size, nullptr, nullptr);
  return out;
}

std::wstring full_path(std::wstring_view path) {
  wchar_t buffer[MAX_PATH * 4]{};
  const DWORD size = GetFullPathNameW(std::wstring(path).c_str(), MAX_PATH * 4, buffer, nullptr);
  return size && size < MAX_PATH * 4 ? std::wstring(buffer, size) : std::wstring(path);
}

std::string utc_now() {
  SYSTEMTIME utc{};
  GetSystemTime(&utc);
  char timestamp[40]{};
  std::snprintf(timestamp, sizeof(timestamp), "%04u-%02u-%02uT%02u:%02u:%02u.%03uZ", utc.wYear, utc.wMonth, utc.wDay, utc.wHour,
                utc.wMinute, utc.wSecond, utc.wMilliseconds);
  return timestamp;
}

void note(State& s, std::string text) {
  AcquireSRWLockExclusive(&s.lock);
  s.notes.push_back(std::move(text));
  ReleaseSRWLockExclusive(&s.lock);
}

// The override for a load of `requested`, if it names an overridden module in bin\win64.
const std::pair<std::wstring, std::wstring>* override_for(const State& s, std::wstring_view requested) {
  if (s.overrides.empty() || requested.empty()) return nullptr;
  const std::wstring path = lower(full_path(requested));
  const std::size_t slash = path.rfind(L'\\');
  if (slash == std::wstring::npos) return nullptr;
  if (path.substr(0, slash) != s.bin_folder) return nullptr;
  const std::wstring name = path.substr(slash + 1);
  for (const auto& item : s.overrides) {
    if (item.first == name) return &item;
  }
  return nullptr;
}

std::wstring widen_ansi(LPCSTR text) {
  if (!text) return {};
  const int size = MultiByteToWideChar(CP_ACP, 0, text, -1, nullptr, 0);
  if (size <= 1) return {};
  std::wstring out(static_cast<std::size_t>(size - 1), L'\0');
  MultiByteToWideChar(CP_ACP, 0, text, -1, out.data(), size);
  return out;
}

// LoadLibraryEx's LOAD_LIBRARY_SEARCH_* flags. Windows refuses any of them together with
// LOAD_WITH_ALTERED_SEARCH_PATH (ERROR_INVALID_PARAMETER), so a caller's search flags are kept as they
// are: for a replacement loaded by its full path, LOAD_LIBRARY_SEARCH_DLL_LOAD_DIR or the default
// directories already look beside it first, as the altered search path would (R19, proxy F-05).
constexpr DWORD kSearchFlags = 0x00000100 /* DLL_LOAD_DIR */ | 0x00000200 /* APPLICATION_DIR */ | 0x00000400 /* USER_DIRS */ |
                               0x00000800 /* SYSTEM32 */ | 0x00001000 /* DEFAULT_DIRS */ | 0x00004000 /* SYSTEM32_NO_FORWARDER */;

DWORD replacement_flags(DWORD flags) {
  return (flags & kSearchFlags) ? flags : flags | LOAD_WITH_ALTERED_SEARCH_PATH;
}

HMODULE load_replacement(State& s, std::wstring_view requested, const std::pair<std::wstring, std::wstring>& item, HANDLE handle,
                         DWORD flags) {
  HMODULE module = s.load_ex_w(item.second.c_str(), handle, replacement_flags(flags));
  const DWORD error = module ? 0 : GetLastError();
  std::string entry = "{\"module\": " + json::quote(narrow(item.first)) + ", \"requested\": " + json::quote(narrow(requested)) +
                      ", \"loaded\": " + json::quote(narrow(item.second)) + ", \"result\": " +
                      json::quote(module ? "redirected" : "failed") + ", \"windows_error\": " + std::to_string(error) + "}";
  AcquireSRWLockExclusive(&s.lock);
  s.overrides_done.push_back(std::move(entry));
  ReleaseSRWLockExclusive(&s.lock);
  write_session_json();
  if (!module) SetLastError(error);
  return module;
}

constexpr DWORD kNotAnImage = LOAD_LIBRARY_AS_DATAFILE | LOAD_LIBRARY_AS_IMAGE_RESOURCE | LOAD_LIBRARY_AS_DATAFILE_EXCLUSIVE;

// Before a load of a binary module that needs other files (ADR 0024), loads each of them by its
// absolute path, until it has loaded once in this process. The module's static import of the same base
// name then binds to the loaded file, wherever Windows would have searched (next to gmod.exe first). A
// file that fails to load is reported; the module's own load then fails as it would have, and the next
// load of the module tries the file again: a scanner or an update may have held it only for a moment
// (R19, proxy F-04). Each file's first failure and its success are reported, not every retry.
void load_first(State& s, std::wstring_view requested) {
  if (s.dependencies.empty() || requested.empty()) return;
  const std::wstring path = lower(full_path(requested));
  for (const auto& [module, files] : s.dependencies) {
    if (module != path) continue;
    for (const auto& file : files) {
      const std::wstring key = lower(file);
      AcquireSRWLockShared(&s.lock);
      const bool done = std::find(s.loaded_first.begin(), s.loaded_first.end(), key) != s.loaded_first.end();
      ReleaseSRWLockShared(&s.lock);
      if (done) continue;
      // Two threads can both get here; the second load only adds a reference to the same module.
      const HMODULE loaded = s.load_ex_w(file.c_str(), nullptr, LOAD_WITH_ALTERED_SEARCH_PATH);
      const DWORD error = loaded ? 0 : GetLastError();
      AcquireSRWLockExclusive(&s.lock);
      bool report = false;
      if (loaded && std::find(s.loaded_first.begin(), s.loaded_first.end(), key) == s.loaded_first.end()) {
        s.loaded_first.push_back(key);
        report = true;
      } else if (!loaded && std::find(s.failed_first.begin(), s.failed_first.end(), key) == s.failed_first.end()) {
        s.failed_first.push_back(key);
        report = true;
      }
      if (report) {
        s.dependencies_done.push_back("{\"module\": " + json::quote(narrow(module)) + ", \"loaded_first\": " + json::quote(narrow(file)) +
                                      ", \"result\": " + json::quote(loaded ? "loaded" : "failed") +
                                      ", \"windows_error\": " + std::to_string(error) + "}");
      }
      ReleaseSRWLockExclusive(&s.lock);
      if (report) write_session_json();
    }
    return;
  }
}

HMODULE WINAPI hook_load_a(LPCSTR name) {
  State& s = *state();
  if (s.active.load(std::memory_order_acquire)) {
    const std::wstring wide = widen_ansi(name);
    load_first(s, wide);
    if (const auto* item = override_for(s, wide)) return load_replacement(s, wide, *item, nullptr, 0);
  }
  return s.load_a(name);
}
HMODULE WINAPI hook_load_w(LPCWSTR name) {
  State& s = *state();
  if (s.active.load(std::memory_order_acquire)) {
    load_first(s, name ? name : L"");
    if (const auto* item = override_for(s, name ? name : L"")) return load_replacement(s, name, *item, nullptr, 0);
  }
  return s.load_w(name);
}
HMODULE WINAPI hook_load_ex_a(LPCSTR name, HANDLE file, DWORD flags) {
  State& s = *state();
  if (s.active.load(std::memory_order_acquire) && (flags & kNotAnImage) == 0) {
    const std::wstring wide = widen_ansi(name);
    load_first(s, wide);
    if (const auto* item = override_for(s, wide)) return load_replacement(s, wide, *item, file, flags);
  }
  return s.load_ex_a(name, file, flags);
}
HMODULE WINAPI hook_load_ex_w(LPCWSTR name, HANDLE file, DWORD flags) {
  State& s = *state();
  if (s.active.load(std::memory_order_acquire) && (flags & kNotAnImage) == 0) {
    load_first(s, name ? name : L"");
    if (const auto* item = override_for(s, name ? name : L"")) return load_replacement(s, name, *item, file, flags);
  }
  return s.load_ex_w(name, file, flags);
}

// ---- Sessions without a runtime: add-on folders left out of searches of garrysmod\addons.

bool addons_search(const State& s, const std::wstring& pattern) {
  if (s.hidden.empty() || pattern.empty()) return false;
  const std::wstring path = lower(full_path(pattern));
  const std::size_t slash = path.rfind(L'\\');
  return slash != std::wstring::npos && path.compare(0, slash, s.addons_folder) == 0 && slash == s.addons_folder.size();
}

bool hidden_name(State& s, std::wstring_view name) {
  const std::wstring folded = lower(std::wstring(name));
  for (const auto& hidden : s.hidden) {
    if (hidden != folded) continue;
    const std::string text = narrow(folded);
    AcquireSRWLockExclusive(&s.lock);
    const bool first = std::find(s.hidden_seen.begin(), s.hidden_seen.end(), text) == s.hidden_seen.end();
    if (first) s.hidden_seen.push_back(text);
    ReleaseSRWLockExclusive(&s.lock);
    if (first) write_session_json();
    return true;
  }
  return false;
}

void track(State& s, HANDLE search) {
  AcquireSRWLockExclusive(&s.lock);
  s.searches.push_back(search);
  ReleaseSRWLockExclusive(&s.lock);
}

// A handle value Windows hands out again (its search was closed through a path we do not see) is
// no longer an add-ons search.
void untrack(State& s, HANDLE search) {
  AcquireSRWLockExclusive(&s.lock);
  s.searches.erase(std::remove(s.searches.begin(), s.searches.end(), search), s.searches.end());
  ReleaseSRWLockExclusive(&s.lock);
}

bool tracked(State& s, HANDLE search) {
  AcquireSRWLockShared(&s.lock);
  const bool found = std::find(s.searches.begin(), s.searches.end(), search) != s.searches.end();
  ReleaseSRWLockShared(&s.lock);
  return found;
}

// A first result that is hidden is replaced by the next one; when none is left, the search is
// closed and reports what an empty folder would (ERROR_FILE_NOT_FOUND).
template <typename Data, typename Next, typename Name>
HANDLE first_visible(State& s, HANDLE search, Data* data, Next next, Name name) {
  while (hidden_name(s, name(data))) {
    if (!next(search, data)) {
      const DWORD error = GetLastError();
      s.find_close(search);
      SetLastError(error == ERROR_NO_MORE_FILES ? ERROR_FILE_NOT_FOUND : error);
      return INVALID_HANDLE_VALUE;
    }
  }
  track(s, search);
  return search;
}

std::wstring name_w(const WIN32_FIND_DATAW* data) { return data->cFileName; }
std::wstring name_a(const WIN32_FIND_DATAA* data) { return widen_ansi(data->cFileName); }

HANDLE WINAPI hook_find_first_a(LPCSTR pattern, LPWIN32_FIND_DATAA data) {
  State& s = *state();
  const HANDLE search = s.find_first_a(pattern, data);
  if (search == INVALID_HANDLE_VALUE || !s.active.load(std::memory_order_acquire)) return search;
  if (!data || !addons_search(s, widen_ansi(pattern))) {
    untrack(s, search);
    return search;
  }
  return first_visible(s, search, data, s.find_next_a, &name_a);
}
HANDLE WINAPI hook_find_first_w(LPCWSTR pattern, LPWIN32_FIND_DATAW data) {
  State& s = *state();
  const HANDLE search = s.find_first_w(pattern, data);
  if (search == INVALID_HANDLE_VALUE || !s.active.load(std::memory_order_acquire)) return search;
  if (!data || !addons_search(s, pattern ? pattern : L"")) {
    untrack(s, search);
    return search;
  }
  return first_visible(s, search, data, s.find_next_w, &name_w);
}
HANDLE WINAPI hook_find_first_ex_w(LPCWSTR pattern, FINDEX_INFO_LEVELS level, LPVOID data, FINDEX_SEARCH_OPS op, LPVOID filter,
                                   DWORD flags) {
  State& s = *state();
  const HANDLE search = s.find_first_ex_w(pattern, level, data, op, filter, flags);
  if (search == INVALID_HANDLE_VALUE || !s.active.load(std::memory_order_acquire)) return search;
  if (!data || (level != FindExInfoStandard && level != FindExInfoBasic) || !addons_search(s, pattern ? pattern : L"")) {
    untrack(s, search);
    return search;
  }
  return first_visible(s, search, static_cast<WIN32_FIND_DATAW*>(data), s.find_next_w, &name_w);
}
BOOL WINAPI hook_find_next_a(HANDLE search, LPWIN32_FIND_DATAA data) {
  State& s = *state();
  BOOL found = s.find_next_a(search, data);
  if (!s.active.load(std::memory_order_acquire)) return found;
  while (found && data && tracked(s, search) && hidden_name(s, widen_ansi(data->cFileName))) found = s.find_next_a(search, data);
  return found;
}
BOOL WINAPI hook_find_next_w(HANDLE search, LPWIN32_FIND_DATAW data) {
  State& s = *state();
  BOOL found = s.find_next_w(search, data);
  if (!s.active.load(std::memory_order_acquire)) return found;
  while (found && data && tracked(s, search) && hidden_name(s, data->cFileName)) found = s.find_next_w(search, data);
  return found;
}
BOOL WINAPI hook_find_close(HANDLE search) {
  State& s = *state();
  untrack(s, search);
  return s.find_close(search);
}

// ---- Read-only presentation of native containers and the menu. Never hook the loader's own
// reads, Steam's writes, or the whitelist. The original archive is still the deployer's source.
std::wstring read_path(std::wstring_view path) {
  auto result = lower(full_path(path));
  if (result.starts_with(L"\\\\?\\unc\\")) result = L"\\\\" + result.substr(8);
  else if (result.starts_with(L"\\\\?\\") && result.size() > 6 && result[5] == L':') result.erase(0, 4);
  return result;
}

const State::ReadRedirect* redirect_for(State& s, std::wstring_view path) noexcept {
  if (path.empty() || s.read_redirects.empty()) return nullptr;
  try {
    const auto key = read_path(path);
    for (const auto& item : s.read_redirects) {
      if (item.source != key) continue;
      fs::refuse_links(s.setup.root, item.relative);
      const auto info = fs::stat(item.replacement);
      if (!info.exists || info.directory || info.link || info.size != item.size || info.mtime != item.mtime) return nullptr;
      return &item;
    }
  } catch (...) {
  }
  return nullptr;
}

bool read_only(DWORD access, DWORD disposition, DWORD flags) noexcept {
  return disposition == OPEN_EXISTING && (flags & FILE_FLAG_DELETE_ON_CLOSE) == 0 &&
      (access & ~(GENERIC_READ | FILE_GENERIC_READ)) == 0;
}

const State::ReadRedirect* redirect_for_ansi(State& s, LPCSTR name) noexcept {
  try { return redirect_for(s, widen_ansi(name)); } catch (...) { return nullptr; }
}

void record_read(State& s, const State::ReadRedirect& item) noexcept {
  try {
  const auto text = narrow(item.source);
  bool added = false;
  AcquireSRWLockExclusive(&s.lock);
  try {
  if (std::find(s.reads_seen.begin(), s.reads_seen.end(), text) == s.reads_seen.end()) {
    s.reads_seen.push_back(text);
    added = true;
  }
  } catch (...) { ReleaseSRWLockExclusive(&s.lock); return; }
  ReleaseSRWLockExclusive(&s.lock);
  if (added) write_session_json();
  } catch (...) {}
}

HANDLE WINAPI hook_create_a(LPCSTR name, DWORD access, DWORD sharing, LPSECURITY_ATTRIBUTES security,
                            DWORD disposition, DWORD flags, HANDLE template_file) {
  State& s = *state();
  if (s.active.load(std::memory_order_acquire) && read_only(access, disposition, flags)) {
    if (const auto* item = redirect_for_ansi(s, name)) {
      const HANDLE file = s.create_w(item->replacement.c_str(), access, sharing, security, disposition, flags, template_file);
      if (file != INVALID_HANDLE_VALUE) { record_read(s, *item); return file; }
    }
  }
  return s.create_a(name, access, sharing, security, disposition, flags, template_file);
}

HANDLE WINAPI hook_create_w(LPCWSTR name, DWORD access, DWORD sharing, LPSECURITY_ATTRIBUTES security,
                            DWORD disposition, DWORD flags, HANDLE template_file) {
  State& s = *state();
  if (s.active.load(std::memory_order_acquire) && read_only(access, disposition, flags)) {
    if (const auto* item = redirect_for(s, name ? name : L"")) {
      const HANDLE file = s.create_w(item->replacement.c_str(), access, sharing, security, disposition, flags, template_file);
      if (file != INVALID_HANDLE_VALUE) { record_read(s, *item); return file; }
    }
  }
  return s.create_w(name, access, sharing, security, disposition, flags, template_file);
}

BOOL WINAPI hook_attributes_a(LPCSTR name, GET_FILEEX_INFO_LEVELS level, LPVOID data) {
  State& s = *state();
  if (s.active.load(std::memory_order_acquire)) {
    if (const auto* item = redirect_for_ansi(s, name)) return s.attributes_w(item->replacement.c_str(), level, data);
  }
  return s.attributes_a(name, level, data);
}
BOOL WINAPI hook_attributes_w(LPCWSTR name, GET_FILEEX_INFO_LEVELS level, LPVOID data) {
  State& s = *state();
  if (s.active.load(std::memory_order_acquire)) {
    if (const auto* item = redirect_for(s, name ? name : L"")) return s.attributes_w(item->replacement.c_str(), level, data);
  }
  return s.attributes_w(name, level, data);
}

bool import_from_loader_dll(const char* dll) {
  const auto starts = [&](const char* prefix) { return _strnicmp(dll, prefix, std::strlen(prefix)) == 0; };
  return starts("kernel32") || starts("kernelbase") || starts("api-ms-win-core-libraryloader") || starts("api-ms-win-core-file");
}

// The addresses an import of `function` from KERNEL32 or KERNELBASE (directly or through an api-ms-win
// set) is bound to once the module is loaded.
std::vector<void*> bound_addresses(const char* function) {
  std::vector<void*> out;
  for (const wchar_t* dll : {L"kernel32.dll", L"kernelbase.dll"}) {
    if (const HMODULE module = GetModuleHandleW(dll)) {
      if (void* address = reinterpret_cast<void*>(GetProcAddress(module, function))) out.push_back(address);
    }
  }
  return out;
}

// Points `module`'s imports of `function` at `replacement`. Every RVA is checked against the mapped
// image. A descriptor without an import name table (OriginalFirstThunk 0: its FirstThunk now holds
// addresses, not names) is matched by the bound address instead (R1-006). The slot is recorded
// before it is changed, so a record that cannot be stored leaves the slot alone (R1-002).
int hook_imports_recorded(void* module, const char* function, void* replacement, std::vector<Hooked>* record) {
  auto* image = static_cast<std::uint8_t*>(module);
  if (!image) return 0;
  const auto* dos = reinterpret_cast<const IMAGE_DOS_HEADER*>(image);
  if (dos->e_magic != IMAGE_DOS_SIGNATURE || dos->e_lfanew <= 0 || dos->e_lfanew > 4096) return 0;
  const auto* nt = reinterpret_cast<const IMAGE_NT_HEADERS64*>(image + dos->e_lfanew);
  if (nt->Signature != IMAGE_NT_SIGNATURE || nt->OptionalHeader.Magic != IMAGE_NT_OPTIONAL_HDR64_MAGIC) return 0;
  const std::uint64_t image_size = nt->OptionalHeader.SizeOfImage;
  const auto inside = [&](std::uint64_t rva, std::uint64_t size) { return rva < image_size && size <= image_size - rva; };
  const auto& directory = nt->OptionalHeader.DataDirectory[IMAGE_DIRECTORY_ENTRY_IMPORT];
  if (!directory.VirtualAddress || !directory.Size || !inside(directory.VirtualAddress, directory.Size)) return 0;
  const std::vector<void*> bound = bound_addresses(function);
  int changed = 0;
  const auto change = [&](void** slot) {
    if (record) record->push_back({slot, *slot});
    DWORD previous = 0;
    if (!VirtualProtect(slot, sizeof(void*), PAGE_READWRITE, &previous)) {
      if (record) record->pop_back();
      return;
    }
    *slot = replacement;
    DWORD ignored = 0;
    VirtualProtect(slot, sizeof(void*), previous, &ignored);
    ++changed;
  };
  // Walked like the Windows loader does, to the empty descriptor (some linkers understate Size), but
  // never past the image.
  const auto* descriptor = reinterpret_cast<const IMAGE_IMPORT_DESCRIPTOR*>(image + directory.VirtualAddress);
  for (std::uint64_t d = 0;
       inside(directory.VirtualAddress + d * sizeof(IMAGE_IMPORT_DESCRIPTOR), sizeof(IMAGE_IMPORT_DESCRIPTOR)) && descriptor[d].Name;
       ++d) {
    const IMAGE_IMPORT_DESCRIPTOR& entry = descriptor[d];
    if (!inside(entry.Name, 1) || !inside(entry.FirstThunk, sizeof(IMAGE_THUNK_DATA64))) continue;
    if (!import_from_loader_dll(reinterpret_cast<const char*>(image + entry.Name))) continue;
    auto* slots = reinterpret_cast<IMAGE_THUNK_DATA64*>(image + entry.FirstThunk);
    if (!entry.OriginalFirstThunk) {
      for (std::uint64_t i = 0; inside(entry.FirstThunk + i * sizeof(IMAGE_THUNK_DATA64), sizeof(IMAGE_THUNK_DATA64)) &&
                                slots[i].u1.Function;
           ++i) {
        void** slot = reinterpret_cast<void**>(&slots[i].u1.Function);
        if (*slot != replacement && std::find(bound.begin(), bound.end(), *slot) != bound.end()) change(slot);
      }
      continue;
    }
    if (!inside(entry.OriginalFirstThunk, sizeof(IMAGE_THUNK_DATA64))) continue;
    const auto* names = reinterpret_cast<const IMAGE_THUNK_DATA64*>(image + entry.OriginalFirstThunk);
    for (std::uint64_t i = 0; inside(entry.OriginalFirstThunk + i * sizeof(IMAGE_THUNK_DATA64), sizeof(IMAGE_THUNK_DATA64)) &&
                              inside(entry.FirstThunk + i * sizeof(IMAGE_THUNK_DATA64), sizeof(IMAGE_THUNK_DATA64)) &&
                              names[i].u1.AddressOfData;
         ++i) {
      if (IMAGE_SNAP_BY_ORDINAL64(names[i].u1.Ordinal)) continue;
      const std::uint64_t name_rva = names[i].u1.AddressOfData;
      if (!inside(name_rva, sizeof(IMAGE_IMPORT_BY_NAME))) continue;
      const auto* by_name = reinterpret_cast<const IMAGE_IMPORT_BY_NAME*>(image + name_rva);
      const std::size_t room = static_cast<std::size_t>(image_size - name_rva - offsetof(IMAGE_IMPORT_BY_NAME, Name));
      const char* text = reinterpret_cast<const char*>(by_name->Name);
      if (strnlen(text, room) == room || std::strcmp(text, function) != 0) continue;
      void** slot = reinterpret_cast<void**>(&slots[i].u1.Function);
      if (*slot != replacement) change(slot);
    }
  }
  return changed;
}

void hook_loads(State& s, void* module) {
  if (s.overrides.empty() && s.dependencies.empty()) return;
  hook_imports_recorded(module, "LoadLibraryA", reinterpret_cast<void*>(&hook_load_a), &s.hooked);
  hook_imports_recorded(module, "LoadLibraryW", reinterpret_cast<void*>(&hook_load_w), &s.hooked);
  hook_imports_recorded(module, "LoadLibraryExA", reinterpret_cast<void*>(&hook_load_ex_a), &s.hooked);
  hook_imports_recorded(module, "LoadLibraryExW", reinterpret_cast<void*>(&hook_load_ex_w), &s.hooked);
}

void hook_searches(State& s, void* module, const std::wstring& base_name) {
  if (s.hidden.empty() || lower(base_name) != kSearchModule) return;
  int changed = hook_imports_recorded(module, "FindFirstFileA", reinterpret_cast<void*>(&hook_find_first_a), &s.hooked);
  changed += hook_imports_recorded(module, "FindFirstFileW", reinterpret_cast<void*>(&hook_find_first_w), &s.hooked);
  changed += hook_imports_recorded(module, "FindFirstFileExW", reinterpret_cast<void*>(&hook_find_first_ex_w), &s.hooked);
  changed += hook_imports_recorded(module, "FindNextFileA", reinterpret_cast<void*>(&hook_find_next_a), &s.hooked);
  changed += hook_imports_recorded(module, "FindNextFileW", reinterpret_cast<void*>(&hook_find_next_w), &s.hooked);
  changed += hook_imports_recorded(module, "FindClose", reinterpret_cast<void*>(&hook_find_close), &s.hooked);
  AcquireSRWLockExclusive(&s.lock);
  s.search_hooked.push_back(narrow(lower(base_name)) + " (" + std::to_string(changed) + " imports)");
  ReleaseSRWLockExclusive(&s.lock);
  if (!changed) note(s, narrow(lower(base_name)) + ": no file-search imports found to hook; the RTX-only add-ons are not hidden");
}

void hook_reads(State& s, void* module, const std::wstring& base_name) {
  if (s.read_redirects.empty() || lower(base_name) != kSearchModule) return;
  int changed = hook_imports_recorded(module, "CreateFileA", reinterpret_cast<void*>(&hook_create_a), &s.hooked);
  changed += hook_imports_recorded(module, "CreateFileW", reinterpret_cast<void*>(&hook_create_w), &s.hooked);
  changed += hook_imports_recorded(module, "GetFileAttributesExA", reinterpret_cast<void*>(&hook_attributes_a), &s.hooked);
  changed += hook_imports_recorded(module, "GetFileAttributesExW", reinterpret_cast<void*>(&hook_attributes_w), &s.hooked);
  auto entry = narrow(lower(base_name)) + " (" + std::to_string(changed) + " imports)";
  AcquireSRWLockExclusive(&s.lock);
  try { s.read_hooked.push_back(std::move(entry)); }
  catch (...) { ReleaseSRWLockExclusive(&s.lock); throw; }
  ReleaseSRWLockExclusive(&s.lock);
  if (!changed) note(s, "native package presentation unavailable: no filesystem read imports found");
}

bool game_module(const State& s, const std::wstring& path) {
  return path.compare(0, s.root_prefix.size(), s.root_prefix) == 0 && path.compare(0, s.loader_prefix.size(), s.loader_prefix) != 0;
}

void handle(State& s, void* base, const std::wstring& full_name, const std::wstring& base_name) {
  const std::wstring path = lower(full_name);
  if (!game_module(s, path)) return;
  bool changed = false;
  const std::string name = narrow(lower(base_name));
  for (const auto& set : s.setup.patch_sets) {
    if (set.module != name) continue;
    for (const auto& patch : set.patches) {
      auto result = patch::apply(base, name, patch);
      AcquireSRWLockExclusive(&s.lock);
      s.patches.push_back(std::move(result));
      ReleaseSRWLockExclusive(&s.lock);
      changed = true;
    }
  }
  if (!s.overrides.empty() || !s.dependencies.empty()) {
    hook_loads(s, base);
    AcquireSRWLockExclusive(&s.lock);
    s.modules_seen.push_back(name);
    ReleaseSRWLockExclusive(&s.lock);
  }
  if (!s.hidden.empty() && lower(base_name) == kSearchModule) {
    hook_searches(s, base, base_name);
    changed = true;
  }
  if (!s.read_redirects.empty() && lower(base_name) == kSearchModule) {
    hook_reads(s, base, base_name);
    changed = true;
  }
  if (changed) write_session_json();
}

void handle_raw(const LdrData* data) noexcept {
  try {
    State* s = state();
    if (!s || !s->active.load(std::memory_order_acquire)) return;
    const std::wstring full(data->full_name->buffer, data->full_name->length / sizeof(wchar_t));
    const std::wstring base(data->base_name->buffer, data->base_name->length / sizeof(wchar_t));
    handle(*s, data->base, full, base);
  } catch (...) {
  }
}

// No C++ objects in this frame: MSVC forbids unwinding in a function with __try.
VOID CALLBACK on_dll(ULONG reason, const LdrData* data, PVOID) {
  if (reason != kLoaded || !data || !data->full_name || !data->base_name) return;
  __try {
    handle_raw(data);
  } __except (EXCEPTION_EXECUTE_HANDLER) {
    // Never fault inside the loader's notification; the module then loads unpatched.
  }
}

std::string patch_json(const patch::Result& r) {
  return "{\"module\": " + json::quote(r.module) + ", \"name\": " + json::quote(r.name) + ", \"result\": " + json::quote(r.result) +
         ", \"reason\": " + json::quote(r.reason) + "}";
}

// Undoes what install() changed: no more notifications, every hook a pass-through, every recorded
// import slot back. The state stays published and allocated (see g_state).
void deactivate(State& s) noexcept {
  s.active.store(false, std::memory_order_release);
  if (s.cookie && s.unregister) {
    s.unregister(s.cookie);
    s.cookie = nullptr;
  }
  for (auto it = s.hooked.rbegin(); it != s.hooked.rend(); ++it) {
    DWORD previous = 0;
    if (VirtualProtect(it->slot, sizeof(void*), PAGE_READWRITE, &previous)) {
      *it->slot = it->original;
      DWORD ignored = 0;
      VirtualProtect(it->slot, sizeof(void*), previous, &ignored);
    }
  }
}

}  // namespace

int hook_imports(void* module, const char* function, void* replacement) {
  return hook_imports_recorded(module, function, replacement, nullptr);
}

bool install(Setup setup, std::string& error) {
  if (const State* current = state(); current && current->active.load(std::memory_order_acquire)) {
    error = "module hooks are already installed";
    return false;
  }
  const HMODULE ntdll = GetModuleHandleW(L"ntdll.dll");
  const HMODULE kernel32 = GetModuleHandleW(L"kernel32.dll");
  const auto reg = ntdll ? reinterpret_cast<Register>(GetProcAddress(ntdll, "LdrRegisterDllNotification")) : nullptr;
  const auto unreg = ntdll ? reinterpret_cast<Unregister>(GetProcAddress(ntdll, "LdrUnregisterDllNotification")) : nullptr;
  if (!reg || !unreg || !kernel32) {
    error = "LdrRegisterDllNotification is not available";
    return false;
  }
  auto fresh = std::make_unique<State>();
  fresh->load_a = reinterpret_cast<LoadA>(GetProcAddress(kernel32, "LoadLibraryA"));
  fresh->load_w = reinterpret_cast<LoadW>(GetProcAddress(kernel32, "LoadLibraryW"));
  fresh->load_ex_a = reinterpret_cast<LoadExA>(GetProcAddress(kernel32, "LoadLibraryExA"));
  fresh->load_ex_w = reinterpret_cast<LoadExW>(GetProcAddress(kernel32, "LoadLibraryExW"));
  fresh->find_first_a = reinterpret_cast<FindFirstA>(GetProcAddress(kernel32, "FindFirstFileA"));
  fresh->find_first_w = reinterpret_cast<FindFirstW>(GetProcAddress(kernel32, "FindFirstFileW"));
  fresh->find_first_ex_w = reinterpret_cast<FindFirstExW>(GetProcAddress(kernel32, "FindFirstFileExW"));
  fresh->find_next_a = reinterpret_cast<FindNextA>(GetProcAddress(kernel32, "FindNextFileA"));
  fresh->find_next_w = reinterpret_cast<FindNextW>(GetProcAddress(kernel32, "FindNextFileW"));
  fresh->find_close = reinterpret_cast<FindCloseFn>(GetProcAddress(kernel32, "FindClose"));
  fresh->create_a = reinterpret_cast<CreateA>(GetProcAddress(kernel32, "CreateFileA"));
  fresh->create_w = reinterpret_cast<CreateW>(GetProcAddress(kernel32, "CreateFileW"));
  fresh->attributes_a = reinterpret_cast<AttributesA>(GetProcAddress(kernel32, "GetFileAttributesExA"));
  fresh->attributes_w = reinterpret_cast<AttributesW>(GetProcAddress(kernel32, "GetFileAttributesExW"));
  if (!fresh->load_a || !fresh->load_w || !fresh->load_ex_a || !fresh->load_ex_w || !fresh->find_first_a || !fresh->find_first_w ||
      !fresh->find_first_ex_w || !fresh->find_next_a || !fresh->find_next_w || !fresh->find_close) {
    error = "LoadLibrary or FindFirstFile functions not found";
    return false;
  }
  fresh->unregister = unreg;
  const std::wstring root = lower(full_path(setup.root.native()));
  fresh->root_prefix = root.back() == L'\\' ? root : root + L'\\';
  fresh->loader_prefix = fresh->root_prefix + L"native-loader\\";
  fresh->bin_folder = fresh->root_prefix + L"bin\\win64";
  for (const auto& [module, file] : setup.overrides) {
    std::wstring wide(module.begin(), module.end());  // validated: [a-z0-9_]+.dll
    fresh->overrides.emplace_back(lower(wide), full_path(file.native()));
  }
  for (const auto& name : setup.hidden_addons) fresh->hidden.push_back(lower(std::wstring(name.begin(), name.end())));  // ASCII
  for (const auto& [module, files] : setup.dependencies) {
    std::vector<std::wstring> paths;
    for (const auto& file : files) paths.push_back(full_path(file.native()));
    fresh->dependencies.emplace_back(lower(full_path(module.native())), std::move(paths));
  }
  fresh->addons_folder = fresh->root_prefix + L"garrysmod\\addons";
  if (!setup.read_redirects.empty() && (!fresh->create_a || !fresh->create_w || !fresh->attributes_a || !fresh->attributes_w)) {
    error = "native package presentation: filesystem functions not found";
    return false;
  }
  for (const auto& [source, replacement] : setup.read_redirects) {
    const auto normalized = std::filesystem::absolute(replacement).lexically_normal();
    auto relative = fs::utf8(normalized.lexically_relative(std::filesystem::absolute(setup.root).lexically_normal()));
    std::replace(relative.begin(), relative.end(), '\\', '/');
    if (!relative.starts_with("native-loader/presentation/")) {
      error = "native package presentation: replacement is outside its cache";
      return false;
    }
    fs::refuse_links(setup.root, relative);
    const auto info = fs::stat(normalized);
    if (!info.exists || info.link || info.directory) continue;
    fresh->read_redirects.push_back({read_path(source.native()), normalized.native(), relative, info.size, info.mtime});
  }
  fresh->hooked.reserve(64);
  fresh->setup = std::move(setup);
  State& s = *fresh;
  g_state.store(fresh.release(), std::memory_order_release);

  // From here on hooks can be reached: any failure undoes everything recorded so far (R1-002).
  try {
    // Modules mapped already (gmod.exe and whatever it imports) get their hooks now.
    const HANDLE snapshot = CreateToolhelp32Snapshot(TH32CS_SNAPMODULE, GetCurrentProcessId());
    if (snapshot != INVALID_HANDLE_VALUE) {
      MODULEENTRY32W entry{};
      entry.dwSize = sizeof(entry);
      for (BOOL more = Module32FirstW(snapshot, &entry); more; more = Module32NextW(snapshot, &entry)) {
        if (!game_module(s, lower(entry.szExePath))) continue;
        hook_loads(s, entry.modBaseAddr);
        hook_searches(s, entry.modBaseAddr, entry.szModule);
        hook_reads(s, entry.modBaseAddr, entry.szModule);
      }
      CloseHandle(snapshot);
    }
    const LONG status = reg(0, &on_dll, nullptr, &s.cookie);
    if (status < 0) {
      error = "LdrRegisterDllNotification failed (NTSTATUS " + std::to_string(static_cast<unsigned long>(status)) + ")";
      deactivate(s);
      return false;
    }
  } catch (const std::exception& e) {
    error = std::string("module hooks could not be installed: ") + e.what();
    deactivate(s);
    return false;
  }
  write_session_json();
  return true;
}

void uninstall() noexcept {
  if (State* s = state()) deactivate(*s);
}

std::string results_json() {
  State* s = state();
  if (!s) return "{}";
  const std::string written = utc_now();
  AcquireSRWLockShared(&s->lock);
  std::string out = "{\n  \"schema\": 1,\n  \"utc\": " + json::quote(written) + ",\n" + s->setup.session_json_base + "  \"patches\": [";
  for (std::size_t i = 0; i < s->patches.size(); ++i) out += (i ? ",\n    " : "\n    ") + patch_json(s->patches[i]);
  out += s->patches.empty() ? "],\n" : "\n  ],\n";
  out += "  \"overrides\": [";
  for (std::size_t i = 0; i < s->overrides_done.size(); ++i) out += (i ? ",\n    " : "\n    ") + s->overrides_done[i];
  out += s->overrides_done.empty() ? "],\n" : "\n  ],\n";
  const auto strings = [](const auto& items) {
    std::string list = "[";
    for (std::size_t i = 0; i < items.size(); ++i) list += (i ? ", " : "") + json::quote(items[i]);
    return list + "]";
  };
  std::vector<std::string> configured;
  for (const auto& name : s->hidden) configured.push_back(narrow(name));
  out += "  \"hidden_addons\": {\"folders\": " + strings(configured) + ", \"left_out\": " + strings(s->hidden_seen) +
         ", \"search_hooks\": " + strings(s->search_hooked) + "},\n";
  std::vector<std::string> dependent;
  for (const auto& item : s->dependencies) dependent.push_back(narrow(item.first));
  out += "  \"module_dependencies\": {\"modules\": " + strings(dependent) + ", \"loaded\": [";
  for (std::size_t i = 0; i < s->dependencies_done.size(); ++i) out += (i ? ", " : "") + s->dependencies_done[i];
  out += "]},\n";
  std::vector<std::string> presented;
  for (const auto& item : s->read_redirects) presented.push_back(narrow(item.source));
  out += "  \"package_presentation\": {\"configured\": " + strings(presented) + ", \"read\": " + strings(s->reads_seen) +
         ", \"hooks\": " + strings(s->read_hooked) + "},\n";
  out += "  \"notes\": " + strings(s->notes) + ",\n";
  out += "  \"hooked_modules\": " + std::to_string(s->modules_seen.size()) + "\n}\n";
  ReleaseSRWLockShared(&s->lock);
  return out;
}

void write_session_json() noexcept {
  try {
    State* s = state();
    if (!s) return;
    const auto folder = fs::join(s->setup.root, status::kDirectory);
    if (!fs::stat(folder).directory) return;  // the start-up report creates it
    // Never through a link anywhere below the game root (R1-005); fs::Error ends up below.
    constexpr std::string_view kFile = "garrysmod/data/native-loader/session.json";
    fs::refuse_links(s->setup.root, kFile);
    const auto text = results_json();
    fs::write_atomic(fs::win32(), fs::join(s->setup.root, kFile), text);
  } catch (...) {
  }
}

}  // namespace nl::proxy::modules
