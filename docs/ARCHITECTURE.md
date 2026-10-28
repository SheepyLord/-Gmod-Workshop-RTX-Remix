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
     discover  allowlisted Workshop items + local .gma + dev folders; skip addonnomount.txt entries
     plan      choose package versions, resolve conflicts (one active runtime)
     deploy    stage → verify CRC32 + SHA-256 → atomic rename; journal every write; back up
               anything replaced; never touch user-edited files or user.conf
     activate  DXVK_CONFIG_FILE / DXVK_RTX_CONFIG_FILE layers, other env vars,
               optional preload of System32\vulkan-1.dll,
               LoadLibraryEx(<package>\runtime\d3d9.dll, LOAD_WITH_ALTERED_SEARCH_PATH),
               register patch sets for modules not loaded yet, add launch arguments
     report    native-loader\logs\loader.log, garrysmod\data\native-loader\status.json
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
the result without changing anything. Deployment of the plan is M3; activation of the runtime M4.

## Open questions (tracked in the roadmap)

- Adding launch arguments (`-dxlevel 90 -nod3d9ex +mat_disable_d3d9ex 1`) from inside the process:
  IAT hooks on `GetCommandLineA/W` in `gmod.exe` and `launcher.dll`, or documented Steam launch options.
- Whether `stdshader_dx6.dll` loads by bare name (preload works) or full path (needs a redirect or a
  journaled on-disk override).
- VAC: in-memory patches stay off on secure servers unless `-insecure` is set.
- Runtime with GModPatchTool's `bin\win64\vulkan-1.dll` in the field install.
