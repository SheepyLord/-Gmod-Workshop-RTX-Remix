-- Keep GPU mask writes local, and preserve authored material opacity.
-- Separate chunk: cl_40_damage is deliberately close to Lua 5.1's local limit.
BBS = BBS or {}
BBS.MaterialSafety = {}
local Safety = BBS.MaterialSafety

function Safety.IsFinite( value )
	return type( value ) == "number" and value == value
		and value > -math.huge and value < math.huge
end

function Safety.RequireUVs( ... )
	for index = 1, select( "#", ... ) do
		local value = select( index, ... )
		if not Safety.IsFinite( value ) or math.abs( value ) > 65536 then
			error( "invalid or extreme projected UV; persistent texture unchanged", 0 )
		end
	end
end

function Safety.AlphaTestReference( parameters )
	local function Enabled( key )
		return ( tonumber( parameters[ key ] ) or 0 ) ~= 0
	end
	-- A blended material can be visible with alpha < 0.5. Adding the ordinary
	-- cutout threshold would erase it before we even paint the first hole.
	local alphaTest = Enabled( "$alphatest" )
	local reference = alphaTest
		and tonumber( parameters[ "$alphatestreference" ] ) or nil
	if not Safety.IsFinite( reference ) then
		reference = not alphaTest and Enabled( "$translucent" ) and 1 / 255 or 0.5
	end
	return math.max( 1 / 255, math.min( reference, 1 ) )
end

-- HUD hooks share render state with other addons. In particular a leftover
-- surface alpha multiplier can initialize the ENTIRE persistent RT transparent.
-- Readable state is restored; write-only overrides return to the HUD baseline.
function Safety.BeginRender( state )
	state.safetyAlpha = surface.GetAlphaMultiplier()
	state.safetyBlend = render.GetBlend()
	state.safetyR, state.safetyG, state.safetyB = render.GetColorModulation()
	state.safetyClipping = DisableClipping( true )
	surface.SetAlphaMultiplier( 1 )
	render.SetBlend( 1 )
	render.SetColorModulation( 1, 1, 1 )
	render.SetScissorRect( 0, 0, 0, 0, false )
	render.SetStencilEnable( false )
	render.OverrideColorWriteEnable( true, true )
	render.OverrideAlphaWriteEnable( true, true )
end

function Safety.EndRender( state )
	pcall( render.SetScissorRect, 0, 0, 0, 0, false )
	pcall( render.OverrideColorWriteEnable, false, false )
	if state.safetyAlpha ~= nil then
		pcall( surface.SetAlphaMultiplier, state.safetyAlpha )
	end
	if state.safetyBlend ~= nil then pcall( render.SetBlend, state.safetyBlend ) end
	if state.safetyR ~= nil then
		pcall( render.SetColorModulation, state.safetyR, state.safetyG, state.safetyB )
	end
	if state.safetyClipping ~= nil then
		pcall( DisableClipping, state.safetyClipping )
	end
end

-- Conservative 32x32 write-domain, NOT a replacement for the exact GPU mask.
-- Record the actual rasterized polygons, including wrapped UV copies. Dilate
-- for blur/filter support, then coalesce disjoint cells into non-overlapping
-- scissor rectangles. Even a corrupt all-white scratch alpha cannot write
-- outside this domain. No GPU readback or per-material extra RT is necessary.
function Safety.NewWriteGuard( width, height, paddingX, paddingY )
	return { width = width, height = height, paddingX = paddingX,
		paddingY = paddingY, rows = {}, polygonCount = 0,
		columns = math.min( width, 32 ), rowCount = math.min( height, 32 ) }
end

function Safety.AddWritePolygon( guard, polygon )
	local minX, minY, maxX, maxY = math.huge, math.huge, -math.huge, -math.huge
	for _, point in ipairs( polygon ) do
		if not Safety.IsFinite( point.x ) or not Safety.IsFinite( point.y ) then
			error( "non-finite projected UV polygon; persistent texture unchanged", 0 )
		end
		minX, minY = math.min( minX, point.x ), math.min( minY, point.y )
		maxX, maxY = math.max( maxX, point.x ), math.max( maxY, point.y )
	end
	minX, minY = minX - guard.paddingX, minY - guard.paddingY
	maxX, maxY = maxX + guard.paddingX, maxY + guard.paddingY
	if maxX < 0 or maxY < 0 or minX >= guard.width or minY >= guard.height then return end
	local firstX = math.max( 0, math.floor( minX / guard.width * guard.columns ) )
	local lastX = math.min( guard.columns - 1,
		math.floor( maxX / guard.width * guard.columns ) )
	local firstY = math.max( 0, math.floor( minY / guard.height * guard.rowCount ) )
	local lastY = math.min( guard.rowCount - 1,
		math.floor( maxY / guard.height * guard.rowCount ) )
	local bits = bit.band( bit.lshift( -1, firstX ), bit.rshift( -1, 31 - lastX ) )
	for row = firstY, lastY do
		guard.rows[ row ] = bit.bor( guard.rows[ row ] or 0, bits )
	end
	guard.polygonCount = guard.polygonCount + 1
end

function Safety.FinishWriteGuard( guard, width, height )
	local rectangles, previous, cellCount = {}, {}, 0
	for row = 0, guard.rowCount - 1 do
		local bits, active, column = guard.rows[ row ] or 0, {}, 0
		while column < guard.columns do
			if bit.band( bits, bit.lshift( 1, column ) ) == 0 then
				column = column + 1
			else
				local first = column
				repeat column = column + 1 until column == guard.columns
					or bit.band( bits, bit.lshift( 1, column ) ) == 0
				cellCount = cellCount + column - first
				local key = first * 32 + column - 1
				local rectangle = previous[ key ]
				if rectangle then
					rectangle[ 4 ] = math.floor( ( row + 1 ) * height / guard.rowCount )
				else
					rectangle = { math.floor( first * width / guard.columns ),
						math.floor( row * height / guard.rowCount ),
						math.floor( column * width / guard.columns ),
						math.floor( ( row + 1 ) * height / guard.rowCount ) }
					rectangles[ #rectangles + 1 ] = rectangle
				end
				active[ key ] = rectangle
			end
		end
		previous = active
	end
	return rectangles, cellCount / ( guard.columns * guard.rowCount )
end
