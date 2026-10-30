--[[---------------------------------------------------------------------------
	Advanced Material Editor - client transport for generated edit PNGs
-----------------------------------------------------------------------------]]

AdvMat        = AdvMat or {}
AdvMat.Assets = AdvMat.Assets or {}
AdvMat.Assets.Remote = AdvMat.Assets.Remote or {}

local A   = AdvMat.Assets
local GEN = AdvMat.Gen

A.Requesting   = A.Requesting   or {}
A.Uploaded     = A.Uploaded     or {}
A.Uploading    = A.Uploading    or {}
A.Installed    = A.Installed    or {}
A.Ensuring     = A.Ensuring     or {}
A.Receive      = A.Receive      or {}
A.UploadQueue  = A.UploadQueue  or {}
A.RequestQueue = A.RequestQueue or {}
A.RequestQueued = A.RequestQueued or {}
A.RequestRetries = A.RequestRetries or {}
A.RequestActive = A.RequestActive or nil

local UPLOAD_PUMP = "AdvMat.AssetUploadPump"
local UPLOAD_INTERVAL = 0.35
local TRANSFER_SECONDS_PER_MESSAGE = 0.35
local REQUEST_START_TIMEOUT = math.max( A.BUFFER_TTL + 60, 900 )
local ENSURE_START_TIMEOUT = math.max( A.BUFFER_TTL + 60, 900 )

local function EnsureDir( target )
	local folder = string.GetPathFromFilename( target or "" )
	local run
	for _, part in ipairs( string.Explode( "/", string.TrimRight( folder, "/" ) ) ) do
		if part ~= "" then
			run = run and ( run .. "/" .. part ) or part
			if not file.IsDir( run, "DATA" ) then file.CreateDir( run ) end
		end
	end
end

local function RequestTimer( target )
	return "AdvMat.AssetRequest." .. util.CRC( target )
end

local function EnsureTimer( target )
	return "AdvMat.AssetEnsure." .. util.CRC( target )
end

local function UploadTimer( target )
	return "AdvMat.AssetUpload." .. util.CRC( target )
end

local function TransferTimeout( total )
	total = math.max( 1, math.floor( tonumber( total ) or 1 ) )
	-- A transfer is deliberately paced at one reliable message per 350 ms.
	-- Keep substantial scheduling/head-of-line slack for a busy listen server,
	-- and refresh this deadline whenever real progress is made.
	return math.max( A.BUFFER_TTL + 60,
		( total + 1 ) * TRANSFER_SECONDS_PER_MESSAGE + 120 )
end

local function UploadMessagesAhead()
	local messages = 0
	for _, job in ipairs( A.UploadQueue ) do
		if A.Uploading[ job.target ] == job.pending then
			if job.index == 0 then messages = messages + job.total + 1
			else messages = messages + math.max( 0, job.total - job.index + 1 ) end
		end
	end
	return messages
end

local function UploadQueueTimeout( total )
	return math.max( ENSURE_START_TIMEOUT,
		( UploadMessagesAhead() + total + 1 ) * TRANSFER_SECONDS_PER_MESSAGE + 120 )
end

--- An edit whose source is an image imported on another computer, which only
--- the server's copy can show here (see AwaitServerCopy).
local function ServerOnly( recipe )
	local Import = AdvMat.Import
	return istable( recipe ) and Import ~= nil and Import.IsSource( recipe.src )
		and not Import.Has( recipe.src )
end

-- GEN.RequestLocal turns an imported image away to AwaitServerCopy, which
-- marks it remote again: there is nothing here to rebuild it from.
local function QueueLocal( recipe )
	AdvMat.Assets.Remote[ GEN.FileName( recipe ) ] = nil
	if isfunction( GEN.RequestLocal ) then GEN.RequestLocal( recipe )
	else GEN.Request( recipe ) end
end

local PumpRequest

local function RemoveRequestJobs( target )
	A.RequestQueued[ target ] = nil
	for index = #A.RequestQueue, 1, -1 do
		if A.RequestQueue[ index ].target == target then
			table.remove( A.RequestQueue, index )
		end
	end
end

local function FinishRequest( target, installed )
	local pending = A.Requesting[ target ]
	if not pending then return end
	local wasActive = A.RequestActive == target
	A.Requesting[ target ] = nil
	A.RequestRetries[ target ] = nil
	RemoveRequestJobs( target )
	timer.Remove( RequestTimer( target ) )
	if wasActive then A.RequestActive = nil end
	if not installed then
		AdvMat.Assets.Remote[ target ] = nil

		-- Whoever waits for an imported image - a Save, typically - hears now
		-- rather than at the end of its timeout. QueueLocal then ends up asking
		-- the server again later, since there is nothing here to rebuild it from.
		if ServerOnly( pending ) then
			hook.Run( "AdvMatGenerationFailed", pending, target,
				AdvMat.L( "import.error_server" ) )
		end

		QueueLocal( pending )
	else
		A.ImportWaits[ target ] = nil
	end
	if wasActive and PumpRequest then PumpRequest() end
end

local function RetryRequest( target )
	local pending = A.Requesting[ target ]
	if not pending then return end
	local wasActive = A.RequestActive == target
	if wasActive then A.RequestActive = nil end
	timer.Remove( RequestTimer( target ) )
	RemoveRequestJobs( target )
	local attempt = math.min( 6, ( A.RequestRetries[ target ] or 0 ) + 1 )
	A.RequestRetries[ target ] = attempt
	local delay = math.min( 15, 0.75 * ( 2 ^ ( attempt - 1 ) ) )
	A.RequestQueued[ target ] = true
	timer.Create( RequestTimer( target ), delay, 1, function()
		if A.Requesting[ target ] ~= pending or not AdvMat.Assets.Remote[ target ] then return end
		A.RequestQueue[ #A.RequestQueue + 1 ] = { target = target, recipe = pending }
		PumpRequest()
	end )
	if wasActive and PumpRequest then PumpRequest() end
end

local function ScheduleRequestFallback( target, delay )
	timer.Create( RequestTimer( target ), delay or REQUEST_START_TIMEOUT, 1, function()
		-- Queued requests have no timer. Only the single request actually sent to
		-- the server may fall back and release the next item in the queue.
		if A.RequestActive ~= target then return end
		FinishRequest( target, false )
	end )
end

local FinishUploading
local resettingServerSession = false

---------------------------------------------------------------------------
-- Images imported on another computer
---------------------------------------------------------------------------
-- Every other edit can fall back to being rebuilt here from its recipe. An
-- imported image cannot: its source is a file on the importing player's
-- computer (cl_61_import.lua), so the server's copy of the finished texture is
-- the only way this client will ever show it. Falling back would be worse than
-- nothing - the build can only fail, and clearing the server mark on the way
-- would drop a request still queued for it, leaving this player on the old
-- texture for the rest of the session while everybody else sees the import.

-- [target] = how often the server has been asked, for the back-off.
A.ImportWaits = A.ImportWaits or {}

--- Ask the server for an imported image's finished texture: within a second
--- the first time, then after a pause that grows each time it could not send
--- it, up to five minutes. The wait counts as a request in flight, so
--- GEN.GetMaterial does not ask again in between.
---
--- Always through a timer, never inline: a listen server can answer a request
--- inside SendToServer, and a refusal would then ask again from inside itself.
function AdvMat.Assets.AwaitServerCopy( recipe )
	if resettingServerSession then return false end

	local clean, target = A.CleanRecipe( recipe )
	if not clean then return false end

	if A.Requesting[ target ] then
		AdvMat.Assets.Remote[ target ] = AdvMat.Assets.Remote[ target ] or A.Requesting[ target ]
		return true
	end

	AdvMat.Assets.Remote[ target ] = clean

	local attempt = ( A.ImportWaits[ target ] or 0 ) + 1
	A.ImportWaits[ target ] = attempt
	if attempt == 1 then
		AdvMat.Log( "%s is an image imported on another computer; asking the server for it.", target )
	end

	A.Requesting[ target ] = clean
	A.RequestQueued[ target ] = true
	timer.Create( RequestTimer( target ), math.min( 300, 4 ^ ( attempt - 1 ) ), 1, function()
		if A.Requesting[ target ] ~= clean or not AdvMat.Assets.Remote[ target ] then return end
		A.RequestQueue[ #A.RequestQueue + 1 ] = { target = target, recipe = clean }
		PumpRequest()
	end )

	return true
end

local function TouchUpload( target, pending, delay )
	timer.Create( UploadTimer( target ), delay or pending.transferTimeout, 1, function()
		FinishUploading( target, false,
			"server did not acknowledge the generated edit upload" )
	end )
end

local function RemoveUploadJobs( target )
	for index = #A.UploadQueue, 1, -1 do
		if A.UploadQueue[ index ].target == target then
			table.remove( A.UploadQueue, index )
		end
	end
	if #A.UploadQueue == 0 then timer.Remove( UPLOAD_PUMP ) end
end

local function PriorityUploadIndex()
	-- A Begin already reserves a buffer on the server. Never pre-empt one of
	-- those transfers: a large PNG can otherwise sit without chunks until that
	-- buffer expires, after which all of its remaining chunks are discarded.
	-- Priority only changes the order of jobs which have not sent Begin yet.
	local afterStarted = 1
	for index, job in ipairs( A.UploadQueue ) do
		if ( tonumber( job.index ) or 0 ) > 0 then afterStarted = index + 1 end
	end
	return afterStarted
end

local function PromoteUploadJob( target )
	local found
	for index, job in ipairs( A.UploadQueue ) do
		if job.target == target then
			-- A started job keeps its place until its final chunk or ACK.
			if ( tonumber( job.index ) or 0 ) > 0 then return end
			found = table.remove( A.UploadQueue, index )
			break
		end
	end
	if found then table.insert( A.UploadQueue, PriorityUploadIndex(), found ) end
end

local function PumpUpload()
	while #A.UploadQueue > 0 do
		local job = A.UploadQueue[ 1 ]
		if A.Uploading[ job.target ] ~= job.pending then
			table.remove( A.UploadQueue, 1 )
		else
			if job.index == 0 then
				-- Move all state forward before SendToServer. Listen servers can run
				-- the server handler and AssetAck/Reject synchronously inside this call.
				job.index = 1
				job.pending.started = true
				TouchUpload( job.target, job.pending )
				net.Start( "AdvMat.AssetBegin" )
					AdvMat.Net.WriteTable( job.meta )
				net.SendToServer()
				return
			end

			local index = job.index
			local chunk = string.sub( job.png,
				( index - 1 ) * A.CHUNK_SIZE + 1, index * A.CHUNK_SIZE )
			job.index = index + 1
			TouchUpload( job.target, job.pending )
			if index >= job.total and A.UploadQueue[ 1 ] == job then
				table.remove( A.UploadQueue, 1 )
			end
			net.Start( "AdvMat.AssetChunk" )
				net.WriteString( job.target )
				net.WriteUInt( index, 16 )
				net.WriteUInt( job.total, 16 )
				net.WriteUInt( #chunk, 17 )
				if #chunk > 0 then net.WriteData( chunk, #chunk ) end
				net.SendToServer()
			return
		end
	end
	timer.Remove( UPLOAD_PUMP )
end

local uploadPumpActive = false

local function RunUploadPump()
	if uploadPumpActive then return end
	uploadPumpActive = true
	local job = A.UploadQueue[ 1 ]
	local ok, err = pcall( PumpUpload )
	uploadPumpActive = false
	if not ok then
		local reason = "generated edit upload transport failed: " .. tostring( err )
		AdvMat.Log( "%s", reason )
		-- Fail only the job which was executing. The repeating pump remains alive
		-- for later queued work, and the guard was released before callbacks run.
		if job and A.Uploading[ job.target ] == job.pending then
			FinishUploading( job.target, false, reason )
		end
	end
end

local function StartUploadPump()
	if timer.Exists and timer.Exists( UPLOAD_PUMP ) then return end
	-- Metadata is tiny and may be enough for a listen server to prove that its
	-- shared DATA file is already the exact authored PNG. Send that first message
	-- now so this common case does not pay even one pacing interval. If bytes are
	-- actually needed, every 30 kB fragment still goes through the conservative
	-- 350 ms pump (below 90 kB/s, leaving room for ordinary reliable traffic).
	-- An AssetAck can run synchronously on a listen server. Do not recurse into
	-- PumpUpload from its callback and burst every queued Begin in one call;
	-- the server quite reasonably rate-limits that. The next item is instead
	-- picked up by the normal paced timer.
	-- Install the paced continuation first. If the immediate Begin itself raises,
	-- FinishUploading can remove the bad job without recursively draining every
	-- item behind it before this call has even returned.
	timer.Create( UPLOAD_PUMP, UPLOAD_INTERVAL, 0, RunUploadPump )
	if not uploadPumpActive then RunUploadPump() end
	if #A.UploadQueue == 0 then timer.Remove( UPLOAD_PUMP ) end
end

FinishUploading = function( target, ok, reason )
	local pending = A.Uploading[ target ]
	if not pending then return end
	A.Uploading[ target ] = nil
	timer.Remove( UploadTimer( target ) )
	RemoveUploadJobs( target )
	if ok then
		A.Uploaded[ target ] = pending.digest
		A.Installed[ target ] = pending.digest
	else
		A.Uploaded[ target ] = nil
	end
	for _, done in ipairs( pending.callbacks ) do
		local called, callErr = pcall( done, ok, reason )
		if not called then AdvMat.Log( "Generated edit upload callback failed: %s", tostring( callErr ) ) end
	end
	if #A.UploadQueue > 0 then StartUploadPump() end
end

function AdvMat.Assets.PublishBuilt( recipe, target, png, done, priority )
	if resettingServerSession then
		local reason = "server session changed"
		if done then done( false, reason ) end
		return false, reason
	end
	local meta, reason = A.MakeMeta( recipe, png )
	if not meta then return false, reason end
	local safe
	safe, reason = A.MetaWireSafe( meta )
	if not safe then return false, reason end
	if target and target ~= meta.target then
		reason = "generated edit target changed"
		return false, reason
	end
	if A.Uploaded[ meta.target ] == meta.digest then
		if done then done( true ) end
		return true
	end

	local pending = A.Uploading[ meta.target ]
	if pending then
		if pending.digest ~= meta.digest then
			reason = "a different generated edit is already uploading for this recipe"
			return false, reason
		end
		if done then pending.callbacks[ #pending.callbacks + 1 ] = done end
		if priority then PromoteUploadJob( meta.target ) end
		return nil
	end
	local total = math.max( 1, math.ceil( #png / A.CHUNK_SIZE ) )
	pending = {
		digest = meta.digest, callbacks = {}, total = total,
		transferTimeout = TransferTimeout( total ),
	}
	if done then pending.callbacks[ 1 ] = done end
	A.Uploading[ meta.target ] = pending
	timer.Create( UploadTimer( meta.target ), UploadQueueTimeout( total ), 1, function()
		FinishUploading( meta.target, false,
			"generated edit upload did not start in time" )
	end )
	local job = {
		target = meta.target, meta = meta, png = png, total = total,
		index = 0, pending = pending,
	}
	if priority and #A.UploadQueue > 0 then
		table.insert( A.UploadQueue, PriorityUploadIndex(), job )
	else A.UploadQueue[ #A.UploadQueue + 1 ] = job end
	StartUploadPump()
	-- Success is reported only by AssetAck after server validation, persistence
	-- and readback. `nil` means the asynchronous upload is in flight.
	return nil
end

local function FinishEnsuring( target, ok, reason )
	local waiting = A.Ensuring[ target ]
	if not waiting then return end
	A.Ensuring[ target ] = nil
	timer.Remove( EnsureTimer( target ) )
	hook.Remove( "AdvMatGenerated", waiting.hookID )
	hook.Remove( "AdvMatGenerationFailed", waiting.hookID )
	for _, done in ipairs( waiting.callbacks ) do
		local called, callErr = pcall( done, ok, reason )
		if not called then AdvMat.Log( "Generated edit preparation callback failed: %s", tostring( callErr ) ) end
	end
end

function A.EnsureUploaded( recipe, done, priority )
	if resettingServerSession then
		local reason = "server session changed"
		if done then done( false, reason ) end
		return false, reason
	end
	local clean, target = A.CleanRecipe( recipe )
	if not clean then
		if done then done( false, target ) end
		return false
	end

	local png = file.Read( target, "DATA" )
	if png then
		local ok, reason = AdvMat.Assets.PublishBuilt( clean, target, png, done, priority )
		if ok ~= false then return ok end
		-- A stale/truncated cache cannot be allowed to make GetMaterial skip the
		-- exact rebuild which the save is now waiting for.
		file.Delete( target )
		GEN.Cache[ target ] = nil
		AdvMat.Log( "Discarded invalid generated edit %s: %s", target, tostring( reason ) )
	end

	local waiting = A.Ensuring[ target ]
	if waiting then
		waiting.callbacks[ #waiting.callbacks + 1 ] = done or function() end
		waiting.priority = waiting.priority or priority == true
		return nil
	end

	local hookID = "AdvMat.AssetEnsure." .. target
	waiting = {
		recipe = clean, callbacks = { done or function() end }, hookID = hookID,
		priority = priority == true,
	}
	A.Ensuring[ target ] = waiting

	hook.Add( "AdvMatGenerated", hookID, function( producedRecipe, produced )
		if produced ~= target then return end
		local bytes = file.Read( target, "DATA" )
		if not bytes then
			FinishEnsuring( target, false, "generated edit output is missing" )
			return
		end
		local total = math.max( 1, math.ceil( #bytes / A.CHUNK_SIZE ) )
		timer.Create( EnsureTimer( target ), UploadQueueTimeout( total ) + 60, 1, function()
			FinishEnsuring( target, false, "generated edit upload timed out" )
		end )
		local ok, reason = AdvMat.Assets.PublishBuilt( producedRecipe or clean, target, bytes,
			function( accepted, rejectedReason )
				FinishEnsuring( target, accepted, rejectedReason )
			end, waiting.priority )
		if ok == false then
			FinishEnsuring( target, false, reason or "generated edit output is missing" )
		end
	end )
	hook.Add( "AdvMatGenerationFailed", hookID, function( _, produced, reason )
		if produced == target then FinishEnsuring( target, false, reason or "generation failed" ) end
	end )
	timer.Create( EnsureTimer( target ), ENSURE_START_TIMEOUT, 1, function()
		FinishEnsuring( target, false, "generated edit timed out" )
	end )
	QueueLocal( clean )
	return nil
end

--- Start the exact-asset preflight as soon as the user adopts an edited
--- texture. Saving remains strictly ACK-gated; this merely overlaps generation
--- and a dedicated-server upload with the time spent back in the material
--- editor. A later save joins the same Ensure/Upload entry instead of sending a
--- duplicate transfer.
---
--- `done( ok, why )`, optional, hears how the background upload ended.
function AdvMat.Assets.StageEdit( recipe, done )
	local clean, reason = A.CleanRecipe( recipe )
	if not clean then return false, reason end
	return A.EnsureUploaded( clean, function( ok, why )
		if not ok then
			AdvMat.Log( "Background generated edit upload failed: %s",
				tostring( why or "upload failed" ) )
		end
		if done then done( ok, why ) end
	end )
end

--- Whether a value contains an edited texture whose exact bytes this server
--- has not acknowledged yet. Used for honest immediate Save feedback without
--- exposing the transport's mutable bookkeeping to the editor UI.
function AdvMat.Assets.NeedsUpload( value )
	for target in pairs( A.EditRecipes( value ) ) do
		if not A.Uploaded[ target ] then return true end
	end
	return false
end

function A.PrepareValue( value, done )
	local recipes = A.EditRecipes( value )
	local list = {}
	for _, recipe in pairs( recipes ) do list[ #list + 1 ] = recipe end
	table.sort( list, function( left, right )
		return GEN.FileName( left ) < GEN.FileName( right )
	end )
	if #list == 0 then
		if done then done( true ) end
		return true
	end

	local index, finished = 0, false
	local function OneDone( ok, reason )
		if finished then return end
		if not ok then
			finished = true
			if done then done( false, reason ) end
			return
		end
		index = index + 1
		local recipe = list[ index ]
		if not recipe then
			finished = true
			if done then done( true ) end
			return
		end
		-- Explicit Save work jumps ahead of speculative pre-staging from a
		-- previously adopted edit. Already-started transfers remain resumable and
		-- each target still emits at most one fragment per pacing tick.
		A.EnsureUploaded( recipe, OneDone, true )
	end
	OneDone( true )
	return nil
end

function AdvMat.Assets.PrepareRule( rule, done )
	local safe, reason = A.WireTableSafe( rule, A.MAX_META_BYTES, "material override" )
	if not safe then
		if done then done( false, reason ) end
		return false, reason
	end
	return A.PrepareValue( istable( rule ) and rule.gen or nil, done )
end

function AdvMat.Assets.PrepareProfile( profile, done )
	return A.PrepareValue( profile, done )
end

--- Single player, or the host of a listen server: the server keeps its edits
--- in this client's own DATA folder (see the listen-host shortcut in
--- sv_29_assets.lua). The same test as LocalHost in cl_61_import.lua.
local function SharesServerData()
	if game and isfunction( game.SinglePlayer ) and game.SinglePlayer() then return true end

	local ply = LocalPlayer()
	return IsValid( ply ) and isfunction( ply.IsListenServerHost )
		and ply:IsListenServerHost() or false
end

function A.MarkRemote( recipe )
	local clean, target = A.CleanRecipe( recipe )
	if not clean then return false end
	-- A snapshot/profile can reference the same edit many times. Once it is
	-- queued or active, do not repeatedly read and CRC a multi-megabyte PNG.
	if AdvMat.Assets.Remote[ target ] then return true end
	if A.Installed[ target ] and file.Exists( target, "DATA" ) then return false end
	if A.Installed[ target ] then A.Installed[ target ] = nil end
	local png = file.Read( target, "DATA" )
	local info = png and A.ValidatePNG( clean, png ) or nil
	if png and not info then
		file.Delete( target )
		GEN.Cache[ target ] = nil
	end
	-- An asset proactively installed by this server already is authoritative.
	-- Any other disk/cache hit may belong to an older server or a degraded
	-- legacy build, so the remote rule still requests the server copy first.
	if info and A.Installed[ target ] == info.digest then return false end
	-- Where this client shares the server's DATA folder, though, this file is
	-- the server's copy. Asking for it would only send the same bytes back,
	-- 30 kB every 0.35 s and one edit at a time.
	if info and SharesServerData() then
		A.Installed[ target ] = info.digest
		return false
	end
	AdvMat.Assets.Remote[ target ] = clean
	return true
end

function AdvMat.Assets.MarkRemoteValue( value )
	local recipes = A.EditRecipes( value )
	for _, recipe in pairs( recipes ) do A.MarkRemote( recipe ) end
end

PumpRequest = function()
	if A.RequestActive and A.Requesting[ A.RequestActive ] then return end
	A.RequestActive = nil

	while #A.RequestQueue > 0 do
		local job = table.remove( A.RequestQueue, 1 )
		A.RequestQueued[ job.target ] = nil
		if A.Requesting[ job.target ] == job.recipe
			and AdvMat.Assets.Remote[ job.target ] then
			A.RequestActive = job.target
			-- Requests intentionally carry only the canonical cache target. Sending
			-- the complete edit recipe can exceed GMod's 64 KiB net-message limit;
			-- the server already indexed the verified upload by this safe target.
			-- Arm the watchdog before sending: a listen server may answer with Miss
			-- synchronously and immediately advance the queue.
			ScheduleRequestFallback( job.target, REQUEST_START_TIMEOUT )
			net.Start( "AdvMat.AssetRequest" )
				net.WriteString( job.target )
			net.SendToServer()
			return
		end
		if A.Requesting[ job.target ] == job.recipe then
			A.Requesting[ job.target ] = nil
		end
	end
end

function AdvMat.Assets.RequestMarked( recipe )
	local clean, target = A.CleanRecipe( recipe )
	if not clean or not AdvMat.Assets.Remote[ target ] then return false end
	if A.Requesting[ target ] then return true end
	if not isstring( target ) or #target > 160
		or not string.match( target, "^advmat/edits/tex_[%w_%-]+%.png$" ) then
		AdvMat.Assets.Remote[ target ] = nil
		QueueLocal( clean )
		return true
	end

	A.Requesting[ target ] = clean
	A.RequestQueued[ target ] = true
	A.RequestQueue[ #A.RequestQueue + 1 ] = { target = target, recipe = clean }
	PumpRequest()
	return true
end

local function Install( meta, png )
	local info, reason = A.ValidatePNG( meta.recipe, png, meta.digest )
	if not info then return nil, reason end
	EnsureDir( info.target )
	file.Write( info.target, png )
	if file.Read( info.target, "DATA" ) ~= png then
		return nil, "could not store the multiplayer generated edit"
	end

	GEN.Cache[ info.target ] = nil
	GEN.Failed[ info.target ] = nil
	GEN.Told[ info.target ] = nil
	A.Installed[ info.target ] = info.digest
	AdvMat.Assets.Remote[ info.target ] = nil
	FinishRequest( info.target, true )
	for index = #GEN.Queue, 1, -1 do
		if GEN.FileName( GEN.Queue[ index ] ) == info.target then table.remove( GEN.Queue, index ) end
	end
	-- Populate the material cache before notifying apply/RTX consumers.
	GEN.GetMaterial( info.recipe )
	hook.Run( "AdvMatGenerated", info.recipe, info.target )
	return info
end

local function PurgeReceive()
	local now = RealTime()
	for target, buffer in pairs( A.Receive ) do
		if not istable( buffer ) or ( buffer.expires or 0 ) <= now then A.Receive[ target ] = nil end
	end
end

local function FailReceive( target, reason )
	A.Receive[ target ] = nil
	if A.Requesting[ target ] then FinishRequest( target, false ) end
	if reason then
		AdvMat.Log( "Ignored generated edit asset: %s", tostring( reason ) )
	end
end

timer.Create( "AdvMat.AssetReceivePurge", 5, 0, PurgeReceive )

net.Receive( "AdvMat.AssetBegin", function()
	local raw = AdvMat.Net.ReadTable()
	local wireSafe, reason = A.MetaWireSafe( raw )
	if not wireSafe then
		AdvMat.Log( "Ignored generated edit transfer: %s", tostring( reason ) )
		return
	end
	-- Asset requests are target-only. Reattach the canonical recipe retained
	-- for the queued/active request before validating the server's compact
	-- response metadata.
	if istable( raw ) and not istable( raw.recipe ) and isstring( raw.target ) then
		raw.recipe = A.Requesting[ raw.target ] or AdvMat.Assets.Remote[ raw.target ]
	end
	local meta
	meta, reason = A.ValidateMeta( raw )
	if not meta then
		AdvMat.Log( "Ignored generated edit transfer: %s", tostring( reason ) )
		if istable( raw ) and isstring( raw.target ) and A.Requesting[ raw.target ] then
			FinishRequest( raw.target, false )
		end
		return
	end
	A.Receive[ meta.target ] = {
		meta = meta, parts = {}, bytes = 0, expires = RealTime() + A.BUFFER_TTL,
	}
	-- The short timer only covers a server that never answers. Once a valid
	-- transfer begins, allow a large image to make steady progress.
	if A.RequestActive == meta.target then
		local total = math.max( 1, math.ceil( meta.size / A.CHUNK_SIZE ) )
		ScheduleRequestFallback( meta.target, TransferTimeout( total ) )
	end
end )

net.Receive( "AdvMat.AssetAck", function()
	local target = net.ReadString()
	local digest = net.ReadString()
	local pending = A.Uploading[ target ]
	if not pending or digest ~= pending.digest then return end
	FinishUploading( target, true )
end )

net.Receive( "AdvMat.AssetChunk", function()
	local target = net.ReadString()
	local index  = net.ReadUInt( 16 )
	local total  = net.ReadUInt( 16 )
	local length = net.ReadUInt( 17 )
	local left = net.BytesLeft and net.BytesLeft()
	local maxChunks = math.ceil( A.MaxBytes() / A.CHUNK_SIZE )
	if not isstring( target ) or #target > 160 or total < 1 or total > maxChunks
		or index < 1 or index > total or length > A.CHUNK_SIZE
		or ( left and length > left ) then return end
	local chunk = length > 0 and net.ReadData( length ) or ""
	local buffer = A.Receive[ target ]
	if not buffer or buffer.expires <= RealTime() then return end
	buffer.expires = RealTime() + A.BUFFER_TTL
	local expectedTotal = math.max( 1, math.ceil( buffer.meta.size / A.CHUNK_SIZE ) )
	if A.RequestActive == target then
		ScheduleRequestFallback( target, TransferTimeout( expectedTotal ) )
	end
	if total ~= expectedTotal or index ~= #buffer.parts + 1 then
		FailReceive( target, "generated edit fragments are inconsistent" )
		return
	end
	buffer.parts[ index ] = chunk
	buffer.bytes = buffer.bytes + #chunk
	if buffer.bytes > buffer.meta.size then
		FailReceive( target, "generated edit transfer exceeded its declared size" )
		return
	end
	if index < total then return end
	A.Receive[ target ] = nil
	local png = table.concat( buffer.parts )
	if #png ~= buffer.meta.size then
		FailReceive( target, "generated edit length does not match" )
		return
	end
	local _, reason = Install( buffer.meta, png )
	if reason then FailReceive( target, reason ) end
end )

net.Receive( "AdvMat.AssetReject", function()
	local target = net.ReadString()
	local reason = net.ReadString()
	local upload = A.Uploading[ target ]
	if upload then
		FinishUploading( target, false, reason )
	elseif A.Requesting[ target ] then
		-- Compatibility with a server that rejects a target request on the old
		-- shared failure channel. Release the active slot before rebuilding.
		FinishRequest( target, false )
	elseif target ~= "" then
		AdvMat.Log( "Generated edit upload was rejected: %s", tostring( reason ) )
	end
end )

net.Receive( "AdvMat.AssetMiss", function()
	local target = net.ReadString()
	local reason = net.ReadString()
	local pending = A.Requesting[ target ]
	if not pending then
		if target ~= "" then
			AdvMat.Log( "Generated edit was unavailable: %s", tostring( reason ) )
		end
		return
	end
	FinishRequest( target, false )
end )

net.Receive( "AdvMat.AssetBusy", function()
	local target = net.ReadString()
	local reason = net.ReadString()
	if A.Requesting[ target ] then
		RetryRequest( target )
	elseif target ~= "" then
		AdvMat.Log( "Generated edit transfer is busy: %s", tostring( reason ) )
	end
end )

hook.Add( "InitPostEntity", "AdvMat.AssetServerSession", function()
	-- A client can reconnect to a different server without reloading Lua. The
	-- new server must receive assets even when their bytes match an old upload.
	-- Reject re-entrant work started by a failure callback until every old hook,
	-- timer and table has been detached; otherwise the final table reset can
	-- orphan that new work with a Begin already on the wire.
	resettingServerSession = true
	for target in pairs( A.Requesting ) do timer.Remove( RequestTimer( target ) ) end
	local uploads = {}
	for target in pairs( A.Uploading ) do uploads[ #uploads + 1 ] = target end
	for _, target in ipairs( uploads ) do
		FinishUploading( target, false, "server session changed" )
	end
	-- An Ensure can still be waiting for local generation and therefore have no
	-- Uploading entry for FinishUploading to unwind.  Leaving those hooks alive
	-- lets a result from the old session call a stale Save callback after the
	-- reconnect, and its long watchdog timer survives as well.
	local ensuring = {}
	for target in pairs( A.Ensuring ) do ensuring[ #ensuring + 1 ] = target end
	for _, target in ipairs( ensuring ) do
		FinishEnsuring( target, false, "server session changed" )
	end
	timer.Remove( UPLOAD_PUMP )
	A.Uploaded, A.Uploading, A.Installed = {}, {}, {}
	A.Ensuring = {}
	AdvMat.Assets.Remote, A.Requesting, A.Receive = {}, {}, {}
	A.UploadQueue, A.RequestQueue, A.RequestQueued, A.RequestRetries = {}, {}, {}, {}
	A.ImportWaits = {}
	A.RequestActive = nil
	resettingServerSession = false
end )
