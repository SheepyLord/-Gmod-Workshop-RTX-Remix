-- MIT. Conservative Source fallback: at most 64 pieces, world collision only.
local F = { limit = 64 }
function F.Spawn(piece)
    if type(ents.CreateClientProp) ~= "function" then return false end
    local ent = ents.CreateClientProp("models/hunter/plates/plate1x1.mdl")
    if not IsValid(ent) then return false end
    local ok = pcall(function()
        ent:SetNoDraw(true)
        ent:SetPos(piece.position)
        ent:SetAngles(piece.angles)
        if piece.geometry.hulls then
            if not ent.PhysicsInitMultiConvex then error("client compound physics unavailable",0) end
            ent:PhysicsInitMultiConvex(piece.geometry.hulls)
        else ent:PhysicsInitConvex(piece.geometry.hull) end
        if ent.EnableCustomCollisions then ent:EnableCustomCollisions(true) end
        ent:SetMoveType(MOVETYPE_VPHYSICS)
        ent:SetSolid(SOLID_VPHYSICS)
        -- WORLD prevents contact with gameplay bodies. The fallback forgoes inter-piece contact.
        ent:SetCollisionGroup(COLLISION_GROUP_WORLD)
        local phys = ent:GetPhysicsObject()
        if not IsValid(phys) then error("client convex physics unavailable", 0) end
        phys:SetMaterial("glass")
        phys:SetMass(math.max(.01, piece.mass))
        phys:SetVelocity(piece.velocity)
        local spin = WorldToLocal(piece.spin, angle_zero, vector_origin, piece.angles)
        phys:AddAngleVelocity(spin)
        phys:Wake()
    end)
    if not ok then ent:Remove(); return false end
    piece.entity = ent
    return true
end
function F.Update(piece)
    if not IsValid(piece.entity) then return false end
    piece.position:Set(piece.entity:GetPos())
    piece.angles:Set(piece.entity:GetAngles())
    local phys = piece.entity:GetPhysicsObject()
    if not IsValid(phys) then return false end
    piece.sleeping = phys:IsAsleep()
    return true
end
function F.Remove(piece)
    if IsValid(piece.entity) then piece.entity:Remove() end
    piece.entity = nil
end
function F.Impulse(piece, origin, radius, speed)
    if not IsValid(piece.entity) then return end
    local delta = piece.position - origin
    local distance = delta:Length()
    if distance >= radius then return end
    local phys = piece.entity:GetPhysicsObject()
    if not IsValid(phys) then return end
    local direction = distance > .001 and delta / distance or Vector(0, 0, 1)
    phys:Wake()
    phys:AddVelocity(direction * (speed * (1 - distance / radius)))
    piece.sleeping = false
end
return F
