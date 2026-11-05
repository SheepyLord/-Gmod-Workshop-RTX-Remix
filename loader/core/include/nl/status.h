#pragma once
// Machine-readable M4 startup result, shared with tests and uninstall; schema documented on disk.
#include "nl/activate.h"
#include "nl/deploy.h"
#include "nl/evidence.h"
#include "nl/reshade.h"
#include <cstdint>
#include <filesystem>
#include <optional>
#include <string>
#include <vector>

namespace nl::status {
inline constexpr std::string_view kDirectory = "garrysmod/data/native-loader";
inline constexpr std::string_view kPath = "garrysmod/data/native-loader/status.json";
// The RTX session marker (R19, proxy F-02). An RTX start holds it open for the life of the game process,
// with delete-on-close, so Windows deletes it when the process ends, however it ends. status.json
// stays after the game exits, and a start through an off switch never runs the loader, so an old
// "active" there outlives its start; the companion's render guard therefore also requires this file.
inline constexpr std::string_view kSessionMarker = "garrysmod/data/native-loader/rtx-session.txt";
// ReShade in this RTX session (ADR 0028).
struct Reshade {
  reshade::Plan plan;
  std::string outcome = "off";  // active, off (not enabled: plan.reason), failed (the session runs without it)
  std::string reason;
  std::string folder;           // absolute native-loader\reshade
  std::string settings;         // kept, migrated or fresh
  std::vector<std::string> presets;  // copied into the folder this start
  std::vector<std::pair<std::string, std::string>> environment;  // set for the layer
  std::vector<std::string> notes;
};
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
  std::vector<std::string> preloaded;  // absolute paths of the plan's late runtime DLLs that loaded (ADR 0030)
  std::uint32_t windows_error = 0;
  bool rolled_back = false;
  double elapsed_ms = 0;
  Reshade reshade;
};
// RTX-session extras (M5): what start-up set up for this session; results of the patch sets and
// overrides that apply later, as engine DLLs load, go to session.json.
struct Session {
  std::size_t cvars = 0;           // session console variables run through cvars_exec
  std::string cvars_exec;          // nativeloader_session.cfg, or empty
  std::size_t recorded = 0;        // user values held for the restore
  std::size_t restore_values = 0;  // start without RTX: values run through restore_exec
  std::string restore_exec;        // nativeloader_restore.cfg, or empty
  std::size_t patches = 0;         // patches of the patch sets this session applies (not the skipped ones)
  bool patches_allowed = false;
  std::vector<std::string> overrides;  // module names
  std::string hooks;               // installed, not needed, or why not
  std::vector<std::string> hidden_addons;  // no runtime this session: requires_remix add-on folders hidden (ADR 0013)
  std::vector<std::string> module_dependencies;  // binary modules whose files load first, every session (ADR 0024)
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
  std::string session_token;  // PID + process creation FILETIME, for current-process menu notices
  deploy::Report deployment;
  double deployment_ms = 0;
  Activation activation;
  Session session;
  std::vector<PackageSource> packages;
  std::vector<std::string> errors;
  double startup_ms = 0;
  evidence::PreviousSession previous_session;
};

std::string serialize(const Report& report);
std::string log_fields(const Report& report);
void write(const std::filesystem::path& root, const Report& report);
// Remove only the generated status/temp files, a session marker no game holds, and the now-empty
// native-loader data folder.
void remove(fs::FileSystem& disk, const std::filesystem::path& root);
// Remove status temp files left by launches whose process has gone (write() calls it). Never throws.
void remove_stale_temporaries(const std::filesystem::path& root, std::uint32_t own_process) noexcept;
// Creates the RTX session marker (kSessionMarker) and returns its Windows handle, which the caller
// keeps open until the process ends; closing it deletes the file. The file holds the session token,
// for diagnosis. Other processes see it (a reader must share read, write and delete access), but can
// neither delete nor replace it while it is held. Throws fs::Error (a link on its path, or another
// live game holding the marker).
void* hold_session_marker(const std::filesystem::path& root, std::string_view session_token);
// Deletes a session marker that no live game holds: one a power loss or a system crash left, since
// then Windows never closed its handle. A held one stays. Never throws.
void clear_session_marker(const std::filesystem::path& root) noexcept;
}  // namespace nl::status
