-- PoC-only shared acceptance driver, copied into a temporary local add-on by the R20-C session.
-- Never packaged. Uses actual stock weapons and engine blood dispatch, not synthetic effect calls.+AddCSLuaFile()
if SERVER then
    game.ConsoleCommand("sv_cheats 1\nsv_allowcslua 1\nai_disabled 1\nhost_timescale 1\n")
    if R20C_QA_MODE and R20C_QA_MODE:find("probe",1,true) then AddCSLuaFile("r20c_hud.lua") end
    local target, armed, label
    local models = { npc_citizen = "models/Humans/Group01/male_07.mdl",
        npc_combine_s = "models/combine_soldier.mdl", npc_zombie = "models/zombie/classic.mdl",
        npc_antlion = "models/antlion.mdl", prop_ragdoll = "models/Humans/Group01/male_07.mdl" }
    local function human() return player.GetHumans()[1] end
    local function aim_point(ent)
        local bone=ent:LookupBone("ValveBiped.Bip01_Spine2")
        if bone then local pos=ent:GetBonePosition(bone) if pos then return pos end end
        return ent:WorldSpaceCenter()
    end
    concommand.Add("r20c_spawn", function(_, _, args)
        if IsValid(target) then if target:IsPlayer() then target:Kick("R20-C fixture complete") else target:Remove() end end
        local class = args[1]
        local p = human()
        p:GodEnable() p:SetPos(Vector(-420, -500, -143)) p:Give("weapon_pistol")
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
        p:SetEyeAngles((aim_point(target) - p:EyePos()):Angle())
        local blood_colour=target:GetBloodColor() -- ragdolls can return zero Lua results, not one nil result
        print("R20C_TARGET " .. class .. " " .. target:EntIndex() .. " blood=" .. tostring(blood_colour))
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
        p:SetEyeAngles((aim_point(target)-p:EyePos()):Angle())
        p:ViewPunchReset()
        timer.Simple(.6,function()
            if not IsValid(target) then return end
            local w=p:GetActiveWeapon() if IsValid(w) then w:SetClip1(30) w:SetNextPrimaryFire(CurTime()) end
            label,armed=args[2],true
            game.ConsoleCommand("host_timescale 0.03\n")
            p:ConCommand("+attack")
        end)
    end)
    concommand.Add("r20c_colour",function(_,_,args)
        local code=tonumber(args[1])
        if IsValid(target) and ({[0]=true,[1]=true,[2]=true,[4]=true,[5]=true,[6]=true})[code] then target:SetBloodColor(code) end
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
        npc:SetPos(Vector(-650,-560,-143)) npc:Spawn()
        if IsValid(target) then
            npc:FireBullets({Src=npc:EyePos(),Dir=(target:WorldSpaceCenter()-npc:EyePos()):GetNormalized(),
                Spread=Vector(0,0,0),Num=1,Damage=10,AmmoType="Pistol"})
        end
        timer.Simple(.2,function() if IsValid(npc) then npc:Remove() end end)
    end)
    return
end

hook.Add("InitPostEntity","r20c",function()
    print("R20C_CATEGORY_START "..util.TableToJSON({guard=NativeLoaderRenderGuard~=nil,observer=NativeLoaderEffectCategories~=nil}))
    local emitter=FindMetaTable("CLuaEmitter")
    if emitter and emitter.Add then
        local original,sampled=emitter.Add,0
        emitter.Add=function(self,mat,pos,...)
            local p=original(self,mat,pos,...)
            local name=isstring(mat) and mat or mat:GetName()
            if p and sampled<8 and name:find("nlfluid_",1,true) then
                sampled=sampled+1
                local began=Vector(pos.x,pos.y,pos.z)
                timer.Simple(.3,function()
                    local ok,value=pcall(function() local r,g,b=p:GetColor() return {material=name,from=began,to=p:GetPos(),velocity=p:GetVelocity(),life=p:GetLifeTime(),colour={r,g,b}} end)
                    print("R20C_PARTICLE "..tostring(ok).." "..(ok and util.TableToJSON(value) or tostring(value)))
                end)
            end
            return p
        end
    end
    for _,name in ipairs(BloodOverhaul and BloodOverhaul.RagdollImpacts and {} or {"Impact","Impact_GMOD","RagdollImpact"}) do
        local effect_name=name
        effects.Register({Init=function(_,data)
            local ent=data:GetEntity()
            print("R20C_DISPATCH "..effect_name.." "..util.TableToJSON({origin=data:GetOrigin(),start=data:GetStart(),
                normal=data:GetNormal(),scale=data:GetScale(),class=IsValid(ent) and ent:GetClass() or false,
                surface=data:GetSurfaceProp(),damage=data:GetDamageType()}))
            util.Effect(effect_name,data,false)
        end,Think=function() return false end,Render=function() end},effect_name)
    end
    timer.Simple(16,function()
        local BO=BloodOverhaul
        if not BO or not BO.Packaged or not DTScreen then print("R20C_ERROR missing_parts") print("NL_SHOT_DONE") return end
        local saved={}
        for _,key in ipairs({"cl_drawhud","r_drawviewmodel","nativeloader_blood_impacts","nativeloader_blood_amount",
            "bloodoverhaul_enable","bloodoverhaul_scheme","dts_enabled","bloodoverhaul_red_r","bloodoverhaul_red_g","bloodoverhaul_red_b",
            "bloodoverhaul_alien_r","bloodoverhaul_alien_g","bloodoverhaul_alien_b"}) do
            local cv=GetConVar(key) if cv then saved[key]=cv:GetString() end
        end
        RunConsoleCommand("cl_drawhud","0") RunConsoleCommand("r_drawviewmodel","0")
        RunConsoleCommand("bloodoverhaul_enable","1") RunConsoleCommand("nativeloader_blood_amount","1")
        RunConsoleCommand("bloodoverhaul_scheme","realistic")
        local function emit(name,value) print("R20C_"..name.." "..util.TableToJSON(value)) end
        local mat=BO.ParticleMaterial(0,1,false)
        local tex=mat:GetTexture("$basetexture")
        emit("MATERIAL",{name=mat:GetName(),shader=mat:GetShader(),texture=tex and tex:GetName(),
            width=tex and tex:Width(),height=tex and tex:Height(),tint=mat:GetVector("$color"),
            particles=GetConVar("r_drawparticles") and GetConVar("r_drawparticles"):GetString(),
            world_valid=IsValid(game.GetWorld())})
        local function close_dialogs()
            for _,panel in ipairs(vgui.GetWorldPanel():GetChildren()) do
                if panel~=g_SpawnMenu and panel~=g_ContextMenu and IsValid(panel) and panel.GetTitle and panel.Close then panel:Close() end
            end
        end
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
        add(function()
            local neutral=CreateMaterial("r20c_neutral_drop","UnlitGeneric",{["$basetexture"]="particle/nlfluid/drop",
                ["$translucent"]="1",["$vertexcolor"]="1",["$vertexalpha"]="1"})
            local sprite=CreateMaterial("r20c_sprite_drop","Sprite",{["$basetexture"]="particle/nlfluid/drop",
                ["$translucent"]="1",["$vertexcolor"]="1",["$vertexalpha"]="1",["$spriteorientation"]="vp_parallel"})
            local tinted=CreateMaterial("r20c_sprite_red","Sprite",{["$basetexture"]="particle/nlfluid/drop",
                ["$translucent"]="1",["$vertexcolor"]="1",["$vertexalpha"]="1",["$spriteorientation"]="vp_parallel"})
            tinted:SetVector("$color",Vector(.588,.063,.055))
            local entries={{"sprites/light_glow02_add",false},{"effects/blood_drop",false},
                {BO.ParticleMaterial(0,1,false),true},{BO.ParticleMaterial(0,1,false),false},{neutral,false},{sprite,false},{tinted,false}}
            local emitter=ParticleEmitter(Vector(-250,-500,-75))
            for i,entry in ipairs(entries) do
                local p=emitter:Add(entry[1],Vector(-250,-565+i*20,-75))
                if p then
                    p:SetVelocity(Vector(0,0,0)) p:SetGravity(Vector(0,0,0)) p:SetDieTime(3)
                    p:SetStartSize(8) p:SetEndSize(8) p:SetStartAlpha(255) p:SetEndAlpha(255)
                    p:SetColor(255,255,255) p:SetLighting(entry[2])
                end
            end
            emitter:Finish()
            timer.Simple(1.2,function()
                if NativeLoaderEffectCategories then NativeLoaderEffectCategories.Status() end
                print("NL_SHOT material_diagnostic")
            end)
        end)
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
                if scheme=="custom" then
                    RunConsoleCommand("bloodoverhaul_red_r","20") RunConsoleCommand("bloodoverhaul_red_g","230") RunConsoleCommand("bloodoverhaul_red_b","110")
                end
                RunConsoleCommand("r20c_spawn","npc_citizen")
                timer.Simple(.9,function() RunConsoleCommand("r20c_fire","weapon_pistol","scheme_"..scheme) end)
            end)
        end
        for _,code in ipairs({1,2,6}) do
            add(function()
                RunConsoleCommand("bloodoverhaul_scheme","realistic") RunConsoleCommand("r20c_spawn","npc_citizen")
                timer.Simple(.5,function() RunConsoleCommand("r20c_colour",tostring(code)) end)
                timer.Simple(.9,function() RunConsoleCommand("r20c_fire","weapon_pistol","stock_colour_"..code) end)
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
                if NativeLoaderEffectCategories then NativeLoaderEffectCategories.Status() end
                print("NL_SHOT many_hits")
            end)
        end)
        local panel_ids={"bloodoverhaul_settings","dynamic_toolgun_screen"}
        if file.Exists("autorun/client/nativeloader_menu.lua","LUA") then panel_ids[#panel_ids+1]="nativeloader_toolgun" end
        for _,panel in ipairs(panel_ids) do
            add(function()
                inspect()
                if not IsValid(g_SpawnMenu) then print("R20C_ERROR no_spawnmenu") print("NL_SHOT panel_missing") return end
                g_SpawnMenu:Open()
                spawnmenu.ActivateTool(panel)
                timer.Simple(1,function() print("NL_SHOT panel_"..panel) end)
            end)
        end
        if R20C_QA_MODE and R20C_QA_MODE:find("probe",1,true) then
            steps={steps[1],function()
                include("r20c_hud.lua")
                timer.Simple(2,function() print("NL_SHOT hud_diagnostic") end)
            end}
        else
            table.remove(steps,1) -- diagnostic shaders share the texture hash; keep them out of acceptance runs
        end
        local function next_step()
            RunConsoleCommand("r20c_resume")
            close_dialogs()
            if index>0 then emit("STEP",{index=index,stats=BO.ImpactStats}) end
            if IsValid(g_SpawnMenu) then g_SpawnMenu:Close() end
            index=index+1
            if not steps[index] then
                hook.Remove("CalcView","r20c")
                for key,value in pairs(saved) do RunConsoleCommand(key,value) end
                emit("FINAL",BO.ImpactStats)
                RunConsoleCommand("nativeloader_blood_status")
                concommand.Add("nl_shot_taken",function() RunConsoleCommand("r20c_resume") end)
                -- Leave a short diagnostic window before the session driver performs its normal
                -- settings restoration/quit. Any extra probes still run under this session's lock.
                timer.Simple(R20C_QA_MODE and R20C_QA_MODE:find("probe",1,true) and 90 or 35,function() print("NL_SHOT_DONE") end)
                return
            end
            timer.Simple(.3,steps[index])
        end
        concommand.Add("nl_shot_taken",next_step)
        emit("READY",{shapes=#BO.Shapes,schemes=#BO.Schemes,dts=DTScreen.Version,
            singleplayer=game.SinglePlayer(),remix=RemixMaterial~=nil})
        next_step()
    end)
end)
