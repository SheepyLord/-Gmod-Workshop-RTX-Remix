# 0044: Remix saves and explicit GMod overrides

- Status: Accepted 2026-10-30
- Decided by: the user's request: "Make the saving and loading of user's config more robust and persistent."

## Context

The Common Remix panel bound numeric sliders to archived ConVars whose empty string meant leave
the value to Remix. A numeric widget can coerce that sentinel to zero. The menu then replayed these
values four seconds after every map start, defeating settings the player had saved in Remix.
The shipped API getter reads only rtx.conf; it cannot supply a live synchronized value.

The runtime serializer truncated the destination before writing, returned no status, and did not
check write or close errors. Layer Save updated its baseline and cleared unsaved state even if the
write failed. Reload removed current values before knowing whether the file could be read.

## Decision

Remix's saved configuration is authoritative at launch. GMod startup replay requires the new
`nativeloader_remix_reapply` switch, off by default. Numeric overrides require their own explicit
selection, also off by default. Keep all older archived values for recovery; do not infer that zero
is always accidental. The widgets remain unbound and initialize under a write guard. Only deliberate,
valid edits are sent. The panel explains that its values are override drafts and tells the player
how to save them with Remix. Fog ownership follows applied session state rather than a dormant draft.

Save serializes to an exclusively created sibling file, checks every write, flushes it, checks close,
then atomically replaces the destination with Windows write-through. On failure, keep the previous
file, in-memory baseline and unsaved status. Delete only the writer's own temporary file. Reload
parses a complete file first and leaves live values alone if opening or reading fails. Export uses
the same checked writer. No changes to the loader's trust model, package paths or user.conf policy.

## Consequences

Opening the menu does not change Remix. A native Save survives a later launch even if GMod retains
an older numeric draft. Players who intentionally want GMod startup overrides opt in and can still
use zero. An old corrupted value already saved into Remix cannot be distinguished from an authored
zero; the fix does not silently rewrite it. Failed saves remain visibly unsaved and log the path and
Windows error, allowing a retry. Failed reloads do not erase current edits.

## Alternatives considered

Replacing all zeros with one would discard legitimate choices. Reading the bundled file-only getter
as if it were a live API would conceal desynchronization. Continuing unconditional startup replay
would still override Alt+X saves. Updating user.conf during deployment would violate its ownership.
