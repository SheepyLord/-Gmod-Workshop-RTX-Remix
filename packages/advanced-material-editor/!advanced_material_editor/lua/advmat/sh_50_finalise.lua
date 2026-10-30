--[[---------------------------------------------------------------------------
	Advanced Material Editor - database finalisation

	Runs after every shader definition and extension has been loaded, and fixes
	up value types that are better decided in one place than maintained by hand
	across two files, one of which is generated.
-----------------------------------------------------------------------------]]

AdvMat = AdvMat or {}

---------------------------------------------------------------------------
-- Texture transforms get their own editor
---------------------------------------------------------------------------
-- The core database types these as text and the generated set types them as
-- matrix. Either way the user ends up looking at a raw
-- "center .5 .5 scale 1 1 rotate 0 translate 0 0" string, which is a poor way
-- to nudge a texture. Retyping them here routes them to the slider editor in
-- cl_65_rows.lua instead.
--
-- The pattern allows a trailing digit so the second blend layer's transforms
-- ( $bumptransform2 and friends ) are caught as well.
local n = 0

for _, list in pairs( AdvMat.Shaders ) do
	for _, def in ipairs( list ) do
		if string.match( def.name, "transform%d*$" ) then
			def.type = "transform"
			n = n + 1
		end
	end
end
