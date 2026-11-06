-- Observe ordinary Source effects; publish only transient Remix categories (ADR 0121).
if not CLIENT or not NativeLoaderRenderGuard then return end
if NativeLoaderEffectCategories then return end
local LIMIT, WORK, TTL = 4096, 12, 120
local names, list, cursor, bound = {}, {}, 1, nil
local sent, retry, delay = {}, {}, {}
local nextScan, nextWrite, cache, cacheIndex = 0, 0, nil, 1
local options = {
    particle = "rtx.gmod.particleTexturesForSession",
    decal = "rtx.gmod.decalTexturesForSession",
    color = "rtx.gmod.legacyEffectTexturesForSession"
}
local function nameOf(value)
    if type(value) ~= "string" then
        if not value or not value.GetName then return end
        value = value:GetName()
    end
    if type(value) ~= "string" or #value > 260 or value:find("%z") then return end
    value = value:lower():gsub("\\", "/"):gsub("^!", ""):gsub("%.vmt$", "")
    if value == "" then return end
    return value
end
local function observe(value, kind)
    local name = nameOf(value)
    if not name then return end
    local state = names[name]
    if not state then
        if #list >= LIMIT then return end
        state = {name = name, due = 0, seen = RealTime()}
        names[name], list[#list + 1] = state, state
    end
    state.seen = RealTime()
    if kind and not state[kind] then state[kind], state.due = true, 0 end
end
-- These functions preserve the engine's arguments, object identity, errors and returns.
local emitter = FindMetaTable("CLuaEmitter")
if emitter and emitter.Add then
    local original = emitter.Add
    emitter.Add = function(self, material, ...)
        local result = original(self, material, ...)
        if result ~= nil then observe(material, "particle") end
        return result
    end
end
local particle = FindMetaTable("CLuaParticle")
if particle and particle.SetMaterial then
    local original = particle.SetMaterial
    particle.SetMaterial = function(self, material, ...)
        observe(material, "particle")
        return original(self, material, ...)
    end
end
if util.DecalEx then
    local original = util.DecalEx
    util.DecalEx = function(material, ...)
        observe(material, "decal")
        return original(material, ...)
    end
end
if util.Decal and util.DecalMaterial then
    local original, resolve = util.Decal, util.DecalMaterial
    util.Decal = function(decal, ...)
        if type(decal) == "string" then observe(resolve(decal), "decal") end
        return original(decal, ...)
    end
end
if render.SetMaterial then
    local original = render.SetMaterial
    render.SetMaterial = function(material, ...)
        bound = material
        return original(material, ...)
    end
end
for _, api in ipairs({"DrawSprite", "DrawBeam", "StartBeam"}) do
    local original = render[api]
    if original then
        render[api] = function(...)
            observe(bound, "particle")
            return original(...)
        end
    end
end

local function flag(mat, key) return (mat:GetInt(key) or 0) ~= 0 end
local function hashList(values)
    local hashes = {}
    for _, hash in ipairs(values or {}) do
        local digits = type(hash) == "string" and hash:match("^0[xX](%x+)$")
        if digits and #digits <= 16 then
            digits = digits:lower():gsub("^0+", "")
            if digits ~= "" then hashes["0x" .. string.rep("0", 16 - #digits) .. digits] = true end
        end
    end
    return hashes
end
local function lookup(state, now)
    -- Hash queries read only the existing draw cache. Never load undrawn materials or characters.
    local hashes = hashList(RemixMaterial.GetAllTextureHashes(state.name))
    state.hashes, state.kinds = nil, nil
    if not next(hashes) then state.due = now + 0.5 return end
    local mat = Material(state.name)
    -- Generated materials may require a ! reference; both lookups are now warm.
    if not mat or mat:IsError() then mat = Material("!" .. state.name) end
    if not mat or mat:IsError() then state.due = now + 1 return end
    local tex = mat:GetTexture("$basetexture")
    if not tex or tex:IsError() then state.due = now + 1 return end
    local texture = tex:GetName():lower():gsub("\\", "/")
    -- Texture categories affect every draw sharing a hash, including shared engine fallback colors.
    if texture == "vgui/white" or texture == "color/white" or texture == "dev/white" or
        texture:find("error", 1, true) or texture == "_rt_fullframefb" then
        state.due = now + 8 return
    end
    local shader = (mat:GetShader() or ""):lower()
    local decal = state.decal or flag(mat, "$decal") or shader == "decalmodulate"
    local sprite = shader == "sprite" or shader == "spritecard"
    local color = shader == "unlitgeneric" and flag(mat, "$vertexcolor") and flag(mat, "$vertexalpha") and
        (flag(mat, "$translucent") or flag(mat, "$additive"))
    local kinds = {decal = decal, particle = not decal and (state.particle or sprite), color = color}
    if decal or kinds.particle or color then state.hashes, state.kinds = hashes, kinds end
    state.irrelevant = not (decal or kinds.particle or color)
    state.due = now + 2
end
local function sync()
    if not RemixConfig or not RemixConfig.SetConfigVariable or not RemixMaterial or
        not RemixMaterial.GetAllTextureHashes or not RemixMaterial.GetCachedMaterials then return end
    local now = RealTime()
    if not cache and now >= nextScan then
        cache, cacheIndex, nextScan = RemixMaterial.GetCachedMaterials() or {}, 1, now + 2
    end
    if cache then
        for _ = 1, WORK do
            local value = cache[cacheIndex]
            if value == nil then cache = nil break end
            cacheIndex = cacheIndex + 1
            observe(value)
        end
    end
    for _ = 1, math.min(WORK, #list) do
        if cursor > #list then cursor = 1 end
        local state = list[cursor]
        if now - state.seen > TTL then
            names[state.name], list[cursor] = nil, list[#list]
            list[#list] = nil
        else
            if now >= state.due then lookup(state, now) end
            if state.irrelevant and not state.particle and not state.decal then
                names[state.name], list[cursor] = nil, list[#list]
                list[#list] = nil
            else cursor = cursor + 1 end
        end
    end
    if now < nextWrite then return end
    nextWrite = now + 0.25
    local sets = {particle = {}, decal = {}, color = {}}
    for _, state in ipairs(list) do
        if state.hashes then
            for kind, enabled in pairs(state.kinds) do
                if enabled then for hash in pairs(state.hashes) do sets[kind][hash] = true end end
            end
        end
    end
    for kind, set in pairs(sets) do
        local values = {}
        for hash in pairs(set) do values[#values + 1] = hash end
        table.sort(values)
        local value = table.concat(values, ", ")
        if sent[kind] ~= value and now >= (retry[kind] or 0) then
            if RemixConfig.SetConfigVariable(options[kind], value) then
                sent[kind], retry[kind], delay[kind] = value, 0, 1
            else
                delay[kind] = math.min((delay[kind] or 0.5) * 2, 60)
                retry[kind] = now + delay[kind]
            end
        end
    end
end
NativeLoaderEffectCategories = {Status = function()
    print("[nativeloader] Effect categories: " .. #list .. " observed materials")
    for kind, option in pairs(options) do print(option .. "=" .. (sent[kind] or "pending")) end
    return #list
end}
hook.Add("Think", "nativeloader_effect_categories", sync)
