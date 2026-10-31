#pragma once

#include <GarrysMod/Lua/LuaBase.h>

#include <cstddef>
#include <cstdint>
#include <string>
#include <vector>

namespace RTXDebug::Memory {

// The caller leaves the RTXDebug table at the top of the Lua stack. This
// function adds its Memory field and leaves the parent table in place.
void RegisterLua(GarrysMod::Lua::ILuaBase* lua, bool (*canMutate)());

// Reads one pointer from a committed, readable page. False if it is not.
bool ReadPointer(uintptr_t address, uintptr_t& value);

// Base of the allocation (module image, heap block) containing address, or 0.
uintptr_t AllocationBase(uintptr_t address);

// Typed writes and applied patches that are still in place.
size_t ActiveMutations();

// Restore every active write and patch in reverse order. Patch definitions
// stay, so they can be applied again. Returns how many were restored and
// appends a message for each one that could not be.
int RestoreAll(std::vector<std::string>& failures);

// Restore everything, then forget all writes and patches. Returns false if a
// target has disappeared or a write could not be restored.
bool Shutdown();

} // namespace RTXDebug::Memory
