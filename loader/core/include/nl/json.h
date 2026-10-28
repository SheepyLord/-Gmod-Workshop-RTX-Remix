#pragma once
// Minimal JSON for the loader: a strict parser for package manifests and config.json (untrusted
// or user-edited input), and string quoting for the files nlctl and the loader write.

#include <cstddef>
#include <cstdint>
#include <optional>
#include <stdexcept>
#include <string>
#include <string_view>
#include <utility>
#include <vector>

namespace nl::json {

// Syntax error, limit exceeded, or a value used as the wrong type.
class Error : public std::runtime_error {
 public:
  using std::runtime_error::runtime_error;
};

class Value {
 public:
  enum class Type { null, boolean, number, string, array, object };
  using Array = std::vector<Value>;
  using Object = std::vector<std::pair<std::string, Value>>;  // document order, keys unique

  Value() = default;
  static Value make_bool(bool value);
  static Value make_number(double value, std::optional<std::int64_t> integer);
  static Value make_string(std::string value);
  static Value make_array(Array items);
  static Value make_object(Object members);

  Type type() const noexcept { return type_; }
  bool is_null() const noexcept { return type_ == Type::null; }
  bool is_bool() const noexcept { return type_ == Type::boolean; }
  bool is_number() const noexcept { return type_ == Type::number; }
  bool is_string() const noexcept { return type_ == Type::string; }
  bool is_array() const noexcept { return type_ == Type::array; }
  bool is_object() const noexcept { return type_ == Type::object; }

  // Accessors throw Error naming `what` when the type does not match.
  bool as_bool(std::string_view what = "value") const;
  std::int64_t as_int(std::string_view what = "value") const;  // integral and within int64 only
  double as_double(std::string_view what = "value") const;
  const std::string& as_string(std::string_view what = "value") const;
  const Array& as_array(std::string_view what = "value") const;
  const Object& as_object(std::string_view what = "value") const;

  // Object member, or nullptr if this is not an object or has no such key.
  const Value* find(std::string_view key) const noexcept;

 private:
  Type type_ = Type::null;
  bool bool_ = false;
  double number_ = 0;
  std::optional<std::int64_t> integer_;
  std::string string_;
  Array array_;
  Object object_;
};

struct ParseLimits {
  std::size_t max_bytes = std::size_t{1} << 20;  // whole document
  std::size_t max_depth = 32;                    // nested arrays/objects
  std::size_t max_string_bytes = 64 * 1024;      // one string after unescaping
  std::size_t max_values = 100000;               // values in the whole document
};

// Strict RFC 8259: UTF-8 (a byte-order mark is rejected), no comments, no trailing commas, no
// duplicate object keys, no NaN or Infinity, numbers within double range, nothing after the value.
// Throws Error("JSON error at byte N: ...").
Value parse(std::string_view text, const ParseLimits& limits = {});

// `text` as a JSON string literal, quotes included. Valid UTF-8 is kept, invalid bytes become
// U+FFFD (one per byte), and quotes, backslashes and control characters are escaped.
std::string quote(std::string_view text);

}  // namespace nl::json
