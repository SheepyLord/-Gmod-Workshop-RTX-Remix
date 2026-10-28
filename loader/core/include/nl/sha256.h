#pragma once
// SHA-256 from Windows CNG. bcrypt.dll is loaded from System32 by full path the first time a hash
// is made, the way the bootstrap loads the real winmm.dll, so the bootstrap (which links nl_core)
// keeps an import table of KERNEL32 only and never looks for bcrypt.dll in bin\win64.

#include <array>
#include <cstddef>
#include <cstdint>
#include <stdexcept>
#include <string>
#include <string_view>

namespace nl::sha256 {

// CNG could not be loaded or failed.
class Error : public std::runtime_error {
 public:
  using std::runtime_error::runtime_error;
};

using Digest = std::array<std::uint8_t, 32>;

// Incremental hash: update() any number of times, then finish() once.
class Hasher {
 public:
  Hasher();
  ~Hasher();
  Hasher(const Hasher&) = delete;
  Hasher& operator=(const Hasher&) = delete;

  void update(const void* data, std::size_t size);
  Digest finish();
  std::string finish_hex();  // 64 lowercase hex digits

 private:
  void* handle_ = nullptr;
};

std::string to_hex(const Digest& digest);

// Hex digest of `bytes`.
std::string of(std::string_view bytes);

}  // namespace nl::sha256
