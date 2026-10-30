# QoL handover: the repository to Codex Astra

- From: Claude, 2026-10-29
- To: Codex Astra, for a run of quality-of-life (QoL) changes the user will ask for
- Start from: `main` at the commit that adds this brief (pushed to `origin`; CI green)
- Work: one branch per change, in its own worktree under `out\worktrees\<name>` (AGENTS.md rules 8, 9)
- Report: `docs/handover/QoL-report.md` when a batch is done or you are blocked (rules for reports in
  [README.md](README.md))

Read [AGENTS.md](../../AGENTS.md) first: its rules bind you. This brief adds what an agent needs that
the rules do not say: where things stand, what works and what does not, how to test, and the traps
that cost earlier rounds time.

## 1. Where things stand

| What | State |
|---|---|
| Repository | `main` equals `origin/main`; every branch is merged; no stash. Worktrees left from earlier rounds (`out\worktrees\r3-001`, `r3-fixes`, `r3-review`, `.claude\worktrees\guinaifen-*`, `robin-*`) are clean and merged: remove one with `git worktree remove` when you need the space |
| Loader | 0.6.0, not released (no `v*` tag; a tag publishes a release, which needs the user). Installed on 2026-10-29 in the PoC and the field install; the field's earlier files are in `out\field-backups\20261029-loader-0.5.0` |
| RTX package | Workshop item 3829070317, version `0.0.0-dev.20261030022927+8beef27e`, built from `packages/` ([ADR 0033](../decisions/0033-one-repository-package-inputs-in-git-lfs.md)); the publish hooks report `unchanged-inputs` for every commit since |
| Other items | 3829275998 Modern House RTX (`0.0.0-dev.202610300425+d7efd636`, the R3-016 fix) and 3829348717 Guinaifen RTX: hidden test items. Modern House's source is the local branch `claude/modern-house-rtx` of `garrys-mod-rtx-remixed` (worktree `.claude\worktrees\modern-house-rtx` there), never pushed: its textures come from another author's map ([ADR 0023](../decisions/0023-content-packages-and-modern-house-item.md)), so where it goes is the user's call |
| Reviews | R1 and R3 closed ([R3-triage.md](R3-triage.md)): every finding fixed, rejected with a reason, or decided by the user |
| CI | `build.yml` (`tools\test.ps1 -Config Release`, then the end-user bundle as an artifact) green on `main`; `package.yml` runs on changes to the package's inputs |

Open items, none started: the runtime's own 260-character environment buffer (R3-017's root cause,
at the next runtime rebuild); a tint for the textured Moon (R3-002, only if the user wants it); the
licence review of `packages/` before anything goes public (R3-011, AGENTS.md rule 7); an RTX session
on a GPU that is not NVIDIA's; hardening in the user's RTX fixes repository against `r_forcehwlight 1`
(R3-016: their `prop_fixes` hook, their `autoexec.cfg`), which is GPL code you may read, not copy.

## 2. Features

- **Bootstrap** (`loader/proxy`): `bin\win64\winmm.dll`, a full proxy of System32's, that runs the
  loader at the EXE entry point; three off switches (launch option, environment, file); a status
  report every start (`garrysmod\data\native-loader\status.json`).
- **Packages and trust:** `.gma` packages with `native/manifest.json` ([PACKAGE_FORMAT.md](../PACKAGE_FORMAT.md))
  from the Workshop, local files and dev folders, by precedence (ADR 0006). Native code only from the
  allowlist in `native-loader\config.json`; content-only packages from any subscription (ADR 0027).
- **Deployment** ([ADR 0007](../decisions/0007-transactional-deployment.md)): one journaled transaction
  per start, staged and hashed, rolled back on any failure or crash; two generations kept; `nlctl
  rollback` and `uninstall`; unsubscribing removes a package (ADR 0025). Since 0.6.0
  ([ADR 0035](../decisions/0035-restore-automatically.md)): a changed package file is put back (the
  change kept in `native-loader\backup\edits`); a file in a package's way is kept in
  `backup\originals` and put back when the package goes; a foreign `winmm.dll` is kept by the
  installer and put back by `-Uninstall`.
- **Activation** ([ADR 0008](../decisions/0008-activation-at-startup.md)): the Remix runtime preloaded
  from its versioned folder; config layers below the player's own `dxvk.conf`/`rtx.conf`/`user.conf`
  (ADR 0021), handed over as short copies in `native-loader\remix` since 0.6.0
  ([ADR 0036](../decisions/0036-remix-layers-as-short-copies.md)); package environment and launch
  arguments; a borderless window (ADR 0018); System32 Vulkan; the runtime's late DLLs; Remix's own
  preset without an NVIDIA GPU (ADR 0030).
- **RTX-session extras** (ADR 0010): the fixes' engine patches in memory (with `-insecure`), the shader
  override, session console variables put back afterwards, RTX-only add-ons hidden without RTX
  (ADR 0013), a module's runtime DLL loaded first, only as deployed (ADR 0024, R3-001).
- **ReShade** in RTX sessions as a Vulkan layer with its own settings (ADR 0028).
- **Companion add-on** (`companion/`): the RTX Remix spawn-menu tab, a guide, restart notices, the
  physical sky, time of day, weather and fog presets (ADR 0031, 0032), in six languages from gettext
  files (ADR 0029).
- **Tooling:** `tools\build.ps1`, `test.ps1`, `workflow.ps1`; the package from `packages/` (Git LFS) with
  `build_package.py` and `inputs.py`; publish hooks (`publish_workshop.py`); the runtime fork's changes
  as patches with `runtime\build_runtime.ps1`; Steam depot verification; `poc_session.py` for scripted
  game sessions; installers.

## 3. Limitations and known behaviour

- 64-bit GMod on Windows only (the x86-64 branch). RTX needs a ray-tracing GPU; AMD and Intel are
  untested in a real session (the integrated Radeon here loses its device after about a minute).
- Nothing is public: the repository is private, the items are hidden, there is no release. No
  signatures: trust is the allowlist.
- Players' edits to package files do not stay: the next start puts the package's copy back (the edit is
  kept in `backup\edits`, which only the player empties). A change that should last belongs in a
  package of its own, or under a `create-only` path.
- A rollback over a taken-over file leaves that path empty until the next deployment (ADR 0035).
- Stale layer copies (a package that drops a layer) stay in `native-loader\remix` until
  `install-loader.ps1 -RemoveState`.
- The runtime crashes on exclusive-fullscreen mode switches (hence the borderless window), and after a
  crash its next start waits on an upload prompt.
- The engine patches are found by byte pattern: a GMod update can make one not match; it is then
  skipped and reported, not forced (RESEARCH.md section 31).
- The first load of `modern_house` after Steam updated its item once ended in an engine error during
  loading (no Lua state yet); the next start loaded it. Not reproduced.
- A rebuild of the runtime from `runtime/` differs from the packaged DLL only in its link stamps (15
  bytes): do not re-import a rebuild unless the patches changed (the LFS quota, rule 6).

## 4. Project standard

- **Rules:** AGENTS.md, all nine, and the standing permissions in rule 5: push `main` and update the
  project's Workshop items once `tools\test.ps1` passes; test items stay hidden; nothing on the
  Workshop is ever deleted; ask before other branches, tags, visibility changes, the field install, or
  any other repository.
- **Every change** keeps the documentation duties (`tools\check_repo.py` fails otherwise): a `.md`
  beside each script, a `README.md` per C++ module folder naming its files, COMPONENTS.md, links that
  resolve. Plus, by hand: a CHANGELOG line under `[Unreleased]`, an ADR for a design decision (an
  accepted one is amended or superseded by a new one, with a note in the index and its status line,
  never rewritten), ROADMAP, RESEARCH.md for facts you dug up (file:line, measured numbers), TESTING.md
  for new kinds of test.
- **A regression test with each fix.** Fixtures are generated by the tests; no game files in the repo
  or the tests.
- **Branches:** `<topic>` in `out\worktrees\<topic>`, merged with `git merge --no-ff` and a message
  `Merge <branch>: <what>`. Commit subjects name the finding or area (`R3-017: ...`, `install-loader:
  ...`); the body says why.
- **Writing:** plain English, short sentences, numbers measured rather than guessed; quote the user's
  decision word for word in an ADR's status.
- **The field install:** only when the user asks in the conversation; back up what you will touch in
  `out\field-backups\<date>-<what>\` with a `SHA256SUMS.txt`; preview with `nlctl apply <root>
  --dry-run` and `nlctl activation <root>`; `-AllowSteamManaged` for the installers there.

## 5. Test protocol

1. **Every change:** `tools\test.ps1` (conventions, Python tests, Debug build and 17 CTests). Loader
   changes also `tools\build.ps1 -Config Release`, which is what CI tests. Last results: conventions
   OK, 17/17, Python 28 + 25 + 188.
2. **Package changes** (`packages/`, `tools\workshop.json`, the packagers): on a branch,
   `git lfs pull` then `python tools\build_package.py --compare <main>\out\workshop\published.json`, and
   read the difference it reports. Merge only what you mean to publish: the hooks publish from `main`.
   A new manifest key or kind needs `tools\build.ps1 -Config Release` in the main checkout first.
3. **Loader or in-game behaviour,** on the PoC (`H:\SteamLibrary\steamapps\common\GarrysMod_PoC`):
   `tools\install-loader.ps1` (the PoC is its default), then
   `python tools\poc_session.py --evidence out\<purpose> run --name <step> --addons --settle 30 --screenshots 2 --hide-hud`.
   Read the record (`map_loaded`, `normal_quit`, `lua_errors`, `activation`, `deployment`), the copied
   `status.json` (`session.notes`, `activation.layer_copies`), the Remix log (`Using config paths
   from DXVK_CONFIG_FILE`) and the screenshots. The R3-017 run in `out\r3-017-poc` is a good baseline.
4. **In a running game:** the RTX fixes' debug module and its client
   (`garrys-mod-rtx-remixed\source\debug\tools\rtxdebug_client.py`): `Engine.GetConVar` (value and
   flags), `Engine.Entities` with a class name (all entities at once overflows), `Lua.Eval` (needs
   `sv_cheats 1` and `-insecure`). In-game screenshots: the console command `jpeg` sent to the
   `Valve001` window with `WM_COPYDATA`.
5. **Runtime changes:** `runtime\build_runtime.ps1 -Fork <clone> -Worktree <tree> -Verify` before any
   build; import a new `d3d9.dll` with `tools\inputs.py` only when the patches changed.

## 6. Pitfalls that cost time before

- **PowerShell 5.1:** `$x = if (...) { [IO.File]::ReadAllBytes(...) }` enumerates the array into boxed
  bytes (gigabytes for a PDB); write `{ ,[IO.File]::ReadAllBytes(...) }`. No `&&` or ternary. Native
  commands' stderr comes back as errors: a successful `git push` "fails" with exit 255, so check `git
  status -sb`. A here-string piped to `git commit -F -` does not arrive; write the message to a file in
  `out\tmp` and pass `-F <file>`.
- **Memory:** an RTX game holds about 17 GB. Six tests in parallel beside it reached the machine's
  commit limit; measure a test's own peak before blaming the machine (that is how the installer's
  boxed bytes were found).
- **CI has no NVIDIA GPU:** the loader adds `native-loader/remix/non-nvidia.conf` there, so expectations
  about layer lists must follow `activation.non_nvidia`.
- **The runtime reads environment variables into 260 characters;** a longer value reads as empty and
  drops every layer (R3-017). Keep anything the loader puts in a variable short.
- **Engine console variables:** `mat_softwareskin` is a cheat variable that Source resets when
  `sv_cheats` goes from 1 to 0. `r_forcehwlight 1` with `r_forcehwskin 0` draws models without a
  `.sw.vtx` in bind pose (R3-016): no add-on of ours may force it.
- **Game sessions:** never stop a `gmod.exe` you did not start (the user may be playing); test sessions
  use `-multirun`. With Workshop add-ons mounted, do not pass `+map`; wait for the fetch, then load the
  map. After a runtime crash the next start blocks on the upload prompt: let it time out, and never set
  `RTX_AUTOMATION_DISABLE_BLOCKING_DIALOG_BOXES` (it grants consent).
- **Privacy:** never search the user's GMod console logs; read only the part your own session wrote.
- **Probes in the field install:** a dev-folder package in `config.json` overrides the Workshop copy
  with the same id (ADR 0006). Put the user's `config.json` back byte for byte afterwards (compare the
  SHA-256 with your backup).
- **Publishing:** every commit, merge and push on `main` runs the publisher in the background
  (`out\workshop\logs`); it builds with the main checkout's `nlctl.exe`. Install the hooks once per
  clone (`python tools\publish_workshop.py --install-hooks`).
- **Files:** temporary and build files only under `out\` (Windows Defender blocked builds elsewhere);
  `check_repo.py` skips other checkouts inside the repository. Paths with `!` and `+` need quoting.

## 7. For a smooth start

- Read in this order: AGENTS.md, this brief, [ROADMAP.md](../ROADMAP.md), the
  [ADR index](../decisions/README.md), [R3-triage.md](R3-triage.md), [TESTING.md](../TESTING.md),
  [ENVIRONMENT.md](../ENVIRONMENT.md) (this machine's installs and toolchain).
- Decisions the user already made are in the ADRs, with their words: do not ask them again. New design
  decisions get an ADR the user agrees to (rule 4 for anything that loosens trust or path rules).
- Evidence folders under `out\` (`r3-016`, `r3-017-poc`, `field-backups`, `workshop\logs`) are local and
  git-ignored; RESEARCH.md and the triage hold what matters from them.
- When you finish a batch: the report, the CHANGELOG, a green `tools\test.ps1`, merged and pushed
  `main`, and the Workshop item current (the publish log says so).
