#pragma once

#include "nl/journal.h"
#include <cstdint>
#include <filesystem>
#include <string>
#include <string_view>
#include <vector>

namespace nl::proxy::diagnostics {
struct GraphicsAdapter {
  std::string name;
  std::uint64_t memory = 0;
};
struct System {
  std::string os;
  std::string cpu;
  unsigned threads = 0;
  std::uint64_t memory = 0;
  std::vector<GraphicsAdapter> graphics;
  std::uint32_t process_id = 0;
  std::string session_token;
};
System query_system();
// Pure builder: no paths, account names, network identifiers or startup logs are exposed.
std::string serialize(const System& system, std::string_view version, std::string_view hash,
                      const journal::Generation& generation);
// Best-effort hardware query and hash of the installed bootstrap; failures remain display-only.
std::string collect(const std::filesystem::path& root, const journal::Generation& generation);
}  // namespace nl::proxy::diagnostics
