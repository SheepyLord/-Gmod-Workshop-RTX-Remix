-- Original, minimal API-call replays from the R8 audit; never load/execute third-party add-on code.
return function(scenario, c)
    local eq, stats = c.eq, c.stats
    local function replay(path, code)
        local fn = assert(loadstring(code, "@lua/" .. path))
        local ok, err = pcall(fn)
        assert(ok, tostring(err))
        return fn
    end
    local function noErrors() eq(#c.errorReports, 0) eq(#c.guard.errors, 0) end
    if scenario == "r8_gshader_targets" then
        replay("autorun/client/worldpos.lua", [[
            IMAGE_FORMAT_RGBA32323232F, IMAGE_FORMAT_R32F = 29, 27
            hook.Add("InitReconstruction","Reconstruction",function()
            r8_targets = {
                GetRenderTargetEx("_rt_WPDepth", ScrW(), ScrH(),4,2,8422157,0,29),
                GetRenderTargetEx("_rt_softwaredepth_half",ScrW()*0.5,ScrH()*0.5,8,2,8422157,0,27),
                GetRenderTargetEx("_rt_NormalsTangents",ScrW(),ScrH(),4,2,8422157,0,24)}
            end)
        ]])
        replay("autorun/!!shaderlib.lua", [[
            hook.Add("Initialize","shaderlib",function()
                hook.Run("InitReconstruction")
                r8_done=true
            end)
        ]])
        hook.Run("Initialize")
        assert(r8_done) eq(#c.rtCalls,0,"no deferred renderer allocation reached native")
        eq(stats().fallback,1,"one shared engine-backed fallback")
        for _,target in ipairs(r8_targets) do eq(target:Width(),1) eq(target:Height(),1) eq(target,r8_targets[1]) end
        noErrors()
    elseif scenario == "r8_gshader_depth" then
        replay("autorun/client/depthbuffer.lua", [[
            r8_stock = render.GetResolvedFullFrameDepth()
            r8_depth = GetRenderTargetEx(r8_stock:GetName(),1,1,4,0,33548,8,27)
            r8_sky = GetRenderTargetEx("_rt_ResolvedFullFrameDepthSky",1,1,4,3,33548,8,27)
            r8_depthmat = CreateMaterial("depthwritesky","DepthWrite",{["$COLOR_DEPTH"]="1"})
            render.CopyRenderTargetToTexture(r8_stock)
            render.CopyTexture(r8_stock,r8_sky)
        ]])
        eq(r8_depth:GetName(),r8_stock:GetName(),"engine depth name preserved without recreation")
        eq(#c.rtCalls,0) eq(stats().copy,0) eq(#c.created,0)
        eq(r8_depthmat:GetShader(),"UnlitGeneric") noErrors()
    elseif scenario == "r8_disk_shaders" then
        -- Remote/opaque VMTs may not be readable. Known effect origins must not load them anyway.
        replay("autorun/client/worldpos.lua", [[Material("pp/opaque-deferred-material")]])
        replay("lifemod/render/modules/dof.lua", [[Material("pp/dof")]])
        eq(#c.mats,0,"known effects skip native lookup even with no readable VMT")
        c.vmtFiles["materials/pp/fxaa.vmt"]='"screenspace_general" { "$pixshader" "fxaa_high_ps30" }'
        c.vmtFiles["materials/pp/patched.vmt"]='"Patch" { "include" "pp/fxaa.vmt" }'
        c.vmtFiles["materials/pp/lux.vmt"]='"LUX_ScreenSpace_General" {}'
        c.vmtFiles["materials/pp/cycle.vmt"]='"patch" { "include" "pp/cycle" }'
        c.vmtFiles["materials/pp/missing.vmt"]='"Patch" { "include" "missing-include" }'
        c.vmtFiles["materials/pp/bare.vmt"]='UnlitGeneric { $pixshader custom_ps30 }'
        c.vmtFiles["materials/pp/bom.vmt"]='\239\187\191"DepthWrite" {}'
        for _,path in ipairs({"pp/fxaa","pp/patched","pp/lux","pp/cycle","pp/missing","pp/bare","pp/bom"}) do
            eq(Material(path):GetShader(),"UnlitGeneric")
        end
        eq(#c.mats,0,"custom shaders never reached native Material")
        local mat=Material("normal") eq(#c.mats,1) eq(mat:GetShader(),"UnlitGeneric") noErrors()
    elseif scenario == "r8_effect_draws" then
        for _,path in ipairs({"postprocess/fxaa.lua","postprocess/ssdo.lua","postprocess/pp_ssr.lua"}) do
            replay(path, [[
                local mat=CreateMaterial("deferred","screenspace_general",{["$pixshader"]="custom_ps30"})
                local target=GetRenderTargetEx("SSDO_RT",ScrW(),ScrH(),8,2,0,0,29)
                render.PushRenderTarget(target) render.Clear(0,0,0,0)
                render.SetMaterial(mat) render.SetRenderTargetEx(1,target) render.DrawQuad()
                render.CopyRenderTargetToTexture(render.GetScreenEffectTexture())
                render.SetRenderTargetEx(1) render.PopRenderTarget()
                surface.SetMaterial(mat) surface.DrawTexturedRect(0,0,ScrW(),ScrH())
            ]])
        end
        eq(stats().quad,0) eq(stats().copy,0) eq(stats().clear,0) eq(stats().surface,0)
        eq(stats().rtEx,3,"only legal MRT clears passed") eq(#c.rtStack,0) noErrors()
        render.SetMaterial(Material("normal")) render.DrawScreenQuad() eq(stats().quad,1,"normal drawing resumes")
    elseif scenario == "r8_world_materials" then
        r8_world=Material("brick/wall")
        r8_entity=setmetatable({},{__index=c.entityMeta})
        replay("autorun/client/bumps_building.lua", [[
            local mat=CreateMaterial("world_bumps","screenspace_general",{["$pixshader"]="bump_ps30"})
            r8_world:SetTexture("$basetexture",render.GetScreenEffectTexture())
            r8_world:SetShader("screenspace_general")
            r8_entity:SetMaterial("pp/bump")
            r8_entity:SetSubMaterial(0,"pp/bump")
            mat:SetFloat("$alpha",1) mat:Recompute()
        ]])
        eq(stats().mutation,0) eq(stats().entity,0)
        local depth=render.GetResolvedFullFrameDepth()
        local luaType=type
        type=function(value) if value==depth then return "ITexture" end return luaType(value) end
        r8_world:SetTexture("$basetexture",depth)
        type=luaType
        r8_world:SetString("$basetexture",GetRenderTarget("bad",0,0):GetName())
        eq(stats().mutation,0,"depth and inert textures cannot replace a world material through another caller")
        r8_world:SetFloat("$alpha",0.8) eq(stats().mutation,1,"legitimate material setter survives")
        c.vmtFiles["materials/custom-world.vmt"]='"screenspace_general" {}'
        r8_entity:SetMaterial("custom-world") eq(stats().entity,0)
        eq(r8_entity:SetSubMaterial(0,"normal"),"sub") eq(stats().entity,1) noErrors()
    elseif scenario == "r8_quick_bloom" then
        replay("autorun/client/cl_bloom_config.lua", [[
            hook.Add("Initialize","CustomBloomSettings",function()
                RunConsoleCommand("mat_bloomscale","0")
                RunConsoleCommand("mat_bloom_scalefactor_scalar","0.2")
                r8_bloom_setup=true
            end)
        ]])
        hook.Run("Initialize") assert(r8_bloom_setup) eq(#c.guard.blocked,2) noErrors()
    elseif scenario == "r8_realcsm" then
        replay("entities/edit_csm/cl_init.lua", [[
            for i=0,7 do
                local target=GetRenderTargetEx("_rt_shadowdepthtexture_"..i,4096,4096,8,2,13,0,48)
                assert(target:Width()>0)
            end
            local lamp=ProjectedTexture()
            lamp:SetEnableShadows(true) lamp:SetFOV(90) lamp:SetNearZ(1) lamp:SetFarZ(131072) lamp:Update()
            render.RedownloadAllLightmaps(false,true)
            GetConVar("r_flashlightdepthres"):SetInt(16384)
        ]])
        eq(#c.rtCalls,0) eq(stats().updates,0) eq(stats().shadows,0)
        eq(GetConVar("r_flashlightdepthres"):GetInt(),1024)
        local ordinary=ProjectedTexture() ordinary:SetEnableShadows(true) ordinary:Update()
        eq(stats().updates,1) eq(stats().shadows,1,"ordinary flashlight path unchanged") noErrors()
    elseif scenario == "r8_lifemod" then
        replay("lifemod/render/modules/dof.lua", [[
            hook.Add("RenderScreenspaceEffects","LifeDOF",function()
                render.DepthRange(0.5,1) cam.Start3D()
                render.SetMaterial(Material("pp/dof")) render.DrawSprite({x=0,y=0,z=0},128,128,{r=255,g=255,b=255,a=255})
                cam.End3D() render.DepthRange(0,1)
                r8_dof_ran=true
            end)
        ]])
        replay("lifemod/render/modules/videodistortion.lua", [[
            hook.Add("PostDrawEffects","LifeDistortion",function()
                render.CopyRenderTargetToTexture(render.GetScreenEffectTexture())
                surface.SetMaterial(Material("pp/copy")) surface.DrawTexturedRectUV(0,0,ScrW(),ScrH(),0,0,1,1)
                r8_distortion_ran=true
            end)
        ]])
        hook.Run("RenderScreenspaceEffects") hook.Run("PostDrawEffects")
        eq(r8_dof_ran,nil) eq(r8_distortion_ran,nil) eq(stats().quad,0) eq(stats().copy,0) noErrors()
        -- LifeMod dispatches module methods itself: direct API paths must also be inert.
        replay("lifemod/render/modules/videodistortion.lua", [[
            render.CopyRenderTargetToTexture(render.GetScreenEffectTexture())
            surface.SetMaterial(Material("pp/copy")) surface.DrawTexturedRectUV(0,0,ScrW(),ScrH(),0,0,1,1)
        ]])
        eq(stats().copy,0) eq(stats().surface,0)
    elseif scenario == "r8_niknaks" then
        replay("niknaks/modules/cl_lightmap_atlas.lua", [[
            r8_atlas=GetRenderTargetEx("NikNaks_atlas",256,128,8,2,0,0,0)
            r8_layer=CreateMaterial("NikNaks_LightmapLayer","UnlitGeneric",{})
            r8_layer:SetTexture("$basetexture",r8_atlas)
        ]])
        eq(r8_atlas:Width(),256) eq(r8_atlas:Height(),128) eq(#c.rtCalls,1) eq(stats().mutation,1) noErrors()
    elseif scenario == "r8_limits" then
        -- Enums added by an add-on do not confer backend support, even on the late route.
        for _,format in ipairs({5,13,28,29,33,38,39,42,47,48,67,9999}) do
            local target=GetRenderTargetEx("unreviewed_"..format,512,512,8,2,0,0,format)
            eq(target:Width(),1)
        end
        for _,size in ipairs({0,-1,0.5,0/0,math.huge,100000}) do eq(GetRenderTarget("size",size,512):Width(),1) end
        eq(GetRenderTargetEx("cubemap",256,256,8,2,16384,0,0):Width(),1)
        RT_SIZE_LITERAL=7777 MATERIAL_RT_DEPTH_ONLY=99
        eq(GetRenderTargetEx("changed-size",16,16,RT_SIZE_LITERAL,2,0,0,0):Width(),1)
        eq(GetRenderTargetEx("changed-depth",16,16,8,MATERIAL_RT_DEPTH_ONLY,0,0,0):Width(),1)
        eq(#c.rtCalls,0) eq(stats().fallback,1) noErrors()
    elseif scenario == "r8_budget" then
        for i=1,128 do GetRenderTarget("small_"..i,8,8) end
        eq(GetRenderTarget("quota",8,8):Width(),1) eq(#c.rtCalls,128)
        noErrors()
    elseif scenario == "r8_byte_budget" then
        for i=1,32 do GetRenderTarget("large_"..i,2048,2048) end
        eq(GetRenderTarget("budget",2048,2048):Width(),1) eq(#c.rtCalls,32)
        eq(c.guard.allocation_bytes,536870912) noErrors()
    elseif scenario == "r8_pair_fallback" then
        local base=c.texture("toolgun",256,256)
        render.PushRenderTarget(base)
        render.PushRenderTarget(GetRenderTarget("invalid",0,0)) render.Clear() render.DrawScreenQuad()
        eq(#c.rtStack,1) eq(stats().clear,0) eq(stats().quad,0)
        render.PopRenderTarget() eq(#c.rtStack,1) eq(stats().currentRT,base)
        render.PopRenderTarget() eq(#c.rtStack,0)
        cam.Start3D(nil,nil,0/0) cam.End3D() eq(stats().camera,0) noErrors()
    elseif scenario == "r8_light_wrappers" then
        r8_lamp=ProjectedTexture()
        local before=debug.getmetatable(r8_lamp)
        replay("autorun/!!projected_texture_wrapper.lua", [[
            local meta=FindMetaTable("ProjectedTexture")
            meta.Remove=function()error("should stay private")end
            local changed=debug.getmetatable(r8_lamp)
            changed.__index=function()error("must not replace native index")end
            debug.setmetatable(r8_lamp,changed)
            assert(debug.getmetatable(r8_lamp)==changed,"the wrapper must read back its own private edits")
        ]])
        eq(debug.getmetatable(r8_lamp),before) eq(c.projectedMeta.Remove,nil)
        replay("autorun/!!dynamic_light_wrapper.lua", [[
            local meta=FindMetaTable("dlight_t") meta.__newindex=function()error("private")end
            local fields={brightness=0}
            debug.setmetatable(r8_lamp,{__index=fields})
            -- Reacquiring a cached light resets the private field table, not the native metatable.
            for i=1,2 do
                local own=debug.getmetatable(r8_lamp)
                own.__index.brightness=i
            end
            assert(fields.brightness==2)
        ]])
        eq(FindMetaTable("dlight_t").__newindex,nil) r8_lamp:Update() eq(stats().updates,1) noErrors()
    elseif scenario == "r8_mp_callbacks" then
        eq(c.guard.installation,"verified multiplayer bootstrap")
        replay("autorun/!!shaderlib.lua", [[
            hook.Add("RenderScene","shaderlib",function()error("deferred renderer must stay inert")end)
            hook.Add("NeedsDepthPass","shaderlib",function()return true end)
            timer.Create("shaderlib",1,0,function()error("deferred timer must stay inert")end)
        ]])
        eq(c.beforeCall("RenderScene"),nil,"cached engine dispatcher invokes the policy wrapper")
        eq(c.beforeCall("NeedsDepthPass"),false)
        assert(pcall(c.timers.shaderlib))
        local server=function()error("ordinary server failure")end
        hook.Add("HUDPaint","server",server)
        eq(hook.GetTable().HUDPaint.server,server)
        assert(not pcall(c.beforeCall,"HUDPaint"),"server Lua retains vanilla error behavior") noErrors()
    elseif scenario == "r8_callbacks" then
        replay("autorun/!!shaderlib.lua", [[
            hook.Add("Initialize","shaderlib",function()r8_init=true end)
            hook.Add("RenderScene","shaderlib",function()error("inert")end)
        ]])
        hook.Run("Initialize") assert(r8_init)
        eq(c.beforeCall("RenderScene"),nil)
        local good=function()return false,2,nil,4,5,6 end
        hook.Add("HUDPaint","good",good) eq(hook.GetTable().HUDPaint.good,good)
        local a,b,d,e,f,g=hook.Run("HUDPaint") eq(a,false) eq(b,2) eq(d,nil) eq(g,6) noErrors()
    elseif scenario == "r8_off_replays" then
        c.cv.nativeloader_guard.value="0"
        replay("autorun/client/worldpos.lua", [[
            r8_raw=GetRenderTargetEx("_rt_WPDepth",1920,1080,4,2,0,0,29)
            CreateMaterial("custom","screenspace_general",{})
            render.SetRenderTargetEx(1,r8_raw)
            hook.Add("RenderScene","shaderlib",function()r8_off_ran=true end)
        ]])
        hook.Run("RenderScene") assert(r8_off_ran)
        eq(#c.rtCalls,1) eq(#c.created,1) eq(stats().rtEx,1) eq(#c.guard.blocked,0) noErrors()
    elseif scenario == "r8_allocator_failure" then
        c.failAllocator()
        local target=GetRenderTarget("invalid",0,0)
        eq(target:GetName(),"_rt_FullFrameFB","allocator Lua error uses existing engine texture") noErrors()
    else error("unknown replay "..scenario) end
end
