#include "nl/evidence.h"
#include "nl/fs.h"
#include "nl/json.h"
#include "nl/memory.h"
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
struct Ending { Exit exit; std::string token; bool quiet; };
struct Gate {
  Handle mutex;
  bool locked = false;
  explicit Gate(const std::filesystem::path& root) {
    auto path = fs::utf8(std::filesystem::absolute(root).lexically_normal());
    for (auto& c : path) if (c >= 'A' && c <= 'Z') c += 'a' - 'A';
    const auto digest = sha256::of(path);
    const auto name = L"Local\\NativeLoader.Evidence." + std::wstring(digest.begin(), digest.end());
    mutex.value = CreateMutexW(nullptr, FALSE, name.c_str());
    if (!mutex.value) { mutex.value = INVALID_HANDLE_VALUE; throw std::runtime_error("cannot create evidence mutex"); }
    const auto wait = WaitForSingleObject(mutex.value, 10000);
    locked = wait == WAIT_OBJECT_0 || wait == WAIT_ABANDONED;
    if (!locked) throw std::runtime_error("evidence collector is busy");
  }
  ~Gate() { if (locked) ReleaseMutex(mutex.value); }
};

// Diagnostic metadata needs atomic replacement, not the deployment journal's write-through
// durability. Avoid two disk-cache flushes on the otherwise empty startup path.
std::string start_text(std::uint64_t start, std::uint32_t process) {
  return "{\"schema\":1,\"start_filetime\":" + std::to_string(start) +
      ",\"time_utc\":" + json::quote(utc(start)) + ",\"process_id\":" + std::to_string(process) + "}\n";
}
void start_record(const std::filesystem::path& root, std::uint64_t start, std::uint32_t process) {
  const auto temporary = std::string(kStart) + ".tmp-" + std::to_string(process) + '-' + std::to_string(start);
  fs::refuse_links(root, temporary);
  fs::refuse_links(root, kStart);
  const auto from = fs::long_path(fs::join(root, temporary)), to = fs::long_path(fs::join(root, kStart));
  const auto text = start_text(start, process);
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
// Only a fresh sample from this process is supporting evidence. Never use the menu warning's
// much larger map reserve to diagnose a crash. <=512 MiB remaining is still only a likelihood.
bool exhausted(const std::filesystem::path& root, std::uint64_t since, std::uint64_t until, std::string_view token) {
  const auto first = utc(std::max(since, until - std::min(until, 300000000ull)));
  const auto last = utc(until);
  const auto near_limit = [](std::uint64_t used, std::uint64_t limit) {
    return limit && limit - std::min(used, limit) <= (512ull << 20);
  };
  try {
    const auto data = json::parse(tail(root, memory::kCommit, 4096));
    const auto id = data.find("session_token"), at = data.find("time_utc");
    const auto used = data.find("commit_total"), limit = data.find("commit_limit");
    if (id && id->as_string() == token && at && at->as_string() >= first && at->as_string() <= last &&
        used && used->is_number() && used->as_int() >= 0 && limit && limit->is_number() && limit->as_int() > 0)
      return near_limit(static_cast<std::uint64_t>(used->as_int()), static_cast<std::uint64_t>(limit->as_int()));
  } catch (const std::exception&) { }
  // The flushed CSV remains useful if the latest-only snapshot was unavailable. Its rows have no
  // PID; require the same start/end window and a complete, correctly shaped UTC row.
  std::string newest;
  bool result = false;
  for (const auto path : {memory::kCsv, memory::kRotated}) {
    const auto text = tail(root, path, 256u << 10);
    std::size_t begin = 0;
    for (auto end = text.find('\n'); end != text.npos; end = text.find('\n', begin)) {
      const std::string_view line(text.data() + begin, end - begin);
      begin = end + 1;
      if (line.size() < 25 || line[24] != ',' || std::count(line.begin(), line.end(), ',') != 9) continue;
      const auto at = std::string(line.substr(0, 24));
      if (at < first || at > last || at < newest) continue;
      std::array<std::string_view, 5> cells{};
      std::size_t cell = 0, offset = 0;
      while (cell < cells.size()) {
        const auto comma = line.find(',', offset);
        if (comma == line.npos) break;
        cells[cell++] = line.substr(offset, comma - offset); offset = comma + 1;
      }
      const auto number = [](std::string_view value, std::uint64_t& parsed) {
        const auto read = std::from_chars(value.data(), value.data() + value.size(), parsed);
        return read.ec == std::errc{} && read.ptr == value.data() + value.size();
      };
      std::uint64_t used = 0, limit = 0;
      if (cell == cells.size() && number(cells[3], used) && number(cells[4], limit) && limit) {
        newest = at; result = near_limit(used, limit);
      }
    }
  }
  return result;
}
std::string exit_record(const PreviousSession& previous, std::uint64_t since, std::uint64_t until,
                        std::uint32_t pid, const Ending& end) {
  return "{\"schema\":1,\"start_filetime\":" + std::to_string(since) + ",\"exit_filetime\":" + std::to_string(until) +
      ",\"process_id\":" + std::to_string(pid) + ",\"process_token\":" + json::quote(end.token) +
      ",\"exit_code\":" + std::to_string(end.exit.code) + ",\"dialog_suppressed\":" + (end.quiet ? "true" : "false") +
      ",\"abnormal\":" + (needs_report(previous.reason) ? "true" : "false") +
      ",\"previous_session\":" + serialize(previous) + "}\n";
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
bool needs_report(std::string_view reason) noexcept {
  return reason == "crash" || reason == "out_of_memory" || reason == "device_lost" ||
      reason == "allocation_failed" || reason == "cs_exception" || reason == "likely_out_of_memory";
}
std::string classify(std::string_view log, std::string_view gpu_json, bool crash, bool oom, std::optional<Exit> exit) {
  bool device_lost = log.find("VK_ERROR_DEVICE_LOST") != log.npos || log.find("Exiting after GPU device loss") != log.npos;
  try {
    const auto data = json::parse(gpu_json);
    if (const auto event = data.find("event"); event && event->is_string()) device_lost |= event->as_string() == "device_lost";
  } catch (const json::Error&) { }
  if (exit && (exit->code == 0xC0000017u || exit->code == 0xC000012Du || exit->code == 8 || exit->code == 14))
    return "out_of_memory";
  // A zero exit or an engine's deliberate quit wins over nonfatal log noise and memory pressure.
  // Explicit Remix fatal messages/fresh crash artifacts still explain a runtime that exits with 0.
  const bool fatal = oom || out_of_memory(log) || crash || (device_lost && !gpu_json.empty()) ||
      log.find("Exiting after GPU device loss") != log.npos ||
      log.find("Memory allocation failed") != log.npos || log.find("Exception on CS thread") != log.npos;
  if (exit && !fatal && (exit->code == 0 ||
      (exit->code < 0x80000000u && log.find("RTX: Terminating application") != log.npos))) return "clean";
  if (oom || out_of_memory(log)) return "out_of_memory";
  if (device_lost) return "device_lost";
  if (log.find("Memory allocation failed") != log.npos) return "allocation_failed";
  if (log.find("Exception on CS thread") != log.npos) return "cs_exception";
  if (exit && exit->code != 0 && exit->code < 0x80000000u && exit->commit_exhausted && !crash)
    return "likely_out_of_memory";
  if (exit && exit->code != 0) return "crash";
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

namespace {
Result collect_impl(const std::filesystem::path& root, std::uint64_t start, std::uint32_t process_id,
                    const std::function<void()>& log_ready, const Limits& limits, std::optional<Ending> ending) {
  Result result;
  const auto began = std::chrono::steady_clock::now();
  bool signalled = false;
  const auto signal = [&] { if (!signalled) { signalled = true; if (log_ready) log_ready(); } };
  try {
    Gate gate(root);  // serialize the observer and next-start collector before any runtime log truncation
    std::uint64_t since = 0;
    std::optional<PreviousSession> completed;
    if (ending) {
      since = start;
      if (tail(root, kStart, 4096) != start_text(start, process_id))
        throw std::runtime_error("exit observer session no longer matches; evidence left for the next start");
    } else {
      try {
        fs::refuse_links(root, kStart);
        const auto old = json::parse(fs::read_file(fs::join(root, kStart), 4096));
        if (const auto time = old.find("start_filetime"); time && time->is_number() && time->as_int() > 0)
          since = static_cast<std::uint64_t>(time->as_int());
        if (const auto end = old.find("end"); since && end) {
          const auto old_pid = old.find("process_id"), end_pid = end->find("process_id"), end_start = end->find("start_filetime");
          const auto previous = end->find("previous_session");
          if (!old_pid || !end_pid || !end_start || old_pid->as_int() != end_pid->as_int() ||
              end_start->as_int() != static_cast<std::int64_t>(since)) throw std::runtime_error("end identity mismatch");
          if (previous) {
            const auto reason = previous->find("reason"), time = previous->find("time_utc"), folder = previous->find("folder");
            if (!reason || !time || !folder) throw std::runtime_error("incomplete end marker");
            PreviousSession p{reason->as_string(), time->as_string(), folder->as_string()};
            if ((p.reason == "clean" || needs_report(p.reason)) &&
                (p.folder.empty() || (p.folder.starts_with(std::string(kSessions) + '/') && paths::problem(p.folder).empty())))
              completed = std::move(p);
          }
        }
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
    }
    // Clock rollback does not make historical crash files eligible again.
    const auto until = ending ? std::max(now_filetime(), since) : std::max(start, since);
    result.previous.time_utc = since ? utc(since) : "";
    fs::refuse_links(root, kStart);
    std::filesystem::create_directories(fs::join(root, "native-loader/logs"));
    if (!ending) start_record(root, start, process_id);
    if (completed) {
      result.previous = std::move(*completed);
      signal();
      result.elapsed_ms = std::chrono::duration<double, std::milli>(std::chrono::steady_clock::now() - began).count();
      return result;  // observer already archived the exact same session, including clean ends
    }
    if (ending) ending->exit.commit_exhausted = exhausted(root, since, until, ending->token);
    const auto exit = ending ? std::optional<Exit>(ending->exit) : std::nullopt;
    const auto log = recent(root, kLog, since, until) ? tail(root, kLog, limits.tail_bytes) : std::string{};
    constexpr std::string_view gpu_path = "rtx-remix/logs/last_gpu_crash.json";
    const auto gpu = recent(root, gpu_path, since, until) ? tail(root, gpu_path, 64u << 10) : std::string{};
    std::vector<Source> found;
    sources(root, "rtx-remix/logs/.sentry-native", since, until, found, limits);
    sources(root, "rtx-remix/logs/.sentry-native/reports", since, until, found, limits);
    sources(root, "crashes", since, until, found, limits);
    sources(root, "native-loader/logs/gpu", since, until, found, limits, 2);
    std::sort(found.begin(), found.end(), [](const auto& a, const auto& b) { return a.time > b.time || (a.time == b.time && a.path < b.path); });
    // Shader debug information is supporting context, not proof of an abnormal exit. Aftermath
    // writes .nvdbg during healthy sessions too; only actual dumps in that folder imply a crash.
    bool crash = std::any_of(found.begin(), found.end(), [](const auto& file) {
      if (!file.path.starts_with("native-loader/logs/gpu/")) return true;
      const auto extension = lower(fs::utf8(std::filesystem::path(file.path).extension()));
      return extension == ".nv-gpudmp" || extension == ".dmp";
    });
    bool oom = false;
    result.previous.reason = classify(log, gpu, crash, false, exit);
    if (log.empty() && gpu.empty() && found.empty() && !needs_report(result.previous.reason)) {
      signal();
    } else if (result.previous.reason == "clean" && (ending || (!crash && gpu.empty()))) {
      signal();
    } else {
      std::string name = utc(ending ? until : start);
      name.erase(std::remove(name.begin(), name.end(), ':'), name.end());
      const auto base = std::string(kSessions) + '/' + name + '-' + std::to_string(process_id) + '-';
      const auto staging = base + "collecting";
      fs::refuse_links(root, staging);
      // Never reuse a partial archive, even after a test/repeated invocation with the same clock.
      if (fs::stat(fs::join(root, staging)).exists) throw std::runtime_error("session evidence folder already exists");
      std::filesystem::create_directories(fs::join(root, staging));
      std::vector<Copy> copied;
      std::uint64_t remaining = limits.bytes - std::min<std::uint64_t>(limits.bytes, ending ? 8192 : 1024);
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
      if (ending) save_tail(memory::kCommit, tail(root, memory::kCommit, 4096));
      result.previous.reason = classify(log, gpu, crash, oom, exit);
      const auto finished = base + result.previous.reason;
      if (ending) {
        auto previous = result.previous; previous.folder = finished;
        remaining += std::min<std::uint64_t>(limits.bytes, 4096);
        save_tail("exit-report.json", exit_record(previous, since, until, process_id, *ending));
        if (std::none_of(copied.begin(), copied.end(), [](const auto& file) { return file.path == "exit-report.json"; }))
          throw std::runtime_error("exit report could not fit in evidence limit");
      }
      fs::write_atomic(fs::win32(), fs::join(root, staging + "/evidence.json"), receipt(copied));
      fs::refuse_links(root, finished);
      fs::win32().move(fs::join(root, staging), fs::join(root, finished), false);
      result.previous.folder = finished;
      retain(root, limits);
    }
    if (ending && tail(root, kStart, 4096) == start_text(start, process_id)) {
      auto record = start_text(start, process_id);
      record.resize(record.size() - 2);  // replace the closing object, preserving identity fields
      record += ",\"end\":" + exit_record(result.previous, since, until, process_id, *ending) + "}\n";
      fs::refuse_links(root, kStart);
      fs::write_atomic(fs::win32(), fs::join(root, kStart), record);
    }
  } catch (const std::exception& error) {
    result.notes.push_back(std::string("previous session evidence: ") + error.what());
  }
  signal();
  result.elapsed_ms = std::chrono::duration<double, std::milli>(std::chrono::steady_clock::now() - began).count();
  return result;
}
}  // namespace
Result collect(const std::filesystem::path& root, std::uint64_t start, std::uint32_t process_id,
               const std::function<void()>& log_ready, const Limits& limits) {
  return collect_impl(root, start, process_id, log_ready, limits, {});
}
Result finish(const std::filesystem::path& root, std::uint64_t start, std::uint32_t process_id,
              std::uint32_t exit_code, std::string_view process_token, bool quiet, const Limits& limits) {
  return collect_impl(root, start, process_id, {}, limits, Ending{Exit{exit_code}, std::string(process_token), quiet});
}
}  // namespace nl::evidence
