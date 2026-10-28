#include "nl/crc32.h"
#include "nl_test.h"

TEST_CASE("crc32: standard check values") {
  CHECK(nl::crc32("123456789", 9) == 0xCBF43926u);
  CHECK(nl::crc32("", 0) == 0u);
  const char text[] = "The quick brown fox jumps over the lazy dog";
  CHECK(nl::crc32(text, sizeof(text) - 1) == 0x414FA339u);
}

TEST_CASE("crc32: incremental updates equal one pass") {
  const char text[] = "The quick brown fox jumps over the lazy dog";
  const auto whole = nl::crc32(text, sizeof(text) - 1);
  CHECK(nl::crc32_update(nl::crc32(text, 10), text + 10, sizeof(text) - 11) == whole);
}
