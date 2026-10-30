-- Localized by the native-loader companion when bundled; standalone use keeps the English.
local bundle_i18n = CLIENT and file.Exists("nativeloader/i18n.lua", "LUA")
    and include("nativeloader/i18n.lua") or nil
local NL = bundle_i18n and bundle_i18n.A or function(text) return text end
local NP = bundle_i18n and bundle_i18n.P or function(text) return text end
local function NN(text) return text end
if SERVER then return end

-- Glass Rewrite Settings Panel
local PANEL = {}

function PANEL:Init()
    self:SetSize(400, 600)
    self:SetTitle(NL("Glass Rewrite Remixed Settings"))
    self:SetDeleteOnClose(false)
    self:SetDraggable(true)
    self:ShowCloseButton(true)
    self:SetScreenLock(true)
    
    -- Create main container
    local scroll = vgui.Create("DScrollPanel", self)
    scroll:Dock(FILL)
    scroll:DockMargin(5, 5, 5, 5)
    
    -- Title
    local title = vgui.Create("DLabel", scroll)
    title:SetText(NL("Glass Rewrite Remixed Settings"))
    title:SetFont("DermaDefaultBold")
    title:SetTextColor(Color(255, 255, 255))
    title:SizeToContents()
    title:DockMargin(0, 0, 0, 10)
    title:Dock(TOP)
    
    -- Settings Sections
    self:CreateVisualSection(scroll)
    self:CreatePhysicsSection(scroll)
    self:CreatePlayerSection(scroll)
    self:CreateAdvancedSection(scroll)
    
    -- Apply/Reset buttons
    self:CreateButtonSection(scroll)
end



function PANEL:CreateVisualSection(parent)
    local visual = vgui.Create("DCollapsibleCategory", parent)
    visual:SetLabel(NL("Visual Effects"))
    visual:SetExpanded(true)
    visual:Dock(TOP)
    visual:DockMargin(0, 0, 0, 5)
    
    local visual_panel = vgui.Create("DPanel", visual)
    visual_panel:SetDrawBackground(false)
    visual:SetContents(visual_panel)
    
    -- Show Cracks
    local cracks_check = vgui.Create("DCheckBoxLabel", visual_panel)
    cracks_check:SetText(NL("Show Cracks Before Breaking"))
    cracks_check:SetConVar("rtx_glass_show_cracks")
    cracks_check:SizeToContents()
    cracks_check:Dock(TOP)
    cracks_check:DockMargin(5, 2, 5, 2)
    
    -- Crack Delay
    self:CreateSlider(visual_panel, NL("Crack Delay"), "rtx_glass_crack_delay", 0.05, 1.0, 2, NL("Time between cracks appearing and glass breaking"))
    
    -- Shard Count
    self:CreateSlider(visual_panel, NL("Shard Count"), "rtx_glass_shard_count", 1, 12, 0, NL("Number of pieces glass breaks into"))
    
    -- Velocity Transfer
    self:CreateSlider(visual_panel, NL("Velocity Transfer"), "rtx_glass_velocity_transfer", 0.1, 3.0, 2, NL("How forcefully glass fragments scatter"))
end

function PANEL:CreatePhysicsSection(parent)
    local physics = vgui.Create("DCollapsibleCategory", parent)
    physics:SetLabel(NL("Physics Settings"))
    physics:SetExpanded(true)
    physics:Dock(TOP)
    physics:DockMargin(0, 0, 0, 5)
    
    local physics_panel = vgui.Create("DPanel", physics)
    physics_panel:SetDrawBackground(false)
    physics:SetContents(physics_panel)
    
    -- Glass Rigidity
    self:CreateSlider(physics_panel, NL("Glass strength"), "rtx_glass_rigidity", 0, 200, 0, NL("How much damage glass can take before breaking"))
    
    -- Mass Factor
    self:CreateSlider(physics_panel, NL("Mass Factor"), "rtx_glass_mass_factor", 0.1, 3.0, 1, NL("How much object mass affects impact force"))
end

function PANEL:CreatePlayerSection(parent)
    local player = vgui.Create("DCollapsibleCategory", parent)
    player:SetLabel(NL("Player Collision"))
    player:SetExpanded(true)
    player:Dock(TOP)
    player:DockMargin(0, 0, 0, 5)
    
    local player_panel = vgui.Create("DPanel", player)
    player_panel:SetDrawBackground(false)
    player:SetContents(player_panel)
    
    -- Player Mass
    self:CreateSlider(player_panel, NL("Player Mass (kg)"), "rtx_glass_player_mass", 30, 150, 0, NL("Player mass for glass breaking calculations"))
    
    -- Player Break Speed
    self:CreateSlider(player_panel, NL("Min Break Speed"), "rtx_glass_player_break_speed", 50, 400, 0, NL("Minimum player speed to break glass"))
end

function PANEL:CreateAdvancedSection(parent)
    local advanced = vgui.Create("DCollapsibleCategory", parent)
    advanced:SetLabel(NL("Advanced"))
    advanced:SetExpanded(false)
    advanced:Dock(TOP)
    advanced:DockMargin(0, 0, 0, 5)
    
    local advanced_panel = vgui.Create("DPanel", advanced)
    advanced_panel:SetDrawBackground(false)
    advanced:SetContents(advanced_panel)
    
    -- Expensive Shards
    local expensive_check = vgui.Create("DCheckBoxLabel", advanced_panel)
    expensive_check:SetText(NL("Detailed collisions for small glass shards (higher cost)"))
    expensive_check:SetConVar("rtx_glass_expensive_shards")
    expensive_check:SizeToContents()
    expensive_check:Dock(TOP)
    expensive_check:DockMargin(5, 5, 5, 10)
end

function PANEL:CreateButtonSection(parent)
    local button_panel = vgui.Create("DPanel", parent)
    button_panel:SetTall(40)
    button_panel:SetDrawBackground(false)
    button_panel:Dock(TOP)
    button_panel:DockMargin(0, 10, 0, 0)
    
    local reset_btn = vgui.Create("DButton", button_panel)
    reset_btn:SetText(NL("Reset to Defaults"))
    reset_btn:SetSize(120, 30)
    reset_btn:SetPos(5, 5)
    reset_btn.DoClick = function()
        self:ResetToDefaults()
        surface.PlaySound("buttons/button14.wav")
    end
    
    local test_btn = vgui.Create("DButton", button_panel)
    test_btn:SetText(NL("Test Settings"))
    test_btn:SetSize(120, 30)
    test_btn:SetPos(135, 5)
    test_btn.DoClick = function()
        RunConsoleCommand("glass_settings")
        surface.PlaySound("buttons/button9.wav")
    end
    
    local debug_btn = vgui.Create("DButton", button_panel)
    debug_btn:SetText(NL("Player Debug"))
    debug_btn:SetSize(120, 30)
    debug_btn:SetPos(265, 5)
    debug_btn.DoClick = function()
        RunConsoleCommand("glass_player_debug")
        surface.PlaySound("buttons/button9.wav")
    end
end

function PANEL:CreateSlider(parent, label, convar, min_val, max_val, decimals, tooltip)
    local slider = vgui.Create("DNumSlider", parent)
    slider:SetText(label)
    slider:SetConVar(convar)
    slider:SetMin(min_val)
    slider:SetMax(max_val)
    slider:SetDecimals(decimals)
    slider:SetTooltip(tooltip)
    slider:Dock(TOP)
    slider:DockMargin(5, 2, 5, 2)
    slider:SetTall(25)
    return slider
end

function PANEL:ResetToDefaults()
    local defaults = {
        rtx_glass_show_cracks = 1,
        rtx_glass_crack_delay = 0.05,
        rtx_glass_shard_count = 12,
        rtx_glass_rigidity = 0,
        rtx_glass_mass_factor = 0.8,
        rtx_glass_velocity_transfer = 2.0,
        rtx_glass_player_mass = 80,
        rtx_glass_player_break_speed = 100,
        rtx_glass_expensive_shards = 1
    }
    
    for convar, value in pairs(defaults) do
        RunConsoleCommand(convar, tostring(value))
    end
    chat.AddText(Color(100, 255, 100), "[Glass] " .. NL("Settings reset to defaults!"))
end

vgui.Register("GlassSettingsPanel", PANEL, "DFrame")

-- Add to spawnmenu
hook.Add("PopulateToolMenu", "GlassRewriteSettings", function()
    spawnmenu.AddToolMenuOption("Utilities", "Glass Rewrite Remixed", "GlassSettings", NL("Settings"), "", "", function(panel)
        panel:ClearControls()
        
        panel:AddControl("Header", {Description = NL("Glass Rewrite Remixed\nRealistic glass destruction system")})
        
        -- Quick Settings Button
        panel:AddControl("Button", {
            Label = NL("Open Settings Panel"),
            Command = "glass_open_panel"
        })
        
        -- Debug Tools
        panel:AddControl("Header", {Description = NL("Debug Tools:")})
        
        panel:AddControl("Button", {
            Label = NL("Show Current Settings"),
            Command = "glass_settings"
        })
        
        panel:AddControl("Button", {
            Label = NL("Player Impact Analysis"),
            Command = "glass_player_debug"
        })
        
        -- Manual Controls
        panel:AddControl("Header", {Description = NL("Manual Controls:")})
        
        panel:AddControl("CheckBox", {
            Label = NL("Show Cracks"),
            Command = "rtx_glass_show_cracks"
        })
        
        panel:AddControl("Slider", {
            Label = NL("Glass strength"),
            Command = "rtx_glass_rigidity",
            Type = "Integer",
            Min = "0",
            Max = "200"
        })
        
        panel:AddControl("Slider", {
            Label = NL("Shard Count"),
            Command = "rtx_glass_shard_count",
            Type = "Integer", 
            Min = "1",
            Max = "12"
        })
        
        panel:AddControl("Slider", {
            Label = NL("Velocity Transfer"),
            Command = "rtx_glass_velocity_transfer",
            Type = "Float",
            Min = "0.1",
            Max = "3.0"
        })
    end)
end)

-- Console command to open settings panel
concommand.Add("glass_open_panel", function()
    if IsValid(GLASS_SETTINGS_FRAME) then
        GLASS_SETTINGS_FRAME:Remove()
    end
    
    GLASS_SETTINGS_FRAME = vgui.Create("GlassSettingsPanel")
    GLASS_SETTINGS_FRAME:Center()
    GLASS_SETTINGS_FRAME:MakePopup()
end) 