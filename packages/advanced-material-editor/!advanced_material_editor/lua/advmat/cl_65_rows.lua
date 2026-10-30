--[[---------------------------------------------------------------------------
	Advanced Material Editor - parameter row widgets

	One row per VMT parameter. Every row talks to the editor through a small
	context table so the rows know nothing about entities or rules:

	    ctx.Get( key )        -> the value, as a VMT literal string (one value)
	    ctx.State( key )      -> isOverridden, isInherited
	    ctx.Set( key, value ) -> value may be nil to drop the override
	    ctx.BaseTexture()     -> path of $basetexture, for texture suggestions

	Get deliberately returns a single value. It used to return the two state
	flags alongside it, which made `tonumber( ctx.Get( k ) )` pass a boolean
	as tonumber's base argument.

	Values are always VMT literal strings. Each widget parses on the way in and
	formats on the way out, so what you see in the raw text box is exactly what
	would be written into a .vmt.
-----------------------------------------------------------------------------]]

AdvMat      = AdvMat or {}
AdvMat.Rows = AdvMat.Rows or {}

local T     = AdvMat.Theme
local BTN_W = 22

-- Row metrics scale with the screen, so the panel stays legible at 4K without
-- the text overflowing its row at 1080p.
local function RowH()   return AdvMat.RowHeight()  end
local function LabelW() return AdvMat.LabelWidth() end

-- Which of the three states a parameter is in has to be obvious at a glance,
-- so the colours are pulled well apart rather than being three near-identical
-- greys against a grey panel.
local COL_OVERRIDE = T.Accent
local COL_INHERIT  = T.TextDim
local COL_UNSET    = T.TextFaint


---------------------------------------------------------------------------
-- Layout
---------------------------------------------------------------------------

--- Height of a category body, measured from its children rather than counted.
--- A transform row contributes a second panel that expands and collapses, so
--- the caller cannot know the total in advance.
function AdvMat.SizeRows( body )
	if not IsValid( body ) then return end

	local tall = 4

	for _, child in ipairs( body:GetChildren() ) do
		if child:IsVisible() then tall = tall + child:GetTall() + 1 end
	end

	body:SetTall( tall )

	local cat = body:GetParent()
	if IsValid( cat ) and cat.InvalidateLayout then cat:InvalidateLayout( true ) end
end

---------------------------------------------------------------------------
-- Parameter help
---------------------------------------------------------------------------
local helpPanel

function AdvMat.CloseParamHelp()
	if IsValid( helpPanel ) then helpPanel:Remove() end
	helpPanel = nil
end

--- Floating explanation for one parameter, shown from the "?" on its row.
---
--- Parented to the editor rather than made a popup: a popup would take
--- keyboard focus the moment the cursor crossed the "?", which would drop you
--- out of whatever text box you were typing in.
local function ShowParamHelp( param, shader )
	AdvMat.CloseParamHelp()

	local host = IsValid( AdvMat.Editor ) and AdvMat.Editor or nil
	local body, facts = AdvMat.GetHelp( shader, param.name )

	local limitW = ( host and host:GetWide()  or ScrW() ) - 24
	local limitH = ( host and host:GetTall()  or ScrH() ) - 24

	local pad   = math.floor( AdvMat.FontSize * 0.7 )
	local wide  = math.min( math.floor( AdvMat.FontSize * 34 ), limitW )
	local inner = wide - pad * 2

	-- Wrapped and measured up front. Letting DLabel stretch itself meant the
	-- panel was sized before the text knew how tall it was, so anything that
	-- ran past the first line got clipped off the bottom.
	local factLines = AdvMat.WrapText( facts, "AdvMatSmall", inner )
	local bodyLines = AdvMat.WrapText( body,  "AdvMatText",  inner )

	local titleH = AdvMat.FontSize + 9
	local factH  = AdvMat.FontSize + 2
	local lineH  = AdvMat.FontSize + 4
	local gap    = 6

	local tall = pad * 2 + titleH + #factLines * factH + gap + #bodyLines * lineH

	local pnl = vgui.Create( "DPanel", host )
	helpPanel = pnl

	pnl:SetSize( wide, math.min( tall, limitH ) )
	pnl:SetDrawOnTop( true )
	pnl:SetMouseInputEnabled( false )

	pnl.Paint = function( _, w, h )
		surface.SetDrawColor( 20, 22, 26, 250 )
		surface.DrawRect( 0, 0, w, h )

		surface.SetDrawColor( T.Accent.r, T.Accent.g, T.Accent.b, 255 )
		surface.DrawOutlinedRect( 0, 0, w, h, 1 )

		local y = pad

		draw.SimpleText( param.name, "AdvMatBold", pad, y, T.Accent )
		y = y + titleH

		for _, line in ipairs( factLines ) do
			draw.SimpleText( line, "AdvMatSmall", pad, y, T.TextDim )
			y = y + factH
		end

		y = y + gap

		for _, line in ipairs( bodyLines ) do
			draw.SimpleText( line, "AdvMatText", pad, y, T.Text )
			y = y + lineH
		end
	end

	-- Placed next to the cursor, in whatever coordinate space the panel ended
	-- up living in, and kept fully inside it.
	local mx, my = input.GetCursorPos()
	if host then mx, my = host:ScreenToLocal( mx, my ) end

	pnl:SetPos(
		math.Clamp( mx + 20, 8, math.max( 8, limitW - pnl:GetWide() + 12 ) ),
		math.Clamp( my + 10, 8, math.max( 8, limitH - pnl:GetTall() + 12 ) ) )

	return pnl
end

---------------------------------------------------------------------------
-- Shared row chrome
---------------------------------------------------------------------------
--- `tall` defaults to one row; a texture row asks for more so its thumbnail
--- is worth looking at.
local function BuildRow( parent, ctx, param, index, tall )
	tall = tall or RowH()

	local row = vgui.Create( "DPanel", parent )
	row:Dock( TOP )
	row:SetTall( tall )
	row:DockMargin( 0, 0, 0, 1 )
	row.Param = param
	row.Ctx   = ctx

	local stripe = ( ( index or 0 ) % 2 == 0 ) and T.RowAlt or T.Row

	row.Paint = function( self, w, h )
		local overridden = ctx.State( param.name )
		local col = overridden and T.RowSet or stripe

		surface.SetDrawColor( col.r, col.g, col.b, 255 )
		surface.DrawRect( 0, 0, w, h )

		if overridden then
			surface.SetDrawColor( COL_OVERRIDE.r, COL_OVERRIDE.g, COL_OVERRIDE.b, 255 )
			surface.DrawRect( 0, 0, 3, h )
		end

	end

	------------------------------------------------------------- revert
	local revert = vgui.Create( "DButton", row )
	revert:Dock( RIGHT )
	revert:SetWide( BTN_W )
	revert:SetText( "" )
	revert:SetTooltip( "Remove this override and fall back to the material's own value" )
	revert.Paint = function( self, w, h )
		local overridden = ctx.State( param.name )
		local col = overridden
			and ( self:IsHovered() and Color( 255, 150, 150 ) or T.Danger )
			or  Color( 92, 96, 104 )
		draw.SimpleText( "x", "AdvMatBold", w * 0.5, h * 0.5, col,
			TEXT_ALIGN_CENTER, TEXT_ALIGN_CENTER )
	end
	revert.DoClick = function()
		ctx.Set( param.name, nil )
		if row.Sync then row:Sync() end
	end

	--------------------------------------------------------------- help
	local help = vgui.Create( "DButton", row )
	help:Dock( RIGHT )
	help:SetWide( BTN_W )
	help:SetText( "" )
	help:SetTooltip( "What does this do?" )

	help.Paint = function( pnl, w, h )
		draw.SimpleText( "?", "AdvMatBold", w * 0.5, h * 0.5,
			pnl:IsHovered() and T.Accent or Color( 120, 125, 135 ),
			TEXT_ALIGN_CENTER, TEXT_ALIGN_CENTER )
	end

	-- Hover to read, click to keep it up while you change something.
	help.OnCursorEntered = function()
		ShowParamHelp( param, ctx.Shader and ctx.Shader() or "VertexLitGeneric" )
	end

	help.OnCursorExited = function()
		if not help.Pinned then AdvMat.CloseParamHelp() end
	end

	help.DoClick = function()
		help.Pinned = not help.Pinned
		if not help.Pinned then AdvMat.CloseParamHelp() end
	end

	-------------------------------------------------------------- label
	local label = vgui.Create( "DLabel", row )
	label:Dock( LEFT )
	label:SetWide( LabelW() )
	label:SetFont( "AdvMatText" )
	label:DockMargin( 8, 0, 0, 0 )
	label:SetText( param.name )
	label:SetTooltip( AdvMat.LocalizedParamDescription(
		ctx.Shader and ctx.Shader() or "VertexLitGeneric", param ) ..
		( param.requires and param.requires ~= "" and
			( "\n" .. AdvMat.L( "help.needs", { value = param.requires } ) ) or "" ) ..
		( param.compileTime and ( "\n" .. AdvMat.L( "help.rebuild" ) ) or "" ) ..
		( blocked and ( "\n" .. AdvMat.L( "help.inert" ) ) or "" ) )

	label.Think = function( self )
		local overridden, inherited = ctx.State( param.name )
		self:SetTextColor( overridden and COL_OVERRIDE or ( inherited and COL_INHERIT or COL_UNSET ) )
	end

	--------------------------------------------------------------- lead
	-- An optional full-height slot between the name and the controls, docked
	-- here so it lands in the right place; rows that do not want one leave it
	-- hidden, and a hidden panel takes no space in the dock layout.
	local lead = vgui.Create( "DPanel", row )
	lead:Dock( LEFT )
	lead:SetWide( 0 )
	lead:SetVisible( false )
	lead.Paint = AdvMat.NoPaint

	-------------------------------------------------------------- body
	-- On a tall row the controls stay one row high and sit in the middle,
	-- rather than stretching into oddly large text boxes and buttons.
	local inset = math.floor( ( tall - RowH() ) * 0.5 ) + 2

	local body = vgui.Create( "DPanel", row )
	body:Dock( FILL )
	body:DockMargin( 6, inset, 4, inset )
	body.Paint = AdvMat.NoPaint

	row.Body   = body
	row.Lead   = lead
	row.Label  = label
	row.Revert = revert
	row.Help   = help

	--- Change the row's height after it has been built, keeping the controls
	--- one row high and centred. A texture row uses this to grow when a texture
	--- is put in it and collapse again when it is cleared, so an empty
	--- parameter does not reserve space for a thumbnail of nothing.
	function row:Resize( newTall )
		if self:GetTall() == newTall then return false end

		local pad = math.floor( ( newTall - RowH() ) * 0.5 ) + 2

		self:SetTall( newTall )
		body:DockMargin( 6, pad, 4, pad )

		return true
	end

	return row
end

---------------------------------------------------------------------------
-- bool
---------------------------------------------------------------------------
AdvMat.Rows.bool = function( parent, ctx, param, index )
	local row = BuildRow( parent, ctx, param, index )

	local check = vgui.Create( "DCheckBox", row.Body )
	check:Dock( LEFT )
	check:SetWide( RowH() - 10 )
	check:DockMargin( 0, 1, 0, 1 )

	row.Sync = function()
		local v = ctx.Get( param.name )
		row.Setting = true
		check:SetChecked( tonumber( v ) ~= nil and tonumber( v ) ~= 0 )
		row.Setting = false
	end

	check.OnChange = function( _, val )
		if row.Setting then return end
		ctx.Set( param.name, val and "1" or "0" )
	end

	row:Sync()
	return row
end

---------------------------------------------------------------------------
-- numeric (float / int)
---------------------------------------------------------------------------
local function NumericRow( parent, ctx, param, decimals, index )
	local row = BuildRow( parent, ctx, param, index )

	local minv = tonumber( param.min ) or 0
	local maxv = tonumber( param.max ) or 1
	if maxv <= minv then maxv = minv + 1 end

	local slider = vgui.Create( "DNumSlider", row.Body )
	slider:Dock( FILL )
	slider:SetText( "" )
	slider:SetMin( minv )
	slider:SetMax( maxv )
	slider:SetDecimals( decimals )
	AdvMat.StyleSlider( slider )

	row.Sync = function()
		local v = tonumber( ctx.Get( param.name ) ) or minv

		-- Documented ranges are conventions, not limits. Widen rather than
		-- silently clamping a value the material already carries.
		if v < slider:GetMin() then slider:SetMin( v ) end
		if v > slider:GetMax() then slider:SetMax( v ) end

		row.Setting = true
		slider:SetValue( v )
		row.Setting = false
	end

	slider.OnValueChanged = function( _, val )
		if row.Setting then return end
		ctx.Set( param.name, decimals == 0
			and tostring( math.Round( val ) )
			or  AdvMat.NumToString( math.Round( val, decimals ) ) )
	end

	row:Sync()
	return row
end

AdvMat.Rows.float = function( parent, ctx, param, index )
	return NumericRow( parent, ctx, param, 3, index )
end

AdvMat.Rows.int = function( parent, ctx, param, index )
	return NumericRow( parent, ctx, param, 0, index )
end

---------------------------------------------------------------------------
-- multi component numeric ( vector2 / vector3 / vector4 )
---------------------------------------------------------------------------
local function VectorRow( parent, ctx, param, count, index )
	local row     = BuildRow( parent, ctx, param, index )
	local entries = {}

	local function Push()
		if row.Setting then return end
		local parts = {}
		for i = 1, count do
			parts[ i ] = AdvMat.NumToString( tonumber( entries[ i ]:GetValue() ) or 0 )
		end
		ctx.Set( param.name, "[" .. table.concat( parts, " " ) .. "]" )
	end

	for i = 1, count do
		local e = vgui.Create( "DTextEntry", row.Body )
		e:Dock( LEFT )
		e:SetWide( 62 )
		e:DockMargin( 0, 0, 4, 0 )
		e:SetNumeric( true )
		e:SetUpdateOnType( false )
		AdvMat.StyleEntry( e )
		e.OnValueChange = Push
		e.OnEnter       = Push
		entries[ i ] = e
	end

	row.Sync = function()
		local v = ctx.Get( param.name )
		local body = string.gsub( tostring( v or "" ), "[%[%]{}]", " " )

		local nums = {}
		for tok in string.gmatch( body, "[-%d%.eE+]+" ) do nums[ #nums + 1 ] = tonumber( tok ) end

		row.Setting = true
		for i = 1, count do
			entries[ i ]:SetValue( AdvMat.NumToString( nums[ i ] or 0 ) )
		end
		row.Setting = false
	end

	row:Sync()
	return row
end

AdvMat.Rows.vector2 = function( parent, ctx, param, index )
	return VectorRow( parent, ctx, param, 2, index )
end

AdvMat.Rows.vector3 = function( parent, ctx, param, index )
	return VectorRow( parent, ctx, param, 3, index )
end

AdvMat.Rows.vector4 = function( parent, ctx, param, index )
	return VectorRow( parent, ctx, param, 4, index )
end

---------------------------------------------------------------------------
-- colour
---------------------------------------------------------------------------
-- VMT colours are "[r g b]" in linear 0..1 and are allowed to exceed 1 for
-- HDR tints, which a 0..255 colour wheel cannot express. So the row offers a
-- swatch for picking the hue and a raw literal box for anything beyond that.
AdvMat.Rows.color = function( parent, ctx, param, index )
	local row = BuildRow( parent, ctx, param, index )

	-- The swatch is created BEFORE the text entry. Docking is resolved in the
	-- order children were added, and a FILL child takes the whole rect that is
	-- left at that moment without leaving room for anything docked to an edge
	-- afterwards - so a FILL added first ends up underneath its own siblings.
	local swatch = vgui.Create( "DButton", row.Body )
	swatch:Dock( LEFT )
	swatch:SetWide( RowH() + 12 )
	swatch:DockMargin( 0, 0, 6, 0 )
	swatch:SetText( "" )
	swatch:SetTooltip( "Pick a colour" )

	local raw = vgui.Create( "DTextEntry", row.Body )
	raw:Dock( FILL )
	raw:SetUpdateOnType( false )
	AdvMat.StyleEntry( raw )
	raw:SetTooltip( "VMT literal, for example [1 0.5 0.25]. Values above 1 are allowed for HDR tints." )

	local function CurrentVector()
		return AdvMat.StringToVector( ctx.Get( param.name ), Vector( 1, 1, 1 ) )
	end

	swatch.Paint = function( self, w, h )
		local v = CurrentVector()
		surface.SetDrawColor( 20, 20, 20 )
		surface.DrawRect( 0, 0, w, h )
		surface.SetDrawColor(
			math.Clamp( v.x, 0, 1 ) * 255,
			math.Clamp( v.y, 0, 1 ) * 255,
			math.Clamp( v.z, 0, 1 ) * 255 )
		surface.DrawRect( 1, 1, w - 2, h - 2 )
	end

	row.Sync = function()
		row.Setting = true
		raw:SetValue( tostring( ctx.Get( param.name ) or "" ) )
		row.Setting = false
	end

	raw.OnValueChange = function( _, val )
		if row.Setting then return end
		local v = AdvMat.StringToVector( val, Vector( 1, 1, 1 ) )
		ctx.Set( param.name, AdvMat.VectorToString( v ) )
		row:Sync()
	end

	swatch.DoClick = function()
		local menu = DermaMenu()
		AdvMat.I18N.Track( menu )

		-- DMenu:AddPanel returns nothing, so the panel has to be built first.
		local combo = vgui.Create( "DColorCombo" )
		combo:SetSize( 280, 220 )
		combo:SetColor( ColorAlpha( CurrentVector():ToColor(), 255 ) )
		combo.OnValueChanged = function( _, col )
			ctx.Set( param.name, AdvMat.VectorToString(
				Vector( col.r / 255, col.g / 255, col.b / 255 ) ) )
			row:Sync()
		end

		menu:AddPanel( combo )
		menu:Open()
	end

	row:Sync()
	return row
end

---------------------------------------------------------------------------
-- texture
---------------------------------------------------------------------------

local function Imported( path )
	return AdvMat.Import ~= nil and AdvMat.Import.IsSource( path )
end

--- The stored value of a parameter a recipe feeds. It only has to switch the
--- shader combo on until the image is attached, so it is the recipe's own
--- source when that is a mounted texture.
---
--- An imported image is a file in this client's data folder that nobody else
--- has. Every other player would see a missing texture while the finished
--- image travels, so the parameter keeps the texture it had instead.
local function Placeholder( ctx, param, recipe )
	local src = recipe.src
	if not Imported( src ) then return src or ctx.BaseTexture() or "color/white" end

	local current = ctx.Get( param.name )
	if isstring( current ) and current ~= "" and not Imported( current ) then return current end

	return ctx.BaseTexture() or "color/white"
end

-- Output file per recipe table, so painting a thumbnail does not hash a
-- recipe every frame. Weak keys: a replaced recipe drops out.
local previewTargets = setmetatable( {}, { __mode = "k" } )

--- The finished image of a recipe, once it exists. A row fed by a recipe shows
--- that rather than the placeholder underneath it - which for an imported
--- picture is the very texture it replaced.
local function GeneratedPreview( recipe )
	if not istable( recipe ) then return nil end

	local GEN = AdvMat.Gen
	local target = previewTargets[ recipe ]

	if target == nil then
		local clean = GEN.Sanitize( recipe )
		target = clean and GEN.FileName( clean ) or false
		previewTargets[ recipe ] = target
	end

	-- GEN.Cache holds false while an image is unavailable.
	return target and GEN.Cache[ target ] or nil
end

-- The buttons beside a texture path share what the path box leaves them. Each
-- asks for its own translated label's width; when a narrow inspector, a long
-- translation or a fourth button would push the box out of the row, they
-- shrink together - to the smaller font before a label is cut short - and the
-- box keeps a few characters of path. A fixed width per button pushed the box
-- off Make rows entirely once Import arrived.

--- Record an action button's preferred width and add it to `list`.
local function PreferWide( button, list )
	surface.SetFont( "AdvMatText" )
	button.AdvMatTextWide = surface.GetTextSize( button:GetText() )
	button.AdvMatPreferredWide = math.max( AdvMat.FontSize * 3, button.AdvMatTextWide + 16 )
	button:SetWide( button.AdvMatPreferredWide )
	list[ #list + 1 ] = button
end

--- Fit the buttons in `list` into a body `w` wide, `fixed` of which is taken
--- by controls that do not shrink.
local function FitActions( list, fixed, w )
	if not w or w <= 0 or #list == 0 then return end

	local want = 0
	for _, button in ipairs( list ) do want = want + button.AdvMatPreferredWide end

	local room  = w - fixed - 4 * #list - AdvMat.FontSize * 3.5
	local scale = want > room and math.max( 0.5, room / want ) or 1

	for _, button in ipairs( list ) do
		local wide = math.floor( button.AdvMatPreferredWide * scale )
		if button:GetWide() ~= wide then
			button:SetWide( wide )
			button:SetFont( wide < button.AdvMatTextWide + 8 and "AdvMatSmall" or "AdvMatText" )
		end
	end
end

AdvMat.Rows.texture = function( parent, ctx, param, index )
	-- Tall enough to judge a thumbnail by, but only once there is one to judge:
	-- a parameter with no texture would otherwise reserve two and a half rows
	-- for an empty black square.
	local tall  = AdvMat.TextureRowHeight()
	local short = RowH()

	local has = ( ctx.Get( param.name ) or "" ) ~= ""
	local row = BuildRow( parent, ctx, param, index, has and tall or short )

	local browse = vgui.Create( "DButton", row.Body )
	browse:Dock( RIGHT )
	browse:SetWide( RowH() + 8 )
	browse:DockMargin( 4, 0, 0, 0 )
	browse:SetText( "..." )
	browse:SetTooltip( "Browse for a texture" )
	AdvMat.StyleButton( browse )

	-- Make, Edit and Import, which share the room the path box leaves.
	local actions = {}

	-- A texture parameter can be pointed at a file, generated from another
	-- texture, or painted by hand. The last two both end up as recipes on the
	-- rule, so they share one code path from here on.
	if ctx.SetGen then
		--- Adopt a finished recipe. The stored parameter value is only a
		--- placeholder that switches the shader combo on; the real image is
		--- attached as a texture once it has been built.
		---
		--- The value has to be set BEFORE the recipe, because SetGen rebuilds
		--- the parameter list and this row goes with it.
		---
		--- Returns false when the editor this row belonged to has gone, which an
		--- import finishing long after its click needs to know.
		local function Adopt( recipe, info )
			if ctx.Set( param.name, Placeholder( ctx, param, recipe ) ) == false then return false end
			ctx.SetGen( param.name, recipe )

			if ctx.SetAutoParam then
				-- Erasing really does need $translucent, but it is a companion
				-- setting owned by this recipe rather than a user edit. Remember
				-- that ownership so deleting/undoing the alpha operation can put
				-- the material back without removing an original VMT flag.
				ctx.SetAutoParam( "$translucent", "1",
					info and info.translucent == true, recipe )
			elseif info and info.translucent and ctx.SetParams then
				-- A hole in a texture is invisible unless the material is
				-- allowed to be see-through, and a tool that silently does
				-- nothing is worse than one that refuses.
				ctx.SetParams( { [ "$translucent" ] = "1" } )
			end

			if info and info.set and ctx.SetParams then
				ctx.SetParams( info.set, info.unset )
			end

			return true
		end

		local function CurrentGen()
			return ctx.GetGen( param.name )
		end

		--- Where a generator starts reading. Generated maps travel as recipes
		--- that every client rebuilds, and no other client has an imported
		--- file, so a map is never generated from one: it starts from the
		--- material's own texture instead.
		local function GeneratorSource( cur )
			local src = cur and cur.src
			if Imported( src ) then src = nil end
			return src or ctx.BaseTexture()
		end

		--- Which generators make sense for this parameter.
		local makers = {}

		if AdvMat.Gen.NORMAL_TARGETS[ param.name ] then
			makers[ #makers + 1 ] = { name = "Normal map from a texture...", fn = function()
				local cur = CurrentGen()
				AdvMat.OpenNormalGenerator(
					GeneratorSource( cur ),
					( cur and select( 2, AdvMat.Gen.KindOf( cur ) ) == "normal" ) and cur or nil,
					Adopt,
					ctx.Target and ctx.Target() or nil )
			end }
		end

		if AdvMat.Gen.PHONG_TARGETS[ param.name ] then
			makers[ #makers + 1 ] = { name = "Phong exponent map from the colours...", fn = function()
				local cur = CurrentGen()
				AdvMat.OpenSurfaceGenerator( "phongexp",
					GeneratorSource( cur ),
					( cur and select( 2, AdvMat.Gen.KindOf( cur ) ) == "phongexp" ) and cur or nil,
					ctx.Target and ctx.Target() or {},
					function( recipe, extras )
						Adopt( recipe, extras and { set = extras.set, unset = extras.unset } )
					end )
			end }
		end

		if AdvMat.Gen.ENVMASK_TARGETS[ param.name ] then
			makers[ #makers + 1 ] = { name = "Reflection mask from the colours...", fn = function()
				local cur = CurrentGen()
				AdvMat.OpenSurfaceGenerator( "envmapmask",
					GeneratorSource( cur ),
					( cur and select( 2, AdvMat.Gen.KindOf( cur ) ) == "envmapmask" ) and cur or nil,
					ctx.Target and ctx.Target() or {},
					function( recipe, extras )
						Adopt( recipe, extras and { set = extras.set, unset = extras.unset } )
					end )
			end }
		end

		if #makers > 0 then
			local make = vgui.Create( "DButton", row.Body )
			make:Dock( RIGHT )
			make:DockMargin( 4, 0, 0, 0 )
			make:SetText( "Make" )
			make:SetTooltip( "Build this map automatically from another texture" )
			AdvMat.StyleButton( make )
			PreferWide( make, actions )

			make.DoClick = function()
				if #makers == 1 then makers[ 1 ].fn() return end

				local menu = DermaMenu()
				AdvMat.I18N.Track( menu )
				for _, entry in ipairs( makers ) do
					menu:AddOption( entry.name, entry.fn )
				end
				menu:Open()
			end
		end

		local edit = vgui.Create( "DButton", row.Body )
		edit:Dock( RIGHT )
		edit:DockMargin( 4, 0, 0, 0 )
		edit:SetText( "Edit" )
		edit:SetTooltip( "Paint on this texture, recolour part of it, or cut a hole in it" )
		AdvMat.StyleButton( edit )
		PreferWide( edit, actions )

		edit.DoClick = function()
			local cur  = CurrentGen()
			local kind = cur and select( 2, AdvMat.Gen.KindOf( cur ) )

			local target = ctx.Target and ctx.Target() or {}
			target.src = ctx.Get( param.name )

			AdvMat.OpenTextureEditor( param.name,
				( kind == "edit" ) and cur or nil,
				target,
				Adopt )
		end

		-- Beside Edit, because an imported picture is an edit: an image with no
		-- steps yet, which Edit then reopens like any other. Offered only where
		-- Model Hotloader can actually read files; otherwise the top of the
		-- parameter list says why not, once, instead of every row saying it.
		if AdvMat.Import and AdvMat.Import.Ready() then
			local import = vgui.Create( "DButton", row.Body )
			import:Dock( RIGHT )
			import:DockMargin( 4, 0, 0, 0 )
			import:SetText( AdvMat.L( "row.import" ) )
			import:SetTooltip( AdvMat.L( "row.import_tip" ) )
			AdvMat.StyleButton( import )
			PreferWide( import, actions )

			import.DoClick = function()
				-- A $translucent the current recipe installed (an erase cut holes)
				-- stays only when the imported image's alpha takes over its job.
				-- Otherwise it goes with the recipe it belonged to, and the import
				-- was already told the material would be opaque.
				local cur = CurrentGen()
				local owned = istable( cur ) and cur.autotranslucent == true

				AdvMat.Import.Pick( param.name, ctx.Target and ctx.Target() or {},
					function( recipe, info )
						return Adopt( recipe, {
							translucent = owned and istable( info ) and info.transparent == true,
						} )
					end )
			end
		end
	end

	-- Full row height, so the thumbnail is actually big enough to judge a
	-- texture by. It lives on the row rather than in the body because the body
	-- is inset to keep the controls one row high.
	local preview = row.Lead
	preview:SetVisible( has )
	preview:SetWide( has and ( tall - 8 ) or 0 )
	preview:DockMargin( 6, 4, 0, 4 )

	local entry = vgui.Create( "DTextEntry", row.Body )
	entry:Dock( FILL )
	entry:SetUpdateOnType( false )
	entry:SetPlaceholderText( "models/folder/texture  (no materials/ prefix, no extension)" )
	AdvMat.StyleEntry( entry )

	row.Body.PerformLayout = function( _, w )
		FitActions( actions, browse:GetWide() + 4, w )
	end

	preview.Paint = function( self, w, h )
		surface.SetDrawColor( 25, 25, 28 )
		surface.DrawRect( 0, 0, w, h )

		local path = ctx.Get( param.name )
		if not path or path == "" then return end

		local mat = ( ctx.GetGen and GeneratedPreview( ctx.GetGen( param.name ) ) )
			or AdvMat.PreviewMaterial( path )
		if not mat then return end

		surface.SetDrawColor( 255, 255, 255 )
		surface.SetMaterial( mat )
		surface.DrawTexturedRect( 1, 1, w - 2, h - 2 )
	end

	row.Sync = function()
		row.Setting = true
		entry:SetValue( tostring( ctx.Get( param.name ) or "" ) )
		row.Setting = false

		-- Grow when a texture appears, collapse when it goes away.
		local now = ( ctx.Get( param.name ) or "" ) ~= ""

		preview:SetVisible( now )
		preview:SetWide( now and ( tall - 8 ) or 0 )

		if row:Resize( now and tall or short ) then
			AdvMat.SizeRows( parent )
		end
	end

	entry.OnValueChange = function( _, val )
		if row.Setting then return end
		local p = AdvMat.NormalizeMaterial( val )
		ctx.Set( param.name, p ~= "" and p or nil )
		row:Sync()
	end

	browse.DoClick = function()
		local target = ctx.Target and ctx.Target() or nil
		AdvMat.OpenTexturePicker( ctx.Get( param.name ), function( path )
			ctx.Set( param.name, ( path ~= "" ) and path or nil )
			row:Sync()
		end, ctx.BaseTexture and ctx.BaseTexture() or nil,
			target and target.host or nil )
	end

	row:Sync()
	return row
end

---------------------------------------------------------------------------
-- free text ( string / matrix / anything unrecognised )
---------------------------------------------------------------------------
AdvMat.Rows.string = function( parent, ctx, param, index )
	local row = BuildRow( parent, ctx, param, index )

	local entry = vgui.Create( "DTextEntry", row.Body )
	entry:Dock( FILL )
	entry:SetUpdateOnType( false )
	AdvMat.StyleEntry( entry )
	if param.default and param.default ~= "" then
		entry:SetPlaceholderText( param.default )
	end

	row.Sync = function()
		row.Setting = true
		entry:SetValue( tostring( ctx.Get( param.name ) or "" ) )
		row.Setting = false
	end

	entry.OnValueChange = function( _, val )
		if row.Setting then return end
		val = string.Trim( val )
		ctx.Set( param.name, val ~= "" and val or nil )
	end

	row:Sync()
	return row
end

AdvMat.Rows.matrix = AdvMat.Rows.string

---------------------------------------------------------------------------
-- texture transform
---------------------------------------------------------------------------
-- A transform is a line of text: "center .5 .5 scale 1 1 rotate 0 translate
-- 0 0". Nudging a texture by editing that by hand is miserable, so the row
-- shows a summary and opens a panel of sliders underneath itself.

local TRANSFORM_FIELDS = {
	{ key = "sx",  text = "Scale X",  min = 0.01, max = 16,  dec = 3,
	  tip = "Above 1 repeats the texture more times and makes it smaller. Below 1 zooms in." },
	{ key = "sy",  text = "Scale Y",  min = 0.01, max = 16,  dec = 3,
	  tip = "The same, down the surface instead of across it." },
	{ key = "rot", text = "Rotate",   min = 0,    max = 360, dec = 1,
	  tip = "Degrees, turning around the pivot below." },
	{ key = "tx",  text = "Slide X",  min = -2,   max = 2,   dec = 3,
	  tip = "Slides the texture sideways. 1 is one whole tile." },
	{ key = "ty",  text = "Slide Y",  min = -2,   max = 2,   dec = 3,
	  tip = "Slides the texture up and down. 1 is one whole tile." },
	{ key = "cx",  text = "Pivot X",  min = 0,    max = 1,   dec = 3,
	  tip = "The point scale and rotate work around. 0.5 is the middle, and is almost always right." },
	{ key = "cy",  text = "Pivot Y",  min = 0,    max = 1,   dec = 3,
	  tip = "The other half of the pivot." },
}

AdvMat.Rows.transform = function( parent, ctx, param, index )
	local row  = BuildRow( parent, ctx, param, index )
	local rowH = RowH()

	-- Docked before the summary: a FILL child claims everything left at the
	-- moment it is laid out, so the label would otherwise run underneath this
	-- button rather than stopping short of it.
	local toggle = vgui.Create( "DButton", row.Body )
	toggle:Dock( RIGHT )
	toggle:SetWide( AdvMat.FontSize * 5 )
	toggle:SetText( "Adjust" )
	AdvMat.StyleButton( toggle )

	local summary = vgui.Create( "DLabel", row.Body )
	summary:Dock( FILL )
	AdvMat.StyleLabel( summary, "AdvMatSmall", T.TextDim )

	-- The sliders live in their own panel, added straight after this row so it
	-- reads as a section belonging to it.
	local box = vgui.Create( "DPanel", parent )
	box:Dock( TOP )
	box:DockMargin( 0, 0, 0, 1 )
	box:DockPadding( AdvMat.FontSize, 4, 4, 4 )
	box:SetTall( rowH * ( #TRANSFORM_FIELDS + 1 ) + 8 )
	box:SetVisible( false )
	box.Paint = AdvMat.Fill( T.RowAlt )

	local function Current()
		return AdvMat.ParseTransform( ctx.Get( param.name ) )
	end

	local function UpdateSummary()
		summary:SetText( AdvMat.TransformSummary( Current() ) )
	end

	local sliders = {}

	for _, field in ipairs( TRANSFORM_FIELDS ) do
		local line = vgui.Create( "DPanel", box )
		line:Dock( TOP )
		line:SetTall( rowH )
		line.Paint = AdvMat.NoPaint

		local lbl = vgui.Create( "DLabel", line )
		lbl:Dock( LEFT )
		lbl:SetWide( AdvMat.FontSize * 5 )
		lbl:SetText( field.text )
		AdvMat.StyleLabel( lbl, "AdvMatText", T.Text )

		local slider = vgui.Create( "DNumSlider", line )
		slider:Dock( FILL )
		slider:SetText( "" )
		slider:SetMin( field.min )
		slider:SetMax( field.max )
		slider:SetDecimals( field.dec )
		slider:SetTooltip( field.tip )
		AdvMat.StyleSlider( slider )

		slider.OnValueChanged = function( _, v )
			if row.Setting then return end

			local t = Current()
			t[ field.key ] = math.Round( v, field.dec )

			ctx.Set( param.name, AdvMat.TransformToString( t ) )
			UpdateSummary()
		end

		sliders[ field.key ] = slider
	end

	local reset = vgui.Create( "DButton", box )
	reset:Dock( TOP )
	reset:SetTall( rowH )
	reset:DockMargin( 0, 4, 0, 0 )
	reset:SetText( "Reset to no transform" )
	AdvMat.StyleButton( reset )

	reset.DoClick = function()
		ctx.Set( param.name, AdvMat.TransformToString( AdvMat.TRANSFORM_DEFAULT ) )
		row:Sync()
	end

	row.Sync = function()
		local t = Current()

		row.Setting = true
		for key, slider in pairs( sliders ) do slider:SetValue( t[ key ] ) end
		row.Setting = false

		UpdateSummary()
	end

	toggle.DoClick = function()
		box:SetVisible( not box:IsVisible() )
		toggle:SetText( box:IsVisible() and "Hide" or "Adjust" )

		if box:IsVisible() then row:Sync() end
		AdvMat.SizeRows( parent )
	end

	row:Sync()
	return row
end

---------------------------------------------------------------------------
-- Generated texture info line
---------------------------------------------------------------------------

--- Sits under a parameter fed by a generator or by the texture editor and
--- spells out what it was made from, so a generated map is never a mystery
--- value.
function AdvMat.CreateGenInfoRow( parent, ctx, param, recipe )
	local kindDef, kind = AdvMat.Gen.KindOf( recipe )

	local row = vgui.Create( "DPanel", parent )
	row:Dock( TOP )
	row:SetTall( RowH() )
	row:DockMargin( 0, 0, 0, 1 )

	row.Paint = function( _, w, h )
		surface.SetDrawColor( T.RowSet.r, T.RowSet.g, T.RowSet.b, 255 )
		surface.DrawRect( 0, 0, w, h )
		surface.SetDrawColor( T.Accent.r, T.Accent.g, T.Accent.b, 255 )
		surface.DrawRect( 0, 0, 3, h )
	end

	local drop = vgui.Create( "DButton", row )
	drop:Dock( RIGHT )
	drop:SetWide( AdvMat.FontSize * 4 )
	drop:DockMargin( 4, 2, 4, 2 )
	drop:SetText( "Drop" )
	drop:SetTooltip( "Throw the recipe away and go back to a plain texture path" )
	AdvMat.StyleButton( drop, true )

	local edit = vgui.Create( "DButton", row )
	edit:Dock( RIGHT )
	edit:SetWide( AdvMat.FontSize * 4 )
	edit:DockMargin( 4, 2, 0, 2 )
	edit:SetText( "Edit" )
	edit:SetTooltip( "Reopen the window that made this, on the same settings" )
	AdvMat.StyleButton( edit )

	-- An imported image's path is a content hash. The name of the file it came
	-- from says more, where this computer still knows it.
	local source = recipe.src or AdvMat.L( "common.blank_image" )
	if Imported( recipe.src ) then source = AdvMat.Import.Describe( recipe.src ) end

	local label = vgui.Create( "DLabel", row )
	label:Dock( FILL )
	label:DockMargin( 10, 0, 0, 0 )
	label:SetText( AdvMat.L( "row.generated_from", {
		kind = kindDef and AdvMat.LText( kindDef.name ) or AdvMat.L( "common.generated" ),
		source = source,
		summary = AdvMat.Gen.Describe( recipe ),
	} ) )
	label:SetTooltip( AdvMat.L( "row.written_data", {
		path = AdvMat.Gen.FileName( recipe ),
	} ) )
	AdvMat.StyleLabel( label, "AdvMatSmall", T.Text )

	--- Reopening has to land in the window that made it, not always in the
	--- normal map generator.
	edit.DoClick = function()
		-- Same ordering rule as the Make button: the value goes on first,
		-- because SetGen rebuilds the parameter list and this row with it.
		local function Adopt( updated, info )
			ctx.Set( param.name, Placeholder( ctx, param, updated ) )
			ctx.SetGen( param.name, updated )

			if ctx.SetAutoParam then
				ctx.SetAutoParam( "$translucent", "1",
					info and info.translucent == true, updated )
			elseif info and info.translucent and ctx.SetParams then
				ctx.SetParams( { [ "$translucent" ] = "1" } )
			end
		end

		local target = ctx.Target and ctx.Target() or {}

		if kind == "edit" then
			target.src = recipe.src
			AdvMat.OpenTextureEditor( param.name, recipe, target, Adopt )

		elseif kind == "phongexp" or kind == "envmapmask" then
			AdvMat.OpenSurfaceGenerator( kind, recipe.src, recipe, target,
				function( updated, extras )
					Adopt( updated )
					if extras and ctx.SetParams then ctx.SetParams( extras.set, extras.unset ) end
				end )

		else
			AdvMat.OpenNormalGenerator( recipe.src, recipe, Adopt, target )
		end
	end

	drop.DoClick = function()
		if ctx.SetAutoParam then
			ctx.SetAutoParam( "$translucent", "1", false, recipe )
		end
		ctx.SetGen( param.name, nil )
	end

	return row
end

---------------------------------------------------------------------------
-- Factory
---------------------------------------------------------------------------
--- `index` only decides the row's stripe colour.
function AdvMat.CreateParamRow( parent, ctx, param, index )
	local maker = AdvMat.Rows[ param.type ] or AdvMat.Rows.string
	return maker( parent, ctx, param, index )
end
