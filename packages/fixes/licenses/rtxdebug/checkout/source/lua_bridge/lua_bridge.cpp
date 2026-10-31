#include "lua_bridge.h"

#include "../debug_context.h"
#include "../lua_util.h"

#include <GarrysMod/FactoryLoader.hpp>
#include <GarrysMod/Lua/Interface.h>
#include <GarrysMod/Lua/LuaInterface.h>
#include <GarrysMod/Lua/LuaShared.h>

#include <cstdio>
#include <initializer_list>
#include <memory>
#include <string>

using GarrysMod::Lua::ILuaBase;
using GarrysMod::Lua::ILuaInterface;
using GarrysMod::Lua::ILuaShared;
using GarrysMod::Lua::Type::Bool;
using GarrysMod::Lua::Type::Nil;
using GarrysMod::Lua::Type::Number;
using GarrysMod::Lua::Type::String;
using GarrysMod::Lua::Type::Table;

namespace RTXDebug::LuaBridge {
namespace {

constexpr const char* kSnapshotName = "__RTXDebugSnapshot";
constexpr const char* kErrorName = "__RTXDebugSnapshotError";
constexpr const char* kGameThreadError = "Lua realms must be accessed on the game thread";
constexpr int kMaxDepth = 6;
constexpr int kMaxNodes = 20000;

std::unique_ptr<SourceSDK::FactoryLoader> g_luaSharedLoader;
ILuaShared* g_luaShared = nullptr;

ILuaInterface* GetRealm(const char* name) {
    if (!g_luaShared) {
        g_luaSharedLoader = std::make_unique<SourceSDK::FactoryLoader>("lua_shared");
        g_luaShared = g_luaSharedLoader->GetInterface<ILuaShared>(GMOD_LUASHARED_INTERFACE);
    }
    if (!g_luaShared || !name) return nullptr;
    unsigned char state = GarrysMod::Lua::State::CLIENT;
    if (std::string(name) == "server") state = GarrysMod::Lua::State::SERVER;
    else if (std::string(name) == "menu") state = GarrysMod::Lua::State::MENU;
    else if (std::string(name) != "client") return nullptr;
    return g_luaShared->GetLuaInterface(state);
}

void CopyValue(ILuaBase* source, ILuaBase* destination,
               int index, int depth, int& nodes) {
    if (++nodes > kMaxNodes || depth > kMaxDepth) {
        destination->PushString("<truncated>");
        return;
    }
    switch (source->GetType(index)) {
        case Nil:
            destination->PushNil();
            return;
        case Bool:
            destination->PushBool(source->GetBool(index));
            return;
        case Number:
            destination->PushNumber(source->GetNumber(index));
            return;
        case String: {
            unsigned int length = 0;
            const char* value = source->GetString(index, &length);
            destination->PushString(value ? value : "", length);
            return;
        }
        case Table: {
            const int tableIndex = index > 0 ? index : source->Top() + index + 1;
            destination->CreateTable();
            source->PushNil();
            bool truncated = false;
            while (source->Next(tableIndex) != 0) {
                const int keyType = source->GetType(-2);
                if (keyType == String) {
                    destination->PushString(source->GetString(-2));
                } else if (keyType == Number) {
                    destination->PushNumber(source->GetNumber(-2));
                } else {
                    const char* typeName = source->GetTypeName(keyType);
                    destination->PushString(typeName ? typeName : "unknown");
                }
                CopyValue(source, destination, -1, depth + 1, nodes);
                destination->SetTable(-3);
                source->Pop(); // Value; keep key for Next.
                if (nodes >= kMaxNodes) { truncated = true; break; }
            }
            if (truncated) source->Pop(); // Key left by the interrupted iteration.
            return;
        }
        default: {
            const char* typeName = source->GetTypeName(source->GetType(index));
            std::string marker = "<";
            marker += typeName ? typeName : "userdata";
            marker += ">";
            destination->PushString(marker.c_str());
            return;
        }
    }
}

void RestoreSnapshotGlobal(ILuaBase* target, bool hadPrevious, int previousRef) {
    if (hadPrevious) target->ReferencePush(previousRef);
    else target->PushNil();
    target->SetField(GarrysMod::Lua::INDEX_GLOBAL, kSnapshotName);
    if (hadPrevious) target->ReferenceFree(previousRef);
}

// Runs code in a realm and returns all of its results. Errors from compiling
// or running it come back as nil and the message.
LUA_FUNCTION_STATIC(Eval) {
    if (!RTXDebug::IsMainThread()) return PushError(LUA, kGameThreadError);
    if (!RTXDebug::CanMutate())
        return PushError(LUA, "evaluation requires local single-player, sv_cheats 1, and -insecure");
    if (!LUA->IsType(1, String) || !LUA->IsType(2, String))
        return PushError(LUA, "Eval(realm, code) expects two strings");
    const std::string code = LUA->GetString(2);
    // The menu state has RunString but no CompileString or loadstring, so
    // there the code is turned into a function by RunString instead.
    const std::string snippet =
        "local __source=" + QuoteLua(code) + "\n"
        "local __fn,__error\n"
        "if CompileString then\n"
        "  __fn=CompileString(__source,'@rtxdebug',false)\n"
        "  if type(__fn)~='function' then __fn,__error=nil,__fn end\n"
        "else\n"
        "  _G.__RTXDebugEvalFunction=nil\n"
        "  __error=RunString('_G.__RTXDebugEvalFunction=function(...) '..__source..'\\nend','@rtxdebug',false)\n"
        "  __fn=_G.__RTXDebugEvalFunction\n"
        "  _G.__RTXDebugEvalFunction=nil\n"
        "end\n"
        "if type(__fn)~='function' then\n"
        "  _G." + std::string(kSnapshotName) + "={ok=false,error=tostring(__error or 'the code did not compile')}\n"
        "else\n"
        "  local function __pack(...) return {n=select('#',...),...} end\n"
        "  local __r=__pack(pcall(__fn))\n"
        "  if __r[1] then\n"
        "    local __values={}\n"
        "    for __i=2,__r.n do __values[__i-1]=__r[__i] end\n"
        "    _G." + std::string(kSnapshotName) + "={ok=true,n=__r.n-1,values=__values}\n"
        "  else\n"
        "    _G." + std::string(kSnapshotName) + "={ok=false,error=tostring(__r[2])}\n"
        "  end\n"
        "end";
    std::string error;
    if (!RunSnapshot(LUA, LUA->GetString(1), snippet, &error)) return PushError(LUA, error);
    if (!LUA->IsType(-1, Table)) {
        LUA->Pop();
        return PushError(LUA, "evaluation produced no result");
    }
    LUA->GetField(-1, "ok");
    const bool ok = LUA->GetBool(-1);
    LUA->Pop();
    if (!ok) {
        LUA->GetField(-1, "error");
        const std::string message = LUA->IsType(-1, String) ? LUA->GetString(-1) : "evaluation failed";
        LUA->Pop(2);
        return PushError(LUA, message);
    }
    // {n = count, values = {...}, value = values[1]}
    LUA->PushNil();
    LUA->SetField(-2, "ok");
    LUA->GetField(-1, "values");
    if (LUA->IsType(-1, Table)) {
        LUA->PushNumber(1);
        LUA->GetTable(-2);
        LUA->SetField(-3, "value");
    }
    LUA->Pop();
    return 1;
}

LUA_FUNCTION_STATIC(Global) {
    if (!RTXDebug::IsMainThread()) return PushError(LUA, kGameThreadError);
    if (!LUA->IsType(1, String) || !LUA->IsType(2, String))
        return PushError(LUA, "Global(realm, dottedPath) expects two strings");
    const std::string path = LUA->GetString(2);
    const std::string snippet =
        "local __value=_G\n"
        "for __part in string.gmatch(" + QuoteLua(path) + ", '[^%.]+') do\n"
        "  if type(__value)~='table' then __value=nil break end\n"
        "  __value=rawget(__value,__part)\n"
        "end\n"
        "_G." + std::string(kSnapshotName) + "=__value";
    std::string error;
    if (!RunSnapshot(LUA, LUA->GetString(1), snippet, &error)) return PushError(LUA, error);
    return 1;
}

LUA_FUNCTION_STATIC(Hooks) {
    if (!RTXDebug::IsMainThread()) return PushError(LUA, kGameThreadError);
    if (!LUA->IsType(1, String)) return PushError(LUA, "Hooks(realm, event) expects a realm string");
    const std::string event = LUA->IsType(2, String) ? LUA->GetString(2) : "";
    const std::string snippet =
        "local __out={} local __all=hook.GetTable() local __event=" + QuoteLua(event) + "\n"
        "for __name,__list in pairs(__all) do\n"
        "  if __event=='' or __name==__event then\n"
        "    local __entry={} local __n=0\n"
        "    for __id,__fn in pairs(__list) do\n"
        "      __n=__n+1 if __n>2048 then break end\n"
        "      local __item={id=tostring(__id),type=type(__fn)}\n"
        "      if type(__fn)=='function' and debug and debug.getinfo then\n"
        "        local __info=debug.getinfo(__fn,'S')\n"
        "        if __info then __item.source=__info.short_src __item.line=__info.linedefined end\n"
        "      end\n"
        "      __entry[#__entry+1]=__item\n"
        "    end\n"
        "    __out[__name]=__entry\n"
        "  end\n"
        "end\n"
        "_G." + std::string(kSnapshotName) + "=__out";
    std::string error;
    if (!RunSnapshot(LUA, LUA->GetString(1), snippet, &error)) return PushError(LUA, error);
    return 1;
}

LUA_FUNCTION_STATIC(GCStats) {
    if (!RTXDebug::IsMainThread()) return PushError(LUA, kGameThreadError);
    if (!LUA->IsType(1, String)) return PushError(LUA, "GCStats(realm) expects a realm string");
    std::string error;
    if (!RunSnapshot(LUA, LUA->GetString(1),
            "_G." + std::string(kSnapshotName) + "={kb=collectgarbage('count')}", &error)) {
        return PushError(LUA, error);
    }
    return 1;
}

LUA_FUNCTION_STATIC(Realms) {
    if (!RTXDebug::IsMainThread()) return PushError(LUA, kGameThreadError);
    LUA->CreateTable();
    for (const char* realm : {"client", "server", "menu"}) {
        LUA->PushBool(GetRealm(realm) != nullptr);
        LUA->SetField(-2, realm);
    }
    return 1;
}

} // namespace

std::string QuoteLua(const std::string& text) {
    std::string quoted = "\"";
    quoted.reserve(text.size() + 2);
    for (unsigned char c : text) {
        switch (c) {
            case '\\': quoted += "\\\\"; break;
            case '"': quoted += "\\\""; break;
            case '\n': quoted += "\\n"; break;
            case '\r': quoted += "\\r"; break;
            case '\t': quoted += "\\t"; break;
            default:
                if (c < 32 || c == 127) {
                    char escape[5];
                    std::snprintf(escape, sizeof(escape), "\\%03u", static_cast<unsigned>(c));
                    quoted += escape;
                } else {
                    quoted += static_cast<char>(c);
                }
                break;
        }
    }
    quoted += '"';
    return quoted;
}

bool RunSnapshot(ILuaBase* caller, const char* realm,
                 const std::string& statement, std::string* error) {
    if (!RTXDebug::IsMainThread()) {
        if (error) *error = kGameThreadError;
        return false;
    }
    ILuaInterface* target = GetRealm(realm);
    if (!target) {
        if (error) *error = "Lua realm is unavailable";
        return false;
    }
    const int before = target->Top();
    target->GetField(GarrysMod::Lua::INDEX_GLOBAL, kSnapshotName);
    const bool hadPrevious = !target->IsType(-1, Nil);
    const int previousRef = hadPrevious ? target->ReferenceCreate() : -1;
    if (!hadPrevious) target->Pop();
    target->PushNil();
    target->SetField(GarrysMod::Lua::INDEX_GLOBAL, kSnapshotName);
    // RunStringEx reports a runtime error only as false, so the statement runs
    // under pcall and leaves its message in kErrorName. A successful result is
    // made finite and free of live userdata before it crosses realms or reaches
    // the request JSON writer: vectors, angles and entities become plain
    // tables, and an invalid entity becomes nil.
    const std::string bounded =
        "local __ok,__err=pcall(function()\n" + statement + "\nend)\n"
        "if not __ok then\n"
        "  _G." + std::string(kErrorName) + "=tostring(__err)\n"
        "else\n"
        "  local __seen={} local __nodes=0\n"
        "  local function __plain(v,d)\n"
        "    __nodes=__nodes+1\n"
        "    if __nodes>20000 or d>6 then return '<truncated>' end\n"
        "    local t=type(v)\n"
        "    if t=='number' then\n"
        "      if v~=v or v==math.huge or v==-math.huge then return tostring(v) end\n"
        "      return v\n"
        "    end\n"
        "    if t=='string' or t=='boolean' or t=='nil' then return v end\n"
        "    if t=='Vector' then return {v.x,v.y,v.z} end\n"
        "    if t=='Angle' then return {v.p,v.y,v.r} end\n"
        "    if t=='Entity' or t=='Player' or t=='NPC' or t=='Weapon' or t=='Vehicle'\n"
        "      or t=='NextBot' or t=='CSEnt' then\n"
        "      if not IsValid(v) then return nil end\n"
        "      return {index=v:EntIndex(),class=v:GetClass()}\n"
        "    end\n"
        "    if t~='table' then return '<'..t..'>' end\n"
        "    if __seen[v] then return '<cycle>' end\n"
        "    __seen[v]=true local out={}\n"
        "    for k,x in pairs(v) do\n"
        "      if __nodes>20000 then break end\n"
        "      if type(k)=='string' or type(k)=='number' then out[k]=__plain(x,d+1) end\n"
        "    end\n"
        "    __seen[v]=nil return out\n"
        "  end\n"
        "  _G." + std::string(kSnapshotName) + "=__plain(_G." + std::string(kSnapshotName) + ",0)\n"
        "end";
    const bool ran = target->RunStringEx("@rtxdebug_snapshot", "", bounded.c_str(),
                                         true, false, true, true);
    while (target->Top() > before) target->Pop();
    std::string message = ran ? "" : "Lua statement did not compile in target realm";
    target->GetField(GarrysMod::Lua::INDEX_GLOBAL, kErrorName);
    if (target->IsType(-1, String)) message = target->GetString(-1);
    target->Pop();
    if (!message.empty()) {
        target->PushNil();
        target->SetField(GarrysMod::Lua::INDEX_GLOBAL, kErrorName);
        RestoreSnapshotGlobal(target, hadPrevious, previousRef);
        if (error) *error = message;
        return false;
    }
    target->GetField(GarrysMod::Lua::INDEX_GLOBAL, kSnapshotName);
    const bool sameState = static_cast<ILuaBase*>(target) == caller
        || (target->GetState() && target->GetState() == caller->GetState());
    if (!sameState) {
        int nodes = 0;
        CopyValue(target, caller, -1, 0, nodes);
        target->Pop();
    }
    RestoreSnapshotGlobal(target, hadPrevious, previousRef);
    return true;
}

void Register(ILuaBase* lua) {
    lua->CreateTable();
    AddFunction(lua, "Eval", Eval);
    AddFunction(lua, "Global", Global);
    AddFunction(lua, "Hooks", Hooks);
    AddFunction(lua, "GCStats", GCStats);
    AddFunction(lua, "Realms", Realms);
    lua->SetField(-2, "Lua");
}

void Shutdown() {
    g_luaShared = nullptr;
    g_luaSharedLoader.reset();
}

} // namespace RTXDebug::LuaBridge
