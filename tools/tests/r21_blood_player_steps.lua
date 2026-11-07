-- R21 review: real weapons and the player's cleanup/scheme controls; never packaged.
if SERVER then
    local target, wall, floor, hits = nil, nil, nil, 0
    local function human() return player.GetHumans()[1] end
    local function aim(ent)
        local bone = ent:LookupBone("ValveBiped.Bip01_Spine2")
        if bone then local pos = ent:GetBonePosition(bone) if pos then return pos end end
        return ent:WorldSpaceCenter()
    end
    concommand.Add("r21review_shoot", function(_, _, args)
        if IsValid(target) then target:Remove() end
        if IsValid(wall) then wall:Remove() end
        if IsValid(floor) then floor:Remove() end
        local p = assert(human())
        p:GodEnable() p:SetPos(Vector(-420, -500, -147))
        wall = ents.Create("prop_physics") wall:SetModel("models/hunter/blocks/cube2x2x2.mdl")
        wall:SetPos(Vector(-125, -500, -95)) wall:Spawn() wall:SetMaterial("models/debug/debugwhite")
        local phys = wall:GetPhysicsObject() if IsValid(phys) then phys:EnableMotion(false) end
        floor = ents.Create("prop_physics") floor:SetModel("models/hunter/plates/plate4x4.mdl")
        floor:SetPos(Vector(-260, -500, -147)) floor:Spawn() floor:SetMaterial("models/debug/debugwhite")
        phys = floor:GetPhysicsObject() if IsValid(phys) then phys:EnableMotion(false) end
        target = ents.Create(args[1])
        if args[1] == "npc_citizen" then target:SetModel("models/Humans/Group01/male_07.mdl") end
        target:SetPos(Vector(-220, -500, -147)) target:SetAngles(Angle(0, 180, 0))
        target:Spawn() target:Activate() target:SetHealth(100000)
        target:SetNWBool("r21review_target", true)
        p:Give("weapon_smg1") p:SetAmmo(999, "SMG1") p:SelectWeapon("weapon_smg1")
        p:SetEyeAngles((aim(target) - p:EyePos()):Angle()) p:ViewPunchReset()
        hits = 0
        timer.Simple(.5, function()
            if not IsValid(target) then return end
            local w = p:GetActiveWeapon() w:SetClip1(99) w:SetNextPrimaryFire(CurTime())
            p:ConCommand("+attack")
            timer.Simple(.85, function()
                p:ConCommand("-attack")
                print("R21_PLAYER_SHOT " .. util.TableToJSON({ class = args[1], label = args[2], hits = hits,
                    blood = target:GetBloodColor(), wall = wall:EntIndex() }))
            end)
        end)
    end)
    hook.Add("PostEntityFireBullets", "r21review_hits", function(ent, data)
        if ent == human() and data.Trace and data.Trace.Entity == target then hits = hits + 1 end
    end)
    concommand.Add("r21review_cleanup", function()
        game.CleanUpMap()
        print("R21_PLAYER_CLEANUP game.CleanUpMap")
    end)
    concommand.Add("r21review_mapchange", function()
        file.Write("r21review_map_return.txt", "1")
        print("R21_PLAYER_ACTION changelevel gm_construct")
        game.ConsoleCommand("changelevel gm_construct\n")
    end)
    game.ConsoleCommand("sv_cheats 1\nsv_allowcslua 1\nai_disabled 1\nhost_timescale 1\n")
    return
end

-- CLIENT PROBE
local map_return = file.Exists("r21review_map_return.txt", "DATA")
if not R21PlayerStepsExplicit and not map_return then return end
if map_return then
    file.Delete("r21review_map_return.txt")
    R21PlayerStepsRunning = nil
end
if R21PlayerStepsRunning then return end
R21PlayerStepsRunning = true
local BO = assert(BloodOverhaul and BloodOverhaul.Packaged and BloodOverhaul)
local saved, calls, steps, index, focus, label = {}, {}, {}, 0, "wall", ""
for _, key in ipairs({ "bloodoverhaul_enable", "bloodoverhaul_scheme", "nativeloader_blood_impacts",
    "nativeloader_blood_amount", "cl_drawhud", "r_drawviewmodel" }) do
    saved[key] = GetConVar(key):GetString()
end
local function set(name, value) RunConsoleCommand(name, value) end
local function emit(name, value) print("R21_PLAYER_" .. name .. " " .. util.TableToJSON(value)) end
local original_decal = util.DecalEx
util.DecalEx = function(material, ...)
    local name = material and material:GetName() or "nil"
    calls[name] = (calls[name] or 0) + 1
    return original_decal(material, ...)
end
local function close()
    if IsValid(g_SpawnMenu) then g_SpawnMenu:Close() end
    for _, p in ipairs(vgui.GetWorldPanel():GetChildren()) do
        if p ~= g_SpawnMenu and p ~= g_ContextMenu and IsValid(p) and p.GetTitle and p.Close then p:Close() end
    end
end
hook.Add("CalcView", "r21review", function()
    if focus == "floor" then
        local eye = Vector(-275, -595, -55)
        return { origin = eye, angles = (Vector(-220, -500, -148) - eye):Angle(), fov = 65, drawviewer = false }
    end
    local eye = Vector(-365, -635, -45)
    return { origin = eye, angles = (Vector(-180, -500, -108) - eye):Angle(), fov = 65, drawviewer = false }
end)
hook.Add("HUDPaint", "r21review", function()
    draw.SimpleText("R21 player steps / " .. label, "DermaDefaultBold", 15, 15, color_white)
end)
local function snapshot(stage)
    local mats = {}
    for _, code in ipairs({ 0, 1 }) do
        local m = BO.Pattern(code, 1)
        if m then mats[#mats + 1] = { code = code, name = m:GetName(), shader = m:GetShader(),
            texture = m:GetTexture("$basetexture"):GetName(), tint = m:GetVector("$color") } end
    end
    emit("STATE", { stage = stage, map = game.GetMap(), scheme = BO.ConVars.scheme:GetString(),
        enabled = BO.ConVars.enable:GetBool(), materials = mats, calls = calls, stats = BO.ImpactStats })
end
local function capture(stage, view)
    focus, label = view, stage .. "_" .. view
    close()
    timer.Simple(1.2, function() snapshot(label) print("NL_SHOT " .. label) end)
end
local function add(fn) steps[#steps + 1] = fn end
local function shoot(stage, class)
    add(function()
        label = stage .. "_" .. class
        RunConsoleCommand("r21review_shoot", class, label)
        timer.Simple(5, function() capture(label, "wall") end)
    end)
    add(function() capture(stage .. "_" .. class, "floor") end)
end
local function pair(stage)
    shoot(stage, "npc_citizen") shoot(stage, "npc_antlion")
end
local function clear_button()
    local form = vgui.Create("DForm")
    local old, button = form.Button, nil
    form.Button = function(self, text, command, ...)
        local control = old(self, text, command, ...)
        if command == "bloodoverhaul_clear" then button = control end
        return control
    end
    BO.BuildMenu(form)
    assert(IsValid(button), "real Blood panel clear button missing")
    button:DoClick() form:Remove()
    emit("ACTION", { action = "RTX Remix / Blood / Clear all decals", actual_button = true })
end
set("cl_drawhud", "0") set("r_drawviewmodel", "0")
set("bloodoverhaul_enable", "1") set("bloodoverhaul_scheme", "realistic")
set("nativeloader_blood_impacts", "1") set("nativeloader_blood_amount", "1")
emit("START", { shapes = #BO.Shapes, remix = RemixMaterial ~= nil, map = game.GetMap() })
if map_return then
    pair("after_map_change")
else
pair("initial")
add(function() clear_button() timer.Simple(2, function() print("NL_SHOT clear_button") end) end)
pair("after_button")
add(function() RunConsoleCommand("r21review_cleanup") timer.Simple(2, function() print("NL_SHOT sandbox_cleanup") end) end)
pair("after_cleanup")
add(function() RunConsoleCommand("r_cleardecals") emit("ACTION", { action = "r_cleardecals" }) timer.Simple(2, function() print("NL_SHOT raw_clear") end) end)
pair("after_raw_clear")
add(function() set("bloodoverhaul_scheme", "blue") timer.Simple(2, function() print("NL_SHOT select_blue") end) end)
pair("blue")
add(function() set("bloodoverhaul_scheme", "realistic") timer.Simple(2, function() print("NL_SHOT select_realistic") end) end)
pair("realistic_again")
end
add(function()
    timer.Simple(10, function() capture("wait_10_seconds", "floor") end)
end)
if not map_return then add(function() RunConsoleCommand("r21review_mapchange") end) end
local function next_step()
    index = index + 1
    if steps[index] then timer.Simple(.3, steps[index]) return end
    snapshot("final")
    util.DecalEx = original_decal
    hook.Remove("CalcView", "r21review") hook.Remove("HUDPaint", "r21review")
    for name, value in pairs(saved) do set(name, value) end
    emit("FINAL", { steps = index - 1, calls = calls, stats = BO.ImpactStats })
    print("NL_SHOT_DONE")
end
local acknowledged = 0
concommand.Add("nl_shot_taken", function(_, _, args)
    local number = tonumber(args[1]) or acknowledged + 1
    if number <= acknowledged then return end
    acknowledged = number next_step()
end)
if map_return then timer.Simple(8, next_step) else next_step() end
