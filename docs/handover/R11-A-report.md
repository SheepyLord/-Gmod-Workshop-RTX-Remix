# R11-A report: automatic PBR

**Implementation is complete within the permitted fixes/companion scope; acceptance remains partial.**
The user's unconditional ?real PBR replacements always win? requirement needs a runtime lookup change.
R11-A explicitly cannot edit `runtime/**`. The fixes conservatively suppress known competing hashes,
but cannot synchronize an asynchronous runtime swap. Do not merge/publish this as satisfying that
requirement until Claude supplies that runtime integration. No runtime/loader/glass, field-install,
Steam setting, origin, tag or Workshop item was changed.

## Implementation and defaults

- World ToPBR stays **opt-in**, `rtx_topbr_enabled 0`. Phong uses perceptual GGX roughness, reflection
  masks have a floor, ordinary dark plastic is not inferred to be metal, and zero emission stays zero.
  Commented properties default off. Explicit community PBR channels and unmasked chrome remain.
- The client snapshots one already-tracked material per frame; two worker-prepared VMT slots and
  two decode-ready slots bound the pipeline. All VMT reads, companion probes, image decoding and
  writing are off frame. Worker lifecycle is serialized and no live IMaterial reaches its decode
  thread. Negative material-name results last only for the session.
- DDS keys contain source bytes, generator version and material recipe. Reuse validates the complete
  header/mip payload. USD publication replaces a complete sorted snapshot atomically, supports
  updates/removal, and touches the root layer after change. Disabling actually removes generated
  entries. Existing/edited generated USD is preserved before replacement; invalid DDS is quarantined.
- `rtx_topbr_game_maps 1` is independent, default on, with ?Imported game PBR? in the character/model
  options and English plus six translated catalogs. It reads existing hotloader local source/library
  metadata; no hotloader hook or manifest format change is needed. Original albedo/alpha are retained.
- Game discovery is bounded to the PMX tree and exact stems. It prefers companions beside the base,
  accepts byte-identical duplicate exports, rejects differing ambiguity/rooted/traversal paths, and
  validates normal channels. PMX vertex/index/string/span/UV and raster budgets fail safely.
- Named skin/face/eye texels are protected in shared UV sheets, including overlap precedence. Public
  and soft-copy hotloader materials are excluded from the generic Source path. Faces receive no
  generated material, so R10's original-atlas eye aliases continue operating.

| Family | Applied data | Deliberately retained/fallback |
|---|---|---|
| Wuthering Waves | RG normals, rebuilt Z, DirectX Y; PMX class roughness/metal/normal targets | ID/HM/HET and diffuse alpha are not guessed to be PBR/coverage. No invented emission |
| Endfield | RG normals with green flipped; P red metallic, alpha smoothness ? roughness, **blue AO**; E emission | Hair and named skin/face have their separate safe rules |
| Silver Palace | XYZ DirectX normals, MRA red metallic / green roughness / blue AO; E where referenced | No eye/skin relief or fabricated emitters |

The Endfield channel mapping is supported by a community shader reconstruction, not an official game
specification; normal-Y decisions are measured inferences. Primary links and curl numbers are in
RESEARCH. Authored map values take priority over fallback targets. Fallbacks follow aggressive.json:
cloth .55/2.6, leather .20/2, stockings .30/1.4, hair .28/1.2, metal .12/1/1.6, default .45/1.8.
AO is kept as data rather than baked into painted albedo under path tracing.

Sources decode at most 4096 squared; generated character maps are at most 2048. There are at most
8192 queued Source names, 128 queued game requests and 4096 submitted game materials. New DDS writes
stop at 1 GiB per module session and retain 64 MiB free space. Old cache/edited backups are retained,
not indiscriminately pruned. Unknown binary USD, scan/read failures or exceeded scan bounds suppress
publication. That conservative behavior can disable automatic output for an otherwise valid pack.

## Validation

Native production-code harnesses passed with assertions enabled: bounded/resource/truncated/animated
VTFs, DDS validity, all four format detectors, Exo/GPBR channel extraction, Source roughness/no-darkness
metal, zero emission, complete USD updates/removal, preserved user edits, Unicode-later conflicts and
binary-USD suppression. Game tests cover RG normal reconstruction/Y convention, packed channels,
shared skin, Unicode PMX names, malformed geometry, paths, duplicate companions and image sanity.
The packaged Lua harness covers syntax, diagnostic calls, convar/command collisions, independent
switches, bounded discovery, unresolved-hash retry and one-time submission.

`tools/test.ps1 -Config Release` passed: **26 CTests, 553 Python tests**, two existing expected skips
(28 gmapack, 25 steam, 500 tools). Package-input deep verification reports zero problems. The indexed
combined package builds with nlctl verification. Source reconstruction from 7094baf reproduces all
changed source files. All 2,334 dependency files match pinned objects after checkout line-ending
normalization; 59 omitted build files were restored under the isolated dependency copy.

PoC shots are 1280?720 on this machine's RTX 5090; these numbers are not 4K/8-GB-GPU acceptance.
Baizhi, Akekuri, the detective and Alf were imported through the hotloader, with their sources read
only under E:/G/Upload. The final repeated character views use one frozen character at a time and
acknowledged captures, preserving full frames and original part visibility. No game model/texture is
committed. Earlier trials with a Lua file-order error, overlapping fixtures, premature camera changes,
or trainstation/out-of-map views are retained as diagnostic evidence and excluded from acceptance.

| Character (full-body ROI) | On/off RGB MAE | Off repeat | On repeat |
|---|---:|---:|---:|
| Baizhi | 3.745 | 1.154 | .957 |
| Akekuri | 3.560 | .981 | 1.045 |
| Alf | 3.740 | 1.148 | 1.392 |
| Robin authored pack | 2.046 | 1.121 | 1.244 |

The ROI is x=480..800, y=125..580, byte RGB. The Robin control has temporal/exposure drift; these
pixel differences alone do not prove exact equality. Its authored mod is unmodified, and automatic
conversion neither submits its absent local source nor publishes replacements for its authored hashes.
R10 status remains supported/enabled at 100%, with two selected surfaces applied and two distinct
original-atlas aliases; the controller/material bindings were not changed.

World profiling exposed **23.553 ms** client inspection despite worker decoding. Moving VMT reads and
companion probes to the worker reduced it to **0.830 ms** on Construct with the same 45 emitted
materials. Conversion p99 fell **23.472 ? 9.133 ms** (maximum **30.636 ? 17.278 ms**). Settled medians
were **7.270 off / 7.213 on / 7.374 restored ms**. Final world/deployment rows are below. Native default-on would still be unjustified
while priority is unresolved and real local Exo/GPBR rendered coverage is absent.

A read-only Workshop survey covered **730 GMAs / 21,101 VMTs**, finding MWB and BFT candidates but no
ExoPBR/GPBR material matches. Those two formats have synthetic channel tests; that is not a claim of
real Workshop rendered acceptance.

## Artifacts, branches and evidence

- Main worktree: `r11-autopbr`, phase 1 checkpoint `ee2f4c4`.
- Fixes: `codex/r11-autopbr`, phase 1 `72d53f4`, phase 2 `5ad6f23`, profiling follow-up `1679a99`.
- Final native DLL: **5,060,608 bytes**, SHA-256
  `c4833fc18673ab050aeac7d6c43431908cd9e4d1212dbfce0b5cd88157418a1c`.
  DLL/PDB remain together in `out/worktrees/r11-fixes/out/r11-module`.
- Only the DLL and ToPBR Lua driver changed in the fixes input index. They were imported individually;
  no whole-part/pruning import was performed. Profiling replaced an uncommitted DLL candidate; only
  the final DLL LFS object is committed, and nothing was pushed/uploaded.
- Complete GPL changed files, patch, pins, hashes and rebuild notes are in
  `packages/fixes/licenses/oversized-skinning/autopbr`, inside the already bundled source tree.
- Evidence under this worktree's `out/r11-autopbr`: `verified/characters` and character-metrics.json;
  `world-verified` before metadata preparation, `world-metadata` after; `precedence`; `final-qa`;
  native/game tests, normal-conventions.json, Workshop survey, dependency/source reconstruction and
  release/package logs. Source/render limitations are not hidden by discarded trials.

## Remaining correctness boundary

The common publisher excludes every observed authored hash, whatever the mod folder's ordering, and
retracts late conflicts. However, an authored runtime swap can land before that retraction. A binary
USD or external composed layer cannot be authoritatively interpreted by this scanner either. Claude
needs to make runtime material resolution consider every authored mod before this generated fallback,
including cache invalidation on reload. A folder rename, extra polling or a passing settled screenshot
is not the user's requested guarantee. R11-A did not cross its forbidden runtime path boundary.

Canonical stems/local PMX sources and naming heuristics limit coverage: absent sources, noncanonical
_D1/repainted names, unknown layouts and ambiguous exports remain as before. WuWa's unproven masks
are not exposed as fictitious metallic/emission maps. The detective does not wear the emissive equipment
textures beside its PMX; Alf provides the additional Silver Palace emitter sample.

## Final world measurements

| View | Off median | On median | Restored median | Conversion p99 / max | Max client snapshot |
|---|---:|---:|---:|---:|---:|
| gm_construct | 7.270 | 7.213 | 7.374 | 9.133 / 17.278 | .830 |
| gm_flatgrass | 4.164 | 4.165 | 4.129 | 5.489 / 7.438 | .069 |
| d1_canals_01 | 6.967 | 6.891 | 6.944 | 9.393 / 12.452 | .644 |

All values are ms. Each settled window is ten seconds, conversion is 45 seconds, timing is wall-clock
PostRender, unfocused sleep and the FPS cap are disabled. These medians show no material steady-frame
cost in the tested views. Construct has 45 emitted fallback hashes, retracting to zero on disable;
failed conversions are zero. Canal inspection uses its actual interior spawn, not the rejected G-Man
intro/outside camera. These runs quit normally with zero Lua errors. The one-time decoder/worker
cost can still exceed a frame; it is deliberately off frame.

## Late authored-mod result

The corrected `?R11_authored_later` fixture loaded before the session with an empty valid USD stage.
After automatic conversion it hot-reloaded an overlapping red material for live hash
`C5E74CB23318460D`. Generated output went from four materials to three, and the authored-hash set
from 305 to 306. The overlap disappeared **0.805 s** after the authored file was written.
The subsequent whole-frame screenshots show the authored red atlas rendering instead of automatic
PBR, while the face/eye atlas stays separate. The session exited normally with zero Lua errors;
only this fixture's unchanged owned files were removed afterwards. See `precedence-valid`.

This is settled success with a measured retraction delay, **not** the user's unconditional guarantee.
The first fixture used invalid inline USD and was rejected by the runtime; `precedence` retains that
trial, whose suppression timing is not authored-render acceptance.

The full `--workshop` run mounted 766 of 767 add-ons but stopped responding at the menu before client
Lua/ToPBR started. A normal quit was refused, so only its verified PoC process was stopped. The
session and stop record are retained. Targeted read-only mounts are used for the two available
community examples; full Workshop startup acceptance remains outside the demonstrated result.

## Targeted content and deployment closure

The UGC-path mount succeeded for installed items 2459720887 and 3333148722, followed by a map
reload. Native inspection recognizes Viper's `attachment_oil_filter_can` as **MWB PBR Gen**;
its cube fixture is exercised with world conversion on/off. The Touhou face candidate resolves
to standard Source, so it is not evidence of real BFT support. The targeted final session quits
normally with zero Lua errors and zero failed conversions; its maximum client snapshot is .572 ms.
Direct absolute-path mounts and the first misplaced mount flags were diagnostic trials, not acceptance.

After generated USD/DDS writes, `nlctl rollback` succeeded (generation 132, 22 filesystem changes).
Reinstall from the indexed combined package succeeded (generation 133, 218 changes), loaded the
exact final DLL SHA-256, and exited normally with zero Lua errors. Clearing registrations left
**zero** `mat_` entries; cached images/retained edits remain. The original Workshop-only loader config
was restored byte-for-byte (SHA-256 `bb27c0d8a80658431ba9394d54e1e458603bf38bcddefdbb84a6aa10c19249a1`).
Depot verification reports zero missing, size/hash mismatch, reparse or unverified entries; the one
`userconfig_differs` is the allowed autoexec.cfg user configuration.

Full Workshop startup, real BFT/Exo/GPBR rendered samples, and the unconditional runtime priority
rule therefore remain explicit acceptance limits. The native implementation, channel tests,
translated setting, source/DLL import, indexed package, Release gate and PoC checks above are complete.


The final restored-Workshop smoke test deployed the original Workshop package at generation 134,
then quit normally with zero Lua errors. No PoC game remains, the original configuration bytes match,
and the exclusive R11-A lock was released. Imported QA assets and content-keyed caches remain available
for Claude; there is no active temporary authored fixture or generated material registration.
