-- Sends the companion's translations to clients: the RTX Remix tab, the guide and the update notice
-- include them (nativeloader/i18n.lua). Documented in nativeloader_i18n.lua.md beside this file.
if SERVER then
    AddCSLuaFile("nativeloader/i18n.lua")
    if file.Exists("nativeloader/i18n_data.lua", "LUA") then AddCSLuaFile("nativeloader/i18n_data.lua") end
end
