-- MIT. One server entity per pane; there are never server entities for broken pieces.
ENT.Type="anim"
ENT.Base="base_anim"
ENT.PrintName="#nlglass_pane"
ENT.Category="Glass Rewrite"
ENT.Spawnable=true -- the default follows the setting; explicit presets offer both kinds
ENT.RenderGroup=RENDERGROUP_TRANSLUCENT
function ENT:UpdateTransmitState() return TRANSMIT_ALWAYS end
function ENT:SpawnFunction(ply,trace,class)
    if not trace.Hit then return end
    local ent=ents.Create(class or "nlglass_pane")
    ent:SetPos(trace.HitPos+trace.HitNormal*2)
    local normal=trace.HitNormal
    local tangent=math.abs(normal.z)<0.9 and Vector(0,0,1):Cross(normal):GetNormalized() or Vector(1,0,0)
    ent:SetAngles(tangent:AngleEx(normal))
    ent:SetCreator(ply) ent:Spawn() ent:Activate()
    return ent
end
