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

## Limits

One successful conversion with this registry is necessary. Older DDS without a recorded association
cannot recover a character whose source is already gone; restoring its source once establishes that
association. No game assets are committed. No branch was pushed, merged, tagged or published.
The two retained device-loss runs remain a parallel-session stability limitation; R11-B changes no
runtime memory management and claims acceptance for the completed low-profile pair.
