#pragma once
// The user's loader policy: <game root>\native-loader\config.json (docs/ON_DISK_LAYOUT.md). Above
// all, the allowlist: only the sources listed here may deploy native code (ADR 0003). Subscribed
// Workshop items are also opened, as content-only packages, unless subscribed_content is false (ADR 0027).

#include <filesystem>
#include <stdexcept>
#include <string>
#include <string_view>
#include <vector>

namespace nl::config {

class Error : public std::runtime_error {
 public:
  using std::runtime_error::runtime_error;
};

inline constexpr int kSchema = 1;
inline constexpr std::string_view kConfigPath = "native-loader/config.json";

// remix.reshade (ADR 0028): the RTX package's ReShade in RTX sessions. automatic ("auto") enables it
// when the game has a ReShade set up (bin\win64\ReShade.ini) or RTX sessions already have settings
// of their own (native-loader\reshade\ReShade.ini).
enum class Reshade { automatic, on, off };

struct Config {
  bool enabled = true;
  std::vector<std::string> workshop;     // Workshop item ids (decimal digits)
  std::vector<std::string> local;        // archive paths, relative to the game root or absolute
  std::vector<std::string> dev_folders;  // package folders, relative to the game root or absolute
  // Content-only packages from every subscribed Workshop item, without listing them (ADR 0027). Native
  // code still needs the allowlist: such a package may only hold Remix mods and Lua add-ons.
  bool subscribed_content = true;
  bool remix_enabled = true;             // false: runtime packages are planned but not activated
  Reshade reshade = Reshade::automatic;
  bool patch_sets_require_insecure = true;
  bool allow_secure_rtx_render_patches = true; // exact reviewed renderer recipes only
  bool from_file = false;                // false: defaults, because config.json does not exist
};

// Parses config.json (strict JSON, schema 1, unknown keys are errors). Throws Error.
Config parse(std::string_view json_text);

// Reads <game root>\native-loader\config.json. A missing file gives the defaults, which allow
// nothing. An unreadable or invalid file throws Error: the loader then stays inactive.
Config load(const std::filesystem::path& game_root);

}  // namespace nl::config
