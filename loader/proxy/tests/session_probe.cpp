#include "session_probe.h"
#include "nl/fs.h"
#include "nl/json.h"
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
std::string call_text(HMODULE module, const char* name) {
  if (!module) return {};
  const auto function = reinterpret_cast<const char* (*)()>(GetProcAddress(module, name));
  return function ? std::string(function()) : std::string{};
}
}  // namespace

int session_probe(const wchar_t* output, const wchar_t* bin) {
  SetErrorMode(SEM_FAILCRITICALERRORS | SEM_NOGPFAULTERRORBOX);
  const std::filesystem::path folder(bin);
  // The engine loads its DLLs by full path; filesystem_stdio uses LoadLibraryExA with this flag.
  const HMODULE engine = LoadLibraryW((folder / L"engine.dll").c_str());
  const std::string shader_path = nl::fs::utf8(folder / L"stdshader_dx6.dll");
  const HMODULE shader = LoadLibraryExA(shader_path.c_str(), nullptr, LOAD_WITH_ALTERED_SEARCH_PATH);
  const DWORD shader_error = shader ? 0 : GetLastError();
  // GMod's add-on searches (ADR 0013): relative to the working directory (the game root) for the A
  // functions, absolute for the W ones; and a folder that is not garrysmod\addons.
  std::string addons_a, addons_w, other_a;
  if (const HMODULE filesystem = LoadLibraryW((folder / L"filesystem_stdio.dll").c_str())) {
    const auto list_a = reinterpret_cast<const char* (*)(const char*)>(GetProcAddress(filesystem, "nl_m5_list_a"));
    const auto list_w = reinterpret_cast<const char* (*)(const wchar_t*)>(GetProcAddress(filesystem, "nl_m5_list_w"));
    const auto root = folder.parent_path().parent_path();
    if (list_a) addons_a = list_a("garrysmod\\addons\\*");
    if (list_w) addons_w = list_w((root / L"garrysmod" / L"addons" / L"*").c_str());
    if (list_a) other_a = list_a("garrysmod\\cfg\\*");
  }
  std::string out = "{\n  \"process_id\": " + std::to_string(GetCurrentProcessId()) +
                    ",\n  \"command_line_w\": " + nl::json::quote(utf8(GetCommandLineW())) +
                    ",\n  \"engine_path\": " + nl::json::quote(module_path(engine)) +
                    ",\n  \"engine_at_attach\": " + nl::json::quote(call_text(engine, "nl_m5_at_attach")) +
                    ",\n  \"engine_now\": " + nl::json::quote(call_text(engine, "nl_m5_now")) +
                    ",\n  \"shader_path\": " + nl::json::quote(module_path(shader)) +
                    ",\n  \"shader_error\": " + std::to_string(shader_error) +
                    ",\n  \"addons_a\": " + nl::json::quote(addons_a) + ",\n  \"addons_w\": " + nl::json::quote(addons_w) +
                    ",\n  \"other_a\": " + nl::json::quote(other_a) + "\n}\n";
  std::ofstream(std::filesystem::path(output), std::ios::binary) << out;
  return 0;
}
