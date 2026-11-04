# painted_shadows.lua

Pure Lua rules (R15, [ADR 0104](../../../../docs/decisions/0104-painted-shadows-and-solid-hair.md)) that
find the painted shadows of imported characters: the partly transparent overlays drawn over the eyes
(目影), under the fringe (发影) or on the face and body (陰影). No game calls.

`classify(part, total)` returns the kind (`"eye"`, `"hair"` or `"body"`) and the rule that found it, or
nil. `part` is a Model Hotloader AssetInfo material (`name`, `base`: the texture's hash or `""`,
`diffuse`, `alpha`, `count`), with `source`, the texture's path in the model (the asset manifest's
`materials[i].base`), when the caller has it; `total` is the model's index count. When only that path
could still decide, the result is `nil, "source"`, and the caller may ask again with it.

| Rule | Finds | Limits |
|---|---|---|
| `name` | 目影 and its variants (白目影, まぶた影, 睫毛影...), 发影/髪影/髮影, 陰影/阴影, 面具影, 表情_影; English `eyelidshadow`, `lashshadow`, `hairshadow`, `faceshadow`; the romanized 目影 as a word (`Moyin`, `muying`, `mokage`); 影 alone at the end of a name or before a digit, Latin letter, symbol or 子 (`影2`, `头发影子`); the word `shadow` | at most 3 % of the model's indices |
| `name`, make-up words | 眼影 and `eyeshadow` also name make-up, so they count only when dark (brightest diffuse channel 0.6 or less), an untextured see-through grey (alpha 0.6 or less, no hue), or painted from a dark texture | as above |
| `painted` | an untextured part with a dark diffuse (0.15 or less) and alpha 0.6 or less: Laevatain's `Hair+` | at most 0.5 % of the indices |
| `texture` | a part painted from a plain dark image (黑, 灰, 黒, black, grey, gray, shadow, 影, 阴影, 陰影, after the folder, extension and a trailing number are removed) with alpha 0.6 or less | at most 0.5 % of the indices |

Never: a part hidden as authored (alpha 0), glasses and lenses (眼鏡, 眼镜, メガネ, サングラス, レンズ,
`glass`, `lens`, `visor`...), and 影 in words that are not shadows (幻影, 剪影, 光影, 投影, 影院, 倒影, 影响).
A part named 影 that is a weapon (`影刀`) is not one either.

Over the 6,684 parts of the field library (2026-11-04, read only) the rules hide 92 parts in 159 models,
all of them named shadows except Laevatain's `Hair+`; the nine shadow-named parts kept are either
hidden as authored or coloured make-up (Evanescia's lavender `Mat_EyeShadow_01`) or a 眼影 painted
from a coloured eye or face texture. Tested by [`imported_parts_harness.lua`](../../../../tools/tests/imported_parts_harness.lua.md).
