-- R21-A client acceptance probe. A locked runner sends this after the map and server fixture load.
local BO = assert(BloodOverhaul and BloodOverhaul.Packaged and BloodOverhaul, "packaged blood missing")
assert(#BO.Shapes == 26 and #BO.Schemes == 12, "wrong shape/scheme inventory")
local saved, steps, index, label = {}, {}, 0, ""
for _, name in ipairs({ "bloodoverhaul_enable", "bloodoverhaul_scheme", "bloodoverhaul_variety",
    "nativeloader_blood_impacts", "nativeloader_blood_amount", "cl_drawhud", "r_drawviewmodel" }) do
    saved[name] = GetConVar(name):GetString()
end
local function emit(name, value)
    local text = util.TableToJSON(value)
    if #text < 3500 then print("R21A_" .. name .. " " .. text) return end
    local total = math.ceil(#text / 3000)
    for i = 1, total do
        print("R21A_CHUNK " .. name .. " " .. i .. "/" .. total .. " " .. text:sub((i - 1) * 3000 + 1, i * 3000))
    end
end
local function add(fn) steps[#steps + 1] = fn end
local function shot(name, delay) label = name timer.Simple(delay or .8, function() print("NL_SHOT " .. name) end) end
-- Console commands are queued. Use synchronous client convar writes before inspecting state.
local function set(name, value)
    -- Engine convars cannot use SetString; only the blood convars need synchronous inspection.
    if name == "cl_drawhud" or name == "r_drawviewmodel" then RunConsoleCommand(name, value)
    else GetConVar(name):SetString(value) end
end
local function ground(x, y)
    local tr = util.TraceLine({ start = Vector(x, y, 500), endpos = Vector(x, y, -700), mask = MASK_SOLID_BRUSHONLY })
    assert(tr.HitWorld and not tr.HitSky, "grid must hit the actual map surface")
    return tr
end
local names = { "decals/blood1", "decals/blood1_subrect", "decals/yblood1", "decals/yblood1_subrect",
    "decals/flesh/blood1", "decals/flesh/blood1_subrect", "decals/alienflesh/shot1",
    "decals/alienflesh/shot1_subrect", "decals/antlion/shot1", "decals/antlion/shot1_subrect", "decals/bloodstain_001",
    "decals/bloodoverhaul/red/bo_blood1_model", "decals/bloodoverhaul/red/bo_blood1" }
local function materials()
    local records = {}
    for _, name in ipairs(names) do
        local m = Material(name)
        local t = m:GetTexture("$basetexture")
        local record = { name = name, shader = m:GetShader(), texture = t and t:GetName(),
            colour = m:GetVector("$color"), colour2 = m:GetVector("$color2"), error = m:IsError(),
            vmt_sha256 = util.SHA256(file.Read("materials/" .. name .. ".vmt", "GAME") or "missing") }
        if RemixMaterial and RemixMaterial.GetAllTextureHashes then
            local ok, hashes = pcall(RemixMaterial.GetAllTextureHashes, name)
            record.hashes_ok, record.hashes = ok, ok and hashes or tostring(hashes)
        end
        records[#records + 1] = record
    end
    return records
end
local function check_source(records)
    for _, entry in ipairs(records) do
        local body = string.lower(file.Read("materials/" .. entry.name .. ".vmt", "GAME") or "")
        local expected = body:match('"?%$basetexture"?%s+"([^"]+)"')
        if expected then assert(entry.texture == expected, "off must restore the winning VMT texture: " .. entry.name) end
        local shader = string.lower(entry.shader)
        if shader:find("lightmappedgeneric", 1, true) or shader:find("vertexlitgeneric", 1, true) then
            local model = shader:find("vertexlitgeneric", 1, true)
            local key = model and "color2" or "color"
            local text = body:match('"?%$' .. key .. '"?%s+"%[([^%]]+)%]"')
            local numbers = {}
            for value in (text or "1 1 1"):gmatch("[%d%.%-]+") do numbers[#numbers + 1] = tonumber(value) end
            local colour = Vector(numbers[1], numbers[2], numbers[3])
            assert(entry[model and "colour2" or "colour"]:DistToSqr(colour) < .0001,
                "off must restore the winning VMT tint: " .. entry.name)
        end
    end
end
local grid = true
hook.Add("CalcView", "r21a", function()
    if grid then return { origin = Vector(-220, -580, 300), angles = Angle(90, 90, 0), fov = 75, drawviewer = false } end
    local target = Vector(-200, -500, -100)
    for _, e in ipairs(ents.GetAll()) do if e:GetNWBool("r20c_target") then target = e:WorldSpaceCenter() break end end
    return { origin = Vector(-360, -645, -55), angles = (target - Vector(-360, -645, -55)):Angle(), fov = 65, drawviewer = false }
end)
hook.Add("HUDPaint", "r21a", function()
    draw.SimpleText("R21-A / " .. label, "DermaDefaultBold", 15, 15, color_white)
end)
set("cl_drawhud", "0") set("r_drawviewmodel", "0")
set("bloodoverhaul_enable", "1") set("bloodoverhaul_scheme", "realistic")
set("nativeloader_blood_impacts", "1") set("nativeloader_blood_amount", "1")
local panels = 0
for _, tab in ipairs(spawnmenu.GetTools()) do
    for _, category in ipairs(tab.Items or {}) do
        for _, item in ipairs(category) do
            if item.ItemName == "bloodoverhaul_settings" then panels = panels + 1 end
        end
    end
end
assert(panels == 1, "expected one blood settings panel")
emit("START", { shapes = #BO.Shapes, schemes = #BO.Schemes, remix = RemixMaterial ~= nil,
    panels = panels, decal_wrapper = debug.getinfo(util.DecalEx, "S").source, materials = materials() })

local function clear(after)
    RunConsoleCommand("r_cleardecals")
    -- Clearing is queued too: stamping now would erase the new decals on the next frame.
    if after then timer.Simple(.2, after) end
end
local function original_grid()
    clear(function()
    for row, code in ipairs({ 0, 1, 2, 6 }) do
        for i = 1, 8 do
            assert(BO.Shapes[i].key == "bo_blood" .. i)
            local m = assert(BO.Pattern(code, i), "missing original pattern")
            local tr = ground(-500 + (i - 1) * 80, -700 + (row - 1) * 80)
            util.DecalEx(m, tr.Entity, tr.HitPos, tr.HitNormal, color_white, 1, 1)
        end
    end
    shot("eight_originals_four_families")
    end)
end
add(function() RunConsoleCommand("r21a_grid") timer.Simple(.6, original_grid) end)
for _, scheme in ipairs(BO.Schemes) do
    local id = scheme.id
    add(function()
        set("bloodoverhaul_scheme", id)
        local rows = {}
        for _, code in ipairs({ 0, 1, 2, 6 }) do
            local m = BO.Pattern(code, 1)
            rows[#rows + 1] = { code = code, texture = m:GetTexture("$basetexture"):GetName(), tint = m:GetVector("$color") }
        end
        emit("SCHEME", { id = id, rows = rows, materials = materials() })
        shot("scheme_" .. id)
    end)
end
add(function()
    clear(function()
    set("bloodoverhaul_enable", "0")
    local baseline = materials()
    check_source(baseline)
    set("bloodoverhaul_enable", "1") set("bloodoverhaul_scheme", "blue")
    set("bloodoverhaul_enable", "0")
    local restored = materials()
    check_source(restored)
    for i, entry in ipairs(baseline) do
        local other = restored[i]
        assert(entry.texture == other.texture, "texture restoration failed " .. entry.name)
        for _, key in ipairs({ "colour", "colour2" }) do
            if entry[key] then assert(other[key] and entry[key]:DistToSqr(other[key]) < .000001, "tint restoration failed " .. entry.name) end
        end
    end
    emit("RESTORED", { equal = true, materials = restored })
    -- Server util.Decal broadcasts the engine decal, matching native NPC bleeding dispatch.
    RunConsoleCommand("r21a_native")
    shot("engine_blood_yellow_master_off", 3)
    end)
end)
add(function()
    set("bloodoverhaul_enable", "1") set("bloodoverhaul_scheme", "blue")
    shot("engine_blood_yellow_blue")
end)
add(function()
    set("bloodoverhaul_enable", "0")
    local restored = materials()
    check_source(restored)
    emit("NATIVE_RESTORED", { equal = true, materials = restored })
    shot("engine_blood_yellow_restored", 2)
end)
if ABL and ABL.Drops and ABL.Pools then
    add(function()
        clear(function()
        grid = false
        set("bloodoverhaul_enable", "1") set("bloodoverhaul_scheme", "realistic")
        local floor = ground(-220, -500).HitPos
        ABL.Pools.Create(floor.x, floor.y, floor.z + .1, 0, 0, 1, 60)
        for i = 1, 12 do
            local pos = ground(-250 + i * 9, -540).HitPos
            ABL.Stains.AddOverlay("splat", (i % 4) + 1, pos.x, pos.y, pos.z + .1,
                0, 0, 1, 1, 0, 0, 0, 1, 0, 12, 12, 120, 1)
        end
        timer.Create("r21a_physics", .25, 24, function()
            for _ = 1, 80 do ABL.Drops.Spawn(-200, -500, floor.z + 74, math.Rand(-50, 50), math.Rand(-50, 50), math.Rand(30, 100), .1) end
        end)
        timer.Simple(4, function()
            local guard = NativeLoaderRenderGuard
            emit("PHYSICS", { drops = ABL.Drops.Count(), pools = ABL.Pools.Count(),
                ground = ABL.GroundStains and ABL.GroundStains.Count(),
                guard_errors = guard and guard.errors, guard_cleanup = guard and guard.cleanup_errors })
            if NativeLoaderEffectCategories then NativeLoaderEffectCategories.Status() end
            shot("physics_blood_drops_pools_stains")
        end)
        end)
    end)
end
local function combat(class)
    add(function()
        grid = false clear() set("bloodoverhaul_enable", "1") set("bloodoverhaul_scheme", "realistic")
        RunConsoleCommand("r20c_spawn", class)
        timer.Simple(1, function() label = class RunConsoleCommand("r20c_fire", "weapon_pistol", "r21a_" .. class) end)
    end)
end
for _, class in ipairs({ "npc_citizen", "npc_combine_s", "npc_zombie", "npc_antlion", "prop_ragdoll" }) do combat(class) end
add(function()
    RunConsoleCommand("r20c_resume") clear()
    local start, frames, peak, stain_peak, rate_peak = SysTime(), {}, 0, 0, 0
    local last = start
    hook.Add("PostRender", "r21a_stress", function()
        local now = SysTime() frames[#frames + 1] = (now - last) * 1000 last = now
        for i = 1, 6 do
            local data = EffectData() data:SetOrigin(Vector(-200, -500, -100)) data:SetNormal(Vector(1, 0, 0))
            data:SetColor(i % 2) data:SetScale(12) util.Effect("BloodImpact", data)
        end
        peak = math.max(peak, #BO.ImpactBudgets.particles.live)
        rate_peak = math.max(rate_peak, #BO.ImpactBudgets.particles.recent)
        stain_peak = math.max(stain_peak, BO.ImpactBudgets.stains.total)
        if now - start < 4 then return end
        hook.Remove("PostRender", "r21a_stress") table.sort(frames)
        assert(peak <= 512 and rate_peak <= 640 and stain_peak <= 384, "impact budget exceeded")
        emit("BUDGET", { frames = #frames, seconds = now - start, median_ms = frames[math.ceil(#frames / 2)],
            p99_ms = frames[math.ceil(#frames * .99)], live_peak = peak, recent_peak = rate_peak, stains = stain_peak, stats = BO.ImpactStats })
        shot("bounded_impacts")
    end)
end)
local function next_step()
    RunConsoleCommand("r20c_resume")
    if IsValid(g_SpawnMenu) then g_SpawnMenu:Close() end
    for _, panel in ipairs(vgui.GetWorldPanel():GetChildren()) do
        if panel ~= g_SpawnMenu and panel ~= g_ContextMenu and IsValid(panel) and panel.GetTitle and panel.Close then panel:Close() end
    end
    index = index + 1
    if steps[index] then timer.Simple(.2, steps[index]) return end
    emit("FINAL", { materials = materials(), stats = BO.ImpactStats, steps = index - 1 })
    hook.Remove("CalcView", "r21a") hook.Remove("HUDPaint", "r21a")
    for name, value in pairs(saved) do set(name, value) end
    print("NL_SHOT_DONE")
end
concommand.Add("nl_shot_taken", next_step)
next_step()
