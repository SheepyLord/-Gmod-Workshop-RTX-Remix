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

-- The draw runs every frame: the pose snapshot and its per-bone entries are reused from draw to draw,
-- each bone keeping the player's matrix and its original translation as three numbers, and the
-- offset is three numbers too, so a draw allocates no snapshot tables or vectors.
local function snapshotBones(ent, player)
    local snapshot = ent.RTXBoneSnapshot
    if not snapshot then
        snapshot = {bones = {}, count = 0}
        ent.RTXBoneSnapshot = snapshot
    end
    snapshot.model = nil
    local model = player:GetModel()
    if ent:GetModel() ~= model then return false end
    local angles = GetConVar("rtx_pseudoplayer_offset_localangles"):GetBool()
        and player:EyeAngles() or player:GetRenderAngles()
    -- Angle(0, yaw, 0):Forward() is (cos yaw, sin yaw, 0).
    local yaw, forward = math.rad(angles.y), offsetValue("rtx_pseudoplayer_offset_x")
    snapshot.dx, snapshot.dy = math.cos(yaw) * forward, math.sin(yaw) * forward
    snapshot.dz = offsetValue("rtx_pseudoplayer_offset_z")
    local count = math.min(ent:GetBoneCount(), player:GetBoneCount())
    local bones = snapshot.bones
    for bone = 0, math.max(count, snapshot.count) - 1 do
        local entry = bones[bone]
        local matrix = bone < count and player:GetBoneMatrix(bone) or nil
        local name = matrix and player:GetBoneName(bone)
        if name and name ~= "__INVALIDBONE__" then
            if not entry then
                entry = {}
                bones[bone] = entry
            end
            entry.matrix, entry.name = matrix, name
            entry.x, entry.y, entry.z = matrix:GetField(1, 4), matrix:GetField(2, 4), matrix:GetField(3, 4)
        elseif entry then
            entry.matrix = nil
        end
    end
    snapshot.count, snapshot.model = count, model
    return true
end

local function offsetBones(ent, count)
    local snapshot = ent.RTXBoneSnapshot
    if not snapshot or not snapshot.model or ent:GetModel() ~= snapshot.model then return end
    local limit = math.min(count or ent:GetBoneCount(), ent:GetBoneCount(), snapshot.count)
    local dx, dy, dz = snapshot.dx, snapshot.dy, snapshot.dz
    for bone = 0, limit - 1 do
        local entry = snapshot.bones[bone]
        local matrix = entry and entry.matrix
        local name = matrix and ent:GetBoneName(bone)
        if name and name ~= "__INVALIDBONE__" and name == entry.name
            and (not ent.BoneHasFlag or BONE_USED_BY_ANYTHING == nil
                or ent:BoneHasFlag(bone, BONE_USED_BY_ANYTHING))
            and ent:GetBoneMatrix(bone) then
            -- A callback may run more than once per draw. Always offset the saved origin.
            matrix:SetField(1, 4, entry.x + dx)
            matrix:SetField(2, 4, entry.y + dy)
            matrix:SetField(3, 4, entry.z + dz)
            ent:SetBoneMatrix(bone, matrix)
        end
    end
end

-- A slot whose material cannot be copied (no such material, no $basetexture or $iris) is left out
-- of the body rather than the whole body: drawn with its shared original it would be an ordinary,
-- uncategorized mesh around the first-person camera. Each name is reported once and not tried again
-- every frame; a failed capture is retried once, five seconds later.
local unavailable, failures, noSlot = {}, {}, nil
local function noCopy(name, reason, transient)
    failures[name] = (failures[name] or 0) + 1
    if failures[name] == 1 then
        print("[gmRTX] Player proxy: no private copy of '" .. tostring(name) .. "' (" .. reason
            .. "); that part is left out of the body")
    end
    unavailable[name] = (transient and failures[name] == 1) and RealTime() + 5 or math.huge
end
local function hiddenSlot()
    noSlot = noSlot or CreateMaterial("rtx_pseudoplayer_noslot", "VertexLitGeneric",
        {["$no_draw"] = "1", ["$model"] = "1", ["$translucent"] = "1", ["$alpha"] = "0"})
    return noSlot
end

-- The slots to draw and the material each copies: the model's materials with the player's
-- sub-material overrides. Read twice a second (and again after a model or skin change), not per draw.
local function slotNames(ent, player)
    local now = RealTime()
    local slots = ent.RTXSlotNames
    if slots and now < slots.refresh then return slots end
    slots = slots or {}
    local list = ent:GetMaterials() or {}
    for index, name in ipairs(list) do
        local override = player:GetSubMaterial(index - 1)
        slots[index] = override and override ~= "" and override or name
    end
    for index = #list + 1, #slots do slots[index] = nil end
    slots.refresh = now + 0.5
    ent.RTXSlotNames = slots
    return slots
end

local function proxyMaterial(name, skin)
    local original = Material(name)
    if original:IsError() then return nil, "material not found" end
    local shader = original:GetShader():gsub("_DX%d+$", "")
    local eye = shader:lower():find("eye", 1, true)
    local texture = eye and original:GetTexture("$iris") or original:GetTexture("$basetexture")
    if not texture or texture:IsError() then texture = original:GetTexture("$basetexture") end
    if not texture or texture:IsError() then return nil, "no $basetexture or $iris" end
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
    if not image then return nil, "capture failed", true end

    file.CreateDir("rtx_player_proxy")
    local path = "rtx_player_proxy/v2_" .. key .. ".png"
    file.Write(path, image)
    local copy = Material("data/" .. path, "smooth"):GetTexture("$basetexture")
    if not copy or copy:IsError() then return nil, "the copied texture did not load", true end
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
        self.RTXMaterials, self.RTXSlotNames = {}, nil
    end
    self:SetPos(player:GetPos())
    self:SetAngles(player:GetRenderAngles())
    if self:GetSkin() ~= player:GetSkin() then
        self:SetSkin(player:GetSkin())
        self.RTXMaterials, self.RTXSlotNames = {}, nil
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
    local slots, entries, now = slotNames(self, player), self.RTXMaterials, RealTime()
    for index = 1, #slots do
        local name = slots[index]
        local entry = entries[index]
        if not entry or entry.name ~= name or (not entry.material and now >= (unavailable[name] or 0)) then
            -- A slot without a material (no private copy) keeps its entry, so it is not tried every frame.
            entry = {name = name, created = now}
            if now >= (unavailable[name] or 0) then
                local proxy, reason, transient = proxyMaterial(name, self:GetSkin())
                if proxy then
                    unavailable[name], failures[name] = nil, nil
                    entry.material = proxy
                else
                    noCopy(name, reason, transient)
                end
            end
            entries[index] = entry
        end
        -- Categorized once: tried on every draw for two seconds (its hashes appear after its first
        -- draw), then twice a second, until it succeeds.
        if entry.material and not entry.registered and now >= (entry.retry or 0)
            and RemixCategoryManager and RemixCategoryManager.RegisterPlayerProxyMaterial then
            entry.registered = RemixCategoryManager.RegisterPlayerProxyMaterial(entry.material:GetName())
            entry.retry = now + (now - entry.created < 2 and 0 or 0.5)
        end
    end
    for index = #slots + 1, #entries do entries[index] = nil end
    for index = 1, #entries do
        render.MaterialOverrideByIndex(index - 1, entries[index].material or hiddenSlot())
    end
    self:InvalidateBoneCache()
    render.SuppressEngineLighting(true)
    local ok, err = pcall(self.DrawModel, self)
    render.SuppressEngineLighting(false)
    render.MaterialOverrideByIndex()
    if not ok then ErrorNoHalt("[gmRTX] Player proxy draw: " .. tostring(err) .. "\n") end
end

ENT.DrawTranslucent = ENT.Draw
