#pragma once
#include <windows.h>
#include "activation.h"
#include "generated/exports.h"

namespace nl::proxy {
inline constexpr DWORD kPathCapacity = 32768;
struct BootstrapState {
  wchar_t exe[kPathCapacity]{};
  wchar_t module[kPathCapacity]{};
  wchar_t root[kPathCapacity]{};
  wchar_t system_winmm[kPathCapacity]{};
  wchar_t log_path[kPathCapacity]{};
  Activation activation{};
  DWORD system_load_error{};
  std::size_t resolved_exports{};
  bool missing_exports[kExportCount]{};
};
extern BootstrapState g_bootstrap;
void startup_guarded() noexcept;
void emergency_log(const char* message, DWORD error) noexcept;
}  // namespace nl::proxy
