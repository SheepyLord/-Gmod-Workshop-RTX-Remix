--[[---------------------------------------------------------------------------
	Advanced Material Editor - the hand edited texture recipe

	An edited texture is a source image plus an ordered list of steps, each of
	which does one thing to one region. Nothing is ever flattened: the steps are
	kept, so any of them can be switched off, reordered or deleted afterwards,
	and the image is rebuilt from the original every time.

	Imported image layers live in a separate ordered stack above those steps. A
	layer stores only a mounted texture path and a normalised transform - never a
	raw pixel payload - so the recipe remains small enough to network, portable,
	and editable after the material is reopened. The author's validated final PNG
	is transported separately when another client cannot reproduce it exactly.

	Painting is not a separate kind of step. A brush stroke is a fill whose
	region happens to be a painted shape, which means one code path covers the
	bucket, the brush and the eraser.

	The eraser has two meanings, and they are two steps: `revert` brings back
	the image the steps started from, which is what rubbing out paint means,
	and `erase` lowers alpha, which cuts a see-through hole.
-----------------------------------------------------------------------------]]

AdvMat     = AdvMat or {}
AdvMat.Gen = AdvMat.Gen or {}
AdvMat.Ops = AdvMat.Ops or {}

local GEN = AdvMat.Gen
local OPS = AdvMat.Ops

---------------------------------------------------------------------------
-- Step catalogue
---------------------------------------------------------------------------
-- `name` is what the user sees in the step list. Keep it a verb phrase: the
-- list reads as a list of things that were done.
OPS.LIST = {
	{ id = "fill",      name = "Fill with colour" },
	{ id = "gradient",  name = "Blend a gradient", key = "history.gradient" },
	{ id = "tint",      name = "Tint" },
	{ id = "adjust",    name = "Adjust colours" },
	{ id = "blur",      name = "Blur" },
	{ id = "sharpen",   name = "Sharpen" },
	{ id = "noise",     name = "Add noise" },
	{ id = "erase",     name = "Erase to transparent" },
	{ id = "restore",   name = "Make solid again" },
	{ id = "revert",    name = "Restore the original" },
	{ id = "alphafrom", name = "Build transparency from the image" },
}

OPS.BLENDS = {
	{ id = "normal",   name = "Normal", key = "texture.blend_normal" },
	{ id = "replace",  name = "Replace, transparency included", key = "texture.blend_replace" },
	{ id = "multiply", name = "Multiply (darken)", key = "texture.blend_multiply" },
	{ id = "screen",   name = "Screen (lighten)", key = "texture.blend_screen" },
	{ id = "add",      name = "Add", key = "texture.blend_add" },
}

OPS.ALPHA_SOURCES = {
	{ id = "luminance", name = "Brightness" },
	{ id = "colour",    name = "How close to a colour" },
	{ id = "selection", name = "The selected region itself" },
}

-- Steps that work over the whole texture, or over a region drawn with the
-- selection tools. Each one is at least a full pass over the image in Lua for
-- every client that rebuilds the recipe, so they keep the ceiling they always
-- had.
OPS.MAX = 64

-- Brush strokes are the exception. A stroke can only change the pixels its
-- brush passed over, and the image engine applies it to exactly those, so a
-- hundred strokes cost about what one whole-texture fill does. They are not
-- counted against OPS.MAX - running into it after sixty-four strokes was the
-- editor refusing to keep painting for no reason a painter could see. What
-- bounds them instead:
--
--   MAX_STEPS      a ceiling on steps of any kind, far above what one save can
--                  carry to the server in any case
--   STROKE_BUDGET  the total brush work, in whole textures visited (see
--                  Sel.StrokeCost). It is exactly what sixty-four of the
--                  largest possible strokes cost - the most a recipe could
--                  demand while strokes still counted - so no recipe that was
--                  valid before is ever cut short, and a hostile one cannot ask
--                  every client for more work than it could then. An ordinary
--                  stroke is a fraction of one texture; this is tens of
--                  thousands.
OPS.MAX_STEPS     = 4096
OPS.STROKE_BUDGET = OPS.MAX * ( ( AdvMat.Sel and AdvMat.Sel.MAX_BRUSH or 512 ) - 1 )

-- Steps whose effect on one pixel depends on nothing but that pixel and how
-- much of the region covers it. Only these can be applied to a stroke's own
-- pixels in isolation; a blur or noise step needs neighbours or positions.
OPS.POINTWISE = {
	fill = true, tint = true, adjust = true, erase = true,
	restore = true, revert = true, alphafrom = true,
}

-- A layer source is four Lua number arrays while it is being composed. Even
-- with bounded sampling that is materially heavier than an ordinary colour
-- step, so it gets its own cap inside the broader step limit.
OPS.MAX_LAYERS = 12

---------------------------------------------------------------------------
-- Value helpers
---------------------------------------------------------------------------
local function Num( v, lo, hi, fallback )
	return AdvMat.ClampNum( v, lo, hi, fallback )
end

--- Colours travel as a four number array, which is a third of the JSON that
--- { r = , g = , b = , a = } would cost and hashes in a fixed order.
local function Colour( raw, fallback )
	if not istable( raw ) then return fallback end

	return {
		math.floor( Num( raw[ 1 ] or raw.r, 0, 255, fallback[ 1 ] ) ),
		math.floor( Num( raw[ 2 ] or raw.g, 0, 255, fallback[ 2 ] ) ),
		math.floor( Num( raw[ 3 ] or raw.b, 0, 255, fallback[ 3 ] ) ),
		math.floor( Num( raw[ 4 ] or raw.a, 0, 255, fallback[ 4 ] ) ),
	}
end

OPS.Colour = Colour

local WHITE = { 255, 255, 255, 255 }

local function Display( key, variables, fallback )
	if AdvMat.L then return AdvMat.L( key, variables ) end
	return fallback
end

function OPS.IsOp( id )
	for _, def in ipairs( OPS.LIST ) do
		if def.id == id then return true end
	end
	return false
end

--- Stable source-language name for document history. History stores this
--- rather than the currently translated display text so switching languages
--- can rebuild every row in the newly selected language.
function OPS.OpSourceName( id )
	for _, def in ipairs( OPS.LIST ) do
		if def.id == id then return def.name end
	end
	return id
end

function OPS.OpName( id )
	for _, def in ipairs( OPS.LIST ) do
		if def.id == id then
			if def.key and AdvMat.L then return AdvMat.L( def.key ) end
			return AdvMat.LText and AdvMat.LText( def.name ) or def.name
		end
	end
	return id
end

--- A texture path safe to keep in a networked edit recipe. This is deliberately
--- syntactic rather than an existence test: a dedicated server may not mount a
--- clientside texture even though every player who owns the model does.
function OPS.TexturePath( raw )
	local path = AdvMat.NormalizeMaterial( raw or "" )
	if path == "" or #path > 260 then return nil end
	if string.sub( path, 1, 1 ) == "/" or string.find( path, ":", 1, true )
		or string.find( path, "//", 1, true ) or string.find( path, "[%c]" ) then
		return nil
	end
	if string.sub( path, 1, 5 ) == "data/" or string.find( path, "~gmod_topbr", 1, true ) then
		return nil
	end
	-- Render-target names are live renderer state, not mounted source images.
	-- Letting one into a persisted recipe can sample the editor's own buffers
	-- (or a frame/depth target) and makes the result timing-dependent.
	if string.sub( path, 1, 4 ) == "_rt_"
		or string.sub( path, 1, 14 ) == "advmat_canvas_"
		or string.sub( path, 1, 17 ) == "advmat_editbuild_"
		or string.sub( path, 1, 14 ) == "advmat_gensrc_" then
		return nil
	end

	for part in string.gmatch( path, "[^/]+" ) do
		if part == "." or part == ".." then return nil end
	end

	return path
end

local function Quant( value )
	if value >= 0 then return math.floor( value * 1000000 + 0.5 ) / 1000000 end
	return math.ceil( value * 1000000 - 0.5 ) / 1000000
end

--- One imported image layer. Layers are intentionally separate from pixel
--- operations: the GPU can composite a transformed texture in one quad, while
--- flattening it into the operation buffer would turn a photographic image
--- into hundreds of thousands of one-pixel upload runs.
function OPS.SanitizeLayer( raw )
	if not istable( raw ) then return nil end

	local src = OPS.TexturePath( raw.src )
	if not src then return nil end

	local out = {
		src     = src,
		x       = Quant( Num( raw.x,       -2,   3, 0.5 ) ),
		y       = Quant( Num( raw.y,       -2,   3, 0.5 ) ),
		w       = Quant( Num( raw.w,    0.002,   4, 1 ) ),
		h       = Quant( Num( raw.h,    0.002,   4, 1 ) ),
		angle   = Quant( Num( raw.angle, -180, 180, 0 ) ),
		opacity = Quant( Num( raw.opacity,   0,   1, 1 ) ),
	}

	if raw.flipx then out.flipx = true end
	if raw.flipy then out.flipy = true end
	if raw.opaque then out.opaque = true end
	if raw.on == false then out.on = false end

	return out
end

function OPS.DescribeLayer( layer )
	if not istable( layer ) then return "" end

	local path = layer.src or "texture"
	local leaf = string.match( path, "([^/]+)$" ) or path
	local opacity = ( layer.opacity or 1 ) < 1
		and Display( "op.opacity", { value = math.Round( ( layer.opacity or 1 ) * 100 ) },
			" at " .. math.Round( ( layer.opacity or 1 ) * 100 ) .. "%" ) or ""

	return Display( "op.layer", { texture = leaf, opacity = opacity },
		"Layer " .. leaf .. opacity )
end

---------------------------------------------------------------------------
-- Sanitising one step
---------------------------------------------------------------------------
function OPS.Sanitize( raw )
	if not istable( raw ) then return nil end

	local op = tostring( raw.op or "" )
	if not OPS.IsOp( op ) then return nil end

	local out = { op = op }

	-- No region at all means the whole texture, which is both a sensible
	-- default and what "Select none, then adjust" should do.
	local sel = AdvMat.Sel.Sanitize( raw.sel )
	if sel and not AdvMat.Sel.CoversAll( sel ) then out.sel = sel end

	-- Steps are switched off rather than deleted so the user can compare, and
	-- an off step still has to survive a save.
	if raw.on == false then out.on = false end

	if op == "fill" then
		out.color   = Colour( raw.color, WHITE )
		out.opacity = Num( raw.opacity, 0, 1, 1 )
		out.blend   = tostring( raw.blend or "normal" )
		if not GEN.InList( OPS.BLENDS, out.blend ) then out.blend = "normal" end

	elseif op == "gradient" then
		out.color1  = Colour( raw.color1, { 0, 0, 0, 255 } )
		out.color2  = Colour( raw.color2, WHITE )
		out.x1      = Num( raw.x1, 0, 1, 0 )
		out.y1      = Num( raw.y1, 0, 1, 0.5 )
		out.x2      = Num( raw.x2, 0, 1, 1 )
		out.y2      = Num( raw.y2, 0, 1, 0.5 )
		out.opacity = Num( raw.opacity, 0, 1, 1 )
		out.blend   = tostring( raw.blend or "normal" )
		if not GEN.InList( OPS.BLENDS, out.blend ) then out.blend = "normal" end

	elseif op == "tint" then
		out.color  = Colour( raw.color, WHITE )
		out.amount = Num( raw.amount, 0, 1, 1 )
		-- Keeping the original brightness is what makes a tint read as a
		-- recolour rather than as a flat coat of paint.
		out.keepvalue = raw.keepvalue ~= false

		-- A tint stored by older versions deliberately left alpha alone.  New
		-- brush strokes opt into paint-like alpha so drawing on a transparent
		-- blank can actually put pixels there, without changing the playback or
		-- hash of an existing recipe.
		if raw.paintalpha then out.paintalpha = true end

		-- Current brush/fill tints preserve relative source shading while also
		-- respecting the chosen colour's value. paintalpha identifies UI paint
		-- steps from the preceding format, so promoting those here fixes existing
		-- black strokes and gives them a fresh cache identity. Truly legacy tints
		-- omit both fields and retain their historical playback and filename.
		if raw.scalevalue or raw.paintalpha then out.scalevalue = true end

	elseif op == "adjust" then
		out.hue      = Num( raw.hue,     -180, 180, 0 )
		out.sat      = Num( raw.sat,        0,   3, 1 )
		out.val      = Num( raw.val,        0,   3, 1 )
		out.bright   = Num( raw.bright,    -1,   1, 0 )
		out.contrast = Num( raw.contrast,   0,   4, 1 )
		out.desat    = Num( raw.desat,      0,   1, 0 )
		if raw.invert then out.invert = true end

		-- These controls were added after adjustment recipes shipped. Keep them
		-- absent when they are unused so an old recipe retains its byte-for-byte
		-- canonical form and therefore its existing cache filename.
		if raw.gamma ~= nil then
			local gamma = Num( raw.gamma, 0.1, 4, 1 )
			if gamma ~= 1 then out.gamma = gamma end
		end
		if raw.posterize ~= nil then
			out.posterize = math.floor( Num( raw.posterize, 2, 64, 2 ) )
		end
		if raw.threshold ~= nil then
			out.threshold = Num( raw.threshold, 0, 1, 0.5 )
		end

	elseif op == "blur" then
		out.radius = math.floor( Num( raw.radius, 1, 12, 2 ) )

	elseif op == "sharpen" then
		out.amount = Num( raw.amount, 0, 3, 1 )

	elseif op == "noise" then
		out.amount = Num( raw.amount, 0, 1, 0.2 )
		out.seed   = math.floor( Num( raw.seed, 0, 65535, 1 ) )
		if raw.mono then out.mono = true end

	elseif op == "erase" or op == "restore" or op == "revert" then
		out.opacity = Num( raw.opacity, 0, 1, 1 )

	elseif op == "alphafrom" then
		out.from = tostring( raw.from or "luminance" )
		if not GEN.InList( OPS.ALPHA_SOURCES, out.from ) then out.from = "luminance" end

		out.threshold = Num( raw.threshold, 0, 1, 0.5 )
		out.softness  = Num( raw.softness,  0, 1, 0.1 )
		if raw.invert then out.invert = true end
		if out.from == "colour" then out.color = Colour( raw.color, { 0, 0, 0, 255 } ) end
	end

	return out
end

--- One line describing a step, used as its label in the step list.
function OPS.Describe( op )
	if not istable( op ) then return "" end

	local where = AdvMat.Sel.IsEmpty( op.sel ) and "the whole texture"
		or AdvMat.Sel.Describe( op.sel )

	local n = AdvMat.NumToString

	if op.op == "fill" then
		local c = op.color or WHITE
		local colour = string.format( "%d,%d,%d", c[ 1 ], c[ 2 ], c[ 3 ] )
		local opacity = ( op.opacity or 1 ) < 1
			and Display( "op.opacity", { value = math.Round( ( op.opacity or 1 ) * 100 ) },
				" at " .. math.Round( ( op.opacity or 1 ) * 100 ) .. "%" ) or ""
		return Display( "op.fill", { where = where, colour = colour, opacity = opacity },
			"Fill " .. where .. " with " .. colour .. opacity )

	elseif op.op == "gradient" then
		local a = op.color1 or { 0, 0, 0, 255 }
		local b = op.color2 or WHITE
		local from = string.format( "%d,%d,%d", a[ 1 ], a[ 2 ], a[ 3 ] )
		local into = string.format( "%d,%d,%d", b[ 1 ], b[ 2 ], b[ 3 ] )
		local opacity = ( op.opacity or 1 ) < 1
			and Display( "op.opacity", { value = math.Round( ( op.opacity or 1 ) * 100 ) },
				" at " .. math.Round( ( op.opacity or 1 ) * 100 ) .. "%" ) or ""
		return Display( "op.gradient", {
			where = where, colour1 = from, colour2 = into, opacity = opacity,
		}, "Blend " .. where .. " from " .. from .. " to " .. into .. opacity )

	elseif op.op == "tint" then
		local c = op.color or WHITE
		local colour = string.format( "%d,%d,%d", c[ 1 ], c[ 2 ], c[ 3 ] )
		return Display( "op.tint", { where = where, colour = colour },
			"Tint " .. where .. " towards " .. colour )

	elseif op.op == "adjust" then
		local bits = {}
		local LT = AdvMat.LText or function( text ) return text end
		if ( op.hue      or 0 ) ~= 0 then bits[ #bits + 1 ] = LT( "hue" )        .. " " .. n( op.hue ) end
		if ( op.sat      or 1 ) ~= 1 then bits[ #bits + 1 ] = LT( "saturation" ) .. " " .. n( op.sat ) end
		if ( op.val      or 1 ) ~= 1 then bits[ #bits + 1 ] = LT( "brightness" ) .. " " .. n( op.val ) end
		if ( op.bright   or 0 ) ~= 0 then bits[ #bits + 1 ] = LT( "lift" )       .. " " .. n( op.bright ) end
		if ( op.contrast or 1 ) ~= 1 then bits[ #bits + 1 ] = LT( "Contrast" )   .. " " .. n( op.contrast ) end
		if op.gamma ~= nil then bits[ #bits + 1 ] = LT( "gamma" ) .. " " .. n( op.gamma ) end
		if ( op.desat    or 0 )  > 0 then bits[ #bits + 1 ] = LT( "greyscale" )  .. " " .. n( op.desat ) end
		if op.posterize ~= nil then bits[ #bits + 1 ] = LT( "posterize" ) .. " " .. op.posterize end
		if op.threshold ~= nil then bits[ #bits + 1 ] = LT( "threshold" ) .. " " .. n( op.threshold ) end
		if op.invert then bits[ #bits + 1 ] = LT( "inverted" ) end

		if #bits == 0 then
			return Display( "op.adjust_none", { where = where }, "Adjust " .. where .. " (no change)" )
		end
		return Display( "op.adjust", { where = where, changes = table.concat( bits, ", " ) },
			"Adjust " .. where .. ": " .. table.concat( bits, ", " ) )

	elseif op.op == "blur" then
		return Display( "op.blur", { where = where, value = op.radius or 2 },
			"Blur " .. where .. " by " .. ( op.radius or 2 ) .. "px" )

	elseif op.op == "sharpen" then
		return Display( "op.sharpen", { where = where, value = n( op.amount or 1 ) },
			"Sharpen " .. where .. " by " .. n( op.amount or 1 ) )

	elseif op.op == "noise" then
		local value = math.Round( ( op.amount or 0 ) * 100 )
		return Display( "op.noise", { where = where, value = value },
			"Add " .. value .. "% noise to " .. where )

	elseif op.op == "erase" then
		return Display( "op.erase", { where = where }, "Erase " .. where .. " to transparent" )

	elseif op.op == "restore" then
		return Display( "op.restore", { where = where }, "Make " .. where .. " solid again" )

	elseif op.op == "revert" then
		return Display( "op.revert", { where = where }, "Restore the original in " .. where )

	elseif op.op == "alphafrom" then
		local source = string.lower( GEN.NameOf( OPS.ALPHA_SOURCES, op.from or "luminance" ) )
		return Display( "op.alpha_from", { source = source, where = where },
			"Transparency from " .. source .. " over " .. where )
	end

	return OPS.OpName( op.op )
end

---------------------------------------------------------------------------
-- Limits
---------------------------------------------------------------------------

--- True when a step is a brush stroke: a pointwise step whose region is one
--- painted stroke. These are the steps that cost only the pixels they cover.
function OPS.IsStroke( op )
	return istable( op ) and OPS.POINTWISE[ op.op ] == true
		and AdvMat.Sel.IsBrushStroke( op.sel )
end

--- How a list of steps stands against the limits: how many brush strokes,
--- how much brush work they add up to, and how many other steps.
function OPS.Tally( ops )
	local strokes, work, others = 0, 0, 0

	for _, op in ipairs( istable( ops ) and ops or {} ) do
		if OPS.IsStroke( op ) then
			strokes = strokes + 1
			work = work + AdvMat.Sel.StrokeCost( op.sel.shapes[ 1 ] )
		else
			others = others + 1
		end
	end

	return strokes, work, others
end

--- Whether one more (sanitised) step fits in a recipe. When it does not, the
--- second value says which limit it met - "steps", "effects" or "strokes" -
--- so the editor can say which kind of step to delete.
---
--- This is the same rule the recipe sanitiser applies, asked in advance: a
--- step the editor accepted is never one a save would quietly drop.
function OPS.CanAppend( recipe, op )
	local ops = istable( recipe ) and istable( recipe.ops ) and recipe.ops or {}
	if #ops >= OPS.MAX_STEPS then return false, "steps" end

	local _, work, others = OPS.Tally( ops )

	if OPS.IsStroke( op ) then
		if work + AdvMat.Sel.StrokeCost( op.sel.shapes[ 1 ] ) > OPS.STROKE_BUDGET then
			return false, "strokes"
		end
	elseif others >= OPS.MAX then
		return false, "effects"
	end

	return true
end

---------------------------------------------------------------------------
-- The recipe kind
---------------------------------------------------------------------------
GEN.Register( {
	id     = "edit",
	name   = "Edited texture",
	dir    = "advmat/edits",
	prefix = "tex_",
	-- Revision 3 evaluates both whole-image and selected colour adjustments
	-- against every output texel instead of enlarging the bounded editor preview.
	-- This deliberately invalidates earlier nominally-large but visibly 512px
	-- cache files. Revision 5 separates "draw this source opaque" from "throw
	-- its alpha channel away". Opaque Source textures routinely carry phong,
	-- reflection and tint masks in alpha, so images baked by older revisions
	-- cannot safely be reused.
	revision = 5,
	region = false,   -- every step carries its own region

	order = { "src", "size", "fill", "ops" },

	-- Fields added after the kind shipped. Only written into the hash when
	-- set, so every recipe from before they existed keeps its filename.
	optional = { "opaque", "layers" },

	defaults = { src = "", size = 512, ops = {} },

	Sanitize = function( recipe, out )
		local ops = {}
		local work, others = 0, 0

		-- Guarded rather than defaulted: ipairs raises on a string or a number,
		-- and this runs on a table that arrived over the network.
		--
		-- The list is cut short at the first step past a limit, as it always
		-- was, rather than skipping that step and keeping later ones: dropping
		-- a step from the middle would replay everything after it on top of a
		-- different image. See OPS.MAX and OPS.STROKE_BUDGET for why strokes
		-- and other steps are counted apart.
		for _, raw in ipairs( istable( recipe.ops ) and recipe.ops or {} ) do
			if #ops >= OPS.MAX_STEPS then break end

			local clean = OPS.Sanitize( raw )
			if clean then
				if OPS.IsStroke( clean ) then
					work = work + AdvMat.Sel.StrokeCost( clean.sel.shapes[ 1 ] )
					if work > OPS.STROKE_BUDGET then break end
				else
					others = others + 1
					if others > OPS.MAX then break end
				end

				ops[ #ops + 1 ] = clean
			end
		end

		local layers = {}
		for _, raw in ipairs( istable( recipe.layers ) and recipe.layers or {} ) do
			if #layers >= OPS.MAX_LAYERS then break end
			local clean = OPS.SanitizeLayer( raw )
			if clean then layers[ #layers + 1 ] = clean end
		end

		-- A texture built from scratch has no source, so it needs a starting
		-- colour instead. One or the other must be there or there is nothing
		-- to draw on.
		if not out.src then
			out.fill = Colour( recipe.fill, { 255, 255, 255, 255 } )
		elseif istable( recipe.fill ) then
			out.fill = Colour( recipe.fill, { 255, 255, 255, 255 } )
		end

		if not out.src and not out.fill then return nil end

		-- The source texture's alpha channel is only transparency if the
		-- material it belongs to says so. A sheet whose .vmt has neither
		-- $translucent nor $alphatest usually uses the channel as shader data.
		-- `opaque` records that interpretation so every client preserves the
		-- bytes while displaying the RGB as a solid image.
		if recipe.opaque then out.opaque = true end

		-- Editor ownership metadata, not image data. It survives a saved rule so
		-- a later session can retract only the $translucent companion this recipe
		-- added. It is absent from `order`/`optional`, so it cannot change pixels
		-- or the generated PNG cache identity.
		if recipe.autotranslucent == true then out.autotranslucent = true end

		-- Re-saving an untouched source texture is not normally an edit. RTX is
		-- the exception: a newly selected logical Source/VTF name must pass through
		-- this builder once so Remix receives a portable image. `sourcecopy` is the
		-- explicit, persisted intent for that case; it is not inferred from `src`,
		-- so opening an unchanged vanilla texture still remains a no-op.
		--
		-- The marker changes validity, not pixels, and is therefore deliberately
		-- omitted from the recipe signature. Once a real operation exists it is
		-- stripped again so an ordinary edit keeps its existing cache identity.
		if #ops == 0 and #layers == 0 and out.src then
			if recipe.sourcecopy ~= true then return nil end
			out.sourcecopy = true
		end

		out.ops = ops
		if #layers > 0 then out.layers = layers end
		return out
	end,

	Describe = function( recipe )
		local ops     = recipe.ops or {}
		local enabled = 0

		for _, op in ipairs( ops ) do
			if op.on ~= false then enabled = enabled + 1 end
		end

		local head = Display( "recipe.steps", { count = enabled },
			enabled .. " step" .. ( enabled == 1 and "" or "s" ) )
		if enabled < #ops then
			head = head .. " (" .. Display( "recipe.off", { count = #ops - enabled },
				( #ops - enabled ) .. " off" ) .. ")"
		end

		local layerCount = #( recipe.layers or {} )
		if layerCount > 0 then
			head = head .. " + " .. Display( "recipe.layers", { count = layerCount },
				layerCount .. " layer" .. ( layerCount == 1 and "" or "s" ) )
		end

		local bits = { head, ( recipe.size or 0 ) .. "px" }

		if not recipe.src then
			bits[ #bits + 1 ] = Display( "recipe.blank", nil, "from a blank image" )
		end

		-- The first step is the one most likely to identify the edit at a
		-- glance, and it fits.
		if ops[ 1 ] then bits[ #bits + 1 ] = string.lower( OPS.Describe( ops[ 1 ] ) ) end

		return table.concat( bits, " / " )
	end,
} )

---------------------------------------------------------------------------
-- Building a recipe from the editor
---------------------------------------------------------------------------

--- True when the edit produces any transparency, which is what tells the
--- material editor to suggest $translucent or $alphatest alongside it.
function OPS.MakesTransparency( recipe )
	if not istable( recipe ) then return false end

	for _, op in ipairs( recipe.ops or {} ) do
		if op.on ~= false and ( op.op == "erase" or op.op == "alphafrom" ) then
			return true
		end

		if op.on ~= false and op.op == "fill" and op.color and op.color[ 4 ] < 255
			and ( op.blend == "replace" ) then
			return true
		end

		if op.on ~= false and op.op == "gradient" and ( op.blend == "replace" ) then
			local a, b = op.color1, op.color2
			if ( a and a[ 4 ] < 255 ) or ( b and b[ 4 ] < 255 ) then return true end
		end

	end

	if istable( recipe.fill ) and recipe.fill[ 4 ] < 255 then return true end

	return false
end

--- Whether an operation stack deliberately writes the source alpha channel.
--- This is separate from MakesTransparency: `restore` can make pixels solid
--- without leaving any visible transparency, but it still means an existing
--- shader mask must no longer be treated as immutable metadata.
function OPS.RepurposesSourceAlpha( recipe )
	if not istable( recipe ) then return false end

	for _, op in ipairs( recipe.ops or {} ) do
		if op.on ~= false and ( op.op == "erase" or op.op == "restore"
			or op.op == "alphafrom" ) then
			return true
		end

		-- Replace is explicitly the alpha-writing blend mode. An opaque replace
		-- is just as significant as a transparent one: it turns mask bytes into
		-- 255 (the same semantic operation as Restore).
		if op.on ~= false and op.op == "fill" and op.blend == "replace" then
			return true
		end

		if op.on ~= false and op.op == "gradient" and op.blend == "replace" then
			return true
		end
	end

	return istable( recipe.fill ) and recipe.fill[ 4 ] < 255 or false
end

--- Whether an opaque material is carrying shader data in its source alpha.
---
--- `opaque` is a display/material decision: the channel is not transparency.
--- It must not also mean "discard the channel", because Source commonly packs
--- reflection, phong, self-illumination and tint masks into that same byte.
--- Once the user explicitly creates a hole, the channel is deliberately
--- repurposed as transparency and the original mask is flattened first; Source
--- cannot interpret one alpha channel as both a mask and translucency.
function OPS.PreservesSourceMask( recipe, sourceHasAlpha )
	if sourceHasAlpha == nil and istable( recipe ) and AdvMat.Gen
		and AdvMat.Gen.SourceHasAlpha then
		sourceHasAlpha = AdvMat.Gen.SourceHasAlpha( recipe.src )
	end

	return sourceHasAlpha == true
		and istable( recipe )
		and recipe.opaque == true
		and isstring( recipe.src ) and recipe.src ~= ""
		and not OPS.RepurposesSourceAlpha( recipe )
end
