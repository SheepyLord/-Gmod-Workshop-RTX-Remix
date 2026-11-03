// Local, explicitly loaded QA module. Reads Source's DebugTextureInfo001 interface (R12-C).
#include <windows.h>
#include <bcrypt.h>
#include <GarrysMod/Lua/Interface.h>
#include <cstddef>
#include <cstdint>
#include <cstring>
#include <cstdio>
#include <array>
#include <string>
#include <unordered_set>

namespace {
using GarrysMod::Lua::ILuaBase;
using Factory = void* (*)(const char*, int*);

// Win64 Source KeyValues ABI, not an owning object. Never change or free engine memory.
struct Key {
  std::uint32_t symbol;
  const char* text;
  const wchar_t* wide;
  union { int integer; float real; void* pointer; } value;
  std::uint8_t type, escapes;
  std::uint16_t sensitive;
  Key* peer;
  Key* child;
  Key* chain;
};
static_assert(offsetof(Key, text) == 8 && offsetof(Key, type) == 32 && offsetof(Key, peer) == 40);

template<class Result, class... Args>
Result call(void* object, std::size_t index, Args... args) {
  return reinterpret_cast<Result (*)(void*, Args...)>((*static_cast<void***>(object))[index])(object, args...);
}
void* debug = nullptr;
void* symbols = nullptr;
bool collecting = false;
bool registryPinned = false;
std::uintptr_t shaderBase = 0;

bool knownShader() {
  wchar_t path[32768];
  if (!GetModuleFileNameW(reinterpret_cast<HMODULE>(shaderBase), path, 32768)) { return false; }
  HANDLE file = CreateFileW(path, GENERIC_READ, FILE_SHARE_READ | FILE_SHARE_WRITE | FILE_SHARE_DELETE,
    nullptr, OPEN_EXISTING, FILE_ATTRIBUTE_NORMAL, nullptr);
  if (file == INVALID_HANDLE_VALUE) { return false; }
  BCRYPT_ALG_HANDLE algorithm = nullptr;
  BCRYPT_HASH_HANDLE hash = nullptr;
  bool ok = BCryptOpenAlgorithmProvider(&algorithm, BCRYPT_SHA256_ALGORITHM, nullptr, 0) >= 0;
  if (ok) { ok = BCryptCreateHash(algorithm, &hash, nullptr, 0, nullptr, 0, 0) >= 0; }
  std::array<unsigned char, 16384> buffer{};
  DWORD bytes = 0;
  while (ok) {
    if (!ReadFile(file, buffer.data(), DWORD(buffer.size()), &bytes, nullptr)) { ok = false; break; }
    if (!bytes) { break; }
    ok = BCryptHashData(hash, buffer.data(), bytes, 0) >= 0;
  }
  std::array<unsigned char, 32> digest{};
  if (ok) { ok = BCryptFinishHash(hash, digest.data(), DWORD(digest.size()), 0) >= 0; }
  if (hash) { BCryptDestroyHash(hash); }
  if (algorithm) { BCryptCloseAlgorithmProvider(algorithm, 0); }
  CloseHandle(file);
  char hex[65];
  for (unsigned i = 0; i < digest.size(); ++i) { sprintf_s(hex + i * 2, 65 - i * 2, "%02x", unsigned(digest[i])); }
  return ok && std::strcmp(hex, "7534cd56738f3f729dab0b88fce7f5fa224898fc15c28021762f3352643f8ca9") == 0;
}

template<class T>
bool copyMemory(const void* source, T& target) {
  SIZE_T count = 0;
  return ReadProcessMemory(GetCurrentProcess(), source, &target, sizeof(target), &count) && count == sizeof(target);
}

template<class T>
T field(const std::array<unsigned char, 128>& bytes, unsigned offset) {
  T value;
  std::memcpy(&value, bytes.data() + offset, sizeof(value));
  return value;
}

void pushNumber(ILuaBase* lua, const char* key, double value) {
  lua->PushNumber(value); lua->SetField(-2, key);
}
void pushText(ILuaBase* lua, const char* key, const char* value) {
  lua->PushString(value ? value : ""); lua->SetField(-2, key);
}

// The public list is not built on the Remix render path on this stock GMod build. The exact
// shipped SHA and vtable RVAs gate this fallback; other engine builds never use private offsets.
int readRegistry(ILuaBase* lua) {
  lua->CreateTable();
  if (!registryPinned) { lua->PushBool(true); lua->PushBool(false); return 3; }
  const auto primary = reinterpret_cast<std::uintptr_t>(debug) - 0x380;
  std::uintptr_t head = 0;
  std::uint32_t frame = 0;
  bool complete = copyMemory(reinterpret_cast<void*>(primary + 0x30e0), head) &&
    copyMemory(reinterpret_cast<void*>(primary + 0x30b8), frame);
  const auto originalHead = head;
  const auto getName = reinterpret_cast<const char* (*)(const std::uint16_t*)>(shaderBase + 0x3d090);
  const auto getFormat = reinterpret_cast<const char* const* (*)(int)>(shaderBase + 0x35550);
  std::unordered_set<std::uintptr_t> visited;
  int index = 0;
  while (complete && head) {
    if (visited.size() >= 65536 || !visited.insert(head).second) { complete = false; break; }
    std::array<unsigned char, 128> record{};
    if (!copyMemory(reinterpret_cast<void*>(head), record)) { complete = false; break; }
    head = field<std::uintptr_t>(record, 0x78);
    if (!(record[0x52] & 1)) { continue; }
    const auto width = field<std::int16_t>(record, 0x4c);
    const auto height = field<std::int16_t>(record, 0x4e);
    const auto depth = field<std::int16_t>(record, 0x50);
    const auto format = field<std::int32_t>(record, 0x68);
    const auto size = field<std::int32_t>(record, 0x38);
    if (width < 1 || height < 1 || depth < 1 || format < -1 || format > 64 || size < 0) {
      complete = false; break;
    }
    const auto name = field<std::uint16_t>(record, 0x20);
    const auto group = field<std::uint16_t>(record, 0x22);
    lua->PushNumber(++index); lua->CreateTable();
    pushText(lua, "Name", getName(&name)); pushText(lua, "TexGroup", getName(&group));
    pushText(lua, "Format", *getFormat(format));
    pushNumber(lua, "Width", width); pushNumber(lua, "Height", height); pushNumber(lua, "Depth", depth);
    pushNumber(lua, "Size", size); pushNumber(lua, "Count", field<std::int16_t>(record, 0x6c));
    pushNumber(lua, "BindsMax", field<std::uint32_t>(record, 0x44));
    pushNumber(lua, "BindsFrame", field<std::uint32_t>(record, 0x48));
    pushNumber(lua, "LastBoundFrame", field<std::uint32_t>(record, 0x40));
    pushNumber(lua, "SnapshotFrame", frame);
    pushText(lua, "SnapshotMode", "pinned_shader_registry");
    lua->SetTable(-3);
  }
  std::uintptr_t afterHead = 0;
  std::uint32_t afterFrame = 0;
  complete = complete && copyMemory(reinterpret_cast<void*>(primary + 0x30e0), afterHead) &&
    copyMemory(reinterpret_cast<void*>(primary + 0x30b8), afterFrame) &&
    originalHead == afterHead && frame == afterFrame;
  lua->PushBool(!complete); lua->PushBool(false);
  return 3;
}

LUA_FUNCTION(begin) {
  if (!debug || !registryPinned) { LUA->PushBool(false); return 1; }
  // Transient debug collection only; both modes are disabled again by End/close.
  call<void>(debug, 0, true);
  call<void>(debug, 1, true);
  collecting = true;
  LUA->PushBool(true);
  return 1;
}

LUA_FUNCTION(read) {
  if (!debug || !symbols || !collecting) { LUA->PushNil(); return 1; }
  Key* root = call<Key*>(debug, 2);
  LUA->CreateTable();
  if (!root) { LUA->Pop(); return readRegistry(LUA); }
  int index = 0;
  bool truncated = false;
  const Key* row = root->child;
  // Caps also make an unsupported/cyclic ABI refuse to traverse indefinitely.
  for (; row && index < 65536; row = row->peer) {
    LUA->PushNumber(++index);
    LUA->CreateTable();
    unsigned count = 0;
    const Key* field = row->child;
    for (; field && count++ < 64; field = field->peer) {
      const char* name = call<const char*>(symbols, 4, int(field->symbol & 0xffffff));
      if (!name || std::strlen(name) > 128) { continue; }
      if (field->type == 1 && field->text) { LUA->PushString(field->text); }
      else if (field->type == 2) { LUA->PushNumber(field->value.integer); }
      else if (field->type == 3) { LUA->PushNumber(field->value.real); }
      else { continue; }
      LUA->SetField(-2, name);
    }
    truncated = truncated || field != nullptr;
    LUA->SetTable(-3);
  }
  LUA->PushBool(truncated || row != nullptr);
  LUA->PushBool(true);
  return 3;
}

LUA_FUNCTION(info) {
  LUA->CreateTable();
  if (!debug) { return 1; }
  const auto base = reinterpret_cast<std::uintptr_t>(GetModuleHandleW(L"shaderapidx9.dll"));
  const auto table = *static_cast<void***>(debug);
  for (unsigned i = 0; i < 6; ++i) {
    char name[32];
    sprintf_s(name, "method_%u_rva", i);
    LUA->PushNumber(double(reinterpret_cast<std::uintptr_t>(table[i]) - base));
    LUA->SetField(-2, name);
  }
  LUA->PushBool(registryPinned); LUA->SetField(-2, "registry_pinned");
  return 1;
}

LUA_FUNCTION(end) {
  if (debug && collecting) {
    call<void>(debug, 1, false);
    call<void>(debug, 0, false);
  }
  collecting = false;
  return 0;
}
}

GMOD_MODULE_OPEN() {
  const auto shader = GetModuleHandleW(L"shaderapidx9.dll");
  const auto create = shader ? reinterpret_cast<Factory>(GetProcAddress(shader, "CreateInterface")) : nullptr;
  debug = create ? create("DebugTextureInfo001", nullptr) : nullptr;
  const auto library = GetModuleHandleW(L"vstdlib.dll");
  const auto getSymbols = library ? reinterpret_cast<void* (*)()>(GetProcAddress(library, "KeyValuesSystem")) : nullptr;
  symbols = getSymbols ? getSymbols() : nullptr;
  shaderBase = reinterpret_cast<std::uintptr_t>(shader);
  registryPinned = debug && knownShader();
  if (registryPinned) {
    const auto table = *static_cast<void***>(debug);
    constexpr std::array<std::uintptr_t, 6> expected = {0x15490, 0x155f0, 0x17b30, 0x181f0, 0x18a70, 0x1dbc0};
    for (unsigned i = 0; i < expected.size(); ++i) {
      registryPinned = registryPinned && reinterpret_cast<std::uintptr_t>(table[i]) == shaderBase + expected[i];
    }
  }
  LUA->CreateTable();
  LUA->PushCFunction(begin); LUA->SetField(-2, "Begin");
  LUA->PushCFunction(read); LUA->SetField(-2, "Read");
  LUA->PushCFunction(info); LUA->SetField(-2, "Info");
  LUA->PushCFunction(end); LUA->SetField(-2, "End");
  LUA->PushBool(debug && symbols && registryPinned); LUA->SetField(-2, "available");
  LUA->SetField(GarrysMod::Lua::INDEX_GLOBAL, "NLVramProbe");
  return 0;
}

GMOD_MODULE_CLOSE() {
  if (debug && collecting) {
    call<void>(debug, 1, false);
    call<void>(debug, 0, false);
  }
  debug = symbols = nullptr;
  collecting = false;
  return 0;
}
