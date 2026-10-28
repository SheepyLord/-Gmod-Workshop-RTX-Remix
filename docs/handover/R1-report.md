# R1 whole-repository review

## Summary

- Reviewed commit: `c540358` (`r1-review`; M0–M7 plus the R1 brief).
- Method: clean-worktree baseline, source and contract review, focused synthetic repros where needed. No game launch, game-install write or network use.
- Baseline: `tools\test.ps1` passed: repository conventions; Python 28 + 19 + 44 = 91 tests (8 skipped); Debug CTest 16/16; `All checks passed.`
- Baseline: `tools\build.ps1 -Config Release` passed: Release CTest 16/16; `Build win64-release OK`.
- Post-build verification: a second `tools\test.ps1` ran the native-dependent Python branches and failed one `test_field_snapshot` case because legacy PowerShell could not resolve `Get-FileHash` (R1-029). Its CTest still passed 16/16. This does not change the clean-worktree baseline result.
- Findings: P0 12; P1 8; P2 7; P3 2. All 159 listed source files and their applicable design and script documentation were reviewed within the brief's scope.

## Findings

| ID | Severity | Area | File:line | Title |
|---|---|---|---|---|
| R1-001 | P0 | A | `loader/proxy/startup.cpp:50,112,261` | Diagnostic log writes through a junction after refusing it |
| R1-005 | P0 | A | `loader/proxy/modules.cpp:504-510` | Session report replaces a user file through a junction |
| R1-007 | P0 | B | `loader/core/src/deploy.cpp:692-708` | A package can create a missing Steam depot file |
| R1-008 | P0 | A/B | `loader/core/src/deploy.cpp:198-202,603-625`; `loader/proxy/runtime.cpp:144-154` | Modified runtime bytes can activate without matching the allowlisted package |
| R1-009 | P0 | D | `tools/field_snapshot.py:84-93` | Rollback deletes a new entry when its move fails |
| R1-010 | P0 | D | `tools/field_snapshot.py:325-335` | Restore follows a junction and overwrites its target |
| R1-011 | P0 | D | `tools/field_snapshot.py:203-219` | Failed registry import still prunes user values |
| R1-012 | P0 | D | `tools/field_snapshot.py:103-113,245-261,325-335` | Missing depot manifests make rollback overwrite Steam files |
| R1-013 | P0 | D | `tools/field_snapshot.py:325-335` | Corrupt snapshot copies are written to user files before verification |
| R1-014 | P0 | B/D | `loader/core/src/deploy.cpp:295-319,1226-1237`; `tools/uninstall-loader.ps1:29-31` | RemoveConfig deletes changed package files that uninstall said it kept |
| R1-015 | P0 | D | `tools/poc_session.py:308-314,521-524` | Reference mode deletes an existing user data folder |
| R1-026 | P0 | D | `tools/poc_session.py:350-370`; `tools/field_snapshot.py:33-45` | Session install overwrites an existing allowlist without a backup |
| R1-002 | P1 | A | `loader/proxy/modules.cpp:299-305,441-452`; `loader/proxy/runtime.cpp:233-235` | Failed hook installation can leave active, untracked import hooks |
| R1-003 | P1 | A | `loader/proxy/modules.cpp:149-169,466-479` | Hook rollback can leave callers dereferencing cleared global state |
| R1-004 | P1 | A | `loader/proxy/startup.cpp:221-224` | Invalid journal still triggers a session-variable restore |
| R1-006 | P1 | A | `loader/proxy/modules.cpp:289-295` | Valid import tables without OriginalFirstThunk evade hooks |
| R1-016 | P1 | D | `tools/poc_parity.py:205-213,237-258` | Native parity paths can escape the PoC root |
| R1-017 | P1 | D | `tools/package_runtime.py:76-93,187-228`; `tools/package_fixes.py:103-135,354-364` | Packagers include private configs and logs from input trees |
| R1-019 | P1 | D | `tools/poc_session.py:509-524` | Session cleanup can terminate a game it did not start |
| R1-029 | P1 | D/F | `tools/poc_session.py:69-71`; `tools/field_snapshot.py:292-298` | Python drivers can fail to install or roll back under inherited PowerShell module paths |
| R1-018 | P2 | D | `tools/build.ps1:20-21`; `tools/lib/VsDevEnv.psm1:34-45` | Build imports MSVC environment into the caller |
| R1-020 | P2 | D | `tools/steam/verify_install.py:30-45` | Depot verification calls a junction-backed install vanilla |
| R1-021 | P2 | F | `tools/test.ps1:45-58` | Clean test runner skips native-dependent Python checks |
| R1-022 | P2 | B/G | `loader/core/src/manifest.cpp:393-414` | Folder-only root areas accept direct files |
| R1-023 | P2 | G | `docs/ARCHITECTURE.md:37,124` | Architecture misstates activation commit and DLL search |
| R1-025 | P2 | H | `tools/gmapack/gmapack.py.md:4` | Vendored packer lacks pinned provenance and its own licence record |
| R1-028 | P2 | F | `tools/tests/test_check_repo.py:32`; `tools/steam/tests/test_install_tools.py:24` | Documented direct tests write scratch to system temp |
| R1-024 | P3 | E/G | `companion/nativeloader/lua/autorun/client/nativeloader.lua:141,159` | Companion reads session fields the writer never emits |
| R1-027 | P3 | G | `docs/COMPONENTS.md:16-17`; `loader/core/README.md:64-73` | Component and path inventories remain at earlier milestones |

## Finding details

### R1-001 — Diagnostic log writes through a junction after refusing it (P0, Area A)

- **What is wrong:** `write_log` validates `native-loader/logs/loader.log` with `fs::refuse_links` (`loader/proxy/startup.cpp:50`), but its failure handler calls `emergency_log` (`:198-200`). That function opens the same path with `OPEN_ALWAYS` and `FILE_APPEND_DATA` without link validation (`:256-265`). `finish_report` also opens it without validation (`:112-119`). Both Win32 opens follow a directory junction or file symlink.
- **Failure scenario:** `native-loader/logs` is a junction to another directory with a user-owned `loader.log`. A normal startup, even with no config, refuses the linked path in `write_log` and then appends diagnostics to the user's file. The game need not activate RTX. This violates the rule against writing through links and changes data outside the loader's files.
- **Evidence:** `out/r1-review/repro/R1-001/repro.ps1` copied the synthetic `nl_proxy_host.exe` and built `winmm.dll` under `out/`, made `native-loader/logs` a junction to a separate `victim` folder, and ran the host. `output.txt` shows exit 0 and the victim's original `USER DATA` followed by `failure=loader.log could not be written` and the full startup report.
- **Confidence:** confirmed (synthetic process reproduction).
- **Suggested fix:** Route every log append through the same link-safe file opening policy, and skip diagnostic disk writes when that policy refuses the path. Keep the debugger diagnostic for a refused log.

### R1-002 — Failed hook installation can leave active, untracked import hooks (P1, Area A)

- **What is wrong:** `hook_imports_recorded` writes an IAT slot before `record->push_back` (`loader/proxy/modules.cpp:299-305`), which can allocate and throw. `install` publishes `g_state` and hooks already mapped modules before returning (`:441-452`), with no cleanup guard. `RuntimeActivation::apply` sets `hooks_installed_` only after a successful return (`loader/proxy/runtime.cpp:233-235`). Its rollback therefore does not call `modules::uninstall` if installation throws. The slot whose record insertion failed is not even in `hooked` for a later undo.
- **Failure scenario:** During a memory-constrained RTX start, allocation of a `Hooked` record fails after the first import slot is redirected. The startup C++ catch reports failure and leaves the runtime inactive, but the hook and `g_state` remain. A later load of `bin/win64/stdshader_dx6.dll` can still be redirected to the package's copy in a supposedly vanilla session. The same incomplete cleanup can follow a native fault while enumerating already mapped modules.
- **Evidence:** Exact trace above; `modules::install` contains no catch or scope guard around `g_state = state.release()` and the existing-module loop. `loader/proxy/startup.cpp:228-233` catches the exception after `RuntimeActivation::rollback` has skipped uninstall because `hooks_installed_` is false. The baseline tests have no allocation-failure case at this boundary.
- **Confidence:** likely (traced, not reproduced).
- **Suggested fix:** Record an import slot before publishing its replacement, and give installation its own rollback guard that restores every slot and clears registration/state on any failure. Set activation ownership before calling an installer that can partially mutate the process.

### R1-003 — Hook rollback can leave callers dereferencing cleared global state (P1, Area A)

- **What is wrong:** Each intercepted `LoadLibrary*` and `Find*` call repeatedly reads `g_state` (`loader/proxy/modules.cpp:149-169,228-269`). `uninstall` restores IAT slots and then sets `g_state = nullptr` (`:466-479`) without waiting for calls already inside the hook. It also clears the pointer even when `VirtualProtect` failed to restore a slot. Keeping the allocation alive does not keep the global pointer those calls use.
- **Failure scenario:** A worker thread enters a hooked load while the entry-point startup thread is undoing hooks after a runtime preload failure. Once `uninstall` clears `g_state`, the worker's next read of `g_state->load_ex_w` or `g_state->lock` dereferences null. An IAT slot whose restore failed creates the same crash on a later call. An activation failure is meant to leave a vanilla process, but may instead crash it.
- **Evidence:** Exact concurrency trace through `runtime.cpp:49-55` and `modules.cpp:149-169,466-479`; no in-flight call count, stable state pointer or failure check protects the hooks. Synthetic integration exercises rollback on one thread only.
- **Confidence:** likely (traced, not reproduced).
- **Suggested fix:** Keep hook entry points able to reach valid original function pointers throughout rollback, including in-flight calls, and refuse to clear state while any hooked IAT slot remains. Synchronize uninstallation with hook callers.

### R1-004 — Invalid journal still triggers a session-variable restore (P1, Area A)

- **What is wrong:** `startup::prepare` refuses an invalid `state.json`, but `startup_cxx` calls `restore_session_cvars` whenever the config exists and is enabled and activation is inactive (`loader/proxy/startup.cpp:221-224`). It does not require valid journal preflight. That helper writes a restore cfg, changes the command line and marks the record used (`:122-135`; `loader/proxy/runtime.cpp:76-112`). The brief requires invalid journal to leave a pure pass-through process.
- **Failure scenario:** After an RTX session, `session_cvars.json` records `r_3dsky=1`. A corrupt journal prevents deployment/activation; the user has since set `r_3dsky=0` in `config.cfg`. The next launch still appends `+exec nativeloader_restore.cfg` to set it back to 1, despite the invalid journal. The game may archive that change over the user's new value.
- **Evidence:** `out/r1-review/repro/R1-004/repro.ps1` ran the synthetic host with an enabled config, invalid `state.json`, a pending cvar record and `config.cfg` containing `r_3dsky "0"`. `output.txt` shows an inactive status for the journal parse error while `nativeloader_restore.cfg` was created and the record changed to `restore_issued: true`.
- **Confidence:** confirmed (synthetic process reproduction of the process and file changes; the synthetic host does not execute GMod cfg files).
- **Suggested fix:** Gate restore and add-on hiding on a successful journal preflight, or explicitly define and test a separate safe restore policy for invalid state that preserves later user edits.

### R1-005 — Session report replaces a user file through a junction (P0, Area A)

- **What is wrong:** `modules::write_session_json` checks only that `garrysmod/data/native-loader` is a directory (`loader/proxy/modules.cpp:507-508`); it does not reject a junction. It then calls `fs::write_atomic` on `session.json` (`:509-510`), whose `MOVEFILE_REPLACE_EXISTING` rename replaces the destination (`loader/core/src/fs.cpp:171-180`). The separate `status::write` checks links, but is called later and cannot prevent this write.
- **Failure scenario:** The game data folder's `native-loader` entry is a junction to a user directory containing `session.json`. An allowlisted `requires_remix` add-on (or an RTX session with patch/override hooks) installs module hooks. The first session report writes through the junction and replaces the user's existing `session.json`, even though the status report subsequently refuses the path.
- **Evidence:** `out/r1-review/repro/R1-005/repro.ps1` made a synthetic game and allowlisted development add-on entirely under `out/`, with `garrysmod/data/native-loader` linked to a `victim` folder. `output.txt` shows synthetic host exit 0 and the victim's `USER DATA` replaced by the loader's JSON. The startup log ends with `startup report could not be written`, confirming the later link check did fire.
- **Confidence:** confirmed (synthetic process reproduction).
- **Suggested fix:** Require `fs::refuse_links` and an ordinary target directory before any session report write, with the same check at the actual file operation. Preserve a preexisting non-loader `session.json` instead of replacing it.

### R1-006 — Valid import tables without OriginalFirstThunk evade hooks (P1, Area A)

- **What is wrong:** `hook_imports_recorded` uses `FirstThunk` as a name table when `OriginalFirstThunk` is zero (`loader/proxy/modules.cpp:289-295`). In a loaded PE image, Windows has already overwritten `FirstThunk` with function addresses. Treating those addresses as image-relative `IMAGE_IMPORT_BY_NAME` RVAs faults; `on_dll` swallows the SEH fault (`:374-381`) and leaves the module unhooked. The startup report can still claim hooks were installed.
- **Failure scenario:** A valid `filesystem_stdio.dll` built with `OriginalFirstThunk=0` loads during an RTX-off session with a deployed `requires_remix` add-on. The folder filter is never attached, so the RTX-only add-on is visible and may run its Lua/native code without Remix. The same PE shape in another game module can skip an override or abort existing-module hook installation.
- **Evidence:** `out/r1-review/repro/R1-006/patch_oft.py` zeroed the KERNEL32 import descriptor's `OriginalFirstThunk` in a copy of the built synthetic `filesystem_stdio.dll`, keeping `FirstThunk` intact. `repro.ps1` ran the synthetic host with an allowlisted RTX-only add-on. `output.txt` shows host exit 0 (the DLL loaded), `status.session.hooks="installed"`, and both A and W listings still containing `nl_rtx_addon`. The normal integration fixture hides it.
- **Confidence:** confirmed (synthetic process reproduction with a valid loaded PE).
- **Suggested fix:** Resolve import names from a validated lookup table before the IAT is bound, or recognize the zero-`OriginalFirstThunk` case and match resolved slot addresses safely. Bound every RVA and descriptor walk to the mapped image and import directory; report a hook failure instead of claiming success.

### R1-007 — A package can create a missing Steam depot file (P0, Area B)

- **What is wrong:** The package path policy admits `garrysmod/cfg/...` as `create-only` (`loader/core/src/paths.cpp:79-86`; `manifest.cpp`), but `decide` chooses `Act::install` whenever the path is absent (`loader/core/src/deploy.cpp:692-708`). It never checks whether Steam's depot manifest owns that pathname. `create-only` protects only an existing file; it does not protect a missing depot file.
- **Failure scenario:** A depot file such as `garrysmod/cfg/config_default.cfg` is missing after an interrupted Steam update, or the user has removed it. An allowlisted package with that path deploys its bytes at the depot pathname on the next launch. The locally cached GMod depot manifests list `config_default.cfg` as an ordinary depot file, yet the loader writes it, violating the repository's byte-identical depot rule. It will also be journaled as loader-owned and may be removed on uninstall.
- **Evidence:** `out/r1-review/repro/R1-007/repro.py` made a synthetic game root with an absent `config_default.cfg` and an allowlisted `create-only` package naming it. `output.txt` shows `nlctl apply` exit 0, `outcome: deployed`, change `add garrysmod/cfg/config_default.cfg`, and the file created. A read-only parse of the locally cached 4001/4002 depot manifests identified that path as depot-owned, not a userconfig entry.
- **Confidence:** confirmed (synthetic deployment plus local depot manifest).
- **Suggested fix:** Reject paths owned by the target game's depot manifests even when absent, using a verified local inventory or a deliberately narrower package area that cannot contain depot files. Apply that check before staging and again before a move.

### R1-008 — Modified runtime bytes can activate without matching the allowlisted package (P0, Areas A/B)

- **What is wrong:** An unchanged deployment and payload reuse accept a matching size and mtime without checking SHA-256 (`loader/core/src/deploy.cpp:198-202,603-625,872-883`). `RuntimeActivation::apply` validates only the journaled file size before `LoadLibraryExW` (`loader/proxy/runtime.cpp:144-154,244`). The journal already holds the expected SHA-256 but activation does not use it. The same check applies to module override files and runtime config layers.
- **Failure scenario:** After an allowlisted runtime is deployed, another process modifies its `d3d9.dll` in place while retaining its size and last-write time. The next start reports deployment unchanged and loads the modified DLL. Its bytes are not the allowlisted package's bytes; native code trust now depends on mutable on-disk state rather than the package hash. If deployment is deferred by a second instance or lock, even a changed mtime will not prevent size-only activation.
- **Evidence:** `out/r1-review/repro/R1-008/repro.py` built and deployed the fake runtime package in a synthetic game, changed one byte of the deployed `d3d9.dll` while preserving size and mtime, and ran the synthetic host. `output.txt` shows `deployment: unchanged`, `activation: active` and the changed DLL loaded. `nlctl status --verify` in the same output detects its SHA-256 drift and exits 1.
- **Confidence:** confirmed (synthetic process reproduction).
- **Suggested fix:** Verify the journaled SHA-256 of every executable payload immediately before activation or hook use, with a safe policy for a changed file. Size and mtime can remain the cheap no-op filter for non-executable files, but cannot establish native code provenance.

### R1-009 — Rollback deletes a new entry when its move fails (P0, Area D)

- **What is wrong:** `move_out` catches every `os.rename` failure and calls `remove(path)` (`tools/field_snapshot.py:84-93`). `remove` unlinks a file or recursively removes a directory (`:73-81`). The caller records this as `deleted` and can still report a clean rollback (`:301-305,373-375`).
- **Failure scenario:** The user places the snapshot on another volume, or an earlier debris entry with the same timestamp/name already exists. Rollback cannot rename a new game-created file into debris, so it deletes that file instead of preserving it. A new directory and all its contents can be deleted the same way.
- **Evidence:** `out/r1-review/repro/R1-009/repro.py` forced the rename error on a synthetic new user file. `output.txt` shows `outcome: deleted`, with neither source nor debris copy remaining. The cross-volume and collision cases follow the same catch.
- **Confidence:** confirmed (forced error-path reproduction).
- **Suggested fix:** Preserve the entry on any failed rename; use a unique debris destination and a verified copy-and-delete path for cross-volume moves, or stop rollback and report the entry as still in place.

### R1-010 — Restore follows a junction and overwrites its target (P0, Area D)

- **What is wrong:** The kept-file restore loop checks `path.is_file()` and then uses `shutil.copy2` (`tools/field_snapshot.py:325-335`), both of which follow a directory junction or file symlink. The earlier listed-entry cleanup does not move a junction that reuses an entry name present in the snapshot (`:308-313`).
- **Failure scenario:** A session replaces `garrysmod/cfg` with a junction to a user directory containing `config.cfg`. Rollback sees the expected entry names and copies its old `config.cfg` through the junction, overwriting the user's file in the other directory; it can report `clean: true`.
- **Evidence:** `out/r1-review/repro/R1-010/repro.ps1` made that junction in a synthetic game and invoked the actual `rollback` routine with registry operations stubbed. `output.txt` shows the victim content replaced with `ORIGINAL CONFIG`, the junction still present, and `rollback clean: True`.
- **Confidence:** confirmed (synthetic rollback reproduction).
- **Suggested fix:** Check every parent and target for reparse points immediately before restoration. Move an unexpected link aside, then restore into an ordinary path; fail closed if the path changes during the write.

### R1-011 — Failed registry import still prunes user values (P0, Area D)

- **What is wrong:** `restore_registry` records `reg import`'s exit code but does not check it (`tools/field_snapshot.py:203-204`). It parses the exported snapshot and deletes every current key/value absent from that parsed file (`:210-219`), even when the import failed or the export was truncated. `read_reg` accepts a syntactically partial export without a completeness check (`:149-175`).
- **Failure scenario:** A truncated `registry.reg` contains the key header but omits a user's value. `reg import` fails. The subsequent prune interprets the omitted value as new and invokes `reg delete /v` on it. The original value is lost despite a failed restore.
- **Evidence:** `out/r1-review/repro/R1-011/repro.py` used a partial synthetic export and mocked registry commands, so it touched no registry. `output.txt` shows `import exit: 1` followed by a `reg delete ... /v UserSetting /f` call.
- **Confidence:** confirmed (mocked command-path reproduction; no registry mutation performed).
- **Suggested fix:** Verify snapshot completeness and a stored digest before registry restore; abort on a failed import or failed parse. Compute a delete plan from a trustworthy export and stop before pruning if any step fails.

### R1-012 — Missing depot manifests make rollback overwrite Steam files (P0, Area D)

- **What is wrong:** `depot_files` treats a missing app manifest or cached depot manifest as `None` (`tools/field_snapshot.py:103-113`). `snapshot` then copies every direct file in its kept folders, including Steam's own files (`:245-261`), and disables the final depot verification. `rollback` writes changed copies back in place (`:325-335`).
- **Failure scenario:** The field install's cached depot manifest is unavailable when the snapshot is taken. Steam later updates `bin/win64/gmod.exe` or another depot file. Rollback restores the old copied bytes over Steam's update and can report `clean: true` because depot verification was disabled.
- **Evidence:** `out/r1-review/repro/R1-012/repro.py` simulated unavailable manifests on a synthetic game with a depot-named executable, then changed it before rollback. `output.txt` shows `depot_check: False`, that file copied, old bytes written back, and `rollback clean: True`.
- **Confidence:** confirmed (synthetic snapshot and rollback with manifest discovery stubbed).
- **Suggested fix:** Require the depot inventory for a Steam-managed field snapshot; fail closed if it cannot be obtained. Never restore a path identified as depot-owned, even if the snapshot file list includes it.

### R1-013 — Corrupt snapshot copies are written to user files before verification (P0, Area D)

- **What is wrong:** The snapshot records the original SHA-256 (`tools/field_snapshot.py:256-261`), but rollback does not hash the saved copy before `shutil.copy2` (`:325-335`). It checks the destination only afterward (`:347-355`), when the user's live file has already been overwritten.
- **Failure scenario:** A snapshot copy is truncated or altered on disk. The live `config.cfg` has since changed. Rollback writes the corrupt copy over it and then reports a difference; it cannot reconstruct either the original or the current user value from that file.
- **Evidence:** `out/r1-review/repro/R1-013/repro.py` supplied a synthetic snapshot whose saved copy did not match its recorded hash. `output.txt` shows the live user file replaced by `CORRUPTED SNAPSHOT COPY` and `clean: False` only after that write.
- **Confidence:** confirmed (synthetic rollback reproduction).
- **Suggested fix:** Preflight the hash and size of every saved copy before any uninstall, removal or restoration, then fail without touching the install if a copy is damaged.

### R1-014 — RemoveConfig deletes changed package files that uninstall said it kept (P0, Areas B/D)

- **What is wrong:** `collect` notes a hash-changed retired file but neither retains it in `retired` nor marks cleanup incomplete (`loader/core/src/deploy.cpp:295-319`). `nlctl uninstall` then removes the journal (`:1226-1237`) and returns success. `uninstall-loader.ps1 -RemoveConfig` follows that success with `install-loader.ps1 -Uninstall -RemoveState`, which recursively removes `native-loader` (`tools/uninstall-loader.ps1:29-31`; `tools/install-loader.ps1:83-95`).
- **Failure scenario:** The user edits a deployed payload file under `native-loader/packages`. The uninstaller reports that the changed file was left in place, but `-RemoveConfig` immediately deletes it with the state directory. The user edit is lost, and the command still succeeds.
- **Evidence:** `out/r1-review/repro/R1-014/repro.py` installed the built bootstrap and deployed a fake runtime in a synthetic game, edited the payload DLL, and ran the wrapper with `-RemoveConfig`. `output.txt` shows the `nlctl` note `not deleted, because it changed`, wrapper exit 0, and the edited file absent afterward.
- **Confidence:** confirmed (synthetic end-to-end reproduction).
- **Suggested fix:** Keep changed retired files in the journal and report cleanup incomplete. Make `-RemoveConfig` refuse a nonempty state folder containing changed payloads, or move those files to a reviewed preservation location before removing the folder.

### R1-015 — Reference mode deletes an existing user data folder (P0, Area D)

- **What is wrong:** `step_run` uses `garrysmod/data/nl_session` for temporary Lua (`tools/poc_session.py:308-314`) and unconditionally removes that whole folder in `finally` (`:521-524`). The removal runs with `--reference` and does not check whether the folder existed beforehand or contains user files.
- **Failure scenario:** The reference install already has `garrysmod/data/nl_session/user.txt`. A `poc_session.py run --reference` starts or even exits early. Cleanup recursively deletes the existing folder and the user's file, despite reference mode's promise to leave the install alone.
- **Evidence:** `out/r1-review/repro/R1-015/repro.py` exercised `step_run` on a synthetic reference folder with process creation mocked. `output.txt` shows the preexisting file absent after a reference-mode run whose fake process had already exited. No game was launched.
- **Confidence:** confirmed (synthetic command-path reproduction).
- **Suggested fix:** Refuse an occupied scratch folder, use a unique per-session path under the game's data area only when writes are authorized, and remove only files this invocation created. Make reference mode avoid game-side temporary files.

### R1-016 — Native parity paths can escape the PoC root (P1, Area D)

- **What is wrong:** `--native` values are joined directly with both roots (`tools/poc_parity.py:205-213`); there is no check that they are relative, normalized install paths. `restore` trusts the recorded path just as directly (`:237-258`). `--data` and `--save` have the same missing containment check.
- **Failure scenario:** `--native ../outside.bin` finds a file beside the reference root and copies it beside the PoC root, outside the PoC. The tool therefore writes to an unintended path and records `../outside.bin` for later deletion.
- **Evidence:** `out/r1-review/repro/R1-016/repro.py` used two synthetic roots under `out/`; `output.txt` shows `target resolves below PoC root: False`, the outside file created and the escaping path recorded.
- **Confidence:** confirmed (synthetic `prepare` reproduction).
- **Suggested fix:** Validate each user-supplied relative path against a strict install-relative grammar and resolve it under the PoC before writing or recording it. Revalidate state paths before restore.

### R1-017 — Packagers include private configs and logs from input trees (P1, Area D)

- **What is wrong:** `package_runtime.py` walks every regular file under `--runtime` and excludes only build byproducts/PDBs (`tools/package_runtime.py:28-30,76-93`); it hashes and lists all others (`:187-228`). `package_fixes.py::collect` likewise excludes a small junk set but accepts logs and private config names under add-ons, mods and all `garrysmod/data` subfolders except `native-loader` (`tools/package_fixes.py:43-45,103-135,354-364`). Neither excludes `user.conf`, `.env` or logs, nor presents them for approval before package output.
- **Failure scenario:** A runtime build folder acquires a local `user.conf`, `.env` credential or diagnostic log. The next package build bundles that file under `native/payload/runtime/`; distributing the GMA would expose it. A similar file under a fixes add-on, mod or data subfolder is packaged as a root file. `tools/package_fixes.py.md` says the rest of `garrysmod/data` is left out, although the code includes each subfolder.
- **Evidence:** `out/r1-review/repro/R1-017/repro.py` built a synthetic runtime package. `output.txt` shows `native/payload/runtime/user.conf`, `private.log` and `.env` in the manifest. The current fork `_output` did not contain these names when inspected read-only; this is a future-input risk.
- **Confidence:** confirmed (synthetic runtime packaging; fixes path traced).
- **Suggested fix:** Use an explicit runtime file allowlist or reject sensitive/config/log names by default, and print a complete package inventory for review before publishing. Apply equivalent exclusions to the fixes packager.

### R1-018 — Build imports MSVC environment into the caller (P2, Area D)

- **What is wrong:** `tools/build.ps1` invokes `Enter-VsDevEnv` before its `try/finally` and restores only `TEMP` and `TMP` (`tools/build.ps1:20-21,38-53`). The imported toolchain variables and PATH are process environment changes (`tools/lib/VsDevEnv.psm1:34-45`) that remain after the script returns, contrary to the brief's environment-isolation requirement.
- **Failure scenario:** A user runs the build in an interactive PowerShell shell, then invokes another compiler or script. It inherits MSVC's PATH, INCLUDE and LIB instead of the user's previous environment.
- **Evidence:** `out/r1-review/repro/R1-018/repro.ps1` ran an incremental Release build in one PowerShell process. `output.txt` shows VSCMD target arch absent before and `x64` after, with PATH, INCLUDE and LIB changed.
- **Confidence:** confirmed (same-process reproduction).
- **Suggested fix:** Run vcvars in a child process or save and restore every environment variable it changes in a `finally` block.

### R1-019 — Session cleanup can terminate a game it did not start (P1, Area D)

- **What is wrong:** `poc_session.py` initially refuses an already-running game, but timeout and cleanup later pass *all* same-root GMod PIDs to `terminate` (`tools/poc_session.py:390-391,509-524`), with no comparison to the process it started or its child PIDs.
- **Failure scenario:** The user starts another game from the same root after this session's preflight. When the first session exits or times out, cleanup enumerates and terminates the later user's process.
- **Evidence:** `out/r1-review/repro/R1-019/repro.py` mocked process enumeration and termination around the actual `step_run` path. `output.txt` shows the session started PID 12345 but passed newly appearing PID 9876 to `terminate`. No process was killed in the repro.
- **Confidence:** confirmed (mocked process-path reproduction).
- **Suggested fix:** Track the launched PID and verified descendants by creation time/parentage, and terminate only those; leave any new same-root process that this invocation did not create alone.

### R1-020 — Depot verification calls a junction-backed install vanilla (P2, Area D)

- **What is wrong:** `verify_install.verify` checks `Path.is_file`, size and SHA-1 (`tools/steam/verify_install.py:30-45`), all of which follow reparse points. It never verifies that the depot file and each parent are ordinary paths. A junction to an identical external file passes and is counted as an intact depot file. It also treats a regular depot entry with no SHA-1 as verified after a size check alone (`:42-45`); the currently cached GMod manifests had no such entries, but the parser supports them.
- **Failure scenario:** `garrysmod/cfg` is replaced with a junction to another directory containing byte-identical `config_default.cfg`. Verification reports that depot file OK even though the install contains a link and Steam's file is absent at its original location.
- **Evidence:** `out/r1-review/repro/R1-020/repro.ps1` built that synthetic layout and supplied a synthetic depot manifest. `output.txt` shows one file marked OK, no missing/hash mismatch and a junction at the parent.
- **Confidence:** confirmed (synthetic verification reproduction).
- **Suggested fix:** Refuse or separately report reparse points in any depot path component, and require a hash for ordinary depot files before counting them as vanilla.

### R1-026 — Session install overwrites an existing allowlist without a backup (P0, Area D)

- **What is wrong:** `poc_session.py::step_install` runs the installer and then unconditionally calls `write_config` (`tools/poc_session.py:362-370`), which atomically replaces `native-loader/config.json` without checking whether a user edited it (`:350-358`). `field_snapshot.py` does not copy files below `native-loader` into its kept set (`:33-45,243-261`), so its rollback cannot restore that config on a field install.
- **Failure scenario:** The field install already has a hand-edited loader allowlist. A later `poc_session.py --allow-steam-managed install` with default empty `--allow-*` arguments replaces it with an empty allowlist. The prior policy is lost even if the field snapshot was taken.
- **Evidence:** `out/r1-review/repro/R1-026/repro.py` exercised `step_install` on a synthetic root with the installer mocked successful. `output.txt` shows the preexisting `my-reviewed-package.gma` entry gone and `allow.local`, `allow.workshop` and `allow.dev_folders` all empty. No game install was touched.
- **Confidence:** confirmed (synthetic command-path reproduction).
- **Suggested fix:** Refuse an existing config unless its expected hash is supplied, or back it up and restore it as part of the session/snapshot. A new install step should not silently reset policy.

### R1-021 — Clean test runner skips native-dependent Python checks (P2, Area F)

- **What is wrong:** `tools/test.ps1` runs every Python group before building native targets (`tools/test.ps1:45-58`). `test_package_runtime.py:215-216` and `test_package_fixes.py:416-417` skip their `nlctl manifest` acceptance checks if `nlctl.exe` is not built. `test_field_snapshot.py:16,95-99` silently takes a branch that does not install the bootstrap when the build is absent. The normal clean-worktree gate never reruns these paths after building.
- **Failure scenario:** A packager emits a manifest the actual `nlctl` rejects, while its Python-only tests pass on a clean checkout. The full runner reports green with those compatibility checks skipped.
- **Evidence:** This clean worktree's baseline reported 44 tool Python tests with 7 skips before the Debug build. After the required builds, `python -m unittest discover -s tests -p 'test_package_*.py' -q` from `tools/` ran 24 tests with no skips and passed. The ordering and decorators show why the original gate omitted the two native cross-checks.
- **Confidence:** confirmed (baseline and targeted after-build run).
- **Suggested fix:** Build native targets before Python tests that require them, or rerun those test modules after the build and require no native-dependent skips in the full gate.

### R1-022 — Folder-only root areas accept direct files (P2, Areas B/G)

- **What is wrong:** The path policy accepts any path immediately below `garrysmod/data` or `garrysmod/addons` (`loader/core/src/paths.cpp:79-86`). `manifest.cpp:393-414` checks only that `split(path,'/').size()` is at least 3, which is true for `garrysmod/data/direct.txt` and `garrysmod/addons/direct.gma`. The accepted layout and ADR 0011 describe named folders with files below them.
- **Failure scenario:** An allowlisted package declares a direct data file or `.gma` directly in `garrysmod/addons`, gaining a package target outside the declared folder-specific areas. A direct add-on file also lacks a folder name for `session::hidden_addons` to hide in an RTX-off session.
- **Evidence:** `out/r1-review/repro/R1-022/repro.py` built a development package with both direct-file paths. `output.txt` shows `nlctl manifest --json` exit 0 and both accepted as root files.
- **Confidence:** confirmed (synthetic manifest reproduction).
- **Suggested fix:** Require `garrysmod/data/<folder>/<file>` and `garrysmod/addons/<addon>/<file>` for each declared file, and keep root-file declarations at the intended folder level.

### R1-023 — Architecture misstates activation commit and DLL search (P2, Area G)

- **What is wrong:** The boot diagram still says `SetDllDirectoryW` is used (`docs/ARCHITECTURE.md:37`) although ADR 0010 and `loader/proxy/runtime.cpp:202-213` use a PATH prepend. It says a status/log failure before final commit keeps the game vanilla (`docs/ARCHITECTURE.md:124`), but `loader/proxy/startup.cpp:193-200,216-242` treats log failure as diagnostic and commits a successful runtime before attempting status reporting.
- **Failure scenario:** An operator sees no fresh status or loader log and follows the architecture's stated failure rule, assuming the process stayed vanilla. The runtime may actually be active, so they can misdiagnose an RTX-on session or make an unsafe next change.
- **Evidence:** Exact document-to-code trace at the cited lines; ADR 0008 explicitly records the commit-before-report revision.
- **Confidence:** likely (semantic drift confirmed by source; harmful operator choice not reproduced).
- **Suggested fix:** Update the boot diagram and failure rule to say PATH is prepended and reporting failure after runtime load does not undo activation. Point readers to status PID/time and module checks for determining the active renderer.

### R1-024 — Companion reads session fields the writer never emits (P3, Areas E/G)

- **What is wrong:** The companion calls `freshness(session)` for `session.json` (`companion/nativeloader/lua/autorun/client/nativeloader.lua:141`), but `modules::results_json` emits no `utc` (`loader/proxy/modules.cpp:481-500`), so it always prints an unknown timestamp. The companion's own `.md` incorrectly lists `utc` as a session field and shows a fresh age in its example. It also reads `override.module` (`nativeloader.lua:159`), while the writer emits `requested`, `loaded`, `result` and `windows_error` (`modules.cpp:135-140`), making the module label `?`.
- **Failure scenario:** `nativeloader_status` prints an apparently undated session and an unnamed override even after a normal active run, reducing its usefulness for distinguishing stale results.
- **Evidence:** Exact serializer/reader field comparison. The two LuaJIT companion tests were skipped in the clean baseline because LuaJIT was not installed, and they cover only update notices.
- **Confidence:** likely (direct schema trace, no LuaJIT reproduction).
- **Suggested fix:** Add a UTC field and module name to the session writer, or have the companion use only fields actually present and compare its process ID with a fresh startup status.

### R1-025 — Vendored packer lacks pinned provenance and its own licence record (P2, Area H)

- **What is wrong:** `tools/gmapack/gmapack.py.md:4` says the packer was vendored as-is from the user's GMA File Packer project, but the subtree has no `LICENSE`/`COPYING` file and no source revision recorded. This does not meet AGENTS.md rule 7's third-party placement and licence-file convention. The repository's root MIT licence may cover it if the same rightsholder authorised that, but the vendored source does not establish it.
- **Failure scenario:** A public source or binary release cannot identify the exact packer version or demonstrate its licence from the checked-in subtree. A later update cannot be compared to a pinned upstream revision.
- **Evidence:** Read-only `git ls-files tools/gmapack` has no licence file; the packer source header and README contain no licence statement or revision. In contrast, `third_party/lzma` has a licence and matching recorded file hashes.
- **Confidence:** likely (repository contents verified; ownership/licence status needs the user's answer).
- **Suggested fix:** Record the packer's source revision and licence, include its licence text, and document any deliberate exception to the `third_party/` layout.

### R1-027 — Component and path inventories remain at earlier milestones (P3, Area G)

- **What is wrong:** The top component table still calls the Lua companion and runtime package planned at M5/M6 and M4 (`docs/COMPONENTS.md:16-17`) despite later sections marking them done. `loader/core/README.md:64-73` still lists only three root areas and omits the implemented `garrysmod/data` and `garrysmod/addons` areas. `companion/README.md:12` says M6 will add the restart notice, although its Lua already contains it. The companion script document says there is no network or timer while the Lua registers a 600-second timer and calls `steamworks.FileInfo` (`nativeloader.lua:185-220`). `tools/test.ps1.md` omits the integration evidence folders its CTests write.
- **Failure scenario:** A reader using these inventories rather than the later appendices gets outdated component status and an incomplete path policy.
- **Evidence:** Direct comparison with `paths.cpp:79-87`, `nativeloader.lua:181-220` and the later M5/M6 sections of `COMPONENTS.md`.
- **Confidence:** likely (direct document-to-code trace).
- **Suggested fix:** Reconcile the headline rows and READMEs with the implemented M5/M6 behavior.


### R1-028 — Documented direct tests write scratch to system temp (P2, Area F)

- **What is wrong:** `tools/tests/test_check_repo.py:32`, `tools/steam/tests/test_install_tools.py:24` and `tools/steam/tests/test_steam_manifest.py:12` call `tempfile.TemporaryDirectory()` without a `dir`. Their `.md` files document direct `python -m unittest` invocation. Outside `tools/test.ps1` (which temporarily redirects `TEMP`/`TMP`), those commands use the system temp directory, contrary to AGENTS.md rule 9.
- **Failure scenario:** A developer follows the documented direct test command in a normal shell. Synthetic repositories and Steam manifests are created under the system temporary folder, where this project's earlier fixture builds were blocked by Windows Defender.
- **Evidence:** Exact source/doc trace. This review did not run the direct command, because it would deliberately write outside the allowed `out/` tree.
- **Confidence:** likely (traced, not executed due the R1 boundary).
- **Suggested fix:** Pass a repo-local `out/tmp` directory explicitly in each test fixture, or make their documented direct invocation use a wrapper that sets and restores `TEMP` and `TMP`.


### R1-029 — Python drivers can fail to install or roll back under inherited PowerShell module paths (P1, Areas D/F)

- **What is wrong:** `poc_session.py` hardcodes `powershell` for installer/uninstaller calls (`tools/poc_session.py:69-71`); `field_snapshot.py` does the same for rollback uninstall (`tools/field_snapshot.py:292-298`), and its integration test uses it when a build is present (`tools/tests/test_field_snapshot.py:95-99`). A Python process launched from `pwsh` can pass PowerShell Core's module paths first in `PSModulePath`. Windows PowerShell 5.1 then fails to autoload `Get-FileHash`, which `install-loader.ps1` requires (`:59`), even though the WindowsPowerShell module directory is also present.
- **Failure scenario:** A field rollback is launched from a `pwsh` environment after the bootstrap is installed. The uninstaller's legacy PowerShell child cannot resolve `Get-FileHash`, exits nonzero, and `field_snapshot.rollback` aborts before restoring the install. The same environment makes `poc_session install` fail. The initial clean-worktree test pass concealed this because its `BUILD` branch was absent until after compilation.
- **Evidence:** The second `tools/test.ps1` in this review failed `test_field_snapshot.test_rollback_puts_everything_back` at the installer with `Get-FileHash` not recognized; Python tests 44 with one failure and five skips, while CTest still passed 16/16. `out/r1-review/evidence/check_powershell_module.txt` shows a legacy child with inherited module paths cannot find the cmdlet, but the same child with only WindowsPowerShell paths resolves `Microsoft.PowerShell.Utility`. The earlier R1-014 synthetic wrapper repro needed `pwsh` for the same reason.
- **Confidence:** confirmed (post-build full test and isolated module-path check).
- **Suggested fix:** Select `pwsh` when available, as CMake's tests do, or launch Windows PowerShell with a compatible module path. Make the full test runner exercise this branch after building and require it to pass.

## Checked and fine

### Area A

- The bootstrap's host and Chromium role checks, plus all three off switches, are applied before the entry hook. The synthetic proxy tests cover these gates and verify that off-switch launches write no loader directory.
- The generated export inventory is checked against this machine's System32 winmm set; the MASM thunks are indirect jumps that preserve call registers. The built proxy's static and delay import directories contain only KERNEL32, as the baseline CTest verified.
- `patch::find` bounds its candidate reads and `patch::apply` skips a patch unless exactly one section match is found. Manifest parsing confines replacement bytes to that match. Ordinary activation error paths restore environment, command-line descriptors, Vulkan reference and PATH, as the synthetic activation integration exercises.

### Area B

- Discovery iterates only entries from `allow.workshop`, `allow.local` and `allow.dev_folders`; the planner applies source precedence, one runtime and root overlap checks before staging. Manifest paths are ASCII, relative, component-checked and confined to declared areas.
- Staging checks file size, archive CRC where present and manifest SHA-256 before recording a pending transaction. Moves use write-through renames; recovery reverses recorded steps. Ordinary replacement, removal and retirement require a full SHA-256 and refuse reparse paths. The fault tests interrupt or fail each filesystem operation of four transaction shapes.
- GMA indexes reject negative and overflowing file sizes; the LZMA decoder limits dictionary size; JSON enforces byte, depth and value limits. Tests exercise damaged and truncated inputs. This does not cover the trust and missing-depot defects above.

### Area C

- `nlctl` uses `wmain` and wide filesystem paths. `plan`, `activation`, `status`, archive inspection and manifest validation perform no writes in their command paths. `apply`, `rollback` and `uninstall` pass `--dry-run` to the core, whose dry-run branch skips locking, recovery, staging and journal writes. The CLI end-to-end CTests passed in both configurations.

### Area D

- `install-loader.ps1` checks the target DLL identity and receipt/build SHA-256 before replacing or removing it, and requires an explicit flag for a Steam-managed install. The synthetic installer tests passed. `make_vanilla_copy.py` copies only files whose bytes match a depot SHA-1 into an empty destination; the locally cached current manifests have no symlink entries or ordinary files without hashes.
- `poc_activation_check.ps1` pins the PoC path and validates a recorded process by image path and start time before acting on it. `smoke_test.ps1` preflights the install and snapshots the specific files it restores. Both have the separate issues and coverage limits recorded above.

### Area E

- The companion catches failed or malformed JSON reads, checks schema before using nested status fields, and uses defensive accessors for missing/wrong-type values. It registers one command and a 600-second update timer, with no per-frame hook. Workshop notices are limited to one per item per session. The missing session fields are R1-024.

### Area F — invariant-to-test map

| Invariant | Test that would fail, or gap |
|---|---|
| Host gate, Chromium roles, three off switches, pure pass-through | `nl_proxy_tests`; `nl_activation_integration`. No test covers a linked diagnostic log (R1-001). |
| Complete winmm forwarding and KERNEL32-only imports | `nl_proxy_generated_exports`, `nl_proxy_tests`, `nl_proxy_kernel32_imports`. |
| Reversible environment/command line/Vulkan/runtime on ordinary failures | `nl_activation_integration`; `nl_cmdline_roundtrip`; `test_cmdline.cpp`. No injected SEH through startup (already known in M4 review). |
| Patch uniqueness, insecure gate, override and add-on filtering | `test_m5.cpp`, `nl_session_integration`. No zero-OriginalFirstThunk PE, concurrent hook rollback, reused search handle, non-ASCII A/W pattern or FindFirstFileExW flag variation (R1-002/003/006). |
| Allowlisted discovery, manifest/path rules and one runtime | `test_config.cpp`, `test_discovery.cpp`, `test_manifest.cpp`, `test_paths.cpp`, `test_planner.cpp`, `nlctl_e2e_plan`. No missing depot path (R1-007) or direct-folder-area file (R1-022). |
| Stage integrity, ownership, rollback/uninstall and power-cut recovery | `test_deploy.cpp`, `nl_tests_faults_*`, `nl_deploy_faults`, `nlctl_e2e_deploy`. They compare distinct before/after states and fail on an intermediate state. No hash check before native activation (R1-008), changed payload plus `-RemoveConfig` (R1-014), or every fault point through the in-process startup entry path. |
| Installer and field rollback data safety | `nl_proxy_installer`, `nlctl_uninstall_loader`, `test_field_snapshot.py`. No cross-volume move failure, junction restore, failed registry import, corrupt snapshot copy or missing depot cache (R1-009 through R1-013). |
| Packager inventory and companion notices | `test_package_runtime.py`, `test_package_fixes.py`, `test_companion.py`. Clean `tools/test.ps1` skips the native-dependent package checks before the build; the two companion tests were skipped because LuaJIT is absent. No secret-file exclusion or malformed/stale session JSON test. |
| Documentation conventions | `tools/check_repo.py` and `test_check_repo.py`; they check links/file inventories, not semantic behavior claims (R1-023/027). |

The `nl_tests` harness counts failed `CHECK`/`REQUIRE` assertions and fails if no cases ran. The real-process fault test checks the old and new snapshots differ before trying every change. Its comparisons are not vacuous.

### Area G

- `config.json`, `state.json`, `status.json` and `session_cvars.json` key names and defaults mostly match their parsers/serializers. Package format's ASCII path and strict JSON rules are implemented. The report lists the direct-file path gap and stale architecture/component/companion descriptions. A line-by-line comparison of every script's `.md` remains open.

### Area H

- All five `third_party/lzma` SHA-256 values match its README, and its licence file is present. `git ls-files` found no tracked binaries, packages, dumps, logs, `user.conf` or `.env` files. A read-only comparison of our patch, hook, companion and packager sources against analogous GPL fixes sources found no exact eight-line non-comment sequence (`out/r1-review/evidence/gpl_similarity.txt`); this limited check is not a legal conclusion. The fixes package intentionally carries GPL Lua/binaries, and the runtime package carries NVIDIA binaries; public-release obligations need review before publication.

## Coverage

`Reviewed` means the relevant code and its callers were traced against the brief. `Partly reviewed` means only selected paths were checked. Headers and fixtures are listed so omissions remain visible.

| Source file | Status |
|---|---|
| `companion/nativeloader/lua/autorun/client/nativeloader.lua` | Reviewed |
| `loader/cli/nlctl.cpp` | Reviewed |
| `loader/cli/tests/crosscheck_gmapack.py` | Reviewed |
| `loader/cli/tests/e2e_deploy.py` | Reviewed |
| `loader/cli/tests/e2e_plan.py` | Reviewed |
| `loader/cli/tests/uninstall_tests.ps1` | Reviewed |
| `loader/core/include/nl/activate.h` | Reviewed |
| `loader/core/include/nl/cmdline.h` | Reviewed |
| `loader/core/include/nl/config.h` | Reviewed |
| `loader/core/include/nl/core.h` | Reviewed |
| `loader/core/include/nl/crc32.h` | Reviewed |
| `loader/core/include/nl/deploy.h` | Reviewed |
| `loader/core/include/nl/discovery.h` | Reviewed |
| `loader/core/include/nl/fs.h` | Reviewed |
| `loader/core/include/nl/gma.h` | Reviewed |
| `loader/core/include/nl/journal.h` | Reviewed |
| `loader/core/include/nl/json.h` | Reviewed |
| `loader/core/include/nl/lzma.h` | Reviewed |
| `loader/core/include/nl/manifest.h` | Reviewed |
| `loader/core/include/nl/package.h` | Reviewed |
| `loader/core/include/nl/patch.h` | Reviewed |
| `loader/core/include/nl/paths.h` | Reviewed |
| `loader/core/include/nl/planner.h` | Reviewed |
| `loader/core/include/nl/session.h` | Reviewed |
| `loader/core/include/nl/sha256.h` | Reviewed |
| `loader/core/include/nl/startup.h` | Reviewed |
| `loader/core/include/nl/status.h` | Reviewed |
| `loader/core/include/nl/utf8.h` | Reviewed |
| `loader/core/include/nl/vdf.h` | Reviewed |
| `loader/core/include/nl/version.h.in` | Reviewed |
| `loader/core/src/activate.cpp` | Reviewed |
| `loader/core/src/cmdline.cpp` | Reviewed |
| `loader/core/src/config.cpp` | Reviewed |
| `loader/core/src/crc32.cpp` | Reviewed |
| `loader/core/src/deploy.cpp` | Reviewed |
| `loader/core/src/discovery.cpp` | Reviewed |
| `loader/core/src/fs.cpp` | Reviewed |
| `loader/core/src/gma.cpp` | Reviewed |
| `loader/core/src/journal.cpp` | Reviewed |
| `loader/core/src/json.cpp` | Reviewed |
| `loader/core/src/lzma.cpp` | Reviewed |
| `loader/core/src/manifest.cpp` | Reviewed |
| `loader/core/src/package.cpp` | Reviewed |
| `loader/core/src/patch.cpp` | Reviewed |
| `loader/core/src/paths.cpp` | Reviewed |
| `loader/core/src/planner.cpp` | Reviewed |
| `loader/core/src/session.cpp` | Reviewed |
| `loader/core/src/sha256.cpp` | Reviewed |
| `loader/core/src/startup.cpp` | Reviewed |
| `loader/core/src/status.cpp` | Reviewed |
| `loader/core/src/utf8.cpp` | Reviewed |
| `loader/core/src/vdf.cpp` | Reviewed |
| `loader/core/src/version.cpp` | Reviewed |
| `loader/proxy/activation.cpp` | Reviewed |
| `loader/proxy/activation.h` | Reviewed |
| `loader/proxy/bootstrap.cpp` | Reviewed |
| `loader/proxy/bootstrap.h` | Reviewed |
| `loader/proxy/generate_exports.py` | Reviewed |
| `loader/proxy/generated/exports.h` | Reviewed |
| `loader/proxy/generated/exports.json` | Reviewed |
| `loader/proxy/generated/thunks.asm` | Reviewed |
| `loader/proxy/generated/winmm.def` | Reviewed |
| `loader/proxy/modules.cpp` | Reviewed |
| `loader/proxy/modules.h` | Reviewed |
| `loader/proxy/runtime.cpp` | Reviewed |
| `loader/proxy/runtime.h` | Reviewed |
| `loader/proxy/startup.cpp` | Reviewed |
| `loader/proxy/tests/activation_integration.py` | Reviewed |
| `loader/proxy/tests/activation_probe.cpp` | Reviewed |
| `loader/proxy/tests/activation_probe.h` | Reviewed |
| `loader/proxy/tests/check_imports.py` | Reviewed |
| `loader/proxy/tests/fixture_delay.cpp` | Reviewed |
| `loader/proxy/tests/fixture_engine.cpp` | Reviewed |
| `loader/proxy/tests/fixture_filesystem.cpp` | Reviewed |
| `loader/proxy/tests/fixture_runtime.cpp` | Reviewed |
| `loader/proxy/tests/fixture_shader.cpp` | Reviewed |
| `loader/proxy/tests/fixture_static.cpp` | Reviewed |
| `loader/proxy/tests/host.cpp` | Reviewed |
| `loader/proxy/tests/install_tests.ps1` | Reviewed |
| `loader/proxy/tests/session_integration.py` | Reviewed |
| `loader/proxy/tests/session_probe.cpp` | Reviewed |
| `loader/proxy/tests/session_probe.h` | Reviewed |
| `loader/proxy/tests/test_activation.cpp` | Reviewed |
| `loader/proxy/tests/test_proxy.cpp` | Reviewed |
| `loader/proxy/version.rc.in` | Reviewed |
| `loader/tests/cmdline_host.cpp` | Reviewed |
| `loader/tests/deploy_faults.py` | Reviewed |
| `loader/tests/fault_host.cpp` | Reviewed |
| `loader/tests/gma_fixture.h` | Reviewed |
| `loader/tests/nl_test.h` | Reviewed |
| `loader/tests/test_activate.cpp` | Reviewed |
| `loader/tests/test_cmdline.cpp` | Reviewed |
| `loader/tests/test_config.cpp` | Reviewed |
| `loader/tests/test_crc32.cpp` | Reviewed |
| `loader/tests/test_deploy.cpp` | Reviewed |
| `loader/tests/test_discovery.cpp` | Reviewed |
| `loader/tests/test_fs.cpp` | Reviewed |
| `loader/tests/test_gma.cpp` | Reviewed |
| `loader/tests/test_journal.cpp` | Reviewed |
| `loader/tests/test_json.cpp` | Reviewed |
| `loader/tests/test_lzma.cpp` | Reviewed |
| `loader/tests/test_m5.cpp` | Reviewed |
| `loader/tests/test_main.cpp` | Reviewed |
| `loader/tests/test_manifest.cpp` | Reviewed |
| `loader/tests/test_package.cpp` | Reviewed |
| `loader/tests/test_paths.cpp` | Reviewed |
| `loader/tests/test_planner.cpp` | Reviewed |
| `loader/tests/test_sha256.cpp` | Reviewed |
| `loader/tests/test_startup.cpp` | Reviewed |
| `loader/tests/test_status.cpp` | Reviewed |
| `loader/tests/test_vdf.cpp` | Reviewed |
| `loader/tests/test_version.cpp` | Reviewed |
| `third_party/lzma/7zTypes.h` | Reviewed |
| `third_party/lzma/Compiler.h` | Reviewed |
| `third_party/lzma/LzmaDec.c` | Reviewed |
| `third_party/lzma/LzmaDec.h` | Reviewed |
| `third_party/lzma/Precomp.h` | Reviewed |
| `tools/build.ps1` | Reviewed |
| `tools/check_repo.py` | Reviewed |
| `tools/compare_frames.py` | Reviewed |
| `tools/diag/pe_imports.py` | Reviewed |
| `tools/field_snapshot.py` | Reviewed |
| `tools/gmapack/gmapack.py` | Reviewed |
| `tools/gmapack/tests/test_gmapack.py` | Reviewed |
| `tools/install-loader.ps1` | Reviewed |
| `tools/lib/VsDevEnv.psm1` | Reviewed |
| `tools/package_fixes.py` | Reviewed |
| `tools/package_runtime.py` | Reviewed |
| `tools/poc_activation_check.ps1` | Reviewed |
| `tools/poc_deploy_check.ps1` | Reviewed |
| `tools/poc_parity.py` | Reviewed |
| `tools/poc_session.py` | Reviewed |
| `tools/smoke_test.ps1` | Reviewed |
| `tools/steam/make_vanilla_copy.py` | Reviewed |
| `tools/steam/steam_manifest.py` | Reviewed |
| `tools/steam/tests/_fixtures.py` | Reviewed |
| `tools/steam/tests/test_install_tools.py` | Reviewed |
| `tools/steam/tests/test_steam_manifest.py` | Reviewed |
| `tools/steam/tests/test_vdf.py` | Reviewed |
| `tools/steam/vdf.py` | Reviewed |
| `tools/steam/verify_install.py` | Reviewed |
| `tools/test.ps1` | Reviewed |
| `tools/tests/test_check_repo.py` | Reviewed |
| `tools/tests/test_companion.py` | Reviewed |
| `tools/tests/test_compare_frames.py` | Reviewed |
| `tools/tests/test_field_snapshot.py` | Reviewed |
| `tools/tests/test_package_fixes.py` | Reviewed |
| `tools/tests/test_package_runtime.py` | Reviewed |
| `tools/uninstall-loader.ps1` | Reviewed |
| `CMakeLists.txt` | Reviewed |
| `CMakePresets.json` | Reviewed |
| `loader/CMakeLists.txt` | Reviewed |
| `loader/cli/CMakeLists.txt` | Reviewed |
| `loader/core/CMakeLists.txt` | Reviewed |
| `loader/proxy/CMakeLists.txt` | Reviewed |
| `loader/proxy/tests/CMakeLists.txt` | Reviewed |
| `loader/tests/CMakeLists.txt` | Reviewed |
| `third_party/lzma/CMakeLists.txt` | Reviewed |
| `tools/gmapack/gmapack.bat` | Reviewed |

## Checks not run and remaining work

- No real GMod, PoC or field launch, game-install write, user `console.log` read, or read of the main checkout's `out/m7/snapshot`: prohibited by the R1 brief. Real renderer behavior, Steam root-launcher command-line behavior and actual engine-DLL hook timing remain for Claude's PoC checks after fixes.
- No registry mutation beyond the baseline `tools/test.ps1` throwaway-key tests. R1-011 used mocked `reg` commands, so the actual failure path needs an isolated registry test before any field rollback.
- No network, Workshop upload or publication. The private upload test remains the user's decision. NVIDIA redistribution and GPL release obligations were not verified against current external terms.
- LuaJIT was unavailable for the companion Python tests in the baseline; optional MSVC `/analyze`, ASan and parser fuzzing were not run. The Python package tests were rerun after the build: 24 passed, no skips. A later full test run exposed R1-029 and failed its Python tool group; its CTest passed.
- **Coverage limit:** every listed source file and script document was reviewed within the brief's scope; vendored LZMA and gmapack were checked for provenance and licence, not audited internally. Findings based on mocked registry/process faults still need the isolated follow-up checks stated above.

## Questions

- **For the user:** Is the vendored GMA File Packer your own MIT-licensed code, and what exact source revision should be recorded? Before any public package, which GPL-2.0 source and notice delivery and NVIDIA redistributable terms have been cleared? ADR 0011 also says its expanded add-on path rule still needs your confirmation.
- **For Claude:** Triage the confirmed P0 cases before any permanent field install. After fixes, exercise link and file failures and hook behavior in synthetic hosts, then run the approved PoC checks. Confirm whether loading System32 `winmm.dll` in `DllMain` and writing `session.json` inside the DLL notification callback can cause a loader-lock stall or re-entry on the supported Windows build; this review found a risk path but no concrete deadlock reproduction, so it is a question rather than a finding.
