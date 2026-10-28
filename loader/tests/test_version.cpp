#include "nl/core.h"
#include "nl/version.h"
#include "nl_test.h"

#include <string>

TEST_CASE("version() matches the CMake project version") {
  const std::string expected = std::to_string(NL_VERSION_MAJOR) + "." + std::to_string(NL_VERSION_MINOR) +
                               "." + std::to_string(NL_VERSION_PATCH);
  CHECK(nl::version() == NL_VERSION_STRING);
  CHECK(nl::version() == expected);
}
