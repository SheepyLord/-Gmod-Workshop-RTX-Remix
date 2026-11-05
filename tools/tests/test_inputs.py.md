# test_inputs.py

Tests for [`inputs.py`](../inputs.py.md), on synthetic parts in `out\tmp\test-inputs-*` (removed
afterwards), and one check of the real `packages\`.

```powershell
python tools\tests\test_inputs.py
```

| Test | Checks |
|---|---|
| `test_plain_and_xz_and_the_index` | CRLF Lua stays plain and byte-identical; a binary, a text over 1 MiB and a non-UTF-8 text go to `.xz`; the index's sizes, SHA-256s, times, stored size and oid, and origins; `verify --deep` passes; unchanged sources are not stored again |
| `test_unpack_restores_bytes_and_times_and_removes_stale_files` | `unpack` writes every file with its bytes and recorded time, deletes a stale file and its empty folder, and writes nothing the second time |
| `test_extract_writes_one_folder_of_a_part_without_its_prefix` | R16: `extract` writes a folder's files (plain and xz) without the prefix, with their times, reads no other stored file (an LFS pointer elsewhere does not matter), and refuses a prefix without `/` or one that names no file |
| `test_a_build_overlay_replaces_the_stored_binaries_without_reading_them` | R16: with `overlay`, a binary comes from the build folder although its stored file is only an LFS pointer; the rest is unpacked as usual; without the overlay that pointer stops `unpack` |
| `test_with_an_overlay_every_native_binary_must_come_from_the_build` | R16: a `.dll` the overlay lacks stops `unpack`, unless `keep_packaged` names it (the file, or its folder ending in `/`) |
| `test_an_overlay_file_the_index_does_not_list_is_refused` | R16: a build never adds files to a part |
| `test_unpack_refuses_content_that_does_not_match` | A changed stored file stops `unpack`, and nothing half-written is left |
| `test_unpack_rewrites_a_change_that_kept_the_size_and_time` | R3-003: an unpacked file edited to the same length and given back its time is rewritten |
| `test_unpack_refuses_links_and_junctions` | R3-006: a junction at a part's folder, and one further down, stop `unpack` before it writes; the junction's target keeps its file |
| `test_import_stores_a_change_that_kept_the_size_and_time` | R3-007: a source changed to the same length and time is stored again |
| `test_verify_finds_missing_extra_and_changed_files` | A missing `.xz`, an unindexed file and a changed plain file are reported; a `README.md` beside the index is not |
| `test_lfs_pointers_verify_by_oid_and_cannot_be_unpacked` | A Git LFS pointer with the right oid and size verifies; `unpack` asks for `git lfs pull`; a pointer to other content is reported |
| `test_import_from_an_inventory_maps_roots_and_prunes` | Inventory sources land under their roots; the packager's own rows and a source in this repository are skipped; a source in no root is an error; `--prune` removes what a re-import no longer brings; a source whose SHA-256 is not the inventory's is refused (R3-007) |
| `test_single_files_and_refused_paths` | `--file` targets; `..`, `//`, drive letters, backslashes, a leading `/` and a part document's name are refused; paths that differ only in case are refused; a part name cannot leave `packages\` |
| `test_the_repository_packages_verify` | Every committed part matches its index. CI checks out without LFS content, so there the `.xz` files are pointers, checked by oid |

**Exit:** 0 when all pass.
