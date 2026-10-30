#include "nl/legacy_detect.h"
#include "nl_test.h"

#include <cstdlib>
#include <filesystem>
#include <fstream>
#include <string>

namespace {
constexpr std::size_t kPe = 0x80, kCoff = kPe + 4, kOptional = kCoff + 20;
constexpr std::size_t kRaw = 0x200;
void put16(std::string& bytes, std::size_t at, unsigned value) {
  bytes.at(at) = static_cast<char>(value & 0xff);
  bytes.at(at + 1) = static_cast<char>((value >> 8) & 0xff);
}
void put32(std::string& bytes, std::size_t at, unsigned value) {
  put16(bytes, at, value & 0xffff); put16(bytes, at + 2, value >> 16);
}
void text(std::string& bytes, std::size_t at, const std::string& value) {
  bytes.replace(at, value.size(), value); bytes.at(at + value.size()) = '\0';
}
std::string fixture(bool x64 = true) {
  std::string bytes(0x800, '\0');
  put16(bytes, 0, 0x5a4d); put32(bytes, 0x3c, kPe); put32(bytes, kPe, 0x00004550);
  put16(bytes, kCoff, x64 ? 0x8664 : 0x014c); put16(bytes, kCoff + 2, 1);
  put16(bytes, kCoff + 16, x64 ? 0xf0 : 0xe0); put16(bytes, kCoff + 18, 0x2002);
  put16(bytes, kOptional, x64 ? 0x20b : 0x10b);
  put32(bytes, kOptional + 56, 0x3000); put32(bytes, kOptional + 60, 0x200);
  const auto directory = kOptional + (x64 ? 112 : 96);
  put32(bytes, directory - 4, 16); put32(bytes, directory, 0x1000); put32(bytes, directory + 4, 0x200);
  const auto section = kOptional + (x64 ? 0xf0 : 0xe0);
  text(bytes, section, ".text"); put32(bytes, section + 8, 0x1000); put32(bytes, section + 12, 0x1000);
  put32(bytes, section + 16, 0x600); put32(bytes, section + 20, kRaw); put32(bytes, section + 36, 0x60000020);
  put32(bytes, kRaw + 20, 1); put32(bytes, kRaw + 24, 1); put32(bytes, kRaw + 28, 0x1040);
  put32(bytes, kRaw + 32, 0x1050); put32(bytes, kRaw + 36, 0x1060);
  put32(bytes, kRaw + 0x40, 0x1400); put32(bytes, kRaw + 0x50, 0x1080); put16(bytes, kRaw + 0x60, 0);
  text(bytes, kRaw + 0x80, std::string(nl::legacy::kRemixExport));
  bytes[kRaw + 0x400] = static_cast<char>(0xc3);
  return bytes;
}
void write(const std::filesystem::path& path, const std::string& bytes) {
  std::filesystem::create_directories(path.parent_path());
  std::ofstream(path, std::ios::binary).write(bytes.data(), static_cast<std::streamsize>(bytes.size()));
}
bool detect(const std::string& bytes) { return nl::legacy::exports_function(bytes, nl::legacy::kRemixExport); }
}  // namespace

TEST_CASE("legacy detect: reads x86 and x64 PE DLL named exports without executing an image") {
  CHECK(detect(fixture())); CHECK(detect(fixture(false)));
  CHECK(!nl::legacy::exports_function(fixture(), "Direct3DCreate9"));
  CHECK(!nl::legacy::exports_function(fixture(), ""));
  CHECK(!nl::legacy::exports_function(fixture(), std::string_view("remixapi\0_InitializeLibrary", 26)));
}

TEST_CASE("legacy detect: requires the named export rather than a string or a generic DXVK proxy") {
  auto bytes = fixture();
  text(bytes, kRaw + 0x80, "Direct3DCreate9");
  text(bytes, kRaw + 0x300, std::string(nl::legacy::kRemixExport));
  CHECK(!detect(bytes));
  CHECK(nl::legacy::exports_function(bytes, "Direct3DCreate9"));
  CHECK(!detect(std::string(nl::legacy::kRemixExport)));
}

TEST_CASE("legacy detect: accepts aliases and properly bounded forwarded exports") {
  auto bytes = fixture();
  put32(bytes, kRaw + 24, 2); put32(bytes, kRaw + 0x54, 0x10c0); put16(bytes, kRaw + 0x62, 0);
  text(bytes, kRaw + 0xc0, "RemixAlias");
  CHECK(detect(bytes)); CHECK(nl::legacy::exports_function(bytes, "RemixAlias"));
  put32(bytes, kRaw + 0x40, 0x1100); text(bytes, kRaw + 0x100, "remix_backend.remixapi_InitializeLibrary");
  CHECK(detect(bytes));
  text(bytes, kRaw + 0x100, "remix_backend.#17"); CHECK(detect(bytes));
  text(bytes, kRaw + 0x100, "remix_backend.#0"); CHECK(!detect(bytes));
  text(bytes, kRaw + 0x100, "remix_backend.#65536"); CHECK(!detect(bytes));
  text(bytes, kRaw + 0x100, "remix_backend.#name"); CHECK(!detect(bytes));
  text(bytes, kRaw + 0x100, "not-a-forwarder"); CHECK(!detect(bytes));
}

TEST_CASE("legacy detect: malformed headers architectures tables and ordinals fail closed") {
  const auto original = fixture();
  for (std::size_t size : {std::size_t{0}, std::size_t{1}, std::size_t{0x3f}, std::size_t{0x100}, std::size_t{0x210}})
    CHECK(!detect(original.substr(0, size)));
  auto changed = original; put32(changed, 0x3c, 0xfffffff0); CHECK(!detect(changed));
  changed = original; put16(changed, kCoff, 0xaa64); CHECK(!detect(changed));
  changed = original; put16(changed, kCoff + 18, 2); CHECK(!detect(changed)); // executable, not DLL
  changed = original; put16(changed, kOptional, 0x10b); CHECK(!detect(changed)); // machine/magic mismatch
  changed = original; put16(changed, kCoff + 2, 97); CHECK(!detect(changed));
  changed = original; put16(changed, kCoff + 16, 20); CHECK(!detect(changed));
  changed = original; put32(changed, kOptional + 108, 0); CHECK(!detect(changed));
  changed = original; put32(changed, kOptional + 112, 0xfffffff0); CHECK(!detect(changed));
  changed = original; put32(changed, kRaw + 20, 0xffffffff); CHECK(!detect(changed));
  changed = original; put32(changed, kRaw + 32, 0xfffffff0); CHECK(!detect(changed));
  changed = original; put16(changed, kRaw + 0x60, 1); CHECK(!detect(changed));
  changed = original; put32(changed, kRaw + 0x40, 0); CHECK(!detect(changed));
  changed = original; put32(changed, kRaw + 0x40, 0x2500); CHECK(!detect(changed)); // unmapped code
}

TEST_CASE("legacy detect: rejects section overflows zero-fill RVAs ambiguous mappings and unterminated strings") {
  const auto section = kOptional + 0xf0;
  auto bytes = fixture(); put32(bytes, section + 12, 0xfffffff0); CHECK(!detect(bytes));
  bytes = fixture(); put32(bytes, section + 20, 0xffffff00); CHECK(!detect(bytes));
  bytes = fixture(); put32(bytes, kRaw + 0x50, 0x1700); CHECK(!detect(bytes)); // zero-filled rather than raw bytes
  bytes = fixture(); put16(bytes, kCoff + 2, 2);
  for (std::size_t i = 0; i < 40; ++i) bytes[section + 40 + i] = bytes[section + i];
  CHECK(!detect(bytes));
  bytes = fixture(); put32(bytes, kRaw + 0x50, 0x15f8); bytes.replace(0x7f8, 8, 8, 'A'); CHECK(!detect(bytes));
  bytes = fixture(); put32(bytes, kRaw + 0x40, 0x11f8); bytes.replace(0x3f8, 8, "dll.func"); CHECK(!detect(bytes));
}

TEST_CASE("legacy detect: ordinary file wrapper refuses absent files directories and junction ancestors") {
  namespace fs = std::filesystem;
  const auto root = nl::test::scratch_dir("legacy_detect");
  const auto file = root / "ordinary/d3d9.dll";
  write(file, fixture());
  CHECK(nl::legacy::is_remix_runtime(file));
  CHECK(!nl::legacy::is_remix_runtime(root / "missing.dll"));
  CHECK(!nl::legacy::is_remix_runtime(root / "ordinary"));
  CHECK(!nl::legacy::is_remix_runtime(root / "ordinary/../ordinary/d3d9.dll"));
  write(root / "malformed.dll", "MZ");
  CHECK(!nl::legacy::is_remix_runtime(root / "malformed.dll"));
  const auto junction = root / "linked";
  const auto command = "cmd /c mklink /J \"" + junction.string() + "\" \"" + (root / "ordinary").string() + "\" >nul";
  REQUIRE(std::system(command.c_str()) == 0);
  CHECK(!nl::legacy::is_remix_runtime(junction / "d3d9.dll"));
  fs::remove(junction); fs::remove_all(root);
}

TEST_CASE("legacy detect: sparse reader reaches distant sections and checks cross-page strings") {
  namespace fs = std::filesystem;
  const auto root = nl::test::scratch_dir("legacy_detect_sparse");
  const auto path = root / "d3d9.dll";
  auto bytes = fixture();
  constexpr unsigned distant_raw = 16 * 1024 * 1024 + 0xe00;
  put32(bytes, kOptional + 0xf0 + 20, distant_raw);
  // The section and export names straddle a 4 KiB source-page boundary.
  put32(bytes, kRaw + 0x50, 0x11f8);
  text(bytes, kRaw + 0x1f8, std::string(nl::legacy::kRemixExport));
  {
    std::ofstream output(path, std::ios::binary);
    output.write(bytes.data(), kRaw);
    output.seekp(distant_raw);
    output.write(bytes.data() + kRaw, static_cast<std::streamsize>(bytes.size() - kRaw));
    REQUIRE(output.good());
  }
  CHECK(nl::legacy::is_remix_runtime(path));
  fs::resize_file(path, distant_raw + 0x1ff);
  CHECK(!nl::legacy::is_remix_runtime(path));
  fs::remove_all(root);
}
