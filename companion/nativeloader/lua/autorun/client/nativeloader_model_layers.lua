-- Outline suppression for RTX sessions (ADR 0047). It owns two transient (NoSave) Remix options and
-- leaves every original material untouched:
--   * rtx.gmod.ignoredOutlineTextures: the texture hashes of the outline materials of loaded models,
--     found by name (nativeloader_ignore_outlines, default 1: the Model outlines checkbox);
--   * rtx.gmod.ignoreOutlineMeshes: the runtime's rule that hides opaque model draws culling their
--     front faces (nativeloader_ignore_outline_shells, default 0, console only). GMod culls that way
--     for real mirrored geometry too, so that rule is opt-in.
-- The work per frame is bounded: a few entities are looked at per frame, in turn, and texture hashes
-- are looked up for a few names per frame: a new name, a name still without hashes (less and less
-- often), or every name after Remix's material-hash revision changed. Documented in
-- nativeloader_model_layers.lua.md beside this file.
local names_enabled = CreateClientConVar("nativeloader_ignore_outlines", "1", true, false,
    "Hide the outline materials of loaded models (rtx.gmod.ignoredOutlineTextures)")
local shells_enabled = CreateClientConVar("nativeloader_ignore_outline_shells", "0", true, false,
    "Also hide every opaque model draw that culls its front faces (rtx.gmod.ignoreOutlineMeshes)")

local SLOTS_PER_FRAME = 256          -- entity material slots looked at per frame
local NAMES_PER_FRAME = 16           -- material names whose texture hashes are looked up per frame
local SWEEP = 10                     -- seconds between sweeps for entities no creation hook reported
local REVISION_POLL = 0.1            -- seconds between material-hash revision polls
local RETRY, RETRY_MAX = 0.25, 4     -- a name without hashes yet: first and longest delay
local REFRESH, REFRESH_MAX = 0.5, 8  -- no revision available: first and longest delay to read all
local WRITE, WRITE_MAX = 1, 60       -- after Remix refused a write: first and longest delay
-- What a material is to the entity that uses it. PROCEDURAL is an outline made by Lua, which
-- TrackMaterial would look for on disk in vain; its hashes appear once it is drawn.
local OUTLINE, ORDINARY, PROCEDURAL = 1, 2, 3

local templates = {["template face"] = true, ["template eyebrows"] = true, ["template nose"] = true,
    ["template eyeline up"] = true, ["template eyeline down"] = true, ["template eyewhites"] = true,
    ["template eye"] = true, ["template teeth"] = true, ["template tongue"] = true}

local function normalize(name)
    return (name:lower():gsub("^!", ""):gsub("\\", "/"):gsub("%.vmt$", ""))
end
local function basename(name)
    local base = normalize(name):match("([^/]+)$")
    return base and (base:gsub("%s*%b()$", ""))
end
local function is_outline(name, family)
    local base = basename(name) or ""
    return (family and (base == "hei" or base == "touming")) or base:match("^outline") ~= nil or
        base:match("[_%-%s]outlines?$") ~= nil or base:match("[_%-%s]outline[_%-%s]") ~= nil
end
local function studio(model)
    return isstring(model) and model:find("%.[mM][dD][lL]$") ~= nil
end

-- Entities, looked at in turn; records[ent] is what was last seen on one.
local list, records, fresh, cursor = {}, {}, {}, 1
local models = {}            -- "model:skin:skins" -> {count, family, names = {{name, kind}, ...}}
local names, tracked = {}, {} -- names[name] = {outline = uses, ordinary = uses, hashes, retry, delay}
local queue, queued, head, tail = {}, {}, 1, 1
local list_dirty, published = true, ""
local revision, next_poll, refresh_at, refresh_delay = nil, 0, 0, REFRESH
local next_sweep, next_retry, next_prune = 0, 0, 0
local writes, active = {}, false

local function enqueue(name)
    if queued[name] then return end
    queued[name], queue[tail], tail = true, name, tail + 1
end
local function requeue_all()
    for name in pairs(names) do enqueue(name) end
end

local function retain(name, kind)
    local state = names[name]
    if not state then
        state = {outline = 0, ordinary = 0, delay = RETRY}
        names[name] = state
        enqueue(name)
    end
    local outline, ordinary = state.outline > 0, state.ordinary > 0
    if kind == ORDINARY then state.ordinary = state.ordinary + 1 else state.outline = state.outline + 1 end
    if state.hashes and (outline ~= (state.outline > 0) or ordinary ~= (state.ordinary > 0)) then list_dirty = true end
    if kind == OUTLINE and not tracked[name] and isfunction(RemixMaterial.TrackMaterial) then
        tracked[name] = true
        RemixMaterial.TrackMaterial(name)
    end
end
local function release(name, kind)
    local state = names[name]
    if not state then return end
    local outline, ordinary = state.outline > 0, state.ordinary > 0
    if kind == ORDINARY then state.ordinary = state.ordinary - 1 else state.outline = state.outline - 1 end
    if state.hashes and (outline ~= (state.outline > 0) or ordinary ~= (state.ordinary > 0)) then list_dirty = true end
    if state.outline <= 0 and state.ordinary <= 0 then names[name] = nil end
end
-- An entity's materials as a set: name -> kind. A name in use as an ordinary material protects its
-- images; an outline found by its real name (TrackMaterial) wins over a procedural one.
local function add(want, name, kind)
    local had = want[name]
    if had == ORDINARY or kind == ORDINARY then want[name] = ORDINARY
    elseif had ~= OUTLINE then want[name] = kind end
end
local function contribute(record, want)
    local had = record.contributes
    for name, kind in pairs(had) do if want[name] ~= kind then release(name, kind) end end
    for name, kind in pairs(want) do if had[name] ~= kind then retain(name, kind) end end
    record.contributes = want
end

local function watch(ent)
    if records[ent] or not IsValid(ent) then return end
    local record = {index = #list + 1, subs = {}, entries = {}, materials = {}, count = 0, contributes = {}}
    list[record.index], records[ent] = ent, record
    fresh[#fresh + 1] = ent
end
local function forget(index)
    local n = #list
    local ent, last = list[index], list[n]
    local record = records[ent]
    list[n] = nil
    if index < n then
        list[index] = last
        records[last].index = index
    end
    records[ent] = nil
    if record then contribute(record, {}) end
end

local function model_data(ent, model, skin)
    local skins = isfunction(ent.SkinCount) and ent:SkinCount() or 1
    local key = model .. ":" .. tostring(skin) .. ":" .. tostring(skins)
    local data = models[key]
    if data then return data end
    local materials = ent:GetMaterials()
    if not istable(materials) or #materials == 0 then return nil end
    local template = 0
    for _, name in ipairs(materials) do
        if isstring(name) and templates[basename(name)] then template = template + 1 end
    end
    data = {count = #materials, family = template >= 2, names = {}}
    for _, name in ipairs(materials) do
        if isstring(name) and name ~= "" then
            data.names[#data.names + 1] = {normalize(name), is_outline(name, data.family) and OUTLINE or ORDINARY}
        end
    end
    models[key] = data
    return data
end

-- Looks at one entity: its model and skin, sub-materials and private proxy materials (rtx_pseudoplayer's
-- RTXMaterials). Rebuilds its set of names only when one of them changed. Returns the slots it read.
local function scan(ent, record)
    local model = ent:GetModel()
    local changed = false
    if model ~= record.model then record.model, record.skin, record.data, changed = model, nil, nil, true end
    if not studio(model) then
        -- World and brush entities, sprites: only the materials of loaded models count (ADR 0047).
        if changed and next(record.contributes) then contribute(record, {}) end
        return 1
    end
    local skin = ent:GetSkin()
    if skin ~= record.skin or not record.data then
        record.skin, record.data, changed = skin, model_data(ent, model, skin), true
        for index in pairs(record.subs) do record.subs[index] = nil end
    end
    local data = record.data
    if not data then -- its materials are not known yet: ask again at the next visit
        if next(record.contributes) then contribute(record, {}) end
        return 2
    end
    local subs = record.subs
    for index = 0, data.count - 1 do
        local name = ent:GetSubMaterial(index)
        if not isstring(name) or name == "" then name = nil end
        if subs[index] ~= name then subs[index], changed = name, true end
    end
    local entries, materials, count = record.entries, record.materials, 0
    local proxies = ent.RTXMaterials
    if istable(proxies) then
        for _, entry in ipairs(proxies) do
            if istable(entry) and isstring(entry.name) and entry.material then
                count = count + 1
                if entries[count] ~= entry or materials[count] ~= entry.material then
                    entries[count], materials[count], changed = entry, entry.material, true
                end
            end
        end
    end
    if count ~= record.count then
        for i = count + 1, record.count do entries[i], materials[i] = nil, nil end
        record.count, changed = count, true
    end
    if changed then
        local want, family = {}, data.family
        for _, entry in ipairs(data.names) do add(want, entry[1], entry[2]) end
        for _, name in pairs(subs) do
            add(want, normalize(name), not is_outline(name, family) and ORDINARY
                or name:sub(1, 1) == "!" and PROCEDURAL or OUTLINE)
        end
        for i = 1, count do
            local material = materials[i]
            local name = isfunction(material.GetName) and material:GetName()
            if isstring(name) and name ~= "" then
                add(want, normalize(name), is_outline(entries[i].name, family) and PROCEDURAL or ORDINARY)
            end
        end
        contribute(record, want)
    end
    return 2 + data.count + count
end

-- New entities first, then the others in turn, until this frame's slots are spent.
local function poll()
    local budget = SLOTS_PER_FRAME
    while budget > 0 and #fresh > 0 do
        local ent = fresh[#fresh]
        fresh[#fresh] = nil
        local record = records[ent]
        if record then
            if IsValid(ent) then budget = budget - scan(ent, record) else forget(record.index) end
        end
    end
    local visits = #list
    while budget > 0 and visits > 0 and #list > 0 do
        visits = visits - 1
        if cursor > #list then cursor = 1 end
        local ent = list[cursor]
        if IsValid(ent) then
            budget = budget - scan(ent, records[ent])
            cursor = cursor + 1
        else
            forget(cursor)
        end
    end
end
local function sweep(now)
    if now < next_sweep then return end
    next_sweep = now + SWEEP
    for _, ent in ipairs(ents.GetAll()) do watch(ent) end
end
local function prune(now)
    if now < next_prune then return end
    next_prune = now + SWEEP
    for i = #list, 1, -1 do if not IsValid(list[i]) then forget(i) end end
end

local function hashes_of(name)
    local found
    for _, hash in ipairs(RemixMaterial.GetAllTextureHashes(name) or {}) do
        if isstring(hash) and hash:match("^0[xX]%x+$") and not hash:match("^0[xX]0+$") then
            found = found or {}
            found[#found + 1] = hash:lower()
        end
    end
    return found
end
local function same(a, b)
    if a == nil or b == nil then return a == b end
    if #a ~= #b then return false end
    for i = 1, #a do if a[i] ~= b[i] then return false end end
    return true
end
local function look_up(now)
    for _ = 1, NAMES_PER_FRAME do
        if head >= tail then
            if head > 1 then head, tail = 1, 1 end
            return
        end
        local name = queue[head]
        queue[head], head = nil, head + 1
        queued[name] = nil
        local state = names[name]
        if state then
            local hashes = hashes_of(name)
            if not same(hashes, state.hashes) then state.hashes, list_dirty = hashes, true end
            if hashes then
                state.retry, state.delay = nil, RETRY
            else
                -- Remix hashes a texture once it is drawn: ask again later, less often each time.
                state.retry, state.delay = now + state.delay, math.min(state.delay * 2, RETRY_MAX)
            end
        end
    end
end
local function retry_due(now)
    if now < next_retry then return end
    next_retry = now + RETRY
    for name, state in pairs(names) do
        if state.retry and now >= state.retry then
            state.retry = nil
            enqueue(name)
        end
    end
end
local function poll_revision(now)
    if now < next_poll then return end
    next_poll = now + REVISION_POLL
    local current = isfunction(RemixMaterial.GetMaterialHashRevision) and RemixMaterial.GetMaterialHashRevision() or nil
    if current ~= nil then
        if current ~= revision then
            revision, refresh_delay = current, REFRESH
            requeue_all()
        end
    elseif now >= refresh_at then
        -- Without a revision a changed binding cannot be seen: read every name again, less often each time.
        refresh_at, refresh_delay = now + refresh_delay, math.min(refresh_delay * 2, REFRESH_MAX)
        requeue_all()
    end
end

local function texture_list()
    if not list_dirty then return published end
    list_dirty = false
    -- A shared image must not hide an ordinary body, face or prop material.
    local protected, values, seen = {}, {}, {}
    for _, state in pairs(names) do
        if state.ordinary > 0 and state.hashes then
            for _, hash in ipairs(state.hashes) do protected[hash] = true end
        end
    end
    for _, state in pairs(names) do
        if state.outline > 0 and state.hashes then
            for _, hash in ipairs(state.hashes) do
                if not protected[hash] and not seen[hash] then
                    seen[hash] = true
                    values[#values + 1] = hash
                end
            end
        end
    end
    table.sort(values)
    published = table.concat(values, ", ")
    return published
end

local function write(key, value, now)
    local state = writes[key]
    if not state then
        state = {delay = WRITE, wait = 0}
        writes[key] = state
    end
    if state.sent == value or now < state.wait then return end
    if RemixConfig.SetConfigVariable(key, value) then
        state.sent, state.delay, state.wait = value, WRITE, 0
    else
        -- Remix refused it and printed a warning: try again later, less often each time.
        state.wait, state.delay = now + state.delay, math.min(state.delay * 2, WRITE_MAX)
    end
end

local function material_api()
    return istable(RemixMaterial) and isfunction(RemixMaterial.GetAllTextureHashes)
end
local function sync()
    local now = RealTime()
    local config = istable(RemixConfig) and isfunction(RemixConfig.SetConfigVariable)
    if config then write("rtx.gmod.ignoreOutlineMeshes", shells_enabled:GetBool() and "True" or "False", now) end
    if not material_api() then return end
    if config and names_enabled:GetBool() then
        if not active then
            active, list_dirty, next_sweep = true, true, 0
            requeue_all()
        end
        sweep(now)
        poll()
        poll_revision(now)
        retry_due(now)
        look_up(now)
        write("rtx.gmod.ignoredOutlineTextures", texture_list(), now)
    else
        active = false
        prune(now)
        if config then write("rtx.gmod.ignoredOutlineTextures", "", now) end
    end
end
hook.Add("OnEntityCreated", "nativeloader_model_layers", function(ent) if material_api() then watch(ent) end end)
hook.Add("Think", "nativeloader_model_layers", sync)
concommand.Add("nativeloader_model_layers_status", function()
    local count = 0
    for _ in pairs(names) do count = count + 1 end
    local sent = writes["rtx.gmod.ignoredOutlineTextures"]
    print(string.format("[nativeloader] Outline suppression: names=%s, shells=%s; %d entities, %d materials; textures=%s",
        tostring(names_enabled:GetBool()), tostring(shells_enabled:GetBool()), #list, count,
        tostring(sent and sent.sent or "pending")))
end)
