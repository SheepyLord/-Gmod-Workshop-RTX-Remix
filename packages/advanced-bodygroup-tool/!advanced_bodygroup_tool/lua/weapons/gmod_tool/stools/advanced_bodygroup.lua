TOOL.Category = "Render"
TOOL.Name = "#tool.advanced_bodygroup.name"
TOOL.Command = nil
TOOL.ConfigName = ""

TOOL.ClientConVar = { noglow = "0" }

local function ResolveEntity( entity )
	if IsValid( entity ) and entity:GetClass() == "prop_effect"
	and IsValid( entity.AttachedEntity ) then
		return entity.AttachedEntity
	end
	return entity
end

function TOOL:GetSelectedEntity()
	local weapon = self:GetWeapon()
	if not IsValid( weapon ) then return NULL end
	return weapon:GetNW2Entity( "AdvancedBodygroupTool.Selected", NULL )
end

function TOOL:SetSelectedEntity( entity )
	if CLIENT then return end
	entity = ResolveEntity( entity )
	if not AdvancedBodygroupTool.IsEditableEntity( entity ) then entity = NULL end
	local weapon = self:GetWeapon()
	if not IsValid( weapon ) or self:GetSelectedEntity() == entity then return end
	weapon:SetNW2Entity( "AdvancedBodygroupTool.Selected", entity )
end

function TOOL:LeftClick( trace )
	if CLIENT then return true end
	local entity = ResolveEntity( trace.Entity )
	if not AdvancedBodygroupTool.IsEditableEntity( entity ) then return false end
	-- Another player is selectable only by an admin; the server refuses every
	-- action on them otherwise.
	if not AdvancedBodygroupTool.CanEditPlayer( self:GetOwner(), entity ) then return false end
	self:SetSelectedEntity( entity )
	return true
end

function TOOL:RightClick( trace ) return self:LeftClick( trace ) end

function TOOL:Reload()
	if SERVER then self:SetSelectedEntity( self:GetOwner() ) end
	return true
end

function TOOL:Think()
	if CLIENT then return end
	local entity = self:GetSelectedEntity()
	if IsValid( entity ) and ( not AdvancedBodygroupTool.IsEditableEntity( entity )
	or not AdvancedBodygroupTool.CanEditPlayer( self:GetOwner(), entity ) ) then
		self:SetSelectedEntity( NULL )
	end
end

if SERVER then return end

TOOL.Information = {
	{ name = "left" },
	{ name = "right" },
	{ name = "reload" },
}

local ABT = AdvancedBodygroupTool
local function L( key, variables )
	return ABT and ABT.L and ABT.L( key, variables ) or tostring( key )
end
if ABT and ABT.I18N and ABT.I18N.ApplyToolPhrases then
	ABT.I18N.ApplyToolPhrases()
end

local lastEntity = NULL
local lastModel = ""
local lastRevision = -1
local lastLanguage = ""
local nextPanelCheck = 0
local expandedBodygroups = setmetatable( {}, { __mode = "k" } )
local regionPreviewMaterialCache = {}

local REGION_BACKGROUND = Color( 238, 238, 238 )
local REGION_HOVER = Color( 224, 236, 248 )
local REGION_SELECTED = Color( 255, 218, 205 )
local REGION_BORDER = Color( 125, 125, 125 )
local REGION_SHAPE = Color( 80, 120, 150, 205 )
local REGION_SHAPE_SELECTED = Color( 205, 70, 45, 220 )
local REGION_PREVIEW_FRAME = Color( 28, 32, 39, 248 )
local REGION_PREVIEW_LIGHT = Color( 210, 214, 220 )
local REGION_PREVIEW_DARK = Color( 155, 160, 168 )
local REGION_PREVIEW_SIZE = 286

local function NiceName( value, fallback )
	value = tostring( value or "" )
	if value == "" then return fallback or L( "common.unnamed" ) end
	value = string.StripExtension( value )
	value = string.GetFileFromFilename( value )
	value = string.Replace( value, "_", " " )
	return string.Trim( value )
end

local function NormalizeMaterialPath( path )
	path = string.lower( string.Trim( tostring( path or "" ) ) )
	path = string.Replace( path, "\\", "/" )
	path = string.gsub( path, "^materials/", "" )
	return string.gsub( path, "%.vmt$", "" )
end

local function ResolveRegionPreviewMaterial( entity, materialPath )
	local target = NormalizeMaterialPath( materialPath )
	local source
	for index, path in ipairs( entity:GetMaterials() or {} ) do
		if NormalizeMaterialPath( path ) == target then
			local override = entity:GetSubMaterial( index - 1 ) or ""
			if override ~= "" then
				local name = string.sub( override, 1, 1 ) == "!"
					and string.sub( override, 2 ) or override
				local material = Material( name )
				if material and not material:IsError() then source = material end
			end
			break
		end
	end
	if not source then
		local material = Material( materialPath or "" )
		if material and not material:IsError() then source = material end
	end
	if not source then return nil end
	local texture = source:GetTexture( "$basetexture" )
	if not texture or texture:IsError() then return source end
	local key = string.lower( tostring( source:GetName() ) .. "|"
		.. tostring( texture:GetName() ) )
	local preview = regionPreviewMaterialCache[ key ]
	if not preview then
		preview = CreateMaterial( "abt_region_material_preview_" .. util.CRC( key ),
			"UnlitGeneric", {
				[ "$basetexture" ] = texture:GetName(),
				[ "$translucent" ] = "1",
				[ "$vertexcolor" ] = "1",
				[ "$vertexalpha" ] = "1",
			} )
		regionPreviewMaterialCache[ key ] = preview
	end
	preview:SetTexture( "$basetexture", texture )
	local transform = source:GetMatrix( "$basetexturetransform" )
	if transform then
		pcall( preview.SetMatrix, preview, "$basetexturetransform", transform )
	end
	return preview
end

local function SendAction( entity, action, writer )
	if not IsValid( entity ) then return end
	net.Start( "advanced_bodygroup_tool_apply" )
		net.WriteEntity( entity )
		net.WriteUInt( action, 3 )
		if writer then writer() end
	net.SendToServer()
end

local function HiddenRegionCount( regions )
	local count = 0
	for _, hidden in pairs( regions or {} ) do
		if hidden then count = count + 1 end
	end
	return count
end

local function RefreshPanelSoon()
	timer.Simple( 0, function()
		local player = LocalPlayer()
		local weapon = IsValid( player ) and player:GetWeapon( "gmod_tool" ) or NULL
		local tool = IsValid( weapon )
			and weapon:GetToolObject( "advanced_bodygroup" ) or nil
		if tool then tool:UpdateControlPanel() end
	end )
end

local function DrawCheckerboard( x, y, width, height )
	local size = 14
	for row = 0, math.ceil( height / size ) - 1 do
		for column = 0, math.ceil( width / size ) - 1 do
			surface.SetDrawColor( ( row + column ) % 2 == 0
				and REGION_PREVIEW_LIGHT or REGION_PREVIEW_DARK )
			surface.DrawRect( x + column * size, y + row * size,
				math.min( size, width - column * size ),
				math.min( size, height - row * size ) )
		end
	end
end

local function DrawRegionPreview( region, x, y, width, height, selected, material )
	local textured = material and not material:IsError()
	if textured then DrawCheckerboard( x, y, width, height )
	else draw.RoundedBox( 3, x, y, width, height, Color( 252, 252, 252 ) ) end
	if textured then
		surface.SetMaterial( material )
		surface.SetDrawColor( color_white )
	else
		draw.NoTexture()
		surface.SetDrawColor( selected and REGION_SHAPE_SELECTED or REGION_SHAPE )
	end
	for _, source in ipairs( region.preview or {} ) do
		if #source == 3 then
			local polygon = {}
			for index, point in ipairs( source ) do
				polygon[ index ] = {
					x = x + 3 + point.x * ( width - 6 ),
					y = y + 3 + point.y * ( height - 6 ),
					u = point.u or 0,
					v = point.v or 0,
				}
			end
			local signedArea = ( polygon[ 2 ].x - polygon[ 1 ].x )
				* ( polygon[ 3 ].y - polygon[ 1 ].y )
				- ( polygon[ 2 ].y - polygon[ 1 ].y )
				* ( polygon[ 3 ].x - polygon[ 1 ].x )
			if signedArea < 0 then polygon[ 2 ], polygon[ 3 ] = polygon[ 3 ], polygon[ 2 ] end
			surface.DrawPoly( polygon )
		end
	end
	surface.SetDrawColor( selected and REGION_SHAPE_SELECTED or REGION_BORDER )
	surface.DrawOutlinedRect( x, y, width, height )
end

local function AddRegionCard( parent, entity, groupId, region, hidden )
	local selected = hidden and true or false
	local previewMaterial = ResolveRegionPreviewMaterial( entity, region.material )
	local previewPanel
	local card = vgui.Create( "DButton", parent )
	card:Dock( TOP )
	card:DockMargin( 0, 0, 4, 4 )
	card:SetTall( 62 )
	card:SetText( "" )
	card:SetCursor( "hand" )
	local function PositionLargePreview()
		if not IsValid( previewPanel ) then return end
		local mouseX, mouseY = gui.MousePos()
		local x, y = mouseX + 22, mouseY + 18
		if x + previewPanel:GetWide() > ScrW() - 8 then
			x = mouseX - previewPanel:GetWide() - 22
		end
		if y + previewPanel:GetTall() > ScrH() - 8 then
			y = mouseY - previewPanel:GetTall() - 18
		end
		previewPanel:SetPos( math.Clamp( x, 8,
			math.max( ScrW() - previewPanel:GetWide() - 8, 8 ) ),
			math.Clamp( y, 8,
			math.max( ScrH() - previewPanel:GetTall() - 8, 8 ) ) )
	end
	local function SetLargePreview( enabled )
		if enabled and not IsValid( previewPanel ) then
			previewPanel = vgui.Create( "DPanel" )
			previewPanel:SetSize( REGION_PREVIEW_SIZE, REGION_PREVIEW_SIZE )
			previewPanel:SetMouseInputEnabled( false )
			previewPanel:SetKeyboardInputEnabled( false )
			previewPanel:SetDrawOnTop( true )
			previewPanel:SetZPos( 32767 )
			previewPanel.Paint = function( _, width, height )
				draw.RoundedBox( 7, 0, 0, width, height, REGION_PREVIEW_FRAME )
				draw.SimpleText( L( "region.title", { id = region.id } ),
					"DermaLarge", 12, 7, color_white, TEXT_ALIGN_LEFT, TEXT_ALIGN_TOP )
				draw.SimpleText( NiceName( region.material, L( "common.material" ) ),
					"DermaDefault", 13, 32, Color( 205, 215, 225 ),
					TEXT_ALIGN_LEFT, TEXT_ALIGN_TOP )
				DrawRegionPreview( region, 10, 51, width - 20, height - 61,
					selected, previewMaterial )
			end
			PositionLargePreview()
		elseif not enabled and IsValid( previewPanel ) then
			previewPanel:Remove()
			previewPanel = nil
		end
	end
	local function SetWorldHover( enabled )
		if card.AdvancedBodygroupWorldHover == enabled then return end
		card.AdvancedBodygroupWorldHover = enabled
		if enabled then
			AdvancedBodygroupTool.SetHoveredRegion( entity, groupId, region.id )
		else
			AdvancedBodygroupTool.ClearHoveredRegion( entity, groupId, region.id )
		end
	end
	local function SetHovered( enabled )
		SetWorldHover( enabled )
		SetLargePreview( enabled )
	end
	card.Think = function( self )
		local hovered = self:IsHovered()
		SetHovered( hovered )
		if hovered then PositionLargePreview() end
	end
	card.OnCursorEntered = function() SetHovered( true ) end
	card.OnCursorExited = function() SetHovered( false ) end
	card.OnRemove = function() SetHovered( false ) end
	card.Paint = function( self, width, height )
		local background = selected and REGION_SELECTED
			or ( self:IsHovered() and REGION_HOVER or REGION_BACKGROUND )
		draw.RoundedBox( 4, 0, 0, width, height, background )
		surface.SetDrawColor( REGION_BORDER )
		surface.DrawOutlinedRect( 0, 0, width, height )
		DrawRegionPreview( region, 7, 7, 52, 48, selected )
		draw.SimpleText( L( "region.title", { id = region.id } ), "DermaDefaultBold",
			67, 12, color_black, TEXT_ALIGN_LEFT, TEXT_ALIGN_TOP )
		draw.SimpleText( L( "region.triangle_count",
			{ count = region.triangleCount } ) .. " · "
			.. NiceName( region.material, L( "common.material" ) ), "DermaDefault",
			67, 34, Color( 75, 75, 75 ), TEXT_ALIGN_LEFT, TEXT_ALIGN_TOP )
		local boxX, boxY = width - 25, 22
		surface.SetDrawColor( Color( 70, 70, 70 ) )
		surface.DrawOutlinedRect( boxX, boxY, 15, 15 )
		if selected then
			surface.SetDrawColor( Color( 190, 55, 35 ) )
			surface.DrawRect( boxX + 3, boxY + 3, 9, 9 )
		end
	end
	card.DoClick = function()
		selected = not selected
		SendAction( entity, AdvancedBodygroupTool.Action.SetRegionHidden, function()
			net.WriteUInt( groupId, 8 )
			net.WriteUInt( region.id, 12 )
			net.WriteBool( selected )
		end )
	end
	return card
end

local function SortedBodygroups( entity )
	local result = {}
	for rawKey, group in pairs( entity:GetBodyGroups() or {} ) do
		if istable( group ) then
			local id = tonumber( group.id ) or tonumber( rawKey )
			if id then result[ #result + 1 ] = { id = id, data = group } end
		end
	end
	table.sort( result, function( left, right ) return left.id < right.id end )
	return result
end

local function AddBodygroupRow( panel, entity, entry, hidden, hiddenRegions,
	vertexKeepBounds )
	local id = entry.id
	local group = entry.data
	local count = math.max( tonumber( group.num ) or 0,
		entity:GetBodygroupCount( id ) or 0 )
	local expandedForEntity = expandedBodygroups[ entity ]
	local expanded = expandedForEntity and expandedForEntity[ id ] or false
	local container = vgui.Create( "DPanel", panel )
	container:SetPaintBackground( false )
	local totalHeight = 25

	local header = vgui.Create( "DPanel", container )
	header:SetPaintBackground( false )
	header:Dock( TOP )
	header:SetTall( 24 )
	local forceHide = vgui.Create( "DCheckBoxLabel", header )
	forceHide:Dock( RIGHT )
	forceHide:SetWide( 218 )
	forceHide:SetDark( true )
	forceHide:SetText( L( "force.all" ) )
	forceHide:SetTooltip( L( "force.tooltip" ) )
	forceHide:SetValue( hidden and 1 or 0 )
	forceHide:SizeToContentsX( 8 )
	forceHide.OnChange = function( _, checked )
		SendAction( entity, AdvancedBodygroupTool.Action.SetForceHidden, function()
			net.WriteUInt( id, 8 )
			net.WriteBool( checked )
		end )
	end

	local label = vgui.Create( "DLabel", header )
	label:Dock( FILL )
	label:SetDark( true )
	label:SetFont( "DermaDefaultBold" )
	label:SetText( L( "bodygroup.label", {
		name = NiceName( group.name, L( "bodygroup.fallback", { id = id } ) ),
		id = id,
	} ) )

	if count > 1 then
		local combo = vgui.Create( "DComboBox", container )
		combo:Dock( TOP )
		combo:SetTall( 24 )
		for value = 0, math.min( count - 1, 255 ) do
			local rawName = group.submodels and group.submodels[ value ] or nil
			local optionName = rawName == "" and L( "bodygroup.hidden_blank" )
				or NiceName( rawName, L( "bodygroup.option", { value = value } ) )
			combo:AddChoice( value .. " — " .. optionName,
				value, value == entity:GetBodygroup( id ) )
		end
		combo.OnSelect = function( _, _, _, value )
			SendAction( entity, AdvancedBodygroupTool.Action.SetBodygroup, function()
				net.WriteUInt( id, 8 )
				net.WriteUInt( value, 8 )
			end )
		end
		totalHeight = totalHeight + 24
	end

	local groupDisplayName = NiceName( group.name,
		L( "bodygroup.fallback", { id = id } ) )
	local vertexButton = vgui.Create( "DButton", container )
	vertexButton:Dock( TOP )
	vertexButton:DockMargin( 0, 3, 0, 0 )
	vertexButton:SetTall( 24 )
	vertexButton:SetText( L( vertexKeepBounds
		and "vertex.button_active" or "vertex.button" ) )
	vertexButton:SetTooltip( L( "vertex.button_tooltip" ) )
	vertexButton.DoClick = function()
		AdvancedBodygroupTool.OpenVertexKeepEditor( entity, id, groupDisplayName )
	end
	totalHeight = totalHeight + 27

	local selectedCount = HiddenRegionCount( hiddenRegions )
	local regionButton = vgui.Create( "DButton", container )
	regionButton:Dock( TOP )
	regionButton:DockMargin( 0, 3, 0, 0 )
	regionButton:SetTall( 24 )
	regionButton:SetText( L( expanded and "region.close" or "region.choose" )
		.. ( selectedCount > 0 and "  " .. L( "region.hidden_count",
			{ count = selectedCount } ) or "" ) )
	regionButton:SetTooltip( L( "region.selector_tooltip" ) )
	regionButton.DoClick = function()
		expandedBodygroups[ entity ] = expandedBodygroups[ entity ] or {}
		expandedBodygroups[ entity ][ id ] = not expanded
		RefreshPanelSoon()
	end
	totalHeight = totalHeight + 27

	if expanded then
		local regions, errorMessage = AdvancedBodygroupTool.GetBodygroupRegions( entity, id )
		local regionBox = vgui.Create( "DPanel", container )
		regionBox:Dock( TOP )
		regionBox:DockMargin( 0, 4, 0, 0 )
		regionBox:SetPaintBackground( false )
		if not regions then
			regionBox:SetTall( 42 )
			local failure = vgui.Create( "DLabel", regionBox )
			failure:Dock( FILL )
			failure:SetDark( true )
			failure:SetWrap( true )
			failure:SetText( L( "region.failure", { error = errorMessage } ) )
			totalHeight = totalHeight + 46
		elseif #regions == 0 then
			regionBox:SetTall( 38 )
			local empty = vgui.Create( "DLabel", regionBox )
			empty:Dock( FILL )
			empty:SetDark( true )
			empty:SetWrap( true )
			empty:SetText( L( "region.empty" ) )
			totalHeight = totalHeight + 42
		else
			local listHeight = math.min( #regions, 4 ) * 66
			local noteHeight = 42
			regionBox:SetTall( noteHeight + listHeight )
			local note = vgui.Create( "DLabel", regionBox )
			note:Dock( TOP )
			note:SetTall( noteHeight )
			note:SetDark( true )
			note:SetWrap( true )
			note:SetText( L( hidden and "region.note_override"
				or "region.note_hover" ) )
			local scroll = vgui.Create( "DScrollPanel", regionBox )
			scroll:Dock( FILL )
			for _, region in ipairs( regions ) do
				if region.id <= 4095 then
					AddRegionCard( scroll, entity, id, region,
						hiddenRegions and hiddenRegions[ region.id ] )
				end
			end
			totalHeight = totalHeight + noteHeight + listHeight + 4
		end
	end
	container:SetTall( totalHeight )
	panel:AddItem( container )
end

function TOOL.BuildCPanel( panel )
    if NATIVELOADER_I18N then NATIVELOADER_I18N.PreparePanel(panel) end
	panel:ClearControls()
	local language = panel:ComboBox( L( "language.title" ) )
	local languageConVar = GetConVar( "abt_language" )
	local selectedLanguage = languageConVar and languageConVar:GetString() or "auto"
	local languageOptions = ABT.I18N and ABT.I18N.GetLanguageOptions
		and ABT.I18N.GetLanguageOptions() or { "auto", "en" }
	for _, code in ipairs( languageOptions ) do
		language:AddChoice( L( "language." .. code ), code,
			code == selectedLanguage )
	end
	language.OnSelect = function( _, _, _, code )
		RunConsoleCommand( "abt_language", code )
	end
	panel:CheckBox( L( "tool.noglow" ), "advanced_bodygroup_noglow" )
	local player = LocalPlayer()
	local weapon = IsValid( player ) and player:GetWeapon( "gmod_tool" ) or NULL
	local tool = IsValid( weapon ) and weapon:GetToolObject( "advanced_bodygroup" ) or nil
	local entity = tool and tool:GetSelectedEntity() or NULL
	if not IsValid( entity ) then
		panel:Help( L( "panel.select_help" ) )
		return
	end

	panel:Help( tostring( entity:GetModel() or L( "common.unknown_model" ) ) )
	local hideAll = panel:Button( L( "panel.hide_all_hideable" ) )
	hideAll:SetTooltip( L( "panel.hide_all_hideable_tooltip" ) )
	hideAll.DoClick = function()
		SendAction( entity, AdvancedBodygroupTool.Action.HideAllHideable )
	end
	local showAll = panel:Button( L( "panel.show_all_reset" ) )
	showAll:SetTooltip( L( "panel.show_all_reset_tooltip" ) )
	showAll.DoClick = function()
		SendAction( entity, AdvancedBodygroupTool.Action.ShowAllReset )
	end
	local skinCount = entity:SkinCount() or 0
	if skinCount > 1 then
		local skin = panel:ComboBox( L( "bodygroup.skin" ) )
		for value = 0, math.min( skinCount - 1, 255 ) do
			skin:AddChoice( L( "bodygroup.skin_value", { value = value } ),
				value, value == entity:GetSkin() )
		end
		skin.OnSelect = function( _, _, _, value )
			SendAction( entity, AdvancedBodygroupTool.Action.SetSkin, function()
				net.WriteUInt( value, 8 )
			end )
		end
	end

	local hidden = AdvancedBodygroupTool.GetHiddenBodygroupSet( entity )
	local hiddenRegions = AdvancedBodygroupTool.GetHiddenRegionSet( entity )
	local vertexKeepBounds = AdvancedBodygroupTool.GetVertexKeepBounds( entity )
	for _, entry in ipairs( SortedBodygroups( entity ) ) do
		local keepBounds = vertexKeepBounds[ entry.id ]
		if keepBounds and tonumber( keepBounds.option )
		~= entity:GetBodygroup( entry.id ) then keepBounds = nil end
		AddBodygroupRow( panel, entity, entry, hidden[ entry.id ],
			hiddenRegions[ entry.id ], keepBounds )
	end
	panel:Help( L( "panel.mask_help" ) )
	local restore = panel:Button( L( "panel.restore" ) )
	restore.DoClick = function()
		SendAction( entity, AdvancedBodygroupTool.Action.RestoreForceHidden )
	end
end

function TOOL:UpdateControlPanel()
	local panel = controlpanel.Get( "advanced_bodygroup" )
	if IsValid( panel ) then self.BuildCPanel( panel ) end
end

function TOOL:GetStage()
	return IsValid( self:GetSelectedEntity() ) and 1 or 0
end

function TOOL:Think()
	local now = RealTime()
	if now < nextPanelCheck then return end
	nextPanelCheck = now + 0.2
	local entity = self:GetSelectedEntity()
	local model = IsValid( entity ) and ( entity:GetModel() or "" ) or ""
	local revision = IsValid( entity )
		and entity:GetNW2Int( AdvancedBodygroupTool.RevisionNWKey, 0 ) or -1
	local language = ABT.I18N and ABT.I18N.language or "en"
	if entity == lastEntity and model == lastModel and revision == lastRevision
	and language == lastLanguage then return end
	lastEntity, lastModel, lastRevision = entity, model, revision
	lastLanguage = language
	self:UpdateControlPanel()
end

function TOOL:DrawHUD()
	local entity = self:GetSelectedEntity()
	if not IsValid( entity ) or self:GetClientNumber( "noglow", 0 ) ~= 0 then return end
	local entities = { entity }
	if entity.GetActiveWeapon then
		local weapon = entity:GetActiveWeapon()
		if IsValid( weapon ) then entities[ #entities + 1 ] = weapon end
	end
	halo.Add( entities, HSVToColor( ( CurTime() * 45 ) % 360, 0.75, 1 ),
		2, 2, 1, true, true )
end
