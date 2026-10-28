#pragma once
// Minimal JSON text helpers, shared by nlctl and (later) the journal and status files.

#include <string>
#include <string_view>

namespace nl::json {

// `text` as a JSON string literal, quotes included. Valid UTF-8 is kept, invalid bytes become
// U+FFFD (one per byte), and quotes, backslashes and control characters are escaped.
std::string quote(std::string_view text);

}  // namespace nl::json
