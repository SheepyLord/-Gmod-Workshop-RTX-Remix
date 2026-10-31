#pragma once

#include <cstddef>
#include <string>
#include <vector>

namespace GarrysMod::Lua {
class ILuaBase;
}

namespace RTXDebug::Engine {

// RTXDebug table is on top of the stack. Registers Engine and Interfaces.
void Register(GarrysMod::Lua::ILuaBase* lua);

// Convars changed through this module's API that are not restored yet.
size_t ActiveOverrides();

// Restores those convars. Returns how many were restored and appends a
// message for each one that could not be.
int RestoreConVars(std::vector<std::string>& failures);

// Restores convars and releases the Source interfaces.
void Shutdown();

} // namespace RTXDebug::Engine
