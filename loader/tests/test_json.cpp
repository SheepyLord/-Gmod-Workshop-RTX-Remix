#include "nl/json.h"
#include "nl_test.h"

#include <cstdint>
#include <limits>
#include <string>

using nl::json::Error;
using nl::json::parse;

TEST_CASE("json: quotes and escapes") {
  CHECK(nl::json::quote("") == "\"\"");
  CHECK(nl::json::quote("a\"b\\c") == "\"a\\\"b\\\\c\"");
  CHECK(nl::json::quote("line\nnext\ttab") == "\"line\\nnext\\ttab\"");
  CHECK(nl::json::quote(std::string("\x01\x1f", 2)) == "\"\\u0001\\u001f\"");
}

TEST_CASE("json: quote keeps valid UTF-8 and replaces invalid bytes") {
  CHECK(nl::json::quote("materials/\xC3\xA4.vmt") == "\"materials/\xC3\xA4.vmt\"");  // a-umlaut
  CHECK(nl::json::quote("\xF0\x9F\x98\x80") == "\"\xF0\x9F\x98\x80\"");              // U+1F600
  CHECK(nl::json::quote("\xFF") == "\"\\ufffd\"");
  CHECK(nl::json::quote("\xC0\xAF") == "\"\\ufffd\\ufffd\"");              // overlong '/'
  CHECK(nl::json::quote("\xED\xA0\x80") == "\"\\ufffd\\ufffd\\ufffd\"");   // surrogate U+D800
  CHECK(nl::json::quote("\xE2\x82") == "\"\\ufffd\\ufffd\"");              // truncated sequence
}

TEST_CASE("json parse: values, nesting and document order") {
  const auto v = parse(R"({"a": 1, "b": [true, false, null], "c": {"d": "x"}, "e": -2.5e3, "f": 0})");
  REQUIRE(v.is_object());
  CHECK(v.find("a")->as_int() == 1);
  REQUIRE(v.find("b")->as_array().size() == 3);
  CHECK(v.find("b")->as_array()[0].as_bool());
  CHECK(!v.find("b")->as_array()[1].as_bool());
  CHECK(v.find("b")->as_array()[2].is_null());
  CHECK(v.find("c")->find("d")->as_string() == "x");
  CHECK(v.find("e")->as_double() == -2500.0);
  CHECK_THROWS_AS(v.find("e")->as_int(), Error);  // not integral
  CHECK(v.find("f")->as_int() == 0);
  CHECK(v.find("missing") == nullptr);
  CHECK(v.as_object()[0].first == "a");
  CHECK(v.as_object()[4].first == "f");
  CHECK_THROWS_AS(v.find("a")->as_string("field a"), Error);
}

TEST_CASE("json parse: strings, escapes and surrogate pairs") {
  CHECK(parse(R"("a\"b\\c\/d\n\t")").as_string() == "a\"b\\c/d\n\t");
  CHECK(parse(R"("\u00e4\ud83d\ude00")").as_string() == "\xC3\xA4\xF0\x9F\x98\x80");
  CHECK(parse("\"\xC3\xA4\"").as_string() == "\xC3\xA4");
  CHECK(parse(" \t\r\n[ ] \n").as_array().empty());
}

TEST_CASE("json parse: int64 boundaries") {
  CHECK(parse("9223372036854775807").as_int() == std::numeric_limits<std::int64_t>::max());
  CHECK(parse("-9223372036854775808").as_int() == std::numeric_limits<std::int64_t>::min());
  const auto big = parse("9223372036854775808");
  CHECK(big.is_number());
  CHECK_THROWS_AS(big.as_int(), Error);
}

TEST_CASE("json parse: rejects everything strict JSON forbids") {
  const char* bad[] = {
      "", " ", "{", "[1,]", "{\"a\":1,}", "{'a':1}", "{\"a\" 1}", "[1 2]", "01", "1.", ".5", "+1", "-",
      "1e", "NaN", "Infinity", "tru", "nul", "\"abc", "\"\\x\"", "\"\\u12\"", "\"\\ud800\"", "\"\\udc00\"",
      "\"\\u0000\"", "{\"a\":1,\"a\":2}", "[1] 2", "// c\n1", "/* c */1", "\"\x01\"", "\"\xFF\"",
      "\xEF\xBB\xBF{}", "1e999", "{1:2}",
  };
  for (const char* text : bad) {
    bool rejected = false;
    try {
      parse(text);
    } catch (const Error&) {
      rejected = true;
    }
    if (!rejected) nl::test::fail(text, __FILE__, __LINE__);
  }
}

TEST_CASE("json parse: limits") {
  nl::json::ParseLimits limits;
  limits.max_depth = 3;
  CHECK(parse("[[[1]]]", limits).is_array());
  CHECK_THROWS_AS(parse("[[[[1]]]]", limits), Error);

  limits = {};
  limits.max_bytes = 4;
  CHECK_THROWS_AS(parse("[1,2]", limits), Error);

  limits = {};
  limits.max_string_bytes = 3;
  CHECK(parse("\"abc\"", limits).as_string() == "abc");
  CHECK_THROWS_AS(parse("\"abcdef\"", limits), Error);

  limits = {};
  limits.max_values = 3;  // the array counts too
  CHECK(parse("[1,2]", limits).as_array().size() == 2);
  CHECK_THROWS_AS(parse("[1,2,3]", limits), Error);
}

TEST_CASE("json: quoted strings parse back unchanged") {
  for (const std::string& text :
       {std::string("plain"), std::string("q\"b\\s\n\t\x01"), std::string("\xC3\xA4\xF0\x9F\x98\x80")}) {
    CHECK(parse(nl::json::quote(text)).as_string() == text);
  }
}
