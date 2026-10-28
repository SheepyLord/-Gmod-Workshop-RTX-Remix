#pragma once
// Machine-readable M4 startup result, shared with tests and uninstall; schema documented on disk.
#include "nl/activate.h"
#include "nl/deploy.h"
#include <cstdint>
#include <filesystem>
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
struct Report {
  std::string loader_version;
  std::string utc;
  std::uint32_t process_id = 0;
  deploy::Report deployment;
  double deployment_ms = 0;
  Activation activation;
  std::vector<std::string> errors;
  double startup_ms = 0;
};

std::string serialize(const Report& report);
std::string log_fields(const Report& report);
void write(const std::filesystem::path& root, const Report& report);
// Remove only the generated status/temp files and the now-empty native-loader data folder.
void remove(fs::FileSystem& disk, const std::filesystem::path& root);
}  // namespace nl::status
