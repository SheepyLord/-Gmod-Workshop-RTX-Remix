-- MIT. Read-only stock swing observations and actual short SWEP traces, including misses.
if CLIENT then return end
local previous = NLGlass.Melee
if previous and previous.Stop then previous.Stop() end
local M = { sent = 0, observed = 0, limited = 0, active = true }
NLGlass.Melee = M
local B = NLGlass.Bullets
local states = setmetatable({}, {__mode = "k"})
local traceLine, traceHull = util.TraceLine, util.TraceHull
local clipTokens,clipStamp=32,CurTime()
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
    -- A swept volume extends beyond a line endpoint. Reclip a containing Source box so even
    -- a line-only SWEP cannot push local glass just behind a wall. Never change its real trace.
    local now=CurTime();clipTokens=math.min(32,clipTokens+math.max(0,now-clipStamp)*64);clipStamp=now
    if clipTokens<1 or not traceHull then M.limited=M.limited+1;return end
    clipTokens=clipTokens-1;radius=math.max(1,math.min(16,math.ceil(radius or 6)))
    local ok,clipped=pcall(traceHull,{start=from,endpos=to,filter=ply,mask=MASK_SHOT_HULL,
        mins=Vector(-radius,-radius,-radius),maxs=Vector(radius,radius,radius)})
    if not ok or type(clipped)~="table" or not isvector(clipped.HitPos) or clipped.StartSolid or clipped.AllSolid then return end
    to=clipped.HitPos
    local primary = type(w.Primary) == "table" and w.Primary or {}
    local hitDamage = type(w.HitDamage)=="table" and ((tonumber(w.HitDamage[1]) or 0)+(tonumber(w.HitDamage[2]) or 0))*.5 or tonumber(w.HitDamage)
    local damage = stock[w:GetClass()] or tonumber(primary.Damage) or hitDamage or 25
    if B.Forward(ply,from,to,damage,radius,ply) then
        state.sentUntil = CurTime()+.1;M.sent=M.sent+1
    end
end
local function stockSwing(ply,w)
    local from = ply:GetShootPos()
    send(ply,w,from,from+ply:GetAimVector()*75,6)
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
    if not s or s.weapon~=w then s={weapon=w,sentUntil=0,nextFire=w:GetNextPrimaryFire()};states[ply]=s end
    s.untilTime,s.seen=CurTime()+.6,CurTime()
    if stock[w:GetClass()] then stockSwing(ply,w) end
    -- Never return an animation override.
end)
-- A trace filter may be an entity, a table of entities or class names, or a function: IsValid
-- indexes its argument, so only entities reach it.
local function player(value)
    if isentity(value) and IsValid(value) and value:IsPlayer() then return value end
end
local function observe(data,result)
    if type(data)~="table" or type(result)~="table" or result.StartSolid or result.AllSolid or
        not isvector(data.start) or not isvector(result.HitPos) or not isvector(data.endpos) then return end
    local delta=data.endpos-data.start
    if delta:LengthSqr()<1 or delta:LengthSqr()>160^2 then return end
    local filter=data.filter;local ply=player(filter)
    if not ply and type(filter)=="table" then
        for i=1,math.min(8,#filter)do ply=player(filter[i]);if ply then break end end
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
    if not pending or radius>=pending[5] then
        local a,b=data.start,result.HitPos
        state.pending={ply,w,Vector(a.x,a.y,a.z),Vector(b.x,b.y,b.z),radius}
    end
    if not pending then timer.Simple(0,function()
        local p=state.pending;state.pending=nil
        if M.active and p and states[ply]==state then send(unpack(p)) end
    end) end
end
-- Every add-on's traces pass through here: an observation must never fail the caller's trace.
local function watch(data,result)
    if not M.active or not B.HasInterest() then return end
    local ok,problem=pcall(observe,data,result)
    if not ok then M.errors=(M.errors or 0)+1;M.lastError=tostring(problem) end
end
local wrappedLine,wrappedHull
if traceLine then
    wrappedLine=function(data,...) local result=traceLine(data,...);watch(data,result);return result end
    util.TraceLine=wrappedLine
end
if traceHull then
    wrappedHull=function(data,...) local result=traceHull(data,...);watch(data,result);return result end
    util.TraceHull=wrappedHull
end
function M.Stop()
    M.active=false
    if util.TraceLine==wrappedLine then util.TraceLine=traceLine end
    if util.TraceHull==wrappedHull then util.TraceHull=traceHull end
    states=setmetatable({}, {__mode="k"})
end
hook.Add("PreCleanupMap", "NLGlass.DebrisMelee", function()
    states=setmetatable({}, {__mode="k"});M.sent,M.observed,M.limited=0,0,0;clipTokens,clipStamp=32,CurTime()
end)
return M
