-- Runs the actual material builders and DrawCarrier, with engine/native behavior instrumented.
local remix=arg[2]=='remix'
local NOW,FRAME=0,1
function SysTime()return NOW end
function FrameNumber()return FRAME end
function Vector(...)return {...}end
function IsValid(v)return v~=nil and v~=false end
function LocalPlayer()return nil end
CreateClientConVar=function()return {GetBool=function()return true end}end
cvars={AddChangeCallback=function()end}
file={Exists=function()return false end}
util={TableToJSON=function(v)return v end}
local bitlib=require('bit');bit={band=bitlib.band}
local initialized,checks,stats=false,0,0
local created,bindings,draws={}, {}, {}
local Mat={};Mat.__index=Mat
function Mat:GetName()return self.name end
function Mat:IsError()return false end
function Mat:GetTexture()return self.texture end
function Mat:SetTexture(_,texture)self.texture=texture end
local function texture(name)return {GetName=function()return name end,IsError=function()return false end}end
local sources={}
for i=1,2 do sources['fixture/'..i]=setmetatable({name='fixture/'..i,texture=texture('fixture/texture'..i)},Mat)end
if not remix then sources['fixture/2'].texture=nil end
function Material(path)return sources[path]end
function CreateMaterial(name,shader,params)
 assert(not remix or shader~='DepthWrite','unknown DepthWrite shader was requested on fixed-function Remix')
 if created[name]then return created[name]end
 local copy={};for key,value in pairs(params)do copy[key]=value end
 local material=setmetatable({name=name,shader=shader,params=copy},Mat);created[name]=material;return material
end
local native={SetNativeVertexCache=function()end,SetupSourceLighting=function()return true end}
function native.CheckRenderer()checks=checks+1;initialized=true;return true end
function native.RenderStats()stats=stats+1;return {fixedFunctionRemix=initialized and remix}end
function native.SetInstanceMaterials(_,names)bindings[#bindings+1]=names;return true end
function native.DrawInstance(_,translucent,depth)
 assert(not remix or not depth,'Source depth pass submitted to Remix')
 draws[#draws+1]={depth=depth,translucent=translucent}
end
local modulation,blend={.2,.3,.4},.8
render={SuppressEngineLighting=function()end,SetLightingOrigin=function()end,
 GetColorModulation=function()return unpack(modulation)end,GetBlend=function()return blend end,
 SetColorModulation=function(r,g,b)modulation={r,g,b}end,SetBlend=function(v)blend=v end,
 ResetModelLighting=function()end,SetLocalModelLights=function()end,RenderFlashlights=function(callback)callback()end}
local info={materials={{path='fixture/1',twoSided=false},{path='fixture/2',twoSided=true,alphaTexture=true}}}
mmdhl={native=native,assets={asset=info},sourceTextureVersion=10,depthMaterials={asset={'stale error material'}},
 L=function(key)return key end,Decode=function(v)return v end,GetAsset=function()return 'asset'end,
 GetInstance=function()return 1 end,IsMMD=function()return true end,PresentationSuppressed=function()return false end}
local entity={MMDHLClientInstance=1,MMDPresentationFrame=1}
function entity:GetColor()return {r=255,g=255,b=255,a=255}end
function entity:GetMaterial()return ''end
function entity:GetSubMaterial()return ''end
function entity:EntIndex()return 42 end
assert(loadfile(arg[1]))()
assert(mmdhl.sourceTextureVersion==11 and not mmdhl.depthMaterials.asset,'stale material cache was not invalidated')
mmdhl.LightingOrigin=function()return Vector(0,0,0)end
mmdhl.DrawCarrier(entity,false,0)
assert(checks==1 and stats==1,'renderer must initialize before its cached backend query')
assert(#draws==2,'normal color and flashlight rendering continues')
assert(modulation[1]==.2 and modulation[2]==.3 and modulation[3]==.4 and blend==.8,'render state restored')
if remix then
 assert(next(created)==nil,'Remix created unused shader clones')
 assert(entity.MMDNamesSent=='asset' and #bindings==1,'valid color registration completed')
 for i=1,2 do assert(bindings[1].depth[i]=='fixture/'..i,'unused depth names remain valid public materials')end
 local before=#draws
 mmdhl.DrawCarrier(entity,false,1073741824)
 mmdhl.DrawCarrier(entity,false,536870912)
 assert(#draws==before,'both Source depth-view flags are skipped on Remix')
else
 assert(not entity.MMDNamesSent and next(created)==nil,'pending texture did not create an immutable bad clone')
 local before=#draws
 mmdhl.DrawCarrier(entity,false,1073741824)
 assert(#draws==before,'Source depth waits for its real texture')
 NOW=.3;sources['fixture/2'].texture=texture('fixture/texture2')
 mmdhl.DrawCarrier(entity,false,1073741824)
 assert(entity.MMDNamesSent=='asset' and #bindings==2,'Source depth recovers after the texture arrives')
 for i=1,2 do
  local name='mmdhl_depth_v11_asset_'..i
  local material=assert(created[name])
  assert(material.shader=='DepthWrite' and material.params['$basetexture']=='fixture/texture'..i)
  assert(material.params['$alphatest']=='1' and material.params['$alphatestreference']=='.5')
  assert(material.params['$nocull']==(i==2 and '1' or '0'),'cutout cull mode preserved')
  assert(material.texture==sources['fixture/'..i].texture,'depth binds actual uploaded texture')
 end
 mmdhl.DrawCarrier(entity,false,536870912)
 assert(draws[#draws].depth,'Source SSAO depth view still draws')
end
local registered=#bindings
for i=1,100 do FRAME=FRAME+1;mmdhl.DrawCarrier(entity,false,0)end
assert(#bindings==registered and checks==1 and stats==1,'ready mappings and backend are cached')
print('PASS: '..arg[2]..' depth shader routing, initialization, material readiness and draw state')
