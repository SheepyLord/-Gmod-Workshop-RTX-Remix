--[[---------------------------------------------------------------------------
	Advanced Material Editor - clientside rule mirror

	The client keeps a mirror of the server's rule database plus a purely local
	"preview" layer that the editor writes to while you drag sliders. Preview
	rules are never networked; hitting Save in the editor promotes them into a
	real rule on the server.

	Resolution order for a given (entity, submaterial index), highest first:

	    preview  >  entity rule  >  model rule  >  material-path rule
-----------------------------------------------------------------------------]]

AdvMat        = AdvMat or {}
AdvMat.Client = AdvMat.Client or {}

local C = AdvMat.Client

C.Rules    = C.Rules    or {}  -- [ruleID]   = rule  (mirrored from server)
C.EntRules = C.EntRules or {}  -- [entIndex] = { [subIndex] = rule }
C.Preview  = C.Preview  or {}  -- [entIndex] = { [subIndex] = rule }  (local only)
C.PendingSaves = C.PendingSaves or {} -- [entIndex][subIndex] = save awaiting its echo

-- Every broadcast carries the server's revision, and a snapshot the revision
-- it was built at. A snapshot is paced out over seconds while broadcasts keep
-- arriving, so a change can land here before an OLDER snapshot finishes and
-- replaces the whole mirror. While a snapshot is on its way the changes are
-- kept, and those newer than the snapshot are replayed on top of it.
C.Revision     = C.Revision     or 0   -- newest revision the mirror reflects
C.Announced    = C.Announced    or {}  -- revisions of snapshots announced but not installed
C.SyncsPending = #C.Announced          -- how many of those there are
C.DeltaLog     = C.DeltaLog     or {}  -- { rev, rule, remove } heard while one is pending
C.DeltaFloor   = C.DeltaFloor   or 0   -- newest revision dropped from a full log

-- Save is a network round trip, not a timer. Keep the exact preview that was
-- sent until the server acknowledges that its authoritative apply pass has
-- completed. The earlier store echo is not enough: it can arrive before the
-- entity's networked sub-material. Releasing on that echo made Save or Close
-- expose the model default between the two events.
local SAVE_CONFIRM_TIMEOUT = 10

local function RuleContentSignature( rule )
	if not istable( rule ) then return "" end

	return AdvMat.Gen.Canonical( {
		index  = tonumber( rule.index ) or 0,
		mat    = AdvMat.NormalizeMaterial( rule.mat or "" ),
		shader = isstring( rule.shader ) and rule.shader or "",
		params = AdvMat.SanitizeParams( rule.params ),
		gen    = AdvMat.Gen.SanitizeAll( rule.gen ),
	} )
end

local function CancelPending( ei, index )
	local set = C.PendingSaves[ ei ]
	if not set then return end

	if index ~= nil then
		set[ index ] = nil
		if table.IsEmpty( set ) then C.PendingSaves[ ei ] = nil end
	else
		C.PendingSaves[ ei ] = nil
	end
end

---------------------------------------------------------------------------
-- Lookup
---------------------------------------------------------------------------

--- The rule that should be applied to submaterial `index` of `ent`, or nil.
--- `matPath` is the entity's original VMT for that slot; pass it when known
--- so the MATERIAL scope can be resolved without re-reading GetMaterials().
function C.Resolve( ent, index, matPath )
	if not IsValid( ent ) then return nil end

	local preview = C.Preview[ ent:EntIndex() ]
	if preview and preview[ index ] then return preview[ index ], true end

	return AdvMat.ResolveRule( ent, index, matPath, C.Rules, C.EntRules ), false
end

--- Every entity currently in the world that a rule could possibly affect.
--- Used to refresh visuals the moment a rule changes.
function C.EntitiesAffectedBy( rule )
	local out = {}
	if not istable( rule ) then return out end

	if rule.scope == AdvMat.SCOPE.ENTITY then
		local ent = Entity( tonumber( rule.key ) or 0 )
		if IsValid( ent ) then out[ #out + 1 ] = ent end
		return out
	end

	if rule.scope == AdvMat.SCOPE.MODEL then
		local want = AdvMat.NormalizeModel( rule.key )
		for _, ent in ipairs( ents.GetAll() ) do
			if IsValid( ent ) and AdvMat.NormalizeModel( ent:GetModel() or "" ) == want then
				out[ #out + 1 ] = ent
			end
		end
		return out
	end

	-- World rules never touch an entity.
	if rule.scope == AdvMat.SCOPE.WORLD then return out end

	-- MATERIAL scope: anything whose material list mentions the path.
	local want = AdvMat.NormalizeMaterial( rule.key )
	for _, ent in ipairs( ents.GetAll() ) do
		if IsValid( ent ) and ent:GetModel() then
			local mats = ent:GetMaterials()
			if mats then
				for _, m in ipairs( mats ) do
					if AdvMat.NormalizeMaterial( m ) == want then
						out[ #out + 1 ] = ent
						break
					end
				end
			end
		end
	end

	return out
end

---------------------------------------------------------------------------
-- Preview layer
---------------------------------------------------------------------------
--- `defer` skips the re-apply, for callers that are about to change several
--- slots in a row and will call AdvMat.Apply.Refresh once themselves.
function C.SetPreview( ent, index, rule, defer )
	if not IsValid( ent ) then return end

	local ei = ent:EntIndex()
	local pending = C.PendingSaves[ ei ] and C.PendingSaves[ ei ][ index ]

	-- A queued preview push can land just after Save.  It is still the same
	-- staged rule and must not cancel the handoff.  A genuinely newer edit has
	-- different content, so its late save echo must not clear that new preview.
	if pending and RuleContentSignature( rule ) ~= pending.content then
		CancelPending( ei, index )
	end

	C.Preview[ ei ] = C.Preview[ ei ] or {}
	C.Preview[ ei ][ index ] = rule

	if not defer then AdvMat.Apply.Refresh( ent ) end
end

function C.ClearPreview( ent, index, defer )
	if not IsValid( ent ) then return end

	local ei  = ent:EntIndex()
	local set = C.Preview[ ei ]
	CancelPending( ei, index )

	if set then
		if index then
			set[ index ] = nil
			if table.IsEmpty( set ) then C.Preview[ ei ] = nil end
		else
			C.Preview[ ei ] = nil
		end
	end

	if not defer then AdvMat.Apply.Refresh( ent ) end
end

--- Close an editor without dropping previews that are still crossing the
--- client/server boundary.  Everything genuinely unsaved is released.
function C.ClearUncommittedPreviews( ent, defer )
	if not IsValid( ent ) then return end

	local ei      = ent:EntIndex()
	local previews = C.Preview[ ei ]
	local pending  = C.PendingSaves[ ei ]

	if previews then
		for index, rule in pairs( previews ) do
			local wait = pending and pending[ index ]
			if not wait or RuleContentSignature( rule ) ~= wait.content then
				previews[ index ] = nil
			else
				-- Kept only for the handoff now. If the save is refused there is
				-- no editor left to clear it, so the refusal has to.
				wait.released = true
			end
		end

		if table.IsEmpty( previews ) then C.Preview[ ei ] = nil end
	end

	if not defer then AdvMat.Apply.Refresh( ent ) end
end

--- Mark the preview for one outgoing rule as pending.  This must run before
--- net.SendToServer: listen servers can echo the rule synchronously.
function C.ExpectSave( ent, index, rule )
	if not IsValid( ent ) or not istable( rule ) then
		if AdvMat.DebugTraceActive then
			AdvMat.DebugTraceEvent( "save.expect_rejected", { reason = "invalid entity or rule" } )
		end
		return
	end

	index = tonumber( index ) or 0

	local ei      = ent:EntIndex()
	local preview = C.Preview[ ei ] and C.Preview[ ei ][ index ]
	if not preview then
		if AdvMat.DebugTraceActive then
			AdvMat.DebugTraceEvent( "save.expect_rejected", {
				reason = "no preview", entity = ei, index = index, rule = rule,
			} )
		end
		return
	end

	local content = RuleContentSignature( rule )
	local previewContent = RuleContentSignature( preview )
	if content == "" or previewContent ~= content then
		if AdvMat.DebugTraceActive then
			AdvMat.DebugTraceEvent( "save.expect_rejected", {
				reason = "preview differs", entity = ei, index = index,
				content = content, preview_content = previewContent,
			} )
		end
		return
	end

	local scope = tonumber( rule.scope ) or AdvMat.SCOPE.MODEL
	local wait = {
		ent     = ent,
		id      = AdvMat.RuleID( scope, rule.key, index ),
		content = content,
		-- A refusal names the edit by this token (see C.RejectSave).
		token   = AdvMat.RuleToken( rule ),
	}

	C.PendingSaves[ ei ] = C.PendingSaves[ ei ] or {}
	C.PendingSaves[ ei ][ index ] = wait
	if AdvMat.DebugTraceActive then
		AdvMat.DebugTraceEvent( "save.awaiting_apply_ack", {
			entity = ei, index = index, id = wait.id, content = content,
		} )
	end

	timer.Simple( SAVE_CONFIRM_TIMEOUT, function()
		local current = C.PendingSaves[ ei ] and C.PendingSaves[ ei ][ index ]
		if current ~= wait then return end

		CancelPending( ei, index )
		if AdvMat.DebugTraceActive then
			AdvMat.DebugTraceEvent( "save.apply_ack_timeout", {
				entity = ei, index = index, id = wait.id, content = content,
			} )
		end

		if IsValid( ent ) then
			local staged = C.Preview[ ei ] and C.Preview[ ei ][ index ]
			if staged and RuleContentSignature( staged ) == content then
				C.ClearPreview( ent, index )
			end
		end

		AdvMat.NotifyLocal(
			"The material apply was not confirmed by the server; its preview was released.",
			NOTIFY_ERROR, 7 )
	end )
end

--- Complete every local handoff that matches the canonical rule in the
--- server's post-apply acknowledgement. Returns entities that need refreshing
--- after the material is built.
function C.ConfirmSave( rule )
	if not istable( rule ) then return {} end

	local scope   = tonumber( rule.scope ) or AdvMat.SCOPE.MODEL
	local id      = AdvMat.RuleID( scope, rule.key, rule.index )
	local content = RuleContentSignature( rule )
	local touched = {}
	if AdvMat.DebugTraceActive then
		AdvMat.DebugTraceEvent( "save.apply_ack_received", {
			id = id, content = content, rule = rule,
		} )
	end

	for ei, set in pairs( C.PendingSaves ) do
		for index, wait in pairs( set ) do
			if wait.id == id and wait.content == content then
				set[ index ] = nil

				local previews = C.Preview[ ei ]
				local staged = previews and previews[ index ]
				if staged and RuleContentSignature( staged ) == content then
					previews[ index ] = nil
					if table.IsEmpty( previews ) then C.Preview[ ei ] = nil end
				end

				if IsValid( wait.ent ) then touched[ #touched + 1 ] = wait.ent end
				if AdvMat.DebugTraceActive then
					AdvMat.DebugTraceEvent( "save.apply_ack_matched", {
						entity = ei, index = index, id = id,
					} )
				end
			end
		end

		if table.IsEmpty( set ) then C.PendingSaves[ ei ] = nil end
	end

	return touched
end

--- The server refused a save. Stop waiting for its acknowledgement at once
--- rather than after the timeout. A preview whose editor is still open stays,
--- because those edits are still unsaved; one whose editor already closed is
--- released, exactly as the timeout would have done.
function C.RejectSave( info )
	if not istable( info ) then return end

	local id = AdvMat.RuleID( tonumber( info.scope ) or AdvMat.SCOPE.MODEL, info.key, info.index )
	local release = {}

	for ei, set in pairs( C.PendingSaves ) do
		for index, wait in pairs( set ) do
			if wait.id == id and ( not isstring( info.token ) or wait.token == info.token ) then
				set[ index ] = nil
				if wait.released then release[ #release + 1 ] = { ei = ei, index = index, wait = wait } end
			end
		end

		if table.IsEmpty( set ) then C.PendingSaves[ ei ] = nil end
	end

	for _, item in ipairs( release ) do
		local staged = C.Preview[ item.ei ] and C.Preview[ item.ei ][ item.index ]
		if IsValid( item.wait.ent ) and staged
			and RuleContentSignature( staged ) == item.wait.content then
			C.ClearPreview( item.wait.ent, item.index )
		end
	end
end

function C.ClearAllPreviews()
	local touched = {}
	for ei in pairs( C.Preview ) do touched[ #touched + 1 ] = Entity( ei ) end
	C.Preview = {}
	C.PendingSaves = {}
	for _, ent in ipairs( touched ) do
		if IsValid( ent ) then AdvMat.Apply.Refresh( ent ) end
	end
end

-- Entity indexes are reused. Never let a deleted prop's local preview, pending
-- save handoff, or entity-scoped mirror leak onto the next entity allocated at
-- the same index. Pending entries carry the original entity reference, so only
-- discard waits that actually belong to the removed object.
hook.Add( "EntityRemoved", "AdvMat.RuleStateEntityRemoved", function( ent )
	if not ent or not ent.EntIndex then return end
	local ei = ent:EntIndex()
	C.Preview[ ei ] = nil
	C.EntRules[ ei ] = nil

	local pending = C.PendingSaves[ ei ]
	if not pending then return end
	for index, wait in pairs( pending ) do
		if wait.ent == ent then pending[ index ] = nil end
	end
	if table.IsEmpty( pending ) then C.PendingSaves[ ei ] = nil end
end )

---------------------------------------------------------------------------
-- Network handlers
---------------------------------------------------------------------------
-- Garry's Mod JSON has an unusual convenience conversion: strings shaped
-- like "[x y z]" and "{x y z}" come back from util.JSONToTable as Vector and
-- Angle objects. Those are also the literal syntaxes used by VMT parameters.
-- Restore the string-only rule invariant at every client receive boundary;
-- CreateMaterial silently turns a Vector value in its KV table into [0 0 0].
local function NormalizeIncomingRule( rule )
	if not istable( rule ) then return nil end

	rule.scope  = tonumber( rule.scope ) or AdvMat.SCOPE.MODEL
	rule.index  = tonumber( rule.index ) or 0
	rule.params = AdvMat.SanitizeParams( rule.params )
	rule.gen    = AdvMat.Gen.SanitizeAll( rule.gen )
	-- This rule originated on another network endpoint. Missing edited images
	-- should be fetched from the server before this client attempts a renderer-
	-- dependent rebuild of the portable recipe.
	if AdvMat.Assets and isfunction( AdvMat.Assets.MarkRemoteValue ) then
		AdvMat.Assets.MarkRemoteValue( rule.gen )
	end
	return rule
end

local function StoreRule( rule )
	if rule.scope == AdvMat.SCOPE.ENTITY then
		local ei = tonumber( rule.key ) or 0
		C.EntRules[ ei ] = C.EntRules[ ei ] or {}
		C.EntRules[ ei ][ tonumber( rule.index ) or 0 ] = rule
	else
		C.Rules[ AdvMat.RuleID( rule.scope, rule.key, rule.index ) ] = rule
	end
end

local function ForgetRule( rule )
	if rule.scope == AdvMat.SCOPE.ENTITY then
		local ei  = tonumber( rule.key ) or 0
		local set = C.EntRules[ ei ]
		if set then
			set[ tonumber( rule.index ) or 0 ] = nil
			if table.IsEmpty( set ) then C.EntRules[ ei ] = nil end
		end
	else
		C.Rules[ AdvMat.RuleID( rule.scope, rule.key, rule.index ) ] = nil
	end
end

-- Only kept while a snapshot is on its way (see C.SyncsPending); otherwise
-- the mirror itself is the whole truth and there is nothing to replay. The
-- limit is a backstop: overflowing it costs one extra resync, not correctness.
local DELTA_LOG_LIMIT = 4096

local function RecordDelta( rev, rule, remove )
	if rev > C.Revision then C.Revision = rev end
	if C.SyncsPending <= 0 then return end

	local log = C.DeltaLog
	log[ #log + 1 ] = { rev = rev, rule = rule, remove = remove == true }

	if #log > DELTA_LOG_LIMIT then
		local dropped = table.remove( log, 1 )
		C.DeltaFloor = math.max( C.DeltaFloor, dropped.rev )
	end
end

net.Receive( "AdvMat.RuleSet", function()
	local rev = net.ReadUInt( 32 )
	local raw = AdvMat.Net.ReadTable()
	if not istable( raw ) or not istable( raw.params ) then return end
	local rule = NormalizeIncomingRule( raw )

	if AdvMat.DebugTraceActive then
		AdvMat.DebugTraceEvent( "rule_set.received", { rule = rule, revision = rev } )
	end
	StoreRule( rule )
	RecordDelta( rev, rule, false )

	if rule.scope == AdvMat.SCOPE.WORLD then
		AdvMat.Apply.ApplyWorld( rule )
	else
		-- Build the material immediately. The server is about to reference it
		-- by name on an entity, and a name nothing has created renders as the
		-- missing-texture checkerboard.
		AdvMat.Apply.BuildForRule( rule )

		local touched = {}
		for _, ent in ipairs( C.EntitiesAffectedBy( rule ) ) do touched[ ent ] = true end

		for ent in pairs( touched ) do
			if IsValid( ent ) then
				AdvMat.Apply.Refresh( ent )
				if AdvMat.DebugTraceActive then
					AdvMat.DebugTraceSnapshot( "rule_set.after_refresh", ent, rule.index, rule )
				end
			end
		end
	end

	hook.Run( "AdvMatRulesChanged", rule, false )
end )

-- This is sent only to the player who saved, after Store.Set has completed its
-- server-side RefreshForRule pass. Until it arrives the exact local preview is
-- kept, including when the editor closes, so a store echo can never expose the
-- model default while the authoritative entity update is still in flight.
net.Receive( "AdvMat.RuleApplied", function()
	local rev     = net.ReadUInt( 32 )
	local persist = net.ReadUInt( 2 )
	local raw = AdvMat.Net.ReadTable()
	if not istable( raw ) or not istable( raw.params ) then return end
	local rule  = NormalizeIncomingRule( raw )
	local empty = AdvMat.RuleIsEmpty( rule )

	-- The broadcast of this same change arrived just before and is already in
	-- the mirror - unless a newer snapshot has been installed since, which then
	-- holds this change or something newer still. Either way, never write an
	-- older state back over it.
	if rev > C.Revision then
		if empty then ForgetRule( rule ) else StoreRule( rule ) end
		RecordDelta( rev, rule, empty )
	end

	-- "Applied" is not "saved": a persistent rule is only on disk once
	-- AdvMat.RulePersisted says so. Count what this player is waiting for.
	if persist == 1 or persist == 2 then
		local wait = C.DiskPending or { saved = 0, removed = 0, rev = 0 }
		if empty then wait.removed = wait.removed + 1 else wait.saved = wait.saved + 1 end
		wait.rev = math.max( wait.rev, rev )
		C.DiskPending = wait

		if persist == 2 and not C.ToldManualSave then
			C.ToldManualSave = true
			AdvMat.NotifyLocal( AdvMat.L( "notify.manual_save" ), NOTIFY_HINT, 8 )
		end
	end

	if rule.scope ~= AdvMat.SCOPE.WORLD and not AdvMat.RuleIsEmpty( rule ) then
		AdvMat.Apply.BuildForRule( rule )
	end

	local confirmed = C.ConfirmSave( rule )
	for _, ent in ipairs( confirmed ) do
		if IsValid( ent ) then
			AdvMat.Apply.Refresh( ent )
			if AdvMat.DebugTraceActive then
				AdvMat.DebugTraceSnapshot( "rule_applied.after_refresh", ent, rule.index, rule )
			end
		end
	end

	if AdvMat.DebugTraceActive then
		AdvMat.DebugTraceEvent( "rule_applied.received", { rule = rule, confirmed = #confirmed } )
		AdvMat.DebugTraceCheckpoint()
	end

	-- Editors with explicit dirty/pending state use the authoritative post-apply
	-- acknowledgement rather than treating the earlier database broadcast as a
	-- successful save. The ordinary editor does not need to subscribe.
	hook.Run( "AdvMatRuleApplied", rule, { revision = rev, persist = persist } )
end )

-- The server has written its database, including everything up to `rev`.
net.Receive( "AdvMat.RulePersisted", function()
	local rev  = net.ReadUInt( 32 )
	local wait = C.DiskPending

	if wait and wait.rev <= rev then
		C.DiskPending = nil
		local message
		if wait.saved == 0 then
			message = string.format( "Removed %d material override(s).", wait.removed )
		elseif wait.removed > 0 then
			message = string.format( "Saved %d override(s), removed %d.", wait.saved, wait.removed )
		else
			message = string.format( "Saved %d override(s).", wait.saved )
		end
		AdvMat.NotifyLocal( message, NOTIFY_GENERIC, 4 )
	end

	hook.Run( "AdvMatRulesPersisted", rev )
end )

-- A save of ours was refused. For a conflict `info.current` is the token of
-- what is stored now, which an editor needs in order to overwrite on purpose.
net.Receive( "AdvMat.RuleRejected", function()
	local info = AdvMat.Net.ReadTable()
	if not istable( info ) then return end

	C.RejectSave( info )
	hook.Run( "AdvMatRuleRejected", info )
end )

net.Receive( "AdvMat.RuleClear", function()
	local rev  = net.ReadUInt( 32 )
	local rule = NormalizeIncomingRule( AdvMat.Net.ReadTable() )
	if not rule then return end

	ForgetRule( rule )
	RecordDelta( rev, rule, true )

	if rule.scope == AdvMat.SCOPE.WORLD then
		AdvMat.Apply.RestoreWorld( rule.key )
	else
		for _, ent in ipairs( C.EntitiesAffectedBy( rule ) ) do
			AdvMat.Apply.Refresh( ent )
		end
	end

	hook.Run( "AdvMatRulesChanged", rule, true )
end )

-- Sent the moment a snapshot is queued for this client, ahead of every
-- broadcast made while it is paced out. From here until it is installed, the
-- changes heard are kept for replay.
net.Receive( "AdvMat.SyncBegin", function()
	C.Announced[ #C.Announced + 1 ] = net.ReadUInt( 32 )
	C.SyncsPending = #C.Announced
end )

--- An announced snapshot is done with: the oldest one when it could not be
--- read, or the one at `revision` when it was installed. Snapshots arrive in
--- the order they were queued, so any announced before it at an older
--- revision can no longer arrive either. Two can share a revision (two
--- requests with no edit between them); only one of those is retired.
local function SnapshotDone( revision )
	if revision == nil then
		table.remove( C.Announced, 1 )
	else
		local still, retired = {}, false
		for _, rev in ipairs( C.Announced ) do
			if rev < revision then
				-- older and abandoned
			elseif rev == revision and not retired then
				retired = true
			else
				still[ #still + 1 ] = rev
			end
		end
		C.Announced = still
	end

	C.SyncsPending = #C.Announced
	if C.SyncsPending == 0 then C.DeltaLog, C.DeltaFloor = {}, 0 end
end

local RequestSync
local syncFailures = 0

--- A snapshot arrived but could not be used. Keeping the old mirror is the
--- least bad option; say so, and ask again a few times with growing gaps.
local function SyncFailed( reason )
	SnapshotDone( nil )

	syncFailures = syncFailures + 1
	AdvMat.Log( "Could not load the server's material overrides: %s", tostring( reason ) )
	if syncFailures > 3 then return end

	AdvMat.NotifyLocal( AdvMat.L( "notify.sync_failed", { reason = tostring( reason ) } ),
		NOTIFY_ERROR, 8 )
	timer.Simple( 10 * syncFailures, function() RequestSync() end )
end

net.Receive( "AdvMat.Sync", function()
	local snapshot, failure = AdvMat.Net.ReceiveChunk()
	if failure then SyncFailed( failure ) return end
	if not snapshot then return end -- more chunks still inbound

	syncFailures = 0
	local revision = tonumber( snapshot.revision ) or 0

	C.Rules    = {}
	C.EntRules = {}

	if istable( snapshot.rules ) then
		for id, rule in pairs( snapshot.rules ) do
			if istable( rule ) and istable( rule.params ) then
				C.Rules[ id ] = NormalizeIncomingRule( rule )
			end
		end
	end

	if istable( snapshot.ents ) then
		for entIndex, set in pairs( snapshot.ents ) do
			local ei = tonumber( entIndex )
			if ei and istable( set ) then
				C.EntRules[ ei ] = {}
				for idx, rule in pairs( set ) do
					if istable( rule ) and istable( rule.params ) then
						rule.scope = AdvMat.SCOPE.ENTITY
						rule.index = tonumber( idx ) or 0
						rule = NormalizeIncomingRule( rule )
						C.EntRules[ ei ][ rule.index ] = rule
					end
				end
			end
		end
	end

	-- The snapshot holds every change up to its own revision. Anything newer
	-- was heard while it travelled and is put back on top, in order.
	local keep, replayed = {}, 0
	for _, delta in ipairs( C.DeltaLog ) do
		if delta.rev > revision then
			if delta.remove then ForgetRule( delta.rule ) else StoreRule( delta.rule ) end
			keep[ #keep + 1 ] = delta
			replayed = replayed + 1
		end
	end

	-- Some change between this snapshot and the oldest one still logged was
	-- dropped from a full log. The mirror may miss it, so fetch a fresh copy.
	local incomplete = revision < C.DeltaFloor

	C.DeltaLog = keep
	SnapshotDone( revision )
	C.Revision = math.max( C.Revision, revision )

	AdvMat.Log( "Synced %d persistent rule(s) from the server%s.", AdvMat.TableCount( C.Rules ),
		replayed > 0 and string.format( " (+%d newer change(s))", replayed ) or "" )

	AdvMat.Apply.EnsureRuleMaterials()
	AdvMat.Apply.RefreshWorld()
	AdvMat.Apply.RefreshAll()

	hook.Run( "AdvMatRulesChanged", nil, false )

	if incomplete then timer.Simple( 6, function() RequestSync() end ) end
end )

net.Receive( "AdvMat.Notify", function()
	local msg  = net.ReadString()
	local kind = net.ReadUInt( 3 )
	AdvMat.NotifyLocal( msg, kind, 5 )
	surface.PlaySound( kind == NOTIFY_ERROR and "buttons/button10.wav" or "buttons/button15.wav" )
end )

---------------------------------------------------------------------------
-- Ask for a sync on join / on autorefresh
---------------------------------------------------------------------------
RequestSync = function()
	net.Start( "AdvMat.Request" )
	net.SendToServer()
end

C.RequestSync = RequestSync

hook.Add( "InitPostEntity", "AdvMat.RequestSync", function()
	timer.Simple( 1, RequestSync )
end )

concommand.Add( "advmat_resync", RequestSync )
