-- R20-C/R21-A: exact-path coexistence guards and private blood implementation (ADRs 0118/0124).
-- This sorts before standalone autoruns. Their on-disk files remain untouched.
local blood = file.Exists("nlblood/shapes.lua", "LUA")
local screen = file.Exists("dynamic_toolgun_screen/nl_package.lua", "LUA")
if not blood and not screen then return end
if SERVER then
    AddCSLuaFile()
    if screen then
        AddCSLuaFile("dynamic_toolgun_screen/nl_package.lua")
        AddCSLuaFile("autorun/client/nativeloader_bundled_panels.lua")
    end
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
    -- A remote server can have sent the old standalone before the verified local payload loads.
    -- Retire only that add-on's named registrations and directly identified wrappers, preserving
    -- any intervening add-on's wrapper. Normal startup reaches this before those modules run.
    local previous = BloodOverhaul
    if previous and not previous.Packaged then
        for name in pairs(previous.ConVars or {}) do
            if cvars.RemoveChangeCallback then cvars.RemoveChangeCallback("bloodoverhaul_" .. name, "bloodoverhaul") end
        end
        hook.Remove("InitPostEntity", "bloodoverhaul_apply")
        hook.Remove("AddToolMenuCategories", "bloodoverhaul_menu")
        hook.Remove("PopulateToolMenu", "bloodoverhaul_menu")
        local function legacy_wrapper(fn)
            local ok, info = pcall(debug.getinfo, fn, "S")
            local path = ok and info and (info.source or ""):gsub("\\", "/"):lower()
            return path and path:sub(-#"/bloodoverhaul/cl_core.lua") == "/bloodoverhaul/cl_core.lua"
        end
        if previous.OrigDecalEx and legacy_wrapper(util.DecalEx) then util.DecalEx = previous.OrigDecalEx end
        local emitter = FindMetaTable("CLuaEmitter")
        if emitter and previous.OrigEmitterAdd and legacy_wrapper(emitter.Add) then emitter.Add = previous.OrigEmitterAdd end
    end
    BloodOverhaul = { Packaged = true, Shapes = include("nlblood/shapes.lua") }
    include("nlblood/schemes.lua")
    include("nativeloader/blood_core.lua")
    include("nativeloader/blood_impacts.lua")
end
