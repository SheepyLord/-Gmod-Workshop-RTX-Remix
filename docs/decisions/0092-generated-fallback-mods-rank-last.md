# 0092: Generated fallback mods rank after every authored mod

- Status: Accepted 2026-11-02 (R11; Claude, for the user's note on item 34)
- Decided by: the user: "actual PBR replacements, if exists, should always overwrite the autoPBR result";
  completes the precedence part [ADR 0091](0091-automatic-pbr-fallbacks.md) left to the runtime

## Context

The RTX fixes' ToPBR writes automatic PBR materials into its own mod, `~gmod_topbr`. Remix takes a
material from the first mod that has one (`AssetReplacer::getReplacementMaterial`), and mods are a set
ordered by `Mod::m_priority`, which was 0 for all, then by path. So a generated material lost to an
authored one only because `~` sorts after ASCII names: a pack whose folder name sorts after `~` (any
non-ASCII name) lost to it. ADR 0091's fixes-side guard skips hashes it finds in other mods' USD text and
retracts late conflicts, but it reads text only, runs on its own schedule (a late pack lost for about
0.8 s in R11-A's test) and cannot read binary USD.

## Decision

Runtime patch 0020: mods whose folder names are listed in `rtx.gmod.fallbackMods` (default
`~gmod_topbr`; comma-separated, matched without ASCII case) get `m_priority` 1 when the mods are
enumerated. Every lookup that walks the mods in order (materials, meshes, lights) therefore consults
them after every authored mod, whatever the names sort as, and a pack loaded or hot-reloaded after the
fallback wrote its material wins as soon as its own data is swapped in. Asset search paths, where the
last path wins, take the fallback mods' paths first. Folder names are compared as UTF-8, so a name
outside the ANSI code page cannot throw during enumeration.

The fixes-side guard stays: it keeps ToPBR from converting what a pack already covers (less work, no
duplicate textures) and keeps older runtimes safe. Its rule that an unreadable mod suppresses all
generated output remains a coverage limit, no longer a precedence one.

## Consequences

- The user's rule holds in the runtime, for both world ToPBR and the imported characters' game maps.
- Another generated mod can be ranked the same way by adding its folder to the option (in `rtx.conf`);
  the option is read when mods are enumerated, so a change applies after a restart.
- A runtime without patch 0020 keeps the old name order; the fixes' guard still covers the common cases.

## Alternatives

- Renaming the fallback mod: no name sorts after every possible folder name.
- Faster scanning or polling in the fixes: still a race with the runtime's own swaps, and blind to
  binary USD.
- A per-mod marker in `mod.usda`: needs the layer opened before ordering and a fixes change; a
  name list keeps the shipped mod as it is.
