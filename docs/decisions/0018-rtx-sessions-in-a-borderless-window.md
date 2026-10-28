# 0018: RTX sessions run in a borderless window the size of the display

- Status: Accepted 2026-10-28
- Decided by: Claude, fixing the crash of the user's first field test with the release bundle ("the game
  crash to desktop on launch"), the same day. The window is the one RTXLauncher and the user's classic
  RTX install have always used.
- Builds on: [0008](0008-activation-at-startup.md) (launch arguments added at start-up)

## Context

- **The field test crashed every start, about 9 s in.** The setup was the CI-built loader 0.2.0, the
  Workshop item, and the player's launch options `-multirun -insecure -tickrate 120`.
  - The loader did its part: it deployed, activated, applied 7 of 7 patch sets and redirected the
    shader override.
  - The Remix runtime crashed. Its log ends with a 640x480 exclusive-fullscreen device, "Setting
    display mode", "FSR FG: onDestroy called" and "[D3D9WindowProc] Swapchain handle is invalid". Its
    crash handler recorded the crash the same millisecond ([RESEARCH.md](../RESEARCH.md) section 18).
- **Why exclusive fullscreen.** The player's launch options name no window mode. The `-dxlevel 90` the
  package adds differs from the 95 that non-RTX sessions store, so the engine reset its video settings
  to 640x480 fullscreen.
- **Reproduced on the PoC** with the field's launch options: the same log, then an access violation
  after 13.6 s. The same start plus `-windowed -noborder -w 3840 -h 2160` ran normally.
- **No earlier test ran in exclusive fullscreen.** Every automated session, M7's included, passed
  `-windowed`. RTXLauncher starts the game with `-windowed -noborder`, and the user's classic install
  with `-windowed -noborder -w 3840 -h 2160` (section 12).
- **Manifests are strict.** A new key, or a launch argument outside schema 1's list, would make every
  installed 0.2.0 loader refuse the updated Workshop item ([PACKAGE_FORMAT.md](../PACKAGE_FORMAT.md)).

## Decision

1. **In an RTX session the loader appends `-windowed -noborder -w <width> -h <height>`** after the
   package's launch arguments. The size is the primary display's current mode (`EnumDisplaySettingsW`,
   in pixels). It is read only when the loader sizes the window, and left out when it cannot be read.
2. **A window mode the player chose wins.** With `-windowed`, `-window`, `-sw`, `-startwindowed`, `-full`
   or `-fullscreen` on the command line (the spellings `engine.dll` reads), nothing is added. The
   player's own `-noborder` or size (`-w`, `-width`, `-h`, `-height`) is kept, and only the rest is added.
3. **It is the loader's rule, not a package field.** No manifest changes, and the packages already
   published get it too. Sessions without RTX are unchanged.
4. **The loader version becomes 0.2.1**, so logs and `status.json` tell a fixed loader from 0.2.0.

## Consequences

- An RTX session covers the primary display without a mode switch, which is the "fullscreen" RTX GMod
  players already know from RTXLauncher. Alt-Tab does not switch modes.
- A player who wants another size or mode puts it in Steam's launch options. `-fullscreen` brings
  the crash back until the runtime is fixed.
- The added options appear in `status.json` (`launch_arguments.added`), the log and `nlctl
  activation`. They are also part of the fallback options when the command-line swap is refused.
- With several displays, the size is the primary display's, the one the game opens on.
- **The crash itself stays in the runtime:** a swap chain used after it was destroyed, in the window
  procedure, during a mode switch. Its fix belongs in the `dxvk-remix-gmod` fork. This rule then
  remains as a safe default.

## Alternatives considered

- **Window options as a package field, or `-windowed` added to schema 1's launch arguments.** Every
  installed 0.2.0 loader would refuse the updated item, because manifests are strict.
- **`-windowed -noborder` without a size.** After the DX-level reset the window would be 640x480.
- **Only fixing the runtime.** That is right, but it lives in another repository and ships later. The
  loader rule also covers runtimes already published.
- **A `config.json` setting.** Not needed: Steam's launch options already let a player choose.
