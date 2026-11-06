--[[
	Terminal layout
	A dense developer readout: eight key/value lines, an FPS graph and a prompt line.
	In templates, **highlighted** text uses the bright terminal colour. A tab splits a line into a label
	and a value; values line up after the widest label, whatever the language and font.
]]

local DTS = DTScreen

local LAYOUT = {
	Name = "#layout.terminal.name",
	Description = "#layout.terminal.desc",
	Background = "term",
	Slots = {
		{ id = "head", label = "#layout.terminal.head", default = "DTS://{tool_id}" },
		{ id = "clock", label = "#layout.terminal.clock", default = "{time:%H:%M:%S}" },
		{ id = "l1", label = "#layout.terminal.l1", default = "{tr:term_tool}" },
		{ id = "l2", label = "#layout.terminal.l2", default = "{tr:term_aim}" },
		{ id = "l3", label = "#layout.terminal.l3", default = "{tr:term_class}" },
		{ id = "l4", label = "#layout.terminal.l4", default = "{tr:term_pos}" },
		{ id = "l5", label = "#layout.terminal.l5", default = "{tr:term_dist}" },
		{ id = "l6", label = "#layout.terminal.l6", default = "{tr:term_owner}" },
		{ id = "l7", label = "#layout.terminal.l7", default = "{tr:term_hp}" },
		{ id = "l8", label = "#layout.terminal.l8", default = "{tr:term_track}" },
		{ id = "foot", label = "#layout.terminal.foot", default = "{hints}" },
	}
}

-- runs -> label runs, value runs (split at the first tab), cached per evaluated line
local splitCache = setmetatable( {}, { __mode = "k" } )

local function SplitAtTab( runs )

	local cached = splitCache[ runs ]
	if ( cached ) then return cached[ 1 ], cached[ 2 ] end

	local left, right = nil, runs
	for i, r in ipairs( runs ) do
		local text = !r.icon and !r.ghost and r[ 1 ]
		local a = isstring( text ) and string.find( text, "\t", 1, true )
		if ( a ) then
			left, right = {}, {}
			for j = 1, i - 1 do left[ #left + 1 ] = runs[ j ] end
			local before = string.sub( text, 1, a - 1 )
			local after = string.gsub( string.sub( text, a + 1 ), "\t", " " )
			if ( before != "" ) then left[ #left + 1 ] = { before, r[ 2 ] } end
			if ( after != "" ) then right[ #right + 1 ] = { after, r[ 2 ] } end
			for j = i + 1, #runs do right[ #right + 1 ] = runs[ j ] end
			break
		end
	end

	splitCache[ runs ] = { left, right }
	return left, right

end

function LAYOUT:Draw( D, ctx, T, slots )

	local mono = DTS.FontFace( "mono" )
	local now = RealTime()

	-- header bar
	D.Rect( 0, 0, 256, 20, T.term_fg )
	local head = { face = mono, size = 14, weight = 700, color = T.term_bg, hl = T.term_bg, overflow = "ellipsis" }
	D.Line( slots.head, 4, 0, 150, 20, head )
	head.align = 2
	D.Line( slots.clock, 150, 0, 102, 20, head )

	-- key / value lines
	local line = { face = mono, size = 15, weight = 500, color = T.term_fg, hl = T.term_hl, overflow = "ellipsis" }

	local column = 0
	for i = 1, 8 do
		local runs = slots[ "l" .. i ]
		local left = runs and SplitAtTab( runs )
		if ( left ) then column = math.max( column, D.MeasureLine( left, line ) ) end
	end
	column = math.Clamp( column + 8, 40, 120 )

	for i = 1, 8 do
		local runs = slots[ "l" .. i ]
		local y = 22 + ( i - 1 ) * 22
		if ( runs ) then
			local left, right = SplitAtTab( runs )
			if ( left ) then
				D.Line( left, 4, y, column - 6, 22, line )
				D.Line( right, 4 + column, y, 248 - column, 22, line )
			else
				D.Line( right, 4, y, 248, 22, line )
			end
		end
	end

	-- FPS graph
	local hist = DTS.FPSHistory or {}
	local gx, gy, gw, gh = 4, 202, 200, 24
	D.Rect( gx, gy + gh, gw, 1, T.term_dim )

	local peak = 30
	for _, v in ipairs( hist ) do peak = math.max( peak, v ) end

	local n = #hist
	if ( n > 1 ) then
		local bw = gw / 60
		for i = 1, n do
			local v = hist[ i ]
			local h = math.max( 1, v / peak * gh )
			D.Rect( gx + gw - ( n - i + 1 ) * bw, gy + gh - h, math.max( bw - 0.5, 1 ), h, i == n and T.term_hl or T.term_dim )
		end
	end

	D.Line( DTS.L( "term.fps", { n = math.Round( DTS.FPS or 0 ) } ), 208, gy, 44, gh, { face = mono, size = 12, color = T.term_fg, align = 2, overflow = "clip" } )

	-- prompt line
	D.Rect( 0, 230, 256, 1, T.term_dim )
	local promptFont = D.Font( mono, 15, 700 )
	D.Text( ">", promptFont, 4, 243, T.term_hl, 0, 1 )

	local note = DTS.ActiveNotification( now )
	local runs = note and note.runs or slots.foot
	if ( runs ) then
		D.Line( runs, 16, 231, 236, 25, { face = mono, size = 14, color = T.term_fg, hl = T.term_hl, overflow = "marquee", speed = 40, alpha = note and note.alpha or 1 } )
	elseif ( now % 1 < 0.5 ) then
		D.Rect( 17, 236, 8, 14, T.term_fg )
	end

end

DTS.RegisterLayout( "terminal", LAYOUT )
