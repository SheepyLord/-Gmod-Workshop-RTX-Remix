-- Read the small bodypart/model/mesh portion of Source v48 MDL files.
--
-- util.GetModelMeshes deliberately exposes geometry without its source
-- bodygroup.  Differential selections recover ownership for ordinary groups
-- with an alternate option, but cannot identify a bodygroup compiled with one
-- visible submodel and no blank.  The MDL already stores the exact ordered
-- bodypart -> model -> mesh relationship, so use that authoritative layout.

BBS = BBS or {}

local LAYOUT_FORMAT = 1
if BBS.CompiledBodypartLayoutFormat ~= LAYOUT_FORMAT then
	BBS.CompiledBodypartLayoutCache = {}
	BBS.CompiledBodypartLayoutFormat = LAYOUT_FORMAT
else
	BBS.CompiledBodypartLayoutCache = BBS.CompiledBodypartLayoutCache or {}
end

local STUDIO_VERSION = 48
local MAX_MODEL_BYTES = 256 * 1024 * 1024
local MAX_BODYPARTS = 256
local MAX_MODELS_PER_BODYPART = 256
local MAX_MESHES_PER_MODEL = 4096

-- studiohdr_t offsets for Source's serialized v48, 32-bit packed format.
local HEADER_LENGTH_OFFSET = 76
local HEADER_NUM_BODYPARTS_OFFSET = 232
local HEADER_BODYPART_INDEX_OFFSET = 236
local BODYPART_SIZE = 16
local BODYPART_NAME_OFFSET = 0
local BODYPART_NUM_MODELS_OFFSET = 4
local BODYPART_BASE_OFFSET = 8
local BODYPART_MODEL_INDEX_OFFSET = 12
local MODEL_SIZE = 148
local MODEL_NAME_OFFSET = 0
local MODEL_NAME_LENGTH = 64
local MODEL_NUM_MESHES_OFFSET = 72
local MODEL_MESH_INDEX_OFFSET = 76
local MESH_SIZE = 116
local MESH_NUM_VERTICES_OFFSET = 8
local MESH_NUM_LOD_VERTICES_OFFSET = 52

local function ReadUInt32LE( bytes, offset )
	if offset < 0 or offset + 4 > #bytes then return nil end
	local a, b, c, d = string.byte( bytes, offset + 1, offset + 4 )
	if not d then return nil end
	return a + b * 256 + c * 65536 + d * 16777216
end

local function ReadCString( bytes, offset, maximumLength )
	if offset < 0 or offset >= #bytes then return nil end
	local last = math.min( #bytes, offset + math.max( maximumLength or 256, 1 ) )
	local terminator = string.find( bytes, "\0", offset + 1, true )
	if not terminator or terminator > last then terminator = last + 1 end
	return string.sub( bytes, offset + 1, terminator - 1 )
end

local function InRange( bytes, offset, length )
	return offset >= 0 and length >= 0 and offset + length <= #bytes
end

local function ParseCompiledBodyparts( model )
	local size = file.Size( model, "GAME" ) or -1
	if size <= 0 then return nil, "MDL file is not mounted" end
	if size > MAX_MODEL_BYTES then return nil, "MDL exceeds parser safety limit" end

	local bytes = file.Read( model, "GAME" )
	if not bytes then return nil, "MDL could not be read" end
	if string.sub( bytes, 1, 4 ) ~= "IDST" then
		return nil, "MDL has no IDST signature"
	end
	local version = ReadUInt32LE( bytes, 4 )
	if version ~= STUDIO_VERSION then
		return nil, "unsupported MDL version " .. tostring( version )
	end
	local declaredLength = ReadUInt32LE( bytes, HEADER_LENGTH_OFFSET )
	if not declaredLength or declaredLength < HEADER_NUM_BODYPARTS_OFFSET + 8
	or declaredLength > #bytes then
		return nil, "invalid MDL declared length"
	end
	local bodypartCount = ReadUInt32LE( bytes, HEADER_NUM_BODYPARTS_OFFSET )
	local bodypartOffset = ReadUInt32LE( bytes, HEADER_BODYPART_INDEX_OFFSET )
	if not bodypartCount or bodypartCount > MAX_BODYPARTS
	or not bodypartOffset
	or not InRange( bytes, bodypartOffset, bodypartCount * BODYPART_SIZE ) then
		return nil, "invalid MDL bodypart table"
	end

	local parsed = {
		model = model,
		version = version,
		fileSize = #bytes,
		bodypartCount = bodypartCount,
		bodyparts = {},
	}
	for bodypartId = 0, bodypartCount - 1 do
		local bodypartAddress = bodypartOffset + bodypartId * BODYPART_SIZE
		local relativeName = ReadUInt32LE( bytes,
			bodypartAddress + BODYPART_NAME_OFFSET )
		local modelCount = ReadUInt32LE( bytes,
			bodypartAddress + BODYPART_NUM_MODELS_OFFSET )
		local bodypartBase = ReadUInt32LE( bytes,
			bodypartAddress + BODYPART_BASE_OFFSET )
		local relativeModels = ReadUInt32LE( bytes,
			bodypartAddress + BODYPART_MODEL_INDEX_OFFSET )
		if not modelCount or modelCount < 1 or modelCount > MAX_MODELS_PER_BODYPART
		or not relativeModels then
			return nil, "invalid model table for bodypart " .. bodypartId
		end
		local modelsAddress = bodypartAddress + relativeModels
		if not InRange( bytes, modelsAddress, modelCount * MODEL_SIZE ) then
			return nil, "model table leaves MDL for bodypart " .. bodypartId
		end

		local bodypart = {
			id = bodypartId,
			name = relativeName and ReadCString( bytes,
				bodypartAddress + relativeName, 256 ) or nil,
			base = bodypartBase or 0,
			modelCount = modelCount,
			models = {},
		}
		for modelId = 0, modelCount - 1 do
			local modelAddress = modelsAddress + modelId * MODEL_SIZE
			local meshCount = ReadUInt32LE( bytes,
				modelAddress + MODEL_NUM_MESHES_OFFSET )
			local relativeMeshes = ReadUInt32LE( bytes,
				modelAddress + MODEL_MESH_INDEX_OFFSET )
			if not meshCount or meshCount > MAX_MESHES_PER_MODEL
			or not relativeMeshes then
				return nil, "invalid mesh table for bodypart " .. bodypartId
			end
			local meshesAddress = modelAddress + relativeMeshes
			if meshCount > 0
			and not InRange( bytes, meshesAddress, meshCount * MESH_SIZE ) then
				return nil, "mesh table leaves MDL for bodypart " .. bodypartId
			end
			local modelRecord = {
				id = modelId,
				name = ReadCString( bytes, modelAddress + MODEL_NAME_OFFSET,
					MODEL_NAME_LENGTH ) or "",
				meshCount = meshCount,
				meshes = {},
			}
			for meshId = 0, meshCount - 1 do
				local meshAddress = meshesAddress + meshId * MESH_SIZE
				modelRecord.meshes[ meshId + 1 ] = {
					id = meshId,
					vertexCount = ReadUInt32LE( bytes,
						meshAddress + MESH_NUM_VERTICES_OFFSET ) or 0,
					lod0VertexCount = ReadUInt32LE( bytes,
						meshAddress + MESH_NUM_LOD_VERTICES_OFFSET ) or 0,
				}
			end
			bodypart.models[ modelId ] = modelRecord
		end
		parsed.bodyparts[ bodypartId ] = bodypart
	end
	return parsed
end

local function LayoutCacheKey( model )
	local size = file.Size( model, "GAME" ) or -1
	local changed = file.Time( model, "GAME" ) or 0
	return string.lower( tostring( model or "" ) ) .. "|" .. size .. "|" .. changed
end

local function GetParsedCompiledBodyparts( model )
	model = string.gsub( tostring( model or "" ), "\\", "/" )
	if model == "" then return nil, "model path is empty" end
	local key = LayoutCacheKey( model )
	local cached = BBS.CompiledBodypartLayoutCache[ key ]
	if cached then return cached.layout, cached.error, true end
	local layout, parseError = ParseCompiledBodyparts( model )
	BBS.CompiledBodypartLayoutCache[ key ] = {
		layout = layout,
		error = parseError,
	}
	return layout, parseError, false
end

function BBS.GetCompiledBodypartMeshLayout( model, selectionValues, lod )
	if math.max( 0, math.floor( tonumber( lod ) or 0 ) ) ~= 0 then
		return nil, "compiled ownership currently supports LOD 0"
	end
	local parsed, parseError, cacheHit = GetParsedCompiledBodyparts( model )
	if not parsed then return nil, parseError, cacheHit end

	local layout = {
		model = parsed.model,
		version = parsed.version,
		bodyparts = {},
		totalMeshes = 0,
		parseCacheHit = cacheHit,
	}
	local cursor = 1
	for bodypartId = 0, parsed.bodypartCount - 1 do
		local source = parsed.bodyparts[ bodypartId ]
		if source then
			local selected = math.floor( tonumber(
				selectionValues and selectionValues[ bodypartId ] ) or 0 )
			selected = math.Clamp( selected, 0, source.modelCount - 1 )
			local activeModel = source.models[ selected ]
			if not activeModel then
				return nil, "active model is absent for bodypart " .. bodypartId,
					cacheHit
			end
			local bodypart = {
				id = bodypartId,
				name = source.name or ( "bodygroup_" .. bodypartId ),
				modelCount = source.modelCount,
				selected = selected,
				selectedModelName = activeModel.name,
				meshCount = activeModel.meshCount,
				firstMesh = cursor,
				lastMesh = cursor + activeModel.meshCount - 1,
				meshes = activeModel.meshes,
			}
			layout.bodyparts[ bodypartId ] = bodypart
			cursor = cursor + activeModel.meshCount
		end
	end
	layout.totalMeshes = cursor - 1
	return layout, nil, cacheHit
end

function BBS.ClearCompiledBodypartLayoutCache()
	BBS.CompiledBodypartLayoutCache = {}
end
