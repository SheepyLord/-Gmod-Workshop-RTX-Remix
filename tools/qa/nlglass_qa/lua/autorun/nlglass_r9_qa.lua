-- MIT. R9 numeric QA, compatible with the saved R8 baseline as well as the new module.
local NET="nlglass_qa_r9"
local function say(format,...) print(string.format("NL_R9 "..format,...)) end
if SERVER then
    util.AddNetworkString(NET)
    NLGlassR9QA={}
    local S=NLGlass.Server
    local running,silent=false,false
    if NLGlass.Blasts then NLGlass.Blasts.Observe=function(e)
        if not running or silent then return end
        say("blast source=%s radius=%.1f damage=%.1f origin=%.1f,%.1f,%.1f sent=%d",e.source,e.radius,e.damage,e.origin.x,e.origin.y,e.origin.z,NLGlass.Blasts.sent)
    end end
    local label="idle"
    local originalDamage,originalImpact=S.Damage,S.Impact
    S.Damage=function(ent,dmg)
        local r=S.byEntity[ent] or S.surfaces[ent]
        if running and not silent and r then say("latency phase=server_damage label=%s id=%d tick=%d game=%.6f wall=%.6f",label,r.id,engine.TickCount(),CurTime(),SysTime()) end
        return originalDamage(ent,dmg)
    end
    S.Impact=function(r,impact,all)
        local start=SysTime()
        local ok,parts=originalImpact(r,impact,all)
        if running and not silent and ok then say("latency phase=server_sent label=%s id=%d tick=%d game=%.6f wall=%.6f cpu_ms=%.4f pieces=%d native=%s",
            label,r.id,engine.TickCount(),CurTime(),SysTime(),(SysTime()-start)*1000,parts and #parts or 0,tostring(r.native)) end
        return ok,parts
    end
    local origin=Vector(611,576,-91)
    local function fixture(kind,at,direction)
        net.Start(NET);net.WriteString(kind);net.WriteVector(at or origin);net.WriteVector(direction or Vector(1,0,0));net.Broadcast()
    end
    local function pane(at,kind)
        local e=ents.Create("nlglass_pane");e.NLGlassPreset={width=96,height=64,kind=kind or "annealed"}
        e:SetPos(at);e:SetAngles(Vector(0,1,0):AngleEx(Vector(1,0,0)));e:Spawn();e:Activate();return e
    end
    function NLGlassR9QA.Run(ply,args)
        if running or not IsValid(ply) or not ply:IsListenServerHost() then return end
        local mode=args[1] or "r9"
        silent=mode=="r9-perf"
        running=true
        local saved={}
        for _,name in ipairs({"rtx_glass_strength","rtx_glass_map_kind"}) do saved[name]=GetConVar(name):GetString() end
        local owned={}
        local duration=mode=="r9-latency" and 26 or mode=="r9-velocity" and 20 or mode=="r9-water" and 7 or mode=="r9-perf" and 29 or 25
        local function later(t,fn)timer.Simple(t,function()if running then fn()end end)end
        local function shot(e,damage)
            if not IsValid(e) then return end
            local at=e:GetPos();ply:FireBullets({Src=at+Vector(150,0,0),Dir=Vector(-1,0,0),Damage=damage,Force=damage*.2,Tracer=0,Spread=vector_origin})
        end
        local function clear() fixture("clear");for _,e in ipairs(owned)do if IsValid(e)then e:Remove()end end;owned={} end
        if mode=="r9-perf" then
            local base=Vector(831.235,576,-143.08)
            ply:SetPos(base);ply:SetEyeAngles(Angle(10,180,0));clear();fixture("perf_empty",base)
            later(7,function()
                local list={}
                for i=0,9 do for j=0,4 do local e=pane(base+Vector(-300-j*70,-360+i*80,52));list[#list+1]=e;owned[#owned+1]=e end end
                timer.Simple(1,function()
                    fixture("perf_falling",base)
                    for k,e in ipairs(list)do timer.Simple(k*.03,function()if IsValid(e)then util.BlastDamage(ply,ply,e:GetPos()+Vector(30,0,0),90,200)end end)end
                end)
            end)
            later(12.4,function()fixture("perf_settled",base)end)
        elseif mode=="r9-latency" then
            -- Four spawned and four real gm_construct map-window impacts, pistol/SMG energies.
            -- Map windows remain engine-owned; no early scripted shatter.
            for i=1,4 do later((i-1)*3,function()
                clear();label=i%2==1 and "spawn_pistol" or "spawn_smg"
                local e=pane(origin);owned[#owned+1]=e
                fixture("view",origin,Vector(-1,0,0))
                timer.Simple(.5,function()for n=1,(i%2==1 and 3 or 10)do shot(e,i%2==1 and 15 or 5)end end)
            end) end
            for i=1,4 do later(12+(i-1)*3,function()
                clear();label=i%2==1 and "map_pistol" or "map_smg"
                local list=ents.FindByClass("func_breakable")
                local e
                for _,candidate in ipairs(list)do local p=candidate:GetPhysicsObject()
                    if IsValid(p) and p:GetMaterial()=="glass" and not S.byEntity[candidate] then S.TrackNative(candidate)end
                    if S.byEntity[candidate] and not S.byEntity[candidate].broken then e=candidate;break end
                end
                if not e then
                    for _,r in pairs(S.records)do if r.original and not r.state.all and IsValid(r.entity) and not r.entity.NLGlassR9Used then
                        e=r.entity;e.NLGlassR9Used=true;label=label.."_surface";break
                    end end
                end
                if not e then say("latency map windows exhausted; use a fresh gm_construct session")return end
                local record=S.byEntity[e];local normal=record and record.frame.angles:Up() or Vector(0,1,0)
                local at=record and record.frame.origin or e:WorldSpaceCenter();fixture("view",at,-normal)
                timer.Simple(.5,function()
                    local count=i%2==1 and 12 or 40
                    local distance=(record and record.state.def.thickness*.5 or 1)+8
                    local from=at+normal*distance
                    local tr=util.TraceLine({start=from,endpos=at-normal*distance,mask=MASK_SHOT})
                    if tr.Entity~=e then normal=-normal;from=at+normal*distance;tr=util.TraceLine({start=from,endpos=at-normal*distance,mask=MASK_SHOT})end
                    say("map_aim id=%s class=%s hit=%s fraction=%.5f",tostring(record and record.id),e:GetClass(),IsValid(tr.Entity) and tr.Entity:GetClass() or "world",tr.Fraction)
                    for _=1,count do ply:FireBullets({Src=from,Dir=-normal,Damage=i%2==1 and 15 or 5,Force=2,Tracer=0,Spread=vector_origin})end
                end)
            end) end
        elseif mode=="r9-velocity" then
            for index,speed in ipairs({250,700,3600})do later((index-1)*4,function()
                clear();label="prop_"..speed
                local e=pane(origin);owned[#owned+1]=e
                local prop=ents.Create("prop_physics");prop:SetModel("models/props_c17/oildrum001.mdl");prop:SetPos(origin+Vector(100,0,0));prop:Spawn();owned[#owned+1]=prop
                local p=prop:GetPhysicsObject();if IsValid(p)then p:EnableGravity(false);p:SetVelocity(Vector(-speed,0,0))end
                fixture("velocity",origin,Vector(-1,0,0))
            end)end
            later(12,function()
                clear();local e=pane(origin);owned[#owned+1]=e
                ply:SetPos(origin+Vector(160,0,-52));ply:SetEyeAngles(Angle(0,180,0));ply:SetVelocity(-ply:GetVelocity())
                ply:SetNW2Bool("nlglass_qa_sprint",true);ply:SetNW2Float("nlglass_qa_move_until",CurTime()+1.6)
                fixture("velocity",origin,Vector(-1,0,0))
            end)
            later(16,function()clear();local e=pane(origin);owned[#owned+1]=e;fixture("velocity",origin,Vector(-1,0,0));timer.Simple(.5,function()shot(e,400)end)end)
        elseif mode=="r9-water" then
            clear();fixture("water",game.GetMap()=="gm_construct" and Vector(-512,4096,-128) or ply:GetPos()+Vector(0,0,40))
        else
            clear();fixture("pile",origin)
            later(5,function()
                -- No entity lies within this blast radius. Baseline sends no kick.
                ply:SetPos(origin+Vector(600,0,0));util.BlastDamage(ply,ply,origin+Vector(-35,0,0),150,120)
                say("empty_blast sent=%s",tostring(NLGlass.Blasts and NLGlass.Blasts.sent));fixture("sample",origin)
                timer.Simple(.5,function()fixture("sample",origin)end)
            end)
            later(9,function()
                local e=ents.Create("env_explosion");e:SetPos(origin+Vector(35,0,0));e:SetKeyValue("iMagnitude","120");e:SetKeyValue("iRadiusOverride","180");e:Spawn();e:Fire("Explode");owned[#owned+1]=e
                fixture("sample",origin)
                timer.Simple(.5,function()fixture("sample",origin)end)
            end)
            later(12,function()
                local e=ents.Create("npc_grenade_frag");e:SetPos(origin+Vector(0,0,10));e:Spawn();e:Fire("SetTimer","0.1");owned[#owned+1]=e
            end)
            later(15,function()
                local e=ents.Create("prop_physics");e:SetModel("models/props_c17/oildrum001_explosive.mdl");e:SetPos(origin+Vector(20,0,20));e:Spawn();owned[#owned+1]=e;e:TakeDamage(1000,ply,ply)
            end)
            later(16.5,function()
                local e=ents.Create("rpg_missile");e:SetPos(origin+Vector(0,0,40));e:SetAngles(Angle(90,0,0));e:SetOwner(ply);e:Spawn()
                e:SetSaveValue("m_flDamage",100);e:SetVelocity(Vector(0,0,-1200));owned[#owned+1]=e
            end)
            later(24,function()fixture("menu_clear",origin)end)
            later(18,function()
                -- Bounds verified by the native read-only BSP probe: gm_construct's one
                -- water brush is x[-3072,1856], y[1985,6464], z[-960,-160].
                local at=game.GetMap()=="gm_construct" and Vector(-512,4096,-128) or ply:GetPos()+Vector(0,0,40)
                if bit.band(util.PointContents(at-Vector(0,0,64)),CONTENTS_WATER)~=0 then fixture("water",at)
                else say("water no volume below fixture; stand above a pool and repeat")end
            end)
        end
        later(duration,function()
            fixture("summary",origin)
            for name,value in pairs(saved)do RunConsoleCommand(name,value)end
            timer.Simple(1,function()clear();fixture("restore");running=false;say("done mode=%s",mode);print("NL_SHOT_DONE")end)
        end)
    end
    return
end
local D,V=NLGlassDebris,NLGlass.Client
local saved,camera,velocityUntil,direction,trace,benchmarking
local oldApply=NLGlass.Fracture.Apply
NLGlass.Fracture.Apply=function(state,...)
    if not saved or benchmarking then return oldApply(state,...)end
    local id=0 for key,r in pairs(V.records)do if r.state==state then id=key;break end end
    trace={id=id,receipt=SysTime(),frame=FrameNumber()}
    say("latency phase=client_receipt id=%d frame=%d game=%.6f wall=%.6f",id,trace.frame,CurTime(),trace.receipt)
    return oldApply(state,...)
end
local oldBuild=V.Build
V.Build=function(r,...)
    local result=oldBuild(r,...)
    if trace and r.id==trace.id then trace.hole=SysTime();say("latency phase=hole_built id=%d frame=%d delay_ms=%.3f",r.id,FrameNumber(),(trace.hole-trace.receipt)*1000)end
    return result
end
local oldSpawn=D.Spawn
D.Spawn=function(...)
    if trace then trace.spawning=true end
    return oldSpawn(...)
end
local frames,negative,worst=0,0,0
local performance,velocityCase=nil,0
hook.Add("PostRender","nlglass_qa_r9",function()
    if performance then performance[#performance+1]=FrameTime()end
    if trace and trace.spawning then
        local s=D.Stats()
        if not trace.first and (s.draw_calls_current or 0)>0 then
            trace.first=SysTime();say("latency phase=first_draw id=%d frame=%d delay_ms=%.3f queued=%d preview=%d",trace.id,FrameNumber(),(trace.first-trace.receipt)*1000,s.creation_pending or 0,s.preview_draws or 0)
        end
        if not trace.last and (s.creation_pending or 0)==0 and (s.live or 0)>0 then
            trace.last=SysTime();say("latency phase=last_body id=%d frame=%d delay_ms=%.3f",trace.id,FrameNumber(),(trace.last-trace.receipt)*1000)
        end
        if trace.hole and not trace.holeDraw then trace.holeDraw=true;say("latency phase=hole_draw id=%d frame=%d delay_ms=%.3f",trace.id,FrameNumber(),(SysTime()-trace.receipt)*1000)end
    end
    if velocityUntil and CurTime()<velocityUntil and D.Diagnostics then
        local rows=D.Diagnostics()
        for _,r in ipairs(rows or {})do local v=Vector(unpack(r[3]));local dot=v:Dot(direction);frames=frames+1;if dot<-.1 then negative=negative+1;worst=math.min(worst,dot)end end
    end
end)
hook.Add("CalcView","nlglass_qa_r9",function()if camera then return {origin=camera[1],angles=camera[2],fov=70}end end)
net.Receive(NET,function()
    local kind,at,dir=net.ReadString(),net.ReadVector(),net.ReadVector()
    if not saved then saved={};for _,name in ipairs({"rtx_glass_debris_lifetime","rtx_glass_debris_budget","rtx_glass_debris_collide_with","rtx_glass_debris_interact","rtx_glass_debris_sounds"})do
        local c=GetConVar(name);if c then saved[name]=c:GetString()end
    end end
    if kind=="restore" then for name,value in pairs(saved)do RunConsoleCommand(name,value)end;saved=nil;camera=nil;trace=nil;benchmarking=nil;return end
    if kind=="clear" then D.Clear();trace=nil;return end
    if kind=="menu_clear" then
        local before=D.Count();local panel=vgui.Create("DForm");NLGlass.BuildSettings(panel)
        local function find(control,text)
            if control.GetText and control:GetText()==text and control.DoClick then return control end
            for _,child in ipairs(control:GetChildren())do local found=find(child,text);if found then return found end end
        end
        local button=find(panel,NLGlass.I18n.L("Clear broken glass"))
        if button then button:DoClick()end
        say("menu_clear button=%s before=%d after=%d",tostring(button~=nil),before,D.Count())
        local all=find(panel,NLGlass.I18n.L("Clear broken glass for everyone"))
        if all then all:DoClick()end
        say("menu_everyone button=%s",tostring(all~=nil));panel:Remove();return
    end
    if kind:match("^perf_") then
        benchmarking=true
        D.Prepare();local eye=at+Vector(0,0,80);camera={eye,((at+Vector(-400,0,20))-eye):Angle()}
        local values={};performance=values
        timer.Simple(kind=="perf_empty" and 6 or kind=="perf_falling" and 4 or 15,function()
            if performance==values then performance=nil end
            table.sort(values);local sum=0;for _,v in ipairs(values)do sum=sum+v end
            say("performance phase=%s frames=%d mean_ms=%.4f p99_ms=%.4f stats=%s",kind,#values,sum/math.max(1,#values)*1000,
                (values[math.max(1,math.ceil(#values*.99))] or 0)*1000,util.TableToJSON(D.Stats()))
        end)
        return
    end
    if kind=="summary" or kind=="sample" then
        local s=D.Stats();say("stats %s",util.TableToJSON(s))
        say("velocity samples=%d backwards=%d worst_dot=%.3f",frames,negative,worst);return
    end
    RunConsoleCommand("rtx_glass_debris_lifetime","180");RunConsoleCommand("rtx_glass_debris_budget","2000")
    RunConsoleCommand("rtx_glass_debris_interact","1");RunConsoleCommand("rtx_glass_debris_collide_with","7")
    if kind=="velocity" then
        if velocityCase>0 then say("velocity_case case=%d samples=%d backwards=%d worst_dot=%.3f",velocityCase,frames,negative,worst)end
        velocityCase=velocityCase+1;frames,negative,worst=0,0,0
        direction=dir;velocityUntil=CurTime()+1.5;return
    end
    if kind=="view" then local eye=at-dir*200+Vector(0,0,30);camera={eye,(at-eye):Angle()};return end
    if kind~="pile" and kind~="water" then return end
    D.Clear();local parts={}
    for x=-2,2 do for y=-2,2 do parts[#parts+1]={poly={{x*16-7,y*16-7},{x*16+7,y*16-7},{x*16+7,y*16+7},{x*16-7,y*16+7}},thickness=.5,velocity=Vector(),spin=Vector(20,10,0)}end end
    D.Spawn({origin=at,angles=angle_zero,color=color_white,material="models/props_combine/health_charger_glass"},parts)
    camera={at+Vector(140,0,60),(at-(at+Vector(140,0,60))):Angle()}
    for _,name in ipairs({"glass_impact_soft1","glass_impact_soft2","glass_impact_soft3","glass_impact_hard1","glass_impact_hard2","glass_impact_hard3","glass_sheet_break1","glass_sheet_break2","glass_sheet_break3"})do
        say("asset physics/glass/%s.wav exists=%s",name,tostring(file.Exists("sound/physics/glass/"..name..".wav","GAME")))
    end
    timer.Simple(4,function()say("%s_stats %s",kind,util.TableToJSON(D.Stats()))end)
    if kind=="water" and D.Diagnostics then
        for _,delay in ipairs({.2,.5,1})do timer.Simple(delay,function()
            local rows=D.Diagnostics();local z,vz,n=0,0,0
            for _,r in ipairs(rows or {})do z=z+r[2][3];vz=vz+r[3][3];n=n+1 end
            say("water_motion t=%.2f samples=%d mean_z=%.3f mean_vz=%.3f",delay,n,z/math.max(1,n),vz/math.max(1,n))
        end)end
    end
end)
