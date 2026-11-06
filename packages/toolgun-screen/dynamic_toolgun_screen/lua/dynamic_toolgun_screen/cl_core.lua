--[[
	Dynamic Toolgun Screen - core
	Namespace, settings registry, registries for layouts/themes/tokens and small shared helpers.
]]

DTScreen = DTScreen or {}
local DTS = DTScreen

DTS.Version = "1.3.1"

DTS.Settings = DTS.Settings or {}
DTS.SettingOrder = DTS.SettingOrder or {}
DTS.Layouts = DTS.Layouts or {}
DTS.LayoutOrder = DTS.LayoutOrder or {}
DTS.Themes = DTS.Themes or {}
DTS.ThemeOrder = DTS.ThemeOrder or {}
DTS.Tokens = DTS.Tokens or {}
DTS.TokenOrder = DTS.TokenOrder or {}

--[[---------------------------------------------------------
	Settings
	Every user setting is a client ConVar called "dts_<name>". The registry keeps defaults so
	presets, reset, export and import all work from one list.
-----------------------------------------------------------]]

local function OnSettingChanged()
	DTS.Dirty = true
	DTS.Broken = nil -- a setting change gives a screen that kept failing another chance
end

function DTS.AddSetting( name, default, help, kind )

	local convar = "dts_" .. name
	default = tostring( default )

	if ( !DTS.Settings[ name ] ) then
		table.insert( DTS.SettingOrder, name )
	end

	local cvar = GetConVar( convar ) or CreateClientConVar( convar, default, true, false, help or "" )

	DTS.Settings[ name ] = {
		name = name,
		convar = convar,
		default = default,
		help = help or "",
		kind = kind or "string",
		cvar = cvar
	}

	cvars.AddChangeCallback( convar, OnSettingChanged, "DTScreen" )

	return cvar

end

function DTS.GetString( name )
	local s = DTS.Settings[ name ]
	return s and s.cvar:GetString() or ""
end

function DTS.GetFloat( name )
	local s = DTS.Settings[ name ]
	return s and s.cvar:GetFloat() or 0
end

function DTS.GetInt( name )
	local s = DTS.Settings[ name ]
	return s and s.cvar:GetInt() or 0
end

function DTS.GetBool( name )
	local s = DTS.Settings[ name ]
	return s and s.cvar:GetBool() or false
end

function DTS.SetSetting( name, value )
	local s = DTS.Settings[ name ]
	if ( !s ) then return end
	RunConsoleCommand( s.convar, tostring( value ) )
end

function DTS.ResetSettings( filter )

	for _, name in ipairs( DTS.SettingOrder ) do
		local s = DTS.Settings[ name ]
		if ( ( !filter or filter( s ) ) and s.cvar:GetString() != s.default ) then
			RunConsoleCommand( s.convar, s.default )
		end
	end

end

-- name -> default, the format ControlPanel:ToolPresets wants
function DTS.GetPresetConVars()

	local out = {}
	for _, name in ipairs( DTS.SettingOrder ) do
		local s = DTS.Settings[ name ]
		out[ s.convar ] = s.default
	end
	return out

end

-- Settings that belong to the player rather than to the look: not exported, and an import leaves them alone.
local PERSONAL = { language = true, inspect_key = true }

-- Settings travel as "DTS1:<base64 json>" holding only the values that differ from the defaults.
function DTS.ExportSettings()

	local out = {}
	for _, name in ipairs( DTS.SettingOrder ) do
		local s = DTS.Settings[ name ]
		local value = s.cvar:GetString()
		if ( value != s.default and !PERSONAL[ name ] ) then out[ name ] = value end
	end

	return "DTS1:" .. util.Base64Encode( util.TableToJSON( out ), true )

end

function DTS.ImportSettings( str )

	str = string.Trim( str or "" )

	local payload = string.match( str, "^DTS1:(.+)$" )
	if ( !payload ) then return false, DTS.L( "import.not_ours" ) end

	local json = util.Base64Decode( payload )
	local data = json and util.JSONToTable( json )
	if ( !istable( data ) ) then return false, DTS.L( "import.damaged" ) end

	-- Only our own settings are touched, everything not in the string goes back to its default
	-- (except the player's own language and inspect key).
	local count = 0
	for _, name in ipairs( DTS.SettingOrder ) do
		local s = DTS.Settings[ name ]
		local value = data[ name ]
		value = ( value != nil ) and tostring( value ) or s.default
		if ( !PERSONAL[ name ] and s.cvar:GetString() != value ) then
			RunConsoleCommand( s.convar, value )
			count = count + 1
		end
	end

	return true, count

end

--[[---------------------------------------------------------
	General settings
-----------------------------------------------------------]]

DTS.AddSetting( "enabled", 1, "Draw the dynamic screen on the tool gun (0 = original screen).", "bool" )
DTS.AddSetting( "layout", "pocketpc", "Screen layout: pocketpc, terminal or minimal.", "layout" )
DTS.AddSetting( "theme", "winmobile", "Colour theme of the screen.", "theme" )
DTS.AddSetting( "background", "auto", "Background: auto, original, art, gradient, camera, rear, image or black.", "background" )
DTS.AddSetting( "bg_image", "", "Material or image used by the 'image' background, e.g. ../data/dts/wallpaper.png", "string" )
DTS.AddSetting( "bg_dim", 0, "Darken the background (0 - 0.9).", "float" )
DTS.AddSetting( "cam_fov", 25, "Field of view of the zoom camera background.", "float" )
DTS.AddSetting( "cam_fps", 20, "How many times per second the camera background is rendered.", "int" )

-- Empty font = automatic: the language picks a font that has its letters (Tahoma, Microsoft YaHei UI, Meiryo UI...).
DTS.AddSetting( "font", "", "Font of the small text on the screen (empty = chosen by the language).", "font" )
DTS.AddSetting( "font_hero", "", "Font of the big text on the screen (empty = chosen by the language).", "font" )
DTS.AddSetting( "font_mono", "", "Font of the Terminal layout (empty = chosen by the language).", "font" )

DTS.AddSetting( "hero_mode", "scroll", "Big text behaviour: scroll (original), auto (scroll only when too long) or fit (shrink to fit).", "string" )
DTS.AddSetting( "hero_speed", 250, "Scroll speed of the big text in pixels per second (original: 250).", "float" )
DTS.AddSetting( "hero_upper", 0, "Show the big text in upper case.", "bool" )

DTS.AddSetting( "clock_24h", "auto", "Clock style: auto (as usual in your language), 1 (24 hour) or 0 (12 hour).", "string" )
DTS.AddSetting( "clock_seconds", 0, "Show seconds on the clock.", "bool" )
DTS.AddSetting( "clock_ampm", 0, "Show AM/PM on the 12 hour clock.", "bool" )
DTS.AddSetting( "clock_blink", 0, "Blink the clock's colon every second.", "bool" )

DTS.AddSetting( "units", "m", "Units for distances and speeds: m (metric), ft (imperial) or hu (Hammer units).", "string" )
DTS.AddSetting( "decimals", 1, "Decimals shown for distances (0 - 3).", "int" )

DTS.AddSetting( "icon_speaker", 1, "Speaker icon in the title bar (game volume and voice chat).", "bool" )
DTS.AddSetting( "icon_signal", 1, "Signal icon in the title bar (connection quality).", "bool" )
DTS.AddSetting( "icon_battery", 1, "Battery icon in the title bar: your device's battery and its percentage while it runs on battery, or a plug while it is plugged in.", "bool" )

DTS.AddSetting( "boot_anim", 1, "Play a short boot animation when the tool gun is taken out.", "bool" )
DTS.AddSetting( "fire_flash", 1, "Flash the screen when the tool gun fires.", "bool" )
DTS.AddSetting( "notifications", 1, "Show game notifications (undo, limits, ...) on the screen.", "bool" )
DTS.AddSetting( "notify_time", 3, "How long notifications stay on the screen, in seconds.", "float" )
DTS.AddSetting( "scanlines", 0, "Strength of the LCD scanline effect (0 - 1).", "float" )
DTS.AddSetting( "vignette", 1, "Darken the edges of the screen slightly.", "bool" )
DTS.AddSetting( "backlight", 1, "Screen brightness (0.2 - 1).", "float" )

DTS.AddSetting( "respect_toolscreens", 1, "Let tools that draw their own screen (e.g. Easy Entity Inspector) keep it.", "bool" )

DTS.AddSetting( "mirror", 0, "Also show the screen on your HUD while holding the tool gun.", "bool" )
DTS.AddSetting( "mirror_corner", "tr", "HUD mirror corner: tl, tr, bl or br.", "string" )
DTS.AddSetting( "mirror_size", 256, "HUD mirror size in pixels.", "int" )
DTS.AddSetting( "mirror_alpha", 235, "HUD mirror opacity (0 - 255).", "int" )

DTS.AddSetting( "refresh", 15, "How many times per second the live values are updated (1 - 60).", "int" )
DTS.AddSetting( "fps", 60, "How many times per second the screen is redrawn (0 = every frame).", "int" )
DTS.AddSetting( "resolution", 256, "Render resolution of the screen: 256 (original) or 512 (sharper on high resolution displays).", "int" )

-- Colour overrides on top of the theme, "" = use the theme. Format: "r g b" or "r g b a".
-- label: English, for the console help; the menu shows the phrase color.<id>.
DTS.ColorOverrides = {
	{ id = "bar", label = "title bar" },
	{ id = "accent", label = "links and highlights" },
	{ id = "hero", label = "big text" },
	{ id = "strip", label = "status line" },
	{ id = "panel", label = "readout panel" },
	{ id = "menu", label = "menu bar" },
	{ id = "term", label = "Terminal text" },
}

for _, c in ipairs( DTS.ColorOverrides ) do
	DTS.AddSetting( "color_" .. c.id, "", "Colour override for: " .. c.label .. " (r g b [a], empty = theme).", "color" )
end

--[[---------------------------------------------------------
	Registries
-----------------------------------------------------------]]

--[[
	Layout table:
		Name, Description
		Background = default background id used when the "background" setting is "auto"
		Slots = { { id, label, default }, ... }   every slot becomes the setting "<layout>_<slot>"
		Draw( self, D, ctx, theme, slots )         slots[id] = evaluated runs, or nil when hidden
]]
function DTS.RegisterLayout( id, layout )

	layout.id = id
	layout.Name = layout.Name or id
	layout.Slots = layout.Slots or {}

	for _, slot in ipairs( layout.Slots ) do
		slot.setting = id .. "_" .. slot.id
		DTS.AddSetting( slot.setting, slot.default or "", "Template of the " .. slot.id .. " line of the " .. id .. " layout.", "template" )
	end

	if ( !DTS.Layouts[ id ] ) then table.insert( DTS.LayoutOrder, id ) end
	DTS.Layouts[ id ] = layout
	DTS.Dirty = true

	return layout

end

function DTS.GetLayout()
	return DTS.Layouts[ DTS.GetString( "layout" ) ] or DTS.Layouts[ "pocketpc" ] or DTS.Layouts[ DTS.LayoutOrder[ 1 ] ]
end

-- Theme table: Name plus colour roles (see cl_themes.lua for the full list).
function DTS.RegisterTheme( id, theme )

	theme.id = id
	theme.Name = theme.Name or id

	if ( !DTS.Themes[ id ] ) then table.insert( DTS.ThemeOrder, id ) end
	DTS.Themes[ id ] = theme
	DTS.Dirty = true

	return theme

end

--[[
	Token: fn( ctx, arg ) returns a string, a number, or a table of runs { { text, highlight }, { icon = "lmb" }, ... }.
	Returning nil or "" counts as empty (see the template rules in cl_tokens.lua).
]]
function DTS.RegisterToken( name, fn, desc, category, example )

	name = string.lower( name )

	if ( !DTS.Tokens[ name ] ) then table.insert( DTS.TokenOrder, name ) end
	DTS.Tokens[ name ] = { name = name, fn = fn, desc = desc or "", category = category or "Other", example = example }
	DTS.Dirty = true

end

--[[---------------------------------------------------------
	Helpers
-----------------------------------------------------------]]

-- The game's own phrase for a key (tool names, NPC names...), or nil if it has none.
function DTS.Phrase( key )

	local phrase = language.GetPhrase( key )
	if ( phrase == key ) then return nil end
	return phrase

end

local reported = {}
function DTS.ErrorOnce( key, msg )

	if ( reported[ key ] ) then return end
	reported[ key ] = true
	ErrorNoHalt( "[Dynamic Toolgun Screen] " .. tostring( msg ) .. "\n" )

end

-- "255 128 0" / "255 128 0 200" -> Color, or nil
function DTS.ParseColor( str )

	if ( !isstring( str ) or str == "" ) then return nil end

	local r, g, b, a = string.match( str, "^%s*(%d+)[%s,]+(%d+)[%s,]+(%d+)[%s,]*(%d*)%s*$" )
	if ( !r ) then return nil end

	return Color( math.Clamp( tonumber( r ), 0, 255 ), math.Clamp( tonumber( g ), 0, 255 ), math.Clamp( tonumber( b ), 0, 255 ), a != "" and math.Clamp( tonumber( a ), 0, 255 ) or 255 )

end

function DTS.ColorToString( col )
	return string.format( "%d %d %d %d", col.r, col.g, col.b, col.a or 255 )
end

--[[---------------------------------------------------------
	Saved settings from older versions. Called after every layout has registered its lines, and does its
	work only once per player (dts_config_version), so a value picked on purpose later, such as Tahoma or
	the 12 hour clock, is never changed back.
	2 (1.1.0): settings still at the English defaults of 1.0.0 move to the new ones, which follow the language.
	3 (1.2.0): "Original artwork" (art) on the Pocket PC layout becomes the new original screen picture;
	           art only ever showed the photo stretched over the screen, which is not what it promised.
-----------------------------------------------------------]]

local CONFIG_VERSION = 3
local configVersion = CreateClientConVar( "dts_config_version", "1", true, false, "Version of the saved Dynamic Toolgun Screen settings (set by the addon)." )

local OLD_DEFAULTS = {
	font = "Tahoma",
	font_hero = "Helvetica",
	font_mono = "Consolas",
	clock_24h = "0",
	pocketpc_title = "{tool_category|Garry's Mod}",
	pocketpc_nav_l = "Back to {tool_prev}",
	pocketpc_r1 = "Props {props}/{props_max}",
	pocketpc_r2 = "{fps} fps  {ping} ms",
	terminal_l1 = "TOOL  **{tool}**",
	terminal_l2 = "AIM   **{aim_what}**",
	terminal_l3 = "CLASS **{ent_class|-}**",
	terminal_l4 = "POS   **{aim_pos}**",
	terminal_l5 = "DIST  **{aim_dist}**  {aim_slope}",
	terminal_l6 = "OWNER **{ent_owner|-}**",
	terminal_l7 = "HP    **{ent_health|-}**",
	terminal_l8 = "TRACK **{track_name|-}** {track_dist}",
}

function DTS.MigrateSettings()

	local from = configVersion:GetInt()
	if ( from >= CONFIG_VERSION ) then return end

	if ( from < 2 ) then
		for name, old in pairs( OLD_DEFAULTS ) do
			local s = DTS.Settings[ name ]
			if ( s and s.default != old and s.cvar:GetString() == old ) then
				RunConsoleCommand( s.convar, s.default )
			end
		end
	end

	if ( from < 3 and DTS.GetString( "background" ) == "art" and DTS.GetString( "layout" ) == "pocketpc" ) then
		RunConsoleCommand( "dts_background", "original" )
	end

	RunConsoleCommand( "dts_config_version", tostring( CONFIG_VERSION ) )

end
