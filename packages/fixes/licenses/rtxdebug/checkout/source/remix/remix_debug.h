#pragma once

#include <cstddef>
#include <string>
#include <vector>

namespace GarrysMod::Lua {
class ILuaBase;
}

namespace RTXDebug::Remix {

// The RTXDebug table must be at the top of the Lua stack.
bool Register(GarrysMod::Lua::ILuaBase* lua);

// Session overrides that still have to be restored.
size_t ActiveOverrides();

// Restores every session override through RemixConfig. Call it while
// RTXFixesBinary is still loaded. Returns how many were restored and appends a
// message for each one that could not be.
int RestoreAll(GarrysMod::Lua::ILuaBase* lua, std::vector<std::string>& failures);

// Module close: restores what is left if RTXFixesBinary is still usable.
void Shutdown(GarrysMod::Lua::ILuaBase* lua);

} // namespace RTXDebug::Remix
