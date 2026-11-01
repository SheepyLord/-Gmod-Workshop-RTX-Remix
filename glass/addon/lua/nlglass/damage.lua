-- MIT. Every server cause becomes this one impact representation, in the pane frame.
local D={}
local F,G,C=NLGlass.Fracture,NLGlass.Geometry,NLGlass.Config
local function valid(e) return IsValid(e) end
function D.Mass(ent,physics)
    if valid(physics) then return math.Clamp(physics:GetMass(),0.1,50000) end
    if valid(ent) then
        local phys=ent:GetPhysicsObject()
        if valid(phys) then return math.Clamp(phys:GetMass(),0.1,50000) end
    end
    return C.Number("rtx_glass_player_mass",85)
end
function D.Normalize(r,point,direction,energy,kind,attacker,inflictor)
    local p=G.LocalPoint(r.frame,point or r.frame.origin)
    -- Clamp to the nearest point on the convex outline, so engine damage positions of (0,0,0)
    -- or blast centres outside a window cannot create a fracture kilometres away.
    local poly=r.state.def.outline
    local inside=true
    for i,a in ipairs(poly) do local b=poly[i%#poly+1] if (b[1]-a[1])*(p.y-a[2])-(b[2]-a[2])*(p.x-a[1])<0 then inside=false end end
    if not inside then
        local distance,bx,by=math.huge,0,0
        for i,a in ipairs(poly) do
            local b=poly[i%#poly+1] local dx,dy=b[1]-a[1],b[2]-a[2]
            local t=math.Clamp(((p.x-a[1])*dx+(p.y-a[2])*dy)/math.max(0.001,dx*dx+dy*dy),0,1)
            local x,y=a[1]+t*dx,a[2]+t*dy
            local ds=(p.x-x)^2+(p.y-y)^2
            if ds<distance then distance,bx,by=ds,x,y end
        end
        p=Vector(bx,by,0)
    end
    direction=direction or Vector()
    if direction:LengthSqr()<0.001 then direction=G.WorldVector(r.frame,{0,0,1}) end
    local d=G.LocalVector(r.frame,direction:GetNormalized())
    r.nextSeed=(r.nextSeed*16807)%2147483647
    local function component(v) return F.Snap(math.Clamp(v,-1,1)) end
    return {x=F.Snap(p.x),y=F.Snap(p.y),dx=component(d.x),dy=component(d.y),dz=component(d.z),
        energy=math.Clamp(math.floor(energy or 0),0,2147483647),kind=kind or "blunt",seed=r.nextSeed,
        attacker=attacker,inflictor=inflictor}
end
function D.Fallback(r,breaker)
    local point,direction=r.frame.origin,Vector()
    if valid(breaker) then point=breaker:WorldSpaceCenter() direction=breaker:GetVelocity() end
    if direction:LengthSqr()<1 and valid(breaker) then direction=r.frame.origin-point end
    local energy=math.max(F.Threshold(r.state.def),0.5*D.Mass(breaker)*direction:LengthSqr())
    return D.Normalize(r,point,direction,energy,"blunt",breaker,breaker)
end
function D.FromDamage(r,dmg)
    local attacker,inflictor=dmg:GetAttacker(),dmg:GetInflictor()
    local point,force=dmg:GetDamagePosition(),dmg:GetDamageForce()
    if point:LengthSqr()==0 then point=r.frame.origin end
    local kind,scale="blunt",16000
    if dmg:IsDamageType(DMG_BLAST) then kind,scale="blast",20000
    elseif dmg:IsDamageType(DMG_BULLET) or dmg:IsDamageType(DMG_BUCKSHOT) then kind,scale="sharp",12000
    elseif dmg:IsDamageType(DMG_CRUSH) then scale=12000 end
    if force:LengthSqr()<0.001 and valid(attacker) then force=r.frame.origin-attacker:WorldSpaceCenter() end
    return D.Normalize(r,point,force,dmg:GetDamage()*scale,kind,attacker,inflictor)
end
function D.FromCollision(r,data)
    local hitter,phys=data.HitEntity,data.HitObject
    local their=data.TheirOldVelocity or (valid(phys) and phys:GetVelocity()) or (valid(hitter) and hitter:GetVelocity()) or Vector()
    local relative=their-(data.OurOldVelocity or Vector())
    if relative:LengthSqr()<1 and data.Speed and data.Speed>0 then relative=-(data.HitNormal or Vector(0,0,1))*data.Speed end
    return D.Normalize(r,data.HitPos,relative,0.5*D.Mass(hitter,phys)*relative:LengthSqr(),"blunt",hitter,hitter)
end
function D.FromBody(r,body)
    if not valid(body) or not (body:IsPlayer() or body:IsNPC() or body:IsVehicle()) then return end
    local velocity=body:GetVelocity()
    if velocity:LengthSqr()<1 then return end
    local normal=G.WorldVector(r.frame,{0,0,1})
    if math.abs(velocity:Dot(normal))<C.Number("rtx_glass_player_break_speed",180) then return end
    local point=body:WorldSpaceCenter()
    local p=G.LocalPoint(r.frame,point)
    -- Touch uses an expanded trigger bound: a player wholly in a hole must not hit ghost glass.
    local inGlass=false
    for _,poly in ipairs(F.Remaining(r.state)) do
        local inside=true
        for i,a in ipairs(poly) do local b=poly[i%#poly+1] if (b[1]-a[1])*(p.y-a[2])-(b[2]-a[2])*(p.x-a[1])<0 then inside=false break end end
        if inside then inGlass=true break end
    end
    if not inGlass then return end
    return D.Normalize(r,point,velocity,0.5*D.Mass(body)*velocity:LengthSqr(),"blunt",body,body)
end
return D
