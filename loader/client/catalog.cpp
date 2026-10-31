#include "catalog.h"
#include "nl/fs.h"
#include "nl/sha256.h"
#include "nl/paths.h"
#include <algorithm>
#include <stdexcept>

namespace nl::client {
namespace {
std::string lower(std::string value) {
  for (char& c : value) if (c >= 'A' && c <= 'Z') c = static_cast<char>(c - 'A' + 'a');
  return value;
}
bool same_path(const std::filesystem::path& a, const std::filesystem::path& b) {
  return lower(fs::utf8(std::filesystem::absolute(a).lexically_normal())) ==
         lower(fs::utf8(std::filesystem::absolute(b).lexically_normal()));
}
bool allowed_source(const std::filesystem::path& root, const config::Config& config, const journal::Package& package) {
  const auto location = fs::join(root, package.location);
  if (package.source == "local" || package.source == "dev_folder") {
    const auto& allowed = package.source == "local" ? config.local : config.dev_folders;
    return std::any_of(allowed.begin(), allowed.end(), [&](const auto& value) { return same_path(location, fs::join(root, value)); });
  }
  if (package.source != "workshop") return false;
  if (!std::filesystem::path(package.location).is_absolute()) return false;
  const auto item = location.parent_path();
  const auto content = item.parent_path().parent_path();
  if (lower(fs::utf8(content.filename())) != "content" ||
      lower(fs::utf8(content.parent_path().filename())) != "workshop") return false;
  return fs::utf8(item.filename()) == "3829070317" && fs::utf8(item.parent_path().filename()) == "4000" &&
    std::find(config.workshop.begin(), config.workshop.end(), "3829070317") != config.workshop.end();
}
}

bool native_bootstrap_present(const journal::Generation& generation) {
  return std::any_of(generation.files.begin(), generation.files.end(), [](const auto& file) {
    return file.package == kPackage && file.path == kModule;
  });
}

bool secure_render_patch_set(std::string_view owner, const manifest::PatchSet& set) {
  if (owner != kPackage) return false;
  // Exact reviewed render-only patch recipes. A renamed owner, added patch or changed byte
  // recipe cannot inherit this exception; all other patch sets retain the insecure gate.
  std::string recipe;
  for (const auto& patch : set.patches) {
    recipe += set.module + "\n" + patch.name + "\n" + patch.find + "\n" + std::to_string(patch.offset) + "\n" + patch.replace + "\n";
  }
  const auto digest = sha256::of(recipe);
  return (set.module == "engine.dll" && digest == "0237f995c5d565c6014a8f35b83dea6e0383695dac78c1f05af0ec9695d1dc9f") ||
    (set.module == "shaderapidx9.dll" && digest == "0c768ff6e4f4df8b5886f7e4efe5ec3277faa2c70bf5df8d534da410f2f4c1bc") ||
    (set.module == "materialsystem.dll" && digest == "bfde5be5aaa9189459ba5c291501a00df2d82ed7f45d987999252c5e3238c20f") ||
    (set.module == "datacache.dll" && digest == "51fc7fdc90777a6eb265a5dbe0f282a9fb4087364da18ca099bd67b9a4510341");
}

Catalog prepare(const std::filesystem::path& root, const config::Config& config,
                const journal::Generation& generation) {
  if (!config.from_file || !config.enabled || !config.remix_enabled) throw std::runtime_error("RTX client payload is disabled");
  const journal::Package* owner = nullptr;
  for (const auto& package : generation.packages) {
    if (package.id == kPackage) {
      if (owner) throw std::runtime_error("Duplicate RTX package identity");
      owner = &package;
    }
  }
  if (!owner || !owner->remix || !owner->requires_remix || !allowed_source(root, config, *owner))
    throw std::runtime_error("RTX client payload has no allowlisted runtime owner");
  if (!native_bootstrap_present(generation)) throw std::runtime_error("RTX client bootstrap was not deployed by its owner");
  Catalog out;
  out.identity = owner->manifest_sha256;
  out.runtime = owner->payload + "/" + owner->remix->entry;
  std::size_t total = 0;
  bool module_verified = false;
  for (const auto& file : generation.files) {
    if (file.package != kPackage) continue;
    if (!paths::is_safe(file.path)) throw std::runtime_error("RTX client file path is not safe");
    const std::string name = lower(file.path);
    if (file.path == kModule) {
      fs::refuse_links(root, file.path);
      const auto bytes = fs::read_file(fs::join(root, file.path), std::size_t{8} << 20);
      if (bytes.size() != file.size || sha256::of(bytes) != file.sha256) throw std::runtime_error("RTX client bootstrap bytes changed");
      module_verified = true;
    }
    constexpr std::string_view prefix = "garrysmod/addons/";
    if (!name.starts_with(prefix) || !name.ends_with(".lua")) continue;
    const auto slash = name.find('/', prefix.size());
    if (slash == std::string::npos || name.substr(slash, 5) != "/lua/") continue;
    const auto addon = name.substr(prefix.size(), slash - prefix.size());
    const auto path = name.substr(slash + 5);
    // Automation that accepts arbitrary source is never enabled by the multiplayer loader.
    if (addon == "rtx_agent" || (addon == "mmd_hotloader" && path == "mmdhl/debug.lua")) continue;
    fs::refuse_links(root, file.path);
    const auto bytes = fs::read_file(fs::join(root, file.path), std::size_t{2} << 20);
    if (bytes.size() != file.size || sha256::of(bytes) != file.sha256 || bytes.find('\0') != std::string::npos)
      throw std::runtime_error("An owned RTX client script changed; snapshot refused");
    total += bytes.size();
    if (total > (std::size_t{64} << 20)) throw std::runtime_error("RTX client script snapshot exceeds its limit");
    if (!out.scripts.emplace(addon + "/" + path, Script{addon, path, bytes}).second)
      throw std::runtime_error("RTX client script names collide");
  }
  if (!module_verified || out.scripts.empty()) throw std::runtime_error("RTX client payload is incomplete");
  return out;
}
}
