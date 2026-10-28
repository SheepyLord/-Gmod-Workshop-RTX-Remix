#pragma once
// Module hooks. RTX sessions (M5, ADR 0010): a DLL-load watcher that applies patch sets to engine
// DLLs as they are mapped (before their code runs), and import hooks on LoadLibrary* that load a
// package's replacement for an overridden module in bin\win64 (stdshader_dx6.dll). Sessions without a
// runtime (ADR 0013): import hooks on filesystem_stdio.dll's FindFirstFile*/FindNextFile* that leave
// the add-on folders of requires_remix packages out of its searches of garrysmod\addons, so GMod
// does not mount them. Installed for the rest of the process; uninstall() is for rollback before commit.

#include "nl/manifest.h"

#include <filesystem>
#include <string>
#include <utility>
#include <vector>

namespace nl::proxy::modules {

struct Setup {
  std::filesystem::path root;                     // the game root (absolute)
  std::vector<manifest::PatchSet> patch_sets;     // empty if not allowed this session
  std::vector<std::pair<std::string, std::filesystem::path>> overrides;  // module -> absolute replacement
  std::vector<std::string> hidden_addons;         // folder names under garrysmod\addons to leave out (no runtime)
  std::string session_json_base;                  // fields written ahead of the results in session.json
};

// Registers the watcher and hooks the modules already loaded. False (with `error`) if it cannot;
// nothing stays changed then. Once per process: the hooks' state is never freed, so a hook running
// on another thread, or one an import slot still points at, always reaches the original function.
bool install(Setup setup, std::string& error);
// Undoes install() (unregisters the watcher, makes every hook a pass-through, restores hooked
// imports). Only before commit. Safe to call when install() failed or never ran.
void uninstall() noexcept;
// The results so far, as the JSON written to garrysmod/data/native-loader/session.json.
std::string results_json();
// Writes session.json now (best effort; also done after each module the watcher changes).
void write_session_json() noexcept;

// Points `module`'s imports of `function` (from KERNEL32, KERNELBASE or an api-ms-win-core-libraryloader
// or -file set) at `replacement`. Returns how many entries changed. Exposed for tests.
int hook_imports(void* module, const char* function, void* replacement);

}  // namespace nl::proxy::modules
