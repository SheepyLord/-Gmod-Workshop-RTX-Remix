-- Eye-only texture identities, transient Remix aliases and scene-adaptive albedo emission (ADR 0088).
-- No hotloader hook: its renderer uses these exact public IMaterials. Never change an entity override.
local matcher = include("nativeloader/eye_white_names.lua")
local vtf = include("nativeloader/eye_white_vtf.lua")
local enabled = CreateClientConVar("nativeloader_eye_whites", "1", true, false,
    "Steady eye whites for imported characters without a PBR replacement")
local brightness = CreateClientConVar("nativeloader_eye_white_brightness", "100", true, false,
    "Eye-white brightness in percent (automatic and scene-adaptive PBR eye materials)", 0, 200)
local PREFIX = "rtx.gmod."
local states, atlases, sent, retries = {}, {}, {}, {}
local assets, key, parts, partIndex, epoch, nextSweep = nil, nil, nil, 1, 0, 0
local cursor, list, nextWrite, nextPrepare = 1, {}, 0, 0
local preparedBytes, prepareMaxMs, warmQueue = 0, 0, {}
local supported = false
local function sameTexture(a, b)
    -- GMod may return distinct Lua userdata wrappers for the same native ITexture.
    return a and b and a:GetName():lower():gsub("\\", "/") == b:GetName():lower():gsub("\\", "/")
end
local function write(option, value, now)
    if sent[option] == value then return true end
    local retry = retries[option] or {at = 0, delay = 0.25}
    retries[option] = retry
    if now < retry.at then return false end
    if RemixConfig.SetConfigVariable(PREFIX .. option, value) then
        sent[option], retries[option] = value, nil
        return true
    end
    retry.at, retry.delay = now + retry.delay, math.min(retry.delay * 2, 8)
    return false
end
local function normalize(name)
    if type(name) ~= "string" then return end
    name = name:lower():gsub("\\", "/"):gsub("^!", ""):gsub("%.vmt$", "")
    local id = name:match("^mmd/(%x+)/[^/]+$")
    return id and #id == 16 and name or nil
end
local function restore(state)
    if state.mat and state.proxy and sameTexture(state.mat:GetTexture("$basetexture"), state.proxy) then
        state.mat:SetTexture("$basetexture", state.original)
    end
    if state.softMat and state.proxy and sameTexture(state.softMat:GetTexture("$basetexture"), state.proxy) then
        state.softMat:SetTexture("$basetexture", state.original)
    end
    state.applied = false
end
local function softName(asset, index)
    local copies = istable(mmdhl.softMaterials) and mmdhl.softMaterials[asset]
    local name = istable(copies) and istable(copies.soft) and copies.soft[index]
    if type(name) ~= "string" or type(asset) ~= "string" then return end
    name = name:lower():gsub("^!", "")
    local owner, slot = name:match("^mmdhl_soft_v%d+_(%x+)_(%d+)$")
    if owner and #owner == 64 and owner == asset:lower() and tonumber(slot) == index then return name end
end
local function discover(now)
    if not assets then
        if now < nextSweep then return end
        assets = istable(mmdhl) and istable(mmdhl.assets) and mmdhl.assets or {}
        key, parts, partIndex, epoch = nil, nil, 1, epoch + 1
    end
    for _ = 1, 128 do
        if parts and parts[partIndex] ~= nil then
            local part = parts[partIndex]
            partIndex = partIndex + 1
            if istable(part) and matcher.matches(part.name, part.en or part.englishName or part.nameEnglish) then
                local name = normalize(part.path)
                if name then
                    local state = states[name]
                    if not state then
                        state = {name = name, at = 0}
                        states[name], list[#list + 1] = state, state
                    end
                    state.epoch = epoch
                    local copy = softName(key, partIndex - 1)
                    if state.softName ~= copy then
                        if state.softMat and state.proxy and sameTexture(state.softMat:GetTexture("$basetexture"), state.proxy) then
                            state.softMat:SetTexture("$basetexture", state.original)
                        end
                        state.softName, state.softMat = copy, nil
                    end
                end
            end
        else
            local info
            if key ~= nil and assets[key] == nil then key = nil end
            key, info = next(assets, key)
            if key == nil then
                for i = #list, 1, -1 do
                    if list[i].epoch ~= epoch then
                        restore(list[i])
                        states[list[i].name], list[i] = nil, list[#list]
                        list[#list] = nil
                    end
                end
                assets, parts, nextSweep = nil, nil, now + 1
                return
            end
            parts, partIndex = istable(info) and istable(info.materials) and info.materials or {}, 1
        end
    end
end
local function hashes(name, procedural)
    if isfunction(RemixMaterial.TrackMaterial) then RemixMaterial.TrackMaterial(procedural and "!" .. name or name) end
    local out = {}
    for _, hash in ipairs(RemixMaterial.GetAllTextureHashes(name) or {}) do
        local digits = type(hash) == "string" and hash:match("^0[xX](%x+)$")
        if digits and #digits <= 16 then
            digits = digits:lower():gsub("^0+", "")
            if digits ~= "" then out["0x" .. string.rep("0", 16 - #digits) .. digits] = true end
        end
    end
    local values = {}
    for hash in pairs(out) do values[#values + 1] = hash end
    return #values == 1 and values[1] or nil -- never guess between variants
end
local function prepare(state, now)
    if not file.Exists("materials/" .. state.name .. ".vmt", "GAME") then return end
    local mat = Material(state.name)
    if not mat or mat:IsError() then return end
    local texture = mat:GetTexture("$basetexture")
    if not texture or texture:IsError() then return end
    local textureName = texture:GetName():lower():gsub("\\", "/")
    if not textureName:match("^mmd/t/%x+$") then return end
    local atlas = atlases[textureName]
    if not atlas then
        if now < nextPrepare or preparedBytes >= 256 * 1024 * 1024 then return end
        nextPrepare = now + 1
        local started = SysTime()
        local source = "materials/" .. textureName .. ".vtf"
        local size = file.Size(source, "GAME")
        if size < 0 or size > vtf.maxBytes or preparedBytes + size > 256 * 1024 * 1024 then return end
        local bytes = file.Read(source, "GAME")
        local proxyBytes, reason = vtf.proxy(bytes)
        if not proxyBytes then state.reason = reason return end
        local digest = util.SHA256(proxyBytes)
        local path = "nativeloader/eye_whites/" .. digest .. ".vtf"
        file.CreateDir("nativeloader/eye_whites")
        if not file.Exists(path, "DATA") then file.Write(path, proxyBytes) end
        -- A user-edited or incomplete cache entry is never overwritten or bound.
        if file.Read(path, "DATA") ~= proxyBytes then state.reason = "cache differs" return end
        local name = "nativeloader_eye_" .. digest
        local original = CreateMaterial(name .. "_source", "UnlitGeneric", {["$basetexture"] = textureName})
        original:SetTexture("$basetexture", texture)
        local proxy = CreateMaterial(name .. "_proxy", "UnlitGeneric", {["$basetexture"] = "../data/" .. path:sub(1, -5)})
        local copy = proxy and proxy:GetTexture("$basetexture")
        if not copy or copy:IsError() or sameTexture(copy, texture) then state.reason = "proxy texture unavailable" return end
        atlas = {original = texture, proxy = copy, sourceMat = original, proxyMat = proxy,
            sourceName = name .. "_source", proxyName = name .. "_proxy", at = 0, warmStage = 1}
        atlases[textureName], warmQueue[#warmQueue + 1] = atlas, atlas
        preparedBytes = preparedBytes + #proxyBytes
        prepareMaxMs = math.max(prepareMaxMs, (SysTime() - started) * 1000)
    end
    state.mat, state.original, state.proxy, state.atlas = mat, texture, atlas.proxy, atlas
end
-- Hash tracking requires a real D3D texture bind. Warm immutable helpers in a tiny offscreen 2D
-- target on separate frames, allowing Source's queued material/texture ownership to settle.
hook.Add("PostRender", "nativeloader_eye_white_warm", function()
    local atlas = warmQueue[1]
    if not atlas then return end
    table.remove(warmQueue, 1)
    local target = GetRenderTarget("nativeloader_eye_hash_warm", 4, 4)
    render.PushRenderTarget(target)
    cam.Start2D()
    surface.SetDrawColor(255, 255, 255, 255)
    surface.SetMaterial(atlas.warmStage == 1 and atlas.sourceMat or atlas.proxyMat)
    surface.DrawTexturedRect(0, 0, 4, 4)
    cam.End2D()
    render.PopRenderTarget()
    if atlas.warmStage == 1 then
        atlas.warmStage = 2
        warmQueue[#warmQueue + 1] = atlas
    else
        atlas.warmStage = 1
    end
end)
local function sync()
    if not istable(RemixConfig) or not isfunction(RemixConfig.SetConfigVariable) or
        not istable(RemixMaterial) or not isfunction(RemixMaterial.GetAllTextureHashes) then return end
    local now = RealTime()
    supported = write("automaticEyeWhites", enabled:GetBool() and "True" or "False", now)
    if not supported then return end -- older runtimes never get a changed material/texture
    local value = tonumber(brightness:GetString()) or 100
    if value ~= value or value == math.huge or value == -math.huge then value = 100 end
    write("eyeWhiteBrightness", string.format("%.6g", math.max(0, math.min(value, 200)) / 100), now)
    discover(now)
    for _ = 1, math.min(8, #list) do
        if cursor > #list then cursor = 1 end
        local state = list[cursor]
        cursor = cursor + 1
        if not enabled:GetBool() then
            restore(state)
        elseif now >= state.at then
            state.at = now + 0.5
            if not state.atlas then prepare(state, now) end
            local atlas = state.atlas
            if atlas and state.softName then
                local copy = Material("!" .. state.softName)
                local texture = copy and not copy:IsError() and copy:GetTexture("$basetexture")
                if texture and (sameTexture(texture, state.original) or sameTexture(texture, state.proxy)) then
                    state.softMat = copy
                end
            end
            if atlas and now >= atlas.at then
                atlas.at = now + 2
                atlas.sourceHash = hashes(atlas.sourceName, true)
                atlas.proxyHash = hashes(atlas.proxyName, true)
                if not atlas.sourceHash or not atlas.proxyHash then warmQueue[#warmQueue + 1] = atlas end
            end
        end
    end
    if now < nextWrite then return end
    nextWrite = now + 0.1
    local pairsByHash, canonical, entries = {}, {}, {}
    for _, state in ipairs(list) do
        local atlas = state.atlas
        if atlas and atlas.sourceHash and atlas.proxyHash and atlas.sourceHash ~= atlas.proxyHash then
            pairsByHash[atlas.proxyHash], canonical[atlas.sourceHash] = atlas.sourceHash, true
        end
    end
    for proxy, source in pairs(pairsByHash) do
        if not canonical[proxy] then entries[#entries + 1] = proxy .. "=" .. source end
    end
    table.sort(entries)
    local registry = table.concat(entries, ",")
    if write("eyeWhiteAliases", registry, now) then
        for _, state in ipairs(list) do
            local atlas = state.atlas
            if enabled:GetBool() and atlas and atlas.proxyHash and not canonical[atlas.proxyHash] and
                pairsByHash[atlas.proxyHash] and sameTexture(state.mat:GetTexture("$basetexture"), state.original) then
                state.mat:SetTexture("$basetexture", state.proxy)
                state.applied = true
            end
            if enabled:GetBool() and atlas and atlas.proxyHash and not canonical[atlas.proxyHash] and
                pairsByHash[atlas.proxyHash] and state.softMat and sameTexture(state.softMat:GetTexture("$basetexture"), state.original) then
                state.softMat:SetTexture("$basetexture", state.proxy)
            end
        end
    end
end
hook.Add("Think", "nativeloader_eye_whites", sync)
hook.Add("ShutDown", "nativeloader_eye_whites", function() for _, state in ipairs(list) do restore(state) end end)
concommand.Add("nativeloader_eye_whites_status", function()
    local applied = 0
    for _, state in ipairs(list) do if state.applied then applied = applied + 1 end end
    print(string.format("[nativeloader] Eye whites: supported=%s enabled=%s brightness=%s materials=%d applied=%d bytes=%d prepare_max_ms=%.3f aliases=%s",
        tostring(supported), tostring(enabled:GetBool()), brightness:GetString(), #list, applied, preparedBytes, prepareMaxMs,
        sent.eyeWhiteAliases or "pending"))
    for _, state in ipairs(list) do
        local atlas = state.atlas
        local bound = state.mat and state.mat:GetTexture("$basetexture")
        print(string.format("[nativeloader] Eye surface %s original=%s proxy=%s applied=%s bound=%s pending=%s", state.name,
            tostring(atlas and atlas.sourceHash), tostring(atlas and atlas.proxyHash), tostring(state.applied),
            bound and bound:GetName() or "none", state.reason or "none"))
    end
end)
