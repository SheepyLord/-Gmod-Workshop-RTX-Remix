# 0115: A published loader record and local update reminders

- Status: Accepted 2026-11-06
- Decided by: the user's R20 item 46; implementation choices by R20-A

The Workshop package updates independently of the bootstrap DLL. An unreleased CMake version must
never send players to a release that does not exist. Older loaders also reject unknown manifest keys.

Keep one hand-edited record, `companion/nativeloader/resource/loader-release.json`, with exactly
`version` and `url`. It is an ordinary, journaled companion root file in the combined runtime package,
with no manifest extension or higher minimum loader version. Leave it at 0.14.0 for R20 development.
After the GitHub release exists, its maintainer sets the record to that release, commits it, and
pushes main so the Workshop package carries the announcement. Never generate it from CMake.

Loader 0.15.0 validates at most 1 KiB of strict JSON. Versions are SemVer core plus optional
prerelease, without build metadata; precedence uses the manifest's SemVer implementation. The URL
must equal `https://github.com/SheepyLord/Gmod-Workshop-RTX-Remix/releases/tag/v` plus that version.
Only the active `gmod-rtx-remix` runtime owner's exact file counts: its source must pass the existing
native distribution/local/dev allowlist, and its size and SHA-256 must match the committed journal.
Missing, ambiguous, modified, linked or invalid input produces no reminder. A content subscription
cannot supply the record, even at the same virtual path. Failed/vanilla activation supplies no new UI.

The menu shows a localized modal on home once per process, with current/latest versions, manual DLL
replacement and restart instructions, the validated download link, Later, and a version-specific
ignore button. A fixed Lua bridge reads the stock menu's local cookies; the menu realm remembers the
process token across page reloads. A newer version asks again. No HTTP update check is added.

Before 0.15.0 the companion shows the same notice after the first map, scaled by ScrH()/1080. It
reads physical BASE_PATH files rather than mounted GAME aliases, verifies runtime ownership and
the journaled record's size/hash, and matches native discovery's package identity/source. The
small ASCII record parser also rejects duplicate/extra keys. A DATA process-token receipt prevents
repetition across map changes; its ignored-version preference is a separate DATA file. This fallback
does not run for 0.15.0 or later. Unavailable filesystem/UI APIs quietly skip the notice.

No native permission, off switch, package schema, Steam setting or Remix user.conf changes.
Offline C++, JavaScript and Lua tests cover validation, trust, precedence, choices and lifecycle.

PoC implementation choice: the tested menu File object has no Write method, so file.Write truncates
a file and errors. Menu choices therefore use stock cookie.Set/GetString in local mn.db, as GMod's
own menu does. Client-realm DATA writes work normally. The reminder adds no cloud-config writes.
