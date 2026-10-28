# verify_install.py

Checks a Steam install against its depot manifests and reports, per file: OK, missing, size
mismatch, content (SHA-1) mismatch, reached through a reparse point, or unverified. Files Steam
marks as user config (for GMod, `garrysmod\cfg\autoexec.cfg`) may differ in content: that is
reported separately (`userconfig_differs`) and never fails the check. Read-only.

Two cases are not vanilla even when the bytes match:

- **`reparse_point`**: a depot file whose path passes through a junction, symbolic link or other
  reparse point at any component below the install root, the file itself included. Steam's file is
  then not at its own path; a link stands in its way. This applies to user-config files too, and
  their content is not read then. Links are never followed to hash what they point to.
- **`unverified`**: an ordinary depot entry that has no SHA-1 in the manifest (Steam writes 20 zero
  bytes) but has a size. Its size can match while its content differs, so it is not counted OK. An
  empty file without a hash is OK, and so is a user-config file without one, since its content may
  differ anyway. The cached GMod manifests had no such entries when this rule was added.

Typical uses: prove an install (or the PoC copy) is vanilla, see what a GMod update changed, and
list the non-depot files someone added to `bin\win64`.

## Usage

```powershell
# manifests are found automatically from appmanifest_*.acf and Steam's depotcache
python tools\steam\verify_install.py "H:\SteamLibrary\steamapps\common\GarrysMod"

# a copy Steam does not manage: borrow the manifests of the Steam-managed install
python tools\steam\verify_install.py "H:\SteamLibrary\steamapps\common\GarrysMod_PoC" `
  --manifests-from "H:\SteamLibrary\steamapps\common\GarrysMod"

# or name manifest files directly
python tools\steam\verify_install.py "<install>" `
  --manifest "C:\Program Files (x86)\Steam\depotcache\4001_7488132547021413298.manifest" `
  --manifest "C:\Program Files (x86)\Steam\depotcache\4002_7341198560151933050.manifest"

# also list files in bin\win64 that no depot ships, and keep the full JSON report
python tools\steam\verify_install.py "<install>" --list-extras bin\win64 --list-extras . --report out\verify.json
```

`GarrysMod_PoC` sits in `steamapps\common`, but Steam does not manage it, so it has no app manifest
of its own. After a GMod update the field install's manifests describe the new build, so verifying
a stale PoC against them reports exactly the files the update changed.

## Output and exit codes

- Prints a JSON summary (counts) and up to 50 paths per category; `--report` writes every path.
  Categories: `missing`, `size_mismatch`, `hash_mismatch`, `reparse_point`, `unverified`,
  `userconfig_differs`, `skipped_symlinks` (entries the manifest itself marks as links), and with
  `--list-extras` `extras`.
- `0` = every depot file matches; `1` = something missing, different, reached through a reparse point
  or unverified; `2` = manifests not found.
- Hashing the full GMod install (about 7.3 GB) takes around a minute on the dev machine.

Tests: [`tests/test_install_tools.py`](tests/test_install_tools.py.md).
