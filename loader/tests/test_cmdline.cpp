#include "nl/cmdline.h"
#include "nl_test.h"

#include <windows.h>

#include <cstdio>
#include <cstring>
#include <array>
#include <string>
#include <vector>

using namespace nl;

namespace {
std::vector<std::wstring> toks(std::wstring_view line) { return cmdline::tokenize(line); }

struct Records {
  wchar_t wide[4] = L"old";
  char ansi[4] = "old";
  wchar_t next_wide[10] = L"old extra";
  char next_ansi[10] = "old extra";
  std::array<cmdline::StringRecord, 3> slots{{{6, 8, 0x12345678, wide}, {3, 4, 0x87654321, ansi}, {6, 8, 0xabcdef12, wide}}};
  auto edits() {
    return std::array<cmdline::RecordChange, 3>{{
      {&slots[0], wide, 6, next_wide, 18, 2}, {&slots[1], ansi, 3, next_ansi, 9, 1},
      {&slots[2], wide, 6, next_wide, 18, 2}}};
  }
};

struct FailedWrite { unsigned calls = 0; unsigned at = 0; };
bool write_with_failure(cmdline::StringRecord* address, const cmdline::StringRecord& value, void* context) noexcept {
  auto& fault = *static_cast<FailedWrite*>(context);
  if (++fault.calls == fault.at) {
    address->buffer = value.buffer;  // fail after a partial write, which must also be undone
    return false;
  }
  std::memcpy(address, &value, sizeof(value));
  return true;
}
}  // namespace

TEST_CASE("cmdline: tokenize follows the Windows quoting and backslash rules") {
  CHECK(toks(L"  gmod.exe  -game   garrysmod ") == std::vector<std::wstring>({L"gmod.exe", L"-game", L"garrysmod"}));
  CHECK(toks(LR"("a b\c" -x)") == std::vector<std::wstring>({L"a b\\c", L"-x"}));
  CHECK(toks(LR"(a\\\"b)") == std::vector<std::wstring>({L"a\\\"b"}));          // 3 backslashes + quote -> \ + "
  CHECK(toks(LR"("a\\" b)") == std::vector<std::wstring>({L"a\\", L"b"}));       // 2 backslashes before the closing quote
  CHECK(toks(LR"("he said ""hi""")") == std::vector<std::wstring>({L"he said \"hi\""}));  // "" inside quotes
  CHECK(toks(L"").empty());
}

TEST_CASE("cmdline: has_arg is case-insensitive and whole-argument") {
  CHECK(cmdline::has_arg(L"gmod.exe -dxlevel 90", L"-dxlevel"));
  CHECK(cmdline::has_arg(L"gmod.exe -DXLevel 90", L"-dxlevel"));
  CHECK(cmdline::has_arg(LR"(gmod.exe "-nod3d9ex")", L"-nod3d9ex"));
  CHECK(!cmdline::has_arg(L"gmod.exe -dxlevelish", L"-dxlevel"));  // not a prefix match
  CHECK(!cmdline::has_arg(L"gmod.exe -game garrysmod", L"-dxlevel"));
}

TEST_CASE("cmdline: the cached-pointer getter shape is recognised and others refused") {
  const unsigned char good[] = {0x48, 0x8b, 0x05, 0x41, 0x08, 0x2b, 0x00, 0xc3};  // kernelbase GetCommandLineA shape
  const auto disp = cmdline::cached_pointer_displacement(good, sizeof(good));
  REQUIRE(disp.has_value());
  CHECK(*disp == 0x002b0841);
  const unsigned char not_mov[] = {0xff, 0x25, 0x00, 0x00, 0x00, 0x00, 0x00, 0xc3};  // jmp [rip] thunk (kernel32)
  CHECK(!cmdline::cached_pointer_displacement(not_mov, sizeof(not_mov)).has_value());
  const unsigned char no_ret[] = {0x48, 0x8b, 0x05, 0x00, 0x00, 0x00, 0x00, 0x90};  // ends in nop, not ret
  CHECK(!cmdline::cached_pointer_displacement(no_ret, sizeof(no_ret)).has_value());
  CHECK(!cmdline::cached_pointer_displacement(good, 7).has_value());  // too few bytes to be sure
}

TEST_CASE("cmdline: cached_pointer_slot resolves the RIP-relative address, with or without endbr64") {
  alignas(8) unsigned char buf[64] = {};
  void* marker = reinterpret_cast<void*>(0x1122334455667788ull);

  // mov rax,[rip+disp]; ret  at buf, pointing at the aligned slot buf+16.
  const std::int32_t disp = 16 - 7;  // slot - (address after the instruction)
  buf[0] = 0x48; buf[1] = 0x8b; buf[2] = 0x05;
  std::memcpy(buf + 3, &disp, sizeof(disp));
  buf[7] = 0xc3;
  std::memcpy(buf + 16, &marker, sizeof(marker));
  void** slot = cmdline::cached_pointer_slot(buf);
  REQUIRE(slot == reinterpret_cast<void**>(buf + 16));
  CHECK(*slot == marker);

  // endbr64 then the same getter at buf2+4, slot at buf2+24.
  alignas(8) unsigned char buf2[64] = {};
  buf2[0] = 0xf3; buf2[1] = 0x0f; buf2[2] = 0x1e; buf2[3] = 0xfa;
  const std::int32_t disp2 = 24 - (4 + 7);
  buf2[4] = 0x48; buf2[5] = 0x8b; buf2[6] = 0x05;
  std::memcpy(buf2 + 7, &disp2, sizeof(disp2));
  buf2[11] = 0xc3;
  std::memcpy(buf2 + 24, &marker, sizeof(marker));
  CHECK(cmdline::cached_pointer_slot(buf2) == reinterpret_cast<void**>(buf2 + 24));

  const unsigned char bad[16] = {0xff, 0x25};
  CHECK(cmdline::cached_pointer_slot(bad) == nullptr);
}

TEST_CASE("cmdline: appending no arguments changes nothing and succeeds") {
  const auto result = cmdline::append_arguments({});
  CHECK(result.ok);
}

TEST_CASE("cmdline: a swap updates all lengths and restores every original descriptor") {
  Records records;
  const auto before = records.slots;
  auto result = cmdline::swap_records(records.edits());
  REQUIRE(result.ok);
  CHECK(records.slots[0].buffer == records.next_wide);
  CHECK(records.slots[0].length == 18 && records.slots[0].maximum_length == 20);
  CHECK(records.slots[1].buffer == records.next_ansi);
  CHECK(records.slots[1].length == 9 && records.slots[1].maximum_length == 10);
  CHECK(records.slots[2].buffer == records.next_wide);
  CHECK(records.slots[2].length == 18 && records.slots[2].maximum_length == 20);
  CHECK(records.slots[0].reserved == before[0].reserved);
  CHECK(result.restore());
  CHECK(std::memcmp(records.slots.data(), before.data(), sizeof(before)) == 0);
  CHECK(result.restore());
}

TEST_CASE("cmdline: a later restore leaves a slot alone that something else has replaced since") {
  Records records;
  const auto before = records.slots;
  auto result = cmdline::swap_records(records.edits());
  REQUIRE(result.ok);
  wchar_t theirs[] = L"theirs";
  records.slots[0].buffer = theirs;  // e.g. another module repointed the PEB's command line
  CHECK(!result.restore());
  CHECK(records.slots[0].buffer == theirs);
  CHECK(std::memcmp(&records.slots[1], &before[1], sizeof(before[1])) == 0);
  CHECK(std::memcmp(&records.slots[2], &before[2], sizeof(before[2])) == 0);
  records.slots[0] = before[0];  // so the result's destructor has nothing left to do
}

TEST_CASE("cmdline: every descriptor is validated before any slot changes") {
  for (int invalid = 0; invalid < 3; ++invalid) {
    Records records;
    if (invalid == 0) records.slots[2].length = 4;
    if (invalid == 1) records.slots[2].maximum_length = 10;
    if (invalid == 2) records.slots[2].buffer = records.next_wide;
    const auto before = records.slots;
    FailedWrite writes;
    auto result = cmdline::swap_records(records.edits(), &write_with_failure, &writes);
    CHECK(!result.ok);
    CHECK(writes.calls == 0);
    CHECK(std::memcmp(records.slots.data(), before.data(), sizeof(before)) == 0);
  }
}

TEST_CASE("cmdline: failed writes roll back earlier and partially written slots") {
  for (unsigned at = 1; at <= 3; ++at) {
    Records records;
    const auto before = records.slots;
    FailedWrite fault{0, at};
    auto result = cmdline::swap_records(records.edits(), &write_with_failure, &fault);
    CHECK(!result.ok);
    CHECK(result.detail.find("all descriptors restored") != std::string::npos);
    CHECK(std::memcmp(records.slots.data(), before.data(), sizeof(before)) == 0);
  }
}

TEST_CASE("cmdline: USHORT checks include the terminator and unwinding restores the swap") {
  Records records;
  const auto before = records.slots;
  auto edits = records.edits();
  edits[0].replacement_bytes = 65534;  // the Unicode terminator would overflow MaximumLength
  CHECK(!cmdline::swap_records(edits).ok);
  CHECK(std::memcmp(records.slots.data(), before.data(), sizeof(before)) == 0);
  {
    auto result = cmdline::swap_records(records.edits());
    REQUIRE(result.ok);
  }
  CHECK(std::memcmp(records.slots.data(), before.data(), sizeof(before)) == 0);
}
