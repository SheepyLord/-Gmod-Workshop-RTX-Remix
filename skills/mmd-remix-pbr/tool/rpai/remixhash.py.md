# remixhash.py

Offline Remix texture hashes for Model Hotloader's uncompressed VTFs.

dxvk-remix (``D3D9CommonTexture::SetupForRtxFrom``) hashes the CPU buffer of
subresource 0 - the top mip as uploaded - with ``XXH64(data, size, 0)`` when
``rtx.useObsoleteHashOnTextureUpload`` is true, otherwise ``XXH3_64bits``.

How Source uploads RGBA8888 was measured against hashes reported by the
running game (Hyacine, 2026-10-24, 10 of 12 textures reproduced):

* VTFs with an alpha flag go up as A8R8G8B8: BGRA bytes (5 of 5).
* VTFs without one mostly go up as X8R8G8B8 with a zero pad byte: BGR0 (4 of
  7). The face sheet went up as BGRA, and the body and hair sheets matched no
  layout at any mip level.
* So live hashes stay authoritative; prediction is the fallback for materials
  that are not drawn yet (hidden by default, toggled by morphs). An override
  for a hash nothing uses is inert, so every plausible candidate is written.

Compiled addons ship block-compressed VTFs, whose blocks go up unchanged: the
top mip's raw DXT5 data reproduced all 3 live hashes of Robin's robin_zzz.mdl
(2026-10-25). DXT1 and DXT3 are hashed the same way.

Part of the `mmd-remix-pbr` skill ([SKILL.md](../../SKILL.md)); the full method and every option are in [tool/README.md](../../tool/README.md).

Run with the rpai venv's Python (`%USERPROFILE%\.rpai\venv\Scripts\python.exe`).

## Side effects

None: computes hashes in memory.

## Exit codes

None: a library module, imported by `rpai` (`tool/rpai/cli.py`), not run on its own.
