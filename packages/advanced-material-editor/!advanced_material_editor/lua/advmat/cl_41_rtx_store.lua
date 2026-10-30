--[[---------------------------------------------------------------------------
	Advanced Material Editor - isolated RTX profile mirror (client)

	The mirror is intentionally unrelated to AdvMat.Client: RTX profiles never
	enter the VMT rule resolver and never cause SetSubMaterial.  A capable client
	announces protocol support, receives only RTX profiles, and hands them to the
	client bridge when RTX mode is active. Local saves overlay this server mirror
	while their assets and version-checked updates synchronize in the background.
-----------------------------------------------------------------------------]]

AdvMat          = AdvMat or {}
AdvMat.RTXStore = AdvMat.RTXStore or {}

local Store  = AdvMat.RTXStore
local Bridge = AdvMat.RTX and AdvMat.RTX.Bridge

-- Protocol 3 requires the current Lua/native session-reset contract.  Older
-- protocol-2 development clients retained cleanup tombstones indefinitely and
-- must not opt into the bounded post-broadcast lifecycle used by this store.
Store.PROTOCOL      = 3
Store.Profiles      = Store.Profiles or {}
Store.HashOwners    = Store.HashOwners or {}
Store.MaterialIndex = Store.MaterialIndex or {}
Store.ProfileETags  = Store.ProfileETags or {}
Store.CleanupPending = Store.CleanupPending or {}
Store.CleanupResults = Store.CleanupResults or {}
Store.PendingAck    = Store.PendingAck or {}
Store.PendingSave   = Store.PendingSave or {}
Store.PendingClear  = Store.PendingClear or {}
-- Locally saved work is separate from the server mirror/version tokens. It
-- survives window closure while uploads run, but never crosses connections.
Store.LocalSaves    = Store.LocalSaves or {}
Store.InFlightSave  = Store.InFlightSave or {}
Store.AppliedETags  = Store.AppliedETags or {}
Store.Revision      = tonumber( Store.Revision ) or 0
Store.Nonce         = tonumber( Store.Nonce ) or 0
Store.ModeAnnounced = Store.ModeAnnounced == true

local NET = {
	HELLO      = "AdvMat.RTX.Hello",
	SYNC_BEGIN = "AdvMat.RTX.SyncBegin",
	PROFILE    = "AdvMat.RTX.Profile",
	SYNC_END   = "AdvMat.RTX.SyncEnd",
	SAVE       = "AdvMat.RTX.Save",
	CLEAR      = "AdvMat.RTX.Clear",
	ACK        = "AdvMat.RTX.Ack",
	NOTIFY     = "AdvMat.RTX.Notify",
}

local SAVE_DEBOUNCE  = 0.15
local CLEAR_DEBOUNCE = 0.10
-- RTX profiles can occupy eighteen 30 KiB fragments.  The reliable net
-- channel must be fed gradually: one large burst can overflow a peer's
-- per-client buffer even though every individual message is legal.
local ACK_TIMEOUT    = 300
local CHUNK_SIZE      = 30000
local SEND_INTERVAL   = 0.35
local SEND_TIMER      = "AdvMat.RTX.OutboundPump"
local MAX_PROFILE_JSON = 512 * 1024
local MAX_COMPRESSED  = 512 * 1024
local MAX_UNCOMPRESSED = 640 * 1024
local MAX_CHUNKS      = math.ceil( MAX_COMPRESSED / CHUNK_SIZE )
local MAX_PENDING_TRANSFERS = 32
local MAX_PENDING_BYTES = 4 * 1024 * 1024
local BUFFER_TTL = 45
-- The server suppresses duplicate HELLO snapshots for two seconds. Recovery
-- must wait beyond that window, and both the request and fragment phases need
-- watchdogs so one dropped SYNC_END cannot leave writes disabled forever.
local SYNC_RETRY_DELAY = 2.25
local SYNC_RESPONSE_TIMEOUT = 60
local SYNC_TRANSFER_TIMEOUT = 45
local SYNC_RETRY_TIMER = "AdvMat.RTX.SyncRetry"
local SYNC_RESPONSE_TIMER = "AdvMat.RTX.SyncResponseTimeout"
local SYNC_TRANSFER_TIMER = "AdvMat.RTX.SyncTransferTimeout"

local syncing, stagedProfiles, stagedETags, stagedTombstones, profilesBeforeSync = false, nil, nil, nil, nil
local profileBuffers = {}
local SendSave

local function ProfileBufferTotals()
	local count, bytes = 0, 0
	for _, buffer in pairs( profileBuffers ) do
		count = count + 1
		bytes = bytes + ( tonumber( buffer.bytes ) or 0 )
	end
	return count, bytes
end

local function PurgeProfileBuffers()
	local now = RealTime()
	for transfer, buffer in pairs( profileBuffers ) do
		if not istable( buffer ) or ( tonumber( buffer.expires ) or 0 ) <= now then
			profileBuffers[ transfer ] = nil
			timer.Remove( "AdvMat.RTX.Profile." .. util.CRC( transfer ) )
		end
	end
	for key, completed in pairs( Store.CleanupResults ) do
		if not istable( completed ) or ( tonumber( completed.expires ) or 0 ) <= now then
			Store.CleanupResults[ key ] = nil
		end
	end
end

timer.Create( "AdvMat.RTX.PurgeProfileBuffers", 5, 0, PurgeProfileBuffers )

local function Copy( value )
	return istable( value ) and table.Copy( value ) or value
end

local function Callback( fn, ... )
	if not isfunction( fn ) then return end
	local ok, err = pcall( fn, ... )
	if not ok then AdvMat.Log( "RTX store callback failed: %s", tostring( err ) ) end
end

local function ErrorText( value )
	if istable( value ) then return table.concat( value, "; " ) end
	return tostring( value or "unknown error" )
end

local function MaterialName( value )
	if istable( value ) then
		value = value.target and value.target.material or value.material
	end
	return AdvMat.NormalizeMaterial( value or "" )
end

local function TargetHashes( profile )
	local target = istable( profile ) and profile.target or {}
	local source = target.hashes or ( target.hash and { target.hash } ) or {}
	local hashes, seen = {}, {}
	for _, hash in ipairs( source ) do
		if isstring( hash ) and not seen[ hash ] then
			seen[ hash ] = true
			hashes[ #hashes + 1 ] = hash
		end
	end
	table.sort( hashes )
	return hashes
end

local function ProfileKey( profile )
	local hashes = TargetHashes( profile )
	if #hashes > 0 then return "rtx:hash:" .. string.sub( hashes[ 1 ], 3 ) end
	local material = MaterialName( profile )
	return material ~= "" and ( "rtx:pending:" .. material ) or nil
end

local function LocalSaveFor( value )
	if next( Store.LocalSaves ) == nil then return nil end
	local material = MaterialName( value )
	if Store.LocalSaves[ material ] then return Store.LocalSaves[ material ] end
	local hashes = istable( value ) and TargetHashes( value )
		or ( Bridge and Bridge.ResolveHashes and Bridge.ResolveHashes( material ) ) or {}
	local wanted = {}
	for _, hash in ipairs( hashes ) do wanted[ hash ] = true end
	for _, queued in pairs( Store.LocalSaves ) do
		for _, hash in ipairs( TargetHashes( queued.profile ) ) do
			if wanted[ hash ] then return queued end
		end
	end
end

function Store.GetSyncState( material )
	local queued = LocalSaveFor( material )
	return queued and queued.syncStatus or "synced", queued and queued.syncError or nil
end

local function RebuildIndexes( profiles )
	Store.HashOwners, Store.MaterialIndex = {}, {}
	for id, profile in pairs( profiles or {} ) do
		local material = MaterialName( profile )
		if material ~= "" and not Store.MaterialIndex[ material ] then
			Store.MaterialIndex[ material ] = id
		end
		for _, hash in ipairs( TargetHashes( profile ) ) do
			if not Store.HashOwners[ hash ] then Store.HashOwners[ hash ] = id end
		end
	end
end

RebuildIndexes( Store.Profiles )

local function SanitizeProfile( raw )
	local schema = AdvMat.RTXSchema
	if not istable( schema ) or not isfunction( schema.SanitizeProfile ) then
		return nil, "RTX profile schema is unavailable"
	end
	local ok, clean, errors = pcall( schema.SanitizeProfile, raw )
	if not ok then return nil, tostring( clean ) end
	if not clean then return nil, ErrorText( errors ) end
	if not clean.target or MaterialName( clean ) == "" then return nil, "target.material is required" end
	-- A structurally valid graph may still be impossible to lower (for example,
	-- two texture inputs multiplied together or more bake operations than the
	-- native protocol supports).  Do not mirror/send a profile that every
	-- compatible writer must reject after the server has accepted it.
	if isfunction( schema.Compile ) then
		local compiledOK, compiled, compileErrors = pcall( schema.Compile, clean )
		if not compiledOK then return nil, tostring( compiled ) end
		if not compiled then return nil, ErrorText( compileErrors ) end
	end
	return clean
end

local function EditorSessionMode( editor )
	if not IsValid( editor ) then return nil end
	local session = editor.AdvMatBackendSession or editor.BackendSession
	if not istable( session ) or session.closed then return nil end
	if session.mode == "rtx" or session.mode == "vanilla" then return session.mode end
end

local function FrozenSessionMode()
	-- AdvMat.Editor is the canonical active window.  RTXEditor is retained as a
	-- compatibility alias, but must not override a real vanilla host.
	return EditorSessionMode( AdvMat.Editor ) or EditorSessionMode( AdvMat.RTXEditor )
end

local function RTXModeActive()
	-- Any open editor follows its frozen session even if the convar changes.
	-- Background sync follows actual Remix capability, not UI preference, so a
	-- forced-vanilla choice remains a hard boundary for all RTX application.
	local frozen = FrozenSessionMode()
	if frozen then return frozen == "rtx" end
	return AdvMat.Backend and AdvMat.Backend.Current
		and AdvMat.Backend.Current() == "rtx"
end

local function ApplyProfile( profile )
	if not RTXModeActive() or not Bridge or not Bridge.Commit then return end
	-- Snapshot/broadcast echoes must not replace a newer local Save while its
	-- texture upload or acknowledgement is still in flight (or failed).
	if LocalSaveFor( profile ) then return end
	-- A material-keyed pending draft is useful for editor lookup/export, but it
	-- owns no global Remix identity and must never be applied automatically.
	if #TargetHashes( profile ) == 0 then return end
	local id = ProfileKey( profile )
	local etag = id and Store.ProfileETags[ id ]
	if etag and Store.AppliedETags[ id ] == etag then return end
	Bridge.Commit( profile, function( ok, result )
		if ok and etag and Store.ProfileETags[ id ] == etag then Store.AppliedETags[ id ] = etag end
		if ok or not istable( result ) or result.status == "exported"
			or result.status == "superseded" then return end
		AdvMat.Log( "RTX material %s was not applied: %s", MaterialName( profile ),
			tostring( result.error or result.status ) )
	end )
end

local function ApplySnapshotProfiles( profiles )
	Store.ApplyGeneration = ( tonumber( Store.ApplyGeneration ) or 0 ) + 1
	local generation = Store.ApplyGeneration
	local queue = {}
	for id, profile in SortedPairs( profiles or {} ) do
		queue[ #queue + 1 ] = { id = id, profile = profile }
	end
	timer.Remove( "AdvMat.RTX.ApplySnapshot" )
	if #queue == 0 then return end

	local index = 0
	-- Native map import and USDA publication are synchronous.  Feed only one
	-- profile per tick so a large server snapshot cannot schedule hundreds of
	-- writer calls for the same frame.
	timer.Create( "AdvMat.RTX.ApplySnapshot", 0.05, 0, function()
		if Store.ApplyGeneration ~= generation then
			timer.Remove( "AdvMat.RTX.ApplySnapshot" )
			return
		end
		index = index + 1
		local entry = queue[ index ]
		if not entry then
			timer.Remove( "AdvMat.RTX.ApplySnapshot" )
			return
		end
		-- Ignore a superseded snapshot entry if a live broadcast replaced it
		-- while this reconciliation queue was draining.
		if Store.Profiles[ entry.id ] == entry.profile then ApplyProfile( entry.profile ) end
	end )
end

local function HashSet( hashes )
	local set = {}
	for _, hash in ipairs( hashes or {} ) do set[ hash ] = true end
	return set
end

local function CleanupTimerName( id )
	return "AdvMat.RTX.Cleanup." .. util.CRC( id )
end

local function CleanupKey( profile )
	return MaterialName( profile ) .. "|" .. table.concat( TargetHashes( profile ), "," )
end

local function CompleteCleanupListeners( cleanup, ok, result )
	local listeners = cleanup.listeners or {}
	cleanup.listeners = {}
	for _, listener in ipairs( listeners ) do Callback( listener, ok, result ) end
end

local AttemptCleanup
local function ScheduleCleanup( cleanup )
	cleanup.attempts = ( cleanup.attempts or 0 ) + 1
	local delay = math.min( 60, math.max( 2, 2 ^ math.min( cleanup.attempts, 5 ) ) )
	timer.Create( CleanupTimerName( cleanup.id ), delay, 1, function()
		if Store.CleanupPending[ cleanup.id ] == cleanup then AttemptCleanup( cleanup ) end
	end )
end

AttemptCleanup = function( cleanup )
	if not cleanup or cleanup.inFlight then return end
	if syncing then
		ScheduleCleanup( cleanup )
		return
	end
	if not RTXModeActive() or not Bridge then
		ScheduleCleanup( cleanup )
		return
	end
	-- Retired server hashes may still be in use by a pending local save. Keep
	-- the cleanup queued until that save is confirmed or explicitly removed.
	if LocalSaveFor( cleanup.profile ) then
		ScheduleCleanup( cleanup )
		return
	end
	local restore = Bridge.RestoreTarget or Bridge.Restore
	if not isfunction( restore ) then
		ScheduleCleanup( cleanup )
		return
	end

	cleanup.inFlight = true
	local argument = Bridge.RestoreTarget and cleanup.profile.target or MaterialName( cleanup.profile )
	local accepted, immediate = restore( argument, function( ok, result )
		cleanup.inFlight = false
		cleanup.lastResult = istable( result ) and Copy( result ) or { status = ok and "restored" or "failed" }
		cleanup.lastResult.cleanupComplete = ok == true
		cleanup.lastResult.nativeCleaned = cleanup.lastResult.exportOnly ~= true and ok == true
		if ok then
			Store.CleanupResults[ CleanupKey( cleanup.profile ) ] = {
				result = Copy( cleanup.lastResult ), expires = RealTime() + 30,
			}
			Store.CleanupPending[ cleanup.id ] = nil
			timer.Remove( CleanupTimerName( cleanup.id ) )
			CompleteCleanupListeners( cleanup, true, cleanup.lastResult )
		else
			CompleteCleanupListeners( cleanup, false, cleanup.lastResult )
			ScheduleCleanup( cleanup )
		end
	end )
	if accepted == false and not cleanup.inFlight
		and Store.CleanupPending[ cleanup.id ] == cleanup then ScheduleCleanup( cleanup ) end
	return accepted, immediate
end

local function QueueCleanup( id, profile, listener )
	local clean = SanitizeProfile( profile )
	if not clean then return nil end
	local profileID = ProfileKey( clean )
	if profileID then Store.AppliedETags[ profileID ] = nil end
	if #TargetHashes( clean ) == 0 then
		local caps = Bridge and Bridge.Capabilities and Bridge.Capabilities() or {}
		if caps.exportOnly ~= true then
			local result = {
				status = "no-native-state", live = false,
				cleanupComplete = true, nativeCleaned = false,
			}
			Callback( listener, true, result )
			return nil, result
		end
	end
	local completed = Store.CleanupResults[ CleanupKey( clean ) ]
	if completed and completed.expires > RealTime() then
		Callback( listener, true, Copy( completed.result ) )
		return nil, completed.result
	end
	if completed then Store.CleanupResults[ CleanupKey( clean ) ] = nil end
	for _, existing in pairs( Store.CleanupPending ) do
		if CleanupKey( existing.profile ) == CleanupKey( clean ) then
			if isfunction( listener ) then existing.listeners[ #existing.listeners + 1 ] = listener end
			AttemptCleanup( existing )
			return existing
		end
	end
	local cleanup = Store.CleanupPending[ id ]
	if not cleanup then
		cleanup = { id = id, profile = clean, attempts = 0, listeners = {} }
		Store.CleanupPending[ id ] = cleanup
	else
		cleanup.profile = clean
	end
	if isfunction( listener ) then cleanup.listeners[ #cleanup.listeners + 1 ] = listener end
	AttemptCleanup( cleanup )
	return cleanup
end

-- A newly active profile owns these hashes intentionally.  Any older cleanup
-- instruction for the same identities must be narrowed/cancelled before its
-- retry can erase the replacement just committed.
local function ReconcileCleanupWithProfile( profile )
	local claimed = HashSet( TargetHashes( profile ) )
	for id, cleanup in pairs( Store.CleanupPending ) do
		local original = TargetHashes( cleanup.profile )
		if #original > 0 then
			local remaining = {}
			for _, hash in ipairs( original ) do
				if not claimed[ hash ] then remaining[ #remaining + 1 ] = hash end
			end
			if #remaining == 0 then
				Store.CleanupPending[ id ] = nil
				timer.Remove( CleanupTimerName( id ) )
				CompleteCleanupListeners( cleanup, true, {
					status = "reclaimed", live = true,
					cleanupComplete = true, nativeCleaned = false,
				} )
			elseif #remaining ~= #original then
				cleanup.profile = Copy( cleanup.profile )
				cleanup.profile.target = Copy( cleanup.profile.target )
				cleanup.profile.target.hash = remaining[ 1 ]
				cleanup.profile.target.hashes = remaining
			end
		end
	end
end

local function SetLocal( profile, suppliedID, suppliedETag )
	local clean, reason = SanitizeProfile( profile )
	if not clean then return nil, reason end
	local id = ProfileKey( clean )
	if not id then return nil, "invalid target material" end
	if suppliedID and suppliedID ~= id then return nil, "profile identity does not match its captured hashes" end
	if not isstring( suppliedETag ) or suppliedETag == "" or #suppliedETag > 64 then
		return nil, "profile version token is missing or invalid"
	end
	ReconcileCleanupWithProfile( clean )
	local previous = Store.MaterialIndex[ MaterialName( clean ) ]
	if previous and previous ~= id then
		Store.Profiles[ previous ] = nil
		Store.ProfileETags[ previous ] = nil
	end
	Store.Profiles[ id ] = clean
	Store.ProfileETags[ id ] = suppliedETag
	RebuildIndexes( Store.Profiles )
	return clean, id
end

local function RemoveLocal( id, material )
	local previous = Store.Profiles[ id ]
	Store.Profiles[ id ] = nil
	Store.ProfileETags[ id ] = nil
	Store.AppliedETags[ id ] = nil
	RebuildIndexes( Store.Profiles )
	return MaterialName( previous ) ~= "" and MaterialName( previous ) or MaterialName( material )
end

function Store.Get( material )
	local localSave = LocalSaveFor( material )
	if localSave then return Copy( localSave.profile ) end
	material = MaterialName( material )
	local id = Store.MaterialIndex[ material ]
	if not id and Bridge and Bridge.ResolveHashes then
		for _, hash in ipairs( Bridge.ResolveHashes( material ) ) do
			id = Store.HashOwners[ hash ]
			if id then break end
		end
	end
	local profile = id and Store.Profiles[ id ] or nil
	return Copy( profile )
end

local function PublishSyncState( queued )
	hook.Run( "AdvMatRTXLocalSyncChanged", queued.material, queued.syncStatus, queued.syncError )
end

local function FinishSave( queued, ok, result )
	if queued.completed then return end
	queued.completed = true
	if Store.InFlightSave[ queued.material ] == queued then Store.InFlightSave[ queued.material ] = nil end
	queued.syncStatus = ok and "synced" or "failed"
	queued.syncError = not ok and result and result.error or nil
	local latest = Store.LocalSaves[ queued.material ] == queued
	if latest then
		if ok and queued.localFinished then
			Store.LocalSaves[ queued.material ] = nil
			if queued.localApplied and result.id then Store.AppliedETags[ result.id ] = result.etag end
		end
		if result.status ~= "superseded" then PublishSyncState( queued ) end
		if not ok and result.status ~= "superseded" and result.status ~= "cancelled" then
			local text = AdvMat.L( "rtx.background_failed", {
				material = queued.material, reason = tostring( queued.syncError or result.status ),
			} )
			if AdvMat.NotifyLocal then AdvMat.NotifyLocal( text, NOTIFY_ERROR, 8 ) end
		end
	end
	Callback( queued.callback, ok, result )
	local nextSave = Store.PendingSave[ queued.material ]
	if nextSave and nextSave.predecessor == queued then
		if ok then
			nextSave.expectedID, nextSave.expectedETag = result.id, result.etag
			nextSave.predecessor = nil
			timer.Create( "AdvMat.RTX.Save." .. util.CRC( queued.material ), SAVE_DEBOUNCE, 1,
				function() SendSave( nextSave ) end )
		else
			Store.PendingSave[ queued.material ] = nil
			FinishSave( nextSave, false, {
				status = result.status, error = result.error, material = queued.material, persisted = false,
			} )
		end
	end
end

local function CommitLocalSave( queued )
	queued.applyAttempt = ( queued.applyAttempt or 0 ) + 1
	local attempt = queued.applyAttempt
	queued.localFinished, queued.localApplied = false, false
	Bridge.Commit( queued.profile, function( applied, detail )
		if attempt ~= queued.applyAttempt then return end
		if Store.LocalSaves[ queued.material ] ~= queued then
			if not queued.localNotified then
				queued.localNotified = true
				Callback( queued.localCallback, false, { status = "superseded" } )
			end
			return
		end
		queued.localFinished = true
		queued.localApplied = applied == true
		local result = Copy( detail or {} )
		result.profile = Copy( queued.profile )
		result.material = queued.material
		result.localSaved, result.persisted = true, queued.syncStatus == "synced"
		result.nativeApplied = applied == true and result.status ~= "exported"
		result.pendingHash = result.status == "waiting-for-hash"
		if not applied and not result.pendingHash then result.applyError = result.error or result.status end
		result.id, result.etag = Store.GetVersion( queued.material )
		queued.localResult = Copy( result )
		if queued.syncStatus == "synced" then
			Store.LocalSaves[ queued.material ] = nil
			if applied and result.id then Store.AppliedETags[ result.id ] = result.etag end
		end
		-- Validation and the retained local recipe are independent of whether a
		-- native writer is installed or its DDS import succeeds on this client.
		if not queued.localNotified then
			queued.localNotified = true
			Callback( queued.localCallback, true, result )
		end
	end )
end

function Store.GetID( material )
	material = MaterialName( material )
	if material == "" then return nil end
	local id = Store.MaterialIndex[ material ]
	if id then return id end
	if Bridge and Bridge.ResolveHashes then
		for _, hash in ipairs( Bridge.ResolveHashes( material ) ) do
			if Store.HashOwners[ hash ] then return Store.HashOwners[ hash ] end
		end
	end
	return nil
end

function Store.GetVersion( material )
	local id = Store.GetID( material )
	return id, id and Store.ProfileETags[ id ] or nil
end

function Store.IsSynced()
	return Store.Synced == true and not syncing
end

function Store.Preview( profile, callback )
	local clean, reason = SanitizeProfile( profile )
	if not clean then
		Callback( callback, false, { status = "failed", error = reason, live = false } )
		return false, reason
	end
	if not RTXModeActive() then
		local result = { status = "inactive", error = "RTX backend is not active", live = false }
		Callback( callback, false, result )
		return false, result.error
	end
	return Bridge.Preview( clean, callback )
end

function Store.Restore( material, callback )
	-- The native preview extension owns rollback and retains the latest saved
	-- baseline, even if a server update arrived while this editor was open.
	local caps = Bridge.Capabilities and Bridge.Capabilities() or {}
	if caps.livePreview and Bridge.RestorePreview then
		return Bridge.RestorePreview( material, callback )
	end
	local saved = Store.Get( material )
	if saved and #TargetHashes( saved ) > 0 then return Bridge.Commit( saved, callback ) end
	if saved then
		local result = { status = "waiting-for-hash", live = false,
			error = "saved RTX draft has no captured hash identity" }
		Callback( callback, false, result )
		return false, result
	end
	if Bridge.RestoreTarget and Bridge.ResolveHashes then
		return Bridge.RestoreTarget( {
			material = MaterialName( material ), hashes = Bridge.ResolveHashes( material ),
		}, callback )
	end
	return Bridge.Restore( material, callback )
end

local function NextNonce( operation, material )
	Store.Nonce = Store.Nonce + 1
	return operation .. ":" .. util.CRC( material ) .. ":" .. tostring( Store.Nonce )
end

local function ArmAckTimeout( nonce, pending )
	local timerName = "AdvMat.RTX.Ack." .. util.CRC( nonce )
	timer.Create( timerName, ACK_TIMEOUT, 1, function()
		if Store.PendingAck[ nonce ] ~= pending then return end
		Store.PendingAck[ nonce ] = nil
		Callback( pending.callback, false, {
			status = "timeout", operation = pending.operation, material = pending.material,
			error = "server did not acknowledge the RTX profile change",
		} )
	end )
end

local function RegisterAck( nonce, operation, material, callback, profile )
	local pending = {
		operation = operation, material = material, callback = callback,
		profile = Copy( profile ),
	}
	Store.PendingAck[ nonce ] = pending
	ArmAckTimeout( nonce, pending )
	return pending
end

-- SAVE fragments and CLEAR operations share one ordered client queue.  This
-- keeps a later clear/save from overtaking an earlier fragmented save while
-- limiting reliable-channel traffic to one <=30 KiB message every tick.
local outbound = { first = 1, last = 0, items = {} }
local outboundPumpRunning = false
local EnsureOutboundPump

local function PushOutbound( job )
	outbound.last = outbound.last + 1
	outbound.items[ outbound.last ] = job
	EnsureOutboundPump()
end

local function PeekOutbound()
	return outbound.items[ outbound.first ]
end

local function PopOutbound()
	outbound.items[ outbound.first ] = nil
	outbound.first = outbound.first + 1
	if outbound.first > outbound.last then
		outbound.first, outbound.last, outbound.items = 1, 0, {}
	end
end

local function ResetOutbound( reason )
	reason = tostring( reason or "RTX connection changed before the operation completed" )
	-- Detach local work before completing callbacks; old uploads/ACKs cannot
	-- reapply it after the native provider resets for a new server or mode.
	Store.LocalSaves, Store.InFlightSave, Store.AppliedETags = {}, {}, {}
	outbound = { first = 1, last = 0, items = {} }
	outboundPumpRunning = false
	timer.Remove( SEND_TIMER )

	for nonce, pending in pairs( Store.PendingAck ) do
		Store.PendingAck[ nonce ] = nil
		timer.Remove( "AdvMat.RTX.Ack." .. util.CRC( nonce ) )
		Callback( pending.callback, false, {
			status = "cancelled", operation = pending.operation,
			material = pending.material, persisted = false, error = reason,
		} )
	end
	for material, queued in pairs( Store.PendingSave ) do
		Store.PendingSave[ material ] = nil
		timer.Remove( "AdvMat.RTX.Save." .. util.CRC( material ) )
		Callback( queued.callback, false, {
			status = "cancelled", operation = "save", material = material,
			persisted = false, error = reason,
		} )
	end
	for material, queued in pairs( Store.PendingClear ) do
		Store.PendingClear[ material ] = nil
		timer.Remove( "AdvMat.RTX.Clear." .. util.CRC( material ) )
		Callback( queued.callback, false, {
			status = "cancelled", operation = "clear", material = material,
			persisted = false, error = reason,
		} )
	end
end

local function PumpOutbound()
	local job = PeekOutbound()
	if not job then
		outboundPumpRunning = false
		timer.Remove( SEND_TIMER )
		return
	end
	local pending = Store.PendingAck[ job.nonce ]
	if not pending then
		PopOutbound()
		if not PeekOutbound() then
			outboundPumpRunning = false
			timer.Remove( SEND_TIMER )
		end
		return
	end

	if job.kind == "save" then
		local index = job.index
		local chunk = string.sub( job.data,
			( index - 1 ) * CHUNK_SIZE + 1, index * CHUNK_SIZE )
		net.Start( NET.SAVE )
			net.WriteString( job.nonce )
			net.WriteString( job.expectedID or "" )
			net.WriteString( job.expectedETag or "" )
			net.WriteUInt( index, 8 )
			net.WriteUInt( job.total, 8 )
			net.WriteUInt( #chunk, 17 )
			if #chunk > 0 then net.WriteData( chunk, #chunk ) end
		net.SendToServer()
		job.index = index + 1
		ArmAckTimeout( job.nonce, pending )
		if job.index > job.total then PopOutbound() end
		if not PeekOutbound() then
			outboundPumpRunning = false
			timer.Remove( SEND_TIMER )
		end
		return
	end

	if job.kind == "clear" then
		net.Start( NET.CLEAR )
			net.WriteString( job.nonce )
			net.WriteString( job.material )
			net.WriteString( job.expectedID or "" )
			net.WriteString( job.expectedETag or "" )
		net.SendToServer()
		ArmAckTimeout( job.nonce, pending )
	end
	PopOutbound()
	if not PeekOutbound() then
		outboundPumpRunning = false
		timer.Remove( SEND_TIMER )
	end
end

EnsureOutboundPump = function()
	if outboundPumpRunning then return end
	outboundPumpRunning = true
	timer.Create( SEND_TIMER, SEND_INTERVAL, 0, PumpOutbound )
end

local function MergeCapturedHashes( profile )
	if not Bridge or not Bridge.ResolveHashes then return profile end
	local material = MaterialName( profile )
	local captured = Bridge.ResolveHashes( material )
	if #captured == 0 then return profile end

	profile = Copy( profile )
	profile.target = Copy( profile.target or {} )
	local hashes = {}
	for _, hash in ipairs( profile.target.hashes or {} ) do hashes[ #hashes + 1 ] = hash end
	if profile.target.hash then hashes[ #hashes + 1 ] = profile.target.hash end
	for _, hash in ipairs( captured ) do hashes[ #hashes + 1 ] = hash end
	profile.target.hash = nil
	profile.target.hashes = hashes
	return profile
end

SendSave = function( queued )
	-- A newer edit may supersede this one while its large generated map is
	-- uploading. Do not let the older preflight commit afterward.
	if Store.PendingSave[ queued.material ] ~= queued then return false end
	if queued.predecessor and not queued.predecessor.completed then return true end
	if not Store.IsSynced() then
		Store.RequestSync()
		return true -- SYNC_END resumes queued saves using their original CAS base.
	end

	-- RTX profiles can reference the same edited-texture recipes as Source/VMT
	-- rules. Cache every exact output on the server before publishing the
	-- profile, otherwise a peer may try (and fail) to rebuild it locally.
	if not queued.assetsPrepared and AdvMat.Assets
		and isfunction( AdvMat.Assets.PrepareProfile ) then
		-- A completed snapshot may resume this job while its upload is still
		-- running. Only a successful asset ACK makes it publishable.
		if queued.assetsPreparing then return true end
		queued.assetsPreparing = true
		AdvMat.Assets.PrepareProfile( queued.profile, function( ok, reason )
			if Store.PendingSave[ queued.material ] ~= queued then return end
			queued.assetsPreparing = false
			if ok then queued.assetsPrepared = true SendSave( queued ) return end
			Store.PendingSave[ queued.material ] = nil
			FinishSave( queued, false, {
				status = "rejected", material = queued.material, persisted = false,
				error = AdvMat.L( "notify.asset_prepare_failed", {
					reason = tostring( reason or "upload failed" ),
				} ),
			} )
		end )
		return true
	end

	local nonce = NextNonce( "save", queued.material )
	local json = util.TableToJSON( queued.profile )
	if not isstring( json ) or #json > MAX_PROFILE_JSON then
		Store.PendingSave[ queued.material ] = nil
		FinishSave( queued, false, {
			status = "rejected", material = queued.material,
			error = "RTX profile exceeds the 512 KiB JSON limit",
		} )
		return false
	end
	local data = isstring( json ) and util.Compress( json ) or nil
	if not isstring( data ) or #data > MAX_COMPRESSED then
		Store.PendingSave[ queued.material ] = nil
		FinishSave( queued, false, {
			status = "rejected", material = queued.material,
			error = "RTX profile is too large to send",
		} )
		return false
	end

	local syncReady, syncError = Store.RequestSync()
	if syncReady == false then
		-- WithdrawModeHello may already have cancelled this pending save while
		-- tearing down the old connection/mode. Complete its callback only once.
		if Store.PendingSave[ queued.material ] == queued then
			Store.PendingSave[ queued.material ] = nil
			FinishSave( queued, false, {
				status = "sync-blocked", material = queued.material,
				error = tostring( syncError or "RTX native state could not be reconciled" ),
			} )
		end
		return false
	end
	-- Preflight is complete and this is still the latest queued save. Only now
	-- does it leave the supersedable queue and become an in-flight CAS request.
	Store.PendingSave[ queued.material ] = nil
	Store.InFlightSave[ queued.material ] = queued
	local ack = RegisterAck( nonce, "save", queued.material, function( ok, result )
		FinishSave( queued, ok, result )
	end, queued.profile )
	ack.localSave = queued.localCallback and queued or nil
	local total = math.max( 1, math.ceil( #data / CHUNK_SIZE ) )
	PushOutbound( {
		kind = "save", nonce = nonce, data = data, total = total, index = 1,
		expectedID = queued.expectedID, expectedETag = queued.expectedETag,
	} )
	return true
end

--- With localCallback, apply and retain the validated recipe immediately. The
--- ordinary callback still reports server persistence, independent of the
--- window lifetime. Writes retain their original version token unless an earlier
--- save from this client acknowledges its successor token.
function Store.Save( profile, callback, expectedVersion, localCallback )
	local optimistic = isfunction( localCallback )
	local function Reject( reason, status )
		local result = { status = status or "rejected", error = reason, persisted = false }
		Callback( localCallback, false, result )
		Callback( callback, false, result )
		return false, reason
	end
	if not Store.IsSynced() and not optimistic then
		local _, syncError = Store.RequestSync()
		local result = {
			status = syncError and "sync-blocked" or "synchronizing", persisted = false,
			error = syncError or "RTX profiles are still synchronizing; try Save again in a moment.",
		}
		Callback( callback, false, result )
		return false, result.error
	end
	profile = MergeCapturedHashes( profile )
	local clean, reason = SanitizeProfile( profile )
	if not clean then
		return Reject( reason )
	end
	if optimistic then
		-- Reset the native session before the local commit, never after it.
		local ready, syncError = Store.RequestSync()
		if not ready then return Reject( syncError, "sync-blocked" ) end
		if not Bridge or not isfunction( Bridge.Commit ) then return Reject( "RTX bridge is unavailable" ) end
	end

	local material = MaterialName( clean )
	local expectedID, expectedETag
	if istable( expectedVersion ) and expectedVersion.explicit == true then
		expectedID = isstring( expectedVersion.id ) and expectedVersion.id ~= ""
			and expectedVersion.id or nil
		expectedETag = isstring( expectedVersion.etag ) and expectedVersion.etag ~= ""
			and expectedVersion.etag or nil
	else
		expectedID, expectedETag = Store.GetVersion( material )
	end
	if ( expectedID == nil ) ~= ( expectedETag == nil ) then
		local error = "authoritative RTX profile version is unavailable; resynchronize before saving"
		return Reject( error, "sync-blocked" )
	end
	local owner = optimistic and LocalSaveFor( clean )
	if owner and owner.material ~= material then
		return Reject( "Another local save owns these texture hashes; edit its material: " .. owner.material )
	end
	if Store.PendingClear[ material ] then return Reject( "RTX override removal is still pending" ) end
	for _, ack in pairs( Store.PendingAck ) do
		if ack.operation == "clear" and ack.material == material then
			return Reject( "RTX override removal is still pending" )
		end
	end
	local previous = Store.PendingSave[ material ]
	if previous then
		Store.PendingSave[ material ] = nil
		FinishSave( previous, false, {
			status = "superseded", material = material,
			error = "a newer RTX profile save replaced this request",
		} )
	end

	local queued = {
		profile = clean, material = material, callback = callback,
		expectedID = expectedID, expectedETag = expectedETag,
		localCallback = optimistic and localCallback or nil, syncStatus = "pending",
		predecessor = Store.InFlightSave[ material ],
	}
	Store.PendingSave[ material ] = queued
	if optimistic then
		Store.LocalSaves[ material ] = queued
		PublishSyncState( queued )
		CommitLocalSave( queued )
	end
	local timerName = "AdvMat.RTX.Save." .. util.CRC( material )
	timer.Create( timerName, SAVE_DEBOUNCE, 1, function()
		if Store.PendingSave[ material ] ~= queued then return end
		SendSave( queued )
	end )

	return true, { status = "queued", material = material }
end

local function SendClear( queued )
	local nonce = NextNonce( "clear", queued.material )
	local syncReady, syncError = Store.RequestSync()
	if syncReady == false then
		Callback( queued.callback, false, {
			status = "sync-blocked", material = queued.material,
			error = tostring( syncError or "RTX native state could not be reconciled" ),
		} )
		return false
	end
	RegisterAck( nonce, "clear", queued.material, queued.callback, queued.profile )
	Store.PendingAck[ nonce ].id = queued.expectedID
	PushOutbound( {
		kind = "clear", nonce = nonce, material = queued.material,
		expectedID = queued.expectedID, expectedETag = queued.expectedETag,
	} )
end

function Store.Clear( material, callback, expectedVersion )
	if not Store.IsSynced() then
		local _, syncError = Store.RequestSync()
		local result = {
			status = syncError and "sync-blocked" or "synchronizing", persisted = false,
			error = syncError or "RTX profiles are still synchronizing; try again in a moment.",
		}
		Callback( callback, false, result )
		return false, result.error
	end
	local requestedMaterial = MaterialName( material )
	local localSave = LocalSaveFor( requestedMaterial )
	if localSave and localSave.syncStatus == "pending" then
		local reason = "This material is syncing in the background; remove it after sync finishes."
		Callback( callback, false, { status = "synchronizing", error = reason, persisted = false } )
		return false, reason
	end
	if requestedMaterial == "" then
		Callback( callback, false, { status = "rejected", error = "invalid material" } )
		return false, "invalid material"
	end
	local expectedID, expectedETag
	if istable( expectedVersion ) and expectedVersion.explicit == true then
		expectedID = isstring( expectedVersion.id ) and expectedVersion.id ~= ""
			and expectedVersion.id or nil
			expectedETag = isstring( expectedVersion.etag ) and expectedVersion.etag ~= ""
			and expectedVersion.etag or nil
	else
		expectedID, expectedETag = Store.GetVersion( requestedMaterial )
	end
	if ( expectedID == nil ) ~= ( expectedETag == nil ) then
		local error = "authoritative RTX profile version is unavailable; resynchronize before clearing"
		Callback( callback, false, { status = "sync-blocked", material = requestedMaterial, error = error } )
		return false, error
	end

	-- Store.Get can resolve a displayed Source-material alias through its
	-- captured hash.  The server does not have that client-only alias map, so
	-- send the saved owner's canonical target material rather than an alias it
	-- cannot resolve.  The expected ID/token still protects the exact version.
	local profile = Store.Get( requestedMaterial )
	if not profile and expectedID then profile = Copy( Store.Profiles[ expectedID ] ) end
	material = profile and MaterialName( profile ) or requestedMaterial

	local pendingSave = Store.PendingSave[ material ]
	if pendingSave then
		Store.PendingSave[ material ] = nil
		timer.Remove( "AdvMat.RTX.Save." .. util.CRC( material ) )
		Callback( pendingSave.callback, false, { status = "superseded", material = material } )
	end

	local previous = Store.PendingClear[ material ]
	if previous then Callback( previous.callback, false, { status = "superseded", material = material } ) end
	local queued = {
		material = material, callback = callback,
		profile = profile,
		expectedID = expectedID, expectedETag = expectedETag,
	}
	Store.PendingClear[ material ] = queued

	local timerName = "AdvMat.RTX.Clear." .. util.CRC( material )
	timer.Create( timerName, CLEAR_DEBOUNCE, 1, function()
		if Store.PendingClear[ material ] ~= queued then return end
		Store.PendingClear[ material ] = nil
		SendClear( queued )
	end )

	return true, { status = "queued", material = material }
end

local function SendModeHello( protocol )
	net.Start( NET.HELLO )
		net.WriteUInt( protocol, 8 )
	net.SendToServer()
end

local function ClearSyncTimers()
	timer.Remove( SYNC_RETRY_TIMER )
	timer.Remove( SYNC_RESPONSE_TIMER )
	timer.Remove( SYNC_TRANSFER_TIMER )
end

local function AbandonSync()
	syncing, stagedProfiles, stagedETags, stagedTombstones, profilesBeforeSync = false, nil, nil, nil, nil
	Store.Synced = false
	Store.SyncRequested = false
	Store.ExpectedProfiles = nil
	for transfer in pairs( profileBuffers ) do
		profileBuffers[ transfer ] = nil
		timer.Remove( "AdvMat.RTX.Profile." .. util.CRC( transfer ) )
	end
	ClearSyncTimers()
end

local function ScheduleSyncRetry()
	timer.Remove( SYNC_RETRY_TIMER )
	timer.Create( SYNC_RETRY_TIMER, SYNC_RETRY_DELAY, 1, function()
		if Store.Synced or syncing or not RTXModeActive() then return end
		Store.RequestSync()
	end )
end

local function ArmSyncTransferTimeout()
	if not syncing then return end
	timer.Create( SYNC_TRANSFER_TIMER, SYNC_TRANSFER_TIMEOUT, 1, function()
		if not syncing then return end
		AbandonSync()
		ScheduleSyncRetry()
	end )
end

local function ArmSyncResponseTimeout()
	if Store.Synced then return end
	timer.Create( SYNC_RESPONSE_TIMER, SYNC_RESPONSE_TIMEOUT, 1, function()
		if Store.Synced or syncing then return end
		Store.SyncRequested = false
		ScheduleSyncRetry()
	end )
end

local function WithdrawModeHello()
	AbandonSync()
	ResetOutbound( "RTX mode was deactivated before the operation completed" )
	-- Preserve the vanilla/auto-no-runtime zero-background-traffic path.  Byte
	-- zero is needed only after this client actually announced protocol 3 to the
	-- current server; a fresh vanilla session has no stale route to withdraw.
	if Store.ModeAnnounced ~= true then return false end
	SendModeHello( 0 )
	Store.ModeAnnounced = false
	return true
end

function Store.RequestSync()
	if not RTXModeActive() then
		WithdrawModeHello()
		return false, "RTX backend is not active"
	end
	if Bridge and isfunction( Bridge.PrepareAuthoritativeSync ) then
		local ok, ready, detail = pcall( Bridge.PrepareAuthoritativeSync )
		if not ok or ready ~= true then
			local reason = ok and detail or ready
			reason = tostring( reason or "native owned-state reset failed" )
			-- Protocol 3 promises an authoritative native reset.  If that promise
			-- cannot be met, withdraw any earlier capability handshake so server-side
			-- auto tool routing and tombstone delivery cannot use stale state.
			WithdrawModeHello()
			ScheduleSyncRetry()
			AdvMat.Log( "RTX profile sync blocked: %s", reason )
			return false, reason
		end
	end
	-- A provider reset clears its on-disk layer even when the server mirror is
	-- current. Invalidate only the native apply cache and replay this connection's
	-- saved state; network snapshot/ACK queues need not be disturbed.
	local generation = Bridge and Bridge.SessionGeneration
	if generation ~= nil and generation ~= Store.NativeGeneration then
		Store.NativeGeneration = generation
		Store.AppliedETags = {}
		if Store.IsSynced() then ApplySnapshotProfiles( Store.Profiles ) end
		for _, queued in pairs( Store.LocalSaves ) do CommitLocalSave( queued ) end
	end
	-- HELLO asks the server to replace its entire outgoing queue with a fresh
	-- snapshot, including dropping queued ACKs. Send it only when a snapshot is
	-- actually needed, not on every Save, material selection and window close.
	if Store.ModeAnnounced and ( Store.IsSynced() or syncing or Store.SyncRequested ) then return true end

	SendModeHello( Store.PROTOCOL )
	Store.ModeAnnounced = true
	Store.SyncRequested = true
	ArmSyncResponseTimeout()
	return true
end

local function ReadProfileFragment()
	PurgeProfileBuffers()
	local transfer = net.ReadString()
	if not isstring( transfer ) or #transfer < 1 or #transfer > 96 then return nil, "bad transfer" end
	local index = net.ReadUInt( 8 )
	local total = net.ReadUInt( 8 )
	local length = net.ReadUInt( 17 )
	local left = net.BytesLeft and net.BytesLeft()
	if total < 1 or total > MAX_CHUNKS or index < 1 or index > total
		or length > CHUNK_SIZE or ( left and length > left ) then
		return nil, "bad fragment"
	end
	local chunk = length > 0 and net.ReadData( length ) or ""

	local buffer = profileBuffers[ transfer ]
	if index == 1 then
		local pending = ProfileBufferTotals()
		if not buffer and pending >= MAX_PENDING_TRANSFERS then return nil, "too many pending transfers" end
		buffer = { total = total, parts = {}, bytes = 0, expires = RealTime() + BUFFER_TTL }
		profileBuffers[ transfer ] = buffer
	elseif not buffer then
		return nil, "out-of-order fragment"
	end
	if buffer.total ~= total then
		profileBuffers[ transfer ] = nil
		timer.Remove( "AdvMat.RTX.Profile." .. util.CRC( transfer ) )
		return nil, "inconsistent transfer"
	end
	buffer.expires = RealTime() + BUFFER_TTL
	local timerName = "AdvMat.RTX.Profile." .. util.CRC( transfer )
	timer.Create( timerName, BUFFER_TTL, 1, function()
		if profileBuffers[ transfer ] == buffer then profileBuffers[ transfer ] = nil end
	end )

	local old = buffer.parts[ index ]
	buffer.parts[ index ] = chunk
	buffer.bytes = buffer.bytes - ( old and #old or 0 ) + #chunk
	local _, aggregate = ProfileBufferTotals()
	if buffer.bytes > MAX_COMPRESSED or aggregate > MAX_PENDING_BYTES then
		profileBuffers[ transfer ] = nil
		timer.Remove( timerName )
		return nil, "profile transfer payload limit exceeded"
	end
	for part = 1, total do
		if buffer.parts[ part ] == nil then return nil end
	end

	profileBuffers[ transfer ] = nil
	timer.Remove( "AdvMat.RTX.Profile." .. util.CRC( transfer ) )
	local json = util.Decompress( table.concat( buffer.parts ), MAX_UNCOMPRESSED )
	if not isstring( json ) or #json > MAX_UNCOMPRESSED then return nil, "profile JSON is too large" end
	local message = json and util.JSONToTable( json )
	if not istable( message ) then return nil, "could not decode profile transfer" end
	return message
end

net.Receive( NET.SYNC_BEGIN, function()
	ClearSyncTimers()
	Store.SyncRequested = false
	Store.Revision = net.ReadUInt( 32 )
	Store.ExpectedProfiles = net.ReadUInt( 16 )
	profilesBeforeSync = Copy( Store.Profiles )
	stagedProfiles = {}
	stagedETags = {}
	stagedTombstones = {}
	syncing = true
	Store.Synced = false
	ArmSyncTransferTimeout()
	for id in pairs( Store.CleanupPending ) do timer.Remove( CleanupTimerName( id ) ) end
end )

net.Receive( NET.PROFILE, function()
	local message, transferError = ReadProfileFragment()
	if transferError then
		AdvMat.Log( "Ignored malformed RTX profile transfer: %s", transferError )
		return
	end
	ArmSyncTransferTimeout()
	if not message then return end
	if not istable( message ) or not isstring( message.id ) then return end
	Store.Revision = math.max( Store.Revision, math.floor( tonumber( message.revision ) or 0 ) )

	if syncing then
		local clean = SanitizeProfile( message.profile )
		if message.removed then
			if clean then stagedTombstones[ message.id ] = clean end
		else
			local id = clean and ProfileKey( clean ) or nil
			if id and id == message.id and isstring( message.etag )
				and message.etag ~= "" and #message.etag <= 64 then
				if AdvMat.Assets and isfunction( AdvMat.Assets.MarkRemoteValue ) then
					AdvMat.Assets.MarkRemoteValue( clean )
				end
				stagedProfiles[ id ] = clean
				stagedETags[ id ] = message.etag
			end
		end
		return
	end

	if message.removed then
		local clean = SanitizeProfile( message.profile )
		if not clean then return end
		local material = MaterialName( clean )
		local activeID = Store.MaterialIndex[ material ]
		if activeID then RemoveLocal( activeID, material ) end
		QueueCleanup( message.id, clean )
		local localSave = LocalSaveFor( clean )
		hook.Run( "AdvMatRTXProfilesChanged", material,
			localSave and Copy( localSave.profile ) or nil, not localSave, message.id )
		return
	end

	local clean, id = SetLocal( message.profile, message.id, message.etag )
	if not clean or id ~= message.id then return end
	if AdvMat.Assets and isfunction( AdvMat.Assets.MarkRemoteValue ) then
		AdvMat.Assets.MarkRemoteValue( clean )
	end
	ApplyProfile( clean )
	local localSave = LocalSaveFor( clean )
	hook.Run( "AdvMatRTXProfilesChanged", MaterialName( clean ),
		Copy( localSave and localSave.profile or clean ), false, id )
end )

local function QueueUnclaimedCleanup( id, profile, claimed )
	local retired = {}
	for _, hash in ipairs( TargetHashes( profile ) ) do
		if not claimed[ hash ] then retired[ #retired + 1 ] = hash end
	end
	if #retired == 0 then return end
	local cleanup = Copy( profile )
	cleanup.target = Copy( cleanup.target or {} )
	cleanup.target.hash = retired[ 1 ]
	cleanup.target.hashes = retired
	QueueCleanup( id, cleanup )
end

net.Receive( NET.SYNC_END, function()
	local revision = net.ReadUInt( 32 )
	local received = AdvMat.TableCount( stagedProfiles or {} )
		+ AdvMat.TableCount( stagedTombstones or {} )
	if not syncing or revision ~= Store.Revision or received ~= ( Store.ExpectedProfiles or 0 ) then
		AbandonSync()
		ScheduleSyncRetry()
		return
	end
	ClearSyncTimers()
	-- The complete authoritative set is now known.  Exact-hash cleanup below is
	-- safe to run immediately because every newly claimed hash is filtered out.
	syncing = false

	local claimed = {}
	for _, profile in pairs( stagedProfiles or {} ) do
		for _, hash in ipairs( TargetHashes( profile ) ) do claimed[ hash ] = true end
	end

	-- Explicit server tombstones and implicit removals discovered by snapshot
	-- reconciliation share the same exact-hash cleanup path.  Filtering both
	-- against the complete staged owner set prevents an old profile from
	-- clearing a hash that the authoritative snapshot still claims.
	for id, profile in pairs( stagedTombstones or {} ) do
		QueueUnclaimedCleanup( id, profile, claimed )
	end
	for id, previous in pairs( profilesBeforeSync or {} ) do
		QueueUnclaimedCleanup( "sync:" .. tostring( revision ) .. ":" .. id,
			previous, claimed )
	end

	for id in pairs( Store.Profiles ) do Store.Profiles[ id ] = nil end
	for id in pairs( Store.ProfileETags ) do Store.ProfileETags[ id ] = nil end
	for id, profile in pairs( stagedProfiles ) do
		Store.Profiles[ id ] = profile
		Store.ProfileETags[ id ] = stagedETags[ id ]
		ReconcileCleanupWithProfile( profile )
	end
	RebuildIndexes( Store.Profiles )
	ApplySnapshotProfiles( Store.Profiles )

	syncing, stagedProfiles, stagedETags, stagedTombstones, profilesBeforeSync = false, nil, nil, nil, nil
	Store.Synced = true
	Store.SyncRequested = false
	hook.Run( "AdvMatRTXProfilesSynced", Store.Profiles, Store.Revision )
	for material, queued in pairs( Store.PendingSave ) do
		timer.Create( "AdvMat.RTX.Save." .. util.CRC( material ), SAVE_DEBOUNCE, 1,
			function() SendSave( queued ) end )
	end
end )

net.Receive( NET.ACK, function()
	local message = AdvMat.Net.ReadTable()
	if not istable( message ) or not isstring( message.nonce ) then return end
	local pending = Store.PendingAck[ message.nonce ]
	if not pending then return end
	Store.PendingAck[ message.nonce ] = nil
	timer.Remove( "AdvMat.RTX.Ack." .. util.CRC( message.nonce ) )

	local result = {
		status    = message.ok and ( pending.operation == "clear" and "cleared" or "saved" ) or "rejected",
		operation = pending.operation,
		material  = pending.material,
		profile   = Copy( message.profile or pending.profile ),
		id        = message.id,
		etag      = message.etag,
		revision  = message.revision,
		error     = message.error,
		persisted = message.ok == true,
	}

	if message.ok ~= true then
		Callback( pending.callback, false, result )
		return
	end

	if pending.operation == "clear" then
		Store.LocalSaves[ pending.material ] = nil
		if pending.id then Store.AppliedETags[ pending.id ] = nil end
		local clearCaps = Bridge and Bridge.Capabilities and Bridge.Capabilities() or {}
		local hashlessExport = pending.profile and #TargetHashes( pending.profile ) == 0
			and clearCaps.exportOnly == true
		if not pending.profile or ( #TargetHashes( pending.profile ) == 0 and not hashlessExport ) then
			result.nativeAttempted = false
			result.nativeCleaned = false
			result.cleanupComplete = true
			Callback( pending.callback, true, result )
			return
		end
		result.status = "cleanup_pending"
		if not RTXModeActive() or not Bridge then
			QueueCleanup( "ack:" .. tostring( pending.id or message.id or pending.material ), pending.profile )
			result.nativeAttempted = false
			result.nativeCleaned = false
			Callback( pending.callback, true, result )
			return
		end
		QueueCleanup( "ack:" .. tostring( pending.id or message.id or pending.material ), pending.profile,
			function( cleaned, cleanupResult )
				local exportOnly = istable( cleanupResult ) and cleanupResult.exportOnly == true
				result.nativeAttempted = not exportOnly
				result.nativeCleaned = not exportOnly and cleaned == true
				result.cleanupComplete = cleaned == true
				result.cleanupStatus = istable( cleanupResult ) and cleanupResult.status or nil
				result.cleanupError = not cleaned and istable( cleanupResult ) and cleanupResult.error or nil
				result.status = cleaned and "cleared" or "cleanup_pending"
				-- The first boolean intentionally reports authoritative server
				-- persistence.  nativeCleaned reports the independent local result.
				Callback( pending.callback, true, result )
			end )
		return
	end

	if pending.localSave then
		-- Local Save already handed this exact revision to the native writer.
		-- ACK confirms persistence only; re-committing here would replace a newer
		-- local save and needlessly bake/import every edited texture twice.
		local localResult = pending.localSave.localResult or {}
		result.nativeApplied = localResult.nativeApplied == true
		result.applyError = localResult.applyError
		result.pendingHash = localResult.pendingHash
		Callback( pending.callback, true, result )
		return
	end

	local hashless = pending.profile and #TargetHashes( pending.profile ) == 0
	local bridgeCaps = Bridge and Bridge.Capabilities and Bridge.Capabilities() or {}
	local canExportDraft = hashless and bridgeCaps.exportOnly == true
	if not pending.profile or ( hashless and not canExportDraft )
		or not RTXModeActive() or not Bridge or not Bridge.Commit then
		result.nativeAttempted = false
		result.nativeApplied = false
		if hashless and not canExportDraft then
			result.status = "waiting-for-hash"
			result.applyStatus = "waiting-for-hash"
			result.pendingHash = true
		end
		Callback( pending.callback, true, result )
		return
	end

	-- Persistence is already successful.  Wait for the debounced writer/export
	-- handoff so the editor can accurately distinguish "saved" from
	-- "exported" without treating a local writer failure as lost server data.
	Bridge.Commit( pending.profile, function( applied, applyResult )
		local exported = istable( applyResult ) and applyResult.status == "exported"
		result.nativeAttempted = not exported
		result.nativeApplied = not exported and applied == true
		if istable( applyResult ) then
			result.live = applyResult.live
			result.path = applyResult.path
			result.applyStatus = applyResult.status
			if exported then result.status = "exported" end
			if not applied then result.applyError = applyResult.error end
		end
		Callback( pending.callback, true, result )
	end )
end )

net.Receive( NET.NOTIFY, function()
	local message = net.ReadString()
	local kind = net.ReadUInt( 3 )
	if AdvMat.NotifyLocal then AdvMat.NotifyLocal( message, kind, 6 ) end
end )

-- `advmat_backend` is a userinfo convar, but a server cannot resolve `auto`
-- from client-only Remix APIs.  Signal the newly resolved state immediately so
-- switching RTX -> auto/vanilla cannot leave a stale server-side RTX route.
if cvars and isfunction( cvars.AddChangeCallback ) then
	cvars.AddChangeCallback( "advmat_backend", function()
		AbandonSync()
		timer.Simple( 0, function()
			if isfunction( Store.RequestSync ) then Store.RequestSync() end
		end )
	end, "AdvMat.RTX.ModeSignal" )
end

hook.Add( "InitPostEntity", "AdvMat.RTX.RequestProfiles", function()
	-- A reconnect may reuse the Lua state and its previous mirror.  Keep those
	-- profiles for exact-hash retirement comparison, but do not permit writes
	-- until the new server has supplied an authoritative snapshot.
	ResetOutbound( "server connection changed before the operation completed" )
	AbandonSync()
	Store.ModeAnnounced = false
	timer.Simple( 1, Store.RequestSync )
end )

hook.Add( "AdvMatBackendCapabilitiesChanged", "AdvMat.RTX.RequestProfiles", function()
	timer.Simple( 0, function()
		Store.RequestSync()
		for _, cleanup in pairs( Store.CleanupPending ) do AttemptCleanup( cleanup ) end
	end )
end )

hook.Add( "AdvMatBackendSessionEnded", "AdvMat.RTX.PublishUnfrozenMode", function()
	timer.Simple( 0, function()
		if isfunction( Store.RequestSync ) then Store.RequestSync() end
	end )
end )

concommand.Add( "advmat_rtx_resync", function()
	AbandonSync()
	Store.RequestSync()
end )
