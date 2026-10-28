#include "gma_fixture.h"
#include "nl/gma.h"
#include "nl/lzma.h"
#include "nl_test.h"

#include <algorithm>
#include <filesystem>
#include <fstream>
#include <memory>
#include <string>

using nl::gma::FormatError;

namespace {

// "GMAD-lzma-test " x 4 (60 bytes), from Python:
//   lzma.compress(data, format=lzma.FORMAT_ALONE)
// Properties 0x5D, 8 MiB dictionary, size unknown (all 0xFF), ends with an end marker.
std::string sample_stream() {
  const char* hex =
      "5d00008000ffffffffffffffff0023934425ca779f379d12e9b4fdcf821d9db788722a83ffffc8370000";
  std::string bytes;
  for (const char* p = hex; p[0] && p[1]; p += 2) {
    const auto nibble = [](char c) { return c <= '9' ? c - '0' : c - 'a' + 10; };
    bytes.push_back(static_cast<char>(nibble(p[0]) << 4 | nibble(p[1])));
  }
  return bytes;
}

const std::string kSampleText = [] {
  std::string text;
  for (int i = 0; i < 4; ++i) text += "GMAD-lzma-test ";
  return text;
}();

void set_declared_size(std::string& stream, std::uint64_t size) {
  for (int i = 0; i < 8; ++i) stream[static_cast<std::size_t>(5 + i)] = static_cast<char>((size >> (8 * i)) & 0xFFu);
}

std::string decode(const std::string& stream, std::size_t chunk = 7) {
  nl::lzma::Source source(std::make_unique<nl::gma::MemorySource>(stream));
  std::string out;
  char buffer[64];
  for (;;) {
    const std::size_t n = source.read(buffer, std::min(chunk, sizeof(buffer)));
    if (!n) break;
    out.append(buffer, n);
  }
  return out;
}

}  // namespace

TEST_CASE("lzma: parses the 13-byte header") {
  const auto stream = sample_stream();
  const auto header = nl::lzma::parse_header(reinterpret_cast<const unsigned char*>(stream.data()), stream.size());
  CHECK(header.properties == 0x5D);
  CHECK(header.dictionary_size == (8u << 20));
  CHECK(!header.size_known());
}

TEST_CASE("lzma: rejects bad properties, oversized dictionaries and short headers") {
  auto stream = sample_stream();
  const auto* bytes = reinterpret_cast<const unsigned char*>(stream.data());
  CHECK_THROWS_AS(nl::lzma::parse_header(bytes, 12), FormatError);
  stream[0] = '\xE1';  // 225 = 9 * 5 * 5: first invalid properties byte
  CHECK_THROWS_AS(nl::lzma::parse_header(reinterpret_cast<const unsigned char*>(stream.data()), stream.size()), FormatError);
  nl::lzma::Limits small;
  small.max_dictionary_size = 1u << 20;
  const auto good = sample_stream();
  CHECK_THROWS_AS(nl::lzma::parse_header(reinterpret_cast<const unsigned char*>(good.data()), good.size(), small), FormatError);
}

TEST_CASE("lzma: decodes unknown-size streams that end with a marker") {
  CHECK(decode(sample_stream()) == kSampleText);
  CHECK(decode(sample_stream(), 1) == kSampleText);   // byte by byte
  CHECK(decode(sample_stream(), 64) == kSampleText);  // in one go
}

TEST_CASE("lzma: decodes known-size streams with a trailing end marker") {
  auto stream = sample_stream();
  set_declared_size(stream, kSampleText.size());
  CHECK(decode(stream) == kSampleText);
}

TEST_CASE("lzma: wrong declared sizes, truncation, trailing bytes and corruption fail") {
  auto too_big = sample_stream();
  set_declared_size(too_big, kSampleText.size() + 1);
  CHECK_THROWS_AS(decode(too_big), FormatError);

  auto too_small = sample_stream();
  set_declared_size(too_small, kSampleText.size() - 1);
  CHECK_THROWS_AS(decode(too_small), FormatError);

  const auto full = sample_stream();
  for (std::size_t n = 0; n < full.size(); ++n) {
    CHECK_THROWS_AS(decode(full.substr(0, n)), FormatError);
  }

  CHECK_THROWS_AS(decode(full + "x"), FormatError);

  auto corrupt = full;
  corrupt[20] = static_cast<char>(corrupt[20] ^ 0x5A);
  bool rejected_or_different = false;
  try {
    rejected_or_different = decode(corrupt) != kSampleText;
  } catch (const FormatError&) {
    rejected_or_different = true;
  }
  CHECK(rejected_or_different);
}

TEST_CASE("lzma: accepts GMod's 8-byte footer only when it matches") {
  const auto footer = [](std::uint32_t size, std::uint32_t magic) {
    std::string out;
    for (int i = 0; i < 4; ++i) out.push_back(static_cast<char>((size >> (8 * i)) & 0xFFu));
    for (int i = 0; i < 4; ++i) out.push_back(static_cast<char>((magic >> (8 * i)) & 0xFFu));
    return out;
  };
  const auto size = static_cast<std::uint32_t>(kSampleText.size());
  for (const bool declared : {false, true}) {
    auto stream = sample_stream();
    if (declared) set_declared_size(stream, size);
    const std::string with_footer = stream + footer(size, nl::lzma::kGmodFooterMagic);
    nl::lzma::Source source(std::make_unique<nl::gma::MemorySource>(with_footer));
    std::string out;
    char buffer[16];
    while (const std::size_t n = source.read(buffer, sizeof(buffer))) out.append(buffer, n);
    CHECK(out == kSampleText);
    CHECK(source.gmod_footer());
  }
  CHECK_THROWS_AS(decode(sample_stream() + footer(size + 1, nl::lzma::kGmodFooterMagic)), FormatError);
  CHECK_THROWS_AS(decode(sample_stream() + footer(size, 0xDEADBEEFu)), FormatError);
  CHECK_THROWS_AS(decode(sample_stream() + footer(size, nl::lzma::kGmodFooterMagic) + "x"), FormatError);
}

TEST_CASE("lzma: reads return decoded bytes before reporting later damage") {
  // Cut the stream inside its last bytes: the first read must still deliver data; only a read that
  // needs the missing part fails.
  const auto full = sample_stream();
  const std::string cut = full.substr(0, full.size() - 3);  // MemorySource views it: keep it alive
  nl::lzma::Source source(std::make_unique<nl::gma::MemorySource>(cut));
  char buffer[64];
  const std::size_t first = source.read(buffer, sizeof(buffer));
  CHECK(first > 0);
  CHECK(std::string(buffer, first) == kSampleText.substr(0, first));
  bool failed = false;
  try {
    while (source.read(buffer, sizeof(buffer))) {
    }
  } catch (const FormatError&) {
    failed = true;
  }
  CHECK(failed);
}

TEST_CASE("lzma: open_archive decodes LZMA-wrapped files") {
  // There is no encoder here, so the round trip with a real GMA inside an LZMA wrapper lives in
  // loader/cli/tests/crosscheck_gmapack.py. This case checks the plumbing.
  const auto dir = nl::test::scratch_dir("lzma_open_archive");
  const auto path = dir / "wrapped.gma";
  const auto stream = sample_stream();
  std::ofstream(path, std::ios::binary).write(stream.data(), static_cast<std::streamsize>(stream.size()));
  nl::gma::Container kind{};
  {
    const auto source = nl::gma::open_archive(path, &kind);
    CHECK(kind == nl::gma::Container::lzma);
    // The payload is text, not GMAD, so parsing it as an index must fail cleanly.
    CHECK_THROWS_AS(nl::gma::read_index(*source), FormatError);
  }
  std::filesystem::remove_all(dir);
}
