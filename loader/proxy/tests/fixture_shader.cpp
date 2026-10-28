// M5 test fixture: stdshader_dx6.dll, both the "vanilla" copy in a synthetic bin\win64 and the
// package's replacement. The probe tells them apart by the path the module was loaded from.
#include <windows.h>

extern "C" __declspec(dllexport) int nl_m5_shader() { return 6; }
