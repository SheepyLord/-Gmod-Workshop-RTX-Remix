# R20-A report: loader updates and multiplayer entry

Implemented on `r20-menu` for [R20-A](R20-A-loader-menu.md), items 46 and 50 of
[the plan](R20-plan.md). No push, merge, tag, Workshop action or GitHub workflow was performed.

## Built

- Loader **0.15.0**. One hand-edited published-release record at
  `companion/nativeloader/resource/loader-release.json`, still **0.14.0**. It travels as an ordinary
  hashed companion root file; no manifest key or minimum-loader bump. Existing packaging already
  collects it. Release maintainers update it only after the GitHub release exists, then commit and
  push main. The procedure is in TESTING and tools/ci/README.
- A strict 1 KiB C++ reader: exact two-field JSON, SemVer core/prerelease without build metadata,
  exact version-specific project URL, active runtime owner `gmod-rtx-remix`, the existing native
  source allowlist, and journaled size/SHA-256. Missing/foreign/ambiguous/changed input is silent.
- The home-menu update modal: installed/latest versions, DLL replacement/restart instructions,
  pinned download link, Later, and per-version ignore. Menu-realm process-token acknowledgement
  survives HTML reloads. No independent network update check.
- The companion's fallback for loaders older than 0.15.0, after InitPostEntity: physical BASE_PATH
  record/journal reads, runtime/discovery ownership and hash checks, SemVer ordering, DATA start
  receipt across map changes and a per-version ignore. Frame, title bar, text and buttons scale with
  ScrH()/1080. All six companion catalogs translated and checked.
- The multiplayer warning on Angular `/servers` navigation, including descendants, encoded paths,
  query strings, code/history routes, main menu and pause menu. Continue permits the pending route;
  Back returns home; only Continue saves the checkbox. Missing bridge or failed UI/navigation opens
  the browser. RTX-off sessions install neither new notice. All seven menu catalogs completed.
- [ADR 0115](../decisions/0115-released-loader-record-and-reminders.md),
  [ADR 0116](../decisions/0116-multiplayer-entry-warning.md), player instructions, component/script
  documentation, changelog, research and testing notes.

## Decisions from live QA

The stock Awesomium menu ignores CSS inset, clamp() and modern flex layout. The final modal uses
explicit edges, prefixed transform centering and a computed font size, verified on the real menu.
Angular run blocks must be registered during script loading, before its DOM-ready bootstrap.

The stock menu's File object has no Write method: file.Write created an empty file and errored at
`lua/includes/extensions/file.lua:24`. Final menu persistence uses the same stock cookie API as
GMod's menu: `nativeloader.multiplayer-warning-dismissed` and `nativeloader.loader-update-ignored`
in local `mn.db`. The client fallback keeps its DATA files. No cloud config, loader config or
Remix user.conf is used for preferences. These choices refine this task's new ADRs before handover.

## Tests and evidence

Evidence is in this worktree's **`out/r20a/`**, git-ignored. The local fixture was extracted from
the existing CI runtime package, with this branch's companion, built translations and a synthetic
**0.16.0** release record. It was explicitly allowlisted as a dev folder and validated by nlctl.
The repository's actual record was never advanced to that synthetic version.

- `test-release-first.log`: full Release pass, 27 CTests and 682 Python tests, two existing skips.
  **`test-release-final.log`: final full Release pass after the live fixes, 27 CTests and 682 Python
  tests, two existing skips, ending `All checks passed.`**
- C++ `test_loader_release.cpp`: strict grammar/URL/size, duplicate fields/owners, native-source
  allowlist, distribution impostors, foreign file owners, wrong size/hash, edited and missing files.
  Existing core SemVer tests remain in the full native gate.
- Actual JS and Lua harnesses: release/prerelease precedence (including rc.2/rc.10 and uint64
  bounds), invalid records/foreign URLs, equality/newer loaders, every button, per-version ignore,
  process/map/page lifetime, every server route, saved dismissal, changed DOM/Angular navigation,
  missing/broken bridge, RTX off and translations. Companion scaling checked at heights 900/2160.
- `companion_i18n.py update`, all six translations, then `check`; every language has 465 companion
  entries. The seven menu catalogs also pass completeness and lossy-encoding checks.

| Live check | Evidence under out/r20a | Result |
|---|---|---|
| English 1600x900 update/warning | `en-900-fixed/update-en-1600.png`, `multiplayer-en-1600.png` | Centered, readable, full instructions and warning |
| Back / Continue | `en-900-fixed/back-home.png`, `continue-browser.png` | Home / real server browser; undismissed warning repeats |
| Permanent dismissal after restart | `en-900-final/record.json`, `zh-900-final/remembered-after-restart.png`, `cookie-persistence.json` | Saved cookie is 1; next process enters browser directly |
| Chinese 1600x900 update/warning | `zh-900-warning/update-zh-1600.png`, `multiplayer-zh-1600.png` | Translated, no lost characters |
| Pause-menu route | `zh-900-warning/pause-warning-zh.png` | Same warning before browser entry |
| Older-loader fallback in RTX | `zh-900-warning/companion-zh-1600.png` | Simulated status loader_version 0.14.0, real verified package |
| Once across map changes | `zh-900-warning/no-repeat-after-map-change.png` | Construct to Flatgrass; no second reminder |
| English 3840x2160 update/warning | `en-2160/update-en-3840.png`, `multiplayer-en-3840.png` | Real 4K window, scaled and readable |
| Chinese 3840x2160 update/warning | `zh-2160/update-zh-3840.png`, `multiplayer-zh-3840.png` | Real 4K window, scaled and readable |
| Isolated companion 4K layout | `layout-2160/companion-en-3840-isolated.png`, `layout-probe.log` | Actual shipped companion function in vanilla rendering, simulated older active status; scaled title/body/buttons |

The PNGs above are native-size PrintWindow captures, not resized images. Successful runs quit
normally and execute the field's read-only configuration before quitting (`settings_back: restored`).
No field game was launched or ended. The nonexistent synthetic download page was not opened;
the exact gui.OpenURL target is verified by the executable harness.

One early Chinese startup hit the 120-second watchdog (`zh-900/record.json`); subsequent Chinese
900 starts passed. An intermediate full gate hit only the existing glass benchmark's 30-second
wall limit under concurrent RTX load (`test-release-contended.log`); the first complete gate passed.

## Restoration and open work

The bootstrap/retained files and registry match the snapshot. All **2,219** files across the saved
native-loader, companion, native-loader DATA and rtx-remix trees match by SHA-256, with no missing
or added files (`tree-restoration.json`). Original package state/config and menu cookies are back.
The task's lock was released. The game rewrote four existing DATA caches and settings/mapkeys.res;
the standard snapshot reports these watched caches separately from retained files.

The snapshot's depot verification against the field install's currently cached manifests reports
**2,831 matching files, 21 size differences and 25 hash differences**, no missing files
(`snapshot/rollback.json`). Consequently that tool's aggregate `clean` is false, although its
retained-file, listing and registry checks pass and the additional tree comparison is exact. No
Steam file was repaired or written. The lead should reconcile the PoC fixture/manifests separately.

**Open for integration QA:** both RTX 4K map attempts lost the GPU device before a companion
capture (`en-2160/record.json`, `zh-2160/record.json`), including a retry with minimum memory profile
and fps_max 30. The same UI works in RTX at 900 and in vanilla rendering at 2160; 4K RTX map
stability is not claimed. Diagnose/retry with the integrated package/fixture; no runtime changes
were made outside R20-A's scope. Review/merge, the 0.15.0 GitHub release and the subsequent published
record update remain with the lead. No unresolved R20-A unit/harness failure is known.

Commits before this report: `cf10e78` (implementation), `6ac7bf6` (navigation timing/fail-open),
`895cd0f` (live stock-engine fixes and persistence). Each carries the requested Codex trailer.
