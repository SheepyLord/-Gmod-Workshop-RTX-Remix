-- MIT. Frozen collision is rebuilt only when a hole changes.
AddCSLuaFile("shared.lua") AddCSLuaFile("cl_init.lua") include("shared.lua")
local S=NLGlass.Server
function ENT:Initialize()
    self:SetModel("models/hunter/plates/plate1x1.mdl")
    local preset=self.NLGlassPreset or {}
    local w,h=preset.width or 96,preset.height or 64
    local def=self.NLGlassDefinition or S.Definition({{-w/2,-h/2},{w/2,-h/2},{w/2,h/2},{-w/2,h/2}},1,
        preset.kind or NLGlass.Config.Kind("rtx_glass_spawn_kind"))
    local frame=self.NLGlassFrame or {origin=self:GetPos(),angles=self:GetAngles(),material="models/props_combine/health_charger_glass",color=self:GetColor()}
    self.NLGlassDefinition=NLGlass.Geometry.ValidDefinition(def)
    if not self.NLGlassDefinition then self:Remove() return end
    local r=S.Register(self,frame,self.NLGlassDefinition)
    if r then S.Collision(r) else self:Remove() end
end
function ENT:OnTakeDamage(dmg) S.Damage(self,dmg) end
function ENT:PhysicsCollide(data) S.Contact(self,data) end
function ENT:Touch(other) S.Body(self,other) end
function ENT:OnRestore()
    timer.Simple(0,function()
        if not IsValid(self) then return end
        local old=S.byEntity[self] if old then S.Forget(old) end
        self.NLGlassFrame=nil self:Initialize()
    end)
end
function ENT:PreEntityCopy()
    duplicator.StoreEntityModifier(self,"NLGlassPane",self.NLGlassDefinition)
end
duplicator.RegisterEntityModifier("NLGlassPane",function(ply,ent,data)
    if not IsValid(ent) or not ent.NLGlassDefinition then return end
    local def=NLGlass.Geometry.ValidDefinition(data)
    if not def then return end
    local old=S.byEntity[ent] if old then S.Forget(old) end
    ent.NLGlassDefinition=def ent.NLGlassFrame=nil ent.NLGlassOriginal=nil ent:Initialize()
end)
