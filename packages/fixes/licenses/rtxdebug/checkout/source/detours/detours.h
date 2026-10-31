#pragma once

#include <cstddef>
#include <string>
#include <vector>

namespace GarrysMod::Lua {
class ILuaBase;
}

namespace RTXDebug::Detours {

// The RTXDebug table must be at the top of the Lua stack.
void Register(GarrysMod::Lua::ILuaBase* lua);

// Detours currently enabled.
size_t ActiveDetours();

// Disables every detour and waits for running callbacks to leave. Returns how
// many were disabled and appends a message for each one that could not be.
int DisableAll(std::vector<std::string>& failures);

void Shutdown();

} // namespace RTXDebug::Detours
