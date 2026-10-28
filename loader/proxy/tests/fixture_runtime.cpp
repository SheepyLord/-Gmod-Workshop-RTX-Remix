#include <windows.h>
extern "C" __declspec(dllimport) int nl_m4_static_value();
extern "C" __declspec(dllimport) int nl_m4_delay_value();
extern "C" __declspec(dllexport) int nl_m4_probe() { return nl_m4_static_value() + nl_m4_delay_value(); }
BOOL WINAPI DllMain(HINSTANCE, DWORD reason, LPVOID) {
  if (reason == DLL_PROCESS_ATTACH) {
    wchar_t fail[2]{};
    if (GetEnvironmentVariableW(L"NL_M4_FAIL_ATTACH", fail, 2) == 1 && fail[0] == L'1') return FALSE;
    if (GetEnvironmentVariableW(L"NL_M4_SEH_ATTACH", fail, 2) == 1 && fail[0] == L'1') RaiseException(0xE0424242, 0, 0, nullptr);
  }
  return TRUE;
}
