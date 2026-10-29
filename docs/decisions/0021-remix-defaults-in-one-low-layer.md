# 0021: The package's Remix defaults are one low layer; the player's files stay on top

- Status: Accepted 2026-10-29
- Decided by: Claude, from the user's report that Remix settings "got reset" every time the game
  reopened, and from reading the fork's config code
- Supersedes: the layering assumption of [0008](0008-activation-at-startup.md), that a
  comma-separated `DXVK_RTX_CONFIG_FILE` list is read weakest first. Refines
  [0020](0020-classic-rtx-settings-as-defaults.md) decision 1.

## Context

The runtime fork (`dxvk-remix-gmod`, branch `gmod-1.6.1`) reads layer lists differently from what
ADR 0008 assumed ([RESEARCH.md](../RESEARCH.md) section 19):

- **`rtx.*` options: the first entry is the strongest.** In a `DXVK_RTX_CONFIG_FILE` or
  `DXVK_CONFIG_FILE` list, earlier entries get names like "00_Remix Config", and the last gets the
  plain name. Layers of one priority sort alphabetically, and the first wins
  (`rtx_option_layer.cpp:49-61`, `rtx_option_constants.h:159-164`).
- **Remix's Save writes the last `DXVK_RTX_CONFIG_FILE` entry.** That was the player's root
  `rtx.conf`, which is also the weakest. A saved setting therefore lost to the package's layer at the
  next start, which is the reported "reset".
- **Priorities:** `dxvk.conf` layers are priority 1, `rtx.conf` layers 3, `user.conf` 0xFFFFFFFE.
  A preset other than Custom writes above even `user.conf`, at every start.
- **`d3d9.*` and `dxvk.*` keys** come from one merged config in which the last file wins.
- **Lists of 260 characters or more are ignored:** the runtime reads the variable into a 260-character
  buffer and falls back to the bare root conf.
- **Texture-hash lists** (`rtx.*Textures`) combine across layers as sets: a layer adds hashes and
  removes its `-0x...` ones.
- **`DXVK_FORCE_WINDOWED=1`** keeps every device creation and Reset windowed, so the exclusive
  fullscreen path that crashed the field test ([0018](0018-rtx-sessions-in-a-borderless-window.md))
  is never taken.

## Decision

1. **A runtime package ships its Remix defaults as one `dxvk_conf_layers` file** and no
   `rtx_conf_layers`.
   - The loader then sets `DXVK_CONFIG_FILE=<payload>/config/dxvk/01_<name>.conf,dxvk.conf`, at
     priority 1.
   - It leaves `DXVK_RTX_CONFIG_FILE` unset, so Remix uses only the player's root `rtx.conf`. That file
     is both the Save target and stronger than the package.
   - `user.conf` stays above both.
2. **The defaults file is merged** by [`tools/remix_defaults.py`](../../tools/remix_defaults.py.md)
   from the classic install's `dxvk.conf`, `rtx.conf` and `user.conf`, weakest first.
   - Later files win, and texture-hash sets combine like Remix layers.
   - The merged layer reproduces every effective value the classic install has at start-up, all
     texture lists included.
3. **The runtime package sets `DXVK_FORCE_WINDOWED=1`** in its `remix.env`. A package value fills an
   absent variable only, so a player can still set it to 0.
4. **The loader notes a layer list of 260 characters or more** in the session notes, which
   `status.json` and `nativeloader_status` show.

## Consequences

- What a player saves in the Remix menu now wins at the next start, both in `rtx.conf` and in
  `user.conf`. The package's values are defaults only.
- Single settings still come back if the graphics preset is not Custom: that is the runtime's preset
  logic. The defaults set Custom, and the in-game guide explains it.
- No loader change is needed for the layout. Loaders 0.2.0 and 0.2.1 already set exactly these
  variables for such a package.
- The one-file layout keeps `DXVK_CONFIG_FILE` near 120 characters, far below the limit.
- `RemixConfig.GetConfigVariable` in the RTX fixes reads only the root `rtx.conf`, so it sees no
  package defaults. Only debugging tools in the fixes use it.

## Alternatives considered

- **Put the player's file first in `DXVK_RTX_CONFIG_FILE`.** The Save target is the last entry, so
  saving would write into the package's payload, which the next start refuses as changed.
- **Fix `makeLayerName` in the fork** so earlier entries are weaker. That is right, but it only
  helps a runtime built after the fix. The one-layer layout works with the runtime as shipped.
- **Two layers (classic `rtx.conf` and classic `user.conf`).** With the first entry strongest, the
  classic `rtx.conf` would beat its own `user.conf`, the opposite of the classic install. Three files
  would also pass 260 characters with real version folders.
