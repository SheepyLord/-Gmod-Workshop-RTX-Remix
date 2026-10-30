--[[---------------------------------------------------------------------------
	Advanced Material Editor - the surface map generator window

	Settings for the phong exponent and reflection mask generators, with a live
	preview and, more importantly, an honest account of what else the material
	needs before the map will do anything at all.

	That last part is most of the value. Both of these maps are silently inert
	in common configurations:

	  a $phongexponenttexture is ignored the moment $phongexponent is set to
	  any positive number, and phong itself does nothing without a $bumpmap

	  a $envmapmask is not read at all once a material has a $bumpmap or
	  $phong 1 - and worse, setting one with a bump map present switches
	  $envmap off, so adding the mask removes the reflection instead of
	  shaping it

	Nearly every playermodel has both a bump map and phong, so a generator that
	just wrote the texture and said nothing would appear broken on exactly the
	models people want to use it on. The window says which route applies and
	offers to set the rest up.
-----------------------------------------------------------------------------]]

AdvMat = AdvMat or {}

local T   = AdvMat.Theme
local GEN = AdvMat.Gen

local PREVIEW_SIZE  = 128
local PREVIEW_DELAY = 0.3

---------------------------------------------------------------------------
-- The region row, shared with the normal map generator
---------------------------------------------------------------------------

--- A "which part of the texture" control. `state` is the recipe being edited;
--- the row reads and writes state.region and state.regionmode directly.
--- A combo bound to this client's ceiling on generated texture sizes.
---
--- Offered next to the resolution rather than buried in a settings menu,
--- because next to the resolution is where somebody meets it: the list stops
--- at the ceiling, and "why is 2048 not on the list" has to be answerable
--- without leaving the dialog.
---
--- `onChange` runs once the console command has landed, so the caller can
--- rebuild the list whose length it just changed.
function AdvMat.SizeLimitBox( parent, onChange )
	local box = vgui.Create( "DComboBox", parent )
	box:SetSortItems( false )
	box:SetTooltip(
		"The largest texture this machine will read or generate.\n" ..
		"Every pixel is handled one at a time in Lua here, so the big sizes " ..
		"cost real time and real memory: 4096 x 4096 is a few hundred megabytes " ..
		"and a pause of several seconds. Raise it when a material needs it." )
	AdvMat.StyleCombo( box )

	local now = AdvMat.Gen.MaxSize()

	for _, px in ipairs( AdvMat.Gen.SIZES ) do
		box:AddChoice( "Up to " .. px, px, px == now )
	end

	box.OnSelect = function( _, _, _, px )
		RunConsoleCommand( "advmat_max_texture_size", tostring( px ) )

		-- A console command lands at the end of the frame, so anything reading
		-- the value back waits for that rather than rebuilding from the number
		-- it is about to stop being.
		timer.Simple( 0, function()
			if IsValid( parent ) and onChange then onChange() end
		end )
	end

	return box
end

--- The same control with a label in front of it, for the dialogs that lay
--- their settings out in labelled rows.
function AdvMat.SizeLimitRow( parent, onChange )
	local row = parent:Add( "DPanel" )
	row:Dock( TOP )
	row:SetTall( AdvMat.RowHeight() + 6 )
	row:DockMargin( 6, 2, 6, 2 )
	row.Paint = AdvMat.NoPaint

	local tag = vgui.Create( "DLabel", row )
	tag:Dock( LEFT )
	tag:SetWide( AdvMat.LabelWidth() )
	tag:SetText( "Largest allowed" )
	AdvMat.StyleLabel( tag, "AdvMatText", T.Text )

	local box = AdvMat.SizeLimitBox( row, onChange )
	box:Dock( FILL )

	return row
end

function AdvMat.RegionRow( parent, state, ctx, onChange )
	local rowH = AdvMat.RowHeight()

	local box = parent:Add( "DPanel" )
	box:Dock( TOP )
	box:SetTall( rowH * 3 + 12 )
	box:DockMargin( 6, 8, 6, 4 )
	box.Paint = AdvMat.Fill( T.Row )

	local head = vgui.Create( "DLabel", box )
	head:Dock( TOP )
	head:SetTall( rowH )
	head:DockMargin( 6, 4, 6, 0 )
	head:SetText( "Where to change" )
	AdvMat.StyleLabel( head, "AdvMatBold", T.Text )

	local desc = vgui.Create( "DLabel", box )
	desc:Dock( TOP )
	desc:SetTall( rowH )
	desc:DockMargin( 6, 0, 6, 0 )
	AdvMat.StyleLabel( desc, "AdvMatSmall", T.TextDim )

	local strip = vgui.Create( "DPanel", box )
	strip:Dock( TOP )
	strip:SetTall( rowH + 4 )
	strip:DockMargin( 6, 2, 6, 4 )
	strip.Paint = AdvMat.NoPaint

	local function Refresh()
		if not state.region then
			desc:SetText( AdvMat.L( "surface.whole_desc" ) )
			return
		end

		desc:SetText( AdvMat.L(
			state.regionmode == "outside" and "surface.region_outside"
				or "surface.region_inside",
			{ area = AdvMat.Sel.Describe( state.region ) }
		) )
	end

	local choose = vgui.Create( "DButton", strip )
	choose:Dock( LEFT )
	choose:SetWide( AdvMat.FontSize * 10 )
	choose:SetText( "Choose the area..." )
	choose:SetTooltip( "Opens the texture editor's selection tools, including " ..
		"clicking the model to pick a piece of it." )
	AdvMat.StyleButton( choose )

	choose.DoClick = function()
		AdvMat.OpenRegionPicker( state.region, ctx, function( sel )
			state.region = sel
			state.regionmode = state.regionmode or "inside"
			Refresh()
			if onChange then onChange() end
		end )
	end

	local clear = vgui.Create( "DButton", strip )
	clear:Dock( LEFT )
	clear:SetWide( AdvMat.FontSize * 7 )
	clear:DockMargin( 6, 0, 0, 0 )
	clear:SetText( "Whole texture" )
	AdvMat.StyleButton( clear )

	clear.DoClick = function()
		state.region = nil
		Refresh()
		if onChange then onChange() end
	end

	local flip = vgui.Create( "DButton", strip )
	flip:Dock( LEFT )
	flip:SetWide( AdvMat.FontSize * 8 )
	flip:DockMargin( 6, 0, 0, 0 )
	flip:SetText( "Inside / outside" )
	flip:SetTooltip( "Swap between changing what you picked and changing everything else." )
	AdvMat.StyleButton( flip )

	flip.DoClick = function()
		state.regionmode = ( state.regionmode == "outside" ) and "inside" or "outside"
		Refresh()
		if onChange then onChange() end
	end

	Refresh()
	return box
end

---------------------------------------------------------------------------
-- What the material needs alongside the map
---------------------------------------------------------------------------

--- The companion parameters that make a generated map actually do something,
--- plus the sentence explaining why. Returned rather than applied, so the
--- caller can show it before writing anything.
local function Companions( kind, recipe, basekv )
	basekv = basekv or {}

	local set, unset, notes = {}, {}, {}

	if kind == "phongexp" then
		set[ "$phong" ] = "1"

		local preset = GEN.PhongPreset( recipe.preset )
		if preset and preset.boost then
			set[ "$phongboost" ] = AdvMat.NumToString( preset.boost )
		end

		set[ "$phongfresnelranges" ] = "[0.05 0.5 1]"

		-- Any POSITIVE $phongexponent replaces the whole exponent texture, so a
		-- map plus a leftover scalar is a map that does nothing at all. Zero is
		-- the documented way to say "use the texture instead", and unlike
		-- removing the parameter it survives being written to a material that
		-- already had one.
		if basekv[ "$phongexponent" ] and ( tonumber( basekv[ "$phongexponent" ] ) or 0 ) > 0 then
			set[ "$phongexponent" ] = "0"
			notes[ #notes + 1 ] = AdvMat.L( "surface.note_exponent", {
				value = basekv[ "$phongexponent" ],
			} )
		end

		if recipe.tintmode and recipe.tintmode ~= "none" then
			set[ "$phongalbedotint" ] = "1"

			if basekv[ "$phongtint" ] then
				notes[ #notes + 1 ] = AdvMat.L( "surface.note_phongtint" )
			end
		end

		-- Source forces half lambert on whenever phong is enabled, which
		-- visibly flattens the diffuse falloff on a character.
		set[ "$phongdisablehalflambert" ] = "1"

		if not basekv[ "$bumpmap" ] then
			notes[ #notes + 1 ] = AdvMat.L( "surface.note_no_bump" )
		end

	elseif kind == "envmapmask" then
		set[ "$envmap" ] = basekv[ "$envmap" ] or "env_cubemap"

		local route, why = AdvMat.ReflectionRoute( basekv )
		notes[ #notes + 1 ] = why

		if route ~= AdvMat.REFLECT_ROUTE.ENVMAPMASK then
			notes[ #notes + 1 ] = AdvMat.L( "surface.note_route" )
		end

		if not basekv[ "$envmap" ] then
			notes[ #notes + 1 ] = AdvMat.L( "surface.note_envmap" )
		end
	end

	return set, unset, notes
end

---------------------------------------------------------------------------
-- The window
---------------------------------------------------------------------------
local PANEL = {}

function PANEL:Init()
	self.Recipe = {}

	local rowH = AdvMat.RowHeight()

	-- Preserve a practical controls column beside the preview/notes pane while
	-- keeping the resize floor inside the current screen on compact displays.
	self:SetMinWidth( math.min( math.max( 720, AdvMat.FontSize * 32 ),
		math.max( 1, ScrW() - 24 ) ) )
	self:SetMinHeight( math.min( 500, math.max( 1, ScrH() - 24 ) ) )
	self:SetSize( math.min( 1000, ScrW() - 80 ), math.min( 700, ScrH() - 80 ) )
	self:SetSizable( true )
	self:Center()
	self:MakePopup()
	AdvMat.StyleFrame( self )

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

	local ok = vgui.Create( "DButton", bottom )
	ok:Dock( RIGHT )
	ok:SetWide( AdvMat.FontSize * 8 )
	ok:SetText( "Use this map" )
	ok.DoClick = function() self:Apply() end
	AdvMat.StyleButton( ok )

	self.SetUp = vgui.Create( "DCheckBoxLabel", bottom )
	self.SetUp:Dock( LEFT )
	self.SetUp:DockMargin( 0, 4, 12, 4 )
	AdvMat.StyleCheck( self.SetUp, "Also set the material up to use it" )
	self.SetUp:SetValue( true )
	self.SetUp:SetTooltip( "Sets the other parameters this map needs. Without them " ..
		"the map is generated but the engine never reads it." )

	self.Summary = vgui.Create( "DLabel", bottom )
	self.Summary:Dock( FILL )
	AdvMat.StyleLabel( self.Summary, "AdvMatSmall", T.TextDim )

	--------------------------------------------------------------- preview
	local right = vgui.Create( "DPanel", self )
	right:Dock( RIGHT )
	right:SetWide( math.max( 300, AdvMat.FontSize * 20 ) )
	right:DockMargin( 6, 0, 0, 0 )
	right.Paint = AdvMat.NoPaint

	self.Preview = vgui.Create( "DPanel", right )
	self.Preview:Dock( TOP )
	self.Preview:SetTall( math.max( 220, math.floor( ScrH() * 0.22 ) ) )
	self.Preview.Paint = function( pnl, w, h )
		surface.SetDrawColor( 24, 25, 29, 255 )
		surface.DrawRect( 0, 0, w, h )

		local mat = self.PreviewMat

		if not mat then
			draw.SimpleText( AdvMat.LText( "Generating..." ), "AdvMatText", w * 0.5, h * 0.5,
				T.TextFaint, TEXT_ALIGN_CENTER, TEXT_ALIGN_CENTER )
			return
		end

		local size = math.min( w, h ) - 16
		surface.SetDrawColor( 255, 255, 255, 255 )
		surface.SetMaterial( mat )
		surface.DrawTexturedRect( ( w - size ) * 0.5, ( h - size ) * 0.5, size, size )
	end

	self.Notes = vgui.Create( "DScrollPanel", right )
	self.Notes:Dock( FILL )
	self.Notes:DockMargin( 0, 6, 0, 0 )
	self.Notes.Paint = AdvMat.Fill( T.Panel )

	---------------------------------------------------------------- source
	local top = vgui.Create( "DPanel", self )
	top:Dock( TOP )
	top:SetTall( rowH + 2 )
	top:DockMargin( 0, 0, 0, 6 )
	top.Paint = AdvMat.NoPaint

	local tag = vgui.Create( "DLabel", top )
	tag:Dock( LEFT )
	tag:SetWide( AdvMat.FontSize * 9 )
	tag:SetText( "Read the colours from" )
	AdvMat.StyleLabel( tag, "AdvMatText", T.TextDim )

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

	------------------------------------------------------------- settings
	self.Body = vgui.Create( "DScrollPanel", self )
	self.Body:Dock( FILL )
	self.Body.Paint = AdvMat.Fill( T.Panel )
end

---------------------------------------------------------------------------
-- Settings
---------------------------------------------------------------------------
local function Slider( parent, label, min, max, dec, value, tip, fn )
	local s = parent:Add( "DNumSlider" )
	s:Dock( TOP )
	s:SetTall( AdvMat.RowHeight() + 6 )
	s:DockMargin( 6, 2, 6, 2 )
	s:SetText( label )
	s:SetMin( min ) s:SetMax( max ) s:SetDecimals( dec ) s:SetValue( value )
	if tip then s:SetTooltip( tip ) end
	AdvMat.StyleSlider( s )
	s.OnValueChanged = fn
	return s
end

local function Combo( parent, label, list, current, tip, fn )
	local row = parent:Add( "DPanel" )
	row:Dock( TOP )
	row:SetTall( AdvMat.RowHeight() + 6 )
	row:DockMargin( 6, 2, 6, 2 )
	row.Paint = AdvMat.NoPaint

	local tag = vgui.Create( "DLabel", row )
	tag:Dock( LEFT )
	tag:SetWide( AdvMat.LabelWidth() )
	tag:SetText( label )
	AdvMat.StyleLabel( tag, "AdvMatText", T.Text )

	local box = vgui.Create( "DComboBox", row )
	box:Dock( FILL )
	box:SetSortItems( false )
	if tip then box:SetTooltip( tip ) end
	AdvMat.StyleCombo( box )

	for _, entry in ipairs( list ) do
		-- An entry that knows for itself whether it is the current one, for a
		-- choice that is more than a single value - the resolution is two.
		box:AddChoice( entry.name, entry.id, entry.on or entry.id == current )
	end

	box.OnSelect = function( _, _, _, data ) fn( data ) end
	return box
end

local function Note( parent, text, warn )
	local lines = AdvMat.WrapText( text, "AdvMatSmall",
		math.max( 120, parent:GetWide() - 24 ) )

	local l = parent:Add( "DPanel" )
	l:Dock( TOP )
	l:SetTall( #lines * ( AdvMat.FontSize + 3 ) + 10 )
	l:DockMargin( 6, 4, 6, 0 )
	l.Paint = function( pnl, w, h )
		surface.SetDrawColor( T.Row.r, T.Row.g, T.Row.b, 255 )
		surface.DrawRect( 0, 0, w, h )

		local accent = warn and T.Warn or T.Accent
		surface.SetDrawColor( accent.r, accent.g, accent.b, 255 )
		surface.DrawRect( 0, 0, 3, h )

		for i, line in ipairs( lines ) do
			draw.SimpleText( line, "AdvMatSmall", 10,
				5 + ( i - 1 ) * ( AdvMat.FontSize + 3 ), warn and T.Warn or T.TextDim )
		end
	end

	return l
end

function PANEL:BuildSettings()
	self.Body:Clear()

	local R = self.Recipe

	if self.Kind == "phongexp" then
		Combo( self.Body, "What is it made of", GEN.PHONG_PRESETS, R.preset,
			"Sets sensible starting values for that kind of surface.", function( id )
				local preset = GEN.PhongPreset( id )
				R.preset = id

				if preset and preset.base then
					R.base, R.range = preset.base, preset.range
					R.levels, R.tintmode = preset.levels, preset.tint
				end

				self:BuildSettings()
				self:Changed()
			end )

		Slider( self.Body, "Base sharpness", 0, 255, 0, R.base,
			"How tight the highlight is where the texture gives no reason to change it.",
			function( _, v ) R.base = v self:Changed() end )

		Slider( self.Body, "How much the texture changes it", -255, 255, 0, R.range,
			"Bright, colourless areas read as metal and get a tighter highlight.",
			function( _, v ) R.range = v self:Changed() end )

		Slider( self.Body, "Ignore fine detail", 0, 3, 2, R.detail,
			"Fine detail in the texture means a rough surface, which gets a broader " ..
			"highlight. Turn this down to let printed patterns through.",
			function( _, v ) R.detail = v self:Changed() end )

		Slider( self.Body, "Smoothing", 0, 8, 0, R.smooth,
			"Blurs the result. A real exponent map is broad flat areas, not a copy " ..
			"of the artwork.",
			function( _, v ) R.smooth = v self:Changed() end )

		Slider( self.Body, "Number of zones", 0, 16, 0, R.levels,
			"Steps the result into this many flat levels. 0 leaves it smooth. " ..
			"If you can still recognise the character in the preview, use fewer zones.",
			function( _, v ) R.levels = v self:Changed() end )

		Combo( self.Body, "Colour the highlight", GEN.PHONG_TINTMODES, R.tintmode,
			"Metal reflects its own colour; skin and cloth reflect white. This only " ..
			"does anything with $phongalbedotint 1, which will be set for you.",
			function( id ) R.tintmode = id self:BuildSettings() self:Changed() end )

		if R.tintmode == "constant" then
			Slider( self.Body, "How much colour", 0, 255, 0, R.tint, nil,
				function( _, v ) R.tint = v self:Changed() end )
		end

		Slider( self.Body, "Rim light mask", 0, 255, 0, R.rim,
			"Goes in the alpha channel. Only read when $rimlight 1 and $rimmask 1 " ..
			"are both set; 255 means no masking.",
			function( _, v ) R.rim = v self:Changed() end )

	else
		Combo( self.Body, "What counts as shiny", GEN.SURFACE_SOURCES, R.source,
			"Bright and colourless is the signature of bare metal. Brightness alone " ..
			"makes a red shirt as reflective as a chrome buckle.",
			function( id ) R.source = id self:Changed() end )

		Slider( self.Body, "Smoothing", 0, 8, 0, R.blur,
			"Blurs before the curve is applied. Without it the artwork itself becomes " ..
			"reflectivity noise.",
			function( _, v ) R.blur = v self:Changed() end )

		Slider( self.Body, "Contrast", 0, 4, 2, R.contrast, nil,
			function( _, v ) R.contrast = v self:Changed() end )

		Slider( self.Body, "Curve", 0.2, 4, 2, R.gamma,
			"Above 1 pushes more of the surface towards matte.",
			function( _, v ) R.gamma = v self:Changed() end )

		Slider( self.Body, "Least reflective", 0, 1, 2, R.lo, nil,
			function( _, v ) R.lo = v self:Changed() end )

		Slider( self.Body, "Most reflective", 0, 1, 2, R.hi,
			"Keeping the ceiling well below 1 is what stops the whole model looking wet.",
			function( _, v ) R.hi = v self:Changed() end )
	end

	local inv = self.Body:Add( "DCheckBoxLabel" )
	inv:Dock( TOP )
	inv:DockMargin( 6, 4, 6, 4 )
	AdvMat.StyleCheck( inv, "Turn it inside out" )
	inv:SetValue( R.invert or false )
	inv.OnChange = function( _, v ) R.invert = v self:Changed() end

	-- The texture's own resolution and halvings of it, so the mask matches the
	-- material it will sit on rather than being visibly softer than it.
	Combo( self.Body, "Size", GEN.SizeMenu( self.SrcEntry:GetValue(), R.size, R.height ),
		nil,
		"Defaults to the texture's own, which is what keeps the mask as sharp " ..
		"as the material it sits on. Bigger takes longer to build and uses " ..
		"more memory.",
		function( dims )
			if not istable( dims ) then return end

			R.size   = dims[ 1 ]
			R.height = ( dims[ 2 ] ~= dims[ 1 ] ) and dims[ 2 ] or nil

			self:Changed()
		end )

	AdvMat.SizeLimitRow( self.Body, function()
		if not IsValid( self ) then return end

		self:BuildSettings()
		self:Changed()
	end )

	AdvMat.RegionRow( self.Body, R, self.Ctx, function() self:Changed() end )
end

---------------------------------------------------------------------------
-- Preview and notes
---------------------------------------------------------------------------
function PANEL:BuildRecipe( size )
	local R = self.Recipe

	local copy = table.Copy( R )
	copy.kind = self.Kind
	copy.src  = self.SrcEntry:GetValue()

	-- `size` caps the longer side for the preview. The shape is kept, because
	-- a square preview of an oblong sheet previews something else.
	local w, h = R.size, R.height or R.size
	if size then w, h = GEN.FitWithin( w, h, size ) end

	copy.size   = w
	copy.height = h

	copy.model   = self.Ctx.model
	copy.slot    = self.Ctx.slot
	copy.matpath = self.Ctx.matpath
	copy.mask    = self.Ctx.mask

	return GEN.Sanitize( copy )
end

function PANEL:Changed()
	local recipe = self:BuildRecipe()

	self.Summary:SetText( recipe and GEN.Describe( recipe ) or "No source texture chosen." )

	self:RefreshNotes()

	timer.Create( "AdvMat.SurfacePreview", PREVIEW_DELAY, 1, function()
		if not IsValid( self ) then return end

		-- GetMaterial returns nothing the first time and queues the build
		-- instead, so the recipe is remembered and the hook below picks the
		-- result up. Without that the preview says "Generating..." for ever.
		local small = self:BuildRecipe( PREVIEW_SIZE )

		self.PreviewRecipe = small
		self.PreviewMat    = small and GEN.GetMaterial( small ) or nil
	end )
end

function PANEL:RefreshNotes()
	self.Notes:Clear()

	local set, unset, notes = Companions( self.Kind, self.Recipe, self.Ctx.basekv )

	self.Pending = { set = set, unset = unset }

	local head = self.Notes:Add( "DLabel" )
	head:Dock( TOP )
	head:SetTall( AdvMat.RowHeight() )
	head:DockMargin( 6, 4, 6, 0 )
	head:SetText( "What else this needs" )
	AdvMat.StyleLabel( head, "AdvMatBold", T.Text )

	local keys = {}
	for k in pairs( set ) do keys[ #keys + 1 ] = k end
	table.sort( keys )

	for _, k in ipairs( keys ) do
		local l = self.Notes:Add( "DLabel" )
		l:Dock( TOP )
		l:SetTall( AdvMat.RowHeight() )
		l:DockMargin( 12, 0, 6, 0 )
		l:SetText( k .. "  " .. set[ k ] )
		AdvMat.StyleLabel( l, "AdvMatSmall", T.Accent )
	end

	for _, k in ipairs( unset ) do
		local l = self.Notes:Add( "DLabel" )
		l:Dock( TOP )
		l:SetTall( AdvMat.RowHeight() )
		l:DockMargin( 12, 0, 6, 0 )
		l:SetText( "remove " .. k )
		AdvMat.StyleLabel( l, "AdvMatSmall", T.Danger )
	end

	for _, text in ipairs( notes ) do
		Note( self.Notes, text, true )
	end
end

---------------------------------------------------------------------------
-- Opening and applying
---------------------------------------------------------------------------
function PANEL:Setup( kind, src, recipe, ctx, done )
	self.Kind = kind
	self.Ctx  = ctx or {}
	self.Done = done

	local defaults = ( kind == "phongexp" ) and GEN.PHONG_DEFAULTS or GEN.ENVMASK_DEFAULTS

	self.Recipe = table.Copy( defaults )

	if istable( recipe ) then
		for k, v in pairs( recipe ) do self.Recipe[ k ] = v end
	end

	self:SetTitle( ( kind == "phongexp" )
		and "Make a phong exponent map"
		or  "Make a reflection mask" )

	self.SrcEntry:SetValue( src or recipe and recipe.src or "" )

	-- Same rule as the normal map generator: a new map matches the resolution
	-- of the texture it is derived from, and a reopened one keeps its own.
	if not istable( recipe ) then
		local nw, nh = GEN.SourceSize( self.SrcEntry:GetValue(),
			self.Recipe.size, self.Recipe.height )

		self.Recipe.size   = nw
		self.Recipe.height = ( nh ~= nw ) and nh or nil
	end

	self:BuildSettings()
	self:Changed()
end

function PANEL:Apply()
	local recipe = self:BuildRecipe()

	if not recipe then
		AdvMat.NotifyLocal( "Choose a source texture first.", NOTIFY_ERROR, 4 )
		return
	end

	if self.Done then
		self.Done( recipe, self.SetUp:GetChecked() and self.Pending or nil )
	end

	self:Close()
end

vgui.Register( "AdvMatSurfaceGen", PANEL, "DFrame" )

--- Open the generator for one of the two surface map kinds.
function AdvMat.OpenSurfaceGenerator( kind, src, recipe, ctx, done )
	if IsValid( AdvMat.SurfaceDialog ) then AdvMat.SurfaceDialog:Remove() end

	local frame = vgui.Create( "AdvMatSurfaceGen" )
	AdvMat.SurfaceDialog = frame
	frame.AdvMatHost = IsValid( ctx and ctx.host ) and ctx.host
		or ( IsValid( AdvMat.Editor ) and AdvMat.Editor or nil )

	frame:Setup( kind, src, recipe, ctx, done )
	if AdvMat.WindowUX then
		AdvMat.WindowUX.SetupFrame( frame,
			"surface_generator_" .. tostring( kind or "map" ) )
		AdvMat.WindowUX.PlaceChild( frame, frame.AdvMatHost )
	end
	return frame
end

-- Refresh the preview the moment the queue finishes the image it was waiting
-- for. The generator queue is asynchronous, so the first GetMaterial after a
-- settings change always comes back empty.
hook.Add( "AdvMatGenerated", "AdvMat.SurfaceDialogPreview", function( _, produced )
	local frame = AdvMat.SurfaceDialog
	if not IsValid( frame ) or not frame.PreviewRecipe then return end

	if GEN.FileName( frame.PreviewRecipe ) == produced then
		frame.PreviewMat = GEN.GetMaterial( frame.PreviewRecipe )
	end
end )
