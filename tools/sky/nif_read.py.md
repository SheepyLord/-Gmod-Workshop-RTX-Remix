# nif_read.py

Reads the shapes of a Skyrim LE NIF (Gamebryo 20.2.0.7, user version 12, BS version 83) far enough to
bake sky textures: node transforms, `NiTriShapeData` vertices, UVs and triangles (the geometry data
holds a 4-byte material CRC after the vector flags), and the texture names each sky, effect or
lighting shader block mentions. Used on Night Sky HD LE's `stars.nif` by
[`bake_nightsky.py`](bake_nightsky.py.md) and [`nightsky_mapping.py`](nightsky_mapping.py.md).

```powershell
python -I tools\sky\nif_read.py <file.nif> [<out.json>]
```

Prints the header, version, and one line per block (type, vertex and triangle counts, textures, or the
node's name, translation, scale and links). With `out.json` it writes `{header, version, user, bs,
blocks: [{index, type, ...; shapes: v, uv, t, ...}]}`. It parses untrusted files: run with `python -I`.
**Exit:** 0; an unexpected layout raises.
