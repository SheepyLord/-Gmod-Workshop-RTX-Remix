# 0022: The companion guards RTX sessions, gathers the RTX menus and carries the guide

- Status: Accepted 2026-10-29
- Decided by: the user (asked to organise the RTX menus, expose more settings, add an illustrated
  guide, and harden Remix against conflicting add-ons), Claude choosing how
- Builds on: [0013](0013-rtx-only-addons-hidden-without-rtx.md) (the companion is in the RTX-only
  package, so it runs only with RTX), [0020](0020-classic-rtx-settings-as-defaults.md)

## Context

- **The audit of the user's add-ons** ([RESEARCH.md](../RESEARCH.md) section 19) found Lua that undoes
  what an RTX session needs:
  - FPS Boost sets `r_threaded_particles 1` and the queued-rendering variables at every client start,
    after the session cfg;
  - Draconic Base turns motion blur back on every second;
  - several add-ons draw stock post-processing.

  Those shaders cannot run at shader model 0, and what remains, a screen copy and a full-screen quad,
  covers the path-traced image.
- **The RTX add-ons' settings are spread** over four Utilities categories ("RTX", "RTX Remix", "RTX
  Remix - API Lights", "Glass Rewrite Remixed"), and expose few Remix options.
- **The fixes' Lua is GPL-2.0** and is not edited here.

## Decision

The companion (MIT, this repository) gets three client files, all only in RTX sessions:

1. **A guard** (`_nativeloader_guard.lua`), in place before other add-ons' autorun files.
   - Lua writes that would change the session console variables, or switch motion blur on, are
     dropped and named in the console once.
   - The stock post-process functions and `halo.Render` become no-ops.
   - The RTX fixes and the companion are exempt, and `nativeloader_guard 0` switches it all off.
   - Typing in the console is not affected.
2. **One "RTX Remix" spawn-menu tab** (`nativeloader_menu.lua`).
   - The fixes' panels are moved into it as they register, unchanged, under "Rendering", "Lights" and
     "Water and glass".
   - It adds "Start here" and "Remix settings": common Remix options through the fixes'
     `RemixConfig.SetConfigVariable`.
   - Values chosen there are kept as client settings and applied at every start. Empty leaves the
     option to Remix's files.
3. **An illustrated guide** (`nativeloader_guide.lua`, `nativeloader_guide`). It opens once on the
   first RTX session, and covers the Remix menu, saving, settings, lights and troubleshooting.
   - Its screenshots are small JPEGs under `materials/nativeloader/guide/`, taken in our own test
     sessions. They are documentation the companion ships, not game files, runtime files or build
     outputs.
   - So they are kept in git with the companion, as an exception to AGENTS.md rule 6.

## Consequences

- An add-on that fights the session is named in the console, and the picture keeps Remix's output.
- An add-on that needs post-processing in an RTX session loses it. `nativeloader_guard 0` gives it
  back.
- Settings from the "Remix settings" panel go into Remix's user layer every start. If the player also
  presses Save in Remix's menu, they end up in `user.conf` too, with the same values.
- Other add-ons' spawn-menu panels are untouched. Only the four known categories move.

## Alternatives considered

- **Editing the fixes' menu code.** That is the GPL fork. Moving the panels at registration needs no
  change there, and keeps working when the fork changes its panels.
- **Blocking every `render.DrawScreenQuad` and `render.RenderView`.** Too broad: the fixes' portals
  and add-ons drawing into their own render targets need them. They are left for a later, targeted
  rule.
