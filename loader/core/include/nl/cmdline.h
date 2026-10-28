#pragma once
// Reading and extending the process command line in memory (M4). The engine reads its command line
// after the EXE entry point, through kernelbase's GetCommandLineW/A (KERNEL32 forwards to them) and
// the PEB. The bootstrap, at the entry point, appends the runtime's launch arguments by pointing
// those caches at longer strings, so no relaunch and no IAT patching per module is needed. The
// parsing helpers are pure and testable; append_arguments() is Win32 and the bootstrap calls it.

#include <cstddef>
#include <cstdint>
#include <optional>
#include <string>
#include <string_view>
#include <vector>

namespace nl::cmdline {

// Splits a command line into arguments by the Windows CommandLineToArgvW rules (quotes, backslashes).
std::vector<std::wstring> tokenize(std::wstring_view line);

// Case-insensitive: is `token` one of the arguments of `line`? Used to skip a launch argument the
// user already passed (e.g. their own -dxlevel).
bool has_arg(std::wstring_view line, std::wstring_view token);

// A cached-pointer getter is `48 8b 05 <disp32> c3` (mov rax,[rip+disp32]; ret): it returns a
// pointer held at a fixed address. kernelbase's GetCommandLineW/A are built this way. Returns the
// 32-bit displacement if the eight bytes at `code` match, else nullopt.
std::optional<std::int32_t> cached_pointer_displacement(const unsigned char* code, std::size_t available);

// The address of the pointer such a getter returns, or nullptr if `getter` is not that shape.
// `max_scan` bounds how far it reads. Exposed for tests; append_arguments() uses it.
void** cached_pointer_slot(const void* getter, std::size_t max_scan = 16);

struct SwapResult {
  bool ok = false;
  std::string detail;  // when !ok, why nothing was changed, for the log
};

// Appends `extra_args` (ASCII) to the command line the process already has, so modules reading it
// later see them. Patches kernelbase's GetCommandLineW and GetCommandLineA caches and the PEB's
// command line. The new strings are allocated for the life of the process. Changes nothing and
// returns !ok if a getter is not the expected shape or does not point at this command line (then
// the caller falls back to documented launch options). An empty list is a successful no-op.
SwapResult append_arguments(const std::vector<std::string>& extra_args);

}  // namespace nl::cmdline
