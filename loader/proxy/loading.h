#pragma once
// The loading window (loader 0.16.0, ADR 0128). Start-up work runs at the game's entry point, before
// Garry's Mod opens a window of its own; the first start after installing or updating the RTX
// package unpacks about 2 GB there, which took a minute with nothing on screen. This window says what
// is happening until the game's own window appears.
//
// loading_text.cpp holds the pure parts (tests/test_loading.cpp); loading_window.cpp the window, on a
// thread of its own, with user32 and gdi32 bound at run time so the import table stays KERNEL32-only.
#include "nl/deploy.h"
#include <cstdint>
#include <string>
#include <string_view>

namespace nl::proxy::loading {

// NATIVE_LOADER_LOADING_WINDOW: "0", "off", "false" or "no" never shows it; "always" shows it at once
// (screenshots, tests); anything else, or nothing, decides by itself.
enum class Mode { automatic, always, off };
Mode mode(std::string_view environment) noexcept;

// A start-up that unpacks at least kMinimumUnpack bytes shows the window after kGraceMs; any start-up
// still working after kSlowStartMs shows it too. An ordinary start does neither, so nothing flashes.
inline constexpr std::uint64_t kMinimumUnpack = std::uint64_t{64} << 20;
inline constexpr std::uint64_t kGraceMs = 400;
inline constexpr std::uint64_t kSlowStartMs = 3000;
bool should_show(Mode mode, std::uint64_t elapsed_ms, std::uint64_t unpack_bytes) noexcept;

// 0 to 100; 0 while nothing is to be unpacked.
int percent(std::uint64_t done, std::uint64_t total) noexcept;

// The window's text in one language of ui/labels.json (as exit_report::language returns it); a
// missing language or label falls back to English.
struct Catalog {
  std::string title, heading, body, checking, unpacking, placing, starting, megabytes, gigabytes, decimal;
};
Catalog catalog(std::string_view language);
// "850 MB", "1.2 GB" ("1,2 Go" in French): binary units, as Windows shows file sizes.
std::string size_text(const Catalog& text, std::uint64_t bytes);
// The line under the progress bar for a deploy::Progress phase.
std::string status_text(const Catalog& text, std::uint32_t phase, std::uint64_t done, std::uint64_t total);

// The window. start() begins a thread that opens the window once should_show() says so; finish() says
// start-up work is over: an open window then stays until this process shows a visible window of its
// own (the game's) or game_wait_ms pass, and one that never opened never will. Neither throws, waits
// or fails start-up; at most one window per process.
inline constexpr std::uint32_t kGameWaitMs = 120000;
inline constexpr wchar_t kClassName[] = L"NativeLoaderLoadingWindow";
void start(std::string_view language, const deploy::Progress* progress, Mode mode,
           std::uint32_t game_wait_ms = kGameWaitMs) noexcept;
void finish() noexcept;
// For the start-up report, before finish(): whether and when the window opened.
std::string note();

// How the window thread ended, for tests: still running, never shown, the game's window appeared,
// game_wait_ms passed, or the window could not be created (user32/gdi32 unavailable, no desktop).
enum class Ended { running, not_shown, game_window, timed_out, unavailable };
Ended ended() noexcept;
// Tests: waits up to `milliseconds` for the window thread to end; true if it has.
bool wait(std::uint32_t milliseconds) noexcept;
// Tests: lets start() run again once the previous thread has ended; false while it still runs.
bool reset_for_tests() noexcept;

}  // namespace nl::proxy::loading
