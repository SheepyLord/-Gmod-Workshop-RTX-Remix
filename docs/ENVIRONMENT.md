# Environment (main development machine)

Facts about the machine this project is developed on, as of 2026-10-27. Update them when they change.

## Garry's Mod

| | |
|---|---|
| Steam library | `H:\SteamLibrary` (other libraries: `C:\Program Files (x86)\Steam`, `D:\SteamLibrary`, `F:\SteamLibrary`) |
| Steam client | `C:\Program Files (x86)\Steam`; depot manifests cached in its `depotcache\` |
| Branch | `x86-64` (64-bit binaries in `bin\win64`), build 26229091 |
| Depots | 4001 content (manifest 7488132547021413298), 4002 binaries (manifest 7341198560151933050) |
| Workshop | `H:\SteamLibrary\steamapps\workshop\content\4000\<id>\*.gma`, 759 item folders; item versions in `...\workshop\appworkshop_4000.acf` |
| GPU | NVIDIA GeForce RTX 5090 (also an AMD integrated GPU) |

### Installs

| Install | State |
|---|---|
| `...\common\GarrysMod` (field) | Steam-managed. All depot files verified vanilla on 2026-10-27, except the user-config `garrysmod\cfg\autoexec.cfg`. Added by the user: DXVK `d3d9.dll` (used for non-RTX play), GModPatchTool's Chromium files including `vulkan-1.dll` and SwiftShader, Jolt physics, MMD Hotloader (`mmdhl_*`), Hammer++/hlmv++, VR DLLs, 44 entries in `garrysmod\addons`, `cfg\addonnomount.txt` with disabled Workshop items. Loader: `bin\win64\winmm.dll` 0.5.0 since 2026-10-29 (0.4.0 before), put there with [`install-loader.ps1`](../tools/install-loader.ps1.md) `-AllowSteamManaged`; 0.4.0's files and journal are kept in `out\field-backups\20261029-loader-0.4.0`. The user's `native-loader\config.json` allows 3829070317, 3829275998 and 3829348717. No ReShade |
| `...\common\GarrysMod_PoC` | Vanilla copy for development; see [TESTING.md](TESTING.md) |
| `...\common\GarrysMod_RTX_c` | The user's RTXLauncher-style RTX install with their fork runtime (`bin\win64\d3d9.dll`, about 930 MB of runtime files), root `rtx.conf` / `dxvk.conf` / `user.conf`, `rtx-remix\mods`, custom `stdshader_dx6.dll`, RTX fixes. Reference only |

## Toolchain

| Tool | Where / version |
|---|---|
| VS 2022 Build Tools | `C:\Program Files (x86)\Microsoft Visual Studio\2022\BuildTools`, MSVC 14.44 (cl 19.44), Windows SDK 10.0.26100.0. `vswhere` lists no instance, so [`tools/lib/VsDevEnv.psm1`](../tools/lib/VsDevEnv.psm1.md) probes the folder |
| CMake / Ninja | Bundled with Build Tools: CMake 3.31.6, Ninja 1.12.1 (not on `PATH` outside the dev environment) |
| Python | 3.12 with `pefile`; tests need only the standard library |
| Other | git 2.56, GitHub CLI, .NET SDK, meson. Not installed: 7-Zip, Node, SteamCMD, DepotDownloader |
| Windows Defender | During M1 it blocked proxy builds and test hosts placed outside this repo folder (a sibling worktree, the system temp folder). Inside the repo's `out\` they run, so every build, worktree and test scratch file lives there (AGENTS.md rule 9) |

## Related local checkouts (`H:\BACKUP_20260815\Modding\`)

| Folder | What |
|---|---|
| `dxvk-remix-gmod` | The user's Remix runtime fork (branch `gmod-1.6.1`) |
| `garrys-mod-rtx-remixed` | The user's fork of the RTX fixes (GPL-2.0) |
| `RTXLauncher` | The user's fork of the launcher this project replaces |
| `!Gmod-Workshop-RTX-Remix` | Plain clone of this repo's `origin` (only the initial commit) |
