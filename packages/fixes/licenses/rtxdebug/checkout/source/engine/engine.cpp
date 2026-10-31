#include "engine.h"

#include "../debug_context.h"
#include "../lua_bridge/lua_bridge.h"
#include "../lua_util.h"
#include "../memory/memory_debug.h"

#include <GarrysMod/FactoryLoader.hpp>
#include <GarrysMod/Lua/Interface.h>

#include <cdll_int.h>
#include <filesystem.h>
#include <icvar.h>
#include <materialsystem/imaterial.h>
#include <materialsystem/imaterialsystem.h>
#include <materialsystem/imaterialvar.h>
#include <materialsystem/itexture.h>
#include <texture_group_names.h>
#include <tier0/dbg.h>
#include <tier1/convar.h>

#include <algorithm>
#include <climits>
#include <cmath>
#include <cstring>
#include <memory>
#include <string>
#include <vector>

using GarrysMod::Lua::ILuaBase;
using GarrysMod::Lua::Type::Number;
using GarrysMod::Lua::Type::String;

namespace RTXDebug::Engine {
namespace {

constexpr const char* kGameThreadError = "Source interfaces must be accessed on the game thread";
constexpr const char* kGateError = "mutation requires local single-player, sv_cheats 1, and -insecure";

struct SavedConVar {
    std::string name;
    std::string value;
};

// GMod x64's vstdlib gives its cvar iterator a virtual destructor ahead of the
// four methods sourcesdk-minimal declares (CCvar::CCVarIteratorInternal has five
// vtable entries; entry 0 deletes). Calling through the SDK's ICvar::Iterator
// therefore deletes the iterator in SetFirst and crashes the game.
class CvarIterator {
public:
    virtual ~CvarIterator() = default;
    virtual void SetFirst() = 0;
    virtual void Next() = 0;
    virtual bool IsValid() = 0;
    virtual ConCommandBase* Get() = 0;
};

// FactoryInternalIterator itself is in the SDK's slot, but protected.
struct CvarIteratorFactory : ICvar {
    static CvarIterator* Create(ICvar* console) {
        const auto factory = &CvarIteratorFactory::FactoryInternalIterator;
        return reinterpret_cast<CvarIterator*>((console->*factory)());
    }
};

// Deleting through the virtual destructor frees the iterator with vstdlib's
// own allocator.
using CvarIteratorPtr = std::unique_ptr<CvarIterator>;

std::unique_ptr<SourceSDK::FactoryLoader> g_cvarLoader;
std::unique_ptr<SourceSDK::FactoryLoader> g_engineLoader;
std::unique_ptr<SourceSDK::FactoryLoader> g_materialLoader;
std::unique_ptr<SourceSDK::FactoryLoader> g_fileLoader;
ICvar* g_cvar = nullptr;
IVEngineClient* g_engine = nullptr;
IMaterialSystem* g_materials = nullptr;
IFileSystem* g_filesystem = nullptr;
// Original values of convars changed through SetConVar, in change order.
std::vector<SavedConVar> g_convarChanges;

ICvar* Cvar() {
    if (!g_cvar) {
        g_cvarLoader = std::make_unique<SourceSDK::FactoryLoader>("vstdlib");
        g_cvar = g_cvarLoader->GetInterface<ICvar>(CVAR_INTERFACE_VERSION);
    }
    return g_cvar;
}

IVEngineClient* EngineClient() {
    if (!g_engine) {
        g_engineLoader = std::make_unique<SourceSDK::FactoryLoader>("engine");
        g_engine = g_engineLoader->GetInterface<IVEngineClient>(VENGINE_CLIENT_INTERFACE_VERSION);
    }
    return g_engine;
}

IMaterialSystem* Materials() {
    if (!g_materials) {
        g_materialLoader = std::make_unique<SourceSDK::FactoryLoader>("materialsystem");
        g_materials = g_materialLoader->GetInterface<IMaterialSystem>(MATERIAL_SYSTEM_INTERFACE_VERSION);
    }
    return g_materials;
}

IFileSystem* Filesystem() {
    if (!g_filesystem) {
        g_fileLoader = std::make_unique<SourceSDK::FactoryLoader>("filesystem_stdio");
        g_filesystem = g_fileLoader->GetInterface<IFileSystem>(FILESYSTEM_INTERFACE_VERSION);
    }
    return g_filesystem;
}

std::vector<SavedConVar>::iterator FindSaved(const char* name) {
    return std::find_if(g_convarChanges.begin(), g_convarChanges.end(),
        [name](const SavedConVar& saved) { return saved.name == name; });
}

// Offsets and limits arrive as Lua numbers; non-finite values use the fallback.
int ReadInt(ILuaBase* lua, int index, int fallback, int minimum, int maximum) {
    if (!lua->IsType(index, Number)) return fallback;
    const double value = lua->GetNumber(index);
    if (!std::isfinite(value)) return fallback;
    return static_cast<int>((std::clamp)(std::trunc(value),
        static_cast<double>(minimum), static_cast<double>(maximum)));
}

bool HasPrefix(const char* name, const std::string& prefix) {
    return prefix.empty() || _strnicmp(name, prefix.c_str(), prefix.size()) == 0;
}

LUA_FUNCTION_STATIC(ListConsole) {
    if (!RTXDebug::IsMainThread()) return PushError(LUA, kGameThreadError);
    ICvar* console = Cvar();
    if (!console) return PushError(LUA, "ICvar is unavailable");
    const std::string prefix = LUA->IsType(1, String) ? LUA->GetString(1) : "";
    const int offset = ReadInt(LUA, 2, 0, 0, INT_MAX);
    const int limit = ReadInt(LUA, 3, 200, 1, 1000);
    CvarIteratorPtr iterator(CvarIteratorFactory::Create(console));
    if (!iterator) return PushError(LUA, "the console cannot be iterated");
    LUA->CreateTable();
    LUA->CreateTable();
    int total = 0, emitted = 0;
    for (iterator->SetFirst(); iterator->IsValid(); iterator->Next()) {
        ConCommandBase* entry = iterator->Get();
        const char* name = entry ? entry->GetName() : nullptr;
        if (!name || !HasPrefix(name, prefix)) continue;
        ++total;
        if (total <= offset || emitted >= limit) continue;
        LUA->CreateTable();
        SetString(LUA, "name", name);
        SetBool(LUA, "command", entry->IsCommand());
        SetNumber(LUA, "flags", entry->GetFlags());
        SetString(LUA, "help", entry->GetHelpText());
        if (!entry->IsCommand()) {
            ConVar* variable = static_cast<ConVar*>(entry);
            SetString(LUA, "value", variable->GetString());
            SetString(LUA, "default", variable->GetDefault());
        }
        SetArrayValue(LUA, ++emitted);
    }
    LUA->SetField(-2, "items");
    SetNumber(LUA, "total", total);
    return 1;
}

LUA_FUNCTION_STATIC(GetConVar) {
    if (!RTXDebug::IsMainThread()) return PushError(LUA, kGameThreadError);
    if (!LUA->IsType(1, String)) return PushError(LUA, "GetConVar(name) expects a string");
    ICvar* console = Cvar();
    ConVar* variable = console ? console->FindVar(LUA->GetString(1)) : nullptr;
    if (!variable) return PushError(LUA, "convar was not found");
    LUA->CreateTable();
    SetString(LUA, "name", variable->GetName());
    SetString(LUA, "value", variable->GetString());
    SetString(LUA, "default", variable->GetDefault());
    SetString(LUA, "help", variable->GetHelpText());
    SetNumber(LUA, "flags", variable->GetFlags());
    float boundary = 0;
    if (variable->GetMin(boundary)) SetNumber(LUA, "min", boundary);
    if (variable->GetMax(boundary)) SetNumber(LUA, "max", boundary);
    const auto saved = FindSaved(variable->GetName());
    if (saved != g_convarChanges.end()) SetString(LUA, "restore_value", saved->value);
    return 1;
}

LUA_FUNCTION_STATIC(SetConVar) {
    if (!RTXDebug::IsMainThread()) return PushError(LUA, kGameThreadError);
    if (!RTXDebug::CanMutate()) return PushError(LUA, kGateError);
    if (!LUA->IsType(1, String) || !LUA->IsType(2, String))
        return PushError(LUA, "SetConVar(name, value) expects two strings");
    ICvar* console = Cvar();
    ConVar* variable = console ? console->FindVar(LUA->GetString(1)) : nullptr;
    if (!variable) return PushError(LUA, "convar was not found");
    // Key the ledger by the registered spelling; lookups are case-insensitive.
    const std::string name = variable->GetName();
    const std::string value = LUA->GetString(2);
    const std::string previous = variable->GetString();
    if (FindSaved(name.c_str()) == g_convarChanges.end()) g_convarChanges.push_back({name, previous});
    variable->SetValue(value.c_str());
    Msg("[RTXDebug] convar %s: '%s' -> '%s'\n", name.c_str(), previous.c_str(), variable->GetString());
    LUA->CreateTable();
    SetString(LUA, "previous", previous);
    SetString(LUA, "value", variable->GetString());
    return 1;
}

// Restoring only undoes this module's own change, so it needs no mutation gate.
LUA_FUNCTION_STATIC(RestoreConVar) {
    if (!RTXDebug::IsMainThread()) return PushError(LUA, kGameThreadError);
    if (!LUA->IsType(1, String)) return PushError(LUA, "RestoreConVar(name) expects a string");
    ICvar* console = Cvar();
    ConVar* variable = console ? console->FindVar(LUA->GetString(1)) : nullptr;
    if (!variable) return PushError(LUA, "convar was not found");
    const auto saved = FindSaved(variable->GetName());
    if (saved == g_convarChanges.end()) return PushError(LUA, "no session override exists for this convar");
    variable->SetValue(saved->value.c_str());
    Msg("[RTXDebug] restored convar %s\n", saved->name.c_str());
    g_convarChanges.erase(saved);
    LUA->PushBool(true);
    return 1;
}

LUA_FUNCTION_STATIC(ConVarOverrides) {
    if (!RTXDebug::IsMainThread()) return PushError(LUA, kGameThreadError);
    ICvar* console = Cvar();
    LUA->CreateTable();
    int index = 1;
    for (const SavedConVar& saved : g_convarChanges) {
        LUA->CreateTable();
        SetString(LUA, "name", saved.name);
        SetString(LUA, "restore_value", saved.value);
        if (ConVar* variable = console ? console->FindVar(saved.name.c_str()) : nullptr)
            SetString(LUA, "value", variable->GetString());
        SetArrayValue(LUA, index++);
    }
    return 1;
}

LUA_FUNCTION_STATIC(Exec) {
    if (!RTXDebug::IsMainThread()) return PushError(LUA, kGameThreadError);
    if (!RTXDebug::CanMutate()) return PushError(LUA, kGateError);
    if (!LUA->IsType(1, String)) return PushError(LUA, "Exec(command) expects a string");
    IVEngineClient* engine = EngineClient();
    if (!engine) return PushError(LUA, "IVEngineClient is unavailable");
    const char* command = LUA->GetString(1);
    Msg("[RTXDebug] executing console command: %s\n", command);
    engine->ClientCmd_Unrestricted(command);
    LUA->PushBool(true);
    return 1;
}

LUA_FUNCTION_STATIC(World) {
    if (!RTXDebug::IsMainThread()) return PushError(LUA, kGameThreadError);
    IVEngineClient* engine = EngineClient();
    if (!engine) return PushError(LUA, "IVEngineClient is unavailable");
    int width = 0, height = 0;
    engine->GetScreenSize(width, height);
    const bool inGame = engine->IsInGame();
    LUA->CreateTable();
    SetBool(LUA, "in_game", inGame);
    SetBool(LUA, "connected", engine->IsConnected());
    SetString(LUA, "map", inGame ? engine->GetLevelName() : "");
    SetNumber(LUA, "map_version", inGame ? engine->GetLevelVersion() : 0);
    SetNumber(LUA, "max_clients", engine->GetMaxClients());
    SetNumber(LUA, "local_player", engine->GetLocalPlayer());
    SetNumber(LUA, "screen_width", width);
    SetNumber(LUA, "screen_height", height);
    SetString(LUA, "game_directory", engine->GetGameDirectory());
    return 1;
}

LUA_FUNCTION_STATIC(Entities) {
    if (!RTXDebug::IsMainThread()) return PushError(LUA, kGameThreadError);
    const std::string realm = LUA->IsType(1, String) ? LUA->GetString(1) : "client";
    const std::string classFilter = LUA->IsType(2, String) ? LUA->GetString(2) : "";
    const int offset = ReadInt(LUA, 3, 0, 0, INT_MAX);
    const int limit = ReadInt(LUA, 4, 200, 1, 1000);
    const std::string statement =
        "local __out={} local __total=0 local __filter=" + LuaBridge::QuoteLua(classFilter) + "\n"
        "local __offset=" + std::to_string(offset) + " local __limit=" + std::to_string(limit) + "\n"
        "for _,__e in ipairs(ents.GetAll()) do\n"
        "  if IsValid(__e) then\n"
        "    local __class=__e:GetClass()\n"
        "    if __filter=='' or __class==__filter then\n"
        "      __total=__total+1\n"
        "      if __total>__offset and #__out<__limit then\n"
        "        local __item={index=__e:EntIndex(),class=__class,model=__e:GetModel(),\n"
        "          health=__e:Health(),skin=__e:GetSkin(),material=__e:GetMaterial(),\n"
        "          position=__e:GetPos(),angles=__e:GetAngles(),color=__e:GetColor(),\n"
        "          player=__e:IsPlayer(),npc=__e:IsNPC()}\n"
        "        if __e:IsPlayer() then __item.name=__e:Nick() end\n"
        "        __out[#__out+1]=__item\n"
        "      end\n"
        "    end\n"
        "  end\n"
        "end\n"
        "_G.__RTXDebugSnapshot={total=__total,items=__out}";
    std::string error;
    if (!LuaBridge::RunSnapshot(LUA, realm.c_str(), statement, &error)) return PushError(LUA, error);
    return 1;
}

// One entity in detail, including the model's material list that Remix
// texture hashes resolve to. Optional getters are called through pcall.
LUA_FUNCTION_STATIC(EntityInfo) {
    if (!RTXDebug::IsMainThread()) return PushError(LUA, kGameThreadError);
    const std::string realm = LUA->IsType(1, String) ? LUA->GetString(1) : "client";
    if (!LUA->IsType(2, Number)) return PushError(LUA, "Entity(realm, index) expects an entity index");
    const double index = LUA->GetNumber(2);
    if (!std::isfinite(index) || std::trunc(index) != index || index < 0 || index > 65535)
        return PushError(LUA, "entity index must be an integer from 0 to 65535");
    const std::string statement =
        "local __e=Entity(" + std::to_string(static_cast<int>(index)) + ")\n"
        "local function __call(f,...)\n"
        "  if not f then return nil end\n"
        "  local __ok,__v=pcall(f,...)\n"
        "  if __ok then return __v end\n"
        "end\n"
        "if IsValid(__e) then\n"
        "  local __out={index=__e:EntIndex(),class=__e:GetClass(),model=__e:GetModel(),\n"
        "    skin=__e:GetSkin(),material=__e:GetMaterial(),health=__e:Health(),\n"
        "    player=__e:IsPlayer(),npc=__e:IsNPC(),weapon=__e:IsWeapon(),\n"
        "    no_draw=__e:GetNoDraw(),model_scale=__e:GetModelScale(),\n"
        "    render_mode=__e:GetRenderMode(),render_fx=__e:GetRenderFX(),\n"
        "    position=__e:GetPos(),angles=__e:GetAngles(),velocity=__e:GetVelocity(),\n"
        "    mins=__e:OBBMins(),maxs=__e:OBBMaxs(),color=__e:GetColor(),\n"
        "    parent=__e:GetParent(),owner=__e:GetOwner(),\n"
        "    bones=__call(__e.GetBoneCount,__e),sequence=__call(__e.GetSequence,__e),\n"
        "    cycle=__call(__e.GetCycle,__e),flexes=__call(__e.GetFlexNum,__e),\n"
        "    nwvars=__call(__e.GetNWVarTable,__e)}\n"
        "  if __e:IsPlayer() then __out.name=__e:Nick() end\n"
        "  local __materials=__call(__e.GetMaterials,__e) or {}\n"
        "  __out.materials=__materials\n"
        "  local __sub={}\n"
        "  for __i=0,#__materials-1 do\n"
        "    local __s=__call(__e.GetSubMaterial,__e,__i)\n"
        "    if __s and __s~='' then __sub[tostring(__i)]=__s end\n"
        "  end\n"
        "  __out.submaterials=__sub\n"
        "  local __groups={}\n"
        "  for _,__g in ipairs(__call(__e.GetBodyGroups,__e) or {}) do\n"
        "    __groups[#__groups+1]={id=__g.id,name=__g.name,count=__g.num,value=__e:GetBodygroup(__g.id)}\n"
        "  end\n"
        "  __out.bodygroups=__groups\n"
        "  _G.__RTXDebugSnapshot=__out\n"
        "end";
    std::string error;
    if (!LuaBridge::RunSnapshot(LUA, realm.c_str(), statement, &error)) return PushError(LUA, error);
    if (LUA->IsType(-1, GarrysMod::Lua::Type::Nil)) {
        LUA->Pop();
        return PushError(LUA, "entity is not valid in this realm");
    }
    return 1;
}

LUA_FUNCTION_STATIC(InterfaceStatus) {
    if (!RTXDebug::IsMainThread()) return PushError(LUA, kGameThreadError);
    struct InterfaceSpec { const char* key; const char* module; const char* version; };
    const InterfaceSpec specs[] = {
        {"engine", "engine", VENGINE_CLIENT_INTERFACE_VERSION},
        {"modelinfo", "engine", "VModelInfoClient006"},
        {"renderview", "engine", "VEngineRenderView014"},
        {"enginetrace", "engine", "EngineTraceClient003"},
        {"client", "client", CLIENT_DLL_INTERFACE_VERSION},
        {"entitylist", "client", "VClientEntityList003"},
        {"materialsystem", "materialsystem", MATERIAL_SYSTEM_INTERFACE_VERSION},
        {"studiorender", "studiorender", "VStudioRender026"},
        {"mdlcache", "datacache", "MDLCache004"},
        {"shaderapi", "shaderapidx9", "ShaderApi030"},
        {"vgui", "vguimatsurface", "VGUI_Surface030"},
        {"cvar", "vstdlib", CVAR_INTERFACE_VERSION},
        {"filesystem", "filesystem_stdio", FILESYSTEM_INTERFACE_VERSION},
        {"lua_shared", "lua_shared", "LUASHARED003"}
    };
    LUA->CreateTable();
    for (const InterfaceSpec& spec : specs) {
        SourceSDK::FactoryLoader loader(spec.module);
        LUA->CreateTable();
        SetString(LUA, "module", spec.module);
        SetString(LUA, "version", spec.version);
        SetBool(LUA, "available", loader.GetInterface<void>(spec.version) != nullptr);
        LUA->SetField(-2, spec.key);
    }
    return 1;
}

// Addresses for memory-level work on an interface: the instance, its vtable
// and the vtable's offset in the module that implements it.
LUA_FUNCTION_STATIC(ResolveInterface) {
    if (!RTXDebug::IsMainThread()) return PushError(LUA, kGameThreadError);
    if (!LUA->IsType(1, String) || !LUA->IsType(2, String))
        return PushError(LUA, "Resolve(module, version) expects two strings");
    SourceSDK::FactoryLoader loader(LUA->GetString(1));
    if (!loader.IsValid()) return PushError(LUA, "module is not loaded or exports no CreateInterface");
    void* instance = loader.GetInterface<void>(LUA->GetString(2));
    if (!instance) return PushError(LUA, "the module does not export this interface version");
    const uintptr_t base = reinterpret_cast<uintptr_t>(loader.GetModule());
    const uintptr_t address = reinterpret_cast<uintptr_t>(instance);
    LUA->CreateTable();
    SetString(LUA, "module_base", HexAddress(base));
    SetString(LUA, "address", HexAddress(address));
    uintptr_t vtable = 0;
    if (Memory::ReadPointer(address, vtable)) {
        SetString(LUA, "vtable", HexAddress(vtable));
        if (vtable > base && Memory::AllocationBase(vtable) == base)
            SetString(LUA, "vtable_rva", HexAddress(vtable - base));
    }
    return 1;
}

const char* MaterialVarTypeName(MaterialVarType_t type) {
    switch (type) {
    case MATERIAL_VAR_TYPE_FLOAT: return "float";
    case MATERIAL_VAR_TYPE_STRING: return "string";
    case MATERIAL_VAR_TYPE_VECTOR: return "vector";
    case MATERIAL_VAR_TYPE_TEXTURE: return "texture";
    case MATERIAL_VAR_TYPE_INT: return "int";
    case MATERIAL_VAR_TYPE_FOURCC: return "fourcc";
    case MATERIAL_VAR_TYPE_MATRIX: return "matrix";
    case MATERIAL_VAR_TYPE_MATERIAL: return "material";
    default: return "undefined";
    }
}

// Pushes {["$name"] = {type, value}} for the defined shader parameters. Texture
// names are read only from precached materials, so a query never loads one.
void PushMaterialParams(ILuaBase* lua, IMaterial* material) {
    lua->CreateTable();
    const int count = material->ShaderParamCount();
    IMaterialVar** params = material->GetShaderParams();
    const bool precached = material->IsPrecached();
    for (int i = 0; params && i < count; ++i) {
        IMaterialVar* variable = params[i];
        if (!variable || !variable->IsDefined()) continue;
        const char* name = variable->GetName();
        if (!name || !*name) continue;
        const MaterialVarType_t type = variable->GetType();
        lua->CreateTable();
        SetString(lua, "type", MaterialVarTypeName(type));
        switch (type) {
        case MATERIAL_VAR_TYPE_FLOAT:
        case MATERIAL_VAR_TYPE_INT:
        case MATERIAL_VAR_TYPE_VECTOR:
        case MATERIAL_VAR_TYPE_STRING:
            SetString(lua, "value", variable->GetStringValue());
            break;
        case MATERIAL_VAR_TYPE_TEXTURE:
            if (precached) {
                if (ITexture* texture = variable->GetTextureValue()) {
                    SetString(lua, "value", texture->GetName());
                    SetBool(lua, "error", texture->IsError());
                }
            }
            break;
        case MATERIAL_VAR_TYPE_MATERIAL:
            if (IMaterial* value = variable->GetMaterialValue()) SetString(lua, "value", value->GetName());
            break;
        default:
            break;
        }
        lua->SetField(-2, name);
    }
}

void PushMaterialFlags(ILuaBase* lua, IMaterial* material) {
    struct FlagName { MaterialVarFlags_t flag; const char* name; };
    static constexpr FlagName flags[] = {
        {MATERIAL_VAR_TRANSLUCENT, "translucent"}, {MATERIAL_VAR_ALPHATEST, "alphatest"},
        {MATERIAL_VAR_ADDITIVE, "additive"}, {MATERIAL_VAR_NOCULL, "nocull"},
        {MATERIAL_VAR_SELFILLUM, "selfillum"}, {MATERIAL_VAR_DECAL, "decal"},
        {MATERIAL_VAR_MODEL, "model"}, {MATERIAL_VAR_VERTEXCOLOR, "vertexcolor"},
        {MATERIAL_VAR_VERTEXALPHA, "vertexalpha"}, {MATERIAL_VAR_NO_DRAW, "nodraw"}
    };
    lua->CreateTable();
    for (const FlagName& entry : flags) SetBool(lua, entry.name, material->GetMaterialVarFlag(entry.flag));
}

LUA_FUNCTION_STATIC(MaterialInfo) {
    if (!RTXDebug::IsMainThread()) return PushError(LUA, kGameThreadError);
    if (!LUA->IsType(1, String)) return PushError(LUA, "Material(name) expects a string");
    IMaterialSystem* materialSystem = Materials();
    if (!materialSystem) return PushError(LUA, "IMaterialSystem is unavailable");
    const char* name = LUA->GetString(1);
    // FindMaterial would load an unknown material; only report loaded ones.
    if (!materialSystem->IsMaterialLoaded(name)) return PushError(LUA, "material is not loaded");
    IMaterial* material = materialSystem->FindMaterial(name, TEXTURE_GROUP_OTHER, false);
    if (!material) return PushError(LUA, "material is not loaded");
    LUA->CreateTable();
    SetString(LUA, "name", material->GetName());
    SetString(LUA, "shader", material->GetShaderName());
    SetString(LUA, "group", material->GetTextureGroupName());
    SetNumber(LUA, "width", material->GetMappingWidth());
    SetNumber(LUA, "height", material->GetMappingHeight());
    SetBool(LUA, "error", material->IsErrorMaterial());
    SetBool(LUA, "precached", material->IsPrecached());
    PushMaterialFlags(LUA, material);
    LUA->SetField(-2, "flags");
    PushMaterialParams(LUA, material);
    LUA->SetField(-2, "params");
    return 1;
}

LUA_FUNCTION_STATIC(MaterialList) {
    if (!RTXDebug::IsMainThread()) return PushError(LUA, kGameThreadError);
    IMaterialSystem* materialSystem = Materials();
    if (!materialSystem) return PushError(LUA, "IMaterialSystem is unavailable");
    const std::string prefix = LUA->IsType(1, String) ? LUA->GetString(1) : "";
    const int offset = ReadInt(LUA, 2, 0, 0, INT_MAX);
    const int limit = ReadInt(LUA, 3, 200, 1, 1000);
    LUA->CreateTable();
    LUA->CreateTable();
    int total = 0, emitted = 0;
    // The material system expects the walk to run to InvalidMaterial.
    const MaterialHandle_t invalid = materialSystem->InvalidMaterial();
    for (MaterialHandle_t handle = materialSystem->FirstMaterial(); handle != invalid;
         handle = materialSystem->NextMaterial(handle)) {
        IMaterial* material = materialSystem->GetMaterial(handle);
        const char* name = material ? material->GetName() : nullptr;
        if (!name || !HasPrefix(name, prefix)) continue;
        ++total;
        if (total <= offset || emitted >= limit) continue;
        LUA->CreateTable();
        SetString(LUA, "name", name);
        SetString(LUA, "shader", material->GetShaderName());
        SetString(LUA, "group", material->GetTextureGroupName());
        SetBool(LUA, "error", material->IsErrorMaterial());
        SetBool(LUA, "precached", material->IsPrecached());
        SetArrayValue(LUA, ++emitted);
    }
    LUA->SetField(-2, "items");
    SetNumber(LUA, "total", total);
    SetNumber(LUA, "loaded", materialSystem->GetNumMaterials());
    return 1;
}

LUA_FUNCTION_STATIC(FileExists) {
    if (!RTXDebug::IsMainThread()) return PushError(LUA, kGameThreadError);
    if (!LUA->IsType(1, String)) return PushError(LUA, "FileExists(path, pathId) expects a path");
    IFileSystem* filesystem = Filesystem();
    if (!filesystem) return PushError(LUA, "IFileSystem is unavailable");
    const char* pathId = LUA->IsType(2, String) ? LUA->GetString(2) : nullptr;
    LUA->PushBool(filesystem->FileExists(LUA->GetString(1), pathId));
    return 1;
}

// There is deliberately no VGUI surface query: in GMod x64's CMatSystemSurface
// GetScreenSize sits one vtable slot after where ISurfaceV30 declares it.
// Engine.World reports the screen size through IVEngineClient instead.

} // namespace

void Register(ILuaBase* lua) {
    lua->CreateTable();
    AddFunction(lua, "ListConsole", ListConsole);
    AddFunction(lua, "GetConVar", GetConVar);
    AddFunction(lua, "SetConVar", SetConVar);
    AddFunction(lua, "RestoreConVar", RestoreConVar);
    AddFunction(lua, "ConVarOverrides", ConVarOverrides);
    AddFunction(lua, "Exec", Exec);
    AddFunction(lua, "World", World);
    AddFunction(lua, "Entities", Entities);
    AddFunction(lua, "Entity", EntityInfo);
    lua->SetField(-2, "Engine");

    lua->CreateTable();
    AddFunction(lua, "Status", InterfaceStatus);
    AddFunction(lua, "Resolve", ResolveInterface);
    AddFunction(lua, "Material", MaterialInfo);
    AddFunction(lua, "Materials", MaterialList);
    AddFunction(lua, "FileExists", FileExists);
    lua->SetField(-2, "Interfaces");
}

size_t ActiveOverrides() {
    return g_convarChanges.size();
}

int RestoreConVars(std::vector<std::string>& failures) {
    int restored = 0;
    ICvar* console = g_convarChanges.empty() ? nullptr : Cvar();
    for (auto it = g_convarChanges.rbegin(); it != g_convarChanges.rend(); ++it) {
        ConVar* variable = console ? console->FindVar(it->name.c_str()) : nullptr;
        if (!variable) {
            failures.push_back("convar " + it->name + " is no longer registered");
            continue;
        }
        variable->SetValue(it->value.c_str());
        Msg("[RTXDebug] restored convar %s\n", it->name.c_str());
        ++restored;
    }
    g_convarChanges.clear();
    return restored;
}

void Shutdown() {
    if (RTXDebug::IsMainThread()) {
        std::vector<std::string> failures;
        RestoreConVars(failures);
        for (const std::string& failure : failures) Warning("[RTXDebug] %s\n", failure.c_str());
    }
    g_convarChanges.clear();
    g_cvar = nullptr;
    g_engine = nullptr;
    g_materials = nullptr;
    g_filesystem = nullptr;
    g_cvarLoader.reset();
    g_engineLoader.reset();
    g_materialLoader.reset();
    g_fileLoader.reset();
}

} // namespace RTXDebug::Engine
