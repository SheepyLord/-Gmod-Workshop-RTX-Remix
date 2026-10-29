# Changelog

Notable changes to this repo. Format: [Keep a Changelog](https://keepachangelog.com/en/1.1.0/).
Versions follow the loader's CMake project version once it ships; until then everything is under
`Unreleased`, grouped by milestone.

## [Unreleased]

### Fixed (the third field round)

- **The player's own model was drawn in first person again** (the pseudo player). The classic
  install's `server.vdf` keeps stale `1`s for `rtx_pseudoplayer`, `rtx_pseudoweapon` and
  `rtx_disablevertexlighting`, against `0` in its `client.vdf`. In single-player both realms share
  these variables, so applying the server table switched the pseudo player back on.
  - The generated table now keeps a name saved for both realms in its client table only.
  - Version 3 applies the corrected values once more, where they are still at their defaults.
  - [RESEARCH.md](docs/RESEARCH.md) section 20.

### Added (the third field round)

- **The Emissives Remix mod ships in the RTX package**
  ([ADR 0023](docs/decisions/0023-content-packages-and-modern-house-item.md)). HL2's fluorescent tube
  lights (gm_construct's basement and elsewhere) now light their rooms: measured twice as bright as
  without it. The classic install's Water mod does not ship: its textures are on the ignore list, so it
  never draws.
- **`tools/package_content.py`:** content packages, Lua add-on folders and Remix mod folders with no
  native code. For an archive alone it hard-links its work folder, so gigabytes of textures are not
  copied twice.
- **Modern House RTX as its own package**, `modern-house-rtx` (the remaster's Remix mod and Lua,
  3.3 GB). It is uploaded as the hidden Workshop test item 3829275998, subscribed, and played in the
  field install from there.

### Fixed (the second field round: rendering parity with the classic install)

- **Remix settings saved in the menu came back at the next start.** In the runtime fork the first
  entry of a layer list is the strongest, so the package's layer beat the player's saved `rtx.conf`
  ([ADR 0021](docs/decisions/0021-remix-defaults-in-one-low-layer.md)).
  - The package now ships its Remix defaults as one low `DXVK_CONFIG_FILE` layer and leaves
    `DXVK_RTX_CONFIG_FILE` unset.
  - The player's `rtx.conf` and `user.conf` now win.
- **The classic RTX install's settings are now the defaults**
  ([ADR 0020](docs/decisions/0020-classic-rtx-settings-as-defaults.md)).
  - Its `dxvk.conf`, `rtx.conf` and `user.conf` are merged into that layer
    (`tools\remix_defaults.py`). Texture-hash lists combine as Remix layers do.
  - The RTX add-ons' settings get the classic values once, where still at their defaults (companion,
    `tools\classic_defaults.py`). Examples: no pseudo player or pseudo weapon, the light updater
    instead of hundreds of API map lights, and the classic flashlight and water.
  - This fixes the MMD player model drawn in first person through the pseudo player, the fog-filled
    pool rooms, and the colour cast.
- **The runtime is forced windowed** (`DXVK_FORCE_WINDOWED=1` in the package), so even an in-game
  switch to fullscreen cannot reach the crash of ADR 0018.

### Added (the second field round)

- **A guard for RTX sessions in the companion**
  ([ADR 0022](docs/decisions/0022-companion-rtx-session-guard.md)). Lua from other add-ons can no
  longer undo the session's settings or switch motion blur on (FPS Boost, Draconic Base). Stock
  post-processing no longer paints over the path-traced image. `nativeloader_guard 0` turns it off.
- **One "RTX Remix" spawn-menu tab.** The RTX add-ons' panels are gathered there, with "Start here"
  and "Remix settings" (preset, upscaler, DLSS, frame generation, indirect lighting, bounces, fog,
  sky, sun, clouds, post effects). Those settings are kept across sessions.
- **An in-game guide** (`nativeloader_guide`, opens once). It covers the Remix menu and how settings
  persist, the classic defaults, lights, and troubleshooting with the log files.
- **The companion reports whether the RTX fixes reached the Remix API** ("Remix API: ready").
- **The RTX debug module ships with its add-on** (`rtx_debug`; `package_fixes.py --with-debug-module`).
- **Loader:** a layer list of 260 characters or more, which the runtime would ignore, is reported in
  the session notes.
- **`poc_session.py`:**
  - `--change-map` loads a mounted Workshop map without a save;
  - `--mount-workshop` takes several items;
  - `--no-window` uses the game's own window settings;
  - console commands wait for the console to go quiet.

### Fixed (the first field test of the release bundle; loader 0.2.1)

- **RTX sessions crashed to the desktop about 9 s after start** when the game ran in exclusive
  fullscreen. The Remix runtime crashes in its window procedure when the engine switches the
  fullscreen device; reproduced on the PoC with the field's launch options.
  - The loader now starts RTX sessions in a borderless window the size of the primary display:
    `-windowed -noborder -w <width> -h <height>`, as RTXLauncher does.
  - A window mode in the player's launch options is used as it is
    ([ADR 0018](docs/decisions/0018-rtx-sessions-in-a-borderless-window.md)).
  - The loader version is 0.2.1.

### Added (local build workflow)

- **`tools\workflow.ps1`** runs CI's build job on this machine: the Release checks (or `-SkipTests`),
  then the end-user bundle in `out\dist`. `-Install <game root>` puts the build into a game.
- **`install-loader.ps1 -ReplaceUntracked`** replaces a loader no receipt records, such as a bundle
  extracted by hand. It keeps a copy in `native-loader\replaced` first.

### Changed (rules)

- **Agents push `main` and update the project's Workshop items without asking** (the user,
  2026-10-28; [ADR 0019](docs/decisions/0019-agents-push-main-and-update-workshop.md)). Other branches,
  tags, force pushes and item visibility still need the user.

### Fixed (CI's first run)

- **`nl_activation_integration` failed on GitHub's runner** (run 40779899329).
  - The test read `nlctl`'s UTF-8 output in the runner's code page, cp1252. A non-ASCII config-file
    name came back garbled, so the CLI's plan seemed to differ from start-up's. The loader was right.
  - Tests now read `nlctl` and the C++ test hosts as UTF-8, and open journals as UTF-8.
  - With text decoded as cp1252, the test passes all 17 cases.
- **The workflow uses the Node 24 versions of its actions** (checkout v5, setup-python v6,
  upload-artifact v6, download-artifact v7). This ends GitHub's Node 20 deprecation warning.

### Added (CI and the release bundle, ADR 0017)

- **GitHub Actions** (`.github/workflows/build.yml`) builds `winmm.dll` on every push of `main`, every
  pull request, and on demand.
  - It runs `tools\test.ps1 -Config Release` on `windows-2022` and keeps the end-user bundle as an
    artifact.
  - A `v*` tag makes a GitHub release with it.
- **The end-user bundle** (`tools/package_loader.py`): a zip to extract into the Garry's Mod folder,
  holding `bin\win64\winmm.dll`, a default `native-loader\config.json` that allows Workshop item
  3829070317, and a README. The PDB ships in a symbols zip. Tested as a player would use it on the
  PoC: the loader found the item by itself, deployed it and activated RTX.
- **`install-loader.ps1 -DefaultConfig`** writes the same default config for a developer install,
  never over an existing one.

### Added (the Workshop distribution item, ADR 0016)

- **Workshop item 3829070317 now carries the RTX package subscribers use.** It is one combined
  package, `gmod-rtx-remix`: the RTX Remix runtime (runtime B, as tested in M5, M7 and R1) and the
  RTX fixes with the Lua companion. A subscriber needs only the loader's `winmm.dll`, a
  `config.json` that allowlists the item, and the subscription.
  - **First upload,** 2026-10-28: version `0.0.0-dev.20261028213205+1e486ed0`, 1,426,861,733 bytes.
  - **Checked as a subscriber** would get it, on the PoC: Steam's download was byte-identical. The
    loader deployed it from the Workshop folder. RTX on path-traced (7 of 7 patch sets, the shader
    override, 33 session variables). RTX off was vanilla, with the 9 add-on folders hidden. All
    depot files were OK afterwards.
- `tools/package_workshop.py` merges native packages into one, from folders or `.gma` archives.
- `tools/publish_workshop.py` builds the package from `tools/workshop.json` and uploads it with
  `gmpublish` only when its content changed. Its git hooks run it in the background after commits
  and merges on `main` and before pushes of `main`.

### Added (M6 follow-up: the Workshop route, tested)

- A private Workshop upload test, run with the user's approval.
  - **Upload:** GMod's `gmpublish` accepted a native package packed with `tools/gmapack`.
  - **Download:** Steam served it back byte for byte.
  - **Deploy:** the loader deployed it from Steam's Workshop folder.
  - **Update:** an update deployed at the next start.

  GMod itself does not mount an archive holding native files, so such a package's Lua comes through
  the loader's add-on folders ([ADR 0015](docs/decisions/0015-workshop-route-for-native-packages.md),
  superseding part of ADR 0012; ADR 0011 confirmed by the user).
- `tools/gmapack` is recorded as the user's own code under this repo's MIT licence (R1-025).
- **Corrected:** GMod's Steam Workshop rules do not forbid DLLs or other runtime files; they have no
  rule about file types. The wiki's `.dll`/`.exe` list describes what `gmad.exe` packs. ADR 0012
  (in a correction note), ADR 0015, the M6 report, the R1 triage and the roadmap had said otherwise.
- **New rule (AGENTS.md rule 5, the user's instruction):** agents may upload and update hidden test
  items for this project on the Workshop without asking. Nothing on the Workshop is removed or deleted
  until the user says the project is done, so test item 3829070317 stays. The earlier advice to delete
  it is withdrawn.

### Changed (R1: whole-repo review)

Codex reviewed the whole repository and reported 29 findings. All of them are triaged and fixed, or
answered ([R1 report](docs/handover/R1-report.md), [triage](docs/handover/R1-triage.md),
[ADR 0014](docs/decisions/0014-r1-hardening.md)).

- **Package areas are narrower.**
  - `garrysmod/cfg` is no longer a package area: it holds 18 of Steam's files, and a package could
    recreate one that was missing.
  - In `rtx-remix/mods`, `garrysmod/addons` and `garrysmod/data`, every file must be inside a named
    folder.
- **Activation checks deployed files.** It checks the journaled size and time of every runtime,
  config-layer and override file. A file changed since deployment is not loaded.
- **The session-variable restore keeps the user's changes.** It runs only with a readable journal, and
  puts a value back only while `config.cfg` still holds what the RTX session set.
  `session_cvars.json` is schema 2; schema 1 is still read.
- **`uninstall-loader.ps1 -RemoveConfig` keeps changed files.** It deletes the loader's own files
  only. A payload file the user changed stays, and a warning lists it.
- **`tools\test.ps1` builds first**, so the Python tests' native cross-checks run.
  **`tools\build.ps1`** puts the caller's environment back when it ends.
- **`field_snapshot.py`** (snapshot schema 3):
  - rollback never deletes; an entry it cannot move stays and is listed;
  - nothing is written through a link;
  - every saved copy is checked before anything changes;
  - the registry is pruned only after a verified import;
  - a Steam-managed install needs its depot manifests (or `--no-depot-check`), and Steam's files are
    never written back;
  - `native-loader/config.json` is kept;
  - older snapshots are refused.
- **`poc_session.py`:**
  - it sends client Lua through the console, hex-encoded, and writes nothing into an install;
  - it ends only the game it started, and that game's children;
  - `install` refuses to replace a different `config.json` without `--replace-config`, which backs
    it up first.
- **The packagers** refuse files that look private (`user.conf`, logs, `.env`, dumps) unless
  `--allow-private` names them, and write an inventory beside each output. Map compile logs are left
  out of the fixes package as junk.
- **`verify_install.py`** fails a depot path that passes through a link, and a depot file it can
  check only by size. **`poc_parity.py`** keeps every path inside the PoC.

### Fixed (R1: whole-repo review)

- `loader.log` appends and `session.json` are never written through a junction or link.
- Module hooks:
  - they stay safe while they are being removed, and after a failed install;
  - slots are recorded before they change;
  - import tables without a name table are hooked by address;
  - every PE offset is bounds-checked.
- `session.json` now has `utc` and `notes`, and each override entry has `module`, which the companion
  was already reading.
- PowerShell started by the Python tools no longer inherits PowerShell 7's `PSModulePath`, which made
  `install-loader.ps1` fail under Windows PowerShell 5.1.
- Three Python test files keep their scratch under `out\tmp` when run directly.

### Added (M7: field install)

- Field test on the user's install ([M7 report](docs/handover/M7-report.md)): RTX on next to the
  user's DXVK `d3d9.dll` and `bin\win64\vulkan-1.dll` (the package's and System32's were loaded), RTX
  off identical to the no-loader baseline, MMD Hot Loader unaffected, and a clean one-command rollback.
- `tools/field_snapshot.py`: a snapshot of what the loader and a test session can change in a real
  install (every non-depot file in the folders packages and sessions write to, by copy: the user's
  DXVK `d3d9.dll`, `vulkan-1.dll`, MMD Hot Loader and Jolt files, configs, logs, databases; folder
  listings; size and time of everything below `garrysmod/data` and `garrysmod/settings`; GMod's
  shared registry key), and a one-command rollback: uninstall, move whatever is new into the
  snapshot's debris folder (links moved, never followed), write changed files back in place (hard
  links hold), make the registry key equal to the export again, then check listings, hashes, registry
  and depot files. Tests in `tools/tests/test_field_snapshot.py` on a synthetic install.

### Added (M6: Workshop route)

- Distribution route ([ADR 0012](docs/decisions/0012-distribution-route.md)): native packages are
  released as downloads and allowlisted as local sources; the Workshop stays a supported source. GMod's
  `gmad.exe` refuses the package format ("Not allowed by whitelist" for `native/manifest.json` and a
  DLL); nothing was published.
- `status.json` lists each deployed package with its source and, for a Workshop item, the update time
  installed at start-up; the Lua companion compares it with `steamworks.FileInfo` (at start and every
  ten minutes) and asks for a restart once when Steam has a newer version. Tested under LuaJIT
  (`tools/tests/test_companion.py`).

### Added (M5: RTX fixes)

- RTX-session extras ([ADR 0010](docs/decisions/0010-rtx-session-extras.md)), applied only when a
  runtime activates: **patch sets** (byte patches written when an engine DLL is mapped, before its code
  runs, only where the pattern occurs exactly once; `-insecure` sessions by default), **module
  overrides** (a game load of `bin\win64\stdshader_dx6.dll` loads the package's copy, through import
  hooks installed at map time) and **session console variables** (a generated
  `cfg/nativeloader_session.cfg` run with `+exec`; the user's archived values recorded first and put
  back once at the next start without RTX). `nl::patch`, `nl::session`, the bootstrap's DLL-load
  watcher (`loader/proxy/modules.cpp`), `session.json`, and the manifest and journal fields.
- Add-ons of RTX-only packages are hidden from sessions without RTX
  ([ADR 0013](docs/decisions/0013-rtx-only-addons-hidden-without-rtx.md)): manifest flag
  `requires_remix` (kept in the journal); when no runtime is active, import hooks on
  `filesystem_stdio.dll`'s `FindFirstFile*`/`FindNextFile*` leave those packages' folders out of
  GMod's searches of `garrysmod\addons`, in memory, reported as `session.hidden_addons`. Found by
  the PoC: with RTX off the fixes' Lua still ran. Tested in `nl_session_integration` with a fake
  `filesystem_stdio.dll`.
- Package areas `garrysmod/addons/<addon>/` (kind `lua-addon`, [ADR 0011](docs/decisions/0011-lua-addon-folders.md):
  GMod x64 mounts add-on folders but not a loose `.gma`) and `garrysmod/data/<folder>/` (create-only
  seed data). `remix.launch_args` accepts `-insecure`; `package_runtime.py --insecure` adds it.
- Loader version 0.2.0. Tests: `test_m5.cpp` (129 core cases) and the synthetic
  `nl_session_integration` (a fake engine DLL patched before its DllMain, the override, the session
  cfg and its restore).
- `tools/poc_session.py` talks to the game through `WM_COPYDATA` console text to Source's `Valve001`
  window: a normal `quit` in single-player, a pinned camera and a hidden HUD through client Lua hooks,
  save loading (`--mount-workshop` mounts the save's Workshop map from Lua in a `-noworkshop`
  session); console text waits out a busy window, and Lua sent after a map change is checked and sent
  again; `--reference` (and `--allow-steam-managed`) leaves the install's `console.log` in place.
- `tools/poc_parity.py`: copies the reference install's user content (user.conf, saved Lua settings,
  mounts, Remix mods, a save and its Workshop map; on request its add-on folders, including the ones
  linked to working copies, and named native files such as the MMD Hot Loader's) into the PoC for a
  like-for-like comparison, in layers, and restores the PoC exactly afterwards.

- `tools/package_fixes.py`: builds the RTX fixes package (folder and/or `.gma`) from the fixes repo,
  read only: every add-on folder as kind `lua-addon` (submodule `.git` files, `*.bak` and other junk
  left out; `--exclude-addon`), the Remix mods, the built `gmcl_` modules, `stdshader_dx6.dll` as a
  `module-override`, the seven `patches64` patch sets and the RTX section of `autoexec.cfg` as
  `session_cvars` (every skipped line reported); marks the package `requires_remix`, and deploys the
  ToPBR converter's mod `~gmod_topbr`, which the fixes rewrite at run time, create-only (a reinstall
  was refused otherwise). The Steam files the fixes overwrite and the root
  `rtx.conf`/`dxvk.conf` (runtime-package layers) stay out. Reproducible; tests in
  `tools/tests/test_package_fixes.py`.
- `tools/compare_frames.py`: the user's block-difference measure for two screenshots (mean absolute
  difference of 32x32 block means) with masks and a threshold exit code, plus mean RGB and Rec. 709
  luminance percentiles per image; needs Pillow. Tests in `tools/tests/test_compare_frames.py`.
- Lua companion `companion/nativeloader`, shipped in the fixes package as the add-on
  `garrysmod/addons/nativeloader`: prints the loader's `status.json` and `session.json` to the console
  at client start and on `nativeloader_status`, and marks a report older than the session as stale.

### Added (M4: activation)

- `tools/poc_session.py`: drives PoC sessions without anyone at the keyboard (install, config, launch,
  wait for the map, `PrintWindow` screenshots, module list, a normal quit through a local remote
  console, logs, uninstall and depot verification). Used for M4's remaining real checks and M5.
- Review fixes (Claude): a successful activation is committed before the report is written, so a
  status or log write failure no longer unloads an initialised runtime; a deployment that fails and is
  undone in process activates the committed generation (`startup::after_deployment`, ADR 0009);
  `package_runtime.py` no longer adds `+mat_disable_d3d9ex 1`, which the game archives into
  `config.cfg` and so would carry into RTX-off sessions (`-nod3d9ex` remains).

- Bootstrap startup now deploys and activates the committed generation, validates runtime/layer
  files, applies reversible environment/arguments/Vulkan/DLL-search changes, and preloads the runtime
  by absolute path. Atomic status schema 1 and matching log fields report active and vanilla outcomes;
  uninstall removes generated status. CTest checks KERNEL32-only imports and a packaged fake runtime
  with static/delay dependencies, rollback and startup policy scenarios.
- `tools/poc_activation_check.ps1`: individual approved PoC launches, package A/B preparation,
  module/log/status evidence, vanilla/dxlevel comparisons, visual confirmations and cleanup. The
  user-approved `-Multirun` mode permits the other install to remain running, never another PoC.
- Loader version `0.1.0` identifies M4 activation support and satisfies the runtime packager's
  `requires_loader >=0.1.0` contract (root project version bump approved by the user).
- Startup deployment policy ([ADR 0009](docs/decisions/0009-startup-deployment-last-good.md)) keeps
  the last good generation when an allowlisted source fails, including during staging, distinguishes
  explicit addon disable, and excludes only the current process from the running-game check.
  Explicit CLI apply retains its M3 behavior. Steam registry lookup loads its system library on demand.
- Corrections before integration: command-line swaps validate and update the complete cached
  string descriptors, roll back partial failures and expose explicit/scoped restoration. A separate
  process tests the real kernelbase/PEB round trip. Package config layers now precede existing user
  lists, retaining the user's final editable layer; ordinary environment values remain untouched.
- `nl_core`: `nl::activate::plan` ([ADR 0008](docs/decisions/0008-activation-at-startup.md)), a pure
  function turning the deployed generation, config, environment and command line into the start-up
  steps: the `d3d9.dll` to preload and the folder to add to the DLL search, the config-file layer
  lists (package layers below the user's root `rtx.conf`, relative to the game root), the package
  environment (the user's own values winning) and the launch arguments to add (those the user did
  not pass).
- `nl_core`: `nl::cmdline` — command-line tokenising, and `append_arguments`, which adds the
  runtime's launch arguments in memory by pointing kernelbase's `GetCommandLineW`/`GetCommandLineA`
  caches and the PEB at longer strings, after checking each getter is the expected
  `mov rax,[rip+disp]; ret` shape and points at this process's command line.
- `nlctl activation <game root>`: read-only, prints what start-up would load, set and add.
- Tests: 12 new `nl_tests` cases (106 in all) for `activate::plan` and `nl::cmdline`, the latter
  including the command-line swap against this process's real kernelbase.
- `tools/package_runtime.py`: builds an RTX Remix runtime package (a package folder and/or a `.gma`)
  from the fork's runtime build folder (`_output`), hashing every file as it is copied. Excludes
  `.exp/.lib/.ilk/.bak` and (unless `--with-pdbs`) `.pdb`; `--d3d9-from` overrides `d3d9.dll` from
  another build folder; `--rtx-conf` / `--dxvk-conf` add config layers; `--env`, `--id`, `--version`
  and more set the manifest. The default version derives from `d3d9.dll`, so the output is
  reproducible. Tests in `tools/tests/test_package_runtime.py`.

### Added (M3: deployer)

- `nl_core`: the transactional deployer `nl::deploy` (`apply`, `rollback`, `uninstall`, `recover`,
  `status`; [ADR 0007](docs/decisions/0007-transactional-deployment.md)):
  - each run is one journaled transaction;
  - staging checks every file's size, CRC-32 and SHA-256 before anything in place changes;
  - the intent is written first, renames stay on one volume, and recovery rolls an unfinished
    transaction back;
  - two generations are kept, and rollback holds the previous one;
  - one deployer at a time, refused while the game runs;
  - runs with nothing to do write nothing.
- `nl_core`: SHA-256 through Windows CNG (`bcrypt.dll` loaded from System32 on first use; the
  bootstrap still imports only KERNEL32). Also:
  - `nl::fs`: every change goes through one countable layer, with write-through renames, retries
    while a scanner holds a file, long paths and refused links;
  - the journal `native-loader\state.json` schema 1;
  - one-pass, bounded-memory extraction (`gma::extract`, `Contents::extract`).
- `nlctl apply | status | rollback | uninstall`, with `--dry-run` and `status --verify`.
- `tools/uninstall-loader.ps1`: `nlctl uninstall`, then `install-loader.ps1 -Uninstall`; keeps
  `config.json` unless `-RemoveConfig`.
- `tools/poc_deploy_check.ps1`: the M3 acceptance run on the PoC without starting the game. It
  passed on 2026-10-27: 3,113 entries identical afterwards, 2,877 depot files OK.
- Tests:
  - 32 new `nl_tests` cases (94 in all);
  - fault injection at every file-system change of a first deployment, an upgrade, a rollback and
    an uninstall: interrupted and failed in process, and killed for real (`nl_fault_host`,
    `deploy_faults.py`; 174 kill points);
  - `nlctl_e2e_deploy`;
  - `nlctl_uninstall_loader`: `uninstall-loader.ps1` in synthetic game folders.
- Docs: ADR 0007; the `state.json` schema in `ON_DISK_LAYOUT.md`; the deployment section of
  `ARCHITECTURE.md`; M3 checks in `TESTING.md`; measurements in `RESEARCH.md` section 9.

### Fixed (M3, after an independent review, before the merge)

Each fix comes with a test; ADR 0007 records the resulting rules.

- Recovery could move a whole new payload folder back into staging, which is then deleted, taking a
  file someone had put into that folder with it. Payload files are now moved one by one, each with
  its hash.
- A file the loader had adopted, then put back itself after the user deleted it, stayed "adopted"
  across a rollback. A later clean-up could then delete a file the journal still listed. It now
  belongs to the loader.
- Paths the deployer builds can be longer than the 1,024 bytes a package path may have, which made
  `state.json` unreadable. The journal now accepts up to 4,096 bytes.
- A retired file that could not be deleted (read-only, open elsewhere) made every command fail. It
  now stays listed with a note, and uninstall keeps its journal until it is gone.
- The loader folds case only for ASCII, but NTFS ignores case for every letter, so a renamed
  non-ASCII path broke ownership. Deployed package paths must now be ASCII.
- An undo skipped because a file had changed left its backup copy behind, untracked for good. Such
  copies are now retired, and folders that cannot be removed stay listed.
- A run that changed nothing did not end a rollback's hold, and a package that was broken at check
  time could lift it. The hold is now compared with the plan before re-planning, and ends, recorded
  in the journal, once the plan differs.
- Putting back a deployed file that had gone missing left the previous generation claiming a copy
  that did not exist, so rollback always refused.
- Links were refused only for new targets. Removals, rollback moves, clean-up and undo now refuse
  them too.
- Test-found: the running-game check took a `gmod.exe` that exited during the scan for a running
  one. It now ignores processes that are gone.

### Changed (M3)

- `nl::package::Package` gains `manifest_sha256` (the package version's identity), and `Contents`
  gains `extract()`.
- Payload folders are `native-loader\packages\<id>\<version>_<generation>\`, refining ADR 0004's
  `<id>\<version>\`. The plan had a manifest-hash suffix; the generation number lets a damaged
  folder be replaced without a name clash.
- CTest runs six tests at a time (`CMakePresets.json`). `nl_tests` accepts `--skip=<text>`, and the
  three exhaustive fault cases are CTests of their own.

### Changed (M1 and M2 merged into `main`)

- `main` now holds the inert bootstrap (M1, Codex, reviewed) and the core library and CLI (M2),
  merged without conflicts; Debug and Release CTest pass 6/6 on the result. AGENTS.md, the roadmap,
  the component map, TESTING.md and the handover index describe the merged state; M3 (deployer) is next.

### Added (M1: inert bootstrap)

- Synthetic executable fixtures stay inside the build directory, respecting the user's chosen
  build location instead of copying binaries to the system temporary directory.
- Test discovery checks paths relative to the repository, so a worktree under an ancestor `out`
  directory still runs all Python suites.
- Chromium helpers using `gmod.exe --type=...` remain pure pass-through; only the main game writes
  the startup log. Smoke tests verify that log's PID, preventing helper logs from masking timing
  evidence or bypassing the command-line off switch.
- `loader/proxy`: x64 `winmm.dll` with generated MASM forwarding for all 181 system ordinals
  (180 names and one ordinal-only export), version identity, host gating, all three off switches,
  PE entry-point hook, guarded UTF-8 startup logging and five-log rotation.
- CTest export/forwarding tests, synthetic-host startup/off-switch/failure/rotation tests, and
  installer ownership/hash/Steam-managed protection tests.
- `tools/install-loader.ps1`: PoC-default DLL/PDB installation, SHA-256 receipt, foreign/user-edit
  refusal, opt-in Steam-managed protection and state-preserving uninstall.
- `tools/smoke_test.ps1`: five PoC map loads, strict console comparison, two inert console tools,
  evidence capture and restoration of prior loader state.

### Added (handover)

- `docs/handover/`: the M1 brief for Codex (scope, boundaries, definition of done, report format),
  the Codex set-up notes and paste-ready prompt, and the conventions for briefs and reports.
- AGENTS.md rule 8: parallel milestones run on their own branch and worktree and keep to their paths.

### Changed (repo rules)

- AGENTS.md rule 9 (user instruction): temporary and build files stay inside the repo under the
  git-ignored `out\` (builds, worktrees, test scratch, evidence). `tools/test.ps1` and
  `tools/build.ps1` point `TEMP`/`TMP` at `out\tmp` while they run.

### Added (M2 part 2: config, discovery, planner)

- `nl_core`: `config.json` schema 1 (the allowlist; strict, unknown keys and numeric Workshop ids
  rejected), a KeyValues reader, discovery of allowlisted sources without the Steam API
  (`libraryfolders.vdf`, `appworkshop_4000.acf`, `addonnomount.txt`, `*_legacy.bin`), and the
  planner (ADR 0006: dev folder > local > Workshop, one runtime, no overlapping root files).
- `nlctl plan <game root>`: what the loader would activate and why, read-only.
- CTest `nlctl_e2e_plan`: the whole chain on gmapack-built packages in a fake Steam library.
- `docs/ON_DISK_LAYOUT.md` specifies the implemented `config.json`.

### Added (M2 part 2: manifests and packages)

- `nl_core`: manifest schema 1 (`nl::manifest::parse`, strict, unknown keys rejected; SemVer; launch
  argument and environment allowlists; root areas and policies) and `check_contents`, which refuses
  unlisted native files. `docs/PACKAGE_FORMAT.md` now specifies what the code enforces.
- `nl_core`: packages from a `.gma` or a development folder (links and reparse points refused);
  `gma::read_entry` reads one file, seeking in plain archives and CRC-checking it.
- `nlctl manifest <file.gma|folder>`.

### Added (M2 part 2: LZMA, JSON, path rules)

- `third_party/lzma`: the LZMA SDK decoder (public domain, 7-Zip tag 26.05, unchanged, hashes in
  its README), built as `nl_lzma`.
- `nl_core`: streaming `lzma::Source` for LZMA-wrapped archives (Workshop `*_legacy.bin`),
  including GMod's 8-byte footer (size, then `0xBEEFCACE`); `open_archive` now reads them.
- `nl_core`: strict JSON parser for manifests and `config.json`; shared UTF-8 validation; path rules
  for anything a package names and the root areas packages may write to.
- `nlctl` reports container, stream size, completeness, CRC trailer and LZMA footer.

### Changed (M2 part 2)

- The 4-byte archive CRC trailer is optional: 19 legacy Workshop items have none and GMod mounts
  them. Only streams cut inside the contents or the trailer are truncated.
- Real data: all 753 installed Workshop archives parse; all 81 legacy items verify (4.4 GB, every
  CRC and footer). `tools/gmapack/gmapack.py` rejects GMod's LZMA footer, so it cannot read them.

### Added (M2 part 1: GMA reader and nlctl)

- `nl_core`: GMA reader for GMAD v1-v3 (header and index with gmapack-compatible limits and
  rejections, single-pass `verify` of every CRC and trailing data, container detection,
  share-all file reading), CRC-32, and JSON string quoting that replaces invalid UTF-8.
- `loader/cli`: `nlctl inspect | verify | scan` (read-only), with a CTest that checks it against
  `tools/gmapack/gmapack.py` on synthetic archives, including damaged ones.
- Test harness: `CHECK_THROWS_AS` and `scratch_dir()` (scratch beside the test executable).
- First real-data run: all 672 installed Workshop `.gma` indexes (98,656 entries) parse without
  errors; the 81 older `*_legacy.bin` items are LZMA-wrapped and wait for the decoder.

### Added (M0: repo scaffold)

- Repo initialised on top of `origin/main` (SheepyLord/-Gmod-Workshop-RTX-Remix).
- Agent-facing docs: `AGENTS.md` (rules, commands, documentation duties), `CLAUDE.md` importing it,
  `docs/` with architecture, components, package format draft, on-disk layout, testing, roadmap,
  environment, research notes and decision records 0001-0005.
- C++ build skeleton: CMake presets `win64-debug` / `win64-release` (MSVC x64, Ninja, static CRT,
  `/W4 /WX`), `nl_core` library and `nl_tests` with an in-repo test harness.
- `tools/build.ps1` (configure, build, CTest) and `tools/lib/VsDevEnv.psm1` (MSVC environment,
  works even when `vswhere` cannot see Build Tools).
- `tools/test.ps1` runs every check; `tools/check_repo.py` enforces the documentation conventions
  (a `.md` beside every script, module READMEs, working links, this changelog, the component map).
- `tools/steam/`: depot manifest parser, `verify_install.py` (is an install vanilla?) and
  `make_vanilla_copy.py` (byte-exact vanilla copy from an existing install, no download), with tests.
  `GarrysMod_PoC` was built with the prototype of this tool on 2026-10-27.
- `tools/diag/pe_imports.py`: lists PE imports/exports (hook-point research).
- `tools/gmapack/`: the GMA File Packer, vendored unchanged except for added script docs.

### Decided

- Bootstrap is a `winmm.dll` proxy that runs its set-up at the EXE entry point (ADR 0001).
- Payloads are source-agnostic; Workshop route decided after a private upload test (ADR 0002).
- Only allowlisted packages may deploy native code until signatures exist (ADR 0003).
- The Remix runtime is preloaded from a versioned folder instead of being copied into `bin\win64` (ADR 0004).
- Repo conventions: script docs, changelog, decision records, MIT licence (ADR 0005).
