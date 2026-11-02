-- R10-H server probe. Inject through console Lua, never install as an autorun.
local Q={tag='r10_h_'..os.time(),frames={},files={},mapping={},shots={}}
R10MMDQA=Q
local M=MMDVMDNPC
function Q.Spawn(prefix,role)
 if IsValid(Q.ent) then M.StopPlayback(Q.ent,true) Q.ent:Remove() Q.ent=nil end
 local _,dirs=file.Find('mmd_hotloader/assets/*','DATA') local id
 for _,candidate in ipairs(dirs) do if candidate:sub(1,#prefix)==prefix then id=candidate break end end
 assert(id,'QA asset absent')
 local p=player.GetAll()[1]
 local spawn=role=='ragdoll' and mmdhl.Spawn or mmdhl.SpawnNPC
 local function done(ent,err)
  if not IsValid(ent) then print('R10_QA_ERROR spawn '..tostring(err)) return end
  Q.ent=ent ent:SetAngles(Angle(0,0,0)) ent:SetPos(Vector(0,0,0))
  print('R10_QA_SPAWN '..util.TableToJSON({index=ent:EntIndex(),model=ent:GetModel(),role=role,map=game.GetMap(),valid=util.IsValidModel(ent:GetModel()),attached=mmdhl.IsMMD(ent),key=ent:GetNW2String('MMDHLRig')}))
 end
 if role=='ragdoll' then spawn(p,id,{position={0,0,0},frozen=true},done)
 else spawn(p,id,'citizen',{position={0,0,0},weapon='none'},done) end
end
function Q.Menu(prefix)
 for model,entry in pairs(mmdhl.actorRegistrations) do if entry.rig.asset:sub(1,#prefix)==prefix and entry.rig.role=='citizen' then
  print('R10_QA_MENU_READY '..util.TableToJSON({model=model,exists=file.Exists(model,'GAME'),valid=util.IsValidModel(model),map=game.GetMap()}))
  player.GetAll()[1]:ConCommand('gmod_spawnnpc mmd_'..entry.rig.key:sub(1,16)) return
 end end
 print('R10_QA_ERROR menu entry absent')
end
hook.Add('PlayerSpawnedNPC','R10MMDQA.Menu',function(_,ent)
 if not IsValid(ent) or ent.MMDHLNativeSpawn then return end
 timer.Simple(.5,function()
  if not IsValid(ent) then return end
  print('R10_QA_MENU_SPAWN '..util.TableToJSON({model=ent:GetModel(),attached=mmdhl.IsMMD(ent),map=game.GetMap(),index=ent:EntIndex()}))
 end)
end)
local cases={smile={'笑い','eye_blink_happy'},wink={'ウィンク','eye_blink_happy_left'},blink={'まばたき','blink'}}
function Q.Build(kind)
 assert(IsValid(Q.ent),'QA NPC absent')
 local case=assert(cases[kind],'unknown expression') local name,source=unpack(case)
 local p=player.GetAll()[1]
 local selected,why=M.SelectTargetForPlayer(p,Q.ent) assert(selected,why)
 local targets,reason=M.ResolveFlexTargets(Q.ent,source,name)
 local targetsInfo={}
 local morphs=mmdhl.GetMorphs(Q.ent)
 local began=SysTime() local geometry,geometryError=mmdhl.GetMorphGeometry and mmdhl.GetMorphGeometry(Q.ent)
 local geometryMs=(SysTime()-began)*1000
 for _,target in ipairs(targets) do
  for i,m in ipairs(morphs) do if M.MorphControllerID(Q.ent,m)==target.id then
   targetsInfo[#targetsInfo+1]={id=target.id,name=m.name,original=m.original,mmd=m.mmd,side=geometry and geometry[i].side,left=geometry and geometry[i].left}
  end end
 end
 Q.mapping[kind]={motion=name,canonical=source,targets=targetsInfo,reason=reason,geometryMs=geometryMs,geometryError=geometryError}
 print('R10_QA_MAPPING '..util.TableToJSON(Q.mapping[kind]))
 local motion=Q.tag..'_'..kind
 local content={format='mmd_vmd_npc_parent_corrected_axis_v1',fps=30,frame_start=0,frame_end=90,frame_count=91,
  display_name='R10 QA '..name,bones={},flexes={{m=name,g=source,k={{0,0},{15,1},{75,1},{90,0}}}}}
 local motionPath=M.MotionPath(motion)
 assert(not file.Exists(motionPath,'DATA') or Q.files[motionPath],'QA motion path already owned')
 file.CreateDir(M.MotionRoot) file.Write(motionPath,util.TableToJSON(content)) Q.files[motionPath]=true
 M.ClearMotionCache()
 Q.motion=motion Q.kind=kind
 local path=M.BuiltPath(motion,Q.ent:GetModel(),{}) Q.files[path]=true
 if file.Exists(path,'DATA') then print('R10_QA_BUILT '..path) return end
 local ok,err=M.BeginBuildForPlayer(p,motion,{}, {startDelay=2,buildFramesPerBatch=32,musicEnabled=false,pelvisZOffset=0,eyeTrackMode='none'})
 assert(ok,err)
 timer.Create('R10MMDQA.Build',.1,600,function()
  if file.Exists(path,'DATA') then timer.Remove('R10MMDQA.Build') print('R10_QA_BUILT '..path) end
 end)
end
function Q.Play()
 local ok,err=M.StartPlaybackForPlayer(player.GetAll()[1],Q.motion,{}, {startDelay=2,musicEnabled=false,loopPlayback=true,pelvisZOffset=0,eyeTrackMode='none'})
 assert(ok,err) Q.probing=true Q.frames={} Q.held=false
 print('R10_QA_PLAY '..Q.kind)
end
hook.Add('Tick','R10MMDQA.Weights',function()
 if not Q.probing or not IsValid(Q.ent) then return end
 local playback=M.Playbacks[Q.ent] if not playback then return end
 local sourceFrame=(CurTime()-(playback.started or CurTime()))*30
 local weights={}
 for i,m in ipairs(mmdhl.GetMorphs(Q.ent)) do
  local weight=mmdhl.GetMorphWeight(Q.ent,i-1)
  if math.abs(weight or 0)>.0001 or m.original=='笑い' or m.original=='ウィンク' or m.original=='まばたき' then
   weights[#weights+1]={mmd=m.mmd,original=m.original,name=m.name,native=m.native,weight=weight}
  end
 end
 Q.frames[#Q.frames+1]={tick=engine.TickCount(),time=CurTime(),frame=sourceFrame,weights=weights}
 if sourceFrame>=30 and not Q.held then
  Q.held=true Q.probing=false
  M.TogglePlaybackPauseForPlayer(player.GetAll()[1],Q.ent)
  local path='r10_mmd_qa/'..Q.tag..'_'..Q.kind..'.json'
  file.CreateDir('r10_mmd_qa')
  file.Write(path,util.TableToJSON({model=Q.ent:GetModel(),map=game.GetMap(),mapping=Q.mapping[Q.kind],frames=Q.frames,generated=table.GetKeys(Q.files)},true))
  print('R10_QA_HELD '..util.TableToJSON({kind=Q.kind,index=Q.ent:EntIndex(),probe=path,motion=Q.motion}))
 end
end)
function Q.Stop()
 if IsValid(Q.ent) then M.StopPlayback(Q.ent,true) end
 Q.probing=false
end
print('R10_QA_INSTALLED '..Q.tag)
