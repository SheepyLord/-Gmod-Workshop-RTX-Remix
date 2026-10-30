# R3 triage

Claude's verification of every finding in [R3-report.md](R3-report.md) (Codex, `7ee1a6f` on
`r3-review`), with the user's R3-015. Each was checked against the code at `ec37c91`; the fixes are on
`r3-fixes`, each with a regression test unless noted. "Severity" is this triage's, beside Codex's.

| ID | Codex | Verdict | Severity | What was done |
|---|---|---|---|---|
| R3-001 | P0 | Confirmed: the gap is real; it is not a boundary against a local attacker | P2 | Fixed as the user decided: the package's files are put back, what was in their place kept, dependencies load only as deployed (ADR 0035, loader 0.6.0; branch `r3-001`) |
| R3-002 | P1 | Confirmed: the textured Moon ignores `moon0.color` | P3 | Kept as designed for now (below) |
| R3-003 | P0 | Confirmed (Codex's repro) | P1 | Fixed: unpack hashes every file it keeps |
| R3-004 | P0 | Confirmed | P1 | Fixed: `--commit`, built from the checkout that has the pushed commit |
| R3-005 | P1 | Confirmed | P2 | Fixed: a Windows file lock held for the whole run |
| R3-006 | P0 | Confirmed (Codex's repro) | P1 | Fixed: links and junctions refused before the first write |
| R3-007 | P1 | Confirmed | P2 | Fixed: every source hashed; inventory cross-check; atomic index |
| R3-008 | P0 | Confirmed (Codex's repro) | P1 | Fixed: every part path checked before anything is written |
| R3-009 | P1 | Confirmed (Codex's mock) | P2 | Fixed: clearing the weather puts Remix's own values back |
| R3-010 | P2 | Confirmed as described; rejected as a bug | — | Documented as the intended behaviour |
| R3-011 | P2 | Confirmed, and the fixes' GPL text (a known gap) too | P2 | Fixed: the licence texts ship beside their add-ons |
| R3-012 | P1 | Confirmed | P2 | Fixed: the default config is checked first and written inside the rollback |
| R3-013 | P1 | Plausible (no live repro) | P3 | Fixed: a partial first mount waits up to 20 s for a remount |
| R3-014 | P1 | Confirmed, and worse: the shipped DLL was not what `runtime/` builds | P1 | Fixed: exact worktree check, `-Verify`, build record and repo gate (ADR 0034) |
| R3-015 | (user) | The sky's 0.25 s update moved it in visible steps | — | Fixed: `nativeloader_sky_interval`, default 0.02 s, slider, six languages |
| R3-016 | (user) | Confirmed in the live game: Modern House RTX forced `r_forcehwlight 1`, and Source's hardware skinning then gives Remix no bones | P1 | Fixed in Modern House RTX; item 3829275998 updated; the user confirmed it in game |
| R3-017 | (Claude, while probing R3-016) | A `DXVK_CONFIG_FILE` over 259 characters reads as empty in the runtime and drops every package layer; the published package's is 273-277 without an NVIDIA GPU | P1 | Fixed as the user chose: the runtime reads short copies of the layers (ADR 0036, loader 0.6.0) |

## The findings

**R3-001: dependency DLLs load without a check.** `modules::load_first`
(`loader/proxy/modules.cpp:188-211`) loads each `load_first` file (Model Hotloader's
`garrysmod/lua/bin/mmdhl_runtime_win64.dll`) by its path, in RTX sessions (`runtime.cpp:324-329`) and
without a runtime (`startup.cpp:189-194`). The runtime's own files and the shader override are checked
against the journal's size and time first (`runtime.cpp:158-182`, R1-008); these are not. The deployer
leaves a file the user changed in place (`deploy.cpp:713/721`, `keep_edited`), so a changed DLL there is
what the loader loads. Not a boundary against someone who can write the folder: GMod's own `require`
loads any `gmcl_*.dll` there with no loader involved, and such a writer could replace `winmm.dll`
itself. It is a consistency gap: the loader should not itself load native code it did not deploy.
The user asked for an explanation and a question first, because a GMod update changes game binaries;
see the closing message of the session and RESEARCH.md section 31 for what such an update does to the
patch sets and the shader override.

The user decided: "Proceed to Restore automatically: put the package's copy back at the next start.
Everything should respect this package", and a `winmm.dll` already there before the install is kept
and put back at uninstall. Done on branch `r3-001`
([ADR 0035](../decisions/0035-restore-automatically.md), loader 0.6.0):
- A `replace-owned` file that changed is put back at the next start (`put-back`), the changed copy
  kept in `native-loader/backup/edits/<transaction>/`; `keep_edited` is left for `create-only` files.
- A file in a package's way, or an adopted one the package now differs from, is taken over
  (`take-over`): kept in `native-loader/backup/originals/` (journal `originals`) and put back by
  clean-up once no generation names its path and the path is free (`restore-original`), which
  `nlctl uninstall` reaches too. An undo never retires a file moved into either folder.
- `session::deployed_files`: `load_first` files load only when the current generation records them
  with their size and time, in RTX sessions (`runtime.cpp`) and without RTX (`startup.cpp`); the others
  are left out with a session note.
- `install-loader.ps1` keeps a foreign `winmm.dll` (and its PDB, unless the loader's) in
  `native-loader\original\`, recorded in the receipt, and `-Uninstall` puts it back.
- Tests: six deployer cases (foreign and adopted files, put-back with rollback, a new version over an
  adopted file, an original dropped two generations later, one whose place is taken, one put back at
  once on unsubscribe), the journal's `originals`, `deployed_files`, and the installer's (49 checks).

**R3-002: the textured Moon ignores `rtx.atmosphere.moon0.color`.** Confirmed in
`runtime/patches/0004` (`evalTexturedMoon`, the albedo is the map scaled to `moonTextureAlbedo`). The
textured Moon's colour is the real Moon's, from the map; its brightness is `moonTextureAlbedo`. The
companion sets `moon0.color` to `0.11, 0.12, 0.135`, a cool tint that the moonlight and the halo use.
Tinting the disc by it would turn the approved Moon bluish, and needs a runtime rebuild; leaving the
companion's colour neutral would change the moonlight instead. Kept as it is, and documented here and
in RESEARCH.md; a tint relative to the option's default grey (0.12) is ready to add if the user wants
the Remix menu's colour to reach the disc.

**R3-003.** `inputs.unpack` kept a file on matching size and time. It now hashes every kept file
(threads, about 1.8 GB a build) and rewrites one that differs. Test: a same-size, same-time edit is
rewritten.

**R3-004.** The shared `pre-push` hook ran the publisher of the worktree the push ran in. Every hook
now passes `--commit <sha>` (`pre-push`: the commit sent to `main`; a deletion publishes nothing);
the publisher finds the checkout whose `HEAD` is that commit (`checkout_at`, this one first, then
`git worktree list`), runs that checkout's script, and the build checks `HEAD` again. No checkout at
the commit: nothing is published, with the reason in the log. Test: two worktrees, each commit found
in the right one, a commit checked out nowhere found nowhere.

**R3-005.** `acquire_lock` created the file, then wrote its PID; a second run could read the empty file
as a dead owner's. The lock is now `msvcrt.locking` on the file's first byte, held by the open handle
until the run ends; Windows drops it when the process exits, so nothing is ever taken over. Test: a
second handle is refused; a process that exits holding the lock leaves it free.

**R3-006.** Unpack followed a junction at `out\inputs\<part>` and deleted the target's files as stale.
It now refuses a link or junction at the destination, the part's folder or anywhere below, before
writing (`refuse_links`, by `FILE_ATTRIBUTE_REPARSE_POINT`). Test: a junction at the part's folder and
one deeper, the target's file untouched.

**R3-007.** Import skipped a source by size and time. It now hashes every source and skips only the
indexed SHA-256; a source whose hash is not the inventory's (changed after the packager read it) stops
the import; `files.json` is written through a `.tmp` and renamed. Tests: a same-size, same-time change
is stored; a changed inventory source is refused.

**R3-008.** `package_workshop.Part` used manifest paths unchecked; `folder / "H:\x"` is `H:\x`, and the
copy opened it for writing before reading the source. Every part's paths are now checked when the part
is opened (under `native/payload/` or `native/root/`, no empty, `.` or `..` segment, no drive, colon,
backslash or control character), and each target must resolve inside the staging folder. Test: seven
bad paths, the sentinel file untouched.

**R3-009.** Clearing the weather stopped sending it but left the last preset's values. The companion
records the options its weather set and, on clearing, sets each back to rtx.conf's value
(`GetConfigVariable` reads only that file: the RTX fixes' `remixapi.cpp`) or, without one, to what
Remix has without it: the package's classic layer, else the runtime's default, which
`tools/weather_presets.py` now reads from the fork's `RTX_OPTION` declarations into
`weather_presets.lua` (`defaults`, 61 options). A chosen fog preset keeps its fog. The RTX fixes'
per-map settings are not known to Lua and are not restored. Test (LuaJIT mock): after Rain, clearing
gives rtx.conf's cloud density and the defaults' rain intensity, spawn radius and lightning; nothing
more is sent afterwards.

**R3-010: rejected.** The companion sends a value when its own changes, and so does not take back what
another add-on or the player in the Remix menu (Alt+X) set later. Re-sending everything periodically
would undo the player's own Remix-menu changes while a weather is set. Only on a map whose add-on sets
the sky, after the player took it over, is everything put back every 10 s (ADR 0031). Documented in
`nativeloader_sky.lua.md`.

**R3-011.** The licence texts kept beside three parts in `packages/` were not in the package: Model
Hotloader's `LICENSE` and the 27 of `licenses/`, Character Motion Importer's `LICENSE`, and the RTX
fixes' GPL-2.0 `LICENSE` (the known gap from before R3). `package_content.py` and `package_fixes.py`
take `--add-to-addon PATH SOURCE` (new files only, never over the add-on's own), and `workshop.json`
puts them at `garrysmod/addons/mmd_hotloader/LICENSE` and `licenses/`, `mmd_vmd_npc/LICENSE` and
`remixbinary/LICENSE`. Whether each library's licence asks for more than its text (a source offer under
the MPL-2.0 or the GPL, for one) is still the licence review AGENTS.md rule 7 requires before anything
goes public. Test: texts added, junk left out, a path the add-on has or an unknown add-on refused.

**R3-012.** The `-DefaultConfig` copy ran after the install's rollback block. The shipped file is now
checked (present, valid JSON) before anything is written, and copied inside the block, whose rollback
removes a partial `config.json` with the DLL, PDB and receipt. The installer's tests pass; no
fault-injection test (the copy's source is the repository's own file).

**R3-013.** `wait_workshop` took any first mount that mounted something. The PoC's measured sequence
(RESEARCH.md section 24) mounts 0 first; a partial first mount was not seen, but a remount could
follow one. Now: 0 of M waits for the remount as before; all of M is final; some but not all waits up
to 20 s (`PARTIAL_MOUNT_GRACE`) for `Addons have changes - remounting`, and the second mount if one
starts. The record says which rule decided (`workshop_ready_by`). Test: both cases.

**R3-014.** `build_runtime.ps1` accepted an existing worktree by commit subjects, ignored submodules and
untracked files, and nothing tied the stored DLL to the patches. Now the worktree's tree must equal the
tree the patches make (scratch index, the fork only read); no uncommitted change; no untracked folder
but declared clones; every submodule and clone at its commit with exactly its patch; `-Verify` runs only
the checks. `base.json` `packaged` records what the stored DLL was built from, and
`tools/check_repo.py` fails while `runtime/` differs (CI runs it on every push). Run against the
worktree the shipped DLL was built in, the check found four inputs `runtime/patches` did not hold
(NVAPI R615 instead of the recorded R570, three uncommitted RTXDI shader changes, and the DLSS 310.9.1
and SHARC 1.8.3 clones the tree does not record; RESEARCH.md section 31). They are now in `base.json`
and `runtime/submodules/rtxdi.patch`, `-Verify` passes on that worktree, and its built DLL is the
packaged one. A build in a fresh worktree needs the network and was not run. `runtime/**` stays out of
the package workflow's paths and the publish fingerprint: the package reads only `packages/`, and the
gate makes a patch change fail until the DLL is rebuilt and imported. Test: the gate passes, ignores
`why` texts, and fails on a changed patch, submodule setting or stored DLL.

**R3-015 (the user).** The sky timer ran every 0.25 s. It now runs every `nativeloader_sky_interval`
seconds (default 0.02, 0 for every frame, 0-1, a saved client setting, reset by
`nativeloader_sky_reset`), adjusted when the setting changes, which does not take a map's sky over;
a slider under "Sky and weather" (0-0.25 s), translated in the six languages. The rain's fade under a
roof now follows the time passed, so it stays half a second at any interval. Unchanged values are
still not sent again, so a still sky costs Lua work only. Tests (mock): the default, the adjustment,
the map's sky kept; the fade unchanged at 0.25 s steps. Not measured in game yet.

**R3-016 (the user): limbs in bind pose on Modern House.** On `modern_house`, new HSR characters, their
ragdolls, the player and the hands were drawn with limbs, clothes and hair at the pelvis; Model
Hotloader's models and Hibiki were right. Found in the user's live session (RTXDebug module, then a
probe build of the runtime deployed from a dev folder): Modern House RTX set `r_forcehwlight 1`; the RTX
fixes then light every model on the GPU, and with `r_forcehwskin 0` Source skins a model without a
`.sw.vtx` through its fixed-function hardware path, which never sets the vertex-blend state, so Remix
draws it rigid on its first bone. Setting it to 0 in the live game fixed every model at once. The
classic install never had it on (its `+r_forcehwlight 1` comes before the variable exists), and the
loader's `mat_softwareskin 1`, which would cover it, is a cheat variable that Source resets when
`sv_cheats` goes back to 0. Fixed in Modern House RTX (`garrys-mod-rtx-remixed`
`claude/modern-house-rtx` `e96ad7f`), and the hidden item 3829275998 updated. RESEARCH.md section 32.
Possible hardening in the RTX fixes (the user's GPL repository, not changed here): their hook could
leave skinned models alone while `r_forcehwskin` is 0, and their `autoexec.cfg` line
`r_forcehwlight 1` (inactive today, for the reason above) could go.

**R3-017 (found while probing R3-016): a long `DXVK_CONFIG_FILE` drops every layer.** The runtime reads
environment variables into a `MAX_PATH` buffer; a value of 260 characters or more reads as empty, and
the runtime then loads `dxvk.conf` alone, silently. The loader writes the layers' paths relative to the
game folder, so the Steam path does not count, but the package's id and version appear twice. The
published package's value is 237-241 characters on an NVIDIA GPU and 273-277 without one (the
non-NVIDIA layer adds 37): so without an NVIDIA GPU an RTX session runs without the package's layers
today. A probe package at 261 characters started with a black screen. The limit itself was known
(RESEARCH.md section 19; the loader only noted a long list). Fixed as the user chose ("Yes, fix
R3-017"; [ADR 0036](../decisions/0036-remix-layers-as-short-copies.md)): the plan lists each package
layer as `native-loader/remix/dxvk-<n>.conf` or `rtx-<n>.conf`, which the bootstrap writes at every RTX
start from the payload file it has just checked, byte for byte; one it cannot write goes back to its
source in the list (`activate::use_sources`), with a note. The published package's list is now 73
characters, 109 without an NVIDIA GPU. Tests: the plan's lists for the published payload folder and a
far longer one, on an AMD GPU; `use_sources`; in the activation integration test, the copies equal
their sources, a copy changed by hand is written again, and a folder in a copy's place falls back to
the source. The root fix, a larger buffer in the runtime's `getEnvVar`, waits for the next runtime
build. RESEARCH.md section 32.

## Evidence

- Branch `r3-fixes`, worktree `out\worktrees\r3-fixes`: `tools\test.ps1` passed: `repo conventions OK`;
  `100% tests passed, 0 tests failed out of 17`; GMA tests 28 (1 skipped), Steam tool tests 25 (1
  skipped), tool tests 187; `All checks passed.`
- `python tools\build_package.py --require-nlctl --compare <main>\out\workshop\published.json`: built
  and validated, 1,798,932,095 bytes; it differs from the published item (digest `3a1b69e0...` against
  `942d0083...`) by exactly 30 added files (the licence texts) and three changed companion files
  (`nativeloader_sky.lua`, `weather_presets.lua`, `i18n_data.lua`); no other manifest key changed.
- `runtime\build_runtime.ps1 -Verify` on `remix-i18n`: "is what runtime\base.json builds ... 4
  patches (tree 815f0dca...), 2 submodule settings, 2 clones"; built DLL `d9cf79e6...`, the packaged one.
- Branch `r3-001` (R3-001, worktree `out\worktrees\r3-001`): `tools\test.ps1` passed: `repo conventions
  OK`; `100% tests passed, 0 tests failed out of 17`; GMA tests 28 (1 skipped), Steam tool tests 25
  (1 skipped), tool tests 188; `All checks passed.` The installer's tests alone: `Installer OK: 49
  checks`.
- R3-016: in the live session, `r_forcehwlight 0` put every model right and 1 broke them again; after
  the R3-016 probe the runtime worktree was put back and `-Verify` passes again (the rebuilt DLL differs
  from the packaged one only in its stamps, RESEARCH.md section 32). Steam has the updated Modern House
  item (`modern-house-rtx.gma`, SHA-256 `d90c206b...`). Checked in the field install afterwards: the
  start deployed it (`modern-house-rtx 0.0.0-dev.202610300425+d7efd636`) with the Workshop RTX package;
  on `modern_house`, `r_forcehwlight` read 0 and `mat_softwareskin` 1, and the user confirmed the
  meshes and bones are right. The first load of the map after Steam's update ended in an engine error
  during loading (a GMod crash dump, `tier0`/`engine.dll`/`GameUI.dll`, no Lua state yet, the runtime's
  log quiet); the next start loaded it.
- R3-017 (branch `r3-001`): `tools\test.ps1` passed (`repo conventions OK`; 17 of 17 CTests; GMA 28,
  Steam tools 25, tools 188; `All checks passed.`), with the field game running. The activation
  integration test's 21 cases include the copies, a rewritten copy and the fallback (`the Remix layer
  native-loader/remix/dxvk-1.conf was not written (... Windows error 5); the runtime reads
  native-loader/packages/m4-runtime/1.0.0_1/config/dxvk/01_defaults.conf instead`). `nlctl activation`
  on the PoC's RTX package: `DXVK_CONFIG_FILE=native-loader/remix/dxvk-1.conf,native-loader/remix/dxvk-2.conf,dxvk.conf`
  (73 characters); neither of its layers holds a path.
- R3-017 and R3-001 in a real RTX session (the user: "Run the session now"): loader 0.6.0 (Release)
  installed in the PoC, `poc_session.py run --addons` on gm_construct (evidence `out\r3-017-poc`). The
  start deployed the Workshop package (generation 26, 318 changes; one note, a create-only file kept;
  nothing put back or taken over) and activated it. `status.json`: `DXVK_CONFIG_FILE` set to
  `native-loader/remix/dxvk-1.conf,native-loader/remix/dxvk-2.conf,dxvk.conf` (73 characters), both
  copies byte-identical to their payload files. The Remix log: "Using config paths from
  DXVK_CONFIG_FILE: native-loader/remix/dxvk-1.conf,native-loader/remix/dxvk-2.conf,dxvk.conf", "Found
  config file" for both. The map loaded in 17.5 s, the frames are path-traced (no black screen), 7
  patches, the shader override, Model Hotloader's runtime loaded before its modules (no session notes),
  no Lua errors, a normal quit. Not run on a GPU that is not NVIDIA's.
- While a game held most of the memory, the installer's tests failed with `OutOfMemoryException`:
  `install-loader.ps1` kept its rollback copies as arrays of boxed bytes (3.1 GB at the peak). Fixed; 236
  MB.

## Left open

- R3-002: a disc tint, if the user wants it (a runtime rebuild).
- R3-017: the runtime's own 260-character buffer (`getEnvVar`), at its next rebuild; a session on a GPU
  that is not NVIDIA's has not been run.
- R3-011: the licence review before anything goes public.
- R3-015: a look in game (the default interval's smoothness and cost).
