# R20-E: live upscaling readback

Date: 2026-11-06. Branch/worktree: `r20-native`, `out/worktrees/r20-native`.
Implementer: Codex (gpt-6.1-sol). [Brief](R20-E-upscaling-readback.md), [plan](R20-plan.md),
[ADR 0123](../decisions/0123-live-upscaling-readback.md).

Initial delivery passed its isolated checks. R20-Q subsequently found starvation with the merged
advancing sky; the follow-up below supersedes that initial acceptance for readiness under load.

## Built

- Runtime patch **0040**, runtime branch `codex/r20-native` at **9e7a4d2d** on `51cf1b8b`.
  A reserved runtime-owned game value publishes effective upscaling/frame-generation settings and
  selected-device capabilities as one atomic versioned snapshot. Readiness waits for startup presets
  and callback convergence, becomes false on pending edits and refreshes at every present. Device
  replacement/destruction cannot leak old ready state. Plugin writes to `rtx.runtime.` are rejected.
- The fixes' sixth GPL patch adds `RemixConfig.GetUpscalingState()`, preserving R20-B's six-field
  contract. Missing export/key, API error or malformed data returns `nil`; success allocates fresh
  tables. There is no settings-file read/save or optional interface-tail access. Complete changed
  source is in [upscaling-state](../../packages/fixes/licenses/oversized-skinning/upscaling-state/README.md).
- `tools/ci/pins.json` records the patch and source tree
  **68b5778182983e59c2d5491699cd7f0996bcd0d1**; public/premake ids are unchanged.
- A hash-pinned `pending_patches` record separates the unimported runtime patch from shipped DLL
  provenance. Existing packaged inputs retain their checks; changed/missing/undeclared additions
  fail. All patches participate in build verification; import clears the pending record. This
  supporting checker/doc change is the necessary scope extension beyond the brief's original paths:
  its no-import and passing-gate requirements were otherwise contradictory (ADR 0123).

Implementation commit: **1a299f8**, with the required co-author trailer. No R20-B file changed.

## Builds and automated checks

Evidence is under this worktree's ignored **`out/r20e/`**.

| Check | Result/evidence |
|---|---|
| Runtime `build_runtime.ps1 -NoImport` | Pass, `runtime-build-final.log`; source/dependency verification and two compile passes |
| Pinned `build_modules.ps1 -Only fixes` | Pass, `module-build-short.log`, `built/provenance-modules.json` |
| Native publisher/reader tests | Pass, `native-tests.log`; optimized patch-derived tests also run in the Release gate |
| Release loader/CTest | Pass, 27/27, `loader-build.log` |
| First full `tools/test.ps1 -Config Release` | Pass, 27 CTest + 687 Python tests (632 tools, 29 gmapack, 26 steam), `release-tests-first.log` |
| Final `tools/test.ps1 -Config Release` after import | Pass, 27 CTest + 687 Python tests; `release-tests-final.log` |
| Imported package inputs | Pass, `fixes-verify.log`: deep verification, 11 parts, zero problems; `module-import.log`: exactly one file stored |
| Architecture/exports | Pass, `binaries.json`: x64, existing game-value exports and module entry points |

The publisher regression includes readiness, failed callback convergence, reserved writes, all enums,
device lifecycle and 100,000 concurrent publications. The reader checks every enum/capability
combination, future versions, malformed/missing values, errors, oversized lengths and unterminated
buffers. Provenance tests cover valid pending additions and attempted exemptions of shipped inputs.

| Binary | Bytes | SHA-256 |
|---|---:|---|
| Local runtime `d3d9.dll` | 417,077,248 | `122caf0bcc58fcb732ef680a1224489fca575d70a6eb1464b0cb122a987d2b82` |
| New fixes module | 5,515,264 | `53da14f9269f042869510fe8be56b8b055263acd7c80a54d3e6178dbbfa94e73` |

The direct module build hit pinned premake's known `!` path bug. The successful unchanged build
script ran through temporary `subst W:` into this worktree's `out`, with `/MP2`; the alias was
removed. The failed attempt's 28 task-created intermediates at the malformed sibling path were
identified by their unique task path and creation times, then moved back under
`out/r20e/failed-premake-intermediates`. `premake-path-recovery.json` records the checked move;
no unrelated sibling files were moved.

## PoC acceptance

The task acquired its own exclusive lock after R20-A released it, snapshotted before changes, and
held it for about five minutes. `poc/session.json`, `poc/validation.json` and each run's console,
Remix log, `modules.json`, loader reports and screenshot are the evidence. The separate probe and
driver remain under `out/r20e`; no R20-B Lua file was changed or injected.

- **Live runtime + new module (`poc/live`).** Selected GPU: **NVIDIA GeForce RTX 5090**.
  `dlss_supported`, `dlss_frame_generation_supported` and `fsr_frame_generation_supported` are all
  **true**. The first Lua call after map load was ready with upscaler 1 / FG 0. The runtime log
  records startup pending `1 0 0 0 0 0 0` at **04:01:49.660**, then presets resolved
  `1 1 1 0 1 1 1` at **04:01:52.054**. The publisher unit test independently reads the unready
  startup value; Lua initializes after this preset phase.
- Each in-memory edit produced **ready false**, then **ready true** with the requested effective
  values: off **0/0**, TAAU **3/0**, DLSS **1/0**, DLSS-G **1/1**, FSR 3 FG **3/2**, original **1/0**.
  Capabilities stayed unchanged. Mutating a returned table did not affect the next one. The probe
  printed `R20E_FRESH_TABLE_PASS` and `R20E_PASS`.
- **Older packaged runtime + new module (`poc/old-runtime`).** The actual native function returned
  `nil`, printing `R20E_OLD_RUNTIME_NIL`; no injected snapshot or stub was used.
- Both sessions exited **0**, `normal_quit: true`, `lua_shots_done: true`, shared field settings
  `restored`; **zero Lua errors and no device loss**. `user.conf` was absent before and after both
  runs, including the runtime trees; it was never created or written. Per-run checks are
  `poc/user-conf-live.json` and `poc/user-conf-old-runtime.json`.
- **Exact restoration passed; lock released.** `poc/restoration.json` checks **4,022** files by
  content and timestamp with no differences; `poc/snapshot/rollback.json` is **clean**. Original
  console bytes were backed up/restored without reading their text; only these two sessions' console
  output was inspected. No field game was launched or ended.

The PoC is stock at its original depot revisions; the field now names newer ones. Real cached
manifests **4001/7488132547021413298** and **4002/7341198560151933050** verify **2,877** stock files,
**7,279,873,012 bytes**, both before and after (`poc/depot-before-old.json`, `poc/depot-after.json`).
Only the same permitted `autoexec.cfg` user-config difference is reported. The temporary restoration
wrapper selects those verified real manifests for the normal snapshot tool's protection and checks;
it does not fake a result or rewrite any Steam file. `poc/restoration-depots.json` records why.
Full addon/data/settings trees were snapshotted too, so ordinary startup writes are restored exactly.

After acceptance, `tools/inputs.py import` stored the module **once**, changing only its xz input
and `packages/fixes/files.json`; deep verification passed. The runtime DLL was **not imported**.

## Follow-up after integration QA

2026-11-06: Q's real timer reads were ready only 14/79 and 10/120 times with normal sky writers,
versus 140/140 while unrelated writes were deferred. The original E unit test did not exercise
`markDirty` with continuous unrelated writers, and its PoC fixture did not contain the merged
advancing-clock defaults. Its success did not establish that case.

The corrected single patch 0040 registers **19 actual option objects** on `RtxInitializer` and
passes each dirty object's address to the store. Only a registered address invalidates readiness;
sky/weather/effect/category edits cannot reset it. The list covers selectors, graphics/upscaling
presets and their upscaling/FG inputs/outputs; lighting outputs of graphics presets are unrelated.
No option-name matching or Lua workaround is used. Publication locking is unchanged. Failed
convergence immediately clears readiness and remains latched until device recreation.

The new SDK-linked runtime unit target passes **20,100** unrelated writes through real
`RtxOption::readOption`, with intervening reads, writes after resolution/before present, dependent
selector/preset callbacks and a failing resolver. Its inputs are controlled test options; the live
case below uses the actual merged companion. The SDK-free unit adds 5,000 unrelated notifications.
Evidence is separate from the original run, under **`out/r20e-followup/`**: `unit-tests.log`,
`portable-tests.log`, `aggregate-native-tests.log`. The amended ADR is additive; its original
decision text remains intact.

The runtime is re-exported as one 0040 commit **d9aba9be**, directly on **51cf1b8b**, authored and
committed as SheepyLord with the requested Codex trailer. Patch SHA-256:
`1b44ea9bce85fd4da91597ae6aa0d5191d015833e39deb762a5a35f390ade2a5` (updated in `pending_patches`).
`runtime-build-final.log` records the passing source/dependency verification and two-pass
`build_runtime.ps1 -NoImport` build. Test DLL: **417,078,272 bytes**, SHA-256
`7fb71c9e745949df43750ff6d3f57cc379086aede87521778becd29510ce9ab6`. Neither DLL was imported again.

**Merged-companion PoC proof passes.** `package-overlay.json` records extraction of Q's actual
merged package, changing only its local runtime DLL and manifest index/test version. The sky source
retains its indexed hash. Q's installer copies its already-built **0.15.0** loader into the PoC;
Q's source/build outputs were only read. The local test runtime is R19 plus corrected
0040; the combined R20 runtime remains the lead's build/import job.

The real native getter is sampled every .02 s, with sky **on**, time passing **on**, a **20-minute
day** and normal .02 s sky updates. An observational setter wrapper forwards every call unchanged
and counts writes; it never defers a write, pauses the sky or fabricates a getter result. The
selected GPU is RTX 5090 and all three support flags remain true.

| Steady phase | Ready / total timer reads | Pending / missing / wrong | Ready ratio |
|---|---:|---:|---:|
| Original 1/0, at least 30 seconds | 1,500 / 1,500 | 0 / 0 / 0 | 100% |
| Off 0/0, at least 10 seconds | 507 / 507 | 0 / 0 / 0 | 100% |
| Both on 1/1, at least 30 seconds | 1,505 / 1,505 | 0 / 0 / 0 | 100% |

Across **71.31 seconds**, there are **27,757** observed sky writes, including **3,517** sun-elevation
writes (about 49.3/s over the entire interval); sun elevation moves **50.981 to 34.915**. There are
**zero unrelated ready-to-pending transitions**. Each selector request immediately reads unready,
then resolves to actual **0/0** or **1/1**. Including those genuine transitions, the timer records
**3,514 ready / 1 pending / 0 missing**: **99.97%** ready, with no incorrect ready values. Original
**1/0** is restored in memory. Receipt: `acceptance.json`, with the raw object and phase counts;
copied session logs/reports/modules/screenshot are in `poc/sky-readiness/game/`.

The game exits **0**, `normal_quit` and `lua_shots_done` true, field/cloud settings restored, no Lua
errors or device loss. The snapshot strategy reuses Q's move-and-restore isolation: **4,200** original
files' hashes/timestamps and the video registry match, zero differences; lock held **3.27 minutes**
and released (`poc/restoration.json`). It preserves Q's refreshed GMod build **26439081**.
`poc-after.json` verifies **2,877** stock files / **7,282,813,551 bytes** against the field's current
manifests, with only the pre-existing permitted `autoexec.cfg` difference. No `user.conf` was saved
or created, no stock file was rewritten, and no field game was launched or ended.

The first full Release run passed all native tests but hit the existing parity test's **20 GiB free
disk reserve** (14 GiB remained after the separate runtime unit build). This was not bypassed:
NTFS compression of this task's generated unit/Release build directories retained their contents
and test receipts, recovering enough space for the normal gate. Compaction receipts are
`build-compaction.log` and `release-build-compaction.log`. The normal final
**`tools/test.ps1 -Config Release` passes, exit 0**: **27 CTests and 687 Python tests** (632 tools,
29 gmapack, 26 Steam; two existing optional-environment skips), ending `All checks passed.`
Receipt: `release-tests-final.log`. The two dedicated runtime unit tests also pass separately.
Follow-up implementation commit: **26cdf43**. The final evidence commit follows it, with the same
configured SheepyLord identity and requested Codex trailer.

## Open

The combined R20 runtime build/import belongs to integration; the stored `d3d9.dll` and its packaged
provenance remain unchanged. Patch 0040 is explicitly pending in `runtime/base.json`. R20-B's
unchanged consumer can then use it; combined hint/field QA belongs to R20 integration. Non-5090
hardware was covered by enum/capability unit cases, not physical-device runs.
No E follow-up implementation or required check remains open. Claude still owns the combined R20
runtime build/import and the resumed R20-Q acceptance matrix; the broader integration findings are
not declared resolved by this narrowly scoped fix. No push, merge, tag, Workshop action or GitHub
workflow was run.
