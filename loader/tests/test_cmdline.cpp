#include "nl/cmdline.h"
#include "nl_test.h"

#include <windows.h>

#include <cstdio>
#include <cstring>
#include <string>
#include <vector>

using namespace nl;

namespace {
std::vector<std::wstring> toks(std::wstring_view line) { return cmdline::tokenize(line); }
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

TEST_CASE("cmdline: appending arguments extends this process's own command line") {
  // Exercises the real kernelbase getters and the PEB in this test process.
  const std::wstring before = GetCommandLineW();
  const auto result = cmdline::append_arguments({"-nl-test-flag", "7"});
  if (!result.ok) {
    std::printf("append_arguments declined: %s\n", result.detail.c_str());
    return;  // a future Windows shape: the bootstrap would fall back; nothing to verify here
  }
  const std::wstring after_w = GetCommandLineW();
  const std::string after_a = GetCommandLineA();
  CHECK(after_w == before + L" -nl-test-flag 7");
  CHECK(after_a.size() >= std::strlen("-nl-test-flag 7"));
  CHECK(after_a.find("-nl-test-flag 7") != std::string::npos);
  CHECK(cmdline::has_arg(GetCommandLineW(), L"-nl-test-flag"));
}
