--[[---------------------------------------------------------------------------
	Advanced Material Editor - RTX Remix editor

	This window owns PBR profiles and an AdvMat bake graph.  Its Material and
	Shader graph workspaces use only the RTX profile store.  A separate embedded
	Source / VMT workspace can also author ordinary AdvMat rules because Source
	still evaluates those parameters in the Remix client; its state and save
	channel remain isolated from the hash-scoped PBR profile.
-----------------------------------------------------------------------------]]

AdvMat = AdvMat or {}

local T       = AdvMat.Theme
local Bridge  = AdvMat.RTX and AdvMat.RTX.Bridge
local Enhance = AdvMat.RTX and AdvMat.RTX.Enhance
local Store   = AdvMat.RTXStore

local MAPS = {
	{ key = "albedo",    label = "Base colour", source = "baseTexture" },
	{ key = "normal",    label = "Normal",      source = "bumpMap", normal = true },
	{ key = "roughness", label = "Roughness" },
	{ key = "metallic",  label = "Metallic" },
	{ key = "height",    label = "Height" },
	{ key = "anisotropy", label = "Anisotropy" },
	{ key = "subsurface_transmittance", label = "Subsurface transmittance" },
	{ key = "subsurface_thickness", label = "Subsurface thickness" },
	{ key = "subsurface_scattering", label = "Single-scattering albedo" },
	{ key = "subsurface_radius", label = "Subsurface radius" },
}

local EMISSION_MAP = { key = "emissive", label = "Emission", source = "emissionTexture" }

local INSPECTION_MAP_FIELDS = {
	albedo = { "baseTexture" },
	normal = { "bumpMap", "exoNormal", "discoveredNormal" },
	roughness = { "phongExponentTexture", "envMapMask", "mraoTexture", "armTexture", "baseTexture" },
	metallic = { "armTexture", "mraoTexture", "baseTexture" },
	height = { "discoveredHeight", "bumpMap", "baseTexture" },
	emissive = { "emissionTexture", "gpbrEmission", "baseTexture" },
	anisotropy = { "baseTexture" },
	subsurface_transmittance = {},
	subsurface_thickness = {},
	subsurface_scattering = {},
	subsurface_radius = {},
}

local function L( key, fallback, vars )
	if AdvMat.I18N and AdvMat.I18N.HasKey and AdvMat.I18N.HasKey( key ) then
		return AdvMat.L( key, vars )
	end
	return fallback
end

local function Copy( value )
	return istable( value ) and table.Copy( value ) or value
end

local function Schema()
	return AdvMat.RTX and AdvMat.RTX.Schema or AdvMat.RTXSchema
end

local function ReadCapabilities()
	if not Bridge or not isfunction( Bridge.Capabilities ) then return {} end
	local ok, capabilities = pcall( Bridge.Capabilities )
	return ok and istable( capabilities ) and capabilities or {}
end

local function ErrorText( errors )
	if istable( errors ) then return table.concat( errors, "; " ) end
	return tostring( errors or "unknown error" )
end

local function MaterialName( value )
	if istable( value ) then value = value.target and value.target.material or value.material end
	return AdvMat.NormalizeMaterial( value or "" )
end

local function MapSource( value )
	if isstring( value ) then return value end
	return istable( value ) and value.source or ""
end

local function MapRecipe( value )
	return istable( value ) and value.recipe or nil
end

-- AME's normal generator draws the way Source reads a normal map, DirectX
-- style, and an edit of a Source texture is one; the bridge converts such a
-- picture to the octahedral form Remix reads (cl_29_rtx_normals.lua). Saying
-- so matters on an enhanced row, which starts out octahedral: a normal map
-- made there would otherwise go to Remix as the tangent-space picture it is.
-- Any other picture - an import, an edit of an enhancement map - keeps the
-- encoding chosen for it.
local function KnownNormalEncoding( recipe )
	if not istable( recipe ) or not AdvMat.Gen or not isfunction( AdvMat.Gen.KindOf ) then return nil end
	local _, kind = AdvMat.Gen.KindOf( recipe )
	if kind == "normal" then return "tangent_space_dx" end
	local source = isstring( recipe.src ) and string.lower( recipe.src ) or ""
	if kind == "edit" and source ~= "" and string.sub( source, 1, 5 ) ~= "data/"
		and not string.match( source, "%.%w+$" ) then
		return "tangent_space_dx"
	end
	return nil
end

local function FeedsNormalSocket( graph, nodeID )
	for _, link in ipairs( istable( graph ) and graph.links or {} ) do
		if link.from and link.from.node == nodeID and link.to and link.to.socket == "normal" then
			for _, node in ipairs( graph.nodes or {} ) do
				if node.id == link.to.node then return node.type == "output_surface" end
			end
		end
	end
	return false
end

--- A generated descriptor always carries a concrete, safe path even when its
--- recipe starts from a flat fill and therefore has no input `src`.  The bridge
--- later materialises this same deterministic path before calling native code.
local function RecipeMapSource( recipe )
	if not istable( recipe ) then return "" end
	local source = AdvMat.NormalizeMaterial( recipe.src or "" )
	if source ~= "" then return source end

	local gen = AdvMat.Gen
	if not gen or not isfunction( gen.Sanitize ) or not isfunction( gen.MaterialPath ) then
		return ""
	end
	local ok, clean = pcall( gen.Sanitize, Copy( recipe ) )
	if not ok or not istable( clean ) then return "" end
	local pathOK, path = pcall( gen.MaterialPath, clean )
	if not pathOK then return "" end
	return AdvMat.NormalizeMaterial( path or "" )
end

-- Source/VTF names need an UnlitGeneric wrapper to be useful in a 2D panel,
-- while generated editor outputs are ordinary PNGs under data/ and must go
-- through Global.Material directly.  Keeping that distinction here lets RTX
-- rows share the vanilla preview helper without teaching that Source-oriented
-- helper about the RTX profile format.
local IMAGE_EXTENSIONS = {
	bmp = true, gif = true, jpeg = true, jpg = true, png = true,
	tif = true, tiff = true,
}

local function MapPreviewMaterial( path )
	path = AdvMat.NormalizeMaterial( path or "" )
	if path == "" then return nil end

	local lower = string.lower( path )
	local extension = string.match( lower, "%.([%w]+)$" )
	if string.sub( lower, 1, 5 ) == "data/" or IMAGE_EXTENSIONS[ extension ] then
		local ok, material = pcall( Material, path, "noclamp smooth" )
		if ok and material then return material end
	end

	if isfunction( AdvMat.PreviewMaterial ) then
		return AdvMat.PreviewMaterial( path )
	end

	local ok, material = pcall( Material, path, "noclamp smooth" )
	return ok and material or nil
end

local function InspectedMapSource( inspection, key )
	local source = istable( inspection ) and inspection.source or {}
	for _, field in ipairs( INSPECTION_MAP_FIELDS[ key ] or {} ) do
		local value = source[ field ]
		if isstring( value ) then
			value = AdvMat.NormalizeMaterial( value )
			if value ~= "" then return value end
		end
	end
	return ""
end

-- A generated edit is represented by its portable recipe in the profile, but
-- another generator must read the image that recipe produces rather than its
-- original Source/VTF input.  Do not open the consumer until that image really
-- exists: the normal dialog probes its source immediately for size and preview.
local materializeRecipeSerial = 0
local function MaterializeRecipeSource( recipe, done )
	local gen = AdvMat.Gen
	if not istable( recipe ) or not gen or not isfunction( gen.Sanitize )
		or not isfunction( gen.FileName ) or not isfunction( gen.MaterialPath )
		or not isfunction( gen.Request ) then return false end
	local ok, clean = pcall( gen.Sanitize, Copy( recipe ) )
	if not ok or not clean then return false end
	local targetOK, target = pcall( gen.FileName, clean )
	local pathOK, path = pcall( gen.MaterialPath, clean )
	if not targetOK or not isstring( target ) or target == ""
		or not pathOK or not isstring( path ) or path == "" then return false end
	if file.Exists( target, "DATA" ) then
		if done then done( path, clean ) end
		return true
	end

	materializeRecipeSerial = materializeRecipeSerial + 1
	local hookID = "AdvMat.RTX.NormalSource." .. materializeRecipeSerial
		.. "." .. util.CRC( target )
	local timerID = hookID .. ".Timeout"
	local finished = false
	local function Finish( generatedPath, reason )
		if finished then return end
		finished = true
		hook.Remove( "AdvMatGenerated", hookID )
		hook.Remove( "AdvMatGenerationFailed", hookID )
		timer.Remove( timerID )
		if done then done( generatedPath, clean, reason ) end
	end
	hook.Add( "AdvMatGenerated", hookID, function( _, produced )
		if produced == target then Finish( path ) end
	end )
	hook.Add( "AdvMatGenerationFailed", hookID, function( _, produced, reason )
		if produced == target then Finish( nil, reason or "generation failed" ) end
	end )
	timer.Create( timerID, 120, 1, function()
		Finish( nil, "generation timed out" )
	end )
	local requested, reason = pcall( gen.Request, clean )
	if not requested then Finish( nil, tostring( reason ) ) end
	return true
end

local function Section( parent, text )
	local header = parent:Add( "DLabel" )
	header:Dock( TOP )
	header:SetTall( AdvMat.RowHeight() + 6 )
	header:DockMargin( 0, 10, 0, 1 )
	header:SetText( "  " .. text )
	header.Paint = AdvMat.Fill( T.Header )
	AdvMat.StyleLabel( header, "AdvMatBold", T.Text )
	return header
end

local function FlatLabel( parent, text, colour, tall )
	local label = parent:Add( "DLabel" )
	label:Dock( TOP )
	label:SetTall( tall or AdvMat.RowHeight() )
	label:DockMargin( 8, 3, 8, 2 )
	label:SetText( text )
	label:SetWrap( true )
	AdvMat.StyleLabel( label, "AdvMatText", colour or T.Text )
	return label
end

local PANEL = {}

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

function PANEL:Init()
	self:SetTitle( L( "rtx.title", "Advanced Material Editor — RTX Remix" ) )
	self:SetDeleteOnClose( true )
	self:SetSizable( true )
	self:ShowCloseButton( true )
	self:SetMinWidth( 820 )
	self:SetMinHeight( 560 )
	self:SetSize( math.Clamp( ScrW() * 0.46, 820, 1500 ),
		math.Clamp( ScrH() * 0.84, 560, 1150 ) )
	self:MakePopup()
	AdvMat.StyleFrame( self )
	if AdvMat.WindowUX then AdvMat.WindowUX.SetupFrame( self, "rtx_editor" ) end

	self.Materials   = {}
	self.MaterialSlots = {}
	self.MaterialSlotGroups = {}
	self.SourceMaterials = {}
	self.Working     = {}
	self.Saved       = {}
	self.SavedIDs    = {}
	self.SavedETags  = {}
	self.Inspections = {}
	self.Dirty       = {}
	self.Undo        = {}
	self.LastUndoAt  = {}
	self.EditRevision = {}
	self.PendingClears = {}
	self.SaveRequests = {}
	self.MaterialAliases = {}
	self.PreviewedMaterials = {}
	-- Per row: the native writer refused its last Save, which the server's
	-- later "synced" notice must not cover up.
	self.ApplyFailed = {}
	-- Per row: the Remix enhancement lookup for its captured hashes, the hashes
	-- read for rows not opened yet (for the list markers), and whether Save may
	-- replace a glass or portal enhancement with an opaque material.
	self.Enhancements = {}
	self.RowHashes   = {}
	self.ShaderChangeConfirmed = {}
	self.Selected    = nil
	self.TargetModel = ""
	self.Closing     = false
	self.RTXStatusText = ""
	self.RTXStatusProblem = nil
	self.SourceStatusText = ""
	self.SourceStatusProblem = nil
	self.RTXCapabilities = ReadCapabilities()
	self.LivePreview = self.RTXCapabilities.livePreview == true

	self.Header = vgui.Create( "DPanel", self )
	self.Header:Dock( TOP )
	self.Header:SetTall( AdvMat.RowHeight() + 16 )
	self.Header.Paint = AdvMat.Fill( Color( 34, 36, 41 ) )

	self.ModeBadge = vgui.Create( "DLabel", self.Header )
	self.ModeBadge:Dock( LEFT )
	self.ModeBadge:SetWide( 245 )
	self.ModeBadge:DockMargin( 10, 4, 8, 4 )
	self.ModeBadge:SetText( L( "rtx.mode_badge", "RTX REMIX  •  APERTURE PBR" ) )
	AdvMat.StyleLabel( self.ModeBadge, "AdvMatBold", Color( 128, 224, 170 ) )

	self.WriterBadge = vgui.Create( "DLabel", self.Header )
	self.WriterBadge:Dock( RIGHT )
	self.WriterBadge:SetWide( 320 )
	self.WriterBadge:DockMargin( 8, 4, 10, 4 )
	self.WriterBadge:SetContentAlignment( 6 )
	AdvMat.StyleLabel( self.WriterBadge, "AdvMatBold", T.TextDim )

	self.ScopeLabel = vgui.Create( "DLabel", self.Header )
	self.ScopeLabel:Dock( FILL )
	self.ScopeLabel:DockMargin( 8, 4, 8, 4 )
	self.ScopeLabel:SetContentAlignment( 5 )
	self.ScopeLabel:SetText( L( "rtx.scope_hash",
		"Scope: every occurrence of the captured texture hash" ) )
	AdvMat.StyleLabel( self.ScopeLabel, "AdvMatText", T.Warn )

	self.WindowUXBar = vgui.Create( "DPanel", self )
	self.WindowUXBar:Dock( TOP )
	self.WindowUXBar:SetTall( AdvMat.RowHeight() + 4 )
	self.WindowUXBar:DockMargin( 8, 4, 8, 0 )
	self.WindowUXBar.Paint = AdvMat.Fill( T.Panel )

	self.MoveBeside = vgui.Create( "DButton", self.WindowUXBar )
	self.MoveBeside:Dock( RIGHT )
	self.MoveBeside:SetWide( math.floor( AdvMat.FontSize * 12.5 ) )
	self.MoveBeside:SetText( L( "window.move_beside", "Move beside target" ) )
	self.MoveBeside:SetTooltip( L( "window.move_beside_tip",
		"Move this window beside the object you are editing." ) )
	AdvMat.StyleButton( self.MoveBeside )
	self.MoveBeside.DoClick = function()
		if AdvMat.WindowUX then
			AdvMat.WindowUX.PositionBesideTarget( self, self.TargetEntity, true )
		end
	end

	self.PlayerMovement = vgui.Create( "DCheckBoxLabel", self.WindowUXBar )
	self.PlayerMovement:Dock( LEFT )
	self.PlayerMovement:DockMargin( 8, 3, 12, 3 )
	AdvMat.StyleCheck( self.PlayerMovement,
		L( "editor.allow_movement", "Allow player movement while editing" ) )
	local movementCV = GetConVar( "advmateditor_playercontrols" )
	self.PlayerMovement:SetValue( movementCV and movementCV:GetBool() and 1 or 0 )
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

	self.WindowUXHint = vgui.Create( "DLabel", self.WindowUXBar )
	self.WindowUXHint:Dock( FILL )
	self.WindowUXHint:SetContentAlignment( 4 )
	self.WindowUXHint:SetTooltip( L( "editor.allow_movement_tip", "" ) )
	AdvMat.StyleLabel( self.WindowUXHint, "AdvMatSmall", T.TextDim )
	self:UpdateWindowUXHint()

	self.Left = vgui.Create( "DPanel", self )
	self.Left:Dock( LEFT )
	self.Left:SetWide( math.Clamp( self:GetWide() * 0.27, 250, 430 ) )
	self.Left:DockMargin( 8, 8, 4, 8 )
	self.Left.Paint = AdvMat.Fill( T.Panel )

	self.MaterialTitle = vgui.Create( "DLabel", self.Left )
	self.MaterialTitle:Dock( BOTTOM )
	self.MaterialTitle:SetTall( AdvMat.RowHeight() + 7 )
	self.MaterialTitle:SetText( L( "editor.submaterials", "Sub-materials" ) )
	AdvMat.StyleLabel( self.MaterialTitle, "AdvMatBold", T.Text )

	self.MaterialList = vgui.Create( "DListView", self.Left )
	self.MaterialList:Dock( BOTTOM )
	self.MaterialList:SetTall( 260 )
	self.MaterialList:SetMultiSelect( false )
	self.MaterialList:AddColumn( "#" ):SetFixedWidth( 38 )
	self.MaterialList:AddColumn( L( "editor.submaterials", "Material" ) )
	self.MaterialList:AddColumn( "" ):SetFixedWidth( 52 )
	AdvMat.StyleListView( self.MaterialList )
	self.MaterialList.OnRowSelected = function( _, _, line )
		self:SelectMaterial( line.AdvMatIndex )
	end

	-- In Derma, a FILL child only reserves space for docked siblings that were
	-- created before it.  Build the preview last so it cannot cover the title
	-- and sub-material list at smaller resolutions.
	self.ModelPanel = vgui.Create( "DModelPanel", self.Left )
	self.ModelPanel:Dock( FILL )
	self.ModelPanel:SetFOV( 40 )
	self.ModelPanel:SetAnimated( false )
	self.ModelPanel.LayoutEntity = function() end
	local paintModel = self.ModelPanel.Paint
	self.ModelPanel.Paint = function( panel, w, h )
		surface.SetDrawColor( 29, 31, 36, 255 )
		surface.DrawRect( 0, 0, w, h )
		if paintModel then paintModel( panel, w, h ) end
	end
	self.ModelPanel.PreDrawModel = function( _, ent )
		if AdvMat.ModelView and AdvMat.ModelView.BeginRTXMirrorDraw then
			AdvMat.ModelView.BeginRTXMirrorDraw( self, ent )
		end
	end
	self.ModelPanel.PostDrawModel = function()
		if AdvMat.ModelView and AdvMat.ModelView.EndRTXDraw then
			AdvMat.ModelView.EndRTXDraw( self )
		end
	end

	self.Right = vgui.Create( "DPanel", self )
	self.Right:Dock( FILL )
	self.Right:DockMargin( 4, 8, 8, 8 )
	self.Right.Paint = AdvMat.Fill( T.Bg )

	self.ActiveMaterial = vgui.Create( "DLabel", self.Right )
	self.ActiveMaterial:Dock( TOP )
	self.ActiveMaterial:SetTall( AdvMat.RowHeight() + 8 )
	self.ActiveMaterial:SetText( L( "editor.select_material", "Select a sub-material on the left" ) )
	AdvMat.StyleLabel( self.ActiveMaterial, "AdvMatTitle", T.Text )

	-- Keep preview state separate from commit actions. A translated Live label
	-- used to squeeze or cover the four buttons at the 820 px minimum width.
	self.Bottom = vgui.Create( "DPanel", self.Right )
	self.Bottom:Dock( BOTTOM )
	self.Bottom:SetTall( AdvMat.RowHeight() + 14 )
	self.Bottom.Paint = AdvMat.Fill( Color( 34, 36, 41 ) )
	self.ActionBar = self.Bottom

	self.PreviewBar = vgui.Create( "DPanel", self.Right )
	self.PreviewBar:Dock( BOTTOM )
	self.PreviewBar:SetTall( AdvMat.RowHeight() + 8 )
	self.PreviewBar:DockMargin( 0, 3, 0, 0 )
	self.PreviewBar.Paint = AdvMat.Fill( T.Panel )

	self.LiveCheck = vgui.Create( "DCheckBoxLabel", self.PreviewBar )
	self.LiveCheck:Dock( LEFT )
	self.LiveCheck:DockMargin( 8, 4, 8, 4 )
	self.LiveCheck:SetValue( self.LivePreview and 1 or 0 )
	self.LiveCheck:SetEnabled( self.RTXCapabilities.livePreview == true )
	AdvMat.StyleCheck( self.LiveCheck, L( "rtx.live_world", "Live RTX world preview" ) )
	self.LiveCheck.OnChange = function( _, enabled )
		if self.UpdatingLiveCheck then return end
		if enabled and ( not self.RTXCapabilities
			or self.RTXCapabilities.livePreview ~= true ) then return end
		self.LivePreview = enabled == true
		self.LivePreviewPreference = self.LivePreview
		if self.LivePreview then self:QueuePreview() else self:RestorePreviews() end
	end

	local actionButtons = {}
	local function PrepareActionButton( button, preferredWide )
		button.AdvMatPreferredWide = math.max( preferredWide,
			math.floor( AdvMat.FontSize * 4.5 ) )
		actionButtons[ #actionButtons + 1 ] = button
	end

	self.CloseButton = vgui.Create( "DButton", self.Bottom )
	self.CloseButton:SetText( L( "common.close", "Close" ) )
	self.CloseButton:SetTooltip( L( "common.close", "Close" ) )
	AdvMat.StyleButton( self.CloseButton )
	self.CloseButton.DoClick = function() self:Close() end
	PrepareActionButton( self.CloseButton, 115 )

	self.SaveButton = vgui.Create( "DButton", self.Bottom )
	self.SaveButton:SetText( L( "common.save", "Save" ) )
	self.SaveButton:SetTooltip( L( "common.save", "Save" ) )
	AdvMat.StyleButton( self.SaveButton )
	self.SaveButton.DoClick = function() self:SaveAll() end
	PrepareActionButton( self.SaveButton, 135 )

	self.ResetButton = vgui.Create( "DButton", self.Bottom )
	self.ResetButton:SetText( L( "rtx.remove", "Remove override" ) )
	self.ResetButton:SetTooltip( L( "rtx.remove", "Remove override" ) )
	AdvMat.StyleButton( self.ResetButton, true )
	self.ResetButton.DoClick = function() self:RemoveOverride() end
	PrepareActionButton( self.ResetButton, 155 )

	self.UndoButton = vgui.Create( "DButton", self.Bottom )
	self.UndoButton:SetText( L( "common.undo", "Undo" ) )
	self.UndoButton:SetTooltip( L( "common.undo", "Undo" ) )
	AdvMat.StyleButton( self.UndoButton )
	self.UndoButton.DoClick = function() self:UndoSelected() end
	PrepareActionButton( self.UndoButton, 105 )

	self.Bottom.PerformLayout = function( _, wide, tall )
		local gap = 5
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

	self.StatusLabel = vgui.Create( "DLabel", self.Right )
	self.StatusLabel:Dock( BOTTOM )
	self.StatusLabel:SetTall( AdvMat.RowHeight() + 3 )
	self.StatusLabel:DockMargin( 4, 2, 4, 2 )
	self.StatusLabel:SetText( "" )
	AdvMat.StyleLabel( self.StatusLabel, "AdvMatSmall", T.TextDim )

	self.Tabs = vgui.Create( "DPropertySheet", self.Right )
	self.Tabs:Dock( FILL )
	self.Tabs.Paint = AdvMat.Fill( T.Panel )

	self.Surface = vgui.Create( "DScrollPanel", self.Tabs )
	self.Surface.Paint = AdvMat.Fill( T.Panel )
	self.Tabs:AddSheet( L( "rtx.surface", "Material" ), self.Surface, "icon16/shading.png" )

	-- Source parameters are still evaluated by the Remix client, but they are
	-- ordinary slot/scope-aware VMT overrides rather than captured-hash PBR
	-- profiles.  The child panel owns a completely separate working copy and
	-- routes saves through AdvMat.RuleSet/RuleClear.
	self.SourcePanel = vgui.Create( "AdvMatRTXSourcePanel", self.Tabs )
	self.SourcePanel:SetParentEditor( self )
	self.SourceSheet = self.Tabs:AddSheet( L( "rtx.source.tab", "Source / VMT" ),
		self.SourcePanel, "icon16/palette.png" )

	self.Graph = vgui.Create( "AdvMatRTXNodeCanvas", self.Tabs )
	self.Tabs:AddSheet( L( "rtx.graph", "Shader graph" ), self.Graph, "icon16/chart_organisation.png" )
	self.Graph.OnGraphChanged = function( _, graph, reason ) self:GraphChanged( graph, reason ) end
	self.Graph.OnGraphError = function( _, errors ) self:SetStatus( ErrorText( errors ), true ) end
	self.Graph.OnEditTextureNode = function( _, nodeID, sourceOverride )
		self:EditTextureNode( nodeID, sourceOverride )
	end

	self.Diagnostics = vgui.Create( "DScrollPanel", self.Tabs )
	self.Diagnostics.Paint = AdvMat.Fill( T.Panel )
	self.Tabs:AddSheet( L( "rtx.diagnostics", "Diagnostics" ), self.Diagnostics, "icon16/information.png" )
	self.Tabs.OnActiveTabChanged = function( _, oldTab, newTab )
		self:OnWorkspaceChanged( oldTab, newTab )
	end

	self.CapabilityHookID = "AdvMat.RTXEditorCapabilities." .. tostring( self )
	hook.Add( "AdvMatBackendCapabilitiesChanged", self.CapabilityHookID, function()
		if not IsValid( self ) then
			hook.Remove( "AdvMatBackendCapabilitiesChanged", self.CapabilityHookID )
			return
		end
		self:RefreshCapabilities()
	end )
	self.ProfileSyncHookID = "AdvMat.RTXEditorProfiles." .. tostring( self )
	hook.Add( "AdvMatRTXProfilesSynced", self.ProfileSyncHookID, function()
		if not IsValid( self ) then
			hook.Remove( "AdvMatRTXProfilesSynced", self.ProfileSyncHookID )
			return
		end
		self:OnProfilesSynced()
	end )
	self.ProfileChangeHookID = "AdvMat.RTXEditorProfileChange." .. tostring( self )
	hook.Add( "AdvMatRTXProfilesChanged", self.ProfileChangeHookID, function( material, profile, removed, profileID )
		if not IsValid( self ) then
			hook.Remove( "AdvMatRTXProfilesChanged", self.ProfileChangeHookID )
			return
		end
		self:OnProfileChanged( material, profile, removed, profileID )
	end )
	self.LocalSyncHookID = "AdvMat.RTXEditorLocalSync." .. tostring( self )
	hook.Add( "AdvMatRTXLocalSyncChanged", self.LocalSyncHookID, function( material, status, reason )
		if not IsValid( self ) then
			hook.Remove( "AdvMatRTXLocalSyncChanged", self.LocalSyncHookID )
			return
		end
		self:OnLocalSyncChanged( material, status, reason )
	end )
	self:RefreshCapabilities()
	self:UpdateActionMode()
end

function PANEL:OnSizeChanged( width )
	if IsValid( self.Left ) then self.Left:SetWide( math.Clamp( width * 0.27, 250, 430 ) ) end
end

function PANEL:OnProfilesSynced()
	-- Refresh untouched slots from the server while retaining local saved work
	-- (Store.Get overlays it) and edits made while the first snapshot was loading.
	for listIndex, material in ipairs( self.Materials or {} ) do
		local slot = listIndex - 1
		if not self.Dirty[ slot ] and not self.PendingClears[ slot ] then
			local saved = Store and Store.Get and Store.Get( material ) or nil
			local id, etag
			if Store and Store.GetVersion then id, etag = Store.GetVersion( material ) end
			self.Saved[ slot ] = saved and Copy( saved ) or nil
			self.SavedIDs[ slot ], self.SavedETags[ slot ] = id, etag
			self.Working[ slot ] = saved and Copy( saved ) or nil
		end
	end
	self:RefreshMaterialAliases()
	if IsValid( self.SaveButton ) then self.SaveButton:SetEnabled( self.AdvMatCanWrite ~= false ) end
	if IsValid( self.ResetButton ) then self.ResetButton:SetEnabled( self.AdvMatCanWrite ~= false ) end
	local selectedIndex = self.PendingSelect
	if selectedIndex == nil then selectedIndex = self.Selected end
	self.PendingSelect = nil
	self:SetStatus( "" )
	if selectedIndex ~= nil then self:SelectMaterial( selectedIndex, true ) end
	-- A background RTX profile sync refreshes the PBR working copy even while
	-- the independent Source/VMT sheet is active. Restore that sheet's selected
	-- real model slot afterwards so the header and action bar do not jump back
	-- to the hash-oriented PBR selection.
	if self:IsSourceTabActive() then
		self:SelectSourceMaterial( self.SourceDisplaySelected or selectedIndex or 0 )
	end
	self:UpdateActionMode()
end

function PANEL:OnProfileChanged( material, profile, _, profileID )
	material = AdvMat.NormalizeMaterial( material or "" )
	if material == "" then return end
	for listIndex, listed in ipairs( self.Materials or {} ) do
		local slot = listIndex - 1
		local listedID = self.SavedIDs[ slot ]
		if not listedID and profileID and Store and Store.GetVersion then
			listedID = Store.GetVersion( listed )
		end
		local sameOwner = isstring( profileID ) and profileID ~= "" and listedID == profileID
		if ( AdvMat.NormalizeMaterial( listed ) == material or sameOwner ) and not self.Dirty[ slot ]
			and not self.PendingClears[ slot ] then
			local saved = profile and Copy( profile ) or nil
			local id, etag
			if Store and Store.GetVersion then id, etag = Store.GetVersion( material ) end
			self.Saved[ slot ] = saved
			self.SavedIDs[ slot ], self.SavedETags[ slot ] = id, etag
			self.Working[ slot ] = saved and Copy( saved )
				or self:CreateProfile( slot, self.Inspections[ slot ] )
			self.PreviewedMaterials[ material ] = nil
			self:BumpEditRevision( slot )
			if self.Selected == slot and self.Working[ slot ] then
				self.Graph:SetGraph( self.Working[ slot ].graph )
				self:BuildSurface()
				self:BuildDiagnostics()
			end
		end
	end
	self:RefreshMaterialAliases()
	self:UpdateMarkers()
end

function PANEL:OnLocalSyncChanged( material, status, reason )
	if self.Closing or status == "pending" then return end
	local selected = false
	for index, profile in pairs( self.Working ) do
		if MaterialName( profile ) == material then
			self.SavedIDs[ index ], self.SavedETags[ index ] = Store.GetVersion( material )
			if status == "failed" then self.Dirty[ index ] = true end
			selected = selected or self.Selected == index
		end
	end
	if selected then
		if status == "failed" then
			self:SetStatus( L( "rtx.background_failed",
				"Server sync failed for {{material}}: {{reason}}. Your local changes are retained; Save to retry.",
				{ material = material, reason = tostring( reason or "" ) } ), true )
		elseif not self.Dirty[ self.Selected ]
			and not ( self.ApplyFailed and self.ApplyFailed[ self.Selected ] ) then
			self:SetStatus( L( "rtx.background_synced", "Saved locally and synced with the server." ) )
		end
	end
	self:UpdateMarkers()
end

function PANEL:IsSourceTabActive()
	return IsValid( self.Tabs ) and self.SourceSheet and IsValid( self.SourceSheet.Tab )
		and self.Tabs:GetActiveTab() == self.SourceSheet.Tab
end

function PANEL:PaintStatus( text, problem )
	if not IsValid( self.StatusLabel ) then return end
	self.StatusLabel:SetText( text or "" )
	self.StatusLabel:SetTextColor( problem == "warning" and T.Warn
		or ( problem and T.Danger or T.TextDim ) )
end

-- Existing RTX call sites keep using SetStatus.  While the Source sheet is
-- active their asynchronous bridge/store messages are remembered without
-- replacing the Source action feedback at the bottom of the window.
function PANEL:SetStatus( text, problem )
	self.RTXStatusText = text or ""
	self.RTXStatusProblem = problem
	if not self:IsSourceTabActive() then self:PaintStatus( text, problem ) end
end

function PANEL:SetSourceStatus( text, problem )
	self.SourceStatusText = text or ""
	self.SourceStatusProblem = problem
	if self:IsSourceTabActive() then self:PaintStatus( text, problem ) end
end

function PANEL:SelectSourceMaterial( index )
	index = tonumber( index )
	if index == nil or not self.Materials[ index + 1 ] then return false end
	self.SourceDisplaySelected = index
	local material = self.Materials[ index + 1 ]
	self.ActiveMaterial:SetText( material )
	if IsValid( self.SourcePanel ) then
		self.SourcePanel:SetMaterialSelection( index, material,
			self.MaterialSlotGroups[ index ] or { self.MaterialSlots[ index ] or index } )
	end
	self:UpdateActionMode()
	return true
end

function PANEL:OnWorkspaceChanged()
	if self:IsSourceTabActive() then
		self:SelectSourceMaterial( self.SourceDisplaySelected or self.Selected or 0 )
	else
		local index = self.SourceDisplaySelected or self.Selected
		if index ~= nil then
			local canonical = self:CanonicalSlot( index )
			self:SelectMaterial( canonical, true )
			local line = self.MaterialLines and self.MaterialLines[ canonical ]
			if IsValid( line ) and IsValid( self.MaterialList ) then
				self.MaterialList:SelectItem( line )
			end
		end
		self:UpdateActionMode()
	end
end

function PANEL:UpdateActionMode()
	if not IsValid( self.SaveButton ) then return end
	local sourceMode = self:IsSourceTabActive()
	self.PreviewBar:SetVisible( not sourceMode )
	self.LiveCheck:SetVisible( not sourceMode )
	self.WriterBadge:SetVisible( not sourceMode )
	self.SaveButton:SetText( L( "common.save", "Save" ) )
	if sourceMode then
		self.ScopeLabel:SetText( L( "rtx.source.save_target", "Source save target" ) )
		self.ResetButton:SetText( L( "rtx.source.remove", "Remove Source override" ) )
		self.ResetButton:SetTooltip( L( "rtx.source.remove", "Remove Source override" ) )
		local source = self.SourcePanel
		local selected = IsValid( source ) and source.Selected ~= nil
		local canWrite = self.AdvMatCanWrite ~= false
		local pending = IsValid( source ) and source:HasPending()
		-- Keep the exact preview handed to RuleSet stable until RuleApplied. A
		-- newer row edit would otherwise replace/cancel that handoff and allow the
		-- authoritative saved snapshot to flash over the newer working copy.
		if IsValid( source ) then source:SetEnabled( not pending ) end
		if IsValid( source.LiveCheck ) then source.LiveCheck:SetEnabled( not pending ) end
		if IsValid( source.ScopeBox ) then
			source.ScopeBox:SetEnabled( not source.WorldMat and not pending )
		end
		self.SaveButton:SetEnabled( canWrite and not pending )
		self.ResetButton:SetEnabled( canWrite and selected and not pending )
		self.UndoButton:SetEnabled( selected and not pending
			and #( source.SourceUndo[ source.Selected ] or {} ) > 0 )
		if IsValid( source.RevertButton ) then
			source.RevertButton:SetEnabled( selected and not pending
				and source.SourceDirty[ source.Selected ] == true )
		end
		local text, problem = source:GetStatus()
		self:SetSourceStatus( text, problem )
	else
		self.ScopeLabel:SetText( L( "rtx.scope_hash",
			"Scope: every occurrence of the captured texture hash" ) )
		self.ResetButton:SetText( L( "rtx.remove", "Remove override" ) )
		self.ResetButton:SetTooltip( L( "rtx.remove", "Remove override" ) )
		local synced = not Store or not Store.IsSynced or Store.IsSynced()
		local canWrite = self.AdvMatCanWrite ~= false
		self.SaveButton:SetEnabled( canWrite )
		self.ResetButton:SetEnabled( canWrite and synced )
		self.UndoButton:SetEnabled( self.Selected ~= nil
			and #( self.Undo[ self.Selected ] or {} ) > 0 )
		self:PaintStatus( self.RTXStatusText, self.RTXStatusProblem )
	end
end

function PANEL:UpdateWriterBadge()
	local caps = self.RTXCapabilities or ReadCapabilities()
	if caps.nativeWriter then
		self.WriterBadge:SetText( caps.livePreview
			and L( "rtx.writer_live", "Native writer • live preview" )
			or L( "rtx.writer_save", "Native writer • save/reload" ) )
		self.WriterBadge:SetTextColor( Color( 128, 224, 170 ) )
	elseif caps.nativeBlocked then
		self.WriterBadge:SetText( L( "rtx.writer_blocked", "Native writer blocked • reset required" ) )
		self.WriterBadge:SetTextColor( T.Danger )
	else
		self.WriterBadge:SetText( L( "rtx.writer_export", "Export-only • native writer not installed" ) )
		self.WriterBadge:SetTextColor( T.Warn )
	end
end

function PANEL:RefreshCapabilities()
	local previousPreview = self.LivePreview == true
	local previouslySupported = self.RTXCapabilities and self.RTXCapabilities.livePreview == true
	self.RTXCapabilities = ReadCapabilities()
	local supportsPreview = self.RTXCapabilities.livePreview == true
	if supportsPreview and not previouslySupported and self.LivePreviewPreference ~= false then
		self.LivePreview = true
	end
	if not supportsPreview then self.LivePreview = false end

	if IsValid( self.LiveCheck ) then
		self.UpdatingLiveCheck = true
		self.LiveCheck:SetEnabled( supportsPreview )
		self.LiveCheck:SetValue( self.LivePreview and 1 or 0 )
		self.LiveCheck:SetTooltip( supportsPreview
			and L( "rtx.live_world_tip", "Preview edits in your world only. Save to keep and share them; closing or turning preview off restores saved materials. Affects every use of the captured texture hash." )
			or L( "rtx.live_world_unavailable", "Live preview requires an updated native RTX bridge with reversible preview support. Update the bridge and restart the game." ) )
		self.UpdatingLiveCheck = false
	end
	if previousPreview and not supportsPreview then self:RestorePreviews() end
	if self.LivePreview and not previousPreview and self.Selected ~= nil
		and self.Dirty[ self.Selected ] then self:QueuePreview() end

	self:UpdateWriterBadge()
	if self.Selected ~= nil then self:BuildDiagnostics() end
end

function PANEL:RestorePreviews()
	local previewed = self.PreviewedMaterials or {}
	self.PreviewedMaterials = {}
	if not Store or not Store.Restore then return end
	for material in pairs( previewed ) do Store.Restore( material ) end
end

function PANEL:FrameModel()
	if not IsValid( self.ModelPanel ) or not IsValid( self.ModelPanel.Entity ) then return end
	local mins, maxs = self.ModelPanel.Entity:GetRenderBounds()
	local centre = ( mins + maxs ) * 0.5
	local radius = math.max( ( maxs - mins ):Length(), 10 )
	self.ModelPanel:SetLookAt( centre )
	self.ModelPanel:SetCamPos( centre + Vector( radius * 0.75, radius * 0.75, radius * 0.25 ) )
end

function PANEL:SetTargetEntity( ent )
	if not IsValid( ent ) then return false end
	self.TargetEntity = ent
	self.TargetModel = AdvMat.NormalizeModel( ent:GetModel() or "" )
	self.SourceMaterials = ent:GetMaterials() or {}
	-- Material/hash profiles are not constrained by Source's sub-material API.
	-- Keep the complete inventory, including GMHLVK's native overflow slots.
	self.Materials = table.Copy( self.SourceMaterials )
	self.ModelPanel:SetModel( self.TargetModel )
	AdvMat.AttachMMDPreview( self.ModelPanel.Entity )
	timer.Simple( 0, function() if IsValid( self ) then self:FrameModel() end end )
	self:PopulateMaterials()
	if IsValid( self.SourcePanel ) then
		self.SourcePanel:SetTargetEntity( ent, self.SourceMaterials, self.MaterialSlotGroups )
		if self.SourceDisplaySelected ~= nil then self:SelectSourceMaterial( self.SourceDisplaySelected ) end
		self:UpdateMarkers()
	end
	if AdvMat.WindowUX then
		AdvMat.WindowUX.PositionBesideTarget( self, ent, false )
	end
	return true
end

function PANEL:SetWorldMaterial( material )
	material = AdvMat.NormalizeMaterial( material )
	if material == "" then return false end
	self.WorldMaterial = material
	self.SourceMaterials = { material }
	self.Materials = { material }
	self.ModelPanel:SetVisible( false )
	self:PopulateMaterials()
	if IsValid( self.SourcePanel ) then
		self.SourcePanel:SetWorldMaterial( material, self.MaterialSlotGroups )
		self.SourcePanel:SetMaterialSelection( 0, material, { 0 } )
		self:UpdateMarkers()
	end
	if AdvMat.WindowUX then
		AdvMat.WindowUX.PositionBesideTarget( self, nil, false )
	end
	return true
end

function PANEL:PopulateMaterials()
	self.MaterialList:Clear()
	self.MaterialLines = {}
	self.MaterialAliases = {}
	local unique, slots, groups, seen = {}, {}, {}, {}
	for sourceIndex, raw in ipairs( self.Materials ) do
		local material = AdvMat.NormalizeMaterial( raw )
		-- RTX replacements are hash/material-global.  Showing duplicate model slots
		-- as independent rows would let two working copies race through the
		-- material-keyed store, so collapse them while retaining the first real slot
		-- for diagnostics and profile metadata.
		if material ~= "" and seen[ material ] == nil then
			local index = #unique
			seen[ material ] = index
			unique[ index + 1 ] = material
			slots[ index ] = sourceIndex - 1
			groups[ index ] = { sourceIndex - 1 }
			local line = self.MaterialList:AddLine( sourceIndex - 1, material, "" )
			line.AdvMatIndex = index
			self.MaterialLines[ index ] = line
			AdvMat.StyleListLine( line, index + 1 )
		elseif material ~= "" then
			local index = seen[ material ]
			groups[ index ][ #groups[ index ] + 1 ] = sourceIndex - 1
		end
	end
	self.Materials = unique
	self.MaterialSlots = slots
	self.MaterialSlotGroups = groups
	self.Enhancements = {}
	self:ReadRowHashes()
	if #self.Materials > 0 then
		local first = self.MaterialLines and self.MaterialLines[ 0 ]
		if first then self.MaterialList:SelectItem( first ) else self:SelectMaterial( 0, true ) end
	end
end

function PANEL:InspectionSeed( material, inspection )
	local source = istable( inspection ) and istable( inspection.source )
		and inspection.source or {}

	return {
		constants = {
			roughness = tonumber( source.roughness ) or 0.5,
			metallic  = tonumber( source.metallic ) or 0,
			emissive_intensity = tonumber( source.emissionScale ) or 0,
		},
		-- InspectMaterial reports Source/VTF logical names, not files a Remix
		-- replacement layer can consume.  They remain inherited UI sources until
		-- the user actually edits one; an unrelated PBR save must not materialise
		-- and downsample the original albedo through the editor's size ceiling.
		maps = {},
	}
end

function PANEL:InspectionMapSource( index, key )
	local inspection = self.Inspections[ index or self.Selected ] or {}
	return InspectedMapSource( inspection, key )
end

-- The existing Source albedo is visible in the row without becoming an
-- authored replacement.  Clicking Edit promotes it to a generated map only
-- after the texture editor returns a real recipe; saving another PBR control
-- therefore preserves the original texture at its native resolution.
function PANEL:DisplayMapSource( index, key, value )
	local source = MapSource( value )
	-- An authored source-less recipe is a real blank map, not the inherited
	-- Source albedo.  Only an entirely absent map receives inspection fallback.
	if source == "" and value == nil and key == "albedo" then
		source = self:InspectionMapSource( index, key )
	end
	return source
end

function PANEL:MapPreviewSource( index, key, value )
	local recipe = MapRecipe( value )
	local gen = AdvMat.Gen
	if istable( recipe ) and gen and isfunction( gen.Sanitize )
		and isfunction( gen.MaterialPath ) then
		local cleanOK, clean = pcall( gen.Sanitize, Copy( recipe ) )
		local pathOK, path = false, nil
		if cleanOK and clean then pathOK, path = pcall( gen.MaterialPath, clean ) end
		if pathOK and isstring( path ) and path ~= "" then return path end
	end
	return self:DisplayMapSource( index, key, value )
end

function PANEL:MapPreviewMaterial( source )
	return MapPreviewMaterial( source )
end

function PANEL:CreateProfile( index, inspection )
	local schema = Schema()
	if not schema then return nil end
	local material = self.Materials[ index + 1 ]
	local hasModel = isstring( self.TargetModel ) and self.TargetModel ~= ""
	local target = {
		kind = "material", material = material,
		model = hasModel and self.TargetModel or nil,
		slot = hasModel and ( self.MaterialSlots[ index ] or index ) or nil,
		hashes = inspection and inspection.hashes or nil,
	}

	-- A material Remix draws from an enhancement starts from that enhancement:
	-- AME's mod sorts first, so whatever a Save writes replaces it whole, and
	-- starting from the Source material would throw its maps away.
	local base = self:EnhancementBase( index, target.hashes )
	local profile, errors
	if base then profile, errors = schema.NewProfile( target, { pbr = base.pbr } ) end
	if not profile then
		profile, errors = schema.NewProfile( target, self:InspectionSeed( material, inspection ) )
	end
	if not profile then self:SetStatus( ErrorText( errors ), true ) end
	return profile
end

---------------------------------------------------------------------------
-- RTX Remix enhancements (cl_28_rtx_enhance.lua)
---------------------------------------------------------------------------

-- The list marks rows Remix draws from an enhancement before they are opened.
-- Reading hashes Remix has already captured changes nothing; a row it has not
-- drawn yet simply gets its mark when it is opened.
function PANEL:ReadRowHashes()
	self.RowHashes = {}
	if not Bridge or not isfunction( Bridge.ResolveHashes ) then return end
	for listIndex, material in ipairs( self.Materials or {} ) do
		local ok, hashes = pcall( Bridge.ResolveHashes, material )
		if ok and istable( hashes ) and #hashes > 0 then self.RowHashes[ listIndex - 1 ] = hashes end
	end
end

function PANEL:SlotHashes( index )
	local profile = ( self.Working and self.Working[ index ] ) or ( self.Saved and self.Saved[ index ] )
	local target = istable( profile ) and profile.target or {}
	local hashes = target.hashes or ( target.hash and { target.hash } ) or nil
	if not hashes or #hashes == 0 then
		local inspection = self.Inspections and self.Inspections[ index ]
		hashes = istable( inspection ) and inspection.hashes or nil
	end
	if ( not hashes or #hashes == 0 ) and self.RowHashes then hashes = self.RowHashes[ index ] end
	return istable( hashes ) and hashes or {}
end

--- Every mod replacing this row's captured hashes (Enhance.Lookup), cached
--- until the hashes or any mod change.
function PANEL:EnhancementFor( index )
	index = tonumber( index )
	if not Enhance or index == nil then return nil end
	local hashes = self:SlotHashes( index )
	if #hashes == 0 then return nil end

	self.Enhancements = self.Enhancements or {}
	local cached = self.Enhancements[ index ]
	local key = table.concat( hashes, "," )
	if cached and cached.key == key and cached.generation == Enhance.Generation then return cached.result end

	local result = Enhance.Lookup( hashes )
	self.Enhancements[ index ] = { key = key, generation = Enhance.Generation, result = result }
	return result
end

--- The enhancement this row's AME profile builds on, as profile values.
function PANEL:EnhancementBase( index, hashes )
	if not Enhance then return nil end
	local found
	if istable( hashes ) and #hashes > 0 then
		found = Enhance.Lookup( hashes )
	else
		found = self:EnhancementFor( index )
	end
	local entry = found and found.enhancement
	if not entry then return nil end
	local pbr, notes = Enhance.Seed( entry.material )
	return { entry = entry, pbr = pbr, notes = notes, lookup = found }
end

local function ShaderName( material )
	local asset = material and material.shaderAsset
	if not isstring( asset ) or asset == "" then return "AperturePBR_Opacity" end
	local name = string.gsub( asset, "%.mdl$", "" )
	return name
end

--- Read every mod again - after publishing new enhancement files - and start
--- untouched rows that have no AME profile over from what is there now.
function PANEL:RereadEnhancements()
	if not Enhance then return end
	Enhance.Refresh( true )
	self.Enhancements = {}
	self:ReadRowHashes()

	for index = 0, #( self.Materials or {} ) - 1 do
		if self.Working[ index ] and not self.Dirty[ index ] and not self.Saved[ index ]
			and not self.PendingClears[ index ] then
			-- Keep the hashes the row already has even when its inspection
			-- predates them.
			local inspection = Copy( self.Inspections[ index ] or {} )
			if not istable( inspection.hashes ) or #inspection.hashes == 0 then
				inspection.hashes = Copy( self:SlotHashes( index ) )
			end
			local fresh = self:CreateProfile( index, inspection )
			if fresh then
				self.Working[ index ] = fresh
				self:BumpEditRevision( index )
			end
		end
	end

	local count = 0
	for _, record in ipairs( Enhance.Mods or {} ) do count = count + ( record.count or 0 ) end
	if self.Selected ~= nil and self.Working[ self.Selected ] then
		local schema = Schema()
		if schema and schema.EnsureGraph then schema.EnsureGraph( self.Working[ self.Selected ] ) end
		self.SettingGraph = true
		self.Graph:SetGraph( self.Working[ self.Selected ].graph )
		self.SettingGraph = false
		self:BuildSurface()
		self:BuildDiagnostics()
	end
	self:UpdateMarkers()
	self:SetStatus( L( "rtx.enh.reread_done", "Read {{mods}} Remix mod(s) with {{materials}} material(s) in {{ms}} ms.", {
		mods = #( Enhance.Mods or {} ), materials = count, ms = Enhance.LastScanMS or 0,
	} ) )
end

--- Replace the working copy with the enhancement's current values. Its
--- target is kept, so a Save replaces the AME profile it was loaded from.
function PANEL:UseEnhancementValues( index )
	index = tonumber( index ) or self.Selected
	local current = index ~= nil and self.Working[ index ] or nil
	local schema = Schema()
	if not current or not schema then return end

	local fresh = self:CreateProfile( index, self.Inspections[ index ] )
	if not fresh then return end
	fresh.target = Copy( current.target )
	local clean, errors = schema.Sanitize( fresh )
	if not clean then self:SetStatus( ErrorText( errors ), true ) return end

	self:RememberUndo( index )
	self.Working[ index ] = clean
	self:MarkChanged( "enhancement", false, index )
	if index == self.Selected then self:BuildSurface() end
end

--- Open an enhancement's map in the texture editor. The DDS is decoded at
--- this client's texture size and kept as an import, so what comes back is an
--- ordinary edit of a picture from this computer.
function PANEL:EditEnhancementMap( key, value, index )
	local source = MapSource( value )
	local name = Enhance.Describe( source )
	self:SetStatus( L( "rtx.enh.preparing", "Preparing {{file}} for editing…", { file = name } ) )
	Enhance.RequestImage( source, "edit", key, nil, function( path, reason )
		if not IsValid( self ) then return end
		if not path then
			self:SetStatus( L( "rtx.enh.prepare_failed", "Could not read {{file}}: {{reason}}", {
				file = name, reason = tostring( reason or "?" ),
			} ), true )
			return
		end
		self:SetStatus( "" )
		self:EditMap( key, path, index, true )
	end )
end

-- Maps of the working copy that name enhancement files which are gone - the
-- enhancement was regenerated after this AME profile was saved.
function PANEL:MissingEnhancementMaps( pbr )
	local missing = {}
	if not Enhance or not istable( pbr ) then return missing end
	for key, map in pairs( pbr.maps or {} ) do
		local source = MapSource( map )
		if Enhance.IsModTexture( source ) and not Enhance.Exists( source ) then
			missing[ #missing + 1 ] = key
		end
	end
	table.sort( missing )
	return missing
end

function PANEL:AddEnhancementSection( parent, index, pbr )
	local found = self:EnhancementFor( index )
	if not found or ( not found.enhancement and not found.automatic ) then return end

	local entry = found.enhancement or found.automatic
	Section( parent, L( "rtx.enh.title", "RTX Remix enhancement" ) )
	FlatLabel( parent, L( "rtx.enh.source", "{{mod}}  •  {{layer}}  •  {{shader}}", {
		mod = entry.folder, layer = Enhance.LayerName( entry.material ), shader = ShaderName( entry.material ),
	} ), T.Accent )

	local function Note( text, colour, lines )
		local label = FlatLabel( parent, text, colour, AdvMat.RowHeight() * ( lines or 2 ) )
		label:SetAutoStretchVertical( true )
		return label
	end

	if not found.enhancement then
		Note( L( "rtx.enh.automatic",
			"Made automatically by the RTX client's ToPBR pass from the Source material. AME does not start from it, and a Save replaces it." ),
			T.TextDim )
		return
	end

	local saved = self.Saved[ index ] ~= nil
	Note( saved and L( "rtx.enh.overridden",
			"Your AME profile replaces this enhancement. Remove override to return to it." )
		or L( "rtx.enh.active",
			"Remix draws this enhancement. These controls start from it, and a Save keeps every map and value you do not change." ),
		saved and T.Warn or T.TextDim )

	local _, notes = Enhance.Seed( entry.material )
	if entry.material.kind ~= "opaque" then
		Note( L( "rtx.enh.shader_warning",
			"This enhancement is a {{shader}} material. AME writes opaque AperturePBR materials only, so a Save replaces it with an opaque surface.",
			{ shader = ShaderName( entry.material ) } ), T.Danger )
	end
	if #notes.unsupported > 0 then
		Note( L( "rtx.enh.unsupported", "Not kept by a Save (AME has no control for them): {{inputs}}",
			{ inputs = table.concat( notes.unsupported, ", " ) } ), T.Warn )
	end
	if #notes.clamped > 0 then
		Note( L( "rtx.enh.clamped", "Outside AME's range, so a Save changes them: {{inputs}}",
			{ inputs = table.concat( notes.clamped, ", " ) } ), T.Warn )
	end
	if #notes.missing + #notes.foreign > 0 then
		Note( L( "rtx.enh.unreadable_maps", "{{count}} map(s) the enhancement names cannot be used: the file is missing or outside the game folder.",
			{ count = #notes.missing + #notes.foreign } ), T.Warn )
	end

	local missing = self:MissingEnhancementMaps( pbr )
	if #missing > 0 then
		Note( L( "rtx.enh.stale", "This profile names enhancement files that no longer exist ({{maps}}): the enhancement was rebuilt. Use its values to start again from it.",
			{ maps = table.concat( missing, ", " ) } ), T.Danger )
	end

	if Bridge and isfunction( Bridge.HasNativeWriter ) and Bridge.HasNativeWriter() then
		local limits, carried = Bridge.NativeLimits(), 0
		for _, map in pairs( pbr and pbr.maps or {} ) do
			if Enhance.NeedsCarry( MapSource( map ), istable( map ) and map.ops or nil, limits ) then
				carried = carried + 1
			end
		end
		if carried > 0 then
			Note( L( "rtx.enh.carry",
				"{{count}} map(s) cannot go to the installed RTX bridge as they are (over {{limit}} px, in a linked mod folder, or with operations); AME saves decoded copies of them, at most {{copy}} px. The enhancement's own files are not changed.",
				{ count = carried, limit = limits.maxTextureDimension,
					copy = limits.maxDecodedTextureDimension or limits.maxTextureDimension } ), T.TextDim )
		end

		-- An edit of a full-size enhancement map is usually bigger than the
		-- writer decodes; it reaches Remix as a smaller copy.
		local fitted = 0
		for _, map in pairs( pbr and pbr.maps or {} ) do
			local recipe = MapRecipe( map )
			if recipe then
				local _, _, smaller = Bridge.WriterSize( recipe )
				if smaller then fitted = fitted + 1 end
			end
		end
		if fitted > 0 then
			Note( L( "rtx.enh.edit_fit",
				"{{count}} edited map(s) are larger than the installed RTX bridge decodes, so Remix gets copies of them at most {{copy}} px. The edits themselves keep their size.",
				{ count = fitted, copy = limits.maxDecodedTextureDimension } ), T.TextDim )
		end
	end

	local row = parent:Add( "DPanel" )
	row:Dock( TOP )
	row:SetTall( AdvMat.RowHeight() + 6 )
	row:DockMargin( 8, 4, 8, 6 )
	row.Paint = AdvMat.NoPaint

	local reread = row:Add( "DButton" )
	reread:Dock( LEFT )
	reread:SetWide( math.max( 150, math.floor( AdvMat.FontSize * 11 ) ) )
	reread:DockMargin( 0, 0, 6, 0 )
	reread:SetText( L( "rtx.enh.reread", "Re-read enhancements" ) )
	reread:SetTooltip( L( "rtx.enh.reread_tip",
		"Read every mod in rtx-remix/mods again, for example after publishing new enhancement files." ) )
	AdvMat.StyleButton( reread )
	reread.DoClick = function() self:RereadEnhancements() end

	local use = row:Add( "DButton" )
	use:Dock( FILL )
	use:SetText( L( "rtx.enh.use", "Use enhancement values" ) )
	use:SetTooltip( L( "rtx.enh.use_tip",
		"Replace this working copy with the enhancement's current maps and values. Save to keep it; Undo brings your copy back." ) )
	AdvMat.StyleButton( use )
	use.DoClick = function() self:UseEnhancementValues( index ) end
end

function PANEL:AdoptInspectionHashes( index, inspection )
	local hashes = istable( inspection ) and inspection.hashes or nil
	local profile = tonumber( index ) ~= nil and self.Working[ index ] or nil
	if not profile or not istable( hashes ) or #hashes == 0 then return false end
	local target = profile.target or {}
	if istable( target.hashes ) and #target.hashes > 0 or target.hash then return false end
	local wasDirty = self.Dirty[ index ] == true
	local hadSaved = self.Saved[ index ] ~= nil
	local clearPending = self.PendingClears[ index ] == true

	profile = Copy( profile )
	profile.target = Copy( profile.target or {} )
	profile.target.hash = nil
	profile.target.hashes = Copy( hashes )
	local schema = Schema()
	local clean = schema and schema.Sanitize and schema.Sanitize( profile ) or nil
	if not clean then return false end

	-- Hash capture can finish after SelectMaterial has already created a clean,
	-- unsaved fallback profile.  At that point Store.Get can newly resolve this
	-- displayed Source material through its captured hash to a profile owned by
	-- another material name.  Adopt that authoritative global working copy and
	-- its exact CAS token.  Dirty slots adopt only the saved baseline and target;
	-- their edited PBR values and graph remain intact.  A clear in flight keeps
	-- its pre-request state until the clear callback resolves it.
	local adoptedSaved, reseeded, saved, id, etag, ownsCapturedHash
	if not clearPending then
		local material = self.Materials[ index + 1 ]
		saved = Store and Store.Get and Store.Get( material ) or nil
		if Store and Store.GetVersion then id, etag = Store.GetVersion( material ) end
		self.Saved[ index ] = saved and Copy( saved ) or nil
		self.SavedIDs[ index ], self.SavedETags[ index ] = id, etag

		-- Material lookup intentionally prefers a profile already saved under the
		-- displayed Source name.  Such a profile may still be a hashless pending
		-- draft; do not replace the newly captured working copy with it.  A saved
		-- profile is authoritative for this adoption only when it actually owns one
		-- of the hashes that just arrived (including an owner with another name).
		local captured = {}
		for _, hash in ipairs( hashes ) do
			hash = isstring( hash ) and string.lower( string.Trim( hash ) ) or ""
			if hash ~= "" then captured[ hash ] = true end
		end
		local savedTarget = istable( saved ) and saved.target or {}
		local savedHashes = savedTarget.hashes or ( savedTarget.hash and { savedTarget.hash } ) or {}
		ownsCapturedHash = false
		for _, hash in ipairs( savedHashes ) do
			hash = isstring( hash ) and string.lower( string.Trim( hash ) ) or ""
			if captured[ hash ] then ownsCapturedHash = true break end
		end
	end

	if wasDirty or clearPending then
		-- Keep edited PBR values and graph nodes.  If the hash is already owned by
		-- another saved material, only rebase the target so the eventual CAS reaches
		-- that canonical server record instead of attempting to create an alias.
		if saved and ownsCapturedHash then clean.target = Copy( saved.target ) end
		self.Working[ index ] = clean
	elseif saved and ownsCapturedHash then
		self.Working[ index ] = Copy( saved )
		adoptedSaved = true
	else
		-- An untouched row that was never saved was made before Remix had
		-- reported its hash. Now that the hash is known, a row Remix draws
		-- from an enhancement starts again from that enhancement.
		if not hadSaved and not saved and self:EnhancementBase( index, hashes ) then
			local seeded = self:CreateProfile( index, inspection )
			if seeded then
				clean = seeded
				reseeded = true
			end
		end
		self.Working[ index ] = clean
	end
	if saved and not adoptedSaved then hadSaved = true end
	self.EditRevision[ index ] = ( tonumber( self.EditRevision[ index ] ) or 0 ) + 1
	-- A persisted hashless draft becomes saveable as soon as inspection captures
	-- its identity.  A resolved hash-global owner is already saved and therefore
	-- remains clean; an existing dirty marker is preserved verbatim.
	if wasDirty or ( not clearPending and hadSaved and not adoptedSaved ) then
		self.Dirty[ index ] = true
	end
	self:RefreshMaterialAliases()
	self:UpdateMarkers()
	if ( adoptedSaved or reseeded ) and self.Selected == index then
		if schema and schema.EnsureGraph then schema.EnsureGraph( self.Working[ index ] ) end
		if IsValid( self.Graph ) then self.Graph:SetGraph( self.Working[ index ].graph ) end
		self:BuildSurface()
		self:BuildDiagnostics()
	end
	return true
end

function PANEL:SlotOwnershipKey( index )
	index = tonumber( index )
	local material = index ~= nil and self.Materials[ index + 1 ] or nil
	if not material then return nil end
	local id = self.SavedIDs[ index ]
	if not id and Store and Store.GetVersion then id = Store.GetVersion( material ) end
	if isstring( id ) and id ~= "" then return "id:" .. id end

	local profile = self.Working[ index ]
	local target = istable( profile ) and profile.target or {}
	local inspection = self.Inspections[ index ] or {}
	local source = target.hashes or ( target.hash and { target.hash } ) or inspection.hashes or {}
	local hashes, seen = {}, {}
	for _, hash in ipairs( source ) do
		hash = isstring( hash ) and string.lower( string.Trim( hash ) ) or ""
		if hash ~= "" and not seen[ hash ] then
			seen[ hash ] = true
			hashes[ #hashes + 1 ] = hash
		end
	end
	table.sort( hashes )
	return hashes[ 1 ] and ( "hash:" .. hashes[ 1 ] ) or nil
end

function PANEL:CanonicalSlot( index )
	index = tonumber( index )
	local key = index ~= nil and self:SlotOwnershipKey( index ) or nil
	if not key then return index end
	local first, firstDirty
	for candidate = 0, #( self.Materials or {} ) - 1 do
		if self:SlotOwnershipKey( candidate ) == key then
			first = first or candidate
			if self.Dirty[ candidate ] then firstDirty = firstDirty or candidate end
		end
	end
	-- If identity was discovered asynchronously after edits began, preserve the
	-- first dirty working copy as the canonical one instead of hiding it.
	return firstDirty or first or index
end

function PANEL:RefreshMaterialAliases()
	self.MaterialAliases = {}
	for index = 0, #( self.Materials or {} ) - 1 do
		local canonical = self:CanonicalSlot( index )
		if canonical ~= nil and canonical ~= index then self.MaterialAliases[ index ] = canonical end
	end
end

function PANEL:RedirectSharedAlias( index, canonical )
	if canonical == nil or canonical == index then return false end
	self.MaterialAliases[ index ] = canonical
	self:SelectMaterial( canonical, true )
	local line = self.MaterialLines and self.MaterialLines[ canonical ]
	if IsValid( line ) and IsValid( self.MaterialList ) then self.MaterialList:SelectItem( line ) end
	local owner = self.Materials[ canonical + 1 ] or ""
	self:SetStatus( L( "rtx.shared_alias",
		"This row shares one captured RTX material identity. Editing the canonical row instead:" )
		.. " " .. owner, "warning" )
	self:UpdateMarkers()
	return true
end

function PANEL:SelectMaterial( index, forceRTX )
	index = tonumber( index )
	if index == nil or not self.Materials[ index + 1 ] then return end
	-- Hash aliases and duplicate identities are PBR concerns.  Source rules are
	-- attached to the actual model slot, so the Source sheet must be allowed to
	-- select every displayed material without being redirected to an RTX owner.
	if not forceRTX and self:IsSourceTabActive() then
		return self:SelectSourceMaterial( index )
	end
	local canonical = self:CanonicalSlot( index )
	if canonical ~= index and self:RedirectSharedAlias( index, canonical ) then return end
	self.Selected = index
	local material = self.Materials[ index + 1 ]
	self.ActiveMaterial:SetText( material )

	if Store and Store.IsSynced and not Store.IsSynced() then
		self.PendingSelect = index
		if IsValid( self.SaveButton ) then self.SaveButton:SetEnabled( self.AdvMatCanWrite ~= false ) end
		if IsValid( self.ResetButton ) then self.ResetButton:SetEnabled( false ) end
		self:SetStatus( L( "rtx.synchronizing",
			"Synchronizing RTX profiles from the server…" ), "warning" )
		if Store.RequestSync then
			local requested, reason = Store.RequestSync()
			if requested == false and reason then
				self:SetStatus( L( "rtx.sync_blocked",
					"RTX profiles cannot synchronize until native owned state is reset: {{reason}}",
					{ reason = tostring( reason ) } ), true )
			end
		end
		-- Inspection/local saved work is usable while the snapshot is arriving.
		-- A Save retains this exact baseline; server CAS still rejects conflicts.
	end
	self.PendingSelect = nil

	local inspection = self.Inspections[ index ]
	if not inspection and Bridge and Bridge.Inspect then
		inspection = Bridge.Inspect( material, function( result )
			if not IsValid( self ) then return end
			self.Inspections[ index ] = result
			self:AdoptInspectionHashes( index, result )
			if self.Selected == index then self:BuildDiagnostics() end
		end )
		self.Inspections[ index ] = inspection
	end
	canonical = self:CanonicalSlot( index )
	if canonical ~= index and self:RedirectSharedAlias( index, canonical ) then return end

	if not self.Working[ index ] then
		local saved = Store and Store.Get and Store.Get( material ) or nil
		self.Saved[ index ] = saved and Copy( saved ) or nil
		if Store and Store.GetVersion then
			self.SavedIDs[ index ], self.SavedETags[ index ] = Store.GetVersion( material )
		end
		self.Working[ index ] = saved or self:CreateProfile( index, inspection )
	end

	local profile = self.Working[ index ]
	if not profile then return end
	local schema = Schema()
	if schema and schema.EnsureGraph then schema.EnsureGraph( profile ) end
	self.Graph:SetGraph( profile.graph )
	self:BuildSurface()
	self:BuildDiagnostics()
	self:UpdateMarkers()
	if Store and Store.GetSyncState then
		local status, reason = Store.GetSyncState( material )
		if status == "pending" then
			self:SetStatus( L( "rtx.local_saved", "Saved locally. Syncing in the background…" ) )
		elseif status == "failed" then
			self:SetStatus( L( "rtx.background_failed",
				"Server sync failed for {{material}}: {{reason}}. Your local changes are retained; Save to retry.",
				{ material = material, reason = tostring( reason or "" ) } ), true )
		end
	end
end

-- Compatibility contract used by the shared texture/generator dialogs.  The
-- RTX editor owns its target for the whole window lifetime just as the vanilla
-- editor does, but its working copy is a PBR profile rather than VMT params.
function PANEL:GetWorking( index, create )
	index = tonumber( index ) or self.Selected
	if index == nil then return nil end
	if not self.Working[ index ] and create then self:SelectMaterial( index, true ) end
	return self.Working[ index ]
end

function PANEL:RememberUndo( index )
	index = tonumber( index ) or self.Selected
	local profile = index ~= nil and self.Working[ index ] or nil
	if not profile then return end
	local stack = self.Undo[ index ] or {}
	local now = RealTime()
	local last = self.LastUndoAt[ index ]
	if not last or now - last > 0.3 then
		stack[ #stack + 1 ] = Copy( profile )
		if #stack > 40 then table.remove( stack, 1 ) end
		self.Undo[ index ] = stack
		self.LastUndoAt[ index ] = now
	end
end

function PANEL:BumpEditRevision( index )
	index = tonumber( index )
	if index == nil then return 0 end
	local revision = ( tonumber( self.EditRevision[ index ] ) or 0 ) + 1
	self.EditRevision[ index ] = revision
	return revision
end

function PANEL:GetEditRevision( index )
	index = tonumber( index )
	if index == nil then return 0 end
	return tonumber( self.EditRevision[ index ] ) or 0
end

function PANEL:UndoSelected()
	if self:IsSourceTabActive() and IsValid( self.SourcePanel ) then
		return self.SourcePanel:UndoSelected()
	end
	return self:UndoRTXSelected()
end

function PANEL:UndoRTXSelected()
	local index = self.Selected
	local stack = index ~= nil and self.Undo[ index ] or nil
	if not stack or #stack == 0 then return end
	self.Working[ index ] = table.remove( stack )
	self.LastUndoAt[ index ] = nil
	self:BumpEditRevision( index )
	self.Dirty[ index ] = true
	self.Graph:SetGraph( self.Working[ index ].graph )
	self:BuildSurface()
	self:UpdateMarkers()
	self:QueuePreview()
end

function PANEL:MutateConstant( key, value )
	local index = self.Selected
	local profile = index ~= nil and self.Working[ index ] or nil
	local schema = Schema()
	if not profile or not schema then return end
	self:RememberUndo()
	local updated, errors = schema.SetConstant( profile, key, value )
	if not updated then self:SetStatus( ErrorText( errors ), true ) return end
	self.Working[ index ] = updated
	self:MarkChanged( "constant" )
end

--- `normalEncoding`, when given, is set in the same step: the encoding of the
--- normal map just installed, when AME knows it (KnownNormalEncoding).
function PANEL:MutateMapAt( index, key, value, normalEncoding )
	index = tonumber( index )
	local profile = index ~= nil and self.Working[ index ] or nil
	local schema = Schema()
	if not profile or not schema then return end
	self:RememberUndo( index )
	local updated, errors = schema.SetMap( profile, key, value )
	if not updated then self:SetStatus( ErrorText( errors ), true ) return end
	if normalEncoding then updated.pbr.options.normal_encoding = normalEncoding end
	self.Working[ index ] = updated
	self:MarkChanged( "map", false, index )
	if index == self.Selected then self:BuildSurface() end
end

function PANEL:MutateMap( key, value )
	return self:MutateMapAt( self.Selected, key, value )
end

function PANEL:MutateOption( key, value )
	local index = self.Selected
	local profile = index ~= nil and self.Working[ index ] or nil
	local schema = Schema()
	if not profile or not schema then return end
	self:RememberUndo()
	profile = Copy( profile )
	profile.pbr = profile.pbr or {}
	profile.pbr.options = profile.pbr.options or {}
	profile.pbr.options[ key ] = value
	local clean, errors = schema.Sanitize( profile )
	if not clean then self:SetStatus( ErrorText( errors ), true ) return end
	self.Working[ index ] = clean
	self:MarkChanged( "option" )
	if key == "blend_enabled" or key == "blend_type" then
		timer.Simple( 0, function()
			if IsValid( self ) and self.Selected == index then self:BuildSurface() end
		end )
	end
end

function PANEL:GraphChanged( graph, reason )
	if self.SettingGraph or self.HandlingGraphChange then return end
	local index = self.Selected
	local profile = index ~= nil and self.Working[ index ] or nil
	local schema = Schema()
	if not profile or not schema then return end
	self.HandlingGraphChange = true
	self:RememberUndo()
	profile = Copy( profile )
	profile.graph = graph
	local clean, errors = schema.Sanitize( profile )
	if not clean then
		self.HandlingGraphChange = false
		self:SetStatus( ErrorText( errors ), true )
		return
	end
	self.Working[ index ] = clean
	self:MarkChanged( reason or "graph", true )
	-- Surface widgets are a view of the compiled graph.  Rebuild them after the
	-- working copy changes; BuildingSurface suppresses their initialization
	-- callbacks, and fromGraph prevents a SetGraph callback loop.
	self:BuildSurface()
	self.HandlingGraphChange = false
end

function PANEL:MarkChanged( reason, fromGraph, changedIndex )
	local index = tonumber( changedIndex ) or self.Selected
	if index == nil then return end
	self:BumpEditRevision( index )
	self.Dirty[ index ] = true
	self:UpdateMarkers()
	if index ~= self.Selected then return end
	self:SetStatus( L( "rtx.unsaved", "Unsaved RTX material changes" ) )
	if not fromGraph and IsValid( self.Graph ) then
		self.SettingGraph = true
		self.Graph:SetGraph( self.Working[ index ].graph )
		self.SettingGraph = false
	end
	self:QueuePreview()
end

function PANEL:QueuePreview()
	if not self.LivePreview or not self.RTXCapabilities
		or self.RTXCapabilities.livePreview ~= true
		or self.Selected == nil or not Store or not Store.Preview then return end
	local profile = self.Working[ self.Selected ]
	if not profile then return end
	local material = MaterialName( profile )
	if material ~= "" then self.PreviewedMaterials[ material ] = true end
	Store.Preview( profile, function( ok, result )
		if not IsValid( self ) or ok then return end
		if istable( result ) and result.exportOnly then return end
		if istable( result ) and result.status ~= "superseded" and result.status ~= "queued" then
			self:SetStatus( tostring( result.error or result.status ), true )
		end
	end )
end

function PANEL:EffectivePBR( index )
	index = tonumber( index ) or self.Selected
	local profile = index ~= nil and self.Working[ index ] or nil
	local schema = Schema()
	if not profile or not schema then return nil end
	local pbr, errors = schema.GetEffectivePBR( profile )
	if not pbr then self:SetStatus( ErrorText( errors ), true ) end
	return pbr
end

function PANEL:AddSlider( parent, key, text, value, lo, hi, decimals )
	local slider = parent:Add( "DNumSlider" )
	slider:Dock( TOP )
	slider:SetTall( AdvMat.RowHeight() + 10 )
	slider:DockMargin( 8, 2, 8, 2 )
	slider:SetText( text )
	slider:SetMinMax( lo, hi )
	slider:SetDecimals( decimals or 3 )
	slider:SetValue( value )
	AdvMat.StyleSlider( slider )
	local ready = true
	slider.OnValueChanged = function( _, nextValue )
		if ready and not self.BuildingSurface then self:MutateConstant( key, tonumber( nextValue ) or value ) end
	end
	return slider
end

function PANEL:AddColour( parent, key, text, value )
	Section( parent, text )
	local mixer = parent:Add( "DColorMixer" )
	mixer:Dock( TOP )
	mixer:SetTall( 155 )
	mixer:DockMargin( 8, 4, 8, 8 )
	mixer:SetPalette( false )
	mixer:SetAlphaBar( false )
	mixer:SetWangs( true )
	mixer:SetColor( Color( value.r * 255, value.g * 255, value.b * 255 ) )
	mixer.ValueChanged = function( _, colour )
		if self.BuildingSurface then return end
		self:MutateConstant( key,
			{ r = colour.r / 255, g = colour.g / 255, b = colour.b / 255 } )
	end
end

function PANEL:AddBooleanOption( parent, key, text, value, onChanged )
	local check = parent:Add( "DCheckBoxLabel" )
	check:Dock( TOP )
	check:DockMargin( 8, 3, 8, 3 )
	check:SetValue( value and 1 or 0 )
	AdvMat.StyleCheck( check, text )
	check.OnChange = function( _, enabled )
		if self.BuildingSurface then return end
		self:MutateOption( key, enabled )
		if onChanged then onChanged( enabled ) end
	end
	return check
end

function PANEL:AddEmissionControls( parent, pbr )
	Section( parent, L( "rtx.emission", "Emission" ) )
	local hint
	local function UpdateHint( enabled )
		if not IsValid( hint ) then return end
		hint:SetText( enabled
			and L( "rtx.emission_enabled_hint", "Emission is on. Turning it off keeps the settings below." )
			or L( "rtx.emission_disabled_hint", "Emission is off. Enable it above to use the map, colour and intensity below." ) )
		hint:SetTextColor( enabled and T.TextDim or T.Warn )
	end
	self:AddBooleanOption( parent, "enable_emission",
		L( "rtx.enable_emission", "Enable emission" ), pbr.options.enable_emission, UpdateHint )
	hint = FlatLabel( parent, "" )
	hint:SetAutoStretchVertical( true )
	UpdateHint( pbr.options.enable_emission )
	-- Keep this gate beside everything it controls, not in the later options
	-- list. Values remain editable while off; never silently enable emission.
	self:AddMapRow( parent, EMISSION_MAP, pbr.maps.emissive )
	self:AddColour( parent, "emissive_color", L( "rtx.emission_colour", "Emission colour" ),
		pbr.constants.emissive_color )
	self:AddSlider( parent, "emissive_intensity",
		L( "rtx.emission_strength", "Emission intensity" ),
		pbr.constants.emissive_intensity, 0, 65504, 2 )
end

function PANEL:AddMapRow( parent, spec, value )
	local index = self.Selected
	local displaySource = self:DisplayMapSource( index, spec.key, value )
	local previewSource = self:MapPreviewSource( index, spec.key, value )
	local inherited = value == nil and displaySource ~= ""
	local rowTall = AdvMat.TextureRowHeight()
	-- A full row-height thumbnail plus four side-by-side buttons left almost no
	-- path field in the 820 px side-inspector layout. Keep the thumbnail useful,
	-- but cap it and put the actions on a second line under a full-width path.
	local previewWide = math.Clamp( math.floor( AdvMat.FontSize * 3 ), 48, 64 )
	local labelWide = math.Clamp( math.floor( AdvMat.FontSize * 7 ), 104, 150 )
	local row = parent:Add( "DPanel" )
	row:Dock( TOP )
	row:SetTall( rowTall )
	row:DockMargin( 0, 0, 0, 1 )
	row.Paint = AdvMat.Fill( T.Row )

	local labelColumn = row:Add( "DPanel" )
	labelColumn:Dock( LEFT )
	labelColumn:SetWide( labelWide )
	labelColumn:DockMargin( 8, 0, 4, 0 )
	labelColumn.Paint = AdvMat.NoPaint

	local labelText = L( "rtx.map." .. spec.key, spec.label )
	local label = labelColumn:Add( "DLabel" )
	label:Dock( TOP )
	label:SetTall( AdvMat.RowHeight() + 3 )
	label:SetText( labelText )
	label:SetTooltip( labelText )
	AdvMat.StyleLabel( label, "AdvMatBold",
		value and T.Accent or ( inherited and T.Text or T.TextDim ) )

	local enhancementMap = Enhance and not MapRecipe( value ) and Enhance.IsModTexture( displaySource )
	if istable( value ) and value.generated and not enhancementMap then
		local generatedText = L( "rtx.map.generated", "Generated / edited map" )
		local generated = labelColumn:Add( "DLabel" )
		generated:Dock( TOP )
		generated:SetTall( AdvMat.RowHeight() )
		generated:SetText( generatedText )
		generated:SetTooltip( generatedText )
		AdvMat.StyleLabel( generated, "AdvMatSmall", T.Warn )
	elseif enhancementMap then
		-- A file from an enhancement mod. Its size and format say whether the
		-- installed writer takes it as it is or gets a decoded copy.
		local info = Enhance.DDSInfo( displaySource )
		local fromText = L( "rtx.enh.from", "From {{mod}}", { mod = Enhance.ModOf( displaySource ) } )
		local from = labelColumn:Add( "DLabel" )
		from:Dock( TOP )
		from:SetTall( AdvMat.RowHeight() )
		from:SetText( fromText )
		from:SetTooltip( Enhance.Describe( displaySource ) .. ( info
			and string.format( "\n%d x %d  %s", info.width, info.height, string.upper( info.format ) ) or "" ) )
		AdvMat.StyleLabel( from, "AdvMatSmall", Color( 128, 224, 170 ) )
	end

	-- Match vanilla texture rows: show the texture beside its path, including
	-- the inherited Source albedo and locally generated data/*.png outputs.
	-- This panel never mutates the profile, so merely viewing an inherited map
	-- cannot accidentally author an RTX replacement.
	local preview = row:Add( "DPanel" )
	preview:Dock( LEFT )
	preview:SetWide( previewSource ~= "" and previewWide or 0 )
	preview:DockMargin( previewSource ~= "" and 2 or 0, 4, 2, 4 )
	preview:SetVisible( previewSource ~= "" )
	preview:SetTooltip( previewSource )
	-- An enhancement's DDS cannot be loaded by the engine; its preview is a
	-- decoded small mip that arrives a few frames later.
	local previewEnhancement = Enhance and Enhance.IsModTexture( previewSource )
	local previewMaterial = not previewEnhancement and self:MapPreviewMaterial( previewSource ) or nil
	preview.Paint = function( _, w, h )
		surface.SetDrawColor( 25, 25, 28, 255 )
		surface.DrawRect( 0, 0, w, h )

		if not previewMaterial and previewEnhancement then
			previewMaterial = Enhance.ThumbnailMaterial( previewSource, spec.key )
		end
		if not previewMaterial then return end
		surface.SetDrawColor( 255, 255, 255, 255 )
		surface.SetMaterial( previewMaterial )
		surface.DrawTexturedRect( 1, 1, math.max( 0, w - 2 ), math.max( 0, h - 2 ) )
	end

	-- Edge-docked columns must be created before this FILL child; see
	-- dev/check_dock.py. Inside it, the path takes the top line and the compact
	-- action strip consumes the remaining height.
	local content = row:Add( "DPanel" )
	content:Dock( FILL )
	content.Paint = AdvMat.NoPaint

	local path = content:Add( "DTextEntry" )
	path:Dock( TOP )
	path:SetTall( AdvMat.RowHeight() + 2 )
	path:DockMargin( 4, 4, 4, 2 )
	path:SetPlaceholderText( L( "rtx.map.empty", "DDS/image path, or use Edit for a Source VTF" ) )
	path:SetValue( displaySource )
	AdvMat.StyleEntry( path )
	path.OnEnter = function( field )
		local entered = string.Trim( field:GetValue() or "" )
		if entered == displaySource then return end
		self:MutateMapAt( index, spec.key, entered )
	end
	path.OnLoseFocus = path.OnEnter

	local actions = content:Add( "DPanel" )
	actions:Dock( FILL )
	actions:DockMargin( 4, 0, 4, 4 )
	actions.Paint = AdvMat.NoPaint
	local buttons = {}
	local function AddAction( text, tooltip, callback, danger )
		local button = actions:Add( "DButton" )
		button:SetText( text )
		button:SetTooltip( tooltip or text )
		button.DoClick = callback
		AdvMat.StyleButton( button, danger )
		buttons[ #buttons + 1 ] = button
		return button
	end

	AddAction( "…", L( "row.browse", "Browse for a texture" ), function()
		AdvMat.OpenTexturePicker( displaySource, function( selected )
			if not IsValid( self ) then return end
			-- The shared picker's Clear button returns an empty string. Mirror this
			-- row's own Clear button before classifying file types; otherwise an empty
			-- selection would reopen the inherited Source texture for materialisation.
			if selected == "" then
				self:MutateMapAt( index, spec.key, nil )
				return
			end
			-- GMod's picker normally returns a logical VTF name.  Remix USDA needs
			-- a real image/DDS file, so route logical Source textures through the
			-- editor, which materialises a portable PNG recipe.  Explicit file
			-- paths can be stored directly.
			local extension = string.match( string.lower( selected or "" ), "%.([%w]+)$" )
			local isFile = extension == "dds" or extension == "png"
				or extension == "jpg" or extension == "jpeg" or extension == "bmp"
				or extension == "tif" or extension == "tiff" or extension == "gif"
			if isFile then
				self:MutateMapAt( index, spec.key, selected )
			else
				self:EditMap( spec.key, selected, index, true )
			end
		end )
	end )

	if spec.normal then
		AddAction( L( "common.make", "Make" ), L( "row.make_tip",
			"Build this map automatically from another texture" ),
			function() self:GenerateNormalMap( value, index ) end )
	end

	AddAction( L( "common.edit", "Edit" ), L( "row.edit_tip",
		"Paint on this texture, recolour part of it, or cut a hole in it" ),
		function() self:EditMap( spec.key, value, index ) end )

	local clearText = L( "common.clear", "Clear" )
	local clear = AddAction( clearText, clearText,
		function() self:MutateMapAt( index, spec.key, nil ) end, true )
	clear:SetEnabled( value ~= nil )

	actions.PerformLayout = function( _, wide, tall )
		local count = #buttons
		if count == 0 then return end
		local gap = 4
		local available = math.max( count, wide - gap * ( count - 1 ) )
		local browseWide = count == 1 and available or math.Clamp(
			math.floor( AdvMat.FontSize * 2.2 ), 34,
			math.max( 34, math.floor( available * 0.25 ) ) )
		local regularCount = math.max( 1, count - 1 )
		local regularWide = math.max( 1,
			math.floor( ( available - browseWide ) / regularCount ) )
		local x = 0
		for buttonIndex, button in ipairs( buttons ) do
			local buttonWide = buttonIndex == 1 and browseWide or regularWide
			if buttonIndex == count then buttonWide = math.max( 1, wide - x ) end
			button:SetPos( x, 0 )
			button:SetSize( buttonWide, tall )
			x = x + buttonWide + gap
		end
	end
end

function PANEL:BuildSurface()
	if not IsValid( self.Surface ) then return end
	self.Surface:Clear()
	local pbr = self:EffectivePBR()
	if not pbr then return end
	self.BuildingSurface = true

	local intro = FlatLabel( self.Surface,
		L( "rtx.surface_intro",
			"Physically based controls. Maps override their matching constants; the Shader graph remains authoritative." ),
		T.TextDim, AdvMat.RowHeight() * 2 )
	intro:SetContentAlignment( 4 )

	self:AddEnhancementSection( self.Surface, self.Selected, pbr )

	Section( self.Surface, L( "rtx.maps", "PBR texture maps" ) )
	for _, spec in ipairs( MAPS ) do self:AddMapRow( self.Surface, spec, pbr.maps[ spec.key ] ) end

	self:AddColour( self.Surface, "albedo", L( "rtx.base_colour", "Base colour multiplier" ),
		pbr.constants.albedo )
	Section( self.Surface, L( "rtx.surface_values", "Surface response" ) )
	self:AddSlider( self.Surface, "roughness", L( "rtx.roughness", "Roughness" ),
		pbr.constants.roughness, 0, 1, 3 )
	self:AddSlider( self.Surface, "metallic", L( "rtx.metallic", "Metallic" ),
		pbr.constants.metallic, 0, 1, 3 )
	self:AddSlider( self.Surface, "opacity", L( "rtx.opacity", "Opacity" ),
		pbr.constants.opacity, 0, 1, 3 )
	self:AddSlider( self.Surface, "anisotropy", L( "rtx.anisotropy", "Anisotropy" ),
		pbr.constants.anisotropy, -1, 1, 3 )
	self:AddSlider( self.Surface, "thin_film_thickness",
		L( "rtx.thin_film", "Thin-film thickness (nm)" ),
		pbr.constants.thin_film_thickness, 0, 1500, 1 )
	Section( self.Surface, L( "rtx.displacement", "Displacement" ) )
	self:AddSlider( self.Surface, "displace_in", L( "rtx.displace_in", "Displacement inward" ),
		pbr.constants.displace_in, 0, 0.2, 4 )
	self:AddSlider( self.Surface, "displace_out", L( "rtx.displace_out", "Displacement outward" ),
		pbr.constants.displace_out, 0, 0.2, 4 )

	self:AddEmissionControls( self.Surface, pbr )

	Section( self.Surface, L( "rtx.subsurface", "Subsurface" ) )
	self:AddColour( self.Surface, "subsurface_transmittance_color",
		L( "rtx.subsurface_transmittance_color", "Transmittance colour" ),
		pbr.constants.subsurface_transmittance_color )
	self:AddSlider( self.Surface, "subsurface_measurement_distance",
		L( "rtx.subsurface_measurement_distance", "Measurement distance" ),
		pbr.constants.subsurface_measurement_distance, 0, 16, 3 )
	self:AddColour( self.Surface, "subsurface_single_scattering_albedo",
		L( "rtx.subsurface_single_scattering_albedo", "Single-scattering albedo" ),
		pbr.constants.subsurface_single_scattering_albedo )
	self:AddSlider( self.Surface, "subsurface_volumetric_anisotropy",
		L( "rtx.subsurface_volumetric_anisotropy", "Volumetric anisotropy" ),
		pbr.constants.subsurface_volumetric_anisotropy, -0.99, 0.99, 3 )
	self:AddColour( self.Surface, "subsurface_radius",
		L( "rtx.subsurface_radius", "Subsurface-scattering radius" ),
		pbr.constants.subsurface_radius )
	self:AddSlider( self.Surface, "subsurface_radius_scale",
		L( "rtx.subsurface_radius_scale", "Subsurface radius scale" ),
		pbr.constants.subsurface_radius_scale, 0, 1000, 2 )
	self:AddSlider( self.Surface, "subsurface_max_sample_radius",
		L( "rtx.subsurface_max_sample_radius", "Maximum sample radius" ),
		pbr.constants.subsurface_max_sample_radius, 0, 65504, 1 )

	self:AddOptionControls( self.Surface, pbr.options )
	self.BuildingSurface = false
end

function PANEL:AddOptionControls( parent, options )
	local function Combo( labelText, key, choices, tooltip )
		local row = parent:Add( "DPanel" )
		row:Dock( TOP )
		row:SetTall( AdvMat.RowHeight() + 5 )
		row:DockMargin( 8, 2, 8, 2 )
		row.Paint = AdvMat.NoPaint
		local label = row:Add( "DLabel" )
		label:Dock( LEFT )
		label:SetWide( 220 )
		label:SetText( labelText )
		AdvMat.StyleLabel( label, "AdvMatText", T.Text )
		local combo = row:Add( "DComboBox" )
		combo:Dock( FILL )
		if tooltip then
			label:SetTooltip( tooltip )
			combo:SetTooltip( tooltip )
		end
		local selected = options[ key ]
		combo:SetValue( L( "rtx.option." .. selected, selected ) )
		for _, value in ipairs( choices ) do
			combo:AddChoice( L( "rtx.option." .. value, value ), value )
		end
		AdvMat.StyleCombo( combo )
		combo.OnSelect = function( _, _, _, value )
			if not self.BuildingSurface then self:MutateOption( key, value ) end
		end
	end
	local function IntegerOption( labelText, key, minimum, maximum, fallback )
		local slider = parent:Add( "DNumSlider" )
		slider:Dock( TOP )
		slider:SetTall( AdvMat.RowHeight() + 8 )
		slider:DockMargin( 8, 2, 8, 2 )
		slider:SetText( labelText )
		slider:SetMinMax( minimum, maximum )
		slider:SetDecimals( 0 )
		slider:SetValue( options[ key ] or fallback )
		AdvMat.StyleSlider( slider )
		slider.OnValueChanged = function( _, value )
			if self.BuildingSurface then return end
			self:MutateOption( key, math.floor( tonumber( value ) or fallback ) )
		end
	end
	local function BooleanOption( labelText, key )
		return self:AddBooleanOption( parent, key, labelText, options[ key ] )
	end

	Section( parent, L( "rtx.base_material", "Base material" ) )
	Combo( L( "rtx.normal_encoding", "Normal-map encoding" ), "normal_encoding",
		{ "octahedral", "tangent_space_ogl", "tangent_space_dx" },
		L( "rtx.normal_encoding_tip",
			"How the normal map picture is drawn. RTX Remix reads only octahedral normal maps, so a DirectX or OpenGL picture is converted when it is applied. AME's own normal maps, like Source's, are DirectX." ) )

	Section( parent, L( "rtx.iridescence", "Iridescence" ) )
	BooleanOption( L( "rtx.enable_thin_film", "Enable thin film" ), "enable_thin_film" )
	BooleanOption( L( "rtx.alpha_thin_film", "Use alpha as thin-film thickness" ),
		"alpha_is_thin_film" )

	Section( parent, L( "rtx.animation", "Animation" ) )
	IntegerOption( L( "rtx.sprite_sheet_rows", "Sprite-sheet rows" ),
		"sprite_sheet_rows", 1, 255, 1 )
	IntegerOption( L( "rtx.sprite_sheet_columns", "Sprite-sheet columns" ),
		"sprite_sheet_columns", 1, 255, 1 )
	IntegerOption( L( "rtx.sprite_sheet_fps", "Sprite-sheet frames per second" ),
		"sprite_sheet_fps", 0, 255, 0 )

	Section( parent, L( "rtx.remix_flags", "Remix flags" ) )
	BooleanOption( L( "rtx.preload_textures", "Preload textures" ), "preload_textures" )
	BooleanOption( L( "rtx.ignore_material", "Ignore material" ), "ignore_material" )

	Section( parent, L( "rtx.alpha_blending", "Alpha blending" ) )
	BooleanOption( L( "rtx.draw_alpha", "Use captured draw-call alpha state" ),
		"use_draw_call_alpha" )
	BooleanOption( L( "rtx.blend_enabled", "Enable alpha blending" ), "blend_enabled" )
	Combo( L( "rtx.blend", "Blend mode" ), "blend_type",
		{
			"alpha", "alpha_emissive", "reverse_alpha_emissive",
			"color", "color_emissive", "reverse_color_emissive", "emissive",
			"multiplicative", "double_multiplicative",
		} )
	BooleanOption( L( "rtx.inverted_blend", "Invert blend" ), "inverted_blend" )
	Combo( L( "rtx.alpha_test", "Alpha test" ), "alpha_test_type",
		{ "none", "never", "less", "equal", "less_equal", "greater", "not_equal", "greater_equal" } )

	local slider = parent:Add( "DNumSlider" )
	slider:Dock( TOP )
	slider:SetTall( AdvMat.RowHeight() + 8 )
	slider:DockMargin( 8, 2, 8, 2 )
	slider:SetText( L( "rtx.alpha_reference", "Alpha reference" ) )
	slider:SetMinMax( 0, 1 )
	slider:SetDecimals( 3 )
	slider:SetValue( options.alpha_reference )
	AdvMat.StyleSlider( slider )
	slider.OnValueChanged = function( _, value )
		if not self.BuildingSurface then
			self:MutateOption( "alpha_reference", tonumber( value ) or options.alpha_reference or 0 )
		end
	end

	Section( parent, L( "rtx.filtering", "Filtering" ) )
	Combo( L( "rtx.filter", "Texture filtering" ), "filter_mode",
		{ "nearest", "linear" } )
	Combo( L( "rtx.wrap_u", "Horizontal wrapping" ), "wrap_u",
		{ "repeat", "mirror", "clamp", "clip" } )
	Combo( L( "rtx.wrap_v", "Vertical wrapping" ), "wrap_v",
		{ "repeat", "mirror", "clamp", "clip" } )

	Section( parent, L( "rtx.subsurface", "Subsurface" ) )
	BooleanOption( L( "rtx.subsurface_diffusion_profile", "Enable diffusion profile" ),
		"subsurface_diffusion_profile" )
end

function PANEL:TextureContext( key, index )
	index = tonumber( index ) or self.Selected
	local material = index ~= nil and self.Materials[ index + 1 ] or ""
	local pbr = self:EffectivePBR( index )
	local source = pbr and MapSource( pbr.maps[ key ] ) or ""
	if source == "" then source = self:InspectionMapSource( index, key ) end
	local basekv = {}
	if AdvMat.Apply and AdvMat.Apply.ReadBase then
		basekv = AdvMat.Apply.ReadBase( material ) or {}
	end
	return {
		host = self, src = source,
		model = self.TargetModel, matpath = material,
		slot = self.MaterialSlots[ index ] or index,
		shader = "VertexLitGeneric", basekv = basekv or {}, param = "$basetexture",
		rtx = true,
	}
end

function PANEL:UseRecipe( key, recipe, normalFromHeight, index )
	if not istable( recipe ) then return end
	index = tonumber( index ) or self.Selected
	local source = RecipeMapSource( recipe )
	if source == "" then
		self:SetStatus( L( "rtx.generated_path_failed",
			"Could not derive a safe path for the generated texture." ), true )
		return
	end
	local descriptor = {
		source = source,
		generated = true,
		ops = normalFromHeight and {
			{ op = "normal_from_height", strength = tonumber( recipe.strength ) or 1,
				channel = recipe.channel or "luminance" },
		} or {},
		recipe = recipe,
	}
	-- A normal-from-height bake's recipe is its height map, not a normal map.
	self:MutateMapAt( index, key, descriptor,
		key == "normal" and not normalFromHeight and KnownNormalEncoding( recipe ) or nil )
end

function PANEL:EditMap( key, value, index, sourceCopy )
	index = tonumber( index ) or self.Selected
	if Enhance and not MapRecipe( value ) and Enhance.IsModTexture( MapSource( value ) ) then
		return self:EditEnhancementMap( key, value, index )
	end
	local ctx = self:TextureContext( key, index )
	local selectedSource = MapSource( value )
	if selectedSource ~= "" then ctx.src = selectedSource end
	ctx.sourcecopy = sourceCopy == true
	local recipe = MapRecipe( value )
	local recipeKind
	if AdvMat.Gen and isfunction( AdvMat.Gen.KindOf ) then
		local ignored
		ignored, recipeKind = AdvMat.Gen.KindOf( recipe )
	end
	if key == "normal" and recipeKind == "normal" and AdvMat.OpenNormalGenerator then
		self:GenerateNormalMap( value, index )
		return
	end
	AdvMat.OpenTextureEditor( "$basetexture", recipe, ctx, function( edited )
		if IsValid( self ) then self:UseRecipe( key, edited, false, index ) end
	end )
end

function PANEL:GenerateNormalMap( current, index )
	if not AdvMat.OpenNormalGenerator then return end
	index = tonumber( index ) or self.Selected
	local pbr = self:EffectivePBR( index )
	local normalRecipe = MapRecipe( current )
	local albedo = pbr and pbr.maps.albedo or nil
	local function OpenGenerator( source, recipe )
		if not IsValid( self ) then return end
		local ctx = self:TextureContext( "normal", index )
		AdvMat.OpenNormalGenerator( source, recipe, function( generated )
			if IsValid( self ) then self:UseRecipe( "normal", generated, false, index ) end
		end, ctx )
	end
	if not normalRecipe then
		local finished = false
		local handled = MaterializeRecipeSource( MapRecipe( albedo ),
			function( generatedSource, albedoRecipe, reason )
				finished = true
				if not IsValid( self ) then return end
				if not generatedSource then
					self:SetStatus( "Could not prepare the edited base-colour map: "
						.. tostring( reason or "generation failed" ), true )
					return
				end
				OpenGenerator( generatedSource, {
					kind = "normal", src = generatedSource,
					size = albedoRecipe.size, height = albedoRecipe.height,
				} )
			end )
		if handled then
			if not finished then
				self:SetStatus( "Preparing the edited base-colour map for normal generation…" )
			end
			return
		end
	end
	local source = ""
	if source == "" then source = MapSource( albedo ) end
	-- The generator reads its source through the engine, which cannot load an
	-- enhancement's DDS. The Source base texture is the same picture.
	if Enhance and Enhance.IsModTexture( source ) then
		source = ""
		self:SetStatus( L( "rtx.enh.normal_source",
			"The normal map is made from the Source base texture: the enhancement's albedo is a DDS file the generator cannot read." ),
			"warning" )
	end
	if source == "" then source = self:InspectionMapSource( index, "albedo" ) end
	if source == "" then source = MapSource( current ) end
	OpenGenerator( source, normalRecipe )
end

function PANEL:EditTextureNode( nodeID, sourceOverride )
	if istable( nodeID ) then nodeID = nodeID.id end
	if not isstring( nodeID ) then return end
	local index = self.Selected
	local profile = index ~= nil and self.Working[ index ] or nil
	if not profile or not profile.graph then return end
	local node
	for _, candidate in ipairs( profile.graph.nodes or {} ) do
		if candidate.id == nodeID then node = candidate break end
	end
	local draftNode, draftLinks
	if not node and self.Selected == index and IsValid( self.Graph )
		and isfunction( self.Graph.GetGraph ) then
		local canvasGraph = self.Graph:GetGraph()
		for _, candidate in ipairs( canvasGraph and canvasGraph.nodes or {} ) do
			if candidate.id == nodeID then
				draftNode = Copy( candidate )
				node = candidate
				break
			end
		end
		if draftNode then
			draftLinks = {}
			for _, link in ipairs( canvasGraph and canvasGraph.links or {} ) do
				if link.from and link.to
					and ( link.from.node == nodeID or link.to.node == nodeID ) then
					draftLinks[ #draftLinks + 1 ] = Copy( link )
				end
			end
		end
	end
	if not node or node.type ~= "texture" or not node.params then return end

	local key = string.match( nodeID, "^advmat_direct_m_([%w_]+)" )
		or self:MapKeyForNode( nodeID, index ) or "albedo"
	local replacementSource = isstring( sourceOverride ) and sourceOverride ~= ""
		and sourceOverride or nil

	-- A node naming an enhancement's DDS is edited through a decoded copy,
	-- exactly like the map row's Edit button.
	if not replacementSource and Enhance and not node.params.recipe
		and Enhance.IsModTexture( node.params.texture ) then
		local name = Enhance.Describe( node.params.texture )
		self:SetStatus( L( "rtx.enh.preparing", "Preparing {{file}} for editing…", { file = name } ) )
		Enhance.RequestImage( node.params.texture, "edit", key, nil, function( path, reason )
			if not IsValid( self ) then return end
			if not path then
				self:SetStatus( L( "rtx.enh.prepare_failed", "Could not read {{file}}: {{reason}}", {
					file = name, reason = tostring( reason or "?" ),
				} ), true )
				return
			end
			self:SetStatus( "" )
			self:EditTextureNode( nodeID, path )
		end )
		return
	end

	local ctx = self:TextureContext( key, index )
	ctx.src = replacementSource or node.params.texture
	ctx.sourcecopy = replacementSource ~= nil
	local editRecipe = Copy( node.params.recipe )
	if replacementSource then
		editRecipe = istable( editRecipe ) and editRecipe or { kind = "edit", ops = {} }
		-- Replace the source only on the dialog's clone.  Cancel must leave the
		-- node and its existing recipe byte-for-byte unchanged.
		editRecipe.src = replacementSource
		-- A source-backed edit never reads the old blank fill. Leaving it present
		-- would give identical pixels a different recipe hash/output filename.
		editRecipe.fill = nil
	end

	local function AdoptRecipe( recipe )
		if not IsValid( self ) or not istable( recipe ) then return end
		local current = self.Working[ index ]
		local schema = Schema()
		if not current or not schema then return end

		-- The texture editor is asynchronous.  Resolve the node in the current
		-- profile by ID so graph sanitisation or later edits cannot leave this
		-- callback mutating a detached table.  Updating the node in place also
		-- preserves every custom downstream operation and connection.
		current = Copy( current )
		current.graph = current.graph or { nodes = {}, links = {} }
		current.graph.nodes = current.graph.nodes or {}
		current.graph.links = current.graph.links or {}
		local liveNode
		for _, candidate in ipairs( current.graph.nodes ) do
			if candidate.id == nodeID then liveNode = candidate break end
		end
		if not liveNode then
			-- A newly-added Texture node is deliberately invalid until it has a
			-- source, so it exists only in the canvas and not in Working.  Promote
			-- that exact draft after the picker/editor supplies a valid recipe.
			if not draftNode or draftNode.type ~= "texture" then return end
			liveNode = Copy( draftNode )
			current.graph.nodes[ #current.graph.nodes + 1 ] = liveNode

			local nodeIDs, occupiedInputs = {}, {}
			for _, candidate in ipairs( current.graph.nodes ) do nodeIDs[ candidate.id ] = true end
			for _, link in ipairs( current.graph.links ) do
				if link.to then occupiedInputs[ link.to.node .. "\1" .. link.to.socket ] = true end
			end
			for _, link in ipairs( draftLinks or {} ) do
				local inputKey = link.to.node .. "\1" .. link.to.socket
				if nodeIDs[ link.from.node ] and nodeIDs[ link.to.node ]
					and not occupiedInputs[ inputKey ] then
					current.graph.links[ #current.graph.links + 1 ] = Copy( link )
					occupiedInputs[ inputKey ] = true
					local targetNode
					for _, candidate in ipairs( current.graph.nodes ) do
						if candidate.id == link.to.node then targetNode = candidate break end
					end
					if targetNode and targetNode.type == "output_surface" then
						current.graph.authoritative = current.graph.authoritative or {}
						current.graph.authoritative[ link.to.socket ] = true
					end
				end
			end
		end
		if liveNode.type ~= "texture" then return end
		local source = RecipeMapSource( recipe )
		if source == "" then
			self:SetStatus( L( "rtx.generated_path_failed",
				"Could not derive a safe path for the generated texture." ), true )
			return
		end
		liveNode.params = liveNode.params or {}
		liveNode.params.texture = source
		liveNode.params.recipe = Copy( recipe )
		-- Only a picture wired straight into the normal socket is the normal
		-- map; one feeding a normal-from-height node is a height map.
		local encoding = FeedsNormalSocket( current.graph, nodeID ) and KnownNormalEncoding( recipe ) or nil
		if encoding then
			current.pbr = current.pbr or {}
			current.pbr.options = current.pbr.options or {}
			current.pbr.options.normal_encoding = encoding
		end

		local clean, errors = schema.Sanitize( current )
		if not clean then self:SetStatus( ErrorText( errors ), true ) return end
		self:RememberUndo( index )
		self.Working[ index ] = clean
		if self.Selected == index then
			self.SettingGraph = true
			self.Graph:SetGraph( clean.graph )
			self.SettingGraph = false
			self:BuildSurface()
		end
		self:MarkChanged( "texture_node", true, index )
	end

	local recipeKind
	if AdvMat.Gen and isfunction( AdvMat.Gen.KindOf ) then
		local ignored
		ignored, recipeKind = AdvMat.Gen.KindOf( editRecipe )
	end
	if recipeKind == "normal" and AdvMat.OpenNormalGenerator then
		AdvMat.OpenNormalGenerator( editRecipe.src or ctx.src, editRecipe, AdoptRecipe, ctx )
	else
		AdvMat.OpenTextureEditor( "$basetexture", editRecipe, ctx, AdoptRecipe )
	end
end

function PANEL:MapKeyForNode( startID, index )
	index = tonumber( index ) or self.Selected
	local profile = index ~= nil and self.Working[ index ] or nil
	local graph = profile and profile.graph
	if not graph or not startID then return nil end
	local queue, seen = { startID }, {}
	local outputSockets = {
		albedo = "albedo", normal = "normal", anisotropy = "anisotropy",
		roughness = "roughness", metallic = "metallic", height = "height",
		emissive = "emissive",
		subsurface_transmittance = "subsurface_transmittance",
		subsurface_thickness = "subsurface_thickness",
		subsurface_scattering = "subsurface_scattering",
		subsurface_radius = "subsurface_radius",
	}
	while #queue > 0 do
		local current = table.remove( queue, 1 )
		if not seen[ current ] then
			seen[ current ] = true
			for _, link in ipairs( graph.links or {} ) do
				if link.from.node == current then
					local target
					for _, candidate in ipairs( graph.nodes or {} ) do
						if candidate.id == link.to.node then target = candidate break end
					end
					if target and target.type == "output_surface" and outputSockets[ link.to.socket ] then
						return outputSockets[ link.to.socket ]
					end
					queue[ #queue + 1 ] = link.to.node
				end
			end
		end
	end
end

function PANEL:BuildDiagnostics()
	if not IsValid( self.Diagnostics ) then return end
	self.Diagnostics:Clear()
	local index = self.Selected
	if index == nil then return end
	local material = self.Materials[ index + 1 ]
	local inspection = self.Inspections[ index ] or {}
	local caps = self.RTXCapabilities or ReadCapabilities()

	Section( self.Diagnostics, L( "rtx.target", "Replacement target" ) )
	FlatLabel( self.Diagnostics, material, T.Accent )
	FlatLabel( self.Diagnostics,
		L( "rtx.scope_explain",
			"RTX Remix identifies legacy materials by the captured base-texture hash. This edit affects every material and model sharing that hash." ),
		T.Warn, AdvMat.RowHeight() * 3 )

	Section( self.Diagnostics, L( "rtx.hashes", "Captured texture hashes" ) )
	local hashes = inspection.hashes or {}
	FlatLabel( self.Diagnostics, #hashes > 0 and table.concat( hashes, "\n" )
		or L( "rtx.hash_wait", "No hash captured yet. Keep this material visible in the world, then retry." ),
		#hashes > 0 and T.Text or T.Warn, math.max( AdvMat.RowHeight() * 2, #hashes * AdvMat.RowHeight() ) )
	local retry = self.Diagnostics:Add( "DButton" )
	retry:Dock( TOP )
	retry:SetTall( AdvMat.RowHeight() )
	retry:DockMargin( 8, 5, 8, 8 )
	retry:SetText( L( "rtx.retry_hash", "Capture hashes again" ) )
	AdvMat.StyleButton( retry )
	retry.DoClick = function()
		if not Bridge then return end
		Bridge.Inspect( material, function( result )
			if not IsValid( self ) then return end
			self.Inspections[ index ] = result
			self:AdoptInspectionHashes( index, result )
			self:BuildDiagnostics()
		end )
	end

	self:AddEnhancementDiagnostics( index )

	Section( self.Diagnostics, L( "rtx.capabilities", "Client capabilities" ) )
	local yes, no = L( "rtx.yes", "yes" ), L( "rtx.no", "no" )
	local function State( enabled ) return enabled and yes or no end
	local capabilityText = table.concat( {
		L( "rtx.cap_tracking", "Legacy hash tracking: {{state}}", { state = State( caps.tracking ) } ),
		L( "rtx.cap_inspection", "Source material inspection: {{state}}", { state = State( caps.inspection ) } ),
		L( "rtx.cap_writer", "Native legacy writer: {{state}}", { state = State( caps.nativeWriter ) } ),
		L( "rtx.cap_preview", "World preview: {{state}}", { state = State( caps.livePreview ) } ),
		L( "rtx.cap_texture", "DDS/map writer: {{state}}", { state = State( caps.textureWriter ) } ),
	}, "\n" )
	FlatLabel( self.Diagnostics, capabilityText, T.Text, AdvMat.RowHeight() * 5 )

	if caps.nativeBlocked then
		FlatLabel( self.Diagnostics,
			L( "rtx.native_blocked",
				"The installed native writer could not reset its owned state, so synchronization and writes are blocked: {{reason}}",
				{ reason = tostring( caps.nativeError or "unknown error" ) } ),
			T.Danger, AdvMat.RowHeight() * 4 )
	elseif not caps.nativeWriter then
		FlatLabel( self.Diagnostics,
			L( "rtx.export_explain",
				"This installed RTX client can inspect materials but cannot write arbitrary legacy USD replacements. Save exports a complete profile under garrysmod/data/advmat/rtx_exports; install the AdvMat RTX native bridge to apply it in-world." ),
			T.Warn, AdvMat.RowHeight() * 4 )
	end
	if caps.externalMaterialAPI and not caps.externalAPIReplacesLegacy then
		FlatLabel( self.Diagnostics,
			L( "rtx.external_warning",
				"CreateOpaqueMaterial is available, but it only creates materials for Remix API geometry. It is intentionally not used for this Source model." ),
			T.TextDim, AdvMat.RowHeight() * 3 )
	end

	Section( self.Diagnostics, L( "rtx.source_inspection", "Imported Source material" ) )
	local source = inspection.source
	if not istable( source ) then
		FlatLabel( self.Diagnostics, inspection.inspectError or L( "rtx.no_inspection", "No ToPBR inspection data." ), T.TextDim )
	else
		local lines = {}
		for _, key in ipairs( { "shaderName", "baseTexture", "bumpMap", "roughness", "metallic",
			"detectedFormat", "surfaceProp" } ) do
			if source[ key ] ~= nil and source[ key ] ~= "" then
				lines[ #lines + 1 ] = L( "rtx.inspect." .. key,
					key .. ": {{value}}", { value = tostring( source[ key ] ) } )
			end
		end
		FlatLabel( self.Diagnostics, table.concat( lines, "\n" ), T.Text,
			math.max( AdvMat.RowHeight() * 2, #lines * AdvMat.RowHeight() ) )
	end
end

--- Every Remix mod that replaces this row's hashes, in the order the runtime
--- checks them, and which one it draws.
function PANEL:AddEnhancementDiagnostics( index )
	if not Enhance then return end
	Section( self.Diagnostics, L( "rtx.enh.diag_title", "RTX Remix mods replacing this hash" ) )

	local found = self:EnhancementFor( index )
	local lines, drawn = {}, {}
	local several = found and #found.hashes > 1
	for rank, entry in ipairs( found and found.entries or {} ) do
		local role
		if entry.own then
			role = L( "rtx.enh.diag_own", "AME profile" )
		elseif entry.automatic then
			role = L( "rtx.enh.diag_automatic", "automatic ToPBR material" )
		else
			role = L( "rtx.enh.diag_enhancement", "enhancement" )
		end
		-- The first mod holding a hash is the one drawn for it.
		local state = L( "rtx.enh.diag_hidden", "hidden by a mod before it" )
		if not drawn[ entry.hash ] then
			drawn[ entry.hash ] = true
			state = L( "rtx.enh.diag_drawn", "drawn" )
		end
		lines[ #lines + 1 ] = string.format( "%d. %s%s  —  %s  (%s, %s; %s)", rank,
			several and ( "0x" .. entry.hash .. "  " ) or "", entry.folder,
			Enhance.LayerName( entry.material ), ShaderName( entry.material ), role, state )
	end
	if #lines == 0 then
		lines[ 1 ] = #self:SlotHashes( index ) > 0
			and L( "rtx.enh.diag_none", "No mod in rtx-remix/mods replaces this hash." )
			or L( "rtx.hash_wait", "No hash captured yet. Keep this material visible in the world, then retry." )
	end
	FlatLabel( self.Diagnostics, table.concat( lines, "\n" ), T.Text,
		math.max( AdvMat.RowHeight() * 2, #lines * AdvMat.RowHeight() ) )

	local count, unreadable = 0, {}
	for _, record in ipairs( Enhance.Mods or {} ) do
		count = count + ( record.count or 0 )
		for _, problem in ipairs( record.errors or {} ) do
			unreadable[ #unreadable + 1 ] = record.folder .. ": " .. problem
		end
	end
	FlatLabel( self.Diagnostics, L( "rtx.enh.reread_done",
		"Read {{mods}} Remix mod(s) with {{materials}} material(s) in {{ms}} ms.", {
			mods = #( Enhance.Mods or {} ), materials = count, ms = Enhance.LastScanMS or 0,
		} ), T.TextDim )
	if #unreadable > 0 then
		FlatLabel( self.Diagnostics, L( "rtx.enh.diag_errors", "Could not read: {{list}}",
			{ list = table.concat( unreadable, "; " ) } ), T.Warn,
			math.max( AdvMat.RowHeight() * 2, math.min( 8, #unreadable ) * AdvMat.RowHeight() ) )
	end
end

function PANEL:UpdateMarkers()
	for index, line in pairs( self.MaterialLines or {} ) do
		if IsValid( line ) and line.SetColumnText then
			local sourceDirty, sourceSaved = false, false
			if IsValid( self.SourcePanel ) then
				sourceDirty = self.SourcePanel:IsDirty( index )
				sourceSaved = self.SourcePanel:HasSavedOverride( index )
			end
			local marker
			if self.Dirty[ index ] and sourceDirty then marker = "P*S*"
			elseif sourceDirty then marker = "S*"
			elseif self.Dirty[ index ] then marker = "P*"
			elseif self.MaterialAliases[ index ] then marker = "↪"
			elseif self.Saved[ index ] and sourceSaved then marker = "●S"
			elseif self.Saved[ index ] then marker = "●"
			elseif sourceSaved then marker = "S"
			else marker = "" end
			-- E: Remix draws this row from an enhancement, and no AME profile
			-- replaces it.
			if not self.Saved[ index ] and not self.MaterialAliases[ index ] then
				local found = self:EnhancementFor( index )
				if found and found.enhancement then marker = marker .. "E" end
			end
			line:SetColumnText( 3, marker )
		end
	end
	if self:IsSourceTabActive() then self:UpdateActionMode()
	else self.UndoButton:SetEnabled( self.Selected ~= nil and #( self.Undo[ self.Selected ] or {} ) > 0 ) end
end

function PANEL:SaveAll()
	if self:IsSourceTabActive() and IsValid( self.SourcePanel ) then
		return self.SourcePanel:SaveAll()
	end
	return self:SaveRTXProfiles()
end

function PANEL:SaveRTXProfiles()
	if self.AdvMatCanWrite == false then
		self:SetStatus( L( "rtx.save_denied", "Only administrators can save on this server." ), true )
		return
	end
	-- Failed background saves remain available after closing/reopening the
	-- window; pressing Save is an explicit retry against the visible baseline.
	if Store and Store.GetSyncState then
		for slot, profile in pairs( self.Working ) do
			if Store.GetSyncState( MaterialName( profile ) ) == "failed" then self.Dirty[ slot ] = true end
		end
	end
	local pending = {}
	for index in pairs( self.Dirty ) do
		local canonical = self:CanonicalSlot( index )
		if canonical ~= nil and canonical ~= index and self.Dirty[ canonical ] then
			self:SetStatus( L( "rtx.shared_alias_conflict",
				"Two unsaved rows now share one captured RTX identity. Keep one working copy before saving." ), true )
			return
		end
		if self.Working[ index ] then pending[ #pending + 1 ] = index end
	end
	if #pending == 0 then
		self:SetStatus( L( "rtx.nothing_save", "Nothing to save." ) )
		return
	end
	local schema = Schema()
	if not schema or not isfunction( schema.Compile ) then
		self:SetStatus( L( "rtx.compiler_unavailable",
			"Cannot save RTX profiles: the RTX material compiler is unavailable." ), true )
		return
	end
	for _, index in ipairs( pending ) do
		local profile = Copy( self.Working[ index ] )
		local ok, compiled, errors = pcall( schema.Compile, profile )
		if not ok then errors, compiled = compiled, nil end
		if not compiled then
			local material = MaterialName( profile )
			if material == "" then material = "slot " .. tostring( index ) end
			self:SetStatus( L( "rtx.compile_failed",
				"Cannot save RTX profile for {{material}}: {{reason}}", {
					material = material,
					reason = ErrorText( errors ),
				} ), true )
			return
		end
	end
	-- A Save over a glass or portal enhancement writes an opaque material in
	-- its place. Ask once per row, and not again once an AME profile already
	-- replaces it.
	self.ShaderChangeConfirmed = self.ShaderChangeConfirmed or {}
	for _, index in ipairs( pending ) do
		if not self.ShaderChangeConfirmed[ index ] and not self.Saved[ index ] then
			local found = self:EnhancementFor( index )
			local entry = found and found.enhancement
			if entry and entry.material.kind ~= "opaque" then
				Derma_Query(
					L( "rtx.enh.confirm_shader",
						"{{material}} is drawn from a {{shader}} enhancement in {{mod}}. AME writes opaque materials only, so saving replaces it with an opaque surface. Save anyway?",
						{ material = self.Materials[ index + 1 ] or "", shader = ShaderName( entry.material ), mod = entry.folder } ),
					L( "rtx.enh.confirm_title", "Replace this enhancement?" ),
					L( "rtx.enh.confirm_save", "Save anyway" ), function()
						if not IsValid( self ) then return end
						self.ShaderChangeConfirmed[ index ] = true
						self:SaveRTXProfiles()
					end,
					L( "common.cancel", "Cancel" ) )
				return
			end
		end
	end

	local left, failed, exported, applyWarnings, pendingHashes = #pending, 0, false, 0, 0
	self.SaveButton:SetEnabled( false )
	self.ResetButton:SetEnabled( false )
	self:SetStatus( L( "rtx.saving", "Saving RTX profiles…" ) )
	for _, index in ipairs( pending ) do
		local profile = Copy( self.Working[ index ] )
		local submittedRevision = self:GetEditRevision( index )
		local request = {}
		self.SaveRequests[ index ] = request
		local function LocalDone( ok, result )
			if not IsValid( self ) or self.Closing or self.SaveRequests[ index ] ~= request then return end
			request.localDone = true
			left = left - 1
			if ok then
				local accepted = istable( result ) and result.profile or profile
				local needsHash = istable( result ) and ( result.pendingHash == true
					or result.status == "waiting-for-hash" )
				self.Saved[ index ] = Copy( accepted )
				self.SavedIDs[ index ] = istable( result ) and result.id or nil
				self.SavedETags[ index ] = istable( result ) and result.etag or nil
				if self:GetEditRevision( index ) == submittedRevision then
					self.Working[ index ] = Copy( accepted )
					self.Dirty[ index ] = ( needsHash or request.syncFailed ) and true or nil
				else
					-- A control, graph, or captured hash changed while the request was
					-- in flight.  The accepted snapshot is the new saved base, but the
					-- newer working copy must remain visible and dirty.
					self.Dirty[ index ] = true
				end
				local material = MaterialName( accepted )
				self.ApplyFailed = self.ApplyFailed or {}
				if istable( result ) and result.applyError ~= nil then
					applyWarnings = applyWarnings + 1
					self.ApplyFailed[ index ] = true
				else
					self.PreviewedMaterials[ material ] = nil
					self.ApplyFailed[ index ] = nil
				end
			else failed = failed + 1 end
			if istable( result ) and result.status == "exported" then exported = true end
			if istable( result ) and ( result.pendingHash == true
				or result.status == "waiting-for-hash" ) then
				pendingHashes = pendingHashes + 1
			end
			if left <= 0 then
				local canWrite = self.AdvMatCanWrite ~= false
				self.SaveButton:SetEnabled( canWrite )
				self.ResetButton:SetEnabled( canWrite )
				self:UpdateMarkers()
				if request.syncFailed then
					self:SetStatus( request.syncError, true )
				elseif failed > 0 then
					self:SetStatus( L( "rtx.save_failed", "One or more RTX profiles could not be saved." ), true )
				elseif pendingHashes > 0 then
					self:SetStatus( L( "rtx.saved_pending_hash",
						"RTX drafts were saved, but one or more materials have no captured texture hash yet. Keep them visible, recapture, then Save again." ),
						"warning" )
				elseif applyWarnings > 0 then
					self:SetStatus( L( "rtx.saved_apply_warning",
						"RTX profiles were saved, but one or more could not be applied. Check Diagnostics or reload Remix." ),
						"warning" )
				else
					self:SetStatus( exported and L( "rtx.exported", "RTX profiles exported." )
						or ( result.persisted and L( "rtx.background_synced", "Saved locally and synced with the server." )
						or L( "rtx.local_saved", "Saved locally. Syncing in the background…" ) ) )
					surface.PlaySound( "buttons/button15.wav" )
				end
			end
		end
		Store.Save( profile, function( ok, result )
			if not IsValid( self ) or self.Closing or self.SaveRequests[ index ] ~= request then return end
			if result.status == "superseded" then return end
			local material = MaterialName( profile )
			if ok then
				self.SavedIDs[ index ], self.SavedETags[ index ] = result.id, result.etag
				local complete = left <= 0 and applyWarnings == 0 and pendingHashes == 0
				for _, listed in ipairs( self.Materials ) do
					if Store.GetSyncState( listed ) ~= "synced" then complete = false break end
				end
				if complete then
					self:SetStatus( L( "rtx.background_synced", "Saved locally and synced with the server." ) )
				end
			else
				-- Keep any newer UI work and the locally applied save. Only an
				-- explicit retry may rebase against the server's current version.
				self.Dirty[ index ] = true
				self.SavedIDs[ index ], self.SavedETags[ index ] = Store.GetVersion( material )
				request.syncFailed = true
				request.syncError = L( "rtx.background_failed",
					"Server sync failed for {{material}}: {{reason}}. Your local changes are retained; Save to retry.",
					{ material = material, reason = tostring( result.error or result.status ) } )
				self:SetStatus( request.syncError, true )
			end
			self:UpdateMarkers()
		end, {
			explicit = true,
			id = self.SavedIDs[ index ],
			etag = self.SavedETags[ index ],
		}, LocalDone )
	end
end

function PANEL:RemoveOverride()
	if self:IsSourceTabActive() and IsValid( self.SourcePanel ) then
		return self.SourcePanel:RemoveSelected()
	end
	return self:RemoveRTXOverride()
end

function PANEL:RemoveRTXOverride()
	local index = self.Selected
	if index == nil then return end
	local material = self.Materials[ index + 1 ]
	if not self.Saved[ index ] and not ( Store and Store.Get and Store.Get( material ) ) then
		self:BumpEditRevision( index )
		self.Working[ index ] = self:CreateProfile( index, self.Inspections[ index ])
		self.Dirty[ index ] = nil
		self.Graph:SetGraph( self.Working[ index ].graph )
		self:BuildSurface()
		self:UpdateMarkers()
		self.PreviewedMaterials[ material ] = nil
		Store.Restore( material )
		return
	end
	local requestRevision = self:BumpEditRevision( index )
	self.PendingClears[ index ] = true
	if IsValid( self.ResetButton ) then self.ResetButton:SetEnabled( false ) end
	Store.Clear( material, function( ok, result )
		if not IsValid( self ) then return end
		self.PendingClears[ index ] = nil
		if IsValid( self.ResetButton ) then self.ResetButton:SetEnabled( self.AdvMatCanWrite ~= false ) end
		if not ok then
			-- A concurrent broadcast is deliberately ignored while our clear is in
			-- flight, otherwise our own removal would race this window.  If CAS
			-- rejects the clear, replay the now-authoritative mirror into an
			-- untouched slot; OnProfileChanged itself preserves dirty work.
			local latest = Store and Store.Get and Store.Get( material ) or nil
			self:OnProfileChanged( material, latest )
			self:SetStatus( tostring( result and result.error or "clear failed" ), true )
			return
		end
		self.Saved[ index ] = nil
		self.SavedIDs[ index ], self.SavedETags[ index ] = nil, nil
		self.PreviewedMaterials[ material ] = nil
		if self.ApplyFailed then self.ApplyFailed[ index ] = nil end
		local editedWhileClearing = self:GetEditRevision( index ) ~= requestRevision
		if not editedWhileClearing then
			self.Working[ index ] = self:CreateProfile( index, self.Inspections[ index ])
			self.Dirty[ index ] = nil
		else
			self.Dirty[ index ] = true
		end
		if self.Selected == index then
			self.Graph:SetGraph( self.Working[ index ].graph )
			self:BuildSurface()
		end
		self:UpdateMarkers()
		-- `nativeCleaned == false` is also the truthful result for export-only
		-- mode, where there was no native layer to remove.  Warn only when the
		-- cleanup itself is still incomplete; deleting the exported bundle is a
		-- completed cleanup and must not be presented as a retry failure.
		if istable( result ) and result.cleanupComplete == false then
			self:SetStatus( L( "rtx.removed_cleanup_warning",
				"RTX profile was removed from the server, but local Remix cleanup is still retrying. Check Diagnostics or reload Remix." ),
				"warning" )
		elseif editedWhileClearing then
			self:SetStatus( L( "rtx.unsaved", "Unsaved RTX material changes" ), "warning" )
		else
			local found = self:EnhancementFor( index )
			local entry = found and found.enhancement
			self:SetStatus( entry and L( "rtx.enh.removed",
				"RTX material override removed. Remix draws the {{mod}} enhancement again.", { mod = entry.folder } )
				or L( "rtx.removed", "RTX material override removed." ) )
		end
	end, {
		explicit = true,
		id = self.SavedIDs[ index ],
		etag = self.SavedETags[ index ],
	} )
end

function PANEL:Close()
	-- Entity previews have a detached acknowledgement handoff in cl_40_store,
	-- but Source world previews are direct material mutations owned by this
	-- window. Keep the window alive until RuleApplied so Close cannot reveal the
	-- old world material between Save and the authoritative apply pass.
	local source = self.SourcePanel
	if IsValid( source ) and source:HasPending() then
		source:SetStatus( L( "rtx.source.wait_close",
			"Please wait for the Source material save to finish before closing the editor." ), "warning" )
		self:UpdateActionMode()
		surface.PlaySound( "buttons/button10.wav" )
		return false
	end

	local base = self.BaseClass
	if base and isfunction( base.Close ) then return base.Close( self ) end
	-- Defensive fallback for unusual Derma loaders which do not publish a
	-- BaseClass table. Mirror DFrame's close lifecycle.
	self:OnClose()
	self:SetVisible( false )
	if self:GetDeleteOnClose() then self:Remove() end
	return true
end

function PANEL:OnClose()
	if self.Closing then return end
	self.Closing = true
	if IsValid( self.SourcePanel ) and self.SourcePanel.Cleanup then
		self.SourcePanel:Cleanup()
	end
	if AdvMat.ModelView and AdvMat.ModelView.EndRTXDraw then
		AdvMat.ModelView.EndRTXDraw( self )
	end
	self:RestorePreviews()
	if self.CapabilityHookID then
		hook.Remove( "AdvMatBackendCapabilitiesChanged", self.CapabilityHookID )
		self.CapabilityHookID = nil
	end
	if self.ProfileSyncHookID then
		hook.Remove( "AdvMatRTXProfilesSynced", self.ProfileSyncHookID )
		self.ProfileSyncHookID = nil
	end
	if self.ProfileChangeHookID then
		hook.Remove( "AdvMatRTXProfilesChanged", self.ProfileChangeHookID )
		self.ProfileChangeHookID = nil
	end
	if self.LocalSyncHookID then
		hook.Remove( "AdvMatRTXLocalSyncChanged", self.LocalSyncHookID )
		self.LocalSyncHookID = nil
	end
	for _, name in ipairs( { "TexPicker", "TexEditor", "SurfaceDialog", "GenDialog" } ) do
		local child = AdvMat[ name ]
		if IsValid( child ) and child.AdvMatHost == self and isfunction( child.Close ) then child:Close() end
	end
	if AdvMat.Backend and AdvMat.Backend.EndSession then
		AdvMat.Backend.EndSession( self.AdvMatBackendSession )
	end
	if AdvMat.RTXEditor == self then AdvMat.RTXEditor = nil end
	if AdvMat.Editor == self then AdvMat.Editor = nil end
end

function PANEL:OnRemove()
	-- Direct Remove/hot reload bypasses DFrame:OnClose. OnClose is idempotent and
	-- owns every session, preview, child-window and input-adjacent cleanup path.
	self:OnClose()
end

vgui.Register( "AdvMatRTXEditor", PANEL, "DFrame" )

function AdvMat.OpenRTXEditor( ent, worldMat, session )
	if IsValid( AdvMat.Editor ) then
		if AdvMat.WindowUX then
			AdvMat.WindowUX.Focus( AdvMat.Editor )
		else
			AdvMat.Editor:MakePopup()
			AdvMat.Editor:MoveToFront()
		end
		return AdvMat.Editor
	end
	local frame = vgui.Create( "AdvMatRTXEditor" )
	frame.AdvMatBackendSession = session
	frame.BackendSession = session
	AdvMat.Editor = frame
	AdvMat.RTXEditor = frame
	if Store and Store.RequestSync then Store.RequestSync() end
	if worldMat and worldMat ~= "" then frame:SetWorldMaterial( worldMat )
	else frame:SetTargetEntity( ent ) end
	if AdvMat.I18N and AdvMat.I18N.Track then AdvMat.I18N.Track( frame ) end
	return frame
end
