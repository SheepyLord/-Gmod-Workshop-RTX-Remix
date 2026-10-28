# generate_exports.py

Reads an AMD64 PE32+ export directory with Python's standard library and generates forwarding
metadata, a module definition file and MASM leaf thunks. Preserves every nonempty EAT ordinal,
every exported name and ordinal-only entries. Does not copy system DLL bytes into the repository.

```powershell
python loader\proxy\generate_exports.py
python loader\proxy\generate_exports.py --check
python loader\proxy\generate_exports.py --dll C:\Windows\System32\winmm.dll --output out\exports
```

Inputs: `--dll` (default `%SystemRoot%/System32/winmm.dll`), `--output` (default adjacent `generated/`),
`--check`. Generation writes `exports.json`, `exports.h`, `winmm.def`, `thunks.asm`. Check mode
writes nothing: verifies the current system's ordinals/names are covered by the committed JSON
and regenerates the expected text in memory to catch drift between generated files. A committed
superset is accepted for older Windows versions, whose absent slots use the zero-return fallback.
CMake runs this check before linking, and CTest repeats it. The C++ export test independently
checks the actual built DLL against the current system module.

Exit 0 with counts on success; 1 with a diagnostic for missing exports, stale generated files,
invalid/truncated/unsupported PE or file errors. No network, third-party modules, game writes or
system changes. `--output` generation overwrites only the four named generated text files.
