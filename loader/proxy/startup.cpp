#include "bootstrap.h"
#include "modules.h"
#include "presentation.h"
#include "runtime.h"
#include "telemetry.h"
#include "observer.h"
#include "early.h"
#include "../client/catalog.h"
#include "nl/activate.h"
#include "nl/fs.h"
#include "nl/memory.h"
#include "nl/session.h"
#include "nl/startup.h"
#include "nl/status.h"
#include "nl/version.h"
#include <chrono>
#include <cstdio>
#include <cwchar>
#include <filesystem>
#include <future>
#include <sstream>
#include <stdexcept>
#include <string>
#include <system_error>

namespace nl::proxy {
namespace {
std::string utf8(std::wstring_view value) {
  if (value.empty()) return {};
  const int size = WideCharToMultiByte(CP_UTF8, 0, value.data(), static_cast<int>(value.size()), nullptr, 0, nullptr, nullptr);
  if (!size) throw std::runtime_error("UTF-8 conversion failed");
  std::string result(static_cast<std::size_t>(size), '\0');
  if (!WideCharToMultiByte(CP_UTF8, 0, value.data(), static_cast<int>(value.size()), result.data(), size, nullptr, nullptr))
    throw std::runtime_error("UTF-8 conversion failed");
  return result;
}

std::string utc_now() {
  SYSTEMTIME utc{};
  GetSystemTime(&utc);
  char timestamp[40]{};
  std::snprintf(timestamp, sizeof(timestamp), "%04u-%02u-%02uT%02u:%02u:%02u.%03uZ",
                utc.wYear, utc.wMonth, utc.wDay, utc.wHour, utc.wMinute, utc.wSecond, utc.wMilliseconds);
  return timestamp;
}

// True if no folder between the game root and loader.log, nor the file, is a link or junction
// (R1-001): every append checks this, as write_log does through fs::refuse_links. No allocation, so
// the emergency log can use it; the buffer is static because only the start-up thread logs.
bool log_path_ordinary() noexcept {
  static wchar_t prefix[kPathCapacity];
  const wchar_t* path = g_bootstrap.log_path;
  const std::size_t length = wcsnlen(path, kPathCapacity);
  const std::size_t root = wcsnlen(g_bootstrap.root, kPathCapacity);
  if (!length || length >= kPathCapacity || root >= length) return false;
  for (std::size_t end = root + 1; end <= length; ++end) {
    if (end < length && path[end] != L'\\' && path[end] != L'/') continue;
    wmemcpy(prefix, path, end);
    prefix[end] = L'\0';
    const DWORD attributes = GetFileAttributesW(prefix);
    if (attributes == INVALID_FILE_ATTRIBUTES) return end == length;  // only the log itself may be missing
    if (attributes & FILE_ATTRIBUTE_REPARSE_POINT) return false;
  }
  return true;
}

void write_log(const status::Report& report) {
  LARGE_INTEGER begin{}, frequency{};
  QueryPerformanceCounter(&begin);
  QueryPerformanceFrequency(&frequency);
  FILETIME filetime{};
  GetSystemTimeAsFileTime(&filetime);
  const auto startup_time = (static_cast<unsigned long long>(filetime.dwHighDateTime) << 32) | filetime.dwLowDateTime;
  // Sample these before the logging/filesystem work.
  const bool engine = GetModuleHandleW(L"engine.dll") != nullptr;
  const bool shaderapi = GetModuleHandleW(L"shaderapidx9.dll") != nullptr;
  const bool d3d9 = GetModuleHandleW(L"d3d9.dll") != nullptr;
  fs::refuse_links(std::filesystem::path(g_bootstrap.root), "native-loader/logs/loader.log");
  const std::filesystem::path log_path(g_bootstrap.log_path);
  std::filesystem::create_directories(log_path.parent_path());
  for (int index = 5; index >= 1; --index) {
    const auto destination = std::filesystem::path(log_path.wstring() + L"." + std::to_wstring(index));
    const auto source = index == 1 ? log_path : std::filesystem::path(log_path.wstring() + L"." + std::to_wstring(index - 1));
    if (index == 5) std::filesystem::remove(destination);
    if (std::filesystem::exists(source)) std::filesystem::rename(source, destination);
  }
  wchar_t working_directory[kPathCapacity]{};
  const DWORD cwd_length = GetCurrentDirectoryW(kPathCapacity, working_directory);
  std::ostringstream log;
  log << "native_loader_version=" NL_VERSION_STRING "\nutc=" << report.utc
      << "\nprocess_id=" << GetCurrentProcessId()
      << "\nphase=exe_entry_point\nentry_point_restored=1\nstartup_filetime=" << startup_time
      << "\nexe_path=" << utf8(g_bootstrap.exe) << "\ngame_root=" << utf8(g_bootstrap.root)
      << "\nworking_directory=" << (cwd_length && cwd_length < kPathCapacity ? utf8(working_directory) : "<unavailable>")
      << "\ncommand_line=" << utf8(GetCommandLineW())
      << "\nhost_matches=" << g_bootstrap.activation.host_matches
      << "\noff_switch.command_line=" << g_bootstrap.activation.command_line_disabled
      << "\noff_switch.environment=" << g_bootstrap.activation.environment_disabled
      << "\noff_switch.disable_file=" << g_bootstrap.activation.file_disabled
      << "\nsystem_winmm=" << utf8(g_bootstrap.system_winmm)
      << "\nsystem_winmm.load_error=" << g_bootstrap.system_load_error
      << "\nexports.resolved=" << g_bootstrap.resolved_exports << "\nexports.total=" << kExportCount
      << "\nmodule.engine.dll=" << engine << "\nmodule.shaderapidx9.dll=" << shaderapi << "\nmodule.d3d9.dll=" << d3d9 << '\n';
  for (std::size_t i = 0; i < kExportCount; ++i) {
    if (g_bootstrap.missing_exports[i]) log << "missing_export=" << (kExports[i].name ? kExports[i].name : "<ordinal-only>")
                                          << " @" << kExports[i].ordinal << " (zero-return stub)\n";
  }
  LARGE_INTEGER end{};
  QueryPerformanceCounter(&end);
  log << "bootstrap.log_ready=1\nelapsed_ms=" << (frequency.QuadPart ? (end.QuadPart - begin.QuadPart) * 1000.0 / frequency.QuadPart : 0.0) << '\n';
  const auto text = log.str();
  const HANDLE file = CreateFileW(log_path.c_str(), GENERIC_WRITE, FILE_SHARE_READ, nullptr, CREATE_ALWAYS, FILE_ATTRIBUTE_NORMAL, nullptr);
  if (file == INVALID_HANDLE_VALUE) throw std::system_error(static_cast<int>(GetLastError()), std::system_category(), "open loader.log");
  DWORD written{};
  const bool success = WriteFile(file, text.data(), static_cast<DWORD>(text.size()), &written, nullptr) && written == text.size();
  const DWORD error = success ? ERROR_SUCCESS : GetLastError();
  CloseHandle(file);
  if (!success) throw std::system_error(static_cast<int>(error), std::system_category(), "write loader.log");
}

struct StartupContext {
  std::chrono::steady_clock::time_point began = std::chrono::steady_clock::now();
  std::filesystem::path root{g_bootstrap.root};
  status::Report report;
  startup::Prepared prepared;
  std::vector<std::pair<std::filesystem::path, std::filesystem::path>> read_redirects;
  std::filesystem::path early_guard_source;
  RuntimeActivation runtime;
  std::future<evidence::Result> evidence_worker;
  std::future<void> evidence_log_ready;
  StartupContext() {
    report.loader_version = NL_VERSION_STRING;
    report.utc = utc_now();
    report.process_id = GetCurrentProcessId();
    report.session_token = memory::process_token();
    report.deployment.action = "apply";
    report.deployment.outcome = "skipped";
  }
};

void finish_report(StartupContext& context) {
  if (context.evidence_worker.valid()) {
    auto evidence = context.evidence_worker.get();
    context.report.previous_session = std::move(evidence.previous);
    for (auto& note : evidence.notes) context.report.session.notes.push_back(std::move(note));
    context.report.session.notes.push_back("previous session evidence collected in " + std::to_string(evidence.elapsed_ms) + " ms (worker)");
  }
  if (context.prepared.config.from_file && context.prepared.config.enabled) {
    const auto note = telemetry::start(context.root, context.prepared.config.memory_telemetry);
    if (!note.empty()) context.report.session.notes.emplace_back(note);
  }
  context.report.startup_ms = std::chrono::duration<double, std::milli>(std::chrono::steady_clock::now() - context.began).count();
  status::write(context.root, context.report);
  const auto text = status::log_fields(context.report);
  if (!log_path_ordinary()) throw std::runtime_error("loader.log is reached through a link; not appended");
  const HANDLE file = CreateFileW(g_bootstrap.log_path, FILE_APPEND_DATA, FILE_SHARE_READ, nullptr,
                                  OPEN_EXISTING, FILE_ATTRIBUTE_NORMAL, nullptr);
  if (file == INVALID_HANDLE_VALUE) throw std::system_error(static_cast<int>(GetLastError()), std::system_category(), "append loader.log");
  DWORD written{};
  const bool ok = WriteFile(file, text.data(), static_cast<DWORD>(text.size()), &written, nullptr) && written == text.size();
  const DWORD error = ok ? ERROR_SUCCESS : GetLastError();
  CloseHandle(file);
  if (!ok) throw std::system_error(static_cast<int>(error), std::system_category(), "append loader.log");
}

void restore_session_cvars(StartupContext& context) noexcept {
  auto& report = context.report.session;
  try {
    // Only with a journal that could be read: an invalid one leaves the process a pure pass-through,
    // and the record waits for a start that can read it (R1-004).
    if (!context.prepared.journal) return;
    // The deployed session variables tell a value the user changed since the RTX session from one
    // the session set, for records written before they held the session values themselves.
    session::Values deployed;
    if (context.prepared.journal->current) {
      for (const auto& package : context.prepared.journal->current->packages) {
        deployed.insert(deployed.end(), package.session.cvars.begin(), package.session.cvars.end());
      }
    }
    const auto exec = session_cvars(context.root, false, deployed, report);
    if (exec.empty()) return;
    auto swap = cmdline::append_arguments(exec);
    if (!swap.ok) {
      report.notes.push_back("restore not run: the command-line swap was refused: " + swap.detail);
      report.restore_exec.clear();
      return;
    }
    swap.commit();
    mark_restore_issued(context.root);
  } catch (const std::exception& error) {
    report.notes.push_back(std::string("restore not run: ") + error.what());
    report.restore_exec.clear();
  }
}

// Without a runtime, the add-on folders of packages marked requires_remix are left out of GMod's
// searches of garrysmod\addons, so their Lua does not run (ADR 0013). Nothing on disk changes. What
// binary modules need loaded before them applies here too (ADR 0024): the package's modules are on
// disk in every session, and another add-on (a Workshop copy) may load them.
void hide_rtx_addons(StartupContext& context) noexcept {
  auto& report = context.report.session;
  try {
    if (!context.prepared.journal || !context.prepared.journal->current) return;
    auto names = session::hidden_addons(*context.prepared.journal->current);
    const auto dependencies = session::module_dependencies(*context.prepared.journal->current);
    if (names.empty() && dependencies.empty() && context.read_redirects.empty()) return;
    modules::Setup setup;
    setup.root = std::filesystem::absolute(context.root);
    setup.read_redirects = context.read_redirects;
    setup.hidden_addons = names;
    std::vector<std::string> modules;
    for (const auto& item : dependencies) {
      std::vector<std::filesystem::path> files;
      for (const auto& file : session::deployed_files(*context.prepared.journal->current, context.root, item.load_first, report.notes)) {
        files.push_back(std::filesystem::absolute(fs::join(context.root, file)).lexically_normal());
      }
      setup.dependencies.emplace_back(std::filesystem::absolute(fs::join(context.root, item.module)).lexically_normal(), std::move(files));
      modules.push_back(item.module);
    }
    setup.session_json_base = "  \"process_id\": " + std::to_string(GetCurrentProcessId()) + ",\n";
    std::string error;
    if (!modules::install(std::move(setup), error)) {
      report.notes.push_back("add-on folders not hidden, module dependencies not loaded: " + error);
      return;
    }
    report.hidden_addons = std::move(names);
    report.module_dependencies = std::move(modules);
    report.hooks = "installed";
  } catch (const std::exception& error) {
    report.notes.push_back(std::string("add-on folders not hidden, module dependencies not loaded: ") + error.what());
  }
}

void failed_startup(StartupContext& context, const char* message, DWORD error) noexcept {
  // A committed runtime is loaded and initialised: unloading it now would be riskier than keeping
  // it, so a failure after the commit (only reporting is left by then) is logged, nothing undone.
  const bool committed = context.runtime.committed();
  const bool restored = committed || rollback_guarded(context.runtime);
  emergency_log(message, error);
  try {
    if (!committed) {
      auto& activation = context.report.activation;
      activation.outcome = "failed";
      activation.reason = message;
      activation.windows_error = error;
      activation.rolled_back = context.runtime.touched();
      activation.environment_set.clear();
      activation.arguments_added.clear();
      activation.vulkan_path.clear();
      activation.elapsed_ms = context.runtime.elapsed_ms();
    }
    context.report.errors.emplace_back(message);
    if (!restored) context.report.errors.emplace_back("activation rollback failed");
    finish_report(context);
  } catch (...) {
    emergency_log(committed ? "startup report could not be written; the runtime stays active"
                            : "startup failure report could not be written; continuing vanilla", error);
  }
}

void startup_cxx(StartupContext& context) noexcept {
  try {
    // The log is for diagnosis only: a log that cannot be written (open in a viewer, read-only
    // folder) must not keep the runtime from starting.
    try {
      write_log(context.report);
    } catch (const std::exception& error) {
      emergency_log("loader.log could not be written; continuing", 0);
      context.report.errors.emplace_back(std::string("loader.log: ") + error.what());
    }
    context.prepared = startup::prepare(context.root, context.report.process_id);
    context.report.deployment = context.prepared.deployment;
    context.report.packages = context.prepared.sources;
    context.report.deployment_ms = context.prepared.elapsed_ms;
    if (context.prepared.journal && context.prepared.journal->current)
      context.report.deployment.generation = context.prepared.journal->current->number;
    if (context.prepared.config.from_file && context.prepared.config.enabled) {
      // Start outside loader lock. Full log copying overlaps planning/presentation; dump copying
      // overlaps runtime activation. The report joins the worker before the engine entry point.
      try {
        auto ready = std::make_shared<std::promise<void>>();
        auto signal = ready->get_future();
        const auto root = context.root;
        const auto start = evidence::now_filetime();
        const auto process = context.report.process_id;
        context.evidence_worker = std::async(std::launch::async, [root, start, process, ready] {
          SetThreadPriority(GetCurrentThread(), THREAD_PRIORITY_BELOW_NORMAL);
          return evidence::collect(root, start, process, [ready] { ready->set_value(); });
        });
        context.evidence_log_ready = std::move(signal);
        // Bind the external observer to the recorded session before loading any runtime code.
        // It remains alive if this process cannot allocate, fail-fasts or overflows its stack.
        context.evidence_log_ready.wait();
        context.report.session.notes.push_back(observer::start(start));
      } catch (const std::exception& error) {
        context.report.session.notes.push_back(std::string("previous session evidence worker unavailable: ") + error.what());
      }
    }
    if (context.prepared.config.from_file && context.prepared.config.enabled && context.prepared.journal &&
        context.prepared.journal->current && !context.prepared.journal->pending) {
      try {
        auto display = presentation::prepare(context.root, *context.prepared.journal->current);
        for (auto& redirect : display.redirects) context.read_redirects.emplace_back(std::move(redirect.source), std::move(redirect.replacement));
        for (auto& note : display.notes) context.report.session.notes.push_back(std::move(note));
      } catch (const std::exception& error) {
        context.report.session.notes.push_back(std::string("native package presentation unavailable: ") + error.what());
      }
    }
    if (context.prepared.may_activate) {
      const journal::Generation none;
      const auto& generation = context.prepared.journal && context.prepared.journal->current ? *context.prepared.journal->current : none;
      context.report.activation.plan = activate::plan(generation, context.prepared.config, activate::environment_value, GetCommandLineW(),
                                                      activate::primary_display, activate::graphics_adapters,
                                                      gpu_diagnostics::probe(context.root));
      if (context.report.activation.plan.activate) {
        // The configuration ADR 0052 found crashing: vanilla with the reason instead (ADR 0056).
        if (auto refusal = client::render_recipes_refusal(context.report.activation.plan, GetCommandLineW()); !refusal.empty()) {
          auto& activation = context.report.activation;
          activation.plan.activate = false;
          activation.plan.reason = std::move(refusal);
          activation.outcome = "failed";
          context.report.session.notes.push_back("RTX skipped; continuing vanilla");
        }
      }
      if (context.report.activation.plan.activate) {
        // A guard that cannot be prepared early never costs RTX (ADR 0056): the companion's guard
        // then installs from its autorun, later, and the note says why.
        try {
          if (auto early = guard::prepare(context.root, context.prepared.config, generation,
                                           context.report.activation.plan.runtime_id)) {
            context.early_guard_source = early->source;
            if (!early->kept.empty())
              context.report.session.notes.push_back("the changed render guard cache was kept at " + early->kept + " and written again");
            context.read_redirects.emplace_back(std::move(early->source), std::move(early->replacement));
            context.report.session.notes.push_back("verified client render guard prepared before addon autorun");
          }
        } catch (const std::exception& error) {
          context.report.session.notes.push_back(std::string("early render guard unavailable (") + error.what() +
                                                 "); the companion guard installs at autorun time instead");
        }
        // ReShade (ADR 0028) is decided for RTX sessions only; a problem reading for it costs ReShade.
        auto& shade = context.report.activation.reshade;
        try {
          shade.plan = reshade::plan(generation, context.prepared.config, reshade::probe(context.root, generation));
        } catch (const std::exception& error) {
          shade.plan.reason = std::string("ReShade not checked: ") + error.what();
        }
        shade.reason = shade.plan.reason;
      }
      // A runtime can truncate remix-dxvk.log from its DLL initializer, before creating a device.
      if (context.evidence_log_ready.valid()) context.evidence_log_ready.get();
      context.runtime.apply(context.root, generation, context.report.activation, context.report.session, context.read_redirects);
      if (context.report.activation.outcome != "active" && !context.early_guard_source.empty()) {
        // Display redirects remain useful in vanilla fallback; executable guard source is RTX-only.
        std::erase_if(context.read_redirects, [&](const auto& redirect) {
          return redirect.first == context.early_guard_source;
        });
      }
    } else {
      context.report.activation.reason = context.prepared.reason;
    }
    // Commit before reporting: the runtime's own start-up code has run, and a report that cannot be
    // written is no reason to unload it (see failed_startup).
    if (context.report.activation.outcome == "active") context.runtime.commit();
    // Without RTX, put back console variables an earlier RTX session changed (M5, ADR 0010), and keep
    // RTX-only add-ons out of the session (ADR 0013).
    if (context.report.activation.outcome != "active" && context.prepared.config.from_file && context.prepared.config.enabled) {
      restore_session_cvars(context);
      // Runtime rollback removed its menu redirect. Vanilla gets a fresh view with no effective
      // tier, including deployment/recipe refusals and failures after layer preparation.
      if (context.prepared.journal && context.prepared.journal->current && !context.prepared.journal->pending) {
        auto inactive = context.report.activation.plan;
        inactive.activate = false;
        auto menu = presentation::prepare_main_menu(context.root, *context.prepared.journal->current, &inactive);
        for (auto& redirect : menu.redirects) context.read_redirects.emplace_back(std::move(redirect.source), std::move(redirect.replacement));
        for (auto& note : menu.notes) context.report.session.notes.push_back(std::move(note));
      }
      hide_rtx_addons(context);
    }
    if (context.report.deployment.outcome == "failed" && !context.report.deployment.error.empty())
      context.report.errors.push_back(context.report.deployment.error);
    if (context.report.activation.outcome == "failed") context.report.errors.push_back(context.report.activation.reason);
  } catch (const std::exception& error) {
    failed_startup(context, error.what(), 0);
    return;
  } catch (...) {
    failed_startup(context, "startup C++ exception; continuing vanilla", 0);
    return;
  }
  // Reporting last, outside the activation's failure path: a report that cannot be written is
  // logged, never retried here (each attempt may wait out a reader) and never undoes anything.
  try {
    finish_report(context);
  } catch (...) {
    emergency_log(context.runtime.committed() ? "startup report could not be written; the runtime stays active"
                                              : "startup report could not be written", 0);
  }
}

// No destructible locals in the SEH frame. The rollback state is owned by its caller.
DWORD startup_seh(StartupContext* context) noexcept {
  __try { startup_cxx(*context); return 0; }
  __except (EXCEPTION_EXECUTE_HANDLER) { return GetExceptionCode(); }
}
DWORD report_seh(StartupContext* context, DWORD error) noexcept {
  __try { failed_startup(*context, "startup SEH fault; continuing vanilla", error); return 0; }
  __except (EXCEPTION_EXECUTE_HANDLER) { return GetExceptionCode(); }
}
}  // namespace

void emergency_log(const char* message, DWORD error) noexcept {
  char buffer[256]{};
  const int length = std::snprintf(buffer, sizeof(buffer), "failure=%s error=0x%08lx\n", message, error);
  OutputDebugStringA(buffer);
  if (!g_bootstrap.log_path[0] || length <= 0 || static_cast<std::size_t>(length) >= sizeof(buffer)) return;
  if (!log_path_ordinary()) return;  // the debugger line above is all a linked log gets
  const HANDLE file = CreateFileW(g_bootstrap.log_path, FILE_APPEND_DATA, FILE_SHARE_READ | FILE_SHARE_WRITE, nullptr, OPEN_ALWAYS, FILE_ATTRIBUTE_NORMAL, nullptr);
  if (file == INVALID_HANDLE_VALUE) return;
  DWORD written{};
  WriteFile(file, buffer, static_cast<DWORD>(length), &written, nullptr);
  CloseHandle(file);
}

void startup_guarded() noexcept {
  try {
    StartupContext context;
    const DWORD fault = startup_seh(&context);
    if (fault) {
      rollback_guarded(context.runtime);
      if (report_seh(&context, fault)) emergency_log("startup SEH failure report unavailable", fault);
    }
  } catch (...) {
    emergency_log("startup context failed; continuing vanilla", 0);
  }
}
}  // namespace nl::proxy
