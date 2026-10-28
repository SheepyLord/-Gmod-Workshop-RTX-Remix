#include "nl/activate.h"

#include "nl/cmdline.h"

#include <algorithm>
#include <cctype>

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
std::string layer_list(const std::string& payload, const std::vector<std::string>& layers, const char* user_conf) {
  std::string value;
  for (const std::string& layer : layers) value += payload + "/" + layer + ",";
  value += user_conf;
  return value;
}

// From the package's launch_args, the ones the command line does not already carry. A -dxlevel or
// +mat_disable_d3d9ex argument keeps its following numeric value; -nod3d9ex stands alone.
std::vector<std::string> missing_args(const std::vector<std::string>& args, std::wstring_view command_line) {
  std::vector<std::string> out;
  for (std::size_t i = 0; i < args.size(); ++i) {
    const std::string& arg = args[i];
    const bool has_value = i + 1 < args.size() &&
        !args[i + 1].empty() && std::all_of(args[i + 1].begin(), args[i + 1].end(), [](char c) { return std::isdigit(static_cast<unsigned char>(c)); });
    if (!cmdline::has_arg(command_line, widen_ascii(arg))) {
      out.push_back(arg);
      if (has_value) out.push_back(args[i + 1]);
    }
    if (has_value) ++i;  // the value was consumed either way
  }
  return out;
}

}  // namespace

Plan plan(const journal::Generation& generation, const config::Config& config, const EnvHas& env,
          std::wstring_view command_line) {
  Plan p;
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
  if (!config.remix_enabled) {
    p.reason = "remix.enabled is false in native-loader/config.json";
    return p;
  }
  const manifest::Remix& remix = *runtime->remix;
  p.runtime_dll = runtime->payload + "/" + remix.entry;
  p.runtime_dir = parent(p.runtime_dll);
  p.prefer_system_vulkan = remix.prefer_system_vulkan_loader;

  if (!remix.rtx_conf_layers.empty() && !env("DXVK_RTX_CONFIG_FILE")) {
    p.env.emplace_back("DXVK_RTX_CONFIG_FILE", layer_list(runtime->payload, remix.rtx_conf_layers, "rtx.conf"));
  }
  if (!remix.dxvk_conf_layers.empty() && !env("DXVK_CONFIG_FILE")) {
    p.env.emplace_back("DXVK_CONFIG_FILE", layer_list(runtime->payload, remix.dxvk_conf_layers, "dxvk.conf"));
  }
  for (const auto& [name, value] : remix.env) {
    if (!env(name)) p.env.emplace_back(name, value);
  }
  p.launch_args = missing_args(remix.launch_args, command_line);
  p.activate = true;
  p.reason = "runtime " + runtime->id + " " + runtime->version;
  return p;
}

}  // namespace nl::activate
