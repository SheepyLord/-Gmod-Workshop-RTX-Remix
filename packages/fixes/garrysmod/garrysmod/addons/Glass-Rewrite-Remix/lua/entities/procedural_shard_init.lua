-- Localized by the native-loader companion when bundled; standalone use keeps the English.
local bundle_i18n = CLIENT and file.Exists("nativeloader/i18n.lua", "LUA")
    and include("nativeloader/i18n.lua") or nil
local NL = bundle_i18n and bundle_i18n.A or function(text) return text end
local NP = bundle_i18n and bundle_i18n.P or function(text) return text end
local function NN(text) return text end
AddCSLuaFile()

// to shut up console
ENT.Type = "anim"
ENT.Base = "base_gmodentity"
ENT.Spawnable = false

local models = {
    "models/hunter/plates/plate1x1.mdl",
    "models/hunter/plates/plate2x2.mdl",
    "models/hunter/plates/plate4x4.mdl",
    "models/hunter/blocks/cube1x1x025.mdl",
    "models/hunter/blocks/cube2x2x025.mdl",
    "models/hunter/blocks/cube4x4x025.mdl",
    "models/hunter/blocks/cube1x1x1.mdl",
    "models/hunter/blocks/cube2x2x2.mdl",
    "models/hunter/blocks/cube4x4x4.mdl",
}

local names = {
    NP("Glass Thin 1"),
    NP("Glass Thin 2"),
    NP("Glass Thin 4"),
    NP("Glass Thick 1"),
    NP("Glass Thick 2"),
    NP("Glass Thick 4"),
    NP("Glass Block 1"),
    NP("Glass Block 2"),
    NP("Glass Block 4"),
}

local use_expensive = CreateConVar("glass_expensive_material", 0, {FCVAR_ARCHIVE, FCVAR_NOTIFY, FCVAR_REPLICATED}, "Use nicer material", 0, 1)

for k, v in ipairs(models) do
    local ENT = scripted_ents.Get("procedural_shard")
    ENT.Spawnable = true
    ENT.PrintName =  names[k]
    function ENT:SpawnFunction(ply, tr, class)
        local block = ents.Create("procedural_shard")
        block:SetPos(tr.HitPos)
        block:SetAngles(Angle(90, ply:EyeAngles()[2], 0))
        block:SetPhysModel(v)
        block:SetPhysScale(Vector(1, 1, 1))
        block:Spawn()
        block:BuildCollision(util.GetModelMeshes(block:GetPhysModel())[1].triangles)
        if use_expensive:GetBool() then block:SetMaterial("glass_rewrite/glass_refract") end

        local phys = block:GetPhysicsObject()
        if phys then phys:EnableMotion(false) end

        return block
    end

    scripted_ents.Register(ENT, "procedural_shard_" .. k)
end

local ENT = scripted_ents.Get("procedural_shard")
ENT.Spawnable = true
ENT.PrintName =  NP("​100% Fragile")
ENT.AdminOnly = true
function ENT:SpawnFunction(ply, tr, class)
    local block = ents.Create("procedural_shard")
    block:SetPos(tr.HitPos)
    block:SetAngles(Angle(90, ply:EyeAngles()[2], 0))
    block:SetPhysModel("models/hunter/blocks/cube2x2x025.mdl")
    block:SetPhysScale(Vector(1, 1, 1))
    block:Spawn()
    block:SetMaterial("phoenix_storms/stripes")
    block:BuildCollision(util.GetModelMeshes(block:GetPhysModel())[1].triangles)
    block.IS_FUNNY_GLASS = true

    local phys = block:GetPhysicsObject()
    if phys then phys:EnableMotion(false) end

    return block
end

scripted_ents.Register(ENT, "procedural_shard_fragile")

