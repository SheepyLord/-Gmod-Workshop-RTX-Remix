#pragma once
// Finding the package archives and folders the config allowlists, without the Steam API (it is not
// initialised yet when the bootstrap runs): one candidate per config entry. Then the subscribed
// Workshop items that hold a package, as content-only candidates (ADR 0027): subscribed according to
// Steam's record, not merely installed (ADR 0111).

#include "nl/config.h"

#include <cstdint>
#include <filesystem>
#include <optional>
#include <set>
#include <string>
#include <string_view>
#include <vector>

namespace nl::discovery {

// In precedence order: a development folder overrides a local archive, which overrides the Workshop.
enum class Source { dev_folder, local, workshop };
const char* source_name(Source source);

struct Candidate {
  Source source = Source::workshop;
  std::string label;                // the config entry as written (Workshop id or path)
  std::filesystem::path location;   // archive file or package folder; empty if not found
  std::string problem;              // why it cannot be used; empty if it can
  // Workshop only, from appworkshop_4000.acf (Steam's record of the installed version):
  std::optional<std::uint64_t> time_updated;
  std::string workshop_manifest;
  bool disabled_by_user = false;  // addon-list opt-out, distinct from a temporarily unusable source
  // Workshop only: Steam no longer has the item. Its record (appworkshop_4000.acf) lists it neither as
  // installed nor as subscribed, and its folder is gone: what Steam leaves after the user unsubscribed
  // (it cleans up when the game is next launched from Steam). An intentional removal like
  // disabled_by_user, unlike a download in progress, which keeps the item in the record (ADR 0025).
  // A content-only candidate is also unsubscribed when the record names no account of this computer
  // as its subscriber, folder or not: the game or a server downloaded it (ADR 0111).
  bool unsubscribed = false;
  // Workshop only: found among the subscribed items, not through the allowlist, so it may hold
  // content only (ADR 0027): the planner skips it if it holds native code.
  bool content_only = false;
};

struct Environment {
  std::filesystem::path game_root;
  std::optional<std::filesystem::path> workshop_content;  // <library>\steamapps\workshop\content\4000
  std::filesystem::path appworkshop_acf;                  // <library>\steamapps\workshop\appworkshop_4000.acf
  std::set<std::string> disabled_workshop;                // ids in garrysmod\cfg\addonnomount.txt
  // Workshop ids of the packages the current generation deployed (the journal): a content-only one
  // keeps a candidate while its folder is gone, so an update in progress keeps it and an unsubscribe
  // or a disable removes it, as for an allowlisted item.
  std::set<std::string> deployed_workshop;
};

// Where Workshop items live: the library the game root sits in (<library>\steamapps\common\<dir>),
// else the library Steam's libraryfolders.vdf lists for app 4000. `steam_root` replaces the
// registry lookup (HKCU\Software\Valve\Steam\SteamPath).
Environment environment_for(const std::filesystem::path& game_root,
                            const std::optional<std::filesystem::path>& steam_root = std::nullopt);

// Only the library the game root sits in, never Steam's list of libraries. Without an allowlisted
// Workshop item, start-up reads the subscriptions this way, so a game copied outside a library
// (a test's scratch folder) scans none of them (ADR 0027).
Environment environment_in_library(const std::filesystem::path& game_root);

// Workshop ids GMod's addon list has disabled (garrysmod\cfg\addonnomount.txt); empty if none.
std::set<std::string> read_addonnomount(const std::filesystem::path& game_root);

// One candidate per allowlisted entry: dev folders, then local archives, then Workshop items, each
// in config order. Then, unless config.subscribed_content is false, the content-only candidates in
// item order: every other installed item whose .gma lists native/manifest.json and that an account on
// this computer subscribed to, and every other item in env.deployed_workshop (legacy _legacy.bin items
// are never scanned; ADR 0027). Without a readable Steam record that has WorkshopItemDetails, no
// installed item is new content; the deployed ones keep their candidates (ADR 0111).
std::vector<Candidate> discover(const config::Config& config, const Environment& env);

// Steam's `subscribedby` value (WorkshopItemDetails in appworkshop_4000.acf): the accounts on this
// computer that subscribed, as decimal account ids separated by commas. True if it names at least
// one non-zero account, false for an empty value or only zeros ("0"), nullopt for anything else: a
// value this code does not understand neither adds nor removes a package (ADR 0111).
std::optional<bool> subscribed_by_an_account(std::string_view subscribedby);

// True if the archive's index lists native/manifest.json: a native-loader package. Reads the header
// and index only; false for anything that is not a readable GMAD archive.
bool lists_native_manifest(const std::filesystem::path& archive);

}  // namespace nl::discovery
