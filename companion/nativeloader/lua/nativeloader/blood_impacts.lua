-- R20-C: bounded client BloodImpact override. Ordinary Lua particles and engine decals, RTX or D3D9.
local BO = BloodOverhaul
local Budget = include("nativeloader/blood_budget.lua")
local enabled = CreateClientConVar("nativeloader_blood_impacts", "1", true, false)
local amount = CreateClientConVar("nativeloader_blood_amount", "1", true, false, "Blood impact amount", 0, 2)
local particles, stains, events = Budget.New(640, 512), Budget.New(48, 384), Budget.New(80, 80)
local active, materials = {}, {}
local stats = { impacts = 0, stock = 0, culled = 0, particles = 0, stains = 0, denied = 0, landings = 0, trace_misses = 0 }
BO.ImpactStats = stats
BO.ImpactBudgets = { particles = particles, stains = stains, events = events }

local function finite(value, fallback, low, high)
    if type(value) ~= "number" or value ~= value or math.abs(value) == math.huge then return fallback end
    return math.Clamp(value, low, high)
end
function BO.ImpactPlan(scale, distance, quality)
    -- Stock UTIL_BloodImpact carries blood amount (up to 255), not a 0..1 size multiplier.
    -- A soft square-root response keeps pistol/rifle/pellet amounts distinct, also in multiplayer.
    scale = math.Clamp(math.sqrt(finite(scale, 12, 0.5, 255) / 12), 0.4, 2.8)
    distance = finite(distance, 0, 0, 100000)
    quality = finite(quality, 1, 0, 2)
    if distance > 4096 or quality <= 0 then return 0, scale end
    local lod = distance > 2048 and 0.25 or (distance > 768 and 0.55 or 1)
    return math.Clamp(math.floor((12 + 8 * scale) * quality * lod + 0.5), 1, 42), scale
end

local function material(code, index, mist)
    local family = BO.Family(code)
    local key = family .. "_" .. index .. (mist and "_mist" or "_drop")
    if not materials[key] then
        local mat = CreateMaterial("nlfluid_" .. key, "UnlitGeneric", {
            ["$basetexture"] = "particle/nlfluid/" .. (mist and "mist" or "drop"),
            ["$translucent"] = "1", ["$vertexcolor"] = "1", ["$vertexalpha"] = "1",
        })
        materials[key] = { mat = mat, code = code, index = index }
    end
    local entry = materials[key]
    local col = BO.ConVars.droplets:GetBool() and BO.Colour(code, index) or BO.StockColour(code)
    entry.mat:SetVector("$color", Vector(col.r / 255, col.g / 255, col.b / 255))
    return entry.mat
end
BO.ParticleMaterial = material
hook.Add("NativeLoaderBloodColoursChanged", "nativeloader_blood", function()
    for _, entry in pairs(materials) do
        local col = BO.ConVars.droplets:GetBool() and BO.Colour(entry.code, entry.index) or BO.StockColour(entry.code)
        entry.mat:SetVector("$color", Vector(col.r / 255, col.g / 255, col.b / 255))
    end
end)
local function clear_particles()
    local now = CurTime()
    for _, entry in ipairs(active) do
        if entry.expires > now then pcall(entry.particle.SetDieTime, entry.particle, 0) end
    end
    active = {}
end
for _, name in ipairs({ "nativeloader_blood_impacts", "bloodoverhaul_enable", "nativeloader_blood_amount" }) do
    cvars.AddChangeCallback(name, function()
        if not enabled:GetBool() or not BO.ConVars.enable:GetBool() or amount:GetFloat() <= 0 then clear_particles() end
    end, "nativeloader_blood_impacts")
end
local function reset()
    clear_particles()
    particles:Reset() stains:Reset() events:Reset()
end
hook.Add("PostCleanupMap", "nativeloader_blood", reset)
concommand.Add("bloodoverhaul_clear", function()
    RunConsoleCommand("r_cleardecals")
    reset()
end)
concommand.Add("nativeloader_blood_status", function()
    particles:Prune(CurTime())
    print(string.format("[nlblood] impacts=%d stock=%d culled=%d particles=%d live<=%d/512 recent=%d/640 stains=%d/384 denied=%d",
        stats.impacts, stats.stock, stats.culled, stats.particles, #particles.live, #particles.recent,
        stains.total, stats.denied))
end)

local function stamp(code, index, size, position, normal)
    if not enabled:GetBool() or not BO.ConVars.enable:GetBool() or amount:GetFloat() <= 0 then return end
    stains:Prune(CurTime())
    if #stains.recent >= stains.rate or stains.total >= stains.maximum then return end
    local tr = util.TraceLine({ start = position + normal * 2, endpos = position - normal * 3, mask = MASK_SOLID })
    if not tr.Hit or tr.HitSky or tr.StartSolid or (not tr.HitWorld and not IsValid(tr.Entity)) then
        stats.trace_misses = stats.trace_misses + 1
        return
    end
    local mat = BO.Pattern(code, index)
    if not mat or not stains:Take(CurTime(), math.huge) then return end
    local scale = size * finite(BO.ConVars.size:GetFloat(), 1, 0.25, 3) / BO.Shapes[index].units
    util.DecalEx(mat, tr.HitWorld and game.GetWorld() or tr.Entity, tr.HitPos, tr.HitNormal, color_white, scale, scale)
    stats.stains = stats.stains + 1
end

local EFFECT = {}
function EFFECT:Init(data)
    local code = data:GetColor()
    if not enabled:GetBool() or not BO.ConVars.enable:GetBool() or amount:GetFloat() <= 0 or not BO.Family(code) then
        stats.stock = stats.stock + 1
        util.Effect("BloodImpact", data, false)
        return
    end
    local origin = data:GetOrigin()
    stats.last_colour, stats.last_scale = code, data:GetScale()
    local count, scale = BO.ImpactPlan(data:GetScale(), EyePos():Distance(origin), amount:GetFloat())
    stats.impacts = stats.impacts + 1
    if count == 0 or not events:Take(CurTime(), 0) then stats.culled = stats.culled + 1 return end
    local emitter = ParticleEmitter(origin)
    if not emitter then
        stats.stock = stats.stock + 1
        util.Effect("BloodImpact", data, false)
        return
    end
    local direction = data:GetNormal():GetNormalized()
    -- A zero direction gives no shooter information. Use a neutral upward spray, never EyePos.
    if direction:LengthSqr() < 0.1 then direction = Vector(0, 0, 1) end
    local now, gain = CurTime(), scale
    for i = #active, 1, -1 do if active[i].expires <= now then table.remove(active, i) end end
    for i = 1, count do
        local mist = i % 5 == 0
        local forward = not mist and i % 3 ~= 0
        local lifetime = mist and math.Rand(0.10, 0.22) or math.Rand(0.75, 1.8)
        if not particles:Take(now, lifetime) then stats.denied = stats.denied + 1 break end
        local index = BO.ConVars.variety:GetBool() and math.random(#BO.Shapes) or 1
        local particle = emitter:Add(material(code, index, mist), origin + direction * (forward and 1.5 or -1.5))
        if particle then
            local spread = forward and 0.42 or 0.85
            local axis = (direction * (forward and 1 or -1) + VectorRand() * spread):GetNormalized()
            local speed = math.Rand(forward and 160 or 80, forward and 460 or 240) * gain
            local size = mist and math.Rand(1.1, 2.4) or (i % 7 == 0 and math.Rand(0.65, 1) or math.Rand(0.12, 0.48))
            particle:SetVelocity(axis * speed)
            particle:SetLifeTime(0) particle:SetDieTime(lifetime)
            particle:SetStartAlpha(mist and 40 or 235) particle:SetEndAlpha(0)
            particle:SetStartSize(size) particle:SetEndSize(mist and size * 2.8 or size * 0.65)
            particle:SetRoll(math.Rand(0, 360)) particle:SetRollDelta(math.Rand(-1, 1))
            particle:SetColor(255, 255, 255)
            particle:SetLighting(true)
            -- Larger drops retain more momentum; fine mist dissipates near the entrance.
            particle:SetAirResistance(mist and 20 or (size < 0.3 and 3.5 or 0.9))
            particle:SetGravity(Vector(0, 0, mist and -80 or -600))
            particle:SetCollide(not mist) particle:SetBounce(0)
            if not mist then
                local landed = false
                particle:SetCollideCallback(function(p, pos, normal)
                    if landed then return end
                    landed = true
                    stats.landings = stats.landings + 1
                    p:SetDieTime(0)
                    stamp(code, index, math.Clamp(size * math.Rand(3, 6), 0.5, 5), pos, normal)
                end)
            end
            active[#active + 1] = { particle = particle, expires = now + lifetime }
            stats.particles = stats.particles + 1
        end
    end
    emitter:Finish()
end
function EFFECT:Think() return false end
function EFFECT:Render() end
effects.Register(EFFECT, "BloodImpact")

-- Server ragdolls send Impact rather than BloodImpact. Client ragdolls can instead be intersected
-- by a world Impact/RagdollImpact ray. Observe those existing dispatches, keeping native physics,
-- sounds, decals and any previously registered Lua effect. There is no new server hook or message.
local ragdoll_colours, ragdolls = setmetatable({}, {__mode = "k"}), setmetatable({}, {__mode = "k"})
local ragdoll_checks, recent_hits = Budget.New(160, 160), {}
local function is_ragdoll(ent)
    return IsValid(ent) and ((ent.IsRagdoll and ent:IsRagdoll()) or ent:GetClass() == "prop_ragdoll")
end
local function remember(ent)
    if is_ragdoll(ent) then ragdolls[ent] = true end
end
hook.Add("OnEntityCreated", "nativeloader_blood_ragdolls", function(ent) timer.Simple(0, function() remember(ent) end) end)
hook.Add("InitPostEntity", "nativeloader_blood_ragdolls", function() for _, ent in ipairs(ents.GetAll()) do remember(ent) end end)
hook.Add("CreateClientsideRagdoll", "nativeloader_blood_ragdolls", function(source, ragdoll)
    remember(ragdoll)
    if IsValid(source) and source.GetBloodColor then ragdoll_colours[ragdoll] = source:GetBloodColor() end
end)
local SURFACE_COLOUR = { [70] = 0, [66] = 0, [72] = 1, [65] = 4 } -- MAT_FLESH/BLOODYFLESH/ALIENFLESH/ANTLION
local function ragdoll_impact(name, data)
    if not enabled:GetBool() or not BO.ConVars.enable:GetBool() or amount:GetFloat() <= 0 then return end
    if bit.band(data:GetDamageType(), 536870914) == 0 then return end -- DMG_BULLET | DMG_BUCKSHOT
    local ent, pos, start = data:GetEntity(), data:GetOrigin(), data:GetStart()
    local direct = is_ragdoll(ent)
    if not direct and IsValid(ent) and not ent:IsWorld() then return end -- living NPC/player has BloodImpact already
    if not direct and not next(ragdolls) then return end
    if not ragdoll_checks:Take(CurTime(), 0) then return end
    local direction = (pos - start):GetNormalized()
    if direction:LengthSqr() < 0.1 then return end
    local surface = util.GetSurfaceData(data:GetSurfaceProp())
    local kind = surface and surface.material
    if not direct then
        -- Ignore living actors along the engine's ragdoll-only ray, including its shooter.
        local tr = util.TraceLine({ start = start, endpos = pos + direction * 4, mask = MASK_SHOT,
            hitclientonly = true, filter = function(e) return not e:IsPlayer() and not e:IsNPC() end })
        if not tr.Hit or not is_ragdoll(tr.Entity) then return end
        ent, pos, kind = tr.Entity, tr.HitPos, tr.MatType
    end
    local code = ragdoll_colours[ent]
    if code == nil and ent.GetBloodColor then code = ent:GetBloodColor() end
    if code == nil then code = SURFACE_COLOUR[kind] end
    if not BO.Family(code) then return end -- metal, mechanical and explicitly bloodless bodies stay dry
    local now = CurTime()
    for i = #recent_hits, 1, -1 do
        local old = recent_hits[i]
        if old.time < now - 0.05 then table.remove(recent_hits, i)
        elseif old.entity == ent and old.name ~= name and (old.pos - pos):LengthSqr() < 4 then return end
    end
    if #recent_hits >= 64 then table.remove(recent_hits, 1) end
    recent_hits[#recent_hits + 1] = { entity = ent, pos = pos, time = now, name = name }
    local fluid = EffectData()
    fluid:SetOrigin(pos) fluid:SetNormal(direction) fluid:SetColor(code)
    -- Impact has no blood amount: retain a useful explicit scale, otherwise use a modest default.
    fluid:SetScale(data:GetScale() > 1 and data:GetScale() or 12)
    stats.ragdoll_impacts = (stats.ragdoll_impacts or 0) + 1
    EFFECT.Init({}, fluid)
end
for _, name in ipairs({ "Impact", "Impact_GMOD", "RagdollImpact" }) do
    local effect_name = name
    local previous = effects.Create and effects.Create(name)
    if previous and previous.NativeLoaderBloodAdapter then previous = previous.NativeLoaderBloodPrevious end
    effects.Register({
        NativeLoaderBloodAdapter = true, NativeLoaderBloodPrevious = previous,
        Init = function(self, data)
            if previous then
                for key, value in pairs(previous) do
                    if key ~= "Init" and key ~= "Think" and key ~= "Render" then self[key] = value end
                end
                if previous.Init then previous.Init(self, data) end
            else
                util.Effect(effect_name, data, false)
            end
            ragdoll_impact(effect_name, data)
        end,
        Think = function(self) return previous and previous.Think and previous.Think(self) or false end,
        Render = function(self) if previous and previous.Render then return previous.Render(self) end end,
    }, name)
end
BO.RagdollImpacts = true
