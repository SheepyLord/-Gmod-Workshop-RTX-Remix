--[[---------------------------------------------------------------------------
	Advanced Material Editor - texture picker

	A browser over everything mounted under materials/. Handles both .vmt and
	.vtf, because VMT parameters that take a texture ( $basetexture, $bumpmap,
	$phongexponenttexture, $envmapmask, $lightwarptexture ... ) want a raw VTF
	path, not a material path.

	It also guesses sibling maps: given "models/foo/body" it will surface
	"models/foo/body_normal", "..._n", "..._bump", "..._exp" and so on, which is
	almost always what you want when wiring up a bump or exponent map.
-----------------------------------------------------------------------------]]

AdvMat = AdvMat or {}

local T = AdvMat.Theme

local function IconSize() return math.max( 100, AdvMat.FontSize * 6 ) end

local LAST_DIR_COOKIE    = "advmat_texpicker_last_dir"
local LAST_SCROLL_COOKIE = "advmat_texpicker_last_scroll"
local DEFAULT_DIR        = "materials/models/"

--- Canonicalise a mounted materials directory before it reaches file.Find or
--- the cookie store. Cookies are client-owned input, so a remembered value is
--- held to the same traversal/absolute-path boundary as a selected texture.
local function PickerDirectory( raw )
	if not isstring( raw ) then return nil end

	local dir = string.gsub( raw, "\\", "/" )
	dir = string.lower( string.Trim( dir ) )
	if dir == "materials" then dir = "materials/" end
	if string.sub( dir, 1, 10 ) ~= "materials/" then return nil end
	if string.find( dir, ":", 1, true ) or string.find( dir, "//", 1, true )
		or string.find( dir, "[%c]" ) then
		return nil
	end

	if not string.EndsWith( dir, "/" ) then dir = dir .. "/" end
	for part in string.gmatch( dir, "[^/]+" ) do
		if part == "." or part == ".." then return nil end
	end

	if not file.IsDir( dir, "GAME" ) then return nil end
	return dir
end

local function TextureDirectory( raw )
	local path = AdvMat.NormalizeMaterial( raw or "" )
	if path == "" then return nil end
	return PickerDirectory( string.GetPathFromFilename( "materials/" .. path ) )
end

local function RememberedPickerDirectory()
	if not cookie or not cookie.GetString then return nil end
	return PickerDirectory( cookie.GetString( LAST_DIR_COOKIE, "" ) )
end

local function RememberedPickerScroll()
	if not cookie or not cookie.GetNumber then return 0 end
	return math.max( 0, cookie.GetNumber( LAST_SCROLL_COOKIE, 0 ) or 0 )
end

--- Resolve the folder shown when a picker opens. An actual current texture is
--- authoritative; otherwise the user's last browse location beats the merely
--- advisory sibling-map suggestion.
function AdvMat.TexturePickerStartDir( current, suggestBase )
	local currentDir = TextureDirectory( current )
	if currentDir then return currentDir end

	local remembered = RememberedPickerDirectory()
	if remembered then return remembered end

	local suggested = TextureDirectory( suggestBase )
	if suggested then return suggested end

	return PickerDirectory( DEFAULT_DIR ) or PickerDirectory( "materials/" ) or DEFAULT_DIR
end

--- Store only a real mounted folder. A stale or tampered path must not replace
--- the last good location merely because a picker happened to close.
function AdvMat.RememberTexturePickerDir( dir, scroll )
	local clean = PickerDirectory( dir )
	if not clean or not cookie or not cookie.Set then return false end

	cookie.Set( LAST_DIR_COOKIE, clean )
	cookie.Set( LAST_SCROLL_COOKIE,
		tostring( math.max( 0, tonumber( scroll ) or 0 ) ) )
	return true
end

---------------------------------------------------------------------------
-- Preview materials
---------------------------------------------------------------------------
local previewCache, previewSerial = {}, 0

-- Procedural materials cannot be freed, only recycled, so browsing has to be
-- bounded. Well past what any one browsing session needs.
local MAX_PREVIEWS = 2000

local function PreviewMaterial( path )
	path = AdvMat.NormalizeMaterial( path )
	if path == "" then return nil end

	local cached = previewCache[ path ]
	if cached ~= nil then return cached or nil end

	if previewSerial >= MAX_PREVIEWS then return nil end

	previewSerial = previewSerial + 1

	local mat = CreateMaterial( "advmat_prev_" .. previewSerial, "UnlitGeneric", {
		[ "$basetexture" ]  = path,
		[ "$translucent" ]  = "1",
		[ "$vertexalpha" ]  = "1",
		[ "$vertexcolor" ]  = "1",
		[ "$nolod" ]        = "1",
	} )

	-- A missing VTF yields the checkerboard error texture; keep it anyway so
	-- the user can see that the path is wrong.
	previewCache[ path ] = mat or false
	return mat
end

AdvMat.PreviewMaterial = PreviewMaterial

---------------------------------------------------------------------------
-- Sibling map guessing
---------------------------------------------------------------------------
local SUFFIX_GUESSES = {
	bump     = { "_normal", "_n", "_nrm", "_bump", "_norm", "_ddn", "_normalmap" },
	exponent = { "_exp", "_exponent", "_phong", "_spec", "_s", "_gloss" },
	mask     = { "_mask", "_m", "_envmapmask", "_specmask" },
	illum    = { "_illum", "_selfillum", "_glow", "_emissive", "_i" },
	detail   = { "_detail", "_dtl" },
}

--- Given a base texture path, return the paths of any sibling maps that
--- actually exist on disk, tagged by the kind of map they look like.
function AdvMat.GuessSiblingMaps( basePath )
	local out  = {}
	local path = AdvMat.NormalizeMaterial( basePath )
	if path == "" then return out end

	-- Strip a suffix the base itself might carry, e.g. "body_diffuse".
	local stem = string.gsub( path, "_?d?i?f?f?u?s?e?$", "" )

	for kind, suffixes in pairs( SUFFIX_GUESSES ) do
		for _, suffix in ipairs( suffixes ) do
			for _, candidate in ipairs( { path .. suffix, stem .. suffix } ) do
				if file.Exists( "materials/" .. candidate .. ".vtf", "GAME" ) then
					out[ #out + 1 ] = { kind = kind, path = candidate }
					break
				end
			end
		end
	end

	return out
end

---------------------------------------------------------------------------
-- Directory listing
---------------------------------------------------------------------------
local function ListDir( dir )
	if not string.EndsWith( dir, "/" ) then dir = dir .. "/" end

	local files, dirs = file.Find( dir .. "*", "GAME" )
	files = files or {}
	dirs  = dirs  or {}

	local textures = {}
	for _, f in ipairs( files ) do
		local ext = string.GetExtensionFromFilename( f )
		if ext == "vtf" or ext == "vmt" then
			textures[ #textures + 1 ] = {
				name = f,
				path = AdvMat.NormalizeMaterial( dir .. f ),
				ext  = ext,
			}
		end
	end

	table.sort( textures, function( a, b ) return a.name < b.name end )
	table.sort( dirs )

	return textures, dirs
end

--- Recursive search under `root` for files whose name contains `needle`.
--- Depth limited so a search from materials/ does not hang the game.
local function SearchDir( root, needle, out, depth )
	out   = out or {}
	depth = depth or 0
	if depth > 6 or #out >= 400 then return out end

	if not string.EndsWith( root, "/" ) then root = root .. "/" end

	local files, dirs = file.Find( root .. "*", "GAME" )

	for _, f in ipairs( files or {} ) do
		local ext = string.GetExtensionFromFilename( f )
		if ( ext == "vtf" or ext == "vmt" ) and string.find( string.lower( f ), needle, 1, true ) then
			out[ #out + 1 ] = {
				name = f,
				path = AdvMat.NormalizeMaterial( root .. f ),
				ext  = ext,
			}
			if #out >= 400 then return out end
		end
	end

	for _, d in ipairs( dirs or {} ) do
		SearchDir( root .. d, needle, out, depth + 1 )
		if #out >= 400 then return out end
	end

	return out
end

---------------------------------------------------------------------------
-- The picker frame
---------------------------------------------------------------------------

--- AdvMat.OpenTexturePicker( currentPath, onPick, [suggestBase], [host] )
---   onPick( path )   called with a normalised, extensionless texture path
---   suggestBase      optional base texture path used to seed the "Suggested"
---                    strip at the top of the results
---   host             editor/controller which owns the callback
function AdvMat.OpenTexturePicker( current, onPick, suggestBase, host )
	if IsValid( AdvMat.TexPicker ) then AdvMat.TexPicker:Remove() end

	local frame = vgui.Create( "DFrame" )
	AdvMat.TexPicker = frame
	frame.AdvMatHost = IsValid( host ) and host
		or ( IsValid( AdvMat.Editor ) and AdvMat.Editor or nil )
	-- Keep both the folder tree and an icon grid usable, but never declare a
	-- minimum larger than WindowUX's 12 px screen margin can accommodate.
	frame:SetMinWidth( math.min( math.max( 640, AdvMat.FontSize * 28 ),
		math.max( 1, ScrW() - 24 ) ) )
	frame:SetMinHeight( math.min( 400, math.max( 1, ScrH() - 24 ) ) )
	frame:SetSize( math.min( 1000, ScrW() - 80 ), math.min( 640, ScrH() - 80 ) )
	frame:SetTitle( "Choose a texture" )
	frame:SetSizable( true )
	frame:Center()
	frame:MakePopup()

	local rowH     = AdvMat.RowHeight()
	local selected = AdvMat.NormalizeMaterial( current or "" )
	local startDir = AdvMat.TexturePickerStartDir( current, suggestBase )
	local rememberedDir = RememberedPickerDirectory()
	local startScroll = rememberedDir == startDir and RememberedPickerScroll() or 0

	---------------------------------------------------------------- bottom
	local bottom = vgui.Create( "DPanel", frame )
	bottom:Dock( BOTTOM )
	bottom:SetTall( rowH + 4 )
	bottom:DockMargin( 0, 6, 0, 0 )
	bottom.Paint = AdvMat.NoPaint

	-- The buttons are created before the path box. Docking is resolved in the
	-- order children were added and a FILL child takes the whole rect that is
	-- left at that moment, so a FILL added first ends up underneath anything
	-- docked to an edge afterwards.
	local accept = vgui.Create( "DButton", bottom )
	accept:Dock( RIGHT )
	accept:SetWide( AdvMat.FontSize * 7 )
	accept:DockMargin( 6, 0, 0, 0 )
	accept:SetText( "Use texture" )
	AdvMat.StyleButton( accept )

	local clear = vgui.Create( "DButton", bottom )
	clear:Dock( RIGHT )
	clear:SetWide( AdvMat.FontSize * 4 )
	clear:DockMargin( 6, 0, 0, 0 )
	clear:SetText( "Clear" )
	AdvMat.StyleButton( clear, true )

	local pathEntry = vgui.Create( "DTextEntry", bottom )
	pathEntry:Dock( FILL )
	pathEntry:SetValue( selected )
	pathEntry:SetUpdateOnType( false )
	AdvMat.StyleEntry( pathEntry )

	accept.DoClick = function()
		local p = AdvMat.NormalizeMaterial( pathEntry:GetValue() )
		AdvMat.RememberTexturePickerDir( TextureDirectory( p ), 0 )
		frame:Close()
		if onPick then onPick( p ) end
	end

	clear.DoClick = function()
		frame:Close()
		if onPick then onPick( "" ) end
	end

	----------------------------------------------------------------- top
	local top = vgui.Create( "DPanel", frame )
	top:Dock( TOP )
	top:SetTall( rowH + 2 )
	top:DockMargin( 0, 0, 0, 6 )
	top.Paint = AdvMat.NoPaint

	-- Same rule: the edge-docked box first, then the one that fills.
	local searchRoot = vgui.Create( "DTextEntry", top )
	searchRoot:Dock( RIGHT )
	searchRoot:SetWide( AdvMat.FontSize * 16 )
	searchRoot:DockMargin( 6, 0, 0, 0 )
	searchRoot:SetValue( "materials/models" )
	AdvMat.StyleEntry( searchRoot )

	local search = vgui.Create( "DTextEntry", top )
	search:Dock( FILL )
	search:SetPlaceholderText( "Search every mounted material... (min 3 characters)" )
	AdvMat.StyleEntry( search )
	searchRoot:SetTooltip( "Folder the search starts from. Narrow it to make searching fast." )

	--------------------------------------------------------------- panes
	local divider = vgui.Create( "DHorizontalDivider", frame )
	divider:Dock( FILL )
	divider:SetLeftWidth( 260 )
	divider:SetDividerWidth( 6 )

	local tree = vgui.Create( "DTree", divider )
	tree.Paint = AdvMat.Fill( T.Panel )
	divider:SetLeft( tree )

	local right = vgui.Create( "DScrollPanel", divider )
	right.Paint = AdvMat.Fill( T.Panel )
	divider:SetRight( right )

	local grid = vgui.Create( "DIconLayout", right )
	grid:Dock( FILL )
	grid:SetSpaceX( 4 )
	grid:SetSpaceY( 4 )

	local activeDir, folderView
	local scrollRestoreSerial = 0

	local function GridScroll()
		local bar = right.GetVBar and right:GetVBar() or nil
		if IsValid( bar ) and bar.GetScroll then return math.max( 0, bar:GetScroll() or 0 ) end
		return 0
	end

	local function RememberActiveDirectory()
		if not folderView or not activeDir then return end
		AdvMat.RememberTexturePickerDir( activeDir, GridScroll() )
	end

	local function RestoreGridScroll( scroll )
		scrollRestoreSerial = scrollRestoreSerial + 1
		local serial = scrollRestoreSerial
		local target = math.max( 0, tonumber( scroll ) or 0 )

		-- DIconLayout does not know its final height until after two layout passes.
		-- Applying the value immediately would clamp every restored offset to zero.
		timer.Simple( 0, function()
			if not IsValid( right ) or serial ~= scrollRestoreSerial then return end
			right:InvalidateLayout( true )
			timer.Simple( 0, function()
				if not IsValid( right ) or serial ~= scrollRestoreSerial then return end
				local bar = right.GetVBar and right:GetVBar() or nil
				if IsValid( bar ) and bar.SetScroll then bar:SetScroll( target ) end
			end )
		end )
	end

	---------------------------------------------------------------- icons
	local iconSize = IconSize()

	local function AddIcon( entry, tag )
		local btn = grid:Add( "DButton" )
		btn:SetSize( iconSize, iconSize + rowH + 6 )
		btn:SetText( "" )
		btn:SetTooltip( entry.path .. ( entry.ext and ( "." .. entry.ext ) or "" ) )

		local mat = PreviewMaterial( entry.path )

		btn.Paint = function( self, w, h )
			local isSel = ( entry.path == selected )
			draw.RoundedBox( 4, 0, 0, w, h,
				isSel and T.Selected or ( self:IsHovered() and T.RowHover or T.Row ) )

			if mat then
				surface.SetDrawColor( 255, 255, 255, 255 )
				surface.SetMaterial( mat )
				surface.DrawTexturedRect( 4, 4, w - 8, w - 8 )
			end

			draw.SimpleText( string.sub( entry.name, 1, 18 ), "AdvMatSmall",
				w * 0.5, h - rowH * 0.5, T.Text, TEXT_ALIGN_CENTER, TEXT_ALIGN_CENTER )

			if tag then
				draw.SimpleText( tag, "AdvMatSmall", 6, 6, T.Warn )
			end
		end

		btn.DoClick = function()
			selected = entry.path
			pathEntry:SetValue( entry.path )
			surface.PlaySound( "ui/buttonclick.wav" )
		end

		btn.DoDoubleClick = function()
			selected = entry.path
			AdvMat.RememberTexturePickerDir( TextureDirectory( entry.path ), 0 )
			frame:Close()
			if onPick then onPick( entry.path ) end
		end
	end

	local function ShowEntries( entries, suggestions )
		grid:Clear()

		for _, s in ipairs( suggestions or {} ) do
			AddIcon( { name = string.GetFileFromFilename( s.path ), path = s.path, ext = "vtf" }, s.kind )
		end

		for _, e in ipairs( entries ) do AddIcon( e ) end

		if #entries == 0 and #( suggestions or {} ) == 0 then
			local lbl = grid:Add( "DLabel" )
			lbl:SetText( "Nothing here." )
			AdvMat.StyleLabel( lbl, "AdvMatText", T.TextDim )
			lbl:SizeToContents()
		end
	end

	local function ShowDirectory( dir, suggestions, scroll )
		local clean = PickerDirectory( dir )
		if not clean then return false end

		RememberActiveDirectory()
		activeDir, folderView = clean, true
		ShowEntries( ( ListDir( clean ) ), suggestions )
		AdvMat.RememberTexturePickerDir( clean, scroll or 0 )
		RestoreGridScroll( scroll )
		return true
	end

	local baseOnRemove = frame.OnRemove
	frame.OnRemove = function( self )
		RememberActiveDirectory()
		if AdvMat.TexPicker == self then AdvMat.TexPicker = nil end
		if baseOnRemove then baseOnRemove( self ) end
	end

	-- StyleFrame registers the DFrame with WindowUX.  Do this after installing
	-- our cleanup handler so WindowUX can safely chain (rather than be replaced
	-- by) the picker-specific OnRemove work above.
	AdvMat.StyleFrame( frame )
	if AdvMat.WindowUX then
		AdvMat.WindowUX.SetupFrame( frame, "texture_picker" )
		AdvMat.WindowUX.PlaceChild( frame, frame.AdvMatHost )
	end

	---------------------------------------------------------------- tree
	local nodesByDir = {}

	local function PopulateNode( node, dir )
		if node.AdvMatPopulated then return end
		node.AdvMatPopulated = true

		local _, dirs = ListDir( dir )
		for _, d in ipairs( dirs ) do
			local child = node:AddNode( d, "icon16/folder.png" )
			child.AdvMatDir = PickerDirectory( dir .. d .. "/" ) or ( dir .. d .. "/" )
			nodesByDir[ child.AdvMatDir ] = child
			-- Give it an expander arrow without listing the whole tree up front.
			child.DoClick = function( self )
				PopulateNode( self, self.AdvMatDir )
				ShowDirectory( self.AdvMatDir, nil, 0 )
				return false
			end
			-- Populate on demand rather than walking the whole materials tree
			-- up front. Overriding SetExpanded catches both the arrow and any
			-- programmatic expansion; the expander button calls it internally.
			local baseSetExpanded = child.SetExpanded
			child.SetExpanded = function( pnl, expand, noAnim )
				PopulateNode( pnl, pnl.AdvMatDir )
				baseSetExpanded( pnl, expand, noAnim )
			end

			if child.SetForceShowExpander then child:SetForceShowExpander( true ) end
		end
	end

	local root = tree:AddNode( "materials", "icon16/folder_database.png" )
	root.AdvMatDir = "materials/"
	nodesByDir[ root.AdvMatDir ] = root
	root.DoClick = function( self )
		PopulateNode( self, self.AdvMatDir )
		ShowDirectory( self.AdvMatDir, nil, 0 )
		return false
	end
	PopulateNode( root, "materials/" )
	root:SetExpanded( true )

	local function RevealDirectory( dir )
		local clean = PickerDirectory( dir )
		if not clean then return false end

		local node = root
		local walked = "materials/"
		for part in string.gmatch( string.sub( clean, #walked + 1 ), "[^/]+" ) do
			PopulateNode( node, walked )
			walked = walked .. part .. "/"
			local child = nodesByDir[ walked ]
			if not IsValid( child ) then return false end
			node:SetExpanded( true, true )
			node = child
		end

		node:ExpandTo( true )
		tree:SetSelectedItem( node )
		timer.Simple( 0, function()
			if not IsValid( tree ) or not IsValid( node ) then return end
			tree:InvalidateLayout( true )
			timer.Simple( 0, function()
				if IsValid( tree ) and IsValid( node ) then tree:ScrollToChild( node ) end
			end )
		end )
		return true
	end

	-------------------------------------------------------------- search
	local function RunSearch()
		local needle = string.lower( string.Trim( search:GetValue() ) )
		if #needle < 3 then return end

		local rootDir = string.Trim( searchRoot:GetValue() )
		if rootDir == "" then rootDir = "materials/" end

		RememberActiveDirectory()
		folderView = false
		ShowEntries( SearchDir( rootDir, needle ) )
		RestoreGridScroll( 0 )
	end

	search.OnEnter      = RunSearch
	searchRoot.OnEnter  = RunSearch

	------------------------------------------------------- initial view
	local suggestions = suggestBase and AdvMat.GuessSiblingMaps( suggestBase ) or {}
	ShowDirectory( startDir, suggestions, startScroll )
	RevealDirectory( startDir )

	return frame
end
