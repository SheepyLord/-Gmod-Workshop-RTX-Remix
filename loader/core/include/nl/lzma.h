#pragma once
// Streaming decoder for LZMA-alone streams (".lzma": 5 properties bytes, 64-bit uncompressed size,
// then data): the wrapper gmpublish.exe uploads put around GMAD archives (Workshop *_legacy.bin).
// GMod's writer (Bootil) appends an 8-byte footer after the stream: the uncompressed size as a
// 32-bit little-endian value, then the magic 0xBEEFCACE. All 81 legacy items on the dev machine
// carry it. The footer is optional here but must match exactly when present.
// Wraps the LZMA SDK decoder in third_party/lzma. Input is untrusted: the dictionary size is
// capped, and corrupt data, early ends, overruns and any other trailing bytes are FormatErrors.

#include "nl/gma.h"

#include <cstddef>
#include <cstdint>
#include <memory>

namespace nl::lzma {

inline constexpr std::size_t kHeaderSize = 13;
inline constexpr std::uint64_t kUnknownSize = ~std::uint64_t{0};
inline constexpr std::size_t kGmodFooterSize = 8;
inline constexpr std::uint32_t kGmodFooterMagic = 0xBEEFCACEu;

struct Header {
  unsigned char properties{};          // lc + 9 * lp + 45 * pb
  std::uint32_t dictionary_size{};
  std::uint64_t uncompressed_size{};   // kUnknownSize when the stream relies on its end marker
  bool size_known() const noexcept { return uncompressed_size != kUnknownSize; }
};

struct Limits {
  std::uint32_t max_dictionary_size = std::uint32_t{256} << 20;  // same as gmapack.py
};

// Parses the 13-byte header. Throws gma::FormatError for invalid properties or a dictionary above
// the limit.
Header parse_header(const unsigned char* bytes, std::size_t size, const Limits& limits = {});

// Decodes the LZMA-alone stream that `compressed` delivers from its first byte.
class Source final : public gma::Source {
 public:
  explicit Source(std::unique_ptr<gma::Source> compressed, const Limits& limits = {});
  ~Source() override;
  Source(const Source&) = delete;
  Source& operator=(const Source&) = delete;

  std::size_t read(void* buffer, std::size_t size) override;
  const Header& header() const noexcept;
  std::uint64_t produced() const noexcept;  // decompressed bytes delivered so far
  bool gmod_footer() const noexcept;        // the stream ended with a valid GMod footer (known once read returns 0)

 private:
  struct Impl;
  std::unique_ptr<Impl> impl_;
};

}  // namespace nl::lzma
