-- Localized by the native-loader companion when bundled; standalone use keeps the English.
local bundle_i18n = CLIENT and file.Exists("nativeloader/i18n.lua", "LUA")
    and include("nativeloader/i18n.lua") or nil
local NL = bundle_i18n and bundle_i18n.A or function(text) return text end
local NP = bundle_i18n and bundle_i18n.P or function(text) return text end
ENT.Type = "anim"
ENT.PrintName = NP("Pseudoplayer")
ENT.Author = "Xenthio"
ENT.Information = NL("For firstperson self shadows and body reflections with RTX")
ENT.Category = "RTX"
ENT.Spawnable = false
ENT.AdminSpawnable = false
AddCSLuaFile()
if not CLIENT then return end

CreateClientConVar("rtx_pseudoplayer_unique_hashes", "1", true, false)
CreateClientConVar("rtx_pseudoplayer_offset_localangles", "0", true, false)
CreateClientConVar("rtx_pseudoplayer_offset_x", "0", true, false)
CreateClientConVar("rtx_pseudoplayer_offset_z", "0", true, false)

local materials = {}
local materialFlags = {['$vertexcolor'] = 0x10, ['$vertexalpha'] = 0x20, ['$selfillum'] = 0x40,
    ['$additive'] = 0x80, ['$alphatest'] = 0x100, ['$nocull'] = 0x2000, ['$translucent'] = 0x200000}
local function offsetValue(name)
    local value = GetConVar(name):GetFloat()
    return value == value and math.Clamp(value, -128, 128) or 0
end

local function snapshotBones(ent, player)
    ent.RTXBoneSnapshot = nil
    local model = player:GetModel()
    if ent:GetModel() ~= model then return false end
    local angles = GetConVar("rtx_pseudoplayer_offset_localangles"):GetBool()
        and player:EyeAngles() or player:GetRenderAngles()
    local forward = Angle(0, angles.y, 0):Forward()
    local offset = forward * offsetValue("rtx_pseudoplayer_offset_x")
        + Vector(0, 0, offsetValue("rtx_pseudoplayer_offset_z"))
    local snapshot = {model = model, count = math.min(ent:GetBoneCount(), player:GetBoneCount()),
        offset = offset, bones = {}}
    for bone = 0, snapshot.count - 1 do
        local matrix = player:GetBoneMatrix(bone)
        local name = player:GetBoneName(bone)
        if matrix and name and name ~= "__INVALIDBONE__" then
            snapshot.bones[bone] = {matrix = matrix, origin = matrix:GetTranslation(), name = name}
        end
    end
    ent.RTXBoneSnapshot = snapshot
    return true
end

local function offsetBones(ent, count)
    local snapshot = ent.RTXBoneSnapshot
    if not snapshot or ent:GetModel() ~= snapshot.model then return end
    local limit = math.min(count or ent:GetBoneCount(), ent:GetBoneCount(), snapshot.count)
    for bone = 0, limit - 1 do
        local entry = snapshot.bones[bone]
        local name = ent:GetBoneName(bone)
        if entry and name and name ~= "__INVALIDBONE__" and name == entry.name
            and (not ent.BoneHasFlag or BONE_USED_BY_ANYTHING == nil
                or ent:BoneHasFlag(bone, BONE_USED_BY_ANYTHING))
            and ent:GetBoneMatrix(bone) then
            -- A callback may run more than once per draw. Always offset the saved origin.
            entry.matrix:SetTranslation(entry.origin + snapshot.offset)
            ent:SetBoneMatrix(bone, entry.matrix)
        end
    end
end

local function proxyMaterial(name, skin)
    local original = Material(name)
    if original:IsError() then return end
    local shader = original:GetShader():gsub("_DX%d+$", "")
    local eye = shader:lower():find("eye", 1, true)
    local texture = eye and original:GetTexture("$iris") or original:GetTexture("$basetexture")
    if not texture or texture:IsError() then texture = original:GetTexture("$basetexture") end
    if not texture or texture:IsError() then return end
    if eye then shader = "VertexLitGeneric" end
    local key = util.CRC(name .. ":" .. skin .. ":" .. texture:GetName())
        .. "_" .. texture:Width() .. "x" .. texture:Height()
    if materials[key] then return materials[key] end

    -- A private texture keeps the player's shadow classification off shared arms/ragdoll textures.
    local opaque = CreateMaterial("pseudoplayercopy_" .. key, "UnlitGeneric", {
        ["$basetexture"] = texture:GetName(), ["$model"] = "1"})
    local alpha = CreateMaterial("pseudoplayercopyalpha_" .. key, "UnlitGeneric", {
        ["$basetexture"] = texture:GetName(), ["$model"] = "1", ["$translucent"] = "1"})
    local target = GetRenderTargetEx("pseudoplayertarget_v2_" .. key, texture:Width(), texture:Height(),
        RT_SIZE_LITERAL, MATERIAL_RT_DEPTH_NONE, 0, 0, IMAGE_FORMAT_RGBA8888)
    render.PushRenderTarget(target)
    render.Clear(0, 0, 0, 0, true, true)
    cam.Start2D()
    render.OverrideAlphaWriteEnable(true, true)
    render.SetWriteDepthToDestAlpha(false)
    render.SetMaterial(opaque)
    render.DrawScreenQuad()
    render.SetMaterial(alpha)
    render.DrawScreenQuad()
    render.CapturePixels()
    local r, g, b = render.ReadPixel(0, 0)
    render.OverrideAlphaWriteEnable(true, false)
    surface.SetDrawColor(r, g, 255 - b, 255)
    surface.DrawRect(0, 0, 1, 1)
    render.OverrideAlphaWriteEnable(false)
    cam.End2D()
    local image = render.Capture({format = "png", x = 0, y = 0,
        w = target:Width(), h = target:Height(), alpha = true})
    render.PopRenderTarget()
    if not image then return end

    file.CreateDir("rtx_player_proxy")
    local path = "rtx_player_proxy/v2_" .. key .. ".png"
    file.Write(path, image)
    local copy = Material("data/" .. path, "smooth"):GetTexture("$basetexture")
    if not copy or copy:IsError() then return end
    local values = original:GetKeyValues()
    local flags = tonumber(values['$flags']) or 0
    for parameter, mask in pairs(materialFlags) do values[parameter] = bit.band(flags, mask) ~= 0 and '1' or '0' end
    -- CreateMaterial supplies these internal fields itself. Copying them emits duplicate-variable errors.
    values['$flags'], values['$flags2'], values['$flags_defined'], values['$flags_defined2'] = nil, nil, nil, nil
    values['$model'] = '1'
    local proxy = CreateMaterial("pseudoplayermaterial_v2_" .. key, shader, values)
    proxy:SetTexture("$basetexture", copy)
    local color = original:GetVector("$color2")
    if color then proxy:SetVector("$color2", color) end
    materials[key] = proxy
    return proxy
end

function ENT:Initialize()
    self.RTXMaterials = {}
    self.RTXCustomDraw = true
    self.RenderOverride = self.Draw
    self:AddCallback("BuildBonePositions", offsetBones)
    self.GetPlayerColor = function()
        local player = LocalPlayer()
        return IsValid(player) and player:GetPlayerColor() or Vector(1, 1, 1)
    end
    self:Think()
end

function ENT:Think()
    local player = LocalPlayer()
    if not IsValid(player) or not GetConVar("rtx_pseudoplayer"):GetBool() then
        self:Remove()
        return
    end
    local model = player:GetModel()
    if self:GetModel() ~= model then
        self.RTXBoneSnapshot = nil
        self:SetModel(model)
        self.RTXMaterials = {}
    end
    self:SetPos(player:GetPos())
    self:SetAngles(player:GetRenderAngles())
    if self:GetSkin() ~= player:GetSkin() then
        self:SetSkin(player:GetSkin())
        self.RTXMaterials = {}
    end
    for group = 0, player:GetNumBodyGroups() - 1 do
        self:SetBodygroup(group, player:GetBodygroup(group))
    end
    self:SetNoDraw(not player:Alive() or player:GetObserverMode() ~= OBS_MODE_NONE
        or player:GetViewEntity() ~= player or player:ShouldDrawLocalPlayer())
    self:NextThink(CurTime())
    return true
end

function ENT:Draw()
    if self:GetNoDraw() then return end
    local player = LocalPlayer()
    if not IsValid(player) then return end
    -- Reading another entity's bones while ours are being built can re-enter bone setup.
    player:SetupBones()
    if not snapshotBones(self, player) then return end
    for index, name in ipairs(self:GetMaterials()) do
        local override = player:GetSubMaterial(index - 1)
        if override and override ~= "" then name = override end
        local entry = self.RTXMaterials[index]
        if not entry or entry.name ~= name then
            local proxy = proxyMaterial(name, self:GetSkin())
            if not proxy then return end
            entry = {name = name, material = proxy}
            self.RTXMaterials[index] = entry
        end
        if RemixCategoryManager and RemixCategoryManager.RegisterPlayerProxyMaterial then
            RemixCategoryManager.RegisterPlayerProxyMaterial(entry.material:GetName())
        end
    end
    for index, entry in ipairs(self.RTXMaterials) do
        render.MaterialOverrideByIndex(index - 1, entry.material)
    end
    self:InvalidateBoneCache()
    render.SuppressEngineLighting(true)
    local ok, err = pcall(self.DrawModel, self)
    render.SuppressEngineLighting(false)
    render.MaterialOverrideByIndex()
    if not ok then ErrorNoHalt("[gmRTX] Player proxy draw: " .. tostring(err) .. "\n") end
end

ENT.DrawTranslucent = ENT.Draw
