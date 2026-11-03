-- Snapshot loaded textures without Material/FindMaterial/TrackMaterial or a render-resource load.
local label = tostring(NL_VRAM_LABEL or "snapshot"):gsub("[^%w_.-]", "_")
local function emit(kind, value)
    print("R12_" .. kind .. " " .. label .. " " .. util.TableToJSON(value))
end
local function stats()
    if RemixResource and isfunction(RemixResource.GetVramStats) then
        emit("VRAM", RemixResource.GetVramStats() or {})
    end
end
local assets, materials = 0, 0
for _, info in pairs(mmdhl and mmdhl.assets or {}) do
    assets = assets + 1
    materials = materials + #(istable(info) and info.materials or {})
end
local actors, library, soft = 0, 0, 0
for _ in pairs(mmdhl and mmdhl.actorRegistrations or {}) do actors = actors + 1 end
for _ in pairs(mmdhl and mmdhl.library and mmdhl.library.entries or {}) do library = library + 1 end
for _ in pairs(mmdhl and mmdhl.softMaterials or {}) do soft = soft + 1 end
emit("CONTEXT", {map = game.GetMap(), width = ScrW(), height = ScrH(), assets = assets,
    materials = materials, entities = #ents.GetAll(), seconds = RealTime(), actor_registrations = actors,
    library_entries = library, soft_material_sets = soft,
    player_model = IsValid(LocalPlayer()) and LocalPlayer():GetModel() or "unavailable"})
stats()
if not NLVramProbe then
    local ok, reason = pcall(require, "nlvramprobe")
    if not ok then emit("PROBE", {available = false, reason = tostring(reason)}) end
end
if not NLVramProbe or not NLVramProbe.available or not NLVramProbe.Begin() then
    emit("PROBE", {available = false})
    print("R12_CENSUS_DONE " .. label)
    return
end
timer.Simple(1, function()
    local rows, truncated, rootPresent = NLVramProbe.Read()
    if NLVramProbe.Info then emit("ABI", NLVramProbe.Info()) end
    NLVramProbe.End()
    if RemixConfig and RemixConfig.SetConfigVariable then
        emit("ALLOCATION_REQUEST", {accepted = RemixConfig.SetConfigVariable("rtx.profiler.memory.requestSnapshot", "True")})
    end
    stats()
    emit("PROBE", {available = true, textures = istable(rows) and #rows or 0, truncated = truncated == true,
        root_present = rootPresent == true})
    for _, row in ipairs(rows or {}) do emit("TEXTURE", row) end
    print("R12_CENSUS_DONE " .. label)
end)
