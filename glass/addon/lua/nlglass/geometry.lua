-- MIT. GMod frame conversion, convex outline extraction, collision and render triangles.
local G = {}
local F=NLGlass.Fracture
function G.ValidDefinition(def)
    if type(def)~="table" or type(def.outline)~="table" or #def.outline<3 or #def.outline>16 then return end
    local points={}
    for _,p in ipairs(def.outline) do
        if type(p)~="table" then return end
        for i=1,2 do if type(p[i])~="number" or p[i]~=p[i] or math.abs(p[i])>4096 then return end end
        points[#points+1]={p[1],p[2]}
    end
    local function bounded(v,a,b) return type(v)=="number" and v==v and v>=a and v<=b end
    if not bounded(def.thickness,0.25,16) or not bounded(def.strength,0.1,10) or
       not bounded(def.piece_size,4,64) or not bounded(def.velocity_transfer,0,3) then return end
    local hull=F.Hull(points)
    if #hull<3 or #hull>16 or F.Area(hull)<4 then return end
    return {outline=hull,thickness=F.Snap(def.thickness),strength=math.max(103/1024,F.Snap(def.strength)),
        kind=def.kind=="tempered" and "tempered" or "annealed",piece_size=F.Snap(def.piece_size),velocity_transfer=F.Snap(def.velocity_transfer)}
end
function G.LocalPoint(frame,p)
    return WorldToLocal(p,angle_zero,frame.origin,frame.angles)
end
function G.WorldPoint(frame,p)
    return LocalToWorld(p,angle_zero,frame.origin,frame.angles)
end
function G.WorldVector(frame,p)
    return G.WorldPoint(frame,Vector(p[1],p[2],p[3]))-frame.origin
end
function G.LocalVector(frame,p)
    return G.LocalPoint(frame,frame.origin+p)
end
function G.Convexes(polys,thickness)
    local out={}
    for _,poly in ipairs(polys) do
        local points={}
        for _,p in ipairs(poly) do
            points[#points+1]=Vector(p[1],p[2],-thickness/2)
            points[#points+1]=Vector(p[1],p[2], thickness/2)
        end
        out[#out+1]=points
    end
    return out
end

function G.Triangles(polys,thickness)
    local out={}
    local function tri(a,b,c,n)
        for _,p in ipairs({a,b,c}) do out[#out+1]={pos=p,normal=n,u=p.x/64,v=p.y/64} end
    end
    for _,poly in ipairs(polys) do
        for i=2,#poly-1 do
            local a,b,c=poly[1],poly[i],poly[i+1]
            tri(Vector(a[1],a[2],thickness/2),Vector(b[1],b[2],thickness/2),Vector(c[1],c[2],thickness/2),Vector(0,0,1))
            tri(Vector(a[1],a[2],-thickness/2),Vector(c[1],c[2],-thickness/2),Vector(b[1],b[2],-thickness/2),Vector(0,0,-1))
        end
        for i,a in ipairs(poly) do
            local b=poly[i%#poly+1]
            local n=Vector(b[2]-a[2],a[1]-b[1],0):GetNormalized()
            local p,q,r,s=Vector(a[1],a[2],-thickness/2),Vector(b[1],b[2],-thickness/2),
                Vector(b[1],b[2],thickness/2),Vector(a[1],a[2],thickness/2)
            tri(p,q,r,n) tri(p,r,s,n)
        end
    end
    return out
end

-- Surface vertices are brush-model local, including world-positioned (origin zero) map brushes.
-- Select the largest face, preserving a triangular/irregular outline rather than an OBB rectangle.
function G.FromEntity(ent,physicsOnly)
    local faces={}
    if not physicsOnly and ent.GetBrushSurfaces then
        for _,surface in ipairs(ent:GetBrushSurfaces() or {}) do
            local vertices=surface:GetVertices()
            if vertices and #vertices>=3 then
                local material=surface:GetMaterial()
                if material and type(material)~="string" and material.GetName then material=material:GetName() end
                faces[#faces+1]={points=vertices,material=type(material)=="string" and material or nil}
            end
        end
    end
    local physics=ent:GetPhysicsObject()
    local cloud={}
    if IsValid(physics) then
        for _,convex in ipairs(physics:GetMeshConvexes() or {}) do
            for _,vertex in ipairs(convex) do cloud[#cloud+1]=vertex.pos or vertex end
        end
    end
    -- Physics meshes have triangle soup; each triangle supplies a candidate frame. Projection's
    -- hull recovers the face of a thin convex. Non-planar props are intentionally a convex envelope.
    if #faces==0 then
        for i=1,#cloud-2,3 do faces[#faces+1]={points={cloud[i],cloud[i+1],cloud[i+2]}} end
    end
    local best,largest=nil,0
    for _,face in ipairs(faces) do
        local points=face.points
        local u=(points[2]-points[1]):GetNormalized()
        local normal=(points[2]-points[1]):Cross(points[3]-points[1]):GetNormalized()
        if normal:LengthSqr()>0.5 and u:LengthSqr()>0.5 then
            local v=normal:Cross(u)
            local projected={}
            for _,p in ipairs(points) do local d=p-points[1] projected[#projected+1]={d:Dot(u),d:Dot(v)} end
            local area=math.abs(F.Area(F.Hull(projected)))
            if area>largest then largest=area best={u=u,v=v,n=normal,base=points[1],face=face} end
        end
    end
    if not best then return end
    local samples=#cloud>0 and cloud or best.face.points
    local lo,hi=math.huge,-math.huge
    for _,p in ipairs(samples) do local z=(p-best.base):Dot(best.n) lo=math.min(lo,z) hi=math.max(hi,z) end
    local localOrigin=best.base+best.n*((lo+hi)/2)
    local worldOrigin=ent:LocalToWorld(localOrigin)
    local u=(ent:LocalToWorld(localOrigin+best.u)-worldOrigin):GetNormalized()
    local n=(ent:LocalToWorld(localOrigin+best.n)-worldOrigin):GetNormalized()
    local angles=u:AngleEx(n)
    local frame={origin=worldOrigin,angles=angles,material="models/props_combine/health_charger_glass",color=ent:GetColor(),
        sourceMaterial=best.face.material}
    local outline={}
    local projection=physicsOnly and samples or best.face.points
    for _,p in ipairs(projection) do
        local q=G.LocalPoint(frame,ent:LocalToWorld(p))
        outline[#outline+1]={q.x,q.y}
    end
    outline=F.Hull(outline)
    if #outline<3 or #outline>16 then return end
    -- Centre the 2D coordinates to fit the compact signed coordinate fields.
    local center=F.Center(outline)
    frame.origin=G.WorldPoint(frame,Vector(center[1],center[2],0))
    for _,p in ipairs(outline) do p[1],p[2]=p[1]-center[1],p[2]-center[2] end
    return frame,outline,math.Clamp(hi-lo,0.5,16)
end
return G
