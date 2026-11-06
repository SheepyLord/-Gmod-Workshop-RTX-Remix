local source, scenario = ...
local function eq(a,b) assert(a==b,tostring(a).." ~= "..tostring(b)) end
CLIENT, NativeLoaderRenderGuard = true, {}
local now, writes, queries, loads = 0, {}, 0, 0
function RealTime() return now end
function include() return {L=function(text)return text end} end
local hooks, metas = {}, {CLuaEmitter={},CLuaParticle={}}
hook={Add=function(_,id,fn)hooks[id]=fn end}
function FindMetaTable(name)return metas[name]end
local originalAdd=function(self,name,...)self.args={name,...}return self.result end
metas.CLuaEmitter.Add=originalAdd
metas.CLuaParticle.SetMaterial=function(self,name)self.material=name return 'set' end
render={SetMaterial=function(mat,...)return mat,... end,DrawSprite=function(...)return 'draw',... end}
util={DecalEx=function(...)return 'decal',... end,Decal=function(...)return 'named',... end,
 DecalMaterial=function()error('observation must not choose another random decal variant')end}
local data={
 decal={shader='LightmappedGeneric',['$decal']=1,hashes={'0xA'}},
 particle={shader='UnlitGeneric',hashes={'0xB'}},
 sprite={shader='Sprite',hashes={'0xC'}},
 mesh={shader='UnlitGeneric',['$vertexcolor']=1,['$vertexalpha']=1,['$translucent']=1,hashes={'0xD'}},
 world={shader='LightmappedGeneric',hashes={'0xE'}},
 cold={shader='Sprite',hashes={}},
 white={shader='Sprite',texture='vgui/white',hashes={'0xF'}},
 invalid={shader='Sprite',hashes={'0x0','0x','0xz','0x12345678901234567','B','0x12\0'}},
}
local cached={'decal','sprite','mesh','world','cold','white','invalid'}
function Material(name)
 loads=loads+1;name=name:gsub('^!','');assert(name~='cold','cold material was loaded')
 local d=assert(data[name],name)
 return {GetName=function()return name end,IsError=function()return false end,
 GetShader=function()return d.shader end,GetInt=function(_,key)return d[key] or 0 end,
 GetTexture=function()return {IsError=function()return false end,GetName=function()return d.texture or name end}end}
end
RemixMaterial={GetCachedMaterials=function()return cached end,GetAllTextureHashes=function(name)queries=queries+1 return data[name].hashes end}
local failures, attempts=0,0
RemixConfig={SetConfigVariable=function(key,value)
 assert(key:match('^rtx%.gmod%.%a+TexturesForSession$'),'persistent option write')
 attempts=attempts+1
 if failures>0 then failures=failures-1 return false end
 writes[key]=value return true
end}
if scenario=='off' then NativeLoaderRenderGuard=nil end
if scenario=='server' then CLIENT=false end
if scenario=='no_api' then RemixConfig=nil RemixMaterial=nil end
assert(loadfile(source))()
local sync=hooks.nativeloader_effect_categories
if scenario=='off' or scenario=='server' then eq(sync,nil)eq(metas.CLuaEmitter.Add,originalAdd)print('PASS '..scenario)return end
local function tick(dt,count)
 now=now+dt
 for _=1,count or 1 do local before=queries sync()assert(queries-before<=12,'unbounded lookups') end
end
local opt=function(kind)return writes['rtx.gmod.'..kind..'TexturesForSession']end
if scenario=='no_api' then tick(1,10)eq(attempts,0)print('PASS '..scenario)return end
local emitter={result={}};eq(metas.CLuaEmitter.Add(emitter,'particle',7),emitter.result)eq(emitter.args[2],7)
tick(0,20)
eq(opt('particle'),'0x000000000000000b, 0x000000000000000c')
eq(opt('decal'),'0x000000000000000a')
eq(opt('legacyEffect'),'0x000000000000000d')
if scenario=='changes' then
 data.particle.hashes={'0x1234'};data.decal.hashes={};tick(3,30)
 eq(opt('particle'),'0x000000000000000c, 0x0000000000001234')eq(opt('decal'),'')
elseif scenario=='wrappers' then
 local mat=Material('mesh');eq(render.SetMaterial(mat,7),mat);eq(render.DrawSprite(9),'draw')
 eq(util.DecalEx(Material('decal'),3),'decal');eq(util.Decal('Blood',3),'named')
 eq(metas.CLuaParticle.SetMaterial({},'particle'),'set')
 tick(3,30);assert(opt('particle'):find('000000000000000d',1,true))
elseif scenario=='retry' then
 failures=20;data.particle.hashes={'0x1234'};local before=attempts;tick(3,20)
 local failed=attempts;tick(0.01,100);eq(attempts,failed);assert(failed>before)
 failures=0;tick(70,30);assert(opt('particle'):find('0000000000001234',1,true))
elseif scenario=='bounded' then
 for i=1,9000 do
  local name='particle'..i;data[name]={shader='Sprite',hashes={'0xB'}}
  metas.CLuaEmitter.Add(emitter,name,i)
 end
 eq(NativeLoaderEffectCategories.Status(),4096)
 tick(1,10);eq(emitter.args[2],9000)
elseif scenario=='hash_budget' then
 data.particle.hashes={}
 for i=1,10000 do data.particle.hashes[i]=string.format('0x%x',i) end
 tick(3,30)
 local _,count=opt('particle'):gsub('0x','')
 eq(count,64)
 assert(not opt('particle'):find('0000000000000041',1,true),'material hash cap')
elseif scenario=='late_hash' then
 data.cold.hashes={'0x123'};Material=function(name)
  name=name:gsub('^!','');return {IsError=function()return false end,GetShader=function()return 'Sprite' end,
  GetInt=function()return 0 end,GetTexture=function()return {IsError=function()return false end,GetName=function()return name end}end}
 end
 tick(3,30);assert(opt('particle'):find('0000000000000123',1,true))
end
print('PASS '..scenario)
