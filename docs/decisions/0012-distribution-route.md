# 0012: Distribution route: native packages are released outside the Workshop; the Workshop stays a supported source

- Status: Accepted 2026-10-28. **Superseded in part by [0015](0015-workshop-route-for-native-packages.md)
  (2026-10-28).** The private upload test was run with the user's approval: the Workshop accepted a
  native package packed with `gmapack` and served it back intact, so native packages may go through
  the Workshop. The rest of this record stands.
- Correction (2026-10-28, at the user's direction): three places here (Context, and the first two
  alternatives) say the Workshop's rules forbid DLL and EXE files. They do not.
  - GMod's [Steam Workshop rules](https://wiki.facepunch.com/gmod/Steam_Workshop_Rules) have no rule
    about file types.
  - The wiki's `.dll`/`.exe` list (Workshop Addon Creation) is what `gmad.exe` will pack.
  - Disguising DLLs under other extensions stays rejected: it would look like malware to anyone who
    inspects the item.
  - See [0015](0015-workshop-route-for-native-packages.md).
- Decided by: Claude, implementing M6 under the user's 2026-10-28 instruction to finish M5-M7 without
  further approvals. Publishing to the Workshop stays outward-facing (AGENTS.md rule 5) and was not done.
- Answers the open question of [ADR 0002](0002-source-agnostic-payloads.md) (that record stands:
  payloads stay source-agnostic)

## Context

ADR 0002 left the distribution route open until a private-visibility Workshop upload had been
tried. The evidence that could be gathered without publishing anything ([RESEARCH.md](../RESEARCH.md)
section 14):

- GMod's own packer refuses the package format: `gmad.exe create` on a folder with
  `native/manifest.json` and `native/payload/test.dll` prints "Not allowed by whitelist" for both
  files and "File list verification failed", and writes no `.gma`; the same folder without them packs.
  The `native/` folder is the package format, so no package can be built with the official tool.
- The GMod wiki lists DLL and EXE files among the file types Workshop items must not contain.
- The loader itself does not need the Workshop: it reads `.gma` archives from local paths and
  development folders as well (M2), deploys them (M3) and keeps the last good version when a source
  goes away (ADR 0009).
- Uploading with `gmpublish` would create a Workshop item: an outward-facing action the user has not
  authorised in this conversation, and `gmpublish` has no dry run.

## Decision

1. The project's route for native packages is a **release download**: the runtime package
   (`package_runtime.py`) and the fixes package (`package_fixes.py`) are published as `.gma` files
   with their manifests' SHA-256s alongside, for example as GitHub release assets of the fork
   repositories; the user allowlists the downloaded file as a `local` source in `config.json`.
2. The **Workshop stays a supported source** (discovery, LZMA-wrapped legacy items, updates and the
   restart notice all work), for anyone allowed to host a package there. Nothing in the loader
   depends on that route.
3. **Two-phase updates** are what the loader does for every source: a package is deployed at the
   next start, never under a running game. For Workshop items `status.json` records the update time
   Steam had installed at start-up; the Lua companion compares it with `steamworks.FileInfo` (at
   start and every ten minutes) and asks for a restart when Steam has a newer one. A local source
   that changes is simply deployed at the next start.
4. A **private upload test** remains possible and is documented in
   [docs/handover/M6-report.md](../handover/M6-report.md) for the user to run; if the Workshop accepts
   and keeps such an item, a later record may make it the preferred route for the Lua half.

## Consequences

- Users download two files and add two lines to `config.json` instead of subscribing; an updater
  (`nlctl fetch` of a URL with a pinned SHA-256, the "Later" row of the roadmap) would remove that step.
- NVIDIA's redistributables in the runtime (DLSS, NRC, ...) are published by whoever publishes the
  runtime release, under those licences; checking them stays before any public package (roadmap risk).
- The fixes' Lua could still go to the Workshop on its own (Lua is whitelisted), but without its
  native half it does nothing; keeping both in one package keeps versions together.

## Alternatives considered

- **Disguising DLLs under whitelisted extensions** (`.dat`, `.txt`) so `gmad` packs them: rejected;
  it evades the Workshop's rules and would read as malware to anyone inspecting it.
- **Building the `.gma` with `gmapack` and uploading with `gmpublish`** without asking: rejected for
  now; outward-facing (rule 5), and the Workshop's rules forbid the content either way.
- **A loader-side downloader now:** larger attack surface (network, TLS, URL trust) for a step the
  user can do by hand; kept for later with pinned hashes.
