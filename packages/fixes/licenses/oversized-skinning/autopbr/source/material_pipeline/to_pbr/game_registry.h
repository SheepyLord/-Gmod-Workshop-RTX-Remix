// GPL-2.0. Worker-owned records for imported textures whose local source is unavailable.
#pragma once
#include "pbr_policy.h"
#include <Windows.h>
#include <array>
#include <iomanip>
#include <limits>
#include <locale>
#include <map>
#include <optional>
#include <sstream>

namespace MaterialPipeline { namespace ToPBR { namespace GameRegistry {
namespace fs = std::filesystem;
constexpr unsigned RecordVersion = 1;
// Independent of the generator: raise only to retire records with a known correctness bug.
constexpr unsigned MinimumRecordVersion = 1;
constexpr size_t MaxRecords = 4096, MaxHashes = 64, MaxBytes = 8 * 1024 * 1024;
struct Texture { std::string file; uint64_t bytes = 0, digest = 0; };
struct Record {
    unsigned version = RecordVersion, generator = 0;
    std::string identity;
    std::vector<uint64_t> hashes; // Provenance only; never a source of live registrations.
    std::array<Texture, 4> textures; // normal, roughness, metallic, emission
    float roughness = .7f, metallic = 0, emission = 1;
};
inline std::string Identity(std::string name) {
    for (auto& c : name) {
        if (c == '\\') c = '/';
        else if (uint8_t(c) < 128) c = char(std::tolower(uint8_t(c)));
    }
    if (name.size() != 22 || name.compare(0, 6, "mmd/t/") != 0) return {};
    for (size_t i = 6; i < name.size(); ++i)
        if (!((name[i] >= '0' && name[i] <= '9') || (name[i] >= 'a' && name[i] <= 'f'))) return {};
    return name;
}
inline bool SafeFile(const std::string& file) {
    if (file.size() < 5 || file.size() > 128 || file.substr(file.size() - 4) != ".dds") return false;
    for (unsigned char c : file)
        if (!((c >= 'a' && c <= 'z') || (c >= 'A' && c <= 'Z') ||
              (c >= '0' && c <= '9') || c == '_' || c == '-' || c == '.')) return false;
    return file.find("..") == std::string::npos;
}
inline bool ValidRecord(const Record& record) {
    if (record.version < MinimumRecordVersion || record.version > RecordVersion || !record.generator ||
        Identity(record.identity) != record.identity || record.identity.empty() || record.hashes.empty() ||
        record.hashes.size() > MaxHashes || (record.textures[0].file.empty() && record.textures[1].file.empty()) ||
        !std::isfinite(record.roughness) || record.roughness < 0 || record.roughness > 1 ||
        !std::isfinite(record.metallic) || record.metallic < 0 || record.metallic > 1 ||
        !std::isfinite(record.emission) || record.emission < 0 || record.emission > 10000) return false;
    for (auto hash : record.hashes) if (!hash) return false;
    for (const auto& texture : record.textures) {
        if (texture.file.empty()) { if (texture.bytes || texture.digest) return false; }
        else if (!SafeFile(texture.file) || texture.bytes < 132 || texture.bytes > 90 * 1024 * 1024) return false;
    }
    return true;
}
inline std::optional<Texture> Inspect(const fs::path& path, bool digest) {
    // No links/junctions, traversal or alternate data streams in recorded paths.
    const DWORD attrs = GetFileAttributesW(path.c_str());
    if (attrs == INVALID_FILE_ATTRIBUTES || (attrs & (FILE_ATTRIBUTE_REPARSE_POINT | FILE_ATTRIBUTE_DIRECTORY)) ||
        !Policy::ValidDDS(path)) return {};
    std::error_code ec;
    Texture texture{path.filename().u8string(), fs::file_size(path, ec), 0};
    if (ec || !SafeFile(texture.file)) return {};
    if (digest) {
        std::ifstream file(path, std::ios::binary);
        uint64_t read = 0, hash = 14695981039346656037ull;
        char bytes[65536];
        while (file.read(bytes, sizeof(bytes)) || file.gcount()) {
            read += uint64_t(file.gcount());
            if (read > texture.bytes) return {};
            for (std::streamsize i = 0; i < file.gcount(); ++i) { hash ^= uint8_t(bytes[i]); hash *= 1099511628211ull; }
        }
        if (file.bad() || read != texture.bytes) return {};
        texture.digest = hash;
    }
    return texture;
}
class Registry {
public:
    explicit Registry(fs::path output) : output_(std::move(output)), path_(output_.parent_path() / "game_materials.registry") {}
    const fs::path& Path() const { return path_; }
    size_t Size() const { return records_.size(); }
    bool Capture(Record& record, const std::array<std::string, 4>& paths) const {
        for (size_t i = 0; i < paths.size(); ++i) {
            if (paths[i].empty()) continue;
            const auto path = fs::u8path(paths[i]).lexically_normal();
            if (path.parent_path() != output_.lexically_normal()) return false;
            auto texture = Inspect(path, true);
            if (!texture) return false;
            record.textures[i] = *texture;
        }
        return ValidRecord(record);
    }
    bool Load() {
        records_.clear(); writable_ = true;
        std::error_code ec;
        if (!fs::exists(path_, ec)) return !ec;
        const auto bytes = fs::file_size(path_, ec);
        if (ec || bytes > MaxBytes) { writable_ = false; return false; }
        std::ifstream file(path_, std::ios::binary);
        std::string text(size_t(bytes), '\0');
        if (!file.read(text.data(), std::streamsize(text.size()))) { writable_ = false; return false; }
        std::istringstream lines(text); lines.imbue(std::locale::classic());
        std::string line;
        if (!std::getline(lines, line) || line != "TOPBR_GAME_REGISTRY 1") { writable_ = false; return false; }
        size_t count = 0;
        while (std::getline(lines, line)) {
            if (++count > MaxRecords) { records_.clear(); writable_ = false; return false; }
            if (line.size() > 4096) continue;
            Record record; size_t hashes = 0;
            std::istringstream row(line); row.imbue(std::locale::classic());
            if (!(row >> record.identity >> record.version >> record.generator >> hashes) || hashes > MaxHashes) continue;
            record.hashes.resize(hashes);
            for (auto& hash : record.hashes) row >> std::hex >> hash >> std::dec;
            for (auto& texture : record.textures) {
                row >> texture.file >> texture.bytes >> std::hex >> texture.digest >> std::dec;
                if (texture.file == "-") texture.file.clear();
            }
            if (!(row >> record.roughness >> record.metallic >> record.emission)) continue;
            row >> std::ws;
            if (!row.eof() || !ValidRecord(record) || !Validate(record, false)) continue;
            // Duplicate identities are ambiguous; reject the whole file rather than select one.
            if (!records_.emplace(record.identity, record).second) { records_.clear(); writable_ = false; return false; }
        }
        return true;
    }
    bool Save() const {
        if (!writable_) return false; // Keep an unknown/unreadable registry intact.
        std::ostringstream text; text.imbue(std::locale::classic());
        text << "TOPBR_GAME_REGISTRY 1\n" << std::setprecision(std::numeric_limits<float>::max_digits10);
        for (const auto& pair : records_) {
            const auto& record = pair.second;
            text << record.identity << ' ' << record.version << ' ' << record.generator << ' ' << record.hashes.size();
            for (auto hash : record.hashes) text << ' ' << std::hex << hash << std::dec;
            for (const auto& texture : record.textures)
                text << ' ' << (texture.file.empty() ? "-" : texture.file) << ' ' << texture.bytes << ' '
                     << std::hex << texture.digest << std::dec;
            text << ' ' << record.roughness << ' ' << record.metallic << ' ' << record.emission << '\n';
        }
        const std::string bytes = text.str();
        if (bytes.size() > MaxBytes) return false;
        // Preserve pre-existing and subsequently edited registry bytes just as USD
        // publication does. Ordinary repeated writes in this worker need no backup.
        const DWORD attrs = GetFileAttributesW(path_.c_str());
        if (attrs != INVALID_FILE_ATTRIBUTES) {
            if (attrs & (FILE_ATTRIBUTE_DIRECTORY | FILE_ATTRIBUTE_REPARSE_POINT)) return false;
            std::ifstream file(path_, std::ios::binary | std::ios::ate);
            const auto size = file.tellg();
            if (!file || size < 0 || uint64_t(size) > MaxBytes) return false;
            std::string previous(size_t(size), '\0'); file.seekg(0);
            if (!file.read(previous.data(), std::streamsize(previous.size()))) return false;
            if (previous == bytes) { lastPublished_ = bytes; return true; }
            if (!lastPublished_ || previous != *lastPublished_) {
                uint64_t hash = 14695981039346656037ull;
                for (unsigned char c : previous) { hash ^= c; hash *= 1099511628211ull; }
                std::ostringstream suffix; suffix << ".before-r11b-" << std::hex << hash << ".bak";
                const fs::path backup(path_.wstring() + fs::u8path(suffix.str()).wstring());
                if (!CopyFileW(path_.c_str(), backup.c_str(), TRUE) && !Policy::SameFile(path_, backup)) return false;
                if (!Policy::SameFile(path_, backup)) return false;
            }
        }
        const fs::path staged(path_.wstring() + L".tmp");
        { std::ofstream file(staged, std::ios::binary | std::ios::trunc);
          file.write(bytes.data(), std::streamsize(bytes.size())); file.close(); if (!file) return false; }
        if (MoveFileExW(staged.c_str(), path_.c_str(), MOVEFILE_REPLACE_EXISTING | MOVEFILE_WRITE_THROUGH)) {
            lastPublished_ = bytes; return true;
        }
        std::error_code ec; fs::remove(staged, ec); return false;
    }
    // A readable source always calls today's converter; failed/empty conversion cannot revive old maps.
    // The generator number is provenance, not an expiry check for source-less records.
    template<class Convert>
    std::optional<Record> Resolve(const std::string& identity, const std::vector<uint64_t>& liveHashes,
                                  bool enabled, bool sourceReadable, Convert convert) {
        if (!enabled || Identity(identity) != identity || identity.empty() || liveHashes.empty() || liveHashes.size() > MaxHashes) return {};
        for (auto hash : liveHashes) if (!hash) return {};
        if (sourceReadable) {
            auto record = convert();
            if (record) {
                record->identity = identity; record->hashes = liveHashes;
                if (!ValidRecord(*record) || !Validate(*record, true)) record.reset();
            }
            if (record && (records_.count(identity) || records_.size() < MaxRecords)) records_[identity] = *record;
            else records_.erase(identity);
            return record;
        }
        auto found = records_.find(identity);
        if (found == records_.end()) return {};
        if (!Validate(found->second, true)) { records_.erase(found); return {}; }
        Record record = found->second;
        record.hashes = liveHashes; // Return only this session's hashes to the caller.
        return record;
    }
    std::string TexturePath(const Texture& texture) const {
        return texture.file.empty() ? std::string{} : (output_ / fs::u8path(texture.file)).u8string();
    }
private:
    bool Validate(const Record& record, bool digest) const {
        const DWORD attrs = GetFileAttributesW(output_.c_str());
        if (attrs == INVALID_FILE_ATTRIBUTES || (attrs & FILE_ATTRIBUTE_REPARSE_POINT)) return false;
        for (const auto& texture : record.textures) if (!texture.file.empty()) {
            const auto checked = Inspect(output_ / fs::u8path(texture.file), digest);
            if (!checked || checked->bytes != texture.bytes || (digest && checked->digest != texture.digest)) return false;
        }
        return true;
    }
    fs::path output_, path_;
    std::map<std::string, Record> records_;
    bool writable_ = true;
    mutable std::optional<std::string> lastPublished_;
};
}}}
