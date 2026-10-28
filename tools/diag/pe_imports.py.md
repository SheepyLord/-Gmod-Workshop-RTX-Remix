# pe_imports.py

Lists the DLLs a Windows PE file imports (static and delay-load) and, with `--exports`, the names it
exports. Read-only diagnostics.

Used to find DLL search-order hook points: `bin\win64\gmod.exe` imports `WINMM.dll` and
`dbghelp.dll`, neither of which is a KnownDLL, which is why the bootstrap is a `winmm.dll` proxy
([ADR 0001](../../docs/decisions/0001-bootstrap-winmm-proxy.md)). Also used to see what a Remix
runtime `d3d9.dll` needs beside it and which `remixapi_*` functions it exports.

## Usage

```powershell
python tools\diag\pe_imports.py "<GarrysMod>\bin\win64\gmod.exe" "<GarrysMod>\bin\win64\shaderapidx9.dll"
python tools\diag\pe_imports.py --exports "<runtime>\d3d9.dll"
python tools\diag\pe_imports.py --json <files...>
```

Requires the `pefile` package (`python -m pip install pefile`). Exit code 1 if any file could not be read.
