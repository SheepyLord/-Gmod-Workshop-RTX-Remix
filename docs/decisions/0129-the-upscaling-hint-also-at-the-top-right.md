# 0129: The upscaling hint also shows at the top right for fifteen seconds

- Status: Accepted 2026-11-07 (R22, the user's item 52.2; amends [ADR 0117](0117-startup-upscaling-hint-and-sky-defaults.md))
- Context: the user: "The hints to enable framegen are not obvious, while keeping the current game hint
  approach, also add hints that show on top right on user's like the Hotloader's warning. This warning
  expires after 15 seconds."

## Decision

1. The startup hint ([ADR 0117](0117-startup-upscaling-hint-and-sky-defaults.md), live state from
   [ADR 0123](0123-live-upscaling-readback.md)) keeps its sandbox notification and sound. When it shows,
   the same text also shows in a notice at the top right, like the Model Hotloader's: a dark panel with
   the green RTX Remix accent, the title "RTX Remix", the hint's text and a close button.
2. It fades in, stays 15 seconds and fades out. Its decision, timing and once-per-start marker are the
   hint's. The RTX tab's checkbox (`nativeloader_upscaling_hint`) turns both off. `cl_showhints 0` turns
   off sandbox hints, and so the sandbox hint, but not the notice, which is not one: R22's PoC check found
   `cl_showhints "0"` in the user's own game (`garrysmod/cfg/client.vdf`, which Steam Cloud does not
   carry), so that game had shown no advice at all. This amends ADR 0117's "`cl_showhints 0` suppresses
   the hint" for the notice.
3. Its size and fonts scale with `ScrH()/1080` (at least 0.65), as the companion's other windows do for
   4K. It sits 20 px from the right and 40 px from the top, below any notice-sized panel already in that
   corner (the Hotloader's), never below a full-screen menu.
4. It needs no new text: the title is the product's name, the body the hint's translated text.
5. A notice that cannot be made never costs the hint (`pcall`).

## Consequences

The advice is seen at the corner a player watches, while the sandbox hint keeps its place and sound. A
player who turned sandbox hints off still sees the notice once per start while upscaling or frame
generation is off; the RTX tab's checkbox is the way to turn the advice off.
