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
