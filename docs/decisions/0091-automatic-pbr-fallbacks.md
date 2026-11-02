# 0091: Bounded automatic PBR fallbacks and imported game maps

- Status: Implementing on R11-A, 2026-11-02; runtime precedence prerequisite remains outside scope
- Decided by: the user's R11 items 34 and 32 and explicit replacement-priority requirement

## Decision

Treat generated materials as fallbacks. Keep vanilla ToPBR opt-in (`rtx_topbr_enabled 0`).
Move live Source material inspection onto the client frame (one snapshot, at most two ready jobs).
Decode, derive maps, inspect competing mods and publish on one worker; cap queued names at 8192
and images at 4096 squared. Rebuild material registrations from current live hashes each session.
Reuse DDS only through a key containing source bytes, generator version and material recipe, with
complete DDS header/payload validation. Negative material-name results are session-local.

Publish complete, sorted USD snapshots atomically, including empty snapshots on disable. Touch the
root layer only after a changed snapshot. Do not resurrect commented VMT properties by default.
Use perceptual GGX roughness from Phong; reflection masks retain a roughness floor. Darkness,
Phong boost and a physics surface name are insufficient metallic evidence. Explicit community PBR
channels and the existing unmasked-chrome path remain distinct.

The baseline `rtx_topbr_stats` called removed Lua functions, and the enable switch did not retract
cached USD entries. Before/after timing of that old switch cannot establish that conversion was off.
The baseline Construct view was 7.29/7.19 ms median; HL2 trainstation was 18.88/24.01 ms, with visible
scene/exposure variation. The final report records controlled revised runs. These observations do
not justify enabling broad heuristic conversion for every player.

## Replacement precedence and scope limit

The fixes conservatively scan competing USD text (including fragments and names sorting after `~`),
exclude every found material hash, and republish removals as mods change. Unknown binary USD,
reparse points, read failures or exceeded scan bounds suppress generated output. Scanning may
exclude more than the active USD stage, deliberately favoring authored content.

This is **not the requested absolute hot-reload guarantee**. Runtime
`src/dxvk/rtx_render/rtx_asset_replacer.cpp:getReplacementMaterial` returns the first mod containing a
hash; `rtx_mod_manager.h:ComparePtrs` orders equal-priority mods by path, and no API sets a fallback
rank. An asynchronous runtime swap can precede fixes-side conflict detection/removal. Binary USD
composition and external layer references also cannot be authoritatively resolved by this scanner.
R11-A is prohibited from editing `runtime/**`. Claude needs a runtime change that always resolves
all authored replacements before this generated mod, invalidating cached translations on swaps.
Changing folder names, guessing a maximum Unicode name or scanning faster does not prove this.

## Imported game maps

Phase 2 adds a separate default-on client setting and bounded conversion from known local source
PMX paths. Original albedo/coverage and named skin, face and eye surfaces remain protected. Shader
channels, aggressive class recipes, tests and rendered limitations are recorded in the final report.
No field files, Steam depot bytes, user.conf, trust rules or native ABI are changed.
