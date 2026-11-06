-- R21-B: execute the complete packaged installation override and UI with native/game fixtures.
-- Usage: luajit hotloader_installation_harness.lua <part folder> <client|server> <scenario>
local folder,realm,scenario=arg[1],arg[2],arg[3]
local function check(ok,why) assert(ok,realm..' '..scenario..': '..why) end
local function noop() end
SERVER,CLIENT=realm=='server',realm=='client'
local feature=SERVER and 'physics' or 'rendering'
function istable(v) return type(v)=='table' end
function isstring(v) return type(v)=='string' end
function IsValid(v) return type(v)=='table' and v.valid==true end
function ScrH() return 1080 end
function CurTime() return 100 end RealTime=CurTime SysTime=CurTime
function math.Clamp(v,a,b) return math.min(math.max(v,a),b) end
function CreateClientConVar() return {GetBool=function() return true end} end
cvars={AddChangeCallback=noop}
local hooks,timers={},{}
hook={Add=function(event,id,fn) hooks[event]=hooks[event] or {} hooks[event][id]=fn end,
 Run=function(event,...) for _,fn in pairs(hooks[event] or {}) do fn(...) end end}
timer={Create=function(id,_,_,fn) timers[id]=fn end,Remove=function(id) timers[id]=nil end,Simple=noop}
concommand={Add=noop}
local messages,writes={},0
function MsgN(text) messages[#messages+1]=text end
local player={valid=true,IsListenServerHost=function() return true end}
function LocalPlayer() return player end
game={IsDedicated=function() return SERVER end,SinglePlayer=function() return true end}
system={IsWindows=function() return true end,IsLinux=function() return false end}
-- Stable encoding, plus a lookup for the decoder: the fixtures need no JSON parser.
local decoded={}
local function encode(v)
 if type(v)~='table' then return type(v)=='string' and string.format('%q',v) or tostring(v) end
 local parts={} for k,x in pairs(v) do parts[#parts+1]=encode(k)..':'..encode(x) end
 table.sort(parts) return '{'..table.concat(parts,',')..'}'
end
util={AddNetworkString=noop,SHA256=function() return 'sha' end,
 TableToJSON=function(v) local s=encode(v) decoded[s]=v return s end,JSONToTable=function(s) return decoded[s] end}
net={Receive=noop,Start=noop,WriteString=noop,Broadcast=noop}
local names={client='gmcl_mmdhl_win64.dll',server='gmsv_mmdhl_win64.dll',runtime='mmdhl_runtime_win64.dll',worker='mmdhl_worker.exe',coacd='lib_coacd.dll'}
local files={} for k,name in pairs(names) do files[k]={name=name,size=1,sha256='sha'} end
local release={release='2.3.1',build='release-build',installApi=1,api=1,files=files}
local policy={schema=1,recommended='2.3.1',approved={'2.3.1'},releases={['2.3.1']=release}}
if scenario=='outdated' then
 local old={} for k,v in pairs(release) do old[k]=v end old.release='2.0.0'
 policy.releases={['2.0.0']=old,['2.3.1']={release='2.3.1',build='new-build',installApi=1,api=1,files={}}}
 for k,v in pairs(files) do policy.releases['2.3.1'].files[k]={name=v.name,size=2,sha256='new'} end
 release=old
elseif scenario=='policy' then policy.schema=0 end
file={Exists=function(path)
 return not (scenario=='missing' and path:find('mmdhl_runtime_win64.dll',1,true))
end,Open=function() return {Size=function() return 1 end,Read=function() return 'x' end,Close=noop} end,
 Read=function() return nil end,CreateDir=noop,Write=function() writes=writes+1 end}
local compatibility={schema=1,family='source-win64-v1',libraries={{name='engine.dll'}}}
function include(path) return path=='mmdhl/native_policy.lua' and policy or compatibility end
local function L(key,args)
 local result=key
 for k,v in pairs(args or {}) do result=result..' '..k..'='..tostring(v) end
 return result
end
mmdhl={L=L,Localize=function(v) return v end}
local report={ready=false,pending=false,libraries={{name='engine.dll',match='unverified'},
 {name='future-game-library.dll',match='unverified'},{name='known.dll',match='exact'}},issues={
 {code='game_incompatible',component='client.dll',message='interface slot or class changed\nsecond line'},
 {code='game_unverified',component='future-game-library.dll',message='future build'},
 {code='game_check_failed',component='game',message='native finding'},
 {code='game_unchecked',component='game',message='native finding'},
 {code='future_native_finding',component='new.dll',message='new native diagnostic'}}}
if scenario=='matched' then report={ready=true,pending=false,libraries={{name='engine.dll',match='exact'}},issues={}} end
local completeReport=report
if scenario=='pending' or scenario=='pending-timeout' then report={ready=false,pending=true,libraries={},issues={}} end
local configureCalls=0
local native={ConfigureCompatibility=function()
 configureCalls=configureCalls+1
 if scenario=='fallback' and configureCalls==1 then return nil,'newer policy' end
 return true
end,GetInstallationInfo=function()
 local function identity(name)
  local path='h:/game/'..(name==names.runtime and 'bin/win64/' or 'garrysmod/lua/bin/')..name
  return {installApi=1,api=1,platform='win64',release=release.release,build=release.build,sha256='sha',path=path,expectedPath=path}
 end
 local info={module=identity(names[realm]),runtime=identity(names.runtime)}
 if scenario=='identity' then info.module.sha256='another-build' end
 return info
end,GetCapabilities=function() return {version='2.0.0'} end,
 CheckCompatibility=function()
  if scenario=='failed' then return nil,'check returned an error\nsecond line' end
  if scenario=='throws' then error('check raised an error\nsecond line') end
  return report
 end}
if scenario=='unchecked' then native.CheckCompatibility=nil end
mmdhl_native=native package.preload.mmdhl=function() return native end
dofile(folder..'/overrides/installation.lua')
check(mmdhl.CheckInstallation()==true,'module was not loaded')
local s=mmdhl.GetInstallationStatus()
local function diagnostics()
 local lines={} for _,text in ipairs(messages) do if text:find('Game compatibility:',1,true) then lines[#lines+1]=text end end
 return lines
end
if report.pending then
 check(s.features[feature]==false,'pending library did not hold the feature')
 check(#diagnostics()==0,'incomplete report logged before pending libraries settled')
 hooks.InitPostEntity['MMDHL.InstallationCompatibility']()
 check(timers['MMDHL.InstallationCompatibility']~=nil,'pending retry timer missing')
 if scenario=='pending' then
  report=completeReport timers['MMDHL.InstallationCompatibility']()
  check(timers['MMDHL.InstallationCompatibility']==nil,'settled check kept retrying')
 else
  for _=1,20 do timers['MMDHL.InstallationCompatibility']() end
 end
end
check(s.features[feature]==true,'game finding disabled the feature')
check(s.features.core==true,'game finding disabled the addon')
local expectedReport=report
if scenario=='failed' or scenario=='unchecked' then expectedReport=nil elseif scenario=='throws' then expectedReport=false end
check(s.compatibility==expectedReport,'raw report not retained')
local codes={}
for _,v in ipairs(s.issues) do
 check(not ({game_unverified=true,game_incompatible=true,game_check_failed=true,game_unchecked=true})[v.code],'game warning survived: '..v.code)
 codes[v.code]=true
end
local expected=({unchecked='outdated',fallback='compatibility_fallback',identity='loaded_mismatch',missing='missing',outdated='outdated_release',policy='policy_invalid',['pending-timeout']='game_not_ready'})[scenario]
if expected then check(codes[expected],'unrelated warning disappeared: '..expected)
else check(#s.issues==0,'unexpected issue') end
check(#diagnostics()==1,'diagnostic line was not printed exactly once')
local line=diagnostics()[1]
check(line:find('[Model Hotloader / '..realm..']',1,true),'wrong realm in diagnostic')
check(not line:find('[\r\n]'),'diagnostic spans multiple lines')
if scenario=='failed' or scenario=='throws' then check(line:find('check failed:',1,true),'check error missing')
elseif scenario=='unchecked' then check(line:find('no game-build check',1,true),'unchecked diagnostic missing')
elseif scenario=='pending-timeout' then check(line:find('still pending',1,true),'pending diagnostic missing')
elseif scenario=='matched' then check(line:find('unverified libraries: none; findings: none',1,true),'matched diagnostic wrong')
else
 check(line:find('engine.dll, future-game-library.dll',1,true),'unverified library names missing')
 check(line:find('game_incompatible (client.dll): interface slot or class changed',1,true),'native finding missing')
 check(line:find('future_native_finding (new.dll):',1,true),'future native finding missing')
end
-- Repeated refreshes and the real Recheck path never log another line or invent game issues.
if scenario~='pending-timeout' then
 for _=1,3 do mmdhl.RefreshGameCompatibility() end
 mmdhl.CheckInstallation(true)
end
check(#diagnostics()==1,'refresh/Recheck repeated the diagnostic')
s=mmdhl.GetInstallationStatus()
check(s.features[feature]==true,'Recheck changed the feature state')
dofile(folder..'/mmd_hotloader/lua/mmdhl/installation_ui.lua')
local summary,_,details,pending=mmdhl.InstallationSummary()
if not expected then
 check(summary=='' and details=='' and pending==0,'game finding reached the UI or its problem count')
 mmdhl.serverInstallation={issues=s.issues,features=s.features}
 check(select(4,mmdhl.InstallationSummary())==0,'server finding reached client problem count')
 vgui={Create=function() error('game finding raised a notice') end}
 hooks['MMDHL.InstallationChanged']['MMDHL.InstallationNotice']()
 check(not mmdhl.installationNoticeShown,'game finding marked a notice as shown')
else
 check(summary~='' and details~='','other warning disappeared from the installation UI')
 if scenario~='outdated' then check(pending>0,'other warning removed from the problem count') end
end
check(writes==0,'check wrote a dismissal or other player data')
print('PASS '..realm..' '..scenario)
