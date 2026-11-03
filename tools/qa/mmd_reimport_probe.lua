-- R12-A QA only. Injected into the two realms of the isolated PoC session.
R12A={retained={}}
local Q=R12A
local function emit(kind,value) print('R12A_'..kind..' '..util.TableToJSON(value or {})) end
hook.Add('MMDHL.AssetForgotten','R12A.ObserveForget',function(id)
 if id==Q.asset then Q.forgotten=(Q.forgotten or 0)+1 emit('FORGOT',{server=SERVER,asset=id,count=Q.forgotten}) end
end)
if CLIENT then
 function Q.Import(source)
  local handle,err=mmdhl.native.BeginImport(source,mmdhl.library.CharacterImportOptions())
  assert(handle,err)
  timer.Create('R12A.Import',.1,0,function()
   local status,why=mmdhl.Decode(mmdhl.native.PollJob(handle))
   if not status then timer.Remove('R12A.Import') print('R12A_ERROR import '..tostring(why)) return end
   if status.state=='complete' then
    timer.Remove('R12A.Import') Q.asset=status.asset mmdhl.library.Refresh()
    emit('IMPORTED',{asset=Q.asset,source=source})
   elseif status.state=='failed' or status.state=='cancelled' then
    timer.Remove('R12A.Import') print('R12A_ERROR import '..tostring(status.error or status.state))
   end
  end)
 end
 function Q.Spawn(role,scale)
  local options=mmdhl.GetGlobalSettings()
  options.role=role options.gender='female' options.frozen=true options.weapon='none'
  options.scaleMultiplier=scale
  local ok,err=mmdhl.RequestSpawn(Q.asset,options,function(state,message,index)
   if state=='ready' then emit('READY',{index=index,role=role})
   elseif state=='error' then print('R12A_ERROR spawn '..mmdhl.Localize(tostring(message))) end
  end)
  if not ok then print('R12A_ERROR spawn '..tostring(err)) end
 end
 function Q.Delete()
  mmdhl.library.Delete({Q.asset},function(ok,message)
   if not ok then print('R12A_ERROR delete '..tostring(message)) return end
   emit('DELETED',{asset=Q.asset,message=mmdhl.Localize(message),present=mmdhl.library.entries[Q.asset]~=nil})
  end)
 end
 function Q.View(index)
  -- An isolated data directory shows the first-run Remix guide. Close QA
  -- dialogs so the screenshot records the actual actor, rather than that guide.
  for _,panel in ipairs(vgui.GetWorldPanel():GetChildren()) do
   if IsValid(panel) and isfunction(panel.GetTitle) and isfunction(panel.Close) then panel:Close() end
  end
  local e=Entity(index)
  if not IsValid(e) then return end
  if e==LocalPlayer() then
   hook.Add('ShouldDrawLocalPlayer','R12A.View',function() return true end)
  end
  hook.Add('CalcView','R12A.View',function()
   if not IsValid(e) then return end
   local at=e:GetPos()+Vector(0,0,40)
   local eye=at+(e:IsRagdoll() and Vector(-145,-70,20) or Vector(145,70,20))
   return {origin=eye,angles=(at-eye):Angle(),fov=55,drawviewer=true}
  end)
  hook.Add('HUDShouldDraw','R12A.View',function() return false end)
  gui.HideGameUI()
 end
 function Q.Inspect(index)
  local e=Entity(index) local rig=IsValid(e) and mmdhl.GetRig(e)
  emit('CLIENT',{index=index,valid=IsValid(e),rig=rig and rig.key,
   instance=IsValid(e) and mmdhl.GetInstance(e) or 0,
   manifest=rig and file.Exists('mmd_hotloader/rigs/'..rig.key..'/rig.json','DATA'),
   model=IsValid(e) and e:GetModel(),attached=IsValid(e) and mmdhl.IsMMD(e)})
 end
else
 -- Stand in for compositeentities' outer wrapper. Both paths still delegate
 -- through the installed persistence wrapper and retain any model conversion.
 local meta=FindMetaTable('Entity') local set=meta.SetModel
 local info=debug.getinfo(set,'S') Q.wrapper={source=info.short_src,line=info.linedefined}
 meta.SetModel=function(e,path,...) Q.setCalls=(Q.setCalls or 0)+1 return set(e,path,...) end
 function Q.Inspect(index)
  local e=Entity(index) assert(IsValid(e),'spawn not on server')
  e:SetPos(Vector(0,0,0)) e:SetAngles(Angle(0,0,0))
  local rig=mmdhl.GetRig(e)
  local ready,why=mmdhl.EnsureModel(e:GetModel())
  if not e:IsPlayer() then Q.retained[#Q.retained+1]={ent=e,model=e:GetModel(),key=rig and rig.key} end
  emit('ENTITY',{index=index,class=e:GetClass(),asset=mmdhl.GetAsset(e),model=e:GetModel(),
   key=e:GetNW2String('MMDHLRig'),valid=util.IsValidModel(e:GetModel()),attached=mmdhl.IsMMD(e),
   ready=ready~=nil,error=why and mmdhl.Localize(why),bindingError=e.MMDHLBindingError,
   manifest=rig and file.Exists('mmd_hotloader/rigs/'..rig.key..'/rig.json','DATA'),
   modelRig=mmdhl.GetRigForModel(e:GetModel())~=nil,physics=e:GetPhysicsObjectCount(),
   setCalls=Q.setCalls})
 end
 function Q.Conversion()
  -- Dupes/tools can give an NPC a ragdoll carrier. Exercise the persistence
  -- conversion memo twice across deletion, rather than only the actor factory.
  local rig
  for _,r in pairs(mmdhl.rigs) do if r.asset==Q.asset and r.role=='ragdoll' then rig=r break end end
  if not rig then emit('CONVERTED',{skipped='no ragdoll carrier'}) return end
  local ent=ents.Create('npc_citizen') ent:SetModel(rig.model) ent:SetKeyValue('citizentype','4') ent:SetPos(Vector(100,0,0)) ent:Spawn()
  timer.Simple(.5,function()
   local r=mmdhl.GetRig(ent)
   emit('CONVERTED',{attached=mmdhl.IsMMD(ent),valid=util.IsValidModel(ent:GetModel()),
    input=rig.model,model=ent:GetModel(),forgotten=Q.forgotten,
    ready=mmdhl.EnsureModel(ent:GetModel())~=nil,key=r and r.key,role=r and r.role})
   Q.retained[#Q.retained+1]={ent=ent,model=ent:GetModel(),key=r and r.key}
  end)
 end
 function Q.CheckRetained()
  local result={}
  for _,old in ipairs(Q.retained) do if IsValid(old.ent) then
   local rig=mmdhl.GetRig(old.ent)
   result[#result+1]={model=old.ent:GetModel(),same=old.ent:GetModel()==old.model,
    rig=rig and rig.key,expected=old.key,valid=util.IsValidModel(old.ent:GetModel())}
  end end
  emit('RETAINED',result)
 end
end
emit('INSTALLED',{server=SERVER,wrapper=Q.wrapper})
