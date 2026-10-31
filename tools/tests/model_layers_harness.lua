-- Runs the shipped outline module (nativeloader_model_layers.lua) against mocked engine and Remix
-- boundaries. Arguments: the module's path and a scenario name. Prints PASS <scenario>.
local source, scenario = ...
local hooks, commands, writes, accepted, tracked, looked, created = {}, {}, {}, {}, {}, {}, {}
local values = {}
local now, revision = 0, 1
local calls = {model = 0, materials = 0, sub = 0, hashes = 0, all = 0, cached = 0, revision = 0}
istable = function(v) return type(v) == "table" end
isfunction = function(v) return type(v) == "function" end
isstring = function(v) return type(v) == "string" end
IsValid = function(v) return type(v) == "table" and v.valid end
RealTime = function() return now end
CreateClientConVar = function(name, default, archived)
    created[name] = {default = default, archived = archived}
    if values[name] == nil then values[name] = default end
    return {GetBool = function() return values[name] == "1" end}
end
hook = {Add = function(event, _, fn) hooks[event] = fn end}
concommand = {Add = function(name, fn) commands[name] = fn end}

local engine = {} -- what ents.GetAll() returns
ents = {GetAll = function()
    calls.all = calls.all + 1
    local copy = {}
    for i, ent in ipairs(engine) do copy[i] = ent end
    return copy
end}
local function entity(model, materials)
    local ent = {valid = true, model = model, skin = 0, skins = 2, materials = materials, sub = {}}
    function ent:GetModel() calls.model = calls.model + 1 return self.model end
    function ent:GetSkin() return self.skin end
    function ent:SkinCount() return self.skins end
    function ent:GetMaterials() calls.materials = calls.materials + 1 return self.materials end
    function ent:GetSubMaterial(index) calls.sub = calls.sub + 1 return self.sub[index] or "" end
    return ent
end
local MMD = {"tex/model/template face", "tex/model/template eyeline up (sirome)", "tex/model/hei", "tex/model/touming"}
local native = {["tex/model/template face"] = {"0x1"}, ["tex/model/template eyeline up (sirome)"] = {"0x2"},
    ["tex/model/hei"] = {"0x3"}, ["tex/model/touming"] = {"0x2"}, ["tex/model/body"] = {"0x1"},
    ["custom/outline_shell"] = {"0x4"}, ["pseudoplayermaterial_outline"] = {"0x9"},
    ["white_outline"] = {"0x5"}, ["black_outline"] = {"0x6"}, ["props/crate"] = {"0x10"}}
RemixMaterial = {
    TrackMaterial = function(name) tracked[name] = (tracked[name] or 0) + 1 end,
    GetAllTextureHashes = function(name)
        calls.hashes, looked[name] = calls.hashes + 1, (looked[name] or 0) + 1
        return native[name] or {}
    end,
    GetMaterialHashRevision = function() calls.revision = calls.revision + 1 return revision end,
    -- Every drawn material, the map's included: stock textures named *_outline are not model outlines.
    GetCachedMaterials = function()
        calls.cached = calls.cached + 1
        return {"white_outline", "black_outline", "custom/outline_shell", "tex/model/hei"}
    end,
}
local refuse = {} -- key -> how many more writes Remix refuses
RemixConfig = {SetConfigVariable = function(key, value)
    writes[#writes + 1] = {key, value, now}
    if (refuse[key] or 0) > 0 then refuse[key] = refuse[key] - 1 return false end
    accepted[key] = value
    return true
end}
local function attempts(key)
    local n = 0
    for _, write in ipairs(writes) do if write[1] == key then n = n + 1 end end
    return n
end
local LIST, SHELLS = "rtx.gmod.ignoredOutlineTextures", "rtx.gmod.ignoreOutlineMeshes"

local ent = entity("models/test.mdl", MMD)
engine[1] = ent
if scenario == "collision" then native["tex/model/template face"] = {"0x3"} end
if scenario == "late_hash" then native["tex/model/hei"] = {} end
if scenario == "ordinary_hei" then ent.materials = {"tex/model/body", "tex/model/hei"} end
if scenario == "proxy" then
    ent.RTXMaterials = {{name = "tex/model/hei", material = {GetName = function() return "pseudoplayermaterial_outline" end}},
        {name = "tex/model/hei"}} -- a slot rtx_pseudoplayer could not copy: no material
end
if scenario == "client_entity" then engine = {} end
if scenario == "nil_revision" then revision = nil end
if scenario == "no_api" then RemixConfig, RemixMaterial = nil, nil end
if scenario == "world" then
    -- A brush entity and the world use map materials; neither is a loaded model (ADR 0047).
    local brush = entity("*1", {"white_outline"})
    local world = entity("maps/gm_test.bsp", {"black_outline"})
    engine[2], engine[3] = brush, world
end
if scenario == "bounded" then
    local crate = {"props/crate"}
    for i, letter in ipairs({"a", "b", "c", "d", "e", "f", "g"}) do
        crate[#crate + 1] = "props/crate_" .. letter
        native["props/crate_" .. letter] = {string.format("0x%X", 0x100 + i)}
    end
    for i = 1, 2000 do engine[#engine + 1] = entity("models/props/crate" .. (i % 40) .. ".mdl", crate) end
end

assert(loadfile(source))()
assert(created.nativeloader_ignore_outlines.default == "1" and created.nativeloader_ignore_outlines.archived)
assert(created.nativeloader_ignore_outline_shells.default == "0" and created.nativeloader_ignore_outline_shells.archived,
    "the front-cull shell rule must be an archived opt-in")
if scenario == "client_entity" then hooks.OnEntityCreated(ent) end
local function frame(dt) now = now + (dt or 0) hooks.Think() end
local function frames(count, dt) for _ = 1, count do frame(dt) end end
-- 2001 entities take a few seconds to look at in turn; one model takes a frame.
local function settle() frames(scenario == "bounded" and 400 or 30, 1 / 60) end

if scenario == "no_api" then
    hooks.OnEntityCreated(ent) settle()
    assert(#writes == 0) print("PASS " .. scenario) return
end
settle()
local expected = "0x3"
if scenario == "collision" or scenario == "late_hash" or scenario == "ordinary_hei" then expected = "" end
if scenario == "proxy" then expected = "0x3, 0x9" end
assert(accepted[LIST] == expected, tostring(accepted[LIST]))
assert(accepted[SHELLS] == "False", "the shell rule must be off unless nativeloader_ignore_outline_shells is 1")
assert(calls.cached == 0, "the cached-material registry is not scanned: map textures named *_outline are not model outlines")
-- Settled: nothing changes, so nothing is written or looked up again, and the model's materials were read once.
local count, hashes = #writes, calls.hashes
frames(120, 1 / 60)
if scenario ~= "late_hash" and scenario ~= "nil_revision" then
    assert(#writes == count and calls.hashes == hashes, "settled frames looked up hashes or wrote again")
end
assert(calls.materials == 1 or scenario == "bounded", "model materials were read more than once")

if scenario == "late_hash" then
    -- The hash is missing until the material is drawn: asked again later, not every frame.
    assert(looked["tex/model/hei"] <= 8, "an unresolved name was looked up every frame: " .. looked["tex/model/hei"])
    native["tex/model/hei"] = {"0x3"}
    frames(60, 1 / 15)
    assert(accepted[LIST] == "0x3", "a late hash was never picked up")
elseif scenario == "toggle" then
    values.nativeloader_ignore_outlines = "0" frame()
    assert(accepted[LIST] == "" and accepted[SHELLS] == "False")
    values.nativeloader_ignore_outlines = "1" frames(5, 1 / 60)
    assert(accepted[LIST] == "0x3")
elseif scenario == "shells" then
    values.nativeloader_ignore_outline_shells = "1" frame()
    assert(accepted[SHELLS] == "True" and accepted[LIST] == "0x3")
    values.nativeloader_ignore_outlines = "0" frame()
    assert(accepted[SHELLS] == "True" and accepted[LIST] == "", "the two rules are separate")
    values.nativeloader_ignore_outline_shells = "0" frame()
    assert(accepted[SHELLS] == "False")
elseif scenario == "submaterial" then
    ent.sub[0] = "!custom/outline_shell" frames(10, 1 / 60)
    assert(accepted[LIST] == "0x3, 0x4" and not tracked["custom/outline_shell"], tostring(accepted[LIST]))
    ent.sub[0] = nil frames(10, 1 / 60)
    assert(accepted[LIST] == "0x3", "a removed sub-material's outline stayed hidden")
elseif scenario == "proxy" then
    assert(not tracked.pseudoplayermaterial_outline, "a procedural proxy was looked for on disk")
elseif scenario == "skin_change" then
    ent.skin = 1 frames(5, 1 / 60)
    assert(calls.materials == 2 and accepted[LIST] == "0x3")
elseif scenario == "retry" then
    -- Remix refuses the list three times: each refusal waits longer, never a write per frame.
    native["custom/outline_shell"] = {"0x4"}
    refuse[LIST] = 3
    ent.sub[0] = "!custom/outline_shell"
    local before = attempts(LIST)
    frame(1 / 60) frame(1 / 60)
    assert(attempts(LIST) == before + 1, "a refused write was retried at once")
    frames(50, 1 / 60) -- 0.83 s
    assert(attempts(LIST) == before + 1, "a refused write was retried before its delay")
    frames(20, 1 / 60) -- past 1 s
    assert(attempts(LIST) == before + 2)
    frames(100, 1 / 60) -- 1.7 s: the second delay is 2 s
    assert(attempts(LIST) == before + 2, "the delay did not grow after a second refusal")
    frames(30, 1 / 60)
    assert(attempts(LIST) == before + 3)
    frames(300, 1 / 60)
    assert(attempts(LIST) == before + 4 and accepted[LIST] == "0x3, 0x4", "the write never went through")
elseif scenario == "world" then
    assert(not tracked.white_outline and not tracked.black_outline, "map materials were treated as outlines")
elseif scenario == "bounded" then
    -- 2001 entities: each frame looks at a bounded share of them and of the names.
    local before = {model = calls.model, sub = calls.sub, hashes = calls.hashes}
    now = now + 0.2 -- past the revision poll and retry intervals
    revision = 2 -- every name is looked up again
    frame()
    assert(calls.model - before.model <= 300, "entities looked at in one frame: " .. (calls.model - before.model))
    assert(calls.sub - before.sub <= 300, "sub-materials read in one frame: " .. (calls.sub - before.sub))
    assert(calls.hashes - before.hashes <= 32, "hash lookups in one frame: " .. (calls.hashes - before.hashes))
    assert(calls.all == 1, "ents.GetAll() runs only in the occasional sweep")
    assert(accepted[LIST] == "0x3")
elseif scenario == "nil_revision" then
    -- No revision: resolved names are read again less and less often, not every frame.
    hashes = calls.hashes
    frames(1200, 1 / 60) -- 20 s
    assert(calls.hashes - hashes <= 4 * 8, "names re-read too often without a revision: " .. (calls.hashes - hashes))
    native["tex/model/hei"] = {"0x7"}
    frames(600, 1 / 60) -- 10 s: longer than the longest refresh delay
    assert(accepted[LIST] == "0x7", "a changed binding was never seen without a revision")
elseif scenario == "revision" then
    native["tex/model/hei"] = {"0x7"}
    frames(30, 1 / 60)
    assert(accepted[LIST] == "0x3", "hashes were re-read although the revision did not change")
    revision = 2 frames(10, 1 / 60)
    assert(accepted[LIST] == "0x7", "a revision change did not refresh the names")
elseif scenario == "prune" then
    local other = entity("models/other.mdl", {"tex/other/body", "tex/other/outline_shell"})
    native["tex/other/outline_shell"] = {"0x8"}
    engine[#engine + 1] = other
    hooks.OnEntityCreated(other) frames(10, 1 / 60)
    assert(accepted[LIST] == "0x3, 0x8")
    other.valid = false
    engine[#engine] = nil
    frames(10, 1 / 60)
    assert(accepted[LIST] == "0x3", "a removed model's outline stayed hidden")
    local seen = looked["tex/other/outline_shell"]
    revision = 3 frames(10, 1 / 60)
    assert(looked["tex/other/outline_shell"] == seen, "a removed model's names are still looked up")
    -- Turned off, removed entities are still dropped (every sweep interval), and nothing is looked up.
    values.nativeloader_ignore_outlines = "0" frame()
    for i = 1, 50 do
        local temp = entity("models/temp.mdl", {"tex/temp"})
        hooks.OnEntityCreated(temp)
        temp.valid = false
    end
    hashes = calls.hashes
    frames(700, 1 / 60)
    assert(calls.hashes == hashes, "hashes were looked up while suppression was off")
    local say, line = print, nil
    print = function(text) line = text end
    commands.nativeloader_model_layers_status()
    print = say
    assert(line:find("names=false, shells=false; 1 entities", 1, true), line)
end
assert(not tracked.pseudoplayermaterial_outline)
assert((tracked["tex/model/hei"] or 0) <= 1, "TrackMaterial was called again for a known name")
print("PASS " .. scenario)
