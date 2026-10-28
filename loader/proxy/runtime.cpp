#include "runtime.h"
#include "nl/fs.h"
#include "nl/paths.h"
#include <algorithm>
#include <stdexcept>

namespace nl::proxy {
namespace {
std::wstring wide(std::string_view value) {
  if (value.empty()) return {};
  const int count = MultiByteToWideChar(CP_UTF8, MB_ERR_INVALID_CHARS, value.data(), static_cast<int>(value.size()), nullptr, 0);
  if (!count) throw std::runtime_error("activation value is not valid UTF-8");
  std::wstring result(static_cast<std::size_t>(count), L'\0');
  if (!MultiByteToWideChar(CP_UTF8, MB_ERR_INVALID_CHARS, value.data(), static_cast<int>(value.size()), result.data(), count))
    throw std::runtime_error("cannot convert activation value to UTF-16");
  return result;
}
std::filesystem::path system_directory() {
  wchar_t buffer[32768]{};
  const UINT size = GetSystemDirectoryW(buffer, 32768);
  if (!size || size >= 32768) throw std::runtime_error("cannot locate System32");
  return std::filesystem::path(buffer);
}
bool same_path(const std::filesystem::path& a, const std::filesystem::path& b) {
  const auto left = a.lexically_normal().make_preferred();
  const auto right = b.lexically_normal().make_preferred();
  return CompareStringOrdinal(left.c_str(), -1, right.c_str(), -1, TRUE) == CSTR_EQUAL;
}
std::string options(const std::vector<std::string>& args) {
  std::string result;
  for (const auto& arg : args) { if (!result.empty()) result += ' '; result += arg; }
  return result;
}
}  // namespace

RuntimeActivation::~RuntimeActivation() { if (!committed_) rollback_guarded(*this); }
double RuntimeActivation::elapsed_ms() const noexcept {
  return started_ ? std::chrono::duration<double, std::milli>(std::chrono::steady_clock::now() - began_).count() : 0;
}
bool RuntimeActivation::rollback() noexcept {
  if (committed_) return true;
  bool ok = true;
  if (runtime_) { if (FreeLibrary(runtime_)) runtime_ = nullptr; else ok = false; }
  if (directory_changed_) { if (SetDllDirectoryW(nullptr)) directory_changed_ = false; else ok = false; }
  if (vulkan_) { if (FreeLibrary(vulkan_)) vulkan_ = nullptr; else ok = false; }
  if (!command_line_.restore()) ok = false;
  for (auto it = environment_.rbegin(); it != environment_.rend(); ++it) {
    if (!it->attempted) continue;
    if (SetEnvironmentVariableW(it->name.c_str(), it->previous ? it->previous->c_str() : nullptr)) it->attempted = false;
    else ok = false;
  }
  return ok;
}
bool rollback_guarded(RuntimeActivation& activation) noexcept {
  __try { return activation.rollback(); }
  __except (EXCEPTION_EXECUTE_HANDLER) { return false; }
}
void RuntimeActivation::commit() noexcept {
  command_line_.commit();
  committed_ = true;  // retain our module references and process settings for the game's lifetime
}

bool RuntimeActivation::apply(const std::filesystem::path& root, const journal::Generation& generation,
                              status::Activation& report) {
  began_ = std::chrono::steady_clock::now();
  started_ = true;
  const auto& plan = report.plan;
  if (!plan.runtime_dll.empty()) {
    report.runtime_dll = fs::utf8(std::filesystem::absolute(fs::join(root, plan.runtime_dll)));
    report.runtime_folder = fs::utf8(std::filesystem::absolute(fs::join(root, plan.runtime_dir)));
  }
  report.reason = plan.reason;
  if (!plan.activate) { report.elapsed_ms = elapsed_ms(); return false; }
  const auto fail = [&](std::string reason, DWORD error = 0) {
    report.outcome = "failed";
    report.reason = std::move(reason);
    report.windows_error = error;
    report.rolled_back = touched_;
    if (!rollback_guarded(*this)) report.reason += "; activation rollback failed";
    report.environment_set.clear();
    report.arguments_added.clear();
    report.vulkan_path.clear();
    report.elapsed_ms = elapsed_ms();
    return false;
  };

  wchar_t cwd[32768]{};
  const DWORD cwd_size = GetCurrentDirectoryW(32768, cwd);
  if (!cwd_size || cwd_size >= 32768 || !same_path(std::filesystem::absolute(root), std::filesystem::path(cwd)))
    return fail("working directory is not the game root");
  const auto dll = std::filesystem::absolute(fs::join(root, plan.runtime_dll)).lexically_normal();
  if (dll.native().size() >= MAX_PATH) return fail("runtime d3d9.dll path does not fit MAX_PATH");
  const auto check_file = [&](const std::string& relative) {
    const auto key = paths::fold(relative);
    const auto record = std::find_if(generation.files.begin(), generation.files.end(), [&](const auto& item) {
      return paths::fold(item.path) == key;
    });
    if (record == generation.files.end()) throw std::runtime_error("activation file is not recorded in the journal: " + relative);
    fs::refuse_links(root, relative);
    const auto file = fs::stat(fs::join(root, relative));
    if (!file.exists || file.directory || file.link || file.size != record->size)
      throw std::runtime_error("activation file is absent or has the wrong recorded size: " + relative);
  };
  check_file(plan.runtime_dll);
  const auto runtime = std::find_if(generation.packages.begin(), generation.packages.end(), [&](const auto& package) {
    return package.id == plan.runtime_id && package.remix.has_value();
  });
  if (runtime == generation.packages.end()) return fail("runtime package is absent from the committed generation");
  for (const auto& layer : runtime->remix->rtx_conf_layers) check_file(runtime->payload + '/' + layer);
  for (const auto& layer : runtime->remix->dxvk_conf_layers) check_file(runtime->payload + '/' + layer);

  // Capture every previous value and allocate every new value before applying the first setting.
  environment_.reserve(plan.env.size());
  for (const auto& [name, value] : plan.env) {
    const auto previous = activate::environment_value(name);
    environment_.push_back({wide(name), wide(value), previous ? std::optional(wide(*previous)) : std::nullopt, false});
  }
  for (auto& variable : environment_) {
    touched_ = true;
    variable.attempted = true;
    if (!SetEnvironmentVariableW(variable.name.c_str(), variable.value.c_str())) {
      const auto error = GetLastError();
      return fail("SetEnvironmentVariableW failed", error);
    }
  }
  command_line_ = cmdline::append_arguments(plan.launch_args);
  if (!command_line_.ok) {
    report.fallback_launch_options = options(plan.launch_args);
    return fail("command-line swap refused: " + command_line_.detail);
  }
  if (!plan.launch_args.empty()) touched_ = true;
  if (plan.prefer_system_vulkan) {
    const auto path = system_directory() / L"vulkan-1.dll";
    vulkan_ = LoadLibraryW(path.c_str());
    if (!vulkan_) { const auto error = GetLastError(); return fail("System32 vulkan-1.dll preload failed", error); }
    report.vulkan_path = fs::utf8(path);
    touched_ = true;
  }
  directory_changed_ = true;
  touched_ = true;
  if (!SetDllDirectoryW(dll.parent_path().c_str())) { const auto error = GetLastError(); return fail("SetDllDirectoryW failed", error); }
  runtime_ = LoadLibraryExW(dll.c_str(), nullptr, LOAD_WITH_ALTERED_SEARCH_PATH);
  if (!runtime_) {
    const DWORD error = GetLastError();
    const auto system = system_directory();
    for (const char* name : {"msvcp140.dll", "vcruntime140.dll", "vcruntime140_1.dll", "vulkan-1.dll"}) {
      if (GetFileAttributesW((system / wide(name)).c_str()) == INVALID_FILE_ATTRIBUTES)
        report.missing_system_dependencies.emplace_back(name);
    }
    return fail("runtime LoadLibraryExW failed (Windows error " + std::to_string(error) + ")", error);
  }
  wchar_t loaded[32768]{};
  const DWORD loaded_length = GetModuleFileNameW(runtime_, loaded, 32768);
  if (!loaded_length || loaded_length >= 32768 || !same_path(dll, std::filesystem::path(loaded)))
    return fail("loaded d3d9.dll does not match the selected runtime path");
  report.outcome = "active";
  report.reason = plan.reason;
  report.environment_set = plan.env;
  report.arguments_added = plan.launch_args;
  report.elapsed_ms = elapsed_ms();
  return true;
}
}  // namespace nl::proxy
