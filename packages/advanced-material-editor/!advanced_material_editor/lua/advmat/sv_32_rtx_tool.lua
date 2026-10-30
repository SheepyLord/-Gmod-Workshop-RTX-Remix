--[[---------------------------------------------------------------------------
	Advanced Material Editor - RTX-only tool actions

	The stool keeps one small dispatch branch, while copy/paste/clear semantics
	live beside the RTX store.  This file is never sent to clients and cannot
	change the vanilla rule path when the resolved mode is vanilla.
-----------------------------------------------------------------------------]]

AdvMat         = AdvMat or {}
AdvMat.RTXTool = AdvMat.RTXTool or {}

local RTXTool = AdvMat.RTXTool

function RTXTool.UsesMode( ply )
	if not IsValid( ply ) then return false end
	local requested = string.lower( ply:GetInfo( "advmat_backend" ) or "auto" )
	if requested == "vanilla" then return false end
	-- HELLO 0 is authoritative for an in-flight backend switch/reset failure.
	-- It closes the small userinfo-replication window where GetInfo can still
	-- report the previous explicit RTX value after the client has withdrawn it.
	if ply.AdvMatRTXModeActive == false then return false end
	if requested == "rtx" then return true end
	local store = AdvMat.RTXStore
	local protocol = istable( store ) and tonumber( store.PROTOCOL ) or 1
	return requested == "auto" and ply.AdvMatRTXModeActive == true
		and ply.AdvMatRTXProtocol == protocol
end

local function ProfileFor( store, material )
	if isfunction( store.Get ) then return store.Get( material ) end
	return istable( store.Profiles ) and store.Profiles[ "rtx:mat:" .. material ] or nil
end

function RTXTool.RightClick( tool, ent, ply )
	local store = AdvMat.RTXStore
	if not store or not istable( store.Profiles ) then return false end
	local mats = ent:GetMaterials() or {}

	if tool:GetStage() == 0 then
		local clip = {}
		for index = 1, math.min( #mats, AdvMat.GetMaterialLimit( ent ) ) do
			local material = AdvMat.NormalizeMaterial( mats[ index ] )
			local profile = ProfileFor( store, material )
			if profile then clip[ index - 1 ] = table.Copy( profile ) end
		end
		if table.IsEmpty( clip ) then
			AdvMat.Notify( ply, "That entity has no RTX material profiles to copy.", NOTIFY_HINT )
			return false
		end
		ply.AdvMatRTXClipboard = clip
		tool:SetStage( 1 )
		AdvMat.Notify( ply, "Copied " .. table.Count( clip ) .. " RTX material profile(s).", NOTIFY_GENERIC )
		return true
	end

	if not AdvMat.IsAllowed( ply ) then
		AdvMat.Notify( ply, "You are not allowed to save RTX material profiles here.", NOTIFY_ERROR )
		return false
	end
	local clip = ply.AdvMatRTXClipboard
	if not istable( clip ) or table.IsEmpty( clip ) then tool:SetStage( 0 ) return false end

	-- A Remix override is globally owned by the destination's captured 64-bit
	-- texture hash, not by the Source entity/slot.  The server cannot discover
	-- that client-render identity here.  Persisting a hashless copy would retire
	-- a working destination override while applying nothing, and reusing the
	-- source hash would overwrite the wrong material.  Refuse the operation and
	-- preserve both sides until a client-side capture/confirmation workflow is
	-- available.
	tool:SetStage( 0 )
	AdvMat.Notify( ply,
		"RTX paste was not applied because destination texture hashes must be captured client-side. Open the destination in the RTX editor and save each material there.",
		NOTIFY_HINT )
	return false
end

function RTXTool.Strip( ent, ply )
	local store = AdvMat.RTXStore
	if not store or not isfunction( store.Clear ) then return false end
	local n = 0
	for _, raw in ipairs( ent:GetMaterials() or {} ) do
		local material = AdvMat.NormalizeMaterial( raw )
		if ProfileFor( store, material ) and store.Clear( material ) then n = n + 1 end
	end
	AdvMat.Notify( ply, n > 0 and ( "Removed " .. n .. " RTX material profile(s)." )
		or "That entity had no RTX material profiles.", n > 0 and NOTIFY_GENERIC or NOTIFY_HINT )
	return n > 0
end
