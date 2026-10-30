# R3 whole-repository review

## Summary

- Reviewed commit: `ec37c91cb5069dc115c7b08a5807a02815103aac` (`r3-review`, identical to local `main` and `origin/main` at review start); comparison base `afe1fb9`.
- Baseline: `tools\test.ps1` passed: `repo conventions OK`; `100% tests passed, 0 tests failed out of 17`; 28 GMA packer tests (1 skipped), 25 Steam tool tests (1 skipped), 177 tool tests (5 skipped); `All checks passed.` `tools\build.ps1 -Config Release` passed: `100% tests passed, 0 tests failed out of 17`; `Build win64-release OK`. Offline package build passed: `877 files, 1,798,746,608 bytes` of GMA output, digest `942d00838b9148c7`; `content the same as 0.0.0-dev.20261030000530+f6c615a6`.
- Review method: source and diff tracing, tests, local build and package comparison. No game or network use.
- Findings: P0 5, P1 7, P2 2, P3 0.

## Findings

| ID | Severity | Area | File:line | Title |
|---|---|---|---|---|
| R3-001 | P0 | A | `loader/proxy/modules.cpp:188-208`, `loader/proxy/startup.cpp:178-203`, `loader/proxy/runtime.cpp:158-182,324-337` | Dependency DLLs load without checking their journaled contents |
| R3-003 | P0 | C | `tools/inputs.py:327-335`, `tools/publish_workshop.py:197-205` | Unpack trusts size and time instead of the indexed hash |
| R3-004 | P0 | C | `tools/publish_workshop.py:338-350,25-26,119-135` | A push of main from another worktree can publish that worktree's package |
| R3-006 | P0 | C | `tools/inputs.py:323-349` | Unpack follows a junction and deletes unrelated files |
| R3-008 | P0 | C | `tools/package_workshop.py:76-105,206-225` | A part manifest can make the combiner truncate an arbitrary file |
| R3-002 | P1 | B | `runtime/patches/0004-*.patch:816-903` (`atmosphere_sky.slangh`), `companion/nativeloader/lua/autorun/nativeloader_sky.lua:60` | Textured Moon ignores moon 0's colour setting |
| R3-005 | P1 | C | `tools/publish_workshop.py:153-174,278-305` | The publish lock can be stolen while its owner writes the PID |
| R3-007 | P1 | C | `tools/inputs.py:163-172,241-260` | Import skips changed input when size and time stay equal |
| R3-009 | P1 | D | `companion/nativeloader/lua/autorun/nativeloader_sky.lua:297-300,361-369,422-459` | Clearing weather leaves the prior weather active |
| R3-012 | P1 | F | `tools/install-loader.ps1:137-175` | A failed default-config copy leaves a completed bootstrap install |
| R3-013 | P1 | F | `tools/poc_session.py:693-700,724-727` | Workshop readiness accepts a partial first mount |
| R3-014 | P1 | C | `runtime/build_runtime.ps1:55-61`, `.github/workflows/package.yml:12-26`, `tools/publish_workshop.py:51-55` | Runtime patch changes can build or publish a stale DLL |
| R3-010 | P2 | D | `companion/nativeloader/lua/autorun/nativeloader_sky.lua:124-130,434-465` | Late Remix changes are never corrected by the sky timer |
| R3-011 | P2 | E | `packages/model-hotloader/LICENSE`, `packages/model-hotloader/licenses/`, `tools/workshop.json:62-100` | Model Hotloader's stored licence texts are absent from the built package |

### R3-001 — Dependency DLLs load without checking their journaled contents (P0, Area A)

`modules::load_first` loads each `load_first` path directly with `LoadLibraryExW` and no file check. Both the RTX-off setup in `hide_rtx_addons` and the RTX-on setup in `RuntimeActivation::apply` take these paths from the committed journal. The RTX-on `check_record` validates the runtime payload and module overrides, but not dependency root files. In `deploy.cpp:710-715`, an altered owned root file is kept as `keep_edited` rather than replaced, so a previously deployed `garrysmod/lua/bin/mmdhl_runtime_win64.dll` can be altered while the journal still records the original allowlisted bytes. The next module load runs the altered DLL. This defeats the stated rule that native code comes only from an allowlisted package.

**Failure scenario:** An installed dependency DLL is replaced or edited after deployment (including during a second instance's deferred deployment). On the next start, `lua_shared.dll` loads its module and the import hook preloads the changed dependency. The actual bytes no longer match the allowlisted package.

**Evidence:** Static trace at the reviewed commit: `loader/core/src/deploy.cpp:710-715` → `loader/proxy/startup.cpp:181-202` or `loader/proxy/runtime.cpp:324-337` → `loader/proxy/modules.cpp:188-208`. The RTX activation checks at `runtime.cpp:158-182` omit the dependency file paths. Confidence: confirmed from code; a game-only validation was not run.

**Suggested fix:** Validate each dependency against the current journal immediately before loading it, ideally with SHA-256 because the trust boundary is native code; refuse the preload and report the mismatch. Apply the same gate in RTX-on and RTX-off sessions.

### R3-002 — Textured Moon ignores moon 0's colour setting (P1, Area B)

The new `evalTexturedMoon` uses the sampled albedo, `moonTextureAlbedo`, `m.brightness`, sunlight and eclipse factor, but never `m.color`. The existing moon option describes `rtx.atmosphere.moon0.color` as its surface albedo and explicitly supports per-channel tint; the companion sets it to `0.11, 0.12, 0.135`. The procedural path uses that colour. With `moonTextureEnable` true (the new default) the disc ignores the setting while moonlight and halo paths use it.

**Failure scenario:** Set moon 0 colour to a visibly red value in the Remix menu during a normal physical-sky session. The textured Moon disc remains its original albedo colour, while its light and halo change colour. Weather or the companion's own slight blue tint also cannot colour the disc.

**Evidence:** Static shader trace in patch lines 816-903, compared with the `Moon0::color` option in the fork's `rtx_atmosphere.h:418-420` and the companion's write at `nativeloader_sky.lua:60`. Confidence: confirmed from source; visual magnitude needs a PoC session.

**Suggested fix:** Apply `m.color` to the textured disc with a scale that preserves the existing neutral 0.12 albedo; keep its eclipse modulation consistent with the halo and distant moonlight.

### R3-003 — Unpack trusts size and time instead of the indexed hash (P0, Area C)

`inputs.unpack` skips an existing `out/inputs/<part>` file when its size and `mtime_ns` equal the index. It does not compare its SHA-256. `publish_workshop.build` calls this unpacker and then feeds the resulting tree to the packagers; the fingerprint deliberately excludes `out/inputs`. A stale or altered cache entry with matching metadata can therefore become the uploaded package while the fingerprint still describes the committed `packages/` inputs. The packagers hash the altered bytes, so their manifest and `nlctl` validation accept the wrong content.

**Failure scenario:** A prior interrupted tool, copied cache, or local edit leaves an altered `out/inputs` file of the same length and timestamp as its index entry. A later publish builds and may upload that file as if it came from the current commit.

**Evidence:** `out/r3-review/repro/R3-003/repro.py` and `output.txt`: after changing one byte of the 27-byte remove-halo Lua input and restoring its indexed time, the second unpack wrote 0 files and left a SHA-256 mismatch. Confidence: confirmed by isolated reproduction.

**Suggested fix:** Hash-check reused unpacked files (or always regenerate them into an isolated, verified build tree). Make publish fail if any unpacked input does not match its index before building.

### R3-004 — A push of main from another worktree can publish that worktree's package (P0, Area C)

The shared pre-push hook tests only whether `remote_ref` is `refs/heads/main`, then invokes `tools/publish_workshop.py` from `git rev-parse --show-toplevel`. In a worktree on another branch, `--show-toplevel` is that worktree, even when the command is `git push origin main`. The script's `REPO`, `HEAD:<path>` fingerprint, `packages/` reads and dirty check therefore all refer to the other branch. The hook is installed in the shared common Git hooks directory and applies to every worktree.

**Failure scenario:** A maintainer pushes `main` from a clean review or feature worktree with different package inputs. Git sends `main`, but the hook can upload that worktree's package to item 3829070317. The publication record then attributes the wrong checkout's HEAD to the item.

**Evidence:** The installed shared pre-push hook matches the template at `publish_workshop.py:338-350`; in this review worktree `git rev-parse --show-toplevel` resolves to `.../out/worktrees/r3-review`, while `git rev-parse --git-path hooks/pre-push` resolves to the main checkout's common hook. Confidence: confirmed static trace; no push or publisher was run.

**Suggested fix:** For a main-ref push, publish from the main checkout or from the exact `local_sha` being pushed; reject a checkout whose HEAD does not match that SHA. Match both local and remote refs before dispatch.

### R3-005 — The publish lock can be stolen while its owner writes the PID (P1, Area C)

`acquire_lock` creates `publish.lock` with `O_EXCL`, then writes its PID in a separate step. A second process that sees the just-created empty file parses owner 0, decides it is stale, and unlinks it. Both processes can then return `True`. They share `STATE/work`, the newest `.gma` files and `published.json`; one can delete the other's build or upload an older build last.

**Failure scenario:** Commit and pre-push background publishers start together and the second checks the lock between the first process's `os.open` and `os.write`. The builds race, often failing, and the final Workshop item or record may reflect the wrong run.

**Evidence:** Exact interleaving of `publish_workshop.py:159-170`, followed by shared deletions and writes at lines 278-305. Confidence: confirmed race in code; the window was not forced in a live publisher because publishing is outside this review's boundary.

**Suggested fix:** Hold an OS-level exclusive lock on an open file for the whole publish, or use a lease protocol that cannot classify a newly created empty file as stale. Keep each run's work and output paths unique.

### R3-006 — Unpack follows a junction and deletes unrelated files (P0, Area C)

`inputs.unpack` accepts an existing `out/inputs/<part>` directory without checking whether it is a symlink or junction. It writes the part's files there, then walks it and unlinks every file not listed by `files.json`. On Windows, an `out/inputs/<part>` junction can point to another directory, so this cleanup deletes files outside the unpack cache.

**Failure scenario:** `out/inputs/remove-halo` is a junction to a user folder. Building the package writes the part's Lua file into that folder and deletes its other files as stale. The same applies to a junction in an intermediate output path.

**Evidence:** `out/r3-review/repro/R3-006/repro.ps1` and `output.txt`: a junction pointed only to a sibling scratch folder under `out/r3-review/repro`; `inputs.unpack` reported `1 stale removed` and deleted the scratch folder's `unrelated.txt`. Confidence: confirmed by isolated reproduction.

**Suggested fix:** Refuse links and junctions at the destination root and at every component before writing or pruning; constrain resolved paths to the intended unpack root.

### R3-007 — Import skips changed input when size and time stay equal (P1, Area C)

The packagers' inventory records hashes, but `read_inventory` discards them. `import_files` considers an indexed source unchanged when only its size and `mtime_ns` match and the old stored file exists; it never hashes the current source. A tool that preserves timestamps can supply changed bytes without updating `packages/`, so the next build and publish omit the intended change.

**Failure scenario:** A source build or copy replaces a DLL or Lua file with different bytes but preserves its length and timestamp. The maintainer runs the documented inventory import; it reports 0 to store and leaves the old LFS object/index in place. The published item stays stale.

**Evidence:** Static trace of `inputs.py:163-172` and `245-250`. The prohibited `inputs.py import` operation was not run. Confidence: confirmed from the comparison condition; no live import reproduction.

**Suggested fix:** Compare the source hash with the indexed `sha256` before skipping. Use the inventory's hash as a cross-check, and make index updates atomic.

### R3-008 — A part manifest can make the combiner truncate an arbitrary file (P0, Area C)

`Part` parses a part's manifest but does not validate its file paths before `combine` calls `Part.copy`. `folder / rel` and `self.path / rel` discard their prefixes when `rel` is an absolute Windows path. `Part.copy` opens the target for writing before it opens the source. An absolute path in `files` thus opens and truncates that same external file, even though the combined package is validated only afterward. `gmapack.read_gma` also accepts unsafe names for reading; its extraction path checks are not used here.

**Failure scenario:** A malformed or hostile part manifest lists `H:\some\user-file` as a file key, and that file exists. Combining the part truncates the user file before reporting a manifest/hash error. A GMA or folder passed via `--part` can carry the key.

**Evidence:** `out/r3-review/repro/R3-008/repro.py` and `output.txt`: the absolute key named only a 20-byte scratch sentinel under `out`; `combine` raised `CombineError`, and the sentinel was 0 bytes afterward. Confidence: confirmed by isolated reproduction.

**Suggested fix:** Validate every part manifest path against the loader's relative-path rules before creating a destination or opening a source; also resolve and constrain each target under the staging folder. Validate before any write.

### R3-009 — Clearing weather leaves the prior weather active (P1, Area D)

`weatherName` returns nil for the empty choice, and `setWeather` only sets `weather.name = nil`. Both `apply` and the 0.25-second timer then stop calling `pushWeather`; no previous cloud, fog, rain or lightning setting is restored in Remix. The control says an empty value leaves weather to Remix's own settings, but the last preset stays in effect until a new session or another actor changes it.

**Failure scenario:** Choose Rain, wait for the blend to finish, then select “(leave to Remix)”. Rain intensity remains 0.8 and cloud density remains 2.5 even after 10 seconds; no weather settings are sent.

**Evidence:** `out/r3-review/repro/R3-009/repro.py` and `output.txt` extend the existing LuaJIT mock harness in memory. The post-clear values remain rainstorm values and the harness records zero writes in the next 10 seconds. Confidence: confirmed in the repository's GMod mock; actual Remix behavior needs a PoC check.

**Suggested fix:** Snapshot the prior live values before taking weather ownership and restore them when the choice is cleared, or provide an explicit reset through the Remix API. Make the UI clear if a restart is required.

### R3-010 — Late Remix changes are never corrected by the sky timer (P2, Area D)

The `sent` cache records the last text the companion gave Remix. The four-times-a-second weather timer recomputes values, but `set` skips an unchanged value without reading whether another actor has since changed the live option. The one-time five-second `applyAll` handles the fixes' known map-start writes; the ten-second repeat runs only when the player has taken over a map with a recognized sky owner. A later change to a constant weather field can therefore persist for the rest of a normal session while the panel still says the selected weather is active.

**Failure scenario:** After the first five seconds, another add-on sets `rtx.atmosphere.cloudDensity` to `9` while the companion owns partly cloudy weather (`0.9`). The timer continues but never sends `0.9` again.

**Evidence:** `out/r3-review/repro/R3-010/repro.py` and `output.txt`: the existing LuaJIT harness, extended in memory, records zero cloud-density writes during 11 seconds after an external write. Confidence: confirmed in the mock; frequency of this interaction in the game is uncertain.

**Suggested fix:** Invalidate or refresh the cache when another actor changes a sky option, or periodically reconcile the live values at a lower rate. Keep the current per-tick cache for unchanged values.

### R3-011 — Model Hotloader's stored licence texts are absent from the built package (P2, Area E)

`packages/model-hotloader/` keeps its MIT licence and 27 bundled-library licence texts under `licenses/`, but they are outside `files.json`. `tools/workshop.json` passes only the add-on folder and six native files to `package_content.py`; the built Model Hotloader part manifest contains no licence or notice path. This is a new omission beside the already-known missing GPL text for the RTX fixes. The legal obligations of each library still require review before a public release.

**Failure scenario:** A player receives the Workshop package with Model Hotloader's native binaries but no accompanying licence texts for the bundled libraries. The repository's private copy of those texts does not travel with the package.

**Evidence:** Deep index verification passed; the built `out/tmp/package-work/model-hotloader/native/manifest.json` has zero licence/notice paths, while `packages/model-hotloader/` has 28 local licence files. Confidence: confirmed absence; whether each particular licence requires a shipped notice is a legal question not resolved offline.

**Suggested fix:** Have the Model Hotloader part carry the applicable licence/notice texts alongside its binaries, then review the runtime DLLs' redistribution texts before making the repository or package public.

### R3-012 — A failed default-config copy leaves a completed bootstrap install (P1, Area F)

`install-loader.ps1` wraps the DLL, PDB and receipt writes in a rollback `try/catch`, but the `-DefaultConfig` copy runs after that block. If the source config is missing, the target is blocked, or the disk fills during this copy, the command fails after leaving the new `winmm.dll`, PDB and receipt installed. A caller can interpret the failed install as no change, and the next game start loads the proxy without the intended allowlist.

**Failure scenario:** Use `-DefaultConfig` on a fresh install when the target disk fills as `config.json` is copied. The command errors, but the bootstrap files and receipt remain; the config may be absent or partial.

**Evidence:** Exact control flow at `tools/install-loader.ps1:137-175`; the default-config copy is outside the rollback block. Confidence: confirmed static trace; install writing is prohibited in this review, so no live reproduction.

**Suggested fix:** Stage and validate the default config before modifying the install, and include its final write in the same rollback plan as the DLL/PDB/receipt. Report partial success distinctly if a full transaction is impossible.

### R3-013 — Workshop readiness accepts a partial first mount (P1, Area F)

`wait_workshop` declares the Workshop ready after any mount message with a nonzero mounted count, even if it is the first message and `N < M`. Its own comment says GMod may mount once before Steam supplies the full subscription list, then remount. A first partial mount can therefore make `poc_session.py` send `map` too early and hit the same wait/hang this logic was added to avoid.

**Failure scenario:** The first message is `Mounted 1 of 755 workshop addons!` from cached items, with the remaining subscriptions still loading. The tool immediately treats it as ready after log quiet and sends the map; the game can wait for Workshop while the session timeout expires.

**Evidence:** Static trace of `tools/poc_session.py:693-700` and the call at lines 724-727. The tests cover a `0 of M` first mount, not a nonzero partial first mount. Confidence: likely; a real Workshop session is outside this review's boundary.

**Suggested fix:** Require a completed second mount when the first reports `N < M`, or use GMod's explicit remount/completion signal; include the observed sequence in the session record.

### R3-014 — Runtime patch changes can build or publish a stale DLL (P1, Area C)

For an existing fork worktree, `build_runtime.ps1` compares only commit subjects with the patch files' subjects. A patch's body can change while its subject stays the same; the script accepts the old worktree and rebuilds its old source. It also ignores submodule changes and untracked files. Separately, `runtime/**` is absent from the package workflow's push paths and from the publisher's `REPO_INPUTS`, so a patch-only change triggers neither package CI nor a new publish fingerprint. There is no automated assertion that `packages/runtime/files/d3d9.dll.xz` matches `runtime/base.json` plus the current patches.

**Failure scenario:** The sky patch is corrected without changing its subject, and an existing runtime build worktree still has the prior commit. `build_runtime.ps1` accepts it and imports the old DLL. If only the patch changes, package CI and the Workshop publisher also see no input change. The intended fix never reaches players, with no failing gate.

**Evidence:** Static trace of `build_runtime.ps1:55-61`, `package.yml:12-26` and `publish_workshop.py:51-55,119-135`. The fork was read only, as required; this check was not executed. Confidence: confirmed from the subject-only and path-filter conditions.

**Suggested fix:** Compare the worktree's exact tree/patch content against a clean application of the current patch series, and verify the built DLL against `base.json` before import. Include runtime source changes in CI/fingerprint or make an explicit mismatch gate fail until the LFS binary is updated.

## Checked and fine

### Area A

- The entry-point patch is restored before startup work, with SEH around the startup boundary. Runtime payload and module overrides are checked against the committed journal before activation. ReShade errors are isolated from runtime activation. Content-only package planning rejects native kinds and payloads.

### Area B

- The CPU and shader lunar-eclipse functions use the same branches and constants. `eclipseSunScale` and the eclipse shadow spans have positive lower bounds; the overlap formula clamps inverse-trigonometric inputs. The sky argument fields are declared in the shared C++/Slang header and zeroed for LUT cache comparison. Texture flags gate sampling, and a stand-in view is bound for each missing texture.

### Area C

- The baseline build combines all ten parts and `nlctl` accepts the result. The ReShade packager pins the setup, DLL and licence hashes; the combiner hashes copied file bytes; content-only package paths are checked by the loader. CI's package job verifies indexed stored inputs and requires a freshly built `nlctl`.

### Area D

- The sky model clamps inverse-trigonometric inputs, wraps bearings, and blends angles by the shorter route. Eclipse stages, preset fields and translations have test coverage. The map BSP reader caps the entity lump at 32 MiB; ownership checks gate writes to the sky until the player takes over.

### Area E

- `python tools/inputs.py verify --deep`: 10 parts checked, 0 problems. A retained package build's eight packager inventories matched their `files.json` source hashes and sizes; the only unused indexed files were the fixes' `autoexec.cfg` (read for cvars) and Model Hotloader's replaced `installation.lua`. Companion files were direct repository inputs, as designed. ReShade's licence is shipped in its payload; the sky texture credits name NASA, Night Sky HD LE, PraedythXVI and Era-7.

### Area F

- The snapshot and parity tools validate target roots and keep rollback records; their tests were part of the baseline. The installer refuses foreign or edited `winmm.dll` files and checks reparse points before touching the install. The new session Lua transport writes evidence under `out` and waits for a start marker.

### Area G

- The baseline ran all repository conventions, CTest and Python tests successfully. The synthetic proxy hosts exercise startup, runtime preloading, module dependencies and ReShade; the companion sky uses a LuaJIT mock. The new failure scenarios above are missing: edited dependency bytes at activation, same-size/same-time unpack cache, junction destinations, absolute manifest keys before validation, a main-ref push from a different worktree, concurrent lock creation, clearing weather, failed default-config copy, and a partial first Workshop mount. `test_companion_sky.py:446-447` currently expects zero writes after clearing weather without asserting the live values, so it passes with R3-009 present.

### Area H

- Script sidecars exist and repository link/convention checks pass. ADR 0033 says unpack checks every file, which R3-003 disproves for an existing output; ADR 0031 says the empty weather choice leaves settings to Remix, which R3-009 disproves mid-session. The installer sidecar states the bootstrap copy rollback but does not describe the partial `-DefaultConfig` failure in R3-012. Older ADR 0024/0026 source paths and add-on hooks are historical decisions superseded by ADR 0033 in the index, so they were treated as context.

## Coverage

| Area | Status | Scope checked |
|---|---|---|
| A | Reviewed | Entry hook; startup; activation; module hooks; ReShade; discovery/content policy; changed manifest, deployment and journal paths; parser limits. |
| B | Reviewed statically | Runtime sky patch, CPU/shader math, texture path/loading, bindings, argument layout and compiler-thread arithmetic. |
| C | Reviewed | Inputs, fingerprint/lock/hooks, build and CI flow, runtime build script, packagers and combiner. |
| D | Reviewed | Sky, model, weather table, menu, guide, guard, defaults and i18n. |
| E | Reviewed | All ten indexes with deep verification; packager inventories; shipped licences and credits. Vendored source behavior was not line-reviewed. |
| F | Reviewed | Changed PoC session and installer paths in depth; snapshot, parity and defaults tools statically for context. |
| G | Reviewed | Baseline, focused test matrix, mocks and failure coverage gaps. |
| H | Reviewed | Changed script sidecars and ADR 0020-0033 against the reviewed code; convention and link checks. |

### Project source and documentation files changed since R1

`Reviewed` means the relevant code and callers or decision claims were traced. `Partly reviewed` means selected paths, tests or claims were checked. The base fork snapshot (patch 0001) is explicitly out of scope.

| Area | File | Status |
|---|---|---|
| A | `loader/core/include/nl/activate.h` | Partly reviewed |
| A | `loader/core/include/nl/config.h` | Partly reviewed |
| A | `loader/core/include/nl/content.h` | Partly reviewed |
| A | `loader/core/include/nl/discovery.h` | Partly reviewed |
| A | `loader/core/include/nl/journal.h` | Partly reviewed |
| A | `loader/core/include/nl/manifest.h` | Partly reviewed |
| A | `loader/core/include/nl/reshade.h` | Partly reviewed |
| A | `loader/core/include/nl/session.h` | Partly reviewed |
| A | `loader/core/include/nl/startup.h` | Partly reviewed |
| A | `loader/core/include/nl/status.h` | Partly reviewed |
| A | `loader/core/src/activate.cpp` | Reviewed |
| A | `loader/core/src/config.cpp` | Partly reviewed |
| A | `loader/core/src/content.cpp` | Reviewed |
| A | `loader/core/src/deploy.cpp` | Partly reviewed |
| A | `loader/core/src/discovery.cpp` | Reviewed |
| A | `loader/core/src/journal.cpp` | Partly reviewed |
| A | `loader/core/src/manifest.cpp` | Reviewed |
| A | `loader/core/src/planner.cpp` | Partly reviewed |
| A | `loader/core/src/reshade.cpp` | Reviewed |
| A | `loader/core/src/session.cpp` | Partly reviewed |
| A | `loader/core/src/startup.cpp` | Reviewed |
| A | `loader/core/src/status.cpp` | Partly reviewed |
| A | `loader/proxy/modules.cpp` | Reviewed |
| A | `loader/proxy/modules.h` | Partly reviewed |
| A | `loader/proxy/runtime.cpp` | Reviewed |
| A | `loader/proxy/runtime.h` | Partly reviewed |
| A | `loader/proxy/startup.cpp` | Reviewed |
| B | `runtime/patches/0001-Snapshot-gmod-1.6.1-working-tree-during-the-remix-1..patch` | Not reviewed (excluded by brief) |
| B | `runtime/patches/0002-Translate-the-Remix-menus-zh-CN-zh-TW-ja-ko-fr-ru.patch` | Partly reviewed (context) |
| B | `runtime/patches/0003-i18n-the-translators-glossaries.patch` | Partly reviewed (context) |
| B | `runtime/patches/0004-Atmosphere-the-real-Moon-a-night-sky-image-lunar-and.patch` | Reviewed |
| C | `.github/workflows/build.yml` | Reviewed |
| C | `.github/workflows/package.yml` | Reviewed |
| C | `loader/cli/nlctl.cpp` | Partly reviewed |
| C | `runtime/base.json` | Reviewed |
| C | `runtime/build_runtime.ps1` | Reviewed |
| C | `tools/build_package.py` | Reviewed |
| C | `tools/check_repo.py` | Reviewed |
| C | `tools/companion_i18n.py` | Partly reviewed |
| C | `tools/inputs.py` | Reviewed |
| C | `tools/package_content.py` | Reviewed |
| C | `tools/package_fixes.py` | Reviewed |
| C | `tools/package_loader.py` | Partly reviewed |
| C | `tools/package_reshade.py` | Reviewed |
| C | `tools/package_workshop.py` | Reviewed |
| C | `tools/publish_workshop.py` | Reviewed |
| C | `tools/weather_presets.py` | Partly reviewed |
| C | `tools/workflow.ps1` | Reviewed |
| C | `tools/workshop.json` | Reviewed |
| D | `companion/i18n/fr.po` | Partly reviewed (syntax and placeholders tested) |
| D | `companion/i18n/ja.po` | Partly reviewed (syntax and placeholders tested) |
| D | `companion/i18n/ko.po` | Partly reviewed (syntax and placeholders tested) |
| D | `companion/i18n/nativeloader.pot` | Partly reviewed (syntax and placeholders tested) |
| D | `companion/i18n/ru.po` | Partly reviewed (syntax and placeholders tested) |
| D | `companion/i18n/zh-CN.po` | Partly reviewed (syntax and placeholders tested) |
| D | `companion/i18n/zh-TW.po` | Partly reviewed (syntax and placeholders tested) |
| D | `companion/nativeloader/lua/autorun/_nativeloader_guard.lua` | Reviewed |
| D | `companion/nativeloader/lua/autorun/client/nativeloader.lua` | Partly reviewed |
| D | `companion/nativeloader/lua/autorun/client/nativeloader_guide.lua` | Reviewed |
| D | `companion/nativeloader/lua/autorun/client/nativeloader_menu.lua` | Reviewed |
| D | `companion/nativeloader/lua/autorun/nativeloader_defaults.lua` | Reviewed |
| D | `companion/nativeloader/lua/autorun/nativeloader_i18n.lua` | Reviewed |
| D | `companion/nativeloader/lua/autorun/nativeloader_sky.lua` | Reviewed |
| D | `companion/nativeloader/lua/nativeloader/classic_defaults.lua` | Partly reviewed |
| D | `companion/nativeloader/lua/nativeloader/i18n.lua` | Reviewed |
| D | `companion/nativeloader/lua/nativeloader/sky_model.lua` | Reviewed |
| D | `companion/nativeloader/lua/nativeloader/weather_presets.lua` | Reviewed |
| E | `tools/sky/bake_nightsky.py` | Reviewed |
| E | `tools/sky/make_moon_textures.py` | Reviewed |
| E | `tools/sky/nif_read.py` | Reviewed |
| E | `tools/sky/nightsky_mapping.py` | Reviewed |
| F | `tools/classic_defaults.py` | Reviewed |
| F | `tools/install-loader.ps1` | Reviewed |
| F | `tools/poc_session.py` | Partly reviewed |
| F | `tools/remix_defaults.py` | Reviewed |
| G | `loader/proxy/tests/README.md` | Partly reviewed (executed; selected cases inspected) |
| G | `loader/proxy/tests/activation_integration.py` | Partly reviewed (executed; selected cases inspected) |
| G | `loader/proxy/tests/activation_integration.py.md` | Partly reviewed (executed; selected cases inspected) |
| G | `loader/proxy/tests/fixture_dep_module.cpp` | Partly reviewed (executed; selected cases inspected) |
| G | `loader/proxy/tests/fixture_dep_runtime.cpp` | Partly reviewed (executed; selected cases inspected) |
| G | `loader/proxy/tests/fixture_luashared.cpp` | Partly reviewed (executed; selected cases inspected) |
| G | `loader/proxy/tests/install_tests.ps1` | Partly reviewed (executed; selected cases inspected) |
| G | `loader/proxy/tests/install_tests.ps1.md` | Partly reviewed (executed; selected cases inspected) |
| G | `loader/proxy/tests/session_integration.py` | Partly reviewed (executed; selected cases inspected) |
| G | `loader/proxy/tests/session_integration.py.md` | Partly reviewed (executed; selected cases inspected) |
| G | `loader/proxy/tests/session_probe.cpp` | Partly reviewed (executed; selected cases inspected) |
| G | `loader/tests/README.md` | Partly reviewed (executed; selected cases inspected) |
| G | `loader/tests/deploy_faults.py` | Partly reviewed (executed; selected cases inspected) |
| G | `loader/tests/test_activate.cpp` | Partly reviewed (executed; selected cases inspected) |
| G | `loader/tests/test_config.cpp` | Partly reviewed (executed; selected cases inspected) |
| G | `loader/tests/test_content.cpp` | Partly reviewed (executed; selected cases inspected) |
| G | `loader/tests/test_dependencies.cpp` | Partly reviewed (executed; selected cases inspected) |
| G | `loader/tests/test_deploy.cpp` | Partly reviewed (executed; selected cases inspected) |
| G | `loader/tests/test_discovery.cpp` | Partly reviewed (executed; selected cases inspected) |
| G | `loader/tests/test_m5.cpp` | Partly reviewed (executed; selected cases inspected) |
| G | `loader/tests/test_manifest.cpp` | Partly reviewed (executed; selected cases inspected) |
| G | `loader/tests/test_planner.cpp` | Partly reviewed (executed; selected cases inspected) |
| G | `loader/tests/test_reshade.cpp` | Partly reviewed (executed; selected cases inspected) |
| G | `loader/tests/test_startup.cpp` | Partly reviewed (executed; selected cases inspected) |
| G | `tools/tests/test_classic_defaults.py` | Partly reviewed (executed; selected cases inspected) |
| G | `tools/tests/test_classic_defaults.py.md` | Partly reviewed (executed; selected cases inspected) |
| G | `tools/tests/test_companion.py` | Partly reviewed (executed; selected cases inspected) |
| G | `tools/tests/test_companion.py.md` | Partly reviewed (executed; selected cases inspected) |
| G | `tools/tests/test_companion_i18n.py` | Partly reviewed (executed; selected cases inspected) |
| G | `tools/tests/test_companion_i18n.py.md` | Partly reviewed (executed; selected cases inspected) |
| G | `tools/tests/test_companion_sky.py` | Partly reviewed (executed; selected cases inspected) |
| G | `tools/tests/test_companion_sky.py.md` | Partly reviewed (executed; selected cases inspected) |
| G | `tools/tests/test_inputs.py` | Partly reviewed (executed; selected cases inspected) |
| G | `tools/tests/test_inputs.py.md` | Partly reviewed (executed; selected cases inspected) |
| G | `tools/tests/test_package_content.py` | Partly reviewed (executed; selected cases inspected) |
| G | `tools/tests/test_package_content.py.md` | Partly reviewed (executed; selected cases inspected) |
| G | `tools/tests/test_package_fixes.py` | Partly reviewed (executed; selected cases inspected) |
| G | `tools/tests/test_package_loader.py` | Partly reviewed (executed; selected cases inspected) |
| G | `tools/tests/test_package_loader.py.md` | Partly reviewed (executed; selected cases inspected) |
| G | `tools/tests/test_package_reshade.py` | Partly reviewed (executed; selected cases inspected) |
| G | `tools/tests/test_package_reshade.py.md` | Partly reviewed (executed; selected cases inspected) |
| G | `tools/tests/test_package_runtime.py` | Partly reviewed (executed; selected cases inspected) |
| G | `tools/tests/test_package_workshop.py` | Partly reviewed (executed; selected cases inspected) |
| G | `tools/tests/test_package_workshop.py.md` | Partly reviewed (executed; selected cases inspected) |
| G | `tools/tests/test_poc_session.py` | Partly reviewed (executed; selected cases inspected) |
| G | `tools/tests/test_poc_session.py.md` | Partly reviewed (executed; selected cases inspected) |
| G | `tools/tests/test_publish_workshop.py` | Partly reviewed (executed; selected cases inspected) |
| G | `tools/tests/test_publish_workshop.py.md` | Partly reviewed (executed; selected cases inspected) |
| G | `tools/tests/test_remix_defaults.py` | Partly reviewed (executed; selected cases inspected) |
| G | `tools/tests/test_remix_defaults.py.md` | Partly reviewed (executed; selected cases inspected) |
| G | `tools/tests/test_weather_presets.py` | Partly reviewed (executed; selected cases inspected) |
| G | `tools/tests/test_weather_presets.py.md` | Partly reviewed (executed; selected cases inspected) |
| H | `.gitattributes` | Partly reviewed |
| H | `AGENTS.md` | Reviewed |
| H | `CHANGELOG.md` | Partly reviewed (links and relevant claims checked) |
| H | `companion/README.md` | Partly reviewed (links and relevant claims checked) |
| H | `companion/i18n/README.md` | Partly reviewed (syntax and placeholders tested) |
| H | `companion/nativeloader/lua/autorun/_nativeloader_guard.lua.md` | Partly reviewed (links and relevant claims checked) |
| H | `companion/nativeloader/lua/autorun/client/nativeloader.lua.md` | Partly reviewed (links and relevant claims checked) |
| H | `companion/nativeloader/lua/autorun/client/nativeloader_guide.lua.md` | Partly reviewed (links and relevant claims checked) |
| H | `companion/nativeloader/lua/autorun/client/nativeloader_menu.lua.md` | Partly reviewed (links and relevant claims checked) |
| H | `companion/nativeloader/lua/autorun/nativeloader_defaults.lua.md` | Partly reviewed (links and relevant claims checked) |
| H | `companion/nativeloader/lua/autorun/nativeloader_i18n.lua.md` | Partly reviewed (links and relevant claims checked) |
| H | `companion/nativeloader/lua/autorun/nativeloader_sky.lua.md` | Partly reviewed (links and relevant claims checked) |
| H | `companion/nativeloader/lua/nativeloader/classic_defaults.lua.md` | Partly reviewed (links and relevant claims checked) |
| H | `companion/nativeloader/lua/nativeloader/i18n.lua.md` | Partly reviewed (links and relevant claims checked) |
| H | `companion/nativeloader/lua/nativeloader/sky_model.lua.md` | Partly reviewed (links and relevant claims checked) |
| H | `companion/nativeloader/lua/nativeloader/weather_presets.lua.md` | Partly reviewed (links and relevant claims checked) |
| H | `dist/native-loader/config.json` | Partly reviewed |
| H | `docs/ARCHITECTURE.md` | Reviewed |
| H | `docs/COMPONENTS.md` | Partly reviewed |
| H | `docs/ENVIRONMENT.md` | Partly reviewed (links and relevant claims checked) |
| H | `docs/ON_DISK_LAYOUT.md` | Partly reviewed (links and relevant claims checked) |
| H | `docs/PACKAGE_FORMAT.md` | Reviewed |
| H | `docs/RESEARCH.md` | Partly reviewed |
| H | `docs/ROADMAP.md` | Partly reviewed (links and relevant claims checked) |
| H | `docs/TESTING.md` | Partly reviewed (links and relevant claims checked) |
| H | `docs/decisions/0012-distribution-route.md` | Partly reviewed (links and relevant claims checked) |
| H | `docs/decisions/0015-workshop-route-for-native-packages.md` | Partly reviewed (links and relevant claims checked) |
| H | `docs/decisions/0016-one-workshop-item-kept-current.md` | Partly reviewed (links and relevant claims checked) |
| H | `docs/decisions/0017-release-bundle-and-ci.md` | Partly reviewed (links and relevant claims checked) |
| H | `docs/decisions/0018-rtx-sessions-in-a-borderless-window.md` | Partly reviewed (links and relevant claims checked) |
| H | `docs/decisions/0019-agents-push-main-and-update-workshop.md` | Partly reviewed (links and relevant claims checked) |
| H | `docs/decisions/0020-classic-rtx-settings-as-defaults.md` | Reviewed (decision section checked) |
| H | `docs/decisions/0021-remix-defaults-in-one-low-layer.md` | Reviewed (decision section checked) |
| H | `docs/decisions/0022-companion-rtx-session-guard.md` | Reviewed (decision section checked) |
| H | `docs/decisions/0023-content-packages-and-modern-house-item.md` | Reviewed (decision section checked) |
| H | `docs/decisions/0024-bundled-addons-and-module-dependencies.md` | Reviewed (decision section checked) |
| H | `docs/decisions/0025-unsubscribe-removes-the-package.md` | Reviewed (decision section checked) |
| H | `docs/decisions/0026-addon-file-from-its-repository.md` | Reviewed (decision section checked) |
| H | `docs/decisions/0027-content-packages-from-any-subscription.md` | Reviewed (decision section checked) |
| H | `docs/decisions/0028-reshade-in-rtx-sessions.md` | Reviewed (decision section checked) |
| H | `docs/decisions/0029-companion-translations.md` | Reviewed (decision section checked) |
| H | `docs/decisions/0030-non-nvidia-gpus-and-late-runtime-dlls.md` | Reviewed (decision section checked) |
| H | `docs/decisions/0031-physical-sky-time-and-weather.md` | Reviewed (decision section checked) |
| H | `docs/decisions/0032-real-moon-stars-eclipses-and-fog-presets.md` | Reviewed (decision section checked) |
| H | `docs/decisions/0033-one-repository-package-inputs-in-git-lfs.md` | Reviewed (decision section checked) |
| H | `docs/decisions/README.md` | Partly reviewed (links and relevant claims checked) |
| H | `docs/handover/M6-report.md` | Partly reviewed (links and relevant claims checked) |
| H | `docs/handover/R1-triage.md` | Partly reviewed |
| H | `docs/handover/R3-codex-prompt.md` | Partly reviewed (links and relevant claims checked) |
| H | `docs/handover/R3-handover.md` | Reviewed |
| H | `docs/handover/README.md` | Partly reviewed (links and relevant claims checked) |
| H | `loader/cli/README.md` | Partly reviewed (links and relevant claims checked) |
| H | `loader/core/README.md` | Partly reviewed (links and relevant claims checked) |
| H | `loader/proxy/README.md` | Partly reviewed (links and relevant claims checked) |
| H | `runtime/README.md` | Reviewed |
| H | `runtime/build_runtime.ps1.md` | Partly reviewed (links and relevant claims checked) |
| H | `third_party/reshade/LICENSE.md` | Partly reviewed (links and relevant claims checked) |
| H | `third_party/reshade/README.md` | Partly reviewed (links and relevant claims checked) |
| H | `tools/build_package.py.md` | Partly reviewed (links and relevant claims checked) |
| H | `tools/check_repo.py.md` | Partly reviewed (links and relevant claims checked) |
| H | `tools/classic_defaults.py.md` | Partly reviewed (links and relevant claims checked) |
| H | `tools/companion_i18n.py.md` | Partly reviewed (links and relevant claims checked) |
| H | `tools/inputs.py.md` | Partly reviewed (links and relevant claims checked) |
| H | `tools/install-loader.ps1.md` | Partly reviewed (links and relevant claims checked) |
| H | `tools/package_content.py.md` | Partly reviewed (links and relevant claims checked) |
| H | `tools/package_fixes.py.md` | Partly reviewed (links and relevant claims checked) |
| H | `tools/package_loader.py.md` | Partly reviewed (links and relevant claims checked) |
| H | `tools/package_reshade.py.md` | Partly reviewed (links and relevant claims checked) |
| H | `tools/package_workshop.py.md` | Partly reviewed (links and relevant claims checked) |
| H | `tools/poc_session.py.md` | Partly reviewed (links and relevant claims checked) |
| H | `tools/publish_workshop.py.md` | Partly reviewed (links and relevant claims checked) |
| H | `tools/remix_defaults.py.md` | Partly reviewed (links and relevant claims checked) |
| H | `tools/sky/bake_nightsky.py.md` | Partly reviewed (links and relevant claims checked) |
| H | `tools/sky/make_moon_textures.py.md` | Partly reviewed (links and relevant claims checked) |
| H | `tools/sky/nif_read.py.md` | Partly reviewed (links and relevant claims checked) |
| H | `tools/sky/nightsky_mapping.py.md` | Partly reviewed (links and relevant claims checked) |
| H | `tools/weather_presets.py.md` | Partly reviewed (links and relevant claims checked) |
| H | `tools/workflow.ps1.md` | Partly reviewed (links and relevant claims checked) |

### Named unchanged context

| Area | File | Status |
|---|---|---|
| A | `loader/proxy/bootstrap.cpp` | Reviewed |
| A | `loader/proxy/activation.cpp` | Reviewed |
| A | `loader/core/src/gma.cpp` | Partly reviewed |
| A | `loader/core/src/lzma.cpp` | Partly reviewed |
| A | `loader/core/src/json.cpp` | Partly reviewed |
| A | `loader/core/src/vdf.cpp` | Partly reviewed |
| A | `loader/core/src/package.cpp` | Reviewed |
| F | `tools/field_snapshot.py` | Partly reviewed (unchanged since R1) |
| F | `tools/poc_parity.py` | Partly reviewed (unchanged since R1) |

### Package indexes

| Area | File | Status |
|---|---|---|
| E | `packages/advanced-bodygroup-tool/files.json` | Reviewed (deep verification and inventory comparison) |
| E | `packages/advanced-material-editor/files.json` | Reviewed (deep verification and inventory comparison) |
| E | `packages/character-motion-importer/files.json` | Reviewed (deep verification and inventory comparison) |
| E | `packages/emissives/files.json` | Reviewed (deep verification and inventory comparison) |
| E | `packages/fixes/files.json` | Reviewed (deep verification and inventory comparison) |
| E | `packages/model-hotloader/files.json` | Reviewed (deep verification and inventory comparison) |
| E | `packages/procedural-bodygroup-destruction/files.json` | Reviewed (deep verification and inventory comparison) |
| E | `packages/remove-halo/files.json` | Reviewed (deep verification and inventory comparison) |
| E | `packages/reshade/files.json` | Reviewed (deep verification and inventory comparison) |
| E | `packages/runtime/files.json` | Reviewed (deep verification and inventory comparison) |

<details><summary>Vendored package source files (integrity checked, behavior not line-reviewed)</summary>

Area E in the brief calls for index, inventory and licence checks. The vendored source files below passed those integrity checks; their code behavior was outside that area’s specified review.

| File | Status |
|---|---|
| `packages/advanced-bodygroup-tool/!advanced_bodygroup_tool/lua/advanced_bodygroup_tool/cl_i18n.lua` | Not reviewed (vendored behavior) |
| `packages/advanced-bodygroup-tool/!advanced_bodygroup_tool/lua/advanced_bodygroup_tool/cl_uv_hide.lua` | Not reviewed (vendored behavior) |
| `packages/advanced-bodygroup-tool/!advanced_bodygroup_tool/lua/advanced_bodygroup_tool/cl_vertex_keep_editor.lua` | Not reviewed (vendored behavior) |
| `packages/advanced-bodygroup-tool/!advanced_bodygroup_tool/lua/autorun/advanced_bodygroup_tool.lua` | Not reviewed (vendored behavior) |
| `packages/advanced-bodygroup-tool/!advanced_bodygroup_tool/lua/weapons/gmod_tool/stools/advanced_bodygroup.lua` | Not reviewed (vendored behavior) |
| `packages/advanced-material-editor/!advanced_material_editor/lua/advmat/cl_05_i18n.lua` | Not reviewed (vendored behavior) |
| `packages/advanced-material-editor/!advanced_material_editor/lua/advmat/cl_19_help_i18n.lua` | Not reviewed (vendored behavior) |
| `packages/advanced-material-editor/!advanced_material_editor/lua/advmat/cl_20_help.lua` | Not reviewed (vendored behavior) |
| `packages/advanced-material-editor/!advanced_material_editor/lua/advmat/cl_23_backend.lua` | Not reviewed (vendored behavior) |
| `packages/advanced-material-editor/!advanced_material_editor/lua/advmat/cl_27_rtx_bridge.lua` | Not reviewed (vendored behavior) |
| `packages/advanced-material-editor/!advanced_material_editor/lua/advmat/cl_28_rtx_enhance.lua` | Not reviewed (vendored behavior) |
| `packages/advanced-material-editor/!advanced_material_editor/lua/advmat/cl_29_rtx_normals.lua` | Not reviewed (vendored behavior) |
| `packages/advanced-material-editor/!advanced_material_editor/lua/advmat/cl_30_theme.lua` | Not reviewed (vendored behavior) |
| `packages/advanced-material-editor/!advanced_material_editor/lua/advmat/cl_31_windowux.lua` | Not reviewed (vendored behavior) |
| `packages/advanced-material-editor/!advanced_material_editor/lua/advmat/cl_40_store.lua` | Not reviewed (vendored behavior) |
| `packages/advanced-material-editor/!advanced_material_editor/lua/advmat/cl_41_rtx_store.lua` | Not reviewed (vendored behavior) |
| `packages/advanced-material-editor/!advanced_material_editor/lua/advmat/cl_50_apply.lua` | Not reviewed (vendored behavior) |
| `packages/advanced-material-editor/!advanced_material_editor/lua/advmat/cl_55_normalgen.lua` | Not reviewed (vendored behavior) |
| `packages/advanced-material-editor/!advanced_material_editor/lua/advmat/cl_56_texops.lua` | Not reviewed (vendored behavior) |
| `packages/advanced-material-editor/!advanced_material_editor/lua/advmat/cl_57_surfacegen.lua` | Not reviewed (vendored behavior) |
| `packages/advanced-material-editor/!advanced_material_editor/lua/advmat/cl_58_meshuv.lua` | Not reviewed (vendored behavior) |
| `packages/advanced-material-editor/!advanced_material_editor/lua/advmat/cl_59_assets.lua` | Not reviewed (vendored behavior) |
| `packages/advanced-material-editor/!advanced_material_editor/lua/advmat/cl_60_texpicker.lua` | Not reviewed (vendored behavior) |
| `packages/advanced-material-editor/!advanced_material_editor/lua/advmat/cl_61_import.lua` | Not reviewed (vendored behavior) |
| `packages/advanced-material-editor/!advanced_material_editor/lua/advmat/cl_65_rows.lua` | Not reviewed (vendored behavior) |
| `packages/advanced-material-editor/!advanced_material_editor/lua/advmat/cl_67_gendialog.lua` | Not reviewed (vendored behavior) |
| `packages/advanced-material-editor/!advanced_material_editor/lua/advmat/cl_68_surfacedialog.lua` | Not reviewed (vendored behavior) |
| `packages/advanced-material-editor/!advanced_material_editor/lua/advmat/cl_70_ui.lua` | Not reviewed (vendored behavior) |
| `packages/advanced-material-editor/!advanced_material_editor/lua/advmat/cl_71_rtx_source.lua` | Not reviewed (vendored behavior) |
| `packages/advanced-material-editor/!advanced_material_editor/lua/advmat/cl_72_canvas.lua` | Not reviewed (vendored behavior) |
| `packages/advanced-material-editor/!advanced_material_editor/lua/advmat/cl_73_modelview.lua` | Not reviewed (vendored behavior) |
| `packages/advanced-material-editor/!advanced_material_editor/lua/advmat/cl_74_texeditor.lua` | Not reviewed (vendored behavior) |
| `packages/advanced-material-editor/!advanced_material_editor/lua/advmat/cl_75_rtx_nodes.lua` | Not reviewed (vendored behavior) |
| `packages/advanced-material-editor/!advanced_material_editor/lua/advmat/cl_76_rtx_editor.lua` | Not reviewed (vendored behavior) |
| `packages/advanced-material-editor/!advanced_material_editor/lua/advmat/cl_78_vmtexport.lua` | Not reviewed (vendored behavior) |
| `packages/advanced-material-editor/!advanced_material_editor/lua/advmat/cl_80_browser.lua` | Not reviewed (vendored behavior) |
| `packages/advanced-material-editor/!advanced_material_editor/lua/advmat/cl_88_dispatch.lua` | Not reviewed (vendored behavior) |
| `packages/advanced-material-editor/!advanced_material_editor/lua/advmat/cl_90_probe.lua` | Not reviewed (vendored behavior) |
| `packages/advanced-material-editor/!advanced_material_editor/lua/advmat/sh_00_config.lua` | Not reviewed (vendored behavior) |
| `packages/advanced-material-editor/!advanced_material_editor/lua/advmat/sh_10_util.lua` | Not reviewed (vendored behavior) |
| `packages/advanced-material-editor/!advanced_material_editor/lua/advmat/sh_15_mmd.lua` | Not reviewed (vendored behavior) |
| `packages/advanced-material-editor/!advanced_material_editor/lua/advmat/sh_20_net.lua` | Not reviewed (vendored behavior) |
| `packages/advanced-material-editor/!advanced_material_editor/lua/advmat/sh_25_vmt.lua` | Not reviewed (vendored behavior) |
| `packages/advanced-material-editor/!advanced_material_editor/lua/advmat/sh_30_shaderdb.lua` | Not reviewed (vendored behavior) |
| `packages/advanced-material-editor/!advanced_material_editor/lua/advmat/sh_31_shaderdb_ext.lua` | Not reviewed (vendored behavior) |
| `packages/advanced-material-editor/!advanced_material_editor/lua/advmat/sh_35_matname.lua` | Not reviewed (vendored behavior) |
| `packages/advanced-material-editor/!advanced_material_editor/lua/advmat/sh_36_rtx_schema.lua` | Not reviewed (vendored behavior) |
| `packages/advanced-material-editor/!advanced_material_editor/lua/advmat/sh_40_gen.lua` | Not reviewed (vendored behavior) |
| `packages/advanced-material-editor/!advanced_material_editor/lua/advmat/sh_41_sel.lua` | Not reviewed (vendored behavior) |
| `packages/advanced-material-editor/!advanced_material_editor/lua/advmat/sh_42_gen_normal.lua` | Not reviewed (vendored behavior) |
| `packages/advanced-material-editor/!advanced_material_editor/lua/advmat/sh_43_texedit.lua` | Not reviewed (vendored behavior) |
| `packages/advanced-material-editor/!advanced_material_editor/lua/advmat/sh_44_gen_surface.lua` | Not reviewed (vendored behavior) |
| `packages/advanced-material-editor/!advanced_material_editor/lua/advmat/sh_45_assets.lua` | Not reviewed (vendored behavior) |
| `packages/advanced-material-editor/!advanced_material_editor/lua/advmat/sh_50_finalise.lua` | Not reviewed (vendored behavior) |
| `packages/advanced-material-editor/!advanced_material_editor/lua/advmat/sv_29_assets.lua` | Not reviewed (vendored behavior) |
| `packages/advanced-material-editor/!advanced_material_editor/lua/advmat/sv_30_store.lua` | Not reviewed (vendored behavior) |
| `packages/advanced-material-editor/!advanced_material_editor/lua/advmat/sv_31_rtx_store.lua` | Not reviewed (vendored behavior) |
| `packages/advanced-material-editor/!advanced_material_editor/lua/advmat/sv_32_rtx_tool.lua` | Not reviewed (vendored behavior) |
| `packages/advanced-material-editor/!advanced_material_editor/lua/advmat/sv_40_apply.lua` | Not reviewed (vendored behavior) |
| `packages/advanced-material-editor/!advanced_material_editor/lua/autorun/advmat_loader.lua` | Not reviewed (vendored behavior) |
| `packages/advanced-material-editor/!advanced_material_editor/lua/weapons/gmod_tool/stools/advmateditor.lua` | Not reviewed (vendored behavior) |
| `packages/character-motion-importer/mmd_vmd_npc/lua/autorun/mmd_vmd_npc.lua` | Not reviewed (vendored behavior) |
| `packages/character-motion-importer/mmd_vmd_npc/lua/mmd_vmd_npc/cl_camera.lua` | Not reviewed (vendored behavior) |
| `packages/character-motion-importer/mmd_vmd_npc/lua/mmd_vmd_npc/cl_flashlight.lua` | Not reviewed (vendored behavior) |
| `packages/character-motion-importer/mmd_vmd_npc/lua/mmd_vmd_npc/cl_menu.lua` | Not reviewed (vendored behavior) |
| `packages/character-motion-importer/mmd_vmd_npc/lua/mmd_vmd_npc/cl_radial.lua` | Not reviewed (vendored behavior) |
| `packages/character-motion-importer/mmd_vmd_npc/lua/mmd_vmd_npc/sh_core.lua` | Not reviewed (vendored behavior) |
| `packages/character-motion-importer/mmd_vmd_npc/lua/mmd_vmd_npc/sv_cache.lua` | Not reviewed (vendored behavior) |
| `packages/character-motion-importer/mmd_vmd_npc/lua/mmd_vmd_npc/sv_commands.lua` | Not reviewed (vendored behavior) |
| `packages/character-motion-importer/mmd_vmd_npc/lua/weapons/gmod_tool/stools/mmd_vmd_npc.lua` | Not reviewed (vendored behavior) |
| `packages/fixes/garrysmod/garrysmod/addons/GMod-Seamless-Portals-Remix/lua/autorun/client/cl_remix_portals.lua` | Not reviewed (vendored behavior) |
| `packages/fixes/garrysmod/garrysmod/addons/GMod-Seamless-Portals-Remix/lua/autorun/client/cl_render_core.lua` | Not reviewed (vendored behavior) |
| `packages/fixes/garrysmod/garrysmod/addons/GMod-Seamless-Portals-Remix/lua/autorun/server/sv_portals_pvs.lua` | Not reviewed (vendored behavior) |
| `packages/fixes/garrysmod/garrysmod/addons/GMod-Seamless-Portals-Remix/lua/autorun/server/sv_prop_teleport.lua` | Not reviewed (vendored behavior) |
| `packages/fixes/garrysmod/garrysmod/addons/GMod-Seamless-Portals-Remix/lua/autorun/sh_detours.lua` | Not reviewed (vendored behavior) |
| `packages/fixes/garrysmod/garrysmod/addons/GMod-Seamless-Portals-Remix/lua/autorun/sh_player_teleport.lua` | Not reviewed (vendored behavior) |
| `packages/fixes/garrysmod/garrysmod/addons/GMod-Seamless-Portals-Remix/lua/entities/seamless_portal/cl_init.lua` | Not reviewed (vendored behavior) |
| `packages/fixes/garrysmod/garrysmod/addons/GMod-Seamless-Portals-Remix/lua/entities/seamless_portal/init.lua` | Not reviewed (vendored behavior) |
| `packages/fixes/garrysmod/garrysmod/addons/GMod-Seamless-Portals-Remix/lua/entities/seamless_portal/sh_init.lua` | Not reviewed (vendored behavior) |
| `packages/fixes/garrysmod/garrysmod/addons/GMod-Seamless-Portals-Remix/lua/weapons/gmod_tool/stools/portal_creator_tool.lua` | Not reviewed (vendored behavior) |
| `packages/fixes/garrysmod/garrysmod/addons/GMod-Seamless-Portals-Remix/lua/weapons/gmod_tool/stools/portal_fitter_tool.lua` | Not reviewed (vendored behavior) |
| `packages/fixes/garrysmod/garrysmod/addons/GMod-Seamless-Portals-Remix/lua/weapons/gmod_tool/stools/portal_resizer_tool.lua` | Not reviewed (vendored behavior) |
| `packages/fixes/garrysmod/garrysmod/addons/GMod-Seamless-Portals-Remix/lua/weapons/portal_gun.lua` | Not reviewed (vendored behavior) |
| `packages/fixes/garrysmod/garrysmod/addons/Glass-Rewrite-Remix/lua/autorun/client/glass_spawnmenu.lua` | Not reviewed (vendored behavior) |
| `packages/fixes/garrysmod/garrysmod/addons/Glass-Rewrite-Remix/lua/autorun/networking.lua` | Not reviewed (vendored behavior) |
| `packages/fixes/garrysmod/garrysmod/addons/Glass-Rewrite-Remix/lua/entities/procedural_shard.lua` | Not reviewed (vendored behavior) |
| `packages/fixes/garrysmod/garrysmod/addons/Glass-Rewrite-Remix/lua/entities/procedural_shard_init.lua` | Not reviewed (vendored behavior) |
| `packages/fixes/garrysmod/garrysmod/addons/Glass-Rewrite-Remix/lua/weapons/gmod_tool/stools/procedural_glass_tool.lua` | Not reviewed (vendored behavior) |
| `packages/fixes/garrysmod/garrysmod/addons/Glass-Rewrite-Remix/lua/world_functions.lua` | Not reviewed (vendored behavior) |
| `packages/fixes/garrysmod/garrysmod/addons/gm_poolrooms_rtx/lua/autorun/poolrooms_rtx.lua` | Not reviewed (vendored behavior) |
| `packages/fixes/garrysmod/garrysmod/addons/gm_poolrooms_rtx/lua/poolrooms_rtx/cl_lights_data.lua` | Not reviewed (vendored behavior) |
| `packages/fixes/garrysmod/garrysmod/addons/gm_poolrooms_rtx/lua/poolrooms_rtx/cl_main.lua` | Not reviewed (vendored behavior) |
| `packages/fixes/garrysmod/garrysmod/addons/gm_poolrooms_rtx/lua/poolrooms_rtx/sh_config.lua` | Not reviewed (vendored behavior) |
| `packages/fixes/garrysmod/garrysmod/addons/mount-hl2rtx/lua/autorun/client/hl2rtx_model_compat_viewmodels.lua` | Not reviewed (vendored behavior) |
| `packages/fixes/garrysmod/garrysmod/addons/mount-hl2rtx/lua/autorun/server/hl2rtx_model_compat.lua` | Not reviewed (vendored behavior) |
| `packages/fixes/garrysmod/garrysmod/addons/niknaks/lua/includes/modules/niknaks.lua` | Not reviewed (vendored behavior) |
| `packages/fixes/garrysmod/garrysmod/addons/niknaks/lua/niknaks/framework/sh_localbsp.lua` | Not reviewed (vendored behavior) |
| `packages/fixes/garrysmod/garrysmod/addons/niknaks/lua/niknaks/modules/sh_bignumber.lua` | Not reviewed (vendored behavior) |
| `packages/fixes/garrysmod/garrysmod/addons/niknaks/lua/niknaks/modules/sh_bitbuffer.lua` | Not reviewed (vendored behavior) |
| `packages/fixes/garrysmod/garrysmod/addons/niknaks/lua/niknaks/modules/sh_bsp_brushes.lua` | Not reviewed (vendored behavior) |
| `packages/fixes/garrysmod/garrysmod/addons/niknaks/lua/niknaks/modules/sh_bsp_entities.lua` | Not reviewed (vendored behavior) |
| `packages/fixes/garrysmod/garrysmod/addons/niknaks/lua/niknaks/modules/sh_bsp_faces.lua` | Not reviewed (vendored behavior) |
| `packages/fixes/garrysmod/garrysmod/addons/niknaks/lua/niknaks/modules/sh_bsp_leafs.lua` | Not reviewed (vendored behavior) |
| `packages/fixes/garrysmod/garrysmod/addons/niknaks/lua/niknaks/modules/sh_bsp_module.lua` | Not reviewed (vendored behavior) |
| `packages/fixes/garrysmod/garrysmod/addons/niknaks/lua/niknaks/modules/sh_bsp_pvspas.lua` | Not reviewed (vendored behavior) |
| `packages/fixes/garrysmod/garrysmod/addons/niknaks/lua/niknaks/modules/sh_bsp_staticprops.lua` | Not reviewed (vendored behavior) |
| `packages/fixes/garrysmod/garrysmod/addons/niknaks/lua/niknaks/modules/sh_bsp_trace.lua` | Not reviewed (vendored behavior) |
| `packages/fixes/garrysmod/garrysmod/addons/niknaks/lua/niknaks/modules/sh_bsp_worldlights.lua` | Not reviewed (vendored behavior) |
| `packages/fixes/garrysmod/garrysmod/addons/niknaks/lua/niknaks/modules/sh_color_extended.lua` | Not reviewed (vendored behavior) |
| `packages/fixes/garrysmod/garrysmod/addons/niknaks/lua/niknaks/modules/sh_datapackage.lua` | Not reviewed (vendored behavior) |
| `packages/fixes/garrysmod/garrysmod/addons/niknaks/lua/niknaks/modules/sh_datetime.lua` | Not reviewed (vendored behavior) |
| `packages/fixes/garrysmod/garrysmod/addons/niknaks/lua/niknaks/modules/sh_enums.lua` | Not reviewed (vendored behavior) |
| `packages/fixes/garrysmod/garrysmod/addons/niknaks/lua/niknaks/modules/sh_file_extended.lua` | Not reviewed (vendored behavior) |
| `packages/fixes/garrysmod/garrysmod/addons/niknaks/lua/niknaks/modules/sh_hooks.lua` | Not reviewed (vendored behavior) |
| `packages/fixes/garrysmod/garrysmod/addons/niknaks/lua/niknaks/modules/sh_linq_module.lua` | Not reviewed (vendored behavior) |
| `packages/fixes/garrysmod/garrysmod/addons/niknaks/lua/niknaks/modules/sh_model_extended.lua` | Not reviewed (vendored behavior) |
| `packages/fixes/garrysmod/garrysmod/addons/niknaks/lua/niknaks/modules/sh_randomizer.lua` | Not reviewed (vendored behavior) |
| `packages/fixes/garrysmod/garrysmod/addons/niknaks/lua/niknaks/modules/sh_sound_module.lua` | Not reviewed (vendored behavior) |
| `packages/fixes/garrysmod/garrysmod/addons/niknaks/lua/niknaks/modules/sh_timedelta.lua` | Not reviewed (vendored behavior) |
| `packages/fixes/garrysmod/garrysmod/addons/niknaks/lua/niknaks/modules/sh_util_extended.lua` | Not reviewed (vendored behavior) |
| `packages/fixes/garrysmod/garrysmod/addons/niknaks/lua/niknaks/submodules/ai/sh_file.lua` | Not reviewed (vendored behavior) |
| `packages/fixes/garrysmod/garrysmod/addons/niknaks/lua/niknaks/submodules/ai/sh_map.lua` | Not reviewed (vendored behavior) |
| `packages/fixes/garrysmod/garrysmod/addons/niknaks/lua/niknaks/submodules/ai/sh_node.lua` | Not reviewed (vendored behavior) |
| `packages/fixes/garrysmod/garrysmod/addons/niknaks/lua/niknaks/submodules/ai/sh_pathfinder.lua` | Not reviewed (vendored behavior) |
| `packages/fixes/garrysmod/garrysmod/addons/niknaks/lua/niknaks/submodules/sh_submodules.lua` | Not reviewed (vendored behavior) |
| `packages/fixes/garrysmod/garrysmod/addons/niknaks/lua/unittest/niknaks/bignumber.lua` | Not reviewed (vendored behavior) |
| `packages/fixes/garrysmod/garrysmod/addons/niknaks/lua/unittest/niknaks/bitbuffer.lua` | Not reviewed (vendored behavior) |
| `packages/fixes/garrysmod/garrysmod/addons/niknaks/lua/unittest/niknaks/bsp.lua` | Not reviewed (vendored behavior) |
| `packages/fixes/garrysmod/garrysmod/addons/niknaks/lua/unittest/niknaks/color.lua` | Not reviewed (vendored behavior) |
| `packages/fixes/garrysmod/garrysmod/addons/niknaks/lua/unittest/niknaks/datetime.lua` | Not reviewed (vendored behavior) |
| `packages/fixes/garrysmod/garrysmod/addons/niknaks/lua/unittest/niknaks/gunit_emmy.lua` | Not reviewed (vendored behavior) |
| `packages/fixes/garrysmod/garrysmod/addons/niknaks/lua/unittest/niknaks/linq.lua` | Not reviewed (vendored behavior) |
| `packages/fixes/garrysmod/garrysmod/addons/niknaks/lua/unittest/niknaks/main.lua` | Not reviewed (vendored behavior) |
| `packages/fixes/garrysmod/garrysmod/addons/niknaks/lua/unittest/niknaks/timedelta.lua` | Not reviewed (vendored behavior) |
| `packages/fixes/garrysmod/garrysmod/addons/remixbinary/lua/autorun/cl_rtx.lua` | Not reviewed (vendored behavior) |
| `packages/fixes/garrysmod/garrysmod/addons/remixbinary/lua/autorun/matdebug.lua` | Not reviewed (vendored behavior) |
| `packages/fixes/garrysmod/garrysmod/addons/remixbinary/lua/autorun/sh_rtx.lua` | Not reviewed (vendored behavior) |
| `packages/fixes/garrysmod/garrysmod/addons/remixbinary/lua/autorun/sv_rtx.lua` | Not reviewed (vendored behavior) |
| `packages/fixes/garrysmod/garrysmod/addons/remixbinary/lua/autorun/tmc.lua` | Not reviewed (vendored behavior) |
| `packages/fixes/garrysmod/garrysmod/addons/remixbinary/lua/entities/gmod_lamp.lua` | Not reviewed (vendored behavior) |
| `packages/fixes/garrysmod/garrysmod/addons/remixbinary/lua/entities/gmod_light.lua` | Not reviewed (vendored behavior) |
| `packages/fixes/garrysmod/garrysmod/addons/remixbinary/lua/entities/remix_rt_light/cl_init.lua` | Not reviewed (vendored behavior) |
| `packages/fixes/garrysmod/garrysmod/addons/remixbinary/lua/entities/remix_rt_light/init.lua` | Not reviewed (vendored behavior) |
| `packages/fixes/garrysmod/garrysmod/addons/remixbinary/lua/entities/remix_rt_light/shared.lua` | Not reviewed (vendored behavior) |
| `packages/fixes/garrysmod/garrysmod/addons/remixbinary/lua/entities/remix_sky_editor/cl_init.lua` | Not reviewed (vendored behavior) |
| `packages/fixes/garrysmod/garrysmod/addons/remixbinary/lua/entities/remix_sky_editor/init.lua` | Not reviewed (vendored behavior) |
| `packages/fixes/garrysmod/garrysmod/addons/remixbinary/lua/entities/remix_sky_editor/shared.lua` | Not reviewed (vendored behavior) |
| `packages/fixes/garrysmod/garrysmod/addons/remixbinary/lua/entities/rtx_pseudoplayer.lua` | Not reviewed (vendored behavior) |
| `packages/fixes/garrysmod/garrysmod/addons/remixbinary/lua/entities/rtx_pseudoweapon.lua` | Not reviewed (vendored behavior) |
| `packages/fixes/garrysmod/garrysmod/addons/remixbinary/lua/patcher/addons/cl_mwbase.lua` | Not reviewed (vendored behavior) |
| `packages/fixes/garrysmod/garrysmod/addons/remixbinary/lua/patcher/cl_init.lua` | Not reviewed (vendored behavior) |
| `packages/fixes/garrysmod/garrysmod/addons/remixbinary/lua/patcher/cl_intercepts.lua` | Not reviewed (vendored behavior) |
| `packages/fixes/garrysmod/garrysmod/addons/remixbinary/lua/patcher/sh_core.lua` | Not reviewed (vendored behavior) |
| `packages/fixes/garrysmod/garrysmod/addons/remixbinary/lua/patcher/tests/cl_mwbase_dependency_tests.lua` | Not reviewed (vendored behavior) |
| `packages/fixes/garrysmod/garrysmod/addons/remixbinary/lua/patcher/tests/cl_patcher_core_tests.lua` | Not reviewed (vendored behavior) |
| `packages/fixes/garrysmod/garrysmod/addons/remixbinary/lua/patcher/tests/cl_patcher_intercepts_tests.lua` | Not reviewed (vendored behavior) |
| `packages/fixes/garrysmod/garrysmod/addons/remixbinary/lua/patcher/tests/cl_patcher_loader_tests.lua` | Not reviewed (vendored behavior) |
| `packages/fixes/garrysmod/garrysmod/addons/remixbinary/lua/remixlua/cl/cl_fix_bft_materials.lua` | Not reviewed (vendored behavior) |
| `packages/fixes/garrysmod/garrysmod/addons/remixbinary/lua/remixlua/cl/cl_fix_pbr_materials.lua` | Not reviewed (vendored behavior) |
| `packages/fixes/garrysmod/garrysmod/addons/remixbinary/lua/remixlua/cl/cl_fix_refract_materials.lua` | Not reviewed (vendored behavior) |
| `packages/fixes/garrysmod/garrysmod/addons/remixbinary/lua/remixlua/cl/cl_fix_solid_color_materials.lua` | Not reviewed (vendored behavior) |
| `packages/fixes/garrysmod/garrysmod/addons/remixbinary/lua/remixlua/cl/cl_map_fixes.lua` | Not reviewed (vendored behavior) |
| `packages/fixes/garrysmod/garrysmod/addons/remixbinary/lua/remixlua/cl/cl_map_markers.lua` | Not reviewed (vendored behavior) |
| `packages/fixes/garrysmod/garrysmod/addons/remixbinary/lua/remixlua/cl/cl_material_inspector.lua` | Not reviewed (vendored behavior) |
| `packages/fixes/garrysmod/garrysmod/addons/remixbinary/lua/remixlua/cl/cl_material_pipeline.lua` | Not reviewed (vendored behavior) |
| `packages/fixes/garrysmod/garrysmod/addons/remixbinary/lua/remixlua/cl/cl_nonapi_flashlight.lua` | Not reviewed (vendored behavior) |
| `packages/fixes/garrysmod/garrysmod/addons/remixbinary/lua/remixlua/cl/cl_remove_detail_textures.lua` | Not reviewed (vendored behavior) |
| `packages/fixes/garrysmod/garrysmod/addons/remixbinary/lua/remixlua/cl/cl_rtx_light_updater.lua` | Not reviewed (vendored behavior) |
| `packages/fixes/garrysmod/garrysmod/addons/remixbinary/lua/remixlua/cl/cl_rtx_material_fixer.lua` | Not reviewed (vendored behavior) |
| `packages/fixes/garrysmod/garrysmod/addons/remixbinary/lua/remixlua/cl/cl_rtx_misc.lua` | Not reviewed (vendored behavior) |
| `packages/fixes/garrysmod/garrysmod/addons/remixbinary/lua/remixlua/cl/cl_rtx_settings.lua` | Not reviewed (vendored behavior) |
| `packages/fixes/garrysmod/garrysmod/addons/remixbinary/lua/remixlua/cl/cl_rtx_topbr_conversion.lua` | Not reviewed (vendored behavior) |
| `packages/fixes/garrysmod/garrysmod/addons/remixbinary/lua/remixlua/cl/customrender/cl_2d_skybox_renderer.lua` | Not reviewed (vendored behavior) |
| `packages/fixes/garrysmod/garrysmod/addons/remixbinary/lua/remixlua/cl/customrender/cl_build_progress.lua` | Not reviewed (vendored behavior) |
| `packages/fixes/garrysmod/garrysmod/addons/remixbinary/lua/remixlua/cl/customrender/cl_displacement_renderer.lua` | Not reviewed (vendored behavior) |
| `packages/fixes/garrysmod/garrysmod/addons/remixbinary/lua/remixlua/cl/customrender/cl_rtx_meshed_world_renderer.lua` | Not reviewed (vendored behavior) |
| `packages/fixes/garrysmod/garrysmod/addons/remixbinary/lua/remixlua/cl/customrender/cl_rtx_skybox_boundary_renderer.lua` | Not reviewed (vendored behavior) |
| `packages/fixes/garrysmod/garrysmod/addons/remixbinary/lua/remixlua/cl/customrender/cl_static_prop_renderer.lua` | Not reviewed (vendored behavior) |
| `packages/fixes/garrysmod/garrysmod/addons/remixbinary/lua/remixlua/cl/customrender/render_core.lua` | Not reviewed (vendored behavior) |
| `packages/fixes/garrysmod/garrysmod/addons/remixbinary/lua/remixlua/cl/remixapi/cl_physgun_color_sync.lua` | Not reviewed (vendored behavior) |
| `packages/fixes/garrysmod/garrysmod/addons/remixbinary/lua/remixlua/cl/remixapi/cl_remix_category_0_manager.lua` | Not reviewed (vendored behavior) |
| `packages/fixes/garrysmod/garrysmod/addons/remixbinary/lua/remixlua/cl/remixapi/cl_remix_category_1_pseudoplayer.lua` | Not reviewed (vendored behavior) |
| `packages/fixes/garrysmod/garrysmod/addons/remixbinary/lua/remixlua/cl/remixapi/cl_remix_category_debug.lua` | Not reviewed (vendored behavior) |
| `packages/fixes/garrysmod/garrysmod/addons/remixbinary/lua/remixlua/cl/remixapi/cl_remix_flashlight.lua` | Not reviewed (vendored behavior) |
| `packages/fixes/garrysmod/garrysmod/addons/remixbinary/lua/remixlua/cl/remixapi/cl_remix_light_cmd.lua` | Not reviewed (vendored behavior) |
| `packages/fixes/garrysmod/garrysmod/addons/remixbinary/lua/remixlua/cl/remixapi/cl_remix_map_configs.lua` | Not reviewed (vendored behavior) |
| `packages/fixes/garrysmod/garrysmod/addons/remixbinary/lua/remixlua/cl/remixapi/debug_hash_hud.lua` | Not reviewed (vendored behavior) |
| `packages/fixes/garrysmod/garrysmod/addons/remixbinary/lua/remixlua/cl/remixapi/rtx_hash_lookup.lua` | Not reviewed (vendored behavior) |
| `packages/fixes/garrysmod/garrysmod/addons/remixbinary/lua/remixlua/cl/remixapi/wrappers/cl_remix_api_map_lights.lua` | Not reviewed (vendored behavior) |
| `packages/fixes/garrysmod/garrysmod/addons/remixbinary/lua/remixlua/cl/remixapi/wrappers/cl_remix_api_map_lights_menu.lua` | Not reviewed (vendored behavior) |
| `packages/fixes/garrysmod/garrysmod/addons/remixbinary/lua/remixlua/cl/remixapi/wrappers/cl_remix_dynamiclight_wrapper.lua` | Not reviewed (vendored behavior) |
| `packages/fixes/garrysmod/garrysmod/addons/remixbinary/lua/remixlua/cl/remixapi/wrappers/cl_remix_dynamiclight_wrapper_menu.lua` | Not reviewed (vendored behavior) |
| `packages/fixes/garrysmod/garrysmod/addons/remixbinary/lua/remixlua/cl/remixapi/wrappers/cl_remix_light_wrapper.lua` | Not reviewed (vendored behavior) |
| `packages/fixes/garrysmod/garrysmod/addons/remixbinary/lua/remixlua/cl/remixapi/wrappers/cl_remix_light_wrapper_menu.lua` | Not reviewed (vendored behavior) |
| `packages/fixes/garrysmod/garrysmod/addons/remixbinary/lua/remixlua/cl/remixapi/wrappers/cl_remix_maplight_animator.lua` | Not reviewed (vendored behavior) |
| `packages/fixes/garrysmod/garrysmod/addons/remixbinary/lua/remixlua/cl/remixapi/wrappers/cl_remix_projectedtexture_wrapper.lua` | Not reviewed (vendored behavior) |
| `packages/fixes/garrysmod/garrysmod/addons/remixbinary/lua/remixlua/cl/remixapi/wrappers/cl_remix_projectedtexture_wrapper_menu.lua` | Not reviewed (vendored behavior) |
| `packages/fixes/garrysmod/garrysmod/addons/remixbinary/lua/remixlua/sh/sh_flashlight_override.lua` | Not reviewed (vendored behavior) |
| `packages/fixes/garrysmod/garrysmod/addons/remixbinary/lua/remixlua/sv/sv_nonapi_flashlight.lua` | Not reviewed (vendored behavior) |
| `packages/fixes/garrysmod/garrysmod/addons/remixbinary/lua/remixlua/sv/sv_remix_flashlight.lua` | Not reviewed (vendored behavior) |
| `packages/fixes/garrysmod/garrysmod/addons/remixbinary/lua/remixlua/sv/sv_remix_maplight_bridge.lua` | Not reviewed (vendored behavior) |
| `packages/fixes/garrysmod/garrysmod/addons/remixbinary/lua/remixlua/sv/sv_remove_entities.lua` | Not reviewed (vendored behavior) |
| `packages/fixes/garrysmod/garrysmod/addons/remixbinary/lua/remixlua/sv/sv_skybox_fix.lua` | Not reviewed (vendored behavior) |
| `packages/fixes/garrysmod/garrysmod/addons/remixbinary/lua/tmc/init.lua` | Not reviewed (vendored behavior) |
| `packages/fixes/garrysmod/garrysmod/addons/remixbinary/lua/tmc/types.lua` | Not reviewed (vendored behavior) |
| `packages/fixes/garrysmod/garrysmod/addons/remixbinary/lua/weapons/gmod_tool/stools/remix_rt_light_bonemerge.lua` | Not reviewed (vendored behavior) |
| `packages/fixes/garrysmod/garrysmod/addons/remixbinary/lua/weapons/gmod_tool/stools/remix_rt_light_cylinder.lua` | Not reviewed (vendored behavior) |
| `packages/fixes/garrysmod/garrysmod/addons/remixbinary/lua/weapons/gmod_tool/stools/remix_rt_light_disk.lua` | Not reviewed (vendored behavior) |
| `packages/fixes/garrysmod/garrysmod/addons/remixbinary/lua/weapons/gmod_tool/stools/remix_rt_light_distant.lua` | Not reviewed (vendored behavior) |
| `packages/fixes/garrysmod/garrysmod/addons/remixbinary/lua/weapons/gmod_tool/stools/remix_rt_light_rect.lua` | Not reviewed (vendored behavior) |
| `packages/fixes/garrysmod/garrysmod/addons/remixbinary/lua/weapons/gmod_tool/stools/remix_rt_light_sphere.lua` | Not reviewed (vendored behavior) |
| `packages/fixes/garrysmod/garrysmod/addons/remixbinary/materials/vmt_replacer.py` | Not reviewed (vendored behavior) |
| `packages/fixes/garrysmod/garrysmod/addons/rtx_agent/lua/autorun/client/rtx_agent.lua` | Not reviewed (vendored behavior) |
| `packages/fixes/garrysmod/garrysmod/addons/rtx_water/lua/autorun/rtx_water.lua` | Not reviewed (vendored behavior) |
| `packages/fixes/garrysmod/garrysmod/addons/rtx_water/lua/rtx_water/cl_bodies.lua` | Not reviewed (vendored behavior) |
| `packages/fixes/garrysmod/garrysmod/addons/rtx_water/lua/rtx_water/cl_core.lua` | Not reviewed (vendored behavior) |
| `packages/fixes/garrysmod/garrysmod/addons/rtx_water/lua/rtx_water/cl_data.lua` | Not reviewed (vendored behavior) |
| `packages/fixes/garrysmod/garrysmod/addons/rtx_water/lua/rtx_water/cl_menu.lua` | Not reviewed (vendored behavior) |
| `packages/fixes/garrysmod/garrysmod/addons/rtx_water/lua/rtx_water/cl_native.lua` | Not reviewed (vendored behavior) |
| `packages/fixes/garrysmod/garrysmod/addons/rtx_water/lua/rtx_water/cl_ripples.lua` | Not reviewed (vendored behavior) |
| `packages/fixes/garrysmod/garrysmod/addons/rtx_water/lua/rtx_water/cl_splash.lua` | Not reviewed (vendored behavior) |
| `packages/fixes/garrysmod/garrysmod/addons/rtx_water/lua/rtx_water/cl_surface.lua` | Not reviewed (vendored behavior) |
| `packages/fixes/garrysmod/garrysmod/addons/rtx_water/lua/rtx_water/sv_bullets.lua` | Not reviewed (vendored behavior) |
| `packages/fixes/source/debug/addon/lua/autorun/client/rtx_debug.lua` | Not reviewed (vendored behavior) |
| `packages/model-hotloader/mmd_hotloader/lua/autorun/mmdhl.lua` | Not reviewed (vendored behavior) |
| `packages/model-hotloader/mmd_hotloader/lua/entities/mmdhl_attach_link.lua` | Not reviewed (vendored behavior) |
| `packages/model-hotloader/mmd_hotloader/lua/entities/mmdhl_prop/cl_init.lua` | Not reviewed (vendored behavior) |
| `packages/model-hotloader/mmd_hotloader/lua/entities/mmdhl_prop/init.lua` | Not reviewed (vendored behavior) |
| `packages/model-hotloader/mmd_hotloader/lua/entities/mmdhl_prop/shared.lua` | Not reviewed (vendored behavior) |
| `packages/model-hotloader/mmd_hotloader/lua/entities/mmdhl_ragdoll/cl_init.lua` | Not reviewed (vendored behavior) |
| `packages/model-hotloader/mmd_hotloader/lua/entities/mmdhl_ragdoll/init.lua` | Not reviewed (vendored behavior) |
| `packages/model-hotloader/mmd_hotloader/lua/entities/mmdhl_ragdoll/shared.lua` | Not reviewed (vendored behavior) |
| `packages/model-hotloader/mmd_hotloader/lua/entities/mmdhl_ragdoll/tool_api.lua` | Not reviewed (vendored behavior) |
| `packages/model-hotloader/mmd_hotloader/lua/mmdhl/actors.lua` | Not reviewed (vendored behavior) |
| `packages/model-hotloader/mmd_hotloader/lua/mmdhl/bodygroups.lua` | Not reviewed (vendored behavior) |
| `packages/model-hotloader/mmd_hotloader/lua/mmdhl/bone_mapper.lua` | Not reviewed (vendored behavior) |
| `packages/model-hotloader/mmd_hotloader/lua/mmdhl/bone_mapper_rules.lua` | Not reviewed (vendored behavior) |
| `packages/model-hotloader/mmd_hotloader/lua/mmdhl/bone_mapper_ui.lua` | Not reviewed (vendored behavior) |
| `packages/model-hotloader/mmd_hotloader/lua/mmdhl/carrier.lua` | Not reviewed (vendored behavior) |
| `packages/model-hotloader/mmd_hotloader/lua/mmdhl/client.lua` | Not reviewed (vendored behavior) |
| `packages/model-hotloader/mmd_hotloader/lua/mmdhl/client_ragdolls.lua` | Not reviewed (vendored behavior) |
| `packages/model-hotloader/mmd_hotloader/lua/mmdhl/collision_editor.lua` | Not reviewed (vendored behavior) |
| `packages/model-hotloader/mmd_hotloader/lua/mmdhl/compat.lua` | Not reviewed (vendored behavior) |
| `packages/model-hotloader/mmd_hotloader/lua/mmdhl/compatibility_policy.lua` | Not reviewed (vendored behavior) |
| `packages/model-hotloader/mmd_hotloader/lua/mmdhl/debug.lua` | Not reviewed (vendored behavior) |
| `packages/model-hotloader/mmd_hotloader/lua/mmdhl/entity_editor.lua` | Not reviewed (vendored behavior) |
| `packages/model-hotloader/mmd_hotloader/lua/mmdhl/faceposer.lua` | Not reviewed (vendored behavior) |
| `packages/model-hotloader/mmd_hotloader/lua/mmdhl/file_access.lua` | Not reviewed (vendored behavior) |
| `packages/model-hotloader/mmd_hotloader/lua/mmdhl/first_person.lua` | Not reviewed (vendored behavior) |
| `packages/model-hotloader/mmd_hotloader/lua/mmdhl/i18n.lua` | Not reviewed (vendored behavior) |
| `packages/model-hotloader/mmd_hotloader/lua/mmdhl/installation.lua` | Not reviewed (vendored behavior) |
| `packages/model-hotloader/mmd_hotloader/lua/mmdhl/installation_ui.lua` | Not reviewed (vendored behavior) |
| `packages/model-hotloader/mmd_hotloader/lua/mmdhl/instances.lua` | Not reviewed (vendored behavior) |
| `packages/model-hotloader/mmd_hotloader/lua/mmdhl/library.lua` | Not reviewed (vendored behavior) |
| `packages/model-hotloader/mmd_hotloader/lua/mmdhl/materials.lua` | Not reviewed (vendored behavior) |
| `packages/model-hotloader/mmd_hotloader/lua/mmdhl/menu.lua` | Not reviewed (vendored behavior) |
| `packages/model-hotloader/mmd_hotloader/lua/mmdhl/names.lua` | Not reviewed (vendored behavior) |
| `packages/model-hotloader/mmd_hotloader/lua/mmdhl/native_policy.lua` | Not reviewed (vendored behavior) |
| `packages/model-hotloader/mmd_hotloader/lua/mmdhl/native_render.lua` | Not reviewed (vendored behavior) |
| `packages/model-hotloader/mmd_hotloader/lua/mmdhl/native_tools.lua` | Not reviewed (vendored behavior) |
| `packages/model-hotloader/mmd_hotloader/lua/mmdhl/performance.lua` | Not reviewed (vendored behavior) |
| `packages/model-hotloader/mmd_hotloader/lua/mmdhl/persistence.lua` | Not reviewed (vendored behavior) |
| `packages/model-hotloader/mmd_hotloader/lua/mmdhl/physics_editor.lua` | Not reviewed (vendored behavior) |
| `packages/model-hotloader/mmd_hotloader/lua/mmdhl/physics_editor_ui.lua` | Not reviewed (vendored behavior) |
| `packages/model-hotloader/mmd_hotloader/lua/mmdhl/physics_lod.lua` | Not reviewed (vendored behavior) |
| `packages/model-hotloader/mmd_hotloader/lua/mmdhl/physics_profile.lua` | Not reviewed (vendored behavior) |
| `packages/model-hotloader/mmd_hotloader/lua/mmdhl/physics_reset.lua` | Not reviewed (vendored behavior) |
| `packages/model-hotloader/mmd_hotloader/lua/mmdhl/physics_settings.lua` | Not reviewed (vendored behavior) |
| `packages/model-hotloader/mmd_hotloader/lua/mmdhl/player_copies.lua` | Not reviewed (vendored behavior) |
| `packages/model-hotloader/mmd_hotloader/lua/mmdhl/props/collision.lua` | Not reviewed (vendored behavior) |
| `packages/model-hotloader/mmd_hotloader/lua/mmdhl/props/editor.lua` | Not reviewed (vendored behavior) |
| `packages/model-hotloader/mmd_hotloader/lua/mmdhl/props/library.lua` | Not reviewed (vendored behavior) |
| `packages/model-hotloader/mmd_hotloader/lua/mmdhl/props/render.lua` | Not reviewed (vendored behavior) |
| `packages/model-hotloader/mmd_hotloader/lua/mmdhl/props/server.lua` | Not reviewed (vendored behavior) |
| `packages/model-hotloader/mmd_hotloader/lua/mmdhl/props/shared.lua` | Not reviewed (vendored behavior) |
| `packages/model-hotloader/mmd_hotloader/lua/mmdhl/props/tool.lua` | Not reviewed (vendored behavior) |
| `packages/model-hotloader/mmd_hotloader/lua/mmdhl/scene_sharing.lua` | Not reviewed (vendored behavior) |
| `packages/model-hotloader/mmd_hotloader/lua/mmdhl/secondary_backend.lua` | Not reviewed (vendored behavior) |
| `packages/model-hotloader/mmd_hotloader/lua/mmdhl/secondary_collision.lua` | Not reviewed (vendored behavior) |
| `packages/model-hotloader/mmd_hotloader/lua/mmdhl/secondary_water.lua` | Not reviewed (vendored behavior) |
| `packages/model-hotloader/mmd_hotloader/lua/mmdhl/server.lua` | Not reviewed (vendored behavior) |
| `packages/model-hotloader/mmd_hotloader/lua/mmdhl/server_settings.lua` | Not reviewed (vendored behavior) |
| `packages/model-hotloader/mmd_hotloader/lua/mmdhl/settings.lua` | Not reviewed (vendored behavior) |
| `packages/model-hotloader/mmd_hotloader/lua/mmdhl/sharing.lua` | Not reviewed (vendored behavior) |
| `packages/model-hotloader/mmd_hotloader/lua/mmdhl/terms.lua` | Not reviewed (vendored behavior) |
| `packages/model-hotloader/mmd_hotloader/lua/mmdhl/ui.lua` | Not reviewed (vendored behavior) |
| `packages/model-hotloader/mmd_hotloader/lua/mmdhl/workshop.lua` | Not reviewed (vendored behavior) |
| `packages/model-hotloader/mmd_hotloader/lua/mmdhl/workshop_export.lua` | Not reviewed (vendored behavior) |
| `packages/model-hotloader/mmd_hotloader/lua/weapons/gmod_tool/stools/mmdhl_prop.lua` | Not reviewed (vendored behavior) |
| `packages/model-hotloader/mmd_hotloader/lua/weapons/weapon_mmdhl.lua` | Not reviewed (vendored behavior) |
| `packages/model-hotloader/overrides/installation.lua` | Not reviewed (vendored behavior) |
| `packages/procedural-bodygroup-destruction/!gmod_bullet_break_simulator/lua/autorun/bullet_break_simulator_loader.lua` | Not reviewed (vendored behavior) |
| `packages/procedural-bodygroup-destruction/!gmod_bullet_break_simulator/lua/bullet_break_simulator/cl_10_i18n.lua` | Not reviewed (vendored behavior) |
| `packages/procedural-bodygroup-destruction/!gmod_bullet_break_simulator/lua/bullet_break_simulator/cl_20_filters.lua` | Not reviewed (vendored behavior) |
| `packages/procedural-bodygroup-destruction/!gmod_bullet_break_simulator/lua/bullet_break_simulator/cl_21_mdl_bodyparts.lua` | Not reviewed (vendored behavior) |
| `packages/procedural-bodygroup-destruction/!gmod_bullet_break_simulator/lua/bullet_break_simulator/cl_22_shape.lua` | Not reviewed (vendored behavior) |
| `packages/procedural-bodygroup-destruction/!gmod_bullet_break_simulator/lua/bullet_break_simulator/cl_25_profiler.lua` | Not reviewed (vendored behavior) |
| `packages/procedural-bodygroup-destruction/!gmod_bullet_break_simulator/lua/bullet_break_simulator/cl_29_mesh_preparation.lua` | Not reviewed (vendored behavior) |
| `packages/procedural-bodygroup-destruction/!gmod_bullet_break_simulator/lua/bullet_break_simulator/cl_30_overlay.lua` | Not reviewed (vendored behavior) |
| `packages/procedural-bodygroup-destruction/!gmod_bullet_break_simulator/lua/bullet_break_simulator/cl_32_mesh_persistence.lua` | Not reviewed (vendored behavior) |
| `packages/procedural-bodygroup-destruction/!gmod_bullet_break_simulator/lua/bullet_break_simulator/cl_39_material_safety.lua` | Not reviewed (vendored behavior) |
| `packages/procedural-bodygroup-destruction/!gmod_bullet_break_simulator/lua/bullet_break_simulator/cl_40_damage.lua` | Not reviewed (vendored behavior) |
| `packages/procedural-bodygroup-destruction/!gmod_bullet_break_simulator/lua/bullet_break_simulator/cl_90_settings.lua` | Not reviewed (vendored behavior) |
| `packages/procedural-bodygroup-destruction/!gmod_bullet_break_simulator/lua/bullet_break_simulator/sh_00_config.lua` | Not reviewed (vendored behavior) |
| `packages/procedural-bodygroup-destruction/!gmod_bullet_break_simulator/lua/bullet_break_simulator/sh_10_network.lua` | Not reviewed (vendored behavior) |
| `packages/procedural-bodygroup-destruction/!gmod_bullet_break_simulator/lua/bullet_break_simulator/sv_20_hits.lua` | Not reviewed (vendored behavior) |
| `packages/remove-halo/Remove_halo/lua/autorun/client/removehalo.lua` | Not reviewed (vendored behavior) |
| `packages/runtime/files/usd/hd/resources/codegenTemplates/schemaClass.cpp` | Not reviewed (vendored behavior) |
| `packages/runtime/files/usd/hd/resources/codegenTemplates/schemaClass.h` | Not reviewed (vendored behavior) |
| `packages/runtime/files/usd/usd/resources/codegenTemplates/__init__.py` | Not reviewed (vendored behavior) |
| `packages/runtime/files/usd/usd/resources/codegenTemplates/api.h` | Not reviewed (vendored behavior) |
| `packages/runtime/files/usd/usd/resources/codegenTemplates/generatedSchema.module.h` | Not reviewed (vendored behavior) |
| `packages/runtime/files/usd/usd/resources/codegenTemplates/module.cpp` | Not reviewed (vendored behavior) |
| `packages/runtime/files/usd/usd/resources/codegenTemplates/moduleDeps.cpp` | Not reviewed (vendored behavior) |
| `packages/runtime/files/usd/usd/resources/codegenTemplates/schemaClass.cpp` | Not reviewed (vendored behavior) |
| `packages/runtime/files/usd/usd/resources/codegenTemplates/schemaClass.h` | Not reviewed (vendored behavior) |
| `packages/runtime/files/usd/usd/resources/codegenTemplates/tokens.cpp` | Not reviewed (vendored behavior) |
| `packages/runtime/files/usd/usd/resources/codegenTemplates/tokens.h` | Not reviewed (vendored behavior) |
| `packages/runtime/files/usd/usd/resources/codegenTemplates/wrapSchemaClass.cpp` | Not reviewed (vendored behavior) |
| `packages/runtime/files/usd/usd/resources/codegenTemplates/wrapTokens.cpp` | Not reviewed (vendored behavior) |

</details>

Coverage entries: 205 changed project text files, 9 named context files, 10 package indexes, 320 vendored source files.

## Checks you could not run

- Real GMod startup and rendering, per the review boundary. Runtime shader execution and device-loss behavior need a controlled PoC session after triage.
- Workshop hooks and publisher upload behavior could only be traced statically; no network, push, `gmpublish` or publisher execution was permitted.
- The fork runtime was not built, since that would create or alter a fork worktree. GPU shader NaNs, allocation failure and device loss need a controlled runtime test; `slangc` was not run.
- Install and snapshot failure paths were not exercised against a real game install, per the boundary. The isolated repros wrote only under `out/r3-review/repro`.

## Questions

- For Claude: Should selecting “(leave to Remix)” reset weather in the current session, as ADR 0031 says, or only at the next start? The current UI has no restart notice.
- For Claude and the user before a public release: Which NVIDIA SDK and Model Hotloader library licence/notice texts must ship with their binaries? The review was offline and did not establish redistribution terms.
