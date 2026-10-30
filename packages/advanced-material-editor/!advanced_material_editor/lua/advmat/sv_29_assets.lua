--[[---------------------------------------------------------------------------
	Advanced Material Editor - server cache/transport for generated edit PNGs
-----------------------------------------------------------------------------]]

AdvMat        = AdvMat or {}
AdvMat.Assets = AdvMat.Assets or {}

local A = AdvMat.Assets

local uploadBuffers = setmetatable( {}, { __mode = "k" } )

-- Retention. Every save of an edited texture caches a new immutable PNG, and
-- nothing used to delete one, so the folder only ever grew. See A.SweepEdits.
CreateConVar( "advmat_edit_retention_days", "30", { FCVAR_ARCHIVE },
	"Days the server keeps an edited texture that no saved override uses any more. 0 keeps them forever." )
CreateConVar( "advmat_edit_storage_mb", "1024", { FCVAR_ARCHIVE },
	"Most disk space the server's edited textures may use, in MB. 0 means no limit." )

A.EDIT_INDEX_FILE = "advmat/edit_index.json"
-- Nothing younger than this is ever removed, whatever the budget says: an
-- author uploads the texture first and saves the rule naming it afterwards.
A.EDIT_MIN_GRACE  = 6 * 3600
A.EDIT_SWEEP_EVERY = 6 * 3600

local MAX_PENDING_PER_PLAYER = 2
local MAX_PENDING_GLOBAL = 32
local REQUEST_BURST = 8
local REQUESTS_PER_SECOND = 4
local BEGIN_BURST = 8
local BEGINS_PER_SECOND = 4
local UPLOAD_MESSAGE_BURST = 16
local UPLOAD_MESSAGES_PER_SECOND = 8
local UPLOAD_BYTE_BURST = A.CHUNK_SIZE * 8
local UPLOAD_BYTES_PER_SECOND = A.CHUNK_SIZE * 3

-- GMod's reliable net channel has a small shared buffer.  A single 4K PNG can
-- be several MiB, so never emit every fragment in one frame.  Downloads are
-- served round-robin (one metadata/fragment message globally per tick); this
-- also keeps one large texture from starving all other players indefinitely.
local DOWNLOAD_INTERVAL = 0.35
local MAX_DOWNLOADS_PER_PLAYER = 8
local MAX_DOWNLOADS_GLOBAL = 64
local downloadQueue = {}
local downloadStats = setmetatable( {}, { __mode = "k" } )

local function PlayerUploadByteLimit()
	return math.max( A.MaxBytes(), math.min( A.HARD_MAX_BYTES, A.MaxBytes() * 2 ) )
end

local function GlobalUploadByteLimit()
	return math.max( A.MaxBytes(),
		math.min( A.HARD_MAX_BYTES * 4, A.MaxBytes() * 8 ) )
end

local function PlayerDownloadByteLimit()
	return PlayerUploadByteLimit()
end

local function GlobalDownloadByteLimit()
	return GlobalUploadByteLimit()
end

local function ConsumeBudget( ply, key, cost, burst, perSecond )
	if not IsValid( ply ) then return false end
	cost = math.max( 0, tonumber( cost ) or 0 )
	local now = CurTime()
	local budget = ply[ key ]
	if not istable( budget ) then budget = { tokens = burst, at = now } end
	budget.tokens = math.min( burst,
		( tonumber( budget.tokens ) or 0 )
			+ math.max( 0, now - ( tonumber( budget.at ) or now ) ) * perSecond )
	budget.at = now
	ply[ key ] = budget
	if budget.tokens < cost then return false end
	budget.tokens = budget.tokens - cost
	return true
end

local function MessageFits( bitLength, byteLimit )
	bitLength = tonumber( bitLength )
	return not bitLength or bitLength <= 0 or bitLength <= byteLimit * 8
end

local function PendingBytes( buffers )
	local total = 0
	for _, buffer in pairs( buffers or {} ) do total = total + ( buffer.bytes or 0 ) end
	return total
end

local function PendingCount( buffers )
	local total = 0
	for _ in pairs( buffers or {} ) do total = total + 1 end
	return total
end

local function ReservedBytes( buffers )
	local total = 0
	for _, buffer in pairs( buffers or {} ) do
		total = total + ( istable( buffer ) and istable( buffer.meta )
			and tonumber( buffer.meta.size ) or 0 )
	end
	return total
end

local function GlobalPending()
	local count, bytes = 0, 0
	for _, buffers in pairs( uploadBuffers ) do
		count = count + PendingCount( buffers )
		bytes = bytes + ReservedBytes( buffers )
	end
	return count, bytes
end

local function PurgeBuffers( onlyPlayer )
	local now = CurTime()
	for ply, buffers in pairs( uploadBuffers ) do
		if not onlyPlayer or ply == onlyPlayer then
			for target, buffer in pairs( buffers ) do
				if not istable( buffer ) or ( buffer.expires or 0 ) <= now then
					buffers[ target ] = nil
				end
			end
			if next( buffers ) == nil then uploadBuffers[ ply ] = nil end
		end
	end
end

timer.Create( "AdvMat.AssetPurge", 5, 0, PurgeBuffers )

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

local function SendFailure( channel, ply, target, reason )
	if not IsValid( ply ) then return end
	net.Start( channel )
		net.WriteString( isstring( target ) and target or "" )
		net.WriteString( isstring( reason ) and string.sub( reason, 1, 240 ) or "unavailable" )
	net.Send( ply )
end

local function SendReject( ply, target, reason )
	SendFailure( "AdvMat.AssetReject", ply, target, reason )
end

local function SendMiss( ply, target, reason )
	SendFailure( "AdvMat.AssetMiss", ply, target, reason )
end

local function SendBusy( ply, target, reason )
	-- A rejected request does not consume its main request budget.  Keep the
	-- negative response on a separate, deliberately small budget so a client
	-- cannot turn request throttling into an unlimited server->client stream.
	if not ConsumeBudget( ply, "AdvMatAssetBusyReplyBudget", 1, 8, 4 ) then return end
	SendFailure( "AdvMat.AssetBusy", ply, target, reason )
end

local function SendAck( ply, info )
	if not IsValid( ply ) or not istable( info ) then return end
	net.Start( "AdvMat.AssetAck" )
		net.WriteString( info.target or "" )
		net.WriteString( info.digest or "" )
	net.Send( ply )
end

local function DownloadTotals()
	local count, bytes = 0, 0
	for _, stats in pairs( downloadStats ) do
		count = count + ( tonumber( stats.count ) or 0 )
		bytes = bytes + ( tonumber( stats.bytes ) or 0 )
	end
	return count, bytes
end

local function ReleaseDownload( job )
	if not istable( job ) then return end
	local stats = downloadStats[ job.ply ]
	if not istable( stats ) then return end
	stats.count = math.max( 0, ( tonumber( stats.count ) or 0 ) - 1 )
	stats.bytes = math.max( 0, ( tonumber( stats.bytes ) or 0 ) - ( job.bytes or 0 ) )
	if istable( stats.targets ) then stats.targets[ job.meta.target ] = nil end
	if stats.count <= 0 then downloadStats[ job.ply ] = nil end
end

local function QueueAsset( meta, png, recipient )
	if not IsValid( recipient ) or not istable( meta ) or not isstring( png ) then
		return false, "invalid generated edit transfer"
	end
	if not A.ValidTarget( meta.target ) then
		return false, "generated edit path is unsafe"
	end
	local wireSafe, wireReason = A.MetaWireSafe( meta )
	if not wireSafe then return false, wireReason end
	if #png ~= tonumber( meta.size ) then
		return false, "generated edit length does not match"
	end
	if meta.digest ~= A.Digest( png ) then
		return false, "generated edit digest does not match"
	end

	local stats = downloadStats[ recipient ]
	if not istable( stats ) then stats = { count = 0, bytes = 0, targets = {} } end
	-- Repeated requests while an exact target is already queued are harmless.
	-- Do not duplicate the PNG string or restart the receiver's ordered stream.
	if stats.targets[ meta.target ] then return true end
	local globalCount, globalBytes = DownloadTotals()
	if stats.count >= MAX_DOWNLOADS_PER_PLAYER
		or globalCount >= MAX_DOWNLOADS_GLOBAL then
		return false, "generated edit transfer queue is full"
	end
	if stats.bytes + #png > PlayerDownloadByteLimit()
		or globalBytes + #png > GlobalDownloadByteLimit() then
		return false, "generated edit transfer byte limit exceeded"
	end

	A.TouchEdit( meta.target )

	local job = {
		ply = recipient, meta = meta, png = png, bytes = #png,
		index = 0, total = math.max( 1, math.ceil( #png / A.CHUNK_SIZE ) ),
	}
	stats.count = stats.count + 1
	stats.bytes = stats.bytes + #png
	stats.targets[ meta.target ] = job
	downloadStats[ recipient ] = stats
	downloadQueue[ #downloadQueue + 1 ] = job
	return true
end

local function PumpDownloads()
	local job
	while #downloadQueue > 0 do
		job = table.remove( downloadQueue, 1 )
		if IsValid( job.ply ) then break end
		ReleaseDownload( job )
		job = nil
	end
	if not job then return end

	if job.index == 0 then
		net.Start( "AdvMat.AssetBegin" )
			AdvMat.Net.WriteTable( job.meta )
		net.Send( job.ply )
		job.index = 1
		downloadQueue[ #downloadQueue + 1 ] = job
		return
	end

	local index = job.index
	local chunk = string.sub( job.png,
		( index - 1 ) * A.CHUNK_SIZE + 1, index * A.CHUNK_SIZE )
	net.Start( "AdvMat.AssetChunk" )
		net.WriteString( job.meta.target )
		net.WriteUInt( index, 16 )
		net.WriteUInt( job.total, 16 )
		net.WriteUInt( #chunk, 17 )
		if #chunk > 0 then net.WriteData( chunk, #chunk ) end
	net.Send( job.ply )

	job.index = index + 1
	if job.index <= job.total then
		downloadQueue[ #downloadQueue + 1 ] = job
	else
		ReleaseDownload( job )
	end
end

timer.Create( "AdvMat.AssetDownloadPump", DOWNLOAD_INTERVAL, 0, PumpDownloads )

local function InstallUpload( ply, buffer )
	local png = table.concat( buffer.parts )
	if #png ~= buffer.meta.size then return nil, "generated edit length does not match" end
	local info, reason = A.ValidatePNG( buffer.meta.recipe, png, buffer.meta.digest )
	if not info then return nil, reason end

	-- A recipe target is immutable for the server session/database. Without
	-- this check, two allowed authors could race different pixels under the
	-- same recipe hash and make an ACK-gated rule resolve to somebody else's
	-- bytes. Builder revisions already mint a new target when output semantics
	-- intentionally change.
	local existing = file.Read( info.target, "DATA" )
	local cached = existing and A.ValidatePNG( info.recipe, existing ) or nil
	-- CRC+length is a portable transport hint, not a collision-resistant
	-- identity. Both payloads are resident here, so immutable-target equality
	-- must be decided byte-for-byte before acknowledging the author's rule.
	if cached and ( cached.digest ~= info.digest or existing ~= png ) then
		return nil, "server already cached different pixels for this edit recipe"
	end
	if cached then
		png, info = existing, cached
	else
		EnsureDir( info.target )
		file.Write( info.target, png )
		if file.Read( info.target, "DATA" ) ~= png then
			return nil, "server could not cache the generated edit"
		end
	end

	A.TouchEdit( info.target )
	AdvMat.Log( "Cached multiplayer edited texture %s (%d bytes).", info.target, #png )
	return info
end

net.Receive( "AdvMat.AssetBegin", function( bitLength, ply )
	-- Authorization precedes metadata decompression and buffer allocation.
	if not IsValid( ply ) or not AdvMat.IsAllowed( ply ) then return end
	if not MessageFits( bitLength, A.MAX_META_BYTES + 8 ) then return end
	-- Charge a begin token before decompressing attacker-controlled metadata.
	if not ConsumeBudget( ply, "AdvMatAssetBeginBudget", 1,
		BEGIN_BURST, BEGINS_PER_SECOND ) then
		return
	end
	local raw = AdvMat.Net.ReadTable()
	local meta, reason = A.ValidateMeta( raw )
	if not meta then
		SendReject( ply, istable( raw ) and raw.target or "", reason )
		return
	end
	local wireSafe, wireReason = A.MetaWireSafe( meta )
	if not wireSafe then
		SendReject( ply, meta.target, wireReason )
		return
	end

	-- In a listen server the host's client and server realms use the same DATA
	-- directory. The texture editor has therefore already written the very file
	-- the server would otherwise spend many seconds receiving in 30 kB packets.
	-- This shortcut is intentionally restricted to IsListenServerHost: remote
	-- clients have independent filesystems and must still upload every byte.
	-- Full PNG/container/dimension/digest validation keeps the same durable-cache
	-- gate as an ordinary completed upload.
	local listenHost = isfunction( ply.IsListenServerHost )
		and ply:IsListenServerHost()
	if listenHost then
		local shared = file.Read( meta.target, "DATA" )
		local info = shared and A.ValidatePNG( meta.recipe, shared, meta.digest ) or nil
		if info then
			SendAck( ply, info )
			return
		end
	end

	PurgeBuffers()
	local buffers = uploadBuffers[ ply ] or {}
	uploadBuffers[ ply ] = buffers
	if buffers[ meta.target ] then
		SendReject( ply, meta.target, "generated edit is already uploading" )
		return
	end
	if not buffers[ meta.target ] and PendingCount( buffers ) >= MAX_PENDING_PER_PLAYER then
		SendReject( ply, meta.target, "too many generated edits are uploading" )
		return
	end
	local globalCount, globalBytes = GlobalPending()
	if globalCount >= MAX_PENDING_GLOBAL
		or ReservedBytes( buffers ) + meta.size > PlayerUploadByteLimit()
		or globalBytes + meta.size > GlobalUploadByteLimit() then
		SendReject( ply, meta.target, "pending generated edit limit exceeded" )
		return
	end
	buffers[ meta.target ] = {
		meta = meta, parts = {}, bytes = 0, expires = CurTime() + A.BUFFER_TTL,
	}
end )

net.Receive( "AdvMat.AssetChunk", function( bitLength, ply )
	if not IsValid( ply ) or not AdvMat.IsAllowed( ply ) then return end
	if not MessageFits( bitLength, A.CHUNK_SIZE + 256 ) then return end
	local target = net.ReadString()
	local index  = net.ReadUInt( 16 )
	local total  = net.ReadUInt( 16 )
	local length = net.ReadUInt( 17 )
	local left = net.BytesLeft and net.BytesLeft()
	local maxChunks = math.max( 1, math.ceil( A.MaxBytes() / A.CHUNK_SIZE ) )
	if not A.ValidTarget( target ) or total < 1 or total > maxChunks
		or index < 1 or index > total or length > A.CHUNK_SIZE
		or ( left and length > left ) then return end

	local buffers = uploadBuffers[ ply ]
	local buffer = buffers and buffers[ target ]
	if not buffer or buffer.expires <= CurTime() then return end
	-- Meter bytes before allocating/copying the fragment.  Exceeding the rate
	-- cancels this upload so subsequent reliable fragments cannot accumulate.
	if not ConsumeBudget( ply, "AdvMatAssetUploadMessageBudget", 1,
		UPLOAD_MESSAGE_BURST, UPLOAD_MESSAGES_PER_SECOND )
		or not ConsumeBudget( ply, "AdvMatAssetUploadByteBudget", length,
		UPLOAD_BYTE_BURST, UPLOAD_BYTES_PER_SECOND ) then
		buffers[ target ] = nil
		SendReject( ply, target, "generated edit upload rate exceeded" )
		return
	end
	local chunk = length > 0 and net.ReadData( length ) or ""
	if not isstring( chunk ) or #chunk ~= length then
		buffers[ target ] = nil
		SendReject( ply, target, "generated edit fragment is truncated" )
		return
	end
	buffer.expires = CurTime() + A.BUFFER_TTL
	local expectedTotal = math.max( 1, math.ceil( buffer.meta.size / A.CHUNK_SIZE ) )
	if total ~= expectedTotal then
		buffers[ target ] = nil
		SendReject( ply, target, "generated edit fragments are inconsistent" )
		return
	end
	-- Reliable net traffic is ordered. Requiring the next sequential fragment
	-- prevents sparse tables, duplicate replacement and allocation games.
	if index ~= #buffer.parts + 1 then
		buffers[ target ] = nil
		SendReject( ply, target, "generated edit fragments arrived out of order" )
		return
	end
	buffer.parts[ index ] = chunk
	buffer.bytes = buffer.bytes + #chunk
	if buffer.bytes > buffer.meta.size
		or PendingBytes( buffers ) > PlayerUploadByteLimit() then
		buffers[ target ] = nil
		SendReject( ply, target, "pending generated edit limit exceeded" )
		return
	end
	if index < total then return end

	buffers[ target ] = nil
	local info, reason = InstallUpload( ply, buffer )
	if reason then
		SendReject( ply, target, reason )
	else
		-- A material rule must not be committed until the author knows the
		-- server has validated and read back the complete immutable PNG.
		SendAck( ply, info )
	end
end )

local function DownloadAlreadyQueued( ply, target )
	local stats = downloadStats[ ply ]
	return istable( stats ) and istable( stats.targets ) and stats.targets[ target ] ~= nil
end

local function DownloadHasCapacity( ply, knownBytes )
	local stats = downloadStats[ ply ]
	local playerCount = istable( stats ) and ( tonumber( stats.count ) or 0 ) or 0
	local playerBytes = istable( stats ) and ( tonumber( stats.bytes ) or 0 ) or 0
	local globalCount, globalBytes = DownloadTotals()
	if playerCount >= MAX_DOWNLOADS_PER_PLAYER
		or globalCount >= MAX_DOWNLOADS_GLOBAL then return false end
	knownBytes = math.max( 0, tonumber( knownBytes ) or 0 )
	return playerBytes + knownBytes <= PlayerDownloadByteLimit()
		and globalBytes + knownBytes <= GlobalDownloadByteLimit()
end

local function CompactMeta( target, png )
	if not A.ValidTarget( target ) then return nil, "generated edit path is unsafe" end
	if not isstring( png ) or #png < 45 or #png > A.MaxBytes()
		or string.sub( png, 1, 8 ) ~= "\137PNG\13\10\26\10" then
		return nil, "server cached generated edit is invalid"
	end
	return { target = target, size = #png, digest = A.Digest( png ) }
end

net.Receive( "AdvMat.AssetRequest", function( bitLength, ply )
	if not IsValid( ply ) then return end
	if not MessageFits( bitLength, 256 ) then return end

	local target = net.ReadString()
	if not A.ValidTarget( target ) then return end
	if DownloadAlreadyQueued( ply, target ) then return end
	-- The bounded request is only one canonical target string. Read it first so
	-- a throttled legitimate client receives a retryable Busy for the active
	-- target instead of falling back to a renderer-dependent local rebuild.
	if not ConsumeBudget( ply, "AdvMatAssetRequestBudget", 1,
		REQUEST_BURST, REQUESTS_PER_SECOND ) then
		SendBusy( ply, target, "generated edit request limit exceeded" )
		return
	end
	if not DownloadHasCapacity( ply ) then
		SendBusy( ply, target, "generated edit transfer queue is full" )
		return
	end
	-- If the branch exposes file.Size, reject an oversized/cap-exhausting file
	-- before file.Read allocates it.  The full bytes are still checked below on
	-- older branches where only file.Read is available.
	if isfunction( file.Size ) then
		local diskBytes = tonumber( file.Size( target, "DATA" ) ) or -1
		if diskBytes > A.MaxBytes() or ( diskBytes >= 0 and not DownloadHasCapacity( ply, diskBytes ) ) then
			SendBusy( ply, target, "generated edit transfer byte limit exceeded" )
			return
		end
	end

	local png = file.Read( target, "DATA" )
	local meta, reason = CompactMeta( target, png )
	if not meta then
		SendMiss( ply, target, reason or "server has no cached generated edit" )
		return
	end
	local queued, queueReason = QueueAsset( meta, png, ply )
	if not queued then SendBusy( ply, target, queueReason ) end
end )

---------------------------------------------------------------------------
-- Retention
---------------------------------------------------------------------------
-- A file is kept while any stored override or RTX profile names it, or while
-- a transfer of it is in flight. One that nothing names any more is kept for
-- advmat_edit_retention_days, counted from the last moment something did -
-- a pasted dupe or an old save can still bring a texture back - and is then
-- removed. While the folder is over advmat_edit_storage_mb, the files unused
-- longest go first. Nothing younger than EDIT_MIN_GRACE goes for either reason.

local lastUse   -- [target] = os.time() it was last uploaded, served or named

local function EditIndex()
	if lastUse then return lastUse end
	lastUse = {}

	local raw = file.Read( A.EDIT_INDEX_FILE, "DATA" )
	local tbl = isstring( raw ) and util.JSONToTable( raw ) or nil
	if istable( tbl ) and istable( tbl.seen ) then
		for target, at in pairs( tbl.seen ) do
			if A.ValidTarget( target ) and tonumber( at ) then lastUse[ target ] = tonumber( at ) end
		end
	end

	return lastUse
end

local function SaveEditIndex()
	if not lastUse then return end
	EnsureDir( A.EDIT_INDEX_FILE )
	file.Write( A.EDIT_INDEX_FILE, util.TableToJSON( { version = 1, seen = lastUse } ) )
end

--- Note that `target` was just uploaded or handed to a client.
function A.TouchEdit( target )
	if not A.ValidTarget( target ) then return end
	EditIndex()[ target ] = os.time()
end

--- Every edited texture something still needs.
local function ReferencedEdits()
	local refs = {}
	local function Collect( value )
		for target in pairs( A.EditRecipes( value ) ) do refs[ target ] = true end
	end

	local Store = AdvMat.Store
	if Store then
		for _, rule in pairs( Store.Rules or {} ) do Collect( rule.gen ) end
		for _, set in pairs( Store.EntityRules or {} ) do
			for _, rule in pairs( set ) do Collect( rule.gen ) end
		end
	end

	local RTX = AdvMat.RTXStore
	if RTX then
		for _, profile in pairs( RTX.Profiles or {} ) do Collect( profile ) end
	end

	-- Mid-transfer: an upload not installed yet, or a download still queued.
	for _, buffers in pairs( uploadBuffers ) do
		for target in pairs( buffers ) do refs[ target ] = true end
	end
	for _, job in ipairs( downloadQueue ) do
		if istable( job.meta ) then refs[ job.meta.target ] = true end
	end

	return refs
end

--- Apply the retention policy now. Returns how many files were removed and
--- how many bytes that freed.
function A.SweepEdits( now )
	now = now or os.time()

	local seen   = EditIndex()
	local refs   = ReferencedEdits()
	local days   = math.max( 0, GetConVar( "advmat_edit_retention_days" ):GetInt() )
	local budget = math.max( 0, GetConVar( "advmat_edit_storage_mb" ):GetInt() ) * 1048576

	local files, total, present = {}, 0, {}
	for _, name in ipairs( file.Find( "advmat/edits/*.png", "DATA" ) or {} ) do
		local target = "advmat/edits/" .. name
		if A.ValidTarget( target ) then
			-- A file the index has never seen - everything, the first time a
			-- server runs this - starts its clock now rather than from when it
			-- was written, so an upgrade never sweeps away a whole old cache.
			if refs[ target ] or not seen[ target ] then seen[ target ] = now end

			local size = tonumber( file.Size( target, "DATA" ) ) or 0
			files[ #files + 1 ] = {
				target = target, size = size, used = seen[ target ], referenced = refs[ target ],
			}
			total = total + size
			present[ target ] = true
		end
	end

	-- Forget files that are gone.
	for target in pairs( seen ) do
		if not present[ target ] then seen[ target ] = nil end
	end

	local removed, freed = 0, 0
	local function Remove( f )
		pcall( file.Delete, f.target )
		if file.Exists( f.target, "DATA" ) then return end
		seen[ f.target ] = nil
		f.gone = true
		removed, freed, total = removed + 1, freed + f.size, total - f.size
	end

	if days > 0 then
		local limit = math.max( days * 86400, A.EDIT_MIN_GRACE )
		for _, f in ipairs( files ) do
			if not f.referenced and now - f.used > limit then Remove( f ) end
		end
	end

	if budget > 0 and total > budget then
		table.sort( files, function( a, b ) return a.used < b.used end )
		for _, f in ipairs( files ) do
			if total <= budget then break end
			if not f.gone and not f.referenced and now - f.used > A.EDIT_MIN_GRACE then Remove( f ) end
		end
	end

	SaveEditIndex()

	if removed > 0 then
		AdvMat.Log( "Removed %d unused edited texture(s), freeing %.1f MB.", removed, freed / 1048576 )
	end
	if budget > 0 and total > budget then
		AdvMat.Log( "Edited textures use %.1f MB, over advmat_edit_storage_mb; everything left is in use or recent.",
			total / 1048576 )
	end

	return removed, freed
end

timer.Create( "AdvMat.EditRetention", A.EDIT_SWEEP_EVERY, 0, function() A.SweepEdits() end )
-- The first pass waits for the stores to load and the first saves to settle.
timer.Simple( 120, function() A.SweepEdits() end )

concommand.Add( "advmat_edit_cleanup", function( ply )
	if IsValid( ply ) and not ply:IsSuperAdmin() then return end
	local removed, freed = A.SweepEdits()
	AdvMat.Log( "advmat_edit_cleanup: removed %d file(s), %.1f MB.", removed, freed / 1048576 )
end )

hook.Add( "ShutDown", "AdvMat.EditIndex", SaveEditIndex )

hook.Add( "PlayerDisconnected", "AdvMat.AssetBuffers", function( ply )
	uploadBuffers[ ply ] = nil
	local keep = {}
	for _, job in ipairs( downloadQueue ) do
		if job.ply == ply then
			ReleaseDownload( job )
		else
			keep[ #keep + 1 ] = job
		end
	end
	downloadQueue = keep
	downloadStats[ ply ] = nil
end )
