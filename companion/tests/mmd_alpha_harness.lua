-- Run with LuaJIT; loads the actual companion script in a deterministic GMod/Remix API stub.
local source, scenario = arg[1], arg[2]
local now, think, calls, tracks, lookups, writes = 0, nil, {}, {}, 0, 0
local revision = 1
local materialLookups, fileLookups = 0, 0
local name = "mmd/0123456789abcdef/mask"
local hash = "0xFB1616F217669E2E"
local bindings, hashes, materialErrors = {[name] = name}, {[name] = {hash}}, {}
function isstring(v) return type(v) == "string" end
function istable(v) return type(v) == "table" end
function isfunction(v) return type(v) == "function" end
function RealTime() return now end
file = {Exists = function(path, realm)
    fileLookups = fileLookups + 1
    assert(realm == "GAME")
    local material = path:match("^materials/(.+)%.vmt$")
    return material and not materialErrors[material] or false
end}
function Material(path)
    materialLookups = materialLookups + 1
    return {
        IsError = function() return materialErrors[path] or false end,
        GetTexture = function()
            local binding = bindings[path]
            if not binding then return end
            return {IsError = function() return false end, GetName = function() return binding end}
        end
    }
end
hook = {Add = function(_, _, fn) think = fn end}
concommand = {Add = function() end}
RemixMaterial = {
    TrackMaterial = function(path) tracks[path] = (tracks[path] or 0) + 1 end,
    GetAllTextureHashes = function(path) lookups = lookups + 1 return hashes[path] end,
    GetMaterialHashRevision = function() return revision end
}
local refuse = false
local refuseTrack = false
local trackAttempts = 0
local track = RemixMaterial.TrackMaterial
RemixMaterial.TrackMaterial = function(path)
    trackAttempts = trackAttempts + 1
    if refuseTrack then return false end
    return track(path)
end
RemixConfig = {SetConfigVariable = function(key, value)
    assert(key == "rtx.gmod.mmdAlphaTexturesForSession", "must only write its NoSave option")
    writes = writes + 1
    if refuse then return false end
    calls[#calls + 1] = value
    return true
end}
mmdhl = {assets = {asset = {materials = {{path = name}}}}, softMaterials = {}}
local function frames(count, step)
    for _ = 1, count do now = now + (step or 1/60) think() end
end
local function value() return calls[#calls] end
local function contains(needle) return value() and value():find(needle:lower(), 1, true) end
if scenario == "no_api" then RemixConfig, RemixMaterial = nil, nil end
local savedConfig, savedMaterial = RemixConfig, RemixMaterial
if scenario == "late_api" then RemixConfig, RemixMaterial = nil, nil end
if scenario == "late_hash" then hashes[name] = nil end
if scenario == "late_material" then materialErrors[name] = true end
if scenario == "fallback" then bindings[name] = "color/white" end
if scenario == "invalid_hash" then hashes[name] = {"0x0", "0X0000", "not-a-hash", "0x12345678901234567", false} end
if scenario == "nil_revision" then RemixMaterial.GetMaterialHashRevision = nil end
if scenario == "no_tracking" then RemixMaterial.TrackMaterial = nil end
if scenario == "retry" then refuse = true end
if scenario == "track_retry" then refuseTrack = true hashes[name] = nil end
if scenario == "cold_library" then
    for i = 1, 4096 do
        local path = "mmd/0123456789abcdef/unused" .. i
        mmdhl.assets.asset.materials[i] = {path = path}
        bindings[path] = path
    end
    hashes = {}
end
-- Every texel partly transparent: the hotloader draws only the soft copy, so only its name has a hash.
local softName = "mmdhl_soft_v1_" .. string.rep("ab", 32) .. "_16"
local softHash = "0x4F9DC84370047174"
if scenario:match("^soft") then
    hashes[name] = nil
    bindings["!" .. softName], hashes[softName] = "mmd/t/2c7b2c8505cc6a6e", {softHash}
    mmdhl_soft = {asset = {soft = {"", "!" .. softName}}}
end
if mmdhl_soft and scenario ~= "soft_late" then mmdhl.softMaterials = mmdhl_soft end
assert(loadfile(source))()
frames(120)
if scenario == "no_api" then
    assert(#calls == 0)
elseif scenario == "late_api" then
    assert(#calls == 0)
    RemixConfig, RemixMaterial = savedConfig, savedMaterial
    frames(120)
    assert(contains(hash))
elseif scenario == "track_retry" then
    assert(value() == "" and trackAttempts == 0 and materialLookups == 0)
    hashes[name], revision = {hash}, revision + 1
    frames(120)
    assert(contains(hash) and trackAttempts > 0 and not tracks[name])
    refuseTrack, revision = false, revision + 1
    frames(120)
    assert(contains(hash) and tracks[name] == 1)
elseif scenario == "late_hash" or scenario == "late_material" then
    assert(value() == "")
    hashes[name], materialErrors[name] = {hash}, nil
    frames(300)
    assert(contains(hash), "late upload/mount was never tagged")
elseif scenario == "fallback" then
    assert(value() == "" and not tracks[name], "shared fallback textures must not enter the category")
    bindings[name] = name
    frames(300)
    assert(contains(hash))
elseif scenario == "invalid_hash" then
    assert(value() == "")
    hashes[name], revision = {"0Xa", "0x000000000000000a", hash, hash}, revision + 1
    frames(120)
    assert(value() == "0x000000000000000a, " .. hash:lower(), "hashes must be valid, sorted and deduplicated")
elseif scenario == "retry" then
    assert(#calls == 0 and writes <= 3, "refused writes need backoff")
    refuse = false
    frames(600)
    assert(contains(hash))
elseif scenario == "new_asset" then
    local other = "mmd/fedcba9876543210/new"
    mmdhl.assets.second = {materials = {{path = other}}}
    bindings[other], hashes[other] = other, {"0x1234"}
    frames(180)
    assert(contains(hash) and contains("0x0000000000001234"), "late assets must join the set")
elseif scenario == "prune" then
    assert(contains(hash))
    mmdhl.assets = {}
    frames(180)
    assert(value() == "", "unloaded assets must release their hashes")
elseif scenario == "revision" or scenario == "nil_revision" then
    local before = writes
    frames(120)
    assert(writes == before, "stable hashes must not rewrite the option")
    hashes[name], revision = {"0x5555"}, revision + 1
    frames(scenario == "revision" and 60 or 600)
    assert(contains("0x0000000000005555") and not contains(hash), "changed bindings must replace old hashes")
elseif scenario == "cold_library" then
    frames(600)
    assert(materialLookups == 0 and fileLookups == 0 and trackAttempts == 0,
        "an unspawned library must never load a material, texture or VMT")
    local active = mmdhl.assets.asset.materials[2000].path
    hashes[active], revision = {hash}, revision + 1
    frames(600)
    assert(contains(hash) and tracks[active] == 1, "drawn materials must still be classified")
    for path in pairs(tracks) do assert(path == active, "another library material was loaded") end
elseif scenario == "bounded" then
    local parts = {}
    for i = 1, 4096 do
        local path = "mmd/0123456789abcdef/part" .. i
        parts[i], bindings[path], hashes[path] = {path = path}, path, {hash}
    end
    mmdhl.assets.asset.materials = parts
    for _ = 1, 300 do
        local before = lookups
        frames(1)
        assert(lookups - before <= 16, "material/hash lookup budget exceeded")
    end
    assert(contains(hash))
elseif scenario == "soft_only" then
    assert(contains(softHash) and tracks[softName] == 1, "a part drawn only through its soft copy must be tagged by the copy's name")
    assert(not contains(hash), "the public material had no hash")
elseif scenario == "soft_late" then
    assert(value() == "", "nothing to tag before the soft copy exists")
    mmdhl.softMaterials = mmdhl_soft
    frames(180)
    assert(contains(softHash), "a soft copy created on first draw must join at the next sweep")
elseif scenario == "soft_budget" then
    local copies = {}
    for i = 1, 1024 do
        local copy = "mmdhl_soft_v1_" .. string.rep("cd", 32) .. "_" .. i
        copies[i], bindings["!" .. copy], hashes[copy] = "!" .. copy, "mmd/t/" .. i, {softHash}
    end
    mmdhl.softMaterials.asset.soft = copies
    for _ = 1, 300 do
        local before = lookups
        frames(1)
        assert(lookups - before <= 16, "soft copies share the lookup budget")
    end
    assert(contains(softHash))
elseif scenario == "soft_namespace" then
    mmdhl.softMaterials.asset.soft = {"!other_material", "!mmdhl_soft_v1_zz_1", "mmd/0123456789abcdef/mask", 42}
    hashes["other_material"], hashes["mmdhl_soft_v1_zz_1"] = {"0x1111"}, {"0x2222"}
    frames(180)
    assert(not contains("0x1111") and not contains("0x2222") and not tracks["other_material"], "only hotloader soft-copy names are tracked")
elseif scenario == "namespace" then
    mmdhl.assets.asset.materials = {{path = "models/props/glass"}, {path = "mmd/short/wrong"},
        {path = "mmd/0123456789abcdef/../../wrong"}, {path = "!MMD/0123456789ABCDEF/MASK.VMT"}}
    frames(180)
    assert(contains(hash) and tracks[name] == 1, "only generated MMD names may be tracked")
else
    assert(contains(hash))
    if scenario ~= "no_tracking" then assert(tracks[name] == 1, "track a mounted material once") end
end
print("PASS " .. scenario)
