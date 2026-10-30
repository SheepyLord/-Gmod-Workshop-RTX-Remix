-- Client-wide tuning is applied at the next complete physics step. No model
-- reimport, pose reset, or change to the fixed 60 Hz clock is required.
local native=mmdhl.native
local L=mmdhl.L
local workers=mmdhl.Decode(native.GetWorkerCapabilities())
local maximumWorkers=workers and workers.maximum or 32
local capabilities=native.GetCapabilities and mmdhl.Decode(native.GetCapabilities())
local definitions={
 {'mmdhl_secondary_iterations','10','Physics accuracy: -1 off, 0 lightweight jiggle, 1-100 full simulation',-1,100},
 {'mmdhl_secondary_gravity','1','Multiplier for character model physics gravity',0,4},
 {'mmdhl_secondary_gravity_baseline','600','The sv_gravity that is Earth gravity (9.81 m/s2) for character model physics: 515, 600 or 800',1,10000},
 {'mmdhl_secondary_gravity_override','0','1: character model physics use mmdhl_secondary_gravity_custom instead of sv_gravity',0,1},
 {'mmdhl_secondary_gravity_custom','9.81','Character model physics gravity in m/s2 while mmdhl_secondary_gravity_override is 1',0,40},
 {'mmdhl_secondary_damping','1','Multiplier for authored body damping',0,4},
 {'mmdhl_secondary_buoyancy','0','1: hair and clothing physics float in water',0,1},
 {'mmdhl_secondary_buoyancy_strength','1.2','Buoyancy of hair and clothing under water: 1 makes them weightless',0,4},
 {'mmdhl_secondary_water_drag','2','How much water slows hair and clothing, per second',0,20},
 {'mmdhl_secondary_stretch','0','Contact-aware stretch correction',0,1},
 {'mmdhl_vrm_relative_damping','1','VRM spring bones damp motion relative to the character, not the world',0,1},
 {'mmdhl_secondary_stretch_tolerance','1','Allowed stretch',.25,4},
 {'mmdhl_workers','0','Model Hotloader worker count: 0 selects the automatic count',0,maximumWorkers}
}
mmdhl.PhysicsSettingDefaults={mmdhl_first_person_body="2",
 mmdhl_secondary_backend='cpu_mt_v2',mmdhl_collide_with=tostring(mmdhl.CollideDefault),mmdhl_spawn_frozen='0',
 mmdhl_secondary_sleep='1',mmdhl_secondary_sleep_linear='0.5',mmdhl_secondary_sleep_angular='0.35',
 mmdhl_secondary_sleep_seconds='1.5',mmdhl_secondary_wake_drift='0.02',mmdhl_secondary_wait_ms='0',
 mmdhl_vertex_cache='1',mmdhl_compact_vertices='1',mmdhl_gpu_skinning='1',mmdhl_update_lod='1',mmdhl_smooth_stepped_poses='1',mmdhl_flashlight_overlap_fix='1',mmdhl_debug_overlay='0',mmdhl_debug_print='0'
}
for _,d in ipairs(definitions) do
 CreateClientConVar(d[1],d[2],true,false,d[3],d[4],d[5])
 mmdhl.PhysicsSettingDefaults[d[1]]=d[2]
end
-- Earth's gravity: what the authored physics of every model is made for.
local Earth=9.81
-- The scale of the authored gravity: the server's sv_gravity over the sv_gravity that counts
-- as 9.81 m/s2 (mmdhl_secondary_gravity_baseline), or a fixed value, times the multiplier.
-- Returns the scale the binary module takes (2.3.1: -16 to 16; earlier ones 0 to 4) and the
-- one asked for.
function mmdhl.SecondaryGravityScale()
 local function n(name) local c=GetConVar(name) return c and c:GetFloat() or 0 end
 local scale
 if n('mmdhl_secondary_gravity_override')~=0 then scale=n('mmdhl_secondary_gravity_custom')/Earth
 else
  local server=GetConVar('sv_gravity') local baseline=n('mmdhl_secondary_gravity_baseline')
  scale=(server and server:GetFloat() or 600)/(baseline>0 and baseline or 600)
 end
 scale=scale*n('mmdhl_secondary_gravity')
 local limit=istable(capabilities) and tonumber(capabilities.secondaryGravity)
 if limit then return math.Clamp(scale,-limit,limit),scale end
 return math.Clamp(scale,0,4),scale
end
-- Floating in water needs a binary module that has it (2.3.1).
function mmdhl.BuoyancySupported() return isfunction(native.SetSecondaryBuoyancy) and isfunction(native.SetSecondaryWater) end
local lastWorkers
local function apply()
 if not native.SetSecondaryTuning then mmdhl.physicsSettingsError=L'physics.error.restart_required' return end
 local function n(name) return GetConVar('mmdhl_'..name):GetFloat() end
 local ok,err=native.SetSecondaryTuning(math.Round(n('secondary_iterations')),(mmdhl.SecondaryGravityScale()),n('secondary_damping'),n('secondary_stretch')~=0,n('secondary_stretch_tolerance'))
 if not ok then mmdhl.physicsSettingsError=err and tostring(err) or L'physics.error.apply_failed' return end
 local workers=math.Round(n('workers'))
 if workers~=lastWorkers then
  -- The native entry point drains existing jobs before replacing the pool.
  local result,workerError=native.SetWorkers(workers)
  if not result then mmdhl.physicsSettingsError=workerError and tostring(workerError) or L'physics.error.workers_failed' return end
  lastWorkers=workers
 end
 if native.SetSpringRelativeDamping then native.SetSpringRelativeDamping(n('vrm_relative_damping')~=0) end
 if mmdhl.BuoyancySupported() then
  local floating,floatError=native.SetSecondaryBuoyancy(n('secondary_buoyancy')~=0,n('secondary_buoyancy_strength'),n('secondary_water_drag'))
  if not floating then mmdhl.physicsSettingsError=floatError and tostring(floatError) or L'physics.error.apply_failed' return end
 end
 mmdhl.physicsSettingsError=nil
end
local function changed() timer.Create('MMDHL.PhysicsSettings',.2,1,apply) end
for _,d in ipairs(definitions) do cvars.AddChangeCallback(d[1],changed,'MMDHL.PhysicsSettings') end
-- sv_gravity is the server's: a replicated console variable runs no change callback on a
-- client, so it is read twice a second.
local lastGravity
timer.Create('MMDHL.SecondaryGravity',.5,0,function()
 local server=GetConVar('sv_gravity') local gravity=server and server:GetFloat()
 if gravity~=lastGravity then lastGravity=gravity changed() end
end)
-- With an older binary module, turning buoyancy on says why it has no effect and turns it off again.
cvars.AddChangeCallback('mmdhl_secondary_buoyancy',function(_,_,value)
 if (tonumber(value) or 0)==0 or mmdhl.BuoyancySupported() then return end
 if mmdhl.ShowNativeUpdateNeeded then mmdhl.ShowNativeUpdateNeeded(L'physics.buoyancy.feature','2.3.1') end
 RunConsoleCommand('mmdhl_secondary_buoyancy','0')
end,'MMDHL.Buoyancy')
hook.Add('InitPostEntity','MMDHL.PhysicsSettings',changed)
changed()
function mmdhl.RestorePhysicsDefaults()
 for name,value in pairs(mmdhl.PhysicsSettingDefaults) do local c=GetConVar(name) if c then c:SetString(value) end end
 changed()
end

-- The convar remains an iteration count for console users and saved settings.
-- Only the menu uses compact, approximately logarithmic positions.
local accuracySteps={[-1]=-1,[0]=0,1,2,5,10,20,50,100}
function mmdhl.BindAccuracySlider(p)
 local cvar=GetConVar('mmdhl_secondary_iterations')
 local syncing=false
 local lastValue
 local function sync()
  local value=cvar:GetInt()
  local step=math.Clamp(value,-1,0)
  if value>0 then
   local distance=math.huge
   for i=1,7 do
    local d=math.abs(math.log(value/accuracySteps[i]))
    if d<distance then step=i distance=d end
   end
  end
  syncing=true p:SetValue(step) syncing=false
  lastValue=value
  p:SetText(value<0 and L'physics.accuracy.off' or value==0 and L'physics.accuracy.jiggle' or L('physics.accuracy.iterations',{count=value}))
 end
 p:SetMinMax(-1,7) p:SetDecimals(0) p:SetDefaultValue(4)
 p.OnValueChanged=function(_,value)
  if syncing then return end
  cvar:SetInt(accuracySteps[math.Clamp(math.Round(value),-1,7)])
  sync()
 end
 local think=p.Think
 p.Think=function(self) if think then think(self) end if cvar:GetInt()~=lastValue then sync() end end
 sync()
end

-- Settings rows, drawn into the Physics & Performance tab (SettingsTab) or into a form of
-- the spawn menu's Utilities tab (SettingsForm), so both offer the same controls:
-- ui.text(value, title), ui.status(), ui.check(cvar, label, hint), ui.slider(cvar, label,
-- min, max, decimals, hint), ui.number(label, min, max, decimals, hint) (no console
-- variable), ui.combo(label, hint), ui.action(label, callback), ui.binder(), ui.collision(title),
-- ui.accuracy(hint), ui.advanced(title) (rows go into a collapsed section until ui.main()).
-- ui.form is true for the Utilities tab.
function mmdhl.SettingsTab(parent,s,fonts,styleChoices)
 local scroll=parent:Add('DScrollPanel') scroll:Dock(FILL)
 local ink,muted=Color(31,43,58),Color(93,109,127)
 local container=scroll
 local ui={root=scroll,muted=muted,form=false}
 local function row(kind,height)
  local p=container:Add(kind) p:Dock(TOP) p:SetTall(s(height)) p:DockMargin(s(8),0,s(16),s(6)) return p
 end
 function ui.text(value,title)
  local p=row('DLabel',title and 34 or 42) p:SetText(value) p:SetFont(title and fonts.Title or fonts.Small) p:SetTextColor(title and ink or muted) p:SetWrap(true) return p
 end
 function ui.status() local p=ui.text('',false) p:SetTall(s(32)) return p end
 function ui.check(cvar,value,hint)
  local p=row('DCheckBoxLabel',28) p:SetText(value) p:SetConVar(cvar) p:SetTextColor(ink) p.Label:SetFont(fonts.Body) p:SetTooltip(hint or '') return p
 end
 function ui.number(value,min,max,decimals,hint)
  local p=row('DNumSlider',38) p:SetText(value) p:SetMinMax(min,max) p:SetDecimals(decimals) p:SetDark(true)
  p.Label:SetFont(fonts.Body) p.Label:SetWide(s(305)) p:SetTooltip(hint or '') return p
 end
 function ui.slider(cvar,value,min,max,decimals,hint)
  local p=ui.number(value,min,max,decimals,hint) p:SetConVar(cvar) p:SetDefaultValue(tonumber(mmdhl.PhysicsSettingDefaults[cvar])) return p
 end
 function ui.combo(value,hint)
  ui.text(value,false)
  local p=row('DComboBox',34) styleChoices(p,s,fonts.Body) p:SetTooltip(hint or '') return p
 end
 function ui.action(value,callback) local p=row('DButton',36) p:SetText(value) p:SetFont(fonts.Body) p.DoClick=callback return p end
 function ui.binder() return row('DBinder',34) end
 function ui.collision(title)
  ui.text(title,false):SetTall(s(26))
  local last
  for _,target in ipairs(mmdhl.CollisionTargets) do
   local p=row('DCheckBoxLabel',24) p:SetText(target.name) p:SetTextColor(ink) p.Label:SetFont(fonts.Body) p:SetTooltip(target.tooltip) p:DockMargin(s(26),0,s(16),s(4))
   mmdhl.BindCollisionCheckbox(p,target.flag) last=p
  end
  last:DockMargin(s(26),0,s(16),s(14)) -- sets the group apart from "Spawn frozen"
 end
 function ui.accuracy(hint)
  local p=row('DNumSlider',38) p:SetDark(true)
  p.Label:SetFont(fonts.Body) p.Label:SetWide(s(305))
  p:SetTooltip(hint) mmdhl.BindAccuracySlider(p) return p
 end
 function ui.advanced(title)
  container=scroll
  local category=row('DCollapsibleCategory',28) category:SetLabel(title) category:SetExpanded(false)
  local content=vgui.Create('DPanel',category) content:SetPaintBackground(false)
  content.PerformLayout=function(p) p:SizeToChildren(false,true) end
  category:SetContents(content) container=content
 end
 function ui.main() container=scroll end
 return ui
end
function mmdhl.SettingsForm(form)
 local container=form
 local ui={root=form,muted=Color(93,109,127),form=true}
 function ui.text(value,title) local p=container:Help(value) if title then p:SetFont('DermaDefaultBold') end return p end
 function ui.status() return container:Help('') end
 function ui.check(cvar,value,hint) local p=container:CheckBox(value,cvar) p:SetTooltip(hint or '') return p end
 function ui.number(value,min,max,decimals,hint) local p=container:NumSlider(value,nil,min,max,decimals) p:SetTooltip(hint or '') return p end
 function ui.slider(cvar,value,min,max,decimals,hint)
  local p=container:NumSlider(value,cvar,min,max,decimals) p:SetTooltip(hint or '') p:SetDefaultValue(tonumber(mmdhl.PhysicsSettingDefaults[cvar])) return p
 end
 function ui.combo(value,hint) local p=container:ComboBox(value) p:SetTooltip(hint or '') return p end
 function ui.action(value,callback) local p=container:Button(value) p.DoClick=callback return p end
 function ui.binder() local p=vgui.Create('DBinder',container) p:SetTall(34) container:AddItem(p) return p end
 function ui.collision(title)
  container:Help(title)
  for _,target in ipairs(mmdhl.CollisionTargets) do local box=container:CheckBox(target.name) box:SetTooltip(target.tooltip) mmdhl.BindCollisionCheckbox(box,target.flag) end
 end
 function ui.accuracy(hint) local p=container:NumSlider('',nil,-1,7,0) p:SetTooltip(hint) mmdhl.BindAccuracySlider(p) return p end
 function ui.advanced(title) local section=vgui.Create('DForm',form) section:SetName(title) section:SetExpanded(false) form:AddItem(section) container=section end
 function ui.main() container=form end
 return ui
end
-- A slider's knob and text box take input whatever the slider's own state: (dis)able them all.
local function enable(p,on)
 p:SetEnabled(on)
 for _,child in ipairs(p.GetChildren and p:GetChildren() or {}) do enable(child,on) end
end
-- A row that only applies while a checkbox setting is on (`wanted` true) or off.
local function dependsOn(p,cvar,wanted)
 local think=p.Think
 p.Think=function(self)
  if think then think(self) end
  local c=GetConVar(cvar) local on=(c and c:GetBool() or false)==wanted
  if self.MMDHLApplies~=on then self.MMDHLApplies=on enable(self,on) self:SetAlpha(on and 255 or 110) end
 end
 return p
end
-- A console variable with a few named values ({value, label} pairs).
local function options(ui,cvar,value,choices,hint)
 local p=ui.combo(value,hint)
 for _,c in ipairs(choices) do p:AddChoice(c[2],c[1]) end
 p.Think=function(panel) local v=GetConVar(cvar):GetString() if panel.shown~=v then panel.shown=v panel:SetValue(panel:GetOptionTextByData(v) or v) end end
 p.OnSelect=function(panel,_,_,data) panel.shown=tostring(data) RunConsoleCommand(cvar,tostring(data)) end
 return p
end
local function physicsRows(ui)
 local muted=ui.muted
 if not ui.form then ui.text(L'physics.title',true) end
 ui.text(L'physics.intro')
 local status=ui.status()
 status.Think=function(p)
  if mmdhl.RequestFrameProfile then mmdhl.RequestFrameProfile(2) end
  if (p.nextUpdate or 0)>RealTime() then return end p.nextUpdate=RealTime()+1
  local profile=mmdhl.frameProfile or {}
  local accuracy=GetConVar('mmdhl_secondary_iterations'):GetInt()
  local mode=accuracy<0 and L'physics.status.off' or accuracy==0 and L'physics.status.jiggle' or L('physics.status.full',{count=accuracy})
  p:SetText(mmdhl.physicsSettingsError or (mode..' · '..(profile.workers and L('physics.status.threads',{count=profile.workers}) or L'physics.status.threads_automatic')))
  p:SetTextColor(mmdhl.physicsSettingsError and Color(180,46,46) or muted)
 end
 -- The Utilities tab keeps its own labels for the settings it always had.
 local backend=ui.combo(ui.form and L'ui.toolmenu.backend' or L'physics.backend.label',L'physics.backend.tooltip')
 mmdhl.BindGlobalChoice(backend,'secondaryBackend',mmdhl.SecondaryBackends)
 if ui.form then ui.text(L'ui.toolmenu.backend_help') end
 ui.collision(ui.form and L'ui.toolmenu.secondary_collision' or L'physics.collision.label')
 ui.check('mmdhl_spawn_frozen',ui.form and L'ui.toolmenu.spawn_frozen' or L'physics.spawn_frozen.label',L'physics.spawn_frozen.tooltip')
 ui.accuracy(L'physics.accuracy.tooltip')
 ui.text(L'physics.accuracy.help')
 -- Gravity follows sv_gravity from the baseline that counts as 9.81 m/s2, unless fixed.
 dependsOn(options(ui,'mmdhl_secondary_gravity_baseline',L'physics.gravity_baseline.label',{{'600',L'physics.gravity_baseline.600'},{'800',L'physics.gravity_baseline.800'},{'515',L'physics.gravity_baseline.515'}},L'physics.gravity_baseline.tooltip'),'mmdhl_secondary_gravity_override',false)
 ui.check('mmdhl_secondary_gravity_override',L'physics.gravity_override.label',L'physics.gravity_override.tooltip')
 dependsOn(ui.slider('mmdhl_secondary_gravity_custom',L'physics.gravity_custom.label',0,40,2,L'physics.gravity_custom.tooltip'),'mmdhl_secondary_gravity_override',true)
 ui.slider('mmdhl_secondary_gravity',L'physics.gravity.label',0,4,2,L'physics.gravity.tooltip')
 local gravity=ui.status()
 gravity.Think=function(p)
  if (p.nextUpdate or 0)>RealTime() then return end p.nextUpdate=RealTime()+.5
  local applied,requested=mmdhl.SecondaryGravityScale()
  local value=string.format('%.2f',applied*Earth)
  local server=GetConVar('sv_gravity')
  local message=GetConVar('mmdhl_secondary_gravity_override'):GetBool() and L('physics.gravity.now_fixed',{gravity=value}) or L('physics.gravity.now',{gravity=value,setting=string.format('%g',server and server:GetFloat() or 600)})
  if applied~=requested then message=message..' '..L'physics.gravity.limited' end
  if p:GetText()~=message then p:SetText(message) p:SetTextColor(muted) end
 end
 ui.slider('mmdhl_secondary_damping',L'physics.damping.label',0,4,2,L'physics.damping.tooltip')
 ui.check('mmdhl_vrm_relative_damping',L'physics.vrm_damping.label',L'physics.vrm_damping.tooltip')
 ui.check('mmdhl_secondary_buoyancy',L'physics.buoyancy.label',L'physics.buoyancy.tooltip')
 dependsOn(ui.slider('mmdhl_secondary_buoyancy_strength',L'physics.buoyancy_strength.label',0,4,2,L'physics.buoyancy_strength.tooltip'),'mmdhl_secondary_buoyancy',true)
 dependsOn(ui.slider('mmdhl_secondary_water_drag',L'physics.water_drag.label',0,20,1,L'physics.water_drag.tooltip'),'mmdhl_secondary_buoyancy',true)
 ui.text(L'lod.title',true)
 ui.check('mmdhl_lod_enabled',L'lod.enabled.label',L'lod.enabled.tooltip')
 ui.advanced(L'lod.advanced')
 ui.slider('mmdhl_lod_near',L'lod.near.label',0,10000,0,L'lod.near.tooltip')
 ui.slider('mmdhl_lod_full',L'lod.full.label',0,20000,0,L'lod.full.tooltip')
 ui.slider('mmdhl_lod_middle',L'lod.middle.label',0,30000,0,L'lod.middle.tooltip')
 ui.slider('mmdhl_lod_cutoff',L'lod.cutoff.label',1,50000,0,L'lod.cutoff.tooltip')
 ui.slider('mmdhl_lod_hidden_seconds',L'lod.hidden.label',0,30,1,L'lod.hidden.tooltip')
 ui.slider('mmdhl_lod_speed',L'lod.speed.label',1,2000,0,L'lod.speed.tooltip')
 ui.slider('mmdhl_lod_angular_speed',L'lod.angular.label',1,1440,0,L'lod.angular.tooltip')
 ui.main()
 ui.text(L'physics.stretch.title',true)
 ui.check('mmdhl_secondary_stretch',L'physics.stretch.label',L'physics.stretch.tooltip')
 ui.slider('mmdhl_secondary_stretch_tolerance',L'physics.stretch_tolerance.label',.25,4,2,L'physics.stretch_tolerance.tooltip')
 ui.text(L'physics.stretch.help')
 -- Name translation shares model names with Google Translate, so "Restore
 -- defaults" leaves this choice alone.
 ui.text(L'names.setting_title',true)
 ui.check('mmdhl_translate_names',L'names.setting_label',L'names.setting_tooltip')
 local translation=ui.text(L'names.setting_help')
 translation.Think=function(p)
  if (p.nextUpdate or 0)>RealTime() then return end p.nextUpdate=RealTime()+1
  local status=mmdhl.names and mmdhl.names.Status()
  local failing=status and status.enabled and status.failures>0
  local message=failing and L'names.status_unavailable' or L'names.setting_help'
  if p:GetText()~=message then p:SetText(message) p:SetTextColor(failing and Color(170,90,20) or muted) end
 end
 ui.text(L'performance.title',true)
 ui.slider('mmdhl_workers',L'performance.workers.label',0,maximumWorkers,0,L'performance.workers.tooltip')
 ui.check('mmdhl_secondary_sleep',L'performance.sleep.label',L'performance.sleep.tooltip')
 ui.advanced(L'performance.advanced')
 ui.slider('mmdhl_secondary_wait_ms',L'performance.wait.label',0,16,1,L'performance.wait.tooltip')
 ui.check('mmdhl_vertex_cache',L'performance.vertex_cache.label',L'performance.vertex_cache.tooltip')
 ui.check('mmdhl_compact_vertices',L'performance.compact_vertices.label',L'performance.compact_vertices.tooltip')
 ui.check('mmdhl_gpu_skinning',L'performance.gpu_skinning.label',L'performance.gpu_skinning.tooltip')
 ui.check('mmdhl_smooth_stepped_poses',L'performance.smooth_poses.label',L'performance.smooth_poses.tooltip')
 options(ui,'mmdhl_update_lod',L'performance.update_lod.label',{{'0',L'performance.update_lod.every_frame'},{'1',L'performance.update_lod.unseen'},{'2',L'performance.update_lod.small'}},L'performance.update_lod.tooltip')
 ui.check('mmdhl_flashlight_overlap_fix',L'performance.flashlight_fix.label',L'performance.flashlight_fix.tooltip')
 ui.slider('mmdhl_secondary_sleep_linear',L'performance.sleep_linear.label',0,10,2,L'performance.sleep_linear.tooltip')
 ui.slider('mmdhl_secondary_sleep_angular',L'performance.sleep_angular.label',0,10,2,L'performance.sleep_angular.tooltip')
 ui.slider('mmdhl_secondary_sleep_seconds',L'performance.sleep_seconds.label',.1,60,1,L'performance.sleep_seconds.tooltip')
 ui.slider('mmdhl_secondary_wake_drift',L'performance.wake_drift.label',0,10,3,L'performance.wake_drift.tooltip')
 ui.main()
 ui.text(L'debug.section',true)
 ui.check('mmdhl_debug_overlay',ui.form and L'ui.toolmenu.debug_overlay' or L'debug.overlay')
 ui.check('mmdhl_debug_print',ui.form and L'ui.toolmenu.debug_print' or L'debug.print')
 ui.action(ui.form and L'ui.toolmenu.debug_report' or L'debug.write_report',function() RunConsoleCommand('mmdhl_debug_report') end)
 if ui.form then ui.text(L('ui.toolmenu.debug_bind_help',{command='bind F7 mmdhl_debug_toggle'})) end
 ui.action(L'physics.reset_all',function() RunConsoleCommand('mmdhl_reset_all_physics') end)
 ui.action(L'physics.cleanup_ragdolls',function() RunConsoleCommand('mmdhl_cleanup_client_ragdolls') end)
 ui.text(L'physics.cleanup_help')
 ui.action(L'physics.toggle',function() RunConsoleCommand('mmdhl_toggle_physics') end)
 ui.text(L'physics.toggle_shortcut')
 local toggle=ui.binder() toggle:SetValue(GetConVar('mmdhl_toggle_physics_key'):GetInt())
 toggle.OnChange=function(_,key) RunConsoleCommand('mmdhl_toggle_physics_key',tostring(key)) end
 ui.text(L'physics.reset_shortcut')
 local reset=ui.binder() reset:SetValue(GetConVar('mmdhl_reset_all_key'):GetInt())
 reset.OnChange=function(p,key) if key==KEY_F8 then key=0 p:SetValue(0) end RunConsoleCommand('mmdhl_reset_all_key',tostring(key)) end
 ui.action(L'physics.restore_defaults',function() mmdhl.RestorePhysicsDefaults() end)
 ui.text(L'physics.restore_help')
end
function mmdhl.BuildPhysicsSettings(parent,s,fonts,styleChoices)
 local ui=mmdhl.SettingsTab(parent,s,fonts,styleChoices)
 physicsRows(ui)
 -- The server's own settings close the tab (server_settings.lua).
 if mmdhl.serverSettings then ui.main() mmdhl.serverSettings.Rows(ui) end
 return ui.root
end
-- Every Physics & Performance setting on a form of the Utilities tab.
function mmdhl.BuildPhysicsSettingsForm(form) physicsRows(mmdhl.SettingsForm(form)) end
