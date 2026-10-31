#pragma once
#include <string>
#include <string_view>

namespace nl::proxy::backend {

struct Selection {
  std::wstring line;
  bool changed = false;
  std::size_t explicit_choices = 0;
};

// Pure process-only compatibility choice. Each explicit selector becomes the stock D3D9 backend;
// repeated options agree regardless of the engine's precedence. Other raw spans stay unchanged.
Selection select(std::wstring_view command_line, bool rtx_active);

}  // namespace nl::proxy::backend
