#include "early.h"
#include "catalog.h"
#include "nl/fs.h"
#include "nl/sha256.h"
#include <algorithm>
#include <stdexcept>

namespace nl::guard {
namespace {
// Part of every cache name: a generator whose output changes gets new names, not mismatches.
constexpr std::string_view kViewFormat = "nativeloader early guard view 2";

bool plain_path(std::string_view path) {
  if (path.empty() || path.front() == '/' || path.find("..") != std::string_view::npos) return false;
  return std::all_of(path.begin(), path.end(), [](char c) {
    return (c >= 'a' && c <= 'z') || (c >= 'A' && c <= 'Z') || (c >= '0' && c <= '9') || c == '/' || c == '.' ||
           c == '_' || c == '-';
  });
}

// A changed cache file is evidence of an edit or a fault: it is kept, never deleted.
std::string keep_aside(const std::filesystem::path& root, std::string_view relative, std::string_view name) {
  fs::refuse_links(root, kKeptFolder);
  for (const std::string_view folder : {std::string_view("native-loader/backup"), kKeptFolder}) {
    const auto path = fs::join(root, folder);
    const auto info = fs::stat(path);
    if (!info.exists) fs::win32().create_directory(path);
    else if (!info.directory || info.link) throw std::runtime_error("The render guard backup folder is not an ordinary directory");
  }
  for (unsigned n = 1; n <= 1000; ++n) {
    const std::string target = std::string(kKeptFolder) + "/" + std::string(name) + "." + std::to_string(n);
    fs::refuse_links(root, target);
    if (fs::stat(fs::join(root, target)).exists) continue;
    fs::win32().move(fs::join(root, relative), fs::join(root, target), false);
    return target;
  }
  throw std::runtime_error("Too many kept render guard cache files");
}
}  // namespace

std::string append_client_guard(std::string_view original, std::string_view guard, std::string_view proof) {
  if (original.find('\0') != std::string_view::npos || guard.find('\0') != std::string_view::npos)
    throw std::runtime_error("Lua initializer/guard contains NUL bytes");
  if (guard.find(kMarker) == std::string_view::npos)
    throw std::runtime_error("The deployed RTX guard does not support early initialization");
  if (!plain_path(proof)) throw std::runtime_error("The render guard proof path is not a plain relative path");
  std::string out(original);
  out += "\n-- Verified RTX render protection; the on-disk Steam initializer is unchanged.\n"
         "-- A listen host serves this view to remote clients too: the guard installs early only where\n"
         "-- this machine's loader wrote the file named below, and checks that this start activated RTX.\n"
         "if CLIENT and not SERVER and not MENU_DLL then\n"
         " local nativeLoaderChecked, nativeLoaderLocalView = pcall(function() return file.Exists(\"";
  out += proof;
  out += "\", \"BASE_PATH\") end)\n"
         " if nativeLoaderChecked and nativeLoaderLocalView == true then\n"
         "  _G.__NATIVELOADER_RTX_GUARD_EARLY = true\n"
         "  local function nativeLoaderInstallRenderGuard()\n";
  out += guard;
  out += "\n  end\n"
         "  local ok, reason = pcall(nativeLoaderInstallRenderGuard)\n"
         "  if not ok then MsgN('[nativeloader] early render guard failed: ' .. tostring(reason)) end\n"
         " end\n"
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
  fs::refuse_links(root, kInit);
  const auto source = fs::join(root, kInit);
  const auto original = fs::read_file(source, std::size_t{128} << 10);
  if (sha256::of(original) != expected_stock_hash)
    throw std::runtime_error("Unsupported stock Lua initializer (changed by a game update?); early view not prepared");
  // Named by its inputs rather than its bytes, so the generated text can name the file whose
  // presence proves the view is this machine's own.
  const std::string name = "render-guard-" +
      sha256::of(std::string(kViewFormat) + "\n" + sha256::of(original) + "\n" + sha256::of(script->second.text)) + ".lua";
  const std::string relative = std::string(kCacheFolder) + "/" + name;
  const auto text = append_client_guard(original, script->second.text, relative);
  fs::refuse_links(root, kCacheFolder);
  const auto folder = fs::join(root, kCacheFolder);
  const auto folder_state = fs::stat(folder);
  if (!folder_state.exists) fs::win32().create_directory(folder);
  else if (!folder_state.directory || folder_state.link)
    throw std::runtime_error("Render guard cache is not an ordinary directory");
  fs::refuse_links(root, relative);
  const auto replacement = fs::join(root, relative);
  const auto state = fs::stat(replacement);
  Redirect redirect{std::filesystem::absolute(source), std::filesystem::absolute(replacement), {}};
  if (state.exists && (state.directory || state.size != text.size() || fs::read_file(replacement, text.size()) != text))
    redirect.kept = keep_aside(root, relative, name);
  if (!state.exists || !redirect.kept.empty()) fs::write_atomic(fs::win32(), replacement, text);
  return redirect;
}
}
