# 0058: The gmpublish preflight fallback, recorded

- Status: Accepted. Records a mechanism added inside [0039](0039-native-package-addon-presentation.md)
  (its publication paragraph) as a decision of its own; changes nothing in the code.
- Date: 2026-10-31. Decided by Claude in review R4, under the user's instruction to decide
  autonomously; the R4 tools review asked for the decision to be explicit.

## Context

`tools/publish_workshop.py` uploads with GMod's `gmpublish.exe`. On this machine Steam's registered
active process id is stale, so `SteamAPI_IsSteamRunning` returns false and `gmpublish` stops with
"Couldn't initialize Steam!" before it tries, although Steam runs and the real
`SteamAPI_Init` succeeds. Since 2026-10-30 every upload of item 3829070317 (13 by the review) went
through the fallback Codex added: when, and only when, the normal run fails with exactly that error,
the publisher copies the pinned `gmpublish.exe` build into a temporary folder, changes the one byte
of the `jnz` after the `SteamAPI_IsSteamRunning` call so the program goes on to the real
`SteamInternal_SteamAPI_Init` (which keeps its own failure exit), and runs that copy. The reviewer
confirmed the pinned hashes, the offset and that authentication and ownership are still enforced by
Steam.

## Decision

Keep the fallback, with these limits: the installed `gmpublish.exe` is never written (AGENTS.md rule
2: the copy lives in a temporary folder that is deleted); it triggers only on that exact error, after
the dirty-input and fingerprint checks; it refuses any other `gmpublish` build (hash pin) instead of
re-patching it; and a failed cleanup no longer makes the next hook upload again (R4). Restarting
Steam clears the stale process id, and then the normal path is used again.

## Consequences

Publishing keeps working on this machine without asking the user to restart Steam. A future
`gmpublish` update makes the fallback refuse until someone reviews the new build; the publisher's
documentation tells the next agent to put that to the user rather than pin a new build on their own.
