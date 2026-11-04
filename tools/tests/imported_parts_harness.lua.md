# imported_parts_harness.lua

LuaJIT fixture (R15) executing the companion's real painted-shadow rules, solid-hair rules, their client
controller and the Model Hotloader's shipped `materials.lua` visibility hook. Invoked by
[test_imported_parts.py](test_imported_parts.py.md), or `luajit imported_parts_harness.lua <repo> <scenario>`.

| Scenario | Checks |
|---|---|
| `shadows` | 24 real parts from the field library hidden with the expected kind and rule (Laevatain's `Moyin` and `Hair+`, Endfield 目影/发影, Star Rail 目影 painted from 黑.jpg and 灰.jpg, ホタル's grey 目影, LycoReco まぶた影/髪影, Tda `hairshadow`, JEPT `EyeShadow`, SilverWolf999 陰影, an unnamed part painted from 黑.jpg); 18 kept (coloured make-up, glasses, tears, authored hidden parts, large parts, 影刀, 幻影); the `"source"` request |
| `hair_names` | hair and non-hair names (`Hairpin`, `chair`, `bangle`, 发饰, 髮+, `hairshadow`, `Hair_HL`), eligibility |
| `vtf` | shares of synthetic VTFs (the user's case, card hair, binary alpha, see-through hair, alpha above half), sampling in steps, the 256-square grid on a 1024 texture, invalid layouts and short reads |
| `hidden`, `remix_off`, `big_manifest` | `mmdhl.RenderHiddenParts` installed and answering per asset; nothing outside RTX; the manifest read once, refused above 8 MiB |
| `solid`, `late_soft` | flags cleared on the public material and the soft copy, other flags kept, card hair untouched, at most 33 file reads per frame, a reloaded material cleared again, restore when off and at shutdown, the status command |
| `reimport`, `despawn` | a replaced or removed asset put back; characters not on the map not measured |
| `hook` | the shipped `mmdhl.SyncMaterialState` sends hidden slots as not visible, ignores an erroring or wrong answer, and does not resend an unchanged state |

Input: source files and the scenario. Output: `PASS <scenario>` or an assertion failure. No disk writes,
network or game. Exit 0 on success, nonzero on failure.
