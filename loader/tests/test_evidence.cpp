#include "nl/evidence.h"
#include "nl/fs.h"
#include "nl/json.h"
#include "nl/memory.h"
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

TEST_CASE("evidence exit: NTSTATUS and Win32 failures, normal quits and generic codes") {
  for (const auto code : {0xC0000017u, 0xC000012Du, 8u, 14u})
    CHECK(e::classify({}, {}, false, false, e::Exit{code}) == "out_of_memory");
  for (const auto code : {0xC0000005u, 0xC0000409u, 0xC00000FDu, 0xE06D7363u, 1u, 259u, 42u})
    CHECK(e::classify({}, {}, false, false, e::Exit{code}) == "crash");
  CHECK(e::classify({}, {}, false, false, e::Exit{0, true}) == "clean");
  CHECK(e::classify("VK_ERROR_DEVICE_LOST (nonfatal log noise)", {}, false, false, e::Exit{0}) == "clean");
  CHECK(e::classify("RTX: Terminating application", {}, false, false, e::Exit{1, true}) == "clean");
  CHECK(e::classify("RTX: Terminating application", {}, false, false, e::Exit{0xC0000005u}) == "crash");
  CHECK(!e::needs_report("clean")); CHECK(!e::needs_report("unknown")); CHECK(e::needs_report("crash"));
}

TEST_CASE("evidence exit: concrete failures outrank generic exit codes and memory inference") {
  CHECK(e::classify("Exiting after GPU device loss", {}, false, false, e::Exit{0}) == "device_lost");
  CHECK(e::classify({}, R"({"event":"device_lost"})", false, false, e::Exit{0}) == "device_lost");
  CHECK(e::classify("Memory allocation failed", {}, false, false, e::Exit{1, true}) == "allocation_failed");
  CHECK(e::classify("Exception on CS thread", {}, false, false, e::Exit{1, true}) == "cs_exception");
  CHECK(e::classify("Exiting after GPU device loss", {}, false, false, e::Exit{0xC0000017u}) == "out_of_memory");
  CHECK(e::classify({}, {}, true, false, e::Exit{1, true}) == "crash");
  CHECK(e::classify({}, {}, true, true, e::Exit{1, true}) == "out_of_memory");
  CHECK(e::classify({}, {}, false, false, e::Exit{1, true}) == "likely_out_of_memory");
  CHECK(e::classify({}, {}, false, false, e::Exit{0xC00000FDu, true}) == "crash");
}

TEST_CASE("evidence exit: archived JSON and next start reuse one conclusion without duplicate archives") {
  const auto root = nl::test::scratch_dir("evidence_exit_reuse");
  const auto start = e::now_filetime() - 10000000;
  e::collect(root, start, 701);
  write(root, "rtx-remix/logs/remix-dxvk.log", "Exiting after GPU device loss\n");
  const auto result = e::finish(root, start, 701, 1, "701-123", true);
  CHECK(result.notes.empty()); CHECK(result.previous.reason == "device_lost");
  REQUIRE(!result.previous.folder.empty());
  const auto report = nl::json::parse(nl::fs::read_file(nl::fs::join(root, result.previous.folder) / "exit-report.json", 4096));
  CHECK(report.find("exit_code")->as_int() == 1); CHECK(report.find("process_id")->as_int() == 701);
  CHECK(report.find("dialog_suppressed")->as_bool()); CHECK(report.find("abnormal")->as_bool());
  CHECK(report.find("previous_session")->find("folder")->as_string() == result.previous.folder);
  const auto next = e::collect(root, e::now_filetime() + 10000000, 702);
  CHECK(next.notes.empty()); CHECK(next.previous.reason == result.previous.reason);
  CHECK(next.previous.folder == result.previous.folder); CHECK(folders(root) == 1);
  CHECK(nl::fs::read_file(root / "rtx-remix/logs/remix-dxvk.log", 4096) == "Exiting after GPU device loss\n");
  fs::remove_all(root);
}

TEST_CASE("evidence exit: normal exits make no report and later clean starts do not evict crash evidence") {
  const auto root = nl::test::scratch_dir("evidence_exit_clean");
  const auto start = e::now_filetime() - 10000000;
  e::collect(root, start, 703);
  write(root, "rtx-remix/logs/remix-dxvk.log", "ordinary RTX session with no shutdown marker\n");
  write(root, "native-loader/logs/gpu/shaderDebugInfo/healthy.nvdbg", "shader debug data");
  const auto result = e::finish(root, start, 703, 0, "703-123", true);
  CHECK(result.notes.empty()); CHECK(result.previous.reason == "clean"); CHECK(result.previous.folder.empty());
  CHECK(folders(root) == 0);
  const auto next = e::collect(root, e::now_filetime(), 704);
  CHECK(next.previous.reason == "clean"); CHECK(next.previous.folder.empty()); CHECK(folders(root) == 0);
  fs::remove_all(root);
}

TEST_CASE("evidence exit: fresh dumps and bounded OOM scans work without a Remix log") {
  for (const auto text : {"generic crash dump", "OUT OF MEMORY!"}) {
    const auto root = nl::test::scratch_dir("evidence_exit_dump");
    const auto start = e::now_filetime() - 10000000;
    e::collect(root, start, 705);
    write(root, "crashes/fresh.dmp", text);
    const auto result = e::finish(root, start, 705, 0, "705-123", true);
    CHECK(result.previous.reason == (std::string_view(text).starts_with("OUT") ? "out_of_memory" : "crash"));
    REQUIRE(!result.previous.folder.empty());
    CHECK(fs::exists(nl::fs::join(root, result.previous.folder) / "exit-report.json"));
    fs::remove_all(root);
  }
}

TEST_CASE("evidence exit: last commit sample requires the same token, freshness and near-limit bytes") {
  for (unsigned i = 0; i < 7; ++i) {
    const auto root = nl::test::scratch_dir("evidence_exit_commit");
    const auto now = e::now_filetime(), start = now - 600000000;
    e::collect(root, start, 706);
    nl::memory::Sample sample;
    sample.time_utc = e::utc(i == 2 ? now - 310000000 : i == 3 ? now + 600000000 : now);
    sample.commit_limit = 90ull << 30;
    sample.commit_total = *sample.commit_limit - (512ull << 20) - (i == 4 ? 1 : 0);
    if (i == 5) sample.commit_limit = 0;
    nl::memory::write_commit(root, sample, i == 1 ? "old-token" : "706-123");
    const auto result = e::finish(root, start, 706, i == 6 ? 0 : 1, "706-123", true);
    CHECK(result.previous.reason == (i == 0 ? "likely_out_of_memory" : i == 6 ? "clean" : "crash"));
    fs::remove_all(root);
  }
}

TEST_CASE("evidence exit: a complete recent CSV sample can supply commit evidence without the snapshot") {
  const auto root = nl::test::scratch_dir("evidence_exit_csv");
  const auto now = e::now_filetime(), start = now - 600000000;
  e::collect(root, start, 707);
  nl::memory::Sample sample; sample.time_utc = e::utc(now);
  sample.commit_limit = 32ull << 30; sample.commit_total = *sample.commit_limit;
  write(root, nl::memory::kCsv, std::string(nl::memory::csv_header()) + nl::memory::csv_line(sample) + "partial,row");
  const auto result = e::finish(root, start, 707, 1, "707-123", true);
  CHECK(result.notes.empty()); CHECK(result.previous.reason == "likely_out_of_memory");
  fs::remove_all(root);
}

TEST_CASE("evidence exit: stale sources and changed session records cannot report another game") {
  const auto root = nl::test::scratch_dir("evidence_exit_identity");
  const auto now = e::now_filetime(), start = now - 10000000;
  e::collect(root, start, 708);
  write(root, "rtx-remix/logs/remix-dxvk.log", "Exiting after GPU device loss\n");
  stamp(root / "rtx-remix/logs/remix-dxvk.log", start - 1);
  const auto ended = e::finish(root, start, 708, 1, "708-123", true);
  CHECK(ended.previous.reason == "crash");
  const auto duplicate = e::finish(root, start, 708, 1, "708-123", true);
  CHECK(!duplicate.notes.empty()); CHECK(!e::needs_report(duplicate.previous.reason)); CHECK(folders(root) == 1);
  e::collect(root, now, 709);
  const auto marker = nl::fs::read_file(nl::fs::join(root, e::kStart), 4096);
  CHECK(!e::needs_report(e::finish(root, start, 708, 0xC0000017u, "708-123", true).previous.reason));
  CHECK(nl::fs::read_file(nl::fs::join(root, e::kStart), 4096) == marker);
  write(root, e::kStart, marker + " ");
  CHECK(!e::needs_report(e::finish(root, now, 709, 1, "709-123", true).previous.reason));
  CHECK(nl::fs::read_file(nl::fs::join(root, e::kStart), 4096) == marker + " ");
  fs::remove_all(root);
}

TEST_CASE("evidence exit: malformed end metadata falls back to the original collector") {
  const auto root = nl::test::scratch_dir("evidence_exit_malformed");
  write(root, e::kStart, "{\"start_filetime\":1,\"end\":{\"previous_session\":{}}}");
  const auto result = e::collect(root, e::now_filetime(), 710);
  CHECK(result.notes.empty()); CHECK(result.previous.reason == "unknown");
  fs::remove_all(root);
}

TEST_CASE("evidence exit: retention preserves an edited exit report and removes only intact reports") {
  const auto root = nl::test::scratch_dir("evidence_exit_retention");
  const auto start = e::now_filetime() - 10000000;
  e::collect(root, start, 711);
  const auto ended = e::finish(root, start, 711, 0xC0000017u, "711-123", true);
  REQUIRE(!ended.previous.folder.empty());
  const auto path = ended.previous.folder + "/exit-report.json";
  const auto original = nl::fs::read_file(nl::fs::join(root, path), 4096);
  write(root, path, "user's diagnosis\n");
  e::Limits limits; limits.sessions = 0;
  e::retain(root, limits);
  CHECK(folders(root) == 1); CHECK(nl::fs::read_file(nl::fs::join(root, path), 4096) == "user's diagnosis\n");
  write(root, path, original);
  e::retain(root, limits); CHECK(folders(root) == 0);
  fs::remove_all(root);
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
  report.session_token = "123-456";
  report.previous_session = {"out_of_memory", "2026-10-31T01:02:03.000Z", "native-loader/logs/sessions/test-out_of_memory"};
  const auto status = nl::json::parse(nl::status::serialize(report));
  CHECK(status.find("session_token")->as_string() == report.session_token);
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
