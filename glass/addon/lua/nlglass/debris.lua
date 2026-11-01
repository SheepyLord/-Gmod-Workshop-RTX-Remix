-- MIT. Public G1 client API. Native/fallback physics are cosmetic and never network a piece.
if SERVER then return end
if NLGlassDebris and NLGlassDebris.Shutdown then NLGlassDebris.Shutdown() end
local geometry = include("nlglass/debris_mesh.lua")
local fallback = include("nlglass/debris_fallback.lua")
local world = include("nlglass/world.lua")
local D = {}
NLGlassDebris = D
local lifetime = CreateClientConVar("rtx_glass_debris_lifetime", "120", true, false, "Broken glass lifetime; 0 keeps it until cleanup", 0, 86400)
local budget = CreateClientConVar("rtx_glass_debris_budget", "2000", true, false, "Maximum broken glass pieces", 0, 8192)
local collide = CreateClientConVar("rtx_glass_debris_collide", "1", true, false, "Broken glass pieces collide with each other", 0, 1)
local pieces, order, poses, changed, areas = {}, {}, {}, {}, {}
local first, last, serial, count = 1, 0, 0, 0
local backend, nativeCapacity, fallbackUnavailable = "none", 0, false
local nativeStats = {}
local metrics = { live = 0, moving = 0, sleeping = 0, merged = 0, batches = 0, rebuilds = 0, pending = 0 }
local knownCollide = collide:GetBool()
local stopped = false
local function clamp(value, min, max) return math.max(min, math.min(max, value)) end
local function limit()
    if fallbackUnavailable then return 0 end
    local n = math.floor(clamp(budget:GetInt(), 0, 8192))
    return world.state == "failed" and math.min(n, fallback.limit) or math.min(n, nativeCapacity > 0 and nativeCapacity or 8192)
end
local function invalidate(area)
    if not area then return end
    for _, mesh in ipairs(area.meshes) do mesh:Destroy() end
    area.meshes, area.included = {}, {}
    if not area.dirty then area.due = RealTime() + .1 end
    area.dirty = true
end
local function unmerge(piece)
    local area = piece.area
    if area then area.members[piece.id] = nil; invalidate(area); piece.area = nil end
end
local function erase(piece)
    unmerge(piece)
    if piece.native then world.api.Remove(piece.native); poses[piece.native] = nil end
    fallback.Remove(piece)
    if piece.mesh then piece.mesh:Destroy() end
    pieces[piece.id], count = nil, count - 1
end
local function oldest()
    while first <= last do
        local id = order[first];order[first], first = nil, first + 1
        if pieces[id] then return pieces[id] end
    end
end
local function trim(target)
    while count > target do local p = oldest();if not p then break end;erase(p) end
end
local function merge(piece)
    if piece.area then return end
    local p, c = piece.position, piece.color
    local key = math.floor(p.x / 256) .. "/" .. math.floor(p.y / 256) .. "/" .. math.floor(p.z / 256) .. ":" ..
        piece.materialName .. ":" .. c.r .. "/" .. c.g .. "/" .. c.b .. "/" .. c.a
    local area = areas[key]
    if not area then
        area = {members = {}, included = {}, meshes = {}, material = piece.material, key = key}
        areas[key] = area
    end
    piece.area, area.members[piece.id] = area, piece
    invalidate(area)
end
local function rebuild()
    local now, rebuilt = RealTime(), 0
    for key, area in pairs(areas) do
        if not next(area.members) then
            invalidate(area);areas[key] = nil
        elseif area.dirty and now >= area.due and rebuilt < 2 then
            local vertices, included, meshes = {}, {}, {}
            local ok = pcall(function()
                for id, p in pairs(area.members) do
                    if #vertices + #p.geometry.vertices > 60000 then
                        meshes[#meshes + 1] = geometry.Build(vertices, area.material);vertices = {}
                    end
                    geometry.Transformed(p, vertices);included[id] = true
                end
                if #vertices > 0 then meshes[#meshes + 1] = geometry.Build(vertices, area.material) end
            end)
            if ok then
                area.meshes, area.included, area.dirty = meshes, included, false
                metrics.rebuilds = metrics.rebuilds + 1
            else
                for _, mesh in ipairs(meshes) do mesh:Destroy() end
                area.due = now + 1
            end
            rebuilt = rebuilt + 1
        end
    end
end
local function physics(piece)
    if backend == "jolt" then
        local id = world.api.Spawn(piece.geometry.hull, piece.position, piece.angles, piece.velocity, piece.spin)
        if not id then return false end
        piece.native = id
        poses[id] = {piece.position.x, piece.position.y, piece.position.z, piece.angles.p, piece.angles.y, piece.angles.r, false}
        return true
    elseif backend == "vphysics" then return fallback.Spawn(piece) end
    return false
end
local function failed(reason)
    world.Fail(reason)
    fallbackUnavailable = type(ents.CreateClientProp) ~= "function"
    backend = fallbackUnavailable and "none" or "vphysics"
    trim(limit())
    for _, p in pairs(pieces) do
        if p.native then poses[p.native] = nil;p.native = nil end
        unmerge(p);p.sleeping, p.pending = false, false
        if not fallback.Spawn(p) then erase(p) end
    end
end
local function ensure()
    if world.state == "new" then
        -- Reserve the hard maximum once so changing the player budget never reimports a map.
        nativeCapacity = 8192
        local cv = GetConVar("sv_gravity")
        world.Begin(nativeCapacity, cv and cv:GetFloat() or 600)
    end
    if world.state == "failed" and backend ~= "vphysics" and not fallbackUnavailable then failed(world.reason) end
end
local function finite(n, max) return isnumber(n) and n == n and math.abs(n) <= max end
local function validVector(v, max)
    return isvector(v) and finite(v.x, max) and finite(v.y, max) and finite(v.z, max)
end
function D.Spawn(frame, fragments)
    if stopped then return end
    if type(frame) ~= "table" or type(fragments) ~= "table" or not isvector(frame.origin) or not isangle(frame.angles) then return end
    if not validVector(frame.origin, 131072) or not finite(frame.angles.p, 36000) or
        not finite(frame.angles.y, 36000) or not finite(frame.angles.r, 36000) then return end
    if budget:GetInt() <= 0 then return end
    ensure()
    local max = limit()
    if max == 0 then return end
    local c = frame.color or color_white
    if type(c) ~= "table" or not finite(c.r, 100000) or not finite(c.g, 100000) or
        not finite(c.b, 100000) or not finite(c.a, 100000) then return end
    local color = Color(clamp(c.r, 0, 255), clamp(c.g, 0, 255), clamp(c.b, 0, 255), clamp(c.a, 0, 255))
    local materialName = type(frame.material) == "string" and #frame.material <= 256 and frame.material or "models/props_c17/fisheyelens"
    local material = Material(materialName)
    -- Ignore excess input before constructing meshes. The retained fragments are the newest ones.
    for i = math.max(1, #fragments - max + 1), #fragments do
        local f = fragments[i]
        if type(f) == "table" and (f.velocity == nil or validVector(f.velocity, 100000)) and
            (f.spin == nil or validVector(f.spin, 36000)) then
            local g = geometry.Geometry(f.poly, f.thickness, color)
            if g then
                trim(max - 1)
                local position, a = LocalToWorld(g.center, angle_zero, frame.origin, frame.angles)
                serial = serial + 1
                local piece = {id = serial, geometry = g, position = position, angles = a, velocity = f.velocity or vector_origin,
                    spin = f.spin or vector_origin, born = CurTime(), color = color, material = material, materialName = materialName,
                    matrix = Matrix(), scale = Vector(1, 1, 1), sleeping = false, mass = g.mass}
                local ok, mesh = pcall(geometry.Build, g.vertices, material)
                if ok then
                    piece.mesh = mesh
                    pieces[serial], count = piece, count + 1
                    last = last + 1;order[last] = serial
                    if world.state == "loading" then piece.pending = true
                    elseif not physics(piece) then erase(piece) end
                end
            end
        end
    end
end
function D.Impulse(origin, radius, speed)
    if stopped or not validVector(origin, 131072) or not isnumber(radius) or not isnumber(speed) or radius ~= radius or speed ~= speed or
        radius <= 0 or radius > 131072 or speed < 0 or speed > 100000 then return end
    if backend == "jolt" then
        local ok, reason = world.api.Impulse(origin, radius, speed)
        if not ok then failed(reason) end
    elseif backend == "vphysics" then
        for _, p in pairs(pieces) do fallback.Impulse(p, origin, radius, speed) end
    end
    for _, p in pairs(pieces) do
        local delta = p.position - origin
        local distance = delta:Length()
        if distance < radius then
            unmerge(p);p.sleeping = false
            if p.pending then
                local direction = distance > .001 and delta / distance or Vector(0, 0, 1)
                p.velocity = p.velocity + direction * (speed * (1 - distance / radius))
            end
        end
    end
end
function D.Clear()
    for _, piece in pairs(pieces) do erase(piece) end
    pieces, order, poses, changed, areas = {}, {}, {}, {}, {}
    first, last, count = 1, 0, 0
    if world.state == "ready" then world.api.Clear() end
end
function D.Count() return count end
function D.Backend() return backend end
function D.Stats()
    metrics.live, metrics.moving, metrics.sleeping, metrics.pending, metrics.batches, metrics.merged = count, 0, 0, 0, 0, 0
    for _, p in pairs(pieces) do
        if p.pending then metrics.pending = metrics.pending + 1
        elseif p.sleeping then metrics.sleeping = metrics.sleeping + 1
        else metrics.moving = metrics.moving + 1 end
        if p.area and p.area.included[p.id] then metrics.merged = metrics.merged + 1 end
    end
    for _, area in pairs(areas) do metrics.batches = metrics.batches + #area.meshes end
    if backend == "jolt" then world.api.Stats(nativeStats) end
    metrics.backend, metrics.native, metrics.skipped_models = backend, nativeStats, world.skipped
    return metrics
end
function D.Shutdown() D.Clear();world.Shutdown();stopped, backend = true, "none" end
local function think()
    if stopped then return end
    world.Tick()
    if world.state == "ready" and backend ~= "jolt" then
        backend = "jolt"
        world.api.SetCollide(collide:GetBool())
        for _, p in pairs(pieces) do
            if p.pending then p.pending = false;if not physics(p) then erase(p) end end
        end
    elseif world.state == "failed" and backend ~= "vphysics" and not fallbackUnavailable then failed(world.reason) end
    trim(limit())
    if backend == "jolt" then
        local cv = GetConVar("sv_gravity")
        local ok, reason = world.api.SetGravity(cv and cv:GetFloat() or 600)
        if ok and knownCollide ~= collide:GetBool() then
            knownCollide = collide:GetBool();ok, reason = world.api.SetCollide(knownCollide)
        end
        if ok then ok, reason = world.api.Step(math.min(FrameTime(), .25)) end
        if ok then ok, reason = world.api.ReadPoses(poses, changed) end
        if not ok then failed(reason)
        else
            -- Native ids and manager ids differ after reuse and fallback; a direct native lookup is kept below.
            for _, p in pairs(pieces) do
                if p.native then
                    local row = poses[p.native]
                    if not row[7] or not p.sleeping then
                        p.position:SetUnpacked(row[1], row[2], row[3]);p.angles:SetUnpacked(row[4], row[5], row[6])
                    end
                    if p.sleeping and not row[7] then unmerge(p) end
                    p.sleeping = row[7]
                end
            end
        end
    elseif backend == "vphysics" then
        for _, p in pairs(pieces) do
            local asleep = p.sleeping
            if not fallback.Update(p) then erase(p)
            elseif asleep and not p.sleeping then unmerge(p) end
        end
    end
    local life, now = clamp(lifetime:GetFloat(), 0, 86400), CurTime()
    for _, p in pairs(pieces) do
        local remaining = life > 0 and p.born + life - now or math.huge
        if remaining <= 0 then erase(p)
        elseif remaining < 1 then unmerge(p);p.shrink = remaining
        else p.shrink = nil;if p.sleeping then merge(p) end end
    end
    rebuild()
    -- Compact the FIFO occasionally, keeping memory proportional to the live budget.
    if first > 8192 or last > 32768 then
        local compact = {}
        for i = first, last do if pieces[order[i]] then compact[#compact + 1] = order[i] end end
        order, first, last = compact, 1, #compact
    end
end
hook.Add("Think", "NLGlass.Debris", think)
hook.Add("PostDrawTranslucentRenderables", "NLGlass.Debris", function(depth, sky)
    if stopped or depth or sky then return end
    for _, area in pairs(areas) do
        render.SetMaterial(area.material)
        for _, mesh in ipairs(area.meshes) do mesh:Draw() end
    end
    for _, p in pairs(pieces) do
        if not p.pending and not (p.area and p.area.included[p.id]) then
            render.SetMaterial(p.material);geometry.Draw(p, p.shrink or 1)
        end
    end
end)
hook.Add("PreCleanupMap", "NLGlass.Debris", D.Clear)
hook.Add("ShutDown", "NLGlass.Debris", D.Shutdown)
return D
