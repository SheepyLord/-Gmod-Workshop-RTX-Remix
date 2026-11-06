-- PoC-only shared acceptance driver, copied into a temporary local add-on by the R20-C session.
-- Never packaged. Uses actual stock weapons and engine blood dispatch, not synthetic effect calls.+AddCSLuaFile()
if SERVER then
    local target, armed, label
    local models = { npc_citizen = "models/Humans/Group01/male_07.mdl",
        npc_combine_s = "models/combine_soldier.mdl", npc_zombie = "models/zombie/classic.mdl",
        npc_antlion = "models/antlion.mdl", prop_ragdoll = "models/Humans/Group01/male_07.mdl" }
    local function human() return player.GetHumans()[1] end
    concommand.Add("r20c_spawn", function(_, _, args)
        if IsValid(target) then if target:IsPlayer() then target:Kick("R20-C fixture complete") else target:Remove() end end
        local class = args[1]
        local p = human()
        p:GodEnable() p:SetPos(Vector(-650, -500, -143)) p:Give("weapon_pistol")
        p:SetAmmo(999, "Pistol") p:SetAmmo(999, "Buckshot") p:SetAmmo(999, "AR2")
        if class == "player" then
            target = player.CreateNextBot("R20C blood target")
            if not IsValid(target) then print("R20C_SKIP player_no_slot") return end
        else
            target = ents.Create(class)
            if not IsValid(target) then print("R20C_ERROR no_target " .. tostring(class)) return end
            target:SetModel(models[class])
        end
        target:SetPos(Vector(-200, -500, -143)) target:SetAngles(Angle(0, 180, 0))
        if not target:IsPlayer() then target:Spawn() target:Activate() end
        target:SetHealth(100000) target:SetNWBool("r20c_target", true)
        if class == "prop_ragdoll" then
            target:SetBloodColor(BLOOD_COLOR_RED)
            for i=0,target:GetPhysicsObjectCount()-1 do
                local phys=target:GetPhysicsObjectNum(i) if IsValid(phys) then phys:EnableMotion(false) end
            end
        end
        p:SetEyeAngles((target:WorldSpaceCenter() - p:EyePos()):Angle())
        print("R20C_TARGET " .. class .. " " .. target:EntIndex() .. " blood=" .. target:GetBloodColor())
    end)
    concommand.Add("r20c_resume", function()
        game.ConsoleCommand("host_timescale 1\n")
        local p=human() if IsValid(p) then p:ConCommand("-attack") end
    end)
    concommand.Add("r20c_fire", function(_,_,args)
        local p=human()
        if not IsValid(target) then print("R20C_ERROR missing_target") return end
        local weapon = args[1]
        p:Give(weapon) p:SelectWeapon(weapon)
        p:SetEyeAngles((target:WorldSpaceCenter()-p:EyePos()):Angle())
        timer.Simple(.6,function()
            if not IsValid(target) then return end
            local w=p:GetActiveWeapon() if IsValid(w) then w:SetClip1(30) w:SetNextPrimaryFire(CurTime()) end
            label,armed=args[2],true
            game.ConsoleCommand("host_timescale 0.03\n")
            p:ConCommand("+attack")
        end)
    end)
    hook.Add("PostEntityFireBullets","r20c",function(ent,data)
        if ent~=human() or not armed then return end
        armed=false
        print("R20C_BULLET "..label.." hit="..tostring(data.Trace and data.Trace.Hit).." entity="..
            tostring(data.Trace and IsValid(data.Trace.Entity) and data.Trace.Entity:GetClass()))
        local shot=label
        timer.Simple(.008,function() print("NL_SHOT "..shot) end)
    end)
    concommand.Add("r20c_remote",function()
        local npc=ents.Create("npc_citizen") npc:SetModel(models.npc_citizen)
        npc:SetPos(Vector(-650,-500,-143)) npc:Spawn()
        if IsValid(target) then
            npc:FireBullets({Src=npc:EyePos(),Dir=(target:WorldSpaceCenter()-npc:EyePos()):GetNormalized(),
                Spread=Vector(0,0,0),Num=1,Damage=10,AmmoType="Pistol"})
        end
        timer.Simple(.2,function() if IsValid(npc) then npc:Remove() end end)
    end)
    return
end

hook.Add("InitPostEntity","r20c",function()
    timer.Simple(16,function()
        local BO=BloodOverhaul
        if not BO or not BO.Packaged or not DTScreen then print("R20C_ERROR missing_parts") print("NL_SHOT_DONE") return end
        local saved={}
        for _,key in ipairs({"cl_drawhud","r_drawviewmodel","nativeloader_blood_impacts","nativeloader_blood_amount",
            "bloodoverhaul_enable","bloodoverhaul_scheme","dts_enabled"}) do
            local cv=GetConVar(key) if cv then saved[key]=cv:GetString() end
        end
        RunConsoleCommand("cl_drawhud","0") RunConsoleCommand("r_drawviewmodel","0")
        RunConsoleCommand("bloodoverhaul_enable","1") RunConsoleCommand("nativeloader_blood_amount","1")
        RunConsoleCommand("bloodoverhaul_scheme","realistic")
        local function emit(name,value) print("R20C_"..name.." "..util.TableToJSON(value)) end
        local function inspect()
            local out={blood=0,screen=0,legacy=0}
            for _,tab in ipairs(spawnmenu.GetTools()) do
                for _,cat in ipairs(tab.Items or {}) do
                    for _,item in ipairs(cat) do
                        if item.ItemName=="bloodoverhaul_settings" then out.blood=out.blood+1 end
                        if item.ItemName=="dynamic_toolgun_screen" then out.screen=out.screen+1 end
                        if item.ItemName=="dts_settings" then out.legacy=out.legacy+1 end
                    end
                end
            end
            emit("PANELS",out)
        end
        local focus
        hook.Add("CalcView","r20c",function()
            local ent
            for _,e in ipairs(ents.GetAll()) do if e:GetNWBool("r20c_target") then ent=e break end end
            local target=IsValid(ent) and ent:WorldSpaceCenter() or Vector(-200,-500,-100)
            return {origin=Vector(-360,-645,-55),angles=(target-Vector(-360,-645,-55)):Angle(),fov=65,drawviewer=false}
        end)
        local steps,index={},0
        local function add(fn) steps[#steps+1]=fn end
        local function shot(class,weapon,name,stock)
            add(function()
                RunConsoleCommand("nativeloader_blood_impacts",stock and "0" or "1")
                RunConsoleCommand("r20c_spawn",class)
                timer.Simple(.9,function() RunConsoleCommand("r20c_fire",weapon,name) end)
            end)
        end
        shot("npc_citizen","weapon_pistol","before_stock",true)
        for _,class in ipairs({"npc_citizen","npc_combine_s","npc_zombie","npc_antlion","prop_ragdoll"}) do
            for _,weapon in ipairs({"weapon_pistol","weapon_shotgun","weapon_ar2"}) do
                shot(class,weapon,class.."_"..weapon)
            end
        end
        if not game.SinglePlayer() then shot("player","weapon_pistol","player_pistol") end
        for _,scheme in ipairs({"blue","rainbow","custom"}) do
            add(function()
                RunConsoleCommand("bloodoverhaul_scheme",scheme)
                RunConsoleCommand("r20c_spawn","npc_citizen")
                timer.Simple(.9,function() RunConsoleCommand("r20c_fire","weapon_pistol","scheme_"..scheme) end)
            end)
        end
        add(function()
            RunConsoleCommand("bloodoverhaul_scheme","realistic")
            RunConsoleCommand("r20c_remote")
            timer.Simple(.2,function() emit("REMOTE",BO.ImpactStats) print("NL_SHOT remote_shooter") end)
        end)
        add(function()
            RunConsoleCommand("bloodoverhaul_clear")
            local frames,last,began={},SysTime(),SysTime()
            hook.Add("PostRender","r20c_perf",function()
                local now=SysTime() frames[#frames+1]=now-last last=now
                for i=1,6 do
                    local data=EffectData() data:SetOrigin(Vector(-200,-500,-100))
                    data:SetNormal(Vector(1,0,0)) data:SetColor(i%2) data:SetScale(4)
                    util.Effect("BloodImpact",data)
                end
                if now-began<4 then return end
                hook.Remove("PostRender","r20c_perf")
                table.sort(frames)
                emit("PERF",{frames=#frames,seconds=now-began,median_ms=frames[math.ceil(#frames*.5)]*1000,
                    p99_ms=frames[math.ceil(#frames*.99)]*1000,stats=BO.ImpactStats,
                    live=#BO.ImpactBudgets.particles.live,recent=#BO.ImpactBudgets.particles.recent,
                    stains=BO.ImpactBudgets.stains.total})
                print("NL_SHOT many_hits")
            end)
        end)
        for _,panel in ipairs({"bloodoverhaul_settings","dynamic_toolgun_screen","nativeloader_toolgun"}) do
            add(function()
                inspect()
                if not IsValid(g_SpawnMenu) then print("R20C_ERROR no_spawnmenu") print("NL_SHOT panel_missing") return end
                g_SpawnMenu:Open()
                spawnmenu.ActivateTool(panel)
                timer.Simple(1,function() print("NL_SHOT panel_"..panel) end)
            end)
        end
        local function next_step()
            RunConsoleCommand("r20c_resume")
            if IsValid(g_SpawnMenu) then g_SpawnMenu:Close() end
            index=index+1
            if not steps[index] then
                hook.Remove("CalcView","r20c")
                for key,value in pairs(saved) do RunConsoleCommand(key,value) end
                emit("FINAL",BO.ImpactStats)
                RunConsoleCommand("nativeloader_blood_status")
                print("NL_SHOT_DONE") return
            end
            timer.Simple(.3,steps[index])
        end
        concommand.Add("nl_shot_taken",next_step)
        emit("READY",{shapes=#BO.Shapes,schemes=#BO.Schemes,dts=DTScreen.Version,
            singleplayer=game.SinglePlayer(),remix=RemixMaterial~=nil})
        next_step()
    end)
end)
