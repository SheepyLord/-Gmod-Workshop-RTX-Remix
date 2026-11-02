# eye_white_names.lua

Pure Lua matcher for Model Hotloader eye-white **surface names**, matching both native and English
names. `include("nativeloader/eye_white_names.lua").matches(name, english)` returns a boolean.
Covers 白目, 白眼, 眼白, 目白 and English sclera/shirome/eye white spellings, side/digit suffixes,
VRM expression materials and instance decorations. Shadow, highlight, cornea, liner, lashes, brows,
blindfold and outline exclusions override a positive English translation. Generic eye, qualified
eyeball, eye_back and the dark 目白框/目白边 rim stay unchanged. The exact corpus spelling `eyeball`
and the painted `目白底` backing are included after UV/geometry review. Never classifies textures or whole characters.

Inputs: two optional strings. Output: boolean. No side effects or exit codes. The QA catalogue script
and Lua regression harness execute this exact module; see [ADR 0088](../../../../docs/decisions/0088-imported-character-eye-whites.md).
