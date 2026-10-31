-- Imported files retain their authored normals; Remix may regenerate them for world draws.
local enabled = CreateClientConVar("nativeloader_imported_model_normals", "0", true, false)
local nextScan, sent = 0, nil
local tracked = {}
local function sync()
    if RealTime() < nextScan then return end
    nextScan = RealTime() + 0.25
    if not RemixConfig or not isfunction(RemixConfig.SetConfigVariable) or
        not RemixMaterial or not isfunction(RemixMaterial.GetAllTextureHashes) then return end
    local names, hashes = {}, {}
    local function add(name)
        if isstring(name) and name ~= "" then names[name:gsub("^!", "")] = true end
    end
    if enabled:GetBool() and mmdhl then
        if isfunction(mmdhl.Entities) then
            for _, ent in ipairs(mmdhl.Entities()) do
                if IsValid(ent) and not ent.MMDHLEditorPreview and not ent.MMDHLHands then
                    local override = ent:GetMaterial()
                    for slot, name in ipairs(ent:GetMaterials() or {}) do
                        local sub = ent:GetSubMaterial(slot - 1)
                        add(sub ~= "" and sub or override ~= "" and override or name)
                    end
                end
            end
        end
        local props = mmdhl.props
        if props and props.RenderCache then
            for _, ent in ipairs(ents.FindByClass("mmdhl_prop")) do
                local entry = props.RenderCache[ent:GetAssetID()]
                for _, mat in pairs(entry and entry.materials or {}) do
                    if mat and isfunction(mat.GetName) then add(mat:GetName()) end
                end
            end
        end
        for name in pairs(names) do
            if not tracked[name] and name:sub(1, 4) == "mmd/" and isfunction(RemixMaterial.TrackMaterial) then
                RemixMaterial.TrackMaterial(name)
                tracked[name] = true
            end
            for _, hash in ipairs(RemixMaterial.GetAllTextureHashes(name) or {}) do
                if isstring(hash) and hash:match("^0[xX]%x+$") and not hash:match("^0[xX]0+$") then
                    hashes[hash:lower()] = true
                end
            end
        end
    end
    local values = {}
    for hash in pairs(hashes) do values[#values + 1] = hash end
    table.sort(values)
    local value = table.concat(values, ", ")
    if value ~= sent and
        RemixConfig.SetConfigVariable("rtx.gmod.importedModelSmoothNormalTextures", value) then sent = value end
end
hook.Add("Think", "nativeloader_imported_normals", sync)
cvars.AddChangeCallback("nativeloader_imported_model_normals", function() nextScan = 0 end,
    "nativeloader_imported_normals")
