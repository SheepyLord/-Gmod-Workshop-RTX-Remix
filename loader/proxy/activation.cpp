#include "activation.h"

namespace nl::proxy {
namespace {
wchar_t folded(wchar_t c) noexcept {
  if (c >= L'A' && c <= L'Z') return c + (L'a' - L'A');
  return c == L'/' ? L'\\' : c;
}
bool whitespace(wchar_t c) noexcept { return c == L' ' || c == L'\t'; }
}  // namespace

bool path_equal(std::wstring_view left, std::wstring_view right) noexcept {
  if (left.size() != right.size()) return false;
  for (std::size_t i = 0; i < left.size(); ++i) {
    if (folded(left[i]) != folded(right[i])) return false;
  }
  return true;
}

std::wstring_view game_root(std::wstring_view exe) noexcept {
  constexpr std::wstring_view suffix = L"\\bin\\win64\\gmod.exe";
  if (exe.size() <= suffix.size() || !path_equal(exe.substr(exe.size() - suffix.size()), suffix)) return {};
  const auto root = exe.substr(0, exe.size() - suffix.size());
  // Only absolute drive or UNC paths supplied by GetModuleFileNameW are valid.
  if (root.size() >= 2 && folded(root[0]) >= L'a' && folded(root[0]) <= L'z' &&
      root[1] == L':' && folded(exe[2]) == L'\\') {
    return root.size() == 2 ? exe.substr(0, 3) : root;
  }
  if (root.size() > 2 && folded(root[0]) == L'\\' && folded(root[1]) == L'\\') {
    const auto share_separator = root.find_first_of(L"\\/", 2);
    if (share_separator != std::wstring_view::npos && share_separator + 1 < root.size()) return root;
  }
  return {};
}

bool command_line_has_token(std::wstring_view line, std::wstring_view token, bool allow_assignment) noexcept {
  std::size_t pos = 0;
  while (pos < line.size()) {
    while (pos < line.size() && whitespace(line[pos])) ++pos;
    if (pos == line.size()) break;
    bool quoted = false;
    bool matches = true;
    bool assignment = false;
    std::size_t length = 0;
    const auto emit = [&](wchar_t c) noexcept {
      if (length < token.size()) {
        if (folded(c) != folded(token[length])) matches = false;
      } else if (allow_assignment && length == token.size() && c == L'=') {
        assignment = true;
      } else if (!assignment) {
        matches = false;
      }
      ++length;
    };
    while (pos < line.size() && (quoted || !whitespace(line[pos]))) {
      std::size_t slashes = 0;
      while (pos < line.size() && line[pos] == L'\\') { ++slashes; ++pos; }
      if (pos < line.size() && line[pos] == L'"') {
        for (std::size_t i = 0; i < slashes / 2; ++i) emit(L'\\');
        if (slashes % 2) {
          emit(L'"');
          ++pos;
        } else if (quoted && pos + 1 < line.size() && line[pos + 1] == L'"') {
          emit(L'"');
          pos += 2;
        } else {
          quoted = !quoted;
          ++pos;
        }
      } else {
        for (std::size_t i = 0; i < slashes; ++i) emit(L'\\');
        if (pos < line.size() && (quoted || !whitespace(line[pos]))) emit(line[pos++]);
      }
    }
    if (matches && (length == token.size() || assignment)) return true;
  }
  return false;
}

Activation should_activate(std::wstring_view exe, std::wstring_view module,
                           std::wstring_view line, std::wstring_view environment,
                           bool disable_file_exists) noexcept {
  const auto root = game_root(exe);
  const auto exe_separator = exe.find_last_of(L"\\/");
  const auto dll_separator = module.find_last_of(L"\\/");
  const bool host = !root.empty() && dll_separator != std::wstring_view::npos &&
      path_equal(exe.substr(0, exe_separator), module.substr(0, dll_separator)) &&
      path_equal(module.substr(dll_separator + 1), L"winmm.dll");
  return {host, command_line_has_token(line, L"-nonativeloader"), environment == L"1", disable_file_exists,
          command_line_has_token(line, L"--type", true)};
}
}  // namespace nl::proxy
