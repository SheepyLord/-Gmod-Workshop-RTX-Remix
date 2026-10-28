#include "nl/paths.h"

#include "nl/utf8.h"

#include <array>

namespace nl::paths {

namespace {

// Device names Windows resolves in any folder and with any extension ("con.txt" is CON).
bool reserved_device(std::string_view component) {
  const std::string base = fold(component.substr(0, component.find('.')));
  static constexpr std::array<std::string_view, 6> kNames = {"con", "prn", "aux", "nul", "conin$", "conout$"};
  for (const auto name : kNames) {
    if (base == name) return true;
  }
  if (base.size() >= 4 && (base.compare(0, 3, "com") == 0 || base.compare(0, 3, "lpt") == 0)) {
    const std::string_view rest = std::string_view(base).substr(3);
    if (rest.size() == 1 && rest[0] >= '0' && rest[0] <= '9') return true;
    // Superscript digits 1-3 (U+00B9, U+00B2, U+00B3) also name ports.
    if (rest == "\xC2\xB9" || rest == "\xC2\xB2" || rest == "\xC2\xB3") return true;
  }
  return false;
}

std::string component_problem(std::string_view c) {
  if (c.empty()) return "empty path component";
  if (c == "." || c == "..") return "'.' or '..' component";
  if (c.size() > kMaxComponentBytes) return "component longer than " + std::to_string(kMaxComponentBytes) + " bytes";
  if (c.back() == '.' || c.back() == ' ') return "component ends with '.' or a space (Windows drops them)";
  if (c.front() == ' ') return "component starts with a space";
  if (reserved_device(c)) return "reserved device name \"" + std::string(c) + "\"";
  for (std::size_t i = 0; i + 1 < c.size(); ++i) {
    if (c[i] == '~' && c[i + 1] >= '0' && c[i + 1] <= '9') return "looks like an 8.3 short name ('~' then a digit)";
  }
  return {};
}

}  // namespace

std::string problem(std::string_view path) {
  if (path.empty()) return "empty path";
  if (path.size() > kMaxPathBytes) return "longer than " + std::to_string(kMaxPathBytes) + " bytes";
  if (!utf8::valid(path)) return "not valid UTF-8";
  for (const char ch : path) {
    const auto c = static_cast<unsigned char>(ch);
    if (c < 0x20 || c == 0x7F) return "control character";
    if (c == '\\') return "backslash (use '/')";
    if (c == '<' || c == '>' || c == ':' || c == '"' || c == '|' || c == '?' || c == '*') {
      return std::string("character '") + ch + "' is not allowed";
    }
  }
  if (path.front() == '/') return "absolute path";
  std::size_t start = 0;
  for (;;) {
    const std::size_t slash = path.find('/', start);
    const std::string reason = component_problem(path.substr(start, slash == std::string_view::npos ? std::string_view::npos : slash - start));
    if (!reason.empty()) return reason;
    if (slash == std::string_view::npos) return {};
    start = slash + 1;
  }
}

std::string fold(std::string_view path) {
  std::string out(path);
  for (char& c : out) {
    if (c >= 'A' && c <= 'Z') c = static_cast<char>(c - 'A' + 'a');
  }
  return out;
}

bool within(std::string_view path, std::string_view prefix) {
  const std::string p = fold(path);
  const std::string q = fold(prefix);
  return p == q || (p.size() > q.size() && p.compare(0, q.size(), q) == 0 && p[q.size()] == '/');
}

RootArea root_area(std::string_view safe_path) {
  const auto below = [&](std::string_view prefix) { return within(safe_path, prefix) && safe_path.size() > prefix.size(); };
  if (below("rtx-remix/mods")) return RootArea::rtx_remix_mods;
  if (below("garrysmod/lua/bin")) return RootArea::lua_bin;
  if (below("garrysmod/cfg")) return RootArea::cfg;
  return RootArea::none;
}

const char* area_name(RootArea area) {
  switch (area) {
    case RootArea::rtx_remix_mods: return "rtx-remix/mods";
    case RootArea::lua_bin: return "garrysmod/lua/bin";
    case RootArea::cfg: return "garrysmod/cfg";
    case RootArea::none: break;
  }
  return "none";
}

}  // namespace nl::paths
