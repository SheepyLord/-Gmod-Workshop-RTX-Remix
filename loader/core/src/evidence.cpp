#include "nl/evidence.h"
#include "nl/fs.h"
#include "nl/json.h"
#include "nl/paths.h"
#include "nl/sha256.h"
#include <windows.h>
#include <algorithm>
#include <array>
#include <chrono>
#include <charconv>
#include <cstdio>
#include <memory>

namespace nl::evidence {
namespace {
constexpr DWORD kSharing = FILE_SHARE_READ | FILE_SHARE_WRITE | FILE_SHARE_DELETE;
constexpr std::string_view kLog = "rtx-remix/logs/remix-dxvk.log";
struct Handle {
  HANDLE value = INVALID_HANDLE_VALUE;
  ~Handle() { if (value != INVALID_HANDLE_VALUE) CloseHandle(value); }
};
struct Source { std::string path; std::uint64_t size = 0; std::uint64_t time = 0; };
struct Copy { std::string path; std::string hash; std::uint64_t size = 0; };

// Diagnostic metadata needs atomic replacement, not the deployment journal's write-through
// durability. Avoid two disk-cache flushes on the otherwise empty startup path.
void start_record(const std::filesystem::path& root, std::uint64_t start, std::uint32_t process) {
  const auto temporary = std::string(kStart) + ".tmp-" + std::to_string(process) + '-' + std::to_string(start);
  fs::refuse_links(root, temporary);
  fs::refuse_links(root, kStart);
  const auto from = fs::long_path(fs::join(root, temporary)), to = fs::long_path(fs::join(root, kStart));
  const auto text = "{\"schema\":1,\"start_filetime\":" + std::to_string(start) +
      ",\"time_utc\":" + json::quote(utc(start)) + ",\"process_id\":" + std::to_string(process) + "}\n";
  {
    Handle output{CreateFileW(from.c_str(), GENERIC_WRITE, FILE_SHARE_READ, nullptr, CREATE_NEW, FILE_ATTRIBUTE_NORMAL, nullptr)};
    if (output.value == INVALID_HANDLE_VALUE) throw std::runtime_error("cannot create session start record");
    DWORD written = 0;
    if (!WriteFile(output.value, text.data(), static_cast<DWORD>(text.size()), &written, nullptr) || written != text.size())
      throw std::runtime_error("cannot write session start record");
  }
  if (!MoveFileExW(from.c_str(), to.c_str(), MOVEFILE_REPLACE_EXISTING)) {
    DeleteFileW(from.c_str());
    throw std::runtime_error("cannot replace session start record");
  }
}

Handle open_read(const std::filesystem::path& root, std::string_view relative) {
  fs::refuse_links(root, relative);
  return {CreateFileW(fs::long_path(fs::join(root, relative)).c_str(), GENERIC_READ, kSharing, nullptr,
                      OPEN_EXISTING, FILE_FLAG_OPEN_REPARSE_POINT | FILE_FLAG_SEQUENTIAL_SCAN, nullptr)};
}
std::string tail(const std::filesystem::path& root, std::string_view path, std::size_t maximum) {
  auto file = open_read(root, path);
  if (file.value == INVALID_HANDLE_VALUE) return {};
  LARGE_INTEGER size{};
  if (!GetFileSizeEx(file.value, &size) || size.QuadPart < 0) return {};
  const auto count = static_cast<DWORD>(std::min<std::uint64_t>(size.QuadPart, maximum));
  LARGE_INTEGER offset{};
  offset.QuadPart = size.QuadPart - count;
  if (!SetFilePointerEx(file.value, offset, nullptr, FILE_BEGIN)) return {};
  std::string text(count, '\0');
  DWORD got = 0;
  if (!ReadFile(file.value, text.data(), count, &got, nullptr)) return {};
  text.resize(got);
  return text;
}
std::string lower(std::string value) {
  for (auto& c : value) if (c >= 'A' && c <= 'Z') c += 'a' - 'A';
  return value;
}
bool out_of_memory(std::string_view text) {
  if (text.find("OUT OF MEMORY!") != text.npos) return true;
  constexpr char wide[] = "O\0U\0T\0 \0O\0F\0 \0M\0E\0M\0O\0R\0Y\0!\0";
  return text.find(std::string_view(wide, sizeof(wide) - 1)) != text.npos;
}
void sources(const std::filesystem::path& root, const std::string& folder, std::uint64_t since,
             std::uint64_t until, std::vector<Source>& found, const Limits& limits, int depth = 0) {
  fs::refuse_links(root, folder);
  WIN32_FIND_DATAW entry{};
  const auto pattern = fs::long_path(fs::join(root, folder) / L"*");
  const HANDLE search = FindFirstFileW(pattern.c_str(), &entry);
  if (search == INVALID_HANDLE_VALUE) return;
  struct Close { HANDLE value; ~Close() { FindClose(value); } } close{search};
  std::size_t visited = 0;
  do {
    const std::wstring_view name(entry.cFileName);
    if (name == L"." || name == L"..") continue;
    if (++visited > limits.files || found.size() >= limits.files) break;
    if (entry.dwFileAttributes & FILE_ATTRIBUTE_REPARSE_POINT) continue;
    const auto path = folder + '/' + fs::utf8(std::filesystem::path(name));
    if (!paths::problem(path).empty()) continue;
    if (entry.dwFileAttributes & FILE_ATTRIBUTE_DIRECTORY) {
      if (depth > 0) sources(root, path, since, until, found, limits, depth - 1);
      continue;
    }
    const auto extension = lower(fs::utf8(std::filesystem::path(name).extension()));
    const bool gpu = folder.starts_with("native-loader/logs/gpu");
    if (!gpu && name != L"last_crash" && extension != ".dmp" && extension != ".txt") continue;
    const auto time = (std::uint64_t(entry.ftLastWriteTime.dwHighDateTime) << 32) | entry.ftLastWriteTime.dwLowDateTime;
    if (time < since || time > until) continue;
    found.push_back({path, (std::uint64_t(entry.nFileSizeHigh) << 32) | entry.nFileSizeLow, time});
  } while (FindNextFileW(search, &entry));
}
bool recent(const std::filesystem::path& root, std::string_view path, std::uint64_t since, std::uint64_t until) {
  fs::refuse_links(root, path);
  const auto s = fs::stat(fs::join(root, path));
  return s.exists && !s.directory && !s.link && s.mtime >= since && s.mtime <= until;
}
// Streams with full source sharing. A source that grows/shrinks while read is skipped, never copied
// partially. OOM text is recognized across chunk boundaries, including UTF-16 LE minidump strings.
bool copy(const std::filesystem::path& root, const Source& source, const std::string& destination,
          std::uint64_t& remaining, std::vector<Copy>& copies, bool& oom) {
  const auto overhead = source.path.size() + 160;
  if (overhead > remaining || source.size > remaining - overhead) return false;
  auto input = open_read(root, source.path);
  if (input.value == INVALID_HANDLE_VALUE) return false;
  BY_HANDLE_FILE_INFORMATION before{};
  if (!GetFileInformationByHandle(input.value, &before) ||
      (before.dwFileAttributes & (FILE_ATTRIBUTE_DIRECTORY | FILE_ATTRIBUTE_REPARSE_POINT))) return false;
  fs::refuse_links(root, destination);
  const auto target = fs::join(root, destination);
  std::filesystem::create_directories(target.parent_path());
  auto output = fs::win32().create_file(target);
  sha256::Hasher hash;
  std::array<char, 64 * 1024> buffer{};
  std::string overlap;
  std::uint64_t total = 0;
  bool success = true;
  for (;;) {
    DWORD got = 0;
    if (!ReadFile(input.value, buffer.data(), static_cast<DWORD>(buffer.size()), &got, nullptr)) { success = false; break; }
    if (!got) break;
    if (got > source.size - total) { success = false; break; }
    const std::string scan = overlap + std::string(buffer.data(), got);
    if (source.path.starts_with("crashes/")) oom = oom || out_of_memory(scan);
    overlap = scan.substr(scan.size() > 64 ? scan.size() - 64 : 0);
    output->write(buffer.data(), got);
    hash.update(buffer.data(), got);
    total += got;
  }
  output->close();
  BY_HANDLE_FILE_INFORMATION after{};
  if (!GetFileInformationByHandle(input.value, &after) || before.nFileSizeHigh != after.nFileSizeHigh ||
      before.nFileSizeLow != after.nFileSizeLow || CompareFileTime(&before.ftLastWriteTime, &after.ftLastWriteTime) != 0)
    success = false;
  if (!success || total != source.size) { fs::win32().remove_file(target); return false; }
  copies.push_back({source.path, hash.finish_hex(), total});
  remaining -= total + overhead;
  return true;
}
std::string receipt(const std::vector<Copy>& copies) {
  std::string text = "{\"native_loader_session\":1,\"files\":[";
  for (const auto& item : copies) {
    if (text.back() != '[') text += ',';
    text += "{\"path\":" + json::quote(item.path) + ",\"size\":" + std::to_string(item.size) +
            ",\"sha256\":" + json::quote(item.hash) + '}';
  }
  return text + "]}\n";
}
bool ordinary_tree(const std::filesystem::path& folder, std::vector<std::string>& actual,
                   std::string prefix = {}, unsigned depth = 0) {
  if (depth > 12 || actual.size() > 513) return false;
  for (const auto& item : fs::list(folder)) {
    if (item.link) return false;
    const auto path = prefix + fs::utf8(std::filesystem::path(item.name));
    if (item.directory) {
      if (!ordinary_tree(folder / item.name, actual, path + '/', depth + 1)) return false;
    } else actual.push_back(path);
  }
  return actual.size() <= 513;
}
}  // namespace

std::uint64_t now_filetime() {
  FILETIME time{};
  GetSystemTimeAsFileTime(&time);
  return (std::uint64_t(time.dwHighDateTime) << 32) | time.dwLowDateTime;
}
std::string utc(std::uint64_t filetime) {
  FILETIME time{static_cast<DWORD>(filetime), static_cast<DWORD>(filetime >> 32)};
  SYSTEMTIME value{};
  if (!FileTimeToSystemTime(&time, &value)) return {};
  char text[40]{};
  std::snprintf(text, sizeof(text), "%04u-%02u-%02uT%02u:%02u:%02u.%03uZ", value.wYear, value.wMonth,
                value.wDay, value.wHour, value.wMinute, value.wSecond, value.wMilliseconds);
  return text;
}
std::string classify(std::string_view log, std::string_view gpu_json, bool crash, bool oom) {
  bool device_lost = log.find("VK_ERROR_DEVICE_LOST") != log.npos || log.find("Exiting after GPU device loss") != log.npos;
  try {
    const auto data = json::parse(gpu_json);
    if (const auto event = data.find("event"); event && event->is_string()) device_lost |= event->as_string() == "device_lost";
  } catch (const json::Error&) { }
  if (oom || out_of_memory(log)) return "out_of_memory";
  if (device_lost) return "device_lost";
  if (log.find("Memory allocation failed") != log.npos) return "allocation_failed";
  if (log.find("Exception on CS thread") != log.npos) return "cs_exception";
  if (crash) return "crash";
  // This is the runtime's deliberate delayed-exit path, not resource destruction/map unload.
  if (log.find("RTX: Terminating application") != log.npos) return "clean";
  return "unknown";
}
std::string serialize(const PreviousSession& p) {
  return "{\"reason\":" + json::quote(p.reason) + ",\"time_utc\":" + json::quote(p.time_utc) +
         ",\"folder\":" + json::quote(p.folder) + '}';
}

void retain(const std::filesystem::path& root, const Limits& limits) {
  fs::refuse_links(root, kSessions);
  const auto sessions = fs::join(root, kSessions);
  if (!fs::stat(sessions).exists) return;
  struct Archive { std::filesystem::path path; std::uint64_t bytes; };
  std::vector<Archive> archives;
  for (const auto& entry : fs::list(sessions)) {
    if (!entry.directory || entry.link) continue;
    const auto folder = sessions / entry.name;
    try {
      const auto manifest = folder / "evidence.json";
      const auto info = fs::stat(manifest);
      if (!info.exists || info.link || info.directory) continue;
      const auto data = json::parse(fs::read_file(manifest, 512u << 10));
      if (!data.find("native_loader_session") || data.find("native_loader_session")->as_int() != 1) continue;
      const auto files = data.find("files");
      if (!files || files->as_array().size() > 512) continue;
      std::vector<std::string> expected{"evidence.json"}, actual;
      std::uint64_t size = info.size;
      bool intact = true;
      for (const auto& file : files->as_array()) {
        const auto path = file.find("path"), bytes = file.find("size"), digest = file.find("sha256");
        if (!path || !bytes || !digest || !paths::problem(path->as_string()).empty() || bytes->as_int() < 0) { intact = false; break; }
        fs::refuse_links(folder, path->as_string());
        const auto hash = fs::hash_file(fs::join(folder, path->as_string()));
        if (hash.size != static_cast<std::uint64_t>(bytes->as_int()) || hash.sha256 != digest->as_string()) { intact = false; break; }
        size += hash.size;
        expected.push_back(path->as_string());
      }
      if (!intact || !ordinary_tree(folder, actual)) continue;
      std::sort(expected.begin(), expected.end());
      std::sort(actual.begin(), actual.end());
      if (actual != expected) continue;  // user edits/additions are never retention fodder
      archives.push_back({folder, size});
    } catch (...) { }  // incomplete/locked/edited archives stay local
  }
  std::sort(archives.begin(), archives.end(), [](const auto& a, const auto& b) { return a.path.filename() > b.path.filename(); });
  std::uint64_t used = 0;
  std::size_t kept = 0;
  for (const auto& archive : archives) {
    if (kept < limits.sessions && archive.bytes <= limits.bytes - used) { ++kept; used += archive.bytes; continue; }
    fs::remove_tree(fs::win32(), archive.path);
  }
}

Result collect(const std::filesystem::path& root, std::uint64_t start, std::uint32_t process_id,
               const std::function<void()>& log_ready, const Limits& limits) {
  Result result;
  const auto began = std::chrono::steady_clock::now();
  bool signalled = false;
  const auto signal = [&] { if (!signalled) { signalled = true; if (log_ready) log_ready(); } };
  try {
    std::uint64_t since = 0;
    try {
      fs::refuse_links(root, kStart);
      const auto old = json::parse(fs::read_file(fs::join(root, kStart), 4096));
      if (const auto time = old.find("start_filetime"); time && time->is_number() && time->as_int() > 0)
        since = static_cast<std::uint64_t>(time->as_int());
    } catch (...) { }
    if (!since) {
      // First R6 start: startup.cpp has already rotated the old loader.log to loader.log.1.
      try {
        const auto old = tail(root, "native-loader/logs/loader.log.1", 64u << 10);
        constexpr std::string_view key = "\nstartup_filetime=";
        if (const auto at = old.find(key); at != old.npos) {
          const auto first = old.data() + at + key.size();
          if (std::from_chars(first, old.data() + old.size(), since).ec != std::errc{}) since = 0;
        }
      } catch (...) { }
    }
    // Clock rollback does not make historical crash files eligible again.
    const auto until = std::max(start, since);
    result.previous.time_utc = since ? utc(since) : "";
    fs::refuse_links(root, kStart);
    std::filesystem::create_directories(fs::join(root, "native-loader/logs"));
    start_record(root, start, process_id);
    const auto log = recent(root, kLog, since, until) ? tail(root, kLog, limits.tail_bytes) : std::string{};
    constexpr std::string_view gpu_path = "rtx-remix/logs/last_gpu_crash.json";
    const auto gpu = recent(root, gpu_path, since, until) ? tail(root, gpu_path, 64u << 10) : std::string{};
    std::vector<Source> found;
    sources(root, "rtx-remix/logs/.sentry-native", since, until, found, limits);
    sources(root, "rtx-remix/logs/.sentry-native/reports", since, until, found, limits);
    sources(root, "crashes", since, until, found, limits);
    sources(root, "native-loader/logs/gpu", since, until, found, limits, 2);
    std::sort(found.begin(), found.end(), [](const auto& a, const auto& b) { return a.time > b.time || (a.time == b.time && a.path < b.path); });
    bool crash = !found.empty(), oom = false;
    result.previous.reason = classify(log, gpu, crash);
    if (log.empty() && gpu.empty() && found.empty()) {
      signal();
    } else if (result.previous.reason == "clean" && !crash && gpu.empty()) {
      signal();
    } else {
      std::string name = utc(start);
      name.erase(std::remove(name.begin(), name.end(), ':'), name.end());
      const auto base = std::string(kSessions) + '/' + name + '-' + std::to_string(process_id) + '-';
      const auto staging = base + "collecting";
      fs::refuse_links(root, staging);
      // Never reuse a partial archive, even after a test/repeated invocation with the same clock.
      if (fs::stat(fs::join(root, staging)).exists) throw std::runtime_error("session evidence folder already exists");
      std::filesystem::create_directories(fs::join(root, staging));
      std::vector<Copy> copied;
      std::uint64_t remaining = limits.bytes - std::min<std::uint64_t>(limits.bytes, 1024);
      const auto save_tail = [&](std::string_view path, const std::string& text) {
        const auto overhead = path.size() + 160;
        if (text.empty() || overhead > remaining || text.size() > remaining - overhead) return;
        const auto target = staging + '/' + std::string(path);
        fs::refuse_links(root, target);
        std::filesystem::create_directories(fs::join(root, target).parent_path());
        auto file = fs::win32().create_file(fs::join(root, target));
        file->write(text.data(), text.size()); file->close();
        copied.push_back({std::string(path), sha256::of(text), text.size()});
        remaining -= text.size() + overhead;
      };
      if (!log.empty()) {
        const auto info = fs::stat(fs::join(root, kLog));
        if (!copy(root, {std::string(kLog), info.size, info.mtime}, staging + '/' + std::string(kLog), remaining, copied, oom)) {
          save_tail(kLog, log);
          result.notes.push_back("previous Remix log: kept its bounded tail; full copy unavailable or over the evidence limit");
        }
      }
      signal();  // the runtime may now truncate its own log; no subsequent read depends on it
      save_tail(gpu_path, gpu);
      for (const auto& source : found) {
        if (!copy(root, source, staging + '/' + source.path, remaining, copied, oom))
          result.notes.push_back("previous session evidence skipped (locked or over limit): " + source.path);
      }
      // This is supporting context, never by itself evidence of a crash. The sampler starts after collect.
      save_tail("native-loader/logs/memory.csv", tail(root, "native-loader/logs/memory.csv", limits.tail_bytes));
      save_tail("native-loader/logs/memory.1.csv", tail(root, "native-loader/logs/memory.1.csv", limits.tail_bytes));
      result.previous.reason = classify(log, gpu, crash, oom);
      fs::write_atomic(fs::win32(), fs::join(root, staging + "/evidence.json"), receipt(copied));
      const auto finished = base + result.previous.reason;
      fs::refuse_links(root, finished);
      fs::win32().move(fs::join(root, staging), fs::join(root, finished), false);
      result.previous.folder = finished;
      retain(root, limits);
    }
  } catch (const std::exception& error) {
    result.notes.push_back(std::string("previous session evidence: ") + error.what());
  }
  signal();
  result.elapsed_ms = std::chrono::duration<double, std::milli>(std::chrono::steady_clock::now() - began).count();
  return result;
}
}  // namespace nl::evidence
