-- Localized by the native-loader companion when bundled; standalone use keeps the English.
local bundle_i18n = CLIENT and file.Exists("nativeloader/i18n.lua", "LUA")
    and include("nativeloader/i18n.lua") or nil
local function NL(text)
    return bundle_i18n and bundle_i18n.A(text, BBS.I18N and BBS.I18N.language or "en") or text
end
local NP = bundle_i18n and bundle_i18n.P or function(text) return text end
local function NN(text) return text end
-- Client hit retrace, 3D overlay, HUD summary, and debug console commands.

BBS = BBS or {}
-- Also load the new policy module on an individual-file refresh of an older
-- running install; the normal alphabetical autorun path already included it.
if not BBS.StepMeshNativeCleanup then
	include( "bullet_break_simulator/cl_29_mesh_preparation.lua" )
end
BBS.DebugHits = BBS.DebugHits or {}
BBS.ClientHitCount = BBS.ClientHitCount or 0
BBS.LastHit = BBS.LastHit or nil
BBS.ModelMeshCache = BBS.ModelMeshCache or {}
BBS.ModelMeshCacheStats = BBS.ModelMeshCacheStats or {
	hits = 0,
	misses = 0,
	builds = 0,
	failures = 0,
	evictions = 0,
}
BBS.MeshQueryQueue = BBS.MeshQueryQueue or {}
BBS.DeferredHitMeshQueue = BBS.DeferredHitMeshQueue or {}
BBS.MeshPrewarmQueue = BBS.MeshPrewarmQueue or {}
BBS.MeshPrewarmQueued = BBS.MeshPrewarmQueued or setmetatable( {}, { __mode = "k" } )
BBS.MeshPrewarmByKey = BBS.MeshPrewarmByKey or {}
BBS.PendingHitBursts = BBS.PendingHitBursts
	or setmetatable( {}, { __mode = "k" } )
BBS.HitDispatchQueue = BBS.HitDispatchQueue or {}
BBS.MeshPrewarmStats = BBS.MeshPrewarmStats or { meshMilliseconds = 0,
	eligibilityMilliseconds = 0, completed = 0 }
BBS.ModelMeshCacheAccessSerial = BBS.ModelMeshCacheAccessSerial or 0
BBS.ModelMeshNegativeAccess = BBS.ModelMeshNegativeAccess or {}
BBS.ModelMeshNegativeSerial = BBS.ModelMeshNegativeSerial or 0
BBS.MeshCacheEvictionGCSteps = BBS.MeshCacheEvictionGCSteps or 0
if BBS.ModelMeshCacheFormat ~= 18 then
	if BBS.CancelPersistentMeshWork then
		BBS.CancelPersistentMeshWork( true )
	end
	BBS.ModelMeshCache = {}
	BBS.ModelMeshCacheStats = {
		hits = 0, misses = 0, builds = 0, failures = 0, evictions = 0,
	}
	BBS.DebugHits = {}
	BBS.LastHit = nil
	BBS.MeshQueryQueue = {}
	BBS.DeferredHitMeshQueue = {}
	BBS.MeshPrewarmQueue = {}
	BBS.MeshPrewarmQueued = setmetatable( {}, { __mode = "k" } )
	BBS.MeshPrewarmByKey = {}
	BBS.PendingHitBursts = setmetatable( {}, { __mode = "k" } )
	BBS.HitDispatchQueue = {}
	BBS.MeshPrewarmStats = { meshMilliseconds = 0,
		eligibilityMilliseconds = 0, completed = 0 }
	BBS.ModelMeshCacheAccessSerial = 0
	BBS.ModelMeshNegativeAccess = {}
	BBS.ModelMeshNegativeSerial = 0
	BBS.MeshCacheEvictionGCSteps = 0
	BBS.ModelMeshCacheFormat = 18
end
-- A suspended packer closes over the previous file instance's local deadline
-- pointer. Restart only that resumable phase on auto-refresh; completed caches
-- and immutable job identities remain valid.
local refreshedPrewarmQueue = {}
local refreshedPrewarmByKey = {}
local refreshedPrewarmQueued = setmetatable( {}, { __mode = "k" } )
for _, queuedJob in ipairs( BBS.MeshPrewarmQueue ) do
	if queuedJob.meshThread then
		queuedJob.meshThread = nil
		queuedJob.meshCPUMilliseconds = 0
		queuedJob.meshMaximumSliceMilliseconds = 0
		queuedJob.phase = "mesh"
	end
	if queuedJob.speculative == nil then
		queuedJob.speculative = not queuedJob.urgent
	end
	queuedJob.preparationStartedAt = queuedJob.preparationStartedAt or SysTime()
	if queuedJob.urgent then
		queuedJob.urgentStartedAt = queuedJob.urgentStartedAt
			or queuedJob.preparationStartedAt
	end
	queuedJob.pinnedContinuation = queuedJob.diskState ~= nil
		or queuedJob.phase == "rtx_cleanup"
	if queuedJob.key and not refreshedPrewarmByKey[ queuedJob.key ] then
		refreshedPrewarmQueue[ #refreshedPrewarmQueue + 1 ] = queuedJob
		refreshedPrewarmByKey[ queuedJob.key ] = queuedJob
		if IsValid( queuedJob.entity ) then
			refreshedPrewarmQueued[ queuedJob.entity ] = true
		end
	end
end
BBS.MeshPrewarmQueue = refreshedPrewarmQueue
BBS.MeshPrewarmByKey = refreshedPrewarmByKey
BBS.MeshPrewarmQueued = refreshedPrewarmQueued
for key, loadState in pairs( BBS.PersistentMeshLoads or {} ) do
	local referenced = false
	for _, queuedJob in ipairs( BBS.MeshPrewarmQueue ) do
		if queuedJob.diskState == loadState then
			referenced = true
			break
		end
	end
	if not referenced then
		if BBS.CancelPersistentMeshLoad then BBS.CancelPersistentMeshLoad( loadState ) end
		loadState.cancelled = true
		BBS.PersistentMeshLoads[ key ] = nil
	end
end

local COLOR_RAW = Color( 255, 70, 70, 230 )
local COLOR_SURFACE = Color( 70, 255, 100, 240 )
local COLOR_TRACE = Color( 255, 205, 70, 180 )
local COLOR_DIRECTION = Color( 255, 135, 40, 230 )
local COLOR_NORMAL = Color( 60, 190, 255, 230 )
local COLOR_MISS = Color( 255, 70, 220, 235 )
local COLOR_TEXT = Color( 245, 245, 245, 255 )
local COLOR_HULL_WIRE = Color( 80, 235, 255, 245 )
local COLOR_HULL_INSIDE = Color( 255, 90, 55, 245 )
local COLOR_HULL_OUTSIDE = Color( 90, 255, 140, 245 )
local ZERO_ANGLE = Angle( 0, 0, 0 )
local ZERO_VECTOR = Vector( 0, 0, 0 )

-- Existing debug installs retain archived convar values across auto-refresh.
-- Apply the screenshot defaults once, then preserve subsequent user changes.
timer.Simple( 0, function()
	local revision = GetConVar( "bbs_settings_revision" )
	if not revision or revision:GetInt() >= 17 then return end
	local previous = revision:GetInt()
	if previous < 1 then
		RunConsoleCommand( "bbs_hull_radius", "0.5" )
		RunConsoleCommand( "bbs_hull_inside_distance", "1" )
		RunConsoleCommand( "bbs_hull_outside_distance", "2" )
		RunConsoleCommand( "bbs_hull_segments", "20" )
		RunConsoleCommand( "bbs_hull_fill_alpha", "38" )
	end
	if previous < 2 then
		-- Revision 2 changed only expensive visual defaults.
		local rtSize = GetConVar( "bbs_damage_rt_size" )
		if rtSize and rtSize:GetInt() == 1024 then
			RunConsoleCommand( "bbs_damage_rt_size", "512" )
		end
		RunConsoleCommand( "bbs_damage_uv_preview", "0" )
	end
	if previous < 3 then
		-- Revision 3 makes the value a maximum edge and raises the quick default.
		-- Only migrate the old 512 default; deliberate higher choices survive.
		local rtSize = GetConVar( "bbs_damage_rt_size" )
		if rtSize and rtSize:GetInt() == 512 then
			RunConsoleCommand( "bbs_damage_rt_size", "2048" )
		end
	end
	if previous < 4 then
		-- Revision 4 makes the texture inspector strictly opt-in, including for
		-- clients whose archived value was enabled by the former debug preset.
		RunConsoleCommand( "bbs_damage_uv_preview", "0" )
	end
	if previous < 5 then
		-- The first dynamic-mesh coverage implementation could reach Source's
		-- native vertex ceiling on complex hits. Keep it as an explicit A/B tool,
		-- but migrate every existing install back to the stable surface path.
		-- Also retire the old 4096 debug-preset default: persistent render targets
		-- are not reclaimed during a session and can exhaust video memory after a
		-- few multi-material hits.
		RunConsoleCommand( "bbs_damage_batch_raster", "0" )
		local rtSize = GetConVar( "bbs_damage_rt_size" )
		if rtSize and rtSize:GetInt() > 2048 then
			RunConsoleCommand( "bbs_damage_rt_size", "2048" )
		end
		local projectionCap = GetConVar( "bbs_damage_projection_max_triangles" )
		if projectionCap and projectionCap:GetInt() > 16384 then
			RunConsoleCommand( "bbs_damage_projection_max_triangles", "16384" )
		end
	end
	if previous < 6 then
		-- Revision 6 is the normal clean-install profile shown in the Damage tab.
		-- Existing development installs receive it once so their archived debug
		-- values do not continue printing or selecting oversized tears by default.
		RunConsoleCommand( "bbs_damage_enabled", "1" )
		RunConsoleCommand( "bbs_damage_apply_materials", "1" )
		RunConsoleCommand( "bbs_debug_overlay", "0" )
		RunConsoleCommand( "bbs_debug_console", "0" )
		RunConsoleCommand( "bbs_debug_hud", "0" )
		RunConsoleCommand( "bbs_debug_labels", "0" )
		RunConsoleCommand( "bbs_hull_enabled", "0" )
		RunConsoleCommand( "bbs_perf_enabled", "0" )
		RunConsoleCommand( "bbs_perf_hud", "0" )
		RunConsoleCommand( "bbs_perf_console", "0" )
		RunConsoleCommand( "bbs_hull_radius", "0.5" )
		RunConsoleCommand( "bbs_hull_inside_distance", "4" )
		RunConsoleCommand( "bbs_hull_outside_distance", "10" )
		RunConsoleCommand( "bbs_hole_damage_scaling", "1" )
		RunConsoleCommand( "bbs_hole_reference_damage", "5" )
		RunConsoleCommand( "bbs_hole_max_radius_multiplier", "5" )
		RunConsoleCommand( "bbs_hole_base_irregularity", "0.4" )
		RunConsoleCommand( "bbs_hole_damage_irregularity", "0.5" )
		RunConsoleCommand( "bbs_hole_max_irregularity", "0.9" )
		RunConsoleCommand( "bbs_damage_rt_size", "2048" )
		RunConsoleCommand( "bbs_damage_uv_expand_pixels", "1" )
		RunConsoleCommand( "bbs_damage_uv_feather_pixels", "0" )
		RunConsoleCommand( "bbs_damage_uv_blur_passes", "2" )
		RunConsoleCommand( "bbs_damage_uv_unwrap_seams", "1" )
		RunConsoleCommand( "bbs_damage_projection_depth", "4" )
		RunConsoleCommand( "bbs_damage_projection_tolerance", "0.04" )
	end
	if previous < 8 then
		-- Revision 8 restores unlimited mesh-surface penetration as the normal
		-- profile and migrates installs which retained the temporary finite default.
		RunConsoleCommand( "bbs_damage_layer_limit", "0" )
	end
	if previous < 9 then
		-- Revision 9 removes the multi-second latency caused by hydrating hundreds
		-- of small persistent-cache chunks under the former 1 ms/frame default.
		-- Preserve deliberate custom values while migrating the archived defaults.
		local ioBudget = GetConVar( "bbs_mesh_cache_io_budget_ms" )
		if ioBudget and math.abs( ioBudget:GetFloat() - 1 ) < 0.001 then
			RunConsoleCommand( "bbs_mesh_cache_io_budget_ms", "3" )
		end
		local buildBudget = GetConVar( "bbs_mesh_build_budget_ms" )
		if buildBudget and math.abs( buildBudget:GetFloat() - 1.5 ) < 0.001 then
			RunConsoleCommand( "bbs_mesh_build_budget_ms", "3" )
		end
	end
	if previous < 10 then
		-- Revision 10 deliberately resets client settings to the current realtime
		-- profile. A fixed per-frame budget cannot meet a wall-time target on
		-- low-FPS/RTX clients, and archived values would otherwise silently retain
		-- the obsolete scheduler. The explicit cache assignments below also make
		-- this migration safe if the preset command is unavailable during a reload.
		RunConsoleCommand( "bbs_realtime_preset" )
		RunConsoleCommand( "bbs_mesh_prewarm", "1" )
		RunConsoleCommand( "bbs_mesh_prewarm_living", "1" )
		RunConsoleCommand( "bbs_mesh_disk_cache", "1" )
		RunConsoleCommand( "bbs_mesh_cache_io_budget_ms", "12" )
		RunConsoleCommand( "bbs_mesh_build_budget_ms", "12" )
		RunConsoleCommand( "bbs_mesh_prepare_target_seconds", "4" )
		RunConsoleCommand( "bbs_mesh_prepare_catchup_ms", "100" )
	end
	if previous < 11 then
		-- Revision 11 removes the wall-clock catch-up policy introduced by revision
		-- 10. It could spend 100 ms in each rare frame on a slow/RTX client, making
		-- the game less responsive precisely when it was already overloaded. Reset
		-- these scheduler controls for every updated install; they are safety limits,
		-- not visual preferences, and old archived values are unsafe here.
		RunConsoleCommand( "bbs_mesh_cache_io_budget_ms", "2" )
		RunConsoleCommand( "bbs_mesh_build_budget_ms", "4" )
		RunConsoleCommand( "bbs_mesh_prepare_target_seconds", "4" )
		RunConsoleCommand( "bbs_mesh_prepare_catchup_ms", "8" )
	end
	if previous < 12 then
		-- Compact hydration relies on the ordinary 2/4 ms background profile and
		-- its bounded 8 ms urgent ceiling. Reapply only these scheduler controls
		-- so archived experiments cannot leave first-shot work permanently at the
		-- speculative budget after this update.
		RunConsoleCommand( "bbs_mesh_cache_io_budget_ms", "2" )
		RunConsoleCommand( "bbs_mesh_build_budget_ms", "4" )
		RunConsoleCommand( "bbs_mesh_prepare_target_seconds", "4" )
		RunConsoleCommand( "bbs_mesh_prepare_catchup_ms", "8" )
	end
	if previous < 14 then
		-- Revision 14 isolates the RTX scheduler and removes an archived 20 ms
		-- query slice observed in the Remix archive. Do not mutate any vanilla
		-- setting: that runtime already behaves correctly and must retain the exact
		-- profile selected by its user. The new RTX convars already have safe defaults.
		if BBS.IsActiveRTXRuntime and BBS.IsActiveRTXRuntime() then
			RunConsoleCommand( "bbs_mesh_query_budget_ms", "3" )
			RunConsoleCommand( "bbs_mesh_rtx_background_budget_ms", "8" )
			RunConsoleCommand( "bbs_mesh_rtx_catchup_ms", "12" )
		end
	end
	if previous < 15 then
		-- The former Aggressive profile still proved too conservative in normal
		-- play. Revision 15 deliberately makes 1.25x that profile the recommended
		-- baseline for both new and updated clients. These seven archived convars
		-- are reset together so the visible preset and effective runtime limits
		-- cannot disagree after an addon update.
		RunConsoleCommand( "bbs_mesh_cache_io_budget_ms", "10" )
		RunConsoleCommand( "bbs_mesh_build_budget_ms", "15" )
		RunConsoleCommand( "bbs_mesh_query_budget_ms", "10" )
		RunConsoleCommand( "bbs_damage_projection_budget_ms", "6.25" )
		RunConsoleCommand( "bbs_mesh_prepare_catchup_ms", "20" )
		RunConsoleCommand( "bbs_mesh_rtx_background_budget_ms", "15" )
		RunConsoleCommand( "bbs_mesh_rtx_catchup_ms", "25" )
	end
	if previous < 16 then
		-- The old default (4) did not soften cutout alpha before 0.19.14.
		-- Migrate ONLY that exact value once; deliberately chosen other values
		-- survive, and selecting 4 again after this update remains supported.
		local softness = GetConVar( "bbs_damage_uv_feather_pixels" )
		if softness and softness:GetFloat() == 4 then
			RunConsoleCommand( "bbs_damage_uv_feather_pixels", "0" )
		end
	end
	if previous < 17 then
		local target = GetConVar( "bbs_mesh_prepare_target_seconds" )
		if target and target:GetFloat() == 4 then
			RunConsoleCommand( "bbs_mesh_prepare_target_seconds", "2" )
		end
	end
	RunConsoleCommand( "bbs_settings_revision", "17" )
end )

local function GetBool( name )
	local convar = GetConVar( name )
	return convar and convar:GetBool() or false
end

local function GetFloat( name, fallback )
	local convar = GetConVar( name )
	return convar and convar:GetFloat() or fallback
end

local function GetInt( name, fallback )
	local convar = GetConVar( name )
	return convar and convar:GetInt() or fallback
end

function BBS.ClearPendingHitWork( targetKind )
	local removed = 0
	local orphanedCacheKeys = {}
	local function CancelHit( hit, reason, status )
		if not hit then return end
		hit.meshQuery = {
			ok = false, pending = false, error = reason or "work cancelled",
		}
		if BBS.PerfFinish then BBS.PerfFinish( hit, status or "cancelled" ) end
	end
	local function Matches( entity )
		if not IsValid( entity ) then return true end
		return not targetKind or BBS.GetDamageTargetKind( entity ) == targetKind
	end
	for entity in pairs( BBS.PendingHitBursts ) do
		if Matches( entity ) then
			BBS.PendingHitBursts[ entity ] = nil
			removed = removed + 1
		end
	end
	for index = #BBS.HitDispatchQueue, 1, -1 do
		if Matches( BBS.HitDispatchQueue[ index ].entity ) then
			table.remove( BBS.HitDispatchQueue, index )
			removed = removed + 1
		end
	end
	for index = #BBS.DeferredHitMeshQueue, 1, -1 do
		local deferred = BBS.DeferredHitMeshQueue[ index ]
		local hit = deferred.hit
		if Matches( hit and hit.entity ) then
			table.remove( BBS.DeferredHitMeshQueue, index )
			if deferred.cacheKey then
				orphanedCacheKeys[ deferred.cacheKey ] = true
			end
			CancelHit( hit, "target type was disabled", "target_disabled" )
			removed = removed + 1
		end
	end
	-- Release only after every matching deferred hit has been removed. Several
	-- burst records may depend on the same cold model producer, and checking in
	-- the loop would retain it until the next unrelated lifecycle event.
	for cacheKey in pairs( orphanedCacheKeys ) do
		if BBS.ReleaseOrphanUrgentMeshPrewarm then
			BBS.ReleaseOrphanUrgentMeshPrewarm( cacheKey )
		end
	end
	for index = #BBS.MeshQueryQueue, 1, -1 do
		local hit = BBS.MeshQueryQueue[ index ].hit
		if Matches( hit and hit.entity ) then
			table.remove( BBS.MeshQueryQueue, index )
			CancelHit( hit, "target type was disabled", "target_disabled" )
			removed = removed + 1
		end
	end
	return removed
end

local function ValidTargetHit( trace, entity )
	return trace and trace.Hit and trace.Entity == entity
end

local function TargetOnly( target )
	return function( candidate )
		return candidate == target
	end
end

local function RunTargetTrace( entity, startPosition, endPosition )
	return util.TraceLine( {
		start = startPosition,
		endpos = endPosition,
		mask = MASK_SHOT,
		ignoreworld = true,
		filter = TargetOnly( entity ),
	} )
end

local function TraceDistanceToRaw( trace, rawPosition )
	if not trace or not trace.HitPos then return math.huge end
	return trace.HitPos:Distance( rawPosition )
end

local function FindNearestPhysicsBone( entity, position )
	local nearest = -1
	local nearestDistance = math.huge

	for index = 0, entity:GetPhysicsObjectCount() - 1 do
		local physicsObject = entity:GetPhysicsObjectNum( index )
		if IsValid( physicsObject ) then
			local distance = physicsObject:GetPos():DistToSqr( position )
			if distance < nearestDistance then
				nearest = index
				nearestDistance = distance
			end
		end
	end

	return nearest
end

local function FindNearestModelBone( entity, position )
	entity:SetupBones()
	local nearest = -1
	local nearestDistance = math.huge
	local boneCount = entity:GetBoneCount() or 0
	for bone = 0, math.max( boneCount - 1, -1 ) do
		local matrix = entity:GetBoneMatrix( bone )
		if matrix then
			local distance = matrix:GetTranslation():DistToSqr( position )
			if distance < nearestDistance then
				nearest = bone
				nearestDistance = distance
			end
		end
	end
	return nearest
end

local function ResolveBone( entity, trace, surfacePosition )
	local physicsBone = trace and trace.PhysicsBone or -1
	local modelBone = -1
	local living = BBS.IsLivingDamageTarget( entity )
	if living and trace and ( trace.HitBox or -1 ) >= 0
	and entity.GetHitBoxBone then
		local hitboxSet = entity.GetHitboxSet and entity:GetHitboxSet() or 0
		modelBone = entity:GetHitBoxBone( trace.HitBox, hitboxSet or 0 ) or -1
	end
	if not physicsBone or physicsBone < 0 then
		physicsBone = FindNearestPhysicsBone( entity, surfacePosition )
	end

	if modelBone < 0 and physicsBone and physicsBone >= 0
	and entity.TranslatePhysBoneToBone then
		modelBone = entity:TranslatePhysBoneToBone( physicsBone ) or -1
	end
	if living and modelBone < 0 then
		modelBone = FindNearestModelBone( entity, surfacePosition )
	end

	local boneName = "<none>"
	if modelBone >= 0 then boneName = entity:GetBoneName( modelBone ) or "<unnamed>" end
	return physicsBone or -1, modelBone, boneName
end

local function AttachmentFrame( entity, attachment )
	if not IsValid( entity ) or not attachment then return nil end

	if attachment.kind == "physics" then
		local physicsObject = entity:GetPhysicsObjectNum( attachment.physicsBone )
		if IsValid( physicsObject ) then
			return physicsObject:GetPos(), physicsObject:GetAngles()
		end
	elseif attachment.kind == "bone" then
		entity:SetupBones()
		local matrix = entity:GetBoneMatrix( attachment.modelBone )
		if matrix then return matrix:GetTranslation(), matrix:GetAngles() end
	end

	return entity:GetPos(), entity:GetAngles()
end


local function CreateAttachment( hit )
	local entity = hit.entity
	local attachment = {
		kind = "entity",
		physicsBone = hit.physicsBone,
		modelBone = hit.modelBone,
	}

	if entity:GetClass() == "prop_ragdoll" and hit.physicsBone >= 0
	and IsValid( entity:GetPhysicsObjectNum( hit.physicsBone ) ) then
		attachment.kind = "physics"
	elseif hit.modelBone >= 0 then
		entity:SetupBones()
		if entity:GetBoneMatrix( hit.modelBone ) then attachment.kind = "bone" end
	end

	local origin, angles = AttachmentFrame( entity, attachment )
	if not origin then return nil end
	attachment.snapshotOrigin = Vector( origin.x, origin.y, origin.z )
	attachment.snapshotAngles = Angle( angles.p, angles.y, angles.r )

	attachment.rawPosition = WorldToLocal( hit.rawPosition, ZERO_ANGLE, origin, angles )
	attachment.surfacePosition = WorldToLocal( hit.surfacePosition, ZERO_ANGLE, origin, angles )
	attachment.traceStart = WorldToLocal( hit.traceStart, ZERO_ANGLE, origin, angles )
	attachment.traceEnd = WorldToLocal( hit.traceEnd, ZERO_ANGLE, origin, angles )
	local unusedPosition
	unusedPosition, attachment.directionAngle = WorldToLocal(
		origin, hit.direction:Angle(), origin, angles )
	unusedPosition, attachment.normalAngle = WorldToLocal(
		origin, hit.normal:Angle(), origin, angles )
	local hullRight = hit.hullParameters and hit.hullParameters.right or nil
	if isvector( hullRight ) then
		unusedPosition, attachment.hullRightAngle = WorldToLocal(
			origin, hullRight:Angle(), origin, angles )
	end
	return attachment
end

local function AttachedWorldValues( hit )
	local origin, angles = AttachmentFrame( hit.entity, hit.attachment )
	if not origin then
		return hit.rawPosition, hit.surfacePosition, hit.traceStart, hit.traceEnd,
			hit.direction, hit.normal,
			hit.hullParameters and hit.hullParameters.right or nil
	end

	local rawPosition = LocalToWorld( hit.attachment.rawPosition, ZERO_ANGLE, origin, angles )
	local surfacePosition = LocalToWorld( hit.attachment.surfacePosition, ZERO_ANGLE, origin, angles )
	local traceStart = LocalToWorld( hit.attachment.traceStart, ZERO_ANGLE, origin, angles )
	local traceEnd = LocalToWorld( hit.attachment.traceEnd, ZERO_ANGLE, origin, angles )
	local unusedPosition, directionAngle = LocalToWorld(
		ZERO_VECTOR, hit.attachment.directionAngle, origin, angles )
	local normalAngle
	unusedPosition, normalAngle = LocalToWorld(
		ZERO_VECTOR, hit.attachment.normalAngle, origin, angles )
	local hullRight
	if hit.attachment.hullRightAngle then
		local hullRightAngle
		unusedPosition, hullRightAngle = LocalToWorld(
			ZERO_VECTOR, hit.attachment.hullRightAngle, origin, angles )
		hullRight = hullRightAngle:Forward()
	end

	return rawPosition, surfacePosition, traceStart, traceEnd,
		directionAngle:Forward(), normalAngle:Forward(), hullRight
end

---------------------------------------------------------------------------
-- Cached visual mesh data and conservative removal-hull envelope query
---------------------------------------------------------------------------

local BODYGROUP_DIGITS = "0123456789abcdefghijklmnopqrstuvwxyz"

local function EncodeBodygroupOption( value )
	value = math.Clamp( math.floor( tonumber( value ) or 0 ), 0,
		#BODYGROUP_DIGITS - 1 )
	return string.sub( BODYGROUP_DIGITS, value + 1, value + 1 )
end

local function BodygroupSelection( entity )
	local groups = entity:GetBodyGroups() or {}
	if #groups == 0 then return 0, "0" end

	local values = {}
	local maximumId = -1
	for index, group in ipairs( groups ) do
		local id = group.id or index - 1
		maximumId = math.max( maximumId, id )
		values[ id + 1 ] = EncodeBodygroupOption(
			entity:GetBodygroup( id ) or 0 )
	end
	for index = 1, maximumId + 1 do
		values[ index ] = values[ index ] or "0"
	end

	local selection = table.concat( values )
	return selection ~= "" and selection or 0, selection ~= "" and selection or "0"
end


local function MeshCacheKey( entity, lod )
	local model = string.lower( entity:GetModel() or "" )
	local bodygroupArgument, bodygroupKey = BodygroupSelection( entity )
	local skin = entity:GetSkin() or 0
	return string.format( "%s|lod=%d|bodygroups=%s|skin=%d",
		model, lod, bodygroupKey, skin ), model, bodygroupArgument, skin
end

function BBS.GetModelMeshCacheIdentity( entity, lod )
	if not IsValid( entity ) then return nil end
	return MeshCacheKey( entity, lod or 0 )
end

local function CollectVertexBones( target, vertex )
	local weights = vertex.weights
	if not weights or #weights == 0 then
		target[ 0 ] = true
		return
	end
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

-- UV seams and split normals duplicate the same skinned point many times in
-- ModelMeshData.triangles. Cache one skin input for vertices that share model
-- position and bone weights so every hit poses that point only once.
local function SameSkinWeights( first, second )
	local secondCount = second and #second or 0
	if secondCount == 0 then
		return first and #first == 2 and first[ 1 ] == 0 and first[ 2 ] == 1
	end
	if not first or #first ~= secondCount * 2 then return false end
	for index, right in ipairs( second ) do
		local offset = ( index - 1 ) * 2
		if first[ offset + 1 ] ~= ( right.bone or 0 )
		or first[ offset + 2 ] ~= ( right.weight or 0 ) then return false end
	end
	return true
end

local function GetOrCreateSkinVertex( lookup, output, vertex )
	local position = vertex and vertex.pos
	if not position then return nil end
	-- Formatting four to twelve floating-point values into a string for every
	-- triangle corner dominated cold-cache CPU time. Use a cheap numeric spatial
	-- hash and verify collisions exactly; equal positions always enter the same
	-- bucket, while an accidental hash collision is harmless.
	local x, y, z = position.x, position.y, position.z
	local hash = x * 73856093 + y * 19349663 + z * 83492791
	local bucket = lookup[ hash ]
	if bucket then
		for _, cached in ipairs( bucket ) do
			local cachedPosition = cached.position
			if cachedPosition.x == x and cachedPosition.y == y
			and cachedPosition.z == z
			and SameSkinWeights( cached.weights, vertex.weights ) then
				return cached
			end
		end
	else
		bucket = {}
		lookup[ hash ] = bucket
	end
	local packedWeights = {}
	local rigidBone
	local rawWeights = vertex.weights
	if not rawWeights or #rawWeights == 0 then
		packedWeights[ 1 ], packedWeights[ 2 ] = 0, 1
		rigidBone = 0
	else
		for _, boneWeight in ipairs( rawWeights ) do
			local bone = boneWeight.bone or 0
			local weight = boneWeight.weight or 0
			packedWeights[ #packedWeights + 1 ] = bone
			packedWeights[ #packedWeights + 1 ] = weight
			if weight > 0 then
				if rigidBone == nil then rigidBone = bone
				elseif rigidBone ~= bone then rigidBone = false end
			end
		end
		if rigidBone == nil then rigidBone = 0 end
	end
	local cached = {
		position = position,
		weights = packedWeights,
		rigidBone = rigidBone,
	}
	bucket[ #bucket + 1 ] = cached
	output[ #output + 1 ] = cached
	return cached
end

local function TriangleModelSphere( first, second, third )
	local a, b, c = first.pos, second.pos, third.pos
	local x = ( a.x + b.x + c.x ) / 3
	local y = ( a.y + b.y + c.y ) / 3
	local z = ( a.z + b.z + c.z ) / 3
	local function DistanceSquared( point )
		local dx, dy, dz = point.x - x, point.y - y, point.z - z
		return dx * dx + dy * dy + dz * dz
	end
	return Vector( x, y, z ), math.sqrt( math.max( DistanceSquared( a ),
		DistanceSquared( b ), DistanceSquared( c ) ) )
end

local function TriangleBoneSphere( poseToBone, modelCenter, modelRadius )
	if not poseToBone or not modelCenter then return nil end
	local center = poseToBone * modelCenter
	return center.x, center.y, center.z, modelRadius
end

-- Persistent caches deliberately use small chunks so each individual file read
-- and JSON reconstruction remains bounded. Scale background work with frame
-- cadence, but always respect a small absolute cap. The former wall-clock
-- catch-up policy could jump to 100 ms/frame on a slow client; that both reduced
-- the number of frames available to the coroutine and made spawning feel frozen.
local function RemainingPersistentLoadChunks( state )
	if not state or not state.metadata or not state.metadata.meshes then return nil end
	local remaining = 0
	for meshIndex = state.meshIndex or 1, #state.metadata.meshes do
		local descriptor = state.metadata.meshes[ meshIndex ] or {}
		local skinChunks = descriptor.skinChunks or 0
		local triangleChunks = descriptor.triangleChunks or 0
		if meshIndex == ( state.meshIndex or 1 ) then
			if state.stage == "skin" then
				remaining = remaining
					+ math.max( skinChunks - ( state.chunk or 1 ) + 1, 0 )
					+ triangleChunks
			else
				remaining = remaining
					+ math.max( triangleChunks - ( state.chunk or 1 ) + 1, 0 )
			end
		else
			remaining = remaining + skinChunks + triangleChunks
		end
	end
	return remaining
end

local function MeshPreparationBudget( job, convarName, fallback, minimum )
	local configured = math.Clamp(
		GetFloat( convarName, fallback ), minimum, 120 )
	local now = SysTime()
	local targetSeconds = math.Clamp(
		GetFloat( "bbs_mesh_prepare_target_seconds", 2 ), 1, 15 )
	local normalHardCeiling = math.Clamp(
		GetFloat( "bbs_mesh_prepare_catchup_ms", 20 ), configured, 160 )
	local preparationStartedAt = job and job.preparationStartedAt or nil
	local elapsedSeconds = preparationStartedAt and math.max(
		now - preparationStartedAt, 0 ) or 0
	local remainingSeconds = math.max( targetSeconds - elapsedSeconds, 0 )
	local frameSeconds = RealFrameTime and RealFrameTime() or FrameTime()
	frameSeconds = math.Clamp( tonumber( frameSeconds ) or 1 / 60,
		1 / 240, 0.25 )
	local activeRTX = BBS.IsActiveRTXRuntime
		and BBS.IsActiveRTXRuntime() or false
	local hardCeiling = normalHardCeiling
	-- About one sixth of a frame keeps throughput similar across ordinary frame
	-- rates without creating a positive feedback loop when the game is already
	-- slow. `configured` remains the minimum useful slice and `hardCeiling` is a
	-- real safety cap, never a completion deadline.
	local cadenceAllowance = frameSeconds * 1000 * 0.16
	if activeRTX then
		-- Remix normally presents far fewer real Source frames than vanilla; DLSS
		-- frame generation does not run our Think hooks.  Use more of the otherwise
		-- idle CPU interval while the renderer is GPU-bound, but back off to the
		-- ordinary configured slice when real frame time reaches 30 FPS. Vanilla never
		-- enters this branch and therefore retains the selected normal profile.
		local slowFrame = math.Clamp(
			( frameSeconds * 1000 - 16.67 ) / 16.66, 0, 1 )
		local peakBackground = math.max( configured, math.Clamp( GetFloat(
			"bbs_mesh_rtx_background_budget_ms", 15 ), 1, 120 ) )
		local backgroundCeiling = peakBackground
			+ ( configured - peakBackground ) * slowFrame
		cadenceAllowance = math.min(
			frameSeconds * 1000 * 0.50, backgroundCeiling )
		local peakCeiling = math.max( normalHardCeiling, math.Clamp(
			GetFloat( "bbs_mesh_rtx_catchup_ms", 25 ), configured, 200 ) )
		hardCeiling = peakCeiling
			+ ( normalHardCeiling - peakCeiling ) * slowFrame
	end
	local gentleBudget = math.Clamp(
		math.max( configured, cadenceAllowance ), configured, hardCeiling )
	local effective = gentleBudget
	if job and job.urgent then
		-- Once a real impact is waiting, ramp to the existing safety ceiling.
		-- Background spawn preparation stays at the selected normal cadence, but
		-- first-shot work can ramp to its separate urgent limit. This is a
		-- budget increase only: slow hardware is never treated as an error.
		local urgentStartedAt = job.urgentStartedAt or preparationStartedAt
		local urgentElapsed = urgentStartedAt
			and math.max( now - urgentStartedAt, 0 )
			or ( activeRTX and 0.5 or 0.35 )
		local rampSeconds = activeRTX and 0.5 or 0.35
		local ramp = math.Clamp( urgentElapsed / rampSeconds, 0, 1 )
		effective = gentleBudget
			+ ( hardCeiling - gentleBudget ) * ramp
	end
	local remainingChunks = job and RemainingPersistentLoadChunks(
		job.diskState ) or nil
	return effective, configured, remainingSeconds, remainingChunks,
		targetSeconds, hardCeiling
end

-- Coarse per-bone/per-mesh bounds let a query discover visual layers whose
-- vertices are weighted to bones outside the collision hitbone hierarchy.
-- Bounds live in that bone's bind-local space and conservatively include each
-- triangle sphere, so a point-vs-expanded-AABB rejection cannot hide a true
-- cylinder intersection.
local function ExpandBoneMeshTriangleBounds( meshData, boneId, meshIndex,
	sphereX, sphereY, sphereZ, sphereRadius )
	-- Keep the exported helper tolerant of the legacy sphere-table signature
	-- during individual-file auto-refresh. Full loads use the scalar fast path.
	if istable( sphereX ) then
		local sphere = sphereX
		sphereX, sphereY, sphereZ, sphereRadius =
			sphere.x, sphere.y, sphere.z, sphere.radius
	end
	if not meshData or sphereX == nil then return end
	meshData.boneMeshBounds = meshData.boneMeshBounds or {}
	local byMesh = meshData.boneMeshBounds[ boneId ]
	if not byMesh then
		byMesh = {}
		meshData.boneMeshBounds[ boneId ] = byMesh
	end
	local radius = math.max( tonumber( sphereRadius ) or 0, 0 )
	local minimumX, minimumY, minimumZ = sphereX - radius,
		sphereY - radius, sphereZ - radius
	local maximumX, maximumY, maximumZ = sphereX + radius,
		sphereY + radius, sphereZ + radius
	local bounds = byMesh[ meshIndex ]
	if not bounds then
		byMesh[ meshIndex ] = {
			minimumX = minimumX, minimumY = minimumY, minimumZ = minimumZ,
			maximumX = maximumX, maximumY = maximumY, maximumZ = maximumZ,
		}
		return
	end
	bounds.minimumX = math.min( bounds.minimumX, minimumX )
	bounds.minimumY = math.min( bounds.minimumY, minimumY )
	bounds.minimumZ = math.min( bounds.minimumZ, minimumZ )
	bounds.maximumX = math.max( bounds.maximumX, maximumX )
	bounds.maximumY = math.max( bounds.maximumY, maximumY )
	bounds.maximumZ = math.max( bounds.maximumZ, maximumZ )
end

BBS.ExpandBoneMeshTriangleBounds = ExpandBoneMeshTriangleBounds
BBS.ExpandBoneMeshTriangleBoundsScalar = true

local SPATIAL_FALLBACK_GROUP_TRIANGLES = 64

local function FinalizeSpatialFallbackGroup( group )
	if not group or group.modelCenter then return end
	group.boneIds = {}
	for boneId in pairs( group.boneSet or {} ) do
		group.boneIds[ #group.boneIds + 1 ] = boneId
	end
	table.sort( group.boneIds )
	group.boneSet = nil
	local centerX = ( group.minimumX + group.maximumX ) * 0.5
	local centerY = ( group.minimumY + group.maximumY ) * 0.5
	local centerZ = ( group.minimumZ + group.maximumZ ) * 0.5
	local extentX = math.max( group.maximumX - centerX, 0 )
	local extentY = math.max( group.maximumY - centerY, 0 )
	local extentZ = math.max( group.maximumZ - centerZ, 0 )
	group.modelCenter = Vector( centerX, centerY, centerZ )
	group.modelRadius = math.sqrt(
		extentX * extentX + extentY * extentY + extentZ * extentZ )
	group.minimumX, group.minimumY, group.minimumZ = nil, nil, nil
	group.maximumX, group.maximumY, group.maximumZ = nil, nil, nil
end

function BBS.AddSpatialFallbackTriangle( cachedMesh, lookup, boneSet,
	triangle, firstPosition, secondPosition, thirdPosition )
	if not cachedMesh or not lookup or not triangle then return end
	-- Triangle order emitted by studiomdl is already locally coherent. Chunk
	-- blended triangles in that order and retain the union of their influence
	-- bones. This is conservative (a larger bone union can only enlarge the posed
	-- bound) and replaces a table allocation, sort, and string key per triangle.
	local group = lookup.currentGroup
	if not group or #group.triangles >= SPATIAL_FALLBACK_GROUP_TRIANGLES then
		FinalizeSpatialFallbackGroup( group )
		group = {
			boneSet = {},
			triangles = {},
			minimumX = math.huge, minimumY = math.huge, minimumZ = math.huge,
			maximumX = -math.huge, maximumY = -math.huge, maximumZ = -math.huge,
		}
		lookup.currentGroup = group
		cachedMesh.spatialFallbackGroups =
			cachedMesh.spatialFallbackGroups or {}
		cachedMesh.spatialFallbackGroups[
			#cachedMesh.spatialFallbackGroups + 1 ] = group
	end
	for boneId in pairs( boneSet or {} ) do
		group.boneSet[ tonumber( boneId ) or 0 ] = true
	end
	if not next( group.boneSet ) then group.boneSet[ 0 ] = true end
	group.triangles[ #group.triangles + 1 ] = triangle
	for index = 1, 3 do
		local position = index == 1 and firstPosition
			or ( index == 2 and secondPosition or thirdPosition )
		if position then
			group.minimumX = math.min( group.minimumX, position.x )
			group.minimumY = math.min( group.minimumY, position.y )
			group.minimumZ = math.min( group.minimumZ, position.z )
			group.maximumX = math.max( group.maximumX, position.x )
			group.maximumY = math.max( group.maximumY, position.y )
			group.maximumZ = math.max( group.maximumZ, position.z )
		end
	end
end

function BBS.FinalizeSpatialFallbackGroups( cachedMesh )
	for _, group in ipairs( cachedMesh and cachedMesh.spatialFallbackGroups or {} ) do
		FinalizeSpatialFallbackGroup( group )
	end
end

local activeMeshBuildJob

-- Heavy stages live in separate Source hooks. Without a shared token their
-- individual budgets can stack in one rendered frame (prewarm + query + paint
-- + persistence), recreating the hitch each budget was meant to remove.
function BBS.TryBeginHeavyFrame( owner )
	local frame = FrameNumber()
	if BBS.HeavyWorkFrame == frame then return false end
	BBS.HeavyWorkFrame = frame
	BBS.HeavyWorkOwner = owner
	return true
end

local function TouchModelMeshCache( data )
	if not data or data == false then return end
	BBS.ModelMeshCacheAccessSerial = ( BBS.ModelMeshCacheAccessSerial or 0 ) + 1
	data.lastUsedSerial = BBS.ModelMeshCacheAccessSerial
	data.lastUsedAt = SysTime()
end
BBS.TouchModelMeshCache = TouchModelMeshCache

function BBS.TrimModelMeshCache( protectedKey )
	local maximumEntries = math.Clamp(
		GetInt( "bbs_mesh_cache_max_entries", 6 ), 0, 64 )
	local maximumTriangles = math.Clamp(
		GetInt( "bbs_mesh_cache_max_triangles", 350000 ), 0, 4000000 )

	local pinned = {}
	if protectedKey then pinned[ protectedKey ] = true end
	for _, deferred in ipairs( BBS.DeferredHitMeshQueue or {} ) do
		if deferred.cacheKey then pinned[ deferred.cacheKey ] = true end
	end
	for _, query in ipairs( BBS.MeshQueryQueue or {} ) do
		local key = query.meshData and query.meshData.key
			or query.hit and query.hit.meshQuery and query.hit.meshQuery.cacheKey
		if key then pinned[ key ] = true end
	end
	for _, write in ipairs( BBS.PersistentMeshWriteQueue or {} ) do
		if write.key then pinned[ write.key ] = true end
	end

	local candidates = {}
	local negativeCandidates = {}
	local entryCount, triangleCount = 0, 0
	for key, data in pairs( BBS.ModelMeshCache ) do
		local keyPinned = pinned[ key ]
			or BBS.MeshPrewarmByKey and BBS.MeshPrewarmByKey[ key ] ~= nil
			or BBS.PersistentMeshLoads and BBS.PersistentMeshLoads[ key ] ~= nil
		if data and data ~= false then
			entryCount = entryCount + 1
			triangleCount = triangleCount + ( data.totalTriangleCount or 0 )
			if not keyPinned then
				candidates[ #candidates + 1 ] = {
					key = key, data = data, serial = data.lastUsedSerial or 0,
				}
			end
		elseif data == false and not keyPinned then
			negativeCandidates[ #negativeCandidates + 1 ] = {
				key = key,
				serial = BBS.ModelMeshNegativeAccess[ key ] or 0,
			}
		end
	end
	local evicted = 0
	if #negativeCandidates > 32 then
		table.sort( negativeCandidates, function( left, right )
			return left.serial < right.serial
		end )
		for index = 1, #negativeCandidates - 32 do
			local candidate = negativeCandidates[ index ]
			BBS.ModelMeshCache[ candidate.key ] = nil
			BBS.ModelMeshNegativeAccess[ candidate.key ] = nil
			evicted = evicted + 1
		end
	end
	if ( maximumEntries == 0 or entryCount <= maximumEntries )
	and ( maximumTriangles == 0 or triangleCount <= maximumTriangles ) then
		if evicted == 0 then return 0 end
		BBS.ModelMeshCacheStats.evictions =
			( BBS.ModelMeshCacheStats.evictions or 0 ) + evicted
		BBS.MeshCacheEvictionGCSteps = math.min(
			( BBS.MeshCacheEvictionGCSteps or 0 ) + evicted * 16, 256 )
		return evicted
	end
	table.sort( candidates, function( left, right )
		return left.serial < right.serial
	end )

	for _, candidate in ipairs( candidates ) do
		if ( maximumEntries == 0 or entryCount <= maximumEntries )
		and ( maximumTriangles == 0 or triangleCount <= maximumTriangles ) then break end
		-- A single unusually detailed active model can exceed the triangle target by
		-- itself. Evicting the only ready identity guarantees that its very next shot
		-- repeats the entire cold pipeline, which is worse for both memory churn and
		-- responsiveness. Treat both limits as an LRU budget with a one-entry floor.
		if entryCount <= 1 then break end
		local data = candidate.data
		BBS.ModelMeshCache[ candidate.key ] = nil
		BBS.ModelMeshNegativeAccess[ candidate.key ] = nil
		if BBS.HideableMeshCache then
			BBS.HideableMeshCache[ candidate.key ] = nil
		end
		entryCount = entryCount - 1
		if data and data ~= false then
			triangleCount = triangleCount - ( data.totalTriangleCount or 0 )
		end
		evicted = evicted + 1
	end
	if evicted > 0 then
		BBS.ModelMeshCacheStats.evictions =
			( BBS.ModelMeshCacheStats.evictions or 0 ) + evicted
		-- Reclaim evicted table graphs incrementally on later quiet frames instead
		-- of forcing a full collection at the moment a new model appears.
		BBS.MeshCacheEvictionGCSteps = math.min(
			( BBS.MeshCacheEvictionGCSteps or 0 ) + evicted * 16, 256 )
	end
	return evicted
end

hook.Add( "Think", "BBS.IncrementalMeshCacheGC", function()
	if ( BBS.MeshCacheEvictionGCSteps or 0 ) <= 0 then return end
	if #BBS.MeshQueryQueue > 0 or #BBS.DeferredHitMeshQueue > 0
	or #BBS.MeshPrewarmQueue > 0 or #( BBS.DamagePaintQueue or {} ) > 0
	or #( BBS.PersistentMeshWriteQueue or {} ) > 0
	or table.Count( BBS.PersistentMeshLoads or {} ) > 0 then return end
	collectgarbage( "step", 16 )
	BBS.MeshCacheEvictionGCSteps = BBS.MeshCacheEvictionGCSteps - 1
end )

local function MaybeYieldModelMeshBuild()
	local job = activeMeshBuildJob
	if not job then return end
	if SysTime() >= ( job.deadline or math.huge ) then
		coroutine.yield( "mesh_cache_pack" )
	end
end

local function GetCachedModelMeshesForIdentity(
	key, model, bodygroups, skin, lod )
	lod = lod or 0
	if not key or not model or model == "" then
		return nil, false, "invalid model mesh identity"
	end
	local cached = BBS.ModelMeshCache[ key ]
	if cached ~= nil then
		BBS.ModelMeshCacheStats.hits = BBS.ModelMeshCacheStats.hits + 1
		if cached == false then
			BBS.ModelMeshNegativeSerial =
				( BBS.ModelMeshNegativeSerial or 0 ) + 1
			BBS.ModelMeshNegativeAccess[ key ] = BBS.ModelMeshNegativeSerial
			return nil, true, "known GetModelMeshes failure"
		end
		TouchModelMeshCache( cached )
		return cached, true
	end

	BBS.ModelMeshCacheStats.misses = BBS.ModelMeshCacheStats.misses + 1
	local started = SysTime()
	local nativeStarted = SysTime()
	local ok, modelMeshes, bindPoses = pcall(
		util.GetModelMeshes, model, lod, bodygroups, skin )
	if activeMeshBuildJob then
		activeMeshBuildJob.nativeExtractionMilliseconds =
			( activeMeshBuildJob.nativeExtractionMilliseconds or 0 )
			+ ( SysTime() - nativeStarted ) * 1000
	end
	if not ok or not modelMeshes or #modelMeshes == 0 or not bindPoses then
		BBS.ModelMeshCache[ key ] = false
		BBS.ModelMeshNegativeSerial =
			( BBS.ModelMeshNegativeSerial or 0 ) + 1
		BBS.ModelMeshNegativeAccess[ key ] = BBS.ModelMeshNegativeSerial
		BBS.ModelMeshCacheStats.failures = BBS.ModelMeshCacheStats.failures + 1
		BBS.TrimModelMeshCache()
		local reason = ok and "no readable meshes/bind poses" or tostring( modelMeshes )
		BBS.Log( "mesh cache build failed for %s: %s", key, reason )
		return nil, false, reason
	end
	local activeRTXMeshBuild = BBS.IsActiveRTXRuntime
		and BBS.IsActiveRTXRuntime() or false
	local compactSourceFingerprint = BBS.RawMeshDamageFingerprintStats
		and isfunction( BBS.BuildRawMeshDamageFingerprint )

	local poseToBone = {}
	local inversePoseToBone = {}
	for boneId, bindPose in pairs( bindPoses ) do
		MaybeYieldModelMeshBuild()
		if bindPose.matrix then
			-- Source stores mstudiobone_t::poseToBone here. It is already the
			-- inverse-bind (model-pose -> bone-pose) transform. Keep its inverse
			-- only for the explicit legacy diagnostic; it must not be used for
			-- normal skinning.
			poseToBone[ boneId ] = bindPose.matrix
			inversePoseToBone[ boneId ] = bindPose.matrix:GetInverseTR()
		end
	end

	local data = {
		key = key,
		model = model,
		lod = lod,
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
		totalVertexCount = 0,
		totalSkinVertexCount = 0,
		totalTriangleCount = 0,
		sourceVertexWrappersAvoided = 0,
		buildMilliseconds = 0,
		rtxCleanupPending = activeRTXMeshBuild and true or nil,
		probe = {},
	}

	for meshIndex, modelMesh in ipairs( modelMeshes ) do
		MaybeYieldModelMeshBuild()
		-- ModelMeshData intentionally spells this field `verticies`. Prefer it
		-- because it represents each mesh vertex once; fall back to triangle soup.
		local sourceVertices = modelMesh.verticies
		local sourceKind = "verticies"
		if not sourceVertices or #sourceVertices == 0 then
			sourceVertices = modelMesh.vertices
			sourceKind = "vertices"
		end
		if not sourceVertices or #sourceVertices == 0 then
			sourceVertices = modelMesh.triangles or {}
			sourceKind = "triangles"
		end

		local cachedMesh = {
			meshIndex = meshIndex,
			material = modelMesh.material or "",
			sourceKind = sourceKind,
			vertices = not compactSourceFingerprint and {} or nil,
			persistedVertexCount = compactSourceFingerprint and 0 or nil,
			triangles = {},
			spatialFallbackGroups = {},
			skinVertices = {},
		}
		local spatialFallbackLookup = {}
		local skinVertexLookup = {}
		local sampleSourceVertex
		if compactSourceFingerprint then
			if activeRTXMeshBuild then
				-- Keep RTX's established count/fingerprint loops: the fused metadata
				-- branch did not improve its LuaJIT CPU time on the measured model.
				for vertexIndex, vertex in ipairs( sourceVertices ) do
					if vertexIndex % 64 == 0 then MaybeYieldModelMeshBuild() end
					if vertex.pos then
						cachedMesh.persistedVertexCount = cachedMesh.persistedVertexCount + 1
						sampleSourceVertex = sampleSourceVertex or vertex
					end
				end
				cachedMesh.damageFingerprint = BBS.BuildRawMeshDamageFingerprint(
					modelMesh, MaybeYieldModelMeshBuild, true )
			else
				-- Vanilla counts/samples directly while fingerprinting. This removes
				-- the temporary wrapper graph formerly retained until eligibility.
				cachedMesh.damageFingerprint, cachedMesh.persistedVertexCount,
					sampleSourceVertex = BBS.BuildRawMeshDamageFingerprint(
						modelMesh, MaybeYieldModelMeshBuild )
			end
		else
			for vertexIndex, vertex in ipairs( sourceVertices ) do
				if vertexIndex % 64 == 0 then MaybeYieldModelMeshBuild() end
				if vertex.pos then
					cachedMesh.vertices[ #cachedMesh.vertices + 1 ] = {
						vertexIndex = vertexIndex,
						position = vertex.pos,
						u = tonumber( vertex.u ),
						v = tonumber( vertex.v ),
					}
					sampleSourceVertex = sampleSourceVertex or vertex
				end
			end
		end

		local triangleVertices = modelMesh.triangles or {}
		local triangleIndex = 0
		local boneSet = {}
		for triangleOffset = 1, #triangleVertices - 2, 3 do
			triangleIndex = triangleIndex + 1
			if triangleIndex % 16 == 0 then MaybeYieldModelMeshBuild() end
			local first = triangleVertices[ triangleOffset ]
			local second = triangleVertices[ triangleOffset + 1 ]
			local third = triangleVertices[ triangleOffset + 2 ]
			if first.pos and second.pos and third.pos then
				local firstSkin = GetOrCreateSkinVertex( skinVertexLookup,
					cachedMesh.skinVertices, first )
				local secondSkin = GetOrCreateSkinVertex( skinVertexLookup,
					cachedMesh.skinVertices, second )
				local thirdSkin = GetOrCreateSkinVertex( skinVertexLookup,
					cachedMesh.skinVertices, third )
				local cachedTriangle = {
					triangleIndex = triangleIndex,
					firstSkin, tonumber( first.u ) or false,
						tonumber( first.v ) or false,
					secondSkin, tonumber( second.u ) or false,
						tonumber( second.v ) or false,
					thirdSkin, tonumber( third.u ) or false,
						tonumber( third.v ) or false,
				}
				cachedMesh.triangles[ #cachedMesh.triangles + 1 ] = cachedTriangle
				local rigidBone = isnumber( firstSkin.rigidBone )
					and firstSkin.rigidBone == secondSkin.rigidBone
					and firstSkin.rigidBone == thirdSkin.rigidBone
					and firstSkin.rigidBone or nil
				if rigidBone ~= nil then
					local modelCenter, modelRadius = TriangleModelSphere(
						first, second, third )
					local sphereX, sphereY, sphereZ, sphereRadius = TriangleBoneSphere(
						data.poseToBone[ rigidBone ], modelCenter, modelRadius )
					if sphereX ~= nil then
						ExpandBoneMeshTriangleBounds( data, rigidBone,
							cachedMesh.meshIndex, sphereX, sphereY, sphereZ,
							sphereRadius )
						local entries = data.boneTriangles[ rigidBone ] or {}
						data.boneTriangles[ rigidBone ] = entries
						local offset = #entries
						entries[ offset + 1 ], entries[ offset + 2 ] =
							cachedMesh, cachedTriangle
						entries[ offset + 3 ], entries[ offset + 4 ] =
							sphereX, sphereY
						entries[ offset + 5 ], entries[ offset + 6 ] =
							sphereZ, sphereRadius
						data.spatialIndexedTriangleCount =
							data.spatialIndexedTriangleCount + 1
					else
						rigidBone = nil
					end
				end
				if rigidBone == nil then
					for boneId in pairs( boneSet ) do boneSet[ boneId ] = nil end
					CollectVertexBones( boneSet, firstSkin )
					CollectVertexBones( boneSet, secondSkin )
					CollectVertexBones( boneSet, thirdSkin )
					BBS.AddSpatialFallbackTriangle( cachedMesh,
						spatialFallbackLookup, boneSet, cachedTriangle,
						first.pos, second.pos, third.pos )
					data.spatialUnindexedTriangleCount =
						data.spatialUnindexedTriangleCount + 1
				end
			end
		end
		BBS.FinalizeSpatialFallbackGroups( cachedMesh )
		if compactSourceFingerprint then
			data.sourceVertexWrappersAvoided = data.sourceVertexWrappersAvoided
				+ cachedMesh.persistedVertexCount
		end

		data.totalVertexCount = data.totalVertexCount
			+ ( cachedMesh.persistedVertexCount or #cachedMesh.vertices )
		data.totalSkinVertexCount = data.totalSkinVertexCount + #cachedMesh.skinVertices
		data.totalTriangleCount = data.totalTriangleCount + #cachedMesh.triangles
		data.meshes[ #data.meshes + 1 ] = cachedMesh
		if not data.probe.sampleVertex and sampleSourceVertex then
			-- Retain one complete engine vertex for explicit diagnostics only. The
			-- per-mesh mirror above keeps just position/UV fingerprint fields, avoiding
			-- tens of thousands of references back into ModelMeshData's large graphs.
			if BBS.IsActiveRTXRuntime and BBS.IsActiveRTXRuntime() then
				-- Do not couple the lifetime of RTX's native ModelMeshData graph to a
				-- diagnostic sample.  Copy the readable scalar shape that the probe and
				-- persistent metadata need; vanilla retains its established raw probe.
				local sampleWeights = {}
				local rawSampleWeights = sampleSourceVertex.weights or {}
				if isnumber( rawSampleWeights[ 1 ] ) then
					for index = 1, #rawSampleWeights do
						sampleWeights[ index ] = rawSampleWeights[ index ]
					end
				else
					for _, boneWeight in ipairs( rawSampleWeights ) do
						sampleWeights[ #sampleWeights + 1 ] = boneWeight.bone or 0
						sampleWeights[ #sampleWeights + 1 ] = boneWeight.weight or 0
					end
				end
				local samplePosition = sampleSourceVertex.pos
				data.probe.sampleVertex = {
					pos = Vector( samplePosition.x, samplePosition.y,
						samplePosition.z ),
					u = tonumber( sampleSourceVertex.u ) or 0,
					v = tonumber( sampleSourceVertex.v ) or 0,
					weights = sampleWeights,
				}
			else
				data.probe.sampleVertex = sampleSourceVertex
			end
			data.probe.sampleMesh = {
				meshIndex = meshIndex,
				material = cachedMesh.material,
				sourceKind = sourceKind,
				vertexCount = cachedMesh.persistedVertexCount
					or #cachedMesh.vertices,
				triangleCount = #cachedMesh.triangles,
				hasVerticies = modelMesh.verticies ~= nil,
				hasVertices = modelMesh.vertices ~= nil,
				hasTriangles = modelMesh.triangles ~= nil,
			}
		end
		-- The compact cache now owns everything required from this mesh. Releasing
		-- the native table as we advance lowers the peak retained graph during a
		-- cold build; ipairs reads the next numeric slot directly.
		modelMeshes[ meshIndex ] = nil
	end
	for bindIndex, bindPose in pairs( bindPoses ) do
		data.probe.sampleBindIndex = bindIndex
		if BBS.IsActiveRTXRuntime and BBS.IsActiveRTXRuntime() then
			data.probe.sampleBindPose = {
				matrix = bindPose.matrix and bindPose.matrix:ToTable() or nil,
			}
		else
			data.probe.sampleBindPose = bindPose
		end
		break
	end

	data.buildMilliseconds = ( SysTime() - started ) * 1000
	TouchModelMeshCache( data )
	BBS.ModelMeshCache[ key ] = data
	BBS.ModelMeshNegativeAccess[ key ] = nil
	BBS.TrimModelMeshCache( key )
	BBS.ModelMeshCacheStats.builds = BBS.ModelMeshCacheStats.builds + 1
	BBS.MeshCacheEvictionGCSteps = math.min(
		( BBS.MeshCacheEvictionGCSteps or 0 ) + #data.meshes * 4, 256 )
	if GetBool( "bbs_debug_console" ) then
		BBS.Log( "mesh cache built: %d source vertices / %d skin points / %d triangles / %d meshes in %.2f ms (%s)",
			data.totalVertexCount, data.totalSkinVertexCount,
			data.totalTriangleCount, #data.meshes,
			data.buildMilliseconds, key )
	end
	return data, false
end
BBS.GetCachedModelMeshesForIdentity = GetCachedModelMeshesForIdentity

function BBS.GetCachedModelMeshes( entity, lod )
	lod = lod or 0
	if not IsValid( entity ) then return nil, false, "invalid entity" end
	local key, model, bodygroups, skin = MeshCacheKey( entity, lod )
	return GetCachedModelMeshesForIdentity(
		key, model, bodygroups, skin, lod )
end

local function CaptureCurrentBoneMatrices( entity )
	entity:SetupBones()
	local output = {}
	for boneId = 0, math.max( ( entity:GetBoneCount() or 0 ) - 1, -1 ) do
		local current = entity:GetBoneMatrix( boneId )
		-- Matrix multiplication returns a detached value; retaining the engine's
		-- GetBoneMatrix object itself can allow a later SetupBones to mutate it.
		if current then output[ boneId ] = current * Matrix() end
	end
	return output
end

local function BuildSkinTransforms( entity, meshData, mode, currentBoneSnapshot )
	if not currentBoneSnapshot then entity:SetupBones() end
	mode = mode or "current*poseToBone"
	local transforms = {
		fallbackOrigin = entity:GetPos(),
		fallbackAngles = entity:GetAngles(),
		mode = mode,
		currentBones = {},
	}
	local bindTransforms = mode == "legacy-current*inverse(poseToBone)"
		and meshData.inversePoseToBone or meshData.poseToBone
	for boneId, poseTransform in pairs( bindTransforms or {} ) do
		local current = currentBoneSnapshot and currentBoneSnapshot[ boneId ]
			or entity:GetBoneMatrix( boneId )
		if current then
			transforms.currentBones[ boneId ] = current
			transforms[ boneId ] = current * poseTransform
		end
	end
	return transforms
end

local function SkinCachedVertex( transforms, vertex, control )
	local skin = vertex.skin or vertex
	local posedCache = control and control.posedCache or nil
	if posedCache then
		local cached = posedCache[ skin ]
		if cached ~= nil then return cached ~= false and cached or nil, true end
	end
	local position = skin.position
	local weights = skin.weights
	if not weights or #weights == 0 then
		local root = transforms[ 0 ]
		if root then
			local result = root * position
			if posedCache then posedCache[ skin ] = result end
			return result, false
		end
		local worldPosition = LocalToWorld( position, ZERO_ANGLE,
			transforms.fallbackOrigin, transforms.fallbackAngles )
		if posedCache then posedCache[ skin ] = worldPosition end
		return worldPosition, false
	end

	if #weights == 2 then
		local transform = transforms[ weights[ 1 ] or 0 ]
		local result = transform and ( transform * position ) or nil
		if not result and ( weights[ 1 ] or 0 ) == 0 then
			-- Native weightless vertices are canonicalized to {0, 1}. Preserve
			-- the old empty-weight fallback for unusual models without bone 0.
			result = LocalToWorld( position, ZERO_ANGLE,
				transforms.fallbackOrigin, transforms.fallbackAngles )
		end
		if posedCache then posedCache[ skin ] = result or false end
		return result, false
	end

	local accumulatedX, accumulatedY, accumulatedZ = 0, 0, 0
	local totalWeight = 0
	for index = 1, #weights - 1, 2 do
		local weight = weights[ index + 1 ] or 0
		local transform = transforms[ weights[ index ] or 0 ]
		if transform and weight > 0 then
			local transformed = transform * position
			accumulatedX = accumulatedX + transformed.x * weight
			accumulatedY = accumulatedY + transformed.y * weight
			accumulatedZ = accumulatedZ + transformed.z * weight
			totalWeight = totalWeight + weight
		end
	end
	if totalWeight <= 0 then
		if posedCache then posedCache[ skin ] = false end
		return nil, false
	end
	if math.abs( totalWeight - 1 ) > 0.001 then
		accumulatedX = accumulatedX / totalWeight
		accumulatedY = accumulatedY / totalWeight
		accumulatedZ = accumulatedZ / totalWeight
	end
	local accumulated = Vector( accumulatedX, accumulatedY, accumulatedZ )
	if posedCache then posedCache[ skin ] = accumulated end
	return accumulated, false
end

local function InwardCylinderDirection( hitDirection, surfaceNormal )
	local inward = hitDirection:GetNormalized()
	if inward:Dot( surfaceNormal ) > 0 then inward = -inward end
	return inward
end

local function PointInsideCylinder( point, surfacePosition, inwardDirection,
	radiusSquared, insideDistance, outsideDistance )
	-- This function is called again for every selected corner. Do the projection
	-- with scalars to avoid allocating a temporary relative Vector each time.
	local dx = point.x - surfacePosition.x
	local dy = point.y - surfacePosition.y
	local dz = point.z - surfacePosition.z
	local axialDistance = dx * inwardDirection.x
		+ dy * inwardDirection.y + dz * inwardDirection.z
	if axialDistance < -outsideDistance or axialDistance > insideDistance then return false end
	local radialSquared = dx * dx + dy * dy + dz * dz
		- axialDistance * axialDistance
	return radialSquared <= radiusSquared + 0.0001
end

local function ClosestPointOnTriangle( point, first, second, third )
	local firstSecond = second - first
	local firstThird = third - first
	local firstPoint = point - first
	local d1 = firstSecond:Dot( firstPoint )
	local d2 = firstThird:Dot( firstPoint )
	if d1 <= 0 and d2 <= 0 then return first end

	local secondPoint = point - second
	local d3 = firstSecond:Dot( secondPoint )
	local d4 = firstThird:Dot( secondPoint )
	if d3 >= 0 and d4 <= d3 then return second end

	local vc = d1 * d4 - d3 * d2
	if vc <= 0 and d1 >= 0 and d3 <= 0 then
		return first + firstSecond * ( d1 / ( d1 - d3 ) )
	end

	local thirdPoint = point - third
	local d5 = firstSecond:Dot( thirdPoint )
	local d6 = firstThird:Dot( thirdPoint )
	if d6 >= 0 and d5 <= d6 then return third end

	local vb = d5 * d2 - d1 * d6
	if vb <= 0 and d2 >= 0 and d6 <= 0 then
		return first + firstThird * ( d2 / ( d2 - d6 ) )
	end

	local va = d3 * d6 - d5 * d4
	if va <= 0 and ( d4 - d3 ) >= 0 and ( d5 - d6 ) >= 0 then
		return second + ( third - second )
			* ( ( d4 - d3 ) / ( ( d4 - d3 ) + ( d5 - d6 ) ) )
	end

	local denominator = 1 / ( va + vb + vc )
	return first + firstSecond * ( vb * denominator ) + firstThird * ( vc * denominator )
end

local function SegmentIntersectsTriangle( segmentStart, segmentEnd, first, second, third )
	local direction = segmentEnd - segmentStart
	local edgeOne = second - first
	local edgeTwo = third - first
	local cross = direction:Cross( edgeTwo )
	local determinant = edgeOne:Dot( cross )
	if math.abs( determinant ) < 0.000001 then return false, nil, nil, nil end

	local inverse = 1 / determinant
	local offset = segmentStart - first
	local u = inverse * offset:Dot( cross )
	if u < 0 or u > 1 then return false, nil, nil, nil end
	local q = offset:Cross( edgeOne )
	local v = inverse * direction:Dot( q )
	if v < 0 or u + v > 1 then return false, nil, nil, nil end
	local fraction = inverse * edgeTwo:Dot( q )
	if fraction < 0 or fraction > 1 then return false, nil, nil, nil end
	-- Preserve the Moller-Trumbore barycentric coordinates. The damage layer
	-- resolver uses these to sample the exact texture point crossed by the bullet
	-- centerline and can therefore let later shots pass through an existing hole.
	return true, fraction, u, v
end

local function ClosestPointsOnSegments( firstStart, firstEnd, secondStart, secondEnd )
	local firstDirection = firstEnd - firstStart
	local secondDirection = secondEnd - secondStart
	local relative = firstStart - secondStart
	local firstLengthSquared = firstDirection:Dot( firstDirection )
	local secondLengthSquared = secondDirection:Dot( secondDirection )
	local secondRelative = secondDirection:Dot( relative )
	local firstFraction, secondFraction

	if firstLengthSquared <= 0.000001 and secondLengthSquared <= 0.000001 then
		return firstStart, secondStart
	elseif firstLengthSquared <= 0.000001 then
		firstFraction = 0
		secondFraction = math.Clamp( secondRelative / secondLengthSquared, 0, 1 )
	else
		local firstRelative = firstDirection:Dot( relative )
		if secondLengthSquared <= 0.000001 then
			secondFraction = 0
			firstFraction = math.Clamp( -firstRelative / firstLengthSquared, 0, 1 )
		else
			local directionsDot = firstDirection:Dot( secondDirection )
			local denominator = firstLengthSquared * secondLengthSquared
				- directionsDot * directionsDot
			if denominator ~= 0 then
				firstFraction = math.Clamp(
					( directionsDot * secondRelative - firstRelative * secondLengthSquared )
					/ denominator, 0, 1 )
			else
				firstFraction = 0
			end
			secondFraction = ( directionsDot * firstFraction + secondRelative )
				/ secondLengthSquared
			if secondFraction < 0 then
				secondFraction = 0
				firstFraction = math.Clamp( -firstRelative / firstLengthSquared, 0, 1 )
			elseif secondFraction > 1 then
				secondFraction = 1
				firstFraction = math.Clamp(
					( directionsDot - firstRelative ) / firstLengthSquared, 0, 1 )
			end
		end
	end

	return firstStart + firstDirection * firstFraction,
		secondStart + secondDirection * secondFraction
end

local function EdgeIntersectsCylinder( edgeStart, edgeEnd, axisStart, axisEnd,
	surfacePosition, inwardDirection, radiusSquared, insideDistance, outsideDistance )
	local edgePoint, axisPoint = ClosestPointsOnSegments(
		edgeStart, edgeEnd, axisStart, axisEnd )
	if edgePoint:DistToSqr( axisPoint ) <= radiusSquared + 0.0001
	and PointInsideCylinder( edgePoint, surfacePosition, inwardDirection,
		radiusSquared, insideDistance, outsideDistance ) then
		return true, edgePoint
	end
	return false, nil
end

local function CylinderAxialDepth( point, surfacePosition, inwardDirection )
	local relative = point - surfacePosition
	return relative:Dot( inwardDirection )
end

local function TriangleIntersectsCylinder( first, second, third, surfacePosition,
	inwardDirection, radiusSquared, insideDistance, outsideDistance,
	outsideEnd, insideEnd, closestToCenter, needLayerDepth )
	outsideEnd = outsideEnd or surfacePosition - inwardDirection * outsideDistance
	insideEnd = insideEnd or surfacePosition + inwardDirection * insideDistance
	local centerlineHit, centerlineFraction, centerlineU, centerlineV =
		SegmentIntersectsTriangle(
		outsideEnd, insideEnd, first, second, third )
	if centerlineHit then
		if not needLayerDepth then return true end
		return true, -outsideDistance + centerlineFraction
			* ( outsideDistance + insideDistance ), centerlineU, centerlineV
	end
	if not needLayerDepth then
		-- Unlimited normal gameplay uses only the boolean intersection. Preserve the
		-- old short-circuit order instead of computing all seven candidates and an
		-- earliest layer depth which no downstream stage consumes.
		if PointInsideCylinder( first, surfacePosition, inwardDirection,
			radiusSquared, insideDistance, outsideDistance ) then return true end
		if PointInsideCylinder( second, surfacePosition, inwardDirection,
			radiusSquared, insideDistance, outsideDistance ) then return true end
		if PointInsideCylinder( third, surfacePosition, inwardDirection,
			radiusSquared, insideDistance, outsideDistance ) then return true end
		closestToCenter = closestToCenter
			or ClosestPointOnTriangle( surfacePosition, first, second, third )
		if PointInsideCylinder( closestToCenter, surfacePosition, inwardDirection,
			radiusSquared, insideDistance, outsideDistance ) then return true end
		if EdgeIntersectsCylinder( first, second, outsideEnd, insideEnd,
			surfacePosition, inwardDirection, radiusSquared,
			insideDistance, outsideDistance ) then return true end
		if EdgeIntersectsCylinder( second, third, outsideEnd, insideEnd,
			surfacePosition, inwardDirection, radiusSquared,
			insideDistance, outsideDistance ) then return true end
		local edgeHit = EdgeIntersectsCylinder(
			third, first, outsideEnd, insideEnd,
			surfacePosition, inwardDirection, radiusSquared,
			insideDistance, outsideDistance )
		return edgeHit
	end

	local found = false
	local earliestDepth = math.huge
	local function ConsiderPoint( point )
		if not point then return end
		found = true
		earliestDepth = math.min( earliestDepth,
			CylinderAxialDepth( point, surfacePosition, inwardDirection ) )
	end
	if PointInsideCylinder( first, surfacePosition, inwardDirection,
		radiusSquared, insideDistance, outsideDistance ) then ConsiderPoint( first ) end
	if PointInsideCylinder( second, surfacePosition, inwardDirection,
		radiusSquared, insideDistance, outsideDistance ) then ConsiderPoint( second ) end
	if PointInsideCylinder( third, surfacePosition, inwardDirection,
		radiusSquared, insideDistance, outsideDistance ) then ConsiderPoint( third ) end
	closestToCenter = closestToCenter
		or ClosestPointOnTriangle( surfacePosition, first, second, third )
	if PointInsideCylinder( closestToCenter, surfacePosition, inwardDirection,
		radiusSquared, insideDistance, outsideDistance ) then
		ConsiderPoint( closestToCenter )
	end
	local edgeHit, edgePoint = EdgeIntersectsCylinder( first, second,
		outsideEnd, insideEnd, surfacePosition, inwardDirection, radiusSquared,
		insideDistance, outsideDistance )
	if edgeHit then ConsiderPoint( edgePoint ) end
	edgeHit, edgePoint = EdgeIntersectsCylinder( second, third,
		outsideEnd, insideEnd, surfacePosition, inwardDirection, radiusSquared,
		insideDistance, outsideDistance )
	if edgeHit then ConsiderPoint( edgePoint ) end
	edgeHit, edgePoint = EdgeIntersectsCylinder( third, first,
		outsideEnd, insideEnd, surfacePosition, inwardDirection, radiusSquared,
		insideDistance, outsideDistance )
	if edgeHit then ConsiderPoint( edgePoint ) end
	return found, found and math.Clamp( earliestDepth,
		-outsideDistance, insideDistance ) or nil, nil, nil
end

local function AddCandidateBoneAndNeighbors( entity, boneId, result )
	if not boneId or boneId < 0 then return end
	result[ boneId ] = true

	local parent = entity:GetBoneParent( boneId )
	if parent and parent >= 0 then
		result[ parent ] = true
		for _, sibling in ipairs( entity:GetChildBones( parent ) or {} ) do
			result[ sibling ] = true
		end
		local grandparent = entity:GetBoneParent( parent )
		if grandparent and grandparent >= 0 then
			result[ grandparent ] = true
			for _, branch in ipairs( entity:GetChildBones( grandparent ) or {} ) do
				result[ branch ] = true
			end
		end
	end

	local children = entity:GetChildBones( boneId ) or {}
	for _, child in ipairs( children ) do result[ child ] = true end
end

local function AllTriangleCandidates( meshData, allowedMeshes )
	local candidates = {}
	local triangleCount = 0
	for _, cachedMesh in ipairs( meshData.meshes ) do
		if not allowedMeshes or allowedMeshes[ cachedMesh.meshIndex ] then
			candidates[ #candidates + 1 ] = {
				cachedMesh = cachedMesh,
				triangles = cachedMesh.triangles,
			}
			triangleCount = triangleCount + #cachedMesh.triangles
		end
	end
	return candidates, triangleCount, true, {}, {
		spatial = false,
		unfilteredCount = triangleCount,
		spatialRejectedCount = 0,
		neighborBoneCount = 0,
		spatialBoneCount = 0,
		candidateBoneCount = 0,
		boneBoundsTestCount = 0,
		boneBoundsAvailable = false,
	}
end

local function PointBoundsDistanceSquared( point, bounds )
	local dx, dy, dz = 0, 0, 0
	if point.x < bounds.minimumX then
		dx = bounds.minimumX - point.x
	elseif point.x > bounds.maximumX then
		dx = point.x - bounds.maximumX
	end
	if point.y < bounds.minimumY then
		dy = bounds.minimumY - point.y
	elseif point.y > bounds.maximumY then
		dy = point.y - bounds.maximumY
	end
	if point.z < bounds.minimumZ then
		dz = bounds.minimumZ - point.z
	elseif point.z > bounds.maximumZ then
		dz = point.z - bounds.maximumZ
	end
	return dx * dx + dy * dy + dz * dz
end

local function PointAABBDistanceSquared( point, minimumX, minimumY, minimumZ,
	maximumX, maximumY, maximumZ )
	local dx, dy, dz = 0, 0, 0
	if point.x < minimumX then
		dx = minimumX - point.x
	elseif point.x > maximumX then
		dx = point.x - maximumX
	end
	if point.y < minimumY then
		dy = minimumY - point.y
	elseif point.y > maximumY then
		dy = point.y - maximumY
	end
	if point.z < minimumZ then
		dz = minimumZ - point.z
	elseif point.z > maximumZ then
		dz = point.z - maximumZ
	end
	return dx * dx + dy * dy + dz * dz
end

local function BuildTriangleCandidates( entity, meshData, hitBone,
	surfacePosition, maximumReach, transforms, allowedMeshes, control )
	if not hitBone or hitBone < 0 or not meshData.boneTriangles
	or meshData.boneTriangleStride ~= 6 then
		return AllTriangleCandidates( meshData, allowedMeshes )
	end

	local candidateBones = {}
	AddCandidateBoneAndNeighbors( entity, hitBone, candidateBones )
	local localHitByBone = {}
	local function LocalHitForBone( boneId )
		local cached = localHitByBone[ boneId ]
		if cached ~= nil then return cached or nil end
		local current = transforms and transforms.currentBones
			and transforms.currentBones[ boneId ] or nil
		if current then
			cached = current:GetInverseTR() * surfacePosition
			localHitByBone[ boneId ] = cached
			return cached
		end
		-- `false` distinguishes a missing transform from an uncached lookup.
		localHitByBone[ boneId ] = false
		return nil
	end
	local padding = math.Clamp( GetFloat( "bbs_mesh_candidate_padding", 2 ), 0, 16 )
	local reach = maximumReach + padding
	local reachSquared = reach * reach
	local neighborBoneCount = table.Count( candidateBones )
	local spatialBoneCount = 0
	local boneBoundsTestCount = 0
	local boneBoundsAvailable = meshData.boneMeshBounds
		and next( meshData.boneMeshBounds ) ~= nil or false
	local transformScaleByBone = {}
	local function TransformRadiusScale( boneId, transform )
		local cached = transformScaleByBone[ boneId ]
		if cached then return cached end
		-- Source bone matrices are normally rigid, but authored model scale must
		-- enlarge the conservative fallback sphere as well. Cache this once per
		-- influence bone rather than allocating a scale vector for every group.
		local scale = transform:GetScale()
		cached = math.max( math.abs( scale.x ), math.abs( scale.y ),
			math.abs( scale.z ), 0.000001 )
		transformScaleByBone[ boneId ] = cached
		return cached
	end
	local function FallbackGroupOverlaps( group )
		if not group.modelCenter or not transforms then return true end
		local minimumX, minimumY, minimumZ = math.huge, math.huge, math.huge
		local maximumX, maximumY, maximumZ = -math.huge, -math.huge, -math.huge
		local modelRadius = math.max( tonumber( group.modelRadius ) or 0, 0 )
		local foundTransform = false
		for _, boneId in ipairs( group.boneIds or {} ) do
			local transform = transforms[ boneId ]
			-- Missing pose data cannot prove separation. Keep the group so an
			-- unusual skeleton never loses visible collisionless clothing.
			if not transform then return true end
			foundTransform = true
			local center = transform * group.modelCenter
			local radius = modelRadius * TransformRadiusScale( boneId, transform )
			minimumX = math.min( minimumX, center.x - radius )
			minimumY = math.min( minimumY, center.y - radius )
			minimumZ = math.min( minimumZ, center.z - radius )
			maximumX = math.max( maximumX, center.x + radius )
			maximumY = math.max( maximumY, center.y + radius )
			maximumZ = math.max( maximumZ, center.z + radius )
		end
		if not foundTransform then return true end
		-- A linearly-blended point lies in the convex hull of its influence-bone
		-- transforms. Their union AABB, expanded by the bind-space group radius,
		-- is therefore a conservative broad phase for the whole group.
		return PointAABBDistanceSquared( surfacePosition,
			minimumX, minimumY, minimumZ,
			maximumX, maximumY, maximumZ ) <= reachSquared
	end

	-- Collision hitbones describe the physics hull, not necessarily the first
	-- visible surface. A coat, skirt, or equipment shell can be weighted to a
	-- spine bone while a bullet trace reports the thigh underneath it. Discover
	-- every posed bone partition whose eligible visual bounds overlap the sphere
	-- enclosing this cylinder; the per-triangle spheres below then prune it.
	for boneId, meshBounds in pairs( meshData.boneMeshBounds or {} ) do
		local localHit = LocalHitForBone( boneId )
		if localHit then
			for meshIndex, bounds in pairs( meshBounds ) do
				if control then
					control.boneBoundsSteps =
						( control.boneBoundsSteps or 0 ) + 1
					if control.boneBoundsSteps % 32 == 0
					and SysTime() >= ( control.deadline or math.huge ) then
						coroutine.yield()
					end
				end
				if not allowedMeshes or allowedMeshes[ meshIndex ] then
					boneBoundsTestCount = boneBoundsTestCount + 1
					if PointBoundsDistanceSquared( localHit, bounds ) <= reachSquared then
						if not candidateBones[ boneId ] then
							candidateBones[ boneId ] = true
							spatialBoneCount = spatialBoneCount + 1
						end
						break
					end
				end
			end
		end
	end
	for boneId in pairs( candidateBones ) do LocalHitForBone( boneId ) end

	local function Gather( useSpatialFilter )
		local byMesh = {}
		local ordered = {}
		local count = 0
		local unfilteredCount = 0
		local rejectedCount = 0
		local fallbackGroupTestCount = 0
		local fallbackGroupRejectedCount = 0
		local fallbackTriangleAcceptedCount = 0
		for boneId in pairs( candidateBones ) do
			local localHit = localHitByBone[ boneId ]
			local entries = meshData.boneTriangles[ boneId ] or {}
			for entryIndex = 1, #entries, 6 do
				if control then
					control.candidateSteps = ( control.candidateSteps or 0 ) + 1
					if control.candidateSteps % 128 == 0
					and SysTime() >= ( control.deadline or math.huge ) then
						coroutine.yield()
					end
				end
				-- Rigid triangles have exactly one influence bone and therefore exactly
				-- one bucket. Blended triangles live only in one fallback leaf below.
				local entryMesh = entries[ entryIndex ]
				local entryTriangle = entries[ entryIndex + 1 ]
				if entryMesh and entryTriangle
				and ( not allowedMeshes or allowedMeshes[ entryMesh.meshIndex ] ) then
					unfilteredCount = unfilteredCount + 1
					local accepted = true
					if useSpatialFilter and localHit then
						local dx = localHit.x - entries[ entryIndex + 2 ]
						local dy = localHit.y - entries[ entryIndex + 3 ]
						local dz = localHit.z - entries[ entryIndex + 4 ]
						local maximumDistance = reach
							+ entries[ entryIndex + 5 ]
						accepted = dx * dx + dy * dy + dz * dz
							<= maximumDistance * maximumDistance
						if not accepted then rejectedCount = rejectedCount + 1 end
					end
					if accepted then
						local group = byMesh[ entryMesh ]
						if not group then
							group = { cachedMesh = entryMesh, triangles = {} }
							byMesh[ entryMesh ] = group
							ordered[ #ordered + 1 ] = group
						end
						group.triangles[ #group.triangles + 1 ] = entryTriangle
						count = count + 1
					end
				end
			end
		end
		-- A blended vertex is a weighted sum of several posed bones; no one
		-- per-bone bind sphere conservatively contains it. Groups share a compact
		-- influence signature and conservative posed bound, avoiding the old full
		-- scan of every blended coat/hair/equipment triangle on every shot.
		for _, cachedMesh in ipairs( meshData.meshes or {} ) do
			if not allowedMeshes or allowedMeshes[ cachedMesh.meshIndex ] then
				for _, fallbackGroup in ipairs(
					cachedMesh.spatialFallbackGroups or {} ) do
					if control then
						control.candidateSteps =
							( control.candidateSteps or 0 ) + 1
						if control.candidateSteps % 32 == 0
						and SysTime() >= ( control.deadline or math.huge ) then
							coroutine.yield()
						end
					end
					fallbackGroupTestCount = fallbackGroupTestCount + 1
					local triangles = fallbackGroup.triangles or {}
					unfilteredCount = unfilteredCount + #triangles
					local accepted = not useSpatialFilter
						or FallbackGroupOverlaps( fallbackGroup )
					if not accepted then
						fallbackGroupRejectedCount = fallbackGroupRejectedCount + 1
						rejectedCount = rejectedCount + #triangles
					else
						local outputGroup = byMesh[ cachedMesh ]
						if not outputGroup then
							outputGroup = { cachedMesh = cachedMesh, triangles = {} }
							byMesh[ cachedMesh ] = outputGroup
							ordered[ #ordered + 1 ] = outputGroup
						end
						for _, triangle in ipairs( triangles ) do
							outputGroup.triangles[
								#outputGroup.triangles + 1 ] = triangle
							count = count + 1
							fallbackTriangleAcceptedCount =
								fallbackTriangleAcceptedCount + 1
						end
					end
				end
			end
		end
		return ordered, count, unfilteredCount, rejectedCount,
			fallbackGroupTestCount, fallbackGroupRejectedCount,
			fallbackTriangleAcceptedCount
	end

	local ordered, count, unfilteredCount, rejectedCount,
		fallbackGroupTestCount, fallbackGroupRejectedCount,
		fallbackTriangleAcceptedCount = Gather( true )
	local spatialFallback = false
	if count == 0 then
		ordered, count, unfilteredCount, rejectedCount,
			fallbackGroupTestCount, fallbackGroupRejectedCount,
			fallbackTriangleAcceptedCount = Gather( false )
		spatialFallback = true
	end
	if count == 0 then return AllTriangleCandidates( meshData, allowedMeshes ) end
	return ordered, count, false, candidateBones, {
		spatial = not spatialFallback,
		spatialFallback = spatialFallback,
		unfilteredCount = unfilteredCount,
		spatialRejectedCount = rejectedCount,
		padding = padding,
		neighborBoneCount = neighborBoneCount,
		spatialBoneCount = spatialBoneCount,
		candidateBoneCount = table.Count( candidateBones ),
		boneBoundsTestCount = boneBoundsTestCount,
		boneBoundsAvailable = boneBoundsAvailable,
		fallbackGroupTestCount = fallbackGroupTestCount,
		fallbackGroupRejectedCount = fallbackGroupRejectedCount,
		fallbackTriangleAcceptedCount = fallbackTriangleAcceptedCount,
	}
end

local function MaybeYieldMeshQuery( control )
	if not control then return end
	control.steps = ( control.steps or 0 ) + 1
	if control.steps % 8 == 0 and SysTime() >= ( control.deadline or math.huge ) then
		coroutine.yield()
	end
end

-- Public query used by this debugger and, later, material-removal code.
-- Each result mesh contains posed triangles intersecting the irregular hull's
-- enclosing finite cylinder. Exact edge clipping is performed in UV projection.
function BBS.QueryMeshesInCylinder( entity, surfacePosition, hitDirection, surfaceNormal,
	radius, insideDistance, outsideDistance, candidateBone, control )
	local started = SysTime()
	control = control or {}
	local result = {
		ok = false,
		meshes = {},
		meshCount = 0,
		vertexCount = 0,
		insideVertexCount = 0,
		triangleCount = 0,
		scannedVertexCount = 0,
		skippedVertexCount = 0,
		cacheHit = false,
		queryMilliseconds = 0,
	}

	local meshData, cacheHit, cacheError
	if control.meshData then
		meshData = control.meshData
		cacheHit = control.cacheHit
	else
		meshData, cacheHit, cacheError = BBS.GetCachedModelMeshes( entity, 0 )
	end
	result.cacheHit = cacheHit
	if not meshData then
		result.error = cacheError or "mesh data unavailable"
		result.queryMilliseconds = ( SysTime() - started ) * 1000
		return result
	end

	control.meshData = meshData
	control.cacheHit = cacheHit
	local transforms = control.transforms or BuildSkinTransforms( entity, meshData )
	control.transforms = transforms
	control.posedCache = control.posedCache or {}
	control.scannedVertexCount = control.scannedVertexCount or 0
	control.skippedVertexCount = control.skippedVertexCount or 0
	control.uniqueSkinnedVertexCount = control.uniqueSkinnedVertexCount or 0
	control.reusedSkinnedVertexCount = control.reusedSkinnedVertexCount or 0
	control.intervalRejectedCount = control.intervalRejectedCount or 0
	control.axialIntervalRejectedCount = control.axialIntervalRejectedCount or 0
	control.radialIntervalRejectedCount = control.radialIntervalRejectedCount or 0
	control.exactTestCount = control.exactTestCount or 0
	control.diagnosticClosestPointCount = control.diagnosticClosestPointCount or 0
	local collectDiagnostics = control.collectDiagnostics
	if collectDiagnostics == nil then collectDiagnostics = true end
	local collectRejectedDiagnostics = control.collectRejectedDiagnostics
	if collectRejectedDiagnostics == nil then collectRejectedDiagnostics = true end
	local needLayerDepth = math.max( math.floor(
		tonumber( control.layerLimit ) or 0 ), 0 ) > 0 or collectDiagnostics
	local localBoundsConVar = GetConVar( "bbs_mesh_local_bounds" )
	local useLocalBounds = not localBoundsConVar or localBoundsConVar:GetBool()
	local inwardDirection = InwardCylinderDirection( hitDirection, surfaceNormal )
	local radiusSquared = radius * radius
	local outsideEnd = surfacePosition - inwardDirection * outsideDistance
	local insideEnd = surfacePosition + inwardDirection * insideDistance
	local maximumCylinderReach = math.sqrt( radiusSquared
		+ math.max( insideDistance, outsideDistance ) ^ 2 ) + 0.05

	-- A finite cylinder is wholly contained by the oriented rectangular prism
	-- axis=[-outside,+inside], right=[-radius,+radius], up=[-radius,+radius].
	-- Projection is linear over a triangle, so a disjoint interval on any of
	-- these three axes proves that the triangle cannot intersect the cylinder.
	-- This rejection is conservative: overlap advances to the existing exact
	-- test, while only strict separation (with an epsilon) is discarded.
	local reference = math.abs( inwardDirection.z ) < 0.95
		and Vector( 0, 0, 1 ) or Vector( 0, 1, 0 )
	local cylinderRight = inwardDirection:Cross( reference ):GetNormalized()
	local cylinderUp = cylinderRight:Cross( inwardDirection ):GetNormalized()
	local surfaceX, surfaceY, surfaceZ =
		surfacePosition.x, surfacePosition.y, surfacePosition.z
	local axisX, axisY, axisZ =
		inwardDirection.x, inwardDirection.y, inwardDirection.z
	local rightX, rightY, rightZ =
		cylinderRight.x, cylinderRight.y, cylinderRight.z
	local upX, upY, upZ = cylinderUp.x, cylinderUp.y, cylinderUp.z
	local intervalEpsilon = 0.0001
	local function CylinderIntervalRejection( first, second, third )
		local firstX, firstY, firstZ = first.x - surfaceX,
			first.y - surfaceY, first.z - surfaceZ
		local secondX, secondY, secondZ = second.x - surfaceX,
			second.y - surfaceY, second.z - surfaceZ
		local thirdX, thirdY, thirdZ = third.x - surfaceX,
			third.y - surfaceY, third.z - surfaceZ

		local firstProjection = firstX * axisX + firstY * axisY + firstZ * axisZ
		local secondProjection = secondX * axisX + secondY * axisY + secondZ * axisZ
		local thirdProjection = thirdX * axisX + thirdY * axisY + thirdZ * axisZ
		local minimum = math.min( firstProjection, secondProjection, thirdProjection )
		local maximum = math.max( firstProjection, secondProjection, thirdProjection )
		if maximum < -outsideDistance - intervalEpsilon
		or minimum > insideDistance + intervalEpsilon then return 1 end

		firstProjection = firstX * rightX + firstY * rightY + firstZ * rightZ
		secondProjection = secondX * rightX + secondY * rightY + secondZ * rightZ
		thirdProjection = thirdX * rightX + thirdY * rightY + thirdZ * rightZ
		local radialMinimumX = math.min(
			firstProjection, secondProjection, thirdProjection )
		local radialMaximumX = math.max(
			firstProjection, secondProjection, thirdProjection )

		firstProjection = firstX * upX + firstY * upY + firstZ * upZ
		secondProjection = secondX * upX + secondY * upY + secondZ * upZ
		thirdProjection = thirdX * upX + thirdY * upY + thirdZ * upZ
		local radialMinimumY = math.min(
			firstProjection, secondProjection, thirdProjection )
		local radialMaximumY = math.max(
			firstProjection, secondProjection, thirdProjection )

		-- The triangle's radial projection is contained by this 2D AABB. The
		-- squared distance from the origin to that box is a tighter lower bound
		-- than testing right/up independently, while remaining branch-light and
		-- conservative for every point in the triangle.
		local nearestX = radialMinimumX > 0 and radialMinimumX
			or ( radialMaximumX < 0 and -radialMaximumX or 0 )
		local nearestY = radialMinimumY > 0 and radialMinimumY
			or ( radialMaximumY < 0 and -radialMaximumY or 0 )
		local paddedRadius = radius + intervalEpsilon
		if nearestX * nearestX + nearestY * nearestY
		> paddedRadius * paddedRadius then return 2 end
		return 0
	end
	local candidateMeshes, candidateTriangleCount, fullScan, candidateBones,
		candidateStats = BuildTriangleCandidates( entity, meshData, candidateBone,
			surfacePosition, maximumCylinderReach, transforms,
			control.allowedMeshes, control )
	result.candidateTriangleCount = candidateTriangleCount
	result.totalTriangleCount = meshData.totalTriangleCount
	result.fullScan = fullScan
	result.candidateBones = candidateBones
	result.candidateStats = candidateStats
	result.restrictedToEligibleMeshes = control.allowedMeshes ~= nil

	local function ScanCandidates( groups )
		local scan = {
			nearestDistanceSquared = math.huge,
			nearestVertexDistanceSquared = math.huge,
			meshNearest = collectDiagnostics and {} or nil,
			meshes = {},
			matchingByMesh = {},
			vertexCount = 0,
			insideVertexCount = 0,
			triangleCount = 0,
			validTriangleCount = 0,
			broadPhaseRejectedCount = 0,
			axialIntervalRejectedCount = 0,
			radialIntervalRejectedCount = 0,
			exactTestCount = 0,
			diagnosticClosestPointCount = 0,
			diagnosticSkinSeen = collectDiagnostics and {} or nil,
		}
		local function UpdateVertexDiagnostics( position, skin )
			if not collectDiagnostics then return end
			if scan.diagnosticSkinSeen[ skin ] then return end
			scan.diagnosticSkinSeen[ skin ] = true
			local distanceSquared = position:DistToSqr( surfacePosition )
			if distanceSquared < scan.nearestVertexDistanceSquared then
				scan.nearestVertexDistanceSquared = distanceSquared
				scan.nearestVertexPosition = position
			end
			if not scan.boundsMinimum then
				scan.boundsMinimum = Vector( position.x, position.y, position.z )
				scan.boundsMaximum = Vector( position.x, position.y, position.z )
			else
				local minimum = scan.boundsMinimum
				local maximum = scan.boundsMaximum
				minimum.x = math.min( minimum.x, position.x )
				minimum.y = math.min( minimum.y, position.y )
				minimum.z = math.min( minimum.z, position.z )
				maximum.x = math.max( maximum.x, position.x )
				maximum.y = math.max( maximum.y, position.y )
				maximum.z = math.max( maximum.z, position.z )
			end
		end
		local function AddSelectedVertex( matchingMesh, matchedTriangle,
			triangle, corner, worldPosition )
			local inside = PointInsideCylinder( worldPosition, surfacePosition,
				inwardDirection, radiusSquared, insideDistance, outsideDistance )
			local offset = ( corner - 1 ) * 3
			local selectedVertex = {
				vertexIndex = ( triangle.triangleIndex - 1 ) * 3 + corner,
				worldPosition = worldPosition,
				u = triangle[ offset + 2 ],
				v = triangle[ offset + 3 ],
				inside = inside,
			}
			matchedTriangle.vertices[ #matchedTriangle.vertices + 1 ] = selectedVertex
			matchingMesh.vertices[ #matchingMesh.vertices + 1 ] = selectedVertex
			scan.vertexCount = scan.vertexCount + 1
			if inside then scan.insideVertexCount = scan.insideVertexCount + 1 end
		end
		for _, candidateMesh in ipairs( groups ) do
			local cachedMesh = candidateMesh.cachedMesh
			for _, triangle in ipairs( candidateMesh.triangles ) do
				MaybeYieldMeshQuery( control )
				local first, firstReused = SkinCachedVertex(
					transforms, triangle[ 1 ], control )
				local second, secondReused = SkinCachedVertex(
					transforms, triangle[ 4 ], control )
				local third, thirdReused = SkinCachedVertex(
					transforms, triangle[ 7 ], control )
				control.scannedVertexCount = control.scannedVertexCount + 3
				control.reusedSkinnedVertexCount = control.reusedSkinnedVertexCount
					+ ( firstReused and 1 or 0 ) + ( secondReused and 1 or 0 )
					+ ( thirdReused and 1 or 0 )
				control.uniqueSkinnedVertexCount = control.uniqueSkinnedVertexCount
					+ ( firstReused and 0 or 1 ) + ( secondReused and 0 or 1 )
					+ ( thirdReused and 0 or 1 )
				if not first or not second or not third then
					control.skippedVertexCount = control.skippedVertexCount + 3
				else
					scan.validTriangleCount = scan.validTriangleCount + 1
					local rejection = useLocalBounds
						and CylinderIntervalRejection( first, second, third ) or 0
					if rejection ~= 0 then
						scan.broadPhaseRejectedCount = scan.broadPhaseRejectedCount + 1
						control.intervalRejectedCount = control.intervalRejectedCount + 1
						if rejection == 1 then
							scan.axialIntervalRejectedCount =
								scan.axialIntervalRejectedCount + 1
							control.axialIntervalRejectedCount =
								control.axialIntervalRejectedCount + 1
						else
							scan.radialIntervalRejectedCount =
								scan.radialIntervalRejectedCount + 1
							control.radialIntervalRejectedCount =
								control.radialIntervalRejectedCount + 1
						end
					end

					local closest = nil
					-- Console diagnostics normally need only the geometry which can touch
					-- the removal envelope. Synthetic probes and file dumps can request
					-- the old all-candidate nearest/bounds scan explicitly.
					if collectDiagnostics
					and ( rejection == 0 or collectRejectedDiagnostics ) then
						UpdateVertexDiagnostics( first, triangle[ 1 ] )
						UpdateVertexDiagnostics( second, triangle[ 4 ] )
						UpdateVertexDiagnostics( third, triangle[ 7 ] )
						closest = ClosestPointOnTriangle(
							surfacePosition, first, second, third )
						scan.diagnosticClosestPointCount =
							scan.diagnosticClosestPointCount + 1
						control.diagnosticClosestPointCount =
							control.diagnosticClosestPointCount + 1
						local distanceSquared = closest:DistToSqr( surfacePosition )
						local meshNearest = scan.meshNearest[ cachedMesh.meshIndex ]
						if not meshNearest or distanceSquared < meshNearest.distanceSquared then
							scan.meshNearest[ cachedMesh.meshIndex ] = {
								meshIndex = cachedMesh.meshIndex,
								material = cachedMesh.material,
								triangleIndex = triangle.triangleIndex,
								distanceSquared = distanceSquared,
								position = closest,
							}
						end
						if distanceSquared < scan.nearestDistanceSquared then
							scan.nearestDistanceSquared = distanceSquared
							scan.nearestSurfacePosition = closest
							scan.nearestMeshIndex = cachedMesh.meshIndex
							scan.nearestMaterial = cachedMesh.material
							scan.nearestTriangleIndex = triangle.triangleIndex
							local visualNormal = ( second - first ):Cross( third - first )
							if visualNormal:LengthSqr() > 0.000001 then
								scan.nearestSurfaceNormal = visualNormal:GetNormalized()
							end
						end
					end

					if rejection == 0 then
						scan.exactTestCount = scan.exactTestCount + 1
						control.exactTestCount = control.exactTestCount + 1
					end
					local intersects, layerDepth, centerlineU, centerlineV =
						false, nil, nil, nil
					if rejection == 0 then
						intersects, layerDepth, centerlineU, centerlineV =
							TriangleIntersectsCylinder(
							first, second, third, surfacePosition, inwardDirection,
							radiusSquared, insideDistance, outsideDistance,
							outsideEnd, insideEnd, closest, needLayerDepth )
					end
					if intersects then
						local matchingMesh = scan.matchingByMesh[ cachedMesh.meshIndex ]
						if not matchingMesh then
							matchingMesh = {
								meshIndex = cachedMesh.meshIndex,
								material = cachedMesh.material,
								sourceKind = "triangles",
								vertices = {},
								triangles = {},
							}
							scan.matchingByMesh[ cachedMesh.meshIndex ] = matchingMesh
							scan.meshes[ #scan.meshes + 1 ] = matchingMesh
						end
						local matchedTriangle = {
							triangleIndex = triangle.triangleIndex,
							vertices = {},
						}
						layerDepth = layerDepth or 0
						matchedTriangle.layerDepth = layerDepth
						if isnumber( centerlineU ) and isnumber( centerlineV ) then
							if isnumber( triangle[ 2 ] ) and isnumber( triangle[ 3 ] )
							and isnumber( triangle[ 5 ] ) and isnumber( triangle[ 6 ] )
							and isnumber( triangle[ 8 ] ) and isnumber( triangle[ 9 ] ) then
								local firstWeight = 1 - centerlineU - centerlineV
								matchedTriangle.centerlineUV = {
									u = triangle[ 2 ] * firstWeight
										+ triangle[ 5 ] * centerlineU
										+ triangle[ 8 ] * centerlineV,
									v = triangle[ 3 ] * firstWeight
										+ triangle[ 6 ] * centerlineU
										+ triangle[ 9 ] * centerlineV,
								}
								matchedTriangle.centerlineDepth = layerDepth
							end
						end
						matchingMesh.minimumLayerDepth = math.min(
							matchingMesh.minimumLayerDepth or math.huge, layerDepth )
						matchingMesh.maximumLayerDepth = math.max(
							matchingMesh.maximumLayerDepth or -math.huge, layerDepth )
						AddSelectedVertex( matchingMesh, matchedTriangle,
							triangle, 1, first )
						AddSelectedVertex( matchingMesh, matchedTriangle,
							triangle, 2, second )
						AddSelectedVertex( matchingMesh, matchedTriangle,
							triangle, 3, third )
						matchingMesh.triangles[ #matchingMesh.triangles + 1 ] = matchedTriangle
						scan.triangleCount = scan.triangleCount + 1
					end
				end
			end
		end
		scan.diagnosticSkinSeen = nil
		return scan
	end

	local scan = ScanCandidates( candidateMeshes )
	-- Exact intersection, not optional nearest-surface diagnostics, decides
	-- whether a bone-local result is sufficient. Any intersecting triangle is
	-- necessarily within the cylinder's old enclosing-sphere threshold.
	if not fullScan and scan.triangleCount == 0 then
		local fallback = BBS.QueryMeshesInCylinder( entity, surfacePosition,
			hitDirection, surfaceNormal, radius, insideDistance, outsideDistance,
			nil, control )
		fallback.boneCandidateRejected = true
		fallback.initialCandidateTriangleCount = candidateTriangleCount
		fallback.initialCandidateStats = candidateStats
		return fallback
	end

	local nearestDistanceSquared = scan.nearestDistanceSquared
	local nearestVertexDistanceSquared = scan.nearestVertexDistanceSquared
	local nearestSurfacePosition = scan.nearestSurfacePosition
	local nearestSurfaceNormal = scan.nearestSurfaceNormal
	local nearestVertexPosition = scan.nearestVertexPosition
	local boundsMinimum = scan.boundsMinimum
	local boundsMaximum = scan.boundsMaximum
	result.probe = {
		diagnosticsCollected = collectDiagnostics,
		diagnosticScope = collectDiagnostics and ( collectRejectedDiagnostics
			and "all_candidates" or "interval_survivors" ) or "disabled",
		skinningMode = transforms.mode or "unknown",
		inputSurfacePosition = surfacePosition,
		nearestSurfacePosition = nearestSurfacePosition,
		nearestSurfaceDistance = nearestSurfacePosition
			and math.sqrt( nearestDistanceSquared ) or nil,
		nearestMeshIndex = scan.nearestMeshIndex,
		nearestMaterial = scan.nearestMaterial,
		nearestTriangleIndex = scan.nearestTriangleIndex,
		nearestVertexPosition = nearestVertexPosition,
		nearestVertexDistance = nearestVertexPosition
			and math.sqrt( nearestVertexDistanceSquared ) or nil,
		worldBoundsMinimum = boundsMinimum,
		worldBoundsMaximum = boundsMaximum,
		meshNearest = scan.meshNearest,
	}
	if scan.validTriangleCount == 0 then
		result.error = "no posed visual triangles could be evaluated"
		result.queryMilliseconds = ( SysTime() - started ) * 1000
		return result
	end

	-- The captured trace surface is authoritative. Nearest visual geometry is
	-- diagnostic only; silently recentering here would make the rendered hull
	-- disagree with the volume used at the moment of impact.
	result.surfacePosition = surfacePosition
	result.surfaceNormal = surfaceNormal
	result.hitDirection = hitDirection
	result.inwardDirection = inwardDirection
	result.insideDistance = insideDistance
	result.outsideDistance = outsideDistance
	result.nearestVisualSurfacePosition = nearestSurfacePosition
	result.nearestVisualSurfaceNormal = nearestSurfaceNormal
	result.meshes = scan.meshes
	result.vertexCount = scan.vertexCount
	result.insideVertexCount = scan.insideVertexCount
	result.triangleCount = scan.triangleCount
	result.scannedVertexCount = control.scannedVertexCount
	result.skippedVertexCount = control.skippedVertexCount
	result.uniqueSkinnedVertexCount = control.uniqueSkinnedVertexCount
	result.reusedSkinnedVertexCount = control.reusedSkinnedVertexCount
	result.localBoundsEnabled = useLocalBounds
	result.broadPhaseRejectedCount = control.intervalRejectedCount
	result.intervalRejectedCount = control.intervalRejectedCount
	result.axialIntervalRejectedCount = control.axialIntervalRejectedCount
	result.radialIntervalRejectedCount = control.radialIntervalRejectedCount
	result.exactTestCount = control.exactTestCount
	result.diagnosticClosestPointCount = control.diagnosticClosestPointCount
	result.layerLimit = math.max( math.floor( tonumber( control.layerLimit ) or 0 ), 0 )
	result.layerOccludersIncluded = control.allowedMeshes == nil

	result.ok = true
	result.meshCount = #result.meshes
	result.cacheKey = meshData.key
	result.queryMilliseconds = ( SysTime() - started ) * 1000
	return result
end

function BBS.ClearModelMeshCache()
	if BBS.CancelPersistentMeshWork then
		BBS.CancelPersistentMeshWork( true )
	end
	BBS.ModelMeshCache = {}
	BBS.ModelMeshCacheStats = {
		hits = 0, misses = 0, builds = 0, failures = 0, evictions = 0,
	}
	BBS.ModelMeshCacheAccessSerial = 0
	BBS.ModelMeshNegativeAccess = {}
	BBS.ModelMeshNegativeSerial = 0
	BBS.MeshCacheEvictionGCSteps = 0
	BBS.HideableMeshCache = {}
	BBS.MeshPrewarmQueue = {}
	BBS.MeshPrewarmQueued = setmetatable( {}, { __mode = "k" } )
	BBS.MeshPrewarmByKey = {}
	for _, deferred in ipairs( BBS.DeferredHitMeshQueue ) do
		if deferred.hit then
			deferred.hit.meshQuery = {
				ok = false, pending = false, error = "mesh cache was cleared",
			}
			if BBS.PerfFinish then
				BBS.PerfFinish( deferred.hit, "mesh_cache_cleared" )
			end
		end
	end
	for _, query in ipairs( BBS.MeshQueryQueue ) do
		if query.hit then
			query.hit.meshQuery = {
				ok = false, pending = false, error = "mesh cache was cleared",
			}
			if BBS.PerfFinish then
				BBS.PerfFinish( query.hit, "mesh_cache_cleared" )
			end
		end
	end
	BBS.DeferredHitMeshQueue = {}
	BBS.MeshQueryQueue = {}
	BBS.PendingHitBursts = setmetatable( {}, { __mode = "k" } )
	BBS.HitDispatchQueue = {}
end

local FinishMeshPrewarmJob

local function InsertMeshPrewarmJob( job )
	if not job then return end
	if job.pinnedContinuation then
		table.insert( BBS.MeshPrewarmQueue, 1, job )
		return
	end
	if not job.urgent then
		BBS.MeshPrewarmQueue[ #BBS.MeshPrewarmQueue + 1 ] = job
		return
	end
	-- FIFO within the urgent class, ahead of speculative work. Requeued jobs go
	-- behind other urgent identities, so one large cold model cannot monopolize
	-- every frame and newly hit models cannot LIFO-starve earlier consumers.
	local insertIndex = #BBS.MeshPrewarmQueue + 1
	for index, queued in ipairs( BBS.MeshPrewarmQueue ) do
		if not queued.pinnedContinuation and not queued.urgent then
			insertIndex = index
			break
		end
	end
	table.insert( BBS.MeshPrewarmQueue, insertIndex, job )
end

local function PreemptSpeculativeMeshContinuation( urgentKey )
	for index, queued in ipairs( BBS.MeshPrewarmQueue ) do
		if queued.key ~= urgentKey and queued.pinnedContinuation
		and queued.phase ~= "rtx_cleanup" and not queued.urgent then
			table.remove( BBS.MeshPrewarmQueue, index )
			if queued.diskState then
				-- Cancellation is a scheduling choice, not cache corruption. Detach the
				-- partial hydrate without deleting its valid committed metadata.
				if BBS.CancelPersistentMeshLoad then BBS.CancelPersistentMeshLoad( queued.diskState ) end
				queued.diskState.cancelled = true
				if BBS.PersistentMeshLoads then
					BBS.PersistentMeshLoads[ queued.key ] = nil
				end
			end
			queued.diskState = nil
			queued.meshThread = nil
			queued.pinnedContinuation = false
			FinishMeshPrewarmJob( queued )
			BBS.MeshCacheEvictionGCSteps = math.max(
				BBS.MeshCacheEvictionGCSteps or 0, 64 )
			return true
		end
	end
	return false
end

local function QueueMeshPrewarm( entity, urgent )
	if not GetBool( "bbs_enabled" ) then return false end
	if not IsValid( entity ) then return false end
	local isRagdoll = entity:GetClass() == "prop_ragdoll"
	local livingTarget = BBS.IsLivingDamageTarget( entity )
	-- The living toggle controls speculative preparation only. A real hit is
	-- urgent and must always be allowed to create its own producer; its captured
	-- snapshot waits for readiness without a hardware-speed timeout.
	local isLivingSource = livingTarget
		and ( urgent or GetBool( "bbs_mesh_prewarm_living" ) )
	if not isRagdoll and not isLivingSource then return false end
	local deathOnly = GetConVar( "bbs_death_ragdolls_only" )
	if isRagdoll and deathOnly and deathOnly:GetBool()
	and not entity:GetNW2Bool( "BBS.DeathRagdoll", false ) then return false end
	if not entity:GetModel() or entity:GetModel() == "" then return false end
	if BBS.IsModelDamageAllowed then
		local allowed = BBS.IsModelDamageAllowed( entity:GetModel() )
		if not allowed then return false end
	end
	local key, model, bodygroups, skin =
		BBS.GetModelMeshCacheIdentity( entity, 0 )
	if not key then return false end
	local memory = BBS.ModelMeshCache[ key ]
	-- `false` is the negative-cache sentinel for an engine extraction failure.
	-- It can never produce eligibility, so do not create an immortal prewarm job.
	if memory == false then return false end
	local memoryReady = memory ~= nil
		and not ( memory and memory ~= false and memory.rtxCleanupPending )
	local eligibilityReady = BBS.HideableMeshCache
		and BBS.HideableMeshCache[ key ] ~= nil
	if memoryReady and eligibilityReady then
		-- A bounded persistence queue may have superseded this model earlier.
		-- Entity spawn becomes a cheap retry point; committed geometry returns
		-- immediately after only its metadata check.
		if BBS.QueuePersistentMeshWrite then
			BBS.QueuePersistentMeshWrite(
				memory, BBS.HideableMeshCache[ key ] )
		end
		return false
	end
	local existing = BBS.MeshPrewarmByKey[ key ]
	if existing then
		-- A death ragdoll can replace the living NPC which originally queued this
		-- model. Keep the cache-key job and simply refresh its representative.
		if existing.entity ~= entity then
			if IsValid( existing.entity ) then
				BBS.MeshPrewarmQueued[ existing.entity ] = nil
			end
			existing.entity = entity
			BBS.MeshPrewarmQueued[ entity ] = true
		end
		if urgent and not existing.urgent then
			existing.urgent = true
			existing.urgentStartedAt = SysTime()
			existing.preparationStartedAt = existing.preparationStartedAt
				or existing.urgentStartedAt or SysTime()
			for index, queued in ipairs( BBS.MeshPrewarmQueue ) do
				if queued == existing then
					table.remove( BBS.MeshPrewarmQueue, index )
					InsertMeshPrewarmJob( existing )
					break
				end
			end
		elseif urgent then
			existing.preparationStartedAt = existing.preparationStartedAt
				or SysTime()
			existing.urgentStartedAt = existing.urgentStartedAt
				or existing.preparationStartedAt
		end
		-- A producer identity must either be executing or be present in the queue.
		-- Recover stale map-only jobs left by a reload or an interrupted phase; the
		-- old behavior returned true here and let deferred hits wait forever.
		local queued = false
		for _, candidate in ipairs( BBS.MeshPrewarmQueue ) do
			if candidate == existing then queued = true break end
		end
		if not queued and not existing.processing then
			InsertMeshPrewarmJob( existing )
		end
		return true
	end
	-- An ordinary spawn with no damageable bodygroup needs no full model graph.
	-- Do not negative-cache this decision: later overrides/filters may enable it,
	-- and real impacts must always retain the complete producer/debug path.
	if not urgent and BBS.HasDamageableBodygroupsForPrewarm
	and BBS.HasDamageableBodygroupsForPrewarm( entity, bodygroups ) == false then
		return false
	end
	if urgent then PreemptSpeculativeMeshContinuation( key ) end
	BBS.MeshPrewarmQueued[ entity ] = true
	local queuedAt = SysTime()
	local job = {
		entity = entity,
		key = key,
		model = model,
		bodygroups = bodygroups,
		skin = skin,
		lod = 0,
		urgent = urgent and true or false,
		speculative = not urgent,
		preparationStartedAt = queuedAt,
		urgentStartedAt = urgent and queuedAt or nil,
		phase = "resolve",
	}
	BBS.MeshPrewarmByKey[ key ] = job
	InsertMeshPrewarmJob( job )
	return true
end

FinishMeshPrewarmJob = function( job )
	if not job then return end
	-- Preserve producer measurements on every impact waiting for this identity.
	-- The producer is removed before deferred hits resume, so copy the evidence.
	for _, deferred in ipairs( BBS.DeferredHitMeshQueue or {} ) do
		if deferred.cacheKey == job.key then
			deferred.preparation = {
				phase = job.phase,
				budgetMilliseconds = job.preparationBudgetMilliseconds or 0,
				configuredBudgetMilliseconds =
					job.configuredPreparationBudgetMilliseconds or 0,
				diskHydrationMilliseconds = job.diskHydrationMilliseconds or 0,
				diskHydrationFrames = job.diskHydrationFrames or 0,
				diskChunksRead = job.diskChunksRead or 0,
				meshBuildMilliseconds = job.meshCPUMilliseconds or 0,
				meshMaximumSliceMilliseconds =
					job.meshMaximumSliceMilliseconds or 0,
				nativeExtractionMilliseconds =
					job.nativeExtractionMilliseconds or 0,
				eligibilityMilliseconds =
					job.eligibilityCPUMilliseconds or 0,
				eligibilityMaximumSliceMilliseconds =
					job.eligibilityMaximumSliceMilliseconds or 0,
				preparationWallMilliseconds = job.preparationStartedAt
					and ( SysTime() - job.preparationStartedAt ) * 1000 or 0,
				targetSeconds = job.preparationTargetSeconds or 0,
				maximumBudgetMilliseconds =
					job.maximumPreparationBudgetMilliseconds or 0,
				catchupCeilingMilliseconds =
					job.preparationCatchupCeilingMilliseconds or 0,
				meshReturnRecovered = job.meshReturnRecovered and true or false,
			}
		end
	end
	if job.key and BBS.MeshPrewarmByKey[ job.key ] == job then
		BBS.MeshPrewarmByKey[ job.key ] = nil
	end
	if IsValid( job.entity ) then BBS.MeshPrewarmQueued[ job.entity ] = nil end
	if BBS.TrimModelMeshCache then BBS.TrimModelMeshCache() end
end

local function FailDeferredHitsForCacheKey( key, reason, status )
	for index = #BBS.DeferredHitMeshQueue, 1, -1 do
		local deferred = BBS.DeferredHitMeshQueue[ index ]
		if deferred.cacheKey == key then
			table.remove( BBS.DeferredHitMeshQueue, index )
			local hit = deferred.hit
			if hit then
				hit.meshQuery = { ok = false, pending = false,
					cacheKey = key, error = reason }
				if BBS.PerfFinish then
					BBS.PerfFinish( hit, status or "mesh_cache_unavailable" )
				end
			end
		end
	end
end

local function RequeueMeshPrewarmJob( job )
	if not job then return end
	-- A suspended native packer or persistent hydrate retains a large partial
	-- model graph. Finish that producer before starting another identity; this
	-- keeps peak memory bounded to one cold model while ready queries still get
	-- alternating frames through the shared scheduler.
	job.pinnedContinuation = job.meshThread ~= nil or job.diskState ~= nil
		or job.phase == "rtx_cleanup"
	InsertMeshPrewarmJob( job )
end

function BBS.ReleaseOrphanUrgentMeshPrewarm( key )
	if not key then return end
	for _, deferred in ipairs( BBS.DeferredHitMeshQueue or {} ) do
		if deferred.cacheKey == key then return end
	end
	local job = BBS.MeshPrewarmByKey and BBS.MeshPrewarmByKey[ key ] or nil
	if not job or not job.urgent then return end
	if not job.speculative then
		for index, queued in ipairs( BBS.MeshPrewarmQueue or {} ) do
			if queued == job then
				table.remove( BBS.MeshPrewarmQueue, index )
				break
			end
		end
		if job.diskState then
			if BBS.CancelPersistentMeshLoad then BBS.CancelPersistentMeshLoad( job.diskState ) end
			job.diskState.cancelled = true
			if BBS.PersistentMeshLoads then
				BBS.PersistentMeshLoads[ key ] = nil
			end
		end
		FinishMeshPrewarmJob( job )
		return
	end
	job.urgent = false
	job.urgentStartedAt = nil
	for index, queued in ipairs( BBS.MeshPrewarmQueue or {} ) do
		if queued == job then
			table.remove( BBS.MeshPrewarmQueue, index )
			InsertMeshPrewarmJob( job )
			break
		end
	end
end

function BBS.CancelBackgroundMeshWork( reason )
	reason = reason or "background mesh preparation was cancelled"
	for _, job in ipairs( BBS.MeshPrewarmQueue or {} ) do
		if IsValid( job.entity ) then
			BBS.MeshPrewarmQueued[ job.entity ] = nil
		end
	end
	BBS.MeshPrewarmQueue = {}
	BBS.MeshPrewarmByKey = {}
	BBS.MeshPrewarmQueued = setmetatable( {}, { __mode = "k" } )
	if BBS.CancelPersistentMeshWork then
		BBS.CancelPersistentMeshWork( true )
	else
		BBS.PersistentMeshLoads = {}
	end
	for _, deferred in ipairs( BBS.DeferredHitMeshQueue or {} ) do
		local hit = deferred.hit
		if hit then
			hit.meshQuery = { ok = false, pending = false,
				cacheKey = deferred.cacheKey, error = reason }
			if BBS.PerfFinish then
				BBS.PerfFinish( hit, "mesh_prewarm_cancelled" )
			end
		end
	end
	BBS.DeferredHitMeshQueue = {}
	BBS.MeshCacheEvictionGCSteps = math.max(
		BBS.MeshCacheEvictionGCSteps or 0, 32 )
	if BBS.TrimModelMeshCache then BBS.TrimModelMeshCache() end
end

local function CancelSpeculativeMeshWork()
	-- `bbs_mesh_prewarm` controls spawn-time speculation, not the correctness path
	-- for a real impact. Turning it off must not strand/cancel an already captured
	-- cold hit, so retain urgent producers and discard only unused speculative jobs.
	for index = #BBS.MeshPrewarmQueue, 1, -1 do
		local job = BBS.MeshPrewarmQueue[ index ]
		if job and not job.urgent and job.phase ~= "rtx_cleanup" then
			table.remove( BBS.MeshPrewarmQueue, index )
			if job.diskState then
				if BBS.CancelPersistentMeshLoad then BBS.CancelPersistentMeshLoad( job.diskState ) end
				job.diskState.cancelled = true
				if BBS.PersistentMeshLoads then
					BBS.PersistentMeshLoads[ job.key ] = nil
				end
			end
			FinishMeshPrewarmJob( job )
		end
	end
end

cvars.AddChangeCallback( "bbs_mesh_prewarm", function( _, _, newValue )
	if tonumber( newValue ) ~= 0 then return end
	CancelSpeculativeMeshWork()
end, "BBS.CancelDisabledMeshPrewarm" )

hook.Add( "OnEntityCreated", "BBS.QueueModelMeshPrewarm", function( entity )
	if not IsValid( entity ) then return end
	local living = BBS.IsLivingDamageTarget( entity )
	if not living and entity:GetClass() ~= "prop_ragdoll" then return end
	-- Match the last smooth cold-start release: begin living-model preparation on
	-- the next tick, before an immediate first shot can create an avoidable wait.
	-- Ragdolls retain a short settling delay so their final model/bodygroups exist.
	local delay = living and 0 or 0.25
	timer.Simple( delay, function()
		if GetBool( "bbs_enabled" ) and GetBool( "bbs_mesh_prewarm" ) then
			QueueMeshPrewarm( entity )
		end
	end )
end )

hook.Add( "BBS.DamageFiltersChanged", "BBS.RequeueFilteredMeshPrewarm", function()
	if not GetBool( "bbs_enabled" ) or not GetBool( "bbs_mesh_prewarm" ) then return end
	timer.Simple( 0, function()
		for _, entity in ipairs( ents.GetAll() ) do
			if entity:GetClass() == "prop_ragdoll"
			or entity:IsNPC() or entity:IsPlayer() then QueueMeshPrewarm( entity ) end
		end
	end )
end )

timer.Simple( 1, function()
	if not GetBool( "bbs_enabled" ) or not GetBool( "bbs_mesh_prewarm" ) then return end
	for _, entity in ipairs( ents.GetAll() ) do
		if entity:GetClass() == "prop_ragdoll"
		or entity:IsNPC() or entity:IsPlayer() then QueueMeshPrewarm( entity ) end
	end
end )

local nextPrewarmTime = 0
hook.Add( "Think", "BBS.ProcessRagdollMeshPrewarm", function()
	local nextJob = BBS.MeshPrewarmQueue[ 1 ]
	local cleanupPending = nextJob and nextJob.phase == "rtx_cleanup"
	if not GetBool( "bbs_enabled" )
	or ( not GetBool( "bbs_mesh_prewarm" )
		and not ( nextJob and nextJob.urgent ) and not cleanupPending )
	or ( #( BBS.DamagePaintQueue or {} ) > 0
		and not ( nextJob and nextJob.urgent ) and not cleanupPending )
	or ( not cleanupPending and #BBS.MeshQueryQueue > 0
		and ( not ( nextJob and nextJob.urgent )
			or FrameNumber() % 2 == 0 ) ) then return end
	local persistentWriteWatermark = math.Clamp(
		GetInt( "bbs_mesh_cache_write_limit", 3 ), 1, 8 )
	if nextJob and not nextJob.urgent and not cleanupPending
	and not ( BBS.MeshPreparationHasPriority and BBS.MeshPreparationHasPriority( nextJob ) )
	and #( BBS.PersistentMeshWriteQueue or {} ) >= persistentWriteWatermark then
		-- Limit older, unstarted speculation when the disk is behind. Fresh spawn
		-- work, actual hits and pinned partial graphs bypass this gate: serialization
		-- must not lengthen their first-ready path. The write queue is independently
		-- bounded and can supersede an older waiting snapshot.
		return
	end
	-- Older unstarted speculation and recording share alternate frames. Fresh
	-- spawn jobs and pinned continuations get full preparation cadence until ready.
	if #( BBS.PersistentMeshWriteQueue or {} ) > 0
	and not ( nextJob and nextJob.urgent ) and not cleanupPending
	and not ( BBS.MeshPreparationHasPriority and BBS.MeshPreparationHasPriority( nextJob ) )
	and FrameNumber() % 2 == 0 then return end
	if SysTime() < nextPrewarmTime then return end
	local job = table.remove( BBS.MeshPrewarmQueue, 1 )
	if not job then return end
	local entity = job.entity
	if not IsValid( entity ) and job.phase ~= "disk"
	and job.phase ~= "rtx_cleanup"
	and not ( job.phase == "mesh" and job.meshThread ) then
		FinishMeshPrewarmJob( job )
		return
	end
	nextPrewarmTime = SysTime() + 0.001
	local started = SysTime()
	if not BBS.TryBeginHeavyFrame( "mesh-prewarm" ) then
		RequeueMeshPrewarmJob( job )
		return
	end
	job.processing = true
	local phaseOK, phaseError = pcall( function()
	if job.phase == "resolve" then
		local key = job.key or BBS.GetModelMeshCacheIdentity( entity, 0 )
		local memory = key and BBS.ModelMeshCache[ key ] or nil
		if memory and memory ~= false then
			job.phase = "eligibility"
			job.meshData = memory
		elseif GetBool( "bbs_mesh_disk_cache" )
		and BBS.BeginPersistentMeshLoadForIdentity then
			job.diskState = BBS.BeginPersistentMeshLoadForIdentity(
				job.key, job.model, job.bodygroups, job.skin, job.lod )
			job.phase = job.diskState and "disk" or "mesh"
		else
			job.phase = "mesh"
		end
		RequeueMeshPrewarmJob( job )
	elseif job.phase == "disk" then
		if not GetBool( "bbs_mesh_disk_cache" ) then
			if job.diskState then
				if BBS.CancelPersistentMeshLoad then BBS.CancelPersistentMeshLoad( job.diskState ) end
				job.diskState.cancelled = true
			end
			BBS.PersistentMeshLoads[ job.key ] = nil
			job.diskState = nil
			job.phase = "mesh"
			RequeueMeshPrewarmJob( job )
			return
		end
		local complete, meshData
		local budgetMilliseconds, configuredBudgetMilliseconds,
			remainingSeconds, remainingChunks, targetSeconds, catchupCeiling =
			MeshPreparationBudget( job, "bbs_mesh_cache_io_budget_ms", 10, 0.1 )
		job.preparationBudgetMilliseconds = budgetMilliseconds
		job.configuredPreparationBudgetMilliseconds = configuredBudgetMilliseconds
		job.preparationRemainingSeconds = remainingSeconds
		job.preparationRemainingChunks = remainingChunks
		job.preparationTargetSeconds = targetSeconds
		job.preparationCatchupCeilingMilliseconds = catchupCeiling
		job.maximumPreparationBudgetMilliseconds = math.max(
			job.maximumPreparationBudgetMilliseconds or 0, budgetMilliseconds )
		local chunksBefore = BBS.PersistentMeshStats
			and BBS.PersistentMeshStats.chunksRead or 0
		local deadline = SysTime() + budgetMilliseconds / 1000
		repeat
			complete, meshData = BBS.ContinuePersistentMeshLoad( job.diskState )
		until complete or SysTime() >= deadline
		local elapsed = ( SysTime() - started ) * 1000
		job.diskHydrationMilliseconds =
			( job.diskHydrationMilliseconds or 0 ) + elapsed
		job.diskMaximumSliceMilliseconds = math.max(
			job.diskMaximumSliceMilliseconds or 0, elapsed )
		job.diskHydrationFrames = ( job.diskHydrationFrames or 0 ) + 1
		local chunksAfter = BBS.PersistentMeshStats
			and BBS.PersistentMeshStats.chunksRead or chunksBefore
		job.diskChunksRead = ( job.diskChunksRead or 0 )
			+ math.max( chunksAfter - chunksBefore, 0 )
		if BBS.PerfAddBackground then
			BBS.PerfAddBackground( "Prewarm: persistent cache hydrate", elapsed )
		end
		if not complete then
			RequeueMeshPrewarmJob( job )
		else
			job.diskState = nil
		end
		if complete and meshData then
			job.meshData = meshData
			if IsValid( entity ) then
				job.phase = "eligibility"
				RequeueMeshPrewarmJob( job )
			else
				FinishMeshPrewarmJob( job )
			end
		elseif complete and IsValid( entity ) then
			job.phase = "mesh"
			RequeueMeshPrewarmJob( job )
		elseif complete then
			FinishMeshPrewarmJob( job )
		end
	elseif job.phase == "mesh" then
		if not job.meshThread then
			job.meshThread = coroutine.create( function()
				return BBS.GetCachedModelMeshesForIdentity(
					job.key, job.model, job.bodygroups, job.skin, job.lod )
			end )
			job.meshCPUMilliseconds = 0
			job.meshMaximumSliceMilliseconds = 0
		end
		local budgetMilliseconds, configuredBudgetMilliseconds,
			remainingSeconds, _, targetSeconds, catchupCeiling =
			MeshPreparationBudget( job, "bbs_mesh_build_budget_ms", 15, 0.25 )
		job.preparationBudgetMilliseconds = budgetMilliseconds
		job.configuredPreparationBudgetMilliseconds = configuredBudgetMilliseconds
		job.preparationRemainingSeconds = remainingSeconds
		job.preparationTargetSeconds = targetSeconds
		job.preparationCatchupCeilingMilliseconds = catchupCeiling
		job.maximumPreparationBudgetMilliseconds = math.max(
			job.maximumPreparationBudgetMilliseconds or 0, budgetMilliseconds )
		job.deadline = SysTime() + budgetMilliseconds / 1000
		activeMeshBuildJob = job
		local resumeStarted = SysTime()
		local ok, meshData, _, meshError = coroutine.resume( job.meshThread )
		activeMeshBuildJob = nil
		local elapsed = ( SysTime() - resumeStarted ) * 1000
		job.meshCPUMilliseconds = job.meshCPUMilliseconds + elapsed
		job.meshMaximumSliceMilliseconds = math.max(
			job.meshMaximumSliceMilliseconds, elapsed )
		if BBS.PerfAddBackground then
			BBS.PerfAddBackground( "Prewarm: mesh cache", elapsed )
		end
		if not ok then
			BBS.Log( "background mesh cache coroutine failed for %s: %s",
				tostring( job.key or entity:GetModel() ), tostring( meshData ) )
			FinishMeshPrewarmJob( job )
			FailDeferredHitsForCacheKey( job.key,
				"background mesh cache coroutine failed: " .. tostring( meshData ),
				"mesh_prewarm_failed" )
		elseif coroutine.status( job.meshThread ) ~= "dead" then
			RequeueMeshPrewarmJob( job )
		else
			-- The immutable cache publication is the authoritative completion
			-- barrier. RTX/autorefresh builds have been observed to publish the full
			-- table and log success while the coroutine handoff value is nil. Never
			-- discard that successfully built graph because of a return-value anomaly.
			local publishedMeshData = meshData
			if not publishedMeshData then
				local published = BBS.ModelMeshCache[ job.key ]
				if published and published ~= false then
					publishedMeshData = published
					job.meshReturnRecovered = true
					if GetBool( "bbs_debug_console" ) then
						BBS.Log( "background mesh handoff recovered from published cache: key=%s coroutineValue=%s eligibilityFunction=%s",
							tostring( job.key ), tostring( meshData ),
							tostring( isfunction( BBS.GetHideableMeshAnalysis ) ) )
					end
				end
			end
			if publishedMeshData then
				BBS.MeshPrewarmStats.meshMilliseconds =
					BBS.MeshPrewarmStats.meshMilliseconds + job.meshCPUMilliseconds
				job.meshThread = nil
				job.phase = "eligibility"
				job.meshData = publishedMeshData
				RequeueMeshPrewarmJob( job )
			else
				if meshError and GetBool( "bbs_debug_console" ) then
					BBS.Log( "background mesh cache unavailable: %s",
						tostring( meshError ) )
				end
				FinishMeshPrewarmJob( job )
				FailDeferredHitsForCacheKey( job.key,
					meshError or "background model mesh extraction was unavailable",
					"mesh_cache_unavailable" )
			end
		end
	elseif job.phase == "rtx_cleanup" then
		-- Any native ModelMeshData used by packing or differential bodygroup analysis
		-- became unreachable during the preceding phases. On Remix, do not let a
		-- deferred query, material paint, or persistent writer add another allocation
		-- wave until two GC-cycle boundaries have passed. The second boundary
		-- guarantees at least one complete cycle began after those references died.
		-- This phase is never entered by vanilla Garry's Mod.
		local currentKey = IsValid( entity )
			and BBS.GetModelMeshCacheIdentity( entity, job.lod or 0 ) or nil
		if IsValid( entity ) and currentKey ~= job.key then
			-- Do not start another native extraction yet. Remember the replacement,
			-- finish releasing the old graph, and only then hand off identities.
			job.rtxCleanupIdentityChanged = true
			job.rtxCleanupReplacementEntity = entity
		end
		job.rtxCleanupFrames = ( job.rtxCleanupFrames or 0 ) + 1
		local cleanupStarted = SysTime()
		local cleanupBudget = MeshPreparationBudget(
			job, "bbs_mesh_build_budget_ms", 15, 0.25 )
		BBS.StepMeshNativeCleanup( job, cleanupStarted + cleanupBudget / 1000 )
		local cleanupElapsed = ( SysTime() - cleanupStarted ) * 1000
		job.rtxCleanupMilliseconds =
			( job.rtxCleanupMilliseconds or 0 ) + cleanupElapsed
		job.rtxCleanupMaximumSliceMilliseconds = math.max(
			job.rtxCleanupMaximumSliceMilliseconds or 0, cleanupElapsed )
		if BBS.PerfAddBackground then
			BBS.PerfAddBackground( "Prewarm: RTX memory cleanup", cleanupElapsed )
		end
		if ( job.rtxCleanupGCCycles or 0 ) < 2
		or job.rtxCleanupFrames < 4
		or SysTime() < ( job.rtxCleanupUntil or 0 ) then
			RequeueMeshPrewarmJob( job )
			return
		end
		job.meshData.rtxCleanupCompleteAt = SysTime()
		job.meshData.rtxCleanupPending = nil
		job.meshData.rtxNativeGraphPending = false
		if job.rtxCleanupIdentityChanged then
			FinishMeshPrewarmJob( job )
			FailDeferredHitsForCacheKey( job.key,
				"target model/bodygroup/skin changed during RTX memory cleanup",
				"mesh_identity_changed" )
			local replacement = job.rtxCleanupReplacementEntity
			if IsValid( replacement ) then
				QueueMeshPrewarm( replacement, job.urgent )
			end
			return
		end
		if ( job.rtxCleanupFilterRevision or 0 )
		~= ( BBS.DamageFilterRevision or 0 ) then
			-- The old ownership result must never be stamped with the new filter
			-- signature. The native graph is safe now; rerun only eligibility.
			BBS.HideableMeshCache[ job.key ] = nil
			job.eligibility = nil
			job.eligibilityFilterRevision = nil
			job.rtxCleanupFilterRevision = nil
			job.meshData.rtxCleanupPending = true
			job.meshData.rtxCleanupCompleteAt = nil
			job.phase = "eligibility"
			RequeueMeshPrewarmJob( job )
			return
		end
		BBS.HideableMeshCache[ job.key ] = job.eligibility
		if BBS.RecordMeshPreparationReady then BBS.RecordMeshPreparationReady( job ) end
		BBS.MeshPrewarmStats.completed = BBS.MeshPrewarmStats.completed + 1
		BBS.MeshPrewarmStats.rtxCleanupMilliseconds =
			( BBS.MeshPrewarmStats.rtxCleanupMilliseconds or 0 )
			+ ( job.rtxCleanupMilliseconds or 0 )
		BBS.MeshPrewarmStats.rtxCleanupFrames =
			( BBS.MeshPrewarmStats.rtxCleanupFrames or 0 )
			+ job.rtxCleanupFrames
		if BBS.QueuePersistentMeshWrite then
			BBS.QueuePersistentMeshWrite( job.meshData, job.eligibility )
		end
		FinishMeshPrewarmJob( job )
	else
		local currentKey = IsValid( entity )
			and BBS.GetModelMeshCacheIdentity( entity, job.lod or 0 ) or nil
		if currentKey ~= job.key then
			FinishMeshPrewarmJob( job )
			FailDeferredHitsForCacheKey( job.key,
				"target model/bodygroup/skin changed while its mesh cache was prepared",
				"mesh_identity_changed" )
			if IsValid( entity ) then QueueMeshPrewarm( entity, job.urgent ) end
			return
		end
		if BBS.IsActiveRTXRuntime and BBS.IsActiveRTXRuntime() then
			job.meshData.rtxCleanupPending = true
			job.meshData.rtxCleanupCompleteAt = nil
		end
		if not isfunction( BBS.GetHideableMeshAnalysis ) then
			job.eligibilityFunctionWaitStarted =
				job.eligibilityFunctionWaitStarted or SysTime()
			if not job.eligibilityFunctionWaitLogged
			and GetBool( "bbs_debug_console" ) then
				job.eligibilityFunctionWaitLogged = true
				BBS.Log( "background mesh ready; waiting for bodygroup eligibility module: key=%s",
					tostring( job.key ) )
			end
			-- File loading and auto-refresh can be exceptionally slow on mechanical
			-- disks or heavily instrumented RTX clients. Missing elapsed-time targets
			-- are not data errors: keep the producer alive until the module appears or
			-- the user explicitly disables/cancels the addon.
			RequeueMeshPrewarmJob( job )
			return
		end
		if not job.eligibilityThread then
			job.eligibilityFilterRevision = BBS.DamageFilterRevision or 0
			job.eligibilityThread = coroutine.create( function()
				return BBS.GetHideableMeshAnalysis(
					job.entity, job.meshData, function()
						if SysTime() >= ( job.deadline or math.huge ) then
							coroutine.yield( "mesh_eligibility" )
						end
					end )
			end )
			job.eligibilityCPUMilliseconds = 0
			job.eligibilityMaximumSliceMilliseconds = 0
		end
		local budgetMilliseconds, configuredBudgetMilliseconds,
			remainingSeconds, _, targetSeconds, catchupCeiling =
			MeshPreparationBudget( job, "bbs_mesh_build_budget_ms", 15, 0.25 )
		job.preparationBudgetMilliseconds = budgetMilliseconds
		job.configuredPreparationBudgetMilliseconds = configuredBudgetMilliseconds
		job.preparationRemainingSeconds = remainingSeconds
		job.preparationTargetSeconds = targetSeconds
		job.preparationCatchupCeilingMilliseconds = catchupCeiling
		job.maximumPreparationBudgetMilliseconds = math.max(
			job.maximumPreparationBudgetMilliseconds or 0, budgetMilliseconds )
		job.deadline = SysTime() + budgetMilliseconds / 1000
		local resumeStarted = SysTime()
		local ok, eligibility, eligibilityError =
			coroutine.resume( job.eligibilityThread )
		local elapsed = ( SysTime() - resumeStarted ) * 1000
		job.eligibilityCPUMilliseconds =
			( job.eligibilityCPUMilliseconds or 0 ) + elapsed
		job.eligibilityMaximumSliceMilliseconds = math.max(
			job.eligibilityMaximumSliceMilliseconds or 0, elapsed )
		BBS.MeshPrewarmStats.eligibilityMilliseconds =
			BBS.MeshPrewarmStats.eligibilityMilliseconds
			+ elapsed
		if BBS.PerfAddBackground then
			BBS.PerfAddBackground( "Prewarm: bodygroup eligibility", elapsed )
		end
		if not ok then
			FinishMeshPrewarmJob( job )
			FailDeferredHitsForCacheKey( job.key,
				"bodygroup eligibility coroutine failed: "
					.. tostring( eligibility ),
				"mesh_eligibility_unavailable" )
			return
		end
		if coroutine.status( job.eligibilityThread ) ~= "dead" then
			RequeueMeshPrewarmJob( job )
			return
		end
		job.eligibilityThread = nil
		if not eligibility then
			FinishMeshPrewarmJob( job )
			FailDeferredHitsForCacheKey( job.key,
				"bodygroup eligibility was not published: "
					.. tostring( eligibilityError or "unknown error" ),
				"mesh_eligibility_unavailable" )
			return
		end
		-- Publish under the producer identity before removing the producer. This is
		-- the readiness barrier consumed by deferred hits on their next Think.
		if BBS.MeshPreparationNeedsNativeCleanup
		and BBS.MeshPreparationNeedsNativeCleanup( job ) then
			-- GetHideableMeshAnalysis publishes internally. Withdraw that readiness
			-- record until the RTX-only cleanup barrier completes, otherwise the
			-- deferred-hit hook later in this same Think could start a query first.
			BBS.HideableMeshCache[ job.key ] = nil
			job.meshData.rtxCleanupPending = true
			job.meshData.rtxCleanupCompleteAt = nil
			job.eligibility = eligibility
			job.eligibilityThread = nil
			job.phase = "rtx_cleanup"
			job.rtxCleanupFrames = 0
			job.rtxCleanupMilliseconds = 0
			job.rtxCleanupGCCycles = 0
			job.rtxCleanupFilterRevision =
				job.eligibilityFilterRevision or BBS.DamageFilterRevision or 0
			job.rtxCleanupGCProbe =
				setmetatable( { {} }, { __mode = "v" } )
			job.rtxCleanupUntil = SysTime() + 0.25
			RequeueMeshPrewarmJob( job )
		else
			-- Hydration + compiled/restored ownership create no native mesh graph.
			-- Do not wait for two whole GC cycles on this restart fast path.
			job.meshData.rtxCleanupPending = nil
			job.meshData.rtxNativeGraphPending = false
			BBS.HideableMeshCache[ job.key ] = eligibility
			if BBS.RecordMeshPreparationReady then BBS.RecordMeshPreparationReady( job ) end
			BBS.MeshPrewarmStats.completed = BBS.MeshPrewarmStats.completed + 1
			if BBS.QueuePersistentMeshWrite then
				BBS.QueuePersistentMeshWrite( job.meshData, eligibility )
			end
			FinishMeshPrewarmJob( job )
		end
	end
	end )
	job.processing = false
	if not phaseOK then
		activeMeshBuildJob = nil
		if job.diskState and not job.diskState.done
		and BBS.AbortPersistentMeshLoad then
			BBS.AbortPersistentMeshLoad( job.diskState,
				"persistent mesh hydration raised: " .. tostring( phaseError ) )
		end
		FinishMeshPrewarmJob( job )
		FailDeferredHitsForCacheKey( job.key,
			"background mesh preparation failed: " .. tostring( phaseError ),
			"mesh_prewarm_failed" )
		BBS.Log( "background mesh preparation failed for %s: %s",
			tostring( job.key ), tostring( phaseError ) )
	end
end )

function BBS.GetModelMeshCacheSummary()
	local entryCount = 0
	local failedEntryCount = 0
	local vertexCount = 0
	local triangleCount = 0
	for _, data in pairs( BBS.ModelMeshCache ) do
		entryCount = entryCount + 1
		if data == false then
			failedEntryCount = failedEntryCount + 1
		else
			vertexCount = vertexCount + ( data.totalVertexCount or 0 )
			triangleCount = triangleCount + ( data.totalTriangleCount or 0 )
		end
	end
	return entryCount, failedEntryCount, vertexCount, triangleCount
end

function BBS.RefineRagdollImpact( entity, rawPosition, direction )
	local halfLength = math.Clamp( GetFloat( "bbs_debug_trace_length", 32 ), 1, 512 )
	local traceStart = rawPosition - direction * halfLength
	local traceEnd = rawPosition + direction * halfLength
	local forward = RunTargetTrace( entity, traceStart, traceEnd )
	local reverse = RunTargetTrace( entity, traceEnd, traceStart )
	local selected = nil
	local selectedName = "miss"

	if ValidTargetHit( forward, entity ) then
		selected = forward
		selectedName = "forward"
	end
	if ValidTargetHit( reverse, entity )
	and TraceDistanceToRaw( reverse, rawPosition ) < TraceDistanceToRaw( selected, rawPosition ) then
		selected = reverse
		selectedName = "reverse"
	end

	return selected, selectedName, forward, reverse, traceStart, traceEnd
end


local function AddDebugHit( hit )
	local retainHistory = GetBool( "bbs_debug_overlay" )
		or GetBool( "bbs_debug_hud" ) or GetBool( "bbs_debug_console" )
		or GetBool( "bbs_damage_uv_preview" )
		or GetBool( "bbs_damage_dump_debug" )
	-- Adaptive projection can generate thousands of UV micro-triangles. Only
	-- the newest hit needs them for the live preview; retaining them in every
	-- historical marker would turn the debug history into a large memory sink.
	local previousHit = BBS.LastHit
	for _, materialRecord in ipairs( previousHit and previousHit.damageUV
	and previousHit.damageUV.materials or {} ) do
		materialRecord.projectedTriangles = nil
	end
	BBS.LastHit = hit
	if not retainHistory then
		BBS.DebugHits = {}
		return
	end
	table.insert( BBS.DebugHits, hit )
	local maximum = math.Clamp( GetInt( "bbs_debug_max_markers", 64 ), 1, 512 )
	while #BBS.DebugHits > maximum do table.remove( BBS.DebugHits, 1 ) end
end

local function PrintHit( hit, meshOnly )
	if not meshOnly then
		BBS.Log( "CL hit #%d ent=%d model=%s damage=%.2f impacts=%d attacker=%s",
			hit.serial, hit.entityIndex, hit.model, hit.damage,
			hit.burstImpactCount or 1, tostring( hit.attacker ) )
		BBS.Log( "  raw=[%s] dir=[%s] trace=%s delta=%.3f",
			BBS.FormatVector( hit.rawPosition ), BBS.FormatVector( hit.direction ),
			hit.traceName, hit.surfacePosition:Distance( hit.rawPosition ) )
		BBS.Log( "  surface=[%s] normal=[%s] hitbox=%d physbone=%d bone=%d (%s)",
			BBS.FormatVector( hit.surfacePosition ), BBS.FormatVector( hit.normal ),
			hit.hitBox, hit.physicsBone, hit.modelBone, hit.boneName )
		BBS.Log( "  attachment=%s (impact pose captured before mesh analysis)",
			hit.attachment and hit.attachment.kind or "none" )
		local hull = hit.hullParameters or {}
		BBS.Log( "  damage shape: base=%.3f nominal=%.3f range=%.3f..%.3f multiplier=%.3f irregularity=%.3f tears=%d samples=%d seed=%s cap=%.2fx",
			hull.baseRadius or hull.radius or 0,
			hull.radius or 0, hull.minimumRadius or hull.radius or 0,
			hull.maximumRadius or hull.radius or 0,
			hull.damageMultiplier or 1, hull.irregularity or 0,
			hull.tearCount or 0, hull.shapeSamples or 0,
			tostring( hull.seed ), hull.maximumDamageMultiplier or 1 )
		BBS.Log( "  forward: hit=%s ent=%s | reverse: hit=%s ent=%s",
			tostring( hit.forward and hit.forward.Hit ),
			tostring( hit.forward and hit.forward.Entity ),
			tostring( hit.reverse and hit.reverse.Hit ),
			tostring( hit.reverse and hit.reverse.Entity ) )
		if hit.modelFilter then
			BBS.Log( "  model filter: mode=%s listed=%s allowed=%s reason=%s",
				tostring( hit.modelFilter.mode ), tostring( hit.modelFilter.listed ),
				tostring( hit.modelFilter.allowed ), tostring( hit.modelFilter.reason ) )
		end
	end
	local query = hit.meshQuery
	if query and query.pending then
		BBS.Log( "  removal hull mesh query queued (asynchronous)" )
	elseif query and query.ok then
		local probe = query.probe or {}
		if probe.diagnosticsCollected and probe.nearestSurfaceDistance then
			BBS.Log( "  nearest visual surface=%.3f nearest-corner=%.3f pos=[%s] mesh=%s material=%s skinning=%s scope=%s (diagnostic; hull center unchanged)",
				probe.nearestSurfaceDistance, probe.nearestVertexDistance or -1,
				BBS.FormatVector( probe.nearestSurfacePosition ),
				tostring( probe.nearestMeshIndex ),
				tostring( probe.nearestMaterial ),
				tostring( probe.skinningMode ), tostring( probe.diagnosticScope ) )
		else
			BBS.Log( "  nearest visual diagnostics were skipped for the realtime query (skinning=%s)",
				tostring( probe.skinningMode ) )
		end
		BBS.Log( "  removal hull envelope: %d selected triangle vertices (%d envelope-inside), %d triangles in %d meshes; candidates=%d/%d scanned=%d uniqueSkin=%d reusedSkin=%d skipped=%d cache=%s cpu=%.2f ms wall=%.2f ms",
			query.vertexCount, query.insideVertexCount, query.triangleCount,
			query.meshCount, query.candidateTriangleCount or 0,
			query.totalTriangleCount or 0, query.scannedVertexCount,
			query.uniqueSkinnedVertexCount or 0,
			query.reusedSkinnedVertexCount or 0,
			query.skippedVertexCount, query.cacheHit and NL("hit") or NL("miss"),
			query.queryMilliseconds, query.wallMilliseconds or query.queryMilliseconds )
		if query.boneCandidateRejected then
			BBS.Log( "  bone-local candidates were insufficient; result uses full-model fallback" )
		end
		local candidateStats = query.initialCandidateStats or query.candidateStats or {}
		BBS.Log( "  acceleration: boneSpatial=%s bones=%d (%d hierarchy + %d visual-overlap) boundTests=%d bounds=%s rejected=%d/%d padding=%.1f localBounds=%s intervalReject=%d (axial=%d radial=%d) exactTests=%d diagnosticClosest=%d initialCandidates=%s",
			tostring( candidateStats.spatial or false ),
			candidateStats.candidateBoneCount or 0,
			candidateStats.neighborBoneCount or 0,
			candidateStats.spatialBoneCount or 0,
			candidateStats.boneBoundsTestCount or 0,
			tostring( candidateStats.boneBoundsAvailable or false ),
			candidateStats.spatialRejectedCount or 0,
			candidateStats.unfilteredCount or query.candidateTriangleCount or 0,
			candidateStats.padding or 0,
			tostring( query.localBoundsEnabled ~= false ),
			query.intervalRejectedCount or query.broadPhaseRejectedCount or 0,
			query.axialIntervalRejectedCount or 0,
			query.radialIntervalRejectedCount or 0,
			query.exactTestCount or 0,
			query.diagnosticClosestPointCount or 0,
			tostring( query.initialCandidateTriangleCount or query.candidateTriangleCount ) )
		BBS.Log( "  timing: meshCache=%.2f ms cacheWait=%.2f ms poseSnapshot=%.2f ms skinTransforms=%.2f ms maxSlice=%.2f ms queryWall=%.2f ms hitToQuery=%.2f ms",
			query.meshCacheLookupMilliseconds or 0,
			query.meshCacheWaitMilliseconds or 0,
			query.poseSnapshotMilliseconds or 0,
			query.poseTransformMilliseconds or 0,
			query.maximumSliceMilliseconds or 0,
			query.wallMilliseconds or query.queryMilliseconds or 0,
			query.pipelineWallMilliseconds or query.wallMilliseconds
				or query.queryMilliseconds or 0 )
		local preparation = query.meshCachePreparation
		if preparation then
			BBS.Log( "  cache preparation: wall=%.2f ms target=%.2f s diskCPU=%.2f ms frames=%d chunks=%d native=%.2f ms meshCPU=%.2f ms maxSlice=%.2f ms eligibilityCPU=%.2f ms maxSlice=%.2f ms base/final/max=%.2f/%.2f/%.2f ms hardCap=%.2f ms handoffRecovered=%s",
				preparation.preparationWallMilliseconds or 0,
				preparation.targetSeconds or 0,
				preparation.diskHydrationMilliseconds or 0,
				preparation.diskHydrationFrames or 0,
				preparation.diskChunksRead or 0,
				preparation.nativeExtractionMilliseconds or 0,
				preparation.meshBuildMilliseconds or 0,
				preparation.meshMaximumSliceMilliseconds or 0,
				preparation.eligibilityMilliseconds or 0,
				preparation.eligibilityMaximumSliceMilliseconds or 0,
				preparation.configuredBudgetMilliseconds or 0,
				preparation.budgetMilliseconds or 0,
				preparation.maximumBudgetMilliseconds or 0,
				preparation.catchupCeilingMilliseconds or 0,
				tostring( preparation.meshReturnRecovered or false ) )
		end
		for _, matchingMesh in ipairs( query.meshes ) do
			BBS.Log( "    mesh=%d material=%s vertices=%d triangles=%d source=%s",
				matchingMesh.meshIndex, matchingMesh.material,
				#matchingMesh.vertices, #matchingMesh.triangles, matchingMesh.sourceKind )
		end
	elseif query then
		BBS.Log( "  removal hull query failed: %s", query.error or "unknown error" )
		if query.probe then
			BBS.Log( "  probe: nearest surface=%.3f nearest vertex=%.3f bounds=[%s]..[%s]",
				query.probe.nearestSurfaceDistance or -1,
				query.probe.nearestVertexDistance or -1,
				BBS.FormatVector( query.probe.worldBoundsMinimum ),
				BBS.FormatVector( query.probe.worldBoundsMaximum ) )
		end
	end
end

local function ProfiledPrintHit( hit, meshOnly )
	local started = BBS.PerfBegin and BBS.PerfBegin( hit ) or nil
	PrintHit( hit, meshOnly )
	if BBS.PerfEnd then BBS.PerfEnd( hit, "Debug console output", started ) end
end

local function CompleteMeshQueryJob( job, result )
	result = result or { ok = false, error = "mesh query returned no result" }
	result.pending = false
	result.queryMilliseconds = job.cpuMilliseconds or 0
	result.maximumSliceMilliseconds = job.maximumSliceMilliseconds or 0
	result.meshCacheLookupMilliseconds = job.hit.meshCacheLookupMilliseconds or 0
	result.poseCaptureMilliseconds = job.hit.poseCaptureMilliseconds or 0
	result.poseSnapshotMilliseconds = job.hit.poseSnapshotMilliseconds or 0
	result.poseTransformMilliseconds = job.hit.poseTransformMilliseconds or 0
	result.meshCacheWaitMilliseconds = job.hit.meshCacheWaitMilliseconds or 0
	result.meshCachePreparation = job.hit.meshCachePreparation
	result.wallMilliseconds = ( SysTime() - job.enqueuedTime ) * 1000
	result.pipelineWallMilliseconds = job.hit.pipelineStarted
		and ( SysTime() - job.hit.pipelineStarted ) * 1000 or result.wallMilliseconds
	job.hit.meshQuery = result
	if BBS.PerfAddMilliseconds then
		BBS.PerfAddMilliseconds( job.hit, "Removal-hull mesh query", result.queryMilliseconds )
	end
	if GetBool( "bbs_debug_console" ) then ProfiledPrintHit( job.hit, true ) end
	hook.Run( "BBS.MeshQueryCompleted", job.hit, result )
end

function BBS.QueueHitMeshQuery( hit, surfacePosition, direction, normal,
	deferredBoneSnapshot )
	-- Snapshot the impact pose before a cold util.GetModelMeshes/cache build can
	-- consume a long frame and allow physics to move the ragdoll.
	local currentBoneSnapshot = deferredBoneSnapshot
	if not currentBoneSnapshot then
		local poseSnapshotStarted = SysTime()
		currentBoneSnapshot = CaptureCurrentBoneMatrices( hit.entity )
		hit.poseSnapshotMilliseconds = ( SysTime() - poseSnapshotStarted ) * 1000
		if BBS.PerfAddMilliseconds then
			BBS.PerfAddMilliseconds( hit, "Pose snapshot", hit.poseSnapshotMilliseconds )
		end
	end

	local cacheKey = MeshCacheKey( hit.entity, 0 )
	local cachedMeshData = BBS.ModelMeshCache[ cacheKey ]
	if cachedMeshData == false then
		hit.meshQuery = {
			ok = false,
			pending = false,
			cacheKey = cacheKey,
			error = "model mesh extraction is negative-cached as unavailable",
		}
		if BBS.PerfFinish then BBS.PerfFinish( hit, "mesh_cache_unavailable" ) end
		return false
	end
	local meshReady = cachedMeshData ~= nil
		and not ( cachedMeshData and cachedMeshData.rtxCleanupPending )
	local eligibilityRequired = GetBool( "bbs_mesh_restrict_to_hideable" )
	local eligibilityReady = not eligibilityRequired
		or ( BBS.HideableMeshCache and BBS.HideableMeshCache[ cacheKey ] ~= nil )
	if not hit.synthetic and ( not meshReady or not eligibilityReady ) then
		local preparationQueued = QueueMeshPrewarm( hit.entity, true )
		if not preparationQueued then
			hit.meshQuery = {
				ok = false,
				pending = false,
				cacheKey = cacheKey,
				error = "background model mesh preparation could not be queued",
			}
			if BBS.PerfFinish then
				BBS.PerfFinish( hit, "mesh_cache_unavailable" )
			end
			return false
		end
		hit.meshQuery = {
			ok = false,
			pending = true,
			cachePending = true,
			cacheKey = cacheKey,
		}
		-- This is a soft scheduling watermark, not a correctness cap. Dispatch
		-- backpressure normally leaves one retained snapshot per cold identity; if
		-- several different cold models are hit, never discard an older impact just
		-- because a low-end client needs more frames to prepare them.
		local deferredWatermark = math.Clamp(
			GetInt( "bbs_deferred_hit_limit", 4 ), 1, 64 )
		hit.meshQuery.cacheBacklogAboveWatermark =
			#BBS.DeferredHitMeshQueue >= deferredWatermark
		BBS.DeferredHitMeshQueue[ #BBS.DeferredHitMeshQueue + 1 ] = {
			hit = hit,
			surfacePosition = surfacePosition,
			direction = direction,
			normal = normal,
			boneSnapshot = currentBoneSnapshot,
			cacheKey = cacheKey,
			waitStarted = SysTime(),
			nextProducerWatchdogAt = SysTime() + 15,
		}
		hit.meshCacheWaitStarted = SysTime()
		return true
	end
	local cacheStarted = SysTime()
	local meshData, cacheHit, cacheError = BBS.GetCachedModelMeshes( hit.entity, 0 )
	hit.meshCacheLookupMilliseconds = ( SysTime() - cacheStarted ) * 1000
	if BBS.PerfAddMilliseconds then
		BBS.PerfAddMilliseconds( hit, "Mesh cache lookup/build",
			hit.meshCacheLookupMilliseconds )
	end
	if not meshData then
		hit.meshQuery = {
			ok = false,
			pending = false,
			error = cacheError or "mesh data unavailable",
		}
		if BBS.PerfFinish then BBS.PerfFinish( hit, "mesh_cache_unavailable" ) end
		return false
	end

	-- Capture every bone transform immediately, before yielding any work to
	-- later frames. This is the exact pose used for all triangle calculations.
	local poseStarted = SysTime()
	local transforms = BuildSkinTransforms(
		hit.entity, meshData, nil, currentBoneSnapshot )
	hit.poseTransformMilliseconds = ( SysTime() - poseStarted ) * 1000
	if BBS.PerfAddMilliseconds then
		BBS.PerfAddMilliseconds( hit, "Skin transform setup",
			hit.poseTransformMilliseconds )
	end
	hit.poseCaptureMilliseconds = hit.poseSnapshotMilliseconds
		+ hit.poseTransformMilliseconds
	local dumpDiagnostics = GetBool( "bbs_damage_dump_debug" )
	local layerLimit = math.Clamp( GetInt( "bbs_damage_layer_limit", 0 ), 0, 64 )
	hit.damageLayerLimit = layerLimit
	local job = {
		hit = hit,
		meshData = meshData,
		cacheHit = cacheHit,
		transforms = transforms,
		enqueuedTime = SysTime(),
		cpuMilliseconds = 0,
		maximumSliceMilliseconds = 0,
		steps = 0,
		layerLimit = layerLimit,
		-- Nearest-surface and full posed-bounds data are diagnostic-only. Keep
		-- them for explicit probes, console investigations, and debug bundles;
		-- normal damage only needs exact intersecting triangle/UV records.
		collectDiagnostics = hit.synthetic
			or GetBool( "bbs_debug_console" )
			or dumpDiagnostics,
		collectRejectedDiagnostics = hit.synthetic or dumpDiagnostics,
	}
	local eligibility = GetBool( "bbs_mesh_restrict_to_hideable" )
		and not hit.synthetic and BBS.HideableMeshCache
		and BBS.HideableMeshCache[ meshData.key ] or nil
	-- A finite layer cap must see non-damageable visual meshes because each one
	-- consumes a ray layer. Unlimited mode can retain the faster eligible-only
	-- query since occluders cannot change its result.
	if layerLimit == 0 and eligibility
	and ( eligibility.hideableMeshCount or 0 ) > 0 then
		job.allowedMeshes = eligibility.meshGroups
	end
	hit.meshQuery = {
		ok = false,
		pending = true,
		cacheHit = cacheHit,
	}

	job.thread = coroutine.create( function()
		-- The physics hitbone seeds a cheap local hierarchy. Per-bone visual bounds
		-- then add every other posed partition overlapping the cylinder envelope,
		-- so collisionless coats/skirts in front of an underlying body hull remain
		-- candidates. The complete-model fallback remains a final safety net.
		local candidateBone = GetBool( "bbs_mesh_force_full_scan" )
			and nil or hit.modelBone
		-- Mesh collection uses the irregular shape's enclosing radius so no tear
		-- lobe can be omitted. Exact jagged clipping happens later in world-to-UV
		-- projection and may discard envelope-only triangles.
		local queryRadius = hit.hullParameters.maximumRadius
			or hit.hullParameters.radius
		return BBS.QueryMeshesInCylinder( hit.entity, surfacePosition, direction, normal,
			queryRadius, hit.hullParameters.insideDistance,
			hit.hullParameters.outsideDistance, candidateBone, job )
	end )
	BBS.MeshQueryQueue[ #BBS.MeshQueryQueue + 1 ] = job
	return true
end

hook.Add( "Think", "BBS.ResumeCacheDeferredHitQueries", function()
	local resumed = 0
	local index = 1
	while index <= #BBS.DeferredHitMeshQueue do
		local deferred = BBS.DeferredHitMeshQueue[ index ]
		local hit = deferred.hit
		if not IsValid( hit.entity ) then
			table.remove( BBS.DeferredHitMeshQueue, index )
			hit.meshQuery = { ok = false, pending = false,
				error = "entity was removed while its mesh cache was prepared" }
			if BBS.PerfFinish then BBS.PerfFinish( hit, "entity_removed" ) end
			BBS.ReleaseOrphanUrgentMeshPrewarm( deferred.cacheKey )
		elseif MeshCacheKey( hit.entity, 0 ) ~= deferred.cacheKey then
			table.remove( BBS.DeferredHitMeshQueue, index )
			hit.meshQuery = { ok = false, pending = false,
				cacheKey = deferred.cacheKey,
				error = "target model/bodygroup/skin changed while waiting for its mesh cache" }
			if BBS.PerfFinish then
				BBS.PerfFinish( hit, "mesh_identity_changed" )
			end
			BBS.ReleaseOrphanUrgentMeshPrewarm( deferred.cacheKey )
		else
			local cached = BBS.ModelMeshCache[ deferred.cacheKey ]
			if cached == false then
				table.remove( BBS.DeferredHitMeshQueue, index )
				hit.meshQuery = { ok = false, pending = false,
					cacheKey = deferred.cacheKey,
					error = "background model mesh extraction failed" }
				if BBS.PerfFinish then
					BBS.PerfFinish( hit, "mesh_cache_unavailable" )
				end
				BBS.ReleaseOrphanUrgentMeshPrewarm( deferred.cacheKey )
			else
			local meshReady = cached ~= nil
				and not ( cached and cached.rtxCleanupPending )
			local eligibilityReady = not GetBool( "bbs_mesh_restrict_to_hideable" )
				or BBS.HideableMeshCache[ deferred.cacheKey ] ~= nil
			local producer = BBS.MeshPrewarmByKey
				and BBS.MeshPrewarmByKey[ deferred.cacheKey ] or nil
			local recoveryFailed = false
			local now = SysTime()
			local watchdogDue = now >=
				( deferred.nextProducerWatchdogAt or 0 )
			if ( not meshReady or not eligibilityReady )
			and ( not producer or watchdogDue ) then
				deferred.recoveryAttempts = ( deferred.recoveryAttempts or 0 ) + 1
				deferred.lastRecoveryAt = now
				deferred.nextProducerWatchdogAt = now + 15
				local recoveryQueued = QueueMeshPrewarm( hit.entity, true )
				producer = BBS.MeshPrewarmByKey
					and BBS.MeshPrewarmByKey[ deferred.cacheKey ] or nil
				hit.meshQuery.cacheRecoveryAttempts = deferred.recoveryAttempts
				if GetBool( "bbs_debug_console" ) then
					BBS.Log( "  cache wait watchdog: attempt=%d waited=%.2f s meshReady=%s eligibilityReady=%s queued=%s producer=%s",
						deferred.recoveryAttempts,
						math.max( now - ( deferred.waitStarted or now ), 0 ),
						tostring( meshReady ),
						tostring( eligibilityReady ), tostring( recoveryQueued ),
						tostring( producer and producer.phase or "<none>" ) )
				end
				if not recoveryQueued and not producer then
					-- Recheck after QueueMeshPrewarm: it legitimately returns false if
					-- another hook published both readiness records in this frame.
					local recovered = BBS.ModelMeshCache[ deferred.cacheKey ]
					meshReady = recovered ~= nil
						and not ( recovered and recovered.rtxCleanupPending )
					eligibilityReady = not GetBool( "bbs_mesh_restrict_to_hideable" )
						or BBS.HideableMeshCache[ deferred.cacheKey ] ~= nil
					recoveryFailed = not meshReady or not eligibilityReady
				end
			end
			if recoveryFailed then
				table.remove( BBS.DeferredHitMeshQueue, index )
				hit.meshQuery = { ok = false, pending = false,
					cacheKey = deferred.cacheKey,
					error = "orphaned model cache producer could not be recovered" }
				if BBS.PerfFinish then
					BBS.PerfFinish( hit, "mesh_cache_producer_unavailable" )
				end
			elseif meshReady and eligibilityReady and #BBS.MeshQueryQueue < 2 then
				table.remove( BBS.DeferredHitMeshQueue, index )
				hit.meshCacheWaitMilliseconds = ( SysTime()
					- ( deferred.waitStarted or hit.meshCacheWaitStarted
						or hit.pipelineStarted or SysTime() ) ) * 1000
				hit.meshCachePreparation = deferred.preparation
				BBS.QueueHitMeshQuery( hit, deferred.surfacePosition,
					deferred.direction, deferred.normal, deferred.boneSnapshot )
				resumed = resumed + 1
				if resumed >= 1 then break end
			else
				index = index + 1
			end
			end
		end
	end
end )

hook.Add( "Think", "BBS.ProcessAsynchronousMeshQueries", function()
	local job = BBS.MeshQueryQueue[ 1 ]
	if not job then return end
	-- Paint commits CPU hole history as well as GPU alpha. Finish it before the
	-- next query so finite-layer ordering is exact and automatic fire cannot stack
	-- a query slice with a render-target slice in the same frame.
	if #( BBS.DamagePaintQueue or {} ) > 0 then return end
	if not BBS.TryBeginHeavyFrame( "mesh-query" ) then return end
	if not IsValid( job.hit.entity ) then
		table.remove( BBS.MeshQueryQueue, 1 )
		job.hit.meshQuery = { ok = false, pending = false,
			error = "entity was removed during mesh analysis" }
		if BBS.PerfFinish then BBS.PerfFinish( job.hit, "entity_removed" ) end
		return
	end
	if MeshCacheKey( job.hit.entity, 0 ) ~= job.meshData.key then
		table.remove( BBS.MeshQueryQueue, 1 )
		job.hit.meshQuery = { ok = false, pending = false,
			cacheKey = job.meshData.key,
			error = "target model/bodygroup/skin changed during mesh analysis" }
		if BBS.PerfFinish then
			BBS.PerfFinish( job.hit, "mesh_identity_changed" )
		end
		return
	end

	local budgetMilliseconds = math.Clamp(
		GetFloat( "bbs_mesh_query_budget_ms", 10 ), 0.25, 80 )
	job.deadline = SysTime() + budgetMilliseconds / 1000
	local resumeStarted = SysTime()
	local ok, result = coroutine.resume( job.thread )
	local sliceMilliseconds = ( SysTime() - resumeStarted ) * 1000
	job.cpuMilliseconds = job.cpuMilliseconds + sliceMilliseconds
	job.maximumSliceMilliseconds = math.max(
		job.maximumSliceMilliseconds or 0, sliceMilliseconds )

	if not ok then
		table.remove( BBS.MeshQueryQueue, 1 )
		CompleteMeshQueryJob( job, {
			ok = false,
			error = "mesh query coroutine: " .. tostring( result ),
		} )
	elseif coroutine.status( job.thread ) == "dead" then
		table.remove( BBS.MeshQueryQueue, 1 )
		CompleteMeshQueryJob( job, result )
	end
end )

function BBS.ProcessEntityHit( serial, entity, rawPosition, direction, damage,
	attacker, synthetic, burstImpactCount )
	local targetEnabled, targetKind = BBS.IsDamageTargetEnabled( entity )
	if not targetEnabled then return end
	if direction:IsZero() then return end
	direction = direction:GetNormalized()
	local pipelineStarted = SysTime()

	local selected, traceName, forward, reverse, traceStart, traceEnd =
		BBS.RefineRagdollImpact( entity, rawPosition, direction )
	local surfacePosition = selected and selected.HitPos or rawPosition
	local normal = selected and selected.HitNormal or -direction
	local physicsBone, modelBone, boneName = ResolveBone( entity, selected, surfacePosition )
	local duration = math.max( GetFloat( "bbs_debug_duration", 15 ), 0 )

	BBS.ClientHitCount = BBS.ClientHitCount + 1
	local hit = {
		serial = serial,
		entity = entity,
		entityIndex = entity:EntIndex(),
		entityKind = targetKind,
		model = entity:GetModel() or "<none>",
		attacker = attacker,
		damage = damage,
		burstImpactCount = math.max( tonumber( burstImpactCount ) or 1, 1 ),
		synthetic = synthetic or false,
		rawPosition = rawPosition,
		surfacePosition = surfacePosition,
		direction = direction,
		normal = normal,
		traceStart = traceStart,
		traceEnd = traceEnd,
		traceName = traceName,
		forward = forward,
		reverse = reverse,
		hitBox = selected and selected.HitBox or -1,
		physicsBone = physicsBone,
		modelBone = modelBone,
		boneName = boneName,
		created = CurTime(),
		pipelineStarted = pipelineStarted,
		dieTime = duration == 0 and math.huge or CurTime() + duration,
	}
	if BBS.PerfStartHit then BBS.PerfStartHit( hit ) end
	local baseRadius = math.Clamp( GetFloat( "bbs_hull_radius", 0.5 ), 0.05, 256 )
	local insideDistance = math.Clamp(
		GetFloat( "bbs_hull_inside_distance", 4 ), 0, 512 )
	local outsideDistance = math.Clamp(
		GetFloat( "bbs_hull_outside_distance", 10 ), 0, 512 )
	hit.hullParameters = BBS.BuildDamageHullParameters
		and BBS.BuildDamageHullParameters(
			hit, baseRadius, insideDistance, outsideDistance ) or {
			radius = baseRadius,
			minimumRadius = baseRadius,
			maximumRadius = baseRadius,
			insideDistance = insideDistance,
			outsideDistance = outsideDistance,
		}
	hit.attachment = CreateAttachment( hit )
	AddDebugHit( hit )
	if BBS.PerfAddMilliseconds then
		BBS.PerfAddMilliseconds( hit, "Impact trace + hit setup",
			( SysTime() - pipelineStarted ) * 1000 )
	end
	if BBS.IsModelDamageAllowed then
		local allowed, reason, normalized = BBS.IsModelDamageAllowed( hit.model )
		local config = BBS.GetDamageFilterConfig and BBS.GetDamageFilterConfig() or {}
		hit.modelFilter = {
			allowed = allowed,
			reason = reason,
			normalized = normalized,
			mode = config.modelMode or "blacklist",
			listed = normalized and BBS.DamageFilterModelIndex
				and BBS.DamageFilterModelIndex[ normalized ] == true or false,
		}
		if not allowed then
			hit.meshQuery = {
				ok = false,
				pending = false,
				skipped = true,
				status = "model_filter_blocked",
				error = reason or "model excluded by damage filter",
			}
			hit.damageUV = {
				ok = false,
				status = "model_filter_blocked",
				error = reason or "model excluded by damage filter",
			}
			if GetBool( "bbs_debug_console" ) then ProfiledPrintHit( hit ) end
			if BBS.PerfFinish then BBS.PerfFinish( hit, "model_filter_blocked" ) end
			return
		end
	end
	local queued = BBS.QueueHitMeshQuery( hit, surfacePosition, direction, normal )
	if not queued and BBS.PerfFinish then BBS.PerfFinish( hit, "mesh_query_not_queued" ) end
	if GetBool( "bbs_debug_console" ) then ProfiledPrintHit( hit ) end
end

-- Compatibility for external debug commands or older auto-refreshed closures.
BBS.ProcessRagdollHit = BBS.ProcessEntityHit

local function MergeQueuedHits( destination, source, preservePosition )
	if not destination or not source then return destination end
	local oldDamage = math.max( tonumber( destination.damage ) or 0, 0.1 )
	local addedDamage = math.max( tonumber( source.damage ) or 0, 0.1 )
	local totalWeight = oldDamage + addedDamage
	if not preservePosition then
		destination.rawPosition = ( destination.rawPosition * oldDamage
			+ source.rawPosition * addedDamage ) / totalWeight
	end
	destination.directionSum = destination.directionSum
		or destination.direction * oldDamage
	local sourceDirectionSum = source.directionSum
		or source.direction * addedDamage
	destination.directionSum = destination.directionSum + sourceDirectionSum
	if not destination.directionSum:IsZero() then
		destination.direction = destination.directionSum:GetNormalized()
	end
	destination.damage = ( tonumber( destination.damage ) or 0 )
		+ ( tonumber( source.damage ) or 0 )
	destination.burstImpactCount =
		( destination.burstImpactCount or 1 )
		+ ( source.burstImpactCount or 1 )
	destination.serial = source.serial or destination.serial
	destination.attacker = source.attacker or destination.attacker
	return destination
end

local function TrimHitDispatchQueue()
	local maximum = math.Clamp( GetInt( "bbs_hit_queue_limit", 32 ), 4, 256 )
	while #BBS.HitDispatchQueue > maximum do
		local overflow, overflowIndex, nearest
		for sourceIndex = 1, #BBS.HitDispatchQueue - 1 do
			local candidateSource = BBS.HitDispatchQueue[ sourceIndex ]
			local nearestDistanceSquared
			for targetIndex = sourceIndex + 1, #BBS.HitDispatchQueue do
				local candidate = BBS.HitDispatchQueue[ targetIndex ]
				if candidate.entity == candidateSource.entity then
					local distanceSquared = candidate.rawPosition:DistToSqr(
						candidateSource.rawPosition )
					if not nearestDistanceSquared
					or distanceSquared < nearestDistanceSquared then
						nearest = candidate
						nearestDistanceSquared = distanceSquared
					end
				end
			end
			if nearest then
				overflow = candidateSource
				overflowIndex = sourceIndex
				break
			end
		end
		-- Treat the configured limit as a coalescing watermark. Automatic fire on
		-- one target stays bounded without losing damage; hits on different entities
		-- remain queued because deleting them would make effect correctness depend on
		-- how quickly the client's CPU drains the pipeline.
		if not nearest then break end
		local retainedSerial, retainedAttacker = nearest.serial, nearest.attacker
		table.remove( BBS.HitDispatchQueue, overflowIndex )
		MergeQueuedHits( nearest, overflow, true )
		nearest.serial, nearest.attacker = retainedSerial, retainedAttacker
		BBS.HitQueueForcedMergeCount =
			( BBS.HitQueueForcedMergeCount or 0 ) + 1
	end
end

local function FlushHitBurst( entity, burst )
	if BBS.PendingHitBursts[ entity ] == burst then
		BBS.PendingHitBursts[ entity ] = nil
	end
	for _, cluster in ipairs( burst and burst.clusters or {} ) do
		BBS.HitDispatchQueue[ #BBS.HitDispatchQueue + 1 ] = cluster
	end
	TrimHitDispatchQueue()
end

local function AddNetworkHitToBurst( serial, entity, rawPosition, direction,
	damage, attacker )
	local record = {
		serial = serial,
		entity = entity,
		rawPosition = rawPosition,
		direction = direction,
		directionSum = direction * math.max( damage, 0.1 ),
		damage = math.max( damage, 0 ),
		attacker = attacker,
		burstImpactCount = 1,
	}
	if not GetBool( "bbs_hit_coalesce" ) then
		BBS.HitDispatchQueue[ #BBS.HitDispatchQueue + 1 ] = record
		TrimHitDispatchQueue()
		return
	end

	local now = SysTime()
	local window = math.Clamp(
		GetFloat( "bbs_hit_coalesce_window", 0.04 ), 0.005, 0.25 )
	local burst = BBS.PendingHitBursts[ entity ]
	if burst and now >= burst.deadline then
		FlushHitBurst( entity, burst )
		burst = nil
	end
	if not burst then
		burst = { entity = entity, deadline = now + window, clusters = {} }
		BBS.PendingHitBursts[ entity ] = burst
	end

	local radius = math.Clamp(
		GetFloat( "bbs_hit_coalesce_radius", 3 ), 0.05, 64 )
	local radiusSquared = radius * radius
	local nearest, nearestDistanceSquared
	for _, cluster in ipairs( burst.clusters ) do
		local distanceSquared = cluster.rawPosition:DistToSqr( rawPosition )
		if not nearestDistanceSquared or distanceSquared < nearestDistanceSquared then
			nearest = cluster
			nearestDistanceSquared = distanceSquared
		end
	end
	local maximumClusters = math.Clamp(
		GetInt( "bbs_hit_coalesce_max_clusters", 4 ), 1, 16 )
	local forcedMerge = #burst.clusters >= maximumClusters
	if not nearest or ( nearestDistanceSquared > radiusSquared and not forcedMerge ) then
		burst.clusters[ #burst.clusters + 1 ] = record
		return
	end

	MergeQueuedHits( nearest, record,
		forcedMerge and nearestDistanceSquared > radiusSquared )
end

hook.Add( "Think", "BBS.FlushAndDispatchHitBursts", function()
	local now = SysTime()
	for entity, burst in pairs( BBS.PendingHitBursts ) do
		local targetEnabled = BBS.IsDamageTargetEnabled( entity )
		if not targetEnabled then
			BBS.PendingHitBursts[ entity ] = nil
		elseif now >= burst.deadline then
			FlushHitBurst( entity, burst )
		end
	end

	-- Backpressure prevents impact setup from outrunning the coroutine query and
	-- one-material-per-frame paint stages during automatic fire.
	local paintQueueLength = #( BBS.DamagePaintQueue or {} )
	local finiteLayers = GetInt( "bbs_damage_layer_limit", 0 ) > 0
	if #BBS.MeshQueryQueue >= 2
	or paintQueueLength >= 4
	or ( finiteLayers and paintQueueLength > 0 ) then return end
	-- A cold model applies backpressure only to additional hits for the same
	-- cache key. Ready entities must not sit behind an unrelated model hydrate.
	local function WaitingOnColdKey( record )
		if not IsValid( record and record.entity ) then return false end
		local key = MeshCacheKey( record.entity, 0 )
		for _, deferred in ipairs( BBS.DeferredHitMeshQueue ) do
			if deferred.cacheKey == key then return true end
		end
		return false
	end
	local function PopDispatchableRecord()
		for index, record in ipairs( BBS.HitDispatchQueue ) do
			if not WaitingOnColdKey( record ) then
				return table.remove( BBS.HitDispatchQueue, index )
			end
		end
		return nil
	end
	local count = math.Clamp( GetInt( "bbs_hit_dispatch_per_frame", 1 ), 1, 4 )
	for _ = 1, count do
		local record = PopDispatchableRecord()
		if not record then break end
		local targetEnabled = BBS.IsDamageTargetEnabled( record.entity )
		if targetEnabled then
			BBS.ProcessEntityHit( record.serial, record.entity,
				record.rawPosition, record.direction, record.damage,
				record.attacker, false, record.burstImpactCount )
		end
		if #BBS.MeshQueryQueue >= 2 then break end
	end
end )

hook.Add( "EntityRemoved", "BBS.DropRemovedRagdollWork", function( entity )
	BBS.PendingHitBursts[ entity ] = nil
	local removedCacheKeys = {}
	for index = #BBS.HitDispatchQueue, 1, -1 do
		if BBS.HitDispatchQueue[ index ].entity == entity then
			table.remove( BBS.HitDispatchQueue, index )
		end
	end
	for index = #BBS.DeferredHitMeshQueue, 1, -1 do
		local deferred = BBS.DeferredHitMeshQueue[ index ]
		if deferred.hit and deferred.hit.entity == entity then
			table.remove( BBS.DeferredHitMeshQueue, index )
			removedCacheKeys[ deferred.cacheKey ] = true
			deferred.hit.meshQuery = { ok = false, pending = false,
				error = "entity was removed" }
			if BBS.PerfFinish then
				BBS.PerfFinish( deferred.hit, "entity_removed" )
			end
		end
	end
	for key in pairs( removedCacheKeys ) do
		BBS.ReleaseOrphanUrgentMeshPrewarm( key )
	end
end )

net.Receive( BBS.NET_HIT, function()
	local serial = net.ReadUInt( 16 )
	local entity = net.ReadEntity()
	local rawPosition = net.ReadVector()
	local direction = net.ReadNormal()
	local damage = net.ReadFloat()
	local attacker = net.ReadEntity()

	local targetEnabled = BBS.IsDamageTargetEnabled( entity )
	if not targetEnabled then return end
	AddNetworkHitToBurst(
		serial, entity, rawPosition, direction, damage, attacker )
end )

local function DrawCross( position, size, color )
	render.DrawLine( position - Vector( size, 0, 0 ), position + Vector( size, 0, 0 ), color, true )
	render.DrawLine( position - Vector( 0, size, 0 ), position + Vector( 0, size, 0 ), color, true )
	render.DrawLine( position - Vector( 0, 0, size ), position + Vector( 0, 0, size ), color, true )
end

local function LabelAngle( position )
	local angle = ( EyePos() - position ):Angle()
	angle:RotateAroundAxis( angle:Up(), -90 )
	angle:RotateAroundAxis( angle:Forward(), 90 )
	return angle
end

local function DrawHitLabel( hit, position, size )
	if not GetBool( "bbs_debug_labels" ) then return end

	cam.Start3D2D( position + Vector( 0, 0, size * 2.4 ), LabelAngle( position ), 0.06 )
		local title = string.format( "BBS #%d  %s", hit.serial,
			hit.traceName == "miss" and "TRACE MISS" or string.upper( hit.traceName ) )
		local details = string.format( "ent %d | hitbox %d | phys %d | bone %s",
			hit.entityIndex, hit.hitBox, hit.physicsBone, hit.boneName )
		draw.SimpleTextOutlined( title, "DermaLarge", 0, 0,
			hit.traceName == "miss" and COLOR_MISS or COLOR_TEXT,
			TEXT_ALIGN_CENTER, TEXT_ALIGN_BOTTOM, 2, Color( 0, 0, 0, 230 ) )
		draw.SimpleTextOutlined( details, "DermaDefaultBold", 0, 4, COLOR_TEXT,
			TEXT_ALIGN_CENTER, TEXT_ALIGN_TOP, 1, Color( 0, 0, 0, 230 ) )
	cam.End3D2D()
end

local function MeshVertex( position, color )
	mesh.Position( position )
	mesh.Color( color.r, color.g, color.b, color.a )
	mesh.AdvanceVertex()
end

local function MeshTriangle( first, second, third, color )
	MeshVertex( first, color )
	MeshVertex( second, color )
	MeshVertex( third, color )
end

local function DrawRemovalHull( surfacePosition, hitDirection, surfaceNormal,
	parameters, attachedRight )
	if not GetBool( "bbs_hull_enabled" ) then return end

	-- A retained marker must show the exact volume that its mesh query used.
	-- Settings are captured into hit.hullParameters when the shot arrives.
	parameters = parameters or {}
	local insideDistance = math.Clamp( parameters.insideDistance
		or GetFloat( "bbs_hull_inside_distance", 4 ), 0, 512 )
	local outsideDistance = math.Clamp( parameters.outsideDistance
		or GetFloat( "bbs_hull_outside_distance", 10 ), 0, 512 )
	local segments = math.Clamp( math.max( GetInt( "bbs_hull_segments", 20 ),
		parameters.shapeSamples or 0 ), 6, 64 )
	local alpha = math.Clamp( GetInt( "bbs_hull_fill_alpha", 38 ), 0, 255 )
	if insideDistance + outsideDistance <= 0 then return end

	-- Use the captured polar frame so random tears retain their orientation as
	-- the physics bone moves, instead of appearing to rotate around the axis.
	local frame = BBS.BuildRemovalHullFrame and BBS.BuildRemovalHullFrame(
		surfacePosition, hitDirection, surfaceNormal, parameters, attachedRight )
	if not frame then return end
	local inwardDirection = frame.axis

	local outsideEnd = surfacePosition - inwardDirection * outsideDistance
	local insideEnd = surfacePosition + inwardDirection * insideDistance
	local right = frame.right
	local up = frame.up
	local outsideRing = {}
	local insideRing = {}

	for index = 1, segments do
		local radians = ( parameters.angleOffset or 0 )
			+ ( index - 1 ) / segments * math.pi * 2
		local radius = BBS.RemovalHullRadiusAtAngle
			and BBS.RemovalHullRadiusAtAngle( frame, radians )
			or math.Clamp( parameters.radius
				or GetFloat( "bbs_hull_radius", 0.5 ), 0.05, 256 )
		local radial = right * math.cos( radians ) * radius
			+ up * math.sin( radians ) * radius
		outsideRing[ index ] = outsideEnd + radial
		insideRing[ index ] = insideEnd + radial
	end

	if alpha > 0 then
		local fill = Color( 60, 215, 235, alpha )
		mesh.Begin( MATERIAL_TRIANGLES, segments * 4 )
			for index = 1, segments do
				local nextIndex = index % segments + 1
				local outsideA = outsideRing[ index ]
				local outsideB = outsideRing[ nextIndex ]
				local insideA = insideRing[ index ]
				local insideB = insideRing[ nextIndex ]

				MeshTriangle( outsideA, insideA, insideB, fill )
				MeshTriangle( outsideA, insideB, outsideB, fill )
				MeshTriangle( outsideEnd, outsideB, outsideA, fill )
				MeshTriangle( insideEnd, insideA, insideB, fill )
			end
		mesh.End()
	end

	for index = 1, segments do
		local nextIndex = index % segments + 1
		render.DrawLine( outsideRing[ index ], outsideRing[ nextIndex ], COLOR_HULL_OUTSIDE, true )
		render.DrawLine( insideRing[ index ], insideRing[ nextIndex ], COLOR_HULL_INSIDE, true )
		render.DrawLine( outsideRing[ index ], insideRing[ index ], COLOR_HULL_WIRE, true )
	end

	-- Split the axis at the surface so inside and outside depth are obvious.
	render.DrawLine( outsideEnd, surfacePosition, COLOR_HULL_OUTSIDE, true )
	render.DrawLine( surfacePosition, insideEnd, COLOR_HULL_INSIDE, true )
end

hook.Add( "PostDrawTranslucentRenderables", "BBS.DrawRagdollHitOverlay", function( _, drawingSkybox )
	if drawingSkybox then return end
	for index = #BBS.DebugHits, 1, -1 do
		if BBS.DebugHits[ index ].dieTime < CurTime() then
			table.remove( BBS.DebugHits, index )
		end
	end
	if not GetBool( "bbs_debug_overlay" ) then return end
	if #BBS.DebugHits == 0 then return end
	local performanceStarted = BBS.PerfBeginBackground
		and BBS.PerfBeginBackground() or nil

	local size = math.Clamp( GetFloat( "bbs_debug_size", 3 ), 0.25, 64 )
	cam.IgnoreZ( GetBool( "bbs_debug_through_walls" ) )
	render.SetColorMaterial()

	for index = #BBS.DebugHits, 1, -1 do
		local hit = BBS.DebugHits[ index ]
		local rawPosition, surfacePosition, traceStart, traceEnd, direction, normal,
			hullRight =
			AttachedWorldValues( hit )
		local surfaceColor = hit.traceName == "miss" and COLOR_MISS or COLOR_SURFACE
		render.DrawLine( traceStart, traceEnd, COLOR_TRACE, true )
		DrawCross( rawPosition, size * 0.7, COLOR_RAW )
		DrawCross( surfacePosition, size, surfaceColor )
		render.DrawWireframeSphere( surfacePosition, size, 10, 8, surfaceColor, true )
		render.DrawLine( surfacePosition,
			surfacePosition + normal * size * 3, COLOR_NORMAL, true )
		render.DrawLine( rawPosition - direction * size * 3,
			rawPosition, COLOR_DIRECTION, true )
		DrawRemovalHull( surfacePosition, direction, normal,
			hit.hullParameters, hullRight )
		DrawHitLabel( hit, surfacePosition, size )
	end

	cam.IgnoreZ( false )
	if BBS.PerfEndBackground then
		BBS.PerfEndBackground( "Frame: 3D hit overlay", performanceStarted )
	end
end )

hook.Add( "EntityRemoved", "BBS.RemoveDetachedDebugHits", function( entity )
	for index = #BBS.DebugHits, 1, -1 do
		if BBS.DebugHits[ index ].entity == entity then
			table.remove( BBS.DebugHits, index )
		end
	end
	if BBS.LastHit and BBS.LastHit.entity == entity then BBS.LastHit = nil end
end )

hook.Add( "HUDPaint", "BBS.DrawLastHitHUD", function()
	if not GetBool( "bbs_debug_hud" ) or not BBS.LastHit then return end
	local performanceStarted = BBS.PerfBeginBackground
		and BBS.PerfBeginBackground() or nil
	local hit = BBS.LastHit
	local width, height = 520, 122
	local x, y = 20, ScrH() - height - 20

	draw.RoundedBox( 6, x, y, width, height, Color( 10, 12, 16, 215 ) )
	draw.SimpleText( NL("Procedural Bodygroup Destruction — hit debugger"), "DermaDefaultBold",
		x + 10, y + 9, Color( 255, 175, 75 ), TEXT_ALIGN_LEFT, TEXT_ALIGN_TOP )
	draw.SimpleText( string.format( NL("#%d  ent %d  %s  damage %.1f"), hit.serial,
		hit.entityIndex, hit.traceName == "miss" and NL("TRACE MISS") or NL("surface: ") .. hit.traceName,
		hit.damage ), "DermaDefault", x + 10, y + 31, COLOR_TEXT, TEXT_ALIGN_LEFT, TEXT_ALIGN_TOP )
	draw.SimpleText( string.format( NL("hitbox %d | physbone %d | model bone %d (%s)"),
		hit.hitBox, hit.physicsBone, hit.modelBone, hit.boneName ), "DermaDefault",
		x + 10, y + 49, COLOR_TEXT, TEXT_ALIGN_LEFT, TEXT_ALIGN_TOP )
	local query = hit.meshQuery
	local queryText = NL("removal hull mesh query unavailable")
	local queryColor = COLOR_MISS
	if query and query.pending and query.cachePending then
		local preparation = BBS.MeshPrewarmByKey
			and BBS.MeshPrewarmByKey[ query.cacheKey ] or nil
		local phase = preparation and preparation.phase or "queued"
		if phase == "disk" then phase = NL("loading persistent mesh")
		elseif phase == "mesh" then phase = NL("packing native mesh")
		elseif phase == "eligibility" then phase = NL("checking bodygroups")
		elseif phase == "rtx_cleanup" then phase = NL("releasing native mesh memory")
		elseif phase == "resolve" then phase = NL("opening model cache") end
		local waited = hit.meshCacheWaitStarted
			and math.max( SysTime() - hit.meshCacheWaitStarted, 0 ) or 0
		local budget, remainingChunks = 0, nil
		if preparation then
			local configuredBudget, remainingSeconds
			budget, configuredBudget, remainingSeconds, remainingChunks =
				MeshPreparationBudget( preparation,
					preparation.phase == "mesh" and "bbs_mesh_build_budget_ms"
						or "bbs_mesh_cache_io_budget_ms",
					preparation.phase == "mesh" and 15 or 10,
					preparation.phase == "mesh" and 0.25 or 0.1 )
		end
		queryText = string.format( NL("cache: %s… %.2f s | %s chunks | %.1f ms/frame"),
			phase, waited, tostring( remainingChunks or "?" ), budget )
		queryColor = Color( 255, 205, 90 )
	elseif query and query.pending then
		queryText = string.format( NL("hull: analyzing impact snapshot… queue %d | budget %.1f ms/frame"),
			#BBS.MeshQueryQueue, GetFloat( "bbs_mesh_query_budget_ms", 10 ) )
		queryColor = Color( 255, 205, 90 )
	elseif query and query.ok then
		queryText = string.format( NL("hull envelope: %d verts (%d inside) | %d tris / %d meshes | cache %s | %.2f ms"),
			query.vertexCount, query.insideVertexCount, query.triangleCount,
			query.meshCount, query.cacheHit and NL("hit") or NL("miss"), query.queryMilliseconds )
		queryColor = Color( 100, 235, 255 )
	elseif query then
		queryText = NL("removal hull query failed: ") .. tostring( query.error )
	end
	draw.SimpleText( queryText, "DermaDefaultBold", x + 10, y + 68, queryColor,
		TEXT_ALIGN_LEFT, TEXT_ALIGN_TOP )
	if BBS.GetDamageHUDStatus then
		local damageText, damageColor = BBS.GetDamageHUDStatus( hit )
		draw.SimpleText( damageText, "DermaDefault", x + 10, y + 87,
			damageColor or Color( 175, 185, 200 ), TEXT_ALIGN_LEFT, TEXT_ALIGN_TOP )
	end
	draw.SimpleText( string.format( NL("retained %d / received %d"), #BBS.DebugHits, BBS.ClientHitCount ),
		"DermaDefault", x + width - 10, y + 9, Color( 170, 180, 195 ), TEXT_ALIGN_RIGHT, TEXT_ALIGN_TOP )
	if BBS.PerfEndBackground then
		BBS.PerfEndBackground( "Frame: last-hit HUD", performanceStarted )
	end
end )

concommand.Add( "bbs_debug_clear", function()
	for _, job in ipairs( BBS.MeshQueryQueue ) do
		if job.hit then
			job.hit.meshQuery = { ok = false, pending = false,
				error = "debug work was cleared" }
			if BBS.PerfFinish then BBS.PerfFinish( job.hit, "debug_cleared" ) end
		end
	end
	BBS.DebugHits = {}
	BBS.LastHit = nil
	BBS.MeshQueryQueue = {}
	BBS.Log( "cleared client debug markers" )
end, nil, "Clear all Procedural Bodygroup Destruction debug markers." )

concommand.Add( "bbs_debug_dump_last", function()
	if not BBS.LastHit then
		BBS.Log( "no client hit has been received yet" )
		return
	end
	PrintHit( BBS.LastHit )
end, nil, "Print the most recent model hit diagnostics." )

concommand.Add( "bbs_debug_status", function()
	BBS.Log( "version=%s enabled=%s livingPlayers=%s livingNPCs=%s deathOnly=%s overlay=%s retained=%d received=%d queuedQueries=%d deferredHits=%d dispatchQueue=%d activeBursts=%d paintQueue=%d forcedQueueMerges=%d",
		BBS.Version, tostring( GetBool( "bbs_enabled" ) ),
		tostring( GetBool( "bbs_damage_living_players" ) ),
		tostring( GetBool( "bbs_damage_living_npcs" ) ),
		tostring( GetBool( "bbs_death_ragdolls_only" ) ),
		tostring( GetBool( "bbs_debug_overlay" ) ), #BBS.DebugHits,
		BBS.ClientHitCount, #BBS.MeshQueryQueue, #BBS.DeferredHitMeshQueue,
		#BBS.HitDispatchQueue, table.Count( BBS.PendingHitBursts ),
		#( BBS.DamagePaintQueue or {} ),
		BBS.HitQueueForcedMergeCount or 0 )
	local entries, failedEntries, cachedVertices, cachedTriangles =
		BBS.GetModelMeshCacheSummary()
	local stats = BBS.ModelMeshCacheStats
	BBS.Log( "mesh cache: entries=%d failed=%d vertices=%d triangles=%d hits=%d misses=%d builds=%d failures=%d evictions=%d limits=%d entries/%d triangles",
		entries, failedEntries, cachedVertices, cachedTriangles,
		stats.hits or 0, stats.misses or 0, stats.builds or 0,
		stats.failures or 0, stats.evictions or 0,
		GetInt( "bbs_mesh_cache_max_entries", 6 ),
		GetInt( "bbs_mesh_cache_max_triangles", 350000 ) )
	BBS.Log( "prewarm: queued=%d completed=%d meshCPU=%.2f ms eligibilityCPU=%.2f ms enabled=%s baseIO=%.2f ms baseBuild=%.2f ms target=%.2f s hardSliceMax=%.2f ms",
		#BBS.MeshPrewarmQueue, BBS.MeshPrewarmStats.completed or 0,
		BBS.MeshPrewarmStats.meshMilliseconds or 0,
		BBS.MeshPrewarmStats.eligibilityMilliseconds or 0,
		tostring( GetBool( "bbs_mesh_prewarm" ) ),
		GetFloat( "bbs_mesh_cache_io_budget_ms", 10 ),
		GetFloat( "bbs_mesh_build_budget_ms", 15 ),
		GetFloat( "bbs_mesh_prepare_target_seconds", 2 ),
		GetFloat( "bbs_mesh_prepare_catchup_ms", 20 ) )
	local activeRTXReason = BBS.GetActiveRTXRuntimeReason
		and BBS.GetActiveRTXRuntimeReason() or nil
	local persistent = BBS.PersistentMeshStats or {}
	BBS.Log( "runtime profile: activeRTX=%s reason=%s rtxBackground=%.2f ms rtxUrgent=%.2f ms query=%.2f ms writerQueue=%d rtxSettle=%d/%d settleFrames=%d chunkGC=%d/%.2fms",
		tostring( activeRTXReason ~= nil ), tostring( activeRTXReason ),
		GetFloat( "bbs_mesh_rtx_background_budget_ms", 15 ),
		GetFloat( "bbs_mesh_rtx_catchup_ms", 25 ),
		GetFloat( "bbs_mesh_query_budget_ms", 10 ),
		#( BBS.PersistentMeshWriteQueue or {} ),
		persistent.rtxSettleCompleted or 0,
		persistent.rtxSettleQueued or 0,
		persistent.rtxSettleFrames or 0,
		persistent.rtxChunkGCSteps or 0,
		persistent.rtxChunkGCMilliseconds or 0 )
end, nil, "Print Procedural Bodygroup Destruction debug status." )

local function ApplyClientPreset( values, label )
	for name, value in pairs( values ) do
		RunConsoleCommand( name, tostring( value ) )
	end
	BBS.Log( "applied %s preset", label )
end

-- Budget-only profiles are shared by the Performance page and the complete
-- realtime reset below. Keep appearance, filters, cache enablement, and debug
-- instrumentation out of these tables so users can change processing speed
-- without changing what the addon does.
BBS.PerformanceBudgetPresets = {
	gentle = {
		bbs_mesh_cache_io_budget_ms = 5,
		bbs_mesh_build_budget_ms = 7.5,
		bbs_mesh_query_budget_ms = 5,
		bbs_damage_projection_budget_ms = 3.25,
		bbs_mesh_prepare_catchup_ms = 10,
		bbs_mesh_rtx_background_budget_ms = 7.5,
		bbs_mesh_rtx_catchup_ms = 12.5,
	},
	balanced = {
		-- This recommended/default profile is exactly 1.25x the former
		-- 0.19.11 Aggressive profile.
		bbs_mesh_cache_io_budget_ms = 10,
		bbs_mesh_build_budget_ms = 15,
		bbs_mesh_query_budget_ms = 10,
		bbs_damage_projection_budget_ms = 6.25,
		bbs_mesh_prepare_catchup_ms = 20,
		bbs_mesh_rtx_background_budget_ms = 15,
		bbs_mesh_rtx_catchup_ms = 25,
	},
	fast = {
		bbs_mesh_cache_io_budget_ms = 20,
		bbs_mesh_build_budget_ms = 30,
		bbs_mesh_query_budget_ms = 20,
		bbs_damage_projection_budget_ms = 12.5,
		bbs_mesh_prepare_catchup_ms = 40,
		bbs_mesh_rtx_background_budget_ms = 30,
		bbs_mesh_rtx_catchup_ms = 50,
	},
	aggressive = {
		bbs_mesh_cache_io_budget_ms = 40,
		bbs_mesh_build_budget_ms = 60,
		bbs_mesh_query_budget_ms = 40,
		bbs_damage_projection_budget_ms = 25,
		bbs_mesh_prepare_catchup_ms = 80,
		bbs_mesh_rtx_background_budget_ms = 60,
		bbs_mesh_rtx_catchup_ms = 100,
	},
}

local function ApplyPerformanceBudgetPreset( name )
	local values = BBS.PerformanceBudgetPresets[ name ]
	if not values then
		BBS.Log( "unknown performance preset: %s", tostring( name ) )
		return
	end
	ApplyClientPreset( values, name .. " performance" )
end

concommand.Add( "bbs_performance_gentle_preset", function()
	ApplyPerformanceBudgetPreset( "gentle" )
end, nil, "Use small per-frame CPU slices for the smoothest gameplay." )

concommand.Add( "bbs_performance_balanced_preset", function()
	ApplyPerformanceBudgetPreset( "balanced" )
end, nil, "Restore the recommended processing budgets." )

concommand.Add( "bbs_performance_fast_preset", function()
	ApplyPerformanceBudgetPreset( "fast" )
end, nil, "Use larger per-frame CPU slices for faster processing." )

concommand.Add( "bbs_performance_aggressive_preset", function()
	ApplyPerformanceBudgetPreset( "aggressive" )
end, nil, "Maximize processing throughput at the cost of possible frame spikes." )

concommand.Add( "bbs_realtime_preset", function()
	local values = {
		bbs_damage_enabled = 1,
		bbs_damage_apply_materials = 1,
		bbs_damage_layer_limit = 0,
		bbs_damage_force_nocull = 1,
		bbs_damage_rtx_direct_override = 1,
		bbs_debug_overlay = 0,
		bbs_debug_console = 0,
		bbs_debug_hud = 0,
		bbs_debug_labels = 0,
		bbs_hull_enabled = 0,
		bbs_damage_uv_preview = 0,
		bbs_damage_dump_debug = 0,
		bbs_damage_validate_copy = 0,
		bbs_damage_print_vmt = 0,
		bbs_damage_verbose_uv = 0,
		bbs_perf_enabled = 0,
		bbs_perf_hud = 0,
		bbs_perf_console = 0,
		bbs_hull_radius = 0.5,
		bbs_hull_inside_distance = 4,
		bbs_hull_outside_distance = 10,
		bbs_hole_damage_scaling = 1,
		bbs_hole_reference_damage = 5,
		bbs_hole_max_radius_multiplier = 5,
		bbs_hole_base_irregularity = 0.4,
		bbs_hole_damage_irregularity = 0.5,
		bbs_hole_max_irregularity = 0.9,
		bbs_damage_rt_size = 2048,
		bbs_damage_uv_expand_pixels = 1,
		bbs_damage_uv_feather_pixels = 0,
		bbs_damage_uv_blur_passes = 2,
		bbs_damage_uv_unwrap_seams = 1,
		bbs_damage_projection_depth = 4,
		bbs_damage_projection_tolerance = 0.04,
		bbs_damage_projection_max_triangles = 16384,
		bbs_mesh_prewarm = 1,
		bbs_mesh_prewarm_living = 1,
		bbs_mesh_disk_cache = 1,
		bbs_mesh_prepare_target_seconds = 2,
		bbs_mesh_cache_write_limit = 3,
		bbs_mesh_cache_max_entries = 6,
		bbs_mesh_cache_max_triangles = 350000,
		bbs_deferred_hit_limit = 4,
		bbs_mesh_restrict_to_hideable = 1,
		bbs_mesh_local_bounds = 1,
		bbs_mesh_force_full_scan = 0,
		bbs_damage_projection_local_bounds = 1,
		bbs_damage_coverage_rt_size = 1024,
		bbs_damage_batch_raster = 0,
		bbs_hit_coalesce = 1,
		bbs_hit_coalesce_window = 0.04,
		bbs_hit_coalesce_radius = 3,
		bbs_hit_coalesce_max_clusters = 4,
		bbs_hit_dispatch_per_frame = 1,
		bbs_hit_queue_limit = 32,
	}
	for name, value in pairs( BBS.PerformanceBudgetPresets.balanced ) do
		values[ name ] = value
	end
	ApplyClientPreset( values, "realtime" )
end, nil, "Disable heavy diagnostics and select realtime damage settings." )

concommand.Add( "bbs_debug_preset", function()
	ApplyClientPreset( {
		bbs_damage_layer_limit = 0,
		bbs_damage_force_nocull = 1,
		bbs_debug_overlay = 1,
		bbs_damage_rtx_direct_override = 1,
		bbs_debug_console = 1,
		bbs_debug_hud = 1,
		bbs_debug_labels = 1,
		bbs_hull_enabled = 1,
		bbs_damage_uv_preview = 0,
		bbs_damage_validate_copy = 0,
		bbs_damage_print_vmt = 0,
		bbs_damage_verbose_uv = 0,
		bbs_perf_enabled = 1,
		bbs_perf_hud = 1,
		bbs_perf_console = 1,
		bbs_damage_rt_size = 2048,
		bbs_damage_projection_depth = 5,
		bbs_damage_projection_tolerance = 0.03,
		bbs_damage_projection_max_triangles = 16384,
		bbs_mesh_prewarm = 1,
		bbs_mesh_prewarm_living = 1,
		bbs_mesh_disk_cache = 1,
		bbs_mesh_restrict_to_hideable = 1,
		bbs_mesh_local_bounds = 1,
		bbs_mesh_force_full_scan = 0,
		bbs_damage_projection_local_bounds = 1,
		bbs_damage_batch_raster = 0,
		bbs_hit_coalesce = 1,
		bbs_hit_coalesce_window = 0.04,
		bbs_hit_coalesce_radius = 3,
		bbs_hit_coalesce_max_clusters = 4,
		bbs_hit_dispatch_per_frame = 1,
		bbs_hit_queue_limit = 32,
	}, "visual debug" )
end, nil, "Enable visual diagnostics with stability-safe damage settings." )

concommand.Add( "bbs_mesh_cache_status", function()
	local entries, failedEntries, cachedVertices, cachedTriangles =
		BBS.GetModelMeshCacheSummary()
	local stats = BBS.ModelMeshCacheStats
	BBS.Log( "mesh cache: entries=%d failed=%d vertices=%d triangles=%d hits=%d misses=%d builds=%d failures=%d evictions=%d limits=%d entries/%d triangles",
		entries, failedEntries, cachedVertices, cachedTriangles,
		stats.hits or 0, stats.misses or 0, stats.builds or 0,
		stats.failures or 0, stats.evictions or 0,
		GetInt( "bbs_mesh_cache_max_entries", 6 ),
		GetInt( "bbs_mesh_cache_max_triangles", 350000 ) )
	for key, data in pairs( BBS.ModelMeshCache ) do
		if data == false then
			BBS.Log( "  FAILED %s", key )
		else
			BBS.Log( "  %d vertices / %d triangles / %d meshes / %.2f ms | %s",
				data.totalVertexCount, data.totalTriangleCount or 0,
				#data.meshes, data.buildMilliseconds, key )
		end
	end
end, nil, "Print the in-memory model mesh cache." )

concommand.Add( "bbs_mesh_cache_clear", function()
	BBS.ClearModelMeshCache()
	BBS.Log( "cleared the in-memory model mesh cache" )
end, nil, "Clear cached model mesh and bind-pose data." )

concommand.Add( "bbs_mesh_probe_last", function()
	local hit = BBS.LastHit
	if not hit or not hit.meshQuery then
		BBS.Log( "mesh probe unavailable: shoot or probe an enabled target first" )
		return
	end
	if hit.meshQuery.pending then
		BBS.Log( "mesh probe pending: wait for the HUD analysis indicator to finish" )
		return
	end

	BBS.Log( "--- last-hit removal-hull query probe ---" )
	PrintTable( hit.meshQuery.probe or {} )
	local cacheData = hit.meshQuery.cacheKey and BBS.ModelMeshCache[ hit.meshQuery.cacheKey ] or nil
	if not cacheData or cacheData == false then
		BBS.Log( "cached source structure unavailable for %s",
			tostring( hit.meshQuery.cacheKey ) )
		return
	end

	BBS.Log( "--- sampled ModelMeshData shape ---" )
	PrintTable( cacheData.probe.sampleMesh or {} )
	BBS.Log( "--- sampled MeshVertex ---" )
	PrintTable( cacheData.probe.sampleVertex or {} )
	BBS.Log( "--- sampled BoneBindPose at Lua key %s ---",
		tostring( cacheData.probe.sampleBindIndex ) )
	PrintTable( cacheData.probe.sampleBindPose or {} )
end, nil, "Dump sampled mesh, vertex, weight, bind-pose, bounds, and nearest-point data." )

concommand.Add( "bbs_debug_probe", function()
	local player = LocalPlayer()
	if not IsValid( player ) then return end

	local startPosition = player:GetShootPos()
	local direction = player:GetAimVector()
	local trace = util.TraceLine( {
		start = startPosition,
		endpos = startPosition + direction * 32768,
		mask = MASK_SHOT,
		filter = player,
	} )

	local targetEnabled, _, targetReason = BBS.IsDamageTargetEnabled( trace.Entity )
	if not targetEnabled then
		BBS.Log( "probe missed: aim at an enabled ragdoll, living player, or NPC (%s)",
			tostring( targetReason ) )
		return
	end

	BBS.ProcessEntityHit( 0, trace.Entity, trace.HitPos, direction, 0, player, true )
end, nil, "Create a local synthetic marker on an enabled model target." )
