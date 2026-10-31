#pragma once

#include <GarrysMod/Lua/LuaBase.h>

namespace RTXDebug::Transport {

bool Initialize(GarrysMod::Lua::ILuaBase* lua);
void Shutdown();

}
