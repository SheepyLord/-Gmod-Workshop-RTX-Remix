-- R20-C: bounded client BloodImpact override. Ordinary Lua particles and engine decals, RTX or D3D9.
local BO = BloodOverhaul
local Budget = include("nativeloader/blood_budget.lua")
local enabled = CreateClientConVar("nativeloader_blood_impacts", "1", true, false)
local amount = CreateClientConVar("nativeloader_blood_amount", "1", true, false, "Blood impact amount", 0, 2)
local particles, stains, events = Budget.New(640, 512), Budget.New(48, 384), Budget.New(80, 80)
local active, materials = {}, {}
local stats = { impacts = 0, stock = 0, culled = 0, particles = 0, stains = 0, denied = 0 }
BO.ImpactStats = stats
BO.ImpactBudgets = { particles = particles, stains = stains, events = events }

local function finite(value, fallback, low, high)
    if type(value) ~= "number" or value ~= value or math.abs(value) == math.huge then return fallback end
    return math.Clamp(value, low, high)
end
function BO.ImpactPlan(scale, distance, quality)
    scale = finite(scale, 1, 0.25, 8)
    distance = finite(distance, 0, 0, 100000)
    quality = finite(quality, 1, 0, 2)
    if distance > 4096 or quality <= 0 then return 0, scale end
    local lod = distance > 2048 and 0.25 or (distance > 768 and 0.55 or 1)
    return math.Clamp(math.floor((12 + 6 * math.sqrt(scale)) * quality * lod + 0.5), 1, 42), scale
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
    if not tr.Hit or tr.HitSky or tr.StartSolid or not IsValid(tr.Entity) then return end
    local mat = BO.Pattern(code, index)
    if not mat or not stains:Take(CurTime(), math.huge) then return end
    local scale = size * finite(BO.ConVars.size:GetFloat(), 1, 0.25, 3) / BO.Shapes[index].units
    util.DecalEx(mat, tr.Entity, tr.HitPos, tr.HitNormal, color_white, scale, scale)
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
    local now, gain = CurTime(), math.sqrt(scale)
    for i = #active, 1, -1 do if active[i].expires <= now then table.remove(active, i) end end
    for i = 1, count do
        local mist = i % 5 == 0
        local forward = i % 3 ~= 0
        local lifetime = mist and math.Rand(0.10, 0.22) or math.Rand(0.5, 1.35)
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
            particle:SetAirResistance(mist and 160 or (size < 0.3 and 75 or 25))
            particle:SetGravity(Vector(0, 0, mist and -80 or -600))
            particle:SetCollide(not mist) particle:SetBounce(0)
            if not mist then
                local landed = false
                particle:SetCollideCallback(function(p, pos, normal)
                    if landed then return end
                    landed = true
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
