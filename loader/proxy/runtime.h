#pragma once
#include "nl/cmdline.h"
#include "nl/journal.h"
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
  bool apply(const std::filesystem::path& root, const journal::Generation& generation, status::Activation& report);
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
  bool directory_changed_ = false;
  bool touched_ = false;
  bool started_ = false;
  bool committed_ = false;
  std::chrono::steady_clock::time_point began_{};
};
bool rollback_guarded(RuntimeActivation& activation) noexcept;
}  // namespace nl::proxy
