-- The in-game RTX Remix guide (nativeloader_guide): how to use the RTX package and Remix, and how to
-- find out what went wrong. Opens once by itself on the first RTX session, then from the console or
-- the RTX Remix tab's "Start here". Images are in materials/nativeloader/guide/; a missing image is
-- left out. Documented in nativeloader_guide.lua.md beside this file.
local SHOWN = "nativeloader_companion/guide_shown.txt"

local PAGES = {
    { "Welcome", "icon16/star.png", {
        { "image", "nativeloader/guide/rtx_on.jpg" },
        { "h", "RTX Remix is running" },
        { "p", "Garry's Mod is path traced by NVIDIA RTX Remix. The native loader (bin\\win64\\winmm.dll) put the RTX package from the Workshop in place and started Remix before the game made its renderer." },
        { "p", "Everything RTX is in the spawn menu's RTX Remix tab: the settings of the RTX add-ons, the common Remix settings, and this guide." },
        { "h", "Turning RTX off or on" },
        { "p", "RTX off for a while, without uninstalling: in native-loader\\config.json add  \"remix\": { \"enabled\": false }  and start the game again. The game is then plain Garry's Mod; the RTX add-ons are left out too." },
        { "p", "The game runs in a borderless window as large as your screen. Exclusive fullscreen crashes Remix. For another size, put -w <width> -h <height> in the game's launch options in Steam." },
    } },
    { "Remix menu", "icon16/application_view_list.png", {
        { "image", "nativeloader/guide/remix_menu.jpg" },
        { "h", "Alt+X opens Remix's own menu" },
        { "p", "The simple menu has the graphics presets, DLSS and frame generation. The developer menu (Developer Settings) has every option." },
        { "h", "Making changes stick" },
        { "p", "1. Set Graphics Preset to Custom first. Any other preset is applied again at every start and replaces the single settings you changed." },
        { "p", "2. Change what you want." },
        { "p", "3. Save: graphics settings with 'User Settings (user.conf): Save', developer settings with 'Remix Config (rtx.conf): Save'. Both files are in the Garry's Mod folder and win over the package's defaults." },
        { "p", "Do not press 'Migrate N Developer Settings to rtx.conf' and check 'View Changes' before saving: the RTX fixes set some values for the current map through the Remix API, and saving them would apply them to every map." },
    } },
    { "Settings", "icon16/cog.png", {
        { "h", "Defaults from the original RTX install" },
        { "p", "Remix starts with the settings of the original RTX install (its rtx.conf, dxvk.conf and user.conf). The RTX add-ons' own settings got the same install's values once, where you had not changed them yet." },
        { "p", "RTX Remix tab > Start here > 'Use the classic RTX settings' (console: nativeloader_rtx_defaults) applies all of those again, also over values you changed." },
        { "h", "Common Remix settings" },
        { "p", "RTX Remix tab > Remix settings: preset, upscaler, DLSS quality, frame generation, indirect lighting, bounces, fog, sky, sun and clouds. A value set there is kept and applied at every start; '(leave to Remix)' hands it back to Remix's files." },
    } },
    { "Lights", "icon16/lightbulb.png", {
        { "h", "Flashlight" },
        { "p", "The flashlight key gives a path-traced flashlight. Its brightness, cone and offsets are under RTX Remix tab > Lights > Flashlight." },
        { "h", "Map lights" },
        { "p", "By default the map's own lights are lit by Remix from the game's lights (the 'light updater'). 'Disable Remix API Lights' under Rendering > Base Options switches between that and converting every map light into a Remix light." },
        { "h", "Advanced MMD Animation Player" },
        { "p", "Its flashlight becomes a Remix light when the RTX fixes' module reached the Remix API (nativeloader_status says 'Remix API: ready'). The light's strength grows with its radius: a radius of 1 is almost invisible; 20 to 30 is a good start." },
    } },
    { "Troubleshooting", "icon16/wrench.png", {
        { "h", "First look" },
        { "p", "Console: nativeloader_status. It prints what the loader deployed and activated, the session's patches, and whether the Remix API is ready." },
        { "h", "Files to look at" },
        { "p", "native-loader\\logs\\loader.log - what the loader did at this start." },
        { "p", "garrysmod\\data\\native-loader\\status.json and session.json - the same as data." },
        { "p", "rtx-remix\\logs\\remix-dxvk.log - Remix's own log, with every effective setting near the top." },
        { "h", "Common problems" },
        { "p", "The game closes during start-up: check rtx-remix\\logs for 'last_crash' and the end of remix-dxvk.log. Keep the game windowed (it is by default)." },
        { "p", "An add-on draws over the picture or undoes RTX settings: the console names it ('[nativeloader] kept ...'). nativeloader_guard 0 turns the protection off to compare." },
        { "p", "Low frame rate: choose a lower preset or DLSS quality. Frame generation needs an RTX 40 or newer GPU." },
        { "p", "'Couldn't mount file' for the RTX Workshop item is expected: the loader deploys it instead of the game." },
        { "p", "Settings come back after a restart: set the preset to Custom and Save (see 'Remix menu')." },
    } },
}

local function add_text(parent, text, font, color)
    local label = parent:Add("DLabel")
    label:Dock(TOP)
    label:DockMargin(8, font == "DermaLarge" and 10 or 2, 8, 2)
    label:SetFont(font)
    label:SetTextColor(color or Color(230, 230, 230))
    label:SetText(text)
    label:SetWrap(true)
    label:SetAutoStretchVertical(true)
end

local function add_image(parent, path)
    if not file.Exists("materials/" .. path, "GAME") then return end
    local material = Material(path, "smooth")
    if material:IsError() then return end
    local image = parent:Add("DImage")
    image:Dock(TOP)
    image:DockMargin(8, 8, 8, 4)
    image:SetMaterial(material)
    image:SetKeepAspect(true)
    image:SetTall(300)
end

local function open_guide()
    local frame = vgui.Create("DFrame")
    frame:SetTitle("RTX Remix guide")
    frame:SetSize(math.min(960, ScrW() - 40), math.min(720, ScrH() - 40))
    frame:Center()
    frame:MakePopup()
    local sheet = frame:Add("DPropertySheet")
    sheet:Dock(FILL)
    for _, page in ipairs(PAGES) do
        local scroll = vgui.Create("DScrollPanel", sheet)
        for _, item in ipairs(page[3]) do
            if item[1] == "image" then add_image(scroll, item[2])
            elseif item[1] == "h" then add_text(scroll, item[2], "DermaLarge", Color(118, 185, 0))
            else add_text(scroll, item[2], "DermaDefault") end
        end
        sheet:AddSheet(page[1], scroll, page[2])
    end
end

concommand.Add("nativeloader_guide", open_guide, nil, "Opens the RTX Remix guide")

-- Once, on the first RTX session: open the guide a moment after the player has spawned.
hook.Add("InitPostEntity", "nativeloader_guide", function()
    if file.Exists(SHOWN, "DATA") then return end
    file.CreateDir("nativeloader_companion")
    file.Write(SHOWN, os.date("!%Y-%m-%dT%H:%M:%SZ") .. "\n")
    timer.Simple(8, open_guide)
end)
