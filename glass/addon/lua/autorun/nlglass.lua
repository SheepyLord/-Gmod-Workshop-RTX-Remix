-- MIT. Shared bootstrap; the debris implementation belongs to task G1-B.
NLGlass=NLGlass or {}
local shared={"fracture","config","geometry","protocol"}
local client={"i18n_data","i18n","client","menu"}
if SERVER then
    for _,name in ipairs(shared) do AddCSLuaFile("nlglass/"..name..".lua") end
    for _,name in ipairs(client) do AddCSLuaFile("nlglass/"..name..".lua") end
    -- B's files are optional while the tasks are developed separately. Serve every supporting
    -- file too: clients do not need a separate local add-on install. B owns its client includes.
    for _,pattern in ipairs({"nlglass/debris*.lua","nlglass/world*.lua"}) do
        local files=file.Find(pattern,"LUA")
        for _,name in ipairs(files) do AddCSLuaFile("nlglass/"..name) end
    end
end
NLGlass.Fracture=include("nlglass/fracture.lua")
NLGlass.Config=include("nlglass/config.lua")
NLGlass.Geometry=include("nlglass/geometry.lua")
NLGlass.Protocol=include("nlglass/protocol.lua")
if SERVER then
    NLGlass.Damage=include("nlglass/damage.lua")
    include("nlglass/server.lua")
else
    if file.Exists("nlglass/debris.lua","LUA") then include("nlglass/debris.lua") end
    NLGlass.I18n=include("nlglass/i18n.lua")
    include("nlglass/client.lua") include("nlglass/menu.lua")
end

-- Presets inherit the same implementation, so tool/dupe/save handling stays in one class.
for _,kind in ipairs({"annealed","tempered"}) do
    for _,size in ipairs({{48,48},{96,64},{128,128}}) do
        local name="nlglass_"..kind.."_"..size[1].."x"..size[2]
        scripted_ents.Register({Type="anim",Base="nlglass_pane",PrintName="#"..name,
            Category="Glass Rewrite",Spawnable=true,NLGlassPreset={kind=kind,width=size[1],height=size[2]}},name)
    end
end
