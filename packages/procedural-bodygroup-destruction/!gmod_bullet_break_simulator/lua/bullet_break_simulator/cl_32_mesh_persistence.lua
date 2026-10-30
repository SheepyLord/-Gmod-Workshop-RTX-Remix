-- Chunked persistent processed-mesh cache. This avoids rebuilding expensive
-- util.GetModelMeshes results every time the game restarts.

BBS = BBS or {}

-- These jobs survive an autorun refresh because BBS is intentionally shared.
-- Keep their in-memory wrapper schema separate from the on-disk format: a
-- queued writer from an older Lua revision must never reinterpret newly packed
-- triangle corners and silently persist zero UVs.
local function CloseBundle( state )
	local handle = state and state.bundleFile
	if not handle then return end
	state.bundleFile = nil
	-- Also used during hot reload and failure cleanup; an already-closed engine
	-- handle must not prevent the rest of the queued work from being released.
	pcall( handle.Close, handle )
end

local PERSISTENT_RUNTIME_FORMAT = 9
if BBS.PersistentMeshRuntimeFormat ~= PERSISTENT_RUNTIME_FORMAT then
	for _, state in pairs( BBS.PersistentMeshLoads or {} ) do CloseBundle( state ) end
	for _, job in ipairs( BBS.PersistentMeshWriteQueue or {} ) do CloseBundle( job ) end
	BBS.PersistentMeshLoads = {}
	BBS.PersistentMeshWriteQueue = {}
	BBS.PersistentMeshWriteQueued = {}
	BBS.PersistentMeshCommitted = {}
	BBS.PersistentMeshRuntimeFormat = PERSISTENT_RUNTIME_FORMAT
else
	BBS.PersistentMeshLoads = BBS.PersistentMeshLoads or {}
	BBS.PersistentMeshWriteQueue = BBS.PersistentMeshWriteQueue or {}
	BBS.PersistentMeshWriteQueued = BBS.PersistentMeshWriteQueued or {}
	BBS.PersistentMeshCommitted = BBS.PersistentMeshCommitted or {}
end
BBS.PersistentMeshStats = BBS.PersistentMeshStats or {
	loaded = 0,
	written = 0,
	loadFailures = 0,
	writeFailures = 0,
	writeDrops = 0,
	metadataUpdates = 0,
	chunksRead = 0,
	chunksWritten = 0,
}

-- Keep each compressed JSON chunk bounded, but put all chunks in one stream.
-- A detailed model otherwise needs hundreds of filesystem opens on every load.
-- v5/v4/v2 remain readable, including their exact original numeric values.
local CACHE_FORMAT = 6
local CACHE_ROOT = "bbs_mesh_cache/v" .. CACHE_FORMAT
local CHUNK_SIZE = 512
local PREVIOUS_CACHE_FORMAT = 5
local PREVIOUS_CACHE_ROOT = "bbs_mesh_cache/v" .. PREVIOUS_CACHE_FORMAT
local LEGACY_CACHE_FORMAT = 4
local LEGACY_CACHE_ROOT = "bbs_mesh_cache/v" .. LEGACY_CACHE_FORMAT
local LEGACY_CHUNK_SIZE = 128
local OLDER_CACHE_FORMAT = 2
local OLDER_CACHE_ROOT = "bbs_mesh_cache/v" .. OLDER_CACHE_FORMAT
local OLDER_CHUNK_SIZE = 512
local HYDRATE_ROWS_PER_STEP = 32
local WRITE_ROWS_PER_STEP = 32
local INDEX_ROWS_PER_STEP = 128
local ELIGIBILITY_FORMAT = 10
local BUNDLE_NAME = "geometry.dat"

local function GetBool( name, fallback )
	local convar = GetConVar( name )
	return convar and convar:GetBool() or fallback
end

local function GetFloat( name, fallback )
	local convar = GetConVar( name )
	return convar and convar:GetFloat() or fallback
end

local function PersistentWriteBudget( job )
	local configured = math.Clamp(
		GetFloat( "bbs_mesh_cache_io_budget_ms", 10 ), 0.1, 80 )
	-- Recording a completed cache is never on the critical path of a hit. Keep it
	-- at the configured background budget instead of stealing a large frame to
	-- meet an arbitrary wall-clock target; the committed data survives whenever
	-- the writer naturally finishes.
	job.processingStartedAt = job.processingStartedAt or SysTime()
	return configured
end

local function CacheFolder( key, root )
	return ( root or CACHE_ROOT ) .. "/" .. util.CRC( tostring( key or "" ) )
end

local function MetadataPath( key, root )
	return CacheFolder( key, root ) .. "/metadata.json"
end

local function ModelStamp( model )
	return file.Time( model, "GAME" ) or 0, file.Size( model, "GAME" ) or -1
end

local function DiscardMetadata( key, root )
	-- Chunk files are harmless without their small commit record. Deleting only
	-- metadata is cheap, makes an interrupted/corrupt cache immediately invalid,
	-- and lets the next successful background extraction replace its chunks.
	file.Delete( MetadataPath( key, root ) )
	if BBS.PersistentMeshCommitted then BBS.PersistentMeshCommitted[ key ] = nil end
end

local function FilterSignature()
	local config = BBS.GetDamageFilterConfig and BBS.GetDamageFilterConfig() or {}
	local encoded = util.TableToJSON( {
		eligibilityFormat = ELIGIBILITY_FORMAT,
		bodygroups = config.bodygroups or {},
		hideableBodygroupOverrides = config.hideableBodygroupOverrides or {},
	} ) or ""
	return util.CRC( encoded )
end

local function EncodeWeights( weights )
	if istable( weights )
	and ( #weights == 0 or isnumber( weights[ 1 ] ) ) then return weights end
	local output = {}
	for _, value in ipairs( weights or {} ) do
		output[ #output + 1 ] = tonumber( value.bone ) or 0
		output[ #output + 1 ] = tonumber( value.weight ) or 0
	end
	return output
end

local function DecodeWeights( source )
	local output = {}
	if not istable( source ) then return output end
	for index = 1, #( source or {} ) - 1, 2 do
		output[ #output + 1 ] = tonumber( source[ index ] ) or 0
		output[ #output + 1 ] = tonumber( source[ index + 1 ] ) or 0
	end
	return output
end

local function DecodeWeightsChecked( source )
	if not istable( source ) or #source % 2 ~= 0 then return nil end
	for index = 1, #source, 2 do
		local bone = tonumber( source[ index ] )
		local weight = tonumber( source[ index + 1 ] )
		if bone == nil or weight == nil or bone ~= bone or weight ~= weight then
			return nil
		end
		-- JSON already gave us an independent packed array. Normalize it in
		-- place instead of allocating and immediately collecting a second weight
		-- table for every persisted skin point.
		source[ index ] = bone
		source[ index + 1 ] = weight
	end
	return source
end

local function WriteChunk( job, name, value )
	local encoded = util.TableToJSON( value, false )
	if not encoded then return false, "JSON encoding failed" end
	local compressed = util.Compress( encoded )
	if not compressed then return false, "compression failed" end
	if not job.bundleFile then return false, "geometry bundle is not open" end
	local offset = job.bundleBytes or 0
	job.bundleFile:Write( compressed )
	job.bundleBytes = offset + #compressed
	if job.bundleFile:Tell() ~= job.bundleBytes then
		return false, "geometry bundle write was incomplete"
	end
	job.metadata.chunks[ name ] = { offset, #compressed }
	return true
end

local function ReadChunk( state, name )
	local compressed
	if state.cacheFormat == CACHE_FORMAT then
		local entry = state.metadata.chunks[ name ]
		local offset = istable( entry ) and tonumber( entry[ 1 ] ) or nil
		local length = istable( entry ) and tonumber( entry[ 2 ] ) or nil
		if not offset or not length or offset < 0 or length <= 0
		or offset % 1 ~= 0 or length % 1 ~= 0
		or offset ~= ( state.bundleOffset or 0 )
		or offset + length > state.metadata.bundleBytes then
			return nil, "invalid bundle chunk " .. name
		end
		if not state.bundleFile then
			state.bundleFile = file.Open( state.folder .. "/" .. BUNDLE_NAME,
				"rb", "DATA" )
			if not state.bundleFile then return nil, "missing geometry bundle" end
			if state.bundleFile:Size() ~= state.metadata.bundleBytes then
				return nil, "geometry bundle size does not match metadata"
			end
		end
		-- Writer and hydrator both visit skin/triangle chunks in mesh order.
		-- Sequential reads retain the engine's file buffering across resumes.
		compressed = state.bundleFile:Read( length )
		if not compressed or #compressed ~= length then
			return nil, "short bundle read for " .. name
		end
		state.bundleOffset = offset + length
	else
		compressed = file.Read( state.folder .. "/" .. name, "DATA" )
	end
	if not compressed then return nil, "missing " .. name end
	local decoded = util.Decompress( compressed )
	if not decoded then return nil, "could not decompress " .. name end
	local parsed = util.JSONToTable( decoded )
	if not istable( parsed ) then return nil, "could not parse " .. name end
	return parsed
end

local function EncodeOptionalNumber( value )
	value = tonumber( value )
	return value ~= nil and value or false
end

local function SerializeSampleVertex( vertex )
	local position = vertex and vertex.pos
	if not position then return nil end
	return {
		position.x, position.y, position.z,
		tonumber( vertex.u ) or 0, tonumber( vertex.v ) or 0,
		EncodeWeights( vertex.weights ),
	}
end

local function DeserializeSampleVertex( source )
	if not istable( source ) or #source < 5 then return nil end
	return {
		pos = Vector( source[ 1 ] or 0, source[ 2 ] or 0, source[ 3 ] or 0 ),
		u = tonumber( source[ 4 ] ) or 0,
		v = tonumber( source[ 5 ] ) or 0,
		weights = DecodeWeights( source[ 6 ] ),
	}
end

local function SerializeEligibility( eligibility )
	if not eligibility then return nil end
	local meshGroupIds = {}
	for meshIndex, groupMap in pairs( eligibility.meshGroups or {} ) do
		local ids = {}
		for id, bodygroup in pairs( groupMap or {} ) do
			ids[ #ids + 1 ] = tonumber( bodygroup and bodygroup.id )
				or tonumber( id ) or 0
		end
		table.sort( ids )
		meshGroupIds[ tostring( meshIndex ) ] = ids
	end
	return {
		filterSignature = FilterSignature(),
		selection = eligibility.selection,
		inspectedBodygroups = eligibility.inspectedBodygroups or {},
		meshGroupIds = meshGroupIds,
		meshBodygroupIds = eligibility.meshBodygroupIds or {},
		comparisonCount = eligibility.comparisonCount or 0,
		comparisonBodygroupCount = eligibility.comparisonBodygroupCount or 0,
		failedComparisons = eligibility.failedComparisons or 0,
		ambiguousFingerprints = eligibility.ambiguousFingerprints or 0,
		blockedBodygroupCount = eligibility.blockedBodygroupCount or 0,
		overriddenBodygroupCount = eligibility.overriddenBodygroupCount or 0,
		unresolvedOverrideCount = eligibility.unresolvedOverrideCount or 0,
		combinedComparison = eligibility.combinedComparison == true,
		ownershipMode = eligibility.ownershipMode,
		compiledOwnership = eligibility.compiledOwnership == true,
		compiledOwnershipError = eligibility.compiledOwnershipError,
		compiledBodypartCount = eligibility.compiledBodypartCount or 0,
		compiledMeshCount = eligibility.compiledMeshCount or 0,
		directOwnershipBodygroupCount =
			eligibility.directOwnershipBodygroupCount or 0,
		directOwnedMeshAssignments =
			eligibility.directOwnedMeshAssignments or 0,
	}
end

local function RestoreEligibility( key, source )
	if not source or source.filterSignature ~= FilterSignature() then return end
	local inspected = source.inspectedBodygroups or {}
	local byId = {}
	local hideable = {}
	for _, bodygroup in ipairs( inspected ) do
		local id = tonumber( bodygroup.id ) or 0
		bodygroup.id = id
		byId[ id ] = bodygroup
		if bodygroup.eligible then hideable[ #hideable + 1 ] = bodygroup end
	end
	local meshGroups = {}
	for rawMeshIndex, ids in pairs( source.meshGroupIds or {} ) do
		local groupMap = {}
		for _, rawId in ipairs( ids or {} ) do
			local id = tonumber( rawId ) or 0
			if byId[ id ] then groupMap[ id ] = byId[ id ] end
		end
		if next( groupMap ) ~= nil then
			meshGroups[ tonumber( rawMeshIndex ) or rawMeshIndex ] = groupMap
		end
	end
	local meshBodygroupIds = {}
	for rawMeshIndex, rawBodygroupId in pairs(
		source.meshBodygroupIds or {} ) do
		local meshIndex = tonumber( rawMeshIndex )
		local bodygroupId = tonumber( rawBodygroupId )
		if meshIndex and bodygroupId then
			meshBodygroupIds[ meshIndex ] = bodygroupId
		end
	end
	BBS.HideableMeshCache[ key ] = {
		cacheKey = key,
		selection = source.selection,
		bodygroups = hideable,
		inspectedBodygroups = inspected,
		meshGroups = meshGroups,
		meshBodygroupIds = meshBodygroupIds,
		meshFingerprints = {},
		comparisonCount = source.comparisonCount or 0,
		comparisonBodygroupCount = source.comparisonBodygroupCount or 0,
		failedComparisons = source.failedComparisons or 0,
		ambiguousFingerprints = source.ambiguousFingerprints or 0,
		blockedBodygroupCount = source.blockedBodygroupCount or 0,
		overriddenBodygroupCount = source.overriddenBodygroupCount or 0,
		unresolvedOverrideCount = source.unresolvedOverrideCount or 0,
		combinedComparison = source.combinedComparison == true,
		ownershipMode = source.ownershipMode,
		compiledOwnership = source.compiledOwnership == true,
		compiledOwnershipError = source.compiledOwnershipError,
		compiledBodypartCount = source.compiledBodypartCount or 0,
		compiledMeshCount = source.compiledMeshCount or 0,
		directOwnershipBodygroupCount =
			source.directOwnershipBodygroupCount or 0,
		directOwnedMeshAssignments = source.directOwnedMeshAssignments or 0,
		hideableMeshCount = table.Count( meshGroups ),
		buildMilliseconds = 0,
		persistentCache = true,
	}
end

local function BuildMetadata( meshData, eligibility )
	local modelTime, modelSize = ModelStamp( meshData.model )
	local metadata = {
		format = CACHE_FORMAT,
		complete = false,
		key = meshData.key,
		model = meshData.model,
		modelTime = modelTime,
		modelSize = modelSize,
		lod = meshData.lod,
		bodygroups = meshData.bodygroups,
		skin = meshData.skin,
		totalVertexCount = meshData.totalVertexCount,
		totalSkinVertexCount = meshData.totalSkinVertexCount,
		totalTriangleCount = meshData.totalTriangleCount,
		poses = {},
		meshes = {},
		chunks = {},
		eligibility = SerializeEligibility( eligibility ),
		probe = {
			sampleVertex = SerializeSampleVertex(
				meshData.probe and meshData.probe.sampleVertex ),
			sampleMesh = meshData.probe and meshData.probe.sampleMesh or nil,
			sampleBindIndex = meshData.probe and meshData.probe.sampleBindIndex or nil,
		},
	}
	for boneId, matrix in pairs( meshData.poseToBone or {} ) do
		metadata.poses[ #metadata.poses + 1 ] = {
			bone = boneId,
			matrix = matrix:ToTable(),
		}
	end
	table.sort( metadata.poses,
		function( left, right ) return left.bone < right.bone end )
	for meshIndex, mesh in ipairs( meshData.meshes or {} ) do
		metadata.meshes[ meshIndex ] = {
			meshIndex = mesh.meshIndex or meshIndex,
			material = mesh.material or "",
			sourceKind = mesh.sourceKind or "persistent",
			vertexCount = mesh.persistedVertexCount or #( mesh.vertices or {} ),
			skinVertexCount = #( mesh.skinVertices or {} ),
			triangleCount = #( mesh.triangles or {} ),
			damageFingerprint = mesh.damageFingerprint,
			skinChunks = math.ceil( #( mesh.skinVertices or {} ) / CHUNK_SIZE ),
			triangleChunks = math.ceil( #( mesh.triangles or {} ) / CHUNK_SIZE ),
		}
	end
	return metadata
end

function BBS.QueuePersistentMeshWrite( meshData, eligibility )
	if not GetBool( "bbs_enabled", true )
	or not GetBool( "bbs_mesh_disk_cache", true ) or not meshData then return false end
	local key = meshData.key
	if not key or BBS.PersistentMeshWriteQueued[ key ] then return false end
	local modelTime, modelSize = ModelStamp( meshData.model )
	local filterSignature = FilterSignature()
	local committed = BBS.PersistentMeshCommitted[ key ]
	if committed and committed.modelTime == modelTime
	and committed.modelSize == modelSize
	and committed.filterSignature == filterSignature then return false end
	local existing = file.Read( MetadataPath( key ), "DATA" )
	local parsed = existing and util.JSONToTable( existing ) or nil
	local parsedModelTime = istable( parsed ) and tonumber( parsed.modelTime ) or nil
	local parsedModelSize = istable( parsed ) and tonumber( parsed.modelSize ) or nil
	local geometryCurrent = parsed and parsed.complete
		and parsed.format == CACHE_FORMAT
	and parsed.key == key
	and ( parsed.modelTime == nil or parsedModelTime
		and ( parsedModelTime <= 0 or modelTime <= 0
			or parsedModelTime == modelTime ) )
	and ( parsed.modelSize == nil or parsedModelSize
		and ( parsedModelSize < 0 or modelSize < 0
			or parsedModelSize == modelSize ) )
	and istable( parsed.meshes ) and #parsed.meshes > 0
	if geometryCurrent then
		BBS.PersistentMeshCommitted[ key ] = {
			modelTime = modelTime,
			modelSize = modelSize,
			filterSignature = istable( parsed.eligibility )
				and parsed.eligibility.filterSignature or nil,
		}
	end
	if geometryCurrent and istable( parsed.eligibility )
	and parsed.eligibility.filterSignature == filterSignature then return false end
	if geometryCurrent then
		-- Bodygroup filter changes do not change the immutable model geometry.
		-- Rewrite only the small metadata commit record instead of retaining and
		-- recompressing every vertex/triangle chunk for the model.
		parsed.eligibility = SerializeEligibility( eligibility )
		local updated = util.TableToJSON( parsed, false )
		if updated then
			file.Write( MetadataPath( key ), updated )
			BBS.PersistentMeshCommitted[ key ] = {
				modelTime = modelTime, modelSize = modelSize,
				filterSignature = filterSignature,
			}
			BBS.PersistentMeshStats.metadataUpdates =
				( BBS.PersistentMeshStats.metadataUpdates or 0 ) + 1
			return true
		end
	end
	local maximumQueued = math.Clamp( math.floor(
		GetFloat( "bbs_mesh_cache_write_limit", 3 ) ), 1, 8 )
	if #BBS.PersistentMeshWriteQueue >= maximumQueued then
		-- Preserve the actively-writing head and newest locality. Persistence is a
		-- cache, so superseding an older waiting write is always safer than pinning
		-- another complete processed model through a combat burst.
		if #BBS.PersistentMeshWriteQueue == 1 then
			BBS.PersistentMeshStats.writeDrops =
				( BBS.PersistentMeshStats.writeDrops or 0 ) + 1
			return false
		end
		local dropIndex = 2
		local dropped = table.remove( BBS.PersistentMeshWriteQueue, dropIndex )
		if dropped then
			CloseBundle( dropped )
			BBS.PersistentMeshWriteQueued[ dropped.key ] = nil
			if dropped.writeStarted then
				DiscardMetadata( dropped.key )
			end
			BBS.PersistentMeshStats.writeDrops =
				( BBS.PersistentMeshStats.writeDrops or 0 ) + 1
		end
	end
	BBS.PersistentMeshWriteQueued[ key ] = true
	local activeRTX = BBS.IsActiveRTXRuntime
		and BBS.IsActiveRTXRuntime() or false
	local needsRTXSettle = activeRTX
		and meshData.rtxNativeGraphPending ~= false
		and not meshData.rtxCleanupCompleteAt
	if needsRTXSettle then
		BBS.PersistentMeshStats.rtxSettleQueued =
			( BBS.PersistentMeshStats.rtxSettleQueued or 0 ) + 1
	end
	BBS.PersistentMeshWriteQueue[ #BBS.PersistentMeshWriteQueue + 1 ] = {
		runtimeFormat = PERSISTENT_RUNTIME_FORMAT,
		key = key,
		meshData = meshData,
		eligibility = eligibility,
		folder = CacheFolder( key ),
		-- RTX models can already occupy several gigabytes of renderer memory.  The
		-- cold util.GetModelMeshes graph and the source-vertex fingerprints become
		-- unreachable immediately before this queue entry is created; starting JSON
		-- and compression work before Lua passes two GC-cycle boundaries made those
		-- dead graphs overlap the entire writer. Shorekeeper reproducibly crashed client.dll in
		-- that window.  Vanilla keeps the original immediate writer path.
		rtxRuntime = activeRTX,
		rtxSettleUntil = needsRTXSettle and SysTime() + 0.5 or nil,
		rtxSettleFrames = 0,
		rtxGCCycles = 0,
		rtxGCProbe = needsRTXSettle
			and setmetatable( { {} }, { __mode = "v" } ) or nil,
		stage = needsRTXSettle and "rtx_settle" or "init",
		meshIndex = 1,
	}
	return true
end

local function FailWrite( job, reason )
	CloseBundle( job )
	if job.writeStarted then DiscardMetadata( job.key ) end
	BBS.PersistentMeshWriteQueued[ job.key ] = nil
	BBS.PersistentMeshStats.writeFailures =
		( BBS.PersistentMeshStats.writeFailures or 0 ) + 1
	job.done = true
	job.error = reason
end

local function ContinueWrite( job )
	if job.runtimeFormat ~= PERSISTENT_RUNTIME_FORMAT then
		return FailWrite( job, "obsolete in-memory persistent-cache writer" )
	end
	if job.stage == "rtx_settle" then
		job.rtxSettleFrames = ( job.rtxSettleFrames or 0 ) + 1
		-- One bounded step per real Source frame.  Do not use a full collection:
		-- weak RTX clients should take more frames, never receive one large hitch.
		if ( job.rtxGCCycles or 0 ) < 2 then
			collectgarbage( "step", 256 )
			if not job.rtxGCProbe[ 1 ] then
				job.rtxGCCycles = ( job.rtxGCCycles or 0 ) + 1
				if job.rtxGCCycles < 2 then
					job.rtxGCProbe =
						setmetatable( { {} }, { __mode = "v" } )
				else
					job.rtxGCProbe = nil
				end
			end
		end
		if ( job.rtxGCCycles or 0 ) >= 2 and job.rtxSettleFrames >= 8
		and SysTime() >= ( job.rtxSettleUntil or 0 ) then
			job.stage = "init"
			BBS.PersistentMeshStats.rtxSettleCompleted =
				( BBS.PersistentMeshStats.rtxSettleCompleted or 0 ) + 1
			BBS.PersistentMeshStats.rtxSettleFrames =
				( BBS.PersistentMeshStats.rtxSettleFrames or 0 )
				+ job.rtxSettleFrames
		end
		return
	end
	if job.stage == "init" then
		-- metadata.json is the commit record. Remove it before replacing any
		-- same-named chunk so a crash cannot leave a valid header over mixed data.
		DiscardMetadata( job.key )
		job.writeStarted = true
		file.CreateDir( "bbs_mesh_cache" )
		file.CreateDir( CACHE_ROOT )
		file.CreateDir( job.folder )
		job.metadata = BuildMetadata( job.meshData, job.eligibility )
		job.bundleFile = file.Open( job.folder .. "/" .. BUNDLE_NAME, "wb", "DATA" )
		if not job.bundleFile then return FailWrite( job, "could not open geometry bundle" ) end
		job.bundleBytes = 0
		job.stage = "mesh_init"
		return
	end
	local mesh = job.meshData.meshes[ job.meshIndex ]
	local descriptor = job.metadata.meshes[ job.meshIndex ]
	if not mesh then
		CloseBundle( job )
		if file.Size( job.folder .. "/" .. BUNDLE_NAME, "DATA" ) ~= job.bundleBytes then
			return FailWrite( job, "geometry bundle was not completely saved" )
		end
		job.metadata.bundleBytes = job.bundleBytes
		job.metadata.complete = true
		local encoded = util.TableToJSON( job.metadata, false )
		if not encoded then return FailWrite( job, "metadata JSON encoding failed" ) end
		file.Write( job.folder .. "/metadata.json", encoded )
		BBS.PersistentMeshCommitted[ job.key ] = {
			modelTime = job.metadata.modelTime,
			modelSize = job.metadata.modelSize,
			filterSignature = job.metadata.eligibility
				and job.metadata.eligibility.filterSignature or nil,
		}
		BBS.PersistentMeshWriteQueued[ job.key ] = nil
		BBS.PersistentMeshStats.written =
			( BBS.PersistentMeshStats.written or 0 ) + 1
		job.done = true
		return
	end
	if job.stage == "mesh_init" then
		job.skinLookup = {}
		job.offset = 1
		job.chunk = 1
		job.stage = "skin_index"
		return
	end
	if job.stage == "skin_index" then
		local last = math.min(
			job.offset + INDEX_ROWS_PER_STEP - 1, #mesh.skinVertices )
		for index = job.offset, last do job.skinLookup[ mesh.skinVertices[ index ] ] = index end
		job.offset = last + 1
		if job.offset > #mesh.skinVertices then
			job.offset = 1
			job.chunk = 1
			job.output = nil
			job.chunkLast = nil
			job.buildIndex = nil
			job.pendingChunk = nil
			job.stage = "skin_write"
		end
		return
	end
	if job.stage == "skin_write" then
		if job.pendingChunk then
			local name = string.format(
				"m%03d_s%04d.dat", job.meshIndex, job.chunk )
			local ok, reason = WriteChunk( job, name, job.output )
			if not ok then return FailWrite( job, reason ) end
			BBS.PersistentMeshStats.chunksWritten =
				( BBS.PersistentMeshStats.chunksWritten or 0 ) + 1
			job.offset = job.chunkLast + 1
			job.chunk = job.chunk + 1
			job.output = nil
			job.chunkLast = nil
			job.buildIndex = nil
			job.pendingChunk = nil
			return
		end
		if job.offset > #mesh.skinVertices then
			job.offset = 1
			job.chunk = 1
			job.stage = "triangle_write"
			return
		end
		if not job.output then
			job.output = {}
			job.chunkLast = math.min(
				job.offset + CHUNK_SIZE - 1, #mesh.skinVertices )
			job.buildIndex = job.offset
		end
		local last = math.min( job.buildIndex + WRITE_ROWS_PER_STEP - 1,
			job.chunkLast )
		for index = job.buildIndex, last do
			local skinVertex = mesh.skinVertices[ index ]
			local position = skinVertex.position
			job.output[ #job.output + 1 ] = {
				position.x, position.y, position.z,
				EncodeWeights( skinVertex.weights ),
			}
		end
		job.buildIndex = last + 1
		if job.buildIndex > job.chunkLast then job.pendingChunk = true end
		return
	end
	if job.stage == "triangle_write" then
		if job.pendingChunk then
			local name = string.format(
				"m%03d_t%04d.dat", job.meshIndex, job.chunk )
			local ok, reason = WriteChunk( job, name, job.output )
			if not ok then return FailWrite( job, reason ) end
			BBS.PersistentMeshStats.chunksWritten =
				( BBS.PersistentMeshStats.chunksWritten or 0 ) + 1
			job.offset = job.chunkLast + 1
			job.chunk = job.chunk + 1
			job.output = nil
			job.chunkLast = nil
			job.buildIndex = nil
			job.pendingChunk = nil
			return
		end
		if job.offset > #mesh.triangles then
			job.meshIndex = job.meshIndex + 1
			job.stage = "mesh_init"
			job.skinLookup = nil
			return
		end
		if not job.output then
			job.output = {}
			job.chunkLast = math.min(
				job.offset + CHUNK_SIZE - 1, #mesh.triangles )
			job.buildIndex = job.offset
		end
		local last = math.min( job.buildIndex + WRITE_ROWS_PER_STEP - 1,
			job.chunkLast )
		for index = job.buildIndex, last do
			local triangle = mesh.triangles[ index ]
			local firstId = triangle[ 1 ] and job.skinLookup[ triangle[ 1 ] ]
			local secondId = triangle[ 4 ] and job.skinLookup[ triangle[ 4 ] ]
			local thirdId = triangle[ 7 ] and job.skinLookup[ triangle[ 7 ] ]
			if not firstId or not secondId or not thirdId then
				return FailWrite( job,
					"triangle references a skin point outside its mesh" )
			end
			job.output[ #job.output + 1 ] = {
				firstId, EncodeOptionalNumber( triangle[ 2 ] ),
					EncodeOptionalNumber( triangle[ 3 ] ),
				secondId, EncodeOptionalNumber( triangle[ 5 ] ),
					EncodeOptionalNumber( triangle[ 6 ] ),
				thirdId, EncodeOptionalNumber( triangle[ 8 ] ),
					EncodeOptionalNumber( triangle[ 9 ] ),
			}
		end
		job.buildIndex = last + 1
		if job.buildIndex > job.chunkLast then job.pendingChunk = true end
	end
end

hook.Add( "Think", "BBS.WritePersistentMeshCache", function()
	if not GetBool( "bbs_enabled", true )
	or not GetBool( "bbs_mesh_disk_cache", true ) then return end
	if #( BBS.MeshQueryQueue or {} ) > 0
	or #( BBS.DamagePaintQueue or {} ) > 0 then return end
	local waitingPreparation = BBS.MeshPrewarmQueue and BBS.MeshPrewarmQueue[ 1 ]
	if waitingPreparation
	and ( waitingPreparation.urgent or FrameNumber() % 2 == 1
		or BBS.MeshPreparationHasPriority
			and BBS.MeshPreparationHasPriority( waitingPreparation ) ) then return end
	local job = BBS.PersistentMeshWriteQueue[ 1 ]
	if not job then return end
	if job.rtxRuntime
	and FrameNumber() < ( job.rtxNextWriterFrame or 0 ) then return end
	if BBS.TryBeginHeavyFrame
	and not BBS.TryBeginHeavyFrame( "mesh-persistence" ) then return end
	if job.rtxRuntime and job.rtxChunkGCPending then
		-- Give collection its own scheduled heavy frame instead of appending an
		-- unmeasured root scan after the writer's deadline on a weak client.
		local gcStarted = SysTime()
		collectgarbage( "step", 128 )
		local gcElapsed = ( SysTime() - gcStarted ) * 1000
		job.processingMilliseconds = ( job.processingMilliseconds or 0 )
			+ gcElapsed
		job.rtxChunkGCPending = false
		BBS.PersistentMeshStats.rtxChunkGCSteps =
			( BBS.PersistentMeshStats.rtxChunkGCSteps or 0 ) + 1
		BBS.PersistentMeshStats.rtxChunkGCMilliseconds =
			( BBS.PersistentMeshStats.rtxChunkGCMilliseconds or 0 )
			+ gcElapsed
		job.rtxNextWriterFrame = FrameNumber() + 1
		return
	end
	if job.rtxRuntime and job.stage == "rtx_settle" then
		local stepStarted = SysTime()
		local ok, reason = pcall( ContinueWrite, job )
		job.processingMilliseconds = ( job.processingMilliseconds or 0 )
			+ ( SysTime() - stepStarted ) * 1000
		job.processingSteps = ( job.processingSteps or 0 ) + 1
		if not ok then FailWrite( job, tostring( reason ) ) end
		if job.done then
			table.remove( BBS.PersistentMeshWriteQueue, 1 )
			if BBS.TrimModelMeshCache then BBS.TrimModelMeshCache() end
		end
		return
	end
	local deadline = SysTime() + PersistentWriteBudget( job ) / 1000
	local chunksBefore = BBS.PersistentMeshStats.chunksWritten or 0
	repeat
		local stepStarted = SysTime()
		local ok, reason = pcall( ContinueWrite, job )
		job.processingMilliseconds = ( job.processingMilliseconds or 0 )
			+ ( SysTime() - stepStarted ) * 1000
		job.processingSteps = ( job.processingSteps or 0 ) + 1
		if not ok then FailWrite( job, tostring( reason ) ) end
	until job.done or SysTime() >= deadline
		or ( job.rtxRuntime
			and ( BBS.PersistentMeshStats.chunksWritten or 0 ) > chunksBefore )
	if job.rtxRuntime
	and ( BBS.PersistentMeshStats.chunksWritten or 0 ) > chunksBefore then
		-- JSON, compressed strings, and the 512-row output table are all dead after
		-- a flush.  Reclaim them continuously instead of retaining hundreds of
		-- chunks until the commit file is finally written.
		job.rtxChunkGCPending = true
		job.rtxNextWriterFrame = FrameNumber() + 1
	end
	if job.done then
		table.remove( BBS.PersistentMeshWriteQueue, 1 )
		if BBS.TrimModelMeshCache then BBS.TrimModelMeshCache() end
	end
end )

function BBS.CancelPersistentMeshLoad( state )
	if not state then return end
	CloseBundle( state )
	state.cancelled = true
	if BBS.PersistentMeshLoads[ state.key ] == state then
		BBS.PersistentMeshLoads[ state.key ] = nil
	end
end

BBS.CancelPersistentMeshWork = function( discardPartialWrites )
	for _, job in ipairs( BBS.PersistentMeshWriteQueue or {} ) do
		CloseBundle( job )
		if discardPartialWrites and job.writeStarted then
			DiscardMetadata( job.key )
		end
	end
	for _, state in pairs( BBS.PersistentMeshLoads or {} ) do
		BBS.CancelPersistentMeshLoad( state )
	end
	BBS.PersistentMeshLoads = {}
	BBS.PersistentMeshWriteQueue = {}
	BBS.PersistentMeshWriteQueued = {}
	if BBS.TrimModelMeshCache then BBS.TrimModelMeshCache() end
end

cvars.AddChangeCallback( "bbs_mesh_disk_cache", function( _, _, newValue )
	if tonumber( newValue ) ~= 0 then return end
	BBS.CancelPersistentMeshWork( true )
end, "BBS.ReleaseDisabledPersistentMeshWrites" )

local function CollectVertexBones( target, skin )
	local weights = skin and skin.weights
	if not weights or #weights == 0 then target[ 0 ] = true return end
	if isnumber( weights[ 1 ] ) then
		for index = 1, #weights - 1, 2 do
			if ( tonumber( weights[ index + 1 ] ) or 0 ) > 0 then
				target[ tonumber( weights[ index ] ) or 0 ] = true
			end
		end
		return
	end
	for _, boneWeight in ipairs( weights ) do
		if ( boneWeight.weight or 0 ) > 0 then
			target[ boneWeight.bone or 0 ] = true
		end
	end
end

local function PackedRigidBone( weights )
	if not weights or #weights == 0 then return 0 end
	local rigidBone
	for index = 1, #weights - 1, 2 do
		local bone = tonumber( weights[ index ] ) or 0
		if ( tonumber( weights[ index + 1 ] ) or 0 ) > 0 then
			if rigidBone == nil then rigidBone = bone
			elseif rigidBone ~= bone then return false end
		end
	end
	return rigidBone == nil and 0 or rigidBone
end

local function TriangleModelSphere( first, second, third )
	local a, b, c = first.position, second.position, third.position
	local center = Vector( ( a.x + b.x + c.x ) / 3,
		( a.y + b.y + c.y ) / 3, ( a.z + b.z + c.z ) / 3 )
	return center, math.sqrt( math.max( center:DistToSqr( a ),
		center:DistToSqr( b ), center:DistToSqr( c ) ) )
end

local function FailLoad( state, reason )
	CloseBundle( state )
	state.done = true
	state.error = reason
	BBS.PersistentMeshLoads[ state.key ] = nil
	BBS.PersistentMeshStats.loadFailures =
		( BBS.PersistentMeshStats.loadFailures or 0 ) + 1
	DiscardMetadata( state.key, state.cacheRoot )
	return true, nil, reason
end

function BBS.AbortPersistentMeshLoad( state, reason )
	if not state then return true, nil, reason end
	return FailLoad( state, reason or "persistent mesh hydration was aborted" )
end

function BBS.BeginPersistentMeshLoadForIdentity(
	key, model, bodygroups, skin, lod )
	if not GetBool( "bbs_enabled", true )
	or not GetBool( "bbs_mesh_disk_cache", true ) or not key then return nil end
	if not key or BBS.ModelMeshCache[ key ] ~= nil then return nil end
	if BBS.PersistentMeshLoads[ key ] then return BBS.PersistentMeshLoads[ key ] end
	local cacheRoot = CACHE_ROOT
	local encoded = file.Read( MetadataPath( key, cacheRoot ), "DATA" )
	if not encoded then
		cacheRoot = PREVIOUS_CACHE_ROOT
		encoded = file.Read( MetadataPath( key, cacheRoot ), "DATA" )
	end
	if not encoded then
		cacheRoot = LEGACY_CACHE_ROOT
		encoded = file.Read( MetadataPath( key, cacheRoot ), "DATA" )
	end
	if not encoded then
		cacheRoot = OLDER_CACHE_ROOT
		encoded = file.Read( MetadataPath( key, cacheRoot ), "DATA" )
	end
	local metadata = encoded and util.JSONToTable( encoded ) or nil
	local metadataFormat = istable( metadata ) and tonumber( metadata.format ) or nil
	local cacheChunkSize = metadataFormat == LEGACY_CACHE_FORMAT
		and LEGACY_CHUNK_SIZE or metadataFormat == OLDER_CACHE_FORMAT
		and OLDER_CHUNK_SIZE or CHUNK_SIZE
	if not istable( metadata ) or not metadata.complete
	or ( metadataFormat ~= CACHE_FORMAT
		and metadataFormat ~= PREVIOUS_CACHE_FORMAT
		and metadataFormat ~= LEGACY_CACHE_FORMAT
		and metadataFormat ~= OLDER_CACHE_FORMAT ) or metadata.key ~= key
	or not istable( metadata.meshes ) or #metadata.meshes == 0
	or ( metadata.poses ~= nil and not istable( metadata.poses ) )
	or ( metadata.probe ~= nil and not istable( metadata.probe ) )
	or ( metadata.eligibility ~= nil and not istable( metadata.eligibility ) ) then
		if encoded then DiscardMetadata( key, cacheRoot ) end
		return nil
	end
	if metadataFormat == CACHE_FORMAT then
		local bundleBytes = tonumber( metadata.bundleBytes )
		if not istable( metadata.chunks ) or not bundleBytes
		or bundleBytes < 0 or bundleBytes % 1 ~= 0 then
			DiscardMetadata( key, cacheRoot )
			return nil
		end
		metadata.bundleBytes = bundleBytes
	end
	local descriptorVertexTotal, descriptorSkinTotal, descriptorTriangleTotal = 0, 0, 0
	for _, descriptor in ipairs( metadata.meshes ) do
		local vertexCount = istable( descriptor )
			and tonumber( descriptor.vertexCount ) or nil
		local skinVertexCount = istable( descriptor )
			and tonumber( descriptor.skinVertexCount ) or nil
		local triangleCount = istable( descriptor )
			and tonumber( descriptor.triangleCount ) or nil
		local skinChunks = istable( descriptor )
			and tonumber( descriptor.skinChunks ) or nil
		local triangleChunks = istable( descriptor )
			and tonumber( descriptor.triangleChunks ) or nil
		if not istable( descriptor ) or vertexCount == nil
		or skinVertexCount == nil or triangleCount == nil
		or skinChunks == nil or triangleChunks == nil
		or vertexCount < 0 or skinVertexCount < 0 or triangleCount < 0
		or skinChunks < 0 or triangleChunks < 0
		or vertexCount % 1 ~= 0 or skinVertexCount % 1 ~= 0
		or triangleCount % 1 ~= 0 or skinChunks % 1 ~= 0
		or triangleChunks % 1 ~= 0
		or skinChunks ~= math.ceil( skinVertexCount / cacheChunkSize )
		or triangleChunks ~= math.ceil( triangleCount / cacheChunkSize )
		or descriptor.damageFingerprint == nil then
			DiscardMetadata( key, cacheRoot )
			return nil
		end
		descriptor.vertexCount = vertexCount
		descriptor.skinVertexCount = skinVertexCount
		descriptor.triangleCount = triangleCount
		descriptor.skinChunks = skinChunks
		descriptor.triangleChunks = triangleChunks
		descriptorVertexTotal = descriptorVertexTotal + vertexCount
		descriptorSkinTotal = descriptorSkinTotal + skinVertexCount
		descriptorTriangleTotal = descriptorTriangleTotal + triangleCount
	end
	local totalVertexCount = tonumber( metadata.totalVertexCount )
	local totalSkinVertexCount = tonumber( metadata.totalSkinVertexCount )
	local totalTriangleCount = tonumber( metadata.totalTriangleCount )
	if totalVertexCount ~= descriptorVertexTotal
	or totalSkinVertexCount ~= descriptorSkinTotal
	or totalTriangleCount ~= descriptorTriangleTotal then
		DiscardMetadata( key, cacheRoot )
		return nil
	end
	metadata.totalVertexCount = totalVertexCount
	metadata.totalSkinVertexCount = totalSkinVertexCount
	metadata.totalTriangleCount = totalTriangleCount
	local storedModelTime = metadata.modelTime ~= nil
		and tonumber( metadata.modelTime ) or nil
	local storedModelSize = metadata.modelSize ~= nil
		and tonumber( metadata.modelSize ) or nil
	if ( metadata.modelTime ~= nil and storedModelTime == nil )
	or ( metadata.modelSize ~= nil and storedModelSize == nil ) then
		DiscardMetadata( key, cacheRoot )
		return nil
	end
	local modelTime, modelSize = ModelStamp( model )
	if storedModelTime and storedModelTime > 0 and modelTime > 0
	and storedModelTime ~= modelTime then
		DiscardMetadata( key, cacheRoot ) return nil
	end
	if storedModelSize and storedModelSize >= 0 and modelSize >= 0
	and storedModelSize ~= modelSize then
		DiscardMetadata( key, cacheRoot ) return nil
	end
	if metadataFormat == CACHE_FORMAT then
		BBS.PersistentMeshCommitted[ key ] = {
			modelTime = modelTime,
			modelSize = modelSize,
			filterSignature = metadata.eligibility
				and metadata.eligibility.filterSignature or nil,
		}
	end

	local poseToBone = {}
	local inversePoseToBone = {}
	for _, record in ipairs( metadata.poses or {} ) do
		if not istable( record ) or not istable( record.matrix )
		or tonumber( record.bone ) == nil then
			DiscardMetadata( key, cacheRoot )
			return nil
		end
		local ok, matrix = pcall( Matrix, record.matrix )
		if ok and matrix then
			local boneId = tonumber( record.bone ) or 0
			poseToBone[ boneId ] = matrix
			inversePoseToBone[ boneId ] = matrix:GetInverseTR()
		end
	end
	if #( metadata.poses or {} ) > 0 and table.Count( poseToBone ) == 0 then
		DiscardMetadata( key, cacheRoot )
		return nil
	end
	local data = {
		key = key,
		model = model,
		lod = lod or 0,
		bodygroups = bodygroups,
		skin = skin,
		poseToBone = poseToBone,
		inversePoseToBone = inversePoseToBone,
		meshes = {},
		boneTriangles = {},
		boneTriangleStride = 6,
		boneMeshBounds = {},
		spatialIndexedTriangleCount = 0,
		spatialUnindexedTriangleCount = 0,
		totalVertexCount = metadata.totalVertexCount or 0,
		totalSkinVertexCount = metadata.totalSkinVertexCount or 0,
		totalTriangleCount = metadata.totalTriangleCount or 0,
		buildMilliseconds = 0,
		persistentCache = true,
		persistentCacheFormat = metadataFormat,
		probe = {
			sampleVertex = DeserializeSampleVertex(
				metadata.probe and metadata.probe.sampleVertex ),
			sampleMesh = metadata.probe and metadata.probe.sampleMesh or nil,
			sampleBindIndex = metadata.probe and metadata.probe.sampleBindIndex or nil,
		},
	}
	for meshIndex, descriptor in ipairs( metadata.meshes or {} ) do
		data.meshes[ meshIndex ] = {
			meshIndex = descriptor.meshIndex or meshIndex,
			material = descriptor.material or "",
			sourceKind = descriptor.sourceKind or "persistent",
			persistedVertexCount = descriptor.vertexCount or 0,
			vertices = {},
			skinVertices = {},
			triangles = {},
			spatialFallbackGroups = {},
			_spatialFallbackLookup = {},
			damageFingerprint = descriptor.damageFingerprint,
		}
	end
	local state = {
		runtimeFormat = PERSISTENT_RUNTIME_FORMAT,
		key = key,
		folder = CacheFolder( key, cacheRoot ),
		cacheRoot = cacheRoot,
		cacheFormat = metadataFormat,
		chunkSize = cacheChunkSize,
		metadata = metadata,
		data = data,
		meshIndex = 1,
		stage = "skin",
		chunk = 1,
		startedAt = SysTime(),
	}
	BBS.PersistentMeshLoads[ key ] = state
	return state
end

function BBS.BeginPersistentMeshLoad( entity, lod )
	if not IsValid( entity ) then return nil end
	lod = lod or 0
	local key, model, bodygroups, skin =
		BBS.GetModelMeshCacheIdentity( entity, lod )
	return BBS.BeginPersistentMeshLoadForIdentity(
		key, model, bodygroups, skin, lod )
end

function BBS.ContinuePersistentMeshLoad( state )
	if not state then return true, nil, "invalid persistent load state" end
	if state.cancelled then
		CloseBundle( state )
		return true, nil, "persistent load was cancelled"
	end
	if state.runtimeFormat ~= PERSISTENT_RUNTIME_FORMAT then
		CloseBundle( state )
		BBS.PersistentMeshLoads[ state.key ] = nil
		return true, nil, "obsolete in-memory persistent-cache loader"
	end
	if state.done then return true, state.data, state.error end
	local descriptor = state.metadata.meshes[ state.meshIndex ]
	local mesh = state.data.meshes[ state.meshIndex ]
	if not descriptor then
		CloseBundle( state )
		if state.cacheFormat == CACHE_FORMAT
		and ( state.bundleOffset or 0 ) ~= state.metadata.bundleBytes then
			return FailLoad( state, "geometry bundle contains unconsumed data" )
		end
		local loadedVertices, loadedSkinVertices, loadedTriangles = 0, 0, 0
		for _, loadedMesh in ipairs( state.data.meshes or {} ) do
			loadedVertices = loadedVertices
				+ ( tonumber( loadedMesh.persistedVertexCount ) or 0 )
			loadedSkinVertices = loadedSkinVertices
				+ #( loadedMesh.skinVertices or {} )
			loadedTriangles = loadedTriangles + #( loadedMesh.triangles or {} )
		end
		if loadedVertices ~= ( tonumber( state.metadata.totalVertexCount ) or -1 )
		or loadedSkinVertices
			~= ( tonumber( state.metadata.totalSkinVertexCount ) or -1 )
		or loadedTriangles
			~= ( tonumber( state.metadata.totalTriangleCount ) or -1 ) then
			return FailLoad( state,
				"persistent mesh totals do not match committed metadata" )
		end
		state.data.buildMilliseconds = ( SysTime() - state.startedAt ) * 1000
		if BBS.TouchModelMeshCache then BBS.TouchModelMeshCache( state.data ) end
		BBS.ModelMeshCache[ state.key ] = state.data
		if BBS.TrimModelMeshCache then BBS.TrimModelMeshCache( state.key ) end
		BBS.ModelMeshCacheStats.builds = ( BBS.ModelMeshCacheStats.builds or 0 ) + 1
		RestoreEligibility( state.key, state.metadata.eligibility )
		BBS.PersistentMeshLoads[ state.key ] = nil
		BBS.PersistentMeshStats.loaded = ( BBS.PersistentMeshStats.loaded or 0 ) + 1
		state.rows, state.boneScratch = nil, nil
		state.done = true
		return true, state.data
	end

	if state.stage == "skin" then
		if state.chunk > ( descriptor.skinChunks or 0 ) then
			if #mesh.skinVertices ~= descriptor.skinVertexCount then
				return FailLoad( state,
					"persistent skin-point count does not match mesh descriptor" )
			end
			state.stage = "triangles"
			state.chunk = 1
			state.rows, state.rowIndex, state.rowName = nil, nil, nil
			return false
		end
		local name = string.format( "m%03d_s%04d.dat", state.meshIndex, state.chunk )
		if not state.rows then
			local rows, reason = ReadChunk( state, name )
			if not rows then return FailLoad( state, reason ) end
			state.rows, state.rowIndex, state.rowName = rows, 1, name
		end
		local lastRow = math.min( #state.rows,
			( state.rowIndex or 1 ) + HYDRATE_ROWS_PER_STEP - 1 )
		for rowIndex = state.rowIndex or 1, lastRow do
			local row = state.rows[ rowIndex ]
			if not istable( row ) or #row < 4 then
				return FailLoad( state, "invalid skin row in " .. state.rowName )
			end
			local x, y, z = tonumber( row[ 1 ] ),
				tonumber( row[ 2 ] ), tonumber( row[ 3 ] )
			local weights = DecodeWeightsChecked( row[ 4 ] )
			if x == nil or y == nil or z == nil or x ~= x or y ~= y or z ~= z
			or not weights then
				return FailLoad( state,
					"invalid skin scalar/weights in " .. state.rowName )
			end
			-- Retain the decoded row itself as the runtime skin point. The chunk's
			-- outer array can still be released below, while this avoids another
			-- wrapper allocation for every unique skinned position.
			local skinVertex = row
			skinVertex.position = Vector( x, y, z )
			skinVertex.weights = weights
			skinVertex.rigidBone = PackedRigidBone( weights )
			skinVertex[ 1 ], skinVertex[ 2 ], skinVertex[ 3 ], skinVertex[ 4 ] =
				nil, nil, nil, nil
			mesh.skinVertices[ #mesh.skinVertices + 1 ] = skinVertex
		end
		state.rowIndex = lastRow + 1
		if state.rowIndex <= #state.rows then return false end
		state.rows, state.rowIndex, state.rowName = nil, nil, nil
		state.chunk = state.chunk + 1
		BBS.PersistentMeshStats.chunksRead =
			( BBS.PersistentMeshStats.chunksRead or 0 ) + 1
		return false
	end

	if state.chunk > ( descriptor.triangleChunks or 0 ) then
		if #mesh.triangles ~= descriptor.triangleCount then
			return FailLoad( state,
				"persistent triangle count does not match mesh descriptor" )
		end
		if BBS.FinalizeSpatialFallbackGroups then
			BBS.FinalizeSpatialFallbackGroups( mesh )
		end
		mesh._spatialFallbackLookup = nil
		state.meshIndex = state.meshIndex + 1
		state.stage = "skin"
		state.chunk = 1
		state.rows, state.rowIndex, state.rowName = nil, nil, nil
		return false
	end
	local name = string.format( "m%03d_t%04d.dat", state.meshIndex, state.chunk )
	if not state.rows then
		local rows, reason = ReadChunk( state, name )
		if not rows then return FailLoad( state, reason ) end
		state.rows, state.rowIndex, state.rowName = rows, 1, name
	end
	local lastRow = math.min( #state.rows,
		( state.rowIndex or 1 ) + HYDRATE_ROWS_PER_STEP - 1 )
	for rowIndex = state.rowIndex or 1, lastRow do
		local row = state.rows[ rowIndex ]
		if not istable( row ) or #row < 9 then
			return FailLoad( state, "invalid triangle row in " .. state.rowName )
		end
		local firstId, secondId, thirdId = tonumber( row[ 1 ] ),
			tonumber( row[ 4 ] ), tonumber( row[ 7 ] )
		if not firstId or not secondId or not thirdId
		or firstId % 1 ~= 0 or secondId % 1 ~= 0 or thirdId % 1 ~= 0
		or ( row[ 2 ] ~= false and not isnumber( row[ 2 ] ) )
		or ( row[ 3 ] ~= false and not isnumber( row[ 3 ] ) )
		or ( row[ 5 ] ~= false and not isnumber( row[ 5 ] ) )
		or ( row[ 6 ] ~= false and not isnumber( row[ 6 ] ) )
		or ( row[ 8 ] ~= false and not isnumber( row[ 8 ] ) )
		or ( row[ 9 ] ~= false and not isnumber( row[ 9 ] ) ) then
			return FailLoad( state,
				"invalid triangle scalar in " .. state.rowName )
		end
		local first = mesh.skinVertices[ firstId ]
		local second = mesh.skinVertices[ secondId ]
		local third = mesh.skinVertices[ thirdId ]
		if not first or not second or not third then
			return FailLoad( state, "triangle references a missing skin vertex" )
		end
		local triangleIndex = #mesh.triangles + 1
		-- The disk row is already the compact nine-slot runtime layout. Replace
		-- its three integer IDs with skin references and keep the validated UV
		-- scalars in place, eliminating one more allocation per triangle.
		local cachedTriangle = row
		cachedTriangle.triangleIndex = triangleIndex
		cachedTriangle[ 1 ], cachedTriangle[ 4 ], cachedTriangle[ 7 ] =
			first, second, third
		mesh.triangles[ triangleIndex ] = cachedTriangle
		local rigidBone = isnumber( first.rigidBone )
			and first.rigidBone == second.rigidBone
			and first.rigidBone == third.rigidBone
			and first.rigidBone or nil
		if rigidBone ~= nil then
			local modelCenter, modelRadius = TriangleModelSphere(
				first, second, third )
			local pose = state.data.poseToBone[ rigidBone ]
			local center = pose and pose * modelCenter or nil
			if center then
				if BBS.ExpandBoneMeshTriangleBounds then
					if BBS.ExpandBoneMeshTriangleBoundsScalar then
						BBS.ExpandBoneMeshTriangleBounds( state.data, rigidBone,
							mesh.meshIndex, center.x, center.y, center.z,
							modelRadius )
					else
						-- A single-file auto-refresh can briefly leave the older
						-- table-signature helper alive. Keep hydration correct until
						-- cl_30 reloads and publishes the scalar capability flag.
						BBS.ExpandBoneMeshTriangleBounds( state.data, rigidBone,
							mesh.meshIndex, { x = center.x, y = center.y,
								z = center.z, radius = modelRadius } )
					end
				end
				local entries = state.data.boneTriangles[ rigidBone ] or {}
				state.data.boneTriangles[ rigidBone ] = entries
				local offset = #entries
				entries[ offset + 1 ], entries[ offset + 2 ] =
					mesh, cachedTriangle
				entries[ offset + 3 ], entries[ offset + 4 ] =
					center.x, center.y
				entries[ offset + 5 ], entries[ offset + 6 ] =
					center.z, modelRadius
				state.data.spatialIndexedTriangleCount =
					state.data.spatialIndexedTriangleCount + 1
			else
				rigidBone = nil
			end
		end
		if rigidBone == nil then
			local bones = state.boneScratch or {}
			state.boneScratch = bones
			for boneId in pairs( bones ) do bones[ boneId ] = nil end
			CollectVertexBones( bones, first )
			CollectVertexBones( bones, second )
			CollectVertexBones( bones, third )
			if BBS.AddSpatialFallbackTriangle then
				BBS.AddSpatialFallbackTriangle( mesh,
					mesh._spatialFallbackLookup, bones, cachedTriangle,
					first.position, second.position, third.position )
			else
				return FailLoad( state,
					"runtime fallback-group builder is unavailable" )
			end
			state.data.spatialUnindexedTriangleCount =
				state.data.spatialUnindexedTriangleCount + 1
		end
	end
	state.rowIndex = lastRow + 1
	if state.rowIndex <= #state.rows then return false end
	state.rows, state.rowIndex, state.rowName = nil, nil, nil
	state.chunk = state.chunk + 1
	BBS.PersistentMeshStats.chunksRead =
		( BBS.PersistentMeshStats.chunksRead or 0 ) + 1
	return false
end

local function DeletePersistentCacheFiles()
	local deleted = 0
	local _, versions = file.Find( "bbs_mesh_cache/*", "DATA" )
	for _, version in ipairs( versions or {} ) do
		local versionRoot = "bbs_mesh_cache/" .. version
		local rootFiles, folders = file.Find( versionRoot .. "/*", "DATA" )
		for _, name in ipairs( rootFiles or {} ) do
			file.Delete( versionRoot .. "/" .. name )
			deleted = deleted + 1
		end
		for _, folder in ipairs( folders or {} ) do
			local files = file.Find(
				versionRoot .. "/" .. folder .. "/*", "DATA" )
			for _, name in ipairs( files or {} ) do
				file.Delete( versionRoot .. "/" .. folder .. "/" .. name )
				deleted = deleted + 1
			end
		end
	end
	return deleted
end

concommand.Add( "bbs_mesh_disk_cache_clear", function()
	BBS.CancelPersistentMeshWork( true )
	BBS.PersistentMeshCommitted = {}
	BBS.Log( "cleared %d persistent mesh-cache files", DeletePersistentCacheFiles() )
end, nil, "Delete processed model mesh caches stored in data/bbs_mesh_cache." )

concommand.Add( "bbs_mesh_disk_cache_status", function()
	local stats = BBS.PersistentMeshStats
	BBS.Log( "persistent mesh cache: format=%d loads=%d writes=%d metadataUpdates=%d loadFailures=%d writeFailures=%d writeDrops=%d chunksRead=%d chunksWritten=%d activeLoads=%d queuedWrites=%d root=data/%s",
		CACHE_FORMAT, stats.loaded or 0, stats.written or 0,
		stats.metadataUpdates or 0,
		stats.loadFailures or 0, stats.writeFailures or 0,
		stats.writeDrops or 0,
		stats.chunksRead or 0, stats.chunksWritten or 0,
		table.Count( BBS.PersistentMeshLoads ), #BBS.PersistentMeshWriteQueue,
		CACHE_ROOT )
end, nil, "Print persistent processed-mesh cache statistics." )
