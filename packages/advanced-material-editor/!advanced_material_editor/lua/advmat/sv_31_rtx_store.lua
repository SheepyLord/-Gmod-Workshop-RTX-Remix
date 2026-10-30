--[[---------------------------------------------------------------------------
	Advanced Material Editor - isolated RTX profile store (server)

	RTX profiles are not VMT rules.  They have their own schema, JSON database,
	network protocol and client capability handshake.  The server authorizes and
	persists profiles only; application is exclusively clientside through the RTX
	bridge.  In particular this file never calls Entity:SetSubMaterial.
-----------------------------------------------------------------------------]]

AdvMat          = AdvMat or {}
AdvMat.RTXStore = AdvMat.RTXStore or {}

local Store = AdvMat.RTXStore

-- Version two changed authoritative identities from Source material names to
-- captured 64-bit texture hashes.  Version three makes the native
-- ClearAllOwned-per-session reset part of the compatibility contract, allowing
-- delivered cleanup tombstones to be pruned without stranding a stale layer on
-- a disconnected client.  Older clients must not enter this lifecycle.
Store.PROTOCOL = 3
Store.DataFile = "advmat/rtx_overrides.json"
-- file.Write and file.Rename enforce Garry's Mod's DATA filename allow-list.
-- A suffix after `.json` changes the effective extension, so the former
-- `.json.tmp` / `.json.bak` transaction files could never be created by the
-- stock client.  Keep every transaction participant ending in an allowed
-- extension.  The legacy names remain read-only recovery candidates for hosts
-- which previously supplied a less restrictive custom file implementation.
Store.BackupFile = "advmat/rtx_overrides.backup.json"
Store.TempFile = "advmat/rtx_overrides.pending.json"
Store.LegacyBackupFile = Store.DataFile .. ".bak"
Store.LegacyTempFile = Store.DataFile .. ".tmp"
Store.Profiles = Store.Profiles or {}
Store.Tombstones = Store.Tombstones or {}
Store.HashOwners = Store.HashOwners or {}
Store.MaterialIndex = Store.MaterialIndex or {}
Store.Revision = tonumber( Store.Revision ) or 0

CreateConVar( "advmat_rtx_max_profiles", "512", { FCVAR_ARCHIVE },
	"Maximum number of persistent RTX material profiles." )

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

for _, name in pairs( NET ) do util.AddNetworkString( name ) end

-- Profiles may contain bounded paint/generator recipes which are larger than
-- Garry's Mod's 64 KiB net-message ceiling.  Each profile is compressed once
-- and carried in independent 30 KiB fragments.  Clear/ack messages stay small
-- and continue to use the shared one-table helper.
local CHUNK_SIZE          = 30000
local SEND_INTERVAL       = 0.35
local SEND_TIMER          = "AdvMat.RTX.ProfilePump"
local MAX_PROFILE_JSON    = 512 * 1024
local MAX_COMPRESSED      = 512 * 1024
local MAX_UNCOMPRESSED    = 640 * 1024
local MAX_DATABASE_JSON   = 8 * 1024 * 1024
local MAX_CHUNKS          = math.ceil( MAX_COMPRESSED / CHUNK_SIZE )
local MAX_PENDING_PER_PLY = 4
local MAX_PENDING_BYTES   = 1024 * 1024
local BUFFER_TTL          = 45
local MAX_TOMBSTONES      = 1024

Store.TransferID = tonumber( Store.TransferID ) or 0

local dirty, saveQueued = false, false
local diskFailureReason, diskFailureCount = nil, 0
local MAX_AUTOMATIC_SAVE_ATTEMPTS = 4

local function ErrorText( value )
	if istable( value ) then return table.concat( value, "; " ) end
	return tostring( value or "unknown error" )
end

local function SanitizeProfile( raw )
	local schema = AdvMat.RTXSchema
	if not istable( schema ) or not isfunction( schema.SanitizeProfile ) then
		return nil, "RTX profile schema is unavailable"
	end

	local ok, clean, errors = pcall( schema.SanitizeProfile, raw )
	if not ok then return nil, tostring( clean ) end
	if not clean then return nil, ErrorText( errors ) end
	if not clean.target or not isstring( clean.target.material ) or clean.target.material == "" then
		return nil, "target.material is required"
	end
	-- Sanitization proves that the graph is structurally valid; compilation also
	-- proves that its effective output can be represented by the bounded native
	-- writer (for example, two texture inputs cannot be multiplied directly).
	-- Reject that mismatch before it can enter the durable/server-authoritative
	-- store and fail independently on every client.
	if not isfunction( schema.Compile ) then return nil, "RTX profile compiler is unavailable" end
	local compiledOK, compiled, compileErrors = pcall( schema.Compile, clean )
	if not compiledOK then return nil, tostring( compiled ) end
	if not compiled then return nil, "RTX profile cannot be compiled: " .. ErrorText( compileErrors ) end
	return clean
end

local function MaterialName( value )
	if istable( value ) then value = value.target and value.target.material or value.material end
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

-- The first normalized hash is a stable profile identity.  Profiles saved
-- before a material has rendered remain explicitly pending and are never
-- allowed to claim a captured hash until a later save supplies one.
local function ProfileKey( profile )
	local hashes = TargetHashes( profile )
	if #hashes > 0 then return "rtx:hash:" .. string.sub( hashes[ 1 ], 3 ) end
	local material = MaterialName( profile )
	return material ~= "" and ( "rtx:pending:" .. material ) or nil
end

local function RebuildIndexes( profiles )
	local hashes, materials = {}, {}
	for id, profile in pairs( profiles or {} ) do
		local material = MaterialName( profile )
		if material ~= "" and not materials[ material ] then materials[ material ] = id end
		for _, hash in ipairs( TargetHashes( profile ) ) do
			if not hashes[ hash ] then hashes[ hash ] = id end
		end
	end
	return hashes, materials
end

local function InstallIndexes()
	Store.HashOwners, Store.MaterialIndex = RebuildIndexes( Store.Profiles )
end

InstallIndexes()

function Store.Get( material )
	local id = Store.MaterialIndex[ MaterialName( material ) ]
	return id and Store.Profiles[ id ] or nil, id
end

local function ProfileJSONSize( profile )
	local encoded = util.TableToJSON( profile )
	if not isstring( encoded ) then return nil, "could not encode RTX profile" end
	if #encoded > MAX_PROFILE_JSON then return nil, "RTX profile exceeds the 512 KiB limit" end
	return #encoded
end

-- Profile IDs describe captured texture ownership, not profile contents.  A
-- server-issued content token is therefore required to detect two admins
-- editing the same hash-backed profile concurrently.  Clients only echo this
-- opaque value; they never have to reproduce the server's JSON ordering.
local function ProfileETag( profile )
	if not istable( profile ) then return nil end
	local encoded = util.TableToJSON( profile )
	if not isstring( encoded ) then return nil end
	local digest = isfunction( util.SHA256 ) and util.SHA256( encoded )
		or ( isfunction( util.SHA1 ) and util.SHA1( encoded ) )
		or ( isfunction( util.MD5 ) and util.MD5( encoded ) )
		or util.CRC( encoded )
	if not isstring( digest ) then digest = tostring( digest or "" ) end
	return digest ~= "" and string.sub( digest, 1, 64 ) or nil
end

function Store.GetVersion( material )
	local profile, id = Store.Get( material )
	return id, ProfileETag( profile )
end

local function DatabaseJSON( profiles, tombstones, revision )
	local encoded = util.TableToJSON( {
		version = Store.PROTOCOL, saved = os.time(), revision = revision,
		profiles = profiles, tombstones = tombstones,
	}, true )
	if not isstring( encoded ) then return nil, "could not encode RTX profile database" end
	if #encoded > MAX_DATABASE_JSON then return nil, "RTX profile database exceeds the 8 MiB limit" end
	return encoded
end

local function IsCapablePlayer( ply )
	return IsValid( ply ) and ply.AdvMatRTXModeActive == true
		and ply.AdvMatRTXProtocol == Store.PROTOCOL
end

local function CapablePlayers()
	local targets = {}
	for _, ply in ipairs( player.GetAll() ) do
		if IsCapablePlayer( ply ) then
			targets[ #targets + 1 ] = ply
		end
	end
	return targets
end

local function EncodeProfileMessage( id, profile, removed, revision )
	local json = util.TableToJSON( {
		revision = revision or Store.Revision,
		id       = id,
		etag     = not removed and ProfileETag( profile ) or nil,
		removed  = removed == true,
		profile  = profile,
	} )
	if not isstring( json ) or #json > MAX_UNCOMPRESSED then
		return nil, "network JSON limit"
	end
	local data = util.Compress( json )
	if not isstring( data ) or #data > MAX_COMPRESSED then
		return nil, "compressed network payload limit"
	end
	return data
end

-- Each capable client owns an ordered output stream.  A stream emits at most
-- one message per interval, so PROFILE fragments cannot flood that client's
-- reliable net buffer.  Snapshot begin/profile/end controls use the same
-- queue, which makes SYNC_END a true delimiter rather than an early marker.
local outboundQueues = setmetatable( {}, { __mode = "k" } )
local pumpRunning = false

local function QueueEmpty( queue )
	return not queue or queue.first > queue.last
end

local function AnyOutbound()
	for ply, queue in pairs( outboundQueues ) do
		if not IsValid( ply ) or not IsCapablePlayer( ply ) or QueueEmpty( queue ) then
			outboundQueues[ ply ] = nil
		else
			return true
		end
	end
	return false
end

local PumpOutbound
local function EnsureOutboundPump()
	if pumpRunning then return end
	pumpRunning = true
	timer.Create( SEND_TIMER, SEND_INTERVAL, 0, function() PumpOutbound() end )
end

local function PushOutbound( ply, job )
	if not IsCapablePlayer( ply ) then return false end
	local queue = outboundQueues[ ply ]
	if not queue then
		queue = { first = 1, last = 0, items = {} }
		outboundQueues[ ply ] = queue
	end
	queue.last = queue.last + 1
	queue.items[ queue.last ] = job
	EnsureOutboundPump()
	return true
end

local function PopOutbound( queue )
	queue.items[ queue.first ] = nil
	queue.first = queue.first + 1
	if queue.first > queue.last then
		queue.first, queue.last, queue.items = 1, 0, {}
	end
end

local function ResetOutbound( ply )
	outboundQueues[ ply ] = nil
	if not AnyOutbound() then
		pumpRunning = false
		timer.Remove( SEND_TIMER )
	end
end

local function Recipients( target )
	local source
	if target == nil then
		source = CapablePlayers()
	-- Check an actual recipient array before the single-entity branch.  Test
	-- doubles and a few compatibility layers represent players as tables, where
	-- a permissive IsValid implementation would otherwise mistake the array
	-- itself for one player and silently drop a broadcast.
	elseif istable( target ) and #target > 0 then
		source = target
	elseif IsValid( target ) then
		source = { target }
	else
		source = {}
	end
	local result, seen = {}, {}
	for _, ply in ipairs( source ) do
		if IsCapablePlayer( ply ) and not seen[ ply ] then
			seen[ ply ] = true
			result[ #result + 1 ] = ply
		end
	end
	return result
end

PumpOutbound = function()
	for ply, queue in pairs( outboundQueues ) do
		if not IsCapablePlayer( ply ) then
			outboundQueues[ ply ] = nil
		else
			local job = queue.items[ queue.first ]
			if not job then
				outboundQueues[ ply ] = nil
			elseif job.kind == "profile" then
				local index = job.index
				local chunk = string.sub( job.data,
					( index - 1 ) * CHUNK_SIZE + 1, index * CHUNK_SIZE )
				net.Start( NET.PROFILE )
					net.WriteString( job.transfer )
					net.WriteUInt( index, 8 )
					net.WriteUInt( job.total, 8 )
					net.WriteUInt( #chunk, 17 )
					if #chunk > 0 then net.WriteData( chunk, #chunk ) end
				net.Send( ply )
				job.index = index + 1
				if job.index > job.total then PopOutbound( queue ) end
			elseif job.kind == "sync_begin" then
				net.Start( NET.SYNC_BEGIN )
					net.WriteUInt( job.revision % 4294967296, 32 )
					net.WriteUInt( job.count, 16 )
				net.Send( ply )
				PopOutbound( queue )
			elseif job.kind == "sync_end" then
				net.Start( NET.SYNC_END )
					net.WriteUInt( job.revision % 4294967296, 32 )
				net.Send( ply )
				PopOutbound( queue )
			elseif job.kind == "ack" then
				net.Start( NET.ACK )
					AdvMat.Net.WriteTable( job.message )
				net.Send( ply )
				PopOutbound( queue )
			else
				PopOutbound( queue )
			end
		end
	end
	if not AnyOutbound() then
		pumpRunning = false
		timer.Remove( SEND_TIMER )
	end
end

local function SendProfile( target, id, profile, removed )
	local recipients = Recipients( target )
	if #recipients == 0 then return end

	-- Cleanup messages retain the old target hashes.  Clients need those exact
	-- identities after the Source material renders with another base texture.
	local data, payloadError = EncodeProfileMessage( id, profile, removed )
	if not data then
		AdvMat.Log( "RTX profile %s exceeds the %s.", tostring( id ), tostring( payloadError ) )
		return false
	end

	Store.TransferID = Store.TransferID + 1
	local transfer = tostring( Store.Revision ) .. ":" .. tostring( Store.TransferID )
		.. ":" .. util.CRC( id or "" )
	local total = math.max( 1, math.ceil( #data / CHUNK_SIZE ) )
	for _, ply in ipairs( recipients ) do
		PushOutbound( ply, {
			kind = "profile", transfer = transfer,
			data = data, total = total, index = 1,
		} )
	end
	return true
end

local function SendAck( ply, nonce, ok, operation, id, profile, reason )
	if not IsValid( ply ) then return end
	PushOutbound( ply, {
		kind = "ack",
		message = {
			nonce    = isstring( nonce ) and string.sub( nonce, 1, 64 ) or "",
			ok       = ok == true,
			operation = operation,
			id       = id,
			etag     = profile and ProfileETag( profile ) or nil,
			-- The authoritative profile arrives through the chunked PROFILE
			-- broadcast.  Repeating it here would put large recipes back into a
			-- single 64 KiB message.
			profile  = nil,
			revision = Store.Revision,
			error    = reason,
		},
	} )
end

local function Notify( ply, message, kind )
	if not IsValid( ply ) then return end
	net.Start( NET.NOTIFY )
		net.WriteString( string.sub( tostring( message or "" ), 1, 512 ) )
		net.WriteUInt( isnumber( kind ) and math.Clamp( kind, 0, 7 ) or NOTIFY_GENERIC, 3 )
	net.Send( ply )
end

local CleanupProfile, FlushTombstones

local function QueueDiskSave( delay )
	if saveQueued or diskFailureCount >= MAX_AUTOMATIC_SAVE_ATTEMPTS then return end
	saveQueued = true
	timer.Create( "AdvMat.RTX.SaveDisk", delay or 1, 1, Store.SaveDisk )
end

local function DiskSaveFailed( reason, message )
	reason = tostring( reason or "unknown persistence failure" )
	dirty = true
	local previousReason, previousCount = diskFailureReason, diskFailureCount
	diskFailureReason = reason
	diskFailureCount = math.min( diskFailureCount + 1, MAX_AUTOMATIC_SAVE_ATTEMPTS )
	if diskFailureCount == 1 then
		AdvMat.Log( "%s", tostring( message or reason ) )
	elseif diskFailureCount == MAX_AUTOMATIC_SAVE_ATTEMPTS
		and previousCount < MAX_AUTOMATIC_SAVE_ATTEMPTS then
		AdvMat.Log( "RTX profile persistence is still failing (%s); automatic retries are now paused.",
			reason )
	elseif previousReason ~= reason then
		AdvMat.Log( "%s", tostring( message or reason ) )
	end
	if diskFailureCount < MAX_AUTOMATIC_SAVE_ATTEMPTS then
		QueueDiskSave( math.min( 5 * ( 2 ^ ( diskFailureCount - 1 ) ), 30 ) )
	end
	return false, reason
end

local function DiskSaveSucceeded()
	dirty, saveQueued = false, false
	diskFailureReason, diskFailureCount = nil, 0
	timer.Remove( "AdvMat.RTX.SaveDisk" )
end

local function RemoveDataFileVerified( path )
	if not file.Exists( path, "DATA" ) then return true end
	if not isfunction( file.Delete ) then return false end
	local ok = pcall( file.Delete, path )
	return ok and not file.Exists( path, "DATA" )
end

local function RenameDataFileVerified( source, destination, expected )
	if not isfunction( file.Rename ) then return false end
	local ok = pcall( file.Rename, source, destination )
	if not ok or file.Exists( source, "DATA" ) then return false end
	return file.Read( destination, "DATA" ) == expected
end

function Store.SaveDisk( profiles, tombstones, revision )
	saveQueued = false
	profiles = profiles or Store.Profiles
	tombstones = tombstones or Store.Tombstones
	revision = tonumber( revision ) or Store.Revision
	local encoded, encodeError = DatabaseJSON( profiles, tombstones, revision )
	if not encoded then
		return DiskSaveFailed( encodeError,
			"Could not save RTX profiles: " .. tostring( encodeError ) )
	end
	if not file.IsDir( AdvMat.DataFolder, "DATA" ) then file.CreateDir( AdvMat.DataFolder ) end

	-- Never replace the last known-good database until a complete temporary
	-- file can be read back.  file.Rename is atomic within Garry's Mod's DATA
	-- mount; the backup also recovers the narrow old->backup/new->live gap.
	local writeOK, writeResult = pcall( file.Write, Store.TempFile, encoded )
	if not writeOK or writeResult == false
		or file.Read( Store.TempFile, "DATA" ) ~= encoded then
		return DiskSaveFailed( "temporary RTX profile write could not be verified",
			"Could not verify temporary RTX profile database; keeping the previous file." )
	end

	-- Without Rename there is no atomic replacement primitive.  Treat that as
	-- a persistence failure instead of acknowledging a merely verified but
	-- tearable direct write.
	if not isfunction( file.Rename ) then
		if isfunction( file.Delete ) then file.Delete( Store.TempFile ) end
		return DiskSaveFailed( "atomic RTX profile database replacement is unavailable",
			"Could not install RTX profile database: atomic rename is unavailable." )
	end
	local hadLive = file.Exists( Store.DataFile, "DATA" )
	local previous = hadLive and file.Read( Store.DataFile, "DATA" ) or nil
	if hadLive and not isstring( previous ) then
		RemoveDataFileVerified( Store.TempFile )
		return DiskSaveFailed( "live RTX profile database could not be read",
			"Could not read the live RTX profile database; refusing to replace it." )
	end

	-- A stale backup must never participate in rollback.  Remove and verify it
	-- before moving the exact current live bytes into that name.  If either
	-- step fails, the live database has not been replaced and remains canonical.
	if hadLive then
		if not RemoveDataFileVerified( Store.BackupFile ) then
			RemoveDataFileVerified( Store.TempFile )
			return DiskSaveFailed( "stale RTX profile backup could not be removed",
				"Could not retire the stale RTX profile backup; keeping the live database." )
		end
		if not RenameDataFileVerified( Store.DataFile, Store.BackupFile, previous ) then
			-- Atomic rename should leave either source or destination intact.  If
			-- the provider moved the exact bytes but reported an odd state, restore
			-- only those bytes; never restore an older, unverified backup.
			if not file.Exists( Store.DataFile, "DATA" )
				and file.Read( Store.BackupFile, "DATA" ) == previous then
				RenameDataFileVerified( Store.BackupFile, Store.DataFile, previous )
			end
			RemoveDataFileVerified( Store.TempFile )
			return DiskSaveFailed( "live RTX profile database could not be staged",
				"Could not stage the live RTX profile database; replacement was cancelled." )
		end
	end

	local installed = RenameDataFileVerified( Store.TempFile, Store.DataFile, encoded )
	if not installed then
		-- Roll back only from the backup whose bytes were captured and verified
		-- immediately above.  A failed delete/rename can therefore never promote
		-- a stale backup over the latest acknowledged database.
		if hadLive and file.Read( Store.BackupFile, "DATA" ) == previous then
			RemoveDataFileVerified( Store.DataFile )
			RenameDataFileVerified( Store.BackupFile, Store.DataFile, previous )
		elseif not hadLive then
			RemoveDataFileVerified( Store.DataFile )
		end
		return DiskSaveFailed( "RTX profile database replacement failed",
			"Could not install RTX profile database; the store remains dirty." )
	end

	DiskSaveSucceeded()
	AdvMat.Log( "Saved %d RTX profile(s) and %d cleanup tombstone(s) to %s",
		AdvMat.TableCount( profiles ), AdvMat.TableCount( tombstones ), Store.DataFile )
	return true
end

local function MarkDirty()
	dirty = true
	-- Recovery/migration repairs can be deferred because no client mutation is
	-- awaiting an acknowledgement.  User Set/Clear operations use CommitState
	-- synchronously and never pass through this queue.
	QueueDiskSave( 1 )
end

-- A profile is authoritative as soon as the server acknowledges it.  Keep the
-- candidate state private until the complete database has survived the same
-- staged write/readback/rename verification used by manual saves.  This also
-- ensures a failed write cannot leak through a PROFILE broadcast before the
-- caller receives its negative acknowledgement.
local function CommitState( profiles, tombstones, revision )
	local saved, reason = Store.SaveDisk( profiles, tombstones, revision )
	if not saved then
		-- SaveDisk schedules a retry after an I/O failure.  Since the candidate
		-- was never installed, that retry writes the last acknowledged state.
		InstallIndexes()
		return false, "could not durably save RTX profile database: " .. ErrorText( reason )
	end

	Store.Profiles, Store.Tombstones, Store.Revision = profiles, tombstones, revision
	InstallIndexes()
	return true
end

local function DecodeDatabase( path )
	if not file.Exists( path, "DATA" ) then return nil end
	local raw = file.Read( path, "DATA" )
	if not isstring( raw ) or #raw > MAX_DATABASE_JSON then return nil end
	local decoded = util.JSONToTable( raw )
	if not istable( decoded ) or not istable( decoded.profiles ) then return nil end
	return decoded
end

function Store.LoadDisk()
	timer.Remove( "AdvMat.RTX.SaveDisk" )
	dirty, saveQueued = false, false
	diskFailureReason, diskFailureCount = nil, 0
	Store.Profiles, Store.Tombstones = {}, {}
	Store.Revision = 0
	local decoded = DecodeDatabase( Store.DataFile )
	local recovered = false
	if not decoded then
		decoded = DecodeDatabase( Store.BackupFile )
		recovered = decoded ~= nil
	end
	if not decoded then
		decoded = DecodeDatabase( Store.TempFile )
		recovered = decoded ~= nil
	end
	if not decoded then
		decoded = DecodeDatabase( Store.LegacyBackupFile )
		recovered = decoded ~= nil
	end
	if not decoded then
		decoded = DecodeDatabase( Store.LegacyTempFile )
		recovered = decoded ~= nil
	end
	if not decoded then
		InstallIndexes()
		AdvMat.Log( file.Exists( Store.DataFile, "DATA" )
			and "RTX profile database is corrupt and no valid backup exists."
			or "No RTX profile database yet, starting empty." )
		return
	end

	local hashOwners, materialOwners = {}, {}
	for _, candidate in pairs( decoded.profiles ) do
		local clean = SanitizeProfile( candidate )
		if clean and not ProfileJSONSize( clean ) then clean = nil end
		local id = clean and ProfileKey( clean ) or nil
		if id and not EncodeProfileMessage( id, clean, false,
			math.max( 0, math.floor( tonumber( decoded.revision ) or 0 ) ) ) then
			clean, id = nil, nil
		end
		local material = clean and MaterialName( clean ) or ""
		local conflict = material ~= "" and materialOwners[ material ] ~= nil
		for _, hash in ipairs( clean and TargetHashes( clean ) or {} ) do
			if hashOwners[ hash ] then conflict = true break end
		end
		if id and not conflict and not Store.Profiles[ id ] then
			Store.Profiles[ id ] = clean
			materialOwners[ material ] = id
			for _, hash in ipairs( TargetHashes( clean ) ) do hashOwners[ hash ] = id end
		end
	end

	for id, candidate in pairs( istable( decoded.tombstones ) and decoded.tombstones or {} ) do
		if AdvMat.TableCount( Store.Tombstones ) >= MAX_TOMBSTONES then break end
		local rawProfile = istable( candidate ) and ( candidate.profile or candidate ) or nil
		local clean = rawProfile and SanitizeProfile( rawProfile ) or nil
		if clean and not ProfileJSONSize( clean ) then clean = nil end
		local remaining = {}
		for _, hash in ipairs( clean and TargetHashes( clean ) or {} ) do
			if not hashOwners[ hash ] then remaining[ #remaining + 1 ] = hash end
		end
		if clean and #remaining > 0 then
			clean = CleanupProfile( clean, remaining )
			if clean and not EncodeProfileMessage( tostring( id ), clean, true,
				math.max( 0, math.floor( tonumber( decoded.revision ) or 0 ) ) ) then clean = nil end
		end
		if clean and #remaining > 0 then
			Store.Tombstones[ tostring( id ) ] = {
				profile = clean,
				created = math.max( 0, math.floor( tonumber( candidate.created ) or 0 ) ),
				revision = math.max( 0, math.floor( tonumber( candidate.revision ) or 0 ) ),
			}
		end
	end
	Store.Revision = math.max( 0, math.floor( tonumber( decoded.revision ) or 0 ) )
	InstallIndexes()
	if recovered or tonumber( decoded.version ) ~= Store.PROTOCOL then MarkDirty() end
	AdvMat.Log( "Loaded %d RTX profile(s) and %d cleanup tombstone(s)%s.",
		AdvMat.TableCount( Store.Profiles ), AdvMat.TableCount( Store.Tombstones ),
		recovered and " from backup" or "" )
	-- A tombstone surviving startup means the process may have stopped after
	-- committing cleanup but before delivering it.  Deliver it to every client
	-- which has completed the v3 capability handshake, then retire the journal
	-- entry.  With no capable clients, there is nobody carrying live state from
	-- this process; a later/rejoining client performs the mandatory native
	-- ClearAllOwned session reset before its first sync.
	if FlushTombstones then FlushTombstones() end
end

function Store.SendSnapshot( ply )
	if not IsCapablePlayer( ply ) then return end
	-- A repeated HELLO/resync supersedes every older queued message for this
	-- client. Capture cleanup first because FlushTombstones may durably prune it
	-- after enqueueing its live broadcast to the other capable clients.
	local snapshotTombstones = table.Copy( Store.Tombstones )
	ResetOutbound( ply )
	-- The joining player is capable now, so include it in a best-effort drain of
	-- any crash-recovery journal before building the authoritative snapshot.
	-- A failed prune leaves the tombstones below for an additional in-sync copy.
	if FlushTombstones then FlushTombstones() end
	-- Drop the joining player's pre-sync copy of that live broadcast; the exact
	-- captured entries are sent inside the ordered snapshot below. Other clients
	-- keep the broadcast queued normally.
	ResetOutbound( ply )

	local entries = {}
	for id, tombstone in SortedPairs( snapshotTombstones ) do
		if EncodeProfileMessage( id, tombstone.profile, true ) then
			entries[ #entries + 1 ] = { id = id, profile = tombstone.profile, removed = true }
		end
	end
	for id, profile in SortedPairs( Store.Profiles ) do
		if EncodeProfileMessage( id, profile, false ) then
			entries[ #entries + 1 ] = { id = id, profile = profile, removed = false }
		end
	end
	local count = math.min( #entries, 65535 )
	PushOutbound( ply, {
		kind = "sync_begin", revision = Store.Revision, count = count,
	} )

	-- Cleanup is intentionally delivered before active profiles.  A stale native
	-- override is removed first, then any newly claimed hashes are reapplied.
	for index = 1, count do
		local entry = entries[ index ]
		SendProfile( ply, entry.id, entry.profile, entry.removed )
	end

	PushOutbound( ply, { kind = "sync_end", revision = Store.Revision } )
end

local function ShallowCopy( source )
	local copy = {}
	for key, value in pairs( source or {} ) do copy[ key ] = value end
	return copy
end

local function HashSet( hashes )
	local set = {}
	for _, hash in ipairs( hashes or {} ) do set[ hash ] = true end
	return set
end

CleanupProfile = function( profile, hashes )
	if #hashes == 0 then return nil end
	local source = profile.target or {}
	-- Cleanup needs identity only.  Copying a large painted graph into every
	-- tombstone would exhaust the aggregate database limit after a few edits.
	local cleanup = {
		version = 1,
		target = {
			kind = source.kind or "material", material = source.material,
			model = source.model, slot = source.slot,
			hash = hashes[ 1 ], hashes = hashes,
		},
		pbr = {},
		graph = {
			nodes = { { id = "out", type = "output_surface", params = {}, x = 0, y = 0 } },
			links = {},
		},
	}
	return SanitizeProfile( cleanup )
end

local function AddTombstone( tombstones, profile, hashes, revision )
	local cleanup = CleanupProfile( profile, hashes )
	if not cleanup then return nil end
	if AdvMat.TableCount( tombstones ) >= MAX_TOMBSTONES then
		return nil, "RTX cleanup tombstone limit reached; clear pending cleanup before changing ownership"
	end
	local id = "rtx:cleanup:" .. tostring( revision ) .. ":" .. string.sub( hashes[ 1 ], 3 )
	tombstones[ id ] = { profile = cleanup, created = os.time(), revision = revision }
	return id, cleanup
end

local function ReconcileTombstones( tombstones, claimed )
	for id, tombstone in pairs( tombstones ) do
		local original = TargetHashes( tombstone.profile )
		if #original > 0 then
			local remaining = {}
			for _, hash in ipairs( original ) do
				if not claimed[ hash ] then remaining[ #remaining + 1 ] = hash end
			end
			if #remaining == 0 then
				tombstones[ id ] = nil
			elseif #remaining ~= #original then
				tombstone = table.Copy( tombstone )
				tombstone.profile = CleanupProfile( tombstone.profile, remaining )
				tombstones[ id ] = tombstone
			end
		end
	end
end

-- Tombstones are a durable delivery journal, not permanent history.  The
-- authoritative native bridge resets all addon-owned layers once per client
-- session, so disconnected clients do not need an unbounded server ledger.
-- A cleanup entry follows this ordering:
--
--   durable database -> all currently capable clients -> durable prune
--
-- If the server stops anywhere before the final write, LoadDisk sees the
-- tombstone and safely retries it.  Garry's Mod net messages are reliable; a
-- player which disconnects during delivery resets its native state on rejoin.
local function BroadcastTombstones()
	local delivered, refreshed, byMaterial = {}, {}, {}
	local targets = CapablePlayers()
	local hasTargets = #targets > 0
	for id, tombstone in SortedPairs( Store.Tombstones ) do
		-- The empty capable-client set is complete by definition.  Future clients
		-- are covered by protocol 1's required ClearAllOwned session reset.
		if not hasTargets or SendProfile( targets, id, tombstone.profile, true ) then
			delivered[ id ] = true
			local material = MaterialName( tombstone.profile )
			byMaterial[ material ] = byMaterial[ material ] or {}
			byMaterial[ material ][ #byMaterial[ material ] + 1 ] = id
		end
	end

	-- The client removes its material mirror before executing an exact-hash
	-- cleanup.  A retry from an earlier crash can therefore temporarily hide a
	-- newer active profile with the same material alias.  Always follow cleanup
	-- with the current authoritative profile for each affected material.  If
	-- that refresh cannot be encoded, retain its tombstones for a later retry.
	if hasTargets then
		for material, ids in pairs( byMaterial ) do
			local activeID = Store.MaterialIndex[ material ]
			local active = activeID and Store.Profiles[ activeID ] or nil
			if active then
				if SendProfile( targets, activeID, active, false ) then
					refreshed[ activeID ] = true
				else
					for _, id in ipairs( ids ) do delivered[ id ] = nil end
				end
			end
		end
	end
	return delivered, refreshed
end

local function PruneBroadcastTombstones( delivered )
	if not istable( delivered ) or next( delivered ) == nil then return true end
	local tombstones = ShallowCopy( Store.Tombstones )
	for id in pairs( delivered ) do tombstones[ id ] = nil end
	if AdvMat.TableCount( tombstones ) == AdvMat.TableCount( Store.Tombstones ) then return true end

	-- This housekeeping write deliberately does not advance the material
	-- revision.  Failure cannot invalidate the already durable user mutation:
	-- retain the journal entries in memory and on disk so a later drain retries.
	local saved, reason = Store.SaveDisk( Store.Profiles, tombstones, Store.Revision )
	if not saved then
		AdvMat.Log( "Could not prune delivered RTX cleanup tombstones: %s", ErrorText( reason ) )
		return false, reason
	end
	Store.Tombstones = tombstones
	return true
end

FlushTombstones = function()
	if next( Store.Tombstones ) == nil then return true end
	local delivered = BroadcastTombstones()
	return PruneBroadcastTombstones( delivered )
end

-- Exposed for diagnostics/tests and for a manual reload to retry housekeeping.
-- Mutations still call the local function directly so replacing this field
-- cannot weaken persistence-before-broadcast ordering.
Store.FlushTombstones = FlushTombstones

function Store.Set( rawProfile, expectedID, expectedETag )
	local profile, reason = SanitizeProfile( rawProfile )
	if not profile then return nil, reason end
	local size, sizeError = ProfileJSONSize( profile )
	if not size then return nil, sizeError end

	local id = ProfileKey( profile )
	if not id then return nil, "invalid material target" end
	local _, payloadError = EncodeProfileMessage( id, profile, false, Store.Revision + 1 )
	if payloadError then return nil, "RTX profile exceeds the " .. payloadError end
	local material = MaterialName( profile )
	local previousID = Store.MaterialIndex[ material ]
	-- Passing either expectation opts into compare-and-swap.  Empty strings are
	-- the explicit "no saved profile" token used by the wire protocol.
	if expectedID ~= nil or expectedETag ~= nil then
		local wantedID = isstring( expectedID ) and expectedID ~= "" and expectedID or nil
		local wantedETag = isstring( expectedETag ) and expectedETag ~= "" and expectedETag or nil
		local current = previousID and Store.Profiles[ previousID ] or nil
		local currentETag = ProfileETag( current )
		if wantedID ~= previousID or wantedETag ~= currentETag then
			return nil, "RTX profile changed; refresh before saving", previousID, currentETag
		end
	end
	for _, hash in ipairs( TargetHashes( profile ) ) do
		local owner = Store.HashOwners[ hash ]
		if owner and owner ~= previousID then
			local owned = Store.Profiles[ owner ]
			return nil, "captured hash " .. hash .. " is already owned by " .. MaterialName( owned )
		end
	end
	if Store.Profiles[ id ] and id ~= previousID then
		return nil, "captured hash identity is already owned by another RTX profile"
	end
	if not previousID
		and AdvMat.TableCount( Store.Profiles ) >= GetConVar( "advmat_rtx_max_profiles" ):GetInt() then
		return nil, "RTX profile limit reached"
	end

	-- Free journal capacity before constructing the candidate.  Failure is
	-- harmless: existing tombstones remain durable and AddTombstone's hard cap
	-- still prevents hostile/unbounded growth.
	FlushTombstones()

	local revision = Store.Revision + 1
	local profiles, tombstones = ShallowCopy( Store.Profiles ), table.Copy( Store.Tombstones )
	local previous = previousID and profiles[ previousID ] or nil
	if previousID then profiles[ previousID ] = nil end
	profiles[ id ] = profile

	local claimed = HashSet( TargetHashes( profile ) )
	ReconcileTombstones( tombstones, claimed )
	local cleanupID, cleanup
	if previous then
		local oldHashes = TargetHashes( previous )
		local retired = {}
		for _, hash in ipairs( oldHashes ) do
			if not claimed[ hash ] then retired[ #retired + 1 ] = hash end
		end
		if #retired > 0 then
			cleanupID, cleanup = AddTombstone( tombstones, previous, retired, revision )
			if not cleanupID then return nil, cleanup end
			local _, cleanupPayloadError = EncodeProfileMessage( cleanupID, cleanup, true, revision )
			if cleanupPayloadError then return nil, "RTX cleanup exceeds the " .. cleanupPayloadError end
		end
	end

	local _, databaseError = DatabaseJSON( profiles, tombstones, revision )
	if databaseError then return nil, databaseError end
	local committed, commitError = CommitState( profiles, tombstones, revision )
	if not committed then return nil, commitError end
	-- CommitState made every cleanup durable before either message.  Broadcast
	-- all pending cleanup first, publish the active profile, then durably prune
	-- only the cleanup entries which reached every currently capable client.
	local delivered, refreshed = BroadcastTombstones()
	if not refreshed[ id ] then SendProfile( nil, id, profile, false ) end
	PruneBroadcastTombstones( delivered )
	return profile, id
end

function Store.Clear( material, expectedID, expectedETag )
	material = MaterialName( material )
	local currentID = Store.MaterialIndex[ material ]
	-- Profile IDs describe captured-hash ownership and normally remain stable
	-- while an administrator edits the profile.  Clear therefore uses the same
	-- complete version pair as Save: the stable owner ID plus the opaque content
	-- token.  Passing either expectation opts direct callers into CAS; the net
	-- receiver below requires both to be present (or both explicitly absent).
	local hasExpectation = expectedID ~= nil or expectedETag ~= nil
	local wantedID = isstring( expectedID ) and expectedID ~= "" and expectedID or nil
	local wantedETag = isstring( expectedETag ) and expectedETag ~= "" and expectedETag or nil
	local current = currentID and Store.Profiles[ currentID ] or nil
	local currentETag = ProfileETag( current )
	if hasExpectation and ( wantedID ~= currentID or wantedETag ~= currentETag ) then
		return nil, "RTX profile changed; refresh before clearing", currentID, currentETag
	end
	local id = wantedID or currentID
	if not id then return nil, "invalid or unsaved material target" end
	local existing = Store.Profiles[ id ]
	if not existing then return nil, "profile does not exist", id end
	if MaterialName( existing ) ~= material then
		return nil, "RTX profile target changed; refresh before clearing", id
	end
	FlushTombstones()

	local revision = Store.Revision + 1
	local profiles, tombstones = ShallowCopy( Store.Profiles ), table.Copy( Store.Tombstones )
	profiles[ id ] = nil
	local cleanupID, cleanup = AddTombstone( tombstones, existing, TargetHashes( existing ), revision )
	if #TargetHashes( existing ) > 0 and not cleanupID then return nil, cleanup, id end
	if cleanupID then
		local _, cleanupPayloadError = EncodeProfileMessage( cleanupID, cleanup, true, revision )
		if cleanupPayloadError then return nil, "RTX cleanup exceeds the " .. cleanupPayloadError, id end
	end
	local _, databaseError = DatabaseJSON( profiles, tombstones, revision )
	if databaseError then return nil, databaseError, id end
	local committed, commitError = CommitState( profiles, tombstones, revision )
	if not committed then return nil, commitError, id end
	if cleanupID then
		local delivered = BroadcastTombstones()
		PruneBroadcastTombstones( delivered )
	else
		-- A material-only draft never owned native hashes, so a durable cleanup
		-- record would only consume tombstone capacity.  The live removal still
		-- lets connected export-only authors delete their local export file.
		SendProfile( nil, id, existing, true )
	end
	return existing, nil, id
end

-- Saving a complete material can produce several UI events close together.
-- A token bucket preserves one legitimate all-submaterial SaveAll burst while
-- limiting sustained hostile traffic.  Each transfer is still charged on its
-- first fragment before a reassembly buffer is allocated.
local EDIT_BURST = math.max( 32, tonumber( AdvMat.MAX_SUBMATERIALS ) or 0 )
local EDIT_REFILL = 2
local function TakeEditToken( ply )
	local now = CurTime()
	local tokens = math.min( EDIT_BURST,
		( ply.AdvMatRTXTokens or EDIT_BURST )
		+ ( now - ( ply.AdvMatRTXTokenAt or now ) ) * EDIT_REFILL )
	ply.AdvMatRTXTokenAt = now
	if tokens < 1 then
		ply.AdvMatRTXTokens = tokens
		return false
	end
	ply.AdvMatRTXTokens = tokens - 1
	return true
end

local saveBuffers = setmetatable( {}, { __mode = "k" } )

local function PendingCount( buffers )
	local count = 0
	for _ in pairs( buffers or {} ) do count = count + 1 end
	return count
end

local function PendingBytes( buffers )
	local bytes = 0
	for _, buffer in pairs( buffers or {} ) do bytes = bytes + ( tonumber( buffer.bytes ) or 0 ) end
	return bytes
end

local function PurgeSaveBuffers( onlyPlayer )
	local now = CurTime()
	for ply, buffers in pairs( saveBuffers ) do
		if not onlyPlayer or ply == onlyPlayer then
			for nonce, buffer in pairs( buffers ) do
				if not istable( buffer ) or ( tonumber( buffer.expires ) or 0 ) <= now then
					buffers[ nonce ] = nil
				end
			end
			if next( buffers ) == nil then saveBuffers[ ply ] = nil end
		end
	end
end

timer.Create( "AdvMat.RTX.PurgeSaveBuffers", 5, 0, PurgeSaveBuffers )

local function ReadSaveProfile( ply )
	local nonce = net.ReadString()
	if not isstring( nonce ) or #nonce < 1 or #nonce > 64
		or string.find( nonce, "[^%w_:%.%-]" ) then
		return nil, "", "invalid save nonce"
	end

	local expectedID = net.ReadString()
	local expectedETag = net.ReadString()
	if not isstring( expectedID ) or #expectedID > 300
		or not isstring( expectedETag ) or #expectedETag > 64 then
		return nil, nonce, "invalid save version"
	end
	if ( expectedID == "" ) ~= ( expectedETag == "" ) then
		return nil, nonce, "incomplete save version"
	end

	local index = net.ReadUInt( 8 )
	local total = net.ReadUInt( 8 )
	local length = net.ReadUInt( 17 )
	local left = net.BytesLeft and net.BytesLeft()
	if total < 1 or total > MAX_CHUNKS or index < 1 or index > total
		or length > CHUNK_SIZE or ( left and length > left ) then
		return nil, nonce, "invalid save fragment"
	end
	local chunk = length > 0 and net.ReadData( length ) or ""

	local buffers = saveBuffers[ ply ] or {}
	saveBuffers[ ply ] = buffers
	PurgeSaveBuffers( ply )
	buffers = saveBuffers[ ply ] or {}
	saveBuffers[ ply ] = buffers
	local buffer = buffers[ nonce ]
	if index == 1 then
		-- Charge once per transfer, before allocating a reassembly buffer or
		-- attempting decompression.  Charging in NET.SAVE after reassembly lets
		-- an otherwise valid client spend server CPU and memory before the rate
		-- limiter gets a say; charging every fragment rejects legitimate large
		-- profiles.  The first-fragment rule avoids both failure modes.
		if not TakeEditToken( ply ) then
			return nil, nonce, "RTX material edits are being sent too quickly."
		end
		if not buffer and PendingCount( buffers ) >= MAX_PENDING_PER_PLY then
			return nil, nonce, "too many pending RTX saves"
		end
		buffer = {
			total = total, parts = {}, bytes = 0, expires = CurTime() + BUFFER_TTL,
			expectedID = expectedID, expectedETag = expectedETag,
		}
		buffers[ nonce ] = buffer
	elseif not buffer then
		return nil, nonce, "save fragments arrived out of order"
	end

	if buffer.total ~= total or buffer.expectedID ~= expectedID
		or buffer.expectedETag ~= expectedETag or buffer.expires < CurTime() then
		buffers[ nonce ] = nil
		return nil, nonce, "inconsistent or expired RTX save"
	end

	local old = buffer.parts[ index ]
	buffer.parts[ index ] = chunk
	buffer.bytes = buffer.bytes - ( old and #old or 0 ) + #chunk
	-- Pacing intentionally makes transfer duration proportional to payload size;
	-- expiry is therefore inactivity-based and advances with every fragment.
	buffer.expires = CurTime() + BUFFER_TTL
	if buffer.bytes > MAX_COMPRESSED or PendingBytes( buffers ) > MAX_PENDING_BYTES then
		buffers[ nonce ] = nil
		return nil, nonce, "pending RTX profile payload limit exceeded"
	end

	for part = 1, total do
		if buffer.parts[ part ] == nil then return nil, nonce, nil end
	end
	buffers[ nonce ] = nil

	local data = table.concat( buffer.parts )
	local json = util.Decompress( data, MAX_UNCOMPRESSED )
	if not isstring( json ) or #json > MAX_PROFILE_JSON then
		return nil, nonce, "RTX profile exceeds the 512 KiB JSON limit"
	end
	local profile = json and util.JSONToTable( json )
	if not istable( profile ) then return nil, nonce, "could not decode RTX profile" end
	return profile, nonce, nil, buffer.expectedID, buffer.expectedETag
end

net.Receive( NET.HELLO, function( _, ply )
	if not IsValid( ply ) then return end
	local protocol = net.ReadUInt( 8 )
	-- Byte zero is an explicit mode-deactivation signal, not a capability
	-- mismatch.  A client can move from explicit RTX to auto/vanilla without
	-- reconnecting; retaining its old handshake would make server-side tool
	-- actions route into RTX solely because RTX had been active in the past.
	if protocol == 0 then
		ResetOutbound( ply )
		ply.AdvMatRTXProtocol = nil
		ply.AdvMatRTXModeActive = false
		ply.AdvMatRTXNextSync = nil
		saveBuffers[ ply ] = nil
		return
	end
	if protocol ~= Store.PROTOCOL then
		ResetOutbound( ply )
		ply.AdvMatRTXProtocol = nil
		ply.AdvMatRTXModeActive = false
		ply.AdvMatRTXNextSync = nil
		saveBuffers[ ply ] = nil
		Notify( ply, "RTX material protocol version mismatch.", NOTIFY_ERROR )
		return
	end

	ply.AdvMatRTXProtocol = protocol
	ply.AdvMatRTXModeActive = true
	if ( ply.AdvMatRTXNextSync or 0 ) > CurTime() then return end
	ply.AdvMatRTXNextSync = CurTime() + 2
	Store.SendSnapshot( ply )
end )

net.Receive( NET.SAVE, function( _, ply )
	if not IsCapablePlayer( ply ) then return end
	-- Authorization deliberately precedes fragment buffering, decompression and
	-- JSON decoding.  Read only the small nonce needed to correlate the refusal;
	-- Garry's Mod discards the unread remainder when this receiver returns.
	if not AdvMat.IsAllowed( ply ) then
		local nonce = net.ReadString()
		local reason = "You are not allowed to save RTX material profiles here."
		SendAck( ply, nonce, false, "save", nil, nil, reason )
		Notify( ply, reason, NOTIFY_ERROR )
		return
	end
	local incoming, nonce, fragmentError, expectedID, expectedETag = ReadSaveProfile( ply )
	if fragmentError then
		SendAck( ply, nonce, false, "save", nil, nil, fragmentError )
		return
	end
	if not incoming then return end -- more fragments are still in flight
	if AdvMat.Assets and isfunction( AdvMat.Assets.StoredEditsReady ) then
		local ready, assetError = AdvMat.Assets.StoredEditsReady( incoming )
		if not ready then
			SendAck( ply, nonce, false, "save", nil, nil, assetError )
			Notify( ply, "RTX profile rejected: " .. ErrorText( assetError ), NOTIFY_ERROR )
			return
		end
	end

	local profile, idOrError, currentID = Store.Set( incoming, expectedID, expectedETag )
	if not profile then
		local current = currentID and Store.Profiles[ currentID ] or nil
		SendAck( ply, nonce, false, "save", currentID, current, idOrError )
		Notify( ply, "RTX profile rejected: " .. ErrorText( idOrError ), NOTIFY_ERROR )
		return
	end

	SendAck( ply, nonce, true, "save", idOrError, profile )
end )

net.Receive( NET.CLEAR, function( _, ply )
	if not IsCapablePlayer( ply ) then return end
	-- Protocol v3 uses three bounded strings instead of the shared compressed
	-- table helper.  This keeps authorization ahead of JSON decompression.
	local nonce = net.ReadString()
	if not isstring( nonce ) or #nonce < 1 or #nonce > 64
		or string.find( nonce, "[^%w_:%.%-]" ) then return end
	if not AdvMat.IsAllowed( ply ) then
		local reason = "You are not allowed to clear RTX material profiles here."
		SendAck( ply, nonce, false, "clear", nil, nil, reason )
		Notify( ply, reason, NOTIFY_ERROR )
		return
	end
	if not TakeEditToken( ply ) then
		SendAck( ply, nonce, false, "clear", nil, nil, "RTX material edits are being sent too quickly." )
		return
	end
	local material = net.ReadString()
	local expectedID = net.ReadString()
	local expectedETag = net.ReadString()
	if not isstring( material ) or #material < 1 or #material > 260
		or not isstring( expectedID ) or #expectedID > 300
		or not isstring( expectedETag ) or #expectedETag > 64
		or ( ( expectedID == "" ) ~= ( expectedETag == "" ) ) then
		SendAck( ply, nonce, false, "clear", nil, nil, "invalid RTX clear target" )
		return
	end
	local old, reason, id = Store.Clear( material, expectedID, expectedETag )
	if not old then
		local current = id and Store.Profiles[ id ] or nil
		SendAck( ply, nonce, false, "clear", id, current, reason )
		return
	end
	SendAck( ply, nonce, true, "clear", id )
end )

hook.Add( "Initialize", "AdvMat.RTX.Load", Store.LoadDisk )
hook.Add( "ShutDown", "AdvMat.RTX.SaveOnShutdown", function()
	if dirty then Store.SaveDisk() end
end )
hook.Add( "PlayerDisconnected", "AdvMat.RTX.ForgetClient", function( ply )
	ResetOutbound( ply )
	ply.AdvMatRTXProtocol = nil
	ply.AdvMatRTXModeActive = nil
	ply.AdvMatRTXNextSync = nil
	saveBuffers[ ply ] = nil
end )

-- Lua autorefresh may load this after Initialize.
if AdvMat.TableCount( Store.Profiles ) == 0 and AdvMat.TableCount( Store.Tombstones ) == 0 then
	Store.LoadDisk()
end

local function ConsoleAllowed( ply )
	return not IsValid( ply ) or ply:IsSuperAdmin()
end

concommand.Add( "advmat_rtx_save", function( ply )
	if ConsoleAllowed( ply ) then Store.SaveDisk() end
end )

concommand.Add( "advmat_rtx_reload", function( ply )
	if not ConsoleAllowed( ply ) then return end
	Store.LoadDisk()
	for _, target in ipairs( CapablePlayers() ) do Store.SendSnapshot( target ) end
end )

concommand.Add( "advmat_rtx_list", function( ply )
	if not ConsoleAllowed( ply ) then return end
	for id, profile in SortedPairs( Store.Profiles ) do
		AdvMat.Log( "%s -> %s", id, profile.target.material )
	end
	AdvMat.Log( "%d RTX profile(s), %d cleanup tombstone(s) total.",
		AdvMat.TableCount( Store.Profiles ), AdvMat.TableCount( Store.Tombstones ) )
end )
