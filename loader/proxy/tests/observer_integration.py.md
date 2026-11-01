# observer_integration.py

CTest integration for the real embedded observer through System32 `rundll32.exe`.
Uses copied `nl_proxy_host.exe` binaries, never Garry's Mod or a runtime. Scratch must
resolve below this worktree's `out/`; each generated root is checked before removal.
Failed cases remain for diagnosis. No network, downloads, install writes or consent changes.

```powershell
python loader/proxy/tests/observer_integration.py --host out/build/win64-release/loader/proxy/tests/nl_proxy_host.exe --proxy out/build/win64-release/loader/proxy/winmm.dll --scratch out/tmp/observer-manual
```

Inputs are the built synthetic host, proxy and scratch directory. Output is PASS lines and
on failure the generated root. Checks waiting before exit, exact NTSTATUS/Win32 values,
all log/dump/commit sources, zero-exit fatal Remix paths, clean silence, quiet JSON persistence,
observer exit, manual-invocation refusal, all loader off switches and non-game/Chromium hosts.
The chosen exit codes simulate failures; no actual memory exhaustion or driver reset occurs.
Exit 0 on success; nonzero on an assertion, timeout or OS error. Run via CTest normally.
