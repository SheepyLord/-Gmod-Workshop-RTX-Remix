#include "nl/core.h"
#include "nl/version.h"

namespace nl {

std::string_view version() noexcept {
  return NL_VERSION_STRING;
}

}  // namespace nl
