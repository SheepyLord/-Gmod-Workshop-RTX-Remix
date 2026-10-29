#include "nl/config.h"
#include "nl/fs.h"
#include "nl/journal.h"
#include "nl/manifest.h"
#include "nl/reshade.h"
#include "nl_test.h"

#include <filesystem>
#include <fstream>
#include <sstream>
#include <stdexcept>
#include <string>

namespace sfs = std::filesystem;

namespace {

const std::string kSha(64, 'a');
const char* kLayer = R"({"file_format_version": "1.0.0", "layer": {"name": "VK_LAYER_nativeloader_reshade", "type": "GLOBAL",
  "library_path": ".\\ReShade64.dll", "api_version": "1.3.268", "implementation_version": "1", "description": "ReShade"}})";

void write(const sfs::path& path, const std::string& text) {
  sfs::create_directories(path.parent_path());
  std::ofstream(path, std::ios::binary) << text;
}

std::string read(const sfs::path& path) {
  std::ifstream in(path, std::ios::binary);
  std::ostringstream out;
  out << in.rdbuf();
  return out.str();
}

bool has_line(const std::string& text, const std::string& line) {
  return ("\r\n" + text).find("\r\n" + line + "\r\n") != std::string::npos;
}

// A generation whose package carries ReShade beside the runtime, as the combined RTX package does.
nl::journal::Generation generation() {
  nl::journal::Package p;
  p.id = "gmod-rtx-remix";
  p.version = "1.0.0";
  p.manifest_sha256 = kSha;
  p.source = "workshop";
  p.location = "x.gma";
  p.payload = "native-loader/packages/gmod-rtx-remix/1.0.0_3";
  p.reshade = nl::manifest::Reshade{"reshade/VkLayer_nativeloader_reshade.json"};
  nl::journal::Generation g;
  g.number = 3;
  g.packages.push_back(p);
  return g;
}

nl::reshade::Probe usable(bool game_ini, bool own_ini) {
  nl::reshade::Probe probe;
  probe.game_ini = game_ini;
  probe.own_ini = own_ini;
  probe.layer_name = "VK_LAYER_nativeloader_reshade";
  probe.layer_library = "native-loader/packages/gmod-rtx-remix/1.0.0_3/reshade/ReShade64.dll";
  return probe;
}

nl::config::Config mode(nl::config::Reshade reshade) {
  nl::config::Config c;
  c.reshade = reshade;
  return c;
}

}  // namespace

TEST_CASE("reshade: the layer manifest names a VK_LAYER_ and a .dll beside it") {
  const auto layer = nl::reshade::parse_layer(kLayer);
  CHECK(layer.name == "VK_LAYER_nativeloader_reshade");
  CHECK(layer.library == "ReShade64.dll");
  CHECK(nl::reshade::parse_layer(R"({"layer": {"name": "VK_LAYER_x", "library_path": "a.DLL"}})").library == "a.DLL");
  for (const char* bad : {R"({"layer": {"name": "reshade", "library_path": "ReShade64.dll"}})",
                          R"({"layer": {"name": "VK_LAYER_", "library_path": "ReShade64.dll"}})",
                          R"({"layer": {"name": "VK_LAYER_a-b", "library_path": "ReShade64.dll"}})",
                          R"({"layer": {"name": "VK_LAYER_x", "library_path": "..\\ReShade64.dll"}})",
                          R"({"layer": {"name": "VK_LAYER_x", "library_path": "C:\\Windows\\a.dll"}})",
                          R"({"layer": {"name": "VK_LAYER_x", "library_path": "sub/a.dll"}})",
                          R"({"layer": {"name": "VK_LAYER_x", "library_path": "ReShade64.exe"}})",
                          R"({"layer": {"name": "VK_LAYER_x"}})", R"({"name": "VK_LAYER_x"})", "not json"}) {
    bool threw = false;
    try {
      nl::reshade::parse_layer(bad);
    } catch (const std::exception&) {
      threw = true;
    }
    if (!threw) nl::test::fail(bad, __FILE__, __LINE__);
  }
}

TEST_CASE("reshade: the plan follows remix.reshade, the game's ReShade and the RTX sessions' own settings") {
  using nl::config::Reshade;
  using Settings = nl::reshade::Plan::Settings;
  const auto g = generation();

  // auto: only with a ReShade for the game, or settings from an earlier RTX session.
  auto p = nl::reshade::plan(g, mode(Reshade::automatic), usable(false, false));
  CHECK(!p.enable);
  CHECK(p.reason.find("\"auto\"") != std::string::npos);
  p = nl::reshade::plan(g, mode(Reshade::automatic), usable(true, false));
  CHECK(p.enable);
  CHECK(p.settings == Settings::migrate);
  CHECK(p.layer_name == "VK_LAYER_nativeloader_reshade");
  CHECK(p.layer_manifest == "native-loader/packages/gmod-rtx-remix/1.0.0_3/reshade/VkLayer_nativeloader_reshade.json");
  CHECK(p.layer_dir == "native-loader/packages/gmod-rtx-remix/1.0.0_3/reshade");
  CHECK(p.library == "native-loader/packages/gmod-rtx-remix/1.0.0_3/reshade/ReShade64.dll");
  CHECK(p.package == "gmod-rtx-remix");
  p = nl::reshade::plan(g, mode(Reshade::automatic), usable(true, true));
  CHECK(p.enable && p.settings == Settings::keep);  // settings once made are the RTX sessions' own
  p = nl::reshade::plan(g, mode(Reshade::automatic), usable(false, true));
  CHECK(p.enable && p.settings == Settings::keep);

  // on: always, with new settings when there are none to take; off: never.
  p = nl::reshade::plan(g, mode(Reshade::on), usable(false, false));
  CHECK(p.enable && p.settings == Settings::fresh);
  p = nl::reshade::plan(g, mode(Reshade::off), usable(true, true));
  CHECK(!p.enable);
  CHECK(p.reason.find("\"off\"") != std::string::npos);

  // [INSTALL] BasePath beats the loader's folder in ReShade, so the game's own settings would change.
  auto probe = usable(true, true);
  probe.game_base_path = true;
  p = nl::reshade::plan(g, mode(Reshade::on), probe);
  CHECK(!p.enable);
  CHECK(p.reason.find("BasePath") != std::string::npos);

  probe = usable(true, false);
  probe.layer_problem = "layer.name and layer.library_path must be strings";
  p = nl::reshade::plan(g, mode(Reshade::on), probe);
  CHECK(!p.enable);
  CHECK(p.reason.find("cannot be used") != std::string::npos);

  // No package carries it, or its package has no payload.
  CHECK(!nl::reshade::plan(nl::journal::Generation{}, mode(Reshade::on), usable(true, true)).enable);
  auto bare = g;
  bare.packages[0].payload.clear();
  CHECK(nl::reshade::carrier(bare) == nullptr);
  CHECK(!nl::reshade::plan(bare, mode(Reshade::on), usable(true, true)).enable);
}

TEST_CASE("reshade: migration makes the game's paths absolute and points presets to copies") {
  const sfs::path game = "H:\\Games\\GarrysMod\\bin\\win64";
  // What ReShade's setup writes for a Direct3D 9 install: relative paths, few keys.
  const std::string setup =
      "[GENERAL]\r\n"
      "EffectSearchPaths=.\\reshade-shaders\\Shaders\\**\r\n"
      "TextureSearchPaths=.\\reshade-shaders\\Textures\\**,D:\\Shared\\Textures\r\n"
      "PresetPath=.\\ReShadePreset.ini\r\n"
      "PreprocessorDefinitions=RESHADE_DEPTH_INPUT_IS_REVERSED=0,RESHADE_DEPTH_INPUT_IS_LOGARITHMIC=0\r\n"
      "\r\n"
      "[INPUT]\r\n"
      "KeyOverlay=36,0,0,0\r\n";
  const auto m = nl::reshade::migrate(setup, game);
  CHECK(has_line(m.ini, "EffectSearchPaths=H:\\Games\\GarrysMod\\bin\\win64\\reshade-shaders\\Shaders\\**"));
  CHECK(has_line(m.ini, "TextureSearchPaths=H:\\Games\\GarrysMod\\bin\\win64\\reshade-shaders\\Textures\\**,D:\\Shared\\Textures"));
  CHECK(has_line(m.ini, "PresetPath=.\\ReShadePreset.ini"));
  CHECK(has_line(m.ini, "PreprocessorDefinitions=RESHADE_DEPTH_INPUT_IS_REVERSED=0,RESHADE_DEPTH_INPUT_IS_LOGARITHMIC=0"));
  CHECK(has_line(m.ini, "KeyOverlay=36,0,0,0"));
  // Keys whose default is the base folder are written out for the game's folder: screenshots land where they did.
  CHECK(has_line(m.ini, "[SCREENSHOT]"));
  CHECK(has_line(m.ini, "SavePath=H:\\Games\\GarrysMod\\bin\\win64\\"));
  CHECK(has_line(m.ini, "PostSaveCommandWorkingDirectory=H:\\Games\\GarrysMod\\bin\\win64\\"));
  CHECK(m.ini.find("IntermediateCachePath") == std::string::npos);  // ReShade's default is the temporary folder
  REQUIRE(m.presets.size() == 1);
  CHECK(m.presets[0].source == sfs::path("H:\\Games\\GarrysMod\\bin\\win64\\ReShadePreset.ini"));
  CHECK(m.presets[0].name == "ReShadePreset.ini");
  CHECK(m.preset_folder == game);
  // The [INPUT] section comes after the added keys' [GENERAL] lines, as it did.
  CHECK(m.ini.find("[GENERAL]") < m.ini.find("[INPUT]"));
}

TEST_CASE("reshade: migration of a full ReShade.ini keeps what it does not change, and names presets apart") {
  const sfs::path game = "C:\\G\\bin\\win64";
  const std::string saved =
      "[GENERAL]\n"
      "EffectSearchPaths=.\\reshade-shaders\\Shaders\\**,%USERPROFILE%\\fx\n"
      "IntermediateCachePath=C:\\Users\\me\\AppData\\Local\\Temp\\ReShade\n"
      "PresetPath=.\\presets\\Main.ini\n"
      "PresetShortcutKeys=112,0,0,0,113,0,0,0\n"
      "PresetShortcutPaths=.\\presets\\Night.ini,D:\\Elsewhere\\Main.ini\n"
      "StartupPresetPath=\n"
      "TextureSearchPaths=.\\reshade-shaders\\Textures\\**\n"
      "\n"
      "[OVERLAY]\n"
      "Window=[Window][Debug##Default],Pos=60,,60,Size=400,,400,Collapsed=0\n"
      "\n"
      "[SCREENSHOT]\n"
      "PostSaveCommand=magick.exe\n"
      "PostSaveCommandWorkingDirectory=.\\\n"
      "SavePath=.\\shots\n"
      "SoundPath=\n"
      "\n"
      "[STYLE]\n"
      "Font=fonts\\a.ttf\n"
      "LatinFont=\n";
  const auto m = nl::reshade::migrate(saved, game);
  CHECK(has_line(m.ini, "EffectSearchPaths=C:\\G\\bin\\win64\\reshade-shaders\\Shaders\\**,%USERPROFILE%\\fx"));
  CHECK(has_line(m.ini, "IntermediateCachePath=C:\\Users\\me\\AppData\\Local\\Temp\\ReShade"));
  CHECK(has_line(m.ini, "PresetPath=.\\presets\\Main.ini"));
  CHECK(has_line(m.ini, "PresetShortcutKeys=112,0,0,0,113,0,0,0"));
  // The second Main.ini is another file: it gets a name of its own.
  CHECK(has_line(m.ini, "PresetShortcutPaths=.\\presets\\Night.ini,.\\Main.ini"));
  CHECK(has_line(m.ini, "StartupPresetPath="));
  CHECK(has_line(m.ini, "Window=[Window][Debug##Default],Pos=60,,60,Size=400,,400,Collapsed=0"));
  CHECK(has_line(m.ini, "PostSaveCommand=magick.exe"));  // a command, not resolved against the folder
  CHECK(has_line(m.ini, "PostSaveCommandWorkingDirectory=C:\\G\\bin\\win64\\"));
  CHECK(has_line(m.ini, "SavePath=C:\\G\\bin\\win64\\shots"));
  CHECK(has_line(m.ini, "SoundPath="));
  CHECK(has_line(m.ini, "Font=C:\\G\\bin\\win64\\fonts\\a.ttf"));
  CHECK(has_line(m.ini, "LatinFont="));
  REQUIRE(m.presets.size() == 3);
  CHECK(m.presets[0].name == "presets/Main.ini");
  CHECK(m.presets[1].name == "presets/Night.ini");
  CHECK(m.presets[2].name == "Main.ini");
  CHECK(m.presets[2].source == sfs::path("D:\\Elsewhere\\Main.ini"));
  CHECK(m.preset_folder == sfs::path("C:\\G\\bin\\win64\\presets"));
  CHECK(m.ini.find("\r\n") != std::string::npos);  // ReShade's own line breaks

  // Two outside presets with one file name: the second gets " (2)" before the extension.
  const auto twice = nl::reshade::migrate("[GENERAL]\nPresetPath=D:\\a\\P.ini\nPresetShortcutPaths=E:\\b\\P.ini\n", game);
  CHECK(has_line(twice.ini, "PresetShortcutPaths=.\\P (2).ini"));
}

TEST_CASE("reshade: what counts as a preset") {
  CHECK(nl::reshade::is_preset("Techniques=A@A.fx\r\nTechniqueSorting=A@A.fx\r\n\r\n[A.fx]\r\nStrength=1\r\n"));
  CHECK(nl::reshade::is_preset("\xEF\xBB\xBFKeyFoo=1\nTechniques=\n"));
  CHECK(!nl::reshade::is_preset("[GENERAL]\nTechniques=A@A.fx\n"));  // inside a section: a ReShade.ini, not a preset
  CHECK(!nl::reshade::is_preset("readme text\n"));
}

TEST_CASE("reshade: prepare copies the settings once and never writes the game's ReShade") {
  const auto root = nl::test::scratch_dir("reshade_prepare");
  const auto game = root / "bin" / "win64";
  const std::string ini = "[GENERAL]\r\nEffectSearchPaths=.\\reshade-shaders\\Shaders\\**\r\nPresetPath=.\\ReShadePreset.ini\r\n";
  write(game / "ReShade.ini", ini);
  write(game / "ReShadePreset.ini", "Techniques=NLCheck@NLCheck.fx\r\n");
  write(game / "Other.ini", "Techniques=NLHeavy@NLHeavy.fx\r\n");
  write(game / "notes.txt", "not a preset\r\n");
  write(game / "d3d9.dll", "the Direct3D 9 ReShade");
  sfs::create_directories(root / "native-loader");

  const auto probe = nl::reshade::probe(root, generation());
  CHECK(probe.game_ini && !probe.own_ini && !probe.game_base_path);
  CHECK(!probe.layer_problem.empty());  // the generation's payload is not on disk here

  const auto first = nl::reshade::prepare(root, nl::reshade::Plan::Settings::migrate);
  CHECK(first.settings == "migrated");
  const auto folder = root / "native-loader" / "reshade";
  const std::string made = read(folder / "ReShade.ini");
  const auto absolute_game = sfs::absolute(game).lexically_normal().make_preferred();
  CHECK(has_line(made, "EffectSearchPaths=" + nl::fs::utf8(absolute_game) + "\\reshade-shaders\\Shaders\\**"));
  CHECK(has_line(made, "PresetPath=.\\ReShadePreset.ini"));
  CHECK(read(folder / "ReShadePreset.ini") == "Techniques=NLCheck@NLCheck.fx\r\n");
  CHECK(read(folder / "Other.ini") == "Techniques=NLHeavy@NLHeavy.fx\r\n");  // the preset list has the others too
  CHECK(!sfs::exists(folder / "notes.txt"));
  CHECK(first.presets.size() == 2);
  // The game's files are as they were.
  CHECK(read(game / "ReShade.ini") == ini);
  CHECK(read(game / "ReShadePreset.ini") == "Techniques=NLCheck@NLCheck.fx\r\n");
  CHECK(read(game / "d3d9.dll") == "the Direct3D 9 ReShade");

  // Later starts keep what RTX sessions changed.
  write(folder / "ReShadePreset.ini", "Techniques=\r\n");
  CHECK(nl::reshade::probe(root, generation()).own_ini);
  CHECK(nl::reshade::prepare(root, nl::reshade::Plan::Settings::keep).settings == "kept");
  CHECK(nl::reshade::prepare(root, nl::reshade::Plan::Settings::migrate).settings == "kept");  // ReShade.ini is there
  CHECK(read(folder / "ReShadePreset.ini") == "Techniques=\r\n");

  // Without ReShade.ini the settings are taken again; a preset already in the folder is kept.
  sfs::remove(folder / "ReShade.ini");
  const auto again = nl::reshade::prepare(root, nl::reshade::Plan::Settings::migrate);
  CHECK(again.settings == "migrated");
  CHECK(read(folder / "ReShadePreset.ini") == "Techniques=\r\n");
  CHECK(!again.notes.empty());

  // [INSTALL] BasePath is found.
  write(game / "ReShade.ini", ini + "\r\n[INSTALL]\r\nBasePath=..\\..\\reshade\r\n");
  CHECK(nl::reshade::probe(root, generation()).game_base_path);
  sfs::remove_all(root);
}

TEST_CASE("reshade: fresh settings and the layer the probe reads") {
  const auto root = nl::test::scratch_dir("reshade_fresh");
  sfs::create_directories(root / "native-loader");
  const auto g = generation();
  write(root / sfs::path(g.packages[0].payload) / "reshade" / "VkLayer_nativeloader_reshade.json", kLayer);
  const auto probe = nl::reshade::probe(root, g);
  CHECK(probe.layer_problem.empty());
  CHECK(probe.layer_name == "VK_LAYER_nativeloader_reshade");
  CHECK(probe.layer_library == g.packages[0].payload + "/reshade/ReShade64.dll");
  CHECK(!probe.game_ini && !probe.own_ini);

  CHECK(nl::reshade::prepare(root, nl::reshade::Plan::Settings::fresh).settings == "fresh");
  const std::string made = read(root / "native-loader" / "reshade" / "ReShade.ini");
  CHECK(has_line(made, "EffectSearchPaths=.\\reshade-shaders\\Shaders\\**"));
  CHECK(has_line(made, "SavePath=" + nl::fs::utf8(sfs::absolute(root / "bin" / "win64").lexically_normal().make_preferred()) + "\\"));
  CHECK(!sfs::exists(root / "bin"));  // nothing written outside native-loader/reshade
  sfs::remove_all(root);
}

TEST_CASE("reshade: the manifest section, its kind and the journal record") {
  const auto with = [](const std::string& kinds, const std::string& reshade) {
    return "{\"schema\": 1, \"id\": \"shade\", \"version\": \"6.8.0\", \"kinds\": [" + kinds +
           "], \"files\": {\"native/payload/reshade/VkLayer_nativeloader_reshade.json\": {\"size\": 1, \"sha256\": \"" + kSha +
           "\"}, \"native/payload/reshade/ReShade64.dll\": {\"size\": 1, \"sha256\": \"" + kSha + "\"}}" + reshade + "}";
  };
  const auto m = nl::manifest::parse(with("\"reshade\"", ", \"reshade\": {\"layer\": \"reshade/VkLayer_nativeloader_reshade.json\"}"));
  REQUIRE(m.reshade.has_value());
  CHECK(m.reshade->layer == "reshade/VkLayer_nativeloader_reshade.json");
  CHECK(m.has(nl::manifest::Kind::reshade));
  CHECK(std::string(nl::manifest::kind_name(nl::manifest::Kind::reshade)) == "reshade");
  for (const auto& bad : {with("\"reshade\"", ""),  // the kind needs the section
                          with("\"root-files\"", ", \"reshade\": {\"layer\": \"reshade/VkLayer_nativeloader_reshade.json\"}"),
                          with("\"reshade\"", ", \"reshade\": {\"layer\": \"reshade/ReShade64.dll\"}"),
                          with("\"reshade\"", ", \"reshade\": {\"layer\": \"reshade/missing.json\"}"),
                          with("\"reshade\"", ", \"reshade\": {\"layer\": \"../x.json\"}"),
                          with("\"reshade\"", ", \"reshade\": {\"layer\": \"reshade/VkLayer_nativeloader_reshade.json\", \"x\": 1}")}) {
    bool threw = false;
    try {
      nl::manifest::parse(bad);
    } catch (const nl::manifest::Error&) {
      threw = true;
    }
    if (!threw) nl::test::fail(bad.c_str(), __FILE__, __LINE__);
  }

  nl::journal::Journal j;
  j.loader = "0.5.0";
  j.next = 4;
  j.current = generation();
  const std::string text = nl::journal::serialize(j);
  CHECK(text.find("\"reshade\": {\"layer\": \"reshade/VkLayer_nativeloader_reshade.json\"}") != std::string::npos);
  const auto back = nl::journal::parse(text);
  REQUIRE(back.current && back.current->packages[0].reshade);
  CHECK(back.current->packages[0].reshade->layer == "reshade/VkLayer_nativeloader_reshade.json");
  CHECK(nl::journal::serialize(back) == text);
  j.current->packages[0].reshade.reset();
  CHECK(nl::journal::serialize(j).find("reshade") == std::string::npos);  // only written when there is one
}

TEST_CASE("reshade: remix.reshade in config.json") {
  CHECK(nl::config::parse(R"({"schema": 1})").reshade == nl::config::Reshade::automatic);
  CHECK(nl::config::parse(R"({"schema": 1, "remix": {"reshade": "auto"}})").reshade == nl::config::Reshade::automatic);
  CHECK(nl::config::parse(R"({"schema": 1, "remix": {"reshade": "on"}})").reshade == nl::config::Reshade::on);
  CHECK(nl::config::parse(R"({"schema": 1, "remix": {"reshade": "off", "enabled": true}})").reshade == nl::config::Reshade::off);
  for (const char* bad : {R"({"schema": 1, "remix": {"reshade": true}})", R"({"schema": 1, "remix": {"reshade": "yes"}})",
                          R"({"schema": 1, "remix": {"reshade": "ON"}})"}) {
    bool threw = false;
    try {
      nl::config::parse(bad);
    } catch (const nl::config::Error&) {
      threw = true;
    }
    if (!threw) nl::test::fail(bad, __FILE__, __LINE__);
  }
}
