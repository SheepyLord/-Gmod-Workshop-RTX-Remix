#include "early.h"
#include "catalog.h"
#include "nl/fs.h"
#include "nl/sha256.h"
#include <stdexcept>

namespace nl::guard {
std::string append_client_guard(std::string_view original, std::string_view guard) {
  if (original.find('\0') != std::string_view::npos || guard.find('\0') != std::string_view::npos)
    throw std::runtime_error("Lua initializer/guard contains NUL bytes");
  if (guard.find(kMarker) == std::string_view::npos)
    throw std::runtime_error("The deployed RTX guard does not support early initialization");
  std::string out(original);
  out += "\n-- Verified RTX render protection; the on-disk Steam initializer is unchanged.\n"
         "if CLIENT and not SERVER and not MENU_DLL then\n"
         " _G.__NATIVELOADER_RTX_GUARD_EARLY = true\n"
         " local function nativeLoaderInstallRenderGuard()\n";
  out += guard;
  out += "\n end\n"
         " local ok, reason = pcall(nativeLoaderInstallRenderGuard)\n"
         " if not ok then MsgN('[nativeloader] early render guard failed: ' .. tostring(reason)) end\n"
         "end\n";
  return out;
}

std::optional<Redirect> prepare(const std::filesystem::path& root, const config::Config& config,
                               const journal::Generation& generation, std::string_view selected_runtime,
                               std::string_view expected_stock_hash) {
  if (!config.from_file || !config.enabled || !config.remix_enabled) return std::nullopt;
  if (selected_runtime != client::kPackage) return std::nullopt;
  auto catalog = client::prepare(root, config, generation);
  const auto script = catalog.scripts.find(std::string(kGuard));
  if (script == catalog.scripts.end()) throw std::runtime_error("The verified RTX companion guard is absent");
  if (script->second.text.find(kMarker) == std::string::npos)
    throw std::runtime_error("The deployed RTX guard does not support early initialization");
  try {
    fs::refuse_links(root, kInit);
    const auto source = fs::join(root, kInit);
    const auto original = fs::read_file(source, std::size_t{128} << 10);
    if (sha256::of(original) != expected_stock_hash)
      throw std::runtime_error("Unsupported stock Lua initializer; early protection was not redirected");
    const auto text = append_client_guard(original, script->second.text);
    const auto digest = sha256::of(text);
    constexpr std::string_view directory = "native-loader/presentation";
    fs::refuse_links(root, directory);
    const auto folder = fs::join(root, directory);
    const auto folder_state = fs::stat(folder);
    if (!folder_state.exists) fs::win32().create_directory(folder);
    else if (!folder_state.directory || folder_state.link)
      throw std::runtime_error("Render guard cache is not an ordinary directory");
    const std::string relative = std::string(directory) + "/render-guard-" + digest + ".lua";
    fs::refuse_links(root, relative);
    const auto replacement = fs::join(root, relative);
    const auto state = fs::stat(replacement);
    if (state.exists) {
      if (state.directory || state.link || state.size != text.size() || fs::read_file(replacement, text.size()) != text)
        throw std::runtime_error("Render guard cache was changed; existing bytes preserved");
    } else {
      fs::write_atomic(fs::win32(), replacement, text);
    }
    return Redirect{std::filesystem::absolute(source), std::filesystem::absolute(replacement)};
  } catch (const std::exception& error) {
    throw RequiredUnavailable(error.what());
  }
}
}
