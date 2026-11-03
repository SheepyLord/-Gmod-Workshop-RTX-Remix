# 0099: Saved characters load on first use; the most recently used stay ready

- Status: accepted within R13-A, the user's approval of the [R13 plan](../handover/R13-plan.md) (2026-11-03)
- Decided by: R13-A (Claude subagent); supersedes the publication rule of
  [ADR 0090](0090-ready-carriers-before-actor-publication.md) (entries only after precache)

## Context

[ADR 0090](0090-ready-carriers-before-actor-publication.md) made every map mount and precache each
saved NPC and player-model character before its NPC-tab or player-model entry was published, so the
entries work after a map change. Precaching a model loads it with its materials and textures: on the
copied field library (57 characters, 98 loadable saved NPC/player rigs) a map start held every
character's textures in memory with nothing spawned (private bytes 27.0 GB, working set 20.9 GB on
this computer). Runtime patch 0022 keeps their GPU backing away until a texture is first used, but
their CPU copies stay, and anything that touches all loaded textures at once makes them all
GPU-resident. The [R13-A report](../handover/R13-A-report.md) found that step: the first Combine
soldier of a session (the NPC tab's, or a character spawned in that role) raised game textures
0.29 → 17.07 GB within one frame on the copied library, the lag report's 14.35 GB within 30 seconds;
the AR2 alt-fire ammo item the soldier precaches does it on its own.
The step itself is in the engine or the runtime, outside the hotloader; the hotloader decides how
much is loaded for it to touch.

## Decision

1. **Entries from metadata.** Each map publishes every saved character's NPC-tab and player-model
   entry from validated metadata: a loadable rig whose identity matches its model, its carrier (and
   its arms' carrier) and its material archive on disk. Nothing is mounted or loaded for it.
   `actorRegistrations[model].lazy` marks such an entry.
2. **Ready right before first use.** The server mounts and precaches a published character (the
   ADR 0090 gate: mount the material archive and carrier, precache, `util.IsValidModel`) at its
   first real use:
   - the persistence `Entity:SetModel` wrapper, which every route reaches: the NPC tab (Sandbox's
     `InternalSpawnNPC`), the player's model, saves, dupes and tools;
   - `util.PrecacheModel` and `util.IsValidModel` for a carrier path mount it first (Sandbox's player
     class precaches the player's model before `SetModel`; addons validate models);
   - the hotloader's own spawns, which already pass the same gate before creating the entity.
3. **Clients.** A client in the server's process (single player, a listen server's host) shares its
   mounts, so it publishes host entries from metadata too. A player on another server mounts the
   carrier when the registration arrives, as before (downloading it first), so the carrier is there
   before that server's first use precaches it. `ClientsideModel`/`ClientsideRagdoll` of a carrier
   (a model panel's preview) mount it first, and the server reuses a carrier the client realm already
   mounted (the exact model is visible) instead of mounting it again.
4. **The ready set.** At map start the most recently used characters are made ready as before:
   newest use first, at most `activation.memory.warm_characters` characters and
   `activation.memory.warm_mib` MiB of material archives, both from `native-loader/status.json`
   (R13-C's memory profile). No file or no field: none. A character too large for what is left is
   passed over for an older one that fits; a character never used is not kept. Use is recorded on
   every spawn (any role), NPC-tab spawn, player model, restored or pasted entity, in
   `mmd_hotloader/recent.json` (`[asset, unix time]` pairs, newest 512); a character used before
   that record existed falls back to the time the native module last prepared one of its carriers
   (it rewrites `names/rigs/<key>.json`). Server ConVars `mmdhl_warm_characters` and `mmdhl_warm_mib`
   (default -1, automatic) override the two values for tests and apply at once.
5. **Menu icons.** A carrier has no visible mesh, so the engine's spawn icon of one is an empty
   image (215 bytes in the field's cache), and drawing it loads the model and its textures.
   `SpawnIcon` (the Player Model window, spawnlists, model pickers) shows a carrier's real cached
   image if one exists, otherwise the character's name, and never gives `ModelImage` the model.

## Consequences

- With nothing spawned, no character outside the ready set is mounted, precached or loaded: private
  bytes 14.97 GB and working set 9.09 GB with a high computer's ready set of 10 characters, 9.56 GB
  and 3.53 GB with none (from 27.03 GB and 20.87 GB).
- The first Combine soldier makes the ready set and the characters used so far resident instead of
  every saved character (5.0 GB instead of 16.8 GB with 10 ready). The ready set's archive cap
  (`warm_mib`) bounds that part until the engine-side step is fixed.
- A character's first use loads it then; the delay is measured in the report. Characters in the
  ready set and characters used earlier in the session spawn as before.
- Source keeps a used character's model, materials and textures until the map changes: GMod has
  no way to unprecache a model, and a global material reload disrupts other content. R13-B releases
  their idle GPU images; the next map no longer loads them unless they are in the ready set.
- The NPC tab, the player-model selector, saves, dupes, map changes and delete/reimport
  ([ADR 0094](0094-reimported-carrier-metadata-and-state.md)) keep working; entries stay published
  after a map change (ADR 0090's purpose), now from metadata.
- Multiplayer players of another server still download and mount at registration (unchanged).

## Alternatives considered

- **Keep precaching every saved character and only defer GPU backing (patch 0022 alone):** their
  CPU copies stay (tens of GB on the field), and one event that touches every loaded texture makes
  them all resident.
- **Drop the precache without readiness at use:** ADR 0090's missing-model and error-model failures
  after a map change return.
- **Unpublish unready entries:** the NPC tab and the selector would no longer list them.
- **Render menu icons offscreen:** a carrier's icon is empty; the name is more useful and loads
  nothing.
