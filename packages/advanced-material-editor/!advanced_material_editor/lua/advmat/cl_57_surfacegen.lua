--[[---------------------------------------------------------------------------
	Advanced Material Editor - surface map generators

	Builds the images the recipes in sh_44_gen_surface.lua describe. Both of
	them start from the same three fields derived from the colour texture:

	  L  brightness, Rec. 601 luma, 0..1
	  S  saturation, 0..1. Metal is bright AND colourless; a red shirt is
	     bright and very much not, and that is the difference plain luminance
	     cannot see.
	  D  detail energy: how far the pixel is from a blurred copy of itself.
	     High D means fine visible structure means a rough surface means a
	     broader, weaker highlight.

	The last stage of the exponent map matters as much as the first: the result
	is blurred, stepped into a handful of levels, then blurred again. A real
	exponent map is a small number of broad flat zones with soft borders. If
	the generated map still reads as a picture of the character, every logo and
	seam printed on the diffuse will show up as a change in how sharp the
	specular highlight is, which is the single most common way these come out
	looking wrong.
-----------------------------------------------------------------------------]]

AdvMat = AdvMat or {}

local GEN = AdvMat.Gen
local BUF = AdvMat.Buf

local floor, min, max, abs = math.floor, math.min, math.max, math.abs

---------------------------------------------------------------------------
-- Derived fields
---------------------------------------------------------------------------
local fieldCache = {}

--- L, S and D for a source texture, cached because both generators want them
--- and a user comparing settings will rebuild many times over.
local function Fields( src )
	-- Keyed on the source's serial number rather than its table address. An
	-- address is reused once the table behind it is dropped, and the source
	-- cache drops everything at once when it fills up, so an address key would
	-- occasionally hand one texture's fields back for another.
	local key = src.id or ( "anon:" .. tostring( src ) )
	local hit = fieldCache[ key ]
	if hit then return hit end

	local n = src.w * src.h
	local r, g, b = src.r, src.g, src.b

	local L, S = {}, {}

	for i = 1, n do
		-- A queued build may pause here for the next frame (GEN.Yield).
		if i % 16384 == 0 then GEN.Yield() end

		local pr, pg, pb = r[ i ], g[ i ], b[ i ]

		L[ i ] = ( pr * 0.299 + pg * 0.587 + pb * 0.114 ) / 255

		local hi = max( pr, pg, pb )
		local lo = min( pr, pg, pb )
		S[ i ] = ( hi > 0 ) and ( ( hi - lo ) / hi ) or 0
	end

	-- Four pixels is the radius the detail term is defined against; it is
	-- large enough to ignore texture grain and small enough to still catch
	-- stitching, panel lines and printed pattern.
	local soft = BUF.BlurField( L, src.w, src.h, 4 )
	local D    = {}

	for i = 1, n do
		-- Scaled so ordinary printed detail lands near the top of the range
		-- rather than in the bottom tenth of it.
		local d = abs( L[ i ] - soft[ i ] ) * 4
		D[ i ] = ( d > 1 ) and 1 or d
	end

	local out = { L = L, S = S, D = D, w = src.w, h = src.h }

	-- Two entries is enough for "the thing being edited" plus "the thing it
	-- is being compared against", and each is three arrays of a million.
	local count = 0
	for _ in pairs( fieldCache ) do count = count + 1 end
	if count >= 2 then fieldCache = {} end

	fieldCache[ key ] = out
	return out
end

--- Drop the cached fields whenever the source pixels behind them do.
hook.Add( "AdvMatSourcesFlushed", "AdvMat.SurfaceFields", function()
	fieldCache = {}
end )

---------------------------------------------------------------------------
-- Reflection mask
---------------------------------------------------------------------------

--- The 0..1 mask an envmapmask recipe describes. Shared with the normal map
--- generator, which can carry the same mask in its alpha channel.
function GEN.ReflectMask( src, opts )
	local f = Fields( src )
	local n = src.w * src.h

	local L, S = f.L, f.S
	local base = {}

	local source = opts.source or "metal"

	if source == "luminance" then
		for i = 1, n do base[ i ] = L[ i ] end

	elseif source == "saturation" then
		for i = 1, n do base[ i ] = 1 - S[ i ] end

	elseif source == "flat" then
		for i = 1, n do base[ i ] = 1 end

	else
		-- Brightness, weighted by how colourless the pixel is. A little of the
		-- plain brightness is kept so that a saturated but obviously glossy
		-- area does not fall all the way to matte.
		for i = 1, n do
			base[ i ] = L[ i ] * ( 0.35 + 0.65 * ( 1 - S[ i ] ) )
		end
	end

	-- Blur BEFORE the curve. Curving first turns per pixel noise into per
	-- pixel reflectivity, and no amount of blurring afterwards fully undoes it.
	local blur = opts.blur or 0
	if blur > 0 then base = BUF.BlurField( base, src.w, src.h, blur ) end

	local contrast = opts.contrast or 1
	local gamma    = opts.gamma or 1
	local lo       = opts.lo or 0
	local hi       = opts.hi or 1
	local invert   = opts.invert

	local out = {}

	for i = 1, n do
		local v = base[ i ]

		if contrast ~= 1 then v = ( v - 0.5 ) * contrast + 0.5 end
		if v < 0 then v = 0 elseif v > 1 then v = 1 end

		if gamma ~= 1 then v = v ^ gamma end
		if invert then v = 1 - v end

		out[ i ] = lo + ( hi - lo ) * v
	end

	return out
end

GEN.Builders.envmapmask = function( recipe )
	local w, h = GEN.Dims( recipe )

	local src = GEN.ReadSource( recipe.src, w, h )
	if not src then return nil, "could not read " .. recipe.src end

	local mask = GEN.ReflectMask( src, recipe )
	GEN.Yield()

	local px, o = {}, 1

	for i = 1, src.w * src.h do
		-- The shader multiplies the reflection by all three channels, so a
		-- grey mask is a plain strength and a coloured one would tint the
		-- reflection. Grey is what a mask is for.
		local v = floor( math.Clamp( mask[ i ], 0, 1 ) * 255 + 0.5 )
		px[ o ], px[ o + 1 ], px[ o + 2 ] = v, v, v
		o = o + 3
	end

	return px, src.w, src.h, 3
end

-- Black is "reflects nothing", which is the right thing to leave outside a
-- region that was told to generate only inside one.
GEN.Neutral.envmapmask = function() return 0, 0, 0, 255 end

---------------------------------------------------------------------------
-- Phong exponent
---------------------------------------------------------------------------

--- Step a 0..1 field down to `levels` flat values. Real exponent maps are a
--- handful of material zones, not a continuous gradient, and this is what
--- turns a photograph into zones.
local function Posterise( field, n, levels )
	if levels < 2 then return end

	local steps = levels - 1

	for i = 1, n do
		field[ i ] = floor( field[ i ] * steps + 0.5 ) / steps
	end
end

GEN.Builders.phongexp = function( recipe )
	local w, h = GEN.Dims( recipe )

	local src = GEN.ReadSource( recipe.src, w, h )
	if not src then return nil, "could not read " .. recipe.src end

	local w, h = src.w, src.h
	local n    = w * h

	local f = Fields( src )
	local L, S, D = f.L, f.S, f.D

	local base   = ( recipe.base  or 0 ) / 255
	local range  = ( recipe.range or 0 ) / 255
	local detail = recipe.detail or 1

	---------------------------------------------------------------- red
	local gloss = {}

	for i = 1, n do
		-- Bright and colourless reads as a hard, polished surface; visible
		-- fine detail reads as a rough one and pulls the exponent back down.
		local v = base + range * ( 0.5 * ( 1 - S[ i ] ) * L[ i ] ) - detail * 1.2 * D[ i ]

		if v < 0 then v = 0 elseif v > 1 then v = 1 end
		gloss[ i ] = v ^ 0.8
	end

	if ( recipe.smooth or 0 ) > 0 then
		gloss = BUF.BlurField( gloss, w, h, recipe.smooth )
	end

	Posterise( gloss, n, recipe.levels or 0 )
	GEN.Yield()

	-- One more pixel of blur, to soften the hard borders posterising just
	-- created without putting the picture back.
	gloss = BUF.BlurField( gloss, w, h, 1 )

	if recipe.invert then
		for i = 1, n do gloss[ i ] = 1 - gloss[ i ] end
	end

	-------------------------------------------------------------- green
	-- How far the highlight takes on the surface's own colour. Only read when
	-- $phongalbedotint 1 is also set, and only correct on genuinely metallic
	-- areas: tinting a dielectric like skin or cloth just dims its highlight.
	local tintmode = recipe.tintmode or "metal"
	local tint     = ( recipe.tint or 0 ) / 255

	local green = {}

	if tintmode == "none" then
		for i = 1, n do green[ i ] = 0 end

	elseif tintmode == "constant" then
		for i = 1, n do green[ i ] = tint end

	elseif tintmode == "saturation" then
		for i = 1, n do green[ i ] = 0.25 * S[ i ] end

	else
		for i = 1, n do
			local metal = ( L[ i ] - 0.35 ) * 1.6 * ( 1 - S[ i ] )
			green[ i ] = ( metal < 0 ) and 0 or ( metal > 1 ) and 1 or metal
		end

		green = BUF.BlurField( green, w, h, 2 )
	end

	GEN.Yield()

	-------------------------------------------------------------- alpha
	local rim = ( recipe.rim or 255 ) / 255

	---------------------------------------------------------------- out
	local px, o = {}, 1

	for i = 1, n do
		local a = rim

		if recipe.rimdetail then
			-- Rim light on a rough surface reads as a fuzzy halo, so it is
			-- pulled back wherever the surface has fine detail.
			a = rim * math.Clamp( 1 - 1.5 * D[ i ], 0, 1 )
		end

		px[ o     ] = floor( math.Clamp( gloss[ i ], 0, 1 ) * 255 + 0.5 )
		px[ o + 1 ] = floor( math.Clamp( green[ i ], 0, 1 ) * 255 + 0.5 )
		px[ o + 2 ] = 0            -- never sampled by any shipping shader
		px[ o + 3 ] = floor( math.Clamp( a, 0, 1 ) * 255 + 0.5 )

		o = o + 4
	end

	return px, w, h, 4
end

-- Exponent 1 with no tint and an unmasked rim: the flattest, least opinionated
-- thing that can sit outside a region.
GEN.Neutral.phongexp = function() return 0, 0, 0, 255 end

---------------------------------------------------------------------------
-- A normal map that carries a mask in its alpha channel
---------------------------------------------------------------------------
-- On any material with $bumpmap or $phong the shader will not read a separate
-- $envmapmask at all - it looks in the alpha channel of the normal map. So the
-- normal map generator has to be able to put one there, or the reflection mask
-- generator is useless on exactly the models people want to use it on.
local PlainNormal = GEN.Builders.normal

GEN.Builders.normal = function( recipe )
	local px, w, h, channels = PlainNormal( recipe )
	if not px then return px, w, h, channels end

	if not recipe.alphamask then return px, w, h, channels end

	local src = GEN.ReadSource( recipe.src, w, h )
	if not src then return px, w, h, channels end

	local mask = GEN.ReflectMask( src, recipe.alphamask )

	-- Re-interleave from three channels to four. Done backwards so it can be
	-- read and written in the same array without a second copy of a megapixel.
	local n = w * h

	for i = n, 1, -1 do
		local from = ( i - 1 ) * 3
		local to   = ( i - 1 ) * 4

		px[ to + 4 ] = floor( math.Clamp( mask[ i ], 0, 1 ) * 255 + 0.5 )
		px[ to + 3 ] = px[ from + 3 ]
		px[ to + 2 ] = px[ from + 2 ]
		px[ to + 1 ] = px[ from + 1 ]
	end

	return px, w, h, 4
end
