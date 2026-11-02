-- G1 QA add-on (never shipped): copied into a test install's garrysmod/addons for one session, then
-- removed. `nlglass_qa [field|map]` (server, host only) runs break causes against glass and a
-- performance scene; the client frames each step and prints NL_SHOT for poc_session.py --lua-shots.
local NET_VIEW, NET_NEXT, NET_FIXTURE = "nlglass_qa_view", "nlglass_qa_next", "nlglass_qa_fixture"
-- The walk and run steps hold the player's own keys: forward (and sprint), facing west. Both realms run it,
-- so prediction agrees; GMod picks the run speed from the user command's buttons, not from the move data.
hook.Add("StartCommand", "nlglass_qa_walk", function(ply, cmd)
    if CurTime() < ply:GetNW2Float("nlglass_qa_attack_until", 0) then
        cmd:ClearMovement();cmd:SetViewAngles(ply:GetNW2Angle("nlglass_qa_attack_angle",angle_zero))
        cmd:SetButtons(IN_ATTACK);return
    end
    if CurTime() > ply:GetNW2Float("nlglass_qa_move_until", 0) then return end
    local sprint = ply:GetNW2Bool("nlglass_qa_sprint", false)
    cmd:ClearMovement() cmd:SetViewAngles(Angle(0, 180, 0)) cmd:SetForwardMove(10000)
    cmd:SetButtons(bit.bor(IN_FORWARD, sprint and IN_SPEED or 0))
end)
if SERVER then
    util.AddNetworkString(NET_VIEW) util.AddNetworkString(NET_NEXT) util.AddNetworkString(NET_FIXTURE)
    local steps, index, owner = {}, 0, nil
    local ORIGIN = Vector(831.235, 576, -143.08) -- gm_construct, open field to the west
    local function say(fmt, ...) print(string.format("NL_QA " .. fmt, ...)) end
    local function send(label, from, at, delay)
        net.Start(NET_VIEW) net.WriteString(label) net.WriteVector(from) net.WriteAngle((at - from):Angle())
        net.WriteFloat(delay or 0.5) net.Send(owner)
    end
    local function view(label, at, delay) send(label, at + Vector(140, 0, 20), at, delay) end
    local function pane(center, kind, w, h)
        local normal = Vector(1, 0, 0) -- faces the player, who stands east of it looking west
        local tangent = Vector(0, 0, 1):Cross(normal):GetNormalized()
        local e = ents.Create("nlglass_pane")
        e.NLGlassPreset = {width = w or 96, height = h or 64, kind = kind or "annealed"}
        e:SetPos(center) e:SetAngles(tangent:AngleEx(normal)) e:Spawn() e:Activate()
        return e
    end
    local function point(e, u, v) return e:GetPos() + e:GetForward() * u - e:GetRight() * v end
    local function shoot(target, damage, from)
        local src = from or target + Vector(120, 0, 8)
        owner:FireBullets({Src = src, Dir = (target - src):GetNormalized(), Damage = damage, Num = 1, Spread = vector_origin,
            Force = damage * 0.2, Tracer = 0, Attacker = owner})
    end
    local function clear() for _, e in ipairs(ents.FindByClass("nlglass_pane")) do e:Remove() end
        for _, c in ipairs({"prop_physics", "prop_ragdoll"}) do for _, e in ipairs(ents.FindByClass(c)) do if e.NLGlassQA then e:Remove() end end end end
    local function throw(model, class, from, velocity)
        local p = ents.Create(class) p:SetModel(model) p:SetPos(from) p.NLGlassQA = true p:Spawn()
        for i = 0, p:GetPhysicsObjectCount() - 1 do local o = p:GetPhysicsObjectNum(i) if IsValid(o) then o:SetVelocity(velocity) o:Wake() end end
        return p
    end
    local tags = {}
    local function add(fn, tag) steps[#steps + 1] = fn tags[#steps] = tag end
    -- accepted impacts per pane id, counted around the glass server's one entry point
    local S, impacts = nil, {}
    local function watch()
        S = NLGlass and NLGlass.Server
        if not S or S.NLGlassQAImpact then return end
        S.NLGlassQAImpact = S.Impact
        S.Impact = function(r, impact, forceAll)
            local ok, pieces = S.NLGlassQAImpact(r, impact, forceAll)
            if ok then impacts[r.id] = (impacts[r.id] or 0) + 1 end
            return ok, pieces
        end
    end
    local function left(id)
        local r, F = id and S.records[id], NLGlass.Fracture
        if not r then return 0 end
        local area = 0 for _, poly in ipairs(F.Remaining(r.state)) do area = area + F.Area(poly) end
        return area / F.Area(r.state.def.outline)
    end
    local function field()
        local A = ORIGIN + Vector(-220, 0, 52)
        -- 1. bullets: one round cracks, more grow the cracks, then the pane breaks
        add(function() clear() local e = pane(A) steps.e = e timer.Simple(0.5, function() shoot(point(e, 24, 14), 15) say("bullet 1") view("bullet_crack1", A) end) end)
        add(function() shoot(point(steps.e, 24, 14), 15) say("bullet 2") view("bullet_crack2", A) end)
        add(function() for i = 1, 4 do shoot(point(steps.e, 24 - i, 14 + i), 15) end say("bullets 3-6, pane valid %s", tostring(IsValid(steps.e))) view("bullet_break", A, 0.35) end)
        add(function() view("bullet_settled", A, 3) end)
        -- 2. the break follows the impact
        add(function() clear() local a, b = pane(A + Vector(0, -60, 0)), pane(A + Vector(0, 60, 0))
            timer.Simple(0.5, function() shoot(point(a, -40, -24), 400) shoot(point(b, 0, 0), 400) say("corner and centre") view("corner_vs_centre", A, 0.3) end) end)
        add(function() view("corner_vs_centre_settled", A, 3) end)
        -- 3. weak hits add up on a large window
        add(function() clear() local e = pane(A + Vector(0, 0, 30), "annealed", 256, 128)
            timer.Simple(0.5, function() for i = 1, 12 do timer.Simple(i * 0.08, function() if IsValid(e) then shoot(point(e, -20, 10), 8) end end) end
                timer.Simple(1.2, function() say("weak hits: 12 x 8 damage, pane valid %s", tostring(IsValid(e))) view("weak_hits", A + Vector(0, 0, 30), 0.3) end) end) end)
        -- 4. a thrown prop, 5. a thrown ragdoll
        add(function() clear() pane(A) timer.Simple(0.5, function() local p = throw("models/props_c17/oildrum001.mdl", "prop_physics", A + Vector(90, 0, 0), Vector(-700, 0, 40))
            say("prop thrown, mass %.1f", p:GetPhysicsObject():GetMass()) view("prop_physics", A, 0.6) end) end)
        add(function() clear() pane(A) timer.Simple(0.5, function() throw("models/Humans/Group01/male_07.mdl", "prop_ragdoll", A + Vector(90, 0, 0), Vector(-650, 0, 40))
            say("ragdoll thrown") view("prop_ragdoll", A, 0.6) end) end)
        -- 6. walking into a pane leaves it whole, 7. running into one breaks it: the player's own movement,
        -- forward held (and sprint for the run) from 160 units away, facing the pane
        local function walk(label, sprint)
            add(function() clear() local e = pane(A + Vector(0, 0, -16), "annealed", 64, 96)
                local id = S.byEntity[e] and S.byEntity[e].id
                owner:SetPos(Vector(A.x + 160, A.y, ORIGIN.z)) owner:SetEyeAngles(Angle(0, 180, 0)) owner:SetVelocity(-owner:GetVelocity())
                owner.NLGlassQASpeed = 0
                owner:SetNW2Bool("nlglass_qa_sprint", sprint) owner:SetNW2Float("nlglass_qa_move_until", CurTime() + 1.6)
                -- annealed glass keeps its frame after a breakout: count impacts and the glass left, not only the entity
                timer.Simple(1.7, function() say("%s: pane valid %s, impacts %d, glass left %.0f%%, speed reached %.0f", label, tostring(IsValid(e)),
                    impacts[id] or 0, left(id) * 100, owner.NLGlassQASpeed or 0) view(label, A, 0.1) end)
            end, "contact")
        end
        hook.Add("Move", "nlglass_qa_speed", function(ply, mv) if ply == owner then ply.NLGlassQASpeed = math.max(ply.NLGlassQASpeed or 0, mv:GetVelocity():Length2D()) end end)
        walk("walk", false) walk("run", true)
        -- 7. an explosion, 8. tempered: rounds, then a blast, 9. a scripted break
        add(function() clear() pane(A) timer.Simple(0.5, function() util.BlastDamage(owner, owner, A + Vector(40, 10, 0), 200, 120) say("blast") view("blast", A, 0.4) end) end)
        add(function() clear() local e = pane(A, "tempered") steps.e = e
            timer.Simple(0.5, function() for i = 1, 4 do shoot(point(e, -10 + i, 6), 15) end say("tempered rounds, pane valid %s", tostring(IsValid(e))) view("tempered_rounds", A, 0.4) end) end)
        add(function() util.BlastDamage(owner, owner, A + Vector(40, 0, 0), 120, 150) say("tempered blast") view("tempered_blast", A, 0.35) end)
        add(function() clear() local e = pane(A) timer.Simple(0.5, function() e:Fire("Break") say("scripted") view("scripted", A, 0.6) end) end)
        -- 10. performance: 50 panes broken by blasts; the client measures frame times before, falling, settled
        local eye, look = ORIGIN + Vector(0, 0, 80), ORIGIN + Vector(-400, 0, 20)
        add(function() clear() owner:SetPos(ORIGIN) owner:SetEyeAngles(Angle(10, 180, 0)) send("perf_empty", eye, look, 6) end)
        add(function()
            local list = {}
            for i = 0, 9 do for j = 0, 4 do list[#list + 1] = pane(ORIGIN + Vector(-300 - j * 70, -360 + i * 80, 52)) end end
            timer.Simple(1, function()
                for k, e in ipairs(list) do timer.Simple(k * 0.03, function() if IsValid(e) then util.BlastDamage(owner, owner, e:GetPos() + Vector(30, 0, 0), 90, 200) end end) end
                say("perf: %d panes broken", #list) send("perf_falling", eye, look, 4)
            end)
        end)
        add(function() send("perf_settled", eye, look, 15) end)
    end
    -- the performance scene with the old system (Glass-Rewrite-Remix, in the package before G1): the same 50
    -- 96x64 panes, built the way its map replacement builds one, and the same blasts; only for the baseline
    local function old()
        local eye, look = ORIGIN + Vector(0, 0, 80), ORIGIN + Vector(-400, 0, 20)
        local function shards() return #ents.FindByClass("procedural_shard") end
        add(function() owner:SetPos(ORIGIN) owner:SetEyeAngles(Angle(10, 180, 0)) send("old_empty", eye, look, 6) end)
        add(function()
            local list, cube = {}, "models/hunter/blocks/cube025x025x025.mdl"
            for i = 0, 9 do for j = 0, 4 do
                local b = ents.Create("procedural_shard")
                b:SetPhysModel(cube) b:SetPhysScale(Vector(1, 48, 32) / 5.90625)
                b:SetPos(ORIGIN + Vector(-300 - j * 70, -360 + i * 80, 52)) b:SetAngles(angle_zero) b:Spawn()
                b:BuildCollision(util.GetModelMeshes(cube)[1].triangles)
                if IsValid(b:GetPhysicsObject()) then b:GetPhysicsObject():EnableMotion(false) end
                list[#list + 1] = b
            end end
            timer.Simple(1, function()
                for k, e in ipairs(list) do timer.Simple(k * 0.03, function() if IsValid(e) then util.BlastDamage(owner, owner, e:GetPos() + Vector(30, 0, 0), 90, 200) end end) end
                say("old: %d panes broken", #list) send("old_falling", eye, look, 4)
                timer.Simple(4, function() say("old falling: %d shard entities", shards()) end)
            end)
        end)
        add(function() send("old_settled", eye, look, 15) timer.Simple(15, function() say("old settled: %d shard entities", shards()) end) end)
    end
    -- R7-C: deliberately large client pieces distinguish follow-up fracture from merely moving
    -- minimum-size G1 tiles. They use the real public manager/Jolt path, never a forced native split.
    local function interact()
        local A = ORIGIN + Vector(-220, 0, 2)
        local function fixture(kind)
            clear()
            owner:SetPos(ORIGIN) owner:SetEyeAngles(Angle(0, 180, 0))
            net.Start(NET_FIXTURE) net.WriteString(kind) net.WriteVector(A) net.Send(owner)
            if NLGlass.Bullets then NLGlass.Bullets.Mark(A, 768) end
        end
        add(function()
            clear();local e = pane(A + Vector(0, 0, 50))
            timer.Simple(.5, function() shoot(e:GetPos(), 400) view("interact_real_pane", A, 3) end)
        end)
        add(function()
            shoot(A, 40, A + Vector(0, 0, 120))
            say("real pane follow-up: forwarded rays %s (no client fixture interest was registered)", tostring(NLGlass.Bullets and NLGlass.Bullets.sent))
            view("interact_real_followup", A, 1)
        end)
        -- Empty traversal gives a Source movement control for the identical walk through the pile.
        local function walk(label, kind, sprint)
            add(function() fixture(kind);view(label .. "_before", A, 2.5) end)
            add(function()
                owner:SetPos(Vector(A.x + 110, A.y, ORIGIN.z)) owner:SetVelocity(-owner:GetVelocity())
                owner:SetEyeAngles(Angle(0, 180, 0));owner.NLGlassQASpeed = 0
                local health = owner:Health()
                owner:SetNW2Bool("nlglass_qa_sprint", sprint) owner:SetNW2Float("nlglass_qa_move_until", CurTime() + 1.3)
                timer.Simple(1.4, function()
                    say("%s: Source x %.2f, passed %s, peak speed %.1f, health %d -> %d", label, owner:GetPos().x,
                        tostring(owner:GetPos().x < A.x - 60), owner.NLGlassQASpeed or 0, health, owner:Health())
                    view(label, A, .1)
                end)
            end)
        end
        hook.Add("Move", "nlglass_qa_speed", function(ply, mv)
            if ply == owner then ply.NLGlassQASpeed = math.max(ply.NLGlassQASpeed or 0, mv:GetVelocity():Length2D()) end
        end)
        walk("interact_empty_walk", "empty", false)
        walk("interact_walk", "pile", false)
        walk("interact_run", "pile", true)
        add(function() fixture("slab");view("interact_ragdoll_before", A, 2.5) end)
        add(function()
            throw("models/Humans/Group01/male_07.mdl", "prop_ragdoll", A + Vector(0, 0, 150), Vector(0, 0, -120))
            say("ragdoll dropped onto a settled slab");view("interact_ragdoll", A, 2)
        end)
        add(function() fixture("pile");view("interact_prop_before", A, 2.5) end)
        add(function()
            -- From just above the ground: A is the pane centre's height, so a drum thrown from there flew over the pile.
            local p = throw("models/props_c17/oildrum001.mdl", "prop_physics", Vector(A.x + 140, A.y, ORIGIN.z + 30), Vector(-650, 0, -60))
            say("prop sent onto the pile, Source mass %.1f", p:GetPhysicsObject():GetMass());view("interact_prop", A, 1.3)
        end)
        add(function() fixture("slab");view("interact_bullet_before", A, 2.5) end)
        add(function()
            shoot(A, 40, A + Vector(0, 0, 120));say("one real Source bullet down into the local slab")
            view("interact_bullet", A, .8)
        end)
        add(function() fixture("slab");view("interact_blast_before", A, 2.5) end)
        add(function()
            -- A damageable Source prop away from the slab supplies the engine's blast callback.
            local anchor = throw("models/props_c17/oildrum001.mdl", "prop_physics", A + Vector(0, 150, 32), vector_origin)
            anchor:GetPhysicsObject():EnableMotion(false)
            util.BlastDamage(owner, owner, A + Vector(0, 0, 24), 260, 150)
            say("real Source blast, damageable witness prop 150 units away");view("interact_blast", A, 1.3)
        end)
        add(function() fixture("fall");say("large local slab falling 256 units, no applied damage")
            view("interact_fall", A + Vector(0, 0, 70), 2) end)
        add(function() view("interact_fall_settled", A, 3) end)
        add(function()
            fixture("empty")
            say("interaction cleanup: fixtures removed; compare field falling/settled cost with G1 run 10")
            view("interact_cleanup", A, .2)
        end)
    end
    local function r8()
        local A=ORIGIN+Vector(-220,0,2)
        local savedWeapon=IsValid(owner:GetActiveWeapon()) and owner:GetActiveWeapon():GetClass()
        local function option(kind)
            net.Start(NET_FIXTURE);net.WriteString(kind);net.WriteVector(A);net.Send(owner)
        end
        local function fixture(kind) clear();option(kind);owner:SetPos(ORIGIN) end
        local function attack(class,label)
            owner:Give(class);owner:SelectWeapon(class)
            if class=="weapon_pistol" then owner:GiveAmmo(60,"Pistol",true)
            elseif class=="weapon_smg1" then owner:GiveAmmo(120,"SMG1",true) end
            owner:SetPos(Vector(A.x+8,A.y,ORIGIN.z));owner:SetVelocity(-owner:GetVelocity())
            local angle=(A+Vector(10,10,0)-owner:GetShootPos()):Angle()
            owner:SetEyeAngles(angle)
            -- After the weapon's deploy animation (a pistol cannot fire for about a second after SelectWeapon).
            timer.Simple(1.5,function()
                local beforeHits,beforeMelee=NLGlass.Bullets.sent,NLGlass.Melee.sent
                owner:SetNW2Angle("nlglass_qa_attack_angle",angle)
                owner:SetNW2Float("nlglass_qa_attack_until",CurTime()+.4)
                say("%s: real %s input",label,class)
                timer.Simple(.6,function() say("%s: forwarded hit delta %d, melee delta %d",label,
                    NLGlass.Bullets.sent-beforeHits,NLGlass.Melee.sent-beforeMelee)end)
                view(label,A,1.5)
            end)
        end
        add(function() option("r8_defaults");fixture("slab");view("r8_old_pile_before",A,61) end)
        add(function() attack("weapon_pistol","r8_pistol_60s") end)
        add(function() attack("weapon_smg1","r8_smg_60s") end)
        add(function() fixture("slab");view("r8_crowbar_before",A,3) end)
        add(function() attack("weapon_crowbar","r8_crowbar") end)
        local function walk(label,players)
            add(function() option(players and "r8_players" or "r8_defaults");fixture("pile");view(label.."_before",A,3) end)
            add(function()
                owner:SetPos(Vector(A.x+110,A.y,ORIGIN.z));owner:SetVelocity(-owner:GetVelocity());owner:SetEyeAngles(Angle(0,180,0))
                local health=owner:Health();owner:SetNW2Bool("nlglass_qa_sprint",false)
                owner:SetNW2Float("nlglass_qa_move_until",CurTime()+1.3)
                timer.Simple(1.4,function()
                    say("%s: Source x %.2f health %d -> %d, players %s",label,owner:GetPos().x,health,owner:Health(),tostring(players))
                    view(label,A,.2)
                end)
            end)
        end
        walk("r8_default_walk",false);walk("r8_players_walk",true)
        add(function() option("r8_restore");fixture("empty");if savedWeapon then owner:SelectWeapon(savedWeapon) end
            view("r8_cleanup",A,.3) end)
    end
    local function map()
        local panes = {}
        for _, e in ipairs(ents.FindByClass("func_breakable")) do
            local o = e:GetPhysicsObject()
            if IsValid(o) and o:GetMaterial() == "glass" then panes[#panes + 1] = e end
        end
        local start = owner:GetPos()
        table.sort(panes, function(a, b) return a:WorldSpaceCenter():DistToSqr(start) < b:WorldSpaceCenter():DistToSqr(start) end)
        say("map: %d native glass panes", #panes)
        local function frame(e)
            local mins, maxs = e:OBBMins(), e:OBBMaxs() local size = maxs - mins
            local axis = (size.x <= size.y and size.x <= size.z) and Vector(1, 0, 0) or (size.y <= size.z and Vector(0, 1, 0) or Vector(0, 0, 1))
            local center = e:WorldSpaceCenter()
            if axis:Dot(start - center) < 0 then axis = -axis end
            return center, axis
        end
        local a, b = panes[1], panes[2]
        if not IsValid(a) then return end
        local c, n = frame(a)
        local stand = c + n * 90 local ground = util.TraceLine({start = stand, endpos = stand - Vector(0, 0, 200), mask = MASK_PLAYERSOLID_BRUSHONLY})
        add(function() owner:SetPos(ground.HitPos) owner:SetEyeAngles((c - (ground.HitPos + Vector(0, 0, 64))):Angle())
            timer.Simple(0.5, function() shoot(c + Vector(0, 0, 6), 15, c + n * 60) say("map round 1, pane valid %s", tostring(IsValid(a))) send("map_crack", c + n * 110, c, 0.5) end) end)
        add(function() for i = 1, 8 do timer.Simple(i * 0.15, function() if IsValid(a) then shoot(c + Vector(0, 0, 6 - i), 15, c + n * 60) end end) end
            timer.Simple(1.5, function() say("map rounds, pane valid %s", tostring(IsValid(a))) send("map_break", c + n * 110, c, 0.3) end) end)
        add(function() send("map_settled", c + n * 110, c, 3) end)
        if IsValid(b) then
            local c2, n2 = frame(b)
            add(function() throw("models/Humans/Group01/male_07.mdl", "prop_ragdoll", c2 + n2 * 80, -n2 * 650 + Vector(0, 0, 40))
                timer.Simple(1, function() say("map ragdoll, pane valid %s", tostring(IsValid(b))) end) send("map_ragdoll", c2 + n2 * 120, c2, 1.2) end)
        end
    end
    local function nextStep()
        index = index + 1
        local fn = steps[index]
        if not fn then clear() say("done") net.Start(NET_VIEW) net.WriteString("") net.WriteVector(vector_origin) net.WriteAngle(angle_zero) net.WriteFloat(0) net.Send(owner) return end
        local ok, err = pcall(fn) if not ok then say("step %d failed: %s", index, tostring(err)) nextStep() end
    end
    net.Receive(NET_NEXT, function(_, ply) if ply == owner then timer.Simple(0.2, nextStep) end end)
    concommand.Add("nlglass_qa", function(ply, _, args)
        if IsValid(ply) and not ply:IsListenServerHost() then return end
        owner = IsValid(ply) and ply or player.GetAll()[1]
        if not IsValid(owner) then return end
        if args[1] and args[1]:match("^r9") and NLGlassR9QA then NLGlassR9QA.Run(owner,args);return end
        steps, tags, index = {}, {}, 0
        watch()
        if args[1] == "map" then map() elseif args[1] == "old" then old() elseif args[1] == "interact" then interact() elseif args[1]=="r8" then r8()
        else owner:SetPos(ORIGIN) owner:SetEyeAngles(Angle(0, 180, 0)) field() end
        if args[1] == "contact" then -- only the walk and run steps
            local only = {} for i, fn in ipairs(steps) do if tags[i] == "contact" then only[#only + 1] = fn end end steps = only
        end
        say("start %s, %d steps", args[1] or "field", #steps) timer.Simple(1, nextStep)
    end)
    return
end
-- client: frame the step, report the broken-glass manager, measure frame times, print NL_SHOT
local camera, frames, savedR8
net.Receive(NET_FIXTURE, function()
    local kind, at = net.ReadString(), net.ReadVector()
    local d = NLGlassDebris
    if not d then print("NL_QA interaction fixture FAILED: missing manager");return end
    if kind:match("^r8_") then
        if kind=="r8_restore" then
            if savedR8 then for name,value in pairs(savedR8)do RunConsoleCommand(name,tostring(value))end;savedR8=nil end
        else
            if not savedR8 then
                savedR8={};for _,name in ipairs({"rtx_glass_debris_collide_with","rtx_glass_debris_interact","rtx_glass_debris_lifetime"})do
                    local cv=GetConVar(name);savedR8[name]=cv and cv:GetFloat() or 0
                end
                print(string.format("NL_QA r8 saved flags %s interact %s lifetime %s",tostring(savedR8.rtx_glass_debris_collide_with),
                    tostring(savedR8.rtx_glass_debris_interact),tostring(savedR8.rtx_glass_debris_lifetime)))
            end
            RunConsoleCommand("rtx_glass_debris_collide_with",kind=="r8_players" and "7" or "3")
            RunConsoleCommand("rtx_glass_debris_interact","1");RunConsoleCommand("rtx_glass_debris_lifetime","180")
        end
        return
    end
    d.Clear()
    local list = {}
    local function piece(x, y, width, height)
        list[#list + 1] = {poly = {{x - width / 2, y - height / 2}, {x + width / 2, y - height / 2},
            {x + width / 2, y + height / 2}, {x - width / 2, y + height / 2}}, thickness = .5,
            velocity = vector_origin, spin = vector_origin, seed = #list + 1}
    end
    if kind == "pile" then for x = -1, 1 do for y = -1, 1 do piece(x * 34, y * 34, 32, 32) end end
    elseif kind == "slab" or kind == "fall" then piece(0, 0, 96, 64) end
    if #list > 0 then
        d.Spawn({origin = at + Vector(0, 0, kind == "fall" and 256 or 8), angles = angle_zero,
            material = "models/props_combine/health_charger_glass", color = Color(255, 255, 255)}, list)
    end
    print("NL_QA interaction fixture " .. kind .. " pieces " .. #list .. " | requires interact=1, piece_size=8, Jolt")
end)
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
    local function f(v) return type(v) == "number" and string.format("%.2f", v) or tostring(v) end
    print(string.format("NL_QA client %s backend %s live %s moving %s sleeping %s batches %s frames %d mean_ms %.2f p99_ms %.2f" ..
        " | manager think_ms %s draw_ms %s think_peak %s draw_peak %s draws %s culled %s rebuild_peak %s" ..
        " | jolt step_ms %s awake %s brushes %s skipped %s refused %s statics %s models %s",
        label, d and d.Backend() or "missing", tostring(s.live), tostring(s.moving), tostring(s.sleeping), tostring(s.batches),
        #times, mean * 1000, p99 * 1000, f(s.think_ms), f(s.draw_ms), f(s.think_peak_ms), f(s.draw_peak_ms),
        f(s.draw_calls_avg), tostring(s.culled_pieces), f(s.rebuild_peak_ms),
        f(n.step_ms), tostring(n.awake), tostring(n.brushes), tostring(n.skipped_brushes),
        tostring(n.refused_brushes), tostring(n.statics), tostring(n.models)))
    print(string.format("NL_QA interaction %s enabled %s available %s mirrors %s candidates %s queries %s capture_ms %s" ..
        " capture_peak %s split_ms %s split_peak %s splits %s bullet %s blast %s body %s fall %s pending %s rays %s ray_hits %s dropped %s/%s/%s",
        label, tostring(s.interaction), tostring(s.interaction_available), tostring(s.scene_bodies), tostring(s.scene_candidates),
        tostring(s.scene_queries), f(s.capture_ms), f(s.capture_peak_ms), f(s.split_ms), f(s.split_peak_ms), tostring(s.splits), tostring(s.splits_bullet),
        tostring(s.splits_blast), tostring(s.splits_body), tostring(s.splits_fall), tostring(s.damage_pending),
        tostring(s.ray_pending), tostring(n.ray_hits), tostring(s.damage_dropped), tostring(s.rays_dropped), tostring(n.damage_dropped)))
    print(string.format("NL_QA fast bodies %s peak %s boxes %s candidates %s examined %s sweeps %s hits %s limited %s",
        tostring(s.scene_fast_bodies), tostring(s.scene_peak_bodies), tostring(s.scene_fast_boxes),
        tostring(s.scene_fast_candidates), tostring(s.scene_examined), tostring(n.scene_sweeps),
        tostring(n.scene_sweep_hits), tostring(n.scene_sweep_limited)))
    print(string.format("NL_QA r8 %s flags %s fragments %s queued %s queued_fragments %s created %s creation_ms %s creation_peak %s grouped %s melee_hits %s melee_splits %s melee_limited %s retired %s released %s",
        label,tostring(s.collision_flags),tostring(s.fragments),tostring(s.creation_pending),tostring(s.creation_fragments),
        tostring(s.created_last),f(s.creation_ms),f(s.creation_peak_ms),tostring(s.grouped_fragments),tostring(n.melee_hits),
        tostring(s.splits_melee),tostring(n.melee_limited),tostring(s.retired_individual),tostring(s.released_individual)))
end
local pending
net.Receive(NET_VIEW, function()
    local label, origin, angles, delay = net.ReadString(), net.ReadVector(), net.ReadAngle(), net.ReadFloat()
    if label == "" then camera = nil print("NL_SHOT_DONE") return end
    camera = {origin, angles} frames = {} pending = label
    timer.Simple(delay, function() stats(label) print("NL_SHOT " .. label) end)
end)
concommand.Add("nl_shot_taken", function() if pending then pending = nil net.Start(NET_NEXT) net.SendToServer() end end)
