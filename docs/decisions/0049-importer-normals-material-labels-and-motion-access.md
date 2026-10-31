# 0049: Imported normals and add-on navigation

- Status: Accepted 2026-10-30
- Decided by: requests 17, 19/19.1 and 20; the user said "in game validation is not needed"

## Context

Authored vertex normals can differ from mesh geometry. Remix already provides area-weighted
normal generation through its Smooth Normals category. Its Lua config getter reads a file, not
live settings, so replacing the saved set could discard user tags. Imported materials' generated
paths are useful identities but poor labels. AME also restored a stale Source row when leaving RTX.

## Decision

Offer a default-off, archived normal recalculation checkbox beside character and prop spawn
controls. Collect active world-model hashes and write only an additive NoSave runtime option.
It joins saved smooth-normal tags and invalidates cached draw translation. Imported files and
normal maps stay unchanged. Texture tags affect every draw sharing a hash, including previews
of the same asset; the tooltip states that boundary.

AME shows original material names from metadata, falling back to paths. Tooltips retain raw paths.
Stored identities, slot groups, duplicate hash ownership and the two edit stores stay unchanged.
Source follows the current RTX row; returning maps to the canonical RTX owner.

Add a translated Motion importer creation tab whose button opens the existing VMD manager.
Late API availability enables the button; creating the tab never opens another window itself.

## Consequences

Three LuaJIT behavior cases exercise production methods/modules. A dedicated native suite checks
option lifetime. Full repository checks, input verification and a reviewed package precede main's
publishing hooks. The user's explicit waiver replaces the usual in-game check for this batch.
