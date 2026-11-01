# 0069: The adaptive eye emission ratio, tuned in game

- Status: Accepted 2026-10-31 (C-16; Claude as project manager, for the user's eye-white request).
  Supersedes the provisional numeric default of [0068](0068-adaptive-eye-emission-publishing.md).
- Decided by: the PoC measurements below

## Context

[0067](0067-scene-adaptive-emission.md) gives opaque materials an emission that follows auto
exposure's scene luminance, and [0068](0068-adaptive-eye-emission-publishing.md) has the PBR tool
write it for eye materials as `adaptive = fallback * R`. One number was left open: `R`, provisionally
`1/0.18`, which reproduces the old fixed level at exposure 1. The user's report: anime eye whites turn
over-dark or over-bright as the light changes, which does not suit these characters.

## Measurements (2026-10-31)

PoC, runtime `remix-main+8a5df5d8` (patch 0016), a copy of Robin's pack as the test mod `c16_robin`,
gm_construct, the player placed on one spawn point so Robin lands in the same pose and light every
run ([`eye_white_probe.lua`](../../tools/qa/eye_white_probe.lua.md)), the camera 22 units above her
face, 1920x1080, each condition settled 10 s. "Fixed" is the same runtime with
`rtx.adaptiveEmission.enable = False` (a temporary root `rtx.conf`). The number is the eye white's
linear luminance over the cheek's beside it
([`eye_white_patches.py`](../../tools/qa/eye_white_patches.py.md)); about 1 is the anime look.

| | noon | golden hour | dusk | night | interior, day | interior, night |
|---|---|---|---|---|---|---|
| fixed emission (0.6) | 0.69 | 0.52 | 0.88 | 46 | 0.79 | 0.84 |
| `R = 1/0.18` (input 3.33) | 0.62 | 0.61 | 0.48 | 0.31 | | |
| `R = 4/0.18` (runtime scale 4) | 0.94 | 1.28 | 0.73 | 0.64 | | |
| **`R = 25`** (input 15) | **0.98** | **1.38** | **0.77** | **0.70** | 1.04 | 1.04 |

The interior is a lamp-lit room of the building east of gm_construct's spawn (the player placed on
(1227, -1669, -144), looking 50 degrees down at yaw 45); Robin lands in another pose there, so it has
its own boxes (`sclera_ur` 822,490,834,500, `sclera_lo` 745,588,775,597, `skin` 850,600,875,618). The
lamps make day and night alike, and the room is not dark enough for the fixed glow (0.8).

Each condition's number is linear in `R`: interpolating scale 1 and 4 to 4.5 predicted 0.99, 1.39,
0.77 and 0.70, and the pack value 15 measured 0.98, 1.38, 0.77 and 0.70. At night the runtime log
showed `adapted_yf` 0.00046-0.00069 with the exposure at its cap of 16. Evidence:
`out/qa-poc/c16` (`A-fixed-r1`, `B-adaptive-r1`, `B-adaptive-p4`, `B-adaptive-v15`, `A-fixed-room`,
`B-adaptive-room`, contact sheets); runs at other spawn points (`B-adaptive-s3`, `B-adaptive-s6`) are not
comparable: one of them had half the cheek luminance at night.

## Decision

`R = 25` (= 4.5/0.18) is rpai's default, and the character packs carry `adaptive = fallback * 25`
(Robin's face: 15). The runtime's defaults stay: scale 1, luminance clamps 0..64, fallback 0.18.

The number cannot be 1 in every condition, for two reasons the measurements separate:

1. **The eye's lit part alone** (the fits' intercepts) is about 0.4-0.5 of the cheek by day and 0.2
   at night: the eyelids and lashes shade the recessed eye. Path tracing shows that; anime shading
   does not. The emission has to make up the difference.
2. **The emission follows the frame's light, the cheek its own.** Auto exposure's centre-weighted
   mean sets the emission; where the face is in shade while the frame is lit (golden hour) the eye
   white runs ahead, and where a low sun lights the cheek but not the recessed eye (dusk) it falls
   behind.

25 keeps the worst case smallest (golden hour 1.38 against night 0.70), and in the dark the eye white
stays below the cheek, as the C-16 plan requires (fixed emission: 46 times the cheek).

## Consequences

- Robin's, Evernight/March 7th's and Guinaifen's packs get the value with
  `set_adaptive_emission.py --multiplier 25`; new packs get it from rpai.
- A character whose eyes are drawn or built differently can be re-levelled per pack
  (`--emissive-adaptive-intensity`, or `--multiplier` on a published pack).
- The iris and the catchlight share the eye material's one emissive map, so they scale by the same
  factor: the catchlights are brighter and the irises a little more vivid (checked by eye at every
  condition).
- `adapted_yf` is that frame's mean while the exposure is smoothed (tau 0.15-0.75 s): moving between
  a bright and a dark place briefly brightens or dims the eye whites before the exposure settles.
- What remains (dusk 0.77, golden hour 1.38) needs a signal local to the eye, such as the light the
  face receives; nothing in the runtime offers that today.

## Alternatives considered

- **Keep `1/0.18`:** grey eye whites in every condition (0.31-0.62).
- **A global `rtx.adaptiveEmission.scale`:** the same lift for every adaptive material in every pack,
  including packs this project does not make; the level belongs with each pack's art.
- **A minimum luminance to lift the night:** brings back the dark-scene glow this work removes.
- **Different values per condition:** one material input cannot know the condition.
