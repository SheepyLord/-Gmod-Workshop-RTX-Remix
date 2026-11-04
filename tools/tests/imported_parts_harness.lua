-- Run the shipped painted-shadow and solid-hair rules, their client controller and the Model Hotloader's
-- visibility hook against a minimal engine/API fixture. Usage: luajit imported_parts_harness.lua <repo> <scenario>
local root, scenario = arg[1], arg[2]
local base = root .. "/companion/nativeloader/lua/"
local shadows = dofile(base .. "nativeloader/painted_shadows.lua")
local hair = dofile(base .. "nativeloader/solid_hair.lua")
bit = require("bit")
local function pass() io.write("PASS " .. scenario .. "\n") os.exit(0) end

-- Real parts from the field library (2026-11-04): name, alpha, diffuse, texture source, count, total.
local function part(name, alpha, diffuse, source, count, total)
    return {name = name, alpha = alpha, diffuse = {diffuse, diffuse, diffuse}, base = source ~= "" and "f00d" or "",
        source = source, count = count}, total
end
if scenario == "shadows" then
    local hidden = {
        {"eye", "name", part("Moyin", 0.5, 0, "", 96, 1150545)},             -- Laevatain, the pinyin of 目影
        {"hair", "painted", part("Hair+", 0.5, 0, "", 444, 1150545)},        -- Laevatain, unnamed black overlay
        {"eye", "name", part("目影", 0.3, 0, "", 102, 263964)},               -- Yvonne (Endfield)
        {"hair", "name", part("发影", 0.3, 0, "", 1158, 263964)},
        {"eye", "name", part("目影", 0.5, 1, "tex\\黑.jpg", 162, 557295)},     -- Robin (Star Rail)
        {"eye", "name", part("目影", 0.4, 1, "tex\\灰.jpg", 144, 449853)},     -- 桂乃芬
        {"eye", "name", part("目影", 0.3, 0.753, "", 150, 629439)},           -- ホタル: untextured grey
        {"eye", "name", part("目影", 1, 1, "texture\\shadow.png", 300, 410565)}, -- Linlong
        {"hair", "name", part("髮影", 1, 1, "texture\\shadow2.png", 1146, 410565)},
        {"eye", "name", part("まぶた影", 1, 1, "textures\\tex_Eye_Takina.png", 240, 285735)}, -- LycoReco
        {"hair", "name", part("髪影", 1, 1, "textures\\tex_Hair_Takina.png", 4104, 285735)},
        {"hair", "name", part("hairshadow", 1, 1, "tex\\face_Mikuv4x.tga", 975, 104901)},     -- Tda
        {"eye", "name", part("EyeShadow", 0.5, 0, "", 102, 1143777)},         -- JEPT: dark, so not make-up
        {"hair", "name", part("HairShadow", 0.5, 0, "textures/T_actor_common_hairshadow_01_M.png", 639, 1143777)},
        {"eye", "name", part("M_eyeshadow_common_05", 0.3, 0, "textures/T_actor_common_eyeshadow_01_M.png", 120, 254238)},
        {"eye", "name", part("眼影", 0.4, 0.8, "", 168, 330231)},             -- untextured see-through grey
        {"body", "name", part("面具影", 0.2, 0, "", 117, 191775)},
        {"body", "name", part("陰影上身", 1, 1, "tex\\阴影.png", 1389, 534036)}, -- SilverWolf999
        {"body", "name", part("表情_影", 1, 1, "textures\\tex_Facial_Sakurako.png", 486, 291354)},
        {"eye", "name", part("MI_AlfDefault_U_LashShadow01_A", 1, 1, "Textures\\T_AlfDefault_EyeTrans01_A_D.png", 216, 285180)},
        {"body", "name", part("影2", 0.5, 1, "tex\\颜.png", 120, 300000)},
        {"hair", "name", part("头发影子", 0.5, 1, "tex\\颜.png", 120, 300000)},
        {"eye", "texture", part("材質12", 0.3, 1, "sph\\黑.jpg", 150, 711927)}, -- unnamed, a plain black image
        {"eye", "name", part("眼影", 0.3, 1, "tex\\黑1.png", 150, 300000)},     -- make-up name, dark texture
    }
    for _, case in ipairs(hidden) do
        local kind, rule = shadows.classify(case[3], case[4])
        assert(kind == case[1] and rule == case[2], "miss " .. case[3].name .. ": " .. tostring(kind) .. " " .. tostring(rule))
    end
    local kept = {
        {part("Mat_EyeShadow_01", 0.76, 0.91, "", 138, 129060)},              -- Evanescia: coloured make-up
        {part("眼影", 0.3, 1, "眼睛1.png", 216, 379716)},                       -- a coloured eye texture
        {part("淚", 1, 1, "textures\\Tears.png", 6156, 318639)},
        {part("眼镜", 1, 1, "tex\\衣服.png", 588, 306069)},
        {part("GlassesLenses", 1, 1, "tex\\Kafka_Body_Map3_D.png", 240, 137961)},
        {part("サングラス影", 0.5, 0, "", 100, 300000)},                         -- glasses win over 影
        {part("メガネ", 1, 0, "", 3480, 150966)},
        {part("EyeShadow(Hide)", 0, 1, "", 192, 300231)},                      -- authored hidden
        {part("发shadow", 0, 1, "textures\\Hair2.png", 79068, 585912)},
        {part("ShadowHeart", 1, 1, "tex\\body.png", 60000, 300000)},           -- not the word shadow, and large
        {part("Shadow", 1, 1, "tex\\body.png", 60000, 300000)},                -- the word, but 20 % of the model
        {part("影刀", 1, 1, "tex\\weapon.png", 900, 300000)},                   -- 影 starting another word
        {part("幻影", 0.5, 0, "", 100, 300000)},
        {part("MI_Hair+", 1, 1, "tex\\后发hi.png", 31572, 285039)},              -- a highlight overlay, 11 %
        {part("Eye_Hi", 0.5, 1, "tex\\eye.png", 100, 300000)},
        {part("眼睛1", 0.3, 1, "tex\\脸.png", 120, 300000)},
        {part("Body", 1, 1, "tex\\Body.png", 191028, 400000)},
        {part("黒い布", 0.5, 0.05, "", 6000, 300000)},                           -- dark and see-through, but 2 %
    }
    for _, case in ipairs(kept) do
        local kind = shadows.classify(case[1], case[2])
        assert(kind == nil, "false positive " .. case[1].name .. ": " .. tostring(kind))
    end
    -- Without the texture's path, an undecided textured part asks for it; untextured ones never do.
    local blind = {name = "眼影", alpha = 0.3, diffuse = {1, 1, 1}, base = "f00d", count = 216}
    local kind, why = shadows.classify(blind, 379716)
    assert(kind == nil and why == "source")
    kind, why = shadows.classify({name = "材質12", alpha = 0.3, diffuse = {1, 1, 1}, base = "f00d", count = 150}, 711927)
    assert(kind == nil and why == "source")
    kind, why = shadows.classify({name = "Mat_EyeShadow_01", alpha = 0.76, diffuse = {0.84, 0.79, 0.906}, base = "", count = 138}, 129060)
    assert(kind == nil and why == nil)
    assert(shadows.classify(nil, 1) == nil and shadows.classify({name = "目影", alpha = 0.3, count = 0}, 10) == nil)
    assert(shadows.classify({name = "目影", alpha = 0.3, count = 10}, 0) == nil)
    pass()
end
if scenario == "hair_names" then
    for _, name in ipairs({"Hair", "髪", "前髪", "后发", "头发1", "髮", "MI_R2T1LiliMd10011Bang", "MI_AlfDefault_U_Hair01",
        "hair_down_front", "Bangs", "HairBack", "Hair_Front", "右辫髮", "おだんご髪", "hair00", "ponytail_L", "アホ毛"}) do
        assert(hair.isHair(name), "miss " .. name)
    end
    for _, name in ipairs({"Hairpin", "Cloth_Hairpin", "hairband", "chair", "bangle", "髪飾り", "发饰", "髮+", "头发高光",
        "Hair_Bangs+", "hairshadow", "HairShadow", "髪留め+", "Hair_Back+", "发带", "髪リボン", "发影", "Hair_HL",
        "hair_spec", "Body", "", "Face"}) do
        assert(not hair.isHair(name), "false positive " .. name)
    end
    assert(not hair.isHair(nil) and not hair.isHair(12))
    local good = {name = "Hair", alphaTexture = true, base = "abc", alpha = 1}
    assert(hair.eligible(good))
    assert(not hair.eligible({name = "Hair", alphaTexture = false, base = "abc", alpha = 1}))
    assert(not hair.eligible({name = "Hair", alphaTexture = true, base = "", alpha = 1}))
    assert(not hair.eligible({name = "Hair", alphaTexture = true, base = "abc", alpha = 0.5}))
    assert(not hair.eligible({name = "Hairpin", alphaTexture = true, base = "abc", alpha = 1}))
    assert(not hair.eligible(nil))
    pass()
end

-- A hotloader texture: single-frame RGBA8888 VTF 7.2, mips smallest first; alpha(x, y) for the top mip.
local function vtf(size, alpha, options)
    options = options or {}
    local mips, s = 0, size
    while true do mips = mips + 1 if s == 1 then break end s = math.max(1, math.floor(s / 2)) end
    local header = {} for i = 1, 80 do header[i] = 0 end
    local function put(pos, value, count) for i = 0, count - 1 do header[pos + i] = value % 256 value = math.floor(value / 256) end end
    header[1], header[2], header[3] = 86, 84, 70
    put(5, 7, 4) put(9, options.minor or 2, 4) put(13, 80, 4) put(17, size, 2) put(19, size, 2)
    put(25, 1, 2) put(53, options.format or 0, 4) put(57, mips, 1) put(58, 4294967295, 4) put(64, 1, 2)
    local out = {} for i, byte in ipairs(header) do out[i] = string.char(byte) end
    local sizes, w = {}, size
    for i = 1, mips do sizes[i] = w w = math.max(1, math.floor(w / 2)) end
    for i = mips, 2, -1 do out[#out + 1] = string.rep("\90\60\50\255", sizes[i] * sizes[i]) end
    for y = 0, size - 1 do
        local row = {}
        for x = 0, size - 1 do row[x + 1] = "\200\100\90" .. string.char(alpha(x, y)) end
        out[#out + 1] = table.concat(row)
    end
    return table.concat(out)
end
-- Alpha classes by a texel's place in each run of 200: clear, low (cut by 0.5), high, opaque.
local function pattern(clear, low, high)
    return function(x, y)
        local r = (y * 64 + x) % 200
        if r < clear then return 0 elseif r < clear + low then return 60 elseif r < clear + low + high then return 200 end
        return 255
    end
end
local TEXTURES = {
    laevatain = vtf(64, pattern(8, 5, 5)),          -- clear 4 %, cut 2.5 %, high 2.5 %: the user's case
    card = vtf(64, pattern(80, 2, 2)),              -- 40 % clear: strands cut out of the texture
    binary = vtf(64, function(x, y) return ((y * 64 + x) % 1000 < 60) and 0 or 255 end), -- 6 % clear, no partial
    sheer = vtf(64, pattern(0, 30, 30)),            -- 30 % partial: see-through on purpose
    soft_only_high = vtf(64, pattern(0, 0, 10)),    -- 5 % partial, all above half: nothing to fix
}
if scenario == "vtf" then
    local shares = assert(hair.alphaShares(TEXTURES.laevatain))
    assert(shares.samples == 4096 and shares.width == 64 and shares.height == 64)
    assert(math.abs(shares.clear - 0.04) < 0.002 and math.abs(shares.low - 0.025) < 0.002 and math.abs(shares.high - 0.025) < 0.002)
    assert(math.abs(shares.partial - 0.05) < 0.003 and hair.solid(shares))
    assert(not hair.solid(assert(hair.alphaShares(TEXTURES.card))))
    assert(not hair.solid(assert(hair.alphaShares(TEXTURES.binary))))
    assert(not hair.solid(assert(hair.alphaShares(TEXTURES.sheer))))
    assert(not hair.solid(assert(hair.alphaShares(TEXTURES.soft_only_high))))
    assert(not hair.solid(nil))
    -- A few rows per step give the same shares as the whole file.
    local bytes = TEXTURES.laevatain
    local info = assert(hair.layout(bytes:sub(1, 80), #bytes))
    assert(info.top == #bytes - 64 * 64 * 4)
    local job, steps, result = hair.sampler(info), 0, false
    repeat
        steps = steps + 1
        result = job.step(function(offset, length) return bytes:sub(offset + 1, offset + length) end, 8)
    until result ~= false
    assert(steps == 8 and result.low == shares.low and result.clear == shares.clear)
    -- Large textures are sampled on a 256-square grid.
    local big = assert(hair.alphaShares(vtf(1024, pattern(8, 5, 5))))
    assert(big.samples == 65536, big.samples)
    for _, invalid in ipairs({bytes:sub(2), bytes:sub(1, -2), bytes .. "x", vtf(8, pattern(0, 0, 0), {format = 13}),
        vtf(8, pattern(0, 0, 0), {minor = 5}), "VTF\0", 42}) do
        assert(hair.alphaShares(invalid) == nil, "accepted an invalid VTF")
    end
    local job2 = hair.sampler(info)
    local bad, why = job2.step(function() return "short" end, 1)
    assert(bad == nil and why == "read")
    pass()
end

-- The controller and the hotloader against fixtures.
local now, frame, hooks, commands, cvs, printed = 0, 0, {}, {}, {}, {}
local reads, frameReads, maxFrameReads, manifestReads = 0, 0, 0, 0
function istable(x) return type(x) == "table" end
function isstring(x) return type(x) == "string" end
function isfunction(x) return type(x) == "function" end
function isnumber(x) return type(x) == "number" end
function IsValid(x) return type(x) == "table" and not x.removed end
function include(path) return dofile(base .. path) end
function RealTime() return now end
function SysTime() return now end
function FrameNumber() return frame end
table.Count = function(t) local n = 0 for _ in pairs(t) do n = n + 1 end return n end
function print(...) local parts = {} for i = 1, select("#", ...) do parts[i] = tostring((select(i, ...))) end printed[#printed + 1] = table.concat(parts, "\t") end
function CreateClientConVar(name, value)
    if cvs[name] then return cvs[name] end
    local cv = {value = value}
    function cv:GetString() return self.value end
    function cv:GetBool() return self.value ~= "0" end
    cvs[name] = cv return cv
end
hook = {Add = function(event, name, fn) hooks[event .. ":" .. name] = fn hooks[event] = fn end}
concommand = {Add = function(name, fn) commands[name] = fn end}
timer = {Simple = function() end}
CLIENT, SERVER = true, false

local ALPHATEST, TRANSLUCENT = 256, 2097152
local materials = {}
local function makeMaterial(name, flags, texture)
    local mat = {name = name, params = {["$flags"] = flags, ["$allowalphatocoverage"] = 1}, texture = texture, recomputes = 0}
    function mat:IsError() return false end
    function mat:GetInt(key) return self.params[key] end
    function mat:SetInt(key, value) self.params[key] = value end
    function mat:Recompute() self.recomputes = self.recomputes + 1 end
    function mat:GetTexture() return {GetName = function() return mat.texture end, IsError = function() return false end} end
    materials[name] = mat
    return mat
end
local ERROR = {IsError = function() return true end}
function Material(name)
    -- Distinct wrappers per call, as in GMod; they share the native state.
    local mat = materials[name]
    if not mat then return ERROR end
    return setmetatable({}, {__index = mat})
end
local disk = {}
file = {}
function file.Exists(path) return disk[path] ~= nil end
function file.Size(path) return disk[path] and #disk[path] or -1 end
function file.Read(path)
    if path:match("manifest%.json$") then manifestReads = manifestReads + 1 end
    return disk[path]
end
function file.Open(path)
    local bytes = disk[path]
    if not bytes then return nil end
    local handle, pos = {closed = false}, 0
    function handle:Size() return #bytes end
    function handle:Seek(offset) pos = offset end
    function handle:Read(length)
        reads, frameReads = reads + 1, frameReads + 1
        local out = bytes:sub(pos + 1, pos + length) pos = pos + length return out
    end
    function handle:Close() self.closed = true end
    return handle
end
util = {JSONToTable = function(raw) local fn = loadstring("return " .. raw) return fn and fn() end}

-- Two characters: Laevatain-like (Moyin, Hair+, solid hair) and a card-hair one.
local LAEV = string.rep("a", 64)
local CARD = string.rep("c", 64)
local function asset(id, parts)
    local info = {name = id == LAEV and "Laevatain" or "Card", materials = {}}
    for i, p in ipairs(parts) do
        p.path = "mmd/" .. id:sub(1, 16) .. "/" .. p.name .. "_" .. i
        info.materials[i] = p
    end
    return info
end
local function laevParts()
    return {
        {name = "Body", alpha = 1, diffuse = {1, 1, 1}, base = "b0", count = 1000000, alphaTexture = false},
        {name = "Moyin", alpha = 0.5, diffuse = {0, 0, 0}, base = "", count = 96},
        {name = "Hair", alpha = 1, diffuse = {1, 1, 1}, base = "b1", count = 140000, alphaTexture = true, softTriangles = 30},
        {name = "Hair+", alpha = 0.5, diffuse = {0, 0, 0}, base = "", count = 444},
        {name = "材質12", alpha = 0.3, diffuse = {1, 1, 1}, base = "b2", count = 150},
    }
end
local function cardParts()
    return {
        {name = "Body", alpha = 1, diffuse = {1, 1, 1}, base = "b0", count = 400000},
        {name = "Hair", alpha = 1, diffuse = {1, 1, 1}, base = "b3", count = 90000, alphaTexture = true, softTriangles = 5},
    }
end
local remix = scenario ~= "remix_off"
mmdhl = {assets = {}, softMaterials = {}}
mmdhl.assets[LAEV] = asset(LAEV, laevParts())
mmdhl.assets[CARD] = asset(CARD, cardParts())
local ents = {{asset = LAEV}, {asset = CARD}}
function mmdhl.Entities() local out = {} for _, e in ipairs(ents) do if not e.removed then out[#out + 1] = e end end return out end
function mmdhl.GetAsset(ent) return ent.asset end
function mmdhl.UsesRemixPreview() return remix end
-- The mounted materials: Laevatain's hair texture is the user's case, the other one is card hair.
local laevHair = makeMaterial(mmdhl.assets[LAEV].materials[3].path, 256 + 2048 + 536870912, "mmd/t/1111111111111111")
local cardHair = makeMaterial(mmdhl.assets[CARD].materials[2].path, 256 + 2048 + 536870912, "mmd/t/2222222222222222")
disk["materials/" .. laevHair.name .. ".vmt"] = "vmt"
disk["materials/" .. cardHair.name .. ".vmt"] = "vmt"
disk["materials/mmd/t/1111111111111111.vtf"] = TEXTURES.laevatain
disk["materials/mmd/t/2222222222222222.vtf"] = TEXTURES.card
disk["mmd_hotloader/assets/" .. LAEV .. "/manifest.json"] = scenario == "big_manifest" and string.rep(" ", 9 * 1024 * 1024) or
    '{materials = {{base = "tex/Body.png"}, {base = ""}, {base = "tex/T_actor_laevat_hair_01_D.png"}, {base = ""}, {base = "sph/黑.jpg"}}}'
local softName = "!mmdhl_soft_v1_" .. LAEV .. "_3"
local laevSoft
local function makeSoft()
    laevSoft = makeMaterial(softName, 2097152 + 8192 + 2048, "mmd/t/1111111111111111")
    mmdhl.softMaterials[LAEV] = {soft = {"", "", softName, "", ""}}
end
if scenario ~= "late_soft" then makeSoft() end

dofile(base .. "autorun/client/nativeloader_imported_parts.lua")
local think = hooks["Think:nativeloader_imported_parts"]
assert(think and commands.nativeloader_imported_parts_status and hooks["ShutDown:nativeloader_imported_parts"])
local function run(seconds, step)
    step = step or 0.05
    local t = 0
    while t < seconds - 1e-9 do
        frameReads = 0
        think()
        maxFrameReads = math.max(maxFrameReads, frameReads)
        now, frame, t = now + step, frame + 1, t + step
    end
end
local function flags(mat) return mat.params["$flags"] end

if scenario == "hidden" or scenario == "remix_off" then
    run(1.2)
    assert(mmdhl.RenderHiddenParts, "not installed")
    local hidden = mmdhl.RenderHiddenParts(ents[1])
    if scenario == "remix_off" then
        assert(hidden == nil)
        run(5)
        assert(flags(laevHair) == 256 + 2048 + 536870912 and reads == 0, "changed a material outside RTX")
        pass()
    end
    assert(hidden[2] and hidden[4] and not hidden[1] and not hidden[3], "Moyin and Hair+ only")
    assert(mmdhl.RenderHiddenParts(ents[2]) == nil, "card character has no painted shadows")
    cvs.nativeloader_hide_painted_shadows.value = "0"
    assert(mmdhl.RenderHiddenParts(ents[1]) == nil)
    cvs.nativeloader_hide_painted_shadows.value = "1"
    assert(mmdhl.RenderHiddenParts({asset = "bad id"}) == nil and mmdhl.RenderHiddenParts({}) == nil)
    -- The unnamed part painted from a black image is hidden once the manifest gave its path; one read.
    run(3)
    assert(mmdhl.RenderHiddenParts(ents[1])[5], "texture rule after the manifest")
    assert(manifestReads == 1, manifestReads)
    pass()
end
if scenario == "big_manifest" then
    run(3)
    assert(manifestReads == 0, "an oversized manifest was read")
    local hidden = mmdhl.RenderHiddenParts(ents[1])
    assert(hidden[2] and hidden[4] and not hidden[5])
    commands.nativeloader_imported_parts_status()
    local text = table.concat(printed, "\n")
    assert(text:find("texture paths: manifest size", 1, true), text)
    pass()
end
if scenario == "solid" or scenario == "late_soft" then
    run(3)
    assert(bit.band(flags(laevHair), ALPHATEST) == 0, "public material still alpha-tested")
    assert(laevHair.params["$allowalphatocoverage"] == 0)
    assert(bit.band(flags(laevHair), 2048 + 536870912) == 2048 + 536870912, "other flags kept")
    assert(flags(cardHair) == 256 + 2048 + 536870912 and cardHair.params["$allowalphatocoverage"] == 1, "card hair changed")
    assert(maxFrameReads <= 33, "texture rows per frame: " .. maxFrameReads)
    if scenario == "late_soft" then
        makeSoft()
        run(3)
    end
    assert(bit.band(flags(laevSoft), TRANSLUCENT) == 0, "soft copy still blended")
    assert(bit.band(flags(laevSoft), 8192 + 2048) == 8192 + 2048)
    -- A reloaded material gets its flag again, and loses it at the next check.
    laevHair.params["$flags"] = 256 + 2048 + 536870912
    run(2.5)
    assert(bit.band(flags(laevHair), ALPHATEST) == 0, "not applied again after a reload")
    -- Off: both are put back, with alpha-to-coverage.
    cvs.nativeloader_solid_hair.value = "0"
    run(2.5)
    assert(flags(laevHair) == 256 + 2048 + 536870912 and laevHair.params["$allowalphatocoverage"] == 1)
    assert(flags(laevSoft) == 2097152 + 8192 + 2048)
    -- On again, then shutdown puts them back.
    cvs.nativeloader_solid_hair.value = "1"
    run(2.5)
    assert(bit.band(flags(laevHair), ALPHATEST) == 0 and bit.band(flags(laevSoft), TRANSLUCENT) == 0)
    commands.nativeloader_imported_parts_status()
    local text = table.concat(printed, "\n")
    assert(text:find("hair #2 Hair: clear 4.1%, cut 2.6%, partial 5.1% (64x64", 1, true), text)
    assert(text:find("-> solid", 1, true) and text:find("(applied)", 1, true) and text:find("alpha test kept", 1, true))
    assert(text:find("shadow #1 Moyin: eye, by name", 1, true) and text:find("shadow #3 Hair+: hair, by painted", 1, true), text)
    hooks["ShutDown:nativeloader_imported_parts"]()
    assert(flags(laevHair) == 256 + 2048 + 536870912 and flags(laevSoft) == 2097152 + 8192 + 2048)
    pass()
end
if scenario == "reimport" then
    run(3)
    assert(bit.band(flags(laevHair), ALPHATEST) == 0)
    -- The library replaced the asset's metadata: what was applied is put back, then measured again.
    mmdhl.assets[LAEV] = asset(LAEV, laevParts())
    run(1.1)
    run(3)
    assert(bit.band(flags(laevHair), ALPHATEST) == 0, "not applied to the new record")
    -- The asset is gone: its flags are put back.
    mmdhl.assets[LAEV] = nil
    ents[1].removed = true
    run(1.5)
    assert(flags(laevHair) == 256 + 2048 + 536870912, "flags of a removed asset")
    assert(mmdhl.RenderHiddenParts(ents[1]) == nil)
    pass()
end
if scenario == "despawn" then
    -- A character never on the map is not measured; one that leaves keeps what was applied.
    ents[2].removed = true
    run(3)
    assert(reads > 0 and bit.band(flags(laevHair), ALPHATEST) == 0)
    local before = reads
    ents[1].removed = true
    run(3)
    assert(reads == before and bit.band(flags(laevHair), ALPHATEST) == 0)
    assert(flags(cardHair) == 256 + 2048 + 536870912)
    pass()
end

-- The shipped hotloader visibility hook: SyncMaterialState leaves hidden parts out of what it sends.
if scenario == "hook" then
    local meta = {}
    meta.GetBodygroup = function() return 0 end
    for _, name in ipairs({"GetMaterials", "GetSubMaterial", "SetSubMaterial", "GetBodyGroups", "GetNumBodyGroups",
        "SetBodygroup", "GetBodygroupCount", "GetBodygroupName", "FindBodygroupByName", "SetBodyGroups"}) do
        meta[name] = function() end
    end
    function FindMetaTable() return meta end
    properties = {}
    local sent = {}
    local rig = {materials = {}}
    for i = 1, 5 do rig.materials[i] = {name = "p" .. i, path = "mmd/x/p" .. i, defaultHidden = i == 5} end
    mmdhl = {native = {SetMaterialVisibility = function(_, encoded) sent[#sent + 1] = encoded return true end}}
    function mmdhl.IsMMD() return true end
    function mmdhl.GetRig() return rig end
    util = {TableToJSON = function(value)
        local function list(items) local out = {} for i, v in ipairs(items) do out[i] = tostring(v) end return "[" .. table.concat(out, ",") .. "]" end
        return '{"visible":' .. list(value.visible) .. ',"forceOpaque":' .. list(value.forceOpaque) .. "}"
    end}
    dofile(root .. "/packages/model-hotloader/mmd_hotloader/lua/mmdhl/materials.lua")
    local ent = setmetatable({}, {__index = meta})
    function ent:EntIndex() return 3 end
    function ent:GetNW2Int(_, default) return default end
    assert(mmdhl.SyncMaterialState(ent, 1))
    assert(sent[1] == '{"visible":[true,true,true,true,false],"forceOpaque":[false,false,false,false,false]}', sent[1])
    mmdhl.RenderHiddenParts = function(e) assert(e == ent) return {[2] = true, [4] = true} end
    frame = frame + 20
    assert(mmdhl.SyncMaterialState(ent, 1))
    assert(sent[2] == '{"visible":[true,false,true,false,false],"forceOpaque":[false,false,false,false,false]}', sent[2])
    -- An error in the add-on's list is ignored: the parts are drawn as before.
    mmdhl.RenderHiddenParts = function() error("broken") end
    frame = frame + 20
    assert(mmdhl.SyncMaterialState(ent, 1))
    assert(sent[3] == sent[1], sent[3])
    mmdhl.RenderHiddenParts = function() return "not a table" end
    frame = frame + 20
    assert(mmdhl.SyncMaterialState(ent, 1) and #sent == 3, "an unchanged state is sent again")
    pass()
end
error("unknown scenario " .. tostring(scenario))
