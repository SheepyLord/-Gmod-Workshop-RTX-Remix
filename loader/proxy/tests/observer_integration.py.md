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
The manual export call is refused for its process id (exit code `0x4E4C0000 + 2`). A case without an
`exit observer ready` note fails, with the loader log, which names a refusal's reason.
First (R19, proxy F-06), rundll32 calls the proxy's forwarded `timeGetTime` export, as any module in the
observer's process that imports `winmm.dll` by name would: it must return (exit 0), not jump through an
empty forwarding slot, and the observer host still writes no loader files.
Exit 0 on success; nonzero on an assertion, timeout or OS error. Run via CTest normally.
