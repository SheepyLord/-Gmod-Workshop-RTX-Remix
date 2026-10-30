--[[---------------------------------------------------------------------------
	Advanced Material Editor - the normal map recipe

	A diffuse texture has no height information in it, so every normal map made
	this way is an educated guess: brightness is treated as height and the rate
	at which it changes becomes the slope. That is the same assumption every
	"normal map from photo" tool makes, SmartNormal included.

	The settings here are exactly what that guess needs - which channel to read
	the height from, how much to smooth it first, which gradient operator to
	run over it, and how far to lean the result.
-----------------------------------------------------------------------------]]

AdvMat     = AdvMat or {}
AdvMat.Gen = AdvMat.Gen or {}

local GEN = AdvMat.Gen

local function Display( key, variables, fallback )
	if AdvMat.L then return AdvMat.L( key, variables ) end
	return fallback
end

---------------------------------------------------------------------------
-- Settings
---------------------------------------------------------------------------

--- Where the height field is read from. A diffuse texture has no real height
--- data, so this is always an approximation; luminance is the usual choice.
GEN.CHANNELS = {
	{ id = "luminance", name = "Luminance"        },
	{ id = "average",   name = "Average RGB"      },
	{ id = "red",       name = "Red channel"      },
	{ id = "green",     name = "Green channel"    },
	{ id = "blue",      name = "Blue channel"     },
	{ id = "alpha",     name = "Alpha channel"    },
}

--- Gradient operators, smallest and sharpest first.
GEN.FILTERS = {
	{ id = "sobel3",   name = "Sobel 3x3",   size = 3 },
	{ id = "scharr3",  name = "Scharr 3x3",  size = 3 },
	{ id = "prewitt3", name = "Prewitt 3x3", size = 3 },
	{ id = "sobel5",   name = "Sobel 5x5",   size = 5 },
}

GEN.DEFAULTS = {
	src      = "",
	size     = 512,
	channel  = "luminance",
	filter   = "sobel3",
	strength = 4,
	blur     = 0,
	detail   = 0,
	invertx  = false,
	inverty  = false,
	inverth  = false,
	wrap     = true,
}

-- Optional procedural height variation. This is deliberately separate from
-- DEFAULTS: when it is off the field is absent from the recipe, preserving the
-- exact signature (and cached filename) of every normal map made before this
-- feature existed.
GEN.UNEVEN_DEFAULTS = {
	amount = 0.15,
	scale  = 12,
	seed   = 1,
}

---------------------------------------------------------------------------
-- Registration
---------------------------------------------------------------------------
GEN.Register( {
	id     = "normal",
	name   = "Normal map",
	dir    = "advmat/normals",
	prefix = "nrm_",
	region = true,

	-- Field order is frozen: it is what the output filename hashes, so a
	-- normal map generated before regions existed keeps the same name and is
	-- not regenerated on upgrade.
	order = {
		"src", "size", "channel", "filter", "strength",
		"blur", "detail", "invertx", "inverty", "inverth", "wrap",
	},

	-- A normal map can carry a mask in its alpha channel, and on a model that
	-- has $phong or $bumpmap that is the only place the shader will look for
	-- one. See AdvMat.ReflectionRoute in sh_44_gen_surface.lua.
	--
	-- `kernelrev` is not a setting. The 5x5 operator's divisor was half what it
	-- should have been, so it leaned twice as far as the other three at the same
	-- strength. Correcting that changes the pixels a 5x5 recipe describes
	-- WITHOUT changing any of its settings - which would leave anyone holding an
	-- already generated file with an image that no longer matches its own
	-- recipe, and two players seeing different bumps from the same rule. Marking
	-- the revision in the signature regenerates exactly those recipes and
	-- nothing else.
	optional = { "kernelrev", "alphamask", "uneven" },

	defaults = GEN.DEFAULTS,

	Sanitize = function( recipe, out )
		if not out.src then return nil end

		out.channel  = tostring( recipe.channel or GEN.DEFAULTS.channel )
		out.filter   = tostring( recipe.filter  or GEN.DEFAULTS.filter  )
		out.strength = AdvMat.ClampNum( recipe.strength, 0.05, 30, GEN.DEFAULTS.strength )
		out.blur     = math.floor( AdvMat.ClampNum( recipe.blur, 0, 8, 0 ) )
		out.detail   = AdvMat.ClampNum( recipe.detail, 0, 2, 0 )
		out.invertx  = recipe.invertx and true or false
		out.inverty  = recipe.inverty and true or false
		out.inverth  = recipe.inverth and true or false
		out.wrap     = recipe.wrap ~= false

		if not GEN.InList( GEN.CHANNELS, out.channel ) then out.channel = GEN.DEFAULTS.channel end
		if not GEN.InList( GEN.FILTERS,  out.filter  ) then out.filter  = GEN.DEFAULTS.filter  end

		-- Only the 5x5 operator's maths changed, so only its recipes carry the
		-- marker and only they are rebuilt. Every other normal map on disk keeps
		-- the filename it already had.
		if out.filter == "sobel5" then out.kernelrev = 2 end

		-- A seeded, coherent value-noise layer can be added to the height field
		-- before its gradient is calculated. Keeping the controls in one optional
		-- table means a disabled layer contributes nothing to the recipe hash.
		if istable( recipe.uneven ) then
			local amount = AdvMat.ClampNum( recipe.uneven.amount, 0, 1, 0 )
			if amount > 0 then
				out.uneven = {
					amount = amount,
					scale  = math.floor( AdvMat.ClampNum( recipe.uneven.scale, 2, 64,
						GEN.UNEVEN_DEFAULTS[ "scale" ] ) ),
					seed   = math.floor( AdvMat.ClampNum( recipe.uneven.seed, 0, 65535,
						GEN.UNEVEN_DEFAULTS[ "seed" ] ) ),
					rev    = 1,
				}
			end
		end

		-- The alpha channel rides along as a reflection / highlight mask,
		-- built by the same code as a standalone reflection mask but sharing
		-- this recipe's source and size rather than carrying its own.
		if istable( recipe.alphamask ) then
			local mask = GEN.Sanitize( {
				kind     = "envmapmask",
				src      = out.src,
				size     = out.size,
				height   = out.height,
				source   = recipe.alphamask.source,
				blur     = recipe.alphamask.blur,
				contrast = recipe.alphamask.contrast,
				gamma    = recipe.alphamask.gamma,
				lo       = recipe.alphamask.lo,
				hi       = recipe.alphamask.hi,
				invert   = recipe.alphamask.invert,
			} )

			if mask then
				-- Stored without src or size so they can never drift apart from
				-- the recipe that owns them. The shape goes with the size: the
				-- mask is built from the same pixels, at the same resolution.
				mask.src, mask.size, mask.height, mask.kind = nil, nil, nil, nil
				out.alphamask = mask
			end
		end

		return out
	end,

	Describe = function( recipe )
		local bits = {
			GEN.NameOf( GEN.FILTERS, recipe.filter ),
			Display( "recipe.strength",
				{ value = AdvMat.NumToString( math.Round( recipe.strength or 0, 2 ) ) },
				"strength " .. AdvMat.NumToString( math.Round( recipe.strength or 0, 2 ) ) ),
			( recipe.size or 0 ) .. "px",
			string.lower( GEN.NameOf( GEN.CHANNELS, recipe.channel ) ),
		}

		if ( recipe.blur or 0 ) > 0 then
			bits[ #bits + 1 ] = Display( "recipe.blur", { value = recipe.blur }, "blur " .. recipe.blur )
		end
		if ( recipe.detail or 0 ) > 0 then
			local value = AdvMat.NumToString( math.Round( recipe.detail, 2 ) )
			bits[ #bits + 1 ] = Display( "recipe.detail", { value = value }, "detail " .. value )
		end
		if recipe.uneven then
			bits[ #bits + 1 ] = Display( "recipe.uneven", {
				amount  = math.Round( ( recipe.uneven.amount or 0 ) * 100 ),
				density = recipe.uneven.scale or GEN.UNEVEN_DEFAULTS[ "scale" ],
				seed    = recipe.uneven.seed or GEN.UNEVEN_DEFAULTS[ "seed" ],
			}, "uneven " .. math.Round( ( recipe.uneven.amount or 0 ) * 100 )
				.. "% / density " .. ( recipe.uneven.scale or GEN.UNEVEN_DEFAULTS[ "scale" ] )
				.. " / seed " .. ( recipe.uneven.seed or GEN.UNEVEN_DEFAULTS[ "seed" ] ) )
		end

		if recipe.alphamask then
			bits[ #bits + 1 ] = Display( "recipe.alpha_mask", nil, "reflection mask in alpha" )
		end

		local LT = AdvMat.LText or function( text ) return text end
		if recipe.invertx then bits[ #bits + 1 ] = LT( "Invert X" ) end
		if recipe.inverty then bits[ #bits + 1 ] = LT( "Invert Y" ) end
		if recipe.inverth then bits[ #bits + 1 ] = LT( "Invert height" ) end
		if not recipe.wrap then
			bits[ #bits + 1 ] = Display( "recipe.clamped", nil, "clamped" )
		end

		return table.concat( bits, " / " )
	end,
} )
