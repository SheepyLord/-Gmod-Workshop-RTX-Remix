#include "early.h"
#include "catalog.h"
#include "nl/fs.h"
#include "nl/sha256.h"
#include "nl_test.h"

#include <chrono>
#include <cstdio>
#include <cstdlib>
#include <filesystem>
#include <stdexcept>
#include <string>
#include <string_view>
#include <utility>

namespace {
namespace fs = std::filesystem;
constexpr std::string_view kGuardFile =
    "garrysmod/addons/nativeloader/lua/autorun/_nativeloader_guard.lua";
constexpr std::string_view kStockBytes =
    "-- Generated initializer fixture, not a Steam file.\n"
    "FIXTURE_STOCK_INITIALIZED = true\n";
constexpr std::string_view kGuardBytes =
    "-- NATIVELOADER_RENDER_GUARD_V2\n"
    "local generated_guard_value = 'verified fixture only'\n"
    "return generated_guard_value\n";
constexpr std::string_view kModuleBytes = "generated verified native bootstrap fixture";
constexpr std::string_view kProof = "native-loader/presentation/render-guard-fixture.lua";

void write(const fs::path& path, std::string_view bytes) {
  // Extended-length paths: cache file names are long, and so are some checkouts' scratch folders.
  fs::create_directories(fs::path(nl::fs::long_path(path.parent_path())));
  nl::fs::write_atomic(nl::fs::win32(), path, bytes);
}

std::string read(const fs::path& path) {
  return nl::fs::read_file(path, std::size_t{4} << 20);
}

struct Fixture {
  fs::path folder;
  fs::path root;
  nl::config::Config config;
  nl::journal::Generation generation;
  std::string stock{ kStockBytes };
  std::string guard{ kGuardBytes };

  explicit Fixture(std::string_view name)
      : folder(nl::test::scratch_dir(name)), root(folder / "game") {
    fs::create_directories(root / "native-loader");
    config.from_file = true;
    config.local = {"native-package.gma"};
    nl::journal::Package package;
    package.id = nl::client::kPackage;
    package.version = "1.2.3+generated-fixture";
    package.manifest_sha256 = std::string(64, 'a');
    package.source = "local";
    package.location = "native-package.gma";
    package.payload = "native-loader/packages/gmod-rtx-remix/fixture_1";
    package.requires_remix = true;
    nl::manifest::Remix remix;
    remix.entry = "runtime/d3d9.dll";
    package.remix = remix;
    generation.number = 1;
    generation.packages.push_back(std::move(package));
    add(std::string(nl::client::kModule), kModuleBytes);
    add(std::string(kGuardFile), guard);
    write(stock_path(), stock);
  }
  ~Fixture() {
    try { nl::fs::remove_tree(nl::fs::win32(), folder); } catch (...) { }
  }
  fs::path stock_path() const { return nl::fs::join(root, nl::guard::kInit); }
  fs::path guard_path() const { return nl::fs::join(root, kGuardFile); }
  fs::path cache_path() const { return root / "native-loader/presentation"; }
  void add(std::string path, std::string_view bytes,
           std::string owner = std::string(nl::client::kPackage)) {
    write(nl::fs::join(root, path), bytes);
    nl::journal::File file;
    file.path = std::move(path);
    file.package = std::move(owner);
    file.sha256 = nl::sha256::of(bytes);
    file.size = bytes.size();
    generation.files.push_back(std::move(file));
  }
  void replace_verified_guard(std::string_view bytes) {
    guard.assign(bytes);
    write(guard_path(), bytes);
    for (auto& file : generation.files) {
      if (file.path == kGuardFile && file.package == nl::client::kPackage) {
        file.sha256 = nl::sha256::of(bytes);
        file.size = bytes.size();
        return;
      }
    }
    throw std::runtime_error("missing generated guard record");
  }
  std::optional<nl::guard::Redirect> prepare() const {
    return nl::guard::prepare(root, config, generation, nl::client::kPackage, nl::sha256::of(stock));
  }
};

bool junction(const fs::path& path, const fs::path& target) {
  const std::string command = "cmd /d /v:off /c mklink /J \"" + path.string() +
      "\" \"" + target.string() + "\" >nul";
  return std::system(command.c_str()) == 0;
}
}

TEST_CASE("early guard: append preserves original bytes before an isolated client protected call") {
  const std::string original = "-- generated initializer without a final newline\nFIXTURE = true";
  const auto text = nl::guard::append_client_guard(original, kGuardBytes, kProof);
  CHECK(text.starts_with(original));
  CHECK(text.substr(0, original.size()) == original);
  const auto condition = text.find("if CLIENT and not SERVER and not MENU_DLL then", original.size());
  const auto proof = text.find("file.Exists(\"" + std::string(kProof) + "\", \"BASE_PATH\")", original.size());
  const auto local = text.find("if nativeLoaderChecked and nativeLoaderLocalView == true then", original.size());
  const auto flag = text.find("_G.__NATIVELOADER_RTX_GUARD_EARLY = true", original.size());
  const auto function = text.find("local function nativeLoaderInstallRenderGuard()", original.size());
  const auto body = text.find(kGuardBytes, original.size());
  const auto call = text.find("pcall(nativeLoaderInstallRenderGuard)", original.size());
  REQUIRE(condition != std::string::npos);
  REQUIRE(proof != std::string::npos);
  REQUIRE(local != std::string::npos);
  REQUIRE(flag != std::string::npos);
  REQUIRE(function != std::string::npos);
  REQUIRE(body != std::string::npos);
  REQUIRE(call != std::string::npos);
  // The early flag and the guard exist only past the local-view check: a served copy installs nothing.
  CHECK(condition < proof);
  CHECK(proof < local);
  CHECK(local < flag);
  CHECK(flag < function);
  CHECK(function < body);
  CHECK(body + kGuardBytes.size() < call);
  CHECK(text.find("_G.__NATIVELOADER_RTX_GUARD_EARLY", flag + 1) == std::string::npos);
  CHECK(text.find(kGuardBytes, body + 1) == std::string::npos);
  CHECK(text.find("pcall(function() return file.Exists(", condition) != std::string::npos);
  CHECK(text.find("if not ok then", call) != std::string::npos);
  CHECK(text.find("tostring(reason)", call) != std::string::npos);
  CHECK(text.ends_with("end\n"));
}

TEST_CASE("early guard: append rejects missing support marker, NUL and a proof path that is not plain") {
  CHECK_THROWS_AS(nl::guard::append_client_guard(kStockBytes, "UNSUPPORTED_GUARD = true\n", kProof), std::runtime_error);
  std::string stock(kStockBytes);
  stock.push_back('\0');
  CHECK_THROWS_AS(nl::guard::append_client_guard(stock, kGuardBytes, kProof), std::runtime_error);
  std::string guard(kGuardBytes);
  guard.push_back('\0');
  CHECK_THROWS_AS(nl::guard::append_client_guard(kStockBytes, guard, kProof), std::runtime_error);
  for (const std::string_view proof : {"", "/absolute/render-guard.lua", "native-loader/../escape.lua",
                                       "native-loader/quote\".lua", "native-loader\\backslash.lua", "line\nbreak.lua"}) {
    CHECK_THROWS_AS(nl::guard::append_client_guard(kStockBytes, kGuardBytes, proof), std::runtime_error);
  }
}

TEST_CASE("early guard: generated verified initializer redirects without changing stock or guard") {
  Fixture f("early_guard_positive");
  const auto redirect = f.prepare();
  REQUIRE(redirect.has_value());
  CHECK(redirect->source == fs::absolute(f.stock_path()));
  CHECK(redirect->replacement.parent_path() == fs::absolute(f.cache_path()));
  CHECK(redirect->kept.empty());
  const auto name = redirect->replacement.filename().string();
  REQUIRE(name.size() == std::string("render-guard-.lua").size() + 64);
  CHECK(name.starts_with("render-guard-"));
  CHECK(name.ends_with(".lua"));
  // The view names its own cache file as the proof that it is this machine's view.
  const auto text = read(redirect->replacement);
  CHECK(text == nl::guard::append_client_guard(f.stock, f.guard, "native-loader/presentation/" + name));
  CHECK(read(f.stock_path()) == kStockBytes);
  CHECK(read(f.guard_path()) == kGuardBytes);
  CHECK(read(nl::fs::join(f.root, nl::client::kModule)) == kModuleBytes);
  CHECK(!fs::exists(f.root / nl::guard::kKeptFolder));
}

TEST_CASE("early guard: a changed guard or stock initializer gets its own cache file") {
  Fixture f("early_guard_inputs_named");
  const auto first = f.prepare();
  REQUIRE(first.has_value());
  const auto first_bytes = read(first->replacement);
  f.replace_verified_guard("-- NATIVELOADER_RENDER_GUARD_V2\nlocal updated_fixture_guard = true\n");
  const auto second = f.prepare();
  REQUIRE(second.has_value());
  CHECK(second->replacement != first->replacement);
  CHECK(read(first->replacement) == first_bytes);
  f.stock += "-- a different supported initializer fixture\n";
  write(f.stock_path(), f.stock);
  const auto third = f.prepare();
  REQUIRE(third.has_value());
  CHECK(third->replacement != second->replacement);
  CHECK(nl::fs::list(f.cache_path()).size() == 3);
  CHECK(second->kept.empty());
  CHECK(third->kept.empty());
}

TEST_CASE("early guard: repeated preparation reuses one unchanged cache entry") {
  Fixture f("early_guard_idempotent");
  const auto first = f.prepare();
  REQUIRE(first.has_value());
  // Nested worktrees can push the generated cache name past MAX_PATH. Use the same extended
  // path form as the production filesystem helpers, including for the timestamp setter.
  const fs::path extended(nl::fs::long_path(first->replacement));
  const auto prior = fs::last_write_time(extended) - std::chrono::seconds(10);
  fs::last_write_time(extended, prior);
  const auto marked_time = fs::last_write_time(extended);
  const auto bytes = read(first->replacement);
  const auto second = f.prepare();
  REQUIRE(second.has_value());
  CHECK(second->replacement == first->replacement);
  CHECK(read(second->replacement) == bytes);
  CHECK(fs::last_write_time(extended) == marked_time);
  CHECK(nl::fs::list(f.cache_path()).size() == 1);
}

TEST_CASE("early guard: only the verified selected guard is appended") {
  Fixture f("early_guard_verified_only");
  f.add("garrysmod/addons/nativeloader/lua/autorun/client/other.lua", "OTHER_VERIFIED_SCRIPT=true\n");
  nl::journal::File foreign;
  foreign.path = "garrysmod/addons/community/lua/autorun/_nativeloader_guard.lua";
  foreign.package = "community-package";
  foreign.sha256 = std::string(64, 'b');
  foreign.size = 99;
  f.generation.files.push_back(foreign); // absent foreign source must not be read
  write(f.root / "garrysmod/addons/community/lua/autorun/loose.lua", "COMMUNITY_LOOSE_SOURCE=true\n");
  const auto redirect = f.prepare();
  REQUIRE(redirect.has_value());
  const auto bytes = read(redirect->replacement);
  CHECK(bytes.find(kGuardBytes) != std::string::npos);
  CHECK(bytes.find("OTHER_VERIFIED_SCRIPT") == std::string::npos);
  CHECK(bytes.find("COMMUNITY_LOOSE_SOURCE") == std::string::npos);
}

TEST_CASE("early guard: disabled and default policy perform no reads or cache writes") {
  using Switch = bool nl::config::Config::*;
  int index = 0;
  for (const Switch disabled : {&nl::config::Config::from_file, &nl::config::Config::enabled,
                                &nl::config::Config::remix_enabled}) {
    Fixture f("early_guard_disabled_" + std::to_string(index++));
    f.config.*disabled = false;
    fs::remove(f.stock_path());
    fs::remove(f.guard_path());
    fs::remove(nl::fs::join(f.root, nl::client::kModule));
    CHECK(!f.prepare().has_value());
    CHECK(!fs::exists(f.cache_path()));
  }
}

TEST_CASE("early guard: missing allowlist or wrong runtime owner writes no cache") {
  Fixture f("early_guard_owner");
  f.config.local.clear();
  CHECK_THROWS_AS(f.prepare(), std::runtime_error);
  CHECK(!fs::exists(f.cache_path()));
  f.config.local = {"native-package.gma"};
  f.generation.packages.front().id = "other-native-package";
  CHECK_THROWS_AS(f.prepare(), std::runtime_error);
  CHECK(!fs::exists(f.cache_path()));
}

TEST_CASE("early guard: foreign or missing guard ownership cannot authorize early source") {
  Fixture f("early_guard_source_owner");
  f.generation.files.back().package = "community-package";
  CHECK_THROWS_AS(f.prepare(), std::runtime_error);
  CHECK(!fs::exists(f.cache_path()));
  f.generation.files.pop_back();
  CHECK_THROWS_AS(f.prepare(), std::runtime_error);
  CHECK(!fs::exists(f.cache_path()));
}

TEST_CASE("early guard: changed guard bytes or committed size are rejected before cache creation") {
  Fixture f("early_guard_source_hash");
  std::string changed(kGuardBytes);
  changed.back() = ' ';
  write(f.guard_path(), changed);
  CHECK_THROWS_AS(f.prepare(), std::runtime_error);
  CHECK(!fs::exists(f.cache_path()));
  CHECK(read(f.guard_path()) == changed);
  write(f.guard_path(), kGuardBytes);
  f.generation.files.back().size += 1;
  CHECK_THROWS_AS(f.prepare(), std::runtime_error);
  CHECK(!fs::exists(f.cache_path()));
}

TEST_CASE("early guard: changed or foreign module cannot authorize a verified guard") {
  Fixture f("early_guard_module_hash");
  std::string changed(kModuleBytes);
  changed.front() = 'G';
  const auto module = nl::fs::join(f.root, nl::client::kModule);
  write(module, changed);
  CHECK_THROWS_AS(f.prepare(), std::runtime_error);
  CHECK(!fs::exists(f.cache_path()));
  CHECK(read(module) == changed);
  write(module, kModuleBytes);
  f.generation.files.front().package = "another-native-owner";
  CHECK_THROWS_AS(f.prepare(), std::runtime_error);
  CHECK(!fs::exists(f.cache_path()));
}

TEST_CASE("early guard: production stock pin and changed initializer are refused without a cache") {
  Fixture f("early_guard_stock_hash");
  CHECK(nl::sha256::of(f.stock) != nl::guard::kStockInitSha256);
  CHECK_THROWS_AS(nl::guard::prepare(f.root, f.config, f.generation, nl::client::kPackage), std::runtime_error);
  CHECK(!fs::exists(f.cache_path()));
  write(f.stock_path(), "-- Unsupported changed initializer\n");
  CHECK_THROWS_AS(f.prepare(), std::runtime_error);
  CHECK(!fs::exists(f.cache_path()));
  CHECK(read(f.stock_path()) == "-- Unsupported changed initializer\n");
}

TEST_CASE("early guard: a foreign selected runtime performs no reads or writes") {
  Fixture f("early_guard_foreign_runtime");
  fs::remove(f.stock_path());
  fs::remove(f.guard_path());
  CHECK(!nl::guard::prepare(f.root, f.config, f.generation, "another-runtime").has_value());
  CHECK(!fs::exists(f.cache_path()));
}

TEST_CASE("early guard: verified guard without marker or with NUL is still refused") {
  Fixture f("early_guard_marker");
  f.replace_verified_guard("local unsupported_guard = true\n");
  CHECK_THROWS_AS(f.prepare(), std::runtime_error);
  CHECK(!fs::exists(f.cache_path()));
  std::string nul(kGuardBytes);
  nul.push_back('\0');
  f.replace_verified_guard(nul);
  CHECK_THROWS_AS(f.prepare(), std::runtime_error);
  CHECK(!fs::exists(f.cache_path()));
}

TEST_CASE("early guard: NUL or oversized initializer never produces a cache entry") {
  Fixture f("early_guard_stock_text");
  f.stock.push_back('\0');
  write(f.stock_path(), f.stock);
  CHECK_THROWS_AS(f.prepare(), std::runtime_error);
  CHECK(!fs::exists(f.cache_path()));
  f.stock.assign((std::size_t{128} << 10) + 1, 'x');
  write(f.stock_path(), f.stock);
  CHECK_THROWS_AS(f.prepare(), std::runtime_error);
  CHECK(!fs::exists(f.cache_path()));
}

TEST_CASE("early guard: a changed cache file is kept aside and the view regenerated") {
  Fixture f("early_guard_cache_tamper");
  const auto redirect = f.prepare();
  REQUIRE(redirect.has_value());
  const auto expected = read(redirect->replacement);
  for (int round = 1; round <= 2; ++round) {
    auto changed = expected;
    changed.front() = round == 1 ? ' ' : '#';
    write(redirect->replacement, changed);
    const auto again = f.prepare();
    REQUIRE(again.has_value());
    const std::string kept = std::string(nl::guard::kKeptFolder) + "/" +
        redirect->replacement.filename().string() + "." + std::to_string(round);
    CHECK(again->kept == kept);
    CHECK(again->replacement == redirect->replacement);
    CHECK(read(nl::fs::join(f.root, kept)) == changed);
    CHECK(read(again->replacement) == expected);
  }
  CHECK(nl::fs::list(f.root / nl::guard::kKeptFolder).size() == 2);
  CHECK(nl::fs::list(f.cache_path()).size() == 1);
  CHECK(read(f.stock_path()) == kStockBytes);
}

TEST_CASE("early guard: a folder in the cache file's place is kept aside with its contents") {
  Fixture f("eg_folder");
  const auto redirect = f.prepare();
  REQUIRE(redirect.has_value());
  const auto expected = read(redirect->replacement);
  fs::remove(redirect->replacement);
  write(redirect->replacement / "inside.txt", "unrelated folder bytes");
  const auto again = f.prepare();
  REQUIRE(again.has_value());
  REQUIRE(!again->kept.empty());
  CHECK(read(nl::fs::join(f.root, again->kept) / "inside.txt") == "unrelated folder bytes");
  CHECK(read(again->replacement) == expected);
}

TEST_CASE("early guard: a kept-copy junction is refused and the changed cache stays in place") {
  Fixture f("eg_kept_link");
  const auto redirect = f.prepare();
  REQUIRE(redirect.has_value());
  const auto target = f.folder / "kept-target";
  fs::create_directories(target);
  fs::create_directories(f.root / "native-loader/backup");
  if (!junction(f.root / nl::guard::kKeptFolder, target)) {
    std::printf("  (skipped: cannot create kept-copy junction fixture)\n");
    return;
  }
  write(redirect->replacement, "-- changed cache bytes\n");
  CHECK_THROWS_AS(f.prepare(), std::runtime_error);
  CHECK(read(redirect->replacement) == "-- changed cache bytes\n");
  CHECK(nl::fs::list(target).empty());
  fs::remove(f.root / nl::guard::kKeptFolder);
}

TEST_CASE("early guard: a file occupying the cache directory is preserved") {
  Fixture f("early_guard_cache_collision");
  write(f.cache_path(), "existing unrelated cache-path bytes");
  CHECK_THROWS_AS(f.prepare(), std::runtime_error);
  CHECK(read(f.cache_path()) == "existing unrelated cache-path bytes");
  CHECK(read(f.stock_path()) == kStockBytes);
}

TEST_CASE("early guard: stock initializer junction is refused without reading its target") {
  Fixture f("early_guard_stock_junction");
  const auto source = f.stock_path().parent_path();
  const auto target = f.folder / "stock-target";
  fs::rename(source, target);
  if (!junction(source, target)) {
    std::printf("  (skipped: cannot create initializer junction fixture)\n");
    return;
  }
  CHECK_THROWS_AS(f.prepare(), std::runtime_error);
  CHECK(!fs::exists(f.cache_path()));
  CHECK(read(target / "init.lua") == kStockBytes);
  fs::remove(source); // remove the junction only, never its target
}

TEST_CASE("early guard: verified guard junction is refused before cache creation") {
  Fixture f("early_guard_source_junction");
  const auto source = f.root / "garrysmod/addons/nativeloader/lua";
  const auto target = f.folder / "guard-target";
  fs::rename(source, target);
  if (!junction(source, target)) {
    std::printf("  (skipped: cannot create guard source junction fixture)\n");
    return;
  }
  CHECK_THROWS_AS(f.prepare(), std::runtime_error);
  CHECK(!fs::exists(f.cache_path()));
  CHECK(read(target / "autorun/_nativeloader_guard.lua") == kGuardBytes);
  fs::remove(source);
}

TEST_CASE("early guard: cache junction never receives redirected output") {
  Fixture f("early_guard_cache_junction");
  const auto target = f.folder / "cache-target";
  fs::create_directories(target);
  write(target / "keep.txt", "unrelated target bytes");
  if (!junction(f.cache_path(), target)) {
    std::printf("  (skipped: cannot create cache junction fixture)\n");
    return;
  }
  CHECK_THROWS_AS(f.prepare(), std::runtime_error);
  CHECK(read(target / "keep.txt") == "unrelated target bytes");
  CHECK(nl::fs::list(target).size() == 1);
  fs::remove(f.cache_path());
}
