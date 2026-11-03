# vtf_census.py

Read-only disk inventory for the hotloader's material archives:

```
python tools/vtf_census.py H:/SteamLibrary/steamapps/common/GarrysMod_PoC/garrysmod/data/mmd_hotloader/assets --out out/r12-vram/poc-vtfs.json
```

Selects the highest numbered `materials-v*.gma` in each immediate asset folder; `--all-versions`
includes historical archives too. Reads each GMA's directory and just the first 80 bytes of each
`materials/mmd/t/*.vtf`. Reports the supported single-frame 2D RGBA8888 VTF 7.2/80-byte-header
layout, exact mip texel sizes, dimensions/formats and each archive's contribution. A header whose
declared image does not exactly fit the file, and all other layouts, stay explicitly unsupported.
Deduplicates records by normalized texture path, GMA size and recorded CRC32, and reports any path
with conflicting variants. This is an inventory convention, not cryptographic verification of the
image payload. No image pixels are decoded or modified, no game is run and no material is loaded.

These are **disk/logical texel sizes, not measured residency or GPU allocations**. Historical or
deleted library entries can still have archives. The mounted/drawn subset must be measured in a
session; neither adding every archive nor assuming every source texture is loaded is valid.

Inputs: asset directory and optional all-versions flag. Output: JSON in `--out` and compact summary
on stdout. Creates/replaces that output and its parent, plus transient scratch under this
checkout's `out/tmp` for archive decoding. Standard-library Python and the vendored GMA reader.
Exit 0 success, nonzero on inaccessible/malformed archives. LZMA spooling is explicitly scoped
to that scratch directory; the caller's temporary-file setting is restored.
Imports work with both the package-style CLI path and the already loaded vendored module used
by the repository's combined test suite.
