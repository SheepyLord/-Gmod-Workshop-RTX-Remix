#include "nl_test.h"
#include "backend.h"
#include "nl/cmdline.h"
#include <Windows.h>
#include <winternl.h>
#include <intrin.h>
#include <array>
#include <cstring>

using namespace nl;

TEST_CASE("backend: no selector, unrelated text and RTX-off starts stay unchanged") {
  for (const auto line : {L"gmod.exe -console", L"gmod.exe +name \"-shaderapi shaderapidx11\"",
                          L"gmod.exe -shaderapi_extra shaderapidx11", L"\"-shaderapi\" -console"}) {
    const auto result = proxy::backend::select(line, true);
    CHECK(!result.changed);
    CHECK(result.line == line);
  }
  const std::wstring custom = LR"(gmod.exe -shaderapi "C:\FX mods\shaderapidx11.dll" -console)";
  const auto off = proxy::backend::select(custom, false);
  CHECK(!off.changed && off.line == custom && off.explicit_choices == 0);
  CHECK(!proxy::backend::select(L"gmod.exe -shaderapi shaderapidx9", true).changed);
}

TEST_CASE("backend: case, duplicate choices, assignment and quoted paths all choose stock D3D9") {
  const auto result = proxy::backend::select(
      LR"(gmod.exe "-ShAdErApI" "C:\FX mods\shaderapidx11.dll" -shaderapi shaderapigl -SHADERAPI=other.dll +exec keep.cfg)", true);
  CHECK(result.changed && result.explicit_choices == 3);
  CHECK(result.line == L"gmod.exe -shaderapi shaderapidx9 -shaderapi shaderapidx9 -shaderapi shaderapidx9 +exec keep.cfg");
}

TEST_CASE("backend: missing or empty operands never consume another switch") {
  CHECK(proxy::backend::select(L"gmod.exe -shaderapi", true).line == L"gmod.exe -shaderapi shaderapidx9");
  CHECK(proxy::backend::select(L"gmod.exe -shaderapi -windowed +map gm_construct", true).line ==
        L"gmod.exe -shaderapi shaderapidx9 -windowed +map gm_construct");
  CHECK(proxy::backend::select(LR"(gmod.exe -shaderapi "" -shaderapi=)", true).line ==
        L"gmod.exe -shaderapi shaderapidx9 -shaderapi shaderapidx9");
  CHECK(proxy::backend::select(L"gmod.exe -shaderapi -shaderapi shaderapidx11", true).line ==
        L"gmod.exe -shaderapi shaderapidx9 -shaderapi shaderapidx9");
}

TEST_CASE("backend: unrelated raw Unicode, whitespace, quoting and slashes are preserved") {
  const std::wstring line = LR"("H:\游戏\gmod.exe"  -ShAdErApI "C:\FX mods\shaderapidx11.dll"   +name "Miku \"RTX\"" +path "\\server\keep\")";
  const std::wstring expected = LR"("H:\游戏\gmod.exe"  -shaderapi shaderapidx9   +name "Miku \"RTX\"" +path "\\server\keep\")";
  CHECK(proxy::backend::select(line, true).line == expected);
}

namespace {
std::array<cmdline::StringRecord*, 3> process_records() {
  const auto kernelbase = GetModuleHandleW(L"kernelbase.dll");
  auto** wide = cmdline::cached_pointer_slot(reinterpret_cast<const void*>(GetProcAddress(kernelbase, "GetCommandLineW")));
  auto** ansi = cmdline::cached_pointer_slot(reinterpret_cast<const void*>(GetProcAddress(kernelbase, "GetCommandLineA")));
  REQUIRE(wide && ansi);
  auto* peb = reinterpret_cast<PEB*>(__readgsqword(0x60));
  REQUIRE(peb && peb->ProcessParameters);
  return {reinterpret_cast<cmdline::StringRecord*>(reinterpret_cast<unsigned char*>(wide) - offsetof(cmdline::StringRecord, buffer)),
          reinterpret_cast<cmdline::StringRecord*>(reinterpret_cast<unsigned char*>(ansi) - offsetof(cmdline::StringRecord, buffer)),
          reinterpret_cast<cmdline::StringRecord*>(&peb->ProcessParameters->CommandLine)};
}
std::array<cmdline::StringRecord, 3> records_copy(const std::array<cmdline::StringRecord*, 3>& records) {
  std::array<cmdline::StringRecord, 3> copy;
  for (std::size_t i = 0; i < records.size(); ++i) std::memcpy(&copy[i], records[i], sizeof(copy[i]));
  return copy;
}
void check_records(const std::array<cmdline::StringRecord*, 3>& records,
                   const std::array<cmdline::StringRecord, 3>& expected) {
  for (std::size_t i = 0; i < records.size(); ++i)
    CHECK(std::memcmp(records[i], &expected[i], sizeof(expected[i])) == 0);
}
}  // namespace

TEST_CASE("backend: real W A PEB rewrite, nested rollback and exact original descriptors") {
  const std::wstring original_w(GetCommandLineW());
  const std::string original_a(GetCommandLineA());
  const auto records = process_records();
  const auto original_records = records_copy(records);
  const auto custom = original_w + LR"( -ShAdErApI "C:\Mods\shaderapidx11.dll" -shaderapi shaderapigl +name "中文 RTX")";
  auto simulated_launch = cmdline::rewrite_arguments(original_w, custom, {});
  REQUIRE(simulated_launch.ok);
  const auto custom_records = records_copy(records);
  const auto custom_a = std::string(GetCommandLineA());
  const auto selected = proxy::backend::select(GetCommandLineW(), true);
  REQUIRE(selected.changed);
  auto active = cmdline::rewrite_arguments(custom, selected.line, {"-dxlevel", "90", "-nod3d9ex"});
  REQUIRE(active.ok);
  CHECK(std::wstring(GetCommandLineW()) == selected.line + L" -dxlevel 90 -nod3d9ex");
  CHECK(std::string(GetCommandLineA()).find("shaderapidx11") == std::string::npos);
  CHECK(std::string(GetCommandLineA()).find("shaderapigl") == std::string::npos);
  const auto preserved_name = custom_a.substr(custom_a.find(" +name "));
  CHECK(std::string(GetCommandLineA()).ends_with(preserved_name + " -dxlevel 90 -nod3d9ex"));
  CHECK(records[0]->buffer == records[2]->buffer);
  CHECK(active.restore());
  CHECK(std::wstring(GetCommandLineW()) == custom && std::string(GetCommandLineA()) == custom_a);
  check_records(records, custom_records);
  CHECK(simulated_launch.restore());
  CHECK(std::wstring(GetCommandLineW()) == original_w && std::string(GetCommandLineA()) == original_a);
  check_records(records, original_records);
}

TEST_CASE("backend: stale expected text and invalid arguments refuse without any cache write") {
  const std::wstring original_w(GetCommandLineW());
  const std::string original_a(GetCommandLineA());
  const auto records = process_records();
  const auto before = records_copy(records);
  auto stale = cmdline::rewrite_arguments(original_w + L" stale", original_w + L" changed", {});
  CHECK(!stale.ok);
  auto stale_noop = cmdline::rewrite_arguments(original_w + L" stale", original_w + L" stale", {});
  CHECK(!stale_noop.ok);
  auto invalid = cmdline::rewrite_arguments(original_w, original_w + L" -shaderapi shaderapidx9", {std::string("bad\0arg", 7)});
  CHECK(!invalid.ok);
  CHECK(std::wstring(GetCommandLineW()) == original_w && std::string(GetCommandLineA()) == original_a);
  check_records(records, before);
}
