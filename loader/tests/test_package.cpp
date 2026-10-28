#include "gma_fixture.h"
#include "nl/gma.h"
#include "nl/package.h"
#include "nl_test.h"

#include <cstdlib>
#include <filesystem>
#include <fstream>
#include <string>
#include <utility>
#include <vector>

namespace fs = std::filesystem;

namespace {

using Files = std::vector<std::pair<std::string, std::string>>;  // path -> bytes

const Files kPayload = {
    {"native/payload/runtime/d3d9.dll", "MZ-not-a-dll"},
    {"native/payload/config/rtx.conf", "rtx.x = 1\n"},
    {"native/root/rtx-remix/mods/base_mod/mod.usda", "#usda 1.0\n"},
    {"lua/autorun/rtx_status.lua", "print('status')\n"},
};

std::string manifest_for(const Files& files) {
  std::string listed;
  for (const auto& [path, bytes] : files) {
    if (path.rfind("native/", 0) != 0) continue;
    listed += (listed.empty() ? "" : ",\n    ") + std::string("\"") + path + "\": {\"size\": " +
              std::to_string(bytes.size()) + ", \"sha256\": \"" + std::string(64, '0') + "\"}";
  }
  return R"({"schema": 1, "id": "test-runtime", "version": "1.0.0", "kinds": ["remix-runtime", "root-files"],
  "files": {
    )" + listed + R"(
  },
  "remix": {"entry": "runtime/d3d9.dll", "rtx_conf_layers": ["config/rtx.conf"]},
  "root_files": [{"path": "rtx-remix/mods/base_mod"}]})";
}

Files with_manifest(Files files, std::string manifest) {
  files.insert(files.begin(), {"native/manifest.json", std::move(manifest)});
  return files;
}

fs::path write_gma(const fs::path& dir, const std::string& name, const Files& files) {
  nl::test::FixtureArchive archive;
  for (const auto& [path, bytes] : files) archive.files.push_back({path, bytes});
  const std::string data = nl::test::build_gma(archive);
  const fs::path path = dir / name;
  std::ofstream(path, std::ios::binary).write(data.data(), static_cast<std::streamsize>(data.size()));
  return path;
}

fs::path write_folder(const fs::path& dir, const Files& files) {
  for (const auto& [path, bytes] : files) {
    const fs::path target = dir / fs::path(path);
    fs::create_directories(target.parent_path());
    std::ofstream(target, std::ios::binary).write(bytes.data(), static_cast<std::streamsize>(bytes.size()));
  }
  return dir;
}

}  // namespace

TEST_CASE("package: a .gma package loads and its files can be read") {
  const auto dir = nl::test::scratch_dir("package_gma");
  const auto files = with_manifest(kPayload, manifest_for(kPayload));
  {
    auto package = nl::package::load(nl::package::open_archive(write_gma(dir, "runtime.gma", files)));
    CHECK(package.manifest.id == "test-runtime");
    CHECK(package.contents->entries().size() == files.size());
    CHECK(package.contents->read("native/payload/config/rtx.conf", 1024) == "rtx.x = 1\n");
    CHECK(package.contents->read("NATIVE/PAYLOAD/CONFIG/RTX.CONF", 1024) == "rtx.x = 1\n");
    CHECK_THROWS_AS(package.contents->read("native/payload/config/rtx.conf", 3), nl::gma::FormatError);
    CHECK_THROWS_AS(package.contents->read("native/nothing", 1024), nl::package::Error);
  }
  fs::remove_all(dir);
}

TEST_CASE("package: a development folder with the same layout loads") {
  const auto dir = nl::test::scratch_dir("package_folder");
  const auto folder = write_folder(dir / "runtime", with_manifest(kPayload, manifest_for(kPayload)));
  auto package = nl::package::load(nl::package::open_folder(folder));
  CHECK(package.manifest.id == "test-runtime");
  CHECK(package.contents->read("native/payload/runtime/d3d9.dll", 1024) == "MZ-not-a-dll");
  CHECK_THROWS_AS(package.contents->read("native/payload/runtime/d3d9.dll", 2), nl::package::Error);
  package.contents.reset();
  fs::remove_all(dir);
}

TEST_CASE("package: archives without a manifest or with a wrong one are refused") {
  const auto dir = nl::test::scratch_dir("package_bad");
  CHECK_THROWS_AS(nl::package::load(nl::package::open_archive(write_gma(dir, "plain.gma", kPayload))), nl::package::Error);

  Files resized = kPayload;
  const std::string manifest = manifest_for(kPayload);
  resized[1].second += "extra";  // rtx.conf no longer matches its listed size
  CHECK_THROWS_AS(nl::package::load(nl::package::open_archive(write_gma(dir, "resized.gma", with_manifest(resized, manifest)))),
                  nl::manifest::Error);

  Files unlisted = kPayload;
  unlisted.push_back({"native/payload/runtime/sneaky.dll", "x"});
  CHECK_THROWS_AS(nl::package::load(nl::package::open_archive(write_gma(dir, "unlisted.gma", with_manifest(unlisted, manifest)))),
                  nl::manifest::Error);
  fs::remove_all(dir);
}

TEST_CASE("package: folders containing junctions are refused") {
  const auto dir = nl::test::scratch_dir("package_junction");
  const auto folder = write_folder(dir / "runtime", with_manifest(kPayload, manifest_for(kPayload)));
  fs::create_directories(dir / "elsewhere");
  // Directory junctions need no special rights; mklink is the simplest way to make one.
  const std::string command = "cmd /c mklink /J \"" + (folder / "native" / "payload" / "escape").string() + "\" \"" +
                              (dir / "elsewhere").string() + "\" >nul";
  if (std::system(command.c_str()) == 0) {
    CHECK_THROWS_AS(nl::package::open_folder(folder), nl::package::Error);
    fs::remove(folder / "native" / "payload" / "escape");  // removes the junction, not its target
  } else {
    std::printf("  (skipped: could not create a junction)\n");
  }
  fs::remove_all(dir);
}
