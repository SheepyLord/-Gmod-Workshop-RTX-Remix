--[[---------------------------------------------------------------------------
	Advanced Material Editor - network protocol

	Payloads are util.TableToJSON -> util.Compress. Single-rule messages fit
	comfortably in one net message; the full database sync is chunked because
	a net message is capped at 64 KiB and a heavily edited server can easily
	exceed that.
-----------------------------------------------------------------------------]]

AdvMat = AdvMat or {}
AdvMat.Net = AdvMat.Net or {}

AdvMat.Net.CHUNK_SIZE = 32000
-- Keep full-database snapshots below the practical reliable-net throughput
-- ceiling.  A snapshot may be many MiB; emitting all of its chunks in one
-- frame can overflow a joining client's reliable channel before Lua gets a
-- chance to process the first one.
AdvMat.Net.SYNC_INTERVAL = 0.35

-- Compressed net payloads carry their uncompressed size in their first eight
-- bytes. Always give util.Decompress a ceiling: without one, a tiny hostile
-- message can reserve effectively unbounded Lua memory before any of the rule
-- sanitising below gets a chance to reject it.
--
-- A single rule can legitimately be fairly large when it contains painted
-- selections. A full snapshot can contain hundreds of those rules, so it gets
-- a separate, larger ceiling.
AdvMat.Net.MAX_TABLE_SIZE = 8 * 1024 * 1024
AdvMat.Net.MAX_SYNC_SIZE  = 64 * 1024 * 1024

-- A broadcast rule must fit in one net message, which Garry's Mod caps at
-- 64 KiB. The rest of the message (name, revision, length) needs a little room.
AdvMat.Net.MAX_RULE_WIRE = 60000

if SERVER then
	util.AddNetworkString( "AdvMat.SyncBegin" ) -- SV -> CL, a snapshot at this revision is queued
	util.AddNetworkString( "AdvMat.Sync"      ) -- SV -> CL, chunked full database
	util.AddNetworkString( "AdvMat.RuleSet"   ) -- CL -> SV upsert, SV -> CL broadcast
	util.AddNetworkString( "AdvMat.RuleClear" ) -- CL -> SV remove, SV -> CL broadcast
	util.AddNetworkString( "AdvMat.RuleApplied" ) -- SV -> saving CL after the server apply pass
	util.AddNetworkString( "AdvMat.RuleRejected" ) -- SV -> saving CL, the edit was refused and why
	util.AddNetworkString( "AdvMat.RulePersisted" ) -- SV -> saving CL, its edits are on disk
	util.AddNetworkString( "AdvMat.Open"      ) -- SV -> CL, open the editor on an entity
	util.AddNetworkString( "AdvMat.Request"   ) -- CL -> SV, ask for a full sync
	util.AddNetworkString( "AdvMat.Notify"    ) -- SV -> CL, short status line
	util.AddNetworkString( "AdvMat.DebugTrace" ) -- CL toggles tracing; SV returns post-save slot state
end

---------------------------------------------------------------------------
-- Small payloads (one rule)
---------------------------------------------------------------------------
function AdvMat.Net.WriteTable( tbl )
	local data = util.Compress( util.TableToJSON( tbl or {} ) ) or ""
	net.WriteUInt( #data, 24 )
	if #data > 0 then net.WriteData( data, #data ) end
end

function AdvMat.Net.ReadTable()
	local len = net.ReadUInt( 24 )
	if len <= 0 then return {} end

	-- A net message itself is capped at 64 KiB. Checking against the bytes that
	-- actually remain also keeps a forged length from making net.ReadData read
	-- beyond this message.
	local left = net.BytesLeft and net.BytesLeft()
	if left and len > left then return nil end

	local data = net.ReadData( len )
	local json = util.Decompress( data, AdvMat.Net.MAX_TABLE_SIZE )
	if not json then return nil end
	return util.JSONToTable( json )
end

---------------------------------------------------------------------------
-- Chunked transfer, used for the full database sync
---------------------------------------------------------------------------

-- ReceiveChunk intentionally has one reassembly buffer and no transfer id.
-- Consequently, complete snapshots must be serialized for every recipient.
-- A single global queue is deliberately conservative: it also prevents two
-- different late joiners from making the server emit two large reliable-net
-- bursts at the same time.
local syncQueue = {}
local syncPumpRunning = false
local syncLastSentAt
local SYNC_PUMP_TIMER = "AdvMat.SyncPump"

local function SyncNow()
	return CurTime and CurTime() or 0
end

local function AddSyncRecipient( out, seen, ply )
	if not IsValid( ply ) or seen[ ply ] then return end
	seen[ ply ] = true
	out[ #out + 1 ] = ply
end

local function CopySyncRecipients( target )
	local out, seen = {}, {}

	if target == nil then
		local all = player and player.GetAll and player.GetAll() or {}
		for _, ply in pairs( all ) do AddSyncRecipient( out, seen, ply ) end
		return out
	end

	-- Players are userdata in Garry's Mod.  Some test doubles represent them
	-- as tables, so an IsValid method distinguishes one such recipient from a
	-- table containing several recipients.
	if istable( target ) and type( target.IsValid ) ~= "function"
		and type( target.IsPlayer ) ~= "function" then
		for _, ply in pairs( target ) do AddSyncRecipient( out, seen, ply ) end
	else
		AddSyncRecipient( out, seen, target )
	end

	return out
end

local function PruneSyncRecipients( job, disconnected )
	for i = #job.recipients, 1, -1 do
		local ply = job.recipients[ i ]
		if ply == disconnected or not IsValid( ply ) then
			table.remove( job.recipients, i )
		end
	end

	return #job.recipients > 0
end

local function StopSyncPump()
	if not syncPumpRunning then return end
	syncPumpRunning = false
	timer.Remove( SYNC_PUMP_TIMER )
end

local function PumpSyncChunk()
	-- Invalid/disconnected recipients should not keep their compressed
	-- snapshots (which can be large) alive until every older transfer finishes.
	while #syncQueue > 0 do
		local job = syncQueue[ 1 ]
		if not PruneSyncRecipients( job ) then
			table.remove( syncQueue, 1 )
		else
			local i = job.nextChunk
			local chunk = string.sub( job.data,
				( i - 1 ) * AdvMat.Net.CHUNK_SIZE + 1,
				i * AdvMat.Net.CHUNK_SIZE )

			net.Start( "AdvMat.Sync" )
				net.WriteUInt( i, 16 )
				net.WriteUInt( job.total, 16 )
				net.WriteUInt( #chunk, 17 )
				if #chunk > 0 then net.WriteData( chunk, #chunk ) end

			if #job.recipients == 1 then
				net.Send( job.recipients[ 1 ] )
			else
				net.Send( job.recipients )
			end

			syncLastSentAt = SyncNow()
			job.nextChunk = i + 1
			if job.nextChunk > job.total then table.remove( syncQueue, 1 ) end

			if #syncQueue == 0 then StopSyncPump() end
			return true
		end
	end

	StopSyncPump()
	return false
end

local function StartSyncPump()
	if syncPumpRunning or #syncQueue == 0 then return end
	syncPumpRunning = true
	timer.Create( SYNC_PUMP_TIMER, AdvMat.Net.SYNC_INTERVAL, 0, PumpSyncChunk )
end

--- Server: split a table across as many "AdvMat.Sync" messages as needed.
--- `target` is a Player, a table of Players, or nil to broadcast.
function AdvMat.Net.SendChunked( tbl, target )
	if CLIENT then return end

	local recipients = CopySyncRecipients( target )
	if #recipients == 0 then return end

	local data = util.Compress( util.TableToJSON( tbl or {} ) ) or ""
	local total = math.max( 1, math.ceil( #data / AdvMat.Net.CHUNK_SIZE ) )
	local wasIdle = #syncQueue == 0 and not syncPumpRunning

	syncQueue[ #syncQueue + 1 ] = {
		data = data,
		total = total,
		nextChunk = 1,
		recipients = recipients,
	}

	-- Preserve the old synchronous behaviour for an isolated one-message
	-- snapshot.  The timestamp still prevents several small snapshots from
	-- becoming a same-frame burst.  Multi-message databases always use the
	-- paced pump.
	local now = SyncNow()
	if wasIdle and total == 1
		and ( syncLastSentAt == nil
			or now - syncLastSentAt >= AdvMat.Net.SYNC_INTERVAL ) then
		PumpSyncChunk()
		return
	end

	StartSyncPump()
end

if SERVER then
	hook.Add( "PlayerDisconnected", "AdvMat.SyncQueueCleanup", function( ply )
		for i = #syncQueue, 1, -1 do
			if not PruneSyncRecipients( syncQueue[ i ], ply ) then
				table.remove( syncQueue, i )
			end
		end

		if #syncQueue == 0 then StopSyncPump() end
	end )
end

--- Client: feed an incoming "AdvMat.Sync" message into the reassembly buffer.
--- Returns the decoded table once the final chunk arrives, and nil before
--- that. A transfer that completes but cannot be decoded returns nil plus a
--- reason, so the caller can say so instead of silently keeping no rules.
local rxBuffer, rxExpected = {}, 0

function AdvMat.Net.ReceiveChunk()
	local index = net.ReadUInt( 16 )
	local total = net.ReadUInt( 16 )
	local len   = net.ReadUInt( 17 )
	local chunk = len > 0 and net.ReadData( len ) or ""

	if index == 1 then
		rxBuffer, rxExpected = {}, total
	elseif total ~= rxExpected then
		-- A new transfer started before the old one finished; restart cleanly.
		rxBuffer, rxExpected = {}, total
	end

	rxBuffer[ index ] = chunk
	if index < total then return nil end

	local data = table.concat( rxBuffer )
	rxBuffer, rxExpected = {}, 0

	local json = util.Decompress( data, AdvMat.Net.MAX_SYNC_SIZE )
	if not json then
		return nil, "the material database snapshot could not be unpacked"
			.. " (larger than " .. math.floor( AdvMat.Net.MAX_SYNC_SIZE / 1048576 )
			.. " MiB, or damaged)"
	end

	local tbl = util.JSONToTable( json )
	if not istable( tbl ) then return nil, "the material database snapshot could not be read" end
	return tbl
end
