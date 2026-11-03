# test_companion_guide.py

Tests the in-game RTX Remix guide ([`nativeloader_guide.lua`](../../companion/nativeloader/lua/autorun/client/nativeloader_guide.lua.md)
and its pages, [`guide_pages.lua`](../../companion/nativeloader/lua/nativeloader/guide_pages.lua.md))
under LuaJIT with [`companion_guide_harness.lua`](companion_guide_harness.lua.md), and its pictures.

- **Pages:** the six pages in their order, each with an `icon16/` icon; known item kinds and loader
  conditions; section ids unique within a page; every link to an existing page and section; buttons
  that run plain console commands.
- **Every page opens:** every page and every section, in English and the six languages, for an older
  loader (`legacy`), a 0.11.0 one (`r6`) and a 0.13.0 one (`r13`); in English everything shown is in
  the catalog template. The memory page shows more advice the newer the loader.
- **Its size:** with a GUI scaler's larger `DermaDefault` the guide takes that scale (pictures by whole
  steps); `nativeloader_guide_scale` overrides it, and a plain game keeps the plain sizes.
- **Pictures:** each picture a page shows is in `companion/nativeloader/materials/nativeloader/guide/`;
  each picture with a legend has a spec in [`tools/guide_pictures.json`](../guide_pictures.json) with
  as many badges as legend entries; no spec without a page, no picture without a page (the README's
  `rtx_on.jpg` and `remix_menu.jpg` aside); each picture at most 256,000 bytes, 900 pixels wide (the
  page's width in a 1280x720 game; the README's two views of the game are exempt) and 1000 high, all of
  them together at most 4 MiB, all JPEG. The
  JPEG sizes are read from the files' frame headers (no Pillow needed).

The catalog is built from `companion/i18n` with `complete=False`: the structure does not wait for
translations (new text shows in English until it has one); completeness is
[`test_companion_i18n.py`](test_companion_i18n.py.md)'s.

```powershell
python -m unittest discover -s tools/tests -p test_companion_guide.py -v
```

Writes only a temporary catalog and inputs file under `out\tmp`. Skipped without LuaJIT. Exit 0 when
every test passes.
