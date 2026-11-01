-- MIT. Read-only stock swing observations and actual short SWEP traces, including misses.
if CLIENT then return end
local previous = NLGlass.Melee
if previous and previous.Stop then previous.Stop() end
local M = { sent = 0, observed = 0, active = true }
NLGlass.Melee = M
local B = NLGlass.Bullets
local states = setmetatable({}, {__mode = "k"})
local traceLine, traceHull = util.TraceLine, util.TraceHull
local stock = {weapon_crowbar = 25, weapon_stunstick = 40}
local holds = {melee = true, melee2 = true, knife = true, fist = true}
local function weapon(ply)
    if not IsValid(ply) or not ply:IsPlayer() or not ply:Alive() then return end
    local w = ply:GetActiveWeapon()
    if not IsValid(w) then return end
    local primary = type(w.Primary) == "table" and w.Primary or {}
    if stock[w:GetClass()] or (w.GetHoldType and holds[w:GetHoldType()]) or primary.Melee then return w,primary end
end
local function send(ply,w,from,to,radius)
    local state = states[ply]
    if not state or state.weapon ~= w or state.sentUntil > CurTime() then return end
    local primary = type(w.Primary) == "table" and w.Primary or {}
    local hitDamage = type(w.HitDamage)=="table" and ((tonumber(w.HitDamage[1]) or 0)+(tonumber(w.HitDamage[2]) or 0))*.5 or tonumber(w.HitDamage)
    local damage = stock[w:GetClass()] or tonumber(primary.Damage) or hitDamage or 25
    if B.Forward(ply,from,to,damage,math.max(1,math.min(16,math.ceil(radius or 6))),ply) then
        state.sentUntil = CurTime()+.1;M.sent=M.sent+1
    end
end
local function stockSwing(ply,w)
    if not traceLine then return end
    local from = ply:GetShootPos()
    local trace = traceLine({start=from,endpos=from+ply:GetAimVector()*75,filter=ply,mask=MASK_SHOT_HULL})
    if type(trace) == "table" and isvector(trace.HitPos) and not trace.StartSolid and not trace.AllSolid then send(ply,w,from,trace.HitPos,6) end
end
-- Stock C++ melee does not call Lua's util.Trace*. A successful cooldown advance after a ready
-- attack command is the server-side observation; animation supplies an earlier observation too.
hook.Add("StartCommand", "NLGlass.DebrisMelee", function(ply,cmd)
    if not M.active or not B.HasInterest() then return end
    local w = weapon(ply);if not w then states[ply]=nil;return end
    local now,nextFire = CurTime(),w:GetNextPrimaryFire()
    local attacking=cmd:KeyDown(IN_ATTACK) or (ply.KeyDown and ply:KeyDown(IN_ATTACK))
    local state = states[ply]
    if not state or state.weapon ~= w or now-state.seen > 1 then
        state={weapon=w,nextFire=nextFire,sentUntil=0};states[ply]=state
    elseif stock[w:GetClass()] and (state.armed or attacking) and state.nextFire<=now and nextFire > state.nextFire+.00001 then stockSwing(ply,w) end
    state.armed = attacking and nextFire <= now
    state.untilTime = (attacking or cmd:KeyDown(IN_ATTACK2)) and now+.6 or state.untilTime or 0
    state.nextFire,state.seen = nextFire,now
end)
hook.Add("DoAnimationEvent", "NLGlass.DebrisMelee", function(ply,event)
    if not M.active or not B.HasInterest() or (event ~= PLAYERANIMEVENT_ATTACK_PRIMARY and event ~= PLAYERANIMEVENT_ATTACK_SECONDARY) then return end
    local w = weapon(ply);if not w then return end
    local s=states[ply]
    if not s or s.weapon~=w then s={weapon=w,sentUntil=0};states[ply]=s end
    s.untilTime,s.seen=CurTime()+.6,CurTime()
    if stock[w:GetClass()] then stockSwing(ply,w) end
    -- Never return an animation override.
end)
local function observe(data,result)
    if not M.active or not B.HasInterest() or type(data)~="table" or type(result)~="table" or result.StartSolid or result.AllSolid or
        not isvector(data.start) or not isvector(result.HitPos) or not isvector(data.endpos) then return end
    local delta=data.endpos-data.start
    if delta:LengthSqr()<1 or delta:LengthSqr()>160^2 then return end
    local filter=data.filter;local ply
    if IsValid(filter) and filter:IsPlayer() then ply=filter
    elseif type(filter)=="table" then
        for i=1,math.min(8,#filter)do if IsValid(filter[i]) and filter[i]:IsPlayer() then ply=filter[i];break end end
    end
    local state=ply and states[ply]
    if not state or state.untilTime < CurTime() then return end
    local w=weapon(ply)
    if not w or stock[w:GetClass()] or w~=state.weapon or (ply:GetShootPos()-data.start):LengthSqr()>96^2 then return end
    local radius=2
    if isvector(data.mins) and isvector(data.maxs) then
        radius=math.max(math.abs(data.mins.x),math.abs(data.mins.y),math.abs(data.mins.z),
            math.abs(data.maxs.x),math.abs(data.maxs.y),math.abs(data.maxs.z),2)
    end
    M.observed=M.observed+1
    local pending=state.pending
    if not pending or radius>=pending[5] then state.pending={ply,w,data.start,result.HitPos,radius} end
    if not pending then timer.Simple(0,function()
        local p=state.pending;state.pending=nil
        if M.active and p then send(unpack(p)) end
    end) end
end
local wrappedLine,wrappedHull
if traceLine then
    wrappedLine=function(data,...) local result=traceLine(data,...);observe(data,result);return result end
    util.TraceLine=wrappedLine
end
if traceHull then
    wrappedHull=function(data,...) local result=traceHull(data,...);observe(data,result);return result end
    util.TraceHull=wrappedHull
end
function M.Stop()
    M.active=false
    if util.TraceLine==wrappedLine then util.TraceLine=traceLine end
    if util.TraceHull==wrappedHull then util.TraceHull=traceHull end
    states=setmetatable({}, {__mode="k"})
end
hook.Add("PreCleanupMap", "NLGlass.DebrisMelee", function() states=setmetatable({}, {__mode="k"});M.sent,M.observed=0,0 end)
return M
