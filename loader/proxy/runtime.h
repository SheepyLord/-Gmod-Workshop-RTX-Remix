#pragma once
#include "nl/cmdline.h"
#include "nl/journal.h"
#include "nl/session.h"
#include "nl/status.h"
#include <windows.h>
#include <chrono>
#include <filesystem>
#include <optional>
#include <string>
#include <vector>

namespace nl::proxy {
// Owned outside the SEH frame, so native faults cannot bypass activation rollback.
class RuntimeActivation {
 public:
  ~RuntimeActivation();
  RuntimeActivation() = default;
  RuntimeActivation(const RuntimeActivation&) = delete;
  RuntimeActivation& operator=(const RuntimeActivation&) = delete;
  bool apply(const std::filesystem::path& root, const journal::Generation& generation, status::Activation& report,
             status::Session& session);
  bool rollback() noexcept;
  void commit() noexcept;
  bool touched() const noexcept { return touched_; }
  bool committed() const noexcept { return committed_; }
  double elapsed_ms() const noexcept;
 private:
  struct Environment {
    std::wstring name;
    std::wstring value;
    std::optional<std::wstring> previous;
    bool attempted = false;
  };
  std::vector<Environment> environment_;
  cmdline::SwapResult command_line_;
  HMODULE vulkan_ = nullptr;
  HMODULE runtime_ = nullptr;
  DLL_DIRECTORY_COOKIE dll_directory_ = nullptr;  // the runtime folder for loads that search user folders
  bool directory_changed_ = false;
  bool hooks_installed_ = false;
  bool touched_ = false;
  bool started_ = false;
  bool committed_ = false;
  std::chrono::steady_clock::time_point began_{};
};
bool rollback_guarded(RuntimeActivation& activation) noexcept;

// Session console variables (M5, ADR 0010): reads config.cfg and the restore record, writes the record
// and the cfg this start needs (only when their content changes), and returns the +exec arguments.
std::vector<std::string> session_cvars(const std::filesystem::path& root, bool rtx, const session::Values& cvars,
                                       status::Session& report);
// A start without RTX: the restore's +exec is in the command line now, so the record is done with.
void mark_restore_issued(const std::filesystem::path& root);
}  // namespace nl::proxy
