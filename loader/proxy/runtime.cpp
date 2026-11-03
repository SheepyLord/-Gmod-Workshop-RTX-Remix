#include "runtime.h"
#include "backend.h"
#include "../client/catalog.h"
#include "modules.h"
#include "presentation.h"
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
// Writes `text` to `relative` unless the file already holds exactly that (no-op starts write nothing).
void write_if_changed(const std::filesystem::path& root, std::string_view relative, const std::string& text) {
  fs::refuse_links(root, relative);
  const auto path = fs::join(root, relative);
  const auto info = fs::stat(path);
  if (info.exists && !info.directory && info.size == text.size() && fs::read_file(path, text.size() + 1) == text) return;
  fs::write_atomic(fs::win32(), path, text);
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
  if (hooks_installed_) {
    modules::uninstall();
    hooks_installed_ = false;
  }
  while (!preloaded_.empty()) {
    if (!FreeLibrary(preloaded_.back())) ok = false;
    preloaded_.pop_back();
  }
  if (runtime_) { if (FreeLibrary(runtime_)) runtime_ = nullptr; else ok = false; }
  if (directory_changed_) { if (SetDllDirectoryW(nullptr)) directory_changed_ = false; else ok = false; }
  if (dll_directory_) { if (RemoveDllDirectory(dll_directory_)) dll_directory_ = nullptr; else ok = false; }
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

std::vector<std::string> session_cvars(const std::filesystem::path& root, bool rtx, const session::Values& cvars,
                                       status::Session& report) {
  fs::refuse_links(root, session::kRecordPath);
  const auto record_path = fs::join(root, session::kRecordPath);
  std::optional<session::Record> record;
  if (fs::stat(record_path).exists) record = session::parse_record(fs::read_file(record_path, 1 << 20));
  fs::refuse_links(root, session::kConfigCfg);
  const auto config_path = fs::join(root, session::kConfigCfg);
  std::map<std::string, std::string> config;
  if (fs::stat(config_path).exists) config = session::parse_config(fs::read_file(config_path, 8 << 20));
  const auto plan = session::plan(rtx, cvars, record, config);
  const auto write_cfg = [&](std::string_view relative, const session::Values& values, std::string_view purpose) {
    if (!session::ours_or_absent(fs::join(root, relative))) {
      throw std::runtime_error(std::string(relative) + " exists and was not written by the loader");
    }
    write_if_changed(root, relative, session::cfg_text(values, purpose));
  };
  if (plan.write_session) write_cfg(session::kSessionCfg, plan.session, "RTX session");
  if (plan.write_restore) write_cfg(session::kRestoreCfg, plan.restore, "restore after RTX");
  if (plan.record.empty()) {
    if (fs::stat(record_path).exists) fs::win32().remove_file(record_path);
  } else {
    write_if_changed(root, session::kRecordPath, session::serialize(session::Record{plan.record, false, plan.record_session}));
  }
  report.cvars = plan.write_session ? plan.session.size() : 0;
  report.cvars_exec = plan.write_session ? "nativeloader_session.cfg" : "";
  report.recorded = plan.record.size();
  report.restore_values = plan.write_restore ? plan.restore.size() : 0;
  report.restore_exec = plan.write_restore ? "nativeloader_restore.cfg" : "";
  return plan.exec_args;
}

void mark_restore_issued(const std::filesystem::path& root) {
  auto record = session::parse_record(fs::read_file(fs::join(root, session::kRecordPath), 1 << 20));
  record.restore_issued = true;
  write_if_changed(root, session::kRecordPath, session::serialize(record));
}

bool RuntimeActivation::apply(const std::filesystem::path& root, const journal::Generation& generation,
                              status::Activation& report, status::Session& session,
                              const std::vector<std::pair<std::filesystem::path, std::filesystem::path>>& read_redirects) {
  began_ = std::chrono::steady_clock::now();
  started_ = true;
  const auto& plan = report.plan;
  if (!plan.runtime_dll.empty()) {
    report.runtime_dll = fs::utf8(std::filesystem::absolute(fs::join(root, plan.runtime_dll)));
    report.runtime_folder = fs::utf8(std::filesystem::absolute(fs::join(root, plan.runtime_dir)));
  }
  report.reason = plan.reason;
  if (!plan.activate) { report.elapsed_ms = elapsed_ms(); return false; }
  if (plan.reset_gpu_crash_dumps) {
    try { gpu_diagnostics::reset_next_start(root); }
    catch (const std::exception& error) {
      session.notes.push_back(std::string("GPU diagnostics next_start was not rearmed: ") + error.what());
    }
  }
  const auto fail = [&](std::string reason, DWORD error = 0) {
    report.outcome = "failed";
    report.reason = std::move(reason);
    report.windows_error = error;
    report.rolled_back = touched_;
    if (!rollback_guarded(*this)) report.reason += "; activation rollback failed";
    report.environment_set.clear();
    report.arguments_added.clear();
    report.vulkan_path.clear();
    report.reshade.environment.clear();
    if (report.reshade.outcome == "active") {
      report.reshade.outcome = "failed";
      report.reshade.reason = "the activation was rolled back";
    }
    report.elapsed_ms = elapsed_ms();
    return false;
  };

  wchar_t cwd[32768]{};
  const DWORD cwd_size = GetCurrentDirectoryW(32768, cwd);
  if (!cwd_size || cwd_size >= 32768 || !same_path(std::filesystem::absolute(root), std::filesystem::path(cwd)))
    return fail("working directory is not the game root");
  const auto dll = std::filesystem::absolute(fs::join(root, plan.runtime_dll)).lexically_normal();
  if (dll.native().size() >= MAX_PATH) return fail("runtime d3d9.dll path does not fit MAX_PATH");
  // Every file this start loads or hands to the runtime must be as deployed: the size and time the
  // journal recorded. A file changed since (in place, or while a second instance kept this start from
  // deploying) is not loaded (R1-008). Deployment checked the SHA-256 of everything it placed;
  // hashing the whole runtime (about 1 GiB) again at every start would cost seconds.
  const auto check_record = [&](const journal::File& record) {
    fs::refuse_links(root, record.path);
    const auto file = fs::stat(fs::join(root, record.path));
    if (!file.exists || file.directory || file.link || file.size != record.size || file.mtime != record.mtime)
      throw std::runtime_error("activation file is absent or changed since it was deployed: " + record.path);
  };
  const auto check_file = [&](const std::string& relative) {
    const auto key = paths::fold(relative);
    const auto record = std::find_if(generation.files.begin(), generation.files.end(), [&](const auto& item) {
      return paths::fold(item.path) == key;
    });
    if (record == generation.files.end()) throw std::runtime_error("activation file is not recorded in the journal: " + relative);
    check_record(*record);
  };
  check_file(plan.runtime_dll);
  const auto runtime = std::find_if(generation.packages.begin(), generation.packages.end(), [&](const auto& package) {
    return package.id == plan.runtime_id && package.remix.has_value();
  });
  if (runtime == generation.packages.end()) return fail("runtime package is absent from the committed generation");
  for (const auto& record : generation.files) {
    if (!runtime->payload.empty() && paths::within(record.path, runtime->payload)) check_record(record);
  }
  for (const auto& layer : runtime->remix->rtx_conf_layers) check_file(runtime->payload + '/' + layer);
  for (const auto& layer : runtime->remix->dxvk_conf_layers) check_file(runtime->payload + '/' + layer);
  for (const auto& item : plan.module_overrides) check_file(item.file);

  const auto layer_folder = [&] {
    const std::string folder(activate::kLayerFolder);
    fs::refuse_links(root, folder);
    if (!fs::stat(fs::join(root, folder)).exists) fs::win32().create_directory(fs::join(root, folder));
  };
  // The package's layers reach the runtime as copies with short names (ADR 0036, R3-017), written from
  // the files just checked, byte for byte. One that cannot be written is replaced by its source in the
  // lists, which may then be too long for the runtime; a note says so.
  std::vector<std::string> unwritten;
  for (const auto& layer : plan.layer_copies) {
    try {
      layer_folder();
      write_if_changed(root, layer.copy, fs::read_file(fs::join(root, layer.source), std::size_t{1} << 24));
    } catch (const std::exception& error) {
      unwritten.push_back(layer.copy);
      session.notes.push_back("the Remix layer " + layer.copy + " was not written (" + error.what() + "); the runtime reads " +
                              layer.source + " instead");
    }
  }
  if (!unwritten.empty()) activate::use_sources(report.plan, unwritten);

  if (plan.low_tier_fallback) {
    try {
      layer_folder();
      write_if_changed(root, activate::kTierLayer, activate::low_tier_layer_text());
    } catch (const std::exception& error) {
      activate::disable_performance_tier(report.plan, std::string("the built-in low-tier Remix layer was not written: ") + error.what());
    }
  }

  // Without an NVIDIA GPU, the loader's own Remix layer (ADR 0030), which DXVK_CONFIG_FILE lists. A
  // layer that cannot be written costs Remix's automatic preset, not the session (Remix skips a missing file).
  if (plan.non_nvidia) {
    try {
      layer_folder();
      write_if_changed(root, activate::kNonNvidiaLayer, activate::non_nvidia_layer_text());
    } catch (const std::exception& error) {
      session.notes.push_back(std::string("the non-NVIDIA Remix layer was not written: ") + error.what());
    }
  }

  // The memory profile's runtime budgets (R13, ADR 0101). A layer that cannot be written leaves the
  // runtime its own automatic budgets; an older memory.conf must not be read instead.
  if (!plan.memory.layer.empty()) {
    try {
      layer_folder();
      write_if_changed(root, activate::kMemoryLayer, memory_profile::layer_text(plan.memory));
    } catch (const std::exception& error) {
      activate::disable_memory_layer(report.plan, std::string("the memory layer was not written: ") + error.what());
    }
  }

  if (plan.gpu_crash_dumps) {
    try {
      const auto path = gpu_diagnostics::prepare(root);
      for (auto& [name, value] : report.plan.env) if (name == gpu_diagnostics::kDumpVariable) value = path;
      // Claim only after preparing the layer and destination, before the runtime can crash during
      // initialization. CREATE_NEW makes simultaneous game starts share a single next_start request.
      if (plan.gpu_crash_dumps_once && !gpu_diagnostics::consume_next_start(root))
        activate::disable_gpu_crash_dumps(report.plan, "GPU diagnostics next_start was claimed by another start; continuing without diagnostics");
    } catch (const std::exception& error) {
      activate::disable_gpu_crash_dumps(report.plan, std::string("GPU diagnostics were not enabled: ") + error.what());
    }
  }

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
  // Session console variables (M5): record the user's values, write the session cfg, +exec it. A
  // failure here costs the variables, not the session.
  std::vector<std::string> arguments = plan.launch_args;
  if (!plan.session_cvars.empty()) {
    try {
      const auto exec = session_cvars(root, true, plan.session_cvars, session);
      arguments.insert(arguments.end(), exec.begin(), exec.end());
    } catch (const std::exception& error) {
      session.notes.push_back(std::string("session console variables not applied: ") + error.what());
    }
  }
  const std::wstring original_command_line(GetCommandLineW());
  const auto backend_selection = backend::select(original_command_line, true);
  command_line_ = backend_selection.changed
      ? cmdline::rewrite_arguments(original_command_line, backend_selection.line, arguments)
      : cmdline::append_arguments(arguments);
  if (!command_line_.ok) {
    report.fallback_launch_options = options(plan.launch_args);
    return fail("command-line swap refused: " + command_line_.detail);
  }
  if (!arguments.empty() || backend_selection.changed) touched_ = true;
  if (plan.prefer_system_vulkan) {
    const auto path = system_directory() / L"vulkan-1.dll";
    vulkan_ = LoadLibraryW(path.c_str());
    if (!vulkan_) { const auto error = GetLastError(); return fail("System32 vulkan-1.dll preload failed", error); }
    report.vulkan_path = fs::utf8(path);
    touched_ = true;
  }
  // The runtime folder first among the PATH entries (ADR 0010), for bare-name loads early in the start.
  // It does not last: the process's PATH is rewritten without it before the runtime's late loads, which
  // are preloaded below instead (ADR 0030, RESEARCH.md section 27). SetDllDirectoryW would also take the
  // working directory out of the search, and the RTX fixes look up their engine modules as
  // "bin/win64/<name>.dll" relative to it (RESEARCH.md section 13).
  {
    const auto previous = activate::environment_value("PATH");
    std::wstring value = dll.parent_path().native();
    if (previous && !previous->empty()) value += L";" + wide(*previous);
    environment_.push_back({L"PATH", value, previous ? std::optional(wide(*previous)) : std::nullopt, true});
    touched_ = true;
    if (!SetEnvironmentVariableW(L"PATH", value.c_str())) { const auto error = GetLastError(); return fail("PATH update failed", error); }
  }
  // The runtime folder as a user folder too: loads that search the "safe" set (LOAD_LIBRARY_SEARCH_USER_DIRS,
  // or every load once some module calls SetDefaultDllDirectories, as Chromium's code in GMod can) read
  // it; the standard search does not (RESEARCH.md section 27).
  dll_directory_ = AddDllDirectory(dll.parent_path().c_str());
  if (dll_directory_) touched_ = true;
  else session.notes.push_back("AddDllDirectory for the runtime folder failed (Windows error " + std::to_string(GetLastError()) +
                               "); loads that search user folders will not find the runtime's DLLs");

  // ReShade (ADR 0028): the package's Vulkan layer, with its own settings folder, for this session.
  // The Vulkan loader reads the layer variables when the runtime creates its instance, ReShade its
  // base path when the layer loads. A ReShade that cannot be prepared costs ReShade, not the session.
  auto& shade = report.reshade;
  if (shade.plan.enable) {
    std::vector<std::pair<std::string, std::wstring>> values;
    try {
      check_file(shade.plan.layer_manifest);
      check_file(shade.plan.library);
      const auto folder = std::filesystem::absolute(fs::join(root, reshade::kFolder)).lexically_normal();
      const auto layers = std::filesystem::absolute(fs::join(root, shade.plan.layer_dir)).lexically_normal();
      if (folder.native().find(L';') != std::wstring::npos || layers.native().find(L';') != std::wstring::npos)
        throw std::runtime_error("the game's path holds a ';', which the Vulkan loader takes for a list separator");
      const auto prepared = reshade::prepare(root, shade.plan.settings);
      shade.folder = fs::utf8(folder);
      shade.settings = prepared.settings;
      shade.presets = prepared.presets;
      shade.notes = prepared.notes;
      // Ours first; a list the user set stays after it.
      const auto listed_first = [](const std::wstring& ours, const char* name) {
        const auto previous = activate::environment_value(name);
        return previous && !previous->empty() ? ours + L";" + wide(*previous) : ours;
      };
      values.emplace_back("VK_ADD_LAYER_PATH", listed_first(layers.native(), "VK_ADD_LAYER_PATH"));
      values.emplace_back("VK_INSTANCE_LAYERS", listed_first(wide(shade.plan.layer_name), "VK_INSTANCE_LAYERS"));
      if (const auto user = activate::environment_value("RESHADE_BASE_PATH_OVERRIDE"))
        shade.notes.push_back("RESHADE_BASE_PATH_OVERRIDE was \"" + *user + "\"; this session uses native-loader/reshade");
      values.emplace_back("RESHADE_BASE_PATH_OVERRIDE", folder.native());
      if (!activate::environment_value(std::string(reshade::kGlobalLayerOff))) values.emplace_back(reshade::kGlobalLayerOff, L"1");
    } catch (const std::exception& error) {
      shade.outcome = "failed";
      shade.reason = std::string("ReShade not enabled: ") + error.what();
      values.clear();
    }
    for (const auto& [name, value] : values) {
      const auto previous = activate::environment_value(name);
      environment_.push_back({wide(name), value, previous ? std::optional(wide(*previous)) : std::nullopt, true});
      touched_ = true;
      if (!SetEnvironmentVariableW(wide(name).c_str(), value.c_str())) {
        const auto error = GetLastError();
        return fail("SetEnvironmentVariableW failed for " + name, error);
      }
      shade.environment.emplace_back(name, fs::utf8(std::filesystem::path(value)));
    }
    if (!values.empty()) {
      shade.outcome = "active";
      shade.reason = shade.plan.reason;
    }
  }

  // Patch sets and module overrides (M5) for the engine DLLs that load after this point, and what
  // binary modules need loaded before them (ADR 0024).
  auto redirects = read_redirects;
  // Tier copies/fallbacks have now been prepared. The menu must describe this effective plan,
  // including a failed tier write, rather than a second hardware/config preview.
  const auto menu = presentation::prepare_main_menu(root, generation, &plan);
  for (const auto& redirect : menu.redirects) redirects.emplace_back(redirect.source, redirect.replacement);
  for (const auto& note : menu.notes) session.notes.push_back(note);
  if (!plan.patch_sets.empty() || !plan.module_overrides.empty() || !plan.module_dependencies.empty() || !redirects.empty()) {
    modules::Setup setup;
    setup.root = std::filesystem::absolute(root);
    setup.read_redirects = std::move(redirects);
    const bool general_patches = !plan.patch_sets_need_insecure || cmdline::has_arg(GetCommandLineW(), L"-insecure");
    std::size_t skipped_patches = 0;
    for (const auto& set : plan.patch_sets) {
      if (general_patches || (plan.allow_secure_rtx_render_patches && client::secure_render_patch_set(set.package, set.set))) {
        session.patches += set.set.patches.size();  // only what this session applies; session.json has each result
        setup.patch_sets.push_back(set.set);
      } else ++skipped_patches;
    }
    session.patches_allowed = !setup.patch_sets.empty();
    if (!general_patches && session.patches_allowed) session.notes.push_back("reviewed RTX rendering patches enabled without -insecure");
    if (skipped_patches) session.notes.push_back("other patch sets not applied: they need -insecure (config patch_sets.require_insecure)");
    for (const auto& item : plan.module_overrides) {
      setup.overrides.emplace_back(item.module, std::filesystem::absolute(fs::join(root, item.file)).lexically_normal());
      session.overrides.push_back(item.module);
    }
    for (const auto& item : plan.module_dependencies) {
      std::vector<std::filesystem::path> files;
      for (const auto& file : session::deployed_files(generation, root, item.load_first, session.notes)) {
        files.push_back(std::filesystem::absolute(fs::join(root, file)).lexically_normal());
      }
      setup.dependencies.emplace_back(std::filesystem::absolute(fs::join(root, item.module)).lexically_normal(), std::move(files));
      session.module_dependencies.push_back(item.module);
    }
    setup.session_json_base = "  \"process_id\": " + std::to_string(GetCurrentProcessId()) + ",\n";
    std::string error;
    if (!setup.patch_sets.empty() || !setup.overrides.empty() || !setup.dependencies.empty() || !setup.read_redirects.empty()) {
      // Owned before the call: install() can fail after publishing hooks, and rollback must undo them
      // then too (R1-002); uninstall() is safe whatever install() got to.
      hooks_installed_ = true;
      touched_ = true;
      if (!modules::install(std::move(setup), error)) return fail("module hooks: " + error);
      session.hooks = "installed";
    } else {
      session.hooks = "not needed";
    }
  } else {
    session.hooks = "not needed";
  }
  for (const auto& note : plan.notes) session.notes.push_back(note);
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
  // shaderapidx9.dll imports "d3d9.dll" by base name; that must now resolve to this module. A
  // d3d9.dll loaded before the entry point (from elsewhere) would win the binding instead.
  if (GetModuleHandleW(L"d3d9.dll") != runtime_)
    return fail("another d3d9.dll was already loaded; the engine would bind to it, not the runtime");
  // The runtime's late bare-name loads (ADR 0030): the fork probes its FSR DLL by name when it creates
  // the device, and NRC loads CUDA's runtime and compiler by name seconds later. By then no search finds
  // the runtime folder: the game's loads use the standard search, which never reads an AddDllDirectory
  // folder, and the process's PATH has been rewritten without it (RESEARCH.md section 27). Loaded now,
  // by absolute path (checked as deployed above), the late loads bind to these modules. One that does not
  // load costs its feature, as before, not the session.
  for (const auto& relative : plan.preload) {
    const auto file = std::filesystem::absolute(fs::join(root, relative)).lexically_normal();
    if (HMODULE module = LoadLibraryExW(file.c_str(), nullptr, LOAD_WITH_ALTERED_SEARCH_PATH)) {
      preloaded_.push_back(module);
      report.preloaded.push_back(fs::utf8(file));
    } else {
      session.notes.push_back("could not load " + fs::utf8(file.filename()) + " with the runtime (Windows error " +
                              std::to_string(GetLastError()) + "); the runtime will not find it later either");
    }
  }
  report.outcome = "active";
  if (backend_selection.changed)
    session.notes.push_back("RTX compatibility: shader API selection uses stock shaderapidx9 for this process; launch settings are unchanged");
  report.reason = plan.reason;
  report.environment_set = plan.env;
  report.arguments_added = arguments;
  report.elapsed_ms = elapsed_ms();
  return true;
}
}  // namespace nl::proxy
