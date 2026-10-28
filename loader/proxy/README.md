# loader/proxy

M1 inert x64 bootstrap, output `winmm.dll`. All 181 System32 export ordinals are forwarded by leaf
MASM jumps through a table populated from the full System32 path. Named exports resolve by name;
ordinal-only exports by ordinal. Missing functions use a zero-return stub and appear in the active
startup log. The system module is retained for the process lifetime.

`DllMain` uses fixed buffers and allocation-free activation logic. Only a `bin/win64/gmod.exe`
beside this `winmm.dll`, with none of the three off switches, receives a 14-byte absolute jump at
its PE entry point. The hook restores those bytes first, logs outside the loader lock behind
separate C++/SEH guards, and calls the original entry point with its argument, returning its result.
No packages or runtime are loaded. Static CRT notifications remain enabled.

| File | Purpose |
|---|---|
| `CMakeLists.txt` | MASM/RC, `nl_proxy_logic`, DLL, export consistency check and tests |
| `activation.h`, `activation.cpp` | Pure path/root, quoted argument and off-switch decisions |
| `bootstrap.h` | Fixed process state shared by the hook and logger |
| `bootstrap.cpp` | System forwarding table, `DllMain`, PE entry patch/restore and hook |
| `startup.cpp` | UTF-8 log, UTC/process/module proof, five-file rotation, C++/SEH containment |
| `version.rc.in` | CMake version and installer identity resource |
| `generate_exports.py` | Standard-library PE export parser and generator; [usage](generate_exports.py.md) |
| `generated/exports.json` | Checked-in ordinal/name inventory |
| `generated/exports.h` | Generated ordinal/name lookup metadata and count |
| `generated/winmm.def` | Generated public names/ordinals, including `NONAME` |
| `generated/thunks.asm` | One register-preserving indirect jump per exported ordinal |
| [`tests/`](tests/README.md) | Pure logic, forwarding, hook integration, installer tests |

Regenerate on a Windows export-set change with `python loader/proxy/generate_exports.py`; the
build checks that the committed set covers the current machine and the generated files agree.
An older system may lack a committed export: that slot stays a logged zero-return fallback.

Failure limits: logging errors leave the game running and emit a debugger diagnostic. Hook
installation failure leaves pass-through behavior. If Windows refuses both protection changes and
the debugger write fallback when restoring an already installed hook, the process is terminated
instead of recursively entering its patched entry point. This is outside the guarded logging step;
normal activation and failure-to-log paths are covered by the synthetic host tests.
