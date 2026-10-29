#include "nl/content.h"

#include "nl/paths.h"

#include <array>

namespace nl::content {

namespace {

// Exactly gmad.exe's wildcard table (v3, 2026-06 build), as tools/gmapack/gmapack.py vendors it. A
// leading '!' is an exception that wins over every pattern.
constexpr std::array<std::string_view, 73> kWhitelist = {
    "lua/*.lua",
    "scenes/*.vcd",
    "particles/*.pcf",
    "resource/fonts/*.ttf",
    "scripts/vehicles/*.txt",
    "resource/localization/*/*.properties",
    "maps/*.bsp", "maps/*.lmp", "maps/*.nav", "maps/*.ain", "maps/thumb/*.png",
    "sound/*.wav", "sound/*.mp3", "sound/*.ogg",
    "materials/*.vmt", "materials/*.vtf", "materials/*.png",
    "materials/*.jpg", "materials/*.jpeg",
    "materials/colorcorrection/*.raw",
    "models/*.mdl", "models/*.phy", "models/*.ani",
    "models/*.vvd", "models/*.vtx",
    "!models/*.sw.vtx", "!models/*.360.vtx", "!models/*.xbox.vtx",
    "gamemodes/*/*.txt", "!gamemodes/*/*/*.txt",
    "gamemodes/*/*.fgd", "!gamemodes/*/*/*.fgd",
    "gamemodes/*/logo.png", "gamemodes/*/icon24.png",
    "gamemodes/*/gamemode/*.lua",
    "gamemodes/*/entities/effects/*.lua",
    "gamemodes/*/entities/weapons/*.lua",
    "gamemodes/*/entities/entities/*.lua",
    "gamemodes/*/backgrounds/*.png",
    "gamemodes/*/backgrounds/*.jpg",
    "gamemodes/*/backgrounds/*.jpeg",
    "gamemodes/*/content/models/*.mdl",
    "gamemodes/*/content/models/*.phy",
    "gamemodes/*/content/models/*.ani",
    "gamemodes/*/content/models/*.vvd",
    "gamemodes/*/content/models/*.vtx",
    "!gamemodes/*/content/models/*.sw.vtx",
    "!gamemodes/*/content/models/*.360.vtx",
    "!gamemodes/*/content/models/*.xbox.vtx",
    "gamemodes/*/content/materials/*.vmt",
    "gamemodes/*/content/materials/*.vtf",
    "gamemodes/*/content/materials/*.png",
    "gamemodes/*/content/materials/*.jpg",
    "gamemodes/*/content/materials/*.jpeg",
    "gamemodes/*/content/materials/colorcorrection/*.raw",
    "gamemodes/*/content/scenes/*.vcd",
    "gamemodes/*/content/particles/*.pcf",
    "gamemodes/*/content/resource/fonts/*.ttf",
    "gamemodes/*/content/scripts/vehicles/*.txt",
    "gamemodes/*/content/resource/localization/*/*.properties",
    "gamemodes/*/content/maps/*.bsp",
    "gamemodes/*/content/maps/*.nav",
    "gamemodes/*/content/maps/*.ain",
    "gamemodes/*/content/maps/thumb/*.png",
    "gamemodes/*/content/sound/*.wav",
    "gamemodes/*/content/sound/*.mp3",
    "gamemodes/*/content/sound/*.ogg",
    "data_static/*.txt", "data_static/*.dat", "data_static/*.json",
    "data_static/*.xml", "data_static/*.csv",
    "shaders/fxc/*.vcs",
};

constexpr std::array<std::string_view, 15> kRemixModTypes = {
    ".usd", ".usda", ".usdc", ".usdz", ".dds", ".png", ".jpg", ".jpeg", ".tga", ".bmp", ".exr", ".hdr", ".mdl",
    ".json", ".txt",
};

constexpr std::string_view kRoot = "native/root/";
constexpr std::string_view kAddons = "garrysmod/addons/";
constexpr std::string_view kMods = "rtx-remix/mods/";

// Source's wildcard match, as gmapack's: '*' matches anything, '/' included; '?' one character.
bool wildcard(std::string_view pattern, std::string_view text) {
  std::size_t p = 0, i = 0, star = std::string_view::npos, mark = 0;
  while (i < text.size()) {
    if (p < pattern.size() && pattern[p] == '*') {
      star = p++;
      mark = i;
    } else if (p < pattern.size() && (pattern[p] == text[i] || pattern[p] == '?')) {
      ++p;
      ++i;
    } else if (star != std::string_view::npos) {
      p = star + 1;
      i = ++mark;
    } else {
      return false;
    }
  }
  while (p < pattern.size() && pattern[p] == '*') ++p;
  return p == pattern.size();
}

bool ends_with(std::string_view text, std::string_view suffix) {
  return text.size() >= suffix.size() && text.substr(text.size() - suffix.size()) == suffix;
}

}  // namespace

bool workshop_whitelisted(std::string_view path) {
  const std::string folded = paths::fold(path);
  bool allowed = false;
  for (const std::string_view pattern : kWhitelist) {
    if (pattern.front() == '!') {
      if (wildcard(pattern.substr(1), folded)) return false;
    } else if (wildcard(pattern, folded)) {
      allowed = true;
    }
  }
  return allowed;
}

bool remix_mod_file(std::string_view path) {
  const std::string folded = paths::fold(path);
  for (const std::string_view type : kRemixModTypes) {
    if (ends_with(folded, type)) return true;
  }
  return false;
}

std::string problem(const manifest::Manifest& m) {
  for (const manifest::Kind kind : m.kinds) {
    if (kind != manifest::Kind::root_files && kind != manifest::Kind::lua_addon) {
      return std::string("it is a ") + manifest::kind_name(kind) + " package";
    }
  }
  if (m.remix) return "it has a remix runtime section";
  if (!m.session.empty()) return "it changes RTX sessions (patch sets, module overrides or session variables)";
  if (!m.module_dependencies.empty()) return "it has module dependencies";
  for (const manifest::RootFile& root : m.root_files) {
    if (root.area != paths::RootArea::rtx_remix_mods && root.area != paths::RootArea::lua_addons) {
      return "it deploys " + root.path + ", outside rtx-remix/mods and garrysmod/addons";
    }
  }
  for (const auto& [path, info] : m.files) {
    const std::string folded = paths::fold(path);
    if (folded == "native/manifest.json") continue;
    if (!folded.starts_with(kRoot)) return "it holds " + path + ", outside native/root";
    const std::string deployed = path.substr(kRoot.size());
    const std::string_view area = std::string_view(folded).substr(kRoot.size());
    if (area.starts_with(kAddons)) {
      // garrysmod/addons/<add-on>/<path>: what GMod's Workshop takes in an add-on, or its addon.json.
      const std::string_view rest = area.substr(kAddons.size());
      const std::size_t slash = rest.find('/');
      const std::string_view inner = slash == std::string_view::npos ? std::string_view() : rest.substr(slash + 1);
      if (inner != "addon.json" && !workshop_whitelisted(inner)) {
        return "its add-on file " + deployed + " is not one GMod's Workshop allows";
      }
    } else if (area.starts_with(kMods)) {
      if (!remix_mod_file(area)) return "its file " + deployed + " is not Remix mod data";
    } else {
      return "it holds " + deployed + ", outside rtx-remix/mods and garrysmod/addons";
    }
  }
  return {};
}

}  // namespace nl::content
