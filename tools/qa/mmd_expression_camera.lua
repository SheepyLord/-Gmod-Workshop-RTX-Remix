-- R10-H client camera for a server-probed NPC. Set R10MMDTarget to its entity index.
hook.Add('CalcView','R10MMDQA.Camera',function()
 local ent=Entity(R10MMDTarget or 0) if not IsValid(ent) then return end
 local at=ent:GetAttachment(ent:LookupAttachment('eyes') or 0)
 local head=at and at.Pos
 if not head then local bone=ent:LookupBone('ValveBiped.Bip01_Head1') head=bone and ent:GetBonePosition(bone) end
 if not head then return end
 local origin=head+ent:GetForward()*25
 return {origin=origin,angles=(head-origin):Angle(),fov=32,drawviewer=true}
end)
hook.Add('HUDShouldDraw','R10MMDQA.Camera',function() if R10MMDTarget then return false end end)
hook.Add('PreDrawViewModel','R10MMDQA.Camera',function() if R10MMDTarget then return true end end)
gui.HideGameUI() -- the external driver hides the console; Lua cannot run that command
print('R10_QA_CAMERA')
