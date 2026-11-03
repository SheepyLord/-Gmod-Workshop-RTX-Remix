# R12-B report: renamed game PBR and texture-scoped choices

[Brief](R12-B-game-pbr-matching.md); [ADR 0095](../decisions/0095-texture-features-and-imported-pbr-overrides.md).

Completed locally on `r12-pbr` / fixes `codex/r12-pbr`: feature matching, texture-scoped choices,
native/Lua/Release gates, the two-character source-hidden PoC and the final indexed editor smoke.
The PoC is restored and its exclusive lock released. Nothing is pushed, merged or published.

## Matching

Canonical `_D` pairings remain first. Renamed bases compare spatial edges of their UV atlas against
supported normal/packed families at identical normalized coordinates. Aspect, island outlines and
internal boundaries contribute; no rotation/translation/warping is searched. A small English/Chinese
vocabulary adds at most .08 after spatial evidence. Accept only correlation >= .28, supported score
>= .36 and runner-up margin >= .12; weak/flat/ambiguous/incomplete cases abstain. Every decision logs
the base, family, score, margin, feature and reason. The converter retains the original PMX skin,
face and eye masks. Content keys now include semantic channel roles and layout as well as bytes.

Worker-local discovery retains at most eight folder descriptors. Each folder has bounds of 4096
entries, depth six, 64 family stems, 96 feature decodes, 256 MiB feature inputs and 256 million source
pixels. Descriptors are at most 128 pixels on their long edge; original image and per-file bounds
remain 4096 squared / 64 MiB. Clear/restart observes source edits. No user source is written.

The standalone SDK-free `tests/game_match_probe.cpp` executes production `Discover`, reporting both
ordinary and names-hidden decisions. The corpus has **1,133 distinct folder/base pairs from 121 PMX
sources** under `E:/G/Upload`; repeated model variants with the same folder/base are deduplicated.
The **259** exact-stem positive pairings provide the reference. Names-hidden results:

| Production layout | Agree | Disagree | Abstain |
|---|---:|---:|---:|
| Wuthering Waves | 38 | 0 | 37 |
| Endfield | 69 | 0 | 59 |
| Silver Palace | 28 | 0 | 28 |
| Total | **135** | **0** | **124** |

This is agreement with canonical names, not independent human ground truth or a guarantee for
unseen atlases. Preserving normal-only Silver families adds 14 canonical references to the earlier
245-reference exploratory run. The final TSV includes the production layout explicitly.

The requested 阿芙2.0 character has 13 bases; its folder's gun/box PMXs bring the probe total to 16.
Clothing maps to Body01_A (**.7301**, margin **.6686**), stockings to Socks01_A (**.6932**, **.6362**),
and hat to Hat01_A (**.6548**, **.4170**). Eye-reflection texture 眼睛2 pairs with Pupil01_A but remains
protected at conversion. Hair/accessories abstain; vocabulary does not rescue weak evidence. Their
families remain available for explicit player selection. Debug base/normal/packed images and every
decision are in `out/r12-b/debug` and `corpus-final.tsv`. No game image/model is committed.

## Manual choices and queue behavior

The RTX menu's Imported game PBR panel, also `rtx_topbr_game_editor`, lists the looked-at hotloader
character's materials, drawn-only thumbnails and states. Choose a discovered family or individual
source-folder files with an explicit game layout, choose none, or return to automatic. The panel
uses bundled add-on i18n and supplies the new phrases for all six supported languages.

Choices persist in a separate atomic `game_overrides.registry` by the **actual live
`mmd/t/<16 hex>` texture identity**. Manual maps outrank fresh automatic discovery and the automatic
registry; none remains none. Returning to automatic removes the choice. Records contain source/base
and selected-map provenance, layout, generator and validated DDS filenames/sizes/digests/constants.
Missing sources need only unchanged DDS and current drawn hashes. Damaged/missing override DDS never
revive automatic maps; unreadable/unknown override data is preserved and suppresses automatic use.
Failed saves retain the prior in-memory and on-disk choice. Changes retract/refresh all observed
aliases, including edits made while game maps are off. The switch, authored-hash guard and runtime
patch 0020 still control publication. The automatic registry format remains unchanged.

`QueueGameMaterial` collects frame hashes before `DrawnIdentity` may call `FindMaterial`. Empty,
zero and excessive hashes never invoke the material resolver. This removes the identified R11-B
eager-load route; R12-C owns total VRAM measurements. Shared identities retain their displayed family
when later jobs reuse the worker cache.

The first Release run caught a new standalone Lua path missing from the guard's exact exemption
list. The final panel is embedded in the already trusted ToPBR driver. No companion/guard exemption
was changed; the 25-test path suite and both Lua harnesses pass. The standalone file was a never
published, uncommitted input addition and was removed before the final import.

## Verification and artifacts

Production native regressions pass with assertions: existing Source/VTF/USD and game channels,
registry/session persistence, and R12 spatial selection/abstention/layouts/path/family bounds,
drawn-before-load ordering, override/none/automatic precedence, current-hash restoration without
source, changed DDS rejection and Windows sharing-violation atomic-save preservation. Registry and
R12 regressions compile with `/W4 /WX`. The actual embedded Lua panel harness covers metadata,
shared identities, family/individual/none/automatic actions, absent metadata and drawn-only thumbnails.

Build: MSVC **14.44.35207**, SDK **10.0.26100.0**, ReleaseWithSymbols x64, rebased R11-B generated
projects and existing pinned dependencies. No dependency was downloaded. DLL/PDB are in
`out/r12-b/module`; the corresponding GPL source, cumulative patch and pins are in
`packages/fixes/licenses/oversized-skinning/autopbr`. All scratch/evidence stays under this worktree's
`out/r12-b` / `out/tmp`.

The final DLL is **5,379,072 bytes**, SHA-256
`716fcf222ee711dd591244a8940c7e704ac2d860fcad8d2db1bf867274b51217`.
Its matching PDB remains beside it. The DLL was imported **once**, through `inputs.py import fixes
--file`; its xz input is **1,041,688 bytes**. The driver is the only other changed indexed input;
no indexed entry was added or removed. Lua-only editor follow-ups did not change/reimport the DLL.
The cumulative GPL patch reconstructs **30** changed files from `7094baf`, after CRLF normalization;
the source/build pins include raw working-tree hashes and the production `.inl`.

`tools/test.ps1 -Config Release` passes: **26 CTests + 555 Python tests** (502 tools, 28 gmapack,
25 Steam; two existing skips), with `All checks passed.` Deep input verification reports **11 parts,
0 problems**. The final indexed combined package validates with `nlctl`; its exact version/digest
and final fixes commit are recorded in `out/r12-b/final-facts.json` and the source pin file.

## PoC, final gate and restoration

The activity gate waited **600 seconds**
at 01:33:26 / 01:38:26 / 01:43:27 UTC, clearing when no field game remained. R12-C then held the shared
PoC lock. R12-B retried after two minutes, acquired it at **01:46:29 UTC**, and saved **191** files plus
the exact prior journal/deployed hashes. Fresh preflights run before launch. The only model source
used for game QA is the **90,739,343-byte copy** under `out/r12-b/source/Alf2`; the user's source stays
read only. Field processes are never focused, sent input or ended; Steam depot files and Remix
`user.conf` are never written.

The successful functional hold followed R12-A's PoC turns: **01:59:07–02:04:20 UTC**. It imported
the supplied PMX from the copy and a second PMX differing only in its model-name string. Their
distinct assets (`f68499a55a4054b2...` / `9111b24fa94a27f0...`) and materials
`mmd/<asset prefix>/clothes_fu_15` share **`mmd/t/4550924997c00f56`**. Both characters appear in
the pinned screenshots and receive the same override. This exercises different model/material
identities with identical texture bytes, rather than two references to one model name.

| Functional stage | Published hashes |
|---|---:|
| Automatic on / game maps off | 3 / 0 |
| Shared packed-only manual override | 3 |
| None for the shared clothing texture | 2 |
| Override after hiding the copied source and clearing | 3 |
| Return to automatic while the source is hidden | 3 |
| Final cleanup | 0 |

The override affects both distinct material names. With the source absent, both report `override`;
returning to automatic makes both `cached`. There are **zero fresh conversions after source hiding**.
The automatic on/restored USD snapshots match byte-for-byte, as do override source-present/missing
USD and the override registry. Six rendered views are retained under
`out/r12-b/accepted-functional/poc/01-alf2`. Temporal/exposure variation means the images are
qualitative evidence, not a pixel-equality claim: per-character on/off RGB MAE is 1.66/1.86, while
the later on/automatic-restored comparison drifts 4.02/4.74. The data/publication equality is exact.
The run exits **0 normally, zero Lua errors and zero device loss**.

Functional restoration matches all **191 snapshot files, 1,875 prior deployed files and 490 prior
library files**, including pre-run SHA-256 values for the library. New test DDS/registry/asset files
are archived under the evidence directory. Existing mod/cache files and user.conf hashes match;
depot verification passes, no PoC process remains, and the exclusive lock is released.

The first one-character attempt was diagnostic: batching exposed only one drawn material name per
texture, so its sharing assertion refused acceptance. It still converted the three intended families
and quit normally. Its restoration helper initially compared Windows keys with POSIX keys and
archived existing cache files; all bytes were retained, normalized/recovered and verified against
the exact snapshot/deployment before releasing the lock. This is recorded under `diagnostic-01`.
Later holds save library SHA-256 values as well as metadata.

The initial editor smoke found the real DForm `ClearControls` compatibility error, then a separate
QA issue: `poc_session.py --hide-hud` installs a timer that removes Derma windows. The first was
fixed in the driver; the second is disabled only in the UI probe. Diagnostic sessions/normal quits
and full restoration are retained under `diagnostic-02-ui` / `diagnostic-03-hud`. The tightened
harness covers the real DForm API, case-insensitive layout conflicts, and the viewport editor.

The final fixes source is commit **`43d40a4ba349e4fdaed05e74333bd90681d30072`**. The indexed editor acceptance run
uses the exact DLL identified above and verifies the selected entity's **35** material records and the actual
**620×680** editor in a **1280×720** viewport, with material thumbnails, current states, candidate
families and individual-file controls. The form selects a drawn material and refreshes row states;
it offers a visible-character selector and uses the cursor-independent eye trace when available.
Known layout conflicts are checked without Windows case sensitivity. The accepted capture is
`out/r12-b/poc/02-indexed-ui/shot-01-editor-panel.png`. After that capture, two small presentation
refinements (dark row labels and family/layout synchronization) pass the final Lua and Release gates.
This run exits **0 normally, zero Lua errors and zero device loss**.

The UI probe's observer camera was initially independent of the player, and the carrier did not
return from the engine's client trace. Calibration/normal-exit/restoration records are retained in
the diagnostic folders. Final QA checks the visible-character selector and its 35 material records
without relying on carrier hitboxes; eye-trace selection remains available when the engine returns it.

Final restoration again matches **192 snapshot files, 1875
deployed files and 490 prior library files**. Existing mod/cache and user.conf
hashes are unchanged; new fixtures are archived, no PoC process remains, and depot verification
passes before lock release. Full restoration facts are in `out/r12-b/restoration.json`.

The indexed combined package is **`0.0.0-dev.20261103034324+d6b9edff`**, **1097 files**,
digest **`bbfbc98af5b0e66b9ccb3287e87767a023cf01c552da593d9c544e20e0619acf`**, validated by the worktree's Release `nlctl`. Package/native source
pins and `final-facts.json` identify the tested DLL and final Lua. The final Release log reports
`All checks passed.` The post-commit hook checks the branch before publication; this branch remains
`r12-pbr`, and no push, merge, tag or publication is performed.

Later shared-PoC retakes also encountered the loader's intentional rollback hold: reusing the same
local package after rolling it back keeps the prior deployment (`held`, zero operations). Those
retakes are diagnostic, not acceptance. The final setup uses a fresh local package version, applies
it offline, and checks the deployed DLL/Lua SHA-256 values before launch. It also snapshots and
temporarily uses the worktree's Release bootstrap, restoring the prior bootstrap afterward. These
preflights prevent testing an older payload left by another milestone or by a rollback hold.

## Follow-up: R12-B2

[Brief](R12-B2-decode-and-masks.md), committed unchanged; ADR 0095's follow-up supersedes the
original decode/mask behavior above. Completed locally, including the final PoC and exact restore.
The fixes commit is **`026708ae03c05ba6a06fc2f74c19493c9618eda5`**. No push, merge or publication is performed.

### Decode and bounded matching

WIC Fant premultiplied transparent PNG RGB when shrinking. The unchanged review executable
reproduces Body01_B's 2048→128 loss: alpha-zero RGB **167.6→0.0**, overall RGB **166.1→3.1**.
The converter now decodes bounded source-size straight RGBA, then independently area-averages
R/G/B/A with integer overlap weights. Every previous image/compressed-input/aspect/pixel bound
remains. Generator, content salt and completion marker advance to **7 / `r12-game-v7`** so
present-source outputs rebuild; registry schemas and validated source-less retention stay intact.

The generated transparent-PNG regression was first run against `43d40a4` and fails at its colour
assertion (`regression-old.log`). The corrected native suite passes, including 7x7→3x3 fractional
weights, pixel budget exhaustion and a 16x16 transparent packed map converted at an 8x8 normal.
The SDK-free generated-PNG check also runs through the loader's normal Release regression.

Known auxiliary data roles LBMask*, AnisoMask*, PromMask*, Specular*, DynAO*, ExpMask* and Caustic*
may vote only for equal nonzero vocabulary groups. Diffuse/emission variants, arbitrary siblings
and the base itself cannot vote. An explicit exported `T_*_D` name conflicting with the selected
family abstains. Core normal/packed evidence and .28/.36/.12 thresholds, with .08 name support,
stay unchanged. Core maps and possible bases get the existing work budget before auxiliaries.
Optional failures never fail the folder; ambiguous/unreadable families are skipped and logged.
Exhausted core scans still fail closed. Winning evidence paths appear in production/probe logs.

### Corpus rerun and review

The retained descriptor has **1,133 distinct folder/base pairs, 121 PMX files and the same 259
canonical references**. Production names-hidden results (agree / disagree / abstain):

| Layout | R12-B | R12-B2 | Change in agreement |
|---|---:|---:|---:|
| Wuthering Waves | 38 / 0 / 37 | 39 / 0 / 36 | +1 |
| Endfield | 69 / 0 / 59 | 75 / 0 / 53 | +6 |
| Silver Palace | 28 / 0 / 28 | 32 / 0 / 24 | +4 |
| Total | **135 / 0 / 124** | **146 / 0 / 113** | **+11** |

This remains agreement with canonical names, not independent ground truth. The optional one-pass
3x3 edge blur was measured: the initial corrected-decode trial changed **148/0/111→167/0/92**,
and hair's supported score .5989→.6648, skin .2375→.3084 (still abstained). Visual review found an
iris/body mismatch, so production remains unblurred. Broad sibling trials also self-voted bases
and crossed exported EyeTrans/Pupil and Hair_02/Hair_01 families; these diagnostic results were
rejected and the final role/self/exported-family guards rerun over the complete corpus.

Every **14** acceptance missing from the original names-visible `corpus-final.tsv` was inspected
beside its actual winning image. No wrong pairing remains among these final additions. The final
TSV is `out/r12-b2/corpus-accepted.tsv`; contact sheets are `contact-accepted/new-00..02.jpg`,
with per-pair notes in `visual-review.json`. Files below are relative PMX texture names; evidence
is the family basename (the TSV retains absolute paths).

| Model folder | New base | Family | Winning evidence | Score / margin |
|---|---|---|---|---:|
| Alf | `Textures/T_AlfDefault_Pupil01_A_D+.png` | `t_alfdefault_pupil01_a` | `T_AlfDefault_Pupil01_A_Caustic.png` | 0.6248 / 0.4444 |
| Alf | `眼睛.png` | `t_alfdefault_pupil01_a` | `T_AlfDefault_Pupil01_A_Caustic.png` | 0.5625 / 0.4335 |
| Alf | `衣饰.png` | `t_alfdefault_body01_b` | `T_AlfDefault_Body01_B_MRA.png` | 0.8602 / 0.7470 |
| Alf | `头发.png` | `t_alfdefault_hair01_a` | `T_AlfDefault_Hair01_A_AnisoMaskPS.png` | 0.5989 / 0.5212 |
| augusta | `tex/T_R2T1AogusitaMd10011Up_D1.1.png` | `t_r2t1aogusitamd10011up` | `T_R2T1AogusitaMd10011Up_N.png` | 0.4127 / 1.4127 |
| camellya | `textures/T_NHT1ChunXinrenDown_Metal.png` | `t_nht1chunxinrendown` | `T_NHT1ChunXinrenDown_N.png` | 0.4652 / 0.4836 |
| Cynthia | `Textures/T_CynthiaDefault_Hair01_A_D1.png` | `t_cynthiadefault_hair01_a` | `T_CynthiaDefault_Hair01_A_PromMask.png` | 0.5716 / 0.4583 |
| fluorite | `Textures/t_actor_bounda_cloth_01_Alpha.png` | `t_actor_bounda_cloth_01` | `T_actor_bounda_cloth_01_P.png` | 0.6970 / 0.6480 |
| iuno | `tex1/Up-Skin.png` | `t_r2t1younuomd10011up` | `T_R2T1YounuoMd10011Up_N.png` | 0.5093 / 0.4952 |
| iuno | `tex1/Up M.png` | `t_r2t1younuomd10011up` | `T_R2T1YounuoMd10011Up_N.png` | 0.5116 / 0.5057 |
| iuno | `tex1/Down-Skin.png` | `t_r2t1younuomd10011down` | `T_R2T1YounuoMd10011Down_N.png` | 0.3842 / 0.4191 |
| sanhua_alt | `textures/Body_Skin.png` | `body` | `Body_N.png` | 0.3867 / 1.3867 |
| the_detective | `Textures/T_MuninDefault_Pupil01_A_D1.png` | `t_munindefault_pupil01_a` | `T_MuninDefault_Pupil01_A_Caustic.png` | 0.4751 / 0.3425 |
| the_detective | `Textures/T_MuninDefault_Body01_A_D1.png` | `t_munindefault_body01_a` | `T_MuninDefault_Body01_A_MRA.png` | 0.7247 / 0.6142 |

Six prior names-visible acceptances now abstain: three explicit exported-family conflicts
(camellya Up03 and two zankou swimsuit sources), two weak-feature cases (camellya Down_Metal,
margherita Suit_D2), and one folder decode-budget case (Gilberta hair_DnoA). These conservative
losses are retained in `summary-accepted.json`. A subset albedo such as camellya's accepted
XinrenDown_Metal has omitted painted regions, but its accessory strip/corner/pleated UV positions
match the selected normal; original PMX masks continue to bound the actual conversion.

### 阿芙2.0: all 16 folder bases

The original character's 13 bases plus the gun/box PMXs give 16 distinct references. The unchanged
copy is `out/r12-b/source/Alf2`; its rerun is `alf-copy.tsv` and matches the corpus decisions.
Eye pairings below remain protected at conversion. Rejected rows show their best candidate's
score/margin, not an accepted family.

| Base | Result | Evidence | Score / margin |
|---|---|---|---:|
| 枪.png | abstain | — | -1.0000 / 0.0000 |
| 枪带.png | abstain | — | -1.0000 / 0.0000 |
| 熔岩.png | abstain | T_AlfDefault_Glass01_A_N.png | 0.1745 / 0.0135 |
| 箱子.png | abstain | T_AlfDefault_Body01_A_MRA.png | 0.0478 / 0.0180 |
| 脸.png | abstain | T_AlfDefault_Body01_A_MRA.png | 0.1081 / 0.0139 |
| 眼睛.png | pupil01_a | T_AlfDefault_Pupil01_A_Caustic.png | 0.5625 / 0.4335 |
| 眼睛1.png | abstain | T_AlfDefault_Pupil01_A_Caustic.png | 0.0781 / 0.0530 |
| 眼睛2.png | pupil01_a | T_AlfDefault_Pupil01_A_N.png | 0.5776 / 0.3687 |
| 眉毛.png | abstain | T_AlfDefault_Skin01_A_N.png | 0.1264 / 0.0107 |
| 表情1.png | abstain | T_AlfDefault_Pupil01_A_N.png | 0.1357 / 0.0841 |
| 皮肤.png | abstain | T_AlfDefault_Skin01_A_N.png | 0.2375 / 0.1936 |
| 丝袜.png | socks01_a | T_AlfDefault_Socks01_A_MRA.png | 0.6907 / 0.6288 |
| 衣服.png | body01_a | T_AlfDefault_Body01_A_MRA.png | 0.7302 / 0.6686 |
| 衣饰.png | body01_b | T_AlfDefault_Body01_B_MRA.png | 0.8602 / 0.7470 |
| 头发.png | hair01_a | T_AlfDefault_Hair01_A_AnisoMaskPS.png | 0.5989 / 0.5212 |
| 头饰.png | hat01_a | T_AlfDefault_Hat01_A_MRA.png | 0.6462 / 0.4455 |

衣饰 is recovered from Body01_B_MRA's real RGB (**.7802 spatial**); hair is recovered from
Hair01_A_AnisoMaskPS (**.5189 spatial**). Both retain .08 name support. The gun's 熔岩 and 眉毛
still abstain. Original PMX masks protect faces/eyes/skin and shared atlas texels as before.

### Real conversion, PoC and restoration

Body01_B's 2048x2048 mean R/G/B is **154.556 / 113.407 / 230.278**; straight RGBA at 128x128 is
**154.561 / 113.404 / 230.281** (alpha-zero RGB mean **167.34**). A production `Convert` check
with the real packed map and a 128 normal validates **16,384** eligible pixels, including
**15,904** under alpha zero, for exact roughness/metallic/AO. The full-resolution copied PMX
also converts 衣饰 (five maps, 822,041 protected texels) and hair (three, 994,094 protected).

Following the user's R12-B2 standing instruction, normally ended field test **PID 52192**,
`GarrysMod/bin/win64/gmod.exe`, `gm_flatgrass`, validation session
`60fac74506e04fadaa8b8ce535ced0a9`, at 04:10:49 UTC. No field console log was read.
The shared PoC lock was free and was exclusively created at **04:12:05 UTC**; no other lock
was removed. The actual low-profile 1280x720, `-multirun`, no-Workshop run starts at 04:13:23 UTC.

The exact final DLL reports **hair=1 / accessory=2** in `automatic` state, with Hair01_A and
Body01_B, and publishes five fallback materials. It captures
`out/r12-b2/poc/01-alf2/shot-01-alf2-hair-and-accessories.png`, quits **normally with exit 0**,
and records **zero Lua errors and no device loss**. The captured rendered character was inspected.
No QA attempt had to be repeated in this follow-up.

All **3,284** snapshot files (**18,895,376,101 bytes**) restore with identical bytes and timestamps,
including the exact pre-run journal and prior native/library/cache content. New QA files are
archived under `after-new`; the old console was moved back without reading its contents. User.conf
hashes are unchanged. Depot verification reports **2,877 OK, zero missing/size/hash/reparse
mismatches**, with the same permitted autoexec user-config difference. No PoC process remains;
the owned lock is released at **04:16:46 UTC**. Facts are in `restoration.json`.

### Delivery and gates

Fixes source commit **`026708ae03c05ba6a06fc2f74c19493c9618eda5`**, branch `codex/r12-pbr`; corresponding source,
`autopbr.patch`, `source-files.json` and `Source.md` reconstruct all **30** changed files from
`7094baf` after CRLF normalization. The source-copy hashes preserve native working-tree bytes.
The final DLL/PDB are retained under `out/r12-b2/module`. DLL: **5,379,072 bytes**, SHA-256
`ce41b8b00abce2b4cdc0d0b04b7a0183c778dd04673abb890354c414503bc496`. It was imported **once** with `tools/inputs.py import fixes --file`; only that indexed
input changed in this follow-up, with no additions/removals; compressed input is **1,054,360 bytes**.

Native decode/game-channel, matching/mask/family/budget, registry and override regressions pass.
The final repository Release gate and package verification are recorded in the final gate paragraph
below. The R12-B2 brief is committed byte-for-byte as supplied (SHA-256
`5d821fc8ef86418703e5537ffd008a18cbccc409a1a5a0733c5ae0e4f24c61b8`).

Final gates: **`tools/test.ps1 -Config Release` passes**, **26 CTests + 555 Python tests**
(502 tools, 28 gmapack, 25 Steam; two existing skips), with `All checks passed.` Deep input
verification reports **11 parts, 0 problems**. The indexed combined package, validated by Release
`nlctl`, is **`0.0.0-dev.20261103042050+8b127c22`**, **1097 files**, digest
`42fc120b5686c932fe84cc3e08160f8186c9fdf76792e8407fbe4eee540c37ec`. Intentional raw GPL CRLF copies pass the whitespace check with
`core.whitespace=cr-at-eol`; source hashes/reconstruction remain unchanged. Both commits carry the
requested Codex co-author line. Nothing is pushed, merged, tagged or published.
