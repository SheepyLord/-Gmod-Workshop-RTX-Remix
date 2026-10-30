--[[---------------------------------------------------------------------------
	Advanced Material Editor - theme

	The editor paints its own backgrounds and sets its own text colours rather
	than inheriting the Derma skin. Two reasons: the default skin's greys sit
	very close to each other, so a "this parameter is unset" label was
	effectively invisible against the panel behind it; and a user running a
	custom skin would otherwise get unpredictable contrast.

	Fonts are sized from the screen height and rebuilt when the resolution
	changes, so the panel is legible at 1080p and at 4K without the text either
	vanishing or overflowing its row.
-----------------------------------------------------------------------------]]

AdvMat = AdvMat or {}

---------------------------------------------------------------------------
-- Palette
---------------------------------------------------------------------------
AdvMat.Theme = {
	Bg        = Color(  38,  40,  45 ),  -- window background
	Panel     = Color(  46,  48,  54 ),  -- sunken areas: lists, scroll bodies
	Header    = Color(  60,  64,  74 ),  -- category headers
	HeaderHot = Color(  74,  79,  91 ),

	Row       = Color(  52,  55,  62 ),  -- parameter row, odd
	RowAlt    = Color(  47,  50,  56 ),  -- parameter row, even
	RowSet    = Color(  40,  62,  90 ),  -- row carrying an override
	RowHover  = Color(  66,  70,  80 ),

	Accent    = Color( 104, 176, 255 ),  -- overridden
	Text      = Color( 228, 231, 237 ),  -- normal text
	TextDim   = Color( 176, 181, 190 ),  -- value inherited from the .vmt
	TextFaint = Color( 132, 137, 148 ),  -- unset, showing the shader default
	Warn      = Color( 246, 198, 100 ),
	Danger    = Color( 228, 112, 112 ),

	Line      = Color(  28,  30,  34 ),
	Selected  = Color(  58, 108, 168 ),
}

---------------------------------------------------------------------------
-- Fonts
---------------------------------------------------------------------------
AdvMat.FontSize = 16

function AdvMat.BuildFonts()
	-- 1080p -> 16, 1440p -> 22, 2160p -> 30
	local size = math.Clamp( math.floor( ScrH() / 67 ), 14, 30 )
	AdvMat.FontSize = size

	local function make( name, px, weight )
		surface.CreateFont( name, {
			font     = "Roboto",
			size     = px,
			weight   = weight,
			extended = true,
			antialias = true,
		} )
	end

	make( "AdvMatText",  size,                          400 )
	make( "AdvMatBold",  size,                          700 )
	make( "AdvMatSmall", math.max( 12, size - 2 ),      400 )
	make( "AdvMatTitle", size + 4,                      600 )
end

AdvMat.BuildFonts()

--- Height of one parameter row, and the width of its name column.
function AdvMat.RowHeight()  return AdvMat.FontSize + 12 end
function AdvMat.LabelWidth() return math.floor( AdvMat.FontSize * 12.5 ) end

--- Rows carrying a texture are taller, because the thumbnail is the whole
--- point of showing one and at a normal row height it is a postage stamp.
function AdvMat.TextureRowHeight() return math.floor( AdvMat.RowHeight() * 2.4 ) end

hook.Add( "OnScreenSizeChanged", "AdvMat.Fonts", function( oldWidth, oldHeight )
	AdvMat.BuildFonts()
	-- Scale remembered pixel geometry with the display before clamping it. This
	-- preserves the user's layout and keeps high-DPI fonts from outgrowing a
	-- window that happened to be saved on a smaller monitor.
	if AdvMat.WindowUX and AdvMat.WindowUX.HandleScreenSizeChanged then
		AdvMat.WindowUX.HandleScreenSizeChanged( oldWidth, oldHeight )
	elseif IsValid( AdvMat.Editor ) and AdvMat.Editor.ApplyWindowSize then
		AdvMat.Editor:ApplyWindowSize( false )
	end
	local textureEditor = AdvMat.TexEditor
	if IsValid( textureEditor ) and isfunction( textureEditor.ApplyUIScale ) then
		textureEditor:ApplyUIScale()
	end
end )

---------------------------------------------------------------------------
-- Text measuring
---------------------------------------------------------------------------

--- Break `text` into lines that fit `maxWidth` when drawn in `font`.
---
--- DLabel can wrap on its own, but only settles its height during a layout
--- pass, which makes it useless for sizing a panel that has to be positioned
--- immediately. Measuring here means the caller knows the exact height up
--- front.
---
--- A blank line in the input stays a blank line in the output, so paragraph
--- breaks survive. A single ASCII word longer than the limit gets its own
--- line rather than being cut in half. Chinese and Japanese do not normally
--- put spaces between words, so oversized multibyte runs gain safe break
--- opportunities between UTF-8 characters; contiguous ASCII inside them
--- stays atomic so VMT names and numbers are not split.
local function HasMultibyte( text )
	for i = 1, #text do
		if string.byte( text, i ) >= 128 then return true end
	end
	return false
end

local function Utf8BreakUnits( text )
	local units = {}
	local ascii = ""

	local function FlushAscii()
		if ascii == "" then return end
		units[ #units + 1 ] = ascii
		ascii = ""
	end

	local i = 1
	while i <= #text do
		local lead = string.byte( text, i )
		if lead < 128 then
			ascii = ascii .. string.sub( text, i, i )
			i = i + 1
		else
			FlushAscii()
			local size = lead < 224 and 2 or ( lead < 240 and 3 or ( lead < 248 and 4 or 1 ) )
			units[ #units + 1 ] = string.sub( text, i, i + size - 1 )
			i = i + size
		end
	end

	FlushAscii()
	return units
end

local function SplitWideMultibyteRun( text, maxWidth )
	local chunks = {}
	local line = ""

	for _, unit in ipairs( Utf8BreakUnits( text ) ) do
		local try = line .. unit
		if line ~= "" and surface.GetTextSize( try ) > maxWidth then
			chunks[ #chunks + 1 ] = line
			line = unit
		else
			line = try
		end
	end

	if line ~= "" then chunks[ #chunks + 1 ] = line end
	return chunks
end

function AdvMat.WrapText( text, font, maxWidth )
	local lines = {}
	if not isstring( text ) or text == "" then return lines end

	surface.SetFont( font )

	for _, paragraph in ipairs( string.Explode( "\n", text ) ) do
		if paragraph == "" then
			lines[ #lines + 1 ] = ""
		else
			local line = ""

			for _, word in ipairs( string.Explode( " ", paragraph ) ) do
				local try = ( line == "" ) and word or ( line .. " " .. word )

				if line ~= "" and surface.GetTextSize( try ) > maxWidth then
					lines[ #lines + 1 ] = line
					line = ""
				end

				if line == "" and surface.GetTextSize( word ) > maxWidth
				and HasMultibyte( word ) then
					local chunks = SplitWideMultibyteRun( word, maxWidth )
					for i = 1, #chunks - 1 do lines[ #lines + 1 ] = chunks[ i ] end
					line = chunks[ #chunks ] or ""
				elseif line == "" then
					line = word
				else
					line = try
				end
			end

			if line ~= "" then lines[ #lines + 1 ] = line end
		end
	end

	return lines
end

---------------------------------------------------------------------------
-- Paint helpers
---------------------------------------------------------------------------
local T = AdvMat.Theme

--- Flat fill, for panels that only exist to hold a background colour.
function AdvMat.Fill( col )
	return function( _, w, h )
		surface.SetDrawColor( col.r, col.g, col.b, col.a )
		surface.DrawRect( 0, 0, w, h )
	end
end

--- Transparent, for the many layout-only containers.
function AdvMat.NoPaint() end

--- Give a DFrame the editor's own background instead of the skin's.
function AdvMat.StyleFrame( frame )
	if AdvMat.I18N then AdvMat.I18N.Track( frame ) end

	-- DFrame can already be moved by its 24 px title bar and, when sizable,
	-- resized from its lower-right 20 px.  The stock skin normally hints at
	-- those hit targets; our flat skin used to erase every visual clue.  Keep
	-- the native behaviour and make both targets visible again.
	if frame.SetDraggable then frame:SetDraggable( true ) end
	if frame.SetScreenLock then frame:SetScreenLock( true ) end

	frame.Paint = function( pnl, w, h )
		surface.SetDrawColor( T.Bg.r, T.Bg.g, T.Bg.b, 255 )
		surface.DrawRect( 0, 0, w, h )

		surface.SetDrawColor( T.Header.r, T.Header.g, T.Header.b, 255 )
		surface.DrawRect( 0, 0, w, 24 )

		surface.SetDrawColor( T.Line.r, T.Line.g, T.Line.b, 255 )
		surface.DrawOutlinedRect( 0, 0, w, h, 1 )

	end

	if frame.lblTitle then
		frame.lblTitle:SetFont( "AdvMatBold" )
		frame.lblTitle:SetTextColor( T.Text )
		frame.lblTitle:SetTooltip( AdvMat.L and AdvMat.L( "window.drag_tip" )
			or "Drag the title bar to move this window." )
	end

	-- Disabled caption controls look actionable in the stock skin.  This editor
	-- has no taskbar to restore a minimised window from, and resizing is handled
	-- directly at the corner, so show only the close control.
	if IsValid( frame.btnMinim ) and not frame.btnMinim:IsEnabled() then
		frame.btnMinim:SetVisible( false )
	end
	if IsValid( frame.btnMaxim ) and not frame.btnMaxim:IsEnabled() then
		frame.btnMaxim:SetVisible( false )
	end

	-- cl_31 adds the actual move/resize overlay and centralises focus/input for
	-- every top-level AdvMat window which uses this shared frame style.
	if AdvMat.WindowUX then AdvMat.WindowUX.SetupFrame( frame ) end
end

--- DListView rows default to the skin's small font and dark-on-light colours,
--- which clashes badly with the rest of the window.
function AdvMat.StyleListView( list )
	list:SetDataHeight( AdvMat.RowHeight() )
	list.Paint = AdvMat.Fill( T.Panel )

	if list.Columns then
		for _, col in ipairs( list.Columns ) do
			if IsValid( col ) and col.Header then
				col.Header:SetFont( "AdvMatBold" )
				col.Header:SetTextColor( T.Text )
				col.Header.Paint = AdvMat.Fill( T.Header )
			end
		end
	end
end

--- Call after DListView:AddLine so the new line matches.
function AdvMat.StyleListLine( line, index )
	line.Paint = function( pnl, w, h )
		local col = ( index % 2 == 0 ) and T.RowAlt or T.Row
		if pnl:IsLineSelected() then
			col = T.Selected
		elseif pnl:IsHovered() then
			col = T.RowHover
		end

		surface.SetDrawColor( col.r, col.g, col.b, 255 )
		surface.DrawRect( 0, 0, w, h )
	end

	for _, cell in ipairs( line.Columns or {} ) do
		if IsValid( cell ) then
			cell:SetFont( "AdvMatText" )
			cell:SetTextColor( T.Text )
		end
	end
end

--- DNumSlider's own label and value box also come from the skin.
function AdvMat.StyleSlider( slider )
	if IsValid( slider.Label ) then
		if AdvMat.I18N then AdvMat.I18N.LocalizePanel( slider.Label ) end
		slider.Label:SetFont( "AdvMatText" )
		slider.Label:SetTextColor( T.Text )
	end

	if IsValid( slider.TextArea ) then
		slider.TextArea:SetFont( "AdvMatText" )
		slider.TextArea:SetTextColor( T.Text )
	end
end

--- DTextEntry, so typed values are readable on the dark background.
function AdvMat.StyleEntry( entry )
	entry:SetFont( "AdvMatText" )
	entry:SetTextColor( T.Text )

	-- Not every Derma version exposes these on every entry subclass.
	if entry.SetCursorColor    then entry:SetCursorColor( T.Text ) end
	if entry.SetHighlightColor then entry:SetHighlightColor( T.Selected ) end

	entry.Paint = function( pnl, w, h )
		surface.SetDrawColor( 30, 32, 36, 255 )
		surface.DrawRect( 0, 0, w, h )

		surface.SetDrawColor( T.Line.r, T.Line.g, T.Line.b, 255 )
		surface.DrawOutlinedRect( 0, 0, w, h, 1 )

		-- DTextEntry draws its own placeholder from inside the skin's Paint,
		-- which this replaces. Without redrawing it here the hint never shows,
		-- which is why the search box looked like an unlabelled empty field.
		if pnl:GetText() == "" and not pnl:IsEditing() then
			local hint = pnl.GetPlaceholderText and pnl:GetPlaceholderText()

			if isstring( hint ) and hint ~= "" then
				if string.sub( hint, 1, 1 ) == "#" then
					hint = language.GetPhrase( string.sub( hint, 2 ) )
				end

				draw.SimpleText( hint, "AdvMatText", 5, h * 0.5, T.TextFaint,
					TEXT_ALIGN_LEFT, TEXT_ALIGN_CENTER )
			end
		end

		pnl:DrawTextEntryText( T.Text, T.Selected, T.Text )
	end
end

--- DCheckBoxLabel sized to the text it actually carries.
---
--- Guessing a width in characters clipped "Live preview" to "Live p" and
--- "Show every supported parameter" to "Show every su" once the font scaled up
--- with the screen. Measuring cannot get that wrong.
function AdvMat.StyleCheck( box, text )
	box.AdvMatI18NSourceText = text
	box.AdvMatI18NAutoWidth = true
	text = AdvMat.LText and AdvMat.LText( text ) or text
	box.AdvMatI18NLastText = text
	box:SetText( text )
	box:SetFont( "AdvMatText" )
	box:SetTextColor( T.Text )

	surface.SetFont( "AdvMatText" )
	local textWidth = surface.GetTextSize( text )

	-- DCheckBoxLabel squares its tick box off against its own height and then
	-- insets the text past it, so the row height is part of the width.
	box:SetWide( AdvMat.RowHeight() + textWidth + 20 )
end

--- Flat button in the editor's palette.
function AdvMat.StyleButton( btn, danger )
	if AdvMat.I18N then AdvMat.I18N.LocalizePanel( btn ) end
	btn:SetFont( "AdvMatText" )

	btn.Paint = function( pnl, w, h )
		local base = danger and T.Danger or T.Header
		local col  = pnl:IsDown() and T.Selected
			or ( pnl:IsHovered() and T.HeaderHot or base )

		surface.SetDrawColor( col.r, col.g, col.b, 255 )
		surface.DrawRect( 0, 0, w, h )

		surface.SetDrawColor( T.Line.r, T.Line.g, T.Line.b, 255 )
		surface.DrawOutlinedRect( 0, 0, w, h, 1 )
	end

	btn:SetTextColor( T.Text )
end

--- DCollapsibleCategory header.
function AdvMat.StyleCategory( cat )
	if AdvMat.I18N then AdvMat.I18N.LocalizePanel( cat ) end
	local head = cat.Header
	if not IsValid( head ) then return end

	if head.SetFont then head:SetFont( "AdvMatBold" ) end
	if head.SetTextColor then head:SetTextColor( T.Text ) end

	-- PerformLayout re-applies the category's own header height, so set it
	-- there when the accessor exists rather than on the header panel.
	if cat.SetHeaderHeight then
		cat:SetHeaderHeight( AdvMat.RowHeight() + 4 )
	else
		head:SetTall( AdvMat.RowHeight() + 4 )
	end
	head.Paint = function( pnl, w, h )
		local col = pnl:IsHovered() and T.HeaderHot or T.Header
		surface.SetDrawColor( col.r, col.g, col.b, 255 )
		surface.DrawRect( 0, 0, w, h )

		surface.SetDrawColor( T.Accent.r, T.Accent.g, T.Accent.b, 255 )
		surface.DrawRect( 0, 0, 3, h )
	end

	cat.Paint = AdvMat.NoPaint
end

--- DComboBox.
function AdvMat.StyleCombo( combo )
	if AdvMat.I18N then AdvMat.I18N.LocalizePanel( combo ) end
	combo:SetFont( "AdvMatText" )
	combo:SetTextColor( T.Text )

	combo.Paint = function( pnl, w, h )
		local col = pnl:IsHovered() and T.HeaderHot or T.Header
		surface.SetDrawColor( col.r, col.g, col.b, 255 )
		surface.DrawRect( 0, 0, w, h )

		surface.SetDrawColor( T.Line.r, T.Line.g, T.Line.b, 255 )
		surface.DrawOutlinedRect( 0, 0, w, h, 1 )
	end
end

--- DLabel used as a plain caption.
function AdvMat.StyleLabel( label, font, col )
	if AdvMat.I18N then AdvMat.I18N.LocalizePanel( label ) end
	label:SetFont( font or "AdvMatText" )
	label:SetTextColor( col or T.Text )
end
