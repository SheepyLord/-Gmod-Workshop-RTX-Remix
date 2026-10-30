--[[---------------------------------------------------------------------------
	Advanced Material Editor - RTX PBR node canvas

	The graph is deliberately a compact bake graph, not an MDL interpreter.
	Every connection compiles to one of Remix's fixed AperturePBR inputs or to
	a deterministic texture operation.  The shared schema remains the authority
	for validation; this panel only edits and visualises that data.
-----------------------------------------------------------------------------]]

AdvMat          = AdvMat or {}
AdvMat.RTXNodes = AdvMat.RTXNodes or {}

local N = AdvMat.RTXNodes
local T = AdvMat.Theme

local NODE_ORDER = {
	"texture", "value", "color", "invert", "multiply", "normal_from_height",
}

local NODE_LABEL = {
	output_surface     = "Material output",
	texture            = "Texture",
	value              = "Value",
	color              = "Colour",
	invert             = "Invert",
	multiply           = "Multiply",
	normal_from_height = "Normal from height",
}

local SOCKET_LABEL = {
	albedo = "Base colour", normal = "Normal",
	roughness = "Roughness", metallic = "Metallic", height = "Height",
	emissive = "Emission colour", emissive_intensity = "Emission strength",
	opacity = "Opacity", anisotropy = "Anisotropy",
	thin_film_thickness = "Thin-film thickness",
	displace_in = "Displace in", displace_out = "Displace out",
	subsurface_transmittance = "Transmittance colour",
	subsurface_thickness = "Measurement distance",
	subsurface_scattering = "Single-scattering albedo",
	subsurface_volumetric_anisotropy = "Volumetric anisotropy",
	subsurface_radius = "Subsurface-scattering radius",
	subsurface_radius_scale = "Subsurface radius scale",
	subsurface_max_sample_radius = "Maximum sample radius",
	color = "Colour", value = "Value", a = "A", b = "B",
}

local SOCKET_ORDER = {
	output_surface = {
		"albedo", "normal", "roughness", "metallic", "height",
		"emissive", "emissive_intensity", "opacity", "anisotropy",
		"thin_film_thickness", "displace_in", "displace_out",
		"subsurface_transmittance", "subsurface_thickness",
		"subsurface_scattering", "subsurface_volumetric_anisotropy",
		"subsurface_radius", "subsurface_radius_scale",
		"subsurface_max_sample_radius",
	},
	texture = { "color", "value", "normal" },
	value = { "value" }, color = { "color" }, invert = { "value" },
	multiply = { "a", "b", "value" },
	normal_from_height = { "height", "normal" },
}

local TYPE_COLOUR = {
	color   = Color( 224, 174, 91 ),
	number  = Color( 150, 187, 235 ),
	normal  = Color( 145, 216, 165 ),
	numeric = Color( 190, 170, 230 ),
	dynamic = Color( 190, 170, 230 ),
}

local function L( key, fallback )
	if AdvMat.I18N and AdvMat.I18N.HasKey and AdvMat.I18N.HasKey( key ) then
		return AdvMat.L( key )
	end
	return fallback
end

local function SocketLabel( socket )
	return L( "rtx.socket." .. socket, SOCKET_LABEL[ socket ] or socket )
end

local function Copy( value )
	return istable( value ) and table.Copy( value ) or value
end

local function Schema()
	return AdvMat.RTX and AdvMat.RTX.Schema
end

local function Definitions()
	local schema = Schema()
	return schema and schema.NODE_TYPES or {}
end

local function OrderedSockets( node, side )
	local def = Definitions()[ node.type ] or {}
	local source = side == "input" and ( def.inputs or {} ) or ( def.outputs or {} )
	local preferred, out, used = SOCKET_ORDER[ node.type ] or {}, {}, {}
	for _, socket in ipairs( preferred ) do
		if source[ socket ] then
			out[ #out + 1 ] = socket
			used[ socket ] = true
		end
	end
	local tail = {}
	for socket in pairs( source ) do
		if not used[ socket ] then tail[ #tail + 1 ] = socket end
	end
	table.sort( tail )
	for _, socket in ipairs( tail ) do out[ #out + 1 ] = socket end
	return out
end

local function NewNode( nodeType, id, x, y )
	local params = {}
	-- An empty texture node is intentionally incomplete.  Source logical/VTF
	-- names cannot be consumed by USD, so silently seeding one here would create
	-- a graph which looked valid in the UI but could never be published.
	if nodeType == "texture" then params.texture = ""
	elseif nodeType == "value" then params.value = 0.5
	elseif nodeType == "color" then params.color = { r = 1, g = 1, b = 1 }
	elseif nodeType == "invert" then params.value = 0
	elseif nodeType == "multiply" then params.a, params.b = 1, 1
	elseif nodeType == "normal_from_height" then
		params.strength, params.channel = 1, "luminance"
	end
	return { id = id, type = nodeType, x = x, y = y, params = params }
end

local IMAGE_EXTENSIONS = {
	dds = true, png = true, jpg = true, jpeg = true, bmp = true,
	tif = true, tiff = true, gif = true,
}

local function IsRuntimeImagePath( value )
	local extension = string.match( string.lower( value or "" ), "%.([%w]+)$" )
	return IMAGE_EXTENSIONS[ extension or "" ] == true
end

local PANEL = {}

function PANEL:Init()
	self.Graph = { nodes = {}, links = {}, authoritative = {} }
	self.PanX, self.PanY, self.Zoom = 80, 60, 1
	self.NodeWidth, self.HeaderHeight, self.SocketHeight = 210, 30, 24
	self.SelectedID = nil
	self.SocketCache = {}
	self.NodeRects = {}
	self.NextID = 0
	self:SetMouseInputEnabled( true )
	self:SetKeyboardInputEnabled( true )

	self.Inspector = vgui.Create( "DScrollPanel", self )
	self.Inspector:Dock( RIGHT )
	self.Inspector:SetWide( 285 )
	self.Inspector.Paint = AdvMat.Fill( Color( 42, 44, 50 ) )

	self.Hint = vgui.Create( "DLabel", self )
	self.Hint:Dock( BOTTOM )
	self.Hint:SetTall( AdvMat.RowHeight() )
	self.Hint:SetText( L( "rtx.graph.hint",
		"Right-click to add a node. Drag an output pin to an input pin. Delete removes the selected node." ) )
	AdvMat.StyleLabel( self.Hint, "AdvMatSmall", T.TextFaint )

	self:RebuildInspector()
end

function PANEL:CanvasWidth()
	return math.max( 0, self:GetWide() - ( IsValid( self.Inspector ) and self.Inspector:GetWide() or 0 ) )
end

function PANEL:SetGraph( graph )
	self.Graph = Copy( graph ) or { nodes = {}, links = {}, authoritative = {} }
	self.Graph.nodes = self.Graph.nodes or {}
	self.Graph.links = self.Graph.links or {}
	self.Graph.authoritative = self.Graph.authoritative or {}
	self.SelectedID = nil
	self:RebuildInspector()
	self:InvalidateLayout( true )
end

function PANEL:GetGraph()
	return Copy( self.Graph )
end

function PANEL:NodeByID( id )
	for _, node in ipairs( self.Graph.nodes or {} ) do
		if node.id == id then return node end
	end
end

function PANEL:MarkOutputSocket( nodeID, socket )
	local node = self:NodeByID( nodeID )
	if not node or node.type ~= "output_surface" then return false end
	self.Graph.authoritative = self.Graph.authoritative or {}
	self.Graph.authoritative[ socket ] = true
	return true
end

-- Changed() sanitises by copy, so every successful edit replaces all node
-- tables.  Inspector controls must resolve their node again by stable ID on
-- every callback instead of retaining a table that became stale after the
-- first slider tick or keypress.
function PANEL:MutateNode( nodeID, reason, mutate )
	local node = self:NodeByID( nodeID )
	if not node or not isfunction( mutate ) then return false end
	node.params = node.params or {}
	mutate( node )
	return self:Changed( reason )
end

function PANEL:GraphToScreen( x, y )
	return x * self.Zoom + self.PanX, y * self.Zoom + self.PanY
end

function PANEL:ScreenToGraph( x, y )
	return ( x - self.PanX ) / self.Zoom, ( y - self.PanY ) / self.Zoom
end

function PANEL:FreshID( prefix )
	self.NextID = self.NextID + 1
	local base = string.lower( ( string.gsub( prefix or "node", "[^%w_]", "_" ) ) )
	local id = base .. "_" .. tostring( math.floor( RealTime() * 1000 ) ) .. "_" .. self.NextID
	while self:NodeByID( id ) do
		self.NextID = self.NextID + 1
		id = base .. "_" .. self.NextID
	end
	return id
end

function PANEL:ValidateGraph( candidate )
	local schema = Schema()
	if not schema or not isfunction( schema.SanitizeGraph ) then return candidate end
	local clean, errors = schema.SanitizeGraph( candidate )
	return clean, errors
end

function PANEL:Changed( reason )
	local clean, errors = self:ValidateGraph( self.Graph )
	if clean then self.Graph = clean end
	if self.OnGraphChanged then self:OnGraphChanged( Copy( self.Graph ), reason, errors ) end
	self:InvalidateLayout( true )
	return clean ~= nil, errors
end

function PANEL:AddNode( nodeType, screenX, screenY )
	local def = Definitions()[ nodeType ]
	if not def or nodeType == "output_surface" then return end
	local x, y = self:ScreenToGraph( screenX, screenY )
	local node = NewNode( nodeType, self:FreshID( nodeType ), x, y )
	self.Graph.nodes[ #self.Graph.nodes + 1 ] = node
	self.SelectedID = node.id
	self:Changed( "add_node" )
	self:RebuildInspector()
end

function PANEL:RemoveNode( id, reason )
	local node = id and self:NodeByID( id )
	if not node or node.type == "output_surface" then return false end

	for index = #self.Graph.links, 1, -1 do
		local link = self.Graph.links[ index ]
		if link.from.node == id or link.to.node == id then
			self:MarkOutputSocket( link.to.node, link.to.socket )
			table.remove( self.Graph.links, index )
		end
	end
	for index = #self.Graph.nodes, 1, -1 do
		if self.Graph.nodes[ index ].id == id then table.remove( self.Graph.nodes, index ) end
	end
	if self.SelectedID == id then self.SelectedID = nil end
	local changed, errors = self:Changed( reason or "remove_node" )
	self:RebuildInspector()
	return changed, errors
end

function PANEL:RemoveSelected()
	return self:RemoveNode( self.SelectedID, "remove_node" )
end

function PANEL:Connect( from, to )
	if not from or not to or from.side ~= "output" or to.side ~= "input" then return false end
	local old = Copy( self.Graph )
	for index = #self.Graph.links, 1, -1 do
		local link = self.Graph.links[ index ]
		if link.to.node == to.node and link.to.socket == to.socket then
			table.remove( self.Graph.links, index )
		end
	end
	self.Graph.links[ #self.Graph.links + 1 ] = {
		from = { node = from.node, socket = from.socket },
		to = { node = to.node, socket = to.socket },
	}
	self:MarkOutputSocket( to.node, to.socket )
	local clean, errors = self:ValidateGraph( self.Graph )
	if not clean then
		self.Graph = old
		if self.OnGraphError then self:OnGraphError( errors or {} ) end
		return false
	end
	self.Graph = clean
	self:Changed( "connect" )
	return true
end

function PANEL:DisconnectInput( pin )
	if not pin or pin.side ~= "input" then return end
	local changed = false
	for index = #self.Graph.links, 1, -1 do
		local link = self.Graph.links[ index ]
		if link.to.node == pin.node and link.to.socket == pin.socket then
			table.remove( self.Graph.links, index )
			changed = true
		end
	end
	if changed then
		self:MarkOutputSocket( pin.node, pin.socket )
		self:Changed( "disconnect" )
	end
end

local function DrawBezier( x1, y1, x2, y2, colour )
	local bend = math.max( 55, math.abs( x2 - x1 ) * 0.45 )
	local px, py = x1, y1
	surface.SetDrawColor( colour.r, colour.g, colour.b, colour.a or 255 )
	for step = 1, 20 do
		local t = step / 20
		local u = 1 - t
		local x = u * u * u * x1 + 3 * u * u * t * ( x1 + bend )
			+ 3 * u * t * t * ( x2 - bend ) + t * t * t * x2
		local y = u * u * u * y1 + 3 * u * u * t * y1
			+ 3 * u * t * t * y2 + t * t * t * y2
		surface.DrawLine( px, py, x, y )
		px, py = x, y
	end
end

function PANEL:NodeSize( node )
	local inputs, outputs = OrderedSockets( node, "input" ), OrderedSockets( node, "output" )
	local rows = math.max( #inputs, #outputs, 1 )
	return self.NodeWidth, self.HeaderHeight + rows * self.SocketHeight + 9, inputs, outputs
end

function PANEL:Paint( w, h )
	local cw = self:CanvasWidth()
	surface.SetDrawColor( 31, 33, 38, 255 )
	surface.DrawRect( 0, 0, cw, h )

	local spacing = math.max( 18, 32 * self.Zoom )
	local ox, oy = self.PanX % spacing, self.PanY % spacing
	surface.SetDrawColor( 48, 51, 58, 150 )
	for x = ox, cw, spacing do surface.DrawLine( x, 0, x, h ) end
	for y = oy, h, spacing do surface.DrawLine( 0, y, cw, y ) end

	self.SocketCache, self.NodeRects = {}, {}
	for _, node in ipairs( self.Graph.nodes or {} ) do
		local nw, nh, inputs, outputs = self:NodeSize( node )
		local sx, sy = self:GraphToScreen( node.x, node.y )
		local sw, sh = nw * self.Zoom, nh * self.Zoom
		self.NodeRects[ node.id ] = { x = sx, y = sy, w = sw, h = sh, header = self.HeaderHeight * self.Zoom }

		for row, socket in ipairs( inputs ) do
			local py = sy + ( self.HeaderHeight + ( row - 0.5 ) * self.SocketHeight ) * self.Zoom
			self.SocketCache[ node.id .. "\1i\1" .. socket ] = {
				node = node.id, socket = socket, side = "input", x = sx, y = py,
				type = ( Definitions()[ node.type ].inputs or {} )[ socket ],
			}
		end
		for row, socket in ipairs( outputs ) do
			local py = sy + ( self.HeaderHeight + ( row - 0.5 ) * self.SocketHeight ) * self.Zoom
			self.SocketCache[ node.id .. "\1o\1" .. socket ] = {
				node = node.id, socket = socket, side = "output", x = sx + sw, y = py,
				type = ( Definitions()[ node.type ].outputs or {} )[ socket ],
			}
		end
	end

	for _, link in ipairs( self.Graph.links or {} ) do
		local from = self.SocketCache[ link.from.node .. "\1o\1" .. link.from.socket ]
		local to = self.SocketCache[ link.to.node .. "\1i\1" .. link.to.socket ]
		if from and to then DrawBezier( from.x, from.y, to.x, to.y, TYPE_COLOUR[ from.type ] or T.Accent ) end
	end

	if self.WireStart then
		local mx, my = self:LocalCursorPos()
		DrawBezier( self.WireStart.x, self.WireStart.y, math.min( mx, cw ), my,
			TYPE_COLOUR[ self.WireStart.type ] or T.Accent )
	end

	for _, node in ipairs( self.Graph.nodes or {} ) do
		local rect = self.NodeRects[ node.id ]
		if rect then
			local selected = node.id == self.SelectedID
			surface.SetDrawColor( selected and T.Selected or T.Row )
			surface.DrawRect( rect.x, rect.y, rect.w, rect.h )
			surface.SetDrawColor( node.type == "output_surface" and Color( 85, 102, 73 ) or T.Header )
			surface.DrawRect( rect.x, rect.y, rect.w, rect.header )
			surface.SetDrawColor( selected and T.Accent or T.Line )
			surface.DrawOutlinedRect( rect.x, rect.y, rect.w, rect.h, selected and 2 or 1 )

			draw.SimpleText( node.label or L( "rtx.node." .. node.type, NODE_LABEL[ node.type ] or node.type ),
				"AdvMatBold", rect.x + 10, rect.y + rect.header * 0.5, T.Text,
				TEXT_ALIGN_LEFT, TEXT_ALIGN_CENTER )

			local _, _, inputs, outputs = self:NodeSize( node )
			for row, socket in ipairs( inputs ) do
				local pin = self.SocketCache[ node.id .. "\1i\1" .. socket ]
				local colour = TYPE_COLOUR[ pin.type ] or T.Accent
				surface.SetDrawColor( colour )
				surface.DrawRect( pin.x - 5, pin.y - 5, 10, 10 )
				draw.SimpleText( SocketLabel( socket ), "AdvMatSmall", pin.x + 10,
					pin.y, T.TextDim, TEXT_ALIGN_LEFT, TEXT_ALIGN_CENTER )
			end
			for row, socket in ipairs( outputs ) do
				local pin = self.SocketCache[ node.id .. "\1o\1" .. socket ]
				local colour = TYPE_COLOUR[ pin.type ] or T.Accent
				surface.SetDrawColor( colour )
				surface.DrawRect( pin.x - 5, pin.y - 5, 10, 10 )
				draw.SimpleText( SocketLabel( socket ), "AdvMatSmall", pin.x - 10,
					pin.y, T.TextDim, TEXT_ALIGN_RIGHT, TEXT_ALIGN_CENTER )
			end
		end
	end
end

function PANEL:PinAt( x, y, side )
	for _, pin in pairs( self.SocketCache ) do
		if ( not side or pin.side == side ) and ( pin.x - x ) ^ 2 + ( pin.y - y ) ^ 2 <= 13 ^ 2 then
			return pin
		end
	end
end

function PANEL:NodeAt( x, y )
	for index = #( self.Graph.nodes or {} ), 1, -1 do
		local node = self.Graph.nodes[ index ]
		local r = self.NodeRects[ node.id ]
		if r and x >= r.x and x <= r.x + r.w and y >= r.y and y <= r.y + r.h then
			return node, r
		end
	end
end

function PANEL:OpenAddMenu( x, y )
	local menu = DermaMenu()
	for _, nodeType in ipairs( NODE_ORDER ) do
		if Definitions()[ nodeType ] then
			menu:AddOption( L( "rtx.node." .. nodeType, NODE_LABEL[ nodeType ] or nodeType ), function()
				if IsValid( self ) then self:AddNode( nodeType, x, y ) end
			end )
		end
	end
	menu:Open()
end

function PANEL:OnMousePressed( code )
	local x, y = self:LocalCursorPos()
	if x >= self:CanvasWidth() then return end
	self:RequestFocus()

	if code == MOUSE_RIGHT then
		self:OpenAddMenu( x, y )
		return
	elseif code == MOUSE_MIDDLE then
		self.Panning = { x = x, y = y, px = self.PanX, py = self.PanY }
		self:MouseCapture( true )
		return
	elseif code ~= MOUSE_LEFT then return end

	local pin = self:PinAt( x, y )
	if pin then
		if pin.side == "output" then
			self.WireStart = Copy( pin )
			self:MouseCapture( true )
		else
			self:DisconnectInput( pin )
		end
		return
	end

	local node, rect = self:NodeAt( x, y )
	self.SelectedID = node and node.id or nil
	self:RebuildInspector()
	if node and y <= rect.y + rect.header then
		self.Dragging = { node = node, x = x, y = y, nx = node.x, ny = node.y }
		self:MouseCapture( true )
	end
end

function PANEL:OnMouseReleased( code )
	local x, y = self:LocalCursorPos()
	local drag = self.Dragging
	local moved = code == MOUSE_LEFT and drag ~= nil
		and ( drag.node.x ~= drag.nx or drag.node.y ~= drag.ny )
	if code == MOUSE_LEFT and self.WireStart then
		local target = self:PinAt( x, y, "input" )
		if target then self:Connect( self.WireStart, target ) end
	end
	self.WireStart, self.Dragging, self.Panning = nil, nil, nil
	self:MouseCapture( false )
	if moved then self:Changed( "move_node" ) end
end

function PANEL:Think()
	local x, y = self:LocalCursorPos()
	if self.Dragging then
		local drag = self.Dragging
		drag.node.x = drag.nx + ( x - drag.x ) / self.Zoom
		drag.node.y = drag.ny + ( y - drag.y ) / self.Zoom
		self:InvalidateLayout()
	elseif self.Panning then
		local pan = self.Panning
		self.PanX, self.PanY = pan.px + x - pan.x, pan.py + y - pan.y
		self:InvalidateLayout()
	end
end

function PANEL:OnMouseWheeled( delta )
	local x, y = self:LocalCursorPos()
	if x >= self:CanvasWidth() then return false end
	local gx, gy = self:ScreenToGraph( x, y )
	self.Zoom = math.Clamp( self.Zoom * ( delta > 0 and 1.12 or 0.89 ), 0.55, 1.6 )
	self.PanX, self.PanY = x - gx * self.Zoom, y - gy * self.Zoom
	return true
end

function PANEL:OnKeyCodePressed( code )
	-- Claim the key, or Derma passes it on to the editor window as well.
	if code == KEY_DELETE or code == KEY_BACKSPACE then
		self:RemoveSelected()
		return true
	end
end

local function InspectorLabel( parent, text )
	local label = parent:Add( "DLabel" )
	label:Dock( TOP )
	label:SetTall( AdvMat.RowHeight() )
	label:DockMargin( 8, 6, 8, 0 )
	label:SetText( text )
	AdvMat.StyleLabel( label, "AdvMatBold", T.Text )
	return label
end

function PANEL:AddSlider( parent, label, value, lo, hi, decimals, changed )
	local slider = parent:Add( "DNumSlider" )
	slider:Dock( TOP )
	slider:SetTall( AdvMat.RowHeight() + 8 )
	slider:DockMargin( 8, 3, 8, 2 )
	slider:SetText( label )
	slider:SetMinMax( lo, hi )
	slider:SetDecimals( decimals or 3 )
	slider:SetValue( value or 0 )
	AdvMat.StyleSlider( slider )
	local ready = true
	slider.OnValueChanged = function( _, nextValue )
		if ready then changed( tonumber( nextValue ) or 0 ) end
	end
	return slider
end

function PANEL:RebuildInspector()
	if not IsValid( self.Inspector ) then return end
	self.Inspector:Clear()
	local node = self.SelectedID and self:NodeByID( self.SelectedID )
	if not node then
		local empty = InspectorLabel( self.Inspector,
			L( "rtx.graph.select", "Select a node to edit its settings." ) )
		empty:SetWrap( true )
		empty:SetTall( AdvMat.RowHeight() * 2 )
		return
	end
	local nodeID = node.id

	InspectorLabel( self.Inspector,
		node.label or L( "rtx.node." .. node.type, NODE_LABEL[ node.type ] or node.type ) )

	local label = self.Inspector:Add( "DTextEntry" )
	label:Dock( TOP )
	label:SetTall( AdvMat.RowHeight() )
	label:DockMargin( 8, 4, 8, 8 )
	label:SetPlaceholderText( L( "rtx.graph.node_label", "Optional node label" ) )
	label:SetValue( node.label or "" )
	AdvMat.StyleEntry( label )
	label.OnChange = function( field )
		self:MutateNode( nodeID, "node_label", function( current )
			current.label = string.Trim( field:GetValue() or "" )
			if current.label == "" then current.label = nil end
		end )
	end

	node.params = node.params or {}
	if node.type == "texture" then
		InspectorLabel( self.Inspector, L( "rtx.graph.texture_path", "Texture path" ) )
		local path = self.Inspector:Add( "DTextEntry" )
		path:Dock( TOP )
		path:SetTall( AdvMat.RowHeight() )
		path:DockMargin( 8, 2, 8, 4 )
		path:SetValue( node.params.texture or "" )
		AdvMat.StyleEntry( path )
		local submittedPath
		path.OnChange = function() submittedPath = nil end
		local function AcceptPath( field )
			local selected = string.Trim( field:GetValue() or "" )
			if selected == submittedPath then return end
			submittedPath = selected
			if selected == "" then
				-- A Texture node without a path is invalid. Clearing therefore means
				-- removing that node and its links, preserving explicit output ownership.
				self:RemoveNode( nodeID, "texture_clear" )
			elseif IsRuntimeImagePath( selected ) then
				self:MutateNode( nodeID, "texture_path", function( current )
					current.params.texture = selected
					current.params.recipe = nil
				end )
			elseif self.OnEditTextureNode then
				-- Defer committing a Source/VTF name until the texture editor has
				-- produced a portable recipe.  Cancelling leaves the graph unchanged.
				self:OnEditTextureNode( nodeID, selected )
			end
		end
		path.OnEnter = AcceptPath
		path.OnLoseFocus = AcceptPath

		local buttons = self.Inspector:Add( "DPanel" )
		buttons:Dock( TOP )
		buttons:SetTall( AdvMat.RowHeight() )
		buttons:DockMargin( 8, 0, 8, 8 )
		buttons.Paint = AdvMat.NoPaint
		local browse = buttons:Add( "DButton" )
		browse:Dock( LEFT )
		browse:SetWide( 105 )
		browse:SetText( L( "rtx.graph.browse", "Browse" ) )
		AdvMat.StyleButton( browse )
		browse.DoClick = function()
			local current = self:NodeByID( nodeID )
			AdvMat.OpenTexturePicker( current and current.params.texture or "", function( selected )
				if not IsValid( self ) then return end
				-- The shared picker's Clear button returns an empty string. Handle it
				-- before Source-path routing; an empty Texture node is invalid, so use
				-- the graph's real removal operation rather than storing an empty path.
				if selected == "" then
					self:RemoveNode( nodeID, "texture_clear" )
					return
				end
				-- The Source picker normally returns a logical VTF material name,
				-- which a USD layer cannot read from disk.  Route it through the
				-- shared editor so the accepted result carries a portable recipe and
				-- is materialised to an image before native publication.  Explicit
				-- DDS/WIC image paths remain valid direct inputs.
				if IsRuntimeImagePath( selected ) then
					self:MutateNode( nodeID, "texture_path", function( liveNode )
						liveNode.params.texture = selected
						liveNode.params.recipe = nil
					end )
					self:RebuildInspector()
				elseif self.OnEditTextureNode then
					-- Do not store the unreadable logical name first: cancelling the
					-- texture editor must leave the previous valid node untouched.
					self:OnEditTextureNode( nodeID, selected )
				end
			end )
		end
		local edit = buttons:Add( "DButton" )
		edit:Dock( RIGHT )
		edit:SetWide( 105 )
		edit:SetText( L( "common.edit", "Edit" ) )
		AdvMat.StyleButton( edit )
		edit.DoClick = function()
			if self.OnEditTextureNode then self:OnEditTextureNode( nodeID ) end
		end
	elseif node.type == "value" then
		local currentValue = tonumber( node.params.value ) or 0
		local extent = math.max( 16, math.abs( currentValue ) )
		self:AddSlider( self.Inspector, L( "rtx.graph.value", "Value" ), currentValue,
			-extent, extent, 3, function( v )
				self:MutateNode( nodeID, "node_value", function( current ) current.params.value = v end )
			end )
	elseif node.type == "color" then
		local mixer = self.Inspector:Add( "DColorMixer" )
		mixer:Dock( TOP )
		mixer:SetTall( 190 )
		mixer:DockMargin( 8, 4, 8, 8 )
		mixer:SetPalette( false )
		mixer:SetAlphaBar( false )
		mixer:SetWangs( true )
		local c = node.params.color or { r = 1, g = 1, b = 1 }
		mixer:SetColor( Color( c.r * 255, c.g * 255, c.b * 255 ) )
		mixer.ValueChanged = function( _, colour )
			self:MutateNode( nodeID, "node_color", function( current )
				current.params.color = { r = colour.r / 255, g = colour.g / 255, b = colour.b / 255 }
			end )
		end
	elseif node.type == "invert" then
		self:AddSlider( self.Inspector, L( "rtx.graph.unlinked_value", "Unlinked value" ),
			node.params.value, 0, 1, 3,
			function( v )
				self:MutateNode( nodeID, "node_value", function( current ) current.params.value = v end )
			end )
	elseif node.type == "multiply" then
		self:AddSlider( self.Inspector, SocketLabel( "a" ), node.params.a, 0, 16, 3,
			function( v )
				self:MutateNode( nodeID, "node_value", function( current ) current.params.a = v end )
			end )
		self:AddSlider( self.Inspector, SocketLabel( "b" ), node.params.b, 0, 16, 3,
			function( v )
				self:MutateNode( nodeID, "node_value", function( current ) current.params.b = v end )
			end )
	elseif node.type == "normal_from_height" then
		self:AddSlider( self.Inspector, L( "rtx.graph.strength", "Strength" ),
			node.params.strength, 0.01, 32, 2,
			function( v )
				self:MutateNode( nodeID, "node_value", function( current ) current.params.strength = v end )
			end )
		local channel = self.Inspector:Add( "DComboBox" )
		channel:Dock( TOP )
		channel:SetTall( AdvMat.RowHeight() )
		channel:DockMargin( 8, 4, 8, 8 )
		local selectedChannel = node.params.channel or "luminance"
		channel:SetValue( L( "rtx.channel." .. selectedChannel, selectedChannel ) )
		for _, value in ipairs( { "luminance", "r", "g", "b", "a" } ) do
			channel:AddChoice( L( "rtx.channel." .. value, value ), value )
		end
		AdvMat.StyleCombo( channel )
		channel.OnSelect = function( _, _, _, value )
			self:MutateNode( nodeID, "node_channel", function( current )
				current.params.channel = value
			end )
		end
	end

	if node.type ~= "output_surface" then
		local remove = self.Inspector:Add( "DButton" )
		remove:Dock( TOP )
		remove:SetTall( AdvMat.RowHeight() )
		remove:DockMargin( 8, 12, 8, 8 )
		remove:SetText( L( "rtx.graph.delete_node", "Delete node" ) )
		AdvMat.StyleButton( remove, true )
		remove.DoClick = function()
			if self:NodeByID( nodeID ) then
				self.SelectedID = nodeID
				self:RemoveSelected()
			end
		end
	end
end

vgui.Register( "AdvMatRTXNodeCanvas", PANEL, "DPanel" )
