// ADR 0024 test fixture: nl_dep_runtime_win64.dll, the runtime a binary module imports by name. It is
// deployed to garrysmod\lua\bin only, where Windows does not look for a module's static imports.
extern "C" __declspec(dllexport) const char* nl_dep_runtime_name() { return "nl-dep-runtime"; }
