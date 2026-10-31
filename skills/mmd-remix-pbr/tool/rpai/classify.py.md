# classify.py

Surface classes for MMD materials, from their names and sphere maps.

Remix replaces by texture hash, and MMD atlases are shared: on Hyacine one
cloth sheet serves 39 materials, eight of them metal fittings. So a class is
decided per PMX material and later rasterised into texture space (uvmask.py),
which lets one generated texture be metal in some texels and cloth in others.

Rules run in order and the first match wins. CJK terms match as substrings;
English terms match whole words, so "bell" does not catch "belly".

Part of the `mmd-remix-pbr` skill ([SKILL.md](../../SKILL.md)); the full method and every option are in [tool/README.md](../../tool/README.md).

Run with the rpai venv's Python (`%USERPROFILE%\.rpai\venv\Scripts\python.exe`).

## Side effects

None: pure classification rules.

## Exit codes

None: a library module, imported by `rpai` (`tool/rpai/cli.py`), not run on its own.
