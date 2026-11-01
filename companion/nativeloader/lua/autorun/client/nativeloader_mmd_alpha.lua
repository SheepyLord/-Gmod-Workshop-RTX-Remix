-- Model Hotloader's public mmd/<asset>/<part> materials and its soft copies share base textures.
-- Send their Remix hashes to a NoSave category joined with the user's saved rtx.mmdAlphaTextures.
-- No material, asset, persistent Remix option or file is changed. See ADR 0081.
local OPTION = "rtx.gmod.mmdAlphaTexturesForSession"
local DISCOVER, LOOKUPS = 128, 16 -- maximum asset slots and material/hash lookups per frame
local SWEEP, POLL = 1, 0.1
local RETRY, RETRY_MAX, REFRESH = 0.25, 4, 8
local names, list, cursor, epoch = {}, {}, 1, 0
local assets, assetKey, parts, partIndex, nextSweep = nil, nil, nil, 1, 0
local revision, nextPoll, dirty, published = nil, 0, true, ""
local sent, writeAt, writeDelay, nextPublish = nil, 0, 1, 0

local function normalize(name)
    if not isstring(name) then return end
    name = name:lower():gsub("\\", "/"):gsub("^!", ""):gsub("%.vmt$", "")
    local short = name:match("^mmd/(%x+)/[^/]+$")
    if short and #short == 16 then return name end
end
-- A part whose every texel is partly transparent (Columbina's lattice mask) is drawn only through the
-- hotloader's soft copy (mmdhl.softMaterials[asset].soft, created on first draw), never through its
-- public material, so only the soft copy's name gives the runtime's hash (PoC 14-mask-diag, 16-mask-diag2).
local function normalizeSoft(name)
    if not isstring(name) then return end
    name = name:lower():gsub("^!", "")
    if name:match("^mmdhl_soft_v%d+_%x+_%d+$") then return name end
end
local function retain(name, soft)
    if not name then return end
    local state = names[name]
    if not state then
        state = {name = name, delay = RETRY, retry = 0, soft = soft}
        names[name], list[#list + 1] = state, state
    end
    state.epoch = epoch
end
-- The public part names of one asset, then its soft copies' names (false keeps a slot for a bad name).
local function partsOf(key, info)
    local out = {}
    if istable(info) and istable(info.materials) then
        for _, part in ipairs(info.materials) do out[#out + 1] = istable(part) and normalize(part.path) or false end
    end
    local copies = istable(mmdhl.softMaterials) and mmdhl.softMaterials[key]
    if istable(copies) and istable(copies.soft) then
        for _, copy in ipairs(copies.soft) do out[#out + 1] = {normalizeSoft(copy)} end
    end
    return out
end
local function discover(now)
    if not assets then
        if now < nextSweep then return end
        assets = istable(mmdhl) and istable(mmdhl.assets) and mmdhl.assets or {}
        epoch, assetKey, parts, partIndex = epoch + 1, nil, nil, 1
    end
    for _ = 1, DISCOVER do
        if parts and parts[partIndex] ~= nil then
            local part = parts[partIndex]
            partIndex = partIndex + 1
            if istable(part) then retain(part[1], true) else retain(part) end
        else
            local info
            -- Asset removal/reload during the sweep can remove the key used by next(). Restart safely.
            if assetKey ~= nil and assets[assetKey] == nil then assetKey = nil end
            assetKey, info = next(assets, assetKey)
            if assetKey == nil then
                for i = #list, 1, -1 do
                    local state = list[i]
                    if state.epoch ~= epoch then
                        names[state.name], list[i], dirty = nil, list[#list], true
                        list[#list] = nil
                    end
                end
                assets, parts, nextSweep = nil, nil, now + SWEEP
                return
            end
            parts, partIndex = partsOf(assetKey, info), 1
        end
    end
end

local function hashesOf(state)
    -- Never tag Source's shared error/white/fallback textures or a user override from another namespace.
    -- A not-yet-mounted VMT or VTF remains retryable; TrackMaterial is only called once it is real.
    -- A soft copy is made with CreateMaterial: no VMT on disk, found by its "!" name.
    if not state.soft and not file.Exists("materials/" .. state.name .. ".vmt", "GAME") then return end
    local mat = Material(state.soft and "!" .. state.name or state.name)
    if not mat or mat:IsError() then return end
    local texture = mat:GetTexture("$basetexture")
    if not texture or texture:IsError() then return end
    local textureName = texture:GetName():lower():gsub("\\", "/")
    if textureName:sub(1, 4) ~= "mmd/" then return end
    if not state.tracked and isfunction(RemixMaterial.TrackMaterial) then
        state.tracked = RemixMaterial.TrackMaterial(state.name) ~= false
    end
    local hashes = {}
    for _, hash in ipairs(RemixMaterial.GetAllTextureHashes(state.name) or {}) do
        local digits = isstring(hash) and hash:match("^0[xX](%x+)$")
        if digits and #digits <= 16 then
            digits = digits:lower():gsub("^0+", "")
            if digits ~= "" then hashes["0x" .. string.rep("0", 16 - #digits) .. digits] = true end
        end
    end
    local values = {}
    for hash in pairs(hashes) do values[#values + 1] = hash end
    if #values == 0 then return end
    table.sort(values)
    return table.concat(values, ", ")
end
local function lookUp(now)
    if now >= nextPoll then
        nextPoll = now + POLL
        revision = isfunction(RemixMaterial.GetMaterialHashRevision) and RemixMaterial.GetMaterialHashRevision() or nil
    end
    for _ = 1, math.min(LOOKUPS, #list) do
        if cursor > #list then cursor = 1 end
        local state = list[cursor]
        cursor = cursor + 1
        if now >= state.retry or (revision ~= nil and state.revision ~= revision) then
            local hashes = hashesOf(state)
            if hashes ~= state.hashes then state.hashes, dirty = hashes, true end
            state.revision = revision
            if hashes then
                state.retry, state.delay = now + REFRESH, RETRY
            else
                state.retry, state.delay = now + state.delay, math.min(state.delay * 2, RETRY_MAX)
            end
        end
    end
end
local function textureList()
    if not dirty then return published end
    dirty = false
    local hashes, values = {}, {}
    for _, state in ipairs(list) do
        for hash in (state.hashes or ""):gmatch("0x%x+") do hashes[hash] = true end
    end
    for hash in pairs(hashes) do values[#values + 1] = hash end
    table.sort(values)
    published = table.concat(values, ", ")
    return published
end
local function sync()
    if not istable(RemixConfig) or not isfunction(RemixConfig.SetConfigVariable) or
        not istable(RemixMaterial) or not isfunction(RemixMaterial.GetAllTextureHashes) then return end
    local now = RealTime()
    discover(now)
    lookUp(now)
    if now < nextPublish then return end
    nextPublish = now + 0.25
    local value = textureList()
    if sent == value or now < writeAt then return end
    if RemixConfig.SetConfigVariable(OPTION, value) then
        sent, writeAt, writeDelay = value, 0, 1
    else
        writeAt, writeDelay = now + writeDelay, math.min(writeDelay * 2, 60)
    end
end
hook.Add("Think", "nativeloader_mmd_alpha", sync)
concommand.Add("nativeloader_mmd_alpha_status", function()
    print(string.format("[nativeloader] MMD alpha: %d materials; %s=%s", #list, OPTION, sent or "pending"))
end)
