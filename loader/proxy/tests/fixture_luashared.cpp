// ADR 0024 test fixture: lua_shared.dll. Loads a binary module with LoadLibraryExA through its own
// import, as GMod's lua_shared.dll does for require(), so the bootstrap's import hook sees the load.
#include <windows.h>

#include <string>

namespace {
std::string g_text;
}  // namespace

// The loaded module's path and the value its export returns, "<path>|<value>"; "!<error>" if the load
// fails.
extern "C" __declspec(dllexport) const char* nl_dep_require(const char* path) {
  const HMODULE module = LoadLibraryExA(path, nullptr, 0);
  if (!module) return (g_text = "!" + std::to_string(GetLastError())).c_str();
  char name[MAX_PATH * 4]{};
  const DWORD length = GetModuleFileNameA(module, name, sizeof(name));
  const auto value = reinterpret_cast<const char* (*)()>(GetProcAddress(module, "nl_dep_module_value"));
  g_text = std::string(name, length) + "|" + (value ? value() : "");
  return g_text.c_str();
}
