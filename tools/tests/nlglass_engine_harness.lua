-- MIT. Execute the actual G1-A server, wire protocol, entity, tool, menu and client with GMod mocks.
local root,scenario=arg[1],arg[2]
local ffi=require("ffi")
local function check(v,msg) assert(v,msg) end
local function near(a,b,msg) assert(math.abs(a-b)<0.01,(msg or "near")..": "..a.." / "..b) end
local Vec={} Vec.__index=Vec
local function Vector(x,y,z) return setmetatable({x=x or 0,y=y or 0,z=z or 0},Vec) end
function Vec.__add(a,b) return Vector(a.x+b.x,a.y+b.y,a.z+b.z) end
function Vec.__sub(a,b) return Vector(a.x-b.x,a.y-b.y,a.z-b.z) end
function Vec.__unm(a) return Vector(-a.x,-a.y,-a.z) end
function Vec.__mul(a,b) if type(a)=="number" then a,b=b,a end return Vector(a.x*b,a.y*b,a.z*b) end
function Vec.__div(a,b) return a*(1/b) end
function Vec:Dot(b) return self.x*b.x+self.y*b.y+self.z*b.z end
function Vec:Cross(b) return Vector(self.y*b.z-self.z*b.y,self.z*b.x-self.x*b.z,self.x*b.y-self.y*b.x) end
function Vec:LengthSqr() return self:Dot(self) end
function Vec:GetNormalized() local l=math.sqrt(self:LengthSqr()) return l>0 and self/l or Vector() end
local function angle(u,v,n) return {u=u or Vector(1,0,0),v=v or Vector(0,1,0),n=n or Vector(0,0,1)} end
local zero=angle()
function Vec:AngleEx(normal) local u=self:GetNormalized() local n=normal:GetNormalized() return angle(u,n:Cross(u),n) end
local function rotate(p,a) return a.u*p.x+a.v*p.y+a.n*p.z end
local function inverse(p,a) return Vector(p:Dot(a.u),p:Dot(a.v),p:Dot(a.n)) end
local function LocalToWorld(p,pa,o,a) return o+rotate(p,a),angle(rotate(pa.u,a),rotate(pa.v,a),rotate(pa.n,a)) end
local function WorldToLocal(p,pa,o,a) return inverse(p-o,a),angle(inverse(pa.u,a),inverse(pa.v,a),inverse(pa.n,a)) end
local function Color(r,g,b,a) return {r=r,g=g,b=b,a=a or 255} end
local function valid(e) return type(e)=="table" and e.valid~=false and e.valid~=nil end
local function clamp(x,a,b) return math.max(a,math.min(b,x)) end
local entities,classes,nextEntity={}, {},0
local function realm(server)
    local e=setmetatable({},{__index=_G}) e._G=e
    e.SERVER,e.CLIENT=server,not server
    e.Vector,e.Color,e.Angle=Vector,Color,function() return zero end
    e.angle_zero,e.color_white=zero,Color(255,255,255)
    e.LocalToWorld,e.WorldToLocal=LocalToWorld,WorldToLocal
    e.IsValid=valid e.math=setmetatable({Clamp=clamp},{__index=math})
    e.FCVAR_ARCHIVE,e.FCVAR_REPLICATED,e.FCVAR_NOTIFY=1,2,4
    e.MOVETYPE_NONE,e.SOLID_VPHYSICS,e.TRANSMIT_ALWAYS,e.RENDERGROUP_TRANSLUCENT=0,6,2,1
    e.DMG_BULLET,e.DMG_BUCKSHOT,e.DMG_BLAST,e.DMG_CRUSH,e.DMG_CLUB=2,4,8,16,32
    e.TOP,e.FILL=1,5
    e.tick,e.time=100,10 e.queue={} e.out={} e.receivers={} e.cvars={}
    function e.CurTime() return e.time end
    e.engine={TickCount=function() return e.tick end}
    e.file={Exists=function(path) local f=io.open(root.."/"..path,"r") if f then f:close() return true end return false end}
    e.file.Find=function(pattern)
        if pattern=="nlglass/debris*.lua" then return {"debris.lua","debris_render.lua"} end
        if pattern=="nlglass/world*.lua" then return {"world.lua","world_cache.lua"} end
        return {}
    end
    function e.include(path)
        -- G1-B's manager has its own harness (glass_debris_harness.lua); here the public-API stub stands in.
        if path:match("^nlglass/debris") or path:match("^nlglass/world") then return nil end
        return assert(setfenv(assert(loadfile(root.."/"..path)),e))()
    end
    e.sentFiles={}
    function e.AddCSLuaFile(path) e.sentFiles[#e.sentFiles+1]=path end
    local function convar(name,value)
        local c={value=tostring(value)}
        function c:GetFloat() return tonumber(self.value) or 0 end
        function c:GetString() return self.value end
        function c:GetBool() return self.value~="0" end
        function c:GetInt() return math.floor(self:GetFloat()) end
        e.cvars[name]=c return c
    end
    e.CreateConVar,e.CreateClientConVar=convar,convar
    function e.GetConVar(name) return e.cvars[name] end
    e.commands={}
    function e.RunConsoleCommand(name,value) e.commands[#e.commands+1]={name,value} convar(name,value) end
    local namedTimers={}
    e.timer={Simple=function(_,f) e.queue[#e.queue+1]=f end,Create=function(name,_,_,f)
        namedTimers[name]=f e.queue[#e.queue+1]=function() if namedTimers[name]==f then namedTimers[name]=nil f() end end
    end,Remove=function(name) namedTimers[name]=nil end}
    function e.flush()
        for round=1,20 do
            local q=e.queue e.queue={} if #q==0 then return end
            for _,f in ipairs(q) do f() end
        end
        error("timer loop")
    end
    e.hooks={}
    e.hook={Add=function(name,id,f) e.hooks[name]=e.hooks[name] or {} e.hooks[name][id]=f end}
    function e.run(name,...)
        for _,f in pairs(e.hooks[name] or {}) do local r=f(...) if r~=nil then return r end end
    end
    e.util={AddNetworkString=function() end,Effect=function() e.effects=(e.effects or 0)+1 end}
    e.gameevent={Listen=function(name) check(name=="break_breakable","engine break event subscribed") end}
    e.Entity=function(i) return entities[i] end e.Player=function(id) return entities[id] end
    e.LocalPlayer=function() return e.player end
    e.ErrorNoHalt=function(text) e.errorText=text end
    local net={}
    function net.Start(name) e.writing={name=name,tokens={},bits=0} end
    local function write(kind,value,bits)
        if kind=="UInt" or kind=="Int" then
            check(value==math.floor(value),"integer wire field")
            check(kind=="UInt" and value>=0 and value<2^bits or kind=="Int" and value>=-2^(bits-1) and value<2^(bits-1),"wire field bound")
        end
        e.writing.tokens[#e.writing.tokens+1]={kind,value,bits}
        e.writing.bits=e.writing.bits+(bits or (kind=="Vector" and 96 or kind=="Angle" and 48 or kind=="String" and (#value+1)*8 or 32))
    end
    for _,name in ipairs({"UInt","Int","Bool","Vector","Angle","String","Float"}) do
        net["Write"..name]=function(value,bits)
            if name=="Float" then value=tonumber(ffi.new("float",value)) end
            if name=="Vector" then value=Vector(value.x,value.y,value.z) end
            write(name,value,bits or (name=="Bool" and 1 or nil))
        end
        net["Read"..name]=function(bits)
            e.readAt=e.readAt+1 local t=e.reading.tokens[e.readAt]
            check(t and t[1]==name,"wire order: expected "..name)
            if bits then check(t[3]==bits,"wire field width") end
            return t[2]
        end
    end
    local function send(target) e.writing.target=target e.out[#e.out+1]=e.writing e.writing=nil end
    net.Send,net.Broadcast,net.SendToServer=send,send,send
    net.Receive=function(name,f) e.receivers[name]=f end
    e.net=net
    function e.deliver(packet,ply,allowUnread)
        e.reading,e.readAt=packet,0
        check(e.receivers[packet.name],"handler "..packet.name)
        e.receivers[packet.name](packet.bits,ply)
        if not allowUnread then check(e.readAt==#packet.tokens,"all wire fields consumed: "..packet.name) end
    end
    e.ents={FindByClass=function(class)
        local pattern="^"..class:gsub("%*",".*").."$"
        local found={} for _,ent in pairs(entities) do if valid(ent) and ent.class:match(pattern) then found[#found+1]=ent end end return found
    end}
    e.scripted_ents={Register=function(def,name) classes[name]=def end,IsBasedOn=function(name,base)
        while classes[name] do name=classes[name].Base if name==base then return true end end return false
    end}
    e.duplicator={modifiers={},RegisterEntityModifier=function(name,f) e.duplicator.modifiers[name]=f end,
        StoreEntityModifier=function(ent,name,data) ent.modifier={name,data} end}
    e.cleanup={Add=function() end} e.undo={Create=function() end,AddEntity=function() end,SetPlayer=function() end,Finish=function() end}
    e.language={Add=function(key,text) e.phrases=e.phrases or {} e.phrases[key]=text end}
    e.concommand={Add=function(name,f) e.console=e.console or {} e.console[name]=f end}
    e.spawnmenu={AddToolMenuOption=function(...) e.menuArgs={...} end}
    local function panel()
        local p={controls={},texts={}}
        function p:Help(text) self.texts[#self.texts+1]=text end
        local function control(self,label,cvar)
            local c={label=label,cvar=cvar,choices={}}
            function c:SetValue(value) self.value=value end function c:SetEnabled(value) self.enabled=value end
            function c:AddChoice(text,value,selected) self.choices[#self.choices+1]={text,value,selected} end
            function c:ChooseOptionID(index) self.selected=index end
            self.controls[#self.controls+1]=c return c
        end
        p.NumSlider,p.CheckBox,p.ComboBox,p.Button=control,control,control,control
        return p
    end
    e.panel=panel
    e.sound={Play=function() e.sounds=(e.sounds or 0)+1 end}
    e.EffectData=function() return {SetOrigin=function() end,SetNormal=function() end} end
    e.Material=function(name) return name end e.CreateMaterial=function(name) return name end
    e.meshBuilds=0 e.meshDraws=0 e.meshDestroys=0
    e.Mesh=function()
        return {BuildFromTriangles=function(self,t) self.triangles=t e.meshBuilds=e.meshBuilds+1 end,
            Draw=function() e.meshDraws=e.meshDraws+1 end,Destroy=function() e.meshDestroys=e.meshDestroys+1 end}
    end
    e.Matrix=function() return {SetTranslation=function(_,p) e.drawOrigin=p end,SetAngles=function() end} end
    e.cam={PushModelMatrix=function() end,PopModelMatrix=function() end}
    e.render={SetMaterial=function() end,SetBlend=function() end,SetColorModulation=function() end}
    e.debris={} e.impulses={} e.clears=0
    e.NLGlassDebris=setmetatable({Spawn=function(frame,pieces) e.debris[#e.debris+1]={frame=frame,pieces=pieces} end,
        Impulse=function(o,r,s) e.impulses[#e.impulses+1]={o,r,s} end,Clear=function() e.clears=e.clears+1 end,
        Count=function() return #e.debris end,Backend=function() return "none" end,
        Prepare=function() e.prepares=(e.prepares or 0)+1 end},
        {__index=function(_,key) error("private debris API accessed: "..key) end})
    return e
end
local sv=realm(true)
local E={}
local function newEntity(class,options)
    options=options or {} nextEntity=nextEntity+1
    local ent={class=class,id=nextEntity,valid=true,pos=options.pos or Vector(),angles=options.angles or zero,
        velocity=options.velocity or Vector(),color=Color(255,255,255),phys=options.phys,surfaces=options.surfaces,
        flags=options.flags or {},admin=options.admin,inputs={}}
    setmetatable(ent,{__index=function(_,key)
        local def=classes[class]
        while def do if def[key]~=nil then return def[key] end def=classes[def.Base] end
        return E[key]
    end})
    entities[ent.id]=ent return ent
end
function E:GetClass() return self.class end function E:EntIndex() return self.id end
function E:GetPhysicsObject() return self.phys end
function E:GetPos() return self.pos end function E:SetPos(v) self.pos=v end
function E:GetAngles() return self.angles end function E:SetAngles(v) self.angles=v end
function E:GetColor() return self.color end function E:SetColor(v) self.color=v end
function E:GetVelocity() return self.velocity end function E:WorldSpaceCenter() return self.pos end
function E:LocalToWorld(p) return LocalToWorld(p,zero,self.pos,self.angles) end
function E:GetBrushSurfaces() return self.surfaces end
function E:SetModel(m) self.model=m end function E:GetModel() return self.model end
function E:SetMoveType(v) self.moveType=v end function E:SetSolid(v) self.solid=v end
function E:SetNotSolid(v) self.notSolid=v end function E:SetNoDraw(v) self.noDraw=v end
function E:SetTrigger(v) self.trigger=v end function E:UseTriggerBounds(v) self.triggerBounds=v end
function E:EnableCustomCollisions(v) self.custom=v end function E:CollisionRulesChanged() self.collisionChanged=true end
function E:PhysicsDestroy() self.phys=nil end
function E:Fire(name,value,delay,activator,caller) self.inputs[#self.inputs+1]={name,value,delay,activator,caller} end
function E:IsPlayer() return self.flags.player end function E:IsNPC() return self.flags.npc end function E:IsVehicle() return self.flags.vehicle end
function E:IsAdmin() return self.admin end function E:CheckLimit() return self.limit~=false end
function E:SetCreator(p) self.creator=p end function E:AddCount() end
function E:Activate() end
function E:Spawn() if self.Initialize then self:Initialize() end end
function E:Remove() if not self.valid then return end self.valid=false sv.run("EntityRemoved",self) end
local function physics(mass,velocity,material,mesh)
    local p={valid=true,mass=mass or 1,velocity=velocity or Vector(),material=material or "glass",mesh=mesh}
    function p:GetMass() return self.mass end function p:GetVelocity() return self.velocity end
    function p:GetMaterial() return self.material end function p:SetMaterial(v) self.material=v end
    function p:GetMeshConvexes() return self.mesh end function p:EnableMotion(v) self.motion=v end
    function p:EnableCollisions(v) self.collisions=v end
    -- Intentionally has no GetPhysicsObject: a PhysObj is already the physics object.
    return p
end
function E:PhysicsInitMultiConvex(convexes)
    self.physicsBuilds=(self.physicsBuilds or 0)+1
    self.convexes=convexes
    if self.failPhysics then self.phys=nil return false end
    self.phys=physics() return true
end
sv.ents.Create=function(class) return newEntity(class) end
sv.include("autorun/nlglass.lua")
local downloads={} for _,name in ipairs(sv.sentFiles) do downloads[name]=true end
check(downloads["nlglass/debris_render.lua"] and downloads["nlglass/world_cache.lua"],"G1-B supporting files are served to remote clients")
sv.ENT={} sv.include("entities/nlglass_pane/shared.lua")
-- Resolve the entity's relative includes as GMod does.
local originalInclude=sv.include
sv.include=function(path) return originalInclude(path=="shared.lua" and "entities/nlglass_pane/shared.lua" or path) end
sv.include("entities/nlglass_pane/init.lua")
classes.nlglass_pane=sv.ENT sv.include=originalInclude
local S,F,D=sv.NLGlass.Server,sv.NLGlass.Fracture,sv.NLGlass.Damage
local cl=realm(false) cl.cvars=sv.cvars cl.ents=sv.ents
cl.include("autorun/nlglass.lua")
local function network(client,start)
    for i=start or 1,#sv.out do local packet=sv.out[i] if not packet.target or packet.target==client.player then client.deliver(packet) end end
end
local function pane(kind,pos)
    local ent=newEntity("nlglass_pane",{pos=pos})
    ent.NLGlassDefinition=S.Definition({{-48,-32},{48,-32},{48,32},{-48,32}},1,kind or "annealed",1)
    ent:Spawn() return ent,S.byEntity[ent]
end
local function damage(kind,amount,point,attacker,origin)
    local d={kind=kind,amount=amount or 15,point=point or Vector(),attacker=attacker,origin=origin or Vector(1,2,3)}
    function d:IsDamageType(t) return self.kind==t end function d:GetDamage() return self.amount end
    function d:GetDamagePosition() return self.point end function d:GetReportedPosition() return self.origin end
    function d:GetDamageForce() return Vector(0,0,1000) end
    function d:GetAttacker() return self.attacker end function d:GetInflictor() return self.attacker end
    return d
end
local function brush(class,material)
    local front={Vector(-48,-32,0.5),Vector(48,-32,0.5),Vector(48,32,0.5),Vector(-48,32,0.5)}
    local cloud={}
    for _,z in ipairs({-0.5,0.5}) do
        for _,i in ipairs({1,2,3,1,3,4}) do local p=front[i] cloud[#cloud+1]={pos=Vector(p.x,p.y,z)} end
    end
    local face={GetVertices=function() return front end,GetMaterial=function() return "glass/source_window" end}
    return newEntity(class or "func_breakable",{phys=physics(30,Vector(),material or "glass",{cloud}),surfaces={face}})
end
local function piecesSince(start)
    network(cl,start)
    local total=0 for _,call in ipairs(cl.debris) do total=total+#call.pieces end return total
end
if scenario=="damage" then
    for _,kind in ipairs({sv.DMG_BULLET,sv.DMG_BUCKSHOT,sv.DMG_CLUB,sv.DMG_CRUSH}) do
        local ent,r=pane()
        local start=#sv.out+1
        ent:OnTakeDamage(damage(kind,15))
        check(r.state.revision==1 and #F.Cracks(r.state)>0,"damage cause cracks")
        check(sv.run("EntityTakeDamage",ent,damage(kind,15))==nil and r.state.revision==1,"hook does not double-apply SENT damage")
        ent:OnTakeDamage(damage(kind,15)) ent:OnTakeDamage(damage(kind,15))
        check(piecesSince(start)>0,"each damage cause spawns client debris")
    end
elseif scenario=="collision" then
    for _,class in ipairs({"prop_physics","prop_ragdoll"}) do
        local ent,r=pane()
        local hitter=newEntity(class,{phys=physics(120,Vector(0,0,200))})
        local impact=D.FromCollision(r,{HitEntity=hitter,HitObject=hitter.phys,TheirOldVelocity=Vector(0,0,200),OurOldVelocity=Vector(0,0,20),HitPos=Vector()})
        near(impact.energy,0.5*120*180*180,"real hitter mass and relative speed")
        local start=#sv.out+1
        ent:PhysicsCollide({HitEntity=hitter,HitObject=hitter.phys,TheirOldVelocity=Vector(0,0,200),HitPos=Vector()})
        check(r.state.revision==0,"physics rebuild deferred outside callback")
        sv.flush() check(r.state.revision==1,"prop/ragdoll uses unified impact")
        network(cl,1) check(#cl.debris>0,"prop/ragdoll has pieces")
    end
elseif scenario=="bodies" then
    for _,flag in ipairs({"player","npc","vehicle"}) do
        local ent,r=pane()
        local body=newEntity(flag,{velocity=Vector(0,0,200),flags={[flag]=true}})
        if flag=="vehicle" then body.phys=physics(900) end
        local impact=D.FromBody(r,body)
        near(impact.energy,0.5*(flag=="vehicle" and 900 or 85)*200^2,"body mass")
        ent:Touch(body) ent:Touch(body) sv.flush()
        check(r.state.revision==1,"body contact deduplicated")
        network(cl,1) check(#cl.debris>0,"body has pieces")
        local slow=newEntity(flag,{velocity=Vector(0,0,10),flags={[flag]=true}})
        check(D.FromBody(r,slow)==nil,"slow body does not damage")
        body.pos=Vector(0,0,0) check(D.FromBody(r,body)==nil,"a body in the hole meets no ghost glass")
    end
elseif scenario=="scripted" then
    local ent,r=pane()
    local start=#sv.out+1 -- deliberately miss the initial snapshot
    local breaker=newEntity("player",{pos=Vector(40,20,-5),velocity=Vector(0,0,250),flags={player=true}})
    check(sv.run("AcceptInput",ent,"Break",breaker,breaker)==true,"scripted pane break handled")
    check(not valid(ent) and not S.records[r.id],"whole pane removed")
    check(piecesSince(start)>0,"removed pane's break carries independent pre-state without initial snapshot")
    check(cl.debris[1].pieces[1].velocity:LengthSqr()>0,"scripted breaker transfers velocity")
elseif scenario=="native" then
    local ent=brush() local r=S.TrackNative(ent)
    check(r and r.native,"native glass tracked")
    for i=1,4 do sv.run("EntityTakeDamage",ent,damage(sv.DMG_BULLET,15,Vector(20,0,0))) end
    check(#F.Remaining(r.state)>0 and ent.notSolid==nil,"engine retains native health/collision despite high accumulated damage")
    local breaker=newEntity("player",{pos=Vector(20,0,-5),velocity=Vector(0,0,200),flags={player=true}})
    sv.run("AcceptInput",ent,"Break",breaker,breaker)
    sv.run("break_breakable",{entindex=ent.id,userid=breaker.id}) ent:Remove() sv.flush()
    network(cl,1) check(#cl.debris==1,"native event and removal produce exactly one scatter")
    check(cl.debris[1].pieces[1].poly and #cl.debris[1].pieces>0,"native recorded impact pieces")
    local untouched=brush() local r2=S.TrackNative(untouched)
    sv.run("AcceptInput",untouched,"Break",breaker,breaker)
    untouched:Remove() sv.flush() network(cl,#sv.out-1)
    check(r2.broken and r2.lastImpact.x>0,"native removal uses breaker position without recorded damage")
    local nominal=brush() local r3=S.TrackNative(nominal)
    nominal:Remove() sv.flush()
    check(r3.broken and r3.lastImpact.energy>=F.Threshold(r3.state.def),"native no-breaker removal uses nominal energy")
    check(not S.TrackNative(brush("func_breakable","metal")),"non-glass native untouched")
elseif scenario=="map" then
    local ent=brush("func_breakable_surf")
    sv.run("InitPostEntity") local r=S.surfaces[ent]
    check(r and ent.noDraw and ent.notSolid and ent.phys.collisions==false,"surface retained hidden/non-solid")
    check(r.frame.sourceMaterial=="glass/source_window","brush material recorded")
    local p=r.entity
    for i=1,3 do p:OnTakeDamage(damage(sv.DMG_BULLET,15)) end
    check(#ent.inputs==1 and ent.inputs[1][1]=="Shatter","first hole fires original Shatter input")
    local input=ent.inputs[1]
    check(sv.run("AcceptInput",ent,input[1],input[4],input[5])==nil,"engine logic bridge bypasses proxy input")
    check(#F.Remaining(r.state)>0,"partial pane survives logic bridge")
    check(sv.run("AcceptInput",ent,"Break")==true,"map target Break routed to visible pane")
    check(#ent.inputs==1,"map outputs bridge only once")
elseif scenario=="collision_mesh" then
    local ent,r=pane()
    check(#ent.convexes==1 and ent.phys.motion==false,"intact frozen VPhysics")
    for i=1,3 do ent:OnTakeDamage(damage(sv.DMG_BULLET,15)) end
    local polys=F.Remaining(r.state)
    check(#ent.convexes==#polys and #polys>0,"remaining cells alone supply collision")
    for _,convex in ipairs(ent.convexes) do
        local x,y=0,0
        for _,p in ipairs(convex) do x=x+p.x y=y+p.y check(math.abs(p.z)==0.5,"extruded thickness") end
        check(x*x+y*y>1,"no convex fills central opening")
    end
    check(ent.custom and ent.solid==sv.SOLID_VPHYSICS and not ent.notSolid,"custom solid collision enabled")
elseif scenario=="network" then
    local ent,r=pane()
    for i=1,2 do ent:OnTakeDamage(damage(sv.DMG_BULLET,15)) end
    network(cl,1)
    check(#cl.debris==0 and #F.Cracks(cl.NLGlass.Client.records[r.id].state)>0,"networked cracks without debris")
    local late=realm(false) late.cvars=sv.cvars late.ents=sv.ents late.include("autorun/nlglass.lua")
    late.player=newEntity("player",{flags={player=true}})
    sv.run("PlayerInitialSpawn",late.player) sv.flush() late.deliver(sv.out[#sv.out])
    check(sv.out[#sv.out].target==late.player,"actual join hook targets the joining player")
    local lr=late.NLGlass.Client.records[r.id]
    check(lr.state.damage==360000 and #lr.state.impacts==1 and #late.debris==0,"late join receives accumulated history")
    near(lr.state.impacts[1].energy,r.state.impacts[1].energy,"wire energy")
    local start=#sv.out+1 ent:OnTakeDamage(damage(sv.DMG_BULLET,15))
    network(cl,start) network(late,start)
    check(#cl.debris==1 and #late.debris==1 and #cl.debris[1].pieces==#late.debris[1].pieces,"two clients fracture same break")
    for i,piece in ipairs(cl.debris[1].pieces) do
        local other=late.debris[1].pieces[i]
        near(piece.poly[1][1],other.poly[1][1],"two-client polygon") near(piece.velocity.z,other.velocity.z,"two-client velocity")
    end
    late.net.Start("nlglass_sync") late.net.SendToServer()
    sv.deliver(late.out[#late.out],late.player) late.deliver(sv.out[#sv.out])
    local sent=#sv.out sv.deliver(late.out[#late.out],late.player)
    check(#sv.out==sent,"read-only resync is rate limited")
    check(#late.debris==1 and #F.Remaining(late.NLGlass.Client.records[r.id].state)==#F.Remaining(r.state),"partial late-join snapshot does not replay old debris")
    local builds=late.meshBuilds
    late.run("PostDrawTranslucentRenderables",false,false) late.run("PostDrawTranslucentRenderables",false,false)
    check(late.meshBuilds==builds and late.meshDraws>0,"geometry cached across draws")
elseif scenario=="blast_cleanup" then
    local ent,r=pane()
    local grenade=newEntity("grenade",{pos=Vector(1,2,3)})
    local d=damage(sv.DMG_BLAST,100,Vector(),grenade)
    sv.run("EntityTakeDamage",grenade,d) ent:OnTakeDamage(d) S.Blast(d)
    network(cl,1)
    check(#cl.impulses==1 and #cl.debris>0,"one blast event per explosion/tick plus pieces")
    sv.tick=sv.tick+1 S.Blast(d)
    local native=brush() local nr=S.TrackNative(native)
    sv.run("PreCleanupMap") native:Remove() sv.flush()
    check(not nr.broken and next(S.records)==nil,"cleanup suppresses pending native fragments")
    network(cl,1) check(cl.clears>=1 and next(cl.NLGlass.Client.records)==nil,"cleanup clears meshes and debris through API")
    local replacement=brush("func_breakable_surf")
    local survivor=pane() S.Forget(S.byEntity[survivor])
    sv.run("PostCleanupMap") check(S.surfaces[replacement],"cleanup re-registers map windows")
    check(S.byEntity[survivor] and S.byEntity[survivor].state.damage==0,"a surviving scripted pane is reattached after cleanup")
elseif scenario=="save_dupe" then
    local ent,r=pane("tempered") ent:OnTakeDamage(damage(sv.DMG_BULLET,15))
    ent:PreEntityCopy() local copy=newEntity("nlglass_pane") copy:Spawn()
    sv.duplicator.modifiers.NLGlassPane(nil,copy,ent.modifier[2])
    local cr=S.byEntity[copy]
    check(cr.state.def.kind=="tempered" and cr.state.def.thickness==1 and #cr.state.impacts==0,"dupe keeps properties, resets broken state")
    ent:OnRestore() sv.flush() check(S.byEntity[ent].state.damage==0,"save restore starts intact")
    local bad={outline={{0,0},{1,0},{0,1}},thickness=0/0,strength=1,piece_size=8,velocity_transfer=1}
    check(not sv.NLGlass.Geometry.ValidDefinition(bad),"malformed dupe data refused")
    local def=S.Definition({{-48,-32},{48,-32},{48,32},{-48,32}},1,"annealed",0.1)
    local once=sv.NLGlass.Geometry.ValidDefinition(def)
    check(once and sv.NLGlass.Geometry.ValidDefinition(once),"minimum strength remains valid after wire-grid quantization")
    local preset=newEntity("nlglass_tempered_48x48") preset:Spawn()
    check(S.byEntity[preset].state.def.kind=="tempered","spawn-menu preset inheritance")
    sv.run("EntityTakeDamage",preset,damage(sv.DMG_BULLET)) preset:OnTakeDamage(damage(sv.DMG_BULLET))
    check(S.byEntity[preset].state.revision==1,"preset damage not doubled by hook")
elseif scenario=="geometry" then
    local points={Vector(0,0,0.5),Vector(80,0,0.5),Vector(10,50,0.5)}
    local cloud={}
    for _,z in ipairs({-0.5,0.5}) do for _,p in ipairs(points) do cloud[#cloud+1]={pos=Vector(p.x,p.y,z)} end end
    local material={GetName=function() return "glass/triangular" end}
    local ent=newEntity("func_breakable_surf",{pos=Vector(70,-120,300),angles=angle(Vector(0,1,0),Vector(0,0,1),Vector(1,0,0)),
        phys=physics(30,Vector(),"glass",{cloud}),surfaces={{GetVertices=function() return points end,GetMaterial=function() return material end}}})
    S.ReplaceSurface(ent) local r=S.surfaces[ent]
    check(r and #r.state.def.outline==3 and r.frame.sourceMaterial=="glass/triangular","rotated triangle keeps convex outline and IMaterial name")
    near(F.Area(r.state.def.outline),2000,"triangular area") near(r.state.def.thickness,1,"native thickness")
    for _,p in ipairs(points) do near(sv.NLGlass.Geometry.LocalPoint(r.frame,ent:LocalToWorld(p)).z,0.5,"pane +z normal and local frame") end
    local restored=r.entity
    restored:OnRestore() sv.flush()
    check(S.surfaces[ent]==S.byEntity[restored] and ent.noDraw,"save restore retains map output bridge")
    restored:PreEntityCopy() local dupe=newEntity("nlglass_pane") dupe.NLGlassOriginal=ent dupe:Spawn()
    sv.duplicator.modifiers.NLGlassPane(nil,dupe,restored.modifier[2])
    check(S.surfaces[ent].entity==restored and not S.byEntity[dupe].original,"duplicate cannot steal original output bridge")
elseif scenario=="late_entity" then
    local ent,r=pane() ent:SetPos(Vector(100,20,30))
    S.Snapshot(r) local packet=sv.out[#sv.out]
    near(r.frame.origin.x,100,"snapshot refreshes pose without idle polling")
    local builds=ent.physicsBuilds
    entities[ent.id]=nil ent.pos=Vector(50,20,30) -- client entity interpolation is behind the server
    cl.deliver(packet) local cr=cl.NLGlass.Client.records[r.id]
    check(ent.physicsBuilds==builds,"packet can precede networked entity")
    near(cr.localOrigin.x,0,"wire carries actual entity-local frame instead of deriving it from delayed pose")
    entities[ent.id]=ent cl.run("NetworkEntityCreated",ent)
    check(ent.physicsBuilds==builds+1,"late entity receives prediction collision")
    cl.run("PostDrawTranslucentRenderables",false,false) near(cl.drawOrigin.x,50,"pane follows current client entity pose")
    local prop=newEntity("prop_physics") prop.id=ent.id entities[ent.id]=prop
    cl.run("NetworkEntityCreated",prop) check(not prop.physicsBuilds,"reused unrelated entity index cannot acquire glass collision")
elseif scenario=="collision_failure" then
    local ent=newEntity("nlglass_pane") ent.failPhysics=true ent:Spawn()
    check(not valid(ent) and ent.notSolid,"failed collision never leaves a placeholder blocker")
    network(cl,1) check(#cl.debris==1 and #cl.debris[1].pieces>0,"collision failure becomes a full break with pieces")
elseif scenario=="tool_menu" then
    sv.TOOL={} sv.include("weapons/gmod_tool/stools/procedural_glass_tool.lua") local tool=sv.TOOL
    local owner=newEntity("player",{flags={player=true},admin=true})
    tool.GetOwner=function() return owner end
    tool.GetClientInfo=function(_,name) return name=="kind" and "tempered" or "" end
    tool.GetClientNumber=function(_,name,default) return name=="strength" and 2 or default end
    check(tool:RightClick({Hit=true,HitPos=Vector(),HitNormal=Vector(0,0,1)}),"tool creates a pane")
    local ent=entities[nextEntity] local r=S.byEntity[ent]
    check(r.state.def.kind=="tempered" and r.state.def.strength==2 and ent.creator==owner,"tool kind/strength/ownership")
    check(tool:LeftClick({Entity=ent}),"tool updates existing pane")
    local prop=brush("prop_physics") prop.CPPICanTool=function() return false end
    check(not tool:LeftClick({Entity=prop}) and valid(prop),"prop protection respected")
    prop.CPPICanTool=function() return true end
    check(tool:LeftClick({Entity=prop}) and not valid(prop),"tool converts convex prop after collision succeeds")
    cl.player=owner
    cl.run("PopulateToolMenu") check(cl.menuArgs[2]=="Glass Rewrite Remixed" and cl.menuArgs[3]=="GlassSettings","companion settings relocation remains compatible")
    for _,lang in ipairs({"zh-CN","zh-TW","ja","ko","fr","ru"}) do
        cl.CreateConVar("gmod_language",lang)
        check(cl.NLGlass.I18n.L("Glass strength")~="Glass strength","translated menu "..lang)
        local panel=cl.panel() cl.NLGlass.BuildSettings(panel) check(#panel.controls==12,"complete settings page")
    end
    local function settingPacket(index,value)
        cl.net.Start("nlglass_setting") cl.net.WriteUInt(index,4) cl.net.WriteString(value) cl.net.SendToServer()
        return cl.out[#cl.out]
    end
    local outsider=newEntity("player",{admin=false})
    sv.deliver(settingPacket(3,"5"),outsider,true) check(sv.GetConVar("rtx_glass_strength"):GetFloat()==1,"non-admin refused")
    -- The denied handler deliberately consumes no fields; test valid requests directly afterward.
    sv.deliver(settingPacket(3,"5"),owner) check(sv.GetConVar("rtx_glass_strength"):GetFloat()==5,"admin change applied")
    sv.deliver(settingPacket(1,"tempered; quit"),owner) check(sv.GetConVar("rtx_glass_map_kind"):GetString()=="annealed","no command injection")
    sv.deliver(settingPacket(0,""),owner) check(sv.GetConVar("rtx_glass_strength"):GetFloat()==1,"reset restores gameplay defaults")
    cl.out={}
    local panel=cl.panel() cl.NLGlass.BuildSettings(panel)
    panel.controls[3].OnValueChanged(panel.controls[3],7)
    panel.controls[12].DoClick() cl.flush()
    local changes=0
    for _,packet in ipairs(cl.out) do if packet.name=="nlglass_setting" then changes=changes+1 sv.deliver(packet,owner) end end
    check(changes==1 and panel.controls[3].value==1 and panel.controls[1].selected==1,"reset cancels queued edits and refreshes controls")
else error("unknown scenario "..tostring(scenario)) end
check(not sv.hooks.Think and not sv.hooks.Tick,"no server per-tick pane polling")
print("engine "..scenario.." OK")
