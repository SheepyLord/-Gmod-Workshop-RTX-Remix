-- Packaged autorun adapter. Keep the shipped 1.3.1 initializer verbatim under a private path.
-- A server-delivered standalone may already have initialized the client before verified loading.
if CLIENT and DTScreen and DTScreen.Loaded then return end
if SERVER then
    if NativeLoaderDTSServerRegistered then return end
    NativeLoaderDTSServerRegistered = true
    AddCSLuaFile()
    AddCSLuaFile("dynamic_toolgun_screen/nl_original_init.lua")
end
include("dynamic_toolgun_screen/nl_original_init.lua")
