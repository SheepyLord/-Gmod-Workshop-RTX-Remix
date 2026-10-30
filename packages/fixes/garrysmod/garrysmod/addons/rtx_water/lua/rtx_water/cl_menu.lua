-- Localized by the native-loader companion when bundled; standalone use keeps the English.
local bundle_i18n = CLIENT and file.Exists("nativeloader/i18n.lua", "LUA")
    and include("nativeloader/i18n.lua") or nil
local NL = bundle_i18n and bundle_i18n.A or function(text) return text end
local NP = bundle_i18n and bundle_i18n.P or function(text) return text end
local function NN(text) return text end
-- RTX Water settings panel: Spawn menu > Utilities > RTX > RTX Water.

local W = RTXWater
local D = RTXWater_Data

local function combo(panel, label, convar, choices)
	local box = panel:ComboBox(label)
	local current = GetConVar(convar):GetString()
	for _, c in ipairs(choices) do
		box:AddChoice(NL(c[1]), c[2], c[2] == current)
	end
	box.OnSelect = function(_, _, _, data) RunConsoleCommand(convar, data) end
	return box
end

local function build(panel)
	panel:ClearControls()
	panel:Help(NL("Path-traced water for RTX Remix on any map: water type, waves, and the waves players, objects and bullets make in it."))
	panel:CheckBox(NL("Enable RTX Water"), "rtx_water_enable")

	local types = { { NL("Auto (map default)"), "auto" } }
	for _, id in ipairs(D.order.types) do types[#types + 1] = { D.types[id].label, id } end
	combo(panel, NL("Water type"), "rtx_water_type", types)

	local waves = { { NL("Auto (map default)"), "auto" } }
	for _, id in ipairs(D.order.waves) do waves[#waves + 1] = { D.waves[id].label, id } end
	combo(panel, NL("Waves"), "rtx_water_waves", waves)
	panel:NumSlider(NL("Wave strength"), "rtx_water_wave_strength", 0, 3, 2)
	panel:NumSlider(NL("Wave speed"), "rtx_water_wave_speed", 0, 5, 2)
	panel:NumSlider(NL("Wave direction"), "rtx_water_wave_direction", 0, 360, 0)
	panel:NumSlider(NL("Wave size"), "rtx_water_wave_scale", 0.25, 4, 2)

	panel:CheckBox(NL("Waves from players, NPCs and objects"), "rtx_water_interaction")
	panel:CheckBox(NL("Bullet impacts make waves"), "rtx_water_bullets")
	panel:NumSlider(NL("How hard bodies push the water"), "rtx_water_interaction_strength", 0, 3, 2)
	panel:NumSlider(NL("Wave reach (how far waves travel before they die out)"), "rtx_water_interaction_reach", 0.25, 4, 2)
	panel:CheckBox(NL("Splashes: drops, sheets and jets thrown up by bodies and bullets"), "rtx_water_splashes")
	panel:NumSlider(NL("Splash strength"), "rtx_water_splash_strength", 0, 3, 2)
	panel:NumSlider(NL("Splash randomness (0 = the same every time)"), "rtx_water_splash_randomness", 0, 1, 2)
	panel:NumSlider(NL("Maximum airborne droplets"), "rtx_water_splash_drops", 0, 1000, 0)
	combo(panel, NL("Wave detail"), "rtx_water_interaction_quality", {
		{ NL("Low"), "1" }, { NL("Medium"), "2" }, { NL("High"), "3" },
	})
	panel:NumSlider(NL("Wave mesh updates per second (0 = every frame)"), "rtx_water_interaction_rate", 0, 120, 0)
	panel:CheckBox(NL("Draw the surface with RTX Water (off: the map's own faces, no waves from interaction)"), "rtx_water_mesh")
	panel:CheckBox(NL("Use the native core when installed (fastest)"), "rtx_water_native")

	panel:Help(NL("Custom water look (native core only):"))
	panel:CheckBox(NL("Use a custom colour and clarity"), "rtx_water_custom")
	local mixer = vgui.Create("DColorMixer", panel)
	mixer:SetPalette(false)
	mixer:SetAlphaBar(false)
	mixer:SetTall(140)
	local c = string.Explode(" ", GetConVar("rtx_water_color"):GetString())
	mixer:SetColor(Color((tonumber(c[1]) or 0.6) * 255, (tonumber(c[2]) or 0.9) * 255, (tonumber(c[3]) or 1) * 255))
	mixer.ValueChanged = function(_, col)
		timer.Create("RTXWater_Color", 0.2, 1, function()
			RunConsoleCommand("rtx_water_color", string.format("%.3f %.3f %.3f", col.r / 255, col.g / 255, col.b / 255))
		end)
	end
	panel:AddItem(mixer)
	panel:NumSlider(NL("Clarity (units for that colour)"), "rtx_water_clarity", 5, 2000, 0)
	panel:NumSlider(NL("Refraction index"), "rtx_water_ior", 1, 2, 3)

	local status = panel:Help("")
	local function refresh()
		if not IsValid(status) then return end
		local s = W.state
		if not s then
			status:SetText(W.Available() and NL("Not active on this map.") or NL("RTX Remix API not available."))
		else
			local st = W.Ripples.stats or {}
			local core = s.native and NL("native core") or (NL("Lua meshes") .. (W.Native.error and NL(" (native core: ") .. W.Native.error .. ")" or ""))
			status:SetText(string.format(NL("%s, %s; %s. %s: %d, %d tiles, %d vertices, %.2f ms per update%s. Splash drops: %d."),
				NL(D.types[s.type].label), NL(D.waves[s.waves].label), core,
				s.native and NL("Bodies in the water") or NL("Ripples"), W.Ripples.Count(),
				st.tiles or 0, st.verts or 0, st.ms or 0, s.native and NL(" (worker thread)") or "", W.Splash.Count()))
		end
	end
	refresh()
	timer.Create("RTXWater_MenuStatus", 1, 0, function()
		if not IsValid(status) then timer.Remove("RTXWater_MenuStatus") return end
		refresh()
	end)

	panel:Button(NL("Reset settings"), "rtx_water_reset")
	panel:Button(NL("Rebuild water for this map"), "rtx_water_reload")
end

hook.Add("PopulateToolMenu", "RTXWater_Menu", function()
	spawnmenu.AddToolMenuOption("Utilities", "RTX", "RTXWater", NL("RTX Water"), "", "", build)
end)
