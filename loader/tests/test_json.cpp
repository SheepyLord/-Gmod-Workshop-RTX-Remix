#include "nl/json.h"
#include "nl_test.h"

#include <string>

TEST_CASE("json: quotes and escapes") {
  CHECK(nl::json::quote("") == "\"\"");
  CHECK(nl::json::quote("a\"b\\c") == "\"a\\\"b\\\\c\"");
  CHECK(nl::json::quote("line\nnext\ttab") == "\"line\\nnext\\ttab\"");
  CHECK(nl::json::quote(std::string("\x01\x1f", 2)) == "\"\\u0001\\u001f\"");
}

TEST_CASE("json: keeps valid UTF-8 and replaces invalid bytes") {
  CHECK(nl::json::quote("materials/\xC3\xA4.vmt") == "\"materials/\xC3\xA4.vmt\"");  // a-umlaut
  CHECK(nl::json::quote("\xF0\x9F\x98\x80") == "\"\xF0\x9F\x98\x80\"");              // U+1F600
  CHECK(nl::json::quote("\xFF") == "\"\\ufffd\"");
  CHECK(nl::json::quote("\xC0\xAF") == "\"\\ufffd\\ufffd\"");    // overlong '/'
  CHECK(nl::json::quote("\xED\xA0\x80") == "\"\\ufffd\\ufffd\\ufffd\"");  // surrogate U+D800
  CHECK(nl::json::quote("\xE2\x82") == "\"\\ufffd\\ufffd\"");    // truncated sequence
}
