# drop_top_mip.py

Makes a smaller DDS by removing its largest mip. It halves the header's width/height (at least 1),
reduces the mip count, updates the top mip's linear size, and retains every compressed block of mip
1 onward byte for byte. No decoder, encoder, image library or external program is used.

```powershell
python tools\sky\drop_top_mip.py out\inputs\runtime\files\atmosphere\stars.dds out\stars_4096.dds
```

Inputs: a power-of-two, single 2D block-compressed DDS with at least two mips: legacy DXT1/3/5,
ATI1/2, BC4U/S or BC5U/S; or DX10 BC1 through BC7. Arrays, cubemaps, volumes, unsupported formats,
bad dimensions/counts/linear sizes, truncated chains and trailing bytes are refused. Partial chains
are allowed. The DX10 format, colour space, alpha mode and remaining header fields stay intact.

Output: one DDS, created exclusively (an existing output or the source itself is refused). The
parent folder must exist. The result is checked against the source's dimensions and full retained
mip chain before writing and read back afterwards. JSON on stdout gives dimensions, mip count,
payload bytes, dropped bytes, SHA-256 of the source's mip 1 and SHA-256 of the result.

Side effects: reads the source and creates only the output; never changes the source. A failed
write/readback may leave an incomplete output, which the next invocation refuses. Exit codes: 0
success, 1 invalid DDS or I/O error (stderr), 2 command-line error. Tests:
[`test_drop_top_mip.py`](../tests/test_drop_top_mip.py.md). R6 provenance and measurements:
[ADR 0064](../../docs/decisions/0064-performance-tier-defaults.md).
