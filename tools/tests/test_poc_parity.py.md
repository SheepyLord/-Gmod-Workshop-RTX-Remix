# test_poc_parity.py

Unit tests for [`poc_parity.py`](../poc_parity.py.md)'s path checks (R1-016). Each test builds two
synthetic installs, a "reference" and a "PoC", in a temporary folder under `out\tmp`, with a file
beside each root that must never be written. `game_running` is mocked and the Workshop folder points
at a scratch path that does not exist; no real install is read or written, and no Workshop item is
opened.

```powershell
cd tools; python -m unittest tests.test_poc_parity -v    # or tools\test.ps1
```

Covers:

- `path_problem` passes plain relative paths (with `/` or `\`, spaces, `~`). It refuses empty text,
  `.` and `..` components, empty components, absolute, rooted, drive-relative, UNC and `\\?\` paths,
  components ending in `.` or a space, and `:` streams.
- `prepare` refuses escaping `--native`, `--data`, `--save` and `--map` values before it writes
  anything: no file appears beside the PoC (R1-016's repro), no `parity.json` is written and the PoC
  is unchanged. A `--map` id that is not a number is refused too.
- `prepare` refuses a `--native` path that resolves out of the PoC through a junction inside it, and
  writes nothing at the junction's target. Skipped where junctions cannot be made.
- A `prepare` and `restore` round trip of a `--native` file and a save.
- `restore` refuses a `parity.json` that names a path outside the PoC (relative or absolute), or a
  backup outside its `parity-backup` folder. It refuses before touching anything: the recorded
  files, the PoC and the file beside it are unchanged, and `parity.json` stays.

Side effects: only the temporary folder, removed afterwards. Exit code: unittest's (0 when all pass).
