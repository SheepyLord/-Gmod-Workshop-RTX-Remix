-- Localized by the native-loader companion when bundled; standalone use keeps the English.
local bundle_i18n = CLIENT and file.Exists("nativeloader/i18n.lua", "LUA")
    and include("nativeloader/i18n.lua") or nil
local NL = bundle_i18n and bundle_i18n.A or function(text) return text end
local NP = bundle_i18n and bundle_i18n.P or function(text) return text end
local function NN(text) return text end
local function NLP(key, text)
    if bundle_i18n then bundle_i18n.RegisterPhrase(key, text)
    elseif CLIENT then language.Add(key, text) end
end
TOOL.Category = NL("Seamless Portals")
TOOL.Name = "#Tool.portal_resizer_tool.name"

if CLIENT then
	NLP("Tool.portal_resizer_tool.name", NN("Portal Resizer"))
	NLP("Tool.portal_resizer_tool.desc", NN("Sets the size of portals"))

	TOOL.ConvarX = CreateClientConVar("seamless_portals_size_x", "100", false, true, "Sets the size of the portal along the X axis", 10, 1000)
	TOOL.ConvarY = CreateClientConVar("seamless_portals_size_y", "100", false, true, "Sets the size of the portal along the Y axis", 10, 1000)
	TOOL.ConvarZ = CreateClientConVar("seamless_portals_size_z", "8", false, true, "Sets the size of the portal along the Z axis", 1, 100)
	TOOL.ConvarSides = CreateClientConVar("seamless_portals_sides", "1", false, true, "Sets the number of sides of the portal", 3, 100)
	TOOL.ConvarB = CreateClientConVar("seamless_portals_backface", "1", false, true, "Sets whether to spawn with a backface or not", 0, 1)

	TOOL.Information = {
		{name = "left"},
	}

	NLP( "Tool.portal_resizer_tool.left", NN("Sets the size of portals"))

	function TOOL.BuildCPanel(panel)
		panel:AddControl("label", {
			text = NL("Sets the size of portals"),
		})
		panel:NumSlider(NL("Portal Size X"), "seamless_portals_size_x", 10, 1000, 1)
		panel:NumSlider(NL("Portal Size Y"), "seamless_portals_size_y", 10, 1000, 1)
		panel:NumSlider(NL("Portal Size Z"), "seamless_portals_size_z", 1, 100, 1)
		panel:NumSlider(NL("Portal Sides"), "seamless_portals_sides", 3, 100, 0)
		panel:CheckBox(NL("Has Backface (Invisible until linked!)"), "seamless_portals_backface")
	end

	local COLOR_GREEN = Color(0, 255, 0, 50)
	function TOOL:DrawHUD()
		local traceTable = util.GetPlayerTrace(self:GetOwner())
		local trace = SeamlessPortals.TraceLine(traceTable)

		if !trace.Entity or trace.Entity:GetClass() != "seamless_portal" then return end	-- dont draw the world or else u crash lol

		local mins, maxs = trace.Entity:OBBMins(), trace.Entity:OBBMaxs()
		mins[3] = mins[3]
		maxs[3] = 0

		cam.Start3D()
			render.SetColorMaterial()
			render.DrawBox(trace.Entity:GetPos(), trace.Entity:GetAngles(), mins, maxs, COLOR_GREEN)
		cam.End3D()
	end
end

function TOOL:LeftClick(trace)
	local traceTable = util.GetPlayerTrace(self:GetOwner())
	local trace = SeamlessPortals.TraceLine(traceTable)

	if !trace.Entity or trace.Entity:GetClass() != "seamless_portal" then return false end
	if CPPI and SERVER then if !trace.Entity:CPPICanTool(self:GetOwner(), "remover") then return false end end
		if CLIENT then return true end
	local sizex = self:GetOwner():GetInfoNum("seamless_portals_size_x", 1)
	local sizey = self:GetOwner():GetInfoNum("seamless_portals_size_y", 1)
	local sizez = self:GetOwner():GetInfoNum("seamless_portals_size_z", 1)
	trace.Entity:SetSize(Vector(math.Clamp(sizex * 0.5, 1, 500), math.Clamp(sizey * 0.5, 1, 500), math.Clamp(sizez, 1, 100)))
	trace.Entity:SetDisableBackface(self:GetOwner():GetInfoNum("seamless_portals_backface", 1) == 0)
	trace.Entity:SetSides(self:GetOwner():GetInfoNum("seamless_portals_sides", 1))
	return true
end

function TOOL:RightClick(trace)
	local traceTable = util.GetPlayerTrace(self:GetOwner())
	local trace = SeamlessPortals.TraceLine(traceTable)

	if !trace.Entity or trace.Entity:GetClass() != "seamless_portal" then return false end
	if CPPI and SERVER then if !trace.Entity:CPPICanTool(self:GetOwner(), "remover") then return false end end
	trace.Entity:SetSize(Vector(50, 50, 8))
	return true
end
