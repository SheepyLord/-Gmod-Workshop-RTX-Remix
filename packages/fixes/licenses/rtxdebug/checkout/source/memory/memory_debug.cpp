#ifdef _WIN64

#include "memory_debug.h"

#include "../lua_util.h"

#include <GarrysMod/Lua/Interface.h>
#include <Windows.h>
#include <TlHelp32.h>
#include <tier0/dbg.h>

#include <algorithm>
#include <array>
#include <cerrno>
#include <cctype>
#include <cmath>
#include <cstddef>
#include <cstdint>
#include <cstdio>
#include <cstdlib>
#include <cstring>
#include <iomanip>
#include <limits>
#include <sstream>
#include <string>
#include <utility>
#include <vector>

using GarrysMod::Lua::ILuaBase;
namespace Type = GarrysMod::Lua::Type;

namespace RTXDebug::Memory {
namespace {

constexpr size_t kMaxReadBytes = 4096;
constexpr size_t kMaxWriteBytes = 64;
constexpr size_t kMaxSignatureBytes = 512;
constexpr size_t kMaxScanMatches = 128;
constexpr size_t kScanChunkBytes = 1024 * 1024;
constexpr int kMaxPatchOffset = 4096;

struct Section {
    std::string name;
    uintptr_t begin = 0;
    size_t size = 0;
    DWORD characteristics = 0;
};

struct SignatureByte {
    uint8_t value = 0;
    bool wildcard = false;
};

struct OwnedWrite {
    uint64_t id = 0;
    uintptr_t address = 0;
    uintptr_t allocationBase = 0;
    HMODULE pinnedModule = nullptr;
    std::vector<uint8_t> original;
    std::vector<uint8_t> replacement;
    bool active = false;
};

struct OwnedPatch {
    std::string name;
    std::string module;
    uintptr_t moduleBase = 0;
    uintptr_t address = 0;
    HMODULE pinnedModule = nullptr;
    std::vector<uint8_t> expected;
    std::vector<uint8_t> replacement;
    bool active = false;
};

enum class MutationKind { Write, Patch };
struct Mutation {
    MutationKind kind;
    uint64_t writeId = 0;
    std::string patchName;
};

bool (*g_canMutate)() = nullptr;
DWORD g_mainThread = 0;
uint64_t g_nextWriteId = 1;
std::vector<OwnedWrite> g_writes;
std::vector<OwnedPatch> g_patches;
std::vector<Mutation> g_mutations;

bool Allowed() {
    if (GetCurrentThreadId() != g_mainThread) {
        Warning("[RTXDebug] Memory API called off the game thread\n");
        return false;
    }
    if (!g_canMutate || !g_canMutate()) {
        Warning("[RTXDebug] Memory access rejected by local debug gate\n");
        return false;
    }
    return true;
}

int AccessError(ILuaBase* lua) {
    if (GetCurrentThreadId() != g_mainThread) {
        // Calling into the Lua VM from this thread would make an existing
        // threading error worse. The caller receives no result.
        return 0;
    }
    return PushError(lua, "memory API requires local single player, sv_cheats 1 and -insecure");
}

// Restores only undo this module's own bytes, so they need the game thread
// but not the mutation gate: turning sv_cheats off must not strand a patch.
bool RestoreAllowed() {
    if (GetCurrentThreadId() == g_mainThread && g_mainThread != 0) return true;
    Warning("[RTXDebug] Memory API called off the game thread\n");
    return false;
}

std::string HexBytes(const uint8_t* bytes, size_t count) {
    static constexpr char digits[] = "0123456789ABCDEF";
    std::string result;
    result.reserve(count * 2);
    for (size_t i = 0; i < count; ++i) {
        result.push_back(digits[bytes[i] >> 4]);
        result.push_back(digits[bytes[i] & 15]);
    }
    return result;
}

bool ParseAddress(const char* input, uintptr_t& result, bool allowZero = false) {
    if (!input || !*input || input[0] == '-') return false;
    errno = 0;
    char* end = nullptr;
    const unsigned long long value = std::strtoull(input, &end, 0);
    if (errno == ERANGE || end == input || *end != '\0') return false;
    if (value > (std::numeric_limits<uintptr_t>::max)()) return false;
    result = static_cast<uintptr_t>(value);
    return allowZero || result != 0;
}

bool ParseHexBytes(const char* input, std::vector<uint8_t>& bytes, size_t maximum) {
    bytes.clear();
    if (!input) return false;
    std::string digits;
    for (const char* p = input; *p; ++p) {
        if (*p == ' ' || *p == '\t' || *p == ':' || *p == '-') continue;
        if (*p == '0' && (p[1] == 'x' || p[1] == 'X')) { ++p; continue; }
        if (!std::isxdigit(static_cast<unsigned char>(*p))) return false;
        digits.push_back(*p);
    }
    if (digits.empty() || digits.size() % 2 != 0 || digits.size() / 2 > maximum) return false;
    for (size_t i = 0; i < digits.size(); i += 2) {
        const auto nibble = [](char ch) -> uint8_t {
            return static_cast<uint8_t>(ch <= '9' ? ch - '0' : (ch & ~0x20) - 'A' + 10);
        };
        bytes.push_back(static_cast<uint8_t>((nibble(digits[i]) << 4) | nibble(digits[i + 1])));
    }
    return true;
}

bool ParseSignature(const char* input, std::vector<SignatureByte>& bytes) {
    bytes.clear();
    if (!input) return false;
    std::istringstream stream(input);
    std::string token;
    while (stream >> token) {
        if (token == "?" || token == "??") {
            bytes.push_back({0, true});
        } else {
            std::vector<uint8_t> parsed;
            if (token.size() != 2 || !ParseHexBytes(token.c_str(), parsed, 1)) return false;
            bytes.push_back({parsed[0], false});
        }
        if (bytes.size() > kMaxSignatureBytes) return false;
    }
    return !bytes.empty();
}

// Keep SEH in a function without C++ objects that need unwinding.
bool GuardedCopy(void* destination, const void* source, size_t size) {
    __try {
        std::memcpy(destination, source, size);
        return true;
    } __except (EXCEPTION_EXECUTE_HANDLER) {
        return false;
    }
}

bool Region(uintptr_t address, size_t size, MEMORY_BASIC_INFORMATION& info, bool write) {
    if (address == 0 || size == 0 || address > UINTPTR_MAX - size) return false;
    if (!VirtualQuery(reinterpret_cast<void*>(address), &info, sizeof(info))) return false;
    const uintptr_t begin = reinterpret_cast<uintptr_t>(info.BaseAddress);
    if (begin > UINTPTR_MAX - info.RegionSize || address < begin || size > begin + info.RegionSize - address)
        return false;
    if (info.State != MEM_COMMIT || (info.Protect & (PAGE_GUARD | PAGE_NOACCESS))) return false;
    const DWORD protect = info.Protect & 0xFF;
    if (write) return protect != PAGE_NOACCESS;
    return protect == PAGE_READONLY || protect == PAGE_READWRITE || protect == PAGE_WRITECOPY
        || protect == PAGE_EXECUTE || protect == PAGE_EXECUTE_READ || protect == PAGE_EXECUTE_READWRITE
        || protect == PAGE_EXECUTE_WRITECOPY;
}

bool ReadBytes(uintptr_t address, size_t size, std::vector<uint8_t>& output) {
    MEMORY_BASIC_INFORMATION info{};
    if (size > kMaxReadBytes || !Region(address, size, info, false)) return false;
    output.resize(size);
    return GuardedCopy(output.data(), reinterpret_cast<void*>(address), size);
}

bool WriteBytes(uintptr_t address, const std::vector<uint8_t>& bytes, uintptr_t expectedAllocation) {
    MEMORY_BASIC_INFORMATION info{};
    if (bytes.empty() || bytes.size() > kMaxWriteBytes
        || !Region(address, bytes.size(), info, true)
        || (expectedAllocation && reinterpret_cast<uintptr_t>(info.AllocationBase) != expectedAllocation))
        return false;
    std::vector<uint8_t> original;
    if (!ReadBytes(address, bytes.size(), original)) return false;
    std::vector<uint8_t> check(bytes.size());
    DWORD oldProtection = 0;
    if (!VirtualProtect(reinterpret_cast<void*>(address), bytes.size(), PAGE_EXECUTE_READWRITE, &oldProtection))
        return false;
    const bool copied = GuardedCopy(reinterpret_cast<void*>(address), bytes.data(), bytes.size());
    const bool verified = copied
        && GuardedCopy(check.data(), reinterpret_cast<void*>(address), bytes.size())
        && check == bytes;
    if (!verified) GuardedCopy(reinterpret_cast<void*>(address), original.data(), original.size());
    FlushInstructionCache(GetCurrentProcess(), reinterpret_cast<void*>(address), bytes.size());
    DWORD ignored = 0;
    if (!VirtualProtect(reinterpret_cast<void*>(address), bytes.size(), oldProtection, &ignored)) {
        Warning("[RTXDebug] Failed to restore page protection at %s (error %lu)\n",
            HexAddress(address).c_str(), GetLastError());
        // The page is still writable if the first protection change succeeded.
        // Put its original data back before reporting an untracked failure.
        if (!GuardedCopy(reinterpret_cast<void*>(address), original.data(), original.size()))
            Warning("[RTXDebug] Failed to roll back bytes at %s\n", HexAddress(address).c_str());
        FlushInstructionCache(GetCurrentProcess(), reinterpret_cast<void*>(address), bytes.size());
        if (!VirtualProtect(reinterpret_cast<void*>(address), bytes.size(), oldProtection, &ignored))
            Warning("[RTXDebug] Page protection still differs at %s\n", HexAddress(address).c_str());
        return false;
    }
    return verified;
}

bool RangesOverlap(uintptr_t a, size_t aSize, uintptr_t b, size_t bSize) {
    if (a > UINTPTR_MAX - aSize || b > UINTPTR_MAX - bSize) return true;
    return a < b + bSize && b < a + aSize;
}

bool OverlapsOwned(uintptr_t address, size_t size) {
    for (const OwnedWrite& write : g_writes)
        if (write.active && RangesOverlap(address, size, write.address, write.replacement.size())) return true;
    for (const OwnedPatch& patch : g_patches)
        if (patch.active && RangesOverlap(address, size, patch.address, patch.replacement.size())) return true;
    return false;
}

bool ModuleSections(HMODULE module, std::vector<Section>& result, size_t& imageSize) {
    result.clear();
    imageSize = 0;
    if (!module) return false;
    auto* base = reinterpret_cast<uint8_t*>(module);
    IMAGE_DOS_HEADER dos{};
    if (!GuardedCopy(&dos, base, sizeof(dos)) || dos.e_magic != IMAGE_DOS_SIGNATURE
        || dos.e_lfanew <= 0 || dos.e_lfanew > 1 << 20) return false;
    IMAGE_NT_HEADERS64 nt{};
    if (!GuardedCopy(&nt, base + dos.e_lfanew, sizeof(nt)) || nt.Signature != IMAGE_NT_SIGNATURE
        || nt.OptionalHeader.Magic != IMAGE_NT_OPTIONAL_HDR64_MAGIC
        || nt.FileHeader.NumberOfSections == 0 || nt.FileHeader.NumberOfSections > 96) return false;
    imageSize = nt.OptionalHeader.SizeOfImage;
    if (imageSize < sizeof(dos) || imageSize > 1ULL << 32) return false;
    const uintptr_t first = reinterpret_cast<uintptr_t>(base) + dos.e_lfanew
        + offsetof(IMAGE_NT_HEADERS64, OptionalHeader) + nt.FileHeader.SizeOfOptionalHeader;
    const uintptr_t moduleEnd = reinterpret_cast<uintptr_t>(base) + imageSize;
    const size_t sectionBytes = static_cast<size_t>(nt.FileHeader.NumberOfSections) * sizeof(IMAGE_SECTION_HEADER);
    if (moduleEnd < reinterpret_cast<uintptr_t>(base) || first > moduleEnd
        || sectionBytes > moduleEnd - first) return false;
    for (WORD i = 0; i < nt.FileHeader.NumberOfSections; ++i) {
        IMAGE_SECTION_HEADER raw{};
        if (!GuardedCopy(&raw, reinterpret_cast<void*>(first + i * sizeof(raw)), sizeof(raw))) return false;
        if (raw.VirtualAddress >= imageSize) continue;
        const size_t requested = (std::max)(static_cast<size_t>(raw.Misc.VirtualSize),
            static_cast<size_t>(raw.SizeOfRawData));
        const size_t length = (std::min)(requested, imageSize - static_cast<size_t>(raw.VirtualAddress));
        if (!length) continue;
        char name[9]{};
        std::memcpy(name, raw.Name, 8);
        result.push_back({name, reinterpret_cast<uintptr_t>(base) + raw.VirtualAddress,
            length, raw.Characteristics});
    }
    return true;
}

HMODULE RetainModule(const char* name) {
    HMODULE module = nullptr;
    if (!name || !*name || !GetModuleHandleExA(0, name, &module)) return nullptr;
    return module;
}

std::vector<uintptr_t> ScanSections(const std::vector<Section>& sections,
    const std::string& selected, const std::vector<SignatureByte>& signature, size_t maximum) {
    std::vector<uintptr_t> matches;
    for (const Section& section : sections) {
        if (selected == ".text" && (section.characteristics & IMAGE_SCN_MEM_EXECUTE) == 0) continue;
        if (selected != "*" && selected != ".text" && selected != section.name) continue;
        uintptr_t cursor = section.begin;
        const uintptr_t sectionEnd = section.begin + section.size;
        while (cursor < sectionEnd && matches.size() < maximum) {
            MEMORY_BASIC_INFORMATION info{};
            if (!VirtualQuery(reinterpret_cast<void*>(cursor), &info, sizeof(info))) break;
            const uintptr_t regionEnd = reinterpret_cast<uintptr_t>(info.BaseAddress) + info.RegionSize;
            const uintptr_t end = (std::min)(sectionEnd, regionEnd);
            if (end <= cursor) break;
            for (uintptr_t chunk = cursor; chunk < end && matches.size() < maximum;) {
                const size_t remaining = end - chunk;
                const size_t step = (std::min)(remaining, kScanChunkBytes);
                const size_t overlap = (std::min)(remaining - step, signature.size() - 1);
                const size_t size = step + overlap;
                MEMORY_BASIC_INFORMATION checked{};
                if (size >= signature.size() && Region(chunk, size, checked, false)) {
                    std::vector<uint8_t> copy(size);
                    if (GuardedCopy(copy.data(), reinterpret_cast<void*>(chunk), size)) {
                        const size_t lastOffset = (std::min)(step - 1, size - signature.size());
                        for (size_t offset = 0; offset <= lastOffset; ++offset) {
                            bool match = true;
                            for (size_t i = 0; i < signature.size(); ++i) {
                                if (!signature[i].wildcard && copy[offset + i] != signature[i].value) {
                                    match = false;
                                    break;
                                }
                            }
                            if (match) {
                                matches.push_back(chunk + offset);
                                if (matches.size() == maximum) break;
                            }
                        }
                    }
                }
                chunk += step;
            }
            cursor = end;
        }
        if (matches.size() == maximum) break;
    }
    return matches;
}

OwnedWrite* FindWrite(uint64_t id) {
    for (OwnedWrite& write : g_writes) if (write.id == id) return &write;
    return nullptr;
}

OwnedPatch* FindPatch(const std::string& name) {
    for (OwnedPatch& patch : g_patches) if (patch.name == name) return &patch;
    return nullptr;
}

bool RestoreWrite(OwnedWrite& write) {
    if (!write.active) return true;
    std::vector<uint8_t> current;
    if (!ReadBytes(write.address, write.replacement.size(), current)
        || current != write.replacement) {
        Warning("[RTXDebug] Write #%llu changed externally; refusing to restore stale bytes\n",
            static_cast<unsigned long long>(write.id));
        return false;
    }
    if (!WriteBytes(write.address, write.original, write.allocationBase)) return false;
    write.active = false;
    if (write.pinnedModule) {
        FreeLibrary(write.pinnedModule);
        write.pinnedModule = nullptr;
    }
    Msg("[RTXDebug] Restored memory write #%llu at %s\n",
        static_cast<unsigned long long>(write.id), HexAddress(write.address).c_str());
    return true;
}

bool RestorePatch(OwnedPatch& patch) {
    if (!patch.active) return true;
    if (!patch.pinnedModule || reinterpret_cast<uintptr_t>(patch.pinnedModule) != patch.moduleBase)
        return false;
    std::vector<uint8_t> current;
    if (!ReadBytes(patch.address, patch.replacement.size(), current)
        || current != patch.replacement) {
        Warning("[RTXDebug] Patch '%s' changed externally; refusing to restore stale bytes\n",
            patch.name.c_str());
        return false;
    }
    const bool restored = WriteBytes(patch.address, patch.expected, patch.moduleBase);
    if (restored) {
        patch.active = false;
        FreeLibrary(patch.pinnedModule);
        patch.pinnedModule = nullptr;
        Msg("[RTXDebug] Restored patch '%s'\n", patch.name.c_str());
    }
    return restored;
}

enum class ValueType { U8, I8, U16, I16, U32, I32, U64, I64, F32, F64, Bytes, Invalid };

ValueType ParseType(const char* name) {
    if (!name) return ValueType::Invalid;
    static constexpr std::pair<const char*, ValueType> types[] = {
        {"u8", ValueType::U8}, {"i8", ValueType::I8}, {"u16", ValueType::U16},
        {"i16", ValueType::I16}, {"u32", ValueType::U32}, {"i32", ValueType::I32},
        {"u64", ValueType::U64}, {"i64", ValueType::I64}, {"f32", ValueType::F32},
        {"f64", ValueType::F64}, {"bytes", ValueType::Bytes}
    };
    for (const auto& entry : types) if (std::strcmp(name, entry.first) == 0) return entry.second;
    return ValueType::Invalid;
}

size_t TypeSize(ValueType type) {
    switch (type) {
    case ValueType::U8: case ValueType::I8: return 1;
    case ValueType::U16: case ValueType::I16: return 2;
    case ValueType::U32: case ValueType::I32: case ValueType::F32: return 4;
    case ValueType::U64: case ValueType::I64: case ValueType::F64: return 8;
    default: return 0;
    }
}

template <typename T> T FromBytes(const uint8_t* bytes) {
    T value{};
    std::memcpy(&value, bytes, sizeof(value));
    return value;
}

void PushValue(ILuaBase* lua, ValueType type, const uint8_t* bytes, size_t size) {
    switch (type) {
    case ValueType::U8: lua->PushNumber(*bytes); break;
    case ValueType::I8: lua->PushNumber(FromBytes<int8_t>(bytes)); break;
    case ValueType::U16: lua->PushNumber(FromBytes<uint16_t>(bytes)); break;
    case ValueType::I16: lua->PushNumber(FromBytes<int16_t>(bytes)); break;
    case ValueType::U32: lua->PushNumber(FromBytes<uint32_t>(bytes)); break;
    case ValueType::I32: lua->PushNumber(FromBytes<int32_t>(bytes)); break;
    case ValueType::U64: case ValueType::I64:
        lua->PushString(HexAddress(FromBytes<uint64_t>(bytes)).c_str()); break;
    case ValueType::F32: {
        const float value = FromBytes<float>(bytes);
        if (std::isfinite(value)) lua->PushNumber(value);
        else lua->PushString(std::isnan(value) ? "nan" : (value < 0 ? "-inf" : "inf"));
        break;
    }
    case ValueType::F64: {
        const double value = FromBytes<double>(bytes);
        if (std::isfinite(value)) lua->PushNumber(value);
        else lua->PushString(std::isnan(value) ? "nan" : (value < 0 ? "-inf" : "inf"));
        break;
    }
    case ValueType::Bytes: lua->PushString(HexBytes(bytes, size).c_str()); break;
    default: lua->PushNil(); break;
    }
}

bool EncodeNumber(ILuaBase* lua, int index, ValueType type, std::vector<uint8_t>& bytes) {
    bytes.clear();
    if (type == ValueType::Bytes || type == ValueType::U64 || type == ValueType::I64) {
        if (!lua->IsType(index, Type::String)) return false;
        if (type == ValueType::Bytes) return ParseHexBytes(lua->GetString(index), bytes, kMaxWriteBytes);
        uintptr_t value = 0;
        if (!ParseAddress(lua->GetString(index), value, true)) return false;
        bytes.resize(sizeof(uint64_t));
        const uint64_t wide = static_cast<uint64_t>(value);
        std::memcpy(bytes.data(), &wide, sizeof(wide));
        return true;
    }
    if (!lua->IsType(index, Type::Number)) return false;
    const double value = lua->GetNumber(index);
    if (!std::isfinite(value)) return false;
    const size_t width = TypeSize(type);
    if (!width) return false;
    bytes.resize(width);
    if (type == ValueType::F32) {
        const float v = static_cast<float>(value);
        if (!std::isfinite(v)) return false;
        std::memcpy(bytes.data(), &v, width);
        return true;
    }
    if (type == ValueType::F64) {
        std::memcpy(bytes.data(), &value, width);
        return true;
    }
    if (std::trunc(value) != value) return false;
    double minValue = 0;
    double maxValue = 0;
    switch (type) {
    case ValueType::U8: maxValue = UINT8_MAX; break;
    case ValueType::I8: minValue = INT8_MIN; maxValue = INT8_MAX; break;
    case ValueType::U16: maxValue = UINT16_MAX; break;
    case ValueType::I16: minValue = INT16_MIN; maxValue = INT16_MAX; break;
    case ValueType::U32: maxValue = UINT32_MAX; break;
    case ValueType::I32: minValue = INT32_MIN; maxValue = INT32_MAX; break;
    default: return false;
    }
    if (value < minValue || value > maxValue) return false;
    const int64_t signedValue = static_cast<int64_t>(value);
    std::memcpy(bytes.data(), &signedValue, width);
    return true;
}

LUA_FUNCTION(MemoryModules) {
    if (!Allowed()) return AccessError(LUA);
    HANDLE snapshot = CreateToolhelp32Snapshot(TH32CS_SNAPMODULE | TH32CS_SNAPMODULE32, GetCurrentProcessId());
    if (snapshot == INVALID_HANDLE_VALUE) return PushError(LUA, "cannot enumerate process modules");
    LUA->CreateTable();
    MODULEENTRY32W entry{};
    entry.dwSize = sizeof(entry);
    int index = 1;
    if (Module32FirstW(snapshot, &entry)) do {
        LUA->CreateTable();
        char name[MAX_PATH * 3]{};
        char path[MAX_PATH * 3]{};
        WideCharToMultiByte(CP_UTF8, 0, entry.szModule, -1, name, sizeof(name), nullptr, nullptr);
        WideCharToMultiByte(CP_UTF8, 0, entry.szExePath, -1, path, sizeof(path), nullptr, nullptr);
        SetString(LUA, "name", name);
        SetString(LUA, "path", path);
        SetString(LUA, "base", HexAddress(reinterpret_cast<uintptr_t>(entry.modBaseAddr)));
        SetNumber(LUA, "size", entry.modBaseSize);
        LUA->CreateTable();
        std::vector<Section> sections;
        size_t imageSize = 0;
        if (ModuleSections(entry.hModule, sections, imageSize)) {
            int sectionIndex = 1;
            for (const Section& section : sections) {
                LUA->CreateTable();
                SetString(LUA, "name", section.name);
                SetString(LUA, "base", HexAddress(section.begin));
                SetNumber(LUA, "size", static_cast<double>(section.size));
                SetBool(LUA, "executable", (section.characteristics & IMAGE_SCN_MEM_EXECUTE) != 0);
                SetArrayValue(LUA, sectionIndex++);
            }
        }
        LUA->SetField(-2, "sections");
        SetArrayValue(LUA, index++);
        entry.dwSize = sizeof(entry);
    } while (Module32NextW(snapshot, &entry));
    CloseHandle(snapshot);
    Msg("[RTXDebug] Enumerated %d process modules\n", index - 1);
    return 1;
}

LUA_FUNCTION(MemoryScan) {
    if (!Allowed()) return AccessError(LUA);
    if (!LUA->IsType(1, Type::String) || !LUA->IsType(2, Type::String))
        return PushError(LUA, "Scan(module, signature, section?) requires strings");
    const std::string moduleName = LUA->GetString(1);
    const std::string pattern = LUA->GetString(2);
    const std::string section = LUA->IsType(3, Type::String) ? LUA->GetString(3) : ".text";
    std::vector<SignatureByte> parsed;
    if (!ParseSignature(pattern.c_str(), parsed)) return PushError(LUA, "invalid signature");
    HMODULE module = RetainModule(moduleName.c_str());
    if (!module) return PushError(LUA, "module is not loaded");
    std::vector<Section> sections;
    size_t imageSize = 0;
    const bool valid = ModuleSections(module, sections, imageSize);
    const auto matches = valid ? ScanSections(sections, section, parsed, kMaxScanMatches) : std::vector<uintptr_t>{};
    FreeLibrary(module);
    if (!valid) return PushError(LUA, "invalid module image");
    LUA->CreateTable();
    int index = 1;
    for (uintptr_t address : matches) {
        LUA->PushString(HexAddress(address).c_str());
        SetArrayValue(LUA, index++);
    }
    Msg("[RTXDebug] Scanned %s (%s): %zu matches\n", moduleName.c_str(), section.c_str(), matches.size());
    return 1;
}

LUA_FUNCTION(MemoryRead) {
    if (!Allowed()) return AccessError(LUA);
    if (!LUA->IsType(1, Type::String) || !LUA->IsType(2, Type::String))
        return PushError(LUA, "Read(address, type, count?) requires strings");
    uintptr_t address = 0;
    if (!ParseAddress(LUA->GetString(1), address)) return PushError(LUA, "invalid address");
    const ValueType type = ParseType(LUA->GetString(2));
    if (type == ValueType::Invalid) return PushError(LUA, "invalid value type");
    size_t count = 1;
    if (LUA->IsType(3, Type::Number)) {
        const double requested = LUA->GetNumber(3);
        if (!std::isfinite(requested) || requested < 1 || requested > kMaxReadBytes
            || std::trunc(requested) != requested) return PushError(LUA, "invalid count");
        count = static_cast<size_t>(requested);
    }
    const size_t width = type == ValueType::Bytes ? 1 : TypeSize(type);
    if (!width || count > kMaxReadBytes / width) return PushError(LUA, "read exceeds 4096 bytes");
    std::vector<uint8_t> bytes;
    if (!ReadBytes(address, count * width, bytes)) return PushError(LUA, "memory range is unreadable");
    if (count == 1 || type == ValueType::Bytes) {
        PushValue(LUA, type, bytes.data(), bytes.size());
    } else {
        LUA->CreateTable();
        for (size_t i = 0; i < count; ++i) {
            PushValue(LUA, type, bytes.data() + i * width, width);
            SetArrayValue(LUA, static_cast<int>(i + 1));
        }
    }
    Msg("[RTXDebug] Read %zu bytes at %s\n", bytes.size(), HexAddress(address).c_str());
    return 1;
}

LUA_FUNCTION(MemoryWrite) {
    if (!Allowed()) return AccessError(LUA);
    if (!LUA->IsType(1, Type::String) || !LUA->IsType(2, Type::String)
        || !LUA->IsType(4, Type::String))
        return PushError(LUA, "Write(address, type, value, expectedHex) requires address, type and expected bytes");
    uintptr_t address = 0;
    if (!ParseAddress(LUA->GetString(1), address)) return PushError(LUA, "invalid address");
    const ValueType type = ParseType(LUA->GetString(2));
    std::vector<uint8_t> replacement;
    if (!EncodeNumber(LUA, 3, type, replacement)) return PushError(LUA, "invalid value for type");
    std::vector<uint8_t> expected;
    if (!ParseHexBytes(LUA->GetString(4), expected, kMaxWriteBytes)
        || expected.size() != replacement.size()) return PushError(LUA, "expected bytes must match value size");
    if (OverlapsOwned(address, replacement.size())) return PushError(LUA, "target overlaps an active debug write or patch");
    std::vector<uint8_t> current;
    if (!ReadBytes(address, replacement.size(), current) || current != expected)
        return PushError(LUA, "target bytes differ from expected bytes");
    MEMORY_BASIC_INFORMATION info{};
    if (!Region(address, replacement.size(), info, true)) return PushError(LUA, "memory range is not writable");
    HMODULE pinnedModule = nullptr;
    if (info.Type == MEM_IMAGE
        && !GetModuleHandleExA(GET_MODULE_HANDLE_EX_FLAG_FROM_ADDRESS,
            reinterpret_cast<const char*>(address), &pinnedModule))
        return PushError(LUA, "cannot retain target image for reversible write");
    OwnedWrite owned;
    owned.id = g_nextWriteId++;
    owned.address = address;
    owned.allocationBase = reinterpret_cast<uintptr_t>(info.AllocationBase);
    owned.pinnedModule = pinnedModule;
    owned.original = std::move(current);
    owned.replacement = std::move(replacement);
    try {
        g_writes.push_back(std::move(owned));
        g_mutations.push_back({MutationKind::Write, g_writes.back().id, {}});
    } catch (...) {
        if (!g_writes.empty() && g_writes.back().id == owned.id) g_writes.pop_back();
        if (pinnedModule) FreeLibrary(pinnedModule);
        return PushError(LUA, "cannot reserve memory write ledger");
    }
    if (!WriteBytes(address, g_writes.back().replacement, g_writes.back().allocationBase)) {
        g_mutations.pop_back();
        g_writes.pop_back();
        if (pinnedModule) FreeLibrary(pinnedModule);
        return PushError(LUA, "memory write failed");
    }
    g_writes.back().active = true;
    LUA->PushNumber(static_cast<double>(g_writes.back().id));
    Msg("[RTXDebug] Wrote %zu bytes at %s (write #%llu)\n", g_writes.back().replacement.size(),
        HexAddress(address).c_str(), static_cast<unsigned long long>(g_writes.back().id));
    return 1;
}

LUA_FUNCTION(MemoryRestoreWrite) {
    if (!RestoreAllowed()) return 0;
    if (!LUA->IsType(1, Type::Number)) return PushError(LUA, "RestoreWrite(id) requires a numeric id");
    const double raw = LUA->GetNumber(1);
    if (!std::isfinite(raw) || raw < 1 || raw > static_cast<double>((std::numeric_limits<uint64_t>::max)())
        || std::trunc(raw) != raw) return PushError(LUA, "invalid write id");
    OwnedWrite* write = FindWrite(static_cast<uint64_t>(raw));
    if (!write) return PushError(LUA, "write id not found");
    if (!RestoreWrite(*write))
        return PushError(LUA, "write was not restored: its bytes changed externally or the page could not be written");
    LUA->PushBool(true);
    return 1;
}

LUA_FUNCTION(MemoryPatchDefine) {
    if (!Allowed()) return AccessError(LUA);
    for (int i = 1; i <= 3; ++i) if (!LUA->IsType(i, Type::String))
        return PushError(LUA, "PatchDefine(name, module, signature, offset, expectedHex, replacementHex) requires strings");
    if (!LUA->IsType(4, Type::Number) || !LUA->IsType(5, Type::String)
        || !LUA->IsType(6, Type::String)) return PushError(LUA, "invalid patch arguments");
    const std::string name = LUA->GetString(1);
    const std::string moduleName = LUA->GetString(2);
    const std::string pattern = LUA->GetString(3);
    const double offsetNumber = LUA->GetNumber(4);
    if (name.empty() || name.size() > 100 || moduleName.empty() || FindPatch(name)
        || !std::isfinite(offsetNumber) || offsetNumber < -kMaxPatchOffset
        || offsetNumber > kMaxPatchOffset || std::trunc(offsetNumber) != offsetNumber)
        return PushError(LUA, "invalid or duplicate patch name/module/offset");
    const int offset = static_cast<int>(offsetNumber);
    std::vector<SignatureByte> signature;
    std::vector<uint8_t> expected, replacement;
    if (!ParseSignature(pattern.c_str(), signature)
        || !ParseHexBytes(LUA->GetString(5), expected, kMaxWriteBytes)
        || !ParseHexBytes(LUA->GetString(6), replacement, kMaxWriteBytes)
        || expected.size() != replacement.size() || expected == replacement)
        return PushError(LUA, "invalid signature or patch bytes");
    HMODULE module = RetainModule(moduleName.c_str());
    if (!module) return PushError(LUA, "module is not loaded");
    std::vector<Section> sections;
    size_t imageSize = 0;
    const bool valid = ModuleSections(module, sections, imageSize);
    const auto matches = valid ? ScanSections(sections, ".text", signature, 2) : std::vector<uintptr_t>{};
    if (matches.size() != 1) {
        FreeLibrary(module);
        return PushError(LUA, "patch signature must have exactly one executable match");
    }
    const uintptr_t match = matches.front();
    if ((offset < 0 && match < static_cast<uintptr_t>(-offset))
        || (offset > 0 && match > UINTPTR_MAX - static_cast<uintptr_t>(offset))) {
        FreeLibrary(module);
        return PushError(LUA, "patch offset is out of range");
    }
    const uintptr_t address = offset < 0 ? match - static_cast<uintptr_t>(-offset)
        : match + static_cast<uintptr_t>(offset);
    bool executable = false;
    for (const Section& section : sections) {
        if ((section.characteristics & IMAGE_SCN_MEM_EXECUTE)
            && address >= section.begin && address < section.begin + section.size
            && expected.size() <= section.begin + section.size - address) {
            executable = true;
            break;
        }
    }
    std::vector<uint8_t> current;
    const bool matchesExpected = executable && ReadBytes(address, expected.size(), current) && current == expected;
    FreeLibrary(module);
    if (!matchesExpected || OverlapsOwned(address, expected.size()))
        return PushError(LUA, "patch target is not executable, differs from expected bytes or overlaps a debug mutation");
    g_patches.push_back({name, moduleName, reinterpret_cast<uintptr_t>(module), address,
        nullptr, std::move(expected), std::move(replacement), false});
    LUA->PushString(HexAddress(address).c_str());
    Msg("[RTXDebug] Defined patch '%s' in %s at %s\n", name.c_str(), moduleName.c_str(),
        HexAddress(address).c_str());
    return 1;
}

LUA_FUNCTION(MemoryPatchApply) {
    if (!Allowed()) return AccessError(LUA);
    if (!LUA->IsType(1, Type::String)) return PushError(LUA, "PatchApply(name) requires a name");
    OwnedPatch* patch = FindPatch(LUA->GetString(1));
    if (!patch || patch->active) return PushError(LUA, "patch not found or already applied");
    if (OverlapsOwned(patch->address, patch->replacement.size()))
        return PushError(LUA, "patch overlaps an active debug mutation");
    HMODULE module = RetainModule(patch->module.c_str());
    if (!module || reinterpret_cast<uintptr_t>(module) != patch->moduleBase) {
        if (module) FreeLibrary(module);
        return PushError(LUA, "target module changed");
    }
    std::vector<uint8_t> current;
    const bool ready = ReadBytes(patch->address, patch->expected.size(), current)
        && current == patch->expected;
    if (!ready) {
        FreeLibrary(module);
        return PushError(LUA, "target bytes changed before patch application");
    }
    try {
        g_mutations.push_back({MutationKind::Patch, 0, patch->name});
    } catch (...) {
        FreeLibrary(module);
        return PushError(LUA, "cannot reserve patch ledger");
    }
    if (!WriteBytes(patch->address, patch->replacement, patch->moduleBase)) {
        g_mutations.pop_back();
        FreeLibrary(module);
        return PushError(LUA, "patch write failed");
    }
    patch->active = true;
    patch->pinnedModule = module;
    LUA->PushBool(true);
    Msg("[RTXDebug] Applied patch '%s'\n", patch->name.c_str());
    return 1;
}

LUA_FUNCTION(MemoryPatchRestore) {
    if (!RestoreAllowed()) return 0;
    if (!LUA->IsType(1, Type::String)) return PushError(LUA, "PatchRestore(name) requires a name");
    OwnedPatch* patch = FindPatch(LUA->GetString(1));
    if (!patch) return PushError(LUA, "patch not found");
    if (!RestorePatch(*patch))
        return PushError(LUA, "patch was not restored: its bytes changed externally or its module changed");
    LUA->PushBool(true);
    return 1;
}

// The ledgers are listed without the mutation gate so that changes stay
// visible, and restorable, after sv_cheats is turned off.
LUA_FUNCTION(MemoryPatchList) {
    if (!RestoreAllowed()) return 0;
    LUA->CreateTable();
    int index = 1;
    for (const OwnedPatch& patch : g_patches) {
        LUA->CreateTable();
        SetString(LUA, "name", patch.name);
        SetString(LUA, "module", patch.module);
        SetString(LUA, "address", HexAddress(patch.address));
        SetString(LUA, "expected", HexBytes(patch.expected.data(), patch.expected.size()));
        SetString(LUA, "replacement", HexBytes(patch.replacement.data(), patch.replacement.size()));
        SetBool(LUA, "applied", patch.active);
        SetArrayValue(LUA, index++);
    }
    return 1;
}

LUA_FUNCTION(MemoryWriteList) {
    if (!RestoreAllowed()) return 0;
    LUA->CreateTable();
    int index = 1;
    for (const OwnedWrite& write : g_writes) {
        LUA->CreateTable();
        SetNumber(LUA, "id", static_cast<double>(write.id));
        SetString(LUA, "address", HexAddress(write.address));
        SetString(LUA, "original", HexBytes(write.original.data(), write.original.size()));
        SetString(LUA, "replacement", HexBytes(write.replacement.data(), write.replacement.size()));
        SetBool(LUA, "active", write.active);
        SetArrayValue(LUA, index++);
    }
    return 1;
}

bool MutationActive(const Mutation& mutation) {
    if (mutation.kind == MutationKind::Write) {
        const OwnedWrite* write = FindWrite(mutation.writeId);
        return write && write->active;
    }
    const OwnedPatch* patch = FindPatch(mutation.patchName);
    return patch && patch->active;
}

} // namespace

void RegisterLua(ILuaBase* lua, bool (*canMutate)()) {
    g_canMutate = canMutate;
    g_mainThread = GetCurrentThreadId();
    lua->CreateTable();
    AddFunction(lua, "Modules", MemoryModules);
    AddFunction(lua, "Scan", MemoryScan);
    AddFunction(lua, "Read", MemoryRead);
    AddFunction(lua, "Write", MemoryWrite);
    AddFunction(lua, "RestoreWrite", MemoryRestoreWrite);
    AddFunction(lua, "PatchDefine", MemoryPatchDefine);
    AddFunction(lua, "PatchApply", MemoryPatchApply);
    AddFunction(lua, "PatchRestore", MemoryPatchRestore);
    AddFunction(lua, "PatchList", MemoryPatchList);
    AddFunction(lua, "Writes", MemoryWriteList);
    lua->SetField(-2, "Memory");
}

bool ReadPointer(uintptr_t address, uintptr_t& value) {
    std::vector<uint8_t> bytes;
    if (!ReadBytes(address, sizeof(value), bytes)) return false;
    std::memcpy(&value, bytes.data(), sizeof(value));
    return true;
}

uintptr_t AllocationBase(uintptr_t address) {
    MEMORY_BASIC_INFORMATION info{};
    if (!address || !VirtualQuery(reinterpret_cast<void*>(address), &info, sizeof(info))
        || info.State != MEM_COMMIT) return 0;
    return reinterpret_cast<uintptr_t>(info.AllocationBase);
}

size_t ActiveMutations() {
    size_t active = 0;
    for (const OwnedWrite& write : g_writes) if (write.active) ++active;
    for (const OwnedPatch& patch : g_patches) if (patch.active) ++active;
    return active;
}

int RestoreAll(std::vector<std::string>& failures) {
    int restored = 0;
    for (auto iterator = g_mutations.rbegin(); iterator != g_mutations.rend(); ++iterator) {
        if (!MutationActive(*iterator)) continue;
        if (iterator->kind == MutationKind::Write) {
            OwnedWrite* write = FindWrite(iterator->writeId);
            if (RestoreWrite(*write)) ++restored;
            else failures.push_back("memory write #" + std::to_string(write->id) + " at " + HexAddress(write->address));
        } else {
            OwnedPatch* patch = FindPatch(iterator->patchName);
            if (RestorePatch(*patch)) ++restored;
            else failures.push_back("patch '" + patch->name + "'");
        }
    }
    // Keep only what is still in place, so a later RestoreAll retries it.
    g_mutations.erase(std::remove_if(g_mutations.begin(), g_mutations.end(),
        [](const Mutation& mutation) { return !MutationActive(mutation); }), g_mutations.end());
    return restored;
}

bool Shutdown() {
    std::vector<std::string> failures;
    RestoreAll(failures);
    for (const std::string& failure : failures)
        Warning("[RTXDebug] Failed to restore %s during shutdown\n", failure.c_str());
    for (OwnedWrite& write : g_writes) {
        if (write.pinnedModule) FreeLibrary(write.pinnedModule);
        write.pinnedModule = nullptr;
    }
    for (OwnedPatch& patch : g_patches) {
        if (patch.pinnedModule) FreeLibrary(patch.pinnedModule);
        patch.pinnedModule = nullptr;
    }
    g_mutations.clear();
    g_writes.clear();
    g_patches.clear();
    g_canMutate = nullptr;
    g_mainThread = 0;
    return failures.empty();
}

} // namespace RTXDebug::Memory

#endif // _WIN64
