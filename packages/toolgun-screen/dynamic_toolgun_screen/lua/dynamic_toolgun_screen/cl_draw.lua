--[[
	Dynamic Toolgun Screen - drawing helpers

	Layouts draw in a fixed 256 x 256 "design space" (the size of the original screen texture).
	These helpers scale everything to the real render target size (D.S = pixels per design unit),
	so a layout looks the same at 256 and 512 and fonts stay sharp at both.
]]

local DTS = DTScreen
local D = DTS.Draw or {}
DTS.Draw = D

D.S = 1
D.W = 256
D.H = 256

local floor, ceil, max, min, Round, Clamp = math.floor, math.ceil, math.max, math.min, math.Round, math.Clamp
local sin, cos, pi = math.sin, math.cos, math.pi
local SetDrawColor, DrawRect, DrawTexturedRect, DrawTexturedRectUV = surface.SetDrawColor, surface.DrawRect, surface.DrawTexturedRect, surface.DrawTexturedRectUV
local SetFont, GetTextSize, SetTextColor, SetTextPos, DrawText = surface.SetFont, surface.GetTextSize, surface.SetTextColor, surface.SetTextPos, surface.DrawText
local SetMaterial, DrawPoly = surface.SetMaterial, surface.DrawPoly

local function px( v )
	return floor( v * D.S + 0.5 )
end
D.px = px

function D.Begin( size )
	D.S = size / 256
	D.Alpha = 1
end

--[[---------------------------------------------------------
	Fonts: created on demand for the current scale and cached.
-----------------------------------------------------------]]

local fontCache = {}

function D.Font( face, size, weight, italic )

	weight = weight or 500

	-- the language's own fonts (CJK) can ask for a size factor and plain 400/700 weights
	local adj = DTS.FontAdjust and DTS.FontAdjust( face )
	if ( adj ) then
		size = size * adj.scale
		if ( adj.snap ) then weight = weight >= 600 and 700 or 400 end
	end

	local pxsize = max( 6, Round( size * D.S ) )

	-- called a few dozen times per redraw: look up without building strings
	local byFace = fontCache[ face ]
	if ( !byFace ) then byFace = {} fontCache[ face ] = byFace end

	local k = pxsize * 10000 + weight * 2 + ( italic and 1 or 0 )
	local name = byFace[ k ]
	if ( name ) then return name end

	local key = face .. "|" .. pxsize .. "|" .. weight .. ( italic and "|i" or "" )
	name = "DTScreen_" .. util.CRC( key )
	surface.CreateFont( name, {
		font = face,
		size = pxsize,
		weight = weight,
		italic = italic or false,
		antialias = true,
		extended = true
	} )

	byFace[ k ] = name
	return name

end

--[[---------------------------------------------------------
	Shapes
-----------------------------------------------------------]]

local function SetColor( col, a )
	SetDrawColor( col.r, col.g, col.b, ( a or col.a or 255 ) * D.Alpha )
end
D.SetColor = SetColor

function D.Rect( x, y, w, h, col, a )

	local x1, y1 = px( x ), px( y )
	SetColor( col, a )
	DrawRect( x1, y1, px( x + w ) - x1, px( y + h ) - y1 )

end

function D.Outline( x, y, w, h, col, t )

	t = t or 1
	D.Rect( x, y, w, t, col )
	D.Rect( x, y + h - t, w, t, col )
	D.Rect( x, y + t, t, h - t * 2, col )
	D.Rect( x + w - t, y + t, t, h - t * 2, col )

end

local matGradDown = Material( "gui/gradient_down" ) -- opaque at the top
local matGradRight = Material( "gui/gradient" ) -- opaque on the left

function D.Material( mat, x, y, w, h, col, u0, v0, u1, v1 )

	local x1, y1 = px( x ), px( y )
	SetMaterial( mat )
	SetColor( col or color_white )

	if ( u0 ) then
		DrawTexturedRectUV( x1, y1, px( x + w ) - x1, px( y + h ) - y1, u0, v0, u1, v1 )
	else
		DrawTexturedRect( x1, y1, px( x + w ) - x1, px( y + h ) - y1 )
	end

end

-- Vertical gradient from top to bottom.
function D.VGradient( x, y, w, h, top, bottom )

	D.Rect( x, y, w, h, bottom )
	D.Material( matGradDown, x, y, w, h, top )

end

-- Horizontal gradient from left to right.
function D.HGradient( x, y, w, h, left, right )

	D.Rect( x, y, w, h, right )
	D.Material( matGradRight, x, y, w, h, left )

end

function D.RoundedBox( r, x, y, w, h, col )

	local x1, y1 = px( x ), px( y )
	draw.RoundedBox( max( 0, px( r ) ), x1, y1, px( x + w ) - x1, px( y + h ) - y1, Color( col.r, col.g, col.b, ( col.a or 255 ) * D.Alpha ) )

end

-- surface.DrawPoly wants clockwise vertices (screen space, y down).
local function Clockwise( pts )

	local area = 0
	for i = 1, #pts do
		local a, b = pts[ i ], pts[ i % #pts + 1 ]
		area = area + ( a.x * b.y - b.x * a.y )
	end

	if ( area >= 0 ) then return pts end

	local rev = {}
	for i = #pts, 1, -1 do rev[ #rev + 1 ] = pts[ i ] end
	return rev

end

local function PolyPx( pts, col )

	draw.NoTexture()
	SetColor( col )
	DrawPoly( Clockwise( pts ) )

end

-- Icons are redrawn up to dts_fps times a second: their polygons are built once per size and reused.
local shapeCache, shapeCount = {}, 0

local function StoreShape( key, polys )

	for i, p in ipairs( polys ) do polys[ i ] = Clockwise( p ) end

	shapeCount = shapeCount + 1
	if ( shapeCount > 400 ) then shapeCache, shapeCount = {}, 0 end
	shapeCache[ key ] = polys

	return polys

end

local function DrawShape( polys, col )

	draw.NoTexture()
	SetColor( col )
	for i = 1, #polys do DrawPoly( polys[ i ] ) end

end

--[[
	Round shapes are stored around (0, 0) and moved into place when drawn, so an icon that moves
	(inside a scrolling line) reuses its shape instead of building a new one every frame.
	Each polygon keeps a second set of vertices that is overwritten with the moved positions.
]]
local function StoreShapeAt( key, polys )

	polys = StoreShape( key, polys )
	for _, p in ipairs( polys ) do
		if ( !p.moved ) then
			p.moved = {}
			for j = 1, #p do p.moved[ j ] = { x = 0, y = 0 } end
		end
	end
	return polys

end

local function DrawShapeAt( polys, ox, oy, col )

	draw.NoTexture()
	SetColor( col )
	for i = 1, #polys do
		local p = polys[ i ]
		local m = p.moved
		for j = 1, #p do
			local v, src = m[ j ], p[ j ]
			v.x, v.y = src.x + ox, src.y + oy
		end
		DrawPoly( m )
	end

end

-- Points are given in design units.
function D.Poly( pts, col )

	local out = {}
	for i, p in ipairs( pts ) do out[ i ] = { x = p[ 1 ] * D.S, y = p[ 2 ] * D.S } end
	PolyPx( out, col )

end

local function ThickLinePx( x1, y1, x2, y2, t, col )

	local dx, dy = x2 - x1, y2 - y1
	local len = math.sqrt( dx * dx + dy * dy )
	if ( len <= 0 ) then return end

	local nx, ny = -dy / len * t * 0.5, dx / len * t * 0.5
	PolyPx( {
		{ x = x1 + nx, y = y1 + ny },
		{ x = x2 + nx, y = y2 + ny },
		{ x = x2 - nx, y = y2 - ny },
		{ x = x1 - nx, y = y1 - ny }
	}, col )

end

function D.ThickLine( x1, y1, x2, y2, t, col )
	ThickLinePx( x1 * D.S, y1 * D.S, x2 * D.S, y2 * D.S, t * D.S, col )
end

local function CirclePx( cx, cy, r, col, seg )

	seg = seg or 20
	local key = string.format( "c%.2f|%d", r, seg )
	local polys = shapeCache[ key ]

	if ( !polys ) then
		local pts = {}
		for i = 0, seg - 1 do
			local a = i / seg * pi * 2
			pts[ #pts + 1 ] = { x = cos( a ) * r, y = sin( a ) * r }
		end
		polys = StoreShapeAt( key, { pts } )
	end

	DrawShapeAt( polys, cx, cy, col )

end

function D.Circle( cx, cy, r, col, seg )
	CirclePx( cx * D.S, cy * D.S, r * D.S, col, seg )
end

-- Ring segment between angles a0 and a1 (radians, 0 = right, clockwise).
local function ArcPx( cx, cy, r, t, a0, a1, col, seg )

	seg = seg or 8
	local key = string.format( "a%.2f|%.2f|%.3f|%.3f|%d", r, t, a0, a1, seg )
	local polys = shapeCache[ key ]

	if ( !polys ) then
		polys = {}
		local ri, ro = r - t * 0.5, r + t * 0.5
		for i = 0, seg - 1 do
			local s0 = a0 + ( a1 - a0 ) * i / seg
			local s1 = a0 + ( a1 - a0 ) * ( i + 1 ) / seg
			polys[ #polys + 1 ] = {
				{ x = cos( s0 ) * ro, y = sin( s0 ) * ro },
				{ x = cos( s1 ) * ro, y = sin( s1 ) * ro },
				{ x = cos( s1 ) * ri, y = sin( s1 ) * ri },
				{ x = cos( s0 ) * ri, y = sin( s0 ) * ri }
			}
		end
		polys = StoreShapeAt( key, polys )
	end

	DrawShapeAt( polys, cx, cy, col )

end

function D.Arc( cx, cy, r, t, a0, a1, col, seg )
	ArcPx( cx * D.S, cy * D.S, r * D.S, t * D.S, a0, a1, col, seg )
end

--[[---------------------------------------------------------
	Clipping
-----------------------------------------------------------]]

function D.ClipPx( x, y, w, h )
	render.SetScissorRect( x, y, x + w, y + h, true )
end

function D.Clip( x, y, w, h )
	render.SetScissorRect( px( x ), px( y ), px( x + w ), px( y + h ), true )
end

function D.Unclip()
	render.SetScissorRect( 0, 0, 0, 0, false )
end

--[[---------------------------------------------------------
	Simple text
	ax: 0 left, 1 centre, 2 right. ay: 0 top, 1 centre, 2 bottom.
	Returns the text size in design units.
-----------------------------------------------------------]]

function D.TextSize( text, font )

	SetFont( font )
	local w, h = GetTextSize( text )
	return w / D.S, h / D.S

end

function D.Text( text, font, x, y, col, ax, ay, shadow, so )

	SetFont( font )
	local tw, th = GetTextSize( text )
	local X, Y = px( x ), px( y )

	if ( ax == 1 ) then X = X - floor( tw / 2 ) elseif ( ax == 2 ) then X = X - tw end
	if ( ay == 1 ) then Y = Y - floor( th / 2 ) elseif ( ay == 2 ) then Y = Y - th end

	if ( shadow ) then
		local o = max( 1, px( so or 1 ) )
		SetTextColor( shadow.r, shadow.g, shadow.b, ( shadow.a or 255 ) * D.Alpha )
		SetTextPos( X + o, Y + o )
		DrawText( text )
	end

	SetTextColor( col.r, col.g, col.b, ( col.a or 255 ) * D.Alpha )
	SetTextPos( X, Y )
	DrawText( text )

	return tw / D.S, th / D.S

end

--[[---------------------------------------------------------
	Icons (pixel space internally)
-----------------------------------------------------------]]

local function Luminance( col )
	return ( col.r * 0.299 + col.g * 0.587 + col.b * 0.114 ) / 255
end
D.Luminance = Luminance

local colBlack, colWhite = Color( 0, 0, 0 ), Color( 255, 255, 255 )

function D.Contrast( col )
	return Luminance( col ) > 0.55 and colBlack or colWhite
end

local function KeyCapPx( letter, X, Y, S, col )

	local w = floor( S * 0.86 )
	local r = max( 1, floor( S * 0.18 ) )
	draw.RoundedBox( r, X, Y + floor( S * 0.06 ), w, floor( S * 0.88 ), Color( col.r, col.g, col.b, ( col.a or 255 ) * D.Alpha ) )

	local font = D.Font( "Tahoma", ( S * 0.66 ) / D.S, 900 )
	SetFont( font )
	local tw, th = GetTextSize( letter )
	local inv = D.Contrast( col )
	SetTextColor( inv.r, inv.g, inv.b, 255 * D.Alpha )
	SetTextPos( X + floor( ( w - tw ) / 2 ), Y + floor( ( S - th ) / 2 ) )
	DrawText( letter )

end

local function MousePx( X, Y, S, col, side )

	local w, h = floor( S * 0.64 ), floor( S * 0.92 )
	local x0, y0 = X + floor( ( S * 0.86 - w ) / 2 ), Y + floor( S * 0.04 )
	local r = max( 1, floor( w * 0.42 ) )

	draw.RoundedBox( r, x0, y0, w, h, Color( col.r, col.g, col.b, 110 * D.Alpha ) )

	-- the pressed button
	local bw, bh = floor( w / 2 ), floor( h * 0.45 )
	local bx = side == "right" and x0 + w - bw or x0
	draw.RoundedBoxEx( r, bx, y0, bw, bh, Color( col.r, col.g, col.b, 255 * D.Alpha ), side != "right", side == "right", false, false )

	SetDrawColor( 0, 0, 0, 120 * D.Alpha )
	DrawRect( x0 + floor( w / 2 ), y0, max( 1, floor( S * 0.05 ) ), bh )

end

local function PinPx( X, Y, S, col )

	local cx, cy = X + S * 0.43, Y + S * 0.5
	ArcPx( cx, cy, S * 0.3, max( 1, S * 0.12 ), 0, pi * 2, col, 16 )
	CirclePx( cx, cy, S * 0.1, col, 10 )

end

local function InfoPx( X, Y, S, col )

	CirclePx( X + S * 0.43, Y + S * 0.5, S * 0.42, col, 18 )

	local font = D.Font( "Georgia", ( S * 0.7 ) / D.S, 900 )
	SetFont( font )
	local tw, th = GetTextSize( "i" )
	local inv = D.Contrast( col )
	SetTextColor( inv.r, inv.g, inv.b, 255 * D.Alpha )
	SetTextPos( X + floor( S * 0.43 - tw / 2 ), Y + floor( ( S - th ) / 2 ) )
	DrawText( "i" )

end

local ICONS = {
	lmb = function( X, Y, S, col ) MousePx( X, Y, S, col, "left" ) end,
	rmb = function( X, Y, S, col ) MousePx( X, Y, S, col, "right" ) end,
	reload = function( X, Y, S, col ) KeyCapPx( "R", X, Y, S, col ) end,
	use = function( X, Y, S, col ) KeyCapPx( "E", X, Y, S, col ) end,
	warn = function( X, Y, S, col ) KeyCapPx( "!", X, Y, S, col ) end,
	undo = function( X, Y, S, col ) KeyCapPx( "Z", X, Y, S, col ) end, -- Z is the default undo key
	info = InfoPx,
	pin = PinPx,
}
D.InlineIcons = ICONS

-- Width an inline icon takes in a line whose text is S pixels tall.
local function IconWidthPx( S )
	return floor( S * 0.86 )
end

function D.Icon( name, x, y, size, col )

	local fn = ICONS[ name ]
	if ( fn ) then fn( px( x ), px( y ), size * D.S, col ) end

end

-- Windows-style four colour flag. t animates a little wave, or nil for a still flag.
local FLAG_COLORS = { Color( 255, 221, 0 ), Color( 52, 199, 46 ), Color( 238, 34, 17 ), Color( 17, 85, 221 ) }

local function FlagTiles( cx, cy, size, t )

	local S = D.S
	local ts, gap = size * 0.44, size * 0.1
	local wave = t and size * 0.07 or 0
	local tiles = {
		{ cx - gap * 0.5 - ts, cy - gap * 0.5 - ts },
		{ cx + gap * 0.5, cy - gap * 0.5 - ts },
		{ cx - gap * 0.5 - ts, cy + gap * 0.5 },
		{ cx + gap * 0.5, cy + gap * 0.5 },
	}

	local polys = {}
	for i, tile in ipairs( tiles ) do
		local x1, y1 = tile[ 1 ], tile[ 2 ]
		local x2, y2 = x1 + ts, y1 + ts
		local o1 = t and sin( t * 6 + x1 * 0.4 ) * wave or 0
		local o2 = t and sin( t * 6 + x2 * 0.4 ) * wave or 0
		polys[ i ] = {
			{ x = x1 * S, y = ( y1 + o1 ) * S },
			{ x = x2 * S, y = ( y1 + o2 ) * S },
			{ x = x2 * S, y = ( y2 + o2 ) * S },
			{ x = x1 * S, y = ( y2 + o1 ) * S }
		}
	end

	return polys

end

function D.Flag( cx, cy, size, t, alpha )

	local polys
	if ( t ) then
		polys = FlagTiles( cx, cy, size, t )
		for i, p in ipairs( polys ) do polys[ i ] = Clockwise( p ) end
	else
		local key = string.format( "f%.2f|%.2f|%.2f|%.2f", cx, cy, size, D.S )
		polys = shapeCache[ key ] or StoreShape( key, FlagTiles( cx, cy, size ) )
	end

	draw.NoTexture()
	for i = 1, 4 do
		local col = FLAG_COLORS[ i ]
		SetDrawColor( col.r, col.g, col.b, 255 * ( alpha or 1 ) * D.Alpha )
		DrawPoly( polys[ i ] )
	end

end

-- Speaker: level 0-3 sound waves, muted draws a cross, talking makes the waves pulse.
function D.Speaker( x, y, s, col, level, muted, talking )

	D.Rect( x, y + s * 0.34, s * 0.2, s * 0.32, col )
	D.Poly( { { x + s * 0.2, y + s * 0.34 }, { x + s * 0.46, y + s * 0.1 }, { x + s * 0.46, y + s * 0.9 }, { x + s * 0.2, y + s * 0.66 } }, col )

	if ( muted ) then
		local t = max( 1.2, s * 0.11 )
		D.ThickLine( x + s * 0.6, y + s * 0.32, x + s * 0.92, y + s * 0.68, t, col )
		D.ThickLine( x + s * 0.6, y + s * 0.68, x + s * 0.92, y + s * 0.32, t, col )
		return
	end

	local pulse = talking and ( 0.55 + 0.45 * sin( RealTime() * 12 ) ) or 1
	for i = 1, 3 do
		if ( i <= level ) then
			local a = ( col.a or 255 ) * ( talking and ( i == level and pulse or 1 ) or 1 )
			D.Arc( x + s * 0.46, y + s * 0.5, s * ( 0.12 + i * 0.15 ), max( 1.1, s * 0.09 ), -pi * 0.3, pi * 0.3, Color( col.r, col.g, col.b, a ), 4 )
		end
	end

end

-- Four signal bars, `bars` of them lit.
function D.Signal( x, y, w, h, col, bars )

	local bw = w / 4
	for i = 1, 4 do
		local bh = h * ( 0.25 + 0.25 * i )
		local a = i <= bars and ( col.a or 255 ) or 70
		D.Rect( x + ( i - 1 ) * bw, y + h - bh, bw - max( 1, bw * 0.3 ), bh, col, a )
	end

end

-- Battery with a fill fraction; turns red when low.
local colLow = Color( 255, 70, 50 )

function D.Battery( x, y, w, h, col, frac )

	local bodyW = w - 2
	D.Outline( x, y, bodyW, h, col, 1 )
	D.Rect( x + bodyW, y + h * 0.3, 2, h * 0.4, col )

	frac = Clamp( frac or 0, 0, 1 )
	if ( frac > 0 ) then
		D.Rect( x + 2, y + 2, ( bodyW - 4 ) * frac, h - 4, frac < 0.25 and colLow or col )
	end

end

-- Mains plug pointing right (the device runs plugged in).
function D.Plug( x, y, w, h, col )

	local t = max( 1, h * 0.14 )
	D.Rect( x, y + h * 0.5 - t * 0.5, w * 0.32, t, col )                -- cable
	D.Rect( x + w * 0.3, y + h * 0.12, w * 0.36, h * 0.76, col )         -- body
	D.Rect( x + w * 0.66, y + h * 0.26, w * 0.32, max( 1, h * 0.16 ), col ) -- prongs
	D.Rect( x + w * 0.66, y + h * 0.58, w * 0.32, max( 1, h * 0.16 ), col )

end

--[[---------------------------------------------------------
	Rich lines
	runs = { { "text", highlight }, { icon = "lmb" }, ... } (a plain string works too)

	style:
		face, size, weight      font, size in design units
		color, hl               normal and highlight colour
		underline               underline highlighted runs
		underlineAll            underline everything (links)
		shadow, shadowOffset    optional drop shadow
		align                   0 left, 1 centre, 2 right
		overflow                "ellipsis" (default), "marquee" (scroll when too long),
		                        "scroll" (always scroll), "fit" (shrink), "clip"
		speed, gap              marquee speed (design units/s) and gap between repeats
		minSize                 smallest size "fit" may use
-----------------------------------------------------------]]

local ELLIPSIS = utf8.char( 0x2026 )

local measureCache = setmetatable( {}, { __mode = "k" } )
local ellipsisCache = setmetatable( {}, { __mode = "k" } )
local fitCache = setmetatable( {}, { __mode = "k" } )

local function MeasureRuns( runs, font )

	local c = measureCache[ runs ]
	if ( c and c.font == font ) then return c.w, c.h, c.widths end

	SetFont( font )
	local _, th = GetTextSize( "Ag" )
	local tw, widths = 0, {}
	for i, run in ipairs( runs ) do
		local w = run.icon and IconWidthPx( th ) or GetTextSize( run[ 1 ] )
		widths[ i ] = w
		tw = tw + w
	end

	measureCache[ runs ] = { font = font, w = tw, h = th, widths = widths }
	return tw, th, widths

end

local function Utf8Prefix( s, n )

	if ( n <= 0 ) then return "" end
	local off = utf8.offset( s, n + 1 )
	if ( !off ) then return s end
	return string.sub( s, 1, off - 1 )

end

local function Ellipsize( runs, font, maxW )

	local c = ellipsisCache[ runs ]
	if ( c and c.font == font and c.maxW == maxW ) then return c.out, c.w end

	SetFont( font )
	local ellW, th = GetTextSize( ELLIPSIS )
	local avail = maxW - ellW
	local out, cx = {}, 0

	for _, run in ipairs( runs ) do

		local rw = run.icon and IconWidthPx( th ) or GetTextSize( run[ 1 ] )

		if ( cx + rw <= avail ) then
			out[ #out + 1 ] = run
			cx = cx + rw
		else
			if ( !run.icon ) then
				local text = run[ 1 ]
				local lo, hi = 0, utf8.len( text ) or #text
				while ( lo < hi ) do
					local mid = ceil( ( lo + hi ) / 2 )
					if ( GetTextSize( Utf8Prefix( text, mid ) ) <= avail - cx ) then lo = mid else hi = mid - 1 end
				end
				if ( lo > 0 ) then
					local part = Utf8Prefix( text, lo )
					out[ #out + 1 ] = { part, run[ 2 ] }
					cx = cx + GetTextSize( part )
				end
			end
			out[ #out + 1 ] = { ELLIPSIS, run[ 2 ] }
			cx = cx + ellW
			break
		end

	end

	ellipsisCache[ runs ] = { font = font, maxW = maxW, out = out, w = cx }
	return out, cx

end

-- widths: the per-run widths from MeasureRuns, so drawing does not measure again
local function DrawRuns( runs, font, X, Y, th, style, alpha, widths )

	SetFont( font )

	local col, hl = style.color or colWhite, style.hl or style.color or colWhite
	local shadow = style.shadow
	local so = shadow and max( 1, px( style.shadowOffset or 1 ) ) or 0
	local ulY, ulT = Y + floor( th * 0.86 ), max( 1, floor( D.S + 0.5 ) )
	local cx = X

	for i, run in ipairs( runs ) do

		local c = run[ 2 ] and hl or col

		if ( run.icon ) then

			local fn = ICONS[ run.icon ]
			local iw = IconWidthPx( th )
			if ( fn ) then fn( cx, Y, th, Color( c.r, c.g, c.b, ( c.a or 255 ) * alpha ) ) end
			cx = cx + iw
			SetFont( font )

		elseif ( run.ghost ) then

			-- takes its space but stays invisible (blinking clock colon)
			cx = cx + ( widths and widths[ i ] or GetTextSize( run[ 1 ] ) )

		else

			local text = run[ 1 ]
			local w = widths and widths[ i ] or GetTextSize( text )

			if ( shadow ) then
				SetTextColor( shadow.r, shadow.g, shadow.b, ( shadow.a or 255 ) * alpha * D.Alpha )
				SetTextPos( cx + so, Y + so )
				DrawText( text )
			end

			SetTextColor( c.r, c.g, c.b, ( c.a or 255 ) * alpha * D.Alpha )
			SetTextPos( cx, Y )
			DrawText( text )

			if ( style.underlineAll or ( run[ 2 ] and style.underline ) ) then
				SetDrawColor( c.r, c.g, c.b, ( c.a or 255 ) * alpha * D.Alpha )
				DrawRect( cx, ulY, w, ulT )
			end

			cx = cx + w

		end

	end

	return cx - X

end

function D.Line( runs, x, y, w, h, style )

	if ( !runs ) then return 0 end
	if ( isstring( runs ) ) then
		if ( runs == "" ) then return 0 end
		runs = { { runs } }
	end
	if ( #runs == 0 ) then return 0 end

	local size = style.size or 14
	local face = style.face or "Tahoma"
	local font = D.Font( face, size, style.weight )
	local overflow = style.overflow or "ellipsis"
	local alpha = style.alpha or 1

	local X0, Y0 = px( x ), px( y )
	local boxW, boxH = px( x + w ) - X0, px( y + h ) - Y0

	if ( overflow == "fit" ) then

		-- pick the largest size that fits; remembered per text so it is searched once
		local c = fitCache[ runs ]
		if ( c and c.boxW == boxW and c.size == size and c.face == face ) then
			font = c.font
		else
			if ( MeasureRuns( runs, font ) > boxW ) then
				local minSize = style.minSize or size * 0.55
				local s = size
				while ( s > minSize ) do
					s = s - 1
					font = D.Font( face, s, style.weight )
					if ( MeasureRuns( runs, font ) <= boxW ) then break end
				end
			end
			fitCache[ runs ] = { boxW = boxW, size = size, face = face, font = font }
		end

	end

	local tw, th, widths = MeasureRuns( runs, font )
	if ( overflow == "fit" ) then overflow = tw > boxW and "ellipsis" or "clip" end

	local Y = Y0 + floor( ( boxH - th ) / 2 )
	if ( style.valign == 0 ) then Y = Y0 elseif ( style.valign == 2 ) then Y = Y0 + boxH - th end

	if ( overflow == "scroll" or ( overflow == "marquee" and tw > boxW ) ) then

		local gap = px( style.gap or 40 )
		local period = tw + gap
		local offset = ( RealTime() * ( style.speed or 40 ) * D.S ) % period

		D.ClipPx( X0, Y0, boxW, boxH )
		local sx = X0 - offset
		while ( sx < X0 + boxW ) do
			DrawRuns( runs, font, floor( sx ), Y, th, style, alpha, widths )
			sx = sx + period
		end
		D.Unclip()

		return boxW / D.S

	end

	local clip = false
	if ( tw > boxW ) then
		if ( overflow == "ellipsis" ) then
			runs = Ellipsize( runs, font, boxW )
			tw, th, widths = MeasureRuns( runs, font )
		else
			clip = true
		end
	end

	local align = style.align or 0
	local sx = X0
	if ( align == 1 ) then sx = X0 + floor( ( boxW - tw ) / 2 ) elseif ( align == 2 ) then sx = X0 + boxW - tw end

	if ( clip ) then D.ClipPx( X0, Y0, boxW, boxH ) sx = X0 end
	DrawRuns( runs, font, sx, Y, th, style, alpha, widths )
	if ( clip ) then D.Unclip() end

	-- the width it takes on screen, so layouts can place things next to it
	return math.min( tw, boxW ) / D.S

end

-- Width a run list would take with this style (design units).
function D.MeasureLine( runs, style )

	if ( !runs ) then return 0 end
	if ( isstring( runs ) ) then runs = { { runs } } end
	local font = D.Font( style.face or "Tahoma", style.size or 14, style.weight )
	local w = MeasureRuns( runs, font )
	return w / D.S

end
