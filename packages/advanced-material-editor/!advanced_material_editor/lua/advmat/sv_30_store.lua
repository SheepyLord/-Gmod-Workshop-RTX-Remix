--[[---------------------------------------------------------------------------
	Advanced Material Editor - serverside authoritative store

	Two kinds of override live here:

	  * Persistent rules (MODEL / MATERIAL / WORLD scope) are kept in a JSON
	    file under garrysmod/data/advmat/overrides.json and are broadcast to
	    every client on join. These are what make an edit "remembered and
	    automatically applied in the future".

	  * Entity rules (ENTITY scope) are attached to a single entity. They are
	    registered as a duplicator entity modifier so they survive copy/paste,
	    dupes and map save/load, and are re-broadcast whenever the entity is
	    recreated.

	Whichever way a rule arrives - an editor save, a pasted dupe, the tool gun
	- it passes the same checks (Prepare) before the store will hold it.

	Revisions. Every broadcast advances Store.Revision and carries it, and a
	snapshot carries the revision it was built at. A snapshot is paced out over
	several seconds while ordinary broadcasts keep flowing, so a joining client
	can hear about a newer change before the older snapshot has finished. With
	the revisions it replays that change on top of the snapshot instead of
	losing it.

	Durability. The database file is only ever replaced by a temporary copy
	that has been written and read back, and the old file is kept aside until
	the new one is in place. A failed write leaves the store dirty and retries.
	The saving player hears "applied" once the world shows the change, and
	"persisted" only once it is actually on disk.

	Size. The rules together must fit in a snapshot every client will unpack,
	so the store refuses an edit that would push it past that budget.

	Conflicts. An editor can name the version of a rule it loaded (a content
	token, AdvMat.RuleToken). If the stored rule has changed since, the save is
	refused rather than silently replacing somebody else's newer change.
-----------------------------------------------------------------------------]]

AdvMat       = AdvMat or {}
AdvMat.Store = AdvMat.Store or {}

local Store = AdvMat.Store

Store.Rules       = Store.Rules       or {}  -- [ruleID]   = rule  (persistent)
Store.EntityRules = Store.EntityRules or {}  -- [entIndex] = { [subIndex] = rule }

-- Kept across a Lua autorefresh, so a connected client never sees the
-- sequence go backwards.
Store.Revision     = tonumber( Store.Revision ) or 0      -- advanced by every broadcast
Store.DiskRevision = tonumber( Store.DiskRevision ) or 0  -- newest revision known to be on disk

-- file.Write and file.Rename only take an allow-listed extension, which is
-- whatever follows the LAST dot, so every file taking part in a save ends in
-- .json (the RTX store's files are named the same way for the same reason).
Store.BackupFile   = "advmat/overrides.backup.json"
Store.TempFile     = "advmat/overrides.pending.json"
Store.CorruptFile  = "advmat/overrides.corrupt.json"
Store.OverflowFile = "advmat/overrides.overflow.json"

-- A client will not unpack a snapshot larger than AdvMat.Net.MAX_SYNC_SIZE.
-- Holding the rules to three quarters of that leaves room for the snapshot's
-- own framing, so a database the server accepted is one every client can load.
Store.MAX_DATABASE_BYTES = math.floor( AdvMat.Net.MAX_SYNC_SIZE * 0.75 )

-- The reason given when a save was based on an outdated version. Clients are
-- told it is a conflict separately, so the text is only for people.
Store.CONFLICT = "somebody else changed this material after you loaded it"

-- The wiki explicitly recommends a verbose modifier name: the registry is
-- global and a collision silently hijacks another addon's modifier.
local DUPE_MODIFIER = "Advanced Material Editor - submaterials"

---------------------------------------------------------------------------
-- Messages
---------------------------------------------------------------------------
local function Notify( ply, msg, kind )
	if not IsValid( ply ) then return end
	-- Guard the payload: anything that throws between net.Start and net.Send
	-- leaves the message open, and the next net.Start discards it.
	local kindNum = isnumber( kind ) and math.Clamp( kind, 0, 7 ) or NOTIFY_GENERIC

	net.Start( "AdvMat.Notify" )
		net.WriteString( isstring( msg ) and msg or tostring( msg ) )
		net.WriteUInt( kindNum, 3 )
	net.Send( ply )
end

AdvMat.Notify = Notify

---------------------------------------------------------------------------
-- Size
---------------------------------------------------------------------------
-- What a stored rule costs inside a snapshot, measured once per rule table.
-- Weak keys: a replaced or removed rule simply drops out.
local ruleBytes = setmetatable( {}, { __mode = "k" } )

-- A snapshot frames each rule with its quoted id or slot number, a colon and
-- a comma, and for entity rules a share of the per-entity object around them.
-- This overcounts a little, which only makes the budget safer.
local RULE_FRAMING = 64

local function RuleBytes( rule )
	local n = ruleBytes[ rule ]
	if n then return n end

	local json = util.TableToJSON( rule )
	n = ( isstring( json ) and #json or 0 ) + RULE_FRAMING
	ruleBytes[ rule ] = n
	return n
end

--- Bytes the stored rules would take up in a snapshot. `skipRule` is a rule
--- about to be replaced and `skipEntity` an entity whose whole set is, so
--- neither is counted twice.
function Store.DatabaseBytes( skipRule, skipEntity )
	local total = 0

	for _, rule in pairs( Store.Rules ) do
		if rule ~= skipRule then total = total + RuleBytes( rule ) end
	end

	for entIndex, set in pairs( Store.EntityRules ) do
		if entIndex ~= skipEntity then
			for _, rule in pairs( set ) do
				if rule ~= skipRule then total = total + RuleBytes( rule ) end
			end
		end
	end

	return total
end

--- Every rule is broadcast in a single net message.
local function FitsOneMessage( rule )
	local json   = util.TableToJSON( rule )
	local packed = isstring( json ) and util.Compress( json ) or nil
	return isstring( packed ) and #packed <= AdvMat.Net.MAX_RULE_WIRE
end

---------------------------------------------------------------------------
-- Disk I/O
---------------------------------------------------------------------------
local dirty, saveQueued = false, false
local failureReason, failureCount = nil, 0

-- Automatic retries back off and then stop; a new edit or advmat_save still
-- tries again, so a disk that comes back is used without a restart.
local MAX_AUTOMATIC_ATTEMPTS = 4
local SAVE_DELAY = 2   -- coalesces a burst of edits (one Save is one per slot) into one write
local SAVE_TIMER = "AdvMat.Save"

-- Players waiting to hear that their change reached the disk, mapped to the
-- revision that has to be written first, and whether they have already been
-- told it is failing. Weak keys: a player who leaves simply drops out.
local diskWaiters = setmetatable( {}, { __mode = "k" } )
local diskWarned  = setmetatable( {}, { __mode = "k" } )

local function RemoveVerified( path )
	if not file.Exists( path, "DATA" ) then return true end
	if not isfunction( file.Delete ) then return false end
	local ok = pcall( file.Delete, path )
	return ok and not file.Exists( path, "DATA" )
end

local function RenameVerified( source, destination, expected )
	if not isfunction( file.Rename ) then return false end
	local ok = pcall( file.Rename, source, destination )
	if not ok or file.Exists( source, "DATA" ) then return false end
	return file.Read( destination, "DATA" ) == expected
end

--- Replace the live database with `encoded`, or leave the old file exactly as
--- it was. Returns true, or false plus a reason.
local function WriteVerified( encoded )
	if not file.IsDir( AdvMat.DataFolder, "DATA" ) then file.CreateDir( AdvMat.DataFolder ) end

	local hadLive  = file.Exists( AdvMat.DataFile, "DATA" )
	local previous = hadLive and file.Read( AdvMat.DataFile, "DATA" ) or nil
	if hadLive and not isstring( previous ) then
		return false, "the current database file could not be read"
	end

	-- Nothing touches the live file until a complete copy has been read back.
	local wrote, result = pcall( file.Write, Store.TempFile, encoded )
	if not wrote or result == false or file.Read( Store.TempFile, "DATA" ) ~= encoded then
		RemoveVerified( Store.TempFile )
		return false, "the new database could not be written and read back"
	end

	if not isfunction( file.Rename ) then
		-- No atomic replacement on this branch. The best left is a verified copy
		-- of the old file first, then the live file written and read back:
		-- Store.Load falls back to that copy if the live file is ever torn.
		if hadLive then
			pcall( file.Write, Store.BackupFile, previous )
			if file.Read( Store.BackupFile, "DATA" ) ~= previous then
				RemoveVerified( Store.TempFile )
				return false, "the current database could not be backed up"
			end
		end

		pcall( file.Write, AdvMat.DataFile, encoded )
		local ok = file.Read( AdvMat.DataFile, "DATA" ) == encoded
		RemoveVerified( Store.TempFile )
		if not ok then return false, "the database could not be written and read back" end
		return true
	end

	-- A stale backup must never take part in a rollback, so it goes first, and
	-- the exact live bytes captured above take its place.
	if hadLive then
		if not RemoveVerified( Store.BackupFile ) then
			RemoveVerified( Store.TempFile )
			return false, "the old backup could not be removed"
		end

		if not RenameVerified( AdvMat.DataFile, Store.BackupFile, previous ) then
			-- A rename leaves either the source or the destination. If the bytes
			-- moved but the call reported otherwise, put back exactly those.
			if not file.Exists( AdvMat.DataFile, "DATA" )
				and file.Read( Store.BackupFile, "DATA" ) == previous then
				RenameVerified( Store.BackupFile, AdvMat.DataFile, previous )
			end
			RemoveVerified( Store.TempFile )
			return false, "the current database could not be set aside"
		end
	end

	if not RenameVerified( Store.TempFile, AdvMat.DataFile, encoded ) then
		-- Roll back only to the backup verified a moment ago.
		if hadLive and file.Read( Store.BackupFile, "DATA" ) == previous then
			RemoveVerified( AdvMat.DataFile )
			RenameVerified( Store.BackupFile, AdvMat.DataFile, previous )
		elseif not hadLive then
			RemoveVerified( AdvMat.DataFile )
		end
		return false, "the new database could not be moved into place"
	end

	return true
end

local function QueueSave( delay )
	if saveQueued then return end
	saveQueued = true
	timer.Create( SAVE_TIMER, delay or SAVE_DELAY, 1, function() Store.Save() end )
end

local function TellPersisted( revision )
	for ply, wanted in pairs( diskWaiters ) do
		if not IsValid( ply ) then
			diskWaiters[ ply ], diskWarned[ ply ] = nil, nil
		elseif wanted <= revision then
			diskWaiters[ ply ], diskWarned[ ply ] = nil, nil

			net.Start( "AdvMat.RulePersisted" )
				net.WriteUInt( revision % 4294967296, 32 )
			net.Send( ply )
		end
	end
end

local function TellNotPersisted( reason )
	for ply in pairs( diskWaiters ) do
		if IsValid( ply ) and not diskWarned[ ply ] then
			diskWarned[ ply ] = true
			Notify( ply, "Your material change is live, but the server could not save it to disk: "
				.. tostring( reason ) .. ". It will keep trying.", NOTIFY_ERROR )
		end
	end
end

--- Write the persistent rules to disk. Returns true, or false plus a reason.
--- After a failure the previous file is untouched and the store stays dirty.
function Store.Save()
	saveQueued = false
	timer.Remove( SAVE_TIMER )

	local revision = Store.Revision
	local encoded  = util.TableToJSON( {
		version  = 1,
		saved    = os.time(),
		revision = revision,
		rules    = Store.Rules,
	}, true )

	local ok, reason = false, "the database could not be encoded"
	if isstring( encoded ) then ok, reason = WriteVerified( encoded ) end

	if not ok then
		dirty = true
		failureCount = failureCount + 1

		if reason ~= failureReason then
			AdvMat.Log( "Could not save the override database (%s); the previous file was kept.", reason )
		end
		failureReason = reason
		TellNotPersisted( reason )

		if failureCount < MAX_AUTOMATIC_ATTEMPTS then
			QueueSave( math.min( 5 * 2 ^ ( failureCount - 1 ), 30 ) )
		elseif failureCount == MAX_AUTOMATIC_ATTEMPTS then
			AdvMat.Log( "Override database saves keep failing; trying again on the next edit or advmat_save." )
		end
		return false, reason
	end

	dirty = false
	failureReason, failureCount = nil, 0
	Store.DiskRevision = revision
	AdvMat.Log( "Saved %d rule(s) to %s", AdvMat.TableCount( Store.Rules ), AdvMat.DataFile )
	TellPersisted( revision )
	return true
end

local function MarkDirty()
	dirty = true
	if not GetConVar( "advmat_autosave" ):GetBool() then return end
	QueueSave( SAVE_DELAY )
end

function Store.IsDirty() return dirty end

---------------------------------------------------------------------------
-- Rule construction
---------------------------------------------------------------------------

--- Build a normalised rule from raw (possibly client supplied) fields.
local function MakeRule( scope, key, index, mat, shader, params, ply, gen )
	return {
		scope  = scope,
		key    = key,
		index  = math.Clamp( math.floor( tonumber( index ) or 0 ), 0, AdvMat.GetMaterialLimit( key ) - 1 ),
		mat    = AdvMat.NormalizeMaterial( mat or "" ),
		shader = isstring( shader ) and string.sub( shader, 1, 64 ) or nil,
		params = AdvMat.SanitizeParams( params ),
		-- Recipes remain the durable form for generated textures. Full edited
		-- PNGs may also be validated and served by AdvMat.Assets so a legacy
		-- peer does not have to reproduce an unsupported render export.
		gen    = AdvMat.Gen.SanitizeAll( gen ),
		author = IsValid( ply ) and ply:SteamID() or "SERVER",
		time   = os.time(),
	}
end

--- Where a rule for (scope, key) lives: the scope, the normalised key and,
--- for entity scope, the entity. Or nil plus a reason.
local function Locate( scope, key )
	scope = tonumber( scope )
	if not AdvMat.SCOPE_SHORT[ scope ] then return nil, "bad scope" end

	if scope == AdvMat.SCOPE.ENTITY then
		local ent = isentity( key ) and key or Entity( tonumber( key ) or 0 )
		if not IsValid( ent ) then return nil, "entity is gone" end
		return scope, ent:EntIndex(), ent
	end

	local normKey = ( scope == AdvMat.SCOPE.MODEL )
		and AdvMat.NormalizeModel( key )
		or  AdvMat.NormalizeMaterial( key )

	if normKey == "" then return nil, "empty key" end
	return scope, normKey
end

--- Everything a rule has to satisfy before the store will hold it, whichever
--- way it arrived. Returns the normalised rule and, for entity scope, its
--- entity. On failure returns nil, a reason and - when its identity was
--- known - the rejected rule, so the caller can say what is stored there.
---
--- `trusted` is for state the server itself is restoring, which no client can
--- supply edited textures for; see the duplicator callback.
local function Prepare( scope, key, index, mat, shader, params, ply, gen, trusted )
	local normScope, normKey, ent = Locate( scope, key )
	if not normScope then return nil, normKey end

	local rule = MakeRule( normScope, normKey, index, mat, shader, params, ply, gen )

	-- Material- and world-scoped rules are keyed by the VMT path, which is
	-- also the material they start from.
	if rule.mat == ""
		and ( normScope == AdvMat.SCOPE.MATERIAL or normScope == AdvMat.SCOPE.WORLD ) then
		rule.mat = normKey
	end

	if AdvMat.RuleIsEmpty( rule ) then return rule, ent end

	-- A rule naming an edited texture promises every client the author's exact
	-- pixels, so it waits until the server really holds them.
	if not trusted and AdvMat.Assets and isfunction( AdvMat.Assets.StoredEditsReady ) then
		local ready, why = AdvMat.Assets.StoredEditsReady( rule.gen )
		if not ready then return nil, tostring( why ), rule end
	end

	if not FitsOneMessage( rule ) then
		return nil, "the override is too large to send to players", rule
	end

	return rule, ent
end

---------------------------------------------------------------------------
-- Rule mutation
---------------------------------------------------------------------------

--- Push a single rule to every client, then re-apply it in the world.
--- Clients need the rule before the entity starts referencing the material
--- name it produces, so the net message goes first.
local function BroadcastRule( rule, remove )
	Store.Revision = Store.Revision + 1

	net.Start( remove and "AdvMat.RuleClear" or "AdvMat.RuleSet" )
		net.WriteUInt( Store.Revision % 4294967296, 32 )
		AdvMat.Net.WriteTable( rule )
	net.Broadcast()

	if AdvMat.SvApply then AdvMat.SvApply.RefreshForRule( rule ) end
end

--- Attach / refresh the duplicator modifier so entity rules survive dupes.
local function SyncDupeModifier( ent )
	if not IsValid( ent ) then return end

	local set = Store.EntityRules[ ent:EntIndex() ]
	if not set or table.IsEmpty( set ) then
		duplicator.ClearEntityModifier( ent, DUPE_MODIFIER )
		return
	end

	local data = {}
	for idx, rule in pairs( set ) do
		data[ tostring( idx ) ] = {
			mat    = rule.mat,
			shader = rule.shader,
			params = rule.params,
			gen    = rule.gen,
		}
	end

	duplicator.StoreEntityModifier( ent, DUPE_MODIFIER, data )
end

--- The rule stored at the same identity as `rule`, if any.
local function CurrentRule( rule )
	if rule.scope == AdvMat.SCOPE.ENTITY then
		local set = Store.EntityRules[ rule.key ]
		return set and set[ rule.index ] or nil
	end
	return Store.Rules[ AdvMat.RuleID( rule.scope, rule.key, rule.index ) ]
end

--- Create, replace or (with an empty params table) delete a rule.
---
--- `expect` opts into a version check: the content token (AdvMat.RuleToken) of
--- the rule the caller's edit was based on, or "" for none. If what is stored
--- has changed since, nothing is written and the reason is Store.CONFLICT.
---
--- Returns the stored rule and whether anything changed, or nil, a reason and
--- the rule stored at that identity now (nil when there is none or the
--- identity was invalid).
function Store.Set( scope, key, index, mat, shader, params, ply, gen, expect )
	local rule, entOrReason, rejected = Prepare( scope, key, index, mat, shader, params, ply, gen )
	if not rule then
		return nil, entOrReason, rejected and CurrentRule( rejected ) or nil
	end

	local current = CurrentRule( rule )
	if isstring( expect ) and expect ~= AdvMat.RuleToken( current ) then
		return nil, Store.CONFLICT, current
	end

	-- Removing what is not there changes nothing: no broadcast, no disk write.
	-- "Reset to Default" clears every scope, most of them usually empty.
	local empty = AdvMat.RuleIsEmpty( rule )
	if empty and not current then return rule, false end

	if not empty then
		if rule.scope ~= AdvMat.SCOPE.ENTITY and not current
			and AdvMat.TableCount( Store.Rules ) >= GetConVar( "advmat_max_rules" ):GetInt() then
			return nil, "rule limit reached", current
		end

		if Store.DatabaseBytes( current ) + RuleBytes( rule ) > Store.MAX_DATABASE_BYTES then
			return nil, "the server's material database is full", current
		end
	end

	---------------------------------------------------------------- entity
	if rule.scope == AdvMat.SCOPE.ENTITY then
		local set = Store.EntityRules[ rule.key ] or {}
		set[ rule.index ] = ( not empty ) and rule or nil
		Store.EntityRules[ rule.key ] = ( next( set ) ~= nil ) and set or nil

		SyncDupeModifier( entOrReason )
		BroadcastRule( rule, empty )
		return rule, true
	end

	------------------------------------------------------------ persistent
	Store.Rules[ AdvMat.RuleID( rule.scope, rule.key, rule.index ) ] = ( not empty ) and rule or nil
	BroadcastRule( rule, empty )
	MarkDirty()

	return rule, true
end

function Store.Clear( scope, key, index )
	return Store.Set( scope, key, index, nil, nil, {}, nil )
end

--- Wipe every persistent rule that targets a model, across all slots.
function Store.ClearModel( mdl )
	mdl = AdvMat.NormalizeModel( mdl )

	local n = 0
	for i = 0, AdvMat.GetMaterialLimit( mdl ) - 1 do
		local id = AdvMat.RuleID( AdvMat.SCOPE.MODEL, mdl, i )
		if Store.Rules[ id ] then
			Store.Rules[ id ] = nil
			BroadcastRule( { scope = AdvMat.SCOPE.MODEL, key = mdl, index = i }, true )
			n = n + 1
		end
	end

	if n > 0 then MarkDirty() end
	return n
end

---------------------------------------------------------------------------
-- Loading
---------------------------------------------------------------------------
local function DecodeDatabase( path )
	if not file.Exists( path, "DATA" ) then return nil end

	local raw = file.Read( path, "DATA" )
	local tbl = isstring( raw ) and util.JSONToTable( raw ) or nil
	if not istable( tbl ) or not istable( tbl.rules ) then return nil, raw end
	return tbl
end

function Store.Load()
	Store.Rules = {}
	timer.Remove( SAVE_TIMER )
	dirty, saveQueued = false, false
	failureReason, failureCount = nil, 0

	local tbl, unreadable = DecodeDatabase( AdvMat.DataFile )
	local from = AdvMat.DataFile

	-- A save that stopped part way leaves the previous database aside under the
	-- backup name, or (before it was moved into place) the new one under the
	-- temporary name. Either beats starting empty.
	if not tbl then
		for _, path in ipairs( { Store.BackupFile, Store.TempFile } ) do
			tbl = DecodeDatabase( path )
			if tbl then from = path break end
		end
	end

	-- Keep an unreadable file for a person to look at; the next save would
	-- otherwise replace it.
	if isstring( unreadable ) and unreadable ~= "" then
		pcall( file.Write, Store.CorruptFile, unreadable )
		AdvMat.Log( "Override database could not be read; kept a copy as %s.", Store.CorruptFile )
	end

	if not tbl then
		AdvMat.Log( "No override database yet, starting empty." )
		return
	end

	local n, used, overflow = 0, 0, {}

	for id, raw in SortedPairs( tbl.rules ) do
		local scope = istable( raw ) and ( tonumber( raw.scope ) or AdvMat.SCOPE.MODEL ) or nil
		-- Entity-scoped rules are never persisted; drop any that leaked in.
		local normScope, normKey
		if scope and scope ~= AdvMat.SCOPE.ENTITY and istable( raw.params ) then
			normScope, normKey = Locate( scope, raw.key )
		end

		if normScope then
			-- The same normalisation as a save, but the file is the server's own:
			-- its edited textures are not re-checked and its authorship is kept.
			local rule = MakeRule( normScope, normKey, raw.index, raw.mat, raw.shader,
				raw.params, nil, raw.gen )
			rule.author = isstring( raw.author ) and raw.author or rule.author
			rule.time   = tonumber( raw.time ) or rule.time

			-- Keep the slot exactly as saved. MakeRule clamps it to the model's
			-- material limit, and an MMD model's limit above 32 is not known
			-- this early: clamping would move slot 35's rule onto slot 31.
			rule.index = math.max( 0, math.floor( tonumber( raw.index ) or 0 ) )

			if rule.mat == ""
				and ( normScope == AdvMat.SCOPE.MATERIAL or normScope == AdvMat.SCOPE.WORLD ) then
				rule.mat = normKey
			end

			if not AdvMat.RuleIsEmpty( rule ) then
				local cost = RuleBytes( rule )
				if used + cost > Store.MAX_DATABASE_BYTES then
					overflow[ id ] = raw
				else
					Store.Rules[ AdvMat.RuleID( rule.scope, rule.key, rule.index ) ] = rule
					used = used + cost
					n = n + 1
				end
			end
		end
	end

	-- Only a database written by hand or by an older version can be this big.
	-- Never drop those rules silently: keep them where a person can find them.
	if next( overflow ) ~= nil then
		pcall( file.Write, Store.OverflowFile, util.TableToJSON( { rules = overflow }, true ) )
		AdvMat.Log( "Override database is larger than clients can load; %d rule(s) were set aside in %s.",
			AdvMat.TableCount( overflow ), Store.OverflowFile )
	end

	-- Nothing but whole file replacements ever touch the live database again,
	-- so a recovered copy is written back as the live one straight away.
	if from ~= AdvMat.DataFile or next( overflow ) ~= nil then
		AdvMat.Log( "Recovered the override database from %s.", from )
		MarkDirty()
	end

	AdvMat.Log( "Loaded %d persistent rule(s).", n )
end

---------------------------------------------------------------------------
-- Syncing
---------------------------------------------------------------------------

--- Everything a joining client needs: persistent rules plus live entity rules,
--- and the revision they are current to.
local function BuildSnapshot()
	local ents = {}

	for entIndex, set in pairs( Store.EntityRules ) do
		if IsValid( Entity( entIndex ) ) then
			local packed = {}
			for idx, rule in pairs( set ) do packed[ tostring( idx ) ] = rule end
			ents[ tostring( entIndex ) ] = packed
		else
			Store.EntityRules[ entIndex ] = nil
		end
	end

	return { rules = Store.Rules, ents = ents, revision = Store.Revision }
end

--- Queue a snapshot for `target` (a player, or nil for everybody). The marker
--- goes out at once, ahead of any broadcast made while the snapshot is paced
--- out, so the client knows to keep those changes and replay them on top.
local function SendSnapshot( target )
	local snapshot = BuildSnapshot()

	net.Start( "AdvMat.SyncBegin" )
		net.WriteUInt( snapshot.revision % 4294967296, 32 )
	if target == nil then net.Broadcast() else net.Send( target ) end

	AdvMat.Net.SendChunked( snapshot, target )
end

function Store.SyncTo( ply )
	if IsValid( ply ) then SendSnapshot( ply ) end
end

net.Receive( "AdvMat.Request", function( len, ply )
	if not IsValid( ply ) then return end
	if ( ply.AdvMatNextSync or 0 ) > CurTime() then return end
	ply.AdvMatNextSync = CurTime() + 5
	Store.SyncTo( ply )
end )

---------------------------------------------------------------------------
-- Incoming client edits
---------------------------------------------------------------------------

-- Saving one model can legitimately push a rule per sub-material at once, so a
-- flat cooldown would silently swallow most of a single Save. A token bucket
-- lets a burst through while still capping the sustained rate.
local EDIT_BURST, EDIT_REFILL = 48, 20

local function TakeEditToken( ply )
	local now    = CurTime()
	local tokens = math.min( EDIT_BURST,
		( ply.AdvMatTokens or EDIT_BURST ) + ( now - ( ply.AdvMatTokenAt or now ) ) * EDIT_REFILL )

	ply.AdvMatTokenAt = now

	if tokens < 1 then
		ply.AdvMatTokens = tokens
		return false
	end

	ply.AdvMatTokens = tokens - 1
	return true
end

local function DebugEntityMatches( ent, rule )
	if not IsValid( ent ) or not istable( rule ) then return false end
	if rule.scope == AdvMat.SCOPE.ENTITY then
		return ent:EntIndex() == ( tonumber( rule.key ) or -1 )
	end
	if rule.scope == AdvMat.SCOPE.MODEL then
		return AdvMat.NormalizeModel( ent:GetModel() or "" ) == AdvMat.NormalizeModel( rule.key )
	end
	if rule.scope ~= AdvMat.SCOPE.MATERIAL then return false end

	local want = AdvMat.NormalizeMaterial( rule.key )
	for _, path in ipairs( ent:GetMaterials() or {} ) do
		if AdvMat.NormalizeMaterial( path ) == want then return true end
	end
	return false
end

local function SendDebugSaveState( ply, rule, label )
	if not IsValid( ply ) or not ply.AdvMatDebugTrace or not istable( rule ) then return end

	local rows, index = {}, tonumber( rule.index ) or 0
	for _, ent in ipairs( ents.GetAll() ) do
		if #rows >= 64 then break end
		if DebugEntityMatches( ent, rule ) then
			local mats = ent:GetMaterials() or {}
			local effective = Store.Resolve and Store.Resolve( ent, index, mats[ index + 1 ] ) or nil
			local actual = ent:GetSubMaterial( index ) or ""
			local targetName = not AdvMat.RuleIsEmpty( rule )
				and ( "!" .. AdvMat.MaterialName( rule ) ) or ""
			local effectiveName = effective and not AdvMat.RuleIsEmpty( effective )
				and ( "!" .. AdvMat.MaterialName( effective ) ) or ""

			rows[ #rows + 1 ] = {
				entity = ent:EntIndex(), class = ent:GetClass(), model = ent:GetModel(),
				index = index, original_material = mats[ index + 1 ],
				engine_submaterial = actual,
				server_applied = ent.AdvMatApplied and ent.AdvMatApplied[ index ] or nil,
				target_submaterial = targetName,
				effective_submaterial = effectiveName,
				engine_matches_target = actual == targetName,
				engine_matches_effective = actual == effectiveName,
				effective_rule = effective and {
					scope = effective.scope, key = effective.key, index = effective.index,
					mat = effective.mat, shader = effective.shader,
					params = effective.params,
				} or nil,
			}
		end
	end

	net.Start( "AdvMat.DebugTrace" )
		AdvMat.Net.WriteTable( {
			label = label, serverside = GetConVar( "advmat_serverside" ):GetBool(),
			rule = rule, rows = rows,
		} )
	net.Send( ply )
end

local function ScheduleDebugSaveState( ply, rule )
	if not IsValid( ply ) or not ply.AdvMatDebugTrace then return end
	for _, delay in ipairs( { 0, 0.1, 0.5, 2 } ) do
		timer.Simple( delay, function()
			SendDebugSaveState( ply, rule, "server.after_" .. tostring( delay ) )
		end )
	end
end

--- Tell the saving client exactly which edit was refused, so it can stop
--- waiting for it at once and, for a conflict, learn what is stored now.
local function SendRejected( ply, msg, reason, current, remove )
	if not IsValid( ply ) then return end

	local key = msg.key
	if not isstring( key ) and not isnumber( key ) then key = nil end

	net.Start( "AdvMat.RuleRejected" )
		AdvMat.Net.WriteTable( {
			scope    = tonumber( msg.scope ),
			key      = key,
			index    = tonumber( msg.index ),
			remove   = remove == true,
			token    = AdvMat.RuleToken( {
				mat = msg.mat, shader = msg.shader,
				params = remove and {} or msg.params, gen = ( not remove ) and msg.gen or nil,
			} ),
			reason   = tostring( reason ),
			conflict = reason == Store.CONFLICT,
			current  = AdvMat.RuleToken( current ),
		} )
	net.Send( ply )
end

local function HandleEdit( ply, remove )
	if not AdvMat.IsAllowed( ply ) then
		Notify( ply, "You are not allowed to save material overrides here.", NOTIFY_ERROR )
		return
	end

	if not TakeEditToken( ply ) then return end

	-- Decode only after permission and rate-limit checks. ReadTable still has
	-- its own decompression ceiling, but an unauthorized client should not get
	-- to spend even that bounded amount of server work.
	local msg = AdvMat.Net.ReadTable()
	if not istable( msg ) then return end

	-- Sent by editors that loaded a version first; "" means "there was no rule
	-- here". Anything that is not a token means no version check.
	local expect = msg.expect
	if not ( isstring( expect ) and #expect <= 64 ) then expect = nil end

	local rule, result, current = Store.Set(
		msg.scope,
		msg.key,
		msg.index,
		msg.mat,
		msg.shader,
		remove and {} or msg.params,
		ply,
		( not remove ) and msg.gen or nil,
		expect
	)

	if not rule then
		SendRejected( ply, msg, result, current, remove )
		-- A conflict is explained by the editor that sent it, which knows the
		-- slot and what the player can do about it.
		if result ~= Store.CONFLICT then
			Notify( ply, "Material override rejected: " .. tostring( result ), NOTIFY_ERROR )
		end
		return
	end

	-- What happens to the change next:
	--   0  nothing to write: entity rules live on the entity and in its dupes,
	--      and clearing a rule that was not there changed nothing at all
	--   1  queued for disk; AdvMat.RulePersisted follows once it is written
	--   2  held in memory until an admin saves (advmat_autosave is off)
	local persist = 0
	if rule.scope ~= AdvMat.SCOPE.ENTITY and result ~= false then
		persist = GetConVar( "advmat_autosave" ):GetBool() and 1 or 2
		diskWaiters[ ply ] = math.max( diskWaiters[ ply ] or 0, Store.Revision )
	end

	-- RuleSet is the durable-store broadcast. It is deliberately not also the
	-- preview handoff acknowledgement: BroadcastRule has only just run the
	-- server apply pass, and clients can receive the rule before the entity's
	-- networked sub-material catches up. A separate message sent from here
	-- proves the authoritative apply pass has completed.
	net.Start( "AdvMat.RuleApplied" )
		net.WriteUInt( Store.Revision % 4294967296, 32 )
		net.WriteUInt( persist, 2 )
		AdvMat.Net.WriteTable( rule )
	net.Send( ply )

	ScheduleDebugSaveState( ply, rule )
end

net.Receive( "AdvMat.RuleSet",   function( len, ply ) HandleEdit( ply, false ) end )
net.Receive( "AdvMat.RuleClear", function( len, ply ) HandleEdit( ply, true  ) end )
net.Receive( "AdvMat.DebugTrace", function( len, ply )
	if not IsValid( ply ) then return end
	ply.AdvMatDebugTrace = net.ReadBool() == true
end )

---------------------------------------------------------------------------
-- Duplicator / lifecycle
---------------------------------------------------------------------------
duplicator.RegisterEntityModifier( DUPE_MODIFIER, function( ply, ent, data )
	if not IsValid( ent ) or not istable( data ) then return end

	-- A dupe modifier is another client-controlled save path. Without the same
	-- permission gate as AdvMat.RuleSet, a non-admin can paste crafted modifier
	-- data and create an entity rule even while advmat_adminonly is enabled.
	-- An invalid player means server/map restoration and remains allowed.
	local byPlayer = IsValid( ply )
	if byPlayer and not AdvMat.IsAllowed( ply ) then return end

	-- Each entry is checked exactly like an editor save. A pasted entry is no
	-- more trustworthy than a RuleSet message: a malformed one used to reach the
	-- material naming code as-is and fail there on every refresh.
	--
	-- The one difference is edited textures when the server itself restores a
	-- save: there is no client to supply them, and refusing would lose paint
	-- the server accepted before. Those rules fall back to their recipe, exactly
	-- like rules saved before edited textures were transferred at all.
	local limit = AdvMat.GetMaterialLimit( ent )
	local base  = Store.DatabaseBytes( nil, ent:EntIndex() )
	local set, used = {}, 0
	local skipped, why, seen = 0, nil, 0

	for k, entry in pairs( data ) do
		seen = seen + 1

		-- A genuine dupe has one entry per material slot at most. Stop reading
		-- a crafted one long before it costs real work.
		if seen > limit then
			skipped = skipped + 1
			why = why or "the dupe has more entries than the model has material slots"
			break
		end

		local index = tonumber( k )
		local rule, reason

		if not istable( entry ) or not istable( entry.params ) then
			reason = "an entry is malformed"
		elseif not index or index ~= math.floor( index ) or index < 0 or index >= limit then
			reason = "slot " .. tostring( k ) .. " does not exist on this model"
		else
			rule, reason = Prepare( AdvMat.SCOPE.ENTITY, ent, index, entry.mat, entry.shader,
				entry.params, ply, entry.gen, not byPlayer )
		end

		if rule and not AdvMat.RuleIsEmpty( rule ) then
			local cost = RuleBytes( rule )
			if base + used + cost > Store.MAX_DATABASE_BYTES then
				rule, reason = nil, "the server's material database is full"
			else
				set[ rule.index ] = rule
				used = used + cost
			end
		end

		if not rule then
			skipped = skipped + 1
			why = why or reason
		end
	end

	Store.EntityRules[ ent:EntIndex() ] = ( next( set ) ~= nil ) and set or nil
	SyncDupeModifier( ent )

	if skipped > 0 then
		AdvMat.Log( "Skipped %d material override(s) pasted onto %s: %s",
			skipped, tostring( ent ), tostring( why ) )
		if byPlayer then
			Notify( ply, string.format( "%d material override(s) in that dupe were not applied: %s",
				skipped, tostring( why ) ), NOTIFY_ERROR )
		end
	end

	-- Clients may not have been told about the entity yet; give it a tick.
	timer.Simple( 0, function()
		if not IsValid( ent ) then return end

		local current = Store.EntityRules[ ent:EntIndex() ] or {}
		for idx, rule in pairs( set ) do
			-- Something may have replaced or cleared the slot within the tick.
			if current[ idx ] == rule then BroadcastRule( rule, false ) end
		end
		if AdvMat.SvApply then AdvMat.SvApply.Refresh( ent ) end
	end )
end )

hook.Add( "EntityRemoved", "AdvMat.EntityRemoved", function( ent )
	if not IsValid( ent ) then return end
	Store.EntityRules[ ent:EntIndex() ] = nil
end )

hook.Add( "PlayerInitialSpawn", "AdvMat.InitialSync", function( ply )
	-- Backstop. The client normally asks for this itself on InitPostEntity,
	-- which is the first moment net messages reliably reach it.
	timer.Simple( 3, function()
		if IsValid( ply ) then Store.SyncTo( ply ) end
	end )
end )

hook.Add( "Initialize", "AdvMat.Load", function() Store.Load() end )

hook.Add( "ShutDown", "AdvMat.SaveOnShutdown", function()
	if dirty then Store.Save() end
end )

-- Autorefresh reloads this file mid-session; repopulate if we came up empty.
if AdvMat.TableCount( Store.Rules ) == 0 then Store.Load() end

---------------------------------------------------------------------------
-- Console commands
---------------------------------------------------------------------------
local function IsConsoleOrSuperAdmin( ply )
	return not IsValid( ply ) or ply:IsSuperAdmin()
end

concommand.Add( "advmat_save", function( ply )
	if not IsConsoleOrSuperAdmin( ply ) then return end
	local ok, reason = Store.Save()
	if not ok then AdvMat.Log( "advmat_save failed: %s", tostring( reason ) ) end
end )

-- A wholesale replacement has no per-rule broadcasts, so it takes a revision
-- of its own: every client then installs the new snapshot over anything older.
concommand.Add( "advmat_reload", function( ply )
	if not IsConsoleOrSuperAdmin( ply ) then return end
	Store.Load()
	Store.Revision = Store.Revision + 1
	SendSnapshot( nil )
	if AdvMat.SvApply then AdvMat.SvApply.RefreshAll() end
end )

concommand.Add( "advmat_wipe", function( ply )
	if not IsConsoleOrSuperAdmin( ply ) then return end
	Store.Rules = {}
	Store.Revision = Store.Revision + 1
	local ok, reason = Store.Save()
	SendSnapshot( nil )
	if AdvMat.SvApply then AdvMat.SvApply.RefreshAll() end
	AdvMat.Log( ok and "Override database wiped." or
		( "Override rules cleared, but the database file could not be rewritten: " .. tostring( reason ) ) )
end )

concommand.Add( "advmat_list", function( ply )
	if not IsConsoleOrSuperAdmin( ply ) then return end
	for id, rule in SortedPairs( Store.Rules ) do
		AdvMat.Log( "%s  ->  %d param(s)  [%s]", id, AdvMat.TableCount( rule.params ),
			rule.shader or "keep shader" )
	end
	AdvMat.Log( "%d rule(s) total.", AdvMat.TableCount( Store.Rules ) )
end )
