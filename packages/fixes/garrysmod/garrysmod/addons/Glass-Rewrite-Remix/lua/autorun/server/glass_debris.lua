-- GPL-2.0; part of Glass-Rewrite-Remix. The server's loose broken glass (ADR 0061): every piece that broke
-- off a pane, from map windows (rtx_map_glass.lua) and from the add-on's own glass (Split in
-- procedural_shard.lua), oldest first. Each piece becomes interactive physics, at most MAX_PIECES exist,
-- and a piece older than rtx_glass_debris_lifetime seconds fades out (0 keeps it until map cleanup or
-- the budget).
local MAX_PIECES = 256
local SWEEP_INTERVAL = 1 -- seconds; a sweep reads only the oldest entries, never every entity
local pieces = {} -- {entity = ent, born = CurTime()}, oldest first

-- A piece that breaks again (its fragments take its place) or is fading out no longer counts.
local function current(entry)
    local ent = entry.entity
    return IsValid(ent) and not ent.GLASS_BREAKING and not ent.GLASS_FADING
end

-- Players, NPCs and vehicles pass through loose glass: a client has no physics copy of a shard to
-- predict against, so a solid piece would stop or trap a player whom the client lets walk on. The world
-- and props still collide with it, and traces still hit it: bullets, explosions, the physgun, the
-- gravity gun and +use reach every piece. With rtx_glass_expensive_shards 1 the pieces of a pile also
-- collide with each other (COLLISION_GROUP_WEAPON, which GMod gives props that must not collide with
-- players); with 0 they pass through each other (COLLISION_GROUP_DEBRIS), which costs less.
local function loosen(ent)
    local expensive = GetConVar("rtx_glass_expensive_shards")
    ent:SetCollisionGroup((not expensive or expensive:GetBool()) and COLLISION_GROUP_WEAPON or COLLISION_GROUP_DEBRIS)
    local physics = ent:GetPhysicsObject()
    if IsValid(physics) then
        physics:EnableMotion(true)
        physics:Wake()
    end
end

local function compact()
    local kept = {}
    for _, entry in ipairs(pieces) do
        if current(entry) then kept[#kept + 1] = entry end
    end
    pieces = kept
end

GlassRewriteDebris = {MAX_PIECES = MAX_PIECES}

-- A new loose piece: interactive, counted, and the oldest piece goes once there are too many.
function GlassRewriteDebris.Add(ent)
    if not IsValid(ent) then return end
    loosen(ent)
    pieces[#pieces + 1] = {entity = ent, born = CurTime()}
    if #pieces > MAX_PIECES then compact() end
    while #pieces > MAX_PIECES do
        local oldest = table.remove(pieces, 1)
        if current(oldest) then oldest.entity:Remove() end
    end
end

-- How many loose pieces exist (also for checks in game: lua_run print(GlassRewriteDebris.Count())).
function GlassRewriteDebris.Count()
    compact()
    return #pieces
end

-- Pieces are added as they are made, so the oldest come first: a sweep stops at the first one still
-- young enough. Changing the setting applies to the pieces that already lie around.
local function sweep()
    local setting = GetConVar("rtx_glass_debris_lifetime")
    local lifetime = setting and setting:GetFloat() or 0
    if lifetime <= 0 then return end
    local now = CurTime()
    while pieces[1] do
        local entry = pieces[1]
        local live = current(entry)
        if live and now - entry.born < lifetime then break end
        table.remove(pieces, 1)
        if live then
            local ent = entry.entity
            if ent.FadeOut then ent:FadeOut() else ent:Remove() end
        end
    end
end
timer.Create("glass_rewrite_debris_lifetime", SWEEP_INTERVAL, 0, sweep)

hook.Add("PreCleanupMap", "glass_rewrite_debris", function()
    for _, entry in ipairs(pieces) do
        if IsValid(entry.entity) then entry.entity:Remove() end
    end
    pieces = {}
end)
