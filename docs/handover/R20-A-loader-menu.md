# R20-A: the loader update reminder and the multiplayer warning (items 46 and 50)

Worktree `out/worktrees/r20-menu`, branch `r20-menu`, from `r20-int`. Implementer: Codex
(gpt-6.1-sol). Read first: [R20-plan.md](R20-plan.md) (the user's words and the rules for every task),
[AGENTS.md](../../AGENTS.md), [ADR 0050](../decisions/0050-startup-text-and-main-menu-diagnostics.md),
[ADR 0052](../decisions/0052-scoped-rtx-multiplayer-bootstrap.md), [ADR 0056](../decisions/0056-guard-and-startup-fallbacks.md),
`loader/proxy/ui/mainmenu.js.md`, `loader/proxy/ui/read_notices.lua.md`, `loader/proxy/README.md`,
`companion/nativeloader/lua/autorun/client/nativeloader.lua.md`, [docs/PACKAGE_FORMAT.md](../PACKAGE_FORMAT.md).

## The user's items

> 46. The workshop addon should record the most recent version of the loader dll. If user's dll is
> outdated, the main menu should show a window to remind user to re-download and update the loader.
>
> 50. In multiplayer tab, when user click the play multiplayer, display a warning that server might
> forbid custom shading like Remix and Reshade, and the performance and stability is not grantee
> especially if you don't have the PBR resource for the map that the server is running installed, and
> the dev take no responsibility for any consequences of using this addon. User will have to agree to
> continue to server browser, else return to the main menu. This warning could be dismissed permanently.

## Facts

- The loader's version is the top-level `CMakeLists.txt` project version, 0.14.0, the current
  release (https://github.com/SheepyLord/Gmod-Workshop-RTX-Remix/releases, public; a `v*` tag makes a
  release through `build.yml`). This round's loader is **0.15.0**: bump it.
- The main menu is GMod's HTML menu (stock files in the PoC: `garrysmod/html/menu.html`,
  `html/template/main.html`, `html/js/menu/*.js`). The loader serves a generated copy of
  `control.Menu.js` with `loader/proxy/ui/mainmenu.js` appended (`loader/proxy/presentation.cpp`,
  `presentation_data.h.in`, `labels.json` for the text in every menu language). The stock home page
  links the server browser as `<a ng-href="#/servers/" ng-Localize="'find_mp_game'">` ("Find
  Multiplayer Game"); the user calls it "play multiplayer". The same HTML menu is the in-game pause
  menu.
- The manifest parser refuses unknown keys (`only_keys`, `loader/core/src/manifest.cpp:273`): the
  record must not be a new manifest key, or every older loader would refuse the whole package.
- Every loader writes `native-loader/status.json` (DATA) with `loader_version`; the companion's
  `nativeloader.lua` reads that file and already shows an update notice for Workshop packages.
- Loaders before 0.15.0 cannot show anything new in the main menu: their menu script is compiled in.

## What to build

1. **The record of the newest released loader.** One file in this repository holds the newest loader
   that is *released* on GitHub: its version and its release page
   (`https://github.com/SheepyLord/Gmod-Workshop-RTX-Remix/releases/tag/v<version>`). It is changed by
   hand in the release's own commit, after the GitHub release exists, never derived from the CMake
   version (the package is published from `main` before a release is out). For this round it stays
   at **0.14.0**; Claude moves it to 0.15.0 when the release is published. The RTX package carries
   it where both the loader and the companion can read it (suggestion: a file of the companion add-on,
   which the loader deploys as `garrysmod/addons/nativeloader`). Tests: the record's version is never
   newer than the CMake version; its URL matches the pattern above. Document the release step (set the
   record, commit, push `main`) where the release procedure is described (TESTING.md and
   `tools/ci/README.md`, or wherever the R19 release steps are written down).
2. **Trust.** Only the record that the RTX runtime package (the allowlisted package that provides the
   runtime) deployed counts; a content package from any subscription must never be able to show this
   window or choose the link. Validate strictly: size-bounded JSON, `MAJOR.MINOR.PATCH` with an
   optional pre-release (semver ordering), the URL exactly of the pattern above. Anything else: no
   reminder.
3. **The main-menu reminder (loader 0.15.0 and later).** When the record is newer than the running
   loader, the home screen shows a modal window once per start: what the player runs, what is out,
   what to do (download `winmm.dll` from the release page, replace `bin\win64\winmm.dll` in the game
   folder, restart; the Workshop package updates by itself, only this file needs them). Buttons:
   **Open the download page** (opens only the recorded URL through the menu's `gui.OpenURL`),
   **Later** (this start), **Don't remind me about <version>** (remembered; a newer version asks
   again). No network request of our own: the record arrives with the package Steam downloaded.
4. **The in-game reminder for older loaders.** The companion (client Lua, `nativeloader.lua`) shows the
   same reminder in game once per start, after the first map, when `status.json`'s `loader_version` is
   older than the record **and** older than 0.15.0 (a 0.15.0 or later loader reminds in the main menu
   only). Same buttons; "don't remind me" remembered per version. A Derma window that scales with
   `ScrH()/1080` (the field runs 3840x2160 with GUI scaling only in the spawn menu). Translated through
   the companion catalogs.
5. **The multiplayer warning (loader 0.15.0).** Every way from the menu into the server browser (the
   home page link and any other route or link to `#/servers/`, in the main menu and in the pause menu)
   first shows a modal warning, unless the player dismissed it for good. Draft text (keep every point;
   improve the English if you like):
   - Title: *Before you join a server*
   - *Many servers do not allow custom renderers and shaders such as RTX Remix and ReShade, and some
     kick or ban players who use them. Check a server's rules before you play.*
   - *Performance and stability are not guaranteed online, especially without the PBR resources (the
     RTX content) for the map the server runs.*
   - *You use this add-on on servers at your own risk: its developers take no responsibility for any
     consequences.*
   - Checkbox *Don't show this again*; buttons **I understand, continue** (the server browser opens;
     the checkbox, if ticked, is remembered) and **Back** (the home screen).
   Remember the dismissal across starts in the menu Lua realm through the stock bridge with a fixed
   snippet (for example a small file under DATA `native-loader/`; never GMod's cloud `config.cfg`,
   never `native-loader/config.json`). If anything fails (the stock menu changed, the bridge is
   missing), the browser must still open: never trap the player. When the loader runs without RTX
   (the menu is not decorated), nothing changes.
6. Every new menu text in all of `labels.json`'s languages; the companion's in all six catalogs. The
   project link already points at the renamed repository.
7. **Docs and records.** ADR 0115 (the record and the reminders: where it lives, who may set it, the
   release step) and ADR 0116 (the multiplayer warning). CHANGELOG `### R20`, `mainmenu.js.md`,
   `read_notices.lua.md` if it changes, `nativeloader.lua.md`, `dist/README-native-loader.txt` (the
   player README: the reminder, how to update, the warning), PACKAGE_FORMAT.md if the package gains the
   file, COMPONENTS, TESTING.

## Tests and evidence

- Unit tests: the JS harness (`tools/tests/menu_diagnostics_harness.js`, `test_presentation_ui.py`):
  reminder shown for an older loader and not for an equal or newer one, pre-release ordering, invalid
  record or foreign URL ignored, Later, Don't remind (per version), the warning intercepting every
  server route, Continue, Back, the remembered dismissal, the fail-open path. C++ tests for reading
  and trusting the record (`loader/proxy/tests`, `loader/tests`). A Lua harness for the companion's
  in-game reminder (versions, once per start, remembered choice).
- PoC: build and install your loader into the PoC (`tools\workflow.ps1 -SkipTests -Install
  H:\SteamLibrary\steamapps\common\GarrysMod_PoC`, under the lock; restore the PoC's previous
  `winmm.dll` and package state when you release it). Show the reminder with a test record newer than
  0.15.0 in a local package, the warning on Find Multiplayer Game (agree, back, dismissed for good,
  after a restart), in English and in Simplified Chinese, at 1600x900 and 3840x2160 windowed if the
  machine allows. The in-game reminder with a status.json-equivalent older loader (simulate it; do not
  install an old loader into the field). Screenshots under `out\r20a\`.

## Your paths

`loader/`, the top-level `CMakeLists.txt`, `dist/`, `companion/nativeloader/lua/autorun/client/nativeloader.lua`
(+ `.md`), new companion files you need for the record, `companion/i18n/` entries for your text,
`tools/build_package.py` / `tools/package_fixes.py` and their tests only if the record needs them,
`tools/tests/` for your tests, the docs named above.
