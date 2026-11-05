-- R19: the Character Motion Importer's server Lua (sv_commands.lua) under LuaJIT with the game's
-- API stubbed: who may select, pose and dance whom (review H4/L-01), Force Reset and death, stop
-- all, a leaver's dances, the debug frame pace, the other add-ons' cvars across map changes (M9,
-- L-04) and the build budgets (M8, L-09). One scenario per run; prints PASS <scenario>.
-- usage: luajit motion_server_harness.lua <scenario> <the add-on's lua/mmd_vmd_npc folder>
local scenario,folder=arg[1],arg[2]
local source=folder..'/sv_commands.lua'
SERVER,CLIENT=true,false
local function noop() end
local function check(ok,why) if not ok then error('FAIL '..scenario..': '..why,2) end end

-- ---- JSON (util.TableToJSON / JSONToTable) ----
local json={}
function json.encode(v)
 local t=type(v)
 if t=='string' then return '"'..v:gsub('[%c"\\]',function(c) return string.format('\\u%04x',c:byte()) end)..'"' end
 if t=='number' then return v==math.floor(v) and string.format('%d',v) or string.format('%.17g',v) end
 if t=='boolean' then return tostring(v) end
 if t~='table' then return 'null' end
 if #v>0 or next(v)==nil then local out={} for i=1,#v do out[i]=json.encode(v[i]) end return '['..table.concat(out,',')..']' end
 local keys={} for k in pairs(v) do keys[#keys+1]=tostring(k) end table.sort(keys)
 local out={} for _,k in ipairs(keys) do out[#out+1]=json.encode(k)..':'..json.encode(v[k] ~= nil and v[k] or v[tonumber(k)]) end
 return '{'..table.concat(out,',')..'}'
end
function json.decode(s)
 local i=1
 local function ws() i=s:find('[^%s]',i) or #s+1 end
 local value
 local function str()
  local out={} i=i+1
  while true do
   local c=s:sub(i,i)
   if c=='' then error('unterminated string') end
   if c=='"' then i=i+1 return table.concat(out) end
   if c=='\\' then
    local e=s:sub(i+1,i+1)
    if e=='u' then out[#out+1]=string.char(tonumber(s:sub(i+2,i+5),16)%256) i=i+6
    else out[#out+1]=({n='\n',t='\t',r='\r',b='\b',f='\f'})[e] or e i=i+2 end
   else out[#out+1]=c i=i+1 end
  end
 end
 value=function()
  ws() local c=s:sub(i,i)
  if c=='{' then i=i+1 local t={} ws() if s:sub(i,i)=='}' then i=i+1 return t end
   while true do ws() local k=str() ws() i=i+1 t[k]=value() ws() local d=s:sub(i,i) i=i+1 if d=='}' then return t end end end
  if c=='[' then i=i+1 local t={} ws() if s:sub(i,i)==']' then i=i+1 return t end
   while true do t[#t+1]=value() ws() local d=s:sub(i,i) i=i+1 if d==']' then return t end end end
  if c=='"' then return str() end
  if s:sub(i,i+3)=='true' then i=i+4 return true end
  if s:sub(i,i+4)=='false' then i=i+5 return false end
  if s:sub(i,i+3)=='null' then i=i+4 return nil end
  local n=s:match('^-?[%d%.eE+-]+',i) i=i+#n return tonumber(n)
 end
 local ok,result=pcall(value) if ok then return result end
 return nil
end

-- ---- the game ----
local clock=1000
function CurTime() return clock end RealTime=CurTime SysTime=CurTime
function isnumber(v) return type(v)=='number' end function istable(v) return type(v)=='table' end
function isstring(v) return type(v)=='string' end function isfunction(v) return type(v)=='function' end
function isvector(v) return type(v)=='table' and v.isVector==true end function isangle() return false end
function Vector(x,y,z) return {x=x or 0,y=y or 0,z=z or 0,isVector=true} end
function Angle(p,y,r) return {p=p or 0,y=y or 0,r=r or 0} end
function FindMetaTable() return nil end
function math.Clamp(v,a,b) return math.max(a,math.min(b,v)) end
function string.Trim(s) return (tostring(s):gsub('^%s*(.-)%s*$','%1')) end
function string.Replace(s,a,b) return (s:gsub(a:gsub('%p','%%%0'),b)) end
IN_ATTACK,IN_ATTACK2,IN_USE,IN_RELOAD,IN_JUMP,IN_DUCK,IN_ZOOM=1,2048,32,8192,2,4,524288
FCVAR_NONE,FCVAR_ARCHIVE,FCVAR_NOTIFY,FCVAR_REPLICATED,FCVAR_USERINFO=0,128,256,8192,512
local hooks,receivers,timers,named={}, {}, {}, {}
hook={Add=function(event,id,fn) hooks[event]=hooks[event] or {} hooks[event][id]=fn end,Remove=noop,
 Run=function(event,...) for _,fn in pairs(hooks[event] or {}) do fn(...) end end}
concommand={Add=noop}
function AddOriginToPVS() end
-- RunConsoleCommand and timers apply at the end of a frame (tick).
local cvars,commands={}, {}
local function cvar(name,value,fromLua)
 local c={name=name,value=tostring(value)}
 function c:GetString() return self.value end function c:GetBool() return tonumber(self.value)~=0 end
 function c:SetString(v) if not fromLua then error('attempted to modify ConVar not created by Lua') end self.value=tostring(v) end
 cvars[name]=c return c
end
function GetConVar(name) return cvars[name] end
function CreateConVar(name,value) return cvar(name,value,true) end
local issued={}
function RunConsoleCommand(name,value) commands[#commands+1]={name,tostring(value)} issued[#issued+1]=name..' '..tostring(value) end
timer={Simple=function(delay,fn) timers[#timers+1]={at=clock+(delay or 0),fn=fn} end,
 Create=function(name,delay,_,fn) named[name]={at=clock+delay,fn=fn} end,Remove=function(name) named[name]=nil end}
local function tick(seconds)
 for _,c in ipairs(commands) do if cvars[c[1]] then cvars[c[1]].value=c[2] end end commands={}
 clock=clock+(seconds or 0)
 local due=timers timers={} for _,t in ipairs(due) do if t.at<=clock then t.fn() else timers[#timers+1]=t end end
 for name,t in pairs(named) do if t.at<=clock then named[name]=nil t.fn() end end
end
local disk={}
file={Read=function(p) return disk[p] end,Write=function(p,v) disk[p]=v end,Exists=function(p) return disk[p]~=nil end,
 Delete=function(p) disk[p]=nil end,CreateDir=noop,Size=function(p) return disk[p] and #disk[p] or -1 end,Time=function() return 0 end,
 Find=function() return {},{} end}
util={TableToJSON=function(t) return json.encode(t) end,JSONToTable=function(s) local v=type(s)=='string' and json.decode(s) or nil return type(v)=='table' and v or nil end,
 AddNetworkString=noop}
local singleplayer=false
game={SinglePlayer=function() return singleplayer end}
-- net: what a client sends is queued in `reads`; what the server sends is counted.
local reads,sent={}, {}
local function read(default) if #reads>0 then return table.remove(reads,1) end return default end
net={Receive=function(name,fn) receivers[name]=fn end,Start=function(name) sent[#sent+1]=name end,Send=noop,Broadcast=noop,
 ReadString=function() return read('') end,ReadBool=function() return read(false) end,ReadFloat=function() return read(0) end,
 ReadUInt=function() return read(0) end,ReadInt=function() return read(0) end,ReadEntity=function() return read(NULL) end,
 ReadAngle=function() return read(Angle()) end,ReadVector=function() return read(Vector()) end,BytesLeft=function() return 0 end}
for _,name in ipairs({'WriteString','WriteBool','WriteFloat','WriteUInt','WriteInt','WriteEntity','WriteDouble','WriteAngle','WriteVector','WriteData'}) do net[name]=noop end
local function receive(name,ply,...) reads={...} receivers[name](0,ply) reads={} end
local function sentCount(name) local n=0 for _,s in ipairs(sent) do if s==name then n=n+1 end end return n end
-- Entities: unknown methods do nothing; fields (lowercase, or the add-on's MMDVMDNPC...) start empty.
local Entity={}
Entity.__index=function(_,k) local v=rawget(Entity,k) if v~=nil then return v end
 if type(k)~='string' or k:find('^[a-z]') or k:find('^MMDVMDNPC') then return nil end return noop end
function IsValid(e) return type(e)=='table' and e.valid~=false end
NULL=setmetatable({valid=false},Entity)
local nextIndex=1
local function entity(kind,fields)
 local e=setmetatable(fields or {},Entity) e.kind=kind e.index=nextIndex nextIndex=nextIndex+1 e.model=e.model or ('models/'..kind..e.index..'.mdl') return e
end
function Entity:IsPlayer() return self.kind=='player' end function Entity:IsNPC() return self.kind=='npc' end
function Entity:GetBoneCount() return 4 end function Entity:GetModel() return self.model end
function Entity:EntIndex() return self.index end function Entity:GetClass() return self.kind end function Entity:Nick() return 'p'..self.index end
function Entity:IsAdmin() return self.admin==true end function Entity:SteamID64() return self.kind=='player' and ('7656'..self.index) or nil end
function Entity:Freeze(on) self.frozen=on==true end function Entity:IsFrozen() return self.frozen==true end
function Entity:SetNoDraw(on) self.noDraw=on==true end function Entity:GetNoDraw() return self.noDraw==true end
function Entity:GetWeapons() return {} end function Entity:GetPos() return Vector() end function Entity:GetAngles() return Angle() end
function Entity:EyeAngles() return Angle() end
ents={Create=function() return entity('prop') end}

-- ---- the add-on's shared code, as far as these paths use it ----
local loads,chats={}, {}
local function fresh()
 hooks,receivers,timers,named={}, {}, {}, {}
 MMDVMDNPC={DataRoot='mmd_vmd_npc',SettingsRoot='mmd_vmd_npc/settings',BuiltRoot='mmd_vmd_npc/built',BuiltFormat='built-test',
  AudioOffsetPath='mmd_vmd_npc/settings/audio_offsets.json',CacheExtension='.json',
  Chat=function(_,text) chats[#chats+1]=tostring(text) end,
  LookupRequiredReferenceSequenceInfo=function() return {seq=0} end,LookupReferenceSequenceInfo=function() return {seq=0} end,
  LookupReferenceSequence=function() return 0 end,NormalizeMotionID=function(id) id=tostring(id or '') return id~='' and id or nil end,
  BuiltPath=function(id,model) id=tostring(id or '') if id=='' then return nil end return 'mmd_vmd_npc/built/'..id..'_'..model:gsub('%W','_')..'.json',id end,
  LoadMotion=function(id) loads[#loads+1]=id return {frameStart=0,frameEnd=10,fps=30,boneTracks={},flexTracks={}} end,
  ModelFlexList=function() return {} end,SetModelFlexWeight=function() return true end,
  NormalizeTravelSettings=function() return 100,100,0 end,BuiltTravel=function() return false end,BuiltPoseCuts=function() return {} end,
  NoteBuiltHeader=noop,ForgetBuiltHeader=noop,MotionPath=function() return nil end,ListMotions=function() return {} end}
 dofile(source)
end
fresh()
local M=function() return MMDVMDNPC end

local victim=entity('player') local attacker=entity('player') local admin=entity('player',{admin=true})
local npc=entity('npc') local npc2=entity('npc')
local RPE='sv_rpe_living_body_enable'

if scenario=='select' then
 -- Another player is refused, yourself and (for an admin) another player are accepted.
 local ok,why=M().SelectTargetForPlayer(attacker,victim)
 check(not ok and tostring(why):find('only admins',1,true) and M().DebugTargets[attacker]==nil,'a player selected another player')
 check(M().SelectTargetForPlayer(attacker,attacker) and M().DebugTargets[attacker]==attacker,'a player could not select themself')
 check(M().SelectTargetForPlayer(admin,victim) and M().DebugTargets[admin]==victim,'an admin could not select another player')
 check(M().SelectTargetForPlayer(attacker,npc) and M().DebugTargets[attacker]==npc,'an NPC could not be selected')
 -- The menu's "select myself" message names the sender only.
 M().DebugTargets[attacker]=nil receive('mmdvmd_select_target',attacker,victim)
 check(M().DebugTargets[attacker]==nil,'the select message picked another player')
 receive('mmdvmd_select_target',attacker,attacker) check(M().DebugTargets[attacker]==attacker,'the select message did not pick the sender')
 -- The debug window: not on another player.
 local opened=sentCount('mmdvmd_debug_open')
 check(not M().OpenDebugForPlayer(attacker,victim,'m',-1) and sentCount('mmdvmd_debug_open')==opened,'the debug window opened on another player')
 check(M().OpenDebugForPlayer(attacker,attacker,'m',-1) and sentCount('mmdvmd_debug_open')==opened+1,'the debug window did not open on the player themself')
elseif scenario=='play' then
 -- A selection made while an admin (or forged) is checked again where the dance starts, with
 -- the victim's dance built (otherwise the request would only ask for a build).
 disk[M().BuiltPath('m',victim:GetModel())]=util.TableToJSON({format='built-test',model=victim:GetModel(),frame_start=0,frame_end=1,fps=30,frames={{frame=0,bones={},flexes={}}}})
 M().DebugTargets[attacker]=victim
 receive('mmdvmd_play_request',attacker,'m')
 check(not victim:GetNoDraw() and M().SelfPlaybackMovementLocks[victim]==nil and next(M().Playbacks)==nil,'a dance hid or locked another player')
 -- Debug poses and builds: refused as well.
 receive('mmdvmd_debug_apply',attacker,victim,0,0)
 local ok=M().BeginBuildForPlayer(attacker,'unbuilt',{},nil)
 check(not ok and M().BuildJobs[attacker]==nil,'a build started on another player')
elseif scenario=='reset' then
 -- An admin tool froze and hid the player: Force Reset and death leave that alone.
 victim:Freeze(true) victim:SetNoDraw(true)
 M().ForceResetSelfPlaybackForPlayer(victim)
 check(victim:IsFrozen() and victim:GetNoDraw(),'Force Reset unfroze or showed a player the add-on never froze or hid')
 hooks.PlayerDeath.MMDVMDNPCSelfProxyDeathCleanup(victim)
 check(victim:IsFrozen() and victim:GetNoDraw(),'a death unfroze or showed a player the add-on never froze or hid')
 -- What the add-on hid it shows again.
 local other=entity('player') M().SelfPlaybackVisuals[other]={playerNoDraw=false,weapons={}} other:SetNoDraw(true)
 M().ForceResetSelfPlaybackForPlayer(other) check(not other:GetNoDraw(),'Force Reset kept the add-on own hiding')
elseif scenario=='stop_all' or scenario=='disconnect' then
 local stopped={}
 M().StopPlayback=function(ent) stopped[#stopped+1]=ent M().Playbacks[ent]=nil end
 M().Playbacks[npc]={ply=attacker,initiator=attacker} M().Playbacks[npc2]={ply=victim,initiator=victim}
 if scenario=='stop_all' then
  M().StopAllPlaybacksForPlayer(attacker)
  check(#stopped==1 and stopped[1]==npc and M().Playbacks[npc2]~=nil,'stop all stopped another player\'s dance')
  M().StopAllPlaybacksForPlayer(admin)
  check(#stopped==2 and stopped[2]==npc2,'an admin\'s stop all left a dance')
 else
  hooks.PlayerDisconnected.MMDVMDNPCDebugTargetCleanup(attacker)
  check(#stopped==1 and stopped[1]==npc and M().Playbacks[npc2]~=nil,'a leaver\'s dance kept playing, or another one stopped')
 end
elseif scenario=='debug_rate' then
 -- Three requests at once: one frame now, the latest one when the interval ends.
 for _,id in ipairs({'m1','m2','m3'}) do receive('mmdvmd_debug_request',attacker,id,-1) end
 check(#loads==1 and loads[1]=='m1','debug requests were not paced: '..table.concat(loads,','))
 tick(0.05) check(#loads==1,'the paced request came early')
 tick(0.06) check(#loads==2 and loads[2]=='m3','the latest debug request was not answered: '..table.concat(loads,','))
 receive('mmdvmd_debug_request',attacker,'m4',-1) check(#loads==2,'a request inside the interval was answered at once')
 tick(0.2) check(#loads==3 and loads[3]=='m4','the next request was lost')
elseif scenario=='cvar_shutdown' or scenario=='cvar_crash' or scenario=='cvar_lua' then
 cvar(RPE,'1',scenario=='cvar_lua')
 local record=M().CVarRestorePath
 -- A dance turns the RPE body off and keeps the original in data/.
 M().Playbacks[npc]={ply=attacker} M().UpdateRPEBodySuppression() tick()
 check(cvars[RPE].value=='0','the dance did not turn the RPE body off')
 check(type(disk[record])=='string' and util.JSONToTable(disk[record])[RPE]=='1','the original was not recorded: '..tostring(disk[record]))
 if scenario~='cvar_crash' then
  -- The map changes mid-dance: ShutDown puts the original back (a Lua cvar at once).
  issued={} hooks.ShutDown.MMDVMDNPCRestoreCVars()
  if scenario=='cvar_lua' then check(cvars[RPE].value=='1' and #issued==0,'ShutDown did not set a Lua cvar at once') end
  tick() check(cvars[RPE].value=='1','ShutDown did not restore the cvar')
 end
 -- The next map: a new Lua state; the record is still there.
 fresh() check(disk[record]~=nil,'the record went before the next start checked it')
 if scenario=='cvar_crash' then
  check(cvars[RPE].value=='0','the crash test lost its 0')
  -- A dance before InitPostEntity takes the recorded original, not the 0 left behind.
  M().Playbacks[npc]={ply=attacker} M().UpdateRPEBodySuppression() tick()
  M().Playbacks[npc]=nil M().UpdateRPEBodySuppression() tick() tick()
  check(cvars[RPE].value=='1','the 0 an earlier session left was taken for the original')
  check(disk[record]==nil,'the record outlived the restore')
  -- And with nothing playing, InitPostEntity restores what an earlier session left.
  cvar(RPE,'0') disk[record]=util.TableToJSON({[RPE]='1'})
  fresh() hooks.InitPostEntity.MMDVMDNPCRestoreCVars() tick() tick()
  check(cvars[RPE].value=='1' and disk[record]==nil,'the next start did not restore the cvar an earlier session left off')
  -- The record names only the add-ons' cvars: anything else in it is never run.
  disk[record]=util.TableToJSON({['sv_cheats']='1',[RPE]='0; quit'}) issued={}
  fresh() hooks.InitPostEntity.MMDVMDNPCRestoreCVars() tick() tick()
  check(#issued==0,'the record ran something: '..table.concat(issued,' | '))
 else
  hooks.InitPostEntity.MMDVMDNPCRestoreCVars() tick() tick()
  check(cvars[RPE].value=='1' and disk[record]==nil,'the next start did not finish the restore')
 end
elseif scenario=='cvar_admin' then
 cvar(RPE,'1')
 -- An admin turns the RPE body on during the dance: its end keeps that.
 M().Playbacks[npc]={ply=attacker} M().UpdateRPEBodySuppression() tick()
 cvars[RPE].value='2' issued={}
 M().Playbacks[npc]=nil M().UpdateRPEBodySuppression() tick() tick()
 check(cvars[RPE].value=='2' and #issued==0,'the dance\'s end overwrote an admin\'s change: '..table.concat(issued,' | '))
 -- A dance that ends in the frame it began (our 0 not applied yet) still puts the original back.
 M().Playbacks[npc]={ply=attacker} M().UpdateRPEBodySuppression()
 M().Playbacks[npc]=nil M().UpdateRPEBodySuppression() tick() tick()
 check(cvars[RPE].value=='2','a dance that ended in its first frame left the cvar off: '..cvars[RPE].value)
elseif scenario=='built_budget' then
 -- Decoded built animations stay within the byte budget; ones playing are never dropped.
 local function built(ent) local path=M().BuiltPath('m',ent:GetModel())
  disk[path]=util.TableToJSON({format='built-test',model=ent:GetModel(),frame_start=0,frame_end=1,fps=30,frames={{frame=0,bones={},flexes={}}}}) return path end
 local a,b,c=entity('npc'),entity('npc'),entity('npc') local pa,pb,pc=built(a),built(b),built(c)
 M().StopPlayback=function(ent) M().Playbacks[ent]=nil end
 M().Guard.BuiltCacheMaxBytes=#disk[pa]*2+10
 local function play(ent) M().DebugTargets[attacker]=ent receive('mmdvmd_play_request',attacker,'m') check(M().Playbacks[ent]~=nil,'the dance did not start') end
 play(a) M().Playbacks[a]=nil play(b) M().Playbacks[b]=nil play(c) M().Playbacks[c]=nil
 check(M().BuiltCache[pa]==nil and M().BuiltCache[pb]~=nil and M().BuiltCache[pc]~=nil,'the oldest idle built animation was kept past the budget')
 M().BuiltCache={} M().BuiltCacheOrder={} M().BuiltCacheBytes={}
 M().Guard.BuiltCacheMaxBytes=#disk[pa]+10
 play(a) play(b) M().Playbacks[b]=nil play(c)
 check(M().BuiltCache[pa]~=nil and M().BuiltCache[pb]==nil and M().BuiltCache[pc]~=nil,'a playing built animation was dropped, or an idle one kept')
elseif scenario=='build_limits' then
 M().DebugTargets[attacker]=npc
 -- The built files one player may add while the map runs.
 M().Guard.MaxBuiltFilesPerPlayer=1 M().BuiltFilesBy['7656'..attacker.index]=1
 local ok,why=M().BeginBuildForPlayer(attacker,'m',{},nil)
 check(not ok and tostring(why):find('build limit',1,true) and M().BuildJobs[attacker]==nil,'a player built past the file limit: '..tostring(why))
 -- Builds waiting behind a running one.
 M().BuiltFilesBy={} M().Guard.MaxQueuedBuilds=1
 M().BuildJobs[attacker]={id=99,path='running'} M().BuildQueues[attacker]={{path='waiting'}}
 ok,why=M().BeginBuildForPlayer(attacker,'m',{},nil)
 check(not ok and #M().BuildQueues[attacker]==1,'a player queued past the queue limit: '..tostring(why))
 -- A build whose JSON would pass the byte budget stops.
 M().BuildQueues[attacker]=nil
 M().BuildJobs[attacker]={id=7,ply=attacker,ent=npc,sentPlan=true,currentFrame=0,nextRequestFrame=4,startFrame=0,endFrame=100,
  motion={boneTracks={},flexTracks={}},frames={},bones={},flexes={},jsonBytes=M().Guard.MaxBuildJsonBytes-10,inflight={}}
 receive('mmdvmd_build_frame_result',attacker,7,0,1,0,0,true)
 check(M().BuildJobs[attacker]==nil,'a build went past its byte budget')
 -- Admins are not limited.
 M().Guard.MaxBuiltFilesPerPlayer=0 M().BuildJobs[admin]={id=98,path='running'} M().BuildQueues[admin]={{path='waiting'}}
 M().DebugTargets[admin]=npc ok=M().BeginBuildForPlayer(admin,'m',{},nil)
 check(ok and #M().BuildQueues[admin]==2,'an admin was limited')
else
 error('unknown scenario '..tostring(scenario))
end
print('PASS '..scenario)
