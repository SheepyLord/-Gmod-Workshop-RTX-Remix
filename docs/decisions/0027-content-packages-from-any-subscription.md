# 0027: Content packages from any subscribed Workshop item deploy without the allowlist

- Status: Accepted 2026-10-29
- Decided by: the user ("The current allowlist implementation of addon filtering is not accepted.
  Since we can not update the native policy once the user installed the loader dll. [...] Only
  3829070317 contains the Remix payload, other addons could be assumed to be PBR."), Claude choosing how
- Builds on: [0003](0003-native-trust-allowlist.md) (allowlist), [0009](0009-startup-deployment-last-good.md)
  (keep-last-good), [0025](0025-unsubscribe-removes-the-package.md) (unsubscribe)
- Amends 0003: the allowlist still gates native code, but no longer gates content. A package found
  among the subscribed items is opened and may deploy Remix mods and Lua add-ons.

## Context

- **The allowlist is fixed at install.** Players get `native-loader\config.json` with the loader zip and
  do not edit it. A PBR package another player publishes with the agent workflow (the first is
  3829348717, Guinaifen RTX: a Remix mod and a Model Hotloader add-on, 696 MB) never loads for them.
- **What such packages hold.** Measured on the three packages installed here: content packages deploy
  `dds` and `usda` files under `rtx-remix/mods`, and `lua`, `json`, `vtf` and `dat` files under
  `garrysmod/addons`. Only the RTX package (3829070317) carries native code: the runtime payload, and
  DLLs and an EXE in `garrysmod/lua/bin` ([RESEARCH.md](../RESEARCH.md) section 24).
- **Finding them is cheap.** Reading the index of all 677 installed `.gma` archives for
  `native/manifest.json` took 0.29 s (Python, warm cache). GMod itself then reads the same indexes to
  mount them, a few seconds later.

## Decision

1. **Discovery opens the subscriptions.** After the allowlisted sources, discovery adds, in item order:
   - every other installed Workshop item whose one `.gma` lists `native/manifest.json`;
   - every other item a package of the current generation came from, even when its folder is gone,
     so an update in progress keeps it (0009), and an unsubscribe (0025) or a disable in GMod's addon
     list removes it.

   These are content-only candidates. Legacy `_legacy.bin` items are not scanned, and items disabled
   in GMod's addon list are skipped.
2. **Content only.** The planner skips a content-only candidate whose package holds anything else:
   - a runtime, binary modules, patch sets, module overrides, session variables or module dependencies;
   - payload files;
   - root files outside `rtx-remix/mods` and `garrysmod/addons`;
   - an add-on file that GMod's Workshop whitelist (gmad's table) refuses;
   - a mod file that is not Remix data (USD layers, textures, MDL materials, JSON, text).

   The reason says how to allowlist the item, which then deploys it in full.
3. **Where the subscriptions are read from.** Steam's list of libraries is used, as before, only when
   the allowlist names a Workshop item. The subscriptions alone come from the library the game sits in
   (`environment_in_library`), so a game copied outside a Steam library, such as a test's scratch
   folder, scans none.
4. **The off switch.** `"allow": {"subscribed_content": false}` in `config.json` turns this off.
   Every other rule of 0003 stands: the path rules, the off switches, and native code only from the
   allowlist.

## Consequences

- A PBR package published by anyone loads for every player who subscribes to it, with the loader
  0.4.0 or later and no change to `config.json`.
- A content package can still run Lua through its add-on, as any Workshop add-on can once GMod mounts
  it. Its mods are data the allowlisted Remix runtime reads.
- A package that also needs native code shows up as skipped, with the allowlist step in its reason.
- The precedence rules hold: an allowlisted source of the same package id wins, and a content package
  whose root files overlap an active package's is skipped.

## Alternatives considered

- **Keep allowlisting every package.** That is the request this replaces: players cannot edit the
  allowlist.
- **Trust every package, native code included.** Any Workshop item could then run code; native code
  stays opt-in until packages are signed (0003).
- **A list of trusted publishers in the loader.** It would need a loader update for every new author.
