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
