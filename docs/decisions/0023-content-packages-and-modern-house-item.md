# 0023: Content packages carry Remix mods and their Lua; Modern House RTX is its own Workshop item

- Status: Accepted 2026-10-29
- Decided by: the user ("Please package and upload modern_house for testing. Poolday don't need to be
  shipped. Water and Emissives are from remix repo years ago, please ship if they actually affect the
  game."), Claude choosing how and measuring which mods affect the game
- Builds on: [0003](0003-native-trust-allowlist.md) (allowlist), [0011](0011-lua-addon-folders.md)
  (Lua add-on folders), [0013](0013-rtx-only-addons-hidden-without-rtx.md) (RTX-only add-ons hidden
  without RTX), [0015](0015-workshop-route-for-native-packages.md) (the Workshop route),
  [0016](0016-one-workshop-item-kept-current.md) (one item kept current)

## Context

- **GMod cannot mount Remix mods.** A Remix mod is `.usda` and `.dds` files, outside GMod's file
  whitelist, and GMod refuses an archive that holds one (0015). The loader can deploy such files:
  `rtx-remix/mods/<mod>` (kind `root-files`) and Lua add-on folders (kind `lua-addon`).
- **Modern House RTX** is the user's remaster of another author's Workshop map (3495468649):
  - a Remix mod: 490 PBR textures, upscaled from the map's own, 3.32 GB;
  - a Lua add-on: sky, 341 lights, mirrors and fixes.

  It is 2.3 times the size of the RTX package and matters on one map only. Its sources are on the
  fixes fork's branch `claude/modern-house-rtx`.
- **The classic install's other Remix mods**, measured in the field ([RESEARCH.md](../RESEARCH.md)
  section 20):
  - **Emissives** replaces HL2's fluorescent tube light (`lights_florescent01a`, used in gm_construct
    and elsewhere): with it the lights light the room, without it the room is less than half as
    bright.
  - **Water** replaces 29 water textures that the classic settings put on `rtx.ignoreTextures`, so
    their draws never reach the renderer and the mod never applies. A/B in the pool rooms: no change.
  - **Poolday** (the pool rooms): the user does not want it shipped.

## Decision

1. **Content packages.** [`tools/package_content.py`](../../tools/package_content.py.md) packages Lua
   add-on folders and Remix mod folders, with no native code. Kinds are `lua-addon` and `root-files`,
   both `replace-owned`; `--requires-remix` hides RTX-only Lua without RTX. Such a package is
   deployed like any other: only from an allowlisted source (0003).
2. **Modern House RTX is its own package (`modern-house-rtx`) and its own hidden Workshop test item,
   3829275998.** It is not part of the RTX package:
   - players of other maps should not download 3.3 GB;
   - making it public is the user's decision (AGENTS.md rule 5).

   It is uploaded by hand with `gmpublish` (create, then `update -id 3829275998`), not by the `main`
   hooks: its inputs live in the fork's branch.
3. **Emissives ships in the RTX package** as a fourth part of [`workshop.json`](../../tools/workshop.json):
   a content package built from the classic install's folder, pinned in
   `out\packages\round3\emissives.gma` like the runtime part. Water and Poolday do not ship.

## Consequences

- To play Modern House RTX a player subscribes to the map and to 3829275998 and allowlists the item in
  `native-loader\config.json`. While the item is hidden only the user can subscribe.
- Updating it: rebuild with `package_content.py`, then `gmpublish update -id 3829275998 -addon <gma>`.
- The Emissives part changes only when its archive is rebuilt. The deployed mod is owned by the loader,
  so a player's hand-copied `Emissives` folder with the same files is adopted, and a different one
  blocks the package until it is moved.
- The textures of Modern House RTX are derived from another author's map. The item stays hidden until
  the user decides otherwise.

## Alternatives considered

- **Modern House inside the RTX package:** every subscriber would download 3.3 GB for one map.
- **A Lua-only Workshop item that GMod mounts:** the Remix mod would still need the loader, and the
  Lua would run without RTX.
- **Ship Water too:** with the shipped settings it never draws.
