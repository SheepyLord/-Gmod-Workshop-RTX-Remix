#include "gma_fixture.h"
#include "nl/gma.h"
#include "nl_test.h"

#include <filesystem>
#include <fstream>
#include <limits>

using nl::gma::FormatError;
using nl::test::build_gma;
using nl::test::FixtureArchive;

namespace {

FixtureArchive sample() {
  FixtureArchive archive;
  archive.required_content = {"base"};
  archive.files = {
      {"lua/autorun/a.lua", "print('a')"},
      {"materials/x.vmt", "\"LightmappedGeneric\" {}"},
      {"empty.txt", ""},
  };
  return archive;
}

nl::gma::Index index_of(const std::string& bytes, const nl::gma::Limits& limits = {}) {
  nl::gma::MemorySource source(bytes);
  return nl::gma::read_index(source, limits);
}

nl::gma::VerifyReport verify_bytes(const std::string& bytes) {
  nl::gma::MemorySource source(bytes);
  return nl::gma::verify(source);
}

std::string flip(std::string bytes, std::uint64_t at) {
  bytes[static_cast<std::size_t>(at)] = static_cast<char>(bytes[static_cast<std::size_t>(at)] ^ 0x01);
  return bytes;
}

}  // namespace

TEST_CASE("gma: reads header, file index and offsets") {
  const FixtureArchive archive = sample();
  std::uint64_t data_offset = 0;
  const auto index = index_of(build_gma(archive, &data_offset));
  CHECK(index.version == 3);
  CHECK(index.timestamp == archive.timestamp);
  REQUIRE(index.required_content.size() == 1);
  CHECK(index.required_content[0] == "base");
  CHECK(index.title == archive.title);
  CHECK(index.description == archive.description);
  CHECK(index.author == archive.author);
  CHECK(index.addon_version == 1);
  REQUIRE(index.entries.size() == 3);
  CHECK(index.data_offset == data_offset);
  CHECK(index.entries[0].number == 1);
  CHECK(index.entries[2].number == 3);
  CHECK(index.entries[0].path == "lua/autorun/a.lua");
  CHECK(index.entries[0].offset == data_offset);
  CHECK(index.entries[1].offset == data_offset + archive.files[0].data.size());
  CHECK(index.entries[1].crc32 == nl::crc32(archive.files[1].data.data(), archive.files[1].data.size()));
  CHECK(index.entries[2].size == 0);
  CHECK(index.data_end == data_offset + archive.files[0].data.size() + archive.files[1].data.size());
}

TEST_CASE("gma: versions 1 and 2 parse; version 1 has no required content") {
  for (const std::uint8_t version : {std::uint8_t{1}, std::uint8_t{2}}) {
    FixtureArchive archive = sample();
    archive.version = version;
    const auto index = index_of(build_gma(archive));
    CHECK(index.version == version);
    CHECK(index.entries.size() == 3);
    CHECK(index.required_content.size() == (version == 1 ? 0u : 1u));
  }
}

TEST_CASE("gma: every truncation inside header or index is a FormatError") {
  std::uint64_t data_offset = 0;
  const auto bytes = build_gma(sample(), &data_offset);
  for (std::size_t n = 0; n < data_offset; ++n) {
    CHECK_THROWS_AS(index_of(bytes.substr(0, n)), FormatError);
  }
}

TEST_CASE("gma: rejects bad identifiers, versions, names and sizes") {
  const auto good = build_gma(sample());
  CHECK_THROWS_AS(index_of("GMAX" + good.substr(4)), FormatError);
  for (const char version : {'\0', '\x04'}) {
    std::string bytes = good;
    bytes[4] = version;
    CHECK_THROWS_AS(index_of(bytes), FormatError);
  }
  FixtureArchive empty_name = sample();
  empty_name.files[1].path = "";
  CHECK_THROWS_AS(index_of(build_gma(empty_name)), FormatError);
  FixtureArchive duplicate = sample();
  duplicate.files[1].path = "LUA\\AUTORUN\\A.lua";
  CHECK_THROWS_AS(index_of(build_gma(duplicate)), FormatError);
  FixtureArchive negative = sample();
  negative.files[0].size = -1;
  CHECK_THROWS_AS(index_of(build_gma(negative)), FormatError);
}

TEST_CASE("gma: enforces string, entry-count and size-sum limits") {
  nl::gma::Limits short_strings;
  short_strings.max_string_bytes = 8;  // the title "Test addon" has 10 bytes
  CHECK_THROWS_AS(index_of(build_gma(sample()), short_strings), FormatError);
  nl::gma::Limits few_entries;
  few_entries.max_entries = 2;
  CHECK_THROWS_AS(index_of(build_gma(sample()), few_entries), FormatError);
  FixtureArchive huge = sample();
  for (auto& file : huge.files) file.size = std::numeric_limits<std::int64_t>::max();
  CHECK_THROWS_AS(index_of(build_gma(huge)), FormatError);
}

TEST_CASE("gma: verify accepts intact archives and reports damage") {
  const FixtureArchive archive = sample();
  std::uint64_t data_offset = 0;
  const auto good = build_gma(archive, &data_offset);
  const auto intact = verify_bytes(good);
  CHECK(intact.ok());
  CHECK(intact.addon_crc_stored != 0);
  CHECK(intact.addon_crc_stored == intact.addon_crc_actual);

  const auto damaged = verify_bytes(flip(good, data_offset + archive.files[0].data.size()));
  CHECK(!damaged.ok());
  REQUIRE(damaged.bad_entries.size() == 1);
  CHECK(damaged.bad_entries[0] == 1);
  CHECK(damaged.addon_crc_stored != damaged.addon_crc_actual);

  FixtureArchive trailing = sample();
  trailing.trailing = "junk";
  const auto with_tail = verify_bytes(build_gma(trailing));
  CHECK(!with_tail.ok());
  CHECK(with_tail.trailing_bytes == 4);

  // Cut anywhere inside the contents or the trailer: truncated. Cut exactly at the end of the
  // contents: a valid archive without a trailer.
  for (std::size_t n = static_cast<std::size_t>(data_offset); n < good.size(); ++n) {
    if (n == good.size() - 4) continue;
    CHECK_THROWS_AS(verify_bytes(good.substr(0, n)), FormatError);
  }
}

TEST_CASE("gma: the addon CRC trailer is optional") {
  FixtureArchive archive = sample();
  archive.crc_trailer = false;
  const auto bytes = build_gma(archive);
  const auto report = verify_bytes(bytes);
  CHECK(report.ok());
  CHECK(!report.crc_trailer);
  CHECK(report.addon_crc_stored == 0);
  CHECK(report.trailing_bytes == 0);
  CHECK(index_of(bytes).data_end == bytes.size());

  const auto with_trailer = verify_bytes(build_gma(sample()));
  CHECK(with_trailer.crc_trailer);
  for (int partial = 1; partial <= 3; ++partial) {
    CHECK_THROWS_AS(verify_bytes(bytes + std::string(static_cast<std::size_t>(partial), '\0')), FormatError);
  }
}

TEST_CASE("gma: zero CRCs mean unchecked, as gmad -nocrc writes them") {
  FixtureArchive archive = sample();
  archive.addon_crc = false;
  for (auto& file : archive.files) file.crc = 0u;
  std::uint64_t data_offset = 0;
  const auto bytes = build_gma(archive, &data_offset);
  const auto report = verify_bytes(flip(bytes, data_offset));
  CHECK(report.ok());
  CHECK(report.addon_crc_stored == 0);
}

TEST_CASE("gma: detects the container from the first bytes") {
  using nl::gma::Container;
  using nl::gma::detect_container;
  CHECK(detect_container("GMAD\x03") == Container::gmad);
  CHECK(detect_container(std::string_view("\x5d\0\0\0\x01\xff\xff\xff\xff\xff\xff\xff\xff", 13)) == Container::lzma);
  CHECK(detect_container(std::string_view("\xff" "123456789012", 13)) == Container::unknown);
  CHECK(detect_container("GM") == Container::unknown);
}

TEST_CASE("gma: path keys fold ASCII case and backslashes only") {
  CHECK(nl::gma::path_key("Lua\\AutoRun\\A.LUA") == "lua/autorun/a.lua");
  CHECK(nl::gma::path_key("materials/\xC3\x84.vmt") == "materials/\xC3\x84.vmt");
}

TEST_CASE("gma: open_archive reads plain files and LZMA wrappers") {
  const auto dir = nl::test::scratch_dir("gma_open_archive");
  const auto plain = dir / "sample.gma";
  const auto bytes = build_gma(sample());
  std::ofstream(plain, std::ios::binary).write(bytes.data(), static_cast<std::streamsize>(bytes.size()));

  nl::gma::Container kind{};
  {
    const auto source = nl::gma::open_archive(plain, &kind);  // closed at the end of this block
    CHECK(kind == nl::gma::Container::gmad);
    const auto report = nl::gma::verify(*source);
    CHECK(report.ok());
    CHECK(report.index.entries.size() == 3);
  }

  const auto wrapped = dir / "wrapped.gma";
  const std::string header = std::string("\x5d\0\0\0\x01", 5) + std::string(8, '\xff') + "xyz";
  std::ofstream(wrapped, std::ios::binary).write(header.data(), static_cast<std::streamsize>(header.size()));
  {
    // The header is valid, so opening succeeds; the 3-byte "payload" is not an LZMA stream.
    const auto source = nl::gma::open_archive(wrapped, &kind);
    CHECK(kind == nl::gma::Container::lzma);
    CHECK_THROWS_AS(nl::gma::read_index(*source), FormatError);
  }

  CHECK_THROWS_AS(nl::gma::FileSource(dir / "missing.gma"), std::filesystem::filesystem_error);
  std::filesystem::remove_all(dir);
}

namespace {

// Records what extract() delivers.
class Collect final : public nl::gma::EntrySink {
 public:
  void begin(const nl::gma::Entry& entry) override {
    order.push_back(entry.path);
    bytes.emplace_back();
  }
  void data(const unsigned char* chunk, std::size_t size) override { bytes.back().append(reinterpret_cast<const char*>(chunk), size); }
  void end(const nl::gma::Entry&) override { ++ended; }

  std::vector<std::string> order;
  std::vector<std::string> bytes;
  int ended = 0;
};

}  // namespace

TEST_CASE("gma: extract delivers the wanted files in one pass, skips the rest and checks CRCs") {
  const auto dir = nl::test::scratch_dir("gma_extract");
  FixtureArchive archive;
  archive.files = {{"a.txt", "alpha"}, {"big.bin", std::string(300000, 'b')}, {"c.txt", "gamma"}, {"d.txt", "delta"}};
  const auto file = dir / "pack.gma";
  const auto bytes = build_gma(archive);
  std::ofstream(file, std::ios::binary).write(bytes.data(), static_cast<std::streamsize>(bytes.size()));

  Collect some;
  const auto index = nl::gma::extract(file, [](const nl::gma::Entry& e) { return e.path == "a.txt" || e.path == "c.txt"; }, some);
  CHECK(index.entries.size() == 4);
  CHECK((some.order == std::vector<std::string>{"a.txt", "c.txt"}));
  CHECK((some.bytes == std::vector<std::string>{"alpha", "gamma"}));
  CHECK(some.ended == 2);

  archive.files[2].crc = 12345;  // c.txt now fails its CRC
  const auto damaged = dir / "damaged.gma";
  const auto bad = build_gma(archive);
  std::ofstream(damaged, std::ios::binary).write(bad.data(), static_cast<std::streamsize>(bad.size()));
  Collect all;
  CHECK_THROWS_AS(nl::gma::extract(damaged, [](const nl::gma::Entry&) { return true; }, all), FormatError);
  CHECK(all.order.size() == 3);
  CHECK(all.ended == 2);  // end() is never called for the file that failed

  Collect none;
  nl::gma::extract(file, [](const nl::gma::Entry&) { return false; }, none);
  CHECK(none.order.empty());
  std::filesystem::remove_all(dir);
}
