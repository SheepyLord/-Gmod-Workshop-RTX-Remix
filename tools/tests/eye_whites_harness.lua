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
local materialCalls, fileWrites = 0, 0
function istable(x) return type(x) == "table" end
function isfunction(x) return type(x) == "function" end
function include(path) return dofile(base .. path) end
function RealTime() return now end
function SysTime() return now end
function CreateClientConVar(name, value)
    if cvs[name] then return cvs[name] end
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
local softAsset = "1234567890abcdef" .. string.rep("a", 48)
local softName = "mmdhl_soft_v1_" .. softAsset .. "_1"
local matName = "mmd/1234567890abcdef/part1"
local materialReady = scenario ~= "late_material"
function Material(name)
    materialCalls = materialCalls + 1
    if name == matName then return materialReady and eye or {IsError = function() return true end} end
    if name == "!" .. softName then return softEye end
    return foreign
end
function CreateMaterial(name, _, params)
    return material(name:match("_source$") and original or proxy)
end
local sizes, times = {}, {}
file = {
    Exists = function(path, realm)
        if realm == "DATA" then return disk[path] ~= nil end
        return materialReady and (path == "materials/" .. matName .. ".vmt" or path == "materials/mmd/t/abc012.vtf")
    end,
    Size = function(path, realm)
        if scenario == "manual_oversize" and path == "nativeloader/eye_white_choices.json" then return 1024 * 1024 + 1 end
        if scenario == "manual_missing_size_zero" and realm == "DATA" and disk[path] == nil then return 0 end
        if realm == "DATA" then return disk[path] and (sizes[path] or #disk[path]) or -1 end
        return #source
    end,
    Read = function(path, realm)
        assert(scenario ~= "manual_oversize" or path ~= "nativeloader/eye_white_choices.json", "size check must precede reading")
        if realm == "DATA" then return disk[path] end return source
    end,
    Write = function(path, bytes)
        fileWrites = fileWrites + 1
        if scenario == "manual_write_fail" and path == "nativeloader/eye_white_choices.json" then return end
        disk[path] = scenario == "edited_cache" and "user edit" or bytes
    end,
    CreateDir = function() end,
    Find = function(pattern)
        local dir, out = pattern:match("^(.*/)"), {}
        for path in pairs(disk) do
            if path:sub(1, #dir) == dir and path:match("%.vtf$") then out[#out + 1] = path:sub(#dir + 1) end
        end
        table.sort(out)
        return out, {}
    end,
    Time = function(path) return times[path] or 0 end,
    Delete = function(path) disk[path], sizes[path], times[path] = nil, nil, nil end
}
if scenario == "cache_cap" then
    -- 1.2 GiB of older proxies: the oldest goes until the new one fits under 1 GiB.
    for name, entry in pairs({old1 = {600, 1}, old2 = {500, 2}, new3 = {100, 3}}) do
        local path = "nativeloader/eye_whites/" .. name .. ".vtf"
        disk[path], sizes[path], times[path] = "cached", entry[1] * 1024 * 1024, entry[2]
    end
end
local function clone(value)
    if type(value) ~= "table" then return value end
    local out = {} for key, child in pairs(value) do out[key] = clone(child) end return out
end
local json = {}
util = {SHA256 = function() return "digest" end,
    TableToJSON = function(value)
        local function encode(v)
            if type(v) ~= "table" then return type(v) == "string" and string.format("%q", v) or tostring(v) end
            local keys, out = {}, {} for key in pairs(v) do keys[#keys + 1] = key end table.sort(keys)
            for _, key in ipairs(keys) do out[#out + 1] = string.format("%q", key) .. ":" .. encode(v[key]) end
            return "{" .. table.concat(out, ",") .. "}"
        end
        local text = encode(value) json[text] = clone(value) return text
    end,
    JSONToTable = function(text) return clone(json[text]) end}
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
local info = {materials = {{name = "白目", path = matName}, {name = "颜", path = "mmd/1234567890abcdef/face"}}}
local entity = {valid = true}
function IsValid(value) return type(value) == "table" and value.valid == true end
mmdhl = {assets = {[softAsset] = info}, Entities = function() return {entity} end,
    GetAsset = function() return softAsset end}
local CHOICES = "nativeloader/eye_white_choices.json"
if scenario == "manual_mark" or scenario == "manual_reimport" or scenario == "manual_reload" or scenario == "manual_reset" or scenario == "manual_ui" or scenario == "manual_missing_size_zero" then
    info.materials[1].name = "目"
elseif scenario == "manual_exclusion" then info.materials[1].name = "EyeWhite_shadow" end
if scenario == "unspawned" then entity.valid = false end
if scenario == "preview" then entity.MMDHLPreviewRig = {} end
if scenario == "wrong_owner" then info.materials[1].path = "mmd/aaaaaaaaaaaaaaaa/eye_white" end
if scenario == "manual_corrupt" then disk[CHOICES] = "not json" end
if scenario == "manual_oversize" then disk[CHOICES] = "oversized" end
if scenario == "manual_write_fail" then
    disk[CHOICES] = util.TableToJSON({version = 1, assets = {[softAsset] = {["1:白目"] = false}}})
end
if scenario == "manual_limit" then
    local entries = {} for i = 1, 4096 do entries[i .. ":old"] = true end
    disk[CHOICES] = util.TableToJSON({version = 1, assets = {[softAsset] = entries}})
end
if scenario:match("^soft_") then
    if scenario ~= "soft_late" and scenario ~= "soft_inherited" then
        mmdhl.softMaterials = {[softAsset] = {soft = {"!" .. softName}}}
    end
    if scenario == "soft_foreign" then
        mmdhl.softMaterials[softAsset].soft[1] = "!mmdhl_soft_v1_" .. string.rep("b", 64) .. "_1"
    end
end
if scenario == "foreign" then original.GetName = function() return "models/shared/error" end end
if scenario == "bounded" then
    for i = 2, 4096 do info.materials[i] = {name = "白目", path = "mmd/1234567890abcdef/part" .. i} end
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
if scenario:match("^manual_") then
    local api = NATIVELOADER_EYE_WHITES
    if scenario == "manual_oversize" then
        assert(not api.SetChoice(softAsset, 1, true) and disk[CHOICES] == "oversized")
    elseif scenario == "manual_write_fail" then
        local before = disk[CHOICES]
        assert(eye.texture == original and not api.SetChoice(softAsset, 1, true)) frames(30)
        assert(disk[CHOICES] == before and eye.texture == original and api.Materials(softAsset)[1].choice == false)
    elseif scenario == "manual_corrupt" then
        assert(not api.SetChoice(softAsset, 1, true) and disk[CHOICES] == "not json")
    elseif scenario == "manual_limit" then
        assert(not api.SetChoice(softAsset, 1, true), "bounded saved choices")
    elseif scenario == "manual_external" then
        disk[CHOICES] = "user edit"
        assert(not api.SetChoice(softAsset, 1, false) and disk[CHOICES] == "user edit")
    elseif scenario == "manual_unmark" then
        assert(eye.texture == proxy)
        assert(api.SetChoice(softAsset, 1, false))
        assert(eye.texture == original, "unmark restores immediately")
        frames(30)
        assert(not api.Materials(softAsset)[1].selected and api.Materials(softAsset)[1].choice == false)
        assert(eye.texture == original and writes["rtx.gmod.eyeWhiteAliases"] == "")
        hooks.ShutDown() dofile(base .. "autorun/client/nativeloader_eye_whites.lua") frames(30)
        assert(eye.texture == original, "saved false outranks automatic name after map/restart")
    elseif scenario == "manual_asset_scope" then
        assert(api.SetChoice(softAsset, 1, false))
        local other = "1234567890abcdef" .. string.rep("b", 48)
        mmdhl.GetAsset = function() return other end
        mmdhl.assets[other], mmdhl.assets[softAsset] = clone(info), nil
        frames(30)
        assert(eye.texture == proxy, "a different full asset ID does not inherit a choice")
    elseif scenario == "manual_ui" then
        for i = 3, 31 do info.materials[i] = {name = "part" .. i, path = "mmd/1234567890abcdef/part" .. i} end
        local widgets, baseThinks = {}, 0
        local function panel(kind)
            local p = {valid = true, kind = kind, children = {}}
            if kind == "DFrame" then p.Think = function() baseThinks = baseThinks + 1 end end
            widgets[#widgets + 1] = p
            for _, method in ipairs({"Dock", "SetTall", "SetWrap", "SetSize", "SetWide", "Center", "SetTitle",
                "MakePopup", "DockMargin", "SetKeepAspect", "SetTooltip", "SetTextColor"}) do p[method] = function() end end
            function p:SetText(text) self.text = text end
            function p:SetValue(text) self.text = text end
            function p:SetEnabled(value) self.enabled = value end
            function p:SetChecked(value) self.checked = value end
            function p:SetMaterial(value) self.material = value end
            function p:Add(name) local child = panel(name) self.children[#self.children + 1] = child return child end
            function p:Clear() self.children = {} end
            function p:AddChoice(text, id) self.children[#self.children + 1] = {text = text, id = id} return #self.children end
            function p:ChooseOptionID(i) self:OnSelect(i, self.children[i].text, self.children[i].id) end
            return p
        end
        vgui = {Create = panel}
        function ScrW() return 1280 end
        function ScrH() return 720 end
        function Color(r, g, b, a) return {r = r, g = g, b = b, a = a or 255} end
        local oldInclude = include
        function include(path) if path == "nativeloader/i18n.lua" then return {L = function(x) return x end} end return oldInclude(path) end
        local frame = api.Open(entity)
        frame.Think()
        local check, reset, nextButton, scroll, preview
        for _, p in ipairs(widgets) do
            if p.kind == "DCheckBoxLabel" and not check then check = p end
            if p.text == "Use automatic detection" and not reset then reset = p end
            if p.text == "Next materials" then nextButton = p end
            if p.kind == "DScrollPanel" then scroll = p end
            if p.kind == "DImage" and not preview then preview = p end
        end
        assert(check.enabled and not check.checked and not reset.enabled and preview.material, "thumbnail and initial toggle")
        check:OnChange(true) frames(30)
        assert(eye.texture == proxy and check.checked and reset.enabled, "UI mark applies live")
        reset:DoClick() frames(30)
        assert(eye.texture == original and not check.checked and not reset.enabled, "UI returns to automatic")
        for _ = 1, 10 do frame.Think() end
        assert(#scroll.children == 24, "only one bounded page is populated")
        nextButton:DoClick()
        for _ = 1, 10 do frame.Think() end
        assert(#scroll.children == 7 and not nextButton.enabled, "next page lists the remaining materials")
        assert(baseThinks == 21, "preserve the normal DFrame Think method")
    else
        assert(eye.texture == original)
        local calls = materialCalls
        local rows = api.Materials(softAsset)
        assert(#rows == 2 and not rows[1].selected and materialCalls == calls, "metadata list must not load textures")
        assert(not api.SetChoice(softAsset, 0, true) and not api.SetChoice(softAsset, 1, "yes"))
        assert(api.SetChoice(softAsset, 1, true)) frames(30)
        assert(eye.texture == proxy and cheek.texture == original, "manual mark isolates the chosen material")
        assert(api.Materials(softAsset)[1].selected and api.Materials(softAsset)[1].choice == true)
        if scenario == "manual_reimport" then
            mmdhl.assets, entity.valid = {}, false frames(30)
            assert(eye.texture == original)
            mmdhl.assets[softAsset], entity.valid = clone(info), true frames(30)
            assert(eye.texture == proxy, "re-import must retain chosen eye white")
        elseif scenario == "manual_reload" then
            hooks.ShutDown() assert(eye.texture == original)
            dofile(base .. "autorun/client/nativeloader_eye_whites.lua") frames(30)
            assert(eye.texture == proxy, "saved mark survives a fresh controller")
        elseif scenario == "manual_reset" then
            assert(api.SetChoice(softAsset, 1, nil)) frames(30)
            assert(eye.texture == original and api.Materials(softAsset)[1].choice == nil)
        end
    end
elseif scenario == "unspawned" or scenario == "preview" or scenario == "wrong_owner" then
    assert(eye.texture == original and materialCalls == 0 and fileWrites == 0, "unused/foreign assets do no texture work")
    assert(not NATIVELOADER_EYE_WHITES.SetChoice(softAsset, 1, true))
elseif scenario == "despawn" then
    assert(eye.texture == proxy) entity.valid = false frames(30)
    assert(eye.texture == original and writes["rtx.gmod.eyeWhiteAliases"] == "")
elseif scenario == "no_api" or scenario == "old_runtime" or scenario == "foreign" or scenario == "disabled" or
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
    elseif scenario == "cache_cap" then
        local dir = "nativeloader/eye_whites/"
        assert(disk[dir .. "old1.vtf"] == nil, "the oldest proxy must go first")
        assert(disk[dir .. "old2.vtf"] and disk[dir .. "new3.vtf"], "only what the limit needs may go")
        assert(disk[dir .. "digest.vtf"], "the new proxy must be written")
    end
end
print("PASS " .. scenario)
