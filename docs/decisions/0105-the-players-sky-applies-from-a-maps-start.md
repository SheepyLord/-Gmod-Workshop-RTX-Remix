# 0105: The player's own time and weather apply from a map's start, also where the map's add-on sets a sky

- Status: Accepted 2026-11-04 (supersedes rule 5 of [ADR 0031](0031-physical-sky-time-and-weather.md)
  for a sky that does not follow the map)
- Decided by: the user's bug report, item 44 of R16: "The weather and daytime setting is not applied
  when user enters the map, user has to open the menu and go to the setting panel to activate."

## Context

ADR 0031 rule 5 lets a map's own sky add-on keep its sky until the player changes a sky setting in the
session; Modern House RTX is such an add-on, recognised on `modern_house`. The companion's sky applied
at the start of every other map in the tests (PoC: a new game, a map change, a two-player listen
server; the field: gm_construct with the user's settings and add-ons), traced option by option
(`out/r16` in the `r16` worktree). On `modern_house` with the user's settings (Follow the map's sun
unticked, 09:48 with the clock running, clear weather), the companion sent its sky at InitPostEntity,
Modern House RTX set its afternoon 5.8 s later (sun 21 degrees at 222, its clouds and fog), and the
companion then stood aside: its clock stood still and the player's daytime and weather showed only
after a setting was changed in the Sky and weather panel. Modern House RTX loads after InitPostEntity,
so the wrapper that follows its `ApplySettings` was installed only by the 10 s timer.

## Decision

- **A sky that does not follow the map** ("Follow the map's sun" unticked: the player chose a time) is
  the companion's from the map's start, also on a map whose add-on sets a sky. The player's time,
  direction, moon, stars and weather apply at once, and the add-on's later settings of its sky are put
  back in the same call (its `ApplySettings` wrapped) or within 10 s (an add-on that announces itself
  only through `NativeLoaderSkyOwner`), as after a take-over before.
- **A sky that follows the map** (the default) keeps such an add-on's sky, as ADR 0031 decided, until
  the player changes a sky or weather setting in the session. Following the map means following its
  add-on.
- The add-on's `ApplySettings` is wrapped from the sky's first tick after it exists, not only by the
  10 s timer.
- The panel says so: "Follow the map's sun" names the add-on's sky it keeps, and the note on such a
  map says when the add-on's sky stays.

## Consequences

- The user's settings apply on `modern_house` from the start. A player who never chose a time still
  sees Modern House RTX's afternoon.
- Ticking "Follow the map's sun" during a session on such a map does not hand the sky back to the
  add-on: any change takes the sky over, as before. The add-on's sky returns at the next map start.
- No change on maps without such an add-on.

## Alternatives considered

- **Always take over at the start**: the add-on's designed sky would never show, though following the
  map is the default.
- **A separate checkbox** ("let a map's add-on set the sky"): a second setting saying what "Follow the
  map's sun" already says.
- **Re-sending the whole sky several times in the first minute on every map**: no other map changed the
  sky after the companion's 5 s re-send in the traces, and R3-010 decided not to take back what another
  add-on sets later.
