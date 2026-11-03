-- Production matcher/playback adapter, import merge, and actor readiness under LuaJIT.
local mode,addon,hotloader,fixture,pmx=unpack(arg)
local data=dofile(fixture)
function istable(v) return type(v)=='table' end
function isstring(v) return type(v)=='string' end
function isnumber(v) return type(v)=='number' end
function isfunction(v) return type(v)=='function' end
function IsValid(v) return type(v)=='table' and v.valid~=false end
function string.Trim(v) return (v:gsub('^%s+',''):gsub('%s+$','')) end
function string.Replace(v,a,b) return (v:gsub(a,b)) end
function string.GetFileFromFilename(v) return v:match('[^/]+$') or v end
function math.Clamp(v,a,b) return math.max(a,math.min(b,v)) end
local function eq(a,b) assert(a==b,tostring(a)..' ~= '..tostring(b)) end
local function noop() end
hook={Add=noop}
timer={Create=noop,Simple=noop}
util={JSONToTable=function(v) return data[v] end,TableToJSON=function() return '{}' end,AddNetworkString=noop}
file={Read=function(path)
 if path:find('morph_semantics',1,true) then return 'semantics' end
 if path:find('cp932',1,true) then return 'cp932' end
 if path:find('flex_mapping_table',1,true) then return 'aliases' end
end,CreateDir=noop,Write=noop}
MMDVMDNPC={SettingsRoot='settings',MotionRoot='motions',BuiltRoot='built'}
local M=MMDVMDNPC
if mode=='mount' then
 SERVER,CLIENT=true,false
 local visible,mounts,allowed=false,0,true
 local model='models/mmd/aaaaaaaaaaaaaaaa/a.mdl'
 file.Exists=function(name) return name==model and visible end
 game={MountGMA=function() mounts=mounts+1 visible=allowed return allowed,{model} end}
 mmdhl={native={GetMountablePackage=function(relative) return 'data/mmd_hotloader/'..relative end}}
 assert(loadstring(data.mountCode))()
 local archive='data/mmd_hotloader/rigs/'..string.rep('a',32)..'/carrier.gma'
 assert(mmdhl.MountPackage(archive)) eq(mounts,1)
 assert(mmdhl.MountPackage(archive)) eq(mounts,1) -- no live-model reload
 visible=false -- engine unmounted between maps; old success is no longer evidence
 assert(mmdhl.MountPackage(archive)) eq(mounts,2)
 visible=false allowed=false
 assert(not mmdhl.MountPackage(archive)) eq(mounts,3)
 allowed=true assert(mmdhl.MountPackage(archive)) eq(mounts,4)
 assert(not mmdhl.MountPackage(archive,'models/mmd/aaaaaaaaaaaaaaaa/missing.mdl')) eq(mounts,5)
 assert(not mmdhl.MountPackage('../outside.gma'))
 print('PASS mount') return
end
if mode=='actor' then
 SERVER,CLIENT=true,false
 for i,name in ipairs({'CLASS_COMBINE','CLASS_COMBINE_GUNSHIP','CLASS_COMBINE_HUNTER','CLASS_METROPOLICE','CLASS_MANHACK','CLASS_SCANNER','CLASS_STALKER','CLASS_PROTOSNIPER','CLASS_MILITARY','CLASS_PLAYER_ALLY','CLASS_PLAYER_ALLY_VITAL','CLASS_CITIZEN_PASSIVE','CLASS_CITIZEN_REBEL','CLASS_VORTIGAUNT','CLASS_HACKED_ROLLERMINE'}) do _G[name]=i end
 local entries,precache,mounted={},{},{}
 local mountOK=true
 list={Set=function(kind,key,value)
  if kind=='NPC' then assert(precache[value.Model],'menu published before modelprecache') end
  entries[key]=value
 end,GetForEdit=function() return entries end,Get=function() return {} end}
 util.PrecacheModel=function(model) assert(mounted[model],'precache before mount') precache[model]=true end
 util.IsValidModel=function(model) return precache[model]==true end
 timer={Create=noop,Simple=noop}
 hook={Add=noop}
 net={Receive=noop}
 -- actors.lua's ready-set budget (R13-A) creates its two server ConVars at load.
 FCVAR_NONE=0 cvars={AddChangeCallback=noop}
 CreateConVar=function() return {GetInt=function() return -1 end} end
 player_manager={AddValidModel=noop,AddValidHands=noop,RemoveValidModel=noop}
 mmdhl={native={GetCapabilities=function() return {rigGenerator=31,rigGeneratorMin=30,rigVersion=1} end},
  Decode=function(v) return v end,L=function(v) return v end,Localize=function(v) return v end,
  RememberRig=function() return true end,
  MountPackage=function(path) if not mountOK then return false end
   if path:find('carrier.gma',1,true) then mounted['models/mmd/test/a.mdl']=true mounted['models/mmd/test/arms.mdl']=true end
   return true
  end}
 dofile(hotloader..'/actors.lua')
 local rig={version=1,generator=31,key=string.rep('a',32),role='citizen',model='models/mmd/test/a.mdl',name='A',asset=string.rep('a',64),materialGma='materials.gma'}
 assert(not util.IsValidModel(rig.model)) -- new map, no modelprecache entry
 assert(mmdhl.RegisterActor(rig))
 assert(entries['mmd_'..rig.key:sub(1,16)]) assert(util.IsValidModel(rig.model))
 -- Mount state survives; modelprecache belongs to the next map.
 precache={} entries={}
 assert(mmdhl.RegisterActor(rig)) assert(util.IsValidModel(rig.model))
 mountOK=false entries={}
 assert(not mmdhl.RegisterActor(rig)) eq(next(entries),nil)
 local arms={model='models/mmd/test/arms.mdl',key=string.rep('b',32)}
 assert(not mmdhl.ReadyActor(rig,arms))
 print('PASS actor') return
end
assert(loadstring(data.bindingCode))()
local morphs,geometry={},{}
local ent={GetModel=function() return 'models/test.mdl' end,
 GetFlexNum=function() return 4 end,GetFlexName=function(_,id) return ({[0]='eye_blink_happy_left',[1]='eye_blink_happy_right',[2]='blink',[3]='eyes_blink_smile'})[id] or '' end,
 SetFlexWeight=function(self,id,value) self[id]=value end}
mmdhl={IsMMD=function() return #morphs>0 end,GetMorphs=function() return morphs end,
 GetMorphGeometry=function() return geometry end,
 SetMorphWeight=function(_,id,value) ent.morphID=id ent.morphWeight=value return true end}
local function morph(name,original,native)
 local m={mmd=#morphs,name=name,original=original,native=native}
 morphs[#morphs+1]=m return m
end
if mode=='geometry' then
 local ffi=require('ffi')
 local handle=assert(io.open(pmx,'rb')) local bytes=handle:read('*a') handle:close()
 local f={p=0}
 function f:Size() return #bytes end
 function f:Tell() return self.p end
 function f:Skip(n) self.p=self.p+n end
 function f:Seek(n) self.p=n end
 function f:Read(n) local s=bytes:sub(self.p+1,self.p+n) self.p=self.p+n return s end
 function f:ReadByte() return self:Read(1):byte() end
 function f:ReadULong() local a,b,c,d=self:Read(4):byte(1,4) return a+b*256+c*65536+d*16777216 end
 function f:ReadLong() local v=self:ReadULong() return v>=2147483648 and v-4294967296 or v end
 function f:ReadUShort() local a,b=self:Read(2):byte(1,2) return a+b*256 end
 function f:ReadShort() local v=self:ReadUShort() return v>=32768 and v-65536 or v end
 function f:ReadFloat() local v=ffi.new('uint32_t[1]',self:ReadULong()) return tonumber(ffi.cast('float*',v)[0]) end
 assert(loadstring(data.geometryCode))()
 local ok,result=pcall(mmdhl.ReadMorphGeometry,f)
 if pmx:find('invalid',1,true) then assert(not ok,'malformed PMX accepted')
 else assert(ok,result) eq(result[1].side,'left') eq(result[2].side,'right')
  eq(result[3].side,pmx:find('cancel',1,true) and 'right' or pmx:find('partial',1,true) and 'unknown' or 'both')
  eq(result[4].side,'unknown')
 end
 print('PASS geometry') return
end
dofile(addon..'/sv_cache.lua')
M.FlexOverrides={}
local function resolve(source,name) return M.ResolveFlexTargets(ent,source,name) end
local function ids(targets) local out={} for i,t in ipairs(targets) do out[i]=t.id end return table.concat(out,',') end
morph('eye_blink_happy_left','ウィンク',0)
morph('eye_blink_happy_right','ウィンク右',1)
morph('blink','まばたき',2)
morph('eyes_blink_smile','笑い',3)
geometry={{side='left'},{side='right'},{side='both'},{side='both'}}
eq(ids(resolve('eye_blink_happy','笑い')),'3')
eq(ids(resolve('blink','まばたき')),'2')
eq(ids(resolve('eye_blink_happy_left','ウィンク')),'0')
-- Duplicate exact identities are all driven, as nanoem loops model morphs.
morph('extra','笑い',-1) eq(ids(resolve('eye_blink_happy','笑い')),'3,8')
assert(M.SetModelFlexWeight(ent,8,.75)) eq(ent.morphID,4) eq(ent.morphWeight,.75)
eq(M.GetModelFlexName(ent,8),'extra')
assert(M.ModelFlexLabel(ent,8):find('笑い',1,true))
morphs={} geometry={}
morph('left_in_name','EL_Happy_l_CLO',0)
morph('right_in_name','EL_Happy_r_CLO',1)
geometry={{side='right'},{side='left'}}
eq(ids(resolve('eye_blink_happy','笑い')),'1,0')
eq(ids(resolve('eye_blink_happy_left','ウィンク')),'1')
eq(ids(resolve('eye_blink_happy_right','ウィンク右')),'0')
morphs[2]=nil eq(#resolve('eye_blink_happy','笑い'),0)
geometry={} eq(#resolve('eye_blink_happy','笑い'),0)
morphs={} morph('native_opaque','Blink',0) geometry={{side='both'}}
eq(ids(resolve('blink','まばたき')),'0') -- reviewed canonical meaning, not native spelling
morphs={} geometry={}
morph('half','ｳｨﾝｸ２右',0) morph('full','ウィンク２右',1)
geometry={{side='right'},{side='left'}}
eq(ids(resolve('eye_blink_right','ｳｨﾝｸ２右')),'0')
eq(ids(resolve('eye_blink_right','ウィンク２右')),'1')
eq(#resolve('unknown','とても長い表情名の先頭'),0)
local raw=data.longVMD
eq(M.DecodeVMDMorphName(raw),data.longDecoded)
eq(M.DecodeVMDMorphName(string.rep('a',14)..string.char(0x81)),string.rep('a',14)..'・')
eq(M.DecodeVMDMorphName(string.char(0x81,0x30)),'・')
eq(M.DecodeVMDMorphName('X'..string.char(0)..'Y'),'X')
morphs={} morph('long','1234567890123456',0)
eq(#resolve('unknown',M.DecodeVMDMorphName('123456789012345')),0)
morphs={} morph('a','Smile',0) morph('b','smile',1)
eq(ids(resolve('unknown','Smile')),'0') eq(ids(resolve('unknown','smile')),'1')
eq(#resolve('unknown','SMILE'),0)
-- Saved strings/lists/sentinel survive; missing list members never leave half a mapping.
M.SetFlexOverrideForModel(ent:GetModel(),'笑い','eye_blink_happy','blink')
eq(ids(resolve('eye_blink_happy','笑い')),'2')
M.SetFlexOverrideForModel(ent:GetModel(),'笑い','eye_blink_happy',{'blink','absent'})
eq(#resolve('eye_blink_happy','笑い'),0)
M.SetFlexOverrideForModel(ent:GetModel(),'笑い','eye_blink_happy',M.FlexOverrideUnassigned)
eq(#resolve('eye_blink_happy','笑い'),0)
M.FlexOverrides={[ent:GetModel()]={by_source={eye_blink_happy='blink'}}}
eq(ids(resolve('eyes_blink_smile','笑い')),'2')
assert(M.ClearFlexOverrideForModel(ent:GetModel(),'笑い','eyes_blink_smile'))
eq(M.FlexOverrideTargetsForModel(ent:GetModel(),'eyes_blink_smile','笑い'),nil)
M.FlexOverrides={} morphs={}
-- Ordinary Source controllers retain aliases and atomic paired fallback.
eq(ids(resolve('blink','まばたき')),'2')
local oldName=ent.GetFlexName
ent.GetFlexName=function(_,id) return id<2 and oldName(ent,id) or '' end
eq(ids(resolve('eye_blink_happy','笑い')),'0,1')
ent.GetFlexName=function(_,id) return id==0 and 'eye_blink_happy_left' or '' end
eq(#resolve('eye_blink_happy','笑い'),0)
-- In-game importing keeps unknown names and distinct original identities.
dofile(addon..'/cl_import_data.lua') dofile(addon..'/cl_import_bake.lua')
local rawA,rawB=data.rawA,data.rawB
M.ImportData.flexMap[rawA]={'old','same_canonical'} M.ImportData.flexMap[rawB]={'old','same_canonical'}
local parsed={morphOrder={rawA,rawB,'CustomName'},morphs={}}
for _,n in ipairs(parsed.morphOrder) do parsed.morphs[n]={frames={0,10},weights={0,1},count=2} end
local tracks=M.ImportBake.MergeFlexTracks({{parsed=parsed,label='fixture',path='fixture'}})
eq(#tracks,3)
-- Controller ids above signed-16 range survive the adapter and new cache key.
morphs={}
for i=0,33000 do morphs[i+1]={mmd=i,name='extra_'..i,original='extra_'..i,native=-1} end
local id=M.MorphControllerID(ent,morphs[33001]) eq(id,33004)
assert(M.SetModelFlexWeight(ent,id,.4)) eq(ent.morphID,33000)
util.CRC=function() return '1234' end M.CacheExtension='.json'
assert(loadstring(data.cacheCode))()
eq(M.BuiltFormat,'mmd_vmd_npc_built_v2')
local path=M.BuiltPath('motion_fixture','models/player/alyx.mdl',{})
assert(path:match('_fm2%.json$'),path)
print('PASS matcher')
