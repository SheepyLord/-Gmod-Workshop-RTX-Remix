// Real kernelbase/PEB round trip in its own process, never in the shared unit-test runner.
#include "nl/cmdline.h"
#include <windows.h>
#include <winternl.h>
#include <intrin.h>
#include <array>
#include <cstdio>
#include <cstring>
#include <string>

int main() {
  const auto kernelbase = GetModuleHandleW(L"kernelbase.dll");
  auto* wide_slot = nl::cmdline::cached_pointer_slot(reinterpret_cast<const void*>(GetProcAddress(kernelbase, "GetCommandLineW")));
  auto* ansi_slot = nl::cmdline::cached_pointer_slot(reinterpret_cast<const void*>(GetProcAddress(kernelbase, "GetCommandLineA")));
  auto* peb = reinterpret_cast<PEB*>(__readgsqword(0x60));
  if (!wide_slot || !ansi_slot || !peb || !peb->ProcessParameters) return 2;
  const std::wstring before_w = GetCommandLineW();
  const std::string before_a = GetCommandLineA();
  using nl::cmdline::StringRecord;
  const auto record_at = [](void** slot) {
    return reinterpret_cast<StringRecord*>(reinterpret_cast<unsigned char*>(slot) - offsetof(StringRecord, buffer));
  };
  const std::array<StringRecord*, 3> slots{record_at(wide_slot), record_at(ansi_slot),
      reinterpret_cast<StringRecord*>(&peb->ProcessParameters->CommandLine)};
  std::array<StringRecord, 3> before{};
  for (std::size_t i = 0; i < slots.size(); ++i) std::memcpy(&before[i], slots[i], sizeof(StringRecord));
  auto result = nl::cmdline::append_arguments({"-nl-test-flag", "7"});
  if (!result.ok) {
    std::printf("real command-line swap refused: %s\n", result.detail.c_str());
    return 3;
  }
  const std::wstring expected_w = before_w + L" -nl-test-flag 7";
  const std::string expected_a = before_a + " -nl-test-flag 7";
  if (GetCommandLineW() != expected_w || GetCommandLineA() != expected_a ||
      std::wstring(peb->ProcessParameters->CommandLine.Buffer) != expected_w) return 4;
  if (slots[0]->length != expected_w.size() * 2 || slots[0]->maximum_length != expected_w.size() * 2 + 2 ||
      slots[1]->length != expected_a.size() || slots[1]->maximum_length != expected_a.size() + 1 ||
      slots[2]->length != slots[0]->length || slots[2]->maximum_length != slots[0]->maximum_length) return 5;
  if (!result.restore()) return 6;
  for (std::size_t i = 0; i < slots.size(); ++i) if (std::memcmp(&before[i], slots[i], sizeof(StringRecord))) return 7;
  if (GetCommandLineW() != before_w || GetCommandLineA() != before_a) return 8;
  {
    auto scoped = nl::cmdline::append_arguments({"-nl-scope-test"});
    if (!scoped.ok) return 9;
  }
  if (GetCommandLineW() != before_w || GetCommandLineA() != before_a) return 10;
  for (std::size_t i = 0; i < slots.size(); ++i) if (std::memcmp(&before[i], slots[i], sizeof(StringRecord))) return 11;
  std::puts("kernelbase W/A and PEB swapped, lengths updated, exact original descriptors restored (explicit and scoped)");
  return 0;
}
