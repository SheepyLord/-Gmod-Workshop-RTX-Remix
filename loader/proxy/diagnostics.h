#pragma once

#include "nl/journal.h"
#include "nl/activate.h"
#include "nl/performance.h"
#include "loader_release.h"
#include <cstdint>
#include <filesystem>
#include <optional>
#include <string>
#include <string_view>
#include <vector>

namespace nl::proxy::diagnostics {
struct GraphicsAdapter {
  std::string name;
  std::uint64_t memory = 0;
  unsigned vendor = 0;
};
struct System {
  std::string os;
  std::string cpu;
  unsigned threads = 0;
  std::uint64_t memory = 0;
  std::vector<GraphicsAdapter> graphics;
  std::optional<performance::Selection> performance_tier;
  bool rtx_active = false;
  std::optional<loader_release::Record> released_loader;

  std::uint32_t process_id = 0;
  std::string session_token;
};
System query_system();
// Pure selection for the menu: only an activating, permitted plan with a listed tier layer.
void set_performance_tier(System& system, const activate::Plan& plan, std::wstring_view command_line);
// Pure builder: no paths, account names, network identifiers or startup logs are exposed.
std::string serialize(const System& system, std::string_view version, std::string_view hash,
                      const journal::Generation& generation);
// Best-effort hardware query and hash of the installed bootstrap; failures remain display-only.
// With an effective plan, use the prepared session layers. Otherwise make a read-only preview.
std::string collect(const std::filesystem::path& root, const journal::Generation& generation,
                    const activate::Plan* effective = nullptr);
}  // namespace nl::proxy::diagnostics
