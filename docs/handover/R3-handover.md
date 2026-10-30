# R3 handover: whole-repo review for robustness, stability and bugs

- From: Claude, 2026-10-30
- To: Codex (or another reviewer)
- Branch: `r3-review` in `H:\BACKUP_20260815\Modding\!NVIDIA-RTX-Remix\out\worktrees\r3-review`, from
  `main` (the commit that adds this brief)
- Deliverable: `docs/handover/R3-report.md` on `r3-review`. Nothing else is committed
- Setup and the prompt to give the reviewer: [R3-codex-prompt.md](R3-codex-prompt.md)

## 1. Purpose

A thorough, independent review of the whole repository for **robustness, stability and bugs**, after
the rounds since R1 and before more players get the RTX package. Find what would crash or hang the
game, damage an install or the user's data, break the build or the publish, waste the Git LFS quota,
or render wrongly. **Report; do not fix.** Claude verifies each finding, triages and fixes them.

Since [R1](R1-report.md) (merged at `afe1fb9`, 2026-10-28) the repository gained: ReShade in RTX
sessions, module dependencies and late runtime DLLs in the loader (0.3.0-0.5.0), content packages from
any subscription, the companion's menu, guide, sky and weather, the runtime fork's translated menus and
sky (as patches), and, last, one repository that builds everything: the RTX package's inputs in
`packages/` under Git LFS ([ADR 0033](../decisions/0033-one-repository-package-inputs-in-git-lfs.md)).

## 2. Read first

1. [AGENTS.md](../../AGENTS.md): the rules. They bind you too.
2. [docs/ARCHITECTURE.md](../ARCHITECTURE.md), [docs/COMPONENTS.md](../COMPONENTS.md),
   [docs/PACKAGE_FORMAT.md](../PACKAGE_FORMAT.md).
3. The decisions since R1: [0020](../decisions/README.md) to [0033](../decisions/0033-one-repository-package-inputs-in-git-lfs.md)
   (the index lists them).
4. [packages/README.md](../../packages/README.md), [runtime/README.md](../../runtime/README.md).
5. [docs/RESEARCH.md](../RESEARCH.md) sections 25-30 (translations, ReShade, late DLLs, the sky,
   the Moon and night sky, the one-repository move).
6. [R1-report.md](R1-report.md) and [R1-triage.md](R1-triage.md): what was found and fixed then.

## 3. State at handover

- `main` is pushed to `origin` (GitHub, private). Loader 0.5.0. CI: `build.yml` (loader, no LFS) and
  `package.yml` (the RTX package from `packages/`, LFS objects cached).
- Workshop item 3829070317 holds the package `0.0.0-dev.20261030000530+f6c615a6` (content digest
  `942d0083...`); the build from `packages/` reproduces it byte for byte.
- The runtime is the fork `sambow23/dxvk-remix-gmod` at `c6b48ed1` plus [`runtime/patches`](../../runtime/README.md)
  0001-0004; the packaged `d3d9.dll` has SHA-256 `d9cf79e6...`.
- Tests: `tools\test.ps1` passes (17 CTest tests, 176 Python tests in `tools\tests`, the conventions).

## 4. What to review, in this order

`git diff afe1fb9 main` is the part that has had no review. Review it in depth; read the rest as context
and report what you find there too.

### 4.1 Area A: code that runs inside `gmod.exe` (first)

`loader/proxy` (the `winmm.dll`) and the `loader/core` paths it calls at start-up: activation, the
deployer, `reshade.cpp`, module dependencies, late runtime DLLs (`runtime.cpp`, `modules.cpp`,
`startup.cpp`). A fault here kills the game before the user sees anything.

- Every path from the entry-point hook to the D3D9 device: what happens on a missing or partial
  deployment, a Workshop update mid-start, a locked file, a non-ASCII path, a second instance, a
  disabled config, a runtime that fails to load.
- Structured exceptions and C++ exceptions across the start-up boundary; anything that can throw or
  fault while the loader lock is held; DLL search order and the late-DLL list.
- Memory and handle lifetime, buffer sizes, `wchar_t` conversions, integer overflow in parsers (GMA,
  LZMA, JSON, KeyValues, manifests).

### 4.2 Area B: the runtime's sky (`runtime/patches/0004-*.patch`)

C++ in `rtx_atmosphere.h|.cpp`, `dxvk_state_cache.cpp`, shaders in `atmosphere_args.h`,
`atmosphere_sky.slangh`, `common_binding_indices.h`, `common_bindings.slangh`. Read the patch as
code (the fork's tree at `c6b48ed1` is context; a clone is at `H:\BACKUP_20260815\Modding\dxvk-remix-gmod`,
read only). Patches 0002 and 0003 (translations) are context; 0001 is a snapshot of someone's work
tree and out of scope.

- **GPU stability:** NaN or Inf on the sky-miss path (`acos`/`asin` domains, `normalize` of zero vectors,
  `atan2(0,0)`, divisions by `sin(moonRadius)`, `cosI + cosE`, `peak`, `skyPixelAngle`; `log`/`exp`
  overflow in the softplus; degenerate frames at the zenith or the celestial poles). `evalSkyRadiance`
  ends in `max(radiance, 0)`, which turns a NaN into black silently. Float16 range of what is written.
- **Struct layout:** `AtmosphereArgs` identical in C++ and Slang (16-byte rows), its offset inside
  `RaytraceArgs`, static asserts; new fields zeroed in `normalizeForSkyLutCache` when the sky tables
  must not depend on them, set in `getAtmosphereArgs` otherwise.
- **Bindings:** 216-219 and 221 collide with no pass that includes the common bindings; every binding
  bound in every pass that declares it (the 1x1 stand-in until the textures load).
- **Textures:** `loadSkyTexture` with BC3, BC5, BC7 (sRGB and UNORM), 1440x720, truncated or corrupt
  DDS, missing files, a path option changed or toggled mid-session, device loss, barriers before
  sampling, 220 MB when the night sky image is on, allocation failure; `resolveSkyTexturePath`.
- **CPU and GPU twins:** `applyEclipses` and `lunarEclipseLight` against the shader; `discOverlapArea`
  edge cases; the cap of the eclipse's light (64 times the daylight left).
- **`numCompilerThreads < 0`:** few cores, a value below minus the core count, signed/unsigned mixing.
- **Cost** per sky-miss pixel and per secondary-ray miss.

### 4.3 Area C: the build and publish toolchain

`tools/inputs.py`, `tools/build_package.py`, `tools/publish_workshop.py` (fingerprint, lock, unpack,
the hooks with Git LFS's steps), the packagers (`package_runtime.py`, `package_fixes.py`,
`package_content.py`, `package_reshade.py`, `package_workshop.py`), `tools/workshop.json`,
`.github/workflows/build.yml` and `package.yml`, `runtime/build_runtime.ps1`, `tools/check_repo.py`,
`tools/workflow.ps1`.

- A wrong upload: can the publisher upload a package built from stale, partial or unverified inputs
  (out/inputs left from another commit, an interrupted unpack, a pointer file, a dirty `packages/`)?
  Can two runs (hooks from a commit, a merge and a push) race?
- `inputs.py`: path traversal or case collisions through an index or an inventory, partial writes,
  symlinks or junctions under `packages/` or `out/inputs/`, prune deleting the wrong files, a corrupt
  `files.json`, very large files, time restoration.
- The hooks: the pre-push hook's stdin handling with `git lfs pre-push`, a push of several refs, no
  git-lfs, a push that is not of `main`; what a hook does in a worktree.
- CI: LFS bandwidth (the cache key, what runs on pull requests), the permissions, what fails silently.
- `build_runtime.ps1`: the patch-series check, a dirty or wrong worktree, the shader stamp, failures.

### 4.4 Area D: the companion (`companion/nativeloader`)

The sky (`nativeloader_sky.lua`, `sky_model.lua`, `weather_presets.lua`), the menu, the guide, the
guard, i18n. GMod client realm, LuaJIT.

- Convar callbacks that write convars (`writing`, `ours()`): recursion, lost updates; `takenOver` and
  `owner()` for maps whose add-on owns the sky; `RemixConfig` missing or failing; the `sent` cache
  (values Remix resets that are never sent again, values sent in a loop).
- Timers (0.25 s and 10 s): work per tick, `CurTime` jumps, map changes, the clock at 24 h.
- Weather blending and drift: interrupted blends, unknown names, angles across 0/360, NaN.
- `readMap` on malformed or huge BSPs; `sheltered()` every tick; the fog presets against the weather.

### 4.5 Area E: `packages/` and licences

- Each `files.json` against the stored files (`python tools\inputs.py verify --deep`), and the
  packagers' inventories against the indexes (a file a packager reads but the import missed).
- Licences: the RTX fixes (GPL-2.0, aggregated: is the licence and the source offer shipped with the
  binaries in the package?), NVIDIA's runtime DLLs, Night Sky HD LE's permissions and credits, Era-7's
  nebulae, NASA's credit, Model Hotloader's bundled libraries. The repository is private; note what
  would block making it public.

### 4.6 Area F: tools that touch real installs or the user's data

`poc_session.py` (the `--lua` and `--lua-shots` additions), `install-loader.ps1`, `field_snapshot.py`,
`poc_parity.py`, `classic_defaults.py`, `remix_defaults.py`.

### 4.7 Area G: tests

What the code since R1 does that no test covers; mocks that hide real behaviour (the GMod mocks of
`test_companion_sky.py`, the LFS pointer tests); tests that would pass with the feature broken.

### 4.8 Area H: docs against code

The `.md` beside each changed script; the ADRs since R1 against what the code does.

## 5. How to check

1. **Baseline.** In the worktree, `tools\test.ps1`, then `tools\build.ps1 -Config Release`; record the
   summary lines. If either fails on the clean worktree, stop and say so.
2. **The package build, without the network.** The worktree's `packages\` comes with the real LFS
   content from the shared `.git\lfs` (if you see pointer files, run `git lfs checkout`, which reads
   only local objects). Then
   `python tools\build_package.py --require-nlctl --out out\r3-review\dist --compare <main checkout>\out\workshop\published.json`
   should report the same content. It reads the published record and writes only under `out\`.
3. **Reproduce** suspected defects with small tests or scripts; keep their code and output under
   `out\r3-review\repro\<finding id>\`, and revert the working tree: only the report is committed.
4. **In-process behaviour:** the synthetic game hosts in `loader/proxy/tests`, under `out\`. Do not
   launch the real game; list game-only checks under "Checks you could not run" and Claude runs them
   with `tools\poc_session.py`.
5. **The runtime:** review the patch statically. Building it needs the fork clone and its SDKs; if
   you build, only with `runtime\build_runtime.ps1 -Fork H:\BACKUP_20260815\Modding\dxvk-remix-gmod
   -Worktree H:\BACKUP_20260815\Modding\dxvk-remix-gmod\.claude\worktrees\r3-review -NoImport`, which
   creates its own worktree there and changes nothing else.
6. **Optional, if already on this machine (download nothing):** MSVC `/analyze` or AddressSanitizer
   builds of `loader/core` and `loader/proxy` under `out\r3-review\`; mutated inputs through the
   parsers; `slangc` warnings for the sky shader.

## 6. Boundaries

| You may | You may not |
|---|---|
| Read anything in this repository, the fork clone and the add-ons' repositories (`H:\BACKUP_20260815\Modding\ipg\`, `garrys-mod-rtx-remixed`) | Change production code, tests, tools, docs or `packages\`, except the report. A temporary change for a repro is reverted before you commit |
| Build and run the tests, the synthetic hosts, `nlctl`, `inputs.py verify/unpack` and `build_package.py`, with output under `out\` | **Commit to `main`, merge into it, or push anything.** `main`'s hooks publish the Workshop item and a push uploads Git LFS content. Never run `tools\publish_workshop.py`, `gmpublish`, `git lfs push`, or `inputs.py import` |
| Write under `out\r3-review\`: scratch, repros, evidence | Use the network: no `git fetch`/`pull`, no `git lfs pull` (it spends the account's LFS bandwidth), no downloads |
| Add `docs/handover/R3-report.md` and commit it on `r3-review` | Write to any game install (the PoC included), `GarrysMod_RTX_c` or its backups; launch GMod; change Steam settings |
| | Touch the fork clone's checkouts or branches (its main folder is on `gmod-1.6.1` with someone's uncommitted work), or the add-ons' repositories |
| | Read a `console.log` from the user's installs, or anything under the main checkout's `out\m7\snapshot\` (the user's own files and play logs) |
| | Set `RTX_AUTOMATION_DISABLE_BLOCKING_DIALOG_BOXES`: it also gives Remix's crash reporter upload consent. Upload no crash data |

**Registry.** `tools\test.ps1` runs the `field_snapshot` tests, which create and delete a throwaway key
`HKCU\Software\NativeLoaderTest_<random>`. Nothing else may touch the registry.

## 7. Order of work and keeping progress

1. The baseline (section 5, steps 1-2).
2. Area A, then B, then C.
3. Then D, E, F, G and H.

Add findings to the report as you go and keep its coverage table current. If your context or time
runs short: finish the area you are in, commit the report with its coverage table, and say what
remains.

## 8. The report (`docs/handover/R3-report.md`)

1. **Summary:** the commit reviewed, how you checked, the baseline results, and the number of findings
   at each severity.
2. **Findings table**, most severe first: ID (`R3-001`, ...) | Severity | Area | File:line | Title.
3. **One section per finding:** what is wrong (file:line at the reviewed commit; for the runtime,
   the line in the patch and the file it changes); the failure scenario (the concrete input, settings
   or state, and the wrong result); evidence (the repro under `out\r3-review\repro\` and its output, or
   the exact trace); confidence (confirmed, likely, question); a suggested fix in a sentence or two.
4. **Checked and fine:** per area, what you verified and found correct.
5. **Coverage table:** every source file in scope: reviewed, partly reviewed, not reviewed.
6. **Checks you could not run, and why.**
7. **Questions** for the user and for Claude.

Severity:

| Level | Meaning |
|---|---|
| P0 | Damage to the user's install or data; native code from a source the user did not allowlist; a crash or hang of the game, or a GPU hang (TDR, device lost), in a normal setup; a publish of a broken or wrong package |
| P1 | Wrong behaviour in a supported setup with a realistic trigger (a Workshop update during start-up, a non-ASCII path, a second instance, a full disk); visibly wrong rendering in normal play; a build or publish that fails or silently skips a check; spending of the LFS quota without need |
| P2 | Robustness with an unlikely trigger; an invariant the docs state with no test; docs that could lead someone into a harmful action; code likely to break when next changed |
| P3 | Small issues: docs drift, dead code, unclear names |

**Already known.** Report these only with a new angle or a root cause:

- Zoomed to 5 degrees of view, the quarter Moon shows diamond-shaped blocks along the terminator and
  on its earthshine side; clouds, fog, Ray Reconstruction and DLAA do not change them (RESEARCH.md
  section 29).
- About 3 of 17 PoC sessions crashed 7 s into a map at `studiorender.dll+0x5d353`, right after the
  RTX fixes forced a model reload; the next start then waits on Remix's crash-upload prompt.
- Stars are sparse at 720p output (each output pixel averages the star layer, by design).
- The map's 3D skybox shows as a faint miniature in the physical sky at night.
- The RTX package does not ship the RTX fixes' GPL-2.0 licence text with their binaries.
- R1's known items still stand: the companion is hidden with RTX off; watched files are not copied by
  `field_snapshot.py`; patch sets need `-insecure` by default.

## 9. After the report

Claude verifies each finding, records it as accepted or rejected with the reason in `R3-triage.md`,
fixes the accepted ones on a separate branch, tests them (with PoC sessions where they matter) and
merges with the user's OK.

## 10. Stop and ask

Stop and ask the user only if the baseline fails on the clean worktree, or this brief seems to
conflict with AGENTS.md. A check that would need the game, the network or writing outside `out\` is
not a reason to stop: list it under "Checks you could not run" and carry on.
