# 0060: The Motion importer tab is the importer

- Status: Accepted 2026-10-31
- Decided by: the user's review ("The model importer menu has a very bad design, it is just a tab
  with an open menu button, wasting all the space and does not ensemble our importer binary exe we
  built"); Claude choosing the implementation for the R4 lead
- Supersedes the Motion importer tab part of [0049](0049-importer-normals-material-labels-and-motion-access.md)
  (a tab whose button opened the existing VMD manager)

## Context

ADR 0049 added a creation tab holding one label and a button that opened the Character Motion
Importer's floating Motion Manager. The add-on also has an in-game importer with the desktop
importer's inputs (`GmodMMDMotionImporter.exe`, `tools/mmd_vmd_importer_gui.py` in its repository),
but the package part had been imported from a clone that stopped before it (318b054, without
`cl_importer.lua`), so the RTX package carried no in-game importer. Both windows built their Derma
inline, into a `DFrame` only. External Models beside the tab fills its whole area: section buttons on
a top bar, a left column (search, folders, list, actions), a right column (preview, settings,
primary actions), on a light page with flat buttons.

## Decision

- Bring the part up to the add-on's `main` (fcd56f4), keeping this repository's translations.
- In the add-on, the windows' builders become `MMDVMDNPC.BuildMotionImporter(parent, opts)` and
  `MMDVMDNPC.BuildMotionManager(parent, opts)`. The windows (`OpenMotionImporter` with
  `mmdvmd_import`, `OpenMotionManager` with `mmdvmd_menu`) call them inside their `DFrame` and keep
  their layout and Derma look. Options: `theme = "light"` (External Models' colours and button
  styles, `MMDVMDNPC.UIThemes`), `columns = true` (the two-column layout), and for the importer
  `onUnavailable` (the window closes and explains when file access goes away; a panel without it
  shows a notice with Resolve and disables its controls). Built importers share their inputs.
- The companion's tab hosts both: section buttons named by the add-on's own phrases (the desktop
  importer's Inputs and Motion Manager tabs), Open in window, and each section built by the add-on
  into the tab. The importer keeps the desktop importer's field order: the inputs on the left; the
  bake, its options, the progress and the log on the right. Import, bake, build and playback stay
  the add-on's code; the tab adds layout only.
- The tab waits for the add-on's builders (the add-on may load later) and falls back to buttons that
  open the windows for an add-on copy without them. One new phrase, "Open in window", in the
  companion's six catalogs; everything else reuses the add-on's phrases.

## Consequences

The tab, both windows and both console commands run on the same builders; a change to the importer
or the library reaches all of them. The add-on now differs from its upstream by these builders as
well as the translations: a later import from its repository has to carry them (or upstream takes
them). The tab cannot show the desktop importer's preview, Garry's Mod folder or `.gma` export, which
the in-game importer does not have. Checked offline under LuaJIT with mocked Derma
([test_motion_tab.py](../../tools/tests/test_motion_tab.py.md)); its pixels and the light theme's
colours on real Derma need a look in the game.

No trust, loader deployment, native allowlist or field-install policy changes.
