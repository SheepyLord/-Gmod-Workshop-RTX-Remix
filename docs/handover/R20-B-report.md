# R20-B report: startup advice and the sky defaults

Branch `r20-qol`, from `r20-int`. Brief: [R20-B-companion-qol.md](R20-B-companion-qol.md).
Decision: [ADR 0117](../decisions/0117-startup-upscaling-hint-and-sky-defaults.md).

**Item 49 is implemented. Item 45 has a tested Lua consumer and opt-out, but native live readback
and its live off/on acceptance remain open.** The brief's assumed read API is file-only. The
consumer deliberately stays silent on the currently packaged native module, as required when
state cannot be read. This report must not be used to mark item 45 fully integrated.

## Built

- The sky defaults to time passing and a 20-real-minute day. The existing slider range (2–240
  minutes) already includes 20, and Reset uses the same defaults. Panel help, the guide's sky
  caption/paragraph and script references agree. No QA probe or R16 brief/report duplicated an old
  30-minute default; fixed-sky test scenarios now explicitly stop the clock.
- A separate one-time migration in the defaults autorun changes both values only when the current
  pair is numerically `0`/`30`. It marks skipped pairs too, preserving later deliberate choices.
  It runs synchronously after ConVar creation and before sky callbacks/startup, preserving R16's
  chosen-time startup and map sky-add-on ownership. Missing ConVars leave migration pending.
- A new client hint autorun waits at least 12 seconds after the first drawn map, with at most
  25 readiness checks (60 seconds when unobstructed). The guide, spawn/pause menus and Alt+X defer
  the whole decision until they close; UI waiting spends no readiness checks or DATA/snapshot reads.
  It then reads current settings, so advice cannot be hidden or queued before a menu edit.
  It checks active RTX, the selected NVIDIA RTX 20/30/40/50 adapter,
  effective enum values and explicit backend capabilities. The five three-line messages distinguish
  upscaling off, frame generation off and both, with DLSS-G or FSR 3 suggestions as supported.
  They use the sandbox hint style/sound and the exact translated tab/control names, including Alt+X.
- `nativeloader_upscaling_hint` defaults on; its translated checkbox follows Frame generation.
  `cl_showhints 0` also suppresses the advice. The process-id/startup-UTC DATA marker consumes the
  first decision, including both on or opt-out, across Lua map changes. Failed marker persistence
  suppresses the notification. The hint reads no `user.conf` and never writes a Remix option.
- All nine new texts are translated in zh-CN, zh-TW, ja, ko, fr and ru. The new sky instructions use
  each catalog's existing control labels. The hint's ConVar help reuses its translated checkbox text.
  `companion_i18n.py update`, `check` and `build` succeeded (465 companion entries per catalog,
  plus the unchanged 474 add-on entries). Generated add-on reference-only churn was discarded.

## Native interface discovery and the open work

`packages/fixes/licenses/oversized-skinning/memory-limits/source/remixapi/remixapi.cpp:1111`
parses `rtx.conf` and returns empty when an option is absent. Its Lua binding is
`RemixConfig.GetConfigVariable`. It does not read live user layers, graphics/DLSS presets or Alt+X
edits. The tab already documents this limitation. The runtime logs its effective options before
device-dependent preset initialization; parsing that log would also give unreliable advice.

The consumer therefore uses the optional atomic `RemixConfig.GetUpscalingState()` contract in
[its script reference](../../companion/nativeloader/lua/autorun/client/nativeloader_upscaling_hint.lua.md):
effective upscaler/frame-generation enums, a post-preset readiness flag and three positive backend
capability flags. **No provider is shipped today.** Implementing it requires runtime/API work, a
native Lua binding and rebuilt/recorded package inputs outside R20-B's assigned paths. The caller
has no fallback to file settings, archived panel drafts or reconstructed presets. Missing, throwing
or invalid native snapshots show no hint.

Integration follow-up: expose a read-only device/render-thread snapshot after pending graphics/DLSS
preset callbacks resolve; supply actual DLSS, DLSS-G and FSR 3 availability; bridge it to the
documented Lua table; rebuild/import the native inputs and pins through the normal process. Then
repeat PoC starts with actual features off/on, and a map change, without saving Remix settings.
Injected snapshots in the tests are consumer evidence only.
Readiness must also resolve legacy DLFG/FSR enable flags versus the selector, as the runtime UI
does, or return not ready; a zero selector must never claim an already-enabled backend is off.

## Tests and evidence

- `test_companion_qol.py`: seven methods, covering all 18 upscaler/frame-generation combinations,
  unsupported/unknown/mixed GPUs, RTX generations and backend flags, inactive/invalid status,
  preferences, unknown/malformed/throwing reads, marker write failure, retries, delayed drawing,
  a later ready state, two maps, a new process, menus kept open beyond 60 seconds, edits during that
  wait and migration lifetime. The harness traps file-only
  getters and Remix setters. Passed under the installed LuaJIT.
- `test_companion_sky.py`: 15 methods passed, including actual defaults/sky startup for fresh and
  migrated profiles, 1.2 game hours per 60 real seconds, and Modern House's unchanged zero-write
  ownership. Existing R16 chosen-time startup scenarios remain covered.
- The guide's six tests, Remix settings' two tests and bundled guard's 25 tests passed. Multi-line
  catalog ids exposed a missing newline escape in the shared test-only Lua serializer; it now
  escapes newline/carriage return/tab, and the actual guide catalogs exercise it.
- `tools\test.ps1 -Config Release` passed on the final implementation: all 27 native tests and
  688 Python tests (633 tools, 29 gmapack, 26 Steam; two optional-environment skips).
  Log: `out/r20b/release-test-final.log`.

Evidence is under this worktree's `out/r20b/` (ignored build/test/QA artifacts):
`release-test-initial.log`, `release-test.log`, `release-test-final.log`, `guard-tests.log`, the generated `i18n_data.lua`,
and the isolated PoC driver/fixture and its `poc-qa.log`. The first full test run failed only because
the new companion source was missing from the exact bundled-source inventory; that was corrected.

### PoC results

Four successful RTX processes on `gm_construct`, seven map loads, all normal quits with exit 0,
`settings_back: restored`, no status error, device loss or hang. Fifteen 1600x900 screenshots.
`out/r20b/acceptance.json` checks the records, profiles, markers, counts and screenshot SHA-256s.
The native feature getter is absent; off/on snapshots are explicitly **simulated consumer tests**.

| Check | Result | Evidence under out/r20b |
|---|---|---|
| Fresh sky profile | Time passes checked, day length 20, migration marks preservation | `poc-before-ui-fix/fresh-native/game/shot-02-fresh-native-sky.png` |
| Old saved `0`/`30` profile | Real ConVars become `1`/`20`; marker says `migrated 0/30 to 1/20` | `poc/simulated-off/game/shot-02-simulated-off-sky.png`, `console.log` |
| New opt-out checkbox | Checked beside Frame generation; label fits/wraps | `poc/simulated-off/game/shot-03-simulated-off-checkbox.png` |
| Native getter absent | `R20B_API nil`, no hint | `poc-before-ui-fix/fresh-native/game/console.log` |
| Simulated both off | Zero hints while the first-run guide is open; one readable hint after closing it | `poc/simulated-off/game/shot-01-simulated-off-start.png`, `console.log` |
| Same process, next map | Hint counter stays 1, no repeated notification | `poc/simulated-off/game/shot-04-simulated-off-map-change.png` |
| Simulated both on, then off at next map | Counter stays 0 on both maps, successful no-hint decision retained | `poc-before-ui-fix/simulated-on/game/console.log`, `shot-04-simulated-on-map-change.png` |

The initial successful round supplied the fresh/both-on evidence. Its first QA fixture referenced
sandbox's `cl_showhints` before the gamemode created it; this was a probe error, corrected by
deferring that setup to initialization and resuming the fresh-profile probe through console Lua.
The production scripts stayed in their verified package. Subsequent probes had no such error.

Visual inspection of that round found the automatic guide (opened at eight seconds) covering the
hint attempted at twelve. The production fix defers the **whole decision**, not a saved message,
until the map is unobstructed. UI waiting does not consume the 25 readiness checks; the 60-second
readiness window describes unobstructed play. The final clean off/map-change run verifies this
refinement (`R20B_BEFORE_CLOSE 0 cursor=true`, then one hint); the current LuaJIT regression also
keeps UI open beyond 60 seconds and enables both features before closing, producing no stale hint.

The last run's `poc/tree-restoration.json` SHA-256-compares **1,471 retained files**, with no added,
missing or changed files: cfg 23, companion 56, native-loader journal/payload 883 and ToPBR 509.
`poc/restored.json` confirms DATA moved back, registry/config restored and cleanup complete;
`protected-before.json` / `protected-after.json` match for the bootstrap and root Remix files.
`user.conf` did not exist before/after; nothing saved or created it. The field game was never
launched or ended. The task released its own shared lock after restoration.

The first PoC attempt (`out/r20b/poc-attempt1`) reached active RTX but no client Lua. It staged Lua
over deployed release scripts, so the immutable catalog rejected their changed hashes; the launch
also omitted `-insecure` although the PoC config required it. The window stalled for 180 seconds
and the existing session watchdog ended that owned PoC run. This does not establish which setup
issue caused the stall. Its `restored.json` confirms cfg/DATA/registry/config restoration, and the
protected file hashes match. No field game was ended.

The corrected driver uses a local development package with 1,139 indexed files, copied and
SHA-256-verified from the existing release bundle with only R20-B's five Lua files and generated
catalog replaced/added. Its per-case QA fixture is also indexed before launch (1,140 files).
`candidate-validation.json` / per-case `candidate.json` record `nlctl manifest` validation. It
launches with `-insecure`, changes no deployed script behind the loader's verified snapshot, and
snapshots the companion plus the complete native-loader journal/payload folder for exact recovery.
All copies stay under `out/r20b`; the release GMA is read only, no Workshop operation is performed.

## Scope and commits

- `23332f4`: sky defaults/migration, hint consumer/checkbox, catalogs, harnesses and ADR/docs.
- `607bf41`: the new companion's single exact bundled-source inventory entry and adjacent docs.
- `315d525`: exact translated sky control names and translated hint ConVar help.
- `8400164`: forbidden API counters checked outside the consumer's protected calls.
- `29f9b8c`: live-QA visibility fix and its UI-wait/current-state regression.

The inventory registration is the one mechanical addition beyond the brief's primary Lua paths:
`_nativeloader_guard.lua` and its `.md`. The repository's completeness test requires every companion
Lua source there. No guard function, wildcard, path rule or render policy changed; this additive
line can merge with R20-D's guard implementation independently. Tests were not weakened to bypass
the check. All commits use the plan's required Codex co-author trailer.

No pushes, merges, tags, Workshop changes or GitHub workflow starts. No package binaries imported.
The field's configuration is read only for restoring the PoC's shutdown settings; the field game
is never launched by this task. The only remaining acceptance gap is the native snapshot provider
and actual live off/on starts after it exists. Review/merge/publication remain with the lead.
