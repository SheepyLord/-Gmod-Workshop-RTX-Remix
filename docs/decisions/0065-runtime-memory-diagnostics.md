# 0065: Local runtime memory snapshots before device-loss reporting

- Status: Accepted 2026-10-31 (R6 T4)
- Decided by: the user's approval of stability proposal 8; implementation within the T4 brief

## Context

The previous device-loss log did not say how much memory the driver or DXVK used at the loss.
The two opacity micromap budget messages were process-wide `ONCE` messages, hiding later pressure.
The existing VRAM API already collects the relevant counters. See
[the proposal](../handover/R5-stability-proposal.md#8-make-the-runtimes-logs-self-describing),
[the T4 brief](../handover/R6-T4-runtime-logs.md) and [RESEARCH.md](../RESEARCH.md#r6-t4-runtime-memory-snapshots-2026-10-31).

## Decision

Patch 0015 owns a small `RtxMemoryDiagnostics` object in `DxvkObjects`. Both the VRAM API and
diagnostic snapshots use its collector. Driver budget/use includes every heap; DXVK totals and the
eight categories include device-local heaps, preserving the API's meaning. Samples are approximate
host-side observations, without GPU synchronization or traversal of the texture cache.

Emit one `[RTX Memory]` JSON line at each camera cut and at five-minute intervals on present.
Repeated presents of the same frame emit no duplicate. Camera cuts do not postpone the periodic
deadline. At device loss, the single handling thread collects once before the Aftermath wait and
Sentry step, logs the snapshot at error level and writes schema 1 of interface I7 beside the runtime
log. This precedes the wait in `handleDeviceLost`; the earlier `onGpuCrash` recorder/Aftermath work
may already have run. The default path is `rtx-remix/logs/last_gpu_crash.json`;
`DXVK_LOG_PATH` relocates both files.
Write a temporary file, check flush/close, and atomically replace the previous marker. All failures
are best effort and cannot escape the diagnostic handler or change process termination.

Keep separate steady-clock one-minute limits for the two OMM warnings on the device, so recreating
the OMM manager at a camera cut cannot reset them. The first occurrence logs immediately. The next
eligible occurrence includes the number of intervening suppressed repeats; an idle warning does
not emit a separate summary. Rendering budgets and eviction behavior are unchanged.

Do not add `VK_EXT_device_fault` in this patch. The required memory evidence does not need a new
Vulkan device extension or another driver call after a loss. Aftermath remains the existing fault
diagnostic mechanism, with its existing consent and configuration.

The recorded fork tree also references five optional unit-test sources and one medium API test
source which are absent from that tree (the local fork holds ignored copies). Guard only these
targets when their sources are absent, keeping the remaining unit tests and API apps available.
The clean rebuild must not silently depend on those unrecorded local files.

## Consequences

The next-start collector can read a small local structured marker even when GPU dumps are off.
The marker is overwritten only on a later device loss; its UTC timestamp determines freshness.
No uploads or consent changes are added. The runtime still exits on device loss and these counters
do not identify the fault's cause. A stopped presentation loop cannot produce periodic samples.

CPU-only tests cover timing, suppressed counts, JSON integer precision, marker replacement and
failure preservation. Real driver memory sampling, camera-cut integration and induced GPU loss
require the project manager's later game checks; T4 does not launch the game.

## Alternatives considered

- Call the public Remix C API from the queue: it depends on the registered D3D9 device and reads
  the render-owned texture cache. Sharing only its memory collector avoids that dependency.
- Store the warning limits on the OMM manager: camera cuts recreate it and could flood the log.
- Write the marker after Sentry: an interactive or slow crash-report step could delay local evidence.
