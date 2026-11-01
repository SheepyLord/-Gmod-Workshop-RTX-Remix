# R8-B: the Backrooms work's native fixes in the RTX package (brief)

Read [AGENTS.md](../../AGENTS.md) (rule 7: GPL code stays in `packages/fixes`), [R8-plan.md](R8-plan.md),
[packages/fixes/README.md](../../packages/fixes/README.md) and the corresponding-source notes it links
(`packages/fixes/licenses/oversized-skinning/Source.md`, `.../memory-limits/Source.md`, `build-pins.json`).
Work on branch `r8-backrooms` in `out/worktrees/r8-backrooms`, and for the native port on a new branch of the
fixes clone `H:\BACKUP_20260815\Modding\garrys-mod-rtx-remixed` in a worktree under
`out/worktrees/r8-fixes-native` (local commits only, never pushed). Owns: `packages/fixes/licenses/**` (new
corresponding-source notes for this change), `packages/fixes/README.md`, and additive edits to CHANGELOG,
RESEARCH, TESTING. Does not touch `loader/**`, `companion/**`, `glass/**`, `runtime/**`, other packages.

## The user's request (2026-11-01)

"Refer to RTX-Remix modern_house enhancement session, it mentions Backrooms addon needs gmRTX's Lua lighting
API to create its lights, please also inspect its work and deploy the fixes when possible."

## What the other session built (read only)

The Backrooms RTX work for gm_br maps lives in the fixes clone on branch
`claude/rtx-remix-map-enhancement-bda9ac` (worktree `.claude/worktrees/rtx-remix-map-enhancement-bda9ac`,
`docs/GM_BR_RTX.md`): a Lua add-on `gm_br_rtx` (lights through gmRTX's Lua lighting API, visibility and Remix
settings), a 14 GB Remix texture mod (not shippable: too large, and `.dds`/`.usda` are not Workshop types),
and three RTXFixesBinary changes the user's install does not have:

- `6b4794f` RTXFixesBinary: remember models without a SW VTX for the map (`source/modelload_fixes.cpp`);
- `62f4af0` RTXFixesBinary: read the model transform only for draws that use it
  (`source/HardwareSkinningHooks.cpp`);
- `e4d548d` Backrooms RTX: keep the room next door in the ray-traced scene (`source/culling_patches.cpp`,
  plus the add-on's Lua that uses it; without it the add-on falls back to the old `pvs` culling).

That session installed the add-on and the texture mod into the user's field install and left the DLL alone,
because the loader deploys `gmcl_RTXFixesBinary_win64.dll` from this package. The package's DLL is built from
fixes commit `a2c8dbc5` (memory-limit change on the oversized-skinning build `b23c58fa`); the Backrooms branch
split from that line at `f28bd5a9`.

## What to do

1. Review the three native changes (and any later ones on that branch that the add-on needs) for safety on
   every map, not only the Backrooms maps: crashes, behaviour changes with RTX off, performance, interaction
   with the oversized-skinning protections and the memory-limit change.
2. Port them onto `a2c8dbc5` (resolve conflicts with the oversized-skinning work in
   `HardwareSkinningHooks.cpp` carefully; keep every existing protection), rebuild only
   `gmcl_RTXFixesBinary.vcxproj` with the recorded pins (ReleaseWithSymbols|x64, MSVC 14.44.35207, Windows SDK
   10.0.26100.0, the generated projects in `build-projects`), and run the native tests the notes describe.
3. Check what the `gm_br_rtx` add-on calls: gmRTX's Lua lighting API and the new visibility switch. Confirm the
   package's `remixbinary` Lua provides them, or list the matching Lua change needed (in `packages/fixes`).
4. Write the GPL corresponding source for the new DLL under `packages/fixes/licenses/` like the earlier
   layers (Source.md, the patch, the complete changed files, build pins and hashes) and update
   `packages/fixes/README.md`.

Do not import the DLL (Claude runs `tools\inputs.py import fixes` after review), launch the game, change an
install, upload to the Workshop or push. Put the built DLL and PDB under `out/` and name their paths and
SHA-256 in the report. `tools\test.ps1 -Config Release` must pass (the package-provenance check may flag
docs that reference the not-yet-imported DLL; say so). Report in `docs/handover/R8-B-report.md`: what each
change does, review findings, conflicts and how they were resolved, the build and tests, the Lua API check,
and QA steps for Claude on a Backrooms map (lights created, the next room present, no new console errors).
