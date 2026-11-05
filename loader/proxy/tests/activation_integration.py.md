# activation_integration.py

CTest M4 synthetic acceptance. Requires `--repo`, `--host`, `--proxy`, `--runtime`, `--nlctl`,
`--scratch` and `--config`. Scratch must resolve below this repo's `out/tmp`; creates a unique PID
child. Packages test-built DLLs with `tools/package_runtime.py`. Never launches the real game,
reads a real runtime or changes Steam settings. Windows/Python standard library only.

Exercises startup deploy/no-op, static and delay dependencies, the borderless window at the display's
size and a window mode the user chose (ADR 0018), all off switches, RTX off, preserved
user config lists and arguments, source removal versus outage, Workshop disable, a Workshop update in
progress (kept) versus an unsubscribe (removed, payload folder deleted; ADR 0025), lock/pending/
recovery, second-instance gating, invalid journal, failed dependency/DllMain/SEH rollback,
command-line refusal and explicit fallback arguments, cwd/layer checks and status uninstall.

R6: uninstall removes generated status, preserving any latest-only memory snapshot as local
diagnostics (including its atomic-write temporary after a short-lived host); the data folder is
removed only when empty. Compares all retained memory diagnostic bytes before/after.
The fixture host has a test-only TLS switch to invalidate a command-line descriptor before the hook.
For [ADR 0056](../../../docs/decisions/0056-guard-and-startup-fallbacks.md), a catalog-verifiable
`gmod-rtx-remix` development package (the runtime plus a synthetic client helper and V2 guard)
with an initializer no stock hash matches must still activate, note why the early guard view is
unavailable, report no error and write no view.

R19 adds two scenarios:

- **The RTX session marker** (proxy F-02). After the off-switch checks, an RTX host started in its
  hold mode (`--m4-hold`) must report the marker in `session.notes` and hold
  `garrysmod/data/native-loader/rtx-session.txt`, listed and not deletable by this process. Once the host
  is killed (as a crash ends it) the file must be gone within 5 s. A following `-nonativeloader` start
  must leave the old "active" report and no marker. A leftover marker (what a power loss leaves) must be
  gone after a start with RTX off.
- **Content only from subscriptions** ([ADR 0111](../../../docs/decisions/0111-content-packages-only-from-subscribed-items.md)).
  A content package built with the vendored gmapack sits in Workshop item 456 of the library beside the
  allowlisted runtime item. With Steam's record naming no subscriber (what `steamworks.DownloadUGC`
  leaves) nothing deploys and nothing is listed; subscribed, it deploys; with the subscriber gone it is
  removed with the reason; subscribed again it comes back; with the record deleted it stays
  (`unchanged`). The item's file is never touched.

Writes JSON probes, loader logs, status snapshots and a ten-sample unchanged-startup timing summary
under `out/m4-synthetic/<configuration>-<PID>/`. Successful scratch is removed, retrying momentary
Windows image-file locks. Failed scratch is retained and printed. Exit 0 when all checks pass;
nonzero with traceback/evidence on a mismatch or timeout. Only test-created processes are stopped.

## R6 T1 layer precedence

The short-copy check expects the non-NVIDIA Remix layer before the package's DXVK copies: Remix's
`rtx.*` options use the first listed layer containing a key. The root `dxvk.conf` stays last.

### R6 T1 performance tiers and GPU diagnostics

Generates medium/low fixture payloads, updates their synthetic manifest hashes and repacks them
with the vendored gmapack CLI. It checks copied tier bytes and first position on NVIDIA machines
(non-NVIDIA keeps its existing Auto path), pre-R6 low fallback, high omission and invalid-value
notes in status/log. GPU diagnostics checks all three layer options, the absolute created local
folder and environment, next_start once, read-only CLI previews, explicit marker re-arm,
always/off and config bytes unchanged. Adds only generated files below out/tmp and evidence in
out/m4-synthetic; no real game, runtime package input or player config is used.

Also verifies that RTX-off does not consume next_start, a blocked dump-folder path preserves
RTX and the pending request, and activation rollback restores a pre-existing dump destination.

T1 review regressions also assert `next_start -> off -> next_start` re-arms the marker, invalid
diagnostic values keep RTX active with diagnostics off, and a high run after low/medium omits
the leftover tier.conf from both the effective layer list and DXVK_CONFIG_FILE.
