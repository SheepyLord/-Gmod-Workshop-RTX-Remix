# inputs.py

Keeps the RTX package's inputs in this repository, under `packages\<part>\`
([packages/README.md](../packages/README.md), [ADR 0033](../docs/decisions/0033-one-repository-package-inputs-in-git-lfs.md)):
stores files there (text as it is, everything else xz-compressed for Git LFS), indexes them, unpacks
them into `out\inputs\<part>\` for the packagers, and checks the stored files against the index.

```powershell
python tools\inputs.py unpack [--part NAME ...] [--dest out\inputs] [--overlay out\ci\built [--keep-packaged PART/PATH ...]]
python tools\inputs.py extract PART --prefix FOLDER/ --dest DIR
python tools\inputs.py verify [--part NAME ...] [--deep]
python tools\inputs.py import PART [--inventory FILE] [--root SRC=DST ...] [--file SRC=DST ...] [--prune]
python tools\inputs.py list
```

## The index

`packages\<part>\files.json`, schema 1: `part`, `origins` (per target prefix: `source`, its `git`
repository, origin URL, commit and whether the source had local changes, and `imported`, UTC), and
`files`, by path in the part (forward slashes): `size`, `sha256`, `mtime_ns`, `stored` (`plain` or
`xz`), and for xz also `stored_size` and `stored_sha256` (the `.xz` file's, which is its Git LFS oid).

- **Plain:** UTF-8 text without NUL bytes, at most 1 MiB, stored at `packages\<part>\<path>`.
- **xz:** everything else, stored at `<path>.xz` (LZMA2 in the xz format, preset 6, CRC64).
  Compression runs in parallel, one file per thread (CPU count - 2).
- Paths are relative, without `.`/`..`/empty segments, backslashes or drive letters; two paths that
  differ only in case are refused. `files.json`, `README.md`, `LICENSE`, `LICENSE.txt`, `COPYING` and a
  `licenses\` folder at the top of a part are its own documents, not inputs.
- **Names Windows reads as another file** are refused too (review R19, F-09): a path part that ends in a
  dot or a space (Windows drops them: `foo.dll.` is `foo.dll`), a device name in any folder and with any
  extension (`NUL`, `CON`, `AUX`, `PRN`, `COM0`-`COM9`, `LPT0`-`LPT9`, `CONIN$`, `CONOUT$`, `CLOCK$`:
  `com1.txt` too), a character Windows does not allow in a name (`<>:"|?*`, control characters), and
  the 8.3 form of a short name (`LONGNA~1.DLL`, which can be another file's second name; `~gmod_topbr`,
  with no digit after the tilde, is fine). Across the whole index, two paths that differ only in case,
  and a path beside the same path with `.xz` added (stored under one name), are refused. The index is
  checked whole each time it is read, so `verify` reports such an index and `unpack`, `extract` and
  `import` stop before they read or write by it; `import` also refuses a new path that would name the
  file of one already indexed, before it stores anything. Before R19, an index holding both
  `files/foo.dll` and `files/foo.dll.` verified, and `unpack` wrote both to one file at the same time.

## Commands

- **`unpack`**: for every part (or the named ones) makes `out\inputs\<part>\` match the index. A file
  whose size, time and SHA-256 already match is kept (every kept file is hashed: an edited or stale one
  with the indexed size and time would otherwise go into the package, R3-003); others are copied or
  decompressed through a `.tmp` file, checked against the size and SHA-256, renamed into place and
  given the recorded time (so the packagers' time-based versions are reproduced). Files the index does
  not list are deleted, and empty folders removed. A Git LFS pointer instead of content stops it: run
  `git lfs pull`. It writes and deletes only in real folders: the destination, a part's folder, or
  anything below it that is a link or a junction stops it before the first write (R3-006); remove it,
  the tree is rebuilt from `packages\`.
- **`verify`**: every indexed file exists and matches (plain: size and SHA-256; xz: size and SHA-256 of
  the `.xz`, or, for a Git LFS pointer, its oid and size), and no file besides the part's documents is
  unindexed. `--deep` also decompresses real xz content and checks the original SHA-256. Prints the
  problems and `N parts checked, M problems`; exit 1 when there are problems.
- **`import`**: stores sources into a part and updates its index.
  - `--inventory`: a packager's `<out>.inventory.txt` (`size`, `sha256`, `path`, `source`, `note`). Exactly
    its source files are imported, each under the `--root` it lies in (`SRC=DST`: a source folder and
    its place in the part; the longest matching root wins). Rows that are not files (written by the
    packager), and sources in this repository outside `out\` (the companion), are skipped. A source in
    no root is an error.
  - Without `--inventory`, each `--root` folder is copied whole (git metadata and `desktop.ini`-style
    files left out).
  - `--file SRC=DST`: single files, for what a packager reads but does not list (`autoexec.cfg`).
  - Every source is hashed. Unchanged files (the SHA-256 the index has, with the stored file present)
    are not stored again, whatever their time says (R3-007). With `--inventory`, a source whose SHA-256
    is not the one the inventory lists changed after the packager read it, and stops the import: build
    the part again. `--prune` removes indexed files under the import's target prefixes that it did not
    bring. The index is written whole or not at all (a `.tmp` file renamed over it).
  - Prints a JSON summary: `part`, `files`, `stored`, `removed`.
  - An existing index that cannot be read (not JSON, not a schema 1 index of the part, or a name
    refused above) stops the import. Before R19 the import replaced it with a new index that held only
    the files it imported. Only a part without an index starts a new one.
- **`list`**: each part's file count, size and stored size.

**Exit:** 0 on success; 1 on an error (`inputs: ...` on stderr) or, for `verify`, on any problem.
- **`unpack --overlay DIR`** (R16, [ADR 0106](../docs/decisions/0106-the-rtx-package-built-on-github.md)):
  the files a workflow built or fetched, as `DIR\<part>\<path in the part>`, are copied in place of the
  stored ones, which are not read (their Git LFS content need not be there). Each must be a file the
  index lists, and every `.dll`/`.exe` the index lists must come from the overlay unless
  `--keep-packaged` names it (`part/path`, or a folder ending in `/`); otherwise it stops and names them.

- **`extract PART --prefix FOLDER/ --dest DIR`** (R16, [ADR 0107](../docs/decisions/0107-the-model-hotloaders-natives-built-from-a-source-copy.md)):
  writes the part's indexed files under that folder (a source tree a workflow builds from, such as
  `model-hotloader`'s `source/mmdhl/`) to `DIR` without the prefix, checked against the index like
  `unpack`'s; only those files' stored content is read. It stops when the index lists none there.

**Writes:** `packages\<part>\` (import), `out\inputs\` (unpack), the given folder (extract). Reads only the given sources.
Tests: [`tests/test_inputs.py`](tests/test_inputs.py.md).
