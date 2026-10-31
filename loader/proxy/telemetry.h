#pragma once
#include <filesystem>
#include <string_view>
namespace nl::proxy::telemetry {
// Outside loader lock, after evidence collection. Worker owns a DLL reference until process exit.
// Disabling history leaves only the latest system-commit observation for the menu warning.
// Failure returns a static diagnostic note without allocating; it never prevents activation.
std::string_view start(const std::filesystem::path& root, bool history) noexcept;
}  // namespace nl::proxy::telemetry
