#pragma once
// Reading and extending the process command line in memory (M4). The engine reads its command line
// after the EXE entry point, through kernelbase's GetCommandLineW/A (KERNEL32 forwards to them) and
// the PEB. The bootstrap, at the entry point, appends the runtime's launch arguments by pointing
// those caches at longer strings, so no relaunch and no IAT patching per module is needed. The
// parsing helpers are pure and testable; append_arguments() is Win32 and the bootstrap calls it.

#include <cstddef>
#include <cstdint>
#include <optional>
#include <memory>
#include <span>
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

// x64 UNICODE_STRING/ANSI_STRING layout; reserved is their four bytes of padding, preserved exactly.
struct StringRecord {
  std::uint16_t length = 0;
  std::uint16_t maximum_length = 0;
  std::uint32_t reserved = 0;
  void* buffer = nullptr;
};

struct RecordChange {
  StringRecord* record = nullptr;
  const void* expected_buffer = nullptr;
  std::size_t current_bytes = 0;
  void* replacement = nullptr;
  std::size_t replacement_bytes = 0;
  std::size_t terminator_bytes = 0;  // 1 (ANSI) or 2 (Unicode)
};

// A false return may have changed the record: restore it and every earlier attempted write.
using RecordWriter = bool (*)(StringRecord*, const StringRecord&, void*) noexcept;
struct SwapState;

class SwapResult {
 public:
  SwapResult(bool success = false, std::string message = {});
  ~SwapResult();
  SwapResult(SwapResult&&) noexcept;
  SwapResult& operator=(SwapResult&&) noexcept;
  SwapResult(const SwapResult&) = delete;
  SwapResult& operator=(const SwapResult&) = delete;

  bool ok = false;
  std::string detail;  // when !ok, why nothing was changed, for the log

  // Safe to call repeatedly; restores every original descriptor, including lengths.
  bool restore() noexcept;
  // Retain successful buffers for process lifetime. Otherwise destruction restores automatically.
  void commit() noexcept;

 private:
  std::unique_ptr<SwapState> state_;
  friend SwapResult swap_records(std::span<const RecordChange>, RecordWriter, void*);
  friend SwapResult append_arguments(const std::vector<std::string>&);
};

// Validates every pointer/Length/MaximumLength and both old/new USHORT bounds before any write.
// Used by append_arguments and synthetic tests; the caller owns replacement storage here.
SwapResult swap_records(std::span<const RecordChange> changes, RecordWriter writer = nullptr, void* context = nullptr);

// Appends `extra_args` (ASCII) to the command line the process already has, so modules reading it
// later see them. Patches kernelbase's GetCommandLineW and GetCommandLineA caches and the PEB's
// command line. The result owns the new strings until restored or committed for process lifetime.
// Changes nothing and
// returns !ok if a getter is not the expected shape or does not point at this command line (then
// the caller falls back to documented launch options). An empty list is a successful no-op.
SwapResult append_arguments(const std::vector<std::string>& extra_args);

}  // namespace nl::cmdline
