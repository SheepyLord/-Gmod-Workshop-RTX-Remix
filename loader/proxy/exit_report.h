#pragma once
#include "nl/evidence.h"
#include <filesystem>
#include <string>
#include <string_view>

namespace nl::proxy::exit_report {
// Quiet suppresses only our window, never evidence or Remix's consent prompt.
bool quiet(std::string_view environment) noexcept;
// NATIVE_LOADER_WINDOW_GHOSTING=1 keeps Windows' "Not Responding" ghosting; anything else turns it off.
bool keep_window_ghosting(std::string_view environment) noexcept;
std::string command_language(std::wstring_view command);
std::string language(std::string_view config, std::string_view override_code, std::string_view os_locale);
std::string message(const evidence::PreviousSession& previous, std::uint32_t code,
                    const std::filesystem::path& root, std::string_view language);
std::string title(std::string_view language);
}  // namespace nl::proxy::exit_report
