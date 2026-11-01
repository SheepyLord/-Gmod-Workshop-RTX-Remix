# eye_white_patches.py

Measures the eye whites against the skin in the screenshots of
[`eye_white_probe.lua`](eye_white_probe.lua.md): the linear luminance of named pixel boxes in every
shot, and the ratio of the sclera boxes' mean to the skin box. A ratio near 1 is the anime look the
C-16 work aims for (eye whites about as bright as the face around them); the fixed emission gave 0.5-0.9
by day and over 40 at night ([TESTING.md](../../docs/TESTING.md#c-16-scene-adaptive-emission)).

```powershell
python tools\qa\eye_white_patches.py out\qa-poc\c16\B-adaptive-p5
python tools\qa\eye_white_patches.py out\qa-poc\c16\A-fixed-r1 out\qa-poc\c16\B-adaptive-p5 --range 0.8,1.1
python tools\qa\eye_white_patches.py shot.png --patch sclera=960,560,990,566 --patch skin=840,545,870,575 --json
```

## What it computes

- Inputs are run folders (their `shot-*.png`, sorted) or PNG files, read with Pillow as 8-bit RGB.
- Each box is `x0,y0,x1,y1` in pixels, `x0 <= x < x1`, `y0 <= y < y1`. Every pixel is decoded from
  sRGB to linear and weighted with Rec. 709 (`0.2126 R + 0.7152 G + 0.0722 B`); a box gives the mean
  and standard deviation. A large deviation means the box straddles an edge (the lash line, the iris):
  check its place on a crop.
- `ratio` is the mean of the boxes whose names start with `sclera`, divided by the `skin` box;
  `sclera_ratios` gives each sclera box alone. Both are `null` when the skin box is black.
- The values are display-referred: after Remix's tone mapping and the 8-bit sRGB screenshot, so night
  shots (linear values near 0.005, about 15 of 255) carry a few percent of quantization.

Default boxes, for Robin in a 1920x1080 frame with the player placed as
[`eye_white_probe.lua.md`](eye_white_probe.lua.md) shows: `sclera_ul` 905,622,920,636 (above the iris),
`sclera_lr` 966,722,976,742 (below it) and `skin` 1010,660,1040,690 (the cheek beside the eye).

## Options

- `--patch NAME=x0,y0,x1,y1` (repeatable): replaces the default boxes. One must be `skin`, at least one
  must start with `sclera`.
- `--shift dx,dy`: moves every box, for a frame that landed a few pixels off.
- `--range LOW,HIGH`: an acceptance check; shots whose ratio is outside it are marked `OUTSIDE`.
- `--json`: prints `results` (per shot: `shot`, `patches` with `box`, `mean`, `std`; `sclera`, `skin`,
  `ratio`, `sclera_ratios`), `range` and `outside`.

## Exit codes and side effects

0 when every shot was measured (and is inside `--range`), 1 when a shot is outside `--range`, 2 for bad
arguments, a box outside an image, no shots or a missing Pillow. Reads the images only; writes nothing.
