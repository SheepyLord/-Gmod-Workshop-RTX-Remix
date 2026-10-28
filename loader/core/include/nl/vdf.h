#pragma once
// Reader for Valve's text KeyValues format: Steam's .vdf and .acf files and GMod's
// cfg/addonnomount.txt. The same rules as tools/steam/vdf.py.

#include <cstddef>
#include <filesystem>
#include <stdexcept>
#include <string>
#include <string_view>
#include <utility>
#include <vector>

namespace nl::vdf {

class Error : public std::runtime_error {
 public:
  using std::runtime_error::runtime_error;
};

struct Node {
  std::string value;                                   // leaf entries
  std::vector<std::pair<std::string, Node>> children;  // blocks, in document order
  bool block = false;
  // Child by key, compared without ASCII case as Valve's KeyValues does; the last match wins.
  const Node* find(std::string_view key) const noexcept;
};

inline constexpr std::size_t kMaxBytes = std::size_t{16} << 20;

// Quoted and unquoted tokens, \n \t \\ \" escapes, // comments; platform conditionals such as
// [$WIN32] are skipped, not evaluated. Throws Error for unbalanced braces or nesting over 64.
Node parse(std::string_view text);

// Reads and parses a file of at most kMaxBytes. Throws Error, or filesystem_error if unreadable.
Node load(const std::filesystem::path& file);

}  // namespace nl::vdf
