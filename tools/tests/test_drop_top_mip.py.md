# test_drop_top_mip.py

Generated DDS fixtures for [`drop_top_mip.py`](../sky/drop_top_mip.py.md): legacy DXT1/3/5 and DX10
BC7, rectangular chains, sub-block dimensions, the last retained mip's flags/caps, preserved header
fields, exact bytes of source mip 1 and all remaining mips, and corruption detected by verification.
Refuses invalid headers, dimensions/counts/linear size, unsupported formats, arrays, cubes, volumes,
truncated data and trailing bytes. The CLI cannot overwrite the source or an existing output.

Run `python -m unittest tests.test_drop_top_mip -v` from `tools`, or `tools\test.ps1`.
Only CLI tests write files, inside a temporary folder under `out/tmp`, removed afterwards. No real
sky asset or game install is needed. Exit codes: unittest's (0 on success).
