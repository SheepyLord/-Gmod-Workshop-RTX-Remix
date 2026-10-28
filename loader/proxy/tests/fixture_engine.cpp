// M5 test fixture, copied into a synthetic game's bin\win64 as engine.dll. Its marker is what the
// test's patch set rewrites; DllMain copies it, so the probe can tell whether the patch was in place
// before this module's own code ran.
#include <windows.h>
#include <cstring>

extern "C" __declspec(dllexport) const char nl_m5_marker[] = "NLM5PATCH:BEFORE";
static char g_at_attach[sizeof(nl_m5_marker)];

BOOL WINAPI DllMain(HINSTANCE, DWORD reason, LPVOID) {
  if (reason == DLL_PROCESS_ATTACH) std::memcpy(g_at_attach, nl_m5_marker, sizeof(g_at_attach));
  return TRUE;
}

extern "C" __declspec(dllexport) const char* nl_m5_at_attach() { return g_at_attach; }
extern "C" __declspec(dllexport) const char* nl_m5_now() { return nl_m5_marker; }
