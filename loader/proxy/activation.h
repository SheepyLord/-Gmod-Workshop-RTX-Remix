#pragma once
#include <string_view>

namespace nl::proxy {

// All functions here are allocation-free, noexcept and independent of Win32.
bool path_equal(std::wstring_view left, std::wstring_view right) noexcept;
std::wstring_view game_root(std::wstring_view exe) noexcept;
bool command_line_has_token(std::wstring_view line, std::wstring_view token) noexcept;

struct Activation {
  bool host_matches{};
  bool command_line_disabled{};
  bool environment_disabled{};
  bool file_disabled{};
  bool active() const noexcept {
    return host_matches && !command_line_disabled && !environment_disabled && !file_disabled;
  }
};

Activation should_activate(std::wstring_view exe, std::wstring_view module,
                           std::wstring_view command_line, std::wstring_view environment,
                           bool disable_file_exists) noexcept;
}  // namespace nl::proxy
