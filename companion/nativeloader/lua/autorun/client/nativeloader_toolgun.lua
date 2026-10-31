-- Draw only the toolgun's live screen in the HUD pass, after Remix's temporal reconstruction.
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
local output = CreateMaterial("nativeloader_toolgun_output", "UnlitGeneric", {
    ["$basetexture"] = white, ["$translucent"] = "1", ["$vertexalpha"] = "1", ["$ignorez"] = "1",
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

local target, width, height
local function render_screen(data)
    local w, h = ScrW(), ScrH()
    if not target or w ~= width or h ~= height then
        target = GetRenderTargetEx("nativeloader_toolgun_" .. w .. "x" .. h, w, h,
            RT_SIZE_NO_CHANGE, MATERIAL_RT_DEPTH_SEPARATE, 12, -- Source texture flags CLAMPS | CLAMPT
            0, IMAGE_FORMAT_BGRA8888)
        assert(target and not target:IsError(), "Could not create toolgun screen target")
        width, height = w, h
        output:SetTexture("$basetexture", target)
    end
    local view = data.view
    local camera = {type = "3D", origin = view.origin, angles = view.angles,
        fov = view.fovviewmodel, aspect = view.aspect, x = 0, y = 0, w = w, h = h,
        znear = view.znearviewmodel, zfar = view.zfarviewmodel, offcenter = view.offcenter}
    local targetPushed, cameraStarted, modelPushed, meshStarted = false, false, false, false
    local ok, err = xpcall(function()
        render.PushRenderTarget(target)
        targetPushed = true
        render.Clear(0, 0, 0, 0, true, true)
        cam.Start(camera)
        cameraStarted = true
        -- Build a private depth mask so the screen cannot paint over the gun casing or hands.
        render.OverrideColorWriteEnable(true, false)
        render.OverrideAlphaWriteEnable(true, false)
        render.OverrideDepthEnable(true, true)
        data.model:DrawModel()
        if IsValid(data.hands) then data.hands:DrawModel() end
        render.OverrideColorWriteEnable(false)
        render.OverrideAlphaWriteEnable(true, true)
        render.DepthRange(0, 0.99999)
        cam.PushModelMatrix(Matrix())
        modelPushed = true
        render.SetMaterial(screen)
        for _, part in ipairs(data.parts) do
            screen:SetTexture("$basetexture", part.texture)
            render.SetMaterial(screen)
            mesh.Begin(MATERIAL_TRIANGLES, #part.vertices / 3)
            meshStarted = true
            for _, vertex in ipairs(part.vertices) do
                mesh.Position(vertex.position)
                mesh.TexCoord(0, vertex.u, vertex.v)
                mesh.Color(255, 255, 255, 255)
                mesh.AdvanceVertex()
            end
            mesh.End()
            meshStarted = false
        end
    end, debug.traceback)
    if meshStarted then pcall(mesh.End) end
    if modelPushed then cam.PopModelMatrix() end
    render.OverrideColorWriteEnable(false)
    render.OverrideAlphaWriteEnable(false)
    render.OverrideDepthEnable(false)
    render.DepthRange(0, 1)
    if cameraStarted then cam.End3D() end
    if targetPushed then render.PopRenderTarget() end
    if not ok then error(err) end
    stats.draws = stats.draws + 1
    surface.SetMaterial(output)
    surface.SetDrawColor(255, 255, 255, 255)
    surface.DrawTexturedRect(0, 0, w, h)
end

hook.Add("HUDPaint", "nativeloader_toolgun_screen", function()
    if drawing or failed or not enabled:GetBool() then return end
    local data = captured
    if not data or data.frame ~= FrameNumber() or not IsValid(data.model) then return end
    if render.GetRenderTarget() ~= nil then return end
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
