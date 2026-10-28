// nlctl: the loader core on the command line, so packages and installs can be examined (and,
// from M3, deployed) without starting Garry's Mod. Read-only in M2.
//
// Exit codes: 0 ok, 1 a check found problems, 2 bad usage or unreadable/malformed input, 3 bug.

#include "nl/core.h"
#include "nl/gma.h"
#include "nl/json.h"

#include <windows.h>

#include <algorithm>
#include <cstdio>
#include <cwctype>
#include <filesystem>
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

std::string index_json(const fs::path& file, std::uint64_t file_size, const nl::gma::Index& index) {
  std::string out = "{\n  \"file\": " + nl::json::quote(utf8(file)) + ",\n  \"container\": \"gmad\"";
  out += ",\n  \"file_size\": " + std::to_string(file_size);
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
  out += ",\n  \"complete\": ";
  out += file_size >= index.data_end + 4 ? "true" : "false";
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
  nl::gma::Container kind{};
  const auto source = nl::gma::open_archive(file, &kind);
  const auto index = nl::gma::read_index(*source);
  const auto file_size = fs::file_size(file);
  if (json) {
    print(index_json(file, file_size, index));
    return kOk;
  }
  print("file         " + utf8(file) + "\ncontainer    " + container_name(kind) + "\nversion      " +
        std::to_string(index.version) + "\ntitle        " + index.title + "\nauthor       " + index.author +
        "\nfiles        " + std::to_string(index.entries.size()) + " (content " + std::to_string(index.data_offset) +
        ".." + std::to_string(index.data_end) + ", complete: " +
        (file_size >= index.data_end + 4 ? "yes" : "NO") + ")\n");
  for (const auto& e : index.entries) {
    char line[64];
    std::snprintf(line, sizeof(line), "  %6u  %12llu  %08x  ", e.number, static_cast<unsigned long long>(e.size), e.crc32);
    print(line + e.path + "\n");
  }
  return kOk;
}

int cmd_verify(const fs::path& file, bool json) {
  const auto source = nl::gma::open_archive(file);
  const auto report = nl::gma::verify(*source);
  if (json) {
    std::string out = "{\n  \"file\": " + nl::json::quote(utf8(file)) + ",\n  \"ok\": " + (report.ok() ? "true" : "false");
    out += ",\n  \"entries\": " + std::to_string(report.index.entries.size());
    out += ",\n  \"bad_entries\": [";
    for (std::size_t i = 0; i < report.bad_entries.size(); ++i) {
      out += (i ? ", " : "") + nl::json::quote(report.index.entries[report.bad_entries[i]].path);
    }
    out += "],\n  \"addon_crc_stored\": " + std::to_string(report.addon_crc_stored);
    out += ",\n  \"addon_crc_actual\": " + std::to_string(report.addon_crc_actual);
    out += ",\n  \"trailing_bytes\": " + std::to_string(report.trailing_bytes) + "\n}\n";
    print(out);
  } else {
    for (const std::size_t i : report.bad_entries) print("CRC mismatch: " + report.index.entries[i].path + "\n");
    if (report.addon_crc_stored && report.addon_crc_stored != report.addon_crc_actual) print("archive CRC mismatch\n");
    if (report.trailing_bytes) print("trailing data: " + std::to_string(report.trailing_bytes) + " bytes\n");
    print(std::string(report.ok() ? "OK" : "FAILED") + ": " + std::to_string(report.index.entries.size()) + " files\n");
  }
  return report.ok() ? kOk : kCheckFailed;
}

// Read-only parse of every .gma / .bin below `folder`: header and file index only, no contents.
int cmd_scan(const fs::path& folder, bool json) {
  struct Failure {
    std::string file;
    std::string error;
  };
  std::size_t total = 0, gmad_ok = 0, lzma_not_decoded = 0, with_trailing_data = 0, entries = 0;
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
    std::transform(extension.begin(), extension.end(), extension.begin(), [](wchar_t c) { return static_cast<wchar_t>(towlower(c)); });
    // Workshop items are <name>.gma (plain) or, for older uploads, <hash>_legacy.bin (LZMA-wrapped).
    if ((extension != L".gma" && extension != L".bin") || !it->is_regular_file(ec)) continue;
    ++total;
    nl::gma::Container kind = nl::gma::Container::unknown;
    try {
      const auto source = nl::gma::open_archive(it->path(), &kind);
      const auto index = nl::gma::read_index(*source);
      const auto size = fs::file_size(it->path());
      if (size < index.data_end + 4) {
        failures.push_back({utf8(it->path()), "truncated: file ends before the declared contents and CRC"});
        continue;
      }
      if (size > index.data_end + 4) ++with_trailing_data;
      ++gmad_ok;
      entries += index.entries.size();
    } catch (const nl::gma::FormatError& e) {
      if (kind == nl::gma::Container::lzma) {
        ++lzma_not_decoded;  // counted, not failed, until the LZMA decoder lands
      } else {
        failures.push_back({utf8(it->path()), e.what()});
      }
    } catch (const std::exception& e) {
      failures.push_back({utf8(it->path()), e.what()});
    }
  }
  if (json) {
    std::string out = "{\n  \"folder\": " + nl::json::quote(utf8(folder));
    out += ",\n  \"total\": " + std::to_string(total) + ",\n  \"gmad_ok\": " + std::to_string(gmad_ok);
    out += ",\n  \"lzma_not_decoded\": " + std::to_string(lzma_not_decoded);
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
    print(std::to_string(total) + " archives: " + std::to_string(gmad_ok) + " parsed (" + std::to_string(entries) +
          " files), " + std::to_string(lzma_not_decoded) + " LZMA-wrapped (decoder pending), " +
          std::to_string(with_trailing_data) + " with trailing data, " + std::to_string(failures.size()) + " failed\n");
  }
  return failures.empty() ? kOk : kCheckFailed;
}

int usage() {
  std::fputs(
      "usage: nlctl <command> [--json]\n"
      "  inspect <file.gma>   header and file index (no contents read)\n"
      "  verify  <file.gma>   check every file CRC, the archive CRC and trailing data\n"
      "  scan    <folder>     read-only parse of every .gma / .bin archive below the folder\n"
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
