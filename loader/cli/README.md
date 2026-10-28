# loader/cli/ (`nlctl.exe`)

The loader core on the command line, so packages and installs can be examined, and from M3
deployed, without starting Garry's Mod. It links `nl_core`, the same library the bootstrap uses.
Read-only in M2.

| File | Purpose |
|---|---|
| `CMakeLists.txt` | Builds `nlctl`; registers the `nlctl_crosscheck_gmapack` CTest |
| `nlctl.cpp` | Command parsing (`wmain`, Unicode paths) and the commands below |
| `tests/crosscheck_gmapack.py` | CTest: `nlctl` must agree with the Python reference reader ([doc](tests/crosscheck_gmapack.py.md)) |

## Commands

```powershell
nlctl inspect <file.gma> [--json]   # header and file index (LZMA-wrapped: decoded only that far)
nlctl verify  <file.gma> [--json]   # one pass: every nonzero file CRC, the archive CRC, trailing data
nlctl scan    <folder>   [--json]   # read-only parse of every .gma / .bin archive below the folder
nlctl version
```

Plain (`.gma`) and LZMA-wrapped (Workshop `*_legacy.bin`) archives are both read.

- `inspect` reports `container` (`gmad` / `lzma`), `stream_size` (file size, or the declared
  decompressed size; `null` if undeclared), `complete` (all contents present) and `crc_trailer`
  (the optional 4-byte archive CRC is there).
- `verify` decodes everything and also reports `crc_trailer` and, for LZMA, `lzma_gmod_footer`.
  A damaged LZMA container (cut stream, wrong footer, bytes after it) is a format error: exit 2.
- `scan` reads headers and indexes only. It counts `parsed`, `lzma`, `without_crc_trailer` and
  `with_trailing_data`, and fails only archives whose contents or trailer are cut short.

Exit codes: `0` ok, `1` a check found problems (bad CRC, trailing data, failed archives in a scan),
`2` bad usage or unreadable / malformed input, `3` internal error.

Output is UTF-8. JSON strings come from `nl::json::quote`: invalid UTF-8 bytes in archive paths are
shown as U+FFFD, never passed through raw.
