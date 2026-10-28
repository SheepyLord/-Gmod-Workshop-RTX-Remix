# test.ps1

Runs every check in the repo, in this order, and reports which steps failed:

1. [`check_repo.py`](check_repo.py.md): documentation conventions.
2. Python tests: every `tools/**/tests` folder, run from its parent folder with
   `python -m unittest discover -s tests`, so test files import the scripts beside them.
   Excludes generated `out`, `build` and `__pycache__` directories relative to the repository;
   an ancestor folder with one of those names does not hide the repository's tests.
3. [`build.ps1`](build.ps1.md): C++ configure, build and CTest (skip with `-SkipNative`).

Run it before finishing any change (see [AGENTS.md](../AGENTS.md)).

## Usage

```powershell
tools\test.ps1                  # everything, Debug build
tools\test.ps1 -SkipNative      # conventions and Python tests only (no compiler needed)
tools\test.ps1 -Config Release
```

## Outputs

- Writes only what `build.ps1` writes (`out\build\<preset>\`) plus Python `__pycache__` folders.
- Each step runs with `TEMP`/`TMP` pointing at `out\tmp`, so test scratch (Python `tempfile`, child
  processes) stays inside the repo (AGENTS.md rule 9); the previous values are restored after each step.
- Exit code 1 if any step failed; every step still runs so one failure does not hide another.

## Adding tests

- Python: put `test_*.py` in a `tests` folder beside the scripts it covers, with a `.md` per test file.
- C++: add a `test_*.cpp` to [`loader/tests`](../loader/tests/README.md) and list it in that folder's
  `CMakeLists.txt` and `README.md`.
