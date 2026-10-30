// M5 test fixture: filesystem_stdio.dll. Lists a folder the two ways GMod's filesystem_stdio does
// (FindFirstFileA/FindNextFileA and FindFirstFileExW/FindNextFileW, through its own imports), so the
// probe can see which add-on folders the bootstrap leaves out (ADR 0013).
#include <windows.h>

#include <string>

namespace {
std::string g_text;

std::string utf8(const wchar_t* text) {
  const int size = WideCharToMultiByte(CP_UTF8, 0, text, -1, nullptr, 0, nullptr, nullptr);
  std::string out(static_cast<std::size_t>(size > 1 ? size - 1 : 0), '\0');
  if (size > 1) WideCharToMultiByte(CP_UTF8, 0, text, -1, out.data(), size, nullptr, nullptr);
  return out;
}

void add(const std::string& name) {
  if (name == "." || name == "..") return;
  g_text += (g_text.empty() ? "" : "|") + name;
}
}  // namespace

// Names in the folder `pattern` matches, joined with '|'; "!<error>" if the search fails at once.
extern "C" __declspec(dllexport) const char* nl_m5_list_a(const char* pattern) {
  g_text.clear();
  WIN32_FIND_DATAA data{};
  const HANDLE search = FindFirstFileA(pattern, &data);
  if (search == INVALID_HANDLE_VALUE) return (g_text = "!" + std::to_string(GetLastError())).c_str();
  do add(data.cFileName);
  while (FindNextFileA(search, &data));
  FindClose(search);
  return g_text.c_str();
}

extern "C" __declspec(dllexport) const char* nl_m5_list_w(const wchar_t* pattern) {
  g_text.clear();
  WIN32_FIND_DATAW data{};
  const HANDLE search = FindFirstFileExW(pattern, FindExInfoBasic, &data, FindExSearchNameMatch, nullptr, 0);
  if (search == INVALID_HANDLE_VALUE) return (g_text = "!" + std::to_string(GetLastError())).c_str();
  do add(utf8(data.cFileName));
  while (FindNextFileW(search, &data));
  FindClose(search);
  return g_text.c_str();
}

// Presentation tests exercise the real IAT slots, including a write-capable open that must pass
// through to the original file, and the sizes visible to GMod's path-based checks.
namespace {
const char* opened_path(HANDLE file) {
  g_text.clear();
  if (file == INVALID_HANDLE_VALUE) return g_text.c_str();
  wchar_t path[32768]{};
  if (GetFinalPathNameByHandleW(file, path, 32768, FILE_NAME_NORMALIZED)) g_text = utf8(path);
  CloseHandle(file);
  return g_text.c_str();
}
}
extern "C" __declspec(dllexport) const char* nl_display_open_a(const char* path, DWORD access, DWORD disposition) {
  return opened_path(CreateFileA(path, access, FILE_SHARE_READ | FILE_SHARE_WRITE | FILE_SHARE_DELETE,
                                nullptr, disposition, FILE_ATTRIBUTE_NORMAL, nullptr));
}
extern "C" __declspec(dllexport) const char* nl_display_open_w(const wchar_t* path, DWORD access, DWORD disposition) {
  return opened_path(CreateFileW(path, access, FILE_SHARE_READ | FILE_SHARE_WRITE | FILE_SHARE_DELETE,
                                nullptr, disposition, FILE_ATTRIBUTE_NORMAL, nullptr));
}
extern "C" __declspec(dllexport) unsigned long long nl_display_size_a(const char* path) {
  WIN32_FILE_ATTRIBUTE_DATA data{};
  return GetFileAttributesExA(path, GetFileExInfoStandard, &data) ?
      (static_cast<unsigned long long>(data.nFileSizeHigh) << 32) | data.nFileSizeLow : ~0ull;
}
extern "C" __declspec(dllexport) unsigned long long nl_display_size_w(const wchar_t* path) {
  WIN32_FILE_ATTRIBUTE_DATA data{};
  return GetFileAttributesExW(path, GetFileExInfoStandard, &data) ?
      (static_cast<unsigned long long>(data.nFileSizeHigh) << 32) | data.nFileSizeLow : ~0ull;
}
