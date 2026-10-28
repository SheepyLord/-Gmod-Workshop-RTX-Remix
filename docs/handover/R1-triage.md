# R1 triage (Claude)

- Triaged by: Claude, 2026-10-28.
- Input: Codex's [R1 report](R1-report.md), reviewing `c540358`: 29 findings (12 P0, 8 P1, 7 P2, 2 P3),
  each with a failure scenario, 25 of them with a repro under the review worktree's
  `out/r1-review/repro/`.
- Branch: `r1-fixes`, in the worktree `out\worktrees\r1-review`, on top of Codex's report commit
  `0a509dc`. The Python tool fixes were made in parallel on `r1-fix-snapshot` and `r1-fix-tools` and
  merged into `r1-fixes`.
- Decisions that change behaviour: [ADR 0014](../decisions/0014-r1-hardening.md).

## How I checked

I read each finding against the code at `c540358` and looked at Codex's repro where it had one. Every
accepted finding is fixed with a regression test that fails on the old code. Where a new test was
not practical, the fix is structural and the reason is given below.

I accepted all 29 findings. One was accepted in part (R1-008), one is a question for the user
(R1-025), and several severities changed.

I re-rated against the brief's scale. P0 means damage in a normal setup, or with a plausible
trigger. Several of Codex's P0s need a junction that someone deliberately placed inside the loader's
own folders; only a local user or program can create one. I kept those findings and fixed them, at a
lower severity.

## Findings

| ID | Codex | Triage | Fix | Regression test |
|---|---|---|---|---|
| R1-001 | P0 | accepted, **P2**: the trigger is a junction at `native-loader\logs`, and the harm is log lines appended to a file named `loader.log` | Every append to `loader.log` (the final report and the emergency log) first checks that nothing between the game root and the file is a link (`log_path_ordinary`, no allocation) | `nl_session_integration`: "native-loader\logs a junction" |
| R1-002 | P1 | accepted, **P2**: needs an allocation failure in the middle of installing hooks | A slot is recorded before it changes; `install()` undoes everything on any failure; activation owns the hooks before it calls `install()` | Structural (no allocation-failure injection); the paths are covered by the existing activation-failure scenarios |
| R1-003 | P1 | accepted, **P2**: needs an activation failure while another thread is inside a hook | The hooks' state is published once and never cleared or freed. Each hook reads it once, and `uninstall()` makes every hook a pass-through. A slot whose restore fails therefore stays safe | Structural |
| R1-004 | P1 | accepted, **P1** | The restore runs only with a readable journal. It puts a value back only while `config.cfg` still holds what the RTX session set, so a value the user changed is kept. The record is schema 2 (ADR 0014 point 4) | `nl_tests` "a restore keeps what the user changed"; `nl_session_integration` "invalid journal" and "RTX off" |
| R1-005 | P0 | accepted, **P2**: same trigger class as R1-001 | `session.json` is written only when no folder below the game root on its path is a link | `nl_session_integration`: "garrysmod\data\native-loader a junction" |
| R1-006 | P1 | accepted, **P2**: GMod's DLLs are MSVC-built and have name tables; the fix makes the hooks robust anyway | Descriptors without `OriginalFirstThunk` are matched by bound address. Every RVA is checked against the image, and the walk ends at the empty descriptor. A module with no hookable search imports is noted in `session.json` | `nl_session_integration`: "filesystem_stdio.dll without an import name table" |
| R1-007 | P0 | accepted, **P1**: needs a missing depot file and an allowlisted package naming it | `garrysmod/cfg` is no longer a package area. It holds 18 depot files; the other areas hold none ([RESEARCH.md](../RESEARCH.md) section 16) | `nl_tests`: paths, manifest and "deploy: a package cannot create a missing Steam file" |
| R1-008 | P0 | accepted **in part**, **P2** | Activation checks the journaled size **and time** of the whole runtime payload, the layers and the override DLLs. A deliberate change that keeps both is out of scope: a process that can write the game folder can replace the bootstrap itself (ADR 0014 point 3) | `nl_activation_integration`: "changed-runtime" |
| R1-009 | P0 | accepted, **P0** | `field_snapshot.py`: rollback never deletes. Unique debris names; a failed move leaves the entry in place and the rollback not clean; the snapshot folder must be on the install's volume | `test_field_snapshot.py` |
| R1-010 | P0 | accepted, **P1**: needs a junction in the install | `field_snapshot.py`: nothing is restored through a link. A listed entry that became a link moves to debris; the snapshot records entry kinds (schema 3) | `test_field_snapshot.py` |
| R1-011 | P0 | accepted, **P0** | `field_snapshot.py`: `registry.reg` is hash-checked. A failed import or parse prunes nothing and fails the rollback | `test_field_snapshot.py` (mocked `reg` and a throwaway key) |
| R1-012 | P0 | accepted, **P1** | `field_snapshot.py`: a Steam-managed install needs its depot inventory (or `--no-depot-check`). Depot-listed files are never written back, and the report says whether the depot check ran | `test_field_snapshot.py` |
| R1-013 | P0 | accepted, **P1**: needs a damaged snapshot | `field_snapshot.py`: every saved copy is checked (size, SHA-256) before anything changes | `test_field_snapshot.py` |
| R1-014 | P0 | accepted, **P1** | `install-loader.ps1 -RemoveState` (used by `uninstall-loader.ps1 -RemoveConfig`) deletes only the loader's own control and log files and the folders left empty. A changed payload file stays and is listed | `nlctl_uninstall_loader`, `nl_proxy_installer` |
| R1-015 | P0 | accepted, **P2** (one user folder with our exact name), plus a rule I broke, below | `poc_session.py` sends client Lua through the console, hex-encoded, and writes nothing into the install | `test_poc_session.py` |
| R1-016 | P1 | accepted, **P2**: a developer tool fed its own arguments | `poc_parity.py` validates every relative path, including the recorded ones before a restore | `tools/tests` |
| R1-017 | P1 | accepted, **P2**: no such files in today's inputs | Both packagers refuse `user.conf`, logs, `.env` and dumps by default and print the full inventory | `test_package_runtime.py`, `test_package_fixes.py` |
| R1-018 | P2 | accepted | `build.ps1` puts the whole process environment back when it ends | By inspection; `tools\test.ps1` runs it in-process |
| R1-019 | P1 | accepted, **P2** | `poc_session.py` terminates only the game it launched and that game's descendants, checked by parent PID and creation time | `test_poc_session.py` |
| R1-020 | P2 | accepted | `verify_install.py` fails a depot path that passes through a link, and a non-empty depot file without a hash | `tools/steam/tests` |
| R1-021 | P2 | accepted | `test.ps1` builds before the Python tests, so their native cross-checks run | The full run |
| R1-022 | P2 | accepted | Every file in the folder areas must be inside a named folder (ADR 0014 point 1) | `nl_tests`: paths and manifest |
| R1-023 | P2 | accepted, **P3** | ARCHITECTURE: `PATH` instead of `SetDllDirectoryW`, and commit before report, with how to tell the real state | — |
| R1-024 | P3 | accepted | `session.json` gains `utc` (and `notes`); override entries gain `module` | `nl_session_integration` checks `utc` |
| R1-025 | P2 | **answered by the user**: "tools/gmapack is our own code" | `gmapack.py.md` records it as the user's code, under this repo's MIT licence; the upstream revision is not recorded | — |
| R1-026 | P0 | accepted, **P1** | `poc_session.py install` refuses to replace a different `config.json` without `--replace-config`, which backs it up first. `field_snapshot.py` keeps `native-loader/config.json` | `test_poc_session.py`, `test_field_snapshot.py` |
| R1-027 | P3 | accepted | COMPONENTS top rows, the core README's areas, the companion's README and `.md` (timer, Steam request, session fields), and `test.ps1.md` evidence folders | — |
| R1-028 | P2 | accepted, **P3** | The three test files create their temporary folders under `out\tmp` | — |
| R1-029 | P1 | accepted, **P1** | Every `powershell` child of the Python tools starts without `PSModulePath` | `test_field_snapshot.py`, `test_poc_session.py`; the full run after the build |

## A regression the fixes introduced, caught before merge

The first version of the R1-003 fix kept the hooks' state published for good, and so refused a
second `install()`.

- **The failure.** A start whose runtime fails to load after the RTX hooks went in (for example a
  failing `DllMain`) continues as a start without a runtime. Its add-on hiding (ADR 0013) needs a
  second installation, so the RTX-only add-ons would have stayed visible.
- **The fix.** `install()` is now refused only while an earlier installation is active; the old
  state stays allocated.
- **The test.** `nl_session_integration` covers this case ("runtime DllMain fails"). It was checked to
  fail without the fix.

## A rule I broke in M5

R1-015 also shows that `poc_session.py --reference` wrote into the reference install, against
AGENTS.md rule 1.

- **What happened.** The client Lua went into `garrysmod/data/nl_session/`, and the folder was
  deleted after the run. My M5 reference sessions on `GarrysMod_RTX_c` therefore created and removed
  that folder there.
- **What it touched.** The folder did not exist before, so nothing of the user's was lost.
- **What changed.** The driver now writes nothing into any install.

The game itself still writes its usual files when the reference runs (`console.log`, `config.cfg`).

## Codex's question to Claude: loader-lock work

**Loading the system `winmm.dll` in `DllMain`.** This happens on the loading thread, where the loader
lock is re-entrant. The system DLL has no dependency on our module. It is the standard pattern for
proxy DLLs, and every M1-M7 run (synthetic, PoC and field) used it without a stall. It stays as it is.

**`session.json` inside the DLL notification.** The write is ordinary file I/O and loads no library:
JSON text, `CreateFileW`, `WriteFile`, `MoveFileExW`. That is allowed under the loader lock. A slow disk
or a scanner can make it slow, and the write happens only when a patch is applied, a module is hooked
or an add-on is first left out. No deadlock is possible from this path. Moving the write out of the
notification would need a thread or a later hook point, which brings risks of its own, so it stays,
recorded here.

## How the tool fixes landed

Two parallel branches, each with its own regression tests. Each new test was run against the old
script and failed there, except one test that checks ordinary use still works.

### `r1-fix-snapshot`: `field_snapshot.py`, R1-009 to R1-013 and parts of R1-026/029

- **Snapshot schema 3.** Listed entries record their kind, and rollback refuses older snapshots.
  M7's `out\m7\snapshot` is schema 2, so take a new snapshot before the next field session.
- **Rollback never deletes.** An entry it cannot move is listed under `left_in_place`, and the old
  `deleted` key is gone.
- **Writes are checked.** A kept file is written only through ordinary folders, and then only after
  opening it shows it resolves to its own path.
- **Copies are checked first.** Every saved copy is verified before anything changes, and the
  registry export's SHA-256 is checked before any import or prune.
- **Steam's files.** A Steam-managed install needs its depot manifests, or `--no-depot-check`. Steam's
  files are never written back, except the user-config files Steam itself leaves to the user, such
  as `autoexec.cfg`.

### `r1-fix-tools`: `poc_session.py`, `poc_parity.py`, the packagers, `verify_install.py`, test scratch

- **Lua through the console.** Client Lua goes through the console, hex-encoded. In-game check below:
  the camera Lua ran (`camera: true`) in three PoC sessions.
- **Process tree.** The driver tracks the process tree by parent and creation time.
- **Config backup.** `install --replace-config` backs the old config up into the evidence folder.
- **Private files.** The packagers refuse private-looking files unless `--allow-private` names them,
  and write `<output>.inventory.txt`.
- **Map compile logs.** The fixes repo keeps two map compile logs beside its maps, which would have
  stopped the real fixes build. Claude made `maps/*.log` junk (left out) rather than a refusal; any
  other log still refuses the build.

## In-game checks after the fixes (PoC)

With the M5 packages (runtime B and the RTX fixes) and the R1 bootstrap:

| Run | Result |
|---|---|
| RTX on (twice) | First start deployed both packages (445 changes, 7.2 s). The game loaded the package's `d3d9.dll` and `stdshader_dx6.dll`; all 7 patch sets applied; 33 session variables; `mat_dxlevel` 90; a path-traced frame; normal quit, no Lua errors. The second start recorded only the ToPBR file the fixes rewrite (known since M5) |
| RTX off | System32 `d3d9.dll`, the vanilla shader, all 9 of the fixes' add-on folders left out of `filesystem_stdio`'s searches (5 imports hooked), `session.json` with its `utc`, normal quit |
| Uninstall | 2,877 depot files OK, also under the stricter R1-020 check (no links, no size-only files) |

The Workshop upload test then used the same build and the fixed session driver; see
[ADR 0015](../decisions/0015-workshop-route-for-native-packages.md).

## Questions for the user, and the answers (2026-10-28)

1. **R1-025: is `tools/gmapack` your own code?** "Yes, tools/gmapack is our own code." Recorded in
   `gmapack.py.md`.
2. **ADR 0011.** "This should address 0011", given with the approval of the Workshop test. Recorded as
   confirmed. The test also showed that the Workshop route needs ADR 0011's add-on folders, because
   GMod does not mount an item holding native files.
3. **Before any public package:** the GPL-2.0 Lua and binaries in the fixes package, and the NVIDIA
   binaries in the runtime package, need their licence texts, source offers and NVIDIA's
   redistribution terms checked. Still open; nothing is public. (A first version of this note also
   said GMod's Workshop rules restrict `.dll` files. They do not: the rules have no rule about file
   types, and the wiki's `.dll`/`.exe` list is what `gmad.exe` packs. Corrected 2026-10-28 at the
   user's direction; see ADR 0015.)

## Still open after R1

- No test drives an SEH fault through start-up, or an allocation failure inside the hook installation
  (R1-002/003 are structural fixes).
- Codex noted that a line-by-line check of every script's `.md` against its script was not finished.
  The ones touched by these fixes were updated with them.
- `tools/gmapack/tests/test_gmapack.py` still uses the system temp folder when run directly.
  `tools\test.ps1` points it at `out\tmp`.
- The Workshop test item 3829070317 is still on the Workshop, hidden. Deleting it needs its page,
  which only the user can open.
