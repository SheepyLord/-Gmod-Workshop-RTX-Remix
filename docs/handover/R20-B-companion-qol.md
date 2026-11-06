# R20-B: the upscaling hint and the sky's new defaults (items 45 and 49)

Worktree `out/worktrees/r20-qol`, branch `r20-qol`, from `r20-int`. Implementer: Codex
(gpt-6.1-sol). Read first: [R20-plan.md](R20-plan.md) (the user's words and the rules for every task),
[AGENTS.md](../../AGENTS.md), [companion/README.md](../../companion/README.md),
`companion/nativeloader/lua/autorun/nativeloader_sky.lua.md`,
`companion/nativeloader/lua/autorun/client/nativeloader_menu.lua.md`,
`companion/nativeloader/lua/autorun/nativeloader_defaults.lua.md`,
[ADR 0020](../decisions/0020-classic-rtx-settings-as-defaults.md),
[ADR 0031](../decisions/0031-physical-sky-time-and-weather.md).

## The user's items

> 45. Add a game hint to remind user to enable frame generation / up scaling if they didn't enable it
> when the game start.
>
> 49. For the sky and weather, default the time passes to be on, default a day is 20 minutes.

## Facts

- The RTX tab reads and writes the runtime's `rtx.upscalerType` ("Upscaler") and
  `rtx.frameGenerationType` ("Frame generation") through the RTX fixes' `RemixConfig` API
  (`nativeloader_menu.lua:76-81`). Remix graphics presets apply again at every start, so read the
  effective values, after the preset is applied.
- `nativeloader_sky.lua` creates `nativeloader_sky_time_passes` (default `"0"`) and
  `nativeloader_sky_day_minutes` (default `"30"`) as archived client settings, so players who never
  touched them have the old defaults saved. `nativeloader_defaults.lua` already applies first-run
  defaults once, only where a setting still holds its default (ADR 0020).

## What to build

1. **The hint (45).** At the start of the game, in an RTX session, once the runtime's settings can be
   read after the first map loads: when upscaling is off, or frame generation is off, show a game hint
   in the style of sandbox's own hints (`notification.AddLegacy(..., NOTIFY_HINT, ...)` with the hint
   sound) that says what is off and how to turn it on (the RTX Remix tab's Remix settings, or Alt+X;
   both are named the way the tab and the guide name them). Separate wording for upscaling off, frame
   generation off and both. Rules:
   - Once per game start (not at every map change), a little after the map is drawn so it is read.
   - Suggest only what the computer can use: frame generation and DLSS need an NVIDIA RTX GPU, and
     DLSS frame generation an RTX 40 or 50; find what the runtime or `native-loader/status.json`
     (`activation.performance_tier.adapter`, `gpu_vendors`) tells you, and read how the tab's choices
     are offered. If the state cannot be read, show nothing: never a false hint.
   - Respect `cl_showhints 0`; add a client setting to turn this hint off, as a translated checkbox in
     the RTX tab next to the upscaler settings.
2. **The sky's defaults (49).** `nativeloader_sky_time_passes` defaults to `"1"` and
   `nativeloader_sky_day_minutes` to `"20"`. Players who still hold both old defaults (`"0"` and `"30"`)
   get the new ones once, through a one-time migration with a marker (so a player who turns time off
   afterwards keeps it off); anyone who changed either keeps their values. Check every place that
   mirrors these defaults (the panel and its slider ranges, the guide pages, help texts, the R16 map
   start, QA probes, tests, docs) and keep them consistent.
3. Translations of every new text into the six catalogs.
4. Docs: ADR 0117 (the hint and the new sky defaults with the migration), the `.md` beside every
   script you change, CHANGELOG `### R20`, COMPONENTS if a file is added, TESTING.

## Tests and evidence

- Lua harness tests (see `companion/tests` and `tools/tests` for the existing harnesses): the hint's
  decisions (each combination, unsupported GPU, unreadable state, `cl_showhints 0`, the opt-out, once
  per start) and the migration (old defaults move once; changed values stay; the marker holds).
- PoC (under the lock): a start with upscaling and frame generation off shows the right hint once; a
  start with both on shows none; the sky panel shows time passing and 20 minutes on a fresh profile
  and after the migration. Screenshots under `out\r20b\`. Do not save Remix settings while testing
  (never write `user.conf`); restore whatever you changed.

## Your paths

`companion/nativeloader/lua/autorun/nativeloader_sky.lua`, `nativeloader_defaults.lua`, a new hint file
under `companion/nativeloader/lua/autorun/client/` (or `nativeloader.lua`'s neighbours, not
`nativeloader.lua` itself, which R20-A changes), `nativeloader_menu.lua` (only the hint's checkbox,
near the upscaler rows), `companion/nativeloader/lua/nativeloader/guide_pages.lua` for the sky text,
`companion/i18n/`, `companion/tests/`, `tools/tests/` for your tests, the docs named above.
