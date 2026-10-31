#pragma once
#include <filesystem>
#include <string>
namespace nl::proxy::telemetry {
// Outside loader lock, after evidence collection. Worker owns a DLL reference until process exit.
// Disabling history leaves only the latest system-commit observation for the menu warning.
// Failure returns a diagnostic note; it never prevents activation.
std::string start(const std::filesystem::path& root, bool history) noexcept;
}  // namespace nl::proxy::telemetry
