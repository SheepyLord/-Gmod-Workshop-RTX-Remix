-- Player-model categories belong only to private first-person proxy textures.
if not RemixMaterial or not RemixCategoryManager then return end

CreateClientConVar("rtx_auto_categorize_pseudoplayer", "1", true, false)
CreateClientConVar("rtx_auto_categorize_pseudoweapon", "1", true, false)
local registered = {}
-- Shared materials of new models wait in pendingShared (name -> when to look next, and the delay
-- after that) until their hashes are all cleared; then they are done and never looked up again. One
-- not drawn yet has no hashes: it is looked up less and less often (1 s, doubling to 5 s).
local pendingShared, doneShared, clearedHashes, scannedModels = {}, {}, {}, {}
local playerBit = RemixCategoryManager.CATEGORY.THIRD_PERSON_PLAYER_MODEL
local playerBits = bit.bor(playerBit, RemixCategoryManager.CATEGORY.THIRD_PERSON_PLAYER_BODY)

local function queueSharedModel(ent)
    if not IsValid(ent) then return end
    local model = ent:GetModel()
    if not model or scannedModels[model] then return end
    scannedModels[model] = true
    for _, name in ipairs(ent:GetMaterials()) do
        if not name:lower():find('pseudoplayer', 1, true) and not name:lower():find('pseudoweapon', 1, true)
            and not doneShared[name] and not pendingShared[name] then
            pendingShared[name] = {next = 0, delay = 1}
        end
    end
end

-- Takes the player bits off one shared hash; true when they are off.
local function releaseHash(hash)
    if clearedHashes[hash] then return true end
    local previous = RemixMaterial.GetHashCategory(hash) or 0
    -- The native removal API uses its local bookkeeping, which does not contain
    -- categories loaded from rtx.conf. Register just this bit before removing it.
    if RemixMaterial.SetHashCategory(hash, playerBit) then
        local reconciled = RemixMaterial.GetHashCategory(hash) or 0
        if RemixMaterial.RemoveHashCategory(hash) then
            local remaining = bit.band(bit.bor(previous, reconciled), bit.bnot(playerBits))
            if remaining ~= 0 then RemixMaterial.SetHashCategory(hash, remaining) end
            clearedHashes[hash] = true
            return true
        end
    end
    return false
end

local function releaseSharedTextures()
    if not GetConVar('rtx_auto_categorize_pseudoplayer'):GetBool() then return end
    local localPlayer = LocalPlayer()
    queueSharedModel(localPlayer)
    if IsValid(localPlayer) then queueSharedModel(localPlayer:GetHands()) end
    for _, ent in ipairs(player.GetAll()) do queueSharedModel(ent) end
    for _, ent in ipairs(ents.FindByClass('prop_ragdoll')) do queueSharedModel(ent) end
    local now = RealTime()
    for name, state in pairs(pendingShared) do
        if now >= state.next then
            local hashes = RemixMaterial.GetAllTextureHashes(name) or {}
            local done = #hashes > 0
            for _, hash in ipairs(hashes) do
                if not releaseHash(hash) then done = false end
            end
            if done then
                pendingShared[name], doneShared[name] = nil, true
            else
                state.next, state.delay = now + state.delay, math.min(state.delay * 2, 5)
            end
        end
    end
end

function RemixCategoryManager.RegisterPlayerProxyMaterial(name)
    if not isstring(name) then return false end
    local lower = name:lower():gsub("^!", "")
    local body = lower:match("^pseudoplayermaterial") and not lower:find("temp", 1, true)
    local weapon = lower:match("^pseudoweaponmaterial") and not lower:find("temp", 1, true)
    if not body and not weapon then return false end
    local setting = body and "rtx_auto_categorize_pseudoplayer" or "rtx_auto_categorize_pseudoweapon"
    if not GetConVar(setting):GetBool() then return false end
    if registered[name] then return true end
    -- Procedural materials enter the native tracker on their first real draw. A filesystem
    -- lookup before then reports a missing VMT, even though the Lua material is valid.
    local hashes = RemixMaterial.GetAllTextureHashes and RemixMaterial.GetAllTextureHashes(name)
    if not hashes or #hashes == 0 then return false end
    local flags = RemixCategoryManager.CATEGORY.THIRD_PERSON_PLAYER_MODEL
    if body then flags = bit.bor(flags, RemixCategoryManager.CATEGORY.THIRD_PERSON_PLAYER_BODY) end
    RemixCategoryManager.SetMaterialCategory(name, flags)
    registered[name] = true
    return true
end

local function scan(prefix)
    local found = RemixMaterial.FindTexturesByName(prefix) or {}
    for _, entry in ipairs(found) do
        RemixCategoryManager.RegisterPlayerProxyMaterial(entry.name)
    end
end

concommand.Add("rtx_categorize_pseudoplayer", function() scan("pseudoplayermaterial") end)
concommand.Add("rtx_categorize_pseudoweapon", function() scan("pseudoweaponmaterial") end)
-- The body registers its materials at draw time. Legacy weapon proxies need a cache scan.
timer.Create("RemixPseudoplayerCategory_ProxyScan", 1, 0, function()
    releaseSharedTextures()
    if GetConVar("rtx_pseudoplayer"):GetBool() then scan("pseudoplayermaterial") end
    if GetConVar("rtx_pseudoweapon"):GetBool() then scan("pseudoweaponmaterial") end
end)
