#include "activation.h"
#include "nl_test.h"

using namespace nl::proxy;
namespace {
constexpr auto exe = L"H:\\Games\\GMod\\bin\\win64\\gmod.exe";
constexpr auto dll = L"H:\\Games\\GMod\\bin\\win64\\winmm.dll";
}

TEST_CASE("activation accepts only the x64 GMod host beside this DLL") {
  CHECK(should_activate(exe, dll, L"gmod.exe", L"", false).active());
  CHECK(should_activate(L"h:/games/gmod/BIN/WIN64/GMOD.EXE", dll, L"", L"", false).active());
  CHECK(!should_activate(L"H:\\Games\\GMod\\bin\\gmod.exe", dll, L"", L"", false).active());
  CHECK(!should_activate(L"H:\\Games\\GMod\\bin\\win64\\hlmv.exe", dll, L"", L"", false).active());
  CHECK(!should_activate(exe, L"H:\\Elsewhere\\winmm.dll", L"", L"", false).active());
  CHECK(!should_activate(exe, L"H:\\Games\\GMod\\bin\\win64\\foreign.dll", L"", L"", false).active());
  CHECK(!should_activate(L"bin\\win64\\gmod.exe", L"bin\\win64\\winmm.dll", L"", L"", false).active());
}

TEST_CASE("game root derives from the host path rather than the working directory") {
  CHECK(game_root(exe) == L"H:\\Games\\GMod");
  CHECK(game_root(L"C:\\bin\\win64\\gmod.exe") == L"C:\\");
  CHECK(game_root(L"\\\\server\\share\\GMod\\bin\\win64\\gmod.exe") == L"\\\\server\\share\\GMod");
  CHECK(game_root(L"C:/游戏/GMod/bin/win64/gmod.exe") == L"C:/游戏/GMod");
  CHECK(game_root(L"C:\\GMod\\bin\\gmod.exe").empty());
  CHECK(game_root(L"C:\\GMod\\bin\\win64\\gmod.exe.bak").empty());
  CHECK(game_root(L"").empty());
  CHECK(game_root(L"C:relative\\bin\\win64\\gmod.exe").empty());
  CHECK(game_root(L"\\\\server\\bin\\win64\\gmod.exe").empty());
}

TEST_CASE("command line switches are complete case insensitive tokens") {
  CHECK(command_line_has_token(L"\"H:\\Games with spaces\\gmod.exe\"\t-NoNativeLoader +map gm_construct", L"-nonativeloader"));
  CHECK(command_line_has_token(L"gmod.exe \"-nonativeloader\"", L"-nonativeloader"));
  CHECK(command_line_has_token(L"gmod.exe -no\"native\"loader", L"-nonativeloader"));
  CHECK(command_line_has_token(L"gmod.exe \"-nonativeloader", L"-nonativeloader"));
  CHECK(!command_line_has_token(L"gmod.exe -nonativeloader=1", L"-nonativeloader"));
  CHECK(!command_line_has_token(L"gmod.exe +say \"hello -nonativeloader\"", L"-nonativeloader"));
  CHECK(!command_line_has_token(L"gmod.exe --nonativeloader", L"-nonativeloader"));
  CHECK(!command_line_has_token(L"gmod.exe prefix-nonativeloader", L"-nonativeloader"));
  CHECK(!command_line_has_token(L"gmod.exe \"\"", L"-nonativeloader"));
  CHECK(!command_line_has_token(L"", L"-nonativeloader"));
}

TEST_CASE("token parser handles escaped quotes and backslashes") {
  CHECK(command_line_has_token(LR"(gmod.exe "a\"b")", L"a\"b"));
  CHECK(command_line_has_token(LR"(gmod.exe "a\\" b)", L"a\\"));
  CHECK(command_line_has_token(LR"(gmod.exe "a""b")", L"a\"b"));
  CHECK(command_line_has_token(LR"(gmod.exe C:\folder\file)", L"C:\\folder\\file"));
  CHECK(!command_line_has_token(LR"(gmod.exe \"-nonativeloader\")", L"-nonativeloader"));
  CHECK(command_line_has_token(LR"(gmod.exe "x\" -nonativeloader" -nonativeloader)", L"-nonativeloader"));
}

TEST_CASE("each off switch wins independently and all results are retained") {
  CHECK(!should_activate(exe, dll, L"gmod.exe -nonativeloader", L"", false).active());
  CHECK(!should_activate(exe, dll, L"gmod.exe", L"1", false).active());
  CHECK(!should_activate(exe, dll, L"gmod.exe", L"", true).active());
  CHECK(should_activate(exe, dll, L"gmod.exe", L"true", false).active());
  CHECK(should_activate(exe, dll, L"gmod.exe", L"10", false).active());
  const auto all = should_activate(exe, dll, L"-nonativeloader", L"1", true);
  CHECK(all.host_matches && all.command_line_disabled && all.environment_disabled && all.file_disabled);
  CHECK(!all.active());
  CHECK(!should_activate(L"hlmv.exe", dll, L"-nonativeloader", L"1", true).active());
}
