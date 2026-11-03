#include "nl/status.h"
#include "nl/fs.h"
#include "nl/json.h"
#include <windows.h>
#include <sstream>

namespace nl::status {
namespace {
std::string strings(const std::vector<std::string>& values) {
  std::string result = "[";
  for (const auto& value : values) {
    if (result.size() > 1) result += ',';
    result += json::quote(value);
  }
  return result + ']';
}
std::string pairs(const std::vector<std::pair<std::string, std::string>>& values) {
  std::string result = "[";
  for (const auto& [name, value] : values) {
    if (result.size() > 1) result += ',';
    result += "{\"name\":" + json::quote(name) + ",\"value\":" + json::quote(value) + '}';
  }
  return result + ']';
}
const char* blocked_by(deploy::Report::BlockedBy reason) {
  switch (reason) {
    case deploy::Report::BlockedBy::running_game: return "running_game";
    case deploy::Report::BlockedBy::deployer_lock: return "deployer_lock";
    default: return "none";
  }
}
std::string session_json(const Session& s) {
  return "{\"cvars\":" + std::to_string(s.cvars) + ",\"cvars_exec\":" + json::quote(s.cvars_exec) +
         ",\"recorded\":" + std::to_string(s.recorded) + ",\"restore_values\":" + std::to_string(s.restore_values) +
         ",\"restore_exec\":" + json::quote(s.restore_exec) + ",\"patches\":" + std::to_string(s.patches) +
         ",\"patches_allowed\":" + (s.patches_allowed ? "true" : "false") + ",\"overrides\":" + strings(s.overrides) +
         ",\"hooks\":" + json::quote(s.hooks) + ",\"hidden_addons\":" + strings(s.hidden_addons) +
         ",\"module_dependencies\":" + strings(s.module_dependencies) + ",\"notes\":" + strings(s.notes) + "}";
}
std::string copies_json(const std::vector<activate::Plan::LayerCopy>& copies) {
  std::string result = "[";
  for (const auto& layer : copies) {
    if (result.size() > 1) result += ',';
    result += "{\"copy\":" + json::quote(layer.copy) + ",\"source\":" + json::quote(layer.source) + '}';
  }
  return result + ']';
}
std::string numbers(const std::vector<unsigned>& values) {
  std::string result = "[";
  for (const unsigned value : values) {
    if (result.size() > 1) result += ',';
    result += std::to_string(value);
  }
  return result + ']';
}
std::string reshade_json(const Reshade& s) {
  return "{\"outcome\":" + json::quote(s.outcome) + ",\"reason\":" + json::quote(s.reason) + ",\"package\":" +
         json::quote(s.plan.package) + ",\"layer\":" + json::quote(s.plan.layer_name) + ",\"layer_manifest\":" +
         json::quote(s.plan.layer_manifest) + ",\"folder\":" + json::quote(s.folder) + ",\"settings\":" + json::quote(s.settings) +
         ",\"presets\":" + strings(s.presets) + ",\"environment\":" + pairs(s.environment) + ",\"notes\":" + strings(s.notes) + "}";
}
std::string packages_json(const std::vector<PackageSource>& packages) {
  std::string out = "[";
  for (std::size_t i = 0; i < packages.size(); ++i) {
    const auto& p = packages[i];
    out += (i ? "," : "") + std::string("{\"id\":") + json::quote(p.id) + ",\"version\":" + json::quote(p.version) +
           ",\"source\":" + json::quote(p.source) + ",\"label\":" + json::quote(p.label) + ",\"time_updated\":" +
           (p.time_updated ? std::to_string(*p.time_updated) : std::string("null")) + "}";
  }
  return out + "]";
}
}  // namespace

std::string serialize(const Report& r) {
  const auto& d = r.deployment;
  const auto& a = r.activation;
  const auto& p = a.plan;
  std::string result = "{\n\"schema\":1,\"loader_version\":" + json::quote(r.loader_version) +
      ",\"previous_session\":" + evidence::serialize(r.previous_session) +
      ",\"utc\":" + json::quote(r.utc) + ",\"process_id\":" + std::to_string(r.process_id) +
      ",\"session_token\":" + json::quote(r.session_token) +
      ",\"startup_elapsed_ms\":" + std::to_string(r.startup_ms) + ",\n\"deployment\":{\"outcome\":" + json::quote(d.outcome) +
      ",\"reason\":" + json::quote(d.error) + ",\"blocked_by\":" + json::quote(blocked_by(d.blocked_by)) +
      ",\"generation\":" + std::to_string(d.generation) + ",\"recovered\":" + (d.recovered ? "true" : "false") +
      ",\"change_count\":" + std::to_string(d.changes.size()) + ",\"operations\":" + std::to_string(d.operations) +
      ",\"elapsed_ms\":" + std::to_string(r.deployment_ms) + ",\"packages\":" + strings(d.packages) +
      ",\"notes\":" + strings(d.notes) + ",\"skipped\":[";
  for (std::size_t i = 0; i < d.skipped.size(); ++i) {
    if (i) result += ',';
    result += "{\"package\":" + json::quote(d.skipped[i].package) + ",\"reason\":" + json::quote(d.skipped[i].reason) + '}';
  }
  result += "]},\n\"activation\":{\"outcome\":" + json::quote(a.outcome) + ",\"reason\":" + json::quote(a.reason) +
      ",\"elapsed_ms\":" + std::to_string(a.elapsed_ms) + ",\"windows_error\":" + std::to_string(a.windows_error) +
      ",\"rolled_back\":" + (a.rolled_back ? "true" : "false") + ",\"runtime\":{" +
      "\"id\":" + json::quote(p.runtime_id) + ",\"version\":" + json::quote(p.runtime_version) +
      ",\"folder\":" + json::quote(a.runtime_folder) + ",\"dll\":" + json::quote(a.runtime_dll) +
      "},\"system_vulkan_path\":" + json::quote(a.vulkan_path) + ",\"gpu_vendors\":" + numbers(p.gpu_vendors) +
      ",\"performance_tier\":" + performance::serialize(p.performance_tier) +
      ",\"memory\":" + (p.memory.reason.empty() ? std::string("null") : memory_profile::serialize(p.memory)) + ",\"notes\":" + strings(p.notes) +
      ",\"non_nvidia\":" + (p.non_nvidia ? "true" : "false") + ",\"environment\":{\"requested\":" + pairs(p.env) + ",\"set\":" + pairs(a.environment_set) +
      ",\"user_values_kept\":" + pairs(p.user_env) + "},\"layers\":{\"rtx\":" + strings(p.rtx_layers) +
      ",\"dxvk\":" + strings(p.dxvk_layers) + "},\"layer_copies\":" + copies_json(p.layer_copies) +
      ",\"launch_arguments\":{\"requested\":" + strings(p.launch_args) +
      ",\"added\":" + strings(a.arguments_added) + ",\"already_present\":" + strings(p.present_args) +
      ",\"fallback_launch_options\":" + json::quote(a.fallback_launch_options) +
      "},\"missing_system_dependencies\":" + strings(a.missing_system_dependencies) +
      ",\"preloaded\":" + strings(a.preloaded) + ",\"reshade\":" + reshade_json(a.reshade) + "},\n\"session\":" + session_json(r.session) + ",\n\"packages\":" + packages_json(r.packages) +
      ",\n\"errors\":" + strings(r.errors) + "\n}\n";
  return result;
}

std::string log_fields(const Report& r) {
  std::ostringstream out;
  out << "previous_session=" << evidence::serialize(r.previous_session) << '\n';
  out << "deployment.outcome=" << r.deployment.outcome << "\ndeployment.generation=" << r.deployment.generation
      << "\ndeployment.change_count=" << r.deployment.changes.size() << "\ndeployment.operations=" << r.deployment.operations
      << "\ndeployment.elapsed_ms=" << r.deployment_ms << "\ndeployment.recovered=" << r.deployment.recovered
      << "\ndeployment.blocked_by=" << blocked_by(r.deployment.blocked_by)
      << "\ndeployment.error=" << json::quote(r.deployment.error) << '\n';
  for (const auto& skipped : r.deployment.skipped)
    out << "deployment.skipped=" << json::quote(skipped.package + ": " + skipped.reason) << '\n';
  for (const auto& note : r.deployment.notes) out << "deployment.note=" << json::quote(note) << '\n';
  const auto& a = r.activation;
  out << "activation.outcome=" << a.outcome << "\nactivation.reason=" << json::quote(a.reason)
      << "\nactivation.runtime.id=" << a.plan.runtime_id << "\nactivation.runtime.version=" << a.plan.runtime_version
      << "\nactivation.runtime.folder=" << json::quote(a.runtime_folder) << "\nactivation.runtime.dll=" << json::quote(a.runtime_dll)
      << "\nactivation.system_vulkan_path=" << json::quote(a.vulkan_path)
      << "\nactivation.gpu_vendors=" << numbers(a.plan.gpu_vendors) << "\nactivation.non_nvidia=" << a.plan.non_nvidia
      << "\nactivation.performance_tier=" << performance::serialize(a.plan.performance_tier)
      << "\nactivation.memory=" << (a.plan.memory.reason.empty() ? std::string("null") : memory_profile::serialize(a.plan.memory))
      << "\nactivation.environment.set=" << pairs(a.environment_set) << "\nactivation.environment.user_values_kept=" << pairs(a.plan.user_env)
      << "\nactivation.layers.rtx=" << strings(a.plan.rtx_layers) << "\nactivation.layers.dxvk=" << strings(a.plan.dxvk_layers)
      << "\nactivation.layer_copies=" << copies_json(a.plan.layer_copies)
      << "\nactivation.arguments.added=" << strings(a.arguments_added) << "\nactivation.arguments.already_present=" << strings(a.plan.present_args)
      << "\nactivation.fallback_launch_options=" << json::quote(a.fallback_launch_options)
      << "\nactivation.windows_error=" << a.windows_error << "\nactivation.missing_system_dependencies=" << strings(a.missing_system_dependencies)
      << "\nactivation.preloaded=" << strings(a.preloaded) << "\nactivation.rolled_back=" << a.rolled_back << "\nactivation.elapsed_ms=" << a.elapsed_ms
      << "\nactivation.reshade=" << reshade_json(a.reshade) << '\n';
  for (const auto& note : a.plan.notes) out << "activation.note=" << json::quote(note) << '\n';
  out << "session=" << session_json(r.session) << '\n';
  for (const auto& error : r.errors) out << "error=" << json::quote(error) << '\n';
  out << "startup.elapsed_ms=" << r.startup_ms << "\nstartup.complete=1\n";
  return out.str();
}

void write(const std::filesystem::path& root, const Report& report) {
  const auto temporary = std::string(kPath) + ".tmp-" + std::to_string(report.process_id);
  fs::refuse_links(root, kPath);
  fs::refuse_links(root, temporary);
  auto& disk = fs::win32();
  for (const char* relative : {"garrysmod", "garrysmod/data", "garrysmod/data/native-loader"}) {
    const auto path = fs::join(root, relative);
    const auto info = fs::stat(path);
    if (!info.exists) {
      try { disk.create_directory(path); }
      catch (const fs::Error& error) {
        const auto raced = fs::stat(path);
        if (error.code() != ERROR_ALREADY_EXISTS || !raced.directory || raced.link) throw;
      }
    }
    else if (!info.directory || info.link) throw fs::Error("status parent is not an ordinary directory: " + fs::utf8(path), 0);
  }
  // Separate temp files let two game instances report concurrently; each final rename is atomic.
  const auto temp_path = fs::join(root, temporary);
  if (fs::stat(temp_path).exists) disk.remove_file(temp_path);
  const auto text = serialize(report);
  auto file = disk.create_file(temp_path);
  file->write(text.data(), text.size());
  file->close();
  disk.move(temp_path, fs::join(root, kPath), true);
  remove_stale_temporaries(root, report.process_id);
}

void remove_stale_temporaries(const std::filesystem::path& root, std::uint32_t own_process) noexcept {
  // A launch that crashed between creating and renaming its temp file leaves it behind; drop those
  // whose process is gone. Best effort: a file another instance holds simply stays.
  try {
    const auto folder = fs::join(root, kDirectory);
    for (const auto& item : fs::list(folder)) {
      const std::wstring_view name = item.name;
      constexpr std::wstring_view prefix = L"status.json.tmp-";
      if (item.directory || item.link || !name.starts_with(prefix) || name.size() == prefix.size() || name.size() > prefix.size() + 10)
        continue;
      std::uint64_t pid = 0;
      bool numeric = true;
      for (wchar_t c : name.substr(prefix.size())) {
        if (c < L'0' || c > L'9') numeric = false;
        else pid = pid * 10 + static_cast<std::uint64_t>(c - L'0');
      }
      if (!numeric || pid == own_process || pid > 0xffffffffull) continue;
      const HANDLE process = OpenProcess(SYNCHRONIZE, FALSE, static_cast<DWORD>(pid));
      if (process) {
        const bool alive = WaitForSingleObject(process, 0) == WAIT_TIMEOUT;
        CloseHandle(process);
        if (alive) continue;
      } else if (GetLastError() == ERROR_ACCESS_DENIED) {
        continue;  // cannot tell; leave it
      }
      try { fs::win32().remove_file(folder / item.name); } catch (...) {}
    }
  } catch (...) {
  }
}

void remove(fs::FileSystem& disk, const std::filesystem::path& root) {
  fs::refuse_links(root, kPath);
  // The RTX-session report and the generated cfgs (M5); a cfg only if the loader wrote it.
  for (const char* relative : {"garrysmod/cfg/nativeloader_session.cfg", "garrysmod/cfg/nativeloader_restore.cfg"}) {
    fs::refuse_links(root, relative);
    const auto path = fs::join(root, relative);
    const auto info = fs::stat(path);
    if (info.exists && !info.directory && !info.link && fs::read_file(path, 4096).rfind("// Generated by the GMod native loader", 0) == 0) {
      disk.remove_file(path);
    }
  }
  for (const auto& relative : {std::string(kPath), std::string(kPath) + ".tmp", std::string(kDirectory) + "/session.json"}) {
    fs::refuse_links(root, relative);
    const auto path = fs::join(root, relative);
    const auto info = fs::stat(path);
    if (info.exists) {
      if (info.directory || info.link) throw fs::Error("status is not an ordinary file: " + fs::utf8(path), 0);
      disk.remove_file(path);
    }
  }
  const auto folder = fs::join(root, kDirectory);
  if (fs::stat(folder).exists) {
    for (const auto& item : fs::list(folder)) {
      const std::wstring_view name = item.name;
      constexpr std::wstring_view prefix = L"status.json.tmp-";
      if (!name.starts_with(prefix) || name.size() == prefix.size()) continue;
      const auto suffix = name.substr(prefix.size());
      bool numeric = true;
      for (wchar_t c : suffix) if (c < L'0' || c > L'9') numeric = false;
      if (numeric && !item.directory && !item.link) disk.remove_file(folder / item.name);
    }
  }
  if (fs::empty_directory(folder)) disk.remove_directory(folder);
}
}  // namespace nl::status
