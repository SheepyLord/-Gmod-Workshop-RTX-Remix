// Deliberately tiny host: the loader runs before this CRT/main, via the static import.
#include <windows.h>
#include <mmsystem.h>
#include <cstdio>

int wmain(int argc, wchar_t** argv) {
  if (argc < 3) return 2;
  FILETIME time{};
  GetSystemTimeAsFileTime(&time);
  const auto stamp = (static_cast<unsigned long long>(time.dwHighDateTime) << 32) | time.dwLowDateTime;
  char marker[256]{};
  const int length = std::snprintf(marker, sizeof(marker), "host_main_filetime=%llu\nlog_present_at_main=%d\ntimeGetTime=%lu\n",
                                    stamp, GetFileAttributesW(argv[2]) != INVALID_FILE_ATTRIBUTES, timeGetTime());
  const HANDLE file = CreateFileW(argv[1], GENERIC_WRITE, 0, nullptr, CREATE_ALWAYS, FILE_ATTRIBUTE_NORMAL, nullptr);
  if (file == INVALID_HANDLE_VALUE || length <= 0) return 3;
  DWORD written{};
  const bool ok = WriteFile(file, marker, static_cast<DWORD>(length), &written, nullptr) && written == static_cast<DWORD>(length);
  CloseHandle(file);
  return ok ? 0 : 4;
}
