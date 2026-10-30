#pragma once
// Static legacy-runtime identification. No library is loaded or executable code called. This is
// classification for backup planning, never a native-code trust/allowlisting decision.

#include <filesystem>
#include <string_view>

namespace nl::legacy {

inline constexpr std::string_view kRemixExport = "remixapi_InitializeLibrary";

// A structurally valid PE32/x86 or PE32+/x64 DLL with this named export. Aliases and valid
// forwarded exports are accepted. Header/table/RVA/string failures and unsupported machines give
// false. Defined over file bytes, not an already mapped image. Exposed for generated-fixture tests.
bool exports_function(std::string_view bytes, std::string_view name) noexcept;

// An ordinary file, reached without links or junctions, exporting kRemixExport. Uses bounded
// sparse reads rather than loading the whole image; unreadable, changing or malformed files give false.
bool is_remix_runtime(const std::filesystem::path& file) noexcept;

}  // namespace nl::legacy
