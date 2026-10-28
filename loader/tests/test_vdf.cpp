#include "nl/vdf.h"
#include "nl_test.h"

TEST_CASE("vdf: blocks, comments, escapes and unquoted tokens") {
  const auto root = nl::vdf::parse(R"(
    // app manifest excerpt
    "AppState"
    {
      "appid"   "4000"
      "name"    "Garry's \"Mod\""
      "path"    "C:\\Program Files (x86)\\Steam"
      "InstalledDepots" { "4001" { "manifest" "7488132547021413298" } }
      unquoted value
    })");
  const auto* state = root.find("AppState");
  REQUIRE(state && state->block);
  CHECK(state->find("appid")->value == "4000");
  CHECK(state->find("name")->value == "Garry's \"Mod\"");
  CHECK(state->find("path")->value == "C:\\Program Files (x86)\\Steam");
  CHECK(state->find("InstalledDepots")->find("4001")->find("manifest")->value == "7488132547021413298");
  CHECK(state->find("unquoted")->value == "value");
  CHECK(state->find("APPID")->value == "4000");  // keys compare without case
  CHECK(state->find("missing") == nullptr);
}

TEST_CASE("vdf: later duplicates win; conditionals are skipped") {
  const auto root = nl::vdf::parse(R"("a" "1" "a" "2" "b" "3" [$WIN32] "c" "4" [!$X360])");
  CHECK(root.find("a")->value == "2");
  CHECK(root.find("b")->value == "3");
  CHECK(root.find("c")->value == "4");
  CHECK(root.children.size() == 4);
}

TEST_CASE("vdf: GMod's addonnomount.txt and Steam's appworkshop shape") {
  const auto nomount = nl::vdf::parse("\"addonnomount\"\n{\n\t\"1\"\t\t\"1310909460\"\n\t\"2\"\t\t\"1846733342\"\n}\n");
  CHECK(nomount.find("addonnomount")->children.size() == 2);
  const auto acf = nl::vdf::parse(R"("AppWorkshop" { "appid" "4000" "WorkshopItemsInstalled" {
      "104486597" { "size" "181376" "timeupdated" "1723341289" "manifest" "2436479633753873249" } } })");
  const auto* item = acf.find("AppWorkshop")->find("WorkshopItemsInstalled")->find("104486597");
  REQUIRE(item != nullptr);
  CHECK(item->find("timeupdated")->value == "1723341289");
}

TEST_CASE("vdf: unbalanced or keyless blocks are errors") {
  for (const char* bad : {"\"a\" {", "}", "{ \"a\" \"b\" }"}) {
    CHECK_THROWS_AS(nl::vdf::parse(bad), nl::vdf::Error);
  }
  std::string deep;
  for (int i = 0; i < 70; ++i) deep += "\"k\" { ";
  CHECK_THROWS_AS(nl::vdf::parse(deep), nl::vdf::Error);
}
