# ADR 0125: Model Hotloader game-build findings are diagnostics

Status: accepted (R21-B, the user's decision). Date: 2026-11-06.

The user accepts the assumption that the Model Hotloader's separate native modules continue to
work after Garry's Mod updates, and will address actual breakage update by update. The packaged
release's profiles predate build 26439081; maintaining a tested-build list is no longer a reason
to interrupt players. This applies to this build and every later one without an allowlist of builds.

The package's local `overrides/installation.lua`, shipped through `--addon-file`, stops adding
`game_unverified`, `game_incompatible`, `game_check_failed` and `game_unchecked` installation issues.
Native findings remain in `status.compatibility` for Copy diagnostics. The installation window
omits them: this keeps them out of the warning banner, notice, Dismiss key and problem counts,
without changing the UI's treatment of any other warning.

One plain console line per realm's Lua session names unverified libraries and native findings, or
the unavailable/failed check. Pending libraries defer that line until they settle or exhaust the
existing retry limit. Refresh and Recheck do not repeat it. A realm is recreated on a map load, so
the new realm reports its own check once. Control characters in native messages become spaces.

Feature behavior is unchanged: `pending` still waits for its library and the existing timeout
warning remains. The natives and their interface, slot and class guards are unchanged; calls they
cannot make still fail. A broken update therefore appears as actual feature/call failures and the
console diagnostic, without a game-build warning. Outdated releases, compatibility-policy fallback,
identity mismatches and missing files retain their existing warnings.

Only this repository's package copy changes, imported through `tools/inputs.py import`; neither the
Hotloader's repository nor its native source/binaries changes. Its local-change record is
`packages/model-hotloader/source/Source.md`. R20's proposed separate task to validate the natives
against each new game build and regenerate compatibility evidence is dropped.
