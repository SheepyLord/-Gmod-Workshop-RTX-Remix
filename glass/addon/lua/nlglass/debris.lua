-- MIT. Public G1 client API. Native/fallback physics are cosmetic and never network a piece.
if SERVER then return end
if NLGlassDebris and NLGlassDebris.Shutdown then NLGlassDebris.Shutdown() end
local geometry = include("nlglass/debris_mesh.lua")
local fallback = include("nlglass/debris_fallback.lua")
local world = include("nlglass/world.lua")
local batches = include("nlglass/debris_batches.lua")
local individual = include("nlglass/debris_draw.lua")
local view = include("nlglass/debris_view.lua")
local scene = include("nlglass/debris_scene.lua")
local expiry = include("nlglass/debris_expiry.lua")
local collisionFlags = include("nlglass/debris_settings.lua")
local detail = include("nlglass/debris_detail.lua")
local D = {}
NLGlassDebris = D
local lifetime = CreateClientConVar("rtx_glass_debris_lifetime", "120", true, false, "Broken glass lifetime; 0 keeps it until cleanup", 0, 86400)
local budget = CreateClientConVar("rtx_glass_debris_budget", "2000", true, false, "Maximum broken glass pieces", 0, 8192)
local interact = CreateClientConVar("rtx_glass_debris_interact", "1", true, false, "Source bodies and follow-up damage affect your broken glass", 0, 1)
local interactionAvailable, knownInteraction = false, false
local rays, damageQueue, damageByID = {}, {}, {}
local damageFirst, damageLast = 1, 0
local pieces, order, poses, changed = {}, {}, {}, {}
local natives, pending, shrinking, removals, impulses = {}, {}, {}, {}, {}
local stepBusy, stepElapsed, expiryCursor, knownLife = false, 0, 1, -1
local nativeMoving = 0
local first, last, serial, count = 1, 0, 0, 0
local represented, queuedWeight, queuedCount = 0, 0, 0
local creation, createFirst, createLast, createFrame = {}, 1, 0, -1
local demand, demandStamp = 0, 0
local blastHistory,blastSerial={},0
local backend, nativeCapacity, fallbackUnavailable = "none", 0, false
local nativeStats = {}
local metrics = { live = 0, moving = 0, sleeping = 0, merged = 0, batches = 0, rebuilds = 0, pending = 0 }
local knownFlags = -1
local stopped = false
local function window() return { values = {}, cursor = 1, count = 0, sum = 0, peak = 0, last = 0 } end
local thinkTime, drawTime, drawCalls = window(), window(), window()
local currentFrame, currentDrawTime, currentDrawCalls = nil, 0, 0
local fallbackFrame = 0
local function sample(w, value)
    w.sum = w.sum - (w.values[w.cursor] or 0) + value
    w.values[w.cursor], w.cursor = value, w.cursor % 120 + 1
    w.count, w.last, w.peak = math.min(120, w.count + 1), value, math.max(w.peak, value)
end
local function advanceFrame()
    local number = FrameNumber and FrameNumber() or fallbackFrame
    if currentFrame == number then return end
    if currentFrame then sample(drawTime, currentDrawTime);sample(drawCalls, currentDrawCalls) end
    currentFrame, currentDrawTime, currentDrawCalls = number, 0, 0
    metrics.culled_pieces, metrics.draw_calls_current = 0, 0
end
local function clamp(value, min, max) return math.max(min, math.min(max, value)) end
local function limit()
    if fallbackUnavailable then return 0 end
    local n = math.floor(clamp(budget:GetInt(), 0, 8192))
    return world.state == "failed" and math.min(n, fallback.limit) or math.min(n, nativeCapacity > 0 and nativeCapacity or 8192)
end
local function unmerge(piece)
    batches.Remove(piece, individual)
    individual.Add(piece)
end
local function erase(piece)
    expiry.Remove(piece)
    unmerge(piece)
    if piece.native then
        if not piece.nativeSleeping then nativeMoving = nativeMoving - 1 end
        natives[piece.native] = nil
        if stepBusy then removals[piece.native] = true
        else world.api.Remove(piece.native);poses[piece.native] = nil end
    end
    fallback.Remove(piece)
    if piece.mesh then piece.mesh:Destroy() end
    individual.Remove(piece)
    pieces[piece.id], pending[piece.id], shrinking[piece.id] = nil, nil, nil
    count = count - 1
    represented = represented - (piece.weight or 1)
end
local function oldest()
    while first <= last do
        local id = order[first];order[first], first = nil, first + 1
        if pieces[id] then return pieces[id] end
    end
end
local function trim(target)
    while represented > target do local p = oldest();if not p then break end;erase(p) end
end
local function merge(piece)
    if not piece.shrink then batches.Add(piece) end
end
local function physics(piece)
    if backend == "jolt" then
        local g = piece.geometry
        local id
        if g.hulls then id = world.api.SpawnGroup(g.hulls, piece.position, piece.angles, piece.velocity, piece.spin)
        else id = world.api.Spawn(g.hull, piece.position, piece.angles, piece.velocity, piece.spin, piece.minimumSize or 8) end
        if not id then return false end
        piece.native, natives[id] = id, piece
        piece.nativeSleeping, nativeMoving = false, nativeMoving + 1
        poses[id] = {piece.position.x, piece.position.y, piece.position.z, piece.angles.p, piece.angles.y, piece.angles.r, false}
        return true
    elseif backend == "vphysics" then return fallback.Spawn(piece) end
    return false
end
local function failed(reason)
    world.Fail(reason)
    fallbackUnavailable = type(ents.CreateClientProp) ~= "function"
    backend = fallbackUnavailable and "none" or "vphysics"
    stepBusy, removals, impulses = false, {}, {}
    trim(limit())
    for _, p in pairs(pieces) do
        if p.native then poses[p.native], natives[p.native] = nil, nil;p.native = nil end
        unmerge(p);p.sleeping, p.pending, pending[p.id] = false, false, nil
        if not fallback.Spawn(p) then erase(p) end
    end
    nativeMoving = 0
    interactionAvailable, knownInteraction = false, false;scene.Reset()
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
local function popCreation()
    local q=creation[createFirst]
    if q then
        creation[createFirst],createFirst=nil,createFirst+1
        queuedWeight,queuedCount=queuedWeight-q.weight,queuedCount-1
    end
    if createFirst>createLast then creation,createFirst,createLast={},1,0 end
    if createFirst>8192 then
        local compact={};for i=createFirst,createLast do compact[#compact+1]=creation[i] end
        creation,createFirst,createLast=compact,1,#compact
    end
    return q
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
    local size = GetConVar("rtx_glass_piece_size")
    local minimumSize = clamp(size and size:GetFloat() or 8, 4, 64)
    local valid={}
    for i = math.max(1, #fragments - max + 1), #fragments do
        local f = fragments[i]
        if type(f) == "table" and (f.velocity == nil or validVector(f.velocity, 100000)) and
            (f.spin == nil or validVector(f.spin, 36000)) then
            valid[#valid+1]=f
        end
    end
    local now=CurTime();demand=math.max(0,demand-math.max(0,now-demandStamp)*256)+#valid;demandStamp=now
    local eye
    if EyePos then
        local focus=EyePos()
        if validVector(focus,131072) then
            local p=WorldToLocal(focus,angle_zero,frame.origin,frame.angles);eye={p.x,p.y,p.z}
        end
    end
    local coarse=world.api and world.api.SpawnGroup and (demand>192 or nativeMoving>256)
    local packed=detail.Pack(valid,1,#valid,coarse,eye)
    local context={origin=frame.origin,angles=frame.angles,color=color,material=material,materialName=materialName,
        minimum=minimumSize,born=now,blastSerial=blastSerial}
    for _,q in ipairs(packed) do
        q.weight,q.context=#q.parts,context
        while queuedWeight+q.weight>max do if not popCreation() then break end end
        trim(math.max(0,max-queuedWeight-q.weight))
        createLast=createLast+1;creation[createLast]=q
        queuedWeight,queuedCount=queuedWeight+q.weight,queuedCount+1
        metrics.creation_peak_pending=math.max(metrics.creation_peak_pending or 0,queuedCount)
        if q.weight>1 then metrics.grouped_fragments=(metrics.grouped_fragments or 0)+q.weight end
    end
    metrics.creation_pending=queuedCount
end
local function buildCreation()
    if createFrame==fallbackFrame then return end
    createFrame=fallbackFrame
    local before,made,vertices=SysTime(),0,0
    while queuedCount>0 and made<12 and vertices<8192 do
        local nextQ=creation[createFirst];local estimated=0
        for _,part in ipairs(nextQ.parts) do estimated=estimated+12*#part.poly-12 end
        if made>0 and vertices+estimated>8192 then break end
        local q=popCreation();local c,f=q.context,q.parts[1]
        local life=lifetime:GetFloat()
        if life<=0 or CurTime()-c.born<life then
            local g=q.weight>1 and geometry.Group(q.parts,c.color) or geometry.Geometry(f.poly,f.thickness,c.color)
            if g then
                local position,a=LocalToWorld(g.center,angle_zero,c.origin,c.angles)
                serial=serial+1
                local velocity,spin=f.velocity or vector_origin,f.spin or vector_origin
                if q.weight>1 then
                    velocity,spin=Vector(),Vector()
                    for _,part in ipairs(q.parts) do
                        velocity=velocity+(part.velocity or vector_origin)/q.weight
                        spin=spin+(part.spin or vector_origin)/q.weight
                    end
                end
                local px,py,pz,kicks=position.x,position.y,position.z,0
                for i=#blastHistory,1,-1 do
                    local e=blastHistory[i];if e[1]<=c.blastSerial then break end
                    local dx,dy,dz=px-e[2],py-e[3],pz-e[4];local distance=math.sqrt(dx*dx+dy*dy+dz*dz)
                    if distance<e[5] then
                        local direction=distance>.001 and Vector(dx/distance,dy/distance,dz/distance) or Vector(0,0,1)
                        velocity=velocity+direction*(e[6]*(1-distance/e[5]));kicks=kicks+1
                        if kicks==8 then break end
                    end
                end
                local p={id=serial,geometry=g,position=position,angles=a,velocity=velocity,spin=spin,weight=q.weight,
                    born=CurTime(),ageBorn=c.born,color=c.color,material=c.material,materialName=c.materialName,
                    matrix=Matrix(),scale=Vector(1,1,1),poseDirty=true,sleeping=false,mass=g.mass,
                    minimumSize=finite(f.minimum_size,64) and f.minimum_size>=4 and f.minimum_size or c.minimum}
                local ok,mesh=pcall(geometry.Build,g.vertices,c.material)
                if ok then
                    p.mesh=mesh;pieces[p.id],count,represented=p,count+1,represented+q.weight
                    last=last+1;order[last]=p.id;individual.Add(p);expiry.Add(p)
                    if not physics(p) then erase(p) end
                end
                vertices=vertices+#g.vertices
            end
        end
        made=made+1
        if SysTime()-before>=.00075 then break end
    end
    metrics.created_last,metrics.creation_ms=made,(SysTime()-before)*1000
    metrics.creation_peak_ms=math.max(metrics.creation_peak_ms or 0,metrics.creation_ms)
end
-- Server-supplied, Source-clipped pellet traces. Queue at most 32 and apply at most eight per frame.
function D.Ray(from, to, damage, radius)
    radius = radius or 0
    if stopped or not interact:GetBool() or count == 0 or backend ~= "jolt" or not interactionAvailable or
        not validVector(from, 131072) or not validVector(to, 131072) or not finite(damage, 10000) or damage <= 0 or
        not finite(radius, 16) or radius < 0 or (to - from):LengthSqr() > (radius > 0 and 256 or 131072) ^ 2 then return end
    if #rays == 32 then table.remove(rays, 1);metrics.rays_dropped = (metrics.rays_dropped or 0) + 1 end
    rays[#rays + 1] = {from, to, damage, CurTime() + .5, radius}
end
-- Start the map import ahead of the first break (a map with glass, a spawned pane), so the first
-- pieces do not wait for the world while the player looks at them.
function D.Prepare()
    if stopped or budget:GetInt() <= 0 then return end
    ensure()
end
function D.Impulse(origin, radius, speed)
    if stopped or not validVector(origin, 131072) or not isnumber(radius) or not isnumber(speed) or radius ~= radius or speed ~= speed or
        radius <= 0 or radius > 131072 or speed < 0 or speed > 100000 then return end
    blastSerial=blastSerial+1
    if queuedCount>0 then
        if #blastHistory==64 then table.remove(blastHistory,1) end
        blastHistory[#blastHistory+1]={blastSerial,origin.x,origin.y,origin.z,radius,speed}
    else blastHistory={} end
    if backend == "jolt" then
        -- Queue engine-independent mutations while a worker owns the world. Bound the event queue.
        if #impulses >= 64 then table.remove(impulses, 1) end
        impulses[#impulses + 1] = {Vector(origin.x, origin.y, origin.z), radius, speed}
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
    -- Cleanup is the one lifecycle boundary allowed to join an in-flight physics step.
    if world.state == "ready" then world.api.Clear();stepBusy = false end
    for _, piece in pairs(pieces) do piece.native = nil;erase(piece) end
    batches.Clear()
    expiry.Clear();scene.Reset()
    pieces, order, poses, changed = {}, {}, {}, {}
    natives, pending, shrinking, removals, impulses = {}, {}, {}, {}, {}
    rays, damageQueue, damageByID, damageFirst, damageLast = {}, {}, {}, 1, 0
    creation,createFirst,createLast,createFrame={},1,0,-1
    represented,queuedWeight,queuedCount,demand,demandStamp=0,0,0,0,0
    blastHistory,blastSerial={},0
    for _, key in ipairs({"splits", "splits_bullet", "splits_blast", "splits_body", "splits_fall", "splits_melee", "split_ms", "split_peak_ms", "damage_dropped", "rays_dropped",
        "created_last","creation_ms","creation_peak_ms","creation_peak_pending","grouped_fragments"}) do metrics[key] = 0 end
    thinkTime, drawTime, drawCalls = window(), window(), window()
    currentFrame, currentDrawTime, currentDrawCalls = nil, 0, 0
    metrics.culled_pieces, metrics.draw_calls_current = 0, 0
    first, last, count, expiryCursor, stepElapsed, nativeMoving = 1, 0, 0, 1, 0, 0
end
function D.Count() return count + queuedCount end
function D.Backend() return backend end
function D.Stats()
    metrics.live, metrics.moving, metrics.sleeping, metrics.pending, metrics.batches, metrics.merged = count, 0, 0, 0, 0, 0
    for _, p in pairs(pieces) do
        if p.pending then metrics.pending = metrics.pending + 1
        elseif p.sleeping then metrics.sleeping = metrics.sleeping + 1
        else metrics.moving = metrics.moving + 1 end
        if p.area and p.area.included[p.id] then metrics.merged = metrics.merged + 1 end
    end
    metrics.batches, metrics.merged = batches.Count()
    metrics.fragments,metrics.creation_pending,metrics.creation_fragments=represented,queuedCount,queuedWeight
    metrics.pending=metrics.pending+queuedCount
    metrics.rebuilds, metrics.rebuild_vertices = batches.rebuilds, batches.vertices
    metrics.rebuild_ms, metrics.upload_ms = batches.tick_ms or 0, batches.upload_ms or 0
    metrics.rebuild_peak_ms, metrics.upload_peak_ms = batches.tick_peak_ms or 0, batches.upload_peak_ms or 0
    metrics.rebuild_pool_vertices, metrics.retiring_meshes = #batches.pool, batches.retireLast - batches.retireFirst + 1
    metrics.think_ms, metrics.draw_ms = thinkTime.sum / math.max(1, thinkTime.count), drawTime.sum / math.max(1, drawTime.count)
    metrics.think_last_ms, metrics.draw_last_ms = thinkTime.last, drawTime.last
    metrics.think_peak_ms, metrics.draw_peak_ms = thinkTime.peak, drawTime.peak
    metrics.draw_calls, metrics.draw_calls_avg = drawCalls.last, drawCalls.sum / math.max(1, drawCalls.count)
    metrics.think_samples, metrics.draw_samples = thinkTime.count, drawTime.count
    metrics.worker_busy = stepBusy
    metrics.collision_flags = knownFlags
    metrics.interaction, metrics.interaction_available = knownInteraction, interactionAvailable
    metrics.scene_bodies, metrics.scene_candidates, metrics.scene_queries = scene.bodies, scene.candidates, scene.queries
    metrics.capture_ms, metrics.scene_cooks = scene.capture_ms, scene.cooks
    metrics.capture_peak_ms = scene.capture_peak_ms
    metrics.scene_examined, metrics.scene_fast_candidates, metrics.scene_fast_bodies = scene.examined, scene.fast_candidates, scene.fast_bodies
    metrics.scene_fast_boxes, metrics.scene_peak_bodies = scene.fast_boxes, scene.peak_bodies
    metrics.damage_pending, metrics.ray_pending = math.max(0, damageLast - damageFirst + 1), #rays
    if backend == "jolt" then world.api.Stats(nativeStats) end
    metrics.backend, metrics.native, metrics.skipped_models = backend, nativeStats, world.skipped
    return metrics
end
function D.Shutdown() D.Clear();batches.pool = {};world.Shutdown();stopped, backend = true, "none" end
local function fractures()
    local events, reason = world.api.ReadDamage()
    if events == nil then failed(reason);return end
    for _, event in ipairs(events or {}) do
        if not damageByID[event[1]] then
            if damageLast - damageFirst + 1 >= 64 then
                local old = damageQueue[damageFirst];damageByID[old[1]] = nil
                damageQueue[damageFirst], damageFirst = nil, damageFirst + 1
                metrics.damage_dropped = (metrics.damage_dropped or 0) + 1
            end
            damageLast = damageLast + 1;damageQueue[damageLast] = event;damageByID[event[1]] = true
        end
    end
    local start, processed = SysTime(), 0
    metrics.split_ms = 0
    -- One binary replacement per frame; no secondary burst grows with the size of a falling pile.
    while damageFirst <= damageLast and processed < 1 do
        local event = damageQueue[damageFirst];damageQueue[damageFirst], damageFirst = nil, damageFirst + 1
        damageByID[event[1]] = nil
        local parent = natives[event[1]]
        if parent and limit() >= 2 and world.api.CanSplit(parent.native, parent.minimumSize) then
            -- The parent is being replaced. Evict the oldest *remaining* piece for the extra child.
            -- Temporarily skip a parent at the head, so a hit cannot simply erase it at budget.
            if represented+queuedWeight >= limit() then
                local victim = oldest()
                if victim == parent then
                    victim = oldest();first = first - 1;order[first] = parent.id
                end
                if victim then erase(victim) else popCreation() end
            end
            if pieces[parent.id] then
                local children, err = world.api.Split(parent.native, parent.minimumSize)
                if children == nil then failed(err);return end
                if children then
                    erase(parent)
                    for _, f in ipairs(children) do
                        local g = geometry.Geometry(f.poly, f.thickness, parent.color)
                        local ok, mesh = false, nil
                        if g then ok, mesh = pcall(geometry.Build, g.vertices, parent.material) end
                        if ok then
                            serial = serial + 1
                            local p = {id = serial, native = f.id, nativeSleeping = false, geometry = g, mesh = mesh,
                                position = Vector(unpack(f.position)), angles = Angle(unpack(f.angles)),
                                velocity = Vector(unpack(f.velocity)), spin = Vector(unpack(f.spin)),
                                material = parent.material, materialName = parent.materialName, color = parent.color,
                                matrix = Matrix(), scale = Vector(1, 1, 1), poseDirty = true, sleeping = false,
                                born = CurTime(), ageBorn = parent.ageBorn or parent.born, minimumSize = parent.minimumSize, mass = g.mass}
                            pieces[p.id], natives[p.native], count, nativeMoving,represented = p, p, count + 1, nativeMoving + 1,represented+1
                            poses[p.native] = {p.position.x, p.position.y, p.position.z, p.angles.p, p.angles.y, p.angles.r, false}
                            last = last + 1;order[last] = p.id;individual.Add(p);expiry.Add(p)
                        else world.api.Remove(f.id) end
                    end
                    metrics.splits = (metrics.splits or 0) + 1
                    for i, kind in ipairs({"bullet", "blast", "body", "fall", "melee"}) do
                        if math.floor(event[3] / 2 ^ (i - 1)) % 2 == 1 then
                            metrics["splits_" .. kind] = (metrics["splits_" .. kind] or 0) + 1
                        end
                    end
                end
                processed = processed + 1
            end
        end
        if SysTime() - start >= .00075 then break end
    end
    metrics.split_ms = (SysTime() - start) * 1000
    metrics.split_peak_ms = math.max(metrics.split_peak_ms or 0, metrics.split_ms)
    if damageFirst > damageLast then damageQueue, damageByID, damageFirst, damageLast = {}, {}, 1, 0 end
    if damageFirst > 128 then
        local compact = {};for i = damageFirst, damageLast do compact[#compact + 1] = damageQueue[i] end
        damageQueue, damageFirst, damageLast = compact, 1, #compact
    end
end
local function nativeTick()
    stepElapsed = math.min(.25, stepElapsed + math.min(FrameTime(), .25))
    if stepBusy then
        local done, reason = world.api.PollStep()
        if done == nil then failed(reason);return end
        if not done then return end
        stepBusy = false
    end
    for id in pairs(removals) do world.api.Remove(id);poses[id], removals[id] = nil, nil end
    local cv = GetConVar("sv_gravity")
    local ok, reason = world.api.SetGravity(cv and cv:GetFloat() or 600)
    if ok and knownFlags ~= collisionFlags:GetInt() then
        knownFlags = clamp(collisionFlags:GetInt(), 0, 15)
        if world.api.SetCollisionFlags then ok, reason = world.api.SetCollisionFlags(knownFlags) end
    end
    if not ok then failed(reason);return end
    if interactionAvailable and knownInteraction ~= interact:GetBool() then
        knownInteraction = interact:GetBool();ok, reason = world.api.SetInteraction(knownInteraction)
        rays, damageQueue, damageByID, damageFirst, damageLast = {}, {}, {}, 1, 0;scene.Reset()
        if not ok then failed(reason);return end
    end
    if NLGlass and NLGlass.Bullets and NLGlass.Bullets.Update then
        NLGlass.Bullets.Update(world.api, knownInteraction and count > 0)
    end
    for i = 1, #impulses do
        local event = impulses[i]
        ok, reason = world.api.Impulse(event[1], event[2], event[3])
        if not ok then failed(reason);return end
        impulses[i] = nil
    end
    if knownInteraction then
        for _ = 1, math.min(8, #rays) do
            local r = table.remove(rays, 1)
            if r[4] >= CurTime() then
                if r[5] > 0 and world.api.Melee then
                    ok, reason = world.api.Melee(r[1], r[2], math.min(1e9, r[3] * 16000), clamp(r[3] * 20, 80, 1200), r[5])
                else ok, reason = world.api.Ray(r[1], r[2], math.min(1e9, r[3] * 12000), clamp(r[3] * 20, 80, 1200)) end
                if ok == nil then failed(reason);return end
            end
        end
    end
    local spawned = 0
    for id, p in pairs(pending) do
        p.pending, pending[id] = false, nil
        if not physics(p) then erase(p) end
        spawned = spawned + 1
        if spawned >= 128 then break end
    end
    buildCreation()
    local n
    n, reason = world.api.ReadPoses(poses, changed)
    if n == nil then failed(reason);return end
    metrics.pose_updates = n
    for i = 1, n do
        local id = changed[i]
        local p = natives[id]
        if p then
            local row = poses[id]
            if p.nativeSleeping ~= row[7] then nativeMoving = nativeMoving + (row[7] and -1 or 1) end
            p.nativeSleeping = row[7]
            p.position:SetUnpacked(row[1], row[2], row[3]);p.angles:SetUnpacked(row[4], row[5], row[6])
            p.poseDirty = true
            if p.sleeping and not row[7] then unmerge(p) end
            p.sleeping = row[7]
            if p.sleeping then merge(p) end
        end
    end
    local sceneMoved = 0
    if knownInteraction then
        fractures()
        if backend ~= "jolt" then return end
        if count > 0 then
            sceneMoved, reason = scene.Capture(world.api, stepElapsed, knownFlags)
            if sceneMoved == nil then failed(reason);return end
        elseif scene.bodies > 0 then world.api.SyncBodies({}, .016);scene.Reset() end
    end
    if nativeMoving == 0 and sceneMoved == 0 then stepElapsed = 0;return end -- settled scenes keep their fast path
    ok, reason = world.api.BeginStep(stepElapsed)
    stepElapsed = 0
    if not ok then failed(reason);return end
    stepBusy = true
end
local function age()
    local life, now = clamp(lifetime:GetFloat(), 0, 86400), CurTime()
    if life ~= knownLife then
        for _, p in pairs(shrinking) do p.shrink = nil;if p.sleeping then merge(p) end end
        shrinking, expiryCursor, knownLife = {}, first, life
        expiry.Clear()
        for _, p in pairs(pieces) do if p.ageBorn then expiry.Add(p) end end
    end
    if life > 0 then
        while true do
            local p = expiry.PopBefore(now - life + 1)
            if not p then break end
            unmerge(p);shrinking[p.id] = p
        end
        -- Birth order is monotonic. Only the final-second cohort needs per-frame lifetime work.
        expiryCursor = math.max(expiryCursor, first)
        while expiryCursor <= last do
            local p = pieces[order[expiryCursor]]
            if p and p.born + life - now >= 1 then break end
            if p then unmerge(p);shrinking[p.id] = p end
            expiryCursor = expiryCursor + 1
        end
        for _, p in pairs(shrinking) do
            local remaining = (p.ageBorn or p.born) + life - now
            if remaining <= 0 then erase(p) else p.shrink = remaining end
        end
    end
end
local function think()
    if stopped then return end
    local before = SysTime()
    metrics.created_last,metrics.creation_ms=0,0
    fallbackFrame = fallbackFrame + 1;advanceFrame()
    world.Tick()
    if world.state == "ready" and backend ~= "jolt" then
        backend = "jolt"
        world.api.SetCollide(true)
        interactionAvailable = type(world.api.SetInteraction) == "function" and type(world.api.SyncBodies) == "function" and
            type(world.api.ReadRegions) == "function" and type(world.api.ReadDamage) == "function" and
            type(world.api.Ray) == "function" and type(world.api.Split) == "function" and type(world.api.CanSplit) == "function"
    elseif world.state == "failed" and backend ~= "vphysics" and not fallbackUnavailable then failed(world.reason) end
    trim(math.max(0,limit()-queuedWeight))
    while queuedWeight>limit() do if not popCreation() then break end end
    if backend == "jolt" then nativeTick()
    elseif backend == "vphysics" then
        buildCreation()
        for _, p in pairs(pieces) do
            local asleep = p.sleeping
            if not fallback.Update(p) then erase(p)
            else
                if not asleep or not p.sleeping then p.poseDirty = true end
                if asleep and not p.sleeping then unmerge(p)
                elseif p.sleeping then merge(p) end
            end
        end
    end
    age()
    batches.Tick(individual)
    if first > 8192 or last > 32768 then
        local compact = {}
        for i = first, last do if pieces[order[i]] then compact[#compact + 1] = order[i] end end
        order, first, last, expiryCursor = compact, 1, #compact, 1
    end
    sample(thinkTime, (SysTime() - before) * 1000)
end
hook.Add("Think", "NLGlass.Debris", think)
hook.Add("PostDrawTranslucentRenderables", "NLGlass.Debris", function(depth, sky)
    if stopped or depth or sky then return end
    local before = SysTime()
    advanceFrame();view.Capture()
    local settledCalls, settledCulled = batches.Draw(view)
    local movingCalls, movingCulled = individual.Draw(view)
    currentDrawCalls = currentDrawCalls + settledCalls + movingCalls
    currentDrawTime = currentDrawTime + (SysTime() - before) * 1000
    metrics.culled_pieces = metrics.culled_pieces + settledCulled + movingCulled
    metrics.draw_calls_current = currentDrawCalls
end)
hook.Add("PreCleanupMap", "NLGlass.Debris", D.Clear)
hook.Add("ShutDown", "NLGlass.Debris", D.Shutdown)
return D
