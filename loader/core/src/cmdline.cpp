#include "nl/cmdline.h"

#include <windows.h>
#include <winternl.h>

#include <cstring>
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

// Writes a pointer into kernelbase's writable data, making the page writable first and restoring it.
bool write_pointer(void** slot, void* value) {
  DWORD old = 0;
  if (!VirtualProtect(slot, sizeof(void*), PAGE_READWRITE, &old)) return false;
  *slot = value;
  DWORD ignored = 0;
  VirtualProtect(slot, sizeof(void*), old, &ignored);
  return true;
}

void update_peb(wchar_t* command_line, std::size_t length) {
  const std::size_t bytes = length * sizeof(wchar_t);
  if (bytes > 0xFFFE) return;  // a UNICODE_STRING length is a USHORT in bytes
  auto* peb = reinterpret_cast<PEB*>(__readgsqword(0x60));
  if (!peb || !peb->ProcessParameters) return;
  UNICODE_STRING& cl = peb->ProcessParameters->CommandLine;
  cl.Buffer = command_line;
  cl.Length = static_cast<USHORT>(bytes);
  cl.MaximumLength = static_cast<USHORT>(bytes + sizeof(wchar_t));
}

}  // namespace

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
  if (*slot_w != current_w) return {false, "the GetCommandLineW cache is not where expected"};
  if (*slot_a != current_a) return {false, "the GetCommandLineA cache is not where expected"};

  const std::wstring new_w = std::wstring(current_w) + std::wstring(suffix.begin(), suffix.end());
  const std::string new_a = std::string(current_a) + suffix;
  auto* heap_w = new wchar_t[new_w.size() + 1];  // read for the life of the process; never freed
  std::memcpy(heap_w, new_w.c_str(), (new_w.size() + 1) * sizeof(wchar_t));
  auto* heap_a = new char[new_a.size() + 1];
  std::memcpy(heap_a, new_a.c_str(), new_a.size() + 1);

  if (!write_pointer(slot_w, heap_w)) return {false, "could not write the GetCommandLineW cache"};
  if (!write_pointer(slot_a, heap_a)) return {false, "could not write the GetCommandLineA cache"};
  update_peb(heap_w, new_w.size());
  return {true, {}};
}

}  // namespace nl::cmdline
