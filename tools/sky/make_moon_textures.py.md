# make_moon_textures.py

Builds the runtime's Moon textures, `moon_albedo.dds` and `moon_normal.dds`, from NASA's CGI Moon Kit
(https://svs.gsfc.nasa.gov/4720; credit: NASA's Scientific Visualization Studio). The runtime draws
moon 0 with them ([ADR 0032](../../docs/decisions/0032-real-moon-stars-eclipses-and-fog-presets.md));
they ship in `packages\runtime\files\atmosphere` ([packages/README.md](../../packages/README.md)).

```powershell
python -I tools\sky\make_moon_textures.py <lroc_color_poles_4k.tif> <ldem_4.tif> <out folder>
```

| Output | What |
|---|---|
| `moon_albedo.dds` | 2048x1024 BC7 sRGB with mips (Kaiser): the colour map resized in linear light (Lanczos) and scaled so the near side's mean linear luminance, weighted towards the sub-Earth point, is 0.25 (the shader divides by it and multiplies by `rtx.atmosphere.moonTextureAlbedo`) |
| `moon_normal.dds` | 1440x720 BC5 tangent-space normal map (x east, y north) with mips without gamma, from the elevation's central differences (east corrected by the cosine of the latitude, wrapped in longitude) |
| `src\*.png` | The images handed to the compressor |

It prints the near-side mean, the scale, how much clips, the slope percentiles, and each DDS's size,
format and mip count. **Needs:** numpy, Pillow, and NVIDIA Texture Tools Exporter: the RTX Remix
app's `nvtt_export.exe`, or the one `NVTT_EXPORT` names. **Exit:** 0; a missing input or a failed
compression raises. Facts about the sources: [RESEARCH.md](../../docs/RESEARCH.md) section 29.
