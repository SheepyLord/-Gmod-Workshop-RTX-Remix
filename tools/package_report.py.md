# package_report.py

The RTX package's hash report (R16, [ADR 0106](../docs/decisions/0106-the-rtx-package-built-on-github.md)):
the SHA-256 of a built `.gma` and of every file in it, and, for the native binaries the workflow built,
where each came from.

```powershell
python tools\package_report.py out\dist\gmod-rtx-remix-<version>.gma
python tools\package_report.py <gma> --provenance out\ci\built\provenance-*.json --run-url <run> --commit <sha> `
    --json out\report\package-report.json --sums out\report\SHA256SUMS.txt --markdown $env:GITHUB_STEP_SUMMARY
```

| Option | Meaning |
|---|---|
| `gma` | The package to report on (read with [`gmapack`](gmapack/gmapack.py.md); an LZMA-wrapped `.gma` is read too) |
| `--provenance` | One or more provenance records of the run ([`tools/ci`](ci/README.md)): `{"binaries": {"<SHA-256>": {"part", "path", "repository", "commit", "how", "run"}}}`. They are merged; a file of the `.gma` with that SHA-256 gets the record as `built`, wherever a packager put it |
| `--run-url`, `--commit` | The run and commit the package was built by and from (defaults: `NL_RUN_URL`, `GITHUB_SHA`) |
| `--json` | Writes the report: `gma` (name, bytes, sha256), `run`, `commit`, `count`, `binaries` (`.dll`, `.exe`, `.so`, `.sys`), `compiled`, `fetched`, `from_packages`, and `files` (path, size, sha256, in archive order; a binary also has `origin`: `compiled`, `fetched` or `packages`, and `built` when a record names it) |
| `--sums` | Writes sha256sum's format: the `.gma` first, then every file in it |
| `--markdown` | Appends the report as Markdown, for a GitHub job summary: the `.gma`'s size and SHA-256, the commit and run, the counts, the binaries compiled in the run and those it downloaded (each with its SHA-256, repository, commit and recipe), those taken from `packages/`, and every file (in a folded table) |

Reads the archive once, in 4 MiB blocks (about 2 s for the 1.8 GB package from a warm cache). Writes
only the files named. Prints one line: the `.gma`'s size and hash, the file count and how many native
binaries were compiled, fetched or taken from `packages/`. **Exit:** 0 written; 2 when the archive or the provenance cannot
be read. Tested by [test_package_report.py](tests/test_package_report.py.md).
