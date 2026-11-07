// The loading window's pure parts: when it shows and what it says (ADR 0128).
#include "loading.h"
#include "presentation_data.h"
#include "nl/json.h"
#include <cstdio>

namespace nl::proxy::loading {
namespace {
std::string lower(std::string_view value) {
  std::string out(value);
  for (auto& c : out) if (c >= 'A' && c <= 'Z') c += 'a' - 'A';
  return out;
}
void replace(std::string& text, std::string_view key, const std::string& value) {
  const auto at = text.find(key);
  if (at != std::string::npos) text.replace(at, key.size(), value);
}
}  // namespace

Mode mode(std::string_view environment) noexcept {
  try {
    const auto value = lower(environment);
    if (value == "0" || value == "off" || value == "false" || value == "no") return Mode::off;
    if (value == "always") return Mode::always;
  } catch (...) {
  }
  return Mode::automatic;
}

bool should_show(Mode mode, std::uint64_t elapsed_ms, std::uint64_t unpack_bytes) noexcept {
  if (mode == Mode::off) return false;
  if (mode == Mode::always) return true;
  if (elapsed_ms >= kSlowStartMs) return true;
  return elapsed_ms >= kGraceMs && unpack_bytes >= kMinimumUnpack;
}

int percent(std::uint64_t done, std::uint64_t total) noexcept {
  if (!total) return 0;
  if (done >= total) return 100;
  const auto value = static_cast<int>(static_cast<long double>(done) * 100.0L / static_cast<long double>(total));
  return value < 0 ? 0 : value > 99 ? 99 : value;  // 100 only once everything is unpacked
}

Catalog catalog(std::string_view language) {
  const auto catalogs = json::parse(presentation::kDiagnosticsLabels);
  const json::Value* english = catalogs.find("en");
  const json::Value* chosen = catalogs.find(language);
  if (!chosen || !chosen->is_object()) chosen = english;
  const auto label = [&](std::string_view key) -> std::string {
    if (const auto* value = chosen->find(key); value && value->is_string()) return value->as_string();
    if (const auto* value = english->find(key); value && value->is_string()) return value->as_string();
    return {};
  };
  Catalog text;
  text.title = label("loading_title");
  text.heading = label("loading_heading");
  text.body = label("loading_body");
  text.checking = label("loading_checking");
  text.unpacking = label("loading_unpacking");
  text.placing = label("loading_placing");
  text.starting = label("loading_starting");
  text.megabytes = label("loading_megabytes");
  text.gigabytes = label("loading_gigabytes");
  text.decimal = label("loading_decimal");
  return text;
}

std::string size_text(const Catalog& text, std::uint64_t bytes) {
  constexpr std::uint64_t kMiB = std::uint64_t{1} << 20;
  constexpr std::uint64_t kGiB = std::uint64_t{1} << 30;
  char number[32]{};
  if (bytes >= kGiB) {
    // One decimal, rounded down, so "2.1 GB of 2.1 GB" never shows before the end.
    const std::uint64_t tenths = bytes / (kGiB / 10);
    std::snprintf(number, sizeof(number), "%llu%s%llu", static_cast<unsigned long long>(tenths / 10),
                  text.decimal.empty() ? "." : text.decimal.c_str(), static_cast<unsigned long long>(tenths % 10));
    return std::string(number) + " " + text.gigabytes;
  }
  std::snprintf(number, sizeof(number), "%llu", static_cast<unsigned long long>(bytes / kMiB));
  return std::string(number) + " " + text.megabytes;
}

std::string status_text(const Catalog& text, std::uint32_t phase, std::uint64_t done, std::uint64_t total) {
  switch (phase) {
    case deploy::Progress::unpacking: {
      if (!total) return text.checking;
      auto line = text.unpacking;
      replace(line, "{done}", size_text(text, done < total ? done : total));
      replace(line, "{total}", size_text(text, total));
      replace(line, "{percent}", std::to_string(percent(done, total)));
      return line;
    }
    case deploy::Progress::placing: return text.placing;
    case deploy::Progress::starting: return text.starting;
    default: return text.checking;
  }
}

}  // namespace nl::proxy::loading
