#pragma once
// UTF-8 validation shared by the JSON parser and the path rules.

#include <cstddef>
#include <string_view>

namespace nl::utf8 {

// Length of the well-formed UTF-8 sequence at text[i], or 0 if there is none: overlong forms,
// surrogates, code points above U+10FFFF and truncated sequences are all rejected.
std::size_t sequence_length(std::string_view text, std::size_t i) noexcept;

bool valid(std::string_view text) noexcept;

}  // namespace nl::utf8
