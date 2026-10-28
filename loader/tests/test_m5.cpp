// M5: RTX-session extras. Patterns and patches (nl::patch), session console variables (nl::session),
// and the manifest/journal fields that carry them.
#include "nl/activate.h"
#include "nl/journal.h"
#include "nl/manifest.h"
#include "nl/patch.h"
#include "nl/session.h"
#include "nl_test.h"

#include <windows.h>

#include <cstring>
#include <string>
#include <vector>

namespace {

const std::string kSha(64, 'a');

std::string fixes_manifest(const std::string& extra = {}) {
  return R"({
  "schema": 1, "id": "rtx-fixes", "version": "1.0.0",
  "kinds": ["lua-addon", "lua-binary-module", "root-files", "patch-set", "module-override"],
  "files": {
    "native/payload/shaders/stdshader_dx6.dll": {"size": 4, "sha256": ")" + kSha + R"("},
    "native/root/garrysmod/addons/remixbinary/lua/autorun/cl_rtx.lua": {"size": 2, "sha256": ")" + kSha + R"("},
    "native/root/garrysmod/lua/bin/gmcl_RTXFixesBinary_win64.dll": {"size": 3, "sha256": ")" + kSha + R"("},
    "native/root/rtx-remix/mods/base_mod/mod.usda": {"size": 3, "sha256": ")" + kSha + R"("}
  },
  "root_files": [
    {"path": "garrysmod/addons/remixbinary"},
    {"path": "garrysmod/lua/bin/gmcl_RTXFixesBinary_win64.dll"},
    {"path": "rtx-remix/mods/base_mod"}
  ],
  "patch_sets": [{"module": "engine.dll", "patches": [
    {"name": "hdr_lighting", "find": "ff90????????85c0742b", "offset": 0, "replace": "b80200000090"}]}],
  "module_overrides": [{"module": "stdshader_dx6.dll", "file": "native/payload/shaders/stdshader_dx6.dll"}],
  "session_cvars": {"r_3dsky": "0", "mat_softwareskin": "1"})" + extra + R"(
})";
}

std::string replaced(std::string text, const std::string& from, const std::string& to) {
  const auto at = text.find(from);
  if (at == std::string::npos) throw std::logic_error("test bug: missing " + from);
  return text.replace(at, from.size(), to);
}

}  // namespace

TEST_CASE("m5: a fixes manifest with add-ons, patch sets, an override and session variables parses") {
  const auto m = nl::manifest::parse(fixes_manifest());
  CHECK(m.has(nl::manifest::Kind::lua_addon));
  REQUIRE(m.root_files.size() == 3);
  CHECK(m.root_files[0].area == nl::paths::RootArea::lua_addons);
  REQUIRE(m.session.patch_sets.size() == 1);
  CHECK(m.session.patch_sets[0].module == "engine.dll");
  CHECK(m.session.patch_sets[0].patches[0].replace == "b80200000090");
  REQUIRE(m.session.module_overrides.size() == 1);
  CHECK(m.session.module_overrides[0].file == "shaders/stdshader_dx6.dll");
  CHECK(m.session.cvars == nl::session::Values({{"r_3dsky", "0"}, {"mat_softwareskin", "1"}}));
}

TEST_CASE("m5: the manifest refuses unsafe or inconsistent session extras") {
  const std::vector<std::pair<std::string, std::string>> bad = {
      {R"("module": "engine.dll")", R"("module": "Engine.dll")"},                           // not lowercase
      {R"("find": "ff90????????85c0742b")", R"("find": "????")"},                           // only wildcards
      {R"("find": "ff90????????85c0742b")", R"("find": "FF90")"},                           // upper-case hex
      {R"("offset": 0, "replace": "b80200000090")", R"("offset": 6, "replace": "b80200000090")"},  // past the match
      {R"("replace": "b80200000090")", R"("replace": "zz")"},
      {R"("name": "hdr_lighting")", R"("name": "HDR lighting")"},
      {R"("file": "native/payload/shaders/stdshader_dx6.dll")", R"("file": "native/root/rtx-remix/mods/base_mod/mod.usda")"},
      {R"("module": "stdshader_dx6.dll")", R"("module": "stdshader_dx7.dll")"},              // file name differs
      {R"("mat_softwareskin": "1")", R"("mat_softwareskin": "1; quit")"},                  // command smuggling
      {R"("mat_softwareskin": "1")", R"("bind x": "1")"},
      {R"({"path": "garrysmod/addons/remixbinary"})", R"({"path": "garrysmod/addons/remixbinary", "policy": "create-only"})"},
      {R"("kinds": ["lua-addon", )", R"("kinds": [)"},                                        // area needs its kind
      {R"(, "patch-set", "module-override"])", R"(])"},
  };
  for (const auto& [from, to] : bad) {
    CHECK_THROWS_AS(nl::manifest::parse(replaced(fixes_manifest(), from, to)), nl::manifest::Error);
  }
  CHECK_THROWS_AS(nl::manifest::parse(replaced(fixes_manifest(), R"({"path": "garrysmod/addons/remixbinary"})",
                                               R"({"path": "garrysmod/addons"})")), nl::manifest::Error);
  // -insecure is an allowed runtime launch argument from M5 on; +exec is still not.
  CHECK(nl::manifest::parse_pattern("ff??00") == std::vector<int>({0xff, -1, 0x00}));
  CHECK(nl::manifest::parse_hex("00ff") == std::vector<std::uint8_t>({0x00, 0xff}));
  CHECK(nl::manifest::parse_hex("0").empty());
}

TEST_CASE("m5: pattern search finds every match, anchored on the first concrete byte") {
  const std::uint8_t data[] = {0x10, 0xff, 0x90, 0x01, 0x02, 0x85, 0xff, 0x90, 0x07, 0x08, 0x85, 0x00};
  const auto pattern = nl::manifest::parse_pattern("ff90????85");
  CHECK(nl::patch::find(data, sizeof(data), pattern, 4) == std::vector<std::size_t>({1, 6}));
  CHECK(nl::patch::find(data, sizeof(data), pattern, 1) == std::vector<std::size_t>({1}));
  CHECK(nl::patch::find(data, sizeof(data), nl::manifest::parse_pattern("??ff90"), 4) == std::vector<std::size_t>({0, 5}));
  CHECK(nl::patch::find(data, 3, pattern, 4).empty());
  CHECK(nl::patch::find(data, sizeof(data), nl::manifest::parse_pattern("0885"), 4) == std::vector<std::size_t>({9}));
}

// The marker the next test patches: writable and volatile, so an optimising build keeps it as one
// array in .data and never folds a read of it (patching const data would be undefined behaviour).
extern "C" volatile char nl_m5_unit_marker[] = "NLM5-UNIT-ONCE:0000";

TEST_CASE("m5: a patch applies only to a pattern that occurs exactly once in the module") {
  // A loaded module of this process: this test executable.
  volatile char* once = nl_m5_unit_marker;
  void* base = GetModuleHandleW(nullptr);
  REQUIRE(!nl::patch::sections(base).empty());
  nl::manifest::Patch patch{"unit_once", "4e4c4d352d554e49542d4f4e43453a????????", 15, "31313131"};  // "NLM5-UNIT-ONCE:" + 4
  const auto applied = nl::patch::apply(base, "nl_tests.exe", patch);
  CHECK(applied.result == "applied");
  CHECK(once[15] == '1' && once[16] == '1' && once[17] == '1' && once[18] == '1');  // no second literal with the prefix
  const auto again = nl::patch::apply(base, "nl_tests.exe", patch);  // the pattern still matches: once
  CHECK(again.result == "applied");
  nl::manifest::Patch absent{"absent", "4e4c4d352d4e4f2d535543482d4d41524b4552", 0, "00"};  // "NLM5-NO-SUCH-MARKER"
  const auto skipped = nl::patch::apply(base, "nl_tests.exe", absent);
  CHECK(skipped.result == "skipped");
  CHECK(skipped.reason.find("does not occur") != std::string::npos);
  CHECK(nl::patch::sections(nullptr).empty());
}

TEST_CASE("m5: config.cfg values are read by name, quoted or not, binds ignored") {
  const auto values = nl::session::parse_config("// comment\r\nbind \"p\" \"say hi\"\r\nr_3dsky \"1\"\r\n  mat_softwareskin 0\r\nbroken \"x\r\n");
  CHECK(values.at("r_3dsky") == "1");
  CHECK(values.at("mat_softwareskin") == "0");
  CHECK(values.count("broken") == 0);
  CHECK(values.at("bind") == "p");  // harmless: no session variable is called bind
}

TEST_CASE("m5: session variables are recorded once, restored once, then forgotten") {
  const nl::session::Values cvars = {{"r_3dsky", "0"}, {"nl_new", "1"}};
  const std::map<std::string, std::string> config = {{"r_3dsky", "1"}};
  // First RTX session: the user's archived value is recorded (nl_new is not archived: nothing to restore).
  auto first = nl::session::plan(true, cvars, std::nullopt, config);
  CHECK(first.write_session);
  CHECK(first.exec_args == std::vector<std::string>({"+exec", "nativeloader_session.cfg"}));
  CHECK(first.record == nl::session::Values({{"r_3dsky", "1"}}));
  CHECK(first.record_session == nl::session::Values({{"r_3dsky", "0"}}));  // what the session sets
  // Later RTX session: config.cfg now holds the RTX value; the record keeps the user's.
  auto later = nl::session::plan(true, cvars, nl::session::Record{first.record, false}, {{"r_3dsky", "0"}});
  CHECK(later.record == first.record);
  // RTX off: restore once.
  auto off = nl::session::plan(false, {}, nl::session::Record{first.record, false}, {{"r_3dsky", "0"}});
  CHECK(off.write_restore);
  CHECK(off.restore == first.record);
  CHECK(off.exec_args == std::vector<std::string>({"+exec", "nativeloader_restore.cfg"}));
  // The next start: the restore has run; the record is dropped and nothing is added.
  auto next = nl::session::plan(false, {}, nl::session::Record{first.record, true}, {{"r_3dsky", "1"}});
  CHECK(next.drop_record);
  CHECK(next.record.empty());
  CHECK(next.exec_args.empty());
  // An RTX session after a restore ran records afresh.
  auto again = nl::session::plan(true, cvars, nl::session::Record{first.record, true}, {{"r_3dsky", "1"}});
  CHECK(again.drop_record && again.record == first.record && again.write_session);
}

TEST_CASE("m5: a restore keeps what the user changed after the RTX session (R1-004)") {
  const nl::session::Values cvars = {{"r_3dsky", "0"}, {"r_shadows", "0"}};
  const auto rtx = nl::session::plan(true, cvars, std::nullopt, {{"r_3dsky", "1"}, {"r_shadows", "1"}});
  CHECK(rtx.record_session == cvars);
  const nl::session::Record record{rtx.record, false, rtx.record_session};
  // The game archived the session's r_3dsky; the user has set r_shadows to 2 since: only r_3dsky goes back.
  const auto off = nl::session::plan(false, {}, record, {{"r_3dsky", "0"}, {"r_shadows", "2"}});
  CHECK(off.restore == nl::session::Values({{"r_3dsky", "1"}}));
  CHECK(off.record == record.values);
  CHECK(off.exec_args == std::vector<std::string>({"+exec", "nativeloader_restore.cfg"}));
  // Both are the user's own again: nothing to run, and the record is done with.
  const auto done = nl::session::plan(false, {}, record, {{"r_3dsky", "1"}, {"r_shadows", "2"}});
  CHECK(done.restore.empty() && done.exec_args.empty() && done.record.empty());
  // A schema 1 record holds no session values: the deployed packages' values stand in.
  const auto older = nl::session::plan(false, cvars, nl::session::Record{record.values, false}, {{"r_3dsky", "0"}, {"r_shadows", "2"}});
  CHECK(older.restore == nl::session::Values({{"r_3dsky", "1"}}));
}

TEST_CASE("m5: the session record round-trips and refuses what would break the generated cfg") {
  const nl::session::Record record{{{"r_3dsky", "1"}, {"name_with_space", "a b"}}, true, {{"r_3dsky", "0"}}};
  const auto back = nl::session::parse_record(nl::session::serialize(record));
  CHECK(back.values == record.values);
  CHECK(back.restore_issued);
  CHECK(back.session_values == record.session_values);
  CHECK(nl::session::parse_record(R"({"schema":1,"values":{"r_3dsky":"1"}})").session_values.empty());  // schema 1 still read
  CHECK_THROWS_AS(nl::session::parse_record(R"({"schema":1,"values":{"x":"a\"b"}})"), nl::session::Error);
  CHECK_THROWS_AS(nl::session::parse_record(R"({"schema":2,"session_values":{"x":"a\"b"}})"), nl::session::Error);
  CHECK_THROWS_AS(nl::session::parse_record(R"({"schema":3})"), nl::session::Error);
  CHECK_THROWS_AS(nl::session::parse_record(R"({"schema":1,"session_values":{}})"), nl::session::Error);
  CHECK_THROWS_AS(nl::session::parse_record(R"({"schema":1,"extra":1})"), nl::session::Error);
  const auto text = nl::session::cfg_text({{"r_3dsky", "0"}}, "RTX session");
  CHECK(text.rfind(std::string(nl::session::kHeader), 0) == 0);
  CHECK(text.find("r_3dsky \"0\"\n") != std::string::npos);
}

TEST_CASE("m5: the journal keeps each package's session extras; older journals have none") {
  nl::journal::Journal journal;
  journal.loader = "0.2.0";
  journal.next = 2;
  nl::journal::Package package;
  package.id = "rtx-fixes";
  package.version = "1.0.0";
  package.manifest_sha256 = kSha;
  package.source = "local";
  package.location = "C:/fixes.gma";
  package.payload = "native-loader/packages/rtx-fixes/1.0.0_1";
  package.session = nl::manifest::parse(fixes_manifest()).session;
  journal.current = nl::journal::Generation{1, {package}, {}};
  const auto back = nl::journal::parse(nl::journal::serialize(journal));
  REQUIRE(back.current);
  const auto& session = back.current->packages[0].session;
  CHECK(session.patch_sets.size() == 1 && session.patch_sets[0].patches[0].find == "ff90????????85c0742b");
  CHECK(session.module_overrides.size() == 1 && session.module_overrides[0].file == "shaders/stdshader_dx6.dll");
  CHECK(session.cvars.size() == 2);
  journal.current->packages[0].session = {};
  const auto plain = nl::journal::parse(nl::journal::serialize(journal));
  CHECK(plain.current->packages[0].session.empty());
}

TEST_CASE("m5: activation collects the extras of every deployed package, a runtime required") {
  nl::journal::Generation generation;
  nl::journal::Package runtime;
  runtime.id = "runtime";
  runtime.version = "1.0.0";
  runtime.payload = "native-loader/packages/runtime/1.0.0_1";
  runtime.remix = nl::manifest::Remix{};
  runtime.remix->entry = "runtime/d3d9.dll";
  nl::journal::Package fixes;
  fixes.id = "rtx-fixes";
  fixes.version = "1.0.0";
  fixes.payload = "native-loader/packages/rtx-fixes/1.0.0_1";
  fixes.session = nl::manifest::parse(fixes_manifest()).session;
  nl::config::Config config;
  const auto none = [](const std::string&) -> std::optional<std::string> { return std::nullopt; };
  generation.packages = {fixes};
  CHECK(!nl::activate::plan(generation, config, none, L"gmod.exe").activate);  // no runtime: nothing at all
  generation.packages = {runtime, fixes};
  const auto plan = nl::activate::plan(generation, config, none, L"gmod.exe");
  REQUIRE(plan.activate);
  CHECK(plan.patch_sets.size() == 1 && plan.patch_sets[0].package == "rtx-fixes");
  REQUIRE(plan.module_overrides.size() == 1);
  CHECK(plan.module_overrides[0].file == "native-loader/packages/rtx-fixes/1.0.0_1/shaders/stdshader_dx6.dll");
  CHECK(plan.session_cvars.size() == 2);
  config.remix_enabled = false;
  const auto off = nl::activate::plan(generation, config, none, L"gmod.exe");
  CHECK(!off.activate);
  CHECK(off.patch_sets.empty() && off.module_overrides.empty() && off.session_cvars.empty());
}

TEST_CASE("m5: requires_remix is an optional manifest flag, a boolean, false when absent") {
  CHECK(!nl::manifest::parse(fixes_manifest()).requires_remix);
  CHECK(nl::manifest::parse(fixes_manifest(R"(, "requires_remix": true)")).requires_remix);
  CHECK(!nl::manifest::parse(fixes_manifest(R"(, "requires_remix": false)")).requires_remix);
  CHECK_THROWS_AS(nl::manifest::parse(fixes_manifest(R"(, "requires_remix": "yes")")), nl::manifest::Error);
}

TEST_CASE("m5: the journal keeps requires_remix, written only when true") {
  nl::journal::Journal journal;
  journal.loader = "0.2.0";
  journal.next = 2;
  nl::journal::Package package;
  package.id = "rtx-fixes";
  package.version = "1.0.0";
  package.manifest_sha256 = kSha;
  package.source = "local";
  package.location = "C:/fixes.gma";
  package.requires_remix = true;
  journal.current = nl::journal::Generation{1, {package}, {}};
  const auto text = nl::journal::serialize(journal);
  CHECK(text.find("\"requires_remix\": true") != std::string::npos);
  CHECK(nl::journal::parse(text).current->packages[0].requires_remix);
  journal.current->packages[0].requires_remix = false;
  const auto plain = nl::journal::serialize(journal);
  CHECK(plain.find("requires_remix") == std::string::npos);
  CHECK(!nl::journal::parse(plain).current->packages[0].requires_remix);
}

TEST_CASE("m5: the add-on folders hidden without a runtime are those of requires_remix packages") {
  nl::journal::Generation generation;
  generation.number = 3;
  nl::journal::Package fixes;
  fixes.id = "rtx-fixes";
  fixes.requires_remix = true;
  nl::journal::Package other;
  other.id = "lua-tools";
  generation.packages = {fixes, other};
  const auto file = [](std::string path, std::string package) {
    nl::journal::File f;
    f.path = std::move(path);
    f.package = std::move(package);
    f.sha256 = kSha;
    return f;
  };
  generation.files = {file("garrysmod/addons/RemixBinary/lua/autorun/cl_rtx.lua", "rtx-fixes"),
                      file("garrysmod/addons/remixbinary/addon.json", "rtx-fixes"),
                      file("garrysmod/addons/rtx_water/lua/autorun/w.lua", "rtx-fixes"),
                      file("garrysmod/lua/bin/gmcl_RTXFixesBinary_win64.dll", "rtx-fixes"),
                      file("rtx-remix/mods/base_mod/mod.usda", "rtx-fixes"),
                      file("garrysmod/addons/tools/lua/autorun/t.lua", "lua-tools")};
  CHECK(nl::session::hidden_addons(generation) == std::vector<std::string>({"remixbinary", "rtx_water"}));
  generation.packages[0].requires_remix = false;
  CHECK(nl::session::hidden_addons(generation).empty());
}
