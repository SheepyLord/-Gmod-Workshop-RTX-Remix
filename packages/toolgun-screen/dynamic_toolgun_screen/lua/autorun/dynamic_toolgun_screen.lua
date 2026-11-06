--[[
	Dynamic Toolgun Screen
	Turns the tool gun's static mini screen into a live, customizable display.

	This file only bootstraps the addon: the server sends the client files and the language files,
	the client loads them. Everything that draws or reads settings is client-side.
]]

local ROOT = "dynamic_toolgun_screen/"

local CLIENT_FILES = {
	"cl_core.lua",
	"cl_i18n.lua",
	"cl_draw.lua",
	"cl_tokens.lua",
	"cl_themes.lua",
	"layouts/cl_pocketpc.lua",
	"layouts/cl_terminal.lua",
	"layouts/cl_minimal.lua",
	"cl_render.lua",
	"cl_features.lua",
	"cl_inspect.lua",
	"cl_compat.lua",
	"cl_menu.lua",
}

-- Server owners can stop clients from rendering the extra camera view used by the "live camera" backgrounds.
CreateConVar( "dts_sv_allow_camera", "1", { FCVAR_ARCHIVE, FCVAR_REPLICATED }, "Allow players to use the live camera backgrounds of the Dynamic Toolgun Screen (0 = off)." )

if ( SERVER ) then

	util.AddNetworkString( "DTScreen_Track" )

	for _, f in ipairs( CLIENT_FILES ) do
		AddCSLuaFile( ROOT .. f )
	end

	-- every language file goes to every client; cl_i18n.lua loads the one it needs
	for _, f in ipairs( file.Find( ROOT .. "lang/*.lua", "LUA" ) ) do
		AddCSLuaFile( ROOT .. "lang/" .. f )
	end

	-- the "Original screen" background picture, for players who join without the addon (Lua is sent
	-- anyway; without the picture their screen falls back to the "Original photo" background)
	resource.AddSingleFile( "materials/dynamic_toolgun_screen/screen_original.png" )

	return

end

for _, f in ipairs( CLIENT_FILES ) do
	include( ROOT .. f )
end

DTScreen.MigrateSettings()
DTScreen.Loaded = true
hook.Run( "DTScreen_Loaded", DTScreen )
