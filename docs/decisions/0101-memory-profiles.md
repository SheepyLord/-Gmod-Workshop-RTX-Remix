# 0101: memory profiles that scale with the computer

- Status: Accepted 2026-11-03
- Decided by: the user (R13's approval, quoted in [R13-plan.md](../handover/R13-plan.md)); Claude
  (the limits and budgets below)

## Context

In R12's field check the game committed 28.6 GB and held an 18.0 GB working set with nothing
spawned, and a later field session went 2.5 GB over the driver's VRAM budget
([R13 plan](../handover/R13-plan.md#the-lag-report)). R13 makes the game fit smaller computers. The
user set the range on 2026-11-03:

- The minimum is 8 GB of VRAM and 16 GB of RAM; nothing lower is supported.
- The recommended computer is 16 GB and 32 GB, and everything should run smoothly there.
- Budgets scale with the computer: no 8 GB budget on a 16 GB card, and more kept in memory on larger
  computers.
- A short delay on a character's first spawn is acceptable on a small computer. Where memory is
  plentiful, the five most recently used characters stay ready.
- The low tier may change memory only, nothing visible.

## Decision

**Profiles.** At each RTX start the loader reads two sizes:

- The largest hardware adapter's dedicated VRAM, of any vendor: memory is not an NVIDIA class
  question, unlike the R6 tier.
- The total physical RAM (`GlobalMemoryStatusEx`).

Each size picks a profile, and the smaller of the two wins. A size that cannot be read counts as the
minimum's. The limits are inclusive and sit below the installed sizes, because Windows reports a
little less (an 8 GB card as 8,188 MiB, 16 GB of RAM as about 16,200 MiB):

| Profile | VRAM | RAM |
|---|---|---|
| below_minimum | under 7,680 MiB, or | under 14,336 MiB |
| minimum | 7,680 MiB or more | 14,336 MiB or more |
| recommended | 15,360 MiB or more | 28,672 MiB or more |
| high | 23,552 MiB or more | 57,344 MiB or more |

**Budgets.** VRAM and RAM below are the measured sizes.

| Budget | below_minimum, minimum | recommended | high |
|---|---|---|---|
| Characters kept ready (most recently used; R13-A, [ADR 0099](0099-saved-characters-load-on-first-use.md)) | 0 | 5 | 10 |
| Their material archives, at most | 0 | RAM / 10 | RAM / 10 |
| GPU memory of game textures before idle ones are released (`d3d9.managedTextureBudgetMiB`) | VRAM / 4 | VRAM / 4 | VRAM / 4 |
| A game texture's CPU copy once it is on the GPU (`d3d9.releaseManagedHostCopies`) | released | kept | kept |

- The GPU budget never drops below 512 MiB.
- Below the minimum, the minimum's rules run with the computer's own sizes, and the reason says the
  computer is unsupported.

**Override.** `remix.memory_profile` in `native-loader\config.json` takes `auto` (the default),
`minimum`, `recommended` or `high`.

- An explicit minimum or recommended profile sizes its budgets for that profile's computer: 8 GB and
  16 GB, or 16 GB and 32 GB. It never assumes more than the computer measures.
- High keeps the measured sizes.
- This is also how tests run the minimum's budgets on a large computer.
- A wrong value, of any JSON type, costs only the override: a note, then auto, as
  `remix.performance_tier` does.

**Where it goes.**

- `status.json` `activation.memory` holds `profile`, `source`, `reason`, `vram_mib`, `ram_mib`,
  `warm_characters`, `warm_mib`, `managed_texture_budget_mib`, `release_host_copies` and `layer`. It is
  `null` when no profile was chosen. `nlctl activation` prints the same, and the companion's RTX tab
  shows the profile and the number of characters kept ready.
- The runtime's two settings travel in a DXVK layer the bootstrap writes at every RTX start:
  `native-loader\remix\memory.conf`.
  - It holds D3D9 options only, so it never mixes the two kinds of loader option
    ([ADR 0062](0062-loader-layers-performance-tiers-and-gpu-dumps.md)).
  - Because DXVK merges every layer and the later one wins, it is listed after the package's layers,
    before the loader's diagnostics layer and the user's `dxvk.conf`.
  - A layer that cannot be written is not listed, with a note: the runtime then sizes its own budgets.
- The profile is independent of the R6 performance tier, which is unchanged.

**Older loaders.** Without the layer, the runtime computes the same budgets itself from the device's
VRAM and the RAM ([ADR 0100](0100-one-copy-and-idle-release-of-game-textures.md)). The hotloader keeps no character ready
when `status.json` has no `activation.memory`.

- The companion never writes `remix.memory_profile`, because a loader before 0.13.0 rejects unknown
  config keys and would stay inactive.

## Consequences

- One rule sizes everything from what the computer has. Larger computers keep more characters ready
  and more textures on the GPU, and nothing assumes 8 GB on a larger card.
- The profile, the override and the layer need loader 0.13.0. The bootstrap reaches players only when
  they install it, while the runtime and the add-ons arrive with the Workshop package.
- The tests are:
  - `test_memory_profile.cpp`: profiles, limits, budgets, override, JSON and layer text.
  - `test_activate.cpp`: the layer's place, no profile without a RAM reader, a failed layer.
  - `activation_integration.py`: the bootstrap writes and lists the layer, and drops one it cannot
    write.
  - The companion stability harness: the menu line in every language.
