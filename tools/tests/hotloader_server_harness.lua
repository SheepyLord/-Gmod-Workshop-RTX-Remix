-- R19: Model Hotloader's server and client Lua under LuaJIT, with the game's API stubbed: removing
-- and replacing another player's character (review L-02), the reach of a prop attachment (L-07),
-- the collision mesh pace (L-08) and the remote collision shapes the module drops (MH-05).
-- One scenario per run; prints PASS <scenario>.
-- usage: luajit hotloader_server_harness.lua <scenario> <lua/mmdhl folder> <slices file>
-- The slices file holds production code cut out of files this harness cannot load whole:
-- sharing.lua's mmdhl.CanEdit and mmdhl.OwnsEntity, carrier.lua's collision mesh receiver.
local scenario,folder,slices=arg[1],arg[2],arg[3]
local function noop() end
local function check(ok,why) if not ok then error('FAIL '..scenario..': '..why,2) end end
local clock=1000
function CurTime() return clock end RealTime=CurTime SysTime=CurTime
function isnumber(v) return type(v)=='number' end function istable(v) return type(v)=='table' end
function isstring(v) return type(v)=='string' end function isfunction(v) return type(v)=='function' end
local V={} V.__index=V
function Vector(x,y,z) return setmetatable({x=x or 0,y=y or 0,z=z or 0},V) end
V.__sub=function(a,b) return Vector(a.x-b.x,a.y-b.y,a.z-b.z) end
V.__add=function(a,b) return Vector(a.x+b.x,a.y+b.y,a.z+b.z) end
V.__mul=function(a,s) return Vector(a.x*s,a.y*s,a.z*s) end
function V:Length() return math.sqrt(self.x^2+self.y^2+self.z^2) end
function V:DistToSqr(o) local d=self-o return d.x^2+d.y^2+d.z^2 end
function V:Unpack() return self.x,self.y,self.z end
function Angle(p,y,r) return {p=p or 0,y=y or 0,r=r or 0} end
function table.Copy(t) if type(t)~='table' then return t end local c={} for k,v in pairs(t) do c[k]=table.Copy(v) end return c end
local hooks,receivers,sent={}, {}, {}
hook={Add=function(event,id,fn) hooks[event]=hooks[event] or {} hooks[event][id]=fn end,Remove=noop,
 Run=function(event,...) for _,fn in pairs(hooks[event] or {}) do local r=fn(...) if r~=nil then return r end end end}
local reads={}
local function read(default) if #reads>0 then return table.remove(reads,1) end return default end
net={Receive=function(name,fn) receivers[name]=fn end,Start=function(name) sent[#sent+1]=name end,Send=noop,SendToServer=noop,Broadcast=noop,
 ReadString=function() return read('') end,ReadBool=function() return read(false) end,ReadFloat=function() return read(0) end,
 ReadUInt=function() return read(0) end,ReadInt=function() return read(0) end,ReadEntity=function() return read(NULL) end,
 ReadVector=function() return read(Vector()) end,ReadAngle=function() return read(Angle()) end,ReadData=function() return read('') end}
for _,name in ipairs({'WriteString','WriteBool','WriteFloat','WriteUInt','WriteInt','WriteEntity','WriteData','WriteVector','WriteAngle'}) do net[name]=noop end
local function receive(name,ply,...) reads={...} receivers[name](0,ply) reads={} end
local function count(name) local n=0 for _,s in ipairs(sent) do if s==name then n=n+1 end end return n end
util={AddNetworkString=noop,TableToJSON=function() return '[]' end,JSONToTable=function() return {} end,Compress=function(s) return s end,Decompress=function(s) return s end}
duplicator={RegisterEntityClass=noop,RegisterConstraint=noop,DoGeneric=noop}
cleanup={Register=noop} timer={Create=noop,Remove=noop,Simple=noop}
undo={Create=noop,AddEntity=noop,SetPlayer=noop,Finish=noop,SetCustomUndoText=noop}
function include() end function GetConVar() return {GetBool=function() return true end,GetInt=function() return 1 end} end
local properties={}
gamemode={Call=function(name,p,property) if name=='CanProperty' then properties[#properties+1]=property end return nil end}
local E={} E.__index=function(_,k) local v=rawget(E,k) if v~=nil then return v end if type(k)=='string' and k:find('^[A-Z]') and not k:find('^MMD') then return noop end end
function IsValid(e) return type(e)=='table' and e.valid~=false end
NULL=setmetatable({valid=false},E)
local registry={}
local function entity(kind,fields) local e=setmetatable(fields or {},E) e.kind=kind registry[#registry+1]=e e.index=#registry e.pos=e.pos or Vector() return e end
function Entity(i) return registry[i] or NULL end
function E:IsPlayer() return self.kind=='player' end function E:IsWorld() return false end
function E:GetClass() return self.kind end function E:IsAdmin() return self.admin==true end
function E:GetCreator() return self.creator end function E:Remove() self.removed=true end
function E:EyePos() return self.pos end function E:GetPos() return self.pos end function E:NearestPoint() return self.pos end
function E:WorldSpaceCenter() return self.pos end function E:GetBoneCount() return 4 end function E:EntIndex() return self.index end
mmdhl={native={},L=function(key) return key end,IsMMD=function() return true end,GetInstance=function() return 0 end}
local function cut(name)
 local text=assert(io.open(slices,'rb')):read('*a')
 return text:match('%-%- slice '..name..'\r?\n(.-)%-%- end '..name)
end
assert(loadstring(cut('sharing')))() -- mmdhl.CanEdit and mmdhl.OwnsEntity
local owner,other,admin=entity('player'),entity('player'),entity('player',{admin=true})

if scenario=='remove' then
 dofile(folder..'/server.lua')
 local spawned={}
 mmdhl.Spawn=function(_,id) spawned[#spawned+1]=id end
 local ragdoll=entity('prop_ragdoll',{creator=owner,MMDOptions={}})
 -- Another player: neither removed nor replaced, and the remover property is what is asked.
 receive('mmdhl_action',other,'remove','',ragdoll.index,'')
 check(not ragdoll.removed,'another player removed a character they do not own')
 check(table.concat(properties,','):find('remover',1,true),'remove was not checked as the remover property: '..table.concat(properties,','))
 receive('mmdhl_action',other,'replace',string.rep('a',64),ragdoll.index,'')
 check(#spawned==0,'another player replaced a character they do not own')
 -- Its owner and an admin may.
 receive('mmdhl_action',owner,'replace',string.rep('a',64),ragdoll.index,'') check(#spawned==1,'the owner could not replace their character')
 receive('mmdhl_action',owner,'remove','',ragdoll.index,'') check(ragdoll.removed,'the owner could not remove their character')
 local second=entity('prop_ragdoll',{creator=owner})
 receive('mmdhl_action',admin,'remove','',second.index,'') check(second.removed,'an admin could not remove a character')
 -- Prop protection's owner (CPPI) decides where it is installed.
 local guarded=entity('prop_ragdoll',{creator=other}) function guarded:CPPIGetOwner() return owner end
 receive('mmdhl_action',other,'remove','',guarded.index,'') check(not guarded.removed,'the creator removed what prop protection says another player owns')
 -- Other edits stay with CanProperty, as before: a pose change is still applied.
 local posed={} mmdhl.SetManualBonePose=function(ent) posed[#posed+1]=ent end
 local third=entity('prop_ragdoll',{creator=owner})
 receive('mmdhl_action',other,'bone','',third.index,'{}') check(#posed==1,'an edit other than remove or replace was refused')
elseif scenario=='attach' then
 local loads,notices={}, {}
 local P={native={},Info={},Pins={},Loading={},LastUse={},Notice=noop,CanonicalScale=function(s) return s end,ValidScale=function() return true end,
  FiniteVector=function() return true end,FiniteAngle=function() return true end,ValidID=function() return true end,CanUse=function() return true end,
  Load=function(id) loads[#loads+1]=id end}
 game={SinglePlayer=function() return false end}
 mmdhl.props=P mmdhl.approved={props={[string.rep('b',64)]={name='Prop'}}} mmdhl.cleanupGeneration=0
 dofile(folder..'/props/server.lua')
 -- The notice's text is the one string the refusal writes.
 local lastNotice net.WriteString=function(text) lastNotice=text end
 owner.pos=Vector(0,0,0)
 local near=entity('npc',{pos=Vector(1000,0,0)}) local far=entity('npc',{pos=Vector(5000,0,0)})
 receive('mmdhl_prop_attach',owner,'attach',far,NULL,string.rep('b',64),-1,Vector(),Angle(),1)
 check(#loads==0 and lastNotice=='props.attach.aim_target','a prop was attached to a target out of reach')
 clock=clock+1
 receive('mmdhl_prop_attach',owner,'attach',near,NULL,string.rep('b',64),-1,Vector(),Angle(),1)
 check(#loads==1,'a prop could not be attached to a target within reach')
elseif scenario=='mesh' then
 assert(loadstring(cut('carrier')))() -- the collision mesh receiver
 local function body() return {GetMeshConvexes=function() return {} end} end
 local function ragdoll() local e=entity('prop_ragdoll') function e:GetPhysicsObjectCount() return 18 end function e:GetPhysicsObjectNum() return body() end
  function e:GetNW2String() return '' end return e end
 local a,b=ragdoll(),ragdoll()
 for _=1,5 do receive('mmdhl_collision_mesh',owner,a) end
 check(count('mmdhl_collision_mesh')==1,'collision meshes were not paced: '..count('mmdhl_collision_mesh'))
 clock=clock+.3 receive('mmdhl_collision_mesh',owner,a) check(count('mmdhl_collision_mesh')==1,'the same entity was answered again within 1.5 s')
 receive('mmdhl_collision_mesh',owner,b) check(count('mmdhl_collision_mesh')==2,'another entity was not answered')
 receive('mmdhl_collision_mesh',owner,a) check(count('mmdhl_collision_mesh')==2,'a player was answered faster than four times a second')
 clock=clock+1.6 receive('mmdhl_collision_mesh',owner,a) check(count('mmdhl_collision_mesh')==3,'the entity was not answered after its pause')
 receive('mmdhl_collision_mesh',other,b) check(count('mmdhl_collision_mesh')==4,'one player\'s pace held up another')
elseif scenario=='scene' then
 -- The client: shapes the module dropped are asked for again when a frame names them.
 SERVER,CLIENT=false,true
 game={SinglePlayer=function() return false end}
 -- Shape requests are the client's command 1 (net.WriteUInt(1,2)).
 local requested={} local publish={true}
 net.WriteUInt=function(value,bits) if bits==2 and value==1 then requested[#requested+1]=true end end
 local accepted={}
 mmdhl.native={AcceptSceneGeometry=function(id) accepted[#accepted+1]=id return publish.accept~=false or nil,publish.accept==false and 'refused' or nil end,
  PublishRemoteScene=function() return publish[1],publish[2] end,ClearRemoteScene=noop}
 local character=entity('mmdhl_ragdoll') character.pos=Vector()
 function character:BoundingRadius() return 10 end
 mmdhl.Entities=function() return {character} end mmdhl.SceneKinds=function() return 1 end mmdhl.GetCollisionFlags=function() return 1 end
 mmdhl.GetInstance=function() return 1 end
 function LocalPlayer() return owner end
 function V:Distance(o) return math.sqrt(self:DistToSqr(o)) end
 dofile(folder..'/scene_sharing.lua')
 local key=string.rep('c',64)
 local frames={}
 util.JSONToTable=function(s) if frames[s] then return frames[s] end local k=s:match('^%["(%x+)"%]$') if k then return {k} end end
 local function deliver(sequence)
  frames['f'..sequence]={timestamp=sequence,sequence=sequence,objects={{id=1,shape=key,bytes=48,position={0,0,0},rotation={0,0,0,1}}}}
  local data='f'..sequence
  reads={0,sequence,1,1,#data,data} receivers.mmdhl_scene() reads={}
 end
 local function chunk() reads={1,key,0,true,48,string.rep('x',48)} receivers.mmdhl_scene() reads={} end
 hooks.Think['MMDHL.SceneSubscription']() -- subscribes: active
 deliver(1) check(#requested==1,'the named shape was not asked for')
 chunk() check(#accepted==1,'the shape did not reach the module')
 -- The module answers that it dropped the shape: the next frame naming it asks again.
 publish={true,'["'..key..'"]'} mmdhl.UpdateRemoteScene() publish={true}
 deliver(2) check(#requested==2,'a shape the module dropped was not asked for again')
 -- A shape the module refuses waits ten seconds before it is asked for again.
 publish.accept=false chunk() publish.accept=nil
 deliver(3) check(#requested==2,'a refused shape was asked for again at once')
 clock=clock+11 deliver(4) check(#requested==3,'a refused shape was never asked for again')
else
 error('unknown scenario '..tostring(scenario))
end
print('PASS '..scenario)
