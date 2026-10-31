local source, scenario = ...
local hooks, commands, callbacks = {}, {}, {}
local active, frame, nowWidth, nowHeight = true, 1, 1280, 720
local rt, calls, vertices, warnings = nil, {}, {}, 0
local targetFailure = scenario == "target_failure"
local function record(name) calls[name] = (calls[name] or 0) + 1 end
local vector = {}; vector.__index = vector
function Vector(x,y,z) return setmetatable({x=x,y=y,z=z},vector) end
vector.__add = function(a,b) return Vector(a.x+b.x,a.y+b.y,a.z+b.z) end
vector.__mul = function(a,b) return Vector(a.x*b,a.y*b,a.z*b) end
vector.__div = function(a,b) return Vector(a.x/b,a.y/b,a.z/b) end
local matrix = {}; matrix.__index = matrix
function Matrix(x,y,z) return setmetatable({offset=Vector(x or 0,y or 0,z or 0)},matrix) end
matrix.__mul = function(a,b)
    if b.offset then return Matrix(a.offset.x+b.offset.x,a.offset.y+b.offset.y,a.offset.z+b.offset.z) end
    return a.offset+b
end
local texture = {GetName=function() return "DTScreen_Screen512" end,IsError=function() return false end}
local originalWrites = 0
local original = {GetTexture=function() return texture end,SetTexture=function() originalWrites=originalWrites+1 end}
function Material() return original end
function CreateMaterial(name) return {SetTexture=function() record("private_texture") end} end
function CreateClientConVar() return {GetBool=function() return active end} end
cvars={AddChangeCallback=function(name,fn) callbacks[name]=fn end}
concommand={Add=function(name,fn) commands[name]=fn end}
hook={Add=function(event,name,fn) hooks[event]=fn end}
istable=function(value) return type(value)=="table" end
IsValid=function(value) return value~=nil and value.valid==true end
FrameNumber=function() return frame end
ScrW=function() return nowWidth end ScrH=function() return nowHeight end
VIEW_MAIN, RT_SIZE_NO_CHANGE, MATERIAL_RT_DEPTH_SEPARATE, IMAGE_FORMAT_BGRA8888, MATERIAL_TRIANGLES=0,1,2,12,4
RemixConfig=scenario~="no_api" and {} or nil
local player={valid=true}
LocalPlayer=function() return player end
function player:Alive() return true end
function player:ShouldDrawLocalPlayer() return scenario=="third_person" end
function player:GetHands() return nil end
local weapon={valid=true,GetClass=function() return scenario=="other_weapon" and "weapon_pistol" or "gmod_tool" end}
local model={valid=true}
function model:GetModel() return "models/weapons/c_toolgun.mdl" end
function model:GetSkin() return 0 end
function model:GetNumBodyGroups() return 1 end
function model:GetBodygroup() return 0 end
function model:GetColor() return {a=255} end
function model:GetBoneMatrix(bone) return bone==0 and Matrix(10,20,30) or Matrix(20,30,40) end
function model:DrawModel()
    record("depth_model")
    if scenario=="depth_failure" then error("injected model draw failure") end
end
local triangles={}
for i=1,6 do triangles[i]={pos=Vector(1,2,3),u=0.2,v=0.3,weights={{bone=0,weight=0.25},{bone=1,weight=0.75}}} end
util={
    GetModelMeshes=function()
        record("mesh_read")
        return {{material=scenario=="unsupported" and "models/body" or "models/weapons/v_toolgun/screen",triangles=triangles}},
               {[0]={matrix=Matrix(-1,-2,-3)},[1]={matrix=Matrix(-5,-5,-5)}}
    end,
    TableToJSON=function() return "{}" end,
}
local colorOverride,alphaOverride,depthOverride,depthNear,depthFar=false,false,false,0,1
render={
    GetRenderTarget=function() return scenario=="subview" and texture or rt end,
    GetViewSetup=function() return {viewid=0,origin=Vector(0,0,0),angles={},aspect=16/9,fovviewmodel=77,znearviewmodel=1,zfarviewmodel=1000} end,
    PushRenderTarget=function(target) assert(target,"Never push the main framebuffer") rt=target record("push_rt") end,
    PopRenderTarget=function() rt=nil record("pop_rt") end,
    Clear=function() assert(rt,"Never clear the main framebuffer") record("clear") end,
    OverrideColorWriteEnable=function(override) colorOverride=override end,
    OverrideAlphaWriteEnable=function(override) alphaOverride=override end,
    OverrideDepthEnable=function(override) depthOverride=override end,
    DepthRange=function(near,far) depthNear,depthFar=near,far end,
    SetMaterial=function() end,
}
cam={
    Start=function(data) assert(data.fov==77 and data.znear==1 and data.zfar==1000) record("camera") end,
    End3D=function() record("end_camera") end,
    PushModelMatrix=function() record("push_model") end,
    PopModelMatrix=function() record("pop_model") end,
}
mesh={
    Begin=function() record("mesh_begin") end,End=function() record("mesh_end") end,
    Position=function(position)
        if scenario=="mesh_failure" then error("injected vertex failure") end
        vertices[#vertices+1]=position
    end,
    TexCoord=function() end,Color=function() end,AdvanceVertex=function() end,
}
surface={SetMaterial=function() end,SetDrawColor=function() end,DrawTexturedRect=function() record("composite") end}
function GetRenderTargetEx(name,w,h,size,depth,flags)
    assert(w==nowWidth and h==nowHeight and depth==MATERIAL_RT_DEPTH_SEPARATE and flags==12)
    record("allocate")
    return not targetFailure and texture or nil
end
function ErrorNoHalt() warnings=warnings+1 end
dofile(source)
local function draw()
    hooks.PostDrawViewModel(model,player,weapon)
    hooks.HUDPaint()
end
draw()
assert(originalWrites==0,"Original material was modified")
assert(not rt and not colorOverride and not alphaOverride and not depthOverride and depthNear==0 and depthFar==1,"Render state leaked")
if scenario=="no_api" or scenario=="third_person" or scenario=="other_weapon" or scenario=="unsupported" or scenario=="subview" then
    assert(not calls.composite and not calls.clear and warnings==0,"Unsupported view was changed")
elseif scenario=="target_failure" then
    assert(not calls.clear and not calls.push_rt and warnings==1,"Allocation failure touched the framebuffer")
    targetFailure=false active=false callbacks.nativeloader_toolgun_screen() active=true callbacks.nativeloader_toolgun_screen()
    draw()
    assert(calls.allocate==2 and calls.composite==1,"Failed target was not retried")
elseif scenario=="depth_failure" or scenario=="mesh_failure" then
    assert(warnings==1 and calls.push_rt==calls.pop_rt and calls.camera==calls.end_camera,"Failure did not unwind")
    assert((calls.push_model or 0)==(calls.pop_model or 0),"Model matrix leaked")
    if scenario=="mesh_failure" then assert(calls.mesh_begin==calls.mesh_end,"Mesh left open") end
    draw() assert(warnings==1,"Failure spammed every frame")
else
    assert(calls.composite==1 and calls.depth_model==1 and #vertices==6,"Screen was not drawn once")
    assert(math.abs(vertices[1].x-14.5)<0.001 and math.abs(vertices[1].y-25.25)<0.001 and vertices[1].z==36,"Pose-to-bone skinning incorrect")
    frame=frame+1 hooks.HUDPaint() assert(calls.composite==1,"Stale frame was painted")
    nowWidth,nowHeight=1920,1080 draw()
    assert(calls.allocate==2 and calls.composite==2,"Output resize was not respected")
end
print("PASS "..scenario)
