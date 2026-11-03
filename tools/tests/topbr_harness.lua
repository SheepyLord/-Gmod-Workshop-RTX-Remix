-- Regression for the packaged client driver and independent imported-game setting.
SERVER=false BRANCH="x86-64"
file={Exists=function() return false end}
local vars,callbacks,commands,hooks={},{},{},{}
local calls={}
function Color(...) return {...} end
function MsgC(...) end
function tobool(v) return v==true or v==1 or v=="1" end
function isstring(v) return type(v)=="string" end
function istable(v) return type(v)=="table" end
function RealTime() return 100 end
function CreateClientConVar(name,value)
    if not vars[name] then
        local cv={value=value}
        function cv:GetBool() return tobool(self.value) end
        function cv:GetFloat() return tonumber(self.value) end
        vars[name]=cv
    end
end
function GetConVar(name) return vars[name] end
function RunConsoleCommand(name,value)
    assert(vars[name],name)
    local old=vars[name].value vars[name].value=value
    if callbacks[name] then callbacks[name](name,old,value) end
end
cvars={AddChangeCallback=function(name,fn) callbacks[name]=fn end}
concommand={Add=function(name,fn) assert(not vars[name],"convar/command collision: "..name) commands[name]=fn end}
hook={Add=function(event,name,fn) hooks[name]=fn end}
local enabled,gameEnabled=false,false
local tries,accepted=0,0
local p={}
p.IsInitialized=function() return true end
p.SetEnabled=function(v) enabled=v end
p.SetGameEnabled=function(v) gameEnabled=v end
p.SetDebugOutput=function(v) calls.debug=v end
p.SetMetallicGeneration=function(v) calls.metal=v end
p.SetAutoDiscover=function(v) calls.discover=v end
p.SetParseCommentedProperties=function(v) calls.comments=v end
p.GetStats=function() return {} end
p.PumpSnapshots=function() calls.pump=(calls.pump or 0)+1 end
p.IsProcessingInBackground=function() return false end
p.GetQueuedMaterialCount=function() return 0 end
p.GetLastProcessedCount=function() return 0 end
p.ClearCache=function() calls.clear=true end
p.QueueMaterialsForProcessing=function() calls.queue=true end
p.QueueGameMaterial=function(name,source,base)
    assert(name=="mmd/0123456789abcdef/material_0")
    assert(source=="E:/models/test.pmx" and base=="tex/test_D.png")
    tries=tries+1
    if tries>1 then accepted=accepted+1 return true end
    return false
end
MaterialPipeline={ToPBR=p}
dofile(arg[1])
assert(vars.rtx_topbr_enabled.value=="0")
assert(vars.rtx_topbr_parse_commented_properties.value=="0")
assert(vars.rtx_topbr_game_maps:GetBool())
commands.rtx_topbr_stats() -- Removed APIs must never be called.
RunConsoleCommand("rtx_topbr_debug","1") assert(calls.debug==true)
RunConsoleCommand("rtx_topbr_autodiscover","0") assert(calls.discover==false)
RunConsoleCommand("rtx_topbr_enabled","1") assert(enabled)
RunConsoleCommand("rtx_topbr_game_maps","0") assert(not gameEnabled and enabled)
RunConsoleCommand("rtx_topbr_game_maps","1") assert(gameEnabled)
local id=string.rep("a",64)
mmdhl = {assets = {}, library = {entries = {}}}
mmdhl.assets[id] = {materials = {{path = "mmd/0123456789abcdef/material_0"}}}
mmdhl.library.entries[id] = {source = "E:/models/test.pmx", info = {materials = {{base = "tex/test_D.png"}}}}

for _=1,3 do hooks.RTXToPBR_GameMaps() end
assert(tries==1 and accepted==0)
-- Advance the sweep interval: unavailable live hashes must retry.
function RealTime() return 106 end
hooks.RTXToPBR_GameMaps()
assert(tries==2 and accepted==1)
function RealTime() return 112 end
hooks.RTXToPBR_GameMaps()
assert(tries==2 and accepted==1) -- successful requests are one-time per client session
-- Missing source/base metadata still reaches the native texture-identity registry.
local missingTries=0
p.QueueGameMaterial=function(name,source,base)
    assert(name=="mmd/0123456789abcdef/material_0")
    assert(source=="" and base=="")
    missingTries=missingTries+1
    return true
end
mmdhl.library.entries[id]=nil
commands.rtx_topbr_clear() assert(calls.clear)
hooks.RTXToPBR_GameMaps() assert(missingTries==1)
RunConsoleCommand("rtx_topbr_game_maps","0")
commands.rtx_topbr_clear()
hooks.RTXToPBR_GameMaps() assert(missingTries==1)
RunConsoleCommand("rtx_topbr_game_maps","1")
hooks.RTXToPBR_GameMaps() assert(missingTries==2)
hooks.RTXToPBR_Snapshots() assert(calls.pump==1)
print("PASS ToPBR driver: diagnostics, settings, bounded metadata discovery, hash retry, source-less queue and clear/requeue")
