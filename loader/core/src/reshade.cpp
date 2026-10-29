#include "nl/reshade.h"

#include "nl/fs.h"
#include "nl/json.h"
#include "nl/paths.h"

#include <algorithm>
#include <map>
#include <set>
#include <stdexcept>

namespace nl::reshade {
namespace {

using Path = std::filesystem::path;

constexpr std::size_t kMaxIni = std::size_t{1} << 20;  // a ReShade.ini or preset larger than this is not read
constexpr std::size_t kMaxSiblings = 256;              // presets copied from the current preset's folder

std::string trim(std::string_view text) {
  const auto begin = text.find_first_not_of(" \t");
  if (begin == std::string_view::npos) return {};
  return std::string(text.substr(begin, text.find_last_not_of(" \t") - begin + 1));
}

char lower(char c) { return c >= 'A' && c <= 'Z' ? static_cast<char>(c + ('a' - 'A')) : c; }

bool same(std::string_view a, std::string_view b) {
  return a.size() == b.size() && std::equal(a.begin(), a.end(), b.begin(), [](char x, char y) { return lower(x) == lower(y); });
}

std::string folded(std::string_view text) {
  std::string out(text);
  std::transform(out.begin(), out.end(), out.begin(), lower);
  return out;
}

std::string parent(std::string_view path) {
  const auto slash = path.find_last_of('/');
  return slash == std::string_view::npos ? std::string() : std::string(path.substr(0, slash));
}

// One line of ReShade's ini format: "[SECTION]" or "key=value" (a list value is comma-separated).
struct Line {
  std::string text;     // as read, without the line break
  std::string section;  // the section it belongs to; "" before the first
  std::string key;      // empty unless the line is an entry
  std::string value;
};

std::vector<Line> parse_ini(std::string_view text) {
  if (text.substr(0, 3) == "\xEF\xBB\xBF") text.remove_prefix(3);
  std::vector<Line> out;
  std::string section;
  for (std::size_t at = 0;;) {
    const auto end = text.find('\n', at);
    std::string_view raw = text.substr(at, end == std::string_view::npos ? std::string_view::npos : end - at);
    if (!raw.empty() && raw.back() == '\r') raw.remove_suffix(1);
    Line line;
    line.text = std::string(raw);
    const std::string content = trim(raw);
    if (content.size() >= 2 && content.front() == '[' && content.back() == ']') {
      section = content.substr(1, content.size() - 2);
    } else if (const auto equals = raw.find('='); equals != std::string_view::npos && content[0] != ';' && content[0] != '#') {
      line.key = trim(raw.substr(0, equals));
      line.value = trim(raw.substr(equals + 1));
    }
    line.section = section;
    out.push_back(std::move(line));
    if (end == std::string_view::npos) break;
    at = end + 1;
  }
  if (!out.empty() && out.back().text.empty() && !text.empty() && text.back() == '\n') out.pop_back();
  return out;
}

std::vector<std::string> split_list(std::string_view value) {
  std::vector<std::string> out;
  for (std::size_t at = 0;;) {
    const auto comma = value.find(',', at);
    out.emplace_back(value.substr(at, comma == std::string_view::npos ? std::string_view::npos : comma - at));
    if (comma == std::string_view::npos) return out;
    at = comma + 1;
  }
}

std::string join_list(const std::vector<std::string>& items) {
  std::string out;
  for (std::size_t i = 0; i < items.size(); ++i) out += (i ? "," : "") + items[i];
  return out;
}

Path from_utf8(std::string_view text) { return fs::join({}, text); }

// A value ReShade would not resolve against its base folder: absolute (drive, UNC, rooted) or with
// a %MACRO% it expands itself. Left as written.
bool kept_as_written(std::string_view value) {
  return value.empty() || value.find('%') != std::string_view::npos || value[0] == '\\' || value[0] == '/' ||
         (value.size() >= 2 && value[1] == ':');
}

Path resolved(std::string_view value, const Path& base) {
  Path path = (kept_as_written(value) ? from_utf8(value) : base / from_utf8(value)).lexically_normal();
  return path.make_preferred();
}

std::string absolute_value(std::string_view value, const Path& base) {
  return kept_as_written(value) ? std::string(value) : fs::utf8(resolved(value, base));
}

std::string backslashes(std::string text) {
  std::replace(text.begin(), text.end(), '/', '\\');
  return text;
}

// Names in the folder for copied presets: the path below the game's folder for one inside it, else
// the file name; a name another preset took gets " (2)", " (3)", ... before its extension.
class PresetNames {
 public:
  explicit PresetNames(Path game_folder) : game_folder_(std::move(game_folder)) {}

  // The name for `source`, the same one each time it is asked for.
  std::string name(const Path& source) {
    const std::string key = folded(fs::utf8(source));
    if (const auto known = by_source_.find(key); known != by_source_.end()) return known->second;
    const Path relative = source.lexically_relative(game_folder_);
    const bool inside = !relative.empty() && relative.is_relative() &&
                        std::none_of(relative.begin(), relative.end(), [](const Path& part) { return part == ".." || part == "."; });
    std::string base = fs::utf8(inside ? relative : source.filename());
    std::replace(base.begin(), base.end(), '\\', '/');
    // " (2)" goes before the extension of the file name: "a/b.ini" -> "a/b (2).ini".
    const auto name_start = base.find_last_of('/') == std::string::npos ? 0 : base.find_last_of('/') + 1;
    const auto dot = base.find_last_of('.');
    const auto stem_end = dot != std::string::npos && dot > name_start ? dot : base.size();
    std::string chosen = base;
    for (int n = 2; taken_.count(folded(chosen)); ++n) {
      chosen = base.substr(0, stem_end) + " (" + std::to_string(n) + ")" + base.substr(stem_end);
    }
    taken_.insert(folded(chosen));
    by_source_.emplace(key, chosen);
    presets_.push_back({source, chosen});
    return chosen;
  }
  const std::vector<Migration::Preset>& presets() const { return presets_; }

 private:
  Path game_folder_;
  std::map<std::string, std::string> by_source_;
  std::set<std::string> taken_;
  std::vector<Migration::Preset> presets_;
};

enum class KeyKind { path, paths, preset, presets };
struct KeyRule {
  std::string_view section;
  std::string_view key;
  KeyKind kind;
  std::string_view fallback;  // ReShade's default when the key is absent, against the base folder; "" for none
};
// Every ReShade 6.8 setting that holds a path ReShade resolves against its base folder.
constexpr KeyRule kRules[] = {
    {"GENERAL", "EffectSearchPaths", KeyKind::paths, ".\\"},
    {"GENERAL", "TextureSearchPaths", KeyKind::paths, ".\\"},
    {"GENERAL", "IntermediateCachePath", KeyKind::path, ""},
    {"GENERAL", "PresetPath", KeyKind::preset, ".\\ReShadePreset.ini"},
    {"GENERAL", "StartupPresetPath", KeyKind::preset, ""},
    {"GENERAL", "PresetShortcutPaths", KeyKind::presets, ""},
    {"SCREENSHOT", "SavePath", KeyKind::path, ".\\"},
    {"SCREENSHOT", "SoundPath", KeyKind::path, ""},
    {"SCREENSHOT", "PostSaveCommandWorkingDirectory", KeyKind::path, ".\\"},
    {"STYLE", "EditorFont", KeyKind::path, ""},
    {"STYLE", "Font", KeyKind::path, ""},
    {"STYLE", "LatinFont", KeyKind::path, ""},
    {"ADDON", "AddonPath", KeyKind::path, ""},
};

const KeyRule* rule_for(const Line& line) {
  for (const KeyRule& rule : kRules) {
    if (same(line.section, rule.section) && same(line.key, rule.key)) return &rule;
  }
  return nullptr;
}

std::string text_of(const std::vector<Line>& lines) {
  std::string out;
  for (const Line& line : lines) out += line.text + "\r\n";
  return out;
}

}  // namespace

const journal::Package* carrier(const journal::Generation& generation) {
  for (const journal::Package& package : generation.packages) {
    if (package.reshade && !package.payload.empty()) return &package;
  }
  return nullptr;
}

Layer parse_layer(std::string_view json_text) {
  const json::Value root = json::parse(json_text, {std::size_t{64} << 10, 8, 4096, 1000});
  const json::Value* layer = root.find("layer");
  const json::Value* name = layer ? layer->find("name") : nullptr;
  const json::Value* library = layer ? layer->find("library_path") : nullptr;
  if (!name || !name->is_string() || !library || !library->is_string()) {
    throw std::runtime_error("layer.name and layer.library_path must be strings");
  }
  Layer out;
  out.name = name->as_string();
  const std::string_view tail = std::string_view(out.name).substr(std::min<std::size_t>(9, out.name.size()));
  if (out.name.rfind("VK_LAYER_", 0) != 0 || tail.empty() || tail.size() > 64 ||
      !std::all_of(tail.begin(), tail.end(), [](char c) {
        return (c >= 'A' && c <= 'Z') || (c >= 'a' && c <= 'z') || (c >= '0' && c <= '9') || c == '_';
      })) {
    throw std::runtime_error("layer.name \"" + out.name + "\" must be VK_LAYER_ and 1-64 of A-Z a-z 0-9 _");
  }
  std::string_view file = library->as_string();
  if (file.substr(0, 2) == ".\\" || file.substr(0, 2) == "./") file.remove_prefix(2);
  if (file.size() < 5 || !same(file.substr(file.size() - 4), ".dll") ||
      file.find_first_of("/\\:") != std::string_view::npos || !paths::is_safe(file)) {
    throw std::runtime_error("layer.library_path must name a .dll beside the manifest");
  }
  out.library = std::string(file);
  return out;
}

Probe probe(const Path& root, const journal::Generation& generation) {
  Probe p;
  const Path game_ini = fs::join(root, std::string(kGameFolder) + "/" + std::string(kIni));
  try {
    const fs::Stat info = fs::stat(game_ini);
    p.game_ini = info.exists && !info.directory;
    if (p.game_ini) {
      for (const Line& line : parse_ini(fs::read_file(game_ini, kMaxIni))) {
        if (same(line.section, "INSTALL") && same(line.key, "BasePath") && !line.value.empty()) p.game_base_path = true;
      }
    }
  } catch (const fs::Error&) {
    // Present but unreadable: a migration would fail later and say so.
  }
  fs::refuse_links(root, kFolder);
  try {
    const fs::Stat own = fs::stat(fs::join(root, std::string(kFolder) + "/" + std::string(kIni)));
    p.own_ini = own.exists && !own.directory;
  } catch (const fs::Error&) {
  }
  if (const journal::Package* package = carrier(generation)) {
    const std::string manifest = package->payload + "/" + package->reshade->layer;
    try {
      const Layer layer = parse_layer(fs::read_file(fs::join(root, manifest), std::size_t{64} << 10));
      p.layer_name = layer.name;
      p.layer_library = parent(manifest) + "/" + layer.library;
    } catch (const std::exception& error) {
      p.layer_problem = error.what();
    }
  }
  return p;
}

const char* settings_name(Plan::Settings settings) {
  switch (settings) {
    case Plan::Settings::keep: return "keep";
    case Plan::Settings::migrate: return "migrate";
    case Plan::Settings::fresh: return "fresh";
  }
  return "keep";
}

Plan plan(const journal::Generation& generation, const config::Config& config, const Probe& probe) {
  Plan p;
  const journal::Package* package = carrier(generation);
  if (!package) {
    p.reason = "no deployed package carries ReShade";
    return p;
  }
  p.package = package->id;
  p.layer_manifest = package->payload + "/" + package->reshade->layer;
  p.layer_dir = parent(p.layer_manifest);
  if (config.reshade == config::Reshade::off) {
    p.reason = "remix.reshade is \"off\" in native-loader/config.json";
    return p;
  }
  if (config.reshade == config::Reshade::automatic && !probe.game_ini && !probe.own_ini) {
    p.reason = "remix.reshade is \"auto\", and neither the game has a ReShade (bin/win64/ReShade.ini) nor RTX sessions have "
               "ReShade settings (native-loader/reshade/ReShade.ini); \"on\" enables it";
    return p;
  }
  if (probe.game_base_path) {
    p.reason = "bin/win64/ReShade.ini sets [INSTALL] BasePath, which ReShade prefers to native-loader/reshade: it would use "
               "and change the game's own ReShade settings";
    return p;
  }
  if (!probe.layer_problem.empty() || probe.layer_name.empty()) {
    p.reason = "the layer manifest " + p.layer_manifest + " cannot be used: " +
               (probe.layer_problem.empty() ? std::string("it names no layer") : probe.layer_problem);
    return p;
  }
  p.layer_name = probe.layer_name;
  p.library = probe.layer_library;
  p.settings = probe.own_ini ? Plan::Settings::keep : probe.game_ini ? Plan::Settings::migrate : Plan::Settings::fresh;
  p.enable = true;
  p.reason = "ReShade from " + package->id + " " + package->version + ", " +
             (p.settings == Plan::Settings::keep      ? "with its settings in native-loader/reshade"
              : p.settings == Plan::Settings::migrate ? "with settings taken from bin/win64/ReShade.ini"
                                                      : "with new settings");
  return p;
}

Migration migrate(std::string_view game_ini, const Path& game_folder) {
  std::vector<Line> lines = parse_ini(game_ini);
  PresetNames names(game_folder);
  Migration m;
  m.preset_folder = game_folder;
  const auto preset_value = [&](std::string_view value, bool current) -> std::string {
    if (value.empty() || value.find('%') != std::string_view::npos) return std::string(value);  // as written
    const Path source = resolved(value, game_folder);
    if (current) m.preset_folder = source.parent_path();
    return ".\\" + backslashes(names.name(source));
  };
  const auto new_value = [&](const KeyRule& rule, std::string_view value) -> std::string {
    switch (rule.kind) {
      case KeyKind::path: return absolute_value(value, game_folder);
      case KeyKind::paths: {
        auto items = split_list(value);
        for (auto& item : items) item = absolute_value(item, game_folder);
        return join_list(items);
      }
      case KeyKind::preset: return preset_value(value, rule.key == "PresetPath");
      case KeyKind::presets: {
        auto items = split_list(value);
        for (auto& item : items) item = preset_value(item, false);
        return join_list(items);
      }
    }
    return std::string(value);
  };
  std::vector<const KeyRule*> seen;
  for (Line& line : lines) {
    const KeyRule* rule = line.key.empty() ? nullptr : rule_for(line);
    if (!rule) continue;
    seen.push_back(rule);
    const std::string value = new_value(*rule, line.value);
    if (value != line.value) line.text = line.key + "=" + value;
  }
  // Keys left out resolve against the base folder by default: write them out for the game's folder.
  for (const KeyRule& rule : kRules) {
    if (rule.fallback.empty() || std::find(seen.begin(), seen.end(), &rule) != seen.end()) continue;
    Line added;
    added.section = std::string(rule.section);
    added.key = std::string(rule.key);
    added.value = new_value(rule, rule.fallback);
    added.text = added.key + "=" + added.value;
    // After the section's last line (a blank line ends it), or in a new section at the end.
    auto last = lines.end();
    for (auto it = lines.begin(); it != lines.end(); ++it) {
      if (same(it->section, rule.section) && !trim(it->text).empty()) last = it;
    }
    if (last != lines.end()) {
      lines.insert(std::next(last), std::move(added));
    } else {
      if (!lines.empty() && !trim(lines.back().text).empty()) lines.push_back(Line{});
      Line header;
      header.text = "[" + std::string(rule.section) + "]";
      header.section = std::string(rule.section);
      lines.push_back(std::move(header));
      lines.push_back(std::move(added));
    }
  }
  m.ini = text_of(lines);
  m.presets = names.presets();
  return m;
}

std::string fresh(const Path& game_folder) {
  Path screenshots = game_folder.lexically_normal();
  screenshots.make_preferred();
  return "[GENERAL]\r\n"
         "EffectSearchPaths=.\\reshade-shaders\\Shaders\\**\r\n"
         "TextureSearchPaths=.\\reshade-shaders\\Textures\\**\r\n"
         "PresetPath=.\\ReShadePreset.ini\r\n"
         "\r\n"
         "[SCREENSHOT]\r\n"
         "SavePath=" + fs::utf8(screenshots) + "\\\r\n";
}

bool is_preset(std::string_view text) {
  for (const Line& line : parse_ini(text)) {
    if (!line.section.empty()) return false;
    if (line.key == "Techniques") return true;
  }
  return false;
}

Prepared prepare(const Path& root, Plan::Settings settings) {
  Prepared out;
  fs::refuse_links(root, kFolder);
  const Path folder = fs::join(root, kFolder);
  if (!fs::stat(folder).exists) fs::win32().create_directory(folder);
  const Path ini = fs::join(folder, kIni);
  if (settings == Plan::Settings::keep || fs::stat(ini).exists) {
    out.settings = "kept";
    return out;
  }
  Path game_folder = std::filesystem::absolute(fs::join(root, kGameFolder)).lexically_normal();
  game_folder.make_preferred();
  if (settings == Plan::Settings::fresh) {
    fs::write_atomic(fs::win32(), ini, fresh(game_folder));
    out.settings = "fresh";
    return out;
  }
  Migration m = migrate(fs::read_file(fs::join(game_folder, kIni), kMaxIni), game_folder);
  // The other presets in the current preset's folder, for ReShade's preset list.
  PresetNames names(game_folder);
  for (const auto& preset : m.presets) names.name(preset.source);
  try {
    std::size_t found = 0;
    for (const fs::Item& item : fs::list(m.preset_folder)) {
      if (item.directory || item.link || found >= kMaxSiblings) continue;
      const Path file = m.preset_folder / item.name;
      const std::string extension = folded(fs::utf8(file.extension()));
      if ((extension != ".ini" && extension != ".txt") || same(fs::utf8(file.filename()), kIni)) continue;
      const fs::Stat info = fs::stat(file);
      if (info.size > kMaxIni || !is_preset(fs::read_file(file, kMaxIni))) continue;
      names.name(file);
      ++found;
    }
  } catch (const fs::Error& error) {
    out.notes.push_back(std::string("other presets not copied: ") + error.what());
  }
  for (const auto& preset : names.presets()) {
    const std::string relative = std::string(kFolder) + "/" + preset.name;
    fs::refuse_links(root, relative);
    const Path target = fs::join(root, relative);
    if (fs::stat(target).exists) {
      out.notes.push_back(preset.name + " is already in native-loader/reshade and was kept");
      continue;
    }
    const fs::Stat source = fs::stat(preset.source);
    if (!source.exists || source.directory || source.link) continue;  // ReShade makes it when it saves the preset
    const std::string bytes = fs::read_file(preset.source, kMaxIni);
    // A preset below the game's folder keeps its subfolder ("presets/a.ini"): make the folders missing.
    std::vector<Path> missing;
    for (Path at = target.parent_path(); at != folder && at.has_relative_path() && !fs::stat(at).exists; at = at.parent_path()) {
      missing.push_back(at);
    }
    for (auto it = missing.rbegin(); it != missing.rend(); ++it) fs::win32().create_directory(*it);
    fs::write_atomic(fs::win32(), target, bytes);
    out.presets.push_back(preset.name);
  }
  fs::write_atomic(fs::win32(), ini, m.ini);
  out.settings = "migrated";
  return out;
}

}  // namespace nl::reshade
