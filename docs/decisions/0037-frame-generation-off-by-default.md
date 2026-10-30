# 0037: Frame generation is off by default, at one generated frame

- Status: Accepted 2026-10-29. Amends [0020](0020-classic-rtx-settings-as-defaults.md) (the classic
  install's settings as the package's defaults) for three options that depend on the GPU.
- Decided by: the user, as an emergency fix ("we by default set the frame generation to be on, and 3x.
  However for users using 30, 40 or AMD, it immediately crashes the game. They are also not able to
  edit the multiple of FG setting."), Claude choosing how.

## Context

The package's Remix defaults ([ADR 0021](0021-remix-defaults-in-one-low-layer.md)) are the classic
install's settings, and that install runs on an RTX 5090: `rtx.frameGenerationType = 1` (DLSS-G),
`rtx.dlfg.enable = True` and `rtx.dlfg.maxInterpolatedFrames = 2`, which is 3x, multi-frame generation.
Only RTX 50 GPUs support more than one generated frame; RTX 40 supports one, RTX 30 and AMD none. Players
with those GPUs crashed at start. Remix's menu shows the multiplier only where multi-frame generation is
supported (`if (supportsMultiFrame)` in the runtime's GUI), so an RTX 40 player could not lower it either.

## Decision

1. The package's layer sets `rtx.frameGenerationType = 0` (off), `rtx.dlfg.enable = False` and
   `rtx.dlfg.maxInterpolatedFrames = 1`: a player who turns DLSS-G on (the RTX Remix tab or Remix's
   menu) gets 2x, which RTX 40 and 50 support; an RTX 50 player raises it in Remix's menu.
2. `tools/remix_defaults.py` forces these three values (`GPU_DEPENDENT`) whatever the classic install
   has, so a regenerated layer keeps them, and notes it in the layer's header.

## Consequences

- No player's start depends on the GPU for frame generation; RTX 50 owners lose 3x until they turn it
  on. A player's own saved `rtx.conf`/`user.conf` still wins over the layer.
- The classic install's look is otherwise unchanged (ADR 0020).

## Alternatives considered

- **Pick the setting by GPU at start** (as the non-NVIDIA layer does, ADR 0030): needs the GPU
  generation, which DXGI's vendor id does not give; a fix for later, in the loader or the runtime.
- **Clamp the multiplier in the runtime** to what the GPU supports: the right runtime fix, but it needs a
  rebuild and a new 363 MB DLL; not for an emergency.
