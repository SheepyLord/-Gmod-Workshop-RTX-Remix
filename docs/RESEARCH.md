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
  `%LOCALAPPDATA%\NVIDIA\RTXRemix\user_settings\<hash>.conf` is also read.
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
- `createLayersFromEnvVar` (`:629-647`) makes one layer per listed path, lowest priority first; the
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
