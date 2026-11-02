-- MIT. Observe exact Lua blasts, native explosion inputs and native grenade sounds. Never
-- change damage, sound tables, hook returns or Source physics. Duplicate observations coalesce.
if not SERVER then return end
local S=NLGlass.Server
local previous=NLGlass.Blasts
if previous and previous.Restore then previous.Restore() end
local B={sent=0,deduplicated=0,limited=0,pending=0,tokens=16,stamp=CurTime(),recent={}}
NLGlass.Blasts=B
local function finite(v) return type(v)=="number" and v==v and math.abs(v)<=131072 end
local function enqueue(origin,radius,damage,source)
    if not origin or not finite(origin.x) or not finite(origin.y) or not finite(origin.z) or
        not finite(radius) or radius<=0 or not finite(damage) or damage<=0 then return end
    local now=CurTime()
    B.tokens=math.min(16,B.tokens+math.max(0,now-B.stamp)*32);B.stamp=now
    for i=#B.recent,1,-1 do
        local e=B.recent[i]
        if now-e.time>.1 then table.remove(B.recent,i)
        elseif (origin-e.origin):LengthSqr()<32^2 then
            -- Exact API radius/damage replaces an attenuated victim observation before send.
            e.radius=math.min(2048,math.max(e.radius,radius));e.damage=math.max(e.damage,damage)
            B.deduplicated=B.deduplicated+1;return
        end
    end
    if B.tokens<1 or B.pending>=32 then B.limited=B.limited+1;return end
    B.tokens=B.tokens-1
    local e={origin=Vector(origin.x,origin.y,origin.z),radius=math.Clamp(radius,1,2048),damage=damage,time=now,source=source}
    if #B.recent>=32 then table.remove(B.recent,1) end
    B.recent[#B.recent+1]=e;B.pending=B.pending+1
    local epoch=S.epoch
    -- Damage/OnBreak callbacks may schedule glass. Keep their ordering; the ballistic preview
    -- and deferred queue both retain blasts received while body construction is pending.
    timer.Simple(0,function() timer.Simple(0,function()
        B.pending=B.pending-1
        if S.epoch~=epoch then return end
        net.Start("nlglass_blast");net.WriteVector(e.origin);net.WriteFloat(e.radius)
        net.WriteFloat(math.Clamp(e.damage*10,180,1800));net.Broadcast();B.sent=B.sent+1
        if B.Observe then B.Observe(e) end
    end) end)
end
B.Emit=enqueue
function S.Blast(dmg)
    local inflictor=dmg:GetInflictor()
    -- ReportedPosition is the thrower's position for CBaseGrenade, not the explosion.
    local origin=IsValid(inflictor) and inflictor:WorldSpaceCenter() or dmg:GetDamagePosition()
    enqueue(origin,math.Clamp(dmg:GetDamage()*4,64,2048),dmg:GetDamage(),"damage")
end
local original,wrapped={},{}
local function wrap(name,observe)
    local fn=util[name]
    if type(fn)~="function" then return end
    original[name]=fn
    wrapped[name]=function(...)
        -- Cosmetic observation failure must never interfere with the caller's damage.
        local ok,err=pcall(observe,...)
        if not ok then ErrorNoHalt("[NLGlass] blast observation: "..tostring(err).."\n") end
        return fn(...)
    end
    util[name]=wrapped[name]
end
wrap("BlastDamage",function(_,_,pos,radius,damage) enqueue(pos,radius,damage,"util.BlastDamage") end)
wrap("BlastDamageInfo",function(info,pos,radius) enqueue(pos,radius,info:GetDamage(),"util.BlastDamageInfo") end)
function B.Restore() for name,fn in pairs(original) do if util[name]==wrapped[name] then util[name]=fn end end end
hook.Add("AcceptInput","NLGlass.BlastInput",function(ent,input)
    local class=ent:GetClass()
    if string.lower(input)~="explode" or (class~="env_explosion" and class~="env_physexplosion") then return end
    local keys=ent:GetKeyValues() or {}
    local damage=tonumber(keys.iMagnitude or keys.imagnitude or keys.magnitude) or 100
    local radius=tonumber(keys.iRadiusOverride or keys.iradiusoverride or keys.radius) or damage*2.5
    enqueue(ent:GetPos(),radius>0 and radius or damage*2.5,damage,"input:"..class)
end)
hook.Add("EntityEmitSound","NLGlass.BlastSound",function(data)
    if data.OriginalSoundName~="BaseGrenade.Explode" and data.SoundName~="BaseGrenade.Explode" then return end
    local ent=data.Entity
    if not IsValid(ent) then return end
    local damage=ent.GetInternalVariable and ent:GetInternalVariable("m_flDamage") or 100
    local radius=ent.GetInternalVariable and ent:GetInternalVariable("m_DmgRadius") or 250
    enqueue(ent:GetPos(),tonumber(radius) or 250,tonumber(damage) or 100,"native-grenade")
end)
-- GMod's input hook observes native ExplosionCreate too: PoC barrels and RPGs both
-- reached the env_explosion route with zero damage victims. No entity polling is needed.
return B
