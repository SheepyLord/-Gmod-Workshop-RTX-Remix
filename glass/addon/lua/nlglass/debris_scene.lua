-- MIT. Bounded client-only Source snapshots. All mutations go to our Jolt mirrors, never Source.
local S = { bodies = 0, candidates = 0, queries = 0, capture_ms = 0, capture_peak_ms = 0, cooks = 0,
    examined = 0, fast_candidates = 0, fast_bodies = 0, fast_boxes = 0, peak_bodies = 0 }
local candidates, regions, states, serial, nextDiscovery = {}, {}, {}, 0, 0
local MAX_BODIES, MAX_ENTITIES, MAX_BONES, MAX_EXAMINED = 96, 128, 24, 512
local LOOKAHEAD, MAX_SWEEP, FAST_SPEED = .25, 192, 160
local currentFlags = 3
local function living(e)
    return IsValid(e) and ((e:IsPlayer() and e:Alive()) or
        ((e:IsNPC() or (e.IsNextBot and e:IsNextBot())) and e:Health()>0))
end
local function kind(e)
    if e:IsPlayer() then return e:Alive() and 4 or 0 end
    if (e:IsNPC() or (e.IsNextBot and e:IsNextBot())) and e:Health() > 0 then return 8 end
    local class = e:GetClass()
    -- Equipped weapons/followers are not independent Source objects. The owner's hull supplies
    -- living contact when selected; otherwise an attachment must not bypass the living-off mask.
    if (e.IsWeapon and e:IsWeapon()) or class=="phys_bone_follower" then
        local owner=e.GetOwner and e:GetOwner()
        local parent=e.GetParent and e:GetParent()
        if living(owner) or living(parent) then return 0 end
    end
    return ((e.IsRagdoll and e:IsRagdoll()) or class == "prop_ragdoll" or class == "class C_ClientRagdoll" or
        class == "class C_HL2MPRagdoll" or class == "client_ragdoll") and 2 or 1
end
local function allowed(e)
    local k = kind(e)
    return k > 0 and math.floor(currentFlags / k) % 2 == 1
end
-- Source vectors are engine objects: every component read calls into the engine. Each vector is
-- read once and the region tests run on plain numbers. Discovery may test 512 bodies against 32
-- regions; with vectors that cost milliseconds in game (PoC, 2026-11-01).
local function components(v, bound)
    if not isvector(v) then return end
    local x, y, z = v.x, v.y, v.z
    if x == x and y == y and z == z and math.abs(x) <= bound and math.abs(y) <= bound and math.abs(z) <= bound then
        return x, y, z
    end
end
local function finite(v, bound) return components(v, bound) ~= nil end
-- The bounded travel within the lookahead, and the squared speed (0 for an unusable velocity).
local function sweep(velocity)
    local x, y, z = components(velocity, 100000)
    if not x then return 0, 0, 0, 0 end
    local speed2, scale = x * x + y * y + z * z, LOOKAHEAD
    if speed2 * scale * scale > MAX_SWEEP * MAX_SWEEP then scale = MAX_SWEEP / math.sqrt(speed2) end
    return x * scale, y * scale, z * scale, speed2
end
local function near(lx, ly, lz, hx, hy, hz, sx, sy, sz)
    if sx < 0 then lx = lx + sx else hx = hx + sx end
    if sy < 0 then ly = ly + sy else hy = hy + sy end
    if sz < 0 then lz = lz + sz else hz = hz + sz end
    for i = 1, #regions do
        local r = regions[i]
        if lx <= r[4] and hx >= r[1] and ly <= r[5] and hy >= r[2] and lz <= r[6] and hz >= r[3] then return true end
    end
    return false
end
local function discover(api)
    candidates, regions, S.queries, S.examined, S.fast_candidates, S.candidates = {}, {}, 0, 0, 0, 0
    local focus = EyePos and EyePos() or vector_origin
    local raw = api.ReadRegions(finite(focus, 131072) and focus or vector_origin)
    if type(raw) ~= "table" then return end
    local seen, fast, actors, other = {}, {}, {}, {}
    for i = 1, math.min(32, #raw) do
        local lo, hi = raw[i][1], raw[i][2]
        regions[#regions + 1] = {lo[1], lo[2], lo[3], hi[1], hi[2], hi[3]}
    end
    local function consider(e)
        S.examined = S.examined + 1
        if seen[e] or not IsValid(e) or not e.WorldSpaceAABB then return end
        seen[e] = true
        if e:IsWorld() or e:GetClass():match("^nlglass_") or not allowed(e) then return end
        local lo, hi = e:WorldSpaceAABB()
        local lx, ly, lz = components(lo, 131072)
        local hx, hy, hz = components(hi, 131072)
        if not lx or not hx then return end
        local sx, sy, sz, speed2 = sweep(e:GetVelocity())
        if not near(lx, ly, lz, hx, hy, hz, sx, sy, sz) then return end
        local bucket = speed2 >= FAST_SPEED * FAST_SPEED and fast or (e:IsPlayer() and actors or other)
        if #bucket < MAX_ENTITIES then bucket[#bucket + 1] = e end
    end
    -- Scan only a bounded spatial prefix, but rank before truncating it: slow shapes/bones must
    -- not consume every mirror slot before an incoming prop. Players lead the remaining tier.
    local players = player and player.GetAll and player.GetAll() or {}
    for i = 1, math.min(MAX_ENTITIES, #players) do
        consider(players[i])
    end
    for _, r in ipairs(regions) do
        if S.examined >= MAX_EXAMINED or #fast == MAX_ENTITIES then break end
        if ents.FindInBox then
            S.queries = S.queries + 1
            -- The query must reach outside the unswept regions, or the velocity filter never
            -- sees an approaching body. Only the filter's bounded sweep can retain it.
            for _, e in ipairs(ents.FindInBox(Vector(r[1] - MAX_SWEEP, r[2] - MAX_SWEEP, r[3] - MAX_SWEEP),
                Vector(r[4] + MAX_SWEEP, r[5] + MAX_SWEEP, r[6] + MAX_SWEEP))) do
                consider(e)
                if S.examined == MAX_EXAMINED or #fast == MAX_ENTITIES then break end
            end
        end
    end
    for _, bucket in ipairs({fast, actors, other}) do
        for _, e in ipairs(bucket) do
            if #candidates == MAX_ENTITIES then break end
            candidates[#candidates + 1] = e
        end
    end
    S.fast_candidates = math.min(MAX_ENTITIES, #fast)
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
    return Vector(math.max(.05, (hi.x - lo.x) * .5), math.max(.05, (hi.y - lo.y) * .5), math.max(.05, (hi.z - lo.z) * .5))
end
function S.Reset()
    candidates, regions, states, serial, nextDiscovery = {}, {}, {}, 0, 0
    S.bodies, S.candidates, S.queries, S.cooks, S.capture_ms, S.capture_peak_ms = 0, 0, 0, 0, 0, 0
    S.examined, S.fast_candidates, S.fast_bodies, S.fast_boxes, S.peak_bodies = 0, 0, 0, 0, 0
end
function S.Capture(api, dt, flags)
    local start, now = SysTime(), CurTime()
    flags = flags or 3
    if flags ~= currentFlags then currentFlags, nextDiscovery, states = flags, 0, {} end
    if flags == 0 then
        if S.bodies > 0 then api.SyncBodies({}, .016) end
        S.Reset();return 0
    end
    if now >= nextDiscovery then discover(api);nextDiscovery = now + .1 end
    if #candidates == 0 and S.bodies == 0 then
        S.cooks, S.capture_ms = 0, (SysTime() - start) * 1000
        S.capture_peak_ms = math.max(S.capture_peak_ms, S.capture_ms);return 0
    end
    local rows, keep, cooks, fastBodies = {}, {}, 0, 0
    local massSetting = GetConVar and GetConVar("rtx_glass_player_mass")
    local actorMass = massSetting and math.max(1, math.min(500, massSetting:GetFloat())) or 85
    local function add(e, slot, position, angles, half, mass, velocity, phys)
        if #rows >= MAX_BODIES or not finite(position, 131072) or not finite(half, 1024) or not finite(velocity, 100000) then return end
        if not isangle(angles) then return end
        local ap, ay, ar = angles.p, angles.y, angles.r
        if ap ~= ap or ay ~= ay or ar ~= ar or math.max(math.abs(ap), math.abs(ay), math.abs(ar)) > 36000 then return end
        if not isnumber(mass) or mass ~= mass then return end
        local old = states[e] and states[e][slot]
        -- IsValid comes before PhysObj equality: comparing a destroyed Source object can throw.
        if old and old.phys and (not IsValid(old.phys) or not IsValid(phys) or old.phys ~= phys) then old = nil end
        local sx, sy, sz, speed2 = sweep(velocity)
        local fresh, fast = not old, speed2 >= FAST_SPEED * FAST_SPEED
        if fresh then serial = serial + 1;old = {key = serial, phys = phys} end
        local shape
        -- Fast cold bodies enter as boxes in this snapshot. Do not stall first contact on
        -- engine mesh extraction; upgrade when slow, under the unchanged two-shape budget.
        if IsValid(phys) and not fast and not old.attempted and cooks < 2 and (cooks == 0 or SysTime() - start < .0005) then
            old.attempted, cooks = true, cooks + 1
            shape = convexes(phys);old.custom = shape ~= nil
        end
        if IsValid(phys) then
            if old.custom then position, angles = phys:GetPos(), phys:GetAngles()
            elseif phys.GetAABB and phys.LocalToWorld then
                -- GetAABB is in the object's own frame (a client prop at 831,400,-100 reported
                -- -14,-14,0 .. 14,14,45; PoC, 2026-11-01): the box takes the object's pose.
                local lo, hi = phys:GetAABB()
                if finite(lo, 131072) and finite(hi, 131072) then
                    position, half, angles = phys:LocalToWorld((lo + hi) * .5), halfBounds(lo, hi), phys:GetAngles()
                end
            end
        end
        local px, py, pz = components(position, 131072)
        local hx, hy, hz = components(half, 1024)
        if not px or not hx then return end
        -- World AABBs are checked before this function. Per-bone shapes receive an extra coarse test.
        local radius = math.sqrt(hx * hx + hy * hy + hz * hz)
        if not near(px - radius, py - radius, pz - radius, px + radius, py + radius, pz + radius, sx, sy, sz) then return end
        keep[e] = keep[e] or {};keep[e][slot] = old
        rows[#rows + 1] = {old.key, position, angles, half, math.max(.01, math.min(50000, mass)), shape, velocity, kind(e)}
        if fast then
            fastBodies = fastBodies + 1
            if fresh and IsValid(phys) then S.fast_boxes = S.fast_boxes + 1 end
        end
    end
    for _, e in ipairs(candidates) do
        if #rows >= MAX_BODIES then break end
        if IsValid(e) and e.WorldSpaceAABB and not e:IsWorld() and not e:GetClass():match("^nlglass_") and allowed(e) then
            local lo, hi = e:WorldSpaceAABB()
            local lx, ly, lz = components(lo, 131072)
            local hx, hy, hz = components(hi, 131072)
            if lx and hx and near(lx, ly, lz, hx, hy, hz, sweep(e:GetVelocity())) then
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
                        local half = halfBounds(lo, hi)
                        for i = 0, math.min(n, MAX_BONES) - 1 do
                            local phys = e:GetPhysicsObjectNum(i)
                            if IsValid(phys) then
                                hasPhysics = true
                                add(e, i, phys:GetPos(), phys:GetAngles(), half, phys:GetMass(), phys:GetVelocity(), phys)
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
    S.fast_bodies, S.peak_bodies = fastBodies, math.max(S.peak_bodies, #rows)
    S.capture_peak_ms = math.max(S.capture_peak_ms, S.capture_ms)
    return moved, reason
end
return S
