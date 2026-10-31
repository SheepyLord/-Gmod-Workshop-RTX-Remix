#include "nl/evidence.h"
#include "nl/fs.h"
#include "nl/json.h"
#include "nl/status.h"
#include "nl_test.h"
#include <windows.h>
#include <algorithm>
#include <chrono>
#include <cstdio>
#include <fstream>

namespace {
namespace e = nl::evidence;
namespace fs = std::filesystem;
void write(const fs::path& root, std::string_view path, std::string_view text) {
  const auto file = nl::fs::join(root, path);
  fs::create_directories(file.parent_path());
  std::ofstream(file, std::ios::binary).write(text.data(), static_cast<std::streamsize>(text.size()));
}
void stamp(const fs::path& file, std::uint64_t value) {
  const HANDLE handle = CreateFileW(file.c_str(), FILE_WRITE_ATTRIBUTES, FILE_SHARE_READ | FILE_SHARE_WRITE | FILE_SHARE_DELETE,
                                     nullptr, OPEN_EXISTING, FILE_ATTRIBUTE_NORMAL, nullptr);
  REQUIRE(handle != INVALID_HANDLE_VALUE);
  FILETIME time{static_cast<DWORD>(value), static_cast<DWORD>(value >> 32)};
  CHECK(SetFileTime(handle, nullptr, nullptr, &time));
  CloseHandle(handle);
}
std::size_t folders(const fs::path& root) {
  std::size_t count = 0;
  const auto path = nl::fs::join(root, e::kSessions);
  if (fs::exists(path)) for (const auto& entry : fs::directory_iterator(path)) if (entry.is_directory()) ++count;
  return count;
}
}

TEST_CASE("evidence: every class, optional structured fields and specific failures beat generic exits") {
  CHECK(e::classify("VK_ERROR_DEVICE_LOST") == "device_lost");
  CHECK(e::classify("Exiting after GPU device loss") == "device_lost");
  CHECK(e::classify("Exception on CS thread") == "cs_exception");
  CHECK(e::classify("Exception on CS thread: Memory allocation failed") == "allocation_failed");
  CHECK(e::classify("OUT OF MEMORY!") == "out_of_memory");
  CHECK(e::classify("RTX: Terminating application") == "clean");
  CHECK(e::classify("FSR FG: onDestroy called") == "unknown");
  CHECK(e::classify("") == "unknown");
  CHECK(e::classify("", "{}", true) == "crash");
  CHECK(e::classify("", R"({"event":"device_lost"})") == "device_lost");
  CHECK(e::classify("", R"({"event":null,"schema":999,"heaps":{}})") == "unknown");
  CHECK(e::classify("", "malformed") == "unknown");
  CHECK(e::classify("RTX: Terminating application", {}, true) == "crash");
  CHECK(e::classify("VK_ERROR_DEVICE_LOST", {}, true, true) == "out_of_memory");
}

TEST_CASE("evidence: original log is copied before readiness and crash sources are untouched") {
  const auto root = nl::test::scratch_dir("evidence_sources");
  const std::string log = "the entire old log\nVK_ERROR_DEVICE_LOST\n";
  write(root, "rtx-remix/logs/remix-dxvk.log", log);
  write(root, "rtx-remix/logs/.sentry-native/last_crash", "yes");
  write(root, "rtx-remix/logs/.sentry-native/reports/cpu.dmp", "cpu crash");
  write(root, "native-loader/logs/gpu/shaderDebugInfo/test.nvdbg", "shader");
  write(root, "native-loader/logs/memory.csv", "old telemetry\n");
  bool signalled = false;
  const auto collected = e::collect(root, e::now_filetime() + 10000000, 123, [&] {
    signalled = true;
    write(root, "rtx-remix/logs/remix-dxvk.log", "new runtime log\n");
  });
  CHECK(signalled);
  CHECK(collected.notes.empty());
  CHECK(collected.previous.reason == "device_lost");
  REQUIRE(!collected.previous.folder.empty());
  const auto archive = nl::fs::join(root, collected.previous.folder);
  CHECK(nl::fs::read_file(archive / "rtx-remix/logs/remix-dxvk.log", 4096) == log);
  CHECK(nl::fs::read_file(archive / "rtx-remix/logs/.sentry-native/reports/cpu.dmp", 4096) == "cpu crash");
  CHECK(nl::fs::read_file(archive / "native-loader/logs/gpu/shaderDebugInfo/test.nvdbg", 4096) == "shader");
  CHECK(nl::fs::read_file(archive / "native-loader/logs/memory.csv", 4096) == "old telemetry\n");
  CHECK(nl::fs::read_file(root / "rtx-remix/logs/.sentry-native/reports/cpu.dmp", 4096) == "cpu crash");
  CHECK(nl::fs::read_file(root / "native-loader/logs/memory.csv", 4096) == "old telemetry\n");
  fs::remove_all(root);
}

TEST_CASE("evidence: OOM strings across chunks and UTF16 dump strings classify exhausted commit") {
  for (bool wide : {false, true}) {
    const auto root = nl::test::scratch_dir(wide ? "evidence_oom_wide" : "evidence_oom");
    std::string dump(65530, 'x');
    for (const char c : std::string("OUT OF MEMORY!")) { dump += c; if (wide) dump += '\0'; }
    write(root, "crashes/example.dmp", dump);
    const auto result = e::collect(root, e::now_filetime() + 10000000, 124);
    CHECK(result.previous.reason == "out_of_memory");
    REQUIRE(!result.previous.folder.empty());
    CHECK(nl::fs::read_file(nl::fs::join(root, result.previous.folder) / "crashes/example.dmp", 100000) == dump);
    fs::remove_all(root);
  }
}

TEST_CASE("evidence: previous start filters old and future files including stale structured crashes") {
  const auto root = nl::test::scratch_dir("evidence_times");
  const auto start = e::now_filetime() + 10000000;
  const auto since = start - 30000000;
  write(root, e::kStart, "{\"start_filetime\":" + std::to_string(since) + "}");
  write(root, "crashes/old.dmp", "OUT OF MEMORY!"); stamp(root / "crashes/old.dmp", since - 1);
  write(root, "crashes/future.dmp", "OUT OF MEMORY!"); stamp(root / "crashes/future.dmp", start + 1);
  write(root, "rtx-remix/logs/last_gpu_crash.json", "{\"event\":\"device_lost\"}");
  stamp(root / "rtx-remix/logs/last_gpu_crash.json", since - 1);
  const auto result = e::collect(root, start, 125);
  CHECK(result.notes.empty());
  CHECK(result.previous.reason == "unknown");
  CHECK(result.previous.time_utc == e::utc(since));
  CHECK(result.previous.folder.empty());
  CHECK(folders(root) == 0);
  CHECK(nl::json::parse(nl::fs::read_file(nl::fs::join(root, e::kStart), 4096)).find("start_filetime")->as_int() == static_cast<std::int64_t>(start));
  fs::remove_all(root);
}

TEST_CASE("evidence: upgrade uses the last loader record and structured crashes tolerate missing fields") {
  const auto root = nl::test::scratch_dir("evidence_upgrade");
  const auto since = e::now_filetime() - 10000000;
  write(root, "native-loader/logs/loader.log.1", "utc=before\nstartup_filetime=" + std::to_string(since) + "\nmodule=0\n");
  write(root, "rtx-remix/logs/last_gpu_crash.json", "{\"event\":\"device_lost\"}");
  const auto result = e::collect(root, e::now_filetime() + 10000000, 126);
  CHECK(result.previous.time_utc == e::utc(since));
  CHECK(result.previous.reason == "device_lost");
  CHECK(!result.previous.folder.empty());
  fs::remove_all(root);
}

TEST_CASE("evidence: empty and deliberate clean sessions make no evidence folder") {
  const auto root = nl::test::scratch_dir("evidence_empty");
  CHECK(e::collect(root, e::now_filetime(), 127).previous.folder.empty());
  write(root, "rtx-remix/logs/remix-dxvk.log", "RTX: Terminating application\n");
  const auto clean = e::collect(root, e::now_filetime() + 10000000, 127);
  CHECK(clean.previous.reason == "clean");
  CHECK(clean.previous.folder.empty());
  fs::remove_all(root);
}

TEST_CASE("evidence: locked dumps are skipped without delaying the log readiness signal") {
  const auto root = nl::test::scratch_dir("evidence_locked");
  write(root, "crashes/locked.dmp", "OUT OF MEMORY!");
  const auto source = root / "crashes/locked.dmp";
  const HANDLE lock = CreateFileW(source.c_str(), GENERIC_READ, 0, nullptr, OPEN_EXISTING, FILE_ATTRIBUTE_NORMAL, nullptr);
  REQUIRE(lock != INVALID_HANDLE_VALUE);
  bool ready = false;
  const auto result = e::collect(root, e::now_filetime() + 10000000, 128, [&] { ready = true; });
  CloseHandle(lock);
  CHECK(ready);
  CHECK(result.previous.reason == "crash");
  CHECK(!result.notes.empty());
  CHECK(nl::fs::read_file(source, 4096) == "OUT OF MEMORY!");
  CHECK(!fs::exists(nl::fs::join(root, result.previous.folder) / "crashes/locked.dmp"));
  fs::remove_all(root);
}

TEST_CASE("evidence: file and byte limits, log tail fallback, five archives, user edits preserved") {
  const auto root = nl::test::scratch_dir("evidence_retention");
  const auto start = e::now_filetime() + 10000000;
  e::Limits limits;
  limits.bytes = 128u << 10;
  limits.tail_bytes = 128;
  limits.files = 2;
  std::vector<std::string> saved;
  for (unsigned i = 0; i < 7; ++i) {
    write(root, "rtx-remix/logs/remix-dxvk.log", std::string(140000, 'x') + "\nVK_ERROR_DEVICE_LOST\n");
    stamp(root / "rtx-remix/logs/remix-dxvk.log", start + i * 10000000ull - 1);
    write(root, "crashes/too-large.dmp", std::string(200000, 'x'));
    stamp(root / "crashes/too-large.dmp", start + i * 10000000ull - 1);
    const auto result = e::collect(root, start + i * 10000000ull, 129, {}, limits);
    REQUIRE(!result.previous.folder.empty());
    saved.push_back(result.previous.folder);
    CHECK(fs::file_size(nl::fs::join(root, result.previous.folder) / "rtx-remix/logs/remix-dxvk.log") == 128);
    if (i == 0) write(root, result.previous.folder + "/rtx-remix/logs/remix-dxvk.log", "user edit");
  }
  CHECK(folders(root) == 6); // five bounded archives plus the user's edited archive
  CHECK(!fs::exists(nl::fs::join(root, saved[1])));
  CHECK(nl::fs::read_file(nl::fs::join(root, saved[0]) / "rtx-remix/logs/remix-dxvk.log", 4096) == "user edit");
  limits.bytes = 1024;
  e::retain(root, limits);
  std::uint64_t bytes = 0;
  for (const auto& folder : fs::directory_iterator(nl::fs::join(root, e::kSessions))) {
    if (folder.path().filename() == nl::fs::join(root, saved[0]).filename()) continue;
    for (const auto& file : fs::recursive_directory_iterator(folder.path())) if (file.is_regular_file()) bytes += file.file_size();
  }
  CHECK(bytes <= limits.bytes);
  fs::remove_all(root);
}

TEST_CASE("evidence: previous session status round trips and empty-start timing is measured") {
  nl::status::Report report;
  report.previous_session = {"out_of_memory", "2026-10-31T01:02:03.000Z", "native-loader/logs/sessions/test-out_of_memory"};
  const auto status = nl::json::parse(nl::status::serialize(report));
  CHECK(status.find("previous_session")->find("folder")->as_string() == report.previous_session.folder);
  CHECK(nl::status::log_fields(report).find("out_of_memory") != std::string::npos);
  const auto root = nl::test::scratch_dir("evidence_timing");
  double total = 0, maximum = 0;
  for (unsigned i = 0; i < 30; ++i) {
    const auto result = e::collect(root, e::now_filetime(), 130);
    CHECK(result.notes.empty());
    CHECK(result.previous.folder.empty());
    total += result.elapsed_ms;
    maximum = std::max(maximum, result.elapsed_ms);
  }
  std::printf("evidence empty start: mean %.3f ms, max %.3f ms (30 starts)\n", total / 30, maximum);
  fs::remove_all(root);
}
