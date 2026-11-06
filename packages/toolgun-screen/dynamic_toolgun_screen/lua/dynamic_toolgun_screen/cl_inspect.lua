--[[
	Dynamic Toolgun Screen - inspect
	Hold a key and the tool gun is raised so its screen faces you up close, like checking a watch.

	The screen quad is rigidly skinned to one bone of the view model. Every frame we take that bone's
	matrix (from the last draw), find where the screen sits relative to the model's root, and move the
	root so the screen ends up centred in front of the eyes. Animations keep playing around it.
]]

local DTS = DTScreen

DTS.AddSetting( "inspect_key", 0, "Hold this key or mouse button to bring the tool gun screen up close (a KEY_ or MOUSE_ number, 0 = none). +dts_inspect works too.", "int" )
DTS.AddSetting( "inspect_size", 0.42, "Size of the screen while inspecting (0.2 - 0.7).", "float" )
DTS.AddSetting( "inspect_on_top", 1, "While inspecting, draw the screen in front of the paper note glued to the tool gun (0 = the note covers its top right corner, as on the model).", "bool" )

--[[
	Screen corners in the space of the bone they are skinned to: top left, top right, bottom left
	(texture u to the right, v down).
	They are measured from the mesh of the model that is actually loaded: addons replace the tool gun
	model under the same file name (Advanced Toolgun's has the screen 0.7 units further right). The
	values of the stock model (read from its VVD + bone poseToBone) are only used if that fails.
]]
local STOCK = {
	[ "models/weapons/c_toolgun.mdl" ] = {
		bone = "Hand",
		tl = Vector( 1.1819, 5.9339, 4.2806 ),
		tr = Vector( -1.0601, 5.9339, 4.2806 ),
		bl = Vector( 1.1819, 4.3542, 2.6897 ),
	},
}

-- the main screen only: replacement models can add more screens (screen2...)
local function IsScreenMaterial( mat )
	return string.EndsWith( string.lower( string.gsub( mat, "\\", "/" ) ), "v_toolgun/screen" )
end

local measured = {}

local function ScreenInfo( model )

	model = string.lower( model or "" )
	if ( measured[ model ] != nil ) then return measured[ model ] or nil end
	measured[ model ] = STOCK[ model ] or false

	local ok, meshes, bones = pcall( util.GetModelMeshes, model )
	if ( !ok or !istable( meshes ) or !istable( bones ) ) then return measured[ model ] or nil end

	for _, m in ipairs( meshes ) do
		if ( isstring( m.material ) and IsScreenMaterial( m.material ) and istable( m.verticies ) ) then

			local tl, tr, bl, bone
			for _, v in ipairs( m.verticies ) do
				local w = v.weights and v.weights[ 1 ]
				if ( w and v.u and v.v ) then
					bone = bone or w.bone
					if ( v.u < 0.5 and v.v < 0.5 ) then tl = v.pos end
					if ( v.u > 0.5 and v.v < 0.5 ) then tr = v.pos end
					if ( v.u < 0.5 and v.v > 0.5 ) then bl = v.pos end
				end
			end

			local pose = bone and bones[ bone ] and bones[ bone ].matrix
			if ( tl and tr and bl and pose ) then
				measured[ model ] = { boneId = bone, tl = pose * tl, tr = pose * tr, bl = pose * bl }
				break
			end

		end
	end

	return measured[ model ] or nil

end

-- World positions of the screen's top left, top right and bottom left corners, or nil.
function DTS.ScreenCorners( vm )

	local info = ScreenInfo( vm:GetModel() )
	if ( !info ) then return nil end

	local bone = info.boneId or vm:LookupBone( info.bone )
	if ( !bone ) then return nil end

	local m = vm:GetBoneMatrix( bone )
	if ( !m ) then return nil end

	return m * info.tl, m * info.tr, m * info.bl

end

-- World position and angle of the screen (forward = into the screen, up = top edge), or nil.
function DTS.ScreenFrame( vm )

	local tl, tr, bl = DTS.ScreenCorners( vm )
	if ( !tl ) then return nil end

	local right, down = tr - tl, bl - tl
	local center = tl + right * 0.5 + down * 0.5

	local fwd = right:Cross( down )
	fwd:Normalize()
	local up = -down
	up:Normalize()

	return center, fwd:AngleEx( up ), right:Length()

end

--[[---------------------------------------------------------
	Input: a key picked in the menu, +dts_inspect, or dts_inspect_toggle
-----------------------------------------------------------]]

concommand.Add( "+dts_inspect", function() DTS.InspectHeld = true end, nil, "Hold to look at the tool gun screen up close." )
concommand.Add( "-dts_inspect", function() DTS.InspectHeld = false end )
concommand.Add( "dts_inspect_toggle", function() DTS.InspectToggled = !DTS.InspectToggled end, nil, "Raise or lower the tool gun screen." )

local frac = 0

local function HoldingToolgun()
	local ply = LocalPlayer()
	local wep = IsValid( ply ) and ply:GetActiveWeapon()
	return IsValid( wep ) and wep:GetClass() == "gmod_tool"
end

hook.Add( "Think", "DTScreen_Inspect", function()

	local holding = HoldingToolgun()
	if ( !holding ) then DTS.InspectToggled = false end

	-- the binder in the panel also accepts mouse buttons, which input.IsKeyDown does not see
	local key = DTS.GetInt( "inspect_key" )
	local keyDown = key > 0 and input.IsButtonDown( key ) and !vgui.CursorVisible() and !gui.IsGameUIVisible()

	DTS.Inspecting = holding and ( DTS.InspectHeld or DTS.InspectToggled or keyDown ) or false
	frac = math.Approach( frac, DTS.Inspecting and 1 or 0, RealFrameTime() * 5 )

end )

function DTS.InspectFraction()
	return frac
end

-- Where the screen sits relative to the view model's root, measured while the model is drawn
-- (bones and root are guaranteed to match then). Reading the bones later could mix a fresh root with
-- stale bones whenever the model skipped a draw, which could push it out of view for good.
local relPos, relAng, screenH

hook.Add( "CalcViewModelView", "DTScreen_Inspect", function( wep, vm, oldPos, oldAng, pos, ang )

	if ( frac <= 0 or !relPos or !IsValid( wep ) or wep:GetClass() != "gmod_tool" ) then return end

	-- where the screen would be with this frame's root, and the root seen from the screen
	local cPos, cAng = LocalToWorld( relPos, relAng, pos, ang )
	local rPos, rAng = WorldToLocal( pos, ang, cPos, cAng )

	-- target: centred in front of the eyes and facing them, its size set by inspect_size (with the
	-- view model's own field of view, the default 0.42 fills a little over half the view height)
	local fov = wep.ViewModelFOV or 62
	local size = math.Clamp( DTS.GetFloat( "inspect_size" ), 0.2, 0.7 )
	local dist = ( screenH or 2.25 ) / ( size * 2 * math.tan( math.rad( fov * 0.5 ) ) )
	local tAng = Angle( oldAng.p, oldAng.y, 0 )
	local tPos = oldPos + tAng:Forward() * dist

	local nPos, nAng = LocalToWorld( rPos, rAng, tPos, tAng )

	local e = frac * frac * ( 3 - 2 * frac )
	return LerpVector( e, pos, nPos ), LerpAngle( e, ang, nAng )

end )

--[[
	The model's paper note sticks out in front of the screen's top right corner, so it covers that corner
	once the screen faces you. By default (inspect_on_top) the screen is drawn once more on top of the model
	while inspecting, so nothing covers it; turned off, the note stays in front, as the model is built.
]]
local matScreen = Material( "models/weapons/v_toolgun/screen" )
local matOverlay = CreateMaterial( "DTScreen_InspectOverlay", "UnlitGeneric", {
	[ "$basetexture" ] = "models/weapons/v_toolgun/screen_bg",
	[ "$ignorez" ] = 1,
	[ "$vertexcolor" ] = 1,
	[ "$vertexalpha" ] = 1
} )

hook.Add( "PostDrawViewModel", "DTScreen_Inspect", function( vm, ply, wep )

	if ( !IsValid( wep ) or wep:GetClass() != "gmod_tool" ) then return end

	-- nothing to measure until the screen is raised (the first measurement reads the model's mesh)
	if ( !DTS.Inspecting and frac <= 0 ) then relPos = nil return end

	local tl, tr, bl = DTS.ScreenCorners( vm )
	if ( !tl ) then return end

	local center, screenAng = DTS.ScreenFrame( vm )
	relPos, relAng = WorldToLocal( center, screenAng, vm:GetPos(), vm:GetAngles() )
	screenH = ( bl - tl ):Length() -- the stock screen is 2.25 units tall; other models may differ

	if ( frac < 0.5 or !DTS.GetBool( "inspect_on_top" ) ) then return end

	local tex = matScreen:GetTexture( "$basetexture" )
	if ( tex and !tex:IsError() ) then matOverlay:SetTexture( "$basetexture", tex ) end

	render.SetMaterial( matOverlay )
	render.DrawQuad( tl, tr, tr + bl - tl, bl, Color( 255, 255, 255, 255 * math.Clamp( ( frac - 0.5 ) * 2, 0, 1 ) ) )

end )
