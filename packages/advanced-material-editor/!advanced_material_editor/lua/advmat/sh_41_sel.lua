--[[---------------------------------------------------------------------------
	Advanced Material Editor - selection recipes

	A selection says WHERE something applies: which part of a texture a fill
	covers, or which part of a texture a generator is allowed to write to. It
	is stored the same way everything else in this addon is stored - as a small
	description that every client can rebuild the identical pixels from - rather
	than as a bitmap, because a bitmap would have to be networked and a
	description is a few dozen bytes.

	A selection is an ordered list of shapes, each of which adds to, subtracts
	from or intersects the running mask, followed by grow, feather and invert.
	That is the same model an image editor uses, and it is what lets Shift-drag
	mean "add this too" and Ctrl-drag mean "except this".

	Every coordinate is normalised to 0..1 across the texture, so a selection
	made while looking at a 256 pixel preview still means the same thing when
	the 1024 pixel image is finally written.

	Two shapes need more than their own numbers to resolve:

	  wand      needs the source pixels, because it selects by colour
	  uv*       needs the model's mesh, because it selects by what the model
	            actually maps onto the texture

	Both are still deterministic - every client has the same texture and the
	same .mdl - and both are resolved at rasterisation time in cl_56_texops.lua.
	The model and sub-material slot they need live on the recipe that carries
	the selection, not on each shape.
-----------------------------------------------------------------------------]]

AdvMat     = AdvMat or {}
AdvMat.Sel = AdvMat.Sel or {}

local S = AdvMat.Sel

---------------------------------------------------------------------------
-- Shape catalogue
---------------------------------------------------------------------------
-- `pts` is a flat list of normalised x, y pairs rather than a list of tables:
-- it halves the JSON size on the wire and it is what the rasteriser wants.
S.SHAPES = {
	all      = { name = "Everything",        needs = nil    },
	rect     = { name = "Rectangle",         needs = nil    },
	ellipse  = { name = "Ellipse",           needs = nil    },
	poly     = { name = "Free shape",        needs = nil    },
	brush    = { name = "Painted",           needs = nil    },
	wand     = { name = "Similar colour",    needs = "pixels" },
	uvtri    = { name = "One model face",    needs = "mesh" },
	uvisland = { name = "Connected UV piece", needs = "mesh" },
	uvall    = { name = "Everything the model uses", needs = "mesh" },
}

S.MODES = {
	add = "Add",
	sub = "Subtract",
	int = "Keep only the overlap",
}

S.MAX_SHAPES = 24
S.MAX_POLY   = 128
S.MAX_BRUSH  = 512

---------------------------------------------------------------------------
-- Sanitising
---------------------------------------------------------------------------
-- NaN fails every comparison, so a plain clamp lets it straight through and it
-- ends up as an infinite loop bound in the rasteriser. AdvMat.ClampNum is the
-- one place that is handled.
local function Num( v, lo, hi, fallback )
	return AdvMat.ClampNum( v, lo, hi, fallback )
end

--- Flat coordinate list, clamped and thinned to the cap. Returns nil below
--- `least` points, because a polygon with two corners is not a shape.
---
--- Over the cap the list is sampled evenly rather than cut short. A lasso drawn
--- slowly produces hundreds of points, and keeping only the leading hundred and
--- a bit would close the outline somewhere in the middle of itself - a
--- completely different shape from the one that was drawn, with no warning.
local function Points( raw, least, most )
	if not istable( raw ) then return nil end

	local n = math.floor( #raw / 2 )
	if n < least then return nil end

	local out  = {}
	local step = ( n > most ) and ( n / most ) or 1
	local at   = 1

	while #out < most * 2 do
		local p = math.floor( at )
		if p > n then break end

		out[ #out + 1 ] = Num( raw[ p * 2 - 1 ], -1, 2, 0 )
		out[ #out + 1 ] = Num( raw[ p * 2     ], -1, 2, 0 )

		at = at + step
	end

	-- Where the outline ends decides where it closes, so the final point is
	-- kept even when the even sampling stepped past it.
	if step > 1 and #out >= 2 then
		out[ #out - 1 ] = Num( raw[ n * 2 - 1 ], -1, 2, 0 )
		out[ #out     ] = Num( raw[ n * 2     ], -1, 2, 0 )
	end

	if #out < least * 2 then return nil end
	return out
end

local function SanitizeShape( raw, first )
	if not istable( raw ) then return nil end

	local t = tostring( raw.t or "" )
	if not S.SHAPES[ t ] then return nil end

	local mode = tostring( raw.mode or "add" )
	if not S.MODES[ mode ] then mode = "add" end

	-- The first shape has nothing to combine with, so it always starts the
	-- mask rather than subtracting from an empty one.
	if first then mode = "add" end

	local out = { t = t, mode = mode }

	if t == "rect" or t == "ellipse" then
		out.x = Num( raw.x, -1, 2, 0 )
		out.y = Num( raw.y, -1, 2, 0 )
		out.w = Num( raw.w,  0, 3, 0 )
		out.h = Num( raw.h,  0, 3, 0 )

		-- A zero width drag is a click, not a region.
		if out.w <= 0.0005 or out.h <= 0.0005 then return nil end

	elseif t == "poly" then
		out.pts = Points( raw.pts, 3, S.MAX_POLY )
		if not out.pts then return nil end

	elseif t == "brush" then
		out.pts = Points( raw.pts, 1, S.MAX_BRUSH )
		if not out.pts then return nil end
		out.r = Num( raw.r, 0.001, 0.5, 0.03 )

		-- Hardness controls how much of the radius stays fully covered before
		-- fading towards the rim.  A missing value is the original one-pixel
		-- antialiased hard edge.  Keep that default absent from the clean recipe
		-- so old strokes, and strokes which explicitly choose 100%, retain their
		-- exact canonical form and generated-texture cache filename.
		local hardness = Num( raw.hardness, 0, 1, 1 )
		if hardness < 1 then out.hardness = hardness end

	elseif t == "wand" then
		out.x   = Num( raw.x, 0, 1, 0.5 )
		out.y   = Num( raw.y, 0, 1, 0.5 )
		out.tol = Num( raw.tol, 0, 1, 0.15 )
		out.contiguous = raw.contiguous ~= false

	elseif t == "uvtri" or t == "uvisland" then
		out.x = Num( raw.x, 0, 1, 0.5 )
		out.y = Num( raw.y, 0, 1, 0.5 )
	end

	return out
end

--- Coerce anything into a valid selection, or nil when nothing is selected.
function S.Sanitize( sel )
	if not istable( sel ) then return nil end

	local shapes = {}

	-- `or {}` only covers nil. A recipe off the network can carry a string or a
	-- number here, and ipairs raises on those rather than iterating nothing.
	for _, raw in ipairs( istable( sel.shapes ) and sel.shapes or {} ) do
		if #shapes >= S.MAX_SHAPES then break end

		local clean = SanitizeShape( raw, #shapes == 0 )
		if clean then shapes[ #shapes + 1 ] = clean end
	end

	if #shapes == 0 then return nil end

	local out = { shapes = shapes }

	local feather = Num( sel.feather, 0, 0.25, 0 )
	local grow    = Num( sel.grow,   -0.25, 0.25, 0 )

	if feather > 0.0005          then out.feather = feather end
	if math.abs( grow ) > 0.0005 then out.grow    = grow end
	if sel.invert                then out.invert  = true end

	-- A clip is a second, whole selection intersected with the finished mask
	-- AFTER this one's own grow, feather and invert have been applied.
	--
	-- That ordering is the entire reason it exists. A brush stroke inside a
	-- selection is "the stroke, limited to what is selected" - and folding the
	-- selection in as another shape instead would let the stroke's own invert
	-- act on it, so painting inside an inverted selection would paint
	-- everywhere EXCEPT where the brush went.
	--
	-- Only the four shaping fields are carried across, which bounds the nesting
	-- at one level: a clip cannot itself have a clip.
	if istable( sel.clip ) then
		local clip = S.Sanitize( {
			shapes  = sel.clip.shapes,
			feather = sel.clip.feather,
			grow    = sel.clip.grow,
			invert  = sel.clip.invert,
		} )

		if clip then out.clip = clip end
	end

	return out
end

---------------------------------------------------------------------------
-- Questions the UI asks
---------------------------------------------------------------------------
function S.IsEmpty( sel )
	return not ( istable( sel ) and istable( sel.shapes ) and #sel.shapes > 0 )
end

--- True when the selection is the whole texture and nothing else, which means
--- the caller can skip building a mask at all.
function S.CoversAll( sel )
	if S.IsEmpty( sel ) then return false end
	if sel.invert or sel.feather or sel.grow or sel.clip then return false end
	if #sel.shapes ~= 1 then return false end
	return sel.shapes[ 1 ].t == "all"
end

--- True when any shape has to look at the model's mesh to resolve.
function S.NeedsMesh( sel )
	if S.IsEmpty( sel ) then return false end

	for _, shape in ipairs( sel.shapes ) do
		local def = S.SHAPES[ shape.t ]
		if def and def.needs == "mesh" then return true end
	end

	return S.NeedsMesh( sel.clip )
end

---------------------------------------------------------------------------
-- Brush strokes
---------------------------------------------------------------------------

--- True when a selection is one painted brush stroke and nothing else, apart
--- from an optional clip.
---
--- That is the shape of every stroke drawn on the canvas, and it is worth
--- recognising: a stroke can only ever change the pixels its brush passed
--- over, so the image engine applies it to those alone instead of visiting the
--- whole texture, and the step limit has no reason to count it.
function S.IsBrushStroke( sel )
	if S.IsEmpty( sel ) or #sel.shapes ~= 1 then return false end
	if sel.invert or sel.grow or sel.feather then return false end

	local shape = sel.shapes[ 1 ]
	return shape.t == "brush" and ( shape.mode == nil or shape.mode == "add" )
		and istable( shape.pts ) and #shape.pts >= 2
end

--- How much work a brush stroke asks of every client that rebuilds it, in
--- whole textures: the area of each segment's bounding box on the sheet, which
--- is what the rasteriser visits. It is a budget worked out from the recipe
--- alone, not a timing, so the server and every client reach the same answer.
---
--- One segment can visit at most the whole sheet, so a stroke costs at most
--- one less than its point count.
function S.StrokeCost( shape )
	if not istable( shape ) or not istable( shape.pts ) then return 0 end

	local pts = shape.pts
	local n   = math.floor( #pts / 2 )
	local r   = tonumber( shape.r ) or 0.03

	if n < 1 then return 0 end

	-- One axis of a segment's box, clipped to the sheet.
	local function Span( a, b )
		local lo = math.max( math.min( a, b ) - r, 0 )
		local hi = math.min( math.max( a, b ) + r, 1 )
		return ( hi > lo ) and ( hi - lo ) or 0
	end

	if n == 1 then return Span( pts[ 1 ], pts[ 1 ] ) * Span( pts[ 2 ], pts[ 2 ] ) end

	local cost = 0
	for i = 1, n - 1 do
		cost = cost + Span( pts[ i * 2 - 1 ], pts[ i * 2 + 1 ] )
		            * Span( pts[ i * 2 ], pts[ i * 2 + 2 ] )
	end

	return cost
end

--- A stroke as it is worth keeping: only the points that move its outline by
--- more than `tolerance` pixels of a `w` x `h` image, each rounded to four
--- decimal places.
---
--- The canvas records the pointer every time it moves about a pixel, which is
--- what drawing under the cursor needs, but most of those points lie on the
--- line between their neighbours. Leaving them out moves the painted edge by
--- less than the tolerance and makes a typical stroke a third of the size -
--- and size is what decides how many strokes one save can carry to the
--- server. Rounding to four decimal places moves a point by at most a
--- fortieth of a pixel on the usual 512 working image (a fifth on the widest
--- oblong one), and prints as six characters where a raw pointer position
--- prints as eighteen.
---
--- The distance is measured in pixels rather than in fractions of the sheet,
--- because the brush is round in pixels: on an oblong sheet a fraction across
--- is not the same distance as the same fraction down.
function S.CompactStroke( pts, w, h, tolerance )
	if not istable( pts ) then return {} end

	local n = math.floor( #pts / 2 )
	if n < 1 then return {} end

	w = math.max( tonumber( w ) or 512, 1 )
	h = math.max( tonumber( h ) or w, 1 )

	local tol2 = ( tolerance or 0.35 ) ^ 2
	local keep = { [ 1 ] = true, [ n ] = true }

	-- Ramer-Douglas-Peucker with an explicit stack, because a slow spiral nests
	-- as deeply as it has points. Distance is to the segment rather than to
	-- the line through it, since a capsule ends at its points: a stroke that
	-- doubles back is not a straight line however close its ends are.
	local stack = { 1, n }

	while #stack > 0 do
		local last  = table.remove( stack )
		local first = table.remove( stack )

		local ax, ay = pts[ first * 2 - 1 ] * w, pts[ first * 2 ] * h
		local dx = pts[ last * 2 - 1 ] * w - ax
		local dy = pts[ last * 2 ] * h - ay
		local len2 = dx * dx + dy * dy

		local worst, at = tol2, nil

		for i = first + 1, last - 1 do
			local px, py = pts[ i * 2 - 1 ] * w, pts[ i * 2 ] * h
			local t = 0

			if len2 > 0 then
				t = ( ( px - ax ) * dx + ( py - ay ) * dy ) / len2
				if t < 0 then t = 0 elseif t > 1 then t = 1 end
			end

			local ex, ey = px - ( ax + dx * t ), py - ( ay + dy * t )
			local d = ex * ex + ey * ey

			if d > worst then worst, at = d, i end
		end

		if at then
			keep[ at ] = true
			stack[ #stack + 1 ] = first
			stack[ #stack + 1 ] = at
			stack[ #stack + 1 ] = at
			stack[ #stack + 1 ] = last
		end
	end

	local function Round( v )
		return math.floor( ( tonumber( v ) or 0 ) * 10000 + 0.5 ) / 10000
	end

	local out = {}

	for i = 1, n do
		if keep[ i ] then
			local x, y = Round( pts[ i * 2 - 1 ] ), Round( pts[ i * 2 ] )

			-- Rounding can land two kept neighbours on the same spot, and a
			-- zero-length segment is only a second copy of a dab already there.
			if #out < 2 or out[ #out - 1 ] ~= x or out[ #out ] ~= y then
				out[ #out + 1 ] = x
				out[ #out + 1 ] = y
			end
		end
	end

	return out
end

---------------------------------------------------------------------------
-- Display
---------------------------------------------------------------------------
local SHORT = {
	all      = { "selection.whole", "everything" },
	rect     = { "selection.rect", "a rectangle" },
	ellipse  = { "selection.ellipse", "an ellipse" },
	poly     = { "selection.poly", "a free shape" },
	brush    = { "selection.brush", "a painted area" },
	wand     = { "selection.wand", "a colour" },
	uvtri    = { "selection.face", "one model face" },
	uvisland = { "selection.island", "a connected piece of the model" },
	uvall    = { "selection.model", "everything the model uses" },
}

local function Display( key, variables, fallback )
	if AdvMat.L then return AdvMat.L( key, variables ) end
	return fallback
end

--- Plain English, for the line that sits under a "Region" button.
function S.Describe( sel )
	if S.IsEmpty( sel ) then return Display( "selection.whole", nil, "the whole texture" ) end

	local short = SHORT[ sel.shapes[ 1 ].t ]
	local first = short and Display( short[ 1 ], nil, short[ 2 ] )
		or Display( "selection.region", nil, "a region" )
	local extra = #sel.shapes - 1

	local text = first

	if extra > 0 then
		text = Display( "selection.more", { base = text, count = extra },
			text .. " and " .. extra .. " more step" .. ( extra == 1 and "" or "s" ) )
	end

	local tail = {}
	if sel.invert then
		tail[ #tail + 1 ] = Display( "selection.inverted", nil, "inverted" )
	end
	if sel.grow    then
		local value = AdvMat.NumToString( math.Round( math.abs( sel.grow ) * 100, 1 ) )
		tail[ #tail + 1 ] = Display( sel.grow > 0 and "selection.grown" or "selection.shrunk",
			{ value = value }, ( sel.grow > 0 and "grown " or "shrunk " ) .. value .. "%" )
	end
	if sel.feather then
		local value = AdvMat.NumToString( math.Round( sel.feather * 100, 1 ) )
		tail[ #tail + 1 ] = Display( "selection.soft", { value = value }, "softened " .. value .. "%" )
	end

	if #tail > 0 then text = text .. " (" .. table.concat( tail, ", " ) .. ")" end

	if sel.clip then
		local clip = S.Describe( sel.clip )
		text = Display( "selection.limited", { base = text, clip = clip },
			text .. ", limited to " .. clip )
	end

	return text
end

--- How many shapes, for a compact badge.
function S.Count( sel )
	if S.IsEmpty( sel ) then return 0 end
	return #sel.shapes
end

---------------------------------------------------------------------------
-- Editing helpers, shared by the canvas and the region picker
---------------------------------------------------------------------------

--- Append a shape, returning a new selection rather than mutating the old one
--- so that undo can keep the previous value.
function S.Push( sel, shape )
	local out = { shapes = {} }

	if istable( sel ) then
		for _, s in ipairs( sel.shapes or {} ) do out.shapes[ #out.shapes + 1 ] = s end
		out.feather = sel.feather
		out.grow    = sel.grow
		out.invert  = sel.invert
	end

	out.shapes[ #out.shapes + 1 ] = shape

	-- Replacing means starting over, which is what a plain drag with no
	-- modifier held does.
	if shape.mode == "replace" then
		shape.mode  = "add"
		out.shapes  = { shape }
	end

	return S.Sanitize( out )
end

--- A selection covering the whole texture, used by "Select all".
function S.All()
	return { shapes = { { t = "all", mode = "add" } } }
end
