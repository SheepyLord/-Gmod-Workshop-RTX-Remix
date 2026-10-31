#include "catalog.h"
#include "bootstrap_data.h"
#include "poll.h"
#include "nl/fs.h"
#include <GarrysMod/Lua/Interface.h>
#include <GarrysMod/Lua/LuaInterface.h>
#include <GarrysMod/Lua/LuaShared.h>
#include <windows.h>
#include <optional>
#include <string_view>

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
nl::client::PollGate gate;
constexpr const char* kHook = "NativeLoader.VerifiedRTXClient";
constexpr const char* kRegistry = "NativeLoader.VerifiedRTXClient.Identity";
constexpr const char* kAttempts = "NativeLoader.VerifiedRTXClient.Attempts";
constexpr const char* kApi = "__NATIVELOADER_CLIENT_API";

// Menu realm only: that state is ours.
bool boolean(ILuaBase* lua, const char* key) {
  lua->GetField(GarrysMod::Lua::INDEX_GLOBAL, key);
  const bool value = lua->IsType(-1, Type::Bool) && lua->GetBool(-1);
  lua->Pop();
  return value;
}
// Client realm: server Lua may have set metamethods on _G (a __newindex could take the API), so
// every access there is raw. Pushes table[key].
void raw_get(ILuaBase* lua, int table, const char* key) {
  lua->PushSpecial(table);
  lua->PushString(key);
  lua->RawGet(-2);
  lua->Remove(-2);
}
// table[key] = the value on top of the stack, which is popped.
void raw_set(ILuaBase* lua, int table, const char* key) {
  lua->PushSpecial(table);
  lua->Insert(-2);
  lua->PushString(key);
  lua->Insert(-2);
  lua->RawSet(-3);
  lua->Pop();
}
bool raw_bool(ILuaBase* lua, const char* key) {
  raw_get(lua, GarrysMod::Lua::SPECIAL_GLOB, key);
  const bool value = lua->IsType(-1, Type::Bool) && lua->GetBool(-1);
  lua->Pop();
  return value;
}
void done(ILuaBase* lua) {
  lua->PushString(catalog->identity.c_str());
  raw_set(lua, GarrysMod::Lua::SPECIAL_REG, kRegistry);
}
bool is_done(ILuaBase* lua) {
  raw_get(lua, GarrysMod::Lua::SPECIAL_REG, kRegistry);
  unsigned length = 0;
  const char* text = lua->IsType(-1, Type::String) ? lua->GetString(-1, &length) : nullptr;
  const bool result = text && std::string_view(text, length) == std::string_view(catalog->identity);
  lua->Pop();
  return result;
}
unsigned attempts(ILuaBase* lua) {
  raw_get(lua, GarrysMod::Lua::SPECIAL_REG, kAttempts);
  const double value = lua->IsType(-1, Type::Number) ? lua->GetNumber(-1) : 0;
  lua->Pop();
  if (!(value >= 1)) return 0;
  return value >= nl::client::kMaxClientAttempts ? nl::client::kMaxClientAttempts : static_cast<unsigned>(value);
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
    LUA->PushNumber(++index); LUA->PushString(name.c_str()); LUA->RawSet(-3);
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
// Runs on the client realm, called protected there by Poll: an error raised in that state outside
// a protected call would end the process. No C++ object with a destructor lives in this frame.
LUA_FUNCTION_STATIC(InitializeClient) {
  if (!catalog || LUA != client) return 0;
  if (!raw_bool(LUA, "CLIENT_DLL") || raw_bool(LUA, "SERVER") || is_done(LUA)) return 0;
  raw_get(LUA, GarrysMod::Lua::SPECIAL_GLOB, "GAMEMODE");
  const bool ready = LUA->IsType(-1, Type::Table);
  LUA->Pop();
  if (!ready) return 0;
  // The initializer declines while the local player is not valid; a realm that never gets one is
  // given up instead of being compiled again on every poll.
  const unsigned attempt = attempts(LUA) + 1;
  if (!nl::client::attempt_allowed(attempt)) {
    status = "the client realm never became ready for the verified RTX payload";
    done(LUA);
    return 0;
  }
  LUA->PushNumber(attempt);
  raw_set(LUA, GarrysMod::Lua::SPECIAL_REG, kAttempts);
  LUA->CreateTable();
  LUA->PushString("read"); LUA->PushCFunction(Read); LUA->RawSet(-3);
  LUA->PushString("list"); LUA->PushCFunction(List); LUA->RawSet(-3);
  LUA->PushString("finish"); LUA->PushCFunction(Finish); LUA->RawSet(-3);
  LUA->PushString("identity"); LUA->PushString(catalog->identity.c_str()); LUA->RawSet(-3);
  raw_set(LUA, GarrysMod::Lua::SPECIAL_GLOB, kApi);
  const bool ok = client->RunStringEx("@nativeloader/verified-client-bootstrap", "", kClientBootstrap.data(), true, false, true, true);
  LUA->PushNil();
  raw_set(LUA, GarrysMod::Lua::SPECIAL_GLOB, kApi);
  if (!ok) { status = "verified client bootstrap failed"; done(LUA); }
  return 0;
}
LUA_FUNCTION_STATIC(Poll) {
  if (LUA != menu || !catalog || !shared || !gate.due(GetTickCount64())) return 0;
  client = shared->GetLuaInterface(GarrysMod::Lua::State::CLIENT);
  if (!client) return 0;
  const int top = client->Top();
  client->PushCFunction(InitializeClient);
  if (client->PCall(0, 0, 0) != 0) status = "verified client bootstrap step failed";
  client->Pop(client->Top() - top);
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
    // The owned environments keep api.read and the other callbacks reachable for the client
    // realm's lifetime, longer than the menu's require reference: never unload this code.
    HMODULE pinned = nullptr;
    if (!GetModuleHandleExW(GET_MODULE_HANDLE_EX_FLAG_FROM_ADDRESS | GET_MODULE_HANDLE_EX_FLAG_PIN,
                            reinterpret_cast<LPCWSTR>(&catalog), &pinned)) throw std::runtime_error("Cannot keep the RTX client bootstrap loaded");
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
