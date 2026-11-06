#pragma once
#include "nl/config.h"
#include "nl/journal.h"
#include <filesystem>
#include <optional>
#include <string>
#include <string_view>

namespace nl::proxy::loader_release {
inline constexpr std::string_view kPath = "garrysmod/addons/nativeloader/resource/loader-release.json";
inline constexpr std::size_t kMaxBytes = 1024;
struct Record { std::string version, url; };
// Strict, bounded two-field JSON. No build metadata; the URL must name this exact release.
std::optional<Record> parse(std::string_view bytes);
// Only the active allowlisted runtime owner's committed, unchanged file counts. Failure is silent.
std::optional<Record> read(const std::filesystem::path& root, const config::Config& config,
                           const journal::Generation& generation, std::string_view runtime_owner);
std::string serialize(const std::optional<Record>& record);
}
