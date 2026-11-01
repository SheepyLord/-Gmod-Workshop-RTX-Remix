-- MIT. Runs the actual Source snapshot and pellet forwarding modules with read-only Source doubles.
local root, scenario = assert(arg[1]), assert(arg[2])
local checks, now, queries, cooks, sends, filters = 0, 0, 0, 0, {}, 0
local function check(v, message) checks = checks + 1;assert(v, message) end
local V, A, P = {}, {}, {}
V.__index, A.__index, P.__index = V, A, P
function Vector(x,y,z) return setmetatable({x=x or 0,y=y or 0,z=z or 0},V) end
function Angle(p,y,r) return setmetatable({p=p or 0,y=y or 0,r=r or 0},A) end
function V.__add(a,b) return Vector(a.x+b.x,a.y+b.y,a.z+b.z) end
function V.__sub(a,b) return Vector(a.x-b.x,a.y-b.y,a.z-b.z) end
function V.__mul(a,b) return Vector(a.x*b,a.y*b,a.z*b) end
function V:LengthSqr() return self.x*self.x+self.y*self.y+self.z*self.z end
function V:Length() return math.sqrt(self:LengthSqr()) end
function V:DistToSqr(b) return (self-b):LengthSqr() end
function isvector(v) return getmetatable(v)==V end
function isangle(v) return getmetatable(v)==A end
function isnumber(v) return type(v)=="number" end
function IsValid(v) return type(v)=="table" and v.valid==true end
function CurTime() return now end
function SysTime() return os.clock() end
angle_zero,vector_origin,SOLID_NONE=Angle(),Vector(),0
function LocalToWorld(p,_,o,a)
    local c,s=math.cos(math.rad(a.y)),math.sin(math.rad(a.y))
    return o+Vector(c*p.x-s*p.y,s*p.x+c*p.y,p.z),Angle(a.p,a.y,a.r)
end
local function forbid() error("Source writes are forbidden") end
function P.__eq(a,b) check(a.valid and b.valid,"never compare destroyed PhysObjs");return rawequal(a,b) end
local function phys(position)
    return setmetatable({valid=true,position=position or Vector(),angles=Angle(),mass=30,velocity=Vector(),
        GetPos=function(self) return self.position end,GetAngles=function(self) return self.angles end,
        GetMass=function(self) return self.mass end,GetVelocity=function(self) return self.velocity end,
        -- As in game: PhysObj:GetAABB is in the object's own frame, LocalToWorld places it.
        GetAABB=function() return Vector(-4,-4,-4),Vector(4,4,4) end,
        LocalToWorld=function(self,v) return (LocalToWorld(v,angle_zero,self.position,self.angles)) end,
        GetMeshConvexes=function()
            cooks=cooks+1;local t={}
            for _,x in ipairs({-4,4})do for _,y in ipairs({-4,4})do for _,z in ipairs({-4,4})do t[#t+1]={pos=Vector(x,y,z)}end end end
            return {t}
        end,SetPos=forbid,SetVelocity=forbid,AddVelocity=forbid,ApplyForceCenter=forbid,Wake=forbid},P)
end
local function entity(kind,position,bodies)
    local e={valid=true,kind=kind,position=position or Vector(),angles=Angle(),bodies=bodies or {},alive=true,
        IsWorld=function(self)return self.kind=="worldspawn"end,GetClass=function(self)return self.kind end,
        IsPlayer=function(self)return self.kind=="player"end,IsNPC=function(self)return self.kind=="npc_citizen"end,
        IsNextBot=function(self)return self.kind=="nextbot"end,Alive=function(self)return self.alive end,Health=function(self)return self.alive and 100 or 0 end,
        WorldSpaceAABB=function(self)return self.position-Vector(16,16,32),self.position+Vector(16,16,32)end,
        GetCollisionBounds=function()return Vector(-16,-16,0),Vector(16,16,72)end,
        OBBMins=function()return Vector(-8,-4,-4)end,OBBMaxs=function()return Vector(8,4,4)end,
        GetPos=function(self)return self.position end,GetAngles=function(self)return self.angles end,
        GetVelocity=function(self)return self.velocity or Vector(100,0,0)end,GetSolid=function()return 6 end,
        GetPhysicsObjectCount=function(self)return #self.bodies end,
        GetPhysicsObjectNum=function(self,i)return self.bodies[i+1]end,
        SetPos=forbid,SetVelocity=forbid,TakeDamage=forbid,SetAngles=forbid}
    return e
end
local nearby={}
ents={FindInBox=function()queries=queries+1;return nearby end,GetAll=forbid}
local function api()
    return {ReadRegions=function()return {{{-100,-100,-100},{100,100,100}},{{-50,-50,-50},{150,150,150}}}end,
        SyncBodies=function(rows,dt)check(dt>=.001 and dt<=.25,"bounded sample time");return #rows end}
end
local function capture(S,n,dt,flags)
    local out
    local previous=n.SyncBodies
    n.SyncBodies=function(rows,dt)out=rows;return previous(rows,dt)end
    S.Capture(n,dt or .016,flags or 15);n.SyncBodies=previous;return out
end
if scenario=="sceneperf" then
    local ffi=require("ffi")
    ffi.cdef[[int QueryPerformanceCounter(int64_t *); int QueryPerformanceFrequency(int64_t *);]]
    local counter,frequency=ffi.new("int64_t[1]"),ffi.new("int64_t[1]")
    assert(ffi.C.QueryPerformanceFrequency(frequency)~=0)
    local period=1/tonumber(frequency[0])
    function SysTime()ffi.C.QueryPerformanceCounter(counter);return tonumber(counter[0])*period end
    local function bench(label,count,fast)
        local S=dofile(root.."/nlglass/debris_scene.lua");local n=api();nearby={};now=0
        n.ReadRegions=function()return count==0 and {} or {{{-100,-100,-100},{100,100,100}}}end
        for i=1,count do
            local p=phys(Vector(0,80,64));local e=entity("prop_physics",p.position,{p});e.velocity=vector_origin
            nearby[#nearby+1]=e
        end
        if fast then
            local p=nearby[#nearby].bodies[1];p.position,p.velocity=Vector(-210,0,4),Vector(650,0,0)
            nearby[#nearby].position,nearby[#nearby].velocity=p.position,p.velocity
        end
        for i=1,80 do now=i/60;S.Capture(n,1/60)end
        collectgarbage("collect")
        local total,times=0,{}
        for i=1,1200 do
            now=now+1/60;local start=SysTime();S.Capture(n,1/60)
            local elapsed=(SysTime()-start)*1000;total=total+elapsed;times[#times+1]=elapsed
        end
        table.sort(times)
        print(string.format("R7-C capture %s n=1200 mean_ms=%.6f p99_ms=%.6f max_ms=%.6f bodies=%d candidates=%d examined=%s",
            label,total/1200,times[1188],times[1200],S.bodies,S.candidates,tostring(S.examined)))
    end
    bench("empty",0);bench("warm96",96);bench("priority512",512,true)
elseif scenario=="scene_fast_replay" or scenario=="scene_fast_crowded_replay" then
    -- Real spatial query semantics: unlike the classification doubles, distant entities are absent.
    -- Feed these exact capture rows to Jolt in test_glass_interaction.py, including empty frames.
    local S=dofile(root.."/nlglass/debris_scene.lua")
    local n=api();n.ReadRegions=function()return {{{-146,-146,-96},{146,146,100}}}end
    ents.FindInBox=function(lo,hi)
        queries=queries+1;local found={}
        for _,e in ipairs(nearby)do
            local a,b=e:WorldSpaceAABB()
            if a.x<=hi.x and b.x>=lo.x and a.y<=hi.y and b.y>=lo.y and a.z<=hi.z and b.z>=lo.z then found[#found+1]=e end
        end
        return found
    end
    local speed=scenario=="scene_fast_replay" and 3600 or 650
    local dt=tonumber(arg[3]) or 1/60
    local p=phys(Vector(-210,0,4));p.velocity=Vector(speed,0,0)
    -- Fast bodies must not wait for or spend time in expensive engine mesh extraction.
    p.GetMeshConvexes=function()cooks=cooks+1;error("fast mirror must use its box before convex extraction")end
    local e=entity("prop_physics",p.position,{p});e.velocity=p.velocity
    if scenario=="scene_fast_crowded_replay" then
        for _=1,120 do
            local slow=entity("prop_dynamic",Vector(0,120,64));slow.velocity=vector_origin
            nearby[#nearby+1]=slow
        end
    end
    nearby[#nearby+1]=e
    print("REPLAY_BEGIN")
    for tick=0,35 do
        now=tick*dt;p.position=Vector(-210+speed*now,0,4);e.position=p.position
        local rows=capture(S,n,dt) or {}
        check(cooks==0,"fast capture never calls slow mesh extraction")
        print(string.format("frame %.9f %d",dt,#rows))
        for _,r in ipairs(rows)do
            check(r[6]==nil,"replay contains immediate boxes, no slow convex extraction")
            print(string.format("%d %.9f %.9f %.9f %.9f %.9f %.9f %.9f %.9f %.9f %.9f %.9f %.9f %.9f",
                r[1],r[2].x,r[2].y,r[2].z,r[3].p,r[3].y,r[3].r,r[4].x,r[4].y,r[4].z,r[5],r[7].x,r[7].y,r[7].z))
        end
    end
    print("REPLAY_END")
elseif scenario:match("^scene") then
    local S=dofile(root.."/nlglass/debris_scene.lua") local n=api()
    if scenario=="scene_flags" then
        local actor, npc, bot = entity("player"), entity("npc_citizen"), entity("nextbot")
        local rag, prop = entity("prop_ragdoll",nil,{phys()}), entity("prop_physics",nil,{phys()})
        local clientRag = entity("class C_ClientRagdoll",nil,{phys()})
        local held,pickup,follower=entity("weapon_crowbar",nil,{phys()}),entity("weapon_crowbar",nil,{phys()}),entity("phys_bone_follower",nil,{phys()})
        held.IsWeapon=function()return true end;pickup.IsWeapon=held.IsWeapon;held.GetOwner=function()return actor end
        follower.GetOwner=function()return npc end
        nearby={actor,npc,bot,rag,prop,clientRag,held,pickup,follower};player={GetAll=function()return {actor}end}
        for flags=0,15 do
            local rows=capture(S,n,.016,flags) or {}
            local expected=0
            for _, k in ipairs({4,8,8,2,1,2,1}) do if math.floor(flags/k)%2==1 then expected=expected+1 end end
            check(#rows==expected,"independent collision category filtering mask "..flags)
            for _,row in ipairs(rows)do check(math.floor(flags/row[8])%2==1,"snapshot tags match the filter")end
        end
        S.Reset();local rows=capture(S,n,.016,3)
        check(#rows==4,"default excludes living hulls, their equipped weapons and bone followers, but keeps pickups")
        rows=capture(S,n,.016,7)
        check(rows[3][8]==1 and rows[3][6]~=nil,"flag changes resend cold native shapes rather than retaining stale custom-shape cache")
        actor.alive=false;npc.alive=false;bot.alive=false
        now=now+.11;rows=capture(S,n,.016,15)
        for _,row in ipairs(rows)do check(row[8]~=4 and row[8]~=8,"dead actors cannot keep living mirrors")end
    elseif scenario=="scene_kinds" then
        local player=entity("player",nil,{phys()})
        local npc=entity("npc_citizen",nil,{phys()})
        local rag=entity("prop_ragdoll",nil,{phys(Vector(0,0,8)),phys(Vector(0,0,16)),phys(Vector(0,0,24))})
        local prop=entity("prop_physics",nil,{phys()})
        local dead=entity("player");dead.alive=false
        nearby={player,npc,rag,prop,entity("prop_dynamic"),dead,entity("worldspawn"),entity("nlglass_pane"),entity("prop_physics",Vector(9000,0,0))}
        local rows=capture(S,n)
        check(#rows==7,"living hulls, per-physics-bone ragdoll, physics prop and box fallback")
        check(cooks>=1 and cooks<=2 and queries==2,"bounded new shapes and duplicate region candidates deduplicated")
        check(rows[1][5]==85 and rows[1][6]==nil and rows[1][2].z==32 and rows[1][4].z==40,
            "player uses its hull plus the floor-piece sole skirt, not shadow mass/shape")
        check(rows[3][5]==30 and rows[3][6]~=nil,"ragdoll uses physics-bone shape and real mass")
        local key=rows[3][1]
        now=.02;rag.bodies[1].position=Vector(5,0,8);rows=capture(S,n)
        check(rows[3][1]==key and rows[3][2].x==5 and rows[3][6]==nil,"same mirror updates every step without recooking")
        check(queries==2,"discovery remains at ten Hz")
        rag.bodies[1].valid=false;rag.bodies[1]=phys(Vector(7,0,8));now=.04
        rows=capture(S,n);check(rows[3][1]~=key,"rebuilt physics object gets a new mirror identity")
        prop.valid=false;rows=capture(S,n);check(#rows==6,"removed Source entities disappear from the next snapshot")
    elseif scenario=="scene_caps" then
        local actor=entity("player")
        player={GetAll=function()return {actor}end}
        for i=1,300 do
            local bodies={};for b=1,30 do bodies[b]=phys() end
            nearby[i]=entity("prop_ragdoll",nil,bodies)
        end
        local rows=capture(S,n)
        check(S.candidates==128 and #rows==96 and cooks>=1 and cooks<=2,"candidate/body/new-shape caps")
        check(rows[1][5]==85,"nearby players take priority over a saturated generic entity prefix")
        check(rows[24][1] and rows[25][1],"per-ragdoll bone cap permits other entities")
        check(queries==2 and S.examined==512,"bounded priority prefix prevents additional candidate inspection")
        n.ReadRegions=function()return {}end;now=.2;rows=capture(S,n)
        check(#rows==0 and S.bodies==0,"no live regions means no Source capture")
        S.Reset();check(S.bodies==0 and S.candidates==0,"cleanup clears cached owners")
    elseif scenario=="scene_fallback" then
        local rag=entity("prop_ragdoll",nil,{{valid=false}})
        rag.GetHitBoxCount=function()return 2 end;rag.GetHitBoxBone=function(_,i)return i+10 end
        rag.GetHitBoxBounds=function()return Vector(-2,-2,-6),Vector(2,2,6)end
        rag.GetBoneMatrix=function(_,bone)return {GetTranslation=function()return Vector(0,0,bone)end,GetAngles=function()return Angle(0,45,0)end}end
        local prop=entity("prop_dynamic");prop.angles=Angle(0,90,0)
        local bad=phys(Vector(20,0,0));bad.angles=Angle(0,30,0);bad.GetMeshConvexes=function()return {{ {pos=Vector(0/0,0,0)} }}end
        nearby={rag,prop,entity("prop_physics",nil,{bad})}
        local rows=capture(S,n)
        check(#rows==4 and rows[1][3].y==45 and rows[2][2].z==11,"remote ragdoll follows bone hitboxes")
        check(rows[3][3].y==90,"nonphysics object uses an oriented box")
        check(rows[4][6]==nil and rows[4][4].x==4,"malformed physics convexes retain a coarse box")
        check(rows[4][2].x==20 and rows[4][3].y==30,"a coarse box takes its physics object's world pose")
    elseif scenario=="scene_sweep_bounds" then
        local function moving(x,v)
            local p=phys(Vector(x,0,4));p.velocity=Vector(v,0,0)
            local e=entity("prop_physics",p.position,{p});e.velocity=p.velocity
            return e,p
        end
        local incoming,p=moving(-260,650)
        local away=moving(-260,-650)
        local distant=moving(-450,100000)
        nearby={away,distant,incoming}
        local rows=capture(S,n)
        check(#rows==1 and rows[1][2].x==-260 and rows[1][6]==nil and cooks==0,"sweep sees incoming body but rejects away/distant bodies; no early kick or cooking")
        check(S.fast_candidates==1 and S.fast_bodies==1 and S.fast_boxes==1 and S.peak_bodies==1,"fast capture telemetry")
        local key=rows[1][1]
        incoming.position,p.position=Vector(),Vector();incoming.velocity,p.velocity=Vector(),Vector();now=.02
        rows=capture(S,n)
        check(rows[1][1]==key and rows[1][6]~=nil and cooks==1,"slow mirror upgrades its original box within the ordinary cooking budget")
        check(S.fast_boxes==1 and S.fast_bodies==0,"upgrade keeps identity and does not count another fast box")
        S.Reset();check(S.fast_boxes==0 and S.peak_bodies==0 and S.examined==0,"reset clears fast capture counters")
    else error("unknown scene case") end
else
    SERVER,CLIENT=true,false
    local hooks,receivers={},{}
    hook={Add=function(name,_,fn)hooks[name]=fn end}
    local message
    net={Receive=function(name,fn)receivers[name]=fn end,
        Start=function(name,unreliable)message={name=name,unreliable=unreliable,fields={}}end,
        WriteVector=function(v)message.fields[#message.fields+1]=v end,
        WriteFloat=function(v)message.fields[#message.fields+1]=v end,
        WriteUInt=function(v)message.fields[#message.fields+1]=v end,
        Send=function(r)message.recipients=r;sends[#sends+1]=message end,SendToServer=forbid,Broadcast=forbid}
    util={AddNetworkString=function()end}
    function RecipientFilter()
        filters=filters+1
        return {pvs={},players={},AddPVS=function(self,p)self.pvs[#self.pvs+1]=p end,AddPlayer=function(self,p)self.players[#self.players+1]=p end}
    end
    game={GetAmmoID=function()return 1 end,GetAmmoPlayerDamage=function()return 12 end,GetAmmoNPCDamage=function()return 9 end}
    local B=dofile(root.."/nlglass/debris_bullets.lua")
    local shooter=entity("player")
    local data={Damage=15,Trace={StartPos=Vector(-100,0,0),HitPos=Vector(100,0,0)},Callback=function()end}
    local original=data.Callback
    local function fire(e)check(hooks.PostEntityFireBullets(e or shooter,data)==nil,"bullet hook never changes the bullet")end
    if scenario=="bullets_filter" then
        fire();check(#sends==0 and filters==0,"no recent breaks means no messages or recipient filters")
        B.Mark(Vector(0,5000,0));fire();check(#sends==0,"rays outside recent glass regions stay local to Source")
        B.Mark(Vector());fire();check(#sends==1,"nearby bullet reaches glass clients")
        local m=sends[1]
        check(m.unreliable and m.name=="nlglass_debris_hit" and #m.fields==4,"bounded unreliable trace payload")
        check(m.fields[2].x==100 and m.fields[3]==15,"ray ends at Source's actual hit, with pellet damage")
        check(#m.recipients.pvs==1 and m.recipients.players[1]==shooter,"PVS plus shooter, never broadcast")
        check(data.Callback==original,"weapon callback remains unchanged")
        data.Damage=0;fire();check(sends[2].fields[3]==12,"zero damage uses ammo metadata")
        data.Attacker=shooter;fire(entity("weapon_pistol"))
        check(sends[3].recipients.players[1]==shooter,"a weapon-fired trace still includes its actual player attacker")
        now=121;fire();check(#sends==3,"expired interest regions forward nothing")
        B.Clear();check(#B.regions==0 and B.sent==0,"cleanup clears recent break interest")
    elseif scenario=="bullets_rate" then
        B.Mark(Vector())
        for _=1,100 do fire()end
        check(#sends==8 and B.limited==92,"per-firing-entity burst cap")
        now=1;for _=1,30 do fire()end;check(#sends==16,"per-entity token bucket refills only to its burst")
        B.Clear();B.Mark(Vector());sends={}
        for _=1,5 do local other=entity("player");for _=1,8 do fire(other)end end
        check(#sends==32,"global burst cap across shooters")
        for i=1,100 do B.Mark(Vector(i*256,0,0))end
        check(#B.regions==32,"recent-break region ring stays bounded")
        B.Clear();B.Mark(Vector(5000,0,0))
        local inspected=0
        B.regions[1].origin=setmetatable({}, {__index=function(_,key)inspected=inspected+1;return key=="x" and 5000 or 0 end})
        local beforeFilters=filters
        for _=1,300 do fire()end
        check(inspected==0 and filters-beforeFilters==64,"bounded region inspection uses numbers, never Source components")
    elseif scenario=="bullets_interest" then
        local a,b=entity("player"),entity("player")
        local function interest(ply,center,count,radius,bits)
            net.ReadUInt=function()return count or 1 end
            net.ReadVector=function()return center end
            net.ReadFloat=function()return radius or 600 end
            -- As in game: a compressed vector (3-66 bits) and a 32-bit float per region.
            receivers.nlglass_debris_interest(bits or (6+(count or 1)*(54+32)),ply)
        end
        interest(a,Vector());interest(b,Vector(10000,0,0))
        check(B.HasInterest() and B.clients[a] and B.clients[b],"each client owns a separate bounded interest lease")
        for i=1,65 do
            now=i*2;interest(a,Vector());interest(b,Vector(10000,0,0))
            if i==30 or i==65 then
                local before=#sends;fire()
                check(#sends==before+1,"renewed live-piece interest survives 60 and 130 seconds")
                local seenA,seenB=false,false
                for _,p in ipairs(sends[#sends].recipients.players)do seenA=seenA or p==a;seenB=seenB or p==b end
                check(seenA and not seenB and #sends[#sends].recipients.pvs==0,"only the client whose local pieces overlap receives a long-lived hit")
            end
        end
        now=132;interest(a,Vector(10000,0,0));local before=#sends;fire();check(#sends==before,"displaced local piles replace their old regions")
        now=140;fire();check(#sends==before and not B.HasInterest(),"lost leases expire and stop forwarding")
        interest(a,Vector(),33,600,4200);check(not B.clients[a],"too many regions refused")
        interest(a,Vector(),1,600,6+35);check(B.clients[a] and #B.clients[a].regions==1,"the smallest real update (a zero vector) is accepted")
        B.clients[a]=nil;interest(a,Vector(),1,600,6+34);check(not B.clients[a],"an update shorter than one region is refused")
        interest(a,Vector(0/0,0,0));check(not B.clients[a],"nonfinite regions refused")
        interest(a,Vector());local saved=B.clients[a];interest(a,Vector(10000,0,0))
        check(B.clients[a]==saved,"rapid interest updates cannot replace an accepted lease")
        now=142;interest(a,Vector(),0);check(#B.clients[a].regions==0,"explicit empty interest clears local demand")
    elseif scenario:match("^melee_") then
        local timers={};timer={Simple=function(_,fn)timers[#timers+1]=fn end}
        local function flush() local list=timers;timers={};for _,fn in ipairs(list)do fn()end end
        local w={valid=true,Primary={Damage=31},nextFire=0,class="weapon_crowbar",GetClass=function(self)return self.class end,
            GetHoldType=function()return "melee2"end,GetNextPrimaryFire=function(self)return self.nextFire end}
        shooter.GetActiveWeapon=function()return w end;shooter.GetShootPos=function()return Vector()end
        shooter.GetAimVector=function()return Vector(1,0,0)end
        IN_ATTACK,IN_ATTACK2,PLAYERANIMEVENT_ATTACK_PRIMARY,PLAYERANIMEVENT_ATTACK_SECONDARY=1,2,0,1
        local command={KeyDown=function(_,key)return key==IN_ATTACK end}
        local lastData,lastResult,clipBlocked,clipQueries
        clipQueries=0
        util.TraceLine=function(data)
            clipQueries=clipQueries+1
            lastData=data;lastResult={HitPos=data.endpos,StartPos=data.start,Hit=false}
            if clipBlocked then lastResult.StartSolid=true end
            if scenario=="melee_swep" then lastResult.HitPos=Vector(data.endpos.x==30 and 22 or 30,0,0);lastResult.Hit=true end
            return lastResult
        end
        util.TraceHull=util.TraceLine
        B.Mark(Vector());local M=dofile(root.."/nlglass/debris_melee.lua")
        if scenario=="melee_stock" then
            hooks.StartCommand(shooter,command);check(#sends==0,"ready command alone is not a swing")
            now=.02;w.nextFire=.5;hooks.StartCommand(shooter,command)
            check(#sends==1 and sends[1].fields[4]==6,"successful stock crowbar swing forwards a bounded volume")
            hooks.DoAnimationEvent(shooter,PLAYERANIMEVENT_ATTACK_PRIMARY)
            check(#sends==1,"animation and cooldown observations do not duplicate a stock swing")
            now=.6;w.class="weapon_stunstick";w.nextFire=0;hooks.StartCommand(shooter,command)
            now=.62;w.nextFire=1;hooks.StartCommand(shooter,command)
            check(#sends==2 and sends[2].fields[3]==40,"stunstick uses its own melee damage")
            local other=entity("player");other.GetActiveWeapon=shooter.GetActiveWeapon
            other.GetShootPos,other.GetAimVector=shooter.GetShootPos,shooter.GetAimVector
            now=.8;hooks.DoAnimationEvent(other,PLAYERANIMEVENT_ATTACK_PRIMARY);hooks.StartCommand(other,command)
            check(#sends==3,"an animation before the first command initializes a complete stock swing state")
            now=1.1;clipBlocked=true;hooks.DoAnimationEvent(other,PLAYERANIMEVENT_ATTACK_PRIMARY)
            check(#sends==3,"stock melee cannot cross a solid start in the Source clipping volume")
            clipBlocked=false;B.Clear();B.Mark(Vector(5000,0,0));local before=clipQueries
            for _=1,100 do
                local p=entity("player");p.GetActiveWeapon=shooter.GetActiveWeapon;p.GetShootPos=shooter.GetShootPos;p.GetAimVector=shooter.GetAimVector
                hooks.DoAnimationEvent(p,PLAYERANIMEVENT_ATTACK_PRIMARY)
            end
            check(clipQueries-before<=32 and M.limited>0,"Source melee clipping queries obey their own global burst cap even outside recipient regions")
        else
            w.class="weapon_trace_melee";hooks.StartCommand(shooter,command)
            local input={start=Vector(),endpos=Vector(90,0,0),filter=shooter,mins=Vector(-8,-8,-8),maxs=Vector(8,8,8)}
            local result=util.TraceHull(input)
            check(result==lastResult and lastData==input and result.HitPos.x==30,"SWEP receives the same real trace object and input")
            input.start.x,result.HitPos.x=900,1000
            flush()
            check(#sends==1 and sends[1].fields[2].x==22 and sends[1].fields[4]==8,"the native volume is conservatively re-clipped by Source while the SWEP's own hit stays unchanged")
            check(result.HitPos.x==1000,"deferred observation owns copies and never overwrites a weapon's reused vectors")
            input.start.x=0
            util.TraceLine(input);flush();check(#sends==1,"duplicate melee traces in the same swing are coalesced")
            now=.8;util.TraceLine(input);flush();check(#sends==1,"traces outside an attack window do not become melee")
            now=.9;hooks.StartCommand(shooter,command);input.endpos=Vector(10000,0,0);util.TraceLine(input)
            check(#sends==1,"unrelated long traces are ignored")
            now=1.1;w.class="weapon_fists";w.Primary={};w.HitDamage={8,12};hooks.StartCommand(shooter,command)
            input.endpos=Vector(48,0,0);input.mins,input.maxs=nil,nil;util.TraceLine(input)
            input.mins,input.maxs=Vector(-10,-10,-8),Vector(10,10,8);util.TraceHull(input);flush()
            check(#sends==2 and sends[2].fields[4]==10 and sends[2].fields[3]==10,"fists' line-then-hull pattern keeps the final wider trace and configured damage")
        end
        M.Stop();local observed=M.observed
        util.TraceLine({start=Vector(),endpos=Vector(50,0,0),filter=shooter})
        check(M.observed==observed,"stop restores trace adapters without gameplay writes")
    elseif scenario=="bullets_client_interest" then
        CLIENT,SERVER=true,false;local updates=0
        net.SendToServer=function()updates=updates+1 end
        local C=dofile(root.."/nlglass/debris_bullets.lua")
        local reads=0;local n={ReadRegions=function()reads=reads+1;return {{{0,0,0},{512,512,512}}}end}
        C.Update(n,false);check(updates==0 and reads==0,"empty clients send no demand")
        C.Update(n,true);check(updates==1 and reads==1,"first live pieces register immediately")
        for i=1,60 do now=i*.01;C.Update(n,true)end
        check(updates==1,"interest polling is cheap between two-second refreshes")
        now=61;C.Update(n,true);check(updates==2,"settled long-lived pieces renew their lease")
        C.Update(n,false);check(updates==3 and reads==2,"cleanup/master off sends an empty update without querying pieces")
        C.Update(n,false);check(updates==3,"empty update is not repeated")
    elseif scenario=="bullets_client" then
        CLIENT,SERVER=true,false;NLGlassDebris={Ray=function(...)_G.got={...}end}
        dofile(root.."/nlglass/debris_bullets.lua")
        local read=0;net.ReadVector=function()read=read+1;return read==1 and data.Trace.StartPos or data.Trace.HitPos end
        net.ReadFloat=function()return 15 end
        net.ReadUInt=function()return 0 end
        receivers.nlglass_debris_hit()
        check(got[1].x==-100 and got[2].x==100 and got[3]==15,"client routes one authoritative trace without predicted duplication")
        check(#sends==0,"client sends no interaction network requests")
    else error("unknown bullet case") end
end
print(string.format("interaction %s OK (%d assertions)",scenario,checks))
