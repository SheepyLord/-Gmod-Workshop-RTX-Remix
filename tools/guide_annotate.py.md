# guide_annotate.py

Makes the RTX Remix guide's pictures from real in-game captures. For each picture it crops the
capture, never scaling it, so the game's text stays as sharp as it was on screen, and draws numbered
badges with arrows that point at the exact control. What to draw is in
[`guide_pictures.json`](guide_pictures.json); the captures come from
[`qa/guide_shots.lua`](qa/guide_shots.lua.md) through [`poc_session.py`](poc_session.py.md).

```powershell
# All pictures, from a folder of capture sessions, into the guide folder:
python tools\guide_annotate.py --shots out\r14-guide\shots
# Some of them, somewhere else first:
python tools\guide_annotate.py --shots out\r14-guide\shots --only start_here remix_settings --out out\r14-guide\preview
# A capture with a labelled 50-pixel grid, for reading coordinates when writing a spec:
python tools\guide_annotate.py --grid out\r14-guide\shots\tab\shot-01-spawnmenu_tab.png --crop 1100,0,1920,700 --to out\r14-guide\grid.png
```

## The spec (`tools/guide_pictures.json`)

```json
{
  "style": { "color": [118, 185, 0], "outline": [16, 16, 16], "number": [10, 10, 10], "radius": 13,
             "font": 17, "arrow": 3, "head": 13, "quality": 85, "max_bytes": 256000 },
  "pictures": {
    "start_here": {
      "capture": "tab/shot-*-spawnmenu_tab.png",
      "crop": [1180, 60, 1830, 760],
      "badges": [
        { "box": [1290, 150, 1820, 236], "at": [1250, 193] },
        { "target": [1500, 262], "at": [1250, 262] }
      ]
    }
  }
}
```

- `capture`: a file pattern relative to `--shots` (the last match is used, so a repeated session wins).
- `crop`: `x0, y0, x1, y1` in capture pixels. The picture is exactly this part of the capture.
- `badges`, in legend order: badge *n* is legend entry *n* of the picture's `image` item in
  [`guide_pages.lua`](../companion/nativeloader/lua/nativeloader/guide_pages.lua.md). Each has `at`, the
  badge's centre, and what it points at: `target`, a point (the arrow's tip), or `box`, a control's
  rectangle, outlined, the arrow ending at its nearest edge. All in capture pixels.
- `style`: one look for every picture: green badges with a dark rim and a black number, green arrows
  and outlines with a dark edge (readable on light and dark backgrounds), JPEG `quality`, the size
  limit.

Before drawing, each picture is checked, and a problem stops it: the crop outside the capture, a badge
outside the crop, a badge over its own box, two badges overlapping, or a badge too close to the
point it shows.

## Output

`<out>/<name>.jpg` for each picture (default the guide folder,
`companion/nativeloader/materials/nativeloader/guide/`): baseline JPEG without chroma subsampling, so
coloured text keeps its edges. It prints each picture's size, badge count and bytes, then the total.
The guide's test ([`tests/test_companion_guide.py`](tests/test_companion_guide.py.md)) holds each
picture to 256,000 bytes, 900 pixels wide, and all of them to 4 MiB.

Needs Pillow. Writes only `--out` (or `--to` for `--grid`). Exit 0 when every picture was made; 1 when
a capture is missing, a spec has a problem or a picture is over its size limit (the others are
still written).
