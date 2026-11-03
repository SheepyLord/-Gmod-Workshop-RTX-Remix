# test_memory_report.py

Unit tests for [`tools/qa/memory_report.py`](../qa/memory_report.py.md), R13's session memory report.

- **Windows and phases.** Generated loader and companion telemetry, with a rotated file, an older
  session's row, an empty counter and a row without a time. A session window and a named phase report
  the right sample counts, peaks and last values.
- **Command line.** `--out` writes the report. A window with no samples exits 1, a malformed phase
  exits 2, and a time that is not UTC is refused.
- **Census.** Censusing this test's own process gives committed memory, its private allocations, and
  size buckets that add up to the private total. Windows only.

```powershell
python -m unittest tools.tests.test_memory_report
```

Fixtures are written to a temporary folder; nothing outside it is read or changed.
