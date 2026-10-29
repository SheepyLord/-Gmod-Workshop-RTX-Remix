#pragma once
// ReShade in RTX sessions (loader 0.5.0, ADR 0028). The Remix runtime renders through Vulkan, so the
// RTX package carries ReShade as a Vulkan layer, which the bootstrap enables for an RTX session
// through the Vulkan loader's environment variables. A ReShade installed for Direct3D 9
// (bin\win64\d3d9.dll) never loads into an RTX session: the game binds the runtime's d3d9.dll,
// preloaded at the entry point. The layer gets its own settings folder, native-loader\reshade,
// seeded once from the game's bin\win64\ReShade.ini (paths made absolute, presets copied), so the
// Direct3D 9 ReShade's files are never written and are as they were whenever RTX is off.

#include "nl/config.h"
#include "nl/journal.h"

#include <filesystem>
#include <string>
#include <string_view>
#include <utility>
#include <vector>

namespace nl::reshade {

inline constexpr std::string_view kFolder = "native-loader/reshade";  // the RTX sessions' ReShade base path
inline constexpr std::string_view kGameFolder = "bin/win64";          // where the game's own ReShade lives
inline constexpr std::string_view kIni = "ReShade.ini";
// The disable_environment of the layer ReShade's setup registers for every Vulkan application: set in
// an RTX session, so a ReShade installed that way does not run beside the package's.
inline constexpr std::string_view kGlobalLayerOff = "DISABLE_VK_LAYER_reshade_1";

// What start-up reads from disk to decide.
struct Probe {
  bool game_ini = false;        // bin/win64/ReShade.ini: a ReShade set up for this game (any API)
  bool game_base_path = false;  // ...that sets [INSTALL] BasePath, which ReShade prefers to the loader's folder
  bool own_ini = false;         // native-loader/reshade/ReShade.ini, kept from an earlier RTX session
  std::string layer_name;       // from the package's layer manifest
  std::string layer_library;    // the library it names, relative to the game root
  std::string layer_problem;    // why the layer manifest cannot be used; empty if it can
};

// The deployed package that carries ReShade: the first with a reshade section and a payload.
const journal::Package* carrier(const journal::Generation& generation);

// Reads the facts above. A file it cannot read counts as absent; an unusable layer manifest is
// reported in layer_problem. Throws only for a link on the way to native-loader/reshade.
Probe probe(const std::filesystem::path& root, const journal::Generation& generation);

// A Vulkan layer manifest's layer.name and layer.library_path. The name is VK_LAYER_ and 1-64 of
// A-Z a-z 0-9 _; the library is a .dll file name beside the manifest (".\" may precede it).
// Throws std::runtime_error.
struct Layer {
  std::string name;
  std::string library;  // the file name
};
Layer parse_layer(std::string_view json_text);

// What an RTX session does about ReShade.
struct Plan {
  enum class Settings { keep, migrate, fresh };
  bool enable = false;
  std::string reason;          // why it is or is not enabled
  std::string package;         // id of the package that carries ReShade; empty if none does
  std::string layer_manifest;  // relative to the game root
  std::string layer_dir;
  std::string layer_name;
  std::string library;         // relative to the game root
  Settings settings = Settings::keep;
};
const char* settings_name(Plan::Settings settings);

// Pure. Called for a session whose runtime activates; remix.reshade decides (auto: when the game has
// a ReShade or the RTX sessions have settings of their own).
Plan plan(const journal::Generation& generation, const config::Config& config, const Probe& probe);

// The folder's ReShade.ini from the game's: every path ReShade would resolve against the game's
// folder is made absolute (search paths, screenshots, fonts, sounds, cache, add-ons), a key whose
// default is such a path is written out, and the presets it names (PresetPath, StartupPresetPath,
// PresetShortcutPaths) point to copies in the folder. Lines it does not change stay as they were.
struct Migration {
  std::string ini;
  struct Preset {
    std::filesystem::path source;  // absolute
    std::string name;              // in the folder, '/'-separated
  };
  std::vector<Preset> presets;
  std::filesystem::path preset_folder;  // the current preset's folder: other presets there are copied too
};
Migration migrate(std::string_view game_ini, const std::filesystem::path& game_folder);

// Settings without a ReShade for the game: effects from the folder's reshade-shaders, screenshots
// beside the game's executable.
std::string fresh(const std::filesystem::path& game_folder);

// Whether ini text is a ReShade preset: a Techniques entry before the first section.
bool is_preset(std::string_view text);

// Makes native-loader/reshade and, for migrate or fresh, its ReShade.ini, with the presets copied
// (the migration's, and the other presets in the current preset's folder). Never replaces a file
// in the folder and writes nothing outside it. Throws on failure.
struct Prepared {
  std::string settings;              // kept, migrated or fresh
  std::vector<std::string> presets;  // copied, as named in the folder
  std::vector<std::string> notes;
};
Prepared prepare(const std::filesystem::path& root, Plan::Settings settings);

}  // namespace nl::reshade
