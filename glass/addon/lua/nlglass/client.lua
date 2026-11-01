-- MIT. Cached pane/crack geometry and deterministic replay; debris uses only G1-B's public API.
local V={records={}}
NLGlass.Client=V
local F,G,P=NLGlass.Fracture,NLGlass.Geometry,NLGlass.Protocol
local frost=CreateMaterial("nlglass_frost","UnlitGeneric",{["$basetexture"]="models/debug/debugwhite",
    ["$translucent"]="1",["$alpha"]="0.65",["$color"]="[0.65 0.72 0.76]",["$nocull"]="1"})
local function destroy(r)
    if r.mesh then r.mesh:Destroy() r.mesh=nil end
    if r.cracks then r.cracks:Destroy() r.cracks=nil end
end
function V.Entity(r)
    local ent=Entity(r.entityIndex)
    if not IsValid(ent) then return end
    if r.native then return ent:GetClass()=="func_breakable" and ent or nil end
    if ent:GetClass()=="nlglass_pane" or scripted_ents.IsBasedOn(ent:GetClass(),"nlglass_pane") then return ent end
end
function V.Attach(r)
    local ent=V.Entity(r)
    if not IsValid(ent) then return end
    if r.native then return end
    -- The server remains authoritative. An identical frozen client copy lets prediction/traces
    -- meet the remaining cells instead of the placeholder model's box or a vanished whole pane.
    local polys=F.Remaining(r.state)
    if #polys==0 then ent:PhysicsDestroy() ent:SetNotSolid(true) return end
    ent:PhysicsInitMultiConvex(G.Convexes(polys,r.state.def.thickness))
    ent:EnableCustomCollisions(true) ent:SetSolid(SOLID_VPHYSICS)
    local phys=ent:GetPhysicsObject()
    if IsValid(phys) then phys:EnableMotion(false) ent:SetNotSolid(false) else ent:SetNotSolid(true) end
end
function V.Build(r)
    destroy(r)
    local polys=F.Remaining(r.state)
    if #polys>0 and not r.native then
        r.mesh=Mesh() r.mesh:BuildFromTriangles(G.Triangles(polys,r.state.def.thickness))
    end
    local triangles={}
    local function tri(a,b,c,normal)
        for _,v in ipairs({a,b,c}) do triangles[#triangles+1]={pos=v,normal=normal,u=v.x/64,v=v.y/64} end
    end
    for _,line in ipairs(F.Cracks(r.state)) do
        local a,b=line[1],line[2]
        local dx,dy=b[1]-a[1],b[2]-a[2]
        local length=math.sqrt(dx*dx+dy*dy)
        if length>0.001 then
            local width=line.sharp and 0.10 or 0.065
            local nx,ny=-dy/length*width,dx/length*width
            for _,side in ipairs({-1,1}) do
                local z=side*(r.state.def.thickness/2+0.015)
                local p,q,s,t=Vector(a[1]+nx,a[2]+ny,z),Vector(b[1]+nx,b[2]+ny,z),
                    Vector(b[1]-nx,b[2]-ny,z),Vector(a[1]-nx,a[2]-ny,z)
                tri(p,q,s,Vector(0,0,side)) tri(p,s,t,Vector(0,0,side))
            end
        end
    end
    if #triangles>0 then r.cracks=Mesh() r.cracks:BuildFromTriangles(triangles) end
    r.material=Material(r.frame.material)
    V.Attach(r)
end
function V.Store(r)
    local old=V.records[r.id]
    if old then destroy(old) end
    V.records[r.id]=r V.Build(r)
    return r
end
local function sync()
    if (V.syncAt or -10)>CurTime()-2 then return end
    V.syncAt=CurTime() net.Start("nlglass_sync") net.SendToServer()
end
net.Receive("nlglass_state",function() V.Store(P.ReadRecord()) end)
net.Receive("nlglass_hit",function()
    local id,revision=net.ReadUInt(32),net.ReadUInt(32)
    local breaking=net.ReadBool()
    local before=breaking and P.ReadRecord() or nil
    local impact,forceAll,native=P.ReadImpact(),net.ReadBool(),net.ReadBool()
    local r=V.records[id]
    if before then r=V.Store(before) end
    if not r or r.state.revision~=revision then sync() return end
    local pieces=F.Apply(r.state,impact,forceAll,native)
    V.Build(r)
    if #pieces>0 then
        for _,piece in ipairs(pieces) do piece.velocity=G.WorldVector(r.frame,piece.velocity) piece.spin=G.WorldVector(r.frame,piece.spin) end
        if NLGlassDebris then NLGlassDebris.Spawn(r.frame,pieces) end
        local point=G.WorldPoint(r.frame,Vector(impact.x,impact.y,0))
        sound.Play("physics/glass/glass_sheet_break"..(impact.seed%3+1)..".wav",point,75,100)
        local effect=EffectData() effect:SetOrigin(point) effect:SetNormal(G.WorldVector(r.frame,{impact.dx,impact.dy,impact.dz}):GetNormalized())
        util.Effect("GlassImpact",effect)
    end
end)
net.Receive("nlglass_remove",function()
    local id=net.ReadUInt(32) local r=V.records[id]
    if r then destroy(r) V.records[id]=nil end
end)
net.Receive("nlglass_blast",function()
    local origin,radius,speed=net.ReadVector(),net.ReadFloat(),net.ReadFloat()
    if NLGlassDebris then NLGlassDebris.Impulse(origin,radius,speed) end
end)
function V.Clear()
    for _,r in pairs(V.records) do destroy(r) end
    V.records={}
    if NLGlassDebris then NLGlassDebris.Clear() end
end
net.Receive("nlglass_clear",V.Clear)
hook.Add("PreCleanupMap","NLGlass.ClientClear",V.Clear)
hook.Add("ShutDown","NLGlass.ClientClear",V.Clear)
hook.Add("InitPostEntity","NLGlass.Sync",sync)
timer.Simple(0,sync) -- also covers client Lua refresh after the map's InitPostEntity
hook.Add("NetworkEntityCreated","NLGlass.Attach",function(ent)
    for _,r in pairs(V.records) do if r.entityIndex==ent:EntIndex() then V.Attach(r) end end
end)
hook.Add("PostDrawTranslucentRenderables","NLGlass.Draw",function(depth,sky)
    if depth or sky then return end
    local show=GetConVar("rtx_glass_show_cracks")
    for _,r in pairs(V.records) do
        local origin,angles=r.frame.origin,r.frame.angles
        local ent=V.Entity(r)
        if r.localOrigin and IsValid(ent) then origin,angles=LocalToWorld(r.localOrigin,r.localAngles,ent:GetPos(),ent:GetAngles()) end
        local matrix=Matrix() matrix:SetTranslation(origin) matrix:SetAngles(angles)
        cam.PushModelMatrix(matrix)
        local color=r.frame.color or color_white
        render.SetColorModulation(color.r/255,color.g/255,color.b/255) render.SetBlend(color.a/255)
        if r.mesh then render.SetMaterial(r.material) r.mesh:Draw() end
        render.SetColorModulation(1,1,1) render.SetBlend(1)
        if r.cracks and (not show or show:GetBool()) then render.SetMaterial(frost) r.cracks:Draw() end
        cam.PopModelMatrix()
    end
end)
return V
