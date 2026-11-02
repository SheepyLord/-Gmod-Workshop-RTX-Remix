# 0091: Bounded automatic PBR fallbacks and imported game maps

- Status: Accepted 2026-11-02 (R11); the runtime precedence it required is [ADR 0092](0092-generated-fallback-mods-rank-last.md) (runtime patch 0020)
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

## Final implementation evidence and corrections

The measured client snapshot initially peaked at 23.553 ms because VMT reads and companion probes
still ran there. The final pipeline prepares two owned VMT snapshots on the worker, adds live
IMaterial values/hashes on the client (one per frame), and decodes through two ready slots. The
same Construct view and 45 emitted materials now peak at 0.830 ms for client inspection; conversion
p99 is 9.133 ms rather than 23.472 ms. Registered normal/roughness values are unchanged by this split.

The initial HL2 figures above are not valid acceptance measurements: the explicit camera was outside
the map, and the default trainstation view is its scripted G-Man introduction. The report distinguishes
those runs and uses a canal map for useful HL2 inspection. Default world conversion remains 0; game
maps default to 1 as requested. Exact canonical stems, known local PMX sources and supported channel
layouts are required; ambiguous/differently named inputs remain unchanged.

The completed shader-channel/UV/lifecycle checks and final release gate are recorded in the R11-A
report. No folder scan is promoted to an unconditional precedence guarantee: runtime integration
remains required before acceptance/merge.
