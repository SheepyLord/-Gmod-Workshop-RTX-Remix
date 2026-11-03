// GPL-2.0. Atomic publication of imported game maps and the legacy-map transcoder (R13-M).
// Worker-only; no session budget applies: free disk space and the image bound are the limits.
#pragma once
#include "pbr_policy.h"
#include <Windows.h>
#include <functional>

namespace MaterialPipeline { namespace ToPBR { namespace DDS {
namespace fs = std::filesystem;
using SpaceQuery = std::function<std::optional<uint64_t>(const fs::path&)>;
inline std::optional<uint64_t> FreeSpace(const fs::path& folder) {
    std::error_code ec;
    const auto space = fs::space(folder, ec);
    if (ec) return {};
    return space.available;
}
// Writes the full chain as `format` through a flushed staging file and a write-through
// replacement. An existing file at `path` is one the caller found invalid: it is kept as
// `<path>.rejected-<tick>`, as the uncompressed writer always did. Every refusal throws one line.
inline void Publish(const fs::path& path, const std::vector<Level>& chain, Format format,
                    const SpaceQuery& space = FreeSpace) {
    if (chain.empty()) throw std::runtime_error("image bounds exceeded: map has no levels");
    const uint32_t w = chain[0].width, h = chain[0].height;
    if (!Policy::ValidImage(w, h)) throw std::runtime_error(Policy::ImageRefusal(w, h, path.filename().u8string()));
    const auto bytes = Encode(chain, format);
    const auto available = space(path.parent_path());
    if (!available || *available < bytes.size() + Policy::DiskHeadroom)
        throw std::runtime_error(Policy::DiskRefusal(available, bytes.size(), path.parent_path().u8string()));
    const DWORD attrs = GetFileAttributesW(path.c_str());
    if (attrs != INVALID_FILE_ATTRIBUTES) {
        if (attrs & (FILE_ATTRIBUTE_DIRECTORY | FILE_ATTRIBUTE_REPARSE_POINT))
            throw std::runtime_error("DDS destination is a folder or link: " + path.filename().u8string());
        const fs::path rejected(path.wstring() + L".rejected-" + std::to_wstring(GetTickCount64()));
        if (!MoveFileExW(path.c_str(), rejected.c_str(), MOVEFILE_WRITE_THROUGH))
            throw std::runtime_error("cannot move the invalid DDS aside: " + path.filename().u8string());
    }
    const fs::path staged(path.wstring() + L".tmp");
    HANDLE file = CreateFileW(staged.c_str(), GENERIC_WRITE, 0, nullptr, CREATE_ALWAYS, FILE_ATTRIBUTE_NORMAL, nullptr);
    bool written = file != INVALID_HANDLE_VALUE;
    for (size_t offset = 0; written && offset < bytes.size();) {
        DWORD count = 0;
        const DWORD chunk = DWORD((std::min)(bytes.size() - offset, size_t(64) * 1024 * 1024));
        written = WriteFile(file, bytes.data() + offset, chunk, &count, nullptr) != 0 && count != 0;
        offset += count;
    }
    if (written) written = FlushFileBuffers(file) != 0;
    DWORD error = written ? ERROR_SUCCESS : GetLastError();
    if (file != INVALID_HANDLE_VALUE && !CloseHandle(file) && written) { written = false; error = GetLastError(); }
    if (written && !Policy::ValidDDS(staged, format)) { written = false; error = ERROR_INVALID_DATA; }
    if (!written) {
        DeleteFileW(staged.c_str());
        throw std::runtime_error("DDS write failed: " + path.filename().u8string() + " (Windows error " + std::to_string(error) + ")");
    }
    if (!MoveFileExW(staged.c_str(), path.c_str(), MOVEFILE_REPLACE_EXISTING | MOVEFILE_WRITE_THROUGH)) {
        const auto moveError = GetLastError();
        DeleteFileW(staged.c_str());
        throw std::runtime_error("DDS publication failed: " + path.filename().u8string() + " (Windows error " + std::to_string(moveError) + ")");
    }
}
// The format a role is stored in. Roles: 0 normal (octahedral RG), 1 roughness, 2 metallic,
// 3 emission. Emission and maps whose base is not block-aligned stay uncompressed.
inline Format GameFormat(size_t role, uint32_t w, uint32_t h) {
    if (role > 2 || !BlockAligned(w, h)) return Format::RGBA8;
    return role == 0 ? Format::BC5 : Format::BC4;
}
// A stored map may be in its compact format or (records written before R13) uncompressed.
inline bool RoleAccepts(size_t role, Format format) {
    return format == Format::RGBA8 || (role == 0 && format == Format::BC5) || ((role == 1 || role == 2) && format == Format::BC4);
}
// Re-encodes a finished uncompressed map's stored levels. No source image is read.
inline void Transcode(const fs::path& from, const fs::path& to, Format format, const SpaceQuery& space = FreeSpace) {
    Info info;
    const auto chain = Read(from, info);
    if (info.format != Format::RGBA8) throw std::runtime_error("only uncompressed maps are transcoded: " + from.filename().u8string());
    Publish(to, chain, format, space);
}
}}}
