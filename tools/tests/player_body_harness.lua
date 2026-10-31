local entityPath, categoryPath, menuPath = ...
local values = {rtx_pseudoplayer = "1", rtx_pseudoweapon = "1", rtx_pseudoplayer_unique_hashes = "0",
    rtx_pseudoplayer_offset_x = "0", rtx_pseudoplayer_offset_z = "12"}
local callbacks, timers, hooks, panels, categories = {}, {}, {}, {}, {}
local imageWrites, draws, playerBoneWrites = 0, 0, 0
local lighting, overrideCleared, pixelColor
local inBoneCallback, drawErrors = false, {}
local function convar(name)
    return {GetBool = function() return values[name] ~= "0" and values[name] ~= "" end,
        GetFloat = function() return tonumber(values[name]) or 0 end,
        GetString = function() return values[name] end}
end
function CreateClientConVar(name, default)
    if values[name] == nil then values[name] = default end
    return convar(name)
end
GetConVar = convar
isstring = function(v) return type(v) == "string" end
istable = function(v) return type(v) == "table" end
isfunction = function(v) return type(v) == "function" end
IsValid = function(v) return v and not v.removed end
math.Clamp = function(v, lo, hi) return math.max(lo, math.min(v, hi)) end
local vector = {}
vector.__index = vector
vector.__add = function(a, b) return Vector(a.x + b.x, a.y + b.y, a.z + b.z) end
vector.__mul = function(a, b) return Vector(a.x * b, a.y * b, a.z * b) end
function Vector(x, y, z) return setmetatable({x = x, y = y, z = z}, vector) end
function Angle(_, yaw)
    return {y = yaw, Forward = function() return Vector(math.cos(math.rad(yaw)), math.sin(math.rad(yaw)), 0) end}
end
local function boneMatrix()
    return {position = Vector(10, 20, 30), GetTranslation = function(self)
        return Vector(self.position.x, self.position.y, self.position.z)
    end, SetTranslation = function(self, position) self.position = position end}
end
local player = {model = "player", skin = 0, alive = true, observer = 0, third = false,
    boneCount = 2, boneNames = {}, missingBones = {}}
function player:GetModel() return self.model end
function player:GetSkin() return self.skin end
function player:GetPos() return Vector(10, 20, 30) end
function player:GetNumBodyGroups() return 2 end
function player:GetBodygroup(i) return i + 1 end
function player:GetSubMaterial() return "" end
function player:Alive() return self.alive end
function player:GetObserverMode() return self.observer end
function player:GetViewEntity() return self.viewEntity or self end
function player:ShouldDrawLocalPlayer() return self.third end
function player:GetRenderAngles() return Angle(0, 90) end
function player:EyeAngles() return Angle(0, 0) end
function player:GetPlayerColor() return Vector(1, 0.5, 0) end
function player:SetupBones() assert(not inBoneCallback, "source bone setup inside proxy callback") end
function player:GetBoneCount()
    assert(not inBoneCallback, "source bone count read inside proxy callback")
    return self.boneCount
end
function player:GetBoneName(i)
    assert(not inBoneCallback, "source bone name read inside proxy callback")
    return self.boneNames[i] or "Bone" .. i
end
function player:GetBoneMatrix(i)
    assert(not inBoneCallback, "source matrix read inside proxy callback")
    return not self.missingBones[i] and boneMatrix() or nil
end
function player:ManipulateBonePosition() playerBoneWrites = playerBoneWrites + 1; error("real player bone edited") end
function player:ManipulateBoneAngles() playerBoneWrites = playerBoneWrites + 1; error("real player bone edited") end
LocalPlayer = function() return player end
CurTime = function() return 1 end
CLIENT, OBS_MODE_NONE, EF_BONEMERGE = true, 0, 1
BONE_USED_BY_ANYTHING = 524032
AddCSLuaFile = function() end
file = {Exists = function() return false end, CreateDir = function() end,
    Write = function() imageWrites = imageWrites + 1 end}
local function texture(name)
    return {GetName = function() return name end, IsError = function() return false end,
        Width = function() return 32 end, Height = function() return 32 end}
end
local createdShaders = {}
local function material(name)
    return {GetName = function() return name end, IsError = function() return false end,
        GetTexture = function() return texture(name) end,
        GetShader = function() return name:find("eyes", 1, true) and "Eyes_DX8" or "VertexLitGeneric" end,
        GetKeyValues = function() return {['$flags'] = 0x2100, ['$flags2'] = 1,
            ['$flags_defined'] = 1, ['$flags_defined2'] = 1} end, SetTexture = function() end,
        GetVector = function() return Vector(1, 1, 1) end, SetVector = function() end}
end
Material = material
CreateMaterial = function(name, shader, values)
    if name:find('^pseudoplayermaterial') then
        assert(values['$flags'] == nil and values['$flags_defined2'] == nil)
        assert(values['$alphatest'] == '1' and values['$nocull'] == '1')
    end
    createdShaders[name] = shader
    return material(name)
end
GetRenderTargetEx = texture
local sequence = 0
util = {CRC = function() sequence = sequence + 1; return tostring(sequence) end}
render = setmetatable({ReadPixel = function() return 255, 255, 255 end,
    Capture = function() return "PNG" end,
    SuppressEngineLighting = function(v) lighting = v end,
    ModelMaterialOverride = function() overrideCleared = true end,
    MaterialOverrideByIndex = function(index, mat)
        if index == nil then overrideCleared = true; return end
        assert(mat:GetName():find("^pseudoplayermaterial_v2_"), "shared material used on proxy")
    end}, {__index = function() return function() end end})
cam = {Start2D = function() end, End2D = function() end}
surface = {SetDrawColor = function(r, g, b, a) pixelColor = {r, g, b, a} end, DrawRect = function() end}
ErrorNoHalt = function(message) drawErrors[#drawErrors + 1] = message end
ENT = {}
dofile(entityPath)
local proxy = setmetatable({skin = 0, bones = {}, boneCount = 2, boneNames = {},
    unusedBones = {}, missingBones = {}, boneWrites = {}}, {__index = ENT})
function proxy:AddCallback(_, fn) self.boneCallback = fn end
function proxy:GetModel() return self.model end
function proxy:SetModel(v) self.model = v; self.bones = {} end
function proxy:SetPos(v) self.pos = v end
function proxy:SetAngles(v) self.angles = v end
function proxy:SetParent(v) self.parent = v end
function proxy:AddEffects() end
function proxy:RemoveEffects() end
function proxy:GetSkin() return self.skin end
function proxy:SetSkin(v) self.skin = v end
function proxy:SetBodygroup(i, v) self.groups = self.groups or {}; self.groups[i] = v end
function proxy:SetNoDraw(v) self.hidden = v end
function proxy:GetNoDraw() return self.hidden end
function proxy:NextThink() end
function proxy:Remove() self.removed = true end
function proxy:GetMaterials() return self.sourceMaterials or {"models/player/shared"} end
function proxy:GetBoneCount() return self.boneCount end
function proxy:GetBoneName(i) return self.boneNames[i] or "Bone" .. i end
function proxy:BoneHasFlag(i, mask)
    assert(mask == BONE_USED_BY_ANYTHING)
    return not self.unusedBones[i]
end
function proxy:GetBoneMatrix(i) return self.bones[i] end
function proxy:SetBoneMatrix(i, v)
    assert(i < self.boneCount and i < player.boneCount, "bone count exceeded")
    assert(self:GetBoneName(i) ~= "__INVALIDBONE__" and not self.unusedBones[i],
        "invalid or unused destination written")
    assert(not self.missingBones[i], "unavailable destination written")
    assert(self:GetBoneName(i) == (player.boneNames[i] or "Bone" .. i), "mismatched bone written")
    self.boneWrites[i] = (self.boneWrites[i] or 0) + 1
    self.bones[i] = v
end
local function buildBones(count)
    inBoneCallback = true
    local ok, err = pcall(proxy.boneCallback, proxy, count)
    inBoneCallback = false
    if not ok then error(err) end
end
function proxy:InvalidateBoneCache() end
function proxy:DrawModel()
    draws = draws + 1
    if self.failDraw then error("draw failure") end
    self.boneWrites = {}
    for i = 0, self.boneCount - 1 do
        self.bones[i] = not self.missingBones[i] and boneMatrix() or nil
    end
    buildBones(self.callbackCount or self.boneCount)
end
proxy:Initialize()
assert(proxy.parent == nil and proxy.groups[0] == 1 and not proxy.hidden)
assert(proxy.RTXCustomDraw and proxy.RenderOverride == proxy.Draw)
proxy:Draw()
assert(#drawErrors == 0, table.concat(drawErrors, "\n"))
assert(draws == 1 and imageWrites == 1 and pixelColor[3] == 0 and pixelColor[4] == 255,
    "even a white texture must receive a different private pixel")
proxy:Draw()
-- Reuse the same material cache entry despite the legacy unique_hashes=0 preference.
assert(draws == 2 and imageWrites == 1)
buildBones(2)
assert(proxy.bones[0].position.z == 42 and proxy.bones[1].position.z == 42)
buildBones(2)
assert(proxy.bones[0].position.z == 42 and proxy.bones[1].position.z == 42,
    "repeated callbacks accumulated the proxy offset")
values.rtx_pseudoplayer_offset_x = "10"
proxy:Draw()
buildBones(2)
assert(math.abs(proxy.bones[0].position.y - 30) < 0.001 and proxy.bones[0].position.z == 42)
values.rtx_pseudoplayer_offset_localangles = "1"
proxy:Draw()
buildBones(2)
assert(proxy.bones[0].position.x == 20 and proxy.bones[0].position.z == 42 and playerBoneWrites == 0)

-- Models can have unused bones, invalid names and LOD-specific matrix omissions.
player.boneCount, proxy.boneCount, proxy.callbackCount = 8, 9, 16
proxy.boneNames[1], proxy.boneNames[4] = "__INVALIDBONE__", "different"
proxy.unusedBones[2], proxy.missingBones[3] = true, true
player.missingBones[6], player.boneNames[7] = true, "__INVALIDBONE__"
proxy:Draw()
local written = 0
for _ in pairs(proxy.boneWrites) do written = written + 1 end
assert(written == 2 and proxy.boneWrites[0] == 1 and proxy.boneWrites[5] == 1,
    "unavailable or mismatched bones escaped the snapshot guards")
proxy.boneWrites = {}
buildBones(1)
assert(proxy.boneWrites[0] == 1 and proxy.boneWrites[5] == nil, "callback bone count ignored")
local flagMethod, flagMask = proxy.BoneHasFlag, BONE_USED_BY_ANYTHING
proxy.BoneHasFlag, BONE_USED_BY_ANYTHING, proxy.boneNames[2] = nil, nil, "__INVALIDBONE__"
buildBones(16)
proxy.BoneHasFlag, BONE_USED_BY_ANYTHING = flagMethod, flagMask
local beforeModelChange = draws
player.model = "changed_player"
proxy:Draw()
assert(draws == beforeModelChange, "a mismatched player/proxy model was drawn")
proxy.boneWrites = {}
buildBones(16)
assert(next(proxy.boneWrites) == nil, "a mismatched draw reused the previous model's snapshot")
proxy:Think()
proxy:Draw()
assert(draws == beforeModelChange + 1 and proxy.boneWrites[0] == 1,
    "model change did not rebuild the pose snapshot")
local savedModel = proxy.model
proxy.model, proxy.boneWrites = "other_proxy", {}
buildBones(16)
assert(next(proxy.boneWrites) == nil, "a snapshot was applied to a different proxy model")
proxy.model = savedModel
player.boneCount, proxy.boneCount, proxy.callbackCount = 2, 2, nil
player.boneNames, player.missingBones = {}, {}
proxy.boneNames, proxy.unusedBones, proxy.missingBones = {}, {}, {}
assert(#drawErrors == 0, table.concat(drawErrors, "\n"))
local copiesBeforeSkin = imageWrites
player.skin = 1; proxy:Think(); proxy:Draw(); assert(imageWrites == copiesBeforeSkin + 1)
proxy.sourceMaterials = {"models/player/eyes"}; proxy:Draw()
assert(createdShaders[proxy.RTXMaterials[1].material:GetName()] == "VertexLitGeneric")
player.alive = false; proxy:Think(); assert(proxy.hidden)
player.alive = true; player.third = true; proxy:Think(); assert(proxy.hidden)
player.third = false; player.observer = 1; proxy:Think(); assert(proxy.hidden)
player.observer = 0; player.viewEntity = {}; proxy:Think(); assert(proxy.hidden)
player.viewEntity = nil; proxy:Think(); assert(not proxy.hidden)
proxy.failDraw = true; overrideCleared = false; proxy:Draw()
assert(lighting == false and overrideCleared, "a failed body draw leaked render state into arms")
assert(#drawErrors == 1 and drawErrors[1]:find("draw failure", 1, true),
    "an unexpected draw error was swallowed")
values.rtx_pseudoplayer = "0"; proxy:Think(); assert(proxy.removed)

RemixCategoryManager = {CATEGORY = {THIRD_PERSON_PLAYER_MODEL = 0x80000, THIRD_PERSON_PLAYER_BODY = 0x100000},
    SetMaterialCategory = function(name, flags) categories[name] = flags end}
RemixMaterial = {GetAllTextureHashes = function(name)
        return name:find("pending", 1, true) and {} or {"0x123", "0x456"}
    end, FindTexturesByName = function() return {{name = "models/player/shared"},
    {name = "pseudoplayermaterial_v2_test"}, {name = "pseudoplayermaterialtemp1"},
    {name = "!pseudoweaponmaterial1"}, {name = "unrelated/pseudoplayermaterial"}} end}
local nativeFlags, savedPlayerTags = {['0x123'] = 0x1000}, {['0x123'] = true, ['0x456'] = true}
RemixMaterial.GetHashCategory = function(hash) return nativeFlags[hash] end
RemixMaterial.SetHashCategory = function(hash, flags)
    nativeFlags[hash] = flags
    if bit.band(flags, 0x80000) ~= 0 then savedPlayerTags[hash] = true end
    return true
end
RemixMaterial.RemoveHashCategory = function(hash)
    if bit.band(nativeFlags[hash] or 0, 0x80000) ~= 0 then savedPlayerTags[hash] = nil end
    nativeFlags[hash] = nil
    return true
end
function player:GetMaterials() return {'models/player/shared'} end
function player:GetHands() return nil end
_G.player = {GetAll = function() return {player} end}
ents = {FindByClass = function() return {} end}
concommand = {Add = function(name, fn) callbacks[name] = fn end}
timer = {Create = function(name, _, _, fn) timers[name] = fn end, Simple = function() end}
dofile(categoryPath)
callbacks.rtx_categorize_pseudoplayer()
assert(categories.pseudoplayermaterial_v2_test == 0x180000 and categories["!pseudoweaponmaterial1"] == 0x80000)
assert(not categories["models/player/shared"] and not categories.pseudoplayermaterialtemp1
    and not categories["unrelated/pseudoplayermaterial"], "shared world material categorized as player")
assert(not RemixCategoryManager.RegisterPlayerProxyMaterial("pseudoplayermaterial_v2_pending"))
timers.RemixPseudoplayerCategory_ProxyScan()
assert(not savedPlayerTags['0x123'] and nativeFlags['0x123'] == 0x1000,
    'saved shared-player tags were not removed while preserving unrelated categories')
assert(not savedPlayerTags['0x456'] and nativeFlags['0x456'] == nil,
    'file-authored player tags without native bookkeeping were not migrated')
values.rtx_auto_categorize_pseudoplayer = "0"
assert(not RemixCategoryManager.RegisterPlayerProxyMaterial("pseudoplayermaterial_v2_new"))

local written = {}
RemixConfig = {SetConfigVariable = function(key, value) written[key] = value end}
include = function() return {L = function(t) return t end, N = function(t) return t end,
    PreparePanel = function() end, languages = {}} end
cvars = {AddChangeCallback = function(name, fn) callbacks[name] = fn end}
hook = {Add = function(event, id, fn) hooks[event .. ":" .. id] = fn end}
spawnmenu = {AddToolMenuOption = function(_, _, id, _, _, _, fn) panels[id] = fn end,
    AddToolTab = function() end, AddToolCategory = function() end}
dofile(menuPath)
hooks["PopulateToolMenu:nativeloader_menu"]()
local controls = {}
local panel = {CheckBox = function(_, label, key) controls[key] = label end,
    ControlHelp = function() end, NumSlider = function(_, label, key, lo, hi, places)
        controls[key] = {label, lo, hi, places} end}
panels.nativeloader_player(panel)
assert(controls.rtx_pseudoplayer == "Local player shadow")
assert(controls.rtx_pseudoplayer_offset_z[2] == -32 and controls.rtx_pseudoplayer_offset_z[3] == 64)
values.rtx_pseudoplayer = "1"; callbacks.rtx_pseudoplayer()
assert(written["rtx.playerModel.enablePrimaryShadows"] == "True")
print("PASS: private body categories, proxy-only world-Z offsets, cleanup, and RTX menu controls")
