-- MIT. Server-observed hits; clients advertise bounded live-piece interest, never damage.
NLGlass = NLGlass or {}
local B = { sent = 0, limited = 0, regions = {}, clients = setmetatable({}, {__mode = "k"}) }
NLGlass.Bullets = B
local NET, INTEREST = "nlglass_debris_hit", "nlglass_debris_interest"
local function numbers(v)
    if not isvector(v) then return end
    local x, y, z = v.x, v.y, v.z
    if x == x and y == y and z == z and math.max(math.abs(x), math.abs(y), math.abs(z)) <= 131072 then return x, y, z end
end
if CLIENT then
    local nextSend, active = 0, false
    net.Receive(NET, function()
        local from, to, damage = net.ReadVector(), net.ReadVector(), net.ReadFloat()
        local radius = net.ReadUInt(5)
        if NLGlassDebris and NLGlassDebris.Ray then NLGlassDebris.Ray(from, to, damage, radius) end
    end)
    function B.Update(api, wanted)
        local now = CurTime()
        if now < nextSend and wanted == active then return end
        if not wanted and not active then return end
        local regions = wanted and api.ReadRegions(EyePos and EyePos() or vector_origin) or {}
        if type(regions) ~= "table" then return end
        active, nextSend = wanted, now + 2
        net.Start(INTEREST)
        net.WriteUInt(math.min(32, #regions), 6)
        for i = 1, math.min(32, #regions) do
            local lo, hi = regions[i][1], regions[i][2]
            net.WriteVector(Vector((lo[1]+hi[1])*.5, (lo[2]+hi[2])*.5, (lo[3]+hi[3])*.5))
            net.WriteFloat(math.min(2048, math.sqrt((hi[1]-lo[1])^2+(hi[2]-lo[2])^2+(hi[3]-lo[3])^2)*.5 + 32))
        end
        net.SendToServer()
    end
    return B
end
util.AddNetworkString(NET);util.AddNetworkString(INTEREST)
local cursor, tokens, scans, stamp, shots = 1, 32, 64, CurTime(), setmetatable({}, {__mode = "k"})
local nextLeaseSweep, leases = 0, 0
function B.Clear()
    B.regions, B.sent, B.limited, cursor = {}, 0, 0, 1
    B.clients, leases, nextLeaseSweep = setmetatable({}, {__mode = "k"}), 0, 0
    tokens, scans, stamp, shots = 32, 64, CurTime(), setmetatable({}, {__mode = "k"})
end
net.Receive(INTEREST, function(bits, ply)
    local now = CurTime()
    if not IsValid(ply) or not ply:IsPlayer() or bits < 6 or bits > 4200 then return end
    local old = B.clients[ply]
    if old and now < old.nextUpdate then B.limited = B.limited + 1;return end
    if not old then
        local retained=0;for _ in pairs(B.clients) do retained=retained+1 end
        if retained>=128 then return end
    end
    local count = net.ReadUInt(6)
    if count > 32 or bits < 6 + count * 128 then return end
    local regions = {}
    for i = 1, count do
        local x,y,z = numbers(net.ReadVector());local radius = net.ReadFloat()
        if not x or radius ~= radius or radius < 1 or radius > 2048 then return end
        regions[i] = {x,y,z,radius*radius}
    end
    B.clients[ply] = {regions = regions, untilTime = now + 6, nextUpdate = now + 1}
    nextLeaseSweep = 0
end)
-- Brief start-up bridge before a new client's first interest update. Never a lifetime authority.
function B.Mark(origin, radius)
    local x,y,z = numbers(origin);if not x then return end
    B.regions[cursor] = {x,y,z,math.max(768,math.min(2048,radius or 768))^2, untilTime = CurTime()+2, origin = origin}
    cursor = cursor % 32 + 1
end
function B.HasInterest()
    local now = CurTime()
    if now >= nextLeaseSweep then
        leases, nextLeaseSweep = 0, now + .25
        for ply,c in pairs(B.clients) do
            if not IsValid(ply) or c.untilTime <= now then B.clients[ply] = nil
            elseif #c.regions > 0 then leases = leases + 1 end
        end
    end
    if leases > 0 then return true end
    for _,r in ipairs(B.regions) do if r.untilTime > now then return true end end
    return false
end
local function overlaps(x,y,z,dx,dy,dz,length2,r)
    local px,py,pz = r[1]-x,r[2]-y,r[3]-z
    local t = math.max(0,math.min(1,(px*dx+py*dy+pz*dz)/length2))
    px,py,pz = px-dx*t,py-dy*t,pz-dz*t
    return px*px+py*py+pz*pz <= r[4]
end
function B.Forward(entity, from, to, damage, radius, attacker)
    if not IsValid(entity) or not B.HasInterest() then return end
    local x,y,z = numbers(from);local tx,ty,tz = numbers(to)
    if not x or not tx then return end
    local dx,dy,dz = tx-x,ty-y,tz-z
    local length2 = dx*dx+dy*dy+dz*dz
    radius=tonumber(radius) or 0
    if radius~=radius or radius<0 or radius>16 then return end
    if length2 < .001 or length2 > 131072^2 or not isnumber(damage) or damage ~= damage or damage <= 0 then return end
    local now = CurTime();local elapsed = math.max(0,now-stamp);stamp = now
    tokens,scans = math.min(32,tokens+elapsed*64),math.min(64,scans+elapsed*256)
    if scans < 1 then B.limited=B.limited+1;return end
    scans = scans-1
    local shot = shots[entity] or {tokens=8,stamp=now};shots[entity]=shot
    shot.tokens=math.min(8,shot.tokens+math.max(0,now-shot.stamp)*16);shot.stamp=now
    if tokens < 1 or shot.tokens < 1 then B.limited=B.limited+1;return end
    local recipients, found = RecipientFilter(), false
    for ply,c in pairs(B.clients) do
        if IsValid(ply) and c.untilTime > now then
            for _,r in ipairs(c.regions) do
                if overlaps(x,y,z,dx,dy,dz,length2,r) then recipients:AddPlayer(ply);found=true;break end
            end
        end
    end
    for _,r in ipairs(B.regions) do
        if r.untilTime > now and overlaps(x,y,z,dx,dy,dz,length2,r) then recipients:AddPVS(r.origin);found=true end
    end
    if not found then return end
    if IsValid(attacker) and attacker:IsPlayer() then recipients:AddPlayer(attacker) end
    tokens,shot.tokens,B.sent=tokens-1,shot.tokens-1,B.sent+1
    net.Start(NET,true);net.WriteVector(from);net.WriteVector(to);net.WriteFloat(math.min(10000,damage))
    net.WriteUInt(math.max(0,math.min(16,radius or 0)),5);net.Send(recipients)
    return true
end
hook.Add("PostEntityFireBullets", "NLGlass.DebrisBullets", function(entity, data)
    if not IsValid(entity) or type(data) ~= "table" or type(data.Trace) ~= "table" then return end
    local attacker = IsValid(data.Attacker) and data.Attacker or entity
    local damage = tonumber(data.Damage) or 0
    if damage <= 0 and game.GetAmmoID and game.GetAmmoPlayerDamage then
        local ammo = game.GetAmmoID(data.AmmoType or "")
        damage = (attacker:IsNPC() and game.GetAmmoNPCDamage and game.GetAmmoNPCDamage(ammo) or game.GetAmmoPlayerDamage(ammo)) or 0
    end
    B.Forward(entity,data.Trace.StartPos,data.Trace.HitPos,damage,0,attacker)
    -- Do not return a value: other listeners and the actual pellet remain untouched.
end)
hook.Add("PreCleanupMap", "NLGlass.DebrisBullets", B.Clear)
return B
