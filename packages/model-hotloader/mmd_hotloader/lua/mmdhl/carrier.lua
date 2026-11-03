-- Native ragdolls retain all engine methods. These helpers expose the attached MMD state.
local native=mmdhl.native
local L=mmdhl.L
mmdhl.rigs=mmdhl.rigs or {}
mmdhl.rigsByModel=mmdhl.rigsByModel or {}
local rigWriteSerial=0
-- A mounted carrier can survive deletion on Windows while rig.json does not.
-- PrepareCarrier then returns its manifest from the native fit cache instead of
-- packaging it again. Save that authoritative manifest before any SetModel or
-- client notification; a mounted MDL alone cannot restore its MMD identity.
function mmdhl.RememberRig(rig)
 if not mmdhl.IsLoadableRig(rig) or not isstring(rig.key) or (#rig.key~=32 and #rig.key~=64) or rig.key:find('[^a-f0-9]') or
  not isstring(rig.asset) or #rig.asset~=64 or rig.asset:find('[^a-f0-9]') or not isstring(rig.model) or
  not rig.model:match('^models/mmd/'..rig.key:sub(1,16)..'/[^/]+%.mdl$') then return false end
 local path='mmd_hotloader/rigs/'..rig.key..'/rig.json'
 if not file.Exists(path,'DATA') then
  if not file.Exists('mmd_hotloader/rigs/'..rig.key..'/carrier.gma','DATA') then return false end
  local json=util.TableToJSON(rig,true) if not json then return false end
  -- A short/failed write must not leave a final sidecar that the next attempt
  -- mistakes for existing metadata. Never overwrite an existing sidecar.
  local staged
  repeat rigWriteSerial=rigWriteSerial+1 staged='mmd_hotloader/rigs/'..rig.key..'/rig-restore-'..os.time()..'-'..rigWriteSerial..'.json' until not file.Exists(staged,'DATA')
  file.Write(staged,json)
  if file.Read(staged,'DATA')~=json then return false end
  if not file.Exists(path,'DATA') then file.Rename(staged,path) end
  local saved=file.Read(path,'DATA')==json
  if file.Read(staged,'DATA')==json then file.Delete(staged) end
  if not saved then return false end
 end
 mmdhl.rigs[rig.key]=rig mmdhl.rigsByModel[rig.model]=rig
 return true
end
-- Reusable lookup/fit state belongs to a library entry's lifetime. Live
-- entities retain their bound immutable manifest instead of using these maps.
function mmdhl.ForgetAssetRigs(id)
 for key,rig in pairs(mmdhl.rigs) do if rig.asset==id then mmdhl.rigs[key]=nil end end
 for model,rig in pairs(mmdhl.rigsByModel) do if rig.asset==id then mmdhl.rigsByModel[model]=nil end end
 hook.Run('MMDHL.AssetForgotten',id)
end
-- On the client, networked strings change only while network updates are processed
-- between frames, so each is read once per frame. Rendering asks for the asset and
-- rig of every model dozens of times per frame through these helpers.
local function networkedAsset(ent)
 if SERVER then return ent:GetNW2String('MMDHLAsset','') end
 local frame=FrameNumber() if ent.MMDHLAssetFrame~=frame then ent.MMDHLAssetFrame=frame ent.MMDHLAssetValue=ent:GetNW2String('MMDHLAsset','') end
 return ent.MMDHLAssetValue
end
local function networkedRig(ent)
 if SERVER then return ent:GetNW2String('MMDHLRig','') end
 local frame=FrameNumber() if ent.MMDHLRigFrame~=frame then ent.MMDHLRigFrame=frame ent.MMDHLRigValue=ent:GetNW2String('MMDHLRig','') end
 return ent.MMDHLRigValue
end
function mmdhl.IsMMD(ent)
 if not IsValid(ent) then return false end
 local class=ent:GetClass()
 -- Hands/viewmodels already contain native studio geometry. Attaching a full
 -- PMX instance to their viewmodel-space skeleton creates a second body.
 if class=='gmod_hands' or class=='viewmodel' or ent.MMDHLHands then return false end
 return ent.MMDHLLocalAsset~=nil or ent.MMDHLPreviewRig~=nil or networkedAsset(ent)~='' or class=='mmdhl_ragdoll'
end
-- Client-only entities (corpses from CreateClientsideRagdoll, editor previews)
-- have entity index -1: the server cannot resolve them, so their edits apply
-- here instead of travelling as net messages.
function mmdhl.IsClientOnly(ent) return CLIENT and IsValid(ent) and ent:EntIndex()<0 end
function mmdhl.GetAsset(ent) if ent.MMDHLLocalAsset then return ent.MMDHLLocalAsset end if ent.MMDHLPreviewRig then return ent.MMDHLPreviewRig.asset end return ent:GetClass()=='mmdhl_ragdoll' and ent:GetAsset() or networkedAsset(ent) end
function mmdhl.GetInstance(ent) return ent.MMDHLClientInstance or (ent:GetClass()=='mmdhl_ragdoll' and ent:GetInstance() or 0) end
-- Model metadata also belongs to invisible animation/pose controllers. It is
-- not permission to create a second visible character or secondary world.
function mmdhl.PresentationSuppressed(ent)
 if not IsValid(ent) then return true end
 -- Another addon's copy of a player model (player_copies.lua) is shown while that
 -- addon draws it, whatever its no-draw flag (it is drawn by hand).
 if ent.MMDHLCopyOf then return RealTime()-(ent.MMDHLDrawnAt or -math.huge)>1 end
 if ent:GetNoDraw() or ent:IsEffectActive(EF_NODRAW) or ent:GetNW2Bool('MMDHLNoDraw',false) then return true end
 return CLIENT and ent:EntIndex()>0 and (ent.MMDHLNotTransmitting==true or ent:IsDormant()) or false
end
-- Whether the client should destroy the model's world, not merely skip drawing
-- it. Client addons hide distant entities locally (distance culling), often
-- toggling the flag every frame; rebuilding the physics world and buffers each
-- time made the game crawl. A local hide therefore releases only once it has
-- lasted a few seconds; server intent, dormancy and removal release at once.
local LocalHideRelease=5
function mmdhl.PresentationReleased(ent)
 if not IsValid(ent) then return true end
 if ent.MMDHLCopyOf then return RealTime()-(ent.MMDHLDrawnAt or -math.huge)>=LocalHideRelease end
 if ent:GetNW2Bool('MMDHLNoDraw',false) then return true end
 if CLIENT and ent:EntIndex()>0 and (ent.MMDHLNotTransmitting==true or ent:IsDormant()) then return true end
 if ent:GetNoDraw() or ent:IsEffectActive(EF_NODRAW) then
  if not CLIENT then return true end
  ent.MMDHLHiddenSince=ent.MMDHLHiddenSince or RealTime()
  return RealTime()-ent.MMDHLHiddenSince>=LocalHideRelease
 end
 ent.MMDHLHiddenSince=nil
 return false
end
local entityFrame,entityCandidates,entityList,entityListFrame
function mmdhl.InvalidateEntityList() entityFrame=nil entityListFrame=nil end
-- Entities that can carry a model, kept incrementally. Busy maps hold thousands
-- of constraints, bone followers and props, and every frame's list (every tick
-- on the server) used to scan them all. Creation adds by class; any other new
-- entity is checked once at the next list, when its model is set; removal
-- drops. A full scan every five seconds catches model changes and entities
-- created before this file ran. The value orders entities without an index.
local carrierClasses={prop_ragdoll=true,mmdhl_ragdoll=true,player=true,prop_dynamic=true,prop_dynamic_override=true,prop_physics=true,prop_physics_multiplayer=true}
local function carrierCandidate(e)
 if e.MMDHLLocalAsset or e.MMDHLPreviewRig then return true end
 local class=e:GetClass()
 return carrierClasses[class] or class:sub(1,4)=='npc_' or (mmdhl.IsCarrierModel and mmdhl.IsCarrierModel(e:GetModel())) or false
end
local candidates,pendingCandidates,candidateOrder,fullScanAt={},{},0,-math.huge
local function addCandidate(e) if not candidates[e] then candidateOrder=candidateOrder+1 candidates[e]=candidateOrder end end
hook.Add('OnEntityCreated','MMDHL.CarrierCandidates',function(e) if carrierClasses[e:GetClass()] or e:GetClass():sub(1,4)=='npc_' then addCandidate(e) else pendingCandidates[e]=true end end)
-- A client full update removes every entity and recreates it, possibly as a new
-- object without OnEntityCreated: rescan at the next list.
hook.Add('EntityRemoved','MMDHL.CarrierCandidates',function(e,fullUpdate) candidates[e]=nil pendingCandidates[e]=nil if fullUpdate then fullScanAt=-math.huge end end)
-- The addon gave e a model locally (an editor preview): include it in the next list.
function mmdhl.NoteCarrier(e) if IsValid(e) then addCandidate(e) mmdhl.InvalidateEntityList() end end
function mmdhl.Entities()
 local frame=CLIENT and FrameNumber() or engine.TickCount()
 -- The client asks for the list many times per frame; reuse it while every entry is still valid.
 if CLIENT and entityListFrame==frame then
  local valid=true for _,e in ipairs(entityList) do if not IsValid(e) then valid=false break end end
  if valid then return entityList end
 end
 if frame~=entityFrame then
  entityFrame=frame entityCandidates={}
  if RealTime()-fullScanAt>=5 then fullScanAt=RealTime() for _,e in ipairs(ents.GetAll()) do if carrierCandidate(e) then addCandidate(e) end end end
  for e in pairs(pendingCandidates) do if IsValid(e) and carrierCandidate(e) then addCandidate(e) end pendingCandidates[e]=nil end
  -- Most candidates are props, not actors; NW2 lookups stay limited to them.
  for e in pairs(candidates) do if not IsValid(e) then candidates[e]=nil elseif mmdhl.IsMMD(e) then entityCandidates[#entityCandidates+1]=e end end
  table.sort(entityCandidates,function(a,b) local x,y=a:EntIndex(),b:EntIndex() if x~=y then return x<y end return candidates[a]<candidates[b] end)
 end
 local list,seen={},{}
 for _,e in ipairs(entityCandidates) do if mmdhl.IsMMD(e) then list[#list+1]=e seen[e]=true end end
 -- Client ragdolls have no network entity index and are not guaranteed to be
 -- included in ents.GetAll(). Keep the engine-created bodies in a weak registry.
 if CLIENT then for e in pairs(mmdhl.clientRagdolls or {}) do
  if mmdhl.IsMMD(e) then if not seen[e] then list[#list+1]=e seen[e]=true end else mmdhl.clientRagdolls[e]=nil end
 end end
 -- So are other addons' copies of player models (player_copies.lua).
 if CLIENT then for e in pairs(mmdhl.playerCopies or {}) do
  if IsValid(e) and mmdhl.IsMMD(e) then if not seen[e] then list[#list+1]=e seen[e]=true end else mmdhl.playerCopies[e]=nil end
 end end
 if CLIENT then entityList=list entityListFrame=frame end
 return list
end
function mmdhl.GetRig(ent)
 if not IsValid(ent) then return end
 if ent.MMDHLLocalRig then return ent.MMDHLLocalRig end
 if ent.MMDHLPreviewRig then return ent.MMDHLPreviewRig end
 local key=ent.MMDHLLocalRigKey or networkedRig(ent) if key=='' then ent.MMDHLBoundRig=nil return end
 if ent.MMDHLBoundRig and ent.MMDHLBoundRig.key==key then return ent.MMDHLBoundRig end
 if not mmdhl.rigs[key] then mmdhl.rigs[key]=util.JSONToTable(file.Read('mmd_hotloader/rigs/'..key..'/rig.json','DATA') or '') end
 ent.MMDHLBoundRig=mmdhl.rigs[key]
 return ent.MMDHLBoundRig
end
function mmdhl.GetMetadata(ent) local info=mmdhl.assets and mmdhl.assets[mmdhl.GetAsset(ent)] if not info then info=mmdhl.Decode(native.AssetInfo(mmdhl.GetAsset(ent))) end return {asset=mmdhl.GetAsset(ent),rig=mmdhl.GetRig(ent),model=info} end
function mmdhl.GetMorphs(ent) local rig=mmdhl.GetRig(ent) return rig and rig.morphs or {} end
-- R10 PMX geometry helpers (kept in this trusted bundled source path).
do
-- Read only the geometry needed to classify a PMX expression. The immutable imported
-- model.bin is the source of truth; controller suffixes are never a side measurement.
local cache,order={},{}
hook.Add('MMDHL.AssetForgotten','MMDHL.MorphGeometry',function(id)
 cache[id]=nil for i=#order,1,-1 do if order[i]==id then table.remove(order,i) end end
end)
local function side(left)
 if not left then return 'unknown' end
 return left>=.8 and 'left' or left<=.2 and 'right' or 'both'
end
local function readGeometry(f)
 local size=f:Size()
 if size>256*1024*1024 then error('PMX geometry exceeds reader budget') end
 local data=f:Read(size) if not data or #data~=size then error('truncated PMX morph geometry') end
 local pos=1
 local function need(n) if n<0 or n>size-pos+1 then error('truncated PMX morph geometry') end end
 local function skip(n) need(n) pos=pos+n end
 local function byte() need(1) local v=data:byte(pos) pos=pos+1 return v end
 local function unsigned(n)
  need(n) local v=0
  for i=0,n-1 do v=v+data:byte(pos+i)*256^i end
  pos=pos+n return v
 end
 local function long() local v=unsigned(4) return v>=2147483648 and v-4294967296 or v end
 local function float()
  need(4) local a,b,c,d=data:byte(pos,pos+3) pos=pos+4
  local exponent=(d%128)*2+math.floor(c/128)
  local fraction=a+b*256+(c%128)*65536
  if exponent==255 then error('nonfinite PMX geometry') end
  local value=exponent==0 and math.ldexp(fraction,-149) or math.ldexp(fraction+8388608,exponent-150)
  return d>=128 and -value or value
 end
 local function count(limit) local n=long() if n<0 or n>limit then error('PMX geometry count exceeds limit') end return n end
 local function text() skip(count(size)) end
 local function index(n,unsigned)
  need(n)
  if n==1 then local v=byte() return not unsigned and v>=128 and v-256 or v end
  if n==2 then local v=byte()+byte()*256 return not unsigned and v>=32768 and v-65536 or v end
  if n==4 then local v=long() return unsigned and v<0 and v+4294967296 or v end
  error('invalid PMX index width')
 end
 need(4) if data:sub(1,4)~='PMX ' then error('geometry is available for PMX only') end pos=5
 local version=float() if version<2 or version>2.11 then error('unknown PMX version') end
 local globals=byte() if globals<8 then error('invalid PMX header') end
 local encoding,uv,vs,ts,ms,bs,mrs,rs=byte(),byte(),byte(),byte(),byte(),byte(),byte(),byte()
 if encoding>1 or uv>4 then error('invalid PMX globals') end
 for _,n in ipairs({vs,ts,ms,bs,mrs,rs}) do if n~=1 and n~=2 and n~=4 then error('invalid PMX index width') end end
 skip(globals-8) for _=1,4 do text() end
 local xs={}
 local vertices=count(2000000)
 for i=1,vertices do
  xs[i]=float() skip(28+uv*16)
  local deform=byte()
  if deform==0 then skip(bs)
  elseif deform==1 then skip(2*bs+4)
  elseif deform==2 or deform==4 then skip(4*bs+16)
  elseif deform==3 then skip(2*bs+40)
  else error('unknown PMX deform') end
  skip(4)
 end
 skip(count(12000000)*vs)
 for _=1,count(100000) do text() end
 for _=1,count(100000) do
  text() text() skip(66+2*ts)
  local shared=byte() if shared==0 then skip(ts) elseif shared==1 then skip(1) else error('invalid PMX toon') end
  text() skip(4)
 end
 for _=1,count(100000) do
  text() text() skip(12+bs+4) local flags=unsigned(2)
  if bit.band(flags,1)~=0 then skip(bs) else skip(12) end
  if bit.band(flags,0x300)~=0 then skip(bs+4) end
  if bit.band(flags,0x400)~=0 then skip(12) end
  if bit.band(flags,0x800)~=0 then skip(24) end
  if bit.band(flags,0x2000)~=0 then skip(4) end
  if bit.band(flags,0x20)~=0 then
   skip(bs+8)
   for _=1,count(100000) do skip(bs) if byte()~=0 then skip(24) end end
  end
 end
 local morphs={}
 for i=1,count(100000) do
  text() text() local panel,kind=byte(),byte() local n=count(2000000)
  local m={panel=panel,type=kind,total=0,leftWeight=0} morphs[i]=m
  if kind==1 then
   m.offsetStart=pos m.count=n
   for _=1,n do
    local v=index(vs,true)+1 local x,y,z=float(),float(),float()
    if not xs[v] then error('invalid PMX morph vertex') end
    local w=math.sqrt(x*x+y*y+z*z) m.total=m.total+w
    if xs[v]>0 then m.leftWeight=m.leftWeight+w end
   end
  elseif kind==0 or kind==9 then
   m.children={} for j=1,n do m.children[j]={index(mrs,false)+1,float()} end
  elseif kind==2 then skip(n*(bs+28))
  elseif kind>=3 and kind<=7 then skip(n*(vs+16))
  elseif kind==8 then skip(n*(ms+113))
  elseif kind==10 then skip(n*(rs+25))
  else error('unknown PMX morph type') end
 end
 -- Combine signed displacement vectors before measuring a group. Summing
 -- child magnitudes can call a cancelled eye "both". Re-read only referenced
 -- vertex spans instead of retaining every model offset in Lua memory.
 local function collect(i,scale,vertices,visiting,depth)
  local m=morphs[i] if not m or visiting[i] or depth>64 then error('invalid PMX morph group') end
  if scale==0 then return true end
  if scale~=scale or math.abs(scale)==math.huge then error('nonfinite PMX group weight') end
  visiting[i]=true local complete=true
  if m.type==1 then
   pos=m.offsetStart
   for _=1,m.count do
    local v=index(vs,true)+1 local x,y,z=float()*scale,float()*scale,float()*scale
    local out=vertices[v]
    if out then out[1]=out[1]+x out[2]=out[2]+y out[3]=out[3]+z else vertices[v]={x,y,z} end
   end
  elseif m.type==0 then
   for _,child in ipairs(m.children) do if not collect(child[1],scale*child[2],vertices,visiting,depth+1) then complete=false end end
  else
   -- Bone/UV/material and stepped flip effects cannot be measured from vertex
   -- offsets alone. Exact-name playback still drives them normally.
   complete=false
  end
  visiting[i]=nil return complete
 end
 for i,m in ipairs(morphs) do
  local complete=true
  if m.type==0 then
   local vertices={} complete=collect(i,1,vertices,{},0)
   for v,delta in pairs(vertices) do
    local w=math.sqrt(delta[1]^2+delta[2]^2+delta[3]^2)
    m.total=m.total+w if xs[v]>0 then m.leftWeight=m.leftWeight+w end
   end
  end
  m.left=complete and m.total>1e-12 and m.total<math.huge and m.leftWeight/m.total or nil m.side=side(m.left)
 end
 return morphs
end
mmdhl.ReadMorphGeometry=readGeometry -- also exercised against generated PMX fixtures
function mmdhl.GetMorphGeometry(ent)
 local rig=mmdhl.GetRig(ent) if not rig then return nil,'model metadata unavailable' end
 local id=rig.asset if cache[id] then return cache[id] end
 if not isstring(id) or #id~=64 or id:find('[^a-f0-9]') then return nil,'invalid model id' end
 local f=file.Open('mmd_hotloader/assets/'..id..'/model.bin','rb','DATA')
 if not f then return nil,'imported model geometry unavailable' end
 local ok,result=pcall(readGeometry,f) f:Close()
 if not ok then return nil,tostring(result) end
 if #result~=#rig.morphs then return nil,'model geometry and rig morph counts differ' end
 cache[id]=result order[#order+1]=id
 if #order>16 then cache[table.remove(order,1)]=nil end
 return result
end

end
-- End R10 PMX geometry helpers.
function mmdhl.GetMorphWeight(ent,index)
 local morph=mmdhl.GetMorphs(ent)[index+1] if not morph then return end
 return morph.native>=0 and ent:GetFlexWeight(morph.native) or (ent.MMDHLLocalMorphs and ent.MMDHLLocalMorphs[index+1]) or ent:GetNW2Float('MMDHLMorph'..index,0)
end
function mmdhl.SetMorphWeight(ent,index,value)
 if not mmdhl.IsMMD(ent) or not isnumber(value) or value~=value then return false end
 local morph=mmdhl.GetMorphs(ent)[index+1] if not morph then return false end value=math.Clamp(value,-2,2)
 if mmdhl.IsClientOnly(ent) then
  if morph.native>=0 then ent:SetFlexWeight(morph.native,value) else ent.MMDHLLocalMorphs=ent.MMDHLLocalMorphs or {} ent.MMDHLLocalMorphs[index+1]=value end
  return true
 end
 if CLIENT then net.Start('mmdhl_native_morph') net.WriteEntity(ent) net.WriteUInt(index,16) net.WriteFloat(value) net.SendToServer() return true end
 if morph.native>=0 then ent:SetFlexWeight(morph.native,value) else ent:SetNW2Float('MMDHLMorph'..index,value) end
 if mmdhl.GetInstance(ent)>0 then native.SetMorph(mmdhl.GetInstance(ent),index,value*ent:GetFlexScale()) end return true
end
function mmdhl.SetMorphWeights(ent,values)
 if not mmdhl.IsMMD(ent) or not istable(values) or #values~=#mmdhl.GetMorphs(ent) then return false end
 for i,v in ipairs(values) do if not isnumber(v) or v~=v or math.abs(v)==math.huge then return false end values[i]=math.Clamp(v,-2,2) end
 if mmdhl.IsClientOnly(ent) then
  ent.MMDHLLocalMorphs=ent.MMDHLLocalMorphs or {}
  for i,m in ipairs(mmdhl.GetMorphs(ent)) do if m.native>=0 then ent:SetFlexWeight(m.native,values[i]) else ent.MMDHLLocalMorphs[i]=values[i] end end
  return true
 end
 if CLIENT then net.Start('mmdhl_native_morphs') net.WriteEntity(ent) net.WriteUInt(#values,16) for _,v in ipairs(values) do net.WriteFloat(v) end net.SendToServer() return true end
 local weights={} for i,m in ipairs(mmdhl.GetMorphs(ent)) do local v=values[i] if m.native>=0 then ent:SetFlexWeight(m.native,v) else ent:SetNW2Float('MMDHLMorph'..m.mmd,v) end weights[i]=v*ent:GetFlexScale() end
 if mmdhl.GetInstance(ent)>0 then return native.SetMorphs(mmdhl.GetInstance(ent),util.TableToJSON(weights)) end return true
end
function mmdhl.GetDiagnostics(ent,detailed) if mmdhl.GetInstance(ent)>0 then return mmdhl.Decode(native.GetDiagnostics(mmdhl.GetInstance(ent),detailed~=false)) end return {asset=mmdhl.GetAsset(ent),clientSimulated=true,sourceObjects=ent:GetPhysicsObjectCount()} end
function mmdhl.SetManualBonePose(ent,index,pose)
 if not SERVER or not mmdhl.IsMMD(ent) or not isnumber(index) or index<0 or index%1~=0 or not istable(pose) then return false end
 local info=mmdhl.Decode(native.AssetInfo(mmdhl.GetAsset(ent)))
 if not info or index>=(info.bones or 0) then return false end
 local p=pose.translation or {0,0,0} local q=pose.rotation or {0,0,0,1}
 if #p~=3 or #q~=4 then return false end
 local length=0
 for _,values in ipairs({p,q}) do for _,v in ipairs(values) do if not isnumber(v) or v~=v or math.abs(v)>10000 then return false end end end
 for _,v in ipairs(q) do length=length+v*v end if length<1e-8 then return false end
 local clean={translation=p,rotation=q}
 ent.MMDHLManual=ent.MMDHLManual or {} ent.MMDHLManual[index+1]=clean
 ent:SetNW2String('MMDHLManual'..index,util.TableToJSON(clean))
 ent:SetNW2Int('MMDHLManualRevision',ent:GetNW2Int('MMDHLManualRevision',0)+1)
 return true
end

if SERVER then
 util.AddNetworkString('mmdhl_native_morph')
 util.AddNetworkString('mmdhl_native_morphs')
 util.AddNetworkString('mmdhl_collision_mesh')
 net.Receive('mmdhl_collision_mesh',function(_,p)
  local ent=net.ReadEntity() if not mmdhl.CanEdit(p,ent,'bodygroups') or ent:GetPhysicsObjectCount()~=18 then return end
  local meshes={}
  for i=0,17 do local body=ent:GetPhysicsObjectNum(i) local mesh={vertices={},edges={}} local seen,edges={},{}
   for _,convex in ipairs(body:GetMeshConvexes() or {}) do for j=1,#convex,3 do local triangle={}
    for k=0,2 do local v=convex[j+k].pos local key=string.format('%.5f/%.5f/%.5f',v.x,v.y,v.z)
     if not seen[key] then mesh.vertices[#mesh.vertices+1]={v:Unpack()} seen[key]=#mesh.vertices end triangle[k+1]=seen[key]
    end
    for k=1,3 do local a,b=triangle[k],triangle[k%3+1] local key=math.min(a,b)..':'..math.max(a,b) if not edges[key] then edges[key]=true mesh.edges[#mesh.edges+1]={a,b} end end
   end end meshes[i+1]=mesh
  end
  local bytes=util.Compress(util.TableToJSON(meshes)) if #bytes>60000 then return end
  net.Start('mmdhl_collision_mesh') net.WriteEntity(ent) net.WriteString(ent:GetNW2String('MMDHLRig','')) net.WriteUInt(#bytes,16) net.WriteData(bytes,#bytes) net.Send(p)
 end)
 net.Receive('mmdhl_native_morph',function(_,p) local e=net.ReadEntity() local index,value=net.ReadUInt(16),net.ReadFloat() if mmdhl.CanEdit(p,e,'faceposer') then mmdhl.SetMorphWeight(e,index,value) end end)
 net.Receive('mmdhl_native_morphs',function(_,p) local e=net.ReadEntity() local n=net.ReadUInt(16) if not mmdhl.CanEdit(p,e,'faceposer') or n~=#mmdhl.GetMorphs(e) then return end local values={} for i=1,n do values[i]=net.ReadFloat() end mmdhl.SetMorphWeights(e,values) end)
 -- Native carrier, tools, visual and stability gates are recorded in the
 -- validation report. The previous custom entity remains an explicit fallback.
 CreateConVar('mmdhl_native_carrier','1',FCVAR_ARCHIVE,'Use the native Source ragdoll carrier backend')
 -- CreateConVar's default does not replace the prototype's archived zero.
 -- Migrate once; an explicitly selected legacy fallback after this is retained.
 local backendVersion=CreateConVar('mmdhl_backend_version','0',FCVAR_ARCHIVE,'Model Hotloader backend settings migration version')
 if backendVersion:GetInt()<1 then GetConVar('mmdhl_native_carrier'):SetInt(1) backendVersion:SetInt(1) end
 local function save(ent)
  if mmdhl.StoreNativeState then return mmdhl.StoreNativeState(ent) end
  local weights={} for i in ipairs(mmdhl.GetMorphs(ent)) do weights[i]=mmdhl.GetMorphWeight(ent,i-1) end
  local state=mmdhl.GetInstance(ent)>0 and mmdhl.Decode(native.GetState(mmdhl.GetInstance(ent))) or nil
  duplicator.StoreEntityModifier(ent,'MMDHLNative',{version=3,rig=mmdhl.GetRig(ent),asset=mmdhl.GetAsset(ent),options=ent.MMDOptions,morphs=weights,scale=ent:GetFlexScale(),manual=state and state.manual or ent.MMDHLManual,eyeTarget=ent.MMDEyeTarget,eyeDriver=ent.MMDHLEyeDriver,materials=mmdhl.CaptureMaterialState and mmdhl.CaptureMaterialState(ent)})
 end
 function mmdhl.AttachNative(ent,id,options)
  if ent:GetNW2String('MMDHLAsset','')~=id then
   for i in pairs(ent.MMDHLManual or {}) do ent:SetNW2String('MMDHLManual'..(i-1),'') end
   ent.MMDHLManual=nil ent:SetNW2Int('MMDHLManualRevision',0)
   mmdhl.ClearAssetState(ent,mmdhl.GetRig(ent))
  end
  local rig=options.rigManifest
  if not rig then local raw,err=native.PrepareCarrier(id,util.TableToJSON(options)) if not raw then return nil,err end rig=util.JSONToTable(raw) end
  if not mmdhl.RememberRig(rig) then return nil,L'persistence.error.carrier_outdated' end
  if rig.materialGma and not mmdhl.MountPackage(rig.materialGma) then return nil,L'carrier.error.mount_materials' end
  rig.gma=rig.gma or ('data/mmd_hotloader/rigs/'..rig.key..'/carrier.gma')
  local mounted=mmdhl.MountPackage(rig.gma) if not mounted then return nil,L'carrier.error.mount_carrier' end
  local settings=table.Copy(options) settings.backend='source' settings.presentationDriven=true settings.rigManifest=rig
  ent:SetNW2String('MMDHLAsset',id) ent:SetNW2String('MMDHLRig',rig.key) ent:SetNW2Int('MMDHLGeneration',(ent:GetNW2Int('MMDHLGeneration',0)+1))
  ent:SetNW2Bool('MMDHLNoDraw',ent:GetNoDraw() or ent:IsEffectActive(EF_NODRAW))
  mmdhl.InvalidateEntityList()
  ent:SetNW2Int('MMDHLNativeBodyCount',ent:GetPhysicsObjectCount())
  ent:SetNW2Int('MMDHLCollisionFlags',mmdhl.ValidCollisionFlags(options.collisionFlags) or mmdhl.CollideDefault)
  ent:SetNW2String('MMDHLSecondaryBackend',options.secondaryBackend or 'reference')
  ent.MMDOptions=table.Copy(options) ent.MMDPose={} ent.MMDManipulation={} ent.MMDMorphs={}
  ent.MMDHLBoundRig=rig
  if mmdhl.PublishRig then mmdhl.PublishRig(rig) end
  if not ent.MMDHLCopyHook then
   local previous=ent.PreEntityCopy
   ent.PreEntityCopy=function(e,...) if previous then previous(e,...) end save(e) end
   ent.MMDHLCopyHook=true
  end
  return rig
 end
 -- flags.replace: the physics editor swaps it in for an existing ragdoll and moves that one's creator, undo and cleanup.
 function mmdhl.SpawnNative(p,id,options,done,flags)
  options=mmdhl.WithSpawnDefaults(p,options)
  local raw,err=native.PrepareCarrier(id,util.TableToJSON(options)) if not raw then if done then done(nil,err) end return end local rig=util.JSONToTable(raw)
  if not mmdhl.RememberRig(rig) then if done then done(nil,L'persistence.error.carrier_outdated') end return end
  if rig.materialGma and not mmdhl.MountPackage(rig.materialGma) then if done then done(nil,L'carrier.error.mount_materials') end return end
  if not mmdhl.MountPackage(rig.gma) then if done then done(nil,L'carrier.error.mount_carrier') end return end
  if options.role and options.role~='ragdoll' then return mmdhl.SpawnActorNative(p,id,options,rig,done) end
  -- NULL near the networked-edict limit.
  local ent=ents.Create('prop_ragdoll') if not IsValid(ent) then if done then done(nil,L'server.error.native_ragdoll_failed') end return end
  ent:SetModel(rig.model) ent:SetPos(Vector(unpack(options.position or {0,0,0}))) ent:SetAngles(Angle(unpack(options.angles or {0,0,0}))) ent:Spawn()
  if ent:GetPhysicsObjectCount()~=18 then ent:Remove() if done then done(nil,L'carrier.error.physics_objects') end return end
  local attached,e=mmdhl.AttachNative(ent,id,options) if not attached then ent:Remove() if done then done(nil,e) end return end
  for i=0,17 do local body=ent:GetPhysicsObjectNum(i) body:EnableMotion(not options.frozen) if not options.frozen then body:Wake() end end
  -- Before the first duplicator snapshot, so dupes keep the chosen parts.
  if options.bodygroups then mmdhl.ApplyBodygroupState(ent,options.bodygroups) end
  if IsValid(p) and not (flags and flags.replace) then
   -- Sandbox counts the ragdoll toward the player's limit (and prop protection
   -- takes ownership) in this completion hook, as for its own spawns.
   ent:SetCreator(p) gamemode.Call('PlayerSpawnedRagdoll',p,ent:GetModel(),ent)
   undo.Create('mmdhl.undo.ragdoll') undo.AddEntity(ent) undo.SetPlayer(p) undo.Finish() p:AddCleanup('mmdhl',ent)
  end
  save(ent) if done then done(ent) end return ent
 end
 local function failure(ent,err)
  if ent.MMDStopped then return end ent.MMDStopped=err ErrorNoHalt('[Model Hotloader native] '..tostring(err)..'\n')
  file.CreateDir('mmd_hotloader/failures') file.Write('mmd_hotloader/failures/'..os.time()..'-'..ent:EntIndex()..'.json',util.TableToJSON({error=err,asset=mmdhl.GetAsset(ent),rig=mmdhl.GetRig(ent),diagnostics=mmdhl.GetDiagnostics(ent),engine=VERSIONSTR,map=game.GetMap()},true))
 end
 hook.Add('Tick','MMDHL.NativePose',function()
  for _,ent in ipairs(ents.FindByClass('prop_ragdoll')) do
   local h=ent:GetNW2Int('MMDHLInstance',0) if h==0 or ent.MMDStopped then continue end local rig=mmdhl.GetRig(ent) if not rig then continue end
   local scale=ent:GetFlexScale()
   local changed=false local weights=ent.MMDMorphs
   -- The rig is already resolved for this entity. Re-entering GetMorphWeight
   -- for every controller repeats the same networked rig lookup at tick rate.
   for i,morph in ipairs(rig.morphs) do
    local weight
    if morph.native>=0 then weight=ent:GetFlexWeight(morph.native)
    else morph.networkKey=morph.networkKey or ('MMDHLMorph'..morph.mmd) weight=ent:GetNW2Float(morph.networkKey,0) end
    weight=weight*scale if weights[i]~=weight then weights[i]=weight changed=true end
   end
   if changed then native.SetMorphs(h,util.TableToJSON(weights)) end
   -- Source simulates these bodies; the client reads their interpolated studio palette.
  end

 end)
 -- Persistence uses the shared Sandbox entry points in persistence.lua.
 hook.Add('OnPhysgunPickup','MMDHL.QualityHeld',function(_,ent) if mmdhl.IsMMD(ent) then ent:SetNW2Bool('MMDHLPhysgunHeld',true) end end)
 hook.Add('PhysgunDrop','MMDHL.QualityReleased',function(_,ent) if mmdhl.IsMMD(ent) then ent:SetNW2Bool('MMDHLPhysgunHeld',false) end end)
 return
end

net.Receive('mmdhl_collision_mesh',function()
 local ent=net.ReadEntity() local key=net.ReadString() local count=net.ReadUInt(16) local decoded=util.JSONToTable(util.Decompress(net.ReadData(count)) or '')
 if IsValid(ent) and key==ent:GetNW2String('MMDHLRig','') and istable(decoded) then ent.MMDHLActualCollision=decoded ent.MMDHLActualCollisionKey=key end
end)
-- A ragdoll rebound to another carrier asks again: its collision changed with the key.
function mmdhl.RequestCollisionMesh(ent)
 if not IsValid(ent) or (ent.MMDHLActualCollision and ent.MMDHLActualCollisionKey==ent:GetNW2String('MMDHLRig','')) or (ent.MMDHLMeshRequestAt or 0)>RealTime() then return end
 ent.MMDHLMeshRequestAt=RealTime()+2 net.Start('mmdhl_collision_mesh') net.WriteEntity(ent) net.SendToServer()
end
include('mmdhl/native_render.lua')
