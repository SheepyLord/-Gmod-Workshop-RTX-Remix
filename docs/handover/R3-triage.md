# R3 triage

Claude's verification of every finding in [R3-report.md](R3-report.md) (Codex, `7ee1a6f` on
`r3-review`), with the user's R3-015. Each was checked against the code at `ec37c91`; the fixes are on
`r3-fixes`, each with a regression test unless noted. "Severity" is this triage's, beside Codex's.

| ID | Codex | Verdict | Severity | What was done |
|---|---|---|---|---|
| R3-001 | P0 | Confirmed: the gap is real; it is not a boundary against a local attacker | P2 | **Waiting on the user's decision** (below). Not changed |
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
patch sets and the shader override. Left unchanged until the user decides.

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

## Left open

- R3-001: the user's decision.
- R3-002: a disc tint, if the user wants it (a runtime rebuild).
- R3-011: the licence review before anything goes public.
- R3-015: a look in game (the default interval's smoothness and cost).
