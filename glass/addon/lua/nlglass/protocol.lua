-- MIT. Bounded state, compact impacts and the frame shared with the debris API.
local P={Kinds={sharp=0,blunt=1,blast=2},Names={[0]="sharp",[1]="blunt",[2]="blast"}}
function P.WriteImpact(h)
    net.WriteInt(math.floor(h.x*1024+0.5),24) net.WriteInt(math.floor(h.y*1024+0.5),24)
    net.WriteUInt(h.energy,31) net.WriteUInt(h.seed,31) net.WriteUInt(P.Kinds[h.kind] or 1,2)
    for _,v in ipairs({h.dx,h.dy,h.dz}) do net.WriteInt(math.floor(v*1024+0.5),12) end
end
function P.ReadImpact()
    local h={x=net.ReadInt(24)/1024,y=net.ReadInt(24)/1024,energy=net.ReadUInt(31),seed=net.ReadUInt(31),kind=P.Names[net.ReadUInt(2)] or "blunt"}
    h.dx,h.dy,h.dz=net.ReadInt(12)/1024,net.ReadInt(12)/1024,net.ReadInt(12)/1024
    return h
end
function P.WriteRecord(r)
    local s,d=r.state,r.state.def
    net.WriteUInt(r.id,32) net.WriteUInt(r.entityIndex or 0,16) net.WriteBool(r.native or false)
    net.WriteVector(r.frame.origin) net.WriteAngle(r.frame.angles)
    net.WriteVector(r.localOrigin or Vector()) net.WriteAngle(r.localAngles or angle_zero)
    net.WriteString(r.frame.material or "models/props_combine/health_charger_glass") net.WriteString(r.frame.sourceMaterial or "")
    local c=r.frame.color or color_white
    net.WriteUInt(c.r,8) net.WriteUInt(c.g,8) net.WriteUInt(c.b,8) net.WriteUInt(c.a,8)
    net.WriteUInt(#d.outline,5)
    for _,p in ipairs(d.outline) do net.WriteInt(math.floor(p[1]*1024+0.5),24) net.WriteInt(math.floor(p[2]*1024+0.5),24) end
    net.WriteFloat(d.thickness) net.WriteFloat(d.strength) net.WriteBool(d.kind=="tempered")
    net.WriteFloat(d.piece_size) net.WriteFloat(d.velocity_transfer)
    net.WriteUInt(s.revision,32) net.WriteUInt(s.damage,31) net.WriteBool(s.all) net.WriteUInt(#s.impacts,4)
    for _,h in ipairs(s.impacts) do P.WriteImpact(h) net.WriteUInt(h.rays,5) net.WriteUInt(h.hole,8) end
    net.WriteUInt(s.pending or 0,31) net.WriteUInt(s.retiredEnergy or 0,31)
    -- A bounded pane topology, not a history replay or a stream of moving debris meshes.
    -- Share vertex coordinates across cells; a typical near-cap snapshot is ~10 KiB.
    local vertices,indices={},{}
    local shapes={}
    for _,c in ipairs(s.cells) do shapes[#shapes+1]=c end
    for _,g in ipairs(s.groups) do shapes[#shapes+1]=g end
    for _,c in ipairs(shapes) do for _,p in ipairs(c.poly) do
        local key=p[1]..":"..p[2]
        if not indices[key] then vertices[#vertices+1]=p indices[key]=#vertices end
    end end
    net.WriteUInt(#vertices,16)
    for _,p in ipairs(vertices) do net.WriteInt(math.floor(p[1]*1024+0.5),24) net.WriteInt(math.floor(p[2]*1024+0.5),24) end
    net.WriteUInt(s.nextCellID,32)
    local function shape(c)
        net.WriteUInt(c.id,32)
        net.WriteUInt(#c.poly,8)
        for _,p in ipairs(c.poly) do net.WriteUInt(indices[p[1]..":"..p[2]],16) end
        for slot=1,NLGlass.Fracture.MAX_IMPACTS do net.WriteUInt(c.tags[slot] or 0,5) end
    end
    net.WriteUInt(#s.cells,10)
    for _,c in ipairs(s.cells) do shape(c) end
    net.WriteUInt(#s.groups,10)
    for _,g in ipairs(s.groups) do
        shape(g) net.WriteUInt(#g.children,10)
        for _,id in ipairs(g.children) do net.WriteUInt(id,32) end
    end
end
function P.ReadRecord()
    local r={id=net.ReadUInt(32),entityIndex=net.ReadUInt(16),native=net.ReadBool()}
    r.frame={origin=net.ReadVector(),angles=net.ReadAngle()}
    r.localOrigin,r.localAngles=net.ReadVector(),net.ReadAngle()
    r.frame.material,r.frame.sourceMaterial=net.ReadString(),net.ReadString()
    r.frame.color=Color(net.ReadUInt(8),net.ReadUInt(8),net.ReadUInt(8),net.ReadUInt(8))
    local d={outline={}}
    for i=1,net.ReadUInt(5) do d.outline[i]={net.ReadInt(24)/1024,net.ReadInt(24)/1024} end
    d.thickness,d.strength,d.kind=net.ReadFloat(),net.ReadFloat(),net.ReadBool() and "tempered" or "annealed"
    d.piece_size,d.velocity_transfer=net.ReadFloat(),net.ReadFloat()
    local revision,damage,all=net.ReadUInt(32),net.ReadUInt(31),net.ReadBool()
    local impacts={}
    for i=1,net.ReadUInt(4) do impacts[i]=P.ReadImpact() impacts[i].rays=net.ReadUInt(5) impacts[i].hole=net.ReadUInt(8) end
    local pending,retired=net.ReadUInt(31),net.ReadUInt(31)
    local vertices={}
    for i=1,net.ReadUInt(16) do vertices[i]={net.ReadInt(24)/1024,net.ReadInt(24)/1024} end
    local nextCellID=net.ReadUInt(32)
    local function shape()
        local c={poly={},tags={},id=net.ReadUInt(32)}
        for j=1,net.ReadUInt(8) do c.poly[j]=vertices[net.ReadUInt(16)] end
        for slot=1,NLGlass.Fracture.MAX_IMPACTS do local ring=net.ReadUInt(5) if ring>0 then c.tags[slot]=ring end end
        return c
    end
    local cells,groups={},{}
    for i=1,net.ReadUInt(10) do cells[i]=shape() end
    for i=1,net.ReadUInt(10) do
        local g=shape() groups[i]=g g.children={}
        for j=1,net.ReadUInt(10) do g.children[j]=net.ReadUInt(32) end
    end
    r.state=NLGlass.Fracture.Restore(d,impacts,damage,revision,all,cells,pending,retired,groups,nextCellID)
    return r
end
return P
