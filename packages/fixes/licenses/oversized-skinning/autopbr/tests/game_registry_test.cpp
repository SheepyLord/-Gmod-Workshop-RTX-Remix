// GPL-2.0. Production persistent game-map registry and publication-selection regressions.
#include <cassert>
#include <iostream>
#include <stdexcept>
#include <unordered_map>
#include "../source/material_pipeline/to_pbr/game_registry.h"
#include "../source/material_pipeline/to_pbr/fallback_guard.h"
using namespace MaterialPipeline::ToPBR;
namespace fs = std::filesystem;
static void DDS(const fs::path& path, char pixel = 17) {
    uint32_t h[32]{};
    h[0] = 0x20534444; h[1] = 124; h[3] = h[4] = 1; h[7] = 1;
    h[19] = 32; h[20] = 0x41; h[22] = 32;
    h[23] = 0x00ff0000; h[24] = 0x0000ff00; h[25] = 0xff; h[26] = 0xff000000;
    std::ofstream file(path, std::ios::binary); file.write(reinterpret_cast<char*>(h), sizeof(h));
    for (int i = 0; i < 4; ++i) file.put(pixel);
}
static std::string Bytes(const fs::path& path) {
    std::ifstream file(path, std::ios::binary);
    return std::string(std::istreambuf_iterator<char>(file), {});
}
static void SessionCases(const fs::path& output) {
    fs::create_directories(output);
    const auto texture = output / "session.dds";
    DDS(texture);
    GameRegistry::Registry registry(output);
    assert(registry.Load());
    GameRegistry::Session session;
    const std::string identity = "mmd/t/0123456789abcdef", other = "mmd/t/1123456789abcdef";
    int resolutions = 0, conversions = 0, saves = 0;
    auto resolve = [&](const std::string& key, bool maps) {
        ++resolutions;
        auto result = registry.Resolve(key, {0x123}, true, true, [&]() -> std::optional<GameRegistry::Record> {
            ++conversions;
            if (!maps) return {};
            GameRegistry::Record record;
            record.identity = key; record.hashes = {0x123}; record.generator = 5;
            assert(registry.Capture(record, {texture.u8string(), {}, {}, {}}));
            return record;
        });
        ++saves; assert(registry.Save());
        return result;
    };
    auto unexpected = []() -> std::optional<GameRegistry::Record> { assert(false); return {}; };
    assert(!session.ResolveOnce(identity, {0x123}, false, unexpected));
    assert(!session.ResolveOnce(identity, {}, true, unexpected));
    assert(!session.ResolveOnce(identity, {0}, true, unexpected));
    assert(!session.ResolveOnce("not an identity", {0x123}, true, unexpected));
    auto first = session.ResolveOnce(identity, {0x123}, true, [&]() { return resolve(identity, true); });
    assert(first && resolutions == 1 && conversions == 1 && saves == 1);
    // Material/source aliases use the same live identity. Remove both disk inputs:
    // a hit still succeeds without converting, inspecting/hashing DDS or registry I/O.
    fs::rename(texture, output / "hidden.dds");
    fs::rename(registry.Path(), registry.Path().wstring() + L".hidden");
    auto shared = session.ResolveOnce(identity, {0x456, 0x789}, true, unexpected);
    assert(shared && shared->hashes == (std::vector<uint64_t>{0x456, 0x789}));
    assert(shared->textures[0].digest == first->textures[0].digest);
    assert(resolutions == 1 && conversions == 1 && saves == 1);
    fs::rename(output / "hidden.dds", texture);
    fs::rename(registry.Path().wstring() + L".hidden", registry.Path());
    assert(session.ResolveOnce(other, {0x999}, true, [&]() { return resolve(other, true); }));
    assert(resolutions == 2 && conversions == 2 && saves == 2);
    const std::string noMaps = "mmd/t/2123456789abcdef";
    assert(!session.ResolveOnce(noMaps, {0x123}, true, [&]() { return resolve(noMaps, false); }));
    assert(!session.ResolveOnce(noMaps, {0x456}, true, unexpected));
    assert(resolutions == 3 && conversions == 3 && saves == 3);
    // Source rejection also remains no-maps after an exception.
    const std::string rejected = "mmd/t/3123456789abcdef";
    bool threw = false;
    try { session.ResolveOnce(rejected, {0x123}, true, []() -> std::optional<GameRegistry::Record> { throw std::runtime_error("rejected"); }); }
    catch (const std::runtime_error&) { threw = true; }
    assert(threw && !session.ResolveOnce(rejected, {0x456}, true, unexpected));
    // ClearCache stops the production worker. A new worker-local Session resolves
    // both a previously successful identity and a no-maps identity afresh.
    GameRegistry::Session restarted;
    assert(restarted.ResolveOnce(identity, {0xaaa}, true, [&]() { return resolve(identity, true); }));
    assert(!restarted.ResolveOnce(noMaps, {0xbbb}, true, [&]() { return resolve(noMaps, false); }));
    assert(resolutions == 5 && conversions == 5 && saves == 5);
}
int main(int argc, char** argv) {
    assert(argc == 2);
    const fs::path output = fs::u8path(argv[1]) / "textures";
    SessionCases(output.parent_path() / "session" / "textures");
    fs::create_directories(output);
    const std::string identity = "mmd/t/0123456789abcdef";
    assert(GameRegistry::Identity("MMD\\T\\0123456789ABCDEF") == identity);
    assert(GameRegistry::Identity("mmd/0123456789abcdef/material_0").empty());
    assert(GameRegistry::Identity("mmd/t/0123456789abcdef_extra").empty());
    assert(GameRegistry::Identity("mmd/t/0123456789abcdeg").empty());
    assert(!GameRegistry::SafeFile("../normal.dds"));
    assert(!GameRegistry::SafeFile("C:normal.dds"));
    assert(!GameRegistry::SafeFile("normal.dds:stream.dds"));
    std::array<std::string, 4> paths;
    for (size_t i = 0; i < paths.size(); ++i) {
        const auto path = output / ("game_test_" + std::to_string(i) + ".dds");
        DDS(path); paths[i] = path.u8string();
    }
    GameRegistry::Registry registry(output);
    assert(registry.Load() && registry.Size() == 0);
    int conversions = 0;
    auto convert = [&]() -> std::optional<GameRegistry::Record> {
        ++conversions;
        GameRegistry::Record record;
        record.identity = identity; record.hashes = {0x123}; record.generator = 5;
        record.roughness = .123456789f; record.metallic = .875f; record.emission = 1.5f;
        assert(registry.Capture(record, paths));
        return record;
    };
    auto absent = []() -> std::optional<GameRegistry::Record> { assert(false); return {}; };
    // Nothing is guessed for an unknown texture, even if the old live hash happens to match.
    assert(!registry.Resolve(identity, {0x123}, true, false, absent));
    assert(!registry.Resolve(identity, {0x123}, false, true, convert) && conversions == 0);
    auto made = registry.Resolve(identity, {0x123, 0x456}, true, true, convert);
    assert(made && conversions == 1 && made->hashes.size() == 2);
    assert(registry.Save());
    const auto original = Bytes(registry.Path());
    // A crash's leftover staging file is never used as the registry.
    { std::ofstream partial(registry.Path().wstring() + L".tmp"); partial << "partial new data"; }
    GameRegistry::Registry second(output);
    assert(second.Load() && second.Size() == 1);
    assert(!second.Resolve("mmd/t/1123456789abcdef", {0x123}, true, false, absent));
    assert(!second.Resolve(identity, {0}, true, false, absent));
    assert(!second.Resolve(identity, {}, true, false, absent));
    assert(!second.Resolve(identity, {0x999}, false, false, absent));
    auto restored = second.Resolve(identity, {0x999}, true, false, absent);
    assert(restored && restored->hashes == std::vector<uint64_t>{0x999});
    assert(restored->textures[3].file == "game_test_3.dds");
    assert(restored->roughness == made->roughness && restored->metallic == made->metallic && restored->emission == made->emission);
    assert(restored->generator == 5); // No comparison with today's generator/recipe version.
    assert(second.Save() && Bytes(second.Path()) == original);
    // A failed atomic replacement preserves the complete prior registry.
    const fs::path staged(second.Path().wstring() + L".tmp");
    fs::remove(staged);
    fs::create_directory(staged);
    assert(second.Resolve(identity, {0x999}, true, true, [&]() { auto r = made; r->generator = 6; return r; }));
    assert(!second.Save() && Bytes(second.Path()) == original);
    fs::remove(staged);
    // A sharing violation at replacement removes the fully written staging file.
    HANDLE locked = CreateFileW(second.Path().c_str(), GENERIC_READ, FILE_SHARE_READ, nullptr,
                                OPEN_EXISTING, FILE_ATTRIBUTE_NORMAL, nullptr);
    assert(locked != INVALID_HANDLE_VALUE);
    assert(!second.Save() && !fs::exists(staged) && Bytes(second.Path()) == original);
    assert(CloseHandle(locked));
    auto update = [&]() {
        auto record = convert(); record->generator = 999; record->roughness = .25f; return record;
    };
    auto updated = second.Resolve(identity, {0x777}, true, true, update);
    assert(updated && updated->generator == 999 && updated->roughness == .25f && conversions == 2);
    const std::string edit = original + "user edited registry\n";
    { std::ofstream file(second.Path(), std::ios::binary); file << edit; }
    assert(second.Save());
    bool retained = false;
    for (const auto& file : fs::directory_iterator(output.parent_path()))
        if (file.path().extension() == ".bak" && Bytes(file.path()) == edit) retained = true;
    assert(retained);
    // Present sources never fall back when today's conversion fails or yields no safe surface.
    bool threw = false;
    try { second.Resolve(identity, {0x777}, true, true, []() -> std::optional<GameRegistry::Record> { throw std::runtime_error("bad PMX"); }); }
    catch (const std::runtime_error&) { threw = true; }
    assert(threw);
    assert(!second.Resolve(identity, {0x777}, true, true, []() -> std::optional<GameRegistry::Record> { return {}; }));
    assert(second.Size() == 0);
    assert(second.Resolve(identity, {0x777}, true, true, convert) && second.Save());
    // Reopening models cache-clear/restart retention; registrations are never loaded by old hash.
    GameRegistry::Registry cleared(output);
    assert(cleared.Load() && cleared.Resolve(identity, {0x888}, true, false, absent));
    // Same-length pixel corruption has a valid DDS header, but must not restore.
    DDS(fs::u8path(paths[2]), 18);
    assert(Policy::ValidDDS(fs::u8path(paths[2])));
    assert(!cleared.Resolve(identity, {0x888}, true, false, absent) && cleared.Size() == 0);
    assert(cleared.Save());
    DDS(fs::u8path(paths[2]));
    assert(cleared.Resolve(identity, {0x888}, true, true, convert) && cleared.Save());
    // Missing and truncated files prune the record at load, and persist the pruning.
    fs::remove(fs::u8path(paths[1]));
    GameRegistry::Registry missing(output); assert(missing.Load() && missing.Size() == 0 && missing.Save());
    DDS(fs::u8path(paths[1]));
    assert(missing.Resolve(identity, {0x888}, true, true, convert) && missing.Save());
    { std::ofstream bad(fs::u8path(paths[3]), std::ios::binary); bad << "DDS truncated"; }
    GameRegistry::Registry invalid(output); assert(invalid.Load() && invalid.Size() == 0);
    DDS(fs::u8path(paths[3]));
    // Reject retired record versions, traversal, malformed rows, unknown schema and oversized input.
    { auto text = original; text.replace(text.find(identity) + identity.size(), 2, " 0");
      std::ofstream file(registry.Path(), std::ios::binary); file << text; }
    assert(invalid.Load() && invalid.Size() == 0);
    { auto text = original; text.replace(text.find("game_test_0.dds"), 15, "../normal.dds");
      std::ofstream file(registry.Path(), std::ios::binary); file << text; }
    assert(invalid.Load() && invalid.Size() == 0);
    { std::ofstream file(registry.Path(), std::ios::binary); file << "TOPBR_GAME_REGISTRY 1\nmmd/t/0123456789abcdef 1 5 1000000000\n"; }
    assert(invalid.Load() && invalid.Size() == 0);
    // Damage must not disable future recording/restoration. Each first save backs
    // up the exact damaged bytes, including a crash's empty or torn header.
    const std::array<std::pair<std::string, std::string>, 7> damagedFiles{{
        {"empty", ""}, {"garbage", "torn header\n"},
        {"duplicate", original + original.substr(original.find('\n') + 1)},
        {"too-many-rows", original + std::string(GameRegistry::MaxRecords, '\n')},
        {"bad-version", "TOPBR_GAME_REGISTRY 99oops\n"},
        {"signed-version", "TOPBR_GAME_REGISTRY +99\n"},
        {"same-version-zeroes", "TOPBR_GAME_REGISTRY 0001\n"}
    }};
    for (const auto& fixture : damagedFiles) {
        const auto textures = output.parent_path() / fixture.first / "textures";
        fs::create_directories(textures);
        for (const auto& path : paths) fs::copy_file(fs::u8path(path), textures / fs::u8path(path).filename());
        GameRegistry::Registry damaged(textures);
        { std::ofstream file(damaged.Path(), std::ios::binary); file << fixture.second; }
        assert(damaged.Load() && damaged.WasDamaged() && damaged.Size() == 0);
        assert(Bytes(damaged.Path()) == fixture.second);
        assert(!damaged.Resolve(identity, {0x999}, true, false, absent));
        assert(damaged.Save() && Bytes(damaged.Path()) == "TOPBR_GAME_REGISTRY 1\n");
        bool backedUp = false;
        for (const auto& file : fs::directory_iterator(textures.parent_path()))
            if (file.path().filename().u8string().find("game_materials.registry.before-r11b-") == 0 &&
                file.path().extension() == ".bak" && Bytes(file.path()) == fixture.second) backedUp = true;
        assert(backedUp);
        GameRegistry::Registry recovered(textures);
        assert(recovered.Load() && !recovered.WasDamaged() && recovered.Size() == 0);
        assert(recovered.Resolve(identity, {0x777}, true, true, [&]() { return made; }) && recovered.Save());
        GameRegistry::Registry restarted(textures);
        assert(restarted.Load() && restarted.Size() == 1 && !restarted.WasDamaged());
        assert(restarted.Resolve(identity, {0x888}, true, false, absent));
    }
    // Only another well-formed decimal schema version or oversized files stay read-only.
    for (const auto& version : {"99", "00099", "0", "999999999999999999999999999999"}) {
        { std::ofstream file(registry.Path(), std::ios::binary); file << "TOPBR_GAME_REGISTRY " << version << "\nfuture data\n"; }
        const auto future = Bytes(registry.Path());
        assert(!invalid.Load() && !invalid.WasDamaged() && invalid.Size() == 0);
        assert(!invalid.Save() && Bytes(registry.Path()) == future);
    }
    { std::ofstream file(registry.Path(), std::ios::binary); file.seekp(GameRegistry::MaxBytes); file.put('x'); }
    const auto oversized = Bytes(registry.Path());
    assert(!invalid.Load() && !invalid.WasDamaged() && invalid.Size() == 0 && !invalid.Save());
    assert(Bytes(registry.Path()) == oversized);
    // Use exactly the production publication selector for off/authored/incomplete cases.
    struct Material { bool importedGame; };
    std::unordered_map<uint64_t, Material> materials{{0x123, {true}}, {0x456, {false}}};
    FallbackGuard::Result guard;
    assert(FallbackGuard::Select(materials, false, true, guard).size() == 1);
    assert(FallbackGuard::Select(materials, false, false, guard).empty());
    guard.hashes.insert(0x123);
    assert(FallbackGuard::Select(materials, false, true, guard).empty());
    assert(FallbackGuard::Select(materials, true, false, guard).count(0x456) == 1);
    guard.complete = false;
    assert(FallbackGuard::Select(materials, true, true, guard).empty());
    std::cout << "PASS game registry: once-per-worker identity resolution (including no-maps/restart), durable atomic roundtrip/failure, damaged-file backup/recovery, read-only versions/size, live identity/hash, source refresh, generator retention, DDS integrity/pruning, bounds, switches and authored exclusion\n";
}
