--[[---------------------------------------------------------------------------
	Advanced Material Editor - the image engine

	Two core jobs are done in Lua on the CPU because Garry's Mod gives addons no
	way to run a custom shader:

	  Rasterise   turn a selection recipe into a coverage mask - one byte per
	              pixel, 0 where the selection does not reach and 255 where it
	              fully does, with everything in between along a softened edge.

	  Execute     run the texture editor's steps over an RGBA buffer.

	Imported image layers stay as GPU texture quads for preview and export, with
	a bounded CPU fallback for stripped-down engine branches. Both routes share
	the same order and transform math, so a layer is never expanded into hundreds
	of thousands of photographic pixel runs.

	Everything is deliberately kept to flat arrays of numbers. A table per pixel
	would be tidier to read and would also allocate four million tables for a
	1024 image, which is enough to stall the frame and then thrash the garbage
	collector for the next several.
-----------------------------------------------------------------------------]]

AdvMat     = AdvMat or {}
AdvMat.Sel = AdvMat.Sel or {}
AdvMat.Ops = AdvMat.Ops or {}
AdvMat.Buf = AdvMat.Buf or {}

local S   = AdvMat.Sel
local OPS = AdvMat.Ops
local BUF = AdvMat.Buf
local GEN = AdvMat.Gen

local floor, min, max, abs, sqrt = math.floor, math.min, math.max, math.abs, math.sqrt
local strbyte = string.byte

---------------------------------------------------------------------------
-- Buffers
---------------------------------------------------------------------------
-- { w, h, r, g, b, a } with four parallel 1-based arrays, the same shape
-- GEN.ReadSource hands back, so a source can be adopted without a conversion
-- pass.

function BUF.New( w, h )
	return { w = w, h = h, r = {}, g = {}, b = {}, a = {} }
end

function BUF.Solid( w, h, colour )
	local buf = BUF.New( w, h )
	local cr, cg, cb, ca = colour[ 1 ], colour[ 2 ], colour[ 3 ], colour[ 4 ]

	for i = 1, w * h do
		buf.r[ i ], buf.g[ i ], buf.b[ i ], buf.a[ i ] = cr, cg, cb, ca
	end

	return buf
end

--- A private copy of a cached source read, so editing does not corrupt the
--- cache every other recipe is reading from.
function BUF.FromSource( src )
	local buf = BUF.New( src.w, src.h )
	local n   = src.w * src.h

	local sr, sg, sb, sa = src.r, src.g, src.b, src.a
	local dr, dg, db, da = buf.r, buf.g, buf.b, buf.a

	for i = 1, n do
		dr[ i ], dg[ i ], db[ i ], da[ i ] = sr[ i ], sg[ i ], sb[ i ], sa[ i ]
	end

	return buf
end

function BUF.Copy( buf )
	return BUF.FromSource( buf )
end

--- Interleave into the flat byte array the PNG encoder wants.
function BUF.Flatten( buf, channels )
	channels = channels or 4

	local n  = buf.w * buf.h
	local px = {}
	local o  = 1

	local r, g, b, a = buf.r, buf.g, buf.b, buf.a

	if channels == 4 then
		for i = 1, n do
			px[ o ], px[ o + 1 ], px[ o + 2 ], px[ o + 3 ] = r[ i ], g[ i ], b[ i ], a[ i ]
			o = o + 4
		end
	else
		for i = 1, n do
			px[ o ], px[ o + 1 ], px[ o + 2 ] = r[ i ], g[ i ], b[ i ]
			o = o + 3
		end
	end

	return px
end

--- Separable box blur over a plain array of numbers, clamping at the edges.
--- Shared by the surface map generators, which all need a blurred copy of the
--- brightness to tell fine detail from broad shape.
function BUF.BlurField( field, w, h, radius )
	if radius < 1 then return field end

	local span = radius * 2 + 1
	local tmp, out = {}, {}

	-- Rows are where a queued build may pause for the next frame (GEN.Yield).
	for y = 0, h - 1 do
		GEN.Yield()
		local row = y * w
		for x = 0, w - 1 do
			local sum = 0
			for k = -radius, radius do
				sum = sum + field[ row + math.Clamp( x + k, 0, w - 1 ) + 1 ]
			end
			tmp[ row + x + 1 ] = sum / span
		end
	end

	for y = 0, h - 1 do
		GEN.Yield()
		for x = 0, w - 1 do
			local sum = 0
			for k = -radius, radius do
				sum = sum + tmp[ math.Clamp( y + k, 0, h - 1 ) * w + x + 1 ]
			end
			out[ y * w + x + 1 ] = sum / span
		end
	end

	return out
end

--- True when anything in the buffer is less than fully opaque, which decides
--- whether the .png needs an alpha channel at all.
function BUF.HasAlpha( buf )
	local a = buf.a
	for i = 1, buf.w * buf.h do
		if a[ i ] < 255 then return true end
	end
	return false
end

--- Horizontal runs whose RGBA value differs from the untouched source.
--- Shared by the live canvas and the render-target exporter so the two paths
--- cannot disagree about which pixels an edit changed.
---
--- `x0`..`x1` x `y0`..`y1` (inclusive, buffer pixels) limits the search to one
--- rectangle, which is how the canvas re-uploads only what a brush stroke
--- touched. A run never extends past the rectangle's right edge.
function BUF.BuildRuns( buf, src, x0, y0, x1, y1 )
	local runs = {}
	local w, h = buf.w, buf.h

	x0, y0 = x0 or 0, y0 or 0
	x1, y1 = x1 or ( w - 1 ), y1 or ( h - 1 )

	local br, bg, bb, ba = buf.r, buf.g, buf.b, buf.a
	local sr, sg, sb = src and src.r, src and src.g, src and src.b
	local sa = src and src.a

	for y = y0, y1 do
		local row = y * w
		local x   = x0

		while x <= x1 do
			local i = row + x + 1
			local differs = true

			if sr then
				differs = ( br[ i ] ~= sr[ i ] ) or ( bg[ i ] ~= sg[ i ] )
				       or ( bb[ i ] ~= sb[ i ] ) or ( ba[ i ] ~= sa[ i ] )
			end

			if not differs then
				x = x + 1
			else
				local r, g, b, a = br[ i ], bg[ i ], bb[ i ], ba[ i ]
				local run = 1

				while x + run <= x1 do
					local j = row + x + run + 1
					if br[ j ] ~= r or bg[ j ] ~= g or bb[ j ] ~= b
						or ba[ j ] ~= a then break end
					run = run + 1
				end

				runs[ #runs + 1 ] = { x, y, run, r, g, b, a }
				x = x + run
			end
		end
	end

	return runs
end

---------------------------------------------------------------------------
-- Colour maths
---------------------------------------------------------------------------
-- Plain numbers in, plain numbers out. The engine's HSVToColor allocates a
-- Color per call, which is fine for a menu and ruinous for a megapixel.

local function RGBtoHSV( r, g, b )
	r, g, b = r / 255, g / 255, b / 255

	local hi = max( r, g, b )
	local lo = min( r, g, b )
	local d  = hi - lo

	local h = 0

	if d > 0 then
		if hi == r then
			h = ( ( g - b ) / d ) % 6
		elseif hi == g then
			h = ( b - r ) / d + 2
		else
			h = ( r - g ) / d + 4
		end
		h = h * 60
	end

	return h, ( hi > 0 ) and ( d / hi ) or 0, hi
end

local function HSVtoRGB( h, s, v )
	h = h % 360
	if h < 0 then h = h + 360 end

	local c = v * s
	local x = c * ( 1 - abs( ( h / 60 ) % 2 - 1 ) )
	local m = v - c

	local r, g, b

	if     h <  60 then r, g, b = c, x, 0
	elseif h < 120 then r, g, b = x, c, 0
	elseif h < 180 then r, g, b = 0, c, x
	elseif h < 240 then r, g, b = 0, x, c
	elseif h < 300 then r, g, b = x, 0, c
	else                r, g, b = c, 0, x end

	return ( r + m ) * 255, ( g + m ) * 255, ( b + m ) * 255
end

OPS.RGBtoHSV = RGBtoHSV
OPS.HSVtoRGB = HSVtoRGB

--- Rec. 601 luma, which tracks perceived brightness far better than an
--- average and is what image tools use for "convert to greyscale".
local function Luma( r, g, b )
	return r * 0.299 + g * 0.587 + b * 0.114
end

OPS.Luma = Luma

local function Byte( v )
	if v < 0 then return 0 end
	if v > 255 then return 255 end
	return floor( v + 0.5 )
end

-- What a blank image starts as when its recipe names no colour, matching the
-- default in OPS.Base.
local WHITE = { 255, 255, 255, 255 }

---------------------------------------------------------------------------
-- Mask primitives
---------------------------------------------------------------------------
-- A mask is a 1-based array of w*h bytes. Shapes write into a scratch mask
-- which is then combined into the running one, because "subtract" needs to
-- know the shape's own coverage separately from what is already selected.

local function NewMask( n, fill )
	local m = {}
	for i = 1, n do m[ i ] = fill end
	return m
end

--- Coverage of the span [x0, x1) on one row, with fractional ends so a
--- straight edge that falls between two pixels does not come out jagged.
local function Span( mask, row, x0, x1, w, amount )
	if x1 <= x0 then return end

	x0 = max( x0, 0 )
	x1 = min( x1, w )
	if x1 <= x0 then return end

	local ix0 = floor( x0 )
	local ix1 = floor( x1 )

	if ix0 == ix1 then
		local i = row + ix0 + 1
		local v = mask[ i ] + ( x1 - x0 ) * amount
		mask[ i ] = ( v > 255 ) and 255 or v
		return
	end

	local i = row + ix0 + 1
	local v = mask[ i ] + ( ix0 + 1 - x0 ) * amount
	mask[ i ] = ( v > 255 ) and 255 or v

	for x = ix0 + 1, ix1 - 1 do
		i = row + x + 1
		v = mask[ i ] + amount
		mask[ i ] = ( v > 255 ) and 255 or v
	end

	if ix1 < w then
		i = row + ix1 + 1
		v = mask[ i ] + ( x1 - ix1 ) * amount
		mask[ i ] = ( v > 255 ) and 255 or v
	end
end

-- Vertical supersampling for the shapes whose edges are not axis aligned.
-- Four is enough that a diagonal reads as a clean line at any zoom the editor
-- offers, and cheap because each sub-scanline is only a little arithmetic.
local SUB = 4

---------------------------------------------------------------------------
-- Shape rasterisers
---------------------------------------------------------------------------
local Shape = {}

Shape.all = function( mask, w, h )
	for i = 1, w * h do mask[ i ] = 255 end
end

Shape.rect = function( mask, w, h, shape )
	local x0 = shape.x * w
	local y0 = shape.y * h
	local x1 = x0 + shape.w * w
	local y1 = y0 + shape.h * h

	local iy0 = max( floor( y0 ), 0 )
	local iy1 = min( math.ceil( y1 ), h ) - 1

	for y = iy0, iy1 do
		-- How much of this pixel row the rectangle actually covers.
		local cover = min( y + 1, y1 ) - max( y, y0 )
		if cover > 0 then
			Span( mask, y * w, x0, x1, w, 255 * cover )
		end
	end
end

Shape.ellipse = function( mask, w, h, shape )
	local cx = ( shape.x + shape.w * 0.5 ) * w
	local cy = ( shape.y + shape.h * 0.5 ) * h
	local rx = shape.w * w * 0.5
	local ry = shape.h * h * 0.5

	if rx <= 0 or ry <= 0 then return end

	local iy0 = max( floor( cy - ry ), 0 )
	local iy1 = min( math.ceil( cy + ry ), h ) - 1

	local amount = 255 / SUB

	for y = iy0, iy1 do
		local row = y * w

		for s = 0, SUB - 1 do
			local sy = y + ( s + 0.5 ) / SUB
			local dy = ( sy - cy ) / ry

			if dy > -1 and dy < 1 then
				local half = rx * sqrt( 1 - dy * dy )
				Span( mask, row, cx - half, cx + half, w, amount )
			end
		end
	end
end

Shape.poly = function( mask, w, h, shape )
	local pts = shape.pts
	local n   = #pts / 2

	if n < 3 then return end

	-- Bounds first, so a small shape on a large texture costs almost nothing.
	local minY, maxY = math.huge, -math.huge

	for i = 2, #pts, 2 do
		local y = pts[ i ] * h
		if y < minY then minY = y end
		if y > maxY then maxY = y end
	end

	local iy0 = max( floor( minY ), 0 )
	local iy1 = min( math.ceil( maxY ), h ) - 1

	local amount = 255 / SUB
	local xs     = {}

	for y = iy0, iy1 do
		local row = y * w

		for s = 0, SUB - 1 do
			local sy = y + ( s + 0.5 ) / SUB
			local m  = 0

			-- Even-odd fill: every edge the scanline crosses contributes one
			-- boundary, and the inside is between alternate pairs of them.
			for i = 1, n do
				local ax = pts[ i * 2 - 1 ] * w
				local ay = pts[ i * 2     ] * h

				local j  = ( i % n ) + 1
				local bx = pts[ j * 2 - 1 ] * w
				local by = pts[ j * 2     ] * h

				if ( ay <= sy and by > sy ) or ( by <= sy and ay > sy ) then
					m = m + 1
					xs[ m ] = ax + ( sy - ay ) / ( by - ay ) * ( bx - ax )
				end
			end

			if m > 1 then
				for i = m + 1, #xs do xs[ i ] = nil end
				table.sort( xs )

				for i = 1, m - 1, 2 do
					Span( mask, row, xs[ i ], xs[ i + 1 ], w, amount )
				end
			end
		end
	end
end

--- A painted stroke: a run of capsules along the pointer's path. Distance to
--- the segment gives a soft edge for free, which is what makes a brush look
--- like a brush rather than like a chain of squares.
Shape.brush = function( mask, w, h, shape )
	local pts = shape.pts
	local n   = #pts / 2
	local r   = shape.r * ( ( w + h ) * 0.5 )
	local hardness = shape.hardness or 1

	if r < 0.5 then r = 0.5 end

	-- The legacy brush has a one-pixel antialiased edge: it is solid up to
	-- r - 0.5 and clear after r + 0.5.  Hardness moves that solid inner edge
	-- towards the centre while leaving the outside radius alone.  This makes
	-- zero hardness fade over the full radius, while hardness one reduces to
	-- the exact old `r + 0.5 - d` coverage calculation below.
	local outer = r + 0.5
	local inner = ( r - 0.5 ) * hardness
	local fade  = outer - inner

	local function Dab( ax, ay, bx, by )
		local x0 = max( floor( min( ax, bx ) - r - 1 ), 0 )
		local x1 = min( math.ceil( max( ax, bx ) + r + 1 ), w - 1 )
		local y0 = max( floor( min( ay, by ) - r - 1 ), 0 )
		local y1 = min( math.ceil( max( ay, by ) + r + 1 ), h - 1 )

		local dx, dy = bx - ax, by - ay
		local len2   = dx * dx + dy * dy

		for y = y0, y1 do
			local row = y * w
			local py  = y + 0.5

			for x = x0, x1 do
				local px = x + 0.5

				-- Closest point on the segment, clamped to its ends.
				local t = 0
				if len2 > 0 then
					t = ( ( px - ax ) * dx + ( py - ay ) * dy ) / len2
					if t < 0 then t = 0 elseif t > 1 then t = 1 end
				end

				local ex = px - ( ax + dx * t )
				local ey = py - ( ay + dy * t )
				local d  = sqrt( ex * ex + ey * ey )

				-- Coverage falls from one at the hardness radius to zero at the
				-- outside edge.  At hardness one `fade` is exactly one pixel,
				-- preserving the previous antialiasing and output byte-for-byte.
				local cov = ( outer - d ) / fade
				if cov > 0 then
					if cov > 1 then cov = 1 end

					local i = row + x + 1
					local v = cov * 255
					if v > mask[ i ] then mask[ i ] = v end
				end
			end
		end
	end

	if n == 1 then
		local x, y = pts[ 1 ] * w, pts[ 2 ] * h
		Dab( x, y, x, y )
		return
	end

	for i = 1, n - 1 do
		Dab( pts[ i * 2 - 1 ] * w, pts[ i * 2     ] * h,
		     pts[ i * 2 + 1 ] * w, pts[ i * 2 + 2 ] * h )
	end
end

--- Select by colour. Contiguous walks outwards from the clicked pixel and
--- stops at the first pixel too different; non-contiguous takes every pixel in
--- the image that matches, which is how you catch every red stripe at once.
Shape.wand = function( mask, w, h, shape, ctx )
	local px = ctx and ctx.pixels
	if not px then return end

	local sx = math.Clamp( floor( shape.x * w ), 0, w - 1 )
	local sy = math.Clamp( floor( shape.y * h ), 0, h - 1 )

	local seed = sy * w + sx + 1
	local r, g, b, a = px.r, px.g, px.b, px.a

	local sr, sg, sb, sa = r[ seed ], g[ seed ], b[ seed ], a[ seed ]
	if not sr then return end

	-- Tolerance is compared against the largest single channel difference,
	-- which behaves much more predictably to a user dragging a slider than a
	-- euclidean distance does.
	local tol = shape.tol * 255

	local function Match( i )
		return abs( r[ i ] - sr ) <= tol
		   and abs( g[ i ] - sg ) <= tol
		   and abs( b[ i ] - sb ) <= tol
		   and abs( a[ i ] - sa ) <= tol
	end

	if not shape.contiguous then
		for i = 1, w * h do
			if Match( i ) then mask[ i ] = 255 end
		end
		return
	end

	-- Scanline flood fill: fills a whole run at a time and only pushes the
	-- rows above and below, which is far fewer stack entries than a per pixel
	-- flood and matters at 1024.
	local stack, top = {}, 0

	local function Push( x, y )
		top = top + 1
		stack[ top ] = y * w + x
	end

	Push( sx, sy )

	while top > 0 do
		local v = stack[ top ]
		top = top - 1

		local y  = floor( v / w )
		local x  = v - y * w
		local row = y * w

		if mask[ row + x + 1 ] == 0 and Match( row + x + 1 ) then
			local left = x
			while left > 0 and mask[ row + left ] == 0 and Match( row + left ) do
				left = left - 1
			end

			local right = x
			while right < w - 1 and mask[ row + right + 2 ] == 0 and Match( row + right + 2 ) do
				right = right + 1
			end

			for i = left, right do mask[ row + i + 1 ] = 255 end

			if y > 0 then
				local up = ( y - 1 ) * w
				for i = left, right do
					if mask[ up + i + 1 ] == 0 and Match( up + i + 1 ) then Push( i, y - 1 ) end
				end
			end

			if y < h - 1 then
				local down = ( y + 1 ) * w
				for i = left, right do
					if mask[ down + i + 1 ] == 0 and Match( down + i + 1 ) then Push( i, y + 1 ) end
				end
			end
		end
	end
end

---------------------------------------------------------------------------
-- UV shapes
---------------------------------------------------------------------------
-- These need the model's mesh, which lives in cl_58_meshuv.lua. Looked up at
-- call time rather than held in an upvalue, because that file loads after
-- this one.

--- Fill one UV triangle. Straightforward scanline; the supersampling that the
--- polygon rasteriser does is not worth it here because a UV shell is made of
--- hundreds of triangles that share edges, and any seam between two of them
--- would be filled by its neighbour anyway.
local function FillTriangle( mask, w, h, ax, ay, bx, by, cx, cy )
	-- Sort by y so the triangle can be walked as two flat-edged halves.
	if ay > by then ax, ay, bx, by = bx, by, ax, ay end
	if by > cy then bx, by, cx, cy = cx, cy, bx, by end
	if ay > by then ax, ay, bx, by = bx, by, ax, ay end

	local iy0 = max( floor( ay ), 0 )
	local iy1 = min( math.ceil( cy ), h ) - 1

	for y = iy0, iy1 do
		local sy = y + 0.5

		if sy >= ay and sy <= cy then
			local xa = ax + ( cx - ax ) * ( ( cy - ay ) > 0 and ( sy - ay ) / ( cy - ay ) or 0 )
			local xb

			if sy < by then
				xb = ax + ( bx - ax ) * ( ( by - ay ) > 0 and ( sy - ay ) / ( by - ay ) or 0 )
			else
				xb = bx + ( cx - bx ) * ( ( cy - by ) > 0 and ( sy - by ) / ( cy - by ) or 0 )
			end

			if xa > xb then xa, xb = xb, xa end

			-- Half a pixel of bleed on each side, so neighbouring triangles
			-- meet without a hairline gap down the shared edge.
			Span( mask, y * w, xa - 0.5, xb + 0.5, w, 255 )
		end
	end
end

local function UVShapes( mask, w, h, shape, ctx )
	local M = AdvMat.Mesh
	if not M or not ctx or not ctx.model then return end

	-- Resolved against the parts that were showing when the shape was made,
	-- not against the model with every bodygroup at nought. Hiding a part
	-- renumbers the mesh list, so the two are not the same geometry and the
	-- same slot number does not mean the same piece.
	local group = M.Group( ctx.model, ctx.matpath, ctx.slot or 0, ctx.mask )
	if not group then return end

	local tris = group.tris
	if not tris or #tris == 0 then return end

	local wanted = tris

	if shape.t == "uvtri" or shape.t == "uvisland" then
		local hit = M.TriangleAt( group, shape.x, shape.y )
		if not hit then return end

		if shape.t == "uvtri" then
			wanted = { hit }
		else
			wanted = M.Island( ctx.model, ctx.matpath, ctx.slot or 0, hit, ctx.mask )
		end
	end

	for _, t in ipairs( wanted ) do
		FillTriangle( mask, w, h,
			t[ 1 ] * w, t[ 2 ] * h,
			t[ 3 ] * w, t[ 4 ] * h,
			t[ 5 ] * w, t[ 6 ] * h )
	end
end

Shape.uvtri    = UVShapes
Shape.uvisland = UVShapes
Shape.uvall    = UVShapes

---------------------------------------------------------------------------
-- Grow, feather, combine
---------------------------------------------------------------------------

--- Separable box pass. `pick` is max for a dilate, min for an erode and nil
--- for a plain blur.
local function BoxPass( mask, w, h, radius, pick )
	if radius < 1 then return mask end

	local span = radius * 2 + 1
	local tmp  = {}
	local out  = {}

	for y = 0, h - 1 do
		local row = y * w
		for x = 0, w - 1 do
			if pick then
				local v = mask[ row + math.Clamp( x - radius, 0, w - 1 ) + 1 ]
				for k = -radius + 1, radius do
					local s = mask[ row + math.Clamp( x + k, 0, w - 1 ) + 1 ]
					if pick( s, v ) then v = s end
				end
				tmp[ row + x + 1 ] = v
			else
				local sum = 0
				for k = -radius, radius do
					sum = sum + mask[ row + math.Clamp( x + k, 0, w - 1 ) + 1 ]
				end
				tmp[ row + x + 1 ] = sum / span
			end
		end
	end

	for y = 0, h - 1 do
		for x = 0, w - 1 do
			if pick then
				local v = tmp[ math.Clamp( y - radius, 0, h - 1 ) * w + x + 1 ]
				for k = -radius + 1, radius do
					local s = tmp[ math.Clamp( y + k, 0, h - 1 ) * w + x + 1 ]
					if pick( s, v ) then v = s end
				end
				out[ y * w + x + 1 ] = v
			else
				local sum = 0
				for k = -radius, radius do
					sum = sum + tmp[ math.Clamp( y + k, 0, h - 1 ) * w + x + 1 ]
				end
				out[ y * w + x + 1 ] = sum / span
			end
		end
	end

	return out
end

local function Bigger( a, b )  return a > b end
local function Smaller( a, b ) return a < b end

--- Combine a shape's own coverage into the running mask.
local function Combine( mask, shape, w, h, mode )
	local n = w * h

	if mode == "sub" then
		for i = 1, n do
			local keep = mask[ i ] * ( 1 - shape[ i ] / 255 )
			mask[ i ] = keep
		end
	elseif mode == "int" then
		for i = 1, n do
			mask[ i ] = mask[ i ] * ( shape[ i ] / 255 )
		end
	else
		for i = 1, n do
			local v = shape[ i ]
			if v > mask[ i ] then mask[ i ] = v end
		end
	end
end

---------------------------------------------------------------------------
-- The entry point
---------------------------------------------------------------------------

--- Build the coverage mask for `sel` at w x h.
---
--- `ctx` supplies what the shapes that are not pure geometry need:
---     pixels   an RGBA buffer, for "select similar colour"
---     src      a texture path to read pixels from if `pixels` is absent
---     model    the .mdl, for the UV shapes
---     slot     which sub-material of that model
---
--- Returns nil when the selection is empty or covers everything, which lets
--- callers skip the per pixel work entirely.
function S.Rasterize( sel, w, h, ctx )
	if S.IsEmpty( sel ) then return nil end
	if S.CoversAll( sel ) then return nil end

	ctx = ctx or {}

	-- Reading pixels is expensive, so it only happens if a shape asks.
	if not ctx.pixels and ctx.src and ctx.src ~= "" then
		for _, shape in ipairs( sel.shapes ) do
			if shape.t == "wand" then
				ctx.pixels = GEN.ReadSource( ctx.src, w, h, true )
				break
			end
		end
	end

	local n     = w * h
	local mask  = NewMask( n, 0 )
	local scrap = {}

	for _, shape in ipairs( sel.shapes ) do
		local fn = Shape[ shape.t ]

		if fn then
			for i = 1, n do scrap[ i ] = 0 end
			fn( scrap, w, h, shape, ctx )
			Combine( mask, scrap, w, h, shape.mode )
		end
	end

	if sel.grow and sel.grow ~= 0 then
		local radius = floor( abs( sel.grow ) * ( ( w + h ) * 0.5 ) )
		if radius >= 1 then
			mask = BoxPass( mask, w, h, radius, sel.grow > 0 and Bigger or Smaller )
		end
	end

	if sel.feather and sel.feather > 0 then
		local radius = floor( sel.feather * ( ( w + h ) * 0.5 ) )
		if radius >= 1 then
			mask = BoxPass( mask, w, h, radius, nil )
		end
	end

	if sel.invert then
		for i = 1, n do mask[ i ] = 255 - mask[ i ] end
	end

	-- The clip is intersected last, after this selection's own shaping. A
	-- sanitised clip is never empty, so a nil back from the recursion can only
	-- mean it covers everything, which needs no work.
	if sel.clip then
		local clip = S.Rasterize( sel.clip, w, h, ctx )

		if clip then
			for i = 1, n do mask[ i ] = mask[ i ] * ( clip[ i ] / 255 ) end
		end
	end

	-- Rounded once at the end rather than after every stage, so a feathered
	-- edge keeps its gradient instead of being quantised three times.
	for i = 1, n do
		local v = mask[ i ]
		mask[ i ] = ( v < 0 ) and 0 or ( v > 255 ) and 255 or floor( v + 0.5 )
	end

	return mask
end

---------------------------------------------------------------------------
-- Steps
---------------------------------------------------------------------------
local Run = {}

--- Coverage of pixel i, honouring the step's own region. A nil mask means the
--- step applies everywhere, which is the common case and worth not paying for.
local function Cov( mask, i )
	if not mask then return 1 end
	return mask[ i ] / 255
end

--- Blend one source colour onto a pixel using the solid-fill contract. The
--- established fill loop remains inlined below because a Lua function call for
--- every pixel is measurable on a 2048 image; gradients use this counterpart
--- while calculating their per-pixel source colour.
local function BlendPixel( buf, i, cr, cg, cb, ca, amount, blend, preserveAlpha )
	local r, g, b, a = buf.r, buf.g, buf.b, buf.a

	if blend == "replace" then
		local k = 1 - amount
		r[ i ] = Byte( r[ i ] * k + cr * amount )
		g[ i ] = Byte( g[ i ] * k + cg * amount )
		b[ i ] = Byte( b[ i ] * k + cb * amount )
		if not preserveAlpha then a[ i ] = Byte( a[ i ] * k + ca * amount ) end
	else
		local nr, ng, nb = cr, cg, cb

		if blend == "multiply" then
			nr, ng, nb = r[ i ] * cr / 255, g[ i ] * cg / 255, b[ i ] * cb / 255
		elseif blend == "screen" then
			nr = 255 - ( 255 - r[ i ] ) * ( 255 - cr ) / 255
			ng = 255 - ( 255 - g[ i ] ) * ( 255 - cg ) / 255
			nb = 255 - ( 255 - b[ i ] ) * ( 255 - cb ) / 255
		elseif blend == "add" then
			nr, ng, nb = r[ i ] + cr, g[ i ] + cg, b[ i ] + cb
		end

		-- Straight-alpha source-over with the standard blend-mode overlap
		-- term. Hidden RGB under an alpha-zero pixel must not influence new
		-- paint: a transparent white blank painted black stays black, rather
		-- than becoming grey or white when it is made visible.
		local sa = amount * ( ca / 255 )
		if sa > 0 then
			-- An opaque Source material can still carry reflection/phong data in
			-- alpha. Colour paint treats that material as visually opaque and
			-- leaves the data channel byte-for-byte intact.
			if preserveAlpha then
				local keep = 1 - sa
				r[ i ] = Byte( r[ i ] * keep + nr * sa )
				g[ i ] = Byte( g[ i ] * keep + ng * sa )
				b[ i ] = Byte( b[ i ] * keep + nb * sa )
				return
			end

			local da = a[ i ] / 255
			local outA = sa + da * ( 1 - sa )
			local dstOnly = da * ( 1 - sa )
			local srcOnly = sa * ( 1 - da )
			local overlap = sa * da
			r[ i ] = Byte( ( r[ i ] * dstOnly + cr * srcOnly + nr * overlap ) / outA )
			g[ i ] = Byte( ( g[ i ] * dstOnly + cg * srcOnly + ng * overlap ) / outA )
			b[ i ] = Byte( ( b[ i ] * dstOnly + cb * srcOnly + nb * overlap ) / outA )
			a[ i ] = Byte( outA * 255 )
		end
	end
end

Run.fill = function( buf, op, mask, ctx )
	local c  = op.color
	local cr, cg, cb, ca = c[ 1 ], c[ 2 ], c[ 3 ], c[ 4 ]
	local opacity = op.opacity or 1
	local blend   = op.blend or "normal"
	local r, g, b, a = buf.r, buf.g, buf.b, buf.a
	local preserveAlpha = ctx and ctx.preserve_source_mask == true

	for i = 1, buf.w * buf.h do
		local cov = Cov( mask, i )

		if cov > 0 then
			if blend == "replace" then
				local t = opacity * cov
				local k = 1 - t
				r[ i ] = Byte( r[ i ] * k + cr * t )
				g[ i ] = Byte( g[ i ] * k + cg * t )
				b[ i ] = Byte( b[ i ] * k + cb * t )
				if not preserveAlpha then a[ i ] = Byte( a[ i ] * k + ca * t ) end

			else
				local nr, ng, nb = cr, cg, cb

				if blend == "multiply" then
					nr, ng, nb = r[ i ] * cr / 255, g[ i ] * cg / 255, b[ i ] * cb / 255
				elseif blend == "screen" then
					nr = 255 - ( 255 - r[ i ] ) * ( 255 - cr ) / 255
					ng = 255 - ( 255 - g[ i ] ) * ( 255 - cg ) / 255
					nb = 255 - ( 255 - b[ i ] ) * ( 255 - cb ) / 255
				elseif blend == "add" then
					nr, ng, nb = r[ i ] + cr, g[ i ] + cg, b[ i ] + cb
				end

				local sa = opacity * cov * ( ca / 255 )
				if sa > 0 then
					if preserveAlpha then
						local keep = 1 - sa
						r[ i ] = Byte( r[ i ] * keep + nr * sa )
						g[ i ] = Byte( g[ i ] * keep + ng * sa )
						b[ i ] = Byte( b[ i ] * keep + nb * sa )
					else
						local da = a[ i ] / 255
						local outA = sa + da * ( 1 - sa )
						local dstOnly = da * ( 1 - sa )
						local srcOnly = sa * ( 1 - da )
						local overlap = sa * da
						r[ i ] = Byte( ( r[ i ] * dstOnly + cr * srcOnly + nr * overlap ) / outA )
						g[ i ] = Byte( ( g[ i ] * dstOnly + cg * srcOnly + ng * overlap ) / outA )
						b[ i ] = Byte( ( b[ i ] * dstOnly + cb * srcOnly + nb * overlap ) / outA )
						a[ i ] = Byte( outA * 255 )
					end
				end
			end
		end
	end
end

Run.gradient = function( buf, op, mask, ctx )
	local a, b = op.color1, op.color2
	local x1, y1, x2, y2 = op.x1, op.y1, op.x2, op.y2
	local dx, dy = x2 - x1, y2 - y1
	local length2 = dx * dx + dy * dy
	local opacity = op.opacity or 1
	local blend   = op.blend or "normal"
	local preserveAlpha = ctx and ctx.preserve_source_mask == true
	local w, h = buf.w, buf.h
	local i = 1

	for y = 0, h - 1 do
		local py = ( h > 1 ) and ( y / ( h - 1 ) ) or 0.5

		for x = 0, w - 1 do
			local cov = Cov( mask, i )

			if cov > 0 then
				local px = ( w > 1 ) and ( x / ( w - 1 ) ) or 0.5
				local t = 0
				if length2 > 0 then
					t = math.Clamp( ( ( px - x1 ) * dx + ( py - y1 ) * dy ) / length2, 0, 1 )
				end

				local k = 1 - t
				BlendPixel( buf, i,
					a[ 1 ] * k + b[ 1 ] * t,
					a[ 2 ] * k + b[ 2 ] * t,
					a[ 3 ] * k + b[ 3 ] * t,
					a[ 4 ] * k + b[ 4 ] * t,
					opacity * cov, blend, preserveAlpha )
			end

			i = i + 1
		end
	end
end

Run.tint = function( buf, op, mask, ctx )
	local c = op.color
	local th, ts, tv = RGBtoHSV( c[ 1 ], c[ 2 ], c[ 3 ] )
	local amount = op.amount or 1
	local paintalpha = op.paintalpha == true
	local scalevalue = op.scalevalue == true
	local preserveAlpha = ctx and ctx.preserve_source_mask == true

	local r, g, b, a = buf.r, buf.g, buf.b, buf.a

	for i = 1, buf.w * buf.h do
		local cov = Cov( mask, i ) * amount
		if paintalpha then cov = cov * ( ( c[ 4 ] or 255 ) / 255 ) end

		if cov > 0 then
			local nr, ng, nb

			if op.keepvalue == false then
				nr, ng, nb = c[ 1 ], c[ 2 ], c[ 3 ]
			else
				-- Take the hue and saturation from the chosen colour and keep
				-- the pixel's own brightness, which is what makes a recolour
				-- read as the same material in a different colour rather than
				-- as a flat sticker.
				local _, _, v = RGBtoHSV( r[ i ], g[ i ], b[ i ] )
				-- Keep relative light and shadow, but still honour how bright the
				-- selected paint actually is. Discarding target V made black turn
				-- into source-brightness grey (white on a white texture).
				if scalevalue then v = v * tv end
				nr, ng, nb = HSVtoRGB( th, ts, v )
			end

			local k = 1 - cov
			r[ i ] = Byte( r[ i ] * k + nr * cov )
			g[ i ] = Byte( g[ i ] * k + ng * cov )
			b[ i ] = Byte( b[ i ] * k + nb * cov )

			-- A UI paint stroke is pigment, not merely an RGB adjustment.  Source
			-- over makes it visible on a transparent blank and gives brush
			-- strength and colour opacity the same predictable meaning as Fill.
			-- Legacy tint recipes omit paintalpha and retain their exact alpha.
			if paintalpha and not preserveAlpha then
				a[ i ] = Byte( a[ i ] + ( 255 - a[ i ] ) * cov )
			end
		end
	end
end

--- Apply the colour maths for one adjustment to one source texel.
---
--- Kept separate from the buffer loop because the full-resolution exporter
--- operates on packed render readback strings. Sharing this exact function is
--- what keeps a sharp saved texture colour-identical to the bounded editor
--- preview instead of maintaining a second approximation of the controls.
local function AdjustedRGB( nr, ng, nb, op )
	local hue      = op.hue      or 0
	local sat      = op.sat      or 1
	local val      = op.val      or 1
	local bright   = op.bright   or 0
	local contrast = op.contrast or 1
	local desat    = op.desat    or 0
	local invert   = op.invert
	local gamma    = op.gamma
	local levels   = op.posterize
	local threshold = op.threshold

	local touchHSV = ( hue ~= 0 ) or ( sat ~= 1 ) or ( val ~= 1 )

	-- Order matters and this one reads the way a user expects: flip first if
	-- asked, then move the colour, stretch the range, lift it and drain it.
	if invert then nr, ng, nb = 255 - nr, 255 - ng, 255 - nb end

	if touchHSV then
		local hh, ss, vv = RGBtoHSV( nr, ng, nb )
		nr, ng, nb = HSVtoRGB( hh + hue, min( ss * sat, 1 ), min( vv * val, 1 ) )
	end

	if contrast ~= 1 then
		nr = ( nr - 127.5 ) * contrast + 127.5
		ng = ( ng - 127.5 ) * contrast + 127.5
		nb = ( nb - 127.5 ) * contrast + 127.5
	end

	if bright ~= 0 then
		local add = bright * 255
		nr, ng, nb = nr + add, ng + add, nb + add
	end

	-- Standard image-editor gamma: values above one lift the midtones while
	-- zero and one remain fixed. Clamp first because contrast and lift may push
	-- a channel outside the byte range on purpose.
	if gamma and gamma ~= 1 then
		local exponent = 1 / gamma
		nr = 255 * ( math.Clamp( nr, 0, 255 ) / 255 ) ^ exponent
		ng = 255 * ( math.Clamp( ng, 0, 255 ) / 255 ) ^ exponent
		nb = 255 * ( math.Clamp( nb, 0, 255 ) / 255 ) ^ exponent
	end

	if desat > 0 then
		local l = Luma( nr, ng, nb )
		local k = 1 - desat
		nr, ng, nb = nr * k + l * desat, ng * k + l * desat, nb * k + l * desat
	end

	if levels then
		local step = 255 / ( levels - 1 )
		nr = floor( math.Clamp( nr, 0, 255 ) / step + 0.5 ) * step
		ng = floor( math.Clamp( ng, 0, 255 ) / step + 0.5 ) * step
		nb = floor( math.Clamp( nb, 0, 255 ) / step + 0.5 ) * step
	end

	-- Threshold is deliberately last: it previews the final adjusted luminance
	-- and produces a true black/white mask like an image editor.
	if threshold ~= nil then
		local value = ( Luma( nr, ng, nb ) / 255 >= threshold ) and 255 or 0
		nr, ng, nb = value, value, value
	end

	return nr, ng, nb
end

OPS.AdjustedRGB = AdjustedRGB

Run.adjust = function( buf, op, mask )
	local r, g, b = buf.r, buf.g, buf.b

	for i = 1, buf.w * buf.h do
		local cov = Cov( mask, i )

		if cov > 0 then
			local nr, ng, nb = AdjustedRGB( r[ i ], g[ i ], b[ i ], op )
			local k = 1 - cov
			r[ i ] = Byte( r[ i ] * k + nr * cov )
			g[ i ] = Byte( g[ i ] * k + ng * cov )
			b[ i ] = Byte( b[ i ] * k + nb * cov )
		end
	end
end

--- Blur and sharpen both need a blurred copy of the whole buffer, because a
--- pixel just inside the selection has to be able to read its neighbours just
--- outside it or the edge of the region turns into a visible seam.
local function BlurRGB( buf, radius )
	local w, h = buf.w, buf.h
	local out  = { r = {}, g = {}, b = {} }

	for _, ch in ipairs( { "r", "g", "b" } ) do
		local src = buf[ ch ]
		local tmp = {}
		local dst = out[ ch ]
		local span = radius * 2 + 1

		for y = 0, h - 1 do
			local row = y * w
			for x = 0, w - 1 do
				local sum = 0
				for k = -radius, radius do
					sum = sum + src[ row + math.Clamp( x + k, 0, w - 1 ) + 1 ]
				end
				tmp[ row + x + 1 ] = sum / span
			end
		end

		for y = 0, h - 1 do
			for x = 0, w - 1 do
				local sum = 0
				for k = -radius, radius do
					sum = sum + tmp[ math.Clamp( y + k, 0, h - 1 ) * w + x + 1 ]
				end
				dst[ y * w + x + 1 ] = sum / span
			end
		end
	end

	return out
end

Run.blur = function( buf, op, mask )
	local blurred = BlurRGB( buf, op.radius or 2 )
	local r, g, b = buf.r, buf.g, buf.b

	for i = 1, buf.w * buf.h do
		local cov = Cov( mask, i )
		if cov > 0 then
			local k = 1 - cov
			r[ i ] = Byte( r[ i ] * k + blurred.r[ i ] * cov )
			g[ i ] = Byte( g[ i ] * k + blurred.g[ i ] * cov )
			b[ i ] = Byte( b[ i ] * k + blurred.b[ i ] * cov )
		end
	end
end

Run.sharpen = function( buf, op, mask )
	local amount  = op.amount or 1
	local blurred = BlurRGB( buf, 2 )
	local r, g, b = buf.r, buf.g, buf.b

	for i = 1, buf.w * buf.h do
		local cov = Cov( mask, i ) * amount

		if cov > 0 then
			-- Unsharp mask: add back whatever the blur removed.
			r[ i ] = Byte( r[ i ] + ( r[ i ] - blurred.r[ i ] ) * cov )
			g[ i ] = Byte( g[ i ] + ( g[ i ] - blurred.g[ i ] ) * cov )
			b[ i ] = Byte( b[ i ] + ( b[ i ] - blurred.b[ i ] ) * cov )
		end
	end
end

Run.noise = function( buf, op, mask )
	local amount = ( op.amount or 0 ) * 255
	local seed   = op.seed or 1
	local mono   = op.mono

	local r, g, b = buf.r, buf.g, buf.b

	-- A hash rather than math.random: the same recipe has to produce the same
	-- grain on every machine and in every session, and math.random's sequence
	-- depends on whatever else has drawn from it first.
	local function Hash( i, salt )
		local v = bit.bxor( i * 2654435761, ( seed + salt ) * 40503 )
		v = bit.bxor( v, bit.rshift( v, 13 ) )
		v = v * 1274126177
		v = bit.bxor( v, bit.rshift( v, 16 ) )
		return ( bit.band( v, 0xFFFF ) / 65535 ) * 2 - 1
	end

	for i = 1, buf.w * buf.h do
		local cov = Cov( mask, i )

		if cov > 0 then
			local n1 = Hash( i, 0 ) * amount * cov

			if mono then
				r[ i ] = Byte( r[ i ] + n1 )
				g[ i ] = Byte( g[ i ] + n1 )
				b[ i ] = Byte( b[ i ] + n1 )
			else
				r[ i ] = Byte( r[ i ] + n1 )
				g[ i ] = Byte( g[ i ] + Hash( i, 1 ) * amount * cov )
				b[ i ] = Byte( b[ i ] + Hash( i, 2 ) * amount * cov )
			end
		end
	end
end

Run.erase = function( buf, op, mask )
	local opacity = op.opacity or 1
	local a = buf.a

	for i = 1, buf.w * buf.h do
		local cov = Cov( mask, i ) * opacity
		if cov > 0 then a[ i ] = Byte( a[ i ] * ( 1 - cov ) ) end
	end
end

Run.restore = function( buf, op, mask )
	local opacity = op.opacity or 1
	local a = buf.a

	for i = 1, buf.w * buf.h do
		local cov = Cov( mask, i ) * opacity
		if cov > 0 then a[ i ] = Byte( a[ i ] + ( 255 - a[ i ] ) * cov ) end
	end
end

--- Bring back the image the steps started from - the source texture, or the
--- blank colour - in proportion to the coverage. This is what rubbing out
--- paint means: paint, effects and holes all come away together, because each
--- of them is only a difference from that image.
---
--- `ctx.base` is the source exactly as it was read for this image. A pixel put
--- back completely is the source's own value again, which is also what lets the
--- canvas and the saved image show it at the texture's full resolution instead
--- of from the coarser working copy: neither redraws a pixel that matches.
Run.revert = function( buf, op, mask, ctx )
	local opacity = op.opacity or 1
	local base = ctx and ctx.base
	local keepAlpha = ctx and ctx.preserve_source_mask == true
	local r, g, b, a = buf.r, buf.g, buf.b, buf.a

	local br, bg, bb, ba
	local fr, fg, fb, fa

	if base then
		br, bg, bb, ba = base.r, base.g, base.b, base.a
	elseif ctx and ctx.src and ctx.src ~= "" then
		-- A sourced image with no source pixels to hand. Restoring towards a
		-- guess would bake the guess into the picture, so this does nothing.
		return
	else
		local fill = ctx and ctx.fill or WHITE
		fr, fg, fb, fa = fill[ 1 ], fill[ 2 ], fill[ 3 ], fill[ 4 ]
	end

	for i = 1, buf.w * buf.h do
		local cov = Cov( mask, i ) * opacity

		if cov > 0 then
			local tr, tg, tb, ta = fr, fg, fb, fa
			if br then tr, tg, tb, ta = br[ i ], bg[ i ], bb[ i ], ba[ i ] end

			if cov >= 1 then
				r[ i ], g[ i ], b[ i ] = tr, tg, tb
				if not keepAlpha then a[ i ] = ta end
			else
				local k = 1 - cov
				r[ i ] = Byte( r[ i ] * k + tr * cov )
				g[ i ] = Byte( g[ i ] * k + tg * cov )
				b[ i ] = Byte( b[ i ] * k + tb * cov )
				if not keepAlpha then a[ i ] = Byte( a[ i ] * k + ta * cov ) end
			end
		end
	end
end

Run.alphafrom = function( buf, op, mask )
	local from      = op.from or "luminance"
	local threshold = op.threshold or 0.5
	local softness  = max( op.softness or 0.1, 0.0001 )
	local invert    = op.invert

	local r, g, b, a = buf.r, buf.g, buf.b, buf.a
	local c = op.color or { 0, 0, 0, 255 }

	for i = 1, buf.w * buf.h do
		local cov = Cov( mask, i )

		if cov > 0 then
			local t

			if from == "selection" then
				t = cov
			elseif from == "colour" then
				-- Distance from the chosen colour, normalised so 1 is "as far
				-- away as it is possible to be".
				local dr = ( r[ i ] - c[ 1 ] ) / 255
				local dg = ( g[ i ] - c[ 2 ] ) / 255
				local db = ( b[ i ] - c[ 3 ] ) / 255
				t = min( sqrt( dr * dr + dg * dg + db * db ) / 1.732, 1 )
			else
				t = Luma( r[ i ], g[ i ], b[ i ] ) / 255
			end

			-- Smooth step across the threshold, so `softness` widens the band
			-- the image fades across instead of hard cutting.
			local e = math.Clamp( ( t - ( threshold - softness * 0.5 ) ) / softness, 0, 1 )
			e = e * e * ( 3 - 2 * e )

			if invert then e = 1 - e end

			local k = 1 - cov
			a[ i ] = Byte( a[ i ] * k + e * 255 * cov )
		end
	end
end

---------------------------------------------------------------------------
-- Brush strokes, applied to the pixels they cover
---------------------------------------------------------------------------
-- A stroke across a sleeve should cost the sleeve, not the sheet. The route
-- every other step takes rasterises a full-size mask and then visits every
-- pixel, which is right for a fill and ruinous for the hundreds of strokes a
-- painting session makes - it is why strokes once had to be capped at a few
-- dozen. A stroke's coverage is kept sparse instead, only the pixels the brush
-- reached, and the step runs on those alone.
--
-- Nothing about the result is approximate. The coverage is Shape.brush's
-- arithmetic in Shape.brush's order, and the step is the same Run function
-- given the same pixel and the same coverage; it simply never walks the pixels
-- the whole-image route would have skipped. The tests hold the two routes to
-- identical bytes.

--- Where along the row y = `py` a pixel centre can lie within `reach` of the
--- segment a-b: one interval, because a capsule is convex, or nothing.
---
--- Only a bound, worked out to skip pixels that could not have any coverage;
--- the caller still measures every pixel it visits exactly as Shape.brush does
--- and widens the interval by a pixel either side, so rounding here can never
--- change a result.
local function RowSpan( ax, ay, bx, by, len, py, reach )
	local lo, hi = math.huge, -math.huge

	-- The round cap at each end.
	local qa = reach * reach - ( py - ay ) * ( py - ay )
	if qa > 0 then
		local s = sqrt( qa )
		lo, hi = ax - s, ax + s
	end

	local qb = reach * reach - ( py - by ) * ( py - by )
	if qb > 0 then
		local s = sqrt( qb )
		lo, hi = min( lo, bx - s ), max( hi, bx + s )
	end

	-- The band along the segment: perpendicular distance under `reach`, with
	-- the foot of the perpendicular between the two ends.
	if len > 0 then
		local dx, dy = bx - ax, by - ay
		local oy = py - ay
		local bandLo, bandHi = -math.huge, math.huge

		if dy ~= 0 then
			local p, q = ( oy * dx - reach * len ) / dy, ( oy * dx + reach * len ) / dy
			if p > q then p, q = q, p end
			bandLo, bandHi = ax + p, ax + q
		elseif abs( oy ) >= reach then
			bandLo, bandHi = math.huge, -math.huge
		end

		if dx ~= 0 then
			local p, q = -oy * dy / dx, ( len * len - oy * dy ) / dx
			if p > q then p, q = q, p end
			bandLo, bandHi = max( bandLo, ax + p ), min( bandHi, ax + q )
		elseif oy * dy < 0 or oy * dy > len * len then
			bandLo, bandHi = math.huge, -math.huge
		end

		if bandLo <= bandHi then lo, hi = min( lo, bandLo ), max( hi, bandHi ) end
	end

	if lo > hi then return nil end
	return lo, hi
end

--- Brush coverage for the stroke `pts` from point `from` onwards, folded into
--- the sparse map `cov` (pixel index -> 0..255) by keeping the larger value -
--- exactly how Shape.brush combines overlapping capsules.
---
--- Every pixel whose coverage rises is appended to `list` once per call,
--- tracked through `stamp` and `serial`, so a stroke drawn under the pointer
--- recomputes only what its newest segments changed. Without a `stamp`, each
--- pixel is listed the first time it is covered at all, which is all a whole
--- stroke applied in one go needs. Returns the length of `list`, then the
--- rectangle the dabs reached (x0, y0, x1, y1; empty when x0 > x1).
local function BrushCover( pts, from, w, h, radius, hardness, cov, stamp, serial, list )
	local n = floor( #pts / 2 )
	local count = #list
	local bx0, by0, bx1, by1 = w, h, -1, -1
	if n < 1 then return count, bx0, by0, bx1, by1 end

	-- The same set-up as Shape.brush; see the note on hardness there.
	local r = radius * ( ( w + h ) * 0.5 )
	if r < 0.5 then r = 0.5 end

	local outer = r + 0.5
	local inner = ( r - 0.5 ) * hardness
	local fade  = outer - inner

	local function Dab( ax, ay, bx, by )
		local x0 = max( floor( min( ax, bx ) - r - 1 ), 0 )
		local x1 = min( math.ceil( max( ax, bx ) + r + 1 ), w - 1 )
		local y0 = max( floor( min( ay, by ) - r - 1 ), 0 )
		local y1 = min( math.ceil( max( ay, by ) + r + 1 ), h - 1 )
		if x0 > x1 or y0 > y1 then return end

		if x0 < bx0 then bx0 = x0 end
		if y0 < by0 then by0 = y0 end
		if x1 > bx1 then bx1 = x1 end
		if y1 > by1 then by1 = y1 end

		local dx, dy = bx - ax, by - ay
		local len2   = dx * dx + dy * dy
		local len    = sqrt( len2 )

		for y = y0, y1 do
			local row = y * w
			local py  = y + 0.5

			-- Shape.brush visits the segment's whole bounding box. Only the
			-- capsule's own span of this row can have coverage, which on a
			-- diagonal is well under half the box.
			local lo, hi = RowSpan( ax, ay, bx, by, len, py, outer )

			if lo then
				local rx0 = max( floor( lo - 0.5 ) - 1, x0 )
				local rx1 = min( math.ceil( hi - 0.5 ) + 1, x1 )

				for x = rx0, rx1 do
					local i   = row + x + 1
					local was = cov[ i ]

					-- Already fully covered: nothing this capsule does can
					-- raise it, so the distance is not worth measuring.
					if was ~= 255 then
						local px = x + 0.5

						local t = 0
						if len2 > 0 then
							t = ( ( px - ax ) * dx + ( py - ay ) * dy ) / len2
							if t < 0 then t = 0 elseif t > 1 then t = 1 end
						end

						local ex = px - ( ax + dx * t )
						local ey = py - ( ay + dy * t )
						local d  = sqrt( ex * ex + ey * ey )

						local c = ( outer - d ) / fade
						if c > 0 then
							if c > 1 then c = 1 end

							local v = c * 255

							if was == nil or v > was then
								cov[ i ] = v

								if stamp then
									if stamp[ i ] ~= serial then
										stamp[ i ] = serial
										count = count + 1
										list[ count ] = i
									end
								elseif was == nil then
									count = count + 1
									list[ count ] = i
								end
							end
						end
					end
				end
			end
		end
	end

	if n == 1 then
		if from <= 1 then
			local x, y = pts[ 1 ] * w, pts[ 2 ] * h
			Dab( x, y, x, y )
		end
		return count, bx0, by0, bx1, by1
	end

	for i = max( from, 1 ), n - 1 do
		Dab( pts[ i * 2 - 1 ] * w, pts[ i * 2     ] * h,
		     pts[ i * 2 + 1 ] * w, pts[ i * 2 + 2 ] * h )
	end

	return count, bx0, by0, bx1, by1
end

--- True when a selection reads the image's pixels to resolve - "similar
--- colour" - which means its mask can differ from one step to the next and
--- must not be reused between them.
local function ReadsPixels( sel )
	for _, shape in ipairs( sel.shapes or {} ) do
		if shape.t == "wand" then return true end
	end
	return false
end

--- The selection a stroke is limited to, rasterised, or nil when it covers
--- everything. Strokes drawn inside the same selection share one: a session of
--- painting inside a model piece rasterises that piece once per composition
--- rather than once for every stroke in it.
local function ClipMask( clip, w, h, ctx, buf )
	local rctx = {
		pixels  = buf,
		src     = ctx.src,
		model   = ctx.model,
		slot    = ctx.slot,
		matpath = ctx.matpath,
		mask    = ctx.mask,
	}

	local cache = ctx.clip_cache
	if not cache or ReadsPixels( clip ) then return S.Rasterize( clip, w, h, rctx ) end

	local key = w .. "x" .. h .. "|" .. GEN.Canonical( clip )
	local hit = cache[ key ]

	if hit == nil then
		hit = S.Rasterize( clip, w, h, rctx ) or false
		cache[ key ] = hit
	end

	return hit or nil
end

--- Run a pointwise step over a list of pixels instead of over a whole image.
---
--- The pixels are gathered into a one-row buffer with their coverage beside
--- them, the step's own Run function does the work, and the results are
--- scattered back into `buf`. `from` is where each pixel's starting value is
--- read - the image itself, or the copy a live stroke kept before it touched
--- that pixel - indexed like the image, so it may be sparse.
local function RunGathered( fn, op, ctx, buf, list, count, coverage, from )
	local sub = { w = count, h = 1, r = {}, g = {}, b = {}, a = {} }
	local sr, sg, sb, sa = sub.r, sub.g, sub.b, sub.a
	local fr, fg, fb, fa = from.r, from.g, from.b, from.a

	for j = 1, count do
		local i = list[ j ]
		sr[ j ], sg[ j ], sb[ j ], sa[ j ] = fr[ i ], fg[ i ], fb[ i ], fa[ i ]
	end

	-- The parts of the context a pointwise step reads. The original image has
	-- to travel at the same positions as the pixels it is restored into.
	local subctx = {
		src  = ctx.src,
		fill = ctx.fill,
		preserve_source_mask = ctx.preserve_source_mask,
	}

	local base = ctx.base
	if base and op.op == "revert" then
		local gr, gg, gb, ga = {}, {}, {}, {}
		local br, bg, bb, ba = base.r, base.g, base.b, base.a

		for j = 1, count do
			local i = list[ j ]
			gr[ j ], gg[ j ], gb[ j ], ga[ j ] = br[ i ], bg[ i ], bb[ i ], ba[ i ]
		end

		subctx.base = { r = gr, g = gg, b = gb, a = ga }
	end

	fn( sub, op, coverage, subctx )

	local dr, dg, db, da = buf.r, buf.g, buf.b, buf.a
	for j = 1, count do
		local i = list[ j ]
		dr[ i ], dg[ i ], db[ i ], da[ i ] = sr[ j ], sg[ j ], sb[ j ], sa[ j ]
	end
end

--- Coverage for each listed pixel the way Rasterize finishes a mask: the
--- brush, scaled by the clip, rounded once.
local function ListCoverage( list, count, cov, clip )
	local coverage = {}

	for j = 1, count do
		local i = list[ j ]
		local v = cov[ i ]

		if clip then v = v * ( clip[ i ] / 255 ) end
		coverage[ j ] = ( v < 0 ) and 0 or ( v > 255 ) and 255 or floor( v + 0.5 )
	end

	return coverage
end

--- Apply a stroke step to the pixels its brush covers. Returns the rectangle
--- the brush reached (buffer pixels, inclusive), or false when it missed the
--- image entirely.
local function ExecuteStroke( buf, op, ctx, fn )
	local w, h  = buf.w, buf.h
	local sel   = op.sel
	local shape = sel.shapes[ 1 ]

	local cov, list = {}, {}
	local count, x0, y0, x1, y1 = BrushCover( shape.pts, 1, w, h, shape.r,
		shape.hardness or 1, cov, nil, nil, list )
	if count == 0 then return false end

	local clip = sel.clip and ClipMask( sel.clip, w, h, ctx, buf )
	RunGathered( fn, op, ctx, buf, list, count, ListCoverage( list, count, cov, clip ), buf )

	return x0, y0, x1, y1
end

--- Apply one step to `buf` in place.
---
--- A brush stroke returns the rectangle it can have changed (buffer pixels,
--- inclusive), or false when its brush missed the image; every other step
--- returns nothing, meaning it may have changed anything.
function OPS.Execute( buf, op, ctx )
	local fn = Run[ op.op ]
	if not fn then return end

	if OPS.IsStroke( op ) then
		return ExecuteStroke( buf, op, ctx or {}, fn )
	end

	local mask

	if op.sel then
		ctx = ctx or {}

		mask = S.Rasterize( op.sel, buf.w, buf.h, {
			pixels  = buf,
			src     = ctx.src,
			model   = ctx.model,
			slot    = ctx.slot,
			matpath = ctx.matpath,
			mask    = ctx.mask,
		} )
	end

	fn( buf, op, mask, ctx )
end

--- The image an edit recipe starts from, before any step has run.
---
--- `w`/`h` override the recipe's own, which is what lets the editor work at a
--- fraction of the resolution while dragging and still bake the full one on
--- save. They are a pair rather than one number because a texture is allowed
--- to be oblong, and working on a squashed copy of an oblong sheet would put
--- every edit in the wrong place on it.
function OPS.Base( recipe, w, h )
	local rw, rh = GEN.Dims( recipe )

	w = w or rw
	h = h or ( ( w == rw ) and rh or w )

	if recipe.src and recipe.src ~= "" then
		-- `opaque` controls how the image is displayed, not whether its alpha
		-- bytes survive. Source routinely stores shader masks in an opaque base
		-- or bump texture. Only flatten that mask when an explicit alpha-editing
		-- operation repurposes the channel as transparency.
		local sourceHasAlpha = GEN.SourceHasAlpha and GEN.SourceHasAlpha( recipe.src )
		local preserveMask = OPS.PreservesSourceMask( recipe, sourceHasAlpha )
		local src = GEN.ReadSource( recipe.src, w, h,
			not recipe.opaque or preserveMask, preserveMask )
		if not src then return nil, "could not read " .. recipe.src end
		return BUF.FromSource( src ), src
	end

	return BUF.Solid( w, h, recipe.fill or { 255, 255, 255, 255 } )
end

--- The context every step's selection resolves against.
---
--- `src` is the source as it was read for the image being composed. Besides
--- deciding how its alpha is treated, it is what "restore the original" brings
--- back, so a step that may restore has to be given it.
function OPS.Context( recipe, src )
	return {
		src     = recipe.src,
		model   = recipe.model,
		slot    = recipe.slot,
		matpath = recipe.matpath,
		mask    = recipe.mask,
		preserve_source_mask = OPS.PreservesSourceMask( recipe,
			src and src.alpha or nil ),

		-- The image the steps start from: the source read, or the flat colour
		-- a blank image is filled with.
		base = ( recipe.src and recipe.src ~= "" ) and src or nil,
		fill = recipe.fill,

		-- Clip masks shared by the strokes drawn inside one selection, for as
		-- long as this context lives - one composition.
		clip_cache = {},
	}
end

--- Run a recipe's steps over a fresh base image and hand back the buffer.
---
--- Unlike OPS.Render this does not sanitise first, so it can be used on the
--- half-finished recipe the editor is holding - including one with no steps in
--- it yet, which is simply the source texture.
---
--- `upto` stops after that many steps, which is how the editor scrubs back to
--- an earlier point in the list.
function OPS.Compose( recipe, w, h, upto )
	local buf, src = OPS.Base( recipe, w, h )
	if not buf then return nil, src end

	local ctx  = OPS.Context( recipe, src )
	local last = upto or #( recipe.ops or {} )

	for i = 1, last do
		local op = recipe.ops[ i ]
		if op and op.on ~= false then OPS.Execute( buf, op, ctx ) end
	end

	return buf, src
end

---------------------------------------------------------------------------
-- A stroke while it is being drawn
---------------------------------------------------------------------------
-- The editor draws a stroke under the pointer while it is being made, instead
-- of showing a thin line and nothing else until the button is let go - which
-- left the eraser in particular with no way to see what it was rubbing out.
--
-- Each stretch of the stroke recomputes only the pixels whose coverage it
-- raised, and each of those from the value it had before the stroke began,
-- with the stroke's whole coverage so far. Nothing is compounded onto its own
-- preview, so what is on screen while drawing is what the finished step will
-- produce, and Restore can put every pixel back exactly. The editor does that
-- on release and then adds the real step, so the recipe stays the only thing
-- that decides the picture.

local Stroke = {}
Stroke.__index = Stroke

--- Start drawing the stroke step `op` onto `buf`. Only its brush and its kind
--- of step are read now; the points arrive through Extend.
---
--- `clip` is the selection the stroke is limited to, already rasterised at the
--- buffer's size, or nil for everywhere. The editor is holding that mask
--- anyway, so a live stroke borrows it instead of rasterising it again.
function OPS.BeginStroke( buf, op, ctx, clip )
	local shape = op.sel and op.sel.shapes and op.sel.shapes[ 1 ] or {}

	return setmetatable( {
		buf  = buf, op = op, ctx = ctx or {}, clip = clip,
		fn   = Run[ op.op ],
		radius = shape.r or 0.03, hardness = shape.hardness or 1,

		drawn  = 0,   -- how many of the stroke's points are already drawn
		cov    = {},  -- pixel -> brush coverage so far
		stamp  = {},
		serial = 0,
		before = { r = {}, g = {}, b = {}, a = {} },  -- pixel -> its value before
		kept   = {},  -- the pixels held in `before`, in the order they were kept

		covered = false,  -- the brush has passed over a pixel of the image
		reached = false,  -- ...and the selection let it act on one
		changed = false,  -- ...and one now differs from before the stroke
	}, Stroke )
end

local function Grow( box, x0, y0, x1, y1 )
	if not box then return { x0, y0, x1, y1 } end

	if x0 < box[ 1 ] then box[ 1 ] = x0 end
	if y0 < box[ 2 ] then box[ 2 ] = y0 end
	if x1 > box[ 3 ] then box[ 3 ] = x1 end
	if y1 > box[ 4 ] then box[ 4 ] = y1 end

	return box
end

--- Draw whatever part of `pts` - the whole stroke so far, as the canvas keeps
--- it - is new. Returns true when any pixel was recomputed.
function Stroke:Extend( pts )
	local n = floor( #pts / 2 )
	if self.restored or not self.fn or n <= self.drawn then return false end

	local buf  = self.buf
	local w, h = buf.w, buf.h

	self.serial = self.serial + 1

	local rose = {}
	local count, x0, y0, x1, y1 = BrushCover( pts, max( self.drawn, 1 ), w, h,
		self.radius, self.hardness, self.cov, self.stamp, self.serial, rose )

	self.drawn = n
	if count == 0 then return false end
	self.covered = true

	local before = self.before
	local pr, pg, pb, pa = before.r, before.g, before.b, before.a
	local br, bg, bb, ba = buf.r, buf.g, buf.b, buf.a
	local kept = self.kept

	-- The first time the stroke reaches a pixel is the last time its own
	-- value is still in the image.
	for j = 1, count do
		local i = rose[ j ]
		if pr[ i ] == nil then
			pr[ i ], pg[ i ], pb[ i ], pa[ i ] = br[ i ], bg[ i ], bb[ i ], ba[ i ]
			kept[ #kept + 1 ] = i
		end
	end

	local coverage = ListCoverage( rose, count, self.cov, self.clip )

	if not self.reached then
		for j = 1, count do
			if coverage[ j ] > 0 then self.reached = true break end
		end
	end

	RunGathered( self.fn, self.op, self.ctx, buf, rose, count, coverage, before )

	if not self.changed then
		for j = 1, count do
			local i = rose[ j ]
			if br[ i ] ~= pr[ i ] or bg[ i ] ~= pg[ i ] or bb[ i ] ~= pb[ i ]
				or ba[ i ] ~= pa[ i ] then
				self.changed = true
				break
			end
		end
	end

	self.dirty = Grow( self.dirty, x0, y0, x1, y1 )
	self.span  = Grow( self.span,  x0, y0, x1, y1 )
	return true
end

--- The rectangle (buffer pixels, inclusive) recomputed since this was last
--- asked, for the canvas to upload again; nothing when there is none.
function Stroke:TakeDirty()
	local box = self.dirty
	self.dirty = nil
	if not box then return nil end
	return box[ 1 ], box[ 2 ], box[ 3 ], box[ 4 ]
end

--- Put every pixel the stroke touched back the way it was before it began,
--- and return the rectangle they span so it can be shown again. The stroke
--- draws nothing more afterwards.
function Stroke:Restore()
	local buf, before = self.buf, self.before
	local br, bg, bb, ba = buf.r, buf.g, buf.b, buf.a
	local pr, pg, pb, pa = before.r, before.g, before.b, before.a

	for _, i in ipairs( self.kept ) do
		br[ i ], bg[ i ], bb[ i ], ba[ i ] = pr[ i ], pg[ i ], pb[ i ], pa[ i ]
	end

	self.restored = true
	self.kept, self.dirty = {}, nil

	local box = self.span
	self.span = nil
	if not box then return nil end
	return box[ 1 ], box[ 2 ], box[ 3 ], box[ 4 ]
end

---------------------------------------------------------------------------
-- Imported image layers (CPU fallback)
---------------------------------------------------------------------------
-- The normal editor and exporter draw layers as full-resolution GPU quads.
-- This bounded CPU path exists for stripped-down engine branches where the
-- capture API is unavailable, and is also useful to test the transform math
-- without a renderer.

OPS.LAYER_SAMPLE_MAX = 256

function OPS.LayerSampleDims( layer, canvasW, canvasH )
	local sw, sh = GEN.SourceSize( layer and layer.src, OPS.LAYER_SAMPLE_MAX,
		OPS.LAYER_SAMPLE_MAX )
	local target = max( 32, math.ceil( max(
		( layer and layer.w or 1 ) * canvasW,
		( layer and layer.h or 1 ) * canvasH ) ) )

	return GEN.FitWithin( sw, sh, min( OPS.LAYER_SAMPLE_MAX, target ) )
end

local function SampleLayer( src, u, v )
	if src.w <= 1 or src.h <= 1 then
		return src.r[ 1 ] or 0, src.g[ 1 ] or 0, src.b[ 1 ] or 0, src.a[ 1 ] or 255
	end

	-- Match the texel-centre convention used by the GPU quad path. A destination
	-- pixel at normalized coordinate 0.5 / width must land on source texel zero;
	-- mapping across (width - 1) instead blurs even an identity-sized layer.
	local fx = math.Clamp( u * src.w - 0.5, 0, src.w - 1 )
	local fy = math.Clamp( v * src.h - 0.5, 0, src.h - 1 )
	local x0, y0 = floor( fx ), floor( fy )
	local x1, y1 = min( x0 + 1, src.w - 1 ), min( y0 + 1, src.h - 1 )
	local tx, ty = fx - x0, fy - y0

	local i00 = y0 * src.w + x0 + 1
	local i10 = y0 * src.w + x1 + 1
	local i01 = y1 * src.w + x0 + 1
	local i11 = y1 * src.w + x1 + 1

	local function Ch( field )
		local a = field[ i00 ] * ( 1 - tx ) + field[ i10 ] * tx
		local b = field[ i01 ] * ( 1 - tx ) + field[ i11 ] * tx
		return a * ( 1 - ty ) + b * ty
	end

	return Ch( src.r ), Ch( src.g ), Ch( src.b ), Ch( src.a )
end

function OPS.CompositeLayers( buf, layers, preserveDestAlpha )
	if not istable( layers ) or #layers == 0 then return buf end

	local bw, bh = buf.w, buf.h

	for _, raw in ipairs( layers ) do
		local layer = OPS.SanitizeLayer( raw )
		if layer and layer.on ~= false and layer.opacity > 0 then
			local sw, sh = OPS.LayerSampleDims( layer, bw, bh )
			local src = GEN.ReadSource( layer.src, sw, sh, not layer.opaque )
			if not src then return nil, "could not read layer " .. layer.src end

			local cx, cy = layer.x * bw, layer.y * bh
			local lw, lh = layer.w * bw, layer.h * bh
			local hw, hh = lw * 0.5, lh * 0.5
			local rad = math.rad( layer.angle or 0 )
			local co, si = math.cos( rad ), math.sin( rad )

			-- Tight bounds around the rotated rectangle keep a small decal from
			-- paying for a pass over the whole sheet.
			local ex = abs( hw * co ) + abs( hh * si )
			local ey = abs( hw * si ) + abs( hh * co )
			local x0 = max( 0, floor( cx - ex ) )
			local y0 = max( 0, floor( cy - ey ) )
			local x1 = min( bw - 1, math.ceil( cx + ex ) )
			local y1 = min( bh - 1, math.ceil( cy + ey ) )

			for y = y0, y1 do
				for x = x0, x1 do
					local dx, dy = x + 0.5 - cx, y + 0.5 - cy
					local lx =  co * dx + si * dy
					local ly = -si * dx + co * dy
					local u, v = lx / lw + 0.5, ly / lh + 0.5

					if u >= 0 and u <= 1 and v >= 0 and v <= 1 then
						if layer.flipx then u = 1 - u end
						if layer.flipy then v = 1 - v end

						local sr, sg, sb, sa = SampleLayer( src, u, v )
						local t = ( sa / 255 ) * layer.opacity

						if t > 0 then
							local i = y * bw + x + 1
							if preserveDestAlpha then
								-- A mask-bearing base is visually opaque. Composite only
								-- the visible colour and leave its shader-data byte exact.
								local keep = 1 - t
								buf.r[ i ] = Byte( sr * t + buf.r[ i ] * keep )
								buf.g[ i ] = Byte( sg * t + buf.g[ i ] * keep )
								buf.b[ i ] = Byte( sb * t + buf.b[ i ] * keep )
							else
								local da = buf.a[ i ] / 255
								local oa = t + da * ( 1 - t )

								if oa > 0 then
									local dk = da * ( 1 - t )
									buf.r[ i ] = Byte( ( sr * t + buf.r[ i ] * dk ) / oa )
									buf.g[ i ] = Byte( ( sg * t + buf.g[ i ] * dk ) / oa )
									buf.b[ i ] = Byte( ( sb * t + buf.b[ i ] * dk ) / oa )
								end
								buf.a[ i ] = Byte( oa * 255 )
							end
						end
					end
				end
			end
		end
	end

	return buf
end

function OPS.ComposeWithLayers( recipe, w, h, upto )
	local buf, src = OPS.Compose( recipe, w, h, upto )
	if not buf then return nil, src end

	local layered, err = OPS.CompositeLayers( buf, recipe.layers,
		OPS.PreservesSourceMask( recipe, src and src.alpha or nil ) )
	if not layered then return nil, err end
	return layered, src
end

---------------------------------------------------------------------------
-- GPU export
---------------------------------------------------------------------------
-- The editor intentionally works on at most 512 * 512 pixels.  Repeating the
-- recipe at 2048 * 2048 on save used to allocate the source, a mutable copy,
-- a flattened copy and the PNG rows as Lua objects all at once.  On the
-- 32-bit-ish LuaJIT heap that is enough to hang and commonly enough to crash.
--
-- Instead, draw the sharp source into a full-size render target, copy only the
-- changed working-resolution runs over it, capture packed RGB, and encode that
-- stream directly. It is the same composition the canvas shows, without ever
-- representing the full-size image as millions of Lua numbers.

local uploadMat

local function UploadMaterial()
	if uploadMat then return uploadMat end

	uploadMat = CreateMaterial( "advmat_pixel_upload", "UnlitGeneric", {
		[ "$basetexture" ] = "color/white",
		[ "$translucent" ] = "1",
		[ "$vertexcolor" ] = "1",
		[ "$vertexalpha" ] = "1",
		[ "$ignorez" ]     = "1",
		[ "$nocull" ]      = "1",
		[ "$nolod" ]       = "1",
	} )

	return uploadMat
end

local function Vertex( pos, x, y, u, v, r, g, b, a )
	pos:SetUnpacked( x, y, 0 )
	mesh.Position( pos )
	mesh.TexCoord( 0, u, v )
	mesh.Color( r, g, b, a )
	mesh.AdvanceVertex()
end

local function BeginCopyBlend()
	-- Source replaces destination in both colour and alpha.  This is essential
	-- for alpha zero: the surface library treats a draw with alpha zero as a
	-- no-op, and ordinary alpha blending would preserve the old opaque pixel.
	render.OverrideBlend( true,
		BLEND_ONE, BLEND_ZERO, BLENDFUNC_ADD,
		BLEND_ONE, BLEND_ZERO, BLENDFUNC_ADD )
end

local function BeginOverBlend()
	render.OverrideBlend( true,
		BLEND_SRC_ALPHA, BLEND_ONE_MINUS_SRC_ALPHA, BLENDFUNC_ADD,
		BLEND_ONE, BLEND_ONE_MINUS_SRC_ALPHA, BLENDFUNC_ADD )
end

--- Copy a full texture into a rectangle with exact 0..1 UVs - or, given
--- `u0, v0, u1, v1`, exactly that part of it. The canvas uses the second form
--- to redraw the untouched source under one brush stroke: the same quad edges
--- and the same texture coordinates the whole-sheet copy gives those texels,
--- so the patch lands on the identical result.
local function DrawMaterialCopy( mat, x, y, w, h, u0, v0, u1, v1 )
	u0, v0, u1, v1 = u0 or 0, v0 or 0, u1 or 1, v1 or 1

	render.SetMaterial( mat )
	BeginCopyBlend()

	local pos = Vector()
	mesh.Begin( MATERIAL_QUADS, 1 )
		Vertex( pos, x,     y,     u0, v0, 255, 255, 255, 255 )
		Vertex( pos, x + w, y,     u1, v0, 255, 255, 255, 255 )
		Vertex( pos, x + w, y + h, u1, v1, 255, 255, 255, 255 )
		Vertex( pos, x,     y + h, u0, v1, 255, 255, 255, 255 )
	mesh.End()

	render.OverrideBlend( false )
end

GEN.DrawMaterialCopy = DrawMaterialCopy

--- Draw a material or flat vertex colour with ordinary source-over blending.
--- This is used by the black/white export recovery passes, where the opaque
--- background makes the fixed-function colour result exact.
local function DrawMaterialOver( mat, x, y, w, h, r, g, b, a )
	render.SetMaterial( mat )
	BeginOverBlend()

	r, g, b, a = r or 255, g or 255, b or 255, a or 255
	local pos = Vector()
	mesh.Begin( MATERIAL_QUADS, 1 )
		Vertex( pos, x,     y,     0, 0, r, g, b, a )
		Vertex( pos, x + w, y,     1, 0, r, g, b, a )
		Vertex( pos, x + w, y + h, 1, 1, r, g, b, a )
		Vertex( pos, x,     y + h, 0, 1, r, g, b, a )
	mesh.End()

	render.OverrideBlend( false )
end

--- Draw the ordered image-layer stack into the current render target. Each
--- source remains a real texture on the GPU, so a 4K export does not enlarge a
--- 512px CPU preview or turn a photograph into one quad per changed pixel.
function OPS.DrawLayers( layers, w, h, preserveDestAlpha )
	if not istable( layers ) or #layers == 0 then return true end

	local pos = Vector()

	for _, raw in ipairs( layers ) do
		local layer = OPS.SanitizeLayer( raw )
		if layer and layer.on ~= false and layer.opacity > 0 then
			local hasAlpha = not layer.opaque and GEN.SourceHasAlpha( layer.src )
			local mat = GEN.SourceMaterial( layer.src, not layer.opaque and hasAlpha ~= false )
			if not mat or mat:IsError() then
				render.OverrideBlend( false )
				return false, "could not draw layer " .. layer.src
			end

			local cx, cy = layer.x * w, layer.y * h
			local hw, hh = layer.w * w * 0.5, layer.h * h * 0.5
			local rad = math.rad( layer.angle or 0 )
			local co, si = math.cos( rad ), math.sin( rad )
			local alpha = Byte( layer.opacity * 255 )

			local function Point( lx, ly )
				return cx + lx * co - ly * si, cy + lx * si + ly * co
			end

			local x1, y1 = Point( -hw, -hh )
			local x2, y2 = Point(  hw, -hh )
			local x3, y3 = Point(  hw,  hh )
			local x4, y4 = Point( -hw,  hh )
			local u0, u1 = layer.flipx and 1 or 0, layer.flipx and 0 or 1
			local v0, v1 = layer.flipy and 1 or 0, layer.flipy and 0 or 1

			local function DrawQuad( material, r, g, b, a )
				render.SetMaterial( material )
				mesh.Begin( MATERIAL_QUADS, 1 )
					Vertex( pos, x1, y1, u0, v0, r, g, b, a )
					Vertex( pos, x2, y2, u1, v0, r, g, b, a )
					Vertex( pos, x3, y3, u1, v1, r, g, b, a )
					Vertex( pos, x4, y4, u0, v1, r, g, b, a )
				mesh.End()
			end

			if preserveDestAlpha then
				render.OverrideAlphaWriteEnable( true, false )
			end

			if layer.opaque then
				if not render.OverrideColorWriteEnable or not render.OverrideAlphaWriteEnable then
					render.OverrideBlend( false )
					if preserveDestAlpha and render.OverrideAlphaWriteEnable then
						render.OverrideAlphaWriteEnable( true, true )
					end
					return false, "this renderer cannot ignore a layer's source alpha"
				end
				-- "Ignore source alpha" must not merely remove $translucent: the
				-- shader can still output the VTF's alpha and OverrideBlend would use
				-- it. Build constant-opacity source-over explicitly in three small
				-- passes: attenuate destination RGB, add modulated source RGB, then
				-- update destination alpha with a flat constant-alpha quad.
				local opaqueOK, opaqueErr = pcall( function()
					render.OverrideAlphaWriteEnable( true, false )
					render.OverrideBlend( true,
						BLEND_ZERO, BLEND_ONE_MINUS_SRC_ALPHA, BLENDFUNC_ADD,
						BLEND_ZERO, BLEND_ONE, BLENDFUNC_ADD )
					DrawQuad( UploadMaterial(), 0, 0, 0, alpha )

					render.OverrideBlend( true,
						BLEND_ONE, BLEND_ONE, BLENDFUNC_ADD,
						BLEND_ZERO, BLEND_ONE, BLENDFUNC_ADD )
					DrawQuad( mat, alpha, alpha, alpha, 255 )
					render.OverrideBlend( false )

					if not preserveDestAlpha then
						render.OverrideAlphaWriteEnable( true, true )
						render.OverrideColorWriteEnable( true, false )
						BeginOverBlend()
						DrawQuad( UploadMaterial(), 255, 255, 255, alpha )
					end
				end )

				render.OverrideBlend( false )
				render.OverrideColorWriteEnable( false, true )
				render.OverrideAlphaWriteEnable( true, true )
				if not opaqueOK then return false, tostring( opaqueErr ) end
			else
				-- Porter-Duff source-over. Transparent exports are subsequently drawn
				-- over black and white and recovered to straight RGBA, since fixed-
				-- function blending itself stores the colour numerator (premultiplied).
				BeginOverBlend()
				DrawQuad( mat, 255, 255, 255, alpha )
			end
			render.OverrideBlend( false )
			if preserveDestAlpha then
				render.OverrideAlphaWriteEnable( true, true )
			end
		end
	end

	render.OverrideBlend( false )
	return true
end

--- Copy RGBA runs into the current render target.
---
--- A raw mesh is used deliberately.  `surface.DrawRect` discards alpha-zero
--- draws before they reach the blend stage, which made the eraser update the
--- CPU buffer while leaving both previews unchanged.
function GEN.DrawPixelRuns( runs, first, last, scaleX, scaleY )
	if not runs or #runs == 0 then return end

	first  = math.max( first or 1, 1 )
	last   = math.min( last or #runs, #runs )
	scaleX = scaleX or 1
	scaleY = scaleY or 1

	if first > last then return end

	render.SetMaterial( UploadMaterial() )
	BeginCopyBlend()

	-- Keep each dynamic mesh comfortably below Source's vertex limit.
	local batch = 4096
	local pos   = Vector()

	for base = first, last, batch do
		local stop = math.min( base + batch - 1, last )
		mesh.Begin( MATERIAL_QUADS, stop - base + 1 )

		for i = base, stop do
			local run = runs[ i ]
			local x = run[ 1 ] * scaleX
			local y = run[ 2 ] * scaleY
			local w = run[ 3 ] * scaleX
			local h = scaleY
			local r, g, b, a = run[ 4 ], run[ 5 ], run[ 6 ], run[ 7 ]

			Vertex( pos, x,     y,     0, 0, r, g, b, a )
			Vertex( pos, x + w, y,     1, 0, r, g, b, a )
			Vertex( pos, x + w, y + h, 1, 1, r, g, b, a )
			Vertex( pos, x,     y + h, 0, 1, r, g, b, a )
		end

		mesh.End()
	end

	render.OverrideBlend( false )
end

--- Render edited runs over a solid background while preserving replacement
--- semantics. Each changed rectangle first removes the source pixel by copying
--- the background back into that area, then composites the edited straight
--- RGBA value over it. The result is the exact visible colour for that chosen
--- background, including an erase whose alpha is zero.
local function DrawVisibleRuns( runs, scaleX, scaleY, background )
	if not runs or #runs == 0 then return end
	scaleX, scaleY = scaleX or 1, scaleY or 1
	background = Byte( background or 0 )

	local mat = UploadMaterial()
	local batch = 4096
	local pos = Vector()

	local function Pass( reset )
		render.SetMaterial( mat )
		if reset then BeginCopyBlend() else BeginOverBlend() end

		for base = 1, #runs, batch do
			local stop = math.min( base + batch - 1, #runs )
			mesh.Begin( MATERIAL_QUADS, stop - base + 1 )

			for i = base, stop do
				local run = runs[ i ]
				local x, y = run[ 1 ] * scaleX, run[ 2 ] * scaleY
				local w, h = run[ 3 ] * scaleX, scaleY
				local r, g, b, a

				if reset then
					r, g, b, a = background, background, background, 255
				else
					r, g, b, a = run[ 4 ], run[ 5 ], run[ 6 ], run[ 7 ]
				end

				Vertex( pos, x,     y,     0, 0, r, g, b, a )
				Vertex( pos, x + w, y,     1, 0, r, g, b, a )
				Vertex( pos, x + w, y + h, 1, 1, r, g, b, a )
				Vertex( pos, x,     y + h, 0, 1, r, g, b, a )
			end

			mesh.End()
		end

		render.OverrideBlend( false )
	end

	Pass( true )
	Pass( false )
end

local function HasVisibleLayers( layers )
	for _, raw in ipairs( layers or {} ) do
		local layer = OPS.SanitizeLayer( raw )
		if layer and layer.on ~= false and layer.opacity > 0 then return true end
	end
	return false
end

local function CaptureRGB( w, h )
	local data = GEN.CaptureRawRGB( w, h )
	if not data then
		error( "engine RGB capture returned no image" )
	end
	return data
end

local function DrawVisiblePass( recipe, runs, src, w, h, workW, workH, background )
	render.Clear( background, background, background, 255, true, true )

	if recipe.src and recipe.src ~= "" then
		local mat = GEN.SourceMaterial( recipe.src, src and src.alpha or false )
		if not mat or mat:IsError() then error( "could not draw " .. recipe.src ) end
		if src and src.alpha then
			DrawMaterialOver( mat, 0, 0, w, h )
		else
			-- The recipe deliberately treats this source as opaque (or its VTF has
			-- no alpha). Copying avoids letting an irrelevant mask influence the
			-- visible black/white recovery passes.
			DrawMaterialCopy( mat, 0, 0, w, h )
		end
	else
		local fill = recipe.fill or { 255, 255, 255, 255 }
		DrawMaterialOver( UploadMaterial(), 0, 0, w, h,
			fill[ 1 ], fill[ 2 ], fill[ 3 ], fill[ 4 ] )
	end

	DrawVisibleRuns( runs, w / math.max( 1, workW ),
		h / math.max( 1, workH ), background )

	local layersOK, layersErr = OPS.DrawLayers( recipe.layers, w, h )
	if not layersOK then error( layersErr ) end
	return CaptureRGB( w, h )
end

local function DrawHiddenBasePass( recipe, runs, w, h, workW, workH )
	if recipe.src and recipe.src ~= "" then
		local mat = GEN.SourceMaterial( recipe.src, false )
		if not mat or mat:IsError() then error( "could not draw " .. recipe.src ) end
		render.Clear( 0, 0, 0, 255, true, true )
		DrawMaterialCopy( mat, 0, 0, w, h )
	else
		local fill = recipe.fill or { 255, 255, 255, 255 }
		render.Clear( fill[ 1 ], fill[ 2 ], fill[ 3 ], 255, true, true )
	end

	if runs and #runs > 0 then
		GEN.DrawPixelRuns( runs, 1, #runs,
			w / math.max( 1, workW ), h / math.max( 1, workH ) )
	end
	return CaptureRGB( w, h )
end

--- Capture the material's visible colour without letting a shader-mask alpha
--- attenuate it. RGB-only prefix runs replace that colour at working-image
--- coverage, while the native mask is recovered independently by the two
--- ordinary visible passes in CaptureFullResolutionAdjustmentSource.
local function DrawOpaqueRGBPass( recipe, runs, w, h, workW, workH )
	render.Clear( 0, 0, 0, 255, true, true )

	local mat = GEN.SourceMaterial( recipe.src, false )
	if not mat or mat:IsError() then
		error( "could not draw opaque colour from " .. tostring( recipe.src ) )
	end
	DrawMaterialCopy( mat, 0, 0, w, h )
	GEN.DrawPixelRuns( runs, 1, runs and #runs or 0,
		w / math.max( 1, workW ), h / math.max( 1, workH ) )
	return CaptureRGB( w, h )
end

local function CanCaptureEdit()
	local gpu = render and render.Capture and render.OverrideBlend and render.SetMaterial
		and mesh and mesh.Begin and mesh.End and isnumber( MATERIAL_QUADS )
		and isnumber( BLEND_ONE ) and isnumber( BLEND_ZERO )
		and isnumber( BLENDFUNC_ADD )
		and isnumber( BLEND_SRC_ALPHA ) and isnumber( BLEND_ONE_MINUS_SRC_ALPHA )
	if not gpu then return false end

	-- true = full GPU exporter, false = conclusively unsupported compatibility
	-- branch, nil = capture was transiently unavailable and must be retried.
	return GEN.CanCaptureRawRGB()
end

--- A trailing group of colour controls is made of point operations: every
--- output texel can be calculated from the matching composited texel without
--- looking at a neighbour or allocating a full-size Lua colour buffer. A
--- selection is retained as a compact coverage map and only decides how much of
--- that native texel is adjusted; it must never replace the texel with the
--- bounded editor preview. Earlier paint/erase steps can still be rendered as
--- bounded runs first.
local function IsIdentityAdjustment( op )
	return ( op.hue or 0 ) == 0 and ( op.sat or 1 ) == 1
		and ( op.val or 1 ) == 1 and ( op.bright or 0 ) == 0
		and ( op.contrast or 1 ) == 1 and ( op.desat or 0 ) == 0
		and not op.invert and ( op.gamma == nil or op.gamma == 1 )
		and op.posterize == nil and op.threshold == nil
end

local function FullResolutionAdjustments( recipe, maxOps )
	if HasVisibleLayers( recipe.layers ) then return nil end

	local out = {}
	local indices = {}
	local ops = recipe.ops or {}
	local prefixLast = 0

	for i = #ops, 1, -1 do
		local op = ops[ i ]
		if op and op.on ~= false then
			if op.op ~= "adjust" then
				prefixLast = i
				break
			end
			if not IsIdentityAdjustment( op ) then
				table.insert( out, 1, op )
				table.insert( indices, 1, i )
			end
		end
	end

	if #out == 0 then return nil end

	-- Keep the native encoder's worst case in the same complexity class as the
	-- bounded preview. If a pathological recipe stacks many adjustments, bake
	-- its oldest ones into the prefix and retain the newest deterministic suffix
	-- at native resolution. The same recipe and dimensions therefore always make
	-- the same bytes, independent of client speed.
	maxOps = maxOps and max( 1, floor( maxOps ) ) or #out
	while #out > maxOps do
		prefixLast = indices[ 1 ]
		table.remove( out, 1 )
		table.remove( indices, 1 )
	end

	return out, prefixLast
end

OPS.FullResolutionAdjustments = FullResolutionAdjustments

-- How many whole-image passes the native-resolution colour stage may make, as
-- a count of working-size images. Its own number rather than the step limit's:
-- it decides which adjustments are evaluated at full resolution, and so which
-- bytes a recipe saves as, so it must not move when the step limits do.
local NATIVE_ADJUST_STEPS = 64

local MASK_PACK_CHUNK = 8192

--- A selection mask is produced at the editor's bounded working dimensions,
--- but retaining it as Lua numbers is disproportionately expensive. Pack it to
--- one byte per work texel before the native-resolution encoder starts. The
--- mask controls coverage only; source colour is always read independently at
--- the requested output resolution.
local function PackCoverageMask( mask, count )
	if not mask then return nil end

	local chunks = {}
	for first = 1, count, MASK_PACK_CHUNK do
		local last = min( first + MASK_PACK_CHUNK - 1, count )
		local bytes = {}
		for i = first, last do
			bytes[ #bytes + 1 ] = string.char( Byte( mask[ i ] or 0 ) )
		end
		chunks[ #chunks + 1 ] = table.concat( bytes )
	end

	return table.concat( chunks )
end

--- Resolve each selected adjustment in recipe order. Colour-based selections
--- inspect the working image as it looked at that step, so advance a private
--- bounded copy after saving each mask. This preserves preview semantics while
--- the later encoder applies the actual colour maths to native source texels.
local function FullResolutionAdjustmentMasks( recipe, ops, prefix )
	local hasSelection = false
	for _, op in ipairs( ops ) do
		if op.sel then
			hasSelection = true
			break
		end
	end
	if not hasSelection then return nil end

	local work = BUF.Copy( prefix )
	local ctx = OPS.Context( recipe )
	local out = { w = work.w, h = work.h }

	for i, op in ipairs( ops ) do
		local mask
		if op.sel then
			mask = S.Rasterize( op.sel, work.w, work.h, {
				pixels  = work,
				src     = ctx.src,
				model   = ctx.model,
				slot    = ctx.slot,
				matpath = ctx.matpath,
				mask    = ctx.mask,
			} )
		end

		out[ i ] = mask and PackCoverageMask( mask, work.w * work.h ) or false

		Run.adjust( work, op, mask )
	end

	return out
end

local function CaptureFullResolutionAdjustmentSource(
	recipe, runs, buf, src, w, h, workW, workH )
	local preserveMask = OPS.PreservesSourceMask( recipe, src and src.alpha or nil )
	if preserveMask then
		-- Prefix paint is represented by bounded RGB runs, but its copied alpha
		-- must never replace the source's native-resolution shader mask. Capture
		-- the final straight RGB through the opaque sampler and derive A from
		-- untouched native source passes over black and white.
		local black = DrawVisiblePass( recipe, nil, src, w, h, workW, workH, 0 )
		local white = DrawVisiblePass( recipe, nil, src, w, h, workW, workH, 255 )
		local straight = DrawOpaqueRGBPass( recipe, runs, w, h, workW, workH )
		return black, white, nil, true, straight
	end

	-- Draw the source plus any earlier edits at the real requested dimensions.
	-- Transparent images need black and white passes to recover straight RGBA;
	-- opaque ones reuse one packed RGB string, keeping a 4K export bounded too.
	local black = DrawVisiblePass( recipe, runs, src, w, h, workW, workH, 0 )
	local fill = recipe.fill or { 255, 255, 255, 255 }
	local hasAlpha = BUF.HasAlpha( buf ) or ( src and src.alpha == true )
		or ( not src and ( fill[ 4 ] or 255 ) < 255 )
	local white, fallback

	if hasAlpha then
		white = DrawVisiblePass( recipe, runs, src, w, h, workW, workH, 255 )
		fallback = DrawHiddenBasePass( recipe, runs, w, h, workW, workH )
	else
		white = black
	end

	return black, white, fallback, hasAlpha
end

local function FullResolutionAdjustmentPixel( ops, masks, r, g, b, a, x, y, w, h )
	local maskIndex
	if masks then
		local mx = math.Clamp( floor( ( x + 0.5 ) * masks.w / w ), 0, masks.w - 1 )
		local my = math.Clamp( floor( ( y + 0.5 ) * masks.h / h ), 0, masks.h - 1 )
		maskIndex = my * masks.w + mx + 1
	end

	for i, op in ipairs( ops ) do
		local cov = 1
		local mask = masks and masks[ i ]

		if mask then
			-- Sample the bounded coverage at this output texel's centre. Nearest
			-- coverage keeps hard selections hard and costs one byte lookup; only
			-- the mask is scaled, never the source colour beneath it.
			cov = ( strbyte( mask, maskIndex ) or 0 ) / 255
		end

		if cov > 0 then
			local nr, ng, nb = AdjustedRGB( r, g, b, op )
			local keep = 1 - cov
			r = r * keep + nr * cov
			g = g * keep + ng * cov
			b = b * keep + nb * cov

			-- The normal buffer path commits one byte after every step. Preserve
			-- that ordering so stacked adjustments save exactly as they preview.
			r, g, b = Byte( r ), Byte( g ), Byte( b )
		end
	end
	return r, g, b, a
end

local function RenderTargetDimension( rt, mappingName, fallbackName )
	if not rt then return nil end
	for _, name in ipairs( { mappingName, fallbackName } ) do
		local fn = rt[ name ]
		if isfunction( fn ) then
			local ok, value = pcall( fn, rt )
			value = ok and tonumber( value ) or nil
			if value then return math.floor( value ) end
		end
	end
	return nil
end

function OPS.CapturePNG( recipe )
	local canCapture = CanCaptureEdit()
	if canCapture ~= true then
		return nil, canCapture == nil
			and "engine RGB capture is temporarily unavailable"
			or "engine PNG capture is unavailable"
	end

	local w, h   = GEN.Dims( recipe )
	local ww, wh = GEN.EditWorkDims( w, h )
	local nativeVisitBudget = NATIVE_ADJUST_STEPS * ( GEN.EDIT_WORK_PIXELS or ( 512 * 512 ) )
	local nativeAdjustLimit = max( 1, floor( nativeVisitBudget / max( 1, w * h ) ) )
	local fullAdjust, prefixLast = FullResolutionAdjustments( recipe, nativeAdjustLimit )
	local buf, src, fullMasks
	if fullAdjust then
		buf, src = OPS.Compose( recipe, ww, wh, prefixLast )
	else
		buf, src = OPS.Compose( recipe, ww, wh )
	end
	if not buf then return nil, src end
	if fullAdjust then
		fullMasks = FullResolutionAdjustmentMasks( recipe, fullAdjust, buf )
	end

	local rt = GetRenderTarget( "advmat_editbuild_" .. w .. "x" .. h, w, h )
	if not rt then return nil, "could not allocate the edit render target" end
	local actualW = RenderTargetDimension( rt, "GetMappingWidth", "Width" )
	local actualH = RenderTargetDimension( rt, "GetMappingHeight", "Height" )
	if actualW ~= w or actualH ~= h then
		return nil, string.format( "edit render target is %dx%d instead of %dx%d",
			actualW or -1, actualH or -1, w, h )
	end

	local runs = ( not fullAdjust or ( prefixLast or 0 ) > 0 )
		and BUF.BuildRuns( buf, src ) or nil
	local png, black, white, fallback, fullHasAlpha, fullStraightRGB
	local preserveMask = OPS.PreservesSourceMask( recipe, src and src.alpha or nil )
	local recoverStraight = not preserveMask
		and HasVisibleLayers( recipe.layers ) and BUF.HasAlpha( buf )

	render.PushRenderTarget( rt )
	render.OverrideAlphaWriteEnable( true, true )
	cam.Start2D()

	local ok, err = pcall( function()
		if fullAdjust then
			black, white, fallback, fullHasAlpha, fullStraightRGB =
				CaptureFullResolutionAdjustmentSource(
				recipe, runs, buf, src, w, h, ww, wh )
			return
		end

		if recoverStraight then
			-- Fixed-function blending stores the colour numerator in a transparent
			-- target. Two opaque-background passes recover a true straight-alpha
			-- PNG without a full-size Lua pixel buffer or a custom binary shader.
			black = DrawVisiblePass( recipe, runs, src, w, h, ww, wh, 0 )
			white = DrawVisiblePass( recipe, runs, src, w, h, ww, wh, 255 )
			fallback = DrawHiddenBasePass( recipe, runs, w, h, ww, wh )
			return
		end

		if recipe.src and recipe.src ~= "" then
			local sourceHasAlpha = src and src.alpha or false
			local mat = GEN.SourceMaterial( recipe.src, sourceHasAlpha )
			if not mat or mat:IsError() then error( "could not draw " .. recipe.src ) end

			-- Opaque sources are seeded solid and their unreliable shader alpha is
			-- blocked.  Edited runs below are allowed to replace it with zero.
			render.Clear( 0, 0, 0, sourceHasAlpha and 0 or 255, true, true )
			if not sourceHasAlpha then render.OverrideAlphaWriteEnable( true, false ) end
			DrawMaterialCopy( mat, 0, 0, w, h )
			if preserveMask then
				-- The translucent variant contributed the exact shader-mask A.
				-- Overwrite only RGB through the opaque variant so a zero mask
				-- never turns an otherwise visible texel black.
				local opaqueMat = GEN.SourceMaterial( recipe.src, false )
				if not opaqueMat or opaqueMat:IsError() then
					error( "could not draw opaque colour from " .. recipe.src )
				end
				render.OverrideAlphaWriteEnable( true, false )
				DrawMaterialCopy( opaqueMat, 0, 0, w, h )
				render.OverrideAlphaWriteEnable( true, true )
			elseif not sourceHasAlpha then
				render.OverrideAlphaWriteEnable( true, true )
			end
		else
			local fill = recipe.fill or { 255, 255, 255, 255 }
			render.Clear( fill[ 1 ], fill[ 2 ], fill[ 3 ], fill[ 4 ], true, true )
		end

		-- RGB edits must not replace native-resolution shader-mask alpha with
		-- their bounded working-copy samples.
		if preserveMask then render.OverrideAlphaWriteEnable( true, false ) end
		GEN.DrawPixelRuns( runs, 1, #runs, w / ww, h / wh )
		if preserveMask then render.OverrideAlphaWriteEnable( true, true ) end

		local layersOK, layersErr = OPS.DrawLayers(
			recipe.layers, w, h, preserveMask )
		if not layersOK then error( layersErr ) end

		png = render.Capture( {
			format = "png", x = 0, y = 0, w = w, h = h, alpha = true,
		} )
	end )

	-- Close every render state even when drawing or capture failed.  Leaving one
	-- of these active corrupts the rest of the frame instead of raising an error.
	render.OverrideBlend( false )
	cam.End2D()
	render.OverrideAlphaWriteEnable( false, false )
	render.PopRenderTarget()

	if not ok then return nil, tostring( err ) end
	if fullAdjust then
		local function Transform( r, g, b, a, x, y )
			return FullResolutionAdjustmentPixel(
				fullAdjust, fullMasks, r, g, b, a, x, y, w, h )
		end
		local encodedOK, encoded, encodeErr
		if fullHasAlpha then
			encodedOK, encoded, encodeErr = pcall(
				GEN.EncodeRecoveredPNG, black, white, w, h, fallback, Transform,
				fullStraightRGB )
		else
			encodedOK, encoded, encodeErr = pcall(
				GEN.EncodeMappedRGBPNG, black, w, h, Transform )
		end
		if not encodedOK then return nil, tostring( encoded ) end
		if not encoded or #encoded < 8 then
			return nil, encodeErr or "full-resolution adjustment encoding returned no image"
		end
		return encoded, w, h
	end
	if recoverStraight then
		local encodedOK, encoded, encodeErr = pcall(
			GEN.EncodeRecoveredPNG, black, white, w, h, fallback )
		if not encodedOK then return nil, tostring( encoded ) end
		if not encoded then return nil, encodeErr end
		return encoded, w, h
	end
	if not isstring( png ) or #png < 8 then return nil, "engine PNG capture returned no image" end

	return png, w, h
end

--- Run a whole edit recipe and hand back the finished buffer.
function OPS.Render( recipe )
	recipe = GEN.Sanitize( recipe )
	if not recipe then return nil, "the edit has no steps" end

	local w, h = GEN.Dims( recipe )

	return OPS.ComposeWithLayers( recipe, w, h )
end

GEN.Builders.edit = function( recipe )
	-- A machine that genuinely lacks render capture still gets the bounded CPU
	-- implementation below. A machine that supports capture but hits a transient
	-- material/RT/capture failure must report that failure so GEN can retry; using
	-- the low-resolution fallback there would permanently cache degraded pixels
	-- under the full-resolution recipe identity.
	local canCapture = CanCaptureEdit()
	if canCapture == nil then
		return nil, "engine RGB capture is temporarily unavailable"
	end
	if canCapture then
		local png, w, h = OPS.CapturePNG( recipe )
		if not png then return nil, w end
		return nil, w, h, nil, png
	end

	-- Older engine branches have no binary render.Capture formats. The CPU
	-- fallback is exact only while the requested image fits inside the work
	-- budget. Never write a smaller image under a larger recipe identity: that
	-- permanently caches the same blur this exporter is meant to prevent.
	local rw, rh = GEN.Dims( recipe )
	local w, h = GEN.EditWorkDims( rw, rh )
	if w ~= rw or h ~= rh then
		return nil, string.format(
			"this renderer cannot save %dx%d texture edits at full resolution", rw, rh )
	end

	local buf, err = OPS.ComposeWithLayers( recipe, w, h )
	if not buf then return nil, err end

	-- Only spend the fourth channel when there is transparency to store. A
	-- PNG without one is a quarter smaller and loads as fully opaque, which is
	-- exactly what it should be.
	local channels = BUF.HasAlpha( buf ) and 4 or 3

	return BUF.Flatten( buf, channels ), buf.w, buf.h, channels
end
