# On-disk layout (game side)

The old-install migration is the narrow exception to the untouched-depot rule: recognized legacy
edits are archived and restored to verified stock bytes before the shipment is activated
([ADR 0042](decisions/0042-legacy-remix-migration.md)). Root rtx.conf/dxvk.conf from that installation
are archived too. user.conf and custom configs stay; unrelated D3D proxies do not trigger migration.

What the loader adds to a Garry's Mod install. Everything except `bin\win64\winmm.dll` is created
by the loader. Package files are journaled; the receipt, config, logs and status are explicit control
and reporting files with their own cleanup rules.

```
GarrysMod\
├─ bin\win64\winmm.dll                     the bootstrap (installed by the user or install-loader.ps1)
├─ native-loader\
│  ├─ config.json                          user policy: allowlist, switches, options (the user writes it)
│  ├─ state.json                           journal (schema 1, below): what the loader placed, with SHA-256
│  ├─ lock                                 held open by the deployer that is running (one at a time)
│  ├─ disable                              optional empty file: loader stays a pass-through
│  ├─ packages\<id>\<version>_<gen>\...    payload folders, never changed once placed, e.g.
│  │                                         ...\rtx-remix-runtime\1.6.1+gmod.20261025_3\runtime\d3d9.dll
│  ├─ staging\<transaction>\...            extraction in progress (deleted at the end of every run)
│  ├─ backup\<gen>\<path>                  root files generation <gen> replaced or removed: the
│  │                                         previous generation's copies, kept for rollback (none for a
│  │                                         package whose Workshop item was unsubscribed, ADR 0025)
│  ├─ backup\originals\<path>              loader 0.6.0: what was at a package's path before the loader
│  │                                         took it over; put back once no generation names the path,
│  │                                         and at uninstall (journal `originals`, ADR 0035)
│  ├─ backup\edits\<transaction>\<path>    loader 0.6.0: changed copies of the loader's files that the
│  │                                         package's copy replaced; never deleted by the loader (ADR 0035)
│  ├─ backup\legacy\<transaction>\...    loader 0.8.0: archived prior Remix files plus manifest.json
│  │                                         with original paths, sizes and SHA-256; kept after uninstall
│  ├─ backup\render-guard\<file>.<n>      loader 0.10.1: a changed early render guard cache file, moved
│  │                                         aside before the view is written again; never deleted (ADR 0056)
│  ├─ bootstrap-install.json               the bootstrap's install receipt (install-loader.ps1); its
│  │                                         `original` holds the SHA-256 of a kept foreign winmm.dll/.pdb
│  ├─ original\winmm.dll, winmm.pdb        a winmm.dll that was there before install-loader.ps1 (another
│  │                                         mod's), put back by its -Uninstall (ADR 0035)
│  ├─ session_cvars.json                   M5: the user's archived values of the RTX session variables,
│  │                                         kept until a start without RTX has put them back
│  ├─ remix\non-nvidia.conf                loader 0.5.0: written at each RTX start on a computer without an
│  │                                         NVIDIA GPU: Remix's automatic preset (ADR 0030)
│  ├─ remix\dxvk-<n>.conf, rtx-<n>.conf     loader 0.6.0: copies of the package's Remix layers, written at
│  │                                         each RTX start from the checked payload; the runtime reads
│  │                                         these (ADR 0036)
│  ├─ reshade\                             loader 0.5.0: ReShade's base folder in RTX sessions (ADR 0028):
│  │                                         ReShade.ini, presets, ReShade.log; made once from
│  │                                         bin\win64\ReShade.ini, then the user's (never journaled)
│  └─ logs\loader.log                      start-up step log (rotated)
├─ rtx-remix\mods\<mod>\...                root files from packages (journaled)
├─ rtx.conf, dxvk.conf, user.conf          the user's own Remix configs (top layers; never overwritten)
├─ bin\win64\d3d9.dll, ReShade.ini, ...    a ReShade the user set up for Direct3D 9: never written; RTX
│                                            sessions bind the runtime's d3d9.dll instead (ADR 0028)
└─ garrysmod\
   ├─ lua\bin\gmcl_*_win64.dll             binary modules from packages (journaled)
   ├─ addons\<addon>\...                   M5: Lua add-on folders from packages (journaled)
   ├─ cfg\nativeloader_session.cfg         M5: generated each RTX start that has session variables
   ├─ cfg\nativeloader_restore.cfg         M5: generated at the start without RTX that puts them back
   ├─ data\<folder>\...                    M5: create-only seed data from packages (journaled)
   ├─ data\native-loader\status.json       atomic report of each active bootstrap start (M4)
   └─ data\native-loader\session.json      M5: patch sets applied or skipped, overridden loads
```

`nlctl uninstall` (or [`uninstall-loader.ps1`](../tools/uninstall-loader.ps1.md)) removes everything
the journal lists, puts back the originals it kept (one whose place is taken stays, with a note), then
removes the journal and the lock. `backup\edits` stays: the player's changed copies. `config.json`, the receipt and the logs stay
unless `uninstall-loader.ps1 -RemoveConfig` removes them too. `native-loader\reshade` holds the
user's ReShade settings for RTX sessions: both keep it, and `-RemoveConfig` lists it as kept.

`-RemoveConfig` also removes the folders left empty, and `native-loader` itself if it is empty. A
payload file the user changed (which uninstall leaves in place) stays, and is listed. How the deployer
changes these files is [ADR 0007](decisions/0007-transactional-deployment.md).

Packages never write `garrysmod\cfg` ([ADR 0014](decisions/0014-r1-hardening.md)). The two generated
cfgs below are the bootstrap's own.

M4 also removes `garrysmod/data/native-loader/status.json`, its generated per-PID temporary files,
and that data folder if empty. Other files in the data folder are preserved. Bootstrap off switches
remain pure pass-through and do not update the status file; compare its PID/time to the current game.

## config.json (schema 1)

Implemented by `nl::config` (`loader/core/src/config.cpp`). Check what the loader would do with
`nlctl plan <game root>`.

```json
{
  "schema": 1,
  "enabled": true,
  "allow": {
    "workshop": ["3600000000"],
    "local": ["garrysmod/addons/rtx-remix-runtime.gma"],
    "dev_folders": ["D:/dev/rtx-remix-runtime"]
  },
  "remix": { "enabled": true, "reshade": "auto" },
  "patch_sets": { "require_insecure": true, "allow_rtx_render_patches": true }
}
```

| Key | Default | Rule |
|---|---|---|
| `schema` | required | the integer `1` |
| `enabled` | `true` | `false`: startup skips deployment and activation, leaving deployed files in place |
| `allow.workshop` | `[]` | Workshop item ids **as strings** (large numbers lose digits in some editors), no repeats |
| `allow.local` | `[]` | `.gma` / `.bin` archives, relative to the game root or absolute |
| `allow.dev_folders` | `[]` | unpacked package folders (with `native/manifest.json`), relative or absolute |
| `allow.subscribed_content` | `true` | content-only packages from every subscribed Workshop item, without listing them ([ADR 0027](decisions/0027-content-packages-from-any-subscription.md)); `false` turns that off |
| `remix.enabled` | `true` | `false`: runtime packages stay planned but no runtime is loaded (vanilla rendering) |
| `remix.reshade` | `"auto"` | the RTX package's ReShade in RTX sessions ([ADR 0028](decisions/0028-reshade-in-rtx-sessions.md)): `"auto"` when the game has a ReShade (`bin\win64\ReShade.ini`) or `native-loader\reshade\ReShade.ini` exists, `"on"` always, `"off"` never |
| `patch_sets.require_insecure` | `true` | general in-memory patch sets (M5) only with `-insecure`; the exact RTX rendering exception below is separate |
| `patch_sets.allow_rtx_render_patches` | `true` | loader 0.9.0: allow only the seven fingerprinted rendering recipes owned by `gmod-rtx-remix` without `-insecure`; `false` disables this exception, and from loader 0.10.1 RTX then starts only where the general gate lets the recipes apply ([ADR 0056](decisions/0056-guard-and-startup-fallbacks.md)) |

The rendering exception requires the existing native allowlist and active RTX session. Its
fingerprints bind each complete reviewed patch group, including module, names, find/replace bytes,
offsets and order; changing or adding a patch cannot inherit the exception. Keep
`require_insecure: true` to retain the general gate. To opt out, set
`"allow_rtx_render_patches": false` inside `patch_sets` without changing that gate. The renderer
crashed without these recipes, so with the exception off and the gate closed (no `-insecure`) the
loader 0.10.1 start stays vanilla and reports why (activation `failed`). Both values must
be JSON booleans; unknown keys or a string such as `"false"` invalidate config. This does not grant
community scripts extra permissions or change `sv_allowcslua`. See
[ADR 0052](decisions/0052-scoped-rtx-multiplayer-bootstrap.md).

A fixes build that carries the companion declares `requires_loader: ">=0.10.0"`: the companion's V2
render guard needs the loader's early view (ADR 0054), and 0.10.0 also has the verified multiplayer
helper's loader side. An older loader refuses that package instead of launching without them. The
requirement follows the companion, not the helper option: a fixes build without the companion
(which cannot carry the helper either) keeps the older >=0.2.0 minimum
([ADR 0056](decisions/0056-guard-and-startup-fallbacks.md)). Updating only the Workshop payload
cannot update the installed `winmm.dll`.

- `allow` is the native-code allowlist ([ADR 0003](decisions/0003-native-trust-allowlist.md)).
  Without a config file nothing is allowlisted and the loader does nothing.
- With a config file, the subscribed Workshop items are opened too, unless
  `allow.subscribed_content` is `false`. A package found there may hold only Remix mods and Lua
  add-ons ([ADR 0027](decisions/0027-content-packages-from-any-subscription.md)); one with native code
  is skipped until its item is listed in `allow.workshop`.
- Strict JSON; **unknown keys are errors** (a typo such as `"alow"` stops the loader instead of
  silently allowing nothing or something else). An invalid file leaves the loader inactive.
- Which allowlisted package wins when several qualify: [ADR 0006](decisions/0006-package-precedence-and-planning.md).

## state.json (schema 1)

The deployer's journal, implemented by `nl::journal` (`loader/core/src/journal.cpp`); `nlctl status
<game root> --json` prints it. Written only by the deployer, atomically (temporary file, flush,
rename). It is parsed as strictly as a manifest (unknown keys, unsafe paths and paths outside the
folders the loader manages are errors), and a journal that does not parse stops every deployer
command, which then changes nothing. Its paths follow the path rules of
[PACKAGE_FORMAT.md](PACKAGE_FORMAT.md), with one difference: they may be up to 4,096 bytes long,
because the loader puts its own folders in front of package paths.

| Key | Meaning |
|---|---|
| `schema` | the integer `1` |
| `loader` | the loader version that wrote it |
| `next` | number of the next transaction and generation (never reused) |
| `current` | the deployed generation, or `null`: `generation` (its number), `packages`, `files` |
| `previous` | the generation `rollback` returns to, or `null`; same shape |
| `previous_backup` | `native-loader/backup/<gen>`: where the previous generation's root files are that `current` replaced or removed; empty if none |
| `retired` | files waiting to be deleted, each only while it still matches its record; one that cannot be deleted yet (read-only, open elsewhere) stays for the next run |
| `originals` | loader 0.6.0, only when there are some: file records (`path` is where the file goes back; it is kept at `native-loader/backup/originals/<path>`) of what was at a package's path before the loader took it over; each goes back once no generation names its path and the path is free ([ADR 0035](decisions/0035-restore-automatically.md)) |
| `dirs` | folders the loader created; each is removed once empty |
| `hold` | after a rollback, the packages it rolled back from (`id@manifest_sha256`). While the plan (before any package is re-planned as broken) names exactly these, apply deploys nothing; the hold ends when it names anything else. `null`: no hold |
| `pending` | a transaction that has not committed, or `null`: `transaction`, `action` (`apply`, `rollback`), `steps` (`make_dir` / `move`, each with its hash); the next run undoes it |

A package record: `id`, `version`, `manifest_sha256` (the identity of that package version),
`source` (`dev_folder`, `local`, `workshop`), `location`, `payload` (its payload folder, or empty)
and `remix` (the manifest's `remix` section for the runtime, which M4 activates; else `null`).

A file record: `path` (relative to the game root, `/`-separated), `package`, `sha256`, `size`,
`mtime` (last write time when placed, FILETIME units) and `adopted` (`true`: the file was there
before the loader with the right content; the loader never deletes it, and takes it over as an
original once it changes or a new version differs, ADR 0035).

## Off switches (any one)

| Switch | Effect |
|---|---|
| Launch option `-nonativeloader` | Pure pass-through for this launch |
| Environment variable `NATIVE_LOADER_DISABLE=1` | Same |
| File `native-loader\disable` | Same, until the file is deleted |
| Delete `bin\win64\winmm.dll` | Loader gone; deployed files stay inert until `uninstall-loader.ps1` removes them |

## status.json (schema 1, M4)

Written by `nl::status` after the active main-game startup step, including vanilla outcomes caused
by missing/disabled/invalid config, no deployed runtime, RTX off, pending state or an activation
failure. It is not produced by Chromium helpers or an M1 off switch. An old status after an off
switch is deliberately stale. A new report uses `status.json.tmp-<PID>`, flushes it, then atomically
renames it over status.json; simultaneous instances cannot share a temporary filename.

| Field | Meaning |
|---|---|
| `schema` | Integer 1; readers must recognize the schema before interpreting fields |
| `loader_version`, `utc`, `process_id` | Loader version, UTC startup timestamp and main game PID; identify stale reports |
| `startup_elapsed_ms` | Startup through activation, before final report I/O; a diagnostic timing, not a frame benchmark |
| `deployment.outcome` | `skipped`, `deployed`, `unchanged`, `held`, `kept`, `failed` or `refused` |
| `deployment.reason`, `blocked_by` | Error/refusal text; `none`, `running_game` or `deployer_lock` for structured contention |
| `deployment.generation`, `recovered` | Current committed generation (0 if absent/unknown), and whether pending work was recovered |
| `deployment.change_count`, `operations`, `elapsed_ms` | Planned/applied change list count, all deployer filesystem operations, preparation/deployment duration; log/status writes are separate |
| `deployment.packages`, `notes`, `skipped` | Deployed package descriptions, retained-file/defer notes and `{package,reason}` records |
| `activation.outcome`, `reason` | `active`, `inactive` or `failed`, with a reason. `active` confirms the startup transaction, not successful later rendering |
| `activation.runtime` | `{id,version,folder,dll}`; absolute deployed paths when known, even with `remix.enabled=false`; empty strings if unknown |
| `activation.environment.requested` | Planned `{name,value}` assignments |
| `activation.environment.set` | Assignments retained in the final process; empty after rollback |
| `activation.environment.user_values_kept` | Original user values preserved; config lists remain as the final suffix after package layers |
| `activation.layers.rtx`, `dxvk` | Effective low-to-high layer lists, as the runtime reads them; missing/empty user config variables use the default root conf |
| `activation.layer_copies` | Loader 0.6.0, ADR 0036: `{copy,source}` for each package layer: the short copy in `native-loader/remix` the lists name, and the package's file it was written from. A copy that could not be written is not listed; its source is in the list instead, with a `session.notes` entry |
| `activation.launch_arguments.requested`, `added`, `already_present` | Missing planned tokens (the package's, then the loader's borderless window, [ADR 0018](decisions/0018-rtx-sessions-in-a-borderless-window.md)), retained additions, and existing user tokens/values such as `-dxlevel 95` or `-fullscreen` |
| `activation.launch_arguments.fallback_launch_options` | Exact missing options to supply manually after a refused swap; the loader never writes Steam settings |
| `activation.system_vulkan_path` | Retained System32 preload path, or empty when absent/undone |
| `activation.windows_error`, `missing_system_dependencies` | Win32/SEH code and missing System32 redistributable/Vulkan DLL names when preload fails |
| `activation.gpu_vendors`, `non_nvidia` | Loader 0.5.0, ADR 0030: the hardware graphics adapters' PCI vendor ids (DXGI; empty when not read or RTX is off), and whether none is NVIDIA, so `native-loader/remix/non-nvidia.conf` is in `layers.dxvk` |
| `activation.preloaded` | Loader 0.5.0, ADR 0030: absolute paths of the runtime's late bare-name DLLs (`amd_fidelityfx_vk.dll`, `cudart64_*`, `nvrtc64_*`, `nvrtc-builtins64_*`) loaded right after it; one that failed is a `session.notes` entry instead |
| `activation.reshade` | Loader 0.5.0, ADR 0028: `outcome` (`active`, `off`, `failed`: the session runs without ReShade), `reason`, `package`, `layer`, `layer_manifest`, `folder`, `settings` (`kept`, `migrated`, `fresh`), `presets` copied this start, `environment` set for the layer, `notes` |
| `activation.rolled_back`, `elapsed_ms` | Whether applied settings were undone, and activation duration |
| `errors` | Startup errors, JSON-escaped strings; empty on ordinary success/inactivity |

The M1 log header still proves entry timing. M4 appends `deployment.outcome`, `.generation`,
`.change_count`, `.operations`, `.elapsed_ms`, `.recovered`, `.blocked_by`, `.error`, repeated
`.skipped`/`.note`, plus `activation.outcome`, `.reason`, `.runtime.id/version/folder/dll`,
`.system_vulkan_path`, `.environment.set/user_values_kept`, `.layers.rtx/dxvk`, `.layer_copies` (0.6.0),
`.arguments.added/already_present`, `.fallback_launch_options`, `.windows_error`,
`.missing_system_dependencies`, `.preloaded` (0.5.0), `.rolled_back`, `.elapsed_ms`, repeated `error`, and
`startup.elapsed_ms` / `startup.complete`. Structured values use JSON on one key=value line.

## M5 session files

- `garrysmod/data/native-loader/session.json` is rewritten while a session with module hooks runs,
  each time the DLL-load watcher changes something. Its shape:

  ```text
  {"schema": 1, "utc": "<time written>", "process_id": ...,
   "patches": [{"module", "name", "result": "applied"|"skipped", "reason"}],
   "overrides": [{"module", "requested", "loaded", "result": "redirected"|"failed", "windows_error"}],
   "hidden_addons": {"folders", "left_out", "search_hooks"},
   "notes": [...], "hooked_modules": N}
  ```

  - `hidden_addons` is filled in sessions without a runtime
    ([ADR 0013](decisions/0013-rtx-only-addons-hidden-without-rtx.md)). It holds the folders to hide,
    the ones a search actually left out, and `filesystem_stdio.dll` with its hooked import count.
  - `notes` says what did not work as planned, for example a module whose file-search imports could
    not be found.
  - A `process_id` other than the running game's means the file is from an earlier launch.
  - The file is never written when any folder below the game root on its path is a link (R1-005).
- `status.json` gains `"session": {"cvars", "cvars_exec", "recorded", "restore_values",
  "restore_exec", "patches", "patches_allowed", "overrides", "hooks", "hidden_addons", "notes"}`:
  what start-up set up.
- The journal's package records carry `"requires_remix": true` for packages that set it.
- From loader 0.3.0 they also carry `"module_dependencies"` for packages that declare them
  ([ADR 0024](decisions/0024-bundled-addons-and-module-dependencies.md)): the start-up code reads them
  from the journal in sessions without a runtime too. An older loader cannot read such a journal.
- `native-loader/session_cvars.json`: `{"schema": 2, "restore_issued": bool, "values": {name:
  the user's value}, "session_values": {name: the RTX session's value}}`. Schema 1 (without
  `session_values`) is still read. The record's life
  ([ADR 0010](decisions/0010-rtx-session-extras.md), [ADR 0014](decisions/0014-r1-hardening.md)):
  1. It is written before the first RTX session that changes a variable `config.cfg` archives.
  2. A start without RTX, whose journal could be read, writes `nativeloader_restore.cfg`, adds
     `+exec nativeloader_restore.cfg` and sets `restore_issued`. The cfg holds only the values that
     `config.cfg` still has at the session's value: one the user changed since is left alone. If none
     is left, the record is deleted instead.
  3. The start after that deletes the record.
- The two generated cfgs begin with `// Generated by the GMod native loader`; the loader replaces or
  removes only files that do. Uninstall removes them and `session.json`; it keeps a pending record.


## R6 T1 layer order

The earlier "low-to-high" description of `activation.layers.dxvk` does not apply to Remix's
`rtx.*` options. Their first listed DXVK layer containing a key wins: loader Remix layers precede
the package copies. DXVK's merged `dxvk.*`/`d3d9.*` config instead takes the last value. The root
`dxvk.conf` remains last; `rtx.conf` and `user.conf` keep their stronger Remix priorities.

## R6 T1 performance tiers and GPU crash diagnostics (ADR 0062)

Schema 1 accepts these additional optional keys (older loaders reject them as unknown):

| Key | Default | Rule |
|---|---|---|
| `remix.performance_tier` | `"auto"` | `"high"`, `"medium"`, `"low"` override GPU selection; an invalid value/type uses auto and adds an activation note |
| `diagnostics.gpu_crash_dumps` | `"off"` | `"next_start"` once, `"always"` every RTX activation; invalid values/types use off with an activation note |

Auto selects the NVIDIA adapter with the most DXGI DedicatedVideoMemory. The VRAM tier is low
through 8.5 GiB, medium through 12.5 GiB, high above. Recognized consumer RTX model classes 8/9,
7 and 5/6 limit it to high, medium and low respectively; Laptop lowers the class one step, and
Ti/Super do not change it. Use the lighter of class and VRAM. An unmatched description uses VRAM
alone. Known non-NVIDIA adapters keep `non-nvidia.conf` and get no tier layer. A failed/empty query
uses no GPU layer in auto; it honors an explicit tier override and reports "GPU not read".

| Path under the game root | Ownership / behavior |
|---|---|
| `native-loader/packages/<runtime>/<version>_<generation>/config/dxvk-tiers/{medium,low}.conf` | Ordinary runtime payload, journaled and checked before activation; no new manifest field |
| `native-loader/remix/tier.conf` | Regenerated short copy of the selected package tier; a pre-R6 package gets the built-in low fallback, or no layer for medium/high |
| `native-loader/remix/diagnostics.conf` | Generated only when diagnostics apply; enables Aftermath, resource tracking and startup GPU crash state |
| `native-loader/remix/gpu-crash-dumps.used` | Loader-owned atomic one-start marker; any existing marker, including an empty one, counts as consumed; an RTX start in diagnostic off mode removes it best effort |
| `native-loader/logs/gpu/` | Local dump destination; absolute path in this process's DXVK_AFTERMATH_DUMP_PATH, reported in activation.environment; Remix may upload Aftermath dumps through Sentry with the player's crash-reporting consent |

For one capture set `"diagnostics": {"gpu_crash_dumps":"next_start"}`. After preparing the
layer/folder, the first RTX activation attempt claims the marker before runtime initialization.
Later startup failure/crash does not re-arm it. To ask again, close the game and remove only
`native-loader/remix/gpu-crash-dumps.used`; keep the config at next_start. Alternatively, set the
diagnostic mode to off, start RTX once, then set next_start again: the off-mode RTX start removes
the marker best effort (a failure adds a note and keeps RTX). Always leaves the marker alone and
ignores it. Config is never rewritten. Read-only `nlctl activation` and the menu preview never
consume or reset the request; starts with RTX disabled do not either.
A preparation failure is reported and skips diagnostics. Generated files may remain when unused;
unused files are not listed, and no logs or dumps are deleted by this switch.

The loader creates the dump folder locally. Remix hands Aftermath dumps to its Sentry crash
reporter and uploads them when the player accepts Remix crash reporting. Enabling diagnostics
does not grant that consent; R6 leaves the runtime's reporting behavior unchanged.

The DXVK list is tier, non-NVIDIA (mutually exclusive), package short copies, diagnostics, then the
user's nonempty list or root `dxvk.conf`. The RTX list is unchanged. Standard RtxOptions take the
first DXVK layer holding the key; merged DXVK/D3D9 options take the last. Despite its prefix,
`rtx.enableGpuCrashState` is a merged DXVK startup option, so it stays with Aftermath diagnostics.
A player's root DXVK options or DXVK_ENABLE_* environment can override diagnostics. Saved Remix
settings and `rtx.conf` retain their stronger priority over tier defaults. The built-in low layer:

```
rtx.lowMemoryGpu = True
rtx.opacityMicromap.cache.maxBudgetSizeMB = 512
rtx.skyProbeSide = 1024
rtx.volumetrics.froxelGridResolutionScale = 8
rtx.terrainBaker.cascadeMap.levelResolution = 2048
```

`activation.performance_tier` (interface I2) is
`{"tier":"high|medium|low","source":"auto|config|fallback","reason":"one line","adapter":"description","dedicated_vram_mib":0,"layer":"listed path or empty"}`.
Source config identifies every explicit override, including one using built-in low defaults.
Source fallback identifies automatic low selection using the built-in layer. Without NVIDIA the
adapter is empty and the reason explains why; known non-NVIDIA hardware still gets no tier layer.
An unwritable package copy uses its source path as ADR 0036 already does; I2 then names that path.
An unwritable built-in fallback is omitted from the effective list/environment, with an empty I2
layer and a note; RTX still starts and cannot read an older fallback left at that path.
`activation.notes` reports recoverable tier/config/diagnostic issues, also in the bootstrap log.
The menu shows the effective tier and source only with a listed tier layer and an adapter name;
high, pre-R6 medium, failed tier writes and vanilla fallback show no tier row. Read-only preview
also applies the ADR 0056 recipe refusal. Its seven-language translations are
agent-written and await review. No license/trust/path/off-switch or loader version change.
