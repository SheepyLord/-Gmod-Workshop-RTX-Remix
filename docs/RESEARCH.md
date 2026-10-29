# Research notes

Facts the design rests on, with where they came from, so nobody has to dig them up again. Gathered
2026-10-27 unless a section says otherwise. "Verified" = checked directly (file read, PE parse,
hash); "reported" = from a code-reading pass over the named repo, not re-checked line by line.
External paths are local checkouts under `H:\BACKUP_20260815\Modding\` (see [ENVIRONMENT.md](ENVIRONMENT.md)).

## 1. How GMod x64 loads DLLs (verified)

- PE imports (`tools/diag/pe_imports.py` on build 26229091):
  - `bin\win64\gmod.exe`: `USER32, KERNEL32, ADVAPI32, ole32, WINMM, dbghelp`; delay-load `libcef`.
  - `launcher.dll` adds `WSOCK32`; `engine.dll` adds `WININET`; `client.dll` adds `CRYPT32`.
  - `shaderapidx9.dll`: `d3d9.dll`, `d3dx9_42.dll` (static).
  - The root `gmod.exe` is a small 32-bit launcher (`SHLWAPI`, `KERNEL32` only).
- KnownDLLs on this machine do **not** include `winmm`, `dbghelp`, `wsock32`, `wininet`, `crypt32`,
  `d3d9` or `version`, so for those names the copy in `bin\win64` (the application folder) wins.
- Of the executables in a vanilla `bin\win64`, only `gmod.exe` imports `WINMM`/`dbghelp` directly;
  the tools (hlmv, studiomdl, vbsp, ...) load it through `tier0.dll`. The proxy must therefore
  check its host process.
- Vanilla `bin\win64` contains no `d3d9.dll`, `winmm.dll`, `dbghelp.dll`, `version.dll` or
  `vulkan-1.dll` (checked on the PoC copy).
- Windows binds an import to an already-loaded module of the same base name regardless of folder
  (documented search-order behaviour); M4 confirms it for `d3d9.dll` in practice.

## 2. RTX Remix runtime (fork `dxvk-remix-gmod`, verified unless marked)

- Size of the runtime file set in `GarrysMod_RTX_c\bin\win64`: 40 DLL/EXE files, about 928 MB, plus
  `usd\` (150 files, about 5 MB). Biggest: `d3d9.dll` 323 MB, `nvngx_dlssnr.dll` 254 MB,
  `nvrtc64_130_0.dll` 97 MB, `libxess.dll` 74 MB, `nvngx_dlss.dll` 56 MB, `nvngx_dlssd.dll` 46 MB.
- `d3d9.dll` static imports include `usd_*.dll`, `NRC_Vulkan.dll`, `rtxio.dll`,
  `GFSDK_Aftermath_Lib.x64.dll`, `NvLowLatencyVk.dll`, `libxess.dll`, `vulkan-1.dll`, `dbghelp`,
  `VERSION`, `WINHTTP` and the **VC++ 2015+ runtime** (`MSVCP140`, `VCRUNTIME140`, `VCRUNTIME140_1`);
  delay-load `amd_fidelityfx_vk.dll`. Exports: 116, including the D3D9 set and `remixapi_*`
  (with the fork's `remixapi_imgui_*`, persistent instances, game values).
- Config layers (`src/dxvk/rtx_render/rtx_option_layer.cpp:666-746`): `dxvk.conf` < built-in app
  defaults < `rtx.conf` < base-game-mod `rtx.conf` < programmatic layers < `user.conf`.
  `DXVK_CONFIG_FILE` and `DXVK_RTX_CONFIG_FILE` take comma-separated lists (the last `rtx.conf`
  layer is the one the UI saves to); `user.conf` has no environment override and is opened relative
  to the working directory (`rtx_option_constants.h:115-124`). Reported: a per-user layer
  `%LOCALAPPDATA%\NVIDIA\RTXRemix\user_settings\<hash>.conf` is also read. (Corrected in section 19:
  that file holds only first-use and crash-report flags, and is not an option layer.)
- `rtx-remix\{mods,captures,logs}` default to `./rtx-remix/...` made absolute when `d3d9.dll`
  loads, i.e. relative to the working directory, overridable with `DEFAULT_MODS_DIR`,
  `DXVK_CAPTURE_PATH`, `DXVK_LOG_PATH` (`src/util/util_filesys.h:63-65`, `util_filesys.cpp:106-147`).
- DLSS (NGX) feature DLLs are searched in the folder of `d3d9.dll` (`rtx_ngx_wrapper.cpp:165-191`,
  `env::getDllDirectory()`); NRD is located through the module's own path (`rtx_nrd_context.cpp:62`);
  reported: USD plugins resolve from `d3d9.dll`'s folder (`rtx_mod_usd.cpp:2495-2500`).
- GMod is launched with the game root as working directory, which is where `rtx.conf`, `dxvk.conf`,
  `user.conf`, `imgui.ini` and `rtx-remix\` live in `GarrysMod_RTX_c`.

## 3. RTX fixes (`garrys-mod-rtx-remixed`, GPL-2.0)

- Verified: `gmcl_RTXFixesBinary` gets the Remix API through
  `remix::lib::loadRemixDllAndInitialize(L"d3d9.dll")`, which first calls `LoadLibraryW("d3d9.dll")`
  and so accepts an already-loaded runtime (`public/include/remix/remix_c.h:1143-1147`), then falls
  back to `LoadLibraryExW`/`SetDllDirectoryW` variants.
- Verified: its shaderapidx9 and materialsystem patch sets are disabled in code with
  "these don't apply properly" (`source/culling_fixes.cpp:275-277`).
- Reported: requires Remix API 0.1000.1 (fork only; stock NVIDIA runtimes reject it); applies 8
  in-memory engine/client culling patches toggled by `rtx_patch_*` convars, ported from
  SourceRTXTweaks `patches64` (`source/culling_patches.cpp:81-347`); hooks studiorender, datacache,
  filesystem and D3D9 via MinHook and signature scans; the D3D9 device pointer comes from a
  shaderapidx9 signature; `"d3d9.dll"` is hard-coded in several places; game root = exe path minus
  three components.
- Reported: the Lua side (`garrysmod/addons/remixbinary`) bails out in multiplayer unless the
  binary module is installed, and loads it with `require("RTXFixesBinary")`.
- Reported: the RTX stack also needs root `rtx.conf`/`dxvk.conf`, `rtx-remix\mods\{base_mod,
  ~gmod_topbr, rtx_water, gm_poolrooms_rtx}`, a replacement `bin\win64\stdshader_dx6.dll`
  (fixed-function ports of spritecard, eyes, wireframe and water shaders), and cvars in
  `garrysmod\cfg\autoexec.cfg` (`mat_disable_d3d9ex 1`, `r_shadows 0`, `mat_softwareskin 1`,
  `r_novis 1`, ...).
- Reported: `source/startup_assets` is an earlier `d3d9.dll` proxy that reads GMA v3 and finds
  Workshop items without the Steam API (registry, `libraryfolders.vdf`,
  `ugc/4000_subscriptions.vdf`, `appworkshop_4000.acf`). Reference for behaviour only (licence).

## 4. RTXLauncher (reported)

- Installs into a separate copy of GMod (files copied, big folders symlinked; needs admin or
  Developer Mode). The runtime comes from `SheepyLord/dxvk-remix-gmod` GitHub releases (asset
  `*-gmod.zip`, extracted flat into `bin\win64`); the fixes from the `garrys-mod-rtx-remixed`
  nightly zip, extracted into the game root.
- On-disk binary patches from `applypatch.py` (`patches64` from `sambow23/SourceRTXTweaks`):
  hex signatures with `??` wildcards that must match exactly once, length-preserving; plus
  `MaterialSystemFallbackPatch` (x64 only), which caps recursive `$fallbackmaterial` loads.
- Launches `bin\win64\gmod.exe -game garrysmod -console -dxlevel 90 +mat_disable_d3d9ex 1 -nod3d9ex
  -windowed -noborder -noworkshop` with the working directory at the copy's root.
- Updates break because copied binaries go stale against updated VPKs, signatures drift, and
  "update install" can overwrite the fixes' `stdshader_dx6.dll`.

## 5. Workshop and GMA facts (verified)

- Installed items, census of all 759 item folders under `steamapps\workshop\content\4000\<id>\`:
  672 hold one plain GMAD `<name>.gma`; 81 hold an LZMA-wrapped `<hash>_legacy.bin` (older
  uploads; all 81 start with the LZMA properties byte `0x5D`); 6 hold loose files only. The largest
  item is 3.2 GB. `nlctl scan` (M2) parsed all 672 `.gma` indexes, 98,656 entries, in 2.8 s with no
  errors. (An earlier sample of 400 `*.gma`/`*.bin` files, "358 GMAD, 42 LZMA", mixed the two kinds.)
- The 81 `*_legacy.bin` files: LZMA-alone header with properties `0x5D` (lc 3, lp 0, pb 2), 16 MiB
  (19 files) or 32 MiB (62) dictionaries, size always declared (largest 376 MB; 4.4 GB decoded from
  1.5 GB in total). Every file ends with an **8-byte GMod footer** after the LZMA stream: the
  decompressed size as a 32-bit little-endian value, then the magic `0xBEEFCACE` (Bootil's writer).
  `tools/gmapack/gmapack.py` treats those 8 bytes as trailing data, so it cannot read any installed
  legacy item; `nl_core` accepts the footer only when it matches exactly.
- **The archive CRC trailer is optional in practice:** 19 of the 81 legacy items (GMAD v3,
  uploaded 2012-2019) end right after their last file, without the 4-byte CRC, and GMod mounts them.
  One legacy item (1136617425) has a matching CRC trailer followed by four zero bytes of padding.
- `nlctl scan` over all 753 installed archives (2026-10-27): every one parses (672 plain, 81 LZMA,
  104,847 file entries); 19 without trailer, 1 with trailing bytes. `nlctl verify` (Release) over
  all 81 legacy items decoded 4.4 GB in 66 s: 6,191 file CRCs and every footer match; the only
  finding is the padded item above.
- `steamapps\workshop\appworkshop_4000.acf` records per item `size`, `timeupdated` and `manifest`.
  What happens to it when the user subscribes and unsubscribes: section 22.
- `garrysmod\cfg\addonnomount.txt` lists the Workshop ids the user disabled.
- `gmad.exe` only packs whitelisted file types (`.dll`/`.exe` are not); the GMod wiki lists
  DLL and EXE files as restricted for Workshop items. Whether `gmpublish` or the Workshop rejects a
  `.gma` built with other tools is untested (M6).
- GMod launch options `-noworkshop` and `-noaddons` disable Workshop and folder addons for a session.

## 6. Steam depot manifests (verified)

- Cached at `<Steam>\depotcache\<depot>_<manifest>.manifest`; the installed ids are under
  `InstalledDepots` in `steamapps\appmanifest_<appid>.acf`.
- Binary layout: `uint32 0x71F617D0`, `uint32 length`, protobuf `ContentManifestPayload`
  (field 1 = file mapping: 1 filename, 2 size, 3 flags, 5 SHA-1 of content, 6 chunks), then
  `0x1F4812BE` + metadata (1 depot id, 2 manifest id, 4 filenames encrypted). A signature block
  (`0x1B81B817`) and an end marker (`0x32C415AB`) follow, per SteamKit2; our parser does not read
  them. GMod's manifests have plaintext filenames (backslash-separated).
- Flags used: 0x1 user config, 0x40 directory, 0x200 symlink.
- Result on 2026-10-27: 2,877 of 2,878 depot files in the field install matched; the exception was
  the user-config `autoexec.cfg`.

## 7. M1 bootstrap measurements (2026-10-27, Codex)

- Export source: `C:\Windows\System32\winmm.dll`, file version
  `10.0.26100.8875 (WinBuild.160101.0800)`, on Windows build **26300.9711**, display version 26H2
  (registry `CurrentBuild`, `UBR`, `DisplayVersion`; the legacy `ProductName` says Windows 10 Pro).
  The standard-library generator measured **181 populated ordinals**, **180 names**, and **one
  ordinal-only export** (ordinal 2). Inventory: `loader/proxy/generated/exports.json`; generation
  and build-time coverage check: `loader/proxy/generate_exports.py`.
- Independent initial C++ test: `covered 181 system ordinals and 180 names`; forwarding calls
  `timeGetTime`, `timeBeginPeriod(1)`, `timeEndPeriod(1)`, `waveOutGetNumDevs` and
  `mmsystemGetVersion` passed with distinct system/proxy module handles. The initial synthetic
  `gmod.exe` test also passed its log-before-main and absent-engine/shader-API/D3D9 assertions.
  This is synthetic-host evidence, not an enabled PoC result. Test source:
  `loader/proxy/tests/test_proxy.cpp`.
- Debug and Release proxy imports measured by `py -3.12 tools/diag/pe_imports.py`: **KERNEL32.dll
  only**, no static/delay VC++ runtime DLL imports. CMake's static CRT and MASM leaf jumps suffice.
  Python on PATH is now Miniconda 3.14.6 (without `pefile`); the existing `py -3.12` installation
  has `pefile`. No packages were downloaded or installed.
- Baseline PoC map launch (PID 20836, Steam running) reached this ordered sequence:
  `Map: gm_construct`, `Clientside Lua startup!`, joystick initialization,
  `Redownloading all lightmaps`, `Thumbs: 58711 => 58770`. The smoke test requires the map and
  client-Lua markers, then gives post-map output three seconds to flush
  (`tools/smoke_test.ps1`, `Invoke-GameRun`). It normalises only formatting and the numeric
  thumbnail allocation counters (`Normalise-Console`). This strict comparison still needs an
  enabled PoC run; do not assume additional varying lines are harmless.
- PoC `vpk.exe` and `bspzip.exe` statically import `tier0.dll`; PoC `tier0.dll` imports `WINMM.dll`
  (`py -3.12 tools/diag/pe_imports.py` on those three files). No-argument baseline runs exit by
  themselves with codes **1** and **-1**, respectively. Raw stdout/stderr are retained under
  `out/baseline/`; enabled comparisons remain pending.
- Windows Defender blocked the initial Debug proxy at 18:09 local time as
  **Trojan:Win32/Bearfoos.A!ml**, threat id **2147731250**. Subsequent load/copy tests failed with
  Windows' virus/potentially-unwanted-software error. Evidence: `Get-MpThreatDetection` resources
  named the Debug build and the `nl-proxy-测试-*` fixture copies; `Get-MpThreat` reported it active.
  The detection needs human review before further native runtime validation; no antivirus
  configuration was changed. See [M1-report.md](handover/M1-report.md).
- Resumed after the user reported excluding the main checkout: Release passed **11/14** proxy
  cases (including entry timing and all off switches) before fresh detections blocked its remaining
  fixtures and removed the Release DLL in the sibling M1 worktree. Debug passed 7/14; both full
  suites still failed. `0xc0000906` is `STATUS_VIRUS_INFECTED` (installed Windows SDK
  `shared/ntstatus.h:11558`). The new detections name the sibling `!NVIDIA-RTX-Remix-M1` and
  `%TEMP%/nl-proxy-测试-*`, outside the main checkout path the user named. Full logs:
  `out/m1-full-debug-tests.txt`, `out/m1-full-release-tests.txt`.

## 8. M1 final validation and Chromium roles (2026-10-27, Codex)

- Per the user's requested output root, the active `m1-bootstrap` worktree is now
  `H:\BACKUP_20260815\Modding\!NVIDIA-RTX-Remix\out\worktrees\m1-bootstrap`. All builds, installer
  fixtures, host fixtures and evidence stay below it. The earlier sibling worktree/build was
  removed. Seven hash-verified legacy host executables were moved from `%TEMP%` to
  `out/prior-validation/legacy-fixtures` (SHA-256
  `5AA6BAD58029EF96C6DC4936B769C5522BD51094F8EC23658880AA860AB78FF4`), preserving them after
  automatic approval review rejected deletion. No generated executable remains in those temp roots.
- GMod's Chromium processes reuse **the same `bin\win64\gmod.exe`**, with roles such as
  `--type=utility --utility-sub-type=network.mojom.NetworkService`. They do not inherit the parent's
  `-nonativeloader` switch. The first real smoke run showed a helper PID replacing the main log
  (`out/smoke/20261028T012617409Z/off-command.loader.log`). A path-only host gate therefore lets a
  helper run the bootstrap even when the main launch is disabled.
- Fixed by treating `--type=value` / `--type value` roles as pure pass-through, using the same
  allocation-free token parser (`loader/proxy/activation.cpp:89`). Prefix near-misses and quoted
  text are covered, plus four child-role integration runs. The smoke check now requires the log PID
  to equal the launched game PID (`tools/smoke_test.ps1:117`). No hook/forwarding technique changed.
- Debug and Release: **4/4 CTest entries pass**, including **16 proxy cases** and **23 installer
  assertions**. The full Debug runner also runs **56 Python tests** (one pre-existing skip).
  Test discovery needed a repository-relative exclusion filter because the selected worktree has
  an ancestor named `out` (`tools/test.ps1:38`); filtering full absolute paths had hidden Python suites.
- Final Release PoC smoke evidence: `out/smoke/20261028T012849979Z/summary.json`:
  `success=true`, `restored=true`; all five launches reach `gm_construct`; console output matches
  after the documented normalization; all off switches produce no log; both tools match baseline.
  Map-load-plus-settle durations: baseline **6.59s**, enabled **6.56s**, command-off **6.53s**,
  environment-off **6.72s**, file-off **6.57s**. These are smoke durations, not benchmark results.
- The enabled log is from main PID **64992**, resolves **181/181** exports, and samples
  `engine.dll=0`, `shaderapidx9.dll=0`, `d3d9.dll=0` at the EXE entry point. Logged startup work:
  **0.2898ms**. Its command line contains the actual `-game garrysmod ... +map gm_construct`
  launch, not a Chromium helper role. Both final configurations still import **KERNEL32.dll only**.
- Final installed and uninstalled verifier reports each have **2,877 OK**, **0 missing**, **0 size
  mismatches**, **0 hash mismatches**, with the existing `autoexec.cfg` user-config difference.
  Evidence: `out/m1-poc-installed-verify.json`, `out/m1-poc-uninstalled-verify.json`. The PoC is left
  with no bootstrap DLL/PDB or loader state. Installed Release DLL SHA-256:
  `E9B1327A89853344DD967D4B6C5C8E48E52F49849C208EA7605B61EF278A3351`.

## 9. M3 deployment measurements (2026-10-27, Claude)

**Release `nlctl`, this machine, a package with a 323 MiB payload file** (the size of the runtime's
`d3d9.dll`, section 2) in a plain `.gma` in a scratch game folder:

| Command | Time | What it does |
|---|---|---|
| `apply`, first | 1.75 s | extract, check size, CRC-32 and SHA-256, flush, place |
| `apply`, again (no-op) | 44 ms | 0 file-system changes, journal untouched |
| `status` | 13 ms | size and time of every recorded file |
| `status --verify` | 231 ms | SHA-256 of every file: about 1.4 GB/s with CNG on cached data |
| `uninstall` | 0.32 s | a full SHA-256 of each file before it is deleted |

The full 930 MB runtime should therefore deploy in about 5 s from a plain archive. From an
LZMA-wrapped one it takes longer, decoding at about 67 MB/s (section 5).

**Process costs.** In a Debug build a deployer command costs about 30 ms before it does any work:
the process start, plus one Toolhelp scan of all processes for the running-game check. Most of the
rest of a tiny deployment is durability: about 15 flushes and write-through renames per apply.
`test_deploy.cpp` therefore runs its thousands of in-process deployments on a file system without
flushes (`FastDisk`), and the test host skips the process scan.

**Change counts.** The fault test's scenarios, killed by `TerminateProcess` before each change; every
one ended in the old or the new state after recovery:

| Scenario | File-system changes |
|---|---|
| first deployment (runtime + root-files package) | 54 |
| upgrade (new runtime folder; root files replaced, added, removed) | 59 |
| rollback | 26 |
| uninstall | 35 |

**PoC acceptance.** The test package held a payload file, a mod file, a binary Lua module and a
create-only cfg file. The bootstrap install, `apply` and uninstall made 58 changes, the second apply
none. All 3,113 files and folders of `GarrysMod_PoC` were identical afterwards, sizes and times
included, and 2,877 depot files verified OK. Evidence: `out/poc-deploy/20261028-043358/` (the run
after the review fixes; the first run, `20261028-035222`, made 54 changes before payload files were
moved one by one).

**Windows behaviour the deployer relies on:**

- `MoveFileExW` without `MOVEFILE_COPY_ALLOWED` renames only within a volume, which is why staging
  lives under the game folder and links are refused there.
- `GetFileAttributesExW` reports a junction itself, not its target.
- A file opened with `FILE_FLAG_OPEN_REPARSE_POINT` is the link itself, so hashing refuses links.
- An exclusive handle (share mode 0) on `native-loader\lock` makes a second deployer fail with
  `ERROR_SHARING_VIOLATION` until the first one's process ends.
- The running-game check snapshots processes with Toolhelp and opens each `gmod.exe` for its image
  path. A process that exits between the snapshot and `OpenProcess` fails with
  `ERROR_INVALID_PARAMETER`, and only `ERROR_ACCESS_DENIED` means "cannot tell". Under parallel
  CTest, M1's proxy tests run short-lived synthetic `gmod.exe` processes. Treating every failed
  open as "running" made `nlctl_e2e_deploy` refuse now and then.
- Windows may keep an executable's image file locked for a moment after its process ends;
  `e2e_deploy.py` retries putting its placeholder `gmod.exe` back.

## 10. M4 activation research (2026-10-27, Claude)

Gathered while planning M4; scripts were one-offs under `out\tmp` (`pefile`, `ctypes`), read-only.

**Who reads the command line, and when** (PoC, build 26229091):

- `gmod.exe`, `launcher.dll`, `tier0.dll`, `vstdlib.dll`, `engine.dll`, `filesystem_stdio.dll`,
  `materialsystem.dll`, `shaderapidx9.dll` and `client.dll` each import both `GetCommandLineA` and
  `GetCommandLineW` from KERNEL32. `tier0.dll` exports `CommandLine`, `Plat_GetCommandLine` and
  `Plat_GetCommandLineA`; all the others except `gmod.exe` import `CommandLine` from it.
- None of `gmod.exe`, `launcher`, `tier0`, `vstdlib`, `engine`, `shaderapidx9`, `client` imports a
  C runtime DLL (`ucrtbase`, `api-ms-win-crt-*`, `vcruntime*`, `msvcp*`): they link it statically.
  `gmod.exe`'s static imports are only system DLLs and `WINMM` (ours); `launcher.dll` and the
  engine load later. So no engine module has read or cached the command line when our entry-point
  hook runs.
- kernelbase on this machine (Windows 10.0.26300.9711): `GetCommandLineW` is `48 8b 05 41 9f 2b 00 c3`
  and `GetCommandLineA` is `48 8b 05 41 08 2b 00 c3` (`mov rax,[rip+disp32]; ret`); KERNEL32's exports
  of the same names are `jmp [rip+x]` thunks to them. The pointer each returns sits at rva `0x3ae058`
  (W) and `0x3ae048` (A), as the `Buffer` of a `UNICODE_STRING` / `ANSI_STRING`: the 8 bytes before
  each slot hold `Length` = the string's length in bytes (202 and 101 for a 101-character command
  line) and `MaximumLength` = `Length` + one terminator.
- RTXLauncher passes `-dxlevel 90 +mat_disable_d3d9ex 1 -nod3d9ex` (section 4).

**How the runtime takes its config layers** (fork `dxvk-remix-gmod`):

- `resolveConfigPaths` (`src/dxvk/rtx_render/rtx_option_layer.cpp:617-627`): when
  `DXVK_RTX_CONFIG_FILE` (or `DXVK_CONFIG_FILE`) is set and not empty, the runtime reads only the
  paths it lists, split at commas; `.\rtx.conf` is read only when the variable is unset. So a loader
  that sets the variable must list the user's root `rtx.conf` itself.
- (Corrected in section 19: for `rtx.*` options the **first** listed path is the strongest, not the
  weakest.) `createLayersFromEnvVar` (`:629-647`) makes one layer per listed path, lowest priority first; the
  last `rtx.conf` layer becomes `s_rtxConfLayer` (`:704-712`), the one the Remix menu saves to. A
  layer whose file is missing or empty is registered but not merged (`isValid()` is "has options",
  `rtx_option_layer.h:141`).

**The runtime's files** (`H:\BACKUP_20260815\Modding\dxvk-remix-gmod`):

- `_output` is the complete runtime: 192 files, 1,117,358,408 bytes, built 2026-10-26 23:36, with
  `usd\` and the build by-products `d3d9.pdb`, `.exp`, `.lib`. Nothing the classic install keeps in
  `GarrysMod_RTX_c\bin\win64` for the runtime is missing from it.
- `_CompRelease_x64\src\d3d9\d3d9.dll` (338,675,200 bytes, 2026-10-27 11:32) is the newest build and
  the same file as `built-A8E39D93-lockfree-options\d3d9.dll`. The `built-*` and `deployed-*` folders
  hold only `d3d9.dll` and `d3d9.pdb` (140,800,000 bytes for A8E39D93).
- `d3d9.dll`'s only delay-load import is `amd_fidelityfx_vk.dll`, loaded by bare name; its static
  imports include the UCRT API sets (`api-ms-win-crt-*`) besides the VC++ runtime of section 2.
- `msvcp140.dll`, `vcruntime140.dll`, `vcruntime140_1.dll` and `vulkan-1.dll` are only in System32 on
  this machine, not in the PoC's or `GarrysMod_RTX_c`'s `bin\win64`; the classic install keeps
  `amd_fidelityfx_vk.dll` in `bin\win64`.
- `GarrysMod_RTX_c\bin\win64` holds 77 files (3.63 GB) beyond vanilla: the runtime mixed with
  backups, PDBs, Jolt, the MMD hotloader, VR files, `NvRemixBridge`, `dxsupport.cfg` and a
  `debug.log`. A runtime package therefore takes an explicit file set (`_output`), not that folder.
- `GarrysMod_RTX_c` has the user's `rtx.conf` (161,131 bytes) and `dxvk.conf` (2,610 bytes) in its
  root, the layers the classic install runs with.

## 11. M4 implementation and acceptance findings (2026-10-28, Codex)

- Section 10's cached-string layout is now checked before any write, including the PEB descriptor.
  Synthetic descriptor tests cover mismatched Length/MaximumLength/pointer, USHORT overflow and a
  failure after a partial write. A separate process swaps the real kernelbase W/A and PEB records,
  checks updated lengths and restores their exact bytes (`loader/core/src/cmdline.cpp:96`,
  `loader/tests/cmdline_host.cpp`). The user approved loader version 0.1.0 to match the packager's
  existing `requires_loader >=0.1.0` contract.
- Debug and Release pass **15/15 CTest entries**. Core cases total **120** (117 normal plus three
  exhaustive fault groups); proxy cases remain **16**, installer assertions **23**. Python: **66**
  tests, one pre-existing skip. The PE CTest confirms the final bootstrap imports only KERNEL32.
  Steam registry lookup now dynamically resolves RegGetValueW from System32 advapi32
  (`loader/core/src/discovery.cpp:40`).
- The packaged fake runtime proves bare-name d3d9 reuse, static and delay dependency paths, user
  layers/arguments, full failure rollback, explicit fallback options, all off switches, contention,
  source disappearance/removal and version/hold behavior. **17 scenario groups** pass. Isolated
  Release evidence: `out/m4-synthetic/release-62268/summary.json`; ten unchanged-deployment samples
  have **25.8064 ms median**, **19.8476–27.9013 ms** range, zero deployment operations. Timing ends
  before final report I/O. Raising a native exception in the fake DLL initializer produced Windows
  error **1114** and verified vanilla continuation with restored settings.
- The named B folder was absent. Section 10's alternate `_CompRelease_x64/src/d3d9/d3d9.dll` was
  present with the documented size/time and the **A8E39D93** prefix. Full hashes used:
  - A: `E5C65136EA8BC7A7485776C18F975FE8068F74B5743DC8EA536AAFF8D6065BCA`;
  - B: `A8E39D938D96193DF27D245A7F6E72F1C44B75FB2D066A67BDC2CD974EDEA267`.
  The acceptance script pins the full B hash before accepting this alternate copy. No fork file
  was changed. Config snapshots were hash-checked and reused for both packages.
- Real evidence is under `out/poc-activation/20261028T075336206Z/`. Original A contains **191 files,
  977,303,948 bytes** without PDBs; B has **191 files, 977,403,788 bytes**. These measured sizes
  supersede the earlier rough full-runtime estimate for this recipe.
- The user approved each actual launch and explicitly requested **-multirun**, keeping the RTX_c
  install open. Vanilla PoC PID **6876** reached gm_construct with System32 d3d9 and **mat_dxlevel 95**.
  The initial A PID **70300** deployed generation 1 in **4808.77 ms**, activated in **36.5178 ms**,
  and completed startup in **4846.04 ms**. The engine printed **mat_dxlevel 90**, proving it saw
  the injected arguments. Remix logged an RTX 5090 device, successful Reflex initialization,
  ray-tracing feature support and swapchain creation, then the engine exited before map completion.
- The copied classic DXVK config has **d3d9.shaderModel = 0** (snapshot line 10). The fork rejects
  shader bytecode above that option (`src/d3d9/d3d9_shader.cpp:115`), explaining the logged
  “GetShaderModule: Out of range of supported shader model” errors. Its default is **3**
  (`src/d3d9/d3d9_options.cpp:69`). Windows event 1000 recorded a PoC engine.dll fault with
  exception **0xc0000409**; the exact engine termination cause was not independently debugged.
- After §9 consultation, the user approved a **PoC-only shaderModel=3 layer** and one A retry.
  It kept both reference configs unchanged and added one 132-byte layer. PID **31480** reached
  gm_construct at **mat_dxlevel 90**. Deployment: **4920.9048 ms**; activation: **39.4931 ms**.
  All **34** loaded runtime DLLs in `03-RunA/runtime-modules.json` came from the versioned package,
  including d3d9, amd_fidelityfx_vk, NvLowLatencyVk and the DLSS family.
- The user reported **not path-traced/rendering incorrectly**, then stopped further PoC testing.
  Real RTX-off output, **dxlevel persistence**, B activation and rollback therefore remain open.
  Startup activation success is not evidence of successful later rendering.
- Cleanup removed 383 package files and the bootstrap/control/status state. `verify.json` reports
  **2,877 OK**, **0 missing**, **0 size mismatches**, **0 hash mismatches**, with the existing
  autoexec.cfg user-config difference. `created-or-changed.txt` records preserved Remix/Sentry logs,
  capture directories, engine crash artifacts, metrics and game-written config/cache/console changes.
  No game/Remix data was deleted for cleanup. The other RTX_c instance remained running.

## 11. Session side effects and automation (2026-10-28, Claude)

**Settings GMod keeps between sessions.**

- GMod's video settings are in `HKCU\Software\Valve\Source\garrysmod\Settings` (`ScreenWidth`,
  `ScreenWindowed`, `mat_*`, `DXLevel_V1`, ...). The key has the mod folder's name, so the field
  install, the PoC and `GarrysMod_RTX_c` all share it.
- `DXLevel_V1` does not decide the level a session runs at. With 90 stored (since 2026-10-27 02:02),
  vanilla PoC sessions ran at `mat_dxlevel 95` (Codex's baseline, and run 1 below) and wrote 95 back
  at start-up; a session started with `-dxlevel 90` ran at 90.
- `-dxlevel 90` does not carry over: three PoC sessions, vanilla, `-dxlevel 90 -nod3d9ex
  +mat_disable_d3d9ex 1`, vanilla again, ran at 95, 90 and 95, and neither the registry key nor
  `config.cfg` changed (evidence `out\m4-review\persistence-20261028T040607`; the key was restored
  from the backup taken first).
- Archived console variables persist in the install's own `garrysmod\cfg\config.cfg`, which the game
  writes when it quits normally. The PoC's already held `mat_disable_d3d9ex "1"` before M4; a vanilla
  session then reports `"mat_disable_d3d9ex" = "1" ( def. "0" )` and "mat_disable_d3d9ex changes will
  not take effect until application restart": the variable is read when the device is created,
  before `config.cfg` or `+` commands run. So `+mat_disable_d3d9ex 1` on the command line only changes
  the next session (through `config.cfg`), while `-nod3d9ex`, which `shaderapidx9.dll` reads (both
  strings are in it), acts on the current one.

**Ending a session without a person.**

- `game.ConsoleCommand("quit\n")` from server Lua is refused: `game.ConsoleCommand blocked! (quit)`.
- The menu state loads a fixed list of files (`lua/menu/menu.lua`); `RunGameUICommand("QuitNoConfirm")`
  exists only there, so it cannot be reached without changing depot files.
- `WM_CLOSE` to the main window (`CloseMainWindow`) does not end the game (15 s; Codex saw the same).
- Source's TCP remote console does: with `-usercon -ip 127.0.0.1 -port <p> +rcon_password <x>` and a
  listen server (`+maxplayers 2`), an RCON `quit` ends the session normally (exit code 0). In a
  single-player session the remote console does not listen (connection refused).
  [`tools/poc_session.py`](../tools/poc_session.py.md) uses this.

**Shader DLLs.** A vanilla session at `mat_dxlevel 95` loads `stdshader_dx6.dll` too, by full path:
the module list shows `h:\steamlibrary\steamapps\common\garrysmod_poc\bin\win64\stdshader_dx6.dll`,
lower-cased by the engine's file system.

**Windows loader.** At an `LdrRegisterDllNotification` "loaded" callback, the new module's imports
are already bound (`wininet.dll`: 355 of 355 import address table entries resolved, Windows
10.0.26300). An import hook installed then is in place before the module's own code runs.

## 12. What the classic RTX install adds (M5 research, 2026-10-28, Claude with a research agent)

Compared with the PoC (vanilla build 26229091). "Verified" as in the header; offsets are PoC file
offsets or RVAs as stated.

**`GarrysMod_RTX_c` runs an older GMod build.** Of its engine binaries only `tier0.dll` matches a
cached depot manifest; its VPKs (`garrysmod_000-002`, `fallbacks_*`, `sourceengine\content_hl2_dir`)
differ from the PoC's too. Its runtime is B (`d3d9.dll` SHA-256 `a8e39d938d96193d...`).

**On-disk engine patches.** RTXLauncher applies `patches64` from `sambow23/SourceRTXTweaks`
(`applypatch.py`, fetched at install time; no local copy). Each pattern must match exactly once;
RTX_c holds each in patched form. All seven match exactly once in the PoC's build:

| DLL | Pattern (offset) | Replacement | Purpose |
|---|---|---|---|
| engine | `ff90????????85c0742b` (0) | `b80200000090` | `Mod_LoadLighting`: HDR type 2 |
| engine | `ff90????????85c00f84fa000000` (0) | `b80200000090` | `Mod_LoadWorldlights`: HDR |
| shaderapidx9 | `4833cce8????03004881c448` (0) | `85c0750466b80400` | zero-sized buffer returns 4 |
| shaderapidx9 | `4883ec084c` (0) | `31c0c3` | shader constants function returns 0 |
| shaderapidx9 | `4885db75??498b4500` (3) | `eb` | skip the invalid-vertex-format `Error()` |
| materialsystem | `f77c24683bc10f4fc1488b8c24300100004833cce8????04004881c448010000` (0) | `448b4424684585c0740341f7f839c80f4fc14881c448010000c3` | zero-sized buffer guard |
| datacache | `647838302e767478` (0) | `647839302e767478` | `dx80.vtx` to `dx90.vtx` |

`MaterialSystemFallbackPatch` does not apply to either build (a 2-byte `66 90` where it needs a
15-byte site) and was never applied to RTX_c. The fixes' module applies 8 other, in-memory
engine/client culling patches itself (`source/culling_patches.cpp:81-347`, from `module.cpp:427`);
`source/culling_fixes.cpp` (with "these don't apply properly") is dead code: `CullingHooks` is never
initialised (corrects section 3).

**How `stdshader_dx6.dll` is loaded.** `materialsystem.dll`'s `LoadAllShaderDLLs` (rva `0x4b010`)
asks for `stdshader_dbg.dll`, then `stdshader_dx6.dll` up to the dx level, through
`IFileSystem::LoadModule` (vtable +0xe8). `filesystem_stdio.dll` resolves the name against the
`EXECUTABLE_PATH` search path (`bin\win64`, added first by `launcher.dll`) and calls
`LoadLibraryExA(<full path>, NULL, LOAD_WITH_ALTERED_SEARCH_PATH)` from its `Sys_LoadModule` (rva
`0x5ebe0`; the call at `0x5eb02`). Preloading a copy elsewhere therefore does not help; an import hook
on `filesystem_stdio.dll`'s `LoadLibraryExA` does. `LoadLibraryExA` is also imported by materialsystem,
engine and launcher, `LoadLibraryA` by tier0, engine and shaderapidx9, none delay-loaded.

**The fixes' shader DLL.** A binary committed in the fixes at `garrysmod/bin/win64/stdshader_dx6.dll`
(byte-identical to RTX_c's, 437,248 bytes; sources removed in 4b9da1e, readme points to
`sambow23/obsolete-source-engine`): fixed-function ports of spritecard, eyes/eye_refract, wireframe
and water. It finds `gmcl_RTXFixesBinary_win64.dll!RTX_SetEyeTexGenState` by that module name at run
time. With RTX_c's `dxvk.conf` (`d3d9.shaderModel = 0`, line 10) RTX_c's own Remix log also shows
"Out of range of supported shader model" (28 times), so that message is normal there.

**The fixes' other pieces.** `gmcl_RTXFixesBinary_win64.dll` (1,441,792 bytes in RTX_c, built
2026-10-27), `gmcl_rtxwater_win64.dll`, `gmcl_rtxdebug_win64.dll` (all import only tier0, ole32,
KERNEL32). Lua: `addons/remixbinary/lua/autorun/cl_rtx.lua` (`require("RTXFixesBinary")` at :10,
multiplayer guard at :4), rtx_water (`cl_native.lua:37-42`), niknaks and others. Remix mods from the
fixes: `base_mod` (37 MB), `rtx_water` (11 MB), `gm_poolrooms_rtx` (150 MB), `~gmod_topbr` (87 files
in the repo; ToPBR writes generated DDS files there at run time). `autoexec.cfg` is the fixes' file:
`sv_cheats 1`, `mat_disable_d3d9ex 1`, `r_3dsky 0`, water reflection/refraction 0, `r_shadows 0`,
`mat_softwareskin 1`, specular/bump/normal/parallax 0, `r_frustumcullworld 0`, `r_occlusion 0`,
`r_novis 1`, plus the user's own settings. The fixes also overwrite five Steam files (menu
`problems.lua`, sandbox `gmod_camera.lua`, three images), which this project's rule 2 forbids.
Built with premake 5 and garrysmod_common, VS 2022; no release zip locally.

**The user's test save and measure.** Reference save
`GarrysMod_RTX_c\garrysmod\saves\gm_csgosafehouse 2026-10-25 04-08-30.gms`. Harness
`C:\Users\matt-peng\.rpai\work\_probe\session_run.py` (fixed camera `REF_CAMERA`, captures with the
`jpeg` command, HUD and view model hidden). Measure `look\compare.py`: crop both images to a multiple
of 32, take the mean RGB of every 32x32 block, report the mean absolute difference over all blocks and
channels (0-255); about 1 between repeated captures, 1.5-3.6 "close", 16-26 "broken". The save needs
the Workshop map 944959992 (a legacy `.bin`, 162 MB, in the shared Workshop folder), the CS:GO mount,
the user's `SafeHouse` Remix mod, and the MMD Hot Loader character with its `ai_pbr` mod. The classic
install's launch line (`_debug_tools\launch_gmod_keeplogs.bat:12`) is `-console -condebug -dxlevel 90
+mat_disable_d3d9ex 1 -nod3d9ex -windowed -noborder -w 3840 -h 2160 -tickrate 128 -multirun -insecure
+r_forcehwlight 1`; RTXLauncher adds `-noworkshop` only when its `LoadWorkshopAddons` is false (the
user's is true; corrects section 4).

## 13. M5 on the PoC (2026-10-28, Claude)

**Add-on mounting.** GMod x64 mounts an add-on **folder** in `garrysmod/addons` ("Adding Filesystem
Addon 'addons/nl_probe_folder'", its client autorun ran) but not a loose `.gma` placed there, plain
Lua or not (no message, the Lua did not run): `out/poc-sessions/m5-mount-probe`. Local packages
therefore deploy their Lua as add-on folders ([ADR 0011](decisions/0011-lua-addon-folders.md)).

**`SetDllDirectoryW` broke the RTX fixes.** garrysmod_common's `ModuleLoader.cpp` finds GMod's
modules with `GetModuleHandleExA(0, "bin/win64/lua_shared.dll", ...)`, a path relative to the working
directory. With M4's `SetDllDirectoryW(<runtime folder>)`, which also drops the working directory from
the DLL search, that lookup failed: the fixes' module printed "Failed to get ILuaConVars interface" and
"Failed to create or find convar" for its 15 variables, and the game ended with `0xC0000409` right
after the map loaded. With the runtime folder first on `PATH` instead, the module reports "Got
ILuaConVars interface" and every variable ready, and the session quits normally
([ADR 0010](decisions/0010-rtx-session-extras.md) point 4).

**The loader's RTX session on the PoC** (runtime B with the reference install's `rtx.conf` and
`dxvk.conf` as layers, the fixes package built from the fixes repo with `GarrysMod_RTX_c`'s modules,
the reference install's user content copied by [`poc_parity.py`](../tools/poc_parity.py.md)):

- First start deployed both packages (445 changes, 1.43 GB) in 7.3 s, activation 31 ms; a later start
  changed nothing, deployment 54 ms, start-up 80 ms in all.
- All 7 patch sets applied (engine 2, materialsystem 1, datacache 1, shaderapidx9 3), 15 game modules
  hooked, `filesystem_stdio`'s load of `bin\win64\stdshader_dx6.dll` redirected to the package's copy,
  33 session variables run through `nativeloader_session.cfg`.
- gm_construct at the spawn camera (eye 815.2, 288.0, -79.1, yaw 180, pinned in both installs, HUD
  hidden): `GarrysMod_RTX_c` and the PoC differ by **block_diff 0.90** (the user's measure: about 1
  between repeated captures of one install); mean RGB 119.5/113.2/101.0 in both. Evidence
  `out/m5/acceptance/ref-construct-pinned-2` and `poc-construct-pinned`.

**Session variables do not leak in practice.** After RTX sessions that quit normally, none of the
33 session variables appears in the PoC's `config.cfg` (they are not archived in this GMod build), so
the restore record stays empty (`recorded: 0`); the restore is a safety net for variables a package
adds that are.

**Things in the reference install to know about.** Launched with `-noworkshop`, one of its local
add-ons opens a "Zippy's Library missing" dialog that dims the frame (closed by `poc_session.py
--hide-hud`). Its `rtx-remix\mods` holds two **symbolic links**, `codex_new` and `codex_test`, whose
targets lead back up the tree: a copy that follows links never ends (robocopy wrote about 390 GB before
it was stopped). `poc_parity.py` skips linked mods and passes `/XJ`. Five of its 29 add-on folders
are symbolic links or junctions to the user's working copies under `H:\BACKUP_20260815\Modding\ipg\`
(`!advanced_material_editor`, `!gmod_bullet_break_simulator`, `advanced_bodygroup_tool`,
`eeer_body_impact_sounds`, `enhanced_entity_expression_response`; 8.4 GB with their `.git`).

**Loading the user's test save without anyone at the keyboard.**

- The save's map, `gm_csgosafehouse`, exists only as Workshop item 944959992 (a legacy LZMA `.bin`).
  With `-noworkshop`, `gm_load "saves/<name>.gms"` does nothing and prints nothing. With bad
  arguments it prints `usage: gm_load <path>`, so the command itself exists.
- With the Workshop on, the reference install printed nothing for 15 minutes after the material
  system started. It was still busy (about 2 cores, 9 GB working set) when the session driver gave
  up. The user has 753 Workshop archives installed.
- `host_workshop_map` is unknown on a single-player client.
- What works: client Lua `steamworks.DownloadUGC("944959992", cb)` hands back
  `cache/workshop/944959992.gma` (the legacy item decompressed) at once, and `game.MountGMA` on it
  returns true with one file. `gm_load` then changes level to the save's map.
  `poc_session.py --mount-workshop` does this.
- On that level change both installs log "Couldn't write cache/map_pack.bsp to mount embedded
  content!" (GMod's handling of a map inside a mounted `.gma`). The PoC's extracted copy of the map
  was removed so both load it the same way.
- Text sent through `WM_COPYDATA` while the RTX fixes reload models after a map change can be
  accepted by the window and then lost. The camera Lua sent 3 s after `Clientside Lua startup!` never
  ran, while a `quit` sent later did.

**The safehouse comparison, and what the remaining difference is not.** Reference
`ref-safehouse-mounted` against PoC captures with growing parity, all at the user's camera and
loading the save through the mounted Workshop map:

| PoC capture | block_diff |
|---|---|
| + the reference's 16 plain add-ons and the MMD Hot Loader's and RTX bridges' native files | 3.23 |
| + the Advanced Material Editor's data (`garrysmod/data/advmat`: 29 rules, 32 RTX profiles) | 3.23 |
| + the 5 add-ons linked to working copies, and the 2 linked Remix mods (`codex_new`, `codex_test`) | 3.18 |
| + the reference's own `~gmod_topbr` mod instead of the package's | 3.24 |

Two reference frames 4 s apart differ by 0.83. These are byte-identical in both installs: `d3d9.dll`
(a8e39d93), `gmcl_RTXFixesBinary_win64.dll` (485667b7), `stdshader_dx6.dll` (4bf218db),
`rtx.conf`, `dxvk.conf`, `user.conf`, `config.cfg`, `base_mod`, `gm_poolrooms_rtx` and `rtx_water`.
Geometry, lighting and shadows match. The difference sits in 41-46 of 880 blocks above 8, on the
woven chair backs, which are darker in the PoC. What could not be made equal is the game build: the
reference runs GMod 2026.09.15 (10174) with older `engine.dll` and VPKs, the PoC the current
2026.10.26 (10215). Depot files are never written, so that difference stays.

**Without RTX, a deployed package's Lua add-ons still run** (PoC, `remix.enabled: false`, before
ADR 0013).

- GMod mounted the fixes' nine add-on folders ("Adding Filesystem Addon 'addons/remixbinary'").
- Their server Lua initialised ("[RTX Flashlight] Default flashlight override: ENABLED").
- `cl_rtx.lua` `require`s the binary module whenever it is installed. The module noticed Remix was
  missing ("remix::loadRemixDllAndInitialize() failed"), applied none of its own runtime patches
  ("[MemoryPatcher] Disabled 0 patches") and shut down; RTX Water stayed off.
- The module's own PatchManager is a second patcher besides the loader's patch sets. In RTX sessions
  it resolves the same seven culling patches by its own locators and applies them, then restores them
  at map exit.
- `filesystem_stdio.dll` imports `FindFirstFileA`, `FindNextFileA`, `FindFirstFileExW` and
  `FindNextFileW` from KERNEL32, which is where ADR 0013 hides the add-ons. `engine.dll` and
  `tier0.dll` import only the `ExW`/`W` pair.

**The fixes write into their own deployed files.** The ToPBR converter rewrote
`rtx-remix/mods/~gmod_topbr/topbr_generation.txt` in the first PoC session. The deployer then reports
it ("changed after the loader placed it; left as it is"), and an uninstall leaves it behind. A
reinstall then refused the whole fixes package: "topbr_generation.txt already exists and was not
placed by the loader". `package_fixes.py` now deploys that mod create-only.

## 14. Workshop packing and updates (M6, 2026-10-28, Claude)

- `gmad.exe create` (the PoC's `bin\win64\gmad.exe`) on a folder holding `lua/autorun/a.lua`,
  `native/manifest.json` and `native/payload/test.dll`: "native/manifest.json [Not allowed by
  whitelist]", "native/payload/test.dll [Not allowed by whitelist]", "File list verification failed",
  no `.gma` written. The same folder with only the Lua file packs (181 bytes). Evidence
  `out/m6/gmad-probe`.
- **That whitelist is a packing limit, not a Workshop rule** (the user's correction, checked
  2026-10-28).
  - The `.dll`/`.exe`/`.htm`/`.html`/`.css`/`.js` list on the wiki's
    [Workshop Addon Creation](https://wiki.facepunch.com/gmod/Workshop_Addon_Creation) page says what
    `gmad.exe` will pack.
  - The [Steam Workshop rules](https://wiki.facepunch.com/gmod/Steam_Workshop_Rules) have no rule
    about file types. They ban exploits and backdoors, paid-game content, reuploads, wrong tags, and
    empty, test or placeholder items. Their "good ideas" list (not bans, but it can get an item flagged
    as incompatible) includes "do not upload broken addons", with a size limit of about 4 GB.
- **The real package through the Workshop** (ADR 0016, 2026-10-28).
  - `gmpublish update` uploaded the combined `gmod-rtx-remix` archive, 1,426,861,733 bytes (shown as
    "1.3 GB"), to item 3829070317. The archive was stored plain, not compressed.
  - Building it with `publish_workshop.py` takes seconds when the inputs are in the file cache.
  - GMod's `DownloadUGC` fetched it back byte-identical, under the uploaded file name.
  - `appworkshop_4000.acf` then listed it with the new `timeupdated` (1793223164), and the loader
    reported that time in `status.json`.
- Not tried at first: `gmpublish` (it uploads, with no dry run; outward-facing). Tried on 2026-10-28
  with the user's approval ([ADR 0015](decisions/0015-workshop-route-for-native-packages.md),
  [M6 report](handover/M6-report.md)):
  - **Upload.** `bin\win64\gmpublish.exe create -addon <gma> -icon <512x512 baseline JPEG>`, run
    from a game root that holds `steam_appid.txt`, uploaded a `gmapack` archive with
    `native/manifest.json` and a DLL. It did not check the contents. It printed "Success! Your new
    item ID is 3829070317" and "currently marked as hidden". `update -id <id> -addon <gma> -changes
    <text>` replaced the file.
  - **Download.** GMod's `steamworks.DownloadUGC(id, cb)` fetched the hidden item for its owner,
    without a subscription.
    - It went to `steamapps\workshop\content\4000\<id>\<uploaded file name>`, as a plain `.gma` (not
      LZMA-wrapped), byte-identical. An update replaced the file under the new upload's name.
    - `cb` got the path `content/4000/<id>/<name>.gma`.
    - `appworkshop_4000.acf` listed the item under `WorkshopItemsInstalled` (size, `timeupdated`,
      manifest) and under `WorkshopItemDetails`.
  - **GMod's own mount.** `game.MountGMA` refuses an archive that holds a file outside GMod's
    whitelist, printing "Couldn't mount file [<path>]" and returning false. A Lua-only `gmapack`
    archive mounts. A Workshop item that carries native files is therefore never mounted by GMod,
    and its Lua must come from elsewhere.
- The deployer handles LZMA-wrapped legacy Workshop items end to end, an update included
  (`loader/cli/tests/e2e_deploy.py`, M3).
- `steamworks.FileInfo(id, callback)` gives the item's Workshop `updated` time; the companion compares
  it with the `time_updated` that `appworkshop_4000.acf` had at start-up (now in `status.json`
  `packages`) and asks for a restart when it is newer (`tools/tests/test_companion.py`).


## 15. The field install with the loader (M7, 2026-10-28, Claude)

Measured in the user's Steam-managed install: gm_construct, the user's 44 local add-ons, no Workshop,
camera pinned. Evidence in `out/m7` ([M7 report](handover/M7-report.md)).

- **What the field install holds besides Steam's files.**
  - In `bin/win64`: a DXVK `d3d9.dll` (4 MB) for non-RTX play, a `vulkan-1.dll` (903 KB, five hard
    links), the MMD Hot Loader runtime, Jolt's three `vphysics_jolt_*.dll` with PDBs and its zip, and
    VR and Hammer++ files.
  - In `garrysmod/lua/bin`: the MMD Hot Loader's modules and VRMod's.
  - In the root: logs, `steam_appid.txt`, and GModPatchTool's folder and zip.
  - In `garrysmod/data`: 61 GB in 39,613 files.
  - No `rtx-remix`, `user.conf` or `rtx.conf`.
  - 76 non-depot files sit directly in the folders sessions write to, 255 MB; `field_snapshot.py`
    copies them in 3.4 s.
- **Without the loader** the game loads the DXVK `d3d9.dll` and `bin/win64/vulkan-1.dll`, the
  MMD Hot Loader's three modules, and the stock `vphysics.dll`. Jolt is not loaded. `mat_dxlevel` is 95.
- **With the loader and RTX on** it loads the runtime package's `d3d9.dll`, System32's
  `vulkan-1.dll` (the preload wins over `bin/win64`), the package's `stdshader_dx6.dll` and the
  fixes' module, the MMD Hot Loader as before, and `mat_dxlevel` 90. First deployment: 445 changes;
  map after 19 s.
  - Remix shows its first-run welcome panel, because the install has no `user.conf`.
  - The default Remix settings give a bluer frame than the PoC with the reference's `user.conf`
    (mean RGB 73/94/105 against 120/113/101).
- **With the loader and RTX off** the module set equals the baseline's plus the bootstrap, the 44 add-ons
  mount (the fixes' 9 hidden), and the frame matches the baseline's at block_diff 0.015.
- **What a session rewrites in the user's data**, all with unchanged sizes:
  - the MMD Hot Loader's `approved.json` and `workshop/state.json`;
  - `bbs/filters.json`;
  - `settings/mapkeys.res`;
  - in RTX sessions, the fixes' `pseudoweapontexture*.png`.

  New in RTX sessions: the fixes' `rtx_agent`, `rtx_water` and `pseudoplayertexture*.png` in
  `garrysmod/data`, and `rtx-remix/` (Remix's logs).

## 16. R1 review facts (2026-10-28, Claude, triaging Codex's review)

- **Steam's depot files inside the package areas.** Measured read-only from the field install's
  depot manifests (`out/r1-triage/depot_areas.py` in the R1 worktree, 3,063 depot file entries):
  - `garrysmod/cfg/` holds 18: `360controller-linux.cfg`, `360controller.cfg`, `autoexec.cfg`,
    `config_default.cfg`, `game.cfg`, `listenserver.cfg`, `mapcycle.txt`, `mount.cfg`, `network.cfg`,
    `server.cfg`, `settings_default.scr`, `skill.cfg`, `skill1.cfg`, `skill2.cfg`, `skill3.cfg`,
    `skill_manifest.cfg`, `undo360controller.cfg`, `valve.rc`. So `garrysmod/cfg` stopped being a
    package area ([ADR 0014](decisions/0014-r1-hardening.md)).
  - `garrysmod/lua/bin/`, `garrysmod/addons/`, `garrysmod/data/` and `rtx-remix/` hold none.
- **Import tables without names.** A PE import descriptor may have `OriginalFirstThunk` 0. Windows
  then resolves the imports from `FirstThunk` and overwrites it with addresses, so the names are
  gone once the module is mapped. Codex's repro (R1-006) zeroed it in a copy of the synthetic
  `filesystem_stdio.dll`: the DLL loads, and name-based hooks find nothing.
  - The hooks now match such slots by the bound address.
  - `GetProcAddress` on kernel32 follows its forwarders, so `GetProcAddress(kernel32, ...)` and
    `GetProcAddress(kernelbase, ...)` give the addresses the loader binds.
- **Windows PowerShell 5.1 started from PowerShell 7.** It inherits `PSModulePath` with PowerShell 7's
  module folders first. It then fails to autoload `Get-FileHash` (`Microsoft.PowerShell.Utility`), and
  `install-loader.ps1` stops (R1-029, seen in Codex's second `tools\test.ps1` run). A child started
  without `PSModulePath` builds its own default path and works.
  - The failure reproduces without PowerShell 7 installed: put a Core-only
    `Microsoft.PowerShell.Utility` module first in `PSModulePath`. Its manifest must declare every
    Utility cmdlet, as PowerShell 7's does; one declaring only `Get-FileHash` does not reproduce it.
    The field-snapshot and session-driver tests do this.
- **`reg import` and line breaks.** `reg export` writes a `REG_SZ` value holding a line break as
  `\r\r\n`, and `reg import` cannot restore it. `field_snapshot.py` reads exports strictly and refuses
  to prune after a failed import (R1-011).

## 17. GitHub's Windows runner (CI, 2026-10-28, Claude)

- **The runner decodes text as cp1252; this machine decodes UTF-8.**
  - The runner: GitHub's `windows-2022` image (20261022.344.1, runner 2.338.0, CPython 3.12.10 from
    `setup-python`). Its ANSI code page is 1252, so Python decodes a text-mode pipe without an
    `encoding` as cp1252.
  - This machine's ANSI code page is 65001 (Windows' UTF-8 option). `locale.getpreferredencoding(False)`
    gives `cp65001` even with `PYTHONUTF8=0`, so no local run sees the difference.
- **`nlctl` and the C++ test hosts write UTF-8 whatever the code page.** They `fwrite` UTF-8 JSON and
  read the environment with `GetEnvironmentVariableW` (`loader/core/src/activate.cpp`).
- **The first CI run (40779899329) failed `nl_activation_integration`** with "CLI and startup layer
  plans differ".
  - The layer list holds `用户.conf`, which cp1252 turns into `ç”¨æˆ·.conf`.
  - Start-up's `status.json` had the name right.
  - Tests now pass `encoding='utf-8'` when they read `nlctl` or a host, and open files with an explicit
    encoding.
  - A Python child (`package_runtime.py`) writes in the same locale encoding its parent reads, so
    those calls stay as they are.
- **Reproduced here** with a throwaway wrapper (not committed). It makes text-mode `subprocess` pipes,
  and files opened without an encoding, use cp1252: it patches `subprocess.Popen.__init__`, `io.open`
  and `io.text_encoding`, then runs the test with `runpy.run_path`.
  - The old test failed at the same line; the fixed one passed all 17 cases.
  - CTest starts the test with `python -I`, so a `sitecustomize` on `PYTHONPATH` would not load.
- **The runner has no Vulkan loader** (`System32\vulkan-1.dll`). The activation test skips its
  "optional Vulkan preload uses System32" case there.
- **Node 24 actions.**
  - GitHub runs Node 20 actions on Node 24 and warns about each one.
  - The first majors that target Node 24: `checkout` v5, `setup-python` v6, `upload-artifact` v6 and
    `download-artifact` v7. Their release notes change nothing else this workflow uses, and they
    need runner 2.327.1 or later.
  - Later majors existed on 2026-10-28: checkout v7, setup-python v7, upload-artifact v7, and
    download-artifact v8, which makes a digest mismatch an error.
- **Timings of the first run.** `tools\test.ps1 -Config Release` took 4 min 14 s: CTest 21 s for 16
  tests, the Python suites about 40 s.

## 18. The first field test of the release bundle (2026-10-28, Claude)

The setup: the field install with the CI-built loader 0.2.0 and the subscribed item 3829070317. The
player's Steam launch options were `-multirun -insecure -tickrate 120`. Evidence: the loader's own
logs and `status.json`, and Remix's log. The user's console log was not read.

- **Every start crashed to the desktop.** There were three starts, 22:53-22:55 UTC. The last one
  crashed 9 s in.
  - The loader did its part. It deployed the item (442 changes, 7.5 s on the first start), activated
    it, applied 7 of 7 patch sets and the shader override, and hooked 15 modules.
  - Remix's log (`rtx-remix/logs/remix-dxvk.log`) ends with these lines:
    - a 640x480 device with `Windowed: false`;
    - `Setting display mode: 640x480@0`;
    - `FSR FG: onDestroy called`;
    - `[D3D9WindowProc] Swapchain handle is invalid, some of its values may not be correct.`
  - Remix's crash handler (Sentry) wrote `rtx-remix/logs/.sentry-native/last_crash` 1 ms later.
    Windows logged no Application Error.
- **Why 640x480 fullscreen.** On the PoC, `DXLevel_V1` 95 was stored (what non-RTX sessions write),
  and the video key (section 11) held 960x540, windowed, borderless. A start with `-dxlevel 90` ignored
  that size and window mode, and made a 640x480 exclusive-fullscreen device.
- **Reproduced on the PoC** with the field's launch options and `DXLevel_V1` 95 (a throwaway script in
  the worktree's `out/fullscreen`):
  - Without window options: the same log lines, then exit `0xC0000005` after 13.6 s.
  - With `-windowed -noborder -w 3840 -h 2160` added by hand: a windowed 3840x2160 device, still running
    after 45 s, no crash record.
  - With loader 0.2.1 and no window options: the loader added those options itself, with the same
    result ([ADR 0018](decisions/0018-rtx-sessions-in-a-borderless-window.md)).
  - Windowed sessions log one "Swapchain handle is invalid" warning too, and do not crash.
- **The window options GMod x64 reads**, from strings in the PoC's `engine.dll` and `launcher.dll`:
  `-windowed -window -sw -startwindowed -full -fullscreen -noborder -w -width -h -height`.
- **`gmod.exe` is per-monitor DPI aware.** Its manifest has `<dpiAware>true/PM</dpiAware>`.
- **This machine's display:** the RTX 5090 drives the primary display at 3840x2160 and 240 Hz. The
  CPU's AMD graphics are present too.
- **GMod extracts Workshop items separately for each install.**
  - Legacy items are extracted to `garrysmod/cache/workshop/<id>.gma`, beside `<n>.cache` files.
  - The PoC had never mounted the user's subscriptions, because automated sessions pass `-noworkshop`.
    Three starts with the field's options extracted 163 files (4.4 GB). Each start continued with new
    items. The one item a stopped session had been writing was extracted again.
  - Item 3829070317 is never extracted: it is a plain `.gma`.
  - The field install's cache was last written on 2026-10-24.

## 19. Field parity with the classic install (R2, 2026-10-29, Claude with four research agents)

The measure: the pool rooms (`gm_poolrooms`, Workshop 2849511871, mounted from client Lua by
`poc_session.py --mount-workshop ... --change-map gm_poolrooms`) at a pinned camera. The camera is at
the map's spawn point `1336 -456 -82` (eye z -18), pitch 5, yaw 342.5, with the HUD hidden. The block
measure is that of section 12. Evidence is in the worktree's `out/round2`.

**The runtime fork's config layers** (`dxvk-remix-gmod`, branch `gmod-1.6.1`; corrects sections 2 and 10):

- **For `rtx.*` options, the first entry of a `DXVK_RTX_CONFIG_FILE` or `DXVK_CONFIG_FILE` list is the
  strongest.**
  - Earlier entries are named "00_...", "01_..." and the last gets the plain name. Layers of one
    priority sort alphabetically, and the first wins (`rtx_option_layer.cpp:49-61`,
    `rtx_option_constants.h:159-164`).
  - `d3d9.*` and `dxvk.*` keys come from one merged config in which the last file wins.
- **Priorities:**
  - `dxvk.conf` layers 1, per-game built-ins 2 (only `hl2.exe` has an entry), `rtx.conf` layers 3,
    per-option environment variables 5;
  - `user.conf` 0xFFFFFFFE, presets 0xFFFFFFFF.
  - `user.conf` is always `./user.conf`; there is no override.
  - `%LOCALAPPDATA%\NVIDIA\RTXRemix\user_settings\<hash>.conf` holds only first-use and crash-report
    flags.
- **Save targets:**
  - "Remix Config (rtx.conf): Save" writes the last `DXVK_RTX_CONFIG_FILE` entry, every value of that
    layer, and only `rtx.` keys.
  - "User Settings (user.conf): Save" writes `./user.conf`.
  - "Migrate N Developer Settings" moves API-set values from the user layer into the `rtx.conf` layer,
    in memory only.
  - The RTX fixes write developer options through the API into the user layer: per-map configs,
    `ignoreGame*Lights`, texture categories. So `user.conf` shows unsaved changes by itself.
- **Presets:**
  - A graphics preset other than Custom (4) re-applies its values above `user.conf` at every device
    creation. Auto (5) picks Ultra on Blackwell.
  - DLSS preset On forces the upscaler, DLSS quality Auto and Reflex. `rtx.dlssPreset 2` keeps your
    choices.
  - `rtx.raytraceModePreset` Auto rewrites the three ray-trace modes.
- **Limits and switches:**
  - These variables are read into a 260-character buffer; a longer value counts as empty, and the
    runtime falls back to the bare root conf.
  - `DXVK_FORCE_WINDOWED=1` makes every device creation and Reset windowed (`d3d9_swapchain.cpp:1195`).
- **Texture-hash lists** (`rtx.*Textures`) combine across layers as sets: a layer adds its hashes and
  removes its `-0x...` ones. The classic install's effective lists hold 4,087 decal, 1,576 particle,
  549 player-model and 208 ignore hashes, removals included.
- **The fullscreen crash of section 18:**
  - `D3D9WindowProc` (`d3d9_swapchain.cpp:239-309`) keeps using a swap chain while the device
    destructor runs. The "Swapchain handle is invalid" liveness test is itself a use after free.
  - The hook is removed only at the end of the swap chain's destructor.

**What the field ran differently** (before this round):

- **Remix settings.** The package shipped the classic `rtx.conf` and `dxvk.conf`, but not the classic
  `user.conf`: 91 settings. That file holds the 4-hash `playerModelTextures`, the fog
  (`transmittanceMeasurementDistanceMeters` 420), atmosphere, NRC (`integrateIndirectMode` 2) and
  preset 4.
- **The user's test saves** in the field's root `rtx.conf` (16:58) set fog to 10 m, atmosphere off and
  `playerModel.enableInPrimarySpace` False.
- **The RTX add-ons' settings.**
  - GMod x64 keeps Lua convars in `garrysmod/cfg/client.vdf` and `server.vdf`, not `config.cfg`. The
    fixes also keep `r_forcehwskin` as a cookie in `cl.db`, restored at every map load. It is forced
    to 1 when HL2 RTX content is mounted.
  - The classic `client.vdf` (the fixes' own `.vdf`, which RTXLauncher copied, plus the user's tuning)
    against the field:

    | Setting | Classic | Field |
    |---|---|---|
    | `rtx_pseudoplayer`, `rtx_pseudoweapon` | 0 | 1 |
    | `rtx_api_map_lights_autospawn` | 0 | 1 |
    | `rtx_lightupdater` | 1 | 0 |
    | `rtx_flashlight_brightness` | 5 | 1000 |
    | `rtx_water_custom` | 1 | 0 |
    | `rtx_pseudoplayer_unique_hashes` (server) | 0 | 1 |

  - The field also had the cookie `r_forcehwskin=1`.
- **The pseudo player and Model Hotloader.**
  - With `rtx_pseudoplayer 1` the fixes draw a client-side copy of the local player. Model Hotloader
    adopts it as a player copy (`player_copies.lua:52-74`) and draws it with the character's own
    textures, so nothing is tagged and the MMD body appears in first person.
  - Model Hotloader also cuts the head out of the first-person view with a user clip plane, which the
    path tracer ignores. The field's Model Hotloader 2.3.0 has no RTX handling (no `mhrtx_*`
    variables); the classic install's 2.3.1 has.
- **AMAP's RTX flashlight** (`mmd_vmd_npc`, the Character Motion Importer) calls `RemixLight.CreateSphere`
  directly; ProjectedTexture and `rtx_lightupdater` do not matter to it. A sphere light's output grows
  with radius squared, and the field's `mmd_vmd_npc_flashlight_rtx_radius` was 1 (classic 30, AMAP
  default 20).
  - With the classic values the light is strong: the pinned frame went from mean RGB 80/82/76 to
    117/122/119.
- **The classic install's fixes Lua** has three local fixes the fork lacked, committed to the fork as
  `fc478c0`:
  - `cl_material_pipeline.lua` reads model materials from the `.mdl` header; the old walk froze maps
    with thousands of props;
  - the skybox boundary renderer builds its meshes only when switched on; before, it took 3 ms of each
    frame for a minute after every map load;
  - `func_reflective_glass` is removed again after clean-ups and saves.
- **Remix mods:** the classic install loads 29, the field 5. Among them are `Poolday` (337 MB, a
  "Release Ready" replacement mod for the pool rooms), `Water`, `Emissives`, `gmodrtx_poolday_fix`,
  `ai_pbr` and the user's character and map mods.

**Measurements** (block measure; repeat captures of the classic install: 0.60):

| Field state | block_diff | Mean RGB (classic 72.7/93.6/96.6) |
|---|---|---|
| Package with classic `rtx.conf` only, first-run add-on defaults applied (test 1) | 14.47 | 79.0/82.2/76.1 |
| One merged defaults layer, effective Remix values equal to the classic install's (test 2) | 14.79 | 80.0/81.8/76.1 |
| Texture lists merged as sets, every effective list equal (test 4) | 14.78 | 79.9/81.8/76.1 |
| Plus the classic `Poolday`, `Water`, `Emissives`, `gmodrtx_poolday_fix` and `SubUSDs` mods | 14.90 | 79.8/81.6/75.8 |

- The remaining difference is a uniform warm cast against the classic install's blue-grey. The
  effective Remix settings, the pool rooms mod and add-on, the water and the per-map configs are now
  identical; so are the hash lists.
- Not yet compared: the classic install's other local add-ons and their data, among them Advanced
  Material Editor (29 persistent rules, 32 RTX profiles, its standalone bridge DLL), the other 23
  Remix mods, and the older game build.
- The first-person view is correct: no pseudo-player body. Remix's menu opens through
  `RemixConfig.SetUIState(2)`, and "Remix API: ready" is reported under the loader.

**GMod's shared video settings across modes** (PoC, `-nonativeloader` for vanilla, `--no-window`):

- A normal start with `DXLevel_V1` 90 stored, as RTX leaves it, used the stored 2560x1440 windowed,
  kept it, and wrote 95.
- An RTX start with 95 stored opened at the loader's 3840x2160, left the stored size and window flags
  as they were, and wrote 90.
- So neither mode overwrites the other's video settings; command-line `-w`/`-h`/`-windowed` are not
  saved.

**The user's add-ons and the machine** (static audit of the field's local add-ons, about 700
Workshop GMAs and the binaries):

- **Add-ons:**
  - FPS Boost (2982286549) sets `r_threaded_particles 1` and the queued-rendering variables at every
    client start, after the session cfg.
  - Draconic Base (1847505933) turns motion blur on every second.
  - Draconic Base and ECAfEDAP draw stock post-processing; Zippy's Library draws outlines from screen
    copies.
- **Vulkan layers registered here** load into Remix's instance: OBS's `VK_LAYER_OBS_HOOK` and the AMD
  iGPU's `VK_LAYER_AMD_switchable_graphics` are always on. The Steam overlay and Fossilize layers turn
  on only when their `ENABLE_*` variables are set.
- **Other files:**
  - No `d3d11.dll` or `dxgi.dll` is in `bin\win64`; the Chromium leftovers there (`vk_swiftshader`,
    `dxcompiler.dll`, `dxil.dll`) are inert.
  - `gmcl_vrmod_win64.dll` in `lua\bin` links D3D11 and OpenVR, but no VRMod Lua is installed.
- **Zippy's Library** (Workshop 3146473253) is required by the user's local `enhanced_blood`. GMod's
  Workshop rules forbid reuploading another author's item "whatever the reupload reason is", so it is
  mounted from the user's own subscription in test sessions and never packaged.

**Bundling the requested add-ons** (inventory):

- **Model Hotloader:** its modules statically import `mmdhl_runtime_win64.dll`, which Windows finds
  in `bin\win64` next to the exe. The package format cannot place files there.
- **Advanced Material Editor, the bodygroup tool, procedural bodygroup destruction and the Character
  Motion Importer** are Lua add-ons, with an optional bridge DLL for the editor. They fit the package
  areas.
  - In the field, `mmd_hotloader`, `mmd_vmd_npc` and `advanced_bodygroup_tool` are hand-placed folders
    of the same names; the last is a link to the dev folder. The loader refuses to replace a folder it
    does not own, and that refusal fails the package.
- **The debug module** (`gmcl_rtxdebug_win64.dll`) and its one-file add-on `rtx_debug` now ship with
  the fixes.
- **modern_house_rtx:** 8 Lua files plus 490 DDS textures, 3.32 GB. The textures are AI-upscaled from
  the textures of someone else's map (Workshop 3495468649).

## 20. Third field round: the pseudo player, the classic Remix mods, Modern House (2026-10-29, Claude)

Measured in the field install with `poc_session.py --allow-steam-managed`. The evidence is in the
worktree's `out\round3\`.

**The player's own model in first person came back after round 2.**

- The classic install's `cfg\server.vdf` holds stale copies of three settings, and its `client.vdf`
  has the values the game uses:

  | Setting | `server.vdf` | `client.vdf` |
  |---|---|---|
  | `rtx_pseudoplayer` | `1` | `0` |
  | `rtx_pseudoweapon` | `1` | `0` |
  | `rtx_disablevertexlighting` | `1` | `0` |

- The fixes create these on the client only (`cl_rtx_misc.lua`, `CreateClientConVar`), and the
  field's `server.vdf` has no such entries. In single-player one variable of each name serves both
  realms.
- `classic_defaults.lua` version 2 had them in its server table. `nativeloader_rtx_defaults_server`,
  run after the client command, set them to `1`, and the game saved that in `client.vdf`. The pseudo
  player then drew the player's head in front of the camera.
- After the fix (version 3, the server table without names the client table has) the console prints
  `"rtx_pseudoplayer" = "0" ( def. "1" )`. A first-person start in the pool rooms shows no body.
  Version 3's first run changed 0 of 187 client and 0 of 17 server settings: they were classic already.

**Emissives** (`rtx-remix\mods\Emissives`, from the classic install; 10 files, 3.8 MB):

- It replaces one material, `mat_B19B22D6FDE30598`: albedo, an emissive mask, intensity 18, and
  metal and roughness maps.
- That is `models/props_interiors/florescentlight01a_on`, HL2's fluorescent tube light:
  - the fixes' category manager logs it with that hash in gm_construct;
  - `RemixMaterial.GetTextureHash` returns the same number in game;
  - the classic `rtx.conf` also lists it in `rtx.legacyEmissiveTextures`.
- gm_construct has 16 of these lights as static props, `models/props_interiors/lights_florescent01a.mdl`
  skin 1 (NikNaks `GetStaticProps`). 15 form a grid in the basement at z -179, x -1424 to -2704,
  y -1344 to -1824; one is at (-5460, -3164, 381).
- With the camera pinned at (-1584, -1584, -235), pitch -20, yaw 180:

  | | Mean RGB |
  |---|---|
  | With the mod | 49.5 / 45.8 / 38.6 |
  | Without it | 21.5 / 20.6 / 18.5 |

  The block measure between the two is 24.4, against 0.8 between two runs with it. Without the mod
  the tubes still glow (legacy emissive) but light little.
- Remix warns that its textures have no mip-maps. Four files are not referenced: three `.bmp` sources
  and `mirror_diffuse.dds`.

**Water** (`rtx-remix\mods\Water`, 38 files, 33 MB):

- It replaces 29 materials. All 29 textures are in the classic `rtx.ignoreTextures`, as well as in
  `animatedWaterTextures` and `decalTextures`. Ignored draws never reach the renderer, so the
  replacements never apply.
- Its `replacements.usda` references `./SubUSDs/AperturePBR_Translucent.usda`, which the folder lacks.
- `33FAB345028AFF4A`, one of its textures, belongs to the super gravity gun's sheet; no material uses it.
- **A/B in the pool rooms** at the round-2 pinned camera:

  | Compared with each baseline run | Block measure |
  |---|---|
  | Without Water | 0.88, 0.41 |
  | Without Emissives | 0.64, 0.89 |
  | The two baseline runs with each other | 0.90 |

  The largest 16-pixel block differences are 6-9 in every pair.
- **`SubUSDs`** at the mods root has no `mod.usda`; Remix does not load it.

**A test with props is misleading.** Fluorescent lights spawned as `ClientsideModel` with the `_on`
material rendered as solid red slabs, with the mod and without it. Test with the map's own props.

**gm_construct starts the player at different spawn points.** Three starts put the eye at (763, -801),
(643, -657) and (900, 578). Compare with a pinned camera.

**Modern House RTX through the Workshop** ([ADR 0023](decisions/0023-content-packages-and-modern-house-item.md)):

- **The build.** `package_content.py` built the package from the fork worktree in 9 s, with hard links
  in the work folder:
  - 500 files, 3,322,961,921 bytes; the archive is 3,323,148,599 bytes;
  - version `0.0.0-dev.202610280457+caaa4535`.
- **`nlctl` and hard links.** `nlctl manifest` refuses a package folder whose files are hard links ("is a
  link or reparse point; packages may not contain them"). The linked build is checked as the archive.
- **The upload.** `gmpublish create -addon <gma> -icon <512x512 baseline JPEG>` uploaded it in 50 s (shown
  as "3.0 GB"): item **3829275998**, "currently marked as hidden".
- **The subscription.** GMod's `steam_api64.dll` has the flat Steamworks API (`SteamAPI_InitSafe`,
  `SteamAPI_SteamUGC_v021`, `SteamAPI_ISteamUGC_SubscribeItem`, `..._DownloadItem`,
  `..._GetItemDownloadInfo`, `..._GetItemInstallInfo`). Run as app 4000 from a game root holding
  `steam_appid.txt`, it subscribed the owner to the hidden item.
  - Steam downloaded 2,414 MB, the transfer compressed, in 12 s.
  - It installed `content\4000\3829275998\modern-house-rtx.gma` byte-identical (the same SHA-256)
    and listed it in `appworkshop_4000.acf`.
- **The next start.** With the item allowlisted, the loader deployed it from the Workshop: 492 mod
  files and the add-on, `source: workshop`.
- **The map.** On `modern_house` (the map mounted with `--mount-workshop 3495468649`, then `--change-map`):
  - the add-on printed `[MHRTX] applied 9 Remix settings; sky: physical atmosphere` and `created: 341
    lights in the house, 341 on, the atmosphere's sun, 8 mirrors`, with no Lua errors;
  - from the launch to the screenshots took 2.1 minutes.
- **Against the gallery.** At the remaster's terrace camera (732, 154, 536; 6, 90, 0), the field matches
  its gallery shot from the classic install, mean RGB 139.4 / 122.3 / 102.6 against 139.8 / 122.2 / 103.0.
  The gallery shot has a wider field of view.
- **A harmless warning.** GMod printed `Couldn't write cache/map_pack.bsp to mount embedded content!`,
  and the map's textures were right anyway.

**Field changes this round:**

- The user's `enhanced_blood` moved to `garrysmod\addons_d` (their folder of disabled add-ons). With it
  went the need for Zippy's Library.
- The test copies of Water, SubUSDs and Emissives moved out of `rtx-remix\mods` into
  `out\round3\field-removed-mods`; the package now deploys Emissives.
- The round-2 copies of Poolday, `gmodrtx_poolday_fix` and `Poolday_mirror_fix` stay.

## 21. Fourth field round: the bundled add-ons and module dependencies (2026-10-29, Claude)

**Model Hotloader's natives** ([ADR 0024](decisions/0024-bundled-addons-and-module-dependencies.md)):

- **The import.** `gmcl_mmdhl_win64.dll` and `gmsv_mmdhl_win64.dll` statically import
  `mmdhl_runtime_win64.dll` (PE import tables). The runtime imports only system DLLs and loads
  `lib_coacd.dll` itself.
- **Who loads modules.** GMod's `lua_shared.dll` imports `LoadLibraryExA` and `LoadLibraryExW`;
  `client.dll` and `server.dll` import `LoadLibraryA` and `LoadLibraryExW`. Binary modules load without
  `LOAD_WITH_ALTERED_SEARCH_PATH`, so Windows looks for the runtime next to `gmod.exe`. Model Hotloader's
  installer copies it into `bin\win64` for that reason; its import worker `mmdhl_worker.exe` finds the
  copy in `lua\bin`, beside itself.
- **The release layout.** Its release script (`scripts/package-dropin.py`) stages two drop-in trees:
  - `-win64-vulkan` carries a patched DXVK `d3d9.dll`;
  - `-win64-opengl-remix` leaves Direct3D 9 to Remix.

  Both hold `lua\bin\{gmcl,gmsv}_mmdhl_win64.dll`, `mmdhl_runtime_win64.dll`, `lib_coacd.dll`,
  `mmdhl_worker.exe` and `mmdhl-native-release.json` (the version file the add-on checks), plus
  `shaders\fxc\mmdhl_{ps20b,vs20}.vcs` and `bin\win64\mmdhl_runtime_win64.dll`. The add-on's own
  `shaders/fxc` has the same two shaders, byte for byte.
- **Releases.** The newest local release is 2.3.0 (build `1df48dac`, 2026-10-12). The repository's
  `main` is at "Version 2.3.1" (2026-10-26) with staged changes.
- **What the classic install runs.** Its `mmd_hotloader` folder matches the main repository's working
  tree. Its natives are byte-identical to the build in the worktree `wt-full-textures-props`
  (`gmcl_mmdhl_win64.dll` 2,843,648 bytes, 2026-10-26 16:21).

**The user's own Workshop items for the five add-ons**, all subscribed:

| Item | Add-on | Note |
|---|---|---|
| 3810025467 | Model Hotloader | 2.3.0 |
| 3718373357 | MMD VMD NPC Animation (the motion importer) | |
| 3789611737 | Procedural Bodygroup Destruction | 0.19.15 |
| 3791888631 | Advanced Bodygroup Tool | |
| 3793132326 | Advanced Material Editor | 57 files: its Lua and `materials/advmat/shift.png` |

**The parts**, built with `package_content.py`, add-ons filtered as gmad publishes them:

| Part | Files | Bytes | Left out by the filter | Compared with |
|---|---|---|---|---|
| Model Hotloader (add-on and six natives) | 110 | 86,924,394 | | |
| Advanced Material Editor (and its bridge) | 59 | 2,748,327 | 1,846 | 266 MB unfiltered: 14 character textures of 16 MB each committed under `materials/models/sheepylord/hsin`, which the published add-on leaves out (`--ignore materials/models/*`) |
| Advanced Bodygroup Tool | 6 | 212,124 | 37 | the Workshop's 212,438-byte GMA |
| Procedural Bodygroup Destruction | 16 | 753,816 | 16,714 | the local 0.20.0 GMA, 754,307 bytes |
| Character Motion Importer | 17 | 19,315,255 | | the Workshop's 19,334,061 bytes |

The combined RTX package with the nine parts is 1,541,278,091 bytes.

**Measured with loader 0.3.0:**

- **PoC, RTX:** deployed (234 changes). When the game loaded `gmsv_mmdhl_win64.dll`, the bootstrap first
  loaded `mmdhl_runtime_win64.dll` from `lua\bin` (`session.json`). Model Hotloader's native module is
  live on the server and the client (`mmdhl.native` set); no Lua errors.
- **PoC, without RTX:** the package's 16 add-on folders are hidden (`mmdhl` is nil and
  `lua/autorun/mmdhl.lua` is not in the `GAME` path). `require("mmdhl")` succeeds, with the runtime
  loaded first for `gmcl_mmdhl_win64.dll`. A subscribed Workshop copy can therefore use the bundled
  natives in a normal session.
- **Field, RTX:** deployed (407 changes) and active, no Lua errors, the module live on both sides. The
  first-person view in the pool rooms shows no body.
- **Field, moved out first** (the loader never replaces files it did not place):
  - `mmd_hotloader`, `mmd_vmd_npc` and the `advanced_bodygroup_tool` symlink went to `addons_d`;
  - the six Model Hotloader 2.3.0 files in `lua\bin` went to the round-4 backup. Three of them were hard
    links into a Model Hotloader validation folder (`!Gmodl_MMD_Hot_Loader\.claude\worktrees\
    mmd-importer-performance-87a36d\validation\multiplayer\client*`);
  - so did `bin\win64\mmdhl_runtime_win64.dll` (10,710,016 bytes, 2.3.0).

**The visibility-tuned fixes module.**
- Another session rebuilt `gmcl_RTXFixesBinary_win64.dll` (1,444,352 bytes, SHA-256 `189765c0...`,
  2026-10-28 21:19) in the fork worktree `rtx-remix-map-enhancement-bda9ac`. Its branch commit `e4d548d`
  is "Backrooms RTX: keep the room next door in the ray-traced scene" (`source/culling_patches.cpp`,
  +100 lines).
- It installed the module into the classic install's `lua\bin`, where the fixes part takes its modules,
  so the test package carries it byte for byte.
- The field had the earlier `485667b7...`.

**Hooks.** The add-on repositories (the bodygroup tool has none), the fixes fork and Model Hotloader's repository had no git
hooks. Their default branch is `main`, except the fork's checked-out `sheepylord/rtx-water-poolrooms`.

## 22. What Steam does when the user subscribes and unsubscribes (2026-10-29, Claude)

The user found that unsubscribing from the RTX item left RTX Remix running. To tell an unsubscribe
from a download or an update without the Steam API, a hidden test item (3829311605, a 100-byte
add-on package) was subscribed and unsubscribed. The scripts called GMod's own `steam_api64.dll` as
app 4000 (`ISteamUGC::SubscribeItem`, `UnsubscribeItem`, `GetItemState`, `DownloadItem`), polling
`steamapps\workshop\appworkshop_4000.acf` and the item folder every half second.

**Steam's record** has two sections under `AppWorkshop`:
- `WorkshopItemsInstalled`: the items on disk (`size`, `timeupdated`, `manifest`);
- `WorkshopItemDetails`: the items Steam tracks for this account (`manifest`, `timeupdated`,
  `timetouched`, `subscribedby` (an account id) and `latest_*`).

**Subscribe:**
- At 0.6 s the item state was `subscribed,needs-update`, with nothing on disk yet.
- At about 1.1 s the item was in `WorkshopItemDetails`, with `subscribedby`.
- At 8.5 s it was in `WorkshopItemsInstalled`, and its folder held the `.gma`.

So while a first download runs, the item is in `WorkshopItemDetails` with no folder.

**Unsubscribe:**
- The item state lost `subscribed` at once (`installed` only).
- The acf and the folder stayed as they were for the 90 s watched, both while the API session ran and
  after it ended.
- Some minutes later the item was gone from `WorkshopItemDetails`. It was still in
  `WorkshopItemsInstalled`, and the folder was still there.

**The next launch from Steam** (`steam://rungameid/4000`), timed from the launch request:
- At 1.2 s Steam had removed the item from `WorkshopItemsInstalled` and deleted its folder.
- At 2.8 s `gmod.exe` was running. The bootstrap therefore sees the item gone in its first start.
- A second run launched about 20 s after the unsubscribe, with the item still in both sections. At
  1.2 s Steam had removed it from both and deleted the folder, and `gmod.exe` ran at 2.0 s. The
  launch's clean-up does not wait for the later update of `WorkshopItemDetails`.

**Telling the cases apart:**
- A first download: the item is in `WorkshopItemDetails`, with no folder yet.
- An update: the item stays in `WorkshopItemsInstalled`, even while its folder is replaced.
- An unsubscribe, once Steam has cleaned up: the item is in neither section, and its folder is gone.

This is the rule [ADR 0025](decisions/0025-unsubscribe-removes-the-package.md) uses. A game started
without Steam's launch (for example `gmod.exe` run directly) finds the folder still there and keeps the
package until a launch from Steam has removed it.

**End to end with loader 0.3.1 on the PoC** (evidence in `out\round5\e2e`):
1. **Subscribed.** The item was installed in 1.7 s and allowlisted alone. The PoC start deployed it
   (generation 3), and the add-on's autorun printed on the server and the client.
2. **Unsubscribed, then launched from Steam at once.** Steam cleaned up as above. The next PoC start
   removed the package:
   - generation 4, with the note "its Workshop item was unsubscribed, so its files are deleted";
   - the skipped reason "not subscribed";
   - the add-on folder was gone, and the add-on did not run;
   - `native-loader` held only `config.json`, the journal, the lock, the install receipt and the logs,
     with no `packages` or `backup` folder;
   - the journal had no previous generation.
3. **The config put back.** The next PoC start deployed the 1.5 GB RTX package again in 10.0 s (669
   changes), RTX active, with no Lua errors.

`verify_install.py` afterwards: all 2,877 depot files unchanged.

**Seen on the way:** Model Hotloader prints "Missing bin/win64/mmdhl_runtime_win64.dll" and "The
loaded runtime DLL is not the file that was checked", on the server and the client
(`mmdhl.install.error.*`). Its runtime and both modules are loaded: the bootstrap loads the runtime
from `garrysmod\lua\bin` (ADR 0024), and the add-on says it "uses it anyway". The round-4 sessions,
PoC and field, show the same lines. Fixed in section 23.

## 23. Model Hotloader's install check and the runtime in lua/bin (2026-10-29, Claude)

**Where the warnings come from.** Model Hotloader's repository is
`H:\BACKUP_20260815\Modding\ipg\!GMHLVK\Gmod-Model-Hotloader-with-Vulkan` (`main` at `ecd7c42`
"Version 2.3.1"). Its `addon/lua/mmdhl/installation.lua`:
- **Before loading,** `EvaluateInstallation` reads the runtime where Windows looks for it: `bin/win64`
  through `BASE_PATH` on a client or listen server, beside `srcds_win64.exe` then `bin/win64` on a
  dedicated server, `lua/bin` on Linux. A missing file is a warning, printed before `require`.
- **After loading,** `identitiesMatch` compares the runtime path the native module reports
  (`GetInstallationInfo`) with that file. A difference is the "loaded runtime DLL is not the file that
  was checked" warning.

With the loader, the runtime the module reports is `<game>\garrysmod\lua\bin\mmdhl_runtime_win64.dll`
(LoadLibraryExW of that absolute path, `loader/proxy/modules.cpp` `load_first`). So both warnings
fire, although everything works.

**What the RTX package ships.** The classic install's `garrysmod\addons\mmd_hotloader` equals the
repository's `main` working tree, byte for byte, except `lua/mmdhl/native_policy.lua`:
- The working tree holds work staged since 2026-10-26: 41 files, secondary gravity and buoyancy,
  server settings. It is uncommitted; the session that wrote it is offline.
- The shipped `native_policy.lua` is the one the native build writes. It records release 2.3.1 (build
  `ecd7c426c0b5-20261026T225907Z`, runtime SHA-256 `351a7068...`), which is what the classic install's
  `lua\bin` holds. The committed one stops at 2.3.0.

**The fix** (Model Hotloader commit `bed4582`, made on the branch `claude/runtime-in-lua-bin`;
[ADR 0026](decisions/0026-addon-file-from-its-repository.md)):
- **Before loading:** on a Windows client or listen server with no runtime in `bin/win64` and a copy
  in `lua/bin`, that copy is the runtime checked. The missing file waits in `files.runtime.missingAt`.
- **After loading:** `reportMissingRuntime` drops it when the loaded runtime is that copy. Otherwise
  (nothing loaded, loaded from elsewhere, a module too old to say) the missing file is reported as
  before, so a player without the loader still reads why the module did not load.
- **Tests:** its offline suite (51 scripts, lupa 2.8) and the i18n check pass on the branch. On `main`'s
  working tree with the staged work, 55 scripts pass.
- **Landed** (the user: "Push to main"):
  - Model Hotloader's `main` was fast-forwarded from `ecd7c42` to `bed4582` and pushed to GitHub, and
    the branch was deleted.
  - The checkout's staged work is kept, now on top of the fix: the same 41 files and changed lines,
    compared before and after. A backup of the earlier state is in `out\round6\mmdhl-main-backup`.
  - 55 scripts pass there.

**Measured** with the branch-built RTX package on the PoC (loader 0.3.1, RTX active), evidence in
`out\round6\poc`:
- No runtime warning on either realm.
- `mmdhl.native` is set on the server and the client.
- The server's install status lists no issue. The client's lists only `game_unverified`: "This Garry's
  Mod build has not been tested with this native release (engine.dll, client.dll, materialsystem.dll,
  shaderapidx9.dll changed)". That is Model Hotloader's compatibility profile for 2.3.1 against a
  newer GMod build, unrelated to the runtime.

**Git hooks and the publish script.** Git runs a hook with the hooked repository in `GIT_DIR`,
`GIT_INDEX_FILE` and `GIT_WORK_TREE` (githooks(5); for a worktree, `GIT_DIR` is
`.git/worktrees/<name>`). `git -C <path>` and a `cwd` do not override `GIT_DIR`.
- So the round-4 source hooks ran `publish_workshop.py` against the source repository.
- Seen when the fix above was committed in Model Hotloader's worktree: the run refused with this
  repository's `companion/` and `tools/...` listed as untracked. Its log was in
  `Gmod-Model-Hotloader-with-Vulkan\out\workshop\logs`, which was then removed.
- No earlier source-repository commit had run one (no other such log existed).
- The 15 names `git rev-parse --local-env-vars` lists on git 2.56.0 are the ones the script now
  removes.
