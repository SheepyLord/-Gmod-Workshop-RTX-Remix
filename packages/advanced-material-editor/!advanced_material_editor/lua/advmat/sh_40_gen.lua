--[[---------------------------------------------------------------------------
	Advanced Material Editor - generated texture recipes

	A generated texture is stored as a RECIPE, not as image data: the source
	texture plus the settings it was made with. That is what travels over the
	network and what is written to the override database.

	Generated maps are normally rebuilt from that recipe in each client's data
	folder. Hand-edited maps additionally publish their verified final PNG via
	the server because older renderers cannot reproduce large edits exactly.
	The recipe remains the durable/editable representation in both cases, so the
	settings can be reopened later instead of being baked away.

	The recipe hashes to the output filename, so identical settings reuse the
	file that is already on disk and changed settings write a new one.

	There are four kinds of recipe, all sharing this envelope:

	    normal      a tangent space normal map derived from a height field
	    phongexp    a $phongexponenttexture derived from the base colour
	    envmapmask  a reflectivity mask derived from the base colour
	    edit        an image edited by hand in the texture editor

	Each kind registers itself into GEN.Kinds with its own defaults, its own
	sanitiser and its own field order for hashing. This file only knows about
	the envelope; the kinds live in the files that follow.
-----------------------------------------------------------------------------]]

AdvMat     = AdvMat or {}
AdvMat.Gen = AdvMat.Gen or {}

local GEN = AdvMat.Gen

---------------------------------------------------------------------------
-- Kind registry
---------------------------------------------------------------------------
-- Populated by sh_41 (edit), sh_42 (normal) and sh_43 (phong / envmap).
-- A kind is:
--     id        string stored in recipe.kind
--     name      what the user sees
--     dir       output folder under garrysmod/data/
--     prefix    filename prefix
--     defaults  table merged in before sanitising
--     order     field names, in the order they are hashed
--     Sanitize  function( recipe, out ) -> out or nil
--     Describe  function( recipe ) -> one line of text
--     region    true when the kind honours recipe.region
GEN.Kinds = GEN.Kinds or {}

-- Every dimension a generated image is allowed to have. Width and height are
-- chosen from this list independently, so an oblong texture stays oblong: a
-- 4096 x 2048 sheet squeezed into a square is stretched by a factor of two, and
-- a mask built from it lands on the model at the wrong place.
--
-- The top of the ladder is expensive and honestly so. There is no image API
-- here, so every pixel is a Lua table entry: a 4096 x 4096 read is sixteen
-- million of them across four arrays, which is a few hundred megabytes and a
-- pause of several seconds. It is offered because a mask generated smaller than
-- the material it sits on is visibly soft against it, and that is worse. The
-- dialogs say which sizes are the expensive ones.
GEN.SIZES = { 128, 256, 512, 1024, 2048, 4096 }

-- Above this an image is heavy enough to be worth warning about before it is
-- built rather than afterwards.
GEN.HEAVY_PIXELS = 1024 * 1024

--- The kind a recipe belongs to. Recipes written before the editor grew more
--- than one generator have no `kind` field at all, and those were all normal
--- maps, so that is what an absent kind means.
function GEN.KindOf( recipe )
	if not istable( recipe ) then return nil end

	local id = recipe.kind
	if not isstring( id ) or id == "" then id = "normal" end

	return GEN.Kinds[ id ], id
end

function GEN.Register( def )
	GEN.Kinds[ def.id ] = def
	return def
end

local function HasValue( list, v )
	for _, entry in ipairs( list ) do
		if entry == v then return true end
	end
	return false
end

GEN.HasValue = HasValue

--- One dimension of a generated image, or `fallback` when it is not one that is
--- offered.
---
--- Anything unrecognised falls back rather than being rounded to the nearest.
--- A recipe naming 517 pixels did not come from this editor, and rounding it
--- would hash it to a file that claims to be something it is not.
function GEN.SnapSize( v, fallback )
	local n = math.floor( AdvMat.ClampNum( v, 1, 8192, 0 ) )
	if HasValue( GEN.SIZES, n ) then return n end
	return fallback
end

--- Preview recipes may need a smaller short edge to keep an oblong texture's
--- shape under a 128px long-edge cap. These sizes are internal only: the output
--- menus and saved recipes still use GEN.SIZES.
function GEN.SnapPreviewSize( v, fallback )
	local n = math.floor( AdvMat.ClampNum( v, 1, 8192, 0 ) )
	local offered = 1

	while offered < n and offered < 4096 do offered = offered * 2 end
	if offered == n then return n end
	return fallback
end

--- True when a recovered alpha channel says the whole image is invisible.
---
--- That answer is never usable, whichever of two things produced it. A
--- texture whose alpha is genuinely zero everywhere would be a material
--- nobody can see, so it is not what the author meant; and a draw that
--- failed outright - which some builds produce for a DXT1 texture drawn
--- through a translucent material - leaves both recovery passes showing
--- nothing but their own backgrounds, which recovers as alpha zero across
--- the board. Either way the honest reading of the texture is "opaque", and
--- the caller re-reads it that way.
---
--- The threshold is a fraction of a percent rather than exactly zero because
--- the render target's rounding leaves a few stray near-zero values even in
--- a genuinely empty channel.
function GEN.AlphaLooksEmpty( a, n )
	local solid = 0
	local limit = math.max( math.floor( n * 0.002 ), 1 )

	for i = 1, n do
		if a[ i ] > 8 then
			solid = solid + 1
			if solid >= limit then return false end
		end
	end

	return true
end

--- The largest dimension this client is willing to read or generate.
---
--- Snapped DOWN to an offered size rather than refused when it is not one of
--- them: this is a ceiling, and a number in between should hold everything
--- below it rather than fall back to the default and quietly allow MORE than
--- was asked for.
function GEN.MaxSize()
	local cv   = GetConVar( "advmat_max_texture_size" )
	local want = math.floor( AdvMat.ClampNum( cv and cv:GetInt(), 1, 8192, 1024 ) )

	local best = GEN.SIZES[ 1 ]

	for _, size in ipairs( GEN.SIZES ) do
		if size <= want then best = size end
	end

	return best
end

--- A recipe's width and height.
---
--- Height defaults to width, because that is what a recipe with no height field
--- means: every one written before images were allowed to be oblong was square,
--- and leaving the field out is how they stay byte for byte what they were.
function GEN.Dims( recipe )
	if not istable( recipe ) then return 512, 512 end

	local w = math.floor( tonumber( recipe.size ) or 512 )
	local h = math.floor( tonumber( recipe.height ) or w )

	return w, h
end

--- "2048 x 1024", for anywhere a size has to be shown.
function GEN.DimText( w, h )
	return w .. " x " .. h
end

--- `w` x `h` shrunk until its longer side fits `cap`, keeping the shape.
---
--- Halved rather than scaled to fit, so both sides stay powers of two and stay
--- on the ladder.
---
--- Keeping the shape is the whole point, and it is why a ceiling cannot just
--- be applied to each axis on its own: capping 4096 x 2048 at 1024 that way
--- gives 1024 x 1024, which is the oblong sheet squashed into a square - the
--- exact fault the shape is being carried around to avoid.
function GEN.FitWithin( w, h, cap )
	w = math.max( math.floor( w or 512 ), 1 )
	h = math.max( math.floor( h or w ), 1 )

	while ( w > cap or h > cap ) and ( w > 1 or h > 1 ) do
		w = math.max( math.floor( w / 2 ), 1 )
		h = math.max( math.floor( h / 2 ), 1 )
	end

	return w, h
end

-- Texture edits are evaluated in Lua, where four numeric channel tables at
-- 2048 x 2048 consume hundreds of megabytes before the PNG encoder even gets
-- its own copy.  Keep the CPU representation bounded; the clientside builder
-- draws this working result over the full-size source in a render target and
-- lets the engine encode the requested output size.
GEN.EDIT_WORK_PIXELS = 512 * 512

function GEN.EditWorkDims( w, h )
	w = math.max( math.floor( w or 512 ), 1 )
	h = math.max( math.floor( h or w ), 1 )

	while w * h > GEN.EDIT_WORK_PIXELS and w > 32 and h > 32 do
		w = math.floor( w / 2 )
		h = math.floor( h / 2 )
	end

	return w, h
end

--- True when `id` names one of the entries in a { id = , name = } list.
function GEN.InList( list, id )
	for _, entry in ipairs( list ) do
		if entry.id == id then return true end
	end
	return false
end

--- The display name for an id in a { id = , name = } list.
function GEN.NameOf( list, id )
	for _, entry in ipairs( list ) do
		if entry.id == id then
			return AdvMat.LText and AdvMat.LText( entry.name ) or entry.name
		end
	end
	return id
end

---------------------------------------------------------------------------
-- Sanitising
---------------------------------------------------------------------------

--- Coerce anything (including a table straight off the network) into a valid
--- recipe. Returns nil when the recipe is unusable.
function GEN.Sanitize( recipe )
	if not istable( recipe ) then return nil end

	local kind, id = GEN.KindOf( recipe )
	if not kind then return nil end

	local preview = recipe._preview == true
	local snap = preview and GEN.SnapPreviewSize or GEN.SnapSize
	local w = snap( recipe.size, 512 )
	local h = snap( recipe.height, w )

	local out = { kind = id, size = w }
	if preview then out._preview = true end

	-- Stored only when the image is not square. An absent height means "the
	-- same as the width", so every square recipe is exactly the table it was
	-- before oblong ones existed and hashes to the file already on disk.
	if h ~= w then out.height = h end

	-- An edit recipe carries its own source, and a generator may be reading
	-- from an edit rather than from a plain .vtf, so the source is validated
	-- by the kind rather than here.
	local src = AdvMat.NormalizeMaterial( recipe.src or "" )
	if src ~= "" then out.src = src end

	-- Where the generator is allowed to write. Absent means everywhere, which
	-- is both the default and what every recipe saved before regions existed
	-- means.
	if kind.region and AdvMat.Sel then
		local region = AdvMat.Sel.Sanitize( recipe.region )

		if region then
			out.region     = region
			out.regionmode = ( recipe.regionmode == "outside" ) and "outside" or "inside"
			out.regionfill = math.floor( AdvMat.ClampNum( recipe.regionfill, -1, 255, -1 ) )
		end
	end

	-- UV based selections need to know which model and which of its materials
	-- they are talking about, and that is a property of the whole recipe rather
	-- than of each shape.
	--
	-- The material PATH is what identifies the mesh, not the slot number.
	-- Entity:GetMaterials silently drops materials that are missing from disk
	-- and shifts every later index along, so a slot number can point at the
	-- wrong mesh on exactly the broken models where it matters most. The slot
	-- is kept only as a fallback for a path that matches no mesh at all.
	local model = AdvMat.NormalizeModel( recipe.model or "" )
	if model ~= "" and string.sub( model, -4 ) == ".mdl" then
		out.model = model
		out.slot  = math.floor( AdvMat.ClampNum( recipe.slot, 0, AdvMat.GetMaterialLimit( model ) - 1, 0 ) )

		local matpath = AdvMat.NormalizeMaterial( recipe.matpath or "" )
		if matpath ~= "" then out.matpath = matpath end

		-- Which parts of the model were showing when the selection was made.
		--
		-- A model with bodygroups has more than one mesh for the same slot, and
		-- util.GetModelMeshes hands back a DIFFERENT list for each combination -
		-- a different length, so the same slot number is a different piece of
		-- geometry. A piece picked off the model as it was drawn has to be
		-- resolved against the model as it was drawn, or it comes back as some
		-- other part of the character entirely.
		--
		-- Nought is every group at its first option, which is both the common
		-- case and what a bare model panel shows, so it is left out rather than
		-- written: an absent field means the same thing and does not change the
		-- signature of every recipe that already exists.
		local body = math.floor( AdvMat.ClampNum( recipe.mask, 0, 2 ^ 24, 0 ) )
		if body > 0 then out.mask = body end
	end

	out = kind.Sanitize( recipe, out )
	if not out then return nil end

	-- Drop the model reference again unless something in the finished recipe
	-- actually resolves against the mesh. It is part of the hash, and carrying
	-- it when nothing reads it would change the output filename of a recipe
	-- that produces identical pixels.
	if out.model and not GEN.UsesMesh( out ) then
		out.model, out.slot, out.matpath, out.mask = nil, nil, nil, nil
	end

	return out
end

--- True when any selection anywhere in the recipe has to look at the model.
function GEN.UsesMesh( recipe )
	if not AdvMat.Sel then return false end

	if AdvMat.Sel.NeedsMesh( recipe.region ) then return true end

	for _, op in ipairs( istable( recipe.ops ) and recipe.ops or {} ) do
		if istable( op ) and AdvMat.Sel.NeedsMesh( op.sel ) then return true end
	end

	return false
end

--- Sanitize a whole { [parameter] = recipe } table. Returns nil when empty, so
--- rules without generated textures carry no extra field at all.
function GEN.SanitizeAll( gen )
	if not istable( gen ) then return nil end

	local out, n = {}, 0

	for key, recipe in pairs( gen ) do
		if isstring( key ) and n < 12 then
			local k = string.lower( string.Trim( key ) )
			if string.sub( k, 1, 1 ) == "$" and #k <= 64 then
				local clean = GEN.Sanitize( recipe )
				if clean then
					out[ k ] = clean
					n = n + 1
				end
			end
		end
	end

	if n == 0 then return nil end
	return out
end

---------------------------------------------------------------------------
-- Identity
---------------------------------------------------------------------------

--- Canonical text for one value. Tables are walked with their keys sorted, so
--- two tables holding the same data always produce the same text no matter
--- what order pairs() happened to hand them back in.
function GEN.Canonical( v )
	if v == nil       then return "~" end
	if isbool( v )    then return v and "1" or "0" end
	if isnumber( v )  then return AdvMat.NumToString( v ) end
	if isstring( v )  then return v end
	if not istable( v ) then return tostring( v ) end

	local parts = {}

	-- Array part first, in order, then the named keys sorted by name.
	local n = #v
	for i = 1, n do parts[ #parts + 1 ] = GEN.Canonical( v[ i ] ) end

	-- The key itself is kept, not just its text, so a false value still reads
	-- back as false rather than as a missing key.
	local keys = {}
	for k in pairs( v ) do
		if not ( isnumber( k ) and k >= 1 and k <= n and k == math.floor( k ) ) then
			keys[ #keys + 1 ] = k
		end
	end
	table.sort( keys, function( a, b ) return tostring( a ) < tostring( b ) end )

	for _, k in ipairs( keys ) do
		parts[ #parts + 1 ] = tostring( k ) .. "=" .. GEN.Canonical( v[ k ] )
	end

	return "(" .. table.concat( parts, "," ) .. ")"
end

--- Canonical text form, so the same settings always hash the same way.
---
--- A normal map recipe with no region hashes exactly the way it did before
--- there were other kinds of recipe, so every normal map already sitting in a
--- data folder stays valid instead of being regenerated on upgrade.
function GEN.Signature( recipe )
	local kind, id = GEN.KindOf( recipe )
	if not kind then return "" end

	local parts = {}

	if id ~= "normal" then parts[ #parts + 1 ] = "kind=" .. id end

	for _, key in ipairs( kind.order ) do
		parts[ #parts + 1 ] = key .. "=" .. GEN.Canonical( recipe[ key ] )
	end

	-- Fields added after a kind shipped go here instead of into `order`, and
	-- are only written when they are actually set. That keeps the signature of
	-- a recipe that does not use them byte for byte identical to what it
	-- hashed to before the field existed, so the .png already on disk is still
	-- the right one and nothing is regenerated on upgrade.
	for _, key in ipairs( kind.optional or {} ) do
		if recipe[ key ] ~= nil then
			parts[ #parts + 1 ] = key .. "=" .. GEN.Canonical( recipe[ key ] )
		end
	end

	-- Written only when the image is not square, for the same reason it is only
	-- stored then: a square recipe has to hash the way it did before there was
	-- such a thing as a height.
	if recipe.height and recipe.height ~= recipe.size then
		parts[ #parts + 1 ] = "height=" .. tostring( recipe.height )
	end

	if recipe.region then
		parts[ #parts + 1 ] = "region=" .. GEN.Canonical( recipe.region )
		parts[ #parts + 1 ] = "regionmode=" .. tostring( recipe.regionmode or "inside" )
		parts[ #parts + 1 ] = "regionfill=" .. tostring( recipe.regionfill or -1 )
	end

	-- Which model a selection's UV shapes resolve against changes the pixels,
	-- so it has to change the hash. Only written when it is actually set, for
	-- the same reason the optional fields above are.
	if recipe.model then
		parts[ #parts + 1 ] = "model=" .. recipe.model
		parts[ #parts + 1 ] = "slot=" .. tostring( recipe.slot or 0 )
		parts[ #parts + 1 ] = "matpath=" .. tostring( recipe.matpath or "" )

		-- Same reasoning as the model itself: a different set of parts is a
		-- different mesh, so it is different pixels and must be a different
		-- file.
		parts[ #parts + 1 ] = "body=" .. tostring( recipe.mask or 0 )
	end

	return table.concat( parts, ";" )
end

-- Generated filenames are network identities, so every branch must produce
-- the same digest. AdvMat.SHA1 (sh_10_util) uses the engine's SHA-1 only after
-- checking it against a known answer, and an identical pure-Lua one otherwise.
local Hash = AdvMat.SHA1

GEN.Hash = Hash

--- Output file, relative to garrysmod/data/. Written as .png because that is
--- one of the few extensions file.Write accepts, and because it gives the user
--- something they can convert to a .vtf and ship with the model.
function GEN.FileName( recipe )
	local kind = GEN.KindOf( recipe )
	if not kind then return "advmat/gen/bad.png" end

	-- A builder revision changes the pixels without changing the user-authored
	-- recipe. Keep it out of the networked/settings schema, but include it in
	-- the cache identity so a corrected builder never reuses an older degraded
	-- image already present in data/.
	local signature = GEN.Signature( recipe )
	if kind.revision then signature = "revision=" .. tostring( kind.revision ) .. ";" .. signature end

	return kind.dir .. "/" .. kind.prefix .. Hash( signature ) .. ".png"
end

--- Path to hand to Global.Material for the generated image.
function GEN.MaterialPath( recipe )
	return "data/" .. GEN.FileName( recipe )
end

---------------------------------------------------------------------------
-- Display
---------------------------------------------------------------------------

--- One-line summary of a recipe, shown next to the parameter it feeds.
function GEN.Describe( recipe )
	local kind = GEN.KindOf( recipe )
	if not kind then return "" end

	local text = kind.Describe( recipe )

	if recipe.region then
		local where = ( recipe.regionmode == "outside" ) and "outside" or "inside"
		text = text .. "  /  only " .. where .. " a selected region"
	end

	return text
end

--- The kind's display name, for lists and window titles.
function GEN.KindName( recipe )
	local kind = GEN.KindOf( recipe )
	return kind and kind.name or "generated"
end

---------------------------------------------------------------------------
-- Which parameters each generator can be offered for
---------------------------------------------------------------------------
GEN.NORMAL_TARGETS = {
	[ "$bumpmap" ]        = true,
	[ "$bumpmap2" ]       = true,
	[ "$normalmap" ]      = true,
	[ "$normalmap2" ]     = true,
	[ "$corneatexture" ]  = true,
	[ "$parallaxmap" ]    = true,
	[ "$flowmap" ]        = true,
}

GEN.PHONG_TARGETS = {
	[ "$phongexponenttexture" ] = true,
	[ "$phongwarptexture" ]     = false,
}

GEN.ENVMASK_TARGETS = {
	[ "$envmapmask" ]      = true,
	[ "$envmapmask2" ]     = true,
	[ "$blendmodulatetexture" ] = false,
}

--- Every parameter that takes an image and can therefore be hand edited.
--- Deliberately broad: if it is a texture, you may want to paint on it.
function GEN.CanEdit( key )
	return isstring( key ) and string.sub( key, 1, 1 ) == "$"
end
