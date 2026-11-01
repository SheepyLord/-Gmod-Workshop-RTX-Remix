-- MIT. Consolidated settled areas, bounded shared upload scratch and incremental replacement.
local geometry = include("nlglass/debris_mesh.lua")
local B = { areas = {}, work = {}, rebuilds = 0, vertices = 0, batch_count = 0, merged = 0,
    pool = {}, upload = {}, retired = {}, retireFirst = 1, retireLast = 0 }
local maxVertices, frameVertices, frameSeconds = 24000, 1800, .0006
local function retire(mesh)
    B.retireLast = B.retireLast + 1;B.retired[B.retireLast] = mesh
end
local function retireBatches(list)
    for _, b in ipairs(list) do retire(b.mesh) end
end
local function resetUpload()
    for i = #B.upload, 1, -1 do B.upload[i] = nil end
end
local function cancel(area)
    if B.job and B.job.area == area then
        retireBatches(B.job.batches);B.job = nil;resetUpload()
    end
end
local function dirty(area)
    local now = RealTime()
    if not area.dirty then area.since = now end
    area.dirty, area.due = true, math.min(now + .2, area.since + .75)
    B.work[area.key] = area
end
function B.Add(p)
    if p.area then return end
    local v = p.position
    -- Offset the grid so piles on/around zero do not split across eight cells. Color is already
    -- in the vertices; different tint/alpha values can share a material and a draw.
    local x, y, z = math.floor((v.x + 512) / 1024), math.floor((v.y + 512) / 1024), math.floor((v.z + 512) / 1024)
    local key = x .. "/" .. y .. "/" .. z .. ":" .. p.materialName
    local area = B.areas[key]
    if not area then
        area = { members = {}, included = {}, batches = {}, material = p.material, key = key,
            x = x * 1024, y = y * 1024, z = z * 1024, radius = 887 }
        B.areas[key] = area
    end
    area.radius = math.max(area.radius, 887 + p.geometry.radius)
    p.area, area.members[p.id] = area, p
    dirty(area)
end
function B.Remove(p, individual)
    local area = p.area
    if not area then return end
    local batch = area.included[p.id]
    if batch and batch.valid then
        batch.valid = false;B.batch_count, B.merged = B.batch_count - 1, B.merged - batch.count
        for id in pairs(batch.members) do
            area.included[id] = nil
            local member = area.members[id]
            if member then individual[id] = member end
        end
    end
    area.members[p.id], area.included[p.id], p.area = nil, nil, nil
    cancel(area) -- never publish removed/woken/shrinking members from an old snapshot
    dirty(area)
end
local function start(area)
    local list = {}
    for _, p in pairs(area.members) do list[#list + 1] = p end
    B.job = { area = area, list = list, cursor = 1, members = {}, count = 0, batches = {} }
    area.dirty = false -- arrivals during this snapshot request one later revision
end
local function build(job, individual, deadline)
    local area = job.area
    while job.cursor <= #job.list do
        local p = job.list[job.cursor]
        local size = #p.geometry.vertices
        if B.vertices + size > frameVertices or #B.upload + size > maxVertices then break end
        geometry.Transformed(p, B.upload, B.pool)
        job.members[p.id] = true
        job.count, job.cursor, B.vertices = job.count + 1, job.cursor + 1, B.vertices + size
        if SysTime() >= deadline then break end
    end
    local nextPiece = job.list[job.cursor]
    if #B.upload > 0 and (not nextPiece or #B.upload + #nextPiece.geometry.vertices > maxVertices) then
        -- One upload per frame, only after previous frames have prepared its reusable buffer.
        local before = SysTime()
        local mesh = geometry.Build(B.upload, area.material)
        B.upload_ms = (SysTime() - before) * 1000
        job.batches[#job.batches + 1] = { mesh = mesh, members = job.members, count = job.count, valid = true }
        job.members, job.count = {}, 0
        resetUpload()
    end
    if job.cursor > #job.list then
        local included = {}
        for _, b in ipairs(area.batches) do
            if b.valid then B.batch_count, B.merged = B.batch_count - 1, B.merged - b.count end
        end
        for _, b in ipairs(job.batches) do
            B.batch_count, B.merged = B.batch_count + 1, B.merged + b.count
            for id in pairs(b.members) do included[id] = b;individual[id] = nil end
        end
        retireBatches(area.batches)
        area.batches, area.included, B.job = job.batches, included, nil
        if not area.dirty then B.work[area.key] = nil end
        B.rebuilds = B.rebuilds + 1
    end
end
function B.Tick(individual)
    local before = SysTime()
    B.vertices, B.upload_ms = 0, 0
    -- Resource release can synchronize with the renderer too. Do not destroy a whole old pile in
    -- the publication frame, or allocate thousands of transient vertex tables for its replacement.
    for _ = 1, 2 do
        local mesh = B.retired[B.retireFirst]
        if not mesh then break end
        mesh:Destroy();B.retired[B.retireFirst] = nil;B.retireFirst = B.retireFirst + 1
    end
    if B.retireFirst > B.retireLast then B.retireFirst, B.retireLast = 1, 0 end
    if not B.job then
        for key, area in pairs(B.work) do
            if not next(area.members) then
                retireBatches(area.batches);B.areas[key], B.work[key] = nil, nil
            elseif RealTime() >= area.due then start(area);break end
        end
    end
    local job = B.job
    if job then
        local ok = pcall(build, job, individual, before + frameSeconds)
        if not ok then
            local area = job.area
            cancel(area);area.dirty, area.since, area.due = true, RealTime(), RealTime() + 1
        end
    end
    B.tick_ms = (SysTime() - before) * 1000
end
function B.Draw()
    for _, area in pairs(B.areas) do
        render.SetMaterial(area.material)
        for _, b in ipairs(area.batches) do if b.valid then b.mesh:Draw() end end
    end
end
function B.Count() return B.batch_count, B.merged end
function B.Clear()
    for _, area in pairs(B.areas) do
        for _, b in ipairs(area.batches) do b.mesh:Destroy() end
    end
    if B.job then for _, b in ipairs(B.job.batches) do b.mesh:Destroy() end end
    for i = B.retireFirst, B.retireLast do B.retired[i]:Destroy() end
    B.areas, B.work, B.job, B.retired = {}, {}, nil, {}
    B.retireFirst, B.retireLast, B.batch_count, B.merged = 1, 0, 0, 0
    resetUpload() -- retain the bounded pool so the next break does not recreate every vertex
end
return B
