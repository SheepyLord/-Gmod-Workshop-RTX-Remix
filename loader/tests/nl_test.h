#pragma once
// Minimal self-registering test harness for nl_tests (no third-party dependency).
//
//   TEST_CASE("parses an empty archive") {
//     REQUIRE(archive.has_value());   // records a failure and ends this test case
//     CHECK(archive->files.empty());  // records a failure and carries on
//   }

#include <vector>

namespace nl::test {

struct Case {
  const char* name;
  void (*fn)();
  const char* file;
  int line;
};

std::vector<Case>& registry();
void fail(const char* what, const char* file, int line);
int run_all(const char* name_filter);

struct RequireFailed {};

struct Registrar {
  Registrar(const char* name, void (*fn)(), const char* file, int line) {
    registry().push_back({name, fn, file, line});
  }
};

}  // namespace nl::test

#define NL_TEST_CAT2(a, b) a##b
#define NL_TEST_CAT(a, b) NL_TEST_CAT2(a, b)

#define TEST_CASE(name)                                                   \
  static void NL_TEST_CAT(nl_test_fn_, __LINE__)();                       \
  static const ::nl::test::Registrar NL_TEST_CAT(nl_test_reg_, __LINE__)( \
      name, &NL_TEST_CAT(nl_test_fn_, __LINE__), __FILE__, __LINE__);     \
  static void NL_TEST_CAT(nl_test_fn_, __LINE__)()

#define CHECK(expr)                                  \
  do {                                               \
    if (!(expr)) {                                   \
      ::nl::test::fail(#expr, __FILE__, __LINE__);   \
    }                                                \
  } while (false)

#define REQUIRE(expr)                                \
  do {                                               \
    if (!(expr)) {                                   \
      ::nl::test::fail(#expr, __FILE__, __LINE__);   \
      throw ::nl::test::RequireFailed{};             \
    }                                                \
  } while (false)
