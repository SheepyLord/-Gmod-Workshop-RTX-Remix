-- Draw only the toolgun's live screen in the HUD pass, after Remix's temporal reconstruction, as 2D.
-- Its original renderer still owns the texture; custom tool screens and Dynamic Toolgun Screen
-- keep updating it normally. No captured render-target hashes or persistent Remix categories.
local enabled = CreateClientConVar("nativeloader_toolgun_screen", "1", true, false,
    "Draw the live toolgun screen after Remix upscaling to keep animated text readable")
local captured, cached, drawing, failed = nil, nil, false, false
local stats = {captures = 0, draws = 0}
local white = "models/debug/debugwhite"
local screen = CreateMaterial("nativeloader_toolgun_screen", "UnlitGeneric", {
    ["$basetexture"] = white, ["$nocull"] = "1",
})

local function screen_material(name)
    name = string.lower(name):gsub("%.vmt$", "")
    return name == "models/weapons/v_toolgun/screen"
end

local function bodygroups(model)
    local groups = {}
    for index = 0, model:GetNumBodyGroups() - 1 do groups[#groups + 1] = model:GetBodygroup(index) end
    return table.concat(groups, "")
end

local function template(model)
    local path, skin, groups = model:GetModel(), model:GetSkin(), bodygroups(model)
    local key = path .. ":" .. skin .. ":" .. groups
    if cached and cached.key == key then return cached end
    cached = {key = key, screens = {}}
    local meshes, bind = util.GetModelMeshes(path, 0, groups, skin)
    if not meshes or not bind then return cached end
    cached.bind = bind
    for _, part in ipairs(meshes) do
        if screen_material(part.material) then
            cached.screens[#cached.screens + 1] = {name = part.material, vertices = part.triangles}
        end
    end
    return cached
end

local function capture(model, player, weapon)
    if drawing or failed or not enabled:GetBool() or not istable(RemixConfig) then return end
    if render.GetRenderTarget() ~= nil or not IsValid(model) or not IsValid(weapon) then return end
    if weapon:GetClass() ~= "gmod_tool" or player ~= LocalPlayer() then return end
    if not player:Alive() or player:ShouldDrawLocalPlayer() or model:GetColor().a == 0 then return end
    local view = render.GetViewSetup(true)
    if VIEW_MAIN and view.viewid and view.viewid ~= VIEW_MAIN then return end
    local data = template(model)
    if #data.screens == 0 then return end
    local parts, matrices = {}, {}
    for _, part in ipairs(data.screens) do
        local material = Material(part.name)
        local texture = material:GetTexture("$basetexture")
        if texture and not texture:IsError() then
            local vertices = {}
            for _, vertex in ipairs(part.vertices) do
                local position, total = Vector(0, 0, 0), 0
                for _, weight in ipairs(vertex.weights or {}) do
                    local bone = weight.bone
                    if not matrices[bone] then
                        local pose, rest = model:GetBoneMatrix(bone), data.bind[bone]
                        if pose and rest then matrices[bone] = pose * rest.matrix end
                    end
                    if matrices[bone] then
                        position = position + (matrices[bone] * vertex.pos) * weight.weight
                        total = total + weight.weight
                    end
                end
                if total == 0 then return end
                vertices[#vertices + 1] = {position = position / total, u = vertex.u, v = vertex.v}
            end
            parts[#parts + 1] = {texture = texture, vertices = vertices}
        end
    end
    if #parts > 0 then
        stats.captures = stats.captures + 1
        stats.texture = parts[1].texture:GetName()
        stats.triangles = #parts[1].vertices / 3
        captured = {frame = FrameNumber(), model = model, hands = player:GetHands(), view = view, parts = parts}
    end
end

hook.Add("PostDrawViewModel", "nativeloader_toolgun_screen", function(model, player, weapon)
    local ok, err = xpcall(function() capture(model, player, weapon) end, debug.traceback)
    if not ok then
        failed = true
        captured = nil
        stats.error = tostring(err)
        ErrorNoHalt("[nativeloader] Toolgun capture disabled: " .. tostring(err) .. "\n")
    end
end)

-- The screen is drawn as screen-space triangles, projected here with the view model's own field of
-- view: Remix rasterizes 2D HUD draws after its upscaling, while any perspective draw, even one made in
-- HUDPaint into a render target, is taken into the path-traced scene (review R4: the earlier 3D redraw
-- never reached the screen, and scrolling text kept Remix's temporal smear). Each triangle is cut into
-- SUBDIVISIONS^2 smaller ones so the texture follows the perspective closely.
local SUBDIVISIONS = 8
local function projector(view, w, h)
    local forward, right, up = view.angles:Forward(), view.angles:Right(), view.angles:Up()
    -- CViewSetup's view model field of view is horizontal and already scaled to the aspect ratio.
    local scale = 1 / math.tan(math.rad(view.fovviewmodel or view.fov) * 0.5)
    local aspect = w / h
    return function(position)
        local offset = position - view.origin
        local depth = offset:Dot(forward)
        if depth <= 0.5 then return end
        local x = offset:Dot(right) * scale / depth
        local y = offset:Dot(up) * scale * aspect / depth
        return (1 + x) * w * 0.5, (1 - y) * h * 0.5
    end
end

local function lerp_vertex(a, b, c, i, j, n)
    local s, t = i / n, j / n
    local r = 1 - s - t
    return a.position * r + b.position * s + c.position * t,
        a.u * r + b.u * s + c.u * t, a.v * r + b.v * s + c.v * t
end

local function draw_triangle(project, a, b, c)
    local n, rows = SUBDIVISIONS, {}
    for i = 0, n do
        rows[i] = {}
        for j = 0, n - i do
            local position, u, v = lerp_vertex(a, b, c, i, j, n)
            local x, y = project(position)
            if not x then return false end
            rows[i][j] = {x = x, y = y, u = u, v = v}
        end
    end
    for i = 0, n - 1 do
        for j = 0, n - 1 - i do
            surface.DrawPoly({rows[i][j], rows[i + 1][j], rows[i][j + 1]})
            if i + j + 2 <= n then surface.DrawPoly({rows[i + 1][j], rows[i + 1][j + 1], rows[i][j + 1]}) end
        end
    end
    return true
end

local function render_screen(data)
    local project = projector(data.view, ScrW(), ScrH())
    surface.SetDrawColor(255, 255, 255, 255)
    for _, part in ipairs(data.parts) do
        screen:SetTexture("$basetexture", part.texture)
        surface.SetMaterial(screen)
        local vertices = part.vertices
        for index = 1, #vertices - 2, 3 do
            if not draw_triangle(project, vertices[index], vertices[index + 1], vertices[index + 2]) then return end
        end
    end
    stats.draws = stats.draws + 1
end

hook.Add("HUDPaint", "nativeloader_toolgun_screen", function()
    if drawing or failed or not enabled:GetBool() then return end
    local data = captured
    if not data or data.frame ~= FrameNumber() or not IsValid(data.model) then return end
    drawing = true
    local ok, err = xpcall(function() render_screen(data) end, debug.traceback)
    drawing = false
    if not ok then
        failed = true
        stats.error = tostring(err)
        ErrorNoHalt("[nativeloader] Toolgun screen redraw disabled: " .. tostring(err) .. "\n")
    end
end)

cvars.AddChangeCallback("nativeloader_toolgun_screen", function() failed = false; captured = nil; stats.error = nil end,
    "nativeloader_toolgun_screen")

concommand.Add("nativeloader_toolgun_status", function()
    print("[nativeloader] Toolgun screen " .. util.TableToJSON(stats))
end)
