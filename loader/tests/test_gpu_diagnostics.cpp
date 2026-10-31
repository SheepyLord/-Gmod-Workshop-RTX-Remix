#include "nl/gpu_diagnostics.h"
#include "nl/fs.h"
#include "nl_test.h"
#include <atomic>
#include <filesystem>
#include <fstream>
#include <thread>

namespace gpu = nl::gpu_diagnostics;

TEST_CASE("GPU diagnostics: preparation is bounded to owned paths and repeat writes nothing") {
  const auto root = nl::test::scratch_dir("gpu_diagnostics_prepare");
  const auto before = gpu::probe(root);
  CHECK(!before.consumed && before.note.empty());
  CHECK(std::filesystem::path(before.dump_path).is_absolute());
  CHECK(before.dump_path.back() == '/');
  CHECK(!std::filesystem::exists(root / "native-loader"));  // probe is read-only
  const auto path = gpu::prepare(root);
  CHECK(path == before.dump_path);
  CHECK(std::filesystem::is_directory(nl::fs::join(root, gpu::kDumpFolder)));
  const auto layer = nl::fs::join(root, gpu::kLayer);
  CHECK(nl::fs::read_file(layer, 4096) == gpu::layer_text());
  const auto written = nl::fs::stat(layer).mtime;
  CHECK(gpu::prepare(root) == path);
  CHECK(nl::fs::stat(layer).mtime == written);
  CHECK(!gpu::probe(root).consumed);  // preparation alone does not consume the request
  std::filesystem::remove_all(root);
}

TEST_CASE("GPU diagnostics: next_start is consumed once without changing config and can be rearmed") {
  const auto root = nl::test::scratch_dir("gpu_diagnostics_once");
  std::filesystem::create_directories(root / "native-loader");
  const auto config = root / "native-loader/config.json";
  constexpr std::string_view text = R"({"schema":1,"diagnostics":{"gpu_crash_dumps":"next_start"}})";
  std::ofstream(config, std::ios::binary) << text;
  gpu::prepare(root);
  CHECK(gpu::consume_next_start(root));
  CHECK(gpu::probe(root).consumed);
  const auto marker = nl::fs::join(root, gpu::kUsed);
  const auto time = nl::fs::stat(marker).mtime;
  CHECK(!gpu::consume_next_start(root));
  CHECK(nl::fs::stat(marker).mtime == time);
  CHECK(nl::fs::read_file(config, 4096) == text);
  std::filesystem::remove(marker);  // documented player re-arm action
  CHECK(!gpu::probe(root).consumed);
  CHECK(gpu::consume_next_start(root));
  std::ofstream(marker, std::ios::binary | std::ios::trunc);  // interrupted marker write
  CHECK(gpu::probe(root).consumed);
  CHECK(!gpu::consume_next_start(root));
  std::filesystem::remove_all(root);
}

TEST_CASE("GPU diagnostics: only one simultaneous start consumes next_start") {
  const auto root = nl::test::scratch_dir("gpu_diagnostics_race");
  gpu::prepare(root);
  std::atomic<unsigned> claims{0}, errors{0};
  const auto claim = [&] {
    try { if (gpu::consume_next_start(root)) ++claims; }
    catch (...) { ++errors; }
  };
  std::thread first(claim), second(claim);
  first.join();
  second.join();
  CHECK(claims == 1);
  CHECK(errors == 0);
  CHECK(gpu::probe(root).consumed);
  std::filesystem::remove_all(root);
}

TEST_CASE("GPU diagnostics: a blocked parent fails closed without touching config") {
  const auto root = nl::test::scratch_dir("gpu_diagnostics_blocked");
  std::ofstream(root / "native-loader") << "not a directory";
  CHECK_THROWS_AS(gpu::prepare(root), nl::fs::Error);
  CHECK(nl::fs::read_file(root / "native-loader", 4096) == "not a directory");
  std::filesystem::remove_all(root);
}
