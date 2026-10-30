-- Optional provider: native limits remain unchanged for ordinary Source models.
AdvMat=AdvMat or {}
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
