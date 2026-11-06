-- R21-A client acceptance probe. A locked runner sends this after the map and server fixture load.
local BO = assert(BloodOverhaul and BloodOverhaul.Packaged and BloodOverhaul, "packaged blood missing")
assert(#BO.Shapes == 26 and #BO.Schemes == 12, "wrong shape/scheme inventory")
local saved, steps, index, label = {}, {}, 0, ""
for _, name in ipairs({ "bloodoverhaul_enable", "bloodoverhaul_scheme", "bloodoverhaul_variety",
    "nativeloader_blood_impacts", "nativeloader_blood_amount", "cl_drawhud", "r_drawviewmodel" }) do
    saved[name] = GetConVar(name):GetString()
end
local function emit(name, value) print("R21A_" .. name .. " " .. util.TableToJSON(value)) end
local function add(fn) steps[#steps + 1] = fn end
local function shot(name) label = name timer.Simple(.8, function() print("NL_SHOT " .. name) end) end
local names = { "decals/blood1", "decals/blood1_subrect", "decals/yblood1", "decals/yblood1_subrect",
    "decals/flesh/blood1", "decals/flesh/blood1_subrect", "decals/alienflesh/shot1",
    "decals/alienflesh/shot1_subrect", "decals/antlion/shot1", "decals/antlion/shot1_subrect", "decals/bloodstain_001" }
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
local focus, grid = false, true
hook.Add("CalcView", "r21a", function()
    if grid then return { origin = Vector(-220, -580, 300), angles = Angle(90, 0, 0), fov = 75, drawviewer = false } end
    local target = Vector(-200, -500, -100)
    for _, e in ipairs(ents.GetAll()) do if e:GetNWBool("r20c_target") then target = e:WorldSpaceCenter() break end end
    return { origin = Vector(-360, -645, -55), angles = (target - Vector(-360, -645, -55)):Angle(), fov = 65, drawviewer = false }
end)
hook.Add("HUDPaint", "r21a", function()
    draw.SimpleText("R21-A / " .. label, "DermaDefaultBold", 15, 15, color_white)
end)
RunConsoleCommand("cl_drawhud", "0") RunConsoleCommand("r_drawviewmodel", "0")
RunConsoleCommand("bloodoverhaul_enable", "1") RunConsoleCommand("bloodoverhaul_scheme", "realistic")
RunConsoleCommand("nativeloader_blood_impacts", "1") RunConsoleCommand("nativeloader_blood_amount", "1")
emit("START", { shapes = #BO.Shapes, schemes = #BO.Schemes, remix = RemixMaterial ~= nil,
    decal_wrapper = debug.getinfo(util.DecalEx, "S").source, materials = materials() })

local function clear() RunConsoleCommand("r_cleardecals") end
local function original_grid()
    clear()
    for row, code in ipairs({ 0, 1, 2, 6 }) do
        for i = 1, 8 do
            assert(BO.Shapes[i].key == "bo_blood" .. i)
            local m = assert(BO.Pattern(code, i), "missing original pattern")
            util.DecalEx(m, game.GetWorld(), Vector(-500 + (i - 1) * 80, -700 + (row - 1) * 80, -143), Vector(0, 0, 1), color_white, 1, 1)
        end
    end
end
add(function() original_grid() shot("eight_originals_four_families") end)
for _, scheme in ipairs(BO.Schemes) do
    local id = scheme.id
    add(function()
        RunConsoleCommand("bloodoverhaul_scheme", id)
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
    clear() RunConsoleCommand("bloodoverhaul_enable", "0")
    local baseline = materials()
    RunConsoleCommand("bloodoverhaul_enable", "1") RunConsoleCommand("bloodoverhaul_scheme", "blue")
    RunConsoleCommand("bloodoverhaul_enable", "0")
    local restored = materials()
    for i, entry in ipairs(baseline) do
        local other = restored[i]
        assert(entry.texture == other.texture, "texture restoration failed " .. entry.name)
        for _, key in ipairs({ "colour", "colour2" }) do
            if entry[key] then assert(other[key] and entry[key]:DistToSqr(other[key]) < .000001, "tint restoration failed " .. entry.name) end
        end
    end
    emit("RESTORED", { equal = true, materials = restored })
    -- C++ util.Decal bypasses the Lua mixer, as do NPC Blood/YellowBlood decals.
    for i = 1, 8 do
        local pos = Vector(-500 + (i - 1) * 80, -620, -143)
        util.Decal("Blood", pos + Vector(0, 0, 4), pos - Vector(0, 0, 4))
        pos.y = -500
        util.Decal("YellowBlood", pos + Vector(0, 0, 4), pos - Vector(0, 0, 4))
    end
    shot("engine_blood_yellow_master_off")
end)
add(function()
    RunConsoleCommand("bloodoverhaul_enable", "1") RunConsoleCommand("bloodoverhaul_scheme", "blue")
    shot("engine_blood_yellow_blue")
end)
local function combat(class)
    add(function()
        grid = false clear() RunConsoleCommand("bloodoverhaul_scheme", "realistic")
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
    for name, value in pairs(saved) do RunConsoleCommand(name, value) end
    print("NL_SHOT_DONE")
end
concommand.Add("nl_shot_taken", next_step)
next_step()
