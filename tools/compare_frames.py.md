# compare_frames.py

Compares two screenshots of the same view by the user's block-difference measure, for visual
acceptance checks such as the [M5 plan](../docs/handover/M5-plan.md)'s comparisons with
`GarrysMod_RTX_c`. The measure follows the user's own
`C:\Users\matt-peng\.rpai\work\_probe\look\compare.py` (reimplemented here, not copied), with the
user's reading of it: about 1 between repeated captures of one install, 1.5-3.6 "close", 16-26
"broken" ([RESEARCH.md](../docs/RESEARCH.md) section 12).

```powershell
python tools\compare_frames.py rtx_c.png poc.png
python tools\compare_frames.py rtx_c.png poc.png --mask 1500,300,2300,2160 --threshold 3.6 --json
```

## What it computes

- Both images are read with Pillow and converted to 8-bit RGB (alpha dropped). They must be the same
  size.
- **`block_diff`**: each image is cropped from the top left to a whole number of blocks (32x32 by
  default), the mean R, G and B of every block is taken, and `block_diff` is the mean absolute
  difference between the two images' block means over all blocks and all three channels, on the 0-255
  scale. Block means of small regions forgive slight misalignment and noise, which a pixel difference
  would not.
- **`--mask x0,y0,x1,y1`** (repeatable): a pixel rectangle, `x0 <= x < x1`, `y0 <= y < y1`; every
  block it touches is left out of `block_diff` (`masked` counts them). Use it for a region that is
  expected to differ, such as a character the comparison does not cover.
- Per image, over all its pixels (not cropped, masks ignored): `mean_rgb`, and the luminance
  percentiles `p5`, `p50`, `p95`, `p99.5` with Rec. 709 weights (`0.2126 R + 0.7152 G + 0.0722 B`),
  interpolated linearly between the two nearest ranks as numpy's default does. Exposure and black
  frames show there before they show in `block_diff`.

Values agree with a numpy computation of the same definitions (checked on the user's captures). A
3840x2160 pair of pure noise takes about 10 s, ordinary screenshots much less.

## Options

- `--block N`: block size in pixels (default 32).
- `--mask x0,y0,x1,y1`: see above.
- `--threshold N`: exit 1 when `block_diff` is above `N` (for example 3.6, "close").
- `--json`: print `reference` and `image` (`path`, `width`, `height`, `mean_rgb`, `luminance`),
  `block`, `blocks`, `masked`, `block_diff`, `threshold` and `over_threshold` (`null` without a
  threshold). Without it, one line per image and one for `block_diff`.

## Requirements, side effects, exit codes

Python 3.10+ and Pillow 7 or later (`python -m pip install Pillow`). Reads the two images; writes
nothing.

0 compared (and `block_diff` within `--threshold`, if given); 1 `block_diff` above `--threshold`;
2 error: bad command line, an image that cannot be read, images of different sizes, no blocks left
to compare (images smaller than one block, or everything masked), Pillow missing.

Tests: [tests/test_compare_frames.py](tests/test_compare_frames.py.md).
