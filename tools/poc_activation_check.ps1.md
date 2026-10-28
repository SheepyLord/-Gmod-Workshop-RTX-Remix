# poc_activation_check.ps1

M4 acceptance on the pinned GarrysMod_PoC install. Each actual game launch requires separate user
approval. The script starts **one** visible game only for Baseline/RunA/RunOff/RunB/RollbackA with
an explicit `-Launch`; without that switch it prints the concrete plan. It never advances itself
to another run. No mode changes Steam launch options or writes the runtime fork/reference install.

```powershell
tools\poc_activation_check.ps1 -Action Prepare -Config Release
# Use the printed session folder for every subsequent command:
tools\poc_activation_check.ps1 -Session <folder> -Action Baseline       # preview only
tools\poc_activation_check.ps1 -Session <folder> -Action Baseline -Launch # after this launch is approved
tools\poc_activation_check.ps1 -Session <folder> -Action Stop
tools\poc_activation_check.ps1 -Session <folder> -Action RunA -Launch     # separate approval
tools\poc_activation_check.ps1 -Session <folder> -Action Confirm -Visual path-traced -Note 'User confirmation'
tools\poc_activation_check.ps1 -Session <folder> -Action Stop
# RunOff, RunB, then RollbackA each require a new launch approval and a stopped previous game.
tools\poc_activation_check.ps1 -Session <folder> -Action Cleanup
```

Prepare requires a loader-free PoC and existing tested builds. It can prepare packages while a
different game install is running; the before-tree snapshot is taken only after all games are
closed for the separately approved baseline launch. It creates A/B archives below
`out/packages/m4-<stamp>` using package_runtime.py: A from the fork's `_output`, B with its
`built-A8E39D93-lockfree-options/d3d9.dll`, both with the reference install's root rtx.conf/dxvk.conf
as lower layers. If the named B copy is gone, the documented `_CompRelease_x64/src/d3d9` copy is
accepted only with the pinned full A8E39D93 SHA-256 recorded in the script. Both config files are
snapshotted once, with before/after hash checks, so A and B use identical layers even if the other
install is running. Those are the only reference-install files read. Outputs, manifests, session state
and tree snapshots go below `out/poc-activation/<stamp>`. TEMP/TMP stay in repo/out/tmp during packing.

Every run uses cwd=PoC, no Workshop/addons, condebug, gm_construct and `+mat_dxlevel`. Existing
console.log is preserved by moving it into that run's evidence folder before launch; Remix logs
are copied before/after, never deleted. RunA/RunOff/RunB write a hash-guarded session-owned config;
RollbackA runs nlctl rollback and leaves the B allowlist in place to verify the hold.

Capture excludes Sentry crash-database internals, `.lock` files and memory dumps; these are not
Remix text logs and may remain byte-range locked. It also snapshots module paths while startup is
in progress, so an early game exit still leaves module evidence.

Capture waits up to `-TimeoutSeconds` (240 default) for map/client Lua markers, then captures the
actual main PID's module paths, loader/status/Remix/console logs. Active d3d9 and every loaded DLL/PYD
listed in the runtime generation must come from its package folder. Off must use System32 d3d9,
retain the baseline mat_dxlevel and match normalized vanilla console output. Normalization changes
only whitespace/blank lines and numeric thumbnail allocation counters. A mismatch stops the script
for investigation; no subsequent launch is authorized by a previous one. Raw Remix logs still need
review for initialization, and Confirm records only the user's actual on-screen observation.

Capture/Stop/Confirm operate on the recorded run. Stop validates PID, executable and process start
time, requests a graceful close and never force-kills; close manually if requested. Status prints
session state. By default launches refuse while any gmod.exe is running. The user's explicitly
approved `-Multirun` override adds `-multirun` and permits other installs to remain running; an
existing or unidentifiable PoC instance still blocks the launch. Capture leaves the game visible.

Cleanup requires no game running, refuses an externally edited config, calls uninstall-loader.ps1
with RemoveConfig, saves the remaining game/Remix file changes and verifies every PoC depot file.
It retains game/Remix logs, caches and root configs. No cleanup of those files is authorized here.

Exit 0 on a completed action; a terminating error/nonzero separate-process exit on refusal,
timeout, failed build/package/activation, module mismatch or changed off-state behavior. Evidence
and session JSON are retained on failure. Prepare/preview/Status never start a game.
