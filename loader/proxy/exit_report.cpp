#include "exit_report.h"
#include "presentation_data.h"
#include "nl/cmdline.h"
#include "nl/fs.h"
#include "nl/json.h"
#include "nl/session.h"
#include <cstdio>
#include <cwchar>

namespace nl::proxy::exit_report {
namespace {
std::string normalize(std::string value) {
  for (auto& c : value) if (c >= 'A' && c <= 'Z') c += 'a' - 'A';
  if (value == "zh" || value == "schinese" || value.starts_with("zh-cn") || value.starts_with("zh-hans")) return "zh-CN";
  if (value == "tchinese" || value.starts_with("zh-tw") || value.starts_with("zh-hk") || value.starts_with("zh-hant")) return "zh-TW";
  if (value == "japanese" || value == "ja" || value.starts_with("ja-")) return "ja";
  if (value == "koreana" || value == "ko" || value.starts_with("ko-")) return "ko";
  if (value == "french" || value == "fr" || value.starts_with("fr-")) return "fr";
  if (value == "russian" || value == "ru" || value.starts_with("ru-")) return "ru";
  return "en";
}
json::Value catalog(std::string_view code) {
  const auto catalogs = json::parse(presentation::kDiagnosticsLabels);
  return *catalogs.find(normalize(std::string(code)));
}
std::string label(const json::Value& labels, std::string_view key) { return labels.find(key)->as_string(); }
}  // namespace
bool quiet(std::string_view environment) noexcept {
  if (environment.size() != 5) return false;
  constexpr std::string_view value = "quiet";
  for (std::size_t i = 0; i < value.size(); ++i) {
    auto c = environment[i]; if (c >= 'A' && c <= 'Z') c += 'a' - 'A';
    if (c != value[i]) return false;
  }
  return true;
}
std::string command_language(std::wstring_view command) {
  const auto args = cmdline::tokenize(command);
  std::string result;
  for (std::size_t i = 0; i + 1 < args.size(); ++i)
    if (_wcsicmp(args[i].c_str(), L"+gmod_language") == 0) result = fs::utf8(std::filesystem::path(args[++i]));
  return result;
}
std::string language(std::string_view config, std::string_view override_code, std::string_view os_locale) {
  if (!override_code.empty()) return normalize(std::string(override_code));
  const auto values = session::parse_config(config);
  if (const auto found = values.find("gmod_language"); found != values.end()) return normalize(found->second);
  return normalize(std::string(os_locale));
}
std::string title(std::string_view code) { return label(catalog(code), "exit_heading"); }
std::string message(const evidence::PreviousSession& previous, std::uint32_t code,
                    const std::filesystem::path& root, std::string_view language) {
  const auto labels = catalog(language);
  const auto reason = evidence::needs_report(previous.reason) ? previous.reason : "crash";
  char hex[16]{};
  std::snprintf(hex, sizeof(hex), "0x%08X", static_cast<unsigned>(code));
  auto text = label(labels, "failure_" + reason) + "\n\n" + label(labels, "exit_" + reason) +
      "\n\n" + label(labels, "exit_code") + ": " + hex;
  std::string_view exception;
  switch (code) {
    case 0xC0000005u: exception = "exit_access_violation"; break;
    case 0xC0000409u: exception = "exit_fail_fast"; break;
    case 0xC00000FDu: exception = "exit_stack_overflow"; break;
    case 0xE06D7363u: exception = "exit_cpp_exception"; break;
  }
  if (!exception.empty()) text += " (" + label(labels, exception) + ')';
  text += "\n\n" + label(labels, "exit_evidence") + ": ";
  if (previous.folder.empty()) text += label(labels, "evidence_unavailable");
  else text += fs::utf8(fs::join(root, previous.folder));
  return text;
}
}  // namespace nl::proxy::exit_report
