-- Eye-only texture identities, transient Remix aliases and scene-adaptive albedo emission (ADR 0088).
-- No hotloader hook: its renderer uses these exact public IMaterials. Never change an entity override.
local matcher = include("nativeloader/eye_white_names.lua")
local vtf = include("nativeloader/eye_white_vtf.lua")
local enabled = CreateClientConVar("nativeloader_eye_whites", "1", true, false,
    "Steady eye whites for imported characters without a PBR replacement")
local brightness = CreateClientConVar("nativeloader_eye_white_brightness", "100", true, false,
    "Eye-white brightness in percent (automatic and scene-adaptive PBR eye materials)", 0, 200)
local PREFIX = "rtx.gmod."
local CACHE, CACHE_LIMIT = "nativeloader/eye_whites/", 1024 * 1024 * 1024
local states, atlases, sent, retries, owned = {}, {}, {}, {}, {}
local assets, key, parts, partIndex, epoch, nextSweep = nil, nil, nil, 1, 0, 0
local cursor, list, nextWrite, nextPrepare = 1, {}, 0, 0
local preparedBytes, prepareMaxMs, warmQueue = 0, 0, {}
local supported = false
-- Full content ID + slot/native name survive a re-import and do not depend on a source folder.
local CHOICES, MAX_CHOICES, MAX_JSON = "nativeloader/eye_white_choices.json", 4096, 1024 * 1024
local storedExists = file.Exists(CHOICES, "DATA")
local storedSize = storedExists and file.Size(CHOICES, "DATA") or -1
local choices, loadedBytes, choicesOK = {}, nil, not storedExists or (storedSize >= 0 and storedSize <= MAX_JSON)
if choicesOK and storedExists then
    loadedBytes = file.Read(CHOICES, "DATA")
    choicesOK = loadedBytes ~= nil
end
local function assetID(id)
    return type(id) == "string" and #id == 64 and id:match("^[0-9a-f]+$") and id or nil
end
local function materialKey(part, index)
    if not istable(part) or type(part.name) ~= "string" or #part.name > 512 or
        type(index) ~= "number" or index < 1 or index > 4096 or index % 1 ~= 0 then return end
    return tostring(index) .. ":" .. part.name
end
if loadedBytes then
    local ok, data = false, nil
    if #loadedBytes <= MAX_JSON then ok, data = pcall(util.JSONToTable, loadedBytes) end
    choicesOK = ok and istable(data) and data.version == 1 and istable(data.assets)
    local count = 0
    if choicesOK then
        for id, materials in pairs(data.assets) do
            if not assetID(id) or not istable(materials) then choicesOK = false break end
            choices[id] = {}
            for name, value in pairs(materials) do
                local slot = type(name) == "string" and name:match("^(%d+):")
                count = count + 1
                if not slot or tonumber(slot) < 1 or tonumber(slot) > 4096 or #name > 517 or
                    type(value) ~= "boolean" or count > MAX_CHOICES then choicesOK = false break end
                choices[id][name] = value
            end
            if not choicesOK then break end
        end
    end
    if not choicesOK then choices = {} end -- Keep unreadable/foreign data on disk, never overwrite it.
end
local function choice(id, part, index)
    local name = materialKey(part, index)
    if name and choices[id] then return choices[id][name] end
end
local function selected(id, part, index)
    local value = choice(id, part, index)
    if value ~= nil then return value end
    return matcher.matches(part.name, part.en or part.englishName or part.nameEnglish)
end
-- Metadata is not evidence of use: the library keeps it for characters never spawned this map.
-- This public entity list includes native NPCs/players and client ragdolls without requesting assets.
local function spawned()
    local live = {}
    if not istable(mmdhl) or not isfunction(mmdhl.Entities) or not isfunction(mmdhl.GetAsset) then return live end
    for _, ent in ipairs(mmdhl.Entities()) do
        if IsValid(ent) and not ent.MMDHLPreviewRig then
            local id = assetID(mmdhl.GetAsset(ent))
            if id and istable(mmdhl.assets) and istable(mmdhl.assets[id]) then live[id] = mmdhl.assets[id] end
        end
    end
    return live
end
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
local function normalize(name, asset)
    if type(name) ~= "string" then return end
    name = name:lower():gsub("\\", "/"):gsub("^!", ""):gsub("%.vmt$", "")
    local id = name:match("^mmd/(%x+)/[^/]+$")
    return id and #id == 16 and (not asset or id == asset:sub(1, 16)) and name or nil
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
        assets = spawned()
        key, parts, partIndex, epoch = nil, nil, 1, epoch + 1
    end
    for _ = 1, 128 do
        if parts and parts[partIndex] ~= nil then
            local part = parts[partIndex]
            partIndex = partIndex + 1
            if istable(part) and selected(key, part, partIndex - 1) then
                local name = normalize(part.path, key)
                if name then
                    local state = states[name]
                    if not state then
                        state = {name = name, asset = key, index = partIndex - 1, at = 0}
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
-- The cache stays under CACHE_LIMIT: the oldest proxies go first (one is rebuilt when needed again);
-- a proxy this session bound is never deleted.
local function makeRoom(size)
    local entries, total = {}, size
    for _, name in ipairs(file.Find(CACHE .. "*.vtf", "DATA") or {}) do
        local path = CACHE .. name
        local bytes = math.max(file.Size(path, "DATA") or 0, 0)
        total = total + bytes
        if not owned[path] then entries[#entries + 1] = {path = path, bytes = bytes, time = file.Time(path, "DATA") or 0} end
    end
    table.sort(entries, function(a, b) return a.time < b.time end)
    for _, entry in ipairs(entries) do
        if total <= CACHE_LIMIT then break end
        file.Delete(entry.path)
        total = total - entry.bytes
    end
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
        local path = CACHE .. digest .. ".vtf"
        file.CreateDir("nativeloader/eye_whites")
        if not file.Exists(path, "DATA") then
            makeRoom(#proxyBytes)
            file.Write(path, proxyBytes)
        end
        -- A user-edited or incomplete cache entry is never overwritten or bound.
        if file.Read(path, "DATA") ~= proxyBytes then state.reason = "cache differs" return end
        owned[path] = true
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
local function partFor(id, index)
    local info = assetID(id) and spawned()[id]
    local part = info and istable(info.materials) and info.materials[index]
    if not materialKey(part, index) or not normalize(part.path, id) then return end
    return part
end
local function inspect(id, index)
    local part = partFor(id, index)
    if not part or not file.Exists("materials/" .. normalize(part.path, id) .. ".vmt", "GAME") then return end
    local name = normalize(part.path, id)
    local mat = Material(name)
    local texture = mat and not mat:IsError() and mat:GetTexture("$basetexture")
    local state = states[name]
    if state and state.original and sameTexture(texture, state.proxy) then texture = state.original end
    local texName = texture and not texture:IsError() and texture:GetName():lower():gsub("\\", "/")
    if not texName or not texName:match("^mmd/t/%x+$") or
        not file.Exists("materials/" .. texName .. ".vtf", "GAME") then return end
    return mat, texture
end
local function setChoice(id, index, value)
    if value ~= nil and type(value) ~= "boolean" then return false end
    local part = partFor(id, index)
    if not part or not inspect(id, index) or not choicesOK or file.Size(CHOICES, "DATA") > MAX_JSON or
        file.Read(CHOICES, "DATA") ~= loadedBytes then return false end
    local name, count = materialKey(part, index), 0
    for _, materials in pairs(choices) do for _ in pairs(materials) do count = count + 1 end end
    local previous = choice(id, part, index)
    if previous == value then return true end
    if previous == nil and value ~= nil and count >= MAX_CHOICES then return false end
    choices[id] = choices[id] or {}
    choices[id][name] = value
    if next(choices[id]) == nil then choices[id] = nil end
    local bytes = util.TableToJSON({version = 1, assets = choices}, true)
    if not bytes or #bytes > MAX_JSON then
        choices[id] = choices[id] or {} choices[id][name] = previous
        return false
    end
    file.CreateDir("nativeloader")
    file.Write(CHOICES, bytes)
    if file.Read(CHOICES, "DATA") ~= bytes then
        choices[id] = choices[id] or {} choices[id][name] = previous
        return false
    end
    loadedBytes = bytes
    -- Restore immediately, then let the usual validated alias publication bind any new selection.
    -- Retire the old state even when a re-import replaces the metadata table during this session.
    for i = #list, 1, -1 do
        local state = list[i]
        if state.asset == id and state.index == index then
            restore(state)
            states[state.name], list[i] = nil, list[#list]
            list[#list] = nil
        end
    end
    assets, parts, nextSweep, nextWrite = nil, nil, 0, 0
    return true
end
local function materials(id)
    local info, out = assetID(id) and spawned()[id], {}
    for index, part in ipairs(info and info.materials or {}) do
        if index > 4096 then break end
        if materialKey(part, index) and normalize(part.path, id) then
            out[#out + 1] = {index = index, name = part.name, path = part.path,
                automatic = matcher.matches(part.name, part.en or part.englishName or part.nameEnglish),
                choice = choice(id, part, index), selected = selected(id, part, index)}
        end
    end
    return out
end
local function openAssignments(target)
    local L = include("nativeloader/i18n.lua").L
    local frame = vgui.Create("DFrame")
    frame:SetSize(math.min(860, ScrW() - 40), math.min(680, ScrH() - 40))
    frame:Center()
    frame:SetTitle(L("Choose eye-white materials"))
    frame:MakePopup()
    local help = frame:Add("DLabel")
    help:Dock(TOP) help:SetTall(60) help:SetWrap(true)
    help:SetText(L("Choose a spawned character here, or look at one before you open this window. Your choices are saved for this character and apply to all its copies at once, without respawning. Steady eye whites for imported characters and Eye-white brightness still apply."))
    local picker = frame:Add("DComboBox")
    picker:Dock(TOP) picker:SetTall(28)
    picker:SetValue(L("Choose a spawned character"))
    local message = frame:Add("DLabel")
    message:Dock(TOP) message:SetTall(42) message:SetWrap(true)
    message:SetText(L("Spawn an imported character first, from External Models. Only the materials of imported characters can be chosen."))
    local navigation = frame:Add("DPanel")
    navigation:Dock(BOTTOM) navigation:SetTall(30)
    local previous, nextPage = navigation:Add("DButton"), navigation:Add("DButton")
    previous:Dock(LEFT) previous:SetWide(180) previous:SetText(L("Previous materials"))
    nextPage:Dock(RIGHT) nextPage:SetWide(180) nextPage:SetText(L("Next materials"))
    previous:SetEnabled(false) nextPage:SetEnabled(false)
    local scroll = frame:Add("DScrollPanel")
    scroll:Dock(FILL)
    local current, rows, page, pending, stop = nil, {}, 1, 1, 0
    local function showPage()
        scroll:Clear()
        pending, stop = (page - 1) * 24 + 1, math.min(page * 24, #rows)
        previous:SetEnabled(page > 1) nextPage:SetEnabled(stop < #rows)
    end
    local function choose(id)
        current, rows, page = id, materials(id), 1
        message:SetText(L("Ticked materials are eye whites. Use automatic detection removes your choice for that material. When the eyes share a texture with the face, the picture shows the face too; only the material you tick changes."))
        showPage()
    end
    previous.DoClick = function() page = math.max(1, page - 1) showPage() end
    nextPage.DoClick = function() page = page + 1 showPage() end
    picker.OnSelect = function(_, _, _, id) choose(id) end
    local live, ids = spawned(), {}
    for id in pairs(live) do ids[#ids + 1] = id end
    table.sort(ids)
    if not IsValid(target) then
        local player = LocalPlayer()
        target = IsValid(player) and player:GetEyeTrace().Entity or nil
    end
    local wanted = IsValid(target) and istable(mmdhl) and isfunction(mmdhl.GetAsset) and mmdhl.GetAsset(target)
    for _, id in ipairs(ids) do
        local name = type(live[id].name) == "string" and live[id].name or id:sub(1, 16)
        local number = picker:AddChoice(name .. " (" .. id:sub(1, 8) .. ")", id)
        if id == wanted or (#ids == 1) then picker:ChooseOptionID(number) end
    end
    -- Populate only one page, at most four rows per frame. No library textures or atlas clones here.
    local frameThink = frame.Think
    frame.Think = function(self)
        if frameThink then frameThink(self) end -- Keep DFrame's normal dragging/resizing behavior.
        for _ = 1, 4 do
            if pending > stop then return end
            local entry, id = rows[pending], current
            pending = pending + 1
            local row = scroll:Add("DPanel")
            row:Dock(TOP) row:SetTall(118) row:DockMargin(0, 0, 0, 5)
            row.Paint = function(_, width, height)
                surface.SetDrawColor(240, 240, 240, 255) surface.DrawRect(0, 0, width, height)
            end
            local preview = row:Add("DImage")
            preview:Dock(LEFT) preview:SetWide(104) preview:DockMargin(4, 4, 8, 4) preview:SetKeepAspect(true)
            local _, texture = inspect(id, entry.index)
            if texture then
                local thumb = CreateMaterial("nativeloader_eye_thumb_" .. util.SHA256(texture:GetName()), "UnlitGeneric",
                    {["$basetexture"] = texture:GetName(), ["$translucent"] = 1, ["$vertexcolor"] = 1})
                thumb:SetTexture("$basetexture", texture) preview:SetMaterial(thumb)
            end
            local label = row:Add("DLabel")
            label:Dock(TOP) label:SetTall(36) label:SetWrap(true)
            label:SetTextColor(Color(25, 25, 25))
            label:SetText(tostring(entry.index) .. ". " .. entry.name) label:SetTooltip(entry.name .. "\n" .. entry.path)
            local status = row:Add("DLabel")
            status:Dock(TOP) status:SetTall(26)
            status:SetTextColor(Color(60, 60, 60))
            local controls = row:Add("DPanel")
            controls:Dock(TOP) controls:SetTall(32)
            controls.Paint = function() end
            local toggle = controls:Add("DCheckBoxLabel")
            toggle:Dock(LEFT) toggle:SetWide(220) toggle:SetText(L("Eye white")) toggle:SetTextColor(Color(25, 25, 25))
            local reset = controls:Add("DButton")
            reset:Dock(FILL) reset:SetText(L("Use automatic detection"))
            local updating = false
            local function refresh()
                local part = partFor(id, entry.index)
                local manual = part and choice(id, part, entry.index)
                updating = true
                toggle:SetChecked(part and selected(id, part, entry.index) or false)
                toggle:SetEnabled(texture ~= nil and part ~= nil)
                reset:SetEnabled(texture ~= nil and part ~= nil and manual ~= nil)
                if manual ~= nil then
                    status:SetText(manual and L("Chosen: eye white") or L("Chosen: ordinary material"))
                else
                    status:SetText(entry.automatic and L("Automatic: eye white") or L("Automatic: ordinary material"))
                end
                if not texture then status:SetText(L("Texture not available")) end
                updating = false
            end
            local function change(value)
                if not setChoice(id, entry.index, value) then
                    message:SetText(L("Your choice could not be saved: the character may have been removed, or the file of saved choices was changed or cannot be read. No file was overwritten."))
                end
                refresh()
            end
            toggle.OnChange = function(_, value) if not updating then change(value) end end
            reset.DoClick = function() change(nil) end
            refresh()
        end
    end
    return frame
end
NATIVELOADER_EYE_WHITES = {SetChoice = setChoice, Materials = materials, Open = openAssignments}
concommand.Add("nativeloader_eye_white_materials", function() openAssignments() end)
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
