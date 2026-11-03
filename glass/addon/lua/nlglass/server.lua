-- MIT. Authoritative pane registry, damage, map adapters and reliable state/break events.
local S={records={},byEntity={},surfaces={},epoch=0,nextID=0}
local F,G,D,P,C=NLGlass.Fracture,NLGlass.Geometry,NLGlass.Damage,NLGlass.Protocol,NLGlass.Config
NLGlass.Server=S
-- A client cannot otherwise distinguish a remote listen host from a dedicated server.
-- This advertises UI availability only; every clear request is still validated below.
if SetGlobalBool then SetGlobalBool("NLGlass.ListenServer",not game.IsDedicated()) end
-- Native output objects are not exposed by GetKeyValues/TriggerOutput. Capture the raw repeated
-- map keys and let the original entity's unused OnUser channel keep Source's I/O semantics.
S.outputs=setmetatable({},{__mode="k"})
hook.Add("EntityKeyValue","NLGlass.Outputs",function(ent,key,value)
    if ent:GetClass()~="func_breakable_surf" then return end
    key=string.lower(key)
    if key~="onbreak" and not key:match("^onuser[1-4]$") then return end
    local o=S.outputs[ent] or {breaks={},users={}} S.outputs[ent]=o
    if key=="onbreak" then o.breaks[#o.breaks+1]=value else o.users[tonumber(key:sub(-1))]=true end
end)
for _,name in ipairs({"nlglass_state","nlglass_hit","nlglass_remove","nlglass_blast","nlglass_sync","nlglass_clear","nlglass_clear_debris","nlglass_setting"}) do util.AddNetworkString(name) end
-- Glass-Rewrite-Remix archived two of these names with other meanings (contact speed 100, velocity
-- transfer 2) and GMod restores archived values, so a walk would break glass. Reset them once;
-- rtx_glass_settings_version records it, and later choices are kept.
CreateConVar("rtx_glass_settings_version","0",FCVAR_ARCHIVE,"Native loader glass: settings migration done")
function S.MigrateSettings()
    if GetConVar("rtx_glass_settings_version"):GetInt()>=1 then return end
    for _,s in ipairs(C.Settings) do
        if s[1]=="rtx_glass_player_break_speed" or s[1]=="rtx_glass_velocity_transfer" then RunConsoleCommand(s[1],s[2]) end
    end
    RunConsoleCommand("rtx_glass_settings_version","1")
end
timer.Simple(0,S.MigrateSettings)
local function send(target) if target then net.Send(target) else net.Broadcast() end end
function S.Snapshot(r,target)
    S.Refresh(r)
    net.Start("nlglass_state") P.WriteRecord(r) send(target)
end
function S.Forget(r)
    if not S.records[r.id] then return end
    S.records[r.id]=nil
    if r.entity then S.byEntity[r.entity]=nil end
    if r.original then
        if S.surfaces[r.original]==r then
            S.surfaces[r.original]=nil
            if not r.outputFired and IsValid(r.original) then
                r.original:SetNoDraw(false) r.original:SetNotSolid(false)
                local phys=r.original:GetPhysicsObject() if IsValid(phys) then phys:EnableCollisions(true) end
            end
        end
    end
    net.Start("nlglass_remove") net.WriteUInt(r.id,32) net.Broadcast()
end
function S.Refresh(r)
    if r.localOrigin and IsValid(r.entity) then
        r.frame.origin,r.frame.angles=LocalToWorld(r.localOrigin,r.localAngles,r.entity:GetPos(),r.entity:GetAngles())
    end
end
function S.Register(entity,frame,def,native)
    def=G.ValidDefinition(def)
    if not def then return end
    S.nextID=S.nextID+1
    local r={id=S.nextID,entity=entity,entityIndex=entity:EntIndex(),native=native or false,frame=frame,
        state=F.New(def),nextSeed=S.nextID*7919%2147483646+1,contacts=setmetatable({},{__mode="k"}),epoch=S.epoch}
    r.localOrigin,r.localAngles=WorldToLocal(frame.origin,frame.angles,entity:GetPos(),entity:GetAngles())
    S.records[r.id],S.byEntity[entity]=r,r
    entity.NLGlassID=r.id
    if not native and IsValid(entity.NLGlassOriginal) then
        local existing=S.surfaces[entity.NLGlassOriginal]
        if not existing or not IsValid(existing.entity) or existing.entity==entity then
            r.original=entity.NLGlassOriginal S.surfaces[r.original]=r
            r.original:SetNoDraw(true) r.original:SetNotSolid(true)
            local phys=r.original:GetPhysicsObject() if IsValid(phys) then phys:EnableCollisions(false) end
        else entity.NLGlassOriginal=nil end -- a duplicate cannot steal a map window's output bridge
    end
    S.Snapshot(r)
    return r
end
function S.Definition(outline,thickness,kind,strength)
    return {outline=outline,thickness=thickness,kind=kind or C.Kind("rtx_glass_map_kind"),
        strength=strength or C.Number("rtx_glass_strength",1),piece_size=C.Number("rtx_glass_piece_size",8),
        velocity_transfer=C.Number("rtx_glass_velocity_transfer",1)}
end
function S.Collision(r)
    if r.native or not IsValid(r.entity) then return end
    local ent=r.entity
    local polys=F.Remaining(r.state)
    if #polys==0 then ent:Remove() return end
    local ok=ent:PhysicsInitMultiConvex(G.Convexes(polys,r.state.def.thickness))
    if ok==false or not IsValid(ent:GetPhysicsObject()) then
        -- Never leave the model's placeholder cube as an invisible blocker.
        ent:PhysicsDestroy() ent:SetNotSolid(true)
        ErrorNoHalt("[NLGlass] remaining-glass collision failed; pane removed\n")
        S.Impact(r,D.Fallback(r),true)
        if IsValid(ent) then ent:Remove() end
        return
    end
    ent:EnableCustomCollisions(true) ent:SetMoveType(MOVETYPE_NONE) ent:SetSolid(SOLID_VPHYSICS)
    ent:SetNotSolid(false) ent:SetTrigger(true) ent:UseTriggerBounds(true,4)
    local phys=ent:GetPhysicsObject()
    phys:EnableMotion(false) phys:SetMaterial("glass")
    ent:CollisionRulesChanged()
end
local function originalOutput(r,impact)
    if r.outputFired or not IsValid(r.original) then return end
    r.outputFired=true
    local o=S.outputs[r.original]
    if not o or #o.breaks==0 then return end
    local channel
    for i=4,1,-1 do if not o.users[i] then channel=i break end end
    if not channel then
        ErrorNoHalt("[NLGlass] map OnBreak bridge unavailable: all four OnUser outputs are in use\n")
        return
    end
    for _,value in ipairs(o.breaks) do r.original:SetKeyValue("OnUser"..channel,value) end
    r.original:Fire("FireUser"..channel,"",0,IsValid(impact.attacker) and impact.attacker or r.original,r.original)
end
function S.Impact(r,impact,forceAll)
    if not r or r.broken or r.epoch~=S.epoch or S.records[r.id]~=r then return false end
    S.Refresh(r)
    r.lastImpact=impact -- native engine health may break on a hit too weak to show cracks
    local old={id=r.id,entityIndex=r.entityIndex,native=r.native,frame=r.frame,localOrigin=r.localOrigin,localAngles=r.localAngles,
        state=F.Snapshot(r.state)}
    local pieces,accepted,broke=F.Apply(r.state,impact,forceAll,r.native)
    if not accepted then return false end
    if #pieces>0 and NLGlass.Bullets then
        local radius=768
        for _,v in ipairs(r.state.def.outline) do radius=math.max(radius,768+math.sqrt(v[1]*v[1]+v[2]*v[2])) end
        NLGlass.Bullets.Mark(r.frame.origin,radius)
    end
    net.Start("nlglass_hit") net.WriteUInt(r.id,32) net.WriteUInt(old.state.revision,32)
    net.WriteBool(broke) if broke then P.WriteRecord(old) end
    P.WriteImpact(impact) net.WriteBool(forceAll or false) net.WriteBool(r.native) net.Broadcast()
    if S.Observe then S.Observe("sent",r.id,engine.TickCount(),CurTime(),SysTime()) end
    if not r.native then
        if broke then originalOutput(r,impact) S.Collision(r) end
    elseif forceAll then
        r.broken=true
        S.Forget(r)
    end
    return true,pieces
end
function S.Damage(entity,dmg)
    local r=S.byEntity[entity] or S.surfaces[entity]
    if not r then return end
    if S.Observe then S.Observe("damage",r.id,engine.TickCount(),CurTime(),SysTime()) end
    S.Refresh(r)
    if dmg:IsDamageType(DMG_BLAST) then S.Blast(dmg) end
    S.Impact(r,D.FromDamage(r,dmg))
    return not r.native
end
function S.Contact(entity,data)
    local r=S.byEntity[entity]
    if not r then return end
    local hitter=data.HitEntity
    if not hitter then return end
    -- A player's or NPC's physics shadow collides too: bodies follow the break-speed rule, never the
    -- prop energy rule (85 kg at a 200 units/s walk is far above the breaking energy).
    if IsValid(hitter) and (hitter:IsPlayer() or hitter:IsNPC()) then return S.Body(entity,hitter,data.TheirOldVelocity) end
    S.Refresh(r)
    local stamp=engine.TickCount()
    if r.contacts[hitter]==stamp then return end
    r.contacts[hitter]=stamp
    local impact=D.FromCollision(r,data)
    -- Source prohibits destroying/rebuilding a physics object during its collision callback.
    timer.Simple(0,function() if IsValid(entity) then S.Impact(r,impact) end end)
end
-- A player in noclip passes through the world: it never touches, so it never fractures glass.
function S.Ghost(body)
    return IsValid(body) and body:IsPlayer() and body:GetMoveType()==MOVETYPE_NOCLIP
end
function S.Body(entity,body,velocity,point)
    local r=S.byEntity[entity]
    if not r or S.Ghost(body) then return end
    S.Refresh(r)
    local stamp=engine.TickCount()
    if r.contacts[body] and stamp-r.contacts[body]<6 then return end
    local impact=D.FromBody(r,body,velocity,point)
    if impact then r.contacts[body]=stamp timer.Simple(0,function() if IsValid(entity) then S.Impact(r,impact) end end) end
end
-- Touch can arrive after the player mover has clipped the velocity against frozen VPhysics.
-- Sweep the moving player's real hull before that clipping; no scan/tick work for idle panes.
hook.Add("SetupMove","NLGlass.PlayerContact",function(ply,mv)
    if not next(S.records) or S.Ghost(ply) then return end
    local velocity=mv:GetVelocity()+ply:GetBaseVelocity()
    if velocity:LengthSqr()<math.max(1,C.Number("rtx_glass_player_break_speed",250)^2) then return end
    local mins,maxs=ply:GetCollisionBounds()
    local origin=mv:GetOrigin()
    local tr=util.TraceHull({start=origin,endpos=origin+velocity*engine.TickInterval(),mins=mins,maxs=maxs,
        filter=ply,mask=MASK_PLAYERSOLID})
    if tr.Hit and S.byEntity[tr.Entity] then
        local point=origin+velocity*(engine.TickInterval()*tr.Fraction)+(mins+maxs)*0.5
        S.Body(tr.Entity,ply,velocity,point)
    end
end)
function S.NativeBreak(r,breaker)
    if not r or r.broken or r.epoch~=S.epoch then return end
    S.Refresh(r)
    local impact=r.lastImpact or D.Fallback(r,breaker)
    S.Impact(r,impact,true)
end
function S.TrackNative(ent)
    if not IsValid(ent) or ent:GetClass()~="func_breakable" then return end
    if S.byEntity[ent] then return S.byEntity[ent] end
    local phys=ent:GetPhysicsObject()
    if not IsValid(phys) or phys:GetMaterial()~="glass" then return end
    local frame,outline,thickness=G.FromEntity(ent)
    if frame then return S.Register(ent,frame,S.Definition(outline,thickness),true) end
end
function S.ReplaceSurface(ent)
    if not IsValid(ent) or S.surfaces[ent] then return end
    local frame,outline,thickness=G.FromEntity(ent)
    if not frame then return end
    local pane=ents.Create("nlglass_pane")
    if not IsValid(pane) then return end
    pane.NLGlassDefinition=S.Definition(outline,thickness)
    pane.NLGlassFrame=frame pane.NLGlassOriginal=ent pane:SetPos(frame.origin) pane:SetAngles(frame.angles) pane:Spawn()
    local r=S.byEntity[pane]
    if not r then pane:Remove() return end
    r.original=ent S.surfaces[ent]=r
    ent:SetNoDraw(true) ent:SetNotSolid(true)
    local phys=ent:GetPhysicsObject() if IsValid(phys) then phys:EnableCollisions(false) end
end
local function scan()
    -- Most cleanup paths remove these, but a save/other add-on can retain a scripted pane.
    -- Reattach survivors before scanning brushes, so they do not leave ghost collision or get
    -- a second map replacement. Properties persist; broken state may reset.
    for _,ent in ipairs(ents.FindByClass("nlglass_*")) do
        if ent.NLGlassDefinition and not S.byEntity[ent] then ent.NLGlassFrame=nil ent:Initialize() end
    end
    for _,ent in ipairs(ents.FindByClass("func_breakable_surf")) do S.ReplaceSurface(ent) end
    for _,ent in ipairs(ents.FindByClass("func_breakable")) do S.TrackNative(ent) end
end
hook.Add("InitPostEntity","NLGlass.Map",scan)
hook.Add("OnEntityCreated","NLGlass.Map",function(ent)
    local class=ent:GetClass()
    if class=="func_breakable_surf" or class=="func_breakable" then
        timer.Simple(0,function()
            if not IsValid(ent) then return end
            if class=="func_breakable_surf" then S.ReplaceSurface(ent) else S.TrackNative(ent) end
        end)
    end
end)
hook.Add("EntityTakeDamage","NLGlass.Damage",function(ent,dmg)
    -- The scripted entity owns OnTakeDamage; returning nil here permits all other add-on hooks.
    if S.byEntity[ent] and not S.byEntity[ent].native then return end
    if dmg:IsDamageType(DMG_BLAST) then S.Blast(dmg) end
    S.TrackNative(ent)
    if S.Damage(ent,dmg) then return true end
end)
hook.Add("AcceptInput","NLGlass.Input",function(ent,input,activator,caller)
    input=string.lower(input)
    if input~="break" and input~="shatter" then return end
    local surface=S.surfaces[ent]
    local r=S.byEntity[ent] or surface or S.TrackNative(ent)
    if not r then return end
    S.Refresh(r)
    local breaker=IsValid(activator) and activator or caller
    if r.native then r.breaker=breaker return end -- engine still owns health, solids and outputs
    S.Impact(r,D.Fallback(r,breaker),true)
    return true
end)
gameevent.Listen("break_breakable")
hook.Add("break_breakable","NLGlass.NativeBreak",function(data)
    local index=tonumber(data.entindex)
    for _,r in pairs(S.records) do
        if r.native and r.entityIndex==index then
            local breaker=Player(tonumber(data.userid) or 0)
            S.NativeBreak(r,IsValid(breaker) and breaker or r.breaker)
            break
        end
    end
end)
hook.Add("EntityRemoved","NLGlass.Remove",function(ent)
    local r=S.byEntity[ent]
    if not r then return end
    if r.native then
        -- Event ordering varies: removal and break_breakable can both arrive for the same brush.
        timer.Simple(0,function() S.NativeBreak(r,r.breaker) end)
    else
        S.Forget(r)
    end
end)
hook.Add("PreCleanupMap","NLGlass.Clear",function()
    S.epoch=S.epoch+1 S.records={} S.byEntity={} S.surfaces={}
    net.Start("nlglass_clear") net.Broadcast()
end)
hook.Add("PostCleanupMap","NLGlass.Map",scan)
-- Restored saves/duplicates register fresh intact states through the entity's restore method.
hook.Add("PostRestore","NLGlass.Restore",scan)
net.Receive("nlglass_sync",function(_,ply)
    if not IsValid(ply) then return end
    local id=net.ReadUInt(32)
    local window=ply.NLGlassSyncWindow
    if not window or window.at<CurTime()-2 then window={at=CurTime(),count=0,ids={}} ply.NLGlassSyncWindow=window end
    if window.count>=16 or window.ids[id] then return end
    window.count=window.count+1 window.ids[id]=true
    if id==0 then
        for _,r in pairs(S.records) do S.Snapshot(r,ply) end
    elseif S.records[id] then S.Snapshot(S.records[id],ply)
    else net.Start("nlglass_remove") net.WriteUInt(id,32) net.Send(ply) end
end)
net.Receive("nlglass_setting",function(_,ply)
    if not IsValid(ply) or not ply:IsAdmin() then return end
    local index,value=net.ReadUInt(4),net.ReadString()
    if #value>32 then return end
    if index==0 then
        for _,s in ipairs(C.Settings) do RunConsoleCommand(s[1],s[2]) end
        return
    end
    local s=C.Settings[index]
    if not s then return end
    if s[1]=="rtx_glass_map_kind" or s[1]=="rtx_glass_spawn_kind" then
        if value~="annealed" and value~="tempered" then return end
    else
        value=tonumber(value)
        if not value or value~=value then return end
        value=tostring(math.Clamp(value,s[3],s[4]))
    end
    RunConsoleCommand(s[1],value)
end)
net.Receive("nlglass_clear_debris",function(_,ply)
    if not IsValid(ply) or not ply:IsAdmin() or (game.IsDedicated and game.IsDedicated()) then return end
    if (S.clearDebrisAt or -10)>CurTime()-1 then return end
    S.clearDebrisAt=CurTime()
    net.Start("nlglass_clear_debris") net.Broadcast()
end)
local function installBlasts()
    -- MIT. Observe exact Lua blasts, native explosion inputs and native grenade sounds. Never
    -- change damage, sound tables, hook returns or Source physics. Duplicate observations coalesce.
    local S=NLGlass.Server
    local previous=NLGlass.Blasts
    if previous and previous.Restore then previous.Restore() end
    local B={active=true,sent=0,deduplicated=0,limited=0,pending=0,tokens=16,stamp=CurTime(),recent={}}
    NLGlass.Blasts=B
    local function finite(v) return type(v)=="number" and v==v and math.abs(v)<=131072 end
    local function enqueue(origin,radius,damage,source)
        if not B.active then return end
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
            if not B.active or S.epoch~=epoch then return end
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
    function B.Restore()
        B.active=false
        for name,fn in pairs(original) do if util[name]==wrapped[name] then util[name]=fn end end
    end
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
end
S.InstallBlastObserver=installBlasts
installBlasts()
return S
