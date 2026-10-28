#include "nl/activate.h"

#include "nl/cmdline.h"
#include "nl/fs.h"
#include "nl/paths.h"
#include <windows.h>

#include <algorithm>
#include <cctype>
#include <system_error>

namespace nl::activate {
namespace {

// The folder part of a '/'-separated relative path ("a/b/c.dll" -> "a/b"); empty if there is none.
std::string parent(std::string_view path) {
  const auto slash = path.find_last_of('/');
  return slash == std::string_view::npos ? std::string() : std::string(path.substr(0, slash));
}

std::wstring widen_ascii(std::string_view text) {
  return std::wstring(text.begin(), text.end());  // launch_args are ASCII (manifest schema 1)
}

// The package's layers (low priority first) under its payload folder, then the user's root conf on
// top (the editable layer the Remix menu saves to), as a comma-separated list relative to the root.
std::string layer_list(const std::string& payload, const std::vector<std::string>& layers, std::string_view user_conf) {
  std::string value;
  for (const std::string& layer : layers) value += payload + "/" + layer + ",";
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
    const auto wide = widen_ascii(arg);
    const auto found = std::find_if(tokens.begin(), tokens.end(), [&](const auto& token) {
      if (token.size() != wide.size()) return false;
      return std::equal(token.begin(), token.end(), wide.begin(), [](wchar_t a, wchar_t b) {
        const auto lower = [](wchar_t c) { return c >= L'A' && c <= L'Z' ? c + (L'a' - L'A') : c; };
        return lower(a) == lower(b);
      });
    });
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

Plan plan(const journal::Generation& generation, const config::Config& config, const EnvGet& env,
          std::wstring_view command_line) {
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

  const auto add_layers = [&](const char* name, const std::vector<std::string>& package_layers,
                              const char* default_user, std::vector<std::string>& effective) {
    const auto user = env(name);
    if (user) p.user_env.emplace_back(name, *user);
    const auto value = layer_list(runtime->payload, package_layers, user && !user->empty() ? std::string_view(*user) : default_user);
    effective = split_layers(value);
    if (!package_layers.empty()) p.env.emplace_back(name, value);
  };
  add_layers("DXVK_RTX_CONFIG_FILE", remix.rtx_conf_layers, "rtx.conf", p.rtx_layers);
  add_layers("DXVK_CONFIG_FILE", remix.dxvk_conf_layers, "dxvk.conf", p.dxvk_layers);
  for (const auto& [name, value] : remix.env) {
    const auto user = env(name);
    if (!user) p.env.emplace_back(name, value);
    else p.user_env.emplace_back(name, *user);
  }
  p.launch_args = missing_args(remix.launch_args, command_line, p.present_args);
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
  return p;
}

}  // namespace nl::activate
