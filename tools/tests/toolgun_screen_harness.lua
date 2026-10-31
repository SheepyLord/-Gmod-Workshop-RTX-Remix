local source, scenario = ...
local name = scenario
local hooks, commands, callbacks = {}, {}, {}
local active, frame, nowWidth, nowHeight = true, 1, 1280, 720
local calls, polys, warnings = {}, {}, 0
local function record(name) calls[name] = (calls[name] or 0) + 1 end
local vector = {}; vector.__index = vector
function Vector(x,y,z) return setmetatable({x=x,y=y,z=z},vector) end
vector.__add = function(a,b) return Vector(a.x+b.x,a.y+b.y,a.z+b.z) end
vector.__sub = function(a,b) return Vector(a.x-b.x,a.y-b.y,a.z-b.z) end
vector.__mul = function(a,b) return Vector(a.x*b,a.y*b,a.z*b) end
vector.__div = function(a,b) return Vector(a.x/b,a.y/b,a.z/b) end
function vector:Dot(b) return self.x*b.x+self.y*b.y+self.z*b.z end
local matrix = {}; matrix.__index = matrix
function Matrix(x,y,z) return setmetatable({offset=Vector(x or 0,y or 0,z or 0)},matrix) end
matrix.__mul = function(a,b)
    if b.offset then return Matrix(a.offset.x+b.offset.x,a.offset.y+b.offset.y,a.offset.z+b.offset.z) end
    return a.offset+b
end
-- Source's axes for angles (0, 0, 0): forward +x, right -y, up +z.
local angles = {Forward=function() return Vector(1,0,0) end,Right=function() return Vector(0,-1,0) end,
    Up=function() return Vector(0,0,1) end}
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
VIEW_MAIN=0
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
local origin = scenario=="behind" and Vector(100,0,0) or Vector(0,0,0)
-- Only what a 2D HUD draw needs: no render targets, cameras, overrides or depth (Remix takes any
-- perspective draw into its scene; a call to one of those would fail here as a nil function).
render={
    GetRenderTarget=function() return scenario=="subview" and texture or nil end,
    GetViewSetup=function() return {viewid=0,origin=origin,angles=angles,aspect=16/9,fovviewmodel=90} end,
}
surface={
    SetMaterial=function() record("material") end,
    SetDrawColor=function() end,
    DrawPoly=function(vertices)
        if scenario=="poly_failure" then error("injected polygon failure") end
        assert(#vertices==3,"Triangles only")
        for _, v in ipairs(vertices) do assert(v.x and v.y and v.u and v.v,"Vertex without position or UV") end
        polys[#polys+1]=vertices
    end,
}
function ErrorNoHalt() warnings=warnings+1 end
dofile(source)
local function draw()
    hooks.PostDrawViewModel(model,player,weapon)
    hooks.HUDPaint()
end
local function expected(width, height)
    -- The skinned vertex is (14.5, 25.25, 36) (0.25 of bone 0, 0.75 of bone 1); 90 degrees: scale 1.
    local depth, aspect = 14.5, width / height
    return (1 + (-25.25) / depth) * width * 0.5, (1 - 36 * aspect / depth) * height * 0.5
end
draw()
assert(originalWrites==0,"Original material was modified")
if scenario=="no_api" or scenario=="third_person" or scenario=="other_weapon" or scenario=="unsupported" or scenario=="subview" then
    assert(#polys==0 and warnings==0,"Unsupported view was changed")
elseif scenario=="behind" then
    assert(#polys==0 and warnings==0,"A screen behind the camera was drawn")
elseif scenario=="poly_failure" then
    assert(warnings==1,"Failure was not reported once")
    draw() assert(warnings==1 and #polys==0,"Failure spammed every frame")
    active=false callbacks.nativeloader_toolgun_screen() active=true callbacks.nativeloader_toolgun_screen()
    scenario="normal" draw()
    assert(#polys==128,"Re-enabling did not draw again")
else
    assert(#polys==128,"Screen was not drawn once as 2 x 64 projected triangles")
    local x, y = expected(1280, 720)
    assert(math.abs(polys[1][1].x-x)<0.001 and math.abs(polys[1][1].y-y)<0.001,"Projection incorrect")
    assert(math.abs(polys[1][1].u-0.2)<0.001 and math.abs(polys[1][1].v-0.3)<0.001,"UV not carried")
    frame=frame+1 hooks.HUDPaint() assert(#polys==128,"Stale frame was painted")
    nowWidth,nowHeight=1920,1080 draw()
    x, y = expected(1920, 1080)
    assert(#polys==256 and math.abs(polys[129][1].x-x)<0.001 and math.abs(polys[129][1].y-y)<0.001,"Output resize was not respected")
end
print("PASS "..name)
