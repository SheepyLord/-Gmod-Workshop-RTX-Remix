-- R13-A QA only. Injected into both realms of an isolated PoC session by mmd_lazy_session.py.
-- Records memory phases and drives the routes a player uses: the NPC tab, the hotloader menu,
-- the player-model window, NPC/ragdoll/player spawns, saves, dupes and map changes.
R13A=R13A or {}
local Q=R13A
local function emit(kind,value) print('R13A_'..kind..' '..util.TableToJSON(value or {})) end
Q.emit=emit
local function fail(where,why) print('R13A_ERROR '..tostring(where)..' '..tostring(why)) end
Q.fail=fail
local function carrier(model) return isstring(model) and model:lower():match('^models/mmd/[a-f0-9]+/[^/]+%.mdl$')~=nil end
local function loaded(model) return util.IsModelLoaded~=nil and util.IsModelLoaded(model)==true end
-- Registrations and how many of their models Source has loaded (IsModelLoaded never loads one).
local function census()
 local out={registrations=0,loaded=0,lazy=0,assets={},loadedAssets={}}
 for model,entry in pairs(mmdhl and mmdhl.actorRegistrations or {}) do
  out.registrations=out.registrations+1
  local asset=entry.rig and entry.rig.asset
  if asset then out.assets[asset]=true end
  if loaded(model) then out.loaded=out.loaded+1 if asset then out.loadedAssets[asset]=true end end
  if entry.lazy then out.lazy=out.lazy+1 end
 end
 out.assets=table.Count(out.assets) out.loadedAssets=table.Count(out.loadedAssets)
 return out
end
Q.Census=census
local function readiness()
 local R=mmdhl and mmdhl.readiness
 if not istable(R) or not isfunction(R.Describe) then return nil end
 local ok,value=pcall(R.Describe) return ok and value or {error=tostring(value)}
end
-- Every archive mounted from now on, and (server) every carrier precache, with its time. The
-- hotloader looks game.MountGMA and util.PrecacheModel up when it calls them.
if not Q.observing then
 Q.observing=true
 local mount=game.MountGMA
 game.MountGMA=function(path,...)
  local started=SysTime() local result={mount(path,...)}
  emit('MOUNT',{realm=SERVER and 'server' or 'client',path=path,ok=result[1]==true,ms=math.floor((SysTime()-started)*1000),at=os.date('!%H:%M:%S'),action=Q.lastAction})
  return unpack(result)
 end
 if SERVER then
  local precache=util.PrecacheModel
  util.PrecacheModel=function(model,...)
   if not carrier(model) then return precache(model,...) end
   local was=loaded(model) local started=SysTime() local result={precache(model,...)}
   emit('PRECACHE',{model=model,wasLoaded=was,ms=math.floor((SysTime()-started)*1000),at=os.date('!%H:%M:%S'),action=Q.lastAction})
   return unpack(result)
  end
 end
end
function Q.Action(name) Q.lastAction=name emit('ACTION',{name=name,at=os.date('!%H:%M:%S')}) end
if SERVER then
 -- Every NPC the server creates, and Sandbox's completion hook for menu NPCs.
 hook.Add('PlayerSpawnedNPC','R13A.Spawned',function(p,e)
  emit('NPC_SPAWNED',{class=e:GetClass(),model=e:GetModel(),index=e:EntIndex(),attached=mmdhl.IsMMD(e),action=Q.lastAction})
 end)
 hook.Add('OnEntityCreated','R13A.Created',function(e)
  timer.Simple(0,function()
   if IsValid(e) and (e:IsNPC() or carrier(e:GetModel())) then
    emit('CREATED',{class=e:GetClass(),model=e:GetModel(),index=e:EntIndex(),action=Q.lastAction})
   end
  end)
 end)
 function Q.ServerCensus(name)
  local c=census() c.phase=name c.realm='server' c.readiness=readiness()
  local mmd=0 for _,e in ipairs(ents.GetAll()) do if mmdhl.IsMMD(e) then mmd=mmd+1 end end c.entities=mmd
  emit('CENSUS',c)
 end
 -- Faces the first player toward open ground in front of it, as a player aiming a spawn.
 function Q.Aim(pitch)
  local p=player.GetAll()[1] if not IsValid(p) then return end
  p:SetEyeAngles(Angle(pitch or 30,p:EyeAngles().y,0))
 end
 function Q.Inspect(index,label)
  local e=Entity(index)
  if not IsValid(e) then emit('ENTITY',{label=label,index=index,valid=false}) return end
  local rig=mmdhl.GetRig(e)
  emit('ENTITY',{label=label,index=index,valid=true,class=e:GetClass(),model=e:GetModel(),asset=mmdhl.GetAsset(e),
   key=e:GetNW2String('MMDHLRig',''),attached=mmdhl.IsMMD(e),role=e:GetNW2String('MMDHLRole',''),
   validModel=util.IsValidModel(e:GetModel()),bindingError=e.MMDHLBindingError and mmdhl.Localize(e.MMDHLBindingError) or nil,
   rig=rig and rig.key,error=e:GetModel()=='models/error.mdl'})
 end
 function Q.InspectMMD(label)
  local list={}
  for _,e in ipairs(ents.GetAll()) do
   if IsValid(e) and (carrier(e:GetModel()) or mmdhl.IsMMD(e)) then
    list[#list+1]={index=e:EntIndex(),class=e:GetClass(),model=e:GetModel(),asset=mmdhl.GetAsset(e),attached=mmdhl.IsMMD(e),
     key=e:GetNW2String('MMDHLRig',''),bindingError=e.MMDHLBindingError and mmdhl.Localize(e.MMDHLBindingError) or nil}
   end
  end
  emit('MMD_ENTITIES',{label=label,entities=list})
 end
 -- A dupe of an entity as the duplicator tool makes it: copy, then paste beside it.
 function Q.Dupe(index)
  local e=Entity(index) local p=player.GetAll()[1]
  if not IsValid(e) or not IsValid(p) then fail('dupe','missing entity') return end
  local ok,why=pcall(function()
   local copy=duplicator.Copy(e)
   local offset=Vector(60,0,0)
   for _,data in pairs(copy.Entities) do data.Pos=data.Pos+offset end
   local pasted=duplicator.Paste(p,copy.Entities,copy.Constraints)
   for _,made in pairs(pasted) do
    if IsValid(made) then timer.Simple(1,function() Q.Inspect(made:EntIndex(),'dupe') end) end
   end
  end)
  if not ok then fail('dupe',why) end
 end
 function Q.RespawnPlayer()
  local p=player.GetAll()[1] if IsValid(p) then p:Spawn() emit('RESPAWNED',{model=p:GetModel()}) end
 end
 function Q.EnsureAlive()
  local p=player.GetAll()[1]
  if IsValid(p) then local dead=not p:Alive() if dead then p:Spawn() end emit('ALIVE',{respawned=dead,model=p:GetModel(),health=p:Health()}) end
 end
 function Q.RemoveClass(class)
  local n=0 for _,e in ipairs(ents.FindByClass(class)) do e:Remove() n=n+1 end
  emit('REMOVED_CLASS',{class=class,count=n})
 end
 function Q.RemoveMMD()
  local count=0
  for _,e in ipairs(ents.GetAll()) do
   if IsValid(e) and not e:IsPlayer() and mmdhl.IsMMD(e) then e:Remove() count=count+1 end
  end
  local p=player.GetAll()[1]
  if IsValid(p) and mmdhl.IsMMD(p) and mmdhl.RemovePlayerModel then mmdhl.RemovePlayerModel(p) count=count+1 end
  emit('REMOVED',{count=count})
 end
 -- Approval in single player: the catalog the server broadcasts after one.
 function Q.Catalog()
  if mmdhl.SendSharedCatalog then mmdhl.SendSharedCatalog() emit('CATALOG',{sent=true}) else fail('catalog','unavailable') end
 end
 -- One archive mounted the way the hotloader mounts a character's materials at its first spawn.
 function Q.Mount(path)
  local ok,err=mmdhl.MountPackage(path)
  emit('MOUNTED',{path=path,ok=ok==true,error=err and tostring(err) or nil})
 end
 function Q.Recent()
  local raw=file.Read('mmd_hotloader/recent.json','DATA')
  emit('RECENT',{present=raw~=nil,body=raw and util.JSONToTable(raw) or nil})
 end
 -- The lag trigger's steps on the server, on the clock both realms share (SysTime): a new
 -- entry's publication, its registration message and the hotloader's own spawn.
 function Q.TraceServer()
  if Q.tracingServer then return end
  Q.tracingServer=true
  for _,name in ipairs({'PublishActor','SendActorRegistration','RegisterActor','PublishRig','SpawnActorNative','AttachNative'}) do
   local original=mmdhl[name]
   if isfunction(original) then
    mmdhl[name]=function(...)
     local first=select(1,...)
     local key=istable(first) and first.key or (isentity(first) and first:GetClass()) or nil
     emit('TRACE',{t=SysTime(),realm='server',event=name..'-before',key=key})
     local result={original(...)}
     emit('TRACE',{t=SysTime(),realm='server',event=name..'-after',key=key})
     return unpack(result)
    end
   end
  end
 end
 print('R13A_INSTALLED server')
 return
end
-- Client.
-- Game-texture GPU memory twice a second: a rise of more than 256 MB between two samples is
-- reported with the last action the driver announced.
function Q.Watch()
 local function app()
  local ok,stats=pcall(function() return RemixResource and RemixResource.GetVramStats and RemixResource.GetVramStats() end)
  return ok and istable(stats) and stats.usedAppTextureBytes or nil
 end
 Q.watchLast=app()
 timer.Create('R13A.Watch',.5,0,function()
  local now=app() if not now then return end
  if Q.watchLast and now-Q.watchLast>256*1048576 then
   emit('JUMP',{from=Q.watchLast,to=now,at=os.date('!%H:%M:%S'),action=Q.lastAction})
  end
  Q.watchLast=now
 end)
end
-- The client side of the trace: every frame's game-texture GPU memory (a line when it moved by
-- more than 64 MB), the registration message and what it publishes, on the shared clock.
function Q.Trace()
 if Q.tracing then return end
 Q.tracing=true
 local function app()
  local ok,stats=pcall(function() return RemixResource and RemixResource.GetVramStats and RemixResource.GetVramStats() end)
  return ok and istable(stats) and stats.usedAppTextureBytes or nil
 end
 local last=app()
 emit('TRACE',{t=SysTime(),realm='client',event='sample',app=last})
 hook.Add('Think','R13A.Trace',function()
  local now=app()
  if now and last and math.abs(now-last)>64*1048576 then
   emit('TRACE',{t=SysTime(),realm='client',event='sample',app=now,from=last,frame=FrameNumber()})
   last=now
  end
 end)
 local receive=net.Receivers and net.Receivers['mmdhl_actor_registration']
 if isfunction(receive) then
  net.Receivers['mmdhl_actor_registration']=function(...)
   emit('TRACE',{t=SysTime(),realm='client',event='registration-before',app=app()})
   receive(...)
   emit('TRACE',{t=SysTime(),realm='client',event='registration-after',app=app()})
  end
 end
 for _,name in ipairs({'RegisterActor','PublishActorEntry','UnregisterActor'}) do
  local original=mmdhl[name]
  if isfunction(original) then
   mmdhl[name]=function(...)
    local first=select(1,...)
    local key=istable(first) and first.key or (isstring(first) and first) or nil
    local result={original(...)}
    emit('TRACE',{t=SysTime(),realm='client',event=name,key=key,app=app()})
    return unpack(result)
   end
  end
 end
end
function Q.Phase(name)
 local ok,stats=pcall(function() return RemixResource and RemixResource.GetVramStats and RemixResource.GetVramStats() end)
 print('R13_PHASE '..name..' '..os.date('!%Y-%m-%dT%H:%M:%SZ')..' lua_kb='..math.floor(collectgarbage('count'))..
  ' vram='..(ok and istable(stats) and util.TableToJSON(stats) or 'unavailable'))
 local c=census() c.phase=name c.realm='client' c.readiness=readiness()
 local npc,players=0,0
 for key in pairs(list.GetForEdit('NPC')) do if isstring(key) and key:sub(1,4)=='mmd_' then npc=npc+1 end end
 for key in pairs(player_manager.AllValidModels()) do if isstring(key) and key:sub(1,4)=='mmd_' then players=players+1 end end
 c.npcEntries=npc c.playerEntries=players c.presented=table.Count(mmdhl.assets or {})
 c.entities=#(mmdhl.Entities and mmdhl.Entities() or {})
 emit('CENSUS',c)
end
-- The registered NPC/player entries this client lists, for the driver to choose from.
function Q.Entries()
 local out={}
 for model,entry in pairs(mmdhl.actorRegistrations or {}) do
  local r=entry.rig
  if istable(r) then out[#out+1]={key='mmd_'..r.key:sub(1,16),rig=r.key,asset=r.asset,role=r.role,model=model,name=r.name,
   generator=r.generator,arms=entry.arms and entry.arms.key or nil,loaded=loaded(model),lazy=entry.lazy==true} end
 end
 table.sort(out,function(a,b) return a.rig<b.rig end)
 -- One line each: the console cuts a printed line at about 4 KB.
 for _,item in ipairs(out) do emit('ENTRY',item) end
 print('R13A_ENTRIES_DONE '..#out)
end
local function closeWindows()
 for _,panel in ipairs(vgui.GetWorldPanel():GetChildren()) do
  if IsValid(panel) and panel:IsVisible() and isfunction(panel.GetTitle) and isfunction(panel.Close) and panel~=g_SpawnMenu and panel~=g_ContextMenu then panel:Close() end
 end
end
Q.CloseWindows=closeWindows
-- The NPC tab, with the imported characters' category populated as a click on it does.
function Q.NPCTab()
 closeWindows()
 RunConsoleCommand('+menu')
 timer.Simple(1.5,function()
  local ok,why=pcall(function()
   spawnmenu.SwitchCreationTab('#spawnmenu.category.npcs')
   local tab=g_SpawnMenu.CreateMenu:GetCreationTab('#spawnmenu.category.npcs')
   local content=tab and tab.ContentPanel
   local tree=content and content.ContentNavBar and content.ContentNavBar.Tree
   local wanted=mmdhl.L'common.external_models' local icons,found=0,false
   for name,node in pairs(tree and tree.Categories or {}) do
    if name==wanted or language.GetPhrase(name)==wanted then
     found=true node:InternalDoClick()
     for _,icons_ in pairs(node.PropPanel and node.PropPanel.SubCategories or {}) do icons=icons+#icons_ end
    end
   end
   emit('NPCTAB',{found=found,icons=icons})
  end)
  if not ok then fail('npctab',why) end
 end)
end
function Q.CloseMenu() RunConsoleCommand('-menu') closeWindows() end
-- The hotloader's own window, one character selected (its preview).
function Q.Library(id)
 closeWindows()
 local ok,why=pcall(function()
  mmdhl.Open()
  if id and IsValid(mmdhl.window) then mmdhl.window.Library:SelectAsset(id) end
 end)
 if ok then emit('LIBRARY',{selected=id}) else fail('library',why) end
end
-- Sandbox's Player Model window (context menu), with its icon for every player model.
function Q.PlayerModels()
 closeWindows()
 local ok,why=pcall(function()
  local entry=list.Get('DesktopWindows').PlayerEditor
  local window=vgui.Create('DFrame') window:SetSize(entry.width,entry.height) window:Center()
  entry.init(nil,window) window:MakePopup() Q.playerWindow=window
  local icons,mmd=0,0
  local function walk(panel)
   for _,child in ipairs(panel:GetChildren()) do
    if child:GetName()=='SpawnIcon' or child.ClassName=='SpawnIcon' or child.model_path then
     icons=icons+1 if carrier(child.model_path or (child.GetModelName and child:GetModelName())) then mmd=mmd+1 end
    end
    walk(child)
   end
  end
  timer.Simple(1,function() if IsValid(window) then walk(window) end emit('PLAYERMODELS',{icons=icons,mmd=mmd}) end)
 end)
 if not ok then fail('playermodels',why) end
end
-- Spawns through the library's own request and status route; times it until the character is
-- shown (its client presentation instance exists).
local function presented(predicate,label,started,timeout)
 local name='R13A.Presented.'..label
 hook.Add('Think',name,function()
  for _,e in ipairs(mmdhl.Entities and mmdhl.Entities() or {}) do
   if IsValid(e) and predicate(e) and e.MMDHLClientInstance then
    hook.Remove('Think',name)
    emit('PRESENTED',{label=label,ms=math.floor((SysTime()-started)*1000),index=e:EntIndex(),model=e:GetModel(),error=e:GetModel()=='models/error.mdl'})
    return
   end
  end
  if SysTime()-started>(timeout or 90) then
   hook.Remove('Think',name)
   -- Why: each MMD entity as this client sees it.
   local seen={}
   for _,e in ipairs(ents.GetAll()) do if #seen<8 and IsValid(e) and (mmdhl.IsMMD(e) or carrier(e:GetModel())) then
    seen[#seen+1]={index=e:EntIndex(),class=e:GetClass(),model=e:GetModel(),asset=mmdhl.GetAsset(e),instance=e.MMDHLClientInstance,
     attachError=e.MMDHLAttachError and mmdhl.Localize(tostring(e.MMDHLAttachError)) or nil,dormant=e:IsDormant()}
   end end
   emit('NOT_PRESENTED',{label=label,entities=seen})
   fail('presented',label..' timeout')
  end
 end)
end
Q.WaitPresented=presented
function Q.Spawn(id,role,label,extra)
 local options=mmdhl.GetGlobalSettings and mmdhl.GetGlobalSettings() or {}
 options.role=role options.frozen=true options.weapon='none'
 for k,v in pairs(extra or {}) do options[k]=v end
 local started=SysTime()
 local ok,err=mmdhl.RequestSpawn(id,options,function(state,message,index)
  if state=='ready' then
   emit('SPAWN',{label=label,asset=id,role=role,state=state,index=index,ms=math.floor((SysTime()-started)*1000)})
   presented(function(e) return e:EntIndex()==index end,label,started)
  elseif state=='error' then fail('spawn',label..' '..mmdhl.Localize(tostring(message))) end
 end)
 if not ok then fail('spawn',label..' '..tostring(err)) end
end
-- The NPC tab's own spawn command for a registered entry (Sandbox's InternalSpawnNPC).
function Q.NPCTabSpawn(key,asset,label)
 local started=SysTime() local before={}
 for _,e in ipairs(ents.GetAll()) do before[e]=true end
 RunConsoleCommand('gmod_spawnnpc',key,'none')
 presented(function(e) return not before[e] and e:IsNPC() and mmdhl.GetAsset(e)==asset end,label,started)
end
function Q.SpawnClassic(class,label)
 RunConsoleCommand('gmod_spawnnpc',class)
 emit('CLASSIC',{class=class,label=label})
end
-- The player-model selector's choice; the server respawns the player to apply it.
function Q.ChoosePlayerModel(key,model,label)
 Q.playerChoice={started=SysTime(),model=model,label=label}
 RunConsoleCommand('cl_playermodel',key)
end
function Q.WaitPlayer()
 local c=Q.playerChoice if not c then return end
 presented(function(e) return e==LocalPlayer() and e:GetModel()==c.model end,c.label,c.started)
end
-- Follow an entity with the camera for screenshots.
function Q.View(index)
 closeWindows()
 local e=Entity(index)
 hook.Remove('CalcView','R13A.View') hook.Remove('ShouldDrawLocalPlayer','R13A.View')
 if not IsValid(e) then return end
 if e==LocalPlayer() then hook.Add('ShouldDrawLocalPlayer','R13A.View',function() return true end) end
 hook.Add('CalcView','R13A.View',function()
  if not IsValid(e) then return end
  local at=e:GetPos()+Vector(0,0,45)
  local eye=at+(e:IsRagdoll() and Vector(-130,-60,25) or e:GetForward()*120+Vector(0,0,10))
  return {origin=eye,angles=(at-eye):Angle(),fov=55,drawviewer=true}
 end)
 hook.Add('HUDShouldDraw','R13A.View',function(name) if name~='CHudGMod' then return false end end)
end
function Q.ResetView() hook.Remove('CalcView','R13A.View') hook.Remove('ShouldDrawLocalPlayer','R13A.View') hook.Remove('HUDShouldDraw','R13A.View') end
-- Errors and missing models this session printed or showed (client side).
function Q.ErrorModels()
 local list={}
 for _,e in ipairs(ents.GetAll()) do if IsValid(e) and e:GetModel()=='models/error.mdl' then list[#list+1]={index=e:EntIndex(),class=e:GetClass()} end end
 emit('ERROR_MODELS',{entities=list})
end
print('R13A_INSTALLED client')
