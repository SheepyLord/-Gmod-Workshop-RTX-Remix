#include "nl/fs.h"
#include "nl/sha256.h"
#include "nl_test.h"

#include <cstdio>
#include <cstdlib>
#include <filesystem>
#include <fstream>
#include <string>

namespace {

namespace sfs = std::filesystem;

void write(const sfs::path& file, const std::string& bytes) {
  sfs::create_directories(file.parent_path());
  std::ofstream(file, std::ios::binary).write(bytes.data(), static_cast<std::streamsize>(bytes.size()));
}

// Directory junctions need no special rights; mklink is the simplest way to make one.
bool make_junction(const sfs::path& link, const sfs::path& target) {
  const std::string command = "cmd /c mklink /J \"" + link.string() + "\" \"" + target.string() + "\" >nul";
  return std::system(command.c_str()) == 0;
}

}  // namespace

TEST_CASE("fs: stat, hashes and atomic writes (a stale temporary file is replaced)") {
  const auto dir = nl::test::scratch_dir("fs_basics");
  auto& disk = nl::fs::win32();
  const auto file = dir / "state.json";
  CHECK(!nl::fs::stat(file).exists);
  CHECK(!nl::fs::stat(dir / "missing" / "deeper.txt").exists);
  nl::fs::write_atomic(disk, file, "one");
  CHECK(nl::fs::read_file(file, 100) == "one");
  write(dir / "state.json.tmp", "stale");
  nl::fs::write_atomic(disk, file, "two!");
  CHECK(nl::fs::read_file(file, 100) == "two!");
  CHECK(!nl::fs::stat(dir / "state.json.tmp").exists);
  const auto s = nl::fs::stat(file);
  CHECK(s.exists && !s.directory && !s.link && s.size == 4 && s.mtime != 0);
  CHECK(nl::fs::stat(dir).directory);
  const auto h = nl::fs::hash_file(file);
  CHECK(h.size == 4 && h.sha256 == nl::sha256::of("two!"));
  CHECK_THROWS_AS(nl::fs::read_file(file, 3), nl::fs::Error);
  CHECK_THROWS_AS(nl::fs::hash_file(dir), nl::fs::Error);
  CHECK(nl::fs::list(dir).size() == 1);
  CHECK(!nl::fs::empty_directory(dir));
  sfs::create_directories(dir / "empty");
  CHECK(nl::fs::empty_directory(dir / "empty"));
  sfs::remove_all(dir);
}

TEST_CASE("fs: paths longer than MAX_PATH work") {
  const auto dir = nl::test::scratch_dir("fs_long");
  auto& disk = nl::fs::win32();
  std::string relative;
  for (int i = 0; i < 12; ++i) {
    relative += (relative.empty() ? "" : "/") + std::string(30, static_cast<char>('a' + i));
    disk.create_directory(nl::fs::join(dir, relative));
  }
  const auto file = nl::fs::join(dir, relative + "/payload.bin");
  CHECK(file.native().size() > 400);
  {
    const auto writer = disk.create_file(file);
    writer->write("x", 1);
    writer->close();
  }
  CHECK(nl::fs::stat(file).size == 1);
  CHECK(nl::fs::hash_file(file).sha256 == nl::sha256::of("x"));
  disk.move(file, nl::fs::join(dir, relative + "/moved.bin"), false);
  CHECK(nl::fs::read_file(nl::fs::join(dir, relative + "/moved.bin"), 10) == "x");
  nl::fs::remove_tree(disk, nl::fs::join(dir, std::string(30, 'a')));
  CHECK(!nl::fs::stat(nl::fs::join(dir, std::string(30, 'a'))).exists);
  sfs::remove_all(dir);
}

TEST_CASE("fs: Counting counts every change, and its hook can make one fail") {
  const auto dir = nl::test::scratch_dir("fs_counting");
  std::uint64_t fail_at = 0;
  nl::fs::Counting disk(nl::fs::win32(), [&](std::uint64_t change, std::string_view) {
    if (change == fail_at) throw nl::fs::Error("injected", 0);
  });
  nl::fs::write_atomic(disk, dir / "a.json", "{}");  // create, write, close, move
  CHECK(disk.operations() == 4);
  fail_at = 6;  // the write of the next one
  CHECK_THROWS_AS(nl::fs::write_atomic(disk, dir / "a.json", "{\"x\": 1}"), nl::fs::Error);
  CHECK(nl::fs::read_file(dir / "a.json", 100) == "{}");  // the target was never touched
  fail_at = 0;
  nl::fs::write_atomic(disk, dir / "a.json", "{\"y\": 2}");  // removes the stale temporary file first
  CHECK(nl::fs::read_file(dir / "a.json", 100) == "{\"y\": 2}");
  CHECK(disk.operations() == 11);
  sfs::remove_all(dir);
}

TEST_CASE("fs: links are refused, and remove_tree removes a junction without following it") {
  const auto dir = nl::test::scratch_dir("fs_links");
  write(dir / "elsewhere" / "keep.txt", "keep");
  sfs::create_directories(dir / "root" / "rtx-remix");
  if (!make_junction(dir / "root" / "rtx-remix" / "mods", dir / "elsewhere")) {
    std::printf("  (skipped: could not create a junction)\n");
    sfs::remove_all(dir);
    return;
  }
  CHECK_THROWS_AS(nl::fs::refuse_links(dir / "root", "rtx-remix/mods/x/mod.usda"), nl::fs::Error);
  nl::fs::refuse_links(dir / "root", "rtx-remix/other/mod.usda");  // missing components are fine
  CHECK(nl::fs::stat(dir / "root" / "rtx-remix" / "mods").link);
  CHECK_THROWS_AS(nl::fs::hash_file(dir / "root" / "rtx-remix" / "mods"), nl::fs::Error);
  nl::fs::remove_tree(nl::fs::win32(), dir / "root");
  CHECK(!nl::fs::stat(dir / "root").exists);
  CHECK(nl::fs::read_file(dir / "elsewhere" / "keep.txt", 100) == "keep");
  sfs::remove_all(dir);
}
