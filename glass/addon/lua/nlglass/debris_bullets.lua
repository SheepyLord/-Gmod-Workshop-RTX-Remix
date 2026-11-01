-- MIT. One server trace per accepted pellet; no client requests, predicted duplicates or piece stream.
NLGlass = NLGlass or {}
local B = { sent = 0, limited = 0, regions = {} }
NLGlass.Bullets = B
local NET = "nlglass_debris_ray"
local function finite(v)
    return isvector(v) and v.x == v.x and v.y == v.y and v.z == v.z and
        math.max(math.abs(v.x), math.abs(v.y), math.abs(v.z)) <= 131072
end
if CLIENT then
    net.Receive(NET, function()
        local from, to, damage = net.ReadVector(), net.ReadVector(), net.ReadFloat()
        if NLGlassDebris and NLGlassDebris.Ray then NLGlassDebris.Ray(from, to, damage) end
    end)
    return B
end
util.AddNetworkString(NET)
local cursor, tokens, scans, stamp, shots = 1, 32, 64, CurTime(), setmetatable({}, {__mode = "k"})
function B.Clear()
    B.regions, B.sent, B.limited, cursor = {}, 0, 0, 1
    tokens, scans, stamp, shots = 32, 64, CurTime(), setmetatable({}, {__mode = "k"})
end
function B.Mark(origin, radius)
    if not finite(origin) then return end
    local now = CurTime()
    for _, r in ipairs(B.regions) do
        if r.origin:DistToSqr(origin) < 128 * 128 then r.untilTime = now + 120;return end
    end
    B.regions[cursor] = {origin = Vector(origin.x, origin.y, origin.z), radius = math.max(768, math.min(2048, radius or 768)), untilTime = now + 120}
    cursor = cursor % 32 + 1
end
local function overlaps(from, delta, length2, r)
    local px, py, pz = r.origin.x - from.x, r.origin.y - from.y, r.origin.z - from.z
    local t = math.max(0, math.min(1, (px * delta.x + py * delta.y + pz * delta.z) / length2))
    local x, y, z = px - delta.x * t, py - delta.y * t, pz - delta.z * t
    return x * x + y * y + z * z <= r.radius * r.radius
end
hook.Add("PostEntityFireBullets", "NLGlass.DebrisBullets", function(entity, data)
    if #B.regions == 0 or not IsValid(entity) or type(data) ~= "table" or type(data.Trace) ~= "table" then return end
    local trace, now = data.Trace, CurTime()
    local from, to = trace.StartPos, trace.HitPos
    if not finite(from) or not finite(to) then return end
    local delta = to - from
    local length2 = delta:LengthSqr()
    if length2 < .001 or length2 > 131072 ^ 2 then return end
    -- Reject saturated weapons before scanning regions or allocating recipient filters.
    local elapsed = math.max(0, now - stamp);stamp = now
    tokens, scans = math.min(32, tokens + elapsed * 64), math.min(64, scans + elapsed * 256)
    if scans < 1 then B.limited = B.limited + 1;return end
    scans = scans - 1
    local shot = shots[entity] or {tokens = 8, stamp = now}
    shots[entity] = shot
    shot.tokens = math.min(8, shot.tokens + math.max(0, now - shot.stamp) * 16);shot.stamp = now
    if tokens < 1 or shot.tokens < 1 then B.limited = B.limited + 1;return end
    local recipients
    for _, r in ipairs(B.regions) do
        if r.untilTime > now and overlaps(from, delta, length2, r) then
            recipients = recipients or RecipientFilter();recipients:AddPVS(r.origin)
        end
    end
    if not recipients then return end
    local attacker = IsValid(data.Attacker) and data.Attacker or entity
    local damage = tonumber(data.Damage) or 0
    if damage <= 0 and game.GetAmmoID and game.GetAmmoPlayerDamage then
        local ammo = game.GetAmmoID(data.AmmoType or "")
        damage = (attacker:IsNPC() and game.GetAmmoNPCDamage and game.GetAmmoNPCDamage(ammo) or game.GetAmmoPlayerDamage(ammo)) or 0
    end
    if damage ~= damage or damage <= 0 then return end
    if attacker:IsPlayer() then recipients:AddPlayer(attacker) end
    tokens, shot.tokens, B.sent = tokens - 1, shot.tokens - 1, B.sent + 1
    net.Start(NET, true) net.WriteVector(from) net.WriteVector(to) net.WriteFloat(math.min(10000, damage)) net.Send(recipients)
    -- Returning nothing leaves the actual bullet and all other listeners unchanged.
end)
hook.Add("PreCleanupMap", "NLGlass.DebrisBullets", B.Clear)
return B
