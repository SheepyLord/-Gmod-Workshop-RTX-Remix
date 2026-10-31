# ToPBR BC7 conversion (R6 T5)

These notes describe the conversion of the fixes part's existing GPL-2.0 texture inputs;
the fixes [LICENSE](../../LICENSE) applies. No new textures or material references were added.
[conversion.json](conversion.json) records the encoder hash and arguments, pre-conversion
aggregate commit, material usage, sizes, hashes and top-mip error for every file.

The 83 uncompressed BGRA8 DDS files comprise 33 normal maps and 50 roughness maps. All 113
references in [materials.usda](../../garrysmod/rtx-remix/mods/~gmod_topbr/materials.usda) use
`colorSpace = "raw"`; its normal-map `encoding = 0` stays unchanged. BC7_UNORM (DXGI 98) keeps
all four channels in linear space, including the existing normal-map encoding. There are no
colour maps requiring an sRGB format in this set. Filenames, dimensions and mip counts remain.

## Encoder and import

The already-installed NVIDIA Texture Tools Exporter 2023.4.0 development build was used with
highest quality, on the CPU. Its path and SHA-256 are in the conversion record. For each original
DDS, after unpacking the pre-conversion inputs into the worktree's `out/topbr-bc7/original`:

```powershell
$env:TEMP = $env:TMP = (Resolve-Path out/tmp).Path
& 'C:/Program Files/NVIDIA Corporation/RTX Remix/exts/omni.flux.resources/deps/tools/nvtt/nvtt_export.exe' $source --output $destination --format bc7 --quality highest --no-cuda --dx10 --export-transfer-function linear --no-mip-gamma-correct --no-mip-pre-alpha
```

`$source` is one original DDS and `$destination` its same-named file under
`out/topbr-bc7/textures`. The complete indexed pre-conversion set is at aggregate commit
`465bf1f46f779e539d30da90e7f242ce76a30455`. Compare against that set when reproducing the
measurements, rather than recompressing the BC7 outputs. Scratch encoder/verification scripts,
the full per-mip error record and a six-pair comparison image are retained under the task's
`out/tmp` and `out/topbr-bc7` as local evidence.

The import changed exactly the 83 texture inputs and their index entries:

```powershell
python tools/inputs.py import fixes --root "out/topbr-bc7/textures=garrysmod/rtx-remix/mods/~gmod_topbr/textures"
python tools/inputs.py verify --part fixes --deep
```

## Measurements and acceptance

| Size | Before | After |
|---|---:|---:|
| DDS bytes, including headers | 142,869,484 (136.25 MiB) | 35,729,420 (34.07 MiB) |
| xz input bytes | 16,454,204 | 15,000,576 |

The deployed DDS reduction is 107,140,064 bytes (74.9916%). This is a file-size measurement;
resident VRAM was not measured.

Every output has a DX10 DDS header with BC7_UNORM, a single 2D image, the original width,
height and mip count, and exactly the expected block payload length. All 816 mip levels were
decoded with Pillow 12.3.0 and compared to the originals in raw 8-bit channel space. The
pixel-weighted R/G/B RMSE is 0.659/0.655/0.391; alpha matches exactly. The worst top-mip
channel RMSE is 0.957 and the worst individual mip channel RMSE is 4.0. Maximum single-pixel
R/G/B errors are 28/29/13. The offline comparison image preserves the visible normal and
roughness patterns. BC7 remains lossy; these numbers do not establish renderer acceptance.

R6 integration should compare the same surfaces and lighting before/after: Construct brick,
concrete and water, first-person arms/weapons, and Kleiner's face/clothing/glasses. Check close
and distant views for normal direction, seams and roughness changes. T5 launched no game.
