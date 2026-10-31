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
The fixture host has a test-only TLS switch to invalidate a command-line descriptor before the hook.
For [ADR 0056](../../../docs/decisions/0056-guard-and-startup-fallbacks.md), a catalog-verifiable
`gmod-rtx-remix` development package (the runtime plus a synthetic client helper and V2 guard)
with an initializer no stock hash matches must still activate, note why the early guard view is
unavailable, report no error and write no view.

Writes JSON probes, loader logs, status snapshots and a ten-sample unchanged-startup timing summary
under `out/m4-synthetic/<configuration>-<PID>/`. Successful scratch is removed, retrying momentary
Windows image-file locks. Failed scratch is retained and printed. Exit 0 when all checks pass;
nonzero with traceback/evidence on a mismatch or timeout. Only test-created processes are stopped.
