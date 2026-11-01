-- MIT. Native-world bootstrap. Included by debris.lua; no autorun or server dependency.
local W = { state = "new", api = nil, reason = nil, skipped = 0 }
local logged = false
local function fail(reason)
    W.state, W.reason = "failed", tostring(reason or "unknown import failure")
    if W.api then pcall(W.api.Shutdown) end
    if not logged then
        logged = true
        ErrorNoHalt("[NLGlass] Jolt unavailable; using capped client physics: " .. W.reason .. "\n")
    end
end
W.Fail = fail
local function must(value, reason)
    if value == nil or value == false then error(reason or "native call failed", 0) end
    return value
end
W.Must = must

local function collision(model)
    local ent = ClientsideModel(model, RENDERGROUP_OTHER)
    if not IsValid(ent) then return nil end
    -- Always remove our temporary model, including after a malformed engine collision mesh.
    local ok, result = pcall(function()
        ent:SetNoDraw(true)
        ent:PhysicsInit(SOLID_VPHYSICS)
        local phys = ent:GetPhysicsObject()
        if not IsValid(phys) then return nil end
        local mesh = phys:GetMeshConvexes()
        if type(mesh) ~= "table" or #mesh == 0 or #mesh > 128 then return nil end
        local convexes = {}
        for _, convex in ipairs(mesh) do
            local points, seen = {}, {}
            for _, vertex in ipairs(convex) do
                local p = vertex.pos
                if not isvector(p) then return nil end
                local key = string.format("%.5f/%.5f/%.5f", p.x, p.y, p.z)
                if not seen[key] then points[#points + 1], seen[key] = p, true end
                if #points > 256 then return nil end
            end
            if #points < 4 then return nil end
            convexes[#convexes + 1] = points
        end
        return convexes
    end)
    ent:Remove()
    return ok and result or nil
end

function W.Begin(budget, gravity)
    if W.state ~= "new" then return end
    W.state = "loading"
    local ok, reason = pcall(function()
        local module = require("nlglass")
        W.api = type(module) == "table" and module or nlglass
        if type(W.api) ~= "table" or type(W.api.Init) ~= "function" then error("module missing", 0) end
        must(W.api.Init(budget, gravity))
        local map = game.GetMap()
        if type(map) ~= "string" or not map:match("^[%w_/%-]+$") or map:find("..", 1, true) then error("invalid map name", 0) end
        local path = "maps/" .. map .. ".bsp"
        local size = file.Size(path, "GAME")
        if not size or size < 1036 or size > 256 * 1024 * 1024 then error("map missing or larger than 256 MiB", 0) end
        local bytes = file.Read(path, "GAME")
        if type(bytes) ~= "string" or #bytes ~= size then error("cannot read map from GAME", 0) end
        local props = must(W.api.LoadMap(bytes))
        W.task = coroutine.create(function()
            local models = {}
            for _, prop in ipairs(props) do models[prop.model] = false end
            local n = 0
            for model in pairs(models) do
                local convexes = collision(model)
                if convexes then
                    local added = W.api.AddModel(model, convexes)
                    models[model] = added == true
                    if not added then W.skipped = W.skipped + 1 end
                else W.skipped = W.skipped + 1 end
                n = n + 1
                if n % 2 == 0 then coroutine.yield() end
            end
            for i, prop in ipairs(props) do
                if models[prop.model] then W.api.AddProp(prop.model, prop.position, prop.angles, prop.scale) end
                if i % 64 == 0 then coroutine.yield() end
            end
            must(W.api.FinishWorld())
            W.state = "ready"
        end)
    end)
    if not ok then fail(reason) end
end

function W.Tick()
    if W.state == "loading" and W.task then
        local ok, reason = coroutine.resume(W.task)
        if not ok then W.task = nil; fail(reason)
        elseif coroutine.status(W.task) == "dead" then W.task = nil end
    end
end
function W.Shutdown()
    W.task = nil
    if W.api then pcall(W.api.Shutdown) end
    W.state = "new"
end
return W
