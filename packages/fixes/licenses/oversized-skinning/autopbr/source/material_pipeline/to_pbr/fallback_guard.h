// GPL-2.0. Conservative filesystem exclusion; runtime lookup remains authoritative.
#pragma once
#include <cstdint>
#include <filesystem>
#include <fstream>
#include <string>
#include <unordered_set>
#include <Windows.h>

namespace MaterialPipeline { namespace ToPBR { namespace FallbackGuard {
struct Result { bool complete = true; std::unordered_set<uint64_t> hashes; };
template<class Materials>
Materials Select(const Materials& materials, bool worldEnabled, bool gameEnabled, const Result& guard) {
    Materials visible;
    if (guard.complete) for (const auto& pair : materials)
        if ((pair.second.importedGame ? gameEnabled : worldEnabled) && !guard.hashes.count(pair.first)) visible.insert(pair);
    return visible;
}
inline void ExtractHashes(const std::string& text, Result& result) {
    size_t at = 0;
    while ((at = text.find("mat_", at)) != std::string::npos) {
        at += 4;
        size_t end = at; uint64_t value = 0;
        for (; end < text.size(); ++end) {
            unsigned char c = text[end];
            unsigned digit = c >= '0' && c <= '9' ? c - '0' :
                c >= 'A' && c <= 'F' ? c - 'A' + 10 :
                c >= 'a' && c <= 'f' ? c - 'a' + 10 : 16;
            if (digit == 16) break;
            if (end - at >= 16) { result.complete = false; break; }
            value = (value << 4) | digit;
        }
        if (value && end > at) result.hashes.insert(value);
        at = end + 1;
    }
}
inline Result Scan(const std::filesystem::path& mods, const std::filesystem::path& generated) {
    Result result; std::error_code ec;
    size_t entries = 0; uint64_t total = 0;
    std::filesystem::recursive_directory_iterator it(mods, ec), end;
    if (ec) { result.complete = false; return result; }
    for (; it != end; it.increment(ec)) {
        if (ec || ++entries > 32768) { result.complete = false; break; }
        const auto& path = it->path();
        if (path == generated) { it.disable_recursion_pending(); continue; }
        const DWORD attrs = GetFileAttributesW(path.c_str());
        if (attrs == INVALID_FILE_ATTRIBUTES || (attrs & FILE_ATTRIBUTE_REPARSE_POINT)) {
            result.complete = false; it.disable_recursion_pending(); continue;
        }
        if (it.depth() > 16) { result.complete = false; it.disable_recursion_pending(); continue; }
        if (!it->is_regular_file(ec)) continue;
        auto ext = path.extension().wstring();
        for (auto& c : ext) c = wchar_t(towlower(c));
        if (ext != L".usda" && ext != L".usd" && ext != L".usdc") continue;
        const auto size = it->file_size(ec);
        if (ec || size > 16 * 1024 * 1024 || (total += size) > 64 * 1024 * 1024) {
            result.complete = false; continue;
        }
        std::string text(size_t(size), '\0');
        std::ifstream f(path, std::ios::binary);
        if (!f.read(text.data(), std::streamsize(size)) || text.find(char(0)) != std::string::npos ||
            text.compare(0, 8, "PXR-USDC") == 0) {
            // Binary USD and unknown layouts cannot be proved non-overlapping.
            result.complete = false; continue;
        }
        ExtractHashes(text, result);
    }
    if (ec) result.complete = false;
    return result;
}
}}}
