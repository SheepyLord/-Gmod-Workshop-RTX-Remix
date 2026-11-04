-- Sends the companion's translations to clients: the RTX Remix tab, the guide and the update notice
-- include them (nativeloader/i18n.lua). The guide's pages go with them. Documented in
-- nativeloader_i18n.lua.md beside this file.
if SERVER then
    AddCSLuaFile("nativeloader/i18n.lua")
    if file.Exists("nativeloader/i18n_data.lua", "LUA") then AddCSLuaFile("nativeloader/i18n_data.lua") end
    if file.Exists("nativeloader/guide_pages.lua", "LUA") then AddCSLuaFile("nativeloader/guide_pages.lua") end
    -- The rules the client controllers include (eye whites, painted shadows, solid hair).
    for _, name in ipairs({"eye_white_names", "eye_white_vtf", "painted_shadows", "solid_hair"}) do
        if file.Exists("nativeloader/" .. name .. ".lua", "LUA") then AddCSLuaFile("nativeloader/" .. name .. ".lua") end
    end
    util.AddNetworkString("nativeloader_localized_chat")
    function NATIVELOADER_LOCALIZED_CHAT(player, text, arguments)
        net.Start("nativeloader_localized_chat")
        net.WriteString(text)
        net.WriteTable(arguments or {})
        net.Send(player)
    end
else
    local i18n = include("nativeloader/i18n.lua")
    net.Receive("nativeloader_localized_chat", function()
        local text, arguments = net.ReadString(), net.ReadTable()
        local ok, message = pcall(string.format, i18n.A(text), unpack(arguments))
        if ok then chat.AddText(message) end
    end)
end
