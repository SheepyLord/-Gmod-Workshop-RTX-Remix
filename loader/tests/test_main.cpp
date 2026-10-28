// Runner for nl_tests: runs every TEST_CASE, or only those whose name contains argv[1].
// Exit code 0 when at least one test ran and none failed.

#include "nl_test.h"

#include <cstdio>
#include <cstring>
#include <exception>

namespace nl::test {

namespace {
int g_case_failures = 0;
}  // namespace

std::vector<Case>& registry() {
  static std::vector<Case> cases;
  return cases;
}

void fail(const char* what, const char* file, int line) {
  ++g_case_failures;
  std::fprintf(stderr, "  %s(%d): failed: %s\n", file, line, what);
}

int run_all(const char* name_filter) {
  int run = 0;
  int failed = 0;
  for (const Case& c : registry()) {
    if (name_filter && !std::strstr(c.name, name_filter)) {
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
