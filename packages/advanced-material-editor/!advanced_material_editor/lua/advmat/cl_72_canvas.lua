--[[---------------------------------------------------------------------------
	Advanced Material Editor - the texture canvas

	A zoomable, pannable view of an RGBA buffer with a selection drawn over it,
	plus the mouse handling for every tool that draws on it.

	The buffer lives on the CPU, because that is where the edit steps run and
	where the final .png is encoded. Drawing a megapixel of it one rectangle at
	a time every frame is not possible, so it is uploaded into a render target
	whenever it changes and the canvas then draws that in a single call. The
	upload is spread across frames and only touches pixels that differ from the
	source texture, so an edit to one sleeve costs an upload of one sleeve.

	The selection is drawn three ways at once, because no one of them is enough:

	  a tint         shows at a glance how much is selected
	  marching ants  show exactly where the edge is, which a tint cannot
	  dimming        shows that the rest is protected, which is the answer to
	                 "why is my brush not working"

	The ants alternate black and white. A single colour outline vanishes on one
	or the other, and character skins reliably contain both.
-----------------------------------------------------------------------------]]

AdvMat = AdvMat or {}

local T = AdvMat.Theme

local PANEL = {}

-- Zoom is stepped rather than continuous so that 100% is always reachable
-- exactly, which matters when judging a hard edge.
local ZOOMS = { 0.03125, 0.0625, 0.125, 0.25, 0.5, 0.75, 1, 1.5, 2, 3, 4, 6, 8, 12, 16 }

-- Rectangles pushed into the preview render target per frame. High enough that
-- an ordinary edit lands in one or two frames, low enough that a whole-image
-- recolour does not stall.
local UPLOAD_BUDGET = 7000

local CHECKER = 8

-- Fixed-function source-over stores premultiplied RGB in a transparent render
-- target, while Source materials consume straight RGB.  The live layer stack
-- is recovered entirely on the GPU below.  Nine doubling stages are 512
-- effective copies: for alpha 5 / 255 the remaining colour error is under
-- 0.012 of one byte.  Alpha below that is deliberately treated as hidden
-- colour elsewhere too, because one-byte RT rounding cannot be unpremultiplied
-- reliably there.
local PREVIEW_RECOVERY_STAGES = 9

local function BufferHasAlpha( buf )
	if not buf or not buf.a then return false end

	for i = 1, ( buf.w or 0 ) * ( buf.h or 0 ) do
		if ( buf.a[ i ] or 255 ) < 255 then return true end
	end

	return false
end

---------------------------------------------------------------------------
-- Construction
---------------------------------------------------------------------------
function PANEL:Init()
	self.Zoom    = 7          -- index into ZOOMS (100%)
	self.PanX    = 0
	self.PanY    = 0

	-- The image's own shape, in its own pixels. Two numbers rather than one
	-- because a texture is allowed to be oblong, and a 4096 x 2048 sheet shown
	-- in a square is everything on it stretched by a factor of two.
	self.SizeW   = 512
	self.SizeH   = 512

	self.Mode    = "replace"

	self.Pending = nil        -- rows still to push into the render target
	self.Dirty   = true

	self.Tool    = "island"
	self.Brush   = 0.04
	self.Hardness = 1
	self.ShowUV  = true
	self.RTXCompatibility = false
	self.LayerTransform = nil
	self.LayerKeepAspect = true

	self:SetShowSelection( "both" )

	self:SetMouseInputEnabled( true )
	self:SetKeyboardInputEnabled( false )

	self.Ants = {}
end

--- The render target the canvas actually draws, and the material wrapping it.
--- One per size, reused: render targets are never garbage collected, so a new
--- one per open would leak until the map changes.
function PANEL:EnsureTarget()
	local sw, sh = self.SizeW, self.SizeH
	local size   = sw .. "x" .. sh

	if self.RT and self.BaseRT and self.RTSize == size then return self.BaseRT end

	-- Keep the expensive CPU-operation upload in a base target. Imported image
	-- layers are composited into the public target afterwards, so moving one
	-- layer redraws a handful of GPU quads instead of rebuilding the base or
	-- flattening a photograph into thousands of pixel runs.
	self.BaseRT = GetRenderTarget( "advmat_canvas_base_" .. size, sw, sh )
	self.RT     = GetRenderTarget( "advmat_canvas_" .. size, sw, sh )
	self.RTSize = size

	-- Named rather than swapped in afterwards: see the half texel note further
	-- down. A material created against color/white and handed this target later
	-- keeps color/white's sixteen pixel inset and shows 480 texels of 512.
	--
	-- $vertexcolor and $nocull because these are drawn as raw mesh quads: the
	-- modulation surface used to do arrives as vertex colour now, and a raw
	-- quad has a winding for the culler to have an opinion about.
	self.RTMat = CreateMaterial( "advmat_canvas_mat_" .. size, "UnlitGeneric", {
		[ "$basetexture" ] = self.RT and self.RT:GetName() or "color/white",
		[ "$translucent" ] = "1",
		[ "$vertexalpha" ] = "1",
		[ "$vertexcolor" ] = "1",
		[ "$nocull" ]      = "1",
		[ "$nolod" ]       = "1",
		[ "$ignorez" ]     = "1",
	} )

	self.BaseMat = CreateMaterial( "advmat_canvas_base_mat_" .. size, "UnlitGeneric", {
		[ "$basetexture" ] = self.BaseRT and self.BaseRT:GetName() or "color/white",
		[ "$translucent" ] = "1",
		[ "$vertexalpha" ] = "1",
		[ "$vertexcolor" ] = "1",
		[ "$nocull" ]      = "1",
		[ "$nolod" ]       = "1",
		[ "$ignorez" ]     = "1",
	} )

	if self.RT then self.RTMat:SetTexture( "$basetexture", self.RT ) end
	if self.BaseRT then self.BaseMat:SetTexture( "$basetexture", self.BaseRT ) end
	self.CompositeDirty = true

	return self.BaseRT
end

--- The material other panels (the model preview) should point at to show what
--- is currently on the canvas.
function PANEL:GetPreviewTexture()
	self:EnsureTarget()
	return self.RT
end

---------------------------------------------------------------------------
-- Content
---------------------------------------------------------------------------

--- `buf` is the working image, `src` the untouched source it started from.
--- The source is kept so the upload can skip everything that has not changed.
---
--- `dispW`/`dispH` are the resolution the image is DISPLAYED at, defaulting to
--- the buffer's own. They exist because the two costs are different: the
--- buffer is Lua tables walked per edit, while the display is a render target
--- the GPU holds - so the sheet can be shown at 1024 or 2048 with the source
--- drawn into the target sharp at that size, and only the edited runs arrive
--- upscaled from the buffer. Every coordinate is normalised, so nothing else
--- cares that the two differ.
function PANEL:SetImage( buf, src, srcPath, dispW, dispH, layers, visualOpaque )
	local hadImage = self.Buf ~= nil
	local oldW, oldH = self.SizeW, self.SizeH

	self.Buf     = buf
	self.Src     = src
	self.SrcPath = srcPath
	self.SizeW   = dispW or ( buf and buf.w ) or 512
	self.SizeH   = dispH or ( buf and buf.h ) or 512
	self.Layers  = layers or self.Layers or {}
	-- The RT always retains authoritative alpha for the material/model. This
	-- flag affects only the flat editor view, where shader-mask alpha must not
	-- look like transparency.
	self.VisualOpaque = visualOpaque == true
	self.BaseHasAlpha = BufferHasAlpha( buf )
	self.CompositeFailures = 0
	if oldW ~= self.SizeW or oldH ~= self.SizeH then self.UVDirty = true end

	self.RT     = nil           -- size may have changed
	self.BaseRT = nil
	self.Patch  = nil           -- a rectangle of the image being replaced
	self.Ants = nil
	self.Tint = nil
	self.OverlayDirty = true

	self:Invalidate()

	-- The image usually arrives from Setup while Derma still reports the
	-- canvas's temporary 64 x 64 construction size. Fitting synchronously there
	-- consumes the request against that tiny box and leaves the real canvas
	-- showing a small image in its top-left corner.
	--
	-- Recomposition also calls SetImage after undo, redo and step changes. Those
	-- calls must preserve the view the user deliberately panned or zoomed. Only
	-- the first image, or a genuinely different display size, asks the next real
	-- layout for a fresh fit.
	if not hadImage or oldW ~= self.SizeW or oldH ~= self.SizeH then
		self.WantFit = true
		self:InvalidateLayout()
	end
end

--- Replace only the imported layer stack. The base target remains valid, which
--- is what keeps interactive move/resize/rotation GPU-cheap.
function PANEL:SetLayers( layers )
	self.Layers = layers or {}
	self.CompositeFailures = 0
	self.CompositeDirty = true
end

function PANEL:SetLayerTransform( layer, keepAspect )
	self.LayerTransform = layer
	if keepAspect ~= nil then self.LayerKeepAspect = keepAspect == true end
	self:InvalidateLayout()
end

function PANEL:PerformLayout()
	-- A newly-created panel can itself receive a layout at its stock 64 x 64
	-- size before its docked parent is laid out. Keep the request for the real
	-- workspace instead of consuming it at that intermediate size.
	if self.WantFit and self:GetWide() >= 128 and self:GetTall() >= 128 then
		self:FitToWindow()
	end
end

function PANEL:Invalidate()
	self.Dirty   = true
	self.Pending = nil
	self.BaseHasAlpha = BufferHasAlpha( self.Buf )
end

function PANEL:SetSelection( mask )
	self.Mask = mask
	self.Ants = nil
	self.Tint = nil
	self.OverlayDirty = true

	-- A new mask decides the covers-all outline again; the editor sets the
	-- flag right after this call.
	self.SelAll = nil
end

--- `mask` is the packed bodygroup value, so the outline shows the parts that
--- are actually being displayed rather than every part the model can have.
function PANEL:SetUVSource( model, matpath, slot, mask )
	mask = mask or 0

	if self.UVModel == model and self.UVPath == matpath
		and self.UVSlot == slot and self.UVMask == mask then return end

	self:DestroyRTXUVMeshes()
	self.UVModel, self.UVPath, self.UVSlot, self.UVMask = model, matpath, slot, mask
	self.UVDirty = true
end

--- RTX Remix does not composite the additive UV target reliably.  The mode is
--- explicit and local to this canvas so the vanilla renderer retains the
--- byte-for-byte path it already uses.
function PANEL:SetRTXCompatibility( enabled )
	enabled = enabled == true
	if self.RTXCompatibility == enabled then return end

	self:DestroyRTXUVMeshes()
	self.RTXCompatibility = enabled
	self.UVMat = nil
	self.UVDirty = true
end

--- additive, transparent target, baked line alpha, draw alpha, material suffix
function PANEL:UVCompositeMode()
	if self.RTXCompatibility then
		return false, true, self.UVAlpha or 150, 255, "_rtx"
	end

	return true, false, 255, self.UVAlpha or 150, ""
end

---------------------------------------------------------------------------
-- Uploading the buffer
---------------------------------------------------------------------------
-- Two passes. The source texture goes in as one textured rectangle, then only
-- the pixels that differ from it are pushed as run length rectangles. An edit
-- that recoloured one sleeve therefore costs a few hundred rectangles rather
-- than a quarter of a million.

--- Build the list of runs that differ from the source.
--- How many render target pixels one buffer pixel covers, per axis.
function PANEL:UploadScale()
	if not self.Buf or self.Buf.w <= 0 or self.Buf.h <= 0 then return 1, 1 end
	return self.SizeW / self.Buf.w, self.SizeH / self.Buf.h
end

local function BuildRuns( buf, src, x0, y0, x1, y1 )
	return AdvMat.Buf.BuildRuns( buf, src, x0, y0, x1, y1 )
end

--- Draw the untouched source into the bound target over `x, y, w, h`, taking
--- `u0..u1` x `v0..v1` of it - the whole sheet for a full upload, one
--- rectangle of it when only a brush stroke's area is being redrawn. Every
--- alpha rule below applies to both, which is why they live in one place.
---
--- Returns the material drawn from, or nil (or an error material) when there
--- is no source to draw: a blank start, whose every pixel is an upload run.
function PANEL:DrawSource( x, y, w, h, u0, v0, u1, v1 )
	if not self.SrcPath or self.SrcPath == "" then return nil end

	local sourceHasAlpha = self.Src and self.Src.alpha or false
	local preserveMask   = self.VisualOpaque and sourceHasAlpha
	local forceOpaque    = not sourceHasAlpha

	-- Drawn through the variant that matches how the buffer was read.
	-- Copy blending is essential for a mask-bearing opaque source: normal
	-- source-over would premultiply its RGB by the mask before that target
	-- is handed to a Source shader, producing dark/colour-shifted texels.
	local mat = AdvMat.Gen.SourceMaterial( self.SrcPath, sourceHasAlpha )
	if not mat or mat:IsError() then return mat end

	if forceOpaque then render.OverrideAlphaWriteEnable( true, false ) end
	AdvMat.Gen.DrawMaterialCopy( mat, x, y, w, h, u0, v0, u1, v1 )

	if preserveMask then
		-- Keep A from the translucent sampler, then replace only RGB
		-- through the opaque sampler. Shader-mask zero must not make
		-- the visible base colour black.
		local opaqueMat = AdvMat.Gen.SourceMaterial( self.SrcPath, false )
		if not opaqueMat or opaqueMat:IsError() then
			error( "could not draw opaque colour from " .. self.SrcPath )
		end
		render.OverrideAlphaWriteEnable( true, false )
		AdvMat.Gen.DrawMaterialCopy( opaqueMat, x, y, w, h, u0, v0, u1, v1 )
		render.OverrideAlphaWriteEnable( true, true )
	elseif forceOpaque then
		-- Clear's alpha is not preserved by this draw on every Source
		-- renderer. Stamp only the target's alpha channel afterwards;
		-- the source colour already in RGB remains untouched.
		render.OverrideAlphaWriteEnable( true, true )
		render.OverrideColorWriteEnable( true, false )
		surface.SetDrawColor( 255, 255, 255, 255 )
		surface.DrawRect( x, y, w, h )
		render.OverrideColorWriteEnable( false, true )
	end

	return mat
end

--- Push as much of the pending upload as this frame's budget allows.
function PANEL:PumpUpload()
	if not self.Buf then return end

	local rt = self:EnsureTarget()
	if not rt then return end

	if self.Dirty then
		self.Dirty   = false
		self.Pending = BuildRuns( self.Buf, self.Src )
		self.Cursor  = 1
		self.Base    = true
		self.CompositeDirty = true

		-- These runs are the whole image as it stands now, so any area waiting
		-- to be patched is already in them. Patches asked for from here on are
		-- not, and are drawn once this upload has finished.
		self.Patch = nil
	end

	if not self.Pending then return end

	local sw, sh = self.SizeW, self.SizeH

	-- Three things are opened here and all three have to be closed on every
	-- path, including a failure. None of them errors when it is left open - it
	-- quietly corrupts everything drawn for the rest of the frame - so the
	-- pcall wraps only the drawing, and the closing statements sit outside it
	-- in the reverse order they were opened.
	render.PushRenderTarget( rt )

	-- Surface draws leave the alpha channel of a render target alone unless
	-- this is on, which would make every erased area come out opaque no matter
	-- what was drawn.
	render.OverrideAlphaWriteEnable( true, true )
	cam.Start2D()

	local ok, err = pcall( function()
		if self.Base then
			self.Base = false

			-- The CPU read is the authority on alpha. In particular, an opaque
			-- DXT1 source has src.alpha == false and an a[] array filled with 255,
			-- but its UnlitGeneric sampling shader can still output alpha zero on
			-- some builds. If that output is allowed into this target, BuildRuns
			-- sees identical CPU buffers and uploads no corrections: RGB is there,
			-- target alpha stays zero, the canvas is checkerboard and the model is
			-- bald. Seed opaque targets with alpha 255 and preserve it while the
			-- GPU draws the source colour.
			local sourceHasAlpha = self.Src and self.Src.alpha or false
			local preserveMask   = self.VisualOpaque and sourceHasAlpha
			local forceOpaque    = self.SrcPath and self.SrcPath ~= "" and not sourceHasAlpha

			render.Clear( 0, 0, 0, forceOpaque and 255 or 0, true, true )

			local mat = self:DrawSource( 0, 0, sw, sh )

			if not mat or mat:IsError() then
				-- No source: the buffer started from a flat colour, and
				-- every pixel of it counts as a difference anyway.
				surface.SetDrawColor( 0, 0, 0, 0 )
				surface.DrawRect( 0, 0, sw, sh )
			end

			if AdvMat.DebugTraceActive and AdvMat.DebugTraceEvent then
				AdvMat.DebugTraceEvent( "canvas.base_draw", {
					path = self.SrcPath,
					source_alpha = sourceHasAlpha,
					forced_opaque_alpha = forceOpaque,
					preserves_mask_alpha = preserveMask,
					material = mat and mat:GetName() or nil,
					material_error = mat and mat:IsError() or nil,
					target = rt.GetName and rt:GetName() or tostring( rt ),
					size = { sw, sh },
				} )
			end
		end

		local runs = self.Pending
		local last = math.min( self.Cursor + UPLOAD_BUDGET - 1, #runs )

		-- Runs are in working-buffer pixels; the target may be larger.
		local ux, uy = self:UploadScale()


		-- Raw source-copy quads are required here.  Surface discards a rectangle
		-- whose alpha is zero, so the old path faithfully changed the CPU buffer
		-- and then skipped every pixel the eraser asked it to upload.
		if self.VisualOpaque then render.OverrideAlphaWriteEnable( true, false ) end
		AdvMat.Gen.DrawPixelRuns( runs, self.Cursor, last, ux, uy )
		if self.VisualOpaque then render.OverrideAlphaWriteEnable( true, true ) end

		self.Cursor = last + 1
	end )

	-- DrawPixelRuns temporarily replaces the blend equation.  Reset it here as
	-- well as in the happy path so an unexpected mesh error cannot leak source-
	-- copy blending into the rest of the frame.
	render.OverrideBlend( false )
	cam.End2D()
	render.OverrideColorWriteEnable( false, true )
	render.OverrideAlphaWriteEnable( false, false )
	render.PopRenderTarget()

	if not ok then
		AdvMat.Log( "Canvas upload failed: %s", tostring( err ) )
		self.Pending = nil
		return
	end

	if self.Cursor > #self.Pending then
		self.Pending = nil
		self.CompositeDirty = true
		if AdvMat.DebugTraceActive and AdvMat.DebugTraceEvent then
			AdvMat.DebugTraceEvent( "canvas.upload_complete", {
				path = self.SrcPath,
				source = AdvMat.DebugBufferStats and AdvMat.DebugBufferStats( self.Src ) or nil,
				buffer = AdvMat.DebugBufferStats and AdvMat.DebugBufferStats( self.Buf ) or nil,
				target = self.RT and self.RT.GetName and self.RT:GetName() or nil,
			} )
		end
	end
end

---------------------------------------------------------------------------
-- Uploading one rectangle
---------------------------------------------------------------------------
-- A brush stroke changes the pixels under the brush and nothing else, so a
-- stroke being drawn - or one just added - re-uploads only that rectangle.
-- Rebuilding every run on the sheet for each movement of the pointer is what
-- a full Invalidate would mean, and on a heavily painted texture that is many
-- frames of work per stroke.
--
-- A patch redraws the rectangle exactly the way a full upload would have left
-- it: the untouched source first, through the same materials and alpha rules,
-- then the runs that differ from it. A pixel a stroke has just put back to the
-- original is therefore the sharp source again, not a coarse run.

--- Ask for the rectangle `x0..x1` x `y0..y1` (buffer pixels, inclusive) to be
--- uploaded again. Requests made before the next upload merge into one.
function PANEL:PatchRegion( x0, y0, x1, y1 )
	if not self.Buf or not x0 then return end

	local bw, bh = self.Buf.w, self.Buf.h
	x0 = math.max( math.floor( x0 ), 0 )
	y0 = math.max( math.floor( y0 ), 0 )
	x1 = math.min( math.floor( x1 ), bw - 1 )
	y1 = math.min( math.floor( y1 ), bh - 1 )
	if x1 < x0 or y1 < y0 then return end

	local p = self.Patch
	if not p then
		self.Patch = { x0, y0, x1, y1 }
		return
	end

	p[ 1 ], p[ 2 ] = math.min( p[ 1 ], x0 ), math.min( p[ 2 ], y0 )
	p[ 3 ], p[ 4 ] = math.max( p[ 3 ], x1 ), math.max( p[ 4 ], y1 )
end

--- Upload as much of the waiting patch as this frame's run budget allows,
--- a band of whole rows at a time. Whatever is left waits for the next frame.
function PANEL:PumpPatch()
	local p = self.Patch
	if not self.Buf or not p then return end

	-- A patch is drawn over a target that already holds the whole image. One
	-- that has just been made, or replaced at a new size, holds nothing yet.
	local size = self.SizeW .. "x" .. self.SizeH
	if not self.BaseRT or self.RTSize ~= size then
		self:Invalidate()
		return
	end

	local x0, y0, x1, y1 = p[ 1 ], p[ 2 ], p[ 3 ], p[ 4 ]
	local runs, last = {}, y1

	for y = y0, y1 do
		local row = BuildRuns( self.Buf, self.Src, x0, y, x1, y )
		for _, run in ipairs( row ) do runs[ #runs + 1 ] = run end

		if #runs >= UPLOAD_BUDGET and y < y1 then
			last = y
			break
		end
	end

	if last < y1 then
		p[ 2 ] = last + 1
	else
		self.Patch = nil
	end

	local rt = self.BaseRT
	local bw, bh = self.Buf.w, self.Buf.h
	local ux, uy = self:UploadScale()

	-- Balanced on every path, as in PumpUpload; see the note there.
	render.PushRenderTarget( rt )
	render.OverrideAlphaWriteEnable( true, true )
	cam.Start2D()

	local ok, err = pcall( function()
		self:DrawSource( x0 * ux, y0 * uy, ( x1 - x0 + 1 ) * ux, ( last - y0 + 1 ) * uy,
			x0 / bw, y0 / bh, ( x1 + 1 ) / bw, ( last + 1 ) / bh )

		if self.VisualOpaque then render.OverrideAlphaWriteEnable( true, false ) end
		AdvMat.Gen.DrawPixelRuns( runs, 1, #runs, ux, uy )
		if self.VisualOpaque then render.OverrideAlphaWriteEnable( true, true ) end
	end )

	render.OverrideBlend( false )
	cam.End2D()
	render.OverrideColorWriteEnable( false, true )
	render.OverrideAlphaWriteEnable( false, false )
	render.PopRenderTarget()

	if not ok then
		-- Fall back to the path that has always worked rather than leave the
		-- canvas showing a half-drawn stroke.
		AdvMat.Log( "Canvas patch failed: %s", tostring( err ) )
		self:Invalidate()
		return
	end

	-- The layer compositor needs to know when the base first gains
	-- transparency; a hole cut by a stroke arrives here, not through Invalidate.
	if not self.BaseHasAlpha then
		for _, run in ipairs( runs ) do
			if run[ 7 ] < 255 then self.BaseHasAlpha = true break end
		end
	end

	self.CompositeDirty = true
end

---------------------------------------------------------------------------
-- Straight-alpha live layer preview
---------------------------------------------------------------------------
-- A layer with partial coverage over a partially-transparent base is the one
-- case ordinary fixed-function blending cannot leave in a material-ready RT:
-- it writes the premultiplied colour numerator.  Opaque bases and opaque
-- replacement layers stay on the old two-quad fast path.
function PANEL:NeedsStraightLayerRecovery()
	if self.VisualOpaque then return false end
	if not self.BaseHasAlpha then return false end

	for _, raw in ipairs( self.Layers or {} ) do
		local layer = AdvMat.Ops.SanitizeLayer and AdvMat.Ops.SanitizeLayer( raw ) or raw

		if layer and layer.on ~= false and ( layer.opacity or 1 ) > 0 then
			if ( layer.opacity or 1 ) < 1 then return true end

			-- An explicitly opaque layer at full opacity replaces the destination,
			-- as does a mounted texture known not to carry alpha.  Unknown header
			-- state is conservatively recovered rather than risking dark fringes.
			if not layer.opaque then
				local hasAlpha = AdvMat.Gen.SourceHasAlpha
					and AdvMat.Gen.SourceHasAlpha( layer.src )
				if hasAlpha ~= false then return true end
			end
		end
	end

	return false
end

--- Fraction of the true straight colour retained after the bounded recovery.
--- Kept as a method so the numerical guarantee can be regression-tested
--- without requiring a renderer.
function PANEL:StraightLayerRecoveryCoverage( alpha )
	alpha = math.max( 0, math.min( tonumber( alpha ) or 0, 1 ) )
	return 1 - ( 1 - alpha ) ^ ( 2 ^ PREVIEW_RECOVERY_STAGES )
end

local function RecoveryMaterial( name, rt )
	local mat = CreateMaterial( name, "UnlitGeneric", {
		[ "$basetexture" ] = rt and rt:GetName() or "color/white",
		[ "$translucent" ] = "1",
		[ "$vertexalpha" ] = "1",
		[ "$vertexcolor" ] = "1",
		[ "$nocull" ]      = "1",
		[ "$nolod" ]       = "1",
		[ "$ignorez" ]     = "1",
	} )

	if rt then mat:SetTexture( "$basetexture", rt ) end
	return mat
end

--- Lazily allocate two ping-pong targets. Most edited materials are opaque,
--- so they retain the original memory and draw cost.
function PANEL:EnsureLayerRecoveryTargets()
	local size = self.SizeW .. "x" .. self.SizeH
	if self.RecoverySize == size and self.RecoveryRTA and self.RecoveryRTB
		and self.RecoveryMatA and self.RecoveryMatB then
		return true
	end

	self.RecoveryRTA = GetRenderTarget( "advmat_canvas_recover_a_" .. size,
		self.SizeW, self.SizeH )
	self.RecoveryRTB = GetRenderTarget( "advmat_canvas_recover_b_" .. size,
		self.SizeW, self.SizeH )
	if not self.RecoveryRTA or not self.RecoveryRTB then return false end

	self.RecoveryMatA = RecoveryMaterial(
		"advmat_canvas_recover_a_mat_" .. size, self.RecoveryRTA )
	self.RecoveryMatB = RecoveryMaterial(
		"advmat_canvas_recover_b_mat_" .. size, self.RecoveryRTB )
	self.RecoverySize = size
	return true
end

local previewPos

local function PreviewVertex( x, y, u, v )
	previewPos = previewPos or Vector()
	previewPos:SetUnpacked( x, y, 0 )
	mesh.Position( previewPos )
	mesh.TexCoord( 0, u, v )
	mesh.Color( 255, 255, 255, 255 )
	mesh.AdvanceVertex()
end

local function DrawPreviewQuad( mat, w, h )
	render.SetMaterial( mat )
	mesh.Begin( MATERIAL_QUADS, 1 )
		PreviewVertex( 0, 0, 0, 0 )
		PreviewVertex( w, 0, 1, 0 )
		PreviewVertex( w, h, 1, 1 )
		PreviewVertex( 0, h, 0, 1 )
	mesh.End()
end

local function BeginStraightOver()
	render.OverrideBlend( true,
		BLEND_SRC_ALPHA, BLEND_ONE_MINUS_SRC_ALPHA, BLENDFUNC_ADD,
		BLEND_ONE, BLEND_ONE_MINUS_SRC_ALPHA, BLENDFUNC_ADD )
end

local function BeginPremultipliedOver()
	render.OverrideBlend( true,
		BLEND_ONE, BLEND_ONE_MINUS_SRC_ALPHA, BLENDFUNC_ADD,
		BLEND_ONE, BLEND_ONE_MINUS_SRC_ALPHA, BLENDFUNC_ADD )
end

--- Bind one target while preserving every render override even if its draw
--- fails. The outer PumpComposite pcall owns the error and retry budget.
local function IntoCompositeTarget( rt, draw )
	render.PushRenderTarget( rt )
	-- Start the projection only after the target is bound. Start2D captures the
	-- current viewport, so opening it against the screen and then swapping to an
	-- oblong texture target scales or clips every recovery quad.
	cam.Start2D()
	local ok, err = pcall( draw )
	render.OverrideBlend( false )
	render.OverrideColorWriteEnable( false, true )
	render.OverrideAlphaWriteEnable( true, true )
	cam.End2D()
	render.PopRenderTarget()
	if not ok then error( err, 0 ) end
end

--- Copy the finished operation stack into the public preview target, then draw
--- imported layers at the target's native resolution. This path is shared by
--- the flat canvas and the model preview because both consume self.RT.
function PANEL:PumpComposite()
	if not self.Buf or self.Dirty or self.Pending or not self.CompositeDirty then return end

	local base = self:EnsureTarget()
	local rt   = self.RT
	if not base or not rt or not self.BaseMat then return end

	self.CompositeDirty = false
	render.OverrideAlphaWriteEnable( true, true )

	local ok, err = pcall( function()
		local recover = self:NeedsStraightLayerRecovery()
		if recover and not self:EnsureLayerRecoveryTargets() then
			error( "could not allocate straight-alpha preview targets" )
		end

		IntoCompositeTarget( rt, function()
			render.Clear( 0, 0, 0, 0, true, true )

			if recover then
				-- Seed a genuine premultiplied base. DrawLayers then performs
				-- Porter-Duff over in that same representation.
				BeginStraightOver()
				DrawPreviewQuad( self.BaseMat, self.SizeW, self.SizeH )
				render.OverrideBlend( false )
			else
				-- Opaque destinations and full-opacity replacements need no
				-- conversion and keep the original single-copy fast path.
				AdvMat.Gen.DrawMaterialCopy(
					self.BaseMat, 0, 0, self.SizeW, self.SizeH )
			end

			local layersOK, layersErr = AdvMat.Ops.DrawLayers(
				self.Layers, self.SizeW, self.SizeH, self.VisualOpaque )
			if not layersOK then error( layersErr ) end
		end )

		if not recover then return end

		-- Compositing the premultiplied result over itself doubles the number
		-- of equivalent samples each stage. After nine ping-pongs its RGB is
		-- straight to byte precision for every alpha value the editor regards
		-- as recoverable. The original public target retains authoritative A.
		local sourceMat = self.RTMat
		for stage = 1, PREVIEW_RECOVERY_STAGES do
			local destRT, destMat
			if stage % 2 == 1 then
				destRT, destMat = self.RecoveryRTA, self.RecoveryMatA
			else
				destRT, destMat = self.RecoveryRTB, self.RecoveryMatB
			end

			IntoCompositeTarget( destRT, function()
				render.Clear( 0, 0, 0, 0, true, true )
				BeginPremultipliedOver()
				DrawPreviewQuad( sourceMat, self.SizeW, self.SizeH )
				DrawPreviewQuad( sourceMat, self.SizeW, self.SizeH )
			end )
			sourceMat = destMat
		end

		-- Replace only RGB; alpha stays the exact Porter-Duff result from the
		-- first pass. Seed RGB from the edited base before laying the recovered
		-- visible colour over it. A mathematically alpha-zero composite has zero
		-- recovery coverage, so this preserves its hidden base colour instead of
		-- substituting black (which texture filtering would expose as a fringe).
		-- The recovery target is still premultiplied (RGB = colour * coverage),
		-- so premultiplied-over applies that coverage exactly once. Its alpha
		-- equation is irrelevant because alpha writes remain disabled here.
		IntoCompositeTarget( rt, function()
			render.OverrideAlphaWriteEnable( true, false )
			AdvMat.Gen.DrawMaterialCopy(
				self.BaseMat, 0, 0, self.SizeW, self.SizeH )
			BeginPremultipliedOver()
			DrawPreviewQuad( sourceMat, self.SizeW, self.SizeH )
		end )
	end )

	render.OverrideBlend( false )
	render.OverrideColorWriteEnable( false, true )
	render.OverrideAlphaWriteEnable( false, false )

	if not ok then
		self.CompositeFailures = ( self.CompositeFailures or 0 ) + 1
		-- A material can be unavailable for one render hook while it is being
		-- created. Retry a couple of frames, but do not spin forever on a missing
		-- texture. Any subsequent edit resets this small failure budget.
		self.CompositeDirty = self.CompositeFailures < 3
		AdvMat.Log( "Canvas layer composite failed: %s", tostring( err ) )
		return
	end

	self.CompositeFailures = 0
	if self.OnUploaded then self:OnUploaded() end
end

--- How much of the upload is left, so the window can show a progress bar
--- instead of looking frozen on a big change.
function PANEL:UploadProgress()
	if not self.Pending then return 1 end
	if #self.Pending == 0 then return 1 end
	return math.Clamp( ( self.Cursor - 1 ) / #self.Pending, 0, 1 )
end

---------------------------------------------------------------------------
-- Drawing a render target
---------------------------------------------------------------------------
-- Everything on this panel that is not the panel itself arrives as a render
-- target stretched over one rectangle - and that rectangle is handed to the
-- GPU directly, as a mesh quad with explicit texture coordinates. It does not
-- go through the surface library at all.
--
-- That rule was bought with two measurements, and it exists because surface's
-- textured rectangles apply half texel corrections of their own that cannot be
-- switched off, only guessed at.
--
-- The first measurement: marks written into the canvas at known pixels read
-- back out of it at exactly those pixels, and then landed on screen 6.64%
-- further from the middle than the rectangle they were drawn into. That is the
-- half texel inset - s0 = 0.5/w, s1 = 1 - 0.5/w - computed for the 16 pixel
-- color/white the material was created against before the target was swapped
-- in: 16 texels of a 512 target cropped from every side, 480 of 512 shown,
-- a magnification of 1.0667 against a measured 1.0664.
--
-- Fixing that - materials born pointing at their target, coordinates passed
-- explicitly - removed the 6.64% and left a second, smaller error: the second
-- measurement found the picture still magnified x1.004, showing 510.02 of 512
-- texels. That is DrawTexturedRectUV applying its own correction ON TOP of the
-- coordinates it is given, now computed for the right texture. The size of the
-- correction changes with the API's opinion of the texture; the existence of
-- one does not. So no surface call draws these quads any more: the mesh goes
-- to the GPU with u = 0 to 1 and nothing between it and the sampler.
--
-- The symptoms, for the next reader: a stale or built-in inset crops
-- symmetrically, so it magnifies about the centre - the middle of the sheet is
-- always right and the error grows towards the edges. It applies to the image
-- and to every overlay drawn the same way, so they all agree with each other
-- and only things drawn straight onto the panel (the pointer, the brush ring)
-- disagree. That is why an earlier round moved the overlays INTO targets and
-- called it fixed: it made them wrong in the same way as the image, which
-- reads as right.

--- Draw `mat` into the screen-space rectangle x, y, w, h, sampling the whole
--- of its texture, exactly.
---
--- Screen space rather than panel space: surface draws are panel-relative
--- through surface's own offset, which a raw mesh does not see, so the caller
--- adds its own LocalToScreen. The scissor rect still applies - it is render
--- state, not surface state.
local function BlitTarget( mat, x, y, w, h, r, g, b, a, copy )
	render.SetMaterial( mat )

	-- cam.Start2D so the quad is in plain screen pixels whatever matrix the
	-- panel traversal has current. DModelPanel does the same with Start3D.
	cam.Start2D()
	if copy then
		-- Ignore the texture's alpha for this one screen-space presentation.
		-- The underlying target is unchanged and still carries the mask into the
		-- model preview and exported PNG.
		render.OverrideBlend( true,
			BLEND_ONE, BLEND_ZERO, BLENDFUNC_ADD,
			BLEND_ONE, BLEND_ZERO, BLENDFUNC_ADD )
	end

	mesh.Begin( MATERIAL_QUADS, 1 )
		mesh.Position( Vector( x, y, 0 ) )
		mesh.TexCoord( 0, 0, 0 )
		mesh.Color( r, g, b, a )
		mesh.AdvanceVertex()

		mesh.Position( Vector( x + w, y, 0 ) )
		mesh.TexCoord( 0, 1, 0 )
		mesh.Color( r, g, b, a )
		mesh.AdvanceVertex()

		mesh.Position( Vector( x + w, y + h, 0 ) )
		mesh.TexCoord( 0, 1, 1 )
		mesh.Color( r, g, b, a )
		mesh.AdvanceVertex()

		mesh.Position( Vector( x, y + h, 0 ) )
		mesh.TexCoord( 0, 0, 1 )
		mesh.Color( r, g, b, a )
		mesh.AdvanceVertex()
	mesh.End()

	if copy then render.OverrideBlend( false ) end
	cam.End2D()
end

---------------------------------------------------------------------------
-- Overlays
---------------------------------------------------------------------------
-- The wireframe, the selection and the hover outline are all rasterised into
-- render targets and then drawn over the image as textured rectangles - the
-- same way the image itself arrives.
--
-- That is deliberate, but the reason recorded here for two rounds was wrong and
-- is worth keeping straight. Drawing them onto the panel at "x0 + u * side" did
-- not land where the image did - which was true, and was read as the panel
-- being the unreliable one. It was the image: it was being drawn magnified by a
-- stale half texel inset, and putting the overlays through targets too only
-- made them wrong in the same way. See the note above, and the measurement in
-- it. Now that the inset is gone either approach would land correctly; the
-- targets stay because one call placing every layer is still the arrangement
-- with nowhere for them to disagree.
--
-- Both targets are a fixed 1024 on their longer side whatever the texture's own
-- size is, so their placement depends on nothing but the rectangle they are
-- drawn into. The shorter side follows the image's shape: an outline stretched
-- two to one across an oblong sheet is drawn with two-to-one pixels, and reads
-- as a smear along one axis and a hairline along the other.

-- Remix does not reliably sample a render target through the UI material path:
-- the UV target is populated, but drawing its material can produce no pixels.
-- Keep that compatibility workaround entirely separate from vanilla. The
-- Remix path stores the already-parsed UV edges in line meshes and transforms
-- their normalised coordinates straight into the exact rectangle occupied by
-- the texture. Ten thousand triangles are 60,000 line vertices, below the
-- 65,535-vertex limit of one Source IMesh.
local RTX_UV_TRIANGLES_PER_CHUNK = 10000
local rtxUVMaterial

local function RTXUVMaterial()
	rtxUVMaterial = rtxUVMaterial or CreateMaterial( "advmat_canvas_rtx_uv", "UnlitGeneric", {
		[ "$basetexture" ] = "color/white",
		[ "$translucent" ] = "1",
		[ "$vertexalpha" ] = "1",
		[ "$vertexcolor" ] = "1",
		[ "$nocull" ]      = "1",
		[ "$nolod" ]       = "1",
		[ "$ignorez" ]     = "1",
	} )

	return rtxUVMaterial
end

function PANEL:DestroyRTXUVMeshes()
	for _, imesh in ipairs( self.RTXUVMeshes or {} ) do
		if imesh and imesh.Destroy then imesh:Destroy() end
	end

	self.RTXUVMeshes = nil
	self.RTXUVGroup = nil
end

function PANEL:BuildRTXUVMeshes()
	self:DestroyRTXUVMeshes()

	local group = self.UVModel
		and AdvMat.Mesh.Group( self.UVModel, self.UVPath, self.UVSlot, self.UVMask )
	if not group or not istable( group.tris ) or #group.tris == 0 then return end

	-- Static meshes inherit their vertex format from this hint. Use the exact
	-- material they are drawn with so COLOR0 is present on every client.
	local material = RTXUVMaterial()
	if not material or material:IsError() then return end

	local out = {}
	local pos = Vector()

	local function Vertex( u, v )
		pos.x, pos.y, pos.z = u, v, 0
		mesh.Position( pos )
		mesh.Color( 90, 130, 170, 255 )
		mesh.AdvanceVertex()
	end

	for first = 1, #group.tris, RTX_UV_TRIANGLES_PER_CHUNK do
		local last = math.min( first + RTX_UV_TRIANGLES_PER_CHUNK - 1, #group.tris )
		local imesh = Mesh( material )
		mesh.Begin( imesh, MATERIAL_LINES, ( last - first + 1 ) * 3 )

		for i = first, last do
			local t = group.tris[ i ]
			Vertex( t[ 1 ], t[ 2 ] ) Vertex( t[ 3 ], t[ 4 ] )
			Vertex( t[ 3 ], t[ 4 ] ) Vertex( t[ 5 ], t[ 6 ] )
			Vertex( t[ 5 ], t[ 6 ] ) Vertex( t[ 1 ], t[ 2 ] )
		end

		mesh.End()
		out[ #out + 1 ] = imesh
	end

	self.RTXUVMeshes = out
	self.RTXUVGroup = group
end

function PANEL:DrawRTXUVMeshes( x, y, w, h )
	local meshes = self.RTXUVMeshes
	if not meshes or #meshes == 0 or w <= 0 or h <= 0 then return end

	local material = RTXUVMaterial()
	if not material or material:IsError() then return end

	-- SetScale and SetTranslation write independent matrix components, avoiding
	-- an order-dependent Translate/Scale product that can also scale the offset.
	local transform = Matrix()
	transform:SetScale( Vector( w, h, 1 ) )
	transform:SetTranslation( Vector( x, y, 0 ) )

	render.SetMaterial( material )
	render.SetColorModulation( 1, 1, 1 )
	render.SetBlend( ( self.UVAlpha or 150 ) / 255 )
	cam.Start2D()
	cam.PushModelMatrix( transform )

	for _, imesh in ipairs( meshes ) do imesh:Draw() end

	cam.PopModelMatrix()
	cam.End2D()
	render.SetBlend( 1 )
	render.SetColorModulation( 1, 1, 1 )
end

local OVERLAY = 1024

--- An UnlitGeneric wrapper for a render target, so the surface library can draw
--- it.
local function OverlayMaterial( name, rt, additive )
	-- Named rather than swapped in afterwards: see the half texel note above.
	-- Vertex colour and no culling because these are drawn as raw mesh quads.
	local kv = {
		[ "$basetexture" ] = rt and rt:GetName() or "color/white",
		[ "$vertexcolor" ] = "1",
		[ "$vertexalpha" ] = "1",
		[ "$nocull" ]      = "1",
		[ "$nolod" ]       = "1",
		[ "$ignorez" ]     = "1",
	}

	if additive then
		kv[ "$additive" ] = "1"
	else
		kv[ "$translucent" ] = "1"
	end

	local mat = CreateMaterial( name, "UnlitGeneric", kv )
	if rt then mat:SetTexture( "$basetexture", rt ) end

	return mat
end

--- Run `draw` with `rt` bound and a 2D context set up, leaving the render
--- target stack and the context balanced whatever happens inside.
local function IntoTarget( rt, transparent, draw )
	render.PushRenderTarget( rt )

	if transparent then render.OverrideAlphaWriteEnable( true, true ) end
	cam.Start2D()

	local ok, err = pcall( draw )

	cam.End2D()
	if transparent then render.OverrideAlphaWriteEnable( false, false ) end
	render.PopRenderTarget()

	if not ok then AdvMat.Log( "Overlay draw failed: %s", tostring( err ) ) end
end

--- The overlay targets' own size: 1024 along the image's longer axis, and the
--- image's own proportion along the other.
function PANEL:OverlayDims()
	local w, h = self.SizeW or 512, self.SizeH or 512

	if w <= 0 or h <= 0 then return OVERLAY, OVERLAY end

	if w >= h then
		return OVERLAY, math.max( math.floor( OVERLAY * h / w + 0.5 ), 1 )
	end

	return math.max( math.floor( OVERLAY * w / h + 0.5 ), 1 ), OVERLAY
end

--- The model's UV layout. Rebuilt only when the model or sub-material changes:
--- a dense mesh is tens of thousands of lines and has no business being redrawn
--- every frame.
function PANEL:EnsureUV()
	if not self.UVDirty then return end
	self.UVDirty = false
	if self.RTXCompatibility then
		self:BuildRTXUVMeshes()
		return
	end

	local ow, oh = self:OverlayDims()

	-- GetRenderTarget hands back whatever is registered under a name, so the
	-- shape has to be part of the name or the next texture of a different shape
	-- silently gets this one.
	if self.UVRTW ~= ow or self.UVRTH ~= oh then
		self.UVRT  = GetRenderTarget( "advmat_canvas_uv_" .. ow .. "x" .. oh, ow, oh )
		self.UVMat = nil
		self.UVRTW, self.UVRTH = ow, oh
	end

	if not self.UVRT then return end

	local additive, transparent, lineAlpha, _, suffix = self:UVCompositeMode()

	self.UVMat = self.UVMat
		or OverlayMaterial( "advmat_canvas_uvmat" .. suffix .. "_" .. ow .. "x" .. oh,
			self.UVRT, additive )

	local group = self.UVModel
		and AdvMat.Mesh.Group( self.UVModel, self.UVPath, self.UVSlot, self.UVMask )

	IntoTarget( self.UVRT, transparent, function()
		-- Vanilla adds the coloured target over the image. RTX instead reads
		-- alpha from a transparent target, because its additive UI material path
		-- drops this layer entirely.
		render.Clear( 0, 0, 0, transparent and 0 or 255, true, true )
		if not group then return end

		surface.SetDrawColor( 90, 130, 170, lineAlpha )

		for _, t in ipairs( group.tris ) do
			local ax, ay = t[ 1 ] * ow, t[ 2 ] * oh
			local bx, by = t[ 3 ] * ow, t[ 4 ] * oh
			local cx, cy = t[ 5 ] * ow, t[ 6 ] * oh

			surface.DrawLine( ax, ay, bx, by )
			surface.DrawLine( bx, by, cx, cy )
			surface.DrawLine( cx, cy, ax, ay )
		end
	end )
end

--- The selection and the piece under the cursor. Rebuilt whenever either
--- changes, which is user-paced and always a bounded amount of drawing.
function PANEL:EnsureOverlay()
	if not self.OverlayDirty then return end
	self.OverlayDirty = false

	local ow, oh = self:OverlayDims()

	if self.SelRTW ~= ow or self.SelRTH ~= oh then
		self.SelRT  = GetRenderTarget( "advmat_canvas_sel_" .. ow .. "x" .. oh, ow, oh )
		self.SelMat = nil
		self.SelRTW, self.SelRTH = ow, oh
	end

	if not self.SelRT then return end

	self.SelMat = self.SelMat
		or OverlayMaterial( "advmat_canvas_selmat_" .. ow .. "x" .. oh, self.SelRT, false )

	if not self.Ants then self:BuildAnts() end
	if not self.Tint then self:BuildTint() end

	local show  = self.ShowSel
	local tint  = self.Tint
	local ants  = self.Ants
	local hover = self.HoverTris

	IntoTarget( self.SelRT, true, function()
		render.Clear( 0, 0, 0, 0, true, true )

		if show == "both" or show == "shading" then
			surface.SetDrawColor( 90, 200, 255, 70 )

			for _, run in ipairs( tint or {} ) do
				surface.DrawRect( run[ 1 ] * ow, run[ 2 ] * oh,
					math.max( run[ 3 ] * ow, 1 ), math.max( run[ 4 ] * oh, 1 ) )
			end
		end

		if show == "both" or show == "outline" then
			-- Drawn twice, a pixel apart: a single colour outline disappears
			-- against one end of the range or the other, and a character skin
			-- reliably contains both.
			for pass = 1, 2 do
				local off  = ( pass == 1 ) and 1 or 0
				local grey = ( pass == 1 ) and 0 or 255

				surface.SetDrawColor( grey, grey, grey, 255 )

				for _, seg in ipairs( ants or {} ) do
					surface.DrawLine(
						seg[ 1 ] * ow + off, seg[ 2 ] * oh + off,
						seg[ 3 ] * ow + off, seg[ 4 ] * oh + off )
				end
			end
		end

		if hover then
			surface.SetDrawColor( 120, 235, 255, 220 )

			for i = 1, math.min( #hover, 8000 ) do
				local t = hover[ i ]

				local ax, ay = t[ 1 ] * ow, t[ 2 ] * oh
				local bx, by = t[ 3 ] * ow, t[ 4 ] * oh
				local cx, cy = t[ 5 ] * ow, t[ 6 ] * oh

				surface.DrawLine( ax, ay, bx, by )
				surface.DrawLine( bx, by, cx, cy )
				surface.DrawLine( cx, cy, ax, ay )
			end
		end
	end )
end

--- Which parts of the selection are drawn. Baked into the overlay target, so
--- changing it has to rebuild.
function PANEL:SetShowSelection( mode )
	if self.ShowSel == mode then return end

	self.ShowSel      = mode
	self.OverlayDirty = true
end

--- The piece under the cursor, outlined before a click commits to it.
function PANEL:SetHover( tris )
	if self.HoverTris == tris then return end

	self.HoverTris    = tris
	self.OverlayDirty = true
end

---------------------------------------------------------------------------
-- Marching ants
---------------------------------------------------------------------------
-- The outline is traced once into a list of segments in texture space and only
-- rebuilt when the selection changes. Tracing it every frame drops the editor
-- into single figures.

local MAX_ANTS = 1500

-- Runs of selected pixels, for the tint. Far more forgiving than the ant count:
-- a run is a whole horizontal span, so even a complicated island is a few
-- hundred of them.
local MAX_TINT = 6000

function PANEL:BuildAnts()
	self.Ants = {}
	self.AntsClipped = false

	local mask = self.Mask
	if not mask or not self.Buf then return end

	local w, h  = self.Buf.w, self.Buf.h
	local ants  = self.Ants

	-- Emitted as fractions of the texture, not as buffer pixels. The wireframe,
	-- the outline and the shading then all reach the screen through the same
	-- `x0 + u * side`, and there is nowhere left for them to disagree about
	-- where a triangle is.
	local fx, fy = 1 / w, 1 / h

	local function Inside( x, y )
		if x < 0 or y < 0 or x >= w or y >= h then return false end
		return mask[ y * w + x + 1 ] >= 128
	end

	-- Horizontal edges, merged along each row into runs.
	for y = 0, h do
		local run = nil

		for x = 0, w - 1 do
			local edge = Inside( x, y ) ~= Inside( x, y - 1 )

			if edge then
				run = run or x
			elseif run then
				ants[ #ants + 1 ] = { run * fx, y * fy, x * fx, y * fy }
				run = nil
			end
		end

		if run then ants[ #ants + 1 ] = { run * fx, y * fy, 1, y * fy } end
		if #ants > MAX_ANTS then self.AntsClipped = true return end
	end

	-- Vertical edges, merged down each column.
	for x = 0, w do
		local run = nil

		for y = 0, h - 1 do
			local edge = Inside( x, y ) ~= Inside( x - 1, y )

			if edge then
				run = run or y
			elseif run then
				ants[ #ants + 1 ] = { x * fx, run * fy, x * fx, y * fy }
				run = nil
			end
		end

		if run then ants[ #ants + 1 ] = { x * fx, run * fy, x * fx, 1 } end
		if #ants > MAX_ANTS then self.AntsClipped = true return end
	end
end

--- Horizontal runs of selected pixels, so the tint is a few hundred rectangles
--- rather than one per pixel.
---
--- An outline alone is not enough to tell where a selection is. At the zoom
--- that fits a 1024 sheet into a panel, a thin piece is two or three pixels
--- wide and its outline reads as a smudge - which is exactly when someone needs
--- to know whether they picked the right piece.
function PANEL:BuildTint()
	self.Tint = {}

	local mask = self.Mask
	if not mask or not self.Buf then return end

	local w, h = self.Buf.w, self.Buf.h
	local runs = self.Tint

	-- Fractions of the texture, for the same reason the outline uses them.
	local fx, fy = 1 / w, 1 / h

	for y = 0, h - 1 do
		local row   = y * w
		local start = nil

		for x = 0, w - 1 do
			if mask[ row + x + 1 ] >= 128 then
				start = start or x
			elseif start then
				runs[ #runs + 1 ] = { start * fx, y * fy, ( x - start ) * fx, fy }
				start = nil
			end
		end

		if start then runs[ #runs + 1 ] = { start * fx, y * fy, ( w - start ) * fx, fy } end
		if #runs > MAX_TINT then return end
	end
end

---------------------------------------------------------------------------
-- Coordinates
---------------------------------------------------------------------------
function PANEL:Scale() return ZOOMS[ self.Zoom ] or 1 end

--- Panel pixels -> image pixels.
function PANEL:ToImage( sx, sy )
	local s = self:Scale()
	return self.PanX + sx / s, self.PanY + sy / s
end

--- Image pixels -> panel pixels.
function PANEL:ToPanel( ix, iy )
	local s = self:Scale()
	return ( ix - self.PanX ) * s, ( iy - self.PanY ) * s
end

--- Panel pixels -> normalised 0..1 texture coordinates, which is the only
--- form any recipe ever stores.
function PANEL:ToNorm( sx, sy )
	local ix, iy = self:ToImage( sx, sy )
	return ix / self.SizeW, iy / self.SizeH
end

local function Atan2( y, x )
	if x > 0 then return math.atan( y / x ) end
	if x < 0 and y >= 0 then return math.atan( y / x ) + math.pi end
	if x < 0 then return math.atan( y / x ) - math.pi end
	if y > 0 then return math.pi * 0.5 end
	if y < 0 then return -math.pi * 0.5 end
	return 0
end

--- Screen geometry for the selected imported layer. Rotation is done in image
--- pixels, not normalised coordinates, so an oblong canvas cannot skew it.
function PANEL:LayerGeometry()
	local layer = self.LayerTransform
	if not layer then return nil end

	local cx, cy = ( layer.x or 0.5 ) * self.SizeW, ( layer.y or 0.5 ) * self.SizeH
	local hw, hh = ( layer.w or 1 ) * self.SizeW * 0.5,
		( layer.h or 1 ) * self.SizeH * 0.5
	local rad = math.rad( layer.angle or 0 )
	local co, si = math.cos( rad ), math.sin( rad )

	local function P( lx, ly )
		local ix = cx + lx * co - ly * si
		local iy = cy + lx * si + ly * co
		return { self:ToPanel( ix, iy ) }
	end

	local corners = { P( -hw, -hh ), P( hw, -hh ), P( hw, hh ), P( -hw, hh ) }
	local top = P( 0, -hh )
	local s = self:Scale()
	local rotate = P( 0, -hh - 28 / math.max( s, 0.001 ) )
	local pcx, pcy = self:ToPanel( cx, cy )

	return {
		cx = pcx, cy = pcy, imageX = cx, imageY = cy,
		hw = hw, hh = hh, co = co, si = si,
		corners = corners, top = top, rotate = rotate,
	}
end

function PANEL:HitLayer( mx, my )
	local geo = self:LayerGeometry()
	if not geo then return nil end

	local function Near( p, radius )
		local dx, dy = mx - p[ 1 ], my - p[ 2 ]
		return dx * dx + dy * dy <= radius * radius
	end

	local ix, iy = self:ToImage( mx, my )
	local dx, dy = ix - geo.imageX, iy - geo.imageY
	local lx = geo.co * dx + geo.si * dy
	local ly = -geo.si * dx + geo.co * dy
	local inside = math.abs( lx ) <= geo.hw and math.abs( ly ) <= geo.hh

	if Near( geo.rotate, 12 ) then return "rotate", geo end

	-- Keep a usable move target in the middle even when the whole imported
	-- decal is smaller than the fixed-size corner handles at the current zoom.
	-- Exact resizing remains available in the layer controls for extremely
	-- small layers whose entire on-canvas body becomes this move target.
	local scale = math.max( self:Scale(), 0.001 )
	local centreW = math.min( geo.hw, math.max( geo.hw * 0.45, 6 / scale ) )
	local centreH = math.min( geo.hh, math.max( geo.hh * 0.45, 6 / scale ) )
	if inside and math.abs( lx ) <= centreW and math.abs( ly ) <= centreH then
		return "move", geo
	end

	for i, p in ipairs( geo.corners ) do
		if Near( p, 11 ) then return "resize", geo, i end
	end

	if inside then return "move", geo end

	return nil, geo
end

function PANEL:FitToWindow()
	local w, h = self:GetWide(), self:GetTall()
	if w <= 0 or h <= 0 then return end

	self.WantFit = nil

	-- Whichever axis runs out first, so an oblong sheet fits whole rather than
	-- being cropped along its long side.
	local want = math.min( w / self.SizeW, h / self.SizeH )
	local best = 1

	for i, z in ipairs( ZOOMS ) do
		if z <= want then best = i end
	end

	self.Zoom = best

	local s = ZOOMS[ best ]
	self.PanX = ( self.SizeW - w / s ) * 0.5
	self.PanY = ( self.SizeH - h / s ) * 0.5
end

function PANEL:ZoomBy( delta, atX, atY )
	local before = self:Scale()
	local ix, iy = self:ToImage( atX or self:GetWide() * 0.5, atY or self:GetTall() * 0.5 )

	self.Zoom = math.Clamp( self.Zoom + delta, 1, #ZOOMS )

	local after = self:Scale()
	if before == after then return end

	-- Keep whatever was under the cursor under the cursor.
	self.PanX = ix - ( atX or self:GetWide() * 0.5 ) / after
	self.PanY = iy - ( atY or self:GetTall() * 0.5 ) / after
end

---------------------------------------------------------------------------
-- Mouse
---------------------------------------------------------------------------
local function ModeFromKeys()
	local shift = input.IsKeyDown( KEY_LSHIFT ) or input.IsKeyDown( KEY_RSHIFT )
	local ctrl  = input.IsKeyDown( KEY_LCONTROL ) or input.IsKeyDown( KEY_RCONTROL )

	if shift and ctrl then return "int" end
	if shift then return "add" end
	if ctrl  then return "sub" end
	return nil
end

--- The combine mode a new shape should use: whatever the buttons say, unless a
--- modifier is held, in which case that wins for this one drag.
function PANEL:CurrentMode()
	return ModeFromKeys() or self.Mode
end

function PANEL:OnMousePressed( code )
	if not self.Buf then return end

	-- Mouse capture is not optional. Without it a drag that leaves the panel
	-- never delivers a release, and the stroke sticks to the cursor for good.
	self:MouseCapture( true )
	self:RequestFocus()

	local mx, my = self:CursorPos()

	if code == MOUSE_MIDDLE or self.Tool == "pan" then
		self.Panning = { mx, my, self.PanX, self.PanY }
		return
	end

	if code == MOUSE_RIGHT then
		self.Panning = { mx, my, self.PanX, self.PanY }
		return
	end

	if self.Tool == "layer" and self.LayerTransform then
		local kind, geo, corner = self:HitLayer( mx, my )
		if kind then
			local ix, iy = self:ToImage( mx, my )
			local pointerAngle = math.deg( Atan2( iy - geo.imageY, ix - geo.imageX ) )
			self.LayerDrag = {
				kind = kind, corner = corner, startIX = ix, startIY = iy,
				startMX = mx, startMY = my, changed = false,
				startX = self.LayerTransform.x, startY = self.LayerTransform.y,
				startW = self.LayerTransform.w, startH = self.LayerTransform.h,
				angleOffset = ( self.LayerTransform.angle or 0 ) - pointerAngle,
			}
			return
		end
	end

	local u, v = self:ToNorm( mx, my )

	if self.Tool == "box" or self.Tool == "ellipse" then
		self.Drag = { kind = "rect", u0 = u, v0 = v, u1 = u, v1 = v }

	elseif self.Tool == "gradient" then
		self.Drag = { kind = "gradient", u0 = u, v0 = v, u1 = u, v1 = v }

	elseif self.Tool == "lasso" then
		self.Drag = { kind = "poly", pts = { u, v } }

	elseif self.Tool == "paint" or self.Tool == "erase" then
		self.Drag = { kind = "stroke", pts = { u, v } }

		-- Told at once rather than on release, so the stroke can be drawn
		-- under the pointer from its very first dab.
		if self.OnStrokeBegin then self:OnStrokeBegin( self.Drag.pts ) end

	elseif self.Tool == "wand" then
		if self.OnShape then
			self:OnShape( {
				t = "wand", x = u, y = v,
				tol = self.Tolerance or 0.1,
				contiguous = self.Contiguous ~= false,
				mode = self:CurrentMode(),
			} )
		end

	elseif self.Tool == "island" then
		if self.OnShape then
			self:OnShape( { t = "uvisland", x = u, y = v, mode = self:CurrentMode() } )
		end

	elseif self.Tool == "fill" then
		if self.OnFill then self:OnFill( u, v ) end

	elseif self.Tool == "pick" then
		self.Drag = { kind = "pick" }
		if self.OnPick then self:OnPick( u, v ) end
	end
end

function PANEL:OnCursorMoved( mx, my )
	if not self.Buf then return end

	local u, v = self:ToNorm( mx, my )
	self.HoverU, self.HoverV = u, v

	if self.OnHover then self:OnHover( u, v ) end

	if self.Panning then
		local s = self:Scale()
		self.PanX = self.Panning[ 3 ] - ( mx - self.Panning[ 1 ] ) / s
		self.PanY = self.Panning[ 4 ] - ( my - self.Panning[ 2 ] ) / s
		return
	end

	if self.LayerDrag and self.LayerTransform then
		local drag, layer = self.LayerDrag, self.LayerTransform
		local ix, iy = self:ToImage( mx, my )
		if not drag.changed then
			local pdx, pdy = mx - drag.startMX, my - drag.startMY
			if pdx * pdx + pdy * pdy <= 1 then return end
			drag.changed = true
			-- Defer the snapshot until a real drag begins. A simple click now keeps
			-- redo history intact and does not manufacture a no-op undo entry.
			if self.OnLayerBegin then self:OnLayerBegin( layer ) end
		end

		if drag.kind == "move" then
			layer.x = math.Clamp( drag.startX + ( ix - drag.startIX ) / self.SizeW, -2, 3 )
			layer.y = math.Clamp( drag.startY + ( iy - drag.startIY ) / self.SizeH, -2, 3 )

		elseif drag.kind == "rotate" then
			local angle = math.deg( Atan2(
				iy - ( layer.y or 0.5 ) * self.SizeH,
				ix - ( layer.x or 0.5 ) * self.SizeW ) ) + drag.angleOffset
			while angle > 180 do angle = angle - 360 end
			while angle < -180 do angle = angle + 360 end
			layer.angle = angle

		elseif drag.kind == "resize" then
			local rad = math.rad( layer.angle or 0 )
			local co, si = math.cos( rad ), math.sin( rad )
			local dx = ix - ( layer.x or 0.5 ) * self.SizeW
			local dy = iy - ( layer.y or 0.5 ) * self.SizeH
			local nw = math.max( 0.002, 2 * math.abs( co * dx + si * dy ) / self.SizeW )
			local nh = math.max( 0.002, 2 * math.abs( -si * dx + co * dy ) / self.SizeH )

			if self.LayerKeepAspect then
				local scale = math.max( nw / math.max( drag.startW, 0.002 ),
					nh / math.max( drag.startH, 0.002 ) )
				local minScale = math.max( 0.002 / math.max( drag.startW, 0.002 ),
					0.002 / math.max( drag.startH, 0.002 ) )
				local maxScale = math.min( 4 / math.max( drag.startW, 0.002 ),
					4 / math.max( drag.startH, 0.002 ) )
				scale = math.Clamp( scale, minScale, maxScale )
				nw, nh = drag.startW * scale, drag.startH * scale
				layer.w, layer.h = nw, nh
			else
				layer.w, layer.h = math.min( nw, 4 ), math.min( nh, 4 )
			end
		end

		if self.OnLayerChanged then self:OnLayerChanged( layer ) end
		return
	end

	local drag = self.Drag
	if not drag then return end

	if drag.kind == "rect" or drag.kind == "gradient" then
		drag.u1, drag.v1 = u, v

	elseif drag.kind == "poly" or drag.kind == "stroke" then
		local pts = drag.pts
		local n   = #pts

		-- Only record a point once the cursor has actually moved, or a slow
		-- drag fills the cap with hundreds of coincident points.
		local dx = u - pts[ n - 1 ]
		local dy = v - pts[ n ]

		if dx * dx + dy * dy > 0.000004 then
			pts[ n + 1 ] = u
			pts[ n + 2 ] = v

			if drag.kind == "stroke" and self.OnStrokeMoved then self:OnStrokeMoved( drag.pts ) end
		end

	elseif drag.kind == "pick" then
		if self.OnPick then self:OnPick( u, v ) end
	end
end

function PANEL:OnMouseReleased()
	self:MouseCapture( false )

	self.Panning = nil

	if self.LayerDrag then
		local changed = self.LayerDrag.changed
		self.LayerDrag = nil
		if changed and self.OnLayerCommit then self:OnLayerCommit( self.LayerTransform ) end
		return
	end

	local drag = self.Drag
	self.Drag = nil
	if not drag then return end

	local mode = self:CurrentMode()

	if drag.kind == "gradient" then
		-- A click is a useful no-op, not an accidental full-canvas fill. The
		-- recipe treats coincident endpoints as one solid foreground colour, so
		-- require a real one-pixel drag before committing it.
		local dx = ( drag.u1 - drag.u0 ) * math.max( 1, self.SizeW or 1 )
		local dy = ( drag.v1 - drag.v0 ) * math.max( 1, self.SizeH or 1 )
		if dx * dx + dy * dy >= 1 and self.OnGradient then
			self:OnGradient( drag.u0, drag.v0, drag.u1, drag.v1 )
		end

	elseif drag.kind == "rect" then
		local x0, x1 = math.min( drag.u0, drag.u1 ), math.max( drag.u0, drag.u1 )
		local y0, y1 = math.min( drag.v0, drag.v1 ), math.max( drag.v0, drag.v1 )

		if self.Square then
			-- Square in the texture's own pixels. On an oblong sheet that is
			-- not a square in the 0..1 coordinates the shape is stored in, and
			-- a "square" selection that comes out two to one is not one.
			local px = math.min( ( x1 - x0 ) * self.SizeW, ( y1 - y0 ) * self.SizeH )

			x1 = x0 + px / self.SizeW
			y1 = y0 + px / self.SizeH
		end

		if self.OnShape then
			self:OnShape( {
				t = ( self.Tool == "ellipse" ) and "ellipse" or "rect",
				x = x0, y = y0, w = x1 - x0, h = y1 - y0,
				mode = mode,
			} )
		end

	elseif drag.kind == "poly" then
		if self.OnShape and #drag.pts >= 6 then
			self:OnShape( { t = "poly", pts = drag.pts, mode = mode } )
		end

	elseif drag.kind == "stroke" then
		if self.OnStroke then self:OnStroke( drag.pts, self.Brush, self.Hardness or 1 ) end
	end
end

function PANEL:OnCursorExited()
	self.HoverU, self.HoverV = nil, nil
	if self.OnHover then self:OnHover( nil, nil ) end

	-- The cursor was hidden for the brush ring; leaving without putting it
	-- back loses the pointer for the whole rest of the window.
	self:SetCursor( "arrow" )
end

function PANEL:OnMouseWheeled( delta )
	local mx, my = self:CursorPos()

	if input.IsKeyDown( KEY_LCONTROL ) or input.IsKeyDown( KEY_RCONTROL ) then
		if self.OnBrushWheel then self:OnBrushWheel( delta ) end
		return true
	end

	self:ZoomBy( delta, mx, my )
	return true
end

-- The upload happens outside Paint. Writing to a render target does not need a
-- render hook, and pushing one in the middle of a panel's own 2D pass is a
-- reliable way to corrupt whatever is drawn next to it.
function PANEL:Think()
	-- Both overlays write to a render target, which is why they are built here
	-- rather than in Paint: pushing one in the middle of a panel's own 2D pass
	-- corrupts whatever is drawn next to it.
	self:EnsureUV()
	self:EnsureOverlay()

	-- A patch is drawn over a finished upload, never under one still running.
	if self.Buf and ( self.Dirty or self.Pending ) then
		self:PumpUpload()
	elseif self.Buf and self.Patch then
		self:PumpPatch()
	end

	if self.Buf and self.CompositeDirty and not self.Dirty and not self.Pending then
		self:PumpComposite()
	end
end

---------------------------------------------------------------------------
-- Painting
---------------------------------------------------------------------------
--- The transparency checker, clipped to what is actually on screen.
---
--- Drawing it across the whole image would mean a million rectangles a frame at
--- sixteen times zoom on a 512 texture, for squares that are almost all outside
--- the panel. `vw`/`vh` are the visible bounds it is clamped to.
local function Checkerboard( x, y, w, h, vw, vh )
	surface.SetDrawColor( 70, 72, 78, 255 )
	surface.DrawRect( x, y, w, h )

	local x0 = math.max( x, 0 )
	local y0 = math.max( y, 0 )
	local x1 = math.min( x + w, vw )
	local y1 = math.min( y + h, vh )

	if x1 <= x0 or y1 <= y0 then return end

	surface.SetDrawColor( 92, 94, 100, 255 )

	-- Squares are anchored to the image, not to the screen, so panning does not
	-- make the pattern crawl.
	local first = math.floor( ( x0 - x ) / CHECKER )
	local firstY = math.floor( ( y0 - y ) / CHECKER )

	for cy = firstY, math.ceil( ( y1 - y ) / CHECKER ) - 1 do
		for cx = first, math.ceil( ( x1 - x ) / CHECKER ) - 1 do
			if ( cx + cy ) % 2 == 0 then
				local sx = x + cx * CHECKER
				local sy = y + cy * CHECKER

				surface.DrawRect( sx, sy,
					math.min( CHECKER, x + w - sx ),
					math.min( CHECKER, y + h - sy ) )
			end
		end
	end
end

function PANEL:Paint( w, h )
	surface.SetDrawColor( 24, 25, 29, 255 )
	surface.DrawRect( 0, 0, w, h )

	if not self.Buf then
		draw.SimpleText( AdvMat.LText( "Nothing loaded" ), "AdvMatText", w * 0.5, h * 0.5,
			T.TextFaint, TEXT_ALIGN_CENTER, TEXT_ALIGN_CENTER )
		return
	end

	local s  = self:Scale()
	local x0, y0 = self:ToPanel( 0, 0 )
	local iw, ih = self.SizeW * s, self.SizeH * s

	-- Everything is clipped to the panel, so a texture zoomed past the edges
	-- does not scribble over the toolbar next to it.
	local sx, sy = self:LocalToScreen( 0, 0 )
	render.SetScissorRect( sx, sy, sx + w, sy + h, true )

	-- Kept for advmat_probe: the rectangle the image was ACTUALLY put in, in
	-- screen coordinates, recorded at the moment it was drawn.
	--
	-- Every mapping in this file is an exact identity on the page, so if a
	-- click still lands somewhere else then one of the values feeding it is not
	-- what it appears to be, and no amount of reading will say which. This lets
	-- a click be checked against where the picture WENT rather than against
	-- where this panel believes it is - which is the one link that cannot be
	-- checked without running the game.
	local seen = self.LastRect

	if not seen then
		seen = {}
		self.LastRect = seen
	end

	seen.sx, seen.sy = sx, sy
	seen.x0, seen.y0 = x0, y0
	seen.w, seen.h   = iw, ih
	seen.at          = FrameNumber and FrameNumber() or 0

	-- The transparency checker sits behind the image, so an erased area reads
	-- as see-through rather than as black.
	Checkerboard( x0, y0, iw, ih, w, h )

	-- Raw mesh quads, not surface: see the note above BlitTarget. Every layer
	-- goes through the same call for the same reason - they have to land where
	-- the image lands, and the image has to land in the rectangle the pointer
	-- is measured against.
	if self.RTMat then
		BlitTarget( self.RTMat, sx + x0, sy + y0, iw, ih,
			255, 255, 255, 255, self.VisualOpaque )
	end

	-- Vanilla overlays arrive through the same exact quad as the image. Remix's
	-- UV material path drops the target, so its normalized line mesh is instead
	-- transformed straight into this exact screen-space rectangle.
	if self.ShowUV and self.RTXCompatibility then
		local uvX, uvY = sx + x0, sy + y0
		local uvClipX0, uvClipY0 = math.max( sx, uvX ), math.max( sy, uvY )
		local uvClipX1 = math.min( sx + w, uvX + iw )
		local uvClipY1 = math.min( sy + h, uvY + ih )

		-- A Source model may deliberately tile outside 0..1. The vanilla UV
		-- target clips those coordinates at its own edge; preserve that contract
		-- for the direct Remix mesh instead of drawing into the workspace.
		if uvClipX1 > uvClipX0 and uvClipY1 > uvClipY0 then
			render.SetScissorRect( uvClipX0, uvClipY0, uvClipX1, uvClipY1, true )
			self:DrawRTXUVMeshes( uvX, uvY, iw, ih )
			render.SetScissorRect( sx, sy, sx + w, sy + h, true )
		end
	elseif self.ShowUV and self.UVMat then
		local _, _, _, drawAlpha = self:UVCompositeMode()
		BlitTarget( self.UVMat, sx + x0, sy + y0, iw, ih,
			255, 255, 255, drawAlpha )
	end

	if self.SelMat then
		BlitTarget( self.SelMat, sx + x0, sy + y0, iw, ih, 255, 255, 255, 255 )
	end

	-- "Select all" has no mask to bake an outline from - everything is inside
	-- it - so its outline is the edge of the picture, drawn the same two-pass
	-- grey and white as the marching ants so it reads as a selection.
	if self.SelAll and self.ShowSel ~= "off" then
		surface.SetDrawColor( 0, 0, 0, 255 )
		surface.DrawOutlinedRect( x0 + 1, y0 + 1, iw - 2, ih - 2, 1 )
		surface.SetDrawColor( 255, 255, 255, 255 )
		surface.DrawOutlinedRect( x0 + 2, y0 + 2, iw - 4, ih - 4, 1 )
	end

	self:PaintSelection( w, h )
	self:PaintLayerTransform()
	self:PaintDrag( x0, y0, s )
	self:PaintCursor( w, h, s )

	render.SetScissorRect( 0, 0, 0, 0, false )

	-- A frame, so the edge of the texture is obvious against the background.
	surface.SetDrawColor( T.Line.r, T.Line.g, T.Line.b, 255 )
	surface.DrawOutlinedRect( x0, y0, iw, ih, 1 )
end

function PANEL:OnRemove()
	self:DestroyRTXUVMeshes()
end

function PANEL:PaintLayerTransform()
	if self.Tool ~= "layer" or not self.LayerTransform then return end

	local geo = self:LayerGeometry()
	if not geo then return end

	local corners = geo.corners
	surface.SetDrawColor( 70, 215, 255, 245 )
	for i = 1, 4 do
		local a, b = corners[ i ], corners[ ( i % 4 ) + 1 ]
		surface.DrawLine( a[ 1 ], a[ 2 ], b[ 1 ], b[ 2 ] )
	end

	surface.DrawLine( geo.top[ 1 ], geo.top[ 2 ], geo.rotate[ 1 ], geo.rotate[ 2 ] )
	surface.DrawOutlinedRect( geo.rotate[ 1 ] - 5, geo.rotate[ 2 ] - 5, 10, 10, 1 )

	for _, p in ipairs( corners ) do
		surface.SetDrawColor( 18, 20, 24, 255 )
		surface.DrawRect( p[ 1 ] - 5, p[ 2 ] - 5, 10, 10 )
		surface.SetDrawColor( 70, 215, 255, 255 )
		surface.DrawOutlinedRect( p[ 1 ] - 5, p[ 2 ] - 5, 10, 10, 1 )
	end

	surface.DrawLine( geo.cx - 5, geo.cy, geo.cx + 5, geo.cy )
	surface.DrawLine( geo.cx, geo.cy - 5, geo.cx, geo.cy + 5 )
end

--- Everything that is not part of the image itself and is not in world space.
---
--- The selection's own shading and outline are baked into the overlay target
--- and drawn with the image; only the dimming lives here, because it covers the
--- whole panel rather than the texture.
function PANEL:PaintSelection( w, h )
	if not self.Mask or self.ShowSel == "off" then return end

	-- Dimming everything outside the selection is what makes "the rest is
	-- protected" visible instead of something the user has to infer.
	if self.DimOutside and self.ShowSel ~= "outline" then
		surface.SetDrawColor( 0, 0, 0, 90 )
		surface.DrawRect( 0, 0, w, h )
	end
end

function PANEL:PaintDrag( x0, y0, s )
	local drag = self.Drag
	if not drag then return end

	local kx, ky = self.SizeW * s, self.SizeH * s

	surface.SetDrawColor( 120, 200, 255, 220 )

	if drag.kind == "gradient" then
		local ax, ay = x0 + drag.u0 * kx, y0 + drag.v0 * ky
		local bx, by = x0 + drag.u1 * kx, y0 + drag.v1 * ky

		-- A dark under-line keeps the guide legible over pale textures, while
		-- the cyan centre matches the other live selection previews.
		surface.SetDrawColor( 0, 0, 0, 210 )
		for offset = -1, 1 do
			surface.DrawLine( ax + offset, ay, bx + offset, by )
			surface.DrawLine( ax, ay + offset, bx, by + offset )
		end

		surface.SetDrawColor( 120, 200, 255, 240 )
		surface.DrawLine( ax, ay, bx, by )
		surface.DrawOutlinedRect( ax - 4, ay - 4, 8, 8, 1 )
		surface.DrawOutlinedRect( bx - 4, by - 4, 8, 8, 1 )

		local dx = ( drag.u1 - drag.u0 ) * self.SizeW
		local dy = ( drag.v1 - drag.v0 ) * self.SizeH
		draw.SimpleText( math.Round( math.sqrt( dx * dx + dy * dy ) ) .. " px",
			"AdvMatSmall", bx + 8, by + 8, T.Text )

	elseif drag.kind == "rect" then
		local ax, ay = x0 + drag.u0 * kx, y0 + drag.v0 * ky
		local bx, by = x0 + drag.u1 * kx, y0 + drag.v1 * ky

		surface.DrawOutlinedRect( math.min( ax, bx ), math.min( ay, by ),
			math.abs( bx - ax ), math.abs( by - ay ), 1 )

		-- A live size readout, because "how big is this going to be" is the
		-- question a rectangle drag always raises.
		draw.SimpleText(
			math.Round( math.abs( drag.u1 - drag.u0 ) * self.SizeW ) .. " x " ..
			math.Round( math.abs( drag.v1 - drag.v0 ) * self.SizeH ),
			"AdvMatSmall", bx + 8, by + 8, T.Text )

	-- A stroke drawn live is its own preview, and a line along its middle would
	-- only hide what it is doing. The line is left for the one stroke that
	-- cannot be drawn until it is released.
	elseif drag.kind == "poly" or ( drag.kind == "stroke" and not self.LiveStroke ) then
		local pts = drag.pts

		for i = 1, #pts - 3, 2 do
			surface.DrawLine(
				x0 + pts[ i     ] * kx, y0 + pts[ i + 1 ] * ky,
				x0 + pts[ i + 2 ] * kx, y0 + pts[ i + 3 ] * ky )
		end

		if drag.kind == "poly" and #pts >= 4 then
			-- A ghost line back to the start, so closing the shape is never a
			-- surprise.
			surface.SetDrawColor( 120, 200, 255, 90 )
			surface.DrawLine(
				x0 + pts[ #pts - 1 ] * kx, y0 + pts[ #pts ] * ky,
				x0 + pts[ 1 ] * kx, y0 + pts[ 2 ] * ky )
		end
	end
end

local function AltHeld()
	return input and input.IsKeyDown
		and ( input.IsKeyDown( KEY_LALT ) or input.IsKeyDown( KEY_RALT ) ) or false
end

--- Which of its two jobs the eraser is doing: "revert" brings the original
--- back, "holes" makes the texture see-through. A stroke in progress keeps the
--- mode it began with; otherwise it is the one chosen in the tool options,
--- turned over while Alt is held. Nil for every other tool.
function PANEL:EraserMode()
	if self.Tool ~= "erase" then return nil end
	if self.StrokeMode then return self.StrokeMode end

	local mode = ( self.EraseMode == "holes" ) and "holes" or "revert"
	if AltHeld() then mode = ( mode == "holes" ) and "revert" or "holes" end

	return mode
end

function PANEL:PaintCursor( w, h, s )
	if not self.HoverU then return end

	local paintish = ( self.Tool == "paint" or self.Tool == "erase" )
	if not paintish then
		self:SetCursor( "arrow" )
		return
	end

	-- There is no way to supply a custom cursor bitmap, so the pointer is
	-- hidden and the true brush size drawn in its place.
	self:SetCursor( "blank" )

	local mx, my = self:CursorPos()

	-- The brush is round in the texture's own pixels, and its radius is stored
	-- against the mean of the two axes - which is what the rasteriser uses, so
	-- the ring on screen is the area that actually gets painted.
	local r = self.Brush * ( self.SizeW + self.SizeH ) * 0.5 * s

	-- The eraser's two jobs look exactly alike until something has been rubbed
	-- away, so the pointer says which one it is doing - including the moment
	-- Alt turns it over. A dashed ring cuts holes.
	local mode = self:EraserMode()

	if mode then
		local label = ( mode == "holes" ) and "Make see-through" or "Back to original"
		draw.SimpleTextOutlined( AdvMat.LText and AdvMat.LText( label ) or label,
			"AdvMatSmall", mx + r * 0.71 + 6, my + r * 0.71 + 4,
			Color( 255, 255, 255, 235 ), TEXT_ALIGN_LEFT, TEXT_ALIGN_TOP,
			1, Color( 0, 0, 0, 220 ) )
	end

	local segs = 32
	local dashed = ( mode == "holes" )

	for i = 0, segs - 1 do
		if not dashed or ( i % 2 == 0 ) then
			local a0 = ( i / segs ) * math.pi * 2
			local a1 = ( ( i + 1 ) / segs ) * math.pi * 2

			surface.SetDrawColor( 0, 0, 0, 200 )
			surface.DrawLine( mx + math.cos( a0 ) * ( r + 1 ), my + math.sin( a0 ) * ( r + 1 ),
			                  mx + math.cos( a1 ) * ( r + 1 ), my + math.sin( a1 ) * ( r + 1 ) )

			surface.SetDrawColor( 255, 255, 255, 230 )
			surface.DrawLine( mx + math.cos( a0 ) * r, my + math.sin( a0 ) * r,
			                  mx + math.cos( a1 ) * r, my + math.sin( a1 ) * r )
		end
	end

	surface.SetDrawColor( 255, 255, 255, 230 )
	surface.DrawRect( mx, my, 1, 1 )
end

vgui.Register( "AdvMatCanvas", PANEL, "DPanel" )
