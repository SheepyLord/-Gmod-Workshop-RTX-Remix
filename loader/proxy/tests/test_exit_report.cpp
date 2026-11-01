#include "exit_report.h"
#include "nl_test.h"
#include <array>

namespace r = nl::proxy::exit_report;
TEST_CASE("exit report: automation quiet is explicit and does not imply consent") {
  CHECK(r::quiet("quiet")); CHECK(r::quiet("QUIET"));
  CHECK(!r::quiet("")); CHECK(!r::quiet("1")); CHECK(!r::quiet("off")); CHECK(!r::quiet("quiet "));
}
TEST_CASE("exit report: game language overrides Windows and aliases follow the seven catalogs") {
  CHECK(r::language("gmod_language \"zh-cn\"\n", {}, "en-US") == "zh-CN");
  CHECK(r::language("gmod_language \"fr\"\n", "ja", "ru-RU") == "ja");
  CHECK(r::language({}, {}, "zh-Hant-TW") == "zh-TW");
  CHECK(r::language({}, {}, "ko-KR") == "ko");
  CHECK(r::language("gmod_language \"de\"\n", {}, "fr-FR") == "en");
  CHECK(r::language({}, "schinese", {}) == "zh-CN");
  CHECK(r::language({}, "tchinese", {}) == "zh-TW");
  CHECK(r::command_language(L"gmod.exe +gmod_language zh-cn +map gm_construct") == "zh-cn");
  CHECK(r::command_language(L"gmod.exe +gmod_language ru +gmod_language fr") == "fr");
  CHECK(r::command_language(L"gmod.exe +gmod_language").empty());
}
TEST_CASE("exit report: every reason has localized advice, evidence and exception codes") {
  const auto root = std::filesystem::absolute("scratch");
  constexpr std::array reasons{"out_of_memory", "likely_out_of_memory", "device_lost", "allocation_failed", "cs_exception", "crash"};
  for (const auto language : {"en", "zh-CN", "zh-TW", "ja", "ko", "fr", "ru"}) {
    CHECK(!r::title(language).empty());
    if (std::string_view(language) != "en") CHECK(r::title(language) != r::title("en"));
    for (const auto reason : reasons) {
      const nl::evidence::PreviousSession previous{reason, {}, "native-loader/logs/sessions/test"};
      const auto text = r::message(previous, 0xC0000005u, root, language);
      CHECK(text.size() > 100); CHECK(text.find("0xC0000005") != text.npos);
      CHECK(text.find("sessions") != text.npos); CHECK(text.find("{count}") == text.npos);
      for (const auto code : {0xC0000409u, 0xC00000FDu, 0xE06D7363u})
        CHECK(!r::message(previous, code, root, language).empty());
    }
    CHECK(r::message({"crash", {}, {}}, 123, root, language).find("0x0000007B") != std::string::npos);
  }
}
