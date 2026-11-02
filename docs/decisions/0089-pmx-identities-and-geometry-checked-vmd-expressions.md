# ADR 0089: PMX identities before expression meanings

Date: 2026-11-02. Status: accepted for R10-H, the user's item 34.

## Context

The motion importer and Model Hotloader have different English naming tables.
The hotloader's `笑い` is `eyes_blink_smile`; the importer called it
`eye_blink_happy`, then fell through to wink controllers. `はぅ` was translated
as `eyes_peaceful`, which is the hotloader's `なごみ`. The original PMX identity
was available throughout in `rig.morphs[].original`.

The user's 1,225-model corpus corroborates the standard meanings but also
contains reversed names: `ウィンク` usually moves the character's left eye;
`EL_Happy_l_CLO` moves the right eye in all 345 occurrences. Names cannot measure
the side. See [the research](../RESEARCH.md#r10-h-pmx-identities-expression-meanings-and-map-readiness-2026-11-02)
and [the report](../handover/R10-H-report.md).

## Decision

1. Saved per-model manual overrides retain priority, including deliberate
   unassignment. Keep their file format and bytes until the user edits them.
   Source-only overrides also look up the old English key after a canonical
   correction; Clear Mapping removes that legacy key when explicitly requested.
   A saved multi-target mapping resolves in full or is unresolved; it must not
   silently become a different automatic mapping when a member is missing.
2. On hotloader characters, compare the motion's decoded morph name to every
   PMX `original` with exact Unicode equality. Case and half/full width are
   significant. Duplicate original names drive every matching morph, as nanoem
   visits every model morph. Do not normalize, trim, truncate the PMX name or
   substitute a native English name in this step.
3. VMD names are 15 CP932 bytes ending at NUL. Decode them before matching;
   retain unlisted/custom morph tracks and merge only identical VMD identities
   across input files. A truncated name is the name actually present in the
   VMD, not permission to match a longer PMX prefix. nanoem's Windows factory
   uses `MultiByteToWideChar(932, 0)`: incomplete/invalid pairs become U+30FB.
4. Only when that PMX name is absent, use the reviewed standard-meaning table
   and corroborated synonyms. Mining uses unit-weight group equivalence or
   almost identical displacement vectors on the same panel and measured side.
   A partial group recipe is not a whole-expression synonym. Require at least
   three observations and no conflicting meaning; record rejected evidence.
5. Measure each candidate's side from the imported PMX geometry, never its
   native/PMX suffix. PMX +X is character-left. Sum moved-vertex displacement
   magnitudes; >=80% on +X is left, <=20% is right, otherwise bilateral. Group
   vectors combine with signed coefficients before measuring, so cancellation
   cannot invent a second eye. Bone/UV/material/flip effects whose full side
   cannot be measured remain unknown for semantic fallback. No geometry means
   unknown. Eye/brow fallback needs the requested side; a bilateral eye morph
   requires a bilateral target or a complete left/right pair. Exact identities
   and explicit manual choices retain the model/user's own authored behavior.
6. Read geometry lazily from the immutable imported `model.bin`, with bounded
   spans/counts and cycle rejection, caching summaries for at most 16 assets.
   Do not modify native binaries, rig/controller names, presets or source PMX.
7. Native controllers keep their IDs. Overflow morphs use virtual IDs above
   the entity's Source flex count; build/debug wire IDs are signed 32-bit.
   Playback and reset route these through `mmdhl.SetMorphWeight`, which already
   networks overflow weights. This avoids the native 96-controller limit.
8. Show every target's original PMX name beside its stable controller name;
   mark overflow targets `(PMX)`. The Assigned Flex column shows actual resolved
   targets, not a motion's semantic hint. Keep raw names for saved overrides.
9. Built format becomes v2 and its path gains `_fm2`, so both server caches and
   client replicas rebuild without deleting user files. Existing imported
   motions remain readable. A source file already stripped/merged by an older
   importer cannot recover absent identities; reimport its VMD to recover them.
10. Ordinary Source models retain their existing alias and atomic split path,
    including the old semantic hint when an importer canonical was corrected.
    Extend existing DATA alias copies in memory with corrected bundled aliases;
    never overwrite that user file. Hotloader semantic fallback uses the
    reviewed PMX table rather than guessing sides from Source flex names.

## Consequences

Guinaifen and Robin bind `笑い`, `ウィンク`, `まばたき`, `はぅ` and `なごみ` to
their original morphs regardless of native spelling. New model families need
evidence before receiving fallback aliases. An unresolved expression is more
truthful than an invented one. The geometry reader adds a one-time cost only
when a model needs semantic fallback or the QA inspector asks for geometry.

No native rename is shipped: that would invalidate existing saved face presets.
The built/debug protocol changes with the bundled importer on both realms;
mixed old/new client scripts are unsupported, as with its existing build plan.

## Alternatives considered

- More English aliases alone: cannot recover custom identities or distinguish
  a reversed side; still loses information during import.
- NFKC/case/prefix matching as exact: nanoem does not do that. Width-sensitive
  names can intentionally coexist and long VMD names can collide.
- One available half of a two-eye morph: reproduces the reported wink.
- Renaming native flexes: breaks persistent user data and exceeds this task's
  native scope. Keep an advisory list for a future versioned migration.
