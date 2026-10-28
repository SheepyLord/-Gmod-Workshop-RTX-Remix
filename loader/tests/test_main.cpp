// Runner for nl_tests: runs every TEST_CASE, or only those whose name contains argv[1]; with
// --skip=<text>, every TEST_CASE except those whose name contains <text>.
// Exit code 0 when at least one test ran and none failed.

#include "nl_test.h"

#include <windows.h>

#include <cstdio>
#include <cstring>
#include <exception>
#include <stdexcept>
#include <string>

namespace nl::test {

namespace {
int g_case_failures = 0;
}  // namespace

std::vector<Case>& registry() {
  static std::vector<Case> cases;
  return cases;
}

std::filesystem::path scratch_dir(std::string_view name) {
  wchar_t exe[32768]{};
  const DWORD length = GetModuleFileNameW(nullptr, exe, static_cast<DWORD>(std::size(exe)));
  if (length == 0 || length >= std::size(exe)) throw std::runtime_error("cannot locate the test executable");
  const auto dir = std::filesystem::path(exe).parent_path() / "scratch" / std::string(name);
  std::filesystem::remove_all(dir);
  std::filesystem::create_directories(dir);
  return dir;
}

void fail(const char* what, const char* file, int line) {
  ++g_case_failures;
  std::fprintf(stderr, "  %s(%d): failed: %s\n", file, line, what);
}

int run_all(const char* name_filter) {
  int run = 0;
  int failed = 0;
  constexpr const char* kSkip = "--skip=";
  const char* skip = name_filter && std::strncmp(name_filter, kSkip, std::strlen(kSkip)) == 0 ? name_filter + std::strlen(kSkip) : nullptr;
  for (const Case& c : registry()) {
    if (skip ? std::strstr(c.name, skip) != nullptr : name_filter && !std::strstr(c.name, name_filter)) {
      continue;
    }
    ++run;
    g_case_failures = 0;
    try {
      c.fn();
    } catch (const RequireFailed&) {
      // Already reported by REQUIRE.
    } catch (const std::exception& e) {
      fail(e.what(), c.file, c.line);
    } catch (...) {
      fail("unknown exception", c.file, c.line);
    }
    if (g_case_failures) {
      ++failed;
      std::printf("FAIL %s\n", c.name);
    } else {
      std::printf("ok   %s\n", c.name);
    }
  }
  std::printf("%d test case(s), %d failed\n", run, failed);
  return (run == 0 || failed) ? 1 : 0;
}

}  // namespace nl::test

int main(int argc, char** argv) {
  return nl::test::run_all(argc > 1 ? argv[1] : nullptr);
}
