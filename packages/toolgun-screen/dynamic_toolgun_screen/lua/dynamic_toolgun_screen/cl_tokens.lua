--[[
	Dynamic Toolgun Screen - live data

	Templates
		Every text line on the screen is a template: plain text with tokens in braces.
		{token}              a live value, e.g. {aim_dist}
		{token:argument}     tokens that take an argument, e.g. {time:%H:%M:%S} or {cvar:sbox_maxprops}
		{token|fallback}     text to show when the token is empty, e.g. {ent_owner|nobody}
		**text**             highlighted text (link colour, underlined where the layout supports it)
		{{ and }}            literal braces
		A line whose tokens are all empty is hidden, so "Back to {tool_prev}" disappears until there is a previous tool.
		The default lines are {tr:name} references to phrases of the active language (tpl.name in lang/*.lua).

	Context
		Once per refresh (dts_refresh times a second) the screen builds a context: the tool gun's own trace,
		the entity it hits, the tool object, the tracked entity... Tokens read from it and are cached per refresh.

	Everything a token writes in words comes from the language files, so the screen follows the player's language.
]]

local DTS = DTScreen

local Round, Clamp, floor = math.Round, math.Clamp, math.floor
local format = string.format

-- gmod_toolmode is created by the tool gun SWEP, which loads after autorun files
local toolmode

function DTS.ToolMode()
	toolmode = toolmode or GetConVar( "gmod_toolmode" )
	return toolmode and toolmode:GetString() or ""
end

--[[---------------------------------------------------------
	Template parsing and evaluation
-----------------------------------------------------------]]

local parseCache, parseCount = {}, 0

function DTS.ParseTemplate( str )

	local cached = parseCache[ str ]
	if ( cached ) then return cached end

	local segs = {}
	local hl = false
	local buf = {}
	local i, n = 1, #str

	local function Flush()
		if ( #buf > 0 ) then
			segs[ #segs + 1 ] = { lit = table.concat( buf ), hl = hl }
			buf = {}
		end
	end

	while ( i <= n ) do

		local two = string.sub( str, i, i + 1 )
		local c = string.sub( str, i, i )

		if ( two == "**" ) then
			Flush()
			hl = !hl
			i = i + 2
		elseif ( two == "{{" ) then
			buf[ #buf + 1 ] = "{"
			i = i + 2
		elseif ( two == "}}" ) then
			buf[ #buf + 1 ] = "}"
			i = i + 2
		elseif ( c == "{" ) then
			local close = string.find( str, "}", i + 1, true )
			if ( !close ) then
				buf[ #buf + 1 ] = string.sub( str, i )
				break
			end

			local inner = string.sub( str, i + 1, close - 1 )
			local body, fallback = string.match( inner, "^([^|]*)|(.*)$" )
			body = body or inner

			local name, arg = string.match( body, "^%s*([%w_]+)%s*:(.*)$" )
			name = name or string.match( body, "^%s*([%w_]+)%s*$" )

			if ( name ) then
				Flush()
				segs[ #segs + 1 ] = { tok = string.lower( name ), arg = arg, fallback = fallback, hl = hl }
				segs.hasTokens = true
				i = close + 1
			else
				-- not a token: a plain "{", and the text after it is read normally ("Size {w {tool}")
				buf[ #buf + 1 ] = "{"
				i = i + 1
			end
		else
			buf[ #buf + 1 ] = c
			i = i + 1
		end

	end

	Flush()

	parseCount = parseCount + 1
	if ( parseCount > 512 ) then parseCache, parseCount = {}, 0 end
	parseCache[ str ] = segs

	return segs

end

local function EvalToken( name, arg, ctx )

	local key = arg and ( name .. ":" .. arg ) or name
	local cached = ctx.cache[ key ]
	if ( cached != nil ) then return cached end

	local tok = DTS.Tokens[ name ]
	if ( !tok ) then return nil, true end

	local ok, value = pcall( tok.fn, ctx, arg )
	if ( !ok ) then
		DTS.ErrorOnce( "token." .. name, "Token {" .. name .. "} failed: " .. tostring( value ) )
		value = "!"
	end

	if ( value == nil ) then value = "" end
	if ( isnumber( value ) ) then value = tostring( value ) end

	ctx.cache[ key ] = value
	return value

end

DTS.EvalToken = EvalToken

local function IsEmpty( v )
	return v == nil or v == "" or ( istable( v ) and #v == 0 )
end

local function AddRun( runs, text, hl )

	if ( text == "" ) then return end

	local last = runs[ #runs ]
	if ( last and !last.icon and !last.ghost and ( last[ 2 ] or false ) == ( hl or false ) ) then
		last[ 1 ] = last[ 1 ] .. text
	else
		runs[ #runs + 1 ] = { text, hl or false }
	end

end

-- Returns the runs for a template, or nil when the line should be hidden.
function DTS.EvalTemplate( str, ctx )

	if ( !str or str == "" ) then return nil end

	local segs = DTS.ParseTemplate( str )
	local runs = {}
	local anyValue = false

	for _, seg in ipairs( segs ) do

		if ( seg.lit ) then
			AddRun( runs, seg.lit, seg.hl )
		else
			local value, unknown = EvalToken( seg.tok, seg.arg, ctx )

			if ( unknown ) then
				AddRun( runs, "{" .. seg.tok .. "?}", seg.hl )
				anyValue = true
			else
				if ( IsEmpty( value ) and seg.fallback ) then value = seg.fallback end

				if ( !IsEmpty( value ) ) then
					anyValue = true
					if ( istable( value ) ) then
						for _, r in ipairs( value ) do
							if ( r.icon ) then
								runs[ #runs + 1 ] = { icon = r.icon, [ 2 ] = r[ 2 ] or seg.hl }
							elseif ( r.ghost ) then
								runs[ #runs + 1 ] = { r[ 1 ], r[ 2 ] or seg.hl, ghost = true }
							else
								AddRun( runs, tostring( r[ 1 ] or "" ), r[ 2 ] or seg.hl )
							end
						end
					else
						AddRun( runs, tostring( value ), seg.hl )
					end
				end
			end
		end

	end

	if ( segs.hasTokens and !anyValue ) then return nil end
	if ( #runs == 0 ) then return nil end

	return runs

end

-- Plain text of a template (for the menu's token list and for logging).
function DTS.RunsToString( runs )

	if ( !runs ) then return "" end
	if ( isstring( runs ) ) then return runs end

	local out = {}
	for _, r in ipairs( runs ) do
		if ( r.icon ) then
			out[ #out + 1 ] = "[" .. r.icon .. "]"
		else
			out[ #out + 1 ] = tostring( r[ 1 ] or "" )
		end
	end
	return table.concat( out )

end

--[[---------------------------------------------------------
	Context
-----------------------------------------------------------]]

-- Same trace as SWEP:DoToolTrace in the sandbox tool gun, so the screen shows what a click would hit.
local toolMask = bit.bor( CONTENTS_SOLID, CONTENTS_MOVEABLE, CONTENTS_MONSTER, CONTENTS_WINDOW, CONTENTS_DEBRIS, CONTENTS_GRATE, CONTENTS_AUX )

function DTS.ToolTrace( ply )

	local tr = util.GetPlayerTrace( ply )
	tr.mask = toolMask
	tr.mins = vector_origin
	tr.maxs = vector_origin
	tr.filter = { ply, ply:GetVehicle() }

	local trace = util.TraceLine( tr )
	if ( !trace.Hit or !IsValid( trace.Entity ) ) then
		local hull = util.TraceHull( tr )
		if ( IsValid( hull.Entity ) ) then trace = hull end
	end

	return trace

end

function DTS.GetToolTable( mode )

	local swep = weapons.GetStored( "gmod_tool" )
	return swep and swep.Tool and swep.Tool[ mode ] or nil

end

function DTS.BuildContext( weapon )

	local ctx = { cache = {}, now = RealTime(), time = os.time() }
	local ply = LocalPlayer()

	ctx.ply = ply
	ctx.mode = DTS.ToolMode()

	if ( !IsValid( ply ) ) then return ctx end

	if ( !IsValid( weapon ) ) then weapon = ply:GetWeapon( "gmod_tool" ) end
	ctx.weapon = IsValid( weapon ) and weapon or nil

	local tool = ctx.weapon and ctx.weapon.GetToolObject and ctx.weapon:GetToolObject( ctx.mode )
	ctx.tool = tool or DTS.GetToolTable( ctx.mode )

	ctx.tr = DTS.ToolTrace( ply )
	ctx.ent = IsValid( ctx.tr.Entity ) and ctx.tr.Entity or nil
	ctx.track = IsValid( DTS.TrackedEntity ) and DTS.TrackedEntity or nil

	hook.Run( "DTScreen_BuildContext", ctx )

	return ctx

end

--[[---------------------------------------------------------
	Formatting helpers (numbers, units, times and dates in the active language)
-----------------------------------------------------------]]

local UNIT_TO_M = 0.01905 -- 1 unit = 0.75 inch

function DTS.FormatDistance( units )

	local mode = DTS.GetString( "units" )
	local dec = Clamp( DTS.GetInt( "decimals" ), 0, 3 )

	if ( mode == "hu" ) then return DTS.FormatUnit( "hu", units, 0 ) end

	if ( mode == "ft" ) then
		local ft = units / 16
		if ( ft >= 5280 ) then return DTS.FormatUnit( "mi", ft / 5280, 2 ) end
		return DTS.FormatUnit( "ft", ft, dec )
	end

	local m = units * UNIT_TO_M
	if ( m >= 1000 ) then return DTS.FormatUnit( "km", m / 1000, 2 ) end
	return DTS.FormatUnit( "m", m, dec )

end

function DTS.FormatSpeed( ups )

	local mode = DTS.GetString( "units" )

	if ( mode == "hu" ) then return DTS.FormatUnit( "ups", ups, 0 ) end
	if ( mode == "ft" ) then return DTS.FormatUnit( "mph", ups / 16 * 3600 / 5280, 0 ) end
	return DTS.FormatUnit( "kmh", ups * UNIT_TO_M * 3.6, 0 )

end

local function Int( n )
	n = Round( n )
	if ( n == 0 ) then n = 0 end -- no "-0"
	return format( "%d", n )
end

function DTS.FormatVector( v )
	return Int( v.x ) .. ", " .. Int( v.y ) .. ", " .. Int( v.z )
end

function DTS.FormatDuration( s )

	s = floor( math.max( s, 0 ) )
	local h, m, sec = floor( s / 3600 ), floor( s / 60 ) % 60, s % 60

	if ( h > 0 ) then return DTS.L( "duration.hm", { h = h, m = format( "%02d", m ) } ) end
	if ( m > 0 ) then return DTS.L( "duration.ms", { m = m, s = format( "%02d", sec ) } ) end
	return DTS.L( "duration.s", { s = sec } )

end

local function EscapeDate( s )
	return ( string.gsub( s, "%%", "%%%%" ) )
end

--[[
	os.date hands its format to the C runtime, where an unknown % code can end the game: only safe codes pass.
	%a %A %b %B %p are written in the active language (the C runtime would always write them in English).
]]
local SAFE_DATE = { c = true, d = true, H = true, I = true, j = true, m = true, M = true, S = true, U = true, w = true, W = true, x = true, X = true, y = true, Y = true, Z = true, [ "%" ] = true }

function DTS.SafeDate( fmt, t )

	t = t or os.time()
	local d = os.date( "*t", t )

	fmt = string.gsub( fmt or "", "%%(.?)", function( c )
		if ( c == "a" ) then return EscapeDate( DTS.L( "date.wday." .. d.wday ) ) end
		if ( c == "A" ) then return EscapeDate( DTS.L( "date.wday_full." .. d.wday ) ) end
		if ( c == "b" ) then return EscapeDate( DTS.L( "date.month." .. d.month ) ) end
		if ( c == "B" ) then return EscapeDate( DTS.L( "date.month_full." .. d.month ) ) end
		if ( c == "p" ) then return EscapeDate( DTS.L( d.hour < 12 and "clock.am" or "clock.pm" ) ) end
		if ( SAFE_DATE[ c ] ) then return "%" .. c end
		return ""
	end )

	return os.date( fmt, t )

end

function DTS.FormatDate( t )

	local d = os.date( "*t", t )
	return DTS.L( "date.format", {
		wday = DTS.L( "date.wday." .. d.wday ),
		day = d.day,
		month = DTS.L( "date.month." .. d.month ),
		year = d.year
	} )

end

function DTS.Clock24()

	local mode = DTS.GetString( "clock_24h" )
	if ( mode == "1" ) then return true end
	if ( mode == "0" ) then return false end
	return DTS.LanguageClock24()

end

-- Clock from the clock settings. Returns runs so a blinking colon keeps its width.
function DTS.ClockRuns( t )

	local d = os.date( "*t", t )
	local h24 = DTS.Clock24()
	local h = d.hour

	if ( !h24 ) then
		h = h % 12
		if ( h == 0 ) then h = 12 end
	end

	local ghost = DTS.GetBool( "clock_blink" ) and d.sec % 2 == 1
	local runs = { { h24 and format( "%02d", h ) or tostring( h ) }, { ":", false, ghost = ghost or nil }, { format( "%02d", d.min ) } }

	if ( DTS.GetBool( "clock_seconds" ) ) then
		runs[ #runs + 1 ] = { ":", false, ghost = ghost or nil }
		runs[ #runs + 1 ] = { format( "%02d", d.sec ) }
	end

	if ( h24 or !DTS.GetBool( "clock_ampm" ) ) then return runs end

	-- "{time} {ampm}" or "{ampm} {time}", as the language writes it
	local ampm = DTS.L( d.hour < 12 and "clock.am" or "clock.pm" )
	local pattern = DTS.L( "clock.ampm" )
	local a, b = string.find( pattern, "{time}", 1, true )
	if ( !a ) then return runs end

	local before = string.gsub( string.sub( pattern, 1, a - 1 ), "{ampm}", ampm )
	local after = string.gsub( string.sub( pattern, b + 1 ), "{ampm}", ampm )

	local out = {}
	if ( before != "" ) then out[ 1 ] = { before } end
	for _, r in ipairs( runs ) do out[ #out + 1 ] = r end
	if ( after != "" ) then out[ #out + 1 ] = { after } end

	return out

end

function DTS.ClockString( t )
	return DTS.RunsToString( DTS.ClockRuns( t ) )
end

--[[---------------------------------------------------------
	Entity helpers
-----------------------------------------------------------]]

local npcNames = {}

local function NPCName( class )

	if ( npcNames[ class ] != nil ) then return npcNames[ class ] or nil end

	local found = false
	local list_npc = list.Get( "NPC" )
	local exact = list_npc[ class ]
	if ( exact and exact.Name ) then
		found = DTS.Localize( exact.Name )
	else
		for _, v in pairs( list_npc ) do
			if ( v.Class == class and v.Name ) then found = DTS.Localize( v.Name ) break end
		end
	end

	npcNames[ class ] = found
	return found or nil

end

-- NPC names come from the game's phrases, which change with the game's language
hook.Add( "DTScreen_LanguageChanged", "DTScreen_NPCNames", function() npcNames = {} end )

function DTS.ModelName( ent )

	local mdl = ent:GetModel()
	if ( !isstring( mdl ) or mdl == "" or string.sub( mdl, 1, 1 ) == "*" ) then return nil end
	return string.StripExtension( string.GetFileFromFilename( mdl ) )

end

-- A friendly name: player nick, PrintName, NPC spawn menu name, model name for props, else the class.
function DTS.EntityName( ent )

	if ( !IsValid( ent ) ) then return "" end
	if ( ent:IsPlayer() ) then return ent:Nick() end

	local class = ent:GetClass()

	local pn = ent.PrintName
	if ( isstring( pn ) and pn != "" ) then return DTS.Localize( pn ) end

	if ( ent:IsNPC() or ( ent.IsNextBot and ent:IsNextBot() ) ) then
		local name = NPCName( class )
		if ( name ) then return name end
	end

	if ( string.StartWith( class, "prop_" ) or ent:IsVehicle() ) then
		local mdl = DTS.ModelName( ent )
		if ( mdl ) then return mdl end
	end

	return DTS.Phrase( class ) or class

end

function DTS.EntityOwner( ent )

	if ( !IsValid( ent ) ) then return "" end

	if ( ent.CPPIGetOwner ) then
		local owner = ent:CPPIGetOwner()
		if ( IsValid( owner ) and owner:IsPlayer() ) then return owner:Nick() end
	end

	local owner = ent:GetOwner()
	if ( IsValid( owner ) and owner:IsPlayer() ) then return owner:Nick() end

	return ""

end

function DTS.EntityHealth( ent )

	if ( !IsValid( ent ) ) then return "" end

	local hp, maxhp = ent:Health(), ent:GetMaxHealth()
	if ( hp <= 0 and maxhp <= 1 ) then return "" end
	if ( maxhp > 1 ) then return format( "%d/%d", hp, maxhp ) end
	return tostring( hp )

end

-- The surface property as the engine names it (concrete, metal_box...).
function DTS.SurfacePropName( tr )

	if ( !tr or !tr.Hit ) then return "" end
	local name = util.GetSurfacePropName( tr.SurfaceProps or 0 )
	if ( !name or name == "" ) then return "" end
	return ( string.gsub( name, "_", " " ) )

end

-- The kind of material in the active language (Concrete, Metal, Wood...), from the trace's material type.
local MAT_KEYS = {}
for _, name in ipairs( { "ANTLION", "BLOODYFLESH", "CONCRETE", "DIRT", "EGGSHELL", "FLESH", "GRATE", "ALIENFLESH", "CLIP", "SNOW", "PLASTIC", "METAL", "SAND", "FOLIAGE", "COMPUTER", "SLOSH", "TILE", "GRASS", "VENT", "WOOD", "DEFAULT", "GLASS", "WARPSHIELD" } ) do
	local value = _G[ "MAT_" .. name ]
	if ( value ) then MAT_KEYS[ value ] = "mat." .. string.lower( name ) end
end

function DTS.SurfaceName( tr )

	if ( !tr or !tr.Hit ) then return "" end

	local key = MAT_KEYS[ tr.MatType or -1 ]
	if ( key and DTS.HasPhrase( key ) ) then return DTS.L( key ) end

	return DTS.SurfacePropName( tr )

end

--[[
	Upper case beyond ASCII: Latin-1, Latin Extended-A, Greek and Cyrillic (string.upper only knows A-Z).
	Turkish writes the capital of i as İ.
]]
local function UpperCode( c, turkish )

	if ( c >= 97 and c <= 122 ) then
		if ( c == 105 and turkish ) then return 0x130 end
		return c - 32
	end
	if ( c < 0xE0 ) then return c end
	if ( c <= 0xFE ) then return c == 0xF7 and c or c - 32 end -- Latin-1 (not the division sign)
	if ( c == 0xFF ) then return 0x178 end
	if ( c >= 0x100 and c <= 0x17F ) then
		if ( c == 0x131 ) then return 73 end -- dotless i
		if ( c == 0x17F ) then return 83 end -- long s
		if ( ( c >= 0x139 and c <= 0x148 ) or ( c >= 0x179 and c <= 0x17E ) ) then
			return c % 2 == 0 and c - 1 or c -- these pairs start on an odd code point
		end
		if ( c == 0x138 or c == 0x149 ) then return c end
		return c % 2 == 1 and c - 1 or c
	end
	if ( c >= 0x3B1 and c <= 0x3C9 ) then return c == 0x3C2 and 0x3A3 or c - 32 end -- Greek
	if ( c >= 0x3AC and c <= 0x3AF ) then return ( { [ 0x3AC ] = 0x386, [ 0x3AD ] = 0x388, [ 0x3AE ] = 0x389, [ 0x3AF ] = 0x38A } )[ c ] end
	if ( c >= 0x430 and c <= 0x44F ) then return c - 32 end -- Cyrillic
	if ( c >= 0x450 and c <= 0x45F ) then return c - 80 end
	if ( c >= 0x460 and c <= 0x4FF and c % 2 == 1 ) then return c - 1 end -- e.g. Ukrainian ґ
	return c

end

function DTS.Upper( str )

	local turkish = DTS.LangCode == "tr"
	local out = {}
	for _, c in utf8.codes( str ) do
		out[ #out + 1 ] = utf8.char( UpperCode( c, turkish ) )
	end
	return table.concat( out )

end

--[[---------------------------------------------------------
	Tool helpers
-----------------------------------------------------------]]

function DTS.ToolName( mode )

	if ( !mode or mode == "" ) then return "" end

	local phrase = DTS.Phrase( "tool." .. mode .. ".name" )
	if ( phrase ) then return phrase end

	local tool = DTS.GetToolTable( mode )
	if ( tool and isstring( tool.Name ) ) then return DTS.Localize( tool.Name ) end

	return mode

end

-- The category's name exactly as the spawn menu shows it ("Render" is shown as #spawnmenu.tools.render).
local categoryText = {}

hook.Add( "PostReloadToolsMenu", "DTScreen_Categories", function() categoryText = {} end )

function DTS.ToolCategory( mode )

	local tool = DTS.GetToolTable( mode )
	if ( !tool or !isstring( tool.Category ) ) then return "" end

	local cat = tool.Category
	local text = categoryText[ cat ]
	if ( text == nil ) then
		text = false
		for _, tab in ipairs( spawnmenu.GetTools() or {} ) do
			for _, c in ipairs( tab.Items or {} ) do
				if ( c.ItemName == cat and isstring( c.Text ) ) then text = c.Text break end
			end
			if ( text ) then break end
		end
		categoryText[ cat ] = text
	end

	return DTS.Localize( text or cat )

end

local function ToolStage( ctx )

	local w = ctx.weapon
	if ( !IsValid( w ) ) then return 0, 0 end
	return w:GetNWInt( "Stage", 0 ), w:GetNWInt( "Op", 0 )

end

DTS.ToolStage = ToolStage

local function HintIcon( name )

	if ( string.StartWith( name, "left" ) ) then return "lmb" end
	if ( string.StartWith( name, "right" ) ) then return "rmb" end
	if ( string.StartWith( name, "reload" ) ) then return "reload" end
	if ( string.StartWith( name, "use" ) ) then return "use" end
	return "info"

end

-- The current stage's Information entries as { { icon, text }, ... } (the same data the HUD shows).
function DTS.ToolHints( ctx )

	local tool, mode = ctx.tool, ctx.mode
	if ( !tool ) then return {} end

	local stage, op = ToolStage( ctx )
	local out = {}

	if ( istable( tool.Information ) ) then

		for _, v in pairs( tool.Information ) do
			if ( isstring( v ) ) then v = { name = v } end

			local name = istable( v ) and v.name
			if ( name and ( !v.stage or v.stage == stage ) and ( !v.op or v.op == op ) ) then
				local text
				if ( name == "info" ) then
					text = DTS.Phrase( "tool." .. mode .. "." .. stage )
				else
					text = DTS.Phrase( "tool." .. mode .. "." .. name )
				end
				if ( text ) then out[ #out + 1 ] = { name = name, icon = HintIcon( name ), text = text } end
			end
		end

	end

	if ( #out == 0 ) then
		local text = DTS.Phrase( "tool." .. mode .. "." .. stage )
		if ( text ) then out[ 1 ] = { name = "info", icon = "info", text = text } end
	end

	return out

end

--[[---------------------------------------------------------
	Tokens
	Descriptions and categories are phrase keys ("#token.<name>", "#category.<name>"), shown in the
	menu in the player's language.
-----------------------------------------------------------]]

local function T( name, fn, category, example )
	DTS.RegisterToken( name, fn, "#token." .. name, "#category." .. category, example )
end

-- Text ------------------------------------------------------

T( "tr", function( ctx, arg )

	arg = string.Trim( arg or "" )
	if ( arg == "" ) then return "" end

	local key = ( DTS.HasPhrase( "tpl." .. arg ) and "tpl." .. arg ) or ( DTS.HasPhrase( arg ) and arg )
	if ( !key ) then return "{tr:" .. arg .. "?}" end

	-- a phrase may contain tokens, even {tr:...}; stop runaway nesting
	ctx.trDepth = ( ctx.trDepth or 0 ) + 1
	local runs = ctx.trDepth <= 4 and DTS.EvalTemplate( DTS.L( key ), ctx ) or nil
	ctx.trDepth = ctx.trDepth - 1

	return runs or ""

end, "text", "Back to Rope" )

-- Time ------------------------------------------------------

T( "time", function( ctx, arg )
	if ( arg and arg != "" ) then return DTS.SafeDate( arg, ctx.time ) end
	return DTS.ClockRuns( ctx.time )
end, "time", "3:48" )

T( "date", function( ctx, arg )
	if ( arg and arg != "" ) then return DTS.SafeDate( arg, ctx.time ) end
	return DTS.FormatDate( ctx.time )
end, "time", "Fri 23 Oct" )

T( "session", function( ctx )
	return DTS.FormatDuration( SysTime() - ( DTS.SessionStart or SysTime() ) )
end, "time", "1h 05m" )

T( "map_time", function()
	return DTS.FormatDuration( CurTime() )
end, "time", "12m 30s" )

-- Tool ------------------------------------------------------

T( "tool", function( ctx )
	local name = DTS.ToolName( ctx.mode )
	if ( DTS.GetBool( "hero_upper" ) ) then name = DTS.Upper( name ) end
	return name
end, "tool", "Weld" )

T( "tool_id", function( ctx ) return ctx.mode end, "tool", "weld" )

T( "tool_desc", function( ctx )
	return DTS.Phrase( "tool." .. ctx.mode .. ".desc" ) or ""
end, "tool" )

T( "tool_category", function( ctx ) return DTS.ToolCategory( ctx.mode ) end, "tool", "Constraints" )

T( "tool_stage", function( ctx ) return ( ToolStage( ctx ) ) end, "tool", "1" )

T( "tool_progress", function( ctx )
	local stage = ToolStage( ctx )
	if ( stage <= 0 ) then return "" end
	return DTS.L( "tool.progress", { n = stage + 1 } )
end, "tool", "Stage 2" )

T( "tool_prev", function( ctx )
	local prev = DTS.PreviousTool and DTS.PreviousTool()
	return prev and DTS.ToolName( prev ) or ""
end, "tool", "Rope" )

T( "tool_next", function( ctx )
	local nxt = DTS.NextTool and DTS.NextTool( ctx.mode, 1 )
	return nxt and DTS.ToolName( nxt ) or ""
end, "tool", "Winch" )

T( "tool_uses", function() return DTS.ToolUses or 0 end, "tool", "42" )

T( "tool_cvar", function( ctx, arg )
	arg = string.Trim( arg or "" )
	if ( arg == "" ) then return "" end
	local cv = GetConVar( ctx.mode .. "_" .. arg )
	return cv and cv:GetString() or ""
end, "tool", "0" )

T( "tool_settings", function( ctx )
	local tool = ctx.tool
	if ( !tool or !istable( tool.ClientConVar ) ) then return "" end
	local keys = table.GetKeys( tool.ClientConVar )
	table.sort( keys )
	local out = {}
	for _, k in ipairs( keys ) do
		local cv = GetConVar( ctx.mode .. "_" .. k )
		if ( cv ) then
			local v = cv:GetString()
			if ( #v > 24 ) then v = string.GetFileFromFilename( v ) end
			out[ #out + 1 ] = k .. "=" .. v
		end
	end
	return table.concat( out, "  " )
end, "tool", "forcelimit=0  nocollide=0" )

T( "hints", function( ctx )
	local runs = {}
	for i, h in ipairs( DTS.ToolHints( ctx ) ) do
		if ( i > 1 ) then runs[ #runs + 1 ] = { "     " } end
		runs[ #runs + 1 ] = { icon = h.icon }
		runs[ #runs + 1 ] = { " " .. h.text }
	end
	return runs
end, "tool", "[LMB] Select the first object" )

local function HintFor( prefix )
	return function( ctx )
		for _, h in ipairs( DTS.ToolHints( ctx ) ) do
			if ( string.StartWith( h.name, prefix ) ) then return h.text end
		end
		return ""
	end
end

T( "hint_left", HintFor( "left" ), "tool" )
T( "hint_right", HintFor( "right" ), "tool" )
T( "hint_reload", HintFor( "reload" ), "tool" )

-- Aim -------------------------------------------------------

local function Aimed( ctx )
	local tr = ctx.tr
	return tr and tr.Hit and !tr.HitSky and tr or nil
end

T( "target", function( ctx )
	local tr = ctx.tr
	if ( !tr ) then return "" end
	if ( IsValid( ctx.ent ) ) then return DTS.LRuns( "target.entity", { name = DTS.EntityName( ctx.ent ) } ) end
	if ( tr.HitSky ) then return DTS.LRuns( "target.sky" ) end
	if ( tr.Hit ) then
		local surface = DTS.SurfaceName( tr )
		if ( surface != "" ) then return DTS.LRuns( "target.world_surface", { surface = surface } ) end
		return DTS.LRuns( "target.world" )
	end
	return DTS.LRuns( "target.nothing" )
end, "aim", "Aiming at oildrum001" )

T( "aim_what", function( ctx )
	if ( IsValid( ctx.ent ) ) then return DTS.EntityName( ctx.ent ) end
	local tr = Aimed( ctx )
	if ( !tr ) then return ctx.tr and ctx.tr.HitSky and DTS.L( "aim.sky" ) or "" end
	return DTS.SurfaceName( tr )
end, "aim", "Concrete" )

T( "aim_pos", function( ctx ) local tr = Aimed( ctx ) return tr and DTS.FormatVector( tr.HitPos ) or "" end, "aim", "512, -1203, 64" )
T( "aim_x", function( ctx ) local tr = Aimed( ctx ) return tr and Int( tr.HitPos.x ) or "" end, "aim" )
T( "aim_y", function( ctx ) local tr = Aimed( ctx ) return tr and Int( tr.HitPos.y ) or "" end, "aim" )
T( "aim_z", function( ctx ) local tr = Aimed( ctx ) return tr and Int( tr.HitPos.z ) or "" end, "aim" )

T( "aim_dist", function( ctx )
	local tr = Aimed( ctx )
	return tr and DTS.FormatDistance( tr.HitPos:Distance( tr.StartPos ) ) or ""
end, "aim", "12.4 m" )

T( "aim_normal", function( ctx )
	local tr = Aimed( ctx )
	if ( !tr ) then return "" end
	local n = tr.HitNormal
	return DTS.FormatNumber( n.x, 2 ) .. " " .. DTS.FormatNumber( n.y, 2 ) .. " " .. DTS.FormatNumber( n.z, 2 )
end, "aim", "0.00 0.00 1.00" )

T( "aim_slope", function( ctx )
	local tr = Aimed( ctx )
	if ( !tr ) then return "" end
	return Round( math.deg( math.acos( Clamp( tr.HitNormal.z, -1, 1 ) ) ) ) .. utf8.char( 176 )
end, "aim", "30" .. utf8.char( 176 ) )

T( "aim_surface", function( ctx ) return DTS.SurfaceName( Aimed( ctx ) ) end, "aim", "Metal" )
T( "aim_surfaceprop", function( ctx ) return DTS.SurfacePropName( Aimed( ctx ) ) end, "aim", "metal box" )

T( "aim_texture", function( ctx )
	local tr = Aimed( ctx )
	if ( !tr or !tr.HitTexture or string.sub( tr.HitTexture, 1, 2 ) == "**" ) then return "" end
	return string.lower( tr.HitTexture )
end, "aim", "concrete/concretefloor023a" )

-- Aimed entity ------------------------------------------------

local function E( fn )
	return function( ctx, arg ) if ( IsValid( ctx.ent ) ) then return fn( ctx.ent, ctx, arg ) end return "" end
end

T( "ent_name", E( function( ent ) return DTS.EntityName( ent ) end ), "entity", "oildrum001" )
T( "ent_class", E( function( ent ) return ent:GetClass() end ), "entity", "prop_physics" )
T( "ent_model", E( function( ent ) return DTS.ModelName( ent ) or "" end ), "entity", "oildrum001" )
T( "ent_model_path", E( function( ent ) return ent:GetModel() or "" end ), "entity", "models/props_c17/oildrum001.mdl" )
T( "ent_index", E( function( ent ) return ent:EntIndex() end ), "entity", "142" )
T( "ent_health", E( function( ent ) return DTS.EntityHealth( ent ) end ), "entity", "40/40" )
T( "ent_owner", E( function( ent ) return DTS.EntityOwner( ent ) end ), "entity", "Garry" )
T( "ent_material", E( function( ent )
	local m = ent:GetMaterial()
	if ( m == "" ) then m = ent:GetMaterials()[ 1 ] or "" end
	return string.GetFileFromFilename( m )
end ), "entity", "oildrum001" )
T( "ent_color", E( function( ent ) local c = ent:GetColor() return format( "%d %d %d %d", c.r, c.g, c.b, c.a ) end ), "entity", "255 255 255 255" )
T( "ent_skin", E( function( ent ) return ent:GetSkin() end ), "entity", "0" )
T( "ent_speed", E( function( ent ) return DTS.FormatSpeed( ent:GetVelocity():Length() ) end ), "entity", "12 km/h" )
T( "ent_pos", E( function( ent ) return DTS.FormatVector( ent:GetPos() ) end ), "entity" )
T( "ent_ang", E( function( ent ) local a = ent:GetAngles() return Int( a.p ) .. ", " .. Int( a.y ) .. ", " .. Int( a.r ) end ), "entity", "0, 90, 0" )
T( "ent_mass", E( function( ent )
	local phys = ent:GetPhysicsObject()
	if ( !IsValid( phys ) ) then return "" end
	return DTS.FormatUnit( "kg", phys:GetMass(), 0 )
end ), "entity", "30 kg" )

-- Tracked entity (dts_track or the Dynamic Toolgun Screen tool) ---

local function Tracked( fn )
	return function( ctx, arg ) if ( IsValid( ctx.track ) ) then return fn( ctx.track, ctx, arg ) end return "" end
end

T( "track", Tracked( function( ent, ctx )
	local runs = { { icon = "pin" }, { " " }, { DTS.EntityName( ent ), true } }
	if ( IsValid( ctx.ply ) ) then runs[ #runs + 1 ] = { "  " .. DTS.FormatDistance( ent:GetPos():Distance( ctx.ply:GetPos() ) ) } end
	local speed = ent:GetVelocity():Length()
	if ( speed > 1 ) then runs[ #runs + 1 ] = { "  " .. DTS.FormatSpeed( speed ) } end
	local hp = DTS.EntityHealth( ent )
	if ( hp != "" ) then runs[ #runs + 1 ] = { "  " .. DTS.L( "track.hp", { hp = hp } ) } end
	return runs
end ), "tracked", "oildrum001  12.4 m" )

T( "track_name", Tracked( function( ent ) return DTS.EntityName( ent ) end ), "tracked" )
T( "track_class", Tracked( function( ent ) return ent:GetClass() end ), "tracked" )
T( "track_dist", Tracked( function( ent, ctx ) return IsValid( ctx.ply ) and DTS.FormatDistance( ent:GetPos():Distance( ctx.ply:GetPos() ) ) or "" end ), "tracked" )
T( "track_speed", Tracked( function( ent ) return DTS.FormatSpeed( ent:GetVelocity():Length() ) end ), "tracked" )
T( "track_health", Tracked( function( ent ) return DTS.EntityHealth( ent ) end ), "tracked" )
T( "track_pos", Tracked( function( ent ) return DTS.FormatVector( ent:GetPos() ) end ), "tracked" )

-- Player ----------------------------------------------------

local function P( fn )
	return function( ctx, arg ) if ( IsValid( ctx.ply ) ) then return fn( ctx.ply, ctx, arg ) end return "" end
end

T( "player", P( function( ply ) return ply:Nick() end ), "player", "Garry" )
T( "health", P( function( ply ) return ply:Health() end ), "player", "100" )
T( "armor", P( function( ply ) return ply:Armor() end ), "player", "0" )
T( "speed", P( function( ply ) return DTS.FormatSpeed( ply:GetVelocity():Length() ) end ), "player", "18 km/h" )
T( "pos", P( function( ply ) return DTS.FormatVector( ply:GetPos() ) end ), "player", "-1024, 512, 0" )
T( "eye_ang", P( function( ply ) local a = ply:EyeAngles() return DTS.L( "eye_ang", { p = Int( a.p ), y = Int( a.y ) } ) end ), "player", "P 12  Y 270" )

local COMPASS = { "n", "ne", "e", "se", "s", "sw", "w", "nw" }
T( "heading", P( function( ply )
	local deg = ( 90 - ply:EyeAngles().y ) % 360
	return DTS.L( "heading", { dir = DTS.L( "compass." .. COMPASS[ floor( ( deg + 22.5 ) / 45 ) % 8 + 1 ] ), deg = Round( deg ) % 360 } )
end ), "player", "NE 45" .. utf8.char( 176 ) )

T( "noclip", P( function( ply ) return ply:GetMoveType() == MOVETYPE_NOCLIP and DTS.L( "noclip" ) or "" end ), "player", "Noclip" )

-- Game / server ----------------------------------------------

T( "fps", function() return Round( DTS.FPS or 0 ) end, "game", "144" )
T( "ping", P( function( ply ) return ply:Ping() end ), "game", "35" )

-- the device's battery (see DTS.Battery in cl_features.lua)
T( "battery", function()
	local b = DTS.Battery()
	return b.level and DTS.BatteryText( b.level ) or DTS.L( "battery.plugged" )
end, "game", "85%" )
T( "map", function() return game.GetMap() end, "game", "gm_construct" )
T( "players", function() return player.GetCount() .. "/" .. game.MaxPlayers() end, "game", "3/16" )
T( "server", function() return GetHostName() end, "game" )
T( "gamemode", function() return engine.ActiveGamemode() end, "game", "sandbox" )
T( "tickrate", function() return Round( 1 / engine.TickInterval() ) end, "game", "66" )
T( "lua_mem", function() return DTS.FormatUnit( "mb", collectgarbage( "count" ) / 1024, 1 ) end, "game", "85.2 MB" )
T( "entities", function() return ents.GetCount() end, "game", "512" )

local function Limit( kind )
	local cv = GetConVar( "sbox_max" .. kind )
	return cv and cv:GetInt() or nil
end

T( "props", P( function( ply ) return ply:GetCount( "props" ) end ), "game", "12" )
T( "props_max", function() return Limit( "props" ) or "" end, "game", "200" )
T( "count", P( function( ply, ctx, arg )
	if ( !arg or arg == "" ) then return "" end
	arg = string.Trim( arg )
	local max = Limit( arg )
	return ply:GetCount( arg ) .. ( max and ( "/" .. max ) or "" )
end ), "game", "3/10" )

T( "cvar", function( ctx, arg )
	if ( !arg or arg == "" ) then return "" end
	local cv = GetConVar( string.Trim( arg ) )
	return cv and cv:GetString() or ""
end, "game", "600" )
