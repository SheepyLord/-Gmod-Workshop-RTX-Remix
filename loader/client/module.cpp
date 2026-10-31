#include "catalog.h"
#include "bootstrap_data.h"
#include "nl/fs.h"
#include <GarrysMod/Lua/Interface.h>
#include <GarrysMod/Lua/LuaInterface.h>
#include <GarrysMod/Lua/LuaShared.h>
#include <windows.h>
#include <optional>

namespace {
using GarrysMod::Lua::ILuaBase;
using GarrysMod::Lua::ILuaInterface;
using GarrysMod::Lua::ILuaShared;
namespace Type = GarrysMod::Lua::Type;
std::optional<nl::client::Catalog> catalog;
ILuaShared* shared = nullptr;
ILuaBase* menu = nullptr;
ILuaInterface* client = nullptr;
std::string status = "not initialized";
constexpr const char* kHook = "NativeLoader.VerifiedRTXClient";
constexpr const char* kRegistry = "NativeLoader.VerifiedRTXClient.Identity";

bool boolean(ILuaBase* lua, const char* key) {
  lua->GetField(GarrysMod::Lua::INDEX_GLOBAL, key);
  const bool value = lua->IsType(-1, Type::Bool) && lua->GetBool(-1);
  lua->Pop();
  return value;
}
void done(ILuaInterface* lua) {
  lua->PushSpecial(GarrysMod::Lua::SPECIAL_REG);
  lua->PushString(catalog->identity.c_str());
  lua->SetField(-2, kRegistry);
  lua->Pop();
}
bool is_done(ILuaInterface* lua) {
  lua->PushSpecial(GarrysMod::Lua::SPECIAL_REG);
  lua->GetField(-1, kRegistry);
  const bool result = lua->IsType(-1, Type::String) && lua->GetString(-1) == catalog->identity;
  lua->Pop(2);
  return result;
}
LUA_FUNCTION_STATIC(Read) {
  if (!catalog || LUA != client || !LUA->IsType(1, Type::String)) {
    LUA->PushNil(); LUA->PushString("RTX payload read is unavailable in this realm"); return 2;
  }
  unsigned length = 0;
  const auto* name = LUA->GetString(1, &length);
  const auto found = catalog->scripts.find(std::string(name, length));
  if (found == catalog->scripts.end()) {
    LUA->PushNil(); LUA->PushString("File is outside the verified RTX client payload"); return 2;
  }
  LUA->PushString(found->second.text.data(), static_cast<unsigned>(found->second.text.size()));
  return 1;
}
LUA_FUNCTION_STATIC(List) {
  if (!catalog || LUA != client) { LUA->PushNil(); return 1; }
  LUA->CreateTable();
  unsigned index = 0;
  for (const auto& [name, script] : catalog->scripts) {
    (void)script;
    LUA->PushNumber(++index); LUA->PushString(name.c_str()); LUA->SetTable(-3);
  }
  return 1;
}
LUA_FUNCTION_STATIC(Finish) {
  if (!catalog || LUA != client) return 0;
  status = LUA->IsType(3, Type::String) ? LUA->GetString(3) : "client payload completed";
  done(client);
  return 0;
}
LUA_FUNCTION_STATIC(Status) {
  LUA->CreateTable();
  LUA->PushString(status.c_str()); LUA->SetField(-2, "status");
  LUA->PushBool(catalog.has_value()); LUA->SetField(-2, "verified");
  LUA->PushNumber(catalog ? static_cast<double>(catalog->scripts.size()) : 0); LUA->SetField(-2, "scripts");
  return 1;
}
LUA_FUNCTION_STATIC(Poll) {
  if (LUA != menu || !catalog || !shared) return 0;
  client = shared->GetLuaInterface(GarrysMod::Lua::State::CLIENT);
  if (!client || !boolean(client, "CLIENT_DLL") || boolean(client, "SERVER") || is_done(client)) return 0;
  client->GetField(GarrysMod::Lua::INDEX_GLOBAL, "GAMEMODE");
  const bool ready = client->IsType(-1, Type::Table);
  client->Pop();
  if (!ready) return 0;
  const int top = client->Top();
  client->CreateTable();
  client->PushCFunction(Read); client->SetField(-2, "read");
  client->PushCFunction(List); client->SetField(-2, "list");
  client->PushCFunction(Finish); client->SetField(-2, "finish");
  client->PushString(catalog->identity.c_str()); client->SetField(-2, "identity");
  client->SetField(GarrysMod::Lua::INDEX_GLOBAL, "__NATIVELOADER_CLIENT_API");
  const bool ok = client->RunStringEx("@nativeloader/verified-client-bootstrap", "", kClientBootstrap.data(), true, false, true, true);
  client->PushNil(); client->SetField(GarrysMod::Lua::INDEX_GLOBAL, "__NATIVELOADER_CLIENT_API");
  client->Pop(client->Top() - top);
  if (!ok) { status = "verified client bootstrap failed"; done(client); }
  return 0;
}
std::filesystem::path module_path(HMODULE module) {
  std::wstring buffer(32768, L'\0');
  const auto size = GetModuleFileNameW(module, buffer.data(), static_cast<DWORD>(buffer.size()));
  if (!size || size >= buffer.size()) throw std::runtime_error("Cannot resolve RTX client module path");
  buffer.resize(size);
  return std::filesystem::path(buffer).lexically_normal();
}
bool same_path(const std::filesystem::path& a, const std::filesystem::path& b) {
  const auto x = a.lexically_normal().wstring(), y = b.lexically_normal().wstring();
  return CompareStringOrdinal(x.c_str(), static_cast<int>(x.size()), y.c_str(), static_cast<int>(y.size()), TRUE) == CSTR_EQUAL;
}
void hook(ILuaBase* lua, bool add) {
  const int top = lua->Top();
  lua->GetField(GarrysMod::Lua::INDEX_GLOBAL, "hook");
  lua->GetField(-1, add ? "Add" : "Remove");
  lua->PushString("Think"); lua->PushString(kHook);
  if (add) lua->PushCFunction(Poll);
  const int result = lua->PCall(add ? 3 : 2, 0, 0);
  lua->Pop(lua->Top() - top);
  if (result != 0) throw std::runtime_error("Menu Think hook is unavailable");
}
}

GMOD_MODULE_OPEN() {
  if (!boolean(LUA, "MENU_DLL")) return 0;
  if (menu == LUA && catalog) return 0;
  try {
    HMODULE self = nullptr;
    if (!GetModuleHandleExW(GET_MODULE_HANDLE_EX_FLAG_FROM_ADDRESS | GET_MODULE_HANDLE_EX_FLAG_UNCHANGED_REFCOUNT,
                          reinterpret_cast<LPCWSTR>(&catalog), &self)) throw std::runtime_error("Cannot identify RTX client bootstrap");
    const auto file = module_path(self);
    auto root = file;
    for (unsigned i = 0; i < 4; ++i) root = root.parent_path();
    if (!same_path(file, nl::fs::join(root, nl::client::kModule))) throw std::runtime_error("RTX bootstrap is outside its deployed path");
    const auto journal = nl::journal::load(root);
    if (!journal || !journal->current || journal->pending) throw std::runtime_error("There is no committed RTX deployment");
    auto snapshot = nl::client::prepare(root, nl::config::load(root), *journal->current);
    const auto runtime = GetModuleHandleW(L"d3d9.dll");
    if (!runtime || !same_path(module_path(runtime), nl::fs::join(root, snapshot.runtime)))
      throw std::runtime_error("The owned RTX runtime is not active");
    const auto library = GetModuleHandleW(L"lua_shared.dll");
    using Factory = void* (__cdecl*)(const char*, int*);
    const auto factory = library ? reinterpret_cast<Factory>(GetProcAddress(library, "CreateInterface")) : nullptr;
    shared = factory ? static_cast<ILuaShared*>(factory(GMOD_LUASHARED_INTERFACE, nullptr)) : nullptr;
    if (!shared) throw std::runtime_error("The Lua shared interface is unavailable");
    catalog = std::move(snapshot);
    menu = LUA;
    status = "verified; waiting for the client realm";
    hook(LUA, true);
  } catch (const std::exception& error) {
    status = error.what(); catalog.reset(); shared = nullptr; menu = nullptr;
  }
  LUA->CreateTable(); LUA->PushCFunction(Status); LUA->SetField(-2, "Status");
  LUA->SetField(GarrysMod::Lua::INDEX_GLOBAL, "NativeLoaderRTXClient");
  LUA->GetField(GarrysMod::Lua::INDEX_GLOBAL, "MsgN");
  if (LUA->IsType(-1, Type::Function)) {
    LUA->PushString(("[NativeLoader RTX menu] " + status).c_str());
    if (LUA->PCall(1, 0, 0) != 0) LUA->Pop();
  } else LUA->Pop();
  return 0;
}
GMOD_MODULE_CLOSE() {
  if (menu == LUA) {
    try { hook(LUA, false); } catch (...) { }
    menu = nullptr; client = nullptr; shared = nullptr; catalog.reset();
  }
  return 0;
}
