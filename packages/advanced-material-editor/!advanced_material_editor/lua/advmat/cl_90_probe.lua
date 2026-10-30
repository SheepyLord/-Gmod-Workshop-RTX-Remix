--[[---------------------------------------------------------------------------
	Advanced Material Editor - canvas probe

	Two console commands that exist to settle one question: when a click on the
	canvas does not land where it was aimed, WHICH of the numbers involved is
	wrong?

	This is here because that question has been guessed at twice and got the
	wrong answer both times. Every mapping in the canvas is algebraically
	self-consistent when read on the page - panel pixels to image pixels to
	fractions of the texture and back - so if the result on screen disagrees,
	then one of the values feeding it is not what the code believes it is, and
	reading harder will not find which. Measuring will.

	    advmat_probe       print every number the canvas maps through
	    advmat_paintmark   put marks in the picture and marks on the panel
	    advmat_readback    read the picture back and say where the marks landed
	    advmat_screencheck measure the marks against the crosses, on the screen
	    advmat_calibrate   select exactly the middle half of the texture
	    advmat_rule        print a slot's parameters at every stage of a save
	    advmat_savetrace   walk a saved rule's whole chain and say which link broke

	advmat_savetrace exists because the save path has now produced three
	different bugs, and every one of them was invisible in the code and obvious
	in one measurement. The whole documented chain passes in dev/test_roundtrip
	- both realms in one state, the wire included - so when a save still
	vanishes in a real game, the difference IS the game, and this walks the
	chain there: what the editor holds, what the mirror heard back, what
	material was built, and what the server actually put on the entity
	(GetSubMaterial on the client reports the server's value, which is what
	makes that last one checkable at all).

	advmat_readback is the one that needs nobody to look at anything. The marks
	are written into the working buffer at known pixels, pushed into the render
	target, and then that render target is copied back and searched for them.
	Expected pixel against measured pixel, in the target's own coordinates,
	with the screen and the mouse and the eye taken out of it entirely.

	It splits the remaining question in two. If the marks come back where they
	were written, the upload is exact and whatever moves them happens when the
	target is drawn onto the panel. If they come back somewhere else, the
	upload is the fault and the numbers printed here are how far out it is.

	advmat_screencheck closes the other half. It photographs the finished frame
	around each mark and finds BOTH the magenta square and the green cross in
	the same few hundred pixels, so the answer depends on no arithmetic of its
	own - not on where the panel thinks anything is, and not on anybody's eye.
	It then says whether what is left over is a shift (the same everywhere) or
	a scale (growing with distance from the middle), because the two have
	different causes and only one of them is a constant.

	advmat_paintmark is the one that settles the offset, because it does not
	involve the mouse at all. There are two ways a coordinate reaches the
	screen here: through the picture, which is written into a render target and
	then stretched over a rectangle, and through the panel, which is drawn
	straight onto it at "x0 + u * side". Everything the user aims at arrives the
	first way; the pointer, the brush ring and every click arrive the second.
	The whole of this bug is the possibility that those two do not agree.

	So it puts a mark down each way at the same five coordinates. If the green
	cross sits in the middle of the magenta square, the two paths agree and the
	offset is somewhere else entirely. If it does not, the gap between them IS
	the offset, at five places at once - which gives both how far it is shifted
	and whether the shift grows across the picture, in one screenshot, with
	nothing having to be aimed at.

	advmat_rule is the same idea applied to the other half of the addon. A
	parameter that is right on screen and wrong after Save has been lost at one
	of four points - the working copy, the canonical form that gets sent, the
	rule the client mirror holds, or the material built from it - and printing
	all four next to each other says which. Run it before pressing Save and
	again afterwards; the line that changes is the answer.

	The probe reports what each render target ACTUALLY allocated as well as what
	was asked for. A target handed back larger than requested is invisible in
	Lua and would produce exactly the reported symptom: content written into the
	top left corner of it, then stretched over the whole image rectangle, so
	everything is shrunk towards the top left and the error grows with distance
	from it.

	The calibration is the other half. A rectangle from 0.25 to 0.75 has to
	cover the middle half of the texture exactly, with a quarter of the image
	showing on every side. Any deviation from that is the whole bug, measurable
	off a screenshot in texture widths rather than described in words.

	Neither command changes anything that is saved. Delete this file and the
	addon is unaffected.
-----------------------------------------------------------------------------]]

local function Frame()
	local frame = AdvMat.TexEditor

	if not IsValid( frame ) then
		print( "AdvMat: open the texture editor first (the Edit button on a texture row)." )
		return nil
	end

	return frame
end

--- Both dimensions a texture reports. Width/Height and the Mapping pair can
--- disagree, and when they do it is the mapping pair that says how the texture
--- is sampled - which is the one that matters here.
local function TexSize( tex )
	if not tex then return "none" end

	local ok, w, h = pcall( function() return tex:Width(), tex:Height() end )
	local mok, mw, mh = pcall( function()
		return tex:GetMappingWidth(), tex:GetMappingHeight()
	end )

	return string.format( "%s   mapping %s",
		ok and ( w .. " x " .. h ) or "?",
		mok and ( mw .. " x " .. mh ) or "?" )
end

local function Line( label, fmt, ... )
	print( string.format( "  %-14s " .. fmt, label, ... ) )
end

concommand.Add( "advmat_probe", function()
	local frame = Frame()
	if not frame then return end

	local canvas = frame.Canvas
	if not IsValid( canvas ) then print( "AdvMat: no canvas." ) return end

	local w, h   = canvas:GetWide(), canvas:GetTall()
	local scale  = canvas:Scale()
	local x0, y0 = canvas:ToPanel( 0, 0 )
	local iw     = ( canvas.SizeW or 0 ) * scale
	local ih     = ( canvas.SizeH or 0 ) * scale

	print( "" )
	print( "AdvMat canvas probe" )

	Line( "panel", "%d x %d", w, h )
	Line( "zoom", "step %d  (x%.4f)", canvas.Zoom or -1, scale )
	Line( "pan", "%.3f, %.3f", canvas.PanX or 0, canvas.PanY or 0 )
	Line( "canvas size", "%s x %s", tostring( canvas.SizeW ), tostring( canvas.SizeH ) )
	Line( "image rect", "x0 %.3f  y0 %.3f  w %.3f  h %.3f", x0, y0, iw, ih )

	local buf = canvas.Buf
	Line( "buffer", "%s x %s", buf and buf.w or "nil", buf and buf.h or "nil" )

	local src = canvas.Src
	Line( "source read", "%s x %s  alpha=%s",
		src and src.w or "nil", src and src.h or "nil",
		src and tostring( src.alpha ) or "nil" )

	local rw, rh = AdvMat.Gen.Dims( frame.Recipe )

	Line( "recipe size", "%d x %d", rw, rh )
	Line( "native", "%s x %s", tostring( frame.NativeW ), tostring( frame.NativeH ) )
	Line( "working", "%s x %s", tostring( frame.WorkW ), tostring( frame.WorkH ) )

	local ux, uy = canvas:UploadScale()
	Line( "upload scale", "%.4f, %.4f", ux, uy )

	-- The mask is a flat array. Its length is the only way to ask what
	-- resolution it was built at, and it has to be the buffer's.
	local mask = frame.Mask
	local wantMask = ( frame.WorkW or 0 ) * ( frame.WorkH or 0 )

	Line( "mask", "%s entries   (the working size is %d%s)",
		mask and #mask or "none", wantMask,
		( mask and #mask ~= wantMask ) and "  <-- MISMATCH" or "" )

	-- The display target is allowed to be larger than the buffer - that is the
	-- native-resolution canvas - but it has to be the same SHAPE, or the image
	-- is stretched.
	if buf and buf.w > 0 and buf.h > 0
		and math.abs( canvas.SizeW / buf.w - canvas.SizeH / buf.h ) > 0.001 then
		Line( "", "display and buffer are different shapes  <-- MISMATCH" )
	end

	print( "  render targets   (requested -> actual)" )
	Line( "  canvas", "%s -> %s", tostring( canvas.RTSize ), TexSize( canvas.RT ) )
	Line( "  uv overlay", "%s x %s -> %s",
		tostring( canvas.UVRTW ), tostring( canvas.UVRTH ), TexSize( canvas.UVRT ) )
	Line( "  selection", "%s x %s -> %s",
		tostring( canvas.SelRTW ), tostring( canvas.SelRTH ), TexSize( canvas.SelRT ) )

	local path = canvas.SrcPath
	if path and path ~= "" then
		local mat = Material( path )
		local tex = ( mat and not mat:IsError() ) and mat:GetTexture( "$basetexture" ) or nil

		Line( "  source", "%s -> %s", path, TexSize( tex ) )
	end

	local mx, my = canvas:CursorPos()

	if mx < 0 or my < 0 or mx > w or my > h then
		Line( "cursor", "not over the canvas - hover it and run this again" )
		print( "" )
		return
	end

	local u, v = canvas:ToNorm( mx, my )

	Line( "cursor", "panel %d,%d  ->  u %.4f  v %.4f", mx, my, u, v )
	Line( "", "should draw back at panel %.1f, %.1f", x0 + u * iw, y0 + v * ih )

	-- The decisive comparison, and the reason this file exists.
	--
	-- The first answer is what the editor uses: the cursor position this panel
	-- reports, run through its own transform. The second ignores the panel
	-- entirely and asks where the cursor is on the SCREEN relative to the
	-- rectangle the image was last actually drawn into, also on the screen.
	--
	-- The two are the same question asked without any shared assumption. They
	-- have to agree. If they do not, the panel taking the mouse and the panel
	-- putting the picture on the screen do not share an origin, and the
	-- difference printed here IS the bug, in fractions of the texture.
	local seen = canvas.LastRect

	if not seen or not seen.w or seen.w == 0 or not seen.h or seen.h == 0 then
		Line( "screen check", "the canvas has not painted yet" )
		print( "" )
		return
	end

	local gx, gy = gui.MousePos()

	local su = ( gx - ( seen.sx + seen.x0 ) ) / seen.w
	local sv = ( gy - ( seen.sy + seen.y0 ) ) / seen.h

	Line( "panel origin", "screen %d, %d   (recorded while painting)", seen.sx, seen.sy )
	Line( "image on screen", "%.1f, %.1f  size %.1f x %.1f",
		seen.sx + seen.x0, seen.sy + seen.y0, seen.w, seen.h )
	Line( "cursor (screen)", "%d, %d  ->  u %.4f  v %.4f", gx, gy, su, sv )

	local du, dv = su - u, sv - v
	local off    = ( math.abs( du ) > 0.002 or math.abs( dv ) > 0.002 )

	Line( "DIFFERENCE", "%+.4f, %+.4f   %s", du, dv,
		off and "<-- THIS IS THE BUG" or "(agree, so the offset is not here)" )

	if off then
		Line( "", "in texture pixels at %s x %s: %+.1f, %+.1f",
			tostring( canvas.SizeW ), tostring( canvas.SizeH ),
			du * ( canvas.SizeW or 0 ), dv * ( canvas.SizeH or 0 ) )
	end

	print( "" )
end, nil, "Print every coordinate the texture editor's canvas maps through." )

--- Every key of a params table, sorted, so two of them can be read against
--- each other.
local function Keys( t )
	local out = {}
	for k in pairs( t or {} ) do out[ #out + 1 ] = tostring( k ) end
	table.sort( out )
	return out
end

local function DumpParams( label, params )
	local keys = Keys( params )

	if #keys == 0 then
		Line( label, "(none)" )
		return
	end

	Line( label, "%d", #keys )

	for _, k in ipairs( keys ) do
		print( string.format( "      %-28s %s", k, tostring( params[ k ] ) ) )
	end
end

local function DumpGen( label, gen )
	local keys = Keys( gen )

	if #keys == 0 then
		Line( label, "(none)" )
		return
	end

	Line( label, "%d", #keys )

	for _, k in ipairs( keys ) do
		local recipe = gen[ k ]

		print( string.format( "      %-28s kind=%s src=%s size=%s", k,
			tostring( recipe.kind ), tostring( recipe.src ), tostring( recipe.size ) ) )
	end
end

concommand.Add( "advmat_savetrace", function()
	local editor = AdvMat.Editor

	if not IsValid( editor ) then
		print( "AdvMat: open the material editor first, then Save, then run this." )
		return
	end

	local ent = editor.Entity

	if not IsValid( ent ) then
		print( "AdvMat: the editor has no entity (a map surface has no save chain to trace)." )
		return
	end

	local scope = editor:CurrentScope()
	local ei    = ent:EntIndex()

	print( "" )
	print( "AdvMat save trace" )
	Line( "entity", "%d  %s", ei, tostring( ent:GetModel() ) )
	Line( "save target", "%s", AdvMat.SCOPE_NAME[ scope ] or tostring( scope ) )
	Line( "serverside", "%s", GetConVar( "advmat_serverside" ):GetBool()
		and "1 (the server applies saved rules)" or "0 (each client applies its own)" )

	local traced = 0

	for idx = 0, #editor.Materials - 1 do
		local w = editor.Working[ idx ]

		if not AdvMat.RuleIsEmpty( w ) or editor.HadRule[ idx ] then
			traced = traced + 1

			print( "" )
			Line( "slot " .. idx, "%s", tostring( editor.Materials[ idx + 1 ] ) )

			-- 1. What the editor is holding.
			Line( "  editing", "%d parameter(s)%s",
				AdvMat.TableCount( w and w.params ),
				( w and w.gen ) and ( ", " .. AdvMat.TableCount( w.gen ) .. " generated" ) or "" )

			-- 2. What the client mirror heard back from the server. This is
			--    nil until the save's echo lands, so checking it after a save
			--    answers "did the server accept it".
			local key = editor:ScopeKey( idx, scope )
			local rule

			if scope == AdvMat.SCOPE.ENTITY then
				local set = AdvMat.Client.EntRules[ ei ]
				rule = set and set[ idx ]
			else
				rule = AdvMat.Client.Rules[ AdvMat.RuleID( scope, key, idx ) ]
			end

			if not rule then
				Line( "  mirror", "NO RULE under %s  <-- the echo never landed: "
					.. "the server rejected the save, or it never arrived",
					AdvMat.RuleID( scope, key, idx ) )
			else
				Line( "  mirror", "%d parameter(s)%s",
					AdvMat.TableCount( rule.params ),
					rule.gen and ( ", " .. AdvMat.TableCount( rule.gen ) .. " generated" ) or "" )

				-- 3. The material every client should build from it.
				local name  = AdvMat.MaterialName( rule )
				local built = AdvMat.Apply.Built[ name ]

				Line( "  material", "%s  %s", name,
					built and "(built)" or "NOT BUILT  <-- the mirror never built it" )
			end

			-- 4. What the SERVER put on the entity. On the client this reads
			--    the networked value, so it reports the server's opinion.
			local sv = ent:GetSubMaterial( idx )

			if sv == "" then
				Line( "  server", "nothing on the entity  <-- the server never applied it" )
			else
				Line( "  server", "%s", sv )

				if string.sub( sv, 1, 8 ) == "!advmat_"
					and not AdvMat.Apply.Built[ string.sub( sv, 2 ) ] then
					Line( "", "...which THIS client has not built  <-- name mismatch "
						.. "between server and client" )
				end
			end

			-- 5. What this client is drawing over it.
			local pv  = AdvMat.Client.Preview[ ei ]
			local set = AdvMat.Apply.ClientSet[ ei ]

			Line( "  local", "preview %s, clientside write %s",
				( pv and pv[ idx ] ) and "ACTIVE" or "none",
				set and set[ idx ] and tostring( set[ idx ] ) or "none" )
		end
	end

	if traced == 0 then
		Line( "", "no slot is edited and none has a saved rule - nothing to trace" )
	end

	print( "" )
	Line( "how to read it", "run once after pressing Save. Every line that says" )
	Line( "", "<-- names the first broken link; if none does and the model" )
	Line( "", "still looks default, say so - that is its own answer." )
	print( "" )
end, nil, "Walk a saved rule's whole chain and say which link broke." )

concommand.Add( "advmat_rule", function()
	local editor = AdvMat.Editor

	if not IsValid( editor ) then
		print( "AdvMat: open the material editor first." )
		return
	end

	local idx = editor.Selected or 0
	local ent = editor.Entity

	print( "" )
	print( "AdvMat rule probe" )
	Line( "slot", "%d of %s", idx,
		IsValid( ent ) and tostring( ent:GetModel() ) or "the world material" )

	local w = editor.Working and editor.Working[ idx ]

	if not w then
		Line( "working copy", "nothing edited on this slot" )
		print( "" )
		return
	end

	-- 1. What the widgets have put into the working copy.
	DumpParams( "working", w.params )
	DumpGen( "working gen", w.gen )

	-- 2. What that becomes on the way out. Anything here that is missing from
	--    the block above was dropped by sanitising - which is now the same
	--    decision the preview is built from, so it should already have been
	--    announced when it happened.
	local params = AdvMat.SanitizeParams( w.params )
	local gen    = AdvMat.Gen.SanitizeAll( w.gen )

	DumpParams( "canonical", params )
	DumpGen( "canonical gen", gen )

	-- 3. What the client mirror believes is saved. Before a save this is the
	--    PREVIOUS rule; after one it is what came back from the server. A key
	--    present above and absent here did not survive the round trip.
	local rule, isPreview = AdvMat.Client.Resolve( ent, idx,
		editor.Materials and editor.Materials[ idx + 1 ] )

	if not rule then
		Line( "stored rule", "none - nothing saved for this slot yet" )
	else
		Line( "stored rule", "scope=%s  %s", tostring( rule.scope ),
			isPreview and "(this is the local PREVIEW, not a saved rule)" or "(saved)" )
		DumpParams( "  stored", rule.params )
		DumpGen( "  stored gen", rule.gen )
	end

	print( "" )
end, nil, "Print a slot's parameters at every stage between the widgets and the saved rule." )

---------------------------------------------------------------------------
-- Two paths to the screen, marked at the same five places
---------------------------------------------------------------------------

-- Far enough apart to show a shift that grows, and none of them on an edge
-- where a mark would be half off the picture.
local SPOTS = { { 0, 0 }, { 1, 0 }, { 0, 1 }, { 1, 1 },
                { 0.25, 0.25 }, { 0.75, 0.25 }, { 0.5, 0.5 },
                { 0.25, 0.75 }, { 0.75, 0.75 } }

local MARK = 2   -- half width of the square, in buffer pixels

--- Write a solid square into the working buffer, the same way a brush stroke
--- writes into it. Nothing is added to the recipe, so this is not an edit and
--- the next rebuild removes it.
--- Returns the centre of what was actually drawn, in 0..1. A mark in a corner
--- is clipped against the edge, so its middle is not the pixel it was asked
--- for, and comparing a cross drawn at that pixel against it would report an
--- offset that is not there.
local function Square( buf, cx, cy )
	local x0 = math.max( cx - MARK, 0 )
	local x1 = math.min( cx + MARK, buf.w - 1 )
	local y0 = math.max( cy - MARK, 0 )
	local y1 = math.min( cy + MARK, buf.h - 1 )

	for y = y0, y1 do
		local row = y * buf.w

		for x = x0, x1 do
			local i = row + x + 1

			buf.r[ i ], buf.g[ i ], buf.b[ i ], buf.a[ i ] = 255, 0, 255, 255
		end
	end

	return ( x0 + x1 + 1 ) * 0.5 / buf.w, ( y0 + y1 + 1 ) * 0.5 / buf.h
end

concommand.Add( "advmat_paintmark", function()
	local frame = Frame()
	if not frame then return end

	local canvas = frame.Canvas
	local buf    = frame.Buf

	if not IsValid( canvas ) or not buf then
		print( "AdvMat: the canvas has nothing loaded yet." )
		return
	end

	-- Second call clears, so this cannot be left switched on by accident. The
	-- rebuild is what removes the squares: they were never steps.
	if AdvMat.ProbeMarks then
		AdvMat.ProbeMarks = nil
		canvas.PaintOver  = nil
		frame:Recompose()

		print( "AdvMat: marks cleared." )
		return
	end

	local marks = {}

	for _, spot in ipairs( SPOTS ) do
		local cx = math.Clamp( math.floor( spot[ 1 ] * buf.w ), 0, buf.w - 1 )
		local cy = math.Clamp( math.floor( spot[ 2 ] * buf.h ), 0, buf.h - 1 )

		-- The CENTRE of the square that was just written, not the coordinate
		-- that was asked for. A buffer pixel covers a whole texel of the
		-- picture, so its middle sits half a pixel along from its corner, and
		-- comparing a cross drawn at the corner against a square drawn from it
		-- would report half a pixel of error that is not there.
		local mu, mv = Square( buf, cx, cy )

		marks[ #marks + 1 ] = { mu, mv }
	end

	AdvMat.ProbeMarks = marks
	canvas:Invalidate()

	-- Drawn over the panel rather than into the picture, which is the entire
	-- point: this is the other path to the screen.
	canvas.PaintOver = function( pnl, w, h )
		local x0, y0 = pnl:ToPanel( 0, 0 )
		local s      = pnl:Scale()
		local iw, ih = ( pnl.SizeW or 0 ) * s, ( pnl.SizeH or 0 ) * s

		-- Where the panel believes the picture's edges are. The marks in the
		-- picture have to line up inside it; if they hang outside, the picture
		-- is not the size it was drawn into.
		surface.SetDrawColor( 60, 255, 90, 120 )
		surface.DrawOutlinedRect( x0, y0, iw, ih, 2 )

		for _, m in ipairs( AdvMat.ProbeMarks or {} ) do
			local px = x0 + m[ 1 ] * iw
			local py = y0 + m[ 2 ] * ih

			if px > -40 and py > -40 and px < w + 40 and py < h + 40 then
				surface.SetDrawColor( 0, 0, 0, 255 )
				surface.DrawLine( px - 15, py + 1, px + 15, py + 1 )
				surface.DrawLine( px + 1, py - 15, px + 1, py + 15 )

				surface.SetDrawColor( 60, 255, 90, 255 )
				surface.DrawLine( px - 15, py, px + 15, py )
				surface.DrawLine( px, py - 15, px, py + 15 )
			end
		end
	end

	local sx, sy = canvas:LocalToScreen( 0, 0 )
	local x0, y0 = canvas:ToPanel( 0, 0 )
	local scale  = canvas:Scale()
	local iw, ih = ( canvas.SizeW or 0 ) * scale, ( canvas.SizeH or 0 ) * scale

	print( "" )
	print( "AdvMat mark probe" )
	Line( "buffer", "%d x %d", buf.w, buf.h )
	Line( "", "magenta squares are IN the picture, green crosses are ON the panel" )
	Line( "", "they are the same coordinate, so they have to coincide" )

	for _, m in ipairs( marks ) do
		Line( string.format( "%.4f, %.4f", m[ 1 ], m[ 2 ] ),
			"panel %.1f, %.1f   screen %.1f, %.1f",
			x0 + m[ 1 ] * iw, y0 + m[ 2 ] * ih,
			sx + x0 + m[ 1 ] * iw, sy + y0 + m[ 2 ] * ih )
	end

	Line( "image rect", "panel %.1f, %.1f  %.1f x %.1f", x0, y0, iw, ih )

	Line( "", "run advmat_paintmark again to clear" )
	print( "" )
end, nil, "Mark the same five coordinates in the picture and on the panel." )

---------------------------------------------------------------------------
-- Reading the picture back
---------------------------------------------------------------------------

--- Every pixel of `rt` that is the mark colour, sorted into the mark it is
--- nearest to, as { x, y, n } sums.
---
--- The render target has to be pushed and a 2D context started before this,
--- and both have to be closed after it. Copying pixels back outside one comes
--- back as flat black with nothing to say it failed.
local function ScanMarks( w, h, marks )
	local found = {}
	for i = 1, #marks do found[ i ] = { x = 0, y = 0, n = 0 } end

	local data = nil

	if render.Capture then
		local ok, out = pcall( render.Capture, {
			format = "rgb", x = 0, y = 0, w = w, h = h, alpha = false,
		} )

		if ok and isstring( out ) and #out >= w * h * 3 then data = out end
	end

	if not data then render.CapturePixels() end

	local byte = string.byte

	for y = 0, h - 1 do
		for x = 0, w - 1 do
			local r, g, b

			if data then
				local o = ( y * w + x ) * 3 + 1
				r, g, b = byte( data, o, o + 2 )
			else
				r, g, b = render.ReadPixel( x, y )
			end

			-- Loose, because a render target rounds: what went in as pure
			-- magenta does not always come back as exactly 255, 0, 255.
			if r > 180 and g < 80 and b > 180 then
				local best, bestD = nil, nil

				for i, m in ipairs( marks ) do
					local dx = ( x + 0.5 ) - m[ 1 ] * w
					local dy = ( y + 0.5 ) - m[ 2 ] * h
					local d  = dx * dx + dy * dy

					if not bestD or d < bestD then best, bestD = i, d end
				end

				local hit = found[ best ]
				hit.x, hit.y, hit.n = hit.x + x + 0.5, hit.y + y + 0.5, hit.n + 1
			end
		end
	end

	return found
end

local wantReadback = false

local function DoReadback()
	local frame = AdvMat.TexEditor
	if not IsValid( frame ) then return end

	local canvas = frame.Canvas
	local marks  = AdvMat.ProbeMarks

	if not IsValid( canvas ) or not canvas.RT or not marks then return end

	local w, h = canvas.SizeW or 0, canvas.SizeH or 0
	if w <= 0 or h <= 0 then return end

	-- Balanced on every path. An unbalanced render target stack does not fail,
	-- it corrupts everything drawn for the rest of the frame.
	render.PushRenderTarget( canvas.RT )
	cam.Start2D()

	local ok, found = pcall( ScanMarks, w, h, marks )

	cam.End2D()
	render.PopRenderTarget()

	if not ok then
		print( "AdvMat: could not read the canvas back: " .. tostring( found ) )
		return
	end

	print( "" )
	print( "AdvMat readback" )
	Line( "render target", "%d x %d   (the canvas, in its own pixels)", w, h )
	Line( "", "written -> found, in render target pixels" )

	local worstX, worstY = 0, 0
	local missing = 0

	for i, m in ipairs( marks ) do
		local hit = found[ i ]
		local ex, ey = m[ 1 ] * w, m[ 2 ] * h

		if hit.n == 0 then
			missing = missing + 1
			Line( string.format( "%7.1f,%7.1f", ex, ey ), "NOT FOUND" )
		else
			local gx, gy = hit.x / hit.n, hit.y / hit.n
			local dx, dy = gx - ex, gy - ey

			if math.abs( dx ) > math.abs( worstX ) then worstX = dx end
			if math.abs( dy ) > math.abs( worstY ) then worstY = dy end

			Line( string.format( "%7.1f,%7.1f", ex, ey ),
				"%7.1f,%7.1f   off by %+6.2f,%+6.2f   (%d pixels)",
				gx, gy, dx, dy, hit.n )
		end
	end

	if missing > 0 then
		Line( "", "%d mark(s) were not in the target at all", missing )
	end

	-- Half a pixel is the grid itself, not an error.
	if math.abs( worstX ) <= 0.75 and math.abs( worstY ) <= 0.75 then
		Line( "verdict", "the upload is exact - whatever moves the paint " ..
			"happens when this target is drawn onto the panel" )
	else
		Line( "verdict", "the upload is out by up to %+.2f, %+.2f - " ..
			"THIS IS THE BUG", worstX, worstY )
	end

	print( "" )
end

concommand.Add( "advmat_readback", function()
	local frame = Frame()
	if not frame then return end

	if not AdvMat.ProbeMarks then
		print( "AdvMat: run advmat_paintmark first, so there is something to look for." )
		return
	end

	-- Copying pixels out of a render target only works inside a render hook.
	-- A console command is not one, and outside one the copy comes back as
	-- flat black with no error - which would read as "the marks are missing".
	wantReadback = true
	print( "AdvMat: reading the canvas back on the next frame." )
end, nil, "Find the paint marks inside the canvas and say where they actually landed." )

hook.Add( "PreRender", "AdvMat.ProbeReadback", function()
	if not wantReadback then return end
	wantReadback = false

	DoReadback()
end )

---------------------------------------------------------------------------
-- Measuring the marks against the crosses, on the screen itself
---------------------------------------------------------------------------

-- Half the width of the window photographed around each mark. Wide enough to
-- hold a cross arm and any plausible error, small enough that nine of them are
-- a few hundred thousand pixels rather than a whole frame.
local WINDOW = 30

--- The centre of every pixel matching `want` inside one captured window.
local function Centroid( data, w, h, want )
	local byte = string.byte
	local sx, sy, n = 0, 0, 0

	for y = 0, h - 1 do
		for x = 0, w - 1 do
			local o = ( y * w + x ) * 3 + 1
			local r, g, b = byte( data, o, o + 2 )

			if want( r, g, b ) then
				sx, sy, n = sx + x + 0.5, sy + y + 0.5, n + 1
			end
		end
	end

	if n == 0 then return nil end
	return sx / n, sy / n, n
end

-- The mark is magenta and the cross is green, and both are drawn over whatever
-- the texture happens to be, so the tests are loose enough to survive the
-- render target rounding them.
local function IsMark( r, g, b )  return r > 170 and g < 90 and b > 170 end
local function IsCross( r, g, b ) return g > 170 and r < 130 and b < 170 end

local wantScreen = false

local function DoScreenCheck()
	local frame = AdvMat.TexEditor
	if not IsValid( frame ) then return end

	local canvas = frame.Canvas
	local marks  = AdvMat.ProbeMarks

	if not IsValid( canvas ) or not marks then return end
	if not render.Capture then
		print( "AdvMat: this build has no render.Capture, so it cannot measure itself." )
		return
	end

	local sx, sy = canvas:LocalToScreen( 0, 0 )
	local x0, y0 = canvas:ToPanel( 0, 0 )
	local scale  = canvas:Scale()
	local iw, ih = ( canvas.SizeW or 0 ) * scale, ( canvas.SizeH or 0 ) * scale

	-- The middle of the picture, which is the point a scale would be about.
	local cx = sx + x0 + iw * 0.5
	local cy = sy + y0 + ih * 0.5

	print( "" )
	print( "AdvMat screen check" )
	Line( "", "the mark and the cross, found in the same photograph" )

	local side = WINDOW * 2 + 1

	-- For the two fits: a plain average is the shift, and delta against
	-- distance from the middle is the scale.
	local sumX, sumY, seen = 0, 0, 0
	local topX, botX, topY, botY = 0, 0, 0, 0

	for _, m in ipairs( marks ) do
		local px = sx + x0 + m[ 1 ] * iw
		local py = sy + y0 + m[ 2 ] * ih

		local wx = math.Clamp( math.floor( px - WINDOW ), 0, math.max( ScrW() - side, 0 ) )
		local wy = math.Clamp( math.floor( py - WINDOW ), 0, math.max( ScrH() - side, 0 ) )

		local ok, data = pcall( render.Capture, {
			format = "rgb", x = wx, y = wy, w = side, h = side, alpha = false,
		} )

		local label = string.format( "%.4f,%.4f", m[ 1 ], m[ 2 ] )

		if not ok or not isstring( data ) or #data < side * side * 3 then
			Line( label, "could not photograph this one" )
		else
			local mx, my = Centroid( data, side, side, IsMark )
			local gx, gy = Centroid( data, side, side, IsCross )

			if not mx then
				Line( label, "no mark in the window - it is more than %d px out", WINDOW )
			elseif not gx then
				Line( label, "no cross in the window" )
			else
				local dx, dy = mx - gx, my - gy

				Line( label, "mark is %+.2f, %+.2f from the cross", dx, dy )

				sumX, sumY, seen = sumX + dx, sumY + dy, seen + 1

				-- Least squares slope of delta against distance from the middle,
				-- accumulated as it goes.
				local rx, ry = px - cx, py - cy

				topX, botX = topX + dx * rx, botX + rx * rx
				topY, botY = topY + dy * ry, botY + ry * ry
			end
		end
	end

	if seen == 0 then
		Line( "", "nothing measurable - is the editor on screen and unobscured?" )
		print( "" )
		return
	end

	local avgX, avgY = sumX / seen, sumY / seen
	local kx = ( botX > 0 ) and ( 1 + topX / botX ) or 1
	local ky = ( botY > 0 ) and ( 1 + topY / botY ) or 1

	print( "" )
	Line( "as a shift", "%+.2f, %+.2f screen pixels everywhere", avgX, avgY )
	Line( "", "which is %+.3f, %+.3f of a texture pixel",
		avgX / math.max( scale, 0.0001 ), avgY / math.max( scale, 0.0001 ) )
	Line( "as a scale", "x%.5f, x%.5f about the middle", kx, ky )
	Line( "", "which shows %.2f of %s texels across",
		( canvas.SizeW or 0 ) / kx, tostring( canvas.SizeW ) )

	print( "" )
end

concommand.Add( "advmat_screencheck", function()
	local frame = Frame()
	if not frame then return end

	if not AdvMat.ProbeMarks then
		print( "AdvMat: run advmat_paintmark first, so there is something to measure." )
		return
	end

	-- Photographing the finished frame means waiting for the frame to be
	-- finished, and a console command runs nowhere near one.
	wantScreen = true
	print( "AdvMat: measuring on the next frame - leave the editor on screen." )
end, nil, "Measure each paint mark against its cross in a photograph of the screen." )

hook.Add( "PostRenderVGUI", "AdvMat.ProbeScreenCheck", function()
	if not wantScreen then return end
	wantScreen = false

	local ok, err = pcall( DoScreenCheck )
	if not ok then print( "AdvMat: screen check failed: " .. tostring( err ) ) end
end )

concommand.Add( "advmat_calibrate", function()
	local frame = Frame()
	if not frame then return end

	-- Exactly the middle half. Nothing derived, nothing rounded: if what
	-- appears on screen is not a square with a quarter of the image visible on
	-- every side, the difference is the bug, and it can be measured off a
	-- screenshot as a fraction of the texture's width.
	frame:SetSelection( {
		shapes = { { t = "rect", x = 0.25, y = 0.25, w = 0.5, h = 0.5, mode = "add" } },
	} )

	print( "AdvMat: selected the middle half of the texture (0.25 to 0.75 on " ..
		"both axes). It should sit dead centre with a quarter of the image " ..
		"showing on every side." )
end, nil, "Select exactly the middle half of the texture, as a placement test." )

---------------------------------------------------------------------------
-- Cross-layer material trace
---------------------------------------------------------------------------
-- The older save probe checks that a rule exists at each layer. That is not
-- enough when every layer is populated but they do not refer to the SAME rule,
-- or when the Lua key/value table is right and the live IMaterial is not. This
-- recorder follows one reproduction through the editor, every competing rule
-- scope, material construction, the engine sub-material string, the texture
-- CPU buffers and the canvas target. It writes JSON so the comparison can be
-- made after the menu (and all of its panel state) is gone.

local DT = AdvMat.DeepTrace or { events = {}, active = false }
AdvMat.DeepTrace = DT
AdvMat.DebugTraceActive = DT.active

local TRACE_FILE = "advmat/debug_trace.json"
local TRACE_LIMIT = 3000

local WATCH_VARS = {
	"$basetexture", "$bumpmap", "$phong", "$phongboost", "$phongexponent",
	"$phongexponenttexture", "$phongexponentfactor", "$phongalbedotint",
	"$phongalbedoboost", "$phongtint", "$phongfresnelranges",
	"$phongdisablehalflambert", "$rimlight", "$rimlightexponent",
	"$rimlightboost", "$translucent", "$alphatest", "$alpha", "$model", "$nodecal",
	"$envmap", "$envmaptint", "$envmapsaturation", "$flags", "$flags2",
}

local function Call( object, method, ... )
	if not object or not object[ method ] then return nil end
	local ok, value = pcall( object[ method ], object, ... )
	if not ok then return "<error: " .. tostring( value ) .. ">" end
	return value
end

local function JSONSafe( value, depth, seen )
	depth = depth or 0
	seen  = seen or {}

	if value == nil or isbool( value ) or isnumber( value ) or isstring( value ) then
		return value
	end

	if isvector( value ) or isangle( value ) then return tostring( value ) end
	if isentity( value ) then
		return IsValid( value ) and ( "Entity[" .. value:EntIndex() .. "]" ) or "<invalid entity>"
	end

	if not istable( value ) then return tostring( value ) end
	if depth >= 7 then return "<depth limit>" end
	if seen[ value ] then return "<cycle>" end

	seen[ value ] = true
	local out, count = {}, 0
	for key, item in pairs( value ) do
		count = count + 1
		if count > 400 then
			out[ "<truncated>" ] = count
			break
		end

		local safeKey = ( isstring( key ) or isnumber( key ) ) and key or tostring( key )
		out[ safeKey ] = JSONSafe( item, depth + 1, seen )
	end
	seen[ value ] = nil
	return out
end

--- Cheap enough to call while tracing a 2048 sheet: at most 8192 samples,
--- evenly spread over the complete image rather than only its first corner.
function AdvMat.DebugBufferStats( buf )
	if not istable( buf ) or not buf.w or not buf.h or not buf.r then return nil end

	local n    = math.max( 0, tonumber( buf.w ) * tonumber( buf.h ) )
	local step = math.max( 1, math.floor( n / 8192 ) )
	local count, sumR, sumG, sumB, sumA = 0, 0, 0, 0, 0
	local minA, maxA, zeroA, solidA, middleA = 255, 0, 0, 0, 0

	for i = 1, n, step do
		local r = tonumber( buf.r[ i ] ) or 0
		local g = tonumber( buf.g and buf.g[ i ] ) or 0
		local b = tonumber( buf.b and buf.b[ i ] ) or 0
		local a = tonumber( buf.a and buf.a[ i ] ) or 255

		count = count + 1
		sumR, sumG, sumB, sumA = sumR + r, sumG + g, sumB + b, sumA + a
		minA, maxA = math.min( minA, a ), math.max( maxA, a )
		if a <= 1 then zeroA = zeroA + 1
		elseif a >= 254 then solidA = solidA + 1
		else middleA = middleA + 1 end
	end

	local d = math.max( count, 1 )
	return {
		width = buf.w, height = buf.h, pixels = n, sampled = count,
		alpha_capable = buf.alpha,
		mean = {
			math.Round( sumR / d, 3 ), math.Round( sumG / d, 3 ),
			math.Round( sumB / d, 3 ), math.Round( sumA / d, 3 ),
		},
		alpha = { min = minA, max = maxA, zero = zeroA, middle = middleA, solid = solidA },
	}
end

local function LiveVar( mat, shader, key, rawValue )
	local def = AdvMat.GetParamDef( shader or "VertexLitGeneric", key )
	local kind = def and def.type or "string"
	local value

	if kind == "texture" then
		value = Call( mat, "GetTexture", key )
		if value and value.GetName then value = Call( value, "GetName" ) end
	elseif kind == "float" then
		value = Call( mat, "GetFloat", key )
	elseif kind == "int" or kind == "bool" then
		value = Call( mat, "GetInt", key )
	elseif kind == "color" or kind == "vector2" or kind == "vector3" or kind == "vector4" then
		-- pcall cannot suppress messages printed by the native material system.
		-- In particular, a material constructed from truncated colour shorthand
		-- can contain a scalar/string var; asking it for GetVector emits one
		-- warning per trace sample.  GetKeyValues already gave us its
		-- exact live representation, so only use the typed accessor when the
		-- runtime value proves that it really is a vector.
		if not isvector( rawValue ) then return AdvMat.ToVMTString( rawValue ) end
		value = Call( mat, "GetVector", key )
		if value ~= nil then value = tostring( value ) end
	else
		value = Call( mat, "GetString", key )
	end

	return value
end

function AdvMat.DebugMaterialState( mat, shader )
	if not mat then return nil end

	shader = shader or Call( mat, "GetShader" ) or "VertexLitGeneric"
	local state = {
		name = Call( mat, "GetName" ),
		shader = shader,
		error = Call( mat, "IsError" ),
		translucent = Call( mat, "IsTranslucent" ),
		vars = {},
	}

	local raw = Call( mat, "GetKeyValues" )
	if not istable( raw ) then raw = {} end

	for _, key in ipairs( WATCH_VARS ) do
		local rawValue = raw[ key ]
		if rawValue == nil then rawValue = raw[ string.sub( key, 2 ) ] end

		local live = LiveVar( mat, shader, key, rawValue )
		if rawValue ~= nil or live ~= nil then
			state.vars[ key ] = {
				table_value = AdvMat.ToVMTString( rawValue ),
				live_value = JSONSafe( live ),
			}
		end
	end

	return state
end

local function RuleState( rule )
	if not istable( rule ) then return nil end

	local out = {
		scope = tonumber( rule.scope ), key = rule.key, index = tonumber( rule.index ) or 0,
		mat = rule.mat, shader = rule.shader,
		params = table.Copy( rule.params or {} ),
		generators = {},
	}

	if rule.scope ~= AdvMat.SCOPE.WORLD and not AdvMat.RuleIsEmpty( rule ) then
		out.material_name = AdvMat.MaterialName( rule )
	end

	for key, recipe in pairs( rule.gen or {} ) do
		out.generators[ key ] = {
			kind = recipe.kind, src = recipe.src,
			file = AdvMat.Gen.FileName( recipe ),
			signature = AdvMat.Gen.Signature( recipe ),
		}
	end

	return out
end

local function BuiltState( rule )
	if not istable( rule ) or rule.scope == AdvMat.SCOPE.WORLD
		or AdvMat.RuleIsEmpty( rule ) then return nil end

	local name  = AdvMat.MaterialName( rule )
	local entry = AdvMat.Apply.Built[ name ]
	return {
		name = name,
		known = entry ~= nil,
		stored_kv = entry and table.Copy( entry.kv ) or nil,
		live = entry and AdvMat.DebugMaterialState( entry.mat, entry.shader ) or nil,
	}
end

local function SlotState( ent, index, targetRule )
	if not IsValid( ent ) then return { entity = "invalid", index = index } end

	index = tonumber( index ) or 0
	local ei    = ent:EntIndex()
	local mats  = ent:GetMaterials() or {}
	local path  = AdvMat.NormalizeMaterial( mats[ index + 1 ] or "" )
	local model = AdvMat.NormalizeModel( ent:GetModel() or "" )
	local C     = AdvMat.Client

	local entityRule = C.EntRules[ ei ] and C.EntRules[ ei ][ index ]
	local modelRule  = C.Rules[ AdvMat.RuleID( AdvMat.SCOPE.MODEL, model, index ) ]
	local materialRule = C.Rules[ AdvMat.RuleID( AdvMat.SCOPE.MATERIAL, path, index ) ]
	local effective = AdvMat.ResolveRule( ent, index, path, C.Rules, C.EntRules )
	local preview   = C.Preview[ ei ] and C.Preview[ ei ][ index ]
	local pending   = C.PendingSaves[ ei ] and C.PendingSaves[ ei ][ index ]
	local actual    = ent:GetSubMaterial( index ) or ""

	local out = {
		entity = ei, model = model, index = index, original_material = path,
		engine_submaterial = actual,
		clientside_material = AdvMat.Apply.ClientSet[ ei ]
			and AdvMat.Apply.ClientSet[ ei ][ index ] or nil,
		pending = pending and { id = pending.id, content = pending.content } or nil,
		rules = {
			preview = RuleState( preview ), entity = RuleState( entityRule ),
			model = RuleState( modelRule ), material = RuleState( materialRule ),
			effective_saved = RuleState( effective ), target = RuleState( targetRule ),
		},
		built = {
			preview = BuiltState( preview ), entity = BuiltState( entityRule ),
			model = BuiltState( modelRule ), material = BuiltState( materialRule ),
			effective_saved = BuiltState( effective ), target = BuiltState( targetRule ),
		},
	}

	local targetName = targetRule and not AdvMat.RuleIsEmpty( targetRule )
		and ( "!" .. AdvMat.MaterialName( targetRule ) ) or nil
	local effectiveName = effective and not AdvMat.RuleIsEmpty( effective )
		and ( "!" .. AdvMat.MaterialName( effective ) ) or nil

	out.expected_target_submaterial    = targetName
	out.expected_effective_submaterial = effectiveName
	out.engine_matches_target          = targetName and actual == targetName or nil
	out.engine_matches_effective       = effectiveName and actual == effectiveName or nil
	return out
end

local function RenderTargetRGB( rt, width, height )
	if not rt or not render.CapturePixels or not render.ReadPixel then return nil end

	width, height = math.max( tonumber( width ) or 1, 1 ), math.max( tonumber( height ) or 1, 1 )
	render.PushRenderTarget( rt )
	local ok, result = pcall( function()
		render.CapturePixels()

		local n, sumR, sumG, sumB = 0, 0, 0, 0
		local zero, nonzero = 0, 0
		for gy = 0, 15 do
			for gx = 0, 15 do
				local x = math.min( math.floor( ( gx + 0.5 ) * width / 16 ), width - 1 )
				local y = math.min( math.floor( ( gy + 0.5 ) * height / 16 ), height - 1 )
				local r, g, b = render.ReadPixel( x, y )
				r, g, b = tonumber( r ) or 0, tonumber( g ) or 0, tonumber( b ) or 0
				n, sumR, sumG, sumB = n + 1, sumR + r, sumG + g, sumB + b
				if r + g + b <= 3 then zero = zero + 1 else nonzero = nonzero + 1 end
			end
		end

		return {
			sampled = n, zero = zero, nonzero = nonzero,
			mean = { math.Round( sumR / n, 3 ), math.Round( sumG / n, 3 ),
				math.Round( sumB / n, 3 ) },
		}
	end )
	render.PopRenderTarget()

	return ok and result or { error = tostring( result ) }
end

local function TextureState()
	local frame = AdvMat.TexEditor
	if not IsValid( frame ) then return nil end

	local canvas = frame.Canvas
	local path   = frame.Recipe and frame.Recipe.src
	local out = {
		parameter = frame.Param, path = path,
		recipe_opaque = frame.Recipe and frame.Recipe.opaque or false,
		header_alpha = path and AdvMat.Gen.SourceHasAlpha( path ) or nil,
		work_size = { frame.WorkW, frame.WorkH },
		native_size = { frame.NativeW, frame.NativeH },
		buffer = AdvMat.DebugBufferStats( frame.Buf ),
		preview_material = AdvMat.DebugMaterialState( frame.PreviewMat,
			frame.Ctx and frame.Ctx.shader ),
	}

	if IsValid( canvas ) then
		out.canvas = {
			size = { canvas.SizeW, canvas.SizeH }, dirty = canvas.Dirty,
			pending_runs = canvas.Pending and #canvas.Pending or 0,
			cursor = canvas.Cursor,
			source = AdvMat.DebugBufferStats( canvas.Src ),
			buffer = AdvMat.DebugBufferStats( canvas.Buf ),
			target = canvas.RT and Call( canvas.RT, "GetName" ) or nil,
			gpu_rgb = RenderTargetRGB( canvas.RT, canvas.SizeW, canvas.SizeH ),
		}
	end

	if path and path ~= "" then
		out.base_material = AdvMat.DebugMaterialState( Material( path ) )
		out.opaque_sampler = AdvMat.DebugMaterialState( AdvMat.Gen.SourceMaterial( path, false ),
			"UnlitGeneric" )
		out.alpha_sampler = AdvMat.DebugMaterialState( AdvMat.Gen.SourceMaterial( path, true ),
			"UnlitGeneric" )
		out.source_cache = {}
		for key, src in pairs( AdvMat.Gen.Sources ) do
			if string.find( key, path, 1, true ) == 1 then
				out.source_cache[ key ] = AdvMat.DebugBufferStats( src )
			end
		end
	end

	local mp = frame.ModelPanel
	if IsValid( mp ) and IsValid( mp.Entity ) then
		out.model_preview_slot = SlotState( mp.Entity,
			frame.Ctx and frame.Ctx.slot or 0, nil )
	end

	return out
end

function AdvMat.DebugTraceEvent( tag, data )
	if not DT.active then return end

	if #DT.events >= TRACE_LIMIT then table.remove( DT.events, 1 ) end
	DT.events[ #DT.events + 1 ] = {
		t = math.Round( RealTime() - ( DT.started or RealTime() ), 6 ),
		frame = FrameNumber and FrameNumber() or nil,
		tag = tostring( tag ), data = JSONSafe( data ),
	}
end

function AdvMat.DebugTraceSnapshot( label, ent, index, targetRule )
	if not DT.active then return end

	local data = {
		label = label,
		serverside = GetConVar( "advmat_serverside" )
			and GetConVar( "advmat_serverside" ):GetBool() or nil,
		texture_editor = TextureState(),
	}

	if IsValid( ent ) then data.slot = SlotState( ent, index or 0, targetRule ) end
	AdvMat.DebugTraceEvent( "snapshot", data )
end

local function WriteDeepTrace()
	if not file.IsDir( "advmat", "DATA" ) then file.CreateDir( "advmat" ) end

	local payload = {
		version = 1,
		started_at = DT.startedAt,
		written_at = os.date( "!%Y-%m-%dT%H:%M:%SZ" ),
		events = DT.events,
	}

	local json = util.TableToJSON( payload, true )
	if not json then return false end
	file.Write( TRACE_FILE, json )
	return true
end

function AdvMat.DebugTraceCheckpoint()
	if not DT.active then return end
	WriteDeepTrace()
end

local function StartDeepTrace()
	DT.events    = {}
	DT.started   = RealTime()
	DT.startedAt = os.date( "!%Y-%m-%dT%H:%M:%SZ" )
	DT.active    = true
	AdvMat.DebugTraceActive = true
	net.Start( "AdvMat.DebugTrace" )
		net.WriteBool( true )
	net.SendToServer()

	AdvMat.DebugTraceSnapshot( "trace_started" )
	WriteDeepTrace()
	print( "AdvMat: deep trace recording. Reproduce Hair and the Phong save, then run advmat_debug_stop." )
	AdvMat.NotifyLocal( AdvMat.L( "notify.trace_started" ), NOTIFY_GENERIC, 5 )
end

local function StopDeepTrace()
	if not DT.active then
		print( "AdvMat: no deep trace is recording." )
		return
	end

	AdvMat.DebugTraceSnapshot( "trace_stopped" )
	local ok = WriteDeepTrace()
	DT.active = false
	AdvMat.DebugTraceActive = false
	net.Start( "AdvMat.DebugTrace" )
		net.WriteBool( false )
	net.SendToServer()

	print( ok
		and ( "AdvMat: wrote data/" .. TRACE_FILE )
		or  "AdvMat: could not encode the debug trace." )
	AdvMat.NotifyLocal( ok
		and AdvMat.L( "notify.trace_written", { path = TRACE_FILE } )
		or  AdvMat.L( "notify.trace_failed" ), ok and NOTIFY_GENERIC or NOTIFY_ERROR, 8 )
end

AdvMat.StartDebugTrace = StartDeepTrace
AdvMat.StopDebugTrace  = StopDeepTrace

net.Receive( "AdvMat.DebugTrace", function()
	local report = AdvMat.Net.ReadTable()
	if not DT.active or not istable( report ) then return end
	AdvMat.DebugTraceEvent( "server.save_state", report )
	WriteDeepTrace()
end )

concommand.Add( "advmat_debug_start", StartDeepTrace, nil,
	"Record texture buffers, competing rule scopes and live material variables." )
concommand.Add( "advmat_debug_stop", StopDeepTrace, nil,
	"Finish and write the Advanced Material Editor deep trace." )
concommand.Add( "advmat_debug_snapshot", function()
	if not DT.active then StartDeepTrace() end
	AdvMat.DebugTraceSnapshot( "manual" )
	WriteDeepTrace()
	print( "AdvMat: checkpoint written to data/" .. TRACE_FILE )
end, nil, "Write a checkpoint of the current Advanced Material Editor state." )
