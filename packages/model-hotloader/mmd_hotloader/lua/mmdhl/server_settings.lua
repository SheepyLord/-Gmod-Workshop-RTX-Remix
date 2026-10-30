-- Server settings in the spawn menu (Q > Utilities > Admin > External Models, and the end of
-- the library's Physics & Performance tab): who may change ragdoll physics (physics_editor.lua)
-- and the largest static props players may share (props/server.lua). The console variables are
-- replicated, so every player sees the server's values. A change travels as
-- mmdhl_server_setting; the server applies it in single player, for the listen server's host and
-- for superadmins. Hook MMDHLCanChangeServerSettings(player, name, value) may decide otherwise:
-- false refuses, true allows.
local L=mmdhl.L
local S={}
mmdhl.serverSettings=S
-- The static prop upload limits, {default, maximum}: the defaults are 2.3.0's limits; an
-- administrator may raise them up to what the binary module accepts from props imported with
-- full-size textures (2.3.1).
for name,limit in pairs({mmdhl_prop_max_materials={128,128},mmdhl_prop_max_package_mb={256,2048},mmdhl_prop_max_texture_dimension={4096,16384},mmdhl_prop_max_expanded_mb={1024,4096}}) do
 CreateConVar(name,tostring(limit[1]),FCVAR_ARCHIVE+FCVAR_REPLICATED,'Largest static prop this server accepts from uploads (native hard caps still apply)',1,limit[2])
end
-- The settings the spawn menu changes and their ranges (all whole numbers).
S.List={
 {name='mmdhl_physics_editor',min=0,max=2},
 {name='mmdhl_physics_editor_cooldown',min=0,max=60},
 {name='mmdhl_physics_editor_budget',min=0,max=1000},
 {name='mmdhl_prop_max_texture_dimension',min=1,max=16384},
 {name='mmdhl_prop_max_package_mb',min=1,max=2048},
 {name='mmdhl_prop_max_expanded_mb',min=1,max=4096},
 {name='mmdhl_prop_max_materials',min=1,max=128},
}
local byName={} for _,s in ipairs(S.List) do byName[s.name]=s end
-- The value a request sets, or nil for an unknown setting or a value that is not a number:
-- rounded and kept within the setting's range.
function S.Valid(name,value)
 local s=byName[name] value=tonumber(value)
 if not s or not value or value~=value or value==math.huge or value==-math.huge then return nil end
 return math.Clamp(math.Round(value),s.min,s.max)
end
if SERVER then
 util.AddNetworkString('mmdhl_server_setting')
 function S.CanChange(p,name,value)
  local ok=game.SinglePlayer() or (IsValid(p) and (p:IsListenServerHost() or p:IsSuperAdmin()))
  local h=hook.Run('MMDHLCanChangeServerSettings',p,name,value) if h~=nil then ok=h==true end
  return ok
 end
 net.Receive('mmdhl_server_setting',function(_,p)
  local name=net.ReadString() local value=S.Valid(name,net.ReadString())
  if value==nil then return end
  if not S.CanChange(p,name,value) then
   if IsValid(p) then net.Start('mmdhl_notice') net.WriteString(L'server_settings.error.not_allowed') net.Send(p) end
   return
  end
  RunConsoleCommand(name,tostring(value))
 end)
 return
end
-- Whether this player may change them. The server decides; this only greys the controls.
function S.MayChange() local p=LocalPlayer() return game.SinglePlayer() or (IsValid(p) and (p:IsListenServerHost() or p:IsSuperAdmin())) end
function S.Send(name,value) net.Start('mmdhl_server_setting') net.WriteString(name) net.WriteString(tostring(value)) net.SendToServer() end
local function current(name) local c=GetConVar(name) return c and c:GetFloat() or 0 end
-- A slider's knob and text box take input whatever the slider's own state: (dis)able them all.
local function enable(p,on)
 p:SetEnabled(on)
 for _,child in ipairs(p.GetChildren and p:GetChildren() or {}) do enable(child,on) end
end
-- A control showing the server's value (`show` displays one, `shown` reads it back). After a
-- change it shows the server's value again once the server has replied with a new one, or after
-- 1.5 seconds when the server did not take the change.
local function bind(p,name,show,shown)
 p.MMDHLServerValue=current(name) p.MMDHLSyncing=true show(p,p.MMDHLServerValue) p.MMDHLSyncing=nil
 local think=p.Think
 p.Think=function(self)
  if think then think(self) end
  local may=S.MayChange() if self.MMDHLMay~=may then self.MMDHLMay=may enable(self,may) self:SetAlpha(may and 255 or 110) end
  if self.IsEditing and self:IsEditing() then return end
  local value=current(name)
  if value~=self.MMDHLServerValue or (self.MMDHLSentAt and RealTime()-self.MMDHLSentAt>1.5) then
   self.MMDHLServerValue=value self.MMDHLSentAt=nil
   if shown(self)~=value then self.MMDHLSyncing=true show(self,value) self.MMDHLSyncing=nil end
  end
 end
 return p
end
-- A slider asks for its value once it has rested for 0.4 seconds.
local function slider(ui,name,label,hint)
 local s=byName[name] local p=ui.number(label,s.min,s.max,0,hint)
 p.OnValueChanged=function(self,value)
  if self.MMDHLSyncing then return end
  local wanted=S.Valid(name,value) if wanted==nil then return end
  timer.Create('MMDHL.ServerSetting.'..name,.4,1,function() S.Send(name,wanted) if IsValid(self) then self.MMDHLSentAt=RealTime() end end)
 end
 return bind(p,name,function(self,v) self:SetValue(v) end,function(self) return math.Round(self:GetValue()) end)
end
function S.Rows(ui)
 ui.text(L'server_settings.title',true)
 ui.text(L'server_settings.intro')
 local note=ui.status()
 note.Think=function(self) local text=S.MayChange() and L'server_settings.editable' or L'server_settings.read_only' if self:GetText()~=text then self:SetText(text) self:SetTextColor(ui.muted) end end
 local editor=ui.combo(L'server_settings.physics_editor.label',L'server_settings.physics_editor.tooltip')
 editor:AddChoice(L'server_settings.physics_editor.nobody',0) editor:AddChoice(L'server_settings.physics_editor.admins',1) editor:AddChoice(L'server_settings.physics_editor.everyone',2)
 editor.OnSelect=function(self,_,_,data) self.MMDHLChosen=tonumber(data) S.Send('mmdhl_physics_editor',data) self.MMDHLSentAt=RealTime() end
 bind(editor,'mmdhl_physics_editor',function(self,v) self.MMDHLChosen=v self:SetValue(self:GetOptionTextByData(v)) end,function(self) return self.MMDHLChosen end)
 slider(ui,'mmdhl_physics_editor_cooldown',L'server_settings.physics_editor_cooldown.label',L'server_settings.physics_editor_cooldown.tooltip')
 slider(ui,'mmdhl_physics_editor_budget',L'server_settings.physics_editor_budget.label',L'server_settings.physics_editor_budget.tooltip')
 slider(ui,'mmdhl_prop_max_texture_dimension',L'server_settings.prop_max_texture_dimension.label',L'server_settings.prop_max_texture_dimension.tooltip')
 slider(ui,'mmdhl_prop_max_package_mb',L'server_settings.prop_max_package_mb.label',L'server_settings.prop_max_package_mb.tooltip')
 slider(ui,'mmdhl_prop_max_expanded_mb',L'server_settings.prop_max_expanded_mb.label',L'server_settings.prop_max_expanded_mb.tooltip')
 slider(ui,'mmdhl_prop_max_materials',L'server_settings.prop_max_materials.label',L'server_settings.prop_max_materials.tooltip')
end
