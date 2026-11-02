-- MIT. Pure numeric planning. Keep exact polygons; a group merely shares one rigid transform.
local A = {}
local function finite(n) return type(n)=="number" and n==n and math.abs(n)<=8192 end
local function bounds(f)
    if type(f)~="table" or type(f.poly)~="table" or #f.poly<3 or #f.poly>64 or
        not finite(f.thickness) or f.thickness<.01 or f.thickness>64 then return end
    local loX,loY,hiX,hiY,area,px,py=1e9,1e9,-1e9,-1e9,0
    for _,v in ipairs(f.poly) do
        if type(v)~="table" then return end
        local x,y=v[1] or v.x,v[2] or v.y
        if not finite(x) or not finite(y) then return end
        if px then area=area+px*y-py*x end
        px,py=x,y
        loX,loY,hiX,hiY=math.min(loX,x),math.min(loY,y),math.max(hiX,x),math.max(hiY,y)
    end
    local v=f.poly[1];area=area+px*(v[2] or v.y)-py*(v[1] or v.x)
    if area<=.0001 then return end
    return loX,loY,hiX,hiY
end
function A.Pack(fragments, first, last, coarse, eye)
    local out,cells={},{}
    for i=first,last do
        local f=fragments[i];local lx,ly,hx,hy=bounds(f)
        if lx then
            local cx,cy=(lx+hx)*.5,(ly+hy)*.5
            -- Preserve every fragment with any part of its bounds within 256 units of the eye.
            local radius=math.sqrt((hx-lx)^2+(hy-ly)^2)*.5
            local far=eye and (cx-eye[1])^2+(cy-eye[2])^2+eye[3]^2>(256+radius)^2
            local key=coarse and far and hx-lx<=64 and hy-ly<=64 and
                (math.floor(cx/32).."/"..math.floor(cy/32).."/"..f.thickness) or nil
            local group=key and cells[key]
            local points=#f.poly*2
            if not group or #group.parts==8 or group.points+points>512 then
                group={parts={},points=0};out[#out+1]=group
                if key then cells[key]=group end
            end
            group.parts[#group.parts+1],group.points=f,group.points+points
        end
    end
    return out
end
local function buildPreview()
    -- MIT. One transient mesh per break, drawn immediately while the bounded body queue drains.
    local P={live={},serial=0,draws=0,uploads=0}
    local function gravity() local c=GetConVar("sv_gravity") return c and c:GetFloat() or 600 end
    function P.Add(rows,context)
        -- Chunks cap the cost of removing constructed pieces from a shared mesh. Each chunk
        -- follows one ballistic trajectory; bodies start at that exact pose on handoff.
        local group
        for i,q in ipairs(rows) do
            if (i-1)%24==0 then
                P.serial=P.serial+1
                group={id=P.serial,rows={},context=context,velocity=Vector(),kicks={},matrix=Matrix(),dirty=true}
                P.live[group.id]=group
            end
            q.preview=group;group.rows[#group.rows+1]=q
        end
        for _,g in pairs(P.live) do if g.context==context and not g.ready then
            local n,cx,cy=0,0,0
            for _,q in ipairs(g.rows) do for _,f in ipairs(q.parts) do
                g.velocity=g.velocity+(f.velocity or vector_origin);n=n+1
                local x,y=0,0;for _,p in ipairs(f.poly)do x=x+(p[1] or p.x);y=y+(p[2] or p.y)end
                cx,cy=cx+x/#f.poly,cy+y/#f.poly
            end end
            g.velocity=g.velocity/math.max(1,n);g.ready=true
            g.center=LocalToWorld(Vector(cx/math.max(1,n),cy/math.max(1,n),0),angle_zero,context.origin,context.angles)
        end end
    end
    function P.Offset(g)
        local t=math.max(0,CurTime()-g.context.born)
        -- Never age a backlog for seconds through the map. Normal queues drain in <0.5s;
        -- a slow import pauses the preview and body clock at that bound.
        t=math.min(t,.5)
        local offset=g.velocity*t+Vector(0,0,-gravity()*t*t*.5)
        for _,kick in ipairs(g.kicks)do offset=offset+kick.velocity*math.max(0,t-kick.at)end
        -- The caller applies exact per-body blast history to velocity at handoff, not the
        -- preview's approximate chunk kick, so return gravity-aged base velocity separately.
        return offset,g.velocity+Vector(0,0,-gravity()*t)
    end
    function P.Impulse(origin,radius,speed)
        for _,g in pairs(P.live)do
            local offset=P.Offset(g);local delta=g.center+offset-origin;local distance=delta:Length()
            if distance<radius then
                if #g.kicks==8 then table.remove(g.kicks,1)end
                g.kicks[#g.kicks+1]={at=math.min(.5,math.max(0,CurTime()-g.context.born)),
                    velocity=(distance>.001 and delta/distance or Vector(0,0,1))*(speed*(1-distance/radius))}
            end
        end
    end
    function P.Remove(q)
        local g=q.preview
        if g then q.consumed=true;g.dirty=true end
    end
    function P.Draw(geometry,retire)
        local calls=0
        for id,g in pairs(P.live) do
            local c=g.context
            if g.dirty then
                local vertices,remaining={},0
                for _,q in ipairs(g.rows) do if not q.consumed then
                    for _,f in ipairs(q.parts) do
                        -- Only the two glass faces are needed during the short handoff. Avoid
                        -- cooking full extrusion/edge normals outside the construction allowance.
                        local faces=f.previewFaces
                        if not faces then
                            faces={};f.previewFaces=faces
                            local poly=f.poly;local front,back=Vector(0,0,1),Vector(0,0,-1)
                            local function vertex(p,z,n)
                                local x,y=p[1] or p.x,p[2] or p.y
                                faces[#faces+1]={pos=Vector(x,y,z),normal=n,u=x/32,v=y/32,color=c.color}
                            end
                            for i=2,#poly-1 do
                                vertex(poly[1],f.thickness*.5,front);vertex(poly[i],f.thickness*.5,front);vertex(poly[i+1],f.thickness*.5,front)
                                vertex(poly[1],-f.thickness*.5,back);vertex(poly[i+1],-f.thickness*.5,back);vertex(poly[i],-f.thickness*.5,back)
                            end
                        end
                        for _,v in ipairs(faces) do vertices[#vertices+1]=v end
                    end
                    remaining=remaining+1
                end end
                if g.mesh then retire(g.mesh);g.mesh=nil end
                if remaining==0 then P.live[id]=nil
                elseif #vertices>0 then
                    local ok,m=pcall(geometry.Build,vertices,c.material)
                    if ok then g.mesh=m;P.uploads=P.uploads+1 end
                end
                g.dirty=false
            end
            if g.mesh then
                local offset=P.Offset(g)
                g.matrix:SetTranslation(c.origin+offset);g.matrix:SetAngles(c.angles)
                render.SetMaterial(c.material);cam.PushModelMatrix(g.matrix);g.mesh:Draw();cam.PopModelMatrix()
                calls=calls+1
            end
        end
        P.draws=calls
        return calls
    end
    function P.Clear(retire)
        for _,g in pairs(P.live) do if g.mesh then retire(g.mesh) end end
        P.live={};P.draws=0;P.uploads=0
    end
    return P
end
A.Preview=buildPreview()
return A
