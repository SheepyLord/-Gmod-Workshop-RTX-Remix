--[[
	Dynamic Toolgun Screen - rendering

	The sandbox tool gun draws its screen in SWEP:RenderScreen (cl_viewscreen.lua) into the render
	target "GModToolgunScreen" and points the screen material at it. We wrap that function: when the
	dynamic screen is on we draw our own content into the same target (or a 512 one), otherwise the
	original function runs untouched.
]]

local DTS = DTScreen
local D = DTS.Draw

local colWhite, colBlack = Color( 255, 255, 255 ), Color( 0, 0, 0 )

local matScreen = Material( "models/weapons/v_toolgun/screen" )
local matArt = Material( "models/weapons/v_toolgun/screen_bg" )
-- screen_bg with its baked-in text removed (tools/make_original_bg.py): photo, status band, green panel, menu bar
local matOriginal = Material( "dynamic_toolgun_screen/screen_original.png", "smooth ignorez" )
local matGradDown = Material( "gui/gradient_down" )
local matGradUp = Material( "gui/gradient_up" )
local matGradRight = Material( "gui/gradient" )

--[[---------------------------------------------------------
	Render targets and materials
-----------------------------------------------------------]]

local targets = {}

function DTS.GetScreenRT()

	local res = DTS.GetInt( "resolution" ) >= 512 and 512 or 256
	local rt = targets[ res ]
	if ( !rt ) then
		-- 256 is the sandbox target itself, so turning the addon off needs no cleanup
		rt = GetRenderTarget( res == 256 and "GModToolgunScreen" or "DTScreen_Screen512", res, res )
		targets[ res ] = rt
	end
	return rt

end

-- Material that shows whatever the screen currently displays (HUD mirror, menu preview).
local matView = CreateMaterial( "DTScreen_View", "UnlitGeneric", {
	[ "$basetexture" ] = "models/weapons/v_toolgun/screen_bg",
	[ "$vertexcolor" ] = 1,
	[ "$vertexalpha" ] = 1,
	[ "$ignorez" ] = 1
} )

function DTS.DrawScreenTexture( x, y, w, h, alpha )

	local tex = matScreen:GetTexture( "$basetexture" )
	if ( tex and !tex:IsError() ) then matView:SetTexture( "$basetexture", tex ) end

	surface.SetMaterial( matView )
	surface.SetDrawColor( 255, 255, 255, alpha or 255 )
	surface.DrawTexturedRect( x, y, w, h )

end

--[[---------------------------------------------------------
	Live camera background
	Rendered after the frame (PostRender, like the duplicator icon) at dts_cam_fps, only while a
	screen that uses it is visible.
-----------------------------------------------------------]]

local camRT, camMat
local lastCamera = 0

local function CameraTarget()

	if ( !camRT ) then
		camRT = GetRenderTarget( "DTScreen_Camera", 256, 256 )
		camMat = CreateMaterial( "DTScreen_CameraView", "UnlitGeneric", { [ "$basetexture" ] = "DTScreen_Camera", [ "$ignorez" ] = 1, [ "$vertexcolor" ] = 1 } )
		camMat:SetTexture( "$basetexture", camRT )
	end
	return camRT, camMat

end

function DTS.CameraAllowed()
	local cv = GetConVar( "dts_sv_allow_camera" )
	return !cv or cv:GetBool()
end

local function RenderCamera()

	if ( RealTime() - ( DTS.CameraWanted or -10 ) > 0.3 ) then return end
	if ( !DTS.CameraAllowed() or DTS.InCameraRender ) then return end

	local fps = math.Clamp( DTS.GetInt( "cam_fps" ), 1, 60 )
	if ( RealTime() - lastCamera < 1 / fps ) then return end
	lastCamera = RealTime()

	local ply = LocalPlayer()
	if ( !IsValid( ply ) ) then return end

	local rt = CameraTarget()
	local ang = ply:EyeAngles()
	local fov = math.Clamp( DTS.GetFloat( "cam_fov" ), 2, 120 )

	if ( DTS.CameraMode == "rear" ) then
		ang = Angle( ang.p * 0.5, ang.y + 180, 0 )
		fov = 85
	end

	DTS.InCameraRender = true
	render.PushRenderTarget( rt )
		render.Clear( 0, 0, 0, 255, true, true )
		render.RenderView( {
			origin = ply:EyePos(), angles = ang, fov = fov, aspect = 1,
			x = 0, y = 0, w = rt:Width(), h = rt:Height(),
			drawviewmodel = false, drawhud = false, drawmonitors = false, dopostprocess = false, bloomtone = false
		} )
	render.PopRenderTarget()
	DTS.InCameraRender = false

end

--[[---------------------------------------------------------
	Background
-----------------------------------------------------------]]

local imageMats = {}

local function ImageMaterial( path )

	path = string.Trim( path or "" )
	if ( path == "" ) then return nil end

	local mat = imageMats[ path ]
	if ( mat == nil ) then
		local ext = string.lower( string.GetExtensionFromFilename( path ) or "" )
		if ( ext == "png" or ext == "jpg" or ext == "jpeg" ) then
			mat = Material( path, "smooth ignorez" )
		else
			mat = Material( path )
		end
		if ( mat:IsError() ) then mat = false end
		imageMats[ path ] = mat
	end

	return mat or nil

end

function DTS.ResolveBackground( layout )

	local bg = DTS.GetString( "background" )
	if ( bg == "" or bg == "auto" ) then bg = layout.Background or "gradient" end
	if ( ( bg == "camera" or bg == "rear" ) and !DTS.CameraAllowed() ) then bg = "art" end
	if ( bg == "original" and matOriginal:IsError() ) then bg = "art" end
	return bg

end

function DTS.DrawBackground( layout, T )

	local bg = DTS.ResolveBackground( layout )

	if ( bg == "original" ) then

		-- the whole original screen without its text; themes can leave their panels clear on it (Original colours)
		D.Rect( 0, 0, 256, 256, colBlack )
		D.Material( matOriginal, 0, 0, 256, 256, colWhite )
		D.Rect( 0, 0, 256, 256, T.tint )

	elseif ( bg == "art" ) then

		-- the blurred photo in the middle of the original texture is the only part without baked-in text
		D.Rect( 0, 0, 256, 256, colBlack )
		D.Material( matArt, 0, 0, 256, 256, colWhite, 0, 60 / 256, 1, 146 / 256 )
		D.Rect( 0, 0, 256, 256, T.tint )

	elseif ( bg == "camera" or bg == "rear" ) then

		DTS.CameraWanted = RealTime()
		DTS.CameraMode = bg
		local _, mat = CameraTarget()
		D.Rect( 0, 0, 256, 256, colBlack )
		if ( bg == "rear" ) then
			D.Material( mat, 0, 0, 256, 256, colWhite, 1, 0, 0, 1 ) -- mirrored like a real mirror
		else
			D.Material( mat, 0, 0, 256, 256, colWhite )
		end
		D.Rect( 0, 0, 256, 256, T.tint )

	elseif ( bg == "image" ) then

		local mat = ImageMaterial( DTS.GetString( "bg_image" ) )
		if ( mat ) then
			D.Rect( 0, 0, 256, 256, colBlack )
			D.Material( mat, 0, 0, 256, 256, colWhite )
			D.Rect( 0, 0, 256, 256, T.tint )
		else
			D.VGradient( 0, 0, 256, 256, T.bg1, T.bg2 )
		end

	elseif ( bg == "black" ) then

		D.Rect( 0, 0, 256, 256, colBlack )

	elseif ( bg == "term" ) then

		D.Rect( 0, 0, 256, 256, T.term_bg )

	else

		D.VGradient( 0, 0, 256, 256, T.bg1, T.bg2 )

	end

	local dim = math.Clamp( DTS.GetFloat( "bg_dim" ), 0, 0.9 )
	if ( dim > 0 ) then D.Rect( 0, 0, 256, 256, colBlack, dim * 255 ) end

end

--[[---------------------------------------------------------
	Effects drawn over the layout
-----------------------------------------------------------]]

function DTS.DrawEffects( T, now )

	if ( DTS.GetBool( "fire_flash" ) ) then
		local f = 1 - ( now - ( DTS.LastFire or -10 ) ) / 0.3
		if ( f > 0 ) then D.Rect( 0, 0, 256, 256, colWhite, f * 80 ) end
	end

	local lines = math.Clamp( DTS.GetFloat( "scanlines" ), 0, 1 )
	if ( lines > 0 ) then
		for y = 0, 255, 3 do D.Rect( 0, y, 256, 1, colBlack, lines * 110 ) end
	end

	if ( DTS.GetBool( "vignette" ) ) then
		local edge = Color( 0, 0, 0, 70 )
		D.Material( matGradDown, 0, 0, 256, 18, edge )
		D.Material( matGradUp, 0, 238, 256, 18, edge )
		D.Material( matGradRight, 0, 0, 14, 256, edge )
		D.Material( matGradRight, 242, 0, 14, 256, edge, 1, 0, 0, 1 )
	end

	local backlight = math.Clamp( DTS.GetFloat( "backlight" ), 0.2, 1 )
	if ( backlight < 1 ) then D.Rect( 0, 0, 256, 256, colBlack, ( 1 - backlight ) * 255 ) end

end

-- Short boot sequence when the tool gun is taken out.
function DTS.DrawBoot( T, now )

	if ( !DTS.GetBool( "boot_anim" ) ) then return end

	local t = now - ( DTS.BootStart or -10 )
	if ( t < 0 or t > 1 ) then return end

	local cover = t < 0.62 and 1 or ( 1 - ( t - 0.62 ) / 0.38 )
	D.Rect( 0, 0, 256, 256, colBlack, 255 * cover )

	local logo = math.Clamp( ( t - 0.06 ) / 0.22, 0, 1 ) * cover
	if ( logo <= 0 ) then return end

	local grow = 0.65 + 0.35 * math.Clamp( ( t - 0.06 ) / 0.3, 0, 1 )
	D.Flag( 128, 104, 64 * grow, t * 2, logo )

	D.Text( "Garry's Mod", D.Font( DTS.FontFace( "ui" ), 20, 800 ), 128, 158, Color( 255, 255, 255, 255 * logo ), 1, 1 )

	local p = math.Clamp( t / 0.6, 0, 1 )
	D.Rect( 68, 184, 120, 4, colWhite, 50 * logo )
	D.Rect( 68, 184, 120 * p, 4, colWhite, 230 * logo )

end

--[[---------------------------------------------------------
	Refresh: rebuild the context and evaluate the templates at dts_refresh Hz
-----------------------------------------------------------]]

function DTS.Refresh( weapon, force )

	local now = RealTime()
	local hz = math.Clamp( DTS.GetInt( "refresh" ), 1, 60 )

	if ( !force and !DTS.Dirty and DTS.Ctx and now - ( DTS.LastRefresh or 0 ) < 1 / hz ) then return end

	DTS.LastRefresh = now
	DTS.Dirty = false

	local ctx = DTS.BuildContext( weapon )
	DTS.Ctx = ctx
	DTS.ActiveTheme = DTS.BuildTheme()

	local layout = DTS.GetLayout()
	local slots = {}
	for _, slot in ipairs( layout.Slots ) do
		slots[ slot.id ] = DTS.EvalTemplate( DTS.GetString( slot.setting ), ctx )
	end
	DTS.SlotRuns = slots

end

--[[---------------------------------------------------------
	Drawing the screen
-----------------------------------------------------------]]

local function DrawAll( weapon )

	-- inside the error handling too: it runs other addons' DTScreen_BuildContext hooks and their themes
	DTS.Refresh( weapon )

	local now = RealTime()
	local layout = DTS.GetLayout()
	local T = DTS.ActiveTheme
	local ctx = DTS.Ctx

	DTS.DrawBackground( layout, T )

	if ( hook.Run( "DTScreen_PreDraw", D, ctx, T ) != true ) then
		layout:Draw( D, ctx, T, DTS.SlotRuns or {} )
	end

	hook.Run( "DTScreen_PostDraw", D, ctx, T )

	DTS.DrawEffects( T, now )
	DTS.DrawBoot( T, now )

end

-- Breaks text into lines that fit width (design units). Breaks at spaces, or anywhere for scripts without them (CJK).
local function Wrap( text, font, width )

	local lines, line, lineW = {}, "", 0
	local spaceW = D.TextSize( " ", font )

	local function Push()
		if ( line != "" ) then lines[ #lines + 1 ] = line end
		line, lineW = "", 0
	end

	for word, space in string.gmatch( text, "([^ ]+)( ?)" ) do
		local w = D.TextSize( word, font )
		if ( lineW > 0 and lineW + spaceW + w > width ) then Push() end
		if ( w > width ) then
			-- a "word" wider than the line: break between characters
			for _, c in utf8.codes( word ) do
				local ch = utf8.char( c )
				local cw = D.TextSize( ch, font )
				if ( lineW + cw > width ) then Push() end
				line, lineW = line .. ch, lineW + cw
			end
		else
			line = lineW > 0 and ( line .. " " .. word ) or word
			lineW = lineW > 0 and ( lineW + spaceW + w ) or w
		end
	end
	Push()

	return lines

end

local function DrawError( err )

	D.Alpha = 1
	local ui = DTS.FontFace( "ui" )

	D.Rect( 0, 0, 256, 256, Color( 30, 0, 0 ) )
	D.Rect( 0, 0, 256, 26, Color( 190, 20, 20 ) )
	D.Text( DTS.L( "error.title" ), D.Font( ui, 14, 800 ), 6, 13, colWhite, 0, 1 )

	-- the Lua error itself stays as the engine wrote it
	local msg = string.match( tostring( err ), "^[^\n]*" ) or "error"
	msg = string.gsub( msg, "^.-lua/", "" )
	local small = D.Font( "Tahoma", 12, 500 )
	local y = 34
	for _, l in ipairs( Wrap( msg, small, 244 ) ) do
		D.Text( l, small, 6, y, colWhite )
		y = y + 15
		if ( y > 170 ) then break end
	end

	local hintFont = D.Font( ui, 13, 500 )
	local hint = Wrap( DTS.L( "error.hint" ), hintFont, 244 )
	y = 252 - #hint * 17
	for _, l in ipairs( hint ) do
		D.Text( l, hintFont, 6, y, Color( 255, 180, 180 ) )
		y = y + 17
	end

end

-- Alpha is irrelevant for the tool gun model but the HUD mirror draws with it: force it opaque.
local function FixAlpha( size )

	render.OverrideColorWriteEnable( true, false )
	render.OverrideAlphaWriteEnable( true, true )
	surface.SetDrawColor( 0, 0, 0, 255 )
	surface.DrawRect( 0, 0, size, size )
	render.OverrideAlphaWriteEnable( false )
	render.OverrideColorWriteEnable( false )

end

local errorCount = 0
local lastDraw = 0

function DTS.RenderScreen( weapon )

	local rt = DTS.GetScreenRT()
	matScreen:SetTexture( "$basetexture", rt )
	DTS.LastRenderFrame = FrameNumber()

	-- The screen only changes so fast: redraw at dts_fps instead of every frame.
	local now = RealTime()
	local fps = DTS.GetInt( "fps" )
	if ( fps > 0 and now - lastDraw < 1 / fps - 0.0005 and DTS.LastDrawnRT == rt ) then return end
	lastDraw = now
	DTS.LastDrawnRT = rt

	local t0 = SysTime()
	local size = rt:Width()

	render.PushRenderTarget( rt )
	cam.Start2D()

		-- The target shares the depth buffer, which still holds the scene at this point of the frame:
		-- without this, materials lacking $ignorez (png and jpg images) fail the depth test and vanish.
		cam.IgnoreZ( true )

		D.Begin( size )

		local ok, err = xpcall( DrawAll, debug.traceback, weapon )
		D.Unclip()
		D.Alpha = 1

		if ( !ok ) then
			errorCount = errorCount + 1
			DTS.LastError = err
			DTS.ErrorOnce( "render." .. tostring( err ), err )
			pcall( DrawError, err )
			if ( errorCount > 120 ) then
				DTS.Broken = true -- back to the original screen until a setting changes
				print( "[Dynamic Toolgun Screen] Too many errors, showing the original screen. Change a setting or run dts_reset to try again." )
			end
		else
			errorCount = 0
		end

		FixAlpha( size )
		cam.IgnoreZ( false )

	cam.End2D()
	render.PopRenderTarget()

	DTS.RenderMs = Lerp( 0.05, DTS.RenderMs or 0, ( SysTime() - t0 ) * 1000 )
	DTS.LastRenderTime = now

end

--[[---------------------------------------------------------
	The SWEP:RenderScreen wrapper
-----------------------------------------------------------]]

DTS.Wrappers = DTS.Wrappers or setmetatable( {}, { __mode = "k" } )

function DTS.ShouldRender( weapon )

	if ( !DTS.GetBool( "enabled" ) or DTS.Broken ) then return false end

	local tool = IsValid( weapon ) and weapon.GetToolObject and weapon:GetToolObject()
	if ( tool and tool.DrawToolScreen and DTS.GetBool( "respect_toolscreens" ) ) then return false end

	-- another addon's broken hook must not break the tool gun's screen every frame
	local ok, res = pcall( hook.Run, "DTScreen_ShouldDraw", weapon, tool )
	if ( !ok ) then DTS.ErrorOnce( "hook.DTScreen_ShouldDraw", res ) elseif ( res == false ) then return false end

	return true

end

local inFallback = false

local function Fallback( weapon )

	local orig = DTS.OriginalRenderScreen
	if ( !orig or DTS.Wrappers[ orig ] or inFallback ) then return end

	inFallback = true
	local ok, err = pcall( orig, weapon )
	inFallback = false

	if ( !ok ) then DTS.ErrorOnce( "fallback", err ) end

end

local function RenderScreenWrapper( self )

	if ( DTS.ShouldRender( self ) ) then
		DTS.UsingOriginal = false
		DTS.RenderScreen( self )
	else
		DTS.UsingOriginal = true
		Fallback( self )
	end

end

DTS.Wrappers[ RenderScreenWrapper ] = true
DTS.RenderScreenWrapper = RenderScreenWrapper

--[[
	Install the wrapper on the stored gmod_tool table (new tool guns) and on existing ones.
	We only take over from the sandbox original (or an older copy of ourselves after a Lua refresh);
	if another addon replaced the function after us, we report it instead of fighting over it,
	unless `force` is set (the "Take over" button in the menu).
]]
function DTS.Patch( force )

	local stored = weapons.GetStored( "gmod_tool" )
	if ( !stored ) then return false end

	local cur = stored.RenderScreen

	if ( cur != RenderScreenWrapper ) then

		if ( !DTS.Wrappers[ cur ] ) then
			local info = isfunction( cur ) and debug.getinfo( cur, "S" )
			local src = info and info.short_src or "?"

			if ( force or !DTS.OriginalRenderScreen or string.find( src, "cl_viewscreen", 1, true ) ) then
				DTS.OriginalRenderScreen = cur
			else
				DTS.Conflict = src
				return false
			end
		end

		stored.RenderScreen = RenderScreenWrapper

	end

	for _, wep in ipairs( ents.FindByClass( "gmod_tool" ) ) do
		local fn = wep.RenderScreen
		if ( fn != RenderScreenWrapper and ( force or DTS.Wrappers[ fn ] or fn == DTS.OriginalRenderScreen ) ) then
			wep.RenderScreen = RenderScreenWrapper
		end
	end

	DTS.Conflict = nil
	DTS.Patched = true
	return true

end

hook.Add( "InitPostEntity", "DTScreen_Patch", function() DTS.Patch() end )

hook.Add( "OnEntityCreated", "DTScreen_Patch", function( ent )
	if ( ent:GetClass() != "gmod_tool" ) then return end
	timer.Simple( 0, function() if ( IsValid( ent ) ) then DTS.Patch() end end )
end )

-- Cheap watchdog: re-applies the wrapper if the sandbox tool gun gets reloaded (Lua refresh).
timer.Create( "DTScreen_Patch", 2, 0, function() DTS.Patch() end )

DTS.Patch()

--[[---------------------------------------------------------
	After the frame: live camera, and the menu preview when the tool gun isn't drawing the screen
-----------------------------------------------------------]]

hook.Add( "PostRender", "DTScreen_PostRender", function()

	RenderCamera()

	if ( RealTime() - ( DTS.PreviewWanted or -10 ) < 0.3 and DTS.LastRenderFrame != FrameNumber() and !DTS.Broken ) then
		local ply = LocalPlayer()
		local wep = IsValid( ply ) and ply:GetActiveWeapon()
		if ( !IsValid( wep ) or wep:GetClass() != "gmod_tool" or !DTS.UsingOriginal ) then
			if ( DTS.GetBool( "enabled" ) ) then DTS.RenderScreen( IsValid( wep ) and wep:GetClass() == "gmod_tool" and wep or nil ) end
		end
	end

end )
