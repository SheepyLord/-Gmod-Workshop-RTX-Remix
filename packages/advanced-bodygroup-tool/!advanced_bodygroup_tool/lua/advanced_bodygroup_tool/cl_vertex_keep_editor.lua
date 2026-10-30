-- Interactive model-space multi-plane cut editor.

if not CLIENT then return end

local ABT = AdvancedBodygroupTool
local function L( key, variables )
	return ABT and ABT.L and ABT.L( key, variables ) or tostring( key )
end

-- Keep the editor usable while a newly added translation is incomplete.
local function T( key, fallback, variables )
	local translated = L( key, variables )
	if translated ~= key then return translated end
	local fallbackText = string.gsub( fallback or key, "{([%w_]+)}", function( name )
		return variables and tostring( variables[ name ] or "" ) or ""
	end )
	return fallbackText
end

local MAX_CUTS = ABT.MaxVertexCutsPerGroup or 16
local MAX_TOTAL_CUTS = ABT.MaxVertexCuts or 64
local PREVIEW_VERTEX_LIMIT = 60000
local PREVIEW_REBUILD_DELAY = 0.12
local PREVIEW_FOV = 65

-- Apply is acknowledged by the server so a rejected edit never closes over the
-- user's draft. Reloading this file intentionally cancels callbacks from the old UI.
ABT.VertexCutApplyRequests = {}
ABT.VertexCutApplySerial = tonumber( ABT.VertexCutApplySerial ) or 0

local function FinishApplyRequest( requestId, success, timedOut )
	local request = ABT.VertexCutApplyRequests[ requestId ]
	if not request then return end
	ABT.VertexCutApplyRequests[ requestId ] = nil
	if isfunction( request.callback ) then
		local ok, failure = pcall( request.callback, success == true, timedOut == true )
		if not ok then
			ErrorNoHalt( "[Advanced Bodygroup Tool] Cut apply callback failed: "
				.. tostring( failure ) .. "\n" )
		end
	end
end

net.Receive( "advanced_bodygroup_tool_vertex_cuts_result", function()
	FinishApplyRequest( net.ReadUInt( 16 ), net.ReadBool(), false )
end )

local function AllocateApplyRequest( callback )
	for _ = 1, 65535 do
		ABT.VertexCutApplySerial = ABT.VertexCutApplySerial % 65535 + 1
		local requestId = ABT.VertexCutApplySerial
		if not ABT.VertexCutApplyRequests[ requestId ] then
			local request = { callback = callback }
			ABT.VertexCutApplyRequests[ requestId ] = request
			timer.Simple( 8, function()
				if ABT.VertexCutApplyRequests[ requestId ] == request then
					FinishApplyRequest( requestId, false, true )
				end
			end )
			return requestId
		end
	end
end

-- Material("color") includes $model, $vertexcolor, $vertexalpha and
-- $translucent. Supplying the classification color on every vertex avoids
-- relying on model-only color modulation for a hand-built IMesh.
local PREVIEW_COLOR_MATERIAL = Material( "color" )
local PREVIEW_KEPT_COLOR = Color( 49, 199, 229, 230 )
local PREVIEW_REMOVED_COLOR = Color( 235, 67, 55, 82 )
local PREVIEW_PLANE_MATERIAL = CreateMaterial(
	"abt_vertex_cut_preview_plane_v2", "UnlitGeneric", {
		[ "$basetexture" ] = "vgui/white",
		[ "$vertexcolor" ] = "1", [ "$vertexalpha" ] = "1",
		[ "$translucent" ] = "1", [ "$nocull" ] = "1",
	} )

local function FiniteNumber( value, fallback )
	value = tonumber( value )
	if not value or value ~= value or value == math.huge or value == -math.huge then
		return fallback
	end
	return value
end

local function DestroyMeshList( meshes )
	for _, meshObject in ipairs( meshes or {} ) do
		if meshObject and meshObject.Destroy then pcall( meshObject.Destroy, meshObject ) end
	end
end

local function DestroyPreview( preview )
	if not preview then return end
	DestroyMeshList( preview.kept )
	DestroyMeshList( preview.removed )
end

local function TriangleNormal( first, second, third )
	local normal = ( second - first ):Cross( third - first )
	if normal:LengthSqr() < 0.000001 then return Vector( 0, 0, 1 ) end
	normal:Normalize()
	return normal
end

local function BuildPreview( data, option, cuts )
	local preview = { kept = {}, removed = {}, keptCount = 0, removedCount = 0 }
	local pending = { kept = {}, removed = {} }
	local colors = {
		kept = PREVIEW_KEPT_COLOR,
		removed = PREVIEW_REMOVED_COLOR,
	}
	local cutState = { option = option, cuts = cuts }
	local compiledCuts = ABT.CompileVertexKeepCuts
		and ABT.CompileVertexKeepCuts( cutState ) or nil

	local function flush( kind )
		local vertices = pending[ kind ]
		if #vertices == 0 then return true end
		local meshObject = Mesh( PREVIEW_COLOR_MATERIAL )
		local ok = pcall( meshObject.BuildFromTriangles, meshObject, vertices )
		pending[ kind ] = {}
		if not ok then
			if meshObject.Destroy then pcall( meshObject.Destroy, meshObject ) end
			return false
		end
		preview[ kind ][ #preview[ kind ] + 1 ] = meshObject
		return true
	end

	for _, triangle in ipairs( data.triangles or {} ) do
		local positions = triangle.positions
		if istable( positions ) and #positions == 3
		and isvector( positions[ 1 ] ) and isvector( positions[ 2 ] )
		and isvector( positions[ 3 ] ) then
			local kept = ABT.TrianglePassesVertexKeepBounds(
				triangle, cutState, compiledCuts )
			local kind = kept and "kept" or "removed"
			local countKey = kept and "keptCount" or "removedCount"
			preview[ countKey ] = preview[ countKey ] + 1
			local normal = TriangleNormal( positions[ 1 ], positions[ 2 ], positions[ 3 ] )
			for index = 1, 3 do
				local uv = triangle.uv and triangle.uv[ index ] or nil
				pending[ kind ][ #pending[ kind ] + 1 ] = {
					pos = positions[ index ],
					normal = normal,
					u = uv and uv.u or 0,
					v = uv and uv.v or 0,
					color = colors[ kind ],
				}
			end
			if #pending[ kind ] >= PREVIEW_VERTEX_LIMIT then flush( kind ) end
		end
	end
	flush( "kept" )
	flush( "removed" )
	return preview
end

local function CutAngle( cut )
	return Angle(
		FiniteNumber( cut and cut.pitch, 0 ),
		FiniteNumber( cut and cut.yaw, 0 ),
		FiniteNumber( cut and cut.roll, 0 ) )
end

local function CopyCut( source, center )
	source = istable( source ) and source or {}
	local sourceOrigin = isvector( source.origin ) and source.origin or nil
	local sourceAngle = isangle( source.angle ) and source.angle or nil
	local cut = {
		enabled = source.enabled ~= false,
		keep_positive = source.keep_positive ~= false
			and source.keepPositive ~= false,
		ox = FiniteNumber( source.ox, sourceOrigin and sourceOrigin.x or center.x ),
		oy = FiniteNumber( source.oy, sourceOrigin and sourceOrigin.y or center.y ),
		oz = FiniteNumber( source.oz, sourceOrigin and sourceOrigin.z or center.z ),
		pitch = FiniteNumber( source.pitch, sourceAngle and sourceAngle.p or 0 ),
		yaw = FiniteNumber( source.yaw, sourceAngle and sourceAngle.y or 0 ),
		roll = FiniteNumber( source.roll, sourceAngle and sourceAngle.r or 0 ),
	}
	local normal = CutAngle( cut ):Forward()
	cut.offset = ( Vector( cut.ox, cut.oy, cut.oz ) - center ):Dot( normal )
	cut.ox = center.x + normal.x * cut.offset
	cut.oy = center.y + normal.y * cut.offset
	cut.oz = center.z + normal.z * cut.offset
	return cut
end

local function AxisCut( center, value, pitch, yaw, keepPositive )
	local cut = {
		enabled = true,
		keep_positive = keepPositive,
		pitch = pitch,
		yaw = yaw,
		roll = 0,
	}
	local normal = CutAngle( cut ):Forward()
	local axisOrigin = Vector( center.x, center.y, center.z )
	if math.abs( normal.x ) > 0.5 then axisOrigin.x = value end
	if math.abs( normal.y ) > 0.5 then axisOrigin.y = value end
	if math.abs( normal.z ) > 0.5 then axisOrigin.z = value end
	cut.offset = ( axisOrigin - center ):Dot( normal )
	cut.ox = center.x + normal.x * cut.offset
	cut.oy = center.y + normal.y * cut.offset
	cut.oz = center.z + normal.z * cut.offset
	return cut
end

local function CopySavedCuts( saved, center )
	local cuts = {}
	if istable( saved ) and istable( saved.cuts ) then
		for _, source in ipairs( saved.cuts ) do
			if #cuts >= MAX_CUTS then break end
			cuts[ #cuts + 1 ] = CopyCut( source, center )
		end
		return cuts
	end

	-- Convert pre-v6 axis-aligned keep ranges into equivalent cut planes.
	if not istable( saved ) then return cuts end
	if saved.xmin_on and #cuts < MAX_CUTS then
		cuts[ #cuts + 1 ] = AxisCut( center,
			FiniteNumber( saved.xmin, center.x ), 0, 0, true )
	end
	if saved.xmax_on and #cuts < MAX_CUTS then
		cuts[ #cuts + 1 ] = AxisCut( center,
			FiniteNumber( saved.xmax, center.x ), 0, 0, false )
	end
	if saved.ymin_on and #cuts < MAX_CUTS then
		cuts[ #cuts + 1 ] = AxisCut( center,
			FiniteNumber( saved.ymin, center.y ), 0, 90, true )
	end
	if saved.ymax_on and #cuts < MAX_CUTS then
		cuts[ #cuts + 1 ] = AxisCut( center,
			FiniteNumber( saved.ymax, center.y ), 0, 90, false )
	end
	if saved.zmin_on and #cuts < MAX_CUTS then
		cuts[ #cuts + 1 ] = AxisCut( center,
			FiniteNumber( saved.zmin, center.z ), -90, 0, true )
	end
	if saved.zmax_on and #cuts < MAX_CUTS then
		cuts[ #cuts + 1 ] = AxisCut( center,
			FiniteNumber( saved.zmax, center.z ), -90, 0, false )
	end
	return cuts
end

local function SyncCutOrigin( cut, center )
	if not cut then return end
	local normal = CutAngle( cut ):Forward()
	cut.offset = FiniteNumber( cut.offset, 0 )
	cut.ox = center.x + normal.x * cut.offset
	cut.oy = center.y + normal.y * cut.offset
	cut.oz = center.z + normal.z * cut.offset
end

local function SendCuts( entity, group, option, geometryIdentity, cuts, callback )
	if not IsValid( entity ) then return end
	local requestId = AllocateApplyRequest( callback )
	if not requestId then return end
	local count = math.min( #cuts, MAX_CUTS )
	net.Start( "advanced_bodygroup_tool_set_vertex_cuts" )
		net.WriteEntity( entity )
		net.WriteUInt( group, 8 )
		net.WriteUInt( requestId, 16 )
		net.WriteUInt( option, 8 )
		net.WriteString( string.lower( tostring( geometryIdentity or "" ) ) )
		net.WriteUInt( count, 5 )
		for index = 1, count do
			local cut = cuts[ index ]
			net.WriteBool( cut.enabled ~= false )
			net.WriteBool( cut.keep_positive ~= false )
			net.WriteFloat( FiniteNumber( cut.ox, 0 ) )
			net.WriteFloat( FiniteNumber( cut.oy, 0 ) )
			net.WriteFloat( FiniteNumber( cut.oz, 0 ) )
			net.WriteFloat( FiniteNumber( cut.pitch, 0 ) )
			net.WriteFloat( FiniteNumber( cut.yaw, 0 ) )
			net.WriteFloat( FiniteNumber( cut.roll, 0 ) )
		end
	net.SendToServer()
	return requestId
end

local function CountStoredCutsExcept( entity, excludedGroup )
	local total = 0
	for rawGroup, entry in pairs( ABT.GetVertexKeepBounds( entity ) or {} ) do
		if tonumber( rawGroup ) ~= excludedGroup and istable( entry ) then
			total = total + ( istable( entry.cuts ) and #entry.cuts or 1 )
		end
	end
	return total
end

local function SetFixedColumnWidth( column, width )
	if not IsValid( column ) then return end
	if column.SetFixedWidth then column:SetFixedWidth( width ) else column:SetWide( width ) end
end

function ABT.OpenVertexKeepEditor( entity, group, displayName )
	if not IsValid( entity ) then return end
	group = math.floor( tonumber( group ) or -1 )
	local data, errorMessage = ABT.GetBodygroupVertexData( entity, group )
	if not data then
		Derma_Message( T( "vertex.failure", "Could not prepare the cut editor: {error}", {
			error = errorMessage,
		} ), T( "vertex.editor_short", "Bodygroup cut editor" ), L( "common.ok" ) )
		return
	end

	local option = entity:GetBodygroup( group ) or 0
	local geometryIdentity = data.identity
	local saved = ABT.GetVertexKeepBounds( entity )[ group ]
	if saved and tonumber( saved.option ) ~= option then saved = nil end

	local center = ( data.minimum + data.maximum ) * 0.5
	local extent = data.maximum - data.minimum
	local longestExtent = math.max( extent.x, extent.y, extent.z )
	local diagonal = math.max( extent:Length(), 1 )
	local offsetLimit = math.max( diagonal * 0.75, 1 )
	local planeSize = math.max( diagonal * 0.62, 2 )
	local arrowLength = math.max( diagonal * 0.22, 1 )
	local cuts = CopySavedCuts( saved, center )
	local preview = BuildPreview( data, option, cuts )
	local selectedIndex = #cuts > 0 and 1 or nil
	local rebuildGeneration = 0
	local nextPreviewError = 0
	local suppressUI = false
	local refreshingList = false
	local angleSnap = 5
	local applying = false
	local pendingApplyRequest
	local function CurrentCutLimit()
		if not IsValid( entity ) then return 0 end
		return math.Clamp( MAX_TOTAL_CUTS
			- CountStoredCutsExcept( entity, group ), 0, MAX_CUTS )
	end

	local frame = vgui.Create( "DFrame" )
	frame:SetTitle( T( "vertex.editor_title", "Cut editor — {name}", {
		name = tostring( displayName or L( "bodygroup.fallback", { id = group } ) ),
	} ) )
	frame:SetSize( math.min( ScrW() - 30, 1120 ), math.min( ScrH() - 40, 740 ) )
	frame:SetMinWidth( 820 )
	frame:SetMinHeight( 580 )
	frame:SetSizable( true )
	frame:Center()
	frame:MakePopup()
	frame:SetDeleteOnClose( true )
	frame.OnClose = function()
		if pendingApplyRequest then
			ABT.VertexCutApplyRequests[ pendingApplyRequest ] = nil
			pendingApplyRequest = nil
		end
		rebuildGeneration = rebuildGeneration + 1
		DestroyPreview( preview )
		preview = nil
	end

	local right = vgui.Create( "DPanel", frame )
	right:Dock( RIGHT )
	right:SetWide( math.min( 430, math.floor( frame:GetWide() * 0.42 ) ) )
	right:DockMargin( 0, 5, 5, 5 )
	right.Paint = function( _, width, height )
		surface.SetDrawColor( 43, 47, 53, 255 )
		surface.DrawRect( 0, 0, width, height )
	end

	local left = vgui.Create( "DPanel", frame )
	left:Dock( FILL )
	left:DockMargin( 5, 5, 5, 5 )

	local previewPanel = vgui.Create( "DPanel", left )
	previewPanel:Dock( FILL )
	local cameraDistance = math.max( longestExtent * 1.8, diagonal * 0.85, 4 )
	local cameraYaw, cameraPitch = 35, 18
	local dragging, dragButton, lastMouseX, lastMouseY = false, nil, 0, 0
	local cutHandles = {}
	local offsetDragging = nil
	local ViewportSelectCut, ViewportSetOffset

	local function CameraPosition()
		local yaw, pitch = math.rad( cameraYaw ), math.rad( cameraPitch )
		return center + Vector(
			math.cos( pitch ) * math.cos( yaw ) * cameraDistance,
			math.cos( pitch ) * math.sin( yaw ) * cameraDistance,
			math.sin( pitch ) * cameraDistance )
	end

	previewPanel.OnMousePressed = function( self, code )
		if applying then return end
		if code ~= MOUSE_LEFT and code ~= MOUSE_MIDDLE then return end
		local cursorX, cursorY = self:CursorPos()
		if code == MOUSE_LEFT then
			local selectedHandle = selectedIndex and cutHandles[ selectedIndex ] or nil
			if selectedHandle and selectedHandle.visible then
				local tipDistance = ( cursorX - selectedHandle.tipX ) ^ 2
					+ ( cursorY - selectedHandle.tipY ) ^ 2
				if tipDistance <= 15 ^ 2 then
					if ViewportSelectCut then ViewportSelectCut( selectedIndex ) end
					local mouseX, mouseY = gui.MousePos()
					offsetDragging = {
						index = selectedIndex,
						mouseX = mouseX, mouseY = mouseY,
						startOffset = cuts[ selectedIndex ].offset,
						axisX = selectedHandle.axisX,
						axisY = selectedHandle.axisY,
						unitsPerPixel = selectedHandle.unitsPerPixel,
						sign = cuts[ selectedIndex ].keep_positive ~= false and 1 or -1,
					}
					self:MouseCapture( true )
					return
				end
			end
			for index = #cuts, 1, -1 do
				local handle = cutHandles[ index ]
				if handle and handle.visible then
					local badgeDistance = ( cursorX - handle.originX ) ^ 2
						+ ( cursorY - handle.originY ) ^ 2
					if badgeDistance <= 16 ^ 2 then
						if ViewportSelectCut then ViewportSelectCut( index ) end
						return
					end
				end
			end
		end
		dragging, dragButton = true, code
		lastMouseX, lastMouseY = gui.MousePos()
		self:MouseCapture( true )
	end
	previewPanel.OnMouseReleased = function( self, code )
		if offsetDragging and code == MOUSE_LEFT then
			offsetDragging = nil
			self:MouseCapture( false )
			return
		end
		if not dragging or code ~= dragButton then return end
		dragging, dragButton = false, nil
		self:MouseCapture( false )
	end
	previewPanel.OnMouseCaptureLost = function()
		dragging, dragButton, offsetDragging = false, nil, nil
	end
	previewPanel.OnCursorMoved = function()
		if offsetDragging then
			local mouseX, mouseY = gui.MousePos()
			local deltaPixels = ( mouseX - offsetDragging.mouseX )
				* offsetDragging.axisX + ( mouseY - offsetDragging.mouseY )
				* offsetDragging.axisY
			local value = offsetDragging.startOffset + deltaPixels
				* offsetDragging.unitsPerPixel * offsetDragging.sign
			if ViewportSetOffset then
				ViewportSetOffset( offsetDragging.index, value )
			end
			return
		end
		if not dragging then return end
		local mouseX, mouseY = gui.MousePos()
		cameraYaw = cameraYaw - ( mouseX - lastMouseX ) * 0.45
		cameraPitch = math.Clamp( cameraPitch + ( mouseY - lastMouseY ) * 0.45,
			-89, 89 )
		lastMouseX, lastMouseY = mouseX, mouseY
	end
	previewPanel.OnMouseWheeled = function( _, delta )
		if applying then return true end
		cameraDistance = math.Clamp( cameraDistance - delta * cameraDistance * 0.1,
			math.max( longestExtent * 0.08, 0.5 ), 100000 )
		return true
	end

	local function DrawCutPlane( cut, index )
		local angle = CutAngle( cut )
		local normal, rightVector, upVector = angle:Forward(), angle:Right(), angle:Up()
		local origin = Vector( cut.ox, cut.oy, cut.oz )
		local selected = index == selectedIndex
		local enabled = cut.enabled ~= false
		local lineColor, fillColor
		if not enabled then
			lineColor, fillColor = Color( 135, 140, 148, selected and 150 or 75 ),
				Color( 100, 105, 112, selected and 12 or 5 )
		elseif selected then
			lineColor, fillColor = Color( 255, 169, 45, 235 ), Color( 255, 138, 22, 17 )
		else
			lineColor, fillColor = Color( 67, 211, 231, 145 ), Color( 47, 187, 210, 7 )
		end

		local cornerA = origin - rightVector * planeSize - upVector * planeSize
		local cornerB = origin + rightVector * planeSize - upVector * planeSize
		local cornerC = origin + rightVector * planeSize + upVector * planeSize
		local cornerD = origin - rightVector * planeSize + upVector * planeSize
		render.SetMaterial( PREVIEW_PLANE_MATERIAL )
		render.DrawQuad( cornerA, cornerB, cornerC, cornerD, fillColor )

		local divisions = selected and 10 or 6
		for gridIndex = -divisions, divisions do
			local fraction = gridIndex / divisions
			local alongRight = rightVector * ( fraction * planeSize )
			local alongUp = upVector * ( fraction * planeSize )
			render.DrawLine( origin + alongRight - upVector * planeSize,
				origin + alongRight + upVector * planeSize, lineColor, true )
			render.DrawLine( origin + alongUp - rightVector * planeSize,
				origin + alongUp + rightVector * planeSize, lineColor, true )
		end

		local direction = cut.keep_positive ~= false and normal or -normal
		local tip = origin + direction * arrowLength
		local arrowColor = selected and Color( 255, 196, 70, 255 ) or lineColor
		render.DrawLine( origin, tip, arrowColor, true )
		local headBack = tip - direction * ( arrowLength * 0.26 )
		local headWidth = arrowLength * 0.12
		render.DrawLine( tip, headBack + rightVector * headWidth, arrowColor, true )
		render.DrawLine( tip, headBack - rightVector * headWidth, arrowColor, true )
		render.DrawLine( tip, headBack + upVector * headWidth, arrowColor, true )
		render.DrawLine( tip, headBack - upVector * headWidth, arrowColor, true )
		render.DrawWireframeSphere( origin, math.max( arrowLength * 0.045, 0.08 ),
			8, 6, arrowColor, true )
	end

	previewPanel.Paint = function( self, width, height )
		surface.SetDrawColor( 22, 25, 30, 255 )
		surface.DrawRect( 0, 0, width, height )
		local screenX, screenY = self:LocalToScreen( 0, 0 )
		local cameraPosition = CameraPosition()
		local cameraAngle = ( center - cameraPosition ):Angle()
		cutHandles = {}
		-- Vector:ToScreen is inaccurate inside a non-default Start3D viewport.
		-- Invert util.AimVector's exact pixel rays instead, so the 2D handles stay
		-- aligned with the custom viewport at every panel size and aspect ratio.
		local halfWidth, halfHeight = width * 0.5, height * 0.5
		local viewForward, viewRight, viewUp = cameraAngle:Forward(),
			cameraAngle:Right(), cameraAngle:Up()
		local rightRay = util.AimVector( cameraAngle, PREVIEW_FOV,
			halfWidth + 1, halfHeight, width, height )
		local downRay = util.AimVector( cameraAngle, PREVIEW_FOV,
			halfWidth, halfHeight + 1, width, height )
		local rightDepth = rightRay:Dot( viewForward )
		local downDepth = downRay:Dot( viewForward )
		local rightPerPixel = math.abs( rightDepth ) > 0.0000001
			and rightRay:Dot( viewRight ) / rightDepth or 0
		local upPerPixel = math.abs( downDepth ) > 0.0000001
			and downRay:Dot( viewUp ) / downDepth or 0
		local function ProjectToPanel( position )
			local relative = position - cameraPosition
			local depth = relative:Dot( viewForward )
			if depth <= 0.0001 or math.abs( rightPerPixel ) < 0.000000001
			or math.abs( upPerPixel ) < 0.000000001 then return 0, 0, false end
			local localX = halfWidth
				+ relative:Dot( viewRight ) / depth / rightPerPixel
			local localY = halfHeight
				+ relative:Dot( viewUp ) / depth / upPerPixel
			return localX, localY, FiniteNumber( localX ) ~= nil
				and FiniteNumber( localY ) ~= nil
		end
		cam.Start3D( cameraPosition, cameraAngle, PREVIEW_FOV,
			screenX, screenY, width, height, 0.1, math.max( cameraDistance * 10, 1000 ) )
		local renderOK, renderError = pcall( function()
			render.SuppressEngineLighting( true )
			render.CullMode( MATERIAL_CULLMODE_NONE )

			-- A small world-axis tripod keeps rotations readable, like a DCC viewport.
			local axisSize = math.max( diagonal * 0.12, 0.5 )
			render.DrawLine( center, center + Vector( axisSize, 0, 0 ),
				Color( 232, 78, 78 ), true )
			render.DrawLine( center, center + Vector( 0, axisSize, 0 ),
				Color( 84, 210, 112 ), true )
			render.DrawLine( center, center + Vector( 0, 0, axisSize ),
				Color( 78, 137, 242 ), true )

			-- Colors and alpha are embedded in the preview vertices. The built-in
			-- color material consumes both channels consistently for static IMeshes.
			render.SetColorModulation( 1, 1, 1 )
			render.SetBlend( 1 )
			render.SetColorMaterial()
			for _, meshObject in ipairs( preview and preview.removed or {} ) do
				meshObject:Draw()
			end
			for _, meshObject in ipairs( preview and preview.kept or {} ) do
				meshObject:Draw()
			end

			render.SetBlend( 1 )
			render.SetColorModulation( 1, 1, 1 )
			cam.IgnoreZ( true )
			for index, cut in ipairs( cuts ) do DrawCutPlane( cut, index ) end
			cam.IgnoreZ( false )

			for index, cut in ipairs( cuts ) do
				local angle = CutAngle( cut )
				local direction = cut.keep_positive ~= false
					and angle:Forward() or -angle:Forward()
				local origin = Vector( cut.ox, cut.oy, cut.oz )
				local originX, originY, originVisible = ProjectToPanel( origin )
				local tipX, tipY, tipVisible = ProjectToPanel(
					origin + direction * arrowLength )
				local axisX, axisY = tipX - originX, tipY - originY
				local axisPixels = math.sqrt( axisX * axisX + axisY * axisY )
				if axisPixels < 34 then
					-- An end-on normal has no useful projected drag direction, so expose
					-- a short screen-space handle while preserving the 3D arrow itself.
					axisX, axisY, axisPixels = 0, -42, 42
					tipX, tipY = originX, originY - 42
				end
				cutHandles[ index ] = {
					originX = originX, originY = originY,
					tipX = tipX, tipY = tipY,
					axisX = axisX / axisPixels, axisY = axisY / axisPixels,
					unitsPerPixel = arrowLength / axisPixels,
					visible = originVisible and tipVisible
						and originX > -24 and originX < width + 24
						and originY > -24 and originY < height + 24,
				}
			end
		end )
		cam.IgnoreZ( false )
		render.SetBlend( 1 )
		render.SetColorModulation( 1, 1, 1 )
		render.CullMode( MATERIAL_CULLMODE_CCW )
		render.SuppressEngineLighting( false )
		cam.End3D()
		if not renderOK and CurTime() >= nextPreviewError then
			nextPreviewError = CurTime() + 2
			ErrorNoHalt( "[Advanced Bodygroup Tool] Vertex cut preview failed: "
				.. tostring( renderError ) .. "\n" )
		end

		-- Plane badges are both an outliner-in-viewport and direct selection handles.
		draw.NoTexture()
		for index, handle in ipairs( cutHandles ) do
			if handle.visible then
				local cut = cuts[ index ]
				local selected = index == selectedIndex
				local badgeColor = cut.enabled == false and Color( 105, 110, 118, 225 )
					or selected and Color( 242, 146, 35, 245 )
					or Color( 42, 174, 199, 225 )
				if selected then
					surface.SetDrawColor( 255, 185, 61, 230 )
					surface.DrawLine( handle.originX, handle.originY,
						handle.tipX, handle.tipY )
					surface.DrawPoly( {
						{ x = handle.tipX, y = handle.tipY - 7 },
						{ x = handle.tipX + 7, y = handle.tipY },
						{ x = handle.tipX, y = handle.tipY + 7 },
						{ x = handle.tipX - 7, y = handle.tipY },
					} )
				end
				draw.RoundedBox( 10, handle.originX - 11, handle.originY - 11,
					22, 22, badgeColor )
				draw.SimpleText( tostring( index ), "DermaDefaultBold",
					handle.originX, handle.originY, color_white,
					TEXT_ALIGN_CENTER, TEXT_ALIGN_CENTER )
			end
		end

		local keptCount = preview and preview.keptCount or 0
		local removedCount = preview and preview.removedCount or 0
		draw.RoundedBox( 4, 10, 10, math.max( width - 20, 80 ), 68,
			Color( 9, 11, 15, 216 ) )
		draw.DrawText( T( "vertex.preview_help",
			"Orbit: drag empty space · Zoom: wheel\nMove plane: drag orange arrow" ),
			"DermaDefault", 18, 18, Color( 225, 232, 238 ), TEXT_ALIGN_LEFT )
		draw.SimpleText( T( "vertex.preview_count", "Kept {kept} / {total} triangles", {
			kept = keptCount, total = keptCount + removedCount,
		} ), "DermaDefaultBold", 18, 55, Color( 89, 221, 235 ),
			TEXT_ALIGN_LEFT, TEXT_ALIGN_TOP )

		local keptText = T( "vertex.kept", "Kept" )
		local removedText = T( "vertex.removed", "Removed" )
		surface.SetFont( "DermaDefault" )
		local keptWidth = surface.GetTextSize( keptText )
		local removedWidth = surface.GetTextSize( removedText )
		local removedX = 47 + keptWidth
		local legendWidth = removedX + 15 + removedWidth + 10
		local legendY = height - 28
		draw.RoundedBox( 3, 10, legendY - 4, legendWidth, 22,
			Color( 9, 11, 15, 190 ) )
		surface.SetDrawColor( 49, 199, 229, 255 )
		surface.DrawRect( 17, legendY + 2, 10, 10 )
		draw.SimpleText( keptText, "DermaDefault", 32,
			legendY, Color( 220, 226, 232 ) )
		surface.SetDrawColor( 235, 67, 55, 255 )
		surface.DrawRect( removedX, legendY + 2, 10, 10 )
		draw.SimpleText( removedText, "DermaDefault", removedX + 15,
			legendY, Color( 220, 226, 232 ) )
	end

	local function ScheduleRebuild()
		rebuildGeneration = rebuildGeneration + 1
		local generation = rebuildGeneration
		timer.Simple( PREVIEW_REBUILD_DELAY, function()
			if not IsValid( frame ) or generation ~= rebuildGeneration then return end
			local replacement = BuildPreview( data, option, cuts )
			DestroyPreview( preview )
			preview = replacement
		end )
	end

	-- Bottom actions are deliberately separate from editing: only Apply writes state.
	local actions = vgui.Create( "DPanel", right )
	actions:Dock( BOTTOM )
	actions:SetTall( 116 )
	actions:SetPaintBackground( false )

	local apply = vgui.Create( "DButton", actions )
	apply:SetText( T( "vertex.apply", "Apply cuts" ) )
	local clear = vgui.Create( "DButton", actions )
	clear:SetText( T( "vertex.clear", "Clear cuts" ) )
	clear:SetTooltip( T( "vertex.clear_tooltip",
		"Remove every draft cut. Use Apply to save the change." ) )
	local cancel = vgui.Create( "DButton", actions )
	cancel:SetText( L( "common.cancel" ) )
	local applyHint = vgui.Create( "DLabel", actions )
	applyHint:SetPos( 7, 78 )
	applyHint:SetTall( 32 )
	applyHint:SetWrap( true )
	applyHint:SetTextColor( Color( 190, 196, 203 ) )
	applyHint:SetText( T( "vertex.local_draft", "Changes stay local until you click Apply." ) )
	actions.PerformLayout = function( _, width )
		local gap = 5
		apply:SetPos( gap, 7 )
		apply:SetSize( width - gap * 2, 30 )
		local half = math.floor( ( width - gap * 3 ) / 2 )
		clear:SetPos( gap, 42 )
		clear:SetSize( half, 30 )
		cancel:SetPos( gap * 2 + half, 42 )
		cancel:SetSize( width - ( gap * 3 + half ), 30 )
		applyHint:SetWide( width - 14 )
	end

	local help = vgui.Create( "DLabel", right )
	help:Dock( TOP )
	help:DockMargin( 8, 6, 8, 5 )
	help:SetTall( 48 )
	help:SetWrap( true )
	help:SetTextColor( Color( 222, 227, 232 ) )
	help:SetText( T( "vertex.multicut_help",
		"Stack cut planes to keep their shared area. Select a cut, then edit its transform and kept side." ) )

	local collectionHeader = vgui.Create( "DLabel", right )
	collectionHeader:Dock( TOP )
	collectionHeader:DockMargin( 8, 1, 8, 2 )
	collectionHeader:SetTall( 22 )
	collectionHeader:SetFont( "DermaDefaultBold" )
	collectionHeader:SetTextColor( Color( 238, 241, 244 ) )
	collectionHeader:SetText( T( "vertex.collection", "CUT COLLECTION" ) )

	local cutList = vgui.Create( "DListView", right )
	cutList:Dock( TOP )
	cutList:DockMargin( 7, 0, 7, 4 )
	cutList:SetTall( 166 )
	cutList:SetMultiSelect( false )
	SetFixedColumnWidth( cutList:AddColumn( "#" ), 32 )
	SetFixedColumnWidth( cutList:AddColumn( T( "vertex.state", "State" ) ), 64 )
	local sideColumn = cutList:AddColumn( T( "vertex.keep_side_short", "Side" ) )
	SetFixedColumnWidth( sideColumn, 70 )
	if sideColumn.SetTooltip then
		sideColumn:SetTooltip( T( "vertex.keep_side", "Kept side" ) )
	end
	cutList:AddColumn( T( "vertex.rotation", "Rotation" ) )
	local offsetColumn = cutList:AddColumn( T( "vertex.offset_short", "Offset" ) )
	SetFixedColumnWidth( offsetColumn, 70 )
	if offsetColumn.SetTooltip then
		offsetColumn:SetTooltip( T( "vertex.offset", "Offset along normal" ) )
	end

	local toolbar = vgui.Create( "DPanel", right )
	toolbar:Dock( TOP )
	toolbar:DockMargin( 7, 0, 7, 5 )
	toolbar:SetTall( 63 )
	toolbar:SetPaintBackground( false )
	local addCut = vgui.Create( "DButton", toolbar )
	addCut:SetText( T( "vertex.add_cut", "Add" ) )
	local duplicateCut = vgui.Create( "DButton", toolbar )
	duplicateCut:SetText( T( "vertex.duplicate_cut", "Duplicate" ) )
	local removeCut = vgui.Create( "DButton", toolbar )
	removeCut:SetText( T( "vertex.remove_cut", "Remove" ) )
	local moveUp = vgui.Create( "DButton", toolbar )
	moveUp:SetText( T( "vertex.move_up", "Up" ) )
	local moveDown = vgui.Create( "DButton", toolbar )
	moveDown:SetText( T( "vertex.move_down", "Down" ) )
	local toolbarButtons = { addCut, duplicateCut, removeCut, moveUp, moveDown }
	for _, button in ipairs( toolbarButtons ) do
		button:SetTooltip( button:GetText() )
	end
	toolbar.PerformLayout = function( _, width )
		local gap = 3
		local third = math.floor( ( width - gap * 2 ) / 3 )
		addCut:SetPos( 0, 0 )
		addCut:SetSize( third, 30 )
		duplicateCut:SetPos( third + gap, 0 )
		duplicateCut:SetSize( third, 30 )
		removeCut:SetPos( ( third + gap ) * 2, 0 )
		removeCut:SetSize( width - ( third + gap ) * 2, 30 )
		local half = math.floor( ( width - gap ) / 2 )
		moveUp:SetPos( 0, 33 )
		moveUp:SetSize( half, 30 )
		moveDown:SetPos( half + gap, 33 )
		moveDown:SetSize( width - half - gap, 30 )
	end

	local inspectorHeader = vgui.Create( "DLabel", right )
	inspectorHeader:Dock( TOP )
	inspectorHeader:DockMargin( 8, 1, 8, 2 )
	inspectorHeader:SetTall( 22 )
	inspectorHeader:SetFont( "DermaDefaultBold" )
	inspectorHeader:SetTextColor( Color( 238, 241, 244 ) )
	inspectorHeader:SetText( T( "vertex.transform", "TRANSFORM / PLANE" ) )

	local inspector = vgui.Create( "DScrollPanel", right )
	inspector:Dock( FILL )
	inspector:DockMargin( 7, 0, 7, 4 )

	local selectedLabel = vgui.Create( "DLabel", inspector )
	selectedLabel:Dock( TOP )
	selectedLabel:DockMargin( 3, 2, 3, 2 )
	selectedLabel:SetTall( 22 )
	selectedLabel:SetFont( "DermaDefaultBold" )
	selectedLabel:SetDark( false )

	local enabledCheck = vgui.Create( "DCheckBoxLabel", inspector )
	enabledCheck:Dock( TOP )
	enabledCheck:DockMargin( 3, 1, 3, 2 )
	enabledCheck:SetTall( 22 )
	enabledCheck:SetDark( false )
	enabledCheck:SetText( T( "vertex.cut_enabled", "Enabled" ) )

	local sideRow = vgui.Create( "DPanel", inspector )
	sideRow:Dock( TOP )
	sideRow:DockMargin( 2, 2, 2, 3 )
	sideRow:SetTall( 54 )
	sideRow:SetPaintBackground( false )
	local sideLabel = vgui.Create( "DLabel", sideRow )
	sideLabel:SetDark( false )
	sideLabel:SetText( T( "vertex.keep_side", "Keep side" ) )
	local sideCombo = vgui.Create( "DComboBox", sideRow )
	sideCombo:SetSortItems( false )
	sideCombo:AddChoice( T( "vertex.keep_positive", "Positive / arrow side" ), true )
	sideCombo:AddChoice( T( "vertex.keep_negative", "Negative / opposite side" ), false )
	local flipSide = vgui.Create( "DButton", sideRow )
	flipSide:SetText( T( "vertex.flip_side", "Flip" ) )
	sideRow.PerformLayout = function( _, width )
		sideLabel:SetPos( 2, 0 )
		sideLabel:SetSize( width - 4, 20 )
		surface.SetFont( "DermaDefault" )
		local flipWidth = math.Clamp( surface.GetTextSize(
			flipSide:GetText() ) + 24, 82, math.floor( width * 0.42 ) )
		flipSide:SetSize( flipWidth, 30 )
		flipSide:SetPos( width - flipWidth, 23 )
		sideCombo:SetPos( 0, 23 )
		sideCombo:SetSize( math.max( width - flipWidth - 5, 60 ), 30 )
	end

	local offsetSlider = vgui.Create( "DNumSlider", inspector )
	offsetSlider:Dock( TOP )
	offsetSlider:DockMargin( 1, 1, 1, 0 )
	offsetSlider:SetTall( 42 )
	offsetSlider:SetText( T( "vertex.offset", "Offset" ) )
	offsetSlider:SetMin( -offsetLimit )
	offsetSlider:SetMax( offsetLimit )
	offsetSlider:SetDecimals( 3 )
	offsetSlider:SetDark( false )
	offsetSlider:SetTooltip( T( "vertex.offset_tooltip",
		"Move the plane along its normal without changing its angle." ) )

	local rotationLabel = vgui.Create( "DLabel", inspector )
	rotationLabel:Dock( TOP )
	rotationLabel:DockMargin( 3, 7, 3, 0 )
	rotationLabel:SetTall( 18 )
	rotationLabel:SetFont( "DermaDefaultBold" )
	rotationLabel:SetDark( false )
	rotationLabel:SetText( T( "vertex.rotation", "Rotation" ) )

	local pitchSlider = vgui.Create( "DNumSlider", inspector )
	pitchSlider:Dock( TOP )
	pitchSlider:SetTall( 38 )
	pitchSlider:SetText( T( "vertex.pitch", "Pitch" ) )
	pitchSlider:SetMin( -180 )
	pitchSlider:SetMax( 180 )
	pitchSlider:SetDecimals( 1 )
	pitchSlider:SetDark( false )
	local yawSlider = vgui.Create( "DNumSlider", inspector )
	yawSlider:Dock( TOP )
	yawSlider:SetTall( 38 )
	yawSlider:SetText( T( "vertex.yaw", "Yaw" ) )
	yawSlider:SetMin( -180 )
	yawSlider:SetMax( 180 )
	yawSlider:SetDecimals( 1 )
	yawSlider:SetDark( false )
	local rollSlider = vgui.Create( "DNumSlider", inspector )
	rollSlider:Dock( TOP )
	rollSlider:SetTall( 38 )
	rollSlider:SetText( T( "vertex.roll", "Roll" ) )
	rollSlider:SetMin( -180 )
	rollSlider:SetMax( 180 )
	rollSlider:SetDecimals( 1 )
	rollSlider:SetDark( false )
	rollSlider:SetTooltip( T( "vertex.roll_tooltip",
		"Roll rotates the plane grid; pitch and yaw set the cutting direction." ) )

	local snapRow = vgui.Create( "DPanel", inspector )
	snapRow:Dock( TOP )
	snapRow:DockMargin( 2, 4, 2, 2 )
	snapRow:SetTall( 28 )
	snapRow:SetPaintBackground( false )
	local snapLabel = vgui.Create( "DLabel", snapRow )
	snapLabel:SetDark( false )
	snapLabel:SetText( T( "vertex.angle_snap", "Angle snap" ) )
	local snapCombo = vgui.Create( "DComboBox", snapRow )
	snapCombo:SetSortItems( false )
	snapCombo:AddChoice( T( "vertex.snap_off", "Off" ), 0 )
	snapCombo:AddChoice( "1°", 1 )
	snapCombo:AddChoice( "5°", 5 )
	snapCombo:AddChoice( "15°", 15 )
	snapCombo:AddChoice( "45°", 45 )
	snapRow.PerformLayout = function( _, width, height )
		snapLabel:SetPos( 2, 4 )
		snapLabel:SetSize( 100, height - 4 )
		snapCombo:SetPos( 104, 0 )
		snapCombo:SetSize( math.max( width - 104, 30 ), height )
	end

	local presetLabel = vgui.Create( "DLabel", inspector )
	presetLabel:Dock( TOP )
	presetLabel:DockMargin( 3, 7, 3, 1 )
	presetLabel:SetTall( 18 )
	presetLabel:SetFont( "DermaDefaultBold" )
	presetLabel:SetDark( false )
	presetLabel:SetText( T( "vertex.axis_presets", "Axis presets" ) )

	local presetPanel = vgui.Create( "DPanel", inspector )
	presetPanel:Dock( TOP )
	presetPanel:DockMargin( 2, 1, 2, 2 )
	presetPanel:SetTall( 30 )
	presetPanel:SetPaintBackground( false )
	local presets = {
		{ "+X", 0, 0, 0 }, { "-X", 0, 180, 0 },
		{ "+Y", 0, 90, 0 }, { "-Y", 0, -90, 0 },
		{ "+Z", -90, 0, 0 }, { "-Z", 90, 0, 0 },
	}
	local presetButtons = {}
	for index, preset in ipairs( presets ) do
		local button = vgui.Create( "DButton", presetPanel )
		button:SetText( preset[ 1 ] )
		presetButtons[ index ] = button
	end
	presetPanel.PerformLayout = function( _, width, height )
		local gap = 3
		local buttonWidth = math.floor( ( width - gap * 5 ) / 6 )
		for index, button in ipairs( presetButtons ) do
			button:SetPos( ( index - 1 ) * ( buttonWidth + gap ), 0 )
			button:SetSize( index == 6 and width - ( index - 1 )
				* ( buttonWidth + gap ) or buttonWidth, height )
		end
	end

	local alignView = vgui.Create( "DButton", inspector )
	alignView:Dock( TOP )
	alignView:DockMargin( 2, 2, 2, 4 )
	alignView:SetTall( 30 )
	alignView:SetText( T( "vertex.align_view", "Align plane to view" ) )
	alignView:SetTooltip( T( "vertex.align_view_tooltip",
		"Point the selected plane's positive normal toward the current camera." ) )

	local inspectorHelp = vgui.Create( "DLabel", inspector )
	inspectorHelp:Dock( TOP )
	inspectorHelp:DockMargin( 3, 4, 3, 8 )
	inspectorHelp:SetTall( 44 )
	inspectorHelp:SetWrap( true )
	inspectorHelp:SetDark( false )
	inspectorHelp:SetText( T( "vertex.triangle_note",
		"Cuts operate on whole triangles. Multiple enabled planes keep only their shared side." ) )

	local cutRows = {}
	local UpdateInspector

	local function SelectedCut()
		return selectedIndex and cuts[ selectedIndex ] or nil
	end

	local function RotationSummary( cut )
		return string.format( "%.1f / %.1f / %.1f",
			FiniteNumber( cut.pitch, 0 ), FiniteNumber( cut.yaw, 0 ),
			FiniteNumber( cut.roll, 0 ) )
	end

	local function UpdateRow( index )
		local row, cut = cutRows[ index ], cuts[ index ]
		if not IsValid( row ) or not cut then return end
		row:SetColumnText( 1, tostring( index ) )
		row:SetColumnText( 2, cut.enabled ~= false
			and T( "vertex.cut_enabled_short", "On" )
			or T( "vertex.cut_disabled_short", "Off" ) )
		row:SetColumnText( 3, cut.keep_positive ~= false
			and T( "vertex.keep_positive_short", "+ / arrow" )
			or T( "vertex.keep_negative_short", "- / opposite" ) )
		row:SetColumnText( 4, RotationSummary( cut ) )
		row:SetColumnText( 5, string.format( "%.2f", FiniteNumber( cut.offset, 0 ) ) )
	end

	local function RefreshList( requestedIndex )
		refreshingList = true
		cutList:Clear()
		cutRows = {}
		collectionHeader:SetText( T( "vertex.collection", "Cut Collection" )
			.. "  ·  " .. T( "vertex.cut_count", "{count} cut planes", {
				count = #cuts,
			} ) )
		for index, cut in ipairs( cuts ) do
			local row = cutList:AddLine( index, "", "", "", "" )
			row.CutIndex = index
			cutRows[ index ] = row
			UpdateRow( index )
		end
		if #cuts == 0 then
			selectedIndex = nil
		else
			selectedIndex = math.Clamp( math.floor( tonumber( requestedIndex ) or 1 ),
				1, #cuts )
			cutList:SelectItem( cutRows[ selectedIndex ] )
		end
		refreshingList = false
		UpdateInspector()
	end

	local transformControls = {
		enabledCheck, sideCombo, flipSide, offsetSlider, pitchSlider, yawSlider,
		rollSlider, snapCombo, alignView,
	}
	for _, button in ipairs( presetButtons ) do
		transformControls[ #transformControls + 1 ] = button
	end

	local function SetApplying( value )
		applying = value == true
		apply:SetText( applying
			and T( "vertex.applying", "Applying…" )
			or T( "vertex.apply", "Apply cuts" ) )
		apply:SetEnabled( not applying )
		clear:SetEnabled( not applying )
		cancel:SetEnabled( not applying )
		cutList:SetEnabled( not applying )
		if UpdateInspector then UpdateInspector() end
	end

	UpdateInspector = function()
		local cut = SelectedCut()
		local canEdit = not applying
		local hasSelection = cut ~= nil and canEdit
		local cutLimit = CurrentCutLimit()
		suppressUI = true
		selectedLabel:SetText( cut ~= nil
			and T( "vertex.cut_name", "Cut {id}", { id = selectedIndex } )
			or T( "vertex.selected_none", "No cut selected" ) )
		for _, control in ipairs( transformControls ) do control:SetEnabled( hasSelection ) end
		removeCut:SetEnabled( hasSelection )
		duplicateCut:SetEnabled( hasSelection and #cuts < cutLimit )
		moveUp:SetEnabled( hasSelection and selectedIndex > 1 )
		moveDown:SetEnabled( hasSelection and selectedIndex < #cuts )
		addCut:SetEnabled( canEdit and #cuts < cutLimit )
		if cut then
			enabledCheck:SetValue( cut.enabled ~= false and 1 or 0 )
			sideCombo:ChooseOptionID( cut.keep_positive ~= false and 1 or 2 )
			offsetSlider:SetValue( FiniteNumber( cut.offset, 0 ) )
			pitchSlider:SetValue( FiniteNumber( cut.pitch, 0 ) )
			yawSlider:SetValue( FiniteNumber( cut.yaw, 0 ) )
			rollSlider:SetValue( FiniteNumber( cut.roll, 0 ) )
		end
		suppressUI = false
	end

	local function ChangedSelectedCut( refreshInspector )
		local cut = SelectedCut()
		if not cut then return end
		SyncCutOrigin( cut, center )
		UpdateRow( selectedIndex )
		if refreshInspector then UpdateInspector() end
		ScheduleRebuild()
	end

	ViewportSelectCut = function( index )
		index = math.floor( tonumber( index ) or 0 )
		if not cuts[ index ] then return end
		selectedIndex = index
		if cutList.ClearSelection then cutList:ClearSelection() end
		if IsValid( cutRows[ index ] ) then cutList:SelectItem( cutRows[ index ] ) end
		UpdateInspector()
	end

	ViewportSetOffset = function( index, value )
		index = math.floor( tonumber( index ) or 0 )
		local cut = cuts[ index ]
		if not cut then return end
		selectedIndex = index
		cut.offset = math.Clamp( FiniteNumber( value, cut.offset or 0 ),
			-offsetLimit, offsetLimit )
		ChangedSelectedCut( true )
	end

	local function DefaultViewCut()
		local normal = CameraPosition() - center
		if normal:LengthSqr() < 0.000001 then normal = Vector( 1, 0, 0 ) end
		normal:Normalize()
		local angle = normal:Angle()
		return CopyCut( {
			enabled = true, keep_positive = true,
			ox = center.x, oy = center.y, oz = center.z,
			pitch = angle.p, yaw = angle.y, roll = 0,
		}, center )
	end

	cutList.OnRowSelected = function( _, _, row )
		if refreshingList or not row then return end
		selectedIndex = tonumber( row.CutIndex )
		UpdateInspector()
	end

	addCut.DoClick = function()
		if applying or #cuts >= CurrentCutLimit() then return end
		cuts[ #cuts + 1 ] = DefaultViewCut()
		RefreshList( #cuts )
		ScheduleRebuild()
	end

	duplicateCut.DoClick = function()
		local source = SelectedCut()
		if applying or not source or #cuts >= CurrentCutLimit() then return end
		local duplicate = CopyCut( source, center )
		duplicate.offset = math.Clamp( duplicate.offset
			+ math.max( diagonal * 0.025, 0.05 ), -offsetLimit, offsetLimit )
		SyncCutOrigin( duplicate, center )
		table.insert( cuts, selectedIndex + 1, duplicate )
		RefreshList( selectedIndex + 1 )
		ScheduleRebuild()
	end

	removeCut.DoClick = function()
		if not SelectedCut() then return end
		table.remove( cuts, selectedIndex )
		RefreshList( math.min( selectedIndex, #cuts ) )
		ScheduleRebuild()
	end

	moveUp.DoClick = function()
		if not selectedIndex or selectedIndex <= 1 then return end
		cuts[ selectedIndex ], cuts[ selectedIndex - 1 ] =
			cuts[ selectedIndex - 1 ], cuts[ selectedIndex ]
		RefreshList( selectedIndex - 1 )
	end

	moveDown.DoClick = function()
		if not selectedIndex or selectedIndex >= #cuts then return end
		cuts[ selectedIndex ], cuts[ selectedIndex + 1 ] =
			cuts[ selectedIndex + 1 ], cuts[ selectedIndex ]
		RefreshList( selectedIndex + 1 )
	end

	enabledCheck.OnChange = function( _, enabled )
		if suppressUI then return end
		local cut = SelectedCut()
		if not cut then return end
		cut.enabled = enabled == true
		ChangedSelectedCut( false )
	end

	sideCombo.OnSelect = function( _, _, _, keepPositive )
		if suppressUI then return end
		local cut = SelectedCut()
		if not cut then return end
		cut.keep_positive = keepPositive == true
		ChangedSelectedCut( false )
	end

	flipSide.DoClick = function()
		local cut = SelectedCut()
		if not cut then return end
		cut.keep_positive = not ( cut.keep_positive ~= false )
		ChangedSelectedCut( true )
	end

	offsetSlider.OnValueChanged = function( _, value )
		if suppressUI then return end
		local cut = SelectedCut()
		if not cut then return end
		cut.offset = math.Clamp( FiniteNumber( value, cut.offset or 0 ),
			-offsetLimit, offsetLimit )
		ChangedSelectedCut( false )
	end

	local function RotationChanged( field, slider, value )
		if suppressUI then return end
		local cut = SelectedCut()
		if not cut then return end
		value = math.Clamp( FiniteNumber( value, cut[ field ] or 0 ), -180, 180 )
		if angleSnap > 0 then value = math.Round( value / angleSnap ) * angleSnap end
		if math.abs( slider:GetValue() - value ) > 0.0001 then
			suppressUI = true
			slider:SetValue( value )
			suppressUI = false
		end
		cut[ field ] = value
		ChangedSelectedCut( false )
	end
	pitchSlider.OnValueChanged = function( self, value )
		RotationChanged( "pitch", self, value )
	end
	yawSlider.OnValueChanged = function( self, value )
		RotationChanged( "yaw", self, value )
	end
	rollSlider.OnValueChanged = function( self, value )
		RotationChanged( "roll", self, value )
	end

	snapCombo.OnSelect = function( _, _, _, value )
		if suppressUI then return end
		angleSnap = math.max( FiniteNumber( value, 0 ), 0 )
	end
	suppressUI = true
	snapCombo:ChooseOptionID( 3 )
	suppressUI = false

	local function ApplyOrientation( pitch, yaw, roll )
		local cut = SelectedCut()
		if not cut then return end
		cut.pitch, cut.yaw, cut.roll = pitch, yaw, roll or 0
		ChangedSelectedCut( true )
	end
	for index, button in ipairs( presetButtons ) do
		local preset = presets[ index ]
		button.DoClick = function() ApplyOrientation( preset[ 2 ], preset[ 3 ], preset[ 4 ] ) end
	end

	alignView.DoClick = function()
		local normal = CameraPosition() - center
		if normal:LengthSqr() < 0.000001 then return end
		normal:Normalize()
		local angle = normal:Angle()
		ApplyOrientation( angle.p, angle.y, 0 )
	end

	apply.DoClick = function()
		if applying then return end
		local currentData
		if IsValid( entity ) and entity:GetBodygroup( group ) == option then
			currentData = ABT.GetBodygroupVertexData( entity, group )
		end
		if not currentData or currentData.identity ~= geometryIdentity then
			Derma_Message( T( "vertex.option_changed",
				"The model or bodygroup geometry changed. Reopen the editor before applying." ),
				T( "vertex.editor_short", "Bodygroup cut editor" ), L( "common.ok" ) )
			return
		end
		if #cuts > CurrentCutLimit() then
			Derma_Message( T( "vertex.apply_rejected",
				"The server cannot accept this cut edit. Your draft remains open." ),
				T( "vertex.editor_short", "Bodygroup cut editor" ), L( "common.ok" ) )
			UpdateInspector()
			return
		end
		for _, cut in ipairs( cuts ) do SyncCutOrigin( cut, center ) end
		SetApplying( true )
		pendingApplyRequest = SendCuts( entity, group, option, geometryIdentity, cuts,
			function( success )
				pendingApplyRequest = nil
				if not IsValid( frame ) then return end
				if success then
					frame:Close()
					return
				end
				SetApplying( false )
				Derma_Message( T( "vertex.apply_rejected",
					"The server rejected this cut edit. Your draft remains open." ),
					T( "vertex.editor_short", "Bodygroup cut editor" ),
					L( "common.ok" ) )
			end )
		if not pendingApplyRequest then
			SetApplying( false )
			Derma_Message( T( "vertex.apply_rejected",
				"The server rejected this cut edit. Your draft remains open." ),
				T( "vertex.editor_short", "Bodygroup cut editor" ),
				L( "common.ok" ) )
		end
	end

	clear.DoClick = function()
		if applying then return end
		cuts = {}
		selectedIndex = nil
		RefreshList()
		ScheduleRebuild()
	end

	cancel.DoClick = function()
		if not applying then frame:Close() end
	end

	RefreshList( selectedIndex )
end
