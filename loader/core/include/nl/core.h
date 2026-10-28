#pragma once
// Public entry points of the loader core library (nl_core).

#include <string_view>

namespace nl {

// Loader version as "major.minor.patch", taken from the CMake project version.
std::string_view version() noexcept;

}  // namespace nl
