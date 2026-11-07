#pragma once
#include <windows.h>
#include <cstdint>
#include <filesystem>
#include <string>

namespace nl::proxy::observer {
// Kernel32-only, allocation-free DllMain guard. The rundll32 host never enters the loader.
bool host() noexcept;
// Called outside loader lock, after the session start record is ready and before runtime load.
// Returns a diagnostic note, including the observer PID; failures never prevent game startup.
std::string start(std::uint64_t session_start) noexcept;
// Windows marks a window "Not Responding" (and offers to close it) once its thread stops pumping
// messages for 5 s. GMod's does through Workshop remounts and big map loads, while Remix and the menu
// still draw (R8: minutes for gm_br_complex with 765 add-ons). Turns that ghosting off for this process
// unless NATIVE_LOADER_WINDOW_GHOSTING=1. Returns a diagnostic note; never fails startup.
std::string disable_window_ghosting() noexcept;
// The language Garry's Mod shows its menus in, as a ui/labels.json catalog code: +gmod_language, then
// config.cfg's gmod_language, then Steam's language for the game, then Windows' (loader 0.16.0).
std::string game_language(const std::filesystem::path& root);
}  // namespace nl::proxy::observer
