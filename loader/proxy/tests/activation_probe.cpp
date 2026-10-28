#include "activation_probe.h"
#include "nl/activate.h"
#include "nl/cmdline.h"
#include "nl/json.h"
#include "nl/fs.h"
#include <winternl.h>
#include <intrin.h>
#include <filesystem>
#include <fstream>
#include <string>

namespace {
std::string utf8(std::wstring_view text) { return nl::fs::utf8(std::filesystem::path(text)); }
std::string module_path(HMODULE module) {
  if (!module) return {};
  wchar_t buffer[32768]{};
  const auto length = GetModuleFileNameW(module, buffer, 32768);
  return length && length < 32768 ? utf8({buffer, length}) : std::string{};
}
DWORD probe_call(FARPROC address, int* value) noexcept {
  __try { *value = reinterpret_cast<int (*)()>(address)(); return 0; }
  __except (EXCEPTION_EXECUTE_HANDLER) { return GetExceptionCode(); }
}

// Test-only EXE TLS callback: runs after DLL attach but before the patched EXE entry point.
// It makes a descriptor invalid so the bootstrap must report fallback options and undo environment.
void NTAPI invalid_command_line(PVOID, DWORD reason, PVOID) {
  if (reason != DLL_PROCESS_ATTACH) return;
  SetErrorMode(SEM_FAILCRITICALERRORS | SEM_NOGPFAULTERRORBOX);
  wchar_t value[2]{};
  if (GetEnvironmentVariableW(L"NL_M4_BAD_CMDLINE", value, 2) != 1 || value[0] != L'1') return;
  const auto kernelbase = GetModuleHandleW(L"kernelbase.dll");
  auto* slot = nl::cmdline::cached_pointer_slot(reinterpret_cast<const void*>(GetProcAddress(kernelbase, "GetCommandLineW")));
  if (!slot) return;
  auto* record = reinterpret_cast<nl::cmdline::StringRecord*>(reinterpret_cast<unsigned char*>(slot) - 8);
  DWORD previous{};
  if (!VirtualProtect(record, sizeof(*record), PAGE_READWRITE, &previous)) return;
  record->maximum_length ^= 2;
  DWORD ignored{};
  VirtualProtect(record, sizeof(*record), previous, &ignored);
}
}  // namespace

#pragma section(".CRT$XLB", long, read)
extern "C" __declspec(allocate(".CRT$XLB")) PIMAGE_TLS_CALLBACK nl_m4_tls_callback = invalid_command_line;
#pragma comment(linker, "/INCLUDE:_tls_used")
#pragma comment(linker, "/INCLUDE:nl_m4_tls_callback")

int activation_probe(const wchar_t* output, const FILETIME& entered_main) {
  SetErrorMode(SEM_FAILCRITICALERRORS | SEM_NOGPFAULTERRORBOX);
  const bool preloaded = GetModuleHandleW(L"d3d9.dll") != nullptr;
  const auto vulkan = module_path(GetModuleHandleW(L"vulkan-1.dll"));
  const auto game_root = std::filesystem::path(output).parent_path();
  const bool status_at_main = GetFileAttributesW((game_root / L"garrysmod/data/native-loader/status.json").c_str()) != INVALID_FILE_ATTRIBUTES;
  wchar_t dll_directory[32768]{};
  GetDllDirectoryW(32768, dll_directory);
  const std::wstring command_w = GetCommandLineW();
  const std::string command_a = GetCommandLineA();
  const auto* peb = reinterpret_cast<PEB*>(__readgsqword(0x60));
  const std::wstring command_peb = peb->ProcessParameters->CommandLine.Buffer;
  const int ansi_size = WideCharToMultiByte(CP_ACP, 0, command_w.data(), static_cast<int>(command_w.size()), nullptr, 0, nullptr, nullptr);
  std::string expected_a(static_cast<std::size_t>(ansi_size), '\0');
  WideCharToMultiByte(CP_ACP, 0, command_w.data(), static_cast<int>(command_w.size()), expected_a.data(), ansi_size, nullptr, nullptr);
  const HMODULE runtime = LoadLibraryW(L"d3d9.dll");
  const auto entry = runtime ? GetProcAddress(runtime, "nl_m4_probe") : nullptr;
  int value{};
  const DWORD delay_error = entry ? probe_call(entry, &value) : 0;
  std::string text = "{\"process_id\":" + std::to_string(GetCurrentProcessId()) +
      ",\"host_main_filetime\":" + std::to_string((static_cast<unsigned long long>(entered_main.dwHighDateTime) << 32) | entered_main.dwLowDateTime) +
      ",\"preloaded\":" + (preloaded ? "true" : "false") + ",\"status_at_main\":" + (status_at_main ? "true" : "false") +
      ",\"runtime_path\":" + nl::json::quote(module_path(runtime)) + ",\"fake_probe\":" + std::to_string(value) +
      ",\"vulkan_path\":" + nl::json::quote(vulkan) +
      ",\"delay_error\":" + std::to_string(delay_error) +
      ",\"static_dependency\":" + nl::json::quote(module_path(GetModuleHandleW(L"nl_m4_static.dll"))) +
      ",\"delay_dependency\":" + nl::json::quote(module_path(GetModuleHandleW(L"nl_m4_delay.dll"))) +
      ",\"dll_directory\":" + nl::json::quote(utf8(dll_directory)) +
      ",\"command_line_w\":" + nl::json::quote(utf8(command_w)) +
      ",\"command_line_peb\":" + nl::json::quote(utf8(command_peb)) +
      ",\"ansi_matches_wide\":" + (command_a == expected_a ? "true" : "false") + ",\"environment\":{";
  bool first = true;
  for (const char* name : {"DXVK_RTX_CONFIG_FILE", "DXVK_CONFIG_FILE", "RTX_TEST", "DXVK_LOG_LEVEL"}) {
    if (!first) text += ',';
    first = false;
    const auto environment = nl::activate::environment_value(name);
    text += nl::json::quote(name) + ':' + (environment ? nl::json::quote(*environment) : "null");
  }
  text += "}}\n";
  std::ofstream file(std::filesystem::path(output), std::ios::binary);
  file << text;
  file.close();
  if (runtime) FreeLibrary(runtime);
  return file ? 0 : 12;
}
