# verify_install.py

Checks a Steam install against its depot manifests and reports, per file: OK, missing, size
mismatch or content (SHA-1) mismatch. Files Steam marks as user config (for GMod,
`garrysmod\cfg\autoexec.cfg`) are reported separately and never fail the check. Read-only.

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
- `0` = every depot file matches; `1` = something missing or different; `2` = manifests not found.
- Hashing the full GMod install (about 7.3 GB) takes around a minute on the dev machine.

Tests: [`tests/test_install_tools.py`](tests/test_install_tools.py.md).
