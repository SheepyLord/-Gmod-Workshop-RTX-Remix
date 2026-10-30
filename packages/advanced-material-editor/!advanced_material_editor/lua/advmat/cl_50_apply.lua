--[[---------------------------------------------------------------------------
	Advanced Material Editor - clientside material construction

	The client's job is to make sure a procedural material exists under the
	exact name the server hands out for each rule, and to draw the unsaved
	preview while the editor is open.

	How a material is produced:

	  desired key values = the original .vmt's key values, with the rule's
	                       parameters merged on top

	  first time         = CreateMaterial( name, shader, desired )
	  afterwards         = write the changed values onto the existing material
	                       and Recompute() once

	CreateMaterial caches by name and ignores the key values on a repeat call,
	so the name (see sh_35_matname.lua) changes precisely when the material
	cannot be edited in place - a different shader, a flag parameter, or a
	texture. Sliders never change the name, so dragging one mutates a single
	material instead of leaking a new one every frame.
-----------------------------------------------------------------------------]]

AdvMat       = AdvMat or {}
AdvMat.Apply = AdvMat.Apply or {}

local A = AdvMat.Apply

A.Built     = A.Built     or {}  -- [materialName] = { mat = IMaterial, kv = {applied key values} }
A.BaseKV    = A.BaseKV    or {}  -- [materialPath] = { kv, shader, live } or false
A.ClientSet = A.ClientSet or {}  -- [entIndex] = { [subIndex] = materialName } set by us clientside
A.DecalOverrides = A.DecalOverrides or {} -- [entIndex] = saved RenderOverride state
A.WaitingForMMD = A.WaitingForMMD or false

A.WorldBackup  = A.WorldBackup  or {}  -- [path] = { [key] = original value }
A.WorldApplied = A.WorldApplied or {}  -- [path] = { [key] = true }

---------------------------------------------------------------------------
-- Reading a base material
---------------------------------------------------------------------------

--- Original key values of `path` as VMT literal strings, plus its shader.
--- Returns nil if the path does not resolve to anything.
---
--- The .vmt text is the preferred source. IMaterial:GetKeyValues() is only a
--- fallback because it reports every var the material currently has DEFINED,
--- including engine defaults the .vmt never mentioned, which would flood the
--- editor with parameters the author never set.
function A.ReadBase( path )
	path = AdvMat.NormalizeMaterial( path )
	if path == "" then return nil end

	-- Rules can arrive before the Hotloader, its package, or a large VTF upload.
	-- Do not ask Source to resolve an unmounted texture, or cache that first
	-- incomplete answer as the base of every future edit with this material name.
	local prepared, mmd = AdvMat.PrepareMMDMaterial( path )
	if not prepared then
		A.WaitingForMMD = true
		return nil, nil, nil, true
	end
	local mat
	if mmd then
		mat = Material( path )
		local texture = mat and not mat:IsError() and mat:GetTexture( "$basetexture" )
		if not texture or ( texture.IsError and texture:IsError() ) then
			A.WaitingForMMD = true
			return nil, nil, nil, true
		end
		if A.BaseKV[ path ] == false then A.BaseKV[ path ] = nil end
	end

	local cached = A.BaseKV[ path ]
	if cached ~= nil then
		if cached == false then return nil end
		return cached.kv, cached.shader, cached.live
	end

	local kv, shader = AdvMat.ParseVMT( path )

	mat = mat or Material( path )
	local live = ( mat and not mat:IsError() ) and mat or nil

	if not kv then
		if not live then
			A.BaseKV[ path ] = false
			return nil
		end

		kv = {}
		local raw = live:GetKeyValues()

		if istable( raw ) then
			for rawKey, v in pairs( raw ) do
				local k = string.lower( rawKey )
				if not AdvMat.IsInternalKey( k ) then
					local s = AdvMat.ToVMTString( v )
					if isstring( s ) and s ~= "" then kv[ k ] = s end
				end
			end
		end
	end

	if not shader or shader == "" then
		shader = live and live:GetShader() or "VertexLitGeneric"
	end

	-- "Patch" is an indirection stub, never a real shader.
	if string.lower( shader ) == "patch" then shader = "VertexLitGeneric" end

	-- Authors spell shader names every possible way; fold to one spelling so
	-- lookups and comparisons downstream all agree.
	shader = AdvMat.CanonicalShader( shader )

	-- A Patch chain we could not follow can leave us without a base texture.
	if not kv[ "$basetexture" ] and live then
		local ok, tex = pcall( live.GetTexture, live, "$basetexture" )
		if ok and tex and tex.GetName then
			kv[ "$basetexture" ] = AdvMat.NormalizeMaterial( tex:GetName() or "" )
		end
	end

	A.BaseKV[ path ] = { kv = kv, shader = shader, live = live }
	return kv, shader, live
end

---------------------------------------------------------------------------
-- Building / updating a material
---------------------------------------------------------------------------

--- The full key value set a rule asks for: the base material's own values
--- with the rule's parameters merged over them.
function A.DesiredKV( basePath, params )
	local kv, baseShader, _, pending = A.ReadBase( basePath )
	if pending then return nil, nil, true end

	local out = {}
	for k, v in pairs( kv or {} ) do out[ k ] = v end

	-- Everything built here reaches an entity through SetSubMaterial, so it is
	-- always a model material, and a VMT that omitted $model would produce one
	-- the engine refuses to light. World materials never come through this
	-- path: they are edited in place and keep their own settings. An explicit
	-- override in `params` still wins, because that merge happens below.
	out[ "$model" ] = out[ "$model" ] or "1"

	-- Network JSON automatically converts VMT-looking "[x y z]" and
	-- "{x y z}" strings into Vector/Angle objects. Normalise at this final
	-- boundary too, so CreateMaterial never receives userdata where it expects
	-- VMT literal strings even if a caller forgot to normalise an incoming rule.
	for k, v in pairs( AdvMat.SanitizeParams( params ) ) do
		if v == nil or v == "" then
			out[ k ] = nil
		else
			out[ k ] = v
		end
	end

	return out, baseShader
end

--- Make a copy whose vector-valued material vars are unambiguously vectors
--- to CreateMaterial.  The engine's ordinary VMT loader accepts shorthand
--- such as `$envmaptint .7 .7 .7` (and scalar colour shorthands), but the Lua
--- key-value entry point can otherwise retain them as STRING vars.  Shaders
--- subsequently call GetVecValue on that string every draw, flooding the
--- console and producing incorrect reflections.
function A.CreationKV( shader, values )
	local out = {}

	for key, value in pairs( values or {} ) do
		local def = AdvMat.GetParamDef( shader, key )
		local kind = def and def.type

		if kind == "color" or kind == "vector3" then
			local hasNumber = isnumber( value ) or isvector( value )

			if not hasNumber and isstring( value ) then
				for token in string.gmatch( value, "[-%d%.eE+]+" ) do
					if tonumber( token ) ~= nil then
						hasNumber = true
						break
					end
				end
			end

			if hasNumber then
				value = AdvMat.VectorToString( AdvMat.StringToVector( value ) )
			end
		end

		out[ key ] = value
	end

	return out
end

---------------------------------------------------------------------------
-- Texture transforms on a live material
---------------------------------------------------------------------------
-- A transform parameter is a MATRIX on a live material. GetKeyValues hands it
-- back as a VMatrix, which has no VMT spelling, and SetString does not reach a
-- matrix var. Procedural materials never meet this - a transform change
-- rebuilds them from text - but a map material is edited in place, so its
-- transforms are written as matrices and its original is kept as a matrix copy.

local function IsMatrixValue( v ) return TypeID( v ) == TYPE_MATRIX end

local function IsTransformKey( key )
	return isstring( key ) and string.find( key, "transform%d*$" ) ~= nil
end

local function CopyMatrix( m )
	if not isfunction( Matrix ) then return nil end
	local copy = Matrix()
	if not copy or not isfunction( copy.Set ) then return nil end
	copy:Set( m )
	return copy
end

--- The matrix Source makes of "center x y scale x y rotate d translate x y":
--- move the centre to the origin, scale, rotate about Z, then move back to the
--- centre plus the translation - the same composition as the engine's own
--- parser, so a map surface shows what the same text does on a model.
function A.TransformMatrix( text )
	if not isstring( text ) or not isfunction( Matrix ) then return nil end

	local t    = AdvMat.ParseTransform( text )
	local rad  = math.rad( t.rot )
	local c, s = math.cos( rad ), math.sin( rad )

	return Matrix( {
		{ c * t.sx, -s * t.sy, 0, -c * t.sx * t.cx + s * t.sy * t.cy + t.cx + t.tx },
		{ s * t.sx,  c * t.sy, 0, -s * t.sx * t.cx - c * t.sy * t.cy + t.cy + t.ty },
		{ 0, 0, 1, 0 },
		{ 0, 0, 0, 1 },
	} )
end

--- Write one VMT literal onto a live material, using the setter that matches
--- the parameter's declared type. A type mismatch is a silent no-op in the
--- engine, so getting this right is the difference between a value applying
--- and nothing happening at all.
local function WriteValue( mat, shader, key, value )
	-- A saved original transform comes back as the matrix it was copied from.
	if isfunction( mat.SetMatrix ) and ( IsMatrixValue( value ) or IsTransformKey( key ) ) then
		local m = IsMatrixValue( value ) and value or A.TransformMatrix( value )
		if m then
			mat:SetMatrix( key, m )
			return
		end
	end

	local def = AdvMat.GetParamDef( shader, key )
	local t   = def and def.type or "string"

	if t == "float" then
		mat:SetFloat( key, tonumber( value ) or 0 )
	elseif t == "int" or t == "bool" then
		mat:SetInt( key, math.Round( tonumber( value ) or 0 ) )
	elseif t == "color" or t == "vector3" then
		mat:SetVector( key, AdvMat.StringToVector( value ) )
	elseif t == "texture" then
		mat:SetTexture( key, value )
	else
		mat:SetString( key, value )
	end
end

-- Numbers are exact for every flag Source exposes here, so doing this without
-- LuaJIT's signed 32-bit bit library also handles materials whose high flag is
-- set. `enabled` is deliberately VMT-literal aware.
local function FlagEnabled( value )
	local n = tonumber( value )
	if n ~= nil then return n ~= 0 end
	return value == true or string.lower( tostring( value or "" ) ) == "true"
end

local function HasNumericFlag( value, mask )
	return math.floor( ( tonumber( value ) or 0 ) / mask ) % 2 == 1
end

local function WithNumericFlag( value, mask, enabled )
	value = tonumber( value ) or 0
	local has = HasNumericFlag( value, mask )
	if has == enabled then return value end
	return value + ( enabled and mask or -mask )
end

--- Material flag aliases such as $nodecal are not ordinary material vars.
--- Mirror them into the real $flags integer after creation instead of relying
--- on CreateMaterial's branch-dependent alias parsing.
local function SyncMaterialFlags( mat, desired )
	if not mat or not mat.GetInt or not mat.SetInt then return false end

	local before = tonumber( mat:GetInt( "$flags" ) ) or 0
	local after  = before

	for key, value in pairs( desired or {} ) do
		local mask = AdvMat.FLAG_BITS and AdvMat.FLAG_BITS[ key ]
		if mask then after = WithNumericFlag( after, mask, FlagEnabled( value ) ) end
	end

	if after == before then return false end
	mat:SetInt( "$flags", after )
	return true
end

--- Write `desired` onto an existing material, unsetting anything that is no
--- longer wanted. Returns true if anything actually changed.
local function MutateMaterial( mat, applied, desired, shader )
	local changed = false

	for k, v in pairs( desired ) do
		if applied[ k ] ~= v then
			WriteValue( mat, shader, k, v )
			changed = true
		end
	end

	for k in pairs( applied ) do
		if desired[ k ] == nil then
			mat:SetUndefined( k )
			changed = true
		end
	end

	-- SetFloat, SetVector and SetUndefined do not recompute on their own, and
	-- Recompute is slow, so it happens once here rather than per value.
	if changed then mat:Recompute() end

	return changed
end

--- Point any generated parameters at their images.
---
--- The rule's own value for such a parameter is only a placeholder that gets
--- the shader combo turned on; the real image is a PNG in the data folder that
--- has to be attached as a texture afterwards. A recipe that has not been built
--- yet returns nothing and queues itself, and the AdvMatGenerated hook brings us
--- back through here once it lands.
local function ApplyGenerated( entry, rule )
	entry.gen = entry.gen or {}

	-- Put keys whose recipe was dropped back onto their ordinary desired
	-- value. The placeholder path often stays unchanged when the user clicks
	-- Drop, so MutateMaterial cannot detect this transition on its own; without
	-- this pass the old generated ITexture remains attached forever.
	for key in pairs( entry.gen ) do
		if not ( istable( rule.gen ) and rule.gen[ key ] ) then
			local value = entry.kv[ key ]
			if value ~= nil then
				WriteValue( entry.mat, entry.shader, key, value )
			else
				entry.mat:SetUndefined( key )
			end
			entry.gen[ key ] = nil
		end
	end

	if not istable( rule.gen ) then return end

	for key, recipe in pairs( rule.gen ) do
		local tex = AdvMat.Gen.GetTexture( recipe )

		-- SetTexture recomputes the material, so only write when it changes.
		if tex and entry.gen[ key ] ~= tex then
			entry.mat:SetTexture( key, tex )
			entry.gen[ key ] = tex
		end
	end
end

--- Make sure the procedural material for `rule` exists and is up to date.
--- Returns the IMaterial and its name.
function A.BuildForRule( rule )
	if not istable( rule ) or not istable( rule.params ) then return nil end

	local name = AdvMat.MaterialName( rule )
	local base = ( rule.mat and rule.mat ~= "" ) and rule.mat or ""

	-- A material-scoped rule keys off the VMT path, so that path is also the
	-- material to start from when the rule never recorded one.
	if base == "" and rule.scope == AdvMat.SCOPE.MATERIAL then
		base = AdvMat.NormalizeMaterial( rule.key or "" )
	end

	local desired, baseShader, pending = A.DesiredKV( base, rule.params )
	if pending then return nil end
	local shader = rule.shader
	if not shader or shader == "" then shader = baseShader or "VertexLitGeneric" end

	local entry = A.Built[ name ]
	if AdvMat.DebugTraceActive then
		AdvMat.DebugTraceEvent( "material.build_begin", {
			name = name, reused = entry ~= nil, rule = rule, desired = desired,
			before = entry and AdvMat.DebugMaterialState( entry.mat, entry.shader ) or nil,
		} )
	end

	if not entry then
		local mat = CreateMaterial( name, shader, A.CreationKV( shader, desired ) )
		if not mat then return nil end
		SyncMaterialFlags( mat, desired )

		entry = { mat = mat, kv = table.Copy( desired ), shader = shader }
		A.Built[ name ] = entry

		ApplyGenerated( entry, rule )
		if AdvMat.DebugTraceActive then
			AdvMat.DebugTraceEvent( "material.build_created", {
				name = name, stored_kv = entry.kv,
				live = AdvMat.DebugMaterialState( entry.mat, entry.shader ),
			} )
		end

		return mat, name
	end

	MutateMaterial( entry.mat, entry.kv, desired, shader )
	SyncMaterialFlags( entry.mat, desired )
	entry.kv = table.Copy( desired )

	ApplyGenerated( entry, rule )
	if AdvMat.DebugTraceActive then
		AdvMat.DebugTraceEvent( "material.build_mutated", {
			name = name, stored_kv = entry.kv,
			live = AdvMat.DebugMaterialState( entry.mat, entry.shader ),
		} )
	end
	return entry.mat, name
end

--- Rebuild every material the client knows a rule for. Called after a sync so
--- the names the server references actually resolve to something.
function A.EnsureRuleMaterials()
	local C = AdvMat.Client

	for _, rule in pairs( C.Rules ) do
		-- World rules edit the map's material in place; there is no procedural
		-- material to build for them.
		if rule.scope ~= AdvMat.SCOPE.WORLD then A.BuildForRule( rule ) end
	end

	for _, set in pairs( C.EntRules ) do
		for _, rule in pairs( set ) do A.BuildForRule( rule ) end
	end
end

-- A rule can arrive before the generated image it references is ready. When
-- the queue finishes one, bring back through ApplyGenerated the materials whose
-- rules name THAT image, and refresh only the entities those rules reach -
-- previews included. Keeping this beside BuildForRule makes the promise above
-- self-contained; the image generator only has to publish the hook.
--
-- Rebuilding every material and refreshing every entity on each completion
-- made a server with many generated textures hitch once per finished image.

-- Output file per recipe table. Weak keys: a replaced rule drops out.
local recipeTarget = setmetatable( {}, { __mode = "k" } )

local function NamesImage( rule, target )
	if not istable( rule ) or not istable( rule.gen ) then return false end

	for _, recipe in pairs( rule.gen ) do
		local name = recipeTarget[ recipe ]
		if name == nil then
			local GEN = AdvMat.Gen
			name = ( istable( recipe ) and GEN and isfunction( GEN.FileName ) )
				and GEN.FileName( recipe ) or false
			if istable( recipe ) then recipeTarget[ recipe ] = name end
		end
		if name == target then return true end
	end

	return false
end

--- Re-attach one finished image everywhere it is wanted. Without a target
--- there is nothing to narrow by, so everything is brought up to date.
function A.ImageReady( target )
	if not isstring( target ) or target == "" then
		A.EnsureRuleMaterials()
		A.RefreshAll()
		return
	end

	local C       = AdvMat.Client
	local touched = {}

	local function Rebuild( rule )
		A.BuildForRule( rule )
		for _, ent in ipairs( C.EntitiesAffectedBy( rule ) ) do touched[ ent ] = true end
	end

	for _, rule in pairs( C.Rules ) do
		if rule.scope ~= AdvMat.SCOPE.WORLD and NamesImage( rule, target ) then Rebuild( rule ) end
	end

	for _, set in pairs( C.EntRules ) do
		for _, rule in pairs( set ) do
			if NamesImage( rule, target ) then Rebuild( rule ) end
		end
	end

	-- Previews are local to one entity each; refreshing it rebuilds them.
	for ei, set in pairs( C.Preview ) do
		for _, rule in pairs( set ) do
			if NamesImage( rule, target ) then
				local ent = Entity( ei )
				if IsValid( ent ) then touched[ ent ] = true end
				break
			end
		end
	end

	for ent in pairs( touched ) do
		if IsValid( ent ) then A.Refresh( ent ) end
	end
end

hook.Add( "AdvMatGenerated", "AdvMat.GenApply", function( _, target )
	A.ImageReady( target )
end )

-- GEN holds a failed recipe off for a few seconds and builds it again the next
-- time a material asks for it. Every finished image used to be such an ask,
-- for every rule. Now that completions are targeted, ask again explicitly -
-- a few times, for just the rules naming the image - so a transient failure
-- still recovers on its own.
local retries = {}
local MAX_GENERATION_RETRIES = 3

hook.Add( "AdvMatGenerationFailed", "AdvMat.GenRetry", function( _, target )
	if not isstring( target ) or target == "" then return end

	local n = ( retries[ target ] or 0 ) + 1
	if n > MAX_GENERATION_RETRIES then return end
	retries[ target ] = n

	timer.Create( "AdvMat.GenRetry." .. util.CRC( target ), 9, 1, function()
		A.ImageReady( target )
	end )
end )

hook.Add( "AdvMatGenerated", "AdvMat.GenRetryReset", function( _, target )
	if isstring( target ) then retries[ target ] = nil end
end )

function A.FlushCache()
	A.BaseKV = {}
	A.EnsureRuleMaterials()
	A.RefreshWorld()
	A.RefreshAll()
end

concommand.Add( "advmat_flushcache", function() A.FlushCache() end )

---------------------------------------------------------------------------
-- World materials
---------------------------------------------------------------------------
-- Brush geometry has no sub-material slots, so SetSubMaterial cannot reach a
-- map surface at all. The only way to retexture one at runtime is to edit the
-- shared IMaterial the map is already using. Two consequences worth knowing:
-- the change is visible on every surface using that .vmt, and it is local to
-- this client, because the material lives in the client's material system and
-- nothing about it is networked.
--
-- The material's original values are snapshotted the first time it is touched
-- so that removing the rule restores them without a map reload.

local function EnsureBackup( mat, path )
	local snap = A.WorldBackup[ path ]
	if snap then return snap end

	snap = {}

	for rawKey, v in pairs( mat:GetKeyValues() or {} ) do
		local key = string.lower( rawKey )

		-- A texture transform has no VMT literal to keep. Without a copy of the
		-- matrix itself, removing an edit used to unset it, which threw away the
		-- map's own transform until the map was reloaded.
		if IsMatrixValue( v ) then
			snap[ key ] = CopyMatrix( v )
		else
			local s = AdvMat.ToVMTString( v )
			if isstring( s ) then snap[ key ] = s end
		end
	end

	A.WorldBackup[ path ] = snap
	return snap
end

--- Put a key back the way the map had it, or unset it if the map never had it.
local function RestoreKey( mat, shader, backup, key )
	local original = backup[ key ]

	if original ~= nil then
		WriteValue( mat, shader, key, original )
	else
		mat:SetUndefined( key )
	end
end

--- Apply a world-scoped rule by editing the map's own material.
--- Returns the number of parameters that could not be applied.
function A.ApplyWorld( rule )
	if not istable( rule ) or not istable( rule.params ) then return 0 end

	local path = AdvMat.NormalizeMaterial( rule.key or rule.mat or "" )
	if path == "" then return 0 end

	local mat = Material( path )
	if not mat or mat:IsError() then return 0 end

	local backup  = EnsureBackup( mat, path )
	local applied = A.WorldApplied[ path ] or {}
	local shader  = AdvMat.CanonicalShader( rule.shader or mat:GetShader() )

	local changed, refused = false, 0

	for key, value in pairs( rule.params ) do
		-- $flags bits are not material vars, so there is no setter that can
		-- reach them on a live material. Creating a replacement is not an
		-- option here either, because the map is drawing this exact material.
		if AdvMat.FLAG_PARAMS[ key ] then
			refused = refused + 1
		else
			WriteValue( mat, shader, key, value )
			applied[ key ] = true
			changed = true
		end
	end

	for key in pairs( applied ) do
		if rule.params[ key ] == nil then
			RestoreKey( mat, shader, backup, key )
			applied[ key ] = nil
			changed = true
		end
	end

	A.WorldApplied[ path ] = ( not table.IsEmpty( applied ) ) and applied or nil

	if changed then mat:Recompute() end
	return refused
end

--- Undo everything this addon wrote onto a map material.
function A.RestoreWorld( path )
	path = AdvMat.NormalizeMaterial( path )

	local applied = A.WorldApplied[ path ]
	if not applied then return end

	local mat = Material( path )

	if mat and not mat:IsError() then
		local backup = A.WorldBackup[ path ] or {}
		local shader = AdvMat.CanonicalShader( mat:GetShader() )

		for key in pairs( applied ) do
			RestoreKey( mat, shader, backup, key )
		end

		mat:Recompute()
	end

	A.WorldApplied[ path ] = nil
end

--- Bring every map material in line with the world-scoped rules, restoring
--- any that no longer has one.
function A.RefreshWorld()
	local wanted = {}

	for _, rule in pairs( AdvMat.Client.Rules ) do
		if rule.scope == AdvMat.SCOPE.WORLD then
			wanted[ AdvMat.NormalizeMaterial( rule.key ) ] = rule
		end
	end

	for path in pairs( A.WorldApplied ) do
		if not wanted[ path ] then A.RestoreWorld( path ) end
	end

	for _, rule in pairs( wanted ) do A.ApplyWorld( rule ) end
end

---------------------------------------------------------------------------
-- Clientside application
---------------------------------------------------------------------------
-- The server owns committed rules and applies them itself, which is what
-- makes them survive an entity leaving and re-entering the PVS. The client
-- only ever applies:
--
--   * the unsaved preview from an open editor
--   * everything, when advmat_serverside is 0
--
-- A clientside sub-material override is wiped whenever the server sends a
-- full update for that entity, so anything applied here is re-applied on a
-- short timer.

local function ClientSideMode()
	local cv = GetConVar( "advmat_serverside" )
	return cv and not cv:GetBool()
end

--- The rule the client itself should be drawing for a slot, or nil.
--- `owned` means the client has already written to this slot on this entity.
local function ClientRuleFor( ent, idx, matPath, owned )
	local C  = AdvMat.Client
	local ei = ent:EntIndex()

	local preview = C.Preview[ ei ]
	if preview and preview[ idx ] then return preview[ idx ] end

	-- Once the client has written a sub-material there is no way to hand the
	-- slot back to the server's networked value: Entity:SetSubMaterial( idx )
	-- clears the client's copy, and the server has no reason to re-send what,
	-- from its side, never changed. The slot then renders as the model's
	-- default until the entity next re-enters the PVS.
	--
	-- So a slot the client owns must always be written with the right value,
	-- never blanked. When the preview goes away the committed rule is written
	-- in its place, which is the same material the server is pointing at.
	if owned or ClientSideMode() then
		return AdvMat.ResolveRule( ent, idx, matPath, C.Rules, C.EntRules )
	end

	return nil
end

---------------------------------------------------------------------------
-- Model decals
---------------------------------------------------------------------------
-- Studio decals are a separate render list attached to the model. Changing a
-- sub-material's MATERIAL_VAR_SUPPRESS_DECALS bit does not reliably remove
-- decals already in that list, and some branches still project new decals by
-- consulting the model's original material. STUDIO_SKIP_DECALS is entity-wide,
-- so the closest exact runtime behaviour Lua can provide is: if any effective
-- slot enables $nodecal, render no studio decals on that prop.

local STUDIO_RENDER_DEFAULT = STUDIO_RENDER or 1
local STUDIO_SKIP_DECAL_FLAG = STUDIO_SKIP_DECALS or 268435456

local function RuleSuppressesDecals( rule )
	return istable( rule ) and istable( rule.params )
		and FlagEnabled( rule.params[ "$nodecal" ] )
end

local function EntitySuppressesDecals( ent, mats, count )
	local C       = AdvMat.Client
	local preview = C.Preview[ ent:EntIndex() ]

	for i = 1, count do
		local idx  = i - 1
		local rule = preview and preview[ idx ]
			or AdvMat.ResolveRule( ent, idx, mats[ i ], C.Rules, C.EntRules )

		if RuleSuppressesDecals( rule ) then return true end
	end

	return false
end

local function ClearModelDecals( ent )
	if ent.RemoveAllDecals then ent:RemoveAllDecals() end
end

local function SetDecalSuppression( ent, enabled )
	local ei    = ent:EntIndex()
	local state = A.DecalOverrides[ ei ]

	-- EntIndex values are reused. Never restore a wrapper captured for the old
	-- entity onto the new one.
	if state and state.ent ~= ent then
		A.DecalOverrides[ ei ] = nil
		state = nil
	end

	if enabled then
		if state then return end

		state = { ent = ent, previous = ent.RenderOverride }
		state.wrapper = function( self, flags )
			flags = WithNumericFlag( flags or STUDIO_RENDER_DEFAULT,
				STUDIO_SKIP_DECAL_FLAG, true )

			if isfunction( state.previous ) then
				return state.previous( self, flags )
			end

			return self:DrawModel( flags )
		end

		A.DecalOverrides[ ei ] = state
		ent.RenderOverride = state.wrapper
		ClearModelDecals( ent )

		if AdvMat.DebugTraceActive then
			AdvMat.DebugTraceEvent( "entity.nodecal", { entity = ei, enabled = true } )
		end
		return
	end

	if not state then return end

	-- Discard anything projected while rendering was suppressed, then restore
	-- the exact callback that was present before the editor intervened. If a
	-- third party replaced our wrapper meanwhile, leave its callback alone.
	ClearModelDecals( ent )
	if ent.RenderOverride == state.wrapper then ent.RenderOverride = state.previous end
	A.DecalOverrides[ ei ] = nil

	if AdvMat.DebugTraceActive then
		AdvMat.DebugTraceEvent( "entity.nodecal", { entity = ei, enabled = false } )
	end
end

--- Recompute the clientside overrides on one entity.
function A.Refresh( ent )
	if not IsValid( ent ) then return end

	local ei = ent:EntIndex()
	local mdl = ent:GetModel()
	if not mdl or mdl == "" then
		SetDecalSuppression( ent, false )
		return
	end

	local mats = ent:GetMaterials()
	if not istable( mats ) then
		SetDecalSuppression( ent, false )
		return
	end

	local applied = A.ClientSet[ ei ] or {}
	local count   = math.min( #mats, AdvMat.GetMaterialLimit( ent ) )
	local any     = false

	-- This must run even in server-authoritative mode: the server can select a
	-- sub-material, but only the client controls the model's studio draw flags.
	SetDecalSuppression( ent, EntitySuppressesDecals( ent, mats, count ) )

	-- In the normal server-authoritative mode there is no sub-material work to
	-- do unless this entity is being previewed or was previously drawn by us.
	if not ClientSideMode()
		and not AdvMat.Client.Preview[ ei ]
		and not A.ClientSet[ ei ] then
		return
	end

	-- SetModel does not reliably clear clientside sub-material slots. Release
	-- anything beyond the new material count before forgetting that we owned
	-- it, or it can resurface when this entity later grows more slots again.
	for idx in pairs( applied ) do
		if idx >= count then
			ent:SetSubMaterial( idx )
			applied[ idx ] = nil
		end
	end

	for i = 1, count do
		local idx  = i - 1
		local rule = ClientRuleFor( ent, idx, mats[ i ], applied[ idx ] ~= nil )
		local before = AdvMat.DebugTraceActive and ( ent:GetSubMaterial( idx ) or "" ) or nil

		if rule and not AdvMat.RuleIsEmpty( rule ) then
			local _, name = A.BuildForRule( rule )
			if name then
				ent:SetSubMaterial( idx, "!" .. name )
				applied[ idx ] = name
				any = true
			end
		elseif applied[ idx ] then
			-- Only ever clear slots this addon set clientside, so overrides
			-- from other tools are left alone.
			ent:SetSubMaterial( idx )
			applied[ idx ] = nil
		end

		if AdvMat.DebugTraceActive and ( before ~= ( ent:GetSubMaterial( idx ) or "" )
			or ( AdvMat.Editor and AdvMat.Editor.Entity == ent and idx == AdvMat.Editor.Selected ) ) then
			AdvMat.DebugTraceEvent( "entity.slot_refresh", {
				entity = ei, index = idx, before = before,
				after = ent:GetSubMaterial( idx ) or "",
				applied = applied[ idx ], rule = rule,
			} )
		end
	end

	A.ClientSet[ ei ] = any and applied or nil
end

function A.RefreshAll()
	for _, ent in ipairs( ents.GetAll() ) do
		if IsValid( ent ) then A.Refresh( ent ) end
	end
end

concommand.Add( "advmat_refresh", function()
	AdvMat.Apply.EnsureRuleMaterials()
	AdvMat.Apply.RefreshAll()
end )

---------------------------------------------------------------------------
-- Re-application
---------------------------------------------------------------------------
-- Entity:SetSubMaterial set on the client is silently reverted to the
-- server's value roughly five ticks after the entity re-enters the PVS, and
-- Entity:GetSubMaterial on the client reports the server's value rather than
-- ours, so there is nothing to read back. The only reliable answer is to
-- write it again periodically. This only runs while something is actually
-- being drawn clientside.
timer.Create( "AdvMat.Reapply", 0.25, 0, function()
	if A.WaitingForMMD then
		A.WaitingForMMD = false
		A.EnsureRuleMaterials()
		A.RefreshAll()
	end
	if table.IsEmpty( A.ClientSet ) then return end

	for ei, slots in pairs( A.ClientSet ) do
		local ent = Entity( ei )

		if IsValid( ent ) then
			for idx, name in pairs( slots ) do
				ent:SetSubMaterial( idx, "!" .. name )
			end
		else
			A.ClientSet[ ei ] = nil
		end
	end
end )

---------------------------------------------------------------------------
-- Keeping up with the world
---------------------------------------------------------------------------
local function RefreshSoon( ent )
	for _, delay in ipairs( { 0, 0.25, 1 } ) do
		timer.Simple( delay, function()
			if IsValid( ent ) then A.Refresh( ent ) end
		end )
	end
end

hook.Add( "NetworkEntityCreated", "AdvMat.NetworkEntityCreated", RefreshSoon )

hook.Add( "EntityRemoved", "AdvMat.ClientEntityRemoved", function( ent )
	local state = A.DecalOverrides[ ent:EntIndex() ]
	if state and state.ent == ent then A.DecalOverrides[ ent:EntIndex() ] = nil end
end )

hook.Add( "InitPostEntity", "AdvMat.InitialApply", function()
	timer.Simple( 2, function()
		A.EnsureRuleMaterials()
		A.RefreshAll()
	end )
end )

---------------------------------------------------------------------------
-- Missing-material watchdog
---------------------------------------------------------------------------
-- Procedural materials die on map shutdown, but the "!advmat_..." string the
-- server put on an entity survives in save and dupe data. On a rejoin the
-- entity therefore asks for a material nothing has recreated yet and renders
-- as the missing-texture checkerboard.
--
-- Entity:GetSubMaterial returns the SERVER's value on the client, which is
-- exactly what makes this detectable: an entity asking for an advmat_ material
-- we have not built means our rule database is behind, and a resync fixes it.
--
-- This is a one-shot sweep rather than a standing timer; the only window where
-- it can happen is shortly after joining or after a sync.
local nextSweep = 0

function A.SweepForMissing()
	if CurTime() < nextSweep then return end
	nextSweep = CurTime() + 15

	for _, ent in ipairs( ents.GetAll() ) do
		if IsValid( ent ) and ent:GetModel() then
			for idx = 0, AdvMat.GetMaterialLimit( ent ) - 1 do
				local name = ent:GetSubMaterial( idx )

				if isstring( name ) and string.sub( name, 1, 8 ) == "!advmat_"
					and not A.Built[ string.sub( name, 2 ) ] then
					AdvMat.Log( "An entity wants a material we have not built; resyncing." )
					AdvMat.Client.RequestSync()
					return
				end
			end
		end
	end
end

hook.Add( "InitPostEntity", "AdvMat.MissingSweep", function()
	timer.Simple( 8,  A.SweepForMissing )
	timer.Simple( 25, A.SweepForMissing )
end )
