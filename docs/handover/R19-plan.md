# R19: the pre-release review's findings fixed, then release v0.14.0

**The request.** On 2026-11-05, after the pre-release review ([R19-review.md](R19-review.md)), the user said:
"All real findings, then test and publish a new release on Github and workshop."

**Decided with the user the same day**
- The release is **v0.14.0**, with loader 0.14.0.
- Claude starts GitHub's package workflow for this release, this once. AGENTS.md rule 5 otherwise
  leaves that to a person.

## Inputs

- [R19-review.md](R19-review.md) lists the verified findings, worst first, by ID.
- The main checkout holds the Codex reports and every verifier's verdict, git-ignored, in
  `H:\BACKUP_20260815\Modding\!NVIDIA-RTX-Remix\out\review-final\`:
  - `task-<job>.md`: one Codex report per area. Each part below names its own.
  - `verdicts.md`: the verifiers' evidence and the problems Codex missed. Each of its sections names
    the job it checked.

**What gets fixed**
- "Real" means confirmed or partly right. False positives are not touched.
- Some findings are real but by design. Give each the smallest change that removes the risk without
  changing the design.
- Where no such change exists, add a comment where the code makes the choice and explain it in your
  report.
- "None" in the verdicts means no change is needed; say so in your report.

## Rules for every part

1. **Where you work.** Only in your worktree, by absolute path; the runtime part also works in the fork
   tree it names.
   - Commit on your branch.
   - Never commit to `main`, push, tag, start a workflow, upload to the Workshop, or run
     `tools/publish_workshop.py`.
2. **Which files you touch.** Only your part's paths.
   - Do not edit the shared docs: `CHANGELOG.md`, `AGENTS.md`, and `docs/ROADMAP.md`, `RESEARCH.md`,
     `TESTING.md` and `COMPONENTS.md`, `handover/README.md`, `decisions/README.md`. Put the lines you
     propose for them in your report.
   - You must still keep these current: the `.md` beside every script you change, each C++ module's
     `README.md`, and the decision record whose number is given to you.
3. **`packages/` changes only through `tools/inputs.py import`**, text files too, as
   [packages/README.md](../../packages/README.md) "Updating a part" says. Then run
   `python -I tools\inputs.py verify`.
4. **GPL code stays in `packages/fixes`** (AGENTS.md rule 7).
5. **Temporary and build files go under your worktree's `out\`.** Never use the system temp folder.
6. **What you never touch**
   - Steam's files.
   - The field install `H:\SteamLibrary\steamapps\common\GarrysMod`.
   - Remix `user.conf`.
   - The user's game logs.
7. **Do not start the game.** List in your report what the integrator should check in game, and how. The
   integrator runs the combined PoC sessions.
8. **Commits.** Each message says what changed and why, and ends with
   `Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>`. The runtime fork's commits are the
   exception: author `SheepyLord` with the fork's own git identity (its configured noreply address), and no
   AI trailer, as the fork's `CLAUDE.md`
   asks.
9. **Tests**
   - Add a test for each fix wherever the code around it has tests.
   - Run what covers your change: `python -I -m pytest tools\tests\<file> -q` for the tests you touched;
     `tools\test.ps1 -SkipNative` for the conventions; `tools\build.ps1 -Config Release` and CTest for
     this repository's C++.
   - Before your report, run `tools\test.ps1` in full, or `-SkipNative` if you changed no C++ here.
10. **This machine**
    - Use PowerShell for Windows paths: heredocs in the Bash tool lose backslashes.
    - Run the repository's Python with `-I` from the repository root, so that a stray `queue.py` or
      `json.py` cannot shadow the standard library.
11. **When to stop and report back** instead of guessing:
    - a fix would loosen a trust rule (AGENTS.md rule 4);
    - it would change a published file format or a shipped Lua API beyond what your section allows;
    - it needs the user's decision.
12. **Your report.** Write `docs/handover/R19-<letter>-report.md` on your branch and commit it. It holds:
    - for each finding ID: fixed (how, which files), by design (why), or not fixed (why);
    - the tests you ran and their results;
    - the CHANGELOG lines and RESEARCH facts you propose;
    - what the integrator must do: imports, pins, in-game checks, and any user-visible strings to
      translate;
    - open issues.

    Your last message gives the report's path and a summary of at most ten lines.

## Parts

| Part | Worktree (under `H:\BACKUP_20260815\Modding\!NVIDIA-RTX-Remix\out\worktrees\`) and branch | Codex reports |
|---|---|---|
| R19-L loader | `r19-loader`, `r19-loader` | `task-mw40gx2d-mx0ryu.md` (core), `task-mw40gyp5-6sl409.md` (proxy, CLI) |
| R19-R runtime | `r19-runtime`, `r19-runtime`; fork tree `r17\out\runtime-src` | `task-mw40igsn-lqi299.md` (0021-0032), `task-mw40jm2u-u90jd7.md` (0004-0020) |
| R19-X RTX fixes | `r19-fixes`, `r19-fixes` | `task-mw40ht99-s8kfzh.md` |
| R19-E editors | `r19-editors`, `r19-editors` | `task-mw40hobp-dfq1mu.md`; BR-02, BR-03 in `task-mw40hbhb-wibgei.md` |
| R19-H Hotloader and motion | `r19-hotloader`, `r19-hotloader` | `task-mw40hf6a-gc1uyv.md` (native), `task-mw40hmqv-si2gt0.md` (Lua); F-03 in `task-mw40i2w9-6ipiaq.md` |
| R19-G glass and companion | `r19-glass`, `r19-glass` | `task-mw40hbhb-wibgei.md` (GL-01 and the two map misses), `task-mw40h5pg-g30nzx.md` |
| R19-T tooling and CI | `r19-tooling`, `r19-tooling` | `task-mw40i2w9-6ipiaq.md` |

## R19-L: the loader

Paths: `loader/`, `dist/`, and `companion/nativeloader/lua/autorun/_nativeloader_guard.lua`. You may
use decision record number **0111**.

### H2: content packages only from subscribed items (high)

**The problem**
- Content-only discovery (`loader/core/src/discovery.cpp:244-273`) takes every folder in
  `workshop/content/4000` whose single `.gma` lists `native/manifest.json`.
- GMod's `steamworks.DownloadUGC`, which any server's client Lua may call, installs items there
  without a subscription (RESEARCH.md around line 2378; ADR 0015 step 3).
- So a server can make a client deploy a permanent Lua add-on and a Remix mod at the next start.

**What to do**
- Accept a content-only candidate only when Steam's `WorkshopItemDetails` entry for the item has a
  `subscribedby` that is present, non-empty and not `"0"`.
- **An item already deployed but not subscribed** is removed like an unsubscribe (ADR 0025), and its
  reason says so. Proposed wording: "not subscribed: Steam has it only because the game or a server
  downloaded it".
- **When `appworkshop_4000.acf` is missing or unreadable**, add no new content candidates. Keep the
  content packages already deployed, so that one bad read does not remove and redeploy them.
- **Allowlisted items** (`allow.workshop`) are unchanged.
- **Tests:** add cases to `loader/tests/test_discovery.cpp` (with, without and `"0"`; acf missing) and
  to whatever integration test covers content packages.
- **Decision record:** write
  `docs/decisions/0111-content-packages-only-from-subscribed-items.md`. It amends
  [ADR 0027](../decisions/0027-content-packages-from-any-subscription.md) decision 1; do not edit 0027.

### M5: a left-over original blocks deployment

- `displace()` (`loader/core/src/deploy.cpp:786-795`) sends a take-over's original to
  `backup/originals/<path>`, a path with no transaction number.
- Uninstall can leave a file there (`:1494-1497`, "put it back by hand"), and moves never replace
  (`fs.cpp:101`). The next deployment that takes over that path then fails, every time.
- **The fix:** when a file already exists at that place on disk but not in the journal, keep the newly
  displaced file as a changed copy under `backup/edits/<tx>/<path>`, with a note. Never overwrite and
  never fail. Add a test.

### The other findings

- **Core, NLCORE-01 to 05:** fix each as the verdicts describe (small).
- **Proxy F-01:** the fix is the wording in `dist/README-native-loader.txt:71-72`. Point players to
  `remix.enabled:false` to play without RTX, and say what `-nonativeloader` does and does not do.
- **Proxy F-02:** the guard installs from any old `status.json` that says "active".
  - Make it install only when the status file comes from **this** start.
  - `status.json` carries `session_token` (PID plus the process creation time; see
    docs/ON_DISK_LAYOUT.md).
  - Lua cannot read its own PID, but MSVC's `clock()` (LuaJIT's `os.clock`) is the wall time since the
    CRT started. So `os.time() - os.clock()` estimates the process start; compare it to the token's
    creation time with a tolerance of about 30 s.
  - Verify these semantics in the source you can read, choose the most robust check you can justify,
    and keep the early and verified-multiplayer routes working.
  - Describe the in-game check for the integrator: an off-switch start right after an RTX start must
    not install the guard.
- **Proxy F-04:** a `load_first` dependency that failed may be tried again; record only a success.
- **Proxy F-05:** never OR `LOAD_WITH_ALTERED_SEARCH_PATH` with `LOAD_LIBRARY_SEARCH_*` flags.
- **Proxy F-06:** the observer's forwarding table must never hold null targets that a call could reach.
- **Proxy F-07:** `nlctl scan` reports the entries it skipped and the errors it met.
- **Proxy F-08:** keep the design. Write a comment at the `LoadLibraryW` explaining why no lock cycle
  can form, with the verifier's evidence, and propose a RESEARCH line.
- **Proxy F-03:** a false positive; leave it.
- **The version:** do not bump it. The integrator sets 0.14.0.

## R19-R: the runtime

**Where you work**
- Fork tree: `H:\BACKUP_20260815\Modding\!NVIDIA-RTX-Remix\out\worktrees\r17\out\runtime-src`. It is
  detached at `e095f29a` (patch 0032); create branch `claude/r19-review-fixes` there.
- Repository part: your worktree, for `runtime/` and `packages/runtime`.
- Read [runtime/README.md](../../runtime/README.md) and the R18 report for how a patch is built, exported
  and imported.
- Export exactly one new patch, 0033:
  `git format-patch -1 --start-number 33 -o <absolute path to your worktree's runtime\patches>`.
  Re-exporting the range rewrites every patch header.
- Update `runtime/base.json` (`packaged`), add a section to `runtime/README.md`, and import `d3d9.dll`
  with `runtime\build_runtime.ps1`.

### H1: the DDS reader (high)

**The partial loader** (`src/dxvk/rtx_render/rtx_asset_data_manager.cpp:120-190`)
- Reject a mip count below 1 or above 16 (the array's size), and above what the dimensions allow
  (`floor(log2(max(w,h,d))) + 1`).
- Reject a zero width or height.
- Reject a layer or face count that the size check could overflow on.
- Do the level-size sums in 64 bits with overflow checks.

**GLI's `load_dds`** (`include/gli/core/load_dds.inl`, release build)
- Before each read, check that `Size` holds the header (and the DX10 header).
- Check that `Offset + Texture.size() <= Size` before the copy.
- Return an empty texture otherwise.

**Tests:** add a unit test in the fork's test suite, where the texture-budget tests live. Use crafted
headers: 17, 18 and 2^31 mips, a short file, a huge `ArraySize`. Each must be rejected with no write
outside the object.

### The other findings

- **Runtime 0004-0020, R-01 to R-03:**
  - R-03: reject NaN and infinities in the float option parser.
  - R-01 and R-02: as the verdicts and Codex's report say. R-02's verdict is a rewording.
- **Runtime 0021-0032:**
  - **F-01:** the game-thread readers of string options (`rtx_imgui.h:323-340` and the callers the
    verdict lists) must copy under the update mutex. A locked accessor that returns a copy is fine.
  - **F-03:** on a texture cache hit, a later preload request upgrades the cached texture to the
    strongest requirement of its users.
  - **F-04:**
    - Replace the three-probe early-out in `marchEchoDeck` with a conservative test: sample the patch
      mask along the ray at a spacing no wider than a quarter of the patch size, up to a fixed cap.
    - Skip only when every sample is empty, and interpolate the cover from those samples.
    - Keep the cost within noise of R18's: middle deck 0.15-0.3 ms at 4K.
  - **F-05:** evaluate the patch mask at each moon-shadow tap, on the middle deck only.
  - **F-02:** a false positive; leave it.
- **Tests:** run the fork's unit tests and build. In your report, describe the in-game check: partly
  cloudy, day and night with a low moon, against R18.

## R19-X: the RTX fixes (GPL)

Paths: `packages/fixes`, `tools/ci/build_modules.ps1` (fixes and water parts), `tools/ci/pins.json` (the
`fixes` section), and their tests. You may use decision record number **0112**. The fixes' public clone is
`H:\BACKUP_20260815\Modding\garrys-mod-rtx-remixed`; read it, never write it.

### H3: ToPBR's output folder (high)

- **`SetOutputDirectory`** accepts any string from any server's client Lua, and `EnsureOutputDirectory`
  creates and writes there. A network path makes Windows send the player's login to that host.
  - Accept only a relative path inside the folder the shipped Lua uses (read which). Refuse absolute
    paths, drive letters, UNC and `\\?\` paths, `..` segments and `:`.
  - Recheck the resolved path, and fail with a warning.
- **`SetEnabled(true)`** must not override the player's `rtx_topbr_enabled 0`. **`ProcessSingleMaterial`**
  and every other entry point that starts work obey the same setting.
- **The other setters:** look through the rest of `MaterialPipeline.ToPBR` and the fixes' other native
  Lua APIs for setters of this kind, and close them the same way.

**How the change ships**
- It goes in a new GPL patch in `packages/fixes/licenses/oversized-skinning/autopbr/`, listed in
  `pins.json` `fixes.patches`.
- **The tree check.** `build_modules.ps1` compares the patched tree to `patched_commit`, a commit that
  would have to exist on GitHub. Replace that with object ids that `pins.json` records for the patched
  `source`, `public` and `premake5.lua`: run `git write-tree` on the index, then `rev-parse <tree>:<path>`.
  The check then holds anywhere with no pushed commit. Update `test_ci_tools.py`.
- **The source copy.** Update the GPL copy at `packages/fixes/licenses/oversized-skinning/autopbr/source/`
  so it matches.

### The other findings

- **F-01, the water polygon:** `rtxwater.cpp:1024` must require an even length of at least 6. Add
  `fixes.rtxwater_patches` (applied after the water source is restored), its patch file and its
  recorded tree.
- **F-03, F-04 and the flashlight miss** (the fixes' flashlight Lua):
  - destroy the old light before creating a new one;
  - give each player a cooldown on each receiver;
  - let `PlayerSwitchFlashlight` respect the gamemode and `ply:CanUseFlashlight()`, so that dead
    players and spectators get no flashlight.
- **F-05 and F-06:** false positives; leave them.

**Build and import**
- Build locally with `tools\ci\build_modules.ps1 -Only fixes,rtxwater` and local copies; the folder's
  [README](../../tools/ci/README.md) shows how.
- Import with `tools\package_fixes.py` and `inputs.py import`; packages/README.md shows how.
- Check that only the files you meant to change differ.

## R19-E: the editors

Paths: `packages/advanced-material-editor` (Lua and the bridge's source copy),
`packages/advanced-bodygroup-tool`, `packages/procedural-bodygroup-destruction`, and the `advmat`
section of `tools/ci/pins.json` if needed.

**The findings**
- **ADV-01:** encode the snapshot once per revision and reuse it; bound the queue.
- **ADV-02:** a HELLO never resets the rate limit, whatever its protocol.
- **ABT-01:** validate dupe data, so a crafted paste cannot raise errors.
- **ABT-02:** a bounded cache with least-recently-used eviction.
- **ABT-03:** a cooldown on each player's receivers.
- **ABT-04:** players other than the user themself need the same rule that L-01 sets, self or admin,
  if the tool reaches player entities; props stay with prop protection.
- **BBS-01:** `GetBool` must return the setting when it exists. The `and/or` idiom turns false into the
  fallback.
- **BBS-02:** rate-limit the console lines for denied packets.
- **BR-02:** check the length before copying, and catch C++ exceptions at the Lua boundary.
- **BR-03:** `ValidateDds` checks the mip count and the data size against the file size, and a cached
  copy gets the same full check.
- **BR-01:** a false positive; leave it.

**Build and import:** build the bridge with `tools\ci\build_modules.ps1 -Only advmat`, then import it
and the Lua as packages/README.md shows.

## R19-H: the Model Hotloader and the motion importer

Paths: `packages/model-hotloader` (Lua, the native source copy, the policy), `packages/character-motion-importer`,
and the `hotloader` section of `tools/ci/pins.json` if needed.

### H4 and M8 (high and medium)

- **L-01 (H4):** `SelectTargetForPlayer` and `OpenDebugForPlayer` accept a player target only when it
  is the requester, or the requester is an admin.
- **L-09 (M8):** give `BuiltCache` a byte budget, and cap each player's builds and files.

### The misses (M9 and the Force Reset miss)

- **M9:**
  - Restore the third-party convars that a build or a dance turned off: on `ShutDown`, and at the next
    start from a small record kept in `data/`.
  - Never save our own 0 as the "original".
  - Restore only while the value is still the one we set.
- **The Force Reset miss:** Force Reset and death unfreeze or unhide a player only if this add-on froze
  or hid them.

### The other motion findings

- **L-02:** check remove and replace as the `remover` property, and owner-check them as `owns()` does.
- **L-03:** "stop all" stops the requester's own dances unless they are an admin.
- **L-04:** see M9.
- **L-05:** a disconnect stops the leaver's dances.
- **L-06:** a cooldown on the debug request.
- **L-07:** a range check.
- **L-08:** a server-side cooldown.

### The Hotloader native

- **MH-01 (M7):**
  - A texture path may not leave the model's own import root. For a Workshop item that is the item
    folder; for a local import it is the folder the player chose.
  - Keep `..` inside that root, for 2.2 compatibility.
- **MH-02:** key remembered grants on something the caller cannot choose.
- **MH-04:** a memory budget checked before allocation.
- **MH-05:** evict remote collision shapes when their entity goes away, plus a cap.
- **MH-06:** let shutdown cancel queued work, so the map change waits only for work already running.
- **MH-03:** a false positive; leave it.

### Tooling F-03

`packages/model-hotloader/source/mmdhl/scripts/bootstrap.py` extracts codeload tarballs without a
digest. Either fetch by commit through git, which checks the object hashes, or pin and check the
archives' SHA-256. GitHub's archives are not guaranteed to stay byte-stable, so prefer git.

### Build and import

- Build the natives with `tools\ci\build_hotloader.ps1`; its `.md` explains `-Vendor`. It regenerates
  `native_policy.lua` and `mmdhl-native-release.json`.
- Import as packages/README.md shows.

## R19-G: glass and the companion's eye whites

Paths: `glass/`, `packages/glass` (import of the rebuilt module), and
`companion/nativeloader/lua/autorun/client/nativeloader_eye_whites.lua`.

**Glass native**
- **GL-01:** check each lump's declared size against the remaining budget *before* inflating it, and
  count the static-prop lump too.
- **The 'sprp' miss:** cap the total number of static props across entries, or read only the first
  `sprp` entry, as the engine does.
- **The leaf-walk miss:** a work budget on the brush-reference walk, so `ShutDown` never waits long.

**Glass Lua**
- **F-01:** forward bullets only when their path is in the player's PVS or near the player, as well as
  in an interest region.
- **F-02:** pace the full pane sync across ticks with a per-player byte budget, and allow one full
  initial sync per connection.

**Companion**
- **F-03:** cache eviction deletes only files whose names match the companion's own digest naming.
- **F-04:** by design (the documented retention of the companion's own telemetry); no change.

**Build and import:** build with `tools\build.ps1 -Config Release`, run CTest, and import
`gmcl_nlglass_win64.dll` into `packages/glass` as `packages/glass/README.md` says.

## R19-T: tooling and CI

Paths: `tools/` (except `tools/ci/build_modules.ps1`, the fixes part, and `tools/ci/pins.json`'s
`fixes` section) and `.github/workflows/`. The package workflow runs for this release right after
integration, so every change to it must be right the first time. Check the YAML, and keep
`test_ci_tools.py` passing.

### M1: the release that the next commit overwrites (medium)

- After `publish_workshop.py --from-ci` uploads, `published.json` has no fingerprint, so the next hook
  run on `main` uploads a local development build over the release.
- **Record the full commit SHA.** In the local path, while `published.json` holds a GitHub release
  whose commit has the same packaging inputs as `HEAD` (`git diff --quiet <sha> HEAD -- <inputs>`),
  report `unchanged-inputs`, record the fingerprint, and upload nothing.
- **Test both directions:**
  - inputs unchanged since the release: no upload;
  - inputs changed: the development build uploads as before.

### The other findings

- **F-01:** pass `github.ref_name` and similar values to the shell through `env:`, never inline.
- **F-04:** set `actions: write` only on the job that deletes artifacts.
- **F-05:** report and refuse files without a hash, or copy them flagged as unverified.
- **F-07:**
  - Delete the older `rtx-package` artifacts only *after* the new upload succeeds.
  - The job is under the R16 storage rule, so it still keeps one artifact.
- **F-08:** cap the LZMA spool at the size the archive declares, or a fixed maximum.
- **F-09:** `inputs.py` rejects path parts ending in a dot or a space, and other Windows aliases.
- **Miss: no run is not success.** `--from-ci` must fail when no run is found, rather than treat "no run
  within 5 min" as success. The push triggers are gone (ADR 0108).
- **Miss: unpinned pillow.** Pin `pillow` in `build.yml` to an exact version.
- **F-03:** goes to R19-H.
- **F-06:** a false positive; leave it.

## Integration (Claude)

1. **Merge.** Merge the parts into `r19-int` and resolve the conflicts.
2. **Version and docs.**
   - Set the version to 0.14.0.
   - Write the shared docs and the decision index.
   - Have Codex translate any new user-visible strings.
3. **Build and test.** Run `tools\build.ps1 -Config Release` and `tools\test.ps1`, then build the
   package and compare.
4. **Check in the game.** Run PoC sessions for the parts' in-game checks, the package's deployment, an
   RTX session with no Lua errors, the guard after an off-switch start, glass, and the sky.
5. **Release.**
   - Merge into `main`; the hooks publish the development build. Push `main`.
   - When CI passes, tag `v0.14.0` (GitHub release of the loader bundle).
   - Start the package workflow, then `publish_workshop.py --from-ci --commit <sha>`.
   - Check in the field with two starts.
6. **Report.** Write the R19 report.
