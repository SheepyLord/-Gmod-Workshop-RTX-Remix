-- Run the shipped matcher, VTF encoder and controller against a minimal engine/API fixture.
local root, scenario = arg[1], arg[2]
local base = root .. "/companion/nativeloader/lua/"
local names = dofile(base .. "nativeloader/eye_white_names.lua")
if scenario == "names" then
    for _, pair in ipairs({{"白目"}, {"眼白1"}, {"眼白2"}, {"眼睛眼白"}, {"眼白左"}, {"目白"}, {"顔（白目）"},
        {"Face_Eyewhite"}, {"Eye_White"}, {"Eye Whites"}, {"eyewhiteL"}, {"00_EyeWhite_はぅ"},
        {"Face008_GP_EyeWhite (Instance)"}, {"未知", "EyeWhite"}, {"Sclera"}, {"shirome"}, {"White eye"}, {"eyeball"}, {"目白底"}}) do
        assert(names.matches(unpack(pair)), "miss " .. pair[1])
    end
    for _, pair in ipairs({{"目影"}, {"目HL"}, {"目光"}, {"目ハイライト"}, {"瞳"}, {"目"}, {"眼睛"}, {"眼罩"},
        {"目白边"}, {"目白框"}, {"eye_back"}, {"眼角膜"}, {"eyeball_iris"}, {"eyewhitening"}, {"noteyewhite"},
        {"白目影", "EyeWhite"}, {"EyeWhite_shadow"}, {"Face"}, {"EyewhiteHighlight"}}) do
        assert(not names.matches(unpack(pair)), "false positive " .. pair[1])
    end
    print("PASS " .. scenario) return
end
local function fixture()
    local header = {} for i = 1, 80 do header[i] = 0 end
    local function put(pos, value, count) for i = 0, count - 1 do header[pos + i] = value % 256 value = math.floor(value / 256) end end
    header[1], header[2], header[3] = 86, 84, 70
    put(5, 7, 4) put(9, 2, 4) put(13, 80, 4) put(17, 4, 2) put(19, 4, 2)
    put(25, 1, 2) put(57, 3, 1) put(58, 4294967295, 4) put(64, 1, 2)
    local bytes = {} for i, byte in ipairs(header) do bytes[i] = string.char(byte) end
    return table.concat(bytes) .. string.rep("\128\129\130\255", 5) .. "\100\101\102\0" .. string.rep("\128\129\130\255", 15)
end
local source = fixture()
if scenario == "vtf" then
    local encoder = dofile(base .. "nativeloader/eye_white_vtf.lua")
    local changed, pixel = assert(encoder.proxy(source))
    assert(#source == #changed and pixel == 101)
    local differences = 0
    for i = 1, #source do if source:byte(i) ~= changed:byte(i) then differences = differences + 1 assert(i == pixel) end end
    assert(differences == 1 and source:sub(1, 100) == changed:sub(1, 100))
    for _, invalid in ipairs({source:sub(2), source:sub(1, -2), source .. "x", source:sub(1, 8) .. "\3" .. source:sub(10)}) do
        assert(not encoder.proxy(invalid))
    end
    print("PASS " .. scenario) return
end
local now, hooks, commands, cvs, writes, disk = 0, {}, {}, {}, {}, {}
local warm, lookups, frameLookups, maxLookups, refused = false, 0, 0, 0, 0
function istable(x) return type(x) == "table" end
function isfunction(x) return type(x) == "function" end
function include(path) return dofile(base .. path) end
function RealTime() return now end
function SysTime() return now end
function CreateClientConVar(name, value)
    local cv = {value = value}
    function cv:GetString() return self.value end
    function cv:GetBool() return self.value ~= "0" end
    cvs[name] = cv return cv
end
hook = {Add = function(event, _, fn) hooks[event] = fn end}
concommand = {Add = function(name, fn) commands[name] = fn end}
local original = {GetName = function() return "mmd/t/abc012" end, IsError = function() return false end}
local proxy = {GetName = function() return "../data/nativeloader/eye_whites/digest" end, IsError = function() return false end}
local function material(texture)
    local mat = {texture = texture}
    function mat:IsError() return false end
    function mat:GetTexture()
        if scenario == "wrappers" then
            local texture = self.texture
            return {GetName = function() return texture:GetName() end, IsError = function() return false end}
        end
        return self.texture
    end
    function mat:SetTexture(_, value)
        self.texture = scenario == "wrappers" and (value:GetName() == proxy:GetName() and proxy or original) or value
    end
    return mat
end
local eye, cheek, foreign = material(original), material(original), material(original)
local softEye = material(original)
local softAsset = string.rep("a", 64)
local softName = "mmdhl_soft_v1_" .. softAsset .. "_1"
local matName = "mmd/1234567890abcdef/part1"
local materialReady = scenario ~= "late_material"
function Material(name)
    if name == matName then return materialReady and eye or {IsError = function() return true end} end
    if name == "!" .. softName then return softEye end
    return foreign
end
function CreateMaterial(name, _, params)
    return material(name:match("_source$") and original or proxy)
end
file = {
    Exists = function(path, realm)
        if realm == "DATA" then return disk[path] ~= nil end
        return materialReady and (path == "materials/" .. matName .. ".vmt" or path == "materials/mmd/t/abc012.vtf")
    end,
    Size = function() return #source end,
    Read = function(path, realm) return realm == "DATA" and disk[path] or source end,
    Write = function(path, bytes) disk[path] = scenario == "edited_cache" and "user edit" or bytes end,
    CreateDir = function() end
}
util = {SHA256 = function() return "digest" end}
render = {PushRenderTarget = function() end, PopRenderTarget = function() end}
cam = {Start2D = function() end, End2D = function() end}
surface = {SetDrawColor = function() end, SetMaterial = function() end, DrawTexturedRect = function() warm = true end}
function GetRenderTarget() return {} end
local function api()
    RemixConfig = {SetConfigVariable = function(option, value)
        if scenario == "old_runtime" then return false end
        if scenario == "retry" and option:match("eyeWhiteAliases$") and value ~= "" and refused < 2 then refused = refused + 1 return false end
        writes[option] = value return true
    end}
    RemixMaterial = {TrackMaterial = function() return true end, GetAllTextureHashes = function(name)
        lookups, frameLookups = lookups + 1, frameLookups + 1
        if not warm or (scenario == "late_hash" and now < 2) then return {} end
        if scenario == "invalid_hash" then return {"0x0000", "x", "0x10000000000000000"} end
        return {name:match("_source$") and "0x2" or "0x1"}
    end}
end
if scenario ~= "no_api" and scenario ~= "late_api" then api() end
mmdhl = {assets = {one = {materials = {{name = "白目", path = matName}, {name = "颜", path = "mmd/1234567890abcdef/face"}}}}}
if scenario:match("^soft_") then
    mmdhl.assets[softAsset], mmdhl.assets.one = mmdhl.assets.one, nil
    if scenario ~= "soft_late" and scenario ~= "soft_inherited" then
        mmdhl.softMaterials = {[softAsset] = {soft = {"!" .. softName}}}
    end
    if scenario == "soft_foreign" then
        mmdhl.softMaterials[softAsset].soft[1] = "!mmdhl_soft_v1_" .. string.rep("b", 64) .. "_1"
    end
end
if scenario == "foreign" then original.GetName = function() return "models/shared/error" end end
if scenario == "bounded" then
    for i = 2, 4096 do mmdhl.assets.one.materials[i] = {name = "白目", path = "mmd/1234567890abcdef/part" .. i} end
end
dofile(base .. "autorun/client/nativeloader_eye_whites.lua")
if scenario == "disabled" then cvs.nativeloader_eye_whites.value = "0" end
local function frames(n)
    for _ = 1, n do
        now, frameLookups = now + .1, 0
        hooks.Think()
        hooks.PostRender()
        maxLookups = math.max(maxLookups, frameLookups)
    end
end
frames(60)
if scenario == "no_api" or scenario == "old_runtime" or scenario == "foreign" or scenario == "disabled" or
    scenario == "edited_cache" or scenario == "invalid_hash" then
    assert(eye.texture == original, "must fail closed")
elseif scenario == "late_api" then
    assert(eye.texture == original) api() frames(60) assert(eye.texture == proxy)
elseif scenario == "late_material" then
    assert(eye.texture == original) materialReady = true frames(60) assert(eye.texture == proxy)
elseif scenario == "bounded" then
    assert(maxLookups <= 16, "hash lookup budget")
else
    assert(eye.texture == proxy, "eye binding did not become ready")
    assert(cheek.texture == original, "a shared-atlas face must never be changed")
    assert(writes["rtx.gmod.eyeWhiteAliases"] == "0x0000000000000001=0x0000000000000002")
    if scenario:match("^soft_") then
        if scenario == "soft_late" or scenario == "soft_inherited" then
            softEye.texture = scenario == "soft_inherited" and proxy or original
            mmdhl.softMaterials = {[softAsset] = {soft = {"!" .. softName}}}
            frames(25)
        end
        if scenario == "soft_foreign" then assert(softEye.texture == original)
        else
            assert(softEye.texture == proxy, "eligible generated soft copy must share the eye-only identity")
            if scenario == "soft_user_edit" then
                local edit = {GetName = function() return "user/soft_edit" end}
                softEye.texture = edit cvs.nativeloader_eye_whites.value = "0" frames(10) assert(softEye.texture == edit)
            elseif scenario == "soft_prune" then
                mmdhl.assets = {} frames(25) assert(softEye.texture == original and eye.texture == original)
            else
                cvs.nativeloader_eye_whites.value = "0" frames(10) assert(softEye.texture == original and eye.texture == original)
            end
        end
    end
    if scenario == "brightness" then
        for _, percent in ipairs({"0", "100", "200", "999", "-5", "nan"}) do
            cvs.nativeloader_eye_white_brightness.value = percent frames(5)
            local expected = ({["0"]="0", ["100"]="1", ["200"]="2", ["999"]="2", ["-5"]="0", nan="1"})[percent]
            assert(writes["rtx.gmod.eyeWhiteBrightness"] == expected)
        end
    elseif scenario == "toggle" or scenario == "wrappers" then
        cvs.nativeloader_eye_whites.value = "0" frames(5) assert(eye.texture == original)
        cvs.nativeloader_eye_whites.value = "1" frames(10) assert(eye.texture == proxy)
    elseif scenario == "prune" then
        mmdhl.assets = {} frames(25) assert(eye.texture == original and writes["rtx.gmod.eyeWhiteAliases"] == "")
    elseif scenario == "user_edit" then
        local user = {GetName = function() return "user/custom" end} eye.texture = user
        cvs.nativeloader_eye_whites.value = "0" frames(10) assert(eye.texture == user)
    elseif scenario == "shutdown" then
        hooks.ShutDown() assert(eye.texture == original)
    end
end
print("PASS " .. scenario)
