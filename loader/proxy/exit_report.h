#pragma once
#include "nl/evidence.h"
#include <cstdint>
#include <filesystem>
#include <string>
#include <string_view>

namespace nl::proxy::exit_report {
// Quiet suppresses only our window, never evidence or Remix's consent prompt.
bool quiet(std::string_view environment) noexcept;
// NATIVE_LOADER_WINDOW_GHOSTING=1 keeps Windows' "Not Responding" ghosting; anything else turns it off.
bool keep_window_ghosting(std::string_view environment) noexcept;
// The session start comes from GetSystemTimeAsFileTime, which moves once per clock tick (up to 15.625
// ms); the process creation time is finer. A start read within a tick of creation can precede it,
// which made the observer refuse on CI runners at the default tick. Allows two such ticks, no more.
bool session_after_creation(std::uint64_t start, std::uint64_t created) noexcept;
std::string command_language(std::wstring_view command);
// Steam's language for the game, from steamapps/appmanifest_4000.acf ("UserConfig" "language", such as
// "schinese"): what Garry's Mod uses while gmod_language is unset. Empty when absent or unreadable.
std::string app_language(std::string_view appmanifest);
// +gmod_language, then config.cfg's gmod_language, then `os_locale` (callers pass Steam's game
// language there when they have one, then Windows'), normalized to a catalog code.
std::string language(std::string_view config, std::string_view override_code, std::string_view os_locale);
std::string message(const evidence::PreviousSession& previous, std::uint32_t code,
                    const std::filesystem::path& root, std::string_view language);
std::string title(std::string_view language);
}  // namespace nl::proxy::exit_report
