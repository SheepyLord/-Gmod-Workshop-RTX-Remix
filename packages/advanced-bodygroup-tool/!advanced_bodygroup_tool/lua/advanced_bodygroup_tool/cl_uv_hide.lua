-- Per-bodygroup UV alpha masks. This is intentionally clientside: procedural
-- materials and render targets must be created independently on every client.

if not CLIENT then return end

local ABT = AdvancedBodygroupTool
local BODYGROUP_DIGITS = "0123456789abcdefghijklmnopqrstuvwxyz"
local MAX_SUBMATERIALS = 32
local MODEL_STRUCT_SIZE = 148
local DAMAGE_RT_FLAGS = 8960 -- NOMIP | NOLOD | EIGHTBITALPHA
local ZERO_ANGLE = Angle( 0, 0, 0 )
local VTF_ALPHA_FLAGS = 0x3000
local VTF_ALPHA_FORMATS = {
	[ 0 ] = true, [ 1 ] = true, [ 6 ] = true, [ 8 ] = true,
	[ 11 ] = true, [ 12 ] = true, [ 14 ] = true, [ 15 ] = true,
	[ 19 ] = true, [ 20 ] = true, [ 21 ] = true,
	[ 24 ] = true, [ 25 ] = true, [ 29 ] = true,
}
local INTERNAL_MATERIAL_KEYS = {
	[ "$flags" ] = true, [ "$flags_defined" ] = true,
	[ "$flags2" ] = true, [ "$flags_defined2" ] = true,
	[ "$flagsdefined" ] = true, [ "$flagsdefined2" ] = true,
}
local REGION_HIGHLIGHT_MATERIAL = CreateMaterial(
	"abt_region_hover_highlight_clean_v2", "UnlitGeneric", {
		[ "$basetexture" ] = "vgui/white",
		[ "$vertexcolor" ] = "1", [ "$vertexalpha" ] = "1",
		[ "$translucent" ] = "1", [ "$nocull" ] = "1",
	} )
local REGION_ARROW_MATERIAL = CreateMaterial(
	"abt_region_hover_arrow_transparent_v4", "UnlitGeneric", {
		[ "$basetexture" ] = "vgui/white",
		[ "$vertexcolor" ] = "1", [ "$vertexalpha" ] = "1",
		[ "$translucent" ] = "1", [ "$nocull" ] = "1",
	} )

ABT.ClientStates = ABT.ClientStates or setmetatable( {}, { __mode = "k" } )
ABT.ModelLayoutCache = ABT.ModelLayoutCache or {}
ABT.SourceMaterialCache = ABT.SourceMaterialCache or {}
ABT.VTFMetadataCache = ABT.VTFMetadataCache or {}
ABT.MaterialTemplateCache = {}
ABT.RegionAnalysisCache = {}
-- Variant entries are cheap identity lookups and intentionally start clean on
-- auto-refresh. Render targets live in the bounded per-entity pool instead.
ABT.ResourceVariantCache = setmetatable( {}, { __mode = "k" } )
ABT.ResourcePools = ABT.ResourcePools
	or setmetatable( {}, { __mode = "k" } )
ABT.MaterialSerial = ABT.MaterialSerial or 0
ABT.HoveredRegion = nil

-- RenderOverride closures survive auto-refresh. Restore callbacks owned by the
-- previous copy before installing this format.
for entity, state in pairs( ABT.ClientStates ) do
	if IsValid( entity ) and state.renderOverride then
		if entity.RenderOverride == state.renderOverride then
			entity.RenderOverride = state.previousRenderOverride
		else
			local bbs = _G.BBS
			local bbsState = istable( bbs ) and istable( bbs.DamageStates )
				and bbs.DamageStates[ entity ] or nil
			if istable( bbsState )
			and entity.RenderOverride == bbsState.rtxRenderOverride
			and bbsState.previousRenderOverride == state.renderOverride then
				-- BBS currently wraps this old ABT closure. Splice it out while
				-- preserving the third-party callback that ABT originally wrapped.
				bbsState.previousRenderOverride = state.previousRenderOverride
			end
		end
	end
end
ABT.ClientStates = setmetatable( {}, { __mode = "k" } )

local function NormalizeMaterialPath( path )
	path = string.lower( string.Trim( tostring( path or "" ) ) )
	path = string.Replace( path, "\\", "/" )
	path = string.gsub( path, "^materials/", "" )
	return string.gsub( path, "%.vmt$", "" )
end

local function ReadLongAt( handle, offset )
	if not handle or offset < 0 then return nil end
	handle:Seek( offset )
	return handle:ReadLong()
end

local function ReadModelLayout( model )
	model = string.lower( tostring( model or "" ) )
	local cached = ABT.ModelLayoutCache[ model ]
	if cached ~= nil then return cached or nil, cached == false and "cached failure" or nil end
	local handle = file.Open( model, "rb", "GAME" )
	if not handle then
		ABT.ModelLayoutCache[ model ] = false
		return nil, "model file is not readable"
	end

	local ok, result, errorMessage = pcall( function()
		handle:Seek( 0 )
		if handle:Read( 4 ) ~= "IDST" then return nil, "not a Source studio model" end
		local version = ReadLongAt( handle, 4 )
		local fileLength = ReadLongAt( handle, 76 ) or handle:Size()
		local bodypartCount = ReadLongAt( handle, 232 )
		local bodypartOffset = ReadLongAt( handle, 236 )
		if not version or version < 44 or version > 60 then
			return nil, "unsupported studio model version " .. tostring( version )
		end
		if not bodypartCount or bodypartCount < 0 or bodypartCount > 256
		or not bodypartOffset or bodypartOffset < 0
		or bodypartOffset >= fileLength then
			return nil, "invalid bodypart table"
		end

		local layout = { version = version, groups = {}, count = bodypartCount }
		for id = 0, bodypartCount - 1 do
			local bodypart = bodypartOffset + id * 16
			local optionCount = ReadLongAt( handle, bodypart + 4 )
			local modelOffset = ReadLongAt( handle, bodypart + 12 )
			if not optionCount or optionCount < 0 or optionCount > 256
			or not modelOffset or bodypart + modelOffset >= fileLength then
				return nil, "invalid bodypart " .. id
			end
			local group = { options = {}, count = optionCount }
			for option = 0, optionCount - 1 do
				local studioModel = bodypart + modelOffset + option * MODEL_STRUCT_SIZE
				local meshCount = ReadLongAt( handle, studioModel + 72 )
				if not meshCount or meshCount < 0 or meshCount > 4096 then
					return nil, "invalid mesh count in bodypart " .. id
				end
				group.options[ option ] = meshCount
			end
			layout.groups[ id ] = group
		end
		return layout
	end )
	handle:Close()
	if not ok then
		ABT.ModelLayoutCache[ model ] = false
		return nil, tostring( result )
	end
	if not result then
		ABT.ModelLayoutCache[ model ] = false
		return nil, errorMessage
	end
	ABT.ModelLayoutCache[ model ] = result
	return result
end

local function EncodeBodygroupOption( value )
	value = math.Clamp( math.floor( tonumber( value ) or 0 ), 0,
		#BODYGROUP_DIGITS - 1 )
	return string.sub( BODYGROUP_DIGITS, value + 1, value + 1 )
end

local function BodygroupSelection( entity )
	local values = {}
	local maximumId = -1
	for rawKey, group in pairs( entity:GetBodyGroups() or {} ) do
		if istable( group ) then
			local id = tonumber( group.id ) or tonumber( rawKey )
			if id and id >= 0 and id <= 255 and id == math.floor( id ) then
				maximumId = math.max( maximumId, id )
				values[ id + 1 ] = EncodeBodygroupOption( entity:GetBodygroup( id ) )
			end
		end
	end
	for index = 1, maximumId + 1 do values[ index ] = values[ index ] or "0" end
	local selection = table.concat( values )
	return selection ~= "" and selection or 0, selection ~= "" and selection or "0"
end

local function HiddenIdentity( entity )
	local model = entity:GetModel() or ""
	local _, selection = BodygroupSelection( entity )
	local parts = {
		model,
		selection,
		tostring( entity:GetSkin() or 0 ),
		entity:GetNW2String( ABT.HiddenNWKey, "" ),
		ABT.GetHiddenRegionEncoding( entity ),
		ABT.GetVertexKeepEncoding( entity ),
	}
	for index = 0, math.min( #( entity:GetMaterials() or {} ) - 1,
		MAX_SUBMATERIALS - 1 ) do
		parts[ #parts + 1 ] = entity:GetSubMaterial( index ) or ""
	end
	return table.concat( parts, "|" )
end

local function MeshGroupMap( entity, layout, meshCount )
	local result = {}
	local cursor = 1
	for id = 0, layout.count - 1 do
		local group = layout.groups[ id ]
		local option = math.Clamp( entity:GetBodygroup( id ) or 0,
			0, math.max( group.count - 1, 0 ) )
		local count = group.options[ option ] or 0
		for _ = 1, count do
			result[ cursor ] = id
			cursor = cursor + 1
		end
	end
	if cursor - 1 ~= meshCount then
		return nil, string.format(
			"studio mesh count mismatch (MDL=%d, util.GetModelMeshes=%d)",
			cursor - 1, meshCount )
	end
	return result
end

local function QuantizedPositionKey( position )
	if not isvector( position ) then return nil end
	local function quantize( value )
		if value >= 0 then return math.floor( value * 1000 + 0.5 ) end
		return math.ceil( value * 1000 - 0.5 )
	end
	return quantize( position.x ) .. "," .. quantize( position.y )
		.. "," .. quantize( position.z )
end

local function TriangleEdgeKey( first, second )
	if not first or not second or first == second then return nil end
	if first < second then return first .. ">" .. second end
	return second .. ">" .. first
end

local function SkinVertexKey( vertex )
	local position = vertex and vertex.pos
	if not isvector( position ) then return nil end
	local parts = { string.format( "%.9g,%.9g,%.9g",
		position.x, position.y, position.z ) }
	local weights = vertex.weights
	if not weights or #weights == 0 then
		parts[ 2 ] = "0:1"
	else
		for index, boneWeight in ipairs( weights ) do
			parts[ index + 1 ] = string.format( "%d:%.9g",
				boneWeight.bone or 0, boneWeight.weight or 0 )
		end
	end
	return table.concat( parts, "|" )
end

local function GetOrCreateSkinVertex( lookup, vertex )
	local key = SkinVertexKey( vertex )
	if not key then return nil end
	local cached = lookup[ key ]
	if cached then return cached end
	cached = { position = vertex.pos, weights = vertex.weights }
	lookup[ key ] = cached
	return cached
end

local function CreateRegionPreview( triangles )
	local function component( position, axis )
		if axis == "x" then return position.x end
		if axis == "y" then return position.y end
		return position.z
	end
	local minimum = { x = math.huge, y = math.huge, z = math.huge }
	local maximum = { x = -math.huge, y = -math.huge, z = -math.huge }
	for _, triangle in ipairs( triangles ) do
		for _, position in ipairs( triangle.positions or {} ) do
			minimum.x, maximum.x = math.min( minimum.x, position.x ),
				math.max( maximum.x, position.x )
			minimum.y, maximum.y = math.min( minimum.y, position.y ),
				math.max( maximum.y, position.y )
			minimum.z, maximum.z = math.min( minimum.z, position.z ),
				math.max( maximum.z, position.z )
		end
	end
	if minimum.x == math.huge then return {} end
	local ranges = {
		x = maximum.x - minimum.x,
		y = maximum.y - minimum.y,
		z = maximum.z - minimum.z,
	}
	local horizontal = ranges.x >= ranges.y and "x" or "y"
	local vertical = "z"
	if ranges.z < math.min( ranges.x, ranges.y ) * 0.2 then
		horizontal, vertical = "x", "y"
	end
	local width = math.max( ranges[ horizontal ], 0.001 )
	local height = math.max( ranges[ vertical ], 0.001 )
	local preview = {}
	local stride = math.max( math.ceil( #triangles / 192 ), 1 )
	for index = 1, #triangles, stride do
		local triangle = triangles[ index ]
		if triangle.positions and #triangle.positions == 3 then
			local polygon = {}
			for vertexIndex, position in ipairs( triangle.positions ) do
				local uv = triangle.uv and triangle.uv[ vertexIndex ]
				polygon[ #polygon + 1 ] = {
					x = ( component( position, horizontal )
						- minimum[ horizontal ] ) / width,
					y = 1 - ( component( position, vertical )
						- minimum[ vertical ] ) / height,
					u = uv and uv.u or 0,
					v = uv and uv.v or 0,
				}
			end
			preview[ #preview + 1 ] = polygon
		end
	end
	return preview
end

local function DiscoverMeshRegions( meshData, meshIndex, groupId, firstRegionId )
	local records = {}
	local skinVertexLookup = {}
	local vertices = meshData.triangles or {}
	for index = 1, #vertices - 2, 3 do
		local first, second, third = vertices[ index ],
			vertices[ index + 1 ], vertices[ index + 2 ]
		if isnumber( first.u ) and isnumber( first.v )
		and isnumber( second.u ) and isnumber( second.v )
		and isnumber( third.u ) and isnumber( third.v ) then
			records[ #records + 1 ] = {
				uv = {
					{ u = first.u, v = first.v },
					{ u = second.u, v = second.v },
					{ u = third.u, v = third.v },
				},
				positions = { first.pos, second.pos, third.pos },
				vertices = {
					GetOrCreateSkinVertex( skinVertexLookup, first ),
					GetOrCreateSkinVertex( skinVertexLookup, second ),
					GetOrCreateSkinVertex( skinVertexLookup, third ),
				},
				material = meshData.material,
				meshIndex = meshIndex,
				group = groupId,
			}
		end
	end
	if #records == 0 then return {}, {}, firstRegionId end

	local parent = {}
	for index = 1, #records do parent[ index ] = index end
	local function find( index )
		local root = index
		while parent[ root ] ~= root do root = parent[ root ] end
		while parent[ index ] ~= index do
			local nextIndex = parent[ index ]
			parent[ index ] = root
			index = nextIndex
		end
		return root
	end
	local function union( first, second )
		first, second = find( first ), find( second )
		if first ~= second then parent[ second ] = first end
	end
	local edgeOwners = {}
	for index, triangle in ipairs( records ) do
		local keys = {}
		for vertex = 1, 3 do
			keys[ vertex ] = QuantizedPositionKey( triangle.positions[ vertex ] )
		end
		if not keys[ 1 ] or not keys[ 2 ] or not keys[ 3 ] then
			union( 1, index )
		else
			for edge = 1, 3 do
				local edgeKey = TriangleEdgeKey( keys[ edge ], keys[ edge % 3 + 1 ] )
				if edgeKey then
					if edgeOwners[ edgeKey ] then union( index, edgeOwners[ edgeKey ] )
					else edgeOwners[ edgeKey ] = index end
				end
			end
		end
	end

	local components = {}
	for index, triangle in ipairs( records ) do
		local root = find( index )
		local component = components[ root ]
		if not component then
			component = { firstTriangle = index, triangles = {} }
			components[ root ] = component
		end
		component.triangles[ #component.triangles + 1 ] = triangle
	end
	local ordered = {}
	for _, component in pairs( components ) do ordered[ #ordered + 1 ] = component end
	table.sort( ordered, function( left, right )
		return left.firstTriangle < right.firstTriangle
	end )
	local regions, triangles = {}, {}
	local nextRegionId = firstRegionId
	for _, component in ipairs( ordered ) do
		local region = {
			id = nextRegionId,
			group = groupId,
			meshIndex = meshIndex,
			material = meshData.material,
			triangleCount = #component.triangles,
			preview = CreateRegionPreview( component.triangles ),
			triangles = component.triangles,
		}
		regions[ #regions + 1 ] = region
		for _, triangle in ipairs( component.triangles ) do
			triangle.region = nextRegionId
			triangles[ #triangles + 1 ] = triangle
		end
		nextRegionId = nextRegionId + 1
	end
	return regions, triangles, nextRegionId
end

local function RegionAnalysisIdentity( entity )
	local _, selection = BodygroupSelection( entity )
	return string.lower( tostring( entity:GetModel() or "" ) ) .. "|"
		.. selection .. "|" .. tostring( entity:GetSkin() or 0 )
end

local function GetRegionAnalysis( entity )
	if not IsValid( entity ) then return nil, "entity is invalid" end
	local identity = RegionAnalysisIdentity( entity )
	local cached = ABT.RegionAnalysisCache[ identity ]
	if cached then return cached end
	local layout, layoutError = ReadModelLayout( entity:GetModel() )
	if not layout then return nil, layoutError end
	local selection = BodygroupSelection( entity )
	local ok, meshes, bindPoses = pcall( util.GetModelMeshes,
		entity:GetModel(), 0, selection, entity:GetSkin() or 0 )
	if not ok or not meshes or #meshes == 0 then
		return nil, ok and "util.GetModelMeshes returned no meshes" or tostring( meshes )
	end
	local meshGroups, mapError = MeshGroupMap( entity, layout, #meshes )
	if not meshGroups then return nil, mapError end
	local analysis = {
		identity = identity, groups = {}, triangles = {}, poseToBone = {},
	}
	for boneId, bindPose in pairs( bindPoses or {} ) do
		local matrix = istable( bindPose ) and bindPose.matrix or bindPose
		if TypeID( matrix ) == TYPE_MATRIX then
			analysis.poseToBone[ tonumber( boneId ) or boneId ] = matrix
		end
	end
	local nextRegionIds = {}
	for meshIndex, meshData in ipairs( meshes ) do
		local group = meshGroups[ meshIndex ]
		local regions, triangles, nextRegionId = DiscoverMeshRegions(
			meshData, meshIndex, group, nextRegionIds[ group ] or 1 )
		nextRegionIds[ group ] = nextRegionId
		analysis.groups[ group ] = analysis.groups[ group ] or {}
		table.Add( analysis.groups[ group ], regions )
		table.Add( analysis.triangles, triangles )
	end
	ABT.RegionAnalysisCache[ identity ] = analysis
	return analysis
end

function ABT.GetBodygroupRegions( entity, group )
	group = math.floor( tonumber( group ) or -1 )
	local analysis, errorMessage = GetRegionAnalysis( entity )
	if not analysis then return nil, errorMessage end
	return analysis.groups[ group ] or {}
end

function ABT.GetBodygroupVertexData( entity, group )
	group = math.floor( tonumber( group ) or -1 )
	local analysis, errorMessage = GetRegionAnalysis( entity )
	if not analysis then return nil, errorMessage end
	local triangles = {}
	local minimum, maximum
	for _, triangle in ipairs( analysis.triangles or {} ) do
		if triangle.group == group then
			triangles[ #triangles + 1 ] = triangle
			for _, position in ipairs( triangle.positions or {} ) do
				if isvector( position ) then
					if not minimum then
						minimum = Vector( position.x, position.y, position.z )
						maximum = Vector( position.x, position.y, position.z )
					else
						minimum.x = math.min( minimum.x, position.x )
						minimum.y = math.min( minimum.y, position.y )
						minimum.z = math.min( minimum.z, position.z )
						maximum.x = math.max( maximum.x, position.x )
						maximum.y = math.max( maximum.y, position.y )
						maximum.z = math.max( maximum.z, position.z )
					end
				end
			end
		end
	end
	if #triangles == 0 or not minimum then
		return nil, "bodygroup has no drawable triangles"
	end
	return {
		identity = analysis.identity,
		group = group,
		triangles = triangles,
		minimum = minimum,
		maximum = maximum,
	}
end

local function SafePlaneNumber( value )
	value = tonumber( value )
	if not value or value ~= value or math.abs( value ) > 1000000 then return nil end
	return value
end

function ABT.CompileVertexKeepCuts( bounds )
	if not istable( bounds ) or not istable( bounds.cuts ) then return nil end
	local compiled = {}
	for _, cut in ipairs( bounds.cuts ) do
		if istable( cut ) and cut.enabled ~= false then
			local ox = SafePlaneNumber( cut.ox )
			local oy = SafePlaneNumber( cut.oy )
			local oz = SafePlaneNumber( cut.oz )
			local pitch = SafePlaneNumber( cut.pitch )
			local yaw = SafePlaneNumber( cut.yaw )
			local roll = SafePlaneNumber( cut.roll )
			if ox and oy and oz and pitch and yaw and roll then
				local normal = Angle( pitch, yaw, roll ):Forward()
				compiled[ #compiled + 1 ] = {
					ox = ox,
					oy = oy,
					oz = oz,
					nx = normal.x,
					ny = normal.y,
					nz = normal.z,
					keep_positive = cut.keep_positive ~= false,
				}
			end
		end
	end
	return compiled
end

function ABT.TrianglePassesVertexKeepBounds( triangle, bounds, compiledCuts )
	if not istable( bounds ) then return true end
	local positions = triangle and triangle.positions
	if not istable( positions ) or #positions ~= 3 then return true end
	if istable( bounds.cuts ) then
		-- Enabled planes form an intersection: a triangle is retained only when
		-- all three of its vertices lie on the kept side of every active plane.
		compiledCuts = istable( compiledCuts ) and compiledCuts
			or ABT.CompileVertexKeepCuts( bounds ) or {}
		for _, cut in ipairs( compiledCuts ) do
			for _, position in ipairs( positions ) do
				if not isvector( position ) then return true end
				local distance = ( position.x - cut.ox ) * cut.nx
					+ ( position.y - cut.oy ) * cut.ny
					+ ( position.z - cut.oz ) * cut.nz
				if cut.keep_positive then
					if distance < -0.0001 then return false end
				elseif distance > 0.0001 then
					return false
				end
			end
		end
		return true
	end
	-- Legacy version 5 axis-aligned keep bounds.
	for _, position in ipairs( positions ) do
		if not isvector( position ) then return true end
		if bounds.xmin_on and position.x < ( tonumber( bounds.xmin ) or 0 ) then return false end
		if bounds.xmax_on and position.x > ( tonumber( bounds.xmax ) or 0 ) then return false end
		if bounds.ymin_on and position.y < ( tonumber( bounds.ymin ) or 0 ) then return false end
		if bounds.ymax_on and position.y > ( tonumber( bounds.ymax ) or 0 ) then return false end
		if bounds.zmin_on and position.z < ( tonumber( bounds.zmin ) or 0 ) then return false end
		if bounds.zmax_on and position.z > ( tonumber( bounds.zmax ) or 0 ) then return false end
	end
	return true
end

function ABT.SetHoveredRegion( entity, group, regionId )
	if not IsValid( entity ) then ABT.HoveredRegion = nil return false end
	group = math.floor( tonumber( group ) or -1 )
	regionId = math.floor( tonumber( regionId ) or -1 )
	local current = ABT.HoveredRegion
	if current and current.entity == entity and current.group == group
	and current.regionId == regionId
	and current.analysisIdentity == RegionAnalysisIdentity( entity ) then
		return true
	end
	local analysis, errorMessage = GetRegionAnalysis( entity )
	if not analysis then ABT.HoveredRegion = nil return false, errorMessage end
	for _, region in ipairs( analysis.groups[ group ] or {} ) do
		if region.id == regionId then
			ABT.HoveredRegion = {
				entity = entity,
				group = group,
				regionId = regionId,
				region = region,
				analysis = analysis,
				analysisIdentity = analysis.identity,
			}
			return true
		end
	end
	ABT.HoveredRegion = nil
	return false, "region is unavailable"
end

function ABT.ClearHoveredRegion( entity, group, regionId )
	local current = ABT.HoveredRegion
	if not current then return end
	if entity and current.entity ~= entity then return end
	if group ~= nil and current.group ~= group then return end
	if regionId ~= nil and current.regionId ~= regionId then return end
	ABT.HoveredRegion = nil
end

local function HoverBelongsToActiveTool( hover )
	local player = LocalPlayer()
	if not IsValid( player ) then return false end
	local weapon = player:GetActiveWeapon()
	if not IsValid( weapon ) or weapon:GetClass() ~= "gmod_tool"
	or weapon:GetMode() ~= "advanced_bodygroup" then return false end
	local tool = weapon:GetToolObject( "advanced_bodygroup" )
	return tool and tool:GetSelectedEntity() == hover.entity
end

local function BuildHoverSkinTransforms( entity, analysis )
	entity:SetupBones()
	local transforms = {
		fallbackOrigin = entity:GetPos(),
		fallbackAngles = entity:GetAngles(),
	}
	for boneId, poseToBone in pairs( analysis.poseToBone or {} ) do
		local current = entity:GetBoneMatrix( boneId )
		if current then transforms[ boneId ] = current * poseToBone end
	end
	return transforms
end

local function SkinHoverVertex( transforms, vertex, cache )
	if not vertex then return nil end
	local cached = cache[ vertex ]
	if cached ~= nil then return cached ~= false and cached or nil end
	local position = vertex.position
	if not isvector( position ) then cache[ vertex ] = false return nil end
	local weights = vertex.weights
	local result
	if not weights or #weights == 0 then
		local root = transforms[ 0 ]
		result = root and ( root * position ) or LocalToWorld( position,
			ZERO_ANGLE, transforms.fallbackOrigin, transforms.fallbackAngles )
	elseif #weights == 1 then
		local transform = transforms[ weights[ 1 ].bone or 0 ]
		result = transform and ( transform * position ) or nil
	else
		local x, y, z, totalWeight = 0, 0, 0, 0
		for _, boneWeight in ipairs( weights ) do
			local weight = boneWeight.weight or 0
			local transform = transforms[ boneWeight.bone or 0 ]
			if transform and weight > 0 then
				local transformed = transform * position
				x = x + transformed.x * weight
				y = y + transformed.y * weight
				z = z + transformed.z * weight
				totalWeight = totalWeight + weight
			end
		end
		if totalWeight > 0 then
			if totalWeight < 0.999 then
				x, y, z = x / totalWeight, y / totalWeight, z / totalWeight
			end
			result = Vector( x, y, z )
		end
	end
	if not result then
		result = LocalToWorld( position, ZERO_ANGLE,
			transforms.fallbackOrigin, transforms.fallbackAngles )
	end
	cache[ vertex ] = result or false
	return result
end

local function BuildHoveredWorldTriangles( hover )
	local transforms = BuildHoverSkinTransforms( hover.entity, hover.analysis )
	local posedCache, triangles = {}, {}
	for _, triangle in ipairs( hover.region.triangles or {} ) do
		local first = SkinHoverVertex( transforms, triangle.vertices[ 1 ], posedCache )
		local second = SkinHoverVertex( transforms, triangle.vertices[ 2 ], posedCache )
		local third = SkinHoverVertex( transforms, triangle.vertices[ 3 ], posedCache )
		if first and second and third then
			triangles[ #triangles + 1 ] = { first, second, third }
		end
	end
	if #triangles == 0 then return nil end
	local center, count = Vector( 0, 0, 0 ), 0
	for _, position in pairs( posedCache ) do
		if isvector( position ) then center, count = center + position, count + 1 end
	end
	if count == 0 then return nil end
	return triangles, center / count
end

local function DrawHoveredTriangles( triangles, color )
	local batchSize = 1024
	render.SetMaterial( REGION_HIGHLIGHT_MATERIAL )
	for firstTriangle = 1, #triangles, batchSize do
		local count = math.min( batchSize, #triangles - firstTriangle + 1 )
		mesh.Begin( MATERIAL_TRIANGLES, count )
		for index = firstTriangle, firstTriangle + count - 1 do
			for _, position in ipairs( triangles[ index ] ) do
				mesh.Position( position )
				mesh.TexCoord( 0, 0, 0 )
				mesh.Color( color.r, color.g, color.b, color.a )
				mesh.AdvanceVertex()
			end
		end
		mesh.End()
	end
end

local function DrawHoveredTriangleEdges( triangles, color )
	local stride = math.max( math.ceil( #triangles / 800 ), 1 )
	for index = 1, #triangles, stride do
		local triangle = triangles[ index ]
		render.DrawLine( triangle[ 1 ], triangle[ 2 ], color, true )
		render.DrawLine( triangle[ 2 ], triangle[ 3 ], color, true )
		render.DrawLine( triangle[ 3 ], triangle[ 1 ], color, true )
	end
end

local function DrawRegionArrow( entity, target, beamColor, coneColor )
	local towardViewer = EyePos() - target
	if towardViewer:LengthSqr() < 0.001 then towardViewer = entity:GetForward() end
	towardViewer:Normalize()
	local distance = math.Clamp( ( entity:BoundingRadius() or 32 ) * 0.18, 16, 34 )
	local tip = target + towardViewer * 1.5
	local start = target + towardViewer * distance
	local direction = tip - start
	direction:Normalize()
	local base = tip - direction * 5.5
	local right = direction:Cross( Vector( 0, 0, 1 ) )
	if right:LengthSqr() < 0.001 then right = direction:Cross( Vector( 0, 1, 0 ) ) end
	right:Normalize()
	local up = right:Cross( direction )
	up:Normalize()
	local ring = {}
	for index = 0, 5 do
		local radians = math.rad( index * 60 )
		ring[ #ring + 1 ] = base + right * math.cos( radians ) * 1.8
			+ up * math.sin( radians ) * 1.8
	end
	render.SetMaterial( REGION_ARROW_MATERIAL )
	render.DrawBeam( start, base, 1.2, 0, 1, beamColor )
	-- Keep the camera-facing rear of the cone open. A filled cap becomes an
	-- opaque-looking hexagon when the arrow points directly away from the viewer.
	mesh.Begin( MATERIAL_TRIANGLES, #ring )
	for index, point in ipairs( ring ) do
		local nextPoint = ring[ index % #ring + 1 ]
		for _, position in ipairs( { point, nextPoint, tip } ) do
			mesh.Position( position )
			mesh.TexCoord( 0, 0, 0 )
			mesh.Color( coneColor.r, coneColor.g, coneColor.b, coneColor.a )
			mesh.AdvanceVertex()
		end
	end
	mesh.End()
end

local nextHoverRenderError = 0
hook.Add( "PostDrawTranslucentRenderables",
	"AdvancedBodygroupTool.RegionHoverWorld", function( drawingDepth, drawingSkybox )
		if drawingDepth or drawingSkybox then return end
		local hover = ABT.HoveredRegion
		if not hover or not IsValid( hover.entity )
		or not HoverBelongsToActiveTool( hover ) then return end
		if hover.analysisIdentity ~= RegionAnalysisIdentity( hover.entity ) then
			ABT.HoveredRegion = nil
			return
		end
		local ok, errorMessage = pcall( function()
			local triangles, center = BuildHoveredWorldTriangles( hover )
			if not triangles then return end
			local pulse = ( math.sin( RealTime() * 4 ) + 1 ) * 0.5
			local highlight = Color( 255, 55, 185, 130 + pulse * 35 )
			local ghost = Color( 255, 55, 185, 24 + pulse * 12 )
			local edge = Color( 255, 225, 245, 230 )
			local arrowBeam = Color( 55, 210, 255, 175 )
			local arrowCone = Color( 55, 210, 255, 50 )
			render.OverrideBlend( true,
				BLEND_SRC_ALPHA, BLEND_ONE_MINUS_SRC_ALPHA, BLENDFUNC_ADD )
			cam.IgnoreZ( true )
			DrawHoveredTriangles( triangles, ghost )
			cam.IgnoreZ( false )
			render.DepthRange( 0, 0.995 )
			DrawHoveredTriangles( triangles, highlight )
			DrawHoveredTriangleEdges( triangles, edge )
			render.DepthRange( 0, 1 )
			cam.IgnoreZ( true )
			DrawRegionArrow( hover.entity, center, arrowBeam, arrowCone )
		end )
		render.OverrideBlend( false )
		render.DepthRange( 0, 1 )
		cam.IgnoreZ( false )
		if not ok and RealTime() >= nextHoverRenderError then
			nextHoverRenderError = RealTime() + 5
			ErrorNoHalt( "[Advanced Bodygroup Tool] region hover preview failed: "
				.. tostring( errorMessage ) .. "\n" )
		end
	end )

local function FindSubmaterialIndexes( entity, meshMaterial )
	local materials = entity:GetMaterials() or {}
	local target = NormalizeMaterialPath( meshMaterial )
	local result = {}
	for index, path in ipairs( materials ) do
		if NormalizeMaterialPath( path ) == target then result[ #result + 1 ] = index - 1 end
	end
	if #result > 0 then return result end
	for index, path in ipairs( materials ) do
		local normalized = NormalizeMaterialPath( path )
		if normalized ~= "" and target ~= ""
		and ( string.EndsWith( normalized, target )
		or string.EndsWith( target, normalized ) ) then
			return { index - 1 }
		end
	end
	if #materials == 1 then return { 0 } end
	return {}
end

local MAX_VMT_INCLUDE_DEPTH = 4

-- IMaterial:GetKeyValues() is lossy: authored flags such as $alphatest can be
-- represented only inside $flags. Read the mounted VMT text first so source
-- alpha intent and author-supplied parameter strings survive the clone.
local function TokenizeVMT( source )
	local tokens = {}
	local index = 1
	while index <= #source do
		local character = string.sub( source, index, index )
		if character == '"' then
			local close = string.find( source, '"', index + 1, true )
			if not close then break end
			tokens[ #tokens + 1 ] = string.sub( source, index + 1, close - 1 )
			index = close + 1
		elseif character == "/"
		and string.sub( source, index + 1, index + 1 ) == "/" then
			local newline = string.find( source, "\n", index, true )
			index = newline and newline + 1 or #source + 1
		elseif character == "{" or character == "}" then
			tokens[ #tokens + 1 ] = character
			index = index + 1
		elseif character == "[" then
			local close = string.find( source, "]", index, true )
			if not close then break end
			local bracketed = string.sub( source, index, close )
			if string.find( bracketed, "^%[%s*[-%d%.]" ) then
				tokens[ #tokens + 1 ] = bracketed
			end
			index = close + 1
		elseif string.find( character, "%s" ) then
			index = index + 1
		else
			local stop = string.find( source, "[%s{}\"]", index ) or #source + 1
			tokens[ #tokens + 1 ] = string.sub( source, index, stop - 1 )
			index = stop
		end
	end
	return tokens
end

local function ParseVMTBlock( tokens, index )
	local output = {}
	index = index + 1
	while index <= #tokens do
		local key = tokens[ index ]
		if key == "}" then return output, index + 1 end
		local nextToken = tokens[ index + 1 ]
		if not nextToken then return output, index + 1 end
		key = string.lower( key )
		if nextToken == "{" then
			local child
			child, index = ParseVMTBlock( tokens, index + 1 )
			output[ key ] = child
		else
			output[ key ] = nextToken
			index = index + 2
		end
	end
	return output, index
end

local function MergeVMTParameters( destination, source, onlyMissing )
	for key, value in pairs( source or {} ) do
		if not onlyMissing or destination[ key ] == nil then
			if istable( value ) then
				destination[ key ] = destination[ key ] or {}
				MergeVMTParameters( destination[ key ], value, onlyMissing )
			else
				destination[ key ] = value
			end
		end
	end
	return destination
end

local ReadMaterialVMT
ReadMaterialVMT = function( path, depth )
	depth = depth or 0
	path = NormalizeMaterialPath( path )
	if path == "" or depth > MAX_VMT_INCLUDE_DEPTH then return nil end
	if depth == 0 then
		local cached = ABT.MaterialTemplateCache[ path ]
		if cached then return table.Copy( cached.parameters ), cached.shader end
	end
	local source = file.Read( "materials/" .. path .. ".vmt", "GAME" )
	if not source or source == "" then return nil end
	local tokens = TokenizeVMT( source )
	local opening = 1
	while opening <= #tokens and tokens[ opening ] ~= "{" do opening = opening + 1 end
	if opening < 2 or tokens[ opening ] ~= "{" then return nil end
	local shader = tokens[ opening - 1 ]
	local parameters = ParseVMTBlock( tokens, opening )
	if string.lower( shader ) == "patch" then
		local include = parameters.include
		parameters.include = nil
		local parent, parentShader = include
			and ReadMaterialVMT( include, depth + 1 ) or nil
		if parent then
			local merged = MergeVMTParameters( {}, parent )
			MergeVMTParameters( merged, parameters.insert, true )
			MergeVMTParameters( merged, parameters.replace, false )
			parameters.insert = nil
			parameters.replace = nil
			MergeVMTParameters( merged, parameters, false )
			parameters, shader = merged, parentShader
		else
			shader = nil
		end
	end
	if depth == 0 then
		ABT.MaterialTemplateCache[ path ] = {
			parameters = table.Copy( parameters ), shader = shader,
		}
	end
	return parameters, shader
end

local function NumberToVMTString( value )
	if value == math.floor( value ) and math.abs( value ) < 1e9 then
		return string.format( "%d", value )
	end
	local output = string.format( "%.8f", value )
	output = string.gsub( output, "0+$", "" )
	return string.gsub( output, "%.$", "" )
end

local function SanitizeMaterialValue( value )
	if isstring( value ) then return value end
	if isnumber( value ) then return NumberToVMTString( value ) end
	if isbool( value ) then return value and "1" or "0" end
	if isvector( value ) then
		return string.format( "[%s %s %s]", NumberToVMTString( value.x ),
			NumberToVMTString( value.y ), NumberToVMTString( value.z ) )
	end
	if TypeID( value ) == TYPE_TEXTURE then
		local ok, name = pcall( value.GetName, value )
		return ok and name or nil
	end
	if TypeID( value ) == TYPE_MATRIX then return nil end
	if istable( value ) then
		local output = {}
		for rawKey, child in pairs( value ) do
			local key = string.lower( tostring( rawKey ) )
			if not INTERNAL_MATERIAL_KEYS[ key ] then
				local sanitized = SanitizeMaterialValue( child )
				if sanitized ~= nil then output[ key ] = sanitized end
			end
		end
		return output
	end
	return nil
end

local function MaterialParameterEnabled( parameters, name )
	local value = parameters and parameters[ string.lower( name ) ]
	if isbool( value ) then return value end
	if isnumber( value ) then return value ~= 0 end
	if value == nil then return false end
	value = string.lower( string.Trim( tostring( value ) ) )
	return value ~= "" and value ~= "0" and value ~= "false" and value ~= "no"
end

local function UInt32LE( source, offset )
	local a, b, c, d = string.byte( source, offset, offset + 3 )
	if not d then return nil end
	return a + b * 256 + c * 65536 + d * 16777216
end

local function GetVTFMetadata( texture )
	local name = NormalizeMaterialPath( texture:GetName() )
	name = string.gsub( name, "%.vtf$", "" )
	local cached = ABT.VTFMetadataCache[ name ]
	if cached then return cached end
	local metadata = { readable = false, hasAlpha = nil }
	local handle = file.Open( "materials/" .. name .. ".vtf", "rb", "GAME" )
	if handle then
		local ok, header = pcall( function() return handle:Read( 56 ) end )
		handle:Close()
		if ok and header and #header >= 56 and string.sub( header, 1, 4 ) == "VTF\0" then
			metadata.readable = true
			local flags = UInt32LE( header, 21 ) or 0
			local format = UInt32LE( header, 53 )
			metadata.hasAlpha = bit.band( flags, VTF_ALPHA_FLAGS ) ~= 0
				or VTF_ALPHA_FORMATS[ format ] == true
		end
	end
	ABT.VTFMetadataCache[ name ] = metadata
	return metadata
end

local function SetDepthToDestinationAlpha( enabled )
	if render.SetWriteDepthToDestAlpha then render.SetWriteDepthToDestAlpha( enabled ) end
end

local function GetSourceCopyMaterials( texture )
	local name = texture:GetName()
	local key = string.lower( tostring( name ) )
	local cached = ABT.SourceMaterialCache[ key ]
	if not cached then
		local suffix = util.CRC( key )
		cached = {
			rgb = CreateMaterial( "abt_source_rgb_" .. suffix, "UnlitGeneric", {
				[ "$basetexture" ] = name, [ "$ignorez" ] = "1",
			} ),
			alpha = CreateMaterial( "abt_source_alpha_" .. suffix, "UnlitGeneric", {
				[ "$basetexture" ] = name, [ "$translucent" ] = "1",
				[ "$ignorez" ] = "1",
			} ),
		}
		ABT.SourceMaterialCache[ key ] = cached
	end
	cached.rgb:SetTexture( "$basetexture", texture )
	cached.alpha:SetTexture( "$basetexture", texture )
	return cached.rgb, cached.alpha
end

local function InitializeRenderTarget( target, sourceRGB, sourceAlpha, copyAlpha )
	SetDepthToDestinationAlpha( false )
	render.PushRenderTarget( target )
		render.OverrideAlphaWriteEnable( true, true )
		render.Clear( 255, 0, 255, 255 )
		render.OverrideAlphaWriteEnable( false )
		cam.Start2D()
			render.OverrideAlphaWriteEnable( true, false )
			render.OverrideBlend( true, BLEND_ONE, BLEND_ZERO, BLENDFUNC_ADD )
			render.SetMaterial( sourceRGB )
			render.DrawScreenQuad()
			render.OverrideBlend( false )
			render.OverrideAlphaWriteEnable( false )
			render.OverrideColorWriteEnable( true, false )
			render.OverrideAlphaWriteEnable( true, true )
			render.OverrideBlend( true,
				BLEND_ZERO, BLEND_ONE, BLENDFUNC_ADD,
				BLEND_ONE, BLEND_ZERO, BLENDFUNC_ADD )
			if copyAlpha then
				render.SetMaterial( sourceAlpha )
				render.DrawScreenQuad()
			else
				surface.SetDrawColor( 255, 255, 255, 255 )
				surface.DrawRect( 0, 0, target:Width(), target:Height() )
			end
			render.OverrideBlend( false )
			render.OverrideAlphaWriteEnable( false )
			render.OverrideColorWriteEnable( false, false )
		cam.End2D()
	render.PopRenderTarget()
	SetDepthToDestinationAlpha( true )
end

local function NearestPowerOfTwo( requested, maximum )
	local lower = 1
	while lower * 2 <= requested and lower * 2 <= maximum do lower = lower * 2 end
	local upper = math.min( lower * 2, maximum )
	if upper > lower and math.abs( upper - requested ) < math.abs( requested - lower ) then
		return upper
	end
	return lower
end

local function RenderTargetDimensions( texture )
	local sourceWidth = math.max( texture:Width(), 1 )
	local sourceHeight = math.max( texture:Height(), 1 )
	local maximum = math.min( 2048,
		render.MaxTextureWidth and render.MaxTextureWidth() or 2048,
		render.MaxTextureHeight and render.MaxTextureHeight() or 2048 )
	local scale = math.min( maximum / math.max( sourceWidth, sourceHeight ), 1 )
	return NearestPowerOfTwo( sourceWidth * scale, maximum ),
		NearestPowerOfTwo( sourceHeight * scale, maximum )
end

local function TransformAndUnwrapTriangle( coordinates, transform )
	local result = {}
	for _, coordinate in ipairs( coordinates ) do
		local u, v = coordinate.u, coordinate.v
		if transform then
			local point = transform * Vector( u, v, 0 )
			u, v = point.x, point.y
		end
		result[ #result + 1 ] = { u = u, v = v }
	end
	local anchor = result[ 1 ]
	for index = 2, #result do
		local coordinate = result[ index ]
		coordinate.u = coordinate.u + math.floor( anchor.u - coordinate.u + 0.5 )
		coordinate.v = coordinate.v + math.floor( anchor.v - coordinate.v + 0.5 )
	end
	return result
end

local function TileShiftRange( minimum, maximum )
	local first = math.ceil( -maximum )
	local last = math.floor( 1 - minimum )
	if last - first > 16 then last = first + 16 end
	return first, last
end

local function TrianglePolygon( coordinates, width, height, shiftU, shiftV, expansion )
	local points = {}
	for _, coordinate in ipairs( coordinates ) do
		points[ #points + 1 ] = {
			x = ( coordinate.u + shiftU ) * width,
			y = ( coordinate.v + shiftV ) * height,
		}
	end
	if #points ~= 3 then return nil end
	local first, second, third = points[ 1 ], points[ 2 ], points[ 3 ]
	local signedArea = ( second.x - first.x ) * ( third.y - first.y )
		- ( second.y - first.y ) * ( third.x - first.x )
	if signedArea < 0 then points[ 2 ], points[ 3 ] = points[ 3 ], points[ 2 ] end
	if expansion <= 0 then return points end
	local expanded = {}
	for index = 1, 3 do
		local previous = points[ ( index + 1 ) % 3 + 1 ]
		local current = points[ index ]
		local following = points[ index % 3 + 1 ]
		local incomingX, incomingY = current.x - previous.x, current.y - previous.y
		local outgoingX, outgoingY = following.x - current.x, following.y - current.y
		local incomingLength = math.sqrt( incomingX * incomingX + incomingY * incomingY )
		local outgoingLength = math.sqrt( outgoingX * outgoingX + outgoingY * outgoingY )
		if incomingLength < 0.0001 or outgoingLength < 0.0001 then return points end
		local incomingNormalX, incomingNormalY = incomingY / incomingLength,
			-incomingX / incomingLength
		local outgoingNormalX, outgoingNormalY = outgoingY / outgoingLength,
			-outgoingX / outgoingLength
		expanded[ #expanded + 1 ] = {
			x = current.x + incomingNormalX * expansion,
			y = current.y + incomingNormalY * expansion,
		}
		expanded[ #expanded + 1 ] = {
			x = current.x + outgoingNormalX * expansion,
			y = current.y + outgoingNormalY * expansion,
		}
	end
	return expanded
end

local function DrawUVTriangle( coordinates, width, height, transform )
	coordinates = TransformAndUnwrapTriangle( coordinates, transform )
	local minimumU, maximumU = math.huge, -math.huge
	local minimumV, maximumV = math.huge, -math.huge
	for _, coordinate in ipairs( coordinates ) do
		minimumU, maximumU = math.min( minimumU, coordinate.u ),
			math.max( maximumU, coordinate.u )
		minimumV, maximumV = math.min( minimumV, coordinate.v ),
			math.max( maximumV, coordinate.v )
	end
	local expansion = 1
	local firstU, lastU = TileShiftRange( minimumU - expansion / width,
		maximumU + expansion / width )
	local firstV, lastV = TileShiftRange( minimumV - expansion / height,
		maximumV + expansion / height )
	for shiftU = firstU, lastU do
		for shiftV = firstV, lastV do
			local polygon = TrianglePolygon( coordinates, width, height,
				shiftU, shiftV, expansion )
			if polygon then surface.DrawPoly( polygon ) end
		end
	end
end

local function PaintTransparentTriangles( target, triangles, transform )
	SetDepthToDestinationAlpha( false )
	render.PushRenderTarget( target )
		cam.Start2D()
			local previousClipping = DisableClipping( true )
			render.OverrideColorWriteEnable( true, false )
			render.OverrideAlphaWriteEnable( true, true )
			render.OverrideBlend( true,
				BLEND_ZERO, BLEND_ONE, BLENDFUNC_ADD,
				BLEND_ZERO, BLEND_ZERO, BLENDFUNC_ADD )
			draw.NoTexture()
			surface.SetDrawColor( 255, 255, 255, 255 )
			for _, coordinates in ipairs( triangles ) do
				DrawUVTriangle( coordinates, target:Width(), target:Height(), transform )
			end
			render.OverrideBlend( false )
			render.OverrideAlphaWriteEnable( false )
			render.OverrideColorWriteEnable( false, false )
			DisableClipping( previousClipping )
		cam.End2D()
	render.PopRenderTarget()
	SetDepthToDestinationAlpha( true )
end

local function ResolveSourceMaterial( entity, submaterialIndex, originalPath )
	local overrideName = entity:GetSubMaterial( submaterialIndex ) or ""
	local material, sourcePath
	if overrideName ~= "" then
		local procedural = string.sub( overrideName, 1, 1 ) == "!"
		local materialName = procedural
			and string.sub( overrideName, 2 ) or overrideName
		material = Material( materialName )
		if not procedural then sourcePath = materialName end
	end
	if not material or material:IsError() then
		material = Material( originalPath )
		sourcePath = originalPath
	end
	return material, sourcePath
end

local function MaskedResourceCompatible( resource, sourceMaterial, baseTexture,
	shader, width, height, usesAlphaTest, usesTranslucent, copyAlpha )
	if not istable( resource ) or not resource.material or not resource.target
	or resource.material:IsError() or resource.target:IsError() then return false end
	return resource.sourceMaterial == sourceMaterial
		and resource.baseTexture == baseTexture
		and resource.shader == shader
		and resource.width == width and resource.height == height
		and resource.usesAlphaTest == usesAlphaTest
		and resource.usesTranslucent == usesTranslucent
		and resource.copyAlpha == copyAlpha
end

local function CreateMaskedMaterial( entity, submaterialIndex, originalPath,
	triangles, reusable )
	local original, sourcePath = ResolveSourceMaterial(
		entity, submaterialIndex, originalPath )
	if not original or original:IsError() then return nil, "source material failed to load" end
	local baseTexture = original:GetTexture( "$basetexture" )
	if not baseTexture or baseTexture:IsError() then return nil, "material has no $basetexture" end
	local width, height = RenderTargetDimensions( baseTexture )
	local rawParameters = original:GetKeyValues() or {}
	local authoredParameters, authoredShader = sourcePath
		and ReadMaterialVMT( sourcePath )
	local parameterSource = authoredParameters or rawParameters
	local usesAlphaTest = MaterialParameterEnabled( parameterSource, "$alphatest" )
	local usesTranslucent = MaterialParameterEnabled( parameterSource, "$translucent" )
	local alphaStyle = usesAlphaTest or usesTranslucent
	local metadata = GetVTFMetadata( baseTexture )
	local copyAlpha = alphaStyle
		and ( not metadata.readable or metadata.hasAlpha ) or false
	local shader = authoredShader or original:GetShader()
	if not isstring( shader ) or shader == "" or shader == "Shader_Error" then
		shader = "VertexLitGeneric"
	end
	local sourceMaterialName = NormalizeMaterialPath( original:GetName() )
	if sourceMaterialName == "" then
		sourceMaterialName = NormalizeMaterialPath( sourcePath or originalPath )
	end
	local baseTextureName = NormalizeMaterialPath( baseTexture:GetName() )
	local shaderKey = string.lower( shader )
	local resource, target, masked
	if MaskedResourceCompatible( reusable, sourceMaterialName, baseTextureName,
		shaderKey, width, height, usesAlphaTest, usesTranslucent, copyAlpha ) then
		resource = reusable
		target = reusable.target
		masked = reusable.material
	else
		ABT.MaterialSerial = ABT.MaterialSerial + 1
		local serial = ABT.MaterialSerial
		local targetName = "abt_uv_hide_rt_" .. serial
		target = GetRenderTargetEx( targetName, width, height,
			RT_SIZE_LITERAL, MATERIAL_RT_DEPTH_NONE, DAMAGE_RT_FLAGS, 0,
			IMAGE_FORMAT_BGRA8888 )
		if not target or target:IsError() then
			return nil, "masked render target creation failed"
		end
		local parameters = SanitizeMaterialValue( parameterSource ) or {}
		-- GetKeyValues exposes an engine-default $alpha even when the VMT did not
		-- author one. Do not turn that default into a procedural material override.
		if not authoredParameters then parameters[ "$alpha" ] = nil end
		parameters[ "$basetexture" ] = target:GetName()
		parameters[ "$nocull" ] = "1"
		-- Opaque and alpha-tested sources need alpha testing for the new zero-alpha
		-- mask. A translucent source already consumes smooth alpha, so preserve that
		-- blend mode instead of reducing its original alpha to a binary cutout.
		if not usesTranslucent or usesAlphaTest then
			parameters[ "$alphatest" ] = "1"
			parameters[ "$alphatestreference" ] =
				parameters[ "$alphatestreference" ] or "0.5"
			parameters[ "$allowalphatocoverage" ] =
				parameters[ "$allowalphatocoverage" ] or "1"
		end
		local materialName = "abt_uv_hide_mat_" .. serial
		masked = CreateMaterial( materialName, shader, parameters )
		if not masked or masked:IsError() then
			return nil, "masked material creation failed"
		end
		resource = {
			material = masked,
			target = target,
			sourceMaterial = sourceMaterialName,
			baseTexture = baseTextureName,
			shader = shaderKey,
			width = width,
			height = height,
			usesAlphaTest = usesAlphaTest,
			usesTranslucent = usesTranslucent,
			copyAlpha = copyAlpha,
		}
	end
	local sourceRGB, sourceAlpha = GetSourceCopyMaterials( baseTexture )
	InitializeRenderTarget( target, sourceRGB, sourceAlpha, copyAlpha )
	local transform = original:GetMatrix( "$basetexturetransform" )
	PaintTransparentTriangles( target, triangles, transform )
	masked:SetTexture( "$basetexture", target )
	for rawKey, value in pairs( rawParameters ) do
		local key = string.lower( tostring( rawKey ) )
		if key ~= "$basetexture" and TypeID( value ) == TYPE_TEXTURE then
			pcall( masked.SetTexture, masked, key, value )
		end
	end
	if transform then pcall( masked.SetMatrix, masked, "$basetexturetransform", transform ) end
	resource.originalPath = originalPath
	return resource
end

local function DrawPrevious( state, entity, flags )
	local previous = state.previousRenderOverride
	if not isfunction( previous ) or previous == state.renderOverride then
		return entity:DrawModel( flags )
	end

	-- A cooperating RenderOverride may rebuild while this state is live. If its
	-- previous link returns here, stop at the engine draw instead of recursing.
	if state.previousRenderOverrideActive then
		return entity:DrawModel( flags )
	end
	state.previousRenderOverrideActive = true
	local ok, result = pcall( previous, entity, flags )
	state.previousRenderOverrideActive = false
	if not ok then error( result, 0 ) end
	return result
end

local function InstallRenderOverride( entity, state )
	if state.renderOverride and entity.RenderOverride == state.renderOverride then return end
	state.previousRenderOverride = entity.RenderOverride
	state.renderOverride = function( renderEntity, flags )
		if ABT.ClientStates[ renderEntity ] ~= state then
			return DrawPrevious( state, renderEntity, flags )
		end
		for index, resource in pairs( state.resources or {} ) do
			render.MaterialOverrideByIndex( index, resource.material )
		end
		local ok, result = pcall( DrawPrevious, state, renderEntity, flags )
		local clearOK, clearError = pcall( render.MaterialOverrideByIndex )
		if ok and clearOK then return result end
		local failure = ok and clearError or result
		if not state.nextError or RealTime() >= state.nextError then
			state.nextError = RealTime() + 5
			ErrorNoHalt( "[Advanced Bodygroup Tool] render override failed: "
				.. tostring( failure ) .. "\n" )
		end
		return renderEntity:DrawModel( flags )
	end
	entity.RenderOverride = state.renderOverride
end

local function RemoveState( entity )
	local state = ABT.ClientStates[ entity ]
	if state and IsValid( entity ) and state.renderOverride then
		if entity.RenderOverride == state.renderOverride then
			entity.RenderOverride = state.previousRenderOverride
		else
			local bbs = _G.BBS
			local bbsState = istable( bbs ) and istable( bbs.DamageStates )
				and bbs.DamageStates[ entity ] or nil
			if istable( bbsState )
			and entity.RenderOverride == bbsState.rtxRenderOverride
			and bbsState.previousRenderOverride == state.renderOverride then
				bbsState.previousRenderOverride = state.previousRenderOverride
			end
		end
	end
	if state then state.previousRenderOverrideActive = nil end
	ABT.ClientStates[ entity ] = nil
end

local function CollectHiddenMaterialTriangles( entity, analysis, hidden,
	hiddenRegions, vertexKeepBounds )
	local records = {}
	local activeBounds, compiledByGroup = {}, {}
	for rawGroup, bounds in pairs( vertexKeepBounds or {} ) do
		local group = tonumber( rawGroup )
		if group and group == math.floor( group ) and group >= 0 and group <= 255
		and istable( bounds ) and tonumber( bounds.option )
		== entity:GetBodygroup( group ) then
			activeBounds[ group ] = bounds
			if istable( bounds.cuts ) then
				compiledByGroup[ group ] =
					ABT.CompileVertexKeepCuts( bounds ) or {}
			end
		end
	end
	for _, triangle in ipairs( analysis.triangles or {} ) do
		local regions = hiddenRegions[ triangle.group ]
		local keepBounds = activeBounds[ triangle.group ]
		local outsideKeepRange = keepBounds
			and not ABT.TrianglePassesVertexKeepBounds(
				triangle, keepBounds, compiledByGroup[ triangle.group ] )
		if hidden[ triangle.group ] or ( regions and regions[ triangle.region ] )
		or outsideKeepRange then
			local path = NormalizeMaterialPath( triangle.material )
			local record = records[ path ]
			if not record then
				record = { material = triangle.material, triangles = {} }
				records[ path ] = record
			end
			record.triangles[ #record.triangles + 1 ] = triangle.uv
		end
	end
	return records
end

local function BuildState( entity, identity )
	local cached = ABT.ResourceVariantCache[ entity ]
	if cached and cached.identity == identity then
		return {
			identity = identity,
			resources = cached.resources,
			warning = cached.warning,
		}
	end
	ABT.ResourceVariantCache[ entity ] = nil
	local analysis, analysisError = GetRegionAnalysis( entity )
	if not analysis then return nil, analysisError end
	local hidden = ABT.GetHiddenBodygroupSet( entity )
	local hiddenRegions = ABT.GetHiddenRegionSet( entity )
	local vertexKeepBounds = ABT.GetVertexKeepBounds( entity )
	local records = CollectHiddenMaterialTriangles( entity, analysis, hidden,
		hiddenRegions, vertexKeepBounds )
	local state = { identity = identity, resources = {} }
	local pool = ABT.ResourcePools[ entity ]
	if not pool then
		pool = {}
		ABT.ResourcePools[ entity ] = pool
	end
	for _, record in pairs( records ) do
		for _, submaterialIndex in ipairs(
			FindSubmaterialIndexes( entity, record.material ) ) do
			if submaterialIndex >= 0 and submaterialIndex < MAX_SUBMATERIALS then
				local resource, resourceError = CreateMaskedMaterial( entity,
					submaterialIndex, record.material, record.triangles,
					pool[ submaterialIndex ] )
				if resource then
					pool[ submaterialIndex ] = resource
					state.resources[ submaterialIndex ] = resource
				elseif not state.warning then
					state.warning = resourceError
				end
			end
		end
	end
	ABT.ResourceVariantCache[ entity ] = {
		identity = identity,
		resources = state.resources,
		warning = state.warning,
	}
	return state
end

local pending = setmetatable( {}, { __mode = "k" } )
local nextScan = 0

hook.Add( "Think", "AdvancedBodygroupTool.UVHideScan", function()
	if RealTime() < nextScan then return end
	nextScan = RealTime() + 0.35
	local seen = {}
	for _, entity in ipairs( ents.GetAll() ) do
		local hidden = entity:GetNW2String( ABT.HiddenNWKey, "" )
		local hiddenRegions = ABT.GetHiddenRegionEncoding( entity )
		local vertexKeep = ABT.GetVertexKeepEncoding( entity )
		if hidden ~= "" or hiddenRegions ~= "" or vertexKeep ~= "" then
			seen[ entity ] = true
			local identity = HiddenIdentity( entity )
			local state = ABT.ClientStates[ entity ]
			if not state or state.identity ~= identity then
				pending[ entity ] = identity
			elseif next( state.resources or {} ) ~= nil then
				InstallRenderOverride( entity, state )
			end
		end
	end
	for entity in pairs( ABT.ClientStates ) do
		if not seen[ entity ] or not IsValid( entity ) then RemoveState( entity ) end
	end
	for entity in pairs( ABT.ResourceVariantCache ) do
		if not seen[ entity ] or not IsValid( entity ) then
			ABT.ResourceVariantCache[ entity ] = nil
		end
	end
end )

hook.Add( "PreRender", "AdvancedBodygroupTool.UVHideBuild", function()
	local entity, identity = next( pending )
	if not entity then return end
	pending[ entity ] = nil
	if not IsValid( entity ) or (
		entity:GetNW2String( ABT.HiddenNWKey, "" ) == ""
		and ABT.GetHiddenRegionEncoding( entity ) == ""
		and ABT.GetVertexKeepEncoding( entity ) == "" )
	or HiddenIdentity( entity ) ~= identity then return end
	local state, errorMessage = BuildState( entity, identity )
	if not state then
		ABT.ResourceVariantCache[ entity ] = nil
		local old = ABT.ClientStates[ entity ]
		if not old or old.errorIdentity ~= identity then
			ErrorNoHalt( "[Advanced Bodygroup Tool] UV hide failed for "
				.. tostring( entity:GetModel() ) .. ": "
				.. tostring( errorMessage ) .. "\n" )
		end
		RemoveState( entity )
		ABT.ClientStates[ entity ] = {
			identity = identity, errorIdentity = identity, resources = {},
		}
		return
	end
	RemoveState( entity )
	ABT.ClientStates[ entity ] = state
	if next( state.resources ) ~= nil then InstallRenderOverride( entity, state ) end
	if state.warning then
		ErrorNoHalt( "[Advanced Bodygroup Tool] some UV materials were skipped: "
			.. tostring( state.warning ) .. "\n" )
	end
end )

hook.Add( "EntityRemoved", "AdvancedBodygroupTool.UVHideForget", function( entity )
	pending[ entity ] = nil
	ABT.ClearHoveredRegion( entity )
	RemoveState( entity )
	ABT.ResourceVariantCache[ entity ] = nil
	ABT.ResourcePools[ entity ] = nil
end )
