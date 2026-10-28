# crosscheck_gmapack.py

CTest (`nlctl_crosscheck_gmapack`) proving that `nlctl` reads `.gma` archives exactly like the
vendored Python reference, [`tools/gmapack/gmapack.py`](../../../tools/gmapack/gmapack.py.md).

1. Packs two synthetic addons with `gmapack.py create`, each with and without CRCs (`--nocrc`), with
   a fixed timestamp and a required-content entry. One addon has a non-ASCII file name, the other
   uses the package layout (`native/manifest.json`, `native/payload/...`).
2. Wraps each archive in LZMA the way `gmpublish` uploads are stored (`*_legacy.bin`), with and
   without a declared size, using Python's `lzma` module. Adds one copy without the 4-byte CRC
   trailer, as 19 real legacy items are.
3. For every archive, `nlctl inspect --json` must report the same version, SteamID, timestamp,
   required content, title, description, author, addon version, content offsets and file entries
   (number, path, size, CRC, offset) as `gmapack.read_gma()`, plus the right `container`,
   `complete` and `crc_trailer`; `nlctl verify` must pass.
4. Damage: a flipped content byte (verify exit 1 naming the file), a truncated file (`complete:
   false`, verify exit 2), trailing junk (verify exit 1), a file that is no archive (inspect exit 2),
   an LZMA stream missing its last bytes and one with junk after it (verify exit 2).
5. `nlctl scan` counts the intact folder as all parsed (with the right LZMA and no-trailer counts)
   and the damaged folder as two failures plus one archive with trailing data.

GMod's 8-byte LZMA footer is not part of this test because `gmapack.py` rejects it; the C++ unit
tests and the real-data verification in [docs/RESEARCH.md](../../../docs/RESEARCH.md) cover it.

Usage (CTest passes these): `python -I -B crosscheck_gmapack.py --nlctl <nlctl.exe> --gmapack <gmapack.py> --scratch <folder>`.
Writes only below `--scratch` (inside the build tree) and deletes it on success. Exit code 0 on
success; any mismatch exits non-zero with a message.
