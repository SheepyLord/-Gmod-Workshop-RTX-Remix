# GMod Workshop RTX Remix (native loader)

Run NVIDIA RTX Remix in the **normal Steam install** of 64-bit Garry's Mod, without a separate
patched copy of the game and without fighting every GMod update.

> Status: in use. The loader (0.10.x) deploys the RTX package from the Workshop item
> [3829070317](https://steamcommunity.com/sharedfiles/filedetails/?id=3829070317) and runs the
> project's Remix runtime in the player's own install. See [docs/ROADMAP.md](docs/ROADMAP.md) and
> [CHANGELOG.md](CHANGELOG.md).

## Idea

```
GarrysMod\bin\win64\winmm.dll   ← install this one file once
          │
          ├─ at start-up, before the engine: find packages (.gma: the Workshop or local folders)
          ├─ deploy their payloads: Remix runtime, gmcl_ modules, rtx-remix\mods, add-ons, ...
          ├─ load the Remix runtime as d3d9.dll from a versioned folder
          └─ hand over to the game; with RTX off nothing is loaded and the game is vanilla
```

Steam's own files are never modified on disk, so Steam updates and "verify integrity" keep working.
Deleting `winmm.dll` turns everything off.

## For players

1. Download `gmod-native-loader-<version>.zip` from the latest GitHub release and extract it into
   the Garry's Mod folder (it adds `bin\win64\winmm.dll` and `native-loader\config.json`).
2. Subscribe to the Workshop item 3829070317 and start the game on the x86-64 branch.

[dist/README-native-loader.txt](dist/README-native-loader.txt) is the player's readme in the bundle.
A Workshop update cannot replace `winmm.dll`: when the RTX package needs a newer loader, install the
newer bundle.

## For developers and agents

Read [AGENTS.md](AGENTS.md) first. Quick start:

```powershell
tools\test.ps1 -Config Release   # conventions, Python and Lua tests, C++ build and CTest
```

| Doc | |
|---|---|
| [docs/ARCHITECTURE.md](docs/ARCHITECTURE.md) | Boot sequence, components, data flow |
| [docs/COMPONENTS.md](docs/COMPONENTS.md) | Every component and script, with status |
| [docs/PACKAGE_FORMAT.md](docs/PACKAGE_FORMAT.md) | What a package `.gma` contains |
| [docs/ON_DISK_LAYOUT.md](docs/ON_DISK_LAYOUT.md) | What the loader writes into the game folder |
| [docs/TESTING.md](docs/TESTING.md) | Test levels, the PoC and field installs, the release QA protocol |
| [docs/RESEARCH.md](docs/RESEARCH.md) | Facts about GMod, Remix and the existing RTX tooling |
| [docs/decisions/](docs/decisions/README.md) | Why it is built this way |
| [docs/handover/](docs/handover/README.md) | Briefs and reports between agents |
| [skills/](skills/README.md) | Agent skills: AI PBR materials for characters and maps, Workshop content packs |
| [CHANGELOG.md](CHANGELOG.md) | Notable changes |

## Agent skills

[`skills/`](skills/README.md) holds the project's agent skills, each a folder with a `SKILL.md`
that Claude Code (and any agent that reads Markdown) can follow:

- [`mmd-remix-pbr`](skills/mmd-remix-pbr/SKILL.md): AI-generated PBR materials (upscaled albedo,
  normal, roughness, metal, emissive) for MMD characters imported with Model Hotloader, with the
  `rpai` tool, live Remix texture hashes and measured A/B tests.
- [`remix-map-pbr`](skills/remix-map-pbr/SKILL.md): remastering a map for RTX Remix with AI PBR
  materials, lights and extras, as done for gm_poolrooms, Modern House and the Backrooms.
- [`workshop-content-pack`](skills/workshop-content-pack/SKILL.md): packing a character or map with
  the add-ons it depends on into a hidden Workshop item that the loader deploys.

## Licence

MIT, see [LICENSE](LICENSE). RTX Remix, DLSS and the other NVIDIA components a runtime package
carries have their own licences; so do the parts in [packages/](packages/README.md), each with its
licence beside it.
