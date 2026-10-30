--[[---------------------------------------------------------------------------
	Advanced Material Editor - the model preview's controls

	The preview beside the canvas is not decoration. It is the primary way to
	find a piece of a texture, because nobody can look at a character's skin
	sheet and point at the jacket and everybody can point at the jacket on the
	model. That only works if the jacket can be SEEN.

	Two things get in the way of that, and this file is both of them.

	  A character stands in one pose. Anything folded into an armpit, tucked
	  under a skirt or hidden behind an arm cannot be looked at, let alone
	  clicked. So the preview can be animated and scrubbed to a frame.

	  The part you want is often behind a part you do not care about - hair
	  over a face, a coat over a shirt. So parts and sub-materials can be
	  hidden.

	Neither touches what is being edited. Hiding a part changes what the
	preview draws, never what is written; the recipe and the .vmt come out
	identical either way.

	Two rules run through all of it.

	  Hiding a part hides it from CLICKING too. Rays are fired at the geometry
	  the model reports, so if that still contains a hood nobody can see any
	  more, clicking the head behind it selects the hood - which is exactly the
	  "I clicked here and it selected there" failure this editor exists to
	  avoid. The geometry is therefore re-read for the parts on show, and a
	  hide that would take away the material being edited is refused rather
	  than leaving an editor that cannot select anything.

	  A moving model cannot be clicked. Every vertex has to be put through its
	  bones before a ray can be fired at it, and on a character that is far too
	  much work to redo sixty times a second. So while an animation plays the
	  preview is a viewer only: hovering stops highlighting, and clicking it
	  stops the animation first - on the frame that was on screen - and then
	  selects from that pose.
-----------------------------------------------------------------------------]]

AdvMat = AdvMat or {}
AdvMat.ModelView = AdvMat.ModelView or {}

local MV = AdvMat.ModelView
local T  = AdvMat.Theme

-- Half speed is the useful one: most character idles are subtle and the frame
-- you want has gone past before you can react to it. Quarter is for a swing.
local SPEEDS = { 0.25, 0.5, 1, 2 }

---------------------------------------------------------------------------
-- State
---------------------------------------------------------------------------

--- The playback state, created on demand so that nothing has to be set up in
--- any particular order.
function MV.State( frame )
	frame.Anim = frame.Anim or { playing = false, cycle = 0, speed = 1 }
	frame.HiddenMats = frame.HiddenMats or {}
	return frame.Anim
end

local function Ent( frame )
	local mp = frame.ModelPanel
	if not IsValid( mp ) or not IsValid( mp.Entity ) then return nil end
	AdvMat.AttachMMDPreview( mp.Entity )
	return mp.Entity
end

local function Short( path )
	return string.match( path or "", "([^/]+)$" ) or path or ""
end

local function RTXRenderContext( ctx )
	return ctx and ( ctx.rtx == true or ctx.rtxrender == true )
end

---------------------------------------------------------------------------
-- Hiding
---------------------------------------------------------------------------
local invisible

-- RTX Remix cannot reliably light Source's transient DModelPanel materials,
-- and a material whose base texture is a live render target is sampled black.
-- Untouched slots therefore use small UnlitGeneric mirrors which point at the
-- mounted texture already owned by the original VMT.  This is deliberately an
-- RTX-only display path: vanilla keeps drawing the model's materials exactly as
-- it did before.
--
-- Procedural materials cannot be freed.  Cache one mirror per source material
-- and keep a generous hard ceiling so browsing many models cannot leak without
-- bound for the rest of the map.
local rtxMirrors, rtxMirrorSerial = {}, 0
local MAX_RTX_MIRRORS = 512

local function MaterialFlag( mat, key )
	if not mat or not mat.GetInt then return false end
	local ok, value = pcall( mat.GetInt, mat, key )
	return ok and tonumber( value ) ~= nil and tonumber( value ) ~= 0
end

local function MaterialNumber( mat, key, fallback )
	if not mat or not mat.GetFloat then return fallback end
	local ok, value = pcall( mat.GetFloat, mat, key )
	value = ok and tonumber( value ) or nil
	return value ~= nil and value or fallback
end

--- A visible, disk-texture-backed version of one model material for RTX editor
--- previews.  The mounted base texture is copied as an ITexture;
--- pointing a new material at the VMT path itself would sample the VMT rather
--- than its image on some Source branches.
function MV.RTXMirrorMaterial( path )
	path = AdvMat.NormalizeMaterial and AdvMat.NormalizeMaterial( path or "" )
		or tostring( path or "" )
	if path == "" then return nil end

	local cached = rtxMirrors[ path ]
	if cached ~= nil then return cached or nil end
	if rtxMirrorSerial >= MAX_RTX_MIRRORS then return nil end

	local source = Material( path )
	if not source or ( source.IsError and source:IsError() ) then
		rtxMirrors[ path ] = false
		return nil
	end

	local ok, texture = pcall( source.GetTexture, source, "$basetexture" )
	if not ok or not texture then
		rtxMirrors[ path ] = false
		return nil
	end

	local kv = {
		[ "$basetexture" ] = texture.GetName and texture:GetName() or "color/white",
		[ "$model" ]       = "1",
		[ "$nocull" ]      = MaterialFlag( source, "$nocull" ) and "1" or "0",
		[ "$nolod" ]       = "1",
	}

	if MaterialFlag( source, "$translucent" ) then
		kv[ "$translucent" ] = "1"
	elseif MaterialFlag( source, "$alphatest" ) then
		kv[ "$alphatest" ] = "1"
		kv[ "$alphatestreference" ] = tostring(
			MaterialNumber( source, "$alphatestreference", 0.5 ) )
	end

	rtxMirrorSerial = rtxMirrorSerial + 1
	local mirror = CreateMaterial( "advmat_rtx_model_mirror_" .. rtxMirrorSerial,
		"UnlitGeneric", kv )
	if not mirror then
		rtxMirrors[ path ] = false
		return nil
	end

	-- SetTexture is the important part for Remix: it receives the mounted,
	-- non-render-target texture object rather than a procedural texture name.
	mirror:SetTexture( "$basetexture", texture )
	if mirror.Recompute then mirror:Recompute() end

	rtxMirrors[ path ] = mirror
	return mirror
end

--- A material that covers no pixels.
---
--- There is no "do not draw this sub-material" call, so hiding one means
--- replacing it with something that cannot be seen. Zero alpha on a
--- translucent unlit material is the cheapest thing that does that, and it
--- leaves the geometry exactly where it was - which is the point, because
--- hiding here is a change to the picture and not to the model.
local function Invisible()
	invisible = invisible or CreateMaterial( "advmat_invisible", "UnlitGeneric", {
		[ "$basetexture" ] = "color/white",
		[ "$alpha" ]       = "0",
		[ "$translucent" ] = "1",
		[ "$model" ]       = "1",
	} )

	return invisible
end

--- Resolve the material which an RTX editor DModelPanel must draw for one slot.
---
--- SetSubMaterial is ignored by the DX7 path used by the Remix client.  Keep
--- this policy separate from ApplyMaterials so vanilla continues to use the
--- normal entity API, while the RTX panel can feed the same choices directly
--- to render.MaterialOverrideByIndex immediately before it draws.
local function RTXSlotMaterial( frame, mats, slot )
	local edit = tonumber( frame.Ctx and frame.Ctx.slot ) or 0
	if slot == edit and frame.PreviewMat then return frame.PreviewMat end
	if ( frame.HiddenMats or {} )[ slot ] then return Invisible() end
	return MV.RTXMirrorMaterial( mats[ slot + 1 ] )
end

local function RTXMirrorSlotMaterial( frame, mats, slot )
	-- The main RTX editor can carry an ordinary Source/VMT working copy beside
	-- its PBR profile.  Let its stable RTX-safe mirror win for the affected real
	-- slot; untouched slots keep using the mounted-material locator mirrors.
	local sourcePanel = frame and frame.SourcePanel
	if IsValid( sourcePanel ) and sourcePanel.GetPreviewMaterial then
		local preview = sourcePanel:GetPreviewMaterial( slot )
		if preview then return preview end
	end
	return MV.RTXMirrorMaterial( mats[ slot + 1 ] )
end

local activeRTXDrawOwner

local function ResetRTXDrawOverrides()
	if render and render.MaterialOverrideByIndex then
		render.MaterialOverrideByIndex()
	end
	if render and render.ModelMaterialOverride then
		render.ModelMaterialOverride( nil, nil )
	end
	if activeRTXDrawOwner then
		activeRTXDrawOwner.RTXRenderOverrideActive = nil
	end
	activeRTXDrawOwner = nil
end

--- Install one resolver's RTX-only, per-slot overrides for a DModelPanel draw.
local function BeginRTXIndexedDraw( frame, ent, resolve )
	if not frame or not resolve then return false end
	if not ( render and render.MaterialOverrideByIndex ) then return false end

	ent = IsValid( ent ) and ent or Ent( frame )
	if not ent then return false end

	-- The official reset is a nil index.  Clear any interrupted previous panel
	-- draw before installing this frame's set.
	ResetRTXDrawOverrides()
	frame.RTXRenderOverrideActive = nil

	local mats = ent:GetMaterials() or {}
	local applied = false
	-- GMHLVK's preview draws native meshes using GetSubMaterial, so indexed
	-- engine overrides cannot reach it. Its entity API supports every slot.
	local nativePreview = ent.MMDHLEditorPreview ~= nil
	local count = nativePreview and #mats or math.min( #mats, 32 )
	for i = 1, count do
		local mat = resolve( frame, mats, i - 1 )
		if nativePreview then
			local name = mat and ( "!" .. mat:GetName() ) or ""
			-- Each write invalidates GMHLVK's material state. Client-only preview
			-- entities can report their own value, so avoid doing that every frame.
			if ent:GetSubMaterial( i - 1 ) ~= name then
				ent:SetSubMaterial( i - 1, name )
			end
			applied = true
		elseif mat then
			render.MaterialOverrideByIndex( i - 1, mat )
			applied = true
		end
	end

	frame.RTXRenderOverrideActive = applied or nil
	activeRTXDrawOwner = applied and frame or nil
	return applied
end

--- Draw a texture-editor preview, including its edited and hidden slots.
function MV.BeginRTXDraw( frame, ent )
	if not ( frame and RTXRenderContext( frame.Ctx ) ) then return false end
	return BeginRTXIndexedDraw( frame, ent, RTXSlotMaterial )
end

--- Draw a main-editor model locator with visible mounted-texture mirrors only.
--- It intentionally does not consume the texture editor's Ctx/PreviewMat state.
function MV.BeginRTXMirrorDraw( frame, ent )
	return BeginRTXIndexedDraw( frame, ent, RTXMirrorSlotMaterial )
end

--- Clear every indexed override before selection highlights are drawn.
function MV.EndRTXDraw( frame )
	if not frame or activeRTXDrawOwner ~= frame
		or not frame.RTXRenderOverrideActive then return false end

	-- MaterialOverrideByIndex with a nil index is Source's documented reset.
	-- RTXbase additionally resets its model override, so retain both operations
	-- for this client's DX7 compatibility path.
	ResetRTXDrawOverrides()
	return true
end

--- Put every sub-material back to what the current settings say it should be:
--- hidden ones invisible, the one being edited showing the edit, the rest the
--- model's own.
---
--- Done as one pass over all of them rather than one write per change, because
--- two separate things want to write to these slots - hiding, and the live
--- preview of the edit - and whichever ran last would otherwise win.
function MV.ApplyMaterials( frame )
	local ent = Ent( frame )
	if not ent then return end

	local edit = tonumber( frame.Ctx and frame.Ctx.slot ) or 0
	local mats = ent:GetMaterials() or {}
	local hide = frame.HiddenMats or {}
	local rtx  = RTXRenderContext( frame.Ctx )

	-- A model that will not report its materials can still be edited; it just
	-- cannot have anything hidden on it.
	if #mats == 0 then
		if frame.PreviewMat then
			ent:SetSubMaterial( edit, "!" .. frame.PreviewMat:GetName() )
		end
		return
	end

	for i = 1, #mats do
		local slot = i - 1

		if slot == edit and frame.PreviewMat then
			ent:SetSubMaterial( slot, "!" .. frame.PreviewMat:GetName() )
		elseif hide[ slot ] then
			ent:SetSubMaterial( slot, "!" .. Invisible():GetName() )
		elseif rtx then
			local mirror = MV.RTXMirrorMaterial( mats[ i ] )
			if mirror then
				ent:SetSubMaterial( slot, "!" .. mirror:GetName() )
			else
				ent:SetSubMaterial( slot )
			end
		else
			ent:SetSubMaterial( slot )
		end
	end
end

function MV.ToggleMaterial( frame, slot )
	MV.State( frame )

	frame.HiddenMats[ slot ] = ( not frame.HiddenMats[ slot ] ) or nil

	MV.ApplyMaterials( frame )
	MV.Hint( frame )
end

--- Change one bodygroup, and put it straight back if that took away the thing
--- being edited.
function MV.SetPart( frame, group, value )
	local ent = Ent( frame )
	if not ent then return end

	local was = ent:GetBodygroup( group )
	if was == value then return end

	ent:SetBodygroup( group, value )

	if frame.RebuildGroup and not frame:RebuildGroup() then
		-- Hiding this took the material being edited with it, so the flat
		-- sheet would have no outline left and the model nothing to click.
		-- Refusing is friendlier than that.
		ent:SetBodygroup( group, was )
		frame:RebuildGroup()

		if frame.Status then
			frame:Status( "That part carries the map you are editing, so it has to stay on.", true )
		end
		return
	end

	MV.ApplyMaterials( frame )
	MV.Hint( frame )
end

--- Every part back on, every sub-material back on.
function MV.ShowEverything( frame )
	local ent = Ent( frame )
	if not ent then return end

	for i = 0, ( ent:GetNumBodyGroups() or 0 ) - 1 do
		ent:SetBodygroup( i, 0 )
	end

	frame.HiddenMats = {}

	if frame.RebuildGroup then frame:RebuildGroup() end

	MV.ApplyMaterials( frame )
	MV.Hint( frame )
end

---------------------------------------------------------------------------
-- Playback
---------------------------------------------------------------------------

--- Called once a frame from the panel's LayoutEntity, which is the only place
--- a DModelPanel will let anything move its entity.
function MV.Advance( frame )
	local a   = frame.Anim
	local ent = Ent( frame )
	if not a or not ent then return end

	if not a.playing then
		-- A stopped animation is a held pose, not a paused film. The cycle is
		-- re-asserted every frame so nothing else can drift it out from under
		-- geometry that has already been skinned from it.
		ent:SetCycle( a.cycle or 0 )
		return
	end

	local now = RealTime()

	-- Clamped because the first frame after the window opens, or after the
	-- game has been paused, is arbitrarily long and would otherwise throw the
	-- animation most of the way through in a single step.
	local dt = math.Clamp( now - ( a.at or now ), 0, 0.1 )
	a.at = now

	ent:FrameAdvance( dt * ( a.speed or 1 ) )
	a.cycle = ent:GetCycle()

	-- Every vertex has just moved, so anything worked out from where they were
	-- is now wrong. Nothing is rebuilt here: while it plays, nothing asks.
	if frame.PoseChanged then frame:PoseChanged() end

	MV.SyncScrub( frame )
end

function MV.Play( frame, on )
	local a   = MV.State( frame )
	local ent = Ent( frame )

	if on and ent and not a.seq then
		-- Nothing has been chosen, so whatever DModelPanel found when the model
		-- was set is the right thing to play.
		a.seq = ent:GetSequence() or 0
	end

	a.playing = on and true or false
	a.at      = RealTime()

	if IsValid( frame.PlayBtn ) then
		frame.PlayBtn:SetText( a.playing and "Stop" or "Play" )
	end

	if frame.PoseChanged then frame:PoseChanged() end

	MV.Hint( frame )
end

function MV.Sequence( frame, id )
	local ent = Ent( frame )
	if not ent then return end

	local a = MV.State( frame )
	a.seq   = id
	a.cycle = 0

	ent:ResetSequence( id )
	ent:SetCycle( 0 )

	-- Inverse kinematics reaches for a floor and a world that a model panel
	-- does not have, and the result is a character sunk into nothing or with a
	-- foot flung out sideways.
	if ent.SetIK then ent:SetIK( false ) end

	MV.SyncScrub( frame )

	if frame.PoseChanged then frame:PoseChanged() end
end

--- Move to a point in the animation by hand. Scrubbing stops playback, because
--- the two fight over the same number and the user has just said which of them
--- they want.
function MV.Scrub( frame, frac )
	local a = MV.State( frame )
	if a.syncing then return end

	local ent = Ent( frame )
	if not ent then return end

	if a.playing then MV.Play( frame, false ) end

	a.cycle = math.Clamp( frac or 0, 0, 1 )
	ent:SetCycle( a.cycle )

	if frame.PoseChanged then frame:PoseChanged() end
end

--- Move the slider to follow the animation, without that being read back as
--- the user having dragged it.
function MV.SyncScrub( frame )
	if not IsValid( frame.Scrub ) then return end

	local a = MV.State( frame )

	a.syncing = true
	frame.Scrub:SetValue( math.Clamp( a.cycle or 0, 0, 1 ) * 100 )
	a.syncing = false
end

---------------------------------------------------------------------------
-- The line above the model
---------------------------------------------------------------------------
function MV.AnythingHidden( frame )
	if ( frame.BodyMask or 0 ) ~= 0 then return true end

	for _ in pairs( frame.HiddenMats or {} ) do return true end

	return false
end

--- Which of three things the hint says, and it matters: "clicking does
--- nothing" is a bug when the model is standing still, and something the user
--- did on purpose when it is moving or half hidden.
function MV.Hint( frame )
	if not IsValid( frame.ModelHint ) then return end

	local a = frame.Anim

	if a and a.playing then
		frame.ModelHint:SetText(
			"Playing. Click the model to stop on this frame and select from it." )
		frame.ModelHint:SetTextColor( T.Warn )
		return
	end

	local base = frame.ModelHintBase or ""

	if MV.AnythingHidden( frame ) then
		frame.ModelHint:SetText( base ..
			"  Some parts are hidden - those cannot be clicked until you show them again." )
		frame.ModelHint:SetTextColor( T.Warn )
	else
		frame.ModelHint:SetText( base )
		frame.ModelHint:SetTextColor( T.TextDim )
	end
end

---------------------------------------------------------------------------
-- Menus
---------------------------------------------------------------------------
function MV.PartsMenu( frame )
	local ent = Ent( frame )
	if not ent then return end

	local menu = DermaMenu()
	AdvMat.I18N.Track( menu )
	menu:SetMaxHeight( math.floor( ScrH() * 0.6 ) )

	local any = false

	for i = 0, ( ent:GetNumBodyGroups() or 0 ) - 1 do
		local count = ent:GetBodygroupCount( i ) or 0

		if count > 1 then
			any = true

			local name = ent:GetBodygroupName( i )
			if not name or name == "" then
				name = AdvMat.L( "model.part", { number = i } )
			end

			local sub = menu:AddSubMenu( name )
			local at  = ent:GetBodygroup( i )

			-- Models do not tell Lua what their options are called, only how
			-- many there are. The empty one is conventionally last, which is
			-- what the button's tooltip says.
			for v = 0, count - 1 do
				local opt = sub:AddOption(
					( v == 0 ) and AdvMat.L( "model.option_normal" )
						or AdvMat.L( "model.option", { number = v + 1 } ),
					function() MV.SetPart( frame, i, v ) end )

				opt:SetIsCheckable( true )
				opt:SetChecked( at == v )
			end
		end
	end

	if not any then
		menu:AddOption( "This model is one piece - it has no parts to hide." ):SetEnabled( false )
	else
		menu:AddSpacer()
		menu:AddOption( "Show everything", function() MV.ShowEverything( frame ) end )
	end

	menu:Open()
end

function MV.MaterialsMenu( frame )
	local ent = Ent( frame )
	if not ent then return end

	MV.State( frame )

	local mats = ent:GetMaterials() or {}
	local edit = tonumber( frame.Ctx and frame.Ctx.slot ) or 0

	local menu = DermaMenu()
	AdvMat.I18N.Track( menu )
	menu:SetMaxHeight( math.floor( ScrH() * 0.6 ) )

	if #mats == 0 then
		menu:AddOption( "This model does not report its materials." ):SetEnabled( false )
		menu:Open()
		return
	end

	menu:AddOption( "Ticked ones are shown" ):SetEnabled( false )
	menu:AddSpacer()

	for i = 1, #mats do
		local slot = i - 1

		if slot == edit then
			-- Hiding the one being edited would hide the edit, which is the one
			-- thing this window exists to look at.
			local opt = menu:AddOption( AdvMat.L( "model.being_edited", {
				material = Short( mats[ i ] ),
			} ) )
			opt:SetIsCheckable( true )
			opt:SetChecked( true )
			opt:SetEnabled( false )
		else
			local opt = menu:AddOption( Short( mats[ i ] ),
				function() MV.ToggleMaterial( frame, slot ) end )

			opt:SetIsCheckable( true )
			opt:SetChecked( not frame.HiddenMats[ slot ] )
		end
	end

	menu:AddSpacer()
	menu:AddOption( "Show everything", function() MV.ShowEverything( frame ) end )

	menu:Open()
end

---------------------------------------------------------------------------
-- Reset, for when the window is pointed at a model
---------------------------------------------------------------------------
function MV.Refresh( frame )
	local a = MV.State( frame )

	a.playing = false
	a.cycle   = 0
	a.seq     = nil

	frame.HiddenMats = {}

	local ent = Ent( frame )
	local n   = ent and ent.GetSequenceCount and ent:GetSequenceCount() or 0

	-- A neutral reference pose makes the UV preview predictable and exposes
	-- pieces that an arbitrary DModelPanel idle can fold or occlude. Prefer the
	-- model's named reference sequence, while retaining the engine-picked pose
	-- as a fallback for models that do not provide one.
	local reference = ent and ent.LookupSequence and ent:LookupSequence( "reference" )
	if isnumber( reference ) and reference >= 0 and reference < n then
		MV.Sequence( frame, reference )
	end

	if IsValid( frame.SeqBox ) then
		frame.SeqBox:Clear()

		for id = 0, n - 1 do
			local name = ent:GetSequenceName( id )
			if name and name ~= "" then frame.SeqBox:AddChoice( name, id ) end
		end

		local cur = ent and ent:GetSequence() or 0

		frame.SeqBox:SetValue( ( ent and n > 0 and ent:GetSequenceName( cur ) ) or "" )
		frame.SeqBox:SetEnabled( n > 1 )
	end

	if IsValid( frame.PlayBtn ) then
		frame.PlayBtn:SetText( "Play" )
		frame.PlayBtn:SetEnabled( n > 0 )
	end

	if IsValid( frame.Scrub ) then frame.Scrub:SetEnabled( n > 0 ) end

	MV.SyncScrub( frame )
	MV.ApplyMaterials( frame )
	MV.Hint( frame )
end

---------------------------------------------------------------------------
-- Construction
---------------------------------------------------------------------------

--- Build the strip that sits under the model preview. It docks BOTTOM, so it
--- has to be created before whatever fills the rest of `parent`.
function MV.Build( frame, parent )
	local rowH = AdvMat.RowHeight()

	MV.State( frame )

	local strip = vgui.Create( "DPanel", parent )
	strip:Dock( BOTTOM )
	strip:SetTall( rowH * 2 + ( rowH + 6 ) + 12 )
	strip:DockMargin( 0, 6, 0, 0 )
	strip.Paint = AdvMat.NoPaint

	frame.ModelStrip = strip

	------------------------------------------------------------- playback row
	local playRow = vgui.Create( "DPanel", strip )
	playRow:Dock( TOP )
	playRow:SetTall( rowH )
	playRow.Paint = AdvMat.NoPaint

	frame.PlayBtn = vgui.Create( "DButton", playRow )
	frame.PlayBtn:Dock( LEFT )
	frame.PlayBtn:SetWide( math.floor( AdvMat.FontSize * 3.6 ) )
	frame.PlayBtn:DockMargin( 0, 0, 4, 0 )
	frame.PlayBtn:SetText( "Play" )
	frame.PlayBtn:SetTooltip(
		"Move the model, so you can see a part that is folded away in its " ..
		"standing pose.\n\nWhile it is playing you cannot click it. Click " ..
		"once to stop on the frame you are looking at, then click the model " ..
		"to select from that pose." )
	AdvMat.StyleButton( frame.PlayBtn )

	frame.SpeedBox = vgui.Create( "DComboBox", playRow )
	frame.SpeedBox:Dock( RIGHT )
	frame.SpeedBox:SetWide( math.floor( AdvMat.FontSize * 3.6 ) )
	frame.SpeedBox:DockMargin( 4, 0, 0, 0 )
	frame.SpeedBox:SetTooltip( "How fast to play. Slower is easier to stop on the right frame." )
	AdvMat.StyleCombo( frame.SpeedBox )

	frame.SeqBox = vgui.Create( "DComboBox", playRow )
	frame.SeqBox:Dock( FILL )
	frame.SeqBox:SetTooltip(
		"Which animation to play. The names come out of the model, so what is " ..
		"in this list depends entirely on how it was built." )
	AdvMat.StyleCombo( frame.SeqBox )

	frame.PlayBtn.DoClick = function()
		MV.Play( frame, not MV.State( frame ).playing )
	end

	for _, mul in ipairs( SPEEDS ) do
		frame.SpeedBox:AddChoice( mul .. "x", mul, mul == 1 )
	end

	frame.SpeedBox.OnSelect = function( _, _, _, data )
		MV.State( frame ).speed = tonumber( data ) or 1
	end

	frame.SeqBox.OnSelect = function( _, _, _, data )
		MV.Sequence( frame, tonumber( data ) or 0 )
	end

	---------------------------------------------------------------- scrub row
	frame.Scrub = vgui.Create( "DNumSlider", strip )
	frame.Scrub:Dock( TOP )
	frame.Scrub:SetTall( rowH + 6 )
	frame.Scrub:DockMargin( 0, 2, 0, 2 )
	frame.Scrub:SetText( "Frame" )
	frame.Scrub:SetMin( 0 )
	frame.Scrub:SetMax( 100 )
	frame.Scrub:SetDecimals( 0 )
	frame.Scrub:SetTooltip(
		"Step through the animation by hand to hold exactly the pose you want. " ..
		"A held pose can be clicked." )
	AdvMat.StyleSlider( frame.Scrub )

	frame.Scrub.OnValueChanged = function( _, value )
		MV.Scrub( frame, ( tonumber( value ) or 0 ) / 100 )
	end

	----------------------------------------------------------- what shows row
	local showRow = vgui.Create( "DPanel", strip )
	showRow:Dock( TOP )
	showRow:SetTall( rowH )
	showRow.Paint = AdvMat.NoPaint

	local parts = vgui.Create( "DButton", showRow )
	parts:Dock( LEFT )
	parts:SetWide( math.floor( AdvMat.FontSize * 6 ) )
	parts:DockMargin( 0, 0, 4, 0 )
	parts:SetText( "Hide parts" )
	parts:SetTooltip(
		"Switch a bodygroup - hair, a coat, a hat - to another option so it " ..
		"stops covering what you are working on.\n\nModels do not tell the " ..
		"game what their options are called, only how many there are. The " ..
		"empty one is usually last.\n\nThis only changes the preview. Nothing " ..
		"about the material you are editing changes - but the editor does have " ..
		"to read the model again, which takes a moment on a detailed one." )
	AdvMat.StyleButton( parts )

	local mats = vgui.Create( "DButton", showRow )
	mats:Dock( LEFT )
	mats:SetWide( math.floor( AdvMat.FontSize * 7.5 ) )
	mats:DockMargin( 0, 0, 4, 0 )
	mats:SetText( "Hide materials" )
	mats:SetTooltip(
		"Stop drawing one of the model's other materials, so you can see " ..
		"past it to the one you are editing.\n\nThis only changes the " ..
		"preview. Nothing about the material you are editing changes." )
	AdvMat.StyleButton( mats )

	local reset = vgui.Create( "DButton", showRow )
	reset:Dock( LEFT )
	reset:SetWide( math.floor( AdvMat.FontSize * 6 ) )
	reset:SetText( "Reset view" )
	reset:SetTooltip(
		"Point the camera back at the material you are editing, from the " ..
		"front, at a distance that holds all of it.\n\nThe way back when the " ..
		"model has been dragged out of the view.\n\nTo turn around somewhere " ..
		"else instead, middle CLICK that spot - it moves to the middle and " ..
		"everything then turns around it." )
	AdvMat.StyleButton( reset )

	parts.DoClick = function() MV.PartsMenu( frame ) end
	mats.DoClick  = function() MV.MaterialsMenu( frame ) end
	reset.DoClick = function()
		if frame.ResetView then frame:ResetView() end
	end

	return strip
end
