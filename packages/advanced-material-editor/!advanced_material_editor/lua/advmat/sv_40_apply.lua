--[[---------------------------------------------------------------------------
	Advanced Material Editor - serverside application

	Saved rules are applied by the SERVER, with Entity:SetSubMaterial. That is
	the only way to make an override durable: a sub-material set on the client
	is silently reverted to the server's value a few ticks after the entity
	re-enters the PVS or receives a full update.

	The server never builds the material - CreateMaterial is client only. It
	only sends the NAME, which every client derives identically from the rule
	(see sh_35_matname.lua) and creates locally.

	Every distinct material name a server hands out occupies a slot in the
	shared network string table, which is a finite global resource. That is why
	names are derived from rule identity rather than minted per edit, and why
	advmat_max_rules exists.
-----------------------------------------------------------------------------]]

AdvMat         = AdvMat or {}
AdvMat.SvApply = AdvMat.SvApply or {}

local SV    = AdvMat.SvApply
local Store = AdvMat.Store

---------------------------------------------------------------------------
-- Resolution
---------------------------------------------------------------------------
function Store.Resolve( ent, index, matPath )
	return AdvMat.ResolveRule( ent, index, matPath, Store.Rules, Store.EntityRules )
end

---------------------------------------------------------------------------
-- Applying
---------------------------------------------------------------------------

--- Bring one entity's sub-material overrides in line with the rule database.
function SV.Refresh( ent )
	if not IsValid( ent ) then return end

	local mdl = ent:GetModel()
	if not mdl or mdl == "" then return end

	local mats = ent:GetMaterials()
	if not istable( mats ) then return end

	local applied = ent.AdvMatApplied or {}
	local count   = math.min( #mats, AdvMat.GetMaterialLimit( ent ) )
	local any     = false

	-- With advmat_serverside 0 each client draws its own overrides, so the
	-- server must stay out of the way and release anything it already set.
	local serverOwns = GetConVar( "advmat_serverside" ):GetBool()

	-- A model change can reduce the number of material slots. Anything this
	-- addon owned beyond the new end must be released now; otherwise the stale
	-- override is forgotten by our bookkeeping and can reappear if the entity
	-- later changes back to a model with that slot.
	for idx in pairs( applied ) do
		if idx >= count then
			ent:SetSubMaterial( idx )
			applied[ idx ] = nil
		end
	end

	for i = 1, count do
		local idx  = i - 1
		local rule = serverOwns and Store.Resolve( ent, idx, mats[ i ] ) or nil

		if rule and not AdvMat.RuleIsEmpty( rule ) then
			local name = AdvMat.MaterialName( rule )
			local want = "!" .. name

			-- Private bookkeeping is only a cache. Full updates, model changes and
			-- other tools can alter the actual engine slot without updating it.
			-- Reassert on Save when either answer disagrees; this is especially
			-- important for slider-only edits, whose material name deliberately
			-- stays stable and otherwise gives the server no changed string to send.
			if applied[ idx ] ~= name or ( ent:GetSubMaterial( idx ) or "" ) ~= want then
				ent:SetSubMaterial( idx, want )
				applied[ idx ] = name
			end
			any = true

		elseif applied[ idx ] then
			-- Only clear the value if it is still ours. A different tool may have
			-- replaced the engine slot since our bookkeeping was recorded.
			if ( ent:GetSubMaterial( idx ) or "" ) == "!" .. applied[ idx ] then
				ent:SetSubMaterial( idx )
			end
			applied[ idx ] = nil
		end
	end

	ent.AdvMatApplied   = any and applied or nil
	ent.AdvMatLastModel = AdvMat.NormalizeModel( mdl )
end

function SV.RefreshAll()
	for _, ent in ipairs( ents.GetAll() ) do
		if IsValid( ent ) then SV.Refresh( ent ) end
	end
end

--- Refresh only the entities a particular rule can reach.
function SV.RefreshForRule( rule )
	if not istable( rule ) then return end

	-- World materials are edited in place on each client; no entity carries
	-- them and there is nothing for the server to apply.
	if rule.scope == AdvMat.SCOPE.WORLD then return end

	if rule.scope == AdvMat.SCOPE.ENTITY then
		local ent = isentity( rule.key ) and rule.key or Entity( tonumber( rule.key ) or 0 )
		if IsValid( ent ) then SV.Refresh( ent ) end
		return
	end

	if rule.scope == AdvMat.SCOPE.MODEL then
		local want = AdvMat.NormalizeModel( rule.key )
		for _, ent in ipairs( ents.GetAll() ) do
			if IsValid( ent ) and AdvMat.NormalizeModel( ent:GetModel() or "" ) == want then
				SV.Refresh( ent )
			end
		end
		return
	end

	-- MATERIAL scope can touch anything, so this is the expensive case. It
	-- only happens on an edit, never in a loop.
	local want = AdvMat.NormalizeMaterial( rule.key )
	for _, ent in ipairs( ents.GetAll() ) do
		if IsValid( ent ) and ent:GetModel() then
			for _, m in ipairs( ent:GetMaterials() or {} ) do
				if AdvMat.NormalizeMaterial( m ) == want then
					SV.Refresh( ent )
					break
				end
			end
		end
	end
end

---------------------------------------------------------------------------
-- Keeping up with the world
---------------------------------------------------------------------------
local function RefreshSoon( ent )
	-- A brand new entity has no model on the tick it is created.
	for _, delay in ipairs( { 0, 0.25, 1 } ) do
		timer.Simple( delay, function()
			if IsValid( ent ) then SV.Refresh( ent ) end
		end )
	end
end

hook.Add( "OnEntityCreated", "AdvMat.SvEntityCreated", function( ent )
	if table.IsEmpty( Store.Rules ) then return end
	RefreshSoon( ent )
end )

-- Models change at runtime constantly: playermodel switches, prop resizers,
-- Wiremod. A 1 Hz sweep comparing one cached string per entity is cheap, and
-- does nothing at all while the database is empty.
timer.Create( "AdvMat.SvModelWatch", 1, 0, function()
	if table.IsEmpty( Store.Rules ) and table.IsEmpty( Store.EntityRules ) then return end

	for _, ent in ipairs( ents.GetAll() ) do
		if IsValid( ent ) then
			local mdl = ent:GetModel()
			if mdl and mdl ~= "" and ent.AdvMatLastModel ~= AdvMat.NormalizeModel( mdl ) then
				SV.Refresh( ent )
			end
		end
	end
end )

hook.Add( "InitPostEntity", "AdvMat.SvInitialApply", function()
	timer.Simple( 1, SV.RefreshAll )
end )
