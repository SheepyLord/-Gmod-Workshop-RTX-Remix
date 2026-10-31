# R6 T5: drop the fixes' memory-limit call; compress `~gmod_topbr`

Read [R6-plan.md](R6-plan.md) first: its rules, decisions and interfaces bind this task. Background in
[R5-stability-proposal.md](R5-stability-proposal.md) proposal 9, section 2.1, and proposal 11's last
item. Branch `r6-t5-fixes`, worktree `out\worktrees\r6-t5-fixes`. ADR 0066 only if needed.

## 1. `SetMemoryLimits` (proposal 9)

- The RTX fixes module (GPL-2.0, the user's fork at `H:\BACKUP_20260815\Modding\garrys-mod-rtx-remixed`)
  calls `ResourceManager::SetMemoryLimits(256, 1024)` at every module open (`source/module.cpp:431`),
  which sends `rtx.resourceLimits.maxCacheSize` and `.maxVRAM` through `remixapi_SetConfigVariable`; the
  runtime has never had these keys and rejects them at every map load.
- Find the commit the packaged binary was built from: `packages/fixes/files.json` records each file's
  origin (`modules/gmcl_RTXFixesBinary_win64.dll`). In that repository, check `git status` first (the
  user may have uncommitted work: never touch, stash or commit it); make a new git worktree of that
  repository on a new branch from that commit (e.g. `r6-no-memory-limits`), remove the call, and make
  `RemixResource.SetMemoryLimits` a documented no-op that logs once that Remix has no such limits. Do not
  replace it with real budget options set from Lua (`remixapi_SetConfigVariable` writes the User layer,
  which Remix's Save writes into `user.conf`).
- Build `gmcl_RTXFixesBinary_win64.dll` the way that repository builds it (its README or build files),
  and check that the only difference from the packaged binary's behaviour is this change (same source
  commit plus your commit).
- Import it into this repository's `packages/fixes` with `tools\inputs.py import fixes --file ...`,
  `inputs.py verify`, and check `python tools\build_package.py` builds. Commit in the fixes repository on
  your branch only; never push it.

## 2. `~gmod_topbr` (proposal 11)

The fixes part ships the `rtx-remix\mods\~gmod_topbr` mod with uncompressed textures (about 136 MiB).
If a BC7 encoder is available on this machine (`texconv`, NVIDIA Texture Tools, Compressonator, or a
Python package already installed; do not download tools), re-encode them to BC7 where the mod's usage
allows (colour maps BC7 sRGB, normal maps BC5 or BC7 linear as the mod's materials expect), keep the
file names the mod's USD references (or update the references), and import the result. If no encoder is
available, skip this and say so. Measure the size before and after.

## Tests, docs, limits

- `tools\test.ps1`; the package build; CHANGELOG; RESEARCH; `packages/fixes` notes if the part has a
  README for its sources.
- Do not touch `loader/`, `companion/`, `runtime/`, `packages/runtime`. You may not launch the game; in
  your report, say what an in-game check should show (no `rtx.resourceLimits` line in `remix-dxvk.log`;
  `~gmod_topbr` materials unchanged in look).
