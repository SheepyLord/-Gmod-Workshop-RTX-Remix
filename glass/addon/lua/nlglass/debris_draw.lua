-- MIT. Only individual pieces enter these material groups; stable merged piles are never scanned.
local geometry = include("nlglass/debris_mesh.lua")
local R = { groups = {}, retired = {}, retireFirst = 1, retireLast = 0, released = 0 }
function R.Retire(mesh)
    R.retireLast=R.retireLast+1;R.retired[R.retireLast]=mesh
end
function R.Tick()
    R.released=0
    -- Initial construction, up to six split children, evictions and shared preview replacements
    -- retire here. Keep releases bounded even when a receiving-frame preview changes in a burst.
    for _=1,16 do
        local mesh=R.retired[R.retireFirst];if not mesh then break end
        mesh:Destroy();R.retired[R.retireFirst]=nil;R.retireFirst=R.retireFirst+1;R.released=R.released+1
    end
    if R.retireFirst>R.retireLast then R.retireFirst,R.retireLast=1,0
    elseif R.retireFirst>8192 then
        local compact={};for i=R.retireFirst,R.retireLast do compact[#compact+1]=R.retired[i]end
        R.retired,R.retireFirst,R.retireLast=compact,1,#compact
    end
end
function R.ClearRetired()
    for i=R.retireFirst,R.retireLast do R.retired[i]:Destroy() end
    R.retired,R.retireFirst,R.retireLast,R.released={},1,0,0
end
function R.Add(p)
    if p.drawGroup then return end
    local group = R.groups[p.materialName]
    if not group then
        group = { material = p.material, members = {}, count = 0, key = p.materialName }
        R.groups[p.materialName] = group
    end
    p.drawGroup, group.members[p.id], group.count = group, p, group.count + 1
end
function R.Remove(p)
    local group = p.drawGroup
    if not group then return end
    group.members[p.id], group.count, p.drawGroup = nil, group.count - 1, nil
    if group.count == 0 then R.groups[group.key] = nil end
end
function R.Draw(view)
    local calls, culled = 0, 0
    for _, group in pairs(R.groups) do
        local bound = false
        for _, p in pairs(group.members) do
            local scale = p.shrink or 1
            if view.Visible(p.position, p.geometry.radius * scale, true) then
                if not bound then render.SetMaterial(group.material);bound = true end
                geometry.Draw(p, scale);calls = calls + 1
            else culled = culled + 1 end
        end
    end
    return calls, culled
end
local function buildAudio()
    -- MIT. Engine sound calls occur only on the client at an idle native worker boundary.
    local S={played=0,culled=0,limited=0,received=0,tokens=24,stamp=0,frame=-1,frameCount=0,last={}}
    S.setting=CreateClientConVar("rtx_glass_debris_sounds","1",true,false,"Local broken glass impact and split sounds",0,1)
    function S.Drain(api)
        if not api.ReadSounds then return end
        local events=api.ReadSounds()
        if type(events)~="table" then return end
        local now=CurTime()
        S.tokens=math.min(24,S.tokens+math.max(0,now-S.stamp)*24);S.stamp=now
        local frame=FrameNumber()
        if S.frame~=frame then S.frame,S.frameCount=frame,0 end
        local eye=EyePos and EyePos() or vector_origin
        for _,e in ipairs(events) do
            S.received=S.received+1
            local p=e[2];local dx,dy,dz=p[1]-eye.x,p[2]-eye.y,p[3]-eye.z
            if not S.setting:GetBool() or dx*dx+dy*dy+dz*dz>1536^2 then S.culled=S.culled+1
            elseif S.frameCount>=4 or S.tokens<1 or now-(S.last[e[1]] or -100)<.12 then S.limited=S.limited+1
            else
                local kind,speed,mass=e[5],e[3],e[4]
                local name=kind==2 and "physics/glass/glass_sheet_break"..(e[1]%3+1)..".wav" or
                    (kind==3 and "ambient/water/water_splash1.wav" or "physics/glass/glass_impact_"..
                        (speed>220 and mass>.008 and "hard" or "soft")..(e[1]%3+1)..".wav")
                if sound and sound.Play then sound.Play(name,Vector(p[1],p[2],p[3]),kind==2 and 65 or 60,95+e[1]%16,
                    math.Clamp(.12+speed/1200+math.min(mass,.5)*.3,.12,.65)) end
                S.tokens=S.tokens-1;S.frameCount=S.frameCount+1;S.last[e[1]]=now;S.played=S.played+1
            end
        end
        -- Bounded lifetime of per-piece rate entries, even with an infinite debris lifetime.
        if now>(S.prune or 0) then
            for id,t in pairs(S.last) do if now-t>1 then S.last[id]=nil end end
            S.prune=now+1
        end
    end
    function S.Clear() S.last={};S.played=0;S.culled=0;S.limited=0;S.received=0;S.tokens=24;S.stamp=CurTime();S.frame=-1 end
    return S
end
R.Audio=buildAudio()
return R
