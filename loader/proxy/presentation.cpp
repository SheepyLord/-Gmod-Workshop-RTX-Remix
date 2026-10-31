#include "presentation.h"
#include "diagnostics.h"
#include "presentation_data.h"
#include "../client/catalog.h"

#include "nl/crc32.h"
#include "nl/fs.h"
#include "nl/json.h"
#include "nl/package.h"
#include "nl/sha256.h"

#include <algorithm>
#include <cstdint>
#include <set>
#include <stdexcept>

namespace nl::proxy::presentation {
namespace {

constexpr std::string_view kDirectory = "native-loader/presentation";
constexpr std::string_view kMenu = "garrysmod/html/js/menu/control.Addons.js";
constexpr std::string_view kMainMenu = "garrysmod/html/js/menu/control.Menu.js";
constexpr std::size_t kMaxMenuBytes = std::size_t{2} << 20;

bool numeric_id(std::string_view text) {
  return !text.empty() && text.size() <= 20 && text.front() != '0' &&
         std::all_of(text.begin(), text.end(), [](char c) { return c >= '0' && c <= '9'; });
}

void require_id(std::string_view text) {
  if (!numeric_id(text)) throw std::runtime_error("presentation requires a numeric Workshop item ID");
}

std::string lower(std::string text) {
  for (char& c : text) if (c >= 'A' && c <= 'Z') c = static_cast<char>(c - 'A' + 'a');
  return text;
}

void put_u32(std::string& out, std::uint32_t value) {
  for (unsigned i = 0; i < 4; ++i) out.push_back(static_cast<char>((value >> (i * 8)) & 0xff));
}

void put_u64(std::string& out, std::uint64_t value) {
  for (unsigned i = 0; i < 8; ++i) out.push_back(static_cast<char>((value >> (i * 8)) & 0xff));
}

void put_string(std::string& out, std::string_view value) {
  if (value.find('\0') != std::string_view::npos) throw std::runtime_error("NUL in display archive metadata");
  out += value;
  out.push_back('\0');
}

void replace_once(std::string& text, std::string_view from, std::string_view to) {
  const auto at = text.find(from);
  if (at == std::string::npos || text.find(from, at + from.size()) != std::string::npos)
    throw std::runtime_error("stock addon menu source differs; display overlay not installed");
  text.replace(at, from.size(), to);
}

// A Workshop source is outside the game root. Check every existing component from its volume
// root rather than assuming a sibling workshop folder is safe to follow.
void refuse_source_links(const std::filesystem::path& absolute) {
  auto current = absolute.root_path();
  for (const auto& part : absolute.relative_path()) {
    current /= part;
    const auto state = fs::stat(current);
    if (!state.exists) throw std::runtime_error("Workshop source is missing: " + fs::utf8(current));
    if (state.link) throw std::runtime_error("Workshop source passes through a link: " + fs::utf8(current));
  }
}

std::string workshop_id(const std::filesystem::path& source) {
  if (!source.is_absolute()) return {};
  const auto path = source.lexically_normal();
  const auto item = path.parent_path();
  const auto app = item.parent_path();
  const auto content = app.parent_path();
  const auto workshop = content.parent_path();
  const std::string id = fs::utf8(item.filename());
  const std::string extension = lower(fs::utf8(path.extension()));
  if (!numeric_id(id) || fs::utf8(app.filename()) != "4000" ||
      lower(fs::utf8(content.filename())) != "content" || lower(fs::utf8(workshop.filename())) != "workshop" ||
      (extension != ".gma" && extension != ".bin")) return {};
  return id;
}

std::filesystem::path cache(const std::filesystem::path& root, std::string_view bytes, std::string_view extension) {
  const std::string relative = std::string(kDirectory) + "/" + sha256::of(bytes) + std::string(extension);
  fs::refuse_links(root, relative);
  for (const std::string_view folder : {std::string_view("native-loader"), kDirectory}) {
    const auto path = fs::join(root, folder);
    const auto state = fs::stat(path);
    if (!state.exists) fs::win32().create_directory(path);
    else if (!state.directory || state.link) throw std::runtime_error("display cache is not an ordinary directory");
  }
  const auto path = fs::join(root, relative);
  const auto state = fs::stat(path);
  if (state.exists) {
    if (state.directory || state.link || state.size != bytes.size() || fs::read_file(path, bytes.size()) != bytes)
      throw std::runtime_error("display cache was modified; kept unchanged: " + fs::utf8(path));
  } else {
    fs::write_atomic(fs::win32(), path, bytes);
  }
  return path;
}

}  // namespace

std::string make_archive(const gma::Index& original, const journal::Package& package, std::string_view workshop_item) {
  require_id(workshop_item);
  const std::string metadata = "{\"managed_by\":\"native-loader\",\"workshop_item\":" + json::quote(workshop_item) +
      ",\"package\":" + json::quote(package.id) + ",\"version\":" + json::quote(package.version) + "}\n";
  std::string out = "GMAD";
  out.push_back('\3');
  put_u64(out, original.steamid);
  put_u64(out, original.timestamp);
  out.push_back('\0');  // no required content; the loader owns deployment dependencies
  put_string(out, original.title);
  put_string(out, original.description);
  put_string(out, original.author);
  put_u32(out, static_cast<std::uint32_t>(original.addon_version));
  put_u32(out, 1);
  put_string(out, "data_static/native-loader/packages/" + std::string(workshop_item) + ".json");
  put_u64(out, metadata.size());
  put_u32(out, crc32(metadata.data(), metadata.size()));
  put_u32(out, 0);
  out += metadata;
  put_u32(out, crc32(out.data(), out.size()));
  return out;
}

std::string decorate_menu(std::string_view original, const std::vector<std::string>& workshop_items) {
  std::set<std::string> ids;
  for (const auto& id : workshop_items) { require_id(id); ids.insert(id); }
  if (ids.empty()) throw std::runtime_error("no deployed native Workshop items for the addon menu");
  std::string map = "{";
  for (const auto& id : ids) map += (map.size() == 1 ? "" : ",") + json::quote(id) + ":true";
  map += "}";
  std::string decorated(original);
  replace_once(decorated, "var classes = [];", "var classes = [];\n\t\tvar nativeLoaderPackage = NativeLoaderManagedAddon( file );\n\t\tif ( nativeLoaderPackage ) classes.push( \"nl-native\" );");
  replace_once(decorated, "if ( subscriptions.GetInvalidReason( file.id ) ) classes.push( \"invalid\" );",
               "if ( !nativeLoaderPackage && subscriptions.GetInvalidReason( file.id ) ) classes.push( \"invalid\" );");
  replace_once(decorated, "if ( invalid ) return invalid;", "if ( invalid && !NativeLoaderManagedAddon( file ) ) return invalid;");
  const std::string prefix = "// Generated by the GMod native loader: presentation of deployed package containers.\n"
      "var NativeLoaderPackageItems = Object.freeze(" + map + ");\n"
      "function NativeLoaderManagedAddon( file ) { return !!file && Object.prototype.hasOwnProperty.call( NativeLoaderPackageItems, String( file.id ) ); }\n"
      "(function() {\n"
      "  if ( document.getElementById( 'nl-native-addon-style' ) ) return;\n"
      "  var style = document.createElement( 'style' ); style.id = 'nl-native-addon-style';\n"
      "  style.textContent = 'workshopicon.nl-native,workshopicon.nl-native.disabled{border-color:#2387ed}' +\n"
      "    'workshopicon.nl-native name,workshopicon.nl-native author,workshopicon.nl-native votes,workshopicon.nl-native size{background:#2387ed;color:#fff}';\n"
      "  document.head.appendChild( style );\n"
      "})();\n";
  return prefix + decorated;
}

// GMod's menu decodes these generated scripts as Windows-1252: UTF-8 text in them showed as mojibake
// (the panel's "·" as "Â·", and every translated label; review R4). Each non-ASCII character is written
// as a \uXXXX escape (UTF-16, surrogate pairs above U+FFFF), which JavaScript reads as the same character
// in strings, JSON, comments and identifiers.
static std::string ascii_javascript(std::string_view text) {
  std::string out;
  out.reserve(text.size());
  const auto put = [&out](std::uint32_t unit) {
    constexpr char kHex[] = "0123456789abcdef";
    out += "\\u";
    for (int shift = 12; shift >= 0; shift -= 4) out += kHex[(unit >> shift) & 0xF];
  };
  for (std::size_t i = 0; i < text.size();) {
    const auto lead = static_cast<unsigned char>(text[i]);
    if (lead < 0x80) { out += static_cast<char>(lead); ++i; continue; }
    const std::size_t length = lead >= 0xF0 && lead <= 0xF4 ? 4 : lead >= 0xE0 ? 3 : lead >= 0xC2 && lead < 0xE0 ? 2 : 0;
    if (length == 0 || lead > 0xF4 || i + length > text.size()) throw std::runtime_error("generated menu script is not UTF-8");
    std::uint32_t code = lead & (length == 2 ? 0x1F : length == 3 ? 0x0F : 0x07);
    for (std::size_t k = 1; k < length; ++k) {
      const auto next = static_cast<unsigned char>(text[i + k]);
      if ((next & 0xC0) != 0x80) throw std::runtime_error("generated menu script is not UTF-8");
      code = (code << 6) | (next & 0x3F);
    }
    const std::uint32_t lowest = length == 2 ? 0x80 : length == 3 ? 0x800 : 0x10000;
    if (code < lowest || code > 0x10FFFF || (code >= 0xD800 && code <= 0xDFFF))
      throw std::runtime_error("generated menu script is not UTF-8");
    if (code >= 0x10000) {
      put(0xD800 + ((code - 0x10000) >> 10));
      put(0xDC00 + ((code - 0x10000) & 0x3FF));
    } else {
      put(code);
    }
    i += length;
  }
  return out;
}

std::string decorate_main_menu(std::string_view original, std::string_view diagnostics_json, bool client_bootstrap) {
  constexpr std::string_view anchor = "function MenuController( $scope, $rootScope )";
  const auto at = original.find(anchor);
  if (at == std::string_view::npos || original.find(anchor, at + anchor.size()) != std::string_view::npos)
    throw std::runtime_error("stock main menu controller differs; diagnostics overlay not installed");
  // Parse before embedding so an invalid producer cannot turn the response into arbitrary JavaScript.
  if (!json::parse(diagnostics_json).is_object()) throw std::runtime_error("diagnostics must be a JSON object");
  return std::string(original) + ascii_javascript("\nwindow.NativeLoaderClientBootstrap = " + std::string(client_bootstrap ? "true" : "false") +
    ";\nwindow.NativeLoaderDiagnostics = " + std::string(diagnostics_json) +
    ";\nwindow.NativeLoaderReadNotices = " + json::quote(kDiagnosticsNotices) +
    ";\nwindow.NativeLoaderDiagnosticLabels = " + std::string(kDiagnosticsLabels) + ";\n" + std::string(kDiagnosticsScript));
}

std::string add_client_bootstrap(std::string_view original) {
  // The same script: without diagnostics data its overlay part stays out, the trigger still runs.
  return std::string(original) + ascii_javascript("\nwindow.NativeLoaderClientBootstrap = true;\n" + std::string(kDiagnosticsScript));
}

Prepared prepare(const std::filesystem::path& root, const journal::Generation& generation, bool include_diagnostics) {
  Prepared prepared;
  std::vector<std::string> ids;
  for (const auto& current : generation.packages) {
    if (current.source != "workshop") continue;
    try {
      const auto source = fs::join({}, current.location).lexically_normal();
      const std::string id = workshop_id(source);
      if (id.empty()) throw std::runtime_error("source is not an absolute Workshop archive path");
      refuse_source_links(source);
      const auto before = fs::stat(source);
      if (before.directory) throw std::runtime_error("Workshop source is not an ordinary archive");
      const auto package = package::load(package::open_archive(source));
      if (package.manifest_sha256 != current.manifest_sha256 || package.manifest.id != current.id ||
          package.manifest.version.text != current.version)
        throw std::runtime_error("Workshop source differs from the deployed generation");
      auto stream = gma::open_archive(source);
      const auto index = gma::read_index(*stream);
      const auto after = fs::stat(source);
      if (after.link || after.directory || !after.exists || after.size != before.size || after.mtime != before.mtime)
        throw std::runtime_error("Workshop source changed while preparing its display archive");
      const auto replacement = cache(root, make_archive(index, current, id), ".gma");
      prepared.redirects.push_back({source, replacement, id});
      ids.push_back(id);
    } catch (const std::exception& error) {
      prepared.notes.push_back("native package display " + current.id + ": " + error.what());
    }
  }
  if (!ids.empty()) {
    try {
      fs::refuse_links(root, kMenu);
      const auto source = fs::join(root, kMenu);
      const auto text = fs::read_file(source, kMaxMenuBytes);
      const auto replacement = cache(root, decorate_menu(text, ids), ".js");
      prepared.redirects.push_back({source, replacement, {}});
    } catch (const std::exception& error) {
      prepared.notes.push_back("native package addon menu: " + std::string(error.what()));
    }
  }
  if (include_diagnostics) {
    try {
      fs::refuse_links(root, kMainMenu);
      const auto source = fs::join(root, kMainMenu);
      const auto text = fs::read_file(source, kMaxMenuBytes);
      // The multiplayer bootstrap's only trigger lives in this view (ADR 0052): a menu the overlay
      // no longer recognizes still gets the trigger alone (ADR 0056).
      const bool bootstrap = client::native_bootstrap_present(generation);
      std::string decorated;
      try {
        decorated = decorate_main_menu(text, diagnostics::collect(root, generation), bootstrap);
      } catch (const std::exception& error) {
        if (!bootstrap) throw;
        prepared.notes.push_back("native loader main menu: " + std::string(error.what()) +
                                 "; the RTX multiplayer bootstrap trigger is installed without it");
        decorated = add_client_bootstrap(text);
      }
      const auto replacement = cache(root, decorated, ".js");
      prepared.redirects.push_back({source, replacement, {}});
    } catch (const std::exception& error) {
      prepared.notes.push_back("native loader main menu: " + std::string(error.what()));
    }
  }
  return prepared;
}

}  // namespace nl::proxy::presentation
