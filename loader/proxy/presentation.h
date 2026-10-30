#pragma once
// Display-only views for successfully deployed native Workshop packages. The game's file reader
// sees these ordinary, whitelisted archives; the loader still reads the unchanged native archive.

#include "nl/gma.h"
#include "nl/journal.h"

#include <filesystem>
#include <string>
#include <string_view>
#include <vector>

namespace nl::proxy::presentation {

struct Redirect {
  std::filesystem::path source;
  std::filesystem::path replacement;
  std::string workshop_item;  // empty for the generated menu script
};

struct Prepared {
  std::vector<Redirect> redirects;
  std::vector<std::string> notes;
};

// Pure builders, also used by the regression tests. Numeric Workshop IDs are mandatory.
std::string make_archive(const gma::Index& original, const journal::Package& package, std::string_view workshop_item);
// Throws when the expected stock menu implementation differs; no partial override is returned.
std::string decorate_menu(std::string_view original, const std::vector<std::string>& workshop_items);

// Validates each current Workshop source's package identity, creates content-addressed display
// files below native-loader/presentation, and returns exact read redirects. Missing/changed sources,
// links, and modified cache files are left alone and reported. Never changes a Steam/depot file.
Prepared prepare(const std::filesystem::path& root, const journal::Generation& generation);

}  // namespace nl::proxy::presentation
