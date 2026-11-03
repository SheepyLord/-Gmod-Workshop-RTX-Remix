# nativeloader_guide.lua

The in-game RTX Remix guide. Client only, in RTX sessions (the companion ships in the RTX-only
package). It tells a player who has never used Remix where every setting and function of the RTX
package is, what it does and when to change it, with labeled pictures of each place.

## Opening it

- `nativeloader_guide` opens the first page; `nativeloader_guide <page> [section]` opens a page, and
  scrolls to a section (the console completes the page names: `welcome`, `tab`, `remix_menu`,
  `characters`, `memory`, `troubleshooting`).
- `nativeloader_stability_guide` opens **Performance and memory** (RTX Remix tab > Start here >
  Performance and memory guide).
- RTX Remix tab > Start here > Open the RTX Remix guide.
- By itself once, 8 s after the player spawns in the first RTX session. The marker is
  `garrysmod/data/nativeloader_companion/guide_shown.txt`.

A second opening reuses the open window and shows the page asked for.

## Its size

The guide's sizes are for a 1080-line screen. At every opening its scale is the larger of two numbers:
- **The screen's height over 1080:** 2 on a 3840x2160 screen, 1.33 at 1440 lines. This is what GUI
  scaler add-ons do for the spawn menu. R14's field check had one that, by default, scales only the
  spawn menu (`guiscaler_only_spawnmenu 1`), with fonts of its own; the guide stayed at half the spawn
  menu's size.
- **`DermaDefault`'s height** over a Tahoma 13 font of the guide's own, which `DermaDefault` is in a
  plain game: more than 1 when an add-on enlarges it everywhere.

Below 1.15 counts as 1, the guide is never smaller than 1, and at most 4. A 1920x1080 or smaller game
keeps the plain sizes.

- **Fonts, margins and the window's size** follow that scale; at 1 they are the sizes below.
- **The pictures** grow only by whole steps: 2 from a scale of 1.75. They are drawn point-sampled, so
  their pixels stay sharp, and are smoothed only when made smaller to fit a narrow window.

`nativeloader_guide_scale` (client, archived, default 0) overrides the scale: 0 measures, 1 to 4 sets
it. A change of scale rebuilds the window at the next opening. `NATIVELOADER_GUIDE.scale` and
`.picture_scale` show what the last opening used.

## The window

A `DFrame` (at most 1240 x 940 at scale 1, resizable) with two parts:

- **Left, the contents:** every page with its icon, and under each page its sections (each heading
  with an `id`). A click opens the page, or the page scrolled to the section. Entries wrap, so long
  translated titles stay readable.
- **Right, the page:** its title, then its items, and at the end buttons to the previous and the next
  page.

Items ([`../../nativeloader/guide_pages.lua`](../../nativeloader/guide_pages.lua.md) has the pages):
headings, paragraphs, numbered steps, lists, pictures with their legends, explained words, symptoms
with what to do, tips and cautions, code (the JSON examples), buttons that run a console command
(the eye-white chooser, `nativeloader_status` with the console) and links to another section.

**Pictures** come from `materials/nativeloader/guide/`. Each is drawn at its own size, as it was
captured, and only made smaller when the page is narrower than the picture; the pictures are at
most 900 pixels wide, so in a 1280x720 game they are not shrunk either. Under each picture its legend
lists the numbered badges in it: a green badge with the number, then what that control does. The
numbers need no translation; the legend text is translated. A missing picture is left out with its
legend, so the guide also works from an add-on copied without its materials.

Fonts: Tahoma (with `extended`, as `DermaDefault`, so Windows supplies the glyphs of the other
languages), 27 px titles, 20 px headings, 15 px text.

## Advice that depends on the loader

On each opening the guide reads DATA `native-loader/status.json`. Items marked `r6` show only when it
is schema 1 with an `activation.performance_tier` object (loader 0.11.0 or later), `r13` only when
`activation.memory` is there too (0.13.0 or later); `legacy` and `pre13` items show otherwise. Workshop
updates do not update `winmm.dll`, and an older loader rejects newer configuration keys and starts
without RTX, so tier, memory-profile, memory-history, session-folder and GPU-dump instructions appear
only for a loader that has them; an older loader gets the bootstrap-update and manual-copy advice. The
R6 complete minimal JSON example keeps the shipped `allow` list, tells customized installs to keep
their own entries, and warns that invalid JSON turns RTX off; JSON is not translated.

All versions say to save frame generation off and to copy `status.json`, `session.json`, the VRAM CSV
files and the runtime logs **before restarting**: the next start rewrites both JSON reports, and the
evidence collector does not copy them. GPU dumps use the persistent `next_start` value; deleting
`native-loader/remix/gpu-crash-dumps.used` asks for another diagnostic start. The same player advice is
in [`docs/STABILITY.md`](../../../../../docs/STABILITY.md).

The Remix-menu advice follows [ADR 0044](../../../../../docs/decisions/0044-remix-settings-persistence.md):
the tab's Remix settings apply to the session, Remix's Save keeps them, the startup replay is opt-in, and
a numeric override is used only while selected. It names the runtime's static button **Migrate developer
settings to rtx.conf** and warns against it (map-specific values would apply to every map).

## Text and translations

Page titles, headings, paragraphs and legends are `N("...")` in the pages module and translated with
[`../../nativeloader/i18n.lua`](../../nativeloader/i18n.lua.md) when the page is drawn; the window's
own words (`Contents`, `Previous: %s`, `Next: %s`) are `L("...")`. Translation provenance is kept in
[`companion/i18n/README.md`](../../../../i18n/README.md), since extraction regenerates PO comments.

What the open page shows is recorded in `NATIVELOADER_GUIDE.shown` (`id`, `title`, `texts`, `images`),
in drawing order, for the tests and the in-game check. No file, setting or Remix option is written
by the guide (the first-session marker aside).

## History

- R6: `nativeloader_stability_guide` and the Memory and stability page; the loader-dependent advice.
- R14 (first pass): annotated screenshots and a Glass section.
- R14-H: the redesign. Six task-ordered pages (Welcome; The RTX Remix tab, one section per group; The
  Remix menu (Alt+X); Characters; Performance and memory; Troubleshooting), a contents list instead
  of tabs, step lists and legends, and sharp captures with numbered badges
  ([`tools/guide_annotate.py`](../../../../../tools/guide_annotate.py.md) from
  [`tools/qa/guide_shots.lua`](../../../../../tools/qa/guide_shots.lua.md) captures). The Memory and
  stability page became Performance and memory.

Tests: [`tools/tests/test_companion_guide.py`](../../../../../tools/tests/test_companion_guide.py.md)
(every page and section in every language and for every loader, the pictures against their specs and
budget) and [`tools/tests/test_companion_stability.py`](../../../../../tools/tests/test_companion_stability.py.md)
(the loader-dependent advice).
