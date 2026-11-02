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
