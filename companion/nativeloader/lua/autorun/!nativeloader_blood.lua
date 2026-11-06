-- R20-C: exact-path coexistence guards and the owned blood implementation (ADR 0118).
-- This sorts before the standalone autoruns. Their files and materials remain untouched.
local blood = file.Exists("nlblood/shapes.lua", "LUA")
local screen = file.Exists("dynamic_toolgun_screen/nl_package.lua", "LUA")
if not blood and not screen then return end
if SERVER then
    AddCSLuaFile()
    if blood then
        for _, path in ipairs({ "nlblood/shapes.lua", "nlblood/schemes.lua",
            "nativeloader/blood_budget.lua", "nativeloader/blood_core.lua", "nativeloader/blood_impacts.lua" }) do
            AddCSLuaFile(path)
        end
    end
    return
end
if NativeLoaderBundledBloodStarted then return end
NativeLoaderBundledBloodStarted = true
NativeLoaderBundledDTS = screen

local legacy = {
    ["bloodoverhaul/sh_shapes.lua"] = true, ["bloodoverhaul/cl_schemes.lua"] = true,
    ["bloodoverhaul/cl_core.lua"] = true, ["bloodoverhaul/cl_menu.lua"] = true,
}
local once = {}
for _, path in ipairs({ "cl_core.lua", "cl_i18n.lua", "cl_draw.lua", "cl_tokens.lua", "cl_themes.lua",
    "layouts/cl_pocketpc.lua", "layouts/cl_terminal.lua", "layouts/cl_minimal.lua", "cl_render.lua",
    "cl_features.lua", "cl_inspect.lua", "cl_compat.lua", "cl_menu.lua" }) do
    once["dynamic_toolgun_screen/" .. path] = true
end
local original_include, seen = include, {}
function include(path, ...)
    local key = type(path) == "string" and string.lower(path:gsub("\\", "/"))
    if blood and legacy[key] then return end
    if screen and once[key] then
        if seen[key] then return end
        seen[key] = true
    end
    return original_include(path, ...)
end

if blood then
    BloodOverhaul = { Packaged = true, Shapes = include("nlblood/shapes.lua") }
    include("nlblood/schemes.lua")
    include("nativeloader/blood_core.lua")
    include("nativeloader/blood_impacts.lua")
end
