#pragma once
#include <windows.h>
#include <cstdint>
#include <string>

namespace nl::proxy::observer {
// Kernel32-only, allocation-free DllMain guard. The rundll32 host never enters the loader.
bool host() noexcept;
// Called outside loader lock, after the session start record is ready and before runtime load.
// Returns a diagnostic note, including the observer PID; failures never prevent game startup.
std::string start(std::uint64_t session_start) noexcept;
}  // namespace nl::proxy::observer
