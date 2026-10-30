-- Localized by the native-loader companion when bundled; standalone use keeps the English.
local bundle_i18n = CLIENT and file.Exists("nativeloader/i18n.lua", "LUA")
    and include("nativeloader/i18n.lua") or nil
local function NL(text)
    return bundle_i18n and bundle_i18n.A(text, BBS.I18N and BBS.I18N.language or "en") or text
end
local NP = bundle_i18n and bundle_i18n.P or function(text) return text end
local function NN(text) return text end
-- Hideable-bodygroup UV retrieval and per-entity transparency masks.

BBS = BBS or {}

BBS.HideableMeshCache = BBS.HideableMeshCache or {}
BBS.DamageStates = BBS.DamageStates or {}
BBS.DamagePaintQueue = BBS.DamagePaintQueue or {}
BBS.DamageCompatibilityRefreshQueue =
	BBS.DamageCompatibilityRefreshQueue or {}
BBS.DamageCompatibilityRefreshQueued =
	BBS.DamageCompatibilityRefreshQueued
	or setmetatable( {}, { __mode = "k" } )
BBS.OrphanedDamageStates = BBS.OrphanedDamageStates or {}
BBS.PendingDeathDamageTransfers = BBS.PendingDeathDamageTransfers or {}
BBS.PendingDeathRagdollDiscovery = BBS.PendingDeathRagdollDiscovery
	or setmetatable( {}, { __mode = "k" } )
BBS.DamageMaterialSerial = BBS.DamageMaterialSerial or 0
BBS.DamageDebugDumpSerial = BBS.DamageDebugDumpSerial or 0
BBS.DamageMaterialTemplateCache = BBS.DamageMaterialTemplateCache or {}
BBS.DamageSharedCoverage = BBS.DamageSharedCoverage or {}
BBS.DamageSourceMaterialCache = BBS.DamageSourceMaterialCache or {}
BBS.DamageVTFMetadataCache = BBS.DamageVTFMetadataCache or {}
BBS.RTXHashOnWriteGuard = BBS.RTXHashOnWriteGuard or {
	depth = 0,
	serial = 0,
	enabledByAddon = false,
}
BBS.RTXOpacityMicromapIgnore = BBS.RTXOpacityMicromapIgnore or {
	hashes = {},
	orderedHashes = {},
	updateCount = 0,
}
BBS.RTXDamageProbeQueue = BBS.RTXDamageProbeQueue or {}

local BODYGROUP_FILTER_FORMAT = 10
if BBS.HideableMeshCacheFormat ~= BODYGROUP_FILTER_FORMAT then
	BBS.HideableMeshCache = {}
	BBS.HideableMeshCacheFormat = BODYGROUP_FILTER_FORMAT
end

-- RenderOverride closures survive Lua auto-refresh. Bump this independently
-- from material resources whenever their draw-pass behavior changes.
local RTX_RENDER_OVERRIDE_FORMAT = 5
local REBUILD_RTX_RENDER_OVERRIDES =
	BBS.RTXDamageRenderOverrideFormat ~= RTX_RENDER_OVERRIDE_FORMAT
if REBUILD_RTX_RENDER_OVERRIDES then
	for entity, state in pairs( BBS.DamageStates ) do
		if IsValid( entity ) and state.rtxRenderOverrideInstalled then
			if entity.RenderOverride == state.rtxRenderOverride then
				entity.RenderOverride = state.previousRenderOverride
			else
				local tool = _G.AdvancedBodygroupTool
				local abtState = istable( tool ) and istable( tool.ClientStates )
					and tool.ClientStates[ entity ] or nil
				if istable( abtState )
				and entity.RenderOverride == abtState.renderOverride
				and abtState.previousRenderOverride == state.rtxRenderOverride then
					-- ABT currently wraps this old BBS closure. Remove only our link
					-- while preserving whatever callback was below it.
					abtState.previousRenderOverride = state.previousRenderOverride
				end
			end
		end
		state.rtxRenderOverrideInstalled = false
		state.rtxPreviousRenderOverrideActive = nil
		state.rtxRenderOverride = nil
		state.previousRenderOverride = nil
	end
	BBS.RTXDamageRenderOverrideFormat = RTX_RENDER_OVERRIDE_FORMAT
end

-- Created materials are cached permanently by name. A format bump must use
-- fresh names and restore old submaterial overrides during auto-refresh.
local DAMAGE_MATERIAL_FORMAT = 24
if BBS.DamageMaterialFormat ~= DAMAGE_MATERIAL_FORMAT then
	for entity, state in pairs( BBS.DamageStates ) do
		if IsValid( entity ) then
			if state.rtxRenderOverrideInstalled
			and entity.RenderOverride == state.rtxRenderOverride then
				entity.RenderOverride = state.previousRenderOverride
			end
			for submaterialIndex, mask in pairs( state.masks or {} ) do
				if mask.submaterialOverrideApplied ~= false then
					entity:SetSubMaterial( submaterialIndex,
						mask.previousOverride or "" )
				end
			end
		end
	end
	BBS.DamageStates = {}
	BBS.DamagePaintQueue = {}
	BBS.DamageCompatibilityRefreshQueue = {}
	BBS.DamageCompatibilityRefreshQueued =
		setmetatable( {}, { __mode = "k" } )
	BBS.RTXDamageProbeQueue = {}
	BBS.OrphanedDamageStates = {}
	BBS.PendingDeathDamageTransfers = {}
	BBS.PendingDeathRagdollDiscovery = setmetatable( {}, { __mode = "k" } )
	BBS.DamageMaterialSerial = 0
	BBS.DamageDebugDumpSerial = 0
	BBS.DamageMaterialTemplateCache = {}
	BBS.DamageSharedCoverage = {}
	BBS.DamageSourceMaterialCache = {}
	BBS.DamageVTFMetadataCache = {}
	BBS.DamageMaterialFormat = DAMAGE_MATERIAL_FORMAT
end

local DAMAGE_RESOURCE_SUFFIX = "v" .. DAMAGE_MATERIAL_FORMAT .. "_"

local COLOR_OK = Color( 95, 235, 255 )
local COLOR_PENDING = Color( 255, 205, 90 )
local COLOR_SKIP = Color( 175, 185, 200 )
local COLOR_ERROR = Color( 255, 105, 120 )
local MAX_SUBMATERIALS = 32
local DAMAGE_RT_FLAGS = 8960 -- NOMIP | NOLOD | EIGHTBITALPHA (UVs may wrap)
local COVERAGE_RT_FLAGS = 8972 -- CLAMPS | CLAMPT | NOMIP | NOLOD | EIGHTBITALPHA
local COPY_SENTINEL_R = 255
local COPY_SENTINEL_G = 0
local COPY_SENTINEL_B = 255

local function GetBool( name, fallback )
	local convar = GetConVar( name )
	return convar and convar:GetBool() or fallback
end

local function GetInt( name, fallback )
	local convar = GetConVar( name )
	return convar and convar:GetInt() or fallback
end

local function GetFloat( name, fallback )
	local convar = GetConVar( name )
	return convar and convar:GetFloat() or fallback
end

-- Projected UV triangles use one flat numeric buffer with stride six. This
-- avoids one Lua table allocation per adaptive micro-triangle. The optional
-- third argument addresses a triangle inside that buffer; the two-argument
-- form remains compatible with raw/debug coordinate triples.
local PROJECTED_TRIANGLE_STRIDE = 6
local function ProjectedTriangleCount( projectedTriangles )
	if not projectedTriangles then return 0 end
	if isnumber( projectedTriangles[ 1 ] ) then
		return math.floor( #projectedTriangles / PROJECTED_TRIANGLE_STRIDE )
	end
	return #projectedTriangles
end

local function ProjectedTriangleUV( coordinates, index, vertexIndex )
	if not coordinates then return nil, nil end
	if vertexIndex ~= nil then
		if isnumber( coordinates[ 1 ] ) then
			local offset = ( index - 1 ) * PROJECTED_TRIANGLE_STRIDE
				+ ( vertexIndex - 1 ) * 2
			return coordinates[ offset + 1 ], coordinates[ offset + 2 ]
		end
		coordinates = coordinates[ index ]
		index = vertexIndex
		if not coordinates then return nil, nil end
	end
	if isnumber( coordinates[ 1 ] ) then
		local offset = ( index - 1 ) * 2
		return coordinates[ offset + 1 ], coordinates[ offset + 2 ]
	end
	local coordinate = coordinates[ index ]
	return coordinate and coordinate.u, coordinate and coordinate.v
end

-- Keep the sizeable RTX compatibility implementation in its own lexical
-- scope. Lua 5.1 (and therefore Garry's Mod) permits at most 200 active locals
-- in one function; every top-level `local function` also consumes a slot in
-- the file's main function. Export only the narrow interface required by the
-- damage pipeline so future RTX probes cannot make the entire file fail to
-- compile again.
local RTX = {}
do
local function RTXRemixDetectionReason()
	return BBS.GetRTXRemixDetectionReason
		and BBS.GetRTXRemixDetectionReason() or nil
end

local function IsRTXRemixClient()
	return BBS.IsRTXRemixClient and BBS.IsRTXRemixClient()
		or RTXRemixDetectionReason() ~= nil
end

-- Remix normally hashes a texture only when the resource is first observed.
-- Damage masks deliberately keep one render target and mutate it for every
-- hit, so Remix can continue using an older opacity/occlusion representation
-- even though Source displays the new alpha correctly. The runtime option
-- below makes Remix re-hash resources on writes. It is global and can be
-- expensive, therefore it is enabled only around our final alpha composite,
-- coalesced across overlapping jobs, and restored to the user's exact prior
-- value shortly afterwards.
local RTX_HASH_ON_WRITE_KEY = "rtx.recomputeTextureHashOnWrite"
local RTX_OMM_IGNORE_KEY = "rtx.opacityMicromapIgnoreTextures"
local RTX_HASH_ON_WRITE_RESTORE_TIMER =
	"BBS.RestoreRTXRecomputeTextureHashOnWrite"
local RTX_HASH_ON_WRITE_RESTORE_DELAY = 0.20
local RTX_PROBE_HISTORY_LIMIT = 64

local function RTXConfigBoolean( value )
	value = string.lower( string.Trim( tostring( value or "" ) ) )
	return value == "true" or value == "1" or value == "yes" or value == "on"
end

local function NormalizeRTXHash( value )
	local text = string.upper( string.Trim( tostring( value or "" ) ) )
	local digits = string.match( text, "^0X([0-9A-F]+)$" )
		or string.match( text, "^([0-9A-F]+)$" )
	if not digits then return nil end
	digits = string.gsub( digits, "^0+", "" )
	if digits == "" then return nil end
	return "0x" .. digits
end

local function ReadRTXTextureHashArray( materialName )
	local remixMaterial = _G.RemixMaterial
	local getHashes = istable( remixMaterial )
		and remixMaterial.GetAllTextureHashes or nil
	if not isfunction( getHashes ) then return {}, "unavailable" end
	local ok, hashes = pcall( getHashes, materialName )
	if not ok then return {}, tostring( hashes ) end
	local readable = {}
	local seen = {}
	if not istable( hashes ) then
		local normalized = NormalizeRTXHash( hashes )
		if normalized then readable[ 1 ] = normalized end
		return readable, nil
	end
	for _, hash in ipairs( hashes ) do
		local normalized = NormalizeRTXHash( hash )
		if normalized and not seen[ normalized ] then
			seen[ normalized ] = true
			readable[ #readable + 1 ] = normalized
		end
	end
	table.sort( readable )
	return readable, nil
end

local function ReadRTXTextureHashes( materialName )
	local hashes, errorMessage = ReadRTXTextureHashArray( materialName )
	return #hashes > 0 and table.concat( hashes, "," ) or "<none>",
		#hashes, errorMessage
end

local function AddRTXHashesFromText( output, value )
	for digits in string.gmatch( tostring( value or "" ), "0[xX]([0-9A-Fa-f]+)" ) do
		local hash = NormalizeRTXHash( digits )
		if hash then output[ hash ] = true end
	end
end

local function SortedRTXHashes( set )
	local output = {}
	for hash in pairs( set or {} ) do output[ #output + 1 ] = hash end
	table.sort( output )
	return output
end

-- Opacity micromaps are pre-built acceleration data. They are excellent for
-- static alpha-tested foliage, but a persistent render target whose alpha is
-- edited after every bullet is the opposite workload: an asynchronously built
-- micromap can describe an older hole pattern and keep casting an opaque
-- shadow. NVIDIA explicitly provides rtx.opacityMicromapIgnoreTextures for
-- textures with incorrect OMM cutouts. Protect every content hash observed for
-- our procedural targets while preserving hashes already selected by the user.
local function ProtectRTXOpacityHashes( mask, hashes, source )
	if not IsRTXRemixClient() then return false, "RTX Remix not detected" end
	local config = _G.RemixConfig
	local getConfig = istable( config ) and config.GetConfigVariable or nil
	local setConfig = istable( config ) and config.SetConfigVariable or nil
	if not isfunction( getConfig ) or not isfunction( setConfig ) then
		if mask then
			mask.rtxOMMProtectionAvailable = false
			mask.rtxOMMProtectionError = "RemixConfig runtime API unavailable"
		end
		return false, "RemixConfig runtime API unavailable"
	end

	local state = BBS.RTXOpacityMicromapIgnore
	state.hashes = state.hashes or {}
	state.baseHashes = state.baseHashes or {}
	local getOK, currentValue
	if state.baseReadComplete then
		getOK = state.baseReadSucceeded
		currentValue = state.baseReadValue
	else
		getOK, currentValue = pcall( getConfig, RTX_OMM_IGNORE_KEY )
		state.baseReadComplete = true
		state.baseReadSucceeded = getOK
		state.baseReadValue = getOK and tostring( currentValue or "" ) or nil
		state.baseReadError = getOK and nil or tostring( currentValue )
		if getOK then AddRTXHashesFromText( state.baseHashes, currentValue ) end
	end
	local desired = {}
	for hash in pairs( state.baseHashes ) do desired[ hash ] = true end
	for hash in pairs( state.hashes ) do desired[ hash ] = true end

	local added = 0
	local input = {}
	for _, value in ipairs( hashes or {} ) do
		local hash = NormalizeRTXHash( value )
		if hash then
			input[ #input + 1 ] = hash
			if not state.hashes[ hash ] then added = added + 1 end
			state.hashes[ hash ] = true
			desired[ hash ] = true
		end
	end

	local ordered = SortedRTXHashes( desired )
	state.orderedHashes = ordered
	local desiredValue = table.concat( ordered, ", " )
	local currentSet = {}
	for hash in pairs( state.baseHashes ) do currentSet[ hash ] = true end
	-- The currently installed GMod RTX bridge's getter rereads rtx.conf and
	-- cannot return values submitted through SetConfigVariable. Include our last
	-- accepted runtime value when deciding whether another deferred update is
	-- necessary.
	if state.lastSetSucceeded then
		AddRTXHashesFromText( currentSet, state.lastSetValue )
	end
	local missing = false
	for _, hash in ipairs( ordered ) do
		if not currentSet[ hash ] then
			missing = true
			break
		end
	end

	local setOK, setResult = true, true
	if missing then
		setOK, setResult = pcall( setConfig, RTX_OMM_IGNORE_KEY, desiredValue )
		setOK = setOK and setResult ~= false
		state.updateCount = ( state.updateCount or 0 ) + 1
		state.lastSetFrame = FrameNumber()
		state.lastSetValue = desiredValue
		state.lastSetSucceeded = setOK
		state.lastSetResult = setResult
	end
	state.lastReadSucceeded = getOK
	state.lastReadValue = getOK and tostring( currentValue or "" ) or nil
	state.lastReadError = getOK and nil or tostring( currentValue )

	if mask then
		mask.rtxOMMProtectionAvailable = true
		mask.rtxOMMProtectionSource = source or "texture hash probe"
		mask.rtxOMMProtectionInputHashes = #input > 0
			and table.concat( input, "," ) or "<none>"
		mask.rtxOMMProtectionHashCount = #ordered
		mask.rtxOMMProtectionAddedCount = added
		mask.rtxOMMProtectionSetNeeded = missing
		mask.rtxOMMProtectionSucceeded = setOK
		mask.rtxOMMProtectionResult = setResult
		mask.rtxOMMProtectionError = setOK and nil or tostring( setResult )
	end
	return setOK, setOK and ( missing and "queued" or "already protected" )
		or tostring( setResult )
end

local function NormalizeRTXMaterialName( value )
	local output = string.lower( string.Trim( tostring( value or "" ) ) )
	output = string.gsub( output, "\\", "/" )
	output = string.gsub( output, "^!", "" )
	return output
end

local function ReadRTXBridgeEntries( materialName )
	local remixMaterial = _G.RemixMaterial
	local dump = istable( remixMaterial )
		and remixMaterial.DumpAllTextureHashes or nil
	if not isfunction( dump ) then return {}, "unavailable" end
	local ok, rows = pcall( dump )
	if not ok then return {}, tostring( rows ) end
	local target = NormalizeRTXMaterialName( materialName )
	local output = {}
	for _, row in pairs( istable( rows ) and rows or {} ) do
		if istable( row )
		and NormalizeRTXMaterialName( row.material ) == target then
			output[ #output + 1 ] = {
				material = tostring( row.material or "" ),
				texture = tostring( row.texture or "" ),
				hash = NormalizeRTXHash( row.hash ) or tostring( row.hash or "0x0" ),
			}
		end
	end
	table.sort( output, function( left, right )
		return tostring( left.texture ) < tostring( right.texture )
	end )
	return output, nil
end

local function QueueRTXDamageProbe( mask, hitSerial, reason )
	if not mask or not IsRTXRemixClient() then return end
	mask.rtxProbeGeneration = ( mask.rtxProbeGeneration or 0 ) + 1
	BBS.RTXDamageProbeQueue[ mask ] = {
		generation = mask.rtxProbeGeneration,
		hitSerial = hitSerial,
		reason = reason or "damage paint",
		nextFrame = FrameNumber() + 1,
		attempts = 0,
		stableCount = 0,
		lastSignature = nil,
	}
end

local function RecordRTXDamageProbe( mask, pending, hashes, hashError,
		bridgeEntries, bridgeError, protectionOK, protectionResult )
	mask.rtxHashHistory = mask.rtxHashHistory or {}
	local pointers = {}
	for _, entry in ipairs( bridgeEntries or {} ) do
		pointers[ #pointers + 1 ] = tostring( entry.texture )
			.. "=" .. tostring( entry.hash )
	end
	local row = {
		frame = FrameNumber(),
		time = SysTime(),
		hitSerial = pending.hitSerial,
		reason = pending.reason,
		attempt = pending.attempts,
		hashes = #hashes > 0 and table.concat( hashes, "," ) or "<none>",
		hashError = hashError,
		bridgeEntries = #pointers > 0 and table.concat( pointers, "," ) or "<none>",
		bridgeError = bridgeError,
		protectionSucceeded = protectionOK,
		protectionResult = protectionResult,
	}
	mask.rtxHashHistory[ #mask.rtxHashHistory + 1 ] = row
	while #mask.rtxHashHistory > RTX_PROBE_HISTORY_LIMIT do
		table.remove( mask.rtxHashHistory, 1 )
	end
	mask.rtxLastProbe = row
	return row
end

local function BuildRTXIdentityHistoryText( mask )
	local state = BBS.RTXOpacityMicromapIgnore or {}
	local lines = {
		"Procedural Bodygroup Destruction RTX dynamic-opacity identity history",
		"addon_version=" .. tostring( BBS.Version ),
		"generated_material=!" .. tostring( mask and mask.materialName ),
		"render_target=" .. tostring( mask and mask.renderTargetName ),
		"render_target_size=" .. tostring( mask and mask.width ) .. "x"
			.. tostring( mask and mask.height ),
		"omm_ignore_key=" .. RTX_OMM_IGNORE_KEY,
		"omm_known_hash_count=" .. tostring( #( state.orderedHashes or {} ) ),
		"omm_known_hashes=" .. ( #( state.orderedHashes or {} ) > 0
			and table.concat( state.orderedHashes, "," ) or "<none>" ),
		"omm_update_count=" .. tostring( state.updateCount ),
		"omm_last_set_succeeded=" .. tostring( state.lastSetSucceeded ),
		"omm_last_set_result=" .. tostring( state.lastSetResult ),
		"omm_last_read_succeeded=" .. tostring( state.lastReadSucceeded ),
		"omm_last_read_value=" .. tostring( state.lastReadValue ),
		"hash_history_count=" .. tostring( #( mask and mask.rtxHashHistory or {} ) ),
		"",
		"Columns: frame | time | hit | attempt | hashes | D3D pointers=current hash | OMM protected | result",
	}
	for _, row in ipairs( mask and mask.rtxHashHistory or {} ) do
		lines[ #lines + 1 ] = string.format(
			"%s | %.6f | %s | %s | %s | %s | %s | %s",
			tostring( row.frame ), tonumber( row.time ) or 0,
			tostring( row.hitSerial ), tostring( row.attempt ),
			tostring( row.hashes ), tostring( row.bridgeEntries ),
			tostring( row.protectionSucceeded ),
			tostring( row.protectionResult ) )
		if row.hashError or row.bridgeError then
			lines[ #lines + 1 ] = "  errors: hash=" .. tostring( row.hashError )
				.. " bridge=" .. tostring( row.bridgeError )
		end
	end
	return table.concat( lines, "\n" ) .. "\n"
end

hook.Add( "PostRender", "BBS.ProtectRTXDynamicOpacity", function()
	local processed = 0
	for mask, pending in pairs( BBS.RTXDamageProbeQueue ) do
		if processed >= 8 then break end
		if not mask or not mask.materialName
		or pending.generation ~= mask.rtxProbeGeneration then
			BBS.RTXDamageProbeQueue[ mask ] = nil
		elseif FrameNumber() >= ( pending.nextFrame or 0 ) then
			processed = processed + 1
			pending.attempts = pending.attempts + 1
			local hashes, hashError = ReadRTXTextureHashArray( mask.materialName )
			local entries, bridgeError = {}, "skipped (debug bundles disabled)"
			if GetBool( "bbs_damage_dump_debug", false ) then
				entries, bridgeError = ReadRTXBridgeEntries( mask.materialName )
			end
			local protectOK, protectResult = ProtectRTXOpacityHashes(
				mask, hashes, "post-render hash probe" )
			local pointerParts = {}
			for _, entry in ipairs( entries ) do
				pointerParts[ #pointerParts + 1 ] = entry.texture .. "=" .. entry.hash
			end
			local signature = table.concat( hashes, "," ) .. "|"
				.. table.concat( pointerParts, "," )
			if signature == pending.lastSignature and #hashes > 0 then
				pending.stableCount = pending.stableCount + 1
			else
				pending.stableCount = 0
				pending.lastSignature = signature
			end
			RecordRTXDamageProbe( mask, pending, hashes, hashError,
				entries, bridgeError, protectOK, protectResult )
			if mask.lastDebugBundleFolder then
				file.Write( mask.lastDebugBundleFolder
					.. "/rtx_identity_history.txt",
					BuildRTXIdentityHistoryText( mask ) )
			end
			if pending.stableCount >= 2 and protectOK then
				BBS.RTXDamageProbeQueue[ mask ] = nil
			else
				-- A Remix texture hash can appear many frames after Source submits the
				-- render target, especially on slow GPUs. Keep probing with bounded
				-- exponential backoff instead of abandoning protection after eight
				-- rendered frames.
				local backoff = math.min( 2 ^ math.floor(
					math.max( pending.attempts - 1, 0 ) / 4 ), 60 )
				pending.nextFrame = FrameNumber() + backoff
			end
		end
	end
end )

-- SetConfigVariable uses Remix's deferred option layer. The installed bridge's
-- getter only rereads rtx.conf and cannot report a runtime value, so a successful
-- setter result plus one frame boundary is the strongest available handshake.
local function PrepareRTXHashOnWriteJob( job )
	if not job or not IsRTXRemixClient() then return true end
	if job.rtxHashOnWritePrepared then return true end

	local config = _G.RemixConfig
	local getConfig = istable( config ) and config.GetConfigVariable or nil
	local setConfig = istable( config ) and config.SetConfigVariable or nil
	if not isfunction( getConfig ) or not isfunction( setConfig ) then
		job.rtxHashOnWritePreparationError =
			"RemixConfig runtime API unavailable"
		job.rtxHashOnWritePrepared = true
		return true
	end

	local guard = BBS.RTXHashOnWriteGuard
	if guard.enabledByAddon then
		timer.Remove( RTX_HASH_ON_WRITE_RESTORE_TIMER )
		job.rtxHashOnWritePreparationActive = true
		if FrameNumber() < ( guard.enableReadyFrame or 0 ) then
			job.rtxHashOnWritePreparationWaits =
				( job.rtxHashOnWritePreparationWaits or 0 ) + 1
			return false, "waiting one frame for Remix option resolution"
		end
		guard.ready = true
		job.rtxHashOnWritePreparationEffectiveValue =
			"<runtime setter accepted; getter reads rtx.conf only>"
		job.rtxHashOnWritePrepared = true
		return true
	end

	local getOK, previousValue = pcall( getConfig, RTX_HASH_ON_WRITE_KEY )
	if not getOK then
		job.rtxHashOnWritePreparationError =
			"could not read existing Remix option: " .. tostring( previousValue )
		job.rtxHashOnWritePrepared = true
		return true
	end
	previousValue = tostring( previousValue or "" )
	job.rtxHashOnWritePreparationPreviousValue = previousValue
	if RTXConfigBoolean( previousValue ) then
		job.rtxHashOnWritePreparationInherited = true
		job.rtxHashOnWritePrepared = true
		return true
	end

	local setOK, setResult = pcall( setConfig,
		RTX_HASH_ON_WRITE_KEY, "True" )
	local setSucceeded = setOK and setResult ~= false
	job.rtxHashOnWritePreparationSetSucceeded = setSucceeded
	job.rtxHashOnWritePreparationSetResult = setOK and setResult or nil
	job.rtxHashOnWritePreparationSetError = setOK
		and nil or tostring( setResult )
	if not setSucceeded then
		job.rtxHashOnWritePreparationError =
			"failed to queue Remix texture re-hashing"
		job.rtxHashOnWritePrepared = true
		return true
	end

	guard.enabledByAddon = true
	guard.ready = false
	guard.savedValue = previousValue ~= "" and previousValue or "False"
	guard.enableAttempts = 1
	guard.enableRequestedFrame = FrameNumber()
	guard.enableReadyFrame = FrameNumber() + 1
	guard.lastSetSucceeded = setSucceeded
	guard.lastSetResult = setResult
	guard.lastSetError = nil
	guard.serial = ( tonumber( guard.serial ) or 0 ) + 1
	job.rtxHashOnWritePreparationActive = true
	job.rtxHashOnWritePreparationWaits =
		( job.rtxHashOnWritePreparationWaits or 0 ) + 1
	return false, "queued Remix texture re-hashing for next frame"
end

local function BeginRTXHashOnWrite( mask, captureHashes )
	if not mask or not IsRTXRemixClient() then
		if mask then mask.rtxHashOnWriteAttempted = false end
		return nil
	end

	local config = _G.RemixConfig
	local getConfig = istable( config ) and config.GetConfigVariable or nil
	local setConfig = istable( config ) and config.SetConfigVariable or nil
	mask.rtxHashOnWriteAttempted = true
	mask.rtxHashOnWriteAvailable = isfunction( getConfig )
		and isfunction( setConfig )
	mask.rtxHashOnWriteCaptureRequested = captureHashes and true or false
	mask.rtxHashOnWriteRestoreScheduled = false
	mask.rtxHashOnWriteRestorePending = false
	if not mask.rtxHashOnWriteAvailable then
		mask.rtxHashOnWriteEnabledForPaint = false
		mask.rtxHashOnWriteError = "RemixConfig runtime API unavailable"
		return nil
	end

	local guard = BBS.RTXHashOnWriteGuard
	guard.depth = math.max( tonumber( guard.depth ) or 0, 0 ) + 1
	guard.serial = ( tonumber( guard.serial ) or 0 ) + 1
	local token = { active = true, guard = guard, serial = guard.serial }
	timer.Remove( RTX_HASH_ON_WRITE_RESTORE_TIMER )

	mask.rtxHashOnWriteBeginCount =
		( mask.rtxHashOnWriteBeginCount or 0 ) + 1
	mask.rtxHashOnWriteError = nil
	mask.rtxHashOnWriteSetSucceeded = guard.lastSetSucceeded
	mask.rtxHashOnWriteSetResult = guard.lastSetResult
	mask.rtxHashOnWriteSetError = guard.lastSetError
	mask.rtxHashOnWriteCoalesced = guard.enabledByAddon and true or false

	-- Protect the currently bound content hash before changing the alpha. The
	-- post-render probe below will protect the new content hash after Remix has
	-- observed the write and the material has rendered again.
	local currentHashes, currentHashError =
		ReadRTXTextureHashArray( mask.materialName )
	ProtectRTXOpacityHashes( mask, currentHashes, "before alpha write" )
	if captureHashes then
		mask.rtxTextureHashesBefore = #currentHashes > 0
			and table.concat( currentHashes, "," ) or "<none>"
		mask.rtxTextureHashCountBefore = #currentHashes
		mask.rtxTextureHashesBeforeError = currentHashError
	end

	if guard.enabledByAddon then
		mask.rtxHashOnWritePreviousValue = guard.savedValue
		mask.rtxHashOnWriteEffectiveReadSucceeded = nil
		mask.rtxHashOnWriteEffectiveReadError =
			"bridge getter reads rtx.conf only"
		mask.rtxHashOnWriteEffectiveValue =
			"<runtime setter accepted after one frame>"
		mask.rtxHashOnWriteInheritedEnabled = false
		mask.rtxHashOnWriteEnabledForPaint = guard.lastSetSucceeded == true
		mask.rtxHashOnWritePreparationAttempts = guard.enableAttempts
		if not mask.rtxHashOnWriteEnabledForPaint then
			mask.rtxHashOnWriteError =
				"runtime setter was not accepted before alpha composite"
		end
		return token
	end

	local getOK, previousValue = pcall( getConfig, RTX_HASH_ON_WRITE_KEY )
	mask.rtxHashOnWriteGetSucceeded = getOK
	mask.rtxHashOnWriteGetError = getOK and nil or tostring( previousValue )
	previousValue = getOK and tostring( previousValue or "" ) or ""
	mask.rtxHashOnWritePreviousValue = previousValue
	if not getOK then
		mask.rtxHashOnWriteInheritedEnabled = false
		mask.rtxHashOnWriteEnabledForPaint = false
		mask.rtxHashOnWriteError =
			"could not read the user's existing texture hash setting"
		return token
	end
	if getOK and RTXConfigBoolean( previousValue ) then
		mask.rtxHashOnWriteInheritedEnabled = true
		mask.rtxHashOnWriteEffectiveValue = previousValue
		mask.rtxHashOnWriteEnabledForPaint = true
		return token
	end

	guard.savedValue = previousValue ~= "" and previousValue or "False"
	local setOK, setResult = pcall( setConfig,
		RTX_HASH_ON_WRITE_KEY, "True" )
	local setSucceeded = setOK and setResult ~= false
	mask.rtxHashOnWriteSetSucceeded = setSucceeded
	mask.rtxHashOnWriteSetResult = setOK and setResult or nil
	mask.rtxHashOnWriteSetError = setOK and nil or tostring( setResult )

	mask.rtxHashOnWriteEffectiveReadSucceeded = nil
	mask.rtxHashOnWriteEffectiveReadError =
		"bridge getter reads rtx.conf only"
	mask.rtxHashOnWriteEffectiveValue = setSucceeded
		and "<runtime setter accepted; same-frame fallback>" or "<setter failed>"
	local enabled = setSucceeded
	guard.enabledByAddon = enabled
	mask.rtxHashOnWriteInheritedEnabled = false
	mask.rtxHashOnWriteEnabledForPaint = enabled
	if not enabled then
		mask.rtxHashOnWriteError = "failed to enable texture re-hashing for RT write"
	end
	return token
end

local function EndRTXHashOnWrite( token, mask )
	if not token or not token.active then return end
	token.active = false
	local guard = token.guard
	guard.depth = math.max( ( tonumber( guard.depth ) or 1 ) - 1, 0 )
	if not guard.enabledByAddon or guard.depth > 0 then return end

	mask.rtxHashOnWriteRestoreScheduled = true
	mask.rtxHashOnWriteRestorePending = true
	local restoreSerial = guard.serial
	local restoreValue = tostring( guard.savedValue or "False" )
	local attempts = 0
	local function RestorePreviousValue()
		if guard.serial ~= restoreSerial or guard.depth > 0
		or not guard.enabledByAddon then return end
		attempts = attempts + 1
		local config = _G.RemixConfig
		local setConfig = istable( config )
			and config.SetConfigVariable or nil
		local ok, result = false, "RemixConfig.SetConfigVariable unavailable"
		if isfunction( setConfig ) then
			ok, result = pcall( setConfig,
				RTX_HASH_ON_WRITE_KEY, restoreValue )
			ok = ok and result ~= false
		end
		local restored = ok
		mask.rtxHashOnWriteRestoreAttempts = attempts
		mask.rtxHashOnWriteRestoreSucceeded = restored
		mask.rtxHashOnWriteRestoreResult = ok and result or nil
		mask.rtxHashOnWriteRestoreError = ok and nil or tostring( result )
		mask.rtxHashOnWriteRestoredValue = restored
			and ( restoreValue .. " <runtime setter accepted>" ) or "<setter failed>"
		if restored then
			mask.rtxHashOnWriteRestorePending = false
			guard.enabledByAddon = false
			guard.ready = false
			guard.savedValue = nil
			guard.enableAttempts = 0
			return
		end
		if attempts < 5 then
			timer.Create( RTX_HASH_ON_WRITE_RESTORE_TIMER,
				RTX_HASH_ON_WRITE_RESTORE_DELAY, 1, RestorePreviousValue )
		else
			mask.rtxHashOnWriteRestorePending = false
			BBS.Log( "  RTX texture hash setting restore failed after %d attempts: wanted=%s error=%s",
				attempts, restoreValue, tostring( mask.rtxHashOnWriteRestoreError ) )
		end
	end
	timer.Create( RTX_HASH_ON_WRITE_RESTORE_TIMER,
		RTX_HASH_ON_WRITE_RESTORE_DELAY, 1, RestorePreviousValue )
end

local function ReleasePreparedRTXHashOnWriteJob( job, diagnosticsTarget )
	if not job or not job.rtxHashOnWritePreparationActive then return end
	job.rtxHashOnWritePreparationActive = false
	EndRTXHashOnWrite( {
		active = true,
		guard = BBS.RTXHashOnWriteGuard,
	}, diagnosticsTarget or job )
end

-- The generated Source material and its D3D render-target pointer are stable;
-- only the pixels change. The RTX bridge's "InvalidateMaterialCache" function
-- clears its own material-to-D3D-pointer map, not Remix's texture or opacity
-- caches. Calling it after every shot therefore discards useful identity
-- history without invalidating the stale OMM that caused the shadow bug. Bind
-- and submit once, then let hash-on-write plus OMM exclusion handle later edits.
local function RefreshRTXDamageMaterial( mask, reason )
	if not mask or not IsRTXRemixClient() then
		if mask then mask.rtxRefreshAttempted = false end
		return false, "RTX Remix not detected"
	end

	local started = SysTime()
	mask.rtxRefreshAttempted = true
	mask.rtxRefreshCount = ( mask.rtxRefreshCount or 0 ) + 1
	mask.rtxRefreshReason = reason or "damage paint"
	local firstRefresh = mask.rtxRefreshCount == 1

	local collisionFixer = _G.HashCollisionFixer
	local invalidate = istable( collisionFixer )
		and collisionFixer.InvalidateMaterialCache or nil
	mask.rtxCacheInvalidationAvailable = isfunction( invalidate )
	mask.rtxCacheInvalidationSkipped = true
	mask.rtxCacheInvalidationSkipReason =
		"bridge-only invalidation would forget the stable D3D texture identity"
	mask.rtxCacheInvalidationSucceeded = true
	mask.rtxCacheInvalidationResult = nil
	mask.rtxCacheInvalidationError = nil

	local bindOK, bindError = true, nil
	mask.rtxTextureRebindSkipped = not firstRefresh
	if firstRefresh then
		bindOK, bindError = pcall( function()
			mask.material:SetTexture( "$basetexture", mask.renderTarget )
		end )
	end
	mask.rtxTextureRebindSucceeded = bindOK
	mask.rtxTextureRebindError = bindOK and nil or tostring( bindError )
	local recompute = mask.material and mask.material.Recompute or nil
	mask.rtxMaterialRecomputeAvailable = isfunction( recompute )
	mask.rtxMaterialRecomputeSkipped = not firstRefresh
	mask.rtxMaterialRecomputeSucceeded = true
	mask.rtxMaterialRecomputeError = nil
	if firstRefresh and bindOK and mask.rtxMaterialRecomputeAvailable then
		local ok, recomputeError = pcall( recompute, mask.material )
		mask.rtxMaterialRecomputeSucceeded = ok
		if not ok then mask.rtxMaterialRecomputeError = tostring( recomputeError ) end
	end

	local remixMaterial = _G.RemixMaterial
	local track = istable( remixMaterial ) and remixMaterial.TrackMaterial or nil
	mask.rtxTrackerAvailable = isfunction( track )
	mask.rtxTrackerSkipped = not firstRefresh
	mask.rtxTrackerSucceeded = true
	mask.rtxTrackerResult = nil
	mask.rtxTrackerError = nil
	if firstRefresh and mask.rtxTrackerAvailable then
		local ok, result = pcall( track, mask.materialName )
		mask.rtxTrackerSucceeded = ok and result ~= false
		mask.rtxTrackerResult = ok and result or nil
		mask.rtxTrackerError = ok and nil or tostring( result )
	end

	local pipeline = _G.RTXMaterialPipeline
	local process = istable( pipeline ) and pipeline.ProcessMaterial or nil
	mask.rtxPipelineAvailable = isfunction( process )
	mask.rtxPipelineProcessSkipped = true
	mask.rtxPipelineProcessSucceeded = true
	mask.rtxPipelineProcessResult = nil
	mask.rtxPipelineProcessError = nil
	if mask.rtxHashOnWriteCaptureRequested then
		mask.rtxTextureHashesAfter, mask.rtxTextureHashCountAfter,
			mask.rtxTextureHashesAfterError =
			ReadRTXTextureHashes( mask.materialName )
	end

	mask.rtxRefreshSucceeded = bindOK
		and ( not mask.rtxMaterialRecomputeAvailable
			or mask.rtxMaterialRecomputeSucceeded )
		and ( not mask.rtxTrackerAvailable or mask.rtxTrackerSucceeded )
	mask.rtxRefreshMilliseconds = math.max( ( SysTime() - started ) * 1000, 0 )
	return mask.rtxRefreshSucceeded, mask.rtxRefreshSucceeded
		and ( firstRefresh
			and "initial RT binding tracked; bridge cache preserved"
			or "stable RT identity preserved; pixel update only" )
		or "one or more RTX refresh stages failed"
end

RTX.DetectionReason = RTXRemixDetectionReason
RTX.IsClient = IsRTXRemixClient
RTX.HashOnWriteKey = RTX_HASH_ON_WRITE_KEY
RTX.OMMIgnoreKey = RTX_OMM_IGNORE_KEY
RTX.ReadTextureHashArray = ReadRTXTextureHashArray
RTX.NormalizeMaterialName = NormalizeRTXMaterialName
RTX.ReadBridgeEntries = ReadRTXBridgeEntries
RTX.QueueDamageProbe = QueueRTXDamageProbe
RTX.BuildIdentityHistoryText = BuildRTXIdentityHistoryText
RTX.PrepareHashOnWriteJob = PrepareRTXHashOnWriteJob
RTX.BeginHashOnWrite = BeginRTXHashOnWrite
RTX.EndHashOnWrite = EndRTXHashOnWrite
RTX.ReleasePreparedHashOnWriteJob = ReleasePreparedRTXHashOnWriteJob
RTX.RefreshDamageMaterial = RefreshRTXDamageMaterial
end

local function NormalizeMaterialPath( path )
	path = string.lower( string.gsub( tostring( path or "" ), "\\", "/" ) )
	path = string.gsub( path, "^materials/", "" )
	path = string.gsub( path, "%.vmt$", "" )
	return path
end

-- Bodygroup ownership construction has many private helpers but only four
-- formatting helpers are needed by the later debug/reporting code. Isolating
-- the private names also leaves ample headroom below Lua 5.1's local limit for
-- future damage-pipeline work.
local BodygroupHelpers = {}
do
local function BlankSubmodelReason( name )
	local normalized = string.lower( string.Trim( tostring( name or "" ) ) )
	if normalized == "" then return "empty" end
	if string.find( normalized, "unnamed", 1, true ) then return "unnamed" end

	-- Compiled models do not consistently expose the literal QC token. Some
	-- return "blank", Source's generated name "empty", or a path such as
	-- ".../blank.smd" / ".../empty.smd".
	local path = string.gsub( normalized, "\\", "/" )
	local leaf = string.match( path, "([^/]+)$" ) or path
	local stem = string.gsub( leaf, "%.[^%.]+$", "" )
	if normalized == "blank" or stem == "blank" then return "blank" end
	if normalized == "empty" or stem == "empty" then return "empty-token" end
	if string.match( stem, "^blank[%W_]" )
	or string.match( stem, "[%W_]blank$")
	or string.match( stem, "[%W_]blank[%W_]" ) then
		return "blank-token"
	end
	return nil
end

local function SubmodelName( value )
	if isstring( value ) then return value end
	if istable( value ) then
		return value.name or value.model or value.submodel or value.path
	end
	if value == nil then return nil end
	return tostring( value )
end

local function SortedBodygroupEntries( groups )
	local entries = {}
	for rawKey, group in pairs( groups or {} ) do
		if istable( group ) then
			entries[ #entries + 1 ] = { rawKey = rawKey, group = group }
		end
	end
	table.sort( entries, function( left, right )
		local leftId = tonumber( left.group.id ) or tonumber( left.rawKey ) or math.huge
		local rightId = tonumber( right.group.id ) or tonumber( right.rawKey ) or math.huge
		if leftId ~= rightId then return leftId < rightId end
		return tostring( left.rawKey ) < tostring( right.rawKey )
	end )
	return entries
end

-- ModelMeshData bodygroup selection strings use one base-36 character per
-- bodygroup (0-9, then a-z). tonumber("a") returns nil and previously caused
-- selections 10..35 to be read back from the live entity instead of from the
-- cached mesh variant being compared.
local function DecodeBodygroupSelectionCharacter( character )
	local byte = string.byte( string.lower( tostring( character or "" ) ), 1 )
	if not byte then return nil end
	if byte >= 48 and byte <= 57 then return byte - 48 end
	if byte >= 97 and byte <= 122 then return byte - 97 + 10 end
	return nil
end

local function InspectBodygroupSubmodels( group, expectedCount )
	local inspected = {}
	local blankOptions = {}
	local rawEntries = {}
	local byId = {}

	-- This table is explicitly zero-indexed by Garry's Mod. The stock
	-- bodygroup property reads v.submodels[i - 1], so ipairs and index - 1 are
	-- both incorrect here.
	for rawKey, rawValue in pairs( group and group.submodels or {} ) do
		local optionId = tonumber( rawKey )
		local name = SubmodelName( rawValue )
		local rawRecord = {
			key = rawKey,
			keyType = type( rawKey ),
			valueType = type( rawValue ),
			value = tostring( rawValue ),
			name = name,
			id = optionId,
		}
		rawEntries[ #rawEntries + 1 ] = rawRecord
		if optionId ~= nil and optionId >= 0 and optionId == math.floor( optionId ) then
			byId[ optionId ] = true
			name = tostring( name or "" )
			local reason = BlankSubmodelReason( name )
			local option = {
				id = optionId,
				name = name,
				blank = reason ~= nil,
				reason = reason,
				rawKey = rawKey,
				valueType = type( rawValue ),
			}
			inspected[ #inspected + 1 ] = option
			if option.blank then blankOptions[ #blankOptions + 1 ] = option end
		end
	end

	-- A few compiled models omit the entry for an empty mstudiomodel_t rather
	-- than returning an empty string. Infer only individual holes in a
	-- partially populated option table; an entirely missing table stays
	-- unknown so ordinary multi-variant groups are never accepted wholesale.
	expectedCount = math.max( 0, tonumber( expectedCount ) or tonumber( group and group.num ) or 0 )
	if next( byId ) ~= nil then
		for optionId = 0, expectedCount - 1 do
			if not byId[ optionId ] then
				local option = {
					id = optionId,
					name = "",
					blank = true,
					reason = "missing-runtime-entry",
					inferred = true,
				}
				inspected[ #inspected + 1 ] = option
				blankOptions[ #blankOptions + 1 ] = option
			end
		end
	end

	table.sort( inspected, function( left, right ) return left.id < right.id end )
	table.sort( blankOptions, function( left, right ) return left.id < right.id end )
	table.sort( rawEntries, function( left, right )
		if left.id ~= nil and right.id ~= nil and left.id ~= right.id then
			return left.id < right.id
		end
		return tostring( left.key ) < tostring( right.key )
	end )
	return inspected, blankOptions, rawEntries
end

function BBS.HasBlankBodygroup( entity, bodygroupId )
	if not IsValid( entity ) then return false, {}, nil end
	for _, entry in ipairs( SortedBodygroupEntries( entity:GetBodyGroups() ) ) do
		local group = entry.group
		local id = tonumber( group.id ) or tonumber( entry.rawKey )
		if id == bodygroupId then
			local count = math.max( tonumber( group.num ) or 0,
				entity:GetBodygroupCount( id ) or 0 )
			local inspected, blankOptions = InspectBodygroupSubmodels( group, count )
			return #blankOptions > 0, blankOptions, inspected
		end
	end
	return false, {}, nil
end

local function BodygroupSnapshot( entity, selection )
	local groups = entity:GetBodyGroups() or {}
	local values = {}
	local hideable = {}
	local inspectedBodygroups = {}
	local maximumId = -1
	selection = tostring( selection or "" )

	for _, entry in ipairs( SortedBodygroupEntries( groups ) ) do
		local group = entry.group
		local id = tonumber( group.id ) or tonumber( entry.rawKey )
		if id ~= nil then
			local count = math.max( tonumber( group.num ) or 0,
				entity:GetBodygroupCount( id ) or 0 )
			local selected = DecodeBodygroupSelectionCharacter(
				string.sub( selection, id + 1, id + 1 ) )
			if selected == nil then selected = entity:GetBodygroup( id ) or 0 end
			values[ id ] = selected
			maximumId = math.max( maximumId, id )
			local submodels, blankOptions, rawSubmodels =
				InspectBodygroupSubmodels( group, count )
			local bodygroupName = group.name or ( "bodygroup_" .. id )
			local overridden, overrideRecord = false, nil
			if BBS.IsHideableBodygroupOverridden then
				overridden, overrideRecord = BBS.IsHideableBodygroupOverridden(
					entity:GetModel(), id, bodygroupName )
			end
			local filterAllowed, filterReason = true, "bodygroup filter unavailable"
			if BBS.IsBodygroupDamageAllowed then
				filterAllowed, filterReason = BBS.IsBodygroupDamageAllowed( bodygroupName )
			end
			local blacklistBypassed = overridden and not filterAllowed
			if overridden then
				filterAllowed = true
				filterReason = blacklistBypassed
					and "explicit per-model hideable override bypasses bodygroup blacklist"
					or "explicit per-model hideable override has highest priority"
			end
			local record = {
				id = id,
				rawKey = entry.rawKey,
				rawKeyType = type( entry.rawKey ),
				name = bodygroupName,
				count = count,
				declaredCount = tonumber( group.num ),
				selected = selected,
				submodels = submodels,
				rawSubmodels = rawSubmodels,
				blankOptions = blankOptions,
				hasBlank = #blankOptions > 0,
				filterAllowed = filterAllowed,
				filterReason = filterReason,
				overridden = overridden,
				overrideRecord = overrideRecord,
				blacklistBypassed = blacklistBypassed,
			}
			record.eligible = record.overridden
				or ( record.hasBlank and record.filterAllowed )
			inspectedBodygroups[ #inspectedBodygroups + 1 ] = record
			if record.eligible then hideable[ #hideable + 1 ] = record end
		end
	end

	return values, maximumId, hideable, inspectedBodygroups
end

function BBS.HasDamageableBodygroupsForPrewarm( entity, selection )
	if not IsValid( entity ) then return nil end
	-- Reuse the same blank-submodel, override, and denylist rules as damage.
	-- This inspects the entity's small compiled bodygroup description only; it
	-- neither extracts geometry nor changes the selected model/bodygroups.
	local ok, _, _, hideable, inspected = pcall( BodygroupSnapshot, entity, selection )
	if not ok then return nil end
	if #hideable > 0 then return true end
	-- A just-created entity or a partial Lua refresh can lack these descriptions
	-- or filter helpers. Unknown must retain the ordinary preparation path.
	if #inspected == 0 or not BBS.IsHideableBodygroupOverridden
	or not BBS.IsBodygroupDamageAllowed then return nil end
	for _, bodygroup in ipairs( inspected ) do
		if bodygroup.filterAllowed and ( bodygroup.count <= 0
			or #bodygroup.submodels < bodygroup.count ) then return nil end
	end
	return false
end

local function BodygroupComparisonOption( bodygroup )
	for _, option in ipairs( bodygroup.blankOptions or {} ) do
		if option.id ~= bodygroup.selected then return option end
	end
	if not bodygroup.overridden then return nil end
	-- An explicit override may deliberately target a swappable group whose
	-- alternatives are all visible models. Compare the active option with any
	-- other valid option; current fingerprints that disappear belong to the
	-- overridden bodygroup just as they would when compared with a blank.
	for _, option in ipairs( bodygroup.submodels or {} ) do
		if option.id ~= bodygroup.selected then return option end
	end
	if bodygroup.count > 1 then
		local optionId = bodygroup.selected == 0 and 1 or 0
		return {
			id = optionId,
			name = "<override comparison option>",
			blank = false,
			reason = "explicit-override-alternate",
			inferred = true,
		}
	end
	return nil
end

local function BodygroupString( values, maximumId )
	local result = {}
	for id = 0, maximumId do
		local value = math.Clamp( math.floor( tonumber( values[ id ] ) or 0 ), 0, 35 )
		result[ #result + 1 ] = value < 10 and tostring( value )
			or string.char( string.byte( "a" ) + value - 10 )
	end
	return table.concat( result )
end

local function NewFingerprintAccumulator( material )
	return {
		material = NormalizeMaterialPath( material ),
		count = 0,
		sx = 0, sy = 0, sz = 0, su = 0, sv = 0,
		wx = 0, wy = 0, wz = 0, wu = 0, wv = 0,
		minimum = nil,
		maximum = nil,
	}
end

local function AddFingerprintVertex( accumulator, vertex )
	local position = vertex and ( vertex.pos or vertex.position )
	if not position then return end
	local index = accumulator.count + 1
	local u = tonumber( vertex.u ) or 0
	local v = tonumber( vertex.v ) or 0
	local weight = index % 97 + 1
	accumulator.count = index
	accumulator.sx = accumulator.sx + position.x
	accumulator.sy = accumulator.sy + position.y
	accumulator.sz = accumulator.sz + position.z
	accumulator.su = accumulator.su + u
	accumulator.sv = accumulator.sv + v
	accumulator.wx = accumulator.wx + position.x * weight
	accumulator.wy = accumulator.wy + position.y * weight
	accumulator.wz = accumulator.wz + position.z * weight
	accumulator.wu = accumulator.wu + u * weight
	accumulator.wv = accumulator.wv + v * weight
	if not accumulator.minimum then
		accumulator.minimum = Vector( position.x, position.y, position.z )
		accumulator.maximum = Vector( position.x, position.y, position.z )
	else
		accumulator.minimum.x = math.min( accumulator.minimum.x, position.x )
		accumulator.minimum.y = math.min( accumulator.minimum.y, position.y )
		accumulator.minimum.z = math.min( accumulator.minimum.z, position.z )
		accumulator.maximum.x = math.max( accumulator.maximum.x, position.x )
		accumulator.maximum.y = math.max( accumulator.maximum.y, position.y )
		accumulator.maximum.z = math.max( accumulator.maximum.z, position.z )
	end
end

local function FinishFingerprint( accumulator )
	local minimum = accumulator.minimum or Vector( 0, 0, 0 )
	local maximum = accumulator.maximum or Vector( 0, 0, 0 )
	return string.format(
		"%s|n=%d|b=%.4f,%.4f,%.4f,%.4f,%.4f,%.4f|s=%.4f,%.4f,%.4f,%.5f,%.5f|w=%.4f,%.4f,%.4f,%.5f,%.5f",
		accumulator.material, accumulator.count,
		minimum.x, minimum.y, minimum.z, maximum.x, maximum.y, maximum.z,
		accumulator.sx, accumulator.sy, accumulator.sz,
		accumulator.su, accumulator.sv,
		accumulator.wx, accumulator.wy, accumulator.wz,
		accumulator.wu, accumulator.wv )
end

local function FingerprintRawMesh( meshData, yieldWork, skipSourceMetadata )
	local accumulator = NewFingerprintAccumulator( meshData.material )
	local sampleVertex
	local nonSourceVertexCount = 0
	local vertices = meshData.verticies
	if not vertices or #vertices == 0 then vertices = meshData.vertices end
	if not vertices or #vertices == 0 then vertices = meshData.triangles or {} end
	if skipSourceMetadata then
		for index, vertex in ipairs( vertices ) do
			if yieldWork and index % 64 == 0 then yieldWork() end
			AddFingerprintVertex( accumulator, vertex )
		end
		return FinishFingerprint( accumulator )
	end
	for index, vertex in ipairs( vertices ) do
		if yieldWork and index % 64 == 0 then yieldWork() end
		AddFingerprintVertex( accumulator, vertex )
		if vertex.pos then
			sampleVertex = sampleVertex or vertex
		elseif vertex.position then
			-- The shared accumulator also accepts cached records. Native source
			-- counts historically include only .pos, so retain that distinction.
			nonSourceVertexCount = nonSourceVertexCount + 1
		end
	end
	return FinishFingerprint( accumulator ),
		accumulator.count - nonSourceVertexCount, sampleVertex
end

-- Compute the established fingerprint, source count, and diagnostic sample in
-- one traversal while native records are available. Both runtimes avoid the
-- temporary source-vertex mirror; the capability flag handles cl_30 auto-refresh
-- while an older helper with only one return value is still loaded.
BBS.BuildRawMeshDamageFingerprint = FingerprintRawMesh
BBS.RawMeshDamageFingerprintStats = true

local function FingerprintCachedMesh( cachedMesh, yieldWork )
	if cachedMesh.damageFingerprint then return cachedMesh.damageFingerprint end
	local accumulator = NewFingerprintAccumulator( cachedMesh.material )
	for index, vertex in ipairs( cachedMesh.vertices or {} ) do
		if yieldWork and index % 64 == 0 then yieldWork() end
		AddFingerprintVertex( accumulator, vertex )
	end
	cachedMesh.damageFingerprint = FinishFingerprint( accumulator )
	return cachedMesh.damageFingerprint
end

local function CountRawFingerprints( meshes, yieldWork )
	local counts = {}
	for _, meshData in ipairs( meshes or {} ) do
		if yieldWork then yieldWork() end
		local fingerprint = FingerprintRawMesh( meshData, yieldWork, true )
		counts[ fingerprint ] = ( counts[ fingerprint ] or 0 ) + 1
	end
	return counts
end

local function AddBodygroupMeshOwnership( analysis, meshIndex, bodygroup )
	analysis.meshGroups[ meshIndex ] = analysis.meshGroups[ meshIndex ] or {}
	analysis.meshGroups[ meshIndex ][ bodygroup.id ] = bodygroup
end

local function TryCompiledBodypartOwnership( analysis, meshData,
	values, hideableBodygroups, yieldWork )
	if not BBS.GetCompiledBodypartMeshLayout then
		return false, "compiled MDL ownership reader is unavailable"
	end
	local layout, layoutError, layoutCacheHit =
		BBS.GetCompiledBodypartMeshLayout( meshData.model, values, meshData.lod )
	if yieldWork then yieldWork() end
	analysis.compiledOwnershipCacheHit = layoutCacheHit == true
	if not layout then return false, layoutError end
	analysis.compiledBodypartCount = table.Count( layout.bodyparts or {} )
	analysis.compiledMeshCount = layout.totalMeshes or 0
	if layout.totalMeshes ~= #meshData.meshes then
		return false, string.format(
			"compiled/runtime mesh count mismatch (%d/%d)",
			layout.totalMeshes or -1, #meshData.meshes )
	end
	-- The engine enumerates active bodypart meshes in MDL order. Verify that
	-- assumption against every unique-vertex count before authorizing any mesh;
	-- an unusual compiler/branch safely falls back to differential ownership.
	for _, compiled in pairs( layout.bodyparts or {} ) do
		if yieldWork then yieldWork() end
		for localMeshIndex, compiledMesh in ipairs( compiled.meshes or {} ) do
			local meshIndex = compiled.firstMesh + localMeshIndex - 1
			local runtimeMesh = meshData.meshes[ meshIndex ]
			local runtimeVertices = runtimeMesh and
				( runtimeMesh.persistedVertexCount
					or #( runtimeMesh.vertices or {} ) ) or -1
			local expectedVertices = compiledMesh.lod0VertexCount
			if expectedVertices == 0 then
				expectedVertices = compiledMesh.vertexCount
			end
			if runtimeVertices ~= expectedVertices then
				return false, string.format(
					"compiled/runtime vertex mismatch at mesh %d (%d/%d)",
					meshIndex, expectedVertices or -1, runtimeVertices or -1 )
			end
		end
	end

	local ownedMeshCount = 0
	local directBodygroupCount = 0
	for bodygroupId, compiled in pairs( layout.bodyparts or {} ) do
		if yieldWork then yieldWork() end
		for meshIndex = compiled.firstMesh, compiled.lastMesh do
			analysis.meshBodygroupIds[ meshIndex ] = bodygroupId
		end
	end
	for _, bodygroup in ipairs( hideableBodygroups ) do
		local compiled = layout.bodyparts[ bodygroup.id ]
		if compiled then
			bodygroup.ownershipSource = "compiled-mdl"
			bodygroup.compiledName = compiled.name
			bodygroup.compiledSelectedModel = compiled.selectedModelName
			bodygroup.compiledFirstMesh = compiled.firstMesh
			bodygroup.compiledLastMesh = compiled.lastMesh
			bodygroup.compiledMeshCount = compiled.meshCount
			directBodygroupCount = directBodygroupCount + 1
			for meshIndex = compiled.firstMesh, compiled.lastMesh do
				AddBodygroupMeshOwnership( analysis, meshIndex, bodygroup )
				ownedMeshCount = ownedMeshCount + 1
			end
		elseif bodygroup.overridden then
			analysis.unresolvedOverrideCount =
				analysis.unresolvedOverrideCount + 1
		end
	end
	analysis.compiledOwnership = true
	analysis.ownershipMode = "compiled-mdl"
	analysis.directOwnershipBodygroupCount = directBodygroupCount
	analysis.directOwnedMeshAssignments = ownedMeshCount
	return true
end

function BBS.GetHideableMeshAnalysis( entity, meshData, yieldWork )
	if not IsValid( entity ) or not meshData then
		return nil, "invalid entity or cached mesh data"
	end
	local cached = BBS.HideableMeshCache[ meshData.key ]
	if cached then return cached, nil, true end
	local started = SysTime()

	local values, maximumId, hideableBodygroups, inspectedBodygroups =
		BodygroupSnapshot( entity, meshData.bodygroups )
	if yieldWork then yieldWork() end
	local analysis = {
		cacheKey = meshData.key,
		selection = BodygroupString( values, maximumId ),
		bodygroups = hideableBodygroups,
		inspectedBodygroups = inspectedBodygroups,
		meshGroups = {},
		meshBodygroupIds = {},
		meshFingerprints = {},
		comparisonCount = 0,
		failedComparisons = 0,
		ambiguousFingerprints = 0,
		blockedBodygroupCount = 0,
		overriddenBodygroupCount = 0,
		unresolvedOverrideCount = 0,
	}
	for _, bodygroup in ipairs( inspectedBodygroups ) do
		if yieldWork then yieldWork() end
		if bodygroup.overridden then
			analysis.overriddenBodygroupCount = analysis.overriddenBodygroupCount + 1
		elseif bodygroup.hasBlank and not bodygroup.filterAllowed then
			analysis.blockedBodygroupCount = analysis.blockedBodygroupCount + 1
		end
	end

	local compiledOwnership, compiledError = TryCompiledBodypartOwnership(
		analysis, meshData, values, hideableBodygroups, yieldWork )
	analysis.compiledOwnershipError = compiledError
	if not compiledOwnership then
		local currentByFingerprint = {}
		for meshIndex, cachedMesh in ipairs( meshData.meshes ) do
			if yieldWork then yieldWork() end
			local fingerprint = FingerprintCachedMesh( cachedMesh, yieldWork )
			analysis.meshFingerprints[ meshIndex ] = fingerprint
			currentByFingerprint[ fingerprint ] =
				currentByFingerprint[ fingerprint ] or {}
			table.insert( currentByFingerprint[ fingerprint ], meshIndex )
		end
		for _, indexes in pairs( currentByFingerprint ) do
			if yieldWork then yieldWork() end
			if #indexes > 1 then
				analysis.ambiguousFingerprints =
					analysis.ambiguousFingerprints + 1
			end
		end
		-- Compatibility fallback for unsupported MDL revisions or unusual mesh
		-- enumeration. Production only needs the union of meshes owned by eligible
		-- bodygroups, so compare one selection with every eligible group changed.
		local alternateValues = table.Copy( values )
		local changedBodygroups = {}
		for _, bodygroup in ipairs( hideableBodygroups ) do
			if yieldWork then yieldWork() end
			local comparisonOption = BodygroupComparisonOption( bodygroup )
			bodygroup.comparisonOption = comparisonOption
			bodygroup.ownershipSource = "differential-fallback"
			if comparisonOption and comparisonOption.id ~= bodygroup.selected then
				alternateValues[ bodygroup.id ] = comparisonOption.id
				changedBodygroups[ #changedBodygroups + 1 ] = bodygroup
			elseif bodygroup.overridden then
				analysis.unresolvedOverrideCount =
					analysis.unresolvedOverrideCount + 1
			end
		end
		analysis.ownershipMode = "differential-fallback"
		analysis.combinedComparison = true
		analysis.comparisonBodygroupCount = #changedBodygroups
		if #changedBodygroups > 0 then
			local alternateSelection = BodygroupString( alternateValues, maximumId )
			-- Even a disk-loaded graph needs the Remix native-release barrier if
			-- an unsupported MDL requires differential ownership extraction.
			if BBS.IsActiveRTXRuntime and BBS.IsActiveRTXRuntime() then
				meshData.rtxNativeGraphPending = true
			end
			local ok, alternateMeshes = pcall( util.GetModelMeshes,
				meshData.model, meshData.lod, alternateSelection, meshData.skin )
			-- The engine call itself is native and cannot yield, but never combine its
			-- unavoidable hitch with fingerprinting the returned model graph.
			if yieldWork then yieldWork() end
			analysis.comparisonCount = 1
			if not ok or not alternateMeshes then
				analysis.failedComparisons = 1
			else
				local alternateCounts = CountRawFingerprints(
					alternateMeshes, yieldWork )
				local combinedGroupMap = {}
				for _, bodygroup in ipairs( changedBodygroups ) do
					combinedGroupMap[ bodygroup.id ] = bodygroup
				end
				for fingerprint, indexes in pairs( currentByFingerprint ) do
					if yieldWork then yieldWork() end
					if ( alternateCounts[ fingerprint ] or 0 ) < #indexes then
						for _, meshIndex in ipairs( indexes ) do
							analysis.meshGroups[ meshIndex ] = combinedGroupMap
						end
					end
				end
			end
		end
	else
		analysis.combinedComparison = false
		analysis.comparisonBodygroupCount = 0
	end

	analysis.hideableMeshCount = table.Count( analysis.meshGroups )
	analysis.buildMilliseconds = ( SysTime() - started ) * 1000
	-- Once ownership has been resolved, the unique source-vertex mirror is no
	-- longer needed: runtime queries and persistent writes use the indexed skin
	-- points plus triangle wrappers. Retaining it doubled tens of thousands of
	-- references for every cached model and made garbage-collection spikes much
	-- more likely after several different playermodels had appeared.
	for _, cachedMesh in ipairs( meshData.meshes or {} ) do
		if yieldWork then yieldWork() end
		cachedMesh.persistedVertexCount = cachedMesh.persistedVertexCount
			or #( cachedMesh.vertices or {} )
		FingerprintCachedMesh( cachedMesh, yieldWork )
		cachedMesh.vertices = nil
	end
	BBS.HideableMeshCache[ meshData.key ] = analysis
	return analysis, nil, false
end

local function SortedBodygroupNames( groupMap )
	local values = {}
	for _, bodygroup in pairs( groupMap or {} ) do
		local blankIds = {}
		for _, option in ipairs( bodygroup.blankOptions or {} ) do
			blankIds[ #blankIds + 1 ] = tostring( option.id )
		end
		if bodygroup.overridden then
			values[ #values + 1 ] = string.format( "%d:%s(override,owner=%s%s)",
				bodygroup.id, bodygroup.name,
				tostring( bodygroup.ownershipSource or "unresolved" ),
				bodygroup.comparisonOption and
					( ",compare=" .. tostring( bodygroup.comparisonOption.id ) ) or "" )
		else
			values[ #values + 1 ] = string.format( "%d:%s(blank=%s,owner=%s)",
				bodygroup.id, bodygroup.name, table.concat( blankIds, "/" ),
				tostring( bodygroup.ownershipSource or "unresolved" ) )
		end
	end
	table.sort( values )
	return values
end

local function DebugSubmodelName( name )
	name = tostring( name or "" )
	return string.Trim( name ) == "" and "<empty>" or name
end

local function BlankOptionSummary( bodygroup )
	local values = {}
	for _, option in ipairs( bodygroup and bodygroup.blankOptions or {} ) do
		values[ #values + 1 ] = string.format( "%d:%s(%s%s)", option.id,
			DebugSubmodelName( option.name ), tostring( option.reason ),
			option.inferred and ",inferred" or "" )
	end
	return #values > 0 and table.concat( values, "," ) or "<none>"
end

local function DebugRawValue( value )
	value = tostring( value or "" )
	value = string.gsub( value, "\r", "\\r" )
	value = string.gsub( value, "\n", "\\n" )
	return value == "" and "<empty>" or value
end

BodygroupHelpers.SortedNames = SortedBodygroupNames
BodygroupHelpers.DebugSubmodelName = DebugSubmodelName
BodygroupHelpers.BlankOptionSummary = BlankOptionSummary
BodygroupHelpers.DebugRawValue = DebugRawValue
end

local function AddUniqueUV( target, seen, u, v )
	if not isnumber( u ) or not isnumber( v )
	or u ~= u or v ~= v or math.abs( u ) > 100000 or math.abs( v ) > 100000 then
		return false
	end
	local key = string.format( "%.7f|%.7f", u, v )
	if seen[ key ] then return true end
	seen[ key ] = true
	target[ #target + 1 ] = { u = u, v = v }
	return true
end

-- Declared here and assigned beside the UV rasterizer below. Layer resolution
-- runs only after this file has loaded, so the forward reference is safe while
-- keeping the mask's CPU coverage implementation next to its raster equivalent.
local MaskHasDamageAtUV

local function BuildUVTransformAffine( matrix )
	if not matrix then return nil end
	local origin = matrix * Vector( 0, 0, 0 )
	local unitU = matrix * Vector( 1, 0, 0 )
	local unitV = matrix * Vector( 0, 1, 0 )
	return {
		uu = unitU.x - origin.x,
		uv = unitV.x - origin.x,
		uc = origin.x,
		vu = unitU.y - origin.y,
		vv = unitV.y - origin.y,
		vc = origin.y,
	}
end

local function TransformSingleUV( u, v, transform )
	if not transform then return u, v end
	if transform.uu then
		return transform.uu * u + transform.uv * v + transform.uc,
			transform.vu * u + transform.vv * v + transform.vc
	end
	local point = transform * Vector( u, v, 0 )
	return point.x, point.y
end

local function FindExistingDamageMask( entity, meshMaterial )
	local state = IsValid( entity ) and BBS.DamageStates[ entity ] or nil
	if not state then return nil end
	local target = NormalizeMaterialPath( meshMaterial )
	local suffixMatch
	for _, mask in pairs( state.masks or {} ) do
		local original = NormalizeMaterialPath( mask.originalPath )
		if original == target then return mask end
		if not suffixMatch and original ~= "" and target ~= ""
		and ( string.EndsWith( original, target )
		or string.EndsWith( target, original ) ) then
			suffixMatch = mask
		end
	end
	return suffixMatch
end

local function MeshPassesThroughExistingDamage( entity, matchingMesh )
	local mask = FindExistingDamageMask( entity, matchingMesh.material )
	if not mask or not MaskHasDamageAtUV then return false, 0, 0, mask end
	local sampleCount = 0
	local openSampleCount = 0
	for _, triangle in ipairs( matchingMesh.triangles or {} ) do
		local sample = triangle.centerlineUV
		if sample and isnumber( sample.u ) and isnumber( sample.v )
		and sample.u == sample.u and sample.v == sample.v
		and math.abs( sample.u ) <= 100000
		and math.abs( sample.v ) <= 100000 then
			sampleCount = sampleCount + 1
			local u, v = TransformSingleUV(
				sample.u, sample.v, mask.baseTextureTransform )
			if MaskHasDamageAtUV( mask, u, v ) then
				openSampleCount = openSampleCount + 1
			end
		end
	end
	-- A mesh may contain both the front and rear surface of a clothing shell.
	-- It is transparent to the ray only when every centerline crossing is already
	-- removed. Edge-only cylinder overlap has no ray sample and remains blocking.
	return sampleCount > 0 and openSampleCount == sampleCount,
		sampleCount, openSampleCount, mask
end

local function GetAdvancedBodygroupHiddenSet( entity )
	local tool = _G.AdvancedBodygroupTool
	if not istable( tool ) or not isfunction( tool.GetHiddenBodygroupSet ) then
		return nil
	end
	local ok, hidden = pcall( tool.GetHiddenBodygroupSet, entity )
	if not ok or not istable( hidden ) then return nil end
	return hidden
end

local function MeshHiddenByAdvancedBodygroupTool( eligibility, meshIndex,
	hiddenBodygroups )
	if not hiddenBodygroups then return false, nil end
	local bodygroupId = eligibility.meshBodygroupIds
		and eligibility.meshBodygroupIds[ meshIndex ] or nil
	return bodygroupId ~= nil and hiddenBodygroups[ bodygroupId ] == true,
		bodygroupId
end

local function BuildDamageLayerSelection( hit, query, meshData, eligibility )
	local limit = math.Clamp( math.floor( tonumber( hit.damageLayerLimit
		or query.layerLimit or GetInt( "bbs_damage_layer_limit", 0 ) ) or 0 ), 0, 64 )
	local collectLayerDiagnostics = hit.synthetic
		or GetBool( "bbs_debug_console", false )
		or GetBool( "bbs_debug_hud", false )
		or GetBool( "bbs_damage_dump_debug", false )
	local hiddenBodygroups = GetAdvancedBodygroupHiddenSet( hit.entity )
	-- Unlimited mode cannot be affected by visual occluders or earlier holes. In
	-- normal play, select every eligible intersecting mesh directly and avoid a
	-- material lookup, CPU mask query, layer table allocation, and sort per shot.
	if limit == 0 and not collectLayerDiagnostics then
		local selectedMeshes = {}
		local surfaceCount = 0
		local selectedDamageableLayerCount = 0
		local advancedBodygroupHiddenSurfaceCount = 0
		for _, matchingMesh in ipairs( query.meshes or {} ) do
			local hidden = MeshHiddenByAdvancedBodygroupTool( eligibility,
				matchingMesh.meshIndex, hiddenBodygroups )
			if hidden then
				advancedBodygroupHiddenSurfaceCount =
					advancedBodygroupHiddenSurfaceCount + 1
			else
				surfaceCount = surfaceCount + 1
			end
			if not hidden and eligibility.meshGroups[ matchingMesh.meshIndex ] then
				selectedDamageableLayerCount = selectedDamageableLayerCount + 1
				selectedMeshes[ matchingMesh.meshIndex ] = surfaceCount
			end
		end
		return selectedMeshes, {
			limit = 0,
			layers = {},
			surfaceCount = surfaceCount,
			layerCount = surfaceCount,
			selectedLayerCount = surfaceCount,
			selectedDamageableLayerCount = selectedDamageableLayerCount,
			blockedDamageableMeshCount = 0,
			passedExistingHoleCount = 0,
			advancedBodygroupHiddenSurfaceCount =
				advancedBodygroupHiddenSurfaceCount,
			ownershipSource = "mesh-surface-fast-unlimited",
			ownershipError = nil,
			occludersIncluded = query.layerOccludersIncluded == true,
		}
	end
	local layers = {}
	for _, matchingMesh in ipairs( query.meshes or {} ) do
		local minimumDepth = matchingMesh.minimumLayerDepth or 0
		local maximumDepth = matchingMesh.maximumLayerDepth or minimumDepth
		local centerlineDepth
		for _, triangle in ipairs( matchingMesh.triangles or {} ) do
			if triangle.centerlineUV then
				centerlineDepth = math.min( centerlineDepth or math.huge,
					triangle.centerlineDepth or triangle.layerDepth or minimumDepth )
			end
		end
		local passesHole, raySamples, openRaySamples, mask =
			MeshPassesThroughExistingDamage( hit.entity, matchingMesh )
		local hiddenByBodygroupTool, bodygroupId =
			MeshHiddenByAdvancedBodygroupTool( eligibility,
				matchingMesh.meshIndex, hiddenBodygroups )
		layers[ #layers + 1 ] = {
			key = "mesh:" .. tostring( matchingMesh.meshIndex ),
			name = string.format( "mesh %d (%s)", matchingMesh.meshIndex,
				tostring( matchingMesh.material or "unknown material" ) ),
			minimumDepth = minimumDepth,
			maximumDepth = maximumDepth,
			centerlineDepth = centerlineDepth,
			sortDepth = centerlineDepth or minimumDepth,
			meshIndices = { matchingMesh.meshIndex },
			meshIndex = matchingMesh.meshIndex,
			damageable = eligibility.meshGroups[ matchingMesh.meshIndex ] ~= nil,
			advancedBodygroupToolHidden = hiddenByBodygroupTool,
			bodygroupId = bodygroupId,
			passesExistingHole = passesHole,
			consumesLayer = not passesHole and not hiddenByBodygroupTool,
			raySampleCount = raySamples,
			openRaySampleCount = openRaySamples,
			damageMaskSerial = mask and mask.serial or nil,
		}
	end
	table.sort( layers, function( first, second )
		if math.abs( first.sortDepth - second.sortDepth ) > 0.0001 then
			return first.sortDepth < second.sortDepth
		end
		return first.key < second.key
	end )

	local selectedMeshes = {}
	local countedLayerCount = 0
	local selectedLayerCount = 0
	local selectedDamageableLayerCount = 0
	local blockedDamageableMeshCount = 0
	local passedExistingHoleCount = 0
	local advancedBodygroupHiddenSurfaceCount = 0
	for surfaceIndex, layer in ipairs( layers ) do
		layer.surfaceIndex = surfaceIndex
		if layer.consumesLayer then
			countedLayerCount = countedLayerCount + 1
			layer.countedIndex = countedLayerCount
			layer.index = countedLayerCount
			layer.selected = limit == 0 or countedLayerCount <= limit
		elseif layer.advancedBodygroupToolHidden then
			layer.index = surfaceIndex
			layer.selected = false
			advancedBodygroupHiddenSurfaceCount =
				advancedBodygroupHiddenSurfaceCount + 1
		else
			layer.index = surfaceIndex
			layer.selected = false
			passedExistingHoleCount = passedExistingHoleCount + 1
		end
		if layer.selected and layer.consumesLayer then
			selectedLayerCount = selectedLayerCount + 1
			if layer.damageable then
				selectedDamageableLayerCount = selectedDamageableLayerCount + 1
			end
		end
		for _, meshIndex in ipairs( layer.meshIndices ) do
			if eligibility.meshGroups[ meshIndex ] then
				if layer.selected then
					selectedMeshes[ meshIndex ] = layer.countedIndex
				elseif layer.consumesLayer then
					blockedDamageableMeshCount = blockedDamageableMeshCount + 1
				end
			end
		end
	end
	return selectedMeshes, {
		limit = limit,
		layers = layers,
		surfaceCount = #layers,
		layerCount = countedLayerCount,
		selectedLayerCount = selectedLayerCount,
		selectedDamageableLayerCount = selectedDamageableLayerCount,
		blockedDamageableMeshCount = blockedDamageableMeshCount,
		passedExistingHoleCount = passedExistingHoleCount,
		advancedBodygroupHiddenSurfaceCount =
			advancedBodygroupHiddenSurfaceCount,
		ownershipSource = "mesh-surface",
		ownershipError = nil,
		occludersIncluded = query.layerOccludersIncluded == true,
	}
end

local function BuildAffectedUVResult( hit, query, meshData, eligibility )
	local collectUVDiagnostics = hit.synthetic
		or GetBool( "bbs_debug_console", false )
		or GetBool( "bbs_debug_hud", false )
		or GetBool( "bbs_damage_uv_preview", false )
		or GetBool( "bbs_damage_dump_debug", false )
		or GetBool( "bbs_damage_validate_copy", false )
		or GetBool( "bbs_damage_verbose_uv", false )
	local selectedLayerMeshes, layerSelection = BuildDamageLayerSelection(
		hit, query, meshData, eligibility )
	local result = {
		ok = true,
		status = "uv_ready",
		meshCacheKey = meshData.key,
		bodygroups = eligibility.bodygroups,
		inspectedBodygroups = eligibility.inspectedBodygroups,
		hideableMeshCount = eligibility.hideableMeshCount,
		meshes = {},
		materials = {},
		materialByKey = {},
		affectedMeshCount = 0,
		affectedMaterialCount = 0,
		triangleCount = 0,
		uvCount = 0,
		missingUVTriangleCount = 0,
		queuedMaterialCount = 0,
		appliedMaterialCount = 0,
		layerLimit = layerSelection.limit,
		layers = layerSelection.layers,
		layerSurfaceCount = layerSelection.surfaceCount,
		layerCount = layerSelection.layerCount,
		selectedLayerCount = layerSelection.selectedLayerCount,
		selectedDamageableLayerCount = layerSelection.selectedDamageableLayerCount,
		blockedDamageableMeshCount = layerSelection.blockedDamageableMeshCount,
		passedExistingHoleCount = layerSelection.passedExistingHoleCount,
		advancedBodygroupHiddenSurfaceCount =
			layerSelection.advancedBodygroupHiddenSurfaceCount or 0,
		layerOwnershipSource = layerSelection.ownershipSource,
		layerOwnershipError = layerSelection.ownershipError,
		layerOccludersIncluded = layerSelection.occludersIncluded,
		uvDiagnosticsCollected = collectUVDiagnostics,
	}

	for _, matchingMesh in ipairs( query.meshes or {} ) do
		local hideableGroups = eligibility.meshGroups[ matchingMesh.meshIndex ]
		local layerIndex = selectedLayerMeshes[ matchingMesh.meshIndex ]
		if hideableGroups and layerIndex then
			local meshTriangleCount = 0
			local meshRecord = {
				meshIndex = matchingMesh.meshIndex,
				layerIndex = layerIndex,
				material = matchingMesh.material,
				bodygroups = hideableGroups,
				bodygroupNames = collectUVDiagnostics
					and BodygroupHelpers.SortedNames( hideableGroups ) or {},
				triangles = {},
				uvs = {},
				uvSeen = collectUVDiagnostics and {} or nil,
			}
			local materialKey = NormalizeMaterialPath( matchingMesh.material )
			local materialRecord = result.materialByKey[ materialKey ]
			if not materialRecord then
				materialRecord = {
					key = materialKey,
					material = matchingMesh.material,
					meshIndices = {},
					meshSeen = {},
					triangles = {},
					uvs = {},
					uvSeen = collectUVDiagnostics and {} or nil,
					status = "uv_ready",
				}
				result.materialByKey[ materialKey ] = materialRecord
				result.materials[ #result.materials + 1 ] = materialRecord
			end
			if not materialRecord.meshSeen[ matchingMesh.meshIndex ] then
				materialRecord.meshSeen[ matchingMesh.meshIndex ] = true
				materialRecord.meshIndices[ #materialRecord.meshIndices + 1 ] = matchingMesh.meshIndex
			end

			for _, triangle in ipairs( matchingMesh.triangles or {} ) do
				local sourceVertices = triangle.vertices or {}
				local complete = #sourceVertices == 3
				for _, vertex in ipairs( sourceVertices ) do
					local u = vertex.u
					local v = vertex.v
					local worldPosition = vertex.worldPosition
					if not isnumber( u ) or not isnumber( v )
					or u ~= u or v ~= v
					or math.abs( u ) > 100000 or math.abs( v ) > 100000
					or not isvector( worldPosition ) then
						complete = false
						break
					end
				end
				if complete then
					local triangleRecord = {
						meshIndex = matchingMesh.meshIndex,
						triangleIndex = triangle.triangleIndex,
						sourceVertices = sourceVertices,
					}
					local coordinates
					if collectUVDiagnostics then
						coordinates = {}
						triangleRecord.world = {}
						for _, vertex in ipairs( sourceVertices ) do
							coordinates[ #coordinates + 1 ] = {
								u = vertex.u, v = vertex.v,
							}
							triangleRecord.world[ #triangleRecord.world + 1 ] =
								vertex.worldPosition
						end
						triangleRecord.uv = coordinates
					end
					if collectUVDiagnostics then
						meshRecord.triangles[ #meshRecord.triangles + 1 ] = triangleRecord
					end
					materialRecord.triangles[ #materialRecord.triangles + 1 ] = triangleRecord
					meshTriangleCount = meshTriangleCount + 1
					result.triangleCount = result.triangleCount + 1
					if collectUVDiagnostics then
						for _, coordinate in ipairs( coordinates ) do
							AddUniqueUV( meshRecord.uvs, meshRecord.uvSeen,
								coordinate.u, coordinate.v )
							AddUniqueUV( materialRecord.uvs, materialRecord.uvSeen,
								coordinate.u, coordinate.v )
						end
					end
				else
					result.missingUVTriangleCount = result.missingUVTriangleCount + 1
				end
			end

			meshRecord.uvSeen = nil
			if meshTriangleCount > 0 then
				result.affectedMeshCount = result.affectedMeshCount + 1
				if collectUVDiagnostics then
					result.meshes[ #result.meshes + 1 ] = meshRecord
				end
			end
		end
	end

	local filteredMaterials = {}
	for _, materialRecord in ipairs( result.materials ) do
		materialRecord.meshSeen = nil
		materialRecord.uvSeen = nil
		if #materialRecord.triangles > 0 then
			filteredMaterials[ #filteredMaterials + 1 ] = materialRecord
			result.uvCount = result.uvCount + #materialRecord.uvs
		end
	end
	result.materials = filteredMaterials
	result.affectedMaterialCount = #filteredMaterials
	return result
end

local function FindSubmaterial( entity, meshMaterial )
	local materials = entity:GetMaterials() or {}
	local target = NormalizeMaterialPath( meshMaterial )
	for index, materialPath in ipairs( materials ) do
		if NormalizeMaterialPath( materialPath ) == target then
			return index - 1, materialPath, "exact"
		end
	end
	for index, materialPath in ipairs( materials ) do
		local normalized = NormalizeMaterialPath( materialPath )
		if normalized ~= "" and target ~= ""
		and ( string.EndsWith( normalized, target )
		or string.EndsWith( target, normalized ) ) then
			return index - 1, materialPath, "suffix"
		end
	end
	if #materials == 1 then return 0, materials[ 1 ], "only-material" end
	return nil, nil, "not-found"
end

local INTERNAL_MATERIAL_KEYS = {
	[ "$flags" ] = true,
	[ "$flags_defined" ] = true,
	[ "$flags2" ] = true,
	[ "$flags_defined2" ] = true,
	[ "$flagsdefined" ] = true,
	[ "$flagsdefined2" ] = true,
}

local MAX_VMT_INCLUDE_DEPTH = 4

-- IMaterial:GetKeyValues() is lossy: it exposes internal flags and turns VMT
-- texture-transform literals into VMatrix values. Prefer the mounted VMT text
-- so CreateMaterial receives the same strings the material author wrote.
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
		elseif character == "/" and string.sub( source, index + 1, index + 1 ) == "/" then
			local newline = string.find( source, "\n", index, true )
			index = newline and newline + 1 or #source + 1
		elseif character == "{" or character == "}" then
			tokens[ #tokens + 1 ] = character
			index = index + 1
		elseif character == "[" then
			local close = string.find( source, "]", index, true )
			if not close then break end
			local bracketed = string.sub( source, index, close )
			-- Preserve numeric vectors. Hardware condition suffixes are ignored.
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
	local source = file.Read( "materials/" .. path .. ".vmt", "GAME" )
	if not source or source == "" then return nil end
	local tokens = TokenizeVMT( source )
	local opening = 1
	while opening <= #tokens and tokens[ opening ] ~= "{" do opening = opening + 1 end
	if opening < 2 or tokens[ opening ] ~= "{" then return nil end

	local shader = tokens[ opening - 1 ]
	local parameters = ParseVMTBlock( tokens, opening )
	if string.lower( shader ) ~= "patch" then return parameters, shader end

	local include = parameters.include
	parameters.include = nil
	local parent, parentShader = include and ReadMaterialVMT( include, depth + 1 ) or nil
	if not parent then return parameters, nil end
	local merged = MergeVMTParameters( {}, parent )
	-- Patch insert fills absent values; replace deliberately overwrites them.
	MergeVMTParameters( merged, parameters.insert, true )
	MergeVMTParameters( merged, parameters.replace, false )
	parameters.insert = nil
	parameters.replace = nil
	MergeVMTParameters( merged, parameters, false )
	return merged, parentShader
end

local function NumberToVMTString( value )
	if value == math.floor( value ) and math.abs( value ) < 1e9 then
		return string.format( "%d", value )
	end
	local output = string.format( "%.8f", value )
	output = string.gsub( output, "0+$", "" )
	return string.gsub( output, "%.$", "" )
end

local function SanitizeMaterialValue( value, droppedCounter )
	if isstring( value ) then return value end
	if isnumber( value ) then return NumberToVMTString( value ) end
	if isbool( value ) then return value and "1" or "0" end
	if isvector( value ) then
		return string.format( "[%s %s %s]", NumberToVMTString( value.x ),
			NumberToVMTString( value.y ), NumberToVMTString( value.z ) )
	end
	if TypeID( value ) == TYPE_TEXTURE then
		local ok, name = pcall( value.GetName, value )
		return ok and NormalizeMaterialPath( name ) or nil
	end
	if TypeID( value ) == TYPE_MATRIX then
		droppedCounter.count = droppedCounter.count + 1
		return nil
	end
	if istable( value ) then
		local output = {}
		for rawKey, child in pairs( value ) do
			local key = string.lower( tostring( rawKey ) )
			if INTERNAL_MATERIAL_KEYS[ key ] then
				droppedCounter.count = droppedCounter.count + 1
			else
				local sanitized = SanitizeMaterialValue( child, droppedCounter )
				if sanitized ~= nil then output[ key ] = sanitized end
			end
		end
		return output
	end
	droppedCounter.count = droppedCounter.count + 1
	return nil
end

local function CountMaterialParameters( parameters )
	local count = 0
	for _, value in pairs( parameters or {} ) do
		count = count + 1
		if istable( value ) then count = count + CountMaterialParameters( value ) end
	end
	return count
end

local function MaterialParameterEnabled( parameters, name )
	local value = parameters and parameters[ string.lower( name ) ]
	if isbool( value ) then return value end
	if isnumber( value ) then return value ~= 0 end
	if value == nil then return false end
	value = string.lower( string.Trim( tostring( value ) ) )
	return value ~= "" and value ~= "0" and value ~= "false" and value ~= "no"
end

local function IsUsableMaterial( material )
	if not material then return false end
	local ok, isError = pcall( material.IsError, material )
	return ok and not isError
end

-- Advanced Material Editor does not alter the model's original VMT. It builds
-- an !advmat_* procedural material containing the effective base VMT plus the
-- selected rule. Reading Material( originalPath ) consequently loses every AME
-- edit. Resolve the public AME rule/build tables when the addon is present, but
-- retain a completely optional integration so BBS has no hard dependency.
local function CanonicalCompatibilityValue( value, canonicalFunction )
	if isfunction( canonicalFunction ) then
		local ok, text = pcall( canonicalFunction, value )
		if ok and isstring( text ) then return text end
	end
	local ok, text = pcall( util.TableToJSON,
		istable( value ) and value or { value = tostring( value ) }, false )
	return ok and text or tostring( value )
end

local function ResolveAdvancedMaterialEditorSource( entity, submaterialIndex,
	originalPath )
	local advmat = _G.AdvMat
	local client = istable( advmat ) and advmat.Client or nil
	local apply = istable( advmat ) and advmat.Apply or nil
	if not istable( client ) or not istable( apply ) then return nil, false end

	local rawOverride = ""
	if IsValid( entity ) and entity.GetSubMaterial then
		local ok, value = pcall( entity.GetSubMaterial, entity, submaterialIndex )
		if ok and isstring( value ) then rawOverride = value end
	end
	local serverMaterialName = string.match( rawOverride, "^!(advmat_.+)$" )
	local clientMaterialName
	local clientSet = apply.ClientSet
		and apply.ClientSet[ entity:EntIndex() ] or nil
	if istable( clientSet ) and isstring( clientSet[ submaterialIndex ] ) then
		clientMaterialName = clientSet[ submaterialIndex ]
	end

	local rule, preview, resolveError
	if isfunction( client.Resolve ) then
		local ok, resolvedRule, isPreview = pcall( client.Resolve,
			entity, submaterialIndex, originalPath )
		if ok then
			rule = resolvedRule
			preview = isPreview == true
		else
			resolveError = tostring( resolvedRule )
		end
	end
	if rule and isfunction( advmat.RuleIsEmpty ) then
		local ok, empty = pcall( advmat.RuleIsEmpty, rule )
		if ok and empty then rule = nil end
	end

	local material, materialName, buildError
	if rule and isfunction( apply.BuildForRule ) then
		local ok, builtMaterial, builtName = pcall( apply.BuildForRule, rule )
		if ok then
			material = builtMaterial
			materialName = builtName
		else
			buildError = tostring( builtMaterial )
		end
	end
	materialName = materialName or clientMaterialName or serverMaterialName
	local entry = materialName and istable( apply.Built )
		and apply.Built[ materialName ] or nil
	if not IsUsableMaterial( material ) and istable( entry ) then
		material = entry.mat
	end
	if not IsUsableMaterial( material ) then
		local expected = rule ~= nil or serverMaterialName ~= nil
			or clientMaterialName ~= nil
		return nil, expected, expected and string.format(
			"AME material is pending (rule=%s server=%s client=%s resolve=%s build=%s)",
			tostring( rule ~= nil ), tostring( serverMaterialName ),
			tostring( clientMaterialName ), tostring( resolveError ),
			tostring( buildError ) ) or nil
	end

	local parameters = istable( entry ) and istable( entry.kv )
		and table.Copy( entry.kv ) or nil
	local generatedTextures = istable( entry ) and istable( entry.gen )
		and entry.gen or nil
	local generatedTextureCount = 0
	for _ in pairs( generatedTextures or {} ) do
		generatedTextureCount = generatedTextureCount + 1
	end

	local canonical = istable( advmat.Gen ) and advmat.Gen.Canonical or nil
	local identityText = table.concat( {
		tostring( materialName or material:GetName() or "" ),
		CanonicalCompatibilityValue( rule or {}, canonical ),
		CanonicalCompatibilityValue( parameters or {}, canonical ),
	}, "|" )
	return {
		material = material,
		materialName = materialName,
		overrideName = materialName and ( "!" .. materialName ) or nil,
		parameters = parameters,
		parametersAuthoritative = parameters ~= nil,
		generatedTextures = generatedTextures,
		generatedTextureCount = generatedTextureCount,
		shader = ( istable( entry ) and entry.shader )
			or material:GetShader(),
		rule = rule,
		ruleScope = rule and rule.scope or nil,
		ruleMaterial = rule and rule.mat or nil,
		preview = preview == true,
		clientOwned = clientMaterialName ~= nil,
		rawOverride = rawOverride,
		resolveError = resolveError,
		buildError = buildError,
		sourceKind = preview and "advanced-material-editor-preview"
			or "advanced-material-editor-rule",
		identity = "ame:" .. util.CRC( identityText ),
	}, false
end

local ABT_BODYGROUP_DIGITS = "0123456789abcdefghijklmnopqrstuvwxyz"

local function AdvancedBodygroupToolIdentity( tool, entity )
	local values = {}
	local maximumId = -1
	for rawKey, group in pairs( entity:GetBodyGroups() or {} ) do
		if istable( group ) then
			local id = tonumber( group.id ) or tonumber( rawKey )
			if id then
				maximumId = math.max( maximumId, id )
				local value = math.Clamp( math.floor( tonumber(
					entity:GetBodygroup( id ) ) or 0 ), 0,
					#ABT_BODYGROUP_DIGITS - 1 )
				values[ id + 1 ] = string.sub( ABT_BODYGROUP_DIGITS,
					value + 1, value + 1 )
			end
		end
	end
	for index = 1, maximumId + 1 do values[ index ] = values[ index ] or "0" end
	local selection = table.concat( values )
	if selection == "" then selection = "0" end
	local hiddenKey = tool.HiddenNWKey or "ABT_HiddenBodygroups"
	local hiddenRegions = ""
	if isfunction( tool.GetHiddenRegionEncoding ) then
		local ok, encoded = pcall( tool.GetHiddenRegionEncoding, entity )
		if ok and isstring( encoded ) then hiddenRegions = encoded end
	end
	local parts = {
		entity:GetModel() or "", selection, tostring( entity:GetSkin() or 0 ),
		entity:GetNW2String( hiddenKey, "" ), hiddenRegions,
	}
	for index = 0, math.min( #( entity:GetMaterials() or {} ) - 1,
		MAX_SUBMATERIALS - 1 ) do
		parts[ #parts + 1 ] = entity:GetSubMaterial( index ) or ""
	end
	return table.concat( parts, "|" ), parts[ 4 ] ~= "" or hiddenRegions ~= ""
end

-- Advanced Bodygroup Tool applies its alpha-only bodygroup/region mask from a
-- private RenderOverride. Its public client state is the only lossless source:
-- rebuilding from the disk VMT would make a hidden bodygroup visible again.
local function ResolveAdvancedBodygroupToolSource( entity, submaterialIndex )
	local tool = _G.AdvancedBodygroupTool
	if not istable( tool ) or not IsValid( entity ) then return nil, false end
	local identity, active = AdvancedBodygroupToolIdentity( tool, entity )
	if not active then return nil, false end
	local state = istable( tool.ClientStates ) and tool.ClientStates[ entity ] or nil
	if not istable( state ) or state.identity ~= identity then
		return nil, true, "ABT alpha material is waiting for its current client state"
	end
	local resource = istable( state.resources )
		and state.resources[ submaterialIndex ] or nil
	if not istable( resource ) or not IsUsableMaterial( resource.material ) then
		-- The state is current and this material has no triangles in a hidden
		-- bodygroup/region. That is a real no-op rather than a build failure.
		return nil, false
	end
	local target = resource.target
	local targetName = target and target.GetName and target:GetName() or ""
	return {
		material = resource.material,
		resource = resource,
		state = state,
		stateIdentity = identity,
		materialName = resource.material:GetName(),
		target = target,
		targetName = targetName,
		identity = "abt:" .. util.CRC( identity .. "|" .. targetName ),
		sourceKind = "advanced-bodygroup-tool-alpha",
	}, false
end

local function SourceTextureDimensions( texture )
	if not texture or texture:IsError() then return nil, nil end
	-- Engine texture LOD can reduce Width/Height without changing the authored
	-- image. Keep its original canvas; this does not change global texture LOD
	-- or recover detail from mip levels the engine has not loaded.
	return texture:GetMappingWidth(), texture:GetMappingHeight()
end

local function ResolveEditedMaterialSources( entity, submaterialIndex,
	originalPath )
	local advancedMaterial, amePending, ameReason =
		ResolveAdvancedMaterialEditorSource( entity, submaterialIndex, originalPath )
	local advancedBodygroup, abtPending, abtReason =
		ResolveAdvancedBodygroupToolSource( entity, submaterialIndex )
	-- ABT is intentionally alpha-only. Its render target may have been built
	-- while BBS or another editor owned the slot, so using its RGB as the primary
	-- source can recursively clone an older damage material. AME (when present)
	-- owns RGB/parameters; otherwise the mounted VMT remains the primary source.
	local primary = advancedMaterial
	local sourceMaterial = primary and primary.material or Material( originalPath )
	local sourceTexture = sourceMaterial and not sourceMaterial:IsError()
		and sourceMaterial:GetTexture( "$basetexture" ) or nil
	local sourceWidth, sourceHeight = SourceTextureDimensions( sourceTexture )
	local signature = table.concat( {
		advancedMaterial and advancedMaterial.identity or "ame:none",
		advancedBodygroup and advancedBodygroup.identity or "abt:none",
		"source:" .. tostring( sourceWidth ) .. "x" .. tostring( sourceHeight ),
	}, "|" )
	return {
		advancedMaterialEditor = advancedMaterial,
		advancedBodygroupTool = advancedBodygroup,
		primary = primary,
		signature = signature,
		pending = amePending or abtPending or false,
		pendingReason = ameReason or abtReason,
	}
end

local function CloneMaterialParameters( originalPath, original, renderTargetName,
	effectiveSource )
	originalPath = NormalizeMaterialPath( originalPath )
	local template
	if effectiveSource then
		local source = effectiveSource.parameters
		local sourceKind = effectiveSource.sourceKind
		local keyValuesFallback = not istable( source )
		if keyValuesFallback then
			source = original:GetKeyValues() or {}
			sourceKind = sourceKind .. "+GetKeyValues-fallback"
		end
		local sourceAlphaStyle = MaterialParameterEnabled( source, "$alphatest" )
			or MaterialParameterEnabled( source, "$translucent" )
		local droppedCounter = { count = 0 }
		local parameters = SanitizeMaterialValue( source, droppedCounter ) or {}
		-- As with the regular fallback below, an unauthored engine-default
		-- $alpha must not turn into an authored AME override in the clone.
		if keyValuesFallback then parameters[ "$alpha" ] = nil end
		template = {
			parameters = parameters,
			sourceShader = effectiveSource.shader,
			sourceKind = sourceKind,
			sourceAlphaStyle = sourceAlphaStyle,
			droppedCount = droppedCounter.count,
		}
	else
		template = BBS.DamageMaterialTemplateCache[ originalPath ]
	end
	if not template then
		local source, sourceShader = ReadMaterialVMT( originalPath )
		local sourceKind = source and "vmt" or "GetKeyValues-fallback"
		if not source then source = original:GetKeyValues() or {} end
		local sourceAlphaStyle = MaterialParameterEnabled( source, "$alphatest" )
			or MaterialParameterEnabled( source, "$translucent" )
		local droppedCounter = { count = 0 }
		local parameters = SanitizeMaterialValue( source, droppedCounter ) or {}
		-- GetKeyValues exposes a default $alpha even when the VMT did not author it.
		if sourceKind == "GetKeyValues-fallback" then parameters[ "$alpha" ] = nil end
		template = {
			parameters = parameters,
			sourceShader = sourceShader,
			sourceKind = sourceKind,
			sourceAlphaStyle = sourceAlphaStyle,
			droppedCount = droppedCounter.count,
		}
		BBS.DamageMaterialTemplateCache[ originalPath ] = template
	end
	local parameters = table.Copy( template.parameters )
	local inheritedNoCull = parameters[ "$nocull" ]
	parameters[ "$basetexture" ] = renderTargetName
	if GetBool( "bbs_damage_force_nocull", true ) then
		parameters[ "$nocull" ] = "1"
	end
	parameters[ "$alphatestreference" ] = tostring(
		BBS.MaterialSafety.AlphaTestReference( parameters ) )
	parameters[ "$alphatest" ] = "1"
	parameters[ "$allowalphatocoverage" ] = "1"
	return parameters, CountMaterialParameters( parameters ),
		template.droppedCount, template.sourceShader,
		template.sourceKind, template.sourceAlphaStyle, inheritedNoCull
end

local function EscapeVMTString( value )
	value = tostring( value or "" )
	value = string.gsub( value, "\\", "\\\\" )
	return string.gsub( value, '"', '\\"' )
end

local function SortedKeys( source )
	local keys = {}
	for key in pairs( source or {} ) do keys[ #keys + 1 ] = key end
	table.sort( keys, function( first, second ) return tostring( first ) < tostring( second ) end )
	return keys
end

local function AppendVMTBlock( lines, parameters, indentation )
	indentation = indentation or "\t"
	for _, key in ipairs( SortedKeys( parameters ) ) do
		local value = parameters[ key ]
		if istable( value ) then
			lines[ #lines + 1 ] = string.format( '%s"%s"', indentation,
				EscapeVMTString( key ) )
			lines[ #lines + 1 ] = indentation .. "{"
			AppendVMTBlock( lines, value, indentation .. "\t" )
			lines[ #lines + 1 ] = indentation .. "}"
		else
			lines[ #lines + 1 ] = string.format( '%s"%s" "%s"', indentation,
				EscapeVMTString( key ), EscapeVMTString( value ) )
		end
	end
end

local function GeneratedVMTText( shader, parameters )
	local lines = { tostring( shader or "VertexLitGeneric" ), "{" }
	AppendVMTBlock( lines, parameters, "\t" )
	lines[ #lines + 1 ] = "}"
	return table.concat( lines, "\n" ) .. "\n"
end

local function PrintGeneratedMaterialVMT( mask )
	local generated = mask.generatedVMT or GeneratedVMTText(
		mask.originalShader, mask.cloneParameters )
	BBS.Log( "  generated material VMT for !%s:", mask.materialName )
	for line in string.gmatch( generated .. "\n", "(.-)\n" ) do
		BBS.Log( "    %s", line )
	end
end

local function CaptureRenderTargetPNG( renderTarget, width, height, includeAlpha )
	render.PushRenderTarget( renderTarget )
	local ok, captured = pcall( render.Capture, {
		format = "png",
		quality = 100,
		x = 0,
		y = 0,
		w = width,
		h = height,
		alpha = includeAlpha == true,
	} )
	render.PopRenderTarget()
	if not ok then return nil, tostring( captured ) end
	if not captured or captured == "" then return nil, "render.Capture returned no data" end
	return captured
end

local function DebugVector( value )
	return value and BBS.FormatVector( value ) or "<nil>"
end

local function DebugBundleFolder( hit )
	BBS.DamageDebugDumpSerial = BBS.DamageDebugDumpSerial + 1
	local timestamp = os.date( "%Y%m%d_%H%M%S" )
	return string.format( "bbs_debug/%s_hit_%04d_ent_%d_dump_%03d",
		timestamp, hit.serial or 0, hit.entityIndex or -1,
		BBS.DamageDebugDumpSerial )
end

local function BuildUVText( materialRecord )
	local lines = {
		"# Selected UV triangles",
		"# triangle_index vertex u v",
	}
	for _, triangle in ipairs( materialRecord.triangles or {} ) do
		for vertexIndex, coordinate in ipairs( triangle.uv or {} ) do
			lines[ #lines + 1 ] = string.format( "%d %d %.9f %.9f",
				triangle.triangleIndex or -1, vertexIndex,
				coordinate.u or 0, coordinate.v or 0 )
		end
	end
	return table.concat( lines, "\n" ) .. "\n"
end

local function BuildProjectedUVText( materialRecord )
	local lines = {
		"# Adaptive irregular removal-hull projection in transformed/unwrapped UV space",
		"# projected_triangle vertex u v",
	}
	local projected = materialRecord.projectedTriangles or {}
	for triangleIndex = 1, ProjectedTriangleCount( projected ) do
		for vertexIndex = 1, 3 do
			local u, v = ProjectedTriangleUV(
				projected, triangleIndex, vertexIndex )
			lines[ #lines + 1 ] = string.format( "%d %d %.9f %.9f",
				triangleIndex, vertexIndex, u or 0, v or 0 )
		end
	end
	return table.concat( lines, "\n" ) .. "\n"
end

local function BuildRemovalHullShapeText( hit )
	local hull = hit and hit.hullParameters or {}
	local lines = {
		"# Deterministic damage-scaled polar removal-hull boundary",
		"damage=" .. tostring( hit and hit.damage ),
		"seed=" .. tostring( hull.seed ),
		"base_radius=" .. tostring( hull.baseRadius ),
		"nominal_radius=" .. tostring( hull.radius ),
		"minimum_radius=" .. tostring( hull.minimumRadius ),
		"maximum_radius=" .. tostring( hull.maximumRadius ),
		"damage_multiplier=" .. tostring( hull.damageMultiplier ),
		"maximum_damage_multiplier=" .. tostring( hull.maximumDamageMultiplier ),
		"irregularity=" .. tostring( hull.irregularity ),
		"tear_count=" .. tostring( hull.tearCount ),
		"sample_count=" .. tostring( hull.shapeSamples ),
		"angle_offset_radians=" .. tostring( hull.angleOffset ),
		"# sample angle_degrees radius",
	}
	local count = #( hull.radii or {} )
	for index, radius in ipairs( hull.radii or {} ) do
		local radians = ( index - 1 ) / math.max( count, 1 ) * math.pi * 2
			+ ( hull.angleOffset or 0 )
		lines[ #lines + 1 ] = string.format( "%d %.6f %.9f",
			index, math.deg( radians ), radius )
	end
	return table.concat( lines, "\n" ) .. "\n"
end

local function BuildMeshSelectionText( query )
	local lines = { "# Posed mesh triangles selected by the removal hull's enclosing cylinder" }
	for _, matchingMesh in ipairs( query and query.meshes or {} ) do
		lines[ #lines + 1 ] = string.format( "mesh=%d material=%s triangles=%d",
			matchingMesh.meshIndex or -1, tostring( matchingMesh.material ),
			#( matchingMesh.triangles or {} ) )
		for _, triangle in ipairs( matchingMesh.triangles or {} ) do
			local centerline = triangle.centerlineUV
			lines[ #lines + 1 ] = string.format(
				"  triangle=%d layer_depth=%s centerline_uv=%s",
				triangle.triangleIndex or -1, tostring( triangle.layerDepth ),
				centerline and string.format( "[%.9f %.9f]",
					centerline.u or 0, centerline.v or 0 ) or "<none>" )
			for vertexIndex, vertex in ipairs( triangle.vertices or {} ) do
				lines[ #lines + 1 ] = string.format(
					"    vertex=%d world=[%s] uv=[%.9f %.9f] literalInside=%s",
					vertexIndex, DebugVector( vertex.worldPosition ),
					vertex.u or 0, vertex.v or 0, tostring( vertex.inside ) )
			end
		end
	end
	return table.concat( lines, "\n" ) .. "\n"
end

local function BuildBodygroupFilterText( damage )
	local lines = {
		"Bodygroup blank-option filter and per-model hideable overrides",
		"# GetBodyGroups and submodels are enumerated with pairs; submodel keys are zero-based option IDs.",
		"# Eligible names: zero-length, empty, unnamed, blank, or a path/basename resolving to empty/blank.",
		"# A missing option ID is inferred blank only when the runtime submodel table is otherwise populated.",
		"# User denylist matching is exact and case-insensitive; blocked blank-capable groups are not eligible.",
		"# A per-model hideable override has highest priority and bypasses the name denylist.",
		"# Source v48 MDL bodypart mesh spans are used after exact runtime vertex-count validation.",
		"# Differential model-selection comparison is retained only as a compatibility fallback.",
	}
	for _, bodygroup in ipairs( damage and damage.inspectedBodygroups or {} ) do
		lines[ #lines + 1 ] = string.format(
			"group=%d raw_key=%s raw_key_type=%s name=%s selected=%d count=%d declared_count=%s has_blank=%s overridden=%s blacklist_bypassed=%s filter_allowed=%s eligible=%s ownership_source=%s compiled_mesh_span=%s..%s comparison_option=%s filter_reason=%s blank_options=%s",
			bodygroup.id, BodygroupHelpers.DebugRawValue( bodygroup.rawKey ),
			tostring( bodygroup.rawKeyType ), tostring( bodygroup.name ),
			bodygroup.selected, bodygroup.count, tostring( bodygroup.declaredCount ),
			tostring( bodygroup.hasBlank ), tostring( bodygroup.overridden ),
			tostring( bodygroup.blacklistBypassed ), tostring( bodygroup.filterAllowed ),
			tostring( bodygroup.eligible ), tostring( bodygroup.ownershipSource ),
			tostring( bodygroup.compiledFirstMesh ),
			tostring( bodygroup.compiledLastMesh ),
			tostring( bodygroup.comparisonOption
				and bodygroup.comparisonOption.id ), tostring( bodygroup.filterReason ),
			BodygroupHelpers.BlankOptionSummary( bodygroup ) )
		for _, option in ipairs( bodygroup.submodels or {} ) do
			lines[ #lines + 1 ] = string.format(
				"  option=%d name=%s blank=%s reason=%s inferred=%s value_type=%s",
				option.id, BodygroupHelpers.DebugSubmodelName( option.name ),
				tostring( option.blank ), tostring( option.reason ),
				tostring( option.inferred or false ), tostring( option.valueType ) )
		end
		for _, raw in ipairs( bodygroup.rawSubmodels or {} ) do
			lines[ #lines + 1 ] = string.format(
				"  raw key=%s key_type=%s option_id=%s value_type=%s value=%s extracted_name=%s",
				BodygroupHelpers.DebugRawValue( raw.key ), tostring( raw.keyType ), tostring( raw.id ),
				tostring( raw.valueType ), BodygroupHelpers.DebugRawValue( raw.value ),
				BodygroupHelpers.DebugRawValue( raw.name ) )
		end
	end
	return table.concat( lines, "\n" ) .. "\n"
end

local function WriteBodygroupProbeBundle( hit, damage, label )
	if not GetBool( "bbs_damage_dump_debug", false ) then return nil end
	local folder = DebugBundleFolder( hit or {} )
	file.CreateDir( "bbs_debug" )
	file.CreateDir( folder )
	file.Write( folder .. "/bodygroup_filter.txt", table.concat( {
		"probe=" .. tostring( label or "bodygroup" ),
		"addon_version=" .. tostring( BBS.Version ),
		"model=" .. tostring( hit and hit.model or "<unknown>" ),
		"entity_index=" .. tostring( hit and hit.entityIndex or -1 ),
		"",
		BuildBodygroupFilterText( damage ),
	}, "\n" ) )
	BBS.Log( "  bodygroup probe dumped: garrysmod/data/%s/bodygroup_filter.txt", folder )
	return folder
end

local function WriteMaterialDebugBundle( job, mask, captures )
	captures = captures or {}
	local hit = job.hit
	local query = hit.meshQuery or {}
	local materialRecord = job.materialRecord
	local folder = DebugBundleFolder( hit )
	file.CreateDir( "bbs_debug" )
	file.CreateDir( folder )
	mask.lastDebugBundleFolder = folder

	local hull = hit.hullParameters or {}
	local nearest = hit.damageUV and hit.damageUV.nearestHideableMesh or nil
	local paint = mask.lastPaintDiagnostics or {}
	local damageState = IsValid( job.entity ) and BBS.DamageStates[ job.entity ] or nil
	local summary = {
		"Procedural Bodygroup Destruction material debug bundle",
		"addon_version=" .. tostring( BBS.Version ),
		"created=" .. os.date( "%Y-%m-%d %H:%M:%S" ),
		"hit_serial=" .. tostring( hit.serial ),
		"entity_index=" .. tostring( hit.entityIndex ),
		"entity=" .. tostring( hit.entity ),
		"model=" .. tostring( hit.model ),
		"model_filter_mode=" .. tostring( hit.modelFilter and hit.modelFilter.mode ),
		"model_filter_listed=" .. tostring( hit.modelFilter and hit.modelFilter.listed ),
		"model_filter_allowed=" .. tostring( hit.modelFilter and hit.modelFilter.allowed ),
		"model_filter_reason=" .. tostring( hit.modelFilter and hit.modelFilter.reason ),
		"raw_position=" .. DebugVector( hit.rawPosition ),
		"surface_position=" .. DebugVector( hit.surfacePosition ),
		"hit_direction=" .. DebugVector( hit.direction ),
		"surface_normal=" .. DebugVector( hit.normal ),
		"physics_bone=" .. tostring( hit.physicsBone ),
		"model_bone=" .. tostring( hit.modelBone ),
		"bone_name=" .. tostring( hit.boneName ),
		"hull_radius=" .. tostring( hull.radius ),
		"hull_base_radius=" .. tostring( hull.baseRadius ),
		"hull_minimum_radius=" .. tostring( hull.minimumRadius ),
		"hull_maximum_radius=" .. tostring( hull.maximumRadius ),
		"hull_inside_distance=" .. tostring( hull.insideDistance ),
		"hull_outside_distance=" .. tostring( hull.outsideDistance ),
		"hull_damage_multiplier=" .. tostring( hull.damageMultiplier ),
		"hull_damage_multiplier_cap=" .. tostring( hull.maximumDamageMultiplier ),
		"hull_irregularity=" .. tostring( hull.irregularity ),
		"hull_irregularity_cap=" .. tostring( hull.maximumIrregularity ),
		"hull_shape_seed=" .. tostring( hull.seed ),
		"hull_shape_samples=" .. tostring( hull.shapeSamples ),
		"hull_tear_count=" .. tostring( hull.tearCount ),
		"query_meshes=" .. tostring( query.meshCount ),
		"query_triangles=" .. tostring( query.triangleCount ),
		"query_vertices=" .. tostring( query.vertexCount ),
		"nearest_visual_distance=" .. tostring( query.probe and query.probe.nearestSurfaceDistance ),
		"nearest_hideable_mesh=" .. tostring( nearest and nearest.meshIndex ),
		"nearest_hideable_material=" .. tostring( nearest and nearest.material ),
		"nearest_hideable_distance=" .. tostring( nearest and nearest.distance ),
		"affected_material=" .. tostring( materialRecord.material ),
		"submaterial_index=" .. tostring( job.submaterialIndex ),
		"submaterial_match=" .. tostring( materialRecord.submaterialMatch ),
		"original_vmt_path=materials/" .. tostring( mask.originalPath ) .. ".vmt",
		"original_shader=" .. tostring( mask.originalShader ),
		"original_base_texture=" .. tostring( mask.baseTextureName ),
		"original_base_texture_size=" .. tostring( mask.sourceTextureWidth )
			.. "x" .. tostring( mask.sourceTextureHeight ),
		"material_source=" .. tostring( mask.materialSource ),
		"advanced_material_editor_detected=" .. tostring(
			mask.advancedMaterialEditor ),
		"advanced_material_editor_material=" .. tostring(
			mask.advancedMaterialEditorMaterialName ),
		"advanced_material_editor_override=" .. tostring(
			mask.advancedMaterialEditorOverride ),
		"advanced_material_editor_preview=" .. tostring(
			mask.advancedMaterialEditorPreview ),
		"advanced_material_editor_client_owned=" .. tostring(
			mask.advancedMaterialEditorClientOwned ),
		"advanced_material_editor_rule_scope=" .. tostring(
			mask.advancedMaterialEditorRuleScope ),
		"advanced_material_editor_rule_material=" .. tostring(
			mask.advancedMaterialEditorRuleMaterial ),
		"advanced_material_editor_raw_override=" .. tostring(
			mask.advancedMaterialEditorRawOverride ),
		"advanced_material_editor_effective_parameters=" .. tostring(
			mask.advancedMaterialEditorParameterCount ),
		"advanced_material_editor_generated_textures=" .. tostring(
			mask.advancedMaterialEditorGeneratedTextureCount ),
		"advanced_material_editor_generated_textures_applied=" .. tostring(
			mask.advancedMaterialEditorGeneratedTexturesApplied ),
		"advanced_material_editor_generated_texture_errors=" .. table.concat(
			mask.advancedMaterialEditorGeneratedTextureErrors or {}, " | " ),
		"advanced_material_editor_resolve_error=" .. tostring(
			mask.advancedMaterialEditorResolveError ),
		"advanced_material_editor_build_error=" .. tostring(
			mask.advancedMaterialEditorBuildError ),
		"advanced_bodygroup_tool_detected=" .. tostring(
			mask.advancedBodygroupTool ),
		"advanced_bodygroup_tool_identity=" .. tostring(
			mask.advancedBodygroupToolIdentity ),
		"advanced_bodygroup_tool_material=" .. tostring(
			mask.advancedBodygroupToolMaterialName ),
		"advanced_bodygroup_tool_target=" .. tostring(
			mask.advancedBodygroupToolTargetName ),
		"advanced_bodygroup_tool_alpha_composited=" .. tostring(
			mask.advancedBodygroupToolAlphaComposited ),
		"advanced_bodygroup_tool_alpha_error=" .. tostring(
			mask.advancedBodygroupToolAlphaError ),
		"edited_source_signature=" .. tostring( mask.editedSourceSignature ),
		"direct_material_ownership=" .. tostring( mask.directMaterialOwnership ),
		"live_texture_objects_applied=" .. tostring(
			mask.liveTextureObjectsApplied ),
		"live_matrix_objects_applied=" .. tostring(
			mask.liveMatrixObjectsApplied ),
		"live_object_errors=" .. table.concat(
			mask.liveObjectErrors or {}, " | " ),
		"source_copy_method=" .. tostring( mask.sourceCopyMethod ),
		"alpha_initialization=" .. tostring( mask.alphaInitialization ),
		"generated_material=!" .. tostring( mask.materialName ),
		"rtx_detected=" .. tostring( RTX.IsClient() ),
		"rtx_detection_reason=" .. tostring( RTX.DetectionReason() ),
		"config_getter_scope=rtx.conf file only (runtime writes are not readable by this bridge build)",
		"rtx_direct_override=" .. tostring( mask.rtxDirectOverride ),
		"rtx_direct_override_reason=" .. tostring( mask.rtxDirectOverrideReason ),
		"rtx_refresh_attempted=" .. tostring( mask.rtxRefreshAttempted ),
		"rtx_refresh_count=" .. tostring( mask.rtxRefreshCount ),
		"rtx_refresh_reason=" .. tostring( mask.rtxRefreshReason ),
		"rtx_refresh_result=" .. tostring( mask.rtxRefreshReasonText ),
		"rtx_refresh_succeeded=" .. tostring( mask.rtxRefreshSucceeded ),
		"rtx_refresh_milliseconds=" .. tostring( mask.rtxRefreshMilliseconds ),
		"rtx_cache_invalidation_available=" .. tostring(
			mask.rtxCacheInvalidationAvailable ),
		"rtx_cache_invalidation_skipped=" .. tostring(
			mask.rtxCacheInvalidationSkipped ),
		"rtx_cache_invalidation_skip_reason=" .. tostring(
			mask.rtxCacheInvalidationSkipReason ),
		"rtx_cache_invalidation_succeeded=" .. tostring(
			mask.rtxCacheInvalidationSucceeded ),
		"rtx_cache_invalidation_result=" .. tostring(
			mask.rtxCacheInvalidationResult ),
		"rtx_cache_invalidation_error=" .. tostring(
			mask.rtxCacheInvalidationError ),
		"rtx_texture_rebind_succeeded=" .. tostring( mask.rtxTextureRebindSucceeded ),
		"rtx_texture_rebind_skipped=" .. tostring( mask.rtxTextureRebindSkipped ),
		"rtx_texture_rebind_error=" .. tostring( mask.rtxTextureRebindError ),
		"rtx_material_recompute_available=" .. tostring(
			mask.rtxMaterialRecomputeAvailable ),
		"rtx_material_recompute_succeeded=" .. tostring(
			mask.rtxMaterialRecomputeSucceeded ),
		"rtx_material_recompute_skipped=" .. tostring(
			mask.rtxMaterialRecomputeSkipped ),
		"rtx_material_recompute_error=" .. tostring(
			mask.rtxMaterialRecomputeError ),
		"rtx_tracker_available=" .. tostring( mask.rtxTrackerAvailable ),
		"rtx_tracker_skipped=" .. tostring( mask.rtxTrackerSkipped ),
		"rtx_tracker_succeeded=" .. tostring( mask.rtxTrackerSucceeded ),
		"rtx_tracker_result=" .. tostring( mask.rtxTrackerResult ),
		"rtx_tracker_error=" .. tostring( mask.rtxTrackerError ),
		"rtx_pipeline_available=" .. tostring( mask.rtxPipelineAvailable ),
		"rtx_pipeline_process_skipped=" .. tostring( mask.rtxPipelineProcessSkipped ),
		"rtx_pipeline_process_succeeded=" .. tostring(
			mask.rtxPipelineProcessSucceeded ),
		"rtx_pipeline_process_result=" .. tostring( mask.rtxPipelineProcessResult ),
		"rtx_pipeline_process_error=" .. tostring( mask.rtxPipelineProcessError ),
		"rtx_hash_on_write_attempted=" .. tostring(
			mask.rtxHashOnWriteAttempted ),
		"rtx_hash_on_write_available=" .. tostring(
			mask.rtxHashOnWriteAvailable ),
		"rtx_hash_on_write_begin_count=" .. tostring(
			mask.rtxHashOnWriteBeginCount ),
		"rtx_hash_on_write_preparation_waits=" .. tostring(
			mask.rtxHashOnWritePreparationWaits ),
		"rtx_hash_on_write_preparation_attempts=" .. tostring(
			mask.rtxHashOnWritePreparationAttempts ),
		"rtx_hash_on_write_preparation_error=" .. tostring(
			mask.rtxHashOnWritePreparationError ),
		"rtx_hash_on_write_capture_requested=" .. tostring(
			mask.rtxHashOnWriteCaptureRequested ),
		"rtx_hash_on_write_get_succeeded=" .. tostring(
			mask.rtxHashOnWriteGetSucceeded ),
		"rtx_hash_on_write_get_error=" .. tostring(
			mask.rtxHashOnWriteGetError ),
		"rtx_hash_on_write_previous_value=" .. tostring(
			mask.rtxHashOnWritePreviousValue ),
		"rtx_hash_on_write_inherited_enabled=" .. tostring(
			mask.rtxHashOnWriteInheritedEnabled ),
		"rtx_hash_on_write_coalesced=" .. tostring(
			mask.rtxHashOnWriteCoalesced ),
		"rtx_hash_on_write_set_succeeded=" .. tostring(
			mask.rtxHashOnWriteSetSucceeded ),
		"rtx_hash_on_write_set_result=" .. tostring(
			mask.rtxHashOnWriteSetResult ),
		"rtx_hash_on_write_set_error=" .. tostring(
			mask.rtxHashOnWriteSetError ),
		"rtx_hash_on_write_effective_value=" .. tostring(
			mask.rtxHashOnWriteEffectiveValue ),
		"rtx_hash_on_write_effective_read_succeeded=" .. tostring(
			mask.rtxHashOnWriteEffectiveReadSucceeded ),
		"rtx_hash_on_write_effective_read_error=" .. tostring(
			mask.rtxHashOnWriteEffectiveReadError ),
		"rtx_hash_on_write_enabled_for_paint=" .. tostring(
			mask.rtxHashOnWriteEnabledForPaint ),
		"rtx_hash_on_write_error=" .. tostring( mask.rtxHashOnWriteError ),
		"rtx_hash_on_write_restore_scheduled=" .. tostring(
			mask.rtxHashOnWriteRestoreScheduled ),
		"rtx_hash_on_write_restore_pending=" .. tostring(
			mask.rtxHashOnWriteRestorePending ),
		"rtx_hash_on_write_restore_attempts=" .. tostring(
			mask.rtxHashOnWriteRestoreAttempts ),
		"rtx_hash_on_write_restore_succeeded=" .. tostring(
			mask.rtxHashOnWriteRestoreSucceeded ),
		"rtx_hash_on_write_restore_result=" .. tostring(
			mask.rtxHashOnWriteRestoreResult ),
		"rtx_hash_on_write_restored_value=" .. tostring(
			mask.rtxHashOnWriteRestoredValue ),
		"rtx_hash_on_write_restore_error=" .. tostring(
			mask.rtxHashOnWriteRestoreError ),
		"rtx_texture_hashes_before=" .. tostring( mask.rtxTextureHashesBefore ),
		"rtx_texture_hash_count_before=" .. tostring(
			mask.rtxTextureHashCountBefore ),
		"rtx_texture_hashes_before_error=" .. tostring(
			mask.rtxTextureHashesBeforeError ),
		"rtx_texture_hashes_after=" .. tostring( mask.rtxTextureHashesAfter ),
		"rtx_texture_hash_count_after=" .. tostring(
			mask.rtxTextureHashCountAfter ),
		"rtx_texture_hashes_after_error=" .. tostring(
			mask.rtxTextureHashesAfterError ),
		"rtx_omm_ignore_key=" .. RTX.OMMIgnoreKey,
		"rtx_omm_protection_available=" .. tostring(
			mask.rtxOMMProtectionAvailable ),
		"rtx_omm_protection_source=" .. tostring(
			mask.rtxOMMProtectionSource ),
		"rtx_omm_protection_input_hashes=" .. tostring(
			mask.rtxOMMProtectionInputHashes ),
		"rtx_omm_protection_total_hashes=" .. tostring(
			mask.rtxOMMProtectionHashCount ),
		"rtx_omm_protection_added_hashes=" .. tostring(
			mask.rtxOMMProtectionAddedCount ),
		"rtx_omm_protection_set_needed=" .. tostring(
			mask.rtxOMMProtectionSetNeeded ),
		"rtx_omm_protection_succeeded=" .. tostring(
			mask.rtxOMMProtectionSucceeded ),
		"rtx_omm_protection_result=" .. tostring(
			mask.rtxOMMProtectionResult ),
		"rtx_omm_protection_error=" .. tostring(
			mask.rtxOMMProtectionError ),
		"rtx_probe_generation=" .. tostring( mask.rtxProbeGeneration ),
		"rtx_probe_history_count=" .. tostring( #( mask.rtxHashHistory or {} ) ),
		"rtx_render_override_installed=" .. tostring( damageState
			and damageState.rtxRenderOverrideInstalled ),
		"rtx_render_override_active=" .. tostring( damageState
			and job.entity.RenderOverride == damageState.rtxRenderOverride ),
		"rtx_render_override_last_draw_failed=" .. tostring( damageState
			and damageState.rtxRenderOverrideLastDrawFailed ),
		"rtx_render_override_failure_count=" .. tostring( damageState
			and damageState.rtxRenderOverrideFailureCount ),
		"rtx_render_override_consecutive_failures=" .. tostring( damageState
			and damageState.rtxRenderOverrideConsecutiveFailures ),
		"rtx_render_override_last_error=" .. tostring( damageState
			and damageState.rtxRenderOverrideLastError ),
		"rtx_render_override_last_failure_flags=" .. tostring( damageState
			and damageState.rtxRenderOverrideLastFailureFlags ),
		"rtx_render_override_last_failure_shadow_depth=" .. tostring( damageState
			and damageState.rtxRenderOverrideLastFailureShadowDepth ),
		"rtx_render_override_last_failure_ssao_depth=" .. tostring( damageState
			and damageState.rtxRenderOverrideLastFailureSSAODepth ),
		"rtx_render_override_last_bound_masks=" .. tostring( damageState
			and damageState.rtxLastBoundMaskCount ),
		"render_target=" .. tostring( mask.renderTargetName ),
		"render_target_size=" .. tostring( mask.width ) .. "x" .. tostring( mask.height ),
		"resolution_policy=" .. tostring( mask.resolutionPolicy ),
		"requested_maximum_edge=" .. tostring( mask.requestedMaximumEdge ),
		"normalized_maximum_edge=" .. tostring( mask.normalizedMaximumEdge ),
		"renderer_maximum_edge=" .. tostring( mask.hardwareMaximumEdge ),
		"renderer_maximum_width=" .. tostring( mask.hardwareMaximumWidth ),
		"renderer_maximum_height=" .. tostring( mask.hardwareMaximumHeight ),
		"source_to_render_target_scale=" .. tostring( mask.sourceScale ),
		"source_to_render_target_scale_x=" .. tostring( mask.sourceScaleX ),
		"source_to_render_target_scale_y=" .. tostring( mask.sourceScaleY ),
		"source_aspect_ratio=" .. tostring( mask.sourceTextureWidth / mask.sourceTextureHeight ),
		"render_target_aspect_ratio=" .. tostring( mask.width / mask.height ),
		"source_uses_alpha=" .. tostring( mask.alphaStyleSource ),
		"source_vtf_path=" .. tostring( mask.vtfMetadata and mask.vtfMetadata.path ),
		"source_vtf_readable=" .. tostring( mask.vtfMetadata
			and mask.vtfMetadata.readable ),
		"source_vtf_flags=" .. string.format( "0x%08X",
			mask.vtfMetadata and mask.vtfMetadata.flags or 0 ),
		"source_vtf_image_format=" .. tostring( mask.vtfMetadata
			and mask.vtfMetadata.imageFormat ),
		"source_vtf_has_alpha=" .. tostring( mask.vtfMetadata
			and mask.vtfMetadata.hasAlpha ),
		"preserve_source_alpha=" .. tostring( mask.preserveSourceAlpha ),
		"generated_alpha_parameter=" .. ( mask.alphaParameter == nil
			and "<absent>" or tostring( mask.alphaParameter ) ),
		"force_nocull_setting=" .. tostring( mask.forceNoCull ),
		"inherited_nocull_parameter=" .. tostring(
			mask.inheritedNoCullParameter ),
		"generated_nocull_parameter=" .. tostring(
			mask.cloneParameters and mask.cloneParameters[ "$nocull" ] ),
		"cpu_damage_coverage_paints=" .. tostring( mask.damageCoverage
			and mask.damageCoverage.paintCount or 0 ),
		"cpu_damage_coverage_triangles=" .. tostring( mask.damageCoverage
			and mask.damageCoverage.triangleCount or 0 ),
		"cpu_damage_coverage_tiled_triangles=" .. tostring( mask.damageCoverage
			and mask.damageCoverage.tiledTriangleCount or 0 ),
		"cpu_damage_coverage_large_triangles=" .. tostring( mask.damageCoverage
			and mask.damageCoverage.largeTriangleCount or 0 ),
		"cpu_damage_coverage_grid=" .. tostring( mask.damageCoverage
			and mask.damageCoverage.gridSize or 0 ),
		"selected_material_triangles=" .. tostring( #( materialRecord.triangles or {} ) ),
		"projected_uv_triangles=" .. tostring(
			ProjectedTriangleCount( materialRecord.projectedTriangles ) ),
		"selected_unique_uvs=" .. tostring( #( materialRecord.uvs or {} ) ),
		"blank_capable_bodygroups=" .. tostring( #( hit.damageUV
			and hit.damageUV.bodygroups or {} ) ),
		"explicit_hideable_bodygroup_overrides=" .. tostring( hit.damageUV
			and hit.damageUV.overriddenBodygroupCount or 0 ),
		"unresolved_hideable_bodygroup_overrides=" .. tostring( hit.damageUV
			and hit.damageUV.unresolvedOverrideCount or 0 ),
		"bodygroup_mesh_ownership_mode=" .. tostring( hit.damageUV
			and hit.damageUV.ownershipMode ),
		"compiled_bodypart_ownership=" .. tostring( hit.damageUV
			and hit.damageUV.compiledOwnership ),
		"compiled_bodypart_ownership_error=" .. tostring( hit.damageUV
			and hit.damageUV.compiledOwnershipError ),
		"inspected_bodygroups=" .. tostring( #( hit.damageUV
			and hit.damageUV.inspectedBodygroups or {} ) ),
		"visual_layer_limit=" .. tostring( hit.damageUV
			and hit.damageUV.layerLimit ),
		"visual_mesh_surfaces_encountered=" .. tostring( hit.damageUV
			and hit.damageUV.layerSurfaceCount ),
		"visual_layers_encountered=" .. tostring( hit.damageUV
			and hit.damageUV.layerCount ),
		"visual_surfaces_passed_through_existing_holes=" .. tostring( hit.damageUV
			and hit.damageUV.passedExistingHoleCount ),
		"visual_surfaces_hidden_by_advanced_bodygroup_tool=" .. tostring(
			hit.damageUV and hit.damageUV.advancedBodygroupHiddenSurfaceCount ),
		"visual_layers_selected=" .. tostring( hit.damageUV
			and hit.damageUV.selectedLayerCount ),
		"visual_damageable_layers_selected=" .. tostring( hit.damageUV
			and hit.damageUV.selectedDamageableLayerCount ),
		"visual_damageable_meshes_blocked_by_limit=" .. tostring( hit.damageUV
			and hit.damageUV.blockedDamageableMeshCount ),
		"visual_layer_ownership=" .. tostring( hit.damageUV
			and hit.damageUV.layerOwnershipSource ),
		"visual_layer_occluders_included=" .. tostring( hit.damageUV
			and hit.damageUV.layerOccludersIncluded ),
		"uv_mask_expansion_pixels=" .. tostring( paint.expansion ),
		"uv_mask_feather_pixels=" .. tostring( paint.feather ),
		"uv_mask_blur_passes=" .. tostring( paint.blurPasses ),
		"uv_seam_unwrap_enabled=" .. tostring( paint.unwrapSeams ),
		"uv_seam_triangles_unwrapped=" .. tostring( paint.seamTriangleCount ),
		"projection_depth=" .. tostring( paint.projectionDepth ),
		"projection_requested_depth=" .. tostring( paint.projectionRequestedDepth ),
		"projection_budget_limited=" .. tostring( paint.projectionBudgetLimited ),
		"projection_conservative_upper_bound=" .. tostring(
			paint.projectionConservativeUpperBound ),
		"projection_coarse_terminal=" .. tostring(
			paint.projectionCoarseTerminal ),
		"projection_retry_count=" .. tostring( paint.projectionRetryCount ),
		"projection_discarded_at_cap=" .. tostring(
			paint.projectionDiscardedAtCap ),
		"projection_maximum_depth_reached=" .. tostring(
			paint.projectionMaximumDepthReached ),
		"projection_tolerance_world=" .. tostring( paint.projectionTolerance ),
		"projection_triangle_cap=" .. tostring( paint.projectionMaximumTriangles ),
		"projection_local_radius_bounds=" .. tostring(
			paint.projectionLocalBounds ),
		"projection_local_angular_bound_cells=" .. tostring(
			paint.projectionAngularBoundCellCount ),
		"projection_global_angular_bound_cells=" .. tostring(
			paint.projectionGlobalAngularBoundCellCount ),
		"projection_maximum_angular_deviation_radians=" .. tostring(
			paint.projectionMaximumAngularDeviation ),
		"projection_maximum_radius_slope_per_radian=" .. tostring(
			paint.projectionMaximumAngularSlope ),
		"projection_capped=" .. tostring( paint.projectionCapped ),
		"projection_cpu_milliseconds=" .. tostring( paint.projectionMilliseconds ),
		"projection_cells_visited=" .. tostring( paint.projectionVisitedCellCount ),
		"projection_cells_inside=" .. tostring( paint.projectionInsideCellCount ),
		"projection_cells_outside=" .. tostring( paint.projectionOutsideCellCount ),
		"projection_cells_boundary=" .. tostring( paint.projectionBoundaryCellCount ),
		"projection_source_triangles_missed=" .. tostring(
			paint.projectionMissedSourceTriangleCount ),
		"projection_source_triangles_missing_world=" .. tostring(
			paint.projectionMissingWorldTriangleCount ),
		"projection_degenerate_uv_triangles=" .. tostring(
			paint.projectionDegenerateTriangleCount ),
		"projection_error=" .. tostring( paint.projectionError ),
		"projection_shape_seed=" .. tostring( paint.shapeSeed ),
		"projection_shape_samples=" .. tostring( paint.shapeSampleCount ),
		"projection_shape_tears=" .. tostring( paint.shapeTearCount ),
		"projection_shape_irregularity=" .. tostring( paint.shapeIrregularity ),
		"projection_damage_multiplier=" .. tostring( paint.shapeDamageMultiplier ),
		"projection_shape_radius_range=" .. tostring( paint.shapeMinimumRadius )
			.. ".." .. tostring( paint.shapeMaximumRadius ),
		"uv_maximum_raw_u_span=" .. tostring( paint.maximumRawUSpan ),
		"uv_maximum_raw_v_span=" .. tostring( paint.maximumRawVSpan ),
		"uv_maximum_raster_u_span=" .. tostring( paint.maximumRasterUSpan ),
		"uv_maximum_raster_v_span=" .. tostring( paint.maximumRasterVSpan ),
		"uv_raster_batch_requested=" .. tostring( paint.batchRasterRequested ),
		"uv_raster_mode=" .. tostring( paint.rasterMode ),
		"uv_raster_polygon_count=" .. tostring( paint.rasterPolygonCount ),
		"uv_raster_primitive_count=" .. tostring( paint.rasterPrimitiveCount ),
		"uv_raster_batch_count=" .. tostring( paint.rasterBatchCount ),
		"uv_raster_fallback_error=" .. tostring( paint.rasterFallbackError ),
		"uv_raster_milliseconds=" .. tostring( paint.rasterMilliseconds ),
		"uv_blur_milliseconds=" .. tostring( paint.blurMilliseconds ),
		"coverage_alpha_mode=" .. tostring( paint.coverageAlphaMode ),
		"uv_alpha_composite_milliseconds=" .. tostring(
			paint.alphaCompositeMilliseconds ),
		"alpha_write_domain_fraction=" .. tostring( paint.alphaWriteDomainFraction ),
		"alpha_write_rectangle_count=" .. tostring( paint.alphaWriteRectangleCount ),
		"compatibility_history_alpha_mode=" .. tostring( mask.compatibilityHistoryMode ),
		"source_probe_visible_threshold=" .. tostring( mask.copyProbe
			and mask.copyProbe.visibleThreshold ),
		"source_copy_valid=" .. tostring( mask.sourceCopyValid ),
		"source_copy_validation_enforced=" .. tostring(
			mask.sourceValidationEnforced or false ),
		"source_copy_validation_skipped=" .. tostring(
			mask.sourceValidationSkipped or false ),
		"source_rgb_copy_valid=" .. tostring( mask.sourceRGBValid ),
		"source_alpha_copy_valid=" .. tostring( mask.sourceAlphaValid ),
		"source_copy_non_sentinel_samples=" .. tostring( mask.copyProbe
			and mask.copyProbe.nonSentinelCount ),
		"source_copy_total_samples=" .. tostring( mask.copyProbe
			and mask.copyProbe.sampleCount ),
		"before_rgb_capture=" .. ( captures.beforeRGB and "ok"
			or tostring( captures.beforeRGBError ) ),
		"before_alpha_capture=" .. ( captures.beforeAlpha and "ok"
			or tostring( captures.beforeAlphaError ) ),
		"edited_rgb_capture=" .. ( captures.afterRGB and "ok"
			or tostring( captures.afterRGBError ) ),
		"edited_alpha_capture=" .. ( captures.afterAlpha and "ok"
			or tostring( captures.afterAlphaError ) ),
		"coverage_before_blur_capture=" .. ( captures.coverageBefore and "ok"
			or tostring( captures.coverageBeforeError ) ),
		"coverage_after_blur_capture=" .. ( captures.coverageAfter and "ok"
			or tostring( captures.coverageAfterError ) ),
	}
	file.Write( folder .. "/summary.txt", table.concat( summary, "\n" ) .. "\n" )
	local layerLines = {
		"surface_index solid_layer selected damageable passes_existing_hole advanced_bodygroup_tool_hidden bodygroup_id ray_samples open_ray_samples damage_mask_serial minimum_depth maximum_depth mesh material",
	}
	for _, layer in ipairs( hit.damageUV and hit.damageUV.layers or {} ) do
		layerLines[ #layerLines + 1 ] = string.format(
			"%d %s %s %s %s %s %s %d %d %s %.6f %.6f %s %s",
			layer.surfaceIndex or -1, tostring( layer.countedIndex or "open" ),
			tostring( layer.selected ), tostring( layer.damageable ),
			tostring( layer.passesExistingHole ),
			tostring( layer.advancedBodygroupToolHidden ),
			tostring( layer.bodygroupId ), layer.raySampleCount or 0,
			layer.openRaySampleCount or 0, tostring( layer.damageMaskSerial ),
			layer.minimumDepth or 0,
			layer.maximumDepth or 0, tostring( layer.meshIndex ),
			tostring( layer.name ) )
	end
	file.Write( folder .. "/visual_layers.txt",
		table.concat( layerLines, "\n" ) .. "\n" )
	file.Write( folder .. "/rtx_identity_history.txt",
		RTX.BuildIdentityHistoryText( mask ) )
	mask.generatedVMT = mask.generatedVMT or GeneratedVMTText(
		mask.originalShader, mask.cloneParameters )
	file.Write( folder .. "/generated_material.vmt.txt", mask.generatedVMT )
	file.Write( folder .. "/generated_parameters.json",
		util.TableToJSON( mask.cloneParameters or {}, true ) or "{}" )
	file.Write( folder .. "/selected_uv_triangles.txt", BuildUVText( materialRecord ) )
	file.Write( folder .. "/projected_uv_triangles.txt",
		BuildProjectedUVText( materialRecord ) )
	file.Write( folder .. "/removal_hull_shape.txt",
		BuildRemovalHullShapeText( hit ) )
	file.Write( folder .. "/selected_mesh_triangles.txt", BuildMeshSelectionText( query ) )
	file.Write( folder .. "/bodygroup_filter.txt",
		BuildBodygroupFilterText( hit.damageUV ) )
	file.Write( folder .. "/render_target_pixel_probes.txt",
		table.concat( captures.probeLines or { "No pixel probes were captured." }, "\n" ) .. "\n" )
	file.Write( folder .. "/uv_rasterization.txt", table.concat( {
		"Irregular damage-scaled removal-hull projected UV coverage rasterization",
		"source_triangle_count=" .. tostring( paint.triangleCount ),
		"projected_triangle_count=" .. tostring( paint.projectedTriangleCount ),
		"projection_depth=" .. tostring( paint.projectionDepth ),
		"projection_requested_depth=" .. tostring( paint.projectionRequestedDepth ),
		"projection_budget_limited=" .. tostring( paint.projectionBudgetLimited ),
		"projection_conservative_upper_bound=" .. tostring(
			paint.projectionConservativeUpperBound ),
		"projection_coarse_terminal=" .. tostring(
			paint.projectionCoarseTerminal ),
		"projection_retry_count=" .. tostring( paint.projectionRetryCount ),
		"projection_discarded_at_cap=" .. tostring(
			paint.projectionDiscardedAtCap ),
		"projection_maximum_depth_reached=" .. tostring(
			paint.projectionMaximumDepthReached ),
		"projection_tolerance_world=" .. tostring( paint.projectionTolerance ),
		"projection_triangle_cap=" .. tostring( paint.projectionMaximumTriangles ),
		"projection_local_radius_bounds=" .. tostring(
			paint.projectionLocalBounds ),
		"projection_local_angular_bound_cells=" .. tostring(
			paint.projectionAngularBoundCellCount ),
		"projection_global_angular_bound_cells=" .. tostring(
			paint.projectionGlobalAngularBoundCellCount ),
		"projection_maximum_angular_deviation_radians=" .. tostring(
			paint.projectionMaximumAngularDeviation ),
		"projection_maximum_radius_slope_per_radian=" .. tostring(
			paint.projectionMaximumAngularSlope ),
		"projection_capped=" .. tostring( paint.projectionCapped ),
		"projection_cpu_milliseconds=" .. tostring( paint.projectionMilliseconds ),
		"projection_cells_visited=" .. tostring( paint.projectionVisitedCellCount ),
		"projection_cells_inside=" .. tostring( paint.projectionInsideCellCount ),
		"projection_cells_outside=" .. tostring( paint.projectionOutsideCellCount ),
		"projection_cells_boundary=" .. tostring( paint.projectionBoundaryCellCount ),
		"projection_source_triangles_missed=" .. tostring(
			paint.projectionMissedSourceTriangleCount ),
		"projection_source_triangles_missing_world=" .. tostring(
			paint.projectionMissingWorldTriangleCount ),
		"projection_error=" .. tostring( paint.projectionError ),
		"shape_seed=" .. tostring( paint.shapeSeed ),
		"shape_sample_count=" .. tostring( paint.shapeSampleCount ),
		"shape_tear_count=" .. tostring( paint.shapeTearCount ),
		"shape_irregularity=" .. tostring( paint.shapeIrregularity ),
		"shape_damage_multiplier=" .. tostring( paint.shapeDamageMultiplier ),
		"shape_minimum_radius=" .. tostring( paint.shapeMinimumRadius ),
		"shape_nominal_radius=" .. tostring( paint.shapeNominalRadius ),
		"shape_maximum_radius=" .. tostring( paint.shapeMaximumRadius ),
		"expansion_pixels=" .. tostring( paint.expansion ),
		"feather_pixels=" .. tostring( paint.feather ),
		"blur_passes=" .. tostring( paint.blurPasses ),
		"unwrap_seams=" .. tostring( paint.unwrapSeams ),
		"seam_triangles_unwrapped=" .. tostring( paint.seamTriangleCount ),
		"maximum_raw_span=[" .. tostring( paint.maximumRawUSpan ) .. " "
			.. tostring( paint.maximumRawVSpan ) .. "]",
		"maximum_raster_span=[" .. tostring( paint.maximumRasterUSpan ) .. " "
			.. tostring( paint.maximumRasterVSpan ) .. "]",
		"raster_batch_requested=" .. tostring( paint.batchRasterRequested ),
		"raster_mode=" .. tostring( paint.rasterMode ),
		"raster_polygon_count=" .. tostring( paint.rasterPolygonCount ),
		"raster_primitive_count=" .. tostring( paint.rasterPrimitiveCount ),
		"raster_batch_count=" .. tostring( paint.rasterBatchCount ),
		"raster_fallback_error=" .. tostring( paint.rasterFallbackError ),
		"raster_milliseconds=" .. tostring( paint.rasterMilliseconds ),
		"blur_milliseconds=" .. tostring( paint.blurMilliseconds ),
		"alpha_composite_milliseconds=" .. tostring(
			paint.alphaCompositeMilliseconds ),
	}, "\n" ) .. "\n" )

	local originalVMT = file.Read( "materials/" .. NormalizeMaterialPath(
		mask.originalPath ) .. ".vmt", "GAME" )
	file.Write( folder .. "/original_material.vmt.txt", originalVMT
		or "// Original VMT was not readable through the GAME search path.\n" )
	-- Keep the traditional names as forced-opaque RGB captures so a valid
	-- texture cannot look blank merely because its alpha is zero.
	if captures.beforeRGB then
		file.Write( folder .. "/texture_before.png", captures.beforeRGB )
		file.Write( folder .. "/texture_before_rgb.png", captures.beforeRGB )
	end
	if captures.beforeAlpha then
		file.Write( folder .. "/texture_before_with_alpha.png", captures.beforeAlpha )
	end
	if captures.afterRGB then
		file.Write( folder .. "/texture_edited.png", captures.afterRGB )
		file.Write( folder .. "/texture_edited_rgb.png", captures.afterRGB )
	end
	if captures.afterAlpha then
		file.Write( folder .. "/texture_edited_with_alpha.png", captures.afterAlpha )
	end
	if captures.coverageBefore then
		file.Write( folder .. "/coverage_before_blur.png", captures.coverageBefore )
	end
	if captures.coverageAfter then
		file.Write( folder .. "/coverage_after_blur.png", captures.coverageAfter )
	end
	mask.lastDebugFolder = folder
	BBS.Log( "  wrote material debug bundle: data/%s/", folder )
end

-- Diagnostics must never prevent an otherwise valid material punch. Keep all
-- filesystem/report failures outside the authoritative application result.
local function TryWriteMaterialDebugBundle( job, mask, captures )
	local ok, errorMessage = pcall( WriteMaterialDebugBundle, job, mask, captures )
	if not ok then
		BBS.Log( "  material debug bundle failed (damage remains applied): %s",
			tostring( errorMessage ) )
	end
	return ok
end

-- Resolution is always the source texture's exact width and height. Legacy
-- size convars remain registered for old configs, but never cap either mask.
-- GetRenderTargetEx requires power-of-two axes; reject unsupported sources
-- before allocation instead of rounding or silently reducing their detail.
local function DamageRenderTargetDimensions( sourceWidth, sourceHeight )
	if sourceWidth == nil or sourceHeight == nil then
		return nil, "full-resolution damage requires valid source texture dimensions"
	end
	for _, dimension in ipairs( { sourceWidth, sourceHeight } ) do
		if type( dimension ) ~= "number" or dimension ~= dimension
		or dimension < 1 or dimension == math.huge
		or dimension ~= math.floor( dimension ) then
			return nil, "full-resolution damage requires valid source texture dimensions"
		end
		local power = 1
		while power < dimension do power = power * 2 end
		if power ~= dimension then
			return nil, "full-resolution damage requires power-of-two source texture dimensions"
		end
	end
	local widthOK, maximumWidth = pcall( render.MaxTextureWidth )
	local heightOK, maximumHeight = pcall( render.MaxTextureHeight )
	if not widthOK or not heightOK or type( maximumWidth ) ~= "number"
	or type( maximumHeight ) ~= "number" or maximumWidth ~= maximumWidth
	or maximumHeight ~= maximumHeight or maximumWidth < 1 or maximumHeight < 1
	or maximumWidth == math.huge or maximumHeight == math.huge then
		return nil, "full-resolution damage unavailable: renderer texture limits could not be determined"
	end
	if sourceWidth > maximumWidth or sourceHeight > maximumHeight then
		return nil, string.format(
			"full-resolution damage unavailable: source %dx%d exceeds renderer limit %dx%d; source material kept",
			sourceWidth, sourceHeight, maximumWidth, maximumHeight )
	end
	return sourceWidth, sourceHeight, maximumWidth, maximumHeight
end

local function CreateFullResolutionTarget( name, width, height, flags )
	local validatedWidth, dimensionError = DamageRenderTargetDimensions( width, height )
	if not validatedWidth then return nil, dimensionError end
	local ok, target = pcall( GetRenderTargetEx, name, width, height,
		RT_SIZE_LITERAL, MATERIAL_RT_DEPTH_NONE, flags, 0, IMAGE_FORMAT_BGRA8888 )
	if not ok or not target or target:IsError()
	or ( target.IsErrorTexture and target:IsErrorTexture() ) then
		return nil, "full-resolution damage target allocation failed: " .. tostring( target )
	end
	-- Literal mode can still be coerced by Source branches/drivers. Never use a
	-- lower-resolution allocation (or a differently shaped one) for the source.
	if target:Width() ~= width or target:Height() ~= height then
		return nil, string.format(
			"full-resolution damage unavailable: renderer allocated %dx%d for %dx%d; source material kept",
			target:Width(), target:Height(), width, height )
	end
	return target
end

-- Paint jobs run serially in HUDPaint, so their temporary coverage surface can
-- be shared by every damaged material at the same resolution. Persistent
-- per-material RTs remain independent and continue accumulating damage.
local function GetSharedCoverageResources( width, height )
	local requestedCacheKey = width .. "x" .. height
	local cached = BBS.DamageSharedCoverage[ requestedCacheKey ]
	if cached and cached.width == width and cached.height == height then return cached end
	local suffix = DAMAGE_RESOURCE_SUFFIX .. requestedCacheKey
	local targetName = "bbs_damage_coverage_rt_" .. suffix
	local target, allocationError = CreateFullResolutionTarget(
		targetName, width, height, COVERAGE_RT_FLAGS )
	if not target then return nil, allocationError end
	local materialName = "bbs_damage_coverage_mat_" .. suffix
	local material = CreateMaterial( materialName, "UnlitGeneric", {
		[ "$basetexture" ] = target:GetName(),
		[ "$translucent" ] = "1",
		[ "$ignorez" ] = "1",
	} )
	material:SetTexture( "$basetexture", target )
	local previewName = "bbs_damage_coverage_preview_" .. suffix
	local preview = CreateMaterial( previewName, "UnlitGeneric", {
		[ "$basetexture" ] = target:GetName(),
		[ "$ignorez" ] = "1",
	} )
	preview:SetTexture( "$basetexture", target )
	cached = {
		target = target,
		targetName = targetName,
		material = material,
		materialName = materialName,
		preview = preview,
		width = width,
		height = height,
	}
	BBS.DamageSharedCoverage[ requestedCacheKey ] = cached
	BBS.DamageSharedCoverage[ width .. "x" .. height ] = cached
	return cached
end

local VTF_ALPHA_FLAGS = 0x3000 -- TEXTUREFLAGS_ONEBITALPHA | EIGHTBITALPHA
local VTF_ALPHA_FORMATS = {
	[ 0 ] = true,  -- RGBA8888
	[ 1 ] = true,  -- ABGR8888
	[ 6 ] = true,  -- IA88
	[ 8 ] = true,  -- A8
	[ 11 ] = true, -- ARGB8888
	[ 12 ] = true, -- BGRA8888
	[ 14 ] = true, -- DXT3
	[ 15 ] = true, -- DXT5
	[ 19 ] = true, -- BGRA4444
	[ 20 ] = true, -- DXT1_ONEBITALPHA
	[ 21 ] = true, -- BGRA5551
	[ 24 ] = true, -- RGBA16161616F
	[ 25 ] = true, -- RGBA16161616
	[ 29 ] = true, -- RGBA32323232F
}

local function UInt32LE( source, offset )
	local first, second, third, fourth = string.byte( source, offset, offset + 3 )
	if not fourth then return nil end
	return first + second * 256 + third * 65536 + fourth * 16777216
end

-- A VMT can author $alphatest even when its VTF has no alpha channel. Source
-- treats that texture as opaque, but copying a DXT1 texture through the alpha
-- helper can produce 1/255 alpha and hide the complete generated material.
-- Read only the mounted VTF header so the initialization path follows the
-- actual texture storage rather than assuming that VMT intent implies data.
local function GetVTFMetadata( baseTexture )
	local baseName = NormalizeMaterialPath( baseTexture:GetName() )
	baseName = string.gsub( baseName, "%.vtf$", "" )
	local cached = BBS.DamageVTFMetadataCache[ baseName ]
	if cached then return cached end

	local metadata = {
		path = baseName,
		readable = false,
		hasAlpha = nil,
		reason = "unreadable",
	}
	local handle = file.Open( "materials/" .. baseName .. ".vtf", "rb", "GAME" )
	if not handle then
		BBS.DamageVTFMetadataCache[ baseName ] = metadata
		return metadata
	end
	local ok, header = pcall( function() return handle:Read( 56 ) end )
	handle:Close()
	if not ok or not header or #header < 56 or string.sub( header, 1, 4 ) ~= "VTF\0" then
		metadata.reason = ok and "invalid-header" or tostring( header )
		BBS.DamageVTFMetadataCache[ baseName ] = metadata
		return metadata
	end

	metadata.readable = true
	metadata.flags = UInt32LE( header, 21 ) or 0
	metadata.imageFormat = UInt32LE( header, 53 )
	metadata.hasAlpha = bit.band( metadata.flags, VTF_ALPHA_FLAGS ) ~= 0
		or VTF_ALPHA_FORMATS[ metadata.imageFormat ] == true
	metadata.reason = metadata.hasAlpha and "vtf-alpha" or "vtf-no-alpha"
	BBS.DamageVTFMetadataCache[ baseName ] = metadata
	return metadata
end

local function SetDepthToDestinationAlpha( enabled )
	if render.SetWriteDepthToDestAlpha then
		render.SetWriteDepthToDestAlpha( enabled )
	end
end

local function InitializeRenderTarget( renderTarget, sourceRGB, sourceAlpha,
	alphaStyle )
	-- Source normally writes depth into destination alpha during model/render
	-- passes. On BGRA8888 render targets that turns an intended opaque alpha
	-- value into byte value 1, which fails a 0.5 alpha test and hides the entire
	-- cloned material. Disable that global render parameter for every alpha
	-- operation below and restore the engine default when finished.
	local state = { depthChanged = false, targetPushed = false, camStarted = false }
	local ok, errorMessage = pcall( function()
		BBS.MaterialSafety.BeginRender( state )
		SetDepthToDestinationAlpha( false )
		state.depthChanged = true
		render.PushRenderTarget( renderTarget )
		state.targetPushed = true
		render.OverrideAlphaWriteEnable( true, true )
		render.Clear( COPY_SENTINEL_R, COPY_SENTINEL_G, COPY_SENTINEL_B, 255 )
		render.OverrideAlphaWriteEnable( false )
		cam.Start2D()
		state.camStarted = true
			-- Pass 1: copy the source RGB verbatim while leaving destination
			-- alpha untouched. A render-library screen quad is used here because
			-- surface.DrawTexturedRect did not write into this RT in PreRender.
			render.OverrideAlphaWriteEnable( true, false )
			render.OverrideBlend( true, BLEND_ONE, BLEND_ZERO, BLENDFUNC_ADD )
			render.SetMaterial( sourceRGB )
			render.DrawScreenQuad()
			render.OverrideBlend( false )
			render.OverrideAlphaWriteEnable( false )

			-- render.Clear is known to produce incorrect alpha for render targets
			-- used by surface rendering. Always establish destination alpha with a
			-- real full-screen draw instead of trusting the clear value.
			render.OverrideColorWriteEnable( true, false )
			render.OverrideAlphaWriteEnable( true, true )
			if alphaStyle then
				-- Pass 2: keep the copied RGB and replace destination alpha with
				-- the source texture's recorded alpha channel.
				render.OverrideBlend( true,
					BLEND_ZERO, BLEND_ONE, BLENDFUNC_ADD,
					BLEND_ONE, BLEND_ZERO, BLENDFUNC_ADD )
				render.SetMaterial( sourceAlpha )
				render.DrawScreenQuad()
			else
				-- Alpha-less VTF formats must begin completely opaque. Use a solid
				-- 255-alpha surface primitive rather than sampling the source helper;
				-- this avoids both DXT1's synthetic alpha and render.Clear's known RT
				-- alpha bug while color writes remain disabled.
				render.OverrideBlend( true,
					BLEND_ZERO, BLEND_ONE, BLENDFUNC_ADD,
					BLEND_ONE, BLEND_ZERO, BLENDFUNC_ADD )
				surface.SetDrawColor( 255, 255, 255, 255 )
				surface.DrawRect( 0, 0, renderTarget:Width(), renderTarget:Height() )
			end
			render.OverrideBlend( false )
			render.OverrideAlphaWriteEnable( false )
			render.OverrideColorWriteEnable( false, false )
	end )
	-- Bad source/AME materials must not leak render state into the rest of the
	-- frame. Cleanup is outside pcall so it also runs after any draw error.
	pcall( render.OverrideBlend, false )
	pcall( render.OverrideAlphaWriteEnable, false )
	pcall( render.OverrideColorWriteEnable, false, false )
	if state.camStarted then pcall( cam.End2D ) end
	if state.targetPushed then pcall( render.PopRenderTarget ) end
	if state.depthChanged then pcall( SetDepthToDestinationAlpha, true ) end
	BBS.MaterialSafety.EndRender( state )
	if not ok then error( errorMessage, 0 ) end
end

local function GetSourceCopyMaterials( baseTexture )
	local baseName = NormalizeMaterialPath( baseTexture:GetName() )
	local cached = BBS.DamageSourceMaterialCache[ baseName ]
	if cached then
		-- AME-generated textures may keep a stable material-system name while the
		-- backing ITexture is regenerated. Rebind the live object on every use so
		-- the source-copy helpers cannot retain an older generated image.
		cached.rgb:SetTexture( "$basetexture", baseTexture )
		cached.alpha:SetTexture( "$basetexture", baseTexture )
		return cached.rgb, cached.alpha
	end
	local suffix = DAMAGE_RESOURCE_SUFFIX .. util.CRC( baseName )
	local rgb = CreateMaterial( "bbs_damage_source_rgb_" .. suffix,
		"UnlitGeneric", {
			[ "$basetexture" ] = baseTexture:GetName(),
			[ "$ignorez" ] = "1",
		} )
	rgb:SetTexture( "$basetexture", baseTexture )
	local alpha = CreateMaterial( "bbs_damage_source_alpha_" .. suffix,
		"UnlitGeneric", {
			[ "$basetexture" ] = baseTexture:GetName(),
			[ "$translucent" ] = "1",
			[ "$ignorez" ] = "1",
		} )
	alpha:SetTexture( "$basetexture", baseTexture )
	BBS.DamageSourceMaterialCache[ baseName ] = { rgb = rgb, alpha = alpha }
	return rgb, alpha
end

local function IntersectRenderTargetAlphaBySource( renderTarget, sourceAlpha )
	local state = { depthChanged = false, targetPushed = false, camStarted = false }
	local ok, errorMessage = pcall( function()
		BBS.MaterialSafety.BeginRender( state )
		SetDepthToDestinationAlpha( false )
		state.depthChanged = true
		render.PushRenderTarget( renderTarget )
		state.targetPushed = true
		cam.Start2D()
		state.camStarted = true
		render.OverrideColorWriteEnable( true, false )
		render.OverrideAlphaWriteEnable( true, true )
		-- Both textures already contain the original source opacity. Multiplying
		-- it again makes unchanged cloth fade on every editor refresh (a^n).
		-- The minimum preserves both cutouts without compounding that opacity.
		render.OverrideBlend( true,
			BLEND_ZERO, BLEND_ONE, BLENDFUNC_ADD,
			BLEND_ONE, BLEND_ONE, BLENDFUNC_MIN )
		render.SetMaterial( sourceAlpha )
		render.DrawScreenQuad()
	end )
	pcall( render.OverrideBlend, false )
	pcall( render.OverrideAlphaWriteEnable, false )
	pcall( render.OverrideColorWriteEnable, false, false )
	if state.camStarted then pcall( cam.End2D ) end
	if state.targetPushed then pcall( render.PopRenderTarget ) end
	if state.depthChanged then pcall( SetDepthToDestinationAlpha, true ) end
	BBS.MaterialSafety.EndRender( state )
	if not ok then return false, tostring( errorMessage ) end
	return true
end

local function ApplyLiveMaterialObjects( source, target )
	local appliedTextures, appliedMatrices, errors = 0, 0, {}
	local values = source:GetKeyValues() or {}
	for rawKey, value in pairs( values ) do
		local key = string.lower( tostring( rawKey ) )
		local valueType = TypeID( value )
		if key ~= "$basetexture" and valueType == TYPE_TEXTURE then
			local ok, errorMessage = pcall( target.SetTexture, target, key, value )
			if ok then appliedTextures = appliedTextures + 1
			else errors[ #errors + 1 ] = key .. ": " .. tostring( errorMessage ) end
		elseif valueType == TYPE_MATRIX then
			local ok, errorMessage = pcall( target.SetMatrix, target, key, value )
			if ok then appliedMatrices = appliedMatrices + 1
			else errors[ #errors + 1 ] = key .. ": " .. tostring( errorMessage ) end
		end
	end
	-- Several Source branches stringify transform values in GetKeyValues even
	-- though the live IMaterial still exposes a matrix object.
	for _, key in ipairs( { "$basetexturetransform", "$bumptransform",
		"$detailtexturetransform", "$envmapmasktransform" } ) do
		local matrix = source:GetMatrix( key )
		if matrix then
			local ok, errorMessage = pcall( target.SetMatrix, target, key, matrix )
			if ok then appliedMatrices = appliedMatrices + 1
			else errors[ #errors + 1 ] = key .. ": " .. tostring( errorMessage ) end
		end
	end
	return appliedTextures, appliedMatrices, errors
end

local function TransferDamageMaskHistory( previousMask, replacementMask )
	if not previousMask or not replacementMask then return true end
	local _, previousAlpha = GetSourceCopyMaterials( previousMask.renderTarget )
	local ok, errorMessage = IntersectRenderTargetAlphaBySource(
		replacementMask.renderTarget, previousAlpha )
	if not ok then return false, errorMessage end
	replacementMask.damageCoverage = previousMask.damageCoverage
	replacementMask.paintedTriangleCount = previousMask.paintedTriangleCount or 0
	replacementMask.paintedProjectedTriangleCount =
		previousMask.paintedProjectedTriangleCount or 0
	replacementMask.compatibilityHistoryTransferred = true
	replacementMask.compatibilityHistoryMode = "alpha-intersection-no-compounding"
	replacementMask.compatibilityPreviousSerial = previousMask.serial
	return true
end

local function CreateDamageMask( entity, submaterialIndex, originalPath,
	editedSources, yieldStage )
	local diskOriginal = Material( originalPath )
	if not diskOriginal or diskOriginal:IsError() then
		return nil, "original material failed to load"
	end
	editedSources = editedSources or ResolveEditedMaterialSources(
		entity, submaterialIndex, originalPath )
	if editedSources.pending then
		return nil, editedSources.pendingReason
			or "edited material source is pending", true
	end
	local advancedMaterial = editedSources.advancedMaterialEditor
	local advancedBodygroup = editedSources.advancedBodygroupTool
	local effectiveSource = editedSources.primary
	local original = effectiveSource and effectiveSource.material or diskOriginal
	local baseTexture = original:GetTexture( "$basetexture" )
	if not baseTexture or baseTexture:IsError() then return nil, "material has no usable $basetexture" end

	BBS.DamageMaterialSerial = BBS.DamageMaterialSerial + 1
	local serial = BBS.DamageMaterialSerial
	local sourceWidth, sourceHeight = SourceTextureDimensions( baseTexture )
	local width, height, hardwareMaximumWidth, hardwareMaximumHeight =
		DamageRenderTargetDimensions( sourceWidth, sourceHeight )
	if not width then return nil, height end
	if yieldStage then yieldStage( "mask_source_resolved" ) end
	local renderTargetName = "bbs_damage_rt_" .. DAMAGE_RESOURCE_SUFFIX .. serial
	local renderTarget, allocationError = CreateFullResolutionTarget(
		renderTargetName, width, height, DAMAGE_RT_FLAGS )
	if not renderTarget then return nil, allocationError end

	local originalParameters = original:GetKeyValues() or {}
	local originalFlags = tonumber( originalParameters[ "$flags" ] ) or 0
	local parameters, copied, dropped, sourceShader, materialSource, alphaStyle,
		inheritedNoCull =
		CloneMaterialParameters( originalPath, original, renderTarget:GetName(),
			effectiveSource )
	local vtfMetadata = GetVTFMetadata( baseTexture )
	-- If the VTF header cannot be read, preserve the previous conservative
	-- behavior. A readable alpha-less VTF is deliberately initialized opaque.
	local preserveSourceAlpha = alphaStyle
		and ( not vtfMetadata.readable or vtfMetadata.hasAlpha )

	-- These helpers are immutable and safely shared by all masks that copy the
	-- same source texture.
	local sourceRGB, sourceAlpha = GetSourceCopyMaterials( baseTexture )
	InitializeRenderTarget( renderTarget, sourceRGB, sourceAlpha, preserveSourceAlpha )
	local advancedBodygroupAlphaComposited = false
	local advancedBodygroupAlphaMode = advancedBodygroup
		and ( advancedMaterial and "intersected-with-ame"
			or "intersected-with-mounted-vmt" ) or "absent"
	local advancedBodygroupAlphaError
	if advancedBodygroup then
		local abtBaseTexture = advancedBodygroup.material:GetTexture( "$basetexture" )
		if abtBaseTexture and not abtBaseTexture:IsError() then
			local _, abtAlpha = GetSourceCopyMaterials( abtBaseTexture )
			advancedBodygroupAlphaComposited, advancedBodygroupAlphaError =
				IntersectRenderTargetAlphaBySource( renderTarget, abtAlpha )
		else
			advancedBodygroupAlphaError = "ABT material has no usable $basetexture"
		end
		if not advancedBodygroupAlphaComposited then
			return nil, "could not compose Advanced Bodygroup Tool alpha: "
				.. tostring( advancedBodygroupAlphaError )
		end
	end
	if yieldStage then yieldStage( "mask_texture_initialized" ) end

	local materialName = "bbs_damage_mat_" .. DAMAGE_RESOURCE_SUFFIX .. serial
	local shader = sourceShader or original:GetShader() or "VertexLitGeneric"
	if shader == "" or string.lower( shader ) == "shader_error" then shader = "VertexLitGeneric" end
	local override = CreateMaterial( materialName, shader, parameters )
	if not override or override:IsError() then return nil, "CreateMaterial returned an error material" end
	override:SetTexture( "$basetexture", renderTarget )
	local liveTextureCount, liveMatrixCount, liveObjectErrors =
		ApplyLiveMaterialObjects( original, override )
	local generatedTextureCount = 0
	local generatedTextureErrors = {}
	for rawKey, texture in pairs( advancedMaterial
		and advancedMaterial.generatedTextures or {} ) do
		local key = string.lower( tostring( rawKey ) )
		-- The damaged render target deliberately replaces AME's effective base
		-- texture. Every other generated map (normal, detail, masks, etc.) must
		-- remain attached to preserve the edited appearance.
		if key ~= "$basetexture" and texture then
			local ok, errorMessage = pcall( override.SetTexture,
				override, key, texture )
			if ok then
				generatedTextureCount = generatedTextureCount + 1
			else
				generatedTextureErrors[ #generatedTextureErrors + 1 ] =
					key .. ": " .. tostring( errorMessage )
			end
		end
	end

	if yieldStage then yieldStage( "mask_material_created" ) end
	local coverage, coverageError = GetSharedCoverageResources( width, height )
	if not coverage then return nil, coverageError end

	local previousOverride = ""
	if entity.GetSubMaterial then previousOverride = entity:GetSubMaterial( submaterialIndex ) or "" end
	-- Client previews are not reflected by GetSubMaterial; AME documents that
	-- it reports the server value in this mode. Remember the resolved AME name
	-- so clearing BBS restores the actual edited material instead of the VMT.
	if advancedMaterial and advancedMaterial.overrideName then
		previousOverride = advancedMaterial.overrideName
	end
	return {
		entity = entity,
		submaterialIndex = submaterialIndex,
		originalPath = originalPath,
		originalMaterial = original,
		diskOriginalMaterial = diskOriginal,
		originalShader = shader,
		originalFlags = originalFlags,
		materialSource = materialSource,
		copiedParameterCount = copied,
		droppedParameterCount = dropped,
		cloneParameters = parameters,
		inheritedNoCullParameter = inheritedNoCull,
		forceNoCull = GetBool( "bbs_damage_force_nocull", true ),
		alphaStyleSource = alphaStyle,
		preserveSourceAlpha = preserveSourceAlpha,
		vtfMetadata = vtfMetadata,
		alphaTestReference = parameters[ "$alphatestreference" ],
		alphaParameter = parameters[ "$alpha" ],
		baseTextureName = baseTexture:GetName(),
		advancedMaterialEditor = advancedMaterial ~= nil,
		editedSourceSignature = editedSources.signature,
		directMaterialOwnership = advancedMaterial ~= nil
			or advancedBodygroup ~= nil,
		advancedMaterialEditorMaterialName = advancedMaterial
			and advancedMaterial.materialName or nil,
		advancedMaterialEditorOverride = advancedMaterial
			and advancedMaterial.overrideName or nil,
		advancedMaterialEditorPreview = advancedMaterial
			and advancedMaterial.preview or false,
		advancedMaterialEditorClientOwned = advancedMaterial
			and advancedMaterial.clientOwned or false,
		advancedMaterialEditorRuleScope = advancedMaterial
			and advancedMaterial.ruleScope or nil,
		advancedMaterialEditorRuleMaterial = advancedMaterial
			and advancedMaterial.ruleMaterial or nil,
		advancedMaterialEditorRawOverride = advancedMaterial
			and advancedMaterial.rawOverride or nil,
		advancedMaterialEditorParameterCount = advancedMaterial
			and CountMaterialParameters( advancedMaterial.parameters ) or 0,
		advancedMaterialEditorGeneratedTextureCount = advancedMaterial
			and advancedMaterial.generatedTextureCount or 0,
		advancedMaterialEditorGeneratedTexturesApplied = generatedTextureCount,
		advancedMaterialEditorGeneratedTextureErrors = generatedTextureErrors,
		advancedMaterialEditorResolveError = advancedMaterial
			and advancedMaterial.resolveError or nil,
		advancedMaterialEditorBuildError = advancedMaterial
			and advancedMaterial.buildError or nil,
		advancedBodygroupTool = advancedBodygroup ~= nil,
		advancedBodygroupToolIdentity = advancedBodygroup
			and advancedBodygroup.stateIdentity or nil,
		advancedBodygroupToolMaterialName = advancedBodygroup
			and advancedBodygroup.materialName or nil,
		advancedBodygroupToolTargetName = advancedBodygroup
			and advancedBodygroup.targetName or nil,
		advancedBodygroupToolSourceMaterial = advancedBodygroup
			and advancedBodygroup.material or nil,
		advancedBodygroupToolSourceResource = advancedBodygroup
			and advancedBodygroup.resource or nil,
		advancedBodygroupToolAlphaComposited =
			advancedBodygroupAlphaComposited,
		advancedBodygroupToolAlphaMode = advancedBodygroupAlphaMode,
		advancedBodygroupToolAlphaError = advancedBodygroupAlphaError,
		liveTextureObjectsApplied = liveTextureCount,
		liveMatrixObjectsApplied = liveMatrixCount,
		liveObjectErrors = liveObjectErrors,
		sourceTextureWidth = sourceWidth,
		sourceTextureHeight = sourceHeight,
		resolutionPolicy = "full-source",
		requestedMaximumEdge = math.max( sourceWidth, sourceHeight ),
		normalizedMaximumEdge = math.max( width, height ),
		hardwareMaximumEdge = math.min( hardwareMaximumWidth, hardwareMaximumHeight ),
		hardwareMaximumWidth = hardwareMaximumWidth,
		hardwareMaximumHeight = hardwareMaximumHeight,
		sourceScale = 1,
		sourceScaleX = width / sourceWidth,
		sourceScaleY = height / sourceHeight,
		sourceCopyMethod =
			"render.DrawScreenQuad RGB + depth-alpha-safe explicit alpha in HUDPaint",
		alphaInitialization = preserveSourceAlpha
			and "copied-source-alpha" or "forced-opaque-fullscreen-draw",
		sourceRGBMaterial = sourceRGB,
		sourceAlphaMaterial = sourceAlpha,
		previousOverride = previousOverride,
		renderTarget = renderTarget,
		renderTargetName = renderTargetName,
		width = width,
		height = height,
		size = math.max( width, height ),
		material = override,
		materialName = materialName,
		serial = serial,
		generatedVMT = ( GetBool( "bbs_damage_dump_debug", false )
			or GetBool( "bbs_damage_print_vmt", false ) )
			and GeneratedVMTText( shader, parameters ) or nil,
		coverageTarget = coverage.target,
		coverageTargetName = coverage.targetName,
		coverageWidth = coverage.width,
		coverageHeight = coverage.height,
		coverageMaterial = coverage.material,
		coverageMaterialName = coverage.materialName,
		coveragePreviewMaterial = coverage.preview,
		baseTextureTransform = BuildUVTransformAffine(
			original:GetMatrix( "$basetexturetransform" ) ),
		paintedTriangleCount = 0,
		paintedProjectedTriangleCount = 0,
	}
end

local function EnsureDamagePreviewMaterials( mask )
	if not mask or mask.previewMaterial then return end
	local serial = mask.serial or 0
	local originalPreview = CreateMaterial(
		"bbs_damage_original_preview_" .. DAMAGE_RESOURCE_SUFFIX .. serial, "UnlitGeneric", {
			[ "$basetexture" ] = mask.baseTextureName,
		} )
	originalPreview:SetTexture( "$basetexture", mask.originalMaterial:GetTexture( "$basetexture" ) )
	local preview = CreateMaterial( "bbs_damage_preview_" .. DAMAGE_RESOURCE_SUFFIX .. serial,
		"UnlitGeneric", {
			[ "$basetexture" ] = mask.renderTargetName,
			[ "$translucent" ] = "1",
			[ "$vertexcolor" ] = "1",
		} )
	preview:SetTexture( "$basetexture", mask.renderTarget )
	local rgbPreview = CreateMaterial( "bbs_damage_rgb_preview_" .. DAMAGE_RESOURCE_SUFFIX .. serial,
		"UnlitGeneric", {
			[ "$basetexture" ] = mask.renderTargetName,
		} )
	rgbPreview:SetTexture( "$basetexture", mask.renderTarget )
	mask.originalPreviewMaterial = originalPreview
	mask.previewMaterial = preview
	mask.rgbPreviewMaterial = rgbPreview
end

local function TransformUVCoordinates( coordinates, transform )
	if not transform then return coordinates end
	local transformed = {}
	for _, coordinate in ipairs( coordinates ) do
		local u, v = TransformSingleUV( coordinate.u, coordinate.v, transform )
		transformed[ #transformed + 1 ] = { u = u, v = v }
	end
	return transformed
end

local function UVSpan( coordinates, key )
	local minimum, maximum = math.huge, -math.huge
	for _, coordinate in ipairs( coordinates or {} ) do
		local value = coordinate[ key ]
		if value and value == value then
			minimum = math.min( minimum, value )
			maximum = math.max( maximum, value )
		end
	end
	if minimum == math.huge then return 0 end
	return maximum - minimum
end

local function UnwrapUVTriangle( coordinates, enabled )
	local output = {}
	for _, coordinate in ipairs( coordinates or {} ) do
		output[ #output + 1 ] = { u = coordinate.u, v = coordinate.v }
	end
	if not enabled or #output < 2 then return output, false end
	local anchor = output[ 1 ]
	local changed = false
	for index = 2, #output do
		local coordinate = output[ index ]
		local shiftU = math.floor( anchor.u - coordinate.u + 0.5 )
		local shiftV = math.floor( anchor.v - coordinate.v + 0.5 )
		if shiftU ~= 0 or shiftV ~= 0 then changed = true end
		coordinate.u = coordinate.u + shiftU
		coordinate.v = coordinate.v + shiftV
	end
	return output, changed
end

local function AddProbeCoordinate( output, seen, u, v, kind, width, height )
	if not u or not v or u ~= u or v ~= v then return end
	u = u - math.floor( u )
	v = v - math.floor( v )
	local x = math.Clamp( math.floor( u * width ), 0, width - 1 )
	local y = math.Clamp( math.floor( v * height ), 0, height - 1 )
	local key = x .. ":" .. y
	if seen[ key ] then return end
	seen[ key ] = true
	output[ #output + 1 ] = { x = x, y = y, u = u, v = v, kind = kind }
end

local function BuildProbeCoordinates( mask, triangles )
	local output = {}
	local seen = {}
	for y = 1, 4 do
		for x = 1, 4 do
			AddProbeCoordinate( output, seen, ( x - 0.5 ) / 4,
				( y - 0.5 ) / 4, "grid", mask.width, mask.height )
		end
	end
	for _, triangle in ipairs( triangles or {} ) do
		local transformed = TransformUVCoordinates(
			triangle.uv or {}, mask.baseTextureTransform )
		transformed = UnwrapUVTriangle( transformed,
			GetBool( "bbs_damage_uv_unwrap_seams", true ) )
		local centerU, centerV = 0, 0
		for _, coordinate in ipairs( transformed ) do
			AddProbeCoordinate( output, seen, coordinate.u, coordinate.v,
				"selected_uv", mask.width, mask.height )
			centerU = centerU + ( coordinate.u or 0 )
			centerV = centerV + ( coordinate.v or 0 )
		end
		if #transformed > 0 then
			AddProbeCoordinate( output, seen, centerU / #transformed,
				centerV / #transformed, "triangle_center", mask.width, mask.height )
		end
	end
	return output
end

local function ProbeRenderTarget( mask, triangles, label )
	local probe = {
		label = label,
		ok = false,
		samples = {},
		sampleCount = 0,
		nonSentinelCount = 0,
		transparentCount = 0,
		affectedSampleCount = 0,
		affectedOpaqueCount = 0,
		minimumAlpha = nil,
		maximumAlpha = nil,
	}
	local coordinates = BuildProbeCoordinates( mask, triangles )
	local visibleThreshold = math.max( 1,
		math.ceil( ( tonumber( mask.alphaTestReference ) or 0.5 ) * 255 ) )
	probe.visibleThreshold = visibleThreshold
	render.PushRenderTarget( mask.renderTarget )
	cam.Start2D()
	local ok, errorMessage = pcall( function()
		render.CapturePixels()
		for _, coordinate in ipairs( coordinates ) do
			local r, g, b, a = render.ReadPixel( coordinate.x, coordinate.y )
			if r ~= nil then
				a = a == nil and 255 or a
				probe.sampleCount = probe.sampleCount + 1
				if r ~= COPY_SENTINEL_R or g ~= COPY_SENTINEL_G
				or b ~= COPY_SENTINEL_B then
					probe.nonSentinelCount = probe.nonSentinelCount + 1
				end
				if a < visibleThreshold then probe.transparentCount = probe.transparentCount + 1 end
				if coordinate.kind ~= "grid" then
					probe.affectedSampleCount = probe.affectedSampleCount + 1
					if a >= visibleThreshold then
						probe.affectedOpaqueCount = probe.affectedOpaqueCount + 1
					end
				end
				probe.minimumAlpha = math.min( probe.minimumAlpha or a, a )
				probe.maximumAlpha = math.max( probe.maximumAlpha or a, a )
				probe.samples[ #probe.samples + 1 ] = {
					x = coordinate.x, y = coordinate.y,
					u = coordinate.u, v = coordinate.v,
					kind = coordinate.kind,
					r = r, g = g, b = b, a = a,
				}
			end
		end
	end )
	cam.End2D()
	render.PopRenderTarget()
	probe.ok = ok
	probe.error = not ok and tostring( errorMessage ) or nil
	return probe
end

local function AppendProbeLines( lines, probe )
	if not probe then return end
	lines[ #lines + 1 ] = string.format(
		"[%s] ok=%s samples=%d non_sentinel=%d transparent=%d affected=%d affected_opaque=%d alpha_min=%s alpha_max=%s error=%s",
		tostring( probe.label ), tostring( probe.ok ), probe.sampleCount or 0,
		probe.nonSentinelCount or 0, probe.transparentCount or 0,
		probe.affectedSampleCount or 0, probe.affectedOpaqueCount or 0,
		tostring( probe.minimumAlpha ), tostring( probe.maximumAlpha ),
		tostring( probe.error ) )
	for index, sample in ipairs( probe.samples or {} ) do
		lines[ #lines + 1 ] = string.format(
			"%03d kind=%s pixel=[%d %d] uv=[%.9f %.9f] rgba=[%d %d %d %d]",
			index, tostring( sample.kind ), sample.x, sample.y,
			sample.u, sample.v, sample.r, sample.g, sample.b, sample.a )
	end
end

local function TileShiftRange( minimum, maximum )
	local first = math.ceil( -maximum )
	local last = math.floor( 1 - minimum )
	if last - first > 16 then last = first + 16 end
	return first, last
end

local function TransformAndUnwrapUVTriangle( coordinates, transform, unwrap )
	local first = coordinates and coordinates[ 1 ]
	local second = coordinates and coordinates[ 2 ]
	local third = coordinates and coordinates[ 3 ]
	if not first or not second or not third then return nil end
	local firstU, firstV = TransformSingleUV( first.u, first.v, transform )
	local secondU, secondV = TransformSingleUV( second.u, second.v, transform )
	local thirdU, thirdV = TransformSingleUV( third.u, third.v, transform )
	local rawUSpan = math.max( firstU, secondU, thirdU )
		- math.min( firstU, secondU, thirdU )
	local rawVSpan = math.max( firstV, secondV, thirdV )
		- math.min( firstV, secondV, thirdV )
	local changed = false
	if unwrap then
		local shiftU = math.floor( firstU - secondU + 0.5 )
		local shiftV = math.floor( firstV - secondV + 0.5 )
		changed = shiftU ~= 0 or shiftV ~= 0
		secondU, secondV = secondU + shiftU, secondV + shiftV
		shiftU = math.floor( firstU - thirdU + 0.5 )
		shiftV = math.floor( firstV - thirdV + 0.5 )
		changed = changed or shiftU ~= 0 or shiftV ~= 0
		thirdU, thirdV = thirdU + shiftU, thirdV + shiftV
	end
	local rasterUSpan = math.max( firstU, secondU, thirdU )
		- math.min( firstU, secondU, thirdU )
	local rasterVSpan = math.max( firstV, secondV, thirdV )
		- math.min( firstV, secondV, thirdV )
	return firstU, firstV, secondU, secondV, thirdU, thirdV,
		changed, rawUSpan, rawVSpan, rasterUSpan, rasterVSpan
end

-- Keep a bounded CPU mirror of committed alpha damage. The former exact-triangle
-- bins retained every micro-triangle forever and duplicated references into many
-- cells, so a repeatedly hit material could eventually consume millions of Lua
-- objects. A 512-square bit grid has fixed capacity (32 KiB in packed form;
-- sparse Lua words are allocated only where damage exists) and O(1) lookup.
local DAMAGE_COVERAGE_GRID_SIZE = 512
local DAMAGE_COVERAGE_WORD_BITS = 32
local DAMAGE_COVERAGE_WORDS_PER_ROW =
	DAMAGE_COVERAGE_GRID_SIZE / DAMAGE_COVERAGE_WORD_BITS

local function DamageCoverageCell( coordinate )
	coordinate = coordinate - math.floor( coordinate )
	return math.Clamp( math.floor(
		coordinate * DAMAGE_COVERAGE_GRID_SIZE ), 0,
		DAMAGE_COVERAGE_GRID_SIZE - 1 ), coordinate
end

local function DamageCoverageRangeMask( firstBit, lastBit )
	local all = bit.bnot( 0 )
	local lower = firstBit <= 0 and all or bit.lshift( all, firstBit )
	local upper = lastBit >= DAMAGE_COVERAGE_WORD_BITS - 1 and all
		or bit.bnot( bit.lshift( all, lastBit + 1 ) )
	return bit.band( lower, upper )
end

local function MarkDamageCoverageRange( coverage, row, firstCell, lastCell )
	firstCell = math.Clamp( firstCell, 0, DAMAGE_COVERAGE_GRID_SIZE - 1 )
	lastCell = math.Clamp( lastCell, 0, DAMAGE_COVERAGE_GRID_SIZE - 1 )
	if lastCell < firstCell or row < 0 or row >= DAMAGE_COVERAGE_GRID_SIZE then return end
	local firstWord = math.floor( firstCell / DAMAGE_COVERAGE_WORD_BITS )
	local lastWord = math.floor( lastCell / DAMAGE_COVERAGE_WORD_BITS )
	for word = firstWord, lastWord do
		local firstBit = word == firstWord
			and firstCell % DAMAGE_COVERAGE_WORD_BITS or 0
		local lastBit = word == lastWord
			and lastCell % DAMAGE_COVERAGE_WORD_BITS
			or DAMAGE_COVERAGE_WORD_BITS - 1
		local key = row * DAMAGE_COVERAGE_WORDS_PER_ROW + word + 1
		local previous = coverage.words[ key ] or 0
		local updated = bit.bor( previous,
			DamageCoverageRangeMask( firstBit, lastBit ) )
		if previous == 0 and updated ~= 0 then
			coverage.allocatedWordCount = coverage.allocatedWordCount + 1
		end
		coverage.words[ key ] = updated
	end
end

local function DamageCoverageEdgeIntersection( y, ax, ay, bx, by )
	if ( ay <= y and by > y ) or ( by <= y and ay > y ) then
		return ax + ( y - ay ) * ( bx - ax ) / ( by - ay )
	end
	return nil
end

local function RasterDamageCoverageTriangle( coverage,
	firstU, firstV, secondU, secondV, thirdU, thirdV )
	local size = DAMAGE_COVERAGE_GRID_SIZE
	local minimumV = math.max( math.min( firstV, secondV, thirdV ), 0 )
	local maximumV = math.min( math.max( firstV, secondV, thirdV ), 1 )
	if maximumV < minimumV then return false end
	local firstRow = math.Clamp( math.ceil( minimumV * size - 0.5 ), 0, size - 1 )
	local lastRow = math.Clamp( math.floor( maximumV * size - 0.5 ), 0, size - 1 )
	local marked = false
	for row = firstRow, lastRow do
		local sampleV = ( row + 0.5 ) / size
		local firstX = DamageCoverageEdgeIntersection( sampleV,
			firstU, firstV, secondU, secondV )
		local secondX = DamageCoverageEdgeIntersection( sampleV,
			secondU, secondV, thirdU, thirdV )
		local thirdX = DamageCoverageEdgeIntersection( sampleV,
			thirdU, thirdV, firstU, firstV )
		local minimumX, maximumX
		if firstX and secondX then
			minimumX, maximumX = math.min( firstX, secondX ), math.max( firstX, secondX )
		elseif firstX and thirdX then
			minimumX, maximumX = math.min( firstX, thirdX ), math.max( firstX, thirdX )
		elseif secondX and thirdX then
			minimumX, maximumX = math.min( secondX, thirdX ), math.max( secondX, thirdX )
		end
		if minimumX then
			local firstCell = math.ceil( math.max( minimumX, 0 ) * size - 0.5 )
			local lastCell = math.floor( math.min( maximumX, 1 ) * size - 0.5 )
			if lastCell >= firstCell then
				MarkDamageCoverageRange( coverage, row, firstCell, lastCell )
				marked = true
			end
		end
	end
	-- Micro-triangles smaller than one grid sample still need one stable interior
	-- sample so a later centerline through the middle of that hole can pass.
	if not marked then
		local centerU = ( firstU + secondU + thirdU ) / 3
		local centerV = ( firstV + secondV + thirdV ) / 3
		if centerU >= 0 and centerU < 1 and centerV >= 0 and centerV < 1 then
			local cellX = math.floor( centerU * size )
			local cellY = math.floor( centerV * size )
			MarkDamageCoverageRange( coverage, cellY, cellX, cellX )
			marked = true
		end
	end
	return marked
end

local function PointInsideDamageUVTriangle( u, v, triangle )
	local ax, ay = triangle[ 1 ], triangle[ 2 ]
	local bx, by = triangle[ 3 ], triangle[ 4 ]
	local cx, cy = triangle[ 5 ], triangle[ 6 ]
	local first = ( u - bx ) * ( ay - by ) - ( ax - bx ) * ( v - by )
	local second = ( u - cx ) * ( by - cy ) - ( bx - cx ) * ( v - cy )
	local third = ( u - ax ) * ( cy - ay ) - ( cx - ax ) * ( v - ay )
	local epsilon = 0.00000001
	local hasNegative = first < -epsilon or second < -epsilon or third < -epsilon
	local hasPositive = first > epsilon or second > epsilon or third > epsilon
	return not ( hasNegative and hasPositive )
end

local function NewDamageCoverageGrid()
	return {
		format = 2,
		gridSize = DAMAGE_COVERAGE_GRID_SIZE,
		words = {},
		allocatedWordCount = 0,
		triangleCount = 0,
		tiledTriangleCount = 0,
		largeTriangleCount = 0, -- retained for old debug-bundle readers
		paintCount = 0,
	}
end

local function BuildProjectedCoverageGrid( projectedTriangles, settings, job )
	local projectedTriangleCount = ProjectedTriangleCount( projectedTriangles )
	if projectedTriangleCount == 0 then return nil end
	local coverage = NewDamageCoverageGrid()
	coverage.expansion = settings and settings.expansion or 0
	coverage.feather = settings and settings.feather or 0
	local cpuSeconds = 0
	local sliceStarted = SysTime()
	local maximumSliceMilliseconds = 0
	local yieldCount = 0
	local function FinishSlice()
		local now = SysTime()
		local seconds = math.max( now - sliceStarted, 0 )
		cpuSeconds = cpuSeconds + seconds
		maximumSliceMilliseconds = math.max(
			maximumSliceMilliseconds, seconds * 1000 )
		return now
	end
	local function MaybeYieldCoverage()
		if not job or coverage.tiledTriangleCount % 8 ~= 0
		or SysTime() < ( job.paintDeadline or math.huge ) then return end
		FinishSlice()
		yieldCount = yieldCount + 1
		coroutine.yield( "cpu_coverage" )
		sliceStarted = SysTime()
	end
	for triangleIndex = 1, projectedTriangleCount do
		if job and triangleIndex % 32 == 0
		and SysTime() >= ( job.paintDeadline or math.huge ) then
			FinishSlice()
			yieldCount = yieldCount + 1
			coroutine.yield( "cpu_coverage" )
			sliceStarted = SysTime()
		end
		local firstU, firstV = ProjectedTriangleUV(
			projectedTriangles, triangleIndex, 1 )
		local secondU, secondV = ProjectedTriangleUV(
			projectedTriangles, triangleIndex, 2 )
		local thirdU, thirdV = ProjectedTriangleUV(
			projectedTriangles, triangleIndex, 3 )
		if isnumber( firstU ) and isnumber( firstV )
		and isnumber( secondU ) and isnumber( secondV )
		and isnumber( thirdU ) and isnumber( thirdV ) then
			local minimumU, maximumU = math.huge, -math.huge
			local minimumV, maximumV = math.huge, -math.huge
			local valid = firstU == firstU and firstV == firstV
				and secondU == secondU and secondV == secondV
				and thirdU == thirdU and thirdV == thirdV
				and math.abs( firstU ) <= 100000 and math.abs( firstV ) <= 100000
				and math.abs( secondU ) <= 100000 and math.abs( secondV ) <= 100000
				and math.abs( thirdU ) <= 100000 and math.abs( thirdV ) <= 100000
			if valid then
				minimumU = math.min( firstU, secondU, thirdU )
				maximumU = math.max( firstU, secondU, thirdU )
				minimumV = math.min( firstV, secondV, thirdV )
				maximumV = math.max( firstV, secondV, thirdV )
				coverage.triangleCount = coverage.triangleCount + 1
				local firstShiftU, lastShiftU =
					TileShiftRange( minimumU, maximumU )
				local firstShiftV, lastShiftV =
					TileShiftRange( minimumV, maximumV )
				for shiftU = firstShiftU, lastShiftU do
					for shiftV = firstShiftV, lastShiftV do
						local shiftedMinimumU = minimumU + shiftU
						local shiftedMaximumU = maximumU + shiftU
						local shiftedMinimumV = minimumV + shiftV
						local shiftedMaximumV = maximumV + shiftV
						if shiftedMaximumU >= 0 and shiftedMinimumU <= 1
						and shiftedMaximumV >= 0 and shiftedMinimumV <= 1 then
							coverage.tiledTriangleCount =
								coverage.tiledTriangleCount + 1
							RasterDamageCoverageTriangle( coverage,
								firstU + shiftU, firstV + shiftV,
								secondU + shiftU, secondV + shiftV,
								thirdU + shiftU, thirdV + shiftV )
							MaybeYieldCoverage()
						end
					end
				end
			end
		end
	end
	FinishSlice()
	return coverage, cpuSeconds * 1000, yieldCount, maximumSliceMilliseconds
end

local function AddProjectedCoverageToMask( mask, incoming, settings )
	if not mask or not incoming then return end
	local coverage = mask.damageCoverage
	if not coverage or coverage.format ~= 2 then
		coverage = NewDamageCoverageGrid()
		mask.damageCoverage = coverage
	end
	coverage.paintCount = coverage.paintCount + 1
	coverage.expansion = math.max( coverage.expansion or 0,
		settings and settings.expansion or 0 )
	coverage.feather = math.max( coverage.feather or 0,
		settings and settings.feather or 0 )
	coverage.triangleCount = coverage.triangleCount
		+ ( incoming.triangleCount or 0 )
	coverage.tiledTriangleCount = coverage.tiledTriangleCount
		+ ( incoming.tiledTriangleCount or 0 )
	for key, incomingBits in pairs( incoming.words or {} ) do
		local previous = coverage.words[ key ] or 0
		local updated = bit.bor( previous, incomingBits )
		if previous == 0 and updated ~= 0 then
			coverage.allocatedWordCount = coverage.allocatedWordCount + 1
		end
		coverage.words[ key ] = updated
	end
end

MaskHasDamageAtUV = function( mask, u, v )
	local coverage = mask and mask.damageCoverage
	if not coverage or coverage.format ~= 2
	or not isnumber( u ) or not isnumber( v )
	or u ~= u or v ~= v or math.abs( u ) > 100000
	or math.abs( v ) > 100000 then return false end
	local cellX, wrappedU = DamageCoverageCell( u )
	local cellY, wrappedV = DamageCoverageCell( v )
	local word = math.floor( cellX / DAMAGE_COVERAGE_WORD_BITS )
	local key = cellY * DAMAGE_COVERAGE_WORDS_PER_ROW + word + 1
	local bits = coverage.words and coverage.words[ key ] or 0
	return bit.band( bits,
		bit.lshift( 1, cellX % DAMAGE_COVERAGE_WORD_BITS ) ) ~= 0
end

local function WriteExpandedCorner( scratch, outputIndex,
	previousX, previousY, currentX, currentY, followingX, followingY, expansion )
	local incomingX, incomingY = currentX - previousX, currentY - previousY
	local outgoingX, outgoingY = followingX - currentX, followingY - currentY
	local incomingLength = math.sqrt( incomingX * incomingX + incomingY * incomingY )
	local outgoingLength = math.sqrt( outgoingX * outgoingX + outgoingY * outgoingY )
	if incomingLength < 0.0001 or outgoingLength < 0.0001 then return false end
	local point = scratch[ outputIndex ]
	point.x = currentX + incomingY / incomingLength * expansion
	point.y = currentY - incomingX / incomingLength * expansion
	point = scratch[ outputIndex + 1 ]
	point.x = currentX + outgoingY / outgoingLength * expansion
	point.y = currentY - outgoingX / outgoingLength * expansion
	return true
end

local function TrianglePolygon( projectedTriangles, triangleIndex,
	width, height, shiftU, shiftV, expansion, scratch )
	local firstU, firstV = ProjectedTriangleUV(
		projectedTriangles, triangleIndex, 1 )
	local secondU, secondV = ProjectedTriangleUV(
		projectedTriangles, triangleIndex, 2 )
	local thirdU, thirdV = ProjectedTriangleUV(
		projectedTriangles, triangleIndex, 3 )
	if not isnumber( firstU ) or not isnumber( firstV )
	or not isnumber( secondU ) or not isnumber( secondV )
	or not isnumber( thirdU ) or not isnumber( thirdV ) then return nil end
	local firstX, firstY = ( firstU + shiftU ) * width,
		( firstV + shiftV ) * height
	local secondX, secondY = ( secondU + shiftU ) * width,
		( secondV + shiftV ) * height
	local thirdX, thirdY = ( thirdU + shiftU ) * width,
		( thirdV + shiftV ) * height
	local signedArea = ( secondX - firstX ) * ( thirdY - firstY )
		- ( secondY - firstY ) * ( thirdX - firstX )
	if signedArea < 0 then
		secondX, thirdX = thirdX, secondX
		secondY, thirdY = thirdY, secondY
	end
	scratch = scratch or {
		{}, {}, {}, {}, {}, {},
	}
	if expansion <= 0 then
		scratch[ 1 ].x, scratch[ 1 ].y = firstX, firstY
		scratch[ 2 ].x, scratch[ 2 ].y = secondX, secondY
		scratch[ 3 ].x, scratch[ 3 ].y = thirdX, thirdY
		return scratch
	end

	-- Build the bevelled Minkowski outline directly into reusable point tables.
	-- surface.DrawPoly consumes them immediately, so no per-polygon allocation is
	-- required even when adaptive projection emits thousands of micro-triangles.
	if not WriteExpandedCorner( scratch, 1, thirdX, thirdY,
		firstX, firstY, secondX, secondY, expansion )
	or not WriteExpandedCorner( scratch, 3, firstX, firstY,
		secondX, secondY, thirdX, thirdY, expansion )
	or not WriteExpandedCorner( scratch, 5, secondX, secondY,
		thirdX, thirdY, firstX, firstY, expansion ) then return nil end
	return scratch
end

local function ForEachUVTrianglePolygon( projectedTriangles, triangleIndex,
	width, height, expansion, callback, scratch )
	local firstU, firstV = ProjectedTriangleUV(
		projectedTriangles, triangleIndex, 1 )
	local secondU, secondV = ProjectedTriangleUV(
		projectedTriangles, triangleIndex, 2 )
	local thirdU, thirdV = ProjectedTriangleUV(
		projectedTriangles, triangleIndex, 3 )
	BBS.MaterialSafety.RequireUVs( firstU, firstV, secondU, secondV, thirdU, thirdV )
	local minimumU = math.min( firstU, secondU, thirdU )
	local maximumU = math.max( firstU, secondU, thirdU )
	local minimumV = math.min( firstV, secondV, thirdV )
	local maximumV = math.max( firstV, secondV, thirdV )
	local marginU = expansion / width
	local marginV = expansion / height
	minimumU = minimumU - marginU
	maximumU = maximumU + marginU
	minimumV = minimumV - marginV
	maximumV = maximumV + marginV
	local firstU, lastU = TileShiftRange( minimumU, maximumU )
	local firstV, lastV = TileShiftRange( minimumV, maximumV )
	for shiftU = firstU, lastU do
		for shiftV = firstV, lastV do
			local polygon = TrianglePolygon( projectedTriangles, triangleIndex,
				width, height, shiftU, shiftV, expansion, scratch )
			if polygon then callback( polygon ) end
		end
	end
end

-- Stay far below Source's documented 65,535-vertex ceiling. Reaching that
-- native limit repeatedly on complex regions has produced process crashes with
-- no Lua traceback, so the experimental path flushes small bounded batches.
local MAX_DYNAMIC_MESH_TRIANGLES = 2048
-- A render target/cam block cannot remain open across a coroutine yield. Draw a
-- small bounded range, restore every render override, then yield between ranges
-- when the per-frame paint deadline has expired.
local DAMAGE_RASTER_SLICE_POLYGONS = 256
local damageRasterMaterial

local function DamageRasterMaterial()
	if damageRasterMaterial then return damageRasterMaterial end
	damageRasterMaterial = CreateMaterial(
		"bbs_damage_mask_raster_v" .. DAMAGE_MATERIAL_FORMAT, "UnlitGeneric", {
			[ "$basetexture" ] = "vgui/white",
			[ "$vertexcolor" ] = "1",
			[ "$vertexalpha" ] = "1",
			[ "$translucent" ] = "1",
			[ "$nocull" ] = "1",
			[ "$ignorez" ] = "1",
		} )
	return damageRasterMaterial
end

local function DrawProjectedCoverageLegacy( projectedTriangles, width, height,
	expansion, statistics, firstIndex, lastIndex )
	draw.NoTexture()
	surface.SetDrawColor( 255, 255, 255, 255 )
	local polygonScratch = expansion > 0
		and { {}, {}, {}, {}, {}, {} } or { {}, {}, {} }
	local function DrawPolygon( polygon )
		if statistics.writeGuard then
			BBS.MaterialSafety.AddWritePolygon( statistics.writeGuard, polygon )
		end
		statistics.polygonCount = statistics.polygonCount + 1
		statistics.primitiveCount = statistics.primitiveCount
			+ math.max( #polygon - 2, 0 )
		surface.DrawPoly( polygon )
	end
	local triangleCount = ProjectedTriangleCount( projectedTriangles )
	firstIndex = math.max( math.floor( tonumber( firstIndex ) or 1 ), 1 )
	lastIndex = math.min( math.floor( tonumber( lastIndex )
		or triangleCount ), triangleCount )
	for index = firstIndex, lastIndex do
		ForEachUVTrianglePolygon( projectedTriangles, index,
			width, height, expansion,
			DrawPolygon, polygonScratch )
	end
end

local function DrawProjectedCoverageBatched( projectedTriangles, width, height,
	expansion, statistics, meshState, firstIndex, lastIndex )
	local vertices = {}
	local vertexValueCount = 0
	local primitiveCount = 0

	local function AppendPoint( point )
		vertexValueCount = vertexValueCount + 1
		vertices[ vertexValueCount ] = point.x
		vertexValueCount = vertexValueCount + 1
		vertices[ vertexValueCount ] = point.y
	end

	local function Flush()
		if primitiveCount <= 0 then return end
		render.SetMaterial( DamageRasterMaterial() )
		mesh.Begin( MATERIAL_TRIANGLES, primitiveCount )
		meshState.open = true
		for index = 1, vertexValueCount, 2 do
			-- The numeric overload avoids allocating or mutating a Vector for every
			-- emitted mask vertex.
			mesh.Position( vertices[ index ], vertices[ index + 1 ], 0 )
			mesh.Color( 255, 255, 255, 255 )
			mesh.AdvanceVertex()
		end
		mesh.End()
		meshState.open = false
		statistics.batchCount = statistics.batchCount + 1
		vertices = {}
		vertexValueCount = 0
		primitiveCount = 0
	end

	local function AppendPolygon( polygon )
		if statistics.writeGuard then
			BBS.MaterialSafety.AddWritePolygon( statistics.writeGuard, polygon )
		end
		local polygonPrimitiveCount = #polygon - 2
		if polygonPrimitiveCount <= 0 then return end
		if primitiveCount + polygonPrimitiveCount
		> MAX_DYNAMIC_MESH_TRIANGLES then Flush() end
		local first = polygon[ 1 ]
		for index = 2, #polygon - 1 do
			AppendPoint( first )
			AppendPoint( polygon[ index ] )
			AppendPoint( polygon[ index + 1 ] )
		end
		primitiveCount = primitiveCount + polygonPrimitiveCount
		statistics.polygonCount = statistics.polygonCount + 1
		statistics.primitiveCount = statistics.primitiveCount
			+ polygonPrimitiveCount
	end

	local polygonScratch = expansion > 0
		and { {}, {}, {}, {}, {}, {} } or { {}, {}, {} }
	local triangleCount = ProjectedTriangleCount( projectedTriangles )
	firstIndex = math.max( math.floor( tonumber( firstIndex ) or 1 ), 1 )
	lastIndex = math.min( math.floor( tonumber( lastIndex )
		or triangleCount ), triangleCount )
	for index = firstIndex, lastIndex do
		ForEachUVTrianglePolygon( projectedTriangles, index,
			width, height, expansion,
			AppendPolygon, polygonScratch )
	end
	Flush()
end

local function DrawProjectedCoverage( projectedTriangles, width, height,
	expansion, batchRequested, statistics, firstIndex, lastIndex )
	statistics = statistics or {
		mode = batchRequested and "mesh-batched" or "surface-legacy",
		polygonCount = 0,
		primitiveCount = 0,
		batchCount = 0,
	}
	if not batchRequested then
		DrawProjectedCoverageLegacy( projectedTriangles, width, height,
			expansion, statistics, firstIndex, lastIndex )
		return statistics
	end
	if not mesh or not mesh.Begin or not mesh.End or not mesh.Position
	or not mesh.Color or not mesh.AdvanceVertex then
		statistics.mode = "surface-fallback"
		statistics.fallbackError = "dynamic mesh API is unavailable"
		DrawProjectedCoverageLegacy( projectedTriangles, width, height,
			expansion, statistics, firstIndex, lastIndex )
		return statistics
	end

	local meshState = { open = false }
	local polygonCount = statistics.polygonCount
	local primitiveCount = statistics.primitiveCount
	local batchCount = statistics.batchCount
	local ok, errorMessage = pcall( DrawProjectedCoverageBatched,
		projectedTriangles, width, height, expansion, statistics, meshState,
		firstIndex, lastIndex )
	if ok then return statistics end
	if meshState.open then pcall( mesh.End ) end
	-- Coverage uses overwrite-white blending. Redrawing the complete legacy
	-- geometry is therefore safe even if one or more batches finished before
	-- the failure; it produces the same union instead of double-applying alpha.
	statistics.mode = "surface-fallback"
	statistics.fallbackError = tostring( errorMessage )
	statistics.polygonCount = polygonCount
	statistics.primitiveCount = primitiveCount
	statistics.batchCount = batchCount
	if not BBS.DamageBatchRasterWarningPrinted then
		BBS.DamageBatchRasterWarningPrinted = true
		BBS.Log( "  batched UV raster failed; using surface.DrawPoly: %s",
			statistics.fallbackError )
	end
	DrawProjectedCoverageLegacy( projectedTriangles, width, height,
		expansion, statistics, firstIndex, lastIndex )
	return statistics
end

local function ProjectedTriangleTileCost( projectedTriangles, triangleIndex,
	width, height, expansion )
	local firstU, firstV = ProjectedTriangleUV(
		projectedTriangles, triangleIndex, 1 )
	local secondU, secondV = ProjectedTriangleUV(
		projectedTriangles, triangleIndex, 2 )
	local thirdU, thirdV = ProjectedTriangleUV(
		projectedTriangles, triangleIndex, 3 )
	BBS.MaterialSafety.RequireUVs( firstU, firstV, secondU, secondV, thirdU, thirdV )
	local marginU = expansion / math.max( width, 1 )
	local marginV = expansion / math.max( height, 1 )
	local firstShiftU, lastShiftU = TileShiftRange(
		math.min( firstU, secondU, thirdU ) - marginU,
		math.max( firstU, secondU, thirdU ) + marginU )
	local firstShiftV, lastShiftV = TileShiftRange(
		math.min( firstV, secondV, thirdV ) - marginV,
		math.max( firstV, secondV, thirdV ) + marginV )
	return math.max( lastShiftU - firstShiftU + 1, 1 )
		* math.max( lastShiftV - firstShiftV + 1, 1 )
end

local function DamageSmoothingSettings()
	return {
		expansion = math.Clamp( GetFloat( "bbs_damage_uv_expand_pixels", 1 ), 0, 64 ),
		feather = math.Clamp( GetFloat( "bbs_damage_uv_feather_pixels", 0 ), 0, 32 ),
		blurPasses = math.Clamp( GetInt( "bbs_damage_uv_blur_passes", 2 ), 0, 16 ),
		unwrapSeams = GetBool( "bbs_damage_uv_unwrap_seams", true ),
		projectionDepth = math.Clamp(
			GetInt( "bbs_damage_projection_depth", 4 ), 0, 8 ),
		projectionTolerance = math.Clamp(
			GetFloat( "bbs_damage_projection_tolerance", 0.04 ), 0.001, 2 ),
		projectionMaxTriangles = math.Clamp(
			GetInt( "bbs_damage_projection_max_triangles", 16384 ), 256, 16384 ),
		projectionLocalBounds = GetBool(
			"bbs_damage_projection_local_bounds", true ),
		batchRaster = GetBool( "bbs_damage_batch_raster", false ),
	}
end

local function BuildProjectionCylinder( hit )
	local hull = hit and hit.hullParameters or nil
	local surfacePosition = hit and hit.surfacePosition or nil
	local hitDirection = hit and hit.direction or nil
	local surfaceNormal = hit and hit.normal or nil
	if not hull or not isvector( surfacePosition ) or not isvector( hitDirection )
	or hitDirection:IsZero() then return nil, "missing captured removal-hull frame" end
	if BBS.BuildRemovalHullFrame then
		local frame = BBS.BuildRemovalHullFrame(
			surfacePosition, hitDirection, surfaceNormal, hull )
		if frame then return frame end
	end
	return nil, "irregular removal-hull frame could not be built"
end

-- Adaptive projection works entirely in the captured hull's orthonormal frame.
-- Subdivision is affine, so interpolating these three scalars is equivalent to
-- interpolating world Vectors and then taking three Dot products, without the
-- thousands of temporary Vector allocations that a detailed hit used to make.
local function ProjectionAtan2( y, x )
	if math.atan2 then return math.atan2( y, x ) end
	if x > 0 then return math.atan( y / x ) end
	if x < 0 then return math.atan( y / x ) + ( y >= 0 and math.pi or -math.pi ) end
	if y > 0 then return math.pi * 0.5 end
	if y < 0 then return -math.pi * 0.5 end
	return 0
end

local function ProjectionHullRadius( cylinder, radians )
	if BBS.RemovalHullRadiusAtAngle then
		return BBS.RemovalHullRadiusAtAngle( cylinder, radians )
	end
	return cylinder.maximumRadius or cylinder.minimumRadius or 0.05
end

local function ProjectionCoordinateVertex( cylinder, axial, radialX, radialY,
	u, v, output )
	local radial = math.sqrt( radialX * radialX + radialY * radialY )
	local angle = ProjectionAtan2( radialY, radialX )
	local boundaryRadius = ProjectionHullRadius( cylinder, angle )
	local axialValue = math.max( axial - cylinder.insideDistance,
		-cylinder.outsideDistance - axial )
	output = output or {}
	output.axial = axial
	output.radialX = radialX
	output.radialY = radialY
	output.radial = radial
	output.boundaryRadius = boundaryRadius
	output.distance = math.max( radial - boundaryRadius, axialValue )
	output.u = u
	output.v = v
	return output
end

local function AcquireProjectionCoordinateVertex( state, cylinder,
	axial, radialX, radialY, u, v )
	local index = ( state.projectionVertexPoolTop or 0 ) + 1
	state.projectionVertexPoolTop = index
	local output = state.projectionVertexPool[ index ]
	if not output then
		output = {}
		state.projectionVertexPool[ index ] = output
	end
	return ProjectionCoordinateVertex(
		cylinder, axial, radialX, radialY, u, v, output )
end

local function ReleaseProjectionVertices( state, marker )
	state.projectionVertexPoolTop = marker or 0
end

local function ProjectionVertex( state, cylinder, world, u, v )
	local origin, axis, right, up = cylinder.origin, cylinder.axis,
		cylinder.right, cylinder.up
	local dx = world.x - origin.x
	local dy = world.y - origin.y
	local dz = world.z - origin.z
	return AcquireProjectionCoordinateVertex( state, cylinder,
		dx * axis.x + dy * axis.y + dz * axis.z,
		dx * right.x + dy * right.y + dz * right.z,
		dx * up.x + dy * up.y + dz * up.z, u, v )
end

local function ProjectionMidpoint( state, cylinder, first, second )
	return AcquireProjectionCoordinateVertex( state, cylinder,
		( first.axial + second.axial ) * 0.5,
		( first.radialX + second.radialX ) * 0.5,
		( first.radialY + second.radialY ) * 0.5,
		( first.u + second.u ) * 0.5,
		( first.v + second.v ) * 0.5 )
end

local function ProjectionCentroid( state, cylinder, first, second, third )
	return AcquireProjectionCoordinateVertex( state, cylinder,
		( first.axial + second.axial + third.axial ) / 3,
		( first.radialX + second.radialX + third.radialX ) / 3,
		( first.radialY + second.radialY + third.radialY ) / 3,
		( first.u + second.u + third.u ) / 3,
		( first.v + second.v + third.v ) / 3 )
end

local function ProjectionCellVertexBounds( center, vertex )
	local axial = vertex.axial - center.axial
	local radialX = vertex.radialX - center.radialX
	local radialY = vertex.radialY - center.radialY
	local radialSquared = radialX * radialX + radialY * radialY
	return radialSquared + axial * axial, radialSquared
end

local function ProjectionCellBounds( center, first, second, third )
	local firstSquared, firstRadialSquared =
		ProjectionCellVertexBounds( center, first )
	local secondSquared, secondRadialSquared =
		ProjectionCellVertexBounds( center, second )
	local thirdSquared, thirdRadialSquared =
		ProjectionCellVertexBounds( center, third )
	return math.sqrt( math.max( firstSquared, secondSquared, thirdSquared ) ),
		math.sqrt( math.max( firstRadialSquared,
			secondRadialSquared, thirdRadialSquared ) )
end

-- The stored polar samples form a continuous piecewise-linear radius function.
-- maximumAngularSlope is therefore a global Lipschitz constant in radius per
-- radian. A radial-plane disk not containing the axis spans at most asin(b/r)
-- radians, which gives much tighter local radius bounds than the global tear
-- extrema while remaining conservative across sample boundaries and UV seams.
local function ProjectionCellRadiusBounds( state, cylinder, center, radialBound )
	local globalMinimum = cylinder.minimumRadius
	local globalMaximum = cylinder.maximumRadius
	if not state.useLocalRadiusBounds then
		state.globalAngularBoundCellCount = state.globalAngularBoundCellCount + 1
		return globalMinimum, globalMaximum
	end
	local slope = cylinder.maximumAngularSlope or 0
	if slope <= 0 then
		state.angularBoundCellCount = state.angularBoundCellCount + 1
		return center.boundaryRadius, center.boundaryRadius
	end
	if center.radial <= radialBound + 0.0000001 then
		state.globalAngularBoundCellCount = state.globalAngularBoundCellCount + 1
		return globalMinimum, globalMaximum
	end
	local angularDeviation = math.asin( math.Clamp(
		radialBound / center.radial, 0, 1 ) )
	state.angularBoundCellCount = state.angularBoundCellCount + 1
	state.maximumAngularDeviation = math.max(
		state.maximumAngularDeviation, angularDeviation )
	local variation = slope * angularDeviation
	return math.max( globalMinimum, center.boundaryRadius - variation ),
		math.min( globalMaximum, center.boundaryRadius + variation )
end

local function ProjectionBoundaryUV( first, second )
	local denominator = first.distance - second.distance
	local fraction = math.abs( denominator ) > 0.0000001
		and math.Clamp( first.distance / denominator, 0, 1 ) or 0.5
	return first.u + ( second.u - first.u ) * fraction,
		first.v + ( second.v - first.v ) * fraction
end

local function AppendProjectedUVTriangle( state,
	firstU, firstV, secondU, secondV, thirdU, thirdV )
	if state.projectedTriangleCount >= state.maximumTriangles then
		state.capped = true
		return false
	end
	local area = ( secondU - firstU ) * ( thirdV - firstV )
		- ( secondV - firstV ) * ( thirdU - firstU )
	if math.abs( area ) <= 0.000000000001 then
		state.degenerateTriangleCount = state.degenerateTriangleCount + 1
		return true
	end
	local output = state.projectedTriangles
	local offset = #output
	output[ offset + 1 ] = firstU
	output[ offset + 2 ] = firstV
	output[ offset + 3 ] = secondU
	output[ offset + 4 ] = secondV
	output[ offset + 5 ] = thirdU
	output[ offset + 6 ] = thirdV
	state.projectedTriangleCount = state.projectedTriangleCount + 1
	return true
end

local function AppendProjectedTriangle( state, first, second, third )
	return AppendProjectedUVTriangle( state,
		first.u, first.v, second.u, second.v, third.u, third.v )
end

-- On the smallest adaptive cells the curved signed-distance boundary is
-- linearized, then clipped with Sutherland-Hodgman in barycentric UV space.
local function ClipProjectionCell( state, first, second, third )
	if state.capped then return end
	local firstInside = first.distance <= 0
	local secondInside = second.distance <= 0
	local thirdInside = third.distance <= 0
	local insideCount = ( firstInside and 1 or 0 )
		+ ( secondInside and 1 or 0 ) + ( thirdInside and 1 or 0 )
	if insideCount == 0 then return end
	if insideCount == 3 then
		AppendProjectedTriangle( state, first, second, third )
		return
	end

	local firstSecondU, firstSecondV = ProjectionBoundaryUV( first, second )
	local secondThirdU, secondThirdV = ProjectionBoundaryUV( second, third )
	local thirdFirstU, thirdFirstV = ProjectionBoundaryUV( third, first )
	if insideCount == 1 then
		if firstInside then
			AppendProjectedUVTriangle( state,
				thirdFirstU, thirdFirstV, first.u, first.v,
				firstSecondU, firstSecondV )
		elseif secondInside then
			AppendProjectedUVTriangle( state,
				firstSecondU, firstSecondV, second.u, second.v,
				secondThirdU, secondThirdV )
		else
			AppendProjectedUVTriangle( state,
				secondThirdU, secondThirdV, third.u, third.v,
				thirdFirstU, thirdFirstV )
		end
		return
	end

	-- One vertex lies outside, producing a clipped quad. Emit its two fan
	-- triangles directly instead of allocating Sutherland-Hodgman arrays.
	if not firstInside then
		if not AppendProjectedUVTriangle( state,
			thirdFirstU, thirdFirstV, firstSecondU, firstSecondV,
			second.u, second.v ) then return end
		AppendProjectedUVTriangle( state,
			thirdFirstU, thirdFirstV, second.u, second.v, third.u, third.v )
	elseif not secondInside then
		if not AppendProjectedUVTriangle( state,
			first.u, first.v, firstSecondU, firstSecondV,
			secondThirdU, secondThirdV ) then return end
		AppendProjectedUVTriangle( state,
			first.u, first.v, secondThirdU, secondThirdV, third.u, third.v )
	else
		if not AppendProjectedUVTriangle( state,
			first.u, first.v, second.u, second.v,
			secondThirdU, secondThirdV ) then return end
		AppendProjectedUVTriangle( state,
			first.u, first.v, secondThirdU, secondThirdV,
			thirdFirstU, thirdFirstV )
	end
end

local function FinalizeProjectionCell( state, cylinder, first, second, third, center )
	local poolMarker = state.projectionVertexPoolTop or 0
	state.boundaryCellCount = state.boundaryCellCount + 1
	center = center or ProjectionCentroid( state, cylinder, first, second, third )
	local firstSecond = ProjectionMidpoint( state, cylinder, first, second )
	local secondThird = ProjectionMidpoint( state, cylinder, second, third )
	local thirdFirst = ProjectionMidpoint( state, cylinder, third, first )
	ClipProjectionCell( state, first, firstSecond, center )
	ClipProjectionCell( state, firstSecond, second, center )
	ClipProjectionCell( state, second, secondThird, center )
	ClipProjectionCell( state, secondThird, third, center )
	ClipProjectionCell( state, third, thirdFirst, center )
	ClipProjectionCell( state, thirdFirst, first, center )
	ReleaseProjectionVertices( state, poolMarker )
end

-- Emergency terminal used only when even the depth-zero high-quality bound
-- would exceed the allocation budget. It samples the same center and edge
-- midpoints, but emits at most one UV triangle per source triangle.
local function FinalizeCoarseProjectionCell( state, cylinder,
	first, second, third, center )
	local poolMarker = state.projectionVertexPoolTop or 0
	state.boundaryCellCount = state.boundaryCellCount + 1
	center = center or ProjectionCentroid( state, cylinder, first, second, third )
	local firstSecond = ProjectionMidpoint( state, cylinder, first, second )
	local secondThird = ProjectionMidpoint( state, cylinder, second, third )
	local thirdFirst = ProjectionMidpoint( state, cylinder, third, first )
	if math.min( first.distance, second.distance, third.distance,
		center.distance, firstSecond.distance, secondThird.distance,
		thirdFirst.distance ) <= 0 then
		AppendProjectedTriangle( state, first, second, third )
	end
	ReleaseProjectionVertices( state, poolMarker )
end

local function MaybeYieldUVProjection( state, forceCheck )
	local job = state and state.job
	if not job then return end
	state.yieldCheckCounter = ( state.yieldCheckCounter or 0 ) + 1
	if not forceCheck and state.yieldCheckCounter % 16 ~= 0 then return end
	local now = SysTime()
	if now < ( job.paintDeadline or math.huge ) then return end
	local sliceStarted = state.projectionSliceStarted or now
	local sliceSeconds = math.max( now - sliceStarted, 0 )
	state.projectionCPUSeconds = ( state.projectionCPUSeconds or 0 ) + sliceSeconds
	state.maximumSliceMilliseconds = math.max(
		state.maximumSliceMilliseconds or 0, sliceSeconds * 1000 )
	state.yieldCount = ( state.yieldCount or 0 ) + 1
	coroutine.yield( "uv_projection" )
	state.projectionSliceStarted = SysTime()
end

local function ProjectTriangleCell( state, cylinder, first, second, third, depth,
	bound, radialBound )
	if state.capped then return end
	state.visitedCellCount = state.visitedCellCount + 1
	MaybeYieldUVProjection( state, false )
	local poolMarker = state.projectionVertexPoolTop or 0
	state.maximumDepthReached = math.max( state.maximumDepthReached, depth )
	local axialMinimum = math.min( first.axial, second.axial, third.axial )
	local axialMaximum = math.max( first.axial, second.axial, third.axial )
	-- Cap rejection is scalar and exact for the whole cell. Avoid centroid,
	-- square-root, angle, and irregular-radius work for geometry outside the
	-- finite cylinder's axial slab.
	if axialMinimum > cylinder.insideDistance
	or axialMaximum < -cylinder.outsideDistance then
		state.outsideCellCount = state.outsideCellCount + 1
		return
	end
	local center = ProjectionCentroid( state, cylinder, first, second, third )
	if not bound or not radialBound then
		bound, radialBound = ProjectionCellBounds( center, first, second, third )
	end
	local radialMinimum = math.max( center.radial - radialBound, 0 )
	local radialMaximum = center.radial + radialBound
	-- The radial-plane bound is strictly tighter than the full hull-space bound
	-- whenever a triangle has appreciable axial extent.
	local localMinimumRadius, localMaximumRadius = ProjectionCellRadiusBounds(
		state, cylinder, center, radialBound )
	if radialMinimum > localMaximumRadius then
		state.outsideCellCount = state.outsideCellCount + 1
		ReleaseProjectionVertices( state, poolMarker )
		return
	end
	-- The conservative lower radius bound is guaranteed inside every angle
	-- spanned by this cell. A cell contained by it and both caps can therefore
	-- be accepted without assuming the irregular outline is convex.
	if axialMinimum >= -cylinder.outsideDistance
	and axialMaximum <= cylinder.insideDistance
	and radialMaximum <= localMinimumRadius then
		state.insideCellCount = state.insideCellCount + 1
		AppendProjectedTriangle( state, first, second, third )
		ReleaseProjectionVertices( state, poolMarker )
		return
	end
	if depth >= state.maximumDepth or bound <= state.tolerance then
		if state.coarseTerminal then
			FinalizeCoarseProjectionCell(
				state, cylinder, first, second, third, center )
		else
			FinalizeProjectionCell( state, cylinder, first, second, third, center )
		end
		ReleaseProjectionVertices( state, poolMarker )
		return
	end

	local firstSecond = ProjectionMidpoint( state, cylinder, first, second )
	local secondThird = ProjectionMidpoint( state, cylinder, second, third )
	local thirdFirst = ProjectionMidpoint( state, cylinder, third, first )
	local childBound = bound * 0.5
	local childRadialBound = radialBound * 0.5
	ProjectTriangleCell( state, cylinder,
		first, firstSecond, thirdFirst, depth + 1, childBound, childRadialBound )
	ProjectTriangleCell( state, cylinder,
		firstSecond, second, secondThird, depth + 1, childBound, childRadialBound )
	ProjectTriangleCell( state, cylinder,
		thirdFirst, secondThird, third, depth + 1, childBound, childRadialBound )
	ProjectTriangleCell( state, cylinder,
		firstSecond, secondThird, thirdFirst, depth + 1, childBound, childRadialBound )
	ReleaseProjectionVertices( state, poolMarker )
end

local function BuildCylinderProjectedUVTriangles( mask, triangles, hit, settings,
	collectDetailedDiagnostics, job )
	local cylinder, cylinderError = BuildProjectionCylinder( hit )
	local state = {
		projectedTriangles = {},
		projectedTriangleCount = 0,
		sourceTriangleCount = #triangles,
		missedSourceTriangleCount = 0,
		missingWorldTriangleCount = 0,
		degenerateTriangleCount = 0,
		visitedCellCount = 0,
		insideCellCount = 0,
		outsideCellCount = 0,
		boundaryCellCount = 0,
		maximumDepthReached = 0,
		angularBoundCellCount = 0,
		globalAngularBoundCellCount = 0,
		maximumAngularDeviation = 0,
		seamTriangleCount = 0,
		maximumRawUSpan = 0,
		maximumRawVSpan = 0,
		maximumRasterUSpan = 0,
		maximumRasterVSpan = 0,
		maximumDepth = settings.projectionDepth,
		tolerance = settings.projectionTolerance,
		maximumTriangles = settings.projectionMaxTriangles,
		coarseTerminal = settings.projectionCoarseTerminal or false,
		useLocalRadiusBounds = settings.projectionLocalBounds,
		capped = false,
		error = cylinderError,
		job = job,
		projectionCPUSeconds = 0,
		projectionSliceStarted = SysTime(),
		yieldCount = 0,
		maximumSliceMilliseconds = 0,
		projectionVertexPool = {},
		projectionVertexPoolTop = 0,
	}
	local function FinishProjectionCPU()
		local now = SysTime()
		local sliceSeconds = math.max(
			now - ( state.projectionSliceStarted or now ), 0 )
		state.projectionCPUSeconds = state.projectionCPUSeconds + sliceSeconds
		state.maximumSliceMilliseconds = math.max(
			state.maximumSliceMilliseconds, sliceSeconds * 1000 )
		state.projectionSliceStarted = now
	end
	if not cylinder then
		FinishProjectionCPU()
		return state.projectedTriangles, state
	end
	local shape = cylinder.parameters or {}
	state.shapeSeed = shape.seed
	state.shapeSampleCount = shape.shapeSamples or 0
	state.shapeTearCount = shape.tearCount or 0
	state.shapeIrregularity = shape.irregularity or 0
	state.shapeDamageMultiplier = shape.damageMultiplier or 1
	state.shapeMinimumRadius = cylinder.minimumRadius
	state.shapeNominalRadius = shape.radius or cylinder.maximumRadius
	state.shapeMaximumRadius = cylinder.maximumRadius
	state.maximumAngularSlope = cylinder.maximumAngularSlope or 0

	for _, triangle in ipairs( triangles ) do
		if state.capped then break end
		MaybeYieldUVProjection( state, true )
		local firstU, firstV, secondU, secondV, thirdU, thirdV,
			seamChanged, rawUSpan, rawVSpan, rasterUSpan, rasterVSpan =
			TransformAndUnwrapUVTriangle(
				triangle.uv or triangle.sourceVertices,
				mask.baseTextureTransform, settings.unwrapSeams )
		if collectDetailedDiagnostics then
			state.maximumRawUSpan = math.max(
				state.maximumRawUSpan, rawUSpan or 0 )
			state.maximumRawVSpan = math.max(
				state.maximumRawVSpan, rawVSpan or 0 )
		end
		if seamChanged then state.seamTriangleCount = state.seamTriangleCount + 1 end
		if collectDetailedDiagnostics then
			state.maximumRasterUSpan = math.max(
				state.maximumRasterUSpan, rasterUSpan or 0 )
			state.maximumRasterVSpan = math.max(
				state.maximumRasterVSpan, rasterVSpan or 0 )
		end

		local world = triangle.world
		local sourceVertices = triangle.sourceVertices
		local firstWorld = world and world[ 1 ]
			or sourceVertices and sourceVertices[ 1 ]
				and sourceVertices[ 1 ].worldPosition
		local secondWorld = world and world[ 2 ]
			or sourceVertices and sourceVertices[ 2 ]
				and sourceVertices[ 2 ].worldPosition
		local thirdWorld = world and world[ 3 ]
			or sourceVertices and sourceVertices[ 3 ]
				and sourceVertices[ 3 ].worldPosition
		if not isvector( firstWorld ) or not isvector( secondWorld )
		or not isvector( thirdWorld ) or not firstU then
			state.missingWorldTriangleCount = state.missingWorldTriangleCount + 1
		else
			local before = state.projectedTriangleCount
			local poolMarker = state.projectionVertexPoolTop or 0
			local first = ProjectionVertex( state, cylinder, firstWorld,
				firstU, firstV )
			local second = ProjectionVertex( state, cylinder, secondWorld,
				secondU, secondV )
			local third = ProjectionVertex( state, cylinder, thirdWorld,
				thirdU, thirdV )
			ProjectTriangleCell( state, cylinder, first, second, third, 0 )
			ReleaseProjectionVertices( state, poolMarker )
			if state.projectedTriangleCount == before then
				state.missedSourceTriangleCount = state.missedSourceTriangleCount + 1
			end
		end
	end
	FinishProjectionCPU()
	return state.projectedTriangles, state
end

-- A terminal boundary cell can emit at most twelve clipped triangles: six
-- center/edge sectors, each clipped convex triangle producing at most two.
-- Choose one effective depth before allocating output, making the configured
-- cap a conservative workload budget instead of an after-the-fact failure.
local PROJECTION_TRIANGLES_PER_TERMINAL_CELL = 12
local function ProjectionDepthForWorkload( sourceTriangleCount,
	requestedDepth, maximumTriangles )
	sourceTriangleCount = math.max( math.floor(
		tonumber( sourceTriangleCount ) or 0 ), 0 )
	requestedDepth = math.max( math.floor( tonumber( requestedDepth ) or 0 ), 0 )
	maximumTriangles = math.max( math.floor(
		tonumber( maximumTriangles ) or 1 ), 1 )
	if sourceTriangleCount == 0 then
		return requestedDepth, 0, false, false
	end

	local upperBound = sourceTriangleCount
		* PROJECTION_TRIANGLES_PER_TERMINAL_CELL
	if upperBound > maximumTriangles then
		-- Depth zero's detailed six-sector finalizer cannot be guaranteed to fit.
		-- The coarse terminal is still shape-tested and has a strict one-output-
		-- triangle-per-source upper bound.
		return 0, sourceTriangleCount, true, true
	end

	local effectiveDepth = 0
	while effectiveDepth < requestedDepth
	and upperBound <= maximumTriangles / 4 do
		effectiveDepth = effectiveDepth + 1
		upperBound = upperBound * 4
	end
	return effectiveDepth, upperBound,
		effectiveDepth < requestedDepth, false
end

local function PaintTriangles( mask, triangles, captureCoverage, hit, job )
	local started = SysTime()
	local settings = DamageSmoothingSettings()
	local collectDetailedDiagnostics = captureCoverage
		or GetBool( "bbs_debug_console", false )
		or GetBool( "bbs_debug_hud", false )
		or GetBool( "bbs_damage_uv_preview", false )
	local projectionStarted = SysTime()
	local requestedProjectionDepth = settings.projectionDepth
	local projectionUpperBound
	local projectionBudgetLimited
	local projectionCoarseTerminal
	settings.projectionDepth, projectionUpperBound, projectionBudgetLimited,
		projectionCoarseTerminal = ProjectionDepthForWorkload(
			#triangles, requestedProjectionDepth, settings.projectionMaxTriangles )
	settings.projectionCoarseTerminal = projectionCoarseTerminal
	local projectionRetryCount = 0
	local projectedTriangles, projection = BuildCylinderProjectedUVTriangles(
		mask, triangles, hit, settings, collectDetailedDiagnostics, job )
	local discardedCappedProjection = projection.capped
	if discardedCappedProjection then
		-- Do not synchronously rebuild the entire micro-triangle set at successively
		-- lower depths. On a complex region those retries multiply CPU and temporary
		-- memory precisely when the limit is trying to protect the game. Discard
		-- atomically and leave the current material untouched.
		projectedTriangles = {}
		projection.projectedTriangles = projectedTriangles
		projection.projectedTriangleCount = 0
		projection.error = projection.error
			or "projected UV triangle cap exceeded; partial coverage discarded without retry"
		if GetBool( "bbs_debug_console", false ) then
			BBS.Log( "  UV projection safety cap reached for %s: limit=%d depth=%d; material damage skipped",
				tostring( mask.originalPath ), projection.maximumTriangles or 0,
				projection.maximumDepth or 0 )
		end
	end
	local projectionWallMilliseconds = ( SysTime() - projectionStarted ) * 1000
	local projectionMilliseconds = ( projection.projectionCPUSeconds or 0 ) * 1000
	local debugCaptureMilliseconds = 0
	local diagnostics = {
		expansion = settings.expansion,
		feather = settings.feather,
		blurPasses = settings.blurPasses,
		unwrapSeams = settings.unwrapSeams,
		triangleCount = #triangles,
		projectedTriangleCount = projection.projectedTriangleCount,
		projectionMilliseconds = projectionMilliseconds,
		projectionWallMilliseconds = projectionWallMilliseconds,
		projectionYieldCount = projection.yieldCount or 0,
		projectionMaximumSliceMilliseconds =
			projection.maximumSliceMilliseconds or projectionMilliseconds,
		projectionDepth = projection.maximumDepth,
		projectionRequestedDepth = requestedProjectionDepth,
		projectionBudgetLimited = projectionBudgetLimited,
		projectionConservativeUpperBound = projectionUpperBound,
		projectionCoarseTerminal = projectionCoarseTerminal,
		projectionRetryCount = projectionRetryCount,
		projectionDiscardedAtCap = discardedCappedProjection,
		projectionMaximumDepthReached = projection.maximumDepthReached,
		projectionTolerance = projection.tolerance,
		projectionMaximumTriangles = projection.maximumTriangles,
		projectionLocalBounds = projection.useLocalRadiusBounds,
		projectionAngularBoundCellCount = projection.angularBoundCellCount,
		projectionGlobalAngularBoundCellCount =
			projection.globalAngularBoundCellCount,
		projectionMaximumAngularDeviation = projection.maximumAngularDeviation,
		projectionMaximumAngularSlope = projection.maximumAngularSlope,
		projectionCapped = projection.capped,
		projectionError = projection.error,
		shapeSeed = projection.shapeSeed,
		shapeSampleCount = projection.shapeSampleCount,
		shapeTearCount = projection.shapeTearCount,
		shapeIrregularity = projection.shapeIrregularity,
		shapeDamageMultiplier = projection.shapeDamageMultiplier,
		shapeMinimumRadius = projection.shapeMinimumRadius,
		shapeNominalRadius = projection.shapeNominalRadius,
		shapeMaximumRadius = projection.shapeMaximumRadius,
		projectionVisitedCellCount = projection.visitedCellCount,
		projectionInsideCellCount = projection.insideCellCount,
		projectionOutsideCellCount = projection.outsideCellCount,
		projectionBoundaryCellCount = projection.boundaryCellCount,
		projectionMissedSourceTriangleCount = projection.missedSourceTriangleCount,
		projectionMissingWorldTriangleCount = projection.missingWorldTriangleCount,
		projectionDegenerateTriangleCount = projection.degenerateTriangleCount,
		seamTriangleCount = projection.seamTriangleCount,
		maximumRawUSpan = projection.maximumRawUSpan,
		maximumRawVSpan = projection.maximumRawVSpan,
		maximumRasterUSpan = projection.maximumRasterUSpan,
		maximumRasterVSpan = projection.maximumRasterVSpan,
		projectedTriangles = projectedTriangles,
	}
	local projectedTriangleCount = ProjectedTriangleCount( projectedTriangles )
	if projectedTriangleCount == 0 then
		diagnostics.rasterMilliseconds = 0
		diagnostics.blurMilliseconds = 0
		diagnostics.alphaCompositeMilliseconds = 0
		diagnostics.coverageBuildMilliseconds = 0
		diagnostics.coverageCommitMilliseconds = 0
		diagnostics.paintWallMilliseconds = ( SysTime() - started ) * 1000
		diagnostics.paintMilliseconds = projectionMilliseconds
		diagnostics.debugCaptureMilliseconds = 0
		mask.lastPaintDiagnostics = diagnostics
		return diagnostics
	end
	if job and SysTime() >= ( job.paintDeadline or math.huge ) then
		coroutine.yield( "uv_projection_complete" )
	end

	-- Finite visual-layer queries need a CPU mirror of alpha holes. Build the
	-- bounded delta before touching render state, allowing a large projection to
	-- yield safely; it is merged only after the GPU composite succeeds.
	local coverageDelta
	local coverageBuildMilliseconds, coverageYieldCount,
		coverageMaximumSliceMilliseconds = 0, 0, 0
	if math.max( tonumber( hit and hit.damageLayerLimit ) or 0, 0 ) > 0 then
		coverageDelta, coverageBuildMilliseconds, coverageYieldCount,
			coverageMaximumSliceMilliseconds = BuildProjectedCoverageGrid(
			projectedTriangles, settings, job )
	end
	diagnostics.coverageBuildMilliseconds = coverageBuildMilliseconds
	diagnostics.coverageYieldCount = coverageYieldCount
	diagnostics.coverageMaximumSliceMilliseconds =
		coverageMaximumSliceMilliseconds
	if job and SysTime() >= ( job.paintDeadline or math.huge ) then
		coroutine.yield( "paint_render_boundary" )
	end

	-- Stage 1: create a white per-hit coverage shape on transparent black.
	local coverageWidth = mask.coverageWidth or mask.width
	local coverageHeight = mask.coverageHeight or mask.height
	local coverageScaleX = coverageWidth / math.max( mask.width, 1 )
	local coverageScaleY = coverageHeight / math.max( mask.height, 1 )
	local coverageExpansion = settings.expansion
		* math.min( coverageScaleX, coverageScaleY )
	diagnostics.coverageWidth = coverageWidth
	diagnostics.coverageHeight = coverageHeight
	local rasterWallStarted = SysTime()
	local rasterCPUSeconds = 0
	local rasterMaximumSliceMilliseconds = 0
	local rasterYieldCount = 0
	local raster = {
		mode = settings.batchRaster and "mesh-batched" or "surface-legacy",
		polygonCount = 0,
		primitiveCount = 0,
		batchCount = 0,
		writeGuard = BBS.MaterialSafety.NewWriteGuard( coverageWidth, coverageHeight,
			2 + settings.feather * coverageScaleX * settings.blurPasses * 4,
			2 + settings.feather * coverageScaleY * settings.blurPasses * 4 ),
	}
	local rasterIndex = 1
	while rasterIndex <= projectedTriangleCount do
		local lastRasterIndex = rasterIndex - 1
		local estimatedPolygons = 0
		repeat
			local nextIndex = lastRasterIndex + 1
			local nextCost = ProjectedTriangleTileCost(
				projectedTriangles, nextIndex, coverageWidth,
				coverageHeight, coverageExpansion )
			if lastRasterIndex >= rasterIndex
			and estimatedPolygons + nextCost
				> DAMAGE_RASTER_SLICE_POLYGONS then break end
			lastRasterIndex = nextIndex
			estimatedPolygons = estimatedPolygons + nextCost
		until lastRasterIndex >= projectedTriangleCount
			or estimatedPolygons >= DAMAGE_RASTER_SLICE_POLYGONS
		local sliceStarted = SysTime()
		local state = {
			depthChanged = false,
			targetPushed = false,
			camStarted = false,
			clippingChanged = false,
		}
		local rasterOK, rasterError = pcall( function()
			BBS.MaterialSafety.BeginRender( state )
			SetDepthToDestinationAlpha( false )
			state.depthChanged = true
			render.PushRenderTarget( mask.coverageTarget )
			state.targetPushed = true
			if rasterIndex == 1 then render.Clear( 0, 0, 0, 0 ) end
			cam.Start2D()
			state.camStarted = true
			state.previousClipping = DisableClipping( true )
			state.clippingChanged = true
			render.OverrideAlphaWriteEnable( true, true )
			render.OverrideBlend( true,
				BLEND_ONE, BLEND_ZERO, BLENDFUNC_ADD,
				BLEND_ONE, BLEND_ZERO, BLENDFUNC_ADD )
			local useBatch = settings.batchRaster
				and raster.mode ~= "surface-fallback"
			DrawProjectedCoverage( projectedTriangles,
				coverageWidth, coverageHeight, coverageExpansion,
				useBatch, raster, rasterIndex, lastRasterIndex )
		end )
		-- Cleanup deliberately lives outside pcall: an exception in any draw call
		-- must not leak a render target, cam block, clipping, or blend override into
		-- the rest of Garry's Mod's frame.
		pcall( render.OverrideBlend, false )
		pcall( render.OverrideAlphaWriteEnable, false )
		if state.clippingChanged then
			pcall( DisableClipping, state.previousClipping )
		end
		if state.camStarted then pcall( cam.End2D ) end
		if state.targetPushed then pcall( render.PopRenderTarget ) end
		if state.depthChanged then pcall( SetDepthToDestinationAlpha, true ) end
		BBS.MaterialSafety.EndRender( state )
		local sliceMilliseconds = math.max(
			( SysTime() - sliceStarted ) * 1000, 0 )
		rasterCPUSeconds = rasterCPUSeconds + sliceMilliseconds / 1000
		rasterMaximumSliceMilliseconds = math.max(
			rasterMaximumSliceMilliseconds, sliceMilliseconds )
		if not rasterOK then error( rasterError, 0 ) end
		rasterIndex = lastRasterIndex + 1
		if rasterIndex <= projectedTriangleCount and job then
			-- GPU command submission is asynchronous, so a short Lua submission time
			-- does not prove the driver finished the work. Submit at most one bounded
			-- polygon slice per rendered frame regardless of the CPU deadline.
			rasterYieldCount = rasterYieldCount + 1
			coroutine.yield( "mask_raster" )
		end
	end
	diagnostics.batchRasterRequested = settings.batchRaster
	diagnostics.rasterMode = raster.mode
	diagnostics.rasterPolygonCount = raster.polygonCount
	diagnostics.rasterPrimitiveCount = raster.primitiveCount
	diagnostics.rasterBatchCount = raster.batchCount
	diagnostics.rasterFallbackError = raster.fallbackError
	diagnostics.rasterMilliseconds = rasterCPUSeconds * 1000
	diagnostics.rasterWallMilliseconds =
		( SysTime() - rasterWallStarted ) * 1000
	diagnostics.rasterYieldCount = rasterYieldCount
	diagnostics.rasterMaximumSliceMilliseconds =
		rasterMaximumSliceMilliseconds
	local writeRectangles
	writeRectangles, diagnostics.alphaWriteDomainFraction =
		BBS.MaterialSafety.FinishWriteGuard( raster.writeGuard, mask.width, mask.height )
	diagnostics.alphaWriteRectangleCount = #writeRectangles
	if #writeRectangles == 0 then
		error( "empty UV write domain; persistent texture unchanged", 0 )
	end
	if captureCoverage then
		local captureStarted = SysTime()
		diagnostics.coverageBeforePNG, diagnostics.coverageBeforeError =
			CaptureRenderTargetPNG( mask.coverageTarget,
				coverageWidth, coverageHeight, false )
		debugCaptureMilliseconds = debugCaptureMilliseconds
			+ ( SysTime() - captureStarted ) * 1000
	end

	-- Stage 2: feather only when the user explicitly selects a nonzero softness.
	-- Before 0.19.14 the blur did not write the cutout alpha, so the archived
	-- default of 4 looked sharp. Revision 16 migrates that value to the new zero
	-- default. Keep positive values functional rather than disabling the slider.
	diagnostics.coverageAlphaMode = settings.feather > 0 and settings.blurPasses > 0
		and "feathered-projection-alpha" or "sharp-projection-alpha"
	local blurMilliseconds = 0
	if settings.feather > 0 and settings.blurPasses > 0 then
		for pass = 1, settings.blurPasses do
			local blurStarted = SysTime()
			local blurState = {}
			local blurOK, blurError = pcall( function()
				BBS.MaterialSafety.BeginRender( blurState )
				SetDepthToDestinationAlpha( false )
				-- GMod's helper calls SetRenderTarget and leaves the last target
				-- bound. Own a stack frame so no scratch target/viewport can leak
				-- into HUD drawing or survive a coroutine yield between passes.
				render.PushRenderTarget( mask.coverageTarget )
				blurState.targetPushed = true
				cam.Start2D()
				blurState.camStarted = true
				render.BlurRenderTarget( mask.coverageTarget,
					settings.feather * coverageScaleX,
					settings.feather * coverageScaleY, 1 )
			end )
			pcall( render.OverrideBlend, false )
			pcall( render.OverrideAlphaWriteEnable, false )
			if blurState.camStarted then pcall( cam.End2D ) end
			if blurState.targetPushed then pcall( render.PopRenderTarget ) end
			pcall( SetDepthToDestinationAlpha, true )
			BBS.MaterialSafety.EndRender( blurState )
			if not blurOK then error( blurError, 0 ) end
			blurMilliseconds = blurMilliseconds
				+ ( SysTime() - blurStarted ) * 1000
			if pass < settings.blurPasses and job then
				coroutine.yield( "mask_blur" )
			end
		end
	end
	diagnostics.blurMilliseconds = blurMilliseconds
	if captureCoverage then
		local captureStarted = SysTime()
		diagnostics.coverageAfterPNG, diagnostics.coverageAfterError =
			CaptureRenderTargetPNG( mask.coverageTarget,
				coverageWidth, coverageHeight, false )
		debugCaptureMilliseconds = debugCaptureMilliseconds
			+ ( SysTime() - captureStarted ) * 1000
	end

	-- Remix needs one frame for its hash-on-write option to become effective.
	-- Arm it only after scratch raster and blur are complete. This keeps the
	-- global option disabled throughout every sliced scratch write and limits
	-- hashing to the single persistent-alpha composite below.
	if job then
		while true do
			local ready, waitReason = RTX.PrepareHashOnWriteJob( job )
			if ready then break end
			job.rtxHashOnWriteWaitReason = waitReason
			coroutine.yield( "rtx_hash_on_write" )
		end
	end

	-- Stage 3: preserve RGB and multiply persistent alpha by (1 - coverage).
	-- This accumulates hits without repeatedly blurring older damage. On Remix,
	-- enable hash-on-write only for this persistent texture mutation; hashing the
	-- scratch coverage and blur targets would add cost without fixing opacity.
	local alphaStarted = SysTime()
	if projectedTriangleCount > 0 then
		local hashToken = RTX.BeginHashOnWrite( mask,
			collectDetailedDiagnostics )
		local state = {
			depthChanged = false,
			targetPushed = false,
			camStarted = false,
		}
		local compositeOK, compositeError = pcall( function()
			BBS.MaterialSafety.BeginRender( state )
			SetDepthToDestinationAlpha( false )
			state.depthChanged = true
			render.PushRenderTarget( mask.renderTarget )
			state.targetPushed = true
			cam.Start2D()
			state.camStarted = true
			render.OverrideAlphaWriteEnable( true, true )
			render.OverrideBlend( true,
				BLEND_ZERO, BLEND_ONE, BLENDFUNC_ADD,
				BLEND_ZERO, BLEND_ONE_MINUS_SRC_ALPHA, BLENDFUNC_ADD )
			render.SetMaterial( mask.coverageMaterial )
			-- These rectangles do not overlap: softness is applied exactly once.
			-- Retain the full-screen UV mapping, restricting only the writable pixels.
			for _, rectangle in ipairs( writeRectangles ) do
				render.SetScissorRect( rectangle[ 1 ], rectangle[ 2 ],
					rectangle[ 3 ], rectangle[ 4 ], true )
				render.DrawScreenQuad()
			end
		end )
		pcall( render.OverrideBlend, false )
		pcall( render.OverrideAlphaWriteEnable, false )
		if state.camStarted then pcall( cam.End2D ) end
		if state.targetPushed then pcall( render.PopRenderTarget ) end
		if state.depthChanged then pcall( SetDepthToDestinationAlpha, true ) end
		BBS.MaterialSafety.EndRender( state )
		RTX.EndHashOnWrite( hashToken, mask )
		if not compositeOK then error( compositeError, 0 ) end
		-- Mirror only coverage which successfully reached the persistent alpha RT.
		-- Later layer queries use this exact projected geometry to pass through old
		-- holes without forcing a render-target readback.
		if coverageDelta then
			local coverageStarted = SysTime()
			AddProjectedCoverageToMask( mask, coverageDelta, settings )
			diagnostics.coverageCommitMilliseconds =
				( SysTime() - coverageStarted ) * 1000
		else
			diagnostics.coverageCommitMilliseconds = 0
		end
	end
	diagnostics.alphaCompositeMilliseconds =
		( SysTime() - alphaStarted ) * 1000
	mask.paintedTriangleCount = mask.paintedTriangleCount + #triangles
	mask.paintedProjectedTriangleCount =
		( mask.paintedProjectedTriangleCount or 0 ) + projectedTriangleCount
	diagnostics.paintWallMilliseconds = ( SysTime() - started ) * 1000
	diagnostics.paintMilliseconds = projectionMilliseconds
		+ ( diagnostics.rasterMilliseconds or 0 )
		+ ( diagnostics.blurMilliseconds or 0 )
		+ ( diagnostics.alphaCompositeMilliseconds or 0 )
		+ ( diagnostics.coverageBuildMilliseconds or 0 )
		+ ( diagnostics.coverageCommitMilliseconds or 0 )
		+ debugCaptureMilliseconds
	diagnostics.debugCaptureMilliseconds = debugCaptureMilliseconds
	mask.lastPaintDiagnostics = diagnostics
	return diagnostics
end

local function AccountJobPerformance( job, name, milliseconds )
	milliseconds = math.max( tonumber( milliseconds ) or 0, 0 )
	if milliseconds ~= milliseconds then return 0 end
	job.performanceAccountedMilliseconds =
		( job.performanceAccountedMilliseconds or 0 ) + milliseconds
	if BBS.PerfAddMilliseconds then
		BBS.PerfAddMilliseconds( job.hit, name, milliseconds )
	end
	return milliseconds
end

local function EndJobPerformance( job, name, startedAt )
	if not startedAt then return 0 end
	return AccountJobPerformance( job, name,
		math.max( ( SysTime() - startedAt ) * 1000, 0 ) )
end

local function GetEntityDamageState( entity )
	local state = BBS.DamageStates[ entity ]
	if state then return state end
	state = {
		entity = entity,
		model = NormalizeMaterialPath( entity:GetModel() or "" ),
		masks = {},
	}
	BBS.DamageStates[ entity ] = state
	return state
end

local RecomputeCompatibilityStateFlags

local function DrawUsingPreviousRenderOverride( state, entity, flags )
	local previous = state.previousRenderOverride
	if not isfunction( previous ) or previous == state.rtxRenderOverride then
		return entity:DrawModel( flags )
	end

	-- RenderOverride ownership can change while either addon rebuilds. Never
	-- follow a previous-callback chain that has already returned to this state.
	if state.rtxPreviousRenderOverrideActive then
		return entity:DrawModel( flags )
	end
	state.rtxPreviousRenderOverrideActive = true
	local ok, result = pcall( previous, entity, flags )
	state.rtxPreviousRenderOverrideActive = false
	if not ok then error( result, 0 ) end
	return result
end

local function DrawWithRTXDamageMaterials( state, entity, flags )
	local boundMaskCount = 0
	-- AME periodically reasserts its !advmat_* submaterial in preview and
	-- client-authoritative modes. Bind BBS's derived material for the duration
	-- of this entity draw so both addons can retain ownership without racing.
	if state.advancedMaterialEditor or state.advancedBodygroupTool
	or GetBool( "bbs_damage_rtx_direct_override", true ) then
		for submaterialIndex, mask in pairs( state.masks or {} ) do
			local currentABTState = mask.advancedBodygroupTool
				and istable( _G.AdvancedBodygroupTool )
				and istable( _G.AdvancedBodygroupTool.ClientStates )
				and _G.AdvancedBodygroupTool.ClientStates[ entity ] or nil
			local abtCurrent = mask.compatibilitySourceSnapshot == true
				or not mask.advancedBodygroupTool
				or ( currentABTState
					and currentABTState.identity
						== mask.advancedBodygroupToolIdentity )
			mask.compatibilitySourceStale = not abtCurrent
			if mask.overrideApplied and mask.material
			and abtCurrent
			and submaterialIndex >= 0 and submaterialIndex < MAX_SUBMATERIALS then
				render.MaterialOverrideByIndex( submaterialIndex, mask.material )
				boundMaskCount = boundMaskCount + 1
			end
		end
	end
	state.rtxLastBoundMaskCount = boundMaskCount
	state.rtxLastRenderFlags = flags
	-- If ABT was installed before BBS, its chained callback would otherwise bind
	-- the ABT-only material after our combined material and erase bullet damage.
	-- Temporarily hide only the exact resources already baked into BBS, then put
	-- them back even when a third-party callback errors.
	local suppressed = {}
	local tool = _G.AdvancedBodygroupTool
	local abtState = istable( tool ) and istable( tool.ClientStates )
		and tool.ClientStates[ entity ] or nil
	if istable( abtState ) and istable( abtState.resources ) then
		for submaterialIndex, mask in pairs( state.masks or {} ) do
			local resource = abtState.resources[ submaterialIndex ]
			if mask.overrideApplied and mask.advancedBodygroupTool
			and abtState.identity == mask.advancedBodygroupToolIdentity
			and resource == mask.advancedBodygroupToolSourceResource then
				suppressed[ submaterialIndex ] = resource
				abtState.resources[ submaterialIndex ] = nil
			end
		end
	end
	local ok, result = pcall( DrawUsingPreviousRenderOverride,
		state, entity, flags )
	if istable( abtState ) and istable( abtState.resources ) then
		for submaterialIndex, resource in pairs( suppressed ) do
			abtState.resources[ submaterialIndex ] = resource
		end
	end
	if not ok then error( result, 0 ) end
	return result
end

local function HasStudioRenderFlag( flags, globalName )
	local flag = _G[ globalName ]
	return isnumber( flags ) and isnumber( flag ) and bit.band( flags, flag ) ~= 0
end

local RestoreRTXDamageRenderOverride

local function InstallRTXDamageRenderOverride( entity, state )
	local detectionReason = RTX.DetectionReason()
	local advancedMaterialCompatibility = state.advancedMaterialEditor == true
	local advancedBodygroupCompatibility = state.advancedBodygroupTool == true
	if not detectionReason and advancedMaterialCompatibility then
		detectionReason = "Advanced Material Editor compatibility"
	end
	if not detectionReason and advancedBodygroupCompatibility then
		detectionReason = "Advanced Bodygroup Tool compatibility"
	end
	if not detectionReason then
		if state.rtxRenderOverrideInstalled and RestoreRTXDamageRenderOverride then
			RestoreRTXDamageRenderOverride( entity, state )
		end
		return false, "no RTX Remix or compatible material editor requires a direct override"
	end
	if not render or not isfunction( render.MaterialOverrideByIndex ) then
		return false, "render.MaterialOverrideByIndex unavailable"
	end
	if state.rtxRenderOverrideInstalled
	and entity.RenderOverride == state.rtxRenderOverride then
		-- A new hit is also a recovery point. Older versions permanently latched a
		-- single transient draw error and silently stopped supplying the alpha-test
		-- material to all later shadow/depth passes on this entity.
		state.rtxRenderOverrideFailed = false
		state.rtxRenderOverrideLastDrawFailed = false
		state.rtxRenderOverrideConsecutiveFailures = 0
		return true, state.rtxDetectionReason or detectionReason
	end
	local activeABTState = istable( _G.AdvancedBodygroupTool )
		and istable( _G.AdvancedBodygroupTool.ClientStates )
		and _G.AdvancedBodygroupTool.ClientStates[ entity ] or nil
	if state.rtxRenderOverrideInstalled and istable( activeABTState )
	and entity.RenderOverride == activeABTState.renderOverride
	and activeABTState.previousRenderOverride == state.rtxRenderOverride then
		-- ABT rebuilt after BBS and now wraps us. We are still in the live chain;
		-- installing another wrapper here would create BBS -> ABT -> BBS recursion.
		state.rtxRenderOverrideFailed = false
		return true, state.rtxDetectionReason or detectionReason
	end

	-- If another addon replaced our callback, chain the new callback rather than
	-- taking ownership of it or restoring a stale function later.
	state.previousRenderOverride = entity.RenderOverride
	state.rtxRenderOverrideFailed = false
	state.rtxDetectionReason = detectionReason
	state.rtxRenderOverride = function( renderEntity, flags )
		if BBS.DamageStates[ renderEntity ] ~= state then
			return DrawUsingPreviousRenderOverride( state, renderEntity, flags )
		end

		local ok, result = pcall( DrawWithRTXDamageMaterials,
			state, renderEntity, flags )
		-- Per-index overrides are global render state and must never leak into the
		-- next entity, including when a chained RenderOverride raises an error.
		local clearOK, clearError = pcall( render.MaterialOverrideByIndex )
		if ok and clearOK then
			state.rtxRenderOverrideFailed = false
			state.rtxRenderOverrideLastDrawFailed = false
			state.rtxRenderOverrideConsecutiveFailures = 0
			state.rtxRenderOverrideLastSuccessTime = SysTime()
			return result
		end

		local failure = ok and ( "override reset failed: " .. tostring( clearError ) )
			or tostring( result )
		state.rtxRenderOverrideFailed = false -- retained only for old-state compatibility
		state.rtxRenderOverrideLastDrawFailed = true
		state.rtxRenderOverrideFailureCount =
			( state.rtxRenderOverrideFailureCount or 0 ) + 1
		state.rtxRenderOverrideConsecutiveFailures =
			( state.rtxRenderOverrideConsecutiveFailures or 0 ) + 1
		state.rtxRenderOverrideLastFailureTime = SysTime()
		state.rtxRenderOverrideLastError = failure
		state.rtxRenderOverrideLastFailureFlags = flags
		state.rtxRenderOverrideLastFailureShadowDepth =
			HasStudioRenderFlag( flags, "STUDIO_SHADOWDEPTHTEXTURE" )
		state.rtxRenderOverrideLastFailureSSAODepth =
			HasStudioRenderFlag( flags, "STUDIO_SSAODEPTHTEXTURE" )

		-- Do not permanently disable RTX-direct drawing. Fall back only for this
		-- invocation, then retry naturally on the next color/shadow pass. Throttle
		-- diagnostics in case an incompatible third-party override fails every frame.
		local now = SysTime()
		if not state.rtxRenderOverrideNextErrorLog
		or now >= state.rtxRenderOverrideNextErrorLog then
			state.rtxRenderOverrideNextErrorLog = now + 5
			BBS.Log( "direct damage material override failed for ent=%d flags=%s shadowDepth=%s ssaoDepth=%s: %s; this pass uses a safe fallback and the next pass will retry",
				renderEntity:EntIndex(), tostring( flags ),
				tostring( state.rtxRenderOverrideLastFailureShadowDepth ),
				tostring( state.rtxRenderOverrideLastFailureSSAODepth ), failure )
		end

		local fallbackOK, fallbackResult = pcall( DrawUsingPreviousRenderOverride,
			state, renderEntity, flags )
		if fallbackOK then return fallbackResult end
		state.rtxRenderOverrideLastFallbackError = tostring( fallbackResult )
		return renderEntity:DrawModel( flags )
	end
	state.rtxRenderOverrideInstalled = true
	entity.RenderOverride = state.rtxRenderOverride
	return true, detectionReason
end

RestoreRTXDamageRenderOverride = function( entity, state )
	if state.rtxRenderOverrideInstalled
	and entity.RenderOverride == state.rtxRenderOverride then
		entity.RenderOverride = state.previousRenderOverride
	else
		local tool = _G.AdvancedBodygroupTool
		local abtState = istable( tool ) and istable( tool.ClientStates )
			and tool.ClientStates[ entity ] or nil
		if state.rtxRenderOverrideInstalled and istable( abtState )
		and entity.RenderOverride == abtState.renderOverride
		and abtState.previousRenderOverride == state.rtxRenderOverride then
			abtState.previousRenderOverride = state.previousRenderOverride
		end
	end
	state.rtxRenderOverrideInstalled = false
	state.rtxPreviousRenderOverrideActive = nil
	state.rtxRenderOverride = nil
	state.previousRenderOverride = nil
end

if REBUILD_RTX_RENDER_OVERRIDES then
	for entity, state in pairs( BBS.DamageStates ) do
		if IsValid( entity ) then
			for _, mask in pairs( state.masks or {} ) do
				if mask.overrideApplied then
					InstallRTXDamageRenderOverride( entity, state )
					break
				end
			end
		end
	end
end

local function ApplyPaintJob( job )
	if not IsValid( job.entity ) then return false, "entity removed" end
	local dumpEnabled = GetBool( "bbs_damage_dump_debug", false )
	local validateCopy = GetBool( "bbs_damage_validate_copy", false )
	local probeCopy = dumpEnabled or validateCopy
	local state = GetEntityDamageState( job.entity )
	local mask = state.masks[ job.submaterialIndex ]
	local editedSources = ResolveEditedMaterialSources(
		job.entity, job.submaterialIndex, job.originalPath )
	local replacingCompatibilitySource = mask
		and mask.editedSourceSignature ~= editedSources.signature
	local createdMask = false
	if not mask or replacingCompatibilitySource then
		local setupMilliseconds = 0
		local previousMask = mask
		local errorMessage, pending
		local useResolvedSources = true
		while true do
			if job.compatibilitySourceNextFrame
			and FrameNumber() < job.compatibilitySourceNextFrame then
				coroutine.yield( "compatibility_source_pending" )
			end
			local attemptStarted = BBS.PerfBegin
				and BBS.PerfBegin( job.hit ) or SysTime()
			if useResolvedSources then
				useResolvedSources = false
			else
				editedSources = ResolveEditedMaterialSources(
					job.entity, job.submaterialIndex, job.originalPath )
			end
			local function YieldSetupStage( label )
				setupMilliseconds = setupMilliseconds + math.max(
					( SysTime() - attemptStarted ) * 1000, 0 )
				coroutine.yield( label )
				attemptStarted = BBS.PerfBegin
					and BBS.PerfBegin( job.hit ) or SysTime()
			end
			mask, errorMessage, pending = CreateDamageMask(
				job.entity, job.submaterialIndex, job.originalPath,
				editedSources, YieldSetupStage )
			if attemptStarted then
				setupMilliseconds = setupMilliseconds
					+ math.max( ( SysTime() - attemptStarted ) * 1000, 0 )
			end
			if mask or not pending then break end
			job.compatibilitySourceWaits =
				( job.compatibilitySourceWaits or 0 ) + 1
			job.compatibilitySourceWaitReason = errorMessage
			local backoff = math.min( 2 ^ math.floor(
				math.max( job.compatibilitySourceWaits - 1, 0 ) / 4 ), 60 )
			job.compatibilitySourceNextFrame = FrameNumber() + backoff
			coroutine.yield( "compatibility_source_pending" )
		end
		AccountJobPerformance( job, "Material clone + source copy",
			setupMilliseconds )
		if not mask then return false, errorMessage end
		if previousMask then
			local transferred, transferError = TransferDamageMaskHistory(
				previousMask, mask )
			if not transferred then
				return false, "could not preserve existing damage while refreshing edited material: "
					.. tostring( transferError )
			end
			if previousMask.submaterialOverrideApplied
			and not mask.directMaterialOwnership then
				mask.previousOverride = previousMask.previousOverride
			end
			mask.compatibilityReplacedSubmaterialOverride =
				previousMask.submaterialOverrideApplied == true
			mask.compatibilityRestoreOverride = mask.advancedMaterialEditorOverride
				or previousMask.previousOverride
			mask.compatibilityRefreshReason = "edited source signature changed"
		end
		if probeCopy then
			local validationStarted = BBS.PerfBegin and BBS.PerfBegin( job.hit ) or nil
			mask.copyProbe = ProbeRenderTarget( mask,
				job.materialRecord.triangles, "after source texture copy" )
			if mask.copyProbe.ok then
				mask.sourceRGBValid = mask.copyProbe.nonSentinelCount > 0
				if mask.preserveSourceAlpha or mask.advancedBodygroupTool
				or previousMask then
					mask.sourceAlphaValid = mask.copyProbe.affectedSampleCount == 0
						or mask.copyProbe.affectedOpaqueCount > 0
				else
					-- Alpha-less sources are required to be opaque everywhere before
					-- the first damage pass. This specifically catches the 1/255
					-- render.Clear failure shown in Huohuo's Clothes dump.
					mask.sourceAlphaValid =
						( mask.copyProbe.minimumAlpha or 0 ) >= 128
				end
				mask.sourceCopyValid = mask.sourceRGBValid and mask.sourceAlphaValid
			else
				mask.sourceCopyValid = nil
			end
			mask.sourceValidationSkipped = false
			mask.catastrophicAlphaFailure = not mask.preserveSourceAlpha
				and not mask.advancedBodygroupTool and not previousMask
				and mask.copyProbe.ok
				and ( mask.copyProbe.minimumAlpha or 0 ) < 128
			BBS.Log( "  source texture copy probe: valid=%s enforced=%s rgb=%s alpha=%s nonSentinel=%d/%d affectedOpaque=%d/%d alphaRange=%s..%s method=%s source=%dx%d rt=%dx%d error=%s",
				tostring( mask.sourceCopyValid ), tostring( validateCopy ),
				tostring( mask.sourceRGBValid ), tostring( mask.sourceAlphaValid ),
				mask.copyProbe.nonSentinelCount or 0,
				mask.copyProbe.sampleCount or 0,
				mask.copyProbe.affectedOpaqueCount or 0,
				mask.copyProbe.affectedSampleCount or 0,
				tostring( mask.copyProbe.minimumAlpha ),
				tostring( mask.copyProbe.maximumAlpha ), mask.sourceCopyMethod,
				mask.sourceTextureWidth, mask.sourceTextureHeight,
				mask.width, mask.height, tostring( mask.copyProbe.error ) )
			EndJobPerformance( job, "GPU source-copy validation", validationStarted )
		else
			-- Source copying has already been verified during development. Avoid
			-- render.CapturePixels here: it synchronizes the GPU and can stall a
			-- normal shot for hundreds of milliseconds.
			mask.sourceCopyValid = nil -- Not measured; do not report a false success.
			mask.sourceValidationSkipped = true
		end
		createdMask = true
	end
	mask.sourceValidationEnforced = validateCopy
	mask.rtxHashOnWritePreparationWaits =
		job.rtxHashOnWritePreparationWaits
	mask.rtxHashOnWritePreparationError =
		job.rtxHashOnWritePreparationError

	local captures = { probeLines = {} }
	AppendProbeLines( captures.probeLines, mask.copyProbe )
	if dumpEnabled then
		local captureStarted = BBS.PerfBegin and BBS.PerfBegin( job.hit ) or nil
		captures.beforeRGB, captures.beforeRGBError = CaptureRenderTargetPNG(
			mask.renderTarget, mask.width, mask.height, false )
		captures.beforeAlpha, captures.beforeAlphaError = CaptureRenderTargetPNG(
			mask.renderTarget, mask.width, mask.height, true )
		EndJobPerformance( job, "Debug capture + bundle I/O", captureStarted )
	end
	job.materialRecord.mask = mask
	if ( validateCopy and mask.sourceCopyValid == false )
	or mask.catastrophicAlphaFailure then
		job.materialRecord.status = "apply_failed"
		if dumpEnabled or GetBool( "bbs_damage_print_vmt", false ) then
			PrintGeneratedMaterialVMT( mask )
		end
		if dumpEnabled then TryWriteMaterialDebugBundle( job, mask, captures ) end
		return false, string.format(
			"source texture validation failed%s (rgb=%s alpha=%s, %d/%d non-sentinel, %d/%d affected opaque); submaterial was not replaced",
			mask.catastrophicAlphaFailure
				and "; catastrophic alpha initialization detected" or "",
			tostring( mask.sourceRGBValid ), tostring( mask.sourceAlphaValid ),
			mask.copyProbe.nonSentinelCount or 0, mask.copyProbe.sampleCount or 0,
			mask.copyProbe.affectedOpaqueCount or 0,
			mask.copyProbe.affectedSampleCount or 0 )
	end
	-- Render-target allocation and source copying can themselves be a substantial
	-- first-hit cost. Keep them in a separate frame from adaptive projection and
	-- the final blur/composite path.
	if createdMask then coroutine.yield( "mask_initialized" ) end
	local paintDiagnostics = PaintTriangles(
		mask, job.materialRecord.triangles, dumpEnabled, job.hit, job )
	AccountJobPerformance( job, "Irregular hull to UV projection",
		paintDiagnostics.projectionMilliseconds or 0 )
	AccountJobPerformance( job, "Debug capture + bundle I/O",
		paintDiagnostics.debugCaptureMilliseconds or 0 )
	local coverageMilliseconds =
		( paintDiagnostics.coverageBuildMilliseconds or 0 )
		+ ( paintDiagnostics.coverageCommitMilliseconds or 0 )
	AccountJobPerformance( job, "Existing-hole coverage grid",
		coverageMilliseconds )
	AccountJobPerformance( job, "Mask raster + blur + alpha",
		math.max( ( paintDiagnostics.paintMilliseconds or 0 )
			- ( paintDiagnostics.projectionMilliseconds or 0 )
			- ( paintDiagnostics.debugCaptureMilliseconds or 0 )
			- coverageMilliseconds, 0 ) )
	job.materialRecord.projectedTriangleCount =
		paintDiagnostics.projectedTriangleCount or 0
	job.materialRecord.projectedTriangles = paintDiagnostics.projectedTriangles or {}
	paintDiagnostics.projectedTriangles = nil
	captures.coverageBefore = paintDiagnostics.coverageBeforePNG
	captures.coverageBeforeError = paintDiagnostics.coverageBeforeError
	captures.coverageAfter = paintDiagnostics.coverageAfterPNG
	captures.coverageAfterError = paintDiagnostics.coverageAfterError
	paintDiagnostics.coverageBeforePNG = nil
	paintDiagnostics.coverageAfterPNG = nil
	local hasProjectedCoverage = ( paintDiagnostics.projectedTriangleCount or 0 ) > 0
	if hasProjectedCoverage then
		-- PaintTriangles acquired and released the active write window around its
		-- final alpha composite.
		job.rtxHashOnWritePreparationActive = false
	else
		-- Projection can legitimately collapse to zero after broad-phase mesh
		-- selection. No alpha composite occurred, so release the prepared window.
		RTX.ReleasePreparedHashOnWriteJob( job, mask )
	end
	if hasProjectedCoverage or ( not state.masks[ job.submaterialIndex ]
		and not paintDiagnostics.projectionError ) then
		-- Publish a new candidate only after validation and projection succeed.
		-- Failed replacements must not evict a previously working material or
		-- poison subsequent hits with the same failed source-copy object. Retain
		-- valid, unbound zero-coverage sources for reuse: allocating a fresh RT on
		-- every near miss would leak permanently named engine textures.
		state.masks[ job.submaterialIndex ] = mask
		if RecomputeCompatibilityStateFlags then
			RecomputeCompatibilityStateFlags( state )
		end
	end
	if hasProjectedCoverage then
		local refreshStarted = BBS.PerfBegin and BBS.PerfBegin( job.hit ) or nil
		local rtxRefresh, rtxRefreshReason = RTX.RefreshDamageMaterial(
			mask, "hit " .. tostring( job.hit.serial ) .. " damage paint" )
		mask.rtxRefreshReasonText = rtxRefreshReason
		job.materialRecord.rtxRefresh = rtxRefresh
		EndJobPerformance( job, "RTX material refresh", refreshStarted )
		if mask.rtxRefreshAttempted and not rtxRefresh then
			BBS.Log( "  RTX material refresh failed: material=%s invalidate=%s error=%s rebind=%s error=%s recompute=%s error=%s pipeline=%s error=%s",
				mask.materialName,
				tostring( mask.rtxCacheInvalidationSucceeded ),
				tostring( mask.rtxCacheInvalidationError ),
				tostring( mask.rtxTextureRebindSucceeded ),
				tostring( mask.rtxTextureRebindError ),
				tostring( mask.rtxMaterialRecomputeSucceeded ),
				tostring( mask.rtxMaterialRecomputeError ),
				tostring( mask.rtxPipelineProcessSucceeded ),
				tostring( mask.rtxPipelineProcessError ) )
		end
		if not mask.overrideApplied then
			if mask.directMaterialOwnership then
				if mask.compatibilityReplacedSubmaterialOverride then
					job.entity:SetSubMaterial( job.submaterialIndex,
						mask.compatibilityRestoreOverride ~= ""
							and mask.compatibilityRestoreOverride or nil )
					mask.previousOverride =
						mask.compatibilityRestoreOverride or ""
				end
				mask.submaterialOverrideApplied = false
			else
				job.entity:SetSubMaterial( job.submaterialIndex,
					"!" .. mask.materialName )
				mask.submaterialOverrideApplied = true
			end
			mask.overrideApplied = true
		end
		local rtxDirect, rtxReason = InstallRTXDamageRenderOverride( job.entity, state )
		mask.rtxDirectOverride = rtxDirect
		mask.rtxDirectOverrideReason = rtxReason
		job.materialRecord.rtxDirectOverride = rtxDirect
		-- Remix resolves the updated render-target content hash only after a real
		-- draw. Poll from PostRender for a few frames, record the D3D pointer/hash
		-- identity, and exclude every observed version from opacity micromaps.
		RTX.QueueDamageProbe( mask, job.hit.serial, "damage material applied" )
		job.materialRecord.status = "applied"
		job.hit.damageUV.appliedMaterialCount =
			job.hit.damageUV.appliedMaterialCount + 1
	else
		-- The mesh query intentionally uses the irregular hull's enclosing
		-- cylinder. A nearby material can therefore be a broad-phase candidate
		-- without receiving any exact jagged projection coverage.
		job.materialRecord.status = "no_projected_coverage"
	end
	if GetBool( "bbs_damage_print_vmt", false ) then
		local outputStarted = BBS.PerfBegin and BBS.PerfBegin( job.hit ) or nil
		PrintGeneratedMaterialVMT( mask )
		EndJobPerformance( job, "Debug console output", outputStarted )
	end
	if dumpEnabled then
		local captureStarted = BBS.PerfBegin and BBS.PerfBegin( job.hit ) or nil
		mask.afterPaintProbe = ProbeRenderTarget( mask,
			job.materialRecord.triangles, "after alpha damage paint" )
		AppendProbeLines( captures.probeLines, mask.afterPaintProbe )
		captures.afterRGB, captures.afterRGBError = CaptureRenderTargetPNG(
			mask.renderTarget, mask.width, mask.height, false )
		captures.afterAlpha, captures.afterAlphaError = CaptureRenderTargetPNG(
			mask.renderTarget, mask.width, mask.height, true )
		TryWriteMaterialDebugBundle( job, mask, captures )
		EndJobPerformance( job, "Debug capture + bundle I/O", captureStarted )
	end
	-- The projected list has served rasterization and synchronous bundle output
	-- by this point. Retain it only while the optional inspector is actually in
	-- use; a normal hit can otherwise pin tens of thousands of tiny Lua tables.
	if job.hit ~= BBS.LastHit
	or not GetBool( "bbs_damage_uv_preview", false ) then
		job.materialRecord.projectedTriangles = nil
	end
	return true
end

local function QueueCompatibilityRefresh( entity, submaterialIndex, mask )
	local slots = BBS.DamageCompatibilityRefreshQueued[ entity ]
	if not slots then
		slots = {}
		BBS.DamageCompatibilityRefreshQueued[ entity ] = slots
	end
	if slots[ submaterialIndex ] then return end
	slots[ submaterialIndex ] = true
	BBS.DamageCompatibilityRefreshQueue[
		#BBS.DamageCompatibilityRefreshQueue + 1 ] = {
		entity = entity,
		submaterialIndex = submaterialIndex,
		maskSerial = mask.serial,
		queuedAt = SysTime(),
	}
end

local function FinishCompatibilityRefreshQueueRecord( record )
	local slots = BBS.DamageCompatibilityRefreshQueued[ record.entity ]
	if slots then
		slots[ record.submaterialIndex ] = nil
		if next( slots ) == nil then
			BBS.DamageCompatibilityRefreshQueued[ record.entity ] = nil
		end
	end
end

RecomputeCompatibilityStateFlags = function( state )
	state.advancedMaterialEditor = false
	state.advancedBodygroupTool = false
	for _, mask in pairs( state.masks or {} ) do
		state.advancedMaterialEditor = state.advancedMaterialEditor
			or mask.advancedMaterialEditor == true
		state.advancedBodygroupTool = state.advancedBodygroupTool
			or mask.advancedBodygroupTool == true
	end
end

local function ProcessCompatibilityRefresh( record )
	if record.nextAttemptFrame
	and FrameNumber() < record.nextAttemptFrame then return false end
	local entity = record.entity
	local state = IsValid( entity ) and BBS.DamageStates[ entity ] or nil
	local previousMask = state and state.masks[ record.submaterialIndex ] or nil
	if not previousMask or previousMask.serial ~= record.maskSerial
	or previousMask.compatibilitySourceSnapshot then
		return true
	end
	local sources = ResolveEditedMaterialSources( entity,
		record.submaterialIndex, previousMask.originalPath )
	if sources.pending then
		record.waitCount = ( record.waitCount or 0 ) + 1
		record.nextAttemptFrame = FrameNumber() + math.min( 2 ^ math.floor(
			math.max( record.waitCount - 1, 0 ) / 4 ), 60 )
		return false, sources.pendingReason
	end
	if sources.signature == previousMask.editedSourceSignature then return true end
	local replacement, errorMessage = CreateDamageMask( entity,
		record.submaterialIndex, previousMask.originalPath, sources )
	if not replacement then return true, errorMessage end
	local transferred, transferError = TransferDamageMaskHistory(
		previousMask, replacement )
	if not transferred then return true, transferError end
	if previousMask.submaterialOverrideApplied
	and not replacement.directMaterialOwnership then
		replacement.previousOverride = previousMask.previousOverride
	end
	replacement.overrideApplied = previousMask.overrideApplied
	replacement.compatibilityRefreshReason = "live edited source changed"
	if previousMask.submaterialOverrideApplied
	and replacement.directMaterialOwnership then
		local restoreOverride = replacement.advancedMaterialEditorOverride
			or previousMask.previousOverride
		entity:SetSubMaterial( record.submaterialIndex,
			restoreOverride ~= "" and restoreOverride or nil )
		replacement.previousOverride = restoreOverride or ""
		replacement.submaterialOverrideApplied = false
	elseif replacement.directMaterialOwnership then
		replacement.submaterialOverrideApplied = false
	else
		entity:SetSubMaterial( record.submaterialIndex,
			"!" .. replacement.materialName )
		replacement.submaterialOverrideApplied = true
	end
	state.masks[ record.submaterialIndex ] = replacement
	RecomputeCompatibilityStateFlags( state )
	local refreshed, refreshReason = RTX.RefreshDamageMaterial(
		replacement, "compatible editor source refresh" )
	replacement.rtxRefreshReasonText = refreshReason
	local direct, directReason = InstallRTXDamageRenderOverride( entity, state )
	replacement.rtxDirectOverride = direct
	replacement.rtxDirectOverrideReason = directReason
	RTX.QueueDamageProbe( replacement, 0, "compatible editor source refresh" )
	if GetBool( "bbs_debug_console", false ) then
		BBS.Log( "refreshed compatible edited material ent=%d slot=%d old=%s new=%s history=%s rtxRefresh=%s direct=%s (%s)",
			entity:EntIndex(), record.submaterialIndex,
			tostring( previousMask.editedSourceSignature ),
			tostring( replacement.editedSourceSignature ),
			tostring( replacement.compatibilityHistoryTransferred ),
			tostring( refreshed ), tostring( direct ), tostring( directReason ) )
	end
	return true
end

local compatibilitySourceScan = {
	nextScan = 0,
	nextRecord = 0,
	queue = {},
	cursor = 1,
}
hook.Add( "Think", "BBS.ScanCompatibleEditedMaterials", function()
	local now = SysTime()
	if compatibilitySourceScan.cursor > #compatibilitySourceScan.queue then
		if #compatibilitySourceScan.queue > 0 then
			compatibilitySourceScan.queue = {}
			compatibilitySourceScan.cursor = 1
			compatibilitySourceScan.nextScan = now + 0.5
		end
		if now < compatibilitySourceScan.nextScan then return end
		for entity, state in pairs( BBS.DamageStates ) do
			if IsValid( entity ) then
				for submaterialIndex, mask in pairs( state.masks or {} ) do
					if mask.overrideApplied
					and not mask.compatibilitySourceSnapshot then
						compatibilitySourceScan.queue[
							#compatibilitySourceScan.queue + 1 ] = {
							entity = entity,
							submaterialIndex = submaterialIndex,
							maskSerial = mask.serial,
						}
					end
				end
			end
		end
		if #compatibilitySourceScan.queue == 0 then
			compatibilitySourceScan.nextScan = now + 0.5
			return
		end
	end
	if now < compatibilitySourceScan.nextRecord then return end
	if BBS.TryBeginHeavyFrame
	and not BBS.TryBeginHeavyFrame( "damage-compatibility-scan" ) then return end
	local record = compatibilitySourceScan.queue[ compatibilitySourceScan.cursor ]
	compatibilitySourceScan.cursor = compatibilitySourceScan.cursor + 1
	compatibilitySourceScan.nextRecord = now + 0.1
	local state = IsValid( record.entity ) and BBS.DamageStates[ record.entity ] or nil
	local mask = state and state.masks[ record.submaterialIndex ] or nil
	if not mask or mask.serial ~= record.maskSerial
	or not mask.overrideApplied or mask.compatibilitySourceSnapshot then return end
	local sources = ResolveEditedMaterialSources( record.entity,
		record.submaterialIndex, mask.originalPath )
	if sources.pending or sources.signature ~= mask.editedSourceSignature then
		QueueCompatibilityRefresh( record.entity,
			record.submaterialIndex, mask )
	end
end )

local function QueueMaterialDamage( hit, damageResult )
	for _, materialRecord in ipairs( damageResult.materials ) do
		local submaterialIndex, originalPath, matchKind =
			FindSubmaterial( hit.entity, materialRecord.material )
		materialRecord.submaterialIndex = submaterialIndex
		materialRecord.originalPath = originalPath
		materialRecord.submaterialMatch = matchKind
		if submaterialIndex == nil then
			materialRecord.status = "no_submaterial"
			materialRecord.error = "mesh material was not found in Entity:GetMaterials()"
		elseif submaterialIndex < 0 or submaterialIndex >= MAX_SUBMATERIALS then
			materialRecord.status = "invalid_submaterial"
			materialRecord.error = "submaterial index is outside 0..31"
		else
			materialRecord.status = "queued"
			BBS.DamagePaintQueue[ #BBS.DamagePaintQueue + 1 ] = {
				hit = hit,
				entity = hit.entity,
				materialRecord = materialRecord,
				submaterialIndex = submaterialIndex,
				originalPath = originalPath,
			}
			damageResult.queuedMaterialCount = damageResult.queuedMaterialCount + 1
		end
	end
	if damageResult.queuedMaterialCount > 0 then
		damageResult.status = "paint_queued"
	else
		damageResult.status = "apply_unavailable"
	end
end

local function PrintDamageResult( hit )
	local damage = hit and hit.damageUV
	if not damage then
		BBS.Log( "  UV damage: no result" )
		return
	end
	if not damage.ok then
		BBS.Log( "  UV damage skipped: %s", damage.error or damage.status or "unknown" )
		return
	end
	BBS.Log( "  UV damage: %d eligible groups (%d explicit overrides), %d/%d eligible/total cached meshes; affected=%d meshes %d materials %d triangles %d unique UVs; apply=%s queued=%d applied=%d",
		#( damage.bodygroups or {} ), damage.overriddenBodygroupCount or 0,
		damage.hideableMeshCount or 0, damage.totalMeshCount or 0,
		damage.affectedMeshCount or 0,
		damage.affectedMaterialCount or 0, damage.triangleCount or 0,
		damage.uvCount or 0, tostring( damage.applyRequested ),
		damage.queuedMaterialCount or 0, damage.appliedMaterialCount or 0 )
	BBS.Log( "  UV timing: eligibility=%s %.2f ms ownership=%s directGroups=%d fallbackGroups=%d comparisons=%d UVbuild+dispatch=%.2f ms",
		damage.eligibilityCacheHit and "cache-hit" or "built",
		damage.eligibilityBuildMilliseconds or 0,
		tostring( damage.ownershipMode or "unknown" ),
		damage.directOwnershipBodygroupCount or 0,
		damage.comparisonBodygroupCount or 0,
		damage.comparisonCount or 0,
		damage.uvPipelineMilliseconds or 0 )
	BBS.Log( "  visual mesh surfaces: limit=%s encountered=%d solidLayers=%d passedExistingHoles=%d passedABTHidden=%d selected=%d damageableSelected=%d blockedDamageableMeshes=%d mode=%s occludersIncluded=%s",
		( damage.layerLimit or 0 ) == 0 and "unlimited"
			or tostring( damage.layerLimit ),
		damage.layerSurfaceCount or damage.layerCount or 0,
		damage.layerCount or 0, damage.passedExistingHoleCount or 0,
		damage.advancedBodygroupHiddenSurfaceCount or 0,
		damage.selectedLayerCount or 0,
		damage.selectedDamageableLayerCount or 0,
		damage.blockedDamageableMeshCount or 0,
		tostring( damage.layerOwnershipSource or "unknown" ),
		tostring( damage.layerOccludersIncluded ) )
	for _, layer in ipairs( damage.layers or {} ) do
		BBS.Log( "    surface=%d solidLayer=%s selected=%s damageable=%s throughHole=%s abtHidden=%s bodygroup=%s raySamples=%d/%d depth=%.3f..%.3f mesh=%s",
			layer.surfaceIndex or -1, tostring( layer.countedIndex or "open" ),
			tostring( layer.selected ),
			tostring( layer.damageable ),
			tostring( layer.passesExistingHole ),
			tostring( layer.advancedBodygroupToolHidden ),
			tostring( layer.bodygroupId ),
			layer.openRaySampleCount or 0, layer.raySampleCount or 0,
			layer.minimumDepth or 0, layer.maximumDepth or 0,
			tostring( layer.name ) )
	end
	if damage.compiledOwnershipError then
		BBS.Log( "  compiled bodypart ownership fallback: %s",
			tostring( damage.compiledOwnershipError ) )
	end
	if damage.nearestHideableMesh then
		local nearest = damage.nearestHideableMesh
		BBS.Log( "    nearest eligible mesh=%d material=%s bodygroups=[%s] distance=%.3f triangle=%s",
			nearest.meshIndex, nearest.material,
			table.concat( nearest.bodygroupNames or {}, "," ),
			nearest.distance or -1, tostring( nearest.triangleIndex ) )
	end
	local limit = GetBool( "bbs_damage_verbose_uv", false )
		and math.Clamp( GetInt( "bbs_damage_uv_console_limit", 24 ), 0, 128 ) or 0
	for _, meshRecord in ipairs( damage.meshes or {} ) do
		BBS.Log( "    mesh=%d layer=%s bodygroups=[%s] material=%s triangles=%d uniqueUVs=%d",
			meshRecord.meshIndex, tostring( meshRecord.layerIndex ),
			table.concat( meshRecord.bodygroupNames, "," ),
			meshRecord.material, #meshRecord.triangles, #meshRecord.uvs )
		for index = 1, math.min( #meshRecord.uvs, limit ) do
			local uv = meshRecord.uvs[ index ]
			BBS.Log( "      uv[%d]=[%.6f %.6f]", index, uv.u, uv.v )
		end
		if limit > 0 and #meshRecord.uvs > limit then
			BBS.Log( "      ... %d more unique UVs", #meshRecord.uvs - limit )
		end
	end
	for _, materialRecord in ipairs( damage.materials or {} ) do
		local mask = materialRecord.mask
		BBS.Log( "    material=%s slot=%s match=%s status=%s shader=%s source=%s inherited=%s dropped=%s",
			materialRecord.material, tostring( materialRecord.submaterialIndex ),
			tostring( materialRecord.submaterialMatch ), tostring( materialRecord.status ),
			mask and mask.originalShader or "<pending>",
			mask and mask.materialSource or "<pending>",
			mask and mask.copiedParameterCount or "<pending>",
			mask and mask.droppedParameterCount or "<pending>" )
	end
end

local function ProfiledPrintDamageResult( hit )
	local started = BBS.PerfBegin and BBS.PerfBegin( hit ) or nil
	PrintDamageResult( hit )
	if BBS.PerfEnd then BBS.PerfEnd( hit, "Debug console output", started ) end
end

hook.Add( "BBS.MeshQueryCompleted", "BBS.BuildHideableBodygroupUVSet", function( hit, query )
	local damageStarted = SysTime()
	local function FinishPerformance( status )
		if BBS.PerfFinish then BBS.PerfFinish( hit, status ) end
	end
	local targetEnabled, _, targetReason = BBS.IsDamageTargetEnabled( hit.entity )
	if not targetEnabled then
		hit.damageUV = { ok = false, status = "target_disabled",
			error = targetReason or "target type is disabled" }
		FinishPerformance( "target_disabled" )
		return
	end
	if BBS.IsModelDamageAllowed then
		local modelAllowed, modelReason = BBS.IsModelDamageAllowed( hit.model )
		if not modelAllowed then
			hit.damageUV = { ok = false, status = "model_filter_blocked",
				error = modelReason or "model excluded by damage filter" }
			FinishPerformance( "model_filter_blocked" )
			return
		end
	end
	if not GetBool( "bbs_damage_enabled", true ) then
		hit.damageUV = { ok = false, status = "disabled", error = "UV damage is disabled" }
		FinishPerformance( "damage_disabled" )
		return
	end
	if not query or not query.ok then
		hit.damageUV = { ok = false, status = "mesh_query_failed",
			error = query and query.error or "mesh query unavailable" }
		FinishPerformance( "mesh_query_failed" )
		return
	end
	local meshData = query.cacheKey and BBS.ModelMeshCache[ query.cacheKey ] or nil
	if not meshData or meshData == false then
		hit.damageUV = { ok = false, status = "mesh_cache_missing",
			error = "cached source mesh data is unavailable" }
		FinishPerformance( "mesh_cache_missing" )
		return
	end

	local eligibilityStarted = BBS.PerfBegin and BBS.PerfBegin( hit ) or nil
	local eligibility, eligibilityError, eligibilityCacheHit =
		BBS.GetHideableMeshAnalysis( hit.entity, meshData )
	if BBS.PerfEnd then BBS.PerfEnd( hit, "Bodygroup eligibility", eligibilityStarted ) end
	if not eligibility then
		hit.damageUV = { ok = false, status = "bodygroup_analysis_failed",
			error = eligibilityError }
		FinishPerformance( "bodygroup_analysis_failed" )
		return
	end
	if #eligibility.bodygroups == 0 then
		local errorMessage = ( eligibility.blockedBodygroupCount or 0 ) > 0
			and string.format( "%d blank-capable bodygroup(s) were excluded by the bodygroup blacklist",
				eligibility.blockedBodygroupCount )
			or "no runtime bodygroup option resolved to an empty/blank/unnamed submodel (run bbs_damage_probe_bodygroups)"
		hit.damageUV = { ok = false, status = "no_hideable_bodygroups",
			error = errorMessage,
			bodygroups = eligibility.bodygroups,
			inspectedBodygroups = eligibility.inspectedBodygroups,
			blockedBodygroupCount = eligibility.blockedBodygroupCount }
		local debugStarted = GetBool( "bbs_damage_dump_debug", false )
			and BBS.PerfBegin and BBS.PerfBegin( hit ) or nil
		WriteBodygroupProbeBundle( hit, hit.damageUV, "automatic_no_eligible_bodygroups" )
		if BBS.PerfEnd then
			BBS.PerfEnd( hit, "Debug capture + bundle I/O", debugStarted )
		end
		if GetBool( "bbs_debug_console", false ) then ProfiledPrintDamageResult( hit ) end
		FinishPerformance( "no_hideable_bodygroups" )
		return
	end

	local uvStarted = BBS.PerfBegin and BBS.PerfBegin( hit ) or nil
	local damage = BuildAffectedUVResult( hit, query, meshData, eligibility )
	if BBS.PerfEnd then BBS.PerfEnd( hit, "Affected UV selection", uvStarted ) end
	local bookkeepingStarted = BBS.PerfBegin and BBS.PerfBegin( hit ) or nil
	damage.eligibilityCacheHit = eligibilityCacheHit
	damage.eligibilityBuildMilliseconds = eligibilityCacheHit
		and 0 or ( eligibility.buildMilliseconds or 0 )
	local nearestHideable = nil
	for meshIndex, groupMap in pairs( eligibility.meshGroups ) do
		local meshNearest = query.probe and query.probe.meshNearest
			and query.probe.meshNearest[ meshIndex ] or nil
		if meshNearest and ( not nearestHideable
		or meshNearest.distanceSquared < nearestHideable.distanceSquared ) then
			nearestHideable = {
				meshIndex = meshIndex,
				material = meshNearest.material,
				triangleIndex = meshNearest.triangleIndex,
				distanceSquared = meshNearest.distanceSquared,
				distance = math.sqrt( meshNearest.distanceSquared ),
				position = meshNearest.position,
				bodygroupNames = BodygroupHelpers.SortedNames( groupMap ),
			}
		end
	end
	damage.nearestHideableMesh = nearestHideable
	damage.totalMeshCount = #meshData.meshes
	damage.comparisonCount = eligibility.comparisonCount
	damage.comparisonBodygroupCount = eligibility.comparisonBodygroupCount
	damage.failedComparisons = eligibility.failedComparisons
	damage.ambiguousFingerprints = eligibility.ambiguousFingerprints
	damage.overriddenBodygroupCount = eligibility.overriddenBodygroupCount or 0
	damage.unresolvedOverrideCount = eligibility.unresolvedOverrideCount or 0
	damage.ownershipMode = eligibility.ownershipMode
	damage.compiledOwnership = eligibility.compiledOwnership == true
	damage.compiledOwnershipError = eligibility.compiledOwnershipError
	damage.directOwnershipBodygroupCount =
		eligibility.directOwnershipBodygroupCount or 0
	damage.applyRequested = GetBool( "bbs_damage_apply_materials", true ) and not hit.synthetic
	damage.uvPipelineMilliseconds = ( SysTime() - damageStarted ) * 1000
	hit.damageUV = damage
	if BBS.PerfEnd then
		BBS.PerfEnd( hit, "UV result bookkeeping", bookkeepingStarted )
	end

	if damage.affectedMaterialCount == 0 then
		damage.status = "no_hideable_mesh_hit"
	elseif damage.applyRequested then
		local queueStarted = BBS.PerfBegin and BBS.PerfBegin( hit ) or nil
		QueueMaterialDamage( hit, damage )
		if BBS.PerfEnd then BBS.PerfEnd( hit, "Material queue dispatch", queueStarted ) end
	else
		damage.status = hit.synthetic and "synthetic_uv_only" or "uv_only"
	end
	if GetBool( "bbs_debug_console", false ) then ProfiledPrintDamageResult( hit ) end
	if damage.status ~= "paint_queued" then FinishPerformance( damage.status ) end
end )

-- RT source copying and pixel capture require a 2D render hook. Running this
-- queue in PreRender made surface/render operations silently leave the RT at
-- its clear color on some clients.
hook.Add( "HUDPaint", "BBS.PaintHideableBodygroupDamage", function()
	local job = BBS.DamagePaintQueue[ 1 ]
	if not job then
		local refresh = BBS.DamageCompatibilityRefreshQueue[ 1 ]
		if not refresh then return end
		if BBS.TryBeginHeavyFrame
		and not BBS.TryBeginHeavyFrame( "damage-compatibility-refresh" ) then
			return
		end
		local ok, finished, errorMessage = pcall(
			ProcessCompatibilityRefresh, refresh )
		if not ok then
			errorMessage = finished
			finished = true
		end
		if finished then
			table.remove( BBS.DamageCompatibilityRefreshQueue, 1 )
			FinishCompatibilityRefreshQueueRecord( refresh )
			if errorMessage and GetBool( "bbs_debug_console", false ) then
				BBS.Log( "compatible material refresh skipped: %s",
					tostring( errorMessage ) )
			end
		elseif #BBS.DamageCompatibilityRefreshQueue > 1 then
			-- A material editor may still be creating this source. Rotate the
			-- unresolved record so one slow dependency cannot block unrelated masks.
			table.remove( BBS.DamageCompatibilityRefreshQueue, 1 )
			BBS.DamageCompatibilityRefreshQueue[
				#BBS.DamageCompatibilityRefreshQueue + 1 ] = refresh
		end
		return
	end
	local targetEnabled, _, targetReason = BBS.IsDamageTargetEnabled( job.entity )
	if not targetEnabled then
		table.remove( BBS.DamagePaintQueue, 1 )
		RTX.ReleasePreparedHashOnWriteJob( job )
		job.materialRecord.status = "target_disabled"
		job.materialRecord.error = targetReason or "target type is disabled"
		if BBS.PerfFinish then BBS.PerfFinish( job.hit, "target_disabled" ) end
		return
	end
	if BBS.TryBeginHeavyFrame
	and not BBS.TryBeginHeavyFrame( "damage-paint" ) then return end
	if not job.paintThread then
		job.paintThread = coroutine.create( function()
			return ApplyPaintJob( job )
		end )
	end
	local budgetMilliseconds = math.Clamp(
		GetFloat( "bbs_damage_projection_budget_ms", 6.25 ), 0.25, 50 )
	job.paintDeadline = SysTime() + budgetMilliseconds / 1000
	local resumeStarted = SysTime()
	local ok, success, errorMessage = coroutine.resume( job.paintThread )
	local resumeMilliseconds = math.max(
		( SysTime() - resumeStarted ) * 1000, 0 )
	job.paintCPUMilliseconds = ( job.paintCPUMilliseconds or 0 )
		+ resumeMilliseconds
	job.paintMaximumSliceMilliseconds = math.max(
		job.paintMaximumSliceMilliseconds or 0, resumeMilliseconds )
	if ok and coroutine.status( job.paintThread ) ~= "dead" then
		if success == "compatibility_source_pending"
		and #BBS.DamagePaintQueue > 1 then
			-- Preserve the coroutine and its captured hit, but let ready paint jobs
			-- proceed while AME/ABT finishes publishing this source.
			table.remove( BBS.DamagePaintQueue, 1 )
			BBS.DamagePaintQueue[ #BBS.DamagePaintQueue + 1 ] = job
		end
		return
	end
	table.remove( BBS.DamagePaintQueue, 1 )
	if job.rtxHashOnWritePreparationActive then
		RTX.ReleasePreparedHashOnWriteJob( job,
			job.materialRecord and job.materialRecord.mask or nil )
	end
	if BBS.PerfAddMilliseconds then
		local residual = math.max( ( job.paintCPUMilliseconds or 0 )
			- ( job.performanceAccountedMilliseconds or 0 ), 0 )
		BBS.PerfAddMilliseconds( job.hit, "Material apply overhead", residual )
	end
	if not ok then
		errorMessage = success
		success = false
	end
	local outputEnabled = not success or GetBool( "bbs_debug_console", false )
	local outputStarted = outputEnabled and BBS.PerfBegin
		and BBS.PerfBegin( job.hit ) or nil
	if not success then
		job.materialRecord.status = "apply_failed"
		job.materialRecord.error = tostring( errorMessage or "unknown paint error" )
		BBS.Log( "  UV material apply failed for %s: %s",
			job.materialRecord.material, job.materialRecord.error )
	elseif job.materialRecord.status == "no_projected_coverage" then
		if GetBool( "bbs_debug_console", false ) then
			BBS.Log( "  UV material skipped: material=%s slot=%d had no exact irregular-hull coverage",
				job.materialRecord.material, job.submaterialIndex )
		end
	elseif GetBool( "bbs_debug_console", false ) then
		local paint = job.materialRecord.mask.lastPaintDiagnostics or {}
		local damageState = BBS.DamageStates[ job.entity ]
		BBS.Log( "  UV material applied: material=%s slot=%d binding=%s rtxReason=%s sourceTriangles=%d projectedTriangles=%d rt=%s(%dx%d) source=%s ame=%s ameMaterial=%s abt=%s abtMaterial=%s signature=%s shader=%s inherited=%d dropped=%d alphatest=1 reference=%s alphaParam=%s nocull=%s forcedNoCull=%s base=%s preserveAlpha=%s alphaInit=%s vtfAlpha=%s vtfFormat=%s vtfFlags=0x%08X expand=%.1f feather=%.1f blurPasses=%d seamUnwrap=%s seamTriangles=%d",
			job.materialRecord.material, job.submaterialIndex,
			job.materialRecord.mask.submaterialOverrideApplied
				and ( job.materialRecord.mask.rtxDirectOverride
					and "SetSubMaterial+RTX-direct" or "SetSubMaterial" )
				or "editor-compatible RenderOverride",
			tostring( job.materialRecord.mask.rtxDirectOverrideReason ),
			#job.materialRecord.triangles,
			job.materialRecord.projectedTriangleCount or 0,
			job.materialRecord.mask.renderTargetName,
			job.materialRecord.mask.width, job.materialRecord.mask.height,
			job.materialRecord.mask.materialSource,
			tostring( job.materialRecord.mask.advancedMaterialEditor ),
			tostring( job.materialRecord.mask.advancedMaterialEditorMaterialName ),
			tostring( job.materialRecord.mask.advancedBodygroupTool ),
			tostring( job.materialRecord.mask.advancedBodygroupToolMaterialName ),
			tostring( job.materialRecord.mask.editedSourceSignature ),
			job.materialRecord.mask.originalShader,
			job.materialRecord.mask.copiedParameterCount,
			job.materialRecord.mask.droppedParameterCount,
			tostring( job.materialRecord.mask.alphaTestReference ),
			job.materialRecord.mask.alphaParameter == nil and "<absent>"
				or tostring( job.materialRecord.mask.alphaParameter ),
			tostring( job.materialRecord.mask.cloneParameters[ "$nocull" ] ),
			tostring( job.materialRecord.mask.forceNoCull ),
			tostring( job.materialRecord.mask.baseTextureName ),
			tostring( job.materialRecord.mask.preserveSourceAlpha ),
			tostring( job.materialRecord.mask.alphaInitialization ),
			tostring( job.materialRecord.mask.vtfMetadata
				and job.materialRecord.mask.vtfMetadata.hasAlpha ),
			tostring( job.materialRecord.mask.vtfMetadata
				and job.materialRecord.mask.vtfMetadata.imageFormat ),
			job.materialRecord.mask.vtfMetadata
				and job.materialRecord.mask.vtfMetadata.flags or 0,
			paint.expansion or 0, paint.feather or 0,
			paint.blurPasses or 0, tostring( paint.unwrapSeams ),
			paint.seamTriangleCount or 0 )
		if job.materialRecord.mask.rtxRefreshAttempted then
			BBS.Log( "  RTX refresh: success=%s count=%d %.2f ms cachePreserved=%s rebind=%s recompute=%s tracker=%s pipelineSkipped=%s hashOnWrite=%s previous=%s set=%s effective=%s restorePending=%s hashes=%s->%s ommProtected=%s ommHashes=%s renderFailures=%d lastDrawFailed=%s boundMasks=%s",
				tostring( job.materialRecord.mask.rtxRefreshSucceeded ),
				job.materialRecord.mask.rtxRefreshCount or 0,
				job.materialRecord.mask.rtxRefreshMilliseconds or 0,
				tostring( job.materialRecord.mask.rtxCacheInvalidationSkipped ),
				tostring( job.materialRecord.mask.rtxTextureRebindSucceeded ),
				tostring( job.materialRecord.mask.rtxMaterialRecomputeSucceeded ),
				tostring( job.materialRecord.mask.rtxTrackerSucceeded ),
				tostring( job.materialRecord.mask.rtxPipelineProcessSkipped ),
				tostring( job.materialRecord.mask.rtxHashOnWriteEnabledForPaint ),
				tostring( job.materialRecord.mask.rtxHashOnWritePreviousValue ),
				tostring( job.materialRecord.mask.rtxHashOnWriteSetSucceeded ),
				tostring( job.materialRecord.mask.rtxHashOnWriteEffectiveValue ),
				tostring( job.materialRecord.mask.rtxHashOnWriteRestorePending ),
				tostring( job.materialRecord.mask.rtxTextureHashesBefore ),
				tostring( job.materialRecord.mask.rtxTextureHashesAfter ),
				tostring( job.materialRecord.mask.rtxOMMProtectionSucceeded ),
				tostring( job.materialRecord.mask.rtxOMMProtectionInputHashes ),
				damageState and damageState.rtxRenderOverrideFailureCount or 0,
				tostring( damageState and damageState.rtxRenderOverrideLastDrawFailed ),
				tostring( damageState and damageState.rtxLastBoundMaskCount ) )
		end
		BBS.Log( "  paint timing: projection=%.2f ms raster=%.2f ms blur=%.2f ms alpha=%.2f ms totalPaint=%.2f ms cells=%d boundary=%d depth=%d/%d budgetLimited=%s bound=%d coarse=%s retries=%d localBounds=%s local/globalAngleCells=%d/%d missedSource=%d capped=%s rasterMode=%s polygons=%d primitives=%d batches=%d; total hit-to-apply %.2f ms; sharedCoverage=%s",
			paint.projectionMilliseconds or 0,
			paint.rasterMilliseconds or 0, paint.blurMilliseconds or 0,
			paint.alphaCompositeMilliseconds or 0,
			paint.paintMilliseconds or 0,
			paint.projectionVisitedCellCount or 0,
			paint.projectionBoundaryCellCount or 0,
			paint.projectionMaximumDepthReached or 0,
			paint.projectionRequestedDepth or paint.projectionDepth or 0,
			tostring( paint.projectionBudgetLimited ),
			paint.projectionConservativeUpperBound or 0,
			tostring( paint.projectionCoarseTerminal ),
			paint.projectionRetryCount or 0,
			tostring( paint.projectionLocalBounds ),
			paint.projectionAngularBoundCellCount or 0,
			paint.projectionGlobalAngularBoundCellCount or 0,
			paint.projectionMissedSourceTriangleCount or 0,
			tostring( paint.projectionCapped ),
			tostring( paint.rasterMode ), paint.rasterPolygonCount or 0,
			paint.rasterPrimitiveCount or 0, paint.rasterBatchCount or 0,
			job.hit.pipelineStarted and ( SysTime() - job.hit.pipelineStarted ) * 1000 or 0,
			tostring( job.materialRecord.mask.coverageTargetName ) )
		BBS.Log( "  projection scheduler: cpu=%.2f ms wall=%.2f ms yields=%d maxSlice=%.2f ms budget=%.2f ms/frame scratch=%dx%d persistent=%dx%d coverageCommit=%.2f ms paintJobMaxSlice=%.2f ms",
			paint.projectionMilliseconds or 0,
			paint.projectionWallMilliseconds or paint.projectionMilliseconds or 0,
			paint.projectionYieldCount or 0,
			paint.projectionMaximumSliceMilliseconds or 0,
			GetFloat( "bbs_damage_projection_budget_ms", 6.25 ),
			paint.coverageWidth or job.materialRecord.mask.width,
			paint.coverageHeight or job.materialRecord.mask.height,
			job.materialRecord.mask.width, job.materialRecord.mask.height,
			paint.coverageCommitMilliseconds or 0,
			job.paintMaximumSliceMilliseconds or 0 )
	end
	if outputEnabled and BBS.PerfEnd then
		BBS.PerfEnd( job.hit, "Debug console output", outputStarted )
	end

	local damage = job.hit.damageUV
	local finishedMaterialCount = 0
	for _, materialRecord in ipairs( damage and damage.materials or {} ) do
		if materialRecord.status == "applied"
		or materialRecord.status == "apply_failed"
		or materialRecord.status == "no_submaterial"
		or materialRecord.status == "invalid_submaterial"
		or materialRecord.status == "no_projected_coverage" then
			finishedMaterialCount = finishedMaterialCount + 1
		end
	end
	if damage and finishedMaterialCount >= damage.affectedMaterialCount then
		local failureCount = 0
		for _, materialRecord in ipairs( damage.materials or {} ) do
			if materialRecord.status == "apply_failed"
			or materialRecord.status == "no_submaterial"
			or materialRecord.status == "invalid_submaterial" then
				failureCount = failureCount + 1
			end
		end
		damage.status = damage.appliedMaterialCount > 0 and "applied"
			or failureCount > 0 and "apply_failed" or "no_projected_coverage"
		if BBS.PerfFinish then BBS.PerfFinish( job.hit, damage.status ) end
	end
end )

function BBS.GetDamageHUDStatus( hit )
	local damage = hit and hit.damageUV
	if not damage then return NL("UV damage: waiting for mesh analysis"), COLOR_PENDING end
	if not damage.ok then return NL("UV damage: ") .. tostring( damage.error or damage.status ), COLOR_SKIP end
	if damage.status == "paint_queued" then
		return string.format( NL("UV damage: %d meshes / %d materials / %d UVs | paint queue %d"),
			damage.affectedMeshCount, damage.affectedMaterialCount,
			damage.uvCount, #BBS.DamagePaintQueue ), COLOR_PENDING
	end
	if damage.status == "applied" then
		return string.format( NL("UV damage: %d material override(s) applied from %d triangles"),
			damage.appliedMaterialCount, damage.triangleCount ), COLOR_OK
	end
	if damage.status == "no_hideable_mesh_hit" then
		local nearest = damage.nearestHideableMesh
		if nearest then
			return string.format( NL("UV damage: no eligible bodygroup touch; nearest %s mesh is %.3f units away"),
				nearest.material, nearest.distance ), COLOR_SKIP
		end
		return NL("UV damage: removal hull did not touch a proven eligible-bodygroup mesh"), COLOR_SKIP
	end
	if damage.status == "no_projected_coverage" then
		return NL("UV damage: broad-phase mesh candidates had no exact irregular-hole coverage"),
			COLOR_SKIP
	end
	if damage.status == "apply_unavailable" then
		return NL("UV damage: affected materials could not be mapped to submaterial slots"), COLOR_ERROR
	end
	if damage.status == "apply_failed" then return NL("UV damage: material application failed"), COLOR_ERROR end
	return string.format( NL("UV damage: %d meshes / %d materials / %d unique UVs (%s)"),
		damage.affectedMeshCount, damage.affectedMaterialCount,
		damage.uvCount, damage.status ), COLOR_OK
end

local function DrawPreviewTriangle( coordinates, x, y, width, height,
	triangleIndex )
	local firstCoordinateU, firstCoordinateV = triangleIndex
		and ProjectedTriangleUV( coordinates, triangleIndex, 1 )
		or ProjectedTriangleUV( coordinates, 1 )
	local secondCoordinateU, secondCoordinateV = triangleIndex
		and ProjectedTriangleUV( coordinates, triangleIndex, 2 )
		or ProjectedTriangleUV( coordinates, 2 )
	local thirdCoordinateU, thirdCoordinateV = triangleIndex
		and ProjectedTriangleUV( coordinates, triangleIndex, 3 )
		or ProjectedTriangleUV( coordinates, 3 )
	if not isnumber( firstCoordinateU ) or not isnumber( firstCoordinateV )
	or not isnumber( secondCoordinateU ) or not isnumber( secondCoordinateV )
	or not isnumber( thirdCoordinateU ) or not isnumber( thirdCoordinateV ) then return end
	local minimumU = math.min( firstCoordinateU, secondCoordinateU, thirdCoordinateU )
	local maximumU = math.max( firstCoordinateU, secondCoordinateU, thirdCoordinateU )
	local minimumV = math.min( firstCoordinateV, secondCoordinateV, thirdCoordinateV )
	local maximumV = math.max( firstCoordinateV, secondCoordinateV, thirdCoordinateV )
	local firstU, lastU = TileShiftRange( minimumU, maximumU )
	local firstV, lastV = TileShiftRange( minimumV, maximumV )
	for shiftU = firstU, lastU do
		for shiftV = firstV, lastV do
			local firstX = x + ( firstCoordinateU + shiftU ) * width
			local firstY = y + ( firstCoordinateV + shiftV ) * height
			local secondX = x + ( secondCoordinateU + shiftU ) * width
			local secondY = y + ( secondCoordinateV + shiftV ) * height
			local thirdX = x + ( thirdCoordinateU + shiftU ) * width
			local thirdY = y + ( thirdCoordinateV + shiftV ) * height
			surface.DrawLine( firstX, firstY, secondX, secondY )
			surface.DrawLine( secondX, secondY, thirdX, thirdY )
			surface.DrawLine( thirdX, thirdY, firstX, firstY )
		end
	end
end

local function DrawPreviewCheckerboard( x, y, width, height )
	local cell = 12
	for row = 0, math.ceil( height / cell ) - 1 do
		for column = 0, math.ceil( width / cell ) - 1 do
			local bright = ( row + column ) % 2 == 0
			surface.SetDrawColor( bright and 105 or 62, bright and 105 or 62,
				bright and 110 or 67, 255 )
			surface.DrawRect( x + column * cell, y + row * cell,
				math.min( cell, width - column * cell ),
				math.min( cell, height - row * cell ) )
		end
	end
end

local function DrawUVOutline( materialRecord, x, y, width, height )
	render.SetScissorRect( x, y, x + width, y + height, true )
	surface.SetDrawColor( 40, 235, 255, 240 )
	if materialRecord.projectedTriangles then
		local projected = materialRecord.projectedTriangles
		for triangleIndex = 1, ProjectedTriangleCount( projected ) do
			DrawPreviewTriangle(
				projected, x, y, width, height, triangleIndex )
		end
	else
		for _, triangle in ipairs( materialRecord.triangles or {} ) do
			local transformed = TransformUVCoordinates( triangle.uv,
				materialRecord.mask and materialRecord.mask.baseTextureTransform )
			transformed = UnwrapUVTriangle( transformed,
				GetBool( "bbs_damage_uv_unwrap_seams", true ) )
			DrawPreviewTriangle( transformed, x, y, width, height )
		end
	end
	render.SetScissorRect( 0, 0, 0, 0, false )
end

local function FitPreviewRectangle( x, y, cellSize, textureWidth, textureHeight )
	textureWidth = math.max( textureWidth or 1, 1 )
	textureHeight = math.max( textureHeight or 1, 1 )
	local aspect = textureWidth / textureHeight
	local width, height
	if aspect >= 1 then
		width = cellSize
		height = math.max( math.floor( cellSize / aspect + 0.5 ), 1 )
	else
		height = cellSize
		width = math.max( math.floor( cellSize * aspect + 0.5 ), 1 )
	end
	return x + math.floor( ( cellSize - width ) * 0.5 ),
		y + math.floor( ( cellSize - height ) * 0.5 ), width, height
end

hook.Add( "HUDPaint", "BBS.DrawAffectedUVPreview", function()
	if not GetBool( "bbs_damage_uv_preview", false ) then return end
	local hit = BBS.LastHit
	local damage = hit and hit.damageUV
	local materialRecord = damage and damage.materials and damage.materials[ 1 ]
	if not materialRecord then return end
	local performanceStarted = BBS.PerfBeginBackground
		and BBS.PerfBeginBackground() or nil

	local size = 160
	local gap = 8
	local width = size * 4 + gap * 3
	local x = ScrW() - width - 24
	local y = 24
	local textureY = y + 20
	draw.RoundedBox( 6, x - 8, y - 8, width + 16, size + 74,
		Color( 10, 12, 16, 230 ) )
	local mask = materialRecord.mask
	if mask then EnsureDamagePreviewMaterials( mask ) end
	local panels = {
		{ label = NL("Original RGB"), material = mask and mask.originalPreviewMaterial },
		{ label = NL("Edited + alpha"), material = mask and mask.previewMaterial, uv = true },
		{ label = NL("Edited RGB only"), material = mask and mask.rgbPreviewMaterial, uv = true },
		{ label = NL("Last hit coverage"), material = mask and mask.coveragePreviewMaterial },
	}
	for panelIndex, panel in ipairs( panels ) do
		local panelX = x + ( panelIndex - 1 ) * ( size + gap )
		local drawX, drawY, drawWidth, drawHeight = FitPreviewRectangle(
			panelX, textureY, size,
			mask and mask.width or size, mask and mask.height or size )
		draw.SimpleText( panel.label, "DermaDefaultBold", panelX, y,
			Color( 225, 230, 238 ), TEXT_ALIGN_LEFT, TEXT_ALIGN_TOP )
		DrawPreviewCheckerboard( drawX, drawY, drawWidth, drawHeight )
		if panel.material then
			surface.SetMaterial( panel.material )
			surface.SetDrawColor( 255, 255, 255, 255 )
			surface.DrawTexturedRect( drawX, drawY, drawWidth, drawHeight )
		end
		if panel.uv then
			DrawUVOutline( materialRecord, drawX, drawY, drawWidth, drawHeight )
		end
	end

	local paint = mask and mask.lastPaintDiagnostics or {}
	draw.SimpleText( string.format( NL("%s | %d source / %d projected tris | %d UVs | expand=%.1f feather=%.1f passes=%d seams=%d"),
		materialRecord.material, #materialRecord.triangles,
		materialRecord.projectedTriangleCount or 0, #materialRecord.uvs,
		paint.expansion or 0, paint.feather or 0, paint.blurPasses or 0,
		paint.seamTriangleCount or 0 ),
		"DermaDefaultBold", x, textureY + size + 7, Color( 225, 230, 238 ),
		TEXT_ALIGN_LEFT, TEXT_ALIGN_TOP )
	if mask and mask.lastDebugFolder then
		draw.SimpleText( NL("dump: data/") .. mask.lastDebugFolder,
			"DermaDefault", x, textureY + size + 24, Color( 170, 185, 205 ),
			TEXT_ALIGN_LEFT, TEXT_ALIGN_TOP )
	end
	if BBS.PerfEndBackground then
		BBS.PerfEndBackground( "Frame: texture inspector", performanceStarted )
	end
end )

local function RestoreDamageState( entity, state )
	if not IsValid( entity ) then return end
	RestoreRTXDamageRenderOverride( entity, state )
	local refreshAdvancedMaterialEditor = false
	for submaterialIndex, mask in pairs( state.masks or {} ) do
		if mask.submaterialOverrideApplied ~= false then
			entity:SetSubMaterial( submaterialIndex,
				mask.previousOverride ~= "" and mask.previousOverride or nil )
		end
		refreshAdvancedMaterialEditor = refreshAdvancedMaterialEditor
			or mask.advancedMaterialEditor == true
	end
	if refreshAdvancedMaterialEditor then
		-- Let BBS's caller finish removing/transferring its state before AME
		-- recomputes client-owned previews. This also handles AME rule edits that
		-- occurred while the damage material was active.
		timer.Simple( 0, function()
			if not IsValid( entity ) then return end
			local advmat = _G.AdvMat
			local apply = istable( advmat ) and advmat.Apply or nil
			if istable( apply ) and isfunction( apply.Refresh ) then
				pcall( apply.Refresh, entity )
			end
		end )
	end
end

local function EntityHasPendingDamageWork( entity )
	if not IsValid( entity ) then return false end
	if BBS.PendingHitBursts and BBS.PendingHitBursts[ entity ] then return true end
	for _, record in ipairs( BBS.HitDispatchQueue or {} ) do
		if record.entity == entity then return true end
	end
	for _, deferred in ipairs( BBS.DeferredHitMeshQueue or {} ) do
		if deferred.hit and deferred.hit.entity == entity then return true end
	end
	for _, query in ipairs( BBS.MeshQueryQueue or {} ) do
		if query.hit and query.hit.entity == entity then return true end
	end
	for _, job in ipairs( BBS.DamagePaintQueue or {} ) do
		if job.entity == entity then return true end
	end
	for _, refresh in ipairs( BBS.DamageCompatibilityRefreshQueue or {} ) do
		if refresh.entity == entity then return true end
	end
	return false
end

local function QueueDeathDamageTransfer( serial, sourceIndex, ragdollIndex,
	expectedModel )
	if sourceIndex <= 0 or ragdollIndex <= 0 then return end
	local existing = BBS.PendingDeathDamageTransfers[ ragdollIndex ]
	if existing and existing.serial == serial then return end
	local now = SysTime()
	BBS.PendingDeathDamageTransfers[ ragdollIndex ] = {
		serial = serial,
		sourceIndex = sourceIndex,
		ragdollIndex = ragdollIndex,
		expectedModel = NormalizeMaterialPath( expectedModel ),
		createdAt = now,
	}
end

local function ResolveTransferSource( transfer )
	local source = Entity( transfer.sourceIndex )
	if IsValid( source ) then
		local kind = BBS.GetDamageTargetKind( source )
		local sourceModel = NormalizeMaterialPath( source:GetModel() or "" )
		if ( kind == "player" or kind == "npc" )
		and ( transfer.expectedModel == ""
			or sourceModel == transfer.expectedModel ) then
			local state = BBS.DamageStates[ source ]
			if state then return source, state, false end
			return source, nil, false
		end
	end

	local orphan = BBS.OrphanedDamageStates[ transfer.sourceIndex ]
	if not orphan then return nil, nil, false end
	if transfer.expectedModel ~= "" and orphan.model ~= transfer.expectedModel then
		return nil, nil, false
	end
	return nil, orphan.state, true
end

local function TransferDamageStateToDeathRagdoll( transfer )
	local ragdoll = Entity( transfer.ragdollIndex )
	if not IsValid( ragdoll ) or ragdoll:GetClass() ~= "prop_ragdoll" then
		return false, "waiting for death ragdoll", false
	end
	local ragdollModel = NormalizeMaterialPath( ragdoll:GetModel() or "" )
	if transfer.expectedModel ~= "" and ragdollModel ~= transfer.expectedModel then
		return false, "death ragdoll model does not match", true
	end

	local source, state, orphaned = ResolveTransferSource( transfer )
	if not state then
		if source and EntityHasPendingDamageWork( source ) then
			return false, "waiting for source damage state", false
		end
		return false, "source has no transferable damage state", true
	end
	if source and EntityHasPendingDamageWork( source ) then
		return false, "waiting for final living-target damage work", false
	end

	local ragdollMaterials = ragdoll:GetMaterials() or {}
	local compatibleMasks = {}
	local compatibleCount = 0
	for submaterialIndex, mask in pairs( state.masks or {} ) do
		local corpsePath = NormalizeMaterialPath(
			ragdollMaterials[ submaterialIndex + 1 ] or "" )
		if corpsePath ~= ""
		and corpsePath == NormalizeMaterialPath( mask.originalPath ) then
			compatibleMasks[ submaterialIndex ] = mask
			compatibleCount = compatibleCount + 1
		end
	end
	if compatibleCount == 0 then
		return false, "no compatible damaged material slots on death ragdoll", true
	end

	-- Move ownership of the render targets. Sharing them with the player would
	-- make a later life repaint the corpse, while copying a full 2K/4K target at
	-- death would add a large hitch.
	if source and BBS.DamageStates[ source ] == state then
		RestoreDamageState( source, state )
		BBS.DamageStates[ source ] = nil
	else
		state.rtxRenderOverrideInstalled = false
		state.rtxRenderOverride = nil
		state.previousRenderOverride = nil
	end
	if orphaned then BBS.OrphanedDamageStates[ transfer.sourceIndex ] = nil end

	local displaced = BBS.DamageStates[ ragdoll ]
	if displaced and displaced ~= state then RestoreDamageState( ragdoll, displaced ) end
	state.entity = ragdoll
	state.model = ragdollModel
	state.masks = compatibleMasks
	state.deathTransferSerial = transfer.serial
	state.deathTransferSourceIndex = transfer.sourceIndex
	BBS.DamageStates[ ragdoll ] = state

	local installRTX = false
	for submaterialIndex, mask in pairs( compatibleMasks ) do
		mask.entity = ragdoll
		mask.previousOverride = ragdoll:GetSubMaterial( submaterialIndex ) or ""
		mask.compatibilitySourceSnapshot = mask.directMaterialOwnership == true
		if mask.overrideApplied then
			if mask.directMaterialOwnership then
				mask.submaterialOverrideApplied = false
			else
				ragdoll:SetSubMaterial( submaterialIndex,
					"!" .. mask.materialName )
				mask.submaterialOverrideApplied = true
			end
			installRTX = true
		end
	end
	if installRTX then InstallRTXDamageRenderOverride( ragdoll, state ) end
	if GetBool( "bbs_debug_console", false ) then
		BBS.Log( "preserved %d damaged material mask(s) on death ragdoll ent=%d from ent=%d",
			compatibleCount, ragdoll:EntIndex(), transfer.sourceIndex )
	end
	return true
end

net.Receive( BBS.NET_TRANSFER_DEATH_DAMAGE, function()
	QueueDeathDamageTransfer( net.ReadUInt( 16 ), net.ReadUInt( 16 ),
		net.ReadUInt( 16 ), net.ReadString() )
end )

hook.Add( "OnEntityCreated", "BBS.DiscoverDeathDamageTransfer", function( entity )
	if not IsValid( entity ) or entity:GetClass() ~= "prop_ragdoll" then return end
	-- Networked transfer metadata can arrive many frames later on a slow client.
	-- The weak-key table cleans itself when the ragdoll disappears, so readiness
	-- rather than elapsed wall time determines this record's lifetime.
	BBS.PendingDeathRagdollDiscovery[ entity ] = true
end )

hook.Add( "Think", "BBS.TransferDeathDamage", function()
	local now = SysTime()
	for ragdoll in pairs( BBS.PendingDeathRagdollDiscovery ) do
		if not IsValid( ragdoll ) then
			BBS.PendingDeathRagdollDiscovery[ ragdoll ] = nil
		else
			local sourceIndex = ragdoll:GetNW2Int(
				"BBS.DamageSourceEntIndex", -1 )
			if sourceIndex > 0 then
				QueueDeathDamageTransfer(
					ragdoll:GetNW2Int( "BBS.DamageTransferSerial", 0 ),
					sourceIndex, ragdoll:EntIndex(),
					ragdoll:GetNW2String( "BBS.DamageSourceModel", "" ) )
				BBS.PendingDeathRagdollDiscovery[ ragdoll ] = nil
			end
		end
	end

	for ragdollIndex, transfer in pairs( BBS.PendingDeathDamageTransfers ) do
		local transferred, reason, terminal =
			TransferDamageStateToDeathRagdoll( transfer )
		if transferred or terminal then
			if not transferred and GetBool( "bbs_debug_console", false ) then
				BBS.Log( "death damage transfer rejected for ragdoll ent=%d: %s",
					ragdollIndex, tostring( reason ) )
			end
			BBS.PendingDeathDamageTransfers[ ragdollIndex ] = nil
		end
	end

	for sourceIndex, orphan in pairs( BBS.OrphanedDamageStates ) do
		local referenced = false
		for _, transfer in pairs( BBS.PendingDeathDamageTransfers ) do
			if transfer.sourceIndex == sourceIndex then
				referenced = true
				break
			end
		end
		-- Never expire a state while a real transfer is waiting on slow pending
		-- paint work. Unreferenced states are only leak protection for servers that
		-- never create or network a corresponding death ragdoll.
		if not referenced
		and now - ( orphan.createdAt or now ) >= 120 then
			BBS.OrphanedDamageStates[ sourceIndex ] = nil
		end
	end
end )

function BBS.ClearAllDamage()
	local count = 0
	for entity, state in pairs( BBS.DamageStates ) do
		if IsValid( entity ) then
			RestoreDamageState( entity, state )
			count = count + 1
		end
	end
	for _, job in ipairs( BBS.DamagePaintQueue ) do
		RTX.ReleasePreparedHashOnWriteJob( job,
			job.materialRecord and job.materialRecord.mask or nil )
	end
	BBS.DamageStates = {}
	BBS.DamagePaintQueue = {}
	BBS.DamageCompatibilityRefreshQueue = {}
	BBS.DamageCompatibilityRefreshQueued =
		setmetatable( {}, { __mode = "k" } )
	BBS.RTXDamageProbeQueue = {}
	BBS.OrphanedDamageStates = {}
	BBS.PendingDeathDamageTransfers = {}
	BBS.PendingDeathRagdollDiscovery = setmetatable( {}, { __mode = "k" } )
	for _, hit in ipairs( BBS.DebugHits or {} ) do hit.damageUV = nil end
	return count
end

cvars.AddChangeCallback( "bbs_damage_layer_limit", function( _, oldValue, newValue )
	if ( tonumber( oldValue ) or 0 ) > 0
	or ( tonumber( newValue ) or 0 ) <= 0 then return end
	-- Infinite mode intentionally skips the CPU hole-history raster. There is no
	-- accurate RT readback path for reconstructing that history later, so clear
	-- old visual masks once when entering finite-layer mode rather than allowing
	-- visible holes to become false occluders.
	if next( BBS.DamageStates or {} ) ~= nil then
		local count = BBS.ClearAllDamage()
		if GetBool( "bbs_debug_console", false ) then
			BBS.Log( "cleared %d damaged entities while enabling finite layer tracking",
				count )
		end
	end
end, "BBS.ResetInfiniteDamageForFiniteLayers" )

function BBS.ClearEntityDamage( entity )
	local state = BBS.DamageStates[ entity ]
	if not state then return false end
	if IsValid( entity ) then RestoreDamageState( entity, state ) end
	for _, mask in pairs( state.masks or {} ) do
		BBS.RTXDamageProbeQueue[ mask ] = nil
	end
	BBS.DamageStates[ entity ] = nil
	for index = #BBS.DamagePaintQueue, 1, -1 do
		if BBS.DamagePaintQueue[ index ].entity == entity then
			RTX.ReleasePreparedHashOnWriteJob(
				BBS.DamagePaintQueue[ index ],
				BBS.DamagePaintQueue[ index ].materialRecord
					and BBS.DamagePaintQueue[ index ].materialRecord.mask or nil )
			table.remove( BBS.DamagePaintQueue, index )
		end
	end
	for index = #BBS.DamageCompatibilityRefreshQueue, 1, -1 do
		if BBS.DamageCompatibilityRefreshQueue[ index ].entity == entity then
			table.remove( BBS.DamageCompatibilityRefreshQueue, index )
		end
	end
	BBS.DamageCompatibilityRefreshQueued[ entity ] = nil
	return true
end

local function ClearDamageTargetKind( targetKind )
	local clear = {}
	for entity in pairs( BBS.DamageStates ) do
		if not IsValid( entity )
		or BBS.GetDamageTargetKind( entity ) == targetKind then
			clear[ #clear + 1 ] = entity
		end
	end
	for _, entity in ipairs( clear ) do BBS.ClearEntityDamage( entity ) end
	if BBS.ClearPendingHitWork then BBS.ClearPendingHitWork( targetKind ) end
end

-- Remove the pre-0.16.1 auto-refresh survivor which deliberately erased a
-- player's masks at death. Death masks are now handed to the server ragdoll.
hook.Remove( "Think", "BBS.ClearDeadPlayerDamage" )

local function UpdateDamageMaskNoCull( mask, forceNoCull )
	if not mask or not mask.material then return end
	local inherited = mask.inheritedNoCullParameter
	local desired = forceNoCull and 1 or ( tonumber( inherited ) or 0 )
	local ok = pcall( mask.material.SetInt, mask.material, "$nocull", desired )
	if ok and isfunction( mask.material.Recompute ) then
		pcall( mask.material.Recompute, mask.material )
	end
	mask.forceNoCull = forceNoCull
	if forceNoCull then
		mask.cloneParameters[ "$nocull" ] = "1"
	else
		mask.cloneParameters[ "$nocull" ] = inherited
	end
	if mask.generatedVMT then
		mask.generatedVMT = GeneratedVMTText(
			mask.originalShader, mask.cloneParameters )
	end
end

cvars.AddChangeCallback( "bbs_damage_force_nocull", function( _, _, value )
	local enabled = tonumber( value ) ~= 0
	timer.Simple( 0, function()
		for _, state in pairs( BBS.DamageStates ) do
			for _, mask in pairs( state.masks or {} ) do
				UpdateDamageMaskNoCull( mask, enabled )
			end
		end
	end )
end, "BBS.UpdateDamageMaterialNoCull" )

cvars.AddChangeCallback( "bbs_enabled", function( _, _, value )
	if tonumber( value ) == 0 then
		BBS.ClearAllDamage()
		if BBS.CancelBackgroundMeshWork then
			BBS.CancelBackgroundMeshWork( "addon was disabled" )
		end
		if BBS.ClearPendingHitWork then BBS.ClearPendingHitWork() end
	end
end, "BBS.ClearDamageWhenDisabled" )

cvars.AddChangeCallback( "bbs_damage_living_players", function( _, _, value )
	if tonumber( value ) == 0 then ClearDamageTargetKind( "player" ) end
end, "BBS.ClearLivingPlayerDamageWhenDisabled" )

cvars.AddChangeCallback( "bbs_damage_living_npcs", function( _, _, value )
	if tonumber( value ) == 0 then ClearDamageTargetKind( "npc" ) end
end, "BBS.ClearLivingNPCDamageWhenDisabled" )

hook.Add( "EntityRemoved", "BBS.RemoveDamageState", function( entity, fullUpdate )
	local state = BBS.DamageStates[ entity ]
	if state and not fullUpdate and BBS.IsLivingDamageTarget( entity ) then
		-- NPC entities usually disappear before their death-ragdoll network
		-- message resolves. Keep only the small state table/resource references
		-- briefly, keyed by the original EntIndex, then validate model/material
		-- slots before attaching them to any ragdoll.
		BBS.OrphanedDamageStates[ entity:EntIndex() ] = {
			state = state,
			model = NormalizeMaterialPath( entity:GetModel() or state.model or "" ),
			createdAt = SysTime(),
		}
	end
	for _, mask in pairs( state and state.masks or {} ) do
		BBS.RTXDamageProbeQueue[ mask ] = nil
	end
	BBS.DamageStates[ entity ] = nil
	BBS.PendingDeathRagdollDiscovery[ entity ] = nil
	BBS.PendingDeathDamageTransfers[ entity:EntIndex() ] = nil
	for index = #BBS.DamagePaintQueue, 1, -1 do
		if BBS.DamagePaintQueue[ index ].entity == entity then
			RTX.ReleasePreparedHashOnWriteJob(
				BBS.DamagePaintQueue[ index ],
				BBS.DamagePaintQueue[ index ].materialRecord
					and BBS.DamagePaintQueue[ index ].materialRecord.mask or nil )
			table.remove( BBS.DamagePaintQueue, index )
		end
	end
	for index = #BBS.DamageCompatibilityRefreshQueue, 1, -1 do
		if BBS.DamageCompatibilityRefreshQueue[ index ].entity == entity then
			table.remove( BBS.DamageCompatibilityRefreshQueue, index )
		end
	end
	BBS.DamageCompatibilityRefreshQueued[ entity ] = nil
end )

local function ReadRTXConfigForProbe( key )
	local config = _G.RemixConfig
	local getConfig = istable( config ) and config.GetConfigVariable or nil
	if not isfunction( getConfig ) then return "<unavailable>" end
	local ok, value = pcall( getConfig, key )
	return ok and tostring( value or "" ) or ( "<error: " .. tostring( value ) .. ">" )
end

local function BuildRTXGlobalProbeText()
	local lines = {
		"Procedural Bodygroup Destruction RTX probe",
		"addon_version=" .. tostring( BBS.Version ),
		"created=" .. os.date( "%Y-%m-%d %H:%M:%S" ),
		"frame=" .. tostring( FrameNumber() ),
		"rtx_detected=" .. tostring( RTX.IsClient() ),
		"rtx_detection_reason=" .. tostring( RTX.DetectionReason() ),
		RTX.HashOnWriteKey .. "=" .. ReadRTXConfigForProbe( RTX.HashOnWriteKey ),
		RTX.OMMIgnoreKey .. "=" .. ReadRTXConfigForProbe( RTX.OMMIgnoreKey ),
		"rtx.opacityMicromap.enable="
			.. ReadRTXConfigForProbe( "rtx.opacityMicromap.enable" ),
		"rtx.opacityMicromap.enableBinding="
			.. ReadRTXConfigForProbe( "rtx.opacityMicromap.enableBinding" ),
		"rtx.keepTexturesForTagging="
			.. ReadRTXConfigForProbe( "rtx.keepTexturesForTagging" ),
		"rtx.hashCollisionDetection.enable="
			.. ReadRTXConfigForProbe( "rtx.hashCollisionDetection.enable" ),
		"",
	}

	local resource = _G.RemixResource
	local getStats = istable( resource ) and resource.GetVramStats or nil
	if isfunction( getStats ) then
		local ok, stats = pcall( getStats )
		lines[ #lines + 1 ] = "[VRAM]"
		if ok and istable( stats ) then
			local keys = {}
			for key in pairs( stats ) do keys[ #keys + 1 ] = tostring( key ) end
			table.sort( keys )
			for _, key in ipairs( keys ) do
				lines[ #lines + 1 ] = key .. "=" .. tostring( stats[ key ] )
			end
		else
			lines[ #lines + 1 ] = "error=" .. tostring( stats )
		end
	else
		lines[ #lines + 1 ] = "[VRAM]\nunavailable"
	end

	local dumpRows = {}
	local remixMaterial = _G.RemixMaterial
	local dump = istable( remixMaterial )
		and remixMaterial.DumpAllTextureHashes or nil
	if isfunction( dump ) then
		local ok, rows = pcall( dump )
		if ok and istable( rows ) then dumpRows = rows end
	end
	lines[ #lines + 1 ] = ""
	lines[ #lines + 1 ] = "[Bridge-wide BBS texture pointers]"
	local bridgeCount = 0
	for _, row in pairs( dumpRows ) do
		if istable( row ) and string.find(
			RTX.NormalizeMaterialName( row.material ), "bbs_damage_mat_", 1, true ) then
			bridgeCount = bridgeCount + 1
			lines[ #lines + 1 ] = string.format(
				"material=%s texture=%s current_hash=%s",
				tostring( row.material ), tostring( row.texture ),
				tostring( row.hash ) )
		end
	end
	if bridgeCount == 0 then lines[ #lines + 1 ] = "<none>" end

	local entityCount, maskCount = 0, 0
	for entity, state in pairs( BBS.DamageStates or {} ) do
		if IsValid( entity ) then
			entityCount = entityCount + 1
			for submaterialIndex, mask in pairs( state.masks or {} ) do
				maskCount = maskCount + 1
				local hashes, hashError =
					RTX.ReadTextureHashArray( mask.materialName )
				local entries, bridgeError =
					RTX.ReadBridgeEntries( mask.materialName )
				lines[ #lines + 1 ] = ""
				lines[ #lines + 1 ] = string.format(
					"[Entity %d slot %d]", entity:EntIndex(), submaterialIndex )
				lines[ #lines + 1 ] = "model=" .. tostring( entity:GetModel() )
				lines[ #lines + 1 ] = "source_material=" .. tostring( mask.originalPath )
				lines[ #lines + 1 ] = "generated_material=!" .. tostring( mask.materialName )
				lines[ #lines + 1 ] = "render_target="
					.. tostring( mask.renderTargetName ) .. " "
					.. tostring( mask.width ) .. "x" .. tostring( mask.height )
				lines[ #lines + 1 ] = "source_submaterial_override="
					.. tostring( entity:GetSubMaterial( submaterialIndex ) )
				lines[ #lines + 1 ] = "current_hashes="
					.. ( #hashes > 0 and table.concat( hashes, "," ) or "<none>" )
				lines[ #lines + 1 ] = "current_hash_error=" .. tostring( hashError )
				lines[ #lines + 1 ] = "bridge_variant_count=" .. tostring( #entries )
				lines[ #lines + 1 ] = "bridge_error=" .. tostring( bridgeError )
				for _, entry in ipairs( entries ) do
					lines[ #lines + 1 ] = "bridge material=" .. entry.material
						.. " texture=" .. entry.texture .. " current_hash=" .. entry.hash
				end
				lines[ #lines + 1 ] = "refresh_count=" .. tostring( mask.rtxRefreshCount )
				lines[ #lines + 1 ] = "cache_invalidation_skipped="
					.. tostring( mask.rtxCacheInvalidationSkipped )
				lines[ #lines + 1 ] = "omm_protection_succeeded="
					.. tostring( mask.rtxOMMProtectionSucceeded )
				lines[ #lines + 1 ] = "omm_protection_input_hashes="
					.. tostring( mask.rtxOMMProtectionInputHashes )
				lines[ #lines + 1 ] = RTX.BuildIdentityHistoryText( mask )
			end
		end
	end
	lines[ #lines + 1 ] = ""
	lines[ #lines + 1 ] = string.format(
		"summary_entities=%d summary_masks=%d pending_hash_probes=%d bridge_rows=%d",
		entityCount, maskCount, table.Count( BBS.RTXDamageProbeQueue or {} ), bridgeCount )
	return table.concat( lines, "\n" ) .. "\n"
end

concommand.Add( "bbs_damage_clear", function()
	BBS.Log( "cleared transparent UV damage from %d entities", BBS.ClearAllDamage() )
end, nil, "Restore original submaterials and clear queued UV damage." )

concommand.Add( "bbs_damage_dump_last", function()
	if not BBS.LastHit then
		BBS.Log( "UV damage probe unavailable: shoot an enabled target first" )
		return
	end
	PrintDamageResult( BBS.LastHit )
end, nil, "Print affected eligible meshes, materials, and unique UV coordinates." )

concommand.Add( "bbs_damage_probe_material", function()
	local hit = BBS.LastHit
	local record = hit and hit.damageUV and hit.damageUV.materials
		and hit.damageUV.materials[ 1 ] or nil
	local mask = record and record.mask or nil
	if not mask then
		BBS.Log( "material probe unavailable: wait for an affected material to apply" )
		return
	end
	BBS.Log( "--- damaged material clone: source=%s original=%s shader=%s override=!%s rt=%s(%dx%d) base=%s alphaSource=%s preserveAlpha=%s alphaInit=%s vtfAlpha=%s format=%s flags=0x%08X ---",
		mask.materialSource, mask.originalPath, mask.originalShader,
		mask.materialName, mask.renderTargetName, mask.width, mask.height,
		mask.baseTextureName,
		tostring( mask.alphaStyleSource ), tostring( mask.preserveSourceAlpha ),
		tostring( mask.alphaInitialization ),
		tostring( mask.vtfMetadata and mask.vtfMetadata.hasAlpha ),
		tostring( mask.vtfMetadata and mask.vtfMetadata.imageFormat ),
		mask.vtfMetadata and mask.vtfMetadata.flags or 0 )
	BBS.Log( "  Advanced Material Editor: detected=%s material=%s override=%s preview=%s clientOwned=%s scope=%s effectiveParams=%d generatedTextures=%d appliedGenerated=%d resolveError=%s buildError=%s",
		tostring( mask.advancedMaterialEditor ),
		tostring( mask.advancedMaterialEditorMaterialName ),
		tostring( mask.advancedMaterialEditorOverride ),
		tostring( mask.advancedMaterialEditorPreview ),
		tostring( mask.advancedMaterialEditorClientOwned ),
		tostring( mask.advancedMaterialEditorRuleScope ),
		mask.advancedMaterialEditorParameterCount or 0,
		mask.advancedMaterialEditorGeneratedTextureCount or 0,
		mask.advancedMaterialEditorGeneratedTexturesApplied or 0,
		tostring( mask.advancedMaterialEditorResolveError ),
		tostring( mask.advancedMaterialEditorBuildError ) )
	BBS.Log( "  Advanced Bodygroup Tool: detected=%s identity=%s material=%s target=%s alphaComposited=%s alphaError=%s sourceSignature=%s directOwnership=%s liveTextures=%d liveMatrices=%d liveErrors=%s",
		tostring( mask.advancedBodygroupTool ),
		tostring( mask.advancedBodygroupToolIdentity ),
		tostring( mask.advancedBodygroupToolMaterialName ),
		tostring( mask.advancedBodygroupToolTargetName ),
		tostring( mask.advancedBodygroupToolAlphaComposited ),
		tostring( mask.advancedBodygroupToolAlphaError ),
		tostring( mask.editedSourceSignature ),
		tostring( mask.directMaterialOwnership ),
		mask.liveTextureObjectsApplied or 0,
		mask.liveMatrixObjectsApplied or 0,
		table.concat( mask.liveObjectErrors or {}, " | " ) )
	PrintGeneratedMaterialVMT( mask )
	PrintTable( mask.cloneParameters or {} )
end, nil, "Dump the exact sanitized VMT parameters used for the last material clone." )

concommand.Add( "bbs_damage_probe_rtx", function()
	file.CreateDir( "bbs_debug" )
	local path = "bbs_debug/rtx_probe_" .. os.date( "%Y%m%d_%H%M%S" ) .. ".txt"
	local output = BuildRTXGlobalProbeText()
	file.Write( path, output )
	BBS.Log( "RTX probe wrote garrysmod/data/%s", path )
	BBS.Log( "  OMM protected hashes=%d updates=%d pending probes=%d",
		#( BBS.RTXOpacityMicromapIgnore.orderedHashes or {} ),
		BBS.RTXOpacityMicromapIgnore.updateCount or 0,
		table.Count( BBS.RTXDamageProbeQueue or {} ) )
end, nil, "Write current RTX texture pointers, hashes, OMM state, and history." )

concommand.Add( "bbs_damage_status", function()
	local entityCount = 0
	local maskCount = 0
	local rtxDirectEntityCount = 0
	for entity, state in pairs( BBS.DamageStates ) do
		if IsValid( entity ) then
			entityCount = entityCount + 1
			maskCount = maskCount + table.Count( state.masks or {} )
			if state.rtxRenderOverrideInstalled
			and entity.RenderOverride == state.rtxRenderOverride then
				rtxDirectEntityCount = rtxDirectEntityCount + 1
			end
		end
	end
	local smoothing = DamageSmoothingSettings()
	BBS.Log( "UV damage status: materialFormat=%d bodygroupFilter=%d enabled=%s apply=%s layerLimit=%d forceNoCull=%s rtxDetected=%s rtxReason=%s rtxDirectEnabled=%s rtxDirectEntities=%d rtxOMMProtected=%d rtxProbeQueue=%d dumpBundles=%s validateCopy=%s printVMT=%s preview=%s entities=%d masks=%d paintQueue=%d eligibilityCache=%d templates=%d sharedCoverage=%d createdMaterials=%d maskResolution=%s expand=%.1f feather=%.1f blurPasses=%d seamUnwrap=%s projectionDepth=%d projectionTolerance=%.3f projectionCap=%d localBounds=%s batchRaster=%s",
		DAMAGE_MATERIAL_FORMAT, BODYGROUP_FILTER_FORMAT,
		tostring( GetBool( "bbs_damage_enabled", true ) ),
		tostring( GetBool( "bbs_damage_apply_materials", true ) ),
		math.max( GetInt( "bbs_damage_layer_limit", 0 ), 0 ),
		tostring( GetBool( "bbs_damage_force_nocull", true ) ),
		tostring( RTX.IsClient() ),
		tostring( RTX.DetectionReason() ),
		tostring( GetBool( "bbs_damage_rtx_direct_override", true ) ),
		rtxDirectEntityCount,
		#( BBS.RTXOpacityMicromapIgnore.orderedHashes or {} ),
		table.Count( BBS.RTXDamageProbeQueue or {} ),
		tostring( GetBool( "bbs_damage_dump_debug", false ) ),
		tostring( GetBool( "bbs_damage_validate_copy", false ) ),
		tostring( GetBool( "bbs_damage_print_vmt", false ) ),
		tostring( GetBool( "bbs_damage_uv_preview", false ) ),
		entityCount, maskCount, #BBS.DamagePaintQueue,
		table.Count( BBS.HideableMeshCache ),
		table.Count( BBS.DamageMaterialTemplateCache ),
		table.Count( BBS.DamageSharedCoverage ), BBS.DamageMaterialSerial,
		"full-source",
		smoothing.expansion, smoothing.feather, smoothing.blurPasses,
		tostring( smoothing.unwrapSeams ), smoothing.projectionDepth,
		smoothing.projectionTolerance, smoothing.projectionMaxTriangles,
		tostring( smoothing.projectionLocalBounds ),
		tostring( smoothing.batchRaster ) )
end, nil, "Print UV damage cache, queue, and material state." )

concommand.Add( "bbs_damage_probe_bodygroups", function()
	local trace = LocalPlayer():GetEyeTrace()
	local entity = trace.Entity
	local targetEnabled, _, targetReason = BBS.IsDamageTargetEnabled( entity )
	if not targetEnabled then
		BBS.Log( "bodygroup probe: aim at an enabled target (%s)",
			tostring( targetReason ) )
		return
	end
	local meshData, _, meshError = BBS.GetCachedModelMeshes( entity, 0 )
	if not meshData then
		BBS.Log( "bodygroup probe mesh failure: %s", tostring( meshError ) )
		return
	end
	local analysis, analysisError = BBS.GetHideableMeshAnalysis( entity, meshData )
	if not analysis then
		BBS.Log( "bodygroup probe failed: %s", tostring( analysisError ) )
		return
	end
	BBS.Log( "bodygroup eligibility probe: selection=%s eligible=%d overrides=%d unresolvedOverrides=%d blockedByName=%d inspected=%d eligibleMeshes=%d/%d ownership=%s directGroups=%d compiledMeshes=%d comparisons=%d failed=%d ambiguous=%d",
		analysis.selection, #analysis.bodygroups,
		analysis.overriddenBodygroupCount or 0,
		analysis.unresolvedOverrideCount or 0,
		analysis.blockedBodygroupCount or 0,
		#( analysis.inspectedBodygroups or {} ), analysis.hideableMeshCount,
		#meshData.meshes,
		tostring( analysis.ownershipMode or "unknown" ),
		analysis.directOwnershipBodygroupCount or 0,
		analysis.compiledMeshCount or 0,
		analysis.comparisonCount, analysis.failedComparisons,
		analysis.ambiguousFingerprints )
	if analysis.compiledOwnershipError then
		BBS.Log( "  compiled bodypart ownership fallback: %s",
			tostring( analysis.compiledOwnershipError ) )
	end
	for _, bodygroup in ipairs( analysis.inspectedBodygroups or {} ) do
		BBS.Log( "  group=%d rawKey=%s(%s) name=%s selected=%d count=%d declared=%s hasBlank=%s overridden=%s blacklistBypassed=%s filterAllowed=%s eligible=%s owner=%s meshes=%s..%s compare=%s reason=%s blankOptions=[%s]",
			bodygroup.id, BodygroupHelpers.DebugRawValue( bodygroup.rawKey ),
			tostring( bodygroup.rawKeyType ), bodygroup.name,
			bodygroup.selected, bodygroup.count, tostring( bodygroup.declaredCount ),
			tostring( bodygroup.hasBlank ), tostring( bodygroup.overridden ),
			tostring( bodygroup.blacklistBypassed ), tostring( bodygroup.filterAllowed ),
			tostring( bodygroup.eligible ), tostring( bodygroup.ownershipSource ),
			tostring( bodygroup.compiledFirstMesh ),
			tostring( bodygroup.compiledLastMesh ),
			tostring( bodygroup.comparisonOption
				and bodygroup.comparisonOption.id ), tostring( bodygroup.filterReason ),
			BodygroupHelpers.BlankOptionSummary( bodygroup ) )
		for _, option in ipairs( bodygroup.submodels or {} ) do
			BBS.Log( "    option=%d name=%s blank=%s reason=%s inferred=%s valueType=%s",
				option.id, BodygroupHelpers.DebugSubmodelName( option.name ),
				tostring( option.blank ), tostring( option.reason ),
				tostring( option.inferred or false ), tostring( option.valueType ) )
		end
		for _, raw in ipairs( bodygroup.rawSubmodels or {} ) do
			BBS.Log( "      raw key=%s keyType=%s optionId=%s valueType=%s value=%s extractedName=%s",
				BodygroupHelpers.DebugRawValue( raw.key ), tostring( raw.keyType ), tostring( raw.id ),
				tostring( raw.valueType ), BodygroupHelpers.DebugRawValue( raw.value ),
				BodygroupHelpers.DebugRawValue( raw.name ) )
		end
	end
	for meshIndex, groupMap in pairs( analysis.meshGroups ) do
		local mesh = meshData.meshes[ meshIndex ]
		BBS.Log( "  mesh=%d material=%s changesWith=[%s]",
			meshIndex, mesh and mesh.material or "<missing>",
			table.concat( BodygroupHelpers.SortedNames( groupMap ), "," ) )
	end
	WriteBodygroupProbeBundle( {
		serial = 0,
		entityIndex = entity:EntIndex(),
		model = entity:GetModel(),
	}, analysis, "manual_console_command" )
end, nil, "Probe blank submodel options and eligible meshes on an enabled target." )
