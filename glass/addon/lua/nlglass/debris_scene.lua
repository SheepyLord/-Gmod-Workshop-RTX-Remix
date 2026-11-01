-- MIT. Bounded client-only Source snapshots. All mutations go to our Jolt mirrors, never Source.
local S = { bodies = 0, candidates = 0, queries = 0, capture_ms = 0, capture_peak_ms = 0, cooks = 0 }
local candidates, regions, states, serial, nextDiscovery = {}, {}, {}, 0, 0
local MAX_BODIES, MAX_ENTITIES, MAX_BONES = 96, 128, 24
local function finite(v, bound)
    return isvector(v) and v.x == v.x and v.y == v.y and v.z == v.z and
        math.abs(v.x) <= bound and math.abs(v.y) <= bound and math.abs(v.z) <= bound
end
local function near(lo, hi)
    for _, r in ipairs(regions) do
        if lo.x <= r[2].x and hi.x >= r[1].x and lo.y <= r[2].y and hi.y >= r[1].y and
            lo.z <= r[2].z and hi.z >= r[1].z then return true end
    end
    return false
end
local function discover(api)
    candidates, regions, S.queries = {}, {}, 0
    local focus = EyePos and EyePos() or vector_origin
    local raw = api.ReadRegions(finite(focus, 131072) and focus or vector_origin)
    if type(raw) ~= "table" then return end
    local seen = {}
    for i = 1, math.min(32, #raw) do
        local r = raw[i]
        local lo, hi = Vector(unpack(r[1])), Vector(unpack(r[2]))
        regions[#regions + 1] = {lo, hi}
    end
    -- Players remain eligible even when a dense region fills the general entity prefix.
    -- This is still region-limited; it never captures distant bodies or scans the whole map.
    local players = player and player.GetAll and player.GetAll() or {}
    for i = 1, math.min(MAX_ENTITIES, #players) do
        local e = players[i]
        if IsValid(e) then
            local lo, hi = e:WorldSpaceAABB()
            if finite(lo, 131072) and finite(hi, 131072) and near(lo, hi) then
                candidates[#candidates + 1], seen[e] = e, true
            end
        end
    end
    for _, r in ipairs(regions) do
        if ents.FindInBox and #candidates < MAX_ENTITIES then
            S.queries = S.queries + 1
            for _, e in ipairs(ents.FindInBox(r[1], r[2])) do
                if IsValid(e) and not seen[e] then
                    seen[e] = true;candidates[#candidates + 1] = e
                    if #candidates == MAX_ENTITIES then break end
                end
            end
        end
    end
    S.candidates = #candidates
end
local function convexes(phys)
    if not phys.GetMeshConvexes then return end
    local ok, raw = pcall(phys.GetMeshConvexes, phys)
    if not ok or type(raw) ~= "table" or #raw == 0 or #raw > 8 then return end
    local out, total = {}, 0
    for _, convex in ipairs(raw) do
        if #convex > 1536 then return end
        local points, seen = {}, {}
        for _, vertex in ipairs(convex) do
            local p = vertex.pos
            if not finite(p, 1024) then return end
            local key = string.format("%.4f/%.4f/%.4f", p.x, p.y, p.z)
            if not seen[key] then points[#points + 1], seen[key], total = p, true, total + 1 end
            if #points > 256 or total > 512 then return end
        end
        if #points < 4 then return end
        out[#out + 1] = points
    end
    return out
end
local function halfBounds(lo, hi)
    local h = (hi - lo) * .5
    return Vector(math.max(.05, h.x), math.max(.05, h.y), math.max(.05, h.z))
end
function S.Reset()
    candidates, regions, states, serial, nextDiscovery = {}, {}, {}, 0, 0
    S.bodies, S.candidates, S.queries, S.cooks, S.capture_ms, S.capture_peak_ms = 0, 0, 0, 0, 0, 0
end
function S.Capture(api, dt)
    local start, now = SysTime(), CurTime()
    if now >= nextDiscovery then discover(api);nextDiscovery = now + .1 end
    if #candidates == 0 and S.bodies == 0 then
        S.cooks, S.capture_ms = 0, (SysTime() - start) * 1000
        S.capture_peak_ms = math.max(S.capture_peak_ms, S.capture_ms);return 0
    end
    local rows, keep, cooks = {}, {}, 0
    local massSetting = GetConVar and GetConVar("rtx_glass_player_mass")
    local actorMass = massSetting and math.max(1, math.min(500, massSetting:GetFloat())) or 85
    local function add(e, slot, position, angles, half, mass, velocity, phys)
        if #rows >= MAX_BODIES or not finite(position, 131072) or not finite(half, 1024) or not finite(velocity, 100000) then return end
        if not isangle(angles) or angles.p ~= angles.p or angles.y ~= angles.y or angles.r ~= angles.r or
            math.max(math.abs(angles.p), math.abs(angles.y), math.abs(angles.r)) > 36000 then return end
        if not isnumber(mass) or mass ~= mass then return end
        local old = states[e] and states[e][slot]
        -- IsValid comes before PhysObj equality: comparing a destroyed Source object can throw.
        if old and old.phys and (not IsValid(old.phys) or not IsValid(phys) or old.phys ~= phys) then old = nil end
        if not old then serial = serial + 1;old = {key = serial, phys = phys} end
        local shape
        if IsValid(phys) and not old.attempted and cooks < 2 and (cooks == 0 or SysTime() - start < .0005) then
            old.attempted, cooks = true, cooks + 1
            shape = convexes(phys);old.custom = shape ~= nil
        end
        if IsValid(phys) then
            if old.custom then position, angles = phys:GetPos(), phys:GetAngles()
            elseif phys.GetAABB then
                local lo, hi = phys:GetAABB()
                if finite(lo, 131072) and finite(hi, 131072) then position, half, angles = (lo + hi) * .5, halfBounds(lo, hi), angle_zero end
            end
        end
        if not finite(position, 131072) or not finite(half, 1024) then return end
        -- World AABBs are checked before this function. Per-bone shapes receive an extra coarse test.
        if not near(position - Vector(half:Length(), half:Length(), half:Length()),
            position + Vector(half:Length(), half:Length(), half:Length())) then return end
        keep[e] = keep[e] or {};keep[e][slot] = old
        rows[#rows + 1] = {old.key, position, angles, half, math.max(.01, math.min(50000, mass)), shape, velocity}
    end
    for _, e in ipairs(candidates) do
        if #rows >= MAX_BODIES then break end
        if IsValid(e) and e.WorldSpaceAABB and not e:IsWorld() and not e:GetClass():match("^nlglass_") then
            local lo, hi = e:WorldSpaceAABB()
            if finite(lo, 131072) and finite(hi, 131072) and near(lo, hi) then
                local living = (e:IsPlayer() and e:Alive()) or ((e:IsNPC() or (e.IsNextBot and e:IsNextBot())) and e:Health() > 0)
                if living then
                    local a, b = e:GetCollisionBounds()
                    -- Source feet stay on the floor instead of stepping onto cosmetic glass.
                    -- A short sole skirt gives the mirror lateral contact with thin floor pieces;
                    -- otherwise its flat bottom only pins them into the map. Source is unchanged.
                    a = Vector(a.x, a.y, a.z - 8)
                    add(e, 0, e:GetPos() + (a + b) * .5, angle_zero, halfBounds(a, b), actorMass, e:GetVelocity())
                elseif not e:IsPlayer() then
                    local n = e.GetPhysicsObjectCount and e:GetPhysicsObjectCount() or 0
                    local hasPhysics = false
                    if n > 0 then
                        for i = 0, math.min(n, MAX_BONES) - 1 do
                            local phys = e:GetPhysicsObjectNum(i)
                            if IsValid(phys) then
                                hasPhysics = true
                                add(e, i, phys:GetPos(), phys:GetAngles(), halfBounds(lo, hi), phys:GetMass(), phys:GetVelocity(), phys)
                            end
                        end
                    end
                    if not hasPhysics and e:GetClass() == "prop_ragdoll" and e.GetHitBoxCount and e.GetBoneMatrix then
                        for i = 0, math.min(MAX_BONES, e:GetHitBoxCount(0) or 0) - 1 do
                            local bone = e:GetHitBoxBone(i, 0)
                            local matrix = bone and e:GetBoneMatrix(bone)
                            if matrix then
                                local a, b = e:GetHitBoxBounds(i, 0)
                                local p, ang = LocalToWorld((a + b) * .5, angle_zero, matrix:GetTranslation(), matrix:GetAngles())
                                add(e, i, p, ang, halfBounds(a, b), 8, e:GetVelocity())
                            end
                        end
                    elseif not hasPhysics and e.GetSolid and e:GetSolid() ~= SOLID_NONE then
                        local a, b = e:OBBMins(), e:OBBMaxs()
                        local p, ang = LocalToWorld((a + b) * .5, angle_zero, e:GetPos(), e:GetAngles())
                        add(e, 0, p, ang, halfBounds(a, b), 10, e:GetVelocity())
                    end
                end
            end
        end
    end
    states = keep
    local moved, reason = api.SyncBodies(rows, math.max(.001, math.min(.25, dt)))
    S.bodies, S.cooks, S.capture_ms = #rows, cooks, (SysTime() - start) * 1000
    S.capture_peak_ms = math.max(S.capture_peak_ms, S.capture_ms)
    return moved, reason
end
return S
