# R11-B report: cached imported game maps

[Brief](R11-B-cached-game-maps.md); [ADR 0093](../decisions/0093-cached-imported-game-materials.md).

Completed locally on `r11-cache`, including the Release gate, package import and PoC restoration.

## Implementation

The fixes' worker writes `game_materials.registry` beside ToPBR's textures. Successful conversions
record the actual live hotloader base texture (`mmd/t/<16 hex>`), observed hashes, four published DDS
channels with byte counts/content digests, constants, record version and generator provenance.
Atomic writes preserve pre-existing or subsequently edited registry bytes. A missing/unreadable
source can restore only a matching texture with valid unchanged DDS, using current live hashes.
Readable sources still run today's converter. Missing/invalid DDS records are pruned; unknown schema
files remain intact without reuse. Work and data bounds remain explicit.

Lua queues loaded materials without source/base metadata. `rtx_topbr_clear` requeues live materials
while retaining records/DDS. Generator updates do not expire source-less records; the independent
minimum record version can retire demonstrated bad records. The setting, protected faces/eyes,
authored-hash guard and runtime patch 0020 remain in force. No old hashes or filenames are guessed.

Files: `game_registry.h`, `to_pbr.cpp/.h`, the small generator-provenance declaration in `game_pbr.h`,
the shared publication selector in `fallback_guard.h`, the ToPBR Lua driver, native/Lua regressions,
and the packaged GPL source/patch/pins. No runtime, loader, glass, companion or other part was edited.

## Source and DLL

- Fixes branch `codex/r11-autopbr`: `6e33b90fd705e4f5185b78e3f80a74232ff0f503` on the supplied `1679a99`.
- MSVC 14.44.35207 / Windows SDK 10.0.26100.0, ReleaseWithSymbols x64, prepared R11-A dependencies.
  Projects/intermediates/output rebased under this worktree's `out/r11-b`; no dependencies downloaded.
- DLL: **5,139,456 bytes**, SHA-256
  `f1cf17478cb46f08a38ca997104a7ddd50d3463e026243ce8183e301d2c6fa43`.
  DLL and matching PDB remain in `out/r11-b/module`.
- The complete GPL source copy and cumulative patch reconstruct all 22 changed files from `7094baf`
  after CRLF normalization. Raw built-source hashes are recorded separately. See
  [Source.md](../../packages/fixes/licenses/oversized-skinning/autopbr/Source.md).

## Validation and PoC

The standalone production registry/selector regression passes with assertions and `/W4 /WX`:
atomic roundtrip/failure, preserved edits, identity/current hashes, missing/truncated/same-size-edited
DDS, input/path/version bounds, retained generator provenance, source refresh/rejection, setting off
and authored exclusion. The Lua harness passes without source/base metadata and across clear/requeue.
Existing production Source/VTF/USD and game-channel regressions pass. The loader build passes 26/26 CTests.

`tools/test.ps1 -Config Release` passes: **26 CTests and 554 Python tests** (501 tools, 28 gmapack,
25 Steam; two existing skips), with `All checks passed.` The indexed-input deep verification reports
`11 parts checked, 0 problems`.

Alf was imported from a **copy** of `E:/G/Upload/Alf` under `out/r11-b/source/Alf` (532 files,
3,562,938,076 bytes). The user library was read only. A local unindexed package allows QA before the
one final DLL import. `02-final-source` quits normally with zero Lua errors: seven published hashes
on, zero off, seven restored, seven after clear, and seven with source metadata removed in memory.
The copy was then renamed to `Alf.source-hidden` between sessions, leaving its recorded source path
unchanged. `03-missing-source` restores the same hashes with byte-identical USD and registry.

The final pinned pair is `04-low-source` / `05-low-missing`, with a rename between them. Both exit
normally (0), with zero Lua errors/device loss. Each publishes **7 on / 0 off / 7 restored**. The
missing-source run logs **zero** fresh game conversions and **seven** cached restorations. Their
camera origin and render bounds match exactly. All material values/paths and registry bytes match:
USD **6,574 bytes**, SHA-256 `97a0f5457f27c12bc3f0ffec493686528f78f4e203d42f7669e54cd48763083c`;
registry **1,879 bytes**, SHA-256 `615a9d85017eeef580f7c32d4f5de116979c1a16bbb5979456910dd614c881fe`.

| Pinned view, byte RGB MAE in x=480..800 / y=125..580 | Source present | Source absent |
|---|---:|---:|
| On versus off | 3.669 | 4.162 |
| On repeat | 1.152 | 1.168 |
| Off repeat | .960 | .967 |

Source-on versus cached-on is 1.799; the two restored frames differ by 1.332. The screenshots show
the same cloth/hair/metal/emission appearance, with temporal denoising/exposure drift. Original full
on/off/repeat images and `character-metrics.json` remain under `out/r11-b/poc` and `out/r11-b`.

The exploratory `01-source` reached those functional states but failed with `VK_ERROR_DEVICE_LOST`
after returning the camera at the end. `03-missing-source` later hit device loss after its clear/requeue
check, with a reported 8.65 GB budget, 7.86 GB usage and micromap allocation denials. These remain
diagnostic evidence, not successful rendered acceptance. `02-final-source` on medium exits normally;
the final pinned comparison uses the low PoC profile, a 30 fps cap and a fixed camera through quit.
The ordinary hotloader spawn uses the player's eye trace rather than the requested position, so both
final views pin the player's location/angles and suppress movement in the PoC only.
No independently running field process was focused, sent input, or ended.

Evidence: `out/r11-b` (build/native tests/source reconstruction, current-run-tagged stage USD/registry,
screenshots and complete session logs). The first diagnostic monitor also saw previous-run console
markers; its source-session snapshots were replaced by a marker-scoped observer before the new
session's first capture. The final pair and all acceptance comparisons use current-run markers.

## Import and restoration

- Imported the **final DLL once**, then the Lua driver separately, each through `inputs.py import
  fixes --file`. Exactly those two indexed entries changed; no entry was removed. The DLL's xz input
  is 1,011,148 bytes. The GPL files, patch, source/build hashes and notes were refreshed alongside them.
- Built the indexed combined package with `--require-nlctl`: 1,090 files, 1,792,628,949 bytes, version
  `0.0.0-dev.20261102222938+b54c1def`, digest `5009f692189db1eb...`. `06-indexed-cleanup` deploys it at
  generation 140, verifies the final DLL and quits normally with zero Lua errors and zero active
  generated materials. The registry/DDS remain intact.
- Restored all **185** original snapshot files byte-for-byte, including local hotloader source and
  approval metadata, keeping changed test bytes under `poc-after` / `poc-after-restored-smoke` first.
  Restored the client settings saved after the probes had returned their original world/game switch
  values (0/1). The loader's original Workshop-only config is exactly
  `bb27c0d8a80658431ba9394d54e1e458603bf38bcddefdbb84a6aa10c19249a1`.
- `07-workshop-restored` deploys the original Workshop package at generation 141, restores the prior
  fixes DLL (`c4833fc1...`), and exits normally with zero Lua errors. Final generated registrations:
  **0**; the validated registry is retained. Depot verification: **2,877 files / 7,279,873,012 bytes OK**,
  zero missing/size/hash/reparse/unverified entries; the one allowed `autoexec.cfg` user configuration
  difference remains. No Remix `user.conf` was written; none is present on the PoC.
- No PoC game remains, and the exclusive lock was released after restoration. The original user
  character folders and the field install were never written. Nothing was pushed, merged or published.

## Field note (Claude)

The field library's five Wuthering Waves and Silver Palace characters (心 twice, 库拉蒂—骑士, 锁暝,
阿芙2.0) were imported from `Desktop` folders that were gone before R11 shipped, so they were never
converted and this registry cannot help them: they need their source once. Their PMX files are not under
`E:\G\Upload`, neither byte for byte (the manifest's `sourceHash` is the PMX's SHA-256) nor by file name.
Of the library's 20 missing sources, 7 do exist byte for byte elsewhere under `E:\G\Upload` (moved or
renamed: Pearl, Ruan Mei, Xingyi, Zankou twice, Furina, March 7th); none of them is a game-PBR character,
so that only matters to the hotloader's Reload.

## Limits

One successful conversion with this registry is necessary. Older DDS without a recorded association
cannot recover a character whose source is already gone; restoring its source once establishes that
association. No game assets are committed. No branch was pushed, merged, tagged or published.
The two retained device-loss runs remain a parallel-session stability limitation; R11-B changes no
runtime memory management and claims acceptance for the completed low-profile pair.

## Review fixes

Claude's review fixes are in fixes commit `cc77daa7a0c4c0d4196637165b0a6662bad145b6`.
Empty/garbage headers, duplicate identities, excess rows and other read failures start empty and
writable, log one damage line, and preserve the exact old bytes through `.before-r11b-<hash>.bak`
on the next save. Only well-formed decimal headers for another version and files over 8 MiB remain
read-only and byte-identical. Staging uses CreateFileW/WriteFile, FlushFileBuffers and CloseHandle
before write-through MoveFileExW; failures remove staging files. Save warnings are session-scoped
across game jobs and worker restarts. ADR 0093's unreadable-file sentence is corrected in place.

Rebuilt ReleaseWithSymbols x64 under `out/r11-b` with the same pinned toolchain/dependencies. New
DLL: **5,147,136 bytes**, SHA-256
`c5ae890e0daf93adf2bec6b8d8e88980510d110bce056ccd874c35947586b2d1`.
The GPL files, cumulative patch and source/build pins reconstruct all 22 changed files from `7094baf`.
Imported this DLL exactly once for the review pass (the authorized second R11-B import); no other
indexed input changed or was removed. Deep input verification: **11 parts, 0 problems**.

The standalone production regression passes with assertions and `/W4 /WX`, including all four
requested damaged fixtures, exact backup bytes, new reload/record/restore, other-version/oversized
preservation and staging cleanup after a real Windows sharing violation. `tools/test.ps1 -Config
Release` passes again: **26 CTests + 554 Python tests**, with the same two existing skips. The
reviewed indexed package validates with `nlctl` (1,090 files; digest `e65390ac0b5ab3b6...`); its
DLL xz is 1,006,816 bytes. Evidence is under `out/r11-b/review`.

The field activity gate cleared at **22:49:33 UTC**: no field `gmod.exe` remained. Fresh preflight
checks before setup and launch also found none, so no waiting interval was necessary. Acquired the
exclusive PoC lock and saved 189 files, including the prior metadata, settings and generated USD/registry.
`08-review-missing` uses the indexed shipped DLL, the still-hidden Alf copy, low profile, 30 fps and
the same fixed camera. It exits **0 normally, zero Lua errors/device loss**, with **seven cached
restorations, zero fresh conversions, 7/0/7 on/off/restored and zero after final cleanup**. Five
screenshots are retained. Actor/camera bounds, hashes, on-state USD and registry match `05-low-missing`
exactly (USD `97a0f545...`, registry `615a9d85...`). Damaged-file recovery was checked in the native
regression; this game run retained the valid registry needed for the source-less restoration proof.

Restored all **189** snapshot files byte-for-byte, archiving six changed files first. The Workshop-only
config remains `bb27c0d8...`. Redeployed the original Workshop package offline with `nlctl apply`
(generation 143; fixes DLL `c4833fc1...`), avoiding an extra game launch. Payload verification reports
only the expected generated `materials.usda` drift; that empty-registration file matches its original
snapshot exactly. Registry/DDS remain retained with **zero active registrations**. Depot verification:
**2,877 files / 7,279,873,012 bytes OK**, zero mismatches and the same one permitted `autoexec.cfg`
user-config difference. No PoC process remains; the lock was released. No Remix `user.conf`, original
character folder or field-install file was written, and no field process was focused, sent input or
ended. Neither branch was pushed, merged or published.

## Second review fixes

Claude's published field check found duplicate conversions for Endfield's shared cloth texture and
new backups of our own USD output at each process restart. Fixes commit
`633fd5e000aca862a8ae58b5c722d678ac4fa053` addresses both. A worker-local, bounded
`GameRegistry::Session` resolves each actual live texture identity once, caching success and no-maps
(including rejected conversions). Later material jobs reuse that result with their own live hashes,
without source probing, conversion, DDS hashing or registry access. Cache clear stops the worker;
worker restart creates a fresh session. Persistent records/DDS remain retained.

`USDA::PublishStagedFile` now recognizes its previous output through a small versioned
`<target>.last-published` size/FNV-1a digest record, read afresh for each publication. It writes the
record through flushed/closed staging and write-through atomic replacement after successful USD
publication. An exact match survives process restart without another backup. Edited/foreign USD
and missing/damaged/stale records still require a byte-verified backup first. Existing backups are
never removed; failed USD replacement cannot advance the record, and failed record replacement
falls back to preservation on the next publication. ADR 0093 gains an additive clarification.

Rebuilt ReleaseWithSymbols x64 under `out/r11-b` with the pinned MSVC/SDK/dependencies. DLL:
**5,167,104 bytes**, SHA-256
`526a6584d4ab68e657b7f1cead25db88beb6cbfa568ad31f92028ddc3345f792`.
The matching PDB remains beside it. Refreshed the GPL files, cumulative patch and source/build pins;
all **23** changed files reconstruct from `7094baf` after CRLF normalization. Imported this DLL
exactly once (the authorized third R11-B import): only `modules/gmcl_RTXFixesBinary_win64.dll`
changed in the input index, nothing removed; its xz is **1,008,800 bytes**.

Native production regressions pass, including `/W4 /WX` for the registry/session test: shared
identity converts once with each caller's current hashes, distinct identities still convert,
no-maps/rejections stay resolved, and a new worker converts again. A hit succeeds with its DDS and
registry temporarily unavailable, proving those paths are not accessed. USD tests publish in
separate child processes, preserving only the foreign original across restart, backing up a
same-size edit and missing/damaged/stale sidecars, and checking failed USD/sidecar replacements
and staging cleanup. Existing Source/VTF and game-channel regressions pass too.

`tools/test.ps1 -Config Release` passes: **26 CTests + 554 Python tests** (501/28/25, the same two
existing skips), `All checks passed.` Deep input verification reports **11 parts, 0 problems**.
The indexed combined package validates with `nlctl`: **1,091 files**, version
`0.0.0-dev.20261102233915+54968393`, digest `2a313fccbb69af31...` (full identity in the package summary).
Evidence: `out/r11-b/second-review` (build, native/Release logs, reconstructed source, import and
input-index checks, package, field activity gate, `poc-result.json` and `restoration.json`).

The activity gate waited **600 seconds**, checking at 23:40:31 / 23:45:31 / 23:50:31 UTC. The first
two checks found the field game busy; the last found no field game. Acquired the exclusive PoC lock
and saved **191** files plus actual hashes of all **1,871** previously deployed files. Both launch
preflights found no field game. `09-second-source` uses the existing Alf copy restored to its source
path, low profile, 30 fps and the pinned camera. It exits **0 normally**, zero Lua errors/device loss,
and logs exactly **seven** `Imported game maps` lines for **seven distinct live identities**,
including only one for the two hair materials sharing `mmd/t/222255a4ff9840e9`. It publishes
**7/0/7** on/off/restored and quits with the seven active. No new materials backup is created.

Renamed only that copy back to `Alf.source-hidden` between runs. `10-second-missing` exits
**0 normally**, zero Lua errors/device loss, with **seven cached restorations, zero fresh conversions,
7/0/7**, then zero after final cleanup. Its complete before/after materials-backup inventories are
identical: **no new backup** across the restart. Both sessions retain five screenshots. Camera and
actor bounds, live hashes and material values/paths match; on-state USD and registry match each other
and the prior accepted pair byte-for-byte (USD **6,574 bytes**, `97a0f545...`; registry **1,879 bytes**,
`615a9d85...`). The captured source/cached views show the same materials.

Restored all **191** snapshot files byte-for-byte and used the loader's **rollback transaction**
(generation **145**) to restore the exact pre-pair deployment, since Steam's Workshop archive had
updated in the meantime. All **1,871** deployed files match their actual pre-pair hashes, including
the original fixes DLL (`c4833fc1...`). The Workshop-only config remains `bb27c0d8...`; generated
registrations are **0**, and the registry/DDS remain retained. Changed QA files and the newly created
publication sidecar were archived under the evidence directory; every existing backup is unchanged.
Depot verification: **2,877 files / 7,279,873,012 bytes OK**, zero missing/size/hash/reparse/unverified
entries, and the same one permitted `autoexec.cfg` configuration difference. No PoC process remains;
the lock was released at the end of restoration (**23:56:44 UTC**). No field-install, original
character-folder, Steam depot or Remix `user.conf` file was written; no field process was ended,
focused or sent input. Neither branch was pushed, merged or published.
