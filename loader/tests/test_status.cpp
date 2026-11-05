#include "nl/status.h"
#include "nl/json.h"
#include "nl/fs.h"
#include "nl_test.h"
#include <windows.h>
#include <filesystem>
#include <fstream>
#include <string>

TEST_CASE("status: schema includes generation activation user layers fallback and errors") {
  nl::status::Report report;
  report.loader_version = "0.1.0";
  report.utc = "2026-10-28T00:00:00.000Z";
  report.process_id = 1234;
  report.deployment.outcome = "kept";
  report.deployment.generation = 7;
  report.deployment.skipped.push_back({"local runtime.gma", "SHA-256 differs"});
  report.activation.outcome = "failed";
  report.activation.reason = "swap refused";
  report.activation.plan.runtime_id = "runtime";
  report.activation.plan.runtime_version = "1.0.0";
  report.activation.plan.user_env = {{"DXVK_RTX_CONFIG_FILE", "用户.conf,top.conf"}};
  report.activation.plan.rtx_layers = {"package/base.conf", "用户.conf", "top.conf"};
  report.activation.plan.present_args = {"-dxlevel", "95"};
  report.activation.fallback_launch_options = "-nod3d9ex +mat_disable_d3d9ex 1";
  report.activation.rolled_back = true;
  report.errors = {"line one\nline two"};
  const auto parsed = nl::json::parse(nl::status::serialize(report));
  REQUIRE(parsed.find("schema") && parsed.find("process_id") && parsed.find("activation") && parsed.find("deployment"));
  CHECK(parsed.find("schema")->as_int() == 1);
  CHECK(parsed.find("process_id")->as_int() == 1234);
  CHECK(parsed.find("deployment")->find("generation")->as_int() == 7);
  const auto& activation = *parsed.find("activation");
  CHECK(activation.find("rolled_back")->as_bool());
  CHECK(activation.find("runtime")->find("id")->as_string() == "runtime");
  CHECK(activation.find("environment")->find("set")->as_array().empty());
  CHECK(activation.find("environment")->find("user_values_kept")->as_array()[0].find("value")->as_string() == "用户.conf,top.conf");
  CHECK(activation.find("layers")->find("rtx")->as_array().back().as_string() == "top.conf");
  CHECK(activation.find("launch_arguments")->find("already_present")->as_array()[1].as_string() == "95");
  CHECK(activation.find("launch_arguments")->find("fallback_launch_options")->as_string() == report.activation.fallback_launch_options);
  CHECK(parsed.find("errors")->as_array()[0].as_string() == "line one\nline two");
  CHECK(nl::status::log_fields(report).find("activation.outcome=failed") != std::string::npos);
}

TEST_CASE("status: the companion guard's local RTX-start check matches only an active outcome") {
  // _nativeloader_guard.lua looks for this exact text (ADR 0056); a writer change must keep it.
  constexpr std::string_view marker = "\n\"activation\":{\"outcome\":\"active\"";
  nl::status::Report report;
  report.activation.outcome = "active";
  report.session.notes = {"\n\"activation\":{\"outcome\":\"active\""};  // quoted text never matches
  const auto active = nl::status::serialize(report);
  CHECK(active.find(marker) != std::string::npos);
  CHECK(active.find(marker, active.find(marker) + 1) == std::string::npos);
  for (const char* outcome : {"inactive", "failed"}) {
    report.activation.outcome = outcome;
    CHECK(nl::status::serialize(report).find(marker) == std::string::npos);
  }
}

TEST_CASE("status: atomic replacement and uninstall remove only generated data") {
  const auto root = nl::test::scratch_dir("startup_status");
  nl::status::Report report;
  report.loader_version = "0.1.0";
  report.process_id = 42;
  nl::status::write(root, report);
  report.process_id = 43;
  report.activation.reason = "no config";
  nl::status::write(root, report);
  const auto path = nl::fs::join(root, nl::status::kPath);
  CHECK(nl::json::parse(nl::fs::read_file(path, 1 << 20)).find("process_id")->as_int() == 43);
  CHECK(!std::filesystem::exists(path.native() + L".tmp-43"));
  const auto folder = path.parent_path();
  std::ofstream(folder / "keep.txt") << "user data";
  std::ofstream(folder / "status.json.tmp-999") << "interrupted generated status";
  nl::status::remove(nl::fs::win32(), root);
  CHECK(!std::filesystem::exists(path));
  CHECK(!std::filesystem::exists(folder / "status.json.tmp-999"));
  CHECK(std::filesystem::exists(folder / "keep.txt"));
  std::filesystem::remove(folder / "keep.txt");
  nl::status::remove(nl::fs::win32(), root);
  CHECK(!std::filesystem::exists(folder));
  std::filesystem::remove_all(root);
}

TEST_CASE("status: the RTX session marker lives exactly as long as its handle (R19, proxy F-02)") {
  const auto root = nl::test::scratch_dir("status_session_marker");
  const auto marker = nl::fs::join(root, nl::status::kSessionMarker);
  void* held = nl::status::hold_session_marker(root, "4242-133000000000000000");
  REQUIRE(held != nullptr);
  // Existence checks see it: attributes, a directory listing, the C++ library's status.
  CHECK(GetFileAttributesW(nl::fs::long_path(marker).c_str()) != INVALID_FILE_ATTRIBUTES);
  WIN32_FIND_DATAW found{};
  const HANDLE search = FindFirstFileW(nl::fs::long_path(marker).c_str(), &found);
  CHECK(search != INVALID_HANDLE_VALUE);
  if (search != INVALID_HANDLE_VALUE) FindClose(search);
  CHECK(std::filesystem::exists(marker));
  // A reader that shares everything reads the token.
  const HANDLE reader = CreateFileW(nl::fs::long_path(marker).c_str(), GENERIC_READ, FILE_SHARE_READ | FILE_SHARE_WRITE | FILE_SHARE_DELETE,
                                    nullptr, OPEN_EXISTING, FILE_ATTRIBUTE_NORMAL, nullptr);
  REQUIRE(reader != INVALID_HANDLE_VALUE);
  char text[64]{};
  DWORD got = 0;
  CHECK(ReadFile(reader, text, sizeof(text) - 1, &got, nullptr));
  CloseHandle(reader);
  CHECK(std::string(text, got) == "session_token=4242-133000000000000000\n");
  // Nobody else deletes or replaces it while it is held, and a held one is never cleared.
  const BOOL deleted = DeleteFileW(nl::fs::long_path(marker).c_str());
  const DWORD why = GetLastError();
  CHECK(!deleted);
  CHECK(why == ERROR_SHARING_VIOLATION);
  CHECK_THROWS_AS(nl::status::hold_session_marker(root, "4243-1"), nl::fs::Error);
  nl::status::clear_session_marker(root);
  CHECK(std::filesystem::exists(marker));
  // Closing the handle, which the end of the game process does, deletes it.
  CloseHandle(static_cast<HANDLE>(held));
  CHECK(!std::filesystem::exists(marker));
  // A leftover (what a power loss leaves): removed by a start without RTX, and by uninstall.
  std::ofstream(marker) << "session_token=1-1\n";
  nl::status::clear_session_marker(root);
  CHECK(!std::filesystem::exists(marker));
  std::ofstream(marker) << "session_token=1-1\n";
  nl::status::remove(nl::fs::win32(), root);
  CHECK(!std::filesystem::exists(marker));
  CHECK(!std::filesystem::exists(marker.parent_path()));
  std::filesystem::remove_all(root);
}

TEST_CASE("status: performance tier I2 and recoverable config notes reach status and log") {
  nl::status::Report report;
  auto& selected = report.activation.plan.performance_tier;
  selected.tier = nl::performance::Tier::low;
  selected.source = "fallback";
  selected.adapter = "RTX 4060 Ti";
  selected.dedicated_vram_mib = 16384;
  selected.reason = "old package; built-in low defaults";
  selected.layer = nl::activate::kTierLayer;
  report.activation.plan.notes = {"remix.performance_tier is invalid; using auto"};
  const auto parsed = nl::json::parse(nl::status::serialize(report));
  const auto* activation = parsed.find("activation");
  const auto* tier = activation->find("performance_tier");
  REQUIRE(tier);
  CHECK(tier->as_object().size() == 6);
  CHECK(tier->find("tier")->as_string() == "low");
  CHECK(tier->find("source")->as_string() == "fallback");
  CHECK(tier->find("dedicated_vram_mib")->as_int() == 16384);
  CHECK(tier->find("layer")->as_string() == selected.layer);
  CHECK(!activation->find("notes")->as_array().empty());
  const auto log = nl::status::log_fields(report);
  CHECK(log.find("activation.performance_tier=" + nl::performance::serialize(selected)) != std::string::npos);
  CHECK(log.find("activation.note=") != std::string::npos);
}
