-- Imported characters' painted shadows and hair alpha in RTX sessions (R15, ADR 0104).
--   * Painted shadows (目影, 发影, 陰影 and unnamed dark overlays; nativeloader/painted_shadows.lua): path
--     tracing casts the real shadow, so they darken twice. They are left out of the draw through the
--     hotloader's visibility (mmdhl.RenderHiddenParts, read by mmdhl.SyncMaterialState); bodygroups,
--     saves, dupes and files stay as they are.
--   * Solid hair (nativeloader/solid_hair.lua): a hair part whose texture is mostly opaque, with a mask
--     inside the strands that the 0.5 alpha test turns into holes, is drawn without the alpha test and
--     its soft copy without blending. Only the materials' flags change, in memory; they are put back when
--     the setting is off, outside RTX sessions and at shutdown. Texture hashes, and so PBR, stay.
-- Only characters on the map are looked at. Per frame: one manifest read at most, 32 sampled texture
-- rows, and a few material checks. Documented in nativeloader_imported_parts.lua.md beside this file.
local shadows = include("nativeloader/painted_shadows.lua")
local hair = include("nativeloader/solid_hair.lua")
local hide = CreateClientConVar("nativeloader_hide_painted_shadows", "1", true, false,
    "Leave imported characters' painted shadows (eye, hair and face shadows) out of the draw in RTX sessions")
local solidHair = CreateClientConVar("nativeloader_solid_hair", "1", true, false,
    "Draw imported characters' mostly opaque hair without the alpha test in RTX sessions")

local ALPHATEST, TRANSLUCENT = 256, 2097152 -- MATERIAL_VAR_ALPHATEST, MATERIAL_VAR_TRANSLUCENT
local MANIFEST_MAX = 8 * 1024 * 1024        -- an asset manifest read for its texture paths
local ROWS_PER_FRAME = 32                   -- texture rows sampled per frame
local HAIR_PER_FRAME = 4                    -- hair parts looked at per frame
local CHECK = 2                             -- seconds between checks of one hair part
local SWEEP = 1                             -- seconds between looks for characters on the map

local records = {}       -- asset id -> {id, info, total, hidden, found, hair, wantsSource, sourceWhy}
local measures = {}      -- texture name -> {shares | why, job, file}
local queue = {}         -- texture names waiting to be measured
local hairList, hairCursor = {}, 1
local remixOn, nextSweep, live = false, 0, {}

local function assetID(id)
    return type(id) == "string" and #id == 64 and id:match("^%x+$") and id or nil
end
local function loaded(id)
    local info = istable(mmdhl) and istable(mmdhl.assets) and mmdhl.assets[id]
    return istable(info) and istable(info.materials) and info or nil
end

-- Painted shadows: classified once per asset, and again with the texture paths when a part needs them.
local function classifyAsset(record, sources)
    local hidden, found, wants = {}, {}, false
    for index, part in ipairs(record.info.materials) do
        if istable(part) then
            local probe = part
            if sources and isstring(sources[index]) then probe = setmetatable({source = sources[index]}, {__index = part}) end
            local kind, rule = shadows.classify(probe, record.total)
            if kind then
                hidden[index] = true
                found[#found + 1] = {index = index, name = tostring(part.name), kind = kind, rule = rule}
            elseif rule == "source" then
                wants = true
            end
        end
    end
    record.hidden, record.found = hidden, found
    return wants
end
local function readSources(id)
    local path = "mmd_hotloader/assets/" .. id .. "/manifest.json"
    local size = file.Size(path, "DATA")
    if not size or size <= 0 or size > MANIFEST_MAX then return nil, "manifest size" end
    local raw = file.Read(path, "DATA")
    if not raw then return nil, "manifest unreadable" end
    local ok, data = pcall(util.JSONToTable, raw)
    if not ok or not istable(data) or not istable(data.materials) then return nil, "manifest not readable as JSON" end
    local sources = {}
    for index, material in ipairs(data.materials) do
        sources[index] = istable(material) and isstring(material.base) and material.base or ""
    end
    return sources
end

-- Solid hair: the public material and the soft copy each keep the flag they had, to put it back.
local function softMaterial(id, index)
    local copies = istable(mmdhl.softMaterials) and mmdhl.softMaterials[id]
    local name = istable(copies) and istable(copies.soft) and copies.soft[index]
    if not isstring(name) or name == "" then return nil end
    local owner, slot = name:lower():gsub("^!", ""):match("^mmdhl_soft_v%d+_(%x+)_(%d+)$")
    if owner ~= id:lower() or tonumber(slot) ~= index then return nil end
    local mat = Material(name)
    return mat and not mat:IsError() and mat or nil
end
local function clearFlag(state, key, mat, flag)
    local flags = mat:GetInt("$flags")
    if not flags then return end
    if not state.saved[key] then
        state.saved[key] = {mat = mat, flag = flag, had = bit.band(flags, flag) ~= 0,
            coverage = flag == ALPHATEST and mat:GetInt("$allowalphatocoverage") or nil}
    end
    -- A material reloaded from disk has its flag again: clear it again.
    if bit.band(flags, flag) == 0 then return end
    mat:SetInt("$flags", bit.band(flags, bit.bnot(flag)))
    if flag == ALPHATEST then mat:SetInt("$allowalphatocoverage", 0) end
    mat:Recompute()
end
local function restoreHair(state)
    for key, saved in pairs(state.saved) do
        local mat = saved.mat
        local flags = mat and not mat:IsError() and mat:GetInt("$flags")
        if flags and saved.had and bit.band(flags, saved.flag) == 0 then
            mat:SetInt("$flags", bit.bor(flags, saved.flag))
            if saved.coverage ~= nil then mat:SetInt("$allowalphatocoverage", saved.coverage) end
            mat:Recompute()
        end
        state.saved[key] = nil
    end
    state.applied = false
end
local function hairStep(record, state, now)
    if now < state.at then return end
    state.at = now + CHECK
    if not (solidHair:GetBool() and remixOn) then
        if state.applied then restoreHair(state) end
        return
    end
    if not state.public then
        if not file.Exists("materials/" .. state.path .. ".vmt", "GAME") then return end
        local mat = Material(state.path)
        if not mat or mat:IsError() then return end
        state.public = mat
    end
    local texture = state.public:GetTexture("$basetexture")
    if not texture or texture:IsError() then return end
    local name = texture:GetName():lower():gsub("\\", "/")
    if not name:match("^mmd/t/%x+$") then state.why = "not a generated texture" return end
    state.texture = name
    local measure = measures[name]
    if not measure then
        measures[name] = {}
        queue[#queue + 1] = name
        state.at = now + 0.25
        return
    end
    if not measure.shares then
        if not measure.why then state.at = now + 0.25 end
        return
    end
    if not hair.solid(measure.shares) then
        if state.applied then restoreHair(state) end
        return
    end
    clearFlag(state, "public", state.public, ALPHATEST)
    -- The soft copy is made at the part's first draw; it is looked for until it exists.
    local soft = softMaterial(record.id, state.index)
    if soft then clearFlag(state, "soft", soft, TRANSLUCENT) end
    state.applied = true
end
local function measureStep()
    local name = queue[1]
    if not name then return end
    local measure = measures[name]
    if not measure.job then
        local f = file.Open("materials/" .. name .. ".vtf", "rb", "GAME")
        if not f then measure.why = "texture unreadable" table.remove(queue, 1) return end
        local info, why = hair.layout(f:Read(80), f:Size())
        if not info then f:Close() measure.why = why table.remove(queue, 1) return end
        measure.file, measure.job, measure.started = f, hair.sampler(info), SysTime()
    end
    local f = measure.file
    local shares, why = measure.job.step(function(offset, length) f:Seek(offset) return f:Read(length) end, ROWS_PER_FRAME)
    if shares == false then return end
    f:Close()
    measure.file, measure.job = nil, nil
    measure.shares, measure.why = shares or nil, shares and nil or why
    measure.ms = (SysTime() - measure.started) * 1000
    table.remove(queue, 1)
end

local function forget(record)
    for _, state in ipairs(record.hair) do restoreHair(state) end
    records[record.id] = nil
    for i = #hairList, 1, -1 do
        if hairList[i].record == record then table.remove(hairList, i) end
    end
end
local function recordFor(id)
    local info = loaded(id)
    local record = records[id]
    if record and record.info == info then return record end
    if record then forget(record) end
    if not info then return nil end
    local total = 0
    for _, part in ipairs(info.materials) do total = total + (istable(part) and tonumber(part.count) or 0) end
    record = {id = id, info = info, total = total, hair = {}}
    record.wantsSource = classifyAsset(record)
    for index, part in ipairs(info.materials) do
        if hair.eligible(part) and isstring(part.path) and part.path ~= "" then
            local state = {record = record, index = index, name = tostring(part.name), path = part.path, saved = {}, at = 0}
            record.hair[#record.hair + 1], hairList[#hairList + 1] = state, state
        end
    end
    records[id] = record
    return record
end

-- The hotloader asks for this list every few frames per character (mmdhl.SyncMaterialState).
local function renderHidden(ent)
    if not remixOn or not hide:GetBool() or not isfunction(mmdhl.GetAsset) then return nil end
    local id = assetID(mmdhl.GetAsset(ent))
    local record = id and recordFor(id)
    return record and next(record.hidden) ~= nil and record.hidden or nil
end

local function spawned()
    local out = {}
    if not isfunction(mmdhl.Entities) or not isfunction(mmdhl.GetAsset) then return out end
    for _, ent in ipairs(mmdhl.Entities()) do
        if IsValid(ent) then
            local id = assetID(mmdhl.GetAsset(ent))
            if id and loaded(id) then out[id] = true end
        end
    end
    return out
end

hook.Add("Think", "nativeloader_imported_parts", function()
    if not istable(mmdhl) then return end
    if mmdhl.RenderHiddenParts ~= renderHidden then mmdhl.RenderHiddenParts = renderHidden end
    local now = RealTime()
    if now >= nextSweep then
        nextSweep = now + SWEEP
        local ok, value = false, false
        if isfunction(mmdhl.UsesRemixPreview) then ok, value = pcall(mmdhl.UsesRemixPreview) end
        remixOn = ok and value == true
        live = spawned()
        for id in pairs(live) do recordFor(id) end
        for id, record in pairs(records) do
            if not loaded(id) or record.info ~= loaded(id) then forget(record) end
        end
        -- One manifest read per sweep, for a character whose painted shadow only a texture path can tell.
        if remixOn and hide:GetBool() then
            for id in pairs(live) do
                local record = records[id]
                if record and record.wantsSource and not record.sourceWhy then
                    local sources, why = readSources(id)
                    record.sourceWhy = why or "read"
                    if sources then classifyAsset(record, sources) end
                    break
                end
            end
        end
    end
    measureStep()
    for _ = 1, math.min(HAIR_PER_FRAME, #hairList) do
        if hairCursor > #hairList then hairCursor = 1 end
        local state = hairList[hairCursor]
        hairCursor = hairCursor + 1
        if live[state.record.id] or state.applied then hairStep(state.record, state, now) end
    end
end)

hook.Add("ShutDown", "nativeloader_imported_parts", function()
    for _, state in ipairs(hairList) do restoreHair(state) end
    for _, measure in pairs(measures) do
        if measure.file then measure.file:Close() measure.file = nil end
    end
end)

local function percent(value) return string.format("%.1f%%", (value or 0) * 100) end
concommand.Add("nativeloader_imported_parts_status", function()
    print(string.format("[nativeloader] Imported parts: rtx=%s hide_painted_shadows=%s solid_hair=%s characters=%d textures_queued=%d",
        tostring(remixOn), tostring(hide:GetBool()), tostring(solidHair:GetBool()), table.Count(live), #queue))
    for id in pairs(live) do
        local record = recordFor(id)
        if record then
            local info = record.info
            print(string.format("[nativeloader] %s (%s): %d part(s), %d painted shadow(s)%s", tostring(info.name or "?"),
                id:sub(1, 12), #info.materials, #record.found,
                record.sourceWhy and record.sourceWhy ~= "read" and " (texture paths: " .. record.sourceWhy .. ")" or ""))
            for _, found in ipairs(record.found) do
                print(string.format("    shadow #%d %s: %s, by %s", found.index - 1, found.name, found.kind, found.rule))
            end
            for _, state in ipairs(record.hair) do
                local measure = state.texture and measures[state.texture]
                local shares = measure and measure.shares
                local detail = shares and string.format("clear %s, cut %s, partial %s (%dx%d, %.1f ms) -> %s",
                    percent(shares.clear), percent(shares.low), percent(shares.partial), shares.width, shares.height,
                    measure.ms or 0, hair.solid(shares) and "solid" or "alpha test kept")
                    or measure and measure.why or state.why or "not measured yet"
                print(string.format("    hair #%d %s: %s%s", state.index - 1, state.name, detail, state.applied and " (applied)" or ""))
            end
        end
    end
end)
