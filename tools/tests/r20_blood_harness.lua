-- Execute the real R20-C controllers against deterministic, small GMod API doubles.
local root, scenario = arg[1], arg[2]
local function source(path) return root .. "/companion/nativeloader/lua/" .. path end
local clock, calls, cvs, callbacks, hooks, commands = 0, {}, {}, {}, {}, {}
CLIENT, SERVER = true, false
function CurTime() return clock end
math.Clamp = function(v, a, b) return math.max(a, math.min(v, b)) end
math.Rand = function(a, b) return (a + b) / 2 end
local V = {} V.__index = V
function Vector(x, y, z) return setmetatable({x=x or 0,y=y or 0,z=z or 0}, V) end
function V.__add(a,b) return Vector(a.x+b.x,a.y+b.y,a.z+b.z) end
function V.__sub(a,b) return Vector(a.x-b.x,a.y-b.y,a.z-b.z) end
function V.__mul(a,b) return Vector(a.x*b,a.y*b,a.z*b) end
function V:LengthSqr() return self.x^2+self.y^2+self.z^2 end
function V:Distance(b) return math.sqrt((self-b):LengthSqr()) end
function V:GetNormalized() local n=math.sqrt(self:LengthSqr()) return n>0 and self*(1/n) or Vector() end
function V:Cross(b) return Vector(self.y*b.z-self.z*b.y,self.z*b.x-self.x*b.z,self.x*b.y-self.y*b.x) end
function VectorRand() return Vector(0,.2,.1) end
function EyePos() return Vector(-100,0,0) end
function Color(r,g,b,a) return {r=r,g=g,b=b,a=a or 255} end
function IsColor(c) return type(c)=='table' and c.r ~= nil end
function HSVToColor(h,s,v) return Color(h % 255, s*255, v*255) end
color_white = Color(255,255,255)
isfunction = function(v) return type(v)=='function' end
istable = function(v) return type(v)=='table' end
function IsValid(v) return v ~= nil and v ~= false end
function CreateClientConVar(name, default)
    if cvs[name] then return cvs[name] end
    local cv = {value=tostring(default), default=tostring(default)}
    function cv:GetString() return self.value end
    function cv:GetFloat() return tonumber(self.value) or 0 end
    function cv:GetInt() return math.floor(self:GetFloat()) end
    function cv:GetBool() return self:GetFloat() ~= 0 end
    function cv:GetName() return name end
    function cv:GetDefault() return self.default end
    cvs[name]=cv return cv
end
GetConVar = function(name) return cvs[name] end
cvars = {AddChangeCallback=function(name,fn,id) callbacks[name]=callbacks[name] or {} callbacks[name][id]=fn end}
function RunConsoleCommand(name, value)
    if cvs[name] then
        local old=cvs[name].value cvs[name].value=tostring(value)
        for _,fn in pairs(callbacks[name] or {}) do fn(name,old,tostring(value)) end
    end
end
hook = {
    Add=function(event,id,fn) hooks[event]=hooks[event] or {} hooks[event][id]=fn end,
    Remove=function(event,id) if hooks[event] then hooks[event][id]=nil end end,
    Run=function(event,...) for _,fn in pairs(hooks[event] or {}) do fn(...) end end,
}
concommand = {Add=function(name,fn) commands[name]=fn end}
local mats = {}
function Material(name)
    if mats[name] then return mats[name] end
    local mat={name=name}
    function mat:GetName() return self.name end
    function mat:IsError() return false end
    function mat:GetShader()
        if self.shader then return self.shader end
        local model = self.name:find('_model',1,true) or (not self.name:find('_subrect',1,true) and
            (self.name:find('decals/flesh/',1,true) or self.name:find('decals/alienflesh/',1,true) or self.name:find('decals/antlion/',1,true)))
        return model and 'VertexLitGeneric' or 'LightmappedGeneric'
    end
    function mat:GetTexture(key)
        local value=self[key] or ('original:'..self.name)
        if type(value)=='string' then return {GetName=function() return value end} end
        return value
    end
    function mat:GetVector(key) return self[key] or Vector(.7,.8,.9) end
    function mat:SetTexture(key,value)
        if calls.watch_material==self.name then
            calls.material_writes=(calls.material_writes or 0)+1
            calls.texture_trace=calls.texture_trace or {}
            calls.texture_trace[#calls.texture_trace+1]=type(value)=='string' and value or value:GetName()
        end
        self[key]=value
    end
    function mat:SetVector(key,value) self[key]=value end
    mats[name]=mat return mat
end
if scenario=='stock_materials' then
    -- GMod may hand Lua distinct userdata wrappers for one underlying material pointer.
    -- Material mutations still affect the same backing data; wrapper identity is not a key.
    local original_material=Material
    Material=function(name)
        local shared=original_material(name)
        return setmetatable({}, {__index=shared,__newindex=shared})
    end
end
CreateMaterial = function(name,shader,fields) local m=Material(name) for k,v in pairs(fields) do m[k]=v end return m end
local emitter_meta = {Add=function(self,mat,pos,...) return {mat=mat,pos=pos,extra={...},
    SetMaterial=function(s,m) s.mat=m s.material_changed=true end} end}
function FindMetaTable(name) if name=='CLuaEmitter' then return emitter_meta end end
util = {
    DecalEx=function(...) calls.decals=calls.decals or {} table.insert(calls.decals,{...}) end,
    Effect=function(...) calls.effects=calls.effects or {} table.insert(calls.effects,{...}) end,
    TraceLine=function(t) return {Hit=true,Entity={},HitPos=t.start,HitNormal=Vector(0,0,1)} end,
}
local added = {}
function ParticleEmitter()
    if calls.fail_emitter then return end
    return {
        Add=function(self,mat,pos)
            local p={material=mat,position=pos,props={}}
            setmetatable(p,{__index=function(_,key) return function(s,...) s.props[key]={...} end end})
            added[#added+1]=p return p
        end,
        Finish=function() end,
    }
end
local registered, registrations = nil, {}
effects = {Register=function(t,name) registrations[name]=t if name=='BloodImpact' then registered=t end end,
    Create=function() return nil end}
bit = require('bit')
game = {GetWorld=function() return false end}
file = {Exists=function() return false end}
include = function(path)
    if path=='nativeloader/i18n.lua' then return {L=function(s) return s end,N=function(s) return s end,PreparePanel=function() end} end
    if path=='nlblood/shapes.lua' then return dofile(root..'/packages/blood-overhaul-rtx/nlblood/lua/nlblood/shapes.lua') end
    if path=='nlblood/schemes.lua' then return dofile(root..'/packages/blood-overhaul-rtx/nlblood/lua/nlblood/schemes.lua') end
    return dofile(source(path))
end
timer = {Simple=function(_,fn) end}
spawnmenu = {AddToolMenuOption=function(...) calls.panels=calls.panels or {} table.insert(calls.panels,{...}) end,
    AddToolTab=function() end,AddToolCategory=function() end}

if scenario=='server_delivery' then
    SERVER,CLIENT=true,false
    local sent={}
    file.Exists=function() return true end
    AddCSLuaFile=function(path) sent[path or '<self>']=true end
    dofile(source('autorun/!nativeloader_blood.lua'))
    assert(sent['dynamic_toolgun_screen/nl_package.lua'] and sent['autorun/client/nativeloader_bundled_panels.lua'])
    assert(sent['nlblood/shapes.lua'] and sent['nativeloader/blood_impacts.lua'])
elseif scenario=='dts_bootstrap' then
    local count=0
    include=function(path) assert(path=='dynamic_toolgun_screen/nl_original_init.lua') count=count+1 DTScreen={Loaded=true} end
    dofile(source('nativeloader/dts_bootstrap.lua')) dofile(source('nativeloader/dts_bootstrap.lua'))
    assert(count==1)
    DTScreen={Loaded=true,Version='standalone'}
    dofile(source('nativeloader/dts_bootstrap.lua')) assert(count==1 and DTScreen.Version=='standalone')
    SERVER,CLIENT=true,false
    AddCSLuaFile=function() end
    dofile(source('nativeloader/dts_bootstrap.lua')) dofile(source('nativeloader/dts_bootstrap.lua'))
    assert(count==2)
elseif scenario=='budget' then
    local Budget=include('nativeloader/blood_budget.lua')
    local b=Budget.New(3,2)
    assert(b:Take(0,2) and b:Take(.1,2) and not b:Take(.2,2))
    assert(not b:Take(1.5,2), 'live cap survives second rollover')
    assert(b:Take(2,2) and b:Take(2.1,2) and not b:Take(2.2,2))
    local rate=Budget.New(3,10)
    assert(rate:Take(0,.01) and rate:Take(.2,.01) and rate:Take(.9,.01))
    assert(not rate:Take(.99,.01),'rolling-second cap, not calendar buckets')
    assert(rate:Take(1,.01) and not rate:Take(1.01,.01))
    local map=Budget.New(2,3)
    assert(map:Take(0,math.huge) and map:Take(.1,math.huge))
    assert(map:Take(10,math.huge) and not map:Take(1000,math.huge))
    map:Reset() assert(map:Take(1000,math.huge))
elseif scenario=='coexist' or scenario=='absent' or scenario=='preloaded' then
    local loaded={}
    file.Exists=function(path) return scenario~='absent' and (path=='nlblood/shapes.lua' or path=='dynamic_toolgun_screen/nl_package.lua') end
    include=function(path)
        loaded[path]=(loaded[path] or 0)+1
        if path=='nlblood/shapes.lua' then return {} end
    end
    local before=include
    local original
    if scenario=='preloaded' then
        original=util.DecalEx
        BloodOverhaul={OrigDecalEx=original,ConVars={enable={}}}
        util.DecalEx=assert(loadstring('return function() error("old mixer ran") end','@lua/bloodoverhaul/cl_core.lua'))()
        hook.Add('InitPostEntity','bloodoverhaul_apply',function() error('old apply ran') end)
        hook.Add('AddToolMenuCategories','bloodoverhaul_menu',function() error('old category ran') end)
    end
    dofile(source('autorun/!nativeloader_blood.lua'))
    if scenario=='absent' then assert(include==before and not BloodOverhaul) else
        assert(BloodOverhaul.Packaged and NativeLoaderBundledDTS)
        -- Either standalone or package virtual source can be selected; both use these old paths.
        for _=1,2 do
            for _,p in ipairs({'sh_shapes','cl_schemes','cl_core','cl_menu'}) do include('bloodoverhaul/'..p..'.lua') end
            include('dynamic_toolgun_screen/cl_core.lua')
        end
        assert(not loaded['bloodoverhaul/cl_core.lua'])
        assert(loaded['dynamic_toolgun_screen/cl_core.lua']==1)
        include('dynamic_toolgun_screen/lang/fr.lua') include('dynamic_toolgun_screen/lang/fr.lua')
        assert(loaded['dynamic_toolgun_screen/lang/fr.lua']==2,'language reload must work')
        include('other/addon.lua') include('other/addon.lua') assert(loaded['other/addon.lua']==2)
        local guarded=include dofile(source('autorun/!nativeloader_blood.lua')) assert(guarded==include)
        assert(loaded['nativeloader/blood_core.lua']==1 and loaded['nativeloader/blood_impacts.lua']==1)
        if original then
            assert(util.DecalEx==original)
            assert(not hooks.InitPostEntity.bloodoverhaul_apply and not hooks.AddToolMenuCategories.bloodoverhaul_menu)
        end
    end
elseif scenario=='menu_fallback' then
    NativeLoaderBundledDTS=true
    dofile(source('autorun/client/nativeloader_bundled_panels.lua'))
    local adapter=spawnmenu.AddToolMenuOption
    dofile(source('autorun/client/nativeloader_bundled_panels.lua')) assert(adapter==spawnmenu.AddToolMenuOption)
    spawnmenu.AddToolMenuOption('Utilities','dts.menu.category','dts_settings','Settings','','',function() end)
    spawnmenu.AddToolMenuOption('Main','Render','dynamic_toolgun_screen','Screen','gmod_tool dynamic_toolgun_screen','',function() end)
    assert(#calls.panels==1 and calls.panels[1][1]=='RTX Remix' and calls.panels[1][2]=='Rendering')
    assert(calls.panels[1][5]=='gmod_tool dynamic_toolgun_screen')
elseif scenario=='menu' then
    NativeLoaderBundledDTS=true
    dofile(source('autorun/client/nativeloader_menu.lua'))
    spawnmenu.AddToolMenuOption('Utilities','dts.menu.category','dts_settings','#dts.menu.settings','','',function() end)
    spawnmenu.AddToolMenuOption('Main','Render','dynamic_toolgun_screen','#tool.dynamic_toolgun_screen.name','gmod_tool dynamic_toolgun_screen','',function() end)
    spawnmenu.AddToolMenuOption('Utilities','Other','other','Other','','',function() end)
    assert(#calls.panels==2)
    local moved=calls.panels[1]
    assert(moved[1]=='RTX Remix' and moved[2]=='Rendering' and moved[3]=='dynamic_toolgun_screen')
    assert(moved[4]=='Dynamic toolgun screen' and moved[5]=='gmod_tool dynamic_toolgun_screen')
    assert(calls.panels[2][1]=='Utilities')
    NativeLoaderBundledDTS=false
    spawnmenu.AddToolMenuOption('Utilities','dts.menu.category','dts_settings','Settings','','',function() end)
    assert(#calls.panels==3 and calls.panels[3][1]=='Utilities')
else
    BloodOverhaul={Packaged=true,Shapes=include('nlblood/shapes.lua')}
    if scenario=='previous_impact' then
        effects.Create=function(name) if name=='Impact' then return {
            Init=function(self,data) calls.previous_data=data self.started=true end,
            Think=function(self) return self.started end,Render=function(self) self.rendered=true end,
            helper=17,
        } end end
    end
    include('nlblood/schemes.lua') include('nativeloader/blood_core.lua') include('nativeloader/blood_impacts.lua')
    local BO=BloodOverhaul
    local data={GetColor=function() return 0 end,GetOrigin=function() return Vector() end,
                GetNormal=function() return Vector(1,0,0) end,GetScale=function() return 2 end}
    local function hit() registered:Init(data) end
    if scenario=='ragdolls' or scenario=='previous_impact' then
        function EffectData()
            local d={}
            for _,key in ipairs({'Origin','Normal','Color','Scale'}) do
                d['Set'..key]=function(self,v) self[key]=v end
                d['Get'..key]=function(self) return self[key] end
            end
            return d
        end
        local rag={IsRagdoll=function() return true end,GetClass=function() return 'prop_ragdoll' end,
                   GetBloodColor=function() return nil end,IsWorld=function() return false end}
        local victim=rag
        local surface=70
        util.GetSurfaceData=function() return {material=surface} end
        data.GetEntity=function() return victim end
        data.GetStart=function() return Vector(-100,0,0) end
        data.GetDamageType=function() return 2 end
        data.GetSurfaceProp=function() return 39 end
        data.GetScale=function() return 1 end
        if scenario=='previous_impact' then
            victim={IsRagdoll=function() return false end,GetClass=function() return 'prop_physics' end,IsWorld=function() return false end}
            local self={}
            registrations.Impact.Init(self,data)
            assert(calls.previous_data==data and self.helper==17 and #added==0)
            assert(registrations.Impact.Think(self)) registrations.Impact.Render(self) assert(self.rendered)
        else
            registrations.Impact.Init({},data)
            assert(BO.ImpactStats.ragdoll_impacts==1 and #added>0 and BO.ImpactStats.last_colour==0)
            assert(calls.effects[#calls.effects][1]=='Impact' and calls.effects[#calls.effects][2]==data and calls.effects[#calls.effects][3]==false)
            local n=#added
            registrations.Impact_GMOD.Init({},data) assert(#added==n,'cross-name duplicate')
            registrations.Impact.Init({},data) assert(#added>n,'separate pellet')
            n=#added surface=77 clock=.1 registrations.Impact.Init({},data) assert(#added==n,'metal stays dry')
            surface=70 rag.GetBloodColor=function() return -1 end
            registrations.Impact.Init({},data) assert(#added==n,'explicitly bloodless stays dry')
            rag.GetBloodColor=function() return nil end
            hook.Run('CreateClientsideRagdoll',{GetBloodColor=function() return 6 end},rag)
            registrations.Impact.Init({},data) assert(BO.ImpactStats.last_colour==6,'source blood colour retained')
            victim=false
            util.TraceLine=function(t) assert(t.hitclientonly) return {Hit=true,Entity=rag,HitPos=Vector(8,0,0),MatType=70} end
            clock=.2 registrations.Impact.Init({},data) assert(BO.ImpactStats.last_colour==6)
            n=#added RunConsoleCommand('nativeloader_blood_impacts','0')
            registrations.Impact.Init({},data) assert(#added==n and calls.effects[#calls.effects][3]==false)
        end
    elseif scenario=='world_landing' then
        util.TraceLine=function(t) return {Hit=true,HitWorld=true,Entity=false,HitPos=t.start,HitNormal=Vector(0,0,1)} end
        hit()
        for _,p in ipairs(added) do
            if p.props.SetCollideCallback then p.props.SetCollideCallback[1](p,Vector(),Vector(0,0,1)) break end
        end
        assert(BO.ImpactStats.landings==1 and BO.ImpactStats.stains==1 and BO.ImpactStats.trace_misses==0)
    elseif scenario=='stock_materials' then
        local original=Material('decals/blood1_subrect')
        local oldtex,oldcol=original:GetTexture('$basetexture'):GetName(),original:GetVector('$color')
        local model=Material('decals/flesh/blood1')
        local modeltex,modelcol=model:GetTexture('$basetexture'):GetName(),model:GetVector('$color2')
        local shared_model=Material('decals/bloodoverhaul/red/bo_blood1_model')
        local shared_tex,shared_col=shared_model:GetTexture('$basetexture'):GetName(),shared_model:GetVector('$color2')
        local unsafe=Material('decals/yblood2_subrect') unsafe.shader='Subrect'
        local unsafe_tex=unsafe:GetTexture('$basetexture'):GetName()
        local stain=Material('decals/bloodstain_001')
        local staintex=stain:GetTexture('$basetexture'):GetName()
        BO.Apply()
        assert(original:GetTexture('$basetexture'):GetName()=='decals/bloodoverhaul/tex/bo_blood1')
        for _,s in ipairs(BO.Schemes) do
            RunConsoleCommand('bloodoverhaul_scheme',s.id)
            for _,code in ipairs({0,1,2,6}) do
                for i=1,8 do assert(BO.Pattern(code,i),'all eight originals in every family') end
            end
            assert(unsafe:GetTexture('$basetexture'):GetName()==unsafe_tex,'Subrect must not alter its parent')
            assert(stain:GetTexture('$basetexture'):GetName()==staintex,'original did not recolour stains')
        end
        RunConsoleCommand('bloodoverhaul_scheme','blue')
        assert(original:GetTexture('$basetexture'):GetName()=='decals/bloodoverhaul/tex/bo_blood1_n')
        assert(model:GetTexture('$basetexture'):GetName()=='decals/bloodoverhaul/tex/flesh1_n')
        assert(model:GetVector('$color2').z>model:GetVector('$color2').x)
        calls.watch_material=shared_model:GetName() calls.material_writes=0 calls.texture_trace={}
        RunConsoleCommand('bloodoverhaul_scheme','violet')
        for _,texture in ipairs(calls.texture_trace) do
            assert(texture~='original:'..shared_model:GetName(),
                'enabled palette changes must paint directly, without restoring the baseline in between')
        end
        calls.watch_material=shared_model:GetName() calls.material_writes=0
        RunConsoleCommand('bloodoverhaul_enable','0')
        assert(calls.material_writes==1,'one restore for each underlying engine material, including wrapper aliases')
        calls.watch_material=nil
        assert(original:GetTexture('$basetexture'):GetName()==oldtex and original:GetVector('$color').x==oldcol.x)
        assert(model:GetTexture('$basetexture'):GetName()==modeltex and model:GetVector('$color2').z==modelcol.z)
        assert(shared_model:GetTexture('$basetexture'):GetName()==shared_tex and shared_model:GetVector('$color2').x==shared_col.x,
            'stock subrect and mixer aliases must share one original model-material snapshot')
        BO.Pattern(0,1) BO.Apply()
        assert(original:GetTexture('$basetexture'):GetName()==oldtex,'disabled apply must stay restored')
        RunConsoleCommand('bloodoverhaul_enable','1')
        assert(original:GetTexture('$basetexture'):GetName()=='decals/bloodoverhaul/tex/bo_blood1_n')
        -- A later add-on edit while disabled becomes the next restore baseline.
        RunConsoleCommand('bloodoverhaul_enable','0') original:SetTexture('$basetexture','another_addon')
        RunConsoleCommand('bloodoverhaul_enable','1') RunConsoleCommand('bloodoverhaul_enable','0')
        assert(original:GetTexture('$basetexture'):GetName()=='another_addon')
    elseif scenario=='impacts' then
        assert(registered:Think()==false)
        for _,name in ipairs({'nativeloader_blood_impacts','bloodoverhaul_enable','nativeloader_blood_amount'}) do
            RunConsoleCommand(name,'0') hit()
            assert(calls.effects[#calls.effects][1]=='BloodImpact' and calls.effects[#calls.effects][2]==data and calls.effects[#calls.effects][3]==false)
            RunConsoleCommand(name,'1')
        end
        data.GetColor=function() return 3 end hit() assert(#added==0)
        data.GetColor=function() return 0 end
        calls.fail_emitter=true hit() assert(#added==0) calls.fail_emitter=false
        hit() assert(#added>0)
        local back,forward,mist,escaped,grounded=0,0,0,0,0
        for _,p in ipairs(added) do
            if p.props.SetVelocity[1].x<0 then back=back+1 else forward=forward+1 end
            if p.props.SetDieTime[1]<.25 then mist=mist+1 end
            if p.props.SetCollideCallback then
                -- Independent linear-drag flight check: droplets must leave the body and some
                -- must reach ground 48 units below it before their configured lifetime ends.
                local velocity=p.props.SetVelocity[1]
                local vx,vz,x,z=velocity.x,velocity.z,0,0
                local dt,drag=1/120,p.props.SetAirResistance[1]
                for t=dt,p.props.SetDieTime[1],dt do
                    vx=vx*math.max(0,1-drag*dt)
                    vz=(vz+p.props.SetGravity[1].z*dt)*math.max(0,1-drag*dt)
                    x,z=x+vx*dt,z+vz*dt
                end
                if math.abs(x)>12 then escaped=escaped+1 end
                if z< -48 then grounded=grounded+1 end
            end
        end
        assert(back>0 and forward>back and mist>0)
        assert(escaped>=(#added-mist)/2 and grounded>=(#added-mist)/2,'blood must travel out of the body and land')
        local n=BO.ImpactPlan(2,100,1)
        assert(BO.ImpactPlan(2,2000,1)<n and BO.ImpactPlan(2,5000,1)==0)
        assert(BO.ImpactPlan(8,100,2)<=42 and BO.ImpactPlan(2,100,0)==0)
        assert(BO.ImpactPlan(12,100,1)>BO.ImpactPlan(8,100,1))
        assert(BO.ImpactPlan(60,100,1)>BO.ImpactPlan(40,100,1),'multiplayer amounts must remain distinct')
        assert(BO.ImpactPlan(0/0,0,1)>0 and BO.ImpactPlan(math.huge,0,1)>0)
        local pale=BO.Colour(1) local green=BO.Colour(2) assert(pale.g~=green.g)
        for _,scheme in ipairs(BO.Schemes) do
            RunConsoleCommand('bloodoverhaul_scheme',scheme.id)
            for _,code in ipairs({0,1,2,4,5,6}) do assert(IsColor(BO.Colour(code,2))) assert(BO.Pattern(code,1)) end
        end
        assert(not BO.Colour(3) and not BO.Pattern(3,1))
        local external=emitter_meta.Add({},'decals/blood1',Vector(),99)
        assert(external.mat:GetName():find('nlfluid_',1,true) and external.extra[1]==99 and external.material_changed)
        RunConsoleCommand('bloodoverhaul_droplets','0')
        external=emitter_meta.Add({},'decals/blood1',Vector(),99)
        assert(external.mat=='decals/blood1' and external.extra[1]==99)
        local original=Material('decals/blood1')
        RunConsoleCommand('bloodoverhaul_variety','0')
        util.DecalEx(original,'ent','pos','normal','colour',.7,.9)
        assert(calls.decals[#calls.decals][1]:GetName()=='decals/bloodoverhaul/red/bo_blood1')
        RunConsoleCommand('bloodoverhaul_enable','0')
        util.DecalEx(original,'ent','pos','normal','colour',.7,.9)
        local dec=calls.decals[#calls.decals]
        assert(dec[1]==original and dec[2]=='ent' and dec[3]=='pos' and dec[4]=='normal' and dec[5]=='colour' and dec[6]==.7 and dec[7]==.9)
    elseif scenario=='saturation' then
        for i=1,200 do hit() end
        assert(#added<=512 and #BO.ImpactBudgets.particles.recent<=640)
        assert(BO.ImpactStats.culled>0 and BO.ImpactStats.denied>0)
        local function land(first)
            for j=first,#added do
                local p=added[j] local cb=p.props.SetCollideCallback
                if cb then cb[1](p,Vector(),Vector(0,0,1)) cb[1](p,Vector(),Vector(0,0,1)) end
            end
        end
        land(1) assert(#calls.decals==48,'collision storms are rate limited and one-shot')
        for batch=1,12 do
            clock=batch*2 local first=#added+1
            for j=1,30 do hit() end
            land(first)
            assert(#BO.ImpactBudgets.particles.recent<=640 and #BO.ImpactBudgets.particles.live<=512)
        end
        assert(#calls.decals==384 and BO.ImpactBudgets.stains.total==384)
        RunConsoleCommand('nativeloader_blood_impacts','0') RunConsoleCommand('nativeloader_blood_impacts','1')
        assert(BO.ImpactBudgets.stains.total==384,'toggles cannot evade map cap')
        commands.bloodoverhaul_clear() assert(BO.ImpactBudgets.stains.total==0)
        clock=clock+2 local first=#added+1 hit() land(first) assert(#calls.decals>384)
    elseif scenario=='blood_menu' then
        dofile(source('autorun/client/nativeloader_blood_menu.lua'))
        local builder=BO.BuildMenu
        dofile(source('autorun/client/nativeloader_blood_menu.lua'))
        assert(BO.BuildMenu==builder,'repeat catalog owner must not reinitialize the menu')
        hook.Run('PopulateToolMenu')
        assert(#calls.panels==1 and calls.panels[1][1]=='RTX Remix' and calls.panels[1][2]=='Blood')
        assert(calls.panels[1][3]=='bloodoverhaul_settings')
    else error('unknown scenario '..scenario) end
end
print('PASS '..scenario)
