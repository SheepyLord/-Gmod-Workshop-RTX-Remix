# R21-A report: Blood Overhaul resources and their PBR by permission

Branch `r21-blood`, from `r21-int`. Implemented by Codex (gpt-6.1-sol). Code commits:
`9b08506`, `2be91ce`, `18d4c44`, `94e1a49` (the setter-skipping experiment in `d464883`
was reverted after visual QA). Every commit uses SheepyLord's configured identity and
the plan's Codex trailer. Status: **packaging implemented; final Release gate passed; post-clear Lua decal palette visual QA remains open**.

## Built

- The blood part includes the full runtime material/texture selection from the user's `dist/addon`:
  natural/neutral `bo_blood1..8`, stock-name blood1..8/yblood1..6 and subrects, flesh/alienflesh,
  antlion impacts and stains. All selected source bytes stay unchanged. All 177 source DDSs and
  182 XXH64/XXH3 overrides join R20-C's unchanged analytic sprite PBR: **179 DDSs, 186 entries in
  one private layer**, lazy loading, no unused DDS and no missing dependency.
- The private mixer has **26 shapes**, the eight originals first, then eighteen generated shapes,
  at the published world sizes. Red/alien VMTs keep the source bytes; green/worker variants use
  R20-C's recipe. Variety off preserves the requested original shape. All twelve schemes remain.
- Schemes reach the same engine subrect and world/model flesh/alienflesh/antlion materials the
  original add-on recoloured. Snapshot by canonical material name, retaining the original texture
  reference and filename and effective tint. Master off restores those values and disables mixing
  and extra impacts. The original binding calls are retained, including for matching texture names.
  Re-enabling captures a fresh baseline, including changes made by another add-on while disabled.
- Master off does not unmount packaged materials/PBR. Impact off/amount zero restores native
  dispatch. Foreign/Subrect shaders are skipped safely. The distinct deployment folders and the
  exact-path legacy Lua guard keep one mixer and one Blood settings panel. The six menu catalogs
  describe the 26 patterns, permission and off-switch scope.
- R20-C's impact code/budgets are unchanged: 640 particle admissions/s, 512 alive, 42 per event,
  80 events/s; 48 stains/s and 384 per cleanup/clear epoch; 160 ragdoll checks/s and 64 recent
  cross-name entries. There is no new native code, trust change, server damage hook or message.
- Credits and a shipped permission notice name Crunchy, Workshop 2683396098, permission obtained
  by SheepyLord on **2026-11-06**, and the exclusion of his resources/derivatives from MIT. Owned
  code/assets retain MIT. The eighteen generated patterns' AI disclosure and prompts remain.

[ADR 0124](../decisions/0124-blood-overhaul-resources-by-permission.md) supersedes 0118's resource
exclusions and stock-material policy. Accepted R20 reports/decisions remain historical records.
Shared round documents are left to the manager, as R21-plan requires; only the ADR index line was
added there. The Workshop page is unchanged and its credit section remains the user's to update.

## Provenance and size

Schema 2 `packages/blood-overhaul-rtx/licenses/provenance.json` audits **1,477 source-project files**:
437 selected unchanged source files and 1,040 exclusions, each SHA-256/reason, plus generated output
hashes. Original MD5 comparisons identify **68 unchanged Crunchy files and 14 modified originals**;
131 converted/derived PBR files, 180 generated-pattern assets/materials and 44 other authored files
have separate labels. Legacy Lua, the unused old droplet, source/reference images, backups, logs,
archives, previews and development work stay out. The old droplet has no remaining shipped caller.

| Part measurement | Before | After | Added |
|---|---:|---:|---:|
| Indexed files | 261 | 548 | 287 |
| Binaries | 112 | 272 | 160 |
| Uncompressed bytes | 138,668,672 | 365,182,216 | 226,513,544 |
| Compressed binary bytes | 55,523,212 | 109,378,436 | **53,855,224** |
| Total stored bytes | 55,653,940 | 109,677,811 | 54,023,871 |

The **160 new LFS objects total 51.36 MiB**, below the brief's rough 100 MB estimate. Each entered
through `inputs.py import` once, after final asset preparation. Existing R20 binaries were reused;
the four analytic VTF/DDS hashes remain identical. Receipts in worktree `out/r21a/`:
`before-index.json`, `import.log`, `sizes.json`, `lfs-added.json`, `prepared/provenance.json`.

The final indexed build, checked by Release nlctl, has **1,746 files, 2,181,710,619 GMA
bytes**, digest `e50e278fa1a12f2eb4b2c707ed723f6f30c58a1eda672ba06e1ff40220a2196a`. Rebuilding the pre-import resources with the same final controller
and credits gives 1,955,110,719 GMA bytes: **226,599,900 bytes added**. The old resources were
recovered from the baseline archive and checked against all 261 original index hashes; no package
input was reverted. Evidence: `final-package/`, `final-baseline-package/`, their logs and JSON records.
Normal builds need only this repository and its LFS inputs, not the source project or NVTT.

## Final tests and live evidence

All evidence is under this worktree's `out/r21a/`; build binaries/screenshots are not committed.

- **`tools/test.ps1 -Config Release`: passed**, exit 0 (`final-release.log`, `final-checks.json`).
  **27/27 CTests**, **710 Python tests** (29 gmapack, 26 Steam, 655 tools), two existing optional
  skips. The blood suite runs nine Python tests and fifteen production-Lua scenarios with LuaJIT.
- Deep input verification, conventions and i18n pass. Each of six companion catalogs has 508
  complete entries; each bundled add-on catalog has 474. DDS closure, 186 unique hashes, both
  hash kinds, exact selected/generated bytes, original MD5 classifications, prompt/permission
  provenance, analytic coverage, unsafe shader rejection, source forwarding, aliases, restoration,
  palette choices, legacy bootstrap/server delivery and the unchanged impact budgets are covered.
- The alias regression fails before the fix and passes after it (`alias-regression.json`,
  `alias-before.log`, `alias-after.log`). The harness models distinct wrappers sharing one engine
  material and ITexture-style names. Renderer binding behavior is checked by the native visual probes.
- The focused `native-toggle-final/` sequence shows native engine Blood/YellowBlood enabled,
  disabled, blue and restored after blue, with matching texture/tint/hash records. Its normal quit,
  field-settings restoration and depot verification pass. The final coexistence sessions repeat
  all 26-shape/four-family palette values, source-value restoration, native broadcasts, five real weapon
  targets, Physics Blood and stress on the final payload.

| Final session | Frames captured | Blood subrect winner | Peak live / recent / stains | Physics drops / pools |
|---|---:|---|---:|---:|
| `legacy-low-physics-final4` | 23 | `DecalModulate_dx6` | 512 / 627 / 276 | 164 / 9 |
| `legacy-high-physics-final4` | 23 | `LightmappedGeneric_DX6` | 512 / 633 / 275 | 163 / 10 |

Both coexistence runs have Crunchy's extracted subscription and a field-style legacy Blood Overhaul
RTX add-on, plus its legacy Remix mod, present beside the package. Low names are `aaa` Crunchy /
`bbb` legacy; high names are `zzz` Crunchy / `yyy` legacy. Source byte hashes, effective shaders,
textures and native hashes are in each `acceptance.json`; matching package/legacy VMTs are labelled
as both, rather than pretending their identical bytes identify a unique folder. The low case makes
Crunchy's original Subrect/DecalModulate win; the high case makes the modern alpha VMTs win.

All final runs have no Lua errors, one panel/mixer, 26 shapes, twelve schemes, real pistol hits on
citizens, Combine, zombies, antlions and a ragdoll, normal quit, and field settings reapplied before
quit. Physics Blood's drops/pools and stain paths render with empty guard-error/cleanup lists.
The four-second six-impacts-per-frame stress stays within every hard cap. Detailed frame timings
and counts are in the acceptance JSON, not a claim of a general performance benchmark.

The clean supplemental runs (`clean-final6/`, `clean-final7/`) cover the package without duplicate
add-ons. Earlier native grid frames that captured before rendering settled are diagnostic history;
native colour/restore claims use the focused four-state probe and the final coexistence frames.

## Coexistence limit and workaround

When Crunchy's original VMTs win, red/yellow engine blood remains visible under RTX with the new
PBR overrides, including the original texture hashes. Those engine decals retain their natural
colours: the controller skips the modulate shaders and shared Subrect parents. Every private mixer
family still supports all schemes. A safe fix must not change another add-on's shared shader/parent;
use the package's alpha VMTs by disabling the duplicate original add-on for engine-decal schemes.
The field-style RTX copy has the same modern VMT bytes and its legacy mixer is guarded. The part's
README records this workaround. No global runtime setting or user.conf change is needed.

## QA corrections and restoration

The report counts the final automated-check sessions above; their palette views do not constitute
visual acceptance of the open item below. Earlier experiments remain as evidence:

- The preflight-only `clean-final/` refused moving depot-owned settings presets before isolation.
  No game started or depot file moved. A cleanup mistake moved the unread original console; it
  was renamed back without opening it, and all snapshot bytes verified. Later drivers leave that
  directory in place. The original log was never read.
- `clean-final2/` could not capture with the default Python lacking Pillow; it was restored and
  depot-verified. All later captures use the existing rpai Python, with Pillow checked before the
  lock. No dependency was installed into the user's environment.
- The probe uses synchronous writes only for Lua blood convars; native HUD convars use commands.
  It waits for queued clear commands before stamping, traces the actual displacement floor
  (about Z -148 here), and chunks JSON below Source's 4,095-character print limit. Fresh samples
  test each palette; native broadcasts settle before capture. These fix false blank/truncated
  test evidence rather than changing any source texture.
- Snapshot originals are keyed by canonical material name. Texture references/names and tints
  are restored by name before painting the next scheme; master off stops after restoration.
  An optimization skipping matching texture setters failed visual QA and was reverted. The
  original binding recipe remains, even where Lua-reported names match.

Every accepted session created its shared lock exclusively, used `-multirun`, isolated only roots
proved to have no depot entries, saved/restored all affected bytes and video registry values,
preserved user.conf/rtx.conf/dxvk.conf, and released only its own lock. All matching-build depot
verifications return 0. Large generated/snapshot copies were removed only after restoration was
verified; receipts remain. The field/source projects were read only; no other repository changed.
The Physics Blood GMA's whole-archive CRC was bad: only the ignored fixture copy's trailer was
cleared, and its per-file CRCs verified. Original archive hashes are in `fixture-sources.json`.

## Open

- **Open visual QA:** the larger Lua DecalEx palette probes show correct material values but
  blank post-clear palette views. The initial original-shape grid and the separately paced native
  engine four-state sequence render, including blue and restored red/yellow. A smaller palette
  probe, a refresh after clearing and explicit opaque stamp colours did not resolve the
  post-clear Lua views. Do not treat API assertions or captured frame counts as proof that
  these palette views passed. Evidence: `simple-palette-final/`,
  `simple-palette-rebind-final/`, and the final coexistence frames. Runtime changes are outside
  this task's assigned paths; no speculative runtime change was made. The root cause has not been
  established, and this report does not attribute it conclusively to the runtime.
- The original-modulate shader limitation/workaround above is separate and intentional: source
  bytes and shared foreign shader state are preserved.
- Manager review, merge on r21-int/main, shared changelog/roadmap/research updates and publication
  remain the manager's steps. This task has not merged, pushed, tagged, published, started Actions
  or edited the Workshop page. R21-B's Hotloader warning change is separate; old-warning notices
  in this branch's screenshots do not belong to A.
