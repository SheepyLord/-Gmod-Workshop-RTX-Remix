-- R13-A: the shipped readiness, registration, persistence and sharing Lua under LuaJIT, with
-- disk, mounts, precache and entities instrumented. One scenario per run; prints PASS <scenario>.
local selected,source,scenario=unpack(arg)
local realm=scenario:match('^client') and 'client' or 'server'
SERVER,CLIENT=realm=='server',realm=='client'
local function noop() end
local function eq(a,b,why) assert(a==b,(why or '')..' '..tostring(a)..' ~= '..tostring(b)) end
for i,name in ipairs({'CLASS_COMBINE','CLASS_COMBINE_GUNSHIP','CLASS_COMBINE_HUNTER','CLASS_METROPOLICE','CLASS_MANHACK','CLASS_SCANNER','CLASS_STALKER','CLASS_PROTOSNIPER','CLASS_MILITARY','CLASS_PLAYER_ALLY','CLASS_PLAYER_ALLY_VITAL','CLASS_CITIZEN_PASSIVE','CLASS_CITIZEN_REBEL','CLASS_VORTIGAUNT','CLASS_HACKED_ROLLERMINE'}) do _G[name]=i end
function istable(v) return type(v)=='table' end
function isstring(v) return type(v)=='string' end
function isnumber(v) return type(v)=='number' end
function isbool(v) return type(v)=='boolean' end
function isfunction(v) return type(v)=='function' end
function isvector() return false end function isangle() return false end
function IsValid(v) return istable(v) and not v.removed and v.valid~=false end
function Vector(...) return {...} end
function Angle(...) return {...} end
function Color(...) return {...} end
FCVAR_NONE,FCVAR_ARCHIVE=0,128
local clock=1000
function RealTime() return clock end function CurTime() return clock end function SysTime() return clock end
local now=1800000000
os.time=function() return now end
function ErrorNoHalt(text) error(text) end
local printed={}
function MsgN(...) printed[#printed+1]=table.concat({...}) end
function table.Copy(value)
 if not istable(value) then return value end
 local copy={} for k,v in pairs(value) do copy[k]=table.Copy(v) end return copy
end
function table.GetKeys(t) local out={} for k in pairs(t) do out[#out+1]=k end return out end
function table.Count(t) local n=0 for _ in pairs(t) do n=n+1 end return n end
function math.Clamp(v,a,b) return math.max(a,math.min(v,b)) end
local hooks,timers,named={}, {}, {}
hook={Add=function(event,key,fn) hooks[event]=hooks[event] or {} hooks[event][key]=fn end,
 Run=function(event,...) for _,fn in pairs(hooks[event] or {}) do fn(...) end end,Remove=noop}
timer={Simple=function(_,fn) timers[#timers+1]=fn end,
 Create=function(name,_,_,fn) named[name]=fn end,Remove=function(name) named[name]=nil end,
 Exists=function(name) return named[name]~=nil end}
local function tick()
 local pending=timers timers={} for _,fn in ipairs(pending) do fn() end
 local due=named named={} for _,fn in pairs(due) do fn() end
end
-- Disk: JSON files hold tables (util.JSONToTable copies them), other files true.
local disk,times,sizes={}, {}, {}
local visible,mountedArchives,precache,mounts,precaches={}, {}, {}, {}, {}
local carrierModels={} -- carrier archive -> the model it provides
local function writes() local n=0 for _ in pairs(disk) do n=n+1 end return n end
file={Read=function(p) return disk[p] end,
 Exists=function(p,where) if where=='GAME' then return visible[p]==true end return disk[p]~=nil end,
 Write=function(p,v) disk[p]=v end,CreateDir=noop,Delete=function(p) disk[p]=nil end,
 Rename=function(a,b) disk[b]=disk[a] disk[a]=nil end,
 Time=function(p) return times[p] or 0 end,Size=function(p) return disk[p]~=nil and (sizes[p] or 0) or -1 end,
 Find=function(pattern,where)
  local folder=pattern:match('^(.*/)%*%.mdl$') local out={}
  for model in pairs(visible) do if folder and model:sub(1,#folder)==folder then out[#out+1]=model:sub(#folder+1) end end
  return out
 end}
util={JSONToTable=function(v) return istable(v) and table.Copy(v) or nil end,
 TableToJSON=function(v) return table.Copy(v) end,AddNetworkString=noop,
 PrecacheModel=function(p) assert(visible[p],'precache before mount: '..tostring(p)) precache[p]=true precaches[#precaches+1]=p end,
 IsValidModel=function(p) return precache[p]==true end,NetworkStringToID=function() return 1 end}
game={SinglePlayer=function() return true end,IsDedicated=function() return false end,
 MountGMA=function(path)
  mounts[#mounts+1]=path
  local model=carrierModels[path]
  if model then visible[model]=true return true,{model} end
  local asset=path:match('assets/(%x+)/materials%-v5%.gma$')
  if asset then mountedArchives[asset]=true visible['materials/mmd/'..asset:sub(1,16)..'/a.vmt']=true return true,{'materials/mmd/'..asset:sub(1,16)..'/a.vmt'} end
  return false
 end}
local lists,players,hands={}, {}, {}
list={GetForEdit=function(kind) lists[kind]=lists[kind] or {} return lists[kind] end,Get=function() return {} end}
function list.Set(kind,key,value) list.GetForEdit(kind)[key]=value end
local function npcEntry(r) return list.GetForEdit('NPC')['mmd_'..r.key:sub(1,16)] end
function ClientsideModel(model) return {model=model} end
function ClientsideRagdoll(model) return {model=model} end
player_manager={AddValidModel=function(key,model) players[key]=model end,AddValidHands=function(key,model) hands[key]=model end,
 RemoveValidModel=function(key) players[key]=nil end,AllValidModels=function() return players end}
local received={}
local reads={}
net={Receive=function(name,fn) received[name]=fn end,Start=noop,WriteString=noop,WriteUInt=noop,WriteBool=noop,
 WriteData=noop,SendToServer=noop,Send=noop,Broadcast=noop,ReadString=function() return table.remove(reads,1) end}
duplicator={CopyEntTable=noop,CreateEntityFromTable=noop,DoGeneric=noop,RegisterEntityModifier=noop,
 StoreEntityModifier=noop,ClearEntityModifier=noop}
undo={Create=noop,AddEntity=noop,SetPlayer=noop,Finish=noop}
gamemode={Call=noop} player={GetAll=function() return {} end}
local convars={}
function CreateConVar(name,value) local c={name=name,value=tonumber(value)} function c:GetInt() return self.value end convars[name]=c return c end
local changes={}
cvars={AddChangeCallback=function(name,fn) changes[name]=fn end}
local function setConVar(name,value) convars[name].value=value if changes[name] then changes[name]() end end
local host=true
function LocalPlayer() return {valid=true,IsListenServerHost=function() return host end} end
local E={} E.__index=E
function FindMetaTable() return E end
function E:SetModel(p) self.model=p end
function E:GetModel() return self.model end
function E:GetClass() return self.class end
function E:IsRagdoll() return self.class=='prop_ragdoll' end
function E:IsPlayer() return self.class=='player' end
function E:EntIndex() return 1 end
function E:GetNW2String(k,d) return self[k] or d end function E:SetNW2String(k,v) self[k]=v end
function E:GetNW2Int(k,d) return self[k] or d end function E:SetNW2Int(k,v) self[k]=v end
function E:SetNW2Bool() end function E:GetNoDraw() return false end
function E:Remove() self.removed=true end
local created={}
ents={Create=function(class) local e=setmetatable({class=class},E) created[#created+1]=e return e end,GetAll=function() return created end}
-- Fixture library: four characters; the second also has a player model with arms.
local function hex(c,n) return string.rep(c,n) end
local assets={hex('1',64),hex('2',64),hex('3',64),hex('4',64)}
local rigs={}
local function rig(asset,keyChar,role)
 local key=hex(keyChar,32)
 local r={version=3,generator=31,key=key,asset=asset,role=role,name='Character '..keyChar,model='models/mmd/'..key:sub(1,16)..'/c.mdl',
  scale=40,mass=60,morphs={},materials={},animation={profile=role..'_female'},materialGma='data/mmd_hotloader/assets/'..asset..'/materials-v5.gma'}
 disk['mmd_hotloader/rigs/'..key..'/rig.json']=table.Copy(r)
 disk['mmd_hotloader/rigs/'..key..'/carrier.gma']=true
 disk['mmd_hotloader/names/rigs/'..key:sub(1,16)..'.json']={id=key}
 carrierModels['data/mmd_hotloader/rigs/'..key..'/carrier.gma']=r.model
 rigs[keyChar]=r
 return r
end
local approved={version=1,assets={},rigs={},props={}}
for i,asset in ipairs(assets) do
 disk['mmd_hotloader/assets/'..asset..'/manifest.json']={name='Character '..i}
 disk['mmd_hotloader/assets/'..asset..'/materials-v5.gma']=true
 sizes['mmd_hotloader/assets/'..asset..'/materials-v5.gma']=({500,700,4000,300})[i]*1048576
 approved.assets[asset]={name='Character '..i,approvedBy='singleplayer'}
end
local npcs={rig(assets[1],'a','citizen'),rig(assets[2],'b','citizen'),rig(assets[3],'c','citizen'),rig(assets[4],'d','combine')}
local player=rig(assets[2],'e','player') local arms=rig(assets[2],'f','arms')
for _,r in ipairs(npcs) do approved.rigs[r.key]={asset=r.asset,role=r.role} end
approved.rigs[player.key]={asset=player.asset,role='player',arms=arms.key}
approved.rigs[arms.key]={asset=arms.asset,role='arms'}
disk['mmd_hotloader/approved.json']=approved
-- Last uses: asset 3 newest (but its archive is large), then 2, then 1; 4 never.
disk['mmd_hotloader/recent.json']={version=1,uses={{assets[3],now-10},{assets[2],now-20},{assets[1],now-30}}}
mmdhl={native={GetCapabilities=function() return {rigGenerator=31,rigGeneratorMin=30,rigVersion=3} end,
 GetMountablePackage=function(relative) if disk['mmd_hotloader/'..relative] then return 'data/mmd_hotloader/'..relative end return nil,'missing' end},
 L=function(v) return v end,Localize=function(v) return v end,
 Decode=function(v,err) if v==nil then return nil,err end return v end,
 I18n={Token=function(v) return v end}}
dofile(selected) -- the MountPackage, RememberRig/ForgetAssetRigs and GetRigForModel production slices
local function load(path) dofile(source..'/'..path) end
local engine={SetModel=E.SetModel,PrecacheModel=util.PrecacheModel,IsValidModel=util.IsValidModel}
local function loadRealm()
 load('actors.lua') -- with the ready set (mmdhl.readiness)
 load('persistence.lua')
 if SERVER then load('sharing.lua') end
 -- Binding (native attachment, appearance) is covered elsewhere; readiness is the boundary here.
 mmdhl.BindEntity=function() return true end
end
loadRealm()
local function precached(model) return precache[model]==true end
local function mounted(model) return visible[model]==true end
local function restore() hooks.InitPostEntity['MMDHL.RestorePublishedActors']() end
local function entry(r) return mmdhl.actorRegistrations[r.model] end
local function status(memory) disk['native-loader/status.json']={activation={outcome='active',memory=memory}} end
if scenario=='server_none' then
 -- No status.json: every entry is published, none is mounted or precached.
 restore()
 for _,r in ipairs(npcs) do assert(npcEntry(r),'npc entry missing') assert(entry(r).lazy) assert(not mounted(r.model)) assert(not precached(r.model)) end
 eq(players['mmd_'..player.key:sub(1,16)],player.model,'player model entry') eq(hands['mmd_'..player.key:sub(1,16)],arms.model,'hands entry')
 eq(#mounts,0,'mounts at map start') eq(#precaches,0,'precaches at map start')
 local d=mmdhl.readiness.Describe() eq(d.readyEntries,0) eq(d.lazyEntries,5) eq(d.budget.source,'none')
 assert(printed[1] and printed[1]:find('0 entries ready',1,true),printed[1])
elseif scenario=='server_budget' then
 -- Two characters and 2000 MiB: asset 3 (4000 MiB) is passed over, 2 and 1 are kept.
 status({profile='recommended',warm_characters=2,warm_mib=2000})
 restore()
 for _,r in ipairs({npcs[1],npcs[2],player}) do assert(not entry(r).lazy,'chosen entry not ready') assert(precached(r.model)) end
 assert(precached(arms.model),'arms of a ready player model')
 for _,r in ipairs({npcs[3],npcs[4]}) do assert(entry(r).lazy) assert(not mounted(r.model)) end
 local chosen={} for _,id in ipairs(mmdhl.readiness.state.chosen) do chosen[id]=true end
 assert(chosen[assets[1]] and chosen[assets[2]] and not chosen[assets[3]],'chosen set')
 eq(mmdhl.readiness.state.archiveBytes,1200*1048576,'archive bytes')
 -- No warm_mib: no cap; 1 character: the newest, however large.
 status({profile='high',warm_characters=1})
 local picked=mmdhl.readiness.Choose({{rig=npcs[3]},{rig=npcs[1]}},mmdhl.readiness.Budget())
 assert(picked[assets[3]] and not picked[assets[1]],'newest first without a cap')
elseif scenario=='server_convar' then
 status({profile='minimum',warm_characters=0})
 restore()
 eq(#precaches,0,'minimum profile keeps none')
 setConVar('mmdhl_warm_characters',1)
 eq(mmdhl.readiness.Budget().source,'status+convar')
 -- The override applies at once: the newest character that fits (asset 3, no cap) is readied.
 assert(not entry(npcs[3]).lazy and precached(npcs[3].model),'override did not ready the newest')
 assert(entry(npcs[1]).lazy,'override readied too many')
 setConVar('mmdhl_warm_characters',-1) setConVar('mmdhl_warm_mib',100)
 eq(mmdhl.readiness.Budget().characters,0)
elseif scenario=='server_first_use' then
 restore()
 local r=npcs[2]
 -- The NPC tab: Sandbox creates the class and sets the entry's model before Spawn.
 local npc=ents.Create('npc_citizen') npc:SetModel(r.model)
 assert(mounted(r.model) and precached(r.model),'first use did not mount and precache')
 eq(npc:GetModel(),r.model) assert(not entry(r).lazy,'entry stays lazy after use')
 local before=#mounts npc=ents.Create('npc_citizen') npc:SetModel(r.model) eq(#mounts,before,'second use remounted')
 -- The player's own model: the gamemode precaches before SetModel; arms with it.
 util.PrecacheModel(player.model)
 assert(mounted(player.model) and precached(player.model),'precache of a published player model')
 local ply=ents.Create('player') ply:SetModel(player.model)
 assert(precached(arms.model),'player model prepared without its arms')
 -- Use is recorded (debounced), newest first.
 tick()
 local saved=disk['mmd_hotloader/recent.json'] eq(saved.version,1)
 eq(saved.uses[1][1],assets[2],'latest use first') eq(saved.uses[1][2],now)
 -- IsValidModel of a published, unused entry mounts it (addons validate before SetModel).
 local other=npcs[4] assert(not mounted(other.model)) util.IsValidModel(other.model) assert(mounted(other.model))
elseif scenario=='server_fallback' then
 -- No recent.json: the native module's per-carrier name records date the last use.
 disk['mmd_hotloader/recent.json']=nil
 times['mmd_hotloader/names/rigs/'..npcs[4].key:sub(1,16)..'.json']=now-5
 times['mmd_hotloader/names/rigs/'..npcs[1].key:sub(1,16)..'.json']=now-50
 status({warm_characters=1,warm_mib=100000})
 restore()
 assert(not entry(npcs[4]).lazy,'fallback recency ignored') assert(entry(npcs[1]).lazy)
 assert(entry(npcs[2]).lazy and entry(npcs[3]).lazy,'never-used characters kept ready')
elseif scenario=='server_map_change' then
 status({warm_characters=1,warm_mib=100000})
 restore()
 assert(not entry(npcs[3]).lazy)
 ents.Create('npc_combine_s'):SetModel(npcs[4].model) tick()
 -- A new map: a new Lua state with the engine's own functions, the precache table and mounts
 -- gone; the use is on disk.
 for k in pairs(precache) do precache[k]=nil end for k in pairs(visible) do visible[k]=nil end
 lists={} players={} hands={}
 local saved=disk['mmd_hotloader/recent.json']
 E.SetModel,util.PrecacheModel,util.IsValidModel=engine.SetModel,engine.PrecacheModel,engine.IsValidModel
 mmdhl.actorRegistrations={} mmdhl.rigs={} mmdhl.rigsByModel={} mmdhl.readiness=nil mmdhl.PersistentSetModel=nil mmdhl.PersistentModelChecks=nil
 loadRealm()
 eq(disk['mmd_hotloader/recent.json'],saved)
 eq(saved.uses[1][1],assets[4],'last use not first on disk')
 restore()
 for _,r in ipairs(npcs) do assert(npcEntry(r),'entry missing after the map change') end
 assert(not entry(npcs[4]).lazy and precached(npcs[4].model),'last used character not ready on the next map')
 assert(entry(npcs[3]).lazy,'budget of one exceeded')
 -- And a published entry still spawns on the new map.
 local npc=ents.Create('npc_citizen') npc:SetModel(npcs[1].model) assert(precached(npcs[1].model))
elseif scenario=='server_forget' then
 restore()
 ents.Create('npc_citizen'):SetModel(npcs[1].model) tick()
 mmdhl.UnregisterAsset(assets[1]) tick()
 eq(entry(npcs[1]),nil,'deleted character still listed')
 for _,pair in ipairs(disk['mmd_hotloader/recent.json'].uses) do assert(pair[1]~=assets[1],'deleted character still recorded') end
 -- A carrier whose archive went: not published.
 disk['mmd_hotloader/rigs/'..npcs[2].key..'/carrier.gma']=nil
 mmdhl.actorRegistrations={} restore()
 eq(entry(npcs[2]),nil,'entry without a carrier published')
elseif scenario=='client_host' then
 -- Single player: the registration message publishes from metadata and mounts nothing.
 reads={npcs[1].key,''} received['mmdhl_actor_registration']()
 assert(entry(npcs[1]) and entry(npcs[1]).lazy,'host entry') eq(#mounts,0,'host client mounted at registration')
 reads={player.key,arms.key} received['mmdhl_actor_registration']()
 assert(entry(player).lazy) eq(players['mmd_'..player.key:sub(1,16)],player.model)
 -- Language and translated names renew entries without mounting.
 hook.Run('MMDHL.LanguageChanged') hook.Run('MMDHL.NamesTranslated') eq(#mounts,0,'renewed names mounted carriers')
 -- Menu icons: a character's is its name, or a real cached image; the engine's empty icon of an
 -- invisible carrier (215 bytes) counts as none. Any other model keeps the engine's icon.
 local cached='materials/spawnicons/'..npcs[1].model:gsub('%.mdl$','')..'.png'
 eq(mmdhl.readiness.IconMode(npcs[1].model),'name')
 disk[cached]=true sizes[cached]=215 eq(mmdhl.readiness.IconMode(npcs[1].model),'name','blank cached icon')
 sizes[cached]=6100 eq(mmdhl.readiness.IconMode(npcs[1].model),'image')
 mmdhl.assets={[npcs[2].asset]={}}
 eq(mmdhl.readiness.IconMode(npcs[2].model),'name','a shown character still loads its model for an icon')
 eq(mmdhl.readiness.IconMode('models/player/kleiner.mdl'),'model')
 -- A SpawnIcon of a character not shown never gives ModelImage its model.
 local modelImage={}
 local icon={Icon={SetModel=function(_,m) modelImage[#modelImage+1]=m end},SetModelName=function(self,m) self.name=m end,
  SetSkinID=noop,SetTooltip=noop,IsValid=function() return true end}
 vgui={GetControlTable=function() return spawnIcon end,Create=function() return {Dock=noop,SetMouseInputEnabled=noop,SetKeyboardInputEnabled=noop,
  SetImage=noop,SetText=noop,SetWrap=noop,SetContentAlignment=noop,SetFont=noop,SetTextColor=noop,Remove=noop} end}
 spawnIcon={SetModel=function(self,m) self.Icon:SetModel(m) end}
 mmdhl.readiness.InstallIcons()
 spawnIcon.SetModel(icon,npcs[3].model) eq(#modelImage,0,'lazy icon loaded its model') eq(icon.name,npcs[3].model)
 spawnIcon.SetModel(icon,npcs[2].model) eq(#modelImage,0,'character icon loaded its model')
 spawnIcon.SetModel(icon,'models/player/kleiner.mdl') eq(#modelImage,1,'stock model icon')
 -- A model panel's preview is a real use: ClientsideModel mounts the carrier first.
 local before=#mounts
 local made=ClientsideModel(npcs[4].model) eq(made.model,npcs[4].model)
 assert(mounted(npcs[4].model),'preview did not mount its carrier') assert(#mounts>before)
 before=#mounts ClientsideModel('models/player/kleiner.mdl') eq(#mounts,before,'a stock model mounted something')
elseif scenario=='client_remote' then
 -- Another server's player mounts the carrier at registration, as before (ready entry).
 host=false game.SinglePlayer=function() return false end
 reads={npcs[1].key,''} received['mmdhl_actor_registration']()
 assert(entry(npcs[1]) and not entry(npcs[1]).lazy,'remote entry not ready') assert(mounted(npcs[1].model),'remote client did not mount')
else
 error('unknown scenario '..scenario)
end
print('PASS '..scenario)
