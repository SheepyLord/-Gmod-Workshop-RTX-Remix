-- Advanced Bodygroup Tool - shared state, networking, and duplicator support.

AdvancedBodygroupTool = AdvancedBodygroupTool or {}
local ABT = AdvancedBodygroupTool

ABT.ModifierName = "advanced_bodygroup_tool"
ABT.HiddenNWKey = "ABT_HiddenBodygroups"
ABT.HiddenRegionsNWKey = "ABT_HiddenBodygroupRegions"
ABT.HiddenRegionsChunkPrefix = "ABT_HiddenBodygroupRegions_"
ABT.HiddenRegionsChunkCountNWKey = "ABT_HiddenBodygroupRegionChunks"
ABT.VertexKeepNWKey = "ABT_VertexKeepBounds"
ABT.VertexKeepChunkPrefix = "ABT_VertexKeepBounds_"
ABT.VertexKeepChunkCountNWKey = "ABT_VertexKeepBoundChunks"
ABT.MaxVertexCutsPerGroup = 16
ABT.MaxVertexCuts = 64
ABT.VertexKeepMaxChunks = 16
ABT.RevisionNWKey = "ABT_Revision"
ABT.Action = ABT.Action or {}
ABT.Action.SetSkin = 0
ABT.Action.SetBodygroup = 1
ABT.Action.SetForceHidden = 2
ABT.Action.RestoreForceHidden = 3
ABT.Action.SetRegionHidden = 4
ABT.Action.HideAllHideable = 5
ABT.Action.ShowAllReset = 6
ABT.Action.SetVertexKeepBounds = 7

local function SafeFiniteNumber( value, maximumMagnitude )
	value = tonumber( value )
	if not value or value ~= value or value == math.huge
	or value == -math.huge then return nil end
	if maximumMagnitude and math.abs( value ) > maximumMagnitude then return nil end
	return value
end

local function SafeInteger( value, minimum, maximum )
	value = SafeFiniteNumber( value )
	if not value or value ~= math.floor( value )
	or value < minimum or value > maximum then return nil end
	return value
end

local function FormatNetworkNumber( value )
	value = SafeFiniteNumber( value, 1000000 )
	if not value then return nil end
	-- Avoid long scientific-notation tails and canonicalize signed near-zero.
	-- At this width, 64 complete cut records always fit in sixteen 450-byte chunks.
	if math.abs( value ) < 0.0000001 then value = 0 end
	local encoded = string.format( "%.8g", value )
	if encoded == "-0" then return "0" end
	return encoded
end

local function IsEditableEntity( entity )
	if not IsValid( entity ) or entity:IsWorld() then return false end
	local model = entity:GetModel()
	return isstring( model ) and model ~= ""
end

ABT.IsEditableEntity = IsEditableEntity

-- Another player's model is theirs: only that player or an admin may edit it,
-- the rule the motion tool uses for player targets. Props, NPCs and ragdolls
-- stay with the CanTool hook and the server's prop protection.
function ABT.CanEditPlayer( player, entity )
	if not IsValid( entity ) or not entity:IsPlayer() then return true end
	return IsValid( player ) and ( entity == player or player:IsAdmin() )
end

local function SortedIndexes( values )
	local indexes = {}
	for rawIndex, enabled in pairs( values or {} ) do
		local index = tonumber( rawIndex )
		if enabled and index and index >= 0 and index == math.floor( index ) then
			indexes[ #indexes + 1 ] = index
		end
	end
	table.sort( indexes )
	return indexes
end

function ABT.GetHiddenBodygroupSet( entity )
	local result = {}
	if not IsValid( entity ) then return result end
	for value in string.gmatch( entity:GetNW2String( ABT.HiddenNWKey, "" ), "%d+" ) do
		local index = tonumber( value )
		if index then result[ index ] = true end
	end
	return result
end

function ABT.GetHiddenRegionEncoding( entity )
	if not IsValid( entity ) then return "" end
	local first = entity:GetNW2String( ABT.HiddenRegionsNWKey, "" )
	local count = entity:GetNW2Int( ABT.HiddenRegionsChunkCountNWKey,
		first ~= "" and 1 or 0 )
	if count <= 1 then return first end
	local chunks = { first }
	for index = 2, math.min( count, 16 ) do
		chunks[ #chunks + 1 ] = entity:GetNW2String(
			ABT.HiddenRegionsChunkPrefix .. index, "" )
	end
	return table.concat( chunks, "," )
end

function ABT.GetHiddenRegionSet( entity )
	local result = {}
	local encoded = ABT.GetHiddenRegionEncoding( entity )
	for rawGroup, rawRegion in string.gmatch( encoded, "(%d+):(%d+)" ) do
		local group, region = tonumber( rawGroup ), tonumber( rawRegion )
		if group and region then
			result[ group ] = result[ group ] or {}
			result[ group ][ region ] = true
		end
	end
	return result
end

function ABT.GetVertexKeepEncoding( entity )
	if not IsValid( entity ) then return "" end
	local first = entity:GetNW2String( ABT.VertexKeepNWKey, "" )
	local count = entity:GetNW2Int( ABT.VertexKeepChunkCountNWKey,
		first ~= "" and 1 or 0 )
	if count <= 1 then return first end
	local chunks = { first }
	for index = 2, math.min( count, ABT.VertexKeepMaxChunks ) do
		chunks[ #chunks + 1 ] = entity:GetNW2String(
			ABT.VertexKeepChunkPrefix .. index, "" )
	end
	return table.concat( chunks, ";" )
end

function ABT.GetVertexKeepBounds( entity )
	local result = {}
	local cutCount = 0
	for token in string.gmatch( ABT.GetVertexKeepEncoding( entity ), "[^;]+" ) do
		local values = string.Explode( ":", token, false )
		if values[ 1 ] == "c" then
			local group = SafeInteger( values[ 2 ], 0, 255 )
			local option = SafeInteger( values[ 3 ], 0, 255 )
			local flags = SafeInteger( values[ 4 ], 0, 3 )
			local ox = SafeFiniteNumber( values[ 5 ], 1000000 )
			local oy = SafeFiniteNumber( values[ 6 ], 1000000 )
			local oz = SafeFiniteNumber( values[ 7 ], 1000000 )
			local pitch = SafeFiniteNumber( values[ 8 ], 1000000 )
			local yaw = SafeFiniteNumber( values[ 9 ], 1000000 )
			local roll = SafeFiniteNumber( values[ 10 ], 1000000 )
			if group and option and flags and ox and oy and oz and pitch
			and yaw and roll and cutCount < ABT.MaxVertexCuts then
				local entry = result[ group ]
				if not istable( entry ) or not istable( entry.cuts )
				or entry.option ~= option then
					entry = { option = option, cuts = {} }
					result[ group ] = entry
				end
				if #entry.cuts < ABT.MaxVertexCutsPerGroup then
					entry.cuts[ #entry.cuts + 1 ] = {
						enabled = bit.band( flags, 1 ) ~= 0,
						keep_positive = bit.band( flags, 2 ) ~= 0,
						ox = ox,
						oy = oy,
						oz = oz,
						pitch = pitch,
						yaw = yaw,
						roll = roll,
					}
					cutCount = cutCount + 1
				end
			end
		else
			-- Version 5 encoded one axis-aligned keep box per bodygroup.
			local group = SafeInteger( values[ 1 ], 0, 255 )
			local option = SafeInteger( values[ 2 ], 0, 255 )
			local mask = SafeInteger( values[ 3 ], 1, 63 )
			local xmin = SafeFiniteNumber( values[ 4 ], 1000000 )
			local xmax = SafeFiniteNumber( values[ 5 ], 1000000 )
			local ymin = SafeFiniteNumber( values[ 6 ], 1000000 )
			local ymax = SafeFiniteNumber( values[ 7 ], 1000000 )
			local zmin = SafeFiniteNumber( values[ 8 ], 1000000 )
			local zmax = SafeFiniteNumber( values[ 9 ], 1000000 )
			if group and option and mask and not result[ group ]
			and xmin and xmax and ymin and ymax and zmin and zmax then
				result[ group ] = {
					option = option,
					xmin_on = bit.band( mask, 1 ) ~= 0,
					xmax_on = bit.band( mask, 2 ) ~= 0,
					ymin_on = bit.band( mask, 4 ) ~= 0,
					ymax_on = bit.band( mask, 8 ) ~= 0,
					zmin_on = bit.band( mask, 16 ) ~= 0,
					zmax_on = bit.band( mask, 32 ) ~= 0,
					xmin = xmin,
					xmax = xmax,
					ymin = ymin,
					ymax = ymax,
					zmin = zmin,
					zmax = zmax,
				}
			end
		end
	end
	return result
end

if SERVER then
	AddCSLuaFile( "advanced_bodygroup_tool/cl_i18n.lua" )
	AddCSLuaFile( "advanced_bodygroup_tool/cl_uv_hide.lua" )
	AddCSLuaFile( "advanced_bodygroup_tool/cl_vertex_keep_editor.lua" )
else
	include( "advanced_bodygroup_tool/cl_i18n.lua" )
	include( "advanced_bodygroup_tool/cl_uv_hide.lua" )
	include( "advanced_bodygroup_tool/cl_vertex_keep_editor.lua" )
	return
end

util.AddNetworkString( "advanced_bodygroup_tool_apply" )
util.AddNetworkString( "advanced_bodygroup_tool_set_vertex_cuts" )
util.AddNetworkString( "advanced_bodygroup_tool_vertex_cuts_result" )

ABT.ManagedEntities = ABT.ManagedEntities or setmetatable( {}, { __mode = "k" } )

-- Builds a state from stored modifier data; defined with the duplicator
-- support below.
local SanitizeStoredState

local function GetState( entity, create )
	local state = entity.AdvancedBodygroupUVHideState
	if not state and create then
		-- A stored modifier came from a dupe or a save, so its fields can hold
		-- anything: the state is built only from what passes the same checks
		-- as a paste.
		local stored = entity.EntityMods and entity.EntityMods[ ABT.ModifierName ]
		state = SanitizeStoredState( entity, stored )
		entity.AdvancedBodygroupUVHideState = state
		ABT.ManagedEntities[ entity ] = true
	end
	if state then
		state.hiddenBodygroups = state.hiddenBodygroups or {}
		state.hiddenRegions = state.hiddenRegions or {}
		state.regionOptions = state.regionOptions or {}
		state.vertexKeepBounds = state.vertexKeepBounds or {}
	end
	return state
end

local function PublishState( entity, state )
	if not IsValid( entity ) then return end
	local values = {}
	for _, index in ipairs( SortedIndexes( state and state.hiddenBodygroups ) ) do
		values[ #values + 1 ] = tostring( index )
	end
	entity:SetNW2String( ABT.HiddenNWKey, table.concat( values, "," ) )
	local regions = {}
	for _, group in ipairs( SortedIndexes( state and state.hiddenRegions ) ) do
		for _, region in ipairs( SortedIndexes( state.hiddenRegions[ group ] ) ) do
			regions[ #regions + 1 ] = group .. ":" .. region
		end
	end
	local chunks, current = {}, ""
	for _, token in ipairs( regions ) do
		local separator = current == "" and "" or ","
		if current ~= "" and #current + #separator + #token > 450 then
			chunks[ #chunks + 1 ] = current
			current, separator = "", ""
		end
		current = current .. separator .. token
	end
	if current ~= "" then chunks[ #chunks + 1 ] = current end
	local previousCount = math.Clamp( entity:GetNW2Int(
		ABT.HiddenRegionsChunkCountNWKey, 0 ), 0, 16 )
	entity:SetNW2String( ABT.HiddenRegionsNWKey, chunks[ 1 ] or "" )
	for index = 2, math.max( previousCount, #chunks ) do
		entity:SetNW2String( ABT.HiddenRegionsChunkPrefix .. index,
			chunks[ index ] or "" )
	end
	entity:SetNW2Int( ABT.HiddenRegionsChunkCountNWKey, #chunks )

	local keepTokens = {}
	for _, group in ipairs( SortedIndexes( state and state.vertexKeepBounds ) ) do
		if #keepTokens >= ABT.MaxVertexCuts then break end
		local bounds = state.vertexKeepBounds[ group ]
		if group <= 255 and istable( bounds ) then
			local rawOption = SafeFiniteNumber( bounds.option, 1000000 ) or 0
			local option = math.Clamp( math.floor( rawOption ), 0, 255 )
			if istable( bounds.cuts ) then
				for index = 1, math.min( #bounds.cuts,
					ABT.MaxVertexCutsPerGroup ) do
					if #keepTokens >= ABT.MaxVertexCuts then break end
					local cut = bounds.cuts[ index ]
					local ox = istable( cut )
						and SafeFiniteNumber( cut.ox, 1000000 )
					local oy = istable( cut )
						and SafeFiniteNumber( cut.oy, 1000000 )
					local oz = istable( cut )
						and SafeFiniteNumber( cut.oz, 1000000 )
					local pitch = istable( cut )
						and SafeFiniteNumber( cut.pitch, 1000000 )
					local yaw = istable( cut )
						and SafeFiniteNumber( cut.yaw, 1000000 )
					local roll = istable( cut )
						and SafeFiniteNumber( cut.roll, 1000000 )
					if ox and oy and oz and pitch and yaw and roll then
						local flags = ( cut.enabled ~= false and 1 or 0 )
							+ ( cut.keep_positive ~= false and 2 or 0 )
						keepTokens[ #keepTokens + 1 ] = table.concat( {
							"c", group, option, flags,
							FormatNetworkNumber( ox ),
							FormatNetworkNumber( oy ),
							FormatNetworkNumber( oz ),
							FormatNetworkNumber( pitch ),
							FormatNetworkNumber( yaw ),
							FormatNetworkNumber( roll ),
						}, ":" )
					end
				end
			else
				local mask = ( bounds.xmin_on and 1 or 0 )
					+ ( bounds.xmax_on and 2 or 0 )
					+ ( bounds.ymin_on and 4 or 0 )
					+ ( bounds.ymax_on and 8 or 0 )
					+ ( bounds.zmin_on and 16 or 0 )
					+ ( bounds.zmax_on and 32 or 0 )
				local xmin = SafeFiniteNumber( bounds.xmin, 1000000 )
				local xmax = SafeFiniteNumber( bounds.xmax, 1000000 )
				local ymin = SafeFiniteNumber( bounds.ymin, 1000000 )
				local ymax = SafeFiniteNumber( bounds.ymax, 1000000 )
				local zmin = SafeFiniteNumber( bounds.zmin, 1000000 )
				local zmax = SafeFiniteNumber( bounds.zmax, 1000000 )
				local valid = ( not bounds.xmin_on or xmin )
					and ( not bounds.xmax_on or xmax )
					and ( not bounds.ymin_on or ymin )
					and ( not bounds.ymax_on or ymax )
					and ( not bounds.zmin_on or zmin )
					and ( not bounds.zmax_on or zmax )
				if mask > 0 and valid then
					keepTokens[ #keepTokens + 1 ] = table.concat( {
						group, option, mask,
						FormatNetworkNumber( xmin or 0 ),
						FormatNetworkNumber( xmax or 0 ),
						FormatNetworkNumber( ymin or 0 ),
						FormatNetworkNumber( ymax or 0 ),
						FormatNetworkNumber( zmin or 0 ),
						FormatNetworkNumber( zmax or 0 ),
					}, ":" )
				end
			end
		end
	end
	local keepChunks, keepCurrent = {}, ""
	for _, token in ipairs( keepTokens ) do
		local separator = keepCurrent == "" and "" or ";"
		if keepCurrent ~= "" and #keepCurrent + #separator + #token > 450 then
			keepChunks[ #keepChunks + 1 ] = keepCurrent
			if #keepChunks >= ABT.VertexKeepMaxChunks then
				keepCurrent = ""
				break
			end
			keepCurrent, separator = "", ""
		end
		keepCurrent = keepCurrent .. separator .. token
	end
	if keepCurrent ~= "" and #keepChunks < ABT.VertexKeepMaxChunks then
		keepChunks[ #keepChunks + 1 ] = keepCurrent
	end
	local previousKeepCount = math.Clamp( entity:GetNW2Int(
		ABT.VertexKeepChunkCountNWKey, 0 ), 0, ABT.VertexKeepMaxChunks )
	entity:SetNW2String( ABT.VertexKeepNWKey, keepChunks[ 1 ] or "" )
	for index = 2, math.max( previousKeepCount, #keepChunks ) do
		entity:SetNW2String( ABT.VertexKeepChunkPrefix .. index,
			keepChunks[ index ] or "" )
	end
	entity:SetNW2Int( ABT.VertexKeepChunkCountNWKey, #keepChunks )
	entity:SetNW2Int( ABT.RevisionNWKey,
		entity:GetNW2Int( ABT.RevisionNWKey, 0 ) + 1 )
end

local function SaveModifier( entity, state )
	duplicator.ClearEntityModifier( entity, ABT.ModifierName )
	if not state or ( next( state.hiddenBodygroups or {} ) == nil
	and next( state.hiddenRegions or {} ) == nil
	and next( state.vertexKeepBounds or {} ) == nil ) then return end
	duplicator.StoreEntityModifier( entity, ABT.ModifierName, {
		version = 6,
		model = entity:GetModel(),
		hiddenBodygroups = table.Copy( state.hiddenBodygroups or {} ),
		hiddenRegions = table.Copy( state.hiddenRegions or {} ),
		regionOptions = table.Copy( state.regionOptions or {} ),
		vertexKeepBounds = table.Copy( state.vertexKeepBounds or {} ),
	} )
end

local function BodygroupExists( entity, wantedId )
	for rawKey, group in pairs( entity:GetBodyGroups() or {} ) do
		if istable( group ) then
			local id = tonumber( group.id ) or tonumber( rawKey )
			if id == wantedId then return true end
		end
	end
	return false
end

local BODYGROUP_IDENTITY_DIGITS = "0123456789abcdefghijklmnopqrstuvwxyz"
local function CurrentGeometryIdentity( entity )
	local values, maximumId = {}, -1
	for rawKey, bodygroup in pairs( entity:GetBodyGroups() or {} ) do
		if istable( bodygroup ) then
			local id = tonumber( bodygroup.id ) or tonumber( rawKey )
			if id and id >= 0 and id <= 255 and id == math.floor( id ) then
				maximumId = math.max( maximumId, id )
				local option = math.Clamp( math.floor( tonumber(
					entity:GetBodygroup( id ) ) or 0 ), 0,
					#BODYGROUP_IDENTITY_DIGITS - 1 )
				values[ id + 1 ] = string.sub( BODYGROUP_IDENTITY_DIGITS,
					option + 1, option + 1 )
			end
		end
	end
	for index = 1, maximumId + 1 do values[ index ] = values[ index ] or "0" end
	local selection = table.concat( values )
	if selection == "" then selection = "0" end
	return string.lower( tostring( entity:GetModel() or "" ) ) .. "|"
		.. selection .. "|" .. tostring( entity:GetSkin() or 0 )
end

local function SafeVertexCoordinate( value )
	return SafeFiniteNumber( value, 1000000 )
end

local function SanitizeVertexKeepBounds( entity, group, source )
	if not istable( source ) then return nil end
	local rawOption = source.option
	if rawOption == nil then rawOption = entity:GetBodygroup( group ) or 0 end
	rawOption = SafeFiniteNumber( rawOption, 1000000 )
	if not rawOption then return nil end
	local option = math.Clamp( math.floor( rawOption ), 0, 255 )
	if source.cuts ~= nil then
		if not istable( source.cuts ) then return nil end
		local indexed, count = {}, 0
		for rawIndex, rawCut in pairs( source.cuts ) do
			local index = tonumber( rawIndex )
			if not index or index ~= math.floor( index ) or index < 1
			or index > ABT.MaxVertexCutsPerGroup or indexed[ index ] ~= nil then
				return nil
			end
			indexed[ index ] = rawCut
			count = count + 1
		end
		if count < 1 or count > ABT.MaxVertexCutsPerGroup then return nil end
		local result = { option = option, cuts = {} }
		for index = 1, count do
			local cut = indexed[ index ]
			if not istable( cut ) then return nil end
			local ox = SafeVertexCoordinate( cut.ox )
			local oy = SafeVertexCoordinate( cut.oy )
			local oz = SafeVertexCoordinate( cut.oz )
			local pitch = SafeFiniteNumber( cut.pitch, 1000000 )
			local yaw = SafeFiniteNumber( cut.yaw, 1000000 )
			local roll = SafeFiniteNumber( cut.roll, 1000000 )
			if not ox or not oy or not oz or not pitch or not yaw or not roll then
				return nil
			end
			result.cuts[ index ] = {
				enabled = cut.enabled ~= false,
				keep_positive = cut.keep_positive ~= false,
				ox = ox,
				oy = oy,
				oz = oz,
				pitch = math.NormalizeAngle( pitch ),
				yaw = math.NormalizeAngle( yaw ),
				roll = math.NormalizeAngle( roll ),
			}
		end
		return result
	end
	local fields = { "xmin", "xmax", "ymin", "ymax", "zmin", "zmax" }
	local result = {
		option = option,
	}
	local active = false
	for _, field in ipairs( fields ) do
		local enabled = source[ field .. "_on" ] == true
		local coordinate = SafeVertexCoordinate( source[ field ] )
		if enabled and coordinate == nil then return nil end
		result[ field .. "_on" ] = enabled
		result[ field ] = coordinate or 0
		active = active or enabled
	end
	if not active then return nil end
	for _, axis in ipairs( { "x", "y", "z" } ) do
		local minimum, maximum = axis .. "min", axis .. "max"
		if result[ minimum .. "_on" ] and result[ maximum .. "_on" ]
		and result[ minimum ] > result[ maximum ] then
			result[ minimum ], result[ maximum ] =
				result[ maximum ], result[ minimum ]
		end
	end
	return result
end

local function VertexKeepEntryCost( entry )
	if not istable( entry ) then return 0 end
	if istable( entry.cuts ) then return #entry.cuts end
	return 1
end

local function CountVertexKeepEntries( entries, excludedGroup )
	local count = 0
	for rawGroup, entry in pairs( entries or {} ) do
		if tonumber( rawGroup ) ~= excludedGroup then
			count = count + VertexKeepEntryCost( entry )
		end
	end
	return count
end

local function FindBodygroupOption( entity, group, id, wantBlank )
	id = tonumber( id )
	if not id then return nil end
	local count = math.max( tonumber( group.num ) or 0,
		entity:GetBodygroupCount( id ) or 0 )
	if count <= 0 then return nil end
	local submodels = istable( group.submodels ) and group.submodels or {}
	for value = 0, math.min( count - 1, 255 ) do
		local name = submodels[ value ]
		if isstring( name ) and ( name == "" ) == wantBlank then return value end
	end
	-- Some models omit submodel names. Option zero is the safest visible reset.
	if not wantBlank then return 0 end
end

local function ResetForChangedModel( entity, state )
	if not state or state.model == entity:GetModel() then return end
	state.model = entity:GetModel()
	state.hiddenBodygroups = {}
	state.hiddenRegions = {}
	state.regionOptions = {}
	state.vertexKeepBounds = {}
	SaveModifier( entity, state )
	PublishState( entity, state )
end

function ABT.SetBodygroupVertexKeepBounds( entity, group, bounds )
	if not IsEditableEntity( entity ) then return false end
	group = math.floor( tonumber( group ) or -1 )
	if group < 0 or group > 255 or not BodygroupExists( entity, group ) then
		return false
	end
	local state = GetState( entity, true )
	ResetForChangedModel( entity, state )
	state.vertexKeepBounds = state.vertexKeepBounds or {}
	if bounds == nil then
		state.vertexKeepBounds[ group ] = nil
	else
		local source = table.Copy( bounds )
		source.option = entity:GetBodygroup( group ) or 0
		local sanitized = SanitizeVertexKeepBounds( entity, group, source )
		if not sanitized then return false end
		if state.vertexKeepBounds[ group ] == nil
		and table.Count( state.vertexKeepBounds ) >= 64 then return false end
		if CountVertexKeepEntries( state.vertexKeepBounds, group )
		+ VertexKeepEntryCost( sanitized ) > ABT.MaxVertexCuts then return false end
		state.vertexKeepBounds[ group ] = sanitized
	end
	SaveModifier( entity, state )
	PublishState( entity, state )
	return true
end

local function CountHiddenRegions( hiddenRegions )
	local count = 0
	for _, regions in pairs( hiddenRegions or {} ) do
		for _, enabled in pairs( regions or {} ) do
			if enabled then count = count + 1 end
		end
	end
	return count
end

function ABT.SetBodygroupRegionHidden( entity, group, region, hidden )
	if not IsEditableEntity( entity ) then return false end
	group = math.floor( tonumber( group ) or -1 )
	region = math.floor( tonumber( region ) or -1 )
	if group < 0 or group > 255 or not BodygroupExists( entity, group )
	or region < 1 or region > 4095 then return false end
	local state = GetState( entity, true )
	ResetForChangedModel( entity, state )
	state.hiddenRegions = state.hiddenRegions or {}
	state.regionOptions = state.regionOptions or {}
	local option = entity:GetBodygroup( group ) or 0
	if state.regionOptions[ group ] ~= nil
	and state.regionOptions[ group ] ~= option then
		state.hiddenRegions[ group ] = nil
		state.regionOptions[ group ] = nil
	end
	local regions = state.hiddenRegions[ group ]
	if hidden then
		regions = regions or {}
		if not regions[ region ] and CountHiddenRegions( state.hiddenRegions ) >= 256 then
			return false
		end
		regions[ region ] = true
		state.hiddenRegions[ group ] = regions
		state.regionOptions[ group ] = option
	elseif regions then
		regions[ region ] = nil
		if next( regions ) == nil then
			state.hiddenRegions[ group ] = nil
			state.regionOptions[ group ] = nil
		end
	end
	SaveModifier( entity, state )
	PublishState( entity, state )
	return true
end

function ABT.SetBodygroupForceHidden( entity, index, hidden )
	if not IsEditableEntity( entity ) then return false end
	index = math.floor( tonumber( index ) or -1 )
	if index < 0 or index > 255 or not BodygroupExists( entity, index ) then
		return false
	end
	local state = GetState( entity, true )
	ResetForChangedModel( entity, state )
	state.hiddenBodygroups[ index ] = hidden and true or nil
	SaveModifier( entity, state )
	PublishState( entity, state )
	return true
end

function ABT.RestoreForceHidden( entity )
	if not IsEditableEntity( entity ) then return false end
	local state = GetState( entity, true )
	state.model = entity:GetModel()
	state.hiddenBodygroups = {}
	state.hiddenRegions = {}
	state.regionOptions = {}
	state.vertexKeepBounds = {}
	SaveModifier( entity, state )
	PublishState( entity, state )
	return true
end

function ABT.HideAllHideableBodygroups( entity )
	if not IsEditableEntity( entity ) then return false end
	local state = GetState( entity, false )
	if state then ResetForChangedModel( entity, state ) end
	local bodygroupsChanged, stateChanged = false, false
	for rawKey, group in pairs( entity:GetBodyGroups() or {} ) do
		if istable( group ) then
			local id = tonumber( group.id ) or tonumber( rawKey )
			local blank = id and FindBodygroupOption( entity, group, id, true ) or nil
			if id and id >= 0 and id <= 255 and blank ~= nil then
				if entity:GetBodygroup( id ) ~= blank then
					entity:SetBodygroup( id, blank )
					bodygroupsChanged = true
				end
				if state and state.hiddenRegions[ id ] then
					state.hiddenRegions[ id ] = nil
					state.regionOptions[ id ] = nil
					stateChanged = true
				end
				if state and state.vertexKeepBounds[ id ] then
					state.vertexKeepBounds[ id ] = nil
					stateChanged = true
				end
			end
		end
	end
	if stateChanged then
		SaveModifier( entity, state )
		PublishState( entity, state )
	elseif bodygroupsChanged then
		entity:SetNW2Int( ABT.RevisionNWKey,
			entity:GetNW2Int( ABT.RevisionNWKey, 0 ) + 1 )
	end
	return true
end

function ABT.ShowAllBodygroupsAndReset( entity )
	if not IsEditableEntity( entity ) then return false end
	for rawKey, group in pairs( entity:GetBodyGroups() or {} ) do
		if istable( group ) then
			local id = tonumber( group.id ) or tonumber( rawKey )
			local visible = id and FindBodygroupOption( entity, group, id, false ) or nil
			if id and id >= 0 and id <= 255 and visible ~= nil then
				entity:SetBodygroup( id, visible )
			end
		end
	end
	local state = GetState( entity, true )
	state.model = entity:GetModel()
	state.hiddenBodygroups = {}
	state.hiddenRegions = {}
	state.regionOptions = {}
	state.vertexKeepBounds = {}
	SaveModifier( entity, state )
	PublishState( entity, state )
	return true
end

-- A dupe is client-controlled data: any field may hold any value. A field that
-- is not a table is read as empty, every key and value is checked before use,
-- and one budget bounds the entries read across all fields, so a crafted
-- paste can neither raise a Lua error part-way through the duplicator nor
-- cost more work than a genuine dupe.
local MAX_STORED_ENTRIES = 4096

local function IsIndex( value, minimum, maximum )
	return value ~= nil and value == math.floor( value )
		and value >= minimum and value <= maximum
end

SanitizeStoredState = function( entity, data )
	local state = {
		model = entity:GetModel(),
		hiddenBodygroups = {},
		hiddenRegions = {},
		regionOptions = {},
		vertexKeepBounds = {},
	}
	if not istable( data ) then return state end
	-- A modifier stored for another model describes other bodygroups.
	if isstring( data.model ) and data.model ~= ""
	and data.model ~= entity:GetModel() then return state end

	local budget = MAX_STORED_ENTRIES
	local function Field( name )
		local value = data[ name ]
		return istable( value ) and value or {}
	end

	for rawIndex, enabled in pairs( Field( "hiddenBodygroups" ) ) do
		budget = budget - 1
		if budget < 0 then break end
		local index = tonumber( rawIndex )
		if enabled and IsIndex( index, 0, 255 )
		and BodygroupExists( entity, index ) then
			state.hiddenBodygroups[ index ] = true
		end
	end

	local storedOptions = Field( "regionOptions" )
	local regionCount = 0
	for rawGroup, rawRegions in pairs( Field( "hiddenRegions" ) ) do
		budget = budget - 1
		if budget < 0 or regionCount >= 256 then break end
		local group = tonumber( rawGroup )
		if IsIndex( group, 0, 255 ) and istable( rawRegions )
		and BodygroupExists( entity, group ) then
			local storedOption = storedOptions[ rawGroup ]
			if storedOption == nil then storedOption = storedOptions[ group ] end
			local expectedOption = tonumber( storedOption )
			if expectedOption == nil then expectedOption = entity:GetBodygroup( group ) end
			if expectedOption == entity:GetBodygroup( group ) then
				for rawRegion, enabled in pairs( rawRegions ) do
					budget = budget - 1
					if budget < 0 or regionCount >= 256 then break end
					local region = tonumber( rawRegion )
					local regions = state.hiddenRegions[ group ]
					if enabled and IsIndex( region, 1, 4095 )
					and not ( regions and regions[ region ] ) then
						regions = regions or {}
						regions[ region ] = true
						state.hiddenRegions[ group ] = regions
						state.regionOptions[ group ] = expectedOption
						regionCount = regionCount + 1
					end
				end
			end
		end
	end

	local keptGroups = 0
	for rawGroup, rawBounds in pairs( Field( "vertexKeepBounds" ) ) do
		budget = budget - 1
		if budget < 0 or keptGroups >= 64 then break end
		local group = tonumber( rawGroup )
		if IsIndex( group, 0, 255 ) and istable( rawBounds )
		and BodygroupExists( entity, group ) then
			local sanitized = SanitizeVertexKeepBounds( entity, group, rawBounds )
			if sanitized and sanitized.option == entity:GetBodygroup( group )
			and CountVertexKeepEntries( state.vertexKeepBounds, group )
			+ VertexKeepEntryCost( sanitized ) <= ABT.MaxVertexCuts then
				if state.vertexKeepBounds[ group ] == nil then keptGroups = keptGroups + 1 end
				state.vertexKeepBounds[ group ] = sanitized
			end
		end
	end
	return state
end

duplicator.RegisterEntityModifier( ABT.ModifierName, function( _, entity, data )
	if not IsEditableEntity( entity ) or not istable( data ) then return end
	if isstring( data.model ) and data.model ~= ""
	and data.model ~= entity:GetModel() then return end
	local state = SanitizeStoredState( entity, data )
	entity.AdvancedBodygroupUVHideState = state
	ABT.ManagedEntities[ entity ] = true
	SaveModifier( entity, state )
	PublishState( entity, state )
end )

-- Every action rewrites networked state that clients rebuild their masks
-- from. The burst covers quick clicks through the region cards; the refill
-- caps what a client sending these messages in a loop can make the server
-- and the other clients do.
local ACTION_BURST, ACTION_REFILL = 24, 8

local function TakeActionToken( player )
	local now = CurTime()
	local tokens = math.min( ACTION_BURST, ( player.ABTActionTokens or ACTION_BURST )
		+ ( now - ( player.ABTActionTokenAt or now ) ) * ACTION_REFILL )
	player.ABTActionTokenAt = now
	if tokens < 1 then
		player.ABTActionTokens = tokens
		return false
	end
	player.ABTActionTokens = tokens - 1
	return true
end

local function PlayerCanEditSelection( player, entity )
	if not IsValid( player ) or not IsEditableEntity( entity ) then return false end
	if not ABT.CanEditPlayer( player, entity ) then return false end
	local weapon = player:GetActiveWeapon()
	if not IsValid( weapon ) or weapon:GetClass() ~= "gmod_tool" then return false end
	if weapon:GetMode() ~= "advanced_bodygroup" then return false end
	local tool = player:GetTool( "advanced_bodygroup" )
	if not tool or tool:GetSelectedEntity() ~= entity then return false end
	local trace = player:GetEyeTrace()
	trace.Entity = entity
	trace.HitPos = entity:WorldSpaceCenter()
	trace.PhysicsBone = 0
	return hook.Run( "CanTool", player, trace, "advanced_bodygroup" ) ~= false
end

net.Receive( "advanced_bodygroup_tool_apply", function( _, player )
	if not IsValid( player ) or not TakeActionToken( player ) then return end
	local entity = net.ReadEntity()
	local action = net.ReadUInt( 3 )
	if not PlayerCanEditSelection( player, entity ) then return end
	if action == ABT.Action.SetSkin then
		local skin = net.ReadUInt( 8 )
		local count = math.max( entity:SkinCount() or 0, 1 )
		entity:SetSkin( math.Clamp( skin, 0, count - 1 ) )
		entity:SetNW2Int( ABT.RevisionNWKey,
			entity:GetNW2Int( ABT.RevisionNWKey, 0 ) + 1 )
		return
	end
	if action == ABT.Action.SetBodygroup then
		local id = net.ReadUInt( 8 )
		local value = net.ReadUInt( 8 )
		if not BodygroupExists( entity, id ) then return end
		local count = entity:GetBodygroupCount( id ) or 0
		if count <= 1 then return end
		entity:SetBodygroup( id, math.Clamp( value, 0, count - 1 ) )
		local state = GetState( entity, false )
		local stateChanged = state and (
			( state.hiddenRegions and state.hiddenRegions[ id ] )
			or ( state.vertexKeepBounds and state.vertexKeepBounds[ id ] ) )
		if stateChanged then
			if state.hiddenRegions then state.hiddenRegions[ id ] = nil end
			if state.regionOptions then state.regionOptions[ id ] = nil end
			if state.vertexKeepBounds then state.vertexKeepBounds[ id ] = nil end
			SaveModifier( entity, state )
			PublishState( entity, state )
		else
			entity:SetNW2Int( ABT.RevisionNWKey,
				entity:GetNW2Int( ABT.RevisionNWKey, 0 ) + 1 )
		end
		return
	end
	if action == ABT.Action.SetForceHidden then
		ABT.SetBodygroupForceHidden( entity,
			net.ReadUInt( 8 ), net.ReadBool() )
		return
	end
	if action == ABT.Action.RestoreForceHidden then
		ABT.RestoreForceHidden( entity )
		return
	end
	if action == ABT.Action.HideAllHideable then
		ABT.HideAllHideableBodygroups( entity )
		return
	end
	if action == ABT.Action.ShowAllReset then
		ABT.ShowAllBodygroupsAndReset( entity )
		return
	end
	if action == ABT.Action.SetRegionHidden then
		ABT.SetBodygroupRegionHidden( entity,
			net.ReadUInt( 8 ), net.ReadUInt( 12 ), net.ReadBool() )
		return
	end
	if action == ABT.Action.SetVertexKeepBounds then
		local group = net.ReadUInt( 8 )
		local mask = net.ReadUInt( 6 )
		local bounds = {
			xmin_on = bit.band( mask, 1 ) ~= 0,
			xmax_on = bit.band( mask, 2 ) ~= 0,
			ymin_on = bit.band( mask, 4 ) ~= 0,
			ymax_on = bit.band( mask, 8 ) ~= 0,
			zmin_on = bit.band( mask, 16 ) ~= 0,
			zmax_on = bit.band( mask, 32 ) ~= 0,
			xmin = net.ReadFloat(),
			xmax = net.ReadFloat(),
			ymin = net.ReadFloat(),
			ymax = net.ReadFloat(),
			zmin = net.ReadFloat(),
			zmax = net.ReadFloat(),
		}
		ABT.SetBodygroupVertexKeepBounds( entity, group,
			mask > 0 and bounds or nil )
	end
end )

-- Multi-plane cuts use a separate message so the established three-bit action
-- packet remains readable by version 5 clients and servers.
net.Receive( "advanced_bodygroup_tool_set_vertex_cuts", function( _, player )
	local entity = net.ReadEntity()
	local group = net.ReadUInt( 8 )
	local requestId = net.ReadUInt( 16 )
	local expectedOption = net.ReadUInt( 8 )
	local expectedGeometryIdentity = string.lower( net.ReadString() or "" )
	local count = net.ReadUInt( 5 )
	local function reply( success )
		if not IsValid( player ) then return end
		net.Start( "advanced_bodygroup_tool_vertex_cuts_result" )
			net.WriteUInt( requestId, 16 )
			net.WriteBool( success == true )
		net.Send( player )
	end
	-- Refused requests are answered too, so the editor stops waiting.
	if not IsValid( player ) or not TakeActionToken( player )
	or count > ABT.MaxVertexCutsPerGroup
	or not PlayerCanEditSelection( player, entity )
	or not BodygroupExists( entity, group )
	or CurrentGeometryIdentity( entity ) ~= expectedGeometryIdentity
	or entity:GetBodygroup( group ) ~= expectedOption then
		reply( false )
		return
	end
	if count == 0 then
		reply( ABT.SetBodygroupVertexKeepBounds( entity, group, nil ) )
		return
	end
	local cuts = {}
	for index = 1, count do
		cuts[ index ] = {
			enabled = net.ReadBool(),
			keep_positive = net.ReadBool(),
			ox = net.ReadFloat(),
			oy = net.ReadFloat(),
			oz = net.ReadFloat(),
			pitch = net.ReadFloat(),
			yaw = net.ReadFloat(),
			roll = net.ReadFloat(),
		}
	end
	reply( ABT.SetBodygroupVertexKeepBounds( entity, group, { cuts = cuts } ) )
end )

timer.Create( "AdvancedBodygroupTool.ModelWatch", 1, 0, function()
	for entity in pairs( ABT.ManagedEntities ) do
		if IsValid( entity ) then
			local state = GetState( entity, false )
			ResetForChangedModel( entity, state )
			local changed = false
			for rawGroup in pairs( state and state.hiddenRegions or {} ) do
				local group = tonumber( rawGroup )
				local expected = group and state.regionOptions[ group ]
				if not group or ( expected ~= nil
				and expected ~= entity:GetBodygroup( group ) ) then
					state.hiddenRegions[ rawGroup ] = nil
					if group then state.regionOptions[ group ] = nil end
					changed = true
				end
			end
			for rawGroup, bounds in pairs( state and state.vertexKeepBounds or {} ) do
				local group = tonumber( rawGroup )
				if not group or not istable( bounds )
				or tonumber( bounds.option ) ~= entity:GetBodygroup( group ) then
					state.vertexKeepBounds[ rawGroup ] = nil
					changed = true
				end
			end
			if changed then
				SaveModifier( entity, state )
				PublishState( entity, state )
			end
		else
			ABT.ManagedEntities[ entity ] = nil
		end
	end
end )

-- Clean up material-slot data left by version 1 during Lua auto-refresh.
timer.Simple( 0, function()
	for _, entity in ipairs( ents.GetAll() ) do
		local stored = entity.EntityMods and entity.EntityMods[ ABT.ModifierName ]
		if istable( stored ) and istable( stored.hiddenMaterials )
		and not istable( stored.hiddenBodygroups ) then
			for rawIndex, previousMaterial in pairs( stored.hiddenMaterials ) do
				local index = tonumber( rawIndex )
				if index then entity:SetSubMaterial( index, previousMaterial or "" ) end
			end
			duplicator.ClearEntityModifier( entity, ABT.ModifierName )
			entity:SetNW2String( "ABT_HiddenMaterials", "" )
		end
	end
end )
