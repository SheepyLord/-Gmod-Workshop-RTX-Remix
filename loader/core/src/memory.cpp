#include "nl/memory.h"
#include "nl/evidence.h"
#include "nl/fs.h"
#include "nl/json.h"
#include "nl/sha256.h"
#include <windows.h>
#include <psapi.h>
#include <dxgi1_4.h>
#include <algorithm>
#include <array>
#include <stdexcept>

namespace nl::memory {
namespace {
std::string number(const std::optional<std::uint64_t>& value) { return value ? std::to_string(*value) : ""; }
bool timestamp(std::string_view text) {
  if (text.size() != 24) return false;
  for (std::size_t i = 0; i < text.size(); ++i) {
    const char expected = i == 4 || i == 7 ? '-' : i == 10 ? 'T' : i == 13 || i == 16 ? ':' : i == 19 ? '.' : i == 23 ? 'Z' : 0;
    if (expected ? text[i] != expected : text[i] < '0' || text[i] > '9') return false;
  }
  return true;
}
bool valid_line(std::string_view line) {
  if (line.empty() || line.back() != '\n') return false;
  const auto comma = line.find(',');
  if (!timestamp(line.substr(0, comma))) return false;
  unsigned commas = 0;
  for (const char c : line.substr(24, line.size() - 25)) {
    if (c == ',') ++commas;
    else if (c < '0' || c > '9') return false;
  }
  return commas == 9;
}
struct Owned { std::string hash; std::size_t size = 0; };
Owned owned(std::string_view text) { return {sha256::of(text), text.size()}; }
bool matches(std::string_view text, const Owned& record, bool allow_row = false) {
  if (record.hash.empty()) return text.empty();
  if (text.size() < record.size || sha256::of(text.substr(0, record.size)) != record.hash) return false;
  return text.size() == record.size || (allow_row && text.size() - record.size <= 1024 && valid_line(text.substr(record.size)));
}
std::string read(const std::filesystem::path& root, std::string_view path, std::size_t bound) {
  fs::refuse_links(root, path);
  const auto file = fs::join(root, path);
  return fs::stat(file).exists ? fs::read_file(file, bound) : std::string{};
}
Owned record(const json::Value& index, std::string_view key) {
  const auto value = index.find(key);
  if (!value) return {};
  const auto hash = value->find("sha256"), size = value->find("size");
  if (!hash || !size || size->as_int() < 0) throw std::runtime_error("invalid memory history receipt");
  return {hash->as_string(), static_cast<std::size_t>(size->as_int())};
}
std::string serialize(const Owned& value) {
  return "{\"sha256\":" + json::quote(value.hash) + ",\"size\":" + std::to_string(value.size) + '}';
}
void parents(const std::filesystem::path& root, std::string_view path) {
  fs::refuse_links(root, path);
  std::filesystem::create_directories(fs::join(root, path).parent_path());
}
void preserve_recovered(const std::filesystem::path& root, std::string_view text) {
  // A flushed row beyond the last receipt could also be a user's valid CSV append. Keep its exact
  // bytes outside history rotation before adopting it, rather than guessing who wrote that row.
  const auto path = "native-loader/backup/edits/memory-" + sha256::of(text) + ".csv";
  parents(root, path);
  if (fs::stat(fs::join(root, path)).exists) {
    if (read(root, path, text.size()) != text) throw std::runtime_error("recovered memory backup was changed; kept unchanged");
  } else fs::write_atomic(fs::win32(), fs::join(root, path), text);
}
}  // namespace

bool commit_warning(std::uint64_t used, std::uint64_t limit) noexcept {
  // R6 map sessions: 11.07-16.18 GiB added system commit from bootstrap to a loaded map
  // (all tiers; see RESEARCH.md, R7-B). Reserve 18 GiB including transient/OS margin.
  // Lower tiers mostly save VRAM, so do not promise a smaller CPU commit requirement.
  // A 24 GiB total floor leaves room for Windows alongside that conservative reserve.
  if (!limit) return false;  // counter unavailable
  return limit < (24ull << 30) || limit - std::min(used, limit) < (18ull << 30);
}
std::string process_token() {
  FILETIME created{}, exited{}, kernel{}, user{};
  GetProcessTimes(GetCurrentProcess(), &created, &exited, &kernel, &user);
  return std::to_string(GetCurrentProcessId()) + '-' +
    std::to_string((std::uint64_t(created.dwHighDateTime) << 32) | created.dwLowDateTime);
}
struct Sampler::State {
  HMODULE dxgi = nullptr;
  IDXGIAdapter3* adapter = nullptr;
  ~State() { if (adapter) adapter->Release(); if (dxgi) FreeLibrary(dxgi); }
};
Sampler::Sampler(bool gpu) : state_(std::make_unique<State>()) {
  if (!gpu) return;
  state_->dxgi = LoadLibraryExW(L"dxgi.dll", nullptr, LOAD_LIBRARY_SEARCH_SYSTEM32);
  if (!state_->dxgi) return;
  using Create = HRESULT(WINAPI*)(REFIID, void**);
  const auto create = reinterpret_cast<Create>(GetProcAddress(state_->dxgi, "CreateDXGIFactory1"));
  IDXGIFactory1* factory = nullptr;
  if (!create || FAILED(create(__uuidof(IDXGIFactory1), reinterpret_cast<void**>(&factory)))) return;
  bool nvidia = false;
  std::uint64_t largest = 0;
  for (UINT index = 0; index < 32; ++index) {
    IDXGIAdapter1* adapter = nullptr;
    if (factory->EnumAdapters1(index, &adapter) != S_OK) break;
    DXGI_ADAPTER_DESC1 desc{};
    if (SUCCEEDED(adapter->GetDesc1(&desc)) && !(desc.Flags & DXGI_ADAPTER_FLAG_SOFTWARE)) {
      const bool candidate_nvidia = desc.VendorId == 0x10DE;
      if ((!nvidia && candidate_nvidia) || (nvidia == candidate_nvidia && (!state_->adapter || desc.DedicatedVideoMemory > largest))) {
        IDXGIAdapter3* selected = nullptr;
        if (SUCCEEDED(adapter->QueryInterface(__uuidof(IDXGIAdapter3), reinterpret_cast<void**>(&selected)))) {
          if (state_->adapter) state_->adapter->Release();
          state_->adapter = selected;
          largest = desc.DedicatedVideoMemory;
          nvidia = candidate_nvidia;
        }
      }
    }
    adapter->Release();
  }
  factory->Release();
}
Sampler::~Sampler() = default;
Sample Sampler::query(bool process) const {
  Sample sample;
  sample.time_utc = evidence::utc(evidence::now_filetime());
  const auto kernel = GetModuleHandleW(L"kernel32.dll");
  using ProcessInfo = BOOL(WINAPI*)(HANDLE, PPROCESS_MEMORY_COUNTERS, DWORD);
  using PerformanceInfo = BOOL(WINAPI*)(PPERFORMANCE_INFORMATION, DWORD);
  const auto get_process = reinterpret_cast<ProcessInfo>(GetProcAddress(kernel, "K32GetProcessMemoryInfo"));
  const auto get_performance = reinterpret_cast<PerformanceInfo>(GetProcAddress(kernel, "K32GetPerformanceInfo"));
  PROCESS_MEMORY_COUNTERS_EX counters{};
  counters.cb = sizeof(counters);
  if (process && get_process && get_process(GetCurrentProcess(), reinterpret_cast<PPROCESS_MEMORY_COUNTERS>(&counters), sizeof(counters))) {
    sample.private_bytes = counters.PrivateUsage;
    sample.working_set = counters.WorkingSetSize;
  }
  PERFORMANCE_INFORMATION performance{};
  performance.cb = sizeof(performance);
  if (get_performance && get_performance(&performance, sizeof(performance))) {
    sample.commit_total = std::uint64_t(performance.CommitTotal) * performance.PageSize;
    sample.commit_limit = std::uint64_t(performance.CommitLimit) * performance.PageSize;
    sample.available_ram = std::uint64_t(performance.PhysicalAvailable) * performance.PageSize;
  }
  if (process && state_->adapter) {
    DXGI_QUERY_VIDEO_MEMORY_INFO local{}, nonlocal{};
    if (SUCCEEDED(state_->adapter->QueryVideoMemoryInfo(0, DXGI_MEMORY_SEGMENT_GROUP_LOCAL, &local))) {
      sample.gpu_local_usage = local.CurrentUsage;
      sample.gpu_local_budget = local.Budget;
    }
    if (SUCCEEDED(state_->adapter->QueryVideoMemoryInfo(0, DXGI_MEMORY_SEGMENT_GROUP_NON_LOCAL, &nonlocal))) {
      sample.gpu_nonlocal_usage = nonlocal.CurrentUsage;
      sample.gpu_nonlocal_budget = nonlocal.Budget;
    }
  }
  return sample;
}
std::string_view csv_header() {
  return "time_utc,private_bytes,working_set_bytes,system_commit_bytes,system_commit_limit_bytes,available_ram_bytes,gpu_local_usage_bytes,gpu_local_budget_bytes,gpu_nonlocal_usage_bytes,gpu_nonlocal_budget_bytes\n";
}
std::string csv_line(const Sample& s) {
  if (!timestamp(s.time_utc)) throw std::runtime_error("memory sample needs an ISO UTC timestamp");
  return s.time_utc + ',' + number(s.private_bytes) + ',' + number(s.working_set) + ',' + number(s.commit_total) + ',' +
    number(s.commit_limit) + ',' + number(s.available_ram) + ',' + number(s.gpu_local_usage) + ',' + number(s.gpu_local_budget) +
    ',' + number(s.gpu_nonlocal_usage) + ',' + number(s.gpu_nonlocal_budget) + '\n';
}
void append(const std::filesystem::path& root, const Sample& sample, const Limits& limits) {
  const auto line = csv_line(sample);
  if (!limits.rows || csv_header().size() + line.size() > limits.bytes) throw std::runtime_error("memory history limit too small");
  auto active = read(root, kCsv, limits.bytes), rotated = read(root, kRotated, limits.bytes);
  if ((active.empty() && fs::stat(fs::join(root, kCsv)).exists) ||
      (rotated.empty() && fs::stat(fs::join(root, kRotated)).exists))
    throw std::runtime_error("empty memory history is unowned or edited; kept unchanged");
  const auto index_text = read(root, kIndex, 4096);
  Owned previous_active, previous_rotated;
  if (!index_text.empty()) {
    const auto index = json::parse(index_text);
    const auto schema = index.find("native_loader_memory");
    if (!schema || schema->as_int() != 1) throw std::runtime_error("unrecognized memory history receipt");
    previous_active = record(index, "active"); previous_rotated = record(index, "rotated");
  }
  // Missing active files are safe to recreate. A completed move may precede its receipt after a crash.
  const bool moved = !rotated.empty() && matches(rotated, previous_active, true);
  if ((!active.empty() && !matches(active, previous_active, true) && !(moved && active.starts_with(csv_header()) && valid_line(std::string_view(active).substr(csv_header().size())))) ||
      (!rotated.empty() && !matches(rotated, previous_rotated) && !moved))
    throw std::runtime_error("memory history changed or is unowned; kept unchanged");
  if (!active.empty() && !active.starts_with(csv_header())) throw std::runtime_error("invalid memory history header");
  if (!active.empty() && !matches(active, previous_active)) preserve_recovered(root, active);
  if (!rotated.empty() && !matches(rotated, previous_rotated) && !matches(rotated, previous_active)) preserve_recovered(root, rotated);
  parents(root, kCsv);
  if (!active.empty() && (static_cast<std::size_t>(std::count(active.begin(), active.end(), '\n')) - 1 >= limits.rows || active.size() + line.size() > limits.bytes)) {
    // Verify again immediately before replacing anything. A changed older file is never deleted.
    if (read(root, kCsv, limits.bytes) != active || read(root, kRotated, limits.bytes) != rotated)
      throw std::runtime_error("memory history changed during rotation");
    if (!rotated.empty()) fs::win32().remove_file(fs::join(root, kRotated));
    fs::refuse_links(root, kRotated);
    fs::win32().move(fs::join(root, kCsv), fs::join(root, kRotated), false);
    rotated = std::move(active); active.clear();
  }
  if (active.empty()) {
    active = csv_header();
    // Establish ownership of the first row before it is flushed (including immediately after a
    // rotation). A crash between the data and final receipt writes can then recover that one row.
    const auto pending = "{\"native_loader_memory\":1,\"active\":" + serialize(owned(active)) +
      ",\"rotated\":" + serialize(rotated.empty() ? Owned{} : owned(rotated)) + "}\n";
    fs::write_atomic(fs::win32(), fs::join(root, kIndex), pending);
  }
  active += line;
  // Atomic append-by-replacement leaves a whole flushed row even if the process dies while writing.
  // The files are small (<=256 KiB); the next receipt accepts exactly one newly flushed row.
  fs::write_atomic(fs::win32(), fs::join(root, kCsv), active);
  const auto receipt = "{\"native_loader_memory\":1,\"active\":" + serialize(owned(active)) +
      ",\"rotated\":" + serialize(rotated.empty() ? Owned{} : owned(rotated)) + "}\n";
  fs::write_atomic(fs::win32(), fs::join(root, kIndex), receipt);
}
void write_commit(const std::filesystem::path& root, const Sample& sample, std::string_view token) {
  const auto value = "{\"schema\":1,\"session_token\":" + json::quote(token) + ",\"time_utc\":" + json::quote(sample.time_utc) +
    ",\"commit_total\":" + (sample.commit_total ? number(sample.commit_total) : "null") +
    ",\"commit_limit\":" + (sample.commit_limit ? number(sample.commit_limit) : "null") +
    ",\"warning\":" + (commit_warning(sample.commit_total.value_or(0), sample.commit_limit.value_or(0)) ? "true" : "false") + "}\n";
  parents(root, kCommit);
  fs::write_atomic(fs::win32(), fs::join(root, kCommit), value);
}
}  // namespace nl::memory
