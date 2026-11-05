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

(Filled in with the integration's results.)

## In-game checks (PoC)

(Filled in with the session results.)

## Release

(Filled in when published.)

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
  R19-T proposes `retention-days: 7`; that is the user's call.
