-- MIT. Cached pane/crack geometry and deterministic replay; debris uses only G1-B's public API.
local previous=NLGlass.Client
if previous and previous.Clear then previous.Clear() end
local V={records={},byIndex={},syncTimes={},DRAW_DISTANCE=8192}
NLGlass.Client=V
local F,G,P=NLGlass.Fracture,NLGlass.Geometry,NLGlass.Protocol
local frost=CreateMaterial("nlglass_frost","UnlitGeneric",{["$basetexture"]="models/debug/debugwhite",
    ["$translucent"]="1",["$alpha"]="0.65",["$color"]="[0.65 0.72 0.76]",["$nocull"]="1"})
local showCracks=GetConVar("rtx_glass_show_cracks")
local function destroy(r)
    if r.mesh then r.mesh:Destroy() r.mesh=nil end
    if r.cracks then r.cracks:Destroy() r.cracks=nil end
end
function V.Entity(r,candidate)
    local ent=candidate or r.entity
    if not IsValid(ent) then ent=Entity(r.entityIndex) end
    if not IsValid(ent) then return end
    local class=ent:GetClass()
    if r.native then return class=="func_breakable" and ent or nil end
    if class=="nlglass_pane" or scripted_ents.IsBasedOn(class,"nlglass_pane") then return ent end
end
function V.Pose(r)
    local ent=r.entity
    if r.localOrigin and IsValid(ent) then
        local position,angles=ent:GetPos(),ent:GetAngles()
        if position==r.posePosition and angles==r.poseAngles then return end
        r.posePosition,r.poseAngles=position,angles
        r.frame.origin,r.frame.angles=LocalToWorld(r.localOrigin,r.localAngles,position,angles)
        r.matrix:SetTranslation(r.frame.origin) r.matrix:SetAngles(r.frame.angles)
    end
end
function V.Attach(r,rebuild,candidate)
    local ent=candidate and V.Entity(r,candidate) or r.entity
    if not IsValid(ent) then ent=V.Entity(r) end
    local changed=ent~=r.entity
    r.entity=ent
    if not IsValid(ent) then return end
    if changed then r.posePosition=nil end
    if r.native then return end
    if not changed and not rebuild then return end
    -- The server remains authoritative. An identical frozen client copy lets prediction/traces
    -- meet the remaining cells instead of the placeholder model's box or a vanished whole pane.
    local polys=F.Remaining(r.state)
    if #polys==0 then ent:PhysicsDestroy() ent:SetNotSolid(true) return end
    ent:PhysicsInitMultiConvex(G.Convexes(polys,r.state.def.thickness))
    ent:EnableCustomCollisions(true) ent:SetSolid(SOLID_VPHYSICS)
    local phys=ent:GetPhysicsObject()
    if IsValid(phys) then phys:EnableMotion(false) ent:SetNotSolid(false) else ent:SetNotSolid(true) end
end
function V.Build(r,collisionChanged)
    if r.builtRevision==r.state.visualRevision then V.Attach(r,collisionChanged) return end
    local polys=F.Remaining(r.state)
    if r.meshCells~=r.state.cells then
        if r.mesh then r.mesh:Destroy() r.mesh=nil end
        if #polys>0 and not r.native then
            r.mesh=Mesh() r.mesh:BuildFromTriangles(G.Triangles(polys,r.state.def.thickness))
        end
        r.meshCells=r.state.cells
    end
    if r.cracks then r.cracks:Destroy() r.cracks=nil end
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
    r.builtRevision=r.state.visualRevision
    V.Attach(r,collisionChanged)
    V.Pose(r)
end
function V.Store(r,deferBuild)
    local old=V.records[r.id]
    if old then destroy(old) V.byIndex[old.entityIndex]=nil end
    V.records[r.id]=r V.byIndex[r.entityIndex]=r
    r.material=Material(r.frame.material)
    r.matrix=Matrix() r.matrix:SetTranslation(r.frame.origin) r.matrix:SetAngles(r.frame.angles)
    local radius=0
    for _,p in ipairs(r.state.def.outline) do radius=math.max(radius,p[1]^2+p[2]^2) end
    r.radius=math.sqrt(radius+(r.state.def.thickness/2)^2)
    local color=r.frame.color or color_white
    r.red,r.green,r.blue,r.alpha=color.r/255,color.g/255,color.b/255,color.a/255
    if not deferBuild then V.Build(r,true) end
    -- A map or session with glass: have the broken-glass world ready before the first break.
    if NLGlassDebris and NLGlassDebris.Prepare then NLGlassDebris.Prepare() end
    return r
end
local function sync(id)
    if (V.syncTimes[id] or -10)>CurTime()-2 then return end
    V.syncTimes[id]=CurTime() net.Start("nlglass_sync") net.WriteUInt(id,32) net.SendToServer()
end
local function initialSync()
    if V.initialRequested then return end
    V.initialRequested=true sync(0)
end
net.Receive("nlglass_state",function()
    local r=P.ReadRecord() local old=V.records[r.id]
    if not old or r.state.revision>=old.state.revision then V.Store(r) end
end)
net.Receive("nlglass_hit",function()
    local id,revision=net.ReadUInt(32),net.ReadUInt(32)
    local breaking=net.ReadBool()
    local before=breaking and P.ReadRecord() or nil
    local impact,forceAll,native=P.ReadImpact(),net.ReadBool(),net.ReadBool()
    local r=V.records[id]
    if r and r.state.revision>revision then return end -- stale/repeated event
    if before and (not r or r.state.revision~=revision) then r=V.Store(before,true) end
    if not r or r.state.revision~=revision then sync(id) return end
    local pieces,_,broke=F.Apply(r.state,impact,forceAll,native)
    V.Build(r,broke)
    V.Pose(r)
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
    if r then destroy(r) V.records[id]=nil V.byIndex[r.entityIndex]=nil end
end)
net.Receive("nlglass_blast",function()
    local origin,radius,speed=net.ReadVector(),net.ReadFloat(),net.ReadFloat()
    if NLGlassDebris then NLGlassDebris.Impulse(origin,radius,speed) end
end)
function V.Clear()
    for _,r in pairs(V.records) do destroy(r) end
    V.records={} V.byIndex={} V.syncTimes={}
    if NLGlassDebris then NLGlassDebris.Clear() end
end
net.Receive("nlglass_clear",V.Clear)
hook.Add("PreCleanupMap","NLGlass.ClientClear",V.Clear)
hook.Add("ShutDown","NLGlass.ClientClear",V.Clear)
hook.Add("InitPostEntity","NLGlass.Sync",initialSync)
if previous then timer.Simple(0,initialSync) end -- refresh only; join uses its one readiness request
hook.Add("NetworkEntityCreated","NLGlass.Attach",function(ent)
    local r=V.byIndex[ent:EntIndex()]
    if r then
        r.entity=nil V.Attach(r,true,ent) V.Pose(r)
    end
end)
hook.Add("EntityRemoved","NLGlass.Detach",function(ent)
    local r=V.byIndex[ent:EntIndex()]
    if r and r.entity==ent then r.entity=nil r.posePosition=nil end
end)
hook.Add("PostDrawTranslucentRenderables","NLGlass.Draw",function(depth,sky)
    if depth or sky then return end
    local eye,forward=EyePos(),EyeVector()
    local show=showCracks and showCracks:GetBool()
    for _,r in pairs(V.records) do
        V.Pose(r)
        local delta=r.frame.origin-eye
        if delta:LengthSqr()<=(V.DRAW_DISTANCE+r.radius)^2 and delta:Dot(forward)>=-r.radius then
            cam.PushModelMatrix(r.matrix)
            render.SetColorModulation(r.red,r.green,r.blue) render.SetBlend(r.alpha)
            if r.mesh then render.SetMaterial(r.material) r.mesh:Draw() end
            render.SetColorModulation(1,1,1) render.SetBlend(1)
            if r.cracks and show then render.SetMaterial(frost) r.cracks:Draw() end
            cam.PopModelMatrix()
        end
    end
end)
return V
