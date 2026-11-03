# R14 report: noclip and glass, and the guide

Status: **done**

Scheduled start 2026-11-03 (task `r14-after-r13`, after R13's report said done). Plan: [R14-plan.md](R14-plan.md).

## Item 41: noclip and glass

`glass/addon/lua/nlglass/server.lua`: new `S.Ghost(body)` (a player whose move type is noclip). `S.Body` and
the `SetupMove` sweep return early for it, so no contact path (touch, physics contact, sweep) fractures a pane.
The test harness got `GetMoveType` and `MOVETYPE_NOCLIP`, and the `bodies` scenario a noclip case.

## Item 5: the guide

- Real captures: `tools\qa\guide_shots.lua` through `tools\poc_session.py` (field install, `--reference`,
  nothing written) opens the spawn menu's RTX Remix tab and its panels; `tools\guide_annotate.py` draws numbered
  arrows (also on the existing Alt+X screenshot). Images: `tab_overview`, `remix_menu_marked`,
  `remix_settings`, `glass_settings`, `guide_window` (the last is not used by a page yet).
- `nativeloader_guide.lua`: a "Where to find things" section, a legend under each picture naming each number,
  a Glass section; images take an optional height.
- Six catalogs updated by Claude (no Codex use; the user allowed Codex only for translation and text checks,
  and the catalogs were small).

## Evidence

`tools\test.ps1 -Config Release`: all checks passed (Python, repo conventions, 26 CTest).

## Open issues

- The Start here, Sky and weather, Base Options and Flashlight panels were captured but the accordion
  sidebar left the previous panel showing, so they have no annotated picture yet.
- A Codex text-validation pass of the English guide wording was not run.
- The new guide pages were not viewed in-game: the field's installed package holds the previous guide until
  the Workshop update arrives and is started twice.
