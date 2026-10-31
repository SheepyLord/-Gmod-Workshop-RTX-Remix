#include "nl/memory.h"
#include "nl/fs.h"
#include "nl/json.h"
#include "nl_test.h"
#include <windows.h>
#include <algorithm>
#include <fstream>
#include <limits>

namespace {
namespace m = nl::memory;
namespace fs = std::filesystem;
m::Sample sample() {
  m::Sample s;
  s.time_utc = "2026-10-31T01:02:03.000Z";
  s.private_bytes = 1; s.working_set = 2; s.commit_total = 3; s.commit_limit = 4; s.available_ram = 5;
  s.gpu_local_usage = 6; s.gpu_local_budget = 7; s.gpu_nonlocal_usage = 8; s.gpu_nonlocal_budget = 9;
  return s;
}
std::string read(const fs::path& root, std::string_view path) { return nl::fs::read_file(nl::fs::join(root, path), 1u << 20); }
void write(const fs::path& root, std::string_view path, std::string_view text) {
  const auto file = nl::fs::join(root, path);
  fs::create_directories(file.parent_path());
  std::ofstream(file, std::ios::binary).write(text.data(), static_cast<std::streamsize>(text.size()));
}
unsigned rows(std::string_view text) { return static_cast<unsigned>(std::count(text.begin(), text.end(), '\n')) - 1; }
}

TEST_CASE("memory: byte columns, UTC format, unavailable counters and unsafe timestamps") {
  CHECK(m::csv_line(sample()) == "2026-10-31T01:02:03.000Z,1,2,3,4,5,6,7,8,9\n");
  auto empty = m::Sample{}; empty.time_utc = sample().time_utc;
  CHECK(m::csv_line(empty) == "2026-10-31T01:02:03.000Z,,,,,,,,,\n");
  CHECK(std::count(m::csv_header().begin(), m::csv_header().end(), ',') == 9);
  empty.time_utc = "bad,time\n";
  CHECK_THROWS_AS(m::csv_line(empty), std::runtime_error);
}

TEST_CASE("memory: warning thresholds are strictly below 32 GiB or above 70 percent") {
  CHECK(!m::commit_warning(0, 0));
  CHECK(m::commit_warning(0, (32ull << 30) - 1));
  CHECK(!m::commit_warning(0, 32ull << 30));
  constexpr auto limit = 40ull << 30;
  CHECK(!m::commit_warning(limit * 7 / 10, limit));
  CHECK(m::commit_warning(limit * 7 / 10 + 1, limit));
  CHECK(m::commit_warning(limit + 1, limit));
  const auto maximum = std::numeric_limits<std::uint64_t>::max();
  CHECK(!m::commit_warning(maximum / 10 * 7, maximum));
  CHECK(m::commit_warning(maximum, maximum));
}

TEST_CASE("memory: two bounded CSV files rotate across repeated starts without duplicate headers") {
  const auto root = nl::test::scratch_dir("memory_rotation");
  m::Limits limits; limits.rows = 3;
  for (unsigned i = 0; i < 8; ++i) m::append(root, sample(), limits);
  const auto current = read(root, m::kCsv), previous = read(root, m::kRotated);
  CHECK(rows(current) == 2);
  CHECK(rows(previous) == 3);
  CHECK(current == std::string(m::csv_header()) + m::csv_line(sample()) + m::csv_line(sample()));
  CHECK(previous.starts_with(m::csv_header()));
  CHECK(fs::file_size(nl::fs::join(root, m::kIndex)) < 4096);
  fs::remove_all(root);
}

TEST_CASE("memory: the byte limit rotates before a row would exceed the file bound") {
  const auto root = nl::test::scratch_dir("memory_bytes");
  m::Limits limits; limits.bytes = m::csv_header().size() + m::csv_line(sample()).size() * 2;
  for (unsigned i = 0; i < 5; ++i) m::append(root, sample(), limits);
  CHECK(rows(read(root, m::kCsv)) == 1);
  CHECK(rows(read(root, m::kRotated)) == 2);
  CHECK(fs::file_size(nl::fs::join(root, m::kRotated)) <= limits.bytes);
  limits.bytes = 1;
  CHECK_THROWS_AS(m::append(root, sample(), limits), std::runtime_error);
  fs::remove_all(root);
}

TEST_CASE("memory: foreign and edited CSV files are preserved, including a valid-looking edit") {
  const auto root = nl::test::scratch_dir("memory_edits");
  write(root, m::kCsv, std::string(m::csv_header()) + m::csv_line(sample()));
  const auto foreign = read(root, m::kCsv);
  CHECK_THROWS_AS(m::append(root, sample()), std::runtime_error);
  CHECK(read(root, m::kCsv) == foreign);
  fs::remove_all(root);
  fs::create_directories(root);
  m::Limits limits; limits.rows = 1;
  m::append(root, sample(), limits); m::append(root, sample(), limits);
  auto edit = sample(); edit.private_bytes = 99;
  write(root, m::kRotated, std::string(m::csv_header()) + m::csv_line(edit));
  CHECK_THROWS_AS(m::append(root, sample(), limits), std::runtime_error);
  CHECK(read(root, m::kRotated).find(",99,") != std::string::npos);
  const auto current = read(root, m::kCsv);
  write(root, m::kCsv, std::string(m::csv_header()) + m::csv_line(edit));
  CHECK_THROWS_AS(m::append(root, sample(), limits), std::runtime_error);
  CHECK(read(root, m::kCsv) != current);
  fs::remove_all(root);
}

TEST_CASE("memory: locked history is skipped without modifying its last flushed sample") {
  const auto root = nl::test::scratch_dir("memory_locked");
  m::append(root, sample());
  const auto before = read(root, m::kCsv);
  const auto path = nl::fs::join(root, m::kCsv);
  const HANDLE lock = CreateFileW(path.c_str(), GENERIC_READ, 0, nullptr, OPEN_EXISTING, FILE_ATTRIBUTE_NORMAL, nullptr);
  REQUIRE(lock != INVALID_HANDLE_VALUE);
  CHECK_THROWS_AS(m::append(root, sample()), std::runtime_error);
  CloseHandle(lock);
  CHECK(read(root, m::kCsv) == before);
  fs::remove_all(root);
}

TEST_CASE("memory: a flushed row with an old receipt and an interrupted rotation recover") {
  const auto root = nl::test::scratch_dir("memory_recovery");
  m::Limits limits; limits.rows = 3;
  m::append(root, sample(), limits);
  const auto receipt = read(root, m::kIndex);
  m::append(root, sample(), limits);
  write(root, m::kIndex, receipt);  // crash between row flush and receipt update
  m::append(root, sample(), limits);
  CHECK(rows(read(root, m::kCsv)) == 3);
  fs::rename(nl::fs::join(root, m::kCsv), nl::fs::join(root, m::kRotated));
  write(root, m::kCsv, std::string(m::csv_header()) + m::csv_line(sample()));
  m::append(root, sample(), limits);  // rotation completed, receipt still describes the old active file
  CHECK(rows(read(root, m::kCsv)) == 2);
  CHECK(rows(read(root, m::kRotated)) == 3);
  fs::remove_all(root);
}

TEST_CASE("memory: live kernel queries, stable process token and latest-only menu snapshot") {
  const auto root = nl::test::scratch_dir("memory_query");
  const auto token = m::process_token();
  CHECK(!token.empty()); CHECK(token == m::process_token());
  m::Sampler sampler(false);
  const auto live = sampler.query();
  REQUIRE(live.commit_limit.has_value()); CHECK(*live.commit_limit > 0);
  REQUIRE(live.private_bytes.has_value()); CHECK(*live.private_bytes > 0);
  CHECK(!live.gpu_local_usage);
  const auto commit_only = sampler.query(false);
  CHECK(!commit_only.private_bytes && !commit_only.working_set);
  CHECK(!m::csv_line(commit_only).empty());
  m::write_commit(root, sample(), token);
  const auto data = nl::json::parse(read(root, m::kCommit));
  CHECK(data.find("session_token")->as_string() == token);
  CHECK(data.find("commit_total")->as_int() == 3);
  CHECK(data.find("warning")->as_bool());
  CHECK(!data.find("private_bytes") && !data.find("gpu_local_usage"));
  CHECK(!fs::exists(nl::fs::join(root, m::kCsv)));
  fs::remove_all(root);
}
