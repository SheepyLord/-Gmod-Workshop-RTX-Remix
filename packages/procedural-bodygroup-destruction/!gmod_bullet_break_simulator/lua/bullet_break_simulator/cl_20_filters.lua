-- Persistent user-facing model and bodygroup damage filters.

BBS = BBS or {}

local FILTER_DIRECTORY = "bbs"
local FILTER_PATH = FILTER_DIRECTORY .. "/filters.json"
local DEFAULT_BODYGROUP_DENYLIST = { "Arm", "Arms", "Hair", "Face", "Body" }

local function NormalizeModelPath( value )
	local path = string.lower( string.Trim( tostring( value or "" ) ) )
	path = string.gsub( path, "\\", "/" )
	path = string.gsub( path, "^/*", "" )
	path = string.gsub( path, "/+", "/" )
	if path == "" then return nil end
	if string.sub( path, 1, 7 ) ~= "models/" then path = "models/" .. path end
	if string.sub( path, -4 ) ~= ".mdl" then path = path .. ".mdl" end
	return path
end

local function NormalizeBodygroupName( value )
	local name = string.Trim( tostring( value or "" ) )
	if name == "" then return nil end
	return name
end

local function NormalizeMode( value )
	return string.lower( tostring( value or "" ) ) == "whitelist"
		and "whitelist" or "blacklist"
end

local function SanitizeList( source, normalizer )
	local result = {}
	local seen = {}
	for _, value in pairs( istable( source ) and source or {} ) do
		local normalized = normalizer( value )
		local key = normalized and string.lower( normalized ) or nil
		if key and not seen[ key ] then
			seen[ key ] = true
			result[ #result + 1 ] = normalized
		end
	end
	table.sort( result, function( left, right )
		return string.lower( left ) < string.lower( right )
	end )
	return result
end

local function SanitizeBodygroupOverrides( source )
	local result = {}
	local seen = {}
	for _, raw in pairs( istable( source ) and source or {} ) do
		if istable( raw ) then
			local model = NormalizeModelPath( raw.model or raw.path )
			local name = NormalizeBodygroupName(
				raw.bodygroup or raw.name or raw.bodygroupName )
			local id = tonumber( raw.id or raw.bodygroupId )
			if id ~= nil then
				id = math.floor( id )
				if id < 0 then id = nil end
			end
			if model and ( name or id ~= nil ) then
				local idIdentity = id ~= nil and ( model .. "|id:" .. id ) or nil
				local nameIdentity = name and ( model .. "|name:"
					.. string.lower( name ) ) or nil
				if not ( idIdentity and seen[ idIdentity ] )
				and not ( nameIdentity and seen[ nameIdentity ] ) then
					if idIdentity then seen[ idIdentity ] = true end
					if nameIdentity then seen[ nameIdentity ] = true end
					result[ #result + 1 ] = {
						model = model,
						bodygroup = name,
						id = id,
					}
				end
			end
		end
	end
	table.sort( result, function( left, right )
		if left.model ~= right.model then return left.model < right.model end
		local leftId = left.id == nil and math.huge or left.id
		local rightId = right.id == nil and math.huge or right.id
		if leftId ~= rightId then return leftId < rightId end
		return string.lower( left.bodygroup or "" )
			< string.lower( right.bodygroup or "" )
	end )
	return result
end

local function DefaultConfig()
	return {
		format = 2,
		modelMode = "blacklist",
		models = {},
		bodygroups = table.Copy( DEFAULT_BODYGROUP_DENYLIST ),
		hideableBodygroupOverrides = {},
	}
end

local function SanitizeConfig( source )
	source = istable( source ) and source or {}
	return {
		format = 2,
		modelMode = NormalizeMode( source.modelMode ),
		models = SanitizeList( source.models, NormalizeModelPath ),
		bodygroups = SanitizeList( source.bodygroups or DEFAULT_BODYGROUP_DENYLIST,
			NormalizeBodygroupName ),
		hideableBodygroupOverrides = SanitizeBodygroupOverrides(
			source.hideableBodygroupOverrides or source.bodygroupOverrides ),
	}
end

local function RebuildIndexes()
	local config = BBS.DamageFilterConfig or DefaultConfig()
	local modelIndex = {}
	local bodygroupIndex = {}
	local overrideModelIndex = {}
	for _, path in ipairs( config.models or {} ) do
		modelIndex[ string.lower( path ) ] = true
	end
	for _, name in ipairs( config.bodygroups or {} ) do
		bodygroupIndex[ string.lower( name ) ] = true
	end
	for _, override in ipairs( config.hideableBodygroupOverrides or {} ) do
		overrideModelIndex[ override.model ] =
			overrideModelIndex[ override.model ] or {}
		overrideModelIndex[ override.model ][ #overrideModelIndex[ override.model ] + 1 ] =
			override
	end
	BBS.DamageFilterModelIndex = modelIndex
	BBS.DamageFilterBodygroupIndex = bodygroupIndex
	BBS.HideableBodygroupOverrideModelIndex = overrideModelIndex
end

local function InvalidateEligibilityCaches()
	-- Raw model meshes do not depend on these lists. Only the differential
	-- bodygroup ownership cache and queued prewarm eligibility work do.
	BBS.HideableMeshCache = {}
	-- An RTX cleanup is a memory-safety barrier, not disposable eligibility work.
	-- Keep it at the head while invalidating its old result; its revision check
	-- below will rerun eligibility after the native graph has been collected.
	local retainedCleanup = {}
	local retainedEntities = setmetatable( {}, { __mode = "k" } )
	for _, job in ipairs( BBS.MeshPrewarmQueue or {} ) do
		if job.phase == "rtx_cleanup" then
			retainedCleanup[ #retainedCleanup + 1 ] = job
			if IsValid( job.entity ) then retainedEntities[ job.entity ] = true end
		end
	end
	BBS.MeshPrewarmQueue = retainedCleanup
	BBS.MeshPrewarmQueued = retainedEntities
	BBS.DamageFilterRevision = ( BBS.DamageFilterRevision or 0 ) + 1
	hook.Run( "BBS.DamageFiltersChanged", BBS.DamageFilterConfig )
end

local function WriteConfig()
	file.CreateDir( FILTER_DIRECTORY )
	local encoded = util.TableToJSON( BBS.DamageFilterConfig, true )
	if not encoded then return false, "could not encode filter configuration" end
	file.Write( FILTER_PATH, encoded )
	return true
end

function BBS.LoadDamageFilters()
	local source = nil
	local raw = file.Read( FILTER_PATH, "DATA" )
	if raw and raw ~= "" then source = util.JSONToTable( raw ) end
	BBS.DamageFilterConfig = SanitizeConfig( source or DefaultConfig() )
	RebuildIndexes()
	InvalidateEligibilityCaches()
	-- Create or repair the human-readable canonical file on every load.
	WriteConfig()
	return BBS.DamageFilterConfig
end

function BBS.SaveDamageFilters()
	BBS.DamageFilterConfig = SanitizeConfig( BBS.DamageFilterConfig )
	RebuildIndexes()
	InvalidateEligibilityCaches()
	return WriteConfig()
end

function BBS.GetDamageFilterConfig()
	return BBS.DamageFilterConfig or BBS.LoadDamageFilters()
end

function BBS.GetDamageFilterPath()
	return "data/" .. FILTER_PATH
end

function BBS.IsModelDamageAllowed( model )
	local config = BBS.GetDamageFilterConfig()
	local normalized = NormalizeModelPath( model )
	if not normalized then return false, "invalid model path", nil end
	local listed = BBS.DamageFilterModelIndex[ normalized ] == true
	if config.modelMode == "whitelist" then
		return listed, listed and "model is whitelisted" or "model is not whitelisted",
			normalized
	end
	return not listed, listed and "model is blacklisted" or "model is not blacklisted",
		normalized
end

function BBS.IsBodygroupDamageAllowed( name )
	local normalized = NormalizeBodygroupName( name )
	if not normalized then return false, "empty bodygroup name" end
	local blocked = BBS.DamageFilterBodygroupIndex[ string.lower( normalized ) ] == true
	return not blocked, blocked and "bodygroup name is blacklisted"
		or "bodygroup name is not blacklisted"
end

-- Explicit per-model overrides are the highest-priority bodygroup decision.
-- A matching ID or name makes the group eligible even when it has no blank
-- submodel and even when the global exact-name denylist contains its name.
function BBS.IsHideableBodygroupOverridden( model, bodygroupId, bodygroupName )
	local normalizedModel = NormalizeModelPath( model )
	if not normalizedModel then return false, nil end
	local id = tonumber( bodygroupId )
	if id ~= nil then id = math.floor( id ) end
	local normalizedName = NormalizeBodygroupName( bodygroupName )
	local lowerName = normalizedName and string.lower( normalizedName ) or nil
	local modelIndex = BBS.HideableBodygroupOverrideModelIndex or {}
	for _, override in ipairs( modelIndex[ normalizedModel ] or {} ) do
		local idMatches = id ~= nil and override.id ~= nil and override.id == id
		local nameMatches = lowerName ~= nil and override.bodygroup ~= nil
			and string.lower( override.bodygroup ) == lowerName
		if idMatches or nameMatches then return true, override end
	end
	return false, nil
end

function BBS.SetModelFilterMode( mode )
	local config = BBS.GetDamageFilterConfig()
	config.modelMode = NormalizeMode( mode )
	return BBS.SaveDamageFilters()
end

function BBS.AddModelFilter( value )
	local normalized = NormalizeModelPath( value )
	if not normalized then return false, "enter a model path" end
	local config = BBS.GetDamageFilterConfig()
	if BBS.DamageFilterModelIndex[ normalized ] then
		return false, "model is already in the list"
	end
	config.models[ #config.models + 1 ] = normalized
	local saved, errorMessage = BBS.SaveDamageFilters()
	return saved, errorMessage or normalized
end

function BBS.RemoveModelFilter( value )
	local normalized = NormalizeModelPath( value )
	if not normalized then return false, "invalid model path" end
	local config = BBS.GetDamageFilterConfig()
	for index, path in ipairs( config.models ) do
		if path == normalized then
			table.remove( config.models, index )
			local saved, errorMessage = BBS.SaveDamageFilters()
			return saved, errorMessage or normalized
		end
	end
	return false, "model was not in the list"
end

function BBS.ClearModelFilters()
	BBS.GetDamageFilterConfig().models = {}
	return BBS.SaveDamageFilters()
end

function BBS.AddBodygroupFilter( value )
	local normalized = NormalizeBodygroupName( value )
	if not normalized then return false, "enter a bodygroup name" end
	local key = string.lower( normalized )
	local config = BBS.GetDamageFilterConfig()
	if BBS.DamageFilterBodygroupIndex[ key ] then
		return false, "bodygroup is already excluded"
	end
	config.bodygroups[ #config.bodygroups + 1 ] = normalized
	local saved, errorMessage = BBS.SaveDamageFilters()
	return saved, errorMessage or normalized
end

function BBS.RemoveBodygroupFilter( value )
	local normalized = NormalizeBodygroupName( value )
	if not normalized then return false, "invalid bodygroup name" end
	local key = string.lower( normalized )
	local config = BBS.GetDamageFilterConfig()
	for index, name in ipairs( config.bodygroups ) do
		if string.lower( name ) == key then
			table.remove( config.bodygroups, index )
			local saved, errorMessage = BBS.SaveDamageFilters()
			return saved, errorMessage or normalized
		end
	end
	return false, "bodygroup was not excluded"
end

function BBS.ResetBodygroupFilters()
	BBS.GetDamageFilterConfig().bodygroups = table.Copy( DEFAULT_BODYGROUP_DENYLIST )
	return BBS.SaveDamageFilters()
end

local function SameBodygroupOverride( override, model, id, name )
	if override.model ~= model then return false end
	if id ~= nil and override.id ~= nil and override.id == id then return true end
	return name ~= nil and override.bodygroup ~= nil
		and string.lower( override.bodygroup ) == string.lower( name )
end

function BBS.AddHideableBodygroupOverride( model, bodygroupId, bodygroupName )
	local normalizedModel = NormalizeModelPath( model )
	local normalizedName = NormalizeBodygroupName( bodygroupName )
	local id = tonumber( bodygroupId )
	if id ~= nil then
		id = math.floor( id )
		if id < 0 then id = nil end
	end
	if not normalizedModel then return false, "enter a valid model path" end
	if id == nil and not normalizedName then
		return false, "enter a bodygroup ID or name"
	end
	local config = BBS.GetDamageFilterConfig()
	for _, override in ipairs( config.hideableBodygroupOverrides ) do
		if SameBodygroupOverride( override, normalizedModel, id, normalizedName ) then
			return false, "bodygroup override already exists"
		end
	end
	config.hideableBodygroupOverrides[ #config.hideableBodygroupOverrides + 1 ] = {
		model = normalizedModel,
		bodygroup = normalizedName,
		id = id,
	}
	local saved, errorMessage = BBS.SaveDamageFilters()
	return saved, errorMessage or string.format( "%s | %s:%s", normalizedModel,
		tostring( id or "*" ), tostring( normalizedName or "<unnamed>" ) )
end

function BBS.RemoveHideableBodygroupOverride( model, bodygroupId, bodygroupName )
	local normalizedModel = NormalizeModelPath( model )
	local normalizedName = NormalizeBodygroupName( bodygroupName )
	local id = tonumber( bodygroupId )
	if id ~= nil then id = math.floor( id ) end
	if not normalizedModel then return false, "invalid model path" end
	local config = BBS.GetDamageFilterConfig()
	for index, override in ipairs( config.hideableBodygroupOverrides ) do
		if SameBodygroupOverride( override, normalizedModel, id, normalizedName ) then
			table.remove( config.hideableBodygroupOverrides, index )
			local saved, errorMessage = BBS.SaveDamageFilters()
			return saved, errorMessage or normalizedModel
		end
	end
	return false, "bodygroup override was not found"
end

function BBS.ClearHideableBodygroupOverrides()
	BBS.GetDamageFilterConfig().hideableBodygroupOverrides = {}
	return BBS.SaveDamageFilters()
end

local function LogMutation( success, value, action )
	if success then
		BBS.Log( "%s: %s", action, tostring( value or "saved" ) )
	else
		BBS.Log( "%s failed: %s", action, tostring( value or "unknown error" ) )
	end
end

concommand.Add( "bbs_filter_status", function()
	local config = BBS.GetDamageFilterConfig()
	BBS.Log( "damage filters: modelMode=%s models=%d bodygroups=%d hideableOverrides=%d file=%s",
		config.modelMode, #config.models, #config.bodygroups,
		#config.hideableBodygroupOverrides, BBS.GetDamageFilterPath() )
	for _, model in ipairs( config.models ) do BBS.Log( "  model=%s", model ) end
	for _, name in ipairs( config.bodygroups ) do BBS.Log( "  bodygroup=%s", name ) end
	for _, override in ipairs( config.hideableBodygroupOverrides ) do
		BBS.Log( "  hideableOverride model=%s bodygroup=%s id=%s priority=highest blacklistBypass=true",
			override.model, tostring( override.bodygroup ), tostring( override.id ) )
	end
end, nil, "Print the current Procedural Bodygroup Destruction model/bodygroup filters." )

concommand.Add( "bbs_filter_reload", function()
	local config = BBS.LoadDamageFilters()
	BBS.Log( "reloaded damage filters: mode=%s models=%d bodygroups=%d hideableOverrides=%d from %s",
		config.modelMode, #config.models, #config.bodygroups,
		#config.hideableBodygroupOverrides, BBS.GetDamageFilterPath() )
end, nil, "Reload Procedural Bodygroup Destruction filters from the data JSON file." )

concommand.Add( "bbs_filter_add_aimed_model", function()
	local player = LocalPlayer()
	local entity = IsValid( player ) and player:GetEyeTrace().Entity or nil
	if not IsValid( entity ) then
		BBS.Log( "add aimed model failed: aim at an entity" )
		return
	end
	local success, value = BBS.AddModelFilter( entity:GetModel() )
	LogMutation( success, value, "model filter add" )
end, nil, "Add the aimed entity's model to the active model list." )

BBS.LoadDamageFilters()
