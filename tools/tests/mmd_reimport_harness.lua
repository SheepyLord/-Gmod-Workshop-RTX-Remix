-- Full production functions, with disk, mount and entity lifetimes instrumented.
local selected,source,realm,scenario=unpack(arg)
SERVER,CLIENT=realm=='server',realm=='client'
local function noop() end
for i,name in ipairs({'CLASS_COMBINE','CLASS_COMBINE_GUNSHIP','CLASS_COMBINE_HUNTER','CLASS_METROPOLICE','CLASS_MANHACK','CLASS_SCANNER','CLASS_STALKER','CLASS_PROTOSNIPER','CLASS_MILITARY','CLASS_PLAYER_ALLY','CLASS_PLAYER_ALLY_VITAL','CLASS_CITIZEN_PASSIVE','CLASS_CITIZEN_REBEL','CLASS_VORTIGAUNT','CLASS_HACKED_ROLLERMINE'}) do _G[name]=i end
local function eq(a,b,why) assert(a==b,(why or '')..' '..tostring(a)..' ~= '..tostring(b)) end
function istable(v) return type(v)=='table' end
function isstring(v) return type(v)=='string' end
function isnumber(v) return type(v)=='number' end
function isbool(v) return type(v)=='boolean' end
function IsValid(v) return istable(v) and not v.removed end
function Vector(...) return {...} end
function Angle(...) return {...} end
function LocalPlayer() return nil end
function RealTime() return 0 end
function CurTime() return 0 end
function ErrorNoHalt(text) error(text) end
function table.Copy(value)
 if not istable(value) then return value end
 local copy={} for k,v in pairs(value) do copy[k]=table.Copy(v) end return copy
end
function math.Clamp(v,a,b) return math.max(a,math.min(v,b)) end
local hooks,timers={},{ }
hook={Add=function(event,key,fn) hooks[event]=hooks[event] or {} hooks[event][key]=fn end,
 Run=function(event,...) for _,fn in pairs(hooks[event] or {}) do fn(...) end end}
timer={Simple=function(_,fn) timers[#timers+1]=fn end,
 Create=function(_,_,_,fn) timers[#timers+1]=fn end,Remove=noop}
local function tick() local pending=timers timers={} for _,fn in ipairs(pending) do fn() end end
local disk,visible,precache,all,entries={},{},{},{},{}
local blockedWrite,mountOK=false,true
local function path(r) return 'mmd_hotloader/rigs/'..r.key..'/rig.json' end
file={Read=function(p) return disk[p] end,Exists=function(p,where) return (where=='GAME' and visible[p] or disk[p])~=nil end,
 Write=function(p,v) if blockedWrite=='partial' then disk[p]='partial' elseif not blockedWrite then disk[p]=v end end,
 Rename=function(a,b) assert(not disk[b]) disk[b]=disk[a] disk[a]=nil end,Delete=function(p) disk[p]=nil end,CreateDir=noop}
util={JSONToTable=function(v) return istable(v) and table.Copy(v) or nil end,
 TableToJSON=function(v) return table.Copy(v) end,AddNetworkString=noop,
 PrecacheModel=function(p) assert(visible[p],'precache before mount') precache[p]=true end,
 IsValidModel=function(p) return precache[p]==true end}
game={SinglePlayer=function() return true end}
list={Set=function(kind,key,value) entries[kind..key]=value end,
 GetForEdit=function() return {} end,Get=function() return {} end}
player_manager={AddValidModel=noop,AddValidHands=noop,RemoveValidModel=noop}
net={Receive=noop,Start=noop,WriteString=noop,WriteUInt=noop,SendToServer=noop,Send=noop,Broadcast=noop}
duplicator={CopyEntTable=noop,CreateEntityFromTable=noop,DoGeneric=noop,RegisterEntityModifier=noop,
 StoreEntityModifier=noop,ClearEntityModifier=noop}
undo={Create=noop,AddEntity=noop,SetPlayer=noop,Finish=noop}
gamemode={Call=noop} player={GetAll=function() return {} end}
local E={} E.__index=E
function FindMetaTable() return E end
function E:SetModel(p) self.model=p end
function E:GetModel() return self.model end
function E:GetClass() return self.class end
function E:IsRagdoll() return self.class=='prop_ragdoll' end
function E:IsPlayer() return self.class=='player' end
function E:EntIndex() return 1 end
function E:GetNW2String(k,d) return self[k] or d end
function E:SetNW2String(k,v) self[k]=v end
function E:GetNW2Int(k,d) return self[k] or d end
function E:SetNW2Int(k,v) self[k]=v end
function E:GetNoDraw() return false end
function E:SetNoDraw() end
function E:GetPhysicsObjectCount() return self:IsRagdoll() and 18 or 1 end
function E:GetPhysicsObjectNum() return {EnableMotion=noop,Wake=noop} end
function E:Remove() self.removed=true end
function E:GetInfo() return '' end
function E:GetInfoNum() return 0 end
function E:SetPos() end function E:SetAngles() end function E:SetKeyValue() end
function E:Spawn() assert(visible[self.model],'spawn before model visible') end
function E:Activate() end function E:AddRelationship() end function E:AddEntityRelationship() end
function E:SetMaxHealth() end function E:SetHealth() end function E:SetCreator() end
function E:AddCleanup() end function E:SetupHands() end function E:GetHands() return nil end
function E:ConCommand() end
function E:GetFlexScale() return 1 end
function E:GetCreationTime() return 0 end
ents={Create=function(class) local ent=setmetatable({class=class},E) all[#all+1]=ent return ent end}
local asset,other=string.rep('a',64),string.rep('b',64)
local keys={ragdoll='1',citizen='2',combine='3',player='4',arms='5'}
local prepared,prepares,boneRevision={},0,1
local function prepare(id,options)
 prepares=prepares+1
 local role=options.role or 'ragdoll'
 local char=options.scaleMultiplier==1.1 and ({ragdoll='6',citizen='7',combine='8',player='9',arms='a'})[role] or keys[role]
 if role=='citizen' and options.boneMap and options.boneMap.revision==2 then char='c' end
 local key=string.rep(char,32)
 local rig=prepared[key]
 if not rig then
  rig={version=1,generator=31,key=key,asset=id,role=role,name='Fixture',model='models/mmd/'..key:sub(1,16)..'/a.mdl',
   scale=3.2,mass=70,morphs={},materials={},animation={profile=role..'_female'}}
  rig.gma='data/mmd_hotloader/rigs/'..key..'/carrier.gma' prepared[key]=rig
 end
 -- Matches PrepareCarrier: a retained carrier skips packaging and rig.json.
 if not disk['mmd_hotloader/rigs/'..key..'/carrier.gma'] then
  disk['mmd_hotloader/rigs/'..key..'/carrier.gma']=true disk[path(rig)]=table.Copy(rig)
 end
 disk['mmd_hotloader/names/rigs/'..key:sub(1,16)..'.json']={id=key}
 return table.Copy(rig)
end
mmdhl={native={GetCapabilities=function() return {rigGenerator=31,rigGeneratorMin=30,rigVersion=1} end,
 PrepareCarrier=prepare,ClearPreview=noop,
 DeleteAssets=function(ids)
  -- Client disk deletion leaves mounted GMA files locked, but removes metadata.
  for p,v in pairs(disk) do if p:find('rig.json',1,true) or p:find('names/rigs/',1,true) then disk[p]=nil end end
  return {pendingFiles=3}
 end},library={entries={},Refresh=noop},assets={},rigs={},
 L=function(v) return v end,Localize=function(v) return v end,Decode=function(v) return v end,
 CanUseAsset=function() return true end,ActorOptions=function(o) return o end,
 WithSpawnDefaults=function(_,o) return o end,
 SavedBoneMap=function() return {revision=boneRevision} end,
 CaptureMaterialState=function() return {} end,
 GetAsset=function(e) return e.MMDHLAsset end,
 IsMMD=function(e) return IsValid(e) and e.MMDHLAsset~=nil end,
 Entities=function() local t={} for _,e in ipairs(all) do if IsValid(e) and mmdhl.IsMMD(e) then t[#t+1]=e end end return t end,
 RemoveClientRagdoll=function() return false end,Action=function(_,_,e)
  if e:IsPlayer() then e.model='models/player/kleiner.mdl' e.MMDHLAsset=nil e.MMDHLRig=nil e.MMDHLBoundRig=nil else e:Remove() end
 end,
 PublishRig=noop,ApplyBodygroupState=noop,StoreNativeState=noop,
 MountPackage=function(p,expected)
  if not mountOK then return false end
  local key=p:match('/rigs/(%x+)/carrier.gma')
  if key then local rig=prepared[key] visible[rig.model]=true end
  if expected and not visible[expected] then return false end
  return true
 end}
dofile(selected)
local savedServer,savedClient=SERVER,CLIENT SERVER,CLIENT=true,false
dofile(source..'/actors.lua')
-- The full server persistence wrapper is tested in both disk-lifetime simulations.
dofile(source..'/persistence.lua')
SERVER,CLIENT=savedServer,savedClient
mmdhl.ActorOptions=function(o) return o end -- fitting input is not the readiness boundary
-- Bind's unrelated appearance adapters are covered elsewhere; retain its actual
-- readiness lookup here, which also catches delayed errors after SetModel.
mmdhl.BindEntity=function(e)
 local r,why=mmdhl.EnsureModel(e:GetModel()) assert(r,why)
 if e.MMDHLRig~=r.key then mmdhl.AttachNative(e,r.asset,{rigManifest=r}) end
 return true
end
mmdhl.AttachNative=function(e,id,o)
 local rig=o.rigManifest or prepare(id,o)
 assert(mmdhl.RememberRig(rig))
 e.MMDHLAsset=id e.MMDHLRig=rig.key e.MMDHLBoundRig=rig
 return rig
end
-- An outer addon wrapper must keep delegating through persistence.
local original=E.SetModel local chained=0
E.SetModel=function(e,p,...) chained=chained+1 return original(e,p,...) end
local host=ents.Create('player') host.model='models/player/kleiner.mdl'
local function spawn(role,scale)
 local result
 mmdhl.SpawnNative(host,asset,{role=role,scaleMultiplier=scale,frozen=true,weapon='none'},function(e,why) assert(e,why) result=e end)
 assert(result,'spawn returned no entity') tick()
 assert(mmdhl.EnsureModel(result:GetModel()),'SetModel carrier not resolvable')
 eq(mmdhl.GetRig(result).role,role) assert(disk[path(mmdhl.GetRig(result))],'manifest not repaired')
 return result
end
local first=spawn('ragdoll')
spawn('citizen') spawn('combine') spawn('player')
local unrelated=prepare(other,{role='ragdoll'}) unrelated.key=string.rep('b',32) unrelated.asset=other
unrelated.model='models/mmd/'..unrelated.key:sub(1,16)..'/a.mdl'
disk[path(unrelated)]=table.Copy(unrelated)
mmdhl.rigs[unrelated.key]=unrelated mmdhl.rigsByModel[unrelated.model]=unrelated
if scenario=='withdraw_live' then
 local bound=mmdhl.GetRig(first)
 disk[path(bound)]=nil
 mmdhl.UnregisterAsset(asset)
 eq(mmdhl.GetRig(first),bound,'live entity lost old manifest')
 eq(mmdhl.GetRigForModel(unrelated.model),unrelated,'another asset was evicted')
 assert(mmdhl.rigs[first.MMDHLRig]==nil,'deleted asset remained reusable')
elseif scenario=='failed_write' then
 local rig=mmdhl.GetRig(first) disk[path(rig)]=nil mmdhl.ForgetAssetRigs(asset)
 blockedWrite=true eq(mmdhl.RememberRig(rig),false,'failed write published rig')
 eq(mmdhl.GetRigForModel(rig.model),nil)
 blockedWrite='partial' eq(mmdhl.RememberRig(rig),false,'partial write published rig')
 eq(disk[path(rig)],nil,'partial metadata reached the final path')
 blockedWrite=false assert(mmdhl.RememberRig(rig))
 disk[path(rig)]='edited generated metadata'
 assert(mmdhl.RememberRig(rig)) eq(disk[path(rig)],'edited generated metadata','existing metadata was overwritten')
 local bad=table.Copy(rig) bad.model='models/mmd/../../bad.mdl'
 assert(not mmdhl.RememberRig(bad),'invalid identity accepted')
elseif scenario=='missing_mount' then
 local rig=mmdhl.GetRig(first) mountOK=false
 eq(mmdhl.ReadyActor(rig),false) eq(mmdhl.EnsureModel(rig.model),nil)
 mountOK=true assert(mmdhl.ReadyActor(rig))
else
 -- Convert and memoize a model-only NPC before deletion.
 local copy=ents.Create('npc_citizen') copy:SetModel(first:GetModel()) tick()
 eq(mmdhl.GetRig(copy).role,'citizen')
 if scenario=='orphan_variant' then
  disk[path(mmdhl.GetRig(copy))]=nil boneRevision=2
  local replacement=ents.Create('npc_citizen') replacement:SetModel(first:GetModel()) tick()
  eq(mmdhl.GetRig(replacement).key,string.rep('c',32),'missing sidecar reused an old converted fit')
 elseif scenario=='reload' then
  -- Auto-refresh keeps the guarded SetModel wrapper. Its memo and the new
  -- forget callback must still reference the same table.
  local bind=mmdhl.BindEntity SERVER,CLIENT=true,false
  dofile(source..'/persistence.lua')
  SERVER,CLIENT=savedServer,savedClient mmdhl.BindEntity=bind
 end
 local count=prepares
 mmdhl.library.entries[asset]={}
 local deleted=false
 mmdhl.library.Delete({asset},function(ok) assert(ok) deleted=true end) tick()
 assert(deleted) eq(mmdhl.GetRigForModel(first:GetModel()),nil,'deleted lookup survived')
 eq(mmdhl.GetRigForModel(unrelated.model),unrelated)
 -- Server withdrawal shares the cache but has its own registry lifetime.
 mmdhl.UnregisterAsset(asset)
 boneRevision=2 -- a reimport has a new saved fit: no retired conversion may win
 mmdhl.library.entries[asset]={} -- same immutable source imported again
 local scale=scenario=='changed_fit' and 1.1 or 1
 local rag=spawn('ragdoll',scale)
 for _,role in ipairs({'citizen','combine','player'}) do spawn(role,scale) end
 local converted=ents.Create('npc_citizen') converted:SetModel(rag:GetModel()) tick()
 eq(mmdhl.GetRig(converted).role,'citizen') eq(mmdhl.GetRig(converted).key,string.rep('c',32),'deleted conversion retained old fit') assert(prepares>count)
 local key=mmdhl.GetRig(rag).key
 spawn('ragdoll',1.1) -- another fit never changes an existing bound carrier
 eq(mmdhl.GetRig(rag).key,key)
 assert(chained>=8,'outer SetModel wrapper was bypassed')
end
print('PASS '..realm..' '..scenario)
