-- GPL-2.0; part of Glass-Rewrite-Remix. Keep native map health, collisions and outputs intact.
local geometry = include("glass_map_geometry.lua")
local tracked, debris = {}, {}
local epoch = 0
local MAX_DEBRIS = 256
local MODEL = "models/hunter/blocks/cube025x025x025.mdl"

local function pose(pane, ent)
    local physics = ent:GetPhysicsObject()
    if IsValid(physics) then
        pane.position, pane.angles, pane.velocity = physics:GetPos(), physics:GetAngles(), physics:GetVelocity()
    end
end

local function track(ent)
    if not IsValid(ent) or ent:GetClass() ~= "func_breakable" then return end
    local index = ent:EntIndex()
    local pane = tracked[index]
    if pane and pane.entity == ent then return pane end
    local physics = ent:GetPhysicsObject()
    if not IsValid(physics) or physics:GetMaterial() ~= "glass" then return end
    local source = physics:GetMeshConvexes()
    if not source or #source == 0 or #source > 16 then return end
    local convexes = {}
    for _, mesh in ipairs(source) do
        local copy = geometry.Copy(mesh)
        if not copy then return end
        convexes[#convexes + 1] = copy
    end
    pane = {entity = ent, convexes = convexes, color = ent:GetColor(), epoch = epoch}
    pose(pane, ent)
    tracked[index] = pane
    return pane
end

local function scatter(pane)
    if pane.epoch ~= epoch then return end -- cleanup/changelevel must not manufacture broken windows
    local count = GetConVar("rtx_glass_shard_count")
    local desired = count and math.ceil(count:GetInt() * 1.5) or 18
    local localImpact = pane.impact and WorldToLocal(pane.impact, Angle(), pane.position, pane.angles) or Vector()
    local pieces = geometry.Fracture(pane.convexes, localImpact, desired)
    local transfer = GetConVar("rtx_glass_velocity_transfer")
    transfer = transfer and transfer:GetFloat() or 2
    local expensive = GetConVar("rtx_glass_expensive_shards")
    local active = {}
    for _, ent in ipairs(debris) do if IsValid(ent) then active[#active + 1] = ent end end
    debris = active
    for _, mesh in ipairs(pieces) do
        while #debris >= MAX_DEBRIS do
            local oldest = table.remove(debris, 1)
            if IsValid(oldest) then oldest:Remove() end
        end
        local block = ents.Create("procedural_shard")
        if IsValid(block) then
            block.RTX_MAP_DEBRIS = true
            block:SetPhysModel(MODEL)
            block:SetPhysScale(Vector(1, 1, 1))
            block:SetPos(pane.position)
            block:SetAngles(pane.angles)
            block:SetColor(pane.color)
            block:Spawn()
            local success = {}
            block:BuildCollision(mesh, success)
            local physics = block:GetPhysicsObject()
            if success[1] and IsValid(block) and IsValid(physics) then
                -- Independent VPhysics pieces: no welds and no particle-only tiny-shard replacement.
                block:SetCollisionGroup(expensive and expensive:GetBool() and COLLISION_GROUP_WORLD or COLLISION_GROUP_DEBRIS)
                local impulse = (pane.force or Vector()) * (0.02 * transfer / math.max(physics:GetMass(), 1))
                if impulse:LengthSqr() > 350 * 350 then impulse = impulse:GetNormalized() * 350 end
                physics:EnableMotion(true)
                physics:SetVelocity(pane.velocity + impulse + VectorRand() * (30 * transfer))
                physics:AddAngleVelocity(VectorRand() * (120 * transfer))
                physics:Wake()
                debris[#debris + 1] = block
            else
                SafeRemoveEntity(block)
            end
        end
    end
end

hook.Add("InitPostEntity", "rtx_map_glass", function()
    for _, ent in ipairs(ents.FindByClass("func_breakable")) do track(ent) end
end)
hook.Add("OnEntityCreated", "rtx_map_glass", function(ent)
    if ent:GetClass() ~= "func_breakable" then return end
    timer.Simple(0, function() track(ent) end)
end)
hook.Add("EntityTakeDamage", "rtx_map_glass", function(ent, damage)
    local pane = track(ent)
    if not pane then return end
    pose(pane, ent)
    pane.impact, pane.force = damage:GetDamagePosition(), damage:GetDamageForce()
end)
hook.Add("AcceptInput", "rtx_map_glass", function(ent, input)
    if string.lower(input) ~= "break" then return end
    local pane = track(ent)
    if pane then pose(pane, ent) end
end)
gameevent.Listen("break_breakable")
hook.Add("break_breakable", "rtx_map_glass", function(data)
    local index = tonumber(data.entindex)
    local pane = index and tracked[index]
    if not pane or pane.broken then return end
    pane.broken = true
    tracked[index] = nil
    -- The event can arrive after EntityRemoved, while the brush is still in its removal frame.
    -- Wait a tick so the native collision has gone before adding the independent fragments.
    timer.Simple(0, function() scatter(pane) end)
end)
hook.Add("EntityRemoved", "rtx_map_glass", function(ent)
    local index = ent:EntIndex()
    local pane = tracked[index]
    if not pane or pane.entity ~= ent then return end
    timer.Simple(0, function() if tracked[index] == pane then tracked[index] = nil end end)
end)
hook.Add("PreCleanupMap", "rtx_map_glass", function()
    epoch = epoch + 1
    tracked = {}
    for _, ent in ipairs(debris) do if IsValid(ent) then ent:Remove() end end
    debris = {}
end)
hook.Add("PostCleanupMap", "rtx_map_glass", function()
    for _, ent in ipairs(ents.FindByClass("func_breakable")) do track(ent) end
end)
