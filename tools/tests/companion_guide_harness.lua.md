# companion_guide_harness.lua

LuaJIT harness for [`test_companion_guide.py`](test_companion_guide.py.md). Arguments: the guide
(`nativeloader_guide.lua`), its pages (`guide_pages.lua`), `i18n.lua`, a built catalog, an inputs file
(a Lua table: the catalog template's message IDs, and the pictures in the guide folder), the mode,
the language and the loader generation (`legacy`, `r6`, `r13`: the `status.json` the guide reads).

It runs the real guide code over mocked GMod: panels whose methods do nothing unless the harness
checks them (labels must wrap; fonts must have been created; text must be a string), `status.json`
from memory, and file, setting and console writes that fail the run.

- `structure`: prints one tab-separated line per page (`PAGE`), item (`ITEM` with its condition),
  section (`SECTION`), picture (`IMAGE` with its legend count), link (`LINK`) and button (`BUTTON`),
  then `PASS structure`.
- `render`: opens every page and every section with `nativeloader_guide <page> [section]`, and checks
  what each shows (`NATIVELOADER_GUIDE.shown`): a translated title, non-empty texts without an
  unexpanded `%s`, in English only text that is in the catalog template (or a JSON example), and only
  pictures that are shipped. Then `nativeloader_stability_guide` must open `memory`, a plain
  `nativeloader_guide` `welcome`, and an unknown page the first page. Prints `SHOWN <page> <texts>
  <pictures>` per page and `PASS render <language> <generation> <pages>`.
- `scale`: `draw.GetFontHeight` reports a `DermaDefault` 31/14 times as tall as the guide's probe,
  as a GUI scaler does. The guide must take that scale, pictures at 2 and a body font of 33. Then
  `nativeloader_guide_scale 1` must give 1 and the plain sizes, and so must a plain `DermaDefault` with
  the setting back at 0. Prints `PASS scale`.

Exit 0 on success; an assertion's message and a nonzero exit otherwise. Reads only its inputs.
