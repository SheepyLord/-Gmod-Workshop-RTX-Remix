# guide_input.py

Presses keys (and posts clicks and wheel turns) in Remix's own menu (Alt+X) for the RTX Remix guide's
pictures. Remix's menu is not part of GMod's Lua UI, so [`guide_shots.lua`](guide_shots.lua.md) cannot
operate it; it prints what it needs instead, and this script does it by posting window messages to the
game window, which the runtime fork passes to its menu when no raw input arrived just before
([RESEARCH.md](../../docs/RESEARCH.md), sections 25 and R14-H).

Run it beside a capture session (it waits for the game to start and ends with it):

```powershell
Start-Process python -ArgumentList 'tools\qa\guide_input.py'   # or any background shell
python tools\poc_session.py --evidence out\r14-guide\s4 run --name remix --addons --width 1920 --height 1080 `
    --lua out\r14-guide\set-remix.lua --lua tools\qa\guide_shots.lua --lua-shots 300
```

| Line in the game's console log | What it posts to the game window |
|---|---|
| `NL_INPUT <n> key <virtual key> <count>` | `WM_KEYDOWN` and `WM_KEYUP` for the key, `count` times (the scan code and extended-key flag filled in) |
| `NL_INPUT <n> click <x> <y>` | `WM_MOUSEMOVE`, then `WM_LBUTTONDOWN` and `WM_LBUTTONUP` 0.12 s apart, at client pixel (x, y) |
| `NL_INPUT <n> wheel <x> <y> <notches>` | `WM_MOUSEMOVE` to (x, y), then one `WM_MOUSEWHEEL` per notch (negative: down), with screen coordinates as the message wants |

What works (2026-11-03, PoC, loader 0.13.0): **keys** reach the menu's keyboard navigation; Page Down
(34) pages the focused developer menu down to its Settings Management section. **Clicks and the wheel do
not** while the real cursor is elsewhere: the menu reads the real cursor position and sees the mouse
leave. Keys also reach the game's own binds: an End press quit the game (the field's `config.cfg`, which
sessions use, binds End to `quit`), and the arrows turn the view; so `guide_shots.lua` uses only Page
Down. Nothing here moves the real mouse or types into another window.

Each `<n>` is done once, in order. The window is the visible "Garry's Mod" window of a `gmod.exe` from
the install (`--root`, default the PoC), found as `poc_session.py` finds it; the process is DPI aware,
so client pixels are the game's own. The console log is only read while the game runs (before a launch
it is the last session's, which `poc_session.py` moves away).

Options: `--root <game>`, `--timeout <seconds>` (default 1200). Prints each input it posted. Exit 0
when the game prints `NL_SHOT_DONE` or exits; 1 after the timeout. It writes nothing, launches nothing
and sends nothing but window messages to that window.
