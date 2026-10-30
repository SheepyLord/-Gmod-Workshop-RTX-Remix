--[[---------------------------------------------------------------------------
	Advanced Material Editor - deterministic material naming

	Sub-material overrides are applied on the SERVER, which means the server
	sends clients a material NAME string and each client has to end up with a
	material of that name holding the right parameters. CreateMaterial is
	client only, so the name has to be derivable from the rule alone, the same
	way on every machine. That is what this file does.

	Two engine facts shape the naming scheme:

	  * Every distinct material name a server hands out becomes a networked
	    string, and the shared network string table is a finite, global
	    resource. A tool that mints a fresh name per edit will exhaust it, so
	    names must be stable across edits.

	  * CreateMaterial caches by name and ignores the key values on a second
	    call, and some parameters cannot be changed on a live material at all.
	    So the name has to change exactly when a material must be rebuilt from
	    scratch, and not one edit sooner.

	The name therefore hashes the rule's identity plus only those parameters
	that force a rebuild. Dragging a slider keeps the name; adding a bump map
	changes it.
-----------------------------------------------------------------------------]]

AdvMat = AdvMat or {}

---------------------------------------------------------------------------
-- Parameters stored in the $flags bitfield
---------------------------------------------------------------------------
-- These are not material vars. IMaterial:SetInt( "$translucent", 1 ) is a
-- silent no-op on them, so changing one always means rebuilding.
AdvMat.FLAG_PARAMS = {
	-- Names below are the VMT spellings of the MATERIAL_VAR_* bits in $flags.
	[ "$debug" ]                    = true,
	[ "$no_debug_override" ]        = true,
	[ "$no_fullbright" ]            = true,
	[ "$no_draw" ]                  = true,
	[ "$nodraw" ]                   = true,
	[ "$use_in_fillrate_mode" ]     = true,
	[ "$vertexcolor" ]              = true,
	[ "$vertexalpha" ]              = true,
	[ "$selfillum" ]                = true,
	[ "$additive" ]                 = true,
	[ "$alphatest" ]                = true,
	[ "$multipass" ]                = true,
	[ "$znearer" ]                  = true,
	[ "$model" ]                    = true,
	[ "$flat" ]                     = true,
	[ "$nocull" ]                   = true,
	[ "$nofog" ]                    = true,
	[ "$ignorez" ]                  = true,
	[ "$decal" ]                    = true,
	[ "$envmapsphere" ]             = true,
	[ "$noalphamod" ]               = true,
	[ "$envmapcameraspace" ]        = true,
	[ "$basealphaenvmapmask" ]      = true,
	[ "$translucent" ]              = true,
	[ "$normalmapalphaenvmapmask" ] = true,
	[ "$softwareskin" ]             = true,
	[ "$opaquetexture" ]            = true,
	[ "$envmapmode" ]               = true,
	[ "$nodecal" ]                  = true,
	[ "$halflambert" ]              = true,
	[ "$wireframe" ]                = true,
	[ "$allowalphatocoverage" ]     = true,
	[ "$vertexfog" ]                = true,
	[ "$nolod" ]                    = true,
}

-- Numeric values for the flag aliases the editor exposes. CreateMaterial
-- normally parses these VMT spellings, but procedural model materials have
-- proved inconsistent across engine branches. The client construction layer
-- uses this table to mirror each requested alias into $flags explicitly.
--
-- Keep the values numeric rather than using MATERIAL_VAR_* globals: Garry's
-- Mod exposes the bitfield through IMaterial but does not publish those enum
-- names to Lua.
AdvMat.FLAG_BITS = {
	[ "$debug" ]                    = 1,
	[ "$no_debug_override" ]        = 2,
	[ "$no_fullbright" ]            = 2,
	[ "$no_draw" ]                  = 4,
	[ "$nodraw" ]                   = 4,
	[ "$use_in_fillrate_mode" ]     = 8,
	[ "$vertexcolor" ]              = 16,
	[ "$vertexalpha" ]              = 32,
	[ "$selfillum" ]                = 64,
	[ "$additive" ]                 = 128,
	[ "$alphatest" ]                = 256,
	[ "$multipass" ]                = 512,
	[ "$znearer" ]                  = 1024,
	[ "$model" ]                    = 2048,
	[ "$flat" ]                     = 4096,
	[ "$nocull" ]                   = 8192,
	[ "$nofog" ]                    = 16384,
	[ "$ignorez" ]                  = 32768,
	[ "$decal" ]                    = 65536,
	[ "$envmapsphere" ]             = 131072,
	[ "$noalphamod" ]               = 262144,
	[ "$envmapcameraspace" ]        = 524288,
	[ "$basealphaenvmapmask" ]      = 1048576,
	[ "$translucent" ]              = 2097152,
	[ "$normalmapalphaenvmapmask" ] = 4194304,
	[ "$softwareskin" ]             = 8388608,
	[ "$opaquetexture" ]            = 16777216,
	[ "$envmapmode" ]               = 33554432,
	[ "$nodecal" ]                  = 67108864,
	[ "$halflambert" ]              = 134217728,
	[ "$wireframe" ]                = 268435456,
	[ "$allowalphatocoverage" ]     = 536870912,
}

-- Value types that cannot be safely written to a live material.
local REBUILD_TYPES = {
	texture   = true,
	string    = true,
	matrix    = true,
	transform = true,
	vector2   = true,
	vector4   = true,
}

--- True when changing `key` means the material has to be created again rather
--- than edited in place.
function AdvMat.ForcesRebuild( shader, key )
	if AdvMat.FLAG_PARAMS[ key ] then return true end

	local def = AdvMat.GetParamDef( shader, key )
	if not def then return true end

	-- Shader combo parameters select a shader permutation. Whether they can be
	-- flipped on a live material is genuinely disputed, so the editor takes
	-- the safe route and rebuilds.
	if def.compileTime then return true end

	return REBUILD_TYPES[ def.type ] == true
end

---------------------------------------------------------------------------
-- Hashing
---------------------------------------------------------------------------
-- The server and every client derive these names independently, so they must
-- all hash the same way. Choosing util.SHA1 when present and a CRC otherwise
-- gave a client on a branch without util.SHA1 a different name from the
-- server's, and it never built the material the entity was told to use.
-- AdvMat.SHA1 is one algorithm everywhere.
--
-- Names are derived again on every refresh of every slot, and the pure-Lua
-- SHA-1 is not free, so the digests are memoised. The inputs are rule
-- identities and signatures: a few hundred distinct strings in practice.
local hashMemo, hashMemoSize = {}, 0
local HASH_MEMO_LIMIT = 4096

local function Hash( s )
	local hit = hashMemo[ s ]
	if hit then return hit end

	hit = string.sub( AdvMat.SHA1( s ), 1, 10 )
	if hashMemoSize >= HASH_MEMO_LIMIT then hashMemo, hashMemoSize = {}, 0 end
	hashMemo[ s ] = hit
	hashMemoSize = hashMemoSize + 1
	return hit
end

--- The signature of everything about a rule that forces a rebuild.
function AdvMat.RebuildSignature( rule )
	-- Every value is checked rather than trusted. A rule is meant to be
	-- sanitised before it gets here, but this runs on the server for every slot
	-- of every entity: one malformed rule must not turn into an error per tick.
	local shader = isstring( rule.shader ) and rule.shader or "*"
	local keys   = {}
	local params = istable( rule.params ) and rule.params or {}

	for k in pairs( params ) do
		if isstring( k ) and AdvMat.ForcesRebuild( shader, k ) then keys[ #keys + 1 ] = k end
	end

	table.sort( keys )

	-- v2 normalises colour/vector parameters before CreateMaterial.  Include
	-- the construction revision in the shared name so an engine material that
	-- was cached with the old (wrong string-var) layout is never returned after
	-- a Lua hot reload.  The server and every client calculate the same name.
	local parts = { "material-build-v2", shader, isstring( rule.mat ) and rule.mat or "" }
	for _, k in ipairs( keys ) do
		parts[ #parts + 1 ] = k .. "=" .. tostring( params[ k ] )
	end

	return table.concat( parts, "\1" )
end

--- Procedural material name for a rule. Identical on the server and on every
--- client, and stable while only slider-style parameters are being changed.
--- Reference it from SetSubMaterial as "!" .. this.
function AdvMat.MaterialName( rule )
	local id = AdvMat.RuleID( rule.scope, rule.key, rule.index )
	return "advmat_" .. Hash( id ) .. "_" .. Hash( AdvMat.RebuildSignature( rule ) )
end

--- Opaque content token for the rule stored at one identity, or "" when there
--- is none. An editor sends the token of the version it loaded, and the server
--- refuses a save whose base is no longer current instead of silently replacing
--- a change somebody else made in the meantime.
---
--- Both realms derive it from the same canonical form the save handoff already
--- compares (cl_40_store), so nothing extra travels with each rule and neither
--- side depends on the other's JSON key order.
function AdvMat.RuleToken( rule )
	if not istable( rule ) then return "" end

	-- Canonicalised first, so a raw client message hashes like the rule the
	-- server would have stored from it, and junk cannot reach the hash. Values
	-- take their network spelling: the server only ever stores that one.
	local GEN    = AdvMat.Gen
	local params = AdvMat.SanitizeParams( rule.params )
	for k, v in pairs( params ) do params[ k ] = AdvMat.WireValue( v ) end

	local clean = {
		mat    = AdvMat.NormalizeMaterial( rule.mat or "" ),
		shader = isstring( rule.shader ) and rule.shader or "",
		params = params,
		gen    = GEN.SanitizeAll( rule.gen ),
	}

	if AdvMat.RuleIsEmpty( clean ) then return "" end
	return string.sub( AdvMat.SHA1( GEN.Canonical( clean ) ), 1, 16 )
end

---------------------------------------------------------------------------
-- Shared rule resolution
---------------------------------------------------------------------------

--- Find the rule that applies to submaterial `index` of `ent`, given a rule
--- table keyed by AdvMat.RuleID and a per-entity table. Highest priority
--- first: entity, then model, then material path.
function AdvMat.ResolveRule( ent, index, matPath, rules, entRules )
	if not IsValid( ent ) then return nil end

	local perEntity = entRules and entRules[ ent:EntIndex() ]
	if perEntity and perEntity[ index ] then return perEntity[ index ] end

	if not rules then return nil end

	local mdl = AdvMat.NormalizeModel( ent:GetModel() or "" )
	if mdl ~= "" then
		local rule = rules[ AdvMat.RuleID( AdvMat.SCOPE.MODEL, mdl, index ) ]
		if rule then return rule end
	end

	if not matPath then
		local mats = ent:GetMaterials()
		matPath = mats and mats[ index + 1 ]
	end

	if matPath then
		local rule = rules[ AdvMat.RuleID( AdvMat.SCOPE.MATERIAL, matPath ) ]
		if rule then return rule end
	end

	return nil
end
