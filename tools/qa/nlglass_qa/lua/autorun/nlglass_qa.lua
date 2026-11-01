-- G1 QA add-on (never shipped): copied into a test install's garrysmod/addons for one session, then
-- removed. `nlglass_qa` (server, host only) runs every break cause against nlglass_pane in turn and a
-- performance scene; the client frames each step and prints NL_SHOT for poc_session.py --lua-shots.
local NET_VIEW, NET_NEXT = "nlglass_qa_view", "nlglass_qa_next"
if SERVER then
    util.AddNetworkString(NET_VIEW) util.AddNetworkString(NET_NEXT)
    local steps, index, owner = {}, 0, nil
    local ORIGIN = Vector(831.235, 576, -143.08) -- gm_construct, open field to the west
    local function say(fmt, ...) print(string.format("NL_QA " .. fmt, ...)) end
    local function pane(center, kind, w, h)
        local normal = Vector(1, 0, 0) -- faces the player, who stands east of it looking west
        local tangent = Vector(0, 0, 1):Cross(normal):GetNormalized()
        local e = ents.Create("nlglass_pane")
        e.NLGlassPreset = {width = w or 96, height = h or 64, kind = kind or "annealed"}
        e:SetPos(center) e:SetAngles(tangent:AngleEx(normal)) e:Spawn() e:Activate()
        return e
    end
    local function point(e, u, v) -- pane-local (u, v) to world: x along the pane's Forward, y along its Left
        return e:GetPos() + e:GetForward() * u - e:GetRight() * v
    end
    local function shoot(target, damage)
        local ply = owner
        local src = target + Vector(120, 0, 8)
        ply:FireBullets({Src = src, Dir = (target - src):GetNormalized(), Damage = damage, Num = 1, Spread = vector_origin,
            Force = damage * 0.2, Tracer = 0, Attacker = ply})
    end
    local function view(label, at, delay)
        net.Start(NET_VIEW) net.WriteString(label) net.WriteVector(at + Vector(140, 0, 20))
        net.WriteAngle((at - (at + Vector(140, 0, 20))):Angle()) net.WriteFloat(delay or 0.5) net.Send(owner)
    end
    local function clear() for _, e in ipairs(ents.FindByClass("nlglass_pane")) do e:Remove() end
        for _, e in ipairs(ents.FindByClass("prop_physics")) do if e.NLGlassQA then e:Remove() end end
        for _, e in ipairs(ents.FindByClass("prop_ragdoll")) do if e.NLGlassQA then e:Remove() end end end
    local A = ORIGIN + Vector(-220, 0, 52)
    local function add(fn) steps[#steps + 1] = fn end
    -- 1. bullets: one round cracks, more grow the cracks, then the pane breaks
    add(function() clear() local e = pane(A) steps.e = e timer.Simple(0.5, function() shoot(point(e, 24, 14), 15) say("bullet 1") view("bullet_crack1", A) end) end)
    add(function() shoot(point(steps.e, 24, 14), 15) say("bullet 2") view("bullet_crack2", A) end)
    add(function() for i = 1, 4 do shoot(point(steps.e, 24 - i, 14 + i), 15) end say("bullets 3-6, pane valid %s", tostring(IsValid(steps.e))) view("bullet_break", A, 0.35) end)
    add(function() view("bullet_settled", A, 3) end)
    -- 2. the break follows the impact: a heavy round at a corner of one pane and the centre of another
    add(function() clear() local a, b = pane(A + Vector(0, -60, 0)), pane(A + Vector(0, 60, 0))
        timer.Simple(0.5, function() shoot(point(a, -40, -24), 400) shoot(point(b, 0, 0), 400) say("corner and centre") view("corner_vs_centre", A, 0.3) end) end)
    add(function() view("corner_vs_centre_settled", A, 3) end)
    -- 3. a thrown prop, 4. a thrown ragdoll, 5. a running player, 6. an explosion, 7. a scripted break
    local function throw(model, class, speed)
        clear() local e = pane(A)
        timer.Simple(0.5, function()
            local p = ents.Create(class) p:SetModel(model) p:SetPos(A + Vector(90, 0, 0)) p.NLGlassQA = true p:Spawn()
            for i = 0, p:GetPhysicsObjectCount() - 1 do local o = p:GetPhysicsObjectNum(i) if IsValid(o) then o:SetVelocity(Vector(-speed, 0, 40)) o:Wake() end end
            say("%s thrown at %d, mass %.1f", class, speed, IsValid(p:GetPhysicsObject()) and p:GetPhysicsObject():GetMass() or -1)
            view(class, A, 0.6)
        end)
    end
    add(function() throw("models/props_c17/oildrum001.mdl", "prop_physics", 700) end)
    add(function() throw("models/Humans/Group01/male_07.mdl", "prop_ragdoll", 650) end)
    add(function() clear() local e = pane(A + Vector(0, 0, -16), "annealed", 64, 96)
        timer.Simple(0.5, function() owner:SetPos(Vector(A.x + 70, A.y, ORIGIN.z)) owner:SetVelocity(Vector(-500, 0, 0)) say("player runs") view("player", A, 0.8) end) end)
    add(function() clear() local e = pane(A)
        timer.Simple(0.5, function() util.BlastDamage(owner, owner, A + Vector(40, 10, 0), 200, 120) say("blast") view("blast", A, 0.4) end) end)
    add(function() clear() local e = pane(A, "tempered")
        timer.Simple(0.5, function() for i = 1, 6 do shoot(point(e, -10 + i, 6), 15) end say("tempered, pane valid %s", tostring(IsValid(e))) view("tempered", A, 0.4) end) end)
    add(function() clear() local e = pane(A) timer.Simple(0.5, function() e:Fire("Break") say("scripted") view("scripted", A, 0.6) end) end)
    -- 8. performance: 40 panes broken by blasts; the client measures the frame time before, falling, settled
    add(function() clear() owner:SetPos(ORIGIN) owner:SetEyeAngles(Angle(10, 180, 0))
        net.Start(NET_VIEW) net.WriteString("perf_empty") net.WriteVector(ORIGIN + Vector(0, 0, 80)) net.WriteAngle(Angle(15, 180, 0)) net.WriteFloat(6) net.Send(owner) end)
    add(function()
        local list = {}
        for i = 0, 7 do for j = 0, 4 do list[#list + 1] = pane(ORIGIN + Vector(-300 - j * 70, -280 + i * 80, 52)) end end
        timer.Simple(1, function()
            for k, e in ipairs(list) do timer.Simple(k * 0.03, function() if IsValid(e) then util.BlastDamage(owner, owner, e:GetPos() + Vector(30, 0, 0), 90, 200) end end) end
            say("perf: %d panes broken", #list)
            net.Start(NET_VIEW) net.WriteString("perf_falling") net.WriteVector(ORIGIN + Vector(0, 0, 80)) net.WriteAngle(Angle(15, 180, 0)) net.WriteFloat(4) net.Send(owner)
        end)
    end)
    add(function() net.Start(NET_VIEW) net.WriteString("perf_settled") net.WriteVector(ORIGIN + Vector(0, 0, 80)) net.WriteAngle(Angle(15, 180, 0)) net.WriteFloat(15) net.Send(owner) end)
    local function nextStep()
        index = index + 1
        local fn = steps[index]
        if not fn then clear() say("done") net.Start(NET_VIEW) net.WriteString("") net.WriteVector(vector_origin) net.WriteAngle(angle_zero) net.WriteFloat(0) net.Send(owner) return end
        local ok, err = pcall(fn) if not ok then say("step %d failed: %s", index, tostring(err)) nextStep() end
    end
    net.Receive(NET_NEXT, function(_, ply) if ply == owner then timer.Simple(0.2, nextStep) end end)
    concommand.Add("nlglass_qa", function(ply)
        if IsValid(ply) and not ply:IsListenServerHost() then return end
        owner = IsValid(ply) and ply or player.GetAll()[1]
        if not IsValid(owner) then return end
        index = 0 owner:SetPos(ORIGIN) owner:SetEyeAngles(Angle(0, 180, 0)) owner:Give("weapon_pistol")
        say("start, %d steps", #steps) timer.Simple(1, nextStep)
    end)
    return
end
-- client: frame the step, report the broken-glass manager, measure frame times, print NL_SHOT
local camera, frames
hook.Add("CalcView", "nlglass_qa", function() if camera then return {origin = camera[1], angles = camera[2], fov = 70, drawviewer = true} end end)
hook.Add("HUDShouldDraw", "nlglass_qa", function() if camera then return false end end)
hook.Add("PostRender", "nlglass_qa", function() if frames then frames[#frames + 1] = FrameTime() end end)
local function stats(label)
    local d = NLGlassDebris
    local s = d and d.Stats and d.Stats() or {}
    local times = frames or {} frames = nil
    table.sort(times)
    local sum = 0 for _, t in ipairs(times) do sum = sum + t end
    local mean = #times > 0 and sum / #times or 0
    local p99 = #times > 0 and times[math.max(1, math.ceil(#times * 0.99))] or 0
    local n = s.native or {}
    print(string.format("NL_QA client %s backend %s live %s moving %s sleeping %s batches %s frames %d mean_ms %.2f p99_ms %.2f" ..
        " | jolt step_ms %s awake %s brushes %s skipped %s statics %s models %s",
        label, d and d.Backend() or "missing", tostring(s.live), tostring(s.moving), tostring(s.sleeping), tostring(s.batches),
        #times, mean * 1000, p99 * 1000, tostring(n.step_ms), tostring(n.awake), tostring(n.brushes), tostring(n.skipped_brushes),
        tostring(n.statics), tostring(n.models)))
end
local pending
net.Receive(NET_VIEW, function()
    local label, origin, angles, delay = net.ReadString(), net.ReadVector(), net.ReadAngle(), net.ReadFloat()
    if label == "" then camera = nil print("NL_SHOT_DONE") return end
    camera = {origin, angles} frames = {} pending = label
    timer.Simple(delay, function() stats(label) print("NL_SHOT " .. label) end)
end)
concommand.Add("nl_shot_taken", function() if pending then pending = nil net.Start(NET_NEXT) net.SendToServer() end end)
