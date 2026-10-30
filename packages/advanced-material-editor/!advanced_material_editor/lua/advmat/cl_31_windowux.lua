--[[---------------------------------------------------------------------------
	Advanced Material Editor - shared window behaviour

	Derma's MakePopup is intentionally greedy: it gives a window the cursor and
	keyboard focus so controls work, but that also prevents the player from using
	the normal game view.  This module keeps those two jobs separate.  With
	"player controls" enabled, the UI keeps its mouse until the user holds right
	mouse in uncovered screen space.  During that hold the screen clicker is
	released, so Source performs its own native mouse-look; releasing the button
	returns the cursor to exactly where it was.

	The module also owns the uninteresting but easy-to-get-wrong parts of desktop
	window behaviour: screen clamping, geometry cookies, child-window placement,
	and visible drag/resize affordances.  It contains no material-editor logic and
	can therefore be shared by the vanilla, RTX and texture editors.
-----------------------------------------------------------------------------]]

AdvMat = AdvMat or {}
AdvMat.WindowUX = AdvMat.WindowUX or {}

local W = AdvMat.WindowUX

local CVAR = "advmateditor_playercontrols"
local COOKIE_PREFIX = "advmat_window_"
local SCREEN_MARGIN = 12
-- Leave enough of the target around the inspector to remain useful at common
-- 1080p/1440p HUD scales, including a little room for the toolgun/crosshair.
local TARGET_GAP = 152
local CHILD_GAP = 18

-- Weak keys are important on hot reload.  A panel removed without running a
-- friendly close path must not be kept alive by this convenience registry.
W.Frames = W.Frames or setmetatable( {}, { __mode = "k" } )
W.RootStates = W.RootStates or setmetatable( {}, { __mode = "k" } )
W.ActiveRoot = W.ActiveRoot or nil
W.LookRoot = W.LookRoot or nil
W.RightWasDown = W.RightWasDown or false
-- The world-look bridge temporarily takes the global screen clicker away from
-- Derma.  Remember that we touched that global switch until the last AdvMat
-- root is gone, so a released look can never leave gameplay input captured.
W.WorldLookLease = W.WorldLookLease or false
W.PendingWorldRelease = W.PendingWorldRelease or false
W.SuppressRightUntilRelease = W.SuppressRightUntilRelease or false
W.InputEpoch = W.InputEpoch or 0
W.ReleaseAfterEpoch = W.ReleaseAfterEpoch or 0
W.CleaningFrames = W.CleaningFrames or setmetatable( {}, { __mode = "k" } )

-- Forward declaration: child ownership can change after SetupFrame, including
-- while a hot-reloaded orphan state still owns a look gesture.
local EndLook

local playerControls = GetConVar and GetConVar( CVAR ) or nil
if not playerControls and CreateClientConVar then
	playerControls = CreateClientConVar( CVAR, "0", true, false,
		"Allow normal movement while an Advanced Material Editor window is open. Hold right mouse outside its windows to look around." )
end
W.PlayerControlsConVar = playerControls

local function Callable( object, name )
	return object ~= nil and isfunction( object[ name ] )
end

local function Finite( value )
	value = tonumber( value )
	return value ~= nil and value == value and math.abs( value ) < 1000000
end

local function ScreenWide()
	return math.max( 1, tonumber( ScrW and ScrW() ) or 1 )
end

local function ScreenTall()
	return math.max( 1, tonumber( ScrH and ScrH() ) or 1 )
end

local function Minimum( frame, getter, fallback )
	if Callable( frame, getter ) then
		local ok, value = pcall( frame[ getter ], frame )
		if ok and Finite( value ) then return math.max( 1, tonumber( value ) ) end
	end
	return fallback
end

local function SafeGeometryKey( key )
	if not isstring( key ) or key == "" then return nil end
	key = string.lower( key )
	key = string.gsub( key, "[^%w_%-]", "_" )
	if #key > 64 then key = string.sub( key, 1, 64 ) end
	return key ~= "" and key or nil
end

local function CookieRead( name )
	if not cookie or not isfunction( cookie.GetString ) then return nil end
	local value = cookie.GetString( name, "" )
	if value == "" or not Finite( value ) then return nil end
	return tonumber( value )
end

local function CookieWrite( name, value )
	if not cookie or not isfunction( cookie.Set ) then return end
	cookie.Set( name, tostring( math.floor( tonumber( value ) or 0 ) ) )
end

local function FramePosition( frame )
	if not IsValid( frame ) then return 0, 0 end
	if Callable( frame, "LocalToScreen" ) then
		local ok, x, y = pcall( frame.LocalToScreen, frame, 0, 0 )
		if ok and Finite( x ) and Finite( y ) then return x, y end
	end
	if Callable( frame, "GetPos" ) then
		local ok, x, y = pcall( frame.GetPos, frame )
		if ok and Finite( x ) and Finite( y ) then return x, y end
	end
	return 0, 0
end

local function FrameSize( frame )
	local w, h = 1, 1
	if Callable( frame, "GetSize" ) then
		local ok, gotW, gotH = pcall( frame.GetSize, frame )
		if ok and Finite( gotW ) and Finite( gotH ) then
			w, h = gotW, gotH
		end
	else
		if Callable( frame, "GetWide" ) then
			local ok, got = pcall( frame.GetWide, frame )
			if ok and Finite( got ) then w = got end
		end
		if Callable( frame, "GetTall" ) then
			local ok, got = pcall( frame.GetTall, frame )
			if ok and Finite( got ) then h = got end
		end
	end
	return math.max( 1, w ), math.max( 1, h )
end

local function IsShown( frame )
	if not IsValid( frame ) then return false end
	if not Callable( frame, "IsVisible" ) then return true end
	local ok, shown = pcall( frame.IsVisible, frame )
	return not ok or shown == true
end

local function FindVisibleRoot( excluded )
	for candidate in pairs( W.RootStates ) do
		if candidate ~= excluded and IsValid( candidate ) and IsShown( candidate ) then
			return candidate
		end
	end
	return nil
end

--- Resolve the controller at the root of an AdvMat window stack.  AdvMatHost
--- links separate top-level DFrames; the normal VGUI parent chain covers small
--- transient frames (for example the texture editor's colour chooser).
function AdvMat.WindowUX.GetRoot( frame )
	if not IsValid( frame ) then return nil end

	local original = frame
	local current = frame
	local seen = {}
	for _ = 1, 32 do
		if seen[ current ] then break end
		seen[ current ] = true

		local nextPanel = IsValid( current.AdvMatHost ) and current.AdvMatHost or nil
		if not IsValid( nextPanel ) and Callable( current, "GetParent" ) then
			local ok, parent = pcall( current.GetParent, current )
			if ok and IsValid( parent ) and W.Frames[ parent ] then nextPanel = parent end
		end

		if not IsValid( nextPanel ) or nextPanel == current then break end
		current = nextPanel
	end

	local record = W.Frames[ original ]
	if record then record.root = current end
	return current
end

local function RootState( root, create )
	root = W.GetRoot( root )
	if not IsValid( root ) then return nil end
	local state = W.RootStates[ root ]
	if not state and create then
		state = {
			root = root,
			playerControls = playerControls and playerControls:GetBool() or false,
			looking = false,
			cascade = 0,
			focusFrame = root,
			waitForRightRelease = false,
		}
		W.RootStates[ root ] = state
	end
	return state
end

local function EachOwnedFrame( root, callback )
	if root == nil then return end
	if IsValid( root ) then root = W.GetRoot( root ) end
	for frame, record in pairs( W.Frames ) do
		if IsValid( frame ) then
			local owner = IsValid( root ) and W.GetRoot( frame ) or record.root
			if owner == root or record.root == root then
				record.root = root
				callback( frame )
			end
		end
	end
end

local function OwnedVisibleFrame( root, preferred, excluded )
	if IsValid( preferred ) and preferred ~= excluded and IsShown( preferred )
	and W.GetRoot( preferred ) == root then
		return preferred
	end
	if IsValid( root ) and root ~= excluded and IsShown( root ) then return root end
	for frame, record in pairs( W.Frames ) do
		if frame ~= excluded and IsValid( frame ) and IsShown( frame )
		and ( record.root == root or W.GetRoot( frame ) == root ) then
			return frame
		end
	end
	return nil
end

--- Clamp both the dimensions and the title bar to the current desktop.  A
--- declared minimum larger than the screen remains authoritative; in that
--- impossible case position zero is safer than inventing a smaller broken UI.
function AdvMat.WindowUX.ClampToScreen( frame )
	if not IsValid( frame ) then return false end

	local sw, sh = ScreenWide(), ScreenTall()
	local minW = Minimum( frame, "GetMinWidth", 80 )
	local minH = Minimum( frame, "GetMinHeight", 60 )
	local w, h = FrameSize( frame )
	local availableW = math.max( 1, sw - SCREEN_MARGIN * 2 )
	local availableH = math.max( 1, sh - SCREEN_MARGIN * 2 )

	w = math.max( minW, math.min( w, math.max( minW, availableW ) ) )
	h = math.max( minH, math.min( h, math.max( minH, availableH ) ) )
	if Callable( frame, "SetSize" ) then frame:SetSize( w, h ) end

	local x, y = FramePosition( frame )
	local maxX, maxY = sw - w - SCREEN_MARGIN, sh - h - SCREEN_MARGIN
	if maxX < SCREEN_MARGIN then x = math.max( 0, math.min( x, sw - w ))
	else x = math.Clamp( x, SCREEN_MARGIN, maxX ) end
	if maxY < SCREEN_MARGIN then y = math.max( 0, math.min( y, sh - h ))
	else y = math.Clamp( y, SCREEN_MARGIN, maxY ) end

	if Callable( frame, "SetPos" ) then frame:SetPos( math.floor( x ), math.floor( y ) ) end
	return true
end

function AdvMat.WindowUX.WasGeometryRestored( frame )
	return IsValid( frame ) and frame.AdvMatWindowUXGeometryRestored == true
end

local function RememberGeometry( frame, record )
	if not IsValid( frame ) or not record then return false end
	record.x, record.y = FramePosition( frame )
	record.w, record.h = FrameSize( frame )
	return true
end

function AdvMat.WindowUX.RestoreGeometry( frame, key )
	if not IsValid( frame ) then return false end
	key = SafeGeometryKey( key or frame.AdvMatWindowUXKey )
	frame.AdvMatWindowUXKey = key
	frame.AdvMatWindowUXGeometryRestored = false
	if not key then return false end

	local prefix = COOKIE_PREFIX .. key .. "_"
	local x, y = CookieRead( prefix .. "x" ), CookieRead( prefix .. "y" )
	local w, h = CookieRead( prefix .. "w" ), CookieRead( prefix .. "h" )
	if not x or not y or not w or not h then return false end

	-- Pixel-perfect coordinates are only meaningful on the display where they
	-- were saved. Scale both the window and its anchor when moving between
	-- resolutions/DPI levels so an inspector that was usable at 1080p does not
	-- become a tiny, clipped panel at 4K (or an off-screen giant in reverse).
	local savedSW = CookieRead( prefix .. "sw" )
	local savedSH = CookieRead( prefix .. "sh" )
	if savedSW and savedSH and savedSW > 0 and savedSH > 0 then
		local scaleX = ScreenWide() / savedSW
		local scaleY = ScreenTall() / savedSH
		x, y = x * scaleX, y * scaleY
		w, h = w * scaleX, h * scaleY
	end

	local minW = Minimum( frame, "GetMinWidth", 80 )
	local minH = Minimum( frame, "GetMinHeight", 60 )
	if w < minW or h < minH then return false end
	if Callable( frame, "SetSize" ) then frame:SetSize( w, h ) end
	if Callable( frame, "SetPos" ) then frame:SetPos( x, y ) end
	W.ClampToScreen( frame )
	frame.AdvMatWindowUXGeometryRestored = true
	return true
end

function AdvMat.WindowUX.SaveGeometry( frame, key )
	local record = W.Frames[ frame ]
	local valid = IsValid( frame )
	key = SafeGeometryKey( key or ( record and record.key )
		or ( valid and frame.AdvMatWindowUXKey ) )
	if not key then return false end

	local x, y, w, h
	if valid then
		W.ClampToScreen( frame )
		if record then
			RememberGeometry( frame, record )
			x, y, w, h = record.x, record.y, record.w, record.h
		else
			x, y = FramePosition( frame )
			w, h = FrameSize( frame )
		end
	elseif record then
		x, y, w, h = record.x, record.y, record.w, record.h
	end
	if not Finite( x ) or not Finite( y ) or not Finite( w ) or not Finite( h ) then return false end
	local prefix = COOKIE_PREFIX .. key .. "_"
	CookieWrite( prefix .. "x", x )
	CookieWrite( prefix .. "y", y )
	CookieWrite( prefix .. "w", w )
	CookieWrite( prefix .. "h", h )
	CookieWrite( prefix .. "sw", ScreenWide() )
	CookieWrite( prefix .. "sh", ScreenTall() )
	return true
end

--- Preserve a window's relative size and position when Source changes video
--- mode or Windows moves the game between differently scaled displays.
function AdvMat.WindowUX.HandleScreenSizeChanged( oldWidth, oldHeight )
	oldWidth = Finite( oldWidth ) and tonumber( oldWidth ) or W.LastScreenWidth
	oldHeight = Finite( oldHeight ) and tonumber( oldHeight ) or W.LastScreenHeight
	local newWidth, newHeight = ScreenWide(), ScreenTall()
	W.LastScreenWidth, W.LastScreenHeight = newWidth, newHeight
	if not oldWidth or not oldHeight or oldWidth <= 0 or oldHeight <= 0 then return end

	local scaleX, scaleY = newWidth / oldWidth, newHeight / oldHeight
	for frame in pairs( W.Frames ) do
		if IsValid( frame ) then
			local x, y = FramePosition( frame )
			local w, h = FrameSize( frame )
			if Callable( frame, "SetSize" ) then frame:SetSize( w * scaleX, h * scaleY ) end
			if Callable( frame, "SetPos" ) then frame:SetPos( x * scaleX, y * scaleY ) end
			W.ClampToScreen( frame )
		end
	end
end

W.LastScreenWidth = ScreenWide()
W.LastScreenHeight = ScreenTall()

local function TargetOnScreen( ent )
	if IsValid( ent ) and Callable( ent, "WorldSpaceCenter" ) then
		local ok, projected = pcall( function()
			local centre = ent:WorldSpaceCenter()
			return centre and centre.ToScreen and centre:ToScreen() or nil
		end )
		if ok and istable( projected ) and Finite( projected.x ) and Finite( projected.y )
		and projected.visible ~= false then return projected.x, projected.y end
	end

	-- World-material opens do not carry an entity.  The click which opened the
	-- editor is still the local eye trace, so use its hit point when available.
	local ply = LocalPlayer and LocalPlayer() or nil
	if IsValid( ply ) and Callable( ply, "GetEyeTrace" ) then
		local ok, projected = pcall( function()
			local trace = ply:GetEyeTrace()
			local hit = trace and trace.HitPos
			return hit and hit.ToScreen and hit:ToScreen() or nil
		end )
		if ok and istable( projected ) and Finite( projected.x ) and Finite( projected.y )
		and projected.visible ~= false then return projected.x, projected.y end
	end

	return ScreenWide() * 0.5, ScreenTall() * 0.5
end

local function CandidateScore( candidate, targetX, targetY, preferredSide )
	local left, top = candidate.x, candidate.y
	local right, bottom = left + candidate.w, top + candidate.h
	local dx = math.max( left - targetX, 0, targetX - right )
	local dy = math.max( top - targetY, 0, targetY - bottom )
	local inside = dx == 0 and dy == 0
	local score = math.sqrt( dx * dx + dy * dy ) * 10
	if inside then
		-- Prefer the candidate whose closest edge leaves the target least buried.
		local edge = math.min( targetX - left, right - targetX,
			targetY - top, bottom - targetY )
		score = -100000 - math.max( 0, edge )
	end
	if candidate.side == preferredSide then score = score + 1000 end
	-- Do not shrink a window unless doing so creates useful world-view space.
	score = score + candidate.w * 0.01
	return score
end

--- Put a primary editor against the least obstructive horizontal edge.  When
--- one side has enough room before the projected target, the window may become
--- narrower (never below its declared minimum) to keep that target fully clear.
function AdvMat.WindowUX.PositionBesideTarget( frame, ent, force )
	if not IsValid( frame ) then return false end
	if W.WasGeometryRestored( frame ) and force ~= true then return false end

	local sw, sh = ScreenWide(), ScreenTall()
	local targetX, targetY = TargetOnScreen( ent )
	targetX = math.Clamp( targetX, 0, sw )
	targetY = math.Clamp( targetY, 0, sh )

	local minW = Minimum( frame, "GetMinWidth", 80 )
	local minH = Minimum( frame, "GetMinHeight", 60 )
	local frameW, frameH = FrameSize( frame )
	frameH = math.max( minH, math.min( frameH, math.max( minH, sh - SCREEN_MARGIN * 2 ) ) )
	local frameY = math.Clamp( targetY - frameH * 0.5, SCREEN_MARGIN,
		math.max( SCREEN_MARGIN, sh - frameH - SCREEN_MARGIN ) )

	local leftRoom = targetX - TARGET_GAP - SCREEN_MARGIN
	local rightRoom = sw - targetX - TARGET_GAP - SCREEN_MARGIN
	-- Even when neither side can provide the ideal gap, reducing to the declared
	-- minimum exposes as much of the object as this display can physically fit.
	-- Keeping the original width in that case needlessly covered another strip
	-- of the model while providing no additional window-management benefit.
	local leftW = math.min( frameW, math.max( minW, leftRoom ) )
	local rightW = math.min( frameW, math.max( minW, rightRoom ) )
	leftW = math.max( minW, math.min( leftW, math.max( minW, sw - SCREEN_MARGIN * 2 ) ) )
	rightW = math.max( minW, math.min( rightW, math.max( minW, sw - SCREEN_MARGIN * 2 ) ) )

	local candidates = {
		{ side = "left", x = SCREEN_MARGIN, y = frameY, w = leftW, h = frameH },
		{ side = "right", x = sw - SCREEN_MARGIN - rightW, y = frameY, w = rightW, h = frameH },
	}
	local preferred = targetX <= sw * 0.5 and "right" or "left"
	local best, bestScore
	for _, candidate in ipairs( candidates ) do
		local score = CandidateScore( candidate, targetX, targetY, preferred )
		if not bestScore or score > bestScore then best, bestScore = candidate, score end
	end

	if not best then return false end
	if Callable( frame, "SetSize" ) then frame:SetSize( best.w, best.h ) end
	if Callable( frame, "SetPos" ) then frame:SetPos( best.x, best.y ) end
	W.ClampToScreen( frame )
	return true
end

--- Place a subordinate window alongside its host when there is room, or use a
--- visibly offset cascade when both sides are occupied.  This avoids opening a
--- dialog exactly over the control and preview that launched it.
function AdvMat.WindowUX.PlaceChild( frame, host, force )
	if not IsValid( frame ) then return false end
	local record = W.Frames[ frame ]
	local oldRoot = record and record.root or W.GetRoot( frame )
	if IsValid( host ) then
		frame.AdvMatHost = host
		local root = W.GetRoot( host )
		if record then
			record.host = host
			record.root = root
		end
		if oldRoot and oldRoot ~= root and W.RootStates[ oldRoot ] then
			local orphan = W.RootStates[ oldRoot ]
			if orphan.looking then EndLook( orphan, false ) end
			W.RootStates[ oldRoot ] = nil
		end
		RootState( root, true )
		W.ActiveRoot = root
	end
	if W.WasGeometryRestored( frame ) and force ~= true then return false end
	if not IsValid( host ) then return W.ClampToScreen( frame ) end

	local sw, sh = ScreenWide(), ScreenTall()
	local hostX, hostY = FramePosition( host )
	local hostW, hostH = FrameSize( host )
	local w, h = FrameSize( frame )
	local rightX = hostX + hostW + CHILD_GAP
	local leftX = hostX - w - CHILD_GAP
	local x, y

	if rightX + w <= sw - SCREEN_MARGIN then
		x, y = rightX, hostY
	elseif leftX >= SCREEN_MARGIN then
		x, y = leftX, hostY
	else
		local root = W.GetRoot( host )
		local state = RootState( root, true )
		state.cascade = ( state.cascade or 0 ) % 6 + 1
		local offset = 22 * state.cascade
		x, y = hostX + offset, hostY + offset
	end

	x = math.Clamp( x, SCREEN_MARGIN, math.max( SCREEN_MARGIN, sw - w - SCREEN_MARGIN ) )
	y = math.Clamp( y, SCREEN_MARGIN, math.max( SCREEN_MARGIN, sh - h - SCREEN_MARGIN ) )
	if Callable( frame, "SetPos" ) then frame:SetPos( x, y ) end
	return W.ClampToScreen( frame )
end

local function OwnerForPanel( panel )
	if not IsValid( panel ) then return nil end

	-- Walk outward from the focused/hovered control. Iterating the weak frame
	-- table made a nested dialog nondeterministically resolve to its parent root,
	-- leaving the actual text-entry window keyboard-disabled.
	local current, seen = panel, {}
	for _ = 1, 64 do
		if not IsValid( current ) or seen[ current ] then break end
		seen[ current ] = true
		if W.Frames[ current ] then
			local root = W.GetRoot( current )
			return current, root, RootState( root, false )
		end
		if not Callable( current, "GetParent" ) then break end
		local ok, parent = pcall( current.GetParent, current )
		if not ok then break end
		current = parent
	end
	return nil
end

local function EditableTextFocus( root, state )
	local focus = state and IsValid( state.textFocus ) and state.textFocus or nil
	if not IsValid( focus ) and vgui and isfunction( vgui.GetKeyboardFocus ) then
		focus = vgui.GetKeyboardFocus()
	end
	if not IsValid( focus ) then return nil end

	local class = ""
	if Callable( focus, "GetClassName" ) then
		local ok, value = pcall( focus.GetClassName, focus )
		if ok then class = string.lower( tostring( value or "" ) ) end
	end
	local editable = focus.AdvMatAcceptsTextInput == true
		or string.find( class, "textentry", 1, true ) ~= nil
		or string.find( class, "numberwang", 1, true ) ~= nil
	if not editable then return nil end

	local frame, ownerRoot = OwnerForPanel( focus )
	if IsValid( frame ) and ownerRoot == root then return focus, frame end
	return nil
end

local function SetFrameInput( frame, mouseEnabled, keyboardEnabled )
	if not IsValid( frame ) then return end
	if mouseEnabled ~= nil and Callable( frame, "SetMouseInputEnabled" )
	and frame.AdvMatWindowUXMouse ~= mouseEnabled then
		frame:SetMouseInputEnabled( mouseEnabled )
		frame.AdvMatWindowUXMouse = mouseEnabled
	end
	if keyboardEnabled ~= nil and Callable( frame, "SetKeyboardInputEnabled" )
	and frame.AdvMatWindowUXKeyboard ~= keyboardEnabled then
		frame:SetKeyboardInputEnabled( keyboardEnabled )
		frame.AdvMatWindowUXKeyboard = keyboardEnabled
	end
end

local function UpdateKeyboard( state )
	if not state or not IsValid( state.root ) then return end
	local _, editingFrame = EditableTextFocus( state.root, state )
	EachOwnedFrame( state.root, function( frame )
		local keyboard = not state.playerControls
			or ( IsValid( editingFrame ) and frame == editingFrame )
		-- A text field that lets go as a look starts lands here mid-look; the
		-- windows keep their input off until the look ends.
		SetFrameInput( frame, not state.looking, not state.looking and keyboard )
	end )
end

local function GameUIVisible()
	if not gui then return false end
	if isfunction( gui.IsGameUIVisible ) and gui.IsGameUIVisible() == true then return true end
	return isfunction( gui.IsConsoleVisible ) and gui.IsConsoleVisible() == true
end

EndLook = function( state, restoreScreenClicker )
	if not state or not state.looking then return end
	state.looking = false
	if W.LookRoot == state.root then W.LookRoot = nil end

	EachOwnedFrame( state.root, function( frame )
		SetFrameInput( frame, true, nil )
	end )
	UpdateKeyboard( state )

	if restoreScreenClicker and IsValid( state.root ) and IsShown( state.root )
	and not GameUIVisible() then
		-- Restore the actual popup rather than turning on the ownerless global
		-- screen clicker.  The popup can then release input normally when closed.
		W.Focus( OwnedVisibleFrame( state.root, state.focusFrame ) or state.root )
		if input and isfunction( input.SetCursorPos ) and Finite( state.cursorX )
		and Finite( state.cursorY ) then input.SetCursorPos( state.cursorX, state.cursorY ) end
		state.pendingFocus = false
		state.restoreCursor = false
	elseif restoreScreenClicker and IsValid( state.root ) then
		-- The escape menu owns the cursor for now. Reclaim it after that menu has
		-- gone rather than fighting a global engine UI from this Think tick.
		state.pendingFocus = true
		state.restoreCursor = true
	end

	if hook and isfunction( hook.Run ) then
		hook.Run( "AdvMatWorldLookChanged", state.root, false )
	end
end

local function CursorPosition()
	if input and isfunction( input.GetCursorPos ) then
		local x, y = input.GetCursorPos()
		if Finite( x ) and Finite( y ) then return x, y end
	end
	if gui and isfunction( gui.MousePos ) then
		local x, y = gui.MousePos()
		if Finite( x ) and Finite( y ) then return x, y end
	end
	if gui and isfunction( gui.MouseX ) and isfunction( gui.MouseY ) then
		return gui.MouseX(), gui.MouseY()
	end
	return 0, 0
end

local function CursorOutsideOwnedWindows( root, x, y )
	local outside = true
	EachOwnedFrame( root, function( frame )
		if not outside or not IsShown( frame ) then return end
		local px, py = FramePosition( frame )
		local w, h = FrameSize( frame )
		if x >= px and x < px + w and y >= py and y < py + h then outside = false end
	end )
	return outside
end

local function BeginLook( state )
	if not state or state.looking or W.LookRoot then return false end
	if not state.playerControls or not IsValid( state.root ) or GameUIVisible() then return false end
	if vgui and isfunction( vgui.CursorVisible ) and not vgui.CursorVisible() then return false end

	state.cursorX, state.cursorY = CursorPosition()
	if not CursorOutsideOwnedWindows( state.root, state.cursorX, state.cursorY ) then return false end
	state.looking = true
	state.pendingFocus = false
	W.LookRoot = state.root
	W.WorldLookLease = true
	W.PendingWorldRelease = false

	if isfunction( CloseDermaMenus ) then CloseDermaMenus() end
	local focus = vgui and isfunction( vgui.GetKeyboardFocus ) and vgui.GetKeyboardFocus() or nil
	local focusFrame, focusRoot = OwnerForPanel( focus )
	if IsValid( focusFrame ) and focusRoot == state.root and IsShown( focusFrame ) then
		state.focusFrame = focusFrame
	end
	if IsValid( focus ) and Callable( focus, "KillFocus" ) then focus:KillFocus() end
	EachOwnedFrame( state.root, function( frame ) SetFrameInput( frame, false, false ) end )
	if gui and isfunction( gui.EnableScreenClicker ) then gui.EnableScreenClicker( false ) end

	if hook and isfunction( hook.Run ) then
		hook.Run( "AdvMatWorldLookChanged", state.root, true )
	end
	return true
end

local function QueueRootFocus( root, cursorX, cursorY, preferred )
	local state = RootState( root, true )
	if not state then return false end
	state.pendingFocus = true
	state.pendingFrame = OwnedVisibleFrame( root, preferred or state.focusFrame ) or root
	state.waitForRightRelease = false
	state.restoreCursor = Finite( cursorX ) and Finite( cursorY )
	if state.restoreCursor then
		state.cursorX, state.cursorY = cursorX, cursorY
	end
	return true
end

local function PanelChainVisible( panel )
	local current, seen = panel, {}
	for _ = 1, 64 do
		if not IsValid( current ) or seen[ current ] then break end
		seen[ current ] = true
		if Callable( current, "IsVisible" ) then
			local ok, visible = pcall( current.IsVisible, current )
			if ok and visible == false then return false end
		end
		if not Callable( current, "GetParent" ) then break end
		local ok, parent = pcall( current.GetParent, current )
		if not ok or not IsValid( parent ) or parent == current then break end
		current = parent
	end
	return IsValid( panel )
end

local function PanelFlag( panel, method, fallback )
	if not IsValid( panel ) or not Callable( panel, method ) then return fallback end
	local ok, value = pcall( panel[ method ], panel )
	if not ok then return fallback end
	return value == true
end

local function ForeignPopupVisible()
	local function visibleMouseOwner( panel )
		if not IsValid( panel ) or not PanelChainVisible( panel ) then return false end
		local owner = OwnerForPanel( panel )
		if IsValid( owner ) then return false end
		return not Callable( panel, "IsMouseInputEnabled" )
			or PanelFlag( panel, "IsMouseInputEnabled", true )
	end
	local function blocks( panel )
		return visibleMouseOwner( panel ) and PanelFlag( panel, "IsPopup", false )
	end

	local spawnMenu = _G and _G.g_SpawnMenu or nil
	local contextMenu = _G and _G.g_ContextMenu or nil
	if visibleMouseOwner( spawnMenu ) or visibleMouseOwner( contextMenu ) then return true end

	local hovered = vgui and isfunction( vgui.GetHoveredPanel )
		and vgui.GetHoveredPanel() or nil
	if blocks( hovered ) then return true end

	if vgui and isfunction( vgui.GetAll ) then
		local ok, panels = pcall( vgui.GetAll )
		if ok and type( panels ) == "table" then
			for _, panel in pairs( panels ) do
				if blocks( panel ) then return true end
			end
		end
	end
	return false
end

local function QueueWorldRelease()
	W.PendingWorldRelease = true
	W.ReleaseAfterEpoch = math.max( tonumber( W.ReleaseAfterEpoch ) or 0,
		( tonumber( W.InputEpoch ) or 0 ) + 1 )
end

local function ReconcileWorldInput()
	if not W.WorldLookLease and not W.PendingWorldRelease then return false end
	if ( tonumber( W.InputEpoch ) or 0 ) < ( tonumber( W.ReleaseAfterEpoch ) or 0 ) then
		return false
	end
	if FindVisibleRoot() or GameUIVisible() then return false end

	-- Do not steal a cursor which another addon opened while this editor was
	-- closing. A hidden/removed AdvMat control does not count as an external
	-- owner; its parent chain becomes invisible before this deferred pass.
	local focus = vgui and isfunction( vgui.GetKeyboardFocus )
		and vgui.GetKeyboardFocus() or nil
	local owner = IsValid( focus ) and OwnerForPanel( focus ) or nil
	if IsValid( focus ) and not IsValid( owner ) and PanelChainVisible( focus ) then
		return false
	end
	if ForeignPopupVisible() then return false end
	if hook and isfunction( hook.Run )
	and hook.Run( "AdvMatShouldKeepScreenClicker" ) == true then return false end

	if gui and isfunction( gui.EnableScreenClicker ) then gui.EnableScreenClicker( false ) end
	W.WorldLookLease = false
	W.PendingWorldRelease = false
	W.ReleaseAfterEpoch = 0
	return true
end

--- Keep ordinary Derma mouse controls, but let un-focused keyboard input pass
--- to the game.  The convar is global by design: users do not have to discover
--- and enable the same accessibility option in every editor variant.
function AdvMat.WindowUX.ApplyPlayerControls( root, enabled, skipConVarWrite )
	root = W.GetRoot( root )
	if not IsValid( root ) then return false end
	local state = RootState( root, true )
	enabled = enabled == true or enabled == 1 or enabled == "1"

	if state.looking and not enabled then
		local held = input and isfunction( input.IsMouseDown )
			and input.IsMouseDown( MOUSE_RIGHT ) == true
		EndLook( state, not held )
		if held then
			state.pendingFocus = true
			state.pendingFrame = OwnedVisibleFrame( state.root, state.focusFrame )
			state.restoreCursor = true
			state.waitForRightRelease = true
			W.SuppressRightUntilRelease = true
		end
	end
	state.playerControls = enabled
	UpdateKeyboard( state )

	if skipConVarWrite ~= true and playerControls and playerControls:GetBool() ~= enabled
	and RunConsoleCommand then
		RunConsoleCommand( CVAR, enabled and "1" or "0" )
	end
	return true
end

--- Focus without throwing away player-control mode.  Repeated tool clicks use
--- this instead of a raw MakePopup, which would otherwise recapture keyboard
--- focus and interrupt movement.
function AdvMat.WindowUX.Focus( frame )
	if not IsValid( frame ) then return false end
	local root = W.GetRoot( frame )
	local state = RootState( root, true )
	W.ActiveRoot = root
	state.focusFrame = frame

	if state.looking then
		if Callable( frame, "MoveToFront" ) then frame:MoveToFront() end
		return true
	end

	if Callable( frame, "MakePopup" ) then
		frame:MakePopup()
		-- MakePopup forcibly re-enables both input paths. Invalidate our cached
		-- state so UpdateKeyboard really reapplies movement-through-UI mode.
		frame.AdvMatWindowUXMouse = nil
		frame.AdvMatWindowUXKeyboard = nil
	end
	if Callable( frame, "MoveToFront" ) then frame:MoveToFront() end
	SetFrameInput( frame, true, nil )
	UpdateKeyboard( state )
	return true
end

local function InstallAffordances( frame )
	if frame.AdvMatWindowUXAffordance then return end
	frame.AdvMatWindowUXAffordance = true

	local oldPaintOver = frame.PaintOver
	frame.PaintOver = function( pnl, w, h )
		if oldPaintOver then oldPaintOver( pnl, w, h ) end
		local theme = AdvMat.Theme or {}
		local dim = theme.TextDim or Color( 176, 181, 190 )
		local hot = theme.Accent or Color( 104, 176, 255 )
		local colour = ( pnl.Dragging or pnl.Sizing ) and hot or dim

		-- Six dots make the title bar's drag affordance visible without installing
		-- a child panel that would steal the DFrame's own drag mouse handling.
		local cx = math.floor( w * 0.5 ) - 7
		surface.SetDrawColor( colour.r, colour.g, colour.b, 180 )
		for row = 0, 1 do
			for col = 0, 2 do surface.DrawRect( cx + col * 6, 7 + row * 6, 2, 2 ) end
		end

		local sizable = Callable( pnl, "GetSizable" ) and pnl:GetSizable()
		if sizable then
			-- Stock DFrame already accepts drags in this 20 px corner; the missing
			-- piece was only a visible, industry-standard diagonal grip.
			for offset = 0, 2 do
				local inset = 5 + offset * 5
				surface.DrawLine( w - inset, h - 2, w - 2, h - inset )
			end
		end
	end
end

local function DirectHost( frame )
	local record = W.Frames[ frame ]
	if record and record.host ~= nil then return record.host end
	if not IsValid( frame ) then return nil end
	if frame.AdvMatHost ~= nil then return frame.AdvMatHost end
	if Callable( frame, "GetParent" ) then
		local ok, parent = pcall( frame.GetParent, frame )
		if ok and IsValid( parent ) and W.Frames[ parent ] then return parent end
	end
	return nil
end

local function DescendantDepth( frame, ancestor )
	local current, seen = frame, {}
	for depth = 1, 64 do
		local host = DirectHost( current )
		if host == ancestor then return depth end
		if host == nil or seen[ host ] then return nil end
		seen[ host ] = true
		current = host
	end
	return nil
end

local function MarkedForDeletion( frame )
	if not IsValid( frame ) or not Callable( frame, "IsMarkedForDeletion" ) then return false end
	local ok, marked = pcall( frame.IsMarkedForDeletion, frame )
	return ok and marked == true
end

local function CloseDescendants( owner )
	local descendants = {}
	for frame in pairs( W.Frames ) do
		if frame ~= owner then
			local depth = DescendantDepth( frame, owner )
			if depth then descendants[ #descendants + 1 ] = { frame = frame, depth = depth } end
		end
	end
	table.sort( descendants, function( a, b ) return a.depth > b.depth end )

	for _, item in ipairs( descendants ) do
		local frame = item.frame
		if IsValid( frame ) and not W.CleaningFrames[ frame ] then
			if Callable( frame, "Close" ) then pcall( frame.Close, frame ) end
			-- A vetoed child or SetDeleteOnClose(false) must not outlive its host.
			-- Stock DFrame removal is only queued, so avoid issuing it twice when the
			-- engine already marked the panel during Close.
			if IsValid( frame ) and not MarkedForDeletion( frame )
			and Callable( frame, "Remove" ) then pcall( frame.Remove, frame ) end
		end
		if W.Frames[ frame ] then AdvMat.WindowUX.Cleanup( frame ) end
	end
end

--- Register a top-level editor/dialog after its size has been chosen. Passing a
--- key opts it into geometry persistence; keyless transient dialogs still gain
--- screen lock and clear drag/resize affordances.
function AdvMat.WindowUX.SetupFrame( frame, key )
	if not IsValid( frame ) then return false end
	local first = W.Frames[ frame ] == nil
	local record = W.Frames[ frame ] or {}
	local previousRoot = record.root
	local oldKey = record.key
	W.Frames[ frame ] = record
	local directHost = IsValid( frame.AdvMatHost ) and frame.AdvMatHost or nil
	if not IsValid( directHost ) and Callable( frame, "GetParent" ) then
		local ok, parent = pcall( frame.GetParent, frame )
		if ok and IsValid( parent ) and W.Frames[ parent ] then directHost = parent end
	end
	record.host = directHost
	if key ~= nil then
		record.key = SafeGeometryKey( key )
		frame.AdvMatWindowUXKey = record.key
	end
	local keyChanged = key ~= nil and record.key ~= oldKey

	if Callable( frame, "SetDraggable" ) then frame:SetDraggable( true ) end
	if Callable( frame, "SetScreenLock" ) then frame:SetScreenLock( true ) end
	InstallAffordances( frame )

	-- A frame may be registered before its durable identity is known. Supplying
	-- that key on a later SetupFrame call must still restore its saved geometry.
	if first or keyChanged then W.RestoreGeometry( frame, record.key ) end
	W.ClampToScreen( frame )
	RememberGeometry( frame, record )

	if first then
		-- Save while the panel is certainly valid. Some engine branches mark a
		-- panel invalid before OnRemove runs, so relying on that callback alone
		-- silently loses the final drag/resize position.
		if Callable( frame, "Close" ) then
			local oldClose = frame.Close
			frame.Close = function( pnl, ... )
				W.SaveGeometry( pnl )
				local result = oldClose( pnl, ... )
				-- Most DFrames remove themselves, but SetDeleteOnClose(false) and
				-- custom close methods may only hide. Hidden roots must release the
				-- same input state as removed ones. A vetoed close remains visible.
				if not IsShown( pnl ) then W.Cleanup( pnl ) end
				return result
			end
		end

		local oldOnRemove = frame.OnRemove
		frame.OnRemove = function( pnl, ... )
			W.SaveGeometry( pnl )
			W.Cleanup( pnl )
			if oldOnRemove then return oldOnRemove( pnl, ... ) end
		end
	end

	local root = W.GetRoot( frame )
	-- StyleFrame runs from several panel Init methods before their opener can
	-- attach AdvMatHost. Retire that temporary self-root when SetupFrame is called
	-- again after hosting, otherwise it looks like a second visible editor and can
	-- prevent the real root from releasing input on close.
	if previousRoot == frame and previousRoot ~= root and W.RootStates[ previousRoot ] then
		local orphan = W.RootStates[ previousRoot ]
		if orphan.looking then EndLook( orphan, false ) end
		W.RootStates[ previousRoot ] = nil
		if W.LookRoot == previousRoot then W.LookRoot = nil end
		if W.ActiveRoot == previousRoot then W.ActiveRoot = root end
	end
	local state = RootState( root, true )
	record.root = root
	state.focusFrame = frame
	W.ActiveRoot = root
	UpdateKeyboard( state )
	return true
end

--- Remove one frame from the registry, or tear down a complete root stack.  Do
--- not blindly enable the screen clicker while a root is disappearing: another
--- popup or the game menu may legitimately own global cursor state by then.
function AdvMat.WindowUX.Cleanup( frame )
	if not frame then return end
	if W.CleaningFrames[ frame ] then return end
	local record = W.Frames[ frame ]
	-- OnRemove timing differs between engine branches. Some still consider the
	-- panel valid while invoking it and some do not, so retain the last known
	-- root in our weak registration record instead of relying on IsValid here.
	local root = record and record.root or nil
	if root == nil and W.RootStates[ frame ] then root = frame end
	if IsValid( frame ) then root = W.GetRoot( frame ) or root end
	local wasRoot = frame == root
	local state = root and W.RootStates[ root ] or nil
	local wasActive = W.ActiveRoot == root
	local wasLooking = state and state.looking == true
	local releaseInput = ( state and state.playerControls == true ) or W.WorldLookLease
	local cursorX, cursorY = state and state.cursorX, state and state.cursorY

	W.CleaningFrames[ frame ] = true
	CloseDescendants( frame )
	W.Frames[ frame ] = nil
	if not wasRoot then
		if state and state.focusFrame == frame then
			state.focusFrame = OwnedVisibleFrame( root, nil, frame )
		end
		-- Covers panels which were briefly registered as their own root before a
		-- host was assigned (including windows surviving a Lua hot reload).
		if W.RootStates[ frame ] and frame ~= root then W.RootStates[ frame ] = nil end
		if W.LookRoot == frame then W.LookRoot = nil end
		W.CleaningFrames[ frame ] = nil
		return
	end
	if wasLooking then
		EndLook( state, false )
		W.SuppressRightUntilRelease = input and isfunction( input.IsMouseDown )
			and input.IsMouseDown( MOUSE_RIGHT ) == true or false
	end
	for child, childRecord in pairs( W.Frames ) do
		if childRecord.root == root
		or ( IsValid( root ) and W.GetRoot( child ) == root ) then
			-- Once unregistered this panel no longer receives UpdateKeyboard, so
			-- never strand an orphaned utility window with keyboard input disabled.
			SetFrameInput( child, true, true )
			W.Frames[ child ] = nil
		end
	end
	W.RootStates[ root ] = nil
	local survivor = FindVisibleRoot( root )
	if wasActive or wasLooking or not IsValid( W.ActiveRoot ) then
		W.ActiveRoot = survivor
		if IsValid( survivor ) then
			QueueRootFocus( survivor, wasLooking and cursorX or nil,
				wasLooking and cursorY or nil )
		end
	end
	if W.LookRoot == root then W.LookRoot = nil end
	if not survivor and releaseInput then QueueWorldRelease() end
	W.CleaningFrames[ frame ] = nil
end

if hook and isfunction( hook.Add ) then
	-- DTextEntry emits these hooks specifically for popup containers which let
	-- most keyboard input fall through to the game (the Sandbox spawn menu uses
	-- the same contract). Polling GetKeyboardFocus in Think remains a fallback,
	-- but these edges make the very first typed character reliable.
	hook.Add( "OnTextEntryGetFocus", "AdvMat.WindowUX.TextFocusOn", function( panel )
		local owner, root, state = OwnerForPanel( panel )
		if not IsValid( owner ) or not state or not state.playerControls then return end
		state.textFocus = panel
		state.textFrame = owner
		W.ActiveRoot = root
		UpdateKeyboard( state )
	end )

	hook.Add( "OnTextEntryLoseFocus", "AdvMat.WindowUX.TextFocusOff", function( panel )
		local _, root, state = OwnerForPanel( panel )
		if not state or not state.playerControls then return end

		local function finish()
			if not state or state.root ~= root or not IsValid( root ) then return end
			if state.textFocus == panel then
				state.textFocus = nil
				state.textFrame = nil
			end
			UpdateKeyboard( state )
		end

		-- Focus commonly moves directly from one text field to another. Waiting a
		-- frame lets the matching GetFocus event win without briefly leaking the
		-- user's first keypress into movement.
		if timer and isfunction( timer.Simple ) then timer.Simple( 0, finish )
		else finish() end
	end )

	hook.Add( "Think", "AdvMat.WindowUX.Input", function()
		W.InputEpoch = ( tonumber( W.InputEpoch ) or 0 ) + 1
		-- Maintain an in-memory fallback for engine branches which invalidate a
		-- panel before invoking OnRemove. This does no cookie I/O and the registry
		-- normally contains only a handful of windows.
		for frame, record in pairs( W.Frames ) do
			if IsValid( frame ) then RememberGeometry( frame, record ) end
		end

		local mouseDown = input and isfunction( input.IsMouseDown )
			and input.IsMouseDown( MOUSE_RIGHT ) == true
		if not mouseDown then W.SuppressRightUntilRelease = false end
		if W.WorldLookLease and not FindVisibleRoot() and not W.PendingWorldRelease then
			QueueWorldRelease()
		end
		ReconcileWorldInput()
		local lookRoot = W.LookRoot
		if lookRoot ~= nil and not IsValid( lookRoot ) then
			-- A Lua error or another addon may remove a popup without reaching its
			-- friendly close path. Never leave that stale panel blocking all future
			-- look gestures after the world has already regained native input.
			if W.Frames[ lookRoot ] or W.RootStates[ lookRoot ] then
				W.Cleanup( lookRoot )
			else
				W.LookRoot = nil
				if W.ActiveRoot == lookRoot then W.ActiveRoot = FindVisibleRoot() end
			end
			lookRoot = W.LookRoot
		end
		local looking = IsValid( lookRoot ) and W.RootStates[ lookRoot ] or nil

		if looking and looking.looking then
			if not mouseDown or not looking.playerControls then EndLook( looking, true ) end
		else
			-- Hover is a reliable and cheap indication of which of several open
			-- AdvMat roots the user most recently interacted with. Resolve it before
			-- testing RMB so a click inside one editor can never start world-look for
			-- a different, previously active standalone window.
			local hovered = vgui and isfunction( vgui.GetHoveredPanel )
				and vgui.GetHoveredPanel() or nil
			local hoveredFrame, hoveredRoot, hoveredState = OwnerForPanel( hovered )
			if IsValid( hoveredRoot ) and IsShown( hoveredRoot ) then
				W.ActiveRoot = hoveredRoot
				if hoveredState and IsValid( hoveredFrame ) and IsShown( hoveredFrame ) then
					hoveredState.focusFrame = hoveredFrame
				end
			end

			local root = W.ActiveRoot
			local state = IsValid( root ) and RootState( root, false ) or nil
			if state and state.pendingFocus
			and ( not state.waitForRightRelease or not mouseDown )
			and not GameUIVisible() then
				state.pendingFocus = false
				state.waitForRightRelease = false
				local focusFrame = OwnedVisibleFrame( root,
					state.pendingFrame or state.focusFrame ) or root
				state.pendingFrame = nil
				W.Focus( focusFrame )
				if state.restoreCursor and input and isfunction( input.SetCursorPos )
				and Finite( state.cursorX ) and Finite( state.cursorY ) then
					input.SetCursorPos( state.cursorX, state.cursorY )
				end
				state.restoreCursor = false
			end
			if state and state.playerControls then
				UpdateKeyboard( state )
				if mouseDown and not W.RightWasDown then BeginLook( state ) end
			end
		end

		W.RightWasDown = mouseDown
	end )

	-- IN_ATTACK2 is removed only while this module has actually released the
	-- cursor for a look gesture. A normal right click inside the editor or in the
	-- world with the option disabled remains completely untouched.
	hook.Add( "CreateMove", "AdvMat.WindowUX.SuppressLookAttack", function( cmd )
		local root = W.LookRoot
		local state = IsValid( root ) and W.RootStates[ root ] or nil
		if ( not state or not state.looking ) and not W.SuppressRightUntilRelease then return end
		if not cmd then return end
		if isfunction( cmd.RemoveKey ) then
			cmd:RemoveKey( IN_ATTACK2 )
		elseif isfunction( cmd.GetButtons ) and isfunction( cmd.SetButtons )
		and bit and isfunction( bit.band ) and isfunction( bit.bnot ) then
			cmd:SetButtons( bit.band( cmd:GetButtons(), bit.bnot( IN_ATTACK2 ) ) )
		end
	end )

end

if cvars and isfunction( cvars.AddChangeCallback ) then
	if isfunction( cvars.RemoveChangeCallback ) then
		cvars.RemoveChangeCallback( CVAR, "AdvMat.WindowUX.PlayerControls" )
	end
	cvars.AddChangeCallback( CVAR, function( _, _, value )
		local enabled = tonumber( value ) ~= 0
		for root in pairs( W.RootStates ) do
			if IsValid( root ) then W.ApplyPlayerControls( root, enabled, true ) end
		end
	end, "AdvMat.WindowUX.PlayerControls" )
end
