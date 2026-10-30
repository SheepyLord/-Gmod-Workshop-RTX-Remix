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
| `...\common\GarrysMod` (field) | Steam-managed. All depot files verified vanilla on 2026-10-27, except the user-config `garrysmod\cfg\autoexec.cfg`. Added by the user: DXVK `d3d9.dll` (used for non-RTX play), GModPatchTool's Chromium files including `vulkan-1.dll` and SwiftShader, Jolt physics, MMD Hotloader (`mmdhl_*`), Hammer++/hlmv++, VR DLLs, 44 entries in `garrysmod\addons`, `cfg\addonnomount.txt` with disabled Workshop items. Loader: `bin\win64\winmm.dll` 0.6.0 since 2026-10-29 (0.5.0 and 0.4.0 before, the same day), put there with [`install-loader.ps1`](../tools/install-loader.ps1.md) `-AllowSteamManaged`; 0.5.0's files, config and journal are kept in `out\field-backups\20261029-loader-0.5.0` (with `SHA256SUMS.txt`), 0.4.0's in `out\field-backups\20261029-loader-0.4.0`. The user's `native-loader\config.json` allows 3829070317, 3829275998 and 3829348717. No ReShade |
| `...\common\GarrysMod_PoC` | Vanilla copy for development; see [TESTING.md](TESTING.md) |
| `...\common\GarrysMod_RTX_c` | The user's RTXLauncher-style RTX install with their fork runtime (`bin\win64\d3d9.dll`, about 930 MB of runtime files), root `rtx.conf` / `dxvk.conf` / `user.conf`, `rtx-remix\mods`, custom `stdshader_dx6.dll`, RTX fixes. Reference only |

## Toolchain

| Tool | Where / version |
|---|---|
| VS 2022 Build Tools | `C:\Program Files (x86)\Microsoft Visual Studio\2022\BuildTools`, MSVC 14.44 (cl 19.44), Windows SDK 10.0.26100.0. `vswhere` lists no instance, so [`tools/lib/VsDevEnv.psm1`](../tools/lib/VsDevEnv.psm1.md) probes the folder |
| CMake / Ninja | Bundled with Build Tools: CMake 3.31.6, Ninja 1.12.1 (not on `PATH` outside the dev environment) |
| Python | 3.12 with `pefile`; tests need only the standard library |
| Other | git 2.56 with Git LFS 3.8 (its filters set in the system and user git config), GitHub CLI, .NET SDK, meson. Not installed: 7-Zip, Node, SteamCMD, DepotDownloader |
| Windows Defender | During M1 it blocked proxy builds and test hosts placed outside this repo folder (a sibling worktree, the system temp folder). Inside the repo's `out\` they run, so every build, worktree and test scratch file lives there (AGENTS.md rule 9) |

## Related local checkouts (`H:\BACKUP_20260815\Modding\`)

None of these is needed to build the loader or the RTX package: what ships from them is in
`packages/` ([ADR 0033](decisions/0033-one-repository-package-inputs-in-git-lfs.md)). A part's new
version is imported from them by hand ([packages/README.md](../packages/README.md)).

| Folder | What |
|---|---|
| `dxvk-remix-gmod` | The Remix runtime fork (`sambow23/dxvk-remix-gmod`; its own checkout is on `gmod-1.6.1` with someone's uncommitted work: leave it alone). This project's changes are [runtime/patches](../runtime/README.md) on `gmod-numos3` `c6b48ed1`; its worktree `.claude\worktrees\remix-i18n` (branch `claude/sky-night`) is them applied, with the Release build in `_CompRelease_x64` |
| `garrys-mod-rtx-remixed` | The user's fork of the RTX fixes (GPL-2.0), the source of `packages/fixes` |
| `ipg\` | The user's add-ons, sources of six parts: `!GMHLVK\Gmod-Model-Hotloader-with-Vulkan`, `!advanced_material_editor`, `!advanced_bodygroup_tool`, `!gmod_bullet_break_simulator`, `Gmod-Mmd-Motion-Importer`, `Remove_halo` |
| `RTXLauncher` | The user's fork of the launcher this project replaces |
| `!Gmod-Workshop-RTX-Remix` | Plain clone of this repo's `origin` (only the initial commit) |
