#pragma once
// Machine-readable M4 startup result, shared with tests and uninstall; schema documented on disk.
#include "nl/activate.h"
#include "nl/deploy.h"
#include <cstdint>
#include <filesystem>
#include <optional>
#include <string>
#include <vector>

namespace nl::status {
inline constexpr std::string_view kDirectory = "garrysmod/data/native-loader";
inline constexpr std::string_view kPath = "garrysmod/data/native-loader/status.json";
struct Activation {
  activate::Plan plan;
  std::string outcome = "inactive";
  std::string reason;
  std::string runtime_dll;     // absolute deployed paths, whether or not loaded
  std::string runtime_folder;
  std::string vulkan_path;  // our retained System32 preload, empty if absent or rolled back
  std::vector<std::pair<std::string, std::string>> environment_set;
  std::vector<std::string> arguments_added;
  std::string fallback_launch_options;
  std::vector<std::string> missing_system_dependencies;
  std::uint32_t windows_error = 0;
  bool rolled_back = false;
  double elapsed_ms = 0;
};
// RTX-session extras (M5): what start-up set up for this session; results of the patch sets and
// overrides that apply later, as engine DLLs load, go to session.json.
struct Session {
  std::size_t cvars = 0;           // session console variables run through cvars_exec
  std::string cvars_exec;          // nativeloader_session.cfg, or empty
  std::size_t recorded = 0;        // user values held for the restore
  std::size_t restore_values = 0;  // start without RTX: values run through restore_exec
  std::string restore_exec;        // nativeloader_restore.cfg, or empty
  std::size_t patches = 0;         // patches planned (across patch sets)
  bool patches_allowed = false;
  std::vector<std::string> overrides;  // module names
  std::string hooks;               // installed, not needed, or why not
  std::vector<std::string> hidden_addons;  // no runtime this session: requires_remix add-on folders hidden (ADR 0013)
  std::vector<std::string> notes;
};
// A package of the committed generation and where it came from (M6): the companion compares a
// Workshop item's update time with the one deployed and asks for a restart when Steam has a newer one.
struct PackageSource {
  std::string id;
  std::string version;
  std::string source;  // workshop, local, dev_folder
  std::string label;   // the allowlist entry: Workshop item id or path
  std::optional<std::uint64_t> time_updated;  // Workshop: appworkshop_4000.acf at start-up
};
struct Report {
  std::string loader_version;
  std::string utc;
  std::uint32_t process_id = 0;
  deploy::Report deployment;
  double deployment_ms = 0;
  Activation activation;
  Session session;
  std::vector<PackageSource> packages;
  std::vector<std::string> errors;
  double startup_ms = 0;
};

std::string serialize(const Report& report);
std::string log_fields(const Report& report);
void write(const std::filesystem::path& root, const Report& report);
// Remove only the generated status/temp files and the now-empty native-loader data folder.
void remove(fs::FileSystem& disk, const std::filesystem::path& root);
// Remove status temp files left by launches whose process has gone (write() calls it). Never throws.
void remove_stale_temporaries(const std::filesystem::path& root, std::uint32_t own_process) noexcept;
}  // namespace nl::status
