-- Optional RTX Remix renderer for Seamless Portals.
-- Reciprocal pairs are assigned to the active runtime's reported portal slots.
-- Pairs beyond that limit continue using the normal render-target path.

SeamlessPortals = SeamlessPortals or {}
if SeamlessPortals.ReleaseAllRemixPortals then
	SeamlessPortals.ReleaseAllRemixPortals()
end

local SIZE_MULTIPLIER = math.sqrt(2)
local enabled = CreateClientConVar("seamless_portals_remix", "1", true, false,
	"Use RTX Remix ray portals when the Remix API is available.", 0, 1)
local debugLogging = CreateClientConVar("seamless_portals_remix_debug", "0", true, false,
	"Print native Seamless Portal submission diagnostics.", 0, 1)
local claimedFrame = setmetatable({}, { __mode = "k" })
local portalResources = setmetatable({}, { __mode = "k" })
local submittedFrame = -1
local warnedUnavailable = false
local activePairs = {}

local function debugPrint(...)
	if !debugLogging:GetBool() then return end
	MsgC(Color(100, 200, 255), "[Seamless Portals RTX] ", color_white, ...)
	MsgN("")
end

local function deactivateResources(resources)
	if !resources then return end
	if resources.instanceHandle and RemixInstance and RemixInstance.DestroyPersistentInstance then
		RemixInstance.DestroyPersistentInstance(resources.instanceHandle)
		resources.instanceHandle = nil
	end
	resources.transformKey = nil
end

local function deactivatePair(pairSlot)
	local pair = activePairs[pairSlot]
	if !pair then return end
	deactivateResources(portalResources[pair.entry])
	deactivateResources(portalResources[pair.exit])
	activePairs[pairSlot] = nil
end

local function deactivateAllPairs()
	local pairSlots = {}
	for pairSlot in pairs(activePairs) do
		table.insert(pairSlots, pairSlot)
	end
	for _, pairSlot in ipairs(pairSlots) do
		deactivatePair(pairSlot)
	end
end

local function destroyResources(resources)
	if !resources then return end
	deactivateResources(resources)
	if resources.meshId and RemixMesh and RemixMesh.DestroyMesh then
		RemixMesh.DestroyMesh(resources.meshId)
	end
	if resources.materialId and RemixMaterial and RemixMaterial.DestroyMaterial then
		RemixMaterial.DestroyMaterial(resources.materialId)
	end
end

function SeamlessPortals.ReleaseRemixPortal(portal)
	for pairSlot, pair in pairs(activePairs) do
		if portal == pair.entry or portal == pair.exit then
			deactivatePair(pairSlot)
			break
		end
	end
	destroyResources(portalResources[portal])
	portalResources[portal] = nil
	claimedFrame[portal] = nil
end

function SeamlessPortals.IsRemixPortalClaimed(portal)
	return claimedFrame[portal] == FrameNumber()
end

local function getCapabilities()
    if !enabled:GetBool() then return nil, "seamless_portals_remix is disabled" end
    if !RemixMaterial then return nil, "RemixMaterial is unavailable" end
    if !RemixMaterial.GetPortalCapabilities then return nil, "GetPortalCapabilities is unavailable" end
    if !RemixMaterial.CreatePortalMaterial then return nil, "CreatePortalMaterial is unavailable" end
    if !RemixMesh or !RemixMesh.CreateMesh then return nil, "RemixMesh.CreateMesh is unavailable" end
    if !RemixInstance then return nil, "RemixInstance is unavailable" end
    if !RemixInstance.CreatePersistentInstance then return nil, "CreatePersistentInstance is unavailable" end
    if !RemixInstance.UpdatePersistentInstance then return nil, "UpdatePersistentInstance is unavailable" end
    if !RemixInstance.DestroyPersistentInstance then return nil, "DestroyPersistentInstance is unavailable" end

    local capabilities = RemixMaterial.GetPortalCapabilities()
    if !capabilities then return nil, "the native capability query returned no data" end
    if !capabilities.available then return nil, "the Remix API is not initialized" end
    if !capabilities.supportsPersistentInstances then return nil, "persistent instances are unsupported" end
    if (capabilities.maxActivePortalSurfaces or 0) < 2 then
        return nil, "the runtime reports fewer than two portal surfaces"
    end
    return capabilities
end

local function printCapabilityStatus()
    local capabilities, reason = getCapabilities()
    if !capabilities then
        MsgC(Color(255, 180, 80), "[Seamless Portals RTX] unavailable: ", color_white,
            reason or "unknown reason", "\n")
        return
    end

    debugPrint("native API ready; surfaces=", capabilities.maxActivePortalSurfaces or 0,
        ", dedicatedVolumes=", capabilities.maxDedicatedPortalVolumes or 0,
        ", runtimeQuery=", tostring(capabilities.supportsRuntimeCapabilityQuery == true))
end

-- Vertex encounter order is significant to stock RayPortalManager:
-- vertex 2 - vertex 0 is its X axis and vertex 1 - vertex 0 is its Y axis.
local portalVertices = {
	{ pos = { -1, -1, 0 }, normal = { 0, 0, 1 }, texcoord = { 0, 0 } },
	{ pos = { -1,  1, 0 }, normal = { 0, 0, 1 }, texcoord = { 0, 1 } },
	{ pos = {  1, -1, 0 }, normal = { 0, 0, 1 }, texcoord = { 1, 0 } },
	{ pos = {  1,  1, 0 }, normal = { 0, 0, 1 }, texcoord = { 1, 1 } }
}
local portalIndices = { 0, 1, 2, 2, 1, 3 }

local function ensureResources(portal, slot)
	local current = portalResources[portal]
	if current and current.slot == slot and current.materialId and current.meshId then
		return current
	end

	destroyResources(current)
	portalResources[portal] = nil

	local uniqueName = string.format("seamless_portal_%d_slot_%d", portal:EntIndex(), slot)
	local materialHash = util.CRC("rtx_remix_material_" .. uniqueName)
	if materialHash == "0" then materialHash = "1" end

	local materialId = RemixMaterial.CreatePortalMaterial(uniqueName .. "_material", {
		hash = materialHash,
		emissiveIntensity = 0
	}, {
		rayPortalIndex = slot,
		rotationSpeed = 0
	})
	if !materialId or materialId == 0 then
		debugPrint("material creation failed for slot ", slot)
		return nil
	end

	local meshId = RemixMesh.CreateMesh(uniqueName .. "_mesh", {
		hash = util.CRC("rtx_remix_mesh_" .. uniqueName),
		surfaces = {
			{
				material = materialId,
				vertices = portalVertices,
				indices = portalIndices
			}
		}
	})
	if !meshId or meshId == 0 then
		RemixMaterial.DestroyMaterial(materialId)
		debugPrint("mesh creation failed for slot ", slot)
		return nil
	end

	current = { slot = slot, materialId = materialId, meshId = meshId }
	portalResources[portal] = current
	return current
end

local function portalTransform(portal)
	local pos = portal:GetPos()
	local size = portal:GetSize()
	-- Seamless Portals maps local coordinates as (x, -y, -z), while Remix
	-- maps them as (-x, y, -z). Swap the in-plane axes so both conventions
	-- describe the same portal transform. Right x Forward keeps the normal Up.
	local x = portal:GetRight() * (size.y * SIZE_MULTIPLIER)
	local y = portal:GetForward() * (size.x * SIZE_MULTIPLIER)
	local z = portal:GetUp() * size.z

	local transform = {
		{ x.x, y.x, z.x, pos.x },
		{ x.y, y.y, z.y, pos.y },
		{ x.z, y.z, z.z, pos.z }
	}
	local transformKey = string.format(
		"%.5f,%.5f,%.5f,%.5f,%.5f,%.5f,%.5f,%.5f,%.5f,%.5f,%.5f,%.5f",
		x.x, y.x, z.x, pos.x,
		x.y, y.y, z.y, pos.y,
		x.z, y.z, z.z, pos.z)
	return transform, transformKey
end

local function ensurePersistentSurface(portal, resources)
	local transform, transformKey = portalTransform(portal)
	if resources.instanceHandle and resources.transformKey == transformKey then
		return true
	end

	local info = {
		meshId = resources.meshId,
		transform = transform,
		doubleSided = true,
		categoryFlags = 0
	}

	if resources.instanceHandle then
		if RemixInstance.UpdatePersistentInstance(resources.instanceHandle, info) then
			resources.transformKey = transformKey
			debugPrint("updated persistent portal ", resources.instanceHandle)
			return true
		end
		RemixInstance.DestroyPersistentInstance(resources.instanceHandle)
		resources.instanceHandle = nil
		resources.transformKey = nil
	end

	local handle = RemixInstance.CreatePersistentInstance(info)
	if !handle or handle == 0 then return false end
	resources.instanceHandle = handle
	resources.transformKey = transformKey
	debugPrint("created persistent portal ", handle)
	return true
end

local function collectReciprocalPairs(eyePos, eyeAng)
	local candidates = {}
	local seen = setmetatable({}, { __mode = "k" })

	for _, portal in ipairs(SeamlessPortals.Portals or {}) do
		if !IsValid(portal) or seen[portal] then continue end
		local destination = portal:GetExitPortal()
		if !IsValid(destination) or destination == portal then continue end
		if destination:GetExitPortal() != portal then continue end
		seen[portal] = true
		seen[destination] = true

		local entry = portal
		local exit = destination
		if entry:EntIndex() > exit:EntIndex() then
			entry, exit = exit, entry
		end
		local visible = SeamlessPortals.ShouldRender(portal, eyePos, eyeAng, SeamlessPortals.GetDrawDistance()) or
			SeamlessPortals.ShouldRender(destination, eyePos, eyeAng, SeamlessPortals.GetDrawDistance())
		local distance = math.min(portal:GetPos():DistToSqr(eyePos), destination:GetPos():DistToSqr(eyePos))
		table.insert(candidates, {
			entry = entry,
			exit = exit,
			visible = visible,
			distance = distance
		})
	end

	table.sort(candidates, function(a, b)
		if a.visible != b.visible then return a.visible end
		if a.distance != b.distance then return a.distance < b.distance end
		return a.entry:EntIndex() < b.entry:EntIndex()
	end)
	return candidates
end

function SeamlessPortals.SubmitRemixPortals(eyePos, eyeAng)
	local frame = FrameNumber()
	if submittedFrame == frame then return false end
	submittedFrame = frame
    local capabilities, unavailableReason = getCapabilities()
    if !capabilities then
        deactivateAllPairs()
        if !warnedUnavailable and RemixMaterial then
            MsgC(Color(255, 180, 80), "[Seamless Portals RTX] Native portal API unavailable (",
                color_white, unavailableReason or "unknown reason", Color(255, 180, 80),
                "); using render-target fallback.\n")
            warnedUnavailable = true
        end
        return false
    end
    warnedUnavailable = false

	local maxPairs = math.floor((capabilities.maxActivePortalSurfaces or 0) / 2)
	local candidates = collectReciprocalPairs(eyePos, eyeAng)
	local selectedCount = math.min(maxPairs, #candidates)
	local selectedByEntry = setmetatable({}, { __mode = "k" })
	for candidateIndex = 1, selectedCount do
		local candidate = candidates[candidateIndex]
		selectedByEntry[candidate.entry] = candidate
	end

	-- Keep selected pairs in their existing slots to avoid recreating immutable
	-- portal materials when camera-distance ordering changes.
	local assigned = setmetatable({}, { __mode = "k" })
	for pairSlot, pair in pairs(activePairs) do
		local selected = selectedByEntry[pair.entry]
		if pairSlot > selectedCount or !selected or selected.exit != pair.exit then
			deactivatePair(pairSlot)
		else
			activePairs[pairSlot] = selected
			assigned[selected.entry] = true
		end
	end

	for candidateIndex = 1, selectedCount do
		local candidate = candidates[candidateIndex]
		if assigned[candidate.entry] then continue end
		for pairSlot = 1, maxPairs do
			if activePairs[pairSlot] then continue end
			activePairs[pairSlot] = candidate
			assigned[candidate.entry] = true
			break
		end
	end

	local anySubmitted = false
	for pairSlot = 1, maxPairs do
		local pair = activePairs[pairSlot]
		if !pair then continue end
		local entrySlot = (pairSlot - 1) * 2
		local exitSlot = entrySlot + 1
		local entryResources = ensureResources(pair.entry, entrySlot)
		local exitResources = ensureResources(pair.exit, exitSlot)
		if !entryResources or !exitResources then
			deactivatePair(pairSlot)
			continue
		end

		local entrySubmitted = ensurePersistentSurface(pair.entry, entryResources)
		local exitSubmitted = entrySubmitted and ensurePersistentSurface(pair.exit, exitResources)
		if !entrySubmitted or !exitSubmitted then
			deactivatePair(pairSlot)
			debugPrint("persistent pair activation failed for slot ", pairSlot)
			continue
		end

		claimedFrame[pair.entry] = frame
		claimedFrame[pair.exit] = frame
		anySubmitted = true
	end
	return anySubmitted
end

function SeamlessPortals.ReleaseAllRemixPortals()
	deactivateAllPairs()
	for portal, resources in pairs(portalResources) do
		destroyResources(resources)
		portalResources[portal] = nil
	end
end

hook.Add("ShutDown", "seamless_portals_remix_cleanup", function()
    SeamlessPortals.ReleaseAllRemixPortals()
end)

cvars.AddChangeCallback("seamless_portals_remix_debug", function(_, _, newValue)
    if tonumber(newValue) != 1 then return end
    printCapabilityStatus()
end, "seamless_portals_remix_debug_status")

timer.Simple(0, function()
    if debugLogging:GetBool() then
        printCapabilityStatus()
    end
end)
