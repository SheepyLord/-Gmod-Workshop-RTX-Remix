--[[---------------------------------------------------------------------------
	Advanced Material Editor - normal map generator window

	The settings panel for cl_55_normalgen.lua, in the spirit of SmartNormal:
	pick a source texture, choose how the height field is read and which
	gradient operator runs over it, and watch the result update.

	The preview is generated at 128px on a debounce so that dragging a slider
	stays responsive; only pressing Generate produces the full resolution
	image. Both go through the same queue as everything else, so nothing here
	touches a render target directly.
-----------------------------------------------------------------------------]]

AdvMat = AdvMat or {}

local T = AdvMat.Theme
local GEN = AdvMat.Gen

local PREVIEW_SIZE  = 128
local PREVIEW_DELAY = 0.35

local PANEL = {}

---------------------------------------------------------------------------
-- Settings -> recipe
---------------------------------------------------------------------------
function PANEL:BuildRecipe( size )
	local ctx = self.Ctx or {}

	-- `size` caps the longer side for the preview. The shape is kept, because
	-- a square preview of an oblong sheet previews something else.
	local w, h = self.Settings.size, self.Settings.height or self.Settings.size
	if size then w, h = GEN.FitWithin( w, h, size ) end

	return GEN.Sanitize( {
		kind     = "normal",
		_preview = size ~= nil,
		src      = self.SrcEntry:GetValue(),
		size     = w,
		height   = h,
		channel  = self.Settings.channel,
		filter   = self.Settings.filter,
		strength = self.Settings.strength,
		blur     = self.Settings.blur,
		detail   = self.Settings.detail,
		uneven   = self.Settings.uneven,
		invertx  = self.Settings.invertx,
		inverty  = self.Settings.inverty,
		inverth  = self.Settings.inverth,
		wrap     = self.Settings.wrap,

		-- Where the generator is allowed to write, and what rides along in the
		-- alpha channel.
		region     = self.Settings.region,
		regionmode = self.Settings.regionmode,
		alphamask  = self.Settings.alphamask,

		model   = ctx.model,
		slot    = ctx.slot,
		matpath = ctx.matpath,
		mask    = ctx.mask,
	} )
end

--- Anything that changes the image refreshes the summary and re-previews.
function PANEL:Changed()
	local recipe = self:BuildRecipe()

	self.Summary:SetText( recipe and GEN.Describe( recipe ) or "No source texture chosen." )

	timer.Create( "AdvMat.GenPreview", PREVIEW_DELAY, 1, function()
		if not IsValid( self ) then return end

		local preview = self:BuildRecipe( PREVIEW_SIZE )
		self.PreviewRecipe = preview
		self.PreviewMat    = preview and GEN.GetMaterial( preview ) or nil
	end )
end

---------------------------------------------------------------------------
-- Construction
---------------------------------------------------------------------------
function PANEL:Init()
	self.Settings = table.Copy( GEN.DEFAULTS )

	local rowH = AdvMat.RowHeight()

	-- The two preview panes need one useful settings column beside them. Cap the
	-- minima to the current desktop so even a small resolution stays reachable.
	self:SetMinWidth( math.min( math.max( 720, AdvMat.FontSize * 38 ),
		math.max( 1, ScrW() - 24 ) ) )
	self:SetMinHeight( math.min( 600, math.max( 1, ScrH() - 24 ) ) )
	self:SetSize( math.min( 960, ScrW() - 80 ), math.min( 660, ScrH() - 80 ) )
	self:SetTitle( "Generate normal map" )
	self:SetSizable( true )
	self:Center()
	self:MakePopup()
	AdvMat.StyleFrame( self )

	------------------------------------------------------------ source row
	local top = vgui.Create( "DPanel", self )
	top:Dock( TOP )
	top:SetTall( rowH + 2 )
	top:DockMargin( 0, 0, 0, 6 )
	top.Paint = AdvMat.NoPaint

	local srcTag = vgui.Create( "DLabel", top )
	srcTag:Dock( LEFT )
	srcTag:SetWide( AdvMat.FontSize * 9 )
	srcTag:SetText( "Source texture" )
	AdvMat.StyleLabel( srcTag, "AdvMatText", T.TextDim )

	local browse = vgui.Create( "DButton", top )
	browse:Dock( RIGHT )
	browse:SetWide( rowH + 8 )
	browse:DockMargin( 6, 0, 0, 0 )
	browse:SetText( "..." )
	AdvMat.StyleButton( browse )

	self.SrcEntry = vgui.Create( "DTextEntry", top )
	self.SrcEntry:Dock( FILL )
	self.SrcEntry:SetUpdateOnType( false )
	self.SrcEntry:SetPlaceholderText( "models/folder/texture" )
	AdvMat.StyleEntry( self.SrcEntry )
	self.SrcEntry.OnValueChange = function() self:Changed() end

	browse.DoClick = function()
		AdvMat.OpenTexturePicker( self.SrcEntry:GetValue(), function( path )
			self.SrcEntry:SetValue( path )
			self:Changed()
		end, self.SrcEntry:GetValue(), self )
	end

	----------------------------------------------------------- bottom bar
	local bottom = vgui.Create( "DPanel", self )
	bottom:Dock( BOTTOM )
	bottom:SetTall( rowH + 6 )
	bottom:DockMargin( 0, 6, 0, 0 )
	bottom.Paint = AdvMat.NoPaint

	local cancel = vgui.Create( "DButton", bottom )
	cancel:Dock( RIGHT )
	cancel:SetWide( AdvMat.FontSize * 5 )
	cancel:DockMargin( 6, 0, 0, 0 )
	cancel:SetText( "Cancel" )
	cancel.DoClick = function() self:Close() end
	AdvMat.StyleButton( cancel )

	local accept = vgui.Create( "DButton", bottom )
	accept:Dock( RIGHT )
	accept:SetWide( AdvMat.FontSize * 11 )
	accept:SetText( "Generate and use" )
	accept:SetTooltip( "Build the map at the chosen resolution and plug it into the parameter." )
	AdvMat.StyleButton( accept )

	accept.DoClick = function()
		local recipe = self:BuildRecipe()

		if not recipe then
			AdvMat.NotifyLocal( "Choose a source texture first.", NOTIFY_ERROR, 4 )
			return
		end

		-- Kick the full resolution build off now; the material picks it up
		-- through the AdvMatGenerated hook when it lands.
		GEN.Request( recipe )

		local callback = self.OnAccept
		self:Close()
		if callback then callback( recipe ) end
	end

	--------------------------------------------------------- summary line
	-- The settings in words, so what a generated map was made from is on
	-- screen rather than buried in the controls.
	self.Summary = vgui.Create( "DLabel", self )
	self.Summary:Dock( BOTTOM )
	self.Summary:SetTall( rowH )
	self.Summary:DockMargin( 0, 4, 0, 0 )
	AdvMat.StyleLabel( self.Summary, "AdvMatSmall", T.Accent )

	--------------------------------------------------------------- panes
	local left = vgui.Create( "DPanel", self )
	left:Dock( LEFT )
	left:SetWide( math.max( 300, AdvMat.FontSize * 19 ) )
	left:DockMargin( 0, 0, 8, 0 )
	left.Paint = AdvMat.NoPaint

	self.SourceView = self:AddPreview( left, "Source", function()
		local path = AdvMat.NormalizeMaterial( self.SrcEntry:GetValue() )
		if path == "" then return nil end
		return AdvMat.PreviewMaterial( path )
	end )

	self.ResultView = self:AddPreview( left, "Normal map", function()
		return self.PreviewMat
	end )

	-- Left empty: OpenNormalGenerator fills it once the starting settings are
	-- known, so the controls are never built twice.
	self.SettingsPane = vgui.Create( "DScrollPanel", self )
	self.SettingsPane:Dock( FILL )
	self.SettingsPane.Paint = AdvMat.Fill( T.Panel )
end

--- A captioned square that paints whatever `get` hands back.
function PANEL:AddPreview( parent, caption, get )
	local rowH = AdvMat.RowHeight()

	local label = vgui.Create( "DLabel", parent )
	label:Dock( TOP )
	label:SetTall( rowH )
	label:SetText( caption )
	AdvMat.StyleLabel( label, "AdvMatText", T.TextDim )

	local view = vgui.Create( "DPanel", parent )
	view:Dock( TOP )
	view:SetTall( math.max( 200, math.floor( ScrH() * 0.20 ) ) )
	view:DockMargin( 0, 0, 0, 8 )

	view.Paint = function( pnl, w, h )
		surface.SetDrawColor( 24, 26, 30, 255 )
		surface.DrawRect( 0, 0, w, h )

		local mat = get()

		if not mat then
			draw.SimpleText( AdvMat.LText( "generating..." ), "AdvMatSmall", w * 0.5, h * 0.5,
				T.TextFaint, TEXT_ALIGN_CENTER, TEXT_ALIGN_CENTER )
			return
		end

		local size = math.min( w, h ) - 12
		surface.SetDrawColor( 255, 255, 255, 255 )
		surface.SetMaterial( mat )
		surface.DrawTexturedRect( ( w - size ) * 0.5, ( h - size ) * 0.5, size, size )
	end

	return view
end

---------------------------------------------------------------------------
-- Settings controls
---------------------------------------------------------------------------
function PANEL:BuildSettings( parent )
	local rowH = AdvMat.RowHeight()
	local this = self

	local function Row( tall )
		local row = parent:Add( "DPanel" )
		row:Dock( TOP )
		row:SetTall( tall or rowH )
		row:DockMargin( 6, 4, 6, 0 )
		row.Paint = AdvMat.NoPaint
		return row
	end

	local function Caption( text )
		local row = Row( rowH + 6 )
		local lbl = vgui.Create( "DLabel", row )
		lbl:Dock( FILL )
		lbl:SetText( text )
		AdvMat.StyleLabel( lbl, "AdvMatBold", T.Text )
	end

	--- `field` is the settings key the choice is stored under. A list whose
	--- entries carry their own `on` flag and a `pick` function instead is for
	--- a choice that is more than one value - the resolution is two.
	local function Combo( text, list, field, tip, pick )
		local row = Row()

		local lbl = vgui.Create( "DLabel", row )
		lbl:Dock( LEFT )
		lbl:SetWide( AdvMat.FontSize * 9 )
		lbl:SetText( text )
		AdvMat.StyleLabel( lbl, "AdvMatText", T.Text )

		local box = vgui.Create( "DComboBox", row )
		box:Dock( FILL )
		box:SetSortItems( false )
		if tip then box:SetTooltip( tip ) end
		AdvMat.StyleCombo( box )

		for _, entry in ipairs( list ) do
			box:AddChoice( entry.name, entry.id,
				entry.on or ( field ~= nil and entry.id == this.Settings[ field ] ) )
		end

		box.OnSelect = function( _, _, _, id )
			if pick then pick( id ) else this.Settings[ field ] = id end
			this:Changed()
		end

		return box
	end

	local function Slider( text, field, min, max, decimals, tip )
		local row = Row()

		local lbl = vgui.Create( "DLabel", row )
		lbl:Dock( LEFT )
		lbl:SetWide( AdvMat.FontSize * 9 )
		lbl:SetText( text )
		AdvMat.StyleLabel( lbl, "AdvMatText", T.Text )

		local slider = vgui.Create( "DNumSlider", row )
		slider:Dock( FILL )
		slider:SetText( "" )
		slider:SetMin( min )
		slider:SetMax( max )
		slider:SetDecimals( decimals )
		slider:SetValue( this.Settings[ field ] )
		if tip then slider:SetTooltip( tip ) end
		AdvMat.StyleSlider( slider )

		slider.OnValueChanged = function( _, v )
			this.Settings[ field ] = math.Round( v, decimals )
			this:Changed()
		end

		return slider
	end

	local function Check( text, field, tip )
		local row = Row()

		local box = vgui.Create( "DCheckBoxLabel", row )
		box:Dock( FILL )
		box:SetText( text )
		box:SetValue( this.Settings[ field ] )
		if tip then box:SetTooltip( tip ) end
		AdvMat.StyleLabel( box, "AdvMatText", T.Text )

		box.OnChange = function( _, v )
			this.Settings[ field ] = v and true or false
			this:Changed()
		end

		return box
	end

	------------------------------------------------------------------ shape
	Caption( "Height" )

	Combo( "Read from", GEN.CHANNELS, "channel",
		"Which channel of the source becomes the height field.\n" ..
		"A diffuse texture has no real height data, so this is always a guess; " ..
		"luminance is the usual one." )

	Slider( "Blur", "blur", 0, 8, 0,
		"Smooths the height field first. Use it to stop compression artefacts " ..
		"and noise turning into fake bumps." )

	Slider( "Detail", "detail", 0, 2, 2,
		"Adds back the fine detail the blur removes, sharpening pores and " ..
		"weave without changing the broad shape." )

	Check( "Invert height", "inverth",
		"Treat dark pixels as high instead of low. Flip this if the surface " ..
		"reads inside-out." )

	------------------------------------------------------- uneven variation
	Caption( AdvMat.L( "gen.uneven" ) )

	local unevenOn = Row()
	local unevenBox = vgui.Create( "DCheckBoxLabel", unevenOn )
	unevenBox:Dock( FILL )
	AdvMat.StyleCheck( unevenBox, AdvMat.L( "gen.uneven_enable" ) )
	unevenBox:SetValue( self.Settings.uneven ~= nil )
	unevenBox:SetTooltip( AdvMat.L( "gen.uneven_enable_tip" ) )

	local unevenBody = parent:Add( "DPanel" )
	unevenBody:Dock( TOP )
	unevenBody:SetTall( rowH * 3 + 8 )
	unevenBody:DockMargin( 6, 2, 6, 4 )
	unevenBody.Paint = AdvMat.NoPaint
	unevenBody:SetVisible( self.Settings.uneven ~= nil )

	local function UnevenSlider( label, field, min, max, decimals, tip, button )
		local row = vgui.Create( "DPanel", unevenBody )
		row:Dock( TOP )
		row:SetTall( rowH + 2 )
		row.Paint = AdvMat.NoPaint

		local lbl = vgui.Create( "DLabel", row )
		lbl:Dock( LEFT )
		lbl:SetWide( AdvMat.FontSize * 9 )
		lbl:SetText( label )
		AdvMat.StyleLabel( lbl, "AdvMatText", T.Text )

		if button then
			button:SetParent( row )
			button:Dock( RIGHT )
			button:SetWide( AdvMat.FontSize * 8 )
			button:DockMargin( 6, 0, 0, 0 )
		end

		local slider = vgui.Create( "DNumSlider", row )
		slider:Dock( FILL )
		slider:SetText( "" )
		slider:SetMin( min )
		slider:SetMax( max )
		slider:SetDecimals( decimals )
		slider:SetValue( ( this.Settings.uneven or GEN.UNEVEN_DEFAULTS )[ field ] )
		if tip then slider:SetTooltip( tip ) end
		AdvMat.StyleSlider( slider )

		slider.OnValueChanged = function( _, value )
			if not this.Settings.uneven then return end
			this.Settings.uneven[ field ] = math.Round( value, decimals )
			this:Changed()
		end

		return slider
	end

	UnevenSlider( AdvMat.L( "gen.uneven_amount" ), "amount", 0.01, 1, 2,
		AdvMat.L( "gen.uneven_amount_tip" ) )
	UnevenSlider( AdvMat.L( "gen.uneven_density" ), "scale", 2, 64, 0,
		AdvMat.L( "gen.uneven_density_tip" ) )

	local reseed = vgui.Create( "DButton" )
	reseed:SetText( AdvMat.L( "gen.uneven_new" ) )
	reseed:SetTooltip( AdvMat.L( "gen.uneven_new_tip" ) )
	AdvMat.StyleButton( reseed )
	local seedSlider = UnevenSlider( AdvMat.L( "gen.uneven_seed" ), "seed", 0, 65535, 0,
		AdvMat.L( "gen.uneven_seed_tip" ), reseed )

	reseed.DoClick = function()
		if not this.Settings.uneven then return end
		local current = this.Settings.uneven.seed or GEN.UNEVEN_DEFAULTS[ "seed" ]
		local nextSeed = math.random( 0, 65535 )
		if nextSeed == current then nextSeed = ( nextSeed + 1 ) % 65536 end
		this.Settings.uneven.seed = nextSeed
		seedSlider:SetValue( nextSeed )
		this:Changed()
	end

	unevenBox.OnChange = function( _, enabled )
		if enabled then
			this.Settings.uneven = this.Settings.uneven
				or table.Copy( this.UnevenDraft or GEN.UNEVEN_DEFAULTS )
		else
			this.UnevenDraft = this.Settings.uneven
				and table.Copy( this.Settings.uneven ) or this.UnevenDraft
			this.Settings.uneven = nil
		end

		unevenBody:SetVisible( enabled )
		parent:InvalidateLayout( true )
		this:Changed()
	end

	--------------------------------------------------------------- gradient
	Caption( "Gradient" )

	Combo( "Filter", GEN.FILTERS, "filter",
		"Sobel is the standard. Scharr is more rotationally accurate on " ..
		"diagonals. Prewitt is softer. The 5x5 reaches further and is smoother." )

	Slider( "Strength", "strength", 0.05, 30, 2,
		"How far the normals lean. Low is a subtle surface, high is dramatic." )

	Check( "Invert X", "invertx", "Mirror the red channel." )
	Check( "Invert Y", "inverty",
		"Mirror the green channel. If lighting looks lit from the wrong side, " ..
		"this is the toggle you want." )

	---------------------------------------------------------------- output
	Caption( "Output" )

	-- The texture's own resolution and halvings of it, so the map matches the
	-- material it will sit on. A normal map generated smaller than the base
	-- texture is soft exactly where the base texture is sharp, and the two are
	-- side by side on the model.
	local sizes = GEN.SizeMenu( self.SrcEntry:GetValue(),
		self.Settings.size, self.Settings.height )

	local box = Combo( "Resolution", sizes, nil,
		"Defaults to the texture's own, which is what keeps the map as sharp " ..
		"as the material it sits on. Bigger is slower to build: every pixel is " ..
		"read one at a time, so the largest sizes pause the game for a moment.",
		function( dims )
			if not istable( dims ) then return end

			this.Settings.size   = dims[ 1 ]
			this.Settings.height = ( dims[ 2 ] ~= dims[ 1 ] ) and dims[ 2 ] or nil
		end )

	box:SetValue( GEN.DimText( self.Settings.size,
		self.Settings.height or self.Settings.size ) )

	AdvMat.SizeLimitRow( parent, function()
		if not IsValid( this ) then return end

		this.SettingsPane:Clear()
		this:BuildSettings( this.SettingsPane )
		this:Changed()
	end )

	Check( "Tile edges", "wrap",
		"On for a texture that tiles, so the edges match up. Off clamps them " ..
		"instead, which suits a character sheet." )

	--------------------------------------------------------------- region
	AdvMat.RegionRow( parent, self.Settings, self.Ctx, function() this:Changed() end )

	--------------------------------------------------- mask in the alpha
	-- On a material with $phong or a $bumpmap, the shader does not read a
	-- separate $envmapmask at all - it looks in the alpha channel of the normal
	-- map. So this is the only place a reflection mask can go on most
	-- playermodels, and it belongs here rather than in a generator that would
	-- silently produce nothing.
	Caption( "Reflection mask" )

	local maskOn = Row()

	local maskBox = vgui.Create( "DCheckBoxLabel", maskOn )
	maskBox:Dock( FILL )
	AdvMat.StyleCheck( maskBox, "Put a reflection mask in the alpha channel" )
	maskBox:SetValue( self.Settings.alphamask ~= nil )
	maskBox:SetTooltip(
		"Fills this normal map's alpha channel with a mask of how reflective and " ..
		"shiny each part of the surface is.\n\n" ..
		"On a material with $phong or a bump map the engine reads its mask from " ..
		"here and ignores $envmapmask entirely, so this is where it has to live." )

	local maskBody = parent:Add( "DPanel" )
	maskBody:Dock( TOP )
	maskBody:SetTall( rowH * 3 + 8 )
	maskBody:DockMargin( 6, 2, 6, 4 )
	maskBody.Paint = AdvMat.NoPaint
	maskBody:SetVisible( self.Settings.alphamask ~= nil )

	local function MaskSlider( label, field, min, max, dec, tip )
		local s = vgui.Create( "DNumSlider", maskBody )
		s:Dock( TOP )
		s:SetTall( rowH + 2 )
		s:SetText( label )
		s:SetMin( min ) s:SetMax( max ) s:SetDecimals( dec )
		s:SetValue( ( this.Settings.alphamask or GEN.ENVMASK_DEFAULTS )[ field ] )
		if tip then s:SetTooltip( tip ) end
		AdvMat.StyleSlider( s )

		s.OnValueChanged = function( _, v )
			if not this.Settings.alphamask then return end
			this.Settings.alphamask[ field ] = v
			this:Changed()
		end
	end

	MaskSlider( "Smoothing", "blur", 0, 8, 0,
		"Blur before the curve, or the artwork itself becomes reflectivity noise." )
	MaskSlider( "Contrast", "contrast", 0, 4, 2 )
	MaskSlider( "Most reflective", "hi", 0, 1, 2,
		"Keeping the ceiling well below 1 is what stops the whole model looking wet." )

	maskBox.OnChange = function( _, v )
		if v then
			this.Settings.alphamask = this.Settings.alphamask
				or table.Copy( GEN.ENVMASK_DEFAULTS )
		else
			this.Settings.alphamask = nil
		end

		maskBody:SetVisible( v )
		this:Changed()
	end

	local note = parent:Add( "DLabel" )
	note:Dock( TOP )
	note:SetTall( rowH * 3 )
	note:DockMargin( 6, 10, 6, 6 )
	note:SetWrap( true )
	note:SetText(
		"The image is written to garrysmod/data/advmat/normals/ as a PNG. " ..
		"Convert it to a .vtf if you want to ship it with the model; until then " ..
		"the settings travel with the override and every client rebuilds it." )
	AdvMat.StyleLabel( note, "AdvMatSmall", T.TextFaint )

end

---------------------------------------------------------------------------
function PANEL:OnClose()
	AdvMat.GenDialog = nil
end

vgui.Register( "AdvMatGenDialog", PANEL, "DFrame" )

---------------------------------------------------------------------------
-- Entry point
---------------------------------------------------------------------------

--- AdvMat.OpenNormalGenerator( defaultSource, existingRecipe, onAccept, ctx )
--- `onAccept( recipe )` fires when the user presses Generate and use.
--- `ctx` is { model, slot, matpath, basekv }, needed so a region can be picked
--- by clicking the model.
function AdvMat.OpenNormalGenerator( defaultSource, existing, onAccept, ctx )
	if IsValid( AdvMat.GenDialog ) then AdvMat.GenDialog:Remove() end

	local frame = vgui.Create( "AdvMatGenDialog" )
	AdvMat.GenDialog = frame
	frame.AdvMatHost = IsValid( ctx and ctx.host ) and ctx.host
		or ( IsValid( AdvMat.Editor ) and AdvMat.Editor or nil )
	frame.OnAccept   = onAccept
	frame.Ctx        = ctx or {}

	-- Reopening an existing generated map lands back on the settings it was
	-- made with rather than the defaults.
	if istable( existing ) then
		local clean = GEN.Sanitize( existing )
		if clean then frame.Settings = table.Copy( clean ) end
	end

	frame.SrcEntry:SetValue( AdvMat.NormalizeMaterial(
		( istable( existing ) and existing.src ) or defaultSource or "" ) )

	-- A new map defaults to the resolution of the texture it is made from.
	-- Anything else either throws away half of a 1024 sheet or upscales a 256
	-- one into blur, neither of which the user asked for. Reopening an existing
	-- recipe keeps whatever it was made at.
	if not istable( existing ) then
		local nw, nh = GEN.SourceSize( frame.SrcEntry:GetValue(),
			frame.Settings.size, frame.Settings.height )

		frame.Settings.size   = nw
		frame.Settings.height = ( nh ~= nw ) and nh or nil
	end

	-- Rebuild the controls now that the settings are known.
	frame.SettingsPane:Clear()
	frame:BuildSettings( frame.SettingsPane )
	frame:Changed()

	if AdvMat.WindowUX then
		AdvMat.WindowUX.SetupFrame( frame, "normal_generator" )
		AdvMat.WindowUX.PlaceChild( frame, frame.AdvMatHost )
	end

	return frame
end

-- Refresh the preview the moment the queue finishes something we asked for.
hook.Add( "AdvMatGenerated", "AdvMat.GenDialogPreview", function( recipe, produced )
	local frame = AdvMat.GenDialog
	if not IsValid( frame ) or not frame.PreviewRecipe then return end

	if GEN.FileName( frame.PreviewRecipe ) == produced then
		frame.PreviewMat = GEN.GetMaterial( frame.PreviewRecipe )
	end
end )
