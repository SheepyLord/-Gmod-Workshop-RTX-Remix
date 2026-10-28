# Architecture

How the loader gets RTX Remix (and other native payloads) into a vanilla 64-bit Garry's Mod.
Facts behind each step, with sources, are in [RESEARCH.md](RESEARCH.md); the reasons for each choice
are in [decisions/](decisions/README.md).

## Goals and limits

- One file installed by the user: `GarrysMod\bin\win64\winmm.dll`. Everything else arrives in packages.
- Steam's files stay byte-identical on disk, so updates and "verify integrity" never fight us.
- With RTX off, or anything going wrong, the game runs exactly as vanilla.
- Native code only from allowlisted packages until signed packages exist
  ([ADR 0003](decisions/0003-native-trust-allowlist.md)).
- Not goals (for now): 32-bit GMod, dedicated servers, Linux/Proton.

## Boot sequence

```
Steam ─► GarrysMod\gmod.exe (launcher) ─► bin\win64\gmod.exe   (working dir = game root)
                                              │ static import WINMM.dll, searched in bin\win64 first
                                              ▼
1. winmm.dll (ours) DllMain ── loader lock held: do almost nothing
     • resolve the real %SystemRoot%\System32\winmm.dll for the forwarded exports
     • host must be bin\win64\gmod.exe; off switches: -nonativeloader, NATIVE_LOADER_DISABLE=1,
       native-loader\disable  → stay a pure pass-through
     • patch the EXE entry point to jump to our start-up step
2. Start-up step (EXE entry point, loader lock free, before WinMain and before any engine DLL)
     preflight valid enabled config and valid journal; missing/disabled/invalid means stay vanilla
     discover  allowlisted Workshop items + local .gma + dev folders; distinguish explicit addon disable
     plan      choose package versions, resolve conflicts (one active runtime); keep the last good
               generation if an unavailable/invalid still-allowlisted source would remove/replace it
     deploy    stage → verify CRC32 + SHA-256 → atomic rename; journal every write; back up
               anything replaced; never touch user-edited files or user.conf
     activate  verify cwd, MAX_PATH, and the journaled size and time of every runtime, layer and
               override file (ADR 0014); apply environment and layers,
               reversible kernelbase W/A + PEB command-line descriptor swap,
               optional preload of System32\vulkan-1.dll,
               the runtime folder first on PATH for delay loads (ADR 0010), then
               LoadLibraryExW(<absolute package runtime d3d9.dll>, LOAD_WITH_ALTERED_SEARCH_PATH)
     report    native-loader\logs\loader.log, atomic garrysmod\data\native-loader\status.json
   then jump to the original entry point
3. Engine start-up. When shaderapidx9.dll loads, its import of "d3d9.dll" binds to the
   module already loaded under that name: the Remix runtime. No preload → normal search
   → whatever d3d9.dll the install has (vanilla system DLL, or the user's DXVK).
4. In game. gmcl_RTXFixesBinary finds the runtime with LoadLibraryW("d3d9.dll") as before.
   The Lua companion shows status. Workshop downloads land during the session and are
   deployed at the next launch ("restart to apply").
```

Failure rule: any error in step 2 is logged, nothing half-deployed is activated, and the game
continues vanilla. A broken deployment is rolled back from the journal on the next start.

## Why each mechanism

| Mechanism | Reason |
|---|---|
| `winmm.dll` proxy | `bin\win64\gmod.exe` imports `WINMM.dll` and `dbghelp.dll`, neither a KnownDLL, so a copy in `bin\win64` loads first and earlier than any engine DLL ([ADR 0001](decisions/0001-bootstrap-winmm-proxy.md)) |
| Entry-point hook | Real work (file I/O, `LoadLibrary`) is unsafe under the loader lock in `DllMain`; at the EXE entry point all static imports are loaded and the lock is free |
| Preloading `d3d9.dll` | Windows binds an import to an already-loaded module of the same name, wherever it came from, so the runtime lives in a versioned folder and `bin\win64` stays clean ([ADR 0004](decisions/0004-runtime-in-versioned-folder.md)) |
| Config layers through env vars | The runtime accepts comma-separated lists in `DXVK_CONFIG_FILE` and `DXVK_RTX_CONFIG_FILE`; package defaults go below the user's own `rtx.conf` instead of overwriting it |
| Patch sets applied at module load | RTXFixesBinary applies its culling patches from Lua, after the device exists; its shaderapidx9/materialsystem sets "don't apply properly" that late. Patching when the DLL is mapped, before its code runs, should fix that (verified in M5) |
| Two-phase updates | GMod downloads Workshop updates after start-up, when `d3d9.dll` is already loaded; replacing a loaded runtime is impossible, so the next launch deploys it |
| Status file instead of a binary module | The Lua companion only needs to read state; `file.Read` on `data/` needs no native code |

## Package sources and planning (M2)

Packages are found without the Steam API (it is not initialised yet at step 2), and only the sources
`native-loader\config.json` allowlists are looked at (`nl::discovery`):

- Workshop: `<library>\steamapps\workshop\content\4000\<id>\`, holding exactly one `<name>.gma`
  (plain) or `<hash>_legacy.bin` (LZMA-wrapped, older uploads). The library is the one the game root
  sits in, else the one Steam's `libraryfolders.vdf` lists for app 4000. `appworkshop_4000.acf`
  gives each item's installed version; GMod's `garrysmod\cfg\addonnomount.txt` disables items.
- Local `.gma` / `.bin` archives and unpacked development folders.
- Later, if chosen: a manifest-declared URL with a pinned SHA-256 ([ADR 0002](decisions/0002-source-agnostic-payloads.md)).

Each candidate's package is loaded (`nl::package::load`: manifest read, parsed against schema 1 and
checked against the files) and `nl::planner::make_plan` decides what is active, with a reason for
everything that is not: precedence dev folder > local > Workshop, one runtime, no overlapping root
files ([ADR 0006](decisions/0006-package-precedence-and-planning.md)). `nlctl plan <game root>` shows
the result without changing anything. Deployment of the plan is M3 (below); activation of the
runtime M4.

## Deployment (M3)

`nl::deploy` turns the plan into files on disk as one transaction per run
([ADR 0007](decisions/0007-transactional-deployment.md)). `nlctl apply` runs it outside the game;
from M4 the start-up step does. Each run goes through these steps:

```
lock      exclusive native-loader\lock; refuse while this folder's gmod.exe runs (outside the game)
recover   undo a transaction an earlier run left unfinished (journal "pending"), finish clean-up
plan      M2's plan; then for every root file: keep, replace, add, remove, adopt, or block its package
stage     extract into native-loader\staging\<transaction>\ in one pass per archive, checking size,
          GMA CRC-32 and the manifest's SHA-256 (CNG); a failure re-plans that package as broken
intent    write the steps to the journal (pending)
move      renames on one volume: old root files aside into backup\<gen>\, new payload folders and
          files into place
commit    write the new journal: the new generation, the previous one kept for rollback
clean up  delete staging, retired generations' files (only if unchanged) and empty folders
```

It replaces or removes only files it placed itself, and only after a full SHA-256 shows they are
unchanged. A file the user changed stays as it is and is reported. A target that holds someone
else's file blocks that package, unless the file already has the right content: then it is adopted
and never touched. `rollback` is a transaction back to the previous generation, and `uninstall`
retires everything. A run with nothing to do writes nothing; [RESEARCH.md](RESEARCH.md) section 9
has the timings.

## Startup activation (M4)

The bootstrap calls `nl::startup::prepare` after the initial M1 log. Missing/disabled/invalid config
or an invalid journal causes no deployment or activation. Only the current process is excluded from
the running-game check. A second same-root game or a busy deployer defers deployment; a current
generation may activate only when its journal has no pending transaction. Startup retains the last
good generation when a still-allowlisted source fails, including during staging. Explicit allowlist
removal and addon disable remain intentional removals; M3 rollback holds are preserved
([ADR 0009](decisions/0009-startup-deployment-last-good.md)).

Activation follows [ADR 0008](decisions/0008-activation-at-startup.md): package config layers precede
the user's existing list (or the default root conf), ordinary user environment values are retained,
missing launch arguments are appended (then a borderless window the size of the primary display,
unless the user chose a window mode: [ADR 0018](decisions/0018-rtx-sessions-in-a-borderless-window.md)),
System32 Vulkan is optionally loaded, the runtime folder is
put first on `PATH` for bare-name delay loads ([ADR 0010](decisions/0010-rtx-session-extras.md)),
and the absolute d3d9 path is preloaded last. A failed step undoes earlier process changes. Rollback
state is owned outside the SEH frame, so native faults cannot skip it. Once the runtime is loaded,
activation is committed before anything is reported: a status file or log line that cannot be
written is only logged and never unloads the runtime. So a missing or stale `status.json` does not
mean the game stayed vanilla; compare its process id and time with the running game, and check the
loaded modules (or `session.json`) to tell.

Launch arguments are now resolved: kernelbase's validated cached-string descriptors and the PEB
are swapped together, including byte lengths and terminator capacity, before the game CRT/engine
reads them. A refused swap prevents activation and reports exact fallback launch options; the user
decides whether to supply them. No Steam settings are written. Chromium helper roles remain inert.

The status file describes startup activation, not later renderer health. Runtime initialization and
actual path tracing are verified separately using Remix logs and the user's on-screen confirmation.
Uninstall removes the generated status file and its data folder when empty.

## RTX-session extras (M5)

The runtime alone does not render like the classic RTX install: that install also patches four
engine DLLs on disk, replaces `stdshader_dx6.dll` with fixed-function ports, runs the RTX console
variables from its `autoexec.cfg`, and carries the fixes' Lua add-ons and binary modules. The loader
does each without touching Steam's files and only in sessions where a runtime activates
([ADR 0010](decisions/0010-rtx-session-extras.md), [ADR 0011](decisions/0011-lua-addon-folders.md)):

```
start-up (RTX on)   record the user's archived values of the session variables (config.cfg)
                    write cfg/nativeloader_session.cfg; add +exec nativeloader_session.cfg
                    register the DLL-load watcher (LdrRegisterDllNotification), hook the game's
                    LoadLibrary* imports
engine DLL mapped   apply its patch sets (pattern exactly once; -insecure sessions); hook its imports
stdshader_dx6 load  filesystem_stdio's LoadLibraryExA(<root>\bin\win64\stdshader_dx6.dll) loads the
                    package's copy instead
start-up (RTX off)  if values were recorded: write cfg/nativeloader_restore.cfg, +exec it, once;
                    if a package is marked requires_remix: register the watcher for its add-ons
filesystem_stdio    (RTX off) its FindFirstFile*/FindNextFile* imports are hooked; searches of
  mapped            <root>\garrysmod\addons skip that package's add-on folders, so GMod does not
                    mount them (ADR 0013)
```

The fixes' Lua add-ons, binary modules, Remix mods and seed data are ordinary root files of the
fixes package (`garrysmod/addons/<addon>`, `garrysmod/lua/bin`, `rtx-remix/mods`,
`garrysmod/data/<folder>`); [`package_fixes.py`](../tools/package_fixes.py.md) builds it from the
fixes repo and marks it `requires_remix`, so its add-ons stay out of RTX-off sessions without any
file being moved ([ADR 0013](decisions/0013-rtx-only-addons-hidden-without-rtx.md)). Results land in
`garrysmod/data/native-loader/session.json`, which the Lua companion prints.

## Open questions (tracked in the roadmap)

- VAC: in-memory patches stay off on secure servers unless `-insecure` is set.

Answered: `stdshader_dx6.dll` is loaded by full path (`filesystem_stdio`'s `LoadLibraryExA`), so M5
redirects it through import hooks; and in the field install, next to a `vulkan-1.dll` in
`bin\win64`, the runtime binds System32's (M7, [report](handover/M7-report.md)).
