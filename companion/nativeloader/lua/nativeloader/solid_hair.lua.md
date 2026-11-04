# solid_hair.lua

Pure Lua rules (R15, [ADR 0104](../../../../docs/decisions/0104-painted-shadows-and-solid-hair.md)) that
decide whether an imported character's hair is drawn solid instead of alpha-tested. No game calls.

Game rips (Endfield's `T_actor_*_hair_01_D`, Laevatain's among them) keep a mask or a hairline fade in
the hair texture's alpha, inside the strands. The hotloader's 0.5 alpha test cuts the texels below half,
and its blended soft copy shows the rest through: see-through notches in the hair. The user's own fix
for Laevatain was to remove `$alphatest`.

- `isHair(name)`: hair names (髪, 发, 髮, 头发, 刘海, 辫, ポニーテール, アホ毛...; English words starting with
  `hair` and `bang`, `fringe`, `ponytail`, `braid`...), but not the hair's overlays (影, 光, 高光,
  ハイライト, `+`; `shadow`, `highlight`, `HL`, `spec`, `gloss`, `rim`, `sp`, `spa`) or accessories (飾, 饰,
  带, 簪, 夹, 绳, リボン, ゴム, ピン, 留め; `ribbon`, `band`, `pin`, `clip`, `tie`, `bow`, `ring`...).
  `Hairpin` and `chair` are not hair.
- `eligible(part)`: a hair name, `alphaTexture` (the hotloader found an alpha channel), a texture, and
  material alpha 0.99 or more (an authored see-through part keeps its alpha).
- `layout(header, size)`: checks the hotloader's VTF layout (7.2, RGBA8888, one frame, one slice, no
  cube map, no low-resolution image, the exact size of every mip) and returns the top mip's offset.
- `sampler(info)`: samples the top mip's alpha on a grid of at most 256 x 256, a few rows per
  `step(read, rows)`, through a `read(offset, length)` function. Shares: clear (alpha 8 or less), low
  (9-127, which the 0.5 test cuts), high (128-246), opaque (247 or more), the limits of the native soft rule.
- `alphaShares(bytes)`: the same for a whole file in memory.
- `solid(shares)`: clear 10 % or less (no strands cut out of the texture), partial 20 % or less (a mask,
  not a see-through part), and low 0.2 % or more (the alpha test cuts holes).

Field library, 2026-11-04 (read only): Laevatain's hair is clear 3.6 %, low 1.6 %, partial 5.0 %; the
partial texels of the hair textures lie in regions over 16 texels wide (85-100 % of them), not in
anti-aliased strand edges. Solid by this rule: the Endfield hair of Laevatain, JEPT and Yvonne, and a few
other models whose hair has partial alpha below half (Tda式初音ミクV4X, 芙提雅, 薇薇安, 克罗瑞娜, 卜卜, 娜娜莉). Not solid:
cut-out hair (刻晴, clear 12.9 %), binary alpha (雅珂达, low 0.006 %), hair whose partial alpha is all above
half (露娜拉), and see-through hair (灵可's bangs, partial 21 %). Tested by
[`imported_parts_harness.lua`](../../../../tools/tests/imported_parts_harness.lua.md).
