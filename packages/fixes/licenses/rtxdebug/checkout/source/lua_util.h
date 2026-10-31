#pragma once

#include <GarrysMod/Lua/LuaBase.h>

#include <cstdint>
#include <cstdio>
#include <string>

// Every RTXDebug function returns its result, or nil and an error message.
// The field helpers write into the table on top of the Lua stack.
namespace RTXDebug {

inline int PushError(GarrysMod::Lua::ILuaBase* lua, const char* message) {
    lua->PushNil();
    lua->PushString(message ? message : "unknown error");
    return 2;
}

inline int PushError(GarrysMod::Lua::ILuaBase* lua, const std::string& message) {
    return PushError(lua, message.c_str());
}

inline void AddFunction(GarrysMod::Lua::ILuaBase* lua, const char* name,
    GarrysMod::Lua::CFunc function) {
    lua->PushCFunction(function);
    lua->SetField(-2, name);
}

inline void SetString(GarrysMod::Lua::ILuaBase* lua, const char* key, const char* value) {
    lua->PushString(value ? value : "");
    lua->SetField(-2, key);
}

inline void SetString(GarrysMod::Lua::ILuaBase* lua, const char* key, const std::string& value) {
    lua->PushString(value.c_str(), static_cast<unsigned int>(value.size()));
    lua->SetField(-2, key);
}

inline void SetNumber(GarrysMod::Lua::ILuaBase* lua, const char* key, double value) {
    lua->PushNumber(value);
    lua->SetField(-2, key);
}

inline void SetBool(GarrysMod::Lua::ILuaBase* lua, const char* key, bool value) {
    lua->PushBool(value);
    lua->SetField(-2, key);
}

// Moves the value on top of the stack into the array just below it.
inline void SetArrayValue(GarrysMod::Lua::ILuaBase* lua, int index) {
    lua->PushNumber(index);
    lua->Insert(-2);
    lua->SetTable(-3);
}

// Addresses and 64-bit values cross into Lua as hex strings; doubles would
// lose their low bits.
inline std::string HexAddress(uintptr_t value) {
    char buffer[2 + sizeof(uintptr_t) * 2 + 1]{};
    std::snprintf(buffer, sizeof(buffer), "0x%llX", static_cast<unsigned long long>(value));
    return buffer;
}

} // namespace RTXDebug
