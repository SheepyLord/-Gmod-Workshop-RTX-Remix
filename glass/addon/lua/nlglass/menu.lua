-- MIT. Spawn-menu settings; gameplay changes travel through a validated, admin-only server route.
local L=NLGlass.I18n.L
local function N(text) return text end
local C=NLGlass.Config
local function default(name)
    for _,s in ipairs(C.Settings) do if s[1]==name then return s[2] end end
end
local function setting(name,value)
    for index,s in ipairs(C.Settings) do
        if s[1]==name then
            timer.Create("NLGlass.Setting."..name,0.15,1,function()
                net.Start("nlglass_setting") net.WriteUInt(index,4) net.WriteString(tostring(value)) net.SendToServer()
            end)
            return
        end
    end
end
local function admin() local p=LocalPlayer() return IsValid(p) and p:IsAdmin() end
local function gameplaySlider(panel,text,name,lo,hi,decimals)
    panel:Help(L(text))
    local control=panel:NumSlider("","",lo,hi,decimals)
    control:SetValue(C.Number(name,lo)) control:SetEnabled(admin())
    control.OnValueChanged=function(_,value) setting(name,value) end
    panel.NLGlassResetters[#panel.NLGlassResetters+1]=function()
        local callback=control.OnValueChanged control.OnValueChanged=function() end
        control:SetValue(tonumber(default(name))) control.OnValueChanged=callback
    end
end
local function kind(panel,text,name)
    panel:Help(L(text))
    local box=panel:ComboBox("")
    box:AddChoice(L("Annealed glass"),"annealed",C.Kind(name)=="annealed")
    box:AddChoice(L("Tempered glass"),"tempered",C.Kind(name)=="tempered")
    box:SetEnabled(admin())
    box.OnSelect=function(_,_,_,value) setting(name,value) end
    panel.NLGlassResetters[#panel.NLGlassResetters+1]=function()
        local callback=box.OnSelect box.OnSelect=function() end
        box:ChooseOptionID(default(name)=="tempered" and 2 or 1) box.OnSelect=callback
    end
end
function NLGlass.BuildSettings(panel)
    panel.NLGlassResetters={}
    panel:Help(L("Server settings require an administrator."))
    kind(panel,N("Map windows"),"rtx_glass_map_kind")
    kind(panel,N("Spawned glass"),"rtx_glass_spawn_kind")
    panel:Help(L("Kind, strength and piece size apply to new panes; clean up the map to replace its windows."))
    gameplaySlider(panel,N("Glass strength"),"rtx_glass_strength",0.1,10,2)
    local box=panel:CheckBox(L("Show cracks")) box:SetValue(C.Number("rtx_glass_show_cracks",1)) box:SetEnabled(admin())
    box.OnChange=function(_,checked) setting("rtx_glass_show_cracks",checked and "1" or "0") end
    panel.NLGlassResetters[#panel.NLGlassResetters+1]=function()
        local callback=box.OnChange box.OnChange=function() end box:SetValue(1) box.OnChange=callback
    end
    gameplaySlider(panel,N("Piece size"),"rtx_glass_piece_size",4,64,0)
    gameplaySlider(panel,N("Velocity transfer"),"rtx_glass_velocity_transfer",0,3,2)
    gameplaySlider(panel,N("Player break speed"),"rtx_glass_player_break_speed",0,1000,0)
    panel:Help(L("Default: 250 units/s; walking stays below this threshold."))
    gameplaySlider(panel,N("Player / NPC mass (kg)"),"rtx_glass_player_mass",1,500,0)
    panel:Help(L("Broken pieces are local to you and collide with the map and other pieces."))
    panel:Help(L("Debris lifetime (s; 0 = until cleanup)")) panel:NumSlider("","rtx_glass_debris_lifetime",0,600,0)
    panel:Help(L("Debris budget")) panel:NumSlider("","rtx_glass_debris_budget",100,8192,0)
    panel:CheckBox(L("Pieces collide with each other"),"rtx_glass_debris_collide")
    panel:CheckBox(L("Bodies and damage affect broken pieces"),"rtx_glass_debris_interact")
    panel:Help(L("Players, props, bullets, blasts and falls move or break your pieces. Glass never pushes back."))
    local reset=panel:Button(L("Reset to Defaults"))
    reset.DoClick=function()
        for _,s in ipairs(C.Debris) do RunConsoleCommand(s[1],s[2]) end
        if admin() then
            for _,s in ipairs(C.Settings) do timer.Remove("NLGlass.Setting."..s[1]) end
            net.Start("nlglass_setting") net.WriteUInt(0,4) net.WriteString("") net.SendToServer()
            for _,resetControl in ipairs(panel.NLGlassResetters) do resetControl() end
        end
    end
end
hook.Add("PopulateToolMenu","NLGlass.Settings",function()
    spawnmenu.AddToolMenuOption("Utilities","Glass Rewrite Remixed","GlassSettings",L("Glass settings"),"","",NLGlass.BuildSettings)
end)
concommand.Add("glass_open_panel",function()
    local frame=vgui.Create("DFrame") frame:SetTitle(L("Glass settings")) frame:SetSize(460,760) frame:Center() frame:MakePopup()
    local scroll=vgui.Create("DScrollPanel",frame) scroll:Dock(FILL)
    local panel=vgui.Create("DForm",scroll) panel:Dock(TOP) panel:SetName(L("Glass settings")) NLGlass.BuildSettings(panel)
end)
NLGlass.I18n.Phrase("nlglass_pane",L("Glass pane"))
for _,k in ipairs({{"annealed",L("Annealed glass")},{"tempered",L("Tempered glass")}}) do
    for _,s in ipairs({"48x48","96x64","128x128"}) do
        language.Add("nlglass_"..k[1].."_"..s,k[2].." "..s)
    end
end
