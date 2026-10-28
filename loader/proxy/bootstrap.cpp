#include "bootstrap.h"
#include <cstdint>
#include <cstring>

extern "C" {
FARPROC nl_forward_table[nl::proxy::kExportCount]{};
}

namespace nl::proxy {
BootstrapState g_bootstrap;
namespace {
constexpr SIZE_T kPatchSize = 14;
using EntryPoint = std::uintptr_t(WINAPI*)(void*);
unsigned char* g_entry{};
unsigned char g_saved_entry[kPatchSize]{};

INT_PTR WINAPI missing_export() noexcept { return 0; }

bool append_path(wchar_t* destination, std::wstring_view base, std::wstring_view suffix) noexcept {
  if (base.size() + suffix.size() >= kPathCapacity) return false;
  std::memmove(destination, base.data(), base.size() * sizeof(wchar_t));
  std::memcpy(destination + base.size(), suffix.data(), suffix.size() * sizeof(wchar_t));
  destination[base.size() + suffix.size()] = L'\0';
  return true;
}

void resolve_exports() noexcept {
  for (auto& address : nl_forward_table) address = &missing_export;
  const UINT length = GetSystemDirectoryW(g_bootstrap.system_winmm, kPathCapacity);
  HMODULE system{};
  if (length && length < kPathCapacity &&
      append_path(g_bootstrap.system_winmm, {g_bootstrap.system_winmm, length}, L"\\winmm.dll")) {
    // Never load by base name: that would return this proxy and recurse.
    system = LoadLibraryW(g_bootstrap.system_winmm);
  }
  if (!system) g_bootstrap.system_load_error = GetLastError();
  for (std::size_t i = 0; i < kExportCount; ++i) {
    const auto& spec = kExports[i];
    const auto address = system ? GetProcAddress(system, spec.name ? spec.name : MAKEINTRESOURCEA(spec.ordinal)) : nullptr;
    if (address) {
      nl_forward_table[i] = address;
      ++g_bootstrap.resolved_exports;
    } else {
      g_bootstrap.missing_exports[i] = true;
    }
  }
  if (g_bootstrap.resolved_exports != kExportCount) OutputDebugStringW(L"Native Loader: unresolved winmm exports use zero-return stubs.\n");
  // This reference lives for the process lifetime, like the static winmm import.
}

bool restore_entry() noexcept {
  DWORD old_protection{};
  if (!VirtualProtect(g_entry, kPatchSize, PAGE_EXECUTE_READWRITE, &old_protection)) {
    // The Windows debugger write path can recover if the protection call failed.
    SIZE_T written{};
    if (!WriteProcessMemory(GetCurrentProcess(), g_entry, g_saved_entry, kPatchSize, &written) || written != kPatchSize) return false;
    return FlushInstructionCache(GetCurrentProcess(), g_entry, kPatchSize) != FALSE;
  }
  std::memcpy(g_entry, g_saved_entry, kPatchSize);
  DWORD ignored{};
  const bool protected_again = VirtualProtect(g_entry, kPatchSize, old_protection, &ignored) != FALSE;
  const bool flushed = FlushInstructionCache(GetCurrentProcess(), g_entry, kPatchSize) != FALSE;
  // This helper is also used for rollback in DllMain, where file writes are forbidden.
  if (!protected_again) OutputDebugStringW(L"Native Loader: entry protection restore failed.\n");
  return flushed;
}

std::uintptr_t WINAPI entry_hook(void* argument) noexcept {
  // Restore before running any loader work. Calling the patched entry would recurse.
  if (!restore_entry()) {
    emergency_log("cannot restore executable entry point", GetLastError());
    TerminateProcess(GetCurrentProcess(), ERROR_INVALID_ACCESS);
    return ERROR_INVALID_ACCESS;
  }
  startup_guarded();
  return reinterpret_cast<EntryPoint>(g_entry)(argument);
}

bool install_hook() noexcept {
  // PE header reads and the tiny write are guarded, with no C++ unwinding here.
  __try {
    auto* base = reinterpret_cast<unsigned char*>(GetModuleHandleW(nullptr));
    const auto* dos = reinterpret_cast<const IMAGE_DOS_HEADER*>(base);
    if (!base || dos->e_magic != IMAGE_DOS_SIGNATURE || dos->e_lfanew <= 0 || dos->e_lfanew > 1024 * 1024) return false;
    const auto* nt = reinterpret_cast<const IMAGE_NT_HEADERS64*>(base + dos->e_lfanew);
    if (nt->Signature != IMAGE_NT_SIGNATURE || nt->FileHeader.Machine != IMAGE_FILE_MACHINE_AMD64 ||
        nt->OptionalHeader.Magic != IMAGE_NT_OPTIONAL_HDR64_MAGIC) return false;
    const DWORD rva = nt->OptionalHeader.AddressOfEntryPoint;
    if (!rva || rva >= nt->OptionalHeader.SizeOfImage || nt->OptionalHeader.SizeOfImage - rva < kPatchSize) return false;
    g_entry = base + rva;
    std::memcpy(g_saved_entry, g_entry, kPatchSize);
    unsigned char jump[kPatchSize] = {0xff, 0x25, 0, 0, 0, 0};
    const auto destination = reinterpret_cast<std::uintptr_t>(&entry_hook);
    std::memcpy(jump + 6, &destination, sizeof(destination));
    DWORD old_protection{};
    if (!VirtualProtect(g_entry, kPatchSize, PAGE_EXECUTE_READWRITE, &old_protection)) return false;
    std::memcpy(g_entry, jump, kPatchSize);
    DWORD ignored{};
    const bool protected_again = VirtualProtect(g_entry, kPatchSize, old_protection, &ignored) != FALSE;
    const bool flushed = FlushInstructionCache(GetCurrentProcess(), g_entry, kPatchSize) != FALSE;
    if (!protected_again || !flushed) {
      restore_entry();
      return false;
    }
    return true;
  } __except (EXCEPTION_EXECUTE_HANDLER) {
    return false;
  }
}

void attach(HMODULE module) noexcept {
  resolve_exports();
  const auto exe_length = GetModuleFileNameW(nullptr, g_bootstrap.exe, kPathCapacity);
  const auto dll_length = GetModuleFileNameW(module, g_bootstrap.module, kPathCapacity);
  if (!exe_length || exe_length >= kPathCapacity || !dll_length || dll_length >= kPathCapacity) return;
  const auto root = game_root({g_bootstrap.exe, exe_length});
  if (root.empty() || !append_path(g_bootstrap.root, root, L"")) return;
  wchar_t environment[4]{};
  const auto env_length = GetEnvironmentVariableW(L"NATIVE_LOADER_DISABLE", environment, 4);
  const std::wstring_view env = env_length && env_length < 4 ? std::wstring_view(environment, env_length) : std::wstring_view{};
  wchar_t disable_path[kPathCapacity]{};
  if (!append_path(disable_path, root, L"\\native-loader\\disable")) return;
  const bool disabled_file = GetFileAttributesW(disable_path) != INVALID_FILE_ATTRIBUTES;
  g_bootstrap.activation = should_activate({g_bootstrap.exe, exe_length}, {g_bootstrap.module, dll_length},
                                           GetCommandLineW(), env, disabled_file);
  if (!g_bootstrap.activation.active()) return;
  if (!append_path(g_bootstrap.log_path, root, L"\\native-loader\\logs\\loader.log")) return;
  if (!install_hook()) OutputDebugStringW(L"Native Loader: entry hook unavailable; continuing as pass-through.\n");
}
}  // namespace
}  // namespace nl::proxy

BOOL WINAPI DllMain(HINSTANCE module, DWORD reason, LPVOID) {
  if (reason == DLL_PROCESS_ATTACH) nl::proxy::attach(module);
  // Keep static CRT thread notifications; no workers, waits or writes under loader lock.
  return TRUE;
}
