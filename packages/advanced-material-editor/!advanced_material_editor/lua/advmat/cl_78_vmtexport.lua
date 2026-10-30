--[[---------------------------------------------------------------------------
	Advanced Material Editor - .vmt export

	Turns whatever is on screen into the text of a real .vmt file, so an edit
	made in game can be shipped with a model instead of living in one player's
	override database.

	The interesting part is not the text. It is that a generated or hand edited
	texture cannot be referenced from a .vmt at all: it is a .png in the client's
	data folder, and the material system only loads .vtf files from materials/.
	So the window also writes the images out, works out what each one should be
	called, says which VTF format each needs and why, and puts the whole thing
	in a readme next to them.

	Emission rules, all of which have a reason:

	  every value is quoted        always legal, and removes the whole question
	                               of which values contain spaces

	  parameters are lowercase     gmad silently lowercases every filename when
	                               it packs an addon, so a material referenced
	                               with capitals works locally and breaks for
	                               everyone who installs it from the Workshop

	  paths use forward slashes    and carry no extension

	  vectors keep square brackets [1 1 1] is used as written, while
	                               {255 255 255} is divided by 255. Emitting one
	                               where the other was meant is a 255x difference
-----------------------------------------------------------------------------]]

AdvMat = AdvMat or {}

local T   = AdvMat.Theme
local GEN = AdvMat.Gen

local EXPORT_DIR = "advmat/export"

---------------------------------------------------------------------------
-- What a generated texture should be called and what it should be saved as
---------------------------------------------------------------------------
local SUFFIX = {
	[ "$basetexture" ]          = "",
	[ "$bumpmap" ]              = "_normal",
	[ "$normalmap" ]            = "_normal",
	[ "$phongexponenttexture" ] = "_exponent",
	[ "$envmapmask" ]           = "_envmask",
	[ "$selfillummask" ]        = "_selfillum",
	[ "$detail" ]               = "_detail",
}

--- The material path a generated image should be given when it is shipped.
local function SuggestPath( matpath, param )
	local base = AdvMat.NormalizeMaterial( matpath or "" )
	if base == "" then base = "models/mymodel/mytexture" end

	local suffix = SUFFIX[ param ]

	if not suffix then
		suffix = "_" .. string.gsub( param, "^%$", "" )
	end

	return base .. "_advmat" .. suffix
end

--- Which VTF format the image wants, and why. Getting this wrong is the most
--- common way a hand converted texture comes out looking broken.
local function FormatAdvice( param, recipe )
	local kind = select( 2, GEN.KindOf( recipe ) )

	if kind == "normal" then
		if recipe.alphamask then
			return "BGRA8888", "Normal Map",
				"It carries a mask in its alpha channel, so it needs a format with " ..
				"alpha. BGR888 would silently throw the mask away."
		end

		return "BGR888", "Normal Map",
			"Normal maps must not be DXT compressed: the 5:6:5 colour endpoints " ..
			"cannot represent a flat normal and the surface comes out banded."
	end

	if kind == "phongexp" then
		return "BGRA8888", nil,
			"The red and green channels mean completely different things here, and " ..
			"DXT compresses colour in 4x4 blocks, so the two would bleed into each " ..
			"other. Alpha carries the rim mask."
	end

	if kind == "envmapmask" then
		return "BGR888", nil, "A greyscale mask with no alpha."
	end

	-- A hand edited texture, or anything else.
	if AdvMat.Ops.MakesTransparency( recipe ) then
		return "DXT5", nil,
			"It has see-through areas, so it needs an alpha channel. Use BGRA8888 " ..
			"instead if the edges look blocky."
	end

	return "DXT1", nil, "No transparency, so the smaller format is fine."
end

---------------------------------------------------------------------------
-- Building the text
---------------------------------------------------------------------------

--- Sorted parameter names, with the ones people look for first at the top.
local ORDER = {
	"$basetexture", "$bumpmap", "$normalmap", "$detail", "$selfillummask",
	"$phong", "$phongexponenttexture", "$phongexponent", "$phongboost",
	"$phongfresnelranges", "$phongalbedotint", "$phongtint",
	"$envmap", "$envmapmask", "$envmaptint", "$envmapcontrast", "$envmapsaturation",
	"$color", "$color2", "$alpha",
}

local function SortKeys( kv )
	local rank, out = {}, {}

	for i, name in ipairs( ORDER ) do rank[ name ] = i end

	for k in pairs( kv ) do out[ #out + 1 ] = k end

	table.sort( out, function( a, b )
		local ra, rb = rank[ a ] or 999, rank[ b ] or 999
		if ra ~= rb then return ra < rb end
		return a < b
	end )

	return out
end

--- Build the .vmt text for a rule.
---
---     rule    { shader, params, gen, mat }
---     opts    { full = show inherited values too, basekv = the original }
---
--- Returns the text and the list of images that have to be converted.
function AdvMat.BuildVMT( rule, opts )
	opts = opts or {}

	local shader = rule.shader
	if not shader or shader == "" then shader = opts.shader or "VertexLitGeneric" end
	shader = AdvMat.CanonicalShader( shader )

	local kv = {}

	if opts.full then
		for k, v in pairs( opts.basekv or {} ) do
			if not AdvMat.IsInternalKey( k ) then kv[ k ] = v end
		end
	end

	for k, v in pairs( rule.params or {} ) do kv[ k ] = v end

	-- Generated images override whatever placeholder path the parameter is
	-- carrying, because the placeholder points at the texture the image was
	-- made FROM rather than at the image.
	local assets = {}

	for param, recipe in pairs( rule.gen or {} ) do
		local path   = SuggestPath( rule.mat, param )
		local format, flag, why = FormatAdvice( param, recipe )

		kv[ param ] = path

		assets[ #assets + 1 ] = {
			param   = param,
			file    = GEN.FileName( recipe ),
			path    = path,
			format  = format,
			flag    = flag,
			why     = why,
			summary = GEN.KindName( recipe ) .. ": " .. GEN.Describe( recipe ),
		}
	end

	table.sort( assets, function( a, b ) return a.param < b.param end )

	------------------------------------------------------------------ text
	local lines = {
		"// Written by the Advanced Material Editor.",
	}

	if #assets > 0 then
		lines[ #lines + 1 ] =
			"// This material uses " .. #assets .. " image(s) made in game."
		lines[ #lines + 1 ] =
			"// They have to be converted to .vtf before this file will work. See readme.txt."
	end

	lines[ #lines + 1 ] = ""
	lines[ #lines + 1 ] = "\"" .. shader .. "\""
	lines[ #lines + 1 ] = "{"

	for _, key in ipairs( SortKeys( kv ) ) do
		local value = kv[ key ]

		if isstring( value ) and value ~= "" then
			-- Everything is quoted. It is always legal, and it removes the
			-- question of which values happen to contain a space.
			lines[ #lines + 1 ] = string.format( "\t%-28s %s",
				"\"" .. string.lower( key ) .. "\"", "\"" .. value .. "\"" )
		end
	end

	lines[ #lines + 1 ] = "}"
	lines[ #lines + 1 ] = ""

	return table.concat( lines, "\n" ), assets
end

---------------------------------------------------------------------------
-- The readme that goes with the images
---------------------------------------------------------------------------
local function BuildReadme( matpath, assets, addon )
	local L = {}

	local function Add( s ) L[ #L + 1 ] = s or "" end

	Add( AdvMat.L( "export.readme_title" ) )
	Add( "======================================================" )
	Add()
	Add( AdvMat.L( "export.readme_intro" ) )
	Add()
	Add( AdvMat.L( "export.readme_step1" ) )
	Add()
	Add( AdvMat.L( "export.readme_step2" ) )
	Add()

	for _, a in ipairs( assets ) do
		Add( "   " .. a.param )
		Add( "     " .. AdvMat.L( "export.readme_file", {
			value = string.GetFileFromFilename( a.file ),
		} ) )
		Add( "     " .. AdvMat.L( "export.readme_save", { value = a.path } ) )
		Add( "     " .. AdvMat.L( "export.readme_format", {
			format = a.format,
			flag = a.flag and AdvMat.L( "export.readme_with_flag", { flag = a.flag } ) or "",
		} ) )
		Add( "     " .. AdvMat.L( "export.readme_why", {
			value = AdvMat.LText( a.why ),
		} ) )
		Add( "     " .. AdvMat.L( "export.readme_made", { value = a.summary } ) )
		Add()
		Add( "     vtfcmd.exe -file \"" .. string.GetFileFromFilename( a.file ) ..
			"\" -output \".\" -format \"" .. a.format .. "\"" ..
			( a.flag == "Normal Map" and " -flag \"NORMAL\"" or "" ) )
		Add()
	end

	Add( AdvMat.L( "export.readme_step3" ) )
	Add()
	Add( "     garrysmod/addons/" .. ( addon or "my_addon" ) .. "/materials/" .. matpath .. ".vmt" )

	for _, a in ipairs( assets ) do
		Add( "     garrysmod/addons/" .. ( addon or "my_addon" ) .. "/materials/" .. a.path .. ".vtf" )
	end

	Add()
	Add( AdvMat.L( "export.readme_step4" ) )
	Add()
	Add( AdvMat.L( "export.readme_final" ) )
	Add()

	return table.concat( L, "\n" )
end

---------------------------------------------------------------------------
-- The window
---------------------------------------------------------------------------
local PANEL = {}

function PANEL:Init()
	local rowH = AdvMat.RowHeight()

	-- Leave room for both the editable VMT text and the export notes, without a
	-- minimum which could strand the title bar beyond a small screen.
	self:SetMinWidth( math.min( math.max( 720, AdvMat.FontSize * 32 ),
		math.max( 1, ScrW() - 24 ) ) )
	self:SetMinHeight( math.min( 480, math.max( 1, ScrH() - 24 ) ) )
	self:SetSize( math.min( 1000, ScrW() - 80 ), math.min( 720, ScrH() - 80 ) )
	self:SetTitle( "Copy this material as a .vmt" )
	self:SetSizable( true )
	self:Center()
	self:MakePopup()
	AdvMat.StyleFrame( self )

	------------------------------------------------------------ bottom bar
	local bottom = vgui.Create( "DPanel", self )
	bottom:Dock( BOTTOM )
	bottom:SetTall( rowH + 6 )
	bottom:DockMargin( 0, 6, 0, 0 )
	bottom.Paint = AdvMat.NoPaint

	local function Button( text, chars, tip, fn )
		local b = vgui.Create( "DButton", bottom )
		b:Dock( RIGHT )
		b:SetWide( math.floor( AdvMat.FontSize * chars ) )
		b:DockMargin( 6, 0, 0, 0 )
		b:SetText( text )
		if tip then b:SetTooltip( tip ) end
		b.DoClick = fn
		AdvMat.StyleButton( b )
		return b
	end

	Button( "Close", 4.5, nil, function() self:Close() end )

	Button( "Copy to clipboard", 10, "Puts the text above on your clipboard.", function()
		if SetClipboardText then
			SetClipboardText( self.Text:GetValue() )
			AdvMat.NotifyLocal( "Copied.", NOTIFY_GENERIC, 3 )
		else
			AdvMat.NotifyLocal( AdvMat.L( "notify.clipboard_missing" ), NOTIFY_ERROR, 5 )
		end
	end )

	self.WriteBtn = Button( "Write the files", 9,
		AdvMat.L( "export.write_tip", { folder = EXPORT_DIR } ),
		function() self:WriteFiles() end )

	self.Full = vgui.Create( "DCheckBoxLabel", bottom )
	self.Full:Dock( LEFT )
	self.Full:DockMargin( 0, 4, 12, 4 )
	AdvMat.StyleCheck( self.Full, "Include the material's original settings" )
	self.Full:SetValue( true )
	self.Full:SetTooltip(
		"On: a complete material you can ship on its own.\n" ..
		"Off: only the parameters you changed, which is what you want if you are " ..
		"pasting into a .vmt that already exists." )
	self.Full.OnChange = function() self:Rebuild() end

	------------------------------------------------------------- the notes
	-- Docked before the text: a FILL claims whatever is left at the moment it
	-- is added, so anything docked to an edge has to come first.
	self.Side = vgui.Create( "DScrollPanel", self )
	self.Side:Dock( RIGHT )
	self.Side:SetWide( math.max( 320, AdvMat.FontSize * 22 ) )
	self.Side:DockMargin( 6, 0, 0, 0 )
	self.Side.Paint = AdvMat.Fill( T.Panel )

	------------------------------------------------------------ the text
	self.Text = vgui.Create( "DTextEntry", self )
	self.Text:Dock( FILL )
	self.Text:SetMultiline( true )
	self.Text:SetVerticalScrollbarEnabled( true )
	AdvMat.StyleEntry( self.Text )
end

local function SideNote( parent, title, body, warn )
	title = AdvMat.LText( title )
	body = AdvMat.LText( body )
	local head = parent:Add( "DLabel" )
	head:Dock( TOP )
	head:SetTall( AdvMat.RowHeight() )
	head:DockMargin( 6, 6, 6, 0 )
	head:SetText( title )
	AdvMat.StyleLabel( head, "AdvMatBold", warn and T.Warn or T.Text )

	local lines = AdvMat.WrapText( body, "AdvMatSmall", parent:GetWide() - 26 )

	local pnl = parent:Add( "DPanel" )
	pnl:Dock( TOP )
	pnl:SetTall( #lines * ( AdvMat.FontSize + 3 ) + 8 )
	pnl:DockMargin( 6, 2, 6, 2 )
	pnl.Paint = function( _, w, h )
		surface.SetDrawColor( T.Row.r, T.Row.g, T.Row.b, 255 )
		surface.DrawRect( 0, 0, w, h )

		for i, line in ipairs( lines ) do
			draw.SimpleText( line, "AdvMatSmall", 8,
				4 + ( i - 1 ) * ( AdvMat.FontSize + 3 ), T.TextDim )
		end
	end

	return pnl
end

function PANEL:Rebuild()
	local text, assets = AdvMat.BuildVMT( self.Rule, {
		full   = self.Full:GetChecked(),
		basekv = self.BaseKV,
		shader = self.BaseShader,
	} )

	self.VMT    = text
	self.Assets = assets

	self.Text:SetValue( text )

	self.Side:Clear()

	if #assets == 0 then
		SideNote( self.Side, AdvMat.L( "export.ready" ),
			AdvMat.L( "export.ready_body", {
				path = AdvMat.NormalizeMaterial( self.Rule.mat or "" ),
			} ) )
		return
	end

	SideNote( self.Side, AdvMat.L( "export.needs_images", { count = #assets } ),
		AdvMat.L( "export.images_body" ), true )

	for _, a in ipairs( assets ) do
		SideNote( self.Side, a.param, AdvMat.L( "export.asset_body", {
			summary = a.summary,
			path = a.path,
			format = a.format,
			flag = a.flag and AdvMat.L( "export.flag_tick", { flag = a.flag } ) or "",
			why = AdvMat.LText( a.why ),
		} ) )
	end
end

function PANEL:WriteFiles()
	local matpath = AdvMat.NormalizeMaterial( self.Rule.mat or "" )
	if matpath == "" then matpath = "models/mymodel/mytexture" end

	local folder = EXPORT_DIR .. "/" .. string.gsub( matpath, "/", "_" )

	file.CreateDir( "advmat" )
	file.CreateDir( EXPORT_DIR )
	file.CreateDir( folder )

	-- .vmt is on file.Write's allowed extension list, so the file that comes
	-- out is the real thing rather than something to rename. If a build
	-- disagrees, a .txt copy is still better than nothing.
	local name = string.GetFileFromFilename( matpath )
	local vmt  = folder .. "/" .. name .. ".vmt"

	file.Write( vmt, self.VMT )

	if not file.Exists( vmt, "DATA" ) then
		file.Write( vmt .. ".txt", self.VMT )
	end

	local missing = 0

	for _, a in ipairs( self.Assets ) do
		local data = file.Read( a.file, "DATA" )

		if data then
			file.Write( folder .. "/" .. string.GetFileFromFilename( a.file ), data )
		else
			-- The recipe has not been built yet on this machine. Asking for it
			-- queues it, so a second press picks it up.
			missing = missing + 1
		end
	end

	file.Write( folder .. "/readme.txt", BuildReadme( matpath, self.Assets ) )

	if missing > 0 then
		AdvMat.NotifyLocal( AdvMat.L( "notify.images_pending", { count = missing } ),
			NOTIFY_HINT, 7 )
	end

	AdvMat.NotifyLocal( "Written to garrysmod/data/" .. folder .. "/", NOTIFY_GENERIC, 7 )
	AdvMat.Log( "Exported %s to data/%s/", matpath, folder )
end

function PANEL:Setup( rule, basekv, shader )
	self.Rule       = rule or {}
	self.BaseKV     = basekv or {}
	self.BaseShader = shader

	self:SetTitle( "Copy this material as a .vmt   -   " ..
		AdvMat.NormalizeMaterial( self.Rule.mat or "" ) )

	self:Rebuild()
end

vgui.Register( "AdvMatVMTExport", PANEL, "DFrame" )

function AdvMat.OpenVMTExport( rule, basekv, shader, host )
	local frame = vgui.Create( "AdvMatVMTExport" )
	frame.AdvMatHost = IsValid( host ) and host
		or ( IsValid( AdvMat.Editor ) and AdvMat.Editor or nil )
	frame:Setup( rule, basekv, shader )
	if AdvMat.WindowUX then
		AdvMat.WindowUX.SetupFrame( frame, "vmt_export" )
		AdvMat.WindowUX.PlaceChild( frame, frame.AdvMatHost )
	end
	return frame
end
