#include "modules.h"
#include "nl/fs.h"
#include "nl_test.h"
#include <windows.h>
#include <filesystem>
#include <fstream>

TEST_CASE("presentation: filesystem IAT redirects only exact read-only opens and restores pass-through") {
  namespace fs = std::filesystem;
  namespace hooks = nl::proxy::modules;
  const auto root = nl::test::scratch_dir("presentation-hooks");
  const auto source = root / "workshop.gma";
  const auto replacement = root / "native-loader/presentation/display.gma";
  const auto other = root / "unrelated.gma";
  fs::create_directories(replacement.parent_path());
  fs::create_directories(root / "bin/win64");
  std::ofstream(source, std::ios::binary) << "original";
  std::ofstream(replacement, std::ios::binary) << "display facade";
  std::ofstream(other, std::ios::binary) << "other";
  const auto dll = root / "bin/win64/filesystem_stdio.dll";
  fs::copy_file(NL_PRESENTATION_FIXTURE_PATH, dll);
  hooks::Setup setup;
  setup.root = root;
  setup.read_redirects.emplace_back(source, replacement);
  std::string error;
  CHECK(hooks::install(std::move(setup), error));
  const HMODULE module = LoadLibraryW(dll.c_str());
  CHECK(module != nullptr);
  const auto open_a = reinterpret_cast<const char* (*)(const char*, DWORD, DWORD)>(GetProcAddress(module, "nl_display_open_a"));
  const auto open_w = reinterpret_cast<const char* (*)(const wchar_t*, DWORD, DWORD)>(GetProcAddress(module, "nl_display_open_w"));
  const auto size_a = reinterpret_cast<unsigned long long (*)(const char*)>(GetProcAddress(module, "nl_display_size_a"));
  const auto size_w = reinterpret_cast<unsigned long long (*)(const wchar_t*)>(GetProcAddress(module, "nl_display_size_w"));
  CHECK(open_a && open_w && size_a && size_w);
  if (module && open_a && open_w && size_a && size_w) {
    const auto requested = nl::fs::utf8(source);
    CHECK(std::string(open_a(requested.c_str(), GENERIC_READ, OPEN_EXISTING)).ends_with("display.gma"));
    CHECK(std::string(open_w(source.c_str(), GENERIC_READ, OPEN_EXISTING)).ends_with("display.gma"));
    CHECK(size_a(requested.c_str()) == fs::file_size(replacement));
    CHECK(size_w(source.c_str()) == fs::file_size(replacement));
    CHECK(std::string(open_a(requested.c_str(), GENERIC_READ | GENERIC_WRITE, OPEN_EXISTING)).ends_with("workshop.gma"));
    CHECK(std::string(open_w(source.c_str(), GENERIC_READ, OPEN_ALWAYS)).ends_with("workshop.gma"));
    CHECK(std::string(open_w(other.c_str(), GENERIC_READ, OPEN_EXISTING)).ends_with("unrelated.gma"));
    // Calls from this test executable are outside filesystem_stdio.dll and remain untouched.
    CHECK(nl::fs::read_file(source, 100) == "original");
    CHECK(hooks::results_json().find("workshop.gma") != std::string::npos);
    // A replaced/edited cache is not used; neither file is overwritten or repaired.
    std::ofstream(replacement, std::ios::binary | std::ios::app) << " edited";
    CHECK(std::string(open_w(source.c_str(), GENERIC_READ, OPEN_EXISTING)).ends_with("workshop.gma"));
    hooks::uninstall();
    CHECK(size_w(source.c_str()) == fs::file_size(source));
    CHECK(std::string(open_w(source.c_str(), GENERIC_READ, OPEN_EXISTING)).ends_with("workshop.gma"));
  } else hooks::uninstall();
  if (module) FreeLibrary(module);
  fs::remove_all(root);
}

TEST_CASE("presentation: redirect cache boundary rejects embedded parent components") {
  namespace fs = std::filesystem;
  namespace hooks = nl::proxy::modules;
  const auto root = nl::test::scratch_dir("presentation-hook-boundary");
  fs::create_directories(root / "native-loader/presentation");
  std::ofstream(root / "escape.gma") << "outside the cache";
  hooks::Setup setup;
  setup.root = root;
  setup.read_redirects.emplace_back(root / "source.gma", root / "native-loader/presentation/../../escape.gma");
  std::string error;
  CHECK(!hooks::install(std::move(setup), error));
  CHECK(error.find("outside its cache") != std::string::npos);
  hooks::uninstall();
  fs::remove_all(root);
}
