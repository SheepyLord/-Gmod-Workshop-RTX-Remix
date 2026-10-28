# Testing

## Levels

| Level | What | How | Since |
|---|---|---|---|
| Conventions | Script docs, module READMEs, links, changelog, component map | `python tools\check_repo.py` | M0 |
| Python unit tests | `tools/**/tests` | `tools\test.ps1 -SkipNative` | M0 |
| C++ unit tests | `nl_tests` (CTest) | `tools\build.ps1` | M0 |
| CLI integration | `nlctl` against synthetic packages and a scratch game folder | CTest (`nlctl_crosscheck_gmapack`, `nlctl_e2e_plan`) | M2 |
| Real-data parse | Read-only parse of every installed Workshop archive (header and index only) | `nlctl scan`, by hand | M2 |
| PoC in-game | Launch `GarrysMod_PoC` with the bootstrap, check logs and behaviour | `tools\smoke_test.ps1` | M1 |
| Field test | The user's real install, with backups and a tested rollback | manual, with the user | M7 |

`tools\test.ps1` runs the first four (the CLI integration tests are CTests) and must pass before any
change is finished.

### M2 core and CLI checks

CTest runs `nl_tests` (62 cases: CRC-32, GMA, LZMA, JSON, paths, manifests, packages, KeyValues,
config, discovery, planner), `nlctl_crosscheck_gmapack` (`nlctl` against `tools/gmapack/gmapack.py`
on generated archives, damaged and LZMA-wrapped ones included) and `nlctl_e2e_plan` (the whole chain
on gmapack-built packages in a fake Steam library). Fixtures are generated; no test reads a game
install.

After changing the GMA or LZMA reader, repeat the read-only real-data parse:

```powershell
out\build\win64-release\loader\cli\nlctl.exe scan "H:\SteamLibrary\steamapps\workshop\content\4000"
```

On 2026-10-27 all 753 archives parsed (672 plain, 81 LZMA-wrapped; 104,847 entries; 19 without the
optional CRC trailer, 1 with trailing bytes). `nlctl verify <archive>` decodes one archive completely
and checks every CRC and, for LZMA, GMod's footer; see [RESEARCH.md](RESEARCH.md) section 5.

### M1 bootstrap checks

`tools/build.ps1` also runs `nl_proxy_tests` (16 pure/export/forwarding/child-host cases),
`nl_proxy_generated_exports` and `nl_proxy_installer` (synthetic roots only). Both configurations
use static CRT. Generate/update committed exports with `python loader/proxy/generate_exports.py`.
Before installation check runtime dependencies with `py -3.12 tools/diag/pe_imports.py
out/build/win64-release/loader/proxy/winmm.dll` on this machine (the Python with `pefile`).

With Steam running and GMod closed:

```powershell
tools\build.ps1 -Config Release
tools\smoke_test.ps1 -Config Release
```

The smoke script performs baseline/enabled/three off-switch map loads and compares two console
tools. Only thumbnail allocation counters and formatting are normalised. Evidence, a machine-readable
summary and original loader/log backups go to `out/smoke/<UTC timestamp>/`; original DLL/PDB, receipt,
disable flag, loader logs and console log are restored even on failure. See
[smoke_test.ps1.md](../tools/smoke_test.ps1.md) for exact side effects and failure behavior.
The script checks actual module absence and complete export resolution in the enabled log.
Antivirus blocking a local build is a test failure requiring review; scripts do not change security
settings or suppress it.

Until the merge into `main` (2026-10-27), M1 was built and tested in its branch worktree
`H:\BACKUP_20260815\Modding\!NVIDIA-RTX-Remix\out\worktrees\m1-bootstrap`. Since then the main
checkout builds the proxy into its own `out\build\<preset>`, which is where `install-loader.ps1` (and
through it `smoke_test.ps1`) takes it from (AGENTS.md rule 9). Chromium helper roles stay inert, and
the real-game smoke check verifies the enabled log's PID against the game process it launched.

## Installs

| Install | Path | Use |
|---|---|---|
| PoC | `H:\SteamLibrary\steamapps\common\GarrysMod_PoC` | All development and in-game tests |
| Field | `H:\SteamLibrary\steamapps\common\GarrysMod` | Only with the user's explicit go-ahead (AGENTS.md rule 1) |
| RTX_c | `H:\SteamLibrary\steamapps\common\GarrysMod_RTX_c` | Reference for the expected look and file set; read-only |

### The PoC install

Built on 2026-10-27 from the field install: the 2,877 files that GMod's depots 4001 and 4002 list
for build 26229091 (x86-64 branch), each copied only after its SHA-1 matched Steam's cached manifest.
That makes it byte-identical to a fresh download. Missing on purpose: `garrysmod\cfg\autoexec.cfg`
(a user-config file the field install has customised; GMod runs without it). Added:
`steam_appid.txt` (`4000`), needed to launch a copy Steam does not manage.

Check that it is still vanilla (everything we deploy is extra, so this stays green until a GMod update):

```powershell
python tools\steam\verify_install.py "H:\SteamLibrary\steamapps\common\GarrysMod_PoC" `
  --manifests-from "H:\SteamLibrary\steamapps\common\GarrysMod"
```

After a GMod update (Steam updates only the field install) the check lists what changed. To rebuild,
delete the PoC folder deliberately, then:

```powershell
python tools\steam\make_vanilla_copy.py "H:\SteamLibrary\steamapps\common\GarrysMod" `
  "H:\SteamLibrary\steamapps\common\GarrysMod_PoC" --report out\poc_copy.json
```

### Launching the PoC (Steam must be running)

```powershell
& "H:\SteamLibrary\steamapps\common\GarrysMod_PoC\bin\win64\gmod.exe" -game garrysmod -console -windowed -w 1280 -h 720 -condebug
```

Start it with the working directory set to the PoC root (Remix reads its configs from there).
The PoC sees the same Workshop subscriptions as the field install; add `-noworkshop` (and
`-noaddons`) to keep GMod from mounting them during loader tests. The loader's own discovery does not
depend on GMod mounting anything.

## Field test protocol (M7, summary)

1. Snapshot `bin\win64` file list and hashes, root configs, `garrysmod\lua\bin`.
2. Install the bootstrap; launch with RTX off first: the existing DXVK `d3d9.dll` must still load.
3. Enable the runtime package; compare against `GarrysMod_RTX_c` on the user's test save.
4. Roll back with `uninstall-loader.ps1`; `verify_install.py` must report the depot files unchanged.
