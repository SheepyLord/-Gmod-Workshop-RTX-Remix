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

// The package's layers (low priority first) under its payload folder, then a layer of the loader's own
// if any (ADR 0030), then the user's root conf on top (the editable layer the Remix menu saves to), as
// a comma-separated list relative to the root.
std::string layer_list(const std::string& payload, const std::vector<std::string>& layers, std::string_view loader_layer,
                       std::string_view user_conf) {
  std::string value;
  for (const std::string& layer : layers) value += payload + "/" + layer + ",";
  if (!loader_layer.empty()) value += std::string(loader_layer) + ",";
  value += user_conf;
  return value;
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

std::vector<unsigned> graphics_adapters() {
  // As user32 above: the bootstrap's import table stays KERNEL32-only, so DXGI is loaded here.
  std::vector<unsigned> vendors;
  wchar_t system[MAX_PATH]{};
  const UINT length = GetSystemDirectoryW(system, MAX_PATH);
  if (!length || length >= MAX_PATH) return vendors;
  const HMODULE dxgi = LoadLibraryW((std::filesystem::path(system) / L"dxgi.dll").c_str());
  if (!dxgi) return vendors;
  using Create = HRESULT(WINAPI*)(REFIID, void**);
  const auto create = reinterpret_cast<Create>(GetProcAddress(dxgi, "CreateDXGIFactory1"));
  IDXGIFactory1* factory = nullptr;
  if (create && SUCCEEDED(create(__uuidof(IDXGIFactory1), reinterpret_cast<void**>(&factory))) && factory) {
    IDXGIAdapter1* adapter = nullptr;
    for (UINT i = 0; factory->EnumAdapters1(i, &adapter) != DXGI_ERROR_NOT_FOUND; ++i) {
      DXGI_ADAPTER_DESC1 description{};
      if (adapter && SUCCEEDED(adapter->GetDesc1(&description)) && !(description.Flags & DXGI_ADAPTER_FLAG_SOFTWARE)) {
        vendors.push_back(description.VendorId);
      }
      if (adapter) adapter->Release();
      adapter = nullptr;
    }
    factory->Release();
  }
  return vendors;  // dxgi.dll stays loaded, as user32 does
}

std::string non_nvidia_layer_text() {
  return "# Written by the GMod native loader at each RTX start on a computer without an NVIDIA GPU (ADR 0030).\r\n"
         "# The RTX package's settings pin Remix's graphics preset to Custom, tuned for NVIDIA GPUs; this layer\r\n"
         "# gives Remix its automatic choice for this GPU back. Your own dxvk.conf, rtx.conf and user.conf win.\r\n"
         "rtx.graphicsPreset = 5\r\n";
}

Plan plan(const journal::Generation& generation, const config::Config& config, const EnvGet& env,
          std::wstring_view command_line, const DisplayGet& display, const GpuGet& gpus) {
  Plan p;
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
  if (gpus) p.gpu_vendors = gpus();
  p.non_nvidia = !p.gpu_vendors.empty() &&
                 std::none_of(p.gpu_vendors.begin(), p.gpu_vendors.end(), [](unsigned vendor) { return vendor == kNvidia; });

  const auto add_layers = [&](const char* name, const std::vector<std::string>& package_layers, std::string_view loader_layer,
                              const char* default_user, std::vector<std::string>& effective) {
    const auto user = env(name);
    if (user) p.user_env.emplace_back(name, *user);
    const auto value = layer_list(runtime->payload, package_layers, loader_layer,
                                  user && !user->empty() ? std::string_view(*user) : default_user);
    effective = split_layers(value);
    if (!package_layers.empty() || !loader_layer.empty()) {
      // The runtime reads these variables into a 260-character buffer and takes a longer value as
      // empty: it would then use the bare root conf and none of the package's layers (RESEARCH.md
      // section 19).
      if (value.size() >= kMaxLayerList)
        p.notes.push_back(std::string(name) + " is " + std::to_string(value.size()) + " characters; the runtime reads at most " +
                          std::to_string(kMaxLayerList - 1) + " and ignores a longer list");
      p.env.emplace_back(name, value);
    }
  };
  add_layers("DXVK_RTX_CONFIG_FILE", remix.rtx_conf_layers, {}, "rtx.conf", p.rtx_layers);
  add_layers("DXVK_CONFIG_FILE", remix.dxvk_conf_layers, p.non_nvidia ? kNonNvidiaLayer : std::string_view{}, "dxvk.conf",
             p.dxvk_layers);
  for (const auto& [name, value] : remix.env) {
    const auto user = env(name);
    if (!user) p.env.emplace_back(name, value);
    else p.user_env.emplace_back(name, *user);
  }
  p.launch_args = missing_args(remix.launch_args, command_line, p.present_args);
  add_window_args(command_line, display, p.launch_args, p.present_args);
  p.patch_sets_need_insecure = config.patch_sets_require_insecure;
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

}  // namespace nl::activate
