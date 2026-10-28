# crosscheck_gmapack.py

CTest (`nlctl_crosscheck_gmapack`) proving that `nlctl` reads `.gma` archives exactly like the
vendored Python reference, [`tools/gmapack/gmapack.py`](../../../tools/gmapack/gmapack.py.md).

1. Packs two synthetic addons with `gmapack.py create`, each with and without CRCs (`--nocrc`), with
   a fixed timestamp and a required-content entry. One addon has a non-ASCII file name, the other
   uses the package layout (`native/manifest.json`, `native/payload/...`).
2. For every archive, `nlctl inspect --json` must report the same version, SteamID, timestamp,
   required content, title, description, author, addon version, content offsets and file entries
   (number, path, size, CRC, offset) as `gmapack.read_gma()`, and `nlctl verify` must pass.
3. Damage: a flipped content byte (verify exit 1 naming the file), a truncated file (inspect says
   `complete: false`, verify exits 2), trailing junk (verify exit 1, 4 trailing bytes), a file that is
   no archive (inspect exits 2).
4. `nlctl scan` counts the intact folder as all parsed and the damaged folder as two failures plus
   one archive with trailing data.

Usage (CTest passes these): `python -I -B crosscheck_gmapack.py --nlctl <nlctl.exe> --gmapack <gmapack.py> --scratch <folder>`.
Writes only below `--scratch` (inside the build tree) and deletes it on success. Exit code 0 on
success; any mismatch exits non-zero with a message.
