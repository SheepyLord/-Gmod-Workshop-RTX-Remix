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
        GetAABB=function(self) return self.position-Vector(4,4,4),self.position+Vector(4,4,4) end,
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
        GetVelocity=function()return Vector(100,0,0)end,GetSolid=function()return 6 end,
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
local function capture(S,n)
    local out
    local previous=n.SyncBodies
    n.SyncBodies=function(rows,dt)out=rows;return previous(rows,dt)end
    S.Capture(n,.016);n.SyncBodies=previous;return out
end
if scenario:match("^scene") then
    local S=dofile(root.."/nlglass/debris_scene.lua") local n=api()
    if scenario=="scene_kinds" then
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
        check(queries==1,"full candidate cap prevents additional spatial queries")
        n.ReadRegions=function()return {}end;now=.2;rows=capture(S,n)
        check(#rows==0 and S.bodies==0,"no live regions means no Source capture")
        S.Reset();check(S.bodies==0 and S.candidates==0,"cleanup clears cached owners")
    elseif scenario=="scene_fallback" then
        local rag=entity("prop_ragdoll",nil,{{valid=false}})
        rag.GetHitBoxCount=function()return 2 end;rag.GetHitBoxBone=function(_,i)return i+10 end
        rag.GetHitBoxBounds=function()return Vector(-2,-2,-6),Vector(2,2,6)end
        rag.GetBoneMatrix=function(_,bone)return {GetTranslation=function()return Vector(0,0,bone)end,GetAngles=function()return Angle(0,45,0)end}end
        local prop=entity("prop_dynamic");prop.angles=Angle(0,90,0)
        local bad=phys();bad.GetMeshConvexes=function()return {{ {pos=Vector(0/0,0,0)} }}end
        nearby={rag,prop,entity("prop_physics",nil,{bad})}
        local rows=capture(S,n)
        check(#rows==4 and rows[1][3].y==45 and rows[2][2].z==11,"remote ragdoll follows bone hitboxes")
        check(rows[3][3].y==90,"nonphysics object uses an oriented box")
        check(rows[4][6]==nil and rows[4][4].x==4,"malformed physics convexes retain a coarse box")
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
        check(m.unreliable and m.name=="nlglass_debris_ray" and #m.fields==3,"bounded unreliable trace payload")
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
        for _=1,300 do fire()end
        check(inspected==64*3,"distant rejected pellets still obey the region-inspection burst cap")
    elseif scenario=="bullets_client" then
        CLIENT,SERVER=true,false;NLGlassDebris={Ray=function(...)_G.got={...}end}
        dofile(root.."/nlglass/debris_bullets.lua")
        local read=0;net.ReadVector=function()read=read+1;return read==1 and data.Trace.StartPos or data.Trace.HitPos end
        net.ReadFloat=function()return 15 end
        receivers.nlglass_debris_ray()
        check(got[1].x==-100 and got[2].x==100 and got[3]==15,"client routes one authoritative trace without predicted duplication")
        check(#sends==0,"client sends no interaction network requests")
    else error("unknown bullet case") end
end
print(string.format("interaction %s OK (%d assertions)",scenario,checks))
