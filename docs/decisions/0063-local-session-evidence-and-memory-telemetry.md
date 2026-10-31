# 0063: Local session evidence and memory telemetry

- Status: Accepted
- Date: 2026-10-31
- Decided by: the user, approving R5 proposals 3, 5 and 11; R6's retention/default decisions

## Context

The [R5 proposal](../handover/R5-stability-proposal.md) established two different failures: GPU
device loss without Aftermath data, and exhausted system commit. Restarting destroys the useful
runtime log. Start-only memory figures cannot explain growth during play. See
[RESEARCH.md](../RESEARCH.md#r6-t2-evidence-boundaries-2026-10-31).

## Decision

Keep evidence locally by default. A bootstrap worker classifies the last 256 KiB of the previous
Remix log, reads optional fresh `last_gpu_crash.json`, and copies the full log before releasing a
runtime-load gate. Remaining bounded dump copying overlaps activation and finishes before the
startup report. A copy failure is a note, never a reason to disable RTX. Locked sources are skipped,
with full read/write/delete sharing for readable ones. Original logs/dumps are never modified.

Record the current start separately from deployment state. The next start takes crash files only
from that interval; the previous loader log's FILETIME is the first-upgrade fallback. Without either
record, retain existing evidence conservatively. More specific failure evidence wins: engine OOM,
device loss, allocation failure, CS exception, generic crash, explicit deliberate exit, unknown.
No generic clean-shutdown marker exists in the runtime; resource destruction alone is insufficient.

Keep the newest five intact, receipted archives within 200 MiB. SHA-256/size checks and a complete
directory census protect user-edited copies and additions from retention. Such user-owned folders
are outside the automatic bound. Oversized dumps are skipped; an oversized log keeps its bounded
tail. A SHA-256 receipt records exactly what was saved. Neither this data nor telemetry is uploaded.
`status.json` adds R6 I5's `previous_session`; `nlctl status` shows it without requiring a journal.

Memory telemetry is on by default, configurable with `diagnostics.memory_telemetry` (`on`/`off`).
Use a low-priority bootstrap worker and runtime-loaded DXGI, keeping the DLL import dependency
set KERNEL32-only. Sample process private/working-set bytes, system commit/limit/available RAM and
GPU local/non-local usage/budget every ten seconds, flushing each CSV line. Rotate bounded history
to `memory.1.csv`; the evidence collector keeps the tails before a new sampler starts.

The home-menu panel shows a local failure summary and a once-per-start warning when commit limit
is below 32 GiB or usage exceeds 70 percent. Its text follows all seven existing menu languages.
It explains system-managed page files on a drive with room and closing other programs. It does not
change the page file, settings, launch options, native trust or Remix configuration.

## Consequences

Implementation detail: CSV history rotates hourly (360 rows per segment), with a 256-KiB per-file
cap and size/hash receipts. Each logical append is flushed by atomic replacement of the small
segment, so a crash cannot expose a partial row. History off disables process/GPU sampling and CSV
writes; an independent latest-only system commit snapshot in the game's data folder lets the
home-menu warning use a recent observation even with history off. Global loader off switches still
disable both. Snapshot tokens include process creation time to reject previous-process data.

Restarting preserves useful evidence instead of erasing it. Large copies run on a worker; a large
old log can still delay runtime load, and startup waits for remaining evidence before entering the
engine. Collection cannot recover dumps that the runtime already deleted, sources locked against
readers, or data outside the bounded collection. Classification describes evidence, not root cause.
Actual fault reproduction and an in-game soak remain integration work; T2 does not launch GMod.

## Alternatives considered

- Moving original logs/dumps would violate source preservation.
- Copying after runtime load would race log truncation; copying every dump on the entry thread
  would put all I/O on the startup path.
- Treating teardown messages as clean exits would conceal crashes during shutdown/map changes.
- Unbounded telemetry or retaining arbitrary session folders would consume disk indefinitely and
  risk deleting user-edited evidence.
