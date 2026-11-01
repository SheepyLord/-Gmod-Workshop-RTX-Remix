# R7-B: crash exit report and diagnostics

R7-B is implemented on `r7-crash-diag`, based on `42bd1e9`. Claude retains PoC acceptance
and integration. No Garry's Mod executable was launched: every process test used a copied
synthetic host under this worktree's `out/`. No game install, Steam file/setting, Remix
user.conf, glass code, package input, runtime source or Workshop item was changed. No download,
push, merge or tag was performed. No Remix consent-granting automation variable was set.

## Changes and commits

- `2cb7d7c` — map commit headroom and the content add-on summary.
- `fb68cfe` — external observer, shared classification/archives, seven-language reports and
  previews, unattended policy, tests/docs, and the existing long-path guard-test repair.
- `639dbc6` — restore UTF-8 catalog strings damaged by Windows PowerShell's default
  ASCII pipeline encoding and add before-failing catalog/embedded-message regressions.
  The actual translated strings are now stored directly as UTF-8; no generator is required.

Every task commit ends with the requested Codex co-author trailer. The handover and final
validation notes are committed separately.

1. **Exit report:** one localized native message after an abnormal exit, with a plain reason,
   suggested action, hexadecimal exit code and evidence folder. It supports OOM, device loss,
   allocation failure, CS-thread exception, generic crash and a separately qualified likely-OOM
   inference. Known exception codes receive localized descriptions. JSON is kept inside the
   receipted evidence archive, and the next start reuses the same reason/folder. Clean ends
   make only an end marker, so normal starts stop evicting crash evidence.
2. **Memory warning:** warn strictly below **18 GiB free system commit**, or a **24 GiB total
   commit limit**. Equality is sufficient; a zero limit is unavailable; subtraction saturates.
   **64.0 / 90.6 GiB does not warn.** Reanalysis of 24 usable saved R6 sessions found about
   11.074-16.184 GiB added system commit from bootstrap through map load. Eighteen GiB is a
   conservative reserve above those samples, shared across tiers because their main savings
   are VRAM. All seven messages state the new thresholds and remedies. Measurements and caveats
   are in [RESEARCH](../RESEARCH.md#r7-b-commit-headroom-from-the-saved-r6-runs-2026-11-01)
   and [ADR 0082](../decisions/0082-map-commit-headroom-and-addon-summary.md).
3. **Add-on list:** `gmod-rtx-remix` keeps its full version/hash row. Other deployed packages
   produce one localized enabled-content count, including zero, in both panel and copied text.

## Observer design and why

System32 `rundll32.exe` loads the same `winmm.dll` and calls `NativeLoaderObserveW`; there is
no extracted or separately shipped executable. DllMain recognizes that exact host and returns
before winmm resolution, entry hooking, deployment or worker startup. The game starts the
observer after recording this session and preserving the old log, before loading the runtime.
Readiness has a three-second bound; failure is a diagnostic note rather than an activation veto.

The observer inherits only a restricted game-process handle and a ready event through a handle
allowlist. It checks executable path, PID, process creation time, inherited-handle flag and
parent PID. It waits on the pinned handle, rather than reopening a possibly recycled PID.
It therefore has an independent stack/address space for OOM, fail-fast and stack-overflow
failures, and cannot show our report while Remix's own crash prompt still keeps the game alive.
After reporting it exits; an interactive observer exits when its OK dialog is dismissed.
The bootstrap still imports only KERNEL32; user32 is loaded dynamically after exit.

The observer and next-start collector share `evidence::classify` and bounded archive copying.
Explicit no-memory/commit-limit statuses take priority. Specific fatal logs, GPU crash JSON and
fresh dumps explain generic exits. A generic nonzero exit with no stronger evidence can become
`likely_out_of_memory` only with a sample <=30 seconds old and <=512 MiB free commit. The
snapshot must match this process token; CSV fallback must match the session time window. A
concrete exception keeps its code/classification. Shader `.nvdbg` context alone is not a crash.
Zero exits stay clean unless fresh fatal Remix/crash evidence explains them.

A per-root mutex serializes exit/startup collection. An exact session-marker comparison rejects
changed, duplicate or newer sessions. The observer records its conclusion in the end marker;
the next start neither reclassifies nor duplicates that archive. The report participates in
R6's hash-verified five-archive / 200 MiB retention, preserving original and edited evidence.
See [ADR 0083](../decisions/0083-external-exit-observer-from-the-proxy.md).

`NATIVE_LOADER_EXIT_REPORT=quiet` keeps the report/JSON without our window; `poc_session.py`
forces it. `off` skips observation for unrelated synthetic tests. Neither changes Remix's
consent. Global loader off switches prevent observation. Language priority is explicit
`+gmod_language`, archived `config.cfg`, then Windows locale, with English fallback.

## Claude's PoC checks

After installing this branch's built DLL through the usual reviewed workflow, run one preview
at a time and dismiss it before the next. These previews are read-only and do not launch a game
or fabricate evidence:

```powershell
$dll = 'H:\SteamLibrary\steamapps\common\GarrysMod_PoC\bin\win64\winmm.dll'
$reason = 'out_of_memory'
& "$env:SystemRoot\System32\rundll32.exe" "${dll},NativeLoaderExitPreview" $reason zh-CN
```

Replace `$reason` with each of `out_of_memory`, `likely_out_of_memory`, `device_lost`,
`allocation_failed`, `cs_exception`, `crash`. The optional language is one of `en`, `zh-CN`,
`zh-TW`, `ja`, `ko`, `fr`, `ru`; omit it to select the game/Windows language. A shell inheriting
`quiet` intentionally shows no window. Preview codes are representative: OOM `0xC0000017`,
unknown crash `0xC0000005`, other reasons `1`; the displayed path is the sessions parent.

For actual exit acceptance, confirm `exit observer ready: pid=...` in loader.log, then test a
normal quit and controlled PoC termination with `0xC0000017` / `0xC000012D` / exception statuses.
The real path reads fresh logs/dumps rather than a preview reason. Device-loss simulation needs
the fatal log line or GPU marker. The synthetic test already covers these sources without
memory exhaustion. After an abnormal exit, inspect
`native-loader/logs/sessions/<UTC>-<pid>-<reason>/exit-report.json` and matching `end` metadata
in session-start.json, then check the next menu's same reason/folder. Full steps are in
[TESTING](../TESTING.md#r7-b-exit-observer-and-read-only-previews).

## Validation

`tools\test.ps1 -Config Release` **passed with exit 0**, including the UTF-8 fix. Final evidence:
`out/r7-b/release-verified.log` (26 native CTests in 36.50 s; the 402-test tools group in 73.140 s).

- Release native checks: **26/26 CTests**. Python groups: **455 tests** (28 gmapack, 25 steam,
  402 tools), with **two expected fixture skips**.
- **23 real observer scenarios** using synthetic hosts: waiting/termination, chosen status
  codes, every evidence source, fatal zero exits, quiet JSON, clean silence, manual-invocation
  refusal, all loader off switches, non-game and Chromium hosts.
- **19 evidence cases**, including **10 new exit cases**; **3 new formatting/language cases**;
  **8 memory cases** including exact boundaries; content counts 0/1/4 and all six failure
  summaries in all seven languages through the real JavaScript panel and clipboard fixture.
- A separate Win32 window probe checks one visible French dialog after a synthetic access
  violation, correct UTF-8 text/code/folder, command-language precedence and observer exit after OK.
- The initial full gate exposed the known long-worktree timestamp failure in the guard cache
  test. It now uses the production extended-length path helper, retaining its original
  idempotence assertion. No short-output-path workaround or Windows setting change is needed.

Evidence stays in this worktree's `out/r7-b/`, including release logs and dialog-probe.json.
The built DLL and CLI are under `out/build/win64-release/loader/proxy/` and `loader/cli/`.
The DLL SHA-256 is `16f6c63861cbaacbdcdf2c2861c812ad8f6716097ab620fda11df78a98ac1790`.
Empty evidence collection in the final parallel run took 1.379 ms mean / 4.073 ms maximum
over 30 starts; the observer readiness handshake is separate and bounded to three seconds.

## Limits

No real OOM, fail-fast, stack overflow, driver reset or GMod/Remix crash prompt was induced.
The chosen exit codes demonstrate process isolation; Claude still owns integrated PoC QA.
The translated text is agent-written and needs native-speaker/visual review.

Diagnosis is evidence, not proof of root cause. Ten-second samples can miss spikes; a stale
sample stays inconclusive. The map reserve is an estimate from two maps on this machine,
not a guarantee for arbitrary content or smaller GPUs. Locked, oversized or unavailable
evidence remains subject to R6's bounds. Disk/permission failures can prevent saved reports;
Windows policy can refuse the observer or UI. Power loss, shutdown, a killed observer, or a
failure before readiness cannot guarantee a message. An immediate restart can win collection;
the older observer then stays silent rather than read a different game's evidence. Language
changes not archived before a crash may use the previously archived language.
