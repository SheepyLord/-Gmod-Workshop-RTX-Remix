-- MIT. Incremental settled-area batches; old valid chunks remain visible until replacements exist.
local geometry = include("nlglass/debris_mesh.lua")
local B = { areas = {}, work = {}, rebuilds = 0, vertices = 0 }
local maxVertices, frameVertices = 6000, 1800
local function destroy(batches)
    for _, b in ipairs(batches) do b.mesh:Destroy() end
end
local function cancel(area)
    if area.job then destroy(area.job.batches);area.job = nil end
end
local function dirty(area)
    if not area.dirty then area.due = RealTime() + .1 end
    area.dirty = true
    B.work[area.key] = area
end
function B.Add(p)
    if p.area then return end
    local v, c = p.position, p.color
    local key = math.floor(v.x / 256) .. "/" .. math.floor(v.y / 256) .. "/" .. math.floor(v.z / 256) .. ":" ..
        p.materialName .. ":" .. c.r .. "/" .. c.g .. "/" .. c.b .. "/" .. c.a
    local area = B.areas[key]
    if not area then
        area = { members = {}, included = {}, batches = {}, material = p.material, key = key }
        B.areas[key] = area
    end
    p.area, area.members[p.id] = area, p
    dirty(area) -- additions do not retire an existing batch
end
function B.Remove(p, individual)
    local area = p.area
    if not area then return end
    local batch = area.included[p.id]
    if batch and batch.valid then
        -- A removed/woken/shrinking member cannot remain in an immutable GPU mesh. Hide only its
        -- small chunk; its surviving members draw individually while all other chunks stay drawn.
        batch.valid = false
        for id in pairs(batch.members) do
            area.included[id] = nil
            local member = area.members[id]
            if member then individual[id] = member end
        end
    end
    area.members[p.id], area.included[p.id], p.area = nil, nil, nil
    cancel(area) -- a snapshot with removed members cannot be published
    dirty(area)
end
function B.Tick(individual)
    B.vertices = 0
    local built = false
    for key, area in pairs(B.work) do
        if not next(area.members) then
            cancel(area);destroy(area.batches);B.areas[key], B.work[key] = nil, nil
        elseif area.dirty and RealTime() >= area.due and B.vertices < frameVertices and not built then
            if not area.job then
                local list = {}
                for _, p in pairs(area.members) do list[#list + 1] = p end
                area.job = { list = list, cursor = 1, vertices = {}, members = {}, batches = {} }
                area.dirty = false -- later arrivals request a subsequent revision
            end
        end
        local job = area.job
        if job and B.vertices < frameVertices and not built then
            local ok = pcall(function()
                while job.cursor <= #job.list do
                    local p = job.list[job.cursor]
                    local size = #p.geometry.vertices
                    if B.vertices + size > frameVertices or #job.vertices + size > maxVertices then break end
                    geometry.Transformed(p, job.vertices)
                    job.members[p.id] = true
                    job.cursor, B.vertices = job.cursor + 1, B.vertices + size
                end
                -- At most one bounded GPU upload per frame. Transformation work has its own cap.
                local nextPiece = job.list[job.cursor]
                if #job.vertices > 0 and (not nextPiece or #job.vertices + #nextPiece.geometry.vertices > maxVertices) then
                    local mesh = geometry.Build(job.vertices, area.material)
                    job.batches[#job.batches + 1] = { mesh = mesh, members = job.members, valid = true }
                    job.vertices, job.members, built = {}, {}, true
                end
                if job.cursor > #job.list then
                    local included = {}
                    for _, b in ipairs(job.batches) do
                        for id in pairs(b.members) do included[id] = b;individual[id] = nil end
                    end
                    destroy(area.batches)
                    area.batches, area.included, area.job = job.batches, included, nil
                    if not area.dirty then B.work[key] = nil end
                    B.rebuilds = B.rebuilds + 1
                end
            end)
            if not ok then cancel(area);area.dirty, area.due = true, RealTime() + 1 end
        end
    end
end
function B.Draw()
    for _, area in pairs(B.areas) do
        render.SetMaterial(area.material)
        for _, b in ipairs(area.batches) do if b.valid then b.mesh:Draw() end end
    end
end
function B.Count()
    local batches, merged = 0, 0
    for _, area in pairs(B.areas) do
        for _, b in ipairs(area.batches) do
            if b.valid then batches = batches + 1;for _ in pairs(b.members) do merged = merged + 1 end end
        end
    end
    return batches, merged
end
function B.Clear()
    for _, area in pairs(B.areas) do cancel(area);destroy(area.batches) end
    B.areas, B.work = {}, {}
end
return B
