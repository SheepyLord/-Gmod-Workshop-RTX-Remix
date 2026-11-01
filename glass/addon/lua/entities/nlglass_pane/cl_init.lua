-- MIT. The global client renderer owns cached pane/crack meshes, not the placeholder model.
include("shared.lua")
function ENT:Draw() end
function ENT:DrawTranslucent() end
