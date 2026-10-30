--[[---------------------------------------------------------------------------
	Advanced Material Editor - the editor window

	Left  : live model preview and the list of sub-materials on the model
	Right : every parameter the selected sub-material's shader understands,
	        grouped, searchable and annotated

	Edits go into a local working copy that is previewed on your screen
	immediately. Save promotes the working copy into a real rule on the server,
	which persists it, applies it durably and shows it to everyone else.
-----------------------------------------------------------------------------]]

AdvMat = AdvMat or {}

local PREVIEW_DELAY = 0.06

local T = AdvMat.Theme

local function L( key, fallback )
	return AdvMat.L and AdvMat.L( key ) or fallback
end

-- Shaders that make sense on a .mdl. Anything else still applies, but with a
-- caveat worth telling the user about. Keys are canonical spellings; the
-- shader read out of a .vmt is folded through AdvMat.CanonicalShader first,
-- because authors write "VertexlitGeneric" and "vertexlitgeneric" just as
-- often as the documented spelling.
local MODEL_SHADERS = {
	VertexLitGeneric = true,
	EyeRefract       = true,
	Eyes             = true,
	Cable            = true,
	Refract          = true,
	Sprite           = true,
	SpriteCard       = true,
	Modulate         = true,
	Wireframe        = true,
}

local BRUSH_ONLY = {
	LightmappedGeneric    = true,
	WorldVertexTransition = true,
	Water                 = true,
}

---------------------------------------------------------------------------
-- Window sizing
---------------------------------------------------------------------------
-- "Auto" tracks the screen so the editor is neither a postage stamp on a 4K
-- monitor nor larger than a 1366x768 laptop panel. The fixed presets are for
-- people who would rather pin it.
local SIZES = {
	{ name = "Auto" },
	{ name = "Small",     w = 1000, h = 620  },
	{ name = "Medium",    w = 1280, h = 780  },
	{ name = "Large",     w = 1600, h = 950  },
	{ name = "Maximised", max = true },
}

local function SizeFor( id )
	local spec = SIZES[ id ] or SIZES[ 1 ]

	if spec.max then
		return ScrW() - 40, ScrH() - 40
	end

	if not spec.w then
		-- Auto opens as a utility inspector beside the object, not as a modal
		-- sheet across the centre of the player's view. Larger fixed presets are
		-- still available for users who want the full parameter list at once.
		return math.Clamp( math.floor( ScrW() * 0.46 ), 820, 1500 ),
		       math.Clamp( math.floor( ScrH() * 0.84 ), 560, 1150 )
	end

	-- A preset larger than the screen would put the buttons off-screen.
	return math.min( spec.w, ScrW() - 40 ), math.min( spec.h, ScrH() - 40 )
end

-- Resolution priority, highest first. A narrower rule shadows a broader one.
local SCOPE_RANK = {
	[ AdvMat.SCOPE.ENTITY   ] = 3,
	[ AdvMat.SCOPE.MODEL    ] = 2,
	[ AdvMat.SCOPE.MATERIAL ] = 1,
}

local function ConVarBool( name, fallback )
	local cv = GetConVar( name )
	if not cv then return fallback end
	return cv:GetBool()
end

local PANEL = {}

local function GenOwnsAutoParam( gen, key )
	if key ~= "$translucent" then return false end
	for _, recipe in pairs( istable( gen ) and gen or {} ) do
		if istable( recipe ) and recipe.autotranslucent == true then
			return true
		end
	end
	return false
end

local function RecipeAutoParams( gen )
	if GenOwnsAutoParam( gen, "$translucent" ) then
		return { [ "$translucent" ] = true }
	end
end

---------------------------------------------------------------------------
-- Working copy
---------------------------------------------------------------------------
function PANEL:GetWorking( idx, create )
	local w = self.Working[ idx ]
	if w or not create then return w end

	w = {
		mat    = AdvMat.NormalizeMaterial( self.Materials[ idx + 1 ] or "" ),
		shader = nil,
		params = {},
		gen    = nil,   -- recipes for generated textures, keyed by parameter
	}

	self.Working[ idx ] = w
	return w
end

--- Original key values for a slot, read once and cached.
function PANEL:GetBaseKV( idx )
	if self.BaseKV[ idx ] == nil then
		local kv, shader = AdvMat.Apply.ReadBase( self.Materials[ idx + 1 ] or "" )
		self.BaseKV[ idx ]     = kv or false
		self.BaseShader[ idx ] = shader or "VertexLitGeneric"
	end

	return self.BaseKV[ idx ] or {}
end

function PANEL:GetActiveShader( idx )
	local w = self.Working[ idx ]
	if w and w.shader and w.shader ~= "" then return w.shader end
	self:GetBaseKV( idx )
	return self.BaseShader[ idx ] or "VertexLitGeneric"
end

--- A slot's working copy in the form it will actually be STORED in: keys
--- lowercased and trimmed, values marshalled to .vmt strings, blanks and
--- unusable entries dropped, generator recipes validated by their own kind.
---
--- This exists because the preview and the save used to disagree. SendRule
--- shipped the raw working copy and the server sanitised whatever arrived,
--- while the preview was built from that same raw copy with nothing applied -
--- so anything sanitising removes looked completely right the whole time it
--- was being edited, and vanished the moment Save landed. Which reads, from
--- the outside, as Save resetting the parameter to the material's default.
---
--- The server still sanitises what it receives; it cannot trust a client. But
--- it is now confirming a decision already made here rather than making one
--- nobody has seen the result of.
function PANEL:Canonical( idx )
	local w = self:GetWorking( idx, true )

	local params = AdvMat.SanitizeParams( w.params )
	local gen    = AdvMat.Gen.SanitizeAll( w.gen )

	self:ReportDropped( idx, w, params, gen )

	return params, gen, w
end

--- Say so when canonicalising threw something away.
---
--- Reported once per change rather than once per call, because this runs on
--- every preview push. A parameter quietly disappearing somewhere between the
--- screen and the disk is the exact failure this is here to end, so it is
--- worth interrupting for - while the user is still in a position to do
--- something about it.
function PANEL:ReportDropped( idx, w, params, gen )
	local lost = {}

	for key in pairs( w.params or {} ) do
		local k = string.lower( string.Trim( tostring( key ) ) )
		if params[ k ] == nil then lost[ #lost + 1 ] = k end
	end

	for key in pairs( w.gen or {} ) do
		local k = string.lower( string.Trim( tostring( key ) ) )
		if not gen or gen[ k ] == nil then
			lost[ #lost + 1 ] = k .. " (generated map)"
		end
	end

	table.sort( lost )

	local now = table.concat( lost, ", " )

	self.Dropped = self.Dropped or {}
	if self.Dropped[ idx ] == now then return end

	self.Dropped[ idx ] = now
	if now == "" then return end

	AdvMat.NotifyLocal( AdvMat.L( "notify.cannot_preview", { items = now } ),
		NOTIFY_ERROR, 8 )

	AdvMat.Log( "Slot %d dropped on canonicalising: %s", idx, now )
end

--- The rule table a slot's working copy represents.
function PANEL:RuleFor( idx, scope, key )
	local params, gen, w = self:Canonical( idx )

	return {
		scope  = scope or AdvMat.SCOPE.ENTITY,
		key    = key or self.Entity:EntIndex(),
		index  = idx,
		mat    = ( w.mat ~= "" ) and w.mat or AdvMat.NormalizeMaterial( self.Materials[ idx + 1 ] or "" ),
		shader = w.shader,
		params = params,
		gen    = gen,
	}
end

---------------------------------------------------------------------------
-- Preview
---------------------------------------------------------------------------
function PANEL:QueuePreview()
	-- A dragged slider calls this every frame. timer.Create with a fixed name
	-- restarts the countdown on every call, so the preview only ever landed
	-- once the drag STOPPED - which is exactly the "nothing happens until I let
	-- go" problem.
	--
	-- Throttle instead of debounce: push straight away when enough time has
	-- passed, and leave a timer running so the final position still lands if
	-- the drag ends inside the window.
	local now = SysTime()

	if now >= ( self.NextPreview or 0 ) then
		self.NextPreview = now + PREVIEW_DELAY
		timer.Remove( "AdvMat.Preview" )
		self:PushPreview()
		return
	end

	timer.Create( "AdvMat.Preview", self.NextPreview - now, 1, function()
		if not IsValid( self ) then return end
		self.NextPreview = SysTime() + PREVIEW_DELAY
		self:PushPreview()
	end )
end

function PANEL:PushPreview()
	local live = self.LivePreview:GetChecked()

	if self.WorldMat then
		local w = self.Working[ 0 ]

		if live and w then
			-- Passed even when every parameter has been removed: ApplyWorld
			-- then restores the keys it previously wrote, which is exactly the
			-- preview of "no override".
			self.RefusedFlags = AdvMat.Apply.ApplyWorld(
				self:RuleFor( 0, AdvMat.SCOPE.WORLD, self.WorldMat ) )
		else
			-- Puts the map material back to whatever is actually saved.
			AdvMat.Apply.RefreshWorld()
			self.RefusedFlags = 0
		end

		self:UpdateMarkers()
		if self.Selected then self:UpdateWarning( self.Selected, self:GetActiveShader( 0 ) ) end
		return
	end

	if not IsValid( self.Entity ) then return end

	-- Every slot is staged first and applied once. Refreshing per slot would
	-- re-walk the whole material list for each of up to 32 slots.
	for idx = 0, #self.Materials - 1 do
		local w = self.Working[ idx ]

		if live and not AdvMat.RuleIsEmpty( w ) then
			AdvMat.Client.SetPreview( self.Entity, idx, self:RuleFor( idx ), true )
		else
			AdvMat.Client.ClearPreview( self.Entity, idx, true )
		end
	end

	AdvMat.Apply.Refresh( self.Entity )

	self:UpdateModelPanel()
	self:UpdateMarkers()
end

--- The DModelPanel owns a private clientside entity that the normal apply
--- path never sees, so the working set is pushed onto it directly. It always
--- previews, whether or not the world entity is being changed.
function PANEL:UpdateModelPanel()
	if self.WorldMat then return end

	local mp = self.ModelPanel
	if not IsValid( mp ) then return end

	local e = mp.Entity
	if not IsValid( e ) then return end

	local highlight = self.Highlight:GetChecked() and self.Selected or nil

	for idx = 0, #self.Materials - 1 do
		local w = self.Working[ idx ]

		if idx == highlight then
			e:SetSubMaterial( idx, "!advmat_highlight" )
		elseif not AdvMat.RuleIsEmpty( w ) then
			local _, name = AdvMat.Apply.BuildForRule( self:RuleFor( idx ) )
			if name then e:SetSubMaterial( idx, "!" .. name ) end
		else
			e:SetSubMaterial( idx )
		end
	end
end

---------------------------------------------------------------------------
-- Window sizing
---------------------------------------------------------------------------

--- Resize to the selected preset. Reposition only for an explicit user
--- choice; a resolution change clamps the existing user placement instead of
--- unexpectedly throwing the inspector back over the object.
function PANEL:ApplyWindowSize( reposition )
	local cv = GetConVar( "advmateditor_size" )
	local id = math.Clamp( cv and cv:GetInt() or 1, 1, #SIZES )

	local w, h = SizeFor( id )
	self:SetSize( w, h )
	if AdvMat.WindowUX then
		AdvMat.WindowUX.ClampToScreen( self )
		-- Auto is the non-obstructive inspector preset. Fixed and maximised
		-- choices retain the dimensions their labels promise; the separate
		-- "Move beside target" action can intentionally fit either one beside it.
		if reposition and id == 1 then
			AdvMat.WindowUX.PositionBesideTarget( self, self.Entity, true )
		elseif reposition then
			self:Center()
			AdvMat.WindowUX.ClampToScreen( self )
		end
	elseif reposition then
		self:Center()
	end
end

function PANEL:UpdateWindowUXHint()
	if not IsValid( self.WindowUXHint ) then return end
	local moving = IsValid( self.PlayerMovement ) and self.PlayerMovement:GetChecked()
	self.WindowUXHint:SetText( moving
		and L( "editor.player_controls_hint",
			"WASD to move • hold RMB over visible world to look • release to edit" )
		or L( "window.move_resize_hint",
			"Drag title bar to move • drag lower-right corner to resize" ) )
	self.WindowUXHint:SetTextColor( moving and T.Accent or T.TextDim )
end

---------------------------------------------------------------------------
-- Construction
---------------------------------------------------------------------------
function PANEL:Init()
	self.Working    = {}
	self.HadRule    = {}
	self.RuleScope  = {}
	self.BaseKV     = {}
	self.BaseShader = {}
	self.Materials  = {}
	self.Selected   = nil
	self.WorldMat   = nil  -- set by SetWorldMaterial for map surfaces
	self.ParamViews = {}   -- expanded groups and scroll, kept separately per slot
	self.ParamCats  = {}
	self.ParamViewSlot = nil
	self.ParamViewFiltered = false
	self.ParamViewBuild = 0
	self.ParamPendingScroll = nil
	-- Per durable rule identity. Async texture uploads must never let an older
	-- Save callback publish after a newer Save/clear for the same target.
	self.RuleSendTokens = {}
	self.RuleSendSerial = 0
	self.AdvMatClosing = false
	-- Per durable rule identity: the version (AdvMat.RuleToken) the working copy
	-- is based on, and what this editor last sent there. A save names the
	-- version it was based on, so another player's newer change is reported as
	-- a conflict instead of being silently replaced.
	self.BaseTokens = {}
	self.SentTokens = {}

	self.RejectHookID = "AdvMat.EditorRejected." .. tostring( self )
	hook.Add( "AdvMatRuleRejected", self.RejectHookID, function( info )
		if IsValid( self ) and isfunction( self.OnRuleRejected ) then self:OnRuleRejected( info ) end
	end )

	-- Model Hotloader can become able, or unable, to read files while this is
	-- open: its file access loads a frame after its Lua, and the player can
	-- switch it off. The texture rows gain or lose Import with it.
	self.ImportHookID = "AdvMat.EditorImport." .. tostring( self )
	hook.Add( "AdvMatImportChanged", self.ImportHookID, function()
		if IsValid( self ) and isfunction( self.BuildParamList ) then self:BuildParamList() end
	end )

	self:SetTitle( "Advanced Material Editor" )
	self:SetSizable( true )
	self:SetMinWidth( 820 )
	self:SetMinHeight( 520 )
	self:MakePopup()
	self:ApplyWindowSize( false )

	AdvMat.StyleFrame( self )
	if AdvMat.WindowUX then AdvMat.WindowUX.SetupFrame( self, "vanilla_editor" ) end

	local rowH = AdvMat.RowHeight()

	------------------------------------------------------------- top bar
	local top = vgui.Create( "DPanel", self )
	top:Dock( TOP )
	top:SetTall( rowH + 2 )
	top:DockMargin( 0, 0, 0, 6 )
	top.Paint = AdvMat.NoPaint

	self.ScopeBox = vgui.Create( "DComboBox", top )
	self.ScopeBox:Dock( RIGHT )
	self.ScopeBox:SetWide( AdvMat.FontSize * 17 )
	self.ScopeBox:SetSortItems( false )
	self.ScopeBox:SetTooltip( "Where Save writes the override to." )
	AdvMat.StyleCombo( self.ScopeBox )

	for _, scope in ipairs( { AdvMat.SCOPE.MODEL, AdvMat.SCOPE.ENTITY, AdvMat.SCOPE.MATERIAL } ) do
		self.ScopeBox:AddChoice( AdvMat.SCOPE_NAME[ scope ], scope )
	end

	local cvScope = GetConVar( "advmateditor_scope" )
	local scope   = math.Clamp( cvScope and cvScope:GetInt() or 2, 1, 3 )
	self.ScopeBox:ChooseOptionID( scope == AdvMat.SCOPE.MODEL and 1
		or scope == AdvMat.SCOPE.ENTITY and 2 or 3 )

	self.ScopeBox.OnSelect = function( _, _, _, data )
		RunConsoleCommand( "advmateditor_scope", tostring( data ) )
	end

	local scopeTag = vgui.Create( "DLabel", top )
	scopeTag:Dock( RIGHT )
	scopeTag:SetWide( AdvMat.FontSize * 6 )
	scopeTag:SetText( "Save target:" )
	scopeTag:SetContentAlignment( 6 )
	AdvMat.StyleLabel( scopeTag, "AdvMatText", T.TextDim )

	------------------------------------------------------- window size
	self.SizeBox = vgui.Create( "DComboBox", top )
	self.SizeBox:Dock( RIGHT )
	self.SizeBox:SetWide( AdvMat.FontSize * 8 )
	self.SizeBox:DockMargin( 0, 0, 14, 0 )
	self.SizeBox:SetSortItems( false )
	self.SizeBox:SetTooltip( "Window size. Auto follows your screen resolution." )
	AdvMat.StyleCombo( self.SizeBox )

	for id, spec in ipairs( SIZES ) do
		self.SizeBox:AddChoice( spec.name, id )
	end

	local cvSize = GetConVar( "advmateditor_size" )
	self.SizeBox:ChooseOptionID( math.Clamp( cvSize and cvSize:GetInt() or 1, 1, #SIZES ) )

	self.SizeBox.OnSelect = function( _, _, _, id )
		RunConsoleCommand( "advmateditor_size", tostring( id ) )
		timer.Simple( 0, function()
			if IsValid( self ) then self:ApplyWindowSize( true ) end
		end )
	end

	local sizeTag = vgui.Create( "DLabel", top )
	sizeTag:Dock( RIGHT )
	sizeTag:SetWide( AdvMat.FontSize * 7.5 )
	sizeTag:SetText( L( "editor.window_size", "Window size:" ) )
	sizeTag:SetContentAlignment( 6 )
	AdvMat.StyleLabel( sizeTag, "AdvMatText", T.TextDim )

	-- Created last on purpose. Docking is resolved in the order children were
	-- added and a FILL child claims the whole rect that is left at that moment,
	-- so a label docked FILL first would run underneath all four controls above
	-- rather than stopping short of them.
	self.ModelLabel = vgui.Create( "DLabel", top )
	self.ModelLabel:Dock( FILL )
	AdvMat.StyleLabel( self.ModelLabel, "AdvMatText", T.Text )

	---------------------------------------------------- window / player bar
	-- Keep navigation and window-management controls separate from the action
	-- bar so translated labels do not crowd Save at the narrower inspector size.
	local windowBar = vgui.Create( "DPanel", self )
	windowBar:Dock( TOP )
	windowBar:SetTall( rowH + 4 )
	windowBar:DockMargin( 0, 0, 0, 6 )
	windowBar.Paint = AdvMat.Fill( T.Panel )
	self.WindowUXBar = windowBar

	self.MoveBeside = vgui.Create( "DButton", windowBar )
	self.MoveBeside:Dock( RIGHT )
	self.MoveBeside:SetWide( math.floor( AdvMat.FontSize * 12.5 ) )
	self.MoveBeside:SetText( L( "window.move_beside", "Move beside target" ) )
	self.MoveBeside:SetTooltip( L( "window.move_beside_tip",
		"Move this window beside the object you are editing." ) )
	AdvMat.StyleButton( self.MoveBeside )
	self.MoveBeside.DoClick = function()
		if AdvMat.WindowUX then
			AdvMat.WindowUX.PositionBesideTarget( self, self.Entity, true )
		end
	end

	self.PlayerMovement = vgui.Create( "DCheckBoxLabel", windowBar )
	self.PlayerMovement:Dock( LEFT )
	self.PlayerMovement:DockMargin( 8, 3, 12, 3 )
	AdvMat.StyleCheck( self.PlayerMovement,
		L( "editor.allow_movement", "Allow player movement while editing" ) )
	self.PlayerMovement:SetValue( ConVarBool( "advmateditor_playercontrols", false ) )
	self.PlayerMovement:SetConVar( "advmateditor_playercontrols" )
	self.PlayerMovement:SetTooltip( L( "editor.allow_movement_tip",
		"Movement keys control your player while the editor remains open. " ..
		"Hold RMB over the visible world to look around; release it to edit." ) )
	self.PlayerMovement.OnChange = function( _, enabled )
		self:UpdateWindowUXHint()
		timer.Simple( 0, function()
			if IsValid( self ) and AdvMat.WindowUX then
				AdvMat.WindowUX.ApplyPlayerControls( self, enabled == true )
			end
		end )
	end

	self.WindowUXHint = vgui.Create( "DLabel", windowBar )
	self.WindowUXHint:Dock( FILL )
	self.WindowUXHint:SetContentAlignment( 4 )
	self.WindowUXHint:SetTooltip( L( "editor.allow_movement_tip", "" ) )
	AdvMat.StyleLabel( self.WindowUXHint, "AdvMatSmall", T.TextDim )
	self:UpdateWindowUXHint()

	----------------------------------------------------------- bottom bars
	-- Actions and preview toggles used to share one horizontal strip. At the
	-- 820 px minimum width a translated pair of check boxes could consume the
	-- space reserved for the seven action buttons; high-DPI fonts made that
	-- collision even easier to reach. Keep actions on the bottom-most row and
	-- give stateful preview controls a dedicated row immediately above it.
	local bottom = vgui.Create( "DPanel", self )
	bottom:Dock( BOTTOM )
	bottom:SetTall( rowH + 6 )
	bottom:DockMargin( 0, 3, 0, 0 )
	bottom.Paint = AdvMat.NoPaint
	self.ActionBar = bottom

	local previewBottom = vgui.Create( "DPanel", self )
	previewBottom:Dock( BOTTOM )
	previewBottom:SetTall( rowH + 4 )
	previewBottom:DockMargin( 0, 6, 0, 0 )
	previewBottom.Paint = AdvMat.Fill( T.Panel )
	self.PreviewBar = previewBottom

	self.LivePreview = vgui.Create( "DCheckBoxLabel", previewBottom )
	self.LivePreview:Dock( LEFT )
	self.LivePreview:DockMargin( 8, 3, 14, 3 )
	AdvMat.StyleCheck( self.LivePreview, "Live preview" )
	self.LivePreview:SetValue( ConVarBool( "advmateditor_livepreview", true ) )
	self.LivePreview:SetConVar( "advmateditor_livepreview" )
	self.LivePreview:SetTooltip( "Show unsaved changes on the real prop, for you only." )
	self.LivePreview.OnChange = function() self:QueuePreview() end

	self.Highlight = vgui.Create( "DCheckBoxLabel", previewBottom )
	self.Highlight:Dock( LEFT )
	self.Highlight:DockMargin( 0, 3, 14, 3 )
	AdvMat.StyleCheck( self.Highlight, "Highlight selected sub-material" )
	self.Highlight:SetTooltip(
		"Paints the selected slot magenta in the preview.\n" ..
		"Use this to confirm you are editing the part you think you are." )
	self.Highlight.OnChange = function() self:UpdateModelPanel() end

	-- Preferred button widths are given in characters. The action bar scales
	-- them down proportionally only when its complete translated toolbar would
	-- exceed the available width; buttons never overlap, and their full action
	-- remains available in the tooltip at that compact breakpoint.
	local actionButtons = {}
	local function AddButton( text, chars, tip, fn, danger )
		local b = vgui.Create( "DButton", bottom )
		b.AdvMatPreferredWide = math.floor( AdvMat.FontSize * chars )
		b:SetText( text )
		b:SetTooltip( tip or text )
		b.DoClick = fn
		AdvMat.StyleButton( b, danger )
		actionButtons[ #actionButtons + 1 ] = b
		return b
	end

	AddButton( "Close", 4.5, nil, function() self:Close() end )

	AddButton( "Save", 6, "Store these settings on the server so they come back every map load.",
		function() self:SaveAll() end )

	AddButton( "Undo", 5, "Throw away every unsaved change and go back to what is saved.",
		function()
			self:ReloadWorking()
			self:QueuePreview()
			self:BuildParamList()
		end )

	AddButton( "Reset to Default", 9,
		"Put the selected sub-material back to how the model shipped, deleting every " ..
		"saved override on it in all three scopes.",
		function() self:DeleteSelected() end, true )

	AddButton( "Presets", 5, "Save, load or copy a set of parameters.",
		function() self:OpenPresetMenu() end )

	AddButton( "Trace", 4.5,
		"Record the preview, save handoff, competing rule scopes, engine slot and live material values. " ..
		"Click once before reproducing a problem and again afterwards; the trace is written under data/advmat.",
		function()
			if AdvMat.DebugTraceActive then
				if AdvMat.StopDebugTrace then AdvMat.StopDebugTrace() end
			elseif AdvMat.StartDebugTrace then
				AdvMat.StartDebugTrace()
			else
				AdvMat.NotifyLocal( "The material trace module is not loaded.", NOTIFY_ERROR, 5 )
			end
		end )

	AddButton( "Copy .vmt", 6,
		"Show this material as .vmt text you can copy, and write out any textures " ..
		"you generated or painted so they can be shipped with the model.",
		function() self:OpenVMTExport() end )

	bottom.PerformLayout = function( _, wide, tall )
		local gap = 4
		local available = math.max( 1, wide - gap * math.max( 0, #actionButtons - 1 ) )
		local preferred = 0
		for _, button in ipairs( actionButtons ) do
			preferred = preferred + button.AdvMatPreferredWide
		end
		local compact = preferred > available
		local scale = preferred > 0 and math.min( 1, available / preferred ) or 1
		local right = wide
		for index, button in ipairs( actionButtons ) do
			local buttonWide
			if compact and index == #actionButtons then
				buttonWide = math.max( 1, right )
			else
				buttonWide = math.max( 1,
					math.floor( button.AdvMatPreferredWide * scale ) )
			end
			right = right - buttonWide
			button:SetPos( math.max( 0, right ), 0 )
			button:SetSize( buttonWide, tall )
			right = right - gap
		end
	end

	--------------------------------------------------------------- panes
	local divider = vgui.Create( "DHorizontalDivider", self )
	divider:Dock( FILL )
	-- A compact preview rail leaves enough room for controls when Auto opens as
	-- a side inspector on 1080p displays. The divider remains user-adjustable.
	divider:SetLeftWidth( math.Clamp( math.floor( self:GetWide() * 0.28 ), 260, 430 ) )
	divider:SetLeftMin( 260 )
	divider:SetRightMin( 420 )
	divider:SetDividerWidth( 6 )
	self.Divider = divider

	local left = vgui.Create( "DPanel", divider )
	left.Paint = AdvMat.NoPaint
	divider:SetLeft( left )

	self.ModelPanel = vgui.Create( "DModelPanel", left )
	self.ModelPanel:Dock( TOP )
	self.ModelPanel:SetTall( math.max( 220, math.floor( ScrH() * 0.22 ) ) )
	self.ModelPanel:SetFOV( 40 )
	self.ModelPanel:SetAnimated( false )
	self.ModelPanel.LayoutEntity = function( panel, ent )
		AdvMat.AttachMMDPreview( ent ) -- Asset decoding may finish after the editor opens.
		ent:SetAngles( Angle( 0, RealTime() * 20 % 360, 0 ) )
		if ent.MMDHLEditorPreview then
			-- The empty carrier's bounds do not include hair and accessories.
			-- Fit the visible MMD mesh after layout, accounting for panel aspect.
			local mn, mx = ent:GetRenderBounds()
			local center = ent:LocalToWorld( ( mn + mx ) * 0.5 )
			local half = math.rad( panel:GetFOV() * 0.5 )
			half = math.min( half, math.atan( math.tan( half ) * panel:GetTall() / math.max( panel:GetWide(), 1 ) ) )
			local distance = ( mx - mn ):Length() * 0.53 / math.max( math.sin( half ), 0.05 )
			panel:SetLookAt( center )
			panel:SetCamPos( center + Vector( -1, -0.2, 0.05 ):GetNormalized() * distance )
		end
	end

	-- World mode has no model to spin, so the material itself is shown instead.
	self.MatPreview = vgui.Create( "DPanel", left )
	self.MatPreview:Dock( TOP )
	self.MatPreview:SetTall( math.max( 220, math.floor( ScrH() * 0.22 ) ) )
	self.MatPreview:SetVisible( false )
	self.MatPreview.Paint = function( pnl, w, h )
		surface.SetDrawColor( T.Panel.r, T.Panel.g, T.Panel.b, 255 )
		surface.DrawRect( 0, 0, w, h )

		local working = self.Working[ 0 ]
		local base    = ( working and working.params[ "$basetexture" ] )
			or ( self:GetBaseKV( 0 ) or {} )[ "$basetexture" ]

		if not base then return end

		-- Drawn through an UnlitGeneric stand-in: a map material is
		-- LightmappedGeneric and needs lightmap data that a 2D draw has not got.
		local mat = AdvMat.PreviewMaterial( base )
		if not mat then return end

		local size = math.min( w, h ) - 16
		surface.SetDrawColor( 255, 255, 255, 255 )
		surface.SetMaterial( mat )
		surface.DrawTexturedRect( ( w - size ) * 0.5, ( h - size ) * 0.5, size, size )
	end

	local listLbl = vgui.Create( "DLabel", left )
	listLbl:Dock( TOP )
	listLbl:SetTall( rowH + 4 )
	listLbl:DockMargin( 0, 6, 0, 2 )
	listLbl:SetText( "Sub-materials" )
	AdvMat.StyleLabel( listLbl, "AdvMatTitle", T.Text )

	self.MatList = vgui.Create( "DListView", left )
	self.MatList:Dock( FILL )
	self.MatList:SetMultiSelect( false )
	self.MatList:AddColumn( "#" ):SetFixedWidth( AdvMat.FontSize * 2 )
	self.MatList:AddColumn( "Material" )
	self.MatList:AddColumn( "" ):SetFixedWidth( AdvMat.FontSize + 4 )
	AdvMat.StyleListView( self.MatList )

	self.MatList.OnRowSelected = function( _, _, line )
		self.Selected = line.AdvMatIndex
		self:BuildParamList()
		self:UpdateModelPanel()
	end

	--------------------------------------------------------------- right
	local right = vgui.Create( "DPanel", divider )
	right.Paint = AdvMat.NoPaint
	divider:SetRight( right )

	local head = vgui.Create( "DPanel", right )
	head:Dock( TOP )
	head:SetTall( rowH * 4 + 16 )
	head:DockMargin( 0, 0, 0, 4 )
	head.Paint = AdvMat.NoPaint

	self.MatLabel = vgui.Create( "DLabel", head )
	self.MatLabel:Dock( TOP )
	self.MatLabel:SetTall( rowH + 4 )
	self.MatLabel:SetText( "Select a sub-material on the left" )
	AdvMat.StyleLabel( self.MatLabel, "AdvMatTitle", T.Text )

	self.Warning = vgui.Create( "DLabel", head )
	self.Warning:Dock( TOP )
	self.Warning:SetTall( rowH )
	self.Warning:SetText( "" )
	AdvMat.StyleLabel( self.Warning, "AdvMatSmall", T.Warn )

	local shaderRow = vgui.Create( "DPanel", head )
	shaderRow:Dock( TOP )
	shaderRow:SetTall( rowH + 2 )
	shaderRow:DockPadding( 0, 2, 0, 2 )
	shaderRow.Paint = AdvMat.NoPaint

	local shaderTag = vgui.Create( "DLabel", shaderRow )
	shaderTag:Dock( LEFT )
	shaderTag:SetWide( AdvMat.FontSize * 4 )
	shaderTag:SetText( "Shader" )
	AdvMat.StyleLabel( shaderTag, "AdvMatText", T.TextDim )

	self.ShaderBox = vgui.Create( "DComboBox", shaderRow )
	self.ShaderBox:Dock( LEFT )
	self.ShaderBox:SetWide( AdvMat.FontSize * 13 )
	self.ShaderBox:SetTooltip( "Changing this rebuilds the material with a different shader." )
	AdvMat.StyleCombo( self.ShaderBox )
	self.ShaderBox.OnSelect = function( _, _, value )
		if self.SettingShader or not self.Selected then return end
		local w = self:GetWorking( self.Selected, true )
		w.shader = ( value ~= self.BaseShader[ self.Selected ] ) and value or nil
		self:BuildParamList()
		self:QueuePreview()
	end

	-- Search and the potentially long translated Show-all label get their own
	-- row. Keeping them beside Shader made the search box almost disappear in
	-- the narrower, non-obstructive Auto layout.
	local filterRow = vgui.Create( "DPanel", head )
	filterRow:Dock( FILL )
	filterRow:DockPadding( 0, 2, 0, 2 )
	filterRow.Paint = AdvMat.NoPaint

	self.ShowAll = vgui.Create( "DCheckBoxLabel", filterRow )
	self.ShowAll:Dock( RIGHT )
	self.ShowAll:DockMargin( 0, 3, 0, 3 )
	AdvMat.StyleCheck( self.ShowAll, "Show every supported parameter" )
	self.ShowAll:SetValue( ConVarBool( "advmateditor_showall", true ) )
	self.ShowAll:SetConVar( "advmateditor_showall" )
	self.ShowAll.OnChange = function() self:BuildParamList() end

	self.Filter = vgui.Create( "DTextEntry", filterRow )
	self.Filter:Dock( FILL )
	self.Filter:DockMargin( 6, 0, 6, 0 )
	self.Filter:SetPlaceholderText( "Search parameters by name or description..." )
	self.Filter:SetTooltip( "Type to narrow the list below. Matches parameter names and their descriptions." )
	self.Filter:SetUpdateOnType( true )
	self.Filter.OnValueChange = function() self:BuildParamList() end
	AdvMat.StyleEntry( self.Filter )

	self.Scroll = vgui.Create( "DScrollPanel", right )
	self.Scroll:Dock( FILL )
	self.Scroll.Paint = AdvMat.Fill( T.Panel )
end

---------------------------------------------------------------------------
-- Target entity
---------------------------------------------------------------------------
function PANEL:SetEntity( ent )
	if not IsValid( ent ) then self:Close() return end

	self.Entity    = ent
	self.Materials = ent:GetMaterials() or {}

	-- Display the entire inventory. Application limits belong to the entity's
	-- material provider, not the list; GMHLVK supplies slots beyond Source's 32.
	self.ModelLabel:SetText( string.format( "%s    (%d sub-material%s)",
		ent:GetModel() or "?",
		#self.Materials,
		#self.Materials == 1 and "" or "s" ) )

	self.ModelPanel:SetModel( ent:GetModel() or "models/error.mdl" )

	local pe = self.ModelPanel.Entity
	AdvMat.AttachMMDPreview( pe )
	if IsValid( pe ) then
		local mn, mx = pe:GetRenderBounds()
		local size   = math.max( mx.x - mn.x, mx.y - mn.y, mx.z - mn.z, 1 )
		self.ModelPanel:SetCamPos( Vector( size, size, size * 0.6 ) )
		self.ModelPanel:SetLookAt( ( mn + mx ) * 0.5 )
	end

	self:ReloadWorking()
	self:RefreshMaterialList()

	if #self.Materials > 0 then self.MatList:SelectFirstItem() end

	self:UpdateModelPanel()
	if AdvMat.WindowUX then
		-- The target is only known after the DFrame has been constructed. Saved
		-- geometry wins; a first-time window is placed clear of the target.
		AdvMat.WindowUX.PositionBesideTarget( self, ent, false )
	end
end

--- Point the editor at a map surface rather than an entity. Brush geometry
--- has no sub-material slots, so there is exactly one thing to edit.
function PANEL:SetWorldMaterial( path )
	path = AdvMat.NormalizeMaterial( path or "" )
	if path == "" then self:Close() return end

	self.WorldMat  = path
	self.Entity    = nil
	self.Materials = { path }

	self.ModelLabel:SetText( "Map surface    " .. path )

	self.ModelPanel:SetVisible( false )
	self.MatPreview:SetVisible( true )

	-- Neither control means anything without an entity.
	self.Highlight:SetVisible( false )
	self.ScopeBox:SetEnabled( false )
	self.ScopeBox:SetValue( AdvMat.SCOPE_NAME[ AdvMat.SCOPE.WORLD ] )

	self:ReloadWorking()
	self:RefreshMaterialList()
	self.MatList:SelectFirstItem()
	if AdvMat.WindowUX then
		AdvMat.WindowUX.PositionBesideTarget( self, nil, false )
	end
end

--- Remember which version of each rule the working copy is based on, for every
--- identity a Save could write to: entity, model and material scope per slot,
--- or the one map surface.
function PANEL:CaptureBaseTokens()
	local C = AdvMat.Client
	self.BaseTokens = {}

	if self.WorldMat then
		local id = AdvMat.RuleID( AdvMat.SCOPE.WORLD, self.WorldMat )
		self.BaseTokens[ id ] = AdvMat.RuleToken( C.Rules[ id ] )
		return
	end

	if not IsValid( self.Entity ) then return end

	local ei  = self.Entity:EntIndex()
	local mdl = self.Entity:GetModel()

	for i = 1, #self.Materials do
		local idx   = i - 1
		local entID = AdvMat.RuleID( AdvMat.SCOPE.ENTITY, ei, idx )
		local mdlID = AdvMat.RuleID( AdvMat.SCOPE.MODEL, mdl, idx )
		local matID = AdvMat.RuleID( AdvMat.SCOPE.MATERIAL, self.Materials[ i ] or "" )

		local set = C.EntRules and C.EntRules[ ei ]
		self.BaseTokens[ entID ] = AdvMat.RuleToken( set and set[ idx ] )
		self.BaseTokens[ mdlID ] = AdvMat.RuleToken( C.Rules and C.Rules[ mdlID ] )
		self.BaseTokens[ matID ] = AdvMat.RuleToken( C.Rules and C.Rules[ matID ] )
	end
end

--- The server refused one of this editor's saves. For a conflict, adopt the
--- version that is stored now, so pressing Save again deliberately replaces
--- it; any other refusal has already been explained by the server's notice.
function PANEL:OnRuleRejected( info )
	if not istable( info ) then return end

	local id   = AdvMat.RuleID( tonumber( info.scope ) or AdvMat.SCOPE.MODEL, info.key, info.index )
	local sent = self.SentTokens and self.SentTokens[ id ]
	if not sent or sent.token ~= info.token then return end

	self.SentTokens[ id ] = nil
	self.BaseTokens[ id ] = isstring( info.current ) and info.current or ""

	if info.conflict then
		AdvMat.NotifyLocal( AdvMat.L( "notify.save_conflict", { slot = sent.idx } ), NOTIFY_ERROR, 10 )
		surface.PlaySound( "buttons/button10.wav" )
	end
end

--- Pull the server's current rules into the working copy.
function PANEL:ReloadWorking()
	if IsValid( self.Entity ) then AdvMat.Client.ClearPreview( self.Entity ) end

	self.Working   = {}
	self.HadRule   = {}
	self.RuleScope = {}
	self:CaptureBaseTokens()

	if self.WorldMat then
		local rule = AdvMat.Client.Rules[ AdvMat.RuleID( AdvMat.SCOPE.WORLD, self.WorldMat ) ]

		if rule and not AdvMat.RuleIsEmpty( rule ) then
			self.Working[ 0 ] = {
				mat    = self.WorldMat,
				shader = rule.shader,
				params = table.Copy( rule.params ),
				gen    = rule.gen and table.Copy( rule.gen ) or nil,
				_autoParams = RecipeAutoParams( rule.gen ),
			}
			self.HadRule[ 0 ]   = true
			self.RuleScope[ 0 ] = AdvMat.SCOPE.WORLD
		end

		return
	end

	for i = 1, #self.Materials do
		local idx  = i - 1
		local rule = AdvMat.Client.Resolve( self.Entity, idx, self.Materials[ i ] )

		if rule and not AdvMat.RuleIsEmpty( rule ) then
			self.Working[ idx ] = {
				mat    = ( rule.mat and rule.mat ~= "" ) and rule.mat
				         or AdvMat.NormalizeMaterial( self.Materials[ i ] ),
				shader = rule.shader,
				params = table.Copy( rule.params ),
				gen    = rule.gen and table.Copy( rule.gen ) or nil,
				_autoParams = RecipeAutoParams( rule.gen ),
			}
			self.HadRule[ idx ]   = true
			self.RuleScope[ idx ] = rule.scope
		end
	end
end

---------------------------------------------------------------------------
-- Sub-material list
---------------------------------------------------------------------------
--- Repaint the "has an override" markers without rebuilding the list.
--- Rebuilding it would re-run SelectItem, which fires OnRowSelected, which
--- rebuilds the whole parameter pane - destroying the very slider being
--- dragged.
function PANEL:UpdateMarkers()
	for _, line in ipairs( self.MatList:GetLines() ) do
		local w = self.Working[ line.AdvMatIndex ]
		line:SetColumnText( 3, AdvMat.RuleIsEmpty( w ) and "" or "*" )
	end
end

function PANEL:RefreshMaterialList()
	local keep = self.Selected
	self.MatList:Clear()

	for i = 1, #self.Materials do
		local idx  = i - 1
		local w    = self.Working[ idx ]
		local mark = AdvMat.RuleIsEmpty( w ) and "" or "*"

		local label = AdvMat.NormalizeMaterial( self.Materials[ i ] )
		local inventory = IsValid( self.Entity ) and mmdhl and mmdhl.GetMaterials and mmdhl.GetMaterials( self.Entity )
		if inventory and inventory[ i ] then label = inventory[ i ].name end
		local line = self.MatList:AddLine( idx, label, mark )
		line:SetTooltip( self.Materials[ i ] )
		line.AdvMatIndex = idx
		line:SetTooltip( AdvMat.L( "editor.slot_tip", {
			material = self.Materials[ i ], slot = idx,
		} ) )
		AdvMat.StyleListLine( line, i )

		if keep == idx then self.MatList:SelectItem( line ) end
	end
end

---------------------------------------------------------------------------
-- Parameter list
---------------------------------------------------------------------------
function PANEL:MakeContext( idx )
	local editor = self
	local baseKV = self:GetBaseKV( idx )
	local baseShader = self:GetActiveShader( idx )

	-- A row can outlive the panel that created it while a texture dialog is
	-- open.  Never dispatch a delayed callback into a removed Derma panel: GMod
	-- strips its registered methods, which turns editor:GetWorking into a nil
	-- method call instead of a useful "the host was closed" result.
	local function Host()
		if not IsValid( editor ) or not isfunction( editor.GetWorking ) then return nil end
		return editor
	end

	-- Identity is captured with the context.  Values in the working rule may
	-- continue to change, but a dialog opened for this row must never drift to a
	-- later tool trace, entity, material path or bodygroup configuration.
	local targetModel = IsValid( self.Entity )
		and AdvMat.NormalizeModel( self.Entity:GetModel() or "" ) or nil
	local targetPath = AdvMat.NormalizeMaterial( self.Materials[ idx + 1 ] or "" )
	local targetMask = IsValid( self.Entity )
		and AdvMat.Mesh and AdvMat.Mesh.BodyMask( self.Entity ) or 0

	local function ForgetAutoOwnership( w, key )
		if w._autoParams then
			w._autoParams[ key ] = nil
			if table.IsEmpty( w._autoParams ) then w._autoParams = nil end
		end
		if key == "$translucent" then
			for _, recipe in pairs( istable( w.gen ) and w.gen or {} ) do
				if istable( recipe ) then recipe.autotranslucent = nil end
			end
		end
	end

	return {
		--- The current value, as a VMT literal string. Exactly ONE return
		--- value: returning the override flags from here as well made
		--- `tonumber( ctx.Get( k ) )` silently pass a boolean as tonumber's
		--- base argument. The flags live on State instead.
		Get = function( key )
			local host = Host()
			local w = host and host.Working[ idx ]
			if w and w.params[ key ] ~= nil then return w.params[ key ] end
			if baseKV[ key ] ~= nil then return baseKV[ key ] end

			local def = AdvMat.GetParamDef(
				host and host:GetActiveShader( idx ) or baseShader, key )
			return ( def and def.default ) or ""
		end,

		--- isOverridden, isInherited
		State = function( key )
			local host      = Host()
			local w         = host and host.Working[ idx ]
			local inherited = baseKV[ key ] ~= nil
			return ( w and w.params[ key ] ~= nil ) or false, inherited
		end,

		Set = function( key, value )
			local host = Host()
			if not host then return false end

			local w = host:GetWorking( idx, true )
			-- A direct row edit takes ownership away from a companion value
			-- which a generated texture previously installed automatically.
			ForgetAutoOwnership( w, key )
			w.params[ key ] = value
			host:QueuePreview()
			return true
		end,

		BaseTexture = function()
			local host = Host()
			local w = host and host.Working[ idx ]
			return ( w and w.params[ "$basetexture" ] )
				or baseKV[ "$basetexture" ]
				or targetPath
		end,

		--- Which shader the help text should describe the parameter for.
		Shader = function()
			local host = Host()
			return host and host:GetActiveShader( idx ) or baseShader
		end,

		--- Generation recipes live alongside the parameters rather than inside
		--- them, because a parameter's value is a VMT string and a recipe is a
		--- table of settings.
		GetGen = function( key )
			local host = Host()
			local w = host and host.Working[ idx ]
			return w and w.gen and w.gen[ key ] or nil
		end,

		SetGen = function( key, recipe )
			local host = Host()
			if not host then return false end

			local w = host:GetWorking( idx, true )

			w.gen = w.gen or {}
			w.gen[ key ] = recipe
			if table.IsEmpty( w.gen ) then w.gen = nil end

			host:QueuePreview()
			host:BuildParamList()
			return true
		end,

		--- Everything the texture editor and the generators need to know about
		--- where this parameter lives: which model and sub-material, so UV
		--- selection can resolve, and the original key values, so a preview
		--- looks like the real material rather than a flat unlit swatch.
		Target = function()
			local host = Host()
			local w = host and host.Working[ idx ]

			-- Transparency flags may have been changed in the working copy. The
			-- texture editor needs the effective value, not only the original
			-- VMT, when deciding whether the source alpha is a hole or a mask.
			local function Effective( key )
				if w and w.params and w.params[ key ] ~= nil then return w.params[ key ] end
				return baseKV[ key ]
			end

			return {
				model   = targetModel,
				slot    = idx,
				matpath = targetPath,

				-- The parts the entity is actually wearing. A dialog that
				-- resolves a UV selection has to see the same mesh the user is
				-- looking at, and for a model with bodygroups that is not the
				-- one every group reads back as nought.
				mask    = targetMask,
				shader  = host and host:GetActiveShader( idx ) or baseShader,
				basekv  = baseKV,
				src     = baseKV[ "$basetexture" ],
				showsalpha = tobool( Effective( "$translucent" ) )
					or tobool( Effective( "$alphatest" ) ),
			}
		end,

		--- Apply a batch of companion parameters at once. The generators use
		--- this to switch on the things their map needs in order to be read at
		--- all, which is otherwise the commonest reason a generated map appears
		--- to do nothing.
		SetParams = function( set, unset )
			local host = Host()
			if not host then return false end

			local w = host:GetWorking( idx, true )
			local n = 0

			for k, v in pairs( set or {} ) do
				ForgetAutoOwnership( w, k )
				if w.params[ k ] ~= v then
					w.params[ k ] = v
					n = n + 1
				end
			end

			for _, k in ipairs( unset or {} ) do
				ForgetAutoOwnership( w, k )
				if w.params[ k ] ~= nil or baseKV[ k ] ~= nil then
					-- An empty string is how a parameter is removed rather than
					-- overridden, and it survives the round trip to the server.
					w.params[ k ] = nil
					n = n + 1
				end
			end
			if w._autoParams and table.IsEmpty( w._autoParams ) then
				w._autoParams = nil
			end

			if n > 0 then
				host:QueuePreview()
				host:BuildParamList()

				AdvMat.NotifyLocal( "Set " .. n .. " related parameter(s).",
					NOTIFY_GENERIC, 4 )
			end

			return true
		end,

		--- Install or retract a companion material flag owned by a generated
		--- texture. This is deliberately separate from SetParams: ordinary row
		--- edits must never be removed when an erase step is later disabled.
		SetAutoParam = function( key, value, wanted, ownerRecipe )
			local host = Host()
			if not host then return false end

			local w = host:GetWorking( idx, true )
			local ownedBefore = ( w._autoParams and w._autoParams[ key ] == true )
				or GenOwnsAutoParam( w.gen, key )
			local effective = w.params[ key ]
			if effective == nil then effective = baseKV[ key ] end

			-- Ownership belongs to the generated parameter, not to the material as
			-- a whole. Several edited maps may need the same companion flag. Stamp
			-- this recipe only when the editor actually had to supply the flag, then
			-- derive the material-level bit from every recipe which is still present.
			if istable( ownerRecipe ) then
				if wanted and ( ownedBefore or not tobool( effective ) ) then
					ownerRecipe.autotranslucent = true
				elseif not wanted then
					ownerRecipe.autotranslucent = nil
				end
			end

			local owned = GenOwnsAutoParam( w.gen, key )
			local changed = false

			if owned then
				w._autoParams = w._autoParams or {}
				w._autoParams[ key ] = true
				if w.params[ key ] ~= value then
					w.params[ key ] = value
					changed = true
				end
			elseif ownedBefore then
				-- nil reveals the original VMT value (including an explicit 0).
				w.params[ key ] = nil
				if w._autoParams then
					w._autoParams[ key ] = nil
					if table.IsEmpty( w._autoParams ) then w._autoParams = nil end
				end
				changed = true
			end

			if changed then
				host:QueuePreview()
				host:BuildParamList()
			end
			return owned
		end,
	}
end

function PANEL:UpdateWarning( idx, shader )
	local msgs = {}

	if self.WorldMat then
		msgs[ #msgs + 1 ] = AdvMat.L( "editor.world_in_place" )

		if ( self.RefusedFlags or 0 ) > 0 then
			msgs[ #msgs + 1 ] = AdvMat.L( "editor.world_flags", {
				count = self.RefusedFlags,
			} )
		end
	else
		-- Fold the spelling first: a .vmt saying "VertexlitGeneric" is the same
		-- shader as "VertexLitGeneric" and must not be warned about.
		local canon = AdvMat.CanonicalShader( shader )

		if BRUSH_ONLY[ canon ] then
			msgs[ #msgs + 1 ] = AdvMat.L( "editor.brush_shader", { shader = canon } )
		elseif not MODEL_SHADERS[ canon ] then
			msgs[ #msgs + 1 ] = AdvMat.L( "editor.not_model_shader", { shader = canon } )
		end
	end

	if not AdvMat.VMTExists( self.Materials[ idx + 1 ] or "" ) then
		msgs[ #msgs + 1 ] = AdvMat.L( "editor.missing_vmt" )
	end

	self.Warning:SetText( table.concat( msgs, "  " ) )
end

--- Preserve the controls that are about to be destroyed by BuildParamList.
--- Search results deliberately do not replace the normal layout: searching
--- opens every matching group temporarily, and clearing the query should take
--- the user back to the layout they had before searching.
function PANEL:RememberParamView()
	local idx = self.ParamViewSlot
	if idx == nil or self.ParamViewFiltered then return end

	local state = self.ParamViews[ idx ] or { groups = {} }
	state.groups = state.groups or {}

	for group, cat in pairs( self.ParamCats or {} ) do
		if IsValid( cat ) and isfunction( cat.GetExpanded ) then
			state.groups[ group ] = cat:GetExpanded() == true
		end
	end

	local pending = self.ParamPendingScroll
	local bar = IsValid( self.Scroll ) and self.Scroll:GetVBar() or nil
	if pending and pending.slot == idx then
		-- A texture adoption can rebuild more than once before timer.Simple( 0 )
		-- gets a chance to restore the bar. Keep carrying the intended position
		-- instead of recording the intermediate zero from the fresh panel.
		state.scroll = pending.scroll
	elseif IsValid( bar ) and isfunction( bar.GetScroll ) then
		state.scroll = math.max( 0, tonumber( bar:GetScroll() ) or 0 )
	end

	self.ParamViews[ idx ] = state
end

--- The scrollbar cannot be restored until the new categories have completed
--- their first layout. The build token prevents an older deferred restore
--- from moving a list that has already been rebuilt for another material.
function PANEL:RestoreParamScroll( idx, scroll, build )
	if scroll == nil then return end
	scroll = math.max( 0, tonumber( scroll ) or 0 )
	self.ParamPendingScroll = { slot = idx, scroll = scroll, build = build }

	timer.Simple( 0, function()
		if not IsValid( self ) or self.ParamViewBuild ~= build
			or self.ParamViewSlot ~= idx or self.ParamViewFiltered then return end

		self.Scroll:InvalidateLayout( true )
		local bar = self.Scroll:GetVBar()
		if IsValid( bar ) and isfunction( bar.SetScroll ) then
			bar:SetScroll( scroll )
		end

		local pending = self.ParamPendingScroll
		if pending and pending.build == build then
			self.ParamPendingScroll = nil
		end
	end )
end

function PANEL:BuildParamList()
	AdvMat.CloseParamHelp()
	self:RememberParamView()
	self.ParamPendingScroll = nil

	self.ParamViewBuild = ( self.ParamViewBuild or 0 ) + 1
	local build = self.ParamViewBuild
	self.ParamCats = {}
	self.ParamViewSlot = nil
	self.ParamViewFiltered = false
	self.Scroll:Clear()

	local idx = self.Selected
	if not idx then return end

	local matPath = AdvMat.NormalizeMaterial( self.Materials[ idx + 1 ] or "" )
	local shader  = self:GetActiveShader( idx )
	local baseKV  = self:GetBaseKV( idx )

	self.MatLabel:SetText( matPath )
	self:UpdateWarning( idx, shader )

	--------------------------------------------------------- shader box
	self.SettingShader = true
	self.ShaderBox:Clear()

	local shaderList = AdvMat.GetShaderList()
	shader = AdvMat.CanonicalShader( shader )

	if not table.HasValue( shaderList, shader ) then
		table.insert( shaderList, 1, shader )
	end
	for _, name in ipairs( shaderList ) do self.ShaderBox:AddChoice( name ) end
	self.ShaderBox:SetValue( shader )
	self.SettingShader = false

	-- A material's shader is fixed once it exists, and a map surface is drawing
	-- its material directly, so there is no replacement to swap in. Offering
	-- the control there would just be a lie.
	self.ShaderBox:SetEnabled( not self.WorldMat )
	self.ShaderBox:SetTooltip( self.WorldMat
		and AdvMat.L( "editor.map_shader_locked" )
		or  "Changing this rebuilds the material with a different shader." )

	--------------------------------------------------------------- rows
	local ctx     = self:MakeContext( idx )
	local showAll = self.ShowAll:GetChecked()
	local filter  = string.lower( string.Trim( self.Filter:GetValue() or "" ) )
	local working = self.Working[ idx ]
	local savedView = self.ParamViews[ idx ]

	self.ParamViewSlot = idx
	self.ParamViewFiltered = filter ~= ""

	local buckets, order = {}, {}

	local function Bucket( group )
		if not buckets[ group ] then
			buckets[ group ] = {}
			order[ #order + 1 ] = group
		end
		return buckets[ group ]
	end

	local seen = {}

	for _, def in ipairs( AdvMat.GetShaderParams( shader ) ) do
		seen[ def.name ] = true

		local isSet = ( baseKV[ def.name ] ~= nil )
			or ( working and working.params[ def.name ] ~= nil )

		local matches = ( filter == "" )
			or string.find( def.name, filter, 1, true )
			or string.find( string.lower( def.description or "" ), filter, 1, true )

		if matches and ( showAll or isSet ) then
			table.insert( Bucket( def.group or AdvMat.G.MISC ), def )
		end
	end

	-- Anything the material itself defines that the database has no entry for.
	local extras = {}
	for key in pairs( baseKV ) do
		if not seen[ key ] then extras[ key ] = true end
	end
	for key in pairs( working and working.params or {} ) do
		if not seen[ key ] then extras[ key ] = true end
	end

	local extraKeys = {}
	for key in pairs( extras ) do extraKeys[ #extraKeys + 1 ] = key end
	table.sort( extraKeys )

	for _, key in ipairs( extraKeys ) do
		if filter == "" or string.find( key, filter, 1, true ) then
			table.insert( Bucket( AdvMat.G.OTHER ), AdvMat.GetParamDef( shader, key ) )
		end
	end

	----------------------------------------------------- render buckets
	table.sort( order, function( a, b )
		return AdvMat.GroupOrder( a ) < AdvMat.GroupOrder( b )
	end )

	if #order == 0 then
		local lbl = self.Scroll:Add( "DLabel" )
		lbl:Dock( TOP )
		lbl:SetTall( AdvMat.RowHeight() * 2 )
		lbl:SetText( "  Nothing matches. Try turning on \"Show every supported parameter\"." )
		AdvMat.StyleLabel( lbl, "AdvMatText", T.TextDim )
		return
	end

	-- Why no texture row offers Import, said once above all of them.
	if AdvMat.Import then AdvMat.Import.CreateNotice( self.Scroll, self ) end

	local rowH = AdvMat.RowHeight()

	for _, group in ipairs( order ) do
		local defs = buckets[ group ]

		local cat = self.Scroll:Add( "DCollapsibleCategory" )
		cat:Dock( TOP )
		cat:DockMargin( 0, 0, 6, 4 )
		cat:SetLabel( group .. "  (" .. #defs .. ")" )
		AdvMat.StyleCategory( cat )
		self.ParamCats[ group ] = cat

		local body = vgui.Create( "DPanel" )
		body.Paint = AdvMat.Fill( T.Panel )
		body:SetTall( 4 )
		cat:SetContents( body )

		-- VertexLitGeneric alone exposes over two hundred parameters, and each
		-- row is several panels. Categories therefore build their rows the
		-- first time they are opened rather than all at once.
		local function Fill()
			if cat.AdvMatFilled then return end
			cat.AdvMatFilled = true

			for i, def in ipairs( defs ) do
				AdvMat.CreateParamRow( body, ctx, def, i )

				local recipe = ctx.GetGen and ctx.GetGen( def.name )
				if recipe then
					AdvMat.CreateGenInfoRow( body, ctx, def, recipe )
				end
			end

			-- Measured rather than counted: a transform row contributes a
			-- second panel that expands and collapses.
			AdvMat.SizeRows( body )
			self.Scroll:InvalidateLayout( true )
		end

		cat.OnToggle = function( _, expanded )
			if expanded then Fill() end
		end

		local remembered = filter == "" and savedView and savedView.groups
			and savedView.groups[ group ]
		local hasRemembered = filter == "" and savedView and savedView.groups
			and savedView.groups[ group ] ~= nil
		local expanded = filter ~= "" or ( hasRemembered and remembered
			or not hasRemembered and AdvMat.GroupStartsOpen( group ) )

		if expanded then
			cat:SetExpanded( true )
			Fill()
		else
			cat:SetExpanded( false )
		end
	end

	------------------------------------------------- add-custom footer
	local add = self.Scroll:Add( "DButton" )
	add:Dock( TOP )
	add:SetTall( AdvMat.RowHeight() )
	add:DockMargin( 0, 6, 6, 4 )
	add:SetText( "Add a parameter by name..." )
	AdvMat.StyleButton( add )
	add.DoClick = function()
		Derma_StringRequest( AdvMat.L( "editor.add_parameter_title" ),
			AdvMat.L( "editor.add_parameter_prompt" ), "$",
			function( text )
				text = string.lower( string.Trim( text ) )
				local sigil = string.sub( text, 1, 1 )
				if sigil ~= "$" and sigil ~= "%" then
					AdvMat.NotifyLocal( "Parameter names start with $ or %.", NOTIFY_ERROR, 4 )
					return
				end
				ctx.Set( text, "1" )
				self:BuildParamList()
			end )
	end

	if filter == "" and savedView then
		self:RestoreParamScroll( idx, savedView.scroll, build )
	end
end

---------------------------------------------------------------------------
-- Saving
---------------------------------------------------------------------------
function PANEL:CurrentScope()
	if self.WorldMat then return AdvMat.SCOPE.WORLD end

	local _, data = self.ScopeBox:GetSelected()
	return tonumber( data ) or AdvMat.SCOPE.MODEL
end

function PANEL:ScopeKey( idx, scope )
	scope = scope or self:CurrentScope()
	if scope == AdvMat.SCOPE.WORLD    then return self.WorldMat end
	if scope == AdvMat.SCOPE.MODEL    then return self.Entity:GetModel() end
	if scope == AdvMat.SCOPE.MATERIAL then return AdvMat.NormalizeMaterial( self.Materials[ idx + 1 ] or "" ) end
	return self.Entity:EntIndex()
end

--- `force` skips the version check, for "Reset to Default", which removes
--- every scope's rule whatever it currently holds.
function PANEL:SendRule( idx, remove, scope, done, force )
	scope = scope or self:CurrentScope()

	local w = self.Working[ idx ]

	-- Sent in the same canonical form the preview was built from, so that what
	-- is saved is what was on screen. Sending the raw working copy and letting
	-- the server decide what survives is how a parameter came to look fine
	-- right up until Save.
	local params, gen

	if not remove then
		params, gen = self:Canonical( idx )
	end

	local payload = {
		scope  = scope,
		key    = self:ScopeKey( idx, scope ),
		index  = idx,
		mat    = ( w and w.mat ~= "" ) and w.mat
		         or AdvMat.NormalizeMaterial( self.Materials[ idx + 1 ] or "" ),
		shader = ( not remove ) and ( w and w.shader ) or nil,
		params = params or {},
		gen    = gen,
	}
	local sendID = AdvMat.RuleID( scope, payload.key, idx )
	if not force then
		self.BaseTokens = self.BaseTokens or {}
		local base = self.BaseTokens[ sendID ]
		-- Every identity a Save can target is captured when the working copy
		-- loads; fall back to what the mirror holds now rather than to "".
		if base == nil then
			local C = AdvMat.Client
			local current
			if scope == AdvMat.SCOPE.ENTITY then
				local set = C.EntRules and C.EntRules[ tonumber( payload.key ) or -1 ]
				current = set and set[ idx ]
			else
				current = C.Rules and C.Rules[ sendID ]
			end
			base = AdvMat.RuleToken( current )
		end
		payload.expect = base
	end
	self.RuleSendSerial = ( self.RuleSendSerial or 0 ) + 1
	local token = self.RuleSendSerial
	self.RuleSendTokens = self.RuleSendTokens or {}
	self.RuleSendTokens[ sendID ] = token
	local completed = false
	local function Complete( ok, reason )
		if completed then return end
		completed = true
		if self.RuleSendTokens and self.RuleSendTokens[ sendID ] == token then
			self.RuleSendTokens[ sendID ] = nil
		end
		if done then done( ok, reason, payload ) end
	end
	local function IsCurrent()
		return IsValid( self ) and not self.AdvMatClosing
			and self.RuleSendTokens and self.RuleSendTokens[ sendID ] == token
	end

	if AdvMat.DebugTraceActive then
		AdvMat.DebugTraceEvent( "save.outgoing", {
			remove = remove == true,
			selected = self.Selected,
			scope = scope,
			payload = payload,
		} )
		AdvMat.DebugTraceSnapshot( "save.before_send", self.Entity, idx,
			not remove and payload or nil )
	end

	local function Transmit()
		if not IsCurrent() then Complete( false, "superseded" ) return end
		-- Do this before sending.  A listen server can return the canonical rule
		-- before net.SendToServer itself returns.
		if not remove and IsValid( self.Entity ) then
			AdvMat.Client.ExpectSave( self.Entity, idx, payload )
		end

		-- Assume the save lands: a second Save pressed before this one is
		-- acknowledged is based on it, not on what was loaded. A refusal puts
		-- back what the server really holds (OnRuleRejected).
		local token = remove and "" or AdvMat.RuleToken( payload )
		self.SentTokens = self.SentTokens or {}
		self.SentTokens[ sendID ] = { token = token, idx = idx }
		self.BaseTokens = self.BaseTokens or {}
		self.BaseTokens[ sendID ] = token

		net.Start( remove and "AdvMat.RuleClear" or "AdvMat.RuleSet" )
			AdvMat.Net.WriteTable( payload )
		net.SendToServer()

		if AdvMat.DebugTraceActive then
			local ent, sentIndex = self.Entity, idx
			local sent = not remove and table.Copy( payload ) or nil

			AdvMat.DebugTraceEvent( "save.net_sent", { index = idx, remove = remove == true } )
			for _, delay in ipairs( { 0, 0.1, 0.5, 2 } ) do
				timer.Simple( delay, function()
					if not AdvMat.DebugTraceActive then return end
					AdvMat.DebugTraceSnapshot( "save.after_" .. tostring( delay ), ent, sentIndex, sent )
					if delay == 2 then AdvMat.DebugTraceCheckpoint() end
				end )
			end
		end
		Complete( true )
	end

	-- A recipe-only RuleSet can reach a peer which cannot export this image at
	-- full resolution. Finish the exact PNG upload and wait for the server's
	-- durable-cache acknowledgement before RuleSet. Peers can then fetch those
	-- authoritative bytes on demand instead of attempting a degraded rebuild.
	if not remove and AdvMat.Assets and isfunction( AdvMat.Assets.PrepareRule ) then
		AdvMat.Assets.PrepareRule( payload, function( ok, reason )
			if not IsCurrent() then Complete( false, "superseded" ) return end
			if ok then Transmit() return end
			AdvMat.NotifyLocal( AdvMat.L( "notify.asset_prepare_failed", {
				reason = tostring( reason or "upload failed" ),
			} ), NOTIFY_ERROR, 8 )
			Complete( false, reason or "upload failed" )
		end )
		return payload
	end
	Transmit()
	return payload
end

function PANEL:SaveAll()
	if not IsValid( self.Entity ) and not self.WorldMat then return end

	local saved, cleared = 0, 0
	local actions = {}
	local shadowed       = nil
	local waitsForEditedTexture = false

	local target = self:CurrentScope()

	for idx = 0, #self.Materials - 1 do
		local w     = self.Working[ idx ]
		local empty = AdvMat.RuleIsEmpty( w )

		if not empty then
			-- Give immediate feedback only when Save really has an asynchronous
			-- exact-PNG preflight left to finish. Ordinary parameter-only saves and
			-- edits already acknowledged during background staging stay uncluttered.
			if not waitsForEditedTexture and AdvMat.Assets
				and isfunction( AdvMat.Assets.NeedsUpload ) then
				waitsForEditedTexture = AdvMat.Assets.NeedsUpload( w.gen )
			end

			-- The settings on screen may have been loaded from a narrower rule
			-- than the one being saved, in which case that narrower rule keeps
			-- winning and the save looks like it did nothing.
			local from = self.RuleScope[ idx ]
			if from and from ~= target and SCOPE_RANK[ from ] > SCOPE_RANK[ target ] then
				shadowed = from
			end

			actions[ #actions + 1 ] = { idx = idx, remove = false }
			saved = saved + 1

		elseif self.HadRule[ idx ] then
			-- Every parameter was removed from a slot that used to have a
			-- saved rule, so the rule itself has to go.
			actions[ #actions + 1 ] = { idx = idx, remove = true }
			cleared = cleared + 1
		end
	end

	if saved == 0 and cleared == 0 then
		AdvMat.NotifyLocal( "Nothing to save - no parameters have been changed.", NOTIFY_HINT, 4 )
		return
	end
	if waitsForEditedTexture then
		AdvMat.NotifyLocal( AdvMat.L( "notify.asset_preparing", {
			count = #actions,
		} ), NOTIFY_GENERIC, 5 )
	end

	local remaining, sent, removed, failed = #actions, 0, 0, 0
	for _, action in ipairs( actions ) do
		local actionIndex, actionRemove = action.idx, action.remove
		self:SendRule( actionIndex, actionRemove, target, function( ok, reason )
			remaining = remaining - 1
			if ok then
				if actionRemove then
					self.HadRule[ actionIndex ] = nil
					self.RuleScope[ actionIndex ] = nil
					removed = removed + 1
				else
					self.HadRule[ actionIndex ] = true
					self.RuleScope[ actionIndex ] = target
					sent = sent + 1
				end
			elseif reason ~= "superseded" then
				failed = failed + 1
			end
			if remaining > 0 then return end
			if sent + removed > 0 then
				AdvMat.NotifyLocal( string.format(
					"Submitted %d override(s)%s; waiting for server confirmation.",
					sent, removed > 0 and ( ", removed " .. removed ) or "" ),
					NOTIFY_GENERIC, 5 )
				surface.PlaySound( "buttons/button15.wav" )
			elseif failed > 0 then
				AdvMat.NotifyLocal( "No overrides were submitted.", NOTIFY_ERROR, 5 )
			end
		end )
	end

	if shadowed then
		AdvMat.NotifyLocal( AdvMat.L( "notify.shadowed", {
			scope = AdvMat.LText( AdvMat.SCOPE_NAME[ shadowed ] ),
		} ), NOTIFY_HINT, 8 )
	end

	-- Entity previews are released by AdvMat.Client.ConfirmSave when the server
	-- acknowledges that its apply pass (not merely storage) completed for the
	-- exact canonical rule. There is deliberately no fixed delay here: latency
	-- is not a save acknowledgement.
end

function PANEL:DeleteSelected()
	local idx = self.Selected
	if not idx then return end

	-- Clear every scope, not just the current save target. Otherwise removing
	-- a "model" override can leave an "entity" one still shadowing it, and the
	-- slot looks unchanged. A map surface only ever has the one scope.
	local scopes = self.WorldMat
		and { AdvMat.SCOPE.WORLD }
		or  { AdvMat.SCOPE.ENTITY, AdvMat.SCOPE.MODEL, AdvMat.SCOPE.MATERIAL }

	for _, scope in ipairs( scopes ) do
		self:SendRule( idx, true, scope, nil, true )
	end

	self.Working[ idx ]   = nil
	self.HadRule[ idx ]   = nil
	self.RuleScope[ idx ] = nil

	AdvMat.Client.ClearPreview( self.Entity, idx )
	self:QueuePreview()
	self:BuildParamList()
	self:UpdateMarkers()

	AdvMat.NotifyLocal( "Override removed.", NOTIFY_GENERIC, 3 )
end

---------------------------------------------------------------------------
-- .vmt export
---------------------------------------------------------------------------
function PANEL:OpenVMTExport()
	local idx = self.Selected

	if not idx then
		AdvMat.NotifyLocal( "Select a sub-material first.", NOTIFY_HINT, 3 )
		return
	end

	local w = self.Working[ idx ]

	AdvMat.OpenVMTExport( {
		mat    = AdvMat.NormalizeMaterial( self.Materials[ idx + 1 ] or "" ),
		shader = w and w.shader,
		params = ( w and w.params ) or {},
		gen    = w and w.gen,
	}, self:GetBaseKV( idx ), self:GetActiveShader( idx ), self )
end

---------------------------------------------------------------------------
-- Presets
---------------------------------------------------------------------------
local PRESET_DIR = "advmat/presets"

function PANEL:OpenPresetMenu()
	local idx = self.Selected
	if not idx then
		AdvMat.NotifyLocal( "Select a sub-material first.", NOTIFY_HINT, 3 )
		return
	end

	local menu = DermaMenu()
	AdvMat.I18N.Track( menu )

	menu:AddOption( "Save these parameters as a preset...", function()
		Derma_StringRequest( AdvMat.L( "editor.preset_title" ),
			AdvMat.L( "editor.preset_prompt" ), AdvMat.L( "editor.preset_default" ), function( name )
			name = string.gsub( string.lower( string.Trim( name ) ), "[^%w_%-]", "_" )
			if name == "" then return end

			file.CreateDir( "advmat" )
			file.CreateDir( PRESET_DIR )

			local w = self.Working[ idx ]
			file.Write( PRESET_DIR .. "/" .. name .. ".json", util.TableToJSON( {
				shader = w and w.shader or self:GetActiveShader( idx ),
				params = w and w.params or {},
			}, true ) )

			AdvMat.NotifyLocal( "Preset saved as " .. name, NOTIFY_GENERIC, 4 )
		end )
	end ):SetIcon( "icon16/disk.png" )

	local presets = file.Find( PRESET_DIR .. "/*.json", "DATA" ) or {}

	if #presets > 0 then
		menu:AddSpacer()

		local load = menu:AddSubMenu( "Apply a preset" )
		local wipe = menu:AddSubMenu( "Delete a preset" )

		for _, fname in ipairs( presets ) do
			local nice = string.StripExtension( fname )

			load:AddOption( nice, function()
				local raw = file.Read( PRESET_DIR .. "/" .. fname, "DATA" )
				local tbl = raw and util.JSONToTable( raw )

				if not istable( tbl ) or not istable( tbl.params ) then
					AdvMat.NotifyLocal( "That preset is unreadable.", NOTIFY_ERROR, 4 )
					return
				end

				local w = self:GetWorking( idx, true )
				w.shader = tbl.shader
				for k, v in pairs( AdvMat.SanitizeParams( tbl.params ) ) do w.params[ k ] = v end

				self:BuildParamList()
				self:QueuePreview()
			end )

			wipe:AddOption( nice, function()
				file.Delete( PRESET_DIR .. "/" .. fname )
				AdvMat.NotifyLocal( "Deleted preset " .. nice, NOTIFY_GENERIC, 3 )
			end )
		end
	end

	menu:AddSpacer()

	menu:AddOption( "Copy these parameters to every other sub-material", function()
		local w = self.Working[ idx ]
		if AdvMat.RuleIsEmpty( w ) then return end

		for other = 0, #self.Materials - 1 do
			if other ~= idx then
				local ow = self:GetWorking( other, true )
				ow.shader = w.shader
				for k, v in pairs( w.params ) do ow.params[ k ] = v end
				ow.gen = w.gen and table.Copy( w.gen ) or nil
			end
		end

		self:QueuePreview()
		AdvMat.NotifyLocal( "Copied to " .. ( #self.Materials - 1 ) .. " sub-material(s).",
			NOTIFY_GENERIC, 4 )
	end ):SetIcon( "icon16/page_copy.png" )

	menu:Open()
end

---------------------------------------------------------------------------
function PANEL:OnClose()
	if self.AdvMatClosing then return end
	self.AdvMatClosing = true
	self.RuleSendTokens = {}
	if self.RejectHookID then
		hook.Remove( "AdvMatRuleRejected", self.RejectHookID )
		self.RejectHookID = nil
	end
	if self.ImportHookID then
		hook.Remove( "AdvMatImportChanged", self.ImportHookID )
		self.ImportHookID = nil
	end
	AdvMat.CloseParamHelp()

	-- Every subordinate dialog carries this exact host.  Closing the material
	-- editor ends the edit session, so do not leave a texture/generator callback
	-- alive with a removed panel behind it.
	for _, name in ipairs( {
		"TexPicker", "TexEditor", "SurfaceDialog", "GenDialog", "ImportHelp",
	} ) do
		local child = AdvMat[ name ]
		if IsValid( child ) and child.AdvMatHost == self and isfunction( child.Close ) then
			child:Close()
		end
	end

	if IsValid( self.Entity ) then
		if AdvMat.DebugTraceActive then
			AdvMat.DebugTraceSnapshot( "editor.before_close", self.Entity, self.Selected or 0 )
		end
		AdvMat.Client.ClearUncommittedPreviews( self.Entity )
		if AdvMat.DebugTraceActive then
			AdvMat.DebugTraceSnapshot( "editor.after_close", self.Entity, self.Selected or 0 )
			AdvMat.DebugTraceCheckpoint()
		end
	end

	-- Drop any unsaved map-material preview back to what is actually stored.
	if self.WorldMat then AdvMat.Apply.RefreshWorld() end

	if AdvMat.Backend and isfunction( AdvMat.Backend.EndSession ) then
		AdvMat.Backend.EndSession( self.AdvMatBackendSession )
	end
	if AdvMat.Editor == self then AdvMat.Editor = nil end
end

function PANEL:OnRemove()
	-- Direct Remove/hot reload bypasses DFrame:OnClose. Keep session, preview,
	-- child-window and input cleanup identical to the close-button path.
	self:OnClose()
end

vgui.Register( "AdvMatEditor", PANEL, "DFrame" )

---------------------------------------------------------------------------
-- Entry points
---------------------------------------------------------------------------
--- Open on an entity, or on a map surface material when `worldMat` is given.
function AdvMat.OpenVanillaEditor( ent, worldMat, session )
	if not IsValid( ent ) and ( not worldMat or worldMat == "" ) then return end

	-- One open window is one edit session.  A predicted tool click still reaches
	-- the server while Derma has the mouse, so a click on another prop or wall
	-- must focus the existing session rather than destroying it and retargeting
	-- the callbacks of any texture dialog it owns.
	if IsValid( AdvMat.Editor ) then
		local focus = AdvMat.Editor
		for _, name in ipairs( {
			"TexPicker", "TexEditor", "SurfaceDialog", "GenDialog",
		} ) do
			local child = AdvMat[ name ]
			if IsValid( child ) and child.AdvMatHost == AdvMat.Editor then
				focus = child
				break
			end
		end

		if AdvMat.WindowUX then
			AdvMat.WindowUX.Focus( focus )
		else
			if isfunction( focus.MakePopup ) then focus:MakePopup() end
			if isfunction( focus.MoveToFront ) then focus:MoveToFront() end
		end
		return AdvMat.Editor
	end

	-- Flat magenta, used by the "highlight selected sub-material" toggle.
	CreateMaterial( "advmat_highlight", "UnlitGeneric", {
		[ "$basetexture" ] = "color/white",
		[ "$model" ]       = "1",
		[ "$color" ]       = "[1 0 1]",
	} )

	local frame = vgui.Create( "AdvMatEditor" )
	frame.AdvMatBackendSession = session
	frame.BackendSession = session
	AdvMat.Editor = frame

	if worldMat and worldMat ~= "" then
		frame:SetWorldMaterial( worldMat )
	else
		frame:SetEntity( ent )
	end

	return frame
end
