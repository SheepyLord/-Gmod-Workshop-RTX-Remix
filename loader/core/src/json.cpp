#include "nl/json.h"

#include "nl/utf8.h"

#include <charconv>
#include <cmath>
#include <cstdio>
#include <unordered_set>

namespace nl::json {

namespace {

using utf8::sequence_length;

void append_utf8(std::string& out, std::uint32_t code) {
  if (code < 0x80) {
    out.push_back(static_cast<char>(code));
  } else if (code < 0x800) {
    out.push_back(static_cast<char>(0xC0 | (code >> 6)));
    out.push_back(static_cast<char>(0x80 | (code & 0x3F)));
  } else if (code < 0x10000) {
    out.push_back(static_cast<char>(0xE0 | (code >> 12)));
    out.push_back(static_cast<char>(0x80 | ((code >> 6) & 0x3F)));
    out.push_back(static_cast<char>(0x80 | (code & 0x3F)));
  } else {
    out.push_back(static_cast<char>(0xF0 | (code >> 18)));
    out.push_back(static_cast<char>(0x80 | ((code >> 12) & 0x3F)));
    out.push_back(static_cast<char>(0x80 | ((code >> 6) & 0x3F)));
    out.push_back(static_cast<char>(0x80 | (code & 0x3F)));
  }
}

class Parser {
 public:
  Parser(std::string_view text, const ParseLimits& limits) : text_(text), limits_(limits) {}

  Value document() {
    if (text_.size() > limits_.max_bytes) fail("document exceeds " + std::to_string(limits_.max_bytes) + " bytes");
    if (text_.substr(0, 3) == "\xEF\xBB\xBF") fail("byte-order mark is not allowed");
    skip_space();
    Value value = parse_value(0);
    skip_space();
    if (pos_ != text_.size()) fail("unexpected data after the value");
    return value;
  }

 private:
  [[noreturn]] void fail(const std::string& message) const {
    throw Error("JSON error at byte " + std::to_string(pos_) + ": " + message);
  }

  void skip_space() {
    while (pos_ < text_.size() &&
           (text_[pos_] == ' ' || text_[pos_] == '\t' || text_[pos_] == '\n' || text_[pos_] == '\r')) {
      ++pos_;
    }
  }

  bool consume_literal(std::string_view word) {
    if (text_.substr(pos_, word.size()) != word) return false;
    pos_ += word.size();
    return true;
  }

  Value parse_value(std::size_t depth) {
    if (++values_ > limits_.max_values) fail("more than " + std::to_string(limits_.max_values) + " values");
    if (pos_ >= text_.size()) fail("unexpected end of input");
    const char c = text_[pos_];
    if (c == '{') return parse_object(depth + 1);
    if (c == '[') return parse_array(depth + 1);
    if (c == '"') return Value::make_string(parse_string());
    if (c == '-' || (c >= '0' && c <= '9')) return parse_number();
    if (consume_literal("true")) return Value::make_bool(true);
    if (consume_literal("false")) return Value::make_bool(false);
    if (consume_literal("null")) return Value();
    fail("unexpected character");
  }

  Value parse_object(std::size_t depth) {
    if (depth > limits_.max_depth) fail("nesting deeper than " + std::to_string(limits_.max_depth));
    ++pos_;  // {
    Value::Object members;
    std::unordered_set<std::string> keys;
    skip_space();
    if (pos_ < text_.size() && text_[pos_] == '}') {
      ++pos_;
      return Value::make_object(std::move(members));
    }
    for (;;) {
      skip_space();
      if (pos_ >= text_.size() || text_[pos_] != '"') fail("expected a string key");
      std::string key = parse_string();
      if (!keys.insert(key).second) fail("duplicate key \"" + key + "\"");
      skip_space();
      if (pos_ >= text_.size() || text_[pos_] != ':') fail("expected ':'");
      ++pos_;
      skip_space();
      Value value = parse_value(depth);
      members.emplace_back(std::move(key), std::move(value));
      skip_space();
      if (pos_ < text_.size() && text_[pos_] == ',') {
        ++pos_;
        continue;
      }
      if (pos_ < text_.size() && text_[pos_] == '}') {
        ++pos_;
        return Value::make_object(std::move(members));
      }
      fail("expected ',' or '}'");
    }
  }

  Value parse_array(std::size_t depth) {
    if (depth > limits_.max_depth) fail("nesting deeper than " + std::to_string(limits_.max_depth));
    ++pos_;  // [
    Value::Array items;
    skip_space();
    if (pos_ < text_.size() && text_[pos_] == ']') {
      ++pos_;
      return Value::make_array(std::move(items));
    }
    for (;;) {
      skip_space();
      items.push_back(parse_value(depth));
      skip_space();
      if (pos_ < text_.size() && text_[pos_] == ',') {
        ++pos_;
        continue;
      }
      if (pos_ < text_.size() && text_[pos_] == ']') {
        ++pos_;
        return Value::make_array(std::move(items));
      }
      fail("expected ',' or ']'");
    }
  }

  std::uint32_t hex4() {
    if (pos_ + 4 > text_.size()) fail("truncated \\u escape");
    std::uint32_t value = 0;
    for (int i = 0; i < 4; ++i) {
      const char c = text_[pos_++];
      value <<= 4;
      if (c >= '0' && c <= '9') value |= static_cast<std::uint32_t>(c - '0');
      else if (c >= 'a' && c <= 'f') value |= static_cast<std::uint32_t>(c - 'a' + 10);
      else if (c >= 'A' && c <= 'F') value |= static_cast<std::uint32_t>(c - 'A' + 10);
      else fail("invalid \\u escape");
    }
    return value;
  }

  std::string parse_string() {
    ++pos_;  // opening quote
    std::string out;
    for (;;) {
      if (pos_ >= text_.size()) fail("unterminated string");
      if (out.size() > limits_.max_string_bytes) fail("string longer than " + std::to_string(limits_.max_string_bytes) + " bytes");
      const auto c = static_cast<unsigned char>(text_[pos_]);
      if (c == '"') {
        ++pos_;
        return out;
      }
      if (c < 0x20) fail("control character in string");
      if (c == '\\') {
        ++pos_;
        if (pos_ >= text_.size()) fail("unterminated escape");
        const char e = text_[pos_++];
        switch (e) {
          case '"': out.push_back('"'); break;
          case '\\': out.push_back('\\'); break;
          case '/': out.push_back('/'); break;
          case 'b': out.push_back('\b'); break;
          case 'f': out.push_back('\f'); break;
          case 'n': out.push_back('\n'); break;
          case 'r': out.push_back('\r'); break;
          case 't': out.push_back('\t'); break;
          case 'u': {
            std::uint32_t code = hex4();
            if (code >= 0xDC00 && code <= 0xDFFF) fail("unpaired low surrogate");
            if (code >= 0xD800 && code <= 0xDBFF) {
              if (text_.substr(pos_, 2) != "\\u") fail("unpaired high surrogate");
              pos_ += 2;
              const std::uint32_t low = hex4();
              if (low < 0xDC00 || low > 0xDFFF) fail("unpaired high surrogate");
              code = 0x10000 + ((code - 0xD800) << 10) + (low - 0xDC00);
            }
            if (code == 0) fail("NUL character in string");
            append_utf8(out, code);
            break;
          }
          default: fail("invalid escape");
        }
        continue;
      }
      const std::size_t length = sequence_length(text_, pos_);
      if (!length) fail("invalid UTF-8");
      out.append(text_.substr(pos_, length));
      pos_ += length;
    }
  }

  Value parse_number() {
    const std::size_t start = pos_;
    if (text_[pos_] == '-') ++pos_;
    if (pos_ >= text_.size()) fail("invalid number");
    if (text_[pos_] == '0') {
      ++pos_;
    } else if (text_[pos_] >= '1' && text_[pos_] <= '9') {
      while (pos_ < text_.size() && text_[pos_] >= '0' && text_[pos_] <= '9') ++pos_;
    } else {
      fail("invalid number");
    }
    bool integral = true;
    if (pos_ < text_.size() && text_[pos_] == '.') {
      integral = false;
      ++pos_;
      if (pos_ >= text_.size() || text_[pos_] < '0' || text_[pos_] > '9') fail("invalid number");
      while (pos_ < text_.size() && text_[pos_] >= '0' && text_[pos_] <= '9') ++pos_;
    }
    if (pos_ < text_.size() && (text_[pos_] == 'e' || text_[pos_] == 'E')) {
      integral = false;
      ++pos_;
      if (pos_ < text_.size() && (text_[pos_] == '+' || text_[pos_] == '-')) ++pos_;
      if (pos_ >= text_.size() || text_[pos_] < '0' || text_[pos_] > '9') fail("invalid number");
      while (pos_ < text_.size() && text_[pos_] >= '0' && text_[pos_] <= '9') ++pos_;
    }
    const std::string_view digits = text_.substr(start, pos_ - start);
    double value = 0;
    const auto [end, ec] = std::from_chars(digits.data(), digits.data() + digits.size(), value);
    if (ec != std::errc() || end != digits.data() + digits.size() || !std::isfinite(value)) {
      fail("number out of range");
    }
    std::optional<std::int64_t> integer;
    if (integral) {
      std::int64_t i = 0;
      const auto [iend, iec] = std::from_chars(digits.data(), digits.data() + digits.size(), i);
      if (iec == std::errc() && iend == digits.data() + digits.size()) integer = i;
    }
    return Value::make_number(value, integer);
  }

  std::string_view text_;
  const ParseLimits& limits_;
  std::size_t pos_ = 0;
  std::size_t values_ = 0;
};

[[noreturn]] void type_error(std::string_view what, const char* expected) {
  throw Error(std::string(what) + " must be " + expected);
}

}  // namespace

Value Value::make_bool(bool value) {
  Value v;
  v.type_ = Type::boolean;
  v.bool_ = value;
  return v;
}

Value Value::make_number(double value, std::optional<std::int64_t> integer) {
  Value v;
  v.type_ = Type::number;
  v.number_ = value;
  v.integer_ = integer;
  return v;
}

Value Value::make_string(std::string value) {
  Value v;
  v.type_ = Type::string;
  v.string_ = std::move(value);
  return v;
}

Value Value::make_array(Array items) {
  Value v;
  v.type_ = Type::array;
  v.array_ = std::move(items);
  return v;
}

Value Value::make_object(Object members) {
  Value v;
  v.type_ = Type::object;
  v.object_ = std::move(members);
  return v;
}

bool Value::as_bool(std::string_view what) const {
  if (type_ != Type::boolean) type_error(what, "true or false");
  return bool_;
}

std::int64_t Value::as_int(std::string_view what) const {
  if (type_ != Type::number || !integer_) type_error(what, "an integer");
  return *integer_;
}

double Value::as_double(std::string_view what) const {
  if (type_ != Type::number) type_error(what, "a number");
  return number_;
}

const std::string& Value::as_string(std::string_view what) const {
  if (type_ != Type::string) type_error(what, "a string");
  return string_;
}

const Value::Array& Value::as_array(std::string_view what) const {
  if (type_ != Type::array) type_error(what, "an array");
  return array_;
}

const Value::Object& Value::as_object(std::string_view what) const {
  if (type_ != Type::object) type_error(what, "an object");
  return object_;
}

const Value* Value::find(std::string_view key) const noexcept {
  if (type_ != Type::object) return nullptr;
  for (const auto& [name, value] : object_) {
    if (name == key) return &value;
  }
  return nullptr;
}

Value parse(std::string_view text, const ParseLimits& limits) {
  return Parser(text, limits).document();
}

std::string quote(std::string_view text) {
  std::string out;
  out.reserve(text.size() + 2);
  out.push_back('"');
  for (std::size_t i = 0; i < text.size();) {
    const auto c = static_cast<unsigned char>(text[i]);
    if (c == '"' || c == '\\') {
      out.push_back('\\');
      out.push_back(static_cast<char>(c));
      ++i;
    } else if (c < 0x20) {
      switch (c) {
        case '\n': out += "\\n"; break;
        case '\r': out += "\\r"; break;
        case '\t': out += "\\t"; break;
        case '\b': out += "\\b"; break;
        case '\f': out += "\\f"; break;
        default: {
          char escaped[8];
          std::snprintf(escaped, sizeof(escaped), "\\u%04x", static_cast<unsigned>(c));
          out += escaped;
        }
      }
      ++i;
    } else if (const std::size_t length = sequence_length(text, i)) {
      out.append(text.substr(i, length));
      i += length;
    } else {
      out += "\\ufffd";
      ++i;
    }
  }
  out.push_back('"');
  return out;
}

}  // namespace nl::json
