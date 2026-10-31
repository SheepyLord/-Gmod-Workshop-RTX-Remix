# loader/proxy

R6: `startup.cpp` starts the local evidence collector outside loader lock, overlaps copying with
planning and activation, waits for the old Remix log before loading its DLL, and joins the remaining
dump work before writing `previous_session` to status. Failures are diagnostic notes, never an
activation veto. See [ADR 0063](../../docs/decisions/0063-local-session-evidence-and-memory-telemetry.md).

Loader 0.8.1 adds `diagnostics.h` / `diagnostics.cpp`: local CPU/thread/RAM/Windows/DXGI information,
the installed bootstrap SHA-256 and deployed package versions/manifest hashes. `ui/mainmenu.js`,
`ui/labels.json` and `ui/presentation_data.h.in` provide the seven-language main-menu home panel
and its CMake embedding. An exact read redirect supplies a generated copy of control.Menu.js;
the Steam file is unchanged. No account names, paths or network identifiers are displayed.

R6's `ui/read_notices.lua` is an embedded, bounded, read-only menu bridge for this start's status
and latest system commit. The panel localizes failure summaries/evidence folders and its RAM warning
in seven languages. Status, menu data and memory snapshots share a PID/creation-time token to reject
stale starts, including PID reuse. The warning is acknowledged in menu Lua, once before a map;
no page-file or game setting is changed. The only displayed path is the relative evidence folder.

X64 bootstrap, output `winmm.dll`: M1 forwarding/entry hook plus M4 startup deployment and activation.
All 181 System32 export ordinals are forwarded by leaf
MASM jumps through a table populated from the full System32 path. Named exports resolve by name;
ordinal-only exports by ordinal. Missing functions use a zero-return stub and appear in the active
startup log. The system module is retained for the process lifetime.

`DllMain` uses fixed buffers and allocation-free activation logic. Only a `bin/win64/gmod.exe`
beside this `winmm.dll`, with none of the three off switches, receives a 14-byte absolute jump at
its PE entry point. Chromium helper roles (`--type=...` or `--type ...`) using the same executable
stay pure pass-through, so they cannot overwrite the game log or bypass a parent launch switch.
The hook restores those bytes first, then runs the log, startup deployment policy, activation and
atomic status report behind separate C++/SEH guards before calling the original entry point.
Missing/disabled/invalid configuration leaves the process vanilla. A valid current generation can
activate through reversible environment/arguments/Vulkan/DLL-search changes, with absolute runtime
preload last. Rollback state lives outside the SEH frame. Static CRT notifications remain enabled.
See [ADR 0008](../../docs/decisions/0008-activation-at-startup.md) and
[ADR 0009](../../docs/decisions/0009-startup-deployment-last-good.md).

| File | Purpose |
|---|---|
| `telemetry.h`, `telemetry.cpp` | R6 process-lifetime background worker, outside loader lock after evidence collection; flushes memory history every ten seconds and supplies the latest system-commit snapshot. Holds a bootstrap reference while running; no shutdown join under loader lock. History off queries only system commit; disabled loader starts no worker |
| `presentation.h`, `presentation.cpp` | Loader 0.7.0: validate current Workshop package identities, build inert display GMAs and a targeted addon-menu overlay under `native-loader/presentation`; exact read redirects give GMod blue native-package cards and normal Workshop descriptions without changing depot or Workshop files ([ADR 0039](../../docs/decisions/0039-native-package-addon-presentation.md)). Loader 0.10.1: when the stock main menu controller changed, the main menu view still carries the multiplayer bootstrap trigger alone ([ADR 0056](../../docs/decisions/0056-guard-and-startup-fallbacks.md)) |
| `CMakeLists.txt` | MASM/RC, `nl_proxy_logic`, DLL, export consistency check and tests |
| `activation.h`, `activation.cpp` | Pure path/root, quoted argument and off-switch decisions |
| `backend.h`, `backend.cpp` | RTX-only stock D3D9 process selection: rewrite every explicit `-shaderapi` choice, including duplicate/case/quoted-path forms, while preserving unrelated raw arguments. RTX-off launches stay unchanged. `runtime.cpp` uses the reversible W/A/PEB swap and reports the compatibility choice only after successful activation; Steam launch options and graphics DLL files are never edited |
| `bootstrap.h` | Fixed process state shared by the hook and logger |
| `bootstrap.cpp` | System forwarding table, `DllMain`, PE entry patch/restore and hook |
| `startup.cpp` | Entry log/proof/rotation, config→discovery→deployment→activation orchestration, atomic status and final logging, C++/SEH containment. Loader 0.10.1: an early render guard view that cannot be prepared is a note, never a refusal; the rendering-recipe opt-out without `-insecure` stays vanilla with its reason (ADR 0056) |
| `modules.h`, `modules.cpp` | M5 module hooks: the `LdrRegisterDllNotification` watcher that applies patch sets as engine DLLs are mapped, and the `LoadLibrary*` import hooks that load an overridden module's replacement ([ADR 0010](../../docs/decisions/0010-rtx-session-extras.md)); in sessions without a runtime, the `FindFirstFile*`/`FindNextFile*` import hooks on `filesystem_stdio.dll` that leave `requires_remix` packages' add-on folders out of searches of `garrysmod\addons` ([ADR 0013](../../docs/decisions/0013-rtx-only-addons-hidden-without-rtx.md)); in every session (loader 0.3.0), the same `LoadLibrary*` hooks load the files a package's binary module needs (its runtime DLL in `garrysmod\lua\bin`) by absolute path just before the game loads it ([ADR 0024](../../docs/decisions/0024-bundled-addons-and-module-dependencies.md)); results in `session.json` (never written through a link). Since R1: the hooks' state is published once and never freed, and `uninstall()` turns every hook into a pass-through, so a hook running on another thread stays safe; slots are recorded before they change; import descriptors without a name table are matched by bound address; every RVA is checked against the image |
| `runtime.h`, `runtime.cpp` | M4 activation preconditions, reversible environment/command-line/Vulkan/DLL-search steps (the runtime folder on `PATH` and, from loader 0.5.0, an `AddDllDirectory` folder), the copies of the package's Remix layers the runtime reads (ADR 0036), the non-NVIDIA Remix layer (ADR 0030), ReShade's layer and settings (ADR 0028), absolute runtime preload, then the runtime's late bare-name DLLs by absolute path (ADR 0030); state remains outside the SEH frame until reporting succeeds |
| `version.rc.in` | CMake version and installer identity resource |
| `generate_exports.py` | Standard-library PE export parser and generator; [usage](generate_exports.py.md) |
| `generated/exports.json` | Checked-in ordinal/name inventory |
| `generated/exports.h` | Generated ordinal/name lookup metadata and count |
| `generated/winmm.def` | Generated public names/ordinals, including `NONAME` |
| `generated/thunks.asm` | One register-preserving indirect jump per exported ordinal |
| [`tests/`](tests/README.md) | Pure logic, forwarding, hook integration, installer, import-table and packaged fake-runtime integration tests |

Regenerate on a Windows export-set change with `python loader/proxy/generate_exports.py`; the
build checks that the committed set covers the current machine and the generated files agree.
An older system may lack a committed export: that slot stays a logged zero-return fallback.

Failure limits: logging errors leave the game running and emit a debugger diagnostic. Hook
installation failure leaves pass-through behavior. If Windows refuses both protection changes and
the debugger write fallback when restoring an already installed hook, the process is terminated
instead of recursively entering its patched entry point. This is outside the guarded logging step;
normal activation and failure-to-log paths are covered by the synthetic host tests.
