-- MIT. Fresh implementation of the existing tool name: convex prop envelope or a new flat pane.
TOOL.Category="Glass Rewrite"
TOOL.Name="#Tool.procedural_glass_tool.name"
TOOL.ClientConVar={width="96",height="64",thickness="1",kind="annealed",strength="1"}
local I=CLIENT and NLGlass.I18n
local L=I and I.L or function(text) return text end
if CLIENT then
    I.Phrase("Tool.procedural_glass_tool.name",L("Glass tool"))
    I.Phrase("Tool.procedural_glass_tool.desc",L("Convert a prop to a convex glass pane, or create a pane."))
    I.Phrase("Tool.procedural_glass_tool.left",L("Left: convert a prop or reset the kind and strength of a pane"))
    I.Phrase("Tool.procedural_glass_tool.right",L("Right: create a pane at the surface"))
    TOOL.Information={{name="left"},{name="right"}}
end
local function permitted(ent,owner)
    return not ent.CPPICanTool or ent:CPPICanTool(owner,"procedural_glass_tool")
end
local function properties(tool,outline,thickness)
    local def=NLGlass.Server.Definition(outline,thickness,tool:GetClientInfo("kind")=="tempered" and "tempered" or "annealed",
        math.Clamp(tool:GetClientNumber("strength",1),0.1,10))
    return NLGlass.Geometry.ValidDefinition(def)
end
local function finish(pane,owner)
    pane:SetCreator(owner)
    if pane.CPPISetOwner then pane:CPPISetOwner(owner) end
    undo.Create("Glass") undo.AddEntity(pane) undo.SetPlayer(owner) undo.Finish()
    cleanup.Add(owner,"props",pane) owner:AddCount("props",pane)
end
function TOOL:LeftClick(trace)
    local ent,owner=trace.Entity,self:GetOwner()
    if not IsValid(ent) or not permitted(ent,owner) then return false end
    if ent:GetClass()=="nlglass_pane" or scripted_ents.IsBasedOn(ent:GetClass(),"nlglass_pane") then
        if CLIENT then return true end
        local def=properties(self,ent.NLGlassDefinition.outline,ent.NLGlassDefinition.thickness)
        if not def then return false end
        local old=NLGlass.Server.byEntity[ent] if old then NLGlass.Server.Forget(old) end
        ent.NLGlassDefinition=def ent.NLGlassFrame=nil ent:Initialize()
        return true
    end
    if ent:GetClass()~="prop_physics" then return false end
    if CLIENT then return true end
    if not owner:CheckLimit("props") then return false end
    local frame,outline,thickness=NLGlass.Geometry.FromEntity(ent,true)
    if not frame then return false end
    local def=properties(self,outline,thickness)
    if not def then return false end
    local pane=ents.Create("nlglass_pane")
    if not IsValid(pane) then return false end
    pane.NLGlassDefinition=def pane.NLGlassFrame=frame
    pane:SetPos(frame.origin) pane:SetAngles(frame.angles) pane:SetColor(ent:GetColor()) pane:Spawn()
    if not IsValid(pane) or not NLGlass.Server.byEntity[pane] then return false end
    local creator=ent.CPPIGetOwner and ent:CPPIGetOwner() or owner
    finish(pane,owner)
    if IsValid(creator) and pane.CPPISetOwner then pane:CPPISetOwner(creator) end
    ent:Remove()
    return true
end
function TOOL:RightClick(trace)
    if not trace.Hit then return false end
    if CLIENT then return true end
    local owner=self:GetOwner()
    if not owner:CheckLimit("props") then return false end
    local w,h=math.Clamp(self:GetClientNumber("width",96),8,1024),math.Clamp(self:GetClientNumber("height",64),8,1024)
    local t=math.Clamp(self:GetClientNumber("thickness",1),0.25,16)
    local pane=ents.Create("nlglass_pane")
    if not IsValid(pane) then return false end
    pane.NLGlassDefinition=properties(self,{{-w/2,-h/2},{w/2,-h/2},{w/2,h/2},{-w/2,h/2}},t)
    if not pane.NLGlassDefinition then pane:Remove() return false end
    local normal=trace.HitNormal
    local u=math.abs(normal.z)<0.9 and Vector(0,0,1):Cross(normal):GetNormalized() or Vector(1,0,0)
    pane:SetPos(trace.HitPos+normal*(t/2+0.05)) pane:SetAngles(u:AngleEx(normal)) pane:Spawn()
    if not IsValid(pane) then return false end
    finish(pane,owner)
    return true
end
function TOOL.BuildCPanel(panel)
    panel:Help(L("Left: convert a prop or reset the kind and strength of a pane"))
    panel:Help(L("Right: create a pane at the surface"))
    panel:Help(L("Props become a flat convex envelope; complex shapes are simplified."))
    local box=panel:ComboBox(L("Glass kind"),"procedural_glass_tool_kind")
    box:AddChoice(L("Annealed glass"),"annealed") box:AddChoice(L("Tempered glass"),"tempered")
    box.OnSelect=function(_,_,_,value) RunConsoleCommand("procedural_glass_tool_kind",value) end
    for _,s in ipairs({{L("Width"),"width",8,1024,0},{L("Height"),"height",8,1024,0},{L("Thickness"),"thickness",0.25,16,2},{L("Glass strength"),"strength",0.1,10,2}}) do
        panel:Help(s[1]) panel:NumSlider("","procedural_glass_tool_"..s[2],s[3],s[4],s[5])
    end
end
