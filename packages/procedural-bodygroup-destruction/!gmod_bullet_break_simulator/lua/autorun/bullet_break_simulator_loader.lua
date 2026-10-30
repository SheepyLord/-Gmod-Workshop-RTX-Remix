-- Procedural Bodygroup Destruction - deterministic realm-aware loader.

BBS = BBS or {}
BBS.Version = "0.20.0-fast-preparation"
BBS.LuaFolder = "bullet_break_simulator"

local PRIORITY = { sh_ = 1, sv_ = 2, cl_ = 3 }

local function LoadFolder( folder )
	local files = file.Find( folder .. "/*.lua", "LUA" ) or {}

	table.sort( files, function( a, b )
		local aPriority = PRIORITY[ string.sub( a, 1, 3 ) ] or 9
		local bPriority = PRIORITY[ string.sub( b, 1, 3 ) ] or 9
		if aPriority ~= bPriority then return aPriority < bPriority end
		return a < b
	end )

	for _, name in ipairs( files ) do
		local path = folder .. "/" .. name
		local prefix = string.sub( name, 1, 3 )

		if prefix == "sv_" then
			if SERVER then include( path ) end
		elseif prefix == "cl_" then
			if SERVER then
				AddCSLuaFile( path )
			else
				include( path )
			end
		else
			AddCSLuaFile( path )
			include( path )
		end
	end
end

LoadFolder( BBS.LuaFolder )

local loadLoggingEnabled = false
if SERVER then
	local logging = GetConVar( "bbs_server_logging" )
	local revision = GetConVar( "bbs_server_settings_revision" )
	loadLoggingEnabled = logging and logging:GetBool()
		and revision and revision:GetInt() >= 1 or false
else
	local logging = GetConVar( "bbs_debug_console" )
	local revision = GetConVar( "bbs_settings_revision" )
	loadLoggingEnabled = logging and logging:GetBool()
		and revision and revision:GetInt() >= 6 or false
end
if BBS.Log and loadLoggingEnabled then
	BBS.Log( "loaded %s in the %s realm", BBS.Version,
		SERVER and "server" or "client" )
end
