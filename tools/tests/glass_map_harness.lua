-- Execute the shipped geometry, map-break controller and packet writer with generated engine data.
local V = {}
V.__index = V
function Vector(x,y,z) return setmetatable({x=x or 0,y=y or 0,z=z or 0},V) end
function V.__add(a,b) return Vector(a.x+b.x,a.y+b.y,a.z+b.z) end
function V.__sub(a,b) return Vector(a.x-b.x,a.y-b.y,a.z-b.z) end
function V.__unm(a) return Vector(-a.x,-a.y,-a.z) end
function V.__mul(a,b) return Vector(a.x*b,a.y*b,a.z*b) end
function V.__div(a,b) return a*(1/b) end
function V:Dot(b) return self.x*b.x+self.y*b.y+self.z*b.z end
function V:Cross(b) return Vector(self.y*b.z-self.z*b.y,self.z*b.x-self.x*b.z,self.x*b.y-self.y*b.x) end
function V:LengthSqr() return self:Dot(self) end
function V:GetNormalized() local n=math.sqrt(self:LengthSqr());return n>0 and self/n or Vector() end
function Angle() return {} end
function VectorRand() return Vector(.2,-.3,.4) end
function WorldToLocal(p,_,origin) return p-origin,Angle() end
function math.Clamp(v,a,b) return math.max(a,math.min(b,v)) end
math.randomseed(8421)

local base=arg[1]
local geometry=dofile(base..'/lua/glass_map_geometry.lua')
local function box(x,y,z,transform)
    local p={Vector(-x,-y,-z),Vector(x,-y,-z),Vector(x,y,-z),Vector(-x,y,-z),
        Vector(-x,-y,z),Vector(x,-y,z),Vector(x,y,z),Vector(-x,y,z)}
    if transform then for i,v in ipairs(p) do p[i]=transform(v) end end
    local mesh={}
    for _,f in ipairs({{1,4,3,2},{5,6,7,8},{1,5,8,4},{2,3,7,6},{1,2,6,5},{4,8,7,3}}) do
        for _,i in ipairs({f[1],f[2],f[3],f[1],f[3],f[4]}) do mesh[#mesh+1]=p[i] end
    end
    return mesh
end
local checks=0
local function check(v,message) checks=checks+1;assert(v,message) end
for _,shape in ipairs({box(.5,25,67),box(25,.5,67),box(25,67,.5),box(.5,25,67,function(p)
    local c,s=math.cos(.7),math.sin(.7);return Vector(p.x*c+p.z*s,p.y,-p.x*s+p.z*c)+Vector(30,40,50)
end)}) do
    local _,_,center=geometry.Bounds(shape)
    for _,count in ipairs({2,6,18,24}) do
        local pieces=geometry.Fracture({shape},center,count)
        check(#pieces==count,'fragment count for arbitrary pane orientation')
        local total=0
        for _,piece in ipairs(pieces) do
            check(geometry.Copy(piece)~=nil,'closed nondegenerate fragment')
            total=total+math.abs(geometry.Volume(piece))
        end
        check(math.abs(total-math.abs(geometry.Volume(shape)))<.001,'volume conserved by closed caps')
    end
end
check(geometry.Copy({Vector(),Vector(),Vector()})==nil,'flat/invalid mesh refused')
local nan=box(1,1,1);nan[1].x=0/0
check(geometry.Copy(nan)==nil,'nonfinite geometry refused')
local wrapped={};for i,p in ipairs(box(.5,25,67)) do wrapped[i]={pos=p} end
check(#geometry.Copy(wrapped)==36,'VPhysics MeshVertex input accepted')

-- Real map controller: engine mocks describe effects, not copies of the controller's decisions.
local events,timers,pool,spawned={}, {}, {}, {}
SERVER=true;CLIENT=false
hook={Add=function(event,id,callback) events[event]=events[event] or {};events[event][id]=callback end}
timer={Simple=function(_,callback) timers[#timers+1]=callback end}
gameevent={Listen=function(name) check(name=='break_breakable','native break event registered') end}
local function run(name,...)
    for _,callback in pairs(events[name] or {}) do check(callback(...)==nil,'hook preserves native return values') end
end
local function flush()
    local count=0
    while #timers>0 do
        local now=timers;timers={}
        for _,callback in ipairs(now) do callback() end
        count=count+1;assert(count<100,'bounded timers')
    end
end
function IsValid(ent) return type(ent)=='table' and ent.valid~=false end
function SafeRemoveEntity(ent) ent:Remove() end
COLLISION_GROUP_WORLD=20;COLLISION_GROUP_DEBRIS=1
local values={rtx_glass_shard_count=12,rtx_glass_velocity_transfer=2,rtx_glass_expensive_shards=1}
function GetConVar(name) return {GetInt=function()return values[name]end,GetFloat=function()return values[name]end,GetBool=function()return values[name]~=0 end} end
local function physics(material)
    return {valid=true,GetMaterial=function()return material end,GetMeshConvexes=function()return {wrapped}end,
        GetPos=function()return Vector(10,20,30)end,GetAngles=Angle,GetVelocity=function()return Vector(1,2,3)end,
        GetMass=function()return 2 end,EnableMotion=function(self,v)self.motion=v end,
        SetVelocity=function(self,v)self.velocity=v end,AddAngleVelocity=function()end,Wake=function(self)self.awake=true end}
end
local function brush(id,material,class)
    local p=physics(material)
    return {valid=true,health=15,GetClass=function()return class or 'func_breakable'end,
        EntIndex=function()return id end,GetPhysicsObject=function()return p end,GetColor=function()return {r=255,g=255,b=255,a=255}end}
end
local function count()
    local n=0;for _,ent in ipairs(spawned)do if ent.valid then n=n+1 end end;return n
end
ents={FindByClass=function()return pool end,Create=function(class)
    check(class=='procedural_shard','reuse networked glass entity')
    local p=physics('glass')
    local ent={valid=true,GetPhysicsObject=function()return p end,Spawn=function()end,
        SetPhysModel=function(self,v)self.model=v end,SetPhysScale=function()end,SetPos=function(self,v)self.position=v end,
        SetAngles=function()end,SetColor=function()end,SetCollisionGroup=function(self,v)self.group=v end,
        BuildCollision=function(self,mesh,success)self.mesh=mesh;success[1]=true end,Remove=function(self)self.valid=false end}
    spawned[#spawned+1]=ent;return ent
end}
function include(path) check(path=='glass_map_geometry.lua','controller uses shipped geometry');return geometry end
dofile(base..'/lua/autorun/server/rtx_map_glass.lua')
local pane=brush(10,'glass');pool={pane};run('InitPostEntity')
check(count()==0 and pane.health==15,'intact native pane untouched')
run('EntityTakeDamage',pane,{GetDamagePosition=function()return Vector(10,20,30)end,GetDamageForce=function()return Vector(1500,0,0)end})
run('EntityRemoved',pane) -- observed native ordering: removal hook precedes break event
run('break_breakable',{entindex=10});run('break_breakable',{entindex=10});flush()
check(count()==18,'one native break creates exactly one independent debris set')
check(pane.valid and pane.health==15,'controller never removes or replaces native pane')
for _,ent in ipairs(spawned)do check(ent.RTX_MAP_DEBRIS and ent:GetPhysicsObject().motion and ent:GetPhysicsObject().awake,'persistent moving debris')end
local metal=brush(11,'metal');pool={metal};run('InitPostEntity');run('break_breakable',{entindex=11});flush()
check(count()==18,'non-glass breakable ignored')
local prop=brush(12,'glass','prop_physics');pool={prop};run('InitPostEntity');run('break_breakable',{entindex=12});flush()
check(count()==18,'glass props outside brush integration untouched')
local removed=brush(13,'glass');pool={removed};run('InitPostEntity');run('EntityRemoved',removed);flush()
run('break_breakable',{entindex=13});flush();check(count()==18,'ordinary removal creates no debris')
local delayed=brush(14,'glass');pool={delayed};run('InitPostEntity');run('break_breakable',{entindex=14})
run('PreCleanupMap');flush();check(count()==0,'cleanup cancels queued fractures and clears existing debris')
for i=1,20 do
    local glass=brush(20+i,'glass');run('OnEntityCreated',glass);flush();run('AcceptInput',glass,'Break')
    run('break_breakable',{entindex=20+i});flush()
end
check(count()==256,'map debris has a bounded oldest-first budget')
run('PreCleanupMap');pool={brush(99,'glass')};run('PostCleanupMap');run('break_breakable',{entindex=99});flush()
check(count()==18,'map cleanup repopulates brush support')
print('geometry and native-event assertions: '..checks)

-- Execute the shipped server network writer. The Python runner only normalizes GLua comments.
local receivers,packets,current={}, {}, nil
local shards={}
for i=1,256 do
    local triangles={};for j=1,300 do triangles[j]={pos=Vector(j,0,0)}end
    shards[i]={valid=true,TRIANGLES=triangles,EntIndex=function()return i end}
end
shards[#shards+1]={valid=false}
shards[#shards+1]={valid=true,TRIANGLES={}}
ents.FindByClass=function()return shards end
util={AddNetworkString=function()end}
AddCSLuaFile=function()end
include=function()return function()end,function()end end
local clock,requested=0,1
CurTime=function()return clock end
net={Receive=function(name,callback)receivers[name]=callback end,
    Start=function()current={bits=0,integers={}}end,
    WriteBool=function(v)current.bits=current.bits+1;current.full=v end,
    WriteUInt=function(v,n)current.bits=current.bits+n;current.integers[#current.integers+1]=v end,
    WriteFloat=function()current.bits=current.bits+32 end,
    Send=function(ply)current.to=ply;packets[#packets+1]=current end,
    ReadEntity=function()return shards[requested]end}
assert(loadfile(arg[2]))()
local function tick()
    local before=#packets;run('Tick');clock=clock+1/66
    local sent={};for i=before+1,#packets do sent[#sent+1]=packets[i] end
    return sent
end
local function bits(list,ply) local n=0;for _,p in ipairs(list)do if p.to==ply then n=n+p.bits end end;return n end
-- A late join after 256 shattered windows (about 920 KB): nothing inside the request, then one
-- bounded batch per tick until every valid shard was sent.
local joiner={}
receivers.SHARD_NETWORK(0,joiner)
check(#packets==0,'a full resync is not written inside the request handler')
local total,ticks=0,0
repeat
    local sent=tick();ticks=ticks+1
    check(#sent<=1,'one full-update batch per tick')
    for _,packet in ipairs(sent)do
        check(packet.full and packet.bits<=16000*8,'late-join batch stays within the per-tick pace')
        total=total+packet.integers[1]
    end
    -- Requests repeated while it is running are ignored.
    if ticks==3 then receivers.SHARD_NETWORK(0,joiner) end
until #sent==0 or ticks>1000
check(total==256 and ticks>16,'all valid shards delivered over many ticks: '..total..' in '..ticks)
-- One full resync per player per interval: an empty-request flood serializes nothing more.
for _=1,50 do receivers.SHARD_NETWORK(0,joiner) end
check(#tick()==0,'a repeated full resync within the interval is ignored')
clock=clock+31;receivers.SHARD_NETWORK(0,joiner)
local again=tick()
check(#again==1 and again[1].full,'a full resync is granted again after the interval')
while #tick()>0 do end
-- Two joiners at once: each gets at most one batch per tick.
local other={};clock=clock+31
receivers.SHARD_NETWORK(0,joiner);receivers.SHARD_NETWORK(0,other)
for _=1,5 do
    local sent=tick()
    check(#sent==2 and sent[1].to~=sent[2].to,'one batch per joiner per tick')
end
while #tick()>0 do end
-- Single-shard requests (post-break): answered on the tick, the same shard once, bounded per tick.
packets={}
requested=1;receivers.SHARD_NETWORK(16,joiner)
check(#packets==0,'a single-shard answer waits for the tick')
local sent=tick()
check(#sent==1 and not sent[1].full,'single-shard request protocol unchanged')
for _=1,10 do receivers.SHARD_NETWORK(16,joiner) end
check(#tick()==1,'the same shard requested repeatedly is queued once')
requested=#shards-1;receivers.SHARD_NETWORK(16,joiner)
requested=#shards;receivers.SHARD_NETWORK(16,joiner)
check(#tick()==0,'invalid or empty shards are not answered')
for i=1,40 do requested=i;receivers.SHARD_NETWORK(16,joiner) end
local answered,rounds=0,0
repeat
    sent=tick();rounds=rounds+1
    check(#sent<=16 and bits(sent,joiner)<=16000*8,'single-shard answers are capped per tick')
    answered=answered+#sent
until #sent==0 or rounds>100
check(answered==40 and rounds>2,'every requested shard is answered over several ticks')
-- A player who leaves takes the queue along.
for i=1,10 do requested=i;receivers.SHARD_NETWORK(16,other) end
run('PlayerDisconnected',other)
check(#tick()==0,'a disconnected player is sent nothing')
print('all glass map assertions passed: '..checks)
