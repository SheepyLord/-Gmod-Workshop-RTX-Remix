#pragma once
// Content-only packages (ADR 0027): what a package found without the allowlist, from any subscribed
// Workshop item, may hold. Native code (a runtime, binary modules, payload files, module
// dependencies, patch sets) stays opt-in through the allowlist (ADR 0003); such a package may only
// deploy Remix mod data under rtx-remix/mods/ and Lua add-ons under garrysmod/addons/, file by file
// of the kinds GMod's Workshop and Remix read.
#include "nl/manifest.h"

#include <string>
#include <string_view>

namespace nl::content {

// GMod's Workshop whitelist (the table in gmad.exe, as tools/gmapack/gmapack.py has it): may a
// Workshop add-on hold this file? `path` is relative to the add-on folder; case is ignored.
bool workshop_whitelisted(std::string_view path);

// Data the Remix runtime reads from a mod folder: USD layers, textures, MDL materials, text.
bool remix_mod_file(std::string_view path);

// Why this package may not be deployed as content only; empty if it may.
std::string problem(const manifest::Manifest& m);

}  // namespace nl::content
