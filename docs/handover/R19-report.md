# R19 report: the pre-release review's findings fixed, release v0.14.0

**The request.** On 2026-11-05, after the pre-release review ([R19-review.md](R19-review.md)), the user
said: "All real findings, then test and publish a new release on Github and workshop."

**Decided with the user**
- The release is **v0.14.0**, with loader 0.14.0.
- Claude starts GitHub's package workflow for this release, this once.

The plan and the parts' briefs are in [R19-plan.md](R19-plan.md).

## What was done

Seven Claude subagents fixed the findings in parallel, each on its own branch and worktree. Claude
integrated them on `r19-int`.

| Part | Report | Findings fixed |
|---|---|---|
| R19-L loader | [R19-L-report.md](R19-L-report.md) | H2 (content packages only from subscriptions, [ADR 0111](../decisions/0111-content-packages-only-from-subscribed-items.md)), M5, NLCORE-01 to 05, proxy F-01, F-02 (the guard's session marker), F-04 to F-07; F-08 kept by design with its reason at the code; F-03 a false positive |
| R19-R runtime | [R19-R-report.md](R19-R-report.md) | H1 (the DDS readers, patch 0033), F-01, F-03, F-04, F-05, R-01, R-03; R-02 by design (reworded); F-02 a false positive |
| R19-X RTX fixes | [R19-X-report.md](R19-X-report.md) | H3 and its miss (ToPBR and the other Lua path APIs, [ADR 0112](../decisions/0112-fixes-lua-apis-stay-in-the-game-and-follow-the-player.md)), F-01, F-03, F-04, the flashlight miss; F-05, F-06 false positives |
| R19-E editors | [R19-E-report.md](R19-E-report.md) | ADV-01, ADV-02, ABT-01 to 04, BBS-01, BBS-02, BR-02, BR-03, the bridge's network paths and its file-existence answer; BR-01 a false positive |
| R19-H Hotloader and motion | [R19-H-report.md](R19-H-report.md) | H4 (L-01), L-02 to L-09, both motion misses, MH-01, MH-02, MH-04 to MH-06, tooling F-03; MH-03 a false positive |
| R19-G glass and companion | [R19-G-report.md](R19-G-report.md) | GL-01, the `sprp` and leaf-walk misses, glass F-01, F-02, companion F-03; companion F-04 by design |
| R19-T tooling and CI | [R19-T-report.md](R19-T-report.md) | M1, F-01, F-04, F-05, F-08, F-09, both misses; F-07 by design (below); F-06 a false positive |

## Integration (Claude)

Changes beyond the parts' own commits:
- **F-07 reverted to its old order, by design.** R19-T moved the package workflow's deletion of the older
  `rtx-package` artifact after the new upload. Actions storage is 2 GB, about 1.2 GB was in use, and a
  package is about 0.84 GB, so the release run's upload would fail. The workflow and `tools/ci/README.md`
  now say why the order is deliberate.
- **RTX Water's patches go into the modules cache key** (`tools/ci/cache_key.py`), which R19-X pointed out.
- **`build_hotloader.ps1` resolves relative folders** where it starts, which R19-H pointed out. The workflow
  passes absolute ones, so releases were not affected.
- **The bridge's network paths.** R19-X found the material editor's bridge has the same class of problem
  as H3: it resolved a texture source before its root check. R19-E fixed it, and then also closed the
  file-existence answer for paths outside the game.
- **Patch 0033's author.** The plan gave the fork commit's author an address that is not the fork's git
  identity. The commit's author was corrected (`248fa6ee` became `51cf1b8b`, the same tree) and the patch
  exported again. `runtime/base.json` records that the stored `d3d9.dll` was built from `248fa6ee`. Before
  `main`, the unpushed R19 history was rewritten so that no commit carries that address.
- **The shared docs** were written from the parts' proposals: CHANGELOG, the decision index, RESEARCH,
  TESTING, ON_DISK_LAYOUT and the root README.

## Tests

- **Each part's own tests**, listed in its report. Each new test fails against the code before its fix.
- **`tools\test.ps1 -Config Release` on the final `r19-int` tree:**
  - CTest 27/27;
  - tools 622, gmapack 29 and Steam 26 Python tests;
  - repository conventions OK.
- **`python -I tools\inputs.py verify`** with R19-T's stricter rules: 11 parts, 0 problems.
- **The package, built from `r19-int`:** `gmod-rtx-remix-0.0.0-dev.20261105231040+ad5cf8e8`, 1,814,982,358
  bytes, checked by its own `nlctl`.

## In-game checks (PoC)

These are the sessions `out/r19/r19_session.py` runs under the shared PoC lock. It installs loader 0.14.0
with the package allowed, runs an RTX session on gm_construct with the checks and R18's sky probe, then a
`-nonativeloader` start. Afterwards it puts the PoC's `client.vdf` and `config.json` back byte for byte.

| Check | Result |
|---|---|
| Deployment and activation | `status.json` reports loader 0.14.0 and "active". The session notes include "RTX session marker held until the game exits". The Hotloader's new natives load. 0 Lua errors in the RTX session. |
| Render guard (proxy F-02) | Installed in the RTX start (`early`). The marker is gone after the quit. In the `-nonativeloader` start right after it, `status.json` is unchanged and still says "active", yet the guard is `nil` and there is no marker. GMod's `file.Exists` does not see the marker while the loader holds it, but `file.Find` does: the guard checks both. |
| ToPBR (H3) | `SetOutputDirectory` refuses `\\127.0.0.1\...`, `..\...` and `C:\...` and keeps `~gmod_topbr\textures`. With `rtx_topbr_enabled 0`, `SetEnabled(true)` leaves it off. |
| Remix options (H3) | `RemixConfig.SetConfigVariable("rtx.nsight.graphicsCaptureOutputDir", ...)` is refused. |
| Material editor bridge | `Capabilities().ddsImport` is true. |
| Eye-white cache (companion F-03) | A foreign `notes.vtf` in the cache folder is still there after the session. |
| DDS readers (H1) | No `Corrupted DDS`, `DDS file is shorter` or GLI-fallback lines in the Remix log. The package's mods and ToPBR's textures load. |
| Sky | Partly cloudy by day, toward the sun, away, overhead and west: cumulus with cirrus. Overcast: a closed grey deck. Partly cloudy at night: the night sky. All as in R18. |

**Cost at 3840x2160.** R18's probe and method (`out/r18/sky_session.py`) were run on a quiet machine.
The R19 package was measured first, then the published R18 package in a second session, with the same
spawn, states and views. Each figure is the average over about a second of frames before the shot:

| View | R19 (ms) | R18 (ms) |
|---|---|---|
| Partly cloudy 15 h: sun, away, high, west | 11.20, 11.21, 11.43, 11.76 | 11.15, 11.44, 11.16, 11.88 |
| Overcast 14.5 h: sun, away, high, west | 10.83, 12.41, 11.70, 12.56 | 10.77, 13.05, 12.00, 13.11 |
| Partly cloudy 22.5 h: high, away | 11.19, 11.67 | 10.93, 12.22 |
| Average | 11.60 | 11.77 |

The middle deck's new probes (F-04) and moon-shadow taps (F-05) cost nothing measurable. Overcast looking
away from the sun and toward the horizon is where grazing rays take the most probes, and it is no slower.

## Release

**Published.**
- **Merged and pushed.** `r19-int` was merged into `main` as `3b0bed6` and pushed (`30a9741..3b0bed6`).
  - The post-merge hook built the development package here and uploaded it to item 3829070317 as
    0.0.0-dev.20261105231916+ad5cf8e8.
  - The pre-push hook found the same inputs and did nothing.
  - CI on `main` passed (run 42128850015).
- **The GitHub release.** The annotated tag `v0.14.0` on `3b0bed6` made the GitHub release
  [Native loader v0.14.0](https://github.com/SheepyLord/-Gmod-Workshop-RTX-Remix/releases/tag/v0.14.0)
  (tag build 42130227170). It has `gmod-native-loader-0.14.0+3b0bed6a.zip` (742,854 bytes) and its
  `-symbols` zip. Its notes were then rewritten for players.
- **The release package, built on GitHub.** Claude started the package workflow on `main` at `3b0bed6`,
  as the user allowed for this release (run 42130241622).
  - It compiled 13 native binaries and fetched 41; none came from `packages/`.
  - The `.gma` is 1,814,986,442 bytes, SHA-256 `12c404dc...`.
  - Its `d3d9.dll` has SHA-256 `b311f0d9...` and reports `remix-main+b2129b8e`. The stored one, which
    the PoC tested, is `34287de8...`, built here from the same patches.
- **On the Workshop.** `publish_workshop.py --from-ci` waited for the run and checked the `.gma` against
  the run's `SHA256SUMS.txt`. It then uploaded exactly that file to item 3829070317 as
  0.0.0-dev.20261106004558+ad5cf8e8 (2026-11-06 00:50 UTC).
  - Its inputs fingerprint is the development build's (`ad5cf8e8`); only the native binaries differ.

**Checked in the field.** Before each start, no other lab, game or PoC lock was active.
`tools\steam\verify_install.py` found the field install intact before and after; only the user's
`autoexec.cfg` differs. The field's `cfg/client.vdf` was saved first and is byte-identical afterwards;
`config.cfg` was put back by the session.

| Start | Result |
|---|---|
| Loader 0.14.0 with the development package (`out\r19field\`) | The `winmm.dll` from the GitHub release's zip (SHA-256 `256f245f...`) replaced loader 0.13.0, which is kept in `out\r19field\winmm.dll.0.13.0` in the main checkout. The first start deployed 0.0.0-dev.20261105231916+ad5cf8e8 and activated it, with the render guard installed early. The R19 checks passed as in the PoC (ToPBR, the Remix option, the bridge), with no Lua error. The sky probe's views took 7.74-8.32 ms (average 7.95), and the game quit normally. |
| The release package (`out\r19release\`) | Steam had fetched the updated item within a minute of the upload, and the `.gma` on disk has GitHub's SHA-256. One start deployed and activated 0.0.0-dev.20261106004558+ad5cf8e8. All 207 runtime files match the run's hash report, `d3d9.dll` included. The R19 checks passed again, with no Lua error and no complaint from the DDS readers. The views took 7.78-8.67 ms (average 7.98), and the game quit normally. |

- **ToPBR's folder stays the player's.** 85 of the 931 root files differ from the report. All are in
  ToPBR's output folder `rtx-remix/mods/~gmod_topbr`, which is `create-only`. So the textures ToPBR made
  in this game since 2026-10-29, and its rewritten `materials.usda`, were kept; the loader's status notes
  say so.
- **The Remix log's 70 `err:` lines are the same** as in R18's field run, line for line. They are:
  - 28 shader-model notices;
  - one disposal note;
  - 39 textures that the user's own `Poolday` mod names but does not have;
  - two 11059x8847 textures in the user's `ai_pbr` mod, too big for the streaming staging memory and
    uploaded at once instead.
- **The session marker check** reads FAIL as in the PoC: `file.Exists` does not see the held marker, and
  the guard's `file.Find` does.

## Open issues

- **Oversized and volume textures.** A replacement texture larger than the GPU can create, or a volume
  texture, still fails when its bigger mips stream in (R19-R). It is not memory corruption. The choice
  between refusing such textures and capping their mips is left for later.
- **What a server can still do** (ADR 0112): turn on the player's own Lua convars, call the manual
  game-map actions, and read the install path through `GetOutputDirectory`.
- **MH-02's limit.** Within one Lua state, no caller's identity can be proven. Keying on the chunk name stops
  label reuse, but not deliberate impersonation.
- **MH-01 narrows static props too.** Files outside the model's folder (and the tex and textures folders near
  it) are no longer read, and a model that keeps textures in another sibling folder loses them, with a
  warning for each.
- **One compressed lump.** A single compressed glass map lump is still decoded in one call, so a crafted map
  can hold shutdown for an estimated 1-2 s (R19-G).
- **Actions storage.** The per-push build bundles fill the 2 GB in about two weeks at the current pace.
  R19-T proposes `retention-days: 7`; that is the user's call. After the release the user chose two
  days for every artifact, the loader's bundle included
  ([ADR 0113](../decisions/0113-every-actions-artifact-expires-after-two-days.md)). At the user's word
  the 152 artifacts uploaded before that (1,222 MiB, the release's package among them) were deleted the
  same day; one bundle with the two-day expiry remained.
