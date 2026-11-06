#include "loader_release.h"
#include "nl/fs.h"
#include "nl/sha256.h"
#include "nl_test.h"
#include <fstream>
#include <functional>

namespace {
namespace r = nl::proxy::loader_release;
const std::string url = "https://github.com/SheepyLord/Gmod-Workshop-RTX-Remix/releases/tag/v";
std::string record(std::string_view version) {
  return "{\"version\":\"" + std::string(version) + "\",\"url\":\"" + url + std::string(version) + "\"}";
}
struct Fixture {
  std::filesystem::path root = nl::test::scratch_dir("released_loader");
  nl::config::Config config;
  nl::journal::Generation generation;
  Fixture() {
    config.from_file = config.enabled = config.remix_enabled = true;
    config.dev_folders = {"fixture"};
    nl::journal::Package owner;
    owner.id = "gmod-rtx-remix";
    owner.source = "dev_folder";
    owner.location = nl::fs::utf8(root / "fixture");
    owner.remix = nl::manifest::Remix{};
    generation.packages.push_back(owner);
    put(record("0.16.0"));
  }
  void put(const std::string& bytes) {
    const auto path = nl::fs::join(root, r::kPath);
    std::filesystem::create_directories(path.parent_path());
    std::ofstream(path, std::ios::binary) << bytes;
    generation.files = {{std::string(r::kPath), "gmod-rtx-remix", nl::sha256::of(bytes), bytes.size()}};
  }
  std::optional<r::Record> read(std::string_view owner = "gmod-rtx-remix") {
    return r::read(root, config, generation, owner);
  }
};
}
TEST_CASE("released loader: bounded strict JSON and exact version-specific project URL") {
  for (const auto* version : {"0.14.0", "0.15.0-rc.1", "1.0.0-alpha.beta", "18446744073709551615.0.0"}) {
    const auto value = r::parse(record(version));
    REQUIRE(value);
    CHECK(value->version == version);
    CHECK(value->url == url + version);
    CHECK(r::parse(r::serialize(value)).has_value());
  }
  for (const auto* version : {"01.0.0", "1.2", "1.2.3.4", "1.2.3+build", "1.2.3-01", "1.2.3-", "1.2.3-a..b",
                            "18446744073709551616.0.0", "1.2.3\n", "1.2.3-<script>"})
    CHECK(!r::parse(record(version)));
  for (const auto& bytes : {"[]", "{}", "{\"version\":5,\"url\":true}",
      "{\"version\":\"1.2.3\",\"version\":\"0.0.0\",\"url\":\"bad\"}"}) CHECK(!r::parse(bytes));
  CHECK(!r::parse(std::string(1025, ' ')));
  CHECK(!r::parse(record("1.2.3") + "x"));
  CHECK(!r::parse("{\"extra\":1," + record("1.2.3").substr(1)));
  for (const auto* foreign : {"https://example.com/", "https://github.com.evil.test/", "http://github.com/"})
    CHECK(!r::parse("{\"version\":\"1.2.3\",\"url\":\"" + std::string(foreign) + "\"}"));
  CHECK(!r::parse("{\"version\":\"1.2.3\",\"url\":\"" + url + "1.2.3?x=1\"}"));
  CHECK(r::serialize({}) == "null");
}
TEST_CASE("released loader: only the active allowlisted runtime's unchanged journaled record counts") {
  Fixture f;
  REQUIRE(f.read());
  CHECK(f.read()->version == "0.16.0");
  const std::vector<std::function<void()>> mutations = {
    [&] { f.config.enabled = false; }, [&] { f.config.remix_enabled = false; },
    [&] { f.config.from_file = false; }, [&] { f.config.dev_folders.clear(); },
    [&] { f.generation.packages[0].remix.reset(); }, [&] { f.generation.packages[0].id = "content"; },
    [&] { f.generation.packages.push_back(f.generation.packages[0]); },
    [&] { f.generation.files[0].package = "foreign-content"; },
    [&] { f.generation.files[0].size++; }, [&] { f.generation.files[0].sha256 = std::string(64, 'f'); },
    [&] { f.generation.files[0].size = 1025; }, [&] { f.generation.files.clear(); },
    [&] { f.generation.files.push_back(f.generation.files[0]); },
    [&] { f.generation.files[0].path[0] = 'G'; }
  };
  const auto config = f.config;
  const auto generation = f.generation;
  for (const auto& mutate : mutations) {
    f.config = config; f.generation = generation;
    mutate(); CHECK(!f.read());
  }
  f.config = config; f.generation = generation;
  CHECK(!f.read("another-runtime"));
  f.put("invalid JSON"); CHECK(!f.read());
  f.put(record("0.16.0"));
  std::ofstream(nl::fs::join(f.root, r::kPath), std::ios::binary) << record("0.17.0");
  CHECK(!f.read());
  std::filesystem::remove(nl::fs::join(f.root, r::kPath)); CHECK(!f.read());
}
TEST_CASE("released loader: Workshop content cannot impersonate the distribution runtime") {
  Fixture f;
  f.generation.packages[0].source = "workshop";
  const auto item = f.root / "steamapps/workshop/content/4000/3829070317/native.gma";
  f.generation.packages[0].location = nl::fs::utf8(item);
  CHECK(!f.read());
  f.config.workshop = {"3829070317"};
  REQUIRE(f.read());
  f.generation.packages[0].location = nl::fs::utf8(item.parent_path().parent_path() / "12345678/native.gma");
  f.config.workshop.push_back("12345678");
  CHECK(!f.read());
  f.generation.packages[0].location = "workshop/content/4000/3829070317/native.gma";
  CHECK(!f.read());
}
