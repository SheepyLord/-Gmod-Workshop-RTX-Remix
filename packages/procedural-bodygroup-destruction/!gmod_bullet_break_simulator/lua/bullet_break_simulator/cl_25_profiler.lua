-- Localized by the native-loader companion when bundled; standalone use keeps the English.
local bundle_i18n = CLIENT and file.Exists("nativeloader/i18n.lua", "LUA")
    and include("nativeloader/i18n.lua") or nil
local function NL(text)
    return bundle_i18n and bundle_i18n.A(text, BBS.I18N and BBS.I18N.language or "en") or text
end
local NP = bundle_i18n and bundle_i18n.P or function(text) return text end
local function NN(text) return text end
-- Opt-in per-stage client CPU profiler for the hit-to-material pipeline.

BBS = BBS or {}

local PERFORMANCE_FORMAT = 1
if BBS.PerformanceFormat ~= PERFORMANCE_FORMAT then
	BBS.PerformanceHistory = {}
	BBS.PerformanceBackground = {}
	BBS.LastPerformance = nil
	BBS.PerformanceFormat = PERFORMANCE_FORMAT
else
	BBS.PerformanceHistory = BBS.PerformanceHistory or {}
	BBS.PerformanceBackground = BBS.PerformanceBackground or {}
end

local function GetBool( name, fallback )
	local convar = GetConVar( name )
	return convar and convar:GetBool() or fallback
end

local function GetInt( name, fallback )
	local convar = GetConVar( name )
	return convar and convar:GetInt() or fallback
end

local function ProfilingEnabled()
	return GetBool( "bbs_perf_enabled", false )
end

local function SortedStages( stages )
	local sorted = {}
	for name, stage in pairs( stages or {} ) do
		sorted[ #sorted + 1 ] = {
			name = name,
			milliseconds = stage.milliseconds or 0,
			calls = stage.calls or 0,
		}
	end
	table.sort( sorted, function( left, right )
		if left.milliseconds ~= right.milliseconds then
			return left.milliseconds > right.milliseconds
		end
		return left.name < right.name
	end )
	return sorted
end

function BBS.PerfStartHit( hit )
	if not ProfilingEnabled() or not hit then return nil end
	if hit.performance and not hit.performance.finished then return hit.performance end
	local record = {
		kind = "hit",
		serial = hit.serial,
		entityIndex = hit.entityIndex,
		model = hit.model,
		startedAt = hit.pipelineStarted or SysTime(),
		stages = {},
		measuredMilliseconds = 0,
		finished = false,
	}
	hit.performance = record
	return record
end

function BBS.PerfBegin( hit )
	local record = hit and hit.performance
	if not ProfilingEnabled() or not record or record.finished then return nil end
	return SysTime()
end

function BBS.PerfAddMilliseconds( hit, name, milliseconds, calls )
	local record = hit and hit.performance
	if not ProfilingEnabled() or not record or record.finished then return 0 end
	milliseconds = math.max( tonumber( milliseconds ) or 0, 0 )
	if milliseconds ~= milliseconds then return 0 end
	name = tostring( name or "Unnamed stage" )
	local stage = record.stages[ name ]
	if not stage then
		stage = { milliseconds = 0, calls = 0 }
		record.stages[ name ] = stage
	end
	stage.milliseconds = stage.milliseconds + milliseconds
	stage.calls = stage.calls + math.max( tonumber( calls ) or 1, 1 )
	record.measuredMilliseconds = record.measuredMilliseconds + milliseconds
	return milliseconds
end

function BBS.PerfEnd( hit, name, startedAt )
	if not startedAt then return 0 end
	local milliseconds = math.max( ( SysTime() - startedAt ) * 1000, 0 )
	return BBS.PerfAddMilliseconds( hit, name, milliseconds )
end

function BBS.PerfAddBackground( name, milliseconds )
	if not ProfilingEnabled() then return end
	milliseconds = math.max( tonumber( milliseconds ) or 0, 0 )
	if milliseconds ~= milliseconds then return end
	local stage = BBS.PerformanceBackground[ name ]
	if not stage then
		stage = { milliseconds = 0, calls = 0, maximumMilliseconds = 0 }
		BBS.PerformanceBackground[ name ] = stage
	end
	stage.milliseconds = stage.milliseconds + milliseconds
	stage.calls = stage.calls + 1
	stage.maximumMilliseconds = math.max( stage.maximumMilliseconds, milliseconds )
end

function BBS.PerfBeginBackground()
	if not ProfilingEnabled() then return nil end
	return SysTime()
end

function BBS.PerfEndBackground( name, startedAt )
	if not startedAt then return 0 end
	local milliseconds = math.max( ( SysTime() - startedAt ) * 1000, 0 )
	BBS.PerfAddBackground( name, milliseconds )
	return milliseconds
end

local function AggregateHistory()
	local aggregate = { stages = {}, hitCount = #BBS.PerformanceHistory,
		measuredMilliseconds = 0, wallMilliseconds = 0 }
	for _, record in ipairs( BBS.PerformanceHistory ) do
		aggregate.measuredMilliseconds = aggregate.measuredMilliseconds
			+ ( record.measuredMilliseconds or 0 )
		aggregate.wallMilliseconds = aggregate.wallMilliseconds
			+ ( record.wallMilliseconds or 0 )
		for name, stage in pairs( record.stages or {} ) do
			local target = aggregate.stages[ name ]
			if not target then
				target = { milliseconds = 0, calls = 0, hits = 0 }
				aggregate.stages[ name ] = target
			end
			target.milliseconds = target.milliseconds + ( stage.milliseconds or 0 )
			target.calls = target.calls + ( stage.calls or 0 )
			target.hits = target.hits + 1
		end
	end
	aggregate.ranking = SortedStages( aggregate.stages )
	return aggregate
end

function BBS.GetPerformanceAggregate()
	return AggregateHistory()
end

local function PrintRecord( record )
	if not record then
		BBS.Log( "PERF: no completed profiled hit is available" )
		return
	end
	local hottest = record.ranking and record.ranking[ 1 ] or nil
	BBS.Log( "PERF hit #%s ent=%s status=%s measuredCPU=%.2f ms wall=%.2f ms stages=%d hottest=%s %.2f ms",
		tostring( record.serial ), tostring( record.entityIndex ), tostring( record.status ),
		record.measuredMilliseconds or 0, record.wallMilliseconds or 0,
		#( record.ranking or {} ), hottest and NL(hottest.name) or "<none>",
		hottest and hottest.milliseconds or 0 )
	for index, stage in ipairs( record.ranking or {} ) do
		local percentage = ( record.measuredMilliseconds or 0 ) > 0
			and stage.milliseconds / record.measuredMilliseconds * 100 or 0
		BBS.Log( "  %d. %s: %.2f ms (%.1f%%, %d call%s)", index, stage.name,
			stage.milliseconds, percentage, stage.calls, stage.calls == 1 and "" or "s" )
	end
	local unmeasured = math.max( ( record.wallMilliseconds or 0 )
		- ( record.measuredMilliseconds or 0 ), 0 )
	BBS.Log( "  asynchronous wait / unmeasured wall: %.2f ms", unmeasured )
	if ( record.meshCacheWaitMilliseconds or 0 ) > 0 then
		BBS.Log( "    model mesh cache preparation wait: %.2f ms",
			record.meshCacheWaitMilliseconds )
	end
end

local function PrintAggregate()
	local aggregate = AggregateHistory()
	BBS.Log( "PERF aggregate: %d hit(s), measuredCPU=%.2f ms wall=%.2f ms",
		aggregate.hitCount, aggregate.measuredMilliseconds, aggregate.wallMilliseconds )
	for index, stage in ipairs( aggregate.ranking ) do
		local percentage = aggregate.measuredMilliseconds > 0
			and stage.milliseconds / aggregate.measuredMilliseconds * 100 or 0
		local average = aggregate.hitCount > 0
			and stage.milliseconds / aggregate.hitCount or 0
		BBS.Log( "  %d. %s: total=%.2f ms avg/hit=%.2f ms (%.1f%%, %d calls)",
			index, stage.name, stage.milliseconds, average, percentage, stage.calls )
	end
	local background = SortedStages( BBS.PerformanceBackground )
	if #background > 0 then
		BBS.Log( "PERF background work since clear:" )
		for index, stage in ipairs( background ) do
			local source = BBS.PerformanceBackground[ stage.name ] or {}
			BBS.Log( "  %d. %s: total=%.2f ms calls=%d max=%.2f ms",
				index, stage.name, stage.milliseconds, stage.calls,
				source.maximumMilliseconds or 0 )
		end
	end
end

function BBS.PerfFinish( hit, status )
	local record = hit and hit.performance
	if not record or record.finished then return record end
	record.finished = true
	record.status = status or ( hit.damageUV and hit.damageUV.status )
		or ( hit.meshQuery and hit.meshQuery.status ) or "complete"
	record.wallMilliseconds = math.max( ( SysTime() - record.startedAt ) * 1000, 0 )
	record.meshCacheWaitMilliseconds = hit.meshCacheWaitMilliseconds or 0
	record.ranking = SortedStages( record.stages )
	record.finishedAt = SysTime()
	BBS.LastPerformance = record
	BBS.PerformanceHistory[ #BBS.PerformanceHistory + 1 ] = record
	local maximum = math.Clamp( GetInt( "bbs_perf_history", 32 ), 1, 256 )
	while #BBS.PerformanceHistory > maximum do table.remove( BBS.PerformanceHistory, 1 ) end
	if GetBool( "bbs_perf_console", false ) then PrintRecord( record ) end
	return record
end

hook.Add( "HUDPaint", "BBS.DrawPerformanceHUD", function()
	if not ProfilingEnabled() or not GetBool( "bbs_perf_hud", false ) then return end
	local record = BBS.LastPerformance
	if not record then return end
	local limit = math.Clamp( GetInt( "bbs_perf_stage_limit", 8 ), 1, 16 )
	local visible = math.min( #( record.ranking or {} ), limit )
	local width = 520
	local height = 61 + visible * 18 + 40
	local x, y = 20, 20
	draw.RoundedBox( 6, x, y, width, height, Color( 10, 12, 16, 225 ) )
	draw.SimpleText( NL("Procedural Bodygroup Destruction — performance"), "DermaDefaultBold",
		x + 10, y + 8, Color( 255, 175, 75 ), TEXT_ALIGN_LEFT, TEXT_ALIGN_TOP )
	draw.SimpleText( string.format( NL("hit #%s | CPU %.2f ms | wall %.2f ms | %s"),
		tostring( record.serial ), record.measuredMilliseconds or 0,
		record.wallMilliseconds or 0, tostring( record.status ) ), "DermaDefault",
		x + 10, y + 28, Color( 225, 230, 238 ), TEXT_ALIGN_LEFT, TEXT_ALIGN_TOP )
	for index = 1, visible do
		local stage = record.ranking[ index ]
		local percentage = ( record.measuredMilliseconds or 0 ) > 0
			and stage.milliseconds / record.measuredMilliseconds * 100 or 0
		draw.SimpleText( string.format( "%d. %s", index, NL(stage.name) ), "DermaDefault",
			x + 10, y + 50 + ( index - 1 ) * 18,
			index == 1 and Color( 255, 205, 90 ) or Color( 205, 215, 228 ),
			TEXT_ALIGN_LEFT, TEXT_ALIGN_TOP )
		draw.SimpleText( string.format( "%.2f ms  %.1f%%", stage.milliseconds, percentage ),
			"DermaDefaultBold", x + width - 10, y + 50 + ( index - 1 ) * 18,
			index == 1 and Color( 255, 205, 90 ) or Color( 120, 225, 245 ),
			TEXT_ALIGN_RIGHT, TEXT_ALIGN_TOP )
	end
	local aggregate = AggregateHistory()
	local hottest = aggregate.ranking[ 1 ]
	draw.SimpleText( string.format( NL("Recent hits: %d%s | slowest stage overall: %s"),
		aggregate.hitCount, "",
		hottest and NL(hottest.name) or NL("<none>") ), "DermaDefault",
		x + 10, y + height - 38, Color( 160, 175, 195 ), TEXT_ALIGN_LEFT, TEXT_ALIGN_TOP )
	local background = SortedStages( BBS.PerformanceBackground )
	local backgroundHottest = background[ 1 ]
	local backgroundSource = backgroundHottest
		and BBS.PerformanceBackground[ backgroundHottest.name ] or nil
	draw.SimpleText( string.format( NL("continuous hottest: %s%s"),
		backgroundHottest and NL(backgroundHottest.name) or NL("<none>"),
		backgroundSource and string.format( NL(" (avg %.3f ms, max %.3f ms)"),
			backgroundSource.milliseconds / math.max( backgroundSource.calls, 1 ),
			backgroundSource.maximumMilliseconds or 0 ) or "" ), "DermaDefault",
		x + 10, y + height - 20, Color( 160, 175, 195 ), TEXT_ALIGN_LEFT, TEXT_ALIGN_TOP )
end )

concommand.Add( "bbs_perf_status", function()
	BBS.Log( "PERF profiler enabled=%s HUD=%s console=%s history=%d/%d",
		tostring( ProfilingEnabled() ), tostring( GetBool( "bbs_perf_hud", false ) ),
		tostring( GetBool( "bbs_perf_console", false ) ), #BBS.PerformanceHistory,
		math.Clamp( GetInt( "bbs_perf_history", 32 ), 1, 256 ) )
	PrintRecord( BBS.LastPerformance )
	PrintAggregate()
	BBS.Log( "PERF note: render stages measure client-thread submission/blocking time, not asynchronous GPU execution." )
end, nil, "Print the last and rolling Procedural Bodygroup Destruction performance reports." )

concommand.Add( "bbs_perf_clear", function()
	BBS.PerformanceHistory = {}
	BBS.PerformanceBackground = {}
	BBS.LastPerformance = nil
	BBS.Log( "cleared Procedural Bodygroup Destruction performance history" )
end, nil, "Clear Procedural Bodygroup Destruction performance history." )

local stageLabels = { NN("Affected UV selection"), NN("Bodygroup eligibility"), NN("Debug capture + bundle I/O"), NN("Debug console output"), NN("Frame: 3D hit overlay"), NN("Frame: last-hit HUD"), NN("Frame: texture inspector"), NN("Impact trace + hit setup"), NN("Material apply overhead"), NN("Material queue dispatch"), NN("Mesh cache lookup/build"), NN("Pose snapshot"), NN("Prewarm: RTX memory cleanup"), NN("Prewarm: bodygroup eligibility"), NN("Prewarm: mesh cache"), NN("Prewarm: persistent cache hydrate"), NN("Removal-hull mesh query"), NN("Skin transform setup"), NN("UV result bookkeeping") }
