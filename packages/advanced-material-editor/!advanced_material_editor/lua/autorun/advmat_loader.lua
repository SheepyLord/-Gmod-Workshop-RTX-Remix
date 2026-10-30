--[[---------------------------------------------------------------------------
	Advanced Material Editor
	Autorun loader.

	Loads every file in lua/advmat/ in a deterministic order:
		sh_*  shared     (AddCSLuaFile + include on both realms)
		sv_*  serverside (include on server only)
		cl_*  clientside (AddCSLuaFile on server, include on client)

	Files inside a prefix group are loaded alphabetically, so numeric ordering
	prefixes (sh_00_..., sh_10_...) can be used when load order matters.
-----------------------------------------------------------------------------]]

AdvMat = AdvMat or {}
AdvMat.Version = "1.0.0"
AdvMat.LuaFolder = "advmat"

local PRIORITY = { sh_ = 1, sv_ = 2, cl_ = 3 }

local function LoadFolder( folder )
	local files = file.Find( folder .. "/*.lua", "LUA" )
	if not files then return end

	table.sort( files, function( a, b )
		local pa = PRIORITY[ string.sub( a, 1, 3 ) ] or 9
		local pb = PRIORITY[ string.sub( b, 1, 3 ) ] or 9
		if pa ~= pb then return pa < pb end
		return a < b
	end )

	for _, name in ipairs( files ) do
		local path   = folder .. "/" .. name
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

LoadFolder( AdvMat.LuaFolder )
