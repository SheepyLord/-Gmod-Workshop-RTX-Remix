# GMod Workshop RTX Remix (native loader)

Run NVIDIA RTX Remix in the **normal Steam install** of 64-bit Garry's Mod, without a separate
patched copy of the game and without fighting every GMod update.

> Status: early development. M0 (repo, tooling) is done; the loader itself does not exist yet.
> See [docs/ROADMAP.md](docs/ROADMAP.md).

## Idea

```
GarrysMod\bin\win64\winmm.dll   ← install this one file once
          │
          ├─ at start-up, before the engine: find allowlisted packages (.gma: Workshop or local)
          ├─ deploy their payloads: Remix runtime, gmcl_ modules, rtx-remix\mods, ...
          ├─ load the Remix runtime as d3d9.dll from a versioned folder
          └─ hand over to the game; with RTX off nothing is loaded and the game is vanilla
```

Steam's own files are never modified on disk, so Steam updates and "verify integrity" keep working.
Deleting `winmm.dll` turns everything off.

## For developers and agents

Read [AGENTS.md](AGENTS.md) first. Quick start:

```powershell
tools\test.ps1          # conventions, Python tests, C++ build and tests
```

| Doc | |
|---|---|
| [docs/ARCHITECTURE.md](docs/ARCHITECTURE.md) | Boot sequence, components, data flow |
| [docs/COMPONENTS.md](docs/COMPONENTS.md) | Every component and script, with status |
| [docs/PACKAGE_FORMAT.md](docs/PACKAGE_FORMAT.md) | What a package `.gma` contains (draft) |
| [docs/ON_DISK_LAYOUT.md](docs/ON_DISK_LAYOUT.md) | What the loader writes into the game folder |
| [docs/TESTING.md](docs/TESTING.md) | Test levels, PoC and field installs |
| [docs/RESEARCH.md](docs/RESEARCH.md) | Facts about GMod, Remix and the existing RTX tooling |
| [CHANGELOG.md](CHANGELOG.md) | Notable changes |

## Licence

MIT, see [LICENSE](LICENSE). RTX Remix, DLSS and the other NVIDIA components a runtime package
carries have their own licences.
