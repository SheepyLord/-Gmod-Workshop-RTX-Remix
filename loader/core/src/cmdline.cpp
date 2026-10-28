#include "nl/cmdline.h"

#include <windows.h>
#include <winternl.h>

#include <cstring>
#include <cwchar>
#include <array>
#include <limits>
#include <intrin.h>

namespace nl::cmdline {
namespace {

wchar_t lower(wchar_t c) { return (c >= L'A' && c <= L'Z') ? static_cast<wchar_t>(c + (L'a' - L'A')) : c; }
bool whitespace(wchar_t c) { return c == L' ' || c == L'\t'; }

bool iequal(std::wstring_view a, std::wstring_view b) {
  if (a.size() != b.size()) return false;
  for (std::size_t i = 0; i < a.size(); ++i) {
    if (lower(a[i]) != lower(b[i])) return false;
  }
  return true;
}

static_assert(sizeof(StringRecord) == sizeof(UNICODE_STRING));
static_assert(offsetof(StringRecord, buffer) == offsetof(UNICODE_STRING, Buffer));

bool read_record(const StringRecord* address, StringRecord& record) noexcept {
  __try {
    std::memcpy(&record, address, sizeof(record));
    return true;
  } __except (EXCEPTION_EXECUTE_HANDLER) { return false; }
}

bool write_record(StringRecord* address, const StringRecord& value, void*) noexcept {
  DWORD previous = 0;
  if (!VirtualProtect(address, sizeof(value), PAGE_READWRITE, &previous)) return false;
  bool written = false;
  __try {
    std::memcpy(address, &value, sizeof(value));
    written = true;
  } __except (EXCEPTION_EXECUTE_HANDLER) { written = false; }
  DWORD ignored = 0;
  const bool protected_again = VirtualProtect(address, sizeof(value), previous, &ignored) != FALSE;
  return written && protected_again;
}

}  // namespace

struct SwapState {
  struct Saved {
    StringRecord* address;
    StringRecord before;
    StringRecord after;
    bool needs_restore = false;
  };
  std::vector<Saved> saved;
  RecordWriter writer = &write_record;
  void* context = nullptr;
  std::unique_ptr<wchar_t[]> wide;
  std::unique_ptr<char[]> ansi;
  bool published = false;  // a descriptor pointed at our strings at some point

  // `verify`: restore a slot only while it still holds our descriptor; something else may have
  // replaced it since, and writing the old one back would undo that change. The failure path inside
  // swap_records restores without checking: nothing else ran in between.
  bool restore(bool verify = true) noexcept {
    bool restored = true;
    for (auto it = saved.rbegin(); it != saved.rend(); ++it) {
      if (!it->needs_restore) continue;
      StringRecord current;
      if (verify && (!read_record(it->address, current) || current.buffer != it->after.buffer)) {
        restored = false;
        continue;
      }
      if (writer(it->address, it->before, context)) it->needs_restore = false;
      else restored = false;
    }
    return restored;
  }
  ~SwapState() {
    if (!restore()) OutputDebugStringW(L"Native Loader: command-line descriptor restoration failed.\n");
    if (published) {
      // Once published, other code may have kept a pointer from GetCommandLine* (DLL start-up code ran
      // in between). Never free these few bytes: a dangling command line would be far worse.
      wide.release();
      ansi.release();
    }
  }
};

SwapResult::SwapResult(bool success, std::string message) : ok(success), detail(std::move(message)) {}
SwapResult::~SwapResult() = default;
SwapResult::SwapResult(SwapResult&&) noexcept = default;
SwapResult& SwapResult::operator=(SwapResult&&) noexcept = default;
bool SwapResult::restore() noexcept { return !state_ || state_->restore(); }
void SwapResult::commit() noexcept {
  if (!ok || !state_) return;
  for (auto& change : state_->saved) change.needs_restore = false;
  state_->wide.release();
  state_->ansi.release();
  state_.reset();
}

SwapResult swap_records(std::span<const RecordChange> changes, RecordWriter writer, void* context) {
  SwapResult result;
  result.detail.reserve(192);  // no allocation after the first write
  result.state_ = std::make_unique<SwapState>();
  auto& state = *result.state_;
  state.writer = writer ? writer : &write_record;
  state.context = context;
  state.saved.reserve(changes.size());
  for (const auto& change : changes) {
    const auto width = change.terminator_bytes;
    constexpr auto maximum = std::numeric_limits<std::uint16_t>::max();
    if ((width != 1 && width != 2) || change.current_bytes > maximum - width ||
        change.replacement_bytes > maximum - width || change.current_bytes % width || change.replacement_bytes % width ||
        !change.record || !change.expected_buffer || !change.replacement) {
      result.detail = "command-line descriptor size or pointer is invalid (USHORT capacity includes the terminator)";
      return result;
    }
    StringRecord before;
    if (!read_record(change.record, before) || before.buffer != change.expected_buffer ||
        before.length != change.current_bytes || before.maximum_length != change.current_bytes + width) {
      result.detail = "command-line Buffer, Length or MaximumLength does not match the current string";
      return result;
    }
    auto after = before;
    after.buffer = change.replacement;
    after.length = static_cast<std::uint16_t>(change.replacement_bytes);
    after.maximum_length = static_cast<std::uint16_t>(change.replacement_bytes + width);
    state.saved.push_back({change.record, before, after, false});
  }
  for (auto& change : state.saved) {
    change.needs_restore = true;
    state.published = true;
    if (!state.writer(change.address, change.after, state.context)) {
      result.detail = state.restore(false) ? "command-line write failed; all descriptors restored" :
                                            "command-line write failed; descriptor restoration also failed";
      return result;
    }
  }
  result.ok = true;
  return result;
}

std::vector<std::wstring> tokenize(std::wstring_view line) {
  std::vector<std::wstring> args;
  std::size_t pos = 0;
  while (pos < line.size()) {
    while (pos < line.size() && whitespace(line[pos])) ++pos;
    if (pos == line.size()) break;
    std::wstring arg;
    bool quoted = false;
    while (pos < line.size() && (quoted || !whitespace(line[pos]))) {
      std::size_t slashes = 0;
      while (pos < line.size() && line[pos] == L'\\') { ++slashes; ++pos; }
      if (pos < line.size() && line[pos] == L'"') {
        arg.append(slashes / 2, L'\\');
        if (slashes % 2) {
          arg.push_back(L'"');  // an escaped quote
          ++pos;
        } else if (quoted && pos + 1 < line.size() && line[pos + 1] == L'"') {
          arg.push_back(L'"');  // "" inside quotes is a literal quote
          pos += 2;
        } else {
          quoted = !quoted;
          ++pos;
        }
      } else {
        arg.append(slashes, L'\\');
        if (pos < line.size() && (quoted || !whitespace(line[pos]))) arg.push_back(line[pos++]);
      }
    }
    args.push_back(std::move(arg));
  }
  return args;
}

bool has_arg(std::wstring_view line, std::wstring_view token) {
  for (const std::wstring& arg : tokenize(line)) {
    if (iequal(arg, token)) return true;
  }
  return false;
}

std::optional<std::int32_t> cached_pointer_displacement(const unsigned char* code, std::size_t available) {
  if (available < 8) return std::nullopt;
  if (code[0] == 0x48 && code[1] == 0x8b && code[2] == 0x05 && code[7] == 0xc3) {
    std::int32_t disp = 0;
    std::memcpy(&disp, code + 3, sizeof(disp));
    return disp;
  }
  return std::nullopt;
}

void** cached_pointer_slot(const void* getter, std::size_t max_scan) {
  const auto* code = static_cast<const unsigned char*>(getter);
  // The getter may begin with the CET endbr64 marker (f3 0f 1e fa); skip it if so.
  std::size_t offset = 0;
  if (max_scan >= 12 && code[0] == 0xf3 && code[1] == 0x0f && code[2] == 0x1e && code[3] == 0xfa) offset = 4;
  const auto disp = cached_pointer_displacement(code + offset, max_scan - offset);
  if (!disp) return nullptr;
  // RIP points at the next instruction: the ret at code+offset+7.
  return reinterpret_cast<void**>(const_cast<unsigned char*>(code) + offset + 7 + *disp);
}

SwapResult append_arguments(const std::vector<std::string>& extra_args) {
  if (extra_args.empty()) return {true, {}};
  std::string suffix;
  for (const std::string& arg : extra_args) {
    for (const unsigned char c : arg) {
      if (!c || c > 0x7f) return {false, "launch arguments must be ASCII without NUL"};
    }
    suffix.push_back(' ');
    suffix += arg;
  }
  const HMODULE kernelbase = GetModuleHandleW(L"kernelbase.dll");
  if (!kernelbase) return {false, "kernelbase.dll is not loaded"};
  auto* get_w = GetProcAddress(kernelbase, "GetCommandLineW");
  auto* get_a = GetProcAddress(kernelbase, "GetCommandLineA");
  if (!get_w || !get_a) return {false, "GetCommandLineW/A not exported by kernelbase"};
  void** slot_w = cached_pointer_slot(reinterpret_cast<const void*>(get_w));
  void** slot_a = cached_pointer_slot(reinterpret_cast<const void*>(get_a));
  if (!slot_w || !slot_a) return {false, "GetCommandLine is not the cached-pointer shape on this Windows build"};
  wchar_t* current_w = GetCommandLineW();
  char* current_a = GetCommandLineA();  // builds the ANSI cache if it was not built yet
  auto* peb = reinterpret_cast<PEB*>(__readgsqword(0x60));
  if (!peb || !peb->ProcessParameters) return {false, "the PEB command line is unavailable"};

  const std::wstring new_w = std::wstring(current_w) + std::wstring(suffix.begin(), suffix.end());
  const std::string new_a = std::string(current_a) + suffix;
  auto heap_w = std::make_unique<wchar_t[]>(new_w.size() + 1);
  std::memcpy(heap_w.get(), new_w.c_str(), (new_w.size() + 1) * sizeof(wchar_t));
  auto heap_a = std::make_unique<char[]>(new_a.size() + 1);
  std::memcpy(heap_a.get(), new_a.c_str(), new_a.size() + 1);
  const auto descriptor = [](void** slot) {
    return reinterpret_cast<StringRecord*>(reinterpret_cast<unsigned char*>(slot) - offsetof(StringRecord, buffer));
  };
  const std::array<RecordChange, 3> edits{{
    {descriptor(slot_w), current_w, std::wcslen(current_w) * sizeof(wchar_t), heap_w.get(), new_w.size() * sizeof(wchar_t), sizeof(wchar_t)},
    {descriptor(slot_a), current_a, std::strlen(current_a), heap_a.get(), new_a.size(), sizeof(char)},
    {reinterpret_cast<StringRecord*>(&peb->ProcessParameters->CommandLine), current_w,
     std::wcslen(current_w) * sizeof(wchar_t), heap_w.get(), new_w.size() * sizeof(wchar_t), sizeof(wchar_t)}
  }};
  auto result = swap_records(edits);
  // Keep buffers alive even if a failed write also encountered a rollback error.
  result.state_->wide = std::move(heap_w);
  result.state_->ansi = std::move(heap_a);
  return result;
}

}  // namespace nl::cmdline
