# 0050: Editable startup text and local menu diagnostics

- Status: Accepted 2026-10-30
- Decided by: requests 15 and 23

## Context

The Remix splash referred users to the older Xenthio repository. The game menu runs in a separate
realm, so an ordinary client add-on cannot display diagnostics before a map loads. The loader
already supplies generated display copies through exact read redirects without editing Steam files.

## Decision

Ship seven editable startup_message text files under the project-owned data/nativeloader_ui
folder with create-only policy. The runtime selects the Remix language, normalizes BOM/CRLF,
limits input to 8192 bytes, rejects NUL/empty files and falls back to English then compiled project
text. Substitute the actual {hotkey}/{seconds} values and display text literally. Merge the text's
codepoints into the selected language's font atlas. Existing splash visibility/countdown rules stay.

Loader 0.8.1 appends a local diagnostic panel to a generated copy of control.Menu.js. Validate its
stock controller marker and preserve the original file. Query Windows/CPU/logical threads/RAM and
DXGI adapter names/VRAM once. Show the engine menu's current game version/branch, loader version
and installed winmm.dll SHA-256, plus committed native package versions/manifest SHA-256. Truncate
hashes visually; hover/copy retains full values. This is a native-package inventory, not an inventory
of every subscribed Workshop add-on. No account names, machine paths, IPs or startup logs are included.

The panel appears only on the home menu outside gameplay. It has seven-language labels, uses text
nodes for values, and only opens the project URL or copies diagnostics after an explicit click.
Failed probing/stock-source changes skip display without breaking startup. Trust rules are unchanged.

## Consequences

The startup text updates through Workshop. Main-menu diagnostics require the updated 0.8.1
bootstrap, delivered in the loader bundle; a Workshop runtime update cannot replace a loaded
winmm.dll. Real game installations are not modified during development. Offline C++ filesystem,
JavaScript DOM, template/catalog and native text-policy tests cover the implementation.
