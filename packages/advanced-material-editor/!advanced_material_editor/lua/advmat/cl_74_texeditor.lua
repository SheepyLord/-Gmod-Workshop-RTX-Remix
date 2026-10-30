--[[---------------------------------------------------------------------------
	Advanced Material Editor - the texture editor window

	Paint on a model's texture, cut holes in it, and mark out regions for the
	map generators to work inside.

	The layout is built around one decision: the 3D model is the primary way to
	SELECT things, and the flat texture is only where the paint lands. Nobody
	who has not done this before can look at a character skin sheet and find the
	jacket, but anyone can click the jacket on the model. So the model preview
	is not a decorative spinner off to one side - it does not spin at all, it is
	hit-tested, and clicking it selects the matching piece of the texture.

	Paint and effects become replayable steps; imported images remain an ordered
	layer stack above them. Both are stored as compact instructions rather than
	bitmap snapshots, can be edited again after reopening, and rebuild from the
	original source on every client.
-----------------------------------------------------------------------------]]

AdvMat = AdvMat or {}

local T   = AdvMat.Theme
local OPS = AdvMat.Ops
local SEL = AdvMat.Sel

-- Kept defensive for hot reloads and the lightweight Derma layout harness,
-- where this panel can exist briefly before the shared recipe module reloads.
local function PreservesSourceMask( recipe )
	return OPS.PreservesSourceMask and OPS.PreservesSourceMask( recipe ) or false
end

--- How a source is named on screen. An imported image's path is a content
--- hash; the name of the file it came from says more.
local function SourceLabel( src )
	if src and AdvMat.Import and AdvMat.Import.IsSource( src ) then
		return AdvMat.Import.Name( src ) or AdvMat.L( "import.image" )
	end
	return src
end

-- Remix cannot use a live GMod render target as a captured model texture.  Its
-- own pseudo-player does the same conversion: capture a small image, write it
-- under data/, then give the model the resulting ordinary texture.  Captures
-- are coalesced because dragging a layer slider can invalidate the canvas many
-- times in one second.
local RTX_PREVIEW_DIR   = "advmat/rtx_preview"
local RTX_PREVIEW_DELAY = 0.12
local RTX_PREVIEW_RETRY = 0.25
local RTX_PREVIEW_TRIES = 3
local RTX_PREVIEW_MAX_SIZE = 256

-- Colour controls can fire dozens of value changes during one drag.  A full
-- adjustment still visits every pixel in the working buffer, and replacing a
-- canvas upload before it finishes means no preview ever reaches the screen.
-- Keep the newest request, show it at an interactive cadence, and wait for the
-- previous canvas revision before starting the next one.
local ADJUST_PREVIEW_INTERVAL = 0.08

-- The editor composes at this resolution while you work, and the saved recipe
-- is baked at its own. Every coordinate is stored as a fraction of the texture
-- rather than in pixels, so the two agree exactly.
--
-- Held down to keep painting responsive: each step is a pass over the whole
-- buffer in Lua, and a megapixel of that per brush stroke is not affordable.
-- The canvas still DISPLAYS the source at its own resolution, so what is on
-- screen is sharp even though the edits are composed coarser.
--
--- The working size for an image of w x h: the same shape, halved until it
--- fits the budget.
---
--- Halving rather than scaling to fit keeps both sides powers of two, which is
--- what every texture is and what the render targets want.
local function WorkDims( w, h )
	return AdvMat.Gen.EditWorkDims( w, h )
end

local PANEL = {}

---------------------------------------------------------------------------
-- Tools
---------------------------------------------------------------------------
local TOOLS = {
	{ id = "island",  label = "Pick model piece", icon = "P",
	  shortcut = "P",
	  tip = "Click the model or the texture to select one connected piece of the skin.\n" ..
	        "This is the easy way to find the bit you want." },
	{ id = "box",     label = "Box select", icon = "[]",
	  shortcut = "R",
	  tip = "Drag out a rectangle." },
	{ id = "ellipse", label = "Round select", icon = "()",
	  shortcut = "E",
	  tip = "Drag out an oval." },
	{ id = "lasso",   label = "Freehand select", icon = "S",
	  shortcut = "F",
	  tip = "Draw around the area. It closes itself when you let go." },
	{ id = "wand",    label = "Pick same colour", icon = "W",
	  shortcut = "W",
	  tip = "Click a colour to select everything like it." },
	{ id = "paint",   label = "Paint", icon = "/",
	  shortcut = "B",
	  tip = "Brush colour on. Only inside the selection, if there is one." },
	{ id = "erase",   label = "Eraser", icon = "E",
	  shortcut = "Shift+E",
	  tip = "Rub out paint to bring back the original texture, or cut see-through holes." },
	{ id = "fill",    label = "Fill or recolour", icon = "F",
	  shortcut = "Shift+B",
	  tip = "Colour the whole selection in one click." },
	{ id = "gradient", label = "Gradient", icon = "G",
	  shortcut = "G",
	  tip = "Drag from the foreground colour to the background colour." },
	{ id = "pick",    label = "Colour picker", icon = "i",
	  shortcut = "O",
	  tip = "Take a colour from the texture or from the model." },
	{ id = "pan",     label = "Move the view", icon = "+",
	  shortcut = "H",
	  tip = "Drag to move the view around.\n" ..
	        "On the texture, middle or right mouse does this from any tool.\n" ..
	        "On the model, middle mouse moves it and right mouse turns it." },
	{ id = "layer",   label = "Transform layer", icon = "L",
	  shortcut = "M",
	  tip = "Move an imported texture layer, resize it by its corners, or drag " ..
	        "the handle above it to rotate." },
}

local SELECT_TOOLS = { island = true, box = true, ellipse = true, lasso = true, wand = true }

local MODES = {
	{ id = "replace", label = "Replace" },
	{ id = "add",     label = "Add" },
	{ id = "sub",     label = "Take away" },
	{ id = "int",     label = "Overlap only" },
}

local SHOW_SELECTION = {
	{ id = "both",    label = "Show: outline + shading" },
	{ id = "outline", label = "Show: outline" },
	{ id = "shading", label = "Show: shading" },
	{ id = "off",     label = "Show: nothing" },
}

-- The eraser does two different jobs, and the one it used to do alone - cut a
-- see-through hole - is rarely what someone reaching for an eraser after a
-- slip of the brush wants. Rubbing out paint is the default; the hole is one
-- click (or Alt) away, and the pointer always says which is active.
local ERASE_MODES = {
	{ id = "revert", label = "Back to original",
	  tip = "Rubs out paint, effects and holes, bringing back the texture you started from." },
	{ id = "holes",  label = "Make see-through",
	  tip = "Rubs the texture itself away, so the model shows a hole there." },
}

-- How far, in working pixels, a stored stroke may stray from the path the
-- pointer took. See Sel.CompactStroke: a third of a pixel is invisible, and it
-- is what lets a save carry hundreds of strokes instead of dozens.
local STROKE_TOLERANCE = 0.35

-- Original symbolic tool marks. They intentionally use only Derma drawing
-- primitives: GIMP is the interaction reference, but its GPL/CC-SA artwork is
-- not copied into an addon whose licence is unrelated.
local function ToolGlyph( id, x, y, size, col )
	local function Line( x1, y1, x2, y2 )
		surface.DrawLine( x + x1 * size, y + y1 * size, x + x2 * size, y + y2 * size )
	end
	local function Rect( x1, y1, w, h )
		surface.DrawOutlinedRect( x + x1 * size, y + y1 * size, w * size, h * size, 1 )
	end

	surface.SetDrawColor( col.r, col.g, col.b, col.a or 255 )

	if id == "box" then
		Rect( 0.18, 0.2, 0.64, 0.58 )
	elseif id == "ellipse" then
		local lastX, lastY
		for i = 0, 20 do
			local a = i / 20 * math.pi * 2
			local px, py = 0.5 + math.cos( a ) * 0.31, 0.5 + math.sin( a ) * 0.27
			if lastX then Line( lastX, lastY, px, py ) end
			lastX, lastY = px, py
		end
	elseif id == "lasso" then
		Line( 0.18, 0.3, 0.45, 0.16 ); Line( 0.45, 0.16, 0.8, 0.34 )
		Line( 0.8, 0.34, 0.7, 0.72 ); Line( 0.7, 0.72, 0.35, 0.8 )
		Line( 0.35, 0.8, 0.18, 0.3 ); Line( 0.7, 0.72, 0.86, 0.87 )
	elseif id == "wand" then
		Line( 0.25, 0.78, 0.69, 0.34 ); Line( 0.2, 0.2, 0.2, 0.08 )
		Line( 0.2, 0.2, 0.08, 0.2 ); Line( 0.8, 0.25, 0.92, 0.25 )
		Line( 0.82, 0.24, 0.82, 0.12 ); Line( 0.57, 0.08, 0.62, 0.2 )
	elseif id == "paint" then
		Line( 0.25, 0.78, 0.68, 0.35 ); Line( 0.3, 0.82, 0.73, 0.39 )
		Line( 0.68, 0.35, 0.8, 0.18 ); Line( 0.73, 0.39, 0.8, 0.18 )
	elseif id == "erase" then
		draw.NoTexture()
		surface.DrawPoly( {
			{ x = x + size * 0.2, y = y + size * 0.64 },
			{ x = x + size * 0.52, y = y + size * 0.22 },
			{ x = x + size * 0.82, y = y + size * 0.46 },
			{ x = x + size * 0.5, y = y + size * 0.82 },
		} )
	elseif id == "fill" then
		Line( 0.27, 0.24, 0.65, 0.62 ); Line( 0.65, 0.62, 0.43, 0.82 )
		Line( 0.43, 0.82, 0.18, 0.55 ); Line( 0.18, 0.55, 0.52, 0.2 )
		Line( 0.68, 0.67, 0.82, 0.82 )
	elseif id == "gradient" then
		for i = 0, 5 do
			local v = math.floor( 55 + i * 34 )
			surface.SetDrawColor( v, v, v, col.a or 255 )
			surface.DrawRect( x + size * ( 0.18 + i * 0.105 ), y + size * 0.25,
				size * 0.12, size * 0.5 )
		end
		surface.SetDrawColor( col.r, col.g, col.b, col.a or 255 )
		Rect( 0.18, 0.25, 0.65, 0.5 )
	elseif id == "pick" then
		Line( 0.25, 0.76, 0.7, 0.31 ); Line( 0.33, 0.82, 0.78, 0.37 )
		Rect( 0.18, 0.72, 0.18, 0.14 )
	elseif id == "pan" then
		Line( 0.5, 0.12, 0.5, 0.88 ); Line( 0.12, 0.5, 0.88, 0.5 )
		Line( 0.5, 0.12, 0.4, 0.25 ); Line( 0.5, 0.12, 0.6, 0.25 )
		Line( 0.88, 0.5, 0.75, 0.4 ); Line( 0.88, 0.5, 0.75, 0.6 )
		Line( 0.5, 0.88, 0.4, 0.75 ); Line( 0.5, 0.88, 0.6, 0.75 )
		Line( 0.12, 0.5, 0.25, 0.4 ); Line( 0.12, 0.5, 0.25, 0.6 )
	elseif id == "layer" then
		Rect( 0.2, 0.2, 0.6, 0.6 )
		for _, p in ipairs( { { 0.16, 0.16 }, { 0.72, 0.16 }, { 0.16, 0.72 }, { 0.72, 0.72 } } ) do
			surface.DrawRect( x + p[ 1 ] * size, y + p[ 2 ] * size, size * 0.12, size * 0.12 )
		end
	elseif id == "island" then
		Line( 0.2, 0.72, 0.48, 0.18 ); Line( 0.48, 0.18, 0.82, 0.68 )
		Line( 0.82, 0.68, 0.2, 0.72 ); Line( 0.48, 0.18, 0.47, 0.7 )
	else
		draw.SimpleText( "?", "AdvMatBold", x + size * 0.5, y + size * 0.5,
			col, TEXT_ALIGN_CENTER, TEXT_ALIGN_CENTER )
	end
end

-- Colours are named rather than shown as hex, because "Painted dark red on the
-- part you picked" is a step list you can navigate a week later and
-- "Painted #8B1A1A" is not.
local NAMED = {
	{ "black",      0,   0,   0 }, { "white",      255, 255, 255 },
	{ "grey",       128, 128, 128 }, { "light grey", 190, 190, 190 },
	{ "dark grey",  64,  64,  64 },
	{ "red",        220, 40,  40 }, { "dark red",   130, 25,  25 },
	{ "orange",     240, 140, 40 }, { "gold",       220, 180, 60 },
	{ "yellow",     240, 230, 70 }, { "olive",      130, 130, 50 },
	{ "green",      70,  190, 70 }, { "dark green", 35,  100, 35 },
	{ "teal",       50,  160, 150 }, { "cyan",      80,  220, 230 },
	{ "sky blue",   110, 180, 240 }, { "blue",      60,  90,  220 },
	{ "navy",       30,  40,  110 }, { "purple",    130, 70,  190 },
	{ "magenta",    220, 70,  200 }, { "pink",      240, 150, 180 },
	{ "brown",      120, 80,  50 }, { "tan",        200, 165, 120 },
	{ "cream",      245, 235, 210 },
}

local function ColourName( c )
	local best, bestD = "colour", math.huge

	for _, entry in ipairs( NAMED ) do
		local dr, dg, db = c.r - entry[ 2 ], c.g - entry[ 3 ], c.b - entry[ 4 ]
		local d = dr * dr + dg * dg + db * db

		if d < bestD then best, bestD = entry[ 1 ], d end
	end

	return AdvMat.LText( best )
end

---------------------------------------------------------------------------
-- Saved areas
---------------------------------------------------------------------------
-- A selection is worth keeping: the same "just the jacket" region is wanted
-- again for the normal map, again for the exponent map, and again next session.
-- These live in the user's own data folder rather than in the rule, because
-- they are a personal library and not part of what any other player has to be
-- told about. What travels is always the selection copied into the recipe.

local AREA_DIR = "advmat/areas"

local function AreaFile( name )
	return AREA_DIR .. "/" .. string.gsub( string.lower( name ), "[^%w_%-]", "_" ) .. ".json"
end

function AdvMat.SaveArea( name, sel )
	if not sel then return false end

	file.CreateDir( "advmat" )
	file.CreateDir( AREA_DIR )
	file.Write( AreaFile( name ), util.TableToJSON( sel, true ) )

	return file.Exists( AreaFile( name ), "DATA" )
end

function AdvMat.ListAreas()
	local found = file.Find( AREA_DIR .. "/*.json", "DATA" ) or {}
	local out   = {}

	for _, fname in ipairs( found ) do
		out[ #out + 1 ] = string.StripExtension( fname )
	end

	return out
end

function AdvMat.LoadArea( name )
	local raw = file.Read( AreaFile( name ), "DATA" )
	if not raw then return nil end

	return AdvMat.Sel.Sanitize( util.JSONToTable( raw ) or {} )
end

function AdvMat.DeleteArea( name )
	file.Delete( AreaFile( name ) )
end

---------------------------------------------------------------------------
-- Recipe helpers
---------------------------------------------------------------------------
function PANEL:Snapshot()
	return util.TableToJSON( self.Recipe )
end

function PANEL:PushUndo( label )
	self.UndoStack = self.UndoStack or {}
	self.UndoNames = self.UndoNames or {}
	self.RedoStack = {}
	self.RedoNames = {}

	self.UndoStack[ #self.UndoStack + 1 ] = self:Snapshot()
	self.UndoNames[ #self.UndoNames + 1 ] = self.HistoryCurrentName or "Opened texture"
	self.HistoryCurrentName = label or "Edit"

	-- Snapshots are recipes, not pixels, so sixty-four of them cost less than
	-- one undo step would in a normal image editor.
	while #self.UndoStack > 64 do
		table.remove( self.UndoStack, 1 )
		table.remove( self.UndoNames, 1 )
	end

	self:RefreshUndoButtons()
	self:RefreshHistory()
end

function PANEL:Restore( json )
	local tbl = util.JSONToTable( json or "" )
	if not istable( tbl ) then return end

	-- Undo/redo ends the coalesced slider transaction. Otherwise a quick edit
	-- after Restore can reuse the old transaction, skip its undo snapshot and
	-- leave a redo branch that no longer describes the current recipe.
	self.LayerControlOpen = nil
	timer.Remove( "AdvMat.LayerControl." .. tostring( self ) )

	self.Recipe = tbl
	self.Recipe.ops = self.Recipe.ops or {}
	self.EditingStep = nil

	-- A different recipe has a different size; the running figure for the old
	-- one would let the next step past the save limit unmeasured.
	self.WireBytes, self.WireMeasured = nil, nil

	-- The source and the size are both part of a snapshot, so the working
	-- buffer and the controls that describe it have to come back with them.
	-- Without this an undo past a change of starting image leaves the buffer
	-- the size and the SHAPE that the other texture was, and every step after
	-- it is composed against the wrong grid.
	self.NativeW, self.NativeH =
		AdvMat.Gen.SourceSize( self.Recipe.src, self.NativeW, self.NativeH )

	local rw, rh = AdvMat.Gen.Dims( self.Recipe )
	self.WorkW, self.WorkH = WorkDims( rw, rh )

	self:RefreshSizeBox()
	self:RefreshStartLabel()

	self:Recompose()
	self:RefreshSteps()
	if self.ActiveLayer and not ( self.Recipe.layers and self.Recipe.layers[ self.ActiveLayer ] ) then
		self.ActiveLayer = nil
	end
	if IsValid( self.Canvas ) then
		self.Canvas:SetLayerTransform(
			self.ActiveLayer and self.Recipe.layers and self.Recipe.layers[ self.ActiveLayer ] or nil,
			self.LayerKeepAspect )
	end
	self:RefreshLayers()
	-- Undo/redo replaces the layer table and can also swap a source texture for
	-- a blank one. Rebuild every active tool: layer transforms need the restored
	-- values, while Paint/Fill must update whether Keep shading owns the blend.
	if IsValid( self.Opts ) then self:BuildOptions() end
end

function PANEL:Undo()
	if not self.UndoStack or #self.UndoStack == 0 then return end

	self.RedoStack = self.RedoStack or {}
	self.RedoNames = self.RedoNames or {}
	self.RedoStack[ #self.RedoStack + 1 ] = self:Snapshot()
	self.RedoNames[ #self.RedoNames + 1 ] = self.HistoryCurrentName or "Edit"

	local name = table.remove( self.UndoNames or {} ) or "Earlier state"
	self:Restore( table.remove( self.UndoStack ) )
	self.HistoryCurrentName = name
	self:RefreshUndoButtons()
	self:RefreshHistory()
end

function PANEL:Redo()
	if not self.RedoStack or #self.RedoStack == 0 then return end

	self.UndoStack = self.UndoStack or {}
	self.UndoNames = self.UndoNames or {}
	self.UndoStack[ #self.UndoStack + 1 ] = self:Snapshot()
	self.UndoNames[ #self.UndoNames + 1 ] = self.HistoryCurrentName or "Earlier state"

	local name = table.remove( self.RedoNames or {} ) or "Edit"
	self:Restore( table.remove( self.RedoStack ) )
	self.HistoryCurrentName = name
	self:RefreshUndoButtons()
	self:RefreshHistory()
end

function PANEL:RefreshUndoButtons()
	local canUndo = ( self.UndoStack and #self.UndoStack or 0 ) > 0
	local canRedo = ( self.RedoStack and #self.RedoStack or 0 ) > 0
	for _, button in ipairs( { self.UndoBtn, self.HistoryUndoBtn } ) do
		if IsValid( button ) then button:SetEnabled( canUndo ) end
	end
	for _, button in ipairs( { self.RedoBtn, self.HistoryRedoBtn } ) do
		if IsValid( button ) then button:SetEnabled( canRedo ) end
	end
end

--- Jump to one point in the session history. Position zero is the texture as
--- it was opened; the current point is #UndoStack. Move the snapshots between
--- stacks in memory, then restore only the destination. Replaying up to sixty-
--- four full pixel compositions made clicking an old history row look frozen.
function PANEL:JumpHistory( position )
	self.UndoStack = self.UndoStack or {}
	self.RedoStack = self.RedoStack or {}
	self.UndoNames = self.UndoNames or {}
	self.RedoNames = self.RedoNames or {}

	local total = #self.UndoStack + #self.RedoStack
	position = math.Clamp( math.floor( tonumber( position ) or 0 ), 0, total )
	if position == #self.UndoStack then return end

	local snapshot = self:Snapshot()
	local name = self.HistoryCurrentName or "Current state"
	while #self.UndoStack > position do
		self.RedoStack[ #self.RedoStack + 1 ] = snapshot
		self.RedoNames[ #self.RedoNames + 1 ] = name
		snapshot = table.remove( self.UndoStack )
		name = table.remove( self.UndoNames ) or "Earlier state"
	end
	while #self.UndoStack < position and #self.RedoStack > 0 do
		self.UndoStack[ #self.UndoStack + 1 ] = snapshot
		self.UndoNames[ #self.UndoNames + 1 ] = name
		snapshot = table.remove( self.RedoStack )
		name = table.remove( self.RedoNames ) or "Later state"
	end

	self:Restore( snapshot )
	self.HistoryCurrentName = name
	self:RefreshUndoButtons()
	self:RefreshHistory()
end

function PANEL:RefreshHistory()
	if not IsValid( self.HistoryList ) then return end
	self.HistoryList:Clear()

	local undo = self.UndoStack or {}
	local redo = self.RedoStack or {}
	local undoNames = self.UndoNames or {}
	local redoNames = self.RedoNames or {}
	local rowH = AdvMat.RowHeight() + 4
	local current = #undo

	local entries = {}
	for i = 1, #undo do
		entries[ #entries + 1 ] = { pos = i - 1, name = undoNames[ i ] or "Earlier state" }
	end
	entries[ #entries + 1 ] = {
		pos = current,
		name = self.HistoryCurrentName or "Current state",
		current = true,
	}
	-- Redo is a stack whose last element is the next state. Present it in the
	-- chronological order the user reaches by moving forward.
	for i = #redo, 1, -1 do
		entries[ #entries + 1 ] = {
			pos = current + ( #redo - i + 1 ),
			name = redoNames[ i ] or "Later state",
			future = true,
		}
	end

	for n, entry in ipairs( entries ) do
		local b = self.HistoryList:Add( "DButton" )
		b:Dock( TOP )
		b:SetTall( rowH )
		b:DockMargin( 0, 0, 3, 1 )
		b:SetContentAlignment( 4 )
		b:SetText( ( entry.current and "  >  " or "     " ) .. n .. ". " ..
			AdvMat.LText( entry.name ) )
		b:SetTextColor( entry.future and T.TextFaint or T.Text )
		b.Paint = function( pnl, w, h )
			local col = entry.current and T.Selected
				or ( pnl:IsHovered() and T.RowHover ) or T.Row
			surface.SetDrawColor( col.r, col.g, col.b, 255 )
			surface.DrawRect( 0, 0, w, h )
		end
		b.DoClick = function() self:JumpHistory( entry.pos ) end
	end
end

---------------------------------------------------------------------------
-- Composing
---------------------------------------------------------------------------

--- Change what the steps are applied on top of: either a texture, or a flat
--- colour for a decal or a mask built from nothing.
---
--- The steps are kept. They are described in fractions of the image rather than
--- in pixels of one particular texture, so they mean the same thing over a
--- blank canvas as they did over the original.
function PANEL:SetStart( src, fill )
	if self.RegionMode then return end
	self:PushUndo( "Change starting image" )

	self.Recipe.src  = ( src and src ~= "" ) and src or nil
	self.Recipe.fill = ( not self.Recipe.src ) and ( fill or { 255, 255, 255, 255 } ) or nil

	-- A different starting image can have a different resolution AND a
	-- different shape, and both the finished size and the working buffer
	-- follow it.
	self.NativeW, self.NativeH =
		AdvMat.Gen.SourceSize( self.Recipe.src, self.NativeW, self.NativeH )

	self:SetOutputSize( self.NativeW, self.NativeH, true )
	self:RefreshSizeBox()

	self:Recompose()
	self:RefreshStartLabel()
	self:RefreshLayers()
	self:BuildOptions()
end

function PANEL:RefreshStartLabel()
	if not IsValid( self.StartBtn ) then return end

	self.StartBtn:SetText( self.Recipe.src and "Start: the texture" or "Start: blank" )
end

---------------------------------------------------------------------------
-- The size the finished image is written at
---------------------------------------------------------------------------

--- Rebuild the size list and show the size that is actually set.
function PANEL:RefreshSizeBox()
	if not IsValid( self.SizeBox ) then return end

	local GEN    = AdvMat.Gen
	local rw, rh = GEN.Dims( self.Recipe )

	self.SizeBox:Clear()

	for _, entry in ipairs( GEN.SizeMenu( self.Recipe.src, rw, rh ) ) do
		self.SizeBox:AddChoice( entry.name, entry.id )
	end

	self.SizeBox:SetValue( GEN.DimText( rw, rh ) )
end

--- Adopt `w` x `h` as the size the finished image is written at.
---
--- The working copy follows the OUTPUT rather than the source: what is being
--- edited is the finished image, and painting at a resolution that is thrown
--- away on the way out is work nobody asked for.
---
--- `defer` is for the one caller that is about to rebuild anyway - changing
--- the source changes the size and the pixels together, and composing twice
--- for one action is a visible stall on a large sheet.
function PANEL:SetOutputSize( w, h, defer )
	self.Recipe.size   = w
	self.Recipe.height = ( h ~= w ) and h or nil

	local ww, wh = WorkDims( w, h )
	if ww == self.WorkW and wh == self.WorkH then return end

	self.WorkW, self.WorkH = ww, wh
	if not defer then self:Recompose() end
end

--- Rebuild the working image from scratch. Called after anything other than
--- appending a step, which is the one case that can be done incrementally.
---
--- The source pixels have to be in hand first. Reading them only works inside a
--- render hook - outside one the engine hands back a solid black image and says
--- nothing - and this runs from mouse clicks and menu items, so the read is
--- asked for and the compose happens when it lands. After the first one it is
--- cached and this is immediate.
function PANEL:Recompose()
	if not self.Recipe.src then
		self:ComposeNow()
		return
	end

	local preserveMask = PreservesSourceMask( self.Recipe )
	AdvMat.Gen.PrimeSource( self.Recipe.src, self.WorkW, self.WorkH,
		not self.Recipe.opaque or preserveMask, preserveMask, function( src )
		if not IsValid( self ) then return end

		if not src then
			self:Status( "Could not read " .. tostring( self.Recipe.src ) ..
				" - it may not exist, or this build cannot copy pixels out of a " ..
				"render target.", true )
			return
		end

		self:ComposeNow()
	end )
end

function PANEL:ComposeNow()
	-- A stroke being drawn belongs to the image this replaces. Its saved
	-- pixels mean nothing to the new one, so it is dropped rather than put
	-- back; the stroke itself is still added when the button is let go.
	self:CancelLiveStroke( true )

	local upto = self.ViewStep or #self.Recipe.ops

	local buf, src = OPS.Compose( self.Recipe, self.WorkW, self.WorkH, upto )

	if not buf then
		self:Status( "Could not read " .. tostring( self.Recipe.src ), true )
		return
	end

	self.Buf = buf

	-- The source as it was read for this image. Steps added one at a time
	-- need it for the same reason the composition did: "Back to original"
	-- restores to it.
	self.Src = src

	if AdvMat.DebugTraceActive and AdvMat.DebugTraceEvent then
		AdvMat.DebugTraceEvent( "texture.compose", {
			path = self.Recipe.src,
			recipe_opaque = self.Recipe.opaque or false,
			preserves_source_mask = PreservesSourceMask( self.Recipe ),
			source = AdvMat.DebugBufferStats and AdvMat.DebugBufferStats( src ) or nil,
			buffer = AdvMat.DebugBufferStats and AdvMat.DebugBufferStats( buf ) or nil,
		} )
	end

	-- Shown at the recipe's own resolution (the user's ceiling and a floor of
	-- 1024 permitting), not the working buffer's: the display is a render
	-- target, so the parts of the sheet nobody has touched cost nothing to
	-- show sharp. Only the edits are composed at the buffer's size.
	local rw, rh = AdvMat.Gen.Dims( self.Recipe )
	local dw, dh = AdvMat.Gen.FitWithin( rw, rh,
		math.max( 1024, AdvMat.Gen.MaxSize() ) )

	self.Canvas:SetImage( buf, src, self.Recipe.src, dw, dh,
		self.Recipe.layers, PreservesSourceMask( self.Recipe ) )
	self.Canvas:SetLayerTransform( self.ActiveLayer and self.Recipe.layers
		and self.Recipe.layers[ self.ActiveLayer ] or nil, self.LayerKeepAspect )
	self:PushToModel()

	-- The selection was rasterised against the previous buffer, and the wand in
	-- particular reads its pixels.
	if self.Sel then self:RebuildMask() end
end

--- The context a step runs in on the editor's own image: the recipe's, with
--- the source as it was read for that image, which "Back to original" restores
--- to.
function PANEL:StepContext()
	return OPS.Context( self.Recipe, self.Src )
end

--- Say which limit a step ran into - "steps", "effects", "strokes" or
--- "size" - and what to do about it.
function PANEL:LimitStatus( limit )
	if limit == "effects" then
		self:Status( "That is as many fills, adjustments and filters as one texture " ..
			"can hold. Delete some in the Effects list - brush strokes do not " ..
			"count towards this.", true )
	elseif limit == "strokes" then
		self:Status( "That is as much brushwork as one texture can hold. Delete " ..
			"some strokes in the Effects list to keep painting.", true )
	elseif limit == "size" then
		self:Status( "This edit is now as large as one save can send to the " ..
			"server. Delete steps you no longer need in the Effects list to " ..
			"keep editing.", true )
	else
		self:Status( "That is as many steps as one texture can hold.", true )
	end
end

--- Whether `clean` fits, by the recipe's own limits and by what one save can
--- send. Says why when it does not.
function PANEL:CanAddStep( clean )
	local fits, limit = OPS.CanAppend( self.Recipe, clean )
	if not fits then
		self:LimitStatus( limit )
		return false
	end

	if not self:WireRoomFor( clean ) then
		self:LimitStatus( "size" )
		return false
	end

	return true
end

--- Append a step and run just that one over the current image, which is what
--- keeps painting responsive on a large texture.
---
--- `shown` is a rectangle a live preview of this step drew and has just put
--- back, which has to be uploaded again along with the step itself.
function PANEL:AddStep( op, shown )
	local clean = OPS.Sanitize( op )
	if not clean then return false end
	if not self:CanAddStep( clean ) then return false end

	-- Store the stable English catalogue source, not whatever language happens
	-- to be selected now; History localises it whenever its rows are rebuilt.
	self:PushUndo( OPS.OpSourceName( clean.op ) )

	local preservedSourceMask = PreservesSourceMask( self.Recipe )
	self.Recipe.ops[ #self.Recipe.ops + 1 ] = clean

	-- The recipe now needs the model reference if this step's region came from
	-- one, otherwise the mesh lookup has nothing to resolve against.
	if SEL.NeedsMesh( clean.sel ) then
		self.Recipe.model   = self.Ctx.model
		self.Recipe.slot    = self.Ctx.slot
		self.Recipe.matpath = self.Ctx.matpath

		-- The parts that were on screen when the piece was clicked, which is
		-- the geometry the click was resolved against and therefore the only
		-- geometry it means anything against later.
		self.Recipe.mask = self.BodyMask
	end

	-- The first explicit alpha operation changes what the source channel means:
	-- a shader mask must be flattened to solid before it can become visual
	-- transparency. Recompose from the source at that semantic boundary instead
	-- of applying the step incrementally to mask bytes.
	local sourceMaskChanged = preservedSourceMask
		~= PreservesSourceMask( self.Recipe )
	if self.Buf and not self.ViewStep and not sourceMaskChanged then
		local x0, y0, x1, y1 = OPS.Execute( self.Buf, clean, self:StepContext() )

		if x0 == nil then
			self.Canvas:Invalidate()
		else
			-- A brush stroke reports the rectangle it can have changed, and only
			-- that is uploaded again - together with whatever a live preview of
			-- it drew there and has just put back.
			if x0 then self.Canvas:PatchRegion( x0, y0, x1, y1 ) end
			if shown and shown[ 1 ] then
				self.Canvas:PatchRegion( shown[ 1 ], shown[ 2 ], shown[ 3 ], shown[ 4 ] )
			end
		end

		self:PushToModel()
	else
		self:Recompose()
	end

	self:NoteStepBytes( clean )
	self:RefreshSteps( true )
	self:AnnounceTransparency( clean )
	return true
end

---------------------------------------------------------------------------
-- Transient step preview
---------------------------------------------------------------------------
-- The editor's self.Buf is the committed, incremental image that AddStep and
-- Undo rely on.  Live controls must never write into it: otherwise every
-- slider tick compounds the previous tick and accepting the dialog applies
-- the same adjustment a second time.  One scratch buffer is reset from the
-- committed image for each displayed revision and is bound only to the canvas.
local function CopyBufferInto( dst, src )
	if not src then return nil end
	if not dst or dst.w ~= src.w or dst.h ~= src.h then
		return AdvMat.Buf.Copy( src )
	end

	local n = src.w * src.h
	local sr, sg, sb, sa = src.r, src.g, src.b, src.a
	local dr, dg, db, da = dst.r, dst.g, dst.b, dst.a
	for i = 1, n do
		dr[ i ], dg[ i ], db[ i ], da[ i ] = sr[ i ], sg[ i ], sb[ i ], sa[ i ]
	end

	return dst
end

function PANEL:StepPreviewContext( op )
	local ctx = OPS.Context( self.Recipe, self.Src )
	if not ( op and SEL.NeedsMesh( op.sel ) ) then return ctx end

	-- AddStep normally records these fields on the recipe.  A preview happens
	-- before that commit, so the first UV/model-selected adjustment has to use
	-- the editor's live target explicitly.
	local target = self.Ctx or {}
	ctx.model   = target.model   or ctx.model
	ctx.slot    = target.slot    ~= nil and target.slot or ctx.slot
	ctx.matpath = target.matpath or ctx.matpath
	ctx.mask    = self.BodyMask  ~= nil and self.BodyMask or ctx.mask
	return ctx
end

function PANEL:StepPreviewCanvasReady()
	local canvas = self.Canvas
	return self.Buf ~= nil and IsValid( canvas )
		and not canvas.Dirty and not canvas.Pending
		and not canvas.Patch and not canvas.CompositeDirty
end

function PANEL:BeginStepPreview( owner )
	-- Re-entry is treated as replacement even when a caller reuses its owner
	-- token. Otherwise a shown scratch image could be forgotten without first
	-- rebinding the committed buffer.
	if self.StepPreviewOwner then
		self:EndStepPreview( self.StepPreviewOwner, false )
	end

	self.StepPreviewOwner = owner
	self.StepPreviewOp = nil
	self.StepPreviewDirty = false
	self.StepPreviewShown = false
	self.StepPreviewBuffer = nil
	self.StepPreviewTimerPending = false
	self.StepPreviewTimer = "AdvMat.StepPreview." .. tostring( owner or self )
end

function PANEL:ScheduleStepPreview( owner )
	if owner ~= self.StepPreviewOwner or not self.StepPreviewDirty
		or self.StepPreviewTimerPending then return false end

	self.StepPreviewTimerPending = true
	local timerName = self.StepPreviewTimer
	timer.Create( timerName, ADJUST_PREVIEW_INTERVAL, 1, function()
		if not IsValid( self ) then return end
		if owner ~= self.StepPreviewOwner then return end
		self.StepPreviewTimerPending = false
		if not self.StepPreviewDirty then return end

		-- Finishing the previous run upload is backpressure, not a lost update:
		-- StepPreviewOp always contains the newest slider/check-box state.
		if not self:StepPreviewCanvasReady() then
			self:ScheduleStepPreview( owner )
			return
		end

		self:ApplyStepPreview( owner )
	end )
	return true
end

function PANEL:QueueStepPreview( owner, op )
	if owner ~= self.StepPreviewOwner then return false end
	local clean = OPS.Sanitize( op )
	if not clean then return false end

	self.StepPreviewOp = clean
	self.StepPreviewDirty = true
	self:ScheduleStepPreview( owner )
	return true
end

function PANEL:ApplyStepPreview( owner )
	if owner ~= self.StepPreviewOwner or not self.StepPreviewDirty
		or not self.Buf or not IsValid( self.Canvas ) then return false end

	if not self:StepPreviewCanvasReady() then
		self:ScheduleStepPreview( owner )
		return false
	end

	local clean = self.StepPreviewOp
	if not clean then return false end

	local preview = CopyBufferInto( self.StepPreviewBuffer, self.Buf )
	OPS.Execute( preview, clean, self:StepPreviewContext( clean ) )

	self.StepPreviewBuffer = preview
	self.StepPreviewDirty = false
	self.StepPreviewShown = true
	self.Canvas.Buf = preview
	self.Canvas:Invalidate()
	self:PushToModel()
	return true
end

--- End a live transaction.  `commit` adds exactly one normal recipe step;
--- cancellation simply returns the canvas/model to the committed buffer.
function PANEL:EndStepPreview( owner, commit, op, dying )
	if owner ~= nil and owner ~= self.StepPreviewOwner then return false end
	if not self.StepPreviewOwner then return false end

	local timerName = self.StepPreviewTimer
	if timerName then timer.Remove( timerName ) end

	local hadPreview = self.StepPreviewShown
	self.StepPreviewOwner = nil
	self.StepPreviewOp = nil
	self.StepPreviewDirty = false
	self.StepPreviewShown = false
	self.StepPreviewBuffer = nil
	self.StepPreviewTimerPending = false
	self.StepPreviewTimer = nil

	if dying then return true end

	-- AddStep mutates self.Buf in place. Point the canvas back at that exact
	-- object first so the commit is both authoritative and applied only once.
	if IsValid( self.Canvas ) and self.Buf then
		self.Canvas.Buf = self.Buf
		if hadPreview then self.Canvas:Invalidate() end
	end

	if commit then
		return self:AddStep( op )
	end

	if hadPreview then self:PushToModel() end
	return true
end

--- Erasing does nothing visible unless the material is allowed to be
--- see-through, and a tool that silently does nothing is worse than one that
--- refuses. The material editor is told, and it says so.
function PANEL:AnnounceTransparency( op )
	if self.SaidTranslucent then return end
	if op.op ~= "erase" and op.op ~= "alphafrom" then return end

	self.SaidTranslucent = true
	self.WantsTranslucent = true

	self:Status( "Holes only show up if the material is allowed to be see-through. " ..
		"$translucent will be switched on for you when you press Use this texture." )
end

---------------------------------------------------------------------------
-- Selection
---------------------------------------------------------------------------
function PANEL:SetSelection( sel )
	self.Sel = sel and SEL.Sanitize( sel ) or nil
	self:RebuildMask()
end

function PANEL:RebuildMask()
	-- Nothing to rasterise against yet. Worth returning rather than carrying
	-- on: without a buffer the wand would fall back to reading the texture
	-- itself, and that read has to happen inside a render hook.
	if not self.Buf then return end

	if not self.Sel then
		self.Mask = nil
		self.Canvas:SetSelection( nil )
		self:RefreshSelectionStatus()
		return
	end

	self.Mask = SEL.Rasterize( self.Sel, self.WorkW, self.WorkH, {
		pixels  = self.Buf,
		src     = self.Recipe.src,
		model   = self.Ctx.model,
		slot    = self.Ctx.slot,
		matpath = self.Ctx.matpath,
		mask    = self.BodyMask,
	} )

	self.Canvas:SetSelection( self.Mask )

	-- "Everything" rasterises to no mask at all, as an optimisation - but no
	-- mask is also what NO selection looks like, and the two must not read the
	-- same: one of them is the direct result of pressing Select all.
	self.Canvas.SelAll = ( self.Mask == nil ) and true or nil

	self:RefreshSelectionStatus()
end

function PANEL:PushShape( shape )
	if not shape then return end

	-- Selection tools carry their own softening and growing, and an island
	-- wants the opposite defaults to a box: growing a few pixels covers the
	-- hairline of old colour left along a UV seam, while softening one bleeds
	-- across the seam onto a neighbouring piece and shows as dirt.
	local sel = SEL.Push( self.Sel, shape )

	if sel then
		local px = self:PixelFraction()

		if shape.t == "uvisland" or shape.t == "uvtri" then
			sel.grow    = ( self.IslandGrow or 2 ) * px
			sel.feather = nil
		else
			sel.feather = ( self.Feather or 0 ) * px
			sel.grow    = ( self.Grow or 0 ) * px
		end

		sel = SEL.Sanitize( sel )
	end

	self.Sel = sel
	self:RebuildMask()
end

--- One working pixel as a fraction of the image.
---
--- The rasteriser measures grow and feather against the mean of the two axes,
--- so a fraction meant to be N pixels has to be built the same way or a soft
--- edge comes out twice as wide down one side of an oblong sheet.
function PANEL:PixelFraction()
	return 2 / ( ( self.WorkW or 512 ) + ( self.WorkH or 512 ) )
end

function PANEL:RefreshSelectionStatus()
	if not IsValid( self.SelStatus ) then return end

	if not self.Mask then
		-- A selection with no mask is "Select all": everything is covered, so
		-- there was nothing to rasterise. Saying "nothing selected" here is
		-- how pressing Select all came to read as selecting nothing.
		self.SelStatus:SetText( self.Sel
			and "The whole picture is selected."
			or  "Nothing selected - changes affect the whole picture." )
		return
	end

	local total = 0
	local n = self.WorkW * self.WorkH
	for i = 1, n do total = total + self.Mask[ i ] end

	local pct = total / ( n * 255 ) * 100

	if pct < 0.05 then
		self.SelStatus:SetText( "Your selection is empty - nothing will change." )
	else
		self.SelStatus:SetText( string.format(
			"You have %.1f%% of the picture selected.", pct ) )
	end
end

--- The selection a new step should carry: nil when everything is selected, so
--- the recipe does not store a region that means "no region".
function PANEL:StepSelection()
	if not self.Sel then return nil end
	return table.Copy( self.Sel )
end

---------------------------------------------------------------------------
-- Pushing the result at the model
---------------------------------------------------------------------------
local function PreviewTime()
	return RealTime and RealTime() or 0
end

-- `rtx` describes an RTX replacement recipe. `rtxrender` is narrower: it
-- requests the same disk-backed preview path for a normal Source/VMT recipe
-- opened inside the Remix client. Keeping the two flags separate prevents a
-- Source-tab edit from being persisted as an RTX source-copy descriptor.
local function RTXRenderContext( ctx )
	return ctx and ( ctx.rtx == true or ctx.rtxrender == true )
end

local function SafeDeletePreview( path )
	if path and path ~= "" and file and file.Delete then file.Delete( path ) end
end

--- Mark the latest completed canvas for conversion to an ordinary PNG-backed
--- texture.  This never changes Remix's ray-tracing state; PostRenderVGUI is
--- used only because render.Capture is valid inside a render hook.
function PANEL:QueueRTXPreviewSnapshot()
	if not RTXRenderContext( self.Ctx ) then return false end

	self.RTXPreviewWanted = ( self.RTXPreviewWanted or 0 ) + 1
	self.RTXPreviewAt = PreviewTime() + RTX_PREVIEW_DELAY
	self.RTXPreviewFailures = 0
	return true
end

function PANEL:RTXPreviewCanvasReady()
	local canvas = self.Canvas
	if not IsValid( canvas ) or not canvas.RT or not canvas.RTMat then return false end
	return not canvas.Dirty and not canvas.Pending and not canvas.Patch
		and not canvas.CompositeDirty
end

--- Capture a small copy of the public canvas target.  The source may be a 4K
--- sheet, but the DModelPanel is only a few hundred pixels wide.  Capping the
--- long side bounds both PNG work and the engine texture cache retained by
--- Material().
function PANEL:CaptureRTXPreviewPNG()
	if not self:RTXPreviewCanvasReady() then return nil, "canvas is still uploading" end
	if not ( render and render.Capture and render.PushRenderTarget
		and render.PopRenderTarget and render.SetMaterial
		and render.DrawScreenQuad and cam and cam.Start2D and cam.End2D ) then
		return nil, "engine PNG capture is unavailable"
	end
	if not ( AdvMat.Gen and AdvMat.Gen.FitWithin ) then
		return nil, "texture size helper is unavailable"
	end

	local w, h = AdvMat.Gen.FitWithin( tonumber( self.WorkW ) or 512,
		tonumber( self.WorkH ) or tonumber( self.WorkW ) or 512,
		RTX_PREVIEW_MAX_SIZE )
	local rt = GetRenderTarget( "advmat_rtx_preview_capture_" .. w .. "x" .. h, w, h )
	if not rt then return nil, "could not allocate the RTX preview target" end

	local png
	render.PushRenderTarget( rt )
	render.OverrideAlphaWriteEnable( true, true )
	cam.Start2D()

	local ok, err = pcall( function()
		render.Clear( 0, 0, 0, 0, true, true )
		render.SetColorModulation( 1, 1, 1 )
		render.SetBlend( 1 )
		render.SetMaterial( self.Canvas.RTMat )
		-- Source replaces destination in colour and alpha.  DrawScreenQuad is
		-- intentional: Remix's DX7 path can sample this RT through the normal
		-- screen primitive, while the raw mesh copy path produces black.
		render.OverrideBlend( true,
			BLEND_ONE, BLEND_ZERO, BLENDFUNC_ADD,
			BLEND_ONE, BLEND_ZERO, BLENDFUNC_ADD )
		render.DrawScreenQuad()
		png = render.Capture( {
			format = "png", x = 0, y = 0, w = w, h = h, alpha = true,
		} )
	end )

	-- Restore every state even when capture failed, otherwise the rest of VGUI
	-- is corrupted silently.
	render.OverrideBlend( false )
	render.SetColorModulation( 1, 1, 1 )
	render.SetBlend( 1 )
	cam.End2D()
	render.OverrideColorWriteEnable( false, true )
	render.OverrideAlphaWriteEnable( false, false )
	render.PopRenderTarget()

	if not ok then return nil, tostring( err ) end
	if not isstring( png ) or #png < 8 then
		return nil, "engine PNG capture returned no image"
	end
	return png, w, h
end

function PANEL:InstallRTXPreviewPNG( png )
	if not isstring( png ) or #png < 8 then return false, "invalid preview image" end
	if not self.RTXPreviewID then
		AdvMat.RTXPreviewSessionSerial = ( AdvMat.RTXPreviewSessionSerial or 0 ) + 1
		self.RTXPreviewID = tostring( AdvMat.RTXPreviewSessionSerial )
	end

	file.CreateDir( "advmat" )
	file.CreateDir( RTX_PREVIEW_DIR )

	-- Keep one cache entry per editor.  ITexture:Download reloads a file-backed
	-- texture after this verified overwrite, avoiding both stale Material()
	-- results and an ever-growing set of unique paths.
	local target = string.format( "%s/session_%s.png", RTX_PREVIEW_DIR,
		self.RTXPreviewID )
	local wrote, writeErr = pcall( file.Write, target, png )
	if not wrote then return false, tostring( writeErr ) end
	if file.Read( target, "DATA" ) ~= png then
		SafeDeletePreview( target )
		return false, "could not verify the RTX preview image"
	end

	local image, texture = self.RTXPreviewImage, self.RTXPreviewTexture
	if texture then
		if not texture.Download then
			return false, "file-backed texture reload is unavailable", true
		end
		local reloaded, reloadErr = pcall( texture.Download, texture )
		if not reloaded then return false, tostring( reloadErr ) end
	else
		image = Material( "data/" .. target, "noclamp smooth" )
		if not image or ( image.IsError and image:IsError() ) then
			SafeDeletePreview( target )
			return false, "could not load the RTX preview image"
		end

		local ok
		ok, texture = pcall( image.GetTexture, image, "$basetexture" )
		if not ok or not texture then
			SafeDeletePreview( target )
			return false, "the RTX preview image has no texture"
		end
	end

	local recipe = self.Recipe
	local showAlpha = recipe ~= nil
		and ( not recipe.opaque or self:PreviewShowsHoles() ) or false
	if self.PreviewMat and self.RTXPreviewShowsAlpha ~= showAlpha then
		self.PreviewMat = nil
	end

	if not self.PreviewMat then
		local materialKV = {
			[ "$basetexture" ] = texture.GetName and texture:GetName() or "color/white",
			[ "$model" ]       = "1",
			[ "$nocull" ]      = "1",
			[ "$nolod" ]       = "1",
		}
		if showAlpha then materialKV[ "$translucent" ] = "1" end

		self.PreviewMat = CreateMaterial(
			"advmat_rtx_texedit_" .. self.RTXPreviewID
				.. ( showAlpha and "_alpha" or "_opaque" ),
			"UnlitGeneric", materialKV )
		self.RTXPreviewShowsAlpha = showAlpha
	end
	if not self.PreviewMat then
		SafeDeletePreview( target )
		return false, "could not create the RTX model preview material"
	end

	self.PreviewMat:SetTexture( "$basetexture", texture )
	if self.PreviewMat.Recompute then self.PreviewMat:Recompute() end

	self.RTXPreviewFile = target
	self.RTXPreviewImage = image -- retain the disk-backed material explicitly
	self.RTXPreviewTexture = texture

	AdvMat.ModelView.ApplyMaterials( self )
	return true
end

--- Called from the shared PostRenderVGUI hook below.  A newer edit simply
--- moves the deadline; a canvas that is still uploading is left alone until a
--- later frame, so no partial brush stroke is ever snapshotted.
function PANEL:PumpRTXPreviewSnapshot()
	if not self.RTXPreviewWanted then return false end
	if PreviewTime() < ( self.RTXPreviewAt or 0 ) then return false end
	if not self:RTXPreviewCanvasReady() then return false end

	local request = self.RTXPreviewWanted
	local png, err = self:CaptureRTXPreviewPNG()
	local installed, installErr, permanent = false
	if png then installed, installErr, permanent = self:InstallRTXPreviewPNG( png ) end

	if installed then
		if self.RTXPreviewWanted == request then self.RTXPreviewWanted = nil end
		self.RTXPreviewFailures = 0
		return true
	end

	self.RTXPreviewFailures = ( self.RTXPreviewFailures or 0 ) + 1
	if not permanent and self.RTXPreviewFailures < RTX_PREVIEW_TRIES then
		self.RTXPreviewAt = PreviewTime() + RTX_PREVIEW_RETRY
	else
		self.RTXPreviewWanted = nil
		AdvMat.Log( "RTX model preview snapshot failed: %s",
			tostring( installErr or err or "unknown error" ) )
	end
	return false
end

--- Whether the model preview has to show transparency: the recipe makes some,
--- or a stroke cutting a hole is being drawn right now and its step does not
--- exist yet.
function PANEL:PreviewShowsHoles()
	if OPS.MakesTransparency( self.Recipe ) then return true end

	local stroke = self.LiveStroke
	return stroke ~= nil and stroke.op ~= nil and stroke.op.op == "erase"
end

function PANEL:PushToModel()
	local mp = self.ModelPanel
	if not IsValid( mp ) or not IsValid( mp.Entity ) then return end

	-- Remix samples the canvas render target as black on captured geometry.  It
	-- receives a coalesced disk-backed copy instead; while that first copy is
	-- pending, ApplyMaterials displays the original mounted texture through the
	-- RTX mirrors in cl_73_modelview.lua.
	if RTXRenderContext( self.Ctx ) then
		self:QueueRTXPreviewSnapshot()
		AdvMat.ModelView.ApplyMaterials( self )
		return
	end

	local tex = self.Canvas:GetPreviewTexture()
	if not tex then return end

	local makesTransparency = self:PreviewShowsHoles()
	if self.PreviewMat and self.PreviewMakesTransparency ~= makesTransparency then
		-- Material flags are creation-time state in Source. A texture that gains
		-- or loses a hole therefore needs the matching cached material variant.
		self.PreviewMat = nil
	end

	if not self.PreviewMat then
		local base   = self.Ctx.basekv or {}
		local shader = self.Ctx.shader or "VertexLitGeneric"

		local kv = {}
		for k, v in pairs( base ) do kv[ k ] = v end

		kv[ "$model" ] = "1"

		-- Keep an opaque source opaque so its alpha can remain a shader mask
		-- ($basealphaenvmapmask, phong, self-illumination, ...). Only an edit
		-- which really creates a hole is allowed to repurpose it as transparency.
		if makesTransparency then kv[ "$translucent" ] = "1" end

		-- The Lua material constructor does not reliably coerce Valve's
		-- unquoted/scalar colour shorthand.  Use the same typed boundary as the
		-- main material builder so a base `$envmaptint .7 .7 .7` cannot turn the
		-- texture-editor preview into a malformed, brightly tinted material.
		if AdvMat.Apply and AdvMat.Apply.CreationKV then
			kv = AdvMat.Apply.CreationKV( shader, kv )
		end

		self.PreviewMat = CreateMaterial(
			"advmat_texedit_v3_" .. util.CRC( ( self.Ctx.matpath or "" ) .. self.Param )
				.. ( makesTransparency and "_holes" or "_source" ),
			shader, kv )
		self.PreviewMakesTransparency = makesTransparency
	end

	if self.PreviewMat then
		self.PreviewMat:SetTexture( self.Param, tex )
		self.PreviewMat:Recompute()

		if AdvMat.DebugTraceActive and AdvMat.DebugTraceEvent then
			AdvMat.DebugTraceEvent( "texture.preview_material", {
				path = self.Recipe.src,
				parameter = self.Param,
				texture = tex.GetName and tex:GetName() or tostring( tex ),
				material = AdvMat.DebugMaterialState
					and AdvMat.DebugMaterialState( self.PreviewMat, self.Ctx.shader ) or nil,
			} )
		end

		-- Not written straight onto the slot: hiding writes to these same
		-- slots, and one pass that knows about both is the only way neither
		-- can undo the other.
		AdvMat.ModelView.ApplyMaterials( self )
	end
end

---------------------------------------------------------------------------
-- Construction
---------------------------------------------------------------------------
-- The tool settings that survive the editor being closed: what they are named
-- in the cookie store, and what they are when nothing is stored yet. Cookies
-- rather than a Lua table so they also survive the session.
local PREFS = {
	{ key = "brush",      field = "Brush",      default = 0.04 },
	{ key = "hardness",   field = "Hardness",   default = 1 },
	{ key = "strength",   field = "Strength",   default = 1 },
	{ key = "feather",    field = "Feather",    default = 0 },
	{ key = "grow",       field = "Grow",       default = 0 },
	{ key = "islandgrow", field = "IslandGrow", default = 2 },
	{ key = "tolerance",  field = "Tolerance",  default = 0.1 },
	{ key = "picksize",   field = "PickSize",   default = 1 },
	{ key = "col_r",      field = nil,          default = 220 },
	{ key = "col_g",      field = nil,          default = 40 },
	{ key = "col_b",      field = nil,          default = 40 },
	{ key = "col_a",      field = nil,          default = 255 },
	{ key = "bg_r",       field = nil,          default = 255 },
	{ key = "bg_g",       field = nil,          default = 255 },
	{ key = "bg_b",       field = nil,          default = 255 },
	{ key = "bg_a",       field = nil,          default = 255 },
	{ key = "keepshade",  field = nil,          default = 1 },
}

local function Pref( key )
	for _, p in ipairs( PREFS ) do
		if p.key == key then
			return cookie.GetNumber( "advmat_te_" .. key, p.default )
		end
	end
end

--- Dock limits grow with the font instead of remaining 1080p-sized at 4K.
--- The base values are retained at the normal 14--18 px UI sizes, while the
--- wider limits leave translated labels and DNumSlider captions room at 30 px.
local function DockWidthLimits( side )
	local font = math.max( 14, tonumber( AdvMat.FontSize ) or 16 )
	if side == "left" then
		return math.max( 180, font * 10 ), math.max( 220, font * 12 ),
			math.max( 310, font * 16 )
	end

	return math.max( 270, font * 12 ), math.max( 330, font * 16 ),
		math.max( 440, font * 22 )
end

local function StoredDockWidth( side )
	local minW, defaultW, maxW = DockWidthLimits( side )
	local key = side == "left" and "advmat_te_left_w" or "advmat_te_right_w"
	return math.Clamp( cookie.GetNumber( key, defaultW ), minW, maxW )
end

local function WindowLimits()
	local rowH = AdvMat.RowHeight()
	local maxW, maxH = math.max( 760, ScrW() - 40 ), math.max( 560, ScrH() - 40 )
	local leftMin = select( 1, DockWidthLimits( "left" ) )
	local rightMin = select( 1, DockWidthLimits( "right" ) )
	-- Keep a genuinely usable centre workspace between both docks at large
	-- font sizes. On smaller screens maxW still wins and the dock grips let the
	-- user reclaim space manually.
	local minW = math.min( math.max( 1080, AdvMat.FontSize * 36,
		leftMin + rightMin + 500 + 24 ), maxW )
	local minH = math.min( math.max( 620, rowH * 18 ), maxH )
	return minW, minH, maxW, maxH, math.min( 1600, maxW ), math.min( 960, maxH )
end

function PANEL:LoadPrefs()
	for _, p in ipairs( PREFS ) do
		if p.field then
			self[ p.field ] = cookie.GetNumber( "advmat_te_" .. p.key, p.default )
		end
	end

	self.Colour = Color( Pref( "col_r" ), Pref( "col_g" ),
		Pref( "col_b" ), Pref( "col_a" ) )
	self.BackgroundColour = Color( Pref( "bg_r" ), Pref( "bg_g" ),
		Pref( "bg_b" ), Pref( "bg_a" ) )
	self.KeepShading = Pref( "keepshade" ) ~= 0
	self.LastTool = cookie.GetString( "advmat_te_tool", "island" )
	self.WorkspaceMode = cookie.GetString( "advmat_te_workspace", "split" )
	self.RightTab = cookie.GetString( "advmat_te_righttab", "layers" )
	self.ShowSelectionPref = cookie.GetString( "advmat_te_showselection", "both" )
	self.ShowUVPref = cookie.GetNumber( "advmat_te_showuv", 1 ) ~= 0
	self.DocksVisible = cookie.GetNumber( "advmat_te_docks", 1 ) ~= 0
	self.GradientBlend = cookie.GetString( "advmat_te_gradient_blend", "normal" )
	self.PaintBlend = cookie.GetString( "advmat_te_paint_blend", "normal" )
	self.EraseMode = cookie.GetString( "advmat_te_erase_mode", "revert" ) == "holes"
		and "holes" or "revert"
end

--- Written on close rather than on every change: a slider being dragged calls
--- its callback dozens of times a second, and the cookie store is an SQLite
--- write.
function PANEL:SavePrefs()
	for _, p in ipairs( PREFS ) do
		if p.field then
			cookie.Set( "advmat_te_" .. p.key, tostring( self[ p.field ] or p.default ) )
		end
	end

	cookie.Set( "advmat_te_col_r", tostring( self.Colour.r ) )
	cookie.Set( "advmat_te_col_g", tostring( self.Colour.g ) )
	cookie.Set( "advmat_te_col_b", tostring( self.Colour.b ) )
	cookie.Set( "advmat_te_col_a", tostring( self.Colour.a ) )
	cookie.Set( "advmat_te_bg_r", tostring( self.BackgroundColour.r ) )
	cookie.Set( "advmat_te_bg_g", tostring( self.BackgroundColour.g ) )
	cookie.Set( "advmat_te_bg_b", tostring( self.BackgroundColour.b ) )
	cookie.Set( "advmat_te_bg_a", tostring( self.BackgroundColour.a ) )
	cookie.Set( "advmat_te_keepshade", self.KeepShading and "1" or "0" )
	cookie.Set( "advmat_te_tool", tostring( self.Tool or "island" ) )
	cookie.Set( "advmat_te_workspace", tostring( self.WorkspaceMode or "split" ) )
	cookie.Set( "advmat_te_righttab", tostring( self.RightTab or "layers" ) )
	cookie.Set( "advmat_te_showselection", tostring( self.Canvas and self.Canvas.ShowSel or "both" ) )
	cookie.Set( "advmat_te_showuv", self.Canvas and self.Canvas.ShowUV and "1" or "0" )
	cookie.Set( "advmat_te_docks", self.DocksVisible == false and "0" or "1" )
	cookie.Set( "advmat_te_gradient_blend", tostring( self.GradientBlend or "normal" ) )
	cookie.Set( "advmat_te_paint_blend", tostring( self.PaintBlend or "normal" ) )
	cookie.Set( "advmat_te_erase_mode", self.EraseMode == "holes" and "holes" or "revert" )

	local x, y = self:GetPos()
	cookie.Set( "advmat_te_window_x", tostring( x ) )
	cookie.Set( "advmat_te_window_y", tostring( y ) )
	cookie.Set( "advmat_te_window_w", tostring( self:GetWide() ) )
	cookie.Set( "advmat_te_window_h", tostring( self:GetTall() ) )
	if IsValid( self.LeftDock ) then
		cookie.Set( "advmat_te_left_w", tostring( self.LeftDock:GetWide() ) )
	end
	if IsValid( self.RightPanel ) then
		cookie.Set( "advmat_te_right_w", tostring( self.RightPanel:GetWide() ) )
	end
	if IsValid( self.WorkSplit ) and self.WorkSplit.GetLeftWidth then
		local width = self.WorkspaceMode == "split" and self.WorkSplit:GetLeftWidth()
			or self.SavedSplitWidth
		if width and width > 0 then cookie.Set( "advmat_te_split_w", tostring( width ) ) end
	end
end

--- A divider width based on the room inside this editor, not on the desktop.
--- On a high-DPI/4K desktop the frame is deliberately capped, so 30% of ScrW
--- can be wider than the entire remaining workspace and crush the model side
--- down to its minimum.
function PANEL:InitialCanvasWidth( frameWidth, toolWidth, optionsWidth )
	local leftMin, rightMin = 260, 240
	local available = math.max( leftMin + rightMin,
		( frameWidth or 0 ) - ( toolWidth or 0 ) - ( optionsWidth or 0 ) - 18 )
	local ideal = math.floor( available * 0.5 )

	return math.max( leftMin, math.min( ideal, available - rightMin ) )
end

--- Keep the two docks from consuming the document workspace when a user drags
--- both to their maximum widths. Prefer trimming the options dock first; the
--- tool dock contains DNumSliders whose captions need the extra horizontal room.
function PANEL:ClampDockWidths()
	if not IsValid( self.LeftDock ) or not IsValid( self.RightPanel ) then return end

	local leftMin, _, leftMax = DockWidthLimits( "left" )
	local rightMin, _, rightMax = DockWidthLimits( "right" )
	local left = math.Clamp( self.LeftDock:GetWide(), leftMin, leftMax )
	local right = math.Clamp( self.RightPanel:GetWide(), rightMin, rightMax )
	local workMin = math.max( 300, math.min( 520, math.floor( self:GetWide() * 0.42 ) ) )
	local dockRoom = math.max( leftMin + rightMin, self:GetWide() - workMin - 24 )
	local overflow = left + right - dockRoom

	if overflow > 0 then
		local take = math.min( overflow, right - rightMin )
		right, overflow = right - take, overflow - take
		take = math.min( overflow, left - leftMin )
		left = left - take
	end

	self.LeftDock:SetWide( left )
	self.RightPanel:SetWide( right )
end

--- A slim GIMP-style dock boundary. Width cookies are still written only on
--- close, so dragging does not turn into a stream of SQLite writes.
function PANEL:BuildDockSizer( dock, side )
	local grip = vgui.Create( "DPanel", self )
	grip:Dock( side == "left" and LEFT or RIGHT )
	grip:SetWide( math.max( 6, math.floor( AdvMat.FontSize * 0.25 ) ) )
	grip:DockMargin( side == "left" and 0 or 5, 0,
		side == "left" and 5 or 0, 0 )
	grip:SetCursor( "sizewe" )
	grip:SetMouseInputEnabled( true )
	grip.Paint = function( pnl, w, h )
		local col = ( pnl.Dragging or pnl:IsHovered() ) and T.Selected or T.Line
		surface.SetDrawColor( col.r, col.g, col.b, pnl.Dragging and 255 or 170 )
		surface.DrawRect( math.floor( w * 0.5 ), 0, 1, h )
	end

	grip.OnMousePressed = function( pnl, code )
		if code ~= MOUSE_LEFT then return end
		pnl.Dragging = true
		pnl.StartMouse = gui.MouseX()
		pnl.StartWidth = dock:GetWide()
		pnl:MouseCapture( true )
	end

	grip.OnCursorMoved = function( pnl )
		if not pnl.Dragging or not IsValid( dock ) then return end
		local minW, _, hardMax = DockWidthLimits( side )
		local other = side == "left" and self.RightPanel or self.LeftDock
		local otherW = IsValid( other ) and other:GetWide() or 0
		local workMin = math.max( 300, math.min( 520,
			math.floor( self:GetWide() * 0.42 ) ) )
		local availableMax = math.max( minW,
			math.min( hardMax, self:GetWide() - otherW - workMin - 24 ) )
		local delta = gui.MouseX() - pnl.StartMouse
		if side == "right" then delta = -delta end
		dock:SetWide( math.Clamp( pnl.StartWidth + delta, minW, availableMax ) )
		self:InvalidateLayout( true )
	end

	grip.OnMouseReleased = function( pnl, code )
		if code ~= MOUSE_LEFT or not pnl.Dragging then return end
		pnl.Dragging = nil
		pnl:MouseCapture( false )
	end
	grip.OnMouseCaptureLost = function( pnl ) pnl.Dragging = nil end

	grip:SetTooltip( "Drag to resize this dock." )
	return grip
end

function PANEL:Init()
	self.Recipe   = { kind = "edit", ops = {}, size = 512 }
	self.Ctx      = {}
	self.Param    = "$basetexture"
	self.Tool     = "island"
	self.Mode     = "replace"
	self.ActiveLayer = nil
	self.LayerKeepAspect = true
	self.HistoryCurrentName = "Opened texture"

	-- Colour, brush, strength and the rest: whatever they were last time.
	self:LoadPrefs()
	-- SetWorkspaceMode may temporarily fall back to texture-only before Setup
	-- knows whether a model exists. Preserve the requested preference until
	-- that context has been installed.
	self.RestoredWorkspaceMode = self.WorkspaceMode

	-- Replaced in Setup once the texture is known; these only have to be sane
	-- for the panels built below.
	self.NativeW, self.NativeH = 512, 512
	self.WorkW,   self.WorkH   = 512, 512

	local rowH = AdvMat.RowHeight()

	self:SetTitle( "Texture editor" )
	self:SetSizable( true )

	-- The narrowest useful split contains both docks, both 240 px work views,
	-- and the divider margins. Scale the floor modestly with UI font size.
	local minW, minH, maxW, maxH, defaultW, defaultH = WindowLimits()
	local savedW = cookie.GetNumber( "advmat_te_window_w", defaultW )
	local savedH = cookie.GetNumber( "advmat_te_window_h", defaultH )
	local frameW = math.Clamp( savedW, minW, maxW )
	local frameH = math.Clamp( savedH, minH, maxH )

	self:SetSize( frameW, frameH )
	self:SetMinWidth( minW )
	self:SetMinHeight( minH )
	self:SetDeleteOnClose( true )

	local savedX = cookie.GetNumber( "advmat_te_window_x", -1 )
	local savedY = cookie.GetNumber( "advmat_te_window_y", -1 )
	if savedX >= 0 and savedY >= 0 then
		self:SetPos( math.Clamp( savedX, 0, math.max( 0, ScrW() - frameW ) ),
			math.Clamp( savedY, 0, math.max( 0, ScrH() - frameH ) ) )
	else
		self:Center()
	end
	self:MakePopup()
	AdvMat.StyleFrame( self )
	-- This editor predates the shared window service and already persists its
	-- complete workspace geometry in SavePrefs. Tell child placement to respect
	-- that restored position instead of maintaining a second set of cookies.
	self.AdvMatWindowUXGeometryRestored = savedX >= 0 and savedY >= 0

	-- Single-window image-editor layout: application menus across the top,
	-- contextual tools on the left, document docks on the right, then the
	-- texture/model workspace in the middle.
	self:BuildMenuBar()
	self:BuildBottomBar()
	self:BuildToolDock()
	self:BuildRightDock()

	------------------------------------------------------- canvas command row
	-- There are intentionally many texture/selection commands here, and their
	-- translated labels can be considerably wider than English. A plain panel
	-- let those children paint straight through the model hint once they no
	-- longer fitted. The scroller clips them, keeps every command reachable with
	-- its arrows or the mouse wheel, and spans both work views rather than using
	-- only the canvas half.
	local canvasBar = vgui.Create( "DHorizontalScroller", self )
	canvasBar:Dock( TOP )
	canvasBar:SetTall( rowH + 4 )
	canvasBar:DockMargin( 0, 0, 0, 4 )
	canvasBar:SetOverlap( -4 )
	canvasBar.Paint = AdvMat.NoPaint

	self.CanvasBar = canvasBar
	self:BuildCanvasBar( canvasBar )

	------------------------------------------------------------ tool hints
	-- The active tool, what state it is in, and the keys that change it, where
	-- the eye already is. See "The hint bar" below. Docked before the divider
	-- for the same reason as the command row: a FILL sibling added first would
	-- claim the space this needs.
	local hintBar = vgui.Create( "DPanel", self )
	hintBar:Dock( TOP )
	hintBar:SetTall( rowH + 6 )
	hintBar:DockMargin( 0, 0, 0, 4 )
	hintBar.Paint = function( _, w, h ) self:PaintHintBar( w, h ) end
	self.HintBar = hintBar

	--------------------------------------------------------- canvas / model
	local split = vgui.Create( "DHorizontalDivider", self )
	split:Dock( FILL )
	split:SetLeftWidth( self:InitialCanvasWidth(
		self:GetWide(), self.LeftDock:GetWide(), self.RightPanel:GetWide() ) )
	split:SetLeftMin( 260 )
	split:SetRightMin( 240 )
	split:SetDividerWidth( 6 )
	self.WorkSplit = split

	-- Some RTX client builds do not preserve DHorizontalDivider's private
	-- percentage fields. Enforce single-pane workspaces after the divider's own
	-- layout so Texture only and 3D preview only continue to fill a resized
	-- window there as well as in vanilla Garry's Mod.
	local baseSplitLayout = split.PerformLayout
	split.PerformLayout = function( pnl, w, h )
		baseSplitLayout( pnl, w, h )
		local target = self.WorkspaceMode == "texture" and w
			or self.WorkspaceMode == "model" and 1 or nil
		if target and pnl:GetLeftWidth() ~= target then
			pnl:SetLeftWidth( target )
			baseSplitLayout( pnl, w, h )
		end
	end

	local canvasSide = vgui.Create( "DPanel", split )
	canvasSide.Paint = AdvMat.NoPaint
	split:SetLeft( canvasSide )
	self.CanvasSide = canvasSide

	self.Canvas = vgui.Create( "AdvMatCanvas", canvasSide )
	self.Canvas:Dock( FILL )
	self:WireCanvas()

	local modelSide = vgui.Create( "DPanel", split )
	modelSide.Paint = AdvMat.NoPaint
	split:SetRight( modelSide )
	self.ModelSide = modelSide

	self.ModelHint = vgui.Create( "DLabel", modelSide )
	self.ModelHint:Dock( TOP )
	self.ModelHint:SetTall( rowH * 2 )
	self.ModelHint:DockMargin( 0, 0, 0, 4 )
	self.ModelHint:SetText( "Click the model to select that piece of the skin" )
	self.ModelHint:SetWrap( true )
	AdvMat.StyleLabel( self.ModelHint, "AdvMatText", T.TextDim )

	-- Before the model panel: the strip is docked to an edge and the model
	-- panel fills, and a FILL child claims whatever is left at the moment it
	-- is added rather than shrinking for a later sibling.
	AdvMat.ModelView.Build( self, modelSide )

	self.ModelPanel = vgui.Create( "DModelPanel", modelSide )
	self.ModelPanel:Dock( FILL )
	self:WireModelPanel()

	local wantedTool = self.LastTool
	local knownTool = false
	for _, tool in ipairs( TOOLS ) do
		if tool.id == wantedTool then knownTool = true break end
	end
	-- Restoring Transform layer has the side effect of opening the texture
	-- picker before Setup has installed the incoming recipe. Start on a neutral
	-- tool and let selecting an existing layer activate its transform tool.
	if wantedTool == "layer" then knownTool = false end
	self:SetTool( knownTool and wantedTool or "island" )
	self:SetSelectionDisplay( self.ShowSelectionPref )
	self:SetUVVisible( self.ShowUVPref )
	self:SetRightTab( self.RightTab )
	self:SetDocksVisible( self.DocksVisible )

	-- DHorizontalDivider does not know its final width until the first layout.
	-- Restore the saved split after that pass and clamp it to the real workspace.
	timer.Simple( 0, function()
		if not IsValid( self ) or not IsValid( self.WorkSplit ) then return end
		local saved = cookie.GetNumber( "advmat_te_split_w", -1 )
		local full = math.max( 1, self.WorkSplit:GetWide() )
		local chosen = saved > 0 and saved or math.floor( full * 0.5 )
		chosen = math.Clamp( chosen, 240, math.max( 240, full - 240 ) )
		self.SavedSplitWidth = chosen
		self.WorkSplit:SetLeftWidth( chosen )
		self.RestoringWorkspace = true
		self:SetWorkspaceMode( self.WorkspaceMode )
		self.RestoringWorkspace = nil
	end )

	self:RefreshUndoButtons()
	self:RefreshColourLabel()
	self:RefreshHistory()
end

---------------------------------------------------------------------------
-- GIMP-style window chrome and docks
---------------------------------------------------------------------------
function PANEL:BuildBottomBar()
	local rowH = AdvMat.RowHeight()
	local bottom = vgui.Create( "DPanel", self )
	bottom:Dock( BOTTOM )
	bottom:SetTall( rowH * 2 + 13 )
	bottom:DockMargin( 0, 6, 0, 0 )
	bottom.Paint = AdvMat.NoPaint
	self.BottomBar = bottom

	-- Status and actions need independent rows. Their former fixed widths could
	-- exceed the whole window at high DPI and make controls overlap.
	local actionRow = vgui.Create( "DPanel", bottom )
	actionRow:Dock( BOTTOM )
	actionRow:SetTall( rowH + 5 )
	actionRow.Paint = AdvMat.NoPaint
	self.BottomActionRow = actionRow

	local statusRow = vgui.Create( "DPanel", bottom )
	statusRow:Dock( FILL )
	statusRow.Paint = AdvMat.NoPaint
	self.BottomStatusRow = statusRow

	local function Button( text, chars, tip, fn, danger )
		local b = vgui.Create( "DButton", actionRow )
		b:Dock( RIGHT )
		b:SetWide( math.floor( AdvMat.FontSize * chars ) )
		-- Action labels vary substantially between locales. This row has the
		-- horizontal room, so size to the translated text instead of clipping it.
		b.AdvMatI18NAutoWidth = true
		b:DockMargin( 6, 0, 0, 0 )
		b:SetText( text )
		if tip then b:SetTooltip( tip ) end
		b.DoClick = fn
		AdvMat.StyleButton( b, danger )
		return b
	end

	Button( "Cancel", 5, "Close without changing anything.", function() self:Close() end )
	self.ApplyBtn = Button( "Use this texture", 10,
		"Put this edited texture on the material and close.", function() self:Apply() end )
	self.RedoBtn = Button( "Redo", 4.5, "Redo the last undone change.", function() self:Redo() end )
	self.UndoBtn = Button( "Undo", 4.5, "Undo the last change.", function() self:Undo() end )

	local sizeTag = vgui.Create( "DLabel", statusRow )
	sizeTag:Dock( LEFT )
	sizeTag:SetWide( AdvMat.FontSize * 5 )
	sizeTag:SetText( "Save at" )
	sizeTag:SetContentAlignment( 4 )
	AdvMat.StyleLabel( sizeTag, "AdvMatText", T.TextDim )
	self.SizeTag = sizeTag

	self.SizeBox = vgui.Create( "DComboBox", statusRow )
	self.SizeBox:Dock( LEFT )
	self.SizeBox:SetWide( AdvMat.FontSize * 9 )
	self.SizeBox:DockMargin( 0, 3, 8, 3 )
	self.SizeBox:SetSortItems( false )
	self.SizeBox:SetTooltip(
		"The size the finished texture is written at, defaulting to the " ..
		"texture's own - up to the limit beside this.\nPainting happens at a " ..
		"fraction of it so it stays responsive." )
	AdvMat.StyleCombo( self.SizeBox )
	self.SizeBox.OnSelect = function( _, _, _, dims )
		if istable( dims ) then self:SetOutputSize( dims[ 1 ], dims[ 2 ] ) end
	end

	self.LimitBox = AdvMat.SizeLimitBox( statusRow, function()
		if IsValid( self ) then self:RefreshSizeBox() end
	end )
	self.LimitBox:Dock( LEFT )
	self.LimitBox:SetWide( AdvMat.FontSize * 7 )
	self.LimitBox:DockMargin( 0, 3, 8, 3 )

	self.ZoomStatus = vgui.Create( "DLabel", statusRow )
	self.ZoomStatus:Dock( LEFT )
	self.ZoomStatus:SetWide( AdvMat.FontSize * 5 )
	self.ZoomStatus:DockMargin( 0, 0, 8, 0 )
	self.ZoomStatus:SetContentAlignment( 5 )
	AdvMat.StyleLabel( self.ZoomStatus, "AdvMatText", T.TextDim )
	self.ZoomStatus.Think = function( label )
		if IsValid( self.Canvas ) and self.Canvas.Scale then
			label:SetText( math.Round( self.Canvas:Scale() * 100 ) .. "%" )
		end
	end

	self.PixelStatus = vgui.Create( "DLabel", statusRow )
	self.PixelStatus:Dock( LEFT )
	self.PixelStatus:SetWide( AdvMat.FontSize * 16 )
	self.PixelStatus:DockMargin( 0, 0, 8, 0 )
	self.PixelStatus:SetText( "x: --  y: --  RGBA: --" )
	AdvMat.StyleLabel( self.PixelStatus, "AdvMatSmall", T.TextFaint )

	self.SelStatus = vgui.Create( "DLabel", statusRow )
	self.SelStatus:Dock( FILL )
	AdvMat.StyleLabel( self.SelStatus, "AdvMatText", T.TextDim )

	-- Pixel coordinates are useful but expendable on a narrow window. Keep the
	-- selection message visible, then zoom, then coordinates as room permits.
	statusRow.PerformLayout = function( _, w )
		local showPixel = w >= AdvMat.FontSize * 48
		local showZoom = w >= AdvMat.FontSize * 34
		if self.PixelStatus:IsVisible() ~= showPixel then
			self.PixelStatus:SetVisible( showPixel )
		end
		if self.ZoomStatus:IsVisible() ~= showZoom then
			self.ZoomStatus:SetVisible( showZoom )
		end
	end
end

local function PaintSwatch( colour )
	return function( _, w, h )
		surface.SetDrawColor( 92, 94, 100 )
		surface.DrawRect( 0, 0, w, h )
		surface.SetDrawColor( 58, 60, 66 )
		surface.DrawRect( 0, 0, w * 0.5, h * 0.5 )
		surface.DrawRect( w * 0.5, h * 0.5, w * 0.5, h * 0.5 )
		local c = colour()
		surface.SetDrawColor( c.r, c.g, c.b, c.a )
		surface.DrawRect( 2, 2, w - 4, h - 4 )
		surface.SetDrawColor( T.Line.r, T.Line.g, T.Line.b, 255 )
		surface.DrawOutlinedRect( 0, 0, w, h, 1 )
	end
end

function PANEL:BuildToolDock()
	local rowH = AdvMat.RowHeight()
	local dock = vgui.Create( "DPanel", self )
	dock:Dock( LEFT )
	dock:SetWide( StoredDockWidth( "left" ) )
	dock.Paint = AdvMat.Fill( T.Panel )
	self.LeftDock = dock
	self.LeftDockSizer = self:BuildDockSizer( dock, "left" )

	local head = vgui.Create( "DLabel", dock )
	head:Dock( TOP )
	head:SetTall( rowH + 2 )
	head:SetText( "Tools" )
	AdvMat.StyleLabel( head, "AdvMatBold", T.Text )
	self.ToolHead = head

	local grid = vgui.Create( "DPanel", dock )
	grid:Dock( TOP )
	local cell = rowH + 14
	grid:SetTall( math.ceil( #TOOLS / 2 ) * cell + 6 )
	grid.Paint = AdvMat.NoPaint
	self.ToolGrid = grid
	self.ToolButtons = {}

	for index, tool in ipairs( TOOLS ) do
		local b = vgui.Create( "DButton", grid )
		b:SetText( "" )
		b:SetTooltip( tool.label .. "  (" .. tool.shortcut .. ")\n" .. tool.tip )
		b.Paint = function( pnl, w, h )
			local on = self.Tool == tool.id
			local bg = on and T.Selected or ( pnl:IsHovered() and T.HeaderHot or T.Header )
			surface.SetDrawColor( bg.r, bg.g, bg.b, 255 )
			surface.DrawRect( 0, 0, w, h )
			surface.SetDrawColor( T.Line.r, T.Line.g, T.Line.b, 255 )
			surface.DrawOutlinedRect( 0, 0, w, h, 1 )
			local glyph = math.min( w, h ) - 8
			ToolGlyph( tool.id, ( w - glyph ) * 0.5, ( h - glyph ) * 0.5,
				glyph, on and T.Text or T.TextDim )
		end
		b.DoClick = function() self:SetTool( tool.id ) end
		self.ToolButtons[ tool.id ] = b
	end

	grid.PerformLayout = function( pnl, w )
		local gap = 3
		local currentCell = AdvMat.RowHeight() + 14
		pnl:SetTall( math.ceil( #TOOLS / 2 ) * currentCell + 6 )
		local wide = math.floor( ( w - gap * 3 ) * 0.5 )
		for index, tool in ipairs( TOOLS ) do
			local b = self.ToolButtons[ tool.id ]
			if IsValid( b ) then
				local col, row = ( index - 1 ) % 2, math.floor( ( index - 1 ) / 2 )
				b:SetPos( gap + col * ( wide + gap ), 3 + row * currentCell )
				b:SetSize( wide, currentCell - gap )
			end
		end
	end

	local colours = vgui.Create( "DPanel", dock )
	colours:Dock( TOP )
	colours:SetTall( rowH * 3 + 12 )
	colours:DockMargin( 4, 4, 4, 6 )
	colours.Paint = AdvMat.NoPaint
	self.ColourDock = colours

	self.BGSwatch = vgui.Create( "DButton", colours )
	self.BGSwatch:SetPos( 34, 21 )
	self.BGSwatch:SetSize( rowH * 2, rowH * 2 )
	self.BGSwatch:SetText( "" )
	self.BGSwatch:SetTooltip( "Background colour. Click to change it." )
	self.BGSwatch.Paint = PaintSwatch( function() return self.BackgroundColour end )
	self.BGSwatch.DoClick = function() self:OpenColourPicker( "background" ) end

	self.FGSwatch = vgui.Create( "DButton", colours )
	self.FGSwatch:SetPos( 8, 5 )
	self.FGSwatch:SetSize( rowH * 2, rowH * 2 )
	self.FGSwatch:SetText( "" )
	self.FGSwatch:SetTooltip( "Foreground colour. Click to change it." )
	self.FGSwatch.Paint = PaintSwatch( function() return self.Colour end )
	self.FGSwatch.DoClick = function() self:OpenColourPicker( "foreground" ) end
	self.Swatch = self.FGSwatch -- compatibility with the pre-dock editor

	local defaults = vgui.Create( "DButton", colours )
	defaults:SetPos( 8, rowH * 2 + 10 )
	defaults:SetSize( rowH + 4, rowH + 2 )
	defaults:SetText( "D" )
	defaults:SetTooltip( "Reset foreground/background to black and white (D)" )
	AdvMat.StyleButton( defaults )
	defaults.DoClick = function() self:DefaultColours() end
	self.DefaultColoursBtn = defaults

	local swap = vgui.Create( "DButton", colours )
	swap:SetPos( rowH + 16, rowH * 2 + 10 )
	swap:SetSize( rowH + 4, rowH + 2 )
	swap:SetText( "X" )
	swap:SetTooltip( "Swap foreground and background colours (X)" )
	AdvMat.StyleButton( swap )
	swap.DoClick = function() self:SwapColours() end
	self.SwapColoursBtn = swap

	self.ColourLabel = vgui.Create( "DLabel", colours )
	self.ColourLabel:SetPos( rowH * 3 + 14, 5 )
	self.ColourLabel:SetSize( math.max( 40, dock:GetWide() - rowH * 3 - 22 ), rowH * 2 )
	self.ColourLabel:SetWrap( true )
	AdvMat.StyleLabel( self.ColourLabel, "AdvMatSmall", T.TextDim )
	colours.PerformLayout = function( pnl, w )
		local currentRowH = AdvMat.RowHeight()
		pnl:SetTall( currentRowH * 3 + 12 )
		self.BGSwatch:SetPos( 34, 21 )
		self.BGSwatch:SetSize( currentRowH * 2, currentRowH * 2 )
		self.FGSwatch:SetPos( 8, 5 )
		self.FGSwatch:SetSize( currentRowH * 2, currentRowH * 2 )
		self.DefaultColoursBtn:SetPos( 8, currentRowH * 2 + 10 )
		self.DefaultColoursBtn:SetSize( currentRowH + 4, currentRowH + 2 )
		self.SwapColoursBtn:SetPos( currentRowH + 16, currentRowH * 2 + 10 )
		self.SwapColoursBtn:SetSize( currentRowH + 4, currentRowH + 2 )
		self.ColourLabel:SetPos( currentRowH * 3 + 14, 5 )
		self.ColourLabel:SetSize( math.max( 40, w - currentRowH * 3 - 22 ),
			currentRowH * 2 )
	end

	self.OptsHead = vgui.Create( "DLabel", dock )
	self.OptsHead:Dock( TOP )
	self.OptsHead:SetTall( rowH + 2 )
	AdvMat.StyleLabel( self.OptsHead, "AdvMatTitle", T.Text )

	local reset = vgui.Create( "DButton", dock )
	reset:Dock( BOTTOM )
	reset:SetTall( rowH + 5 )
	reset:DockMargin( 4, 4, 4, 4 )
	reset:SetText( "Reset tool options" )
	reset:SetTooltip( "Restore the selected tool's normal settings." )
	AdvMat.StyleButton( reset )
	reset.DoClick = function() self:ResetToolOptions() end
	self.ToolResetBtn = reset

	self.Opts = vgui.Create( "DScrollPanel", dock )
	self.Opts:Dock( FILL )
	self.Opts:DockMargin( 4, 2, 4, 0 )
	self.Opts.Paint = AdvMat.Fill( T.Panel )
end

function PANEL:BuildRightDock()
	local rowH = AdvMat.RowHeight()
	local right = vgui.Create( "DPanel", self )
	right:Dock( RIGHT )
	right:SetWide( StoredDockWidth( "right" ) )
	right.Paint = AdvMat.Fill( T.Panel )
	self.RightPanel = right
	self.RightDockSizer = self:BuildDockSizer( right, "right" )
	self:ClampDockWidths()

	local tabs = vgui.Create( "DPanel", right )
	tabs:Dock( TOP )
	tabs:SetTall( rowH + 7 )
	tabs.Paint = AdvMat.NoPaint
	self.RightTabs = tabs
	self.RightTabButtons = {}

	local pageHost = vgui.Create( "DPanel", right )
	pageHost:Dock( FILL )
	pageHost.Paint = AdvMat.NoPaint
	self.RightPages = {}

	local function Page( id, label )
		local b = vgui.Create( "DButton", tabs )
		b:Dock( LEFT )
		b:SetWide( math.floor( right:GetWide() / 3 ) )
		b:SetText( label )
		-- The skin's dark button text disappears into these fills; see the
		-- note at the top of cl_30_theme.lua.
		b:SetFont( "AdvMatText" )
		b:SetTextColor( T.Text )
		b.Paint = function( pnl, w, h )
			local on = self.RightTab == id
			local col = on and T.Selected or ( pnl:IsHovered() and T.HeaderHot or T.Header )
			surface.SetDrawColor( col.r, col.g, col.b, 255 )
			surface.DrawRect( 0, 0, w, h )
			surface.SetDrawColor( T.Line.r, T.Line.g, T.Line.b, 255 )
			surface.DrawOutlinedRect( 0, 0, w, h, 1 )
		end
		b.DoClick = function() self:SetRightTab( id ) end
		self.RightTabButtons[ id ] = b

		local page = vgui.Create( "DPanel", pageHost )
		page:Dock( FILL )
		page.Paint = AdvMat.NoPaint
		self.RightPages[ id ] = page
		return page
	end

	local layersPage = Page( "layers", "Layers" )
	local effectsPage = Page( "effects", "Effects" )
	local historyPage = Page( "history", "History" )
	tabs.PerformLayout = function( _, w )
		local tabWidth = math.floor( w / 3 )
		for _, button in pairs( self.RightTabButtons or {} ) do
			if IsValid( button ) then button:SetWide( tabWidth ) end
		end
	end

	self.LayerActions = vgui.Create( "DHorizontalScroller", layersPage )
	self.LayerActions:Dock( BOTTOM )
	self.LayerActions:SetTall( rowH + 7 )
	self.LayerActions:DockMargin( 0, 3, 0, 0 )
	self.LayerActions:SetOverlap( -4 )
	self.LayerActions.Paint = AdvMat.NoPaint
	self:BuildLayerActions()

	self.Layers = vgui.Create( "DScrollPanel", layersPage )
	self.Layers:Dock( FILL )
	self.Layers.Paint = AdvMat.Fill( T.Panel )

	-- Before the list: an edge-docked sibling has to exist before the FILL one
	-- claims the page.
	self.StepSummary = vgui.Create( "DLabel", effectsPage )
	self.StepSummary:Dock( TOP )
	self.StepSummary:DockMargin( 4, 2, 4, 3 )
	self.StepSummary:SetWrap( true )
	self.StepSummary:SetAutoStretchVertical( true )
	AdvMat.StyleLabel( self.StepSummary, "AdvMatSmall", T.TextDim )

	self.Steps = vgui.Create( "DScrollPanel", effectsPage )
	self.Steps:Dock( FILL )
	self.Steps.Paint = AdvMat.Fill( T.Panel )

	local historyActions = vgui.Create( "DPanel", historyPage )
	historyActions:Dock( TOP )
	historyActions:SetTall( rowH + 7 )
	historyActions.Paint = AdvMat.NoPaint
	self.HistoryActions = historyActions

	local hu = vgui.Create( "DButton", historyActions )
	hu:Dock( LEFT ); hu:SetWide( right:GetWide() * 0.5 ); hu:SetText( "Undo" )
	AdvMat.StyleButton( hu ); hu.DoClick = function() self:Undo() end
	self.HistoryUndoBtn = hu
	local hr = vgui.Create( "DButton", historyActions )
	hr:Dock( FILL ); hr:SetText( "Redo" )
	AdvMat.StyleButton( hr ); hr.DoClick = function() self:Redo() end
	self.HistoryRedoBtn = hr
	historyActions.PerformLayout = function( _, w )
		if IsValid( hu ) then hu:SetWide( math.floor( w * 0.5 ) ) end
	end

	self.HistoryList = vgui.Create( "DScrollPanel", historyPage )
	self.HistoryList:Dock( FILL )
	self.HistoryList:DockMargin( 0, 3, 0, 0 )
	self.HistoryList.Paint = AdvMat.Fill( T.Panel )

	-- Legacy references remain valid for region-mode and language-refresh code.
	self.LayersHead = self.RightTabButtons.layers
end

--- Reflow the open editor after a resolution/UI-scale change. Font objects are
--- rebuilt globally, but fixed panel heights and dock widths still need to be
--- brought into line with the new metrics. Preserve each scroll position while
--- recreating rows at their new height.
function PANEL:ApplyUIScale()
	local minW, minH, maxW, maxH = WindowLimits()
	local width = math.Clamp( self:GetWide(), minW, maxW )
	local height = math.Clamp( self:GetTall(), minH, maxH )
	self:SetMinWidth( minW )
	self:SetMinHeight( minH )
	self:SetSize( width, height )
	local x, y = self:GetPos()
	self:SetPos( math.Clamp( x, 0, math.max( 0, ScrW() - width ) ),
		math.Clamp( y, 0, math.max( 0, ScrH() - height ) ) )

	local rowH = AdvMat.RowHeight()
	if IsValid( self.LeftDock ) then
		local minDock, _, maxDock = DockWidthLimits( "left" )
		self.LeftDock:SetWide( math.Clamp( self.LeftDock:GetWide(), minDock, maxDock ) )
	end
	if IsValid( self.RightPanel ) then
		local minDock, _, maxDock = DockWidthLimits( "right" )
		self.RightPanel:SetWide( math.Clamp( self.RightPanel:GetWide(), minDock, maxDock ) )
	end
	self:ClampDockWidths()

	for _, grip in ipairs( { self.LeftDockSizer, self.RightDockSizer } ) do
		if IsValid( grip ) then
			grip:SetWide( math.max( 6, math.floor( AdvMat.FontSize * 0.25 ) ) )
		end
	end
	if IsValid( self.MenuBar ) then self.MenuBar:SetTall( rowH + 2 ) end
	if IsValid( self.BottomBar ) then self.BottomBar:SetTall( rowH * 2 + 13 ) end
	if IsValid( self.BottomActionRow ) then self.BottomActionRow:SetTall( rowH + 5 ) end
	if IsValid( self.CanvasBar ) then self.CanvasBar:SetTall( rowH + 4 ) end
	if IsValid( self.HintBar ) then self.HintBar:SetTall( rowH + 6 ) end
	if IsValid( self.ModelHint ) then self.ModelHint:SetTall( rowH * 2 ) end
	if IsValid( self.ToolHead ) then self.ToolHead:SetTall( rowH + 2 ) end
	if IsValid( self.ToolGrid ) then self.ToolGrid:InvalidateLayout( true ) end
	if IsValid( self.ColourDock ) then self.ColourDock:InvalidateLayout( true ) end
	if IsValid( self.OptsHead ) then self.OptsHead:SetTall( rowH + 2 ) end
	if IsValid( self.ToolResetBtn ) then self.ToolResetBtn:SetTall( rowH + 5 ) end
	if IsValid( self.RightTabs ) then
		self.RightTabs:SetTall( rowH + 7 )
		self.RightTabs:InvalidateLayout( true )
	end
	if IsValid( self.LayerActions ) then self.LayerActions:SetTall( rowH + 7 ) end
	if IsValid( self.HistoryActions ) then self.HistoryActions:SetTall( rowH + 7 ) end
	if IsValid( self.SizeTag ) then self.SizeTag:SetWide( AdvMat.FontSize * 5 ) end
	if IsValid( self.SizeBox ) then self.SizeBox:SetWide( AdvMat.FontSize * 9 ) end
	if IsValid( self.LimitBox ) then self.LimitBox:SetWide( AdvMat.FontSize * 7 ) end
	if IsValid( self.ZoomStatus ) then self.ZoomStatus:SetWide( AdvMat.FontSize * 5 ) end
	if IsValid( self.PixelStatus ) then self.PixelStatus:SetWide( AdvMat.FontSize * 16 ) end

	local scrolls = {}
	for key, panel in pairs( {
		layers = self.Layers, steps = self.Steps, history = self.HistoryList,
		opts = self.Opts,
	} ) do
		local bar = IsValid( panel ) and panel.GetVBar and panel:GetVBar() or nil
		if IsValid( bar ) then scrolls[ key ] = bar:GetScroll() end
	end

	self:RefreshLayers()
	self:RefreshSteps()
	self:RefreshHistory()
	self:BuildOptions()
	self:InvalidateLayout( true )

	timer.Simple( 0, function()
		if not IsValid( self ) then return end
		for key, panel in pairs( {
			layers = self.Layers, steps = self.Steps, history = self.HistoryList,
			opts = self.Opts,
		} ) do
			local bar = IsValid( panel ) and panel.GetVBar and panel:GetVBar() or nil
			if scrolls[ key ] and IsValid( bar ) then bar:SetScroll( scrolls[ key ] ) end
		end
	end )
end

---------------------------------------------------------------------------
-- Menus and workspace state
---------------------------------------------------------------------------
local function AddMenuOption( menu, label, fn, icon )
	local option = menu:AddOption( label, fn )
	if icon then option:SetIcon( icon ) end
	return option
end

function PANEL:BuildMenuBar()
	local bar = vgui.Create( "DMenuBar", self )
	bar:Dock( TOP )
	bar:SetTall( AdvMat.RowHeight() + 2 )
	bar:DockMargin( 0, 0, 0, 4 )
	bar.Paint = AdvMat.Fill( T.Header )
	AdvMat.I18N.Track( bar )
	self.MenuBar = bar
	self.MenuEntries = {}
	self.MenuKeyButtons = {}

	local function Menu( label, key )
		local menu = bar:AddMenu( key and AdvMat.L( key ) or label )
		AdvMat.I18N.Track( menu )
		self.MenuEntries[ #self.MenuEntries + 1 ] = menu
		local children = bar:GetChildren()
		local button = children[ #children ]
		if IsValid( button ) then
			button.AdvMatI18NAutoWidth = true
			-- DMenuBar's buttons take the skin's dark text, which all but vanished
			-- on this header colour.
			button:SetFont( "AdvMatText" )
			button:SetTextColor( T.Text )
		end
		if key then
			self.MenuKeyButtons[ key ] = button
		end
		return menu
	end

	local fileMenu = Menu( "File" )
	AddMenuOption( fileMenu, "Start from the source texture", function()
		self:SetStart( self.OriginalSrc )
	end, "icon16/image.png" )
	AddMenuOption( fileMenu, "Start from a blank white image", function()
		self:SetStart( nil, { 255, 255, 255, 255 } )
	end, "icon16/page_white.png" )
	AddMenuOption( fileMenu, "Start from a blank transparent image", function()
		self:SetStart( nil, { 255, 255, 255, 0 } )
	end, "icon16/page_white_picture.png" )
	AddMenuOption( fileMenu, "Start from the foreground colour", function()
		local c = self.Colour
		self:SetStart( nil, { c.r, c.g, c.b, c.a } )
	end )
	fileMenu:AddSpacer()
	AddMenuOption( fileMenu, "Import as layer...", function()
		if not self.RegionMode then self:ImportLayer() end
	end, "icon16/picture_add.png" )
	fileMenu:AddSpacer()
	self.FileApplyOption = AddMenuOption( fileMenu, "Use this texture",
		function() self:Apply() end, "icon16/accept.png" )
	AddMenuOption( fileMenu, "Close", function() self:Close() end,
		"icon16/cross.png" )

	local editMenu = Menu( "Edit", "texture.menu_edit" )
	AddMenuOption( editMenu, "Undo", function() self:Undo() end,
		"icon16/arrow_undo.png" )
	AddMenuOption( editMenu, "Redo", function() self:Redo() end,
		"icon16/arrow_redo.png" )
	editMenu:AddSpacer()
	AddMenuOption( editMenu, "Foreground colour...", function()
		self:OpenColourPicker( "foreground" )
	end )
	AddMenuOption( editMenu, "Background colour...", function()
		self:OpenColourPicker( "background" )
	end )
	AddMenuOption( editMenu, "Use default colours", function() self:DefaultColours() end )
	AddMenuOption( editMenu, "Swap colours", function() self:SwapColours() end )
	editMenu:AddSpacer()
	AddMenuOption( editMenu, "Reset tool options", function() self:ResetToolOptions() end )

	local selectMenu = Menu( "Select" )
	AddMenuOption( selectMenu, "Select all", function() self:SetSelection( SEL.All() ) end )
	AddMenuOption( selectMenu, "Select none", function() self:SetSelection( nil ) end )
	AddMenuOption( selectMenu, "Invert selection", function()
		if not self.Sel then self:SetSelection( SEL.All() ) end
		local sel = table.Copy( self.Sel )
		sel.invert = not sel.invert
		self:SetSelection( sel )
	end )
	selectMenu:AddSpacer()
	AddMenuOption( selectMenu, "Grow selection...", function()
		self:PromptSelectionChange( "grow", false )
	end )
	AddMenuOption( selectMenu, "Shrink selection...", function()
		self:PromptSelectionChange( "grow", true )
	end )
	AddMenuOption( selectMenu, "Feather selection...", function()
		self:PromptSelectionChange( "feather", false )
	end )
	selectMenu:AddSpacer()
	AddMenuOption( selectMenu, "Saved selections...", function() self:OpenAreaMenu() end )

	-- "Image" is also the French translation of the animation-frame label,
	-- so reverse lookup is deliberately ambiguous.  Use the stable key here.
	local imageMenu = Menu( "Image", "texture.menu_image" )
	AddMenuOption( imageMenu, "Use source dimensions", function()
		self:SetOutputSize( self.NativeW or 512, self.NativeH or self.NativeW or 512 )
		self:RefreshSizeBox()
	end )
	local scaleMenu = imageMenu:AddSubMenu( "Scale output" )
	for _, size in ipairs( { 256, 512, 1024, 2048, 4096 } ) do
		local target = size
		local option = AddMenuOption( scaleMenu, target .. " px", function()
			local nativeW, nativeH = self.NativeW or target, self.NativeH or self.NativeW or target
			local width, height
			if nativeW >= nativeH then
				width, height = target, math.max( 1, math.floor( target * nativeH / nativeW + 0.5 ) )
			else
				height, width = target, math.max( 1, math.floor( target * nativeW / nativeH + 0.5 ) )
			end
			self:SetOutputSize( width, height )
			self:RefreshSizeBox()
		end )
		if target > AdvMat.Gen.MaxSize() then option:SetDisabled( true ) end
	end
	imageMenu:AddSpacer()
	AddMenuOption( imageMenu, "Reset canvas view", function() self.Canvas:FitToWindow() end )

	local toolsMenu = Menu( "Tools" )
	for _, definition in ipairs( TOOLS ) do
		local tool = definition
		AddMenuOption( toolsMenu, tool.label,
			function() self:SetTool( tool.id ) end )
	end

	local coloursMenu = Menu( "Colors" )
	AddMenuOption( coloursMenu, "Brightness, colour and contrast...", function()
		if not self.RegionMode then self:OpenAdjustDialog() end
	end )
	AddMenuOption( coloursMenu, "Desaturate", function()
		if not self.RegionMode then
			self:AddStep( { op = "adjust", sel = self:StepSelection(), desat = 1 } )
		end
	end )
	AddMenuOption( coloursMenu, "Invert colours", function()
		if not self.RegionMode then
			self:AddStep( { op = "adjust", sel = self:StepSelection(), invert = true } )
		end
	end )
	AddMenuOption( coloursMenu, "Gamma...", function()
		if not self.RegionMode then self:PromptAdjustment( "gamma" ) end
	end )
	AddMenuOption( coloursMenu, "Posterize...", function()
		if not self.RegionMode then self:PromptAdjustment( "posterize" ) end
	end )
	AddMenuOption( coloursMenu, "Threshold...", function()
		if not self.RegionMode then self:PromptAdjustment( "threshold" ) end
	end )

	local filtersMenu = Menu( "Filters" )
	AddMenuOption( filtersMenu, "Blur", function()
		if not self.RegionMode then
			self:AddStep( { op = "blur", sel = self:StepSelection(), radius = 3 } )
		end
	end )
	AddMenuOption( filtersMenu, "Sharpen", function()
		if not self.RegionMode then
			self:AddStep( { op = "sharpen", sel = self:StepSelection(), amount = 1 } )
		end
	end )
	AddMenuOption( filtersMenu, "Add noise", function()
		if not self.RegionMode then
			self:AddStep( { op = "noise", sel = self:StepSelection(), amount = 0.15,
				seed = #self.Recipe.ops + 1, mono = true } )
		end
	end )
	AddMenuOption( filtersMenu, "Make dark parts transparent", function()
		if not self.RegionMode then
			self:AddStep( { op = "alphafrom", sel = self:StepSelection(),
				from = "luminance", threshold = 0.35, softness = 0.15 } )
		end
	end )

	local layerMenu = Menu( "Layer" )
	AddMenuOption( layerMenu, "Import as layer...", function()
		if not self.RegionMode then self:ImportLayer() end
	end )
	AddMenuOption( layerMenu, "Change layer source...", function() self:ChangeLayerSource() end )
	AddMenuOption( layerMenu, "Duplicate layer", function() self:DuplicateLayer() end )
	AddMenuOption( layerMenu, "Raise layer", function() self:MoveLayer( 1 ) end )
	AddMenuOption( layerMenu, "Lower layer", function() self:MoveLayer( -1 ) end )
	layerMenu:AddSpacer()
	AddMenuOption( layerMenu, "Centre layer", function()
		self:EditLayer( function( layer ) layer.x, layer.y = 0.5, 0.5 end )
		self:BuildOptions()
	end )
	AddMenuOption( layerMenu, "Fit layer to canvas", function()
		self:EditLayer( function( layer ) self:FitLayer( layer ) end )
		self:BuildOptions()
	end )
	AddMenuOption( layerMenu, "Reset layer transform", function() self:ResetActiveLayer() end )
	layerMenu:AddSpacer()
	AddMenuOption( layerMenu, "Delete layer", function() self:DeleteLayer() end,
		"icon16/delete.png" )

	local viewMenu = Menu( "View" )
	AddMenuOption( viewMenu, "Texture only", function() self:SetWorkspaceMode( "texture" ) end )
	AddMenuOption( viewMenu, "Split texture and 3D preview", function()
		self:SetWorkspaceMode( "split" )
	end )
	AddMenuOption( viewMenu, "3D preview only", function() self:SetWorkspaceMode( "model" ) end )
	viewMenu:AddSpacer()
	AddMenuOption( viewMenu, "Fit canvas in window", function() self.Canvas:FitToWindow() end )
	AddMenuOption( viewMenu, "Zoom to 100%", function()
		self.Canvas.Zoom = 7
		self.Canvas.PanX = ( self.Canvas.SizeW - self.Canvas:GetWide() ) * 0.5
		self.Canvas.PanY = ( self.Canvas.SizeH - self.Canvas:GetTall() ) * 0.5
	end )
	AddMenuOption( viewMenu, "Zoom in", function() self.Canvas:ZoomBy( 1 ) end )
	AddMenuOption( viewMenu, "Zoom out", function() self.Canvas:ZoomBy( -1 ) end )
	viewMenu:AddSpacer()
	AddMenuOption( viewMenu, "Cycle selection display", function() self:CycleSelectionDisplay() end )
	AddMenuOption( viewMenu, "Toggle UV overlay", function()
		self:SetUVVisible( not self.Canvas.ShowUV )
	end )
	AddMenuOption( viewMenu, "Toggle docks", function()
		self:SetDocksVisible( not self.DocksVisible )
	end )

	local helpMenu = Menu( "Help" )
	AddMenuOption( helpMenu, "Keyboard shortcuts", function() self:OpenShortcutHelp() end,
		"icon16/keyboard.png" )
end

function PANEL:DefaultColours()
	self.Colour = Color( 0, 0, 0, 255 )
	self.BackgroundColour = Color( 255, 255, 255, 255 )
	self:RefreshColourLabel()
end

function PANEL:SwapColours()
	self.Colour, self.BackgroundColour = self.BackgroundColour, self.Colour
	self:RefreshColourLabel()
end

function PANEL:SetSelectionDisplay( id )
	local chosen = SHOW_SELECTION[ 1 ]
	for _, entry in ipairs( SHOW_SELECTION ) do
		if entry.id == id then chosen = entry break end
	end
	if IsValid( self.Canvas ) then self.Canvas:SetShowSelection( chosen.id ) end
	self.ShowSelectionPref = chosen.id
	if IsValid( self.ShowBtn ) then self.ShowBtn:SetText( chosen.label ) end
end

function PANEL:CycleSelectionDisplay()
	local current = IsValid( self.Canvas ) and self.Canvas.ShowSel or self.ShowSelectionPref
	local at = 1
	for i, entry in ipairs( SHOW_SELECTION ) do
		if entry.id == current then at = i break end
	end
	self:SetSelectionDisplay( SHOW_SELECTION[ ( at % #SHOW_SELECTION ) + 1 ].id )
end

function PANEL:SetUVVisible( visible )
	visible = visible == true
	self.ShowUVPref = visible
	if IsValid( self.Canvas ) then self.Canvas.ShowUV = visible end
	if IsValid( self.UVCheck ) and self.UVCheck:GetChecked() ~= visible then
		self.SettingUV = true
		self.UVCheck:SetValue( visible )
		self.SettingUV = nil
	end
end

function PANEL:SetRightTab( id )
	if not self.RightPages or not self.RightPages[ id ] then id = "layers" end
	self.RightTab = id
	for name, page in pairs( self.RightPages or {} ) do
		if IsValid( page ) then page:SetVisible( name == id ) end
	end
	for _, button in pairs( self.RightTabButtons or {} ) do
		if IsValid( button ) then button:InvalidateLayout() end
	end

	-- The step list is only kept current while it is on show.
	if id == "effects" and self.StepsDirty and self.Recipe then self:RefreshSteps() end
end

function PANEL:SetDocksVisible( visible )
	visible = visible ~= false
	self.DocksVisible = visible
	if IsValid( self.LeftDock ) then self.LeftDock:SetVisible( visible ) end
	if IsValid( self.LeftDockSizer ) then self.LeftDockSizer:SetVisible( visible ) end
	if IsValid( self.RightPanel ) then self.RightPanel:SetVisible( visible and not self.RegionMode ) end
	if IsValid( self.RightDockSizer ) then
		self.RightDockSizer:SetVisible( visible and not self.RegionMode )
	end
	self:InvalidateLayout( true )
end

function PANEL:SetWorkspaceMode( id )
	if id ~= "texture" and id ~= "model" and id ~= "split" then id = "split" end
	if id == "model" and not self.HaveModel then id = "texture" end
	local split = self.WorkSplit
	if not IsValid( split ) then self.WorkspaceMode = id return end

	if self.WorkspaceMode == "split" and not self.RestoringWorkspace and split.GetLeftWidth then
		self.SavedSplitWidth = split:GetLeftWidth()
	end
	self.WorkspaceMode = id

	local full = math.max( 1, split:GetWide() )
	local function SetLeftWidth( width )
		split:SetLeftWidth( width )
		-- DHorizontalDivider normally updates this ratio only after a mouse drag.
		-- Keep programmatic single-pane modes stable when the frame is resized.
		split._iLeftWidthPct = math.Clamp( width / full, 0, 1 )
		split._iLastWidth = full
	end
	if id == "split" then
		self.CanvasSide:SetVisible( true )
		self.ModelSide:SetVisible( self.HaveModel == true )
		split:SetDividerWidth( self.HaveModel and 6 or 0 )
		split:SetLeftMin( self.HaveModel and 240 or 1 )
		split:SetRightMin( self.HaveModel and 240 or 0 )
		local width = self.SavedSplitWidth or math.floor( full * 0.5 )
		if not self.HaveModel then width = full end
		SetLeftWidth( math.Clamp( width, self.HaveModel and 240 or 1,
			self.HaveModel and math.max( 240, full - 240 ) or full ) )
	elseif id == "texture" then
		self.CanvasSide:SetVisible( true )
		self.ModelSide:SetVisible( false )
		split:SetDividerWidth( 0 )
		split:SetLeftMin( 1 )
		split:SetRightMin( 0 )
		SetLeftWidth( full )
	else
		-- The canvas owns texture uploads/compositing in its Think method. Keep a
		-- one-pixel visible sliver in model-only mode so that processing continues
		-- while the 3D preview receives effectively all of the workspace.
		self.CanvasSide:SetVisible( true )
		self.ModelSide:SetVisible( true )
		split:SetDividerWidth( 0 )
		split:SetLeftMin( 1 )
		split:SetRightMin( 1 )
		SetLeftWidth( 1 )
	end

	for name, button in pairs( self.WorkspaceButtons or {} ) do
		if IsValid( button ) then button:InvalidateLayout() end
	end
	split:InvalidateLayout( true )
end

function PANEL:OpenStartMenu()
	local menu = DermaMenu()
	AdvMat.I18N.Track( menu )
	AddMenuOption( menu, "The texture that is there now", function()
		self:SetStart( self.OriginalSrc )
	end, "icon16/image.png" )
	AddMenuOption( menu, "A blank white image", function()
		self:SetStart( nil, { 255, 255, 255, 255 } )
	end )
	AddMenuOption( menu, "A blank transparent image", function()
		self:SetStart( nil, { 255, 255, 255, 0 } )
	end )
	AddMenuOption( menu, "A blank image in the current colour", function()
		local c = self.Colour
		self:SetStart( nil, { c.r, c.g, c.b, c.a } )
	end )
	menu:Open()
end

function PANEL:PromptSelectionChange( field, negative )
	if not self.Sel then
		self:Status( "Select an area first.", true )
		return
	end
	local title = field == "feather" and "Feather selection" or
		( negative and "Shrink selection" or "Grow selection" )
	Derma_StringRequest( AdvMat.LText( title ), AdvMat.LText( "Pixels" ), "2",
		function( raw )
			if not IsValid( self ) or not self.Sel then return end
			local pixels = math.Clamp( tonumber( raw ) or 0, 0, 256 )
			local sel = table.Copy( self.Sel )
			if field == "feather" then
				sel.feather = pixels * self:PixelFraction()
			else
				sel.grow = ( sel.grow or 0 ) + ( negative and -pixels or pixels )
					* self:PixelFraction()
			end
			self:SetSelection( sel )
		end )
end

function PANEL:PromptAdjustment( field )
	-- Keep the menu shortcuts, but put them in the same live dialog as the
	-- colour controls.  A string prompt cannot show what gamma, posterisation or
	-- threshold will do until after the irreversible AddStep click.
	self:OpenAdjustDialog( field )
end

function PANEL:ResetActiveLayer()
	self:EditLayer( function( layer )
		layer.x, layer.y, layer.angle = 0.5, 0.5, 0
		layer.flipx, layer.flipy = nil, nil
		self:FitLayer( layer )
	end )
	self:BuildOptions()
end

function PANEL:ResetToolOptions()
	local tool = self.Tool
	if tool == "layer" then
		self:ResetActiveLayer()
		return
	elseif tool == "paint" then
		self.Brush, self.Hardness, self.Strength = 0.04, 1, 1
		self.KeepShading, self.PaintBlend = true, "normal"
	elseif tool == "erase" then
		self.Brush, self.Hardness, self.Strength = 0.04, 1, 1
		self.EraseMode = "revert"
		if IsValid( self.Canvas ) then self.Canvas.EraseMode = self.EraseMode end
	elseif tool == "fill" then
		self.Strength, self.KeepShading, self.PaintBlend = 1, true, "normal"
	elseif tool == "gradient" then
		self.Strength, self.GradientBlend = 1, "normal"
	elseif tool == "wand" then
		self.Tolerance, self.Contiguous = 0.1, true
	elseif tool == "box" or tool == "ellipse" or tool == "lasso" then
		self.Feather, self.Grow = 0, 0
		if tool == "box" and IsValid( self.Canvas ) then self.Canvas.Square = false end
	elseif tool == "island" then
		self.IslandGrow = 2
	elseif tool == "pick" then
		self.PickSize = 1
	end
	if IsValid( self.Canvas ) then
		self.Canvas.Brush = self.Brush
		self.Canvas.Hardness = self.Hardness
		self.Canvas.Tolerance = self.Tolerance
		self.Canvas.Contiguous = self.Contiguous
	end
	self:BuildOptions()
end

function PANEL:OpenShortcutHelp()
	local lines = {}
	for _, tool in ipairs( TOOLS ) do
		lines[ #lines + 1 ] = tool.shortcut .. "  -  " .. AdvMat.LText( tool.label )
	end
	lines[ #lines + 1 ] = "Shift+E  -  " .. AdvMat.LText( "Again on the eraser: switch Back to original / Make see-through" )
	lines[ #lines + 1 ] = "Alt  -  " .. AdvMat.LText( "While erasing: use the other eraser mode for that stroke" )
	lines[ #lines + 1 ] = "Ctrl+Z / Ctrl+Y  -  " .. AdvMat.LText( "Undo / Redo" )
	lines[ #lines + 1 ] = "Ctrl+A / Shift+Ctrl+A  -  " .. AdvMat.LText( "Select all / none" )
	lines[ #lines + 1 ] = "D / X  -  " .. AdvMat.LText( "Default / swap colours" )
	lines[ #lines + 1 ] = "Tab  -  " .. AdvMat.LText( "Toggle docks" )
	Derma_Message( table.concat( lines, "\n" ), AdvMat.LText( "Keyboard shortcuts" ),
		AdvMat.LText( "Close" ) )
end

local function ShortcutModifier( left, right )
	return input.IsKeyDown( left ) or input.IsKeyDown( right )
end

function PANEL:HandleShortcut( code )
	local focus = vgui.GetKeyboardFocus and vgui.GetKeyboardFocus() or nil
	if IsValid( focus ) and focus ~= self.Canvas then
		local class = focus.GetClassName and string.lower( focus:GetClassName() or "" ) or ""
		if string.find( class, "textentry", 1, true )
			or string.find( class, "numberwang", 1, true ) then return false end
	end

	local ctrl = ShortcutModifier( KEY_LCONTROL, KEY_RCONTROL )
	local shift = ShortcutModifier( KEY_LSHIFT, KEY_RSHIFT )

	if ctrl then
		if code == KEY_Z and shift then self:Redo() return true end
		if code == KEY_Z then self:Undo() return true end
		if code == KEY_Y then self:Redo() return true end
		if code == KEY_A then
			if shift then self:SetSelection( nil ) else self:SetSelection( SEL.All() ) end
			return true
		end
		if code == KEY_I then
			if not self.Sel then self:SetSelection( SEL.All() ) end
			local sel = table.Copy( self.Sel )
			sel.invert = not sel.invert
			self:SetSelection( sel )
			return true
		end
		return false
	end

	if code == KEY_TAB then self:SetDocksVisible( not self.DocksVisible ) return true end
	if code == KEY_D then self:DefaultColours() return true end
	if code == KEY_X then self:SwapColours() return true end
	if code == KEY_1 then
		self.Canvas.Zoom = 7
		self.Canvas.PanX = ( self.Canvas.SizeW - self.Canvas:GetWide() ) * 0.5
		self.Canvas.PanY = ( self.Canvas.SizeH - self.Canvas:GetTall() ) * 0.5
		return true
	end
	if code == KEY_2 then self.Canvas:FitToWindow() return true end
	if code == KEY_MINUS or code == KEY_PAD_MINUS then self.Canvas:ZoomBy( -1 ) return true end
	if code == KEY_EQUAL or code == KEY_PAD_PLUS then self.Canvas:ZoomBy( 1 ) return true end

	if code == KEY_P then self:SetTool( "island" ) return true end
	if code == KEY_R then self:SetTool( "box" ) return true end
	if code == KEY_E then
		-- Asking for the eraser while holding it switches what it does, so both
		-- of its jobs are one key apart.
		if shift and self.Tool == "erase" then
			self:SetEraseMode( self.EraseMode == "holes" and "revert" or "holes" )
		else
			self:SetTool( shift and "erase" or "ellipse" )
		end
		return true
	end
	if code == KEY_F then self:SetTool( "lasso" ) return true end
	if code == KEY_W then self:SetTool( "wand" ) return true end
	if code == KEY_B then self:SetTool( shift and "fill" or "paint" ) return true end
	if code == KEY_G then self:SetTool( "gradient" ) return true end
	if code == KEY_O then self:SetTool( "pick" ) return true end
	if code == KEY_H then self:SetTool( "pan" ) return true end
	if code == KEY_M then self:SetTool( "layer" ) return true end
	return false
end

function PANEL:OnKeyCodePressed( code )
	return self:HandleShortcut( code )
end

---------------------------------------------------------------------------
-- Canvas top bar
---------------------------------------------------------------------------
function PANEL:BuildCanvasBar( bar )
	local function Add( pnl )
		if bar.AddPanel then
			bar:AddPanel( pnl )
		else
			-- Kept as a harmless fallback for stripped-down Derma implementations.
			pnl:Dock( LEFT )
		end
	end

	local function Small( text, chars, tip, fn )
		local b = vgui.Create( "DButton", bar )
		-- The scroller can absorb the extra width, so size translated labels from
		-- their actual text instead of clipping them to an English character guess.
		b.AdvMatI18NAutoWidth = true
		b:SetWide( math.floor( AdvMat.FontSize * chars ) )
		b:SetText( text )
		if tip then b:SetTooltip( tip ) end
		b.DoClick = fn
		AdvMat.StyleButton( b )
		Add( b )
		return b
	end

	self.WorkspaceButtons = {}
	local function Workspace( id, text, tip )
		local b = Small( text, 6, tip, function() self:SetWorkspaceMode( id ) end )
		b.Paint = function( pnl, w, h )
			local on = self.WorkspaceMode == id
			local col = on and T.Selected or ( pnl:IsHovered() and T.HeaderHot or T.Header )
			surface.SetDrawColor( col.r, col.g, col.b, 255 )
			surface.DrawRect( 0, 0, w, h )
			surface.SetDrawColor( T.Line.r, T.Line.g, T.Line.b, 255 )
			surface.DrawOutlinedRect( 0, 0, w, h, 1 )
		end
		self.WorkspaceButtons[ id ] = b
		return b
	end

	Workspace( "texture", "Texture", "Show only the flat texture canvas." )
	Workspace( "split", "Split", "Show the texture and 3D preview together." )
	Workspace( "model", "3D preview", "Show only the model preview." )

	Small( "Fit", 3, "Zoom so the whole texture fits.", function()
		self.Canvas:FitToWindow()
	end )

	Small( "-", 2, "Zoom out", function() self.Canvas:ZoomBy( -1 ) end )
	Small( "+", 2, "Zoom in",  function() self.Canvas:ZoomBy(  1 ) end )

	self.ShowBtn = Small( SHOW_SELECTION[ 1 ].label, 12,
		"How the selection is drawn. The shading says which pixels are in it, " ..
		"the outline says exactly where its edge falls.",
		function() self:CycleSelectionDisplay() end )

	-- Painting on nothing is a different job from painting on the model's own
	-- texture, and both are wanted: one recolours what is there, the other
	-- makes a decal or a mask from scratch.
	self.StartBtn = Small( "Start from...", 10,
		"Paint over the existing texture, or start from a blank image.", function()
			self:OpenStartMenu()
		end )

	local uv = vgui.Create( "DCheckBoxLabel", bar )
	AdvMat.StyleCheck( uv, "Show the model's outlines" )
	uv:SetValue( self.ShowUVPref ~= false )
	uv:SetTooltip( "Draws the edges of the model's faces over the texture, so you can " ..
		"see which part of the picture goes where." )
	uv.OnChange = function( _, val )
		if not self.SettingUV then self:SetUVVisible( val ) end
	end
	self.UVCheck = uv
	Add( uv )

	-- The scroller places its panels only when it is laid out, but the
	-- localiser re-measures auto-width buttons every few frames - so when
	-- "Start from..." became "Start: the texture" it grew underneath the
	-- outline check box beside it. Lay the row out again whenever its panels'
	-- total width changes; the scroller's own Think still runs first.
	local scrollerThink = bar.Think
	bar.Think = function( pnl )
		if scrollerThink then scrollerThink( pnl ) end

		local total = 0
		for _, child in ipairs( pnl.Panels or {} ) do
			if IsValid( child ) then total = total + child:GetWide() end
		end

		if total ~= pnl.AdvMatPanelsWide then
			pnl.AdvMatPanelsWide = total
			pnl:InvalidateLayout()
		end
	end
end

function PANEL:OpenAreaMenu()
	local menu = DermaMenu()
	AdvMat.I18N.Track( menu )

	if self.Sel then
		menu:AddOption( "Keep this area...", function()
			Derma_StringRequest( AdvMat.L( "texture.keep_title" ),
				AdvMat.L( "texture.keep_prompt" ), AdvMat.L( "texture.keep_default" ), function( name )
				if not AdvMat.SaveArea( name, self.Sel ) then
					AdvMat.NotifyLocal( "Could not save that.", NOTIFY_ERROR, 4 )
					return
				end

				AdvMat.NotifyLocal( "Kept as " .. name, NOTIFY_GENERIC, 3 )
			end )
		end ):SetIcon( "icon16/disk.png" )
	else
		menu:AddOption( "Keep this area... (nothing is selected)", function() end ):SetDisabled( true )
	end

	local areas = AdvMat.ListAreas()

	if #areas > 0 then
		menu:AddSpacer()

		local use  = menu:AddSubMenu( "Use a kept area" )
		local wipe = menu:AddSubMenu( "Forget a kept area" )

		for _, name in ipairs( areas ) do
			use:AddOption( name, function()
				local sel = AdvMat.LoadArea( name )

				if not sel then
					AdvMat.NotifyLocal( "That area is unreadable.", NOTIFY_ERROR, 4 )
					return
				end

				self:SetSelection( sel )
			end )

			wipe:AddOption( name, function()
				AdvMat.DeleteArea( name )
				AdvMat.NotifyLocal( "Forgot " .. name, NOTIFY_GENERIC, 3 )
			end )
		end
	end

	menu:Open()
end

---------------------------------------------------------------------------
-- Canvas events
---------------------------------------------------------------------------
function PANEL:WireCanvas()
	local canvas = self.Canvas
	canvas:SetKeyboardInputEnabled( true )
	-- Say whether the key was used. Derma hands a key the focused panel did not
	-- claim on to its parent, and the parent here is this window, whose own
	-- OnKeyCodePressed runs the same shortcut: one Ctrl+Z undid two steps, and
	-- toggles (X, Tab, Ctrl+I, Shift+E) cancelled themselves out.
	canvas.OnKeyCodePressed = function( _, code ) return self:HandleShortcut( code ) end

	canvas.OnShape = function( _, shape )
		if SELECT_TOOLS[ self.Tool ] then self:PushShape( shape ) end
	end

	canvas.EraseMode = self.EraseMode

	-- A stroke is drawn under the pointer while it is made and becomes a step
	-- when the button is let go. See "Brush strokes" below.
	canvas.OnStrokeBegin = function( _, pts )
		self:BeginLiveStroke( pts )
	end

	canvas.OnStrokeMoved = function( _, pts )
		self:ExtendLiveStroke( pts )
	end

	canvas.OnStroke = function( _, pts, radius, hardness )
		self:CommitStroke( pts, radius, hardness )
	end

	canvas.OnGradient = function( _, x1, y1, x2, y2 )
		if self.RegionMode then return end
		local fg, bg = self.Colour, self.BackgroundColour
		self:AddStep( {
			op = "gradient", sel = self:StepSelection(),
			color1 = { fg.r, fg.g, fg.b, fg.a },
			color2 = { bg.r, bg.g, bg.b, bg.a },
			x1 = x1, y1 = y1, x2 = x2, y2 = y2,
			opacity = self.Strength or 1,
			blend = self.GradientBlend or "normal",
		} )
	end

	canvas.OnFill = function()
		self:DoFill()
	end

	canvas.OnPick = function( _, u, v )
		self:PickColour( u, v )
	end

	canvas.OnHover = function( _, u, v )
		self:HoverUV( u, v )
	end

	canvas.OnBrushWheel = function( _, delta )
		self.Brush = math.Clamp( ( self.Brush or 0.04 ) * ( delta > 0 and 1.25 or 0.8 ), 0.002, 0.5 )
		canvas.Brush = self.Brush
		self:BuildOptions()
	end

	canvas.OnLayerBegin = function()
		if not self.ActiveLayer then return end
		self:PushUndo( "Transform layer" )
		self.LayerDragging = true
	end

	canvas.OnLayerChanged = function()
		if not self.ActiveLayer then return end
		canvas:SetLayers( self.Recipe.layers )
		self:PushToModel()
	end

	canvas.OnLayerCommit = function( _, layer )
		if not self.ActiveLayer then return end
		self.LayerDragging = nil
		local clean = OPS.SanitizeLayer( layer )
		if clean then self.Recipe.layers[ self.ActiveLayer ] = clean end
		canvas:SetLayers( self.Recipe.layers )
		canvas:SetLayerTransform( self.Recipe.layers[ self.ActiveLayer ], self.LayerKeepAspect )
		self:RefreshLayers()
		self:BuildOptions()
		self:PushToModel()
	end
end

---------------------------------------------------------------------------
-- Brush strokes
---------------------------------------------------------------------------
-- A stroke is drawn onto the working image while the pointer moves (see
-- OPS.BeginStroke), so the brush and the eraser show what they do under the
-- cursor instead of a thin line that turns into a result on release. When the
-- button is let go the preview is put back and the real step is added in its
-- place: the recipe stays the one thing that decides the picture, and nothing
-- is ever applied twice.

local function AltHeld()
	return input and input.IsKeyDown
		and ( input.IsKeyDown( KEY_LALT ) or input.IsKeyDown( KEY_RALT ) ) or false
end

--- Which way the eraser works for a stroke starting now: the mode chosen in
--- the tool options, or the other one while Alt is held.
function PANEL:StrokeEraseMode()
	local mode = ( self.EraseMode == "holes" ) and "holes" or "revert"
	if AltHeld() then mode = ( mode == "holes" ) and "revert" or "holes" end
	return mode
end

function PANEL:SetEraseMode( mode )
	self.EraseMode = ( mode == "holes" ) and "holes" or "revert"
	if IsValid( self.Canvas ) then self.Canvas.EraseMode = self.EraseMode end
	if self.Tool == "erase" and IsValid( self.Opts ) then self:BuildOptions() end
end

--- The step a stroke along `pts` makes with `tool`: paint, or the eraser
--- working in `mode`.
function PANEL:StrokeOp( tool, pts, radius, hardness, mode )
	-- A stroke is a fill whose region is the stroke. That keeps the brush,
	-- the eraser and the paint bucket on one code path, and it means a
	-- stroke can be re-coloured afterwards like anything else.
	local sel = {
		shapes = { { t = "brush", pts = pts, r = radius,
			hardness = hardness or self.Hardness or 1, mode = "add" } },

		-- Clipped by the current selection, which is what makes "the rest
		-- is protected" true rather than a claim.
		--
		-- A clip rather than another shape in the list: the selection's own
		-- invert, grow and feather have to be resolved before the two are
		-- intersected, or painting inside an inverted selection would
		-- invert the brush stroke along with everything else.
		clip = self.Sel and table.Copy( self.Sel ) or nil,
	}

	if tool == "erase" then
		return { op = ( mode == "holes" ) and "erase" or "revert", sel = sel,
			opacity = self.Strength }
	end

	return self:PaintOp( sel )
end

--- The button has gone down with a brush tool: start drawing.
function PANEL:BeginLiveStroke( pts )
	self:CancelLiveStroke()

	local tool = self.Tool
	if self.RegionMode or ( tool ~= "paint" and tool ~= "erase" ) then return end

	-- Fixed for the length of the stroke: changing tools or letting go of Alt
	-- half way through does not turn the rest of it into something else.
	self.StrokeTool = tool
	self.StrokeMode = ( tool == "erase" ) and self:StrokeEraseMode() or nil
	if IsValid( self.Canvas ) then self.Canvas.StrokeMode = self.StrokeMode end

	-- Without a committed image there is nothing to draw onto, and an open
	-- adjustment owns the canvas. Those strokes are added on release, as
	-- every stroke used to be.
	if not self.Buf or self.StepPreviewOwner or self.ViewStep then return end

	-- The selection mask is borrowed rather than rasterised again, so it has
	-- to be the one made for this image; it is not while a resize is waiting
	-- for its source to be read.
	local clip = self.Sel and self.Mask or nil
	if clip and #clip ~= self.Buf.w * self.Buf.h then return end

	local op = OPS.Sanitize( self:StrokeOp( tool, pts, self.Brush or 0.04,
		self.Hardness or 1, self.StrokeMode ) )
	if not op or not OPS.IsStroke( op ) then return end

	-- The first edit that turns a source's shader mask into transparency
	-- rebuilds the image from the source with the mask flattened. No preview
	-- drawn over the current image can show that, so this one stroke appears
	-- when it is let go.
	if PreservesSourceMask( self.Recipe )
		and OPS.RepurposesSourceAlpha( { ops = { op } } ) then return end

	self.LiveStroke = OPS.BeginStroke( self.Buf, op, self:StepContext(), clip )
	if IsValid( self.Canvas ) then self.Canvas.LiveStroke = true end

	-- The model needs its see-through material before the step that asks
	-- for it exists, or the hole would only appear on release.
	if op.op == "erase" and not OPS.MakesTransparency( self.Recipe ) then
		self:PushToModel()
	end

	self:ExtendLiveStroke( pts )
end

--- The pointer has moved on: draw the new part of the stroke.
function PANEL:ExtendLiveStroke( pts )
	local stroke = self.LiveStroke
	if not stroke then return end

	stroke:Extend( pts )

	local x0, y0, x1, y1 = stroke:TakeDirty()
	if not x0 then return end

	self.Canvas:PatchRegion( x0, y0, x1, y1 )

	-- The vanilla model shows the canvas target itself, so it follows the
	-- stroke without being told. Remix needs a snapshot, which is coalesced.
	if RTXRenderContext( self.Ctx ) then self:QueueRTXPreviewSnapshot() end
end

--- Abandon the stroke being drawn. Its pixels are put back unless `stale`:
--- the image it was drawn on has already been replaced.
function PANEL:CancelLiveStroke( stale )
	local stroke = self.LiveStroke
	if not stroke then return end

	self.LiveStroke = nil
	if IsValid( self.Canvas ) then self.Canvas.LiveStroke = nil end
	if stale then return end

	local x0, y0, x1, y1 = stroke:Restore()
	if x0 then self.Canvas:PatchRegion( x0, y0, x1, y1 ) end
	if stroke.op.op == "erase" then self:PushToModel() end
end

--- The button has been let go: replace the preview with the real step.
function PANEL:CommitStroke( pts, radius, hardness )
	local tool, mode = self.StrokeTool or self.Tool, self.StrokeMode
	self.StrokeTool, self.StrokeMode = nil, nil
	if IsValid( self.Canvas ) then self.Canvas.StrokeMode = nil end

	local stroke = self.LiveStroke
	self.LiveStroke = nil
	if IsValid( self.Canvas ) then self.Canvas.LiveStroke = nil end

	if self.RegionMode or ( tool ~= "paint" and tool ~= "erase" ) then return end
	if tool == "erase" and not mode then mode = self:StrokeEraseMode() end

	-- Put the preview back first, so the step applies to the image exactly
	-- as it was before the stroke.
	local shown

	if stroke then
		shown = { stroke:Restore() }

		-- A stroke that changed nothing is not worth a step, but it is worth an
		-- explanation: an eraser that silently does nothing is the most
		-- confusing thing an eraser can do.
		if not stroke.changed then
			if stroke.op.op == "erase" then self:PushToModel() end
			self:ExplainEmptyStroke( stroke )
			return
		end
	end

	local compact = SEL.CompactStroke( pts, self.WorkW, self.WorkH, STROKE_TOLERANCE )
	local added = self:AddStep( self:StrokeOp( tool, compact, radius, hardness, mode ), shown )

	-- Refused, by a limit most likely: what the preview drew must go too.
	if not added and shown and shown[ 1 ] then
		self.Canvas:PatchRegion( shown[ 1 ], shown[ 2 ], shown[ 3 ], shown[ 4 ] )
		if stroke and stroke.op.op == "erase" then self:PushToModel() end
	end
end

--- Why a stroke did nothing, when there is something useful to say.
function PANEL:ExplainEmptyStroke( stroke )
	if not stroke.covered then return end

	if not stroke.reached then
		self:Status( "Nothing changed: the brush only works inside the selection. " ..
			"Press Ctrl+Shift+A to select nothing.", true )
	elseif stroke.op.op == "revert" then
		self:Status( "Nothing to rub out there - it already matches the original " ..
			"texture. To cut a hole instead, switch the eraser to Make see-through, " ..
			"or hold Alt.", true )
	elseif stroke.op.op == "erase" then
		self:Status( "Nothing changed - that part is already see-through.", true )
	end
end

---------------------------------------------------------------------------
-- What one save can carry
---------------------------------------------------------------------------
-- A save sends the recipe to the server in one network message, compressed,
-- and anything over the asset layer's ceiling (AdvMat.Assets.MAX_META_BYTES)
-- is refused. Once brush strokes stopped counting against the step limit, that
-- became the real limit on how much painting one texture can hold, so the
-- editor keeps track of it as it goes and says so when a step would not fit -
-- rather than leaving Save to fail after an hour of painting.

-- Room kept back in that message for the rest of the rule: the material's
-- own parameters, and any other texture generated for it.
local WIRE_HEADROOM = 4000

local function WireLimit()
	-- Read through an alias, as the asset modules themselves do: the constant
	-- is defined as A.MAX_META_BYTES in sh_45_assets.lua.
	local assets = AdvMat.Assets
	local ceiling = assets and tonumber( assets.MAX_META_BYTES ) or 60000
	return math.max( ceiling - WIRE_HEADROOM, 1024 )
end

--- The recipe's size the way a save sends it: sanitised, as JSON, compressed.
--- Nil where that cannot be measured.
local function MeasureRecipe( recipe )
	if not ( util and util.TableToJSON and util.Compress ) then return nil end

	local clean = AdvMat.Gen.Sanitize( recipe )
	if not clean then return 0 end

	local packed = util.Compress( util.TableToJSON( clean ) or "" )
	return isstring( packed ) and #packed or nil
end

--- Whether the recipe still fits in one save with `clean` added.
---
--- Compressing a large recipe takes long enough to be felt, so it is not done
--- for every stroke. A running figure is kept instead - each step adds a
--- pessimistic guess at its own size - and only near the line is the recipe
--- measured exactly, with the step in place.
function PANEL:WireRoomFor( clean )
	if not self.WireBytes then self.WireBytes = MeasureRecipe( self.Recipe ) end

	local limit = WireLimit()
	local bytes = self.WireBytes
	if not bytes or bytes < limit * 0.85 then return true end

	local ops = self.Recipe.ops
	ops[ #ops + 1 ] = clean
	local exact = MeasureRecipe( self.Recipe )
	ops[ #ops ] = nil

	if not exact then return true end
	if exact > limit then return false end

	-- Measured with the step already in it; NoteStepBytes must not add it on.
	self.WireBytes, self.WireMeasured = exact, clean
	return true
end

--- Account for a step that has just been added.
function PANEL:NoteStepBytes( clean )
	if self.WireMeasured == clean then
		self.WireMeasured = nil
		return
	end

	self.WireMeasured = nil
	if not ( util and util.TableToJSON ) or not self.WireBytes then return end

	-- Half the step's own JSON: more than it costs inside a recipe that
	-- compresses as a whole, so the guess errs towards measuring early.
	self.WireBytes = self.WireBytes + math.ceil( #( util.TableToJSON( clean ) or "" ) * 0.5 )
end

--- Measure again once editing pauses, to replace the running guess with the
--- real figure the Effects list shows.
function PANEL:ScheduleWireMeasure()
	if not ( timer and timer.Create ) then return end

	timer.Create( "AdvMat.WireMeasure." .. tostring( self ), 1.5, 1, function()
		if not IsValid( self ) then return end
		self.WireBytes = MeasureRecipe( self.Recipe )
		self:RefreshStepSummary()
	end )
end

--- The step a paint or fill action produces, honouring "keep the shading".
function PANEL:PaintOp( sel )
	-- A source-less image starts from one flat fill colour. There is no original
	-- lighting information for a tint to preserve, and preserving its HSV value
	-- makes black paint over a white blank evaluate straight back to white. Use
	-- ordinary paint for blank/generated maps; keep the recolouring behaviour
	-- for real source textures, where light and shadow actually exist.
	local source = self.Recipe and self.Recipe.src
	if self.KeepShading and source and source ~= "" then
		-- Tint keeps the pixel's own brightness and only moves its colour,
		-- which is the difference between "the jacket is red now" and "there
		-- is a red sticker where the jacket was".
		return {
			op = "tint", sel = sel,
			color = { self.Colour.r, self.Colour.g, self.Colour.b, self.Colour.a },
			amount = self.Strength,
			keepvalue = true,
			paintalpha = true,
			scalevalue = true,
		}
	end

	return {
		op = "fill", sel = sel,
		color = { self.Colour.r, self.Colour.g, self.Colour.b, self.Colour.a },
		opacity = self.Strength,
		blend = self.PaintBlend or "normal",
	}
end

function PANEL:DoFill()
	local sel = self:StepSelection()

	if not sel then
		self:Status( "Nothing is selected, so this would fill the whole texture. " ..
			"Pick a piece of the model first, or press Select all if that is what you want.", true )
		return
	end

	self:AddStep( self:PaintOp( sel ) )
end

--- Sample the TEXTURE, never the rendered model. A pixel read off the 3D view
--- has already been through lighting, ambient and any $color tint, so picking
--- from it and painting the result back never matches.
function PANEL:PickColour( u, v )
	if not self.Buf then return end

	local sw, sh = self.WorkW, self.WorkH
	local cx = math.Clamp( math.floor( u * sw ), 0, sw - 1 )
	local cy = math.Clamp( math.floor( v * sh ), 0, sh - 1 )

	-- A 3x3 average by default: source art is DXT compressed, so a single
	-- pixel off a flat surface routinely reads a few percent out.
	local r, g, b, a, n = 0, 0, 0, 0, 0
	local rad = self.PickSize or 1

	for oy = -rad, rad do
		for ox = -rad, rad do
			local x = math.Clamp( cx + ox, 0, sw - 1 )
			local y = math.Clamp( cy + oy, 0, sh - 1 )
			local i = y * sw + x + 1

			r, g, b, a = r + self.Buf.r[ i ], g + self.Buf.g[ i ],
			             b + self.Buf.b[ i ], a + self.Buf.a[ i ]
			n = n + 1
		end
	end

	self.Colour = Color( math.floor( r / n + 0.5 ), math.floor( g / n + 0.5 ),
		math.floor( b / n + 0.5 ), math.floor( a / n + 0.5 ) )

	self:RefreshColourLabel()
end

function PANEL:RefreshColourLabel()
	if IsValid( self.ColourLabel ) then
		self.ColourLabel:SetText( AdvMat.L( "texture.foreground_short", {
			colour = ColourName( self.Colour ),
		} ) .. "\n" .. AdvMat.L( "texture.background_short", {
			colour = ColourName( self.BackgroundColour ),
		} ) )
	end
	if IsValid( self.FGSwatch ) then self.FGSwatch:InvalidateLayout() end
	if IsValid( self.BGSwatch ) then self.BGSwatch:InvalidateLayout() end
end

function PANEL:OpenColourPicker( target )
	target = target == "background" and "background" or "foreground"
	local current = target == "background" and self.BackgroundColour or self.Colour
	local frame = vgui.Create( "DFrame" )
	frame.AdvMatHost = self
	frame:SetSize( 280, 300 )
	frame:SetTitle( target == "background" and "Background colour" or "Foreground colour" )
	frame:Center()
	frame:MakePopup()
	AdvMat.StyleFrame( frame )
	if AdvMat.WindowUX then AdvMat.WindowUX.PlaceChild( frame, self, false ) end

	local mixer = vgui.Create( "DColorMixer", frame )
	mixer:Dock( FILL )
	mixer:SetPalette( true )
	mixer:SetAlphaBar( true )
	mixer:SetColor( current )

	mixer.ValueChanged = function( _, col )
		if target == "background" then
			self.BackgroundColour = Color( col.r, col.g, col.b, col.a )
		else
			self.Colour = Color( col.r, col.g, col.b, col.a )
		end
		self:RefreshColourLabel()
	end
end

---------------------------------------------------------------------------
-- The model preview
---------------------------------------------------------------------------
function PANEL:WireModelPanel()
	local mp = self.ModelPanel

	mp:SetFOV( 40 )
	mp:SetAnimated( false )

	-- No spin. You cannot click a moving target, and in this editor the model
	-- is the primary way to select things.
	--
	-- The one thing allowed to move it is an animation the user asked for, and
	-- that is stepped here rather than through SetAnimated so that stopping
	-- leaves the pose exactly where it was instead of running on.
	mp.LayoutEntity = function() AdvMat.ModelView.Advance( self ) end

	mp.Think = function()
		if not self.Framed then self:FrameModel() end
	end

	mp.PreDrawModel = function( _, ent )
		AdvMat.ModelView.BeginRTXDraw( self, ent )
	end

	mp.PostDrawModel = function( _, ent )
		AdvMat.ModelView.EndRTXDraw( self )
		if not self.HighlightMesh then return end
		AdvMat.Mesh.DrawHighlight( self.HighlightMesh, Color( 90, 210, 255, 150 ) )
	end

	mp.OnCursorMoved = function( pnl, mx, my )
		if pnl.Dragging then
			local dx, dy = mx - pnl.DragX, my - pnl.DragY

			if pnl.Dragging == "pan" then
				-- Handed both ends rather than a delta: the drag is worked out
				-- from where the two rays cross the plane the pivot sits on,
				-- which needs the actual points and not how far apart they are.
				self:PanCamera( pnl.DragX, pnl.DragY, mx, my )
			else
				self.Yaw   = ( self.Yaw or 0 ) - dx * 0.5
				self.Pitch = math.Clamp( ( self.Pitch or 15 ) + dy * 0.5, -80, 80 )
				self:PlaceCamera()
			end

			pnl.DragX, pnl.DragY = mx, my
			pnl.DragMoved = ( pnl.DragMoved or 0 ) + math.abs( dx ) + math.abs( dy )
			return
		end

		self:HoverModel()
	end

	mp.OnMousePressed = function( pnl, code )
		pnl:MouseCapture( true )

		pnl.DragX, pnl.DragY = pnl:CursorPos()
		pnl.DragMoved = 0

		-- Middle mouse moves the view on the canvas, so it moves the view here
		-- too. Right mouse has nothing to be consistent with on a model and is
		-- the obvious home for turning it.
		if code == MOUSE_MIDDLE or ( code == MOUSE_LEFT and self.Tool == "pan" ) then
			pnl.Dragging = "pan"
			return
		end

		if code == MOUSE_RIGHT then
			pnl.Dragging = "orbit"
			return
		end

		self:ClickModel()
	end

	mp.OnMouseReleased = function( pnl, code )
		pnl:MouseCapture( false )

		-- A middle click that never became a drag is a request to look at what
		-- is under the cursor, which is the way out of an orbit that is
		-- turning around the wrong place.
		if pnl.Dragging == "pan" and code == MOUSE_MIDDLE
			and ( pnl.DragMoved or 0 ) < 4 then
			self:CentreOnCursor()
		end

		pnl.Dragging = nil
	end

	mp.OnMouseWheeled = function( _, delta )
		self.CamDist = math.Clamp( ( self.CamDist or 60 ) * ( delta > 0 and 0.85 or 1.18 ), 4, 4000 )
		self:PlaceCamera()
		return true
	end
end

--- Point the camera at the model and pull back far enough to see all of it.
---
--- Render bounds are (0,0,0) until the model has actually loaded, and SetModel
--- returns before that has happened, so framing once during Setup lands on a
--- zero-sized model and leaves the camera inside it. This keeps asking until
--- the bounds are real, which is normally the very next frame.
function PANEL:FrameModel()
	local mp = self.ModelPanel
	if not IsValid( mp ) then return true end

	local ent = mp.Entity
	if not IsValid( ent ) then return false end

	-- Render bounds are (0,0,0) until the model has actually loaded, and
	-- SetModel returns before that has happened. Nothing reports it, so this
	-- just keeps asking until they are real.
	local rmn, rmx = ent:GetRenderBounds()
	if math.max( rmx.x - rmn.x, rmx.y - rmn.y, rmx.z - rmn.z ) <= 0.01 then return false end

	-- The skinned positions are built HERE rather than in Setup, and this is
	-- the whole reason FrameModel retries.
	--
	-- Bones do not exist until the model has loaded either, and skinning
	-- without them does not fail - WorldPositions quietly falls back to the
	-- bind pose. The model is then drawn in its reference pose, so a ray fired
	-- at the ear is tested against geometry that is somewhere else entirely and
	-- selects whatever piece happens to be there instead.
	local world, skinned = AdvMat.Mesh.WorldPositions( ent, self.Group, self.Ctx.model )
	self.World = world

	-- Bones can still be missing for a frame or two after the bounds are real.
	-- Framing on the bind pose is fine; picking against it is not, so this asks
	-- again - a bounded number of times, in case a model never reports any.
	self.SkinTries = ( self.SkinTries or 0 ) + 1

	if not skinned and self.SkinTries < 30 then return false end

	local mn, mx

	-- Framed on the sub-material's own geometry when we know where it is. On a
	-- character whose slot is just the head, framing the whole body leaves the
	-- part you are here to click a few pixels across.
	--
	-- FramingBounds rather than a plain box, because a converted model often
	-- has a stray triangle assigned to the wrong material and a plain box
	-- around one of those centres the view on empty space.
	if self.World and #self.World > 0 then
		mn, mx = AdvMat.Mesh.FramingBounds( self.World )
	end

	if not mn then mn, mx = rmn, rmx end

	local extent = math.max( mx.x - mn.x, mx.y - mn.y, mx.z - mn.z, 1 )

	self.Centre  = ( mn + mx ) * 0.5
	self.CamDist = extent * 1.6
	self.Framed  = true

	self:PlaceCamera()
	return true
end

--- The point the camera turns around and looks at.
---
--- Everything the view does is defined against this one point: turning swings
--- around it, the wheel moves towards and away from it, and dragging moves it
--- sideways. Until the model has loaded well enough to be measured, the middle
--- of its render bounds stands in.
function PANEL:PivotPoint()
	if self.Centre then return self.Centre end

	local mp = self.ModelPanel
	if not IsValid( mp ) or not IsValid( mp.Entity ) then return nil end

	local mn, mx = mp.Entity:GetRenderBounds()
	return ( mn + mx ) * 0.5
end

function PANEL:PlaceCamera()
	local mp = self.ModelPanel
	if not IsValid( mp ) or not IsValid( mp.Entity ) then return end

	local centre = self:PivotPoint()
	if not centre then return end

	local ang = Angle( self.Pitch or 15, self.Yaw or 0, 0 )
	local pos = centre - ang:Forward() * ( self.CamDist or 60 )

	mp:SetCamPos( pos )
	mp:SetLookAt( centre )
end

--- Drag the model about the view.
---
--- The pivot moves, not the camera on its own - so what has been dragged into
--- the middle is then what turning goes around, and the two do not fight.
---
--- The distance is worked out by asking where the ray under the cursor crossed
--- the plane the pivot sits on, at each end of the drag. Doing it that way
--- rather than scaling pixels by the field of view means the model keeps up
--- with the cursor exactly, at any zoom, without this having to know anything
--- about how the panel sets its camera up.
function PANEL:PanCamera( fromX, fromY, toX, toY )
	local mp = self.ModelPanel
	if not IsValid( mp ) then return end

	local centre = self:PivotPoint()
	if not centre then return end

	local o0, d0 = AdvMat.Mesh.PanelRayAt( mp, fromX, fromY )
	local o1, d1 = AdvMat.Mesh.PanelRayAt( mp, toX, toY )
	if not o0 or not o1 then return end

	-- The plane faces the camera, so it is the one plane on which a pixel is
	-- worth the same everywhere.
	local facing = centre - o0
	if facing:LengthSqr() < 1e-6 then return end

	facing:Normalize()

	local p0 = AdvMat.Mesh.RayPlane( o0, d0, centre, facing )
	local p1 = AdvMat.Mesh.RayPlane( o1, d1, centre, facing )
	if not p0 or not p1 then return end

	self.Centre = centre + ( p0 - p1 )
	self:PlaceCamera()
end

--- Put whatever is under the cursor in the middle of the view, and turn around
--- that from now on.
function PANEL:CentreOnCursor()
	local mp = self.ModelPanel
	if not IsValid( mp ) or not IsValid( mp.Entity ) then return end

	local origin, dir = AdvMat.Mesh.PanelRay( mp )
	if not origin then return end

	-- The exact point on the surface when the ray lands on the material being
	-- edited. That geometry is already skinned, so being precise about it costs
	-- nothing.
	local group = self.Group

	if group then
		if not self.World then
			self.World = AdvMat.Mesh.WorldPositions( mp.Entity, group, self.Ctx.model )
		end

		local tri, _, _, dist = AdvMat.Mesh.Pick( group, self.World, origin, dir )

		if tri and dist then
			self.Centre = origin + dir * dist
			self:PlaceCamera()
			return
		end
	end

	-- Anywhere else - a different material, a different part, or past the model
	-- altogether - there is no geometry here to measure against. Rays are only
	-- ever fired at the one sub-material being edited, and skinning a whole
	-- character to answer a click is not worth it.
	--
	-- So the fallback is the point the cursor picks out on the plane the pivot
	-- already sits on. That keeps the click meaning one thing everywhere -
	-- what you pointed at moves to the middle - instead of working on the face
	-- and doing nothing on the chest, and it is exact for anything at roughly
	-- the pivot's depth, which on a character is most of it.
	local centre = self:PivotPoint()
	if not centre then return end

	local facing = centre - origin
	if facing:LengthSqr() < 1e-6 then return end

	facing:Normalize()

	local hit = AdvMat.Mesh.RayPlane( origin, dir, centre, facing )
	if not hit then return end

	self.Centre = hit
	self:PlaceCamera()
end

--- Back to how the view started: framed on the material being edited, from the
--- front, at whatever distance holds all of it.
---
--- Framing runs from Think rather than here, because it needs geometry that
--- has been skinned to the pose the model is actually in, and after parts have
--- been hidden or an animation moved it, that is not what was skinned before.
function PANEL:ResetView()
	self.Framed    = false
	self.SkinTries = 0
	self.Centre    = nil
	self.Yaw       = 180
	self.Pitch     = 10

	self:PoseChanged()
end

--- The model has moved, so everything worked out from where its vertices were
--- is now wrong.
---
--- Nothing is recomputed here. Skinning a character is thousands of matrix
--- multiplies and the pose may well change again next frame, so the work is
--- left to whoever asks next - a hover or a click - and is then done once for
--- that pose rather than once per frame.
function PANEL:PoseChanged()
	self.World = nil

	if self.HighlightMesh then
		self.HighlightMesh:Destroy()
		self.HighlightMesh = nil
	end

	-- Cleared as well as destroyed, or the next hover over the same piece sees
	-- no change and never rebuilds the mesh it has just thrown away.
	self.HighlightIsland = nil
end

--- Re-read the model geometry for the parts that are currently shown, and
--- point the canvas and the picker at it.
---
--- Returns false when the material being edited is no longer in the model,
--- which is what happens when the part carrying it has just been hidden. The
--- caller is expected to put that part back: an editor whose sheet has no
--- outline and whose model cannot be clicked is worse than one that refuses.
function PANEL:RebuildGroup()
	local ctx = self.Ctx
	if not ctx or not ctx.model or ctx.model == "" then return true end

	local mp   = self.ModelPanel
	local mask = IsValid( mp ) and AdvMat.Mesh.BodyMask( mp.Entity ) or 0

	local group = AdvMat.Mesh.Group( ctx.model, ctx.matpath, ctx.slot or 0, mask )

	-- Compared on the material rather than on "did we get anything back":
	-- hiding a part renumbers the mesh list, so the slot fallback inside Group
	-- can hand back another material's geometry and be perfectly happy.
	if self.Group and ( not group or group.material ~= self.Group.material ) then
		return false
	end

	-- Dropped before the group is swapped, not after: the canvas is holding
	-- triangles out of the old geometry, and once self.Group has been replaced
	-- there is no longer anything that agrees they existed.
	self:SetHighlightTriangle( nil )

	self.BodyMask = mask
	self.Group    = group

	self.Canvas:SetUVSource( ctx.model, ctx.matpath, ctx.slot or 0, mask )
	self:PoseChanged()

	return true
end

--- Where the cursor is pointing on the model, as a UV coordinate.
function PANEL:ModelHitUV()
	local mp = self.ModelPanel
	if not IsValid( mp ) or not IsValid( mp.Entity ) then return nil end

	local group = self.Group
	if not group then return nil end

	local origin, dir = AdvMat.Mesh.PanelRay( mp )
	if not origin then return nil end

	-- Skinning every vertex is only worth doing when the pose could have
	-- changed, so it is kept until PoseChanged throws it away rather than
	-- being worked out again here.
	if not self.World then
		self.World = AdvMat.Mesh.WorldPositions( mp.Entity, group, self.Ctx.model )
	end

	local tri, u, v = AdvMat.Mesh.Pick( group, self.World, origin, dir )
	if not tri then return nil end

	local tu, tv = AdvMat.Mesh.HitUV( tri, u, v )
	return tu, tv, tri
end

function PANEL:HoverModel()
	-- A playing animation moves every vertex every frame, and re-skinning the
	-- whole mesh to answer "what is under the cursor" at that rate is not
	-- affordable on a character. Clicking still works: it stops first.
	if self.Anim and self.Anim.playing then return end

	local _, _, tri = self:ModelHitUV()
	self:SetHighlightTriangle( tri )
end

function PANEL:ClickModel()
	-- Stopping does not move the model, so the pose the ray is fired at is the
	-- one that was on screen at the moment of the click.
	if self.Anim and self.Anim.playing then
		AdvMat.ModelView.Play( self, false )
	end

	local u, v, tri = self:ModelHitUV()
	if not u then return end

	if self.Tool == "pick" then
		self:PickColour( u, v )
		return
	end

	if SELECT_TOOLS[ self.Tool ] or self.Tool == "island" then
		self:PushShape( { t = "uvisland", x = u, y = v, mode = self.Canvas:CurrentMode() } )
		self:SetHighlightTriangle( tri )
	end
end

--- Light up the piece under the cursor in the 3D view, so hovering tells you
--- what a click would select before you commit to it.
function PANEL:SetHighlightTriangle( tri )
	local id = tri and self.Group and self.Group.island[ tri[ 7 ] ] or nil

	if id == self.HighlightIsland then return end
	self.HighlightIsland = id

	-- The canvas outlines the same piece, so hovering the model shows you where
	-- on the flat sheet a click would land and hovering the sheet shows you
	-- where on the model.
	self.Canvas:SetHover( id and self.Group and self.Group.islands[ id ] or nil )

	if self.HighlightMesh then
		self.HighlightMesh:Destroy()
		self.HighlightMesh = nil
	end

	if not id or not self.World then return end

	self.HighlightMesh = AdvMat.Mesh.BuildHighlight( self.Group.islands[ id ], self.World )
end

--- Hovering the flat texture lights up the matching piece on the model, which
--- is the same relationship read the other way round.
function PANEL:HoverUV( u, v )
	if IsValid( self.PixelStatus ) then
		if u == nil or v == nil or not self.Buf then
			self.PixelStatus:SetText( "x: --  y: --  RGBA: --" )
		else
			local x = math.Clamp( math.floor( u * self.WorkW ), 0, self.WorkW - 1 )
			local y = math.Clamp( math.floor( v * self.WorkH ), 0, self.WorkH - 1 )
			local i = y * self.WorkW + x + 1
			self.PixelStatus:SetText( string.format( "x: %d  y: %d  RGBA: %d,%d,%d,%d",
				math.floor( u * ( self.Recipe.size or self.WorkW ) ),
				math.floor( v * ( self.Recipe.height or self.Recipe.size or self.WorkH ) ),
				self.Buf.r[ i ] or 0, self.Buf.g[ i ] or 0,
				self.Buf.b[ i ] or 0, self.Buf.a[ i ] or 0 ) )
		end
	end

	if not self.Group or u == nil or v == nil then
		self:SetHighlightTriangle( nil )
		return
	end

	local tri = AdvMat.Mesh.TriangleAt( self.Group, u, v )
	self:SetHighlightTriangle( tri )
end

---------------------------------------------------------------------------
-- Imported texture layers
---------------------------------------------------------------------------
function PANEL:ResolveLayerSource( raw )
	local path = OPS.TexturePath( raw )
	if not path then return nil end

	if file.Exists( "materials/" .. path .. ".vtf", "GAME" ) then return path end

	-- The shared picker also exposes VMTs. A layer needs the image they point
	-- at, not the VMT name placed into another material's $basetexture slot.
	if file.Exists( "materials/" .. path .. ".vmt", "GAME" ) then
		local mat = Material( path )
		local ok, base = pcall( function()
			return mat and not mat:IsError() and mat:GetString( "$basetexture" ) or nil
		end )
		if ok then
			local resolved = OPS.TexturePath( base )
			-- A VMT may point at a live render target. Layers must resolve to a
			-- mounted image so their saved recipe is stable and replayable.
			if resolved and file.Exists( "materials/" .. resolved .. ".vtf", "GAME" ) then
				return resolved
			end
		end
	end

	return nil
end

function PANEL:FitLayer( layer )
	local rw, rh = AdvMat.Gen.Dims( self.Recipe )
	local sw, sh = AdvMat.Gen.SourceSize( layer.src, rw, rh )
	local scale = math.min( 1, rw / math.max( sw, 1 ), rh / math.max( sh, 1 ) )
	layer.w = math.max( 0.002, sw * scale / rw )
	layer.h = math.max( 0.002, sh * scale / rh )
end

function PANEL:SelectLayer( index )
	local layers = self.Recipe.layers or {}
	if not index or not layers[ index ] then
		self.ActiveLayer = nil
		self.Canvas:SetLayerTransform( nil )
		if self.Tool == "layer" then self:SetTool( "island" ) end
		self:RefreshLayers()
		return
	end

	self.ActiveLayer = index
	self.Canvas:SetLayerTransform( layers[ index ], self.LayerKeepAspect )
	if self.Tool ~= "layer" then self:SetTool( "layer" ) else self:BuildOptions() end
	self:RefreshLayers()
end

function PANEL:AddLayer( raw )
	self.Recipe.layers = self.Recipe.layers or {}
	if #self.Recipe.layers >= OPS.MAX_LAYERS then
		self:Status( AdvMat.LText( "That is as many imported layers as one texture can hold." ), true )
		return
	end

	local src = self:ResolveLayerSource( raw )
	if not src then
		self:Status( AdvMat.LText( "That texture could not be opened as a shared image layer." ), true )
		return
	end

	local layer = { src = src, x = 0.5, y = 0.5, opacity = 1 }
	self:FitLayer( layer )
	layer = OPS.SanitizeLayer( layer )
	if not layer then return end

	self:PushUndo( "Import layer" )
	self.Recipe.layers[ #self.Recipe.layers + 1 ] = layer
	self.Canvas:SetLayers( self.Recipe.layers )
	self:SelectLayer( #self.Recipe.layers )
	self:PushToModel()
end

function PANEL:ImportLayer()
	AdvMat.OpenTexturePicker( "", function( path )
		if IsValid( self ) and path ~= "" then self:AddLayer( path ) end
	end, self.Recipe.src )
end

function PANEL:ChangeLayerSource()
	local at = self.ActiveLayer
	local layer = at and self.Recipe.layers[ at ]
	if not layer then return end

	AdvMat.OpenTexturePicker( layer.src, function( path )
		if not IsValid( self ) or path == "" then return end
		-- The picker is a separate window. Keep ownership with the layer that
		-- opened it even if another row was selected before the choice returned.
		local target = self.Recipe.layers and self.Recipe.layers[ at ]
		if target ~= layer then return end
		local src = self:ResolveLayerSource( path )
		if not src then
			self:Status( AdvMat.LText( "That texture could not be opened as a shared image layer." ), true )
			return
		end

		self:PushUndo( "Change layer source" )
		target.src = src
		if self.LayerKeepAspect then
			local rw, rh = AdvMat.Gen.Dims( self.Recipe )
			local sw, sh = AdvMat.Gen.SourceSize( src, rw, rh )
			target.h = math.Clamp( target.w * rw * sh / math.max( sw * rh, 1 ), 0.002, 4 )
		end
		self.Recipe.layers[ at ] = OPS.SanitizeLayer( target )
		self.Canvas:SetLayers( self.Recipe.layers )
		if self.ActiveLayer == at then
			self.Canvas:SetLayerTransform( self.Recipe.layers[ at ], self.LayerKeepAspect )
		end
		self:RefreshLayers()
		self:BuildOptions()
		self:PushToModel()
	end, self.Recipe.src )
end

function PANEL:DuplicateLayer()
	local layer = self.ActiveLayer and self.Recipe.layers[ self.ActiveLayer ]
	if not layer then return end
	if #self.Recipe.layers >= OPS.MAX_LAYERS then
		self:Status( AdvMat.LText( "That is as many imported layers as one texture can hold." ), true )
		return
	end

	self:PushUndo( "Duplicate layer" )
	local copy = table.Copy( layer )
	copy.x, copy.y = math.min( 3, copy.x + 0.03 ), math.min( 3, copy.y + 0.03 )
	table.insert( self.Recipe.layers, self.ActiveLayer + 1, OPS.SanitizeLayer( copy ) )
	self.Canvas:SetLayers( self.Recipe.layers )
	self:SelectLayer( self.ActiveLayer + 1 )
	self:PushToModel()
end

function PANEL:MoveLayer( delta )
	local at = self.ActiveLayer
	local layers = self.Recipe.layers or {}
	local to = at and math.Clamp( at + delta, 1, #layers ) or nil
	if not at or to == at then return end

	self:PushUndo( delta > 0 and "Raise layer" or "Lower layer" )
	layers[ at ], layers[ to ] = layers[ to ], layers[ at ]
	self.ActiveLayer = to
	self.Canvas:SetLayers( layers )
	self.Canvas:SetLayerTransform( layers[ to ], self.LayerKeepAspect )
	self:RefreshLayers()
	self:PushToModel()
end

function PANEL:DeleteLayer()
	local at = self.ActiveLayer
	if not at or not self.Recipe.layers[ at ] then return end

	self:PushUndo( "Delete layer" )
	table.remove( self.Recipe.layers, at )
	self.ActiveLayer = math.min( at, #self.Recipe.layers )
	if self.ActiveLayer == 0 then self.ActiveLayer = nil end
	self.Canvas:SetLayers( self.Recipe.layers )
	self.Canvas:SetLayerTransform( self.ActiveLayer and self.Recipe.layers[ self.ActiveLayer ] or nil,
		self.LayerKeepAspect )
	self:RefreshLayers()
	self:BuildOptions()
	self:PushToModel()
end

function PANEL:BeginLayerControl()
	if not self.LayerControlOpen then
		self:PushUndo( "Edit layer" )
		self.LayerControlOpen = true
	end

	local name = "AdvMat.LayerControl." .. tostring( self )
	timer.Create( name, 0.35, 1, function()
		if IsValid( self ) then self.LayerControlOpen = nil end
	end )
end

function PANEL:EditLayer( fn )
	local at = self.ActiveLayer
	local layer = at and self.Recipe.layers[ at ]
	if not layer or self.BuildingLayerOptions then return end

	self:BeginLayerControl()
	fn( layer )
	local clean = OPS.SanitizeLayer( layer )
	if not clean then return end
	self.Recipe.layers[ at ] = clean
	self.Canvas:SetLayers( self.Recipe.layers )
	self.Canvas:SetLayerTransform( clean, self.LayerKeepAspect )
	self:PushToModel()

	local name = "AdvMat.LayerList." .. tostring( self )
	timer.Create( name, 0.08, 1, function()
		if IsValid( self ) then self:RefreshLayers() end
	end )
end

function PANEL:BuildLayerActions()
	local bar = self.LayerActions
	if not IsValid( bar ) then return end
	self.LayerActionButtons = {}

	local function Add( id, text, tip, fn )
		local b = vgui.Create( "DButton", bar )
		b:SetSize( AdvMat.RowHeight() + 10, AdvMat.RowHeight() + 4 )
		b:SetText( text )
		b:SetTooltip( tip )
		b.DoClick = fn
		AdvMat.StyleButton( b, id == "delete" )
		bar:AddPanel( b )
		self.LayerActionButtons[ id ] = b
	end

	Add( "import", "+", "Import a mounted texture as a new layer", function() self:ImportLayer() end )
	Add( "duplicate", "D", "Duplicate the selected layer", function() self:DuplicateLayer() end )
	Add( "up", "^", "Move the selected layer up", function() self:MoveLayer( 1 ) end )
	Add( "down", "v", "Move the selected layer down", function() self:MoveLayer( -1 ) end )
	Add( "delete", "x", "Delete the selected layer", function() self:DeleteLayer() end )
end

function PANEL:RefreshLayers()
	if not IsValid( self.Layers ) then return end
	self.Layers:Clear()

	local layers = self.Recipe.layers or {}
	local rowH = AdvMat.RowHeight() + 8

	-- Draw last first: later layers are composited on top, matching the visual
	-- order people expect from GIMP and similar editors.
	for i = #layers, 1, -1 do
		local layer = layers[ i ]
		local row = self.Layers:Add( "DPanel" )
		row:Dock( TOP )
		row:SetTall( rowH )
		row:DockMargin( 0, 0, 3, 1 )
		row.Paint = function( pnl, w, h )
			local col = self.ActiveLayer == i and T.Selected
				or ( pnl:IsHovered() and T.RowHover ) or T.Row
			surface.SetDrawColor( col.r, col.g, col.b, 255 )
			surface.DrawRect( 0, 0, w, h )
		end

		local eye = vgui.Create( "DButton", row )
		eye:Dock( LEFT )
		eye:SetWide( AdvMat.RowHeight() )
		eye:SetText( layer.on == false and "-" or "o" )
		-- Without a colour of its own a Derma button keeps the default skin's
		-- dark text, which all but vanishes on these rows.
		eye:SetFont( "AdvMatBold" )
		eye:SetTextColor( layer.on == false and T.TextFaint or T.Accent )
		eye:SetTooltip( "Show or hide this layer" )
		eye.Paint = AdvMat.NoPaint
		eye.DoClick = function()
			self:PushUndo( "Toggle layer visibility" )
			if layer.on == false then layer.on = nil else layer.on = false end
			self.Canvas:SetLayers( layers )
			self:RefreshLayers()
			self:PushToModel()
		end

		local thumb = vgui.Create( "DPanel", row )
		thumb:Dock( LEFT )
		thumb:SetWide( rowH )
		thumb:DockMargin( 2, 2, 4, 2 )
		local mat = AdvMat.PreviewMaterial and AdvMat.PreviewMaterial( layer.src )
		thumb.Paint = function( _, w, h )
			if mat then
				surface.SetDrawColor( 255, 255, 255, layer.on == false and 80 or 255 )
				surface.SetMaterial( mat )
				surface.DrawTexturedRect( 0, 0, w, h )
			end
			surface.SetDrawColor( T.Line.r, T.Line.g, T.Line.b, 255 )
			surface.DrawOutlinedRect( 0, 0, w, h, 1 )
		end

		local choose = vgui.Create( "DButton", row )
		choose:Dock( FILL )
		choose:SetText( OPS.DescribeLayer( layer ) )
		choose:SetFont( "AdvMatText" )
		choose:SetTextColor( layer.on == false and T.TextFaint or T.Text )
		choose:SetContentAlignment( 4 )
		choose:SetTooltip( layer.src )
		choose.Paint = AdvMat.NoPaint
		choose.DoClick = function() self:SelectLayer( i ) end
		choose.DoRightClick = function()
			self:SelectLayer( i )
			local menu = DermaMenu()
			AdvMat.I18N.Track( menu )
			AddMenuOption( menu, "Change layer source...", function() self:ChangeLayerSource() end )
			AddMenuOption( menu, "Duplicate layer", function() self:DuplicateLayer() end )
			AddMenuOption( menu, "Raise layer", function() self:MoveLayer( 1 ) end )
			AddMenuOption( menu, "Lower layer", function() self:MoveLayer( -1 ) end )
			menu:AddSpacer()
			AddMenuOption( menu, "Centre layer", function()
				self:EditLayer( function( active ) active.x, active.y = 0.5, 0.5 end )
				self:BuildOptions()
			end )
			AddMenuOption( menu, "Fit layer to canvas", function()
				self:EditLayer( function( active ) self:FitLayer( active ) end )
				self:BuildOptions()
			end )
			AddMenuOption( menu, "Reset layer transform", function() self:ResetActiveLayer() end )
			menu:AddSpacer()
			AddMenuOption( menu, "Delete layer", function() self:DeleteLayer() end,
				"icon16/delete.png" )
			menu:Open()
		end
	end

	local base = self.Layers:Add( "DButton" )
	base:Dock( TOP )
	base:SetTall( rowH )
	base:SetText( self.Recipe.src and AdvMat.L( "texture.layer_base", { texture = SourceLabel( self.Recipe.src ) } )
		or AdvMat.LText( "Base: blank image" ) )
	base:SetContentAlignment( 4 )
	base:SetTooltip( "The source and paint/effect steps below every imported layer" )
	AdvMat.StyleButton( base )
	base.DoClick = function() self:SelectLayer( nil ) end

	local buttons = self.LayerActionButtons or {}
	local selected = self.ActiveLayer and layers[ self.ActiveLayer ] ~= nil
	if IsValid( buttons.import ) then buttons.import:SetEnabled( #layers < OPS.MAX_LAYERS ) end
	if IsValid( buttons.duplicate ) then
		buttons.duplicate:SetEnabled( selected and #layers < OPS.MAX_LAYERS )
	end
	if IsValid( buttons.up ) then
		buttons.up:SetEnabled( selected and self.ActiveLayer < #layers )
	end
	if IsValid( buttons.down ) then
		buttons.down:SetEnabled( selected and self.ActiveLayer > 1 )
	end
	if IsValid( buttons.delete ) then buttons.delete:SetEnabled( selected ) end
end

---------------------------------------------------------------------------
-- Tools and their options
---------------------------------------------------------------------------
function PANEL:SetTool( id )
	if self.RegionMode and ( id == "paint" or id == "erase" or id == "fill"
		or id == "gradient" or id == "layer" ) then return end

	if id == "layer" and not ( self.ActiveLayer and self.Recipe.layers
		and self.Recipe.layers[ self.ActiveLayer ] ) then
		self:ImportLayer()
		return
	end

	self.Tool = id
	self.Canvas.Tool = id
	self.Canvas.DimOutside = ( id == "paint" or id == "erase" or id == "fill"
		or id == "gradient" )

	for _, tool in ipairs( TOOLS ) do
		if tool.id == id and IsValid( self.OptsHead ) then
			self.OptsHead:SetText( tool.label )
		end
	end

	self:BuildOptions()
end

function PANEL:Status( text, bad )
	if not IsValid( self.SelStatus ) then return end

	self.SelStatus:SetText( text )
	self.SelStatus:SetTextColor( bad and T.Warn or T.TextDim )

	timer.Create( "AdvMat.TexStatus", 6, 1, function()
		if not IsValid( self ) then return end
		self.SelStatus:SetTextColor( T.TextDim )
		self:RefreshSelectionStatus()
	end )
end

---------------------------------------------------------------------------
-- The hint bar
---------------------------------------------------------------------------
-- One line above the canvas answering "what does this tool do now, and what
-- do the keys change?" Those answers used to live in tooltips and at the
-- bottom of the options dock, where only someone already looking found them -
-- the eraser's Alt was a sentence below the fold.
--
-- It is worked out afresh every frame from the keyboard as well as the
-- settings, so a held key shows its effect before the click: hold Alt with
-- the eraser and the mode shown is the one the next stroke will use, and the
-- Alt key itself lights up.

local function KeyHeld( left, right )
	return input and input.IsKeyDown
		and ( input.IsKeyDown( left ) or input.IsKeyDown( right ) ) or false
end

--- The words for one entry of the bar: its catalogue key when it has one -
--- "Add" is two different words in other languages, so the English alone
--- cannot find its translation - otherwise its English, either way with any
--- {{name}} slots filled in.
local function HintWords( item, keyField, textField )
	local key = item[ keyField ]
	if key and AdvMat.L then return AdvMat.L( key, item.vars ) end

	local text = item[ textField ] or ""
	if AdvMat.LText then return AdvMat.LText( text, item.vars ) end

	local filled = string.gsub( text, "{{%s*([%w_]+)%s*}}", function( name )
		local value = item.vars and item.vars[ name ]
		return value == nil and "{{" .. name .. "}}" or tostring( value )
	end )
	return filled
end

--- What the bar shows for the active tool.
---
---     tool    the tool's name
---     states  what it will do: { text, key?, vars?, kind } where kind is
---             "mode" for its setting, "held" for a setting a key is
---             changing right now, "warn" for something that stops it
---             working, and "info" for anything else worth knowing
---     hints   the inputs that matter: { keys, text, vars?, held }, `held`
---             while that key is down
---
--- Every string is English source, translated as it is drawn. Kept apart
--- from the drawing so the tests can read it without a renderer.
function PANEL:HintModel()
	local tool  = self.Tool
	local shift = KeyHeld( KEY_LSHIFT, KEY_RSHIFT )
	local ctrl  = KeyHeld( KEY_LCONTROL, KEY_RCONTROL )
	local alt   = KeyHeld( KEY_LALT, KEY_RALT )

	local model = { tool = "", states = {}, hints = {} }

	for _, def in ipairs( TOOLS ) do
		if def.id == tool then model.tool = def.label break end
	end

	local function State( text, kind, vars, key )
		model.states[ #model.states + 1 ] = { text = text, kind = kind or "mode",
			vars = vars, key = key }
	end

	local function Hint( keys, text, held, vars, key )
		model.hints[ #model.hints + 1 ] = { keys = keys, text = text,
			held = held == true, vars = vars, key = key }
	end

	-- Where a brush or a gradient can land - a forgotten selection is the
	-- commonest reason one seems to do nothing.
	local function Reach()
		if self.Sel and self.Mask then
			State( "Only inside the selection", "warn" )
		else
			State( "Works anywhere", "info" )
		end
	end

	-- How paint and fill combine with the picture: a tint when the shading is
	-- kept on a real texture, otherwise the chosen blend.
	local function Blend( id )
		for _, def in ipairs( OPS.BLENDS ) do
			if def.id == ( id or "normal" ) then State( def.name, "mode", nil, def.key ) return end
		end
	end

	local function PaintBlend()
		local source = self.Recipe and self.Recipe.src and self.Recipe.src ~= ""
		if self.KeepShading and source then
			State( "Keep the shading" )
		else
			Blend( self.PaintBlend )
		end
	end

	local brush = { size = AdvMat.NumToString
		and AdvMat.NumToString( math.Round( ( self.Brush or 0.04 ) * 100, 2 ) )
		or tostring( ( self.Brush or 0.04 ) * 100 ) }

	if SELECT_TOOLS[ tool ] then
		-- The same rule the canvas applies to the next shape: a held modifier
		-- wins over the buttons for as long as it is held.
		local mode = ( shift and ctrl ) and "int" or ( shift and "add" )
			or ( ctrl and "sub" ) or self.Mode or "replace"
		local keys = { replace = "texture.mode_replace", add = "texture.mode_add",
			sub = "texture.mode_sub", int = "texture.mode_overlap" }

		for _, def in ipairs( MODES ) do
			if def.id == mode then
				State( def.label, ( shift or ctrl ) and "held" or "mode", nil, keys[ mode ] )
			end
		end

		if tool == "island" then
			Hint( "Click", "select a piece, on the texture or the model" )
		elseif tool == "box" then
			Hint( "Drag", "draw a rectangle" )
			if IsValid( self.Canvas ) and self.Canvas.Square then State( "Keep it square", "info" ) end
		elseif tool == "ellipse" then
			Hint( "Drag", "draw an oval" )
		elseif tool == "lasso" then
			Hint( "Drag", "draw around the area" )
		elseif tool == "wand" then
			Hint( "Click", "select by colour" )
			State( "Tolerance {{value}}%", "info",
				{ value = math.Round( ( self.Tolerance or 0.1 ) * 100 ) } )
			State( self.Contiguous == false and "Everywhere on the sheet"
				or "Only areas that touch", "info" )
		end

		Hint( "Shift", "Add", shift and not ctrl, nil, "texture.mode_add" )
		Hint( "Ctrl", "Take away", ctrl and not shift, nil, "texture.mode_sub" )
		Hint( "Shift+Ctrl", "Overlap only", shift and ctrl, nil, "texture.mode_overlap" )

	elseif tool == "erase" then
		-- A stroke keeps the mode it began with; otherwise this is what the next
		-- one will do, Alt included.
		local chosen = ( self.EraseMode == "holes" ) and "holes" or "revert"
		local mode = self.StrokeMode or self:StrokeEraseMode()

		State( mode == "holes" and "Make see-through" or "Back to original",
			mode ~= chosen and "held" or "mode" )
		Reach()

		Hint( "Alt", chosen == "holes" and "Back to original for one stroke"
			or "Make see-through for one stroke", alt )
		Hint( "Shift+E", "switch mode" )
		Hint( "Ctrl+Wheel", "brush size {{size}}%", ctrl, brush )

	elseif tool == "paint" then
		PaintBlend()
		Reach()
		Hint( "Ctrl+Wheel", "brush size {{size}}%", ctrl, brush )
		Hint( "X", "swap colours" )

	elseif tool == "fill" then
		-- Fill refuses to run without a selection rather than flood the sheet,
		-- so here no selection is the warning and a selection is expected.
		PaintBlend()
		if not self.Sel then
			State( "Select an area first", "warn" )
		elseif self.Mask then
			State( "Only inside the selection", "info" )
		else
			State( "Works anywhere", "info" )
		end
		Hint( "Click", "fill the selection" )
		Hint( "X", "swap colours" )

	elseif tool == "gradient" then
		Blend( self.GradientBlend )
		Reach()
		Hint( "Drag", "foreground to background colour" )
		Hint( "X", "swap colours" )

	elseif tool == "pick" then
		local across = math.floor( self.PickSize or 1 ) * 2 + 1
		State( "Averages {{size}} x {{size}} pixels", "info", { size = across } )
		Hint( "Click", "take a colour, from the texture or the model" )

	elseif tool == "pan" then
		Hint( "Drag", "move the view" )

	elseif tool == "layer" then
		local layer = self.ActiveLayer and self.Recipe and self.Recipe.layers
			and self.Recipe.layers[ self.ActiveLayer ]
		if layer then
			State( OPS.DescribeLayer( layer ), "mode" )
		else
			State( "No layer selected", "warn" )
		end
		Hint( "Drag", "move" )
		Hint( "Corner", "resize" )
		Hint( "Top handle", "rotate" )
	end

	-- True of every tool, so they come last and are the first to go when the
	-- window is narrow.
	Hint( "Wheel", "zoom" )
	if tool ~= "pan" then Hint( "Right drag", "move the view" ) end
	Hint( "Ctrl+Z", "undo" )

	return model
end

--- Draw the bar: the tool's name, its states as pills, then each key and
--- what it does. Everything is drawn in priority order and an entry that does
--- not fit whole is left out along with everything after it, so a narrow
--- window loses the generic hints first and never the tool's own state.
function PANEL:PaintHintBar( w, h )
	surface.SetDrawColor( T.Panel.r, T.Panel.g, T.Panel.b, 255 )
	surface.DrawRect( 0, 0, w, h )
	surface.SetDrawColor( T.Line.r, T.Line.g, T.Line.b, 255 )
	surface.DrawOutlinedRect( 0, 0, w, h, 1 )

	local model = self:HintModel()
	local pad, gap = 8, 6
	local x, limit = pad, w - pad
	local cy = math.floor( h * 0.5 )
	local pillH = math.max( h - 8, 8 )
	local pillY = math.floor( ( h - pillH ) * 0.5 )

	local name = HintWords( model, nil, "tool" )
	surface.SetFont( "AdvMatBold" )
	local nameW = surface.GetTextSize( name )
	if x + nameW > limit then return end
	draw.SimpleText( name, "AdvMatBold", x, cy, T.Text, TEXT_ALIGN_LEFT, TEXT_ALIGN_CENTER )
	x = x + nameW + gap * 2

	surface.SetFont( "AdvMatSmall" )

	for _, state in ipairs( model.states ) do
		local text = HintWords( state, "key", "text" )
		local pillW = surface.GetTextSize( text ) + 14
		if x + pillW > limit then return end

		-- A setting is the selection blue; one a held key is changing is amber,
		-- so it reads as temporary; a warning keeps the quiet fill with amber
		-- words.
		local fill, ink = T.Header, T.Text
		if state.kind == "mode" then
			fill = T.Selected
		elseif state.kind == "held" then
			fill, ink = T.Warn, T.Line
		elseif state.kind == "warn" then
			ink = T.Warn
		end

		draw.RoundedBox( 4, x, pillY, pillW, pillH, fill )
		draw.SimpleText( text, "AdvMatSmall", x + 7, cy, ink, TEXT_ALIGN_LEFT, TEXT_ALIGN_CENTER )
		x = x + pillW + gap
	end

	if #model.hints == 0 or x + gap * 3 > limit then return end
	x = x + gap
	surface.SetDrawColor( T.Line.r, T.Line.g, T.Line.b, 255 )
	surface.DrawRect( x, 5, 1, h - 10 )
	x = x + gap * 2

	for _, hint in ipairs( model.hints ) do
		local keys = HintWords( hint, nil, "keys" )
		local text = HintWords( hint, "key", "text" )
		local capW = surface.GetTextSize( keys ) + 12
		local textW = surface.GetTextSize( text )
		if x + capW + 5 + textW > limit then return end

		-- A key cap, lit while that key is held.
		draw.RoundedBox( 3, x, pillY, capW, pillH, T.Line )
		draw.RoundedBox( 3, x + 1, pillY + 1, capW - 2, pillH - 2,
			hint.held and T.Selected or T.Header )
		draw.SimpleText( keys, "AdvMatSmall", x + capW * 0.5, cy, T.Text,
			TEXT_ALIGN_CENTER, TEXT_ALIGN_CENTER )
		x = x + capW + 5

		draw.SimpleText( text, "AdvMatSmall", x, cy, hint.held and T.Text or T.TextDim,
			TEXT_ALIGN_LEFT, TEXT_ALIGN_CENTER )
		x = x + textW + gap * 2
	end
end

local function OptSlider( parent, label, min, max, decimals, value, tip, fn )
	local s = parent:Add( "DNumSlider" )
	s:Dock( TOP )
	s:SetTall( AdvMat.RowHeight() + 6 )
	s:DockMargin( 6, 2, 6, 2 )
	s:SetText( label )
	s:SetMin( min )
	s:SetMax( max )
	s:SetDecimals( decimals )
	s:SetValue( value )
	if tip then s:SetTooltip( tip ) end
	AdvMat.StyleSlider( s )
	s.OnValueChanged = fn
	return s
end

local function OptCheck( parent, label, value, tip, fn )
	local c = parent:Add( "DCheckBoxLabel" )
	c:Dock( TOP )
	c:DockMargin( 6, 4, 6, 4 )
	AdvMat.StyleCheck( c, label )
	c:SetValue( value )
	if tip then c:SetTooltip( tip ) end
	c.OnChange = fn
	return c
end

local function OptCombo( parent, label, choices, value, tip, fn )
	local caption = parent:Add( "DLabel" )
	caption:Dock( TOP )
	caption:SetTall( AdvMat.RowHeight() )
	caption:DockMargin( 6, 4, 6, 0 )
	caption:SetText( label )
	AdvMat.StyleLabel( caption, "AdvMatSmall", T.TextDim )

	local combo = parent:Add( "DComboBox" )
	combo:Dock( TOP )
	combo:SetTall( AdvMat.RowHeight() + 4 )
	combo:DockMargin( 6, 0, 6, 4 )
	combo:SetSortItems( false )
	if tip then combo:SetTooltip( tip ) end
	AdvMat.StyleCombo( combo )
	for _, definition in ipairs( choices or {} ) do
		local label = definition.key and AdvMat.L( definition.key ) or definition.name
		combo:AddChoice( label, definition.id, definition.id == value )
	end
	combo.OnSelect = function( _, _, _, data ) fn( data ) end
	return combo
end

local function OptLabel( parent, text )
	local l = parent:Add( "DLabel" )
	l:Dock( TOP )
	l:SetTall( AdvMat.RowHeight() )
	l:DockMargin( 6, 4, 6, 0 )
	l:SetText( text )
	AdvMat.StyleLabel( l, "AdvMatSmall", T.TextFaint )
	l:SetWrap( true )
	l:SetAutoStretchVertical( true )
	return l
end

function PANEL:BuildLayerOptions()
	local layer = self.ActiveLayer and self.Recipe.layers[ self.ActiveLayer ]
	if not layer then
		OptLabel( self.Opts, "Import a texture layer, then select it here to move, resize and rotate it." )
		return
	end

	self.BuildingLayerOptions = true

	local source = self.Opts:Add( "DButton" )
	source:Dock( TOP )
	source:SetTall( AdvMat.RowHeight() * 2 )
	source:DockMargin( 6, 4, 6, 4 )
	source:SetText( AdvMat.L( "texture.layer_source", { texture = layer.src } ) )
	source:SetTooltip( layer.src )
	AdvMat.StyleButton( source )
	source.DoClick = function() self:ChangeLayerSource() end

	OptSlider( self.Opts, "Horizontal position (%)", -200, 300, 2, layer.x * 100, nil,
		function( _, v ) self:EditLayer( function( l ) l.x = v / 100 end ) end )
	OptSlider( self.Opts, "Vertical position (%)", -200, 300, 2, layer.y * 100, nil,
		function( _, v ) self:EditLayer( function( l ) l.y = v / 100 end ) end )

	OptCheck( self.Opts, "Keep texture proportions", self.LayerKeepAspect,
		"When enabled, either size control scales both sides together.", function( _, value )
			if self.BuildingLayerOptions then return end
			self.LayerKeepAspect = value
			self.Canvas.LayerKeepAspect = value
		end )

	OptSlider( self.Opts, "Width (%)", 0.2, 400, 2, layer.w * 100, nil,
		function( _, v )
			self:EditLayer( function( l )
				local old = math.max( l.w, 0.002 )
				l.w = v / 100
				if self.LayerKeepAspect then l.h = l.h * l.w / old end
			end )
		end )
	OptSlider( self.Opts, "Height (%)", 0.2, 400, 2, layer.h * 100, nil,
		function( _, v )
			self:EditLayer( function( l )
				local old = math.max( l.h, 0.002 )
				l.h = v / 100
				if self.LayerKeepAspect then l.w = l.w * l.h / old end
			end )
		end )
	OptSlider( self.Opts, "Rotation (degrees)", -180, 180, 2, layer.angle or 0, nil,
		function( _, v ) self:EditLayer( function( l ) l.angle = v end ) end )
	OptSlider( self.Opts, "Layer opacity (%)", 0, 100, 2, layer.opacity * 100, nil,
		function( _, v ) self:EditLayer( function( l ) l.opacity = v / 100 end ) end )

	OptCheck( self.Opts, "Flip horizontally", layer.flipx == true, nil,
		function( _, v ) self:EditLayer( function( l ) l.flipx = v or nil end ) end )
	OptCheck( self.Opts, "Flip vertically", layer.flipy == true, nil,
		function( _, v ) self:EditLayer( function( l ) l.flipy = v or nil end ) end )
	OptCheck( self.Opts, "Ignore the texture's alpha channel", layer.opaque == true,
		"Use this when the alpha channel stores a phong or reflection mask rather than transparency.",
		function( _, v ) self:EditLayer( function( l ) l.opaque = v or nil end ) end )

	local commands = self.Opts:Add( "DHorizontalScroller" )
	commands:Dock( TOP )
	commands:SetTall( AdvMat.RowHeight() + 8 )
	commands:DockMargin( 6, 6, 6, 2 )
	commands:SetOverlap( -4 )
	commands.Paint = AdvMat.NoPaint

	local function Command( text, tip, fn )
		local b = vgui.Create( "DButton", commands )
		b.AdvMatI18NAutoWidth = true
		b:SetSize( AdvMat.FontSize * 6, AdvMat.RowHeight() + 4 )
		b:SetText( text )
		b:SetTooltip( tip )
		b.DoClick = fn
		AdvMat.StyleButton( b )
		commands:AddPanel( b )
	end

	Command( "Centre", "Put the layer in the middle of the canvas", function()
		self:EditLayer( function( l ) l.x, l.y = 0.5, 0.5 end )
		self:BuildOptions()
	end )
	Command( "Fit", "Fit the whole layer inside the canvas", function()
		self:EditLayer( function( l ) self:FitLayer( l ) end )
		self:BuildOptions()
	end )
	Command( "Reset", "Centre, fit and remove rotation and flips", function()
		self:EditLayer( function( l )
			l.x, l.y, l.angle = 0.5, 0.5, 0
			l.flipx, l.flipy = nil, nil
			self:FitLayer( l )
		end )
		self:BuildOptions()
	end )

	OptLabel( self.Opts, "Drag the layer to move it. Drag a corner to resize it, or the handle above it to rotate." )

	self.BuildingLayerOptions = nil
end

function PANEL:BuildOptions()
	self.Opts:Clear()

	local tool = self.Tool
	if tool == "layer" then
		self:BuildLayerOptions()
		return
	end

	if SELECT_TOOLS[ tool ] then
		self:BuildModeButtons()
	end

	if tool == "wand" then
		OptSlider( self.Opts, "How close a colour has to be", 0, 100, 2,
			( self.Tolerance or 0.1 ) * 100,
			"Higher picks up more shades of the colour you clicked.",
			function( _, v )
				self.Tolerance = v / 100
				self.Canvas.Tolerance = self.Tolerance
			end )

		OptCheck( self.Opts, "Only areas that touch", self.Contiguous ~= false,
			"Off selects every matching pixel anywhere on the sheet, which is how " ..
			"you recolour all of the gold trim at once.",
			function( _, v )
				self.Contiguous = v
				self.Canvas.Contiguous = v
			end )
	end

	if tool == "island" then
		OptSlider( self.Opts, "Grow by (pixels)", 0, 16, 2, self.IslandGrow or 2,
			"Nudges the edge outwards, which covers the hairline of old colour " ..
			"that otherwise shows along a seam on the model.\n\n" ..
			"It is also why a picked piece can look a pixel or two larger than " ..
			"you expected. Set it to 0 for an exact edge.",
			function( _, v ) self.IslandGrow = v end )

		OptLabel( self.Opts, "Softening is off for model pieces on purpose: a soft " ..
			"edge bleeds across the seam onto the piece next door and shows up as dirt." )
	end

	if tool == "box" or tool == "ellipse" or tool == "lasso" then
		OptSlider( self.Opts, "Soften the edge (pixels)", 0, 32, 2, self.Feather or 0,
			"Fades the edge of the selection instead of cutting it sharply.",
			function( _, v ) self.Feather = v end )

		OptSlider( self.Opts, "Make it bigger or smaller", -16, 16, 2, self.Grow or 0,
			"Negative shrinks the selected area, positive grows it.",
			function( _, v ) self.Grow = v end )

		if tool == "box" then
			OptCheck( self.Opts, "Keep it square", self.Canvas.Square or false, nil,
				function( _, v ) self.Canvas.Square = v end )
		end
	end

	if tool == "erase" then
		self:BuildEraseModes()
	end

	if tool == "paint" or tool == "erase" then
		OptSlider( self.Opts, "Brush size", 0.01, 40, 2, ( self.Brush or 0.04 ) * 100,
			"Also Ctrl and the mouse wheel.",
			function( _, v )
				self.Brush = v / 100
				self.Canvas.Brush = self.Brush
			end )

		OptSlider( self.Opts, "Brush hardness", 0, 100, 1,
			( self.Hardness or 1 ) * 100,
			"100 gives a crisp edge. Lower values feather each brush dab toward its rim.",
			function( _, v )
				self.Hardness = v / 100
				self.Canvas.Hardness = self.Hardness
			end )
	end

	if tool == "paint" or tool == "fill" then
		local blend
		OptCheck( self.Opts, "Keep the shading", self.KeepShading,
			"Changes the colour but keeps the light and shadow that was already " ..
			"painted on, so the part still looks like cloth instead of a flat sticker.",
			function( _, v )
				self.KeepShading = v
				local preserving = v and self.Recipe and self.Recipe.src
					and self.Recipe.src ~= ""
				if IsValid( blend ) then blend:SetEnabled( not preserving ) end
			end )

		blend = OptCombo( self.Opts, "Paint blend mode", OPS.BLENDS,
			self.PaintBlend or "normal",
			"Controls how ordinary paint combines with the image. Keep shading uses a tint instead.",
			function( value ) self.PaintBlend = value or "normal" end )
		local preservingShading = self.KeepShading and self.Recipe
			and self.Recipe.src and self.Recipe.src ~= ""
		blend:SetEnabled( not preservingShading )
	end

	if tool == "paint" or tool == "erase" or tool == "fill" or tool == "gradient" then
		OptSlider( self.Opts, "Strength", 0, 100, 2, ( self.Strength or 1 ) * 100,
			tool == "erase"
				and "How much each stroke rubs away. 100 goes all the way back to the " ..
					"original, or all the way to see-through."
				or "How far towards the new colour, or how much comes away per stroke.",
			function( _, v ) self.Strength = v / 100 end )
	end

	if tool == "gradient" then
		OptLabel( self.Opts,
			"Drag from the foreground colour to the background colour. The gradient extends past both endpoints." )

		OptCombo( self.Opts, "Gradient blend mode", OPS.BLENDS,
			self.GradientBlend or "normal", nil,
			function( value ) self.GradientBlend = value or "normal" end )
	end

	-- Not for Fill: it refuses to run without a selection rather than fill the
	-- whole texture, so "works anywhere" would be the wrong thing to tell it.
	if tool == "paint" or tool == "erase" or tool == "gradient" then
		self:BuildSelectionNotice()
	end

	if tool == "erase" then
		local holes = self.EraseMode == "holes"

		-- Whole-selection versions of whichever job the eraser is doing. Both
		-- need a selection: without one they would change the entire texture,
		-- which is one click too easy to do by accident.
		local function WholeSelection( text, tip, op )
			local b = self.Opts:Add( "DButton" )
			b:Dock( TOP )
			b:SetTall( AdvMat.RowHeight() + 4 )
			b:DockMargin( 6, 4, 6, 2 )
			b:SetText( text )
			b:SetTooltip( tip )
			AdvMat.StyleButton( b )
			b.DoClick = function()
				local sel = self:StepSelection()
				if not sel then
					self:Status( "Select something first, or this would change the " ..
						"whole texture.", true )
					return
				end
				self:AddStep( { op = op, sel = sel, opacity = 1 } )
			end
		end

		-- Labels short enough for the dock at its narrowest; the full sentence
		-- is the tooltip. The keys that switch modes are in the hint bar above
		-- the canvas, not down here below the fold.
		if holes then
			WholeSelection( "Make selection see-through",
				"Cuts the whole selection away in one go instead of scrubbing at it.", "erase" )
			WholeSelection( "Make selection solid",
				"Fills the holes inside the selection back in.", "restore" )
		else
			WholeSelection( "Selection back to original",
				"Rubs out every change inside the selection in one go.", "revert" )
		end
	end

	if tool == "pick" then
		OptSlider( self.Opts, "How much to average", 0, 4, 0, self.PickSize or 1,
			"Game textures are compressed, so a single pixel is often a few percent " ..
			"out. Averaging a small area is more accurate.",
			function( _, v ) self.PickSize = math.floor( v ) end )
	end

	------------------------------------------------------------ extra steps
	if self.RegionMode then return end

	local extra = self.Opts:Add( "DButton" )
	extra:Dock( TOP )
	extra:SetTall( AdvMat.RowHeight() + 4 )
	extra:DockMargin( 6, 10, 6, 2 )
	extra:SetText( "Other changes..." )
	extra:SetTooltip( "Brightness, blur, noise and the rest, applied to the selection." )
	AdvMat.StyleButton( extra )
	extra.DoClick = function() self:OpenExtraMenu() end
end

function PANEL:BuildModeButtons()
	local strip = self.Opts:Add( "DPanel" )
	strip:Dock( TOP )
	strip:SetTall( ( AdvMat.RowHeight() + 3 ) * #MODES )
	strip:DockMargin( 6, 4, 6, 4 )
	strip.Paint = AdvMat.NoPaint

	for _, mode in ipairs( MODES ) do
		local b = vgui.Create( "DButton", strip )
		-- The tool-options dock is intentionally narrow. One translated mode per
		-- row remains readable in every locale; four fixed-width buttons in one
		-- row overflowed the dock before Russian or French were even considered.
		b:Dock( TOP )
		b:SetTall( AdvMat.RowHeight() + 1 )
		b:DockMargin( 0, 0, 0, 2 )
		b:SetText( mode.label )
		b:SetFont( "AdvMatSmall" )
		b:SetTextColor( T.Text )
		b:SetTooltip( "Shift adds, Ctrl takes away, both together keeps only the overlap." )

		b.Paint = function( pnl, w, h )
			local on = ( self.Mode == mode.id )
			local col = on and T.Selected or ( pnl:IsHovered() and T.HeaderHot or T.Header )
			surface.SetDrawColor( col.r, col.g, col.b, 255 )
			surface.DrawRect( 0, 0, w, h )
			surface.SetDrawColor( T.Line.r, T.Line.g, T.Line.b )
			surface.DrawOutlinedRect( 0, 0, w, h, 1 )
		end

		b.DoClick = function()
			self.Mode = mode.id
			self.Canvas.Mode = mode.id
		end
	end
end

--- The eraser's two jobs as two buttons at the top of its options, so the
--- choice is made before anything is rubbed rather than discovered after.
function PANEL:BuildEraseModes()
	local strip = self.Opts:Add( "DPanel" )
	strip:Dock( TOP )
	strip:SetTall( ( AdvMat.RowHeight() + 3 ) * #ERASE_MODES )
	strip:DockMargin( 6, 4, 6, 2 )
	strip.Paint = AdvMat.NoPaint

	for _, mode in ipairs( ERASE_MODES ) do
		local b = vgui.Create( "DButton", strip )
		b:Dock( TOP )
		b:SetTall( AdvMat.RowHeight() + 1 )
		b:DockMargin( 0, 0, 0, 2 )
		b:SetText( mode.label )
		b:SetFont( "AdvMatSmall" )
		b:SetTextColor( T.Text )
		b:SetTooltip( mode.tip )

		b.Paint = function( pnl, w, h )
			local on = ( self.EraseMode or "revert" ) == mode.id
			local col = on and T.Selected or ( pnl:IsHovered() and T.HeaderHot or T.Header )
			surface.SetDrawColor( col.r, col.g, col.b, 255 )
			surface.DrawRect( 0, 0, w, h )
			surface.SetDrawColor( T.Line.r, T.Line.g, T.Line.b )
			surface.DrawOutlinedRect( 0, 0, w, h, 1 )
		end

		b.DoClick = function() self:SetEraseMode( mode.id ) end
	end

	OptLabel( self.Opts, self.EraseMode == "holes"
		and "Rubs the texture itself away so the model shows a hole. The material " ..
			"is made see-through ($translucent) for you when you press Use this texture."
		or "Rubs out your paint, effects and holes, and brings back the texture you " ..
			"started from. Where nothing has been changed there is nothing to rub out." )
end

--- Whether the brush works everywhere or only inside the selection, kept up
--- to date while the options are open. A selection made a while ago and since
--- forgotten is the commonest reason a brush seems to do nothing at all.
function PANEL:BuildSelectionNotice()
	local label = OptLabel( self.Opts, "" )

	-- DLabel's own Think is what grows a wrapped label to fit its text, so it
	-- is chained rather than replaced.
	local labelThink = label.Think
	label.Think = function( pnl )
		-- A selection with no mask is "Select all"; see RefreshSelectionStatus.
		local text = not self.Sel and "Works anywhere - nothing is selected."
			or not self.Mask and "Works anywhere - the whole picture is selected."
			or "Only works inside the selection. The dimmed area is protected."

		if pnl.AdvMatShown ~= text then
			pnl.AdvMatShown = text
			pnl:SetText( text )
		end

		if labelThink then labelThink( pnl ) end
	end

	local none = self.Opts:Add( "DButton" )
	none:Dock( TOP )
	none:SetTall( AdvMat.RowHeight() + 4 )
	none:DockMargin( 6, 2, 6, 2 )
	none:SetText( "Select none" )
	none:SetTooltip( "Ctrl+Shift+A" )
	AdvMat.StyleButton( none )
	none.DoClick = function() self:SetSelection( nil ) end

	local noneThink = none.Think
	none.Think = function( pnl )
		local on = self.Sel ~= nil
		if pnl:IsEnabled() ~= on then pnl:SetEnabled( on ) end
		if noneThink then noneThink( pnl ) end
	end
end

---------------------------------------------------------------------------
-- The rest of the steps
---------------------------------------------------------------------------
function PANEL:OpenExtraMenu()
	local menu = DermaMenu()
	AdvMat.I18N.Track( menu )
	local sel  = self:StepSelection()

	menu:AddOption( "Brightness, colour and contrast...", function()
		self:OpenAdjustDialog()
	end )

	menu:AddOption( "Blur", function()
		self:AddStep( { op = "blur", sel = sel, radius = 3 } )
	end )

	menu:AddOption( "Sharpen", function()
		self:AddStep( { op = "sharpen", sel = sel, amount = 1 } )
	end )

	menu:AddOption( "Add noise (worn look)", function()
		self:AddStep( { op = "noise", sel = sel, amount = 0.15, seed = #self.Recipe.ops + 1, mono = true } )
	end )

	menu:AddSpacer()

	menu:AddOption( "Make the dark parts see-through", function()
		self:AddStep( { op = "alphafrom", sel = sel, from = "luminance",
			threshold = 0.35, softness = 0.15 } )
	end )

	menu:AddOption( "Make the selection see-through", function()
		self:AddStep( { op = "erase", sel = sel, opacity = 1 } )
	end )

	menu:AddOption( "Bring back the original in the selection", function()
		self:AddStep( { op = "revert", sel = sel, opacity = 1 } )
	end )

	menu:Open()
end

function PANEL:OpenAdjustDialog( initialField )
	-- Only one transient image may own the canvas. Closing the old window first
	-- restores the committed buffer before the next transaction is created.
	if IsValid( self.AdjustDialog ) then self.AdjustDialog:Close() end

	local sel = self:StepSelection()

	local op = { op = "adjust", sel = sel, hue = 0, sat = 1, val = 1,
		bright = 0, contrast = 1, desat = 0 }
	local gammaValue, posterizeValue, thresholdValue = 1, 8, 0.5
	if initialField == "gamma" then op.gamma = gammaValue end
	if initialField == "posterize" then op.posterize = posterizeValue end
	if initialField == "threshold" then op.threshold = thresholdValue end

	-- Keep this a real top-level utility window. A parented DFrame interprets
	-- SetPos in parent-local coordinates, while shared child placement works in
	-- screen coordinates; mixing the two sent this dialog to the wrong display
	-- position and made nested text focus ambiguous.
	local frame = vgui.Create( "DFrame" )
	frame.AdvMatHost = self
	frame:SetSize( math.max( 440, AdvMat.FontSize * 28 ),
		math.min( ScrH() - 80, AdvMat.RowHeight() * 17 + 80 ) )
	frame:SetMinWidth( math.min( math.max( 420, AdvMat.FontSize * 24 ), ScrW() - 24 ) )
	frame:SetMinHeight( math.min( 400, ScrH() - 24 ) )
	frame:SetSizable( true )
	frame:SetTitle( "Brightness, colour and contrast" )
	frame:SetDeleteOnClose( true )
	frame:Center()
	frame:MakePopup()
	if frame.DoModal then frame:DoModal() end
	self.AdjustDialog = frame
	self:BeginStepPreview( frame )

	local finished = false
	local function Finish( commit )
		if finished then return false end
		if not IsValid( self ) then
			finished = true
			return false
		end

		-- Refused before the transaction ends, so the dialog stays open with
		-- its preview and nothing typed into it is lost.
		if commit then
			local clean = OPS.Sanitize( op )
			if clean and not self:CanAddStep( clean ) then return false end
		end

		finished = true
		local done = self:EndStepPreview( frame, commit, op )
		if self.AdjustDialog == frame then self.AdjustDialog = nil end
		return done
	end

	local function Preview()
		if not finished and IsValid( self ) then self:QueueStepPreview( frame, op ) end
	end

	frame.OnClose = function() Finish( false ) end
	-- Panel:Remove does not call DFrame:OnClose. Parent removal and hot reloads
	-- still have to cancel the timer and discard the transient image.
	frame.OnRemove = function() Finish( false ) end
	-- Install the shared cleanup wrapper only after the dialog's transaction
	-- cleanup exists, so a direct Remove cannot replace either responsibility.
	AdvMat.StyleFrame( frame )
	if AdvMat.WindowUX then AdvMat.WindowUX.PlaceChild( frame, self, false ) end

	-- The action row is docked before the scroll panel, because a FILL child takes
	-- the whole remaining rect when it is laid out and would otherwise be sat
	-- on by anything docked to an edge after it.
	local actions = vgui.Create( "DPanel", frame )
	actions:Dock( BOTTOM )
	actions:SetTall( AdvMat.RowHeight() + 6 )
	actions:DockMargin( 0, 6, 0, 0 )
	actions.Paint = AdvMat.NoPaint

	local cancel = vgui.Create( "DButton", actions )
	cancel:Dock( RIGHT )
	cancel:SetWide( math.max( 100, AdvMat.FontSize * 7 ) )
	cancel:DockMargin( 6, 0, 0, 0 )
	cancel:SetText( "Cancel" )
	cancel.AdvMatI18NAutoWidth = true
	AdvMat.StyleButton( cancel )

	local ok = vgui.Create( "DButton", actions )
	ok:Dock( FILL )
	ok:SetText( "Add this step" )
	AdvMat.StyleButton( ok )

	local body = vgui.Create( "DScrollPanel", frame )
	body:Dock( FILL )
	body.Paint = AdvMat.Fill( T.Panel )

	OptSlider( body, "Shift the colour", -180, 180, 0, 0,
		"Rotates every colour around the rainbow.", function( _, v )
			op.hue = v
			Preview()
	end )
	OptSlider( body, "How colourful", 0, 3, 2, 1,
		"0 is grey, 1 is unchanged.", function( _, v )
			op.sat = v
			Preview()
	end )
	OptSlider( body, "Brightness (multiply)", 0, 3, 2, 1, nil, function( _, v )
		op.val = v
		Preview()
	end )
	OptSlider( body, "Brightness (lift)", -1, 1, 2, 0,
		"Adds or removes an even amount of light.", function( _, v )
			op.bright = v
			Preview()
	end )
	OptSlider( body, "Contrast", 0, 4, 2, 1, nil, function( _, v )
		op.contrast = v
		Preview()
	end )
	OptSlider( body, "Drain the colour out", 0, 1, 2, 0,
		"1 makes it completely grey.", function( _, v )
			op.desat = v
			Preview()
	end )
	OptCheck( body, "Turn it inside out (negative)", false, nil, function( _, v )
		op.invert = v
		Preview()
	end )

	OptCheck( body, "Apply gamma", op.gamma ~= nil,
		"Values above 1 brighten midtones; values below 1 darken them.", function( _, enabled )
			op.gamma = enabled and gammaValue or nil
			Preview()
	end )
	OptSlider( body, "Gamma", 0.1, 4, 2, gammaValue, nil, function( _, v )
		gammaValue = v
		if op.gamma ~= nil then
			op.gamma = v
			Preview()
		end
	end )

	OptCheck( body, "Posterize", op.posterize ~= nil,
		"Reduce each colour channel to a small number of levels.", function( _, enabled )
			op.posterize = enabled and posterizeValue or nil
			Preview()
	end )
	OptSlider( body, "Colour levels", 2, 64, 0, posterizeValue, nil, function( _, v )
		posterizeValue = math.floor( v + 0.5 )
		if op.posterize ~= nil then
			op.posterize = posterizeValue
			Preview()
		end
	end )

	OptCheck( body, "Apply threshold", op.threshold ~= nil,
		"Convert each pixel to black or white from its brightness at this cutoff.", function( _, enabled )
			op.threshold = enabled and thresholdValue or nil
			Preview()
	end )
	OptSlider( body, "Threshold", 0, 1, 2, thresholdValue, nil, function( _, v )
		thresholdValue = v
		if op.threshold ~= nil then
			op.threshold = v
			Preview()
		end
	end )

	if initialField then Preview() end
	cancel.DoClick = function() frame:Close() end
	ok.DoClick = function()
		if Finish( true ) then frame:Close() end
	end
end

---------------------------------------------------------------------------
-- Step list
---------------------------------------------------------------------------
--- The line above the list: how many brush strokes and other effects there
--- are, how close the other effects are to their limit, and how much of what
--- one save can send the recipe already uses.
function PANEL:RefreshStepSummary()
	local label = self.StepSummary
	if not IsValid( label ) then return end

	local strokes, _, others = OPS.Tally( self.Recipe.ops )
	local text = AdvMat.L( "texture.step_summary", {
		strokes = strokes, effects = others, max = OPS.MAX,
	} )

	local percent = self.WireBytes and math.floor( self.WireBytes / WireLimit() * 100 + 0.5 )
	if percent then
		text = text .. " " .. AdvMat.L( "texture.save_size", { percent = percent } )
	end

	label:SetText( text )
	label:SetTextColor( ( ( percent or 0 ) >= 80 or others >= OPS.MAX ) and T.Warn or T.TextDim )
end

--- Rebuild the step list after the recipe changed. `appended` says the only
--- change was one step added at the end.
---
--- A row per step was rebuilt for every change, which was harmless while there
--- could only be sixty-four of them and is not with hundreds of strokes: every
--- stroke paid for every stroke before it. A list nobody is looking at is now
--- rebuilt when its tab is opened, and an appended step adds only its own row.
function PANEL:RefreshSteps( appended )
	if not IsValid( self.Steps ) then return end

	self:RefreshStepSummary()
	self:ScheduleWireMeasure()

	if self.RightTab ~= "effects" then
		self.StepsDirty = true
		return
	end

	local ops = self.Recipe.ops

	if appended and not self.StepsDirty and #ops > 1
		and self.StepRowCount == #ops - 1 then
		self:AddStepRow( #ops )
		self.StepRowCount = #ops
		return
	end

	self.StepsDirty = nil
	self.StepRowCount = 0
	self.Steps:Clear()

	if #ops == 0 then
		local l = self.Steps:Add( "DLabel" )
		l:Dock( TOP )
		l:SetTall( AdvMat.RowHeight() * 3 )
		l:SetText( "  Nothing yet.\n  Pick a piece of the model, then paint or fill." )
		AdvMat.StyleLabel( l, "AdvMatText", T.TextFaint )
		l:SetWrap( true )
		return
	end

	for i = 1, #ops do self:AddStepRow( i ) end
	self.StepRowCount = #ops
end

--- One row of the step list. Its buttons read the recipe when clicked rather
--- than when built, because an appended row lives beside rows built earlier.
function PANEL:AddStepRow( i )
	local op   = self.Recipe.ops[ i ]
	local rowH = AdvMat.RowHeight()

	local row = self.Steps:Add( "DPanel" )
	row:Dock( TOP )
	row:SetTall( rowH + 8 )
	row:DockMargin( 0, 0, 4, 1 )

	row.Paint = function( pnl, w, h )
		local col = ( self.ViewStep == i ) and T.Selected
			or ( pnl:IsHovered() and T.RowHover )
			or ( ( i % 2 == 0 ) and T.RowAlt or T.Row )

		surface.SetDrawColor( col.r, col.g, col.b, 255 )
		surface.DrawRect( 0, 0, w, h )

		-- A guide line down the left, so the list reads as a sequence.
		surface.SetDrawColor( T.Accent.r, T.Accent.g, T.Accent.b, 120 )
		surface.DrawRect( 2, 0, 2, h )
	end

	local function Icon( text, wide, tip, fn )
		local b = vgui.Create( "DButton", row )
		b:Dock( RIGHT )
		b:SetWide( wide )
		b:SetText( text )
		b:SetFont( "AdvMatBold" )
		b:SetTextColor( T.TextDim )
		b:SetTooltip( tip )
		b.Paint = AdvMat.NoPaint
		b.DoClick = fn
		return b
	end

	Icon( "x", rowH, "Delete this step", function()
		self:PushUndo( "Delete effect" )
		table.remove( self.Recipe.ops, i )
		self.ViewStep = nil
		self:Recompose()
		self:RefreshSteps()
	end )

	Icon( "v", rowH * 0.7, "Move it later", function()
		local ops = self.Recipe.ops
		if i >= #ops then return end
		self:PushUndo( "Move effect later" )
		ops[ i ], ops[ i + 1 ] = ops[ i + 1 ], ops[ i ]
		self:Recompose()
		self:RefreshSteps()
	end )

	Icon( "^", rowH * 0.7, "Move it earlier", function()
		local ops = self.Recipe.ops
		if i <= 1 then return end
		self:PushUndo( "Move effect earlier" )
		ops[ i ], ops[ i - 1 ] = ops[ i - 1 ], ops[ i ]
		self:Recompose()
		self:RefreshSteps()
	end )

	local eye = vgui.Create( "DButton", row )
	eye:Dock( LEFT )
	eye:SetWide( rowH )
	eye:DockMargin( 6, 0, 0, 0 )
	eye:SetText( op.on == false and "-" or "o" )
	eye:SetFont( "AdvMatBold" )
	eye:SetTextColor( op.on == false and T.TextFaint or T.Accent )
	eye:SetTooltip( "Switch this step off without deleting it" )
	eye.Paint = AdvMat.NoPaint
	eye.DoClick = function()
		local step = self.Recipe.ops[ i ]
		if not step then return end
		self:PushUndo( "Toggle effect visibility" )
		if step.on == false then step.on = nil else step.on = false end
		self:Recompose()
		self:RefreshSteps()
	end

	local name = vgui.Create( "DLabel", row )
	name:Dock( FILL )
	name:DockMargin( 4, 0, 4, 0 )
	name:SetText( i .. ".  " .. AdvMat.Ops.Describe( op ) )
	AdvMat.StyleLabel( name, "AdvMatText",
		op.on == false and T.TextFaint or T.Text )
	name:SetTooltip( AdvMat.Ops.Describe( op ) )
end

---------------------------------------------------------------------------
-- Opening and applying
---------------------------------------------------------------------------

--- Clone the incoming recipe without confusing an intentional blank start
--- with a new editor session.  Kept separate from Setup so this lifecycle rule
--- can be regression-tested without constructing a full Derma window.
function PANEL:PrepareRecipe( recipe, ctx )
	local reopening = istable( recipe )
	local prepared = reopening and table.Copy( recipe ) or { kind = "edit", ops = {} }
	prepared.kind = "edit"
	prepared.ops  = prepared.ops or {}
	local layers = {}
	for _, raw in ipairs( istable( prepared.layers ) and prepared.layers or {} ) do
		if #layers >= OPS.MAX_LAYERS then break end
		local clean = OPS.SanitizeLayer( raw )
		if clean then layers[ #layers + 1 ] = clean end
	end
	prepared.layers = layers
	if not reopening then prepared.src = ctx and ctx.src or nil end
	if prepared.src == "" then prepared.src = nil end

	-- RTX's picker can hand us a logical Source/VTF name which the native writer
	-- cannot use directly. Keep the explicit copy intent on the recipe itself:
	-- the schema and bridge sanitize it again after this window has closed.
	-- Reassert it when reopening an RTX edit as well. Sanitisation omits this
	-- marker while real steps exist, but deleting the final step is still a real
	-- change back to the selected Source texture and must remain applicable.
	local sourceCopy = ctx and ( ctx.sourcecopy == true or ( ctx.rtx == true and reopening ) )

	-- The same holds for an imported image, wherever it is edited: with every
	-- step deleted it is still the picture the player imported, not nothing.
	if AdvMat.Import and AdvMat.Import.IsSource( prepared.src ) then sourceCopy = true end

	if prepared.src and sourceCopy then
		prepared.sourcecopy = true
	end
	return prepared
end

--- `ctx` carries what the editor needs to know about where this texture is
--- going: the model and sub-material so UV selection works, and the base key
--- values so the preview material looks like the real one.
function PANEL:Setup( param, recipe, ctx, done )
	self.Param = param or "$basetexture"
	self.Ctx   = ctx or {}
	self.Done  = done
	-- From here on use only the normalized values. Region pickers and external
	-- callers are allowed to omit either argument.
	param = self.Param
	ctx = self.Ctx
	self.Canvas:SetRTXCompatibility( RTXRenderContext( self.Ctx ) )

	-- A reopened source-less recipe intentionally starts from its stored fill;
	-- only a genuinely new session inherits the row's current source.
	local retainedOpaqueSemantics = istable( recipe ) and recipe.opaque == true
	self.Recipe = self:PrepareRecipe( recipe, self.Ctx )

	-- The canvas keeps its own copies of the shared tool settings.
	self.Canvas.Brush      = self.Brush
	self.Canvas.Hardness   = self.Hardness
	self.Canvas.Tolerance  = self.Tolerance
	self.Canvas.Contiguous = self.Contiguous ~= false

	-- Whether the source's alpha channel means transparency, decided by the
	-- material being edited. Without $translucent or $alphatest that channel is
	-- still read and saved because it commonly carries phong/reflection data;
	-- `opaque` only tells the canvas not to display those mask bytes as holes.
	--
	-- Infer this for new/legacy recipes only. A saved recipe's opaque bit records
	-- how its SOURCE alpha was interpreted. Saving an erase can subsequently add
	-- $translucent to the live material; recomputing from that modified material
	-- on reopen would reinterpret the original mask and change the same recipe's
	-- pixels and hash.
	local basekv = self.Ctx.basekv or {}
	local shows  = self.Ctx.showsalpha
	if shows == nil then
		shows = tobool( basekv[ "$translucent" ] ) or tobool( basekv[ "$alphatest" ] )
	end
	if not retainedOpaqueSemantics then
		shows = AdvMat.Gen.ShouldReadAlpha( self.Recipe.src, shows )
		self.Recipe.opaque = ( not shows ) and true or nil
	end

	if AdvMat.DebugTraceActive and AdvMat.DebugTraceEvent then
		AdvMat.DebugTraceEvent( "texture.setup", {
			parameter = self.Param,
			path = self.Recipe.src,
			matpath = self.Ctx.matpath,
			slot = self.Ctx.slot,
			model = self.Ctx.model,
			vmt_shows_alpha = self.Ctx.showsalpha,
			header_alpha = AdvMat.Gen.SourceHasAlpha( self.Recipe.src ),
			recipe_opaque = self.Recipe.opaque or false,
			preserves_source_mask = PreservesSourceMask( self.Recipe ),
		} )
	end

	-- The texture's own resolution is the right default for the finished image
	-- and the right resolution to look at it on. Saving a 2048 sheet back at 512
	-- throws three quarters of it away for no reason the user asked for, and a
	-- mask that is softer than the material under it is visible in game.
	self.NativeW, self.NativeH = AdvMat.Gen.SourceSize( self.Recipe.src, 512, 512 )

	-- A recipe that already names a size keeps it. Only a new one takes the
	-- source's, and only then does an oblong source make an oblong recipe.
	if not self.Recipe.size then
		self.Recipe.size = self.NativeW
		if self.NativeH ~= self.NativeW then self.Recipe.height = self.NativeH end
	end

	-- Composing is a pass over every pixel in Lua per step, so the working
	-- buffer is capped even when the texture is bigger. The canvas still shows
	-- the source at its own resolution.
	local rw, rh = AdvMat.Gen.Dims( self.Recipe )
	self.WorkW, self.WorkH = WorkDims( rw, rh )

	self:RefreshSizeBox()

	-- Remembered so "start from the texture that is there now" can get back to
	-- it after a detour through a blank image.
	self.OriginalSrc = self.Recipe.src or ctx.src

	self:SetTitle( "Texture editor - " .. param ..
		( self.Recipe.src and ( "  (" .. SourceLabel( self.Recipe.src ) .. ")" ) or "  (new image)" ) )

	-------------------------------------------------------------- the model
	if ctx.model and ctx.model ~= "" then
		self.ModelPanel:SetModel( ctx.model )
		AdvMat.AttachMMDPreview( self.ModelPanel.Entity )

		-- Nought is every bodygroup at its first option, which is what a model
		-- panel shows until somebody changes it.
		self.BodyMask = 0
		self.Group = AdvMat.Mesh.Group( ctx.model, ctx.matpath, ctx.slot or 0, self.BodyMask )

		-- Framing and skinning happen after ModelView.Refresh chooses the initial
		-- reference sequence below. FrameModel still retries until the model has
		-- genuinely loaded; running it before the sequence choice can permanently
		-- frame the camera around DModelPanel's arbitrary walk/idle pose.
		self.Yaw, self.Pitch = 180, 10

		self.Canvas:SetUVSource( ctx.model, ctx.matpath, ctx.slot or 0, self.BodyMask )
	end

	-- The model stays on screen even when its mesh could not be read. It is
	-- still the only thing that makes the flat sheet make sense, and the colour
	-- picker still works off it; only clicking to select is unavailable, and the
	-- label above it says so rather than the panel silently disappearing.
	local haveModel = ctx.model and ctx.model ~= ""
	self.HaveModel = haveModel and true or false

	self.ModelPanel:SetVisible( haveModel and true or false )

	if IsValid( self.ModelStrip ) then
		self.ModelStrip:SetVisible( haveModel and true or false )
	end

	-- Held rather than written straight into the label, because the playback
	-- controls have things of their own to say there and need something to put
	-- back afterwards.
	self.ModelHintBase =
		( not haveModel ) and "No model to show for this material."
		or self.Group and "Click the model to select that piece of the skin. "
		 .. "Right drag turns it, middle drag moves it, the wheel zooms."
		or  "This model's mesh could not be read, so clicking it cannot select "
		 .. "anything. The selection tools on the left still work."

	AdvMat.ModelView.Refresh( self )
	if haveModel then self:FrameModel() end

	self:Recompose()
	self:RefreshSteps()
	self:RefreshLayers()
	self:RefreshSelectionStatus()
	self:RefreshStartLabel()
	-- Init builds the restored tool against a placeholder blank recipe. Rebuild
	-- after the real source is installed so source-dependent controls (notably
	-- Keep shading versus paint blend mode) are correct on the first frame.
	self:BuildOptions()
	self:SetWorkspaceMode( self.RestoredWorkspaceMode or self.WorkspaceMode )
	self.RestoredWorkspaceMode = nil

	if self.Group and self.Group.clipped then
		self:Status( "This model is very dense, so only part of its outline is shown.", true )
	end

end

function PANEL:Apply()
	-- A texture dialog opened by the material editor belongs to that exact
	-- session.  OnClose normally removes us first; this guard covers forced panel
	-- removal and hot reloads without dispatching into a dead row context.
	if self.AdvMatHost ~= nil and ( not IsValid( self.AdvMatHost )
		or not isfunction( self.AdvMatHost.GetWorking ) ) then
		self:Status( "The material editor that opened this texture has closed. " ..
			"Reopen it on the target before applying these changes.", true )
		return
	end

	-- In region mode the whole window is a selection picker for a generator,
	-- and the selection is the answer rather than an edited image.
	if self.RegionMode then
		if self.Done then self.Done( self.Sel and table.Copy( self.Sel ) or nil ) end
		self:Close()
		return
	end

	local clean = AdvMat.Gen.Sanitize( self.Recipe )

	if not clean then
		self:Status( AdvMat.LText( "There is nothing to apply yet - add a step or layer first." ), true )
		return
	end

	-- Begin the exact multiplayer PNG preflight when the edit is adopted rather
	-- than making Save start it from zero. Dedicated-server transfers continue
	-- in the background while the material editor is open; listen-server hosts
	-- can be acknowledged immediately from their shared DATA cache.
	if AdvMat.Assets and isfunction( AdvMat.Assets.StageEdit ) then
		AdvMat.Assets.StageEdit( clean )
	end

	if self.Done then
		self.Done( clean, {
			-- Derive this from the current recipe snapshot. WantsTranslucent is
			-- only a one-shot explanatory notice; keeping it sticky after undo,
			-- delete or disable would reinterpret a restored shader mask as holes.
			translucent = AdvMat.Ops.MakesTransparency( clean ),
		} )
	end

	self:Close()
end

function PANEL:OnRemove()
	local dialog = self.AdjustDialog
	self.AdjustDialog = nil
	self:EndStepPreview( nil, false, nil, true )
	if IsValid( dialog ) then dialog:Remove() end

	if AdvMat.ModelView and AdvMat.ModelView.EndRTXDraw then
		AdvMat.ModelView.EndRTXDraw( self )
	end
	-- The lightweight region picker forces its own tool and dock layout. It
	-- must not replace the user's normal texture-editor workspace preferences.
	if not self.RegionMode then self:SavePrefs() end
	timer.Remove( "AdvMat.LayerControl." .. tostring( self ) )
	timer.Remove( "AdvMat.LayerList." .. tostring( self ) )
	timer.Remove( "AdvMat.WireMeasure." .. tostring( self ) )

	-- Nothing to put back: the image goes with the window.
	self.LiveStroke = nil
	self.RTXPreviewWanted = nil
	SafeDeletePreview( self.RTXPreviewFile )
	self.RTXPreviewFile = nil
	self.RTXPreviewImage = nil
	self.RTXPreviewTexture = nil

	if self.HighlightMesh then
		self.HighlightMesh:Destroy()
		self.HighlightMesh = nil
	end

	if AdvMat.TexEditor == self then AdvMat.TexEditor = nil end
end

vgui.Register( "AdvMatTexEditor", PANEL, "DFrame" )

-- Layer names and operation summaries contain runtime values (texture paths,
-- percentages), so the generic text translator cannot reconstruct their keys
-- after a language switch. Rebuild only those dynamic rows in the open editor.
if hook and hook.Add then
	-- render.Capture is only valid inside a render hook.  Keeping one ownerless
	-- hook avoids lifecycle races: it follows whichever texture editor is open
	-- and becomes a no-op immediately after that panel is removed.
	hook.Add( "PostRenderVGUI", "AdvMat.RTXTexturePreview", function()
		local frame = AdvMat.TexEditor
		if IsValid( frame ) and RTXRenderContext( frame.Ctx )
			and frame.PumpRTXPreviewSnapshot then
			frame:PumpRTXPreviewSnapshot()
		end
	end )

	hook.Add( "AdvMatLanguageChanged", "AdvMat.TextureEditorLanguage", function()
		local frame = AdvMat.TexEditor
		if not IsValid( frame ) then return end
		for key, button in pairs( frame.MenuKeyButtons or {} ) do
			if IsValid( button ) then
				button:SetText( AdvMat.L( key ) )
				button:SizeToContentsX( 20 )
			end
		end
		frame:RefreshLayers()
		frame:RefreshSteps()
		frame:RefreshHistory()
		frame:BuildOptions()
		frame:RefreshColourLabel()
	end )
end

---------------------------------------------------------------------------
-- Entry point
---------------------------------------------------------------------------

--- Open the texture editor.
---     param   the material parameter being edited, e.g. "$basetexture"
---     recipe  an existing edit recipe to reopen, or nil to start fresh
---     ctx     { src, model, matpath, slot, shader, basekv }
---     done    function( recipe, info )
function AdvMat.OpenTextureEditor( param, recipe, ctx, done )
	if IsValid( AdvMat.TexEditor ) then AdvMat.TexEditor:Remove() end

	local frame = vgui.Create( "AdvMatTexEditor" )
	AdvMat.TexEditor = frame
	frame.AdvMatHost = IsValid( ctx and ctx.host ) and ctx.host
		or ( IsValid( AdvMat.Editor ) and AdvMat.Editor or nil )

	frame:Setup( param, recipe, ctx, done )
	if AdvMat.WindowUX then
		AdvMat.WindowUX.PlaceChild( frame, frame.AdvMatHost, false )
	end
	return frame
end

--- The same window with the painting taken away, used to mark out where a
--- generator is allowed to write. Every selection tool, the model preview and
--- the two-way highlight all work exactly as they do when painting, which is
--- the point of reusing it rather than building a second, weaker picker.
function AdvMat.OpenRegionPicker( sel, ctx, done )
	local frame = AdvMat.OpenTextureEditor( ctx and ctx.param or "$basetexture", nil, ctx,
		function( region ) if done then done( region ) end end )

	if not IsValid( frame ) then return nil end

	frame.RegionMode = true
	frame:SetTitle( "Choose the area" )
	-- The ordinary editor restores its last workspace and dock visibility. A
	-- region picker always needs the selection tools, and (when available) both
	-- the texture and model views, regardless of those saved preferences.
	frame:SetDocksVisible( true )
	frame:SetWorkspaceMode( frame.HaveModel and "split" or "texture" )

	if sel then frame:SetSelection( sel ) end

	-- Painting a region would be meaningless, so those tools go away rather
	-- than sitting there doing nothing.
	for _, id in ipairs( { "paint", "erase", "fill", "gradient", "layer" } ) do
		local b = frame.ToolButtons[ id ]
		if IsValid( b ) then b:SetVisible( false ) end
	end

	if IsValid( frame.Steps )    then frame.Steps:SetVisible( false ) end
	if IsValid( frame.LayersHead ) then frame.LayersHead:SetVisible( false ) end
	if IsValid( frame.Layers ) then frame.Layers:SetVisible( false ) end
	if IsValid( frame.LayerActions ) then frame.LayerActions:SetVisible( false ) end
	if IsValid( frame.RightPanel ) then frame.RightPanel:SetVisible( false ) end
	if IsValid( frame.RightDockSizer ) then frame.RightDockSizer:SetVisible( false ) end
	if IsValid( frame.StartBtn ) then frame.StartBtn:SetVisible( false ) end
	if IsValid( frame.ApplyBtn ) then
		frame.ApplyBtn:SetText( "Use this area" )
		frame.ApplyBtn:SetTooltip( "Limit the generator to what you have selected." )
	end
	if IsValid( frame.FileApplyOption ) then frame.FileApplyOption:SetText( "Use this area" ) end

	frame:SetTool( "island" )
	frame:BuildOptions()
	frame:InvalidateLayout( true )

	return frame
end
