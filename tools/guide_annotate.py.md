# guide_annotate.py

Draws green numbered arrows on real in-game captures for the RTX Remix guide. Captures come from
`tools\poc_session.py run --lua tools\qa\guide_shots.lua` (see `tools\qa\guide_shots.lua.md`).

```powershell
python tools\guide_annotate.py --shots out\r14\shots3\guide --out companion\nativeloader\materials\nativeloader\guide
```

`SPECS` lists each image's source capture, crop and arrow targets (capture pixels); the numbers match the
numbered steps in `nativeloader_guide.lua`. Output: one `<name>.jpg` per spec, scaled 2x. Needs Pillow.
Writes only to `--out`. Exit 0 on success.
A source starting with `@` is read from `--out` (the unmarked `remix_menu.jpg` shipped in the guide folder).
