# telemetry_integration.py

Runs the real bootstrap memory worker with a synthetic `nl_proxy_host.exe`, renamed `gmod.exe`
inside generated game roots. Never launches Garry's Mod or reads an installed game. CTest supplies:

```powershell
python -I -B loader/proxy/tests/telemetry_integration.py --host <nl_proxy_host.exe> --proxy <winmm.dll> --nlctl <nlctl.exe> --scratch <worktree/out/tmp/telemetry>
```

Checks default-on flushed CSV rows about ten seconds apart, byte/UTC columns, a current-process
commit snapshot, preservation of the old CSV before next-start sampling, and matching `nlctl status`
text/JSON. With history off, existing CSV bytes stay intact and only the latest commit snapshot is
written for the menu warning; disabling the loader writes neither. No networks or package inputs.

Creates/removes only named fixtures below `--scratch`, which must be in the worktree's `out`.
Starts only the copied synthetic host and terminates/waits for each one in `finally`. Leaves fixtures
for inspection. Exit 0 on success; assertion, child-process or filesystem errors give a nonzero exit.
