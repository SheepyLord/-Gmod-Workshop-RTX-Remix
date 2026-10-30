--[[---------------------------------------------------------------------------
	Advanced Material Editor - surface map recipes

	Two more generators that read a colour texture and guess at something the
	shader wants but the artist never authored.

	  phongexp    a $phongexponenttexture: how tight the specular highlight is
	              (red), and how much of the surface's own colour tints that
	              highlight (green).

	  envmapmask  a reflection mask: how strongly each part of the surface
	              picks up the cubemap.

	Both guesses follow the same two rules, which are what separates a usable
	map from a luminance dump:

	  Bright and colourless is the signature of bare metal, so brightness is
	  weighted by how UNsaturated the pixel is. Plain luminance makes a red
	  shirt as shiny as a chrome buckle.

	  Fine detail means a rough surface. Local high-frequency energy therefore
	  lowers glossiness, and the result is smoothed and stepped into broad
	  zones afterwards. A real Valve exponent map is flat regions with soft
	  borders; if you can still recognise the character in it, it is wrong, and
	  every printed logo and stitch line will show up in the specular.

	Channel meanings for $phongexponenttexture, from the shipped shader
	(skin_ps20b.fxc) rather than from folklore:

	  red    exponent, mapped by the shader as 1 + 149 * (red/255)
	  green  how far the highlight is tinted towards the base colour, and only
	         when $phongalbedotint 1 is also set
	  blue   never sampled by any shipping shader. Write zero.
	  alpha  rim light mask, and only when $rimlight 1 and $rimmask 1
-----------------------------------------------------------------------------]]

AdvMat     = AdvMat or {}
AdvMat.Gen = AdvMat.Gen or {}

local GEN = AdvMat.Gen

local function Display( key, variables, fallback )
	if AdvMat.L then return AdvMat.L( key, variables ) end
	return fallback
end

---------------------------------------------------------------------------
-- Shared settings
---------------------------------------------------------------------------
GEN.SURFACE_SOURCES = {
	{ id = "metal",      name = "Bright and colourless first (recommended)" },
	{ id = "luminance",  name = "Brightness only" },
	{ id = "saturation", name = "Colourless areas only" },
	{ id = "flat",       name = "Ignore the texture, use one level" },
}

---------------------------------------------------------------------------
-- Phong exponent
---------------------------------------------------------------------------
-- The presets come from what Valve's own materials use. They are the fastest
-- way for someone who does not know what an exponent is to get a result that
-- looks like the material they are pointing at.
GEN.PHONG_PRESETS = {
	{ id = "skin",    name = "Skin",             base = 12, range = 40,  tint = "metal",      levels = 5, exponent = 5,   boost = 3 },
	{ id = "cloth",   name = "Cloth or fabric",  base = 5,  range = 25,  tint = "none",       levels = 4, exponent = 3,   boost = 0.8 },
	{ id = "leather", name = "Leather or vinyl", base = 30, range = 60,  tint = "none",       levels = 5, exponent = 20,  boost = 3 },
	{ id = "plastic", name = "Hard plastic",     base = 55, range = 90,  tint = "none",       levels = 5, exponent = 45,  boost = 4 },
	{ id = "metal",   name = "Metal",            base = 110, range = 130, tint = "metal",     levels = 6, exponent = 100, boost = 8 },
	{ id = "hair",    name = "Hair",             base = 15, range = 45,  tint = "metal",      levels = 4, exponent = 15,  boost = 2 },
	{ id = "custom",  name = "Custom" },
}

GEN.PHONG_TINTMODES = {
	{ id = "metal",      name = "Only where the surface looks metallic" },
	{ id = "saturation", name = "A hint of the surface's own colour" },
	{ id = "constant",   name = "The same everywhere" },
	{ id = "none",       name = "Never tint the highlight" },
}

GEN.PHONG_DEFAULTS = {
	src     = "",
	size    = 512,
	preset  = "skin",
	base    = 12,
	range   = 40,
	detail  = 1,
	smooth  = 3,
	levels  = 5,
	tintmode = "metal",
	tint    = 0,
	rim     = 255,
	rimdetail = false,
	invert  = false,
}

function GEN.PhongPreset( id )
	for _, p in ipairs( GEN.PHONG_PRESETS ) do
		if p.id == id then return p end
	end
	return nil
end

GEN.Register( {
	id     = "phongexp",
	name   = "Phong exponent map",
	dir    = "advmat/surface",
	prefix = "phn_",
	region = true,

	order = {
		"src", "size", "preset", "base", "range", "detail",
		"smooth", "levels", "tintmode", "tint", "rim", "rimdetail", "invert",
	},

	defaults = GEN.PHONG_DEFAULTS,

	Sanitize = function( recipe, out )
		if not out.src then return nil end

		local D = GEN.PHONG_DEFAULTS

		out.preset = tostring( recipe.preset or D.preset )
		if not GEN.PhongPreset( out.preset ) then out.preset = "custom" end

		out.base   = math.floor( AdvMat.ClampNum( recipe.base, 0, 255, D.base ) )
		out.range  = math.floor( AdvMat.ClampNum( recipe.range, -255, 255, D.range ) )
		out.detail = AdvMat.ClampNum( recipe.detail, 0, 3, D.detail )
		out.smooth = math.floor( AdvMat.ClampNum( recipe.smooth, 0, 8, D.smooth ) )

		-- Zero means "do not step the result at all", which is the only way to
		-- keep a smooth gradient if that is genuinely what is wanted.
		out.levels = math.floor( AdvMat.ClampNum( recipe.levels, 0, 16, D.levels ) )

		out.tintmode = tostring( recipe.tintmode or D.tintmode )
		if not GEN.InList( GEN.PHONG_TINTMODES, out.tintmode ) then out.tintmode = D.tintmode end

		out.tint = math.floor( AdvMat.ClampNum( recipe.tint, 0, 255, D.tint ) )
		out.rim  = math.floor( AdvMat.ClampNum( recipe.rim, 0, 255, D.rim ) )

		out.rimdetail = recipe.rimdetail and true or false
		out.invert    = recipe.invert    and true or false

		return out
	end,

	Describe = function( recipe )
		local preset = GEN.PhongPreset( recipe.preset )

		local bits = {
			AdvMat.LText and AdvMat.LText( preset and preset.name or "Custom" )
				or ( preset and preset.name or "Custom" ),
			Display( "recipe.exponent", {
				min = math.Round( 1 + 149 * ( recipe.base or 0 ) / 255 ),
				max = math.Round( 1 + 149 * math.Clamp(
					( ( recipe.base or 0 ) + ( recipe.range or 0 ) ) / 255, 0, 1 ) ),
			}, "exponent " .. math.Round( 1 + 149 * ( recipe.base or 0 ) / 255 ) ..
				" to " .. math.Round( 1 + 149 * math.Clamp(
					( ( recipe.base or 0 ) + ( recipe.range or 0 ) ) / 255, 0, 1 ) ) ),
			( recipe.size or 0 ) .. "px",
		}

		if ( recipe.levels or 0 ) > 0 then
			bits[ #bits + 1 ] = Display( "recipe.zones", { count = recipe.levels },
				recipe.levels .. " zones" )
		else
			bits[ #bits + 1 ] = Display( "recipe.smooth", nil, "smooth" )
		end

		if recipe.tintmode ~= "none" then
			bits[ #bits + 1 ] = Display( "recipe.tint", nil, "tinted highlight" )
		end

		if recipe.invert then
			bits[ #bits + 1 ] = Display( "selection.inverted", nil, "inverted" )
		end

		return table.concat( bits, " / " )
	end,
} )

---------------------------------------------------------------------------
-- Reflection mask
---------------------------------------------------------------------------
GEN.ENVMASK_DEFAULTS = {
	src      = "",
	size     = 512,
	source   = "metal",
	blur     = 2,
	contrast = 1.4,
	gamma    = 1.2,
	lo       = 0,
	hi       = 0.65,
	invert   = false,
}

GEN.Register( {
	id     = "envmapmask",
	name   = "Reflection mask",
	dir    = "advmat/surface",
	prefix = "env_",
	region = true,

	order = { "src", "size", "source", "blur", "contrast", "gamma", "lo", "hi", "invert" },

	defaults = GEN.ENVMASK_DEFAULTS,

	Sanitize = function( recipe, out )
		if not out.src then return nil end

		local D = GEN.ENVMASK_DEFAULTS

		out.source = tostring( recipe.source or D.source )
		if not GEN.InList( GEN.SURFACE_SOURCES, out.source ) then out.source = D.source end

		out.blur     = math.floor( AdvMat.ClampNum( recipe.blur, 0, 8, D.blur ) )
		out.contrast = AdvMat.ClampNum( recipe.contrast, 0, 4, D.contrast )
		out.gamma    = AdvMat.ClampNum( recipe.gamma, 0.2, 4, D.gamma )
		out.lo       = AdvMat.ClampNum( recipe.lo, 0, 1, D.lo )
		out.hi       = AdvMat.ClampNum( recipe.hi, 0, 1, D.hi )
		out.invert   = recipe.invert and true or false

		-- A ceiling below the floor would silently produce an inverted mask,
		-- which is what the Invert switch is for.
		if out.hi < out.lo then out.lo, out.hi = out.hi, out.lo end

		return out
	end,

	Describe = function( recipe )
		local bits = {
			string.lower( GEN.NameOf( GEN.SURFACE_SOURCES, recipe.source ) ),
			math.Round( ( recipe.lo or 0 ) * 100 ) .. "-" .. math.Round( ( recipe.hi or 0 ) * 100 ) .. "%",
			( recipe.size or 0 ) .. "px",
		}

		if ( recipe.blur or 0 ) > 0 then
			bits[ #bits + 1 ] = Display( "recipe.smoothed", { value = recipe.blur },
				"smoothed " .. recipe.blur )
		end
		if recipe.invert then
			bits[ #bits + 1 ] = Display( "selection.inverted", nil, "inverted" )
		end

		return table.concat( bits, " / " )
	end,
} )

---------------------------------------------------------------------------
-- Where a reflection mask actually has to live
---------------------------------------------------------------------------
-- $envmapmask is only read by the plain VertexLitGeneric path. The moment a
-- material has a $bumpmap it is ignored, and the shader deletes $envmap along
-- with it, so adding a mask makes reflections disappear rather than shaping
-- them. With $phong 1 there is no mask sampler in the shader at all.
--
-- Since nearly every playermodel has both, a generator that only ever wrote
-- $envmapmask would produce a texture that does nothing on the models people
-- actually use. This works out where the mask has to go instead, and the
-- editor uses it to tell the user in plain words.
--
-- Precedence is from the shipped shader:
--     $normalmapalphaenvmapmask  >  $envmapmask  >  $basealphaenvmapmask
-- and the first of those deletes the other two outright when it is set.

AdvMat.REFLECT_ROUTE = {
	ENVMAPMASK = 1,   -- a separate $envmapmask texture works
	BUMP_ALPHA = 2,   -- it has to live in the alpha channel of $bumpmap
	BASE_ALPHA = 3,   -- it has to live in the alpha channel of $basetexture
}

--- Work out where a reflection mask has to go for a material, given the key
--- values it currently has. Returns the route plus a sentence explaining it.
function AdvMat.ReflectionRoute( kv )
	kv = kv or {}

	local hasBump  = ( kv[ "$bumpmap" ] and kv[ "$bumpmap" ] ~= "" ) and true or false
	local hasPhong = tonumber( kv[ "$phong" ] or 0 ) == 1
	local baseMask = tonumber( kv[ "$basemapalphaphongmask" ] or 0 ) == 1

	if hasPhong then
		if baseMask then
			return AdvMat.REFLECT_ROUTE.BASE_ALPHA,
				Display( "surface.route_base_phong", nil,
					"This material has $phong 1 and $basemapalphaphongmask 1, so the shader " ..
					"reads its reflection and highlight mask from the alpha channel of " ..
					"$basetexture. A separate $envmapmask texture is not read at all." )
		end

		if hasBump then
			return AdvMat.REFLECT_ROUTE.BUMP_ALPHA,
				Display( "surface.route_bump_phong", nil,
					"This material has $phong 1, so the shader reads its reflection and " ..
					"highlight mask from the alpha channel of $bumpmap. A separate " ..
					"$envmapmask texture is not read at all." )
		end

		return AdvMat.REFLECT_ROUTE.BASE_ALPHA,
			Display( "surface.route_base_no_bump", nil,
				"This material has $phong 1 with no $bumpmap, so the mask comes from the " ..
				"alpha channel of $basetexture." )
	end

	if hasBump then
		return AdvMat.REFLECT_ROUTE.BUMP_ALPHA,
			Display( "surface.route_bump", nil,
				"This material has a $bumpmap. $envmapmask is ignored once a bump map is " ..
				"present, and setting it would switch $envmap off as well, so the mask has " ..
				"to go in the alpha channel of $bumpmap with $normalmapalphaenvmapmask 1." )
	end

	return AdvMat.REFLECT_ROUTE.ENVMAPMASK,
		Display( "surface.route_separate", nil,
			"This material has no $bumpmap and no $phong, so a separate $envmapmask " ..
			"texture is read normally." )
end
