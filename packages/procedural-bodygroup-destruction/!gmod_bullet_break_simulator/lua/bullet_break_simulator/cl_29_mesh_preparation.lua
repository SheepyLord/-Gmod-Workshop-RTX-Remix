-- Preparation policy shared by the producer and persistence hooks. Recording a
-- ready model must not double the latency of preparing a newly spawned one.
BBS = BBS or {}

function BBS.MeshPreparationHasPriority( job, now )
	if not job then return false end
	if job.urgent or job.pinnedContinuation or job.phase == "rtx_cleanup" then
		return true
	end
	local target = GetConVar( "bbs_mesh_prepare_target_seconds" )
	target = math.Clamp( target and target:GetFloat() or 2, 1, 15 )
	return ( now or SysTime() ) - ( job.preparationStartedAt or 0 ) < target
end

function BBS.MeshPreparationNeedsNativeCleanup( job )
	if not ( BBS.IsActiveRTXRuntime and BBS.IsActiveRTXRuntime() ) then return false end
	local data = job and job.meshData
	if not data then return false end
	-- A false marker certifies a graph with no outstanding native allocations.
	-- Older/hot-reloaded native producers have no marker: stay conservative.
	if data.rtxNativeGraphPending ~= nil then return data.rtxNativeGraphPending end
	return not data.persistentCache and not data.rtxCleanupCompleteAt
end

function BBS.StepMeshNativeCleanup( job, deadline )
	-- One tiny step per frame made two full GC boundaries take seconds despite
	-- most of the selected preparation budget sitting idle. Reuse that budget;
	-- never call a blocking full collection or remove the two-cycle safeguard.
	while ( job.rtxCleanupGCCycles or 0 ) < 2 do
		collectgarbage( "step", 256 )
		if not job.rtxCleanupGCProbe[ 1 ] then
			job.rtxCleanupGCCycles = ( job.rtxCleanupGCCycles or 0 ) + 1
			job.rtxCleanupGCProbe = job.rtxCleanupGCCycles < 2
				and setmetatable( { {} }, { __mode = "v" } ) or nil
		end
		if SysTime() >= deadline then break end
	end
end

function BBS.RecordMeshPreparationReady( job )
	if not job or not job.meshData then return end
	local wall = math.max( SysTime() - ( job.preparationStartedAt or SysTime() ), 0 ) * 1000
	local measured = ( job.meshCPUMilliseconds or 0 )
		+ ( job.diskHydrationMilliseconds or 0 )
		+ ( job.eligibilityCPUMilliseconds or 0 )
		+ ( job.rtxCleanupMilliseconds or 0 )
	local summary = {
		key = job.key, model = job.model,
		source = job.diskHydrationMilliseconds and "disk"
			or job.meshCPUMilliseconds and "native" or "memory",
		wallMilliseconds = wall, cpuMilliseconds = measured,
		nativeMilliseconds = job.nativeExtractionMilliseconds or 0,
		packMilliseconds = math.max( ( job.meshCPUMilliseconds or 0 )
			- ( job.nativeExtractionMilliseconds or 0 ), 0 ),
		hydrateMilliseconds = job.diskHydrationMilliseconds or 0,
		eligibilityMilliseconds = job.eligibilityCPUMilliseconds or 0,
		cleanupMilliseconds = job.rtxCleanupMilliseconds or 0,
		cleanupFrames = job.rtxCleanupFrames or 0,
		maximumSliceMilliseconds = math.max( job.meshMaximumSliceMilliseconds or 0,
			job.diskMaximumSliceMilliseconds or 0, job.eligibilityMaximumSliceMilliseconds or 0,
			job.rtxCleanupMaximumSliceMilliseconds or 0 ),
		triangles = job.meshData.totalTriangleCount or 0,
		withinTwoSeconds = wall <= 2000,
	}
	BBS.LastMeshPreparation = summary
	local stats = BBS.MeshPrewarmStats
	if stats then
		stats.readyWallMilliseconds = ( stats.readyWallMilliseconds or 0 ) + wall
		stats.readyUnderTwoSeconds = ( stats.readyUnderTwoSeconds or 0 )
			+ ( summary.withinTwoSeconds and 1 or 0 )
	end
	local logging = GetConVar( "bbs_debug_console" )
	if logging and logging:GetBool() then BBS.PrintMeshPreparationReport( summary ) end
end

function BBS.PrintMeshPreparationReport( summary )
	summary = summary or BBS.LastMeshPreparation
	if not summary then BBS.Log( "no model preparation has completed this session" ) return end
	BBS.Log( "model ready: %s source=%s triangles=%d wall=%.2f ms CPU=%.2f ms native=%.2f ms packing=%.2f ms hydrate=%.2f ms ownership=%.2f ms cleanup=%.2f ms/%d frames maxSlice=%.2f ms within2s=%s",
		tostring( summary.model ), summary.source, summary.triangles,
		summary.wallMilliseconds, summary.cpuMilliseconds, summary.nativeMilliseconds,
		summary.packMilliseconds, summary.hydrateMilliseconds, summary.eligibilityMilliseconds,
		summary.cleanupMilliseconds, summary.cleanupFrames, summary.maximumSliceMilliseconds,
		tostring( summary.withinTwoSeconds ) )
end

concommand.Add( "bbs_mesh_prewarm_report", function()
	local job = BBS.MeshPrewarmQueue and BBS.MeshPrewarmQueue[ 1 ]
	if job then
		BBS.Log( "model preparation pending: %s phase=%s age=%.2f s budget=%.2f ms/frame queued=%d",
			tostring( job.model ), tostring( job.phase ),
			math.max( SysTime() - ( job.preparationStartedAt or SysTime() ), 0 ),
			job.preparationBudgetMilliseconds or 0, #BBS.MeshPrewarmQueue )
	end
	BBS.PrintMeshPreparationReport()
end, nil, "Report last completed model preparation CPU, wall time and the two-second target." )
