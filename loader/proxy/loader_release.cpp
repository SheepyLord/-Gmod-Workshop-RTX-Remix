#include "loader_release.h"
#include "../client/catalog.h"
#include "nl/fs.h"
#include "nl/json.h"
#include "nl/sha256.h"

namespace nl::proxy::loader_release {
std::optional<Record> parse(std::string_view bytes) {
  try {
    const auto value = json::parse(bytes, {kMaxBytes, 2, 512, 3});
    if (!value.is_object() || value.as_object().size() != 2) return {};
    const auto* version = value.find("version");
    const auto* url = value.find("url");
    if (!version || !url || !version->is_string() || !url->is_string()) return {};
    const auto parsed = manifest::parse_version(version->as_string());
    if (!parsed || !parsed->build.empty() || url->as_string() !=
        "https://github.com/SheepyLord/Gmod-Workshop-RTX-Remix/releases/tag/v" + parsed->text) return {};
    return Record{parsed->text, url->as_string()};
  } catch (const std::exception&) { return {}; }
}

std::optional<Record> read(const std::filesystem::path& root, const config::Config& config,
                           const journal::Generation& generation, std::string_view runtime_owner) {
  try {
    if (!config.from_file || !config.enabled || !config.remix_enabled || runtime_owner != client::kPackage) return {};
    const journal::Package* owner = nullptr;
    for (const auto& package : generation.packages) {
      if (package.id != runtime_owner) continue;
      if (owner) return {};
      owner = &package;
    }
    if (!owner || !owner->remix || !client::allowed_runtime_source(root, config, *owner)) return {};
    const journal::File* record = nullptr;
    for (const auto& file : generation.files) {
      // Reject duplicate/case-alias ownership, including a content owner's identical path.
      if (file.path.size() != kPath.size()) continue;
      std::string name = file.path;
      for (char& c : name) if (c >= 'A' && c <= 'Z') c = static_cast<char>(c - 'A' + 'a');
      if (name != kPath) continue;
      if (record || file.package != runtime_owner || file.path != kPath || file.size > kMaxBytes) return {};
      record = &file;
    }
    if (!record) return {};
    fs::refuse_links(root, kPath);
    const auto bytes = fs::read_file(fs::join(root, kPath), kMaxBytes);
    if (bytes.size() != record->size || sha256::of(bytes) != record->sha256) return {};
    return parse(bytes);
  } catch (const std::exception&) { return {}; }
}
std::string serialize(const std::optional<Record>& record) {
  return record ? "{\"version\":" + json::quote(record->version) + ",\"url\":" + json::quote(record->url) + "}" : "null";
}
}
