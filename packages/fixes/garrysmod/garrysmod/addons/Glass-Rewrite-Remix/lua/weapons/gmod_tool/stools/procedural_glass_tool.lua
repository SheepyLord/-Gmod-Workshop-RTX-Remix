-- Localized by the native-loader companion when bundled; standalone use keeps the English.
local bundle_i18n = CLIENT and file.Exists("nativeloader/i18n.lua", "LUA")
    and include("nativeloader/i18n.lua") or nil
local NL = bundle_i18n and bundle_i18n.A or function(text) return text end
local NP = bundle_i18n and bundle_i18n.P or function(text) return text end
local function NN(text) return text end
local function NLC(player, text, ...)
    if NATIVELOADER_LOCALIZED_CHAT then
        NATIVELOADER_LOCALIZED_CHAT(player, text, {...})
    else
        player:ChatPrint(string.format(text, ...))
    end
end
local function NLP(key, text)
    if bundle_i18n then bundle_i18n.RegisterPhrase(key, text)
    elseif CLIENT then language.Add(key, text) end
end
TOOL.Category = NL("Glass Rewrite")
TOOL.Name = "#Tool.procedural_glass_tool.name"

if CLIENT then
	NLP("Tool.procedural_glass_tool.name", NN("Glass tool"))
	NLP("Tool.procedural_glass_tool.desc", NN("Turn props into glass by wrapping the model in a glass mesh"))
	
	TOOL.Information = {{name = "left"}}

	NLP("Tool.procedural_glass_tool.left", NN("Left click on a prop to turn it into destructable glass"))

	function TOOL.BuildCPanel(panel)
		panel:AddControl("label", {
			text = NL("Turns props into glass upon left click"),
		})
	end
end

function TOOL:LeftClick(tr)
	local ent = tr.Entity
	local owner = self:GetOwner()

	if CPPI and ent.CPPICanTool and !ent:CPPICanTool(owner, "remover") then return end

	if ent:GetClass() != "prop_physics" then return end
	if !ent:GetPhysicsObject():IsValid() then return end
	if IsUselessModel(ent:GetModel()) then NLC(owner, NN("Invalid Model")) end

	if SERVER then
		local block = ents.Create("procedural_shard")
        block:SetPos(ent:GetPos())
        block:SetAngles(ent:GetAngles())
        block:SetPhysModel(ent:GetModel())
		block:SetPhysScale(Vector(1, 1, 1))
        block:Spawn()
        block:BuildCollision(util.GetModelMeshes(block:GetPhysModel())[1].triangles)

        local phys = block:GetPhysicsObject()
        if phys then 
			phys:EnableMotion(false) 
		else 
			NLC(owner, NN("Unable to generate physics object"))
		end

		undo.Create("Glass")
			undo.AddEntity(block)
			undo.SetPlayer(owner)
		undo.Finish()

		 // prop protection support
		if CPPI then
			local owner = ent:CPPIGetOwner()
			if owner and owner:IsValid() then
				block:CPPISetOwner(owner)
			end
		end

		// remove original entity because we just turned it to glass
		SafeRemoveEntity(ent)
	end

	return true
end

if bundle_i18n then
    bundle_i18n.RegisterPhrase("Glass", NN("Glass"))
end
