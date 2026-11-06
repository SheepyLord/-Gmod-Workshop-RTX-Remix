--[[
	Dynamic Toolgun Screen - the tool
	Left click: track the entity you aim at (its live info appears on the screen)
	Right click: switch to the next screen layout
	Reload: stop tracking
	The tool's panel holds every screen setting, with a live preview.
]]

TOOL.Category = "Render"
TOOL.Name = "#tool.dynamic_toolgun_screen.name"

TOOL.Information = {
	{ name = "left" },
	{ name = "right" },
	{ name = "reload" },
}

-- The tool's name and help come from the addon's language files (cl_i18n.lua registers them with
-- language.Add in the player's language). English stays here only in case those files failed to load.
if ( CLIENT and !( DTScreen and DTScreen.ApplyLanguage ) ) then

	language.Add( "tool.dynamic_toolgun_screen.name", "Dynamic Toolgun Screen" )
	language.Add( "tool.dynamic_toolgun_screen.desc", "Customize the tool gun's live screen and track entities on it" )
	language.Add( "tool.dynamic_toolgun_screen.left", "Track the entity you are aiming at" )
	language.Add( "tool.dynamic_toolgun_screen.right", "Switch to the next screen layout" )
	language.Add( "tool.dynamic_toolgun_screen.reload", "Stop tracking" )

end

local function SendTrack( ply, ent )

	net.Start( "DTScreen_Track" )
	net.WriteEntity( ent )
	net.Send( ply )

end

function TOOL:LeftClick( trace )

	local ent = trace.Entity
	if ( !IsValid( ent ) ) then return false end
	if ( CLIENT ) then return true end

	SendTrack( self:GetOwner(), ent )
	return true

end

function TOOL:RightClick( trace )

	if ( CLIENT ) then return true end

	self:GetOwner():ConCommand( "dts_layout_next" )
	return true

end

function TOOL:Reload( trace )

	if ( CLIENT ) then return true end

	SendTrack( self:GetOwner(), NULL )
	return true

end

function TOOL.BuildCPanel( panel )

	if ( DTScreen and DTScreen.BuildPanel ) then
		DTScreen.BuildPanel( panel )
	else
		panel:Help( "Dynamic Toolgun Screen did not load. Check the console for Lua errors." )
	end

end
