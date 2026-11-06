--[[
	Dynamic Toolgun Screen - other tool gun addons

	Advanced Toolgun [Hotbar] (workshop 2806571951)
		Adds a second screen with a tool list. Holding its key (Left Alt by default) and turning the mouse
		wheel activates one tool after another; when the key comes up it plays the tool gun's fire
		animation to lower the gun again.
		- One hold of the key is one tool change for the "< Back to" history, not one per wheel step.
		- The fire animation it plays on release is not taken for a shot (no flash, no use counted).
		- {atg_tab}, {atg_section}, {atg_prev} and {atg_next} show its list on our screen.
		Its view model has the screen in another place; cl_inspect.lua measures whichever model is loaded.
]]

local DTS = DTScreen

local ATG = DTS.AdvancedToolgun or {}
DTS.AdvancedToolgun = ATG

-- AdvToolgun is the global table it creates
function ATG.Installed()
	return istable( AdvToolgun )
end

local function HoldingToolgun()
	local ply = LocalPlayer()
	local wep = IsValid( ply ) and ply:GetActiveWeapon()
	return IsValid( wep ) and wep:GetClass() == "gmod_tool"
end

--[[---------------------------------------------------------
	Its quick select key
-----------------------------------------------------------]]

local lastDown = -10

-- Is its key down now? Also remembers when it last was.
local function KeyDown()
	local cv = GetConVar( "adv_toolgun_act_bind" )
	local key = cv and cv:GetInt() or 0
	local down = key > 0 and input.IsKeyDown( key )
	if ( down ) then lastDown = RealTime() end
	return down
end

local browsing, browseEnd = false, nil

-- a run left open by a Lua refresh of this file would keep the history frozen
if ( DTS.BrowseOrigin and DTS.EndToolBrowse ) then DTS.EndToolBrowse() end

-- The tool its selection is on, the one the last wheel step asked the server for.
local function SelectedTool()
	local state = ATG.State()
	local entry = state and state.TT[ state.selected ]
	return istable( entry ) and isstring( entry[ 2 ] ) and entry[ 2 ] or nil
end

hook.Add( "Think", "DTScreen_AdvancedToolgun", function()

	if ( !ATG.Installed() ) then return end

	local now = RealTime()

	if ( KeyDown() and HoldingToolgun() ) then
		if ( !browsing ) then DTS.BeginToolBrowse() end
		browsing, browseEnd = true, nil
	elseif ( browsing ) then
		-- the tool change of the last wheel step can still be on its way back from the server:
		-- wait for it, or for about two round trips
		local ply = LocalPlayer()
		local ping = IsValid( ply ) and ply:Ping() or 0
		browsing, browseEnd = false, now + 0.3 + ping * 0.002
	end

	if ( browseEnd and ( now >= browseEnd or SelectedTool() == DTS.ToolMode() ) ) then
		browseEnd = nil
		DTS.EndToolBrowse()
	end

end )

-- With its "Close View / Animation" option on, it plays the fire animation the moment its key comes up.
hook.Add( "DTScreen_IgnoreFire", "DTScreen_AdvancedToolgun", function()

	if ( !ATG.Installed() ) then return end

	local anim = GetConVar( "adv_toolgun_anim" )
	if ( !anim or !anim:GetBool() ) then return end

	if ( !KeyDown() and RealTime() - lastDown < 0.3 ) then return true end

end )

--[[---------------------------------------------------------
	Its list
	The list and the selection are locals of its file. Its global function Scroll uses them, so they
	can be read as that function's upvalues: TT (the open list: { name, tool, category } entries and
	{ name, 0, 0 } section headings), ID and LocalID (the selection), TabN (the tab) and ScrollMode.
	Anything unexpected (another version, another Scroll) and the tokens stay empty.
-----------------------------------------------------------]]

local WANTED = { TT = true, ID = true, LocalID = true, TabN = true, ScrollMode = true }
local slots, slotsOf

function ATG.State()

	local fn = ATG.Installed() and Scroll
	if ( !isfunction( fn ) ) then return nil end

	if ( slotsOf != fn ) then

		slotsOf, slots = fn, nil

		local info = debug.getinfo( fn, "S" )
		if ( info and string.find( string.lower( info.short_src or "" ), "advanced_toolgun", 1, true ) ) then
			local found = {}
			for i = 1, 64 do
				local name = debug.getupvalue( fn, i )
				if ( !name ) then break end
				if ( WANTED[ name ] ) then found[ name ] = i end
			end
			if ( found.TT and found.ID and found.LocalID and found.TabN ) then slots = found end
		end

	end

	if ( !slots ) then return nil end

	local state = {}
	for name, i in pairs( slots ) do
		local _, value = debug.getupvalue( fn, i )
		state[ name ] = value
	end

	if ( !istable( state.TT ) or !isnumber( state.ID ) or !isnumber( state.LocalID ) ) then return nil end

	-- as its Scroll and Switch pick the active entry
	state.selected = state.ScrollMode and state.ID or ( state.ID + state.LocalID - 1 )
	return state

end

local function IsTool( entry )
	return istable( entry ) and isstring( entry[ 2 ] ) and entry[ 2 ] != ""
end

-- The tool one wheel step away (dir 1 = down, -1 = up), as its quick select would pick it.
function ATG.Neighbour( state, dir )

	local list = state.TT
	local i = state.selected + dir
	while ( list[ i ] != nil ) do
		if ( IsTool( list[ i ] ) ) then return list[ i ][ 2 ] end
		i = i + dir
	end

end

-- The heading of the section the selection is in.
function ATG.Section( state )

	local list = state.TT
	for i = state.selected, 1, -1 do
		local entry = list[ i ]
		if ( istable( entry ) and entry[ 2 ] == 0 and isstring( entry[ 1 ] ) ) then return DTS.Localize( entry[ 1 ] ) end
	end

end

--[[---------------------------------------------------------
	Tokens
-----------------------------------------------------------]]

local TABS = { "atg.tab.tools", "atg.tab.wire", "atg.tab.favorites" }

-- read once per refresh
local function State( ctx )
	if ( ctx.atg == nil ) then ctx.atg = ATG.State() or false end
	return ctx.atg or nil
end

local function T( name, fn, example )
	DTS.RegisterToken( name, fn, "#token." .. name, "#category.atg", example )
end

T( "atg_tab", function( ctx )
	local state = State( ctx )
	local key = state and TABS[ state.TabN ]
	return key and DTS.L( key ) or ""
end, "Favorites" )

T( "atg_section", function( ctx )
	local state = State( ctx )
	return state and ATG.Section( state ) or ""
end, "Constraints" )

T( "atg_prev", function( ctx )
	local state = State( ctx )
	local mode = state and ATG.Neighbour( state, -1 )
	return mode and DTS.ToolName( mode ) or ""
end, "Rope" )

T( "atg_next", function( ctx )
	local state = State( ctx )
	local mode = state and ATG.Neighbour( state, 1 )
	return mode and DTS.ToolName( mode ) or ""
end, "Weld" )
