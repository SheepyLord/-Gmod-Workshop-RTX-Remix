-- Optional provider: native limits remain unchanged for ordinary Source models.
AdvMat=AdvMat or {}
-- Labels are presentation only: rules and RTX profiles still use the real material path.
function AdvMat.MaterialDisplayName(material,target,slot)
 local path=AdvMat.NormalizeMaterial(material or '')
 if not mmdhl then return path end
 local rig
 if IsValid(target) then
  rig=mmdhl.GetRig and mmdhl.GetRig(target)
  if not rig and mmdhl.GetRigForModel then rig=mmdhl.GetRigForModel(target:GetModel()) end
 elseif isstring(target) and mmdhl.GetRigForModel then rig=mmdhl.GetRigForModel(target) end
 local list=rig and rig.materials
 local part=list and slot~=nil and list[slot+1]
 if not part or AdvMat.NormalizeMaterial(part.path or '')~=path then
  part=nil
  for _,candidate in ipairs(list or {}) do
   if AdvMat.NormalizeMaterial(candidate.path or '')==path then part=candidate break end
  end
 end
 if not part then
  local asset,index=path:match('^mmdhl_prop_r%d+_(%x+)_(%d+)[gm]$')
  local entry=asset and mmdhl.props and mmdhl.props.RenderCache and mmdhl.props.RenderCache[asset]
  part=entry and entry.info and entry.info.materials and entry.info.materials[tonumber(index)]
 end
 return part and isstring(part.name) and part.name~='' and part.name or path
end
function AdvMat.GetMaterialLimit(target)
 if not mmdhl or not mmdhl.GetRigForModel then return AdvMat.MAX_SUBMATERIALS end
 if isnumber(target) then target=Entity(target) end
 local rig
 if IsValid(target) then rig=mmdhl.GetRig(target) or mmdhl.GetRigForModel(target:GetModel())
 elseif isstring(target) then
  rig=mmdhl.GetRigForModel(target)
  if not rig then
   local asset=mmdhl.GetMaterialAsset and mmdhl.GetMaterialAsset(target)
   if asset and #asset==64 then
    local manifest=util.JSONToTable(file.Read('mmd_hotloader/assets/'..asset..'/manifest.json','DATA') or '')
    if manifest and manifest.materials then return #manifest.materials end
   end
  end
 end
 return rig and rig.materials and #rig.materials or AdvMat.MAX_SUBMATERIALS
end
function AdvMat.AttachMMDPreview(ent)
 return CLIENT and mmdhl and mmdhl.AttachEditorPreview and mmdhl.AttachEditorPreview(ent)
end
-- The Hotloader mounts a model's materials when it first draws the model; rule
-- materials are built on join, often earlier. A texture Source looks up before
-- its package is mounted stays missing for the session, for the model's own
-- materials too (wrong look, "native_render.lua:60" errors). Mount it first.
function AdvMat.PrepareMMDMaterial(path)
 local short=isstring(path) and path:match('^mmd/([a-f0-9]+)/[^/]+$')
 if not short or #short~=16 then return true,false end
 local ready=CLIENT and mmdhl and mmdhl.MountMaterialAsset and mmdhl.MountMaterialAsset(path)
 return ready==true,true
end
