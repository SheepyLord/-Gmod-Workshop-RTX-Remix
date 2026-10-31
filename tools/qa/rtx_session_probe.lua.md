# rtx_session_probe.lua

Client Lua for `poc_session.py run --lua tools\qa\rtx_session_probe.lua --lua-shots 90`: reports what
the loader's companion set up in an RTX session, then tours two views.

Prints short lines (the game's console cuts a line at about 4 KB):

- `NL_QA_GUARD {...}`: the render guard's version, installation (`early`, `autorun` or `verified
  multiplayer bootstrap`), whether it is on, and its blocked/error/cleanup counts, then samples of each
  (`NL_QA_GUARD_BLOCKED`, `NL_QA_GUARD_ERRORS`, `NL_QA_GUARD_CLEANUP`);
- `NL_QA_PARTS {...}`: map, DirectX level, which companion parts and add-ons are loaded (`sky`, `i18n`,
  `mmdhl` Model Hotloader, `advmat` Advanced Material Editor, `motion` the Character Motion Importer),
  pseudoplayers, the weapon;
- `NL_QA_CVARS {...}`: the convars the guard, the player shadow and hardware skinning depend on;
- `NL_QA_HOOKS [...]`: every hook whose name contains `nativeloader`, twelve per line;
- after selecting the toolgun: `NL_QA_WEAPON`, the guard counts again, and the toolgun redraw's own
  status (`nativeloader_toolgun_status`: captures, draws, texture, triangles, error; a healthy session
  shows draws rising and no error).

Screenshots (`NL_SHOT`): `spawn`, then `toolgun` (crop the screen to check that its scrolling text is
sharp, ADR 0057). Side effects: selects a weapon; changes nothing archived. Exit codes: none (client
Lua); the session driver records whether the game quit normally.
