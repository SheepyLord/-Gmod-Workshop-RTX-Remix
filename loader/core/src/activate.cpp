#include "nl/activate.h"

#include "nl/cmdline.h"
#include "nl/fs.h"
#include "nl/paths.h"
#include "nl/session.h"
#include <windows.h>
#include <dxgi.h>

#include <algorithm>
#include <cctype>
#include <system_error>

namespace nl::activate {
namespace {

constexpr std::size_t kMaxLayerList = 260;  // the runtime's buffer for DXVK_CONFIG_FILE / DXVK_RTX_CONFIG_FILE

// The folder part of a '/'-separated relative path ("a/b/c.dll" -> "a/b"); empty if there is none.
std::string parent(std::string_view path) {
  const auto slash = path.find_last_of('/');
  return slash == std::string_view::npos ? std::string() : std::string(path.substr(0, slash));
}

// Whether a command-line token is the option `name` (ASCII, as launch_args are in manifest schema 1),
// ignoring case the way the engine does: "-DXLEVEL" is -dxlevel.
bool same_option(std::wstring_view token, std::string_view name) {
  const auto lower = [](wchar_t c) { return c >= L'A' && c <= L'Z' ? c + (L'a' - L'A') : c; };
  return token.size() == name.size() && std::equal(token.begin(), token.end(), name.begin(), [&](wchar_t a, char b) {
    return lower(a) == lower(static_cast<unsigned char>(b));
  });
}

// Remix's rtx.* options take the first DXVK layer that holds a key (R6, ADR 0062). Loader Remix
// layers therefore precede the package's short copies. The user's root conf stays last in this
// list, as before; rtx.conf and user.conf have their own, stronger RtxOption priorities.
std::string layer_list(const std::vector<std::string>& layers, const std::vector<std::string>& first,
                       const std::vector<std::string>& last, std::string_view user_conf) {
  std::string value;
  for (const auto& layer : first) value += layer + ",";
  for (const std::string& layer : layers) value += layer + ",";
  for (const auto& layer : last) value += layer + ",";
  value += user_conf;
  return value;
}

std::string joined(const std::vector<std::string>& layers) {
  std::string value;
  for (std::size_t i = 0; i < layers.size(); ++i) value += (i ? "," : "") + layers[i];
  return value;
}

// The runtime reads these variables into a 260-character buffer and takes a longer value as empty: it
// then uses the bare root conf and none of the package's layers (RESEARCH.md sections 19 and 32).
void note_length(std::vector<std::string>& notes, const std::string& name, const std::string& value) {
  if (value.size() >= kMaxLayerList)
    notes.push_back(name + " is " + std::to_string(value.size()) + " characters; the runtime reads at most " +
                    std::to_string(kMaxLayerList - 1) + " and ignores a longer list");
}

std::vector<std::string> split_layers(std::string_view value) {
  std::vector<std::string> result;
  for (std::size_t at = 0;;) {
    const auto end = value.find(',', at);
    result.emplace_back(value.substr(at, end == std::string_view::npos ? end : end - at));
    if (end == std::string_view::npos) break;
    at = end + 1;
  }
  return result;
}

// From the package's launch_args, the ones the command line does not already carry. A -dxlevel or
// +mat_disable_d3d9ex argument keeps its following numeric value; -nod3d9ex stands alone.
std::vector<std::string> missing_args(const std::vector<std::string>& args, std::wstring_view command_line,
                                    std::vector<std::string>& present) {
  std::vector<std::string> out;
  const auto tokens = cmdline::tokenize(command_line);
  for (std::size_t i = 0; i < args.size(); ++i) {
    const std::string& arg = args[i];
    const bool has_value = i + 1 < args.size() &&
        !args[i + 1].empty() && std::all_of(args[i + 1].begin(), args[i + 1].end(), [](char c) { return std::isdigit(static_cast<unsigned char>(c)); });
    const auto found = std::find_if(tokens.begin(), tokens.end(), [&](const auto& token) { return same_option(token, arg); });
    if (found == tokens.end()) {
      out.push_back(arg);
      if (has_value) out.push_back(args[i + 1]);
    } else {
      present.push_back(arg);
      if (has_value && std::next(found) != tokens.end()) {
        const auto& value = *std::next(found);
        if (!value.empty() && std::all_of(value.begin(), value.end(), [](wchar_t c) { return c >= L'0' && c <= L'9'; })) {
          std::string numeric;
          for (wchar_t digit : value) numeric.push_back(static_cast<char>(digit));
          present.push_back(std::move(numeric));
        }
      }
    }
    if (has_value) ++i;  // the value was consumed either way
  }
  return out;
}

// The Remix runtime crashes when the game switches its device out of exclusive fullscreen (RESEARCH.md
// section 18), so an RTX session runs in a borderless window the size of the primary display, as
// RTXLauncher starts the game. A window mode the user chose (-windowed, -fullscreen and the engine's
// other spellings) is left as it is, and so are their own -noborder and size.
void add_window_args(std::wstring_view command_line, const DisplayGet& display, std::vector<std::string>& out,
                     std::vector<std::string>& present) {
  const auto tokens = cmdline::tokenize(command_line);
  const auto given = [&](std::string_view name) {
    return std::any_of(tokens.begin(), tokens.end(), [&](const std::wstring& token) { return same_option(token, name); });
  };
  for (const char* mode : {"-windowed", "-window", "-sw", "-startwindowed", "-full", "-fullscreen"}) {
    if (given(mode)) {
      present.emplace_back(mode);
      return;
    }
  }
  out.emplace_back("-windowed");
  if (given("-noborder")) present.emplace_back("-noborder");
  else out.emplace_back("-noborder");
  bool sized = false;
  for (const char* size : {"-w", "-width", "-h", "-height"}) {
    if (given(size)) {
      present.emplace_back(size);
      sized = true;
    }
  }
  if (sized) return;
  const Display screen = display();
  if (screen.width && screen.height)
    out.insert(out.end(), {"-w", std::to_string(screen.width), "-h", std::to_string(screen.height)});
}

}  // namespace

std::optional<std::string> environment_value(const std::string& name) {
  const std::wstring wide(name.begin(), name.end());
  SetLastError(ERROR_SUCCESS);
  const DWORD size = GetEnvironmentVariableW(wide.c_str(), nullptr, 0);
  if (!size) {
    if (GetLastError() == ERROR_ENVVAR_NOT_FOUND) return std::nullopt;
    if (GetLastError() == ERROR_SUCCESS) return std::string{};
    throw std::system_error(static_cast<int>(GetLastError()), std::system_category(), "read activation environment");
  }
  std::wstring value(size, L'\0');
  SetLastError(ERROR_SUCCESS);
  const DWORD copied = GetEnvironmentVariableW(wide.c_str(), value.data(), size);
  if (copied >= size) throw std::runtime_error("activation environment changed while reading");
  if (!copied && GetLastError() != ERROR_SUCCESS)
    throw std::system_error(static_cast<int>(GetLastError()), std::system_category(), "read activation environment");
  value.resize(copied);
  return fs::utf8(std::filesystem::path(value));
}

Display primary_display() {
  // The bootstrap links this code and must keep a KERNEL32-only import table (check_imports.py), so
  // user32 is loaded here. gmod.exe is per-monitor DPI aware, and the mode is in physical pixels anyway.
  wchar_t system[MAX_PATH]{};
  const UINT length = GetSystemDirectoryW(system, MAX_PATH);
  if (!length || length >= MAX_PATH) return {};
  const HMODULE user32 = LoadLibraryW((std::filesystem::path(system) / L"user32.dll").c_str());
  if (!user32) return {};
  const auto get_mode = reinterpret_cast<decltype(&EnumDisplaySettingsW)>(GetProcAddress(user32, "EnumDisplaySettingsW"));
  DEVMODEW mode{};
  mode.dmSize = static_cast<WORD>(sizeof(mode));
  Display display;
  if (get_mode && get_mode(nullptr, ENUM_CURRENT_SETTINGS, &mode)) {
    display.width = mode.dmPelsWidth;
    display.height = mode.dmPelsHeight;
  }
  return display;  // user32 stays loaded: the game loads it anyway
}

std::string adapter_description(std::wstring_view description) noexcept {
  try { return fs::utf8(std::filesystem::path(description)); } catch (...) { return {}; }
}

std::vector<performance::Adapter> graphics_adapters() {
  // As user32 above: the bootstrap's import table stays KERNEL32-only, so DXGI is loaded here.
  std::vector<performance::Adapter> adapters;
  wchar_t system[MAX_PATH]{};
  const UINT length = GetSystemDirectoryW(system, MAX_PATH);
  if (!length || length >= MAX_PATH) return adapters;
  const HMODULE dxgi = LoadLibraryW((std::filesystem::path(system) / L"dxgi.dll").c_str());
  if (!dxgi) return adapters;
  using Create = HRESULT(WINAPI*)(REFIID, void**);
  const auto create = reinterpret_cast<Create>(GetProcAddress(dxgi, "CreateDXGIFactory1"));
  IDXGIFactory1* factory = nullptr;
  if (create && SUCCEEDED(create(__uuidof(IDXGIFactory1), reinterpret_cast<void**>(&factory))) && factory) {
    IDXGIAdapter1* adapter = nullptr;
    for (UINT i = 0; i < 32; ++i) {
      if (factory->EnumAdapters1(i, &adapter) != S_OK) break;
      DXGI_ADAPTER_DESC1 description{};
      if (adapter && SUCCEEDED(adapter->GetDesc1(&description)) && !(description.Flags & DXGI_ADAPTER_FLAG_SOFTWARE)) {
        // Driver descriptions are optional metadata. Malformed UTF-16 or an allocation failure
        // here must not lose the adapter's vendor/VRAM or abort RTX startup.
        auto name = adapter_description(description.Description);
        try { adapters.push_back({description.VendorId, std::move(name), description.DedicatedVideoMemory}); }
        catch (...) { }  // retain the adapters read so far if the list cannot grow
      }
      if (adapter) adapter->Release();
      adapter = nullptr;
    }
    factory->Release();
  }
  return adapters;  // dxgi.dll stays loaded, as user32 does
}

std::string non_nvidia_layer_text() {
  return "# Written by the GMod native loader at each RTX start on a computer without an NVIDIA GPU (ADR 0030).\r\n"
         "# The RTX package's settings pin Remix's graphics preset to Custom, tuned for NVIDIA GPUs; this layer\r\n"
         "# gives Remix its automatic choice for this GPU back. Your own rtx.conf and saved Remix settings win.\r\n"
         "rtx.graphicsPreset = 5\r\n";
}

std::string low_tier_layer_text() {
  return "# Generated by the GMod native loader: low-tier fallback for pre-R6 runtime packages (ADR 0062).\r\n"
         "rtx.lowMemoryGpu = True\r\n"
         "rtx.opacityMicromap.cache.maxBudgetSizeMB = 512\r\n"
         "rtx.skyProbeSide = 1024\r\n"
         "rtx.volumetrics.froxelGridResolutionScale = 8\r\n"
         "rtx.terrainBaker.cascadeMap.levelResolution = 2048\r\n";
}

bool late_runtime_dll(std::string_view file_name) {
  std::string name(file_name);
  for (char& c : name) c = static_cast<char>(std::tolower(static_cast<unsigned char>(c)));
  const auto stem_of = [&](std::string_view prefix) {
    return name.size() > prefix.size() + 4 && name.compare(0, prefix.size(), prefix) == 0 &&
           name.compare(name.size() - 4, 4, ".dll") == 0;
  };
  return name == "amd_fidelityfx_vk.dll" || stem_of("cudart64_") || stem_of("nvrtc64_") || stem_of("nvrtc-builtins64_");
}

Plan plan(const journal::Generation& generation, const config::Config& config, const EnvGet& env,
          std::wstring_view command_line, const DisplayGet& display, const GpuGet& gpus,
          const gpu_diagnostics::Probe& diagnostics) {
  Plan p;
  p.notes = config.notes;
  if (!config.enabled) {
    p.reason = "enabled is false in native-loader/config.json";
    return p;
  }
  const journal::Package* runtime = nullptr;
  for (const journal::Package& pkg : generation.packages) {
    if (pkg.remix && !pkg.payload.empty()) {
      runtime = &pkg;
      break;
    }
  }
  if (!runtime) {
    p.reason = "no runtime package is deployed";
    return p;
  }
  const manifest::Remix& remix = *runtime->remix;
  p.runtime_id = runtime->id;
  p.runtime_version = runtime->version;
  p.runtime_dll = runtime->payload + "/" + remix.entry;
  p.runtime_dir = parent(p.runtime_dll);
  p.prefer_system_vulkan = remix.prefer_system_vulkan_loader;
  if (!config.remix_enabled) {
    p.reason = "remix.enabled is false in native-loader/config.json";
    return p;
  }

  // Without an NVIDIA GPU, Remix chooses its own preset (ADR 0030). Unknown adapters change nothing.
  const auto adapters = gpus ? gpus() : std::vector<performance::Adapter>{};
  for (const auto& adapter : adapters) p.gpu_vendors.push_back(adapter.vendor);
  p.non_nvidia = !p.gpu_vendors.empty() &&
                 std::none_of(p.gpu_vendors.begin(), p.gpu_vendors.end(), [](unsigned vendor) { return vendor == kNvidia; });
  p.performance_tier = performance::classify(adapters, config.performance_tier);
  std::string tier_source;
  if (!p.non_nvidia && (p.performance_tier.nvidia || config.performance_tier != config::PerformanceTier::automatic) &&
      p.performance_tier.tier != performance::Tier::high) {
    const auto path = runtime->payload + "/config/dxvk-tiers/" + performance::name(p.performance_tier.tier) + ".conf";
    const auto file = std::find_if(generation.files.begin(), generation.files.end(), [&](const auto& record) {
      return record.package == runtime->id && paths::fold(record.path) == paths::fold(path);
    });
    if (file != generation.files.end()) {
      tier_source = file->path;
      p.performance_tier.layer = kTierLayer;
    } else if (p.performance_tier.tier == performance::Tier::low) {
      p.low_tier_fallback = true;
      if (config.performance_tier == config::PerformanceTier::automatic) p.performance_tier.source = "fallback";
      p.performance_tier.layer = kTierLayer;
      p.performance_tier.reason += "; package has no low tier file, using built-in low defaults";
    } else {
      p.performance_tier.reason += "; package has no medium tier file, retaining classic defaults";
    }
  }
  if (!diagnostics.note.empty()) p.notes.push_back(diagnostics.note);
  p.gpu_crash_dumps_once = config.gpu_crash_dumps == config::GpuCrashDumps::next_start;
  p.reset_gpu_crash_dumps = config.gpu_crash_dumps == config::GpuCrashDumps::off;
  p.gpu_crash_dumps = config.gpu_crash_dumps == config::GpuCrashDumps::always ||
                      (p.gpu_crash_dumps_once && !diagnostics.consumed);
  if (p.gpu_crash_dumps_once && diagnostics.consumed)
    p.notes.push_back("diagnostics.gpu_crash_dumps=next_start was already consumed; start RTX once with diagnostics off or remove native-loader/remix/gpu-crash-dumps.used to request again");

  // The runtime's late bare-name loads (ADR 0030): its own deployed files, at the top of its folder.
  for (const journal::File& file : generation.files) {
    const std::string folder = parent(file.path);
    if (file.package != runtime->id || paths::fold(folder) != paths::fold(p.runtime_dir)) continue;
    if (late_runtime_dll(std::string_view(file.path).substr(folder.size() + 1))) p.preload.push_back(file.path);
  }
  std::sort(p.preload.begin(), p.preload.end());

  // Each package layer is listed as its copy in kLayerFolder (ADR 0036), so the lists stay short
  // whatever the payload folder's name: the bootstrap writes the copies from the payload.
  const auto add_layers = [&](const char* name, std::string_view kind, const std::vector<std::string>& package_layers,
                              const std::vector<std::string>& first, const std::vector<std::string>& last,
                              const char* default_user, std::vector<std::string>& effective) {
    const auto user = env(name);
    if (user) p.user_env.emplace_back(name, *user);
    std::vector<std::string> copies;
    for (std::size_t i = 0; i < package_layers.size(); ++i) {
      copies.push_back(std::string(kLayerFolder) + "/" + std::string(kind) + "-" + std::to_string(i + 1) + ".conf");
      p.layer_copies.push_back({runtime->payload + "/" + package_layers[i], copies.back()});
    }
    const auto value = layer_list(copies, first, last, user && !user->empty() ? std::string_view(*user) : default_user);
    effective = split_layers(value);
    if (!package_layers.empty() || !first.empty() || !last.empty()) {
      note_length(p.notes, name, value);
      p.env.emplace_back(name, value);
    }
  };
  std::vector<std::string> first;
  if (!p.performance_tier.layer.empty()) first.push_back(p.performance_tier.layer);
  if (p.non_nvidia) first.emplace_back(kNonNvidiaLayer);
  const std::vector<std::string> last = p.gpu_crash_dumps ? std::vector<std::string>{std::string(gpu_diagnostics::kLayer)}
                                                        : std::vector<std::string>{};
  add_layers("DXVK_RTX_CONFIG_FILE", "rtx", remix.rtx_conf_layers, {}, {}, "rtx.conf", p.rtx_layers);
  add_layers("DXVK_CONFIG_FILE", "dxvk", remix.dxvk_conf_layers, first, last, "dxvk.conf",
             p.dxvk_layers);
  if (!tier_source.empty()) p.layer_copies.push_back({tier_source, std::string(kTierLayer)});
  for (const auto& [name, value] : remix.env) {
    const auto user = env(name);
    if (!user) p.env.emplace_back(name, value);
    else p.user_env.emplace_back(name, *user);
  }
  if (p.gpu_crash_dumps) {
    // This opt-in diagnostic destination belongs to the loader for this session. Preserve the user's
    // old value for reporting/rollback, but do not allow it or a package variable to redirect dumps.
    const std::string name(gpu_diagnostics::kDumpVariable);
    for (const auto& [key, value] : p.env) if (key == name) p.gpu_dump_package_value = value;
    std::erase_if(p.env, [&](const auto& item) { return item.first == name; });
    std::erase_if(p.user_env, [&](const auto& item) { return item.first == name; });
    if (const auto user = env(name))
      p.notes.push_back(name + " was \"" + *user + "\"; GPU diagnostics use native-loader/logs/gpu for this session");
    p.env.emplace_back(name, diagnostics.dump_path);
  }
  p.launch_args = missing_args(remix.launch_args, command_line, p.present_args);
  add_window_args(command_line, display, p.launch_args, p.present_args);
  p.patch_sets_need_insecure = config.patch_sets_require_insecure;
  p.allow_secure_rtx_render_patches = config.allow_secure_rtx_render_patches;
  p.activate = true;
  p.reason = "runtime " + runtime->id + " " + runtime->version;

  for (const journal::Package& pkg : generation.packages) {
    for (const auto& set : pkg.session.patch_sets) p.patch_sets.push_back({pkg.id, set});
    for (const auto& item : pkg.session.module_overrides) {
      const auto same = std::find_if(p.module_overrides.begin(), p.module_overrides.end(),
                                     [&](const Plan::Override& o) { return o.module == item.module; });
      if (same != p.module_overrides.end()) {
        p.notes.push_back(item.module + " is overridden by " + same->package + "; " + pkg.id + "'s override is not used");
        continue;
      }
      if (pkg.payload.empty()) continue;
      p.module_overrides.push_back({pkg.id, item.module, pkg.payload + "/" + item.file});
    }
    for (const auto& [name, value] : pkg.session.cvars) {
      const auto same = std::find_if(p.session_cvars.begin(), p.session_cvars.end(), [&](const auto& cvar) {
        return paths::fold(cvar.first) == paths::fold(name);
      });
      if (same != p.session_cvars.end()) same->second = value;
      else p.session_cvars.emplace_back(name, value);
    }
  }
  p.module_dependencies = session::module_dependencies(generation);
  return p;
}

void use_sources(Plan& plan, const std::vector<std::string>& unwritten) {
  const auto missing = [&](const Plan::LayerCopy& layer) {
    return std::find(unwritten.begin(), unwritten.end(), layer.copy) != unwritten.end();
  };
  bool changed = false;
  for (const Plan::LayerCopy& layer : plan.layer_copies) {
    if (!missing(layer)) continue;
    for (auto* list : {&plan.rtx_layers, &plan.dxvk_layers}) std::replace(list->begin(), list->end(), layer.copy, layer.source);
    if (plan.performance_tier.layer == layer.copy) plan.performance_tier.layer = layer.source;
    changed = true;
  }
  if (!changed) return;
  std::erase_if(plan.layer_copies, missing);
  for (auto& [name, value] : plan.env) {
    const std::vector<std::string>* list = name == "DXVK_RTX_CONFIG_FILE" ? &plan.rtx_layers
                                           : name == "DXVK_CONFIG_FILE"   ? &plan.dxvk_layers
                                                                          : nullptr;
    if (!list || joined(*list) == value) continue;
    value = joined(*list);
    note_length(plan.notes, name, value);
  }
}

void disable_performance_tier(Plan& plan, const std::string& reason) {
  const auto layer = plan.performance_tier.layer;
  if (layer.empty()) return;
  std::erase(plan.dxvk_layers, layer);  // even an explicit duplicate must not read the stale fallback
  for (auto& [name, value] : plan.env) if (name == "DXVK_CONFIG_FILE") value = joined(plan.dxvk_layers);
  plan.performance_tier.layer.clear();
  plan.low_tier_fallback = false;
  plan.notes.push_back(reason);
}

void disable_gpu_crash_dumps(Plan& plan, const std::string& reason) {
  if (!plan.gpu_crash_dumps) return;
  plan.gpu_crash_dumps = false;
  const auto layer = std::find(plan.dxvk_layers.begin(), plan.dxvk_layers.end(), gpu_diagnostics::kLayer);
  if (layer != plan.dxvk_layers.end()) plan.dxvk_layers.erase(layer);  // retain a user's explicit duplicate
  for (auto& [name, value] : plan.env) if (name == "DXVK_CONFIG_FILE") value = joined(plan.dxvk_layers);
  const auto user = std::find_if(plan.user_env.begin(), plan.user_env.end(), [](const auto& item) { return item.first == "DXVK_CONFIG_FILE"; });
  const auto suffix = split_layers(user == plan.user_env.end() || user->second.empty() ? "dxvk.conf" : user->second);
  if (plan.dxvk_layers == suffix)
    std::erase_if(plan.env, [](const auto& item) { return item.first == "DXVK_CONFIG_FILE"; });
  std::erase_if(plan.env, [](const auto& item) { return item.first == gpu_diagnostics::kDumpVariable; });
  if (plan.gpu_dump_package_value) plan.env.emplace_back(gpu_diagnostics::kDumpVariable, *plan.gpu_dump_package_value);
  plan.notes.push_back(reason);
}

}  // namespace nl::activate
