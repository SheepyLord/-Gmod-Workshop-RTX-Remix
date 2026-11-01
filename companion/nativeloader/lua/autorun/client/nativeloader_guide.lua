-- The in-game RTX Remix guide (nativeloader_guide): how to use the RTX package and Remix, and how to
-- find out what went wrong. Opens once by itself on the first RTX session, then from the console or
-- the RTX Remix tab's "Start here". Images are in materials/nativeloader/guide/; a missing image is
-- left out. Its text is translated (nativeloader/i18n.lua). Documented in nativeloader_guide.lua.md beside this file.
local SHOWN = "nativeloader_companion/guide_shown.txt"
local i18n = include("nativeloader/i18n.lua")
local L, N = i18n.L, i18n.N

-- Workshop updates can reach an older winmm.dll. Its config parser rejects unknown R6 keys.
local function r6_loader()
    local ok, status = pcall(function()
        local body = file.Read("native-loader/status.json", "DATA")
        return body and util.JSONToTable(body)
    end)
    return ok and type(status) == "table" and status.schema == 1 and
        type(status.activation) == "table" and type(status.activation.performance_tier) == "table"
end

local R6_CONFIG = [[{
  "schema": 1,
  "allow": {
    "workshop": ["3829070317"]
  },
  "remix": {
    "performance_tier": "low"
  },
  "diagnostics": {
    "gpu_crash_dumps": "off"
  }
}]]

local PAGES = {
    { N("Welcome"), "icon16/star.png", {
        { "image", "nativeloader/guide/rtx_on.jpg" },
        { "h", N("RTX Remix is running") },
        { "p", N("Garry's Mod is path traced by NVIDIA RTX Remix. The native loader (bin\\win64\\winmm.dll) put the RTX package from the Workshop in place and started Remix before the game made its renderer.") },
        { "p", N("Everything RTX is in the spawn menu's RTX Remix tab: the settings of the RTX add-ons, the common Remix settings, and this guide.") },
        { "h", N("Turning RTX off or on") },
        { "p", N("RTX off for a while, without uninstalling: in native-loader\\config.json add  \"remix\": { \"enabled\": false }  and start the game again. The game is then plain Garry's Mod; the RTX add-ons are left out too.") },
        { "p", N("The game runs in a borderless window as large as your screen. Exclusive fullscreen crashes Remix. For another size, put -w <width> -h <height> in the game's launch options in Steam.") },
    } },
    { N("Remix menu"), "icon16/application_view_list.png", {
        { "image", "nativeloader/guide/remix_menu.jpg" },
        { "h", N("Alt+X opens Remix's own menu") },
        { "p", N("The simple menu has the graphics presets, DLSS and frame generation. The developer menu (Developer Settings) has every option.") },
        { "h", N("Making changes stick") },
        { "p", N("1. Set Graphics Preset to Custom first. Any other preset is applied again at every start and replaces the single settings you changed.") },
        { "p", N("2. Change what you want.") },
        { "p", N("3. Save: graphics settings with 'User Settings (user.conf): Save', developer settings with 'Remix Config (rtx.conf): Save'. Both files are in the Garry's Mod folder and win over the package's defaults.") },
        { "p", N("Do not press 'Migrate developer settings to rtx.conf'. Before saving, check 'View Changes': the RTX fixes set some values for the current map through the Remix API, and saving them would apply them to every map.") },
    } },
    { N("Settings"), "icon16/cog.png", {
        { "h", N("Defaults from the original RTX install") },
        { "p", N("Remix starts with the settings of the original RTX install (its rtx.conf, dxvk.conf and user.conf). The RTX add-ons' own settings got the same install's values once, where you had not changed them yet.") },
        { "p", N("RTX Remix tab > Start here > 'Use the classic RTX settings' (console: nativeloader_rtx_defaults) applies all of those again, also over values you changed.") },
        { "h", N("Common Remix settings") },
        { "p", N("RTX Remix tab > Remix settings changes common settings for this session. Save them in Alt+X to keep them. Reapplying this panel's choices at launch is off by default; enable it only to override Remix's saved settings. Select a numeric override before editing it.") },
        { "p", N("Fog: Remix's own volumetric presets, from light mist to heavy fog, dust and smoke. A preset replaces the weather's fog until you set it back to '(leave to Remix)'.") },
        { "h", N("Sky and weather") },
        { "p", N("RTX Remix tab > Sky and weather. The physical sky has a real sun, clouds, stars and a moon that light the map. By default the sun stands where the map's own sun is; move the time of day or the sun's direction to choose your own, or let the time pass.") },
        { "p", N("The moon has the real Moon's face and goes through its phases, lit from the sun's side. The night sky is a detailed image of stars, a galaxy and nebulae that turns with the hour and the season; 'Night sky' switches to simulated stars.") },
        { "p", N("Eclipse: a lunar eclipse turns the full moon copper red in Earth's shadow; a solar eclipse covers the sun, darkens the day and shows the corona and the stars. 'Eclipse progress' moves from first contact to the middle.") },
        { "p", N("Weather: twelve kinds, from clear to thunderstorm, snow and sandstorm, changing over the time you choose. Console: nativeloader_sky_time sunset (or noon, night, 18:30 ...), nativeloader_sky_status.") },
    } },
    { N("Lights"), "icon16/lightbulb.png", {
        { "h", N("Flashlight") },
        { "p", N("The flashlight key gives a path-traced flashlight. Its brightness, cone and offsets are under RTX Remix tab > Lights > Flashlight.") },
        { "h", N("Map lights") },
        { "p", N("By default the map's own lights are lit by Remix from the game's lights (the 'light updater'). 'Disable Remix API Lights' under Rendering > Base Options switches between that and converting every map light into a Remix light.") },
        { "h", N("Advanced MMD Animation Player") },
        { "p", N("Its flashlight becomes a Remix light when the RTX fixes' module reached the Remix API (nativeloader_status says 'Remix API: ready'). The light's strength grows with its radius: a radius of 1 is almost invisible; 20 to 30 is a good start.") },
    } },
    { N("Memory and stability"), "icon16/chart_bar.png", {
        { "h", N("For 8 GB GPUs and 16 GB of RAM") },
        { "p", N("Use a system-managed Windows page file on a drive with at least 30 GB free. Close browsers and stop OBS recording before playing. In Task Manager > Performance > Memory, watch Committed: the first number is in use, the second is the limit. If they are close, close other apps or use fewer heavy models.") },
        { "p", N("Turn frame generation off in Alt+X and use 'User Settings (user.conf): Save' so a saved value does not return next start. Keep Garry's Mod's texture detail at its highest: lowering it changes the textures Remix hashes and can break replacement matching. Use fewer heavy characters to reduce memory pressure.") },
        { "p", N("Update bin\\win64\\winmm.dll to loader 0.11.0 or later before changing performance tiers or GPU-crash diagnostics. Older loaders reject these configuration keys and start without RTX."), "legacy" },
        { "h", N("Performance tiers"), "r6" },
        { "p", N("The loader chooses high, medium or low from the NVIDIA GPU's model and VRAM; recognized laptop models step down one class tier. High keeps the classic defaults. Medium and low reduce rendering work and memory use when their tier layer is available; the package's low layer also uses smaller night-sky textures. Your saved Remix settings can override these defaults."), "r6" },
        { "p", N("RTX Remix tab > Start here shows the tier and GPU, or the reason a tier layer was not applied. To override it, use auto, high, medium or low for remix.performance_tier in native-loader\\config.json, then restart Garry's Mod. Loader tiers are separate from Graphics Preset in Alt+X."), "r6" },
        { "p", N("Complete minimal config.json example for the shipped allowlist, with the low tier and GPU dumps off. If you customized the file, keep your allow entries and other settings when adding these objects. Invalid JSON turns RTX off."), "r6" },
        { "code", R6_CONFIG, "r6" },
        { "h", N("Local memory readings") },
        { "p", N("Console: rtx_vram_stats prints VRAM totals and categories when the RTX fixes are available. The companion records garrysmod\\data\\native-loader\\vram.csv and vram.previous.csv every 30 seconds. After three failed API calls it stops for this map; toggle nativeloader_vram_telemetry off (0) and on (1) to retry. These files stay local.") },
        { "p", N("This loader (0.11.0 or later) also records native-loader\\logs\\memory.csv with process RAM and system commit readings."), "r6" },
        { "h", N("After a crash") },
        { "p", N("Before restarting, copy status.json and session.json from garrysmod\\data\\native-loader\\, both vram CSV files and rtx-remix\\logs\\. The next start rewrites both JSON reports and can overwrite runtime logs; the session evidence folder does not keep these JSON reports.") },
        { "p", N("At the next start, this loader (0.11.0 or later) copies available previous-session logs, dumps and memory history into native-loader\\logs\\sessions\\ (last five sessions, at most 200 MB). Originals stay in place; these copies are never uploaded. Copy the relevant session folder before it rotates. If no folder was kept, preserve crashes\\, native-loader\\logs\\gpu\\ and memory CSV files manually."), "r6" },
        { "p", N("This older loader does not collect a session evidence folder. Copy rtx-remix\\logs\\ and matching crashes\\ dumps before restarting the game; update bin\\win64\\winmm.dll to loader 0.11.0 or later for evidence collection."), "legacy" },
        { "p", N("Send the saved logs and JSON reports, both vram CSV files and any retained session folder. Add copies of root rtx.conf, dxvk.conf and user.conf, plus garrysmod\\console.log if available. Include the map, models/mods, steps before the crash, local time and time zone, frame rate and Task Manager Committed reading.") },
        { "p", N("Keep matching original dumps from crashes\\ or native-loader\\logs\\gpu\\ and shaderDebugInfo\\*.nvdbg if no session folder kept them. For a GPU hang, include nearby Event Viewer System events from Display or nvlddmkm and any matching Windows LiveKernelReports\\WATCHDOG dump. Dumps can contain process memory; review what you share.") },
        { "p", N("For a requested GPU-crash reproduction on this loader (0.11.0 or later), change diagnostics.gpu_crash_dumps from \"off\" to \"next_start\" in the complete config.json example above and restart. The config value stays \"next_start\"; to request another start, delete native-loader\\remix\\gpu-crash-dumps.used. Diagnostics add overhead; a GPU dump is created only when supported diagnostics capture a crash."), "r6" },
    } },
    { N("Troubleshooting"), "icon16/wrench.png", {
        { "h", N("First look") },
        { "p", N("Console: nativeloader_status. It prints what the loader deployed and activated, the session's patches, and whether the Remix API is ready.") },
        { "h", N("Files to look at") },
        { "p", N("native-loader\\logs\\loader.log - what the loader did at this start.") },
        { "p", N("garrysmod\\data\\native-loader\\status.json and session.json - the same as data.") },
        { "p", N("rtx-remix\\logs\\remix-dxvk.log - Remix's own log, with every effective setting near the top.") },
        { "h", N("Common problems") },
        { "p", N("The game closes during start-up: check rtx-remix\\logs for 'last_crash' and the end of remix-dxvk.log. Keep the game windowed (it is by default).") },
        { "p", N("An add-on draws over the picture or undoes RTX settings: the console names it ('[nativeloader] kept ...'). nativeloader_guard 0 turns the protection off to compare.") },
        { "p", N("Low frame rate: choose a lower graphics preset or DLSS quality. Frame generation is off by default for stability.") },
        { "p", N("'Couldn't mount file' for the RTX Workshop item is expected: the loader deploys it instead of the game.") },
        { "p", N("Settings come back after a restart: set the preset to Custom and Save (see 'Remix menu').") },
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

local function open_guide(selected)
    local r6 = r6_loader()
    local frame = vgui.Create("DFrame")
    frame:SetTitle(L("RTX Remix guide"))
    frame:SetSize(math.min(960, ScrW() - 40), math.min(720, ScrH() - 40))
    frame:Center()
    frame:MakePopup()
    local sheet = frame:Add("DPropertySheet")
    sheet:Dock(FILL)
    for _, page in ipairs(PAGES) do
        local scroll = vgui.Create("DScrollPanel", sheet)
        for _, item in ipairs(page[3]) do
            if not item[3] or (item[3] == "r6" and r6) or (item[3] == "legacy" and not r6) then
                if item[1] == "image" then add_image(scroll, item[2])
                elseif item[1] == "h" then add_text(scroll, L(item[2]), "DermaLarge", Color(118, 185, 0))
                elseif item[1] == "code" then add_text(scroll, item[2], "DermaDefault")
                else add_text(scroll, L(item[2]), "DermaDefault") end
            end
        end
        local added = sheet:AddSheet(L(page[1]), scroll, page[2])
        if page[1] == selected then sheet:SetActiveTab(added.Tab) end
    end
end

concommand.Add("nativeloader_guide", function() open_guide() end, nil, "Opens the RTX Remix guide")
concommand.Add("nativeloader_stability_guide", function() open_guide("Memory and stability") end, nil,
    "Opens the RTX Remix guide's memory and stability page")

-- Once, on the first RTX session: open the guide a moment after the player has spawned.
hook.Add("InitPostEntity", "nativeloader_guide", function()
    if file.Exists(SHOWN, "DATA") then return end
    file.CreateDir("nativeloader_companion")
    file.Write(SHOWN, os.date("!%Y-%m-%dT%H:%M:%SZ") .. "\n")
    timer.Simple(8, open_guide)
end)
