// ADR 0024 test fixture: gmcl_nl_dep_win64.dll, a binary module with a static import of
// nl_dep_runtime_win64.dll, as Model Hotloader's modules import mmdhl_runtime_win64.dll.
extern "C" __declspec(dllimport) const char* nl_dep_runtime_name();

extern "C" __declspec(dllexport) const char* nl_dep_module_value() { return nl_dep_runtime_name(); }
