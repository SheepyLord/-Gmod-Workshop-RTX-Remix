// nlctl: the loader core on the command line, so packages and installs can be examined (and,
// from M3, deployed) without starting Garry's Mod. Read-only in M2.
//
// Exit codes: 0 ok, 1 a check found problems, 2 bad usage or unreadable/malformed input, 3 bug.

#include "nl/core.h"
#include "nl/gma.h"
#include "nl/json.h"
#include "nl/lzma.h"
#include "nl/manifest.h"
#include "nl/package.h"

#include <windows.h>

#include <algorithm>
#include <cstdio>
#include <cwctype>
#include <filesystem>
#include <optional>
#include <string>
#include <system_error>
#include <vector>

namespace {

namespace fs = std::filesystem;

enum ExitCode : int { kOk = 0, kCheckFailed = 1, kBadInput = 2, kInternal = 3 };

std::string utf8(const fs::path& path) {
  const std::u8string text = path.u8string();
  return std::string(text.begin(), text.end());
}

void print(const std::string& text) {
  std::fwrite(text.data(), 1, text.size(), stdout);
}

const char* container_name(nl::gma::Container kind) {
  switch (kind) {
    case nl::gma::Container::gmad: return "gmad";
    case nl::gma::Container::lzma: return "lzma";
    case nl::gma::Container::unknown: break;
  }
  return "unknown";
}

// Size of the GMAD stream: the file size for plain archives, the declared decompressed size for
// LZMA-wrapped ones (nullopt when the stream does not declare it).
std::optional<std::uint64_t> stream_size(const fs::path& file, const nl::gma::Source& source) {
  if (const auto* lzma = dynamic_cast<const nl::lzma::Source*>(&source)) {
    if (!lzma->header().size_known()) return std::nullopt;
    return lzma->header().uncompressed_size;
  }
  return fs::file_size(file);
}

// How the stream's size relates to the index: the 4-byte CRC trailer is optional (legacy items).
enum class Fit { unknown, truncated, partial_trailer, no_trailer, complete, trailing };

Fit classify(const std::optional<std::uint64_t>& size, const nl::gma::Index& index) {
  if (!size) return Fit::unknown;
  if (*size < index.data_end) return Fit::truncated;
  if (*size == index.data_end) return Fit::no_trailer;
  if (*size < index.data_end + 4) return Fit::partial_trailer;
  return *size == index.data_end + 4 ? Fit::complete : Fit::trailing;
}

const char* complete_json(Fit fit) {
  switch (fit) {
    case Fit::unknown: return "null";
    case Fit::truncated:
    case Fit::partial_trailer: return "false";
    default: return "true";
  }
}

const char* trailer_json(Fit fit) {
  switch (fit) {
    case Fit::unknown: return "null";
    case Fit::complete:
    case Fit::trailing: return "true";
    default: return "false";
  }
}

struct Opened {
  std::unique_ptr<nl::gma::Source> source;
  nl::gma::Container kind = nl::gma::Container::unknown;
  nl::gma::Index index;
  std::optional<std::uint64_t> stream_size;
};

Opened open_and_index(const fs::path& file) {
  Opened o;
  o.source = nl::gma::open_archive(file, &o.kind);
  o.index = nl::gma::read_index(*o.source);
  o.stream_size = stream_size(file, *o.source);
  return o;
}

std::string index_json(const fs::path& file, const Opened& o) {
  const auto& index = o.index;
  std::string out = "{\n  \"file\": " + nl::json::quote(utf8(file));
  out += ",\n  \"container\": \"" + std::string(container_name(o.kind)) + "\"";
  out += ",\n  \"file_size\": " + std::to_string(fs::file_size(file));
  out += ",\n  \"stream_size\": " + (o.stream_size ? std::to_string(*o.stream_size) : std::string("null"));
  out += ",\n  \"version\": " + std::to_string(index.version);
  out += ",\n  \"steamid\": " + std::to_string(index.steamid);
  out += ",\n  \"timestamp\": " + std::to_string(index.timestamp);
  out += ",\n  \"required_content\": [";
  for (std::size_t i = 0; i < index.required_content.size(); ++i) {
    out += (i ? ", " : "") + nl::json::quote(index.required_content[i]);
  }
  out += "],\n  \"title\": " + nl::json::quote(index.title);
  out += ",\n  \"description\": " + nl::json::quote(index.description);
  out += ",\n  \"author\": " + nl::json::quote(index.author);
  out += ",\n  \"addon_version\": " + std::to_string(index.addon_version);
  out += ",\n  \"data_offset\": " + std::to_string(index.data_offset);
  out += ",\n  \"data_end\": " + std::to_string(index.data_end);
  const Fit fit = classify(o.stream_size, index);
  out += ",\n  \"complete\": " + std::string(complete_json(fit));
  out += ",\n  \"crc_trailer\": " + std::string(trailer_json(fit));
  out += ",\n  \"entries\": [";
  for (std::size_t i = 0; i < index.entries.size(); ++i) {
    const auto& e = index.entries[i];
    out += (i ? ",\n    " : "\n    ");
    out += "{\"number\": " + std::to_string(e.number) + ", \"path\": " + nl::json::quote(e.path) +
           ", \"size\": " + std::to_string(e.size) + ", \"crc32\": " + std::to_string(e.crc32) +
           ", \"offset\": " + std::to_string(e.offset) + "}";
  }
  out += index.entries.empty() ? "]\n}\n" : "\n  ]\n}\n";
  return out;
}

int cmd_inspect(const fs::path& file, bool json) {
  const Opened o = open_and_index(file);
  if (json) {
    print(index_json(file, o));
    return kOk;
  }
  const std::string complete = complete_json(classify(o.stream_size, o.index));
  print("file         " + utf8(file) + "\ncontainer    " + container_name(o.kind) + "\nversion      " +
        std::to_string(o.index.version) + "\ntitle        " + o.index.title + "\nauthor       " + o.index.author +
        "\nfiles        " + std::to_string(o.index.entries.size()) + " (content " +
        std::to_string(o.index.data_offset) + ".." + std::to_string(o.index.data_end) + ", complete: " +
        (complete == "true" ? "yes" : complete == "false" ? "NO" : "unknown") + ")\n");
  for (const auto& e : o.index.entries) {
    char line[64];
    std::snprintf(line, sizeof(line), "  %6u  %12llu  %08x  ", e.number, static_cast<unsigned long long>(e.size), e.crc32);
    print(line + e.path + "\n");
  }
  return kOk;
}

int cmd_verify(const fs::path& file, bool json) {
  nl::gma::Container kind{};
  const auto source = nl::gma::open_archive(file, &kind);
  const auto report = nl::gma::verify(*source);
  if (json) {
    std::string out = "{\n  \"file\": " + nl::json::quote(utf8(file));
    out += ",\n  \"container\": \"" + std::string(container_name(kind)) + "\"";
    out += ",\n  \"ok\": " + std::string(report.ok() ? "true" : "false");
    out += ",\n  \"entries\": " + std::to_string(report.index.entries.size());
    out += ",\n  \"bad_entries\": [";
    for (std::size_t i = 0; i < report.bad_entries.size(); ++i) {
      out += (i ? ", " : "") + nl::json::quote(report.index.entries[report.bad_entries[i]].path);
    }
    if (const auto* lzma = dynamic_cast<const nl::lzma::Source*>(source.get())) {
      out += "],\n  \"lzma_gmod_footer\": " + std::string(lzma->gmod_footer() ? "true" : "false");
      out += ",\n  \"crc_trailer\": ";
    } else {
      out += "],\n  \"crc_trailer\": ";
    }
    out += report.crc_trailer ? "true" : "false";
    out += ",\n  \"addon_crc_stored\": " + std::to_string(report.addon_crc_stored);
    out += ",\n  \"addon_crc_actual\": " + std::to_string(report.addon_crc_actual);
    out += ",\n  \"trailing_bytes\": " + std::to_string(report.trailing_bytes) + "\n}\n";
    print(out);
  } else {
    for (const std::size_t i : report.bad_entries) print("CRC mismatch: " + report.index.entries[i].path + "\n");
    if (report.addon_crc_stored && report.addon_crc_stored != report.addon_crc_actual) print("archive CRC mismatch\n");
    if (report.trailing_bytes) print("trailing data: " + std::to_string(report.trailing_bytes) + " bytes\n");
    print(std::string(report.ok() ? "OK" : "FAILED") + ": " + container_name(kind) + ", " +
          std::to_string(report.index.entries.size()) + " files\n");
  }
  return report.ok() ? kOk : kCheckFailed;
}

// Read-only parse of every .gma / .bin below `folder`: header and file index only. LZMA-wrapped
// archives are decoded just far enough to read the index.
int cmd_scan(const fs::path& folder, bool json) {
  struct Failure {
    std::string file;
    std::string error;
  };
  std::size_t total = 0, parsed = 0, lzma = 0, without_crc_trailer = 0, with_trailing_data = 0, entries = 0;
  std::vector<Failure> failures;
  std::error_code ec;
  fs::recursive_directory_iterator it(folder, fs::directory_options::skip_permission_denied, ec), end;
  if (ec) throw fs::filesystem_error("cannot scan folder", folder, ec);
  for (; it != end; it.increment(ec)) {
    if (ec) {
      failures.push_back({utf8(folder), "directory walk: " + ec.message()});
      break;
    }
    std::wstring extension = it->path().extension().wstring();
    std::transform(extension.begin(), extension.end(), extension.begin(),
                   [](wchar_t c) { return static_cast<wchar_t>(std::towlower(c)); });
    // Workshop items are <name>.gma (plain) or, for older uploads, <hash>_legacy.bin (LZMA-wrapped).
    if ((extension != L".gma" && extension != L".bin") || !it->is_regular_file(ec)) continue;
    ++total;
    try {
      const Opened o = open_and_index(it->path());
      const Fit fit = classify(o.stream_size, o.index);
      if (fit == Fit::truncated || fit == Fit::partial_trailer) {
        failures.push_back({utf8(it->path()), fit == Fit::truncated
                                                  ? "truncated: the stream ends inside the declared contents"
                                                  : "truncated: the stream ends inside the CRC trailer"});
        continue;
      }
      if (fit == Fit::no_trailer) ++without_crc_trailer;
      if (fit == Fit::trailing) ++with_trailing_data;
      ++parsed;
      if (o.kind == nl::gma::Container::lzma) ++lzma;
      entries += o.index.entries.size();
    } catch (const std::exception& e) {
      failures.push_back({utf8(it->path()), e.what()});
    }
  }
  if (json) {
    std::string out = "{\n  \"folder\": " + nl::json::quote(utf8(folder));
    out += ",\n  \"total\": " + std::to_string(total) + ",\n  \"parsed\": " + std::to_string(parsed);
    out += ",\n  \"lzma\": " + std::to_string(lzma);
    out += ",\n  \"without_crc_trailer\": " + std::to_string(without_crc_trailer);
    out += ",\n  \"with_trailing_data\": " + std::to_string(with_trailing_data);
    out += ",\n  \"entries\": " + std::to_string(entries) + ",\n  \"failures\": [";
    for (std::size_t i = 0; i < failures.size(); ++i) {
      out += (i ? ",\n    " : "\n    ");
      out += "{\"file\": " + nl::json::quote(failures[i].file) + ", \"error\": " + nl::json::quote(failures[i].error) + "}";
    }
    out += failures.empty() ? "]\n}\n" : "\n  ]\n}\n";
    print(out);
  } else {
    for (const auto& f : failures) print("FAILED " + f.file + ": " + f.error + "\n");
    print(std::to_string(total) + " archives: " + std::to_string(parsed) + " parsed (" + std::to_string(lzma) +
          " LZMA-wrapped, " + std::to_string(entries) + " files), " + std::to_string(without_crc_trailer) +
          " without CRC trailer, " + std::to_string(with_trailing_data) + " with trailing data, " +
          std::to_string(failures.size()) + " failed\n");
  }
  return failures.empty() ? kOk : kCheckFailed;
}

std::string string_array_json(const std::vector<std::string>& items) {
  std::string out = "[";
  for (std::size_t i = 0; i < items.size(); ++i) out += (i ? ", " : "") + nl::json::quote(items[i]);
  return out + "]";
}

std::string manifest_json(const nl::package::Package& package) {
  const auto& m = package.manifest;
  std::uint64_t bytes = 0;
  for (const auto& [path, info] : m.files) bytes += info.size;
  std::vector<std::string> kinds;
  for (const auto kind : m.kinds) kinds.emplace_back(nl::manifest::kind_name(kind));
  std::string out = "{\n  \"location\": " + nl::json::quote(utf8(package.contents->location()));
  out += ",\n  \"id\": " + nl::json::quote(m.id) + ",\n  \"name\": " + nl::json::quote(m.name);
  out += ",\n  \"version\": " + nl::json::quote(m.version.text);
  out += ",\n  \"kinds\": " + string_array_json(kinds);
  out += ",\n  \"requires_loader\": " + (m.requires_loader ? nl::json::quote(">=" + m.requires_loader->text) : "null");
  out += ",\n  \"files\": " + std::to_string(m.files.size()) + ",\n  \"file_bytes\": " + std::to_string(bytes);
  if (m.remix) {
    const auto& r = *m.remix;
    out += ",\n  \"remix\": {\"entry\": " + nl::json::quote(r.entry) + ", \"rtx_conf_layers\": " +
           string_array_json(r.rtx_conf_layers) + ", \"dxvk_conf_layers\": " + string_array_json(r.dxvk_conf_layers) +
           ", \"env\": {";
    for (std::size_t i = 0; i < r.env.size(); ++i) {
      out += (i ? ", " : "") + nl::json::quote(r.env[i].first) + ": " + nl::json::quote(r.env[i].second);
    }
    out += "}, \"launch_args\": " + string_array_json(r.launch_args) + ", \"prefer_system_vulkan_loader\": " +
           (r.prefer_system_vulkan_loader ? "true" : "false") + "}";
  } else {
    out += ",\n  \"remix\": null";
  }
  out += ",\n  \"root_files\": [";
  for (std::size_t i = 0; i < m.root_files.size(); ++i) {
    const auto& rf = m.root_files[i];
    out += (i ? ", " : "") + std::string("{\"path\": ") + nl::json::quote(rf.path) + ", \"policy\": \"" +
           nl::manifest::policy_name(rf.policy) + "\", \"area\": \"" + nl::paths::area_name(rf.area) + "\"}";
  }
  return out + "]\n}\n";
}

// Loads a package (.gma or development folder) and validates its manifest against its files.
int cmd_manifest(const fs::path& location, bool json) {
  try {
    auto contents = fs::is_directory(location) ? nl::package::open_folder(location) : nl::package::open_archive(location);
    const auto package = nl::package::load(std::move(contents));
    if (json) {
      print(manifest_json(package));
    } else {
      const auto& m = package.manifest;
      std::string kinds;
      for (const auto kind : m.kinds) kinds += (kinds.empty() ? "" : ", ") + std::string(nl::manifest::kind_name(kind));
      print("package      " + m.id + " " + m.version.text + " (" + m.name + ")\nkinds        " + kinds + "\nfiles        " +
            std::to_string(m.files.size()) + "\n");
      if (m.remix) print("remix entry  native/payload/" + m.remix->entry + "\n");
      for (const auto& rf : m.root_files) print("root file    " + rf.path + " (" + nl::manifest::policy_name(rf.policy) + ")\n");
      print("OK: valid native package\n");
    }
    return kOk;
  } catch (const nl::package::Error& e) {
    std::fprintf(stderr, "%s\n", e.what());
    return kCheckFailed;
  } catch (const nl::manifest::Error& e) {
    std::fprintf(stderr, "%s\n", e.what());
    return kCheckFailed;
  }
}

int usage() {
  std::fputs(
      "usage: nlctl <command> [--json]\n"
      "  inspect <file.gma>   header and file index (LZMA-wrapped: decoded only that far)\n"
      "  verify  <file.gma>   check every file CRC, the archive CRC and trailing data\n"
      "  scan    <folder>     read-only parse of every .gma / .bin archive below the folder\n"
      "  manifest <file.gma|folder>  validate a native package and summarise its manifest\n"
      "  version              loader version\n",
      stderr);
  return kBadInput;
}

}  // namespace

int wmain(int argc, wchar_t** argv) {
  SetConsoleOutputCP(CP_UTF8);
  try {
    std::vector<std::wstring> args(argv + 1, argv + argc);
    const auto json_flag = std::find(args.begin(), args.end(), L"--json");
    const bool json = json_flag != args.end();
    if (json) args.erase(json_flag);
    if (args.size() == 1 && args[0] == L"version") {
      print(std::string(nl::version()) + "\n");
      return kOk;
    }
    if (args.size() == 2 && args[0] == L"inspect") return cmd_inspect(args[1], json);
    if (args.size() == 2 && args[0] == L"verify") return cmd_verify(args[1], json);
    if (args.size() == 2 && args[0] == L"scan") return cmd_scan(args[1], json);
    if (args.size() == 2 && args[0] == L"manifest") return cmd_manifest(args[1], json);
    return usage();
  } catch (const nl::gma::FormatError& e) {
    std::fprintf(stderr, "error: %s\n", e.what());
    return kBadInput;
  } catch (const fs::filesystem_error& e) {
    std::fprintf(stderr, "error: %s\n", e.what());
    return kBadInput;
  } catch (const std::exception& e) {
    std::fprintf(stderr, "internal error: %s\n", e.what());
    return kInternal;
  }
}
