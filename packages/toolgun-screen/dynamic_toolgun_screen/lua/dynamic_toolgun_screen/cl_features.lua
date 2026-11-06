--[[
	Dynamic Toolgun Screen - features around the screen
	Tool history and quick switching, entity tracking, notifications, fire/deploy detection,
	status icons, HUD mirror, console commands and the context menu entry.
]]

local DTS = DTScreen

DTS.SessionStart = DTS.SessionStart or SysTime()
DTS.FPSHistory = DTS.FPSHistory or {}
DTS.History = DTS.History or {}
DTS.Notices = DTS.Notices or {}
DTS.ToolUses = DTS.ToolUses or 0

--[[---------------------------------------------------------
	Tool history ("< Back to ...") and the tool list ("... >")
-----------------------------------------------------------]]

local function RemoveFromHistory( mode )
	for i = #DTS.History, 1, -1 do
		if ( DTS.History[ i ] == mode ) then table.remove( DTS.History, i ) end
	end
end

-- The saved tool mode is applied while joining; only changes made in game belong in the history.
DTS.InGame = DTS.InGame or IsValid( LocalPlayer() )
hook.Add( "InitPostEntity", "DTScreen_InGame", function() DTS.InGame = true end )

local function PushHistory( mode )
	RemoveFromHistory( mode )
	table.insert( DTS.History, 1, mode )
	while ( #DTS.History > 12 ) do table.remove( DTS.History ) end
end

cvars.AddChangeCallback( "gmod_toolmode", function( _, old, new )

	if ( old == new or !DTS.InGame ) then return end

	DTS.ToolChangedAt = RealTime()
	DTS.Dirty = true

	-- flipping through tools (a quick select addon) counts once, when it ends: DTS.EndToolBrowse
	if ( DTS.BrowseOrigin ) then return end

	if ( old and old != "" ) then PushHistory( old ) end
	RemoveFromHistory( new )

end, "DTScreen_History" )

--[[
	Quick select addons activate every tool they pass on the way to the one you want. Between these
	two calls the tool changes stay out of the history; afterwards the tool you started from is the
	one to go back to.
]]
function DTS.BeginToolBrowse()
	if ( !DTS.BrowseOrigin ) then DTS.BrowseOrigin = DTS.ToolMode() end
end

function DTS.EndToolBrowse()

	local origin = DTS.BrowseOrigin
	if ( !origin ) then return end
	DTS.BrowseOrigin = nil

	local cur = DTS.ToolMode()
	if ( origin != "" and origin != cur ) then PushHistory( origin ) end
	RemoveFromHistory( cur )
	DTS.Dirty = true

end

-- The tool "< Back to" leads to: the start of a quick select run while it lasts, else the last one used.
function DTS.PreviousTool()
	local origin = DTS.BrowseOrigin
	if ( origin and origin != "" and origin != DTS.ToolMode() ) then return origin end
	return DTS.History[ 1 ]
end

local toolList, nextCache

-- The name the Tools tab sorts a tool by (sandbox toolpanel.lua: the phrase of its Text, sorted by SortedPairs).
local function MenuName( item )
	local name = item.Text or item.ItemName or ""
	if ( string.sub( name, 1, 1 ) == "#" ) then name = string.sub( name, 2 ) end
	return language.GetPhrase( name )
end

-- Tools in the order the Tools tab shows them: { { mode = "weld", cat = "Constraints" }, ... }
function DTS.GetToolList()

	if ( toolList and #toolList > 0 ) then return toolList end

	local swep = weapons.GetStored( "gmod_tool" )
	local tools = swep and swep.Tool or {}
	local out = {}

	for _, tab in ipairs( spawnmenu.GetTools() or {} ) do
		for _, cat in ipairs( tab.Items or {} ) do
			local items = {}
			for _, item in ipairs( cat ) do
				if ( istable( item ) and item.ItemName and tools[ item.ItemName ] ) then
					items[ #items + 1 ] = { mode = item.ItemName, key = MenuName( item ) }
				end
			end
			table.sort( items, function( a, b )
				if ( a.key != b.key ) then return a.key < b.key end
				return a.mode < b.mode
			end )
			for _, it in ipairs( items ) do
				out[ #out + 1 ] = { mode = it.mode, cat = tab.Name .. "/" .. tostring( cat.ItemName ) }
			end
		end
	end

	-- no spawn menu (other gamemodes): fall back to category + name order
	if ( #out == 0 ) then
		for mode, tool in pairs( tools ) do
			if ( tool.AddToMenu != false ) then out[ #out + 1 ] = { mode = mode, cat = tostring( tool.Category ) } end
		end
		table.sort( out, function( a, b )
			if ( a.cat != b.cat ) then return a.cat < b.cat end
			return a.mode < b.mode
		end )
	end

	toolList, nextCache = out, {}
	return out

end

hook.Add( "PostReloadToolsMenu", "DTScreen_ToolList", function() toolList = nil end )

-- Next (dir 1) or previous (dir -1) tool in the same category, wrapping around.
function DTS.NextTool( mode, dir )

	local list = DTS.GetToolList()
	local key = mode .. "|" .. dir
	if ( nextCache and nextCache[ key ] != nil ) then return nextCache[ key ] or nil end

	local cat
	for _, t in ipairs( list ) do
		if ( t.mode == mode ) then cat = t.cat break end
	end

	local result = false
	if ( cat ) then
		local same, pos = {}, 1
		for _, t in ipairs( list ) do
			if ( t.cat == cat ) then
				same[ #same + 1 ] = t.mode
				if ( t.mode == mode ) then pos = #same end
			end
		end
		if ( #same > 1 ) then result = same[ ( pos - 1 + dir ) % #same + 1 ] end
	elseif ( list[ 1 ] ) then
		result = list[ 1 ].mode
	end

	if ( nextCache ) then nextCache[ key ] = result end
	return result or nil

end

function DTS.SwitchTool( mode )

	if ( !mode or mode == "" ) then return end

	-- same as clicking the tool in the spawn menu: selects the tool gun and opens the tool's panel
	if ( !pcall( spawnmenu.ActivateTool, mode ) ) then
		RunConsoleCommand( "gmod_tool", mode )
	end

end

--[[---------------------------------------------------------
	Entity tracking
-----------------------------------------------------------]]

function DTS.SetTracked( ent )

	if ( IsValid( ent ) and !ent:IsWorld() ) then
		DTS.TrackedEntity = ent
		DTS.Notify( DTS.L( "notify.tracking", { name = DTS.EntityName( ent ) } ), NOTIFY_HINT )
	else
		if ( IsValid( DTS.TrackedEntity ) ) then DTS.Notify( DTS.L( "notify.untracked" ), NOTIFY_CLEANUP ) end
		DTS.TrackedEntity = nil
	end

	DTS.Dirty = true

end

net.Receive( "DTScreen_Track", function()
	DTS.SetTracked( net.ReadEntity() )
end )

hook.Add( "PreDrawHalos", "DTScreen_Track", function()

	local ent = DTS.TrackedEntity
	if ( !IsValid( ent ) or DTS.ToolMode() != "dynamic_toolgun_screen" ) then return end

	local ply = LocalPlayer()
	local wep = IsValid( ply ) and ply:GetActiveWeapon()
	if ( !IsValid( wep ) or wep:GetClass() != "gmod_tool" ) then return end

	local T = DTS.ActiveTheme
	halo.Add( { ent }, T and T.accent or Color( 0, 160, 255 ), 2, 2, 1, true, true )

end )

--[[---------------------------------------------------------
	Notifications: game notices (undo, limits, hints...) also appear on the screen
-----------------------------------------------------------]]

local NOTICE_ICONS = {
	[ NOTIFY_GENERIC or 0 ] = "info",
	[ NOTIFY_ERROR or 1 ] = "warn",
	[ NOTIFY_UNDO or 2 ] = "undo",
	[ NOTIFY_HINT or 3 ] = "info",
	[ NOTIFY_CLEANUP or 4 ] = "undo",
}

function DTS.Notify( text, kind, duration )

	if ( !DTS.GetBool( "notifications" ) ) then return end

	text = DTS.Localize( tostring( text or "" ) )
	if ( text == "" ) then return end

	table.insert( DTS.Notices, {
		runs = { { icon = NOTICE_ICONS[ kind or 0 ] or "info" }, { " " .. text } },
		start = RealTime(),
		dur = duration or math.Clamp( DTS.GetFloat( "notify_time" ), 0.5, 30 )
	} )

	while ( #DTS.Notices > 5 ) do table.remove( DTS.Notices, 1 ) end

end

-- The newest notification still on screen, with .alpha for fading; nil when there is none.
function DTS.ActiveNotification( now )

	for i = #DTS.Notices, 1, -1 do
		local n = DTS.Notices[ i ]
		local age = now - n.start
		if ( age >= 0 and age < n.dur ) then
			n.alpha = math.Clamp( math.min( ( n.dur - age ) / 0.3, age / 0.12 ), 0, 1 )
			return n
		end
	end

end

local function WrapNotifications()

	if ( !notification or !notification.AddLegacy or notification.DTScreenWrapped == notification.AddLegacy ) then return end

	local original = notification.AddLegacy
	local function AddLegacy( text, kind, length, ... )
		DTS.Notify( text, kind )
		return original( text, kind, length, ... )
	end

	notification.AddLegacy = AddLegacy
	notification.DTScreenWrapped = AddLegacy

end

WrapNotifications()
hook.Add( "InitPostEntity", "DTScreen_Notifications", WrapNotifications )

--[[---------------------------------------------------------
	Per-frame state: FPS, tool gun deploy (boot animation), successful shots (flash)
-----------------------------------------------------------]]

local lastWeapon, lastSeq, lastCycle
local nextSample = 0

hook.Add( "Think", "DTScreen_Think", function()

	local now = RealTime()
	local ft = RealFrameTime()
	if ( ft > 0 ) then DTS.FPS = Lerp( 0.08, DTS.FPS or 1 / ft, 1 / ft ) end

	if ( now >= nextSample ) then
		nextSample = now + 0.25
		local h = DTS.FPSHistory
		h[ #h + 1 ] = DTS.FPS or 0
		if ( #h > 60 ) then table.remove( h, 1 ) end
	end

	local ply = LocalPlayer()
	if ( !IsValid( ply ) ) then return end

	local wep = ply:GetActiveWeapon()
	local holding = IsValid( wep ) and wep:GetClass() == "gmod_tool"

	if ( holding and lastWeapon != wep ) then DTS.BootStart = now end
	lastWeapon = holding and wep or nil

	if ( !holding ) then return end

	-- The tool gun only plays its attack animation when a tool action succeeded (SWEP:DoShootEffect).
	-- Addons that play it for other reasons return true from DTScreen_IgnoreFire (see cl_compat.lua).
	local vm = ply:GetViewModel()
	if ( IsValid( vm ) ) then
		local seq, cycle = vm:GetSequence(), vm:GetCycle()
		if ( vm:GetSequenceActivity( seq ) == ACT_VM_PRIMARYATTACK and ( seq != lastSeq or cycle < ( lastCycle or 0 ) - 0.01 ) and hook.Run( "DTScreen_IgnoreFire", wep, vm ) != true ) then
			DTS.LastFire = now
			DTS.ToolUses = DTS.ToolUses + 1
			DTS.Dirty = true
		end
		lastSeq, lastCycle = seq, cycle
	end

end )

hook.Add( "PlayerStartVoice", "DTScreen_Voice", function( ply ) if ( ply == LocalPlayer() ) then DTS.Talking = true end end )
hook.Add( "PlayerEndVoice", "DTScreen_Voice", function( ply ) if ( ply == LocalPlayer() ) then DTS.Talking = false end end )

-- Flag in the title bar waves for a moment after a shot or a tool change.
function DTS.FlagWave( now )

	local since = now - math.max( DTS.LastFire or -10, DTS.ToolChangedAt or -10 )
	if ( since < 1.2 ) then return now end

end

-- Big text fades in after a tool change.
function DTS.ToolChangeAlpha( now )
	return math.Clamp( ( now - ( DTS.ToolChangedAt or -10 ) ) / 0.25, 0, 1 )
end

--[[
	The device's battery. system.BatteryPower() is Steam's GetCurrentBatteryPower: the charge, 0-100,
	while the device runs on its battery, and 255 while it is on AC power (charging or not) or has no
	battery. The GMod wiki says 255 only without a battery, but Steam's code checks the AC line, so
	there is no charging state to show.
	Returns { level = 0-100 on battery, nil while plugged in }.
]]
local battery = { level = nil }
local batteryReadAt = -10

function DTS.Battery()

	local now = RealTime()
	if ( now - batteryReadAt < 2 ) then return battery end
	batteryReadAt = now

	local v = system.BatteryPower and system.BatteryPower()
	battery.level = ( isnumber( v ) and v >= 0 and v <= 100 ) and math.floor( v + 0.5 ) or nil

	return battery

end

-- "85%" in the language's own way of writing it.
function DTS.BatteryText( level )
	return DTS.L( "battery.percent", { n = level } )
end

local volume = GetConVar( "volume" )
local status = {}

function DTS.StatusIcons( ctx )

	status.speaker = DTS.GetBool( "icon_speaker" )
	status.signal = DTS.GetBool( "icon_signal" )
	status.battery = DTS.GetBool( "icon_battery" )

	local vol = volume and volume:GetFloat() or 1
	status.muted = vol <= 0.01
	status.volume = ( vol > 0.66 and 3 ) or ( vol > 0.33 and 2 ) or 1
	status.talking = DTS.Talking

	local ply = ctx and ctx.ply
	if ( IsValid( ply ) ) then
		local ping = ply:Ping()
		status.bars = ( game.SinglePlayer() or ping < 60 ) and 4 or ( ping < 120 and 3 ) or ( ping < 200 and 2 ) or 1
		status.health = math.Clamp( ply:Health() / math.max( ply:GetMaxHealth(), 1 ), 0, 1 )
	else
		status.bars, status.health = 4, 1
	end

	-- the battery icon shows the device's own battery (status.health stays for layouts of other addons)
	local b = DTS.Battery()
	status.batteryLevel, status.plugged = b.level, b.level == nil

	return status

end

--[[---------------------------------------------------------
	HUD mirror
-----------------------------------------------------------]]

hook.Add( "HUDPaint", "DTScreen_Mirror", function()

	if ( !DTS.GetBool( "mirror" ) ) then return end

	local ply = LocalPlayer()
	local wep = IsValid( ply ) and ply:GetActiveWeapon()
	if ( !IsValid( wep ) or wep:GetClass() != "gmod_tool" ) then return end

	local size = math.Clamp( DTS.GetInt( "mirror_size" ), 64, math.min( ScrW(), ScrH() ) - 40 )
	local corner = DTS.GetString( "mirror_corner" )
	local margin = 24
	local left = corner == "tl" or corner == "bl"
	local top = corner == "tl" or corner == "tr"

	local x = left and margin or ScrW() - size - margin
	local y = top and margin or ScrH() - size - margin

	surface.SetDrawColor( 0, 0, 0, math.Clamp( DTS.GetInt( "mirror_alpha" ), 0, 255 ) * 0.7 )
	surface.DrawRect( x - 3, y - 3, size + 6, size + 6 )
	DTS.DrawScreenTexture( x, y, size, size, math.Clamp( DTS.GetInt( "mirror_alpha" ), 0, 255 ) )

end )

--[[---------------------------------------------------------
	Context menu: right click an entity -> Track on tool gun screen
-----------------------------------------------------------]]

properties.Add( "dts_track", {
	MenuLabel = "#dts.prop.track", -- registered with language.Add by cl_i18n.lua
	Order = 2600,
	MenuIcon = "icon16/monitor.png",
	Filter = function( self, ent, ply ) return IsValid( ent ) and !ent:IsWorld() end,
	Action = function( self, ent )
		if ( DTS.TrackedEntity == ent ) then DTS.SetTracked( nil ) else DTS.SetTracked( ent ) end
	end
} )

--[[---------------------------------------------------------
	Console commands
-----------------------------------------------------------]]

local function Cycle( list, current, dir )
	local idx = 0
	for i, v in ipairs( list ) do if ( v == current ) then idx = i break end end
	return list[ ( idx - 1 + ( dir or 1 ) ) % #list + 1 ]
end

concommand.Add( "dts_tool_back", function()
	local prev = DTS.PreviousTool()
	if ( prev ) then DTS.SwitchTool( prev ) end
end, nil, "Switch back to the previously used tool (like the screen's '< Back to' link)." )

concommand.Add( "dts_tool_next", function()
	DTS.SwitchTool( DTS.NextTool( DTS.ToolMode(), 1 ) )
end, nil, "Switch to the next tool in the current category." )

concommand.Add( "dts_tool_prev", function()
	DTS.SwitchTool( DTS.NextTool( DTS.ToolMode(), -1 ) )
end, nil, "Switch to the previous tool in the current category." )

concommand.Add( "dts_layout_next", function()
	local id = Cycle( DTS.LayoutOrder, DTS.GetString( "layout" ), 1 )
	DTS.SetSetting( "layout", id )
	DTS.Notify( DTS.L( "notify.layout", { name = DTS.Localize( DTS.Layouts[ id ] and DTS.Layouts[ id ].Name or id ) } ), NOTIFY_HINT )
end, nil, "Switch to the next screen layout." )

concommand.Add( "dts_theme_next", function()
	local id = Cycle( DTS.ThemeOrder, DTS.GetString( "theme" ), 1 )
	DTS.SetSetting( "theme", id )
	DTS.Notify( DTS.L( "notify.theme", { name = DTS.Localize( DTS.Themes[ id ] and DTS.Themes[ id ].Name or id ) } ), NOTIFY_HINT )
end, nil, "Switch to the next colour theme." )

concommand.Add( "dts_track", function()
	local ply = LocalPlayer()
	if ( !IsValid( ply ) ) then return end
	local ent = DTS.ToolTrace( ply ).Entity
	if ( IsValid( ent ) ) then DTS.SetTracked( ent ) end
end, nil, "Track the entity you are aiming at on the screen." )

concommand.Add( "dts_untrack", function() DTS.SetTracked( nil ) end, nil, "Stop tracking an entity." )

concommand.Add( "dts_notify", function( _, _, _, argStr )
	DTS.Notify( argStr, NOTIFY_GENERIC )
end, nil, "Show a message on the tool gun screen." )

concommand.Add( "dts_reset", function()
	DTS.ResetSettings()
	print( "[Dynamic Toolgun Screen] All settings are back to their defaults." )
end, nil, "Reset every Dynamic Toolgun Screen setting." )

concommand.Add( "dts_export", function()
	local str = DTS.ExportSettings()
	SetClipboardText( str )
	print( "[Dynamic Toolgun Screen] Settings copied to the clipboard:\n" .. str )
end, nil, "Copy your Dynamic Toolgun Screen settings to the clipboard." )

concommand.Add( "dts_import", function( _, _, _, argStr )
	-- the console cuts long lines, so without an argument it opens a box to paste the string into
	if ( string.Trim( argStr or "" ) == "" and DTS.OpenImportDialog ) then DTS.OpenImportDialog() return end
	local ok, res = DTS.ImportSettings( argStr )
	print( "[Dynamic Toolgun Screen] " .. ( ok and ( "Imported, " .. res .. " settings changed." ) or res ) )
end, nil, "Import settings from a DTS1:... string; without one, opens a box to paste it into." )

function DTS.Diagnostics()

	local orig = DTS.OriginalRenderScreen
	local info = isfunction( orig ) and debug.getinfo( orig, "S" )

	return {
		version = DTS.Version,
		patched = DTS.Patched or false,
		original = info and info.short_src or "none",
		conflict = DTS.Conflict,
		usingOriginal = DTS.UsingOriginal or false,
		renderMs = DTS.RenderMs or 0,
		lastError = DTS.LastError,
		broken = DTS.Broken or false,
		rt = DTS.GetScreenRT():GetName(),
	}

end

concommand.Add( "dts_debug", function()

	local d = DTS.Diagnostics()
	print( "[Dynamic Toolgun Screen] v" .. d.version )
	print( "  installed: " .. tostring( d.patched ) .. "  wraps: " .. d.original .. ( d.conflict and ( "  CONFLICT with " .. d.conflict ) or "" ) )
	print( "  layout: " .. DTS.GetString( "layout" ) .. "  theme: " .. DTS.GetString( "theme" ) .. "  render target: " .. d.rt )
	print( string.format( "  draw cost: %.3f ms  showing original screen: %s  broken: %s", d.renderMs, tostring( d.usingOriginal ), tostring( d.broken ) ) )
	if ( d.lastError ) then print( "  last error: " .. tostring( d.lastError ) ) end

end, nil, "Print Dynamic Toolgun Screen diagnostics." )
