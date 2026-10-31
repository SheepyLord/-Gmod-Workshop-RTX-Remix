#pragma once

#include <string>

namespace GarrysMod::Lua {
class ILuaBase;
}

namespace RTXDebug::LuaBridge {

// RTXDebug table is on top of the caller's Lua stack. Leaves it there.
void Register(GarrysMod::Lua::ILuaBase* lua);
void Shutdown();

// Runs a statement that assigns _G.__RTXDebugSnapshot and copies that plain
// result to the caller's stack. Used for snapshots in other Lua realms. On
// failure nothing is pushed and error holds the Lua error message.
bool RunSnapshot(GarrysMod::Lua::ILuaBase* caller,
                 const char* realm,
                 const std::string& statement,
                 std::string* error = nullptr);

// Quotes text as a Lua string literal for generated snapshot statements.
std::string QuoteLua(const std::string& text);

// True when lua is the Lua state that lua_shared reports for realm ("client",
// "server" or "menu"). Read natively, not from the CLIENT/SERVER/MENU_DLL globals,
// which any script in the state can reassign. False off the game thread.
bool IsRealmState(GarrysMod::Lua::ILuaBase* lua, const char* realm);

} // namespace RTXDebug::LuaBridge
