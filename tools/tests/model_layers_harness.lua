local source, scenario = ...
local hooks, commands, writes, tracked = {}, {}, {}, {}
local enabled, revision, now, skin = true, 1, 0, 0
istable=function(v) return type(v)=="table" end
isfunction=function(v) return type(v)=="function" end
isstring=function(v) return type(v)=="string" end
IsValid=function(v) return v and v.valid end
RealTime=function() return now end
CreateClientConVar=function() return {GetBool=function() return enabled end} end
hook={Add=function(event,name,fn) hooks[event]=fn end}
concommand={Add=function(name,fn) commands[name]=fn end}
local materials={"tex/model/template face","tex/model/template eyeline up (sirome)","tex/model/hei","tex/model/touming"}
if scenario=="ordinary_hei" then materials={"tex/model/body","tex/model/hei"} end
local sub=""
local queries=0
local ent={valid=true,GetModel=function() return "models/test.mdl" end,GetSkin=function() return skin end,
 SkinCount=function() return 2 end,GetMaterials=function() queries=queries+1 return materials end,
 GetSubMaterial=function(_,i) return i==0 and sub or "" end}
ents={GetAll=function() return scenario=="client_entity" and {} or {ent} end}
local native={['tex/model/template face']={'0x1'},['tex/model/template eyeline up (sirome)']={'0x2'},
 ['tex/model/hei']={'0x3'},['tex/model/touming']={'0x2'},['tex/model/body']={'0x1'},
 ['custom/outline_shell']={'0x4'},['pseudoplayermaterial_outline']={'0x9'}}
if scenario=="collision" then native['tex/model/template face']={'0x3'} end
if scenario=="late_hash" then native['tex/model/hei']={} end
if scenario=="proxy" then ent.RTXMaterials={{name='tex/model/hei',material={GetName=function() return 'pseudoplayermaterial_outline' end}}} end
RemixMaterial={TrackMaterial=function(name) tracked[name]=true end,
 GetAllTextureHashes=function(name) return native[name] or {} end,
 GetMaterialHashRevision=function() return revision end}
if scenario=="cached" then RemixMaterial.GetCachedMaterials=function() return {'custom/outline_shell'} end end
local fail=false
RemixConfig={SetConfigVariable=function(key,value)
 writes[#writes+1]={key,value};if fail then fail=false return false end return true
end}
if scenario=="no_api" then RemixConfig=nil end
assert(loadfile(source))()
if scenario=="client_entity" then hooks.OnEntityCreated(ent) end
local function run() hooks.Think() end
local function last(key) for i=#writes,1,-1 do if writes[i][1]==key then return writes[i][2] end end end
run()
if scenario=="no_api" then assert(#writes==0) print('PASS '..scenario) return end
local expected='0x3'
if scenario=="collision" or scenario=="late_hash" or scenario=="ordinary_hei" then expected='' end
if scenario=="proxy" then expected='0x3, 0x9' end
if scenario=="cached" then expected='0x3, 0x4' end
assert(last('rtx.gmod.ignoredOutlineTextures')==expected,last('rtx.gmod.ignoredOutlineTextures'))
assert(last('rtx.gmod.ignoreOutlineMeshes')=='True')
local count=#writes run() assert(#writes==count and queries==1)
if scenario=="late_hash" then
 native['tex/model/hei']={'0x3'} run() assert(last('rtx.gmod.ignoredOutlineTextures')=='0x3')
elseif scenario=="toggle" then
 enabled=false run() assert(last('rtx.gmod.ignoreOutlineMeshes')=='False' and last('rtx.gmod.ignoredOutlineTextures')=='')
 enabled=true run() assert(last('rtx.gmod.ignoredOutlineTextures')=='0x3')
elseif scenario=="submaterial" then
 sub='!custom/outline_shell' now=0.2 run() assert(last('rtx.gmod.ignoredOutlineTextures')=='0x3, 0x4')
elseif scenario=="skin_change" then
 skin=1 run() assert(queries==2 and last('rtx.gmod.ignoredOutlineTextures')=='0x3')
elseif scenario=="retry" then
 enabled=false fail=true run() count=#writes run() assert(#writes==count+1)
end
assert(not tracked.pseudoplayermaterial_outline)
print('PASS '..scenario)
