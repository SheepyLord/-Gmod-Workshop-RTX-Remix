#include "modules.h"

#include "nl/fs.h"
#include "nl/json.h"
#include "nl/patch.h"
#include "nl/status.h"

#include <windows.h>
#include <tlhelp32.h>

#include <algorithm>
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

// The module whose searches mount GMod's add-on folders (it imports FindFirstFileA/ExW and
// FindNextFileA/W: docs/RESEARCH.md section 13).
constexpr std::wstring_view kSearchModule = L"filesystem_stdio.dll";

struct Hooked {
  void** slot;
  void* original;
};

struct State {
  Setup setup;
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
};
State* g_state = nullptr;  // process lifetime once installed

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

// The replacement for a load of `requested`, if it names an overridden module in bin\win64.
const std::wstring* replacement_for(std::wstring_view requested) {
  if (!g_state || g_state->overrides.empty() || requested.empty()) return nullptr;
  const std::wstring path = lower(full_path(requested));
  const std::size_t slash = path.rfind(L'\\');
  if (slash == std::wstring::npos) return nullptr;
  if (path.substr(0, slash) != g_state->bin_folder) return nullptr;
  const std::wstring name = path.substr(slash + 1);
  for (const auto& [module, file] : g_state->overrides) {
    if (module == name) return &file;
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

HMODULE load_replacement(std::wstring_view requested, const std::wstring& file, HANDLE handle, DWORD flags) {
  HMODULE module = g_state->load_ex_w(file.c_str(), handle, flags | LOAD_WITH_ALTERED_SEARCH_PATH);
  const DWORD error = module ? 0 : GetLastError();
  std::string entry = "{\"requested\": " + json::quote(narrow(requested)) + ", \"loaded\": " + json::quote(narrow(file)) +
                      ", \"result\": " + json::quote(module ? "redirected" : "failed") + ", \"windows_error\": " +
                      std::to_string(error) + "}";
  AcquireSRWLockExclusive(&g_state->lock);
  g_state->overrides_done.push_back(std::move(entry));
  ReleaseSRWLockExclusive(&g_state->lock);
  write_session_json();
  if (!module) SetLastError(error);
  return module;
}

HMODULE WINAPI hook_load_a(LPCSTR name) {
  const std::wstring wide = widen_ansi(name);
  if (const auto* file = replacement_for(wide)) return load_replacement(wide, *file, nullptr, 0);
  return g_state->load_a(name);
}
HMODULE WINAPI hook_load_w(LPCWSTR name) {
  if (const auto* file = replacement_for(name ? name : L"")) return load_replacement(name, *file, nullptr, 0);
  return g_state->load_w(name);
}
HMODULE WINAPI hook_load_ex_a(LPCSTR name, HANDLE file, DWORD flags) {
  const std::wstring wide = widen_ansi(name);
  if ((flags & (LOAD_LIBRARY_AS_DATAFILE | LOAD_LIBRARY_AS_IMAGE_RESOURCE | LOAD_LIBRARY_AS_DATAFILE_EXCLUSIVE)) == 0) {
    if (const auto* replacement = replacement_for(wide)) return load_replacement(wide, *replacement, file, flags);
  }
  return g_state->load_ex_a(name, file, flags);
}
HMODULE WINAPI hook_load_ex_w(LPCWSTR name, HANDLE file, DWORD flags) {
  if ((flags & (LOAD_LIBRARY_AS_DATAFILE | LOAD_LIBRARY_AS_IMAGE_RESOURCE | LOAD_LIBRARY_AS_DATAFILE_EXCLUSIVE)) == 0) {
    if (const auto* replacement = replacement_for(name ? name : L"")) return load_replacement(name, *replacement, file, flags);
  }
  return g_state->load_ex_w(name, file, flags);
}

// ---- Sessions without a runtime: add-on folders left out of searches of garrysmod\addons.

bool addons_search(const std::wstring& pattern) {
  if (!g_state || g_state->hidden.empty() || pattern.empty()) return false;
  const std::wstring path = lower(full_path(pattern));
  const std::size_t slash = path.rfind(L'\\');
  return slash != std::wstring::npos && path.compare(0, slash, g_state->addons_folder) == 0 &&
         slash == g_state->addons_folder.size();
}

bool hidden_name(std::wstring_view name) {
  const std::wstring folded = lower(std::wstring(name));
  for (const auto& hidden : g_state->hidden) {
    if (hidden != folded) continue;
    const std::string text = narrow(folded);
    AcquireSRWLockExclusive(&g_state->lock);
    const bool first = std::find(g_state->hidden_seen.begin(), g_state->hidden_seen.end(), text) == g_state->hidden_seen.end();
    if (first) g_state->hidden_seen.push_back(text);
    ReleaseSRWLockExclusive(&g_state->lock);
    if (first) write_session_json();
    return true;
  }
  return false;
}

void track(HANDLE search) {
  AcquireSRWLockExclusive(&g_state->lock);
  g_state->searches.push_back(search);
  ReleaseSRWLockExclusive(&g_state->lock);
}

bool tracked(HANDLE search) {
  AcquireSRWLockShared(&g_state->lock);
  const bool found = std::find(g_state->searches.begin(), g_state->searches.end(), search) != g_state->searches.end();
  ReleaseSRWLockShared(&g_state->lock);
  return found;
}

// A first result that is hidden is replaced by the next one; when none is left, the search is
// closed and reports what an empty folder would (ERROR_FILE_NOT_FOUND).
template <typename Data, typename Next>
HANDLE first_visible(HANDLE search, Data* data, Next next, std::wstring_view (*name)(const Data*)) {
  while (hidden_name(name(data))) {
    if (!next(search, data)) {
      const DWORD error = GetLastError();
      g_state->find_close(search);
      SetLastError(error == ERROR_NO_MORE_FILES ? ERROR_FILE_NOT_FOUND : error);
      return INVALID_HANDLE_VALUE;
    }
  }
  track(search);
  return search;
}

std::wstring_view name_w(const WIN32_FIND_DATAW* data) { return data->cFileName; }

HANDLE WINAPI hook_find_first_a(LPCSTR pattern, LPWIN32_FIND_DATAA data) {
  const HANDLE search = g_state->find_first_a(pattern, data);
  if (search == INVALID_HANDLE_VALUE || !data || !addons_search(widen_ansi(pattern))) return search;
  while (hidden_name(widen_ansi(data->cFileName))) {
    if (!g_state->find_next_a(search, data)) {
      const DWORD error = GetLastError();
      g_state->find_close(search);
      SetLastError(error == ERROR_NO_MORE_FILES ? ERROR_FILE_NOT_FOUND : error);
      return INVALID_HANDLE_VALUE;
    }
  }
  track(search);
  return search;
}
HANDLE WINAPI hook_find_first_w(LPCWSTR pattern, LPWIN32_FIND_DATAW data) {
  const HANDLE search = g_state->find_first_w(pattern, data);
  if (search == INVALID_HANDLE_VALUE || !data || !addons_search(pattern ? pattern : L"")) return search;
  return first_visible(search, data, g_state->find_next_w, &name_w);
}
HANDLE WINAPI hook_find_first_ex_w(LPCWSTR pattern, FINDEX_INFO_LEVELS level, LPVOID data, FINDEX_SEARCH_OPS op, LPVOID filter,
                                   DWORD flags) {
  const HANDLE search = g_state->find_first_ex_w(pattern, level, data, op, filter, flags);
  if (search == INVALID_HANDLE_VALUE || !data || (level != FindExInfoStandard && level != FindExInfoBasic) ||
      !addons_search(pattern ? pattern : L""))
    return search;
  return first_visible(search, static_cast<WIN32_FIND_DATAW*>(data), g_state->find_next_w, &name_w);
}
BOOL WINAPI hook_find_next_a(HANDLE search, LPWIN32_FIND_DATAA data) {
  BOOL found = g_state->find_next_a(search, data);
  while (found && data && tracked(search) && hidden_name(widen_ansi(data->cFileName))) found = g_state->find_next_a(search, data);
  return found;
}
BOOL WINAPI hook_find_next_w(HANDLE search, LPWIN32_FIND_DATAW data) {
  BOOL found = g_state->find_next_w(search, data);
  while (found && data && tracked(search) && hidden_name(data->cFileName)) found = g_state->find_next_w(search, data);
  return found;
}
BOOL WINAPI hook_find_close(HANDLE search) {
  AcquireSRWLockExclusive(&g_state->lock);
  g_state->searches.erase(std::remove(g_state->searches.begin(), g_state->searches.end(), search), g_state->searches.end());
  ReleaseSRWLockExclusive(&g_state->lock);
  return g_state->find_close(search);
}

bool import_from_loader_dll(const char* dll) {
  const auto starts = [&](const char* prefix) { return _strnicmp(dll, prefix, std::strlen(prefix)) == 0; };
  return starts("kernel32") || starts("kernelbase") || starts("api-ms-win-core-libraryloader") || starts("api-ms-win-core-file");
}

int hook_imports_recorded(void* module, const char* function, void* replacement, std::vector<Hooked>* record) {
  auto* image = static_cast<std::uint8_t*>(module);
  const auto* dos = reinterpret_cast<const IMAGE_DOS_HEADER*>(image);
  if (!image || dos->e_magic != IMAGE_DOS_SIGNATURE) return 0;
  const auto* nt = reinterpret_cast<const IMAGE_NT_HEADERS64*>(image + dos->e_lfanew);
  if (nt->Signature != IMAGE_NT_SIGNATURE || nt->OptionalHeader.Magic != IMAGE_NT_OPTIONAL_HDR64_MAGIC) return 0;
  const auto& directory = nt->OptionalHeader.DataDirectory[IMAGE_DIRECTORY_ENTRY_IMPORT];
  if (!directory.VirtualAddress || !directory.Size) return 0;
  int changed = 0;
  for (auto* descriptor = reinterpret_cast<const IMAGE_IMPORT_DESCRIPTOR*>(image + directory.VirtualAddress);
       descriptor->Name; ++descriptor) {
    if (!import_from_loader_dll(reinterpret_cast<const char*>(image + descriptor->Name))) continue;
    const auto* names = reinterpret_cast<const IMAGE_THUNK_DATA64*>(
        image + (descriptor->OriginalFirstThunk ? descriptor->OriginalFirstThunk : descriptor->FirstThunk));
    auto* slots = reinterpret_cast<IMAGE_THUNK_DATA64*>(image + descriptor->FirstThunk);
    for (; names->u1.AddressOfData; ++names, ++slots) {
      if (IMAGE_SNAP_BY_ORDINAL64(names->u1.Ordinal)) continue;
      const auto* by_name = reinterpret_cast<const IMAGE_IMPORT_BY_NAME*>(image + names->u1.AddressOfData);
      if (std::strcmp(reinterpret_cast<const char*>(by_name->Name), function) != 0) continue;
      void** slot = reinterpret_cast<void**>(&slots->u1.Function);
      if (*slot == replacement) continue;
      DWORD previous = 0;
      if (!VirtualProtect(slot, sizeof(void*), PAGE_READWRITE, &previous)) continue;
      void* original = *slot;
      *slot = replacement;
      DWORD ignored = 0;
      VirtualProtect(slot, sizeof(void*), previous, &ignored);
      if (record) record->push_back({slot, original});
      ++changed;
    }
  }
  return changed;
}

void hook_loads(void* module) {
  if (g_state->overrides.empty()) return;
  hook_imports_recorded(module, "LoadLibraryA", reinterpret_cast<void*>(&hook_load_a), &g_state->hooked);
  hook_imports_recorded(module, "LoadLibraryW", reinterpret_cast<void*>(&hook_load_w), &g_state->hooked);
  hook_imports_recorded(module, "LoadLibraryExA", reinterpret_cast<void*>(&hook_load_ex_a), &g_state->hooked);
  hook_imports_recorded(module, "LoadLibraryExW", reinterpret_cast<void*>(&hook_load_ex_w), &g_state->hooked);
}

void hook_searches(void* module, const std::wstring& base_name) {
  if (g_state->hidden.empty() || lower(base_name) != kSearchModule) return;
  int changed = hook_imports_recorded(module, "FindFirstFileA", reinterpret_cast<void*>(&hook_find_first_a), &g_state->hooked);
  changed += hook_imports_recorded(module, "FindFirstFileW", reinterpret_cast<void*>(&hook_find_first_w), &g_state->hooked);
  changed += hook_imports_recorded(module, "FindFirstFileExW", reinterpret_cast<void*>(&hook_find_first_ex_w), &g_state->hooked);
  changed += hook_imports_recorded(module, "FindNextFileA", reinterpret_cast<void*>(&hook_find_next_a), &g_state->hooked);
  changed += hook_imports_recorded(module, "FindNextFileW", reinterpret_cast<void*>(&hook_find_next_w), &g_state->hooked);
  changed += hook_imports_recorded(module, "FindClose", reinterpret_cast<void*>(&hook_find_close), &g_state->hooked);
  AcquireSRWLockExclusive(&g_state->lock);
  g_state->search_hooked.push_back(narrow(lower(base_name)) + " (" + std::to_string(changed) + " imports)");
  ReleaseSRWLockExclusive(&g_state->lock);
}

bool game_module(const std::wstring& path) {
  return path.compare(0, g_state->root_prefix.size(), g_state->root_prefix) == 0 &&
         path.compare(0, g_state->loader_prefix.size(), g_state->loader_prefix) != 0;
}

void handle(void* base, const std::wstring& full_name, const std::wstring& base_name) {
  const std::wstring path = lower(full_name);
  if (!game_module(path)) return;
  bool changed = false;
  const std::string name = narrow(lower(base_name));
  for (const auto& set : g_state->setup.patch_sets) {
    if (set.module != name) continue;
    for (const auto& patch : set.patches) {
      auto result = patch::apply(base, name, patch);
      AcquireSRWLockExclusive(&g_state->lock);
      g_state->patches.push_back(std::move(result));
      ReleaseSRWLockExclusive(&g_state->lock);
      changed = true;
    }
  }
  if (!g_state->overrides.empty()) {
    hook_loads(base);
    AcquireSRWLockExclusive(&g_state->lock);
    g_state->modules_seen.push_back(name);
    ReleaseSRWLockExclusive(&g_state->lock);
  }
  if (!g_state->hidden.empty() && lower(base_name) == kSearchModule) {
    hook_searches(base, base_name);
    changed = true;
  }
  if (changed) write_session_json();
}

void handle_raw(const LdrData* data) noexcept {
  try {
    const std::wstring full(data->full_name->buffer, data->full_name->length / sizeof(wchar_t));
    const std::wstring base(data->base_name->buffer, data->base_name->length / sizeof(wchar_t));
    handle(data->base, full, base);
  } catch (...) {
  }
}

// No C++ objects in this frame: MSVC forbids unwinding in a function with __try.
VOID CALLBACK on_dll(ULONG reason, const LdrData* data, PVOID) {
  if (reason != kLoaded || !data || !data->full_name || !data->base_name || !g_state) return;
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

}  // namespace

int hook_imports(void* module, const char* function, void* replacement) {
  return hook_imports_recorded(module, function, replacement, nullptr);
}

bool install(Setup setup, std::string& error) {
  if (g_state) {
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
  auto state = std::make_unique<State>();
  state->load_a = reinterpret_cast<LoadA>(GetProcAddress(kernel32, "LoadLibraryA"));
  state->load_w = reinterpret_cast<LoadW>(GetProcAddress(kernel32, "LoadLibraryW"));
  state->load_ex_a = reinterpret_cast<LoadExA>(GetProcAddress(kernel32, "LoadLibraryExA"));
  state->load_ex_w = reinterpret_cast<LoadExW>(GetProcAddress(kernel32, "LoadLibraryExW"));
  if (!state->load_a || !state->load_w || !state->load_ex_a || !state->load_ex_w) {
    error = "LoadLibrary functions not found";
    return false;
  }
  const std::wstring root = lower(full_path(setup.root.native()));
  state->root_prefix = root.back() == L'\\' ? root : root + L'\\';
  state->loader_prefix = state->root_prefix + L"native-loader\\";
  state->bin_folder = state->root_prefix + L"bin\\win64";
  for (const auto& [module, file] : setup.overrides) {
    std::wstring wide(module.begin(), module.end());  // validated: [a-z0-9_]+.dll
    state->overrides.emplace_back(lower(wide), full_path(file.native()));
  }
  if (!setup.hidden_addons.empty()) {
    state->find_first_a = reinterpret_cast<FindFirstA>(GetProcAddress(kernel32, "FindFirstFileA"));
    state->find_first_w = reinterpret_cast<FindFirstW>(GetProcAddress(kernel32, "FindFirstFileW"));
    state->find_first_ex_w = reinterpret_cast<FindFirstExW>(GetProcAddress(kernel32, "FindFirstFileExW"));
    state->find_next_a = reinterpret_cast<FindNextA>(GetProcAddress(kernel32, "FindNextFileA"));
    state->find_next_w = reinterpret_cast<FindNextW>(GetProcAddress(kernel32, "FindNextFileW"));
    state->find_close = reinterpret_cast<FindCloseFn>(GetProcAddress(kernel32, "FindClose"));
    if (!state->find_first_a || !state->find_first_w || !state->find_first_ex_w || !state->find_next_a || !state->find_next_w ||
        !state->find_close) {
      error = "FindFirstFile functions not found";
      return false;
    }
    for (const auto& name : setup.hidden_addons) state->hidden.push_back(lower(std::wstring(name.begin(), name.end())));  // ASCII
    state->addons_folder = state->root_prefix + L"garrysmod\\addons";
  }
  state->setup = std::move(setup);
  g_state = state.release();

  // Modules mapped already (gmod.exe and whatever it imports) get their hooks now.
  const HANDLE snapshot = CreateToolhelp32Snapshot(TH32CS_SNAPMODULE, GetCurrentProcessId());
  if (snapshot != INVALID_HANDLE_VALUE) {
    MODULEENTRY32W entry{};
    entry.dwSize = sizeof(entry);
    for (BOOL more = Module32FirstW(snapshot, &entry); more; more = Module32NextW(snapshot, &entry)) {
      if (!game_module(lower(entry.szExePath))) continue;
      hook_loads(entry.modBaseAddr);
      hook_searches(entry.modBaseAddr, entry.szModule);
    }
    CloseHandle(snapshot);
  }
  const LONG status = reg(0, &on_dll, nullptr, &g_state->cookie);
  if (status < 0) {
    error = "LdrRegisterDllNotification failed (NTSTATUS " + std::to_string(static_cast<unsigned long>(status)) + ")";
    uninstall();
    return false;
  }
  g_state->unregister = unreg;
  write_session_json();
  return true;
}

void uninstall() noexcept {
  if (!g_state) return;
  if (g_state->cookie && g_state->unregister) g_state->unregister(g_state->cookie);
  for (auto it = g_state->hooked.rbegin(); it != g_state->hooked.rend(); ++it) {
    DWORD previous = 0;
    if (VirtualProtect(it->slot, sizeof(void*), PAGE_READWRITE, &previous)) {
      *it->slot = it->original;
      DWORD ignored = 0;
      VirtualProtect(it->slot, sizeof(void*), previous, &ignored);
    }
  }
  // Not freed: a hook may still be running on another thread; a few kilobytes stay allocated.
  g_state = nullptr;
}

std::string results_json() {
  if (!g_state) return "{}";
  AcquireSRWLockShared(&g_state->lock);
  std::string out = "{\n  \"schema\": 1,\n" + g_state->setup.session_json_base + "  \"patches\": [";
  for (std::size_t i = 0; i < g_state->patches.size(); ++i) out += (i ? ",\n    " : "\n    ") + patch_json(g_state->patches[i]);
  out += g_state->patches.empty() ? "],\n" : "\n  ],\n";
  out += "  \"overrides\": [";
  for (std::size_t i = 0; i < g_state->overrides_done.size(); ++i) out += (i ? ",\n    " : "\n    ") + g_state->overrides_done[i];
  out += g_state->overrides_done.empty() ? "],\n" : "\n  ],\n";
  const auto strings = [](const auto& items) {
    std::string list = "[";
    for (std::size_t i = 0; i < items.size(); ++i) list += (i ? ", " : "") + json::quote(items[i]);
    return list + "]";
  };
  std::vector<std::string> configured;
  for (const auto& name : g_state->hidden) configured.push_back(narrow(name));
  out += "  \"hidden_addons\": {\"folders\": " + strings(configured) + ", \"left_out\": " + strings(g_state->hidden_seen) +
         ", \"search_hooks\": " + strings(g_state->search_hooked) + "},\n";
  out += "  \"hooked_modules\": " + std::to_string(g_state->modules_seen.size()) + "\n}\n";
  ReleaseSRWLockShared(&g_state->lock);
  return out;
}

void write_session_json() noexcept {
  try {
    if (!g_state) return;
    const auto folder = fs::join(g_state->setup.root, status::kDirectory);
    if (!fs::stat(folder).directory) return;  // the start-up report creates it
    const auto text = results_json();
    fs::write_atomic(fs::win32(), fs::join(g_state->setup.root, "garrysmod/data/native-loader/session.json"), text);
  } catch (...) {
  }
}

}  // namespace nl::proxy::modules
