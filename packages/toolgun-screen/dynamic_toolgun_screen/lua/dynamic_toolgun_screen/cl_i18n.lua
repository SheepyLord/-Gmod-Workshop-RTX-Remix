--[[
	Dynamic Toolgun Screen - languages

	Phrases live in lua/dynamic_toolgun_screen/lang/<code>.lua, one file per language, named like the game's
	own resource/localization folders (zh-cn, pt-br, ...). They are Lua files on purpose: the server sends them
	with the rest of the addon, so every player gets them, also from servers without Workshop downloads.

	en.lua is the source. A phrase missing from a translation falls back to English, so an unfinished
	translation still works. The language follows gmod_language unless dts_language picks one.

	Phrase rules (see TRANSLATING.md):
		{name}        a value filled in by the code, e.g. "Tracking {name}"
		**text**      highlighted on the screen (only in phrases used as screen text)
		tpl.*         default screen lines: templates, so {token}s inside them are live values
		_*            settings of the language itself (name, decimal separator, fonts, clock)
]]

local DTS = DTScreen

local DIR = "dynamic_toolgun_screen/lang/"

local catalogs = {}
-- phrases from DTS.AddPhrases, kept when the files are read again (and over a Lua refresh of this file)
local added = DTS.AddedPhrases or {}
DTS.AddedPhrases = added
local english = {}
local current = {}

local function Load( code )

	local cat = catalogs[ code ]
	if ( cat != nil ) then return cat or nil end
	catalogs[ code ] = false

	local path = DIR .. code .. ".lua"
	local res
	if ( file.Exists( path, "LUA" ) ) then
		local ok
		ok, res = pcall( include, path )
		if ( !ok or !istable( res ) ) then
			DTS.ErrorOnce( "lang." .. code, "Could not load the language file " .. path .. ": " .. tostring( res ) )
			res = nil
		end
	end

	if ( added[ code ] ) then
		res = res or {}
		for k, v in pairs( added[ code ] ) do res[ k ] = v end
	end
	if ( !res ) then return nil end

	catalogs[ code ] = res
	return res

end

-- Installed languages: { { code = "zh-cn", name = "简体中文" }, ... }, English first.
function DTS.Languages()

	local out = {}
	for _, f in ipairs( file.Find( DIR .. "*.lua", "LUA" ) ) do
		local code = string.lower( string.StripExtension( f ) )
		local cat = Load( code )
		if ( cat ) then out[ #out + 1 ] = { code = code, name = cat._name or code } end
	end

	table.sort( out, function( a, b )
		if ( a.code == "en" ) then return b.code != "en" end
		if ( b.code == "en" ) then return false end
		return a.code < b.code
	end )

	return out

end

-- Game languages without their own file use the closest one.
local ALIASES = {
	[ "en-pt" ] = "en", [ "pt-pt" ] = "pt-br", [ "pt" ] = "pt-br", [ "es" ] = "es-es",
	[ "zh" ] = "zh-cn", [ "zh-sg" ] = "zh-cn", [ "zh-hk" ] = "zh-tw", [ "zh-mo" ] = "zh-tw",
}

local function Resolve( code )

	code = string.lower( string.Trim( code or "" ) )
	if ( code == "" ) then return "en" end
	if ( Load( code ) ) then return code end

	local alias = ALIASES[ code ]
	if ( alias and Load( alias ) ) then return alias end

	local base = string.match( code, "^(%a+)" )
	if ( base and Load( base ) ) then return base end

	return "en"

end

function DTS.GameLanguage()
	return string.lower( GetConVarString( "gmod_language" ) or "en" )
end

function DTS.LanguageCode()

	local pick = DTS.GetString( "language" )
	if ( pick == "" or pick == "auto" ) then pick = DTS.GameLanguage() end
	return Resolve( pick )

end

-- Name of a language in that language.
function DTS.LanguageName( code )
	local cat = Load( Resolve( code ) )
	return cat and cat._name or code
end

--[[---------------------------------------------------------
	Lookup
-----------------------------------------------------------]]

local function Lookup( key )

	local s = current[ key ]
	if ( s == nil ) then s = english[ key ] end
	return s

end

function DTS.HasPhrase( key )
	return Lookup( key ) != nil
end

-- The phrase for key with {name} placeholders filled from vars. Unknown keys come back as the key.
function DTS.L( key, vars )

	local s = Lookup( key ) or key
	if ( !vars ) then return s end

	return ( string.gsub( s, "{([%w_]+)}", function( name )
		local v = vars[ name ]
		if ( v == nil ) then return nil end
		return tostring( v )
	end ) )

end

--[[
	A phrase as screen runs: **text** is highlighted, {name} is filled from vars.
	Used for screen text where part of the sentence is highlighted, like "Aiming at **{name}**".
]]
function DTS.LRuns( key, vars )

	local s = Lookup( key ) or key
	local runs, hl, i = {}, false, 1

	local function Add( text )
		if ( text == "" ) then return end
		if ( vars ) then
			text = string.gsub( text, "{([%w_]+)}", function( name )
				local v = vars[ name ]
				if ( v == nil ) then return nil end
				return tostring( v )
			end )
		end
		if ( text != "" ) then runs[ #runs + 1 ] = { text, hl } end
	end

	while ( true ) do
		local a = string.find( s, "**", i, true )
		if ( !a ) then
			Add( string.sub( s, i ) )
			break
		end
		Add( string.sub( s, i, a - 1 ) )
		hl = !hl
		i = a + 2
	end

	return runs

end

-- "#key" strings: our phrases first, then the game's, else unchanged.
function DTS.Localize( str )

	if ( !isstring( str ) ) then return "" end
	if ( string.sub( str, 1, 1 ) != "#" ) then return str end

	local key = string.sub( str, 2 )
	local ours = Lookup( key )
	if ( ours ) then return ours end

	local phrase = language.GetPhrase( key )
	if ( phrase != key ) then return phrase end

	return str

end

-- Let other addons add phrases, e.g. descriptions of their own tokens: DTScreen.AddPhrases( "de", { ... } )
function DTS.AddPhrases( code, phrases )

	code = string.lower( code )
	local mine = added[ code ] or {}
	added[ code ] = mine
	for k, v in pairs( phrases ) do mine[ k ] = v end

	if ( catalogs[ code ] ) then
		for k, v in pairs( phrases ) do catalogs[ code ][ k ] = v end
	else
		catalogs[ code ] = nil -- loads again, with the added phrases
	end
	DTS.Dirty = true

	-- phrases for a language without a file of its own can make it the one to use (DTS.ApplyLanguage
	-- only exists once the whole file has loaded; addons call this later)
	if ( DTS.ApplyLanguage and DTS.LangCode and DTS.LanguageCode() != DTS.LangCode ) then DTS.ApplyLanguage() end

end

--[[---------------------------------------------------------
	Numbers, units and fonts of the active language
-----------------------------------------------------------]]

function DTS.FormatNumber( v, decimals )

	local s = string.format( "%." .. ( decimals or 0 ) .. "f", v )
	if ( string.match( s, "^%-[0%.]+$" ) ) then s = string.sub( s, 2 ) end -- no "-0" or "-0.0"

	local sep = Lookup( "_decimal" ) or "."
	if ( sep != "." ) then s = ( string.gsub( s, "%.", sep ) ) end

	return s

end

-- unit: m, km, ft, mi, hu, kmh, mph, ups, kg, mb
function DTS.FormatUnit( unit, v, decimals )
	return DTS.L( "unit." .. unit, { v = DTS.FormatNumber( v, decimals ) } )
end

local FONT_DEFAULTS = { ui = "Tahoma", hero = "Helvetica", mono = "Consolas" }
local FONT_SETTING = { ui = "font", hero = "font_hero", mono = "font_mono" }

-- The font the language picks for "ui", "hero" or "mono" (one that has its letters).
function DTS.LanguageFont( kind )
	return Lookup( "_font." .. kind ) or FONT_DEFAULTS[ kind ] or "Tahoma"
end

-- Font face for "ui", "hero" or "mono": the setting, or the language's own choice when it is automatic.
function DTS.FontFace( kind )

	local setting = DTS.GetString( FONT_SETTING[ kind ] or "font" )
	if ( setting != "" and setting != "auto" ) then return setting end

	return DTS.LanguageFont( kind )

end

-- Size factor and weight snapping for the language's own fonts (CJK fonts read small and smear at 500/600).
local fontAdjust = {}

function DTS.FontAdjust( face )
	return fontAdjust[ face ]
end

local function RebuildFontAdjust()

	fontAdjust = {}

	local scale = tonumber( Lookup( "_font.scale" ) or "1" ) or 1
	local snap = Lookup( "_font.snap" ) == "1"
	if ( scale == 1 and !snap ) then return end

	for kind in pairs( FONT_DEFAULTS ) do
		local face = Lookup( "_font." .. kind )
		if ( face ) then fontAdjust[ face ] = { scale = scale, snap = snap } end
	end

end

-- Does the language use a 24 hour clock? (dts_clock_24h "auto")
function DTS.LanguageClock24()
	return Lookup( "_clock24" ) == "1"
end

--[[---------------------------------------------------------
	Switching languages
-----------------------------------------------------------]]

-- Phrases the game itself shows: the tool's name and help in the tool menu and HUD, menu entries.
local GAME_PHRASES = {
	[ "tool.dynamic_toolgun_screen.name" ] = "tool.name",
	[ "tool.dynamic_toolgun_screen.desc" ] = "tool.desc",
	[ "tool.dynamic_toolgun_screen.left" ] = "tool.left",
	[ "tool.dynamic_toolgun_screen.right" ] = "tool.right",
	[ "tool.dynamic_toolgun_screen.reload" ] = "tool.reload",
	[ "tool.dynamic_toolgun_screen.0" ] = "tool.desc",
	[ "dts.prop.track" ] = "prop.track",
	[ "dts.menu.category" ] = "menu.category",
	[ "dts.menu.settings" ] = "menu.settings_item",
}

function DTS.ApplyLanguage()

	english = Load( "en" ) or {}

	local code = DTS.LanguageCode()
	current = Load( code ) or english
	DTS.LangCode = code

	RebuildFontAdjust()

	for gameKey, key in pairs( GAME_PHRASES ) do
		language.Add( gameKey, DTS.L( key ) )
	end

	DTS.Dirty = true
	hook.Run( "DTScreen_LanguageChanged", code )

end

-- Same rules as the sandbox's own language switch: never rebuild an open spawn menu or one with unsaved spawnlist edits.
local function RefreshSpawnMenu()

	if ( !IsValid( g_SpawnMenu ) ) then return end

	if ( g_SpawnMenu.m_UnsavedModifications or g_SpawnMenu:IsVisible() ) then
		g_SpawnMenu.m_NeedsLanguageRefresh = true
	else
		RunConsoleCommand( "spawnmenu_reload" )
	end

end

DTS.AddSetting( "language", "", "Language of the screen and its menu: empty = the game's language, or a code such as de, ja, zh-cn.", "language" )

cvars.AddChangeCallback( "dts_language", function()
	DTS.ApplyLanguage()
	RefreshSpawnMenu()
end, "DTScreen_Language" )

-- The sandbox rebuilds the spawn menu on this change; this callback is registered first, so it runs first.
cvars.AddChangeCallback( "gmod_language", function()
	DTS.ApplyLanguage()
end, "DTScreen_Language" )

-- For translators: read the language files again after editing them (singleplayer).
concommand.Add( "dts_language_reload", function()
	catalogs = {}
	DTS.ApplyLanguage()
	RefreshSpawnMenu()
	print( "Dynamic Toolgun Screen: language files read again, active language: " .. DTS.LangCode )
end, nil, "Read the language files of Dynamic Toolgun Screen again, e.g. after editing a translation." )

DTS.ApplyLanguage()
