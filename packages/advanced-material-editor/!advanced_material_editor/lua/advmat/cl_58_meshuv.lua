--[[---------------------------------------------------------------------------
	Advanced Material Editor - model geometry and UV layout

	A texture is a flat image, but the thing you are painting is a model, and
	the mapping between the two is not obvious from either side. Wrapped around
	an unfamiliar character, a texture sheet is a jigsaw of unlabelled pieces.

	This file reads that mapping out of the .mdl with util.GetModelMeshes so the
	editor can show it both ways round: the UV wireframe drawn over the canvas,
	and the piece under the cursor lit up on the model next to it. Clicking a
	part of the model selects the matching part of the texture, which is the
	only way most people will ever find the right corner of the sheet.

	Three facts from the engine shape everything here.

	  The mesh list is keyed by MATERIAL, not by sub-material slot. Slot
	  numbers come from Entity:GetMaterials, which silently drops materials
	  missing from disk and shifts every later index along, so matching on the
	  path is the only mapping that is right on a broken model. The slot is
	  kept as a fallback.

	  Vertices are shared between triangles as the SAME Lua table. Studiomdl
	  splits a vertex wherever the UV layout has a seam, so "triangles that
	  share a vertex table" is exactly "triangles in the same UV island". That
	  makes finding an island a plain union-find over table identity, with no
	  tolerances to get wrong.

	  Positions come back in the bind pose with no bone transform applied, so
	  anything drawn over a live entity has to be skinned by hand first.

	The call is expensive - one Lua table per vertex - so the material requested
	by the editor is cached per model and bodygroup combination. The cache is
	deliberately tiny: each entry pins three Lua tables per triangle and one
	material can have thirty thousand of them.
-----------------------------------------------------------------------------]]

AdvMat      = AdvMat or {}
AdvMat.Mesh = AdvMat.Mesh or {}

local M = AdvMat.Mesh

-- Above this, the wireframe stops being a readable picture and starts being a
-- grey rectangle, and the tables cost more than the feature is worth.
M.MAX_TRIANGLES = 30000

local cache      = {}
local cacheOrder = {}
local MAX_GROUPS = 4

---------------------------------------------------------------------------
-- Reading the model
---------------------------------------------------------------------------

--- Meshes in `model`, grouped by material path.
---
--- A group is:
---     material  normalised .vmt path
---     tris      { { u1,v1, u2,v2, u3,v3, index }, ... }
---     pos       flat array of Vectors, three per triangle, bind pose
---     weights   flat array of bone weight tables, three per triangle, or nil
---     island    { [triangleIndex] = islandId }
---     islands   { [islandId] = { triangle, ... } }
---     clipped   true when the model was too dense and only part was read
---
--- When `matpath` or `slot` is supplied, only that material is retained. The
--- engine has already returned the whole mesh list, so a cheap first pass can
--- resolve the path (or slot fallback) before the triangle budget is spent.
--- This matters on high-poly models: a model-wide budget lets an earlier body
--- mesh consume every triangle and makes later materials look as if they have
--- no UVs at all.
---
--- `mask` is the packed bodygroup value, so hiding a part in the preview also
--- takes it out of the geometry that gets clicked. Without that, a ray fired
--- at the head goes through a hood that is no longer drawn and selects the
--- hood.
function M.Data( model, mask, matpath, slot )
	model = AdvMat.NormalizeModel( model or "" )
	if model == "" then return nil end

	mask = math.floor( math.max( tonumber( mask ) or 0, 0 ) )

	-- Nought is the default configuration, and keying it as the bare model name
	-- keeps every existing entry in the cache exactly where it was.
	local key = ( mask == 0 ) and model or ( model .. "#" .. mask )
	local targeted = matpath ~= nil or slot ~= nil
	local requested = targeted and AdvMat.NormalizeMaterial( matpath or "" ) or nil
	local slotIndex = math.floor( math.max( tonumber( slot ) or 0, 0 ) )

	if targeted then
		key = key .. "@" .. requested .. ":" .. slotIndex
	end

	local hit = cache[ key ]
	if hit ~= nil then
		if hit == false then return nil end
		return hit
	end

	-- A missing model does not fail cleanly: the first call hands back
	-- models/error.mdl geometry and only later calls return nothing. Checking
	-- the path first is the only way to tell the difference.
	if util.IsValidModel and not util.IsValidModel( model ) then
		cache[ key ] = false
		return nil
	end

	local meshes
	if mmdhl and mmdhl.GetRigForModel and mmdhl.GetRigForModel( model ) then
		meshes = mmdhl.GetModelMaterialMeshes( model, targeted and slotIndex or nil, mask )
	else meshes = util.GetModelMeshes( model, 0, mask ) end

	if not istable( meshes ) or #meshes == 0 then
		cache[ key ] = false
		return nil
	end

	-- Resolve the material before reading any triangles. A sub-material slot is
	-- an index into distinct material paths, not necessarily into mesh entries:
	-- one material can be split over many meshes (Firefly's clothes has fourteen).
	local targetPath

	if targeted then
		local present, paths = {}, {}

		for _, data in ipairs( meshes ) do
			local tri = data.triangles
			if istable( tri ) and #tri >= 3 then
				local path = AdvMat.NormalizeMaterial( data.material or "" )
				if not present[ path ] then
					present[ path ] = true
					paths[ #paths + 1 ] = path
				end
			end
		end

		targetPath = requested ~= "" and present[ requested ] and requested
			or paths[ slotIndex + 1 ]

		if not targetPath then
			cache[ key ] = false
			return nil
		end
	end

	local groups  = {}
	local order   = {}
	local total   = 0
	local clipped = false

	for meshIndex, data in ipairs( meshes ) do
		local path = AdvMat.NormalizeMaterial( data.material or "" )
		local tri  = data.triangles

		if ( not targetPath or path == targetPath ) and istable( tri ) and #tri >= 3 then
			local group = groups[ path ]

			if not group then
				group = {
					material = path,
					index    = meshIndex,
					tris     = {},
					pos      = {},
					weights  = nil,
					parent   = {},   -- union-find over vertex tables
				}
				groups[ path ] = group
				order[ #order + 1 ] = group
			end

			local tris, pos = group.tris, group.pos
			local parent    = group.parent

			-- Union-find, keyed on the vertex tables themselves. Two triangles
			-- that share a vertex table are joined; a UV seam duplicates the
			-- vertex, so the two sides of a seam are never joined.
			local function Find( v )
				local root = v
				while parent[ root ] and parent[ root ] ~= root do root = parent[ root ] end

				-- Path compression, or a long chain makes this quadratic on a
				-- dense mesh.
				while parent[ v ] and parent[ v ] ~= root do
					local nxt = parent[ v ]
					parent[ v ] = root
					v = nxt
				end

				return root
			end

			for i = 1, #tri - 2, 3 do
				if total >= M.MAX_TRIANGLES then
					clipped = true
					break
				end

				local a, b, c = tri[ i ], tri[ i + 1 ], tri[ i + 2 ]

				if a and b and c and a.pos and b.pos and c.pos then
					total = total + 1
					local n = #tris + 1

					tris[ n ] = {
						a.u or 0, a.v or 0,
						b.u or 0, b.v or 0,
						c.u or 0, c.v or 0,
						n,
					}

					local o = ( n - 1 ) * 3
					pos[ o + 1 ] = a.pos
					pos[ o + 2 ] = b.pos
					pos[ o + 3 ] = c.pos

					if a.weights or b.weights or c.weights then
						group.weights = group.weights or {}
						group.weights[ o + 1 ] = a.weights
						group.weights[ o + 2 ] = b.weights
						group.weights[ o + 3 ] = c.weights
					end

					-- Join the three corners into one set.
					parent[ a ] = parent[ a ] or a
					parent[ b ] = parent[ b ] or b
					parent[ c ] = parent[ c ] or c

					local ra, rb, rc = Find( a ), Find( b ), Find( c )
					if rb ~= ra then parent[ rb ] = ra end
					if rc ~= ra then parent[ Find( c ) ] = ra end

					-- Remembered so the islands can be resolved in one pass at
					-- the end, once every union has happened.
					tris[ n ].v = a
				end
			end
		end

		if clipped then break end
	end

	if #order == 0 then
		cache[ key ] = false
		return nil
	end

	-- Resolve every triangle to the root of its set, and number the roots.
	for _, group in ipairs( order ) do
		local parent = group.parent
		local ids    = {}

		group.island  = {}
		group.islands = {}

		local function Find( v )
			local root = v
			while parent[ root ] and parent[ root ] ~= root do root = parent[ root ] end
			return root
		end

		for _, t in ipairs( group.tris ) do
			local root = Find( t.v )
			local id   = ids[ root ]

			if not id then
				id = #group.islands + 1
				ids[ root ] = id
				group.islands[ id ] = {}
			end

			group.island[ t[ 7 ] ] = id

			local list = group.islands[ id ]
			list[ #list + 1 ] = t
		end

		-- The vertex references were only needed to build the sets, and each
		-- one pins a whole MeshVertex table (with its Vectors) in memory.
		group.parent = nil
		group.clipped = clipped
		for _, t in ipairs( group.tris ) do t.v = nil end
	end

	local out = {
		model    = model,
		mask     = mask,
		groups   = groups,
		order    = order,
		clipped  = clipped,
		count    = total,
		selected = targetPath and groups[ targetPath ] or nil,
	}

	if clipped then
		AdvMat.Log( "%s has more than %d triangles; the UV overlay shows the first %d.",
			model, M.MAX_TRIANGLES, total )
	end

	cache[ key ] = out
	cacheOrder[ #cacheOrder + 1 ] = key

	while #cacheOrder > MAX_GROUPS do
		local drop = table.remove( cacheOrder, 1 )
		cache[ drop ] = nil
	end

	return out
end

function M.Flush()
	cache, cacheOrder = {}, {}
end

hook.Add( "OnReloaded", "AdvMat.MeshFlush", M.Flush )

---------------------------------------------------------------------------
-- Finding the right group
---------------------------------------------------------------------------

--- The mesh group for one sub-material. Matched on the material path first,
--- because that is the mapping the engine actually uses; the slot number is
--- only a fallback for a path that is in no mesh at all.
function M.Group( model, matpath, slot, mask )
	local data = M.Data( model, mask, matpath, slot )
	if not data then return nil end
	if data.selected then return data.selected end

	if matpath and matpath ~= "" then
		local group = data.groups[ AdvMat.NormalizeMaterial( matpath ) ]
		if group then return group end
	end

	return data.order[ ( tonumber( slot ) or 0 ) + 1 ]
end

--- The UV triangles for one sub-material, in the form the rasteriser wants.
function M.UVTriangles( model, matpath, slot, mask )
	local group = M.Group( model, matpath, slot, mask )
	return group and group.tris or nil
end

--- How many triangles the overlay will draw, so the UI can warn before it
--- tries.
function M.Count( model, matpath, slot, mask )
	local group = M.Group( model, matpath, slot, mask )
	return group and #group.tris or 0
end

---------------------------------------------------------------------------
-- The wireframe, as a flat list of line endpoints
---------------------------------------------------------------------------

--- Every triangle edge of a group as { u1, v1, u2, v2, ... } in 0..1.
---
--- Built once and cached on the group. The canvas draws these directly rather
--- than baking them into a render target and stretching that over the image:
--- one coordinate mapping for the outline and the selection instead of two, so
--- they cannot disagree about where a triangle is.
function M.Edges( group )
	if not group then return nil end
	if group.edges then return group.edges end

	local edges = {}
	local tris  = group.tris

	-- Shared edges are drawn twice. Deduplicating them means hashing a hundred
	-- thousand endpoint pairs to save a draw call that costs almost nothing.
	for i = 1, #tris do
		local t = tris[ i ]
		local o = #edges

		edges[ o +  1 ], edges[ o +  2 ], edges[ o +  3 ], edges[ o +  4 ] = t[1], t[2], t[3], t[4]
		edges[ o +  5 ], edges[ o +  6 ], edges[ o +  7 ], edges[ o +  8 ] = t[3], t[4], t[5], t[6]
		edges[ o +  9 ], edges[ o + 10 ], edges[ o + 11 ], edges[ o + 12 ] = t[5], t[6], t[1], t[2]
	end

	group.edges = edges
	return edges
end

---------------------------------------------------------------------------
-- Hit testing in UV space
---------------------------------------------------------------------------
local function PointInTriangle( px, py, ax, ay, bx, by, cx, cy )
	-- Barycentric sign test. Doing it with the raw cross products avoids a
	-- division and the degenerate-triangle special case that comes with one.
	local d1 = ( px - bx ) * ( ay - by ) - ( ax - bx ) * ( py - by )
	local d2 = ( px - cx ) * ( by - cy ) - ( bx - cx ) * ( py - cy )
	local d3 = ( px - ax ) * ( cy - ay ) - ( cx - ax ) * ( py - ay )

	local neg = ( d1 < 0 ) or ( d2 < 0 ) or ( d3 < 0 )
	local pos = ( d1 > 0 ) or ( d2 > 0 ) or ( d3 > 0 )

	return not ( neg and pos )
end

M.PointInTriangle = PointInTriangle

-- Hit testing runs on every cursor move over the canvas and over the model
-- preview. Walking forty thousand triangles twice a frame is not affordable,
-- so the UV layout is baked once into a grid of "which triangle is here" and
-- looked up directly, which makes it constant time.
--
-- 512 rather than 256: at 256 a click near the border between two islands lands
-- in the wrong one often enough to notice, because a grid cell covers four
-- pixels of a 1024 sheet.
local GRID = 512

local function BuildGrid( group )
	local grid = {}
	for i = 1, GRID * GRID do grid[ i ] = 0 end

	for index, t in ipairs( group.tris ) do
		local ax, ay = t[ 1 ] * GRID, t[ 2 ] * GRID
		local bx, by = t[ 3 ] * GRID, t[ 4 ] * GRID
		local cx, cy = t[ 5 ] * GRID, t[ 6 ] * GRID

		local y0 = math.max( math.floor( math.min( ay, by, cy ) ), 0 )
		local y1 = math.min( math.ceil( math.max( ay, by, cy ) ), GRID ) - 1
		local x0 = math.max( math.floor( math.min( ax, bx, cx ) ), 0 )
		local x1 = math.min( math.ceil( math.max( ax, bx, cx ) ), GRID ) - 1

		-- A triangle smaller than one grid cell would fall through a
		-- centre-sample test entirely, so its cell is claimed outright.
		if x1 < x0 or y1 < y0 then
			local gx = math.Clamp( math.floor( ( ax + bx + cx ) / 3 ), 0, GRID - 1 )
			local gy = math.Clamp( math.floor( ( ay + by + cy ) / 3 ), 0, GRID - 1 )
			grid[ gy * GRID + gx + 1 ] = index
		else
			for gy = y0, y1 do
				local row = gy * GRID
				for gx = x0, x1 do
					if PointInTriangle( gx + 0.5, gy + 0.5, ax, ay, bx, by, cx, cy ) then
						grid[ row + gx + 1 ] = index
					end
				end
			end
		end
	end

	group.grid = grid
	return grid
end

--- The triangle covering (u, v), or nil.
function M.TriangleAt( group, u, v )
	if not group or not group.tris then return nil end

	-- UVs outside 0..1 are legal and mean the texture tiles, so the lookup
	-- wraps the same way the sampler does.
	u, v = u % 1, v % 1

	local grid = group.grid or BuildGrid( group )

	local gx = math.Clamp( math.floor( u * GRID ), 0, GRID - 1 )
	local gy = math.Clamp( math.floor( v * GRID ), 0, GRID - 1 )

	local index = grid[ gy * GRID + gx + 1 ]
	if index and index > 0 then return group.tris[ index ] end

	-- The grid samples cell centres, so a click inside a triangle thinner than
	-- one cell finds nothing. Falling back to an exact test over the
	-- neighbourhood costs nothing on the rare occasions it happens.
	for oy = -1, 1 do
		for ox = -1, 1 do
			local i = grid[ math.Clamp( gy + oy, 0, GRID - 1 ) * GRID
			              + math.Clamp( gx + ox, 0, GRID - 1 ) + 1 ]

			if i and i > 0 then
				local t = group.tris[ i ]
				if PointInTriangle( u, v, t[ 1 ], t[ 2 ], t[ 3 ], t[ 4 ], t[ 5 ], t[ 6 ] ) then
					return t
				end
			end
		end
	end

	return nil
end

--- Every triangle in the same connected UV piece as `tri`.
function M.Island( model, matpath, slot, tri, mask )
	local group = M.Group( model, matpath, slot, mask )
	if not group or not tri then return { tri } end

	local id = group.island[ tri[ 7 ] ]
	if not id then return { tri } end

	return group.islands[ id ] or { tri }
end

---------------------------------------------------------------------------
-- Framing
---------------------------------------------------------------------------

--- A bounding box over `pts` that ignores geometry sitting on its own a long
--- way from everything else.
---
--- Converted models routinely carry a stray triangle or two assigned to the
--- wrong material - a leftover from a merge, or a face nobody noticed. A plain
--- bounding box over those puts its centre in the empty space between the
--- model and the stray, and a camera framed on it has to pull back far enough
--- to hold both. What that looks like is a small model off to one side of the
--- view, swinging around a point it is not standing on.
---
--- So the box is taken over the points within three standard deviations of the
--- centre of mass. Anything further out is a stray - unless there is enough of
--- it that it is not a stray at all but the shape of the material, in which
--- case the plain box is the honest answer and is used instead.
function M.FramingBounds( pts )
	local n = pts and #pts or 0
	if n == 0 then return nil end

	-- Centre of mass rather than the middle of the box: one stray drags a box
	-- corner the whole way to itself, and drags an average by one part in n.
	local sx, sy, sz = 0, 0, 0

	for i = 1, n do
		local p = pts[ i ]
		sx, sy, sz = sx + p.x, sy + p.y, sz + p.z
	end

	local mid = Vector( sx / n, sy / n, sz / n )

	local total, square = 0, 0

	for i = 1, n do
		local p = pts[ i ]
		local dx, dy, dz = p.x - mid.x, p.y - mid.y, p.z - mid.z
		local d = math.sqrt( dx * dx + dy * dy + dz * dz )

		total  = total + d
		square = square + d * d
	end

	local mean = total / n
	local cut  = mean + 3 * math.sqrt( math.max( square / n - mean * mean, 0 ) )

	local mn, mx, kept = nil, nil, 0

	for i = 1, n do
		local p = pts[ i ]
		local dx, dy, dz = p.x - mid.x, p.y - mid.y, p.z - mid.z

		if dx * dx + dy * dy + dz * dz <= cut * cut then
			kept = kept + 1

			if not mn then
				mn, mx = Vector( p ), Vector( p )
			else
				mn.x = math.min( mn.x, p.x ) mx.x = math.max( mx.x, p.x )
				mn.y = math.min( mn.y, p.y ) mx.y = math.max( mx.y, p.y )
				mn.z = math.min( mn.z, p.z ) mx.z = math.max( mx.z, p.z )
			end
		end
	end

	-- Dropping more than one part in fifty is not dropping strays any more, it
	-- is dropping the material, so the plain box is what is wanted.
	--
	-- With a floor of two triangles' worth, because a proportion on its own
	-- never fires on a small material: on a fifty triangle piece one stray IS
	-- more than a fiftieth, so the trimming would refuse to trim exactly the
	-- case that needs it most - the less material there is, the further one
	-- stray drags the box.
	local allowed = math.max( n * 0.02, 6 )

	if not mn or kept < n - allowed then
		mn, mx = Vector( pts[ 1 ] ), Vector( pts[ 1 ] )

		for i = 2, n do
			local p = pts[ i ]
			mn.x = math.min( mn.x, p.x ) mx.x = math.max( mx.x, p.x )
			mn.y = math.min( mn.y, p.y ) mx.y = math.max( mx.y, p.y )
			mn.z = math.min( mn.z, p.z ) mx.z = math.max( mx.z, p.z )
		end
	end

	return mn, mx
end

---------------------------------------------------------------------------
-- Bodygroups
---------------------------------------------------------------------------

--- The packed bodygroup value for an entity's current parts.
---
--- util.GetModelMeshes wants the single number the engine keeps in m_nBody
--- rather than a list, and nothing hands that number out, so it is packed here
--- the way the engine packs it: each group's chosen option scaled by the
--- product of every earlier group's option count.
---
--- Groups with only one option are still counted. They contribute nothing to
--- the total, but they shift the scale for every group after them, and leaving
--- them out silently addresses the wrong part.
function M.BodyMask( ent )
	if mmdhl and mmdhl.IsMMD and mmdhl.IsMMD( ent ) and mmdhl.GetMaterialVisibilityMask then return mmdhl.GetMaterialVisibilityMask( ent ) end
	if not IsValid( ent ) or not ent.GetNumBodyGroups then return 0 end

	local mask, scale = 0, 1

	for i = 0, ent:GetNumBodyGroups() - 1 do
		local count = math.max( ent:GetBodygroupCount( i ) or 1, 1 )

		mask  = mask + ( ent:GetBodygroup( i ) or 0 ) * scale
		scale = scale * count
	end

	return mask
end

---------------------------------------------------------------------------
-- Skinning
---------------------------------------------------------------------------

--- Source pose-to-bone matrices for a model, keyed by the zero-based bone id.
--- These are the matrices returned in GetModelMeshes' second result; they are
--- already the inverse side of the skinning transform and must not be inverted
--- again.
local bindCache = {}

local function BindMatrices( model )
	local hit = bindCache[ model ]
	if hit ~= nil then return hit or nil end

	local _, binds = util.GetModelMeshes( model )

	if not istable( binds ) then
		bindCache[ model ] = false
		return nil
	end

	local out = {}

	for key, bp in pairs( binds ) do
		local id = tonumber( key )
		if id and istable( bp ) and bp.matrix then
			-- Despite the structure's historical name, GetModelMeshes returns
			-- Source's pose-to-bone matrix: it already takes a bind-pose vertex
			-- into bone-local space. Inverting it sends the point away from the
			-- bone a second time (a face at z=58 reached z=179 on Firefly).
			out[ id ] = bp.matrix
		end
	end

	bindCache[ model ] = out
	return out
end

--- Every vertex of `group` in `ent`'s current world space, three per triangle.
---
--- Linear blend skinning: each vertex is moved by every bone that influences
--- it, weighted, having first been taken out of the bind pose. Falls back to
--- the entity's own transform for models with no usable weights, which covers
--- every static prop.
---
--- Also returns whether it genuinely skinned. Bones do not exist until the
--- model has finished loading, and asking too early does not fail - it falls
--- back to the bind pose, which for a character is a visibly different shape
--- from what is being drawn. A caller that is about to fire rays at this
--- geometry wants to know, and to ask again in a moment.
function M.WorldPositions( ent, group, model )
	if not IsValid( ent ) or not group then return nil, false end
	if mmdhl and mmdhl.GetMaterialPositions then local positions = mmdhl.GetMaterialPositions( ent, group.material ) if positions then return positions, true end end

	local pos = group.pos
	local out = {}

	local weights = group.weights

	-- Bone matrices are not updated every frame for some entities, and are
	-- simply missing until this is called.
	if ent.SetupBones then ent:SetupBones() end

	local bones = ent.GetBoneCount and ent:GetBoneCount() or 0

	-- A single-bone model has nothing to skin, so the entity transform is the
	-- right answer rather than a fallback.
	if not weights or bones <= 1 then
		for i = 1, #pos do out[ i ] = ent:LocalToWorld( pos[ i ] ) end
		return out, true
	end

	local binds = BindMatrices( model or AdvMat.NormalizeModel( ent:GetModel() or "" ) )
	if not binds then
		for i = 1, #pos do out[ i ] = ent:LocalToWorld( pos[ i ] ) end
		return out, false
	end

	local skin  = {}
	local found = 0

	for b = 0, bones - 1 do
		local bind = binds[ b ]
		local live = ent:GetBoneMatrix( b )

		if bind and live then
			skin[ b ] = live * bind
			found = found + 1
		end
	end

	-- Not one bone resolved: the model has not finished loading.
	if found == 0 then
		for i = 1, #pos do out[ i ] = ent:LocalToWorld( pos[ i ] ) end
		return out, false
	end

	for i = 1, #pos do
		local p  = pos[ i ]
		local wt = weights[ i ]
		local acc, total = Vector( 0, 0, 0 ), 0

		if wt then
			for _, bw in ipairs( wt ) do
				local m = skin[ bw.bone ]
				if m then
					acc   = acc + ( m * p ) * bw.weight
					total = total + bw.weight
				end
			end
		end

		if total > 0.001 then
			-- Weights that do not sum to one happen; normalising keeps the
			-- vertex where it belongs instead of dragging it towards origin.
			out[ i ] = acc / total
		else
			out[ i ] = ent:LocalToWorld( p )
		end
	end

	return out, true
end

---------------------------------------------------------------------------
-- Picking in 3D
---------------------------------------------------------------------------
local EPS = 1e-6

--- Moller-Trumbore. There is no ray/triangle test in the util library, so
--- this is the whole of it.
local function RayTriangle( o, d, v0, v1, v2 )
	local e1 = v1 - v0
	local e2 = v2 - v0

	local p   = d:Cross( e2 )
	local det = e1:Dot( p )

	if det > -EPS and det < EPS then return nil end

	local inv = 1 / det
	local t   = o - v0

	local u = t:Dot( p ) * inv
	if u < 0 or u > 1 then return nil end

	local q = t:Cross( e1 )
	local v = d:Dot( q ) * inv
	if v < 0 or u + v > 1 then return nil end

	local dist = e2:Dot( q ) * inv
	if dist < EPS then return nil end

	return dist, u, v
end

M.RayTriangle = RayTriangle

--- The triangle a ray hits first. `world` is what WorldPositions returned, so
--- the caller decides once per frame whether re-skinning is worth it rather
--- than paying for it inside the loop.
function M.Pick( group, world, origin, dir )
	if not group or not world then return nil end

	local best, bestDist, bestU, bestV = nil, math.huge, 0, 0
	local tris = group.tris

	for i = 1, #tris do
		local o = ( i - 1 ) * 3
		local dist, u, v = RayTriangle( origin, dir, world[ o + 1 ], world[ o + 2 ], world[ o + 3 ] )

		if dist and dist < bestDist then
			best, bestDist, bestU, bestV = tris[ i ], dist, u, v
		end
	end

	return best, bestU, bestV, bestDist
end

--- Where a ray crosses the plane through `at` facing `normal`, or nil when it
--- runs along the plane and never meets it.
---
--- Used to drag the model about: the plane is the one the pivot sits on, so
--- the world point under the cursor at the start of a drag is still under it
--- at the end.
function M.RayPlane( origin, dir, at, normal )
	local denom = dir:Dot( normal )
	if denom > -EPS and denom < EPS then return nil end

	return origin + dir * ( ( at - origin ):Dot( normal ) / denom )
end

--- Where on the texture a hit landed, so clicking the model can move the
--- cursor to the matching place on the canvas.
function M.HitUV( tri, u, v )
	if not tri then return nil end

	-- Barycentric coordinates from the ray test interpolate the corners.
	local w = 1 - u - v
	return tri[ 1 ] * w + tri[ 3 ] * u + tri[ 5 ] * v,
	       tri[ 2 ] * w + tri[ 4 ] * u + tri[ 6 ] * v
end

---------------------------------------------------------------------------
-- Drawing a highlight
---------------------------------------------------------------------------
-- "color" is UnlitGeneric with $vertexcolor, $vertexalpha and $translucent
-- already on, which is exactly what a coloured overlay wants and avoids the
-- shading problems VertexLitGeneric has with a hand built mesh.

--- Build an IMesh covering `tris`, using world positions.
--- Returns nil when there is nothing to draw.
function M.BuildHighlight( tris, world )
	if not tris or #tris == 0 or not world then return nil end

	-- One mesh cannot hold more than 65535 vertices, which is 21845 triangles.
	local count = math.min( #tris, 21000 )

	local imesh = Mesh()
	mesh.Begin( imesh, MATERIAL_TRIANGLES, count )

	for i = 1, count do
		local o = ( tris[ i ][ 7 ] - 1 ) * 3

		for k = 1, 3 do
			local p = world[ o + k ]
			if p then
				mesh.Position( p )
				mesh.Color( 255, 255, 255, 255 )
				mesh.TexCoord( 0, 0, 0 )
				mesh.AdvanceVertex()
			else
				-- A degenerate vertex rather than an unbalanced buffer: the
				-- primitive count was already committed to.
				mesh.Position( vector_origin )
				mesh.Color( 0, 0, 0, 0 )
				mesh.TexCoord( 0, 0, 0 )
				mesh.AdvanceVertex()
			end
		end
	end

	mesh.End()
	return imesh
end

local overlayMat

--- Draw a highlight mesh in the current 3D context.
---
--- Depth is compressed rather than offset, so the highlight always wins
--- against the surface it is lying exactly on top of. Both windings are drawn
--- because a highlight has no meaningful facing and half of it disappearing is
--- worse than the cost.
function M.DrawHighlight( imesh, colour )
	if not imesh then return end

	overlayMat = overlayMat or Material( "color" )

	colour = colour or Color( 255, 80, 200, 170 )

	-- A DModelPanel sets these before it draws the model and does not reset
	-- them, so without this the highlight comes out tinted by the panel.
	render.SetColorModulation( colour.r / 255, colour.g / 255, colour.b / 255 )
	render.SetBlend( colour.a / 255 )

	render.SetMaterial( overlayMat )

	cam.IgnoreZ( true )
	render.OverrideDepthEnable( true, false )

	render.CullMode( MATERIAL_CULLMODE_CCW )
	imesh:Draw()
	render.CullMode( MATERIAL_CULLMODE_CW )
	imesh:Draw()
	render.CullMode( MATERIAL_CULLMODE_CCW )

	render.OverrideDepthEnable( false, false )
	cam.IgnoreZ( false )

	render.SetColorModulation( 1, 1, 1 )
	render.SetBlend( 1 )
end

---------------------------------------------------------------------------
-- Rays inside a DModelPanel
---------------------------------------------------------------------------

--- The world ray through one point of a DModelPanel, in panel coordinates.
---
--- gui.ScreenToVector is no use here: it reads the player's own view and knows
--- nothing about the camera the panel set up. util.AimVector is the same thing
--- against an arbitrary camera, which is exactly this case.
function M.PanelRayAt( panel, mx, my )
	if not IsValid( panel ) then return nil end

	local w, h = panel:GetWide(), panel:GetTall()
	if w <= 0 or h <= 0 then return nil end

	local camPos = panel:GetCamPos()
	local ang    = panel.GetLookAng and panel:GetLookAng()

	if not ang then
		ang = ( panel:GetLookAt() - camPos ):Angle()
	end

	local dir = util.AimVector( ang, panel:GetFOV(), mx, my, w, h )
	if not dir then return nil end

	return camPos, dir
end

--- The world ray under the cursor of a DModelPanel.
function M.PanelRay( panel )
	if not IsValid( panel ) then return nil end

	local w, h = panel:GetWide(), panel:GetTall()
	if w <= 0 or h <= 0 then return nil end

	local mx, my = panel:CursorPos()

	-- Off the panel is not a miss to be worked out later; there is nothing
	-- under the cursor to fire a ray at.
	if mx < 0 or my < 0 or mx > w or my > h then return nil end

	return M.PanelRayAt( panel, mx, my )
end
