-- Solid hair for imported characters (R15, the user's item 44). Game rips (Endfield, Silver Palace) keep a
-- hairline fade or a shading mask in the hair texture's alpha, inside the strands; the 0.5 alpha test and
-- the blended soft copy turn it into see-through notches. A hair part whose texture is measured mostly
-- opaque, with such a mask, is drawn solid instead; card-style hair, whose alpha cuts the strands out,
-- keeps its cutouts. Pure rules, no game calls. Documented in solid_hair.lua.md beside this file.
local function contains(text, token) return text:find(token, 1, true) ~= nil end
local function any(text, tokens)
    for _, token in ipairs(tokens) do if contains(text, token) then return true end end
    return false
end

local HAIR = {"髪", "发", "髮", "頭髮", "头发", "刘海", "瀏海", "辫", "辮", "马尾", "馬尾", "ポニーテール",
    "ツインテール", "アホ毛", "あほ毛", "呆毛", "もみあげ"}
local HAIR_EN = {"hair", "bang", "fringe", "ponytail", "twintail", "ahoge", "braid", "sideburn"}
-- Not the hair itself: its painted shadows and highlights (overlays that must stay see-through) and
-- the accessories worn in it (their own textures and cutouts).
local OVERLAY = {"影", "光", "ハイライト", "高光", "+", "＋"}
local OVERLAY_EN = {"shadow", "highlight", "hl", "spec", "specular", "gloss", "shine", "rim", "sp", "spa"}
local ACCESSORY = {"飾", "饰", "带", "帶", "簪", "夹", "夾", "绳", "繩", "环", "環", "冠", "花", "钗", "釵",
    "ゴム", "リボン", "ピン", "留め"}
local ACCESSORY_EN = {"ribbon", "band", "pin", "clip", "acc", "ornament", "tie", "flower", "bow", "ring",
    "crown", "comb", "scrunchie"}

local MAX_CLEAR = 0.10   -- of the sampled texels: padding between UV islands, not cut-out strands
local MAX_PARTIAL = 0.20 -- the mask or fade inside the strands; more is see-through on purpose
local MIN_CUT = 0.002    -- texels the 0.5 alpha test cuts (alpha 9-127): below this there is nothing to fix
local SAMPLES = 256      -- per side of the sampling grid over the top mip
local MAX_SIDE = 8192

local function words(lower)
    local out = {}
    for word in lower:gmatch("[a-z]+") do out[#out + 1] = word end
    return out
end
local function listed(word, tokens)
    for _, token in ipairs(tokens) do
        if word == token or word == token .. "s" then return true end
    end
    return false
end
-- English words: "Bangs", "MI_..._Hair01", "hair_down_front", "HairBack" ("hair" starting a word, so
-- not "chair"); "Hairpin" and "hairband" are accessories, "HairShadow" an overlay.
local function englishHair(lower)
    for _, word in ipairs(words(lower)) do
        if word:sub(1, 4) == "hair" then
            local rest = word:sub(5)
            if not listed(rest, ACCESSORY_EN) and not listed(rest, OVERLAY_EN) then return true end
        elseif listed(word, HAIR_EN) then
            return true
        end
    end
    return false
end
local function isHair(name)
    if type(name) ~= "string" or name == "" then return false end
    if any(name, OVERLAY) or any(name, ACCESSORY) then return false end
    for _, word in ipairs(words(name:lower())) do
        if listed(word, OVERLAY_EN) or listed(word, ACCESSORY_EN) then return false end
    end
    return any(name, HAIR) or englishHair(name:lower())
end

-- A part worth measuring: hair, textured, with an alpha channel the hotloader found, drawn fully opaque
-- by its own material (an authored see-through part keeps its alpha).
local function eligible(part)
    return type(part) == "table" and isHair(part.name) and part.alphaTexture == true and
        type(part.base) == "string" and part.base ~= "" and (tonumber(part.alpha) or 1) >= 0.99
end

local function uint(bytes, start, count)
    local out = 0
    for i = count - 1, 0, -1 do out = out * 256 + bytes:byte(start + i) end
    return out
end
-- The hotloader's generated textures: single-frame RGBA8888 VTF 7.2 without a low-resolution image
-- (the checks of eye_white_vtf.lua). header: the file's first 80 bytes; size: the file's size. Returns
-- {width, height, top} (top: the 0-based offset of the top mip, which comes last), or nil and why.
local function layout(header, size)
    if type(header) ~= "string" or #header < 80 or type(size) ~= "number" or size < 84 then return nil, "size" end
    if header:sub(1, 4) ~= "VTF\0" or uint(header, 5, 4) ~= 7 or uint(header, 9, 4) ~= 2 or
        uint(header, 13, 4) ~= 80 or uint(header, 25, 2) ~= 1 or uint(header, 64, 2) ~= 1 or
        uint(header, 53, 4) ~= 0 or uint(header, 58, 4) ~= 4294967295 or
        header:byte(62) ~= 0 or header:byte(63) ~= 0 then return nil, "unsupported VTF layout" end
    local width, height, mips = uint(header, 17, 2), uint(header, 19, 2), header:byte(57)
    if width == 0 or height == 0 or width > MAX_SIDE or height > MAX_SIDE or mips == 0 or mips > 14 or
        math.floor(uint(header, 21, 4) / 16384) % 2 ~= 0 then return nil, "dimensions/frames" end
    local total, w, h = 80, width, height
    for _ = 1, mips do total, w, h = total + w * h * 4, math.max(1, math.floor(w / 2)), math.max(1, math.floor(h / 2)) end
    if total ~= size then return nil, "truncated/extra image data" end
    return {width = width, height = height, top = size - width * height * 4}
end

-- Samples the top mip's alpha on a grid, a few rows per call, so a large texture never stalls a frame.
-- read(offset, length) returns that many bytes of the file from a 0-based offset. step(read, rows)
-- returns the shares when done, false while rows remain, or nil and why. Shares: clear (alpha <= 8),
-- low (9-127, which the 0.5 alpha test cuts), high (128-246) and opaque (>= 247), the limits of the
-- native soft rule (assets.cpp), with partial = low + high.
local function sampler(info)
    local stepX = math.max(1, math.floor(info.width / SAMPLES))
    local stepY = math.max(1, math.floor(info.height / SAMPLES))
    local rowBytes = info.width * 4
    local state = {y = 0, clear = 0, low = 0, high = 0, opaque = 0}
    function state.step(read, rows)
        for _ = 1, math.max(1, rows or 1) do
            if state.y >= info.height then break end
            local row = read(info.top + state.y * rowBytes, rowBytes)
            if type(row) ~= "string" or #row ~= rowBytes then return nil, "read" end
            for x = 4, rowBytes, stepX * 4 do
                local a = row:byte(x)
                if a <= 8 then state.clear = state.clear + 1
                elseif a < 128 then state.low = state.low + 1
                elseif a < 247 then state.high = state.high + 1
                else state.opaque = state.opaque + 1 end
            end
            state.y = state.y + stepY
        end
        if state.y < info.height then return false end
        local n = state.clear + state.low + state.high + state.opaque
        return {clear = state.clear / n, low = state.low / n, high = state.high / n, opaque = state.opaque / n,
            partial = (state.low + state.high) / n, samples = n, width = info.width, height = info.height}
    end
    return state
end

-- The whole file at once (tests, tools).
local function alphaShares(bytes)
    if type(bytes) ~= "string" then return nil, "size" end
    local info, why = layout(bytes:sub(1, 80), #bytes)
    if not info then return nil, why end
    return sampler(info).step(function(offset, length) return bytes:sub(offset + 1, offset + length) end, math.huge)
end

-- Solid: few clear texels (no cut-out strands), a partial region the size of a mask, not of a see-through
-- part, and enough of it below half that the alpha test makes holes.
local function solid(shares)
    return type(shares) == "table" and shares.clear <= MAX_CLEAR and shares.partial <= MAX_PARTIAL and
        shares.low >= MIN_CUT
end

return {isHair = isHair, eligible = eligible, layout = layout, sampler = sampler, alphaShares = alphaShares,
    solid = solid, MAX_CLEAR = MAX_CLEAR, MAX_PARTIAL = MAX_PARTIAL, MIN_CUT = MIN_CUT}
