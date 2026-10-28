# test_vdf.py

Unit tests for [`vdf.py`](../vdf.py.md): nested blocks, comments, escaped quotes and backslashes
(Windows paths as Steam writes them), unquoted tokens, later duplicate keys winning, skipped platform
conditionals, and `ValueError` on unbalanced braces.

Run from `tools\steam\`: `python -m unittest discover -s tests` (or `tools\test.ps1`).
