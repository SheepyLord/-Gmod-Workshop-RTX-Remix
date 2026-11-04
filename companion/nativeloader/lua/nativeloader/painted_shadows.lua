-- Painted shadows of imported characters (R15, the user's item 43): the partly transparent overlays MMD
-- models paint over the eyes (目影), under the fringe (发影) and on the face or body (陰影). Path tracing
-- casts the real shadow there, so in RTX sessions they darken twice. Pure rules, no game calls:
-- classify(part, total) returns the kind ("eye", "hair" or "body") and the rule that found it ("name",
-- "painted" or "texture"); or nil, and "source" when only the texture's file name could still decide.
-- part: a Model Hotloader AssetInfo material (name, base: the texture's hash or '' when untextured,
-- diffuse, alpha, count), with source: the texture's path in the model (the asset manifest's
-- materials[i].base, "tex/黑.jpg"), and en: an English name when one is known; total: the model's
-- index count. Documented in painted_shadows.lua.md.
local function contains(text, token) return text:find(token, 1, true) ~= nil end
local function any(text, tokens)
    for _, token in ipairs(tokens) do if contains(text, token) then return true end end
    return false
end

-- Names that mean an eye, fringe or face/body shadow. 眼影 and "eye shadow" also name make-up, so
-- those two need a dark overlay (MAKEUP below).
local EYE = {"目影", "白目影", "眼白影", "まぶた影", "瞼影", "目の影", "眼皮影", "睫毛影", "まつげ影", "まつ毛影"}
local EYE_EN = {"eyelidshadow", "eyelid shadow", "eyelid_shadow", "lashshadow", "lash shadow", "lash_shadow",
    "lashshad", "eyewhiteshadow", "eyewhite shadow", "eyewhite_shadow"}
local MAKEUP, MAKEUP_EN = {"眼影"}, {"eyeshadow", "eye shadow", "eye_shadow"}
local HAIR = {"发影", "髮影", "髪影", "头发影", "頭髮影", "前髪影", "前发影", "後ろ髪影", "后发影", "刘海影", "瀏海影"}
local HAIR_EN = {"hairshadow", "hair shadow", "hair_shadow", "fringeshadow", "bangshadow", "bangsshadow"}
local BODY = {"面具影", "脸影", "顔影", "颜影", "臉影", "表情影", "表情_影", "陰影", "阴影", "衣影", "首影", "鼻影"}
local BODY_EN = {"faceshadow", "face shadow", "face_shadow", "bodyshadow", "body shadow", "body_shadow"}
-- Romanized 目影 (mùyǐng), as whole words: Laevatain's "Moyin".
local PINYIN = {muying = true, moyin = true, mokage = true, mekage = true}
-- 影 that is not a shadow, and parts that are see-through on purpose.
local NOT_SHADOW = {"幻影", "剪影", "光影", "投影", "影院", "倒影", "影响", "影響"}
local KEEP = {"眼鏡", "眼镜", "メガネ", "めがね", "サングラス", "墨镜", "镜片", "鏡片", "レンズ", "玻璃", "ガラス"}
local KEEP_EN = {"glass", "lens", "visor", "goggle", "monocle"}
-- Plain dark textures an overlay is painted with.
local DARK_TEXTURES = {["黑"] = true, ["灰"] = true, ["黒"] = true, ["black"] = true, ["gray"] = true,
    ["grey"] = true, ["shadow"] = true, ["影"] = true, ["阴影"] = true, ["陰影"] = true}

local NAMED_SHARE = 0.03     -- a named shadow: at most this share of the model's indices
local PAINTED_SHARE = 0.005  -- an unnamed one: untextured or a dark texture, partly transparent and this small
local PAINTED_ALPHA = 0.6
local DARK = 0.15            -- brightest diffuse channel of an unnamed painted shadow
local MAKEUP_DARK = 0.6      -- brightest diffuse channel of a shadow named like make-up

local function words(lower)
    local out = {}
    for word in lower:gmatch("[a-z]+") do out[word] = true end
    return out
end
-- The texture's file name without folder, extension or trailing number: "texture\shadow2.png" -> "shadow".
local function stem(path)
    if type(path) ~= "string" or path == "" then return "" end
    local base = path:gsub("\\", "/"):match("([^/]+)$") or path
    return (base:gsub("%.[^.]*$", ""):lower():gsub("[%d%s_%-]+$", ""))
end
local function channels(diffuse)
    if type(diffuse) ~= "table" then return 1, 1, 1 end
    return tonumber(diffuse[1]) or 1, tonumber(diffuse[2]) or 1, tonumber(diffuse[3]) or 1
end
local function brightest(diffuse) return math.max(channels(diffuse)) end
-- No hue: make-up is coloured, a painted shadow grey or black.
local function grey(diffuse)
    local r, g, b = channels(diffuse)
    return math.max(r, g, b) - math.min(r, g, b) <= 0.03
end
-- A shadow named with 影 alone ("影", "影2", "体影_a", "头发影子"): 影 at the end, or before a digit,
-- Latin letter, symbol or 子; not 影 starting another word ("影刀").
local function shadowCharacter(text)
    local at = 1
    while true do
        local first, last = text:find("影", at, true)
        if not first then return false end
        local following = text:byte(last + 1)
        if not following or following < 0x80 or text:sub(last + 1, last + 3) == "子" then return true end
        -- Full-width forms (U+FF00-U+FF5F: digits, letters, ＋, ＿): EF BC xx or EF BD xx.
        if following == 0xEF and (text:byte(last + 2) == 0xBC or text:byte(last + 2) == 0xBD) then return true end
        at = last + 1
    end
end

local function classify(part, total)
    if type(part) ~= "table" then return nil end
    local name = type(part.name) == "string" and part.name or ""
    local english = type(part.en) == "string" and part.en or type(part.englishName) == "string" and part.englishName or ""
    local alpha, count = tonumber(part.alpha) or 1, tonumber(part.count) or 0
    total = tonumber(total) or 0
    -- Hidden as authored (the hotloader's Show bodygroups), or nothing to draw.
    if alpha <= 0 or count <= 0 or total <= 0 then return nil end
    local text = name .. " " .. english
    local lower = text:lower()
    if any(text, KEEP) or any(lower, KEEP_EN) or any(text, NOT_SHADOW) then return nil end
    local share = count / total
    local hasSource = type(part.source) == "string" and part.source ~= ""
    local untextured = (type(part.base) ~= "string" or part.base == "") and not hasSource
    local dark = brightest(part.diffuse)
    local darkTexture = hasSource and DARK_TEXTURES[stem(part.source)] or false

    if share <= NAMED_SHARE then
        if any(text, EYE) or any(lower, EYE_EN) then return "eye", "name" end
        for word in pairs(words(lower)) do if PINYIN[word] then return "eye", "name" end end
        if any(text, MAKEUP) or any(lower, MAKEUP_EN) then
            -- Make-up is coloured; a shadow is dark, a see-through grey, or painted from a dark texture.
            if dark <= MAKEUP_DARK or darkTexture then return "eye", "name" end
            if untextured and grey(part.diffuse) and alpha <= PAINTED_ALPHA then return "eye", "name" end
            if not untextured and not hasSource then return nil, "source" end
            return nil
        end
        if any(text, HAIR) or any(lower, HAIR_EN) then return "hair", "name" end
        if any(text, BODY) or any(lower, BODY_EN) then return "body", "name" end
        if shadowCharacter(text) or words(lower).shadow or words(lower).shadows then return "body", "name" end
    end
    if share <= PAINTED_SHARE and alpha <= PAINTED_ALPHA then
        local hairy = any(text, {"髪", "发", "髮"}) or contains(lower, "hair")
        if untextured then
            if dark <= DARK then return hairy and "hair" or "eye", "painted" end
            return nil
        end
        if darkTexture then return hairy and "hair" or "eye", "texture" end
        if not hasSource then return nil, "source" end
    end
    return nil
end

return {classify = classify, NAMED_SHARE = NAMED_SHARE, PAINTED_SHARE = PAINTED_SHARE}
