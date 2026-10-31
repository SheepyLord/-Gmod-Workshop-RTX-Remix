-- Execute the shipped geometry, map-break controller, loose-glass lifecycle and packet writer with
-- generated engine data. Arguments: the add-on folder, then plain-Lua copies (test_glass_map.py) of
-- networking.lua, procedural_shard.lua and world_functions.lua.
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

-- Real map controller and debris registry: engine mocks describe effects, not copies of the
-- controller's decisions.
local registry_path=base..'/lua/autorun/server/glass_debris.lua'
local registry_file=io.open(registry_path)
if registry_file then registry_file:close() end
local events,timers,pool,spawned={}, {}, {}, {}
SERVER=true;CLIENT=false
hook={Add=function(event,id,callback) events[event]=events[event] or {};events[event][id]=callback end}
timer={Simple=function(_,callback) timers[#timers+1]=callback end,Create=function() end}
gameevent={Listen=function(name) check(name=='break_breakable','native break event registered') end}
CurTime=function() return 0 end
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
COLLISION_GROUP_WORLD=20;COLLISION_GROUP_DEBRIS=1;COLLISION_GROUP_WEAPON=11
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
if registry_file then dofile(registry_path) end
dofile(base..'/lua/autorun/server/rtx_map_glass.lua')
local pane=brush(10,'glass');pool={pane};run('InitPostEntity')
check(count()==0 and pane.health==15,'intact native pane untouched')
run('EntityTakeDamage',pane,{GetDamagePosition=function()return Vector(10,20,30)end,GetDamageForce=function()return Vector(1500,0,0)end})
run('EntityRemoved',pane) -- observed native ordering: removal hook precedes break event
run('break_breakable',{entindex=10});run('break_breakable',{entindex=10});flush()
check(count()==18,'one native break creates exactly one independent debris set')
check(pane.valid and pane.health==15,'controller never removes or replaces native pane')
for _,ent in ipairs(spawned)do
    check(ent.RTX_MAP_DEBRIS and ent:GetPhysicsObject().motion and ent:GetPhysicsObject().awake,'moving debris')
    -- Not COLLISION_GROUP_WORLD (only the world collides with it): props and the pile collide with it,
    -- players pass through (ADR 0061).
    check(ent.group==COLLISION_GROUP_WEAPON,'map debris collides with props and itself, not with players')
end
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

-- Execute the shipped server network writer. The Python runner only normalizes GLua syntax.
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
print('network assertions: '..checks)

-- Loose broken glass (ADR 0061) with the shipped entity: procedural_shard.lua in both realms, its
-- world_functions.lua, the debris registry and the map controller, over an entity system and a VPhysics
-- that builds each convex hull from the points the entity passes, as the engine does. Each scenario
-- starts on a clean map; a failed one is reported and the others still run.
events={}
math.randomseed(20261031)
clock=1000
function V.__mul(a,b)
    if type(a)=='number' then a,b=b,a end
    if type(b)=='number' then return Vector(a.x*b,a.y*b,a.z*b) end
    return Vector(a.x*b.x,a.y*b.y,a.z*b.z) -- GMod multiplies two vectors per component
end
function V.__eq(a,b) return a.x==b.x and a.y==b.y and a.z==b.z end
function V:Length() return math.sqrt(self:LengthSqr()) end
function Angle(p,y,r) return {p=p or 0,y=y or 0,r=r or 0} end
local function matrix(a) -- Source's AngleMatrix: pitch, yaw, roll in degrees
    local p,y,r=math.rad(a.p or 0),math.rad(a.y or 0),math.rad(a.r or 0)
    local sp,cp,sy,cy,sr,cr=math.sin(p),math.cos(p),math.sin(y),math.cos(y),math.sin(r),math.cos(r)
    return {{cp*cy,sr*sp*cy-cr*sy,cr*sp*cy+sr*sy},{cp*sy,sr*sp*sy+cr*cy,cr*sp*sy-sr*cy},{-sp,sr*cp,cr*cp}}
end
local function rotate(v,a)
    local m=matrix(a)
    return Vector(m[1][1]*v.x+m[1][2]*v.y+m[1][3]*v.z,m[2][1]*v.x+m[2][2]*v.y+m[2][3]*v.z,m[3][1]*v.x+m[3][2]*v.y+m[3][3]*v.z)
end
local function unrotate(v,a)
    local m=matrix(a)
    return Vector(m[1][1]*v.x+m[2][1]*v.y+m[3][1]*v.z,m[1][2]*v.x+m[2][2]*v.y+m[3][2]*v.z,m[1][3]*v.x+m[2][3]*v.y+m[3][3]*v.z)
end
function V:Rotate(a) local r=rotate(self,a);self.x,self.y,self.z=r.x,r.y,r.z end
function VectorRand() return Vector(math.random()*2-1,math.random()*2-1,math.random()*2-1) end
function math.Rand(a,b) return a+(b-a)*math.random() end
function table.Add(dest,source) for _,v in ipairs(source) do dest[#dest+1]=v end return dest end
FCVAR_ARCHIVE,FCVAR_NOTIFY,FCVAR_REPLICATED=128,256,8192
COLLISION_GROUP_NONE=0;SOLID_VPHYSICS=6;MOVETYPE_VPHYSICS=6;TRANSMIT_ALWAYS=0;DMG_BULLET=2;DMG_BLAST=64
engine={TickCount=function() return math.floor(clock*66) end}

-- Settings as CreateConVar registers them; GetConVar reads the current value.
local setting,registered={}, {}
function GetConVar(name)
    if setting[name]==nil then return nil end
    return {GetInt=function() return math.floor(setting[name]) end,GetFloat=function() return setting[name] end,
        GetBool=function() return setting[name]~=0 end}
end
function CreateConVar(name,default,flags,help,low,high)
    registered[name]={default=default,flags=flags,help=help,min=low,max=high}
    if setting[name]==nil then setting[name]=tonumber(default) end
    return GetConVar(name)
end
local function flagged(flags,flag) for _,f in ipairs(flags or {}) do if f==flag then return true end end return false end

-- Timers run at their due time while the clock advances in 50 ms steps.
local pending,repeating={}, {}
timer={Simple=function(delay,callback) pending[#pending+1]={at=clock+delay,callback=callback} end,
    Create=function(name,interval,_,callback) repeating[name]={interval=interval,next=clock+interval,callback=callback} end}
local function due()
    for _=1,100000 do
        local index,first
        for i,t in ipairs(pending) do if t.at<=clock+1e-9 and (not first or t.at<first.at) then index,first=i,t end end
        if not index then break end
        table.remove(pending,index)
        first.callback()
    end
    for _,t in pairs(repeating) do
        while t.next<=clock+1e-9 do t.next=t.next+t.interval;t.callback() end
    end
end
local function advance(seconds)
    local stop=clock+seconds
    due()
    while clock<stop-1e-9 do clock=math.min(stop,clock+0.05);due() end
end
CurTime=function() return clock end

-- VPhysics: the convex hull of the points, each supporting plane once with the corners of its face.
local function bounds(points)
    local low,high=Vector(math.huge,math.huge,math.huge),Vector(-math.huge,-math.huge,-math.huge)
    for _,p in ipairs(points) do
        low.x,low.y,low.z=math.min(low.x,p.x),math.min(low.y,p.y),math.min(low.z,p.z)
        high.x,high.y,high.z=math.max(high.x,p.x),math.max(high.y,p.y),math.max(high.z,p.z)
    end
    return low,high
end
local function corners(face,normal) -- the face's convex outline, counterclockwise seen from outside
    local axis=math.abs(normal.z)<.9 and Vector(0,0,1) or Vector(1,0,0)
    local u=normal:Cross(axis):GetNormalized()
    local w=normal:Cross(u)
    local flat={}
    for _,p in ipairs(face) do flat[#flat+1]={p=p,x=p:Dot(u),y=p:Dot(w)} end
    table.sort(flat,function(a,b) if a.x~=b.x then return a.x<b.x end return a.y<b.y end)
    local function turn(o,a,b) return (a.x-o.x)*(b.y-o.y)-(a.y-o.y)*(b.x-o.x) end
    local lower,upper={}, {}
    for _,q in ipairs(flat) do
        while #lower>=2 and turn(lower[#lower-1],lower[#lower],q)<=1e-9 do table.remove(lower) end
        lower[#lower+1]=q
    end
    for i=#flat,1,-1 do
        local q=flat[i]
        while #upper>=2 and turn(upper[#upper-1],upper[#upper],q)<=1e-9 do table.remove(upper) end
        upper[#upper+1]=q
    end
    table.remove(lower);table.remove(upper)
    local ring={}
    for _,q in ipairs(lower) do ring[#ring+1]=q.p end
    for _,q in ipairs(upper) do ring[#ring+1]=q.p end
    return ring
end
local function hull(points)
    if type(points)~='table' or #points<4 then return nil end
    local planes,n={},#points
    for i=1,n-2 do for j=i+1,n-1 do for k=j+1,n do
        local normal=(points[j]-points[i]):Cross(points[k]-points[i])
        local length=normal:Length()
        if length>1e-9 then
            normal=normal/length
            local d=normal:Dot(points[i])
            local above,below=false,false
            for m=1,n do
                local s=normal:Dot(points[m])-d
                if s>1e-4 then above=true elseif s<-1e-4 then below=true end
            end
            if not (above and below) then
                if above then normal,d=-normal,-d end
                local known=false
                for _,plane in ipairs(planes) do
                    if plane.normal:Dot(normal)>1-1e-6 and math.abs(plane.d-d)<1e-3 then known=true break end
                end
                if not known then planes[#planes+1]={normal=normal,d=d} end
            end
        end
    end end end
    if #planes<4 then return nil end
    local triangles,volume={},0
    for _,plane in ipairs(planes) do
        local face={}
        for _,p in ipairs(points) do if math.abs(plane.normal:Dot(p)-plane.d)<=1e-4 then face[#face+1]=p end end
        local ring=corners(face,plane.normal)
        for t=2,#ring-1 do
            local a,b,c=ring[1],ring[t],ring[t+1]
            triangles[#triangles+1],triangles[#triangles+2],triangles[#triangles+3]=a,b,c
            volume=volume+a:Dot(b:Cross(c))/6
        end
    end
    if volume<=0 then return nil end
    return {triangles=triangles,volume=volume}
end

local NULL=setmetatable({IsValid=function() return false end},{__index=function() return function() return false end end})
function IsValid(x) return type(x)=='table' and x.IsValid~=nil and x:IsValid()==true end
function SafeRemoveEntity(ent) if IsValid(ent) then ent:Remove() end end
local PHYS={}
PHYS.__index=PHYS
function PHYS:IsValid() return self.entity.valid and self.entity.physics==self end
function PHYS:GetMesh()
    local mesh={}
    for i,p in ipairs(self.shape.triangles) do mesh[i]={pos=Vector(p.x,p.y,p.z)} end
    return mesh
end
function PHYS:GetVolume() return self.shape.volume end
function PHYS:SetMass(mass) self.mass=mass end
function PHYS:GetMass() return self.mass end
function PHYS:SetMaterial(material) self.material=material end
function PHYS:GetMaterial() return self.material end
function PHYS:SetPos(pos) self.entity.pos=Vector(pos.x,pos.y,pos.z) end -- a VPhysics entity follows its object
function PHYS:GetPos() return self.entity.pos end
function PHYS:GetAngles() return self.entity.angles end
function PHYS:EnableMotion(on) self.motion=on end
function PHYS:IsMotionEnabled() return self.motion end
function PHYS:Wake() self.awake=true end
function PHYS:SetVelocity(v) if self.motion then self.velocity=Vector(v.x,v.y,v.z) end end
function PHYS:GetVelocity() return self.velocity end
function PHYS:AddAngleVelocity() end

local created,brushes,effects,welds={}, {}, {}, {}
local index=1000
local BASE={}
function BASE:IsValid() return self.valid end
function BASE:EntIndex() return self.index end
function BASE:GetClass() return self.class end
function BASE:Spawn() if self.Initialize then self:Initialize() end end
function BASE:NetworkVar(kind,_,name)
    local key='nw_'..name
    self[key]=({String='',Float=0,Vector=Vector(),Entity=NULL})[kind]
    self['Get'..name]=function(ent) return ent[key] end
    self['Set'..name]=function(ent,value) ent[key]=value end
end
function BASE:SetPos(p) self.pos=Vector(p.x,p.y,p.z) end
function BASE:GetPos() return self.pos end
function BASE:SetAngles(a) self.angles=Angle(a.p,a.y,a.r) end
function BASE:GetAngles() return self.angles end
function BASE:LocalToWorld(v) return self.pos+rotate(v,self.angles) end
function BASE:WorldToLocal(v) return unrotate(v-self.pos,self.angles) end
function BASE:SetMaterial(material) self.material=material end
function BASE:GetMaterial() return self.material end
function BASE:SetColor(color) self.color=color end
function BASE:GetColor() return self.color end
function BASE:SetRenderMode(mode) self.rendermode=mode end
function BASE:GetRenderMode() return self.rendermode end
function BASE:SetCollisionGroup(group) self.group=group end
function BASE:GetCollisionGroup() return self.group end
function BASE:EnableCustomCollisions() end
function BASE:PhysicsInit() return false end -- a shard has no model to take physics from
function BASE:PhysicsInitConvex(points)
    local shape=hull(points)
    if not shape then self.physics=nil return false end
    self.physics=setmetatable({entity=self,shape=shape,motion=true,awake=false,mass=1,velocity=Vector()},PHYS)
    self.mins,self.maxs=bounds(points)
    return true
end
function BASE:GetPhysicsObject() return self.physics or NULL end
function BASE:SetMoveType() end
function BASE:SetSolid() end
function BASE:DrawShadow() end
function BASE:PhysWake() if self.physics then self.physics.awake=true end end
function BASE:BoundingRadius() return self.mins and (self.maxs-self.mins):Length()*0.5 or 0 end
function BASE:OBBMins() return self.mins or Vector() end
function BASE:OBBMaxs() return self.maxs or Vector() end
function BASE:OBBCenter() return self.mins and (self.mins+self.maxs)*0.5 or Vector() end
function BASE:GetVelocity() return self.physics and self.physics.velocity or Vector() end
function BASE:SetNotSolid(on) self.notsolid=on end
function BASE:ForcePlayerDrop() self.dropped=true end
function BASE:IsPlayerHolding() return false end
function BASE:SetNoDraw(on) self.nodraw=on end
function BASE:EmitSound(name) self.sound=name end
function BASE:TakePhysicsDamage(damage)
    self.pushed=(self.pushed or 0)+1
    local physics=self.physics
    if physics and physics.motion then physics.velocity=physics.velocity+damage:GetDamageForce()*(1/physics.mass) end
end
function BASE:Remove()
    if self.removed then return end
    self.removed=true
    if self.OnRemove then self:OnRemove() end
    self.valid,self.physics=false,nil
end
local function instance(methods,fields)
    return setmetatable(fields,{__index=function(_,key)
        local value=methods[key]
        if value~=nil then return value end
        return BASE[key]
    end})
end

local SHARD
ents={Create=function(class)
    check(class=='procedural_shard','only glass is created')
    index=index+1
    local ent=instance(SHARD,{class=class,index=index,valid=true,pos=Vector(),angles=Angle(),group=COLLISION_GROUP_NONE,
        material='',color={r=255,g=255,b=255,a=255},rendermode=0})
    ent:SetupDataTables()
    created[#created+1]=ent
    return ent
end,FindByClass=function(class)
    local found={}
    for _,ent in ipairs(class=='func_breakable' and brushes or class=='procedural_shard' and created or {}) do
        if ent.valid then found[#found+1]=ent end
    end
    return found
end}
util={AddNetworkString=function() end,Effect=function(name,data)
    check(name=='GlassImpact','glass dust effect');effects[#effects+1]=data.origin
end,IntersectRayWithPlane=function(origin,direction,point,normal)
    local denominator=direction:Dot(normal)
    if denominator==0 then return nil end
    local t=(point-origin):Dot(normal)/denominator
    if t<0 then return nil end
    return origin+direction*t
end}
function EffectData() return {SetOrigin=function(self,p) self.origin=p end} end
constraint={Weld=function(a,b) welds[#welds+1]={a,b} end,RemoveAll=function() end}
net={Start=function() end,WriteEntity=function() end,WriteVector=function() end,WriteBool=function() end,Broadcast=function() end}
concommand={Add=function() end}
Material=function() return {} end
AddCSLuaFile=function() end
file={Exists=function() return false end}
language={Add=function() end}
local world_functions=assert(loadfile(arg[4]))
include=function(path)
    if path=='world_functions.lua' then return world_functions() end
    check(path=='glass_map_geometry.lua','unexpected include '..path)
    return geometry
end
local function load_shard(server)
    SERVER,CLIENT=server,not server
    ENT={}
    assert(loadfile(arg[3]))()
    local loaded=ENT
    ENT=nil
    SERVER,CLIENT=true,false
    return loaded
end
SHARD=load_shard(true)
if registry_file then dofile(registry_path) end
dofile(base..'/lua/autorun/server/rtx_map_glass.lua')

local function fade_start(ent) return ent.GetFadeStart and ent:GetFadeStart() or 0 end
local function loose_pieces() -- solid broken-off pieces that are not fading out, oldest first
    local list={}
    for _,ent in ipairs(created) do
        if ent.valid and not ent.notsolid and fade_start(ent)==0 and (ent.RTX_MAP_DEBRIS or ent:GetOriginalShard():IsValid()) then
            list[#list+1]=ent
        end
    end
    return list
end
local function largest(list)
    local best
    for _,ent in ipairs(list) do if not best or ent:BoundingRadius()>best:BoundingRadius() then best=ent end end
    return best
end
local function generation(ent)
    local depth,parent=0,ent:GetReferenceShard()
    while parent~=NULL do depth,parent=depth+1,parent:GetReferenceShard() end
    return depth
end
local function window(id,half,center) -- a native func_breakable glass pane, thin along x
    local shape={}
    for i,p in ipairs(box(half.x,half.y,half.z)) do shape[i]={pos=p} end
    local object={IsValid=function() return true end,GetMaterial=function() return 'glass' end,
        GetMeshConvexes=function() return {shape} end,GetPos=function() return center end,
        GetAngles=function() return Angle() end,GetVelocity=function() return Vector() end}
    local brush={valid=true,IsValid=function(self) return self.valid end,GetClass=function() return 'func_breakable' end,
        EntIndex=function() return id end,GetPhysicsObject=function() return object end,
        GetColor=function() return {r=255,g=255,b=255,a=255} end}
    brushes[#brushes+1]=brush
    run('OnEntityCreated',brush);advance(0)
    return brush
end
local function shatter(brush) -- the engine breaks the brush; the controller adds its pieces a tick later
    local center=brush:GetPhysicsObject():GetPos()
    run('EntityTakeDamage',brush,{GetDamagePosition=function() return center end,GetDamageForce=function() return Vector(800,0,0) end})
    run('break_breakable',{entindex=brush:EntIndex()})
    advance(0)
end
local shooter={IsValid=function() return true end,GetPos=function() return Vector(0,-300,120) end,
    IsPlayer=function() return true end,ChatPrint=function() end}
local function shoot(ent,kind)
    local at=ent:LocalToWorld(ent:OBBCenter())
    ent:OnTakeDamage({GetDamagePosition=function() return at end,GetAttacker=function() return shooter end,
        GetDamage=function() return 40 end,GetDamageType=function() return kind or DMG_BULLET end,
        GetDamageForce=function() return Vector(0,600,-200) end})
end
local function live_count() local n=0;for _,ent in ipairs(created) do if ent.valid then n=n+1 end end;return n end
local function pieces_count() return GlassRewriteDebris and GlassRewriteDebris.Count() or -1 end

local failures={}
local function scenario(name,body)
    run('PreCleanupMap')
    for _,ent in ipairs(created) do if ent.valid then ent:Remove() end end
    created,brushes,effects,welds,pending={}, {}, {}, {}, {}
    setting.rtx_glass_debris_lifetime,setting.rtx_glass_expensive_shards=120,1
    run('PostCleanupMap')
    local ok,problem=pcall(body)
    if ok then print('scenario passed: '..name) else failures[#failures+1]=name..': '..tostring(problem) end
end

scenario('map window debris is loose physics, pushed by bullets',function()
    shatter(window(301,Vector(.5,60,80),Vector(0,0,100)))
    local pieces=loose_pieces()
    check(#pieces==18,'a window breaks into its 18 pieces: '..#pieces)
    for _,piece in ipairs(pieces) do
        local object=piece:GetPhysicsObject()
        check(piece.RTX_MAP_DEBRIS and object:IsMotionEnabled() and object.awake,'map debris moves: it is never frozen')
        check(piece:GetCollisionGroup()==COLLISION_GROUP_WEAPON,'it collides with the world, props and itself, not with players')
    end
    check(#welds==0,'map debris is not welded')
    check(pieces_count()==18,'the registry counts the pieces')
    -- Within its first quarter second a piece cannot break yet: the bullet only pushes it.
    local target=pieces[1]
    local before=target:GetPhysicsObject():GetVelocity()
    shoot(target);advance(.1)
    check(target.pushed==1 and target:GetPhysicsObject():GetVelocity()~=before,'a bullet pushes a piece (TakePhysicsDamage)')
    check(target.valid and not target.notsolid,'a piece too new to break is only pushed')
    setting.rtx_glass_expensive_shards=0
    shatter(window(302,Vector(.5,60,80),Vector(300,0,100)))
    local all=loose_pieces()
    check(all[#all]:GetCollisionGroup()==COLLISION_GROUP_DEBRIS,'rtx_glass_expensive_shards 0: pieces pass through each other')
end)

scenario("the add-on's own pane breaks into loose fragments",function()
    local pane=ents.Create('procedural_shard')
    pane:SetPos(Vector(0,0,60));pane:SetAngles(Angle(90,0,0))
    pane:SetPhysModel('models/hunter/plates/plate2x2.mdl');pane:SetPhysScale(Vector(1,1,1))
    pane:Spawn();pane:BuildCollision(box(47.45,47.45,1.5));pane:GetPhysicsObject():EnableMotion(false)
    check(pane:GetCollisionGroup()==COLLISION_GROUP_NONE and not pane:GetPhysicsObject():IsMotionEnabled(),
        'an unbroken pane stays frozen and solid, like a window')
    advance(.3);shoot(pane);advance(.2)
    check(pane.valid and pane.notsolid and not pane:GetPhysicsObject():IsMotionEnabled(),'the broken pane is a frozen, hidden placeholder')
    local fragments=0
    for _,ent in ipairs(created) do
        if ent~=pane and ent:GetOriginalShard()==pane then
            fragments=fragments+1
            check(ent:BoundingRadius()>=20,'no fragment below the dust size becomes an entity')
            check(ent:GetCollisionGroup()==COLLISION_GROUP_WEAPON and ent:GetPhysicsObject():IsMotionEnabled(),
                "the pane's fragments are loose physics")
        end
    end
    check(fragments>=2,'the pane breaks into fragments: '..fragments)
    check(#effects>0,'its smallest fragments turn into GlassImpact dust')
    check(pieces_count()==fragments,'the fragments count in the budget')
end)

scenario('map debris breaks again and again until only dust is left',function()
    shatter(window(310,Vector(.5,120,160),Vector(0,0,200)))
    check(#loose_pieces()==18,'a big window breaks into 18 pieces')
    local deepest,rounds=0,0
    while #loose_pieces()>0 and rounds<25 do
        rounds=rounds+1
        advance(.3) -- a piece can break a quarter second after it was made
        for _,piece in ipairs(loose_pieces()) do shoot(piece) end
        advance(.2) -- cracks first, then the break
        for _,ent in ipairs(created) do deepest=math.max(deepest,generation(ent)) end
    end
    check(#loose_pieces()==0,'every piece broke down to dust: '..#loose_pieces()..' left after '..rounds..' rounds')
    check(deepest>=2,'fragments of fragments broke again: depth '..deepest)
    check(#effects>0 and #welds==0,'dust shows as GlassImpact; loose fragments are not welded')
    advance(6) -- a fragment that broke goes after 5 s, an original with its last fragment
    check(live_count()==0,'no hidden placeholder is left behind: '..live_count())
    check(pieces_count()==0,'the budget is empty again')
end)

scenario('fragments count in the 256-piece budget, oldest first',function()
    for i=1,15 do shatter(window(320+i,Vector(.5,200,250),Vector(i*600,0,300))) end
    local first=created[1]
    check(#loose_pieces()==256,'broken windows keep 256 pieces: '..#loose_pieces())
    check(not first.valid,'the oldest pieces went first')
    advance(.3)
    local target,oldest=largest(loose_pieces()),loose_pieces()[1]
    shoot(target);advance(.2)
    local fragments=0
    for _,ent in ipairs(created) do if ent.valid and ent:GetReferenceShard()==target then fragments=fragments+1 end end
    check(target.notsolid and fragments>=2,'a map piece breaks into fragments: '..fragments)
    check(#loose_pieces()==256 and pieces_count()==256,'its fragments count in the budget: '..#loose_pieces())
    check(not oldest.valid,'room for them was made by removing the oldest piece')
end)

scenario('a loose piece breaks from a hard impact, not from falling out of a window',function()
    shatter(window(330,Vector(.5,120,160),Vector(0,0,200)))
    advance(.3)
    local pieces=loose_pieces()
    local piece=largest(pieces)
    local world={IsValid=function() return true end} -- the world's physics object: a PhysObj, no GetClass
    local function land(speed,other)
        piece:PhysicsCollide({Speed=speed,HitPos=piece:GetPos(),HitNormal=Vector(0,0,1),HitEntity=other or NULL,
            HitObject=other and other:GetPhysicsObject() or world,OurOldVelocity=Vector(0,0,-speed),OurNewVelocity=Vector(0,0,speed*.3)})
        advance(.2)
    end
    land(450)
    check(piece.valid and not piece.notsolid,'landing at 450 units/s leaves a piece whole')
    land(900,pieces[1]~=piece and pieces[1] or pieces[2])
    check(piece.valid and not piece.notsolid,'two loose pieces never break each other')
    land(700)
    check(piece.notsolid or not piece.valid,'a hard impact (700 units/s) breaks it again')
end)

scenario('pieces fade out after rtx_glass_debris_lifetime seconds',function()
    local lifetime=registered.rtx_glass_debris_lifetime
    check(lifetime and lifetime.default==120,'rtx_glass_debris_lifetime exists, default 120 s')
    check(flagged(lifetime.flags,FCVAR_ARCHIVE) and flagged(lifetime.flags,FCVAR_REPLICATED),'archived and replicated')
    local start=clock
    shatter(window(340,Vector(.5,120,160),Vector(0,0,200)))
    local first=loose_pieces()
    check(#first==18,'18 pieces')
    advance(60)
    local broken=largest(first)
    shoot(broken);advance(.2)
    local fragments={}
    for _,ent in ipairs(loose_pieces()) do if ent:GetReferenceShard()==broken then fragments[#fragments+1]=ent end end
    check(#fragments>=1,'a piece broke into fragments 60 s in')
    advance(start+119.5-clock)
    check(#loose_pieces()==17+#fragments,'nothing fades before its time: '..#loose_pieces())
    local sample=first[1]~=broken and first[1] or first[2]
    while fade_start(sample)==0 and clock<start+121.5 do advance(.05) end -- the next sweep, once a second
    check(clock<=start+121.05,'pieces fade within a second of their lifetime')
    for _,piece in ipairs(first) do
        if piece~=broken then
            check(piece.valid and fade_start(piece)>0 and not piece.CAN_BREAK,'an expired piece shrinks away and no longer breaks')
        end
    end
    for _,fragment in ipairs(fragments) do check(fade_start(fragment)==0,'younger fragments keep their own lifetime') end
    local made=#created
    shoot(sample);advance(.2)
    check(#created==made and (sample.pushed or 0)>0,'a fading piece is pushed, never broken')
    advance(1)
    for _,piece in ipairs(first) do if piece~=broken then check(not piece.valid,'removed after shrinking for a second') end end
    advance(start+60+123-clock)
    for _,fragment in ipairs(fragments) do check(not fragment.valid,'fragments go at the end of their own lifetime') end
    check(live_count()==0,'the broken piece went with its last fragment: '..live_count())
end)

scenario('rtx_glass_debris_lifetime 0 keeps pieces until cleanup or the budget',function()
    local lifetime=registered.rtx_glass_debris_lifetime
    check(lifetime and lifetime.min==0,'0 is a valid lifetime')
    local sweep=repeating.glass_rewrite_debris_lifetime
    check(sweep and sweep.interval>=1,'one sparse sweep timer, no per-frame scan')
    setting.rtx_glass_debris_lifetime=0
    shatter(window(350,Vector(.5,60,80),Vector(0,0,100)))
    advance(3600)
    check(#loose_pieces()==18,'with lifetime 0 every piece stays: '..#loose_pieces())
    setting.rtx_glass_debris_lifetime=120
    advance(1.1)
    local fading=0
    for _,ent in ipairs(created) do if fade_start(ent)>0 then fading=fading+1 end end
    check(fading==18,'a new lifetime applies to the pieces already lying around: '..fading)
    advance(1.1)
    check(live_count()==0,'and they are gone')
end)

scenario('an expired piece shrinks away in Draw without building or freeing a mesh',function()
    local CLIENT_SHARD=load_shard(false)
    local scales,draws,built,destroyed={},0,0,0
    Mesh=function() built=built+1;return {} end
    render={SetMaterial=function() end,SetColorModulation=function() end,SetBlend=function() end}
    cam={PushModelMatrix=function(m) scales[#scales+1]=m.scale end,PopModelMatrix=function() end}
    local mesh={IsValid=function() return true end,Draw=function() draws=draws+1 end,Destroy=function() destroyed=destroyed+1 end}
    local piece=instance(CLIENT_SHARD,{material='',color={r=255,g=255,b=255,a=255}})
    piece:SetupDataTables()
    piece.RENDER_MESH={Mesh=mesh,Material={}}
    piece.GetWorldTransformMatrix=function() return {scale=1,Scale=function(self,v) self.scale=self.scale*v.x end} end
    piece:Draw()
    check(scales[1]==1 and draws==1,'a piece draws at full size until its lifetime ends')
    piece:SetFadeStart(clock)
    clock=clock+.25;piece:Draw()
    clock=clock+.5;piece:Draw()
    check(math.abs(scales[2]-.75)<1e-6 and math.abs(scales[3]-.25)<1e-6,'an expired piece shrinks over one second')
    clock=clock+.3;piece:Draw()
    check(#scales==3 and draws==3,'nothing is drawn once it has shrunk away')
    check(built==0 and destroyed==0,'only the transform changes: no mesh is built or freed')
end)

assert(#failures==0,#failures..' loose glass scenario(s) failed:\n'..table.concat(failures,'\n'))
print('all glass map assertions passed: '..checks)
