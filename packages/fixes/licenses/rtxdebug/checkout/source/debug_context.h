#pragma once

#include <GarrysMod/Lua/LuaBase.h>

namespace RTXDebug {

// The client Lua state and Source interfaces are owned by the game thread.
bool IsMainThread();
bool IsSinglePlayer();
bool IsInsecureLaunch();
bool CheatsEnabled();
bool CanMutate();
bool CanConfigureRendering();
GarrysMod::Lua::ILuaBase* Lua();

}
