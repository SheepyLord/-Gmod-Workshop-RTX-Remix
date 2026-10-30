--[[---------------------------------------------------------------------------
	Advanced Material Editor - reading textures, and writing images back out

	Garry's Mod has no image processing API, so this does the whole job by hand.
	It is the bottom of the generation pipeline: every kind of generated texture
	comes through here to be read, region-masked, encoded and written.

	  read     the source texture is drawn into a render target and copied back.
	           That is the only way to get at a VTF's pixels. Transparency is
	           recovered by drawing it twice over different backgrounds and
	           solving for the alpha, because a render target hands back none.

	  compute  each recipe kind has its own builder; the normal map one lives
	           here. A height field is taken from one channel, optionally
	           blurred and high-passed, then run through a gradient operator,
	           and the gradient becomes a tangent-space normal encoded the usual
	           way as n * 0.5 + 0.5.

	  region   whatever the recipe was not allowed to touch is put back to the
	           neutral value for that kind of map.

	  write    the result is encoded as a PNG and written to the data folder,
	           because Global.Material can load a PNG from there and file.Write
	           will not accept a .vtf into a path the material system searches.
	           The PNG is also something you can convert and ship with a model.

	The PNG encoder filters each row and then compresses with fixed Huffman
	coding and run length matching. It is not a general compressor - there is no
	string matcher - but after a row filter a smooth or flat area is a long run
	of zeroes, which is exactly what it is looking for. The alternative, storing
	the bytes uncompressed, writes an edited 1024 texture as four megabytes.

	Generation is queued rather than run inline, and the queue is drained from
	PreRender. That is not a performance choice: reading a render target only
	works INSIDE a render hook. Outside one there is no error and no warning -
	render.CapturePixels hands back an image filled with 0,0,0,255 - so anything
	that wants pixels from a panel callback or a timer has to ask GEN.PrimeSource
	and carry on when the read lands.
-----------------------------------------------------------------------------]]

AdvMat     = AdvMat or {}
AdvMat.Gen = AdvMat.Gen or {}

local GEN = AdvMat.Gen

GEN.Cache   = GEN.Cache   or {}   -- [file] = ITexture or false while unavailable
GEN.Sources = GEN.Sources or {}   -- [path .. "@" .. w .. "x" .. h] = { w, h, r, g, b, a }
GEN.Queue   = GEN.Queue   or {}
GEN.Busy    = false
GEN.Failed  = GEN.Failed  or {}   -- [file] = RealTime of the last failure
GEN.Told    = GEN.Told    or {}   -- [file] = the user has been told once
GEN.SourceAlpha = GEN.SourceAlpha or {} -- [material path] = VTF header says it has alpha

---------------------------------------------------------------------------
-- Frame budget
---------------------------------------------------------------------------
-- A queued build used to run start to finish inside one PreRender: the
-- source read, a million pixels of Lua arithmetic, the PNG encode. Finishing
-- a 1024 texture cost a visible hitch. It now runs as a coroutine that the
-- queue resumes once a frame, and the per-pixel loops offer to pause at row
-- boundaries once the frame's share has been spent.
--
-- Two things keep that safe. Render-target reads still happen inside
-- PreRender, because that is the only place the coroutine is ever resumed.
-- And no pause point sits between pushing and popping a render target: they
-- are only in plain arithmetic - Compute, the blurs, regions, the encoders.
GEN.FRAME_BUDGET = 0.004   -- seconds of generation work per frame

local buildThread, yieldAt = nil, math.huge
local job   -- the queued build in progress: { recipe, thread }

local function Clock() return ( SysTime or os.clock )() end

--- Offer to pause the queued build until the next frame. Anywhere else it
--- does nothing, so the same code still runs straight through when it is
--- called directly - the texture editor's own export, the tests.
function GEN.Yield()
	if buildThread == nil or coroutine.running() ~= buildThread then return end
	if Clock() < yieldAt then return end
	coroutine.yield()
end

-- The source cache is bounded by PIXELS rather than by entries, because the
-- entries are no longer all the same size. Six 4096 x 2048 reads would be a
-- gigabyte and a half of Lua tables; six 256 pixel ones are a rounding error.
--
-- Roughly one full size oblong sheet, or thirty small ones.
local MAX_SOURCE_PIXELS = 8 * 1024 * 1024

-- Never reused, so a derived cache can key on it safely.
local sourceSerial = 0

---------------------------------------------------------------------------
-- Reading a texture's pixels
---------------------------------------------------------------------------

local sourceMats = {}

--- Whether the mounted VTF itself declares a one-bit or eight-bit alpha
--- channel.  This is more reliable than inferring transparency by drawing a
--- material: a DXT1 texture behind an erroneous $alphatest VMT can render as
--- fully transparent as soon as the sampling material enables translucency.
---
--- Returns nil when the source is not a readable VTF (for example a data PNG),
--- in which case the caller keeps the material-level decision.
function GEN.SourceHasAlpha( path )
	path = AdvMat.NormalizeMaterial( path or "" )
	if path == "" then return nil end

	local cached = GEN.SourceAlpha[ path ]
	if cached ~= nil then return cached end

	-- An imported image says in its own header whether it carries alpha, and
	-- the answer matters: without it an RGBA picture on an opaque material
	-- would be read without the mask bytes it brought.
	if AdvMat.Import and AdvMat.Import.IsSource( path ) then
		local alpha = AdvMat.Import.HasAlpha( path )
		if alpha ~= nil then GEN.SourceAlpha[ path ] = alpha end
		return alpha
	end

	if not file.Open then return nil end

	local f = file.Open( "materials/" .. path .. ".vtf", "rb", "GAME" )
	if not f then return nil end

	local ok, hasAlpha = pcall( function()
		if f:Read( 4 ) ~= "VTF\0" then return nil end
		f:Seek( 20 ) -- signature + version + header size + width + height

		local flags = f:ReadULong()
		if not isnumber( flags ) then return nil end

		local oneBit   = math.floor( flags / 0x1000 ) % 2 == 1
		local eightBit = math.floor( flags / 0x2000 ) % 2 == 1
		return oneBit or eightBit
	end )

	pcall( f.Close, f )
	if not ok or hasAlpha == nil then return nil end

	GEN.SourceAlpha[ path ] = hasAlpha
	if not hasAlpha then
		AdvMat.Log( "%s.vtf declares no alpha channel; sampling it as opaque.", path )
	end

	return hasAlpha
end

--- Combine what the VMT asks the shader to do with what the texture can
--- actually contain.  A definite VTF answer overrides a mistaken VMT flag;
--- unknown source types retain the caller's choice.
function GEN.ShouldReadAlpha( path, materialShowsAlpha )
	if not materialShowsAlpha then return false end
	return GEN.SourceHasAlpha( path ) ~= false
end

--- A flat, unlit material for `path`, used only to sample the raw texture.
---
--- `translucent` builds the variant that honours the texture's alpha channel
--- when it is drawn, which is what makes the two pass alpha recovery below
--- work. It has to be a separate material because $translucent lives in the
--- $flags bitfield and cannot be turned on after the fact.
function GEN.SourceMaterial( path, translucent )
	local key = ( translucent and "t:" or "o:" ) .. path
	local hit = sourceMats[ key ]
	if hit then return hit end

	local kv = {
		[ "$basetexture" ] = path,
		[ "$nolod" ]       = "1",
		[ "$ignorez" ]     = "1",
		[ "$nocull" ]      = "1",
		[ "$vertexalpha" ] = "1",
		[ "$vertexcolor" ] = "1",
	}

	if translucent then kv[ "$translucent" ] = "1" end

	-- An imported image is a PNG or JPEG in data/, which a material can name
	-- only once Global.Material has loaded it and registered its texture under
	-- that texture's own name. The sampler is born pointing at it, as every
	-- sampled texture here must be (the half-texel note in cl_72_canvas.lua),
	-- and is handed the texture as well, the way the texture editor's RTX
	-- preview does. One that is not on this computer has nothing to sample.
	local imported
	if AdvMat.Import and AdvMat.Import.IsSource( path ) then
		local _, tex = AdvMat.Import.Material( path )
		if not tex then return nil end

		imported = tex
		kv[ "$basetexture" ] = tex:GetName()
	end

	local mat = CreateMaterial(
		"advmat_gensrc_mat_" .. ( translucent and "t" or "o" ) .. util.CRC( path ),
		"UnlitGeneric", kv )

	if imported and mat then mat:SetTexture( "$basetexture", imported ) end

	sourceMats[ key ] = mat
	return mat
end

-- `render.Capture` predates its packed RGB output on some engine branches.
-- Merely finding the function therefore does not prove that `format = "rgb"`
-- is usable. Probe one pixel once and share the result with every generator
-- that depends on a raw readback.
local rawRGBCaptureSupported

local function TryCaptureRawRGB( w, h )
	-- No capture entry point at all is a stable property of this engine branch.
	if not render or not isfunction( render.Capture ) then return nil, false end

	w = math.max( 1, math.floor( tonumber( w ) or 0 ) )
	h = math.max( 1, math.floor( tonumber( h ) or 0 ) )

	local ok, data = pcall( render.Capture, {
		format = "rgb",
		x = 0, y = 0, w = w, h = h,
		alpha = false,
	} )

	-- An older implementation may ignore the requested format and hand back
	-- some other encoded image. Accepting a prefix of that data would silently
	-- turn its header into pixels, so the packed buffer must be exact.
	-- A nil/empty result or an exception is not a capability answer. The same
	-- supported engine does this transiently while capture is unavailable (most
	-- visibly under the escape menu), so leave the probe unknown and retry later.
	if not ok or data == nil or data == "" then return nil, nil end

	-- A real response in another representation is conclusive: this branch has
	-- `render.Capture`, but did not honour packed RGB. This includes older builds
	-- that return an encoded PNG despite the requested format.
	if not isstring( data ) or #data ~= w * h * 3 then return nil, false end
	return data, true
end

function GEN.CanCaptureRawRGB()
	if rawRGBCaptureSupported ~= nil then return rawRGBCaptureSupported end

	local _, supported = TryCaptureRawRGB( 1, 1 )
	if supported == nil and render and isfunction( render.Capture ) then
		-- A nil raw reply is ambiguous: old PNG-only branches reject the format,
		-- while supported branches also return nil when capture is temporarily
		-- blocked (notably under the escape menu). A successful ordinary PNG
		-- control capture proves the renderer is active, making that raw refusal
		-- conclusively unsupported. If the control is refused too, keep the probe
		-- unknown so the generation queue retries instead of caching a degraded
		-- compatibility image under the full-resolution recipe identity.
		local controlOK, control = pcall( render.Capture, {
			format = "png", x = 0, y = 0, w = 1, h = 1, alpha = false,
		} )
		if controlOK and isstring( control ) and #control > 0 then supported = false end
	end
	if supported ~= nil then rawRGBCaptureSupported = supported end
	return supported
end

function GEN.CaptureRawRGB( w, h )
	if GEN.CanCaptureRawRGB() ~= true then return nil end

	local data, supported = TryCaptureRawRGB( w, h )
	-- A conclusive format mismatch discovered at the real dimensions supersedes
	-- the tiny probe. A transient refusal does not erase a proven capability.
	if supported == false then rawRGBCaptureSupported = false end
	return data
end

-- Capability is stable for a running engine. Resetting alongside the generated
-- cache still gives renderer/client changes an explicit way to force a re-probe
-- without reloading this file.
function GEN.ResetRawRGBCaptureProbe()
	rawRGBCaptureSupported = nil
end

--- Copy the pushed render target back in one call.
---
--- render.Capture with a raw byte format is a single readback of the whole
--- image instead of a quarter of a million round trips through render.ReadPixel,
--- which is the difference between a hitch and a freeze at 512 pixels square.
--- It is a recent addition, and it also returns nothing while the escape menu
--- is open, so the per pixel path stays as the fallback.
local function CaptureBulk( w, h, r, g, b )
	local data = GEN.CaptureRawRGB( w, h )
	if not data then return false end

	local byte = string.byte
	local i, o = 1, 1

	for _ = 1, w * h do
		-- Rows run top to bottom and left to right, which is the order the
		-- arrays are indexed in.
		r[ i ], g[ i ], b[ i ] = byte( data, o, o + 2 )
		i = i + 1
		o = o + 3
	end

	return true
end

--- One draw of `mat` over a solid grey background, copied back into r/g/b.
--- The render target must already be pushed.
local function ReadPass( mat, w, h, bg, r, g, b )
	render.Clear( bg, bg, bg, 255, true, true )

	-- Everything, the readback included, happens inside the 2D context. A
	-- capture taken outside one comes back as a solid 0,0,0,255 image, which
	-- is exactly the "read back as one flat colour" failure this file warns
	-- about further down.
	cam.Start2D()
		surface.SetDrawColor( 255, 255, 255, 255 )
		surface.SetMaterial( mat )
		surface.DrawTexturedRect( 0, 0, w, h )

		if not CaptureBulk( w, h, r, g, b ) then
			render.CapturePixels()

			local i = 1
			for y = 0, h - 1 do
				for x = 0, w - 1 do
					local pr, pg, pb = render.ReadPixel( x, y )
					r[ i ], g[ i ], b[ i ] = pr, pg, pb
					i = i + 1
				end
			end
		end
	cam.End2D()
end

--- Draw `path` into a render target and copy it back as four flat arrays.
---
--- Must be called from INSIDE a render hook. Outside one the capture comes back
--- solid black with nothing to say it failed, so anywhere else should go
--- through GEN.PrimeSource instead.
---
--- `wantAlpha` recovers the texture's alpha channel as well, which costs a
--- second pass. render.ReadPixel does not hand back a usable alpha from a
--- render target, so it is solved with arithmetic instead: the texture is
--- drawn once over black and once over white, and
---
---     over black : c*a
---     over white : c*a + 255*(1-a)
---
--- so the difference between the two is 255*(1-a) and nothing else. That
--- gives alpha exactly, and dividing the black pass by it gives the straight
--- (un-premultiplied) colour back. A texture with no alpha channel draws
--- identically over both backgrounds, so it correctly comes out fully opaque.
function GEN.ReadSource( path, w, h, wantAlpha, maskAlpha )
	path = AdvMat.NormalizeMaterial( path )
	if path == "" then return nil end

	-- Mask mode is stricter than ordinary transparency recovery. It is only
	-- meaningful for a mounted texture whose header definitely contains alpha;
	-- otherwise synthetic/RGB-only sources would be needlessly promoted to
	-- RGBA. The translucent sampler recovers A, while a separate opaque sampler
	-- below supplies RGB even where that mask is zero.
	local headerAlpha = GEN.SourceHasAlpha( path )
	maskAlpha = maskAlpha == true and headerAlpha == true
	wantAlpha = GEN.ShouldReadAlpha( path, wantAlpha or maskAlpha )
	if not wantAlpha then maskAlpha = false end

	if AdvMat.DebugTraceActive and AdvMat.DebugTraceEvent then
		AdvMat.DebugTraceEvent( "source.read_begin", {
			path = path, width = w, height = h or w, alpha = wantAlpha,
			mask_alpha = maskAlpha, header_alpha = headerAlpha,
		} )
	end

	h = h or w

	local key = path .. "@" .. w .. "x" .. h
		.. ( maskAlpha and "+m" or ( wantAlpha and "+a" or "" ) )
	local cached = GEN.Sources[ key ]
	if cached then return cached end

	-- Drawn through a flat UnlitGeneric stand-in rather than the model's own
	-- material, so what comes back is the texture itself and not the result of
	-- whatever $color2, $phong or lightwarp the .vmt happens to carry.
	local mat = GEN.SourceMaterial( path, wantAlpha )
	if not mat or mat:IsError() then return nil end

	-- Named for both dimensions: GetRenderTarget hands back whatever is already
	-- registered under a name, so one name for two shapes would quietly give
	-- the second caller the first one's target.
	local rt = GetRenderTarget( "advmat_gensrc_" .. w .. "x" .. h, w, h )
	if not rt then return nil end

	local r, g, b, a = {}, {}, {}, {}
	local n = w * h

	-- A read at the top of the ladder is several seconds of frozen game and a
	-- few hundred megabytes of Lua tables. Saying so before it happens means
	-- the pause has an explanation in the console instead of looking like a
	-- hang, which is the difference between a cost and a bug.
	if n > GEN.HEAVY_PIXELS then
		AdvMat.Log( "Reading %s at %d x %d - %d pixels. This will pause for a moment.",
			path, w, h, n )
	end

	-- The pop has to happen whatever goes wrong in between. An unbalanced
	-- render target stack does not fail here, it corrupts everything drawn
	-- afterwards, which is a miserable thing to track down.
	render.PushRenderTarget( rt )

	-- Whether the alpha that was asked for actually came back usable. It is
	-- part of what gets cached, because the canvas draws the source through a
	-- material chosen by this answer.
	local alphaGood = wantAlpha or false

	local ok, err = pcall( function()
		ReadPass( mat, w, h, 0, r, g, b )

		if not wantAlpha then
			for i = 1, n do a[ i ] = 255 end
			return
		end

		local wr, wg, wb = {}, {}, {}
		ReadPass( mat, w, h, 255, wr, wg, wb )

		for i = 1, n do
			-- Averaging the three channels cancels most of the per channel
			-- rounding the render target introduced.
			local d  = ( ( wr[ i ] - r[ i ] ) + ( wg[ i ] - g[ i ] ) + ( wb[ i ] - b[ i ] ) ) / 3
			local av = math.Clamp( 255 - d, 0, 255 )

			a[ i ] = math.floor( av + 0.5 )

			-- Below about 2% coverage the division amplifies rounding noise
			-- into wild colours. The colour under a pixel that transparent is
			-- not visible anyway, so it is left premultiplied.
			if av > 5 then
				local s = 255 / av
				r[ i ] = math.min( 255, math.floor( r[ i ] * s + 0.5 ) )
				g[ i ] = math.min( 255, math.floor( g[ i ] * s + 0.5 ) )
				b[ i ] = math.min( 255, math.floor( b[ i ] * s + 0.5 ) )
			end
		end

		-- A recovery that says the whole texture is invisible is never the
		-- truth - see AlphaLooksEmpty for the two ways it happens. Rather
		-- than hand an invisible image to an editor that will faithfully
		-- display nothing, the texture is read again the plain way: one
		-- opaque pass, alpha solid. This is measured, not hypothetical: a
		-- DXT1 sheet in a set of otherwise identical DXT5 ones came back
		-- empty through the translucent path on a real build while drawing
		-- perfectly in game.
		if not maskAlpha and GEN.AlphaLooksEmpty( a, n ) then
			AdvMat.Log( "%s recovered as fully transparent, which cannot be "
				.. "right; reading it as opaque instead. (Its format may have "
				.. "no alpha channel, whatever the .vmt says.)", path )

			alphaGood = false

			local matO = GEN.SourceMaterial( path, false )

			if matO and not matO:IsError() then
				ReadPass( matO, w, h, 0, r, g, b )
			end

			for i = 1, n do a[ i ] = 255 end
		elseif maskAlpha then
			-- With shader-mask alpha, RGB remains visible even at A=0. The
			-- black/white recovery above cannot reconstruct colour at zero
			-- coverage, so replace RGB with the texture sampled opaquely while
			-- retaining the independently recovered mask bytes.
			local matO = GEN.SourceMaterial( path, false )
			if not matO or matO:IsError() then
				error( "could not read opaque colour from " .. path )
			end
			ReadPass( matO, w, h, 0, r, g, b )
		end
	end )

	render.PopRenderTarget()

	if not ok then
		AdvMat.Log( "Could not read %s: %s", path, tostring( err ) )
		return nil
	end

	-- A completely uniform read is almost always a failed copy back from the
	-- render target rather than a genuinely flat texture, and it would produce
	-- a normal map that is silently flat. Worth saying out loud, because
	-- readback is the one part of this that a replaced renderer might not
	-- support.
	local flat = true

	for i = 2, #r do
		if r[ i ] ~= r[ 1 ] or g[ i ] ~= g[ 1 ] or b[ i ] ~= b[ 1 ] then
			flat = false
			break
		end
	end

	if flat then
		AdvMat.Log( "%s read back as one flat colour. If the texture is not " ..
			"actually flat then this build cannot copy pixels out of a render " ..
			"target, and the generator cannot work here.", path )
	end

	-- `id` is what anything caching values DERIVED from these pixels keys on.
	-- A table address is not safe for that: this table can be dropped when the
	-- source cache is trimmed, and a later read can land on the same address
	-- and quietly inherit the old entry.
	sourceSerial = sourceSerial + 1

	local src = {
		w = w, h = h,
		r = r, g = g, b = b, a = a,
		alpha = alphaGood,
		maskalpha = maskAlpha,
		id    = sourceSerial,
	}

	-- Bound the cache by area, not by entry count: each 1024 source is four
	-- arrays of a million numbers and each 4096 one is sixteen times that.
	local held = 0
	for _, entry in pairs( GEN.Sources ) do held = held + entry.w * entry.h end
	if held + n > MAX_SOURCE_PIXELS then GEN.Sources = {} end

	GEN.Sources[ key ] = src

	if AdvMat.DebugTraceActive and AdvMat.DebugTraceEvent then
		AdvMat.DebugTraceEvent( "source.read_complete", {
			path = path, cache_key = key,
			stats = AdvMat.DebugBufferStats and AdvMat.DebugBufferStats( src ) or nil,
		} )
	end

	return src
end

--- The largest offered size that fits inside `native`, so a texture is read at
--- its own resolution and never invented above it.
local function FitSize( native )
	local best = GEN.SIZES[ 1 ]

	for _, size in ipairs( GEN.SIZES ) do
		if size <= native then best = size end
	end

	return best
end

--- The texture's own resolution, snapped to sizes the generators can work at.
---
--- Both axes independently, because 4096 x 2048 is a perfectly ordinary sheet
--- and squeezing one into a square stretches everything on it by a factor of
--- two - which puts every mask built from it in the wrong place on the model.
---
--- This is the default for everything generated from a texture, and it is the
--- default deliberately. A mask built at 512 and laid over a 2048 material is
--- soft exactly where the material is sharp, and that is the kind of fault that
--- is obvious in game and invisible in the dialog that produced it.
function GEN.SourceSize( path, fallbackW, fallbackH )
	fallbackW = fallbackW or 512
	fallbackH = fallbackH or fallbackW

	path = AdvMat.NormalizeMaterial( path or "" )
	if path == "" then return fallbackW, fallbackH end

	-- Through the importer for an imported image, which never asks the engine
	-- about a file this computer does not have.
	local mat
	if AdvMat.Import and AdvMat.Import.IsSource( path ) then
		mat = AdvMat.Import.Material( path )
	else
		mat = Material( path )
	end
	if not mat or mat:IsError() then return fallbackW, fallbackH end

	-- Both dimensions inside one guard: a texture object missing one of these
	-- accessors is missing both, and the .vmt may name a texture that is not
	-- there at all.
	local ok, nw, nh = pcall( function()
		local tex = mat:GetTexture( "$basetexture" )
		if not tex or not tex.Width then return nil end
		return tex:Width(), tex:Height()
	end )

	if not ok or not nw or nw <= 0 then nw, nh = mat:Width(), mat:Height() end
	if not nw or nw <= 0 then return fallbackW, fallbackH end
	if not nh or nh <= 0 then nh = nw end

	-- The ceiling is applied to the PAIR, not to each axis: holding each one
	-- under 1024 separately turns 4096 x 2048 into 1024 x 1024, which is the
	-- oblong sheet squashed into a square. Shrinking both together keeps the
	-- shape and costs the user exactly what they agreed to.
	return GEN.FitWithin( FitSize( nw ), FitSize( nh ), GEN.MaxSize() )
end

--- The resolution list a dialog offers for something generated from `src`.
---
--- The texture's own resolution first and successive halvings of it after,
--- rather than a fixed list of squares. Every entry is therefore the right
--- SHAPE, and the top one is the only size that neither throws detail away nor
--- invents any - which is why it is the default.
---
--- Entries are { id = { w, h }, name = text, on = it is the current one }.
function GEN.SizeMenu( src, curW, curH )
	curH = curH or curW

	local nw, nh = GEN.SourceSize( src, curW or 512, curH or 512 )

	local out, seen = {}, {}

	local function Add( aw, ah )
		local key = aw .. "x" .. ah
		if seen[ key ] then return end
		seen[ key ] = true

		local name = GEN.DimText( aw, ah )

		-- Said in the list rather than after the event: at the top of the
		-- ladder a build is several seconds of frozen game and a few hundred
		-- megabytes of Lua tables, and that is worth knowing before choosing.
		if aw * ah > GEN.HEAVY_PIXELS then name = name .. "  (slow)" end

		out[ #out + 1 ] = {
			id = { aw, ah }, name = name,
			on = ( aw == curW and ah == curH ),
		}
	end

	local w, h = nw, nh

	while w >= 128 and h >= 128 and #out < 8 do
		Add( w, h )
		w, h = math.floor( w / 2 ), math.floor( h / 2 )
	end

	-- A source smaller than the smallest step still gets to be itself, and a
	-- recipe reopened at a size this source no longer offers still has to be
	-- able to show what it is set to.
	if #out == 0 then Add( nw, nh ) end
	if curW then Add( curW, curH ) end

	return out
end

function GEN.FlushSources()
	GEN.Sources = {}

	-- Anything derived from those pixels is now stale too.
	hook.Run( "AdvMatSourcesFlushed" )
end

---------------------------------------------------------------------------
-- Asking for pixels from outside a render hook
---------------------------------------------------------------------------
-- Reading a render target only works inside a render hook. Outside one there
-- is no error and no warning: render.CapturePixels simply hands back an image
-- filled with 0,0,0,255, so everything downstream quietly operates on black.
--
-- That makes GEN.ReadSource unsafe to call from a panel callback, a timer or a
-- console command - which is most of the editor. Anything in that position
-- asks here instead and carries on in the callback, and the read itself happens
-- on the next frame inside PreRender along with the rest of the queue.

GEN.SourceQueue = GEN.SourceQueue or {}

function GEN.PrimeSource( path, w, h, wantAlpha, maskAlpha, done )
	-- Keep the established five-argument form source-compatible.
	if isfunction( maskAlpha ) then
		done, maskAlpha = maskAlpha, false
	end

	path = AdvMat.NormalizeMaterial( path or "" )

	if path == "" then
		if done then done( nil ) end
		return
	end

	h = h or w

	local headerAlpha = GEN.SourceHasAlpha( path )
	maskAlpha = maskAlpha == true and headerAlpha == true
	wantAlpha = GEN.ShouldReadAlpha( path, wantAlpha or maskAlpha )
	local key = path .. "@" .. w .. "x" .. h
		.. ( maskAlpha and "+m" or ( wantAlpha and "+a" or "" ) )
	local hit = GEN.Sources[ key ]

	-- Already read: no reason to wait a frame.
	if hit then
		if done then done( hit ) end
		return
	end

	for _, queued in ipairs( GEN.SourceQueue ) do
		if queued.key == key then
			queued.also = queued.also or {}
			queued.also[ #queued.also + 1 ] = done
			return
		end
	end

	GEN.SourceQueue[ #GEN.SourceQueue + 1 ] = {
		key = key, path = path, w = w, h = h, alpha = wantAlpha,
		maskalpha = maskAlpha, done = done,
	}
end

---------------------------------------------------------------------------
-- Height field
---------------------------------------------------------------------------
local function HeightField( src, recipe )
	local n   = src.w * src.h
	local r, g, b, a = src.r, src.g, src.b, src.a
	local out = {}

	local channel = recipe.channel

	if channel == "red" then
		for i = 1, n do out[ i ] = r[ i ] / 255 end
	elseif channel == "green" then
		for i = 1, n do out[ i ] = g[ i ] / 255 end
	elseif channel == "blue" then
		for i = 1, n do out[ i ] = b[ i ] / 255 end
	elseif channel == "alpha" then
		for i = 1, n do out[ i ] = a[ i ] / 255 end
	elseif channel == "average" then
		for i = 1, n do out[ i ] = ( r[ i ] + g[ i ] + b[ i ] ) / 765 end
	else
		-- Rec. 601 luma, which tracks perceived brightness far better than a
		-- flat average and is what image tools use for this.
		for i = 1, n do
			out[ i ] = ( r[ i ] * 0.299 + g[ i ] * 0.587 + b[ i ] * 0.114 ) / 255
		end
	end

	if recipe.inverth then
		for i = 1, n do out[ i ] = 1 - out[ i ] end
	end

	return out
end

--- Separable box blur. Radius is in pixels; two passes over a flat array.
local function BoxBlur( field, w, h, radius, wrap )
	if radius < 1 then return field end

	local span = radius * 2 + 1
	local tmp, out = {}, {}

	local function Wrap( v, limit )
		if wrap then return v % limit end
		return math.Clamp( v, 0, limit - 1 )
	end

	for y = 0, h - 1 do
		GEN.Yield()
		local row = y * w
		for x = 0, w - 1 do
			local sum = 0
			for k = -radius, radius do
				sum = sum + field[ row + Wrap( x + k, w ) + 1 ]
			end
			tmp[ row + x + 1 ] = sum / span
		end
	end

	for y = 0, h - 1 do
		GEN.Yield()
		for x = 0, w - 1 do
			local sum = 0
			for k = -radius, radius do
				sum = sum + tmp[ Wrap( y + k, h ) * w + x + 1 ]
			end
			out[ y * w + x + 1 ] = sum / span
		end
	end

	return out
end

--- Build smooth, seeded variation for a scalar height field.
---
--- The lattice is expressed in texture-relative coordinates rather than
--- pixels. A 128px preview and a 2048px build therefore show the same broad
--- pattern instead of choosing unrelated random pixels. With wrapping on, the
--- last lattice cell blends back into the first so the generated surface tiles.
local function UnevenHeight( w, h, uneven, wrap, invertHeight )
	local amount = uneven and uneven.amount or 0
	if amount <= 0 then return nil end

	local scale = math.max( 2, math.floor( uneven.scale or 12 ) )
	local seed  = math.floor( uneven.seed or 1 )
	local cellsX, cellsY

	if w >= h then
		cellsX = scale
		cellsY = math.max( 2, math.floor( scale * h / math.max( w, 1 ) + 0.5 ) )
	else
		cellsY = scale
		cellsX = math.max( 2, math.floor( scale * w / math.max( h, 1 ) + 0.5 ) )
	end

	-- Hashing a small lattice once is much cheaper than hashing four corners
	-- for every output pixel. It also avoids math.random, whose global sequence
	-- depends on unrelated addons and would make recipe builds disagree.
	local function Hash( x, y )
		local value = bit.bxor( x * 374761393, y * 668265263 )
		value = bit.bxor( value, seed * 40503 )
		value = bit.bxor( value, -1640531527 ) -- 0x9E3779B9
		value = bit.bxor( value, bit.lshift( value, 13 ) )
		value = bit.bxor( value, bit.rshift( value, 17 ) )
		value = bit.bxor( value, bit.lshift( value, 5 ) )
		return bit.band( value, 0xFFFF ) / 65535
	end

	local latticeW = wrap and cellsX or cellsX + 1
	local latticeH = wrap and cellsY or cellsY + 1
	local lattice = {}

	for y = 0, latticeH - 1 do
		for x = 0, latticeW - 1 do
			lattice[ y * latticeW + x + 1 ] = Hash( x, y )
		end
	end

	local function Axis( pixels, cells )
		local lo, hi, blend = {}, {}, {}
		local divisor = wrap and math.max( pixels, 1 ) or math.max( pixels - 1, 1 )

		for pixel = 0, pixels - 1 do
			local at = pixel * cells / divisor
			local first = math.floor( at )
			local t = at - first

			if wrap then
				first = first % cells
				lo[ pixel + 1 ] = first
				hi[ pixel + 1 ] = ( first + 1 ) % cells
			else
				first = math.min( first, cells )
				lo[ pixel + 1 ] = first
				hi[ pixel + 1 ] = math.min( first + 1, cells )
			end

			-- Smoothstep removes the sharp derivative at every lattice boundary.
			blend[ pixel + 1 ] = t * t * ( 3 - 2 * t )
		end

		return lo, hi, blend
	end

	local x0, x1, tx = Axis( w, cellsX )
	local y0, y1, ty = Axis( h, cellsY )
	local direction = invertHeight and -1 or 1
	local out = {}

	for y = 0, h - 1 do
		GEN.Yield()
		local ay, by = y0[ y + 1 ], y1[ y + 1 ]
		local fy = ty[ y + 1 ]
		local rowA, rowB = ay * latticeW, by * latticeW

		for x = 0, w - 1 do
			local ax, bx = x0[ x + 1 ], x1[ x + 1 ]
			local fx = tx[ x + 1 ]
			local top = lattice[ rowA + ax + 1 ]
				+ ( lattice[ rowA + bx + 1 ] - lattice[ rowA + ax + 1 ] ) * fx
			local bottom = lattice[ rowB + ax + 1 ]
				+ ( lattice[ rowB + bx + 1 ] - lattice[ rowB + ax + 1 ] ) * fx
			local noise = top + ( bottom - top ) * fy
			local i = y * w + x + 1

			out[ i ] = ( noise - 0.5 ) * amount * direction
		end
	end

	return out
end

---------------------------------------------------------------------------
-- Gradient operators
---------------------------------------------------------------------------
-- Each kernel is listed row by row from the top left, together with the
-- divisor that brings a 0..1 height field back to roughly a 0..1 gradient.
local KERNELS = {
	sobel3 = {
		size = 1, div = 4,
		x = {  -1,  0,  1,   -2, 0, 2,   -1, 0, 1 },
		y = {  -1, -2, -1,    0, 0, 0,    1, 2, 1 },
	},
	scharr3 = {
		size = 1, div = 16,
		x = {  -3,   0,   3,  -10, 0, 10,   -3, 0, 3 },
		y = {  -3, -10,  -3,    0, 0,  0,    3, 10, 3 },
	},
	prewitt3 = {
		size = 1, div = 3,
		x = {  -1, 0, 1,  -1, 0, 1,  -1, 0, 1 },
		y = {  -1, -1, -1,  0, 0, 0,   1, 1, 1 },
	},
	sobel5 = {
		-- 48, not 24: the divisor is the sum of the kernel's positive weights,
		-- which is what brings a full black-to-white step back to a gradient of
		-- one. 2+1 + 8+4 + 12+6 + 8+4 + 2+1 = 48. With half that, this operator
		-- leaned twice as far as the other three at the same strength, so
		-- changing filter silently changed the intensity too.
		size = 2, div = 48,
		x = {
			-1,  -2, 0,  2, 1,
			-4,  -8, 0,  8, 4,
			-6, -12, 0, 12, 6,
			-4,  -8, 0,  8, 4,
			-1,  -2, 0,  2, 1,
		},
		y = {
			-1, -4,  -6, -4, -1,
			-2, -8, -12, -8, -2,
			 0,  0,   0,  0,  0,
			 2,  8,  12,  8,  2,
			 1,  4,   6,  4,  1,
		},
	},
}

---------------------------------------------------------------------------
-- The normal map itself
---------------------------------------------------------------------------

--- Turn a source into a flat array of RGB bytes. Returns pixels, width.
function GEN.Compute( src, recipe )
	local w, h = src.w, src.h
	local wrap = recipe.wrap

	local field = HeightField( src, recipe )

	if recipe.blur > 0 then
		field = BoxBlur( field, w, h, recipe.blur, wrap )
	end

	-- High pass: add back the difference against a heavily blurred copy, which
	-- sharpens fine surface detail without changing the overall shape.
	if recipe.detail > 0 then
		local base   = BoxBlur( field, w, h, math.max( 2, recipe.blur + 3 ), wrap )
		local amount = recipe.detail
		local sharp  = {}

		for i = 1, w * h do
			sharp[ i ] = math.Clamp( field[ i ] + ( field[ i ] - base[ i ] ) * amount * 4, 0, 1 )
		end

		field = sharp
	end

	local uneven = recipe.uneven
		and UnevenHeight( w, h, recipe.uneven, wrap, recipe.inverth ) or nil

	-- Fold the texture-relative variation into one height field per axis. This
	-- keeps its apparent slope independent of output resolution while avoiding
	-- a second pair of kernel accumulators at every sample. Reusing the two
	-- existing tables also avoids another full-image allocation at 4K.
	if uneven then
		for i = 1, w * h do
			local base, variation = field[ i ], uneven[ i ]
			field[ i ]  = base + variation * w / 128
			uneven[ i ] = base + variation * h / 128
		end
	end

	local k      = KERNELS[ recipe.filter ] or KERNELS.sobel3
	local radius = k.size
	local kx, ky = k.x, k.y
	local div    = k.div

	local strength = recipe.strength
	local signX    = recipe.invertx and -1 or 1
	local signY    = recipe.inverty and -1 or 1

	local px = {}
	local o  = 1

	for y = 0, h - 1 do
		GEN.Yield()
		for x = 0, w - 1 do
			local dx, dy, ki = 0, 0, 1

			for oy = -radius, radius do
				local sy
				if wrap then
					sy = ( y + oy ) % h
				else
					sy = math.Clamp( y + oy, 0, h - 1 )
				end

				local rowBase = sy * w

				for ox = -radius, radius do
					local sx
					if wrap then
						sx = ( x + ox ) % w
					else
						sx = math.Clamp( x + ox, 0, w - 1 )
					end

					local at = rowBase + sx + 1
					local vx = field[ at ]
					local vy = uneven and uneven[ at ] or vx
					dx = dx + vx * kx[ ki ]
					dy = dy + vy * ky[ ki ]
					ki = ki + 1
				end
			end

			-- A height increase to the right must tilt the normal left, hence
			-- the negation. Z is fixed at 1 and the whole vector normalised,
			-- so `strength` controls how far the normal leans.
			local nx = -( dx / div ) * strength * signX
			local ny = -( dy / div ) * strength * signY
			local nz = 1

			local len = math.sqrt( nx * nx + ny * ny + 1 )
			nx, ny, nz = nx / len, ny / len, nz / len

			px[ o     ] = math.Clamp( math.floor( ( nx * 0.5 + 0.5 ) * 255 + 0.5 ), 0, 255 )
			px[ o + 1 ] = math.Clamp( math.floor( ( ny * 0.5 + 0.5 ) * 255 + 0.5 ), 0, 255 )
			px[ o + 2 ] = math.Clamp( math.floor( ( nz * 0.5 + 0.5 ) * 255 + 0.5 ), 0, 255 )
			o = o + 3
		end
	end

	return px, w, h
end

---------------------------------------------------------------------------
-- PNG encoding
---------------------------------------------------------------------------
local BYTE = {}
for i = 0, 255 do BYTE[ i ] = string.char( i ) end

local CRC_TABLE

local function CRCTable()
	if CRC_TABLE then return CRC_TABLE end

	CRC_TABLE = {}

	for i = 0, 255 do
		local c = i
		for _ = 1, 8 do
			if bit.band( c, 1 ) == 1 then
				c = bit.bxor( 0xEDB88320, bit.rshift( c, 1 ) )
			else
				c = bit.rshift( c, 1 )
			end
		end
		CRC_TABLE[ i ] = c
	end

	return CRC_TABLE
end

local function CRC32( first, second )
	local t = CRCTable()
	local c = 0xFFFFFFFF

	local function Add( s )
		if not s then return end
		for i = 1, #s do
			c = bit.bxor( t[ bit.band( bit.bxor( c, string.byte( s, i ) ), 0xFF ) ],
				bit.rshift( c, 8 ) )
		end
	end

	Add( first )
	Add( second )

	return bit.bxor( c, 0xFFFFFFFF )
end

local function U32( n )
	return string.char(
		bit.band( bit.rshift( n, 24 ), 0xFF ),
		bit.band( bit.rshift( n, 16 ), 0xFF ),
		bit.band( bit.rshift( n,  8 ), 0xFF ),
		bit.band( n, 0xFF ) )
end

local function AppendChunk( out, kind, data )
	out[ #out + 1 ] = U32( #data )
	out[ #out + 1 ] = kind
	out[ #out + 1 ] = data
	out[ #out + 1 ] = U32( CRC32( kind, data ) )
end

local function PNGImage( w, h, colourType, zlib )
	local out = { "\137PNG\13\10\26\10" }
	AppendChunk( out, "IHDR",
		U32( w ) .. U32( h ) .. string.char( 8, colourType, 0, 0, 0 ) )
	-- Append the compressed payload as its own table item. Building an IDAT
	-- string and then concatenating the whole PNG briefly held another complete
	-- copy of the largest chunk.
	AppendChunk( out, "IDAT", zlib )
	AppendChunk( out, "IEND", "" )
	return table.concat( out )
end

---------------------------------------------------------------------------
-- Deflate
---------------------------------------------------------------------------
-- Fixed Huffman coding with run length matching. Not a general compressor -
-- there is no string matcher and no dynamic code table - but it is linear in
-- the input and it is aimed squarely at what comes out of a PNG row filter,
-- which is long stretches of zero wherever the image is smooth or flat.
--
-- The alternative, stored (uncompressed) blocks, is a page less code and
-- writes an edited 1024 texture as four megabytes. That was tolerable when the
-- only output was a normal map; it is not once every hand painted texture goes
-- through here.

-- Bits are packed least significant first within each byte; Huffman codes are
-- defined most significant first, so their bits go in reversed.
local BitWriter = {}
BitWriter.__index = BitWriter

local BIT_CHUNK = 8192

local function NewBits()
	return setmetatable( { out = {}, pending = {}, acc = 0, n = 0 }, BitWriter )
end

local function BitByte( self, value )
	local pending = self.pending
	pending[ #pending + 1 ] = BYTE[ value ]

	-- A photographic 2048-square PNG can emit close to sixteen million bytes.
	-- Keeping one Lua-table slot per byte costs hundreds of megabytes; flushing
	-- small strings bounds that table while preserving the same deflate stream.
	if #pending >= BIT_CHUNK then
		self.out[ #self.out + 1 ] = table.concat( pending )
		self.pending = {}
	end
end

function BitWriter:Raw( value, count )
	count = math.max( 0, math.floor( count or 0 ) )
	if count == 0 then return end

	-- All writes made by the fixed deflate stream are at most nine bits, so the
	-- pending byte plus this value stays comfortably inside a signed 32-bit
	-- integer. Packing the group in one operation avoids eight or nine Lua loop
	-- iterations for every literal in a photographic texture.
	local mask = bit.lshift( 1, count ) - 1
	local acc = bit.bor( self.acc,
		bit.lshift( bit.band( value or 0, mask ), self.n ) )
	local n = self.n + count

	while n >= 8 do
		BitByte( self, bit.band( acc, 0xFF ) )
		acc = bit.rshift( acc, 8 )
		n = n - 8
	end

	self.acc, self.n = acc, n
end

local function ReverseBits( value, count )
	local reversed = 0
	for i = 0, count - 1 do
		reversed = bit.bor( bit.lshift( reversed, 1 ),
			bit.band( bit.rshift( value, i ), 1 ) )
	end
	return reversed
end

--- A Huffman code, whose bits are written high end first.
function BitWriter:Code( value, count )
	self:Raw( ReverseBits( value, count ), count )
end

function BitWriter:Finish()
	if self.n > 0 then
		BitByte( self, self.acc )
		self.acc, self.n = 0, 0
	end
	if #self.pending > 0 then
		self.out[ #self.out + 1 ] = table.concat( self.pending )
		self.pending = {}
	end

	return table.concat( self.out )
end

--- The fixed literal/length alphabet, straight out of the deflate spec. Cache
--- its already-reversed wire representation once instead of reversing a code
--- for every byte of every saved texture.
local LITERAL_CODE, LITERAL_BITS = {}, {}
for value = 0, 287 do
	local code, count
	if value < 144 then
		code, count = 0x30 + value, 8
	elseif value < 256 then
		code, count = 0x190 + value - 144, 9
	elseif value < 280 then
		code, count = value - 256, 7
	else
		code, count = 0xC0 + value - 280, 8
	end
	LITERAL_CODE[ value ], LITERAL_BITS[ value ] = ReverseBits( code, count ), count
end

local function Literal( w, value )
	w:Raw( LITERAL_CODE[ value ], LITERAL_BITS[ value ] )
end

-- Length code, first length it covers, and how many extra bits follow.
local LENGTHS = {
	{ 257, 3, 0 },  { 258, 4, 0 },  { 259, 5, 0 },  { 260, 6, 0 },
	{ 261, 7, 0 },  { 262, 8, 0 },  { 263, 9, 0 },  { 264, 10, 0 },
	{ 265, 11, 1 }, { 266, 13, 1 }, { 267, 15, 1 }, { 268, 17, 1 },
	{ 269, 19, 2 }, { 270, 23, 2 }, { 271, 27, 2 }, { 272, 31, 2 },
	{ 273, 35, 3 }, { 274, 43, 3 }, { 275, 51, 3 }, { 276, 59, 3 },
	{ 277, 67, 4 }, { 278, 83, 4 }, { 279, 99, 4 }, { 280, 115, 4 },
	{ 281, 131, 5 }, { 282, 163, 5 }, { 283, 195, 5 }, { 284, 227, 5 },
	{ 285, 258, 0 },
}

local function EmitLength( w, length )
	for i = #LENGTHS, 1, -1 do
		local entry = LENGTHS[ i ]

		if length >= entry[ 2 ] then
			Literal( w, entry[ 1 ] )
			if entry[ 3 ] > 0 then w:Raw( length - entry[ 2 ], entry[ 3 ] ) end
			return
		end
	end
end

--- Emit one distance-one run. Three is the shortest match deflate can encode,
--- and its first byte has to be a literal for there to be anything to copy.
local function EmitRun( w, value, run )
	if run < 5 then
		for _ = 1, run do Literal( w, value ) end
		return
	end

	Literal( w, value )
	local left = run - 1

	while left >= 3 do
		local take = math.min( left, 258 )
		-- Never leave a remainder of one or two, which cannot be a match and
		-- would have to become literals anyway.
		if left - take > 0 and left - take < 3 then take = left - 3 end
		EmitLength( w, take )
		w:Raw( 0, 5 )        -- distance code 0, meaning one byte back
		left = left - take
	end

	for _ = 1, left do Literal( w, value ) end
end

--- One fixed Huffman block fed a filtered PNG row at a time. Matching is
--- limited to distance 1, which is a run of one repeated byte.
local DeflateWriter = {}
DeflateWriter.__index = DeflateWriter

local function NewDeflateWriter()
	local bits = NewBits()
	bits:Raw( 1, 1 )   -- final block
	bits:Raw( 1, 2 )   -- fixed Huffman
	return setmetatable( {
		bits = bits, a = 1, b = 0, adlerCount = 0,
	}, DeflateWriter )
end

function DeflateWriter:Write( data )
	local current, run = self.current, self.run
	local a, b, adlerCount = self.a, self.b, self.adlerCount
	local byte = string.byte

	for i = 1, #data do
		local value = byte( data, i )
		a = a + value
		b = b + a
		adlerCount = adlerCount + 1
		if adlerCount >= 5552 then
			a, b, adlerCount = a % 65521, b % 65521, 0
		end

		if value == current then
			run = run + 1
		else
			if current ~= nil then EmitRun( self.bits, current, run ) end
			current, run = value, 1
		end
	end

	self.current, self.run = current, run
	self.a, self.b, self.adlerCount = a, b, adlerCount
end

function DeflateWriter:Finish()
	if self.current ~= nil then EmitRun( self.bits, self.current, self.run ) end
	Literal( self.bits, 256 )    -- end of block
	local a, b = self.a % 65521, self.b % 65521
	return string.char( 0x78, 0x01 ) .. self.bits:Finish()
		.. U32( b * 65536 + a )
end

---------------------------------------------------------------------------
-- Row filters
---------------------------------------------------------------------------
-- PNG lets each row be stored as the difference from its neighbours instead of
-- as raw bytes. On a photograph that turns most of the image into small numbers
-- clustered around zero, and on a flat area it turns it into runs of exactly
-- zero, which is what the run length matcher above is looking for. Without a
-- filter the compressor has almost nothing to find.

local function Paeth( a, b, c )
	local p  = a + b - c
	local pa = math.abs( p - a )
	local pb = math.abs( p - b )
	local pc = math.abs( p - c )

	if pa <= pb and pa <= pc then return a end
	if pb <= pc then return b end
	return c
end

--- The filtered value of one byte under filter `f`.
local function Filtered( f, x, a, b, c )
	if f == 0 then return x end
	if f == 1 then return ( x - a ) % 256 end
	if f == 2 then return ( x - b ) % 256 end
	if f == 3 then return ( x - math.floor( ( a + b ) / 2 ) ) % 256 end
	return ( x - Paeth( a, b, c ) ) % 256
end

--- Pick one filter for the whole image by trying all five over a sample of
--- rows. Choosing per row is what a real encoder does and costs five passes
--- over every byte; sampling gets almost the same answer for a fraction of it,
--- which matters when this is a megapixel of Lua.
local function ChooseFilter( px, w, h, channels )
	local stride = w * channels
	local step   = math.max( 1, math.floor( h / 16 ) )

	local best, bestCost = 0, math.huge

	for f = 0, 4 do
		local sum = 0

		for y = 0, h - 1, step do
			GEN.Yield()
			local base = y * stride
			local prev = base - stride

			for i = 1, stride do
				local x = px[ base + i ] or 0
				local a = ( i > channels ) and ( px[ base + i - channels ] or 0 ) or 0
				local b = ( y > 0 ) and ( px[ prev + i ] or 0 ) or 0
				local c = ( y > 0 and i > channels ) and ( px[ prev + i - channels ] or 0 ) or 0

				-- Bytes are summed as signed values, so a filter that leaves
				-- everything near zero scores lowest. This is the heuristic the
				-- PNG specification itself suggests.
				local v = Filtered( f, x, a, b, c )
				sum = sum + ( ( v < 128 ) and v or ( 256 - v ) )
			end
		end

		if sum < bestCost then best, bestCost = f, sum end
	end

	return best
end

--- 8 bit PNG from a flat array of bytes. `channels` is 3 for RGB or 4 for
--- RGBA; an edited texture needs the fourth because erasing to transparent is
--- the whole point of it.
function GEN.EncodePNG( px, w, h, channels )
	channels = ( channels == 4 ) and 4 or 3

	local stride = w * channels
	local stream = NewDeflateWriter()

	local filter = ChooseFilter( px, w, h, channels )
	local tag    = BYTE[ filter ]

	for y = 0, h - 1 do
		GEN.Yield()
		local parts = { tag }
		local base  = y * stride
		local prev  = base - stride

		if filter == 0 then
			for i = 1, stride do
				parts[ i + 1 ] = BYTE[ px[ base + i ] or 0 ]
			end
		else
			for i = 1, stride do
				local x = px[ base + i ] or 0
				local a = ( i > channels ) and ( px[ base + i - channels ] or 0 ) or 0
				local b = ( y > 0 ) and ( px[ prev + i ] or 0 ) or 0
				local c = ( y > 0 and i > channels ) and ( px[ prev + i - channels ] or 0 ) or 0

				parts[ i + 1 ] = BYTE[ Filtered( filter, x, a, b, c ) ]
			end
		end

		stream:Write( table.concat( parts ) )
	end

	-- IHDR colour type: 2 is truecolour, 6 is truecolour with alpha.
	local colourType = ( channels == 4 ) and 6 or 2

	return PNGImage( w, h, colourType, stream:Finish() )
end

--- Encode an opaque packed RGB readback while transforming each texel in place.
--- This is the three-channel counterpart to EncodeRecoveredPNG below: avoiding
--- an invented alpha channel cuts a quarter of the work and output for the
--- overwhelmingly common opaque base texture.
function GEN.EncodeMappedRGBPNG( rgb, w, h, transform )
	local bytes = math.max( 0, math.floor( w or 0 ) )
		* math.max( 0, math.floor( h or 0 ) ) * 3
	if bytes <= 0 or not isstring( rgb ) or #rgb ~= bytes then
		return nil, "the opaque RGB capture is incomplete"
	end

	local byte = string.byte
	local o = 1
	local stream = NewDeflateWriter()

	for y = 1, h do
		GEN.Yield()
		local parts = { BYTE[ 1 ] }
		local p = 2
		local pr, pg, pb = 0, 0, 0

		for x = 1, w do
			local r, g, b = byte( rgb, o, o + 2 )
			o = o + 3

			if transform then
				r, g, b = transform( r, g, b, 255, x - 1, y - 1,
					( y - 1 ) * w + x )
				r = math.Clamp( math.floor( ( tonumber( r ) or 0 ) + 0.5 ), 0, 255 )
				g = math.Clamp( math.floor( ( tonumber( g ) or 0 ) + 0.5 ), 0, 255 )
				b = math.Clamp( math.floor( ( tonumber( b ) or 0 ) + 0.5 ), 0, 255 )
			end

			parts[ p ], parts[ p + 1 ], parts[ p + 2 ] =
				BYTE[ ( r - pr ) % 256 ], BYTE[ ( g - pg ) % 256 ],
				BYTE[ ( b - pb ) % 256 ]
			p = p + 3
			pr, pg, pb = r, g, b
		end

		stream:Write( table.concat( parts ) )
	end

	return PNGImage( w, h, 2, stream:Finish() )
end

--- Encode a straight-alpha PNG recovered from two ordinary GPU composites:
--- the same image drawn once over black and once over white. Fixed-function
--- blending naturally stores premultiplied colour in a transparent render
--- target, while PNG/material consumers expect straight colour. The two solid
--- backgrounds provide enough information to recover both without allocating
--- millions of Lua-number table entries:
---
---     black = colour * alpha
---     white = colour * alpha + 255 * ( 1 - alpha )
---
--- The first two inputs are packed RGB strings in top-to-bottom row order. An
--- optional third packed RGB image supplies hidden base colour where alpha is
--- mathematically zero. `straight` can supply authoritative, already-straight
--- RGB while black/white are used only to recover alpha; this is how a native
--- shader mask survives bounded RGB paint followed by a sharp adjustment.
function GEN.EncodeRecoveredPNG( black, white, w, h, fallback, transform, straight )
	local bytes = math.max( 0, math.floor( w or 0 ) )
		* math.max( 0, math.floor( h or 0 ) ) * 3
	if bytes <= 0 or not isstring( black ) or not isstring( white )
		or #black ~= bytes or #white ~= bytes then
		return nil, "the straight-alpha capture is incomplete"
	end
	if not isstring( fallback ) or #fallback ~= bytes then fallback = nil end
	if not isstring( straight ) or #straight ~= bytes then straight = nil end

	local byte = string.byte
	local o = 1
	local stream = NewDeflateWriter()

	for y = 1, h do
		GEN.Yield()
		-- Sub filtering is cheap to produce while each row is already hot and
		-- avoids the very large PNGs that unfiltered RGBA gradients can create.
		local parts = { BYTE[ 1 ] }
		local p = 2
		local pr, pg, pb, pa = 0, 0, 0, 0

		for x = 1, w do
			local at = o
			local br, bg, bb = byte( black, o, o + 2 )
			local wr, wg, wb = byte( white, o, o + 2 )
			o = o + 3

			local difference = ( ( wr - br ) + ( wg - bg ) + ( wb - bb ) ) / 3
			local a = math.Clamp( math.floor( 255 - difference + 0.5 ), 0, 255 )
			local r, g, b = br, bg, bb

			if straight then
				-- The mask passes answer only A. RGB came from an opaque sampler,
				-- so even a zero mask retains the colour the material visibly uses.
				r, g, b = byte( straight, at, at + 2 )
			-- At extremely low coverage, unpremultiplication magnifies a one-byte
			-- render-target rounding error into arbitrary hidden colour. It cannot
			-- affect the visible result, so retain the stable black-pass value.
			elseif a > 5 then
				local scale = 255 / a
				r = math.Clamp( math.floor( br * scale + 0.5 ), 0, 255 )
				g = math.Clamp( math.floor( bg * scale + 0.5 ), 0, 255 )
				b = math.Clamp( math.floor( bb * scale + 0.5 ), 0, 255 )
			elseif fallback then
				-- Alpha zero has no mathematically recoverable colour. Preserve the
				-- edited base's hidden RGB instead of substituting black; texture
				-- filtering can otherwise turn a clean erased edge into a dark fringe.
				r, g, b = byte( fallback, at, at + 2 )
			end

			-- A packed readback is cheap enough to keep at the requested output
			-- resolution, unlike four Lua-number arrays.  Texture edits can use
			-- this hook to transform each recovered source texel before it is
			-- filtered and encoded, retaining the source's real detail without
			-- materialising a full-size pixel buffer.
			if transform then
				r, g, b, a = transform( r, g, b, a, x - 1, y - 1,
					( y - 1 ) * w + x )
				r = math.Clamp( math.floor( ( tonumber( r ) or 0 ) + 0.5 ), 0, 255 )
				g = math.Clamp( math.floor( ( tonumber( g ) or 0 ) + 0.5 ), 0, 255 )
				b = math.Clamp( math.floor( ( tonumber( b ) or 0 ) + 0.5 ), 0, 255 )
				a = math.Clamp( math.floor( ( tonumber( a ) or 255 ) + 0.5 ), 0, 255 )
			end

			parts[ p ], parts[ p + 1 ], parts[ p + 2 ], parts[ p + 3 ] =
				BYTE[ ( r - pr ) % 256 ], BYTE[ ( g - pg ) % 256 ],
				BYTE[ ( b - pb ) % 256 ], BYTE[ ( a - pa ) % 256 ]
			p = p + 4
			pr, pg, pb, pa = r, g, b, a
		end

		stream:Write( table.concat( parts ) )
	end

	return PNGImage( w, h, 6, stream:Finish() )
end

---------------------------------------------------------------------------
-- Producing and fetching the finished texture
---------------------------------------------------------------------------
local function LoadMaterial( target )
	local mat = Material( "data/" .. target, "noclamp smooth" )
	if not mat or mat:IsError() then return nil end
	return mat
end

---------------------------------------------------------------------------
-- Builders
---------------------------------------------------------------------------
-- One per recipe kind. A builder takes a sanitised recipe and returns a flat
-- array of bytes plus its dimensions and channel count. Everything after that
-- - regions, encoding, writing, caching - is shared and lives in GEN.Build.
GEN.Builders = GEN.Builders or {}

--- What a region-limited generator writes where it is not allowed to draw.
--- A flat normal is "no bump", black is "no reflection", and so on.
GEN.Neutral = GEN.Neutral or {}

GEN.Builders.normal = function( recipe )
	local w, h = GEN.Dims( recipe )

	local src = GEN.ReadSource( recipe.src, w, h, recipe.channel == "alpha" )
	if not src then return nil, "could not read " .. recipe.src end

	local px, w, h = GEN.Compute( src, recipe )
	return px, w, h, 3
end

-- A flat normal outside the region, and the alpha channel left exactly as the
-- generator wrote it: on a normal map that channel is a reflection mask, not
-- part of the bump data the region is limiting.
GEN.Neutral.normal = function() return 128, 128, 255, nil end

--- Create every folder on a data-relative path.
local function EnsureDir( path )
	local parts, run = string.Explode( "/", path ), nil

	for _, part in ipairs( parts ) do
		run = run and ( run .. "/" .. part ) or part
		file.CreateDir( run )
	end
end

--- Replace everything the region excludes with the fallback colour.
function GEN.ApplyRegion( px, w, h, channels, recipe )
	if not recipe.region or not AdvMat.Sel or not AdvMat.Sel.Rasterize then return end

	local mask = AdvMat.Sel.Rasterize( recipe.region, w, h, {
		src     = recipe.src,
		model   = recipe.model,
		slot    = recipe.slot,
		matpath = recipe.matpath,
		mask    = recipe.mask,
	} )

	local outside = ( recipe.regionmode == "outside" )

	-- Rasterize returns nothing for two different situations: a selection that
	-- covers everything, as an optimisation, and one that selects nothing.
	-- Selecting everything and then asking for the OUTSIDE of it means nothing
	-- may be generated at all, which is not the same as having no region, so it
	-- carries on with a nil mask and a coverage of one.
	if not mask and not ( outside and AdvMat.Sel.CoversAll( recipe.region ) ) then return end

	local nr, ng, nb, na
	local fill = recipe.regionfill or -1

	if fill >= 0 then
		nr, ng, nb, na = fill, fill, fill, 255
	else
		local _, id = GEN.KindOf( recipe )
		local fn    = GEN.Neutral[ id ]

		if fn then nr, ng, nb, na = fn( recipe ) else nr, ng, nb, na = 0, 0, 0, 255 end
	end

	local o = 1

	for i = 1, w * h do
		if i % 16384 == 0 then GEN.Yield() end

		-- Coverage is 0..255, so a feathered edge fades between the generated
		-- image and the fallback rather than stepping between them.
		local cov = mask and ( mask[ i ] / 255 ) or 1
		if outside then cov = 1 - cov end

		if cov < 0.999 then
			local k = 1 - cov
			px[ o     ] = math.floor( px[ o     ] * cov + nr * k + 0.5 )
			px[ o + 1 ] = math.floor( px[ o + 1 ] * cov + ng * k + 0.5 )
			px[ o + 2 ] = math.floor( px[ o + 2 ] * cov + nb * k + 0.5 )

			-- A nil neutral alpha means "leave that channel alone". A normal
			-- map's alpha carries a reflection mask, which is a separate thing
			-- from the bumps the region was drawn to limit, and blanking it
			-- outside the region would silently turn the rest of the model
			-- matte.
			if channels == 4 and na then
				px[ o + 3 ] = math.floor( px[ o + 3 ] * cov + na * k + 0.5 )
			end
		end

		o = o + channels
	end
end

--- Run a recipe all the way through and write the file. Returns the file path
--- on success, or nil plus a reason.
function GEN.Build( recipe )
	recipe = GEN.Sanitize( recipe )
	if not recipe then return nil, "the settings are incomplete" end

	local kind, id = GEN.KindOf( recipe )
	local builder  = GEN.Builders[ id ]
	if not builder then return nil, "no builder for " .. tostring( id ) end

	local px, w, h, channels, png = builder( recipe )
	if not px and not png then return nil, w or "generation failed" end

	if not png then
		GEN.Yield()
		GEN.ApplyRegion( px, w, h, channels, recipe )
		GEN.Yield()
		png = GEN.EncodePNG( px, w, h, channels )
	end

	GEN.Yield()
	local target = GEN.FileName( recipe )
	EnsureDir( kind.dir )

	file.Write( target, png )

	-- Existence alone can be an older cache file left behind when this write
	-- failed or was truncated. Read back the bytes before publishing it as the
	-- canonical result for this recipe.
	local written = file.Read( target, "DATA" )
	if written ~= png then
		return nil, "could not write " .. target
	end

	GEN.Cache[ target ] = LoadMaterial( target ) or false
	return target
end

--- The generated IMaterial for a recipe, or nil if it is not ready yet. A nil
--- return queues the work; the AdvMatGenerated hook fires when it lands.
function GEN.GetMaterial( recipe )
	recipe = GEN.Sanitize( recipe )
	if not recipe then return nil end

	local target = GEN.FileName( recipe )
	-- A recipe learned from the server may have an exact author-produced PNG
	-- waiting in the server cache. Ask for it before accepting any material or
	-- disk cache left by another server/session.
	if AdvMat.Assets and isfunction( AdvMat.Assets.RequestMarked )
		and AdvMat.Assets.RequestMarked( recipe ) then return nil end
	local hit    = GEN.Cache[ target ]

	if hit then return hit end
	if hit == false then return nil end

	-- A failure holds this recipe off for a few seconds rather than for the
	-- session. Most of what can go wrong here is transient - a read that landed
	-- at a bad moment, a material that had not finished loading - and a
	-- permanent refusal means the only way back is a console command.
	local failed = GEN.Failed[ target ]
	if failed and ( RealTime() - failed ) < 8 then return nil end

	-- Already on disk from an earlier session, or from another rule using the
	-- same settings.
	if file.Exists( target, "DATA" ) then
		local mat = LoadMaterial( target )
		if mat then
			GEN.Cache[ target ] = mat
			return mat
		end
	end

	GEN.Request( recipe )
	return nil
end

--- The ITexture behind that material, which is what a material parameter takes.
function GEN.GetTexture( recipe )
	local mat = GEN.GetMaterial( recipe )
	if not mat then return nil end

	local ok, tex = pcall( mat.GetTexture, mat, "$basetexture" )
	if not ok then return nil end

	return tex
end

---------------------------------------------------------------------------
-- Queue
---------------------------------------------------------------------------
-- Reading a megapixel one render.ReadPixel at a time is slow enough to be felt,
-- and it cannot run inside a render hook at all, so it happens here.

function GEN.RequestLocal( recipe )
	recipe = GEN.Sanitize( recipe )
	if not recipe then return end

	-- An image imported on another computer cannot be built here, whichever
	-- way its recipe arrived: its source is a file only that computer has. The
	-- server's copy of the finished texture is the only way to show it.
	if AdvMat.Import and AdvMat.Import.IsSource( recipe.src )
		and not AdvMat.Import.Has( recipe.src )
		and AdvMat.Assets and isfunction( AdvMat.Assets.AwaitServerCopy ) then
		AdvMat.Assets.AwaitServerCopy( recipe )
		return
	end

	local target = GEN.FileName( recipe )

	-- Already being built, over however many frames that takes.
	if job and GEN.FileName( job.recipe ) == target then return end

	for _, queued in ipairs( GEN.Queue ) do
		if GEN.FileName( queued ) == target then return end
	end

	GEN.Queue[ #GEN.Queue + 1 ] = recipe
end

function GEN.Request( recipe )
	recipe = GEN.Sanitize( recipe )
	if not recipe then return end

	-- Rules received from another player first ask the server for the author's
	-- exact baked edit. A server miss/timeout calls RequestLocal, retaining the
	-- recipe-only behaviour for legacy saves and non-edit generators.
	if AdvMat.Assets and isfunction( AdvMat.Assets.RequestMarked )
		and AdvMat.Assets.RequestMarked( recipe ) then return end

	GEN.RequestLocal( recipe )
end

-- PreRender rather than Think: this pushes a render target, and doing that
-- from a plain think can land in the middle of a frame.
--- Record a failure, tell the user once, and allow another attempt later.
---
--- A failure used to be permanent for the session, which turned one bad frame
--- into a texture that never appeared again and no way to find out why short of
--- the console.
local function Failed( recipe, reason )
	local target = GEN.FileName( recipe )

	AdvMat.Log( "%s generation failed: %s", GEN.KindName( recipe ), tostring( reason ) )

	GEN.Failed[ target ] = RealTime()
	GEN.Cache[ target ]  = nil

	-- Async consumers (including the RTX materializer) must be released on the
	-- same frame as a failed build.  Success already has AdvMatGenerated below;
	-- without the matching failure event they can do nothing but wait for their
	-- watchdog and make an immediate generator error look like a two-minute hang.
	hook.Run( "AdvMatGenerationFailed", recipe, target, tostring( reason ) )

	if not GEN.Told[ target ] then
		GEN.Told[ target ] = true

		AdvMat.NotifyLocal( AdvMat.L( "notify.build_failed", {
			kind = GEN.KindName( recipe ), reason = AdvMat.LText( tostring( reason ) ),
		} ), NOTIFY_ERROR, 8 )
	end
end

--- Drain one item of work. Split out of the hook so it can be driven directly
--- from a test, where there is no frame to hang it on.
function GEN.PumpQueue()
	if GEN.Busy then return end

	-- Pixel reads come first. They are the only thing here that HAS to happen
	-- inside a render hook, and a queued build is often waiting on one.
	local req = table.remove( GEN.SourceQueue, 1 )

	if req then
		GEN.Busy = true
		local ok, src = pcall( GEN.ReadSource, req.path, req.w, req.h,
			req.alpha, req.maskalpha )
		GEN.Busy = false

		local result = ok and src or nil

		if req.done then req.done( result ) end
		for _, also in ipairs( req.also or {} ) do also( result ) end
		return
	end

	-- One build at a time, carried across frames until it finishes.
	local start = false
	if not job then
		if #GEN.Queue == 0 then return end
		local queued = table.remove( GEN.Queue, 1 )
		job, start = { recipe = queued, thread = coroutine.create( GEN.Build ) }, true
	end

	GEN.Busy = true
	buildThread, yieldAt = job.thread, Clock() + GEN.FRAME_BUDGET

	local ok, result, err
	if start then
		ok, result, err = coroutine.resume( job.thread, job.recipe )
	else
		ok, result, err = coroutine.resume( job.thread )
	end

	buildThread, yieldAt = nil, math.huge
	GEN.Busy = false

	-- Paused at the frame's budget; it carries on next frame.
	if ok and coroutine.status( job.thread ) ~= "dead" then return end

	local recipe = job.recipe
	job = nil

	if not ok then      Failed( recipe, result )  return end
	if not result then  Failed( recipe, err )     return end

	GEN.Failed[ result ] = nil
	GEN.Told[ result ]   = nil

	AdvMat.Log( "Generated %s from %s", result, recipe.src or "a blank image" )
	hook.Run( "AdvMatGenerated", recipe, result )
end

-- PreRender rather than Think: reading a render target only works inside a
-- render hook, and outside one it silently hands back a black image.
hook.Add( "PreRender", "AdvMat.GenQueue", GEN.PumpQueue )

concommand.Add( "advmat_gen_flush", function()
	GEN.Cache       = {}
	GEN.Failed      = {}
	GEN.Told        = {}
	GEN.SourceAlpha = {}
	GEN.ResetRawRGBCaptureProbe()
	GEN.FlushSources()
	AdvMat.Log( "Generated texture cache cleared." )
end )
