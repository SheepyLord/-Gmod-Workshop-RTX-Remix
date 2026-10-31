-- Outline suppression owns only transient runtime options, leaving original materials untouched.
local enabled = CreateClientConVar("nativeloader_ignore_outlines", "1", true, false)
local models, entities = {}, setmetatable({}, {__mode = "k"})
local outlines, ordinary, hashes = {}, {}, {}
local sentEnabled, sentHashes, revision, registryRevision
local nextHashes, dirty = 0, true
local protected, nextProtected = {}, 0
local templates = {["template face"] = true, ["template eyebrows"] = true, ["template nose"] = true,
    ["template eyeline up"] = true, ["template eyeline down"] = true, ["template eyewhites"] = true,
    ["template eye"] = true, ["template teeth"] = true, ["template tongue"] = true}

local function normalize(name)
    return name:lower():gsub("^!", ""):gsub("\\", "/"):gsub("%.vmt$", "")
end
local function basename(name)
    local base = normalize(name):match("([^/]+)$")
    return base and base:gsub("%s*%b()$", "")
end
local function is_outline(name, family)
    local base = basename(name) or ""
    return (family and (base == "hei" or base == "touming")) or base:match("^outline") ~= nil or
        base:match("[_%-%s]outlines?$") ~= nil or base:match("[_%-%s]outline[_%-%s]") ~= nil
end
local function register(name, outline, procedural)
    name = normalize(name)
    if outline then
        ordinary[name] = nil
        if not outlines[name] then
            outlines[name], dirty = true, true
            if not procedural then RemixMaterial.TrackMaterial(name) end
        end
    elseif not ordinary[name] then
        ordinary[name], dirty = true, true
    end
end
local function discover()
    local all, seen = ents.GetAll(), {}
    for _, ent in ipairs(all) do seen[ent] = true end
    for ent in pairs(entities) do if not seen[ent] then all[#all + 1] = ent end end
    for _, ent in ipairs(all) do
        if IsValid(ent) then
            local model = ent:GetModel()
            local skins = isfunction(ent.SkinCount) and ent:SkinCount() or 1
            local key = model and model .. ":" .. tostring(ent:GetSkin()) .. ":" .. skins
            local data = key and models[key]
            if key and not data then
                local materials = ent:GetMaterials()
                if materials and #materials > 0 then
                    local count = 0
                    for _, name in ipairs(materials) do if templates[basename(name)] then count = count + 1 end end
                    data = {count = #materials, family = count >= 2}
                    models[key] = data
                    for _, name in ipairs(materials) do register(name, is_outline(name, data.family), false) end
                end
            end
            local previous = entities[ent]
            if data and (not previous or previous.key ~= key or RealTime() >= (previous.nextScan or 0)) then
                for index = 0, data.count - 1 do
                    local name = ent:GetSubMaterial(index)
                    if name and name ~= "" then register(name, is_outline(name, data.family), name:sub(1, 1) == "!") end
                end
                entities[ent] = {key = key, nextScan = RealTime() + 0.1}
            end
            if data and istable(ent.RTXMaterials) then
                for _, entry in ipairs(ent.RTXMaterials) do
                    if isstring(entry.name) and entry.material then
                        register(entry.material:GetName(), is_outline(entry.name, data.family), true)
                    end
                end
            end
        end
    end
end
local function sync()
    if not istable(RemixConfig) or not isfunction(RemixConfig.SetConfigVariable) or
        not istable(RemixMaterial) or not isfunction(RemixMaterial.GetAllTextureHashes) then return end
    local value = enabled:GetBool() and "True" or "False"
    if value ~= sentEnabled and RemixConfig.SetConfigVariable("rtx.gmod.ignoreOutlineMeshes", value) then sentEnabled = value end
    if enabled:GetBool() then
        discover()
        local current = RemixMaterial.GetMaterialHashRevision and RemixMaterial.GetMaterialHashRevision()
        local refreshProtected = dirty or (current ~= nil and current ~= revision) or RealTime() >= nextProtected
        if RemixMaterial.GetCachedMaterials and (current == nil or current ~= registryRevision) then
            for _, name in ipairs(RemixMaterial.GetCachedMaterials()) do
                if is_outline(name, false) then register(name, true, true) end
            end
            registryRevision = current
        end
        if dirty or current == nil or current ~= revision or RealTime() >= nextHashes then
            local unresolved = false
            for name in pairs(outlines) do
                local found = false
                for _, hash in ipairs(RemixMaterial.GetAllTextureHashes(name) or {}) do
                    if isstring(hash) and hash:match("^0[xX]%x+$") and not hash:match("^0[xX]0+$") then
                        hashes[hash:lower()], found = true, true
                    end
                end
                unresolved = unresolved or not found
            end
            revision, dirty = current, false
            nextHashes = unresolved and 0 or RealTime() + 0.25
        end
        if refreshProtected then
            -- A shared image must not hide an ordinary body, face or prop material.
            protected = {}
            for name in pairs(ordinary) do
                for _, hash in ipairs(RemixMaterial.GetAllTextureHashes(name) or {}) do
                    if isstring(hash) then protected[hash:lower()] = true end
                end
            end
            nextProtected = RealTime() + 0.25
        end
    end
    local values = {}
    if enabled:GetBool() then for hash in pairs(hashes) do if not protected[hash] then values[#values + 1] = hash end end end
    table.sort(values)
    value = table.concat(values, ", ")
    if value ~= sentHashes and RemixConfig.SetConfigVariable("rtx.gmod.ignoredOutlineTextures", value) then sentHashes = value end
end
hook.Add("OnEntityCreated", "nativeloader_model_layers", function(ent) entities[ent] = entities[ent] or {} end)
hook.Add("Think", "nativeloader_model_layers", sync)
concommand.Add("nativeloader_model_layers_status", function()
    print("[nativeloader] Outline suppression=" .. tostring(enabled:GetBool()) .. "; textures=" .. tostring(sentHashes or "pending"))
end)
