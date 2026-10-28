#include "bootstrap.h"
#include "nl/version.h"
#include <cstdio>
#include <filesystem>
#include <sstream>
#include <stdexcept>
#include <string>
#include <system_error>

namespace nl::proxy {
namespace {
std::string utf8(std::wstring_view value) {
  if (value.empty()) return {};
  const int size = WideCharToMultiByte(CP_UTF8, 0, value.data(), static_cast<int>(value.size()), nullptr, 0, nullptr, nullptr);
  if (!size) throw std::runtime_error("UTF-8 conversion failed");
  std::string result(static_cast<std::size_t>(size), '\0');
  if (!WideCharToMultiByte(CP_UTF8, 0, value.data(), static_cast<int>(value.size()), result.data(), size, nullptr, nullptr))
    throw std::runtime_error("UTF-8 conversion failed");
  return result;
}

void write_log() {
  LARGE_INTEGER begin{}, frequency{};
  QueryPerformanceCounter(&begin);
  QueryPerformanceFrequency(&frequency);
  FILETIME filetime{};
  GetSystemTimeAsFileTime(&filetime);
  const auto startup_time = (static_cast<unsigned long long>(filetime.dwHighDateTime) << 32) | filetime.dwLowDateTime;
  // Sample these before the logging/filesystem work.
  const bool engine = GetModuleHandleW(L"engine.dll") != nullptr;
  const bool shaderapi = GetModuleHandleW(L"shaderapidx9.dll") != nullptr;
  const bool d3d9 = GetModuleHandleW(L"d3d9.dll") != nullptr;
  const std::filesystem::path log_path(g_bootstrap.log_path);
  std::filesystem::create_directories(log_path.parent_path());
  for (int index = 5; index >= 1; --index) {
    const auto destination = std::filesystem::path(log_path.wstring() + L"." + std::to_wstring(index));
    const auto source = index == 1 ? log_path : std::filesystem::path(log_path.wstring() + L"." + std::to_wstring(index - 1));
    if (index == 5) std::filesystem::remove(destination);
    if (std::filesystem::exists(source)) std::filesystem::rename(source, destination);
  }
  SYSTEMTIME utc{};
  GetSystemTime(&utc);
  char timestamp[40]{};
  std::snprintf(timestamp, sizeof(timestamp), "%04u-%02u-%02uT%02u:%02u:%02u.%03uZ",
                utc.wYear, utc.wMonth, utc.wDay, utc.wHour, utc.wMinute, utc.wSecond, utc.wMilliseconds);
  wchar_t working_directory[kPathCapacity]{};
  const DWORD cwd_length = GetCurrentDirectoryW(kPathCapacity, working_directory);
  std::ostringstream log;
  log << "native_loader_version=" NL_VERSION_STRING "\nutc=" << timestamp
      << "\nprocess_id=" << GetCurrentProcessId()
      << "\nphase=exe_entry_point\nentry_point_restored=1\nstartup_filetime=" << startup_time
      << "\nexe_path=" << utf8(g_bootstrap.exe) << "\ngame_root=" << utf8(g_bootstrap.root)
      << "\nworking_directory=" << (cwd_length && cwd_length < kPathCapacity ? utf8(working_directory) : "<unavailable>")
      << "\ncommand_line=" << utf8(GetCommandLineW())
      << "\nhost_matches=" << g_bootstrap.activation.host_matches
      << "\noff_switch.command_line=" << g_bootstrap.activation.command_line_disabled
      << "\noff_switch.environment=" << g_bootstrap.activation.environment_disabled
      << "\noff_switch.disable_file=" << g_bootstrap.activation.file_disabled
      << "\nsystem_winmm=" << utf8(g_bootstrap.system_winmm)
      << "\nsystem_winmm.load_error=" << g_bootstrap.system_load_error
      << "\nexports.resolved=" << g_bootstrap.resolved_exports << "\nexports.total=" << kExportCount
      << "\nmodule.engine.dll=" << engine << "\nmodule.shaderapidx9.dll=" << shaderapi << "\nmodule.d3d9.dll=" << d3d9 << '\n';
  for (std::size_t i = 0; i < kExportCount; ++i) {
    if (g_bootstrap.missing_exports[i]) log << "missing_export=" << (kExports[i].name ? kExports[i].name : "<ordinal-only>")
                                          << " @" << kExports[i].ordinal << " (zero-return stub)\n";
  }
  LARGE_INTEGER end{};
  QueryPerformanceCounter(&end);
  log << "startup.complete=1\nelapsed_ms=" << (frequency.QuadPart ? (end.QuadPart - begin.QuadPart) * 1000.0 / frequency.QuadPart : 0.0) << '\n';
  const auto text = log.str();
  const HANDLE file = CreateFileW(log_path.c_str(), GENERIC_WRITE, FILE_SHARE_READ, nullptr, CREATE_ALWAYS, FILE_ATTRIBUTE_NORMAL, nullptr);
  if (file == INVALID_HANDLE_VALUE) throw std::system_error(static_cast<int>(GetLastError()), std::system_category(), "open loader.log");
  DWORD written{};
  const bool success = WriteFile(file, text.data(), static_cast<DWORD>(text.size()), &written, nullptr) && written == text.size();
  const DWORD error = success ? ERROR_SUCCESS : GetLastError();
  CloseHandle(file);
  if (!success) throw std::system_error(static_cast<int>(error), std::system_category(), "write loader.log");
}

// Separate C++ and SEH frames: MSVC forbids destructors in an __try function.
void startup_cxx() noexcept {
  try {
    write_log();
  } catch (const std::exception&) {
    emergency_log("startup C++ exception; continuing into game", 0);
  } catch (...) {
    emergency_log("startup unknown C++ exception; continuing into game", 0);
  }
}
}  // namespace

void emergency_log(const char* message, DWORD error) noexcept {
  char buffer[256]{};
  const int length = std::snprintf(buffer, sizeof(buffer), "failure=%s error=0x%08lx\n", message, error);
  OutputDebugStringA(buffer);
  if (!g_bootstrap.log_path[0] || length <= 0 || static_cast<std::size_t>(length) >= sizeof(buffer)) return;
  const HANDLE file = CreateFileW(g_bootstrap.log_path, FILE_APPEND_DATA, FILE_SHARE_READ | FILE_SHARE_WRITE, nullptr, OPEN_ALWAYS, FILE_ATTRIBUTE_NORMAL, nullptr);
  if (file == INVALID_HANDLE_VALUE) return;
  DWORD written{};
  WriteFile(file, buffer, static_cast<DWORD>(length), &written, nullptr);
  CloseHandle(file);
}

void startup_guarded() noexcept {
  __try {
    startup_cxx();
  } __except (EXCEPTION_EXECUTE_HANDLER) {
    emergency_log("startup SEH fault; continuing into game", GetExceptionCode());
  }
}
}  // namespace nl::proxy
