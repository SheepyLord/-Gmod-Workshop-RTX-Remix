local source, scenario = ...
local function eq(a,b,why) assert(a==b,(why or "")..": "..tostring(a).." ~= "..tostring(b)) end
local function pack(...) return {n=select("#",...),...} end
local function denied(fn) local ok,err=pcall(fn) assert(not ok and tostring(err):find("guard",1,true),tostring(err)) end
CLIENT, SERVER, MENU_DLL = true, false, false
if scenario=="realm_server" then CLIENT,SERVER=false,true end
if scenario=="realm_menu" then CLIENT,MENU_DLL=false,true end
local multiplayer = scenario=="verified_multiplayer" or scenario=="cached_multiplayer"
__NATIVELOADER_RTX_GUARD_EARLY = not multiplayer and scenario~="no_proof" and scenario~="inherited_proof"
    and scenario~="autorun"
-- status.json as the loader writes it. Remote vanilla clients have none; an RTX-off start reports
-- another outcome. The private multiplayer route never needs it.
local statusText='{\n"schema":1,"loader_version":"0.10.1","utc":"2026-10-31T00:00:00.000Z","process_id":1,"startup_elapsed_ms":1.0,\n'
    ..'"deployment":{"outcome":"unchanged"},\n"activation":{"outcome":"active","reason":"runtime gmod-rtx-remix 1.0.0"},\n"session":{}\n}\n'
if multiplayer or scenario=="no_proof" or scenario=="inherited_proof" or scenario=="remote_initializer"
    or scenario=="realm_server" or scenario=="realm_menu" then statusText=nil end
if scenario=="inactive_start" then statusText=statusText:gsub('"outcome":"active"','"outcome":"inactive"') end
local sentFiles=0
function AddCSLuaFile() sentFiles=sentFiles+1 end
local cv, playerMeta, cvMeta = {}, {}, {}
local getBoolCalls=0
function cvMeta:GetName() return self.name end
function cvMeta:GetString() return self.value end
function cvMeta:GetInt() return tonumber(self.value) or 0 end
function cvMeta:GetFloat() return tonumber(self.value) or 0 end
function cvMeta:GetBool() getBoolCalls=getBoolCalls+1 return tonumber(self.value) ~= 0 end
for _,name in ipairs({"SetInt","SetFloat","SetString","SetBool"}) do
    cvMeta[name]=function(self,value)
        self.value=type(value)=="boolean" and (value and "1" or "0") or tostring(value)
        return "set",value
    end
end
local function convar(name,value) local obj=setmetatable({name=name,value=value},{__index=cvMeta}) cv[name]=obj return obj end
local createCount=0
function CreateClientConVar(name,value)
    createCount=createCount+1
    return cv[name] or convar(name,scenario=="off" and "0" or value)
end
function GetConVar(name) return cv[name] end
convar("mat_motion_blur_enabled","0")
convar("mat_dxlevel","90")
convar("mat_hdr_level","2")
convar("mat_queue_mode","0")
convar("ordinary","0")
local commands={}
function RunConsoleCommand(...) commands[#commands+1]={...} return "run",... end
function playerMeta:ConCommand(...) commands[#commands+1]={...} return "command",... end
game={ConsoleCommand=function(...) commands[#commands+1]={...} return "console",... end}
function FindMetaTable(name) if name=="Player" then return playerMeta elseif name=="ConVar" then return cvMeta end end
local statusReads=0
file={Read=function(name,realm)
    if name=="native-loader/status.json" then eq(realm,"DATA") statusReads=statusReads+1 return statusText end
    eq(name,"cfg/nativeloader_session.cfg") eq(realm,"MOD")
    return 'mat_dxlevel "90"\nmat_queue_mode "0"\n'
end}
function ScrW() return 1920 end
function ScrH() return 1080 end
function IsValid(obj) return type(obj)=="table" and obj.valid==true end
local messages,errorReports={},{}
function MsgN(text) messages[#messages+1]=text end
function ErrorNoHaltWithStack(text) errorReports[#errorReports+1]=text end
local now,frameCount=0,1
function SysTime() return now end
function FrameNumber() return frameCount end
if scenario=="prerender_boundary" then FrameNumber=nil end
IMAGE_FORMAT_DEFAULT=-1
IMAGE_FORMAT_BGRA8888=12
IMAGE_FORMAT_RGBA8888=0
IMAGE_FORMAT_R32F=nil -- the live importer build does not export this supported native format
IMAGE_FORMAT_COUNT=999
RT_SIZE_NO_CHANGE,RT_SIZE_FULL_FRAME_BUFFER,RT_SIZE_LITERAL,RT_SIZE_HDR=0,4,8,3
MATERIAL_RT_DEPTH_SEPARATE,MATERIAL_RT_DEPTH_SHARED,MATERIAL_RT_DEPTH_NONE,MATERIAL_RT_DEPTH_ONLY=0,1,2,3
local targets,rtCalls={},{}
local function texture(name,w,h)
    return {name=name,w=w,h=h,Width=function(t)return t.w end,Height=function(t)return t.h end,GetName=function(t)return t.name end}
end
function GetRenderTarget(name,w,h)
    rtCalls[#rtCalls+1]={name,w,h}
    local key=name:lower():gsub("%.[^./]*$","")
    targets[key]=targets[key] or texture(key,w,h)
    return targets[key],"rt-return"
end
function GetRenderTargetEx(name,w,h,size,depth,flags,rtflags,format)
    rtCalls[#rtCalls+1]={name,w,h,size,depth,flags,rtflags,format}
    if size==4 then w,h=ScrW(),ScrH() end
    targets[name]=targets[name] or texture(name,w,h)
    return targets[name],"ex-return"
end
local created,mats,shaderQueries={},{},0
local function material(shader) return {GetShader=function()shaderQueries=shaderQueries+1 return shader end} end
function CreateMaterial(name,shader,data) created[#created+1]={name,shader,data} return material(shader) end
function Material(name) mats[#mats+1]=name return material(name=="bad_shader" and "screenspace_general" or "UnlitGeneric") end
local depthCalls,quadCalls,setMaterialCalls,rtExCalls,targetQueries=0,0,0,0,0
local currentRT, rtStack=nil,{}
local cameraDepth,clipDepth,modelDepth=0,0,0
local depthRange={0,0.1}
render={}
function render.PushRenderTarget(tex) rtStack[#rtStack+1]={value=currentRT} currentRT=tex return "push" end
function render.PopRenderTarget() assert(#rtStack>0,"native RT underflow") currentRT=table.remove(rtStack).value end
function render.GetRenderTarget() targetQueries=targetQueries+1 return currentRT end
function render.SetRenderTarget(tex) currentRT=tex return "target" end
function render.SetRenderTargetEx(index,tex) rtExCalls=rtExCalls+1 if index==0 then currentRT=tex end return "mrt",index,tex end
function render.GetResolvedFullFrameDepth() depthCalls=depthCalls+1 return texture("depth",1,1) end
function render.RedownloadAllLightmaps() depthCalls=depthCalls+1 return "reload" end
function render.SetMaterial(mat) setMaterialCalls=setMaterialCalls+1 return mat end
function render.MaterialOverride(mat) return mat end
function render.DrawScreenQuad() quadCalls=quadCalls+1 return "quad" end
function render.DepthRange(a,b) depthRange={a,b} end
function render.PushCustomClipPlane() clipDepth=clipDepth+1 end
function render.PopCustomClipPlane() assert(clipDepth>0) clipDepth=clipDepth-1 end
local viewCalls,viewCallback=0,nil
function render.RenderView(...) viewCalls=viewCalls+1 if viewCallback then return viewCallback(...) end return "view",... end
cam={}
function cam.Start() cameraDepth=cameraDepth+1 return "camera" end
function cam.End3D() assert(cameraDepth>0,"native camera underflow") cameraDepth=cameraDepth-1 end
function cam.Start2D() return cam.Start({type="2D"}) end
function cam.End2D() return cam.End3D() end
function cam.Start3D() return cam.Start({type="3D"}) end
function cam.PushModelMatrix() modelDepth=modelDepth+1 end
function cam.PopModelMatrix() assert(modelDepth>0) modelDepth=modelDepth-1 end
function cam.Start3D2D() cam.Start3D() cam.PushModelMatrix() end
function cam.End3D2D() cam.PopModelMatrix() cam.End3D() end
local meshEnds=0
mesh={Begin=function()end,End=function()meshEnds=meshEnds+1 end}
local hooks={}
hook={GetTable=function()return hooks end}
function hook.Add(event,id,fn) hooks[event]=hooks[event] or {} hooks[event][id]=fn end
function hook.Remove(event,id) if hooks[event] then hooks[event][id]=nil end end
function hook.Call(event,gm,...)
    for id,fn in pairs(hooks[event] or {}) do
        local r
        if type(id)=="string" then r=pack(fn(...))
        elseif IsValid(id) then r=pack(fn(id,...))
        else hooks[event][id]=nil end
        if r and r[1]~=nil then return unpack(r,1,6) end
    end
    if gm and gm[event] then return gm[event](gm,...) end
end
function hook.Run(event,...) return hook.Call(event,nil,...) end
local timers,changes={},{}
timer={Create=function(id,delay,count,fn)timers[id]=fn end,Simple=function(delay,fn)timers.simple=fn end}
cvars={AddChangeCallback=function(name,fn,id)changes[name]={fn=fn,id=id}end}
local postCalls=0
function DrawBloom(...) postCalls=postCalls+1 return "bloom",... end
halo={Render=function(...)postCalls=postCalls+1 return "halo",... end}
local beforeCall,beforeAdd,beforeRT,beforeMaterial=hook.Call,hook.Add,GetRenderTargetEx,CreateMaterial
local beforeTimer,beforeCvars=timer.Create,cvars.AddChangeCallback
local privateHook,privateEnvironment,temporaryAPI
-- The verified bootstrap's private environment: the marker is raw-set there and nowhere else.
privateHook=setmetatable({Add=function(...)return hook.Add(...)end},{__index=hook})
privateEnvironment=setmetatable({hook=privateHook},{__index=_G,__newindex=_G})
rawset(privateEnvironment,"NATIVELOADER_VERIFIED_MULTIPLAYER",true)
local function ownedFunction(fn) return setfenv(fn,privateEnvironment) end
local cachedOwnedCalls,cachedGoodCalls=0,0
local cachedOwned,cachedCommunity,cachedInit,cachedObject,cachedObjectFn
if scenario=="cached_multiplayer" then
    cachedOwned=ownedFunction(function()
        cachedOwnedCalls=cachedOwnedCalls+1
        render.PushRenderTarget(texture("existing-late-hook",32,32))
        error("existing owned render callback failure")
    end)
    cachedCommunity=function()return "server-delivered"end
    cachedInit=ownedFunction(function()return "loading identity"end)
    cachedObject={valid=true}
    cachedObjectFn=ownedFunction(function(self,value)eq(self,cachedObject)eq(value,7)return false,2,nil,4,5,6,7 end)
    hook.Add("HUDPaint","already-registered",cachedOwned)
    hook.Add("PostDrawHUD","server-hud",cachedCommunity)
    hook.Add("PostRender",cachedObject,cachedObjectFn)
    for _,event in ipairs({"Initialize","InitPostEntity","OnReloaded"}) do hook.Add(event,"loading",cachedInit) end
end
if multiplayer or scenario=="inherited_proof" then
    if multiplayer then
        temporaryAPI=setmetatable({},{__index=function()error("temporary client API must not be consulted")end})
        __NATIVELOADER_CLIENT_API=temporaryAPI
    else
        -- A global marker cannot authorize installation, nor can an inherited one.
        NATIVELOADER_VERIFIED_MULTIPLAYER=true
        dofile(source)
        rawset(privateEnvironment,"NATIVELOADER_VERIFIED_MULTIPLAYER",nil)
    end
    local chunk=assert(loadfile(source))
    setfenv(chunk,privateEnvironment)
    chunk()
else
    dofile(source)
end
local guard=NativeLoaderRenderGuard
if scenario=="no_proof" or scenario=="inherited_proof" or scenario=="realm_server" or scenario=="realm_menu"
    or scenario=="remote_initializer" or scenario=="inactive_start" then
    eq(guard,nil) eq(createCount,0) eq(hook.Call,beforeCall) eq(GetRenderTargetEx,beforeRT) eq(CreateMaterial,beforeMaterial)
    eq(cv.mat_motion_blur_enabled:GetString(),"0")
    DrawBloom() halo.Render() eq(postCalls,2)
    RunConsoleCommand("mat_dxlevel","95") eq(#commands,1)
    eq(#messages,0)
    eq(sentFiles,0,"the guard is never sent to clients by AddCSLuaFile")
    print("PASS "..scenario)
    return
end
eq(guard.version,2)

if scenario=="verified_multiplayer" then
    eq(__NATIVELOADER_RTX_GUARD_EARLY,false)
    eq(guard.installation,"verified multiplayer bootstrap")
    eq(statusReads,0,"the private route does not consult status.json")
    eq(rawget(_G,"NATIVELOADER_VERIFIED_MULTIPLAYER"),nil,"proof remains private to the verified chunk")
    eq(__NATIVELOADER_CLIENT_API,temporaryAPI,"temporary API is neither used nor changed")
    eq(hook.Call,beforeCall,"the remote server's dispatcher stays unchanged")
    eq(rawget(privateHook,"Call"),nil,"no private proxy-only dispatcher replacement")
    local calls=0
    local fn=ownedFunction(function()calls=calls+1 error("verified MP callback failure")end)
    privateHook.Add("PostRender","mp-failure",fn)
    local registry=hook.GetTable()
    assert(registry.PostRender["mp-failure"]~=fn,"owned late render registration is wrapped")
    for _=1,4 do hook.Call("PostRender") end
    eq(calls,3,"quarantined after three consecutive failures")
    eq(guard.late_render_wrappers,true)
    eq(#errorReports,1,"the original error is reported once per interval")
    assert(errorReports[1]:find("verified MP callback failure",1,true))
    -- Server-delivered callbacks, timers and cvar callbacks keep their identity and engine behaviour.
    local server=function()error("server callback error")end
    hook.Add("PostRender","server",server)
    eq(registry.PostRender.server,server,"community registration unchanged")
    assert(not pcall(hook.Call,"PostRender"),"a server error still propagates as in vanilla GMod")
    hook.Remove("PostRender","server")
    local serverTimer=function()error("server timer")end
    timer.Create("server-timer",1,0,serverTimer) eq(timers["server-timer"],serverTimer)
    local ownedTimer=ownedFunction(function()error("owned timer")end)
    timer.Create("owned-timer",1,0,ownedTimer) assert(timers["owned-timer"]~=ownedTimer,"owned timer protected")
    for _=1,3 do timers["owned-timer"]() end
    local installed=hook.Add
    local again=assert(loadfile(source)) setfenv(again,privateEnvironment) again()
    eq(hook.Add,installed) eq(createCount,1) eq(NativeLoaderRenderGuard,guard)
elseif scenario=="cached_multiplayer" then
    eq(guard.installation,"verified multiplayer bootstrap") eq(guard.late_render_wrappers,true)
    local registry=hook.GetTable()
    assert(registry.HUDPaint["already-registered"]~=cachedOwned,"existing owned render entry wrapped")
    eq(registry.PostDrawHUD["server-hud"],cachedCommunity,"existing server entry keeps its identity")
    for _,event in ipairs({"Initialize","InitPostEntity","OnReloaded"}) do
        eq(registry[event].loading,cachedInit,"loading identity retained for bootstrap replay")
    end
    hook.Add("HUDPaint","healthy",ownedFunction(function()cachedGoodCalls=cachedGoodCalls+1 end))
    for _=1,4 do beforeCall("HUDPaint") end
    eq(cachedOwnedCalls,3) eq(cachedGoodCalls,4) eq(#rtStack,0)
    local laterBadCalls=0
    local laterBad=ownedFunction(function()laterBadCalls=laterBadCalls+1 error("future render callback failure")end)
    hook.Add("HUDPaint","later",laterBad)
    for _=1,4 do beforeCall("HUDPaint") end
    eq(laterBadCalls,3) eq(cachedGoodCalls,8)
    hook.Add("HUDPaint","later",laterBad) -- Same ID/function does not reset quarantine.
    beforeCall("HUDPaint") eq(laterBadCalls,3) eq(cachedGoodCalls,9)
    local replaced=0
    hook.Add("HUDPaint","later",ownedFunction(function()replaced=replaced+1 end))
    beforeCall("HUDPaint") eq(replaced,1) eq(cachedGoodCalls,10)
    local result=pack(beforeCall("PostRender",nil,7))
    eq(result.n,6) eq(result[1],false) eq(result[2],2) eq(result[3],nil) eq(result[6],6)
    local initFn=ownedFunction(function()return "replay"end)
    hook.Add("InitPostEntity","new-owned-init",initFn)
    eq(registry.InitPostEntity["new-owned-init"],initFn,"future owned init identity retained")
    cv.nativeloader_guard.value="0"
    assert(not pcall(beforeCall,"HUDPaint")) eq(cachedOwnedCalls,4,"off bypasses late quarantine")
elseif scenario=="install" then
    eq(guard.installation,"early")
    local call,rt=hook.Call,GetRenderTargetEx
    dofile(source)
    eq(createCount,1) eq(hook.Call,call) eq(GetRenderTargetEx,rt)
    eq(GetConVar("mat_motion_blur_enabled"):GetString(),"1")
    eq(cv.mat_motion_blur_enabled.value,"0")
    DrawBloom() halo.Render() eq(postCalls,0)
    cv.nativeloader_guard.value="0"
    eq(DrawBloom(7),"bloom") eq(halo.Render(),"halo") eq(postCalls,2)
    eq(GetConVar("mat_motion_blur_enabled"):GetInt(),0)
elseif scenario=="autorun" then
    -- A local RTX start whose early view was unavailable installs from the companion autorun.
    eq(guard.installation,"autorun") eq(statusReads,1)
    assert(hook.Call~=beforeCall,"local dispatcher protected as in the early route")
    eq(guard.late_render_wrappers,nil)
    local fn=function()error("local addon error")end
    hook.Add("HUDPaint","local",fn)
    eq(hook.GetTable().HUDPaint["local"],fn,"local registrations keep their identity")
    hook.Call("HUDPaint") eq(#guard.errors,1)
    DrawBloom() eq(postCalls,0)
elseif scenario=="pins" then
    RunConsoleCommand("mat_dxlevel","95") eq(#commands,0)
    cv.mat_dxlevel:SetInt(95) cv.mat_dxlevel:SetFloat(95) cv.mat_dxlevel:SetString("bogus") cv.mat_queue_mode:SetBool(true)
    cv.mat_hdr_level:SetString("1")
    local spoof=assert(loadstring('RunConsoleCommand("mat_dxlevel","95")', "@lua/autorun/nativeloader_imposter.lua"))
    spoof()
    eq(cv.mat_dxlevel.value,"90") eq(cv.mat_queue_mode.value,"0") eq(cv.mat_hdr_level.value,"2")
    cv.mat_queue_mode:SetBool(false) eq(cv.mat_queue_mode.value,"0")
    local player=setmetatable({},{__index=playerMeta})
    player:ConCommand('echo "a;b"; mat_dxlevel 95')
    game.ConsoleCommand("echo ok\nmat_queue_mode 1")
    player:ConCommand('alias later "mat_dxlevel 95; echo x";later')
    RunConsoleCommand("incrementvar","mat_queue_mode","0","3","1")
    RunConsoleCommand("mat_reloadallmaterials") player:ConCommand("mat_setvideomode 1920 1080 1")
    eq(#commands,0)
    player:ConCommand('echo "mat_dxlevel 95; still text"')
    RunConsoleCommand("ordinary","1") player:ConCommand("mat_dxlevel")
    eq(#commands,3)
    RunConsoleCommand("mat_dxlevel","90.0") eq(#commands,4)
    local before=#messages
    RunConsoleCommand("mat_dxlevel","95") RunConsoleCommand("mat_dxlevel","95")
    eq(#messages,before,"log once")
elseif scenario=="native_nul" then
    local nul=string.char(0)
    local player=setmetatable({},{__index=playerMeta})
    denied(function()RunConsoleCommand("mat_restart"..nul)end)
    denied(function()RunConsoleCommand("mat_hdr_level"..nul,"0")end)
    denied(function()RunConsoleCommand("alias","later","mat_restart"..nul)end)
    denied(function()player:ConCommand("echo safe"..nul..";mat_restart")end)
    denied(function()game.ConsoleCommand("echo safe"..nul.."\nmat_hdr_level 0")end)
    denied(function()CreateMaterial("name"..nul,"UnlitGeneric",{})end)
    denied(function()CreateMaterial("name","DepthWrite"..nul,{})end)
    denied(function()Material("normal"..nul)end)
    eq(#commands,0,"no malformed native command strings")
    eq(#created,0,"no malformed native material creation")
    eq(#mats,0,"no malformed native material load")
    RunConsoleCommand("ordinary","1")
    CreateMaterial("ordinary","UnlitGeneric",{})
    Material("normal")
    eq(#commands,1) eq(#created,1) eq(#mats,1)
elseif scenario=="targets" then
    local tex,extra=GetRenderTarget("fresh",256,256) eq(extra,"rt-return")
    local full=GetRenderTargetEx("_GMOD_FrameBlend",-1,-1,4,0,0,0,-1) eq(full.w,1920)
    GetRenderTargetEx("literal",300,250,8,0,0,0,12)
    local shadow=GetRenderTargetEx("mmdhl_shadow_r32",1024,1024,RT_SIZE_NO_CHANGE,MATERIAL_RT_DEPTH_SEPARATE,14,0,27)
    eq(shadow.w,1024) eq(shadow.h,1024) eq(rtCalls[#rtCalls][8],27,"actual importer signature reaches native allocation")
    -- The native API truncates fractional sizes, as stock code computing ScrW() / 3 relies on.
    local third=GetRenderTarget("third",ScrW()/3.5,ScrH()/2.5) eq(rtCalls[#rtCalls][2],ScrW()/3.5,"original arguments forwarded")
    assert(third,"fractional dimensions accepted")
    GetRenderTargetEx("fractional",300.75,250.5,8,0,0,0,12)
    for i=1,30 do GetRenderTarget("importer_copy_"..i,2048,2048) end
    local before=#rtCalls
    for _,name in ipairs({"_rt_shadowdepthtexture_0","_RT_RESOLVEDFULLFRAMEDEPTH.changed","_rt_resolvedfullframedepthsky"}) do
        denied(function()GetRenderTargetEx(name,512,512,8,0,0,0,12)end)
    end
    for _,value in ipairs({0,-2,math.huge,0/0,100000,0.5}) do denied(function()GetRenderTarget("bad",value,256)end) end
    denied(function()GetRenderTargetEx("badformat",128,128,8,0,0,0,9999)end)
    denied(function()GetRenderTargetEx("unknownlarge",128,128,8,0,0,0,2147483647)end)
    denied(function()GetRenderTargetEx("badsize",128,128,nil,0,0,0,12)end)
    denied(function()GetRenderTargetEx("baddepth",128,128,8,9999,0,0,12)end)
    denied(function()GetRenderTargetEx("badflags",128,128,8,0,math.huge,0,12)end)
    denied(function()GetRenderTargetEx("sentinel",128,128,8,0,0,0,IMAGE_FORMAT_COUNT)end)
    IMAGE_FORMAT_BGRA8888=9999
    denied(function()GetRenderTargetEx("changed",128,128,8,0,0,0,IMAGE_FORMAT_BGRA8888)end)
    eq(#rtCalls,before,"rejected before native allocation")
    GetRenderTargetEx("snapshot",128,128,8,0,0,0,12)
    render.PushRenderTarget(nil) render.PopRenderTarget()
    render.PushRenderTarget(tex) cam.Start2D() render.SetMaterial(CreateMaterial("ok","UnlitGeneric",{}))
    eq(render.DrawScreenQuad(),"quad") cam.End2D() render.PopRenderTarget()
    eq(#rtStack,0) eq(cameraDepth,0) eq(quadCalls,1)
    eq(render.SetRenderTargetEx(0,tex),"mrt")
    render.SetRenderTargetEx(0)
    local calls=rtExCalls denied(function()render.SetRenderTargetEx(1,tex)end) eq(rtExCalls,calls)
    -- Clearing MRT slots 1-3 with nil is legal stock behaviour; other slots are not.
    for slot=1,3 do eq(select(2,render.SetRenderTargetEx(slot,nil)),slot) end
    eq(rtExCalls,calls+3)
    for _,slot in ipairs({4,-1,1.5}) do denied(function()render.SetRenderTargetEx(slot,nil)end) end
    eq(rtExCalls,calls+3)
elseif scenario=="shaders" then
    denied(function()CreateMaterial("depth","DepthWrite",{})end)
    denied(function()CreateMaterial("fx","SCREENSPACE_GENERAL",{})end)
    eq(#created,0,"no native CreateMaterial")
    denied(function()render.SetMaterial(material("screenspace_general"))end) eq(setMaterialCalls,0)
    denied(function()Material("bad_shader")end) eq(#mats,1,"disk loading gap is explicit")
    denied(function()render.GetResolvedFullFrameDepth()end)
    denied(function()render.RedownloadAllLightmaps()end) eq(depthCalls,0)
    render.SetMaterial(Material("normal")) render.MaterialOverride(nil) render.DrawScreenQuad()
    eq(quadCalls,1)
elseif scenario=="views" then
    render.RenderView(nil) render.RenderView({w=512,h=512}) eq(viewCalls,2,"sequential stock views")
    viewCallback=function()return render.RenderView({})end
    denied(function()render.RenderView({})end)
    viewCallback=nil
    render.RenderView({}) eq(viewCalls,7,"nested state restored")
    local count=viewCalls denied(function()render.RenderView({w=math.huge})end) eq(viewCalls,count)
    denied(function()render.RenderView({origin={x=0,y=0,z=0/0}})end) eq(viewCalls,count)
    cam.Start3D() cam.End3D() cam.Start3D2D() cam.End3D2D()
    eq(cameraDepth,0) eq(modelDepth,0)
elseif scenario=="hooks" then
    local calls=0
    local bad=function()calls=calls+1 error("C:/Users/private-person/secret.txt")end
    hook.Add("PostRender","bad",bad)
    local registry=hook.GetTable()
    for _=1,5 do hook.Call("PostRender") end
    eq(calls,3,"quarantine needs three consecutive failures") eq(hook.GetTable(),registry) eq(registry.PostRender.bad,bad)
    eq(#errorReports,1,"original error reported once per interval")
    assert(errorReports[1]:find("private-person",1,true),"the engine error output receives the original message")
    for _,record in ipairs(guard.errors) do assert(not record.reason:find("private-person",1,true)) end
    assert(guard.errors[#guard.errors].reason:find("quarantined",1,true))
    local good=function()return false,2,nil,4,5,6,7 end
    hook.Add("PostRender","bad",good)
    local values=pack(hook.Call("PostRender")) eq(values.n,6) eq(values[1],false) eq(values[3],nil) eq(values[6],6)
    eq(registry.PostRender.bad,good)
    hook.Remove("PostRender","bad")
    local object={valid=true}
    local objectFn=function(self,a)eq(self,object)eq(a,"argument")end
    hook.Add("HUDPaint",object,objectFn) hook.Add("HUDPaint",{valid=false},function()error("invalid object")end)
    hook.Call("HUDPaint",nil,"argument") eq(hook.GetTable().HUDPaint[object],objectFn)
    local gm={RenderScene=function(self,a)eq(a,9)return "gm",nil,3 end}
    local result=pack(hook.Call("RenderScene",gm,9)) eq(result.n,3) eq(result[1],"gm")
    -- A gamemode method is contained and reported, never quarantined (base GM:PostDrawViewModel draws the hands).
    local hands=0
    gm.PostDrawViewModel=function(self) hands=hands+1 if hands<=6 then error("hands failed") end return "hands" end
    for _=1,6 do eq(select("#",hook.Call("PostDrawViewModel",gm)),0) end
    eq(hook.Call("PostDrawViewModel",gm),"hands","gamemode method still runs after repeated failures") eq(hands,7)
    -- A success resets the streak; failures spread further than the window apart never quarantine.
    local flaky,flakyCalls=nil,0
    flaky=function() flakyCalls=flakyCalls+1 if flakyCalls%3~=0 then error("intermittent") end end
    hook.Add("PreDrawHUD","flaky",flaky)
    for _=1,9 do hook.Call("PreDrawHUD") end
    eq(flakyCalls,9,"intermittent failures are contained without quarantine")
    local slowCalls=0
    hook.Add("PostDrawHUD","slow",function()slowCalls=slowCalls+1 error("slow")end)
    for _=1,4 do now=now+11 hook.Call("PostDrawHUD") end
    eq(slowCalls,4,"failures outside the window do not accumulate")
    hook.Call("PostDrawHUD") hook.Call("PostDrawHUD") hook.Call("PostDrawHUD")
    eq(slowCalls,6,"three failures within the window quarantine")
    -- Reports are rate-limited per callback and name the suppressed count.
    local reportsBefore=#errorReports
    now=now+11
    hook.Add("PostDrawHUD","slow",function()error("slow again")end)
    for _=1,3 do hook.Call("PostDrawHUD") end
    eq(#errorReports,reportsBefore+1,"one report per callback per interval")
    hook.Add("UnrelatedEvent","bad",bad) assert(not pcall(hook.Call,"UnrelatedEvent"))
    for _,message in ipairs(messages) do assert(not message:find("private-person",1,true)) end
elseif scenario=="report_caps" then
    -- A flood of refusals from many sources cannot hide later error records.
    for i=1,140 do
        local spam=assert(loadstring('RunConsoleCommand("mat_dxlevel","95")', "@lua/autorun/spam"..i..".lua"))
        spam()
    end
    eq(#guard.blocked,128)
    hook.Add("HUDPaint","after-flood",function()error("after the flood")end)
    hook.Call("HUDPaint")
    eq(#guard.errors,1,"error records keep their own cap")
elseif scenario=="cleanup" then
    local base,child=texture("base",128,128),texture("child",128,128)
    render.PushRenderTarget(base) cam.Start3D() render.PushCustomClipPlane() cam.PushModelMatrix()
    hook.Add("HUDPaint","bad",function()
        render.PushRenderTarget(child) cam.Start2D() render.PushCustomClipPlane() cam.PushModelMatrix()
        mesh.Begin()
        error("stop")
    end)
    hook.Call("HUDPaint")
    eq(#rtStack,1) eq(cameraDepth,1) eq(clipDepth,1) eq(modelDepth,1) eq(currentRT,base)
    eq(depthRange[1],0) eq(depthRange[2],0.1) eq(meshEnds,0,"no fake mesh abort")
    eq(#guard.cleanup_errors,0)
    hook.Add("PostRender","settarget",function()render.SetRenderTarget(child)error("stop")end)
    hook.Call("PostRender") eq(currentRT,base)
    cam.PopModelMatrix() render.PopCustomClipPlane() cam.End3D() render.PopRenderTarget()
    eq(#rtStack,0) eq(cameraDepth,0) eq(clipDepth,0) eq(modelDepth,0)
elseif scenario=="stack_ownership" then
    local base,child,temporary=texture("caller",128,128),texture("cross-hook",64,64),texture("temporary",32,32)
    render.PushRenderTarget(base) cam.Start3D() render.PushCustomClipPlane() cam.PushModelMatrix()
    for id,fn in pairs({rt=render.PopRenderTarget,camera=cam.End3D,clip=render.PopCustomClipPlane,model=cam.PopModelMatrix}) do
        hook.Add("HUDPaint",id,function()fn()end)
    end
    hook.Call("HUDPaint")
    eq(#rtStack,1) eq(currentRT,base) eq(cameraDepth,1) eq(clipDepth,1) eq(modelDepth,1)
    for _,id in ipairs({"rt","camera","clip","model"}) do hook.Remove("HUDPaint",id) end
    cam.PopModelMatrix() render.PopCustomClipPlane() cam.End3D() render.PopRenderTarget()

    hook.Add("HUDPaint","nested-pop",function()render.PopRenderTarget()end)
    hook.Add("PreRender","active-parent",function()
        render.PushRenderTarget(base)
        hook.Call("HUDPaint")
        eq(#rtStack,1,"nested callback preserves its active ancestor") eq(currentRT,base)
        render.PopRenderTarget()
    end)
    hook.Call("PreRender")
    eq(#rtStack,0)
    hook.Remove("PreRender","active-parent") hook.Remove("HUDPaint","nested-pop")

    -- A completed successful Pre callback may intentionally open a scope for Post.
    render.PushRenderTarget(base)
    hook.Add("PreRender","cross-open",function()render.PushRenderTarget(child,0,0,64,64)end)
    hook.Add("PostRender","cross-close",function()render.PopRenderTarget()end)
    hook.Call("PreRender") eq(#rtStack,2) eq(currentRT,child)
    hook.Call("PostRender") eq(#rtStack,1) eq(currentRT,base)

    -- An error after that permitted pop replays only its known recorded RT push.
    hook.Call("PreRender")
    hook.Add("PostRender","cross-close",function()
        render.PopRenderTarget()
        render.PushRenderTarget(temporary)
        error("failure after completed cross-callback pop")
    end)
    hook.Call("PostRender")
    eq(#rtStack,2) eq(currentRT,child) eq(#guard.cleanup_errors,0)
    hook.Add("PostRender","cross-close",function()render.PopRenderTarget()end)
    hook.Call("PostRender") eq(#rtStack,1) eq(currentRT,base)
    render.PopRenderTarget() eq(#rtStack,0)
    hook.Remove("PreRender","cross-open") hook.Remove("PostRender","cross-close")

    -- Do not invent a previous native camera context from implicit defaults.
    hook.Add("PreRender","camera-open",function()cam.Start3D()end)
    hook.Add("PostRender","camera-close",function()cam.End3D()error("after camera pop")end)
    hook.Call("PreRender") eq(cameraDepth,1)
    hook.Call("PostRender") eq(cameraDepth,0)
    eq(#guard.cleanup_errors,1,"unreplayable completed camera pop is explicit")
    assert(guard.cleanup_errors[1].reason:find("cannot be safely replayed",1,true))
elseif scenario=="nested_cleanup" then
    local base,a,b=texture("caller",128,128),texture("parent",64,64),texture("child",32,32)
    render.PushRenderTarget(base)
    hook.Add("PostRender","child",function()render.PushRenderTarget(b)end)
    hook.Add("HUDPaint","parent",function()
        render.PushRenderTarget(a)
        hook.Call("PostRender")
        error("parent fails after successful child push")
    end)
    hook.Call("HUDPaint")
    eq(#rtStack,1,"successful child's extra scope unwinds before its parent's")
    eq(currentRT,base) eq(#guard.cleanup_errors,0)
    render.PopRenderTarget()

    render.PushRenderTarget(base)
    hook.Add("PostRender","child",function()render.SetRenderTarget(b)end)
    hook.Add("HUDPaint","parent",function()hook.Call("PostRender")error("parent fails after child direct target change")end)
    hook.Call("HUDPaint")
    eq(#rtStack,1) eq(currentRT,base,"nested direct target change restores parent's entry target")
    eq(#guard.cleanup_errors,0)
    render.PopRenderTarget()

    -- A successful child's permitted cross-callback pop is restored once.
    hook.Add("PreRender","open",function()render.PushRenderTarget(a)end)
    hook.Call("PreRender")
    hook.Add("PostRender","child",function()render.PopRenderTarget()end)
    hook.Add("HUDPaint","parent",function()hook.Call("PostRender")error("parent fails after child pop")end)
    hook.Call("HUDPaint")
    eq(#rtStack,1) eq(currentRT,a) eq(#guard.cleanup_errors,0)
    render.PopRenderTarget()

    -- A failed child's own restoration must not be propagated and replayed again.
    hook.Call("PreRender")
    hook.Add("PostRender","child",function()render.PopRenderTarget()error("child fails after pop")end)
    hook.Add("HUDPaint","parent",function()hook.Call("PostRender")error("parent fails after cleaned child")end)
    hook.Call("HUDPaint")
    eq(#rtStack,1) eq(currentRT,a) eq(#guard.cleanup_errors,0)
    render.PopRenderTarget() eq(#rtStack,0)
elseif scenario=="leaks" then
    -- The stock toolgun screen pushes an RT and a 2D camera, then calls the tool's DrawToolScreen
    -- unprotected; a failing tool leaves both open in every frame.
    local screen=texture("toolgun_screen",256,256)
    local function toolScreen() render.PushRenderTarget(screen) cam.Start2D() error("DrawToolScreen failed") end
    for _=1,40 do frameCount=frameCount+1 assert(not pcall(toolScreen)) end
    render.PushRenderTarget(screen) cam.Start2D() cam.End2D() render.PopRenderTarget()
    eq(#guard.blocked,0,"leaked unowned scopes never reach the tracked stack limit")
    -- Forty broken ENT:Draw calls inside one frame leave unowned scopes that do not count either.
    for _=1,40 do assert(not pcall(function()cam.Start3D2D() error("ENT:Draw failed")end)) end
    cam.Start3D2D() cam.End3D2D()
    eq(#guard.blocked,0)
    -- A leaked unowned scope from an earlier frame is forgotten, so it cannot satisfy a later pop.
    assert(not pcall(toolScreen)) frameCount=frameCount+1
    denied(function()render.PopRenderTarget()end)
    -- A protected callback's own scopes stay bounded and are unwound when it fails.
    local depth=#rtStack
    hook.Add("HUDPaint","runaway",function() for _=1,40 do render.PushRenderTarget(screen) end end)
    hook.Call("HUDPaint")
    eq(#rtStack,depth,"the failed callback's own pushes were unwound")
    eq(guard.blocked[#guard.blocked].reason,"tracked stack limit")
    hook.Remove("HUDPaint","runaway")
    -- Thirty-two of the callback's own scopes are allowed, as before.
    hook.Add("HUDPaint","deep",function() for _=1,32 do render.PushRenderTarget(screen) end for _=1,32 do render.PopRenderTarget() end end)
    local blocked=#guard.blocked
    hook.Call("HUDPaint") eq(#guard.blocked,blocked) eq(#rtStack,depth)
elseif scenario=="prerender_boundary" then
    -- Without FrameNumber, a top-level PreRender is the frame boundary.
    local screen=texture("toolgun_screen",256,256)
    local function toolScreen() render.PushRenderTarget(screen) cam.Start2D() error("DrawToolScreen failed") end
    assert(not pcall(toolScreen))
    render.PushRenderTarget(screen) render.PopRenderTarget()
    hook.Add("PreRender","open",function()render.PushRenderTarget(screen)end)
    hook.Add("PostRender","close",function()render.PopRenderTarget()end)
    hook.Call("PreRender")
    hook.Call("PostRender")
    eq(#guard.blocked,0,"a Pre/Post scope survives the boundary it was opened after")
    denied(function()cam.End2D()end)
    denied(function()render.PopRenderTarget()end)
elseif scenario=="hot_paths" then
    -- hook.Call reads the switch only for the events it protects.
    local reads=getBoolCalls
    for _=1,50 do hook.Call("Think") hook.Call("Tick") end
    eq(getBoolCalls,reads,"unprotected events never read the guard switch")
    -- A protected callback that never touches render targets queries no entry target.
    hook.Add("HUDPaint","plain",function()end)
    local queries=targetQueries
    for _=1,50 do hook.Call("HUDPaint") end
    eq(targetQueries,queries,"entry render target recorded lazily")
    -- Shader names are cached per material object.
    local mat=Material("normal") local before=shaderQueries
    for _=1,50 do render.SetMaterial(mat) end
    eq(shaderQueries,before,"shader name cached when the material was loaded")
    local fresh=material("UnlitGeneric")
    for _=1,50 do render.SetMaterial(fresh) end
    eq(shaderQueries,before+1,"one query for a new material object")
    -- A target change still records and restores the entry target on failure.
    local base,other=texture("base",64,64),texture("other",64,64)
    render.SetRenderTarget(base)
    hook.Add("PostRender","switch",function()render.SetRenderTarget(other)error("switch failed")end)
    hook.Call("PostRender") eq(currentRT,base) eq(targetQueries,queries+1)
elseif scenario=="callbacks" then
    local calls=0
    timer.Create("bad",1,0,function()calls=calls+1 error("bad")end)
    for _=1,5 do timers.bad() end eq(calls,3,"timer quarantine after three consecutive failures")
    timer.Simple(0,function(a)eq(a,8)return "ok",nil,3 end)
    local v=pack(timers.simple(8)) eq(v.n,3)eq(v[3],3)
    cvars.AddChangeCallback("unrelated",function(name,old,new)eq(name,"unrelated")eq(old,"0")eq(new,"1")return 9 end,"identifier")
    eq(changes.unrelated.id,"identifier") eq(changes.unrelated.fn("unrelated","0","1"),9)
    local cvarCalls=0
    cvars.AddChangeCallback("flaky",function()cvarCalls=cvarCalls+1 error("cvar")end)
    changes.flaky.fn() changes.flaky.fn() eq(cvarCalls,2,"two failures do not quarantine")
    cv.nativeloader_guard.value="0"
    assert(not pcall(timers.bad)) eq(calls,4,"off bypasses quarantine")
elseif scenario=="off" then
    GetRenderTargetEx("_rt_shadowdepthtexture_0",-99,-99,999,0,0,0,9999)
    CreateMaterial("depth","DepthWrite",{}) render.GetResolvedFullFrameDepth() render.SetRenderTargetEx(2)
    cv.mat_dxlevel:SetString("95") eq(cv.mat_dxlevel.value,"95")
    DrawBloom() halo.Render() eq(postCalls,2)
    eq(#guard.blocked,0) eq(#guard.errors,0)
else error("unknown scenario "..tostring(scenario)) end
print("PASS "..scenario)
