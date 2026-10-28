#include "nl/fs.h"
#include "nl/journal.h"
#include "nl_test.h"

#include <filesystem>
#include <fstream>
#include <string>
#include <vector>

namespace {

const std::string kSha = std::string(64, 'a');

nl::journal::Journal sample() {
  using nl::journal::Step;
  nl::journal::Journal j;
  j.loader = "0.1.0";
  j.next = 4;
  nl::journal::Package p;
  p.id = "rtx-remix-runtime";
  p.version = "1.6.1+gmod.20261025";
  p.manifest_sha256 = kSha;
  p.source = "workshop";
  p.location = "H:/SteamLibrary/steamapps/workshop/content/4000/1/runtime.gma";
  p.payload = "native-loader/packages/rtx-remix-runtime/1.6.1+gmod.20261025_3";
  nl::manifest::Remix remix;
  remix.entry = "runtime/d3d9.dll";
  remix.rtx_conf_layers = {"config/rtx.conf"};
  remix.env = {{"DXVK_LOG_LEVEL", "info"}};
  remix.launch_args = {"-dxlevel", "90"};
  remix.prefer_system_vulkan_loader = true;
  p.remix = remix;
  nl::journal::Generation g;
  g.number = 3;
  g.packages.push_back(p);
  g.files.push_back({p.payload + "/runtime/d3d9.dll", p.id, kSha, 12, 133000000000000000ULL, false});
  g.files.push_back({"rtx-remix/mods/base_mod/mod.usda", p.id, kSha, 5, 1, true});
  j.current = g;
  nl::journal::Generation previous = g;
  previous.number = 2;
  previous.packages[0].remix.reset();
  j.previous = previous;
  j.previous_backup = "native-loader/backup/3";
  j.retired.push_back({"native-loader/backup/2/rtx-remix/mods/x/a.dds", "mods", kSha, 1, 2, false});
  j.dirs = {"rtx-remix", "rtx-remix/mods"};
  j.hold = std::vector<std::string>{"rtx-remix-runtime@" + kSha};
  nl::journal::Pending pending;
  pending.transaction = 4;
  pending.action = "apply";
  pending.steps.push_back({Step::Op::make_dir, "", "native-loader/backup/4", ""});
  pending.steps.push_back(
      {Step::Op::move, "rtx-remix/mods/base_mod/mod.usda", "native-loader/backup/4/rtx-remix/mods/base_mod/mod.usda", kSha});
  pending.steps.push_back({Step::Op::move, "native-loader/staging/4/0/payload", "native-loader/packages/x/1.0.0_4", ""});
  j.pending = pending;
  return j;
}

}  // namespace

TEST_CASE("journal: serialize and parse round-trip every field") {
  const std::string text = nl::journal::serialize(sample());
  const auto back = nl::journal::parse(text);
  CHECK(nl::journal::serialize(back) == text);
  REQUIRE(back.current.has_value() && back.previous.has_value() && back.pending.has_value());
  CHECK(back.current->files[0].mtime == 133000000000000000ULL);
  CHECK(back.current->files[1].adopted);
  CHECK(back.current->packages[0].remix->env[0].second == "info");
  CHECK(back.current->packages[0].remix->prefer_system_vulkan_loader);
  CHECK(!back.previous->packages[0].remix.has_value());
  CHECK(back.pending->steps.size() == 3);
  CHECK(back.pending->steps[0].op == nl::journal::Step::Op::make_dir);
  CHECK(back.pending->steps[2].sha256.empty());
  CHECK(back.hold && back.hold->size() == 1);

  nl::journal::Journal none = sample();
  none.hold.reset();  // no hold, which is not the same as holding an empty set
  CHECK(!nl::journal::parse(nl::journal::serialize(none)).hold.has_value());
  none.hold = std::vector<std::string>{};
  CHECK(nl::journal::parse(nl::journal::serialize(none)).hold.has_value());
}

TEST_CASE("journal: invalid, unsafe or out-of-bounds journals are refused") {
  const std::string good = nl::journal::serialize(sample());
  const auto replaced = [&](const std::string& from, const std::string& to) {
    std::string text = good;
    const auto at = text.find(from);
    REQUIRE(at != std::string::npos);
    return text.replace(at, from.size(), to);
  };
  const std::vector<std::string> bad = {
      replaced("\"schema\": 1", "\"schema\": 2"),
      replaced("\"next\": 4", "\"next\": 0"),
      replaced("\"loader\"", "\"lodaer\""),  // unknown key
      replaced("\"path\": \"rtx-remix/mods/base_mod/mod.usda\"", "\"path\": \"../escape.txt\""),
      replaced("\"path\": \"native-loader/packages/rtx", "\"path\": \"bin/win64/rtx"),  // a file the loader never owns
      replaced("\"dirs\": [\"rtx-remix\"", "\"dirs\": [\"bin\""),                      // a folder it never makes
      replaced("\"size\": 12", "\"size\": -12"),
      replaced("\"sha256\": \"" + kSha, "\"sha256\": \"" + std::string(64, 'A')),
      replaced("\"source\": \"workshop\"", "\"source\": \"internet\""),
      replaced("\"previous_backup\": \"native-loader/backup/3\"", "\"previous_backup\": \"garrysmod\""),
      replaced("\"action\": \"apply\"", "\"action\": \"delete\""),
      replaced("\"op\": \"make_dir\"", "\"op\": \"run\""),
      replaced("\"to\": \"native-loader/packages/x/1.0.0_4\"", "\"to\": \"C:/Windows/x\""),
      replaced("\"adopted\": false", "\"adopted\": 0"),
      replaced("\"entry\": \"runtime/d3d9.dll\"", "\"entry\": \"../d3d9.dll\""),
      good.substr(0, good.size() / 2),
      "",
  };
  for (const std::string& text : bad) CHECK_THROWS_AS(nl::journal::parse(text), nl::journal::Error);
}

TEST_CASE("journal: save and load through the game folder") {
  const auto dir = nl::test::scratch_dir("journal_files");
  std::filesystem::create_directories(dir / "native-loader");
  CHECK(!nl::journal::load(dir).has_value());
  nl::journal::save(nl::fs::win32(), dir, sample());
  const auto loaded = nl::journal::load(dir);
  REQUIRE(loaded.has_value());
  CHECK(nl::journal::serialize(*loaded) == nl::journal::serialize(sample()));
  std::ofstream(dir / "native-loader" / "state.json", std::ios::binary) << "{";
  CHECK_THROWS_AS(nl::journal::load(dir), nl::journal::Error);
  std::filesystem::remove_all(dir);
}
