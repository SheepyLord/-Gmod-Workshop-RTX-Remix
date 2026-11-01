-- Executes the MIT G1-B manager and helpers with strict engine doubles, without a game.
local base = assert(arg[1])
local ffi=require("ffi")
ffi.cdef[[int QueryPerformanceCounter(int64_t *); int QueryPerformanceFrequency(int64_t *);]]
local counter,frequency=ffi.new("int64_t[1]"),ffi.new("int64_t[1]")
assert(ffi.C.QueryPerformanceFrequency(frequency)~=0)
local period=1/tonumber(frequency[0])
local function wallclock() ffi.C.QueryPerformanceCounter(counter);return tonumber(counter[0])*period end
local checks = 0
local function check(value, message) checks = checks + 1; assert(value, message) end
local V, A = {}, {}
local calls={vectors=0,angles=0,matrices=0,matrixWrites=0,materials=0,transforms=0}
V.__index, A.__index = V, A
function Vector(x,y,z) calls.vectors=calls.vectors+1;return setmetatable({x=x or 0,y=y or 0,z=z or 0},V) end
function Angle(p,y,r) calls.angles=calls.angles+1;return setmetatable({p=p or 0,y=y or 0,r=r or 0},A) end
function V.__add(a,b) return Vector(a.x+b.x,a.y+b.y,a.z+b.z) end
function V.__sub(a,b) return Vector(a.x-b.x,a.y-b.y,a.z-b.z) end
function V.__mul(a,b) return Vector(a.x*b,a.y*b,a.z*b) end
function V.__div(a,b) return a*(1/b) end
function V:LengthSqr() return self.x*self.x+self.y*self.y+self.z*self.z end
function V:Length() return math.sqrt(self:LengthSqr()) end
function V:Cross(b) return Vector(self.y*b.z-self.z*b.y,self.z*b.x-self.x*b.z,self.x*b.y-self.y*b.x) end
function V:GetNormalized() local n=self:Length();return n>0 and self/n or Vector() end
function V:Set(v) self.x,self.y,self.z=v.x,v.y,v.z end
function V:SetUnpacked(x,y,z) self.x,self.y,self.z=x,y,z end
function A:Set(a) self.p,self.y,self.r=a.p,a.y,a.r end
function A:SetUnpacked(p,y,r) self.p,self.y,self.r=p,y,r end
function isnumber(v) return type(v)=="number" end
function isvector(v) return getmetatable(v)==V end
function isangle(v) return getmetatable(v)==A end
function Color(r,g,b,a) return {r=r,g=g,b=b,a=a or 255} end
vector_origin,angle_zero,color_white=Vector(),Angle(),Color(255,255,255)
function LocalToWorld(p,a,o,b) -- Full Source pitch/yaw/roll basis, used to validate transformed meshes.
    calls.transforms=calls.transforms+1
    local pch,yaw,roll=math.rad(b.p),math.rad(b.y),math.rad(b.r)
    local cp,sp,cy,sy,cr,sr=math.cos(pch),math.sin(pch),math.cos(yaw),math.sin(yaw),math.cos(roll),math.sin(roll)
    return o+Vector(cy*cp*p.x+(cy*sp*sr-sy*cr)*p.y+(cy*sp*cr+sy*sr)*p.z,
        sy*cp*p.x+(sy*sp*sr+cy*cr)*p.y+(sy*sp*cr-cy*sr)*p.z,-sp*p.x+cp*sr*p.y+cp*cr*p.z),Angle(a.p+b.p,a.y+b.y,a.r+b.r)
end
function WorldToLocal(p,a,o,b) return p-o,Angle(a.p-b.p,a.y-b.y,a.r-b.r) end
SERVER,CLIENT=false,true
SOLID_VPHYSICS,MOVETYPE_VPHYSICS,COLLISION_GROUP_WORLD,RENDERGROUP_OTHER=6,6,20,10
local clock,dt,convars,events,meshes,entities,draws,logCount,reads,api,mode
local failMesh = false
local function phys()
    return {valid=true,asleep=false,impulses=0,SetMaterial=function() end,SetMass=function() end,
        SetVelocity=function() end,AddAngleVelocity=function() end,Wake=function(self) self.asleep=false end,
        IsAsleep=function(self) return self.asleep end,AddVelocity=function(self) self.impulses=self.impulses+1 end,
        GetMeshConvexes=function()
            local out={};for _,x in ipairs({-1,1})do for _,y in ipairs({-1,1})do for _,z in ipairs({-1,1})do
                out[#out+1]={pos=Vector(x,y,z)}
            end end end;return {out}
        end}
end
function IsValid(v) return type(v)=="table" and v.valid==true end
local function entity(model,temporary)
    local e={valid=true,model=model,temporary=temporary,position=Vector(),angles=Angle(),physics=phys(),
        SetNoDraw=function() end,PhysicsInit=function() end,PhysicsInitConvex=function() end,SetMoveType=function() end,SetSolid=function() end,
        SetCollisionGroup=function(self,v) self.group=v end,SetPos=function(self,v) self.position=v end,SetAngles=function(self,v) self.angles=v end,
        GetPos=function(self) return self.position end,GetAngles=function(self) return self.angles end,
        GetPhysicsObject=function(self) return self.physics end,Remove=function(self) self.valid=false end}
    if model=="models/missing.mdl" then e.physics.valid=false end
    entities[#entities+1]=e;return e
end
function CurTime() return clock end
function RealTime() return clock end
function FrameTime() return dt end
function Material(name) return {name=name} end
function Mesh(material)
    local m={material=material,valid=true,BuildFromTriangles=function(self,v)
        if failMesh then failMesh=false;error("injected GPU build refusal") end
        check(#v%3==0 and #v<=60000,"bounded triangle mesh");self.vertexCount=#v
    end,Destroy=function(self)check(self.valid,"no double mesh destruction");self.valid=false end,
    Draw=function(self)check(self.valid,"never draw destroyed mesh");draws=draws+1 end}
    meshes[#meshes+1]=m;return m
end
function Matrix()
    calls.matrices=calls.matrices+1
    return {SetTranslation=function(self,v)calls.matrixWrites=calls.matrixWrites+1;self.position=v end,
        SetAngles=function(self,v)calls.matrixWrites=calls.matrixWrites+1;self.angles=v end,
        SetScale=function(self,v)calls.matrixWrites=calls.matrixWrites+1;self.scale=v.x end}
end
cam={PushModelMatrix=function(matrix) _G.lastScale=matrix.scale end,PopModelMatrix=function()end}
render={SetMaterial=function()calls.materials=calls.materials+1 end}
function ErrorNoHalt() logCount=logCount+1 end
function include(path) return dofile(base.."/"..path) end
function CreateClientConVar(name,default)
    convars[name]=convars[name] or {value=tonumber(default),GetInt=function(self)return math.floor(self.value)end,
        GetFloat=function(self)return self.value end,GetBool=function(self)return self.value~=0 end}
    return convars[name]
end
function GetConVar(name) return convars[name] end
function RunConsoleCommand(name,value) convars[name].value=tonumber(value) end
function math.Clamp(value,low,high) return math.max(low,math.min(high,value)) end
function SysTime() return arg[3]=="renderperf" and wallclock() or clock end
function LocalPlayer() return {valid=true,GetEyeTrace=function()return {HitPos=Vector()}end} end
local function makeapi()
    local n={bodies={},next=0,imports=0,clears=0,models=0,props=0}
    function n.Init(budget,gravity) check(budget==8192 and gravity==600,"one bounded reserve at map start");return true end
    function n.BeginLoadMap(bytes)
        check(#bytes==1036,"BSP bytes passed from GAME");n.imports=n.imports+1
        n.importWaits=1;return true
    end
    function n.PollLoadMap()
        if n.importWaits>0 then n.importWaits=n.importWaits-1;return false end
        if mode=="badmap" then return nil,"unsupported BSP" end
        return {{model="models/solid.mdl",position={0,0,0},angles={0,0,0},scale=1},
            {model="models/solid.mdl",position={1,0,0},angles={0,0,0},scale=1},
            {model="models/missing.mdl",position={0,0,0},angles={0,0,0},scale=1}}
    end
    function n.LoadMap(bytes) -- also permits a before/after run against the original manager
        n.BeginLoadMap(bytes)
        local props,err
        repeat props,err=n.PollLoadMap() until props~=false
        return props,err
    end
    function n.AddModel(_,convexes)
        check(#convexes==1 and #convexes[1]==8,"deduplicated prop collision")
        if mode=="refusedmodel" then return false end
        n.models=n.models+1;return true
    end
    function n.AddProp() n.props=n.props+1;return true end
    function n.BeginFinishWorld() return true end
    function n.PollFinishWorld() return true end
    function n.FinishWorld() return true end
    function n.Spawn(_,pos,angles)
        check(not n.running,"spawn never touches in-flight world")
        n.next=n.next+1;n.bodies[n.next]={position=pos,angles=angles,asleep=false,dirty=true};return n.next
    end
    function n.Remove(id) check(not n.running,"remove never touches in-flight world");n.bodies[id]=nil;return true end
    function n.Clear() n.running=false;n.bodies={};n.clears=n.clears+1;return true end
    function n.Shutdown() n.running=false;n.bodies={};return true end
    function n.SetGravity() check(not n.running,"gravity only between steps");return true end
    function n.SetCollide(value) check(not n.running,"collide only between steps");n.collide=value;return true end
    function n.BeginStep()
        check(not n.running,"one worker step at a time");n.running=true;n.waits=n.delayStep or 0;return true
    end
    function n.PollStep()
        check(n.running,"poll a started step")
        if n.waits>0 then n.waits=n.waits-1;return false end
        n.running=false
        if n.failStep then return nil,"internal update failure" end
        return true
    end
    function n.Step() return true end
    function n.ReadPoses(rows,changed)
        check(not n.running,"poses only after worker completes")
        local count=0
        for id,b in pairs(n.bodies)do
            if not b.asleep or b.dirty then
                local r=assert(rows[id],"preallocated pose record")
                r[1],r[2],r[3],r[4],r[5],r[6],r[7]=b.position.x,b.position.y,b.position.z,b.angles.p,b.angles.y,b.angles.r,b.asleep
                b.dirty=false;count=count+1;changed[count]=id
            elseif n.poisonUnchanged then
                -- Deliberately stale/poisoned rows outside the returned changed list must be ignored.
                rows[id][1],rows[id][7]=99999,false
            end
        end
        return count
    end
    function n.Impulse()
        check(not n.running,"impulse only between steps")
        for _,b in pairs(n.bodies)do b.asleep,b.dirty=false,true end;n.impulses=(n.impulses or 0)+1;return true
    end
    function n.Stats(out) out.live=0;for _ in pairs(n.bodies)do out.live=out.live+1 end;return true end
    return n
end
local function setup(which)
    if NLGlassDebris then NLGlassDebris.Shutdown() end
    clock,dt,convars,events,meshes,entities,draws,logCount,reads,mode=0,.01,{}, {}, {}, {},0,0,0,which
    local callbacks={}
    hook={Add=function(event,id,fn)
        callbacks[event]=callbacks[event] or {};callbacks[event][id]=fn
        events[event]=function(...)for _,f in pairs(callbacks[event])do f(...)end end
    end,Remove=function(event,id)if callbacks[event]then callbacks[event][id]=nil end end}
    ents={CreateClientProp=function(model) return entity(model,false) end}
    ClientsideModel=function(model) return entity(model,true) end
    if which=="none" then ents.CreateClientProp=nil end
    file={Size=function(path,realm)check(path=="maps/gm_fixture.bsp" and realm=="GAME","map read only from GAME");return 1036 end,
        Read=function()reads=reads+1;return string.rep("x",1036)end}
    game={GetMap=function()return "gm_fixture"end}
    api=makeapi()
    _G.require=function(name)check(name=="nlglass","only own client module required");if which=="missing" or which=="none" then error("missing module") end;return api end
    CreateClientConVar("sv_gravity","600")
    NLGlassDebris=nil
    return dofile(base.."/nlglass/debris.lua")
end
local function tick(amount) dt=amount or .01;clock=clock+dt;events.Think() end
local function draw() draws=0;events.PostDrawTranslucentRenderables(false,false);return draws end
local function set(name,value)convars["rtx_glass_debris_"..name].value=value end
local frame={origin=Vector(10,10,20),angles=Angle(),material="glass/fixture"}
local function fragments(n)
    local t={};for i=1,n do t[i]={poly={{-1,-1},{1,-1},{1,1},{-1,1}},thickness=.3,velocity=Vector(),spin=Vector(),seed=i}end;return t
end
local function settle()
    for _,b in pairs(api.bodies)do b.asleep,b.dirty=true,true end
    for _,e in ipairs(entities)do e.physics.asleep=true end
    tick(.01);tick(.21);for _=1,4 do tick() end
end
if arg[3]=="perf" then
    local D=setup("jolt");set("budget",4000);set("lifetime",0)
    local begin=os.clock();D.Spawn(frame,fragments(4000))
    local spawned=(os.clock()-begin)*1000
    for _=1,100 do tick() end
    begin=os.clock();for _=1,200 do tick() end
    local active=(os.clock()-begin)*5
    for _,b in pairs(api.bodies)do b.asleep,b.dirty=true,true end
    for _=1,200 do tick() end
    begin=os.clock();for _=1,1000 do tick() end
    local settled=(os.clock()-begin)
    local s=D.Stats()
    print(string.format("G1-B Lua benchmark pieces=%d spawn_cpu_ms=%.3f active_mean_ms=%.4f settled_mean_ms=%.4f merged=%d batches=%d",
        D.Count(),spawned,active,settled,s.merged,s.batches))
    D.Shutdown();return
end
if arg[3]=="renderperf" then
    -- Same manager, mock physics and camera for before/after comparisons. No engine/GPU timings.
    local D=setup("jolt");set("budget",2000);set("lifetime",0)
    for i=0,49 do
        D.Spawn({origin=Vector(128+(i%10)*72,128+math.floor(i/10)*72,32),angles=Angle(),material=frame.material},fragments(40))
    end
    for _=1,40 do tick() end
    local function bench(label,n)
        collectgarbage("collect")
        for k in pairs(calls)do calls[k]=0 end
        local before=collectgarbage("count")
        collectgarbage("stop")
        local times,total,worst={},0,0
        for i=1,n do
            local t=wallclock();tick();draw();t=(wallclock()-t)*1000
            times[i],total,worst=t,total+t,math.max(worst,t)
        end
        local kb=collectgarbage("count")-before
        collectgarbage("restart")
        table.sort(times)
        local s=D.Stats()
        print(string.format("G1-B renderperf %s frames=%d live=%d merged=%d batches=%d draws=%d mean_ms=%.4f p99_ms=%.4f max_ms=%.4f alloc_KiB=%.1f vectors=%d angles=%d matrix_writes=%d materials=%d transforms=%d",
            label,n,D.Count(),s.merged,s.batches,draws,total/n,times[math.ceil(n*.99)],worst,kb,calls.vectors,calls.angles,calls.matrixWrites,calls.materials,calls.transforms))
    end
    bench("moving",240)
    for _,b in pairs(api.bodies)do b.asleep,b.dirty=true,true end
    bench("settling",240)
    bench("settled",240)
    D.Shutdown();return
end
local D=setup("jolt")
set("budget",3);D.Spawn(frame,fragments(3));check(D.Count()==3 and D.Stats().pending==3,"pending import queues bounded pieces")
tick();tick();tick()
check(D.Backend()=="jolt" and api.models==1 and api.props==2 and D.Stats().skipped_models==1,"unique solid prop collision and missing-model skip")
check(draw()==3,"moving pieces use individual meshes")
check(meshes[1].vertexCount==36,"both faces and four edges of a quad")
settle();check(D.Stats().merged==3 and D.Stats().batches==1 and draw()==1,"settled area draws one merged mesh")
local rebuilds=D.Stats().rebuilds;tick(.2);check(D.Stats().rebuilds==rebuilds,"unchanged area never rebuilt")
D.Impulse(Vector(10,10,20),32,100);check(draw()==3,"impulse invalidates affected static chunk immediately")
tick();check(api.impulses==1 and D.Stats().sleeping==0,"queued native wake reaches manager")
set("budget",2);tick();check(D.Count()==2 and api.bodies[1]==nil,"budget drops oldest first")
settle();D.Spawn(frame,fragments(1));tick();check(D.Count()==2 and api.bodies[2]==nil,"spawning evicts oldest and invalidates batch")
set("budget",8);D.Spawn(frame,fragments(6));tick();check(D.Count()==8 and reads==1 and api.imports==1,"increasing budget never reimports map")
set("lifetime",0);tick(500);check(D.Count()==8,"zero lifetime lasts until cleanup")
D.Clear();check(D.Count()==0 and api.clears==1,"Clear removes native bodies and merged geometry")
for _,m in ipairs(meshes)do check(not m.valid,"Clear frees every owned mesh") end
set("lifetime",2);D.Spawn(frame,fragments(1));settle();tick(.9)
check(D.Count()==1 and D.Stats().merged==0,"last second unmerges for transform shrink")
draw();check(lastScale>0 and lastScale<1,"expiry shrinks transform with opaque material")
tick(1);check(D.Count()==0,"expiry removes piece")
set("lifetime",0);D.Spawn(frame,fragments(4));tick();api.failStep=true;tick()
check(D.Backend()=="vphysics" and D.Count()==4 and logCount==1,"runtime failure migrates live pieces to fallback")
events.PreCleanupMap();check(D.Count()==0,"cleanup clears manager")

D=setup("missing");set("budget",200);D.Spawn(frame,fragments(100))
check(D.Backend()=="vphysics" and D.Count()==64 and logCount==1,"missing module selects 64-piece Source fallback")
for _,e in ipairs(entities)do if e.valid then check(e.group==COLLISION_GROUP_WORLD,"fallback never collides with gameplay bodies") end end
settle();check(D.Stats().merged==64,"fallback sleeping pieces also batch")
D.Impulse(Vector(10,10,20),32,100);check(draw()==64,"fallback impulse invalidates batching")
for _,e in ipairs(entities)do if e.valid then check(e.physics.impulses==1,"fallback explosion wakes and pushes") end end
set("budget",2);tick();check(D.Count()==2,"fallback respects smaller player budget")
D.Spawn(frame,fragments(10));check(D.Count()==2 and logCount==1,"failure logs once per map")
events.PreCleanupMap();check(D.Count()==0,"fallback Clear removes client props")
for _,e in ipairs(entities)do check(not e.valid,"no fallback entity leaked") end

D=setup("badmap");D.Spawn(frame,fragments(3));tick();tick();D.Spawn(frame,fragments(1))
check(D.Backend()=="vphysics" and reads==1 and logCount==1,"failed map imports once and falls back")
D=setup("none");D.Spawn(frame,fragments(3));tick();check(D.Backend()=="none" and D.Count()==0,"no physics backend creates no pieces")
D=setup("jolt");set("budget",0);D.Spawn(frame,fragments(3));check(D.Count()==0 and reads==0,"budget zero avoids native startup")
set("budget",3)
D.Spawn(frame,{{poly={{0,0},{1,0},{2,0}},thickness=1},{poly={{0,0},{1,0},{1,1}},thickness=0/0}})
check(D.Count()==0,"degenerate and nonfinite polygons refused")
D.Spawn({origin=Vector(0/0,0,0),angles=Angle()},fragments(1));check(D.Count()==0,"nonfinite frame refused")
D.Shutdown()

D=setup("refusedmodel");D.Prepare();tick();tick();tick()
check(D.Backend()=="jolt" and D.Stats().skipped_models==2 and api.props==0 and logCount==0,
    "refused prop model is counted without failing the imported world")
D.Shutdown()

D=setup("jolt");set("budget",600);set("lifetime",0)
D.Spawn(frame,fragments(2));tick();tick();tick();settle()
local oldBatch=meshes[#meshes]
local revision=D.Stats().rebuilds
api.poisonUnchanged=true;tick()
check(D.Stats().pose_updates==0 and D.Stats().merged==2 and draw()==1,
    "unchanged pose rows are ignored and fully sleeping worlds do not dispatch workers")
api.poisonUnchanged=false
D.Spawn(frame,fragments(1));tick()
for _,b in pairs(api.bodies)do b.asleep,b.dirty=true,true end
tick();failMesh=true;tick(.21)
check(oldBatch.valid and D.Stats().merged==2,"failed replacement retains old valid pile geometry")
tick(1.1)
check(oldBatch.valid and D.Stats().merged==3 and draw()==1,"replacement swaps only after success and defers old GPU resource release")
tick();check(not oldBatch.valid,"retired mesh is released on a later frame")
oldBatch,revision=meshes[#meshes],D.Stats().rebuilds
D.Spawn(frame,fragments(500))
for _=1,10 do tick() end
check(D.Stats().pending==0,"large arrivals are bounded and drained across frames")
for _,b in pairs(api.bodies)do b.asleep,b.dirty=true,true end
tick();tick(.21)
check(oldBatch.valid and D.Stats().rebuilds==revision,"old valid pile remains during incremental replacement")
local frames=0
repeat
    tick();frames=frames+1
    check(D.Stats().rebuild_vertices<=1800,"pile transformation work is capped per frame")
until D.Stats().rebuilds>revision or frames>30
check(frames>1 and frames<=30 and D.Stats().merged==503 and draw()==1,
    "large pile replaces old meshes atomically after bounded work across frames")
tick();check(not oldBatch.valid,"publication defers mesh destruction until the next frame")
local batchCount=D.Stats().batches
api.bodies[1].asleep,api.bodies[1].dirty=false,true;tick()
check(draw()==503 and draw()>batchCount,"a wake retires its affected consolidated chunk without stale duplicate geometry")
api.delayStep=3;tick()
local oldCount=D.Count()
D.Spawn(frame,fragments(3));D.Impulse(Vector(10,10,20),32,10);set("budget",400)
tick();tick()
check(D.Count()==400 and D.Backend()=="jolt" and D.Stats().pending==3,
    "spawn removal and impulse queue while worker polls pending without touching Jolt")
for _=1,10 do tick() end
check(D.Count()==400 and D.Stats().pending==0 and api.impulses==1,"deferred mutations drain after completion")
events.PreCleanupMap();check(D.Count()==0,"cleanup joins in-flight work and releases all stages")
for _,m in ipairs(meshes)do check(not m.valid,"no old or staging mesh leaks after cleanup") end
D.Shutdown()

-- Transformed positions/normals match Source's complete pitch/yaw/roll basis. Scratch survives
-- an upload and is reused at a different pose/color, without per-vertex userdata on the next pass.
local geometry=include("nlglass/debris_mesh.lua")
local g=assert(geometry.Geometry({{-2,-1},{2,-1},{2,1},{-2,1}},.6,color_white))
local p={geometry=g,position=Vector(10,-20,30),angles=Angle(13,27,39),color=color_white}
local out,pool={},{}
geometry.Transformed(p,out,pool)
for i,v in ipairs(g.vertices)do
    local expected=LocalToWorld(v.pos,angle_zero,p.position,p.angles)
    local normal=LocalToWorld(v.normal,angle_zero,vector_origin,p.angles)
    check((out[i].pos-expected):Length()<.00001 and (out[i].normal-normal):Length()<.00001,
        "pooled vertex transform preserves Source winding, normals and rotation")
end
p.position:SetUnpacked(-30,80,4);p.color=Color(20,40,60,80)
local vectorCount=calls.vectors
geometry.Transformed(p,{},pool)
check(calls.vectors==vectorCount and pool[1].color==p.color,"second settled upload reuses every vertex and honors tint/alpha")

D=setup("jolt");set("budget",2000);set("lifetime",0)
for i=0,49 do
    D.Spawn({origin=Vector(-400+(i%10)*80,-160+math.floor(i/10)*80,i%2==0 and -.1 or .1),angles=Angle(),
        material=frame.material,color=Color(100+i,150,200,200+i)},fragments(40))
end
for _=1,40 do tick() end
for _,b in pairs(api.bodies)do b.asleep,b.dirty=true,true end
for _=1,140 do
    tick();check(D.Stats().rebuild_vertices<=1800,"consolidation never transforms over 1800 vertices/frame")
end
local s=D.Stats()
check(s.merged==2000 and s.batches==4 and draw()==4,"2000 differently tinted pieces around grid zero consolidate into four draws")
check(s.rebuild_pool_vertices<=24000,"one bounded scratch pool is shared by all areas and uploads")
revision=s.rebuilds;for _=1,120 do tick() end
check(D.Stats().rebuilds==revision,"stable 2000-piece piles schedule no rebuilds")
vectorCount=calls.vectors
set("budget",1900)
for _=1,140 do tick() end
check(D.Stats().merged==1900 and D.Stats().batches==3 and draw()==3,"removal reconsolidates surviving pieces without stale/duplicate members")
check(calls.vectors==vectorCount,"rebuilding a warmed pile allocates no new vertex vectors")
D.Clear()
for _,m in ipairs(meshes)do check(not m.valid,"Clear releases published, canceled and retired consolidated meshes") end
D.Shutdown()

if arg[2] then
    -- Execute the real performance probe too: settings restore, lifecycle and cancellation.
    D=setup("jolt");set("budget",7);set("lifetime",12)
    for _,cv in pairs(convars)do cv.GetString=function(self)return tostring(self.value)end end
    NL_GLASS_PROBE_COUNT,NL_GLASS_PROBE_SECONDS,NL_GLASS_PROBE_ORIGIN=4,5,Vector()
    dofile(arg[2]);tick(.1);tick(.1);tick(.1);tick(.1);tick(2.1);tick(5.1);tick(5.1);tick(10.1);tick(10.1)
    check(NLGlassDebrisProbe==nil and D.Count()==0,"probe completes and clears cosmetic pieces")
    check(convars.rtx_glass_debris_budget.value==7 and convars.rtx_glass_debris_lifetime.value==12,"probe restores temporary convars")
    dofile(arg[2]);set("lifetime",23);NLGlassDebrisProbe.Cancel()
    check(convars.rtx_glass_debris_lifetime.value==23,"probe preserves an intervening player edit")
    D.Shutdown()
end
print("all glass debris assertions passed: "..checks)
