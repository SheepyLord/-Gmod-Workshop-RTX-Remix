#pragma once
// Finding the package archives and folders the config allowlists, without the Steam API (it is not
// initialised yet when the bootstrap runs). Only allowlisted sources are looked at: one candidate
// per config entry, nothing else.

#include "nl/config.h"

#include <cstdint>
#include <filesystem>
#include <optional>
#include <set>
#include <string>
#include <vector>

namespace nl::discovery {

// In precedence order: a development folder overrides a local archive, which overrides the Workshop.
enum class Source { dev_folder, local, workshop };
const char* source_name(Source source);

struct Candidate {
  Source source = Source::workshop;
  std::string label;                // the config entry as written (Workshop id or path)
  std::filesystem::path location;   // archive file or package folder; empty if not found
  std::string problem;              // why it cannot be used; empty if it can
  // Workshop only, from appworkshop_4000.acf (Steam's record of the installed version):
  std::optional<std::uint64_t> time_updated;
  std::string workshop_manifest;
  bool disabled_by_user = false;  // addon-list opt-out, distinct from a temporarily unusable source
};

struct Environment {
  std::filesystem::path game_root;
  std::optional<std::filesystem::path> workshop_content;  // <library>\steamapps\workshop\content\4000
  std::filesystem::path appworkshop_acf;                  // <library>\steamapps\workshop\appworkshop_4000.acf
  std::set<std::string> disabled_workshop;                // ids in garrysmod\cfg\addonnomount.txt
};

// Where Workshop items live: the library the game root sits in (<library>\steamapps\common\<dir>),
// else the library Steam's libraryfolders.vdf lists for app 4000. `steam_root` replaces the
// registry lookup (HKCU\Software\Valve\Steam\SteamPath).
Environment environment_for(const std::filesystem::path& game_root,
                            const std::optional<std::filesystem::path>& steam_root = std::nullopt);

// Workshop ids GMod's addon list has disabled (garrysmod\cfg\addonnomount.txt); empty if none.
std::set<std::string> read_addonnomount(const std::filesystem::path& game_root);

// One candidate per allowlisted entry: dev folders, then local archives, then Workshop items, each
// in config order.
std::vector<Candidate> discover(const config::Config& config, const Environment& env);

}  // namespace nl::discovery
