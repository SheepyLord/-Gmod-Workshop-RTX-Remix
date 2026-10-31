--[[---------------------------------------------------------------------------
	Advanced Material Editor - Source/VMT workspace for the RTX Remix editor

	Remix replaces captured textures with a hash-scoped PBR profile, but Source
	still evaluates the model's VMT before that capture.  This panel exposes that
	original material layer without putting VMT-shaped data in an RTX profile.

	The boundary is intentional:
	  * SourceWorking / SourceDirty / SourceUndo belong only to this panel.
	  * Save uses the ordinary AdvMat.RuleSet / RuleClear protocol.
	  * The parent RTX editor continues to own PBR profiles and their CAS store.

	RTX collapses equal material paths into one hash-oriented row. Source model
	rules remain slot-oriented, so the panel also offers the real engine slots
	which contributed to the selected row instead of silently editing the first.
-----------------------------------------------------------------------------]]

if not CLIENT then return end

AdvMat = AdvMat or {}

local T = AdvMat.Theme
local PREVIEW_DELAY = 0.06
local SAVE_CONFIRM_TIMEOUT = 10

local SCOPE_RANK = {
	[ AdvMat.SCOPE.ENTITY ]   = 3,
	[ AdvMat.SCOPE.MODEL ]    = 2,
	[ AdvMat.SCOPE.MATERIAL ] = 1,
}

local function L( key, fallback, variables )
	if AdvMat.I18N and AdvMat.I18N.HasKey and AdvMat.I18N.HasKey( key ) then
		return AdvMat.L( key, variables )
	end
	return fallback
end

local function GenOwnsAutoParam( gen, key )
	if key ~= "$translucent" then return false end
	for _, recipe in pairs( istable( gen ) and gen or {} ) do
		if istable( recipe ) and recipe.autotranslucent == true then return true end
	end
	return false
end

local function CopyRule( rule )
	if not istable( rule ) then return nil end
	local gen = rule.gen and table.Copy( rule.gen ) or nil
	local automatic = rule._autoParams and table.Copy( rule._autoParams ) or nil
	for _, recipe in pairs( istable( gen ) and gen or {} ) do
		if istable( recipe ) and recipe.autotranslucent == true then
			automatic = automatic or {}
			automatic[ "$translucent" ] = true
		end
	end
	return {
		mat    = AdvMat.NormalizeMaterial( rule.mat or "" ),
		shader = isstring( rule.shader ) and rule.shader or nil,
		params = table.Copy( rule.params or {} ),
		gen    = gen,
		-- Local editor metadata. It is intentionally excluded from network and
		-- signature canonicalisation, but undo must retain who owns an automatic
		-- companion flag such as $translucent.
		_autoParams = automatic,
	}
end

-- Compare editor working copies without their slot/scope envelope. This is
-- used both to protect edits made while a save is in flight and to detect two
-- real model slots trying to author different values into the same path-global
-- MATERIAL rule.
local function RuleBodySignature( rule )
	rule = istable( rule ) and rule or {}
	return AdvMat.Gen.Canonical( {
		mat = AdvMat.NormalizeMaterial( rule.mat or "" ),
		shader = isstring( rule.shader ) and rule.shader or "",
		params = AdvMat.SanitizeParams( rule.params ),
		gen = AdvMat.Gen.SanitizeAll( rule.gen ),
	} )
end

-- RuleApplied returns the authoritative rule after the server apply pass. Keep
-- the identity envelope in this signature so acknowledgements for duplicate
-- material slots and multi-scope removals cannot satisfy one another.
local function AppliedSignature( rule )
	if not istable( rule ) then return "" end
	return AdvMat.Gen.Canonical( {
		scope = tonumber( rule.scope ) or AdvMat.SCOPE.MODEL,
		key = tostring( rule.key or "" ),
		index = tonumber( rule.index ) or 0,
		body = RuleBodySignature( rule ),
	} )
end

local function ConVarBool( name, fallback )
	local value = GetConVar( name )
	return value and value:GetBool() or fallback
end

local function ShortMaterial( path )
	return string.match( path or "", "([^/]+)$" ) or path or ""
end

local PANEL = {}

function PANEL:Init()
	-- These names are deliberately different from the parent editor's PBR
	-- Working/Dirty/Undo fields.  A VMT rule and an RTX profile are not
	-- interchangeable working-copy formats.
	self.SourceWorking   = {}
	self.SourceSaved     = {}
	self.SourceDirty     = {}
	self.SourceUndo      = {}
	self.SourceLastUndo  = {}
	self.SourceHadRule   = {}
	self.SourceRuleScope = {}
	self.SourceBaseKV    = {}
	self.SourceBaseShader = {}
	self.SourceLoaded    = {}
	self.SourceMirrors   = {}
	self.SourcePreviewDirty = {}
	self.SourceRevision  = {}
	self.SourcePending   = {}
	self.SourceBatchID   = 0
	-- Per durable rule identity: the version (AdvMat.RuleToken) each loaded
	-- slot is based on, and what this tab last sent there. See SaveAll.
	self.SourceTokens    = {}
	self.SentTokens      = {}
	self.MaterialBySlot  = {}
	self.MaterialSlotGroups = {}
	self.SelectedByMaterial = {}
	self.ParamViews      = {}
	self.ParamCats       = {}
	self.Selected        = nil
	self.DisplayIndex    = nil
	self.CleanedUp       = false
	self.StatusText      = ""
	self.StatusProblem   = nil

	self.Paint = AdvMat.Fill( T.Panel )

	local rowH = AdvMat.RowHeight()

	self.Intro = vgui.Create( "DLabel", self )
	self.Intro:Dock( TOP )
	self.Intro:SetTall( rowH * 2 + 10 )
	self.Intro:DockMargin( 8, 6, 8, 4 )
	self.Intro:SetWrap( true )
	AdvMat.StyleLabel( self.Intro, "AdvMatText", T.TextDim )

	self.TargetRow = vgui.Create( "DPanel", self )
	self.TargetRow:Dock( TOP )
	self.TargetRow:SetTall( rowH + 8 )
	self.TargetRow:DockMargin( 8, 0, 8, 2 )
	self.TargetRow.Paint = AdvMat.NoPaint

	self.RevertButton = vgui.Create( "DButton", self.TargetRow )
	self.RevertButton:Dock( RIGHT )
	self.RevertButton:SetWide( math.max( 150, AdvMat.FontSize * 9 ) )
	self.RevertButton:DockMargin( 6, 0, 0, 0 )
	AdvMat.StyleButton( self.RevertButton )
	self.RevertButton.DoClick = function() self:RevertSelected() end

	self.LiveCheck = vgui.Create( "DCheckBoxLabel", self.TargetRow )
	self.LiveCheck:Dock( RIGHT )
	self.LiveCheck:DockMargin( 10, 4, 10, 4 )
	self.LiveCheck:SetValue( ConVarBool( "advmateditor_livepreview", true ) and 1 or 0 )
	self.LiveCheck:SetConVar( "advmateditor_livepreview" )
	AdvMat.StyleCheck( self.LiveCheck, "Live Source world preview" )
	self.LiveCheck.OnChange = function() self:QueuePreview() end

	self.SlotBox = vgui.Create( "DComboBox", self.TargetRow )
	self.SlotBox:Dock( FILL )
	self.SlotBox:SetSortItems( false )
	AdvMat.StyleCombo( self.SlotBox )
	self.SlotBox.OnSelect = function( _, _, _, slot )
		if self.SettingSlot then return end
		self:SelectSlot( tonumber( slot ) )
	end

	self.ScopeRow = vgui.Create( "DPanel", self )
	self.ScopeRow:Dock( TOP )
	self.ScopeRow:SetTall( rowH + 8 )
	self.ScopeRow:DockMargin( 8, 0, 8, 2 )
	self.ScopeRow.Paint = AdvMat.NoPaint

	self.ScopeLabel = vgui.Create( "DLabel", self.ScopeRow )
	self.ScopeLabel:Dock( LEFT )
	self.ScopeLabel:SetWide( math.max( 145, AdvMat.FontSize * 9 ) )
	self.ScopeLabel:SetContentAlignment( 4 )
	AdvMat.StyleLabel( self.ScopeLabel, "AdvMatBold", T.Text )

	self.ScopeBox = vgui.Create( "DComboBox", self.ScopeRow )
	self.ScopeBox:Dock( LEFT )
	self.ScopeBox:SetWide( math.max( 250, AdvMat.FontSize * 16 ) )
	self.ScopeBox:SetSortItems( false )
	AdvMat.StyleCombo( self.ScopeBox )
	self.ScopeBox.OnSelect = function( _, _, _, scope )
		if self.SettingScope then return end
		scope = tonumber( scope ) or AdvMat.SCOPE.MODEL
		RunConsoleCommand( "advmateditor_scope", tostring( scope ) )
		self:UpdateScopeHint()
		-- Moving an existing rule to a different save target is itself an edit;
		-- it must be saveable without forcing an unrelated slider change.
		local slot = self.Selected
		local working = slot ~= nil and self.SourceWorking[ slot ] or nil
		if slot ~= nil and not AdvMat.RuleIsEmpty( working )
			and self.SourceRuleScope[ slot ] ~= scope then
			self:BumpRevision( slot )
			self.SourceDirty[ slot ] = true
			self:SetStatus( L( "rtx.source.unsaved",
				"Unsaved Source material changes" ) )
			self:NotifyParentState()
		end
	end

	self.ScopeHint = vgui.Create( "DLabel", self.ScopeRow )
	self.ScopeHint:Dock( FILL )
	self.ScopeHint:DockMargin( 10, 0, 0, 0 )
	self.ScopeHint:SetWrap( true )
	AdvMat.StyleLabel( self.ScopeHint, "AdvMatSmall", T.TextDim )

	self.ParamHead = vgui.Create( "DPanel", self )
	self.ParamHead:Dock( TOP )
	self.ParamHead:SetTall( rowH * 2 + 12 )
	self.ParamHead:DockMargin( 8, 2, 8, 4 )
	self.ParamHead.Paint = AdvMat.NoPaint

	self.Warning = vgui.Create( "DLabel", self.ParamHead )
	self.Warning:Dock( TOP )
	self.Warning:SetTall( rowH )
	self.Warning:SetText( "" )
	AdvMat.StyleLabel( self.Warning, "AdvMatSmall", T.Warn )

	local shaderRow = vgui.Create( "DPanel", self.ParamHead )
	shaderRow:Dock( FILL )
	shaderRow.Paint = AdvMat.NoPaint

	self.ShaderLabel = vgui.Create( "DLabel", shaderRow )
	self.ShaderLabel:Dock( LEFT )
	self.ShaderLabel:SetWide( math.max( 75, AdvMat.FontSize * 4 ) )
	AdvMat.StyleLabel( self.ShaderLabel, "AdvMatText", T.TextDim )

	self.ShaderBox = vgui.Create( "DComboBox", shaderRow )
	self.ShaderBox:Dock( LEFT )
	self.ShaderBox:SetWide( math.max( 220, AdvMat.FontSize * 13 ) )
	AdvMat.StyleCombo( self.ShaderBox )
	self.ShaderBox.OnSelect = function( _, _, shader )
		local slot = self.Selected
		if self.SettingShader or slot == nil then return end
		local base = self.SourceBaseShader[ slot ] or self:GetActiveShader( slot )
		local working = self:GetWorking( slot, true )
		local nextShader = shader ~= base and shader or nil
		if working.shader == nextShader then return end
		self:RememberUndo( slot )
		working.shader = nextShader
		self:MarkChanged( slot )
		self:BuildParamList()
	end

	self.ShowAll = vgui.Create( "DCheckBoxLabel", shaderRow )
	self.ShowAll:Dock( RIGHT )
	self.ShowAll:DockMargin( 6, 3, 0, 3 )
	self.ShowAll:SetValue( ConVarBool( "advmateditor_showall", true ) and 1 or 0 )
	self.ShowAll:SetConVar( "advmateditor_showall" )
	AdvMat.StyleCheck( self.ShowAll, "Show every supported parameter" )
	self.ShowAll.OnChange = function() self:BuildParamList() end

	self.Filter = vgui.Create( "DTextEntry", shaderRow )
	self.Filter:Dock( FILL )
	self.Filter:DockMargin( 6, 0, 6, 0 )
	self.Filter:SetUpdateOnType( true )
	self.Filter.OnValueChange = function() self:BuildParamList() end
	AdvMat.StyleEntry( self.Filter )

	self.Scroll = vgui.Create( "DScrollPanel", self )
	self.Scroll:Dock( FILL )
	self.Scroll:DockMargin( 8, 0, 2, 4 )
	self.Scroll.Paint = AdvMat.Fill( T.Panel )

	self.LanguageHookID = "AdvMat.RTXSourceLanguage." .. tostring( self )
	hook.Add( "AdvMatLanguageChanged", self.LanguageHookID, function()
		if not IsValid( self ) then
			hook.Remove( "AdvMatLanguageChanged", self.LanguageHookID )
			return
		end
		self:RefreshLanguage()
	end )
	self.RulesHookID = "AdvMat.RTXSourceRules." .. tostring( self )
	hook.Add( "AdvMatRulesChanged", self.RulesHookID, function( rule )
		if IsValid( self ) then self:OnRulesChanged( rule ) end
	end )
	self.AppliedHookID = "AdvMat.RTXSourceApplied." .. tostring( self )
	hook.Add( "AdvMatRuleApplied", self.AppliedHookID, function( rule, info )
		if IsValid( self ) then self:OnRuleApplied( rule, info ) end
	end )
	self.RejectedHookID = "AdvMat.RTXSourceRejected." .. tostring( self )
	hook.Add( "AdvMatRuleRejected", self.RejectedHookID, function( info )
		if IsValid( self ) then self:OnRuleRejected( info ) end
	end )
	self.PersistedHookID = "AdvMat.RTXSourcePersisted." .. tostring( self )
	hook.Add( "AdvMatRulesPersisted", self.PersistedHookID, function( revision )
		if IsValid( self ) then self:OnRulesPersisted( revision ) end
	end )
	self.GeneratedHookID = "AdvMat.RTXSourceGenerated." .. tostring( self )
	hook.Add( "AdvMatGenerated", self.GeneratedHookID, function()
		if not IsValid( self ) then return end
		for slot in pairs( self.SourceWorking ) do
			self.SourcePreviewDirty[ slot ] = true
		end
	end )
	-- The texture rows gain or lose Import as Model Hotloader's file access
	-- comes and goes, exactly as in the vanilla editor.
	self.ImportHookID = "AdvMat.RTXSourceImport." .. tostring( self )
	hook.Add( "AdvMatImportChanged", self.ImportHookID, function()
		if IsValid( self ) then self:BuildParamList() end
	end )

	self:RefreshLanguage()
	self:BuildParamList()
end

function PANEL:SetParentEditor( editor )
	self.ParentEditor = editor
end

function PANEL:SetStatus( text, problem )
	self.StatusText = text or ""
	self.StatusProblem = problem
	local parent = self.ParentEditor
	if IsValid( parent ) and parent.IsSourceTabActive
		and parent:IsSourceTabActive() and parent.SetSourceStatus then
		parent:SetSourceStatus( self.StatusText, problem )
	end
end

function PANEL:GetStatus()
	return self.StatusText or "", self.StatusProblem
end

function PANEL:RefreshLanguage()
	self.Intro:SetText( L( "rtx.source.intro",
		"Edit the original Source VMT parameters. Source overrides are saved separately from RTX Remix profiles; many Source shading parameters do not affect Remix." ) )
	self.RevertButton:SetText( L( "rtx.source.revert", "Revert Source changes" ) )
	self.LiveCheck:SetText( L( "rtx.source.live_preview", "Live Source world preview" ) )
	self.ScopeLabel:SetText( L( "rtx.source.save_target", "Source save target" ) )
	self.ShaderLabel:SetText( L( "editor.shader", "Shader" ) )
	self.ShowAll:SetText( L( "editor.show_all", "Show every supported parameter" ) )
	self.Filter:SetPlaceholderText( L( "editor.search",
		"Search parameters by name or description..." ) )
	self:PopulateScopeChoices()
	self:PopulateSlotChoices()
	self:UpdateScopeHint()
	self:BuildParamList()
end

function PANEL:PopulateScopeChoices()
	if not IsValid( self.ScopeBox ) then return end
	local selected = self:CurrentScope()
	self.SettingScope = true
	self.ScopeBox:Clear()
	if self.WorldMat then
		self.ScopeBox:AddChoice( L( "editor.scope_surface",
			"This map surface material" ), AdvMat.SCOPE.WORLD, true )
		self.ScopeBox:SetEnabled( false )
	else
		self.ScopeBox:AddChoice( L( "editor.scope_model",
			"Every prop with this model" ), AdvMat.SCOPE.MODEL )
		self.ScopeBox:AddChoice( L( "editor.scope_entity",
			"This entity only" ), AdvMat.SCOPE.ENTITY )
		self.ScopeBox:AddChoice( L( "editor.scope_material",
			"Every material with this path" ), AdvMat.SCOPE.MATERIAL )
		self.ScopeBox:SetEnabled( true )
		local choice = selected == AdvMat.SCOPE.MODEL and 1
			or selected == AdvMat.SCOPE.ENTITY and 2 or 3
		self.ScopeBox:ChooseOptionID( choice )
	end
	self.SettingScope = false
end

function PANEL:UpdateScopeHint()
	if not IsValid( self.ScopeHint ) then return end
	local scope = self:CurrentScope()
	local keys = {
		[ AdvMat.SCOPE.ENTITY ] = { "rtx.source.scope_entity_hint",
			"Save the Source/VMT override only on this entity. The RTX profile still uses its captured texture-hash scope." },
		[ AdvMat.SCOPE.MODEL ] = { "rtx.source.scope_model_hint",
			"Save the Source/VMT override for every prop using this model. The RTX profile still uses its captured texture-hash scope." },
		[ AdvMat.SCOPE.MATERIAL ] = { "rtx.source.scope_material_hint",
			"Save the Source/VMT override for every material with this path. The RTX profile still uses its captured texture-hash scope." },
		[ AdvMat.SCOPE.WORLD ] = { "rtx.source.scope_surface_hint",
			"Save the Source/VMT override for this map surface material. The RTX profile still uses its captured texture-hash scope." },
	}
	local spec = keys[ scope ] or keys[ AdvMat.SCOPE.MODEL ]
	self.ScopeHint:SetText( L( spec[ 1 ], spec[ 2 ] ) )
end

function PANEL:ResetSourceState()
	self.SourceWorking   = {}
	self.SourceSaved     = {}
	self.SourceDirty     = {}
	self.SourceUndo      = {}
	self.SourceLastUndo  = {}
	self.SourceHadRule   = {}
	self.SourceRuleScope = {}
	self.SourceBaseKV    = {}
	self.SourceBaseShader = {}
	self.SourceLoaded    = {}
	self.SourceMirrors   = {}
	self.SourcePreviewDirty = {}
	self.SourceRevision  = {}
	for _, records in pairs( self.SourcePending or {} ) do
		for _, record in ipairs( records ) do
			if record.timer then timer.Remove( record.timer ) end
		end
	end
	self.SourcePending   = {}
	self.SourceTokens    = {}
	self.SentTokens      = {}
	self.AwaitDisk       = nil
	self.ParamViews      = {}
	self.SelectedByMaterial = {}
	self.Selected        = nil
	self.DisplayIndex    = nil
end

function PANEL:SetTargetEntity( entity, materials, slotGroups )
	if not IsValid( entity ) then return false end
	self.Entity = entity
	self.WorldMat = nil
	self.TargetModel = AdvMat.NormalizeModel( entity:GetModel() or "" )
	self.MaterialBySlot = {}
	for index, material in ipairs( materials or entity:GetMaterials() or {} ) do
		self.MaterialBySlot[ index - 1 ] = AdvMat.NormalizeMaterial( material )
	end
	self.MaterialSlotGroups = slotGroups or {}
	self:ResetSourceState()
	self:PopulateScopeChoices()
	return true
end

function PANEL:SetWorldMaterial( material, slotGroups )
	material = AdvMat.NormalizeMaterial( material or "" )
	if material == "" then return false end
	self.Entity = nil
	self.WorldMat = material
	self.TargetModel = ""
	self.MaterialBySlot = { [ 0 ] = material }
	self.MaterialSlotGroups = slotGroups or { [ 0 ] = { 0 } }
	self:ResetSourceState()
	self:PopulateScopeChoices()
	return true
end

function PANEL:SetMaterialSelection( displayIndex, material, slots )
	displayIndex = tonumber( displayIndex )
	material = AdvMat.NormalizeMaterial( material or "" )
	if displayIndex == nil or material == "" then
		self.DisplayIndex = nil
		self.Selected = nil
		self:PopulateSlotChoices()
		self:BuildParamList()
		return false
	end

	self.DisplayIndex = displayIndex
	self.DisplayMaterial = material
	self.MaterialSlotGroups[ displayIndex ] = slots or self.MaterialSlotGroups[ displayIndex ] or { displayIndex }
	local group = self.MaterialSlotGroups[ displayIndex ]
	local selected = self.SelectedByMaterial and self.SelectedByMaterial[ material ] or nil
	if not table.HasValue( group, selected ) then selected = group[ 1 ] end
	self:PopulateSlotChoices( selected )
	return self:SelectSlot( selected )
end

function PANEL:PopulateSlotChoices( selected )
	if not IsValid( self.SlotBox ) then return end
	local group = self.DisplayIndex ~= nil and self.MaterialSlotGroups[ self.DisplayIndex ] or nil
	selected = tonumber( selected ) or self.Selected
	self.SettingSlot = true
	self.SlotBox:Clear()
	if not group or #group == 0 then
		self.SlotBox:SetValue( L( "rtx.source.select_material",
			"Select a sub-material on the left to edit its Source parameters." ) )
		self.SlotBox:SetEnabled( false )
	else
		for option, slot in ipairs( group ) do
			local material = self.MaterialBySlot[ slot ] or self.DisplayMaterial or ""
			local label = L( "rtx.source.slot", "Source slot {{slot}}: {{material}}", {
				slot = slot, material = AdvMat.MaterialDisplayName( material, self.Entity or self.TargetModel, slot ),
			} )
			self.SlotBox:AddChoice( label, slot, slot == selected )
			if slot == selected then self.SlotBox:ChooseOptionID( option ) end
		end
		self.SlotBox:SetEnabled( #group > 1 )
	end
	self.SettingSlot = false
end

function PANEL:SelectSlot( slot )
	slot = tonumber( slot )
	if slot == nil or not self.MaterialBySlot[ slot ] then return false end
	self.Selected = slot
	self.SelectedByMaterial = self.SelectedByMaterial or {}
	self.SelectedByMaterial[ self.MaterialBySlot[ slot ] ] = slot
	self:LoadSlot( slot )
	self:PopulateSlotChoices( slot )
	self:BuildParamList()
	self:SetStatus( self.SourceDirty[ slot ]
		and L( "rtx.source.unsaved", "Unsaved Source material changes" ) or "" )
	self:NotifyParentState()
	return true
end

--- The rule identities a Save of `slot` could write to, as RuleID strings.
function PANEL:SlotIdentities( slot )
	local material = self.MaterialBySlot[ slot ] or ""
	if self.WorldMat then return { AdvMat.RuleID( AdvMat.SCOPE.WORLD, self.WorldMat ) } end

	local ids = {
		AdvMat.RuleID( AdvMat.SCOPE.MODEL, self.TargetModel or "", slot ),
		AdvMat.RuleID( AdvMat.SCOPE.MATERIAL, material ),
	}
	if IsValid( self.Entity ) then
		ids[ #ids + 1 ] = AdvMat.RuleID( AdvMat.SCOPE.ENTITY, self.Entity:EntIndex(), slot )
	end
	return ids
end

--- What the mirror holds at one identity now, as a version token.
local function MirrorToken( id )
	local C = AdvMat.Client
	local entIndex, index = string.match( id, "^ent:(%-?%d+):(%d+)$" )
	if entIndex then
		local set = C.EntRules and C.EntRules[ tonumber( entIndex ) ]
		return AdvMat.RuleToken( set and set[ tonumber( index ) ] )
	end
	return AdvMat.RuleToken( C.Rules and C.Rules[ id ] )
end

function PANEL:LoadSlot( slot )
	if self.SourceLoaded[ slot ] then return end
	self.SourceLoaded[ slot ] = true

	-- The version every identity this slot could be saved to is based on.
	self.SourceTokens = self.SourceTokens or {}
	for _, id in ipairs( self:SlotIdentities( slot ) ) do
		self.SourceTokens[ id ] = MirrorToken( id )
	end

	local material = self.MaterialBySlot[ slot ] or ""
	local rule
	if self.WorldMat then
		rule = AdvMat.Client.Rules[ AdvMat.RuleID( AdvMat.SCOPE.WORLD, self.WorldMat ) ]
	elseif IsValid( self.Entity ) then
		rule = AdvMat.Client.Resolve( self.Entity, slot, material )
	end
	if not rule or AdvMat.RuleIsEmpty( rule ) then return end
	local working = CopyRule( rule )
	self.SourceWorking[ slot ] = working
	self.SourceSaved[ slot ] = CopyRule( working )
	self.SourceHadRule[ slot ] = true
	self.SourceRuleScope[ slot ] = rule.scope
	self.SourcePreviewDirty[ slot ] = true
end

function PANEL:GetWorking( slot, create )
	slot = tonumber( slot ) or self.Selected
	if slot == nil then return nil end
	self:LoadSlot( slot )
	local working = self.SourceWorking[ slot ]
	if working or not create then return working end
	working = {
		mat = AdvMat.NormalizeMaterial( self.MaterialBySlot[ slot ] or "" ),
		shader = nil,
		params = {},
		gen = nil,
	}
	self.SourceWorking[ slot ] = working
	self.SourcePreviewDirty[ slot ] = true
	return working
end

function PANEL:GetBaseKV( slot )
	if self.SourceBaseKV[ slot ] == nil then
		local kv, shader = AdvMat.Apply.ReadBase( self.MaterialBySlot[ slot ] or "" )
		self.SourceBaseKV[ slot ] = kv or false
		self.SourceBaseShader[ slot ] = shader or "VertexLitGeneric"
	end
	return self.SourceBaseKV[ slot ] or {}
end

function PANEL:GetActiveShader( slot )
	local working = self.SourceWorking[ slot ]
	if working and working.shader and working.shader ~= "" then return working.shader end
	self:GetBaseKV( slot )
	return self.SourceBaseShader[ slot ] or "VertexLitGeneric"
end

function PANEL:RememberUndo( slot )
	slot = tonumber( slot ) or self.Selected
	if slot == nil then return end
	local now = RealTime()
	local last = self.SourceLastUndo[ slot ]
	if last and now - last <= 0.3 then return end
	local stack = self.SourceUndo[ slot ] or {}
	stack[ #stack + 1 ] = CopyRule( self.SourceWorking[ slot ] ) or false
	if #stack > 40 then table.remove( stack, 1 ) end
	self.SourceUndo[ slot ] = stack
	self.SourceLastUndo[ slot ] = now
end

function PANEL:NotifyParentState()
	local parent = self.ParentEditor
	if not IsValid( parent ) then return end
	if parent.UpdateMarkers then parent:UpdateMarkers() end
	if parent.UpdateActionMode then parent:UpdateActionMode() end
end

function PANEL:HasPending( slot )
	self.SourcePending = self.SourcePending or {}
	if slot ~= nil then
		local records = self.SourcePending[ tonumber( slot ) ]
		return records ~= nil and #records > 0
	end
	for _, records in pairs( self.SourcePending ) do
		if #records > 0 then return true end
	end
	return false
end

function PANEL:HasOpenOwnedDialog()
	for _, name in ipairs( { "TexPicker", "TexEditor", "SurfaceDialog", "GenDialog" } ) do
		local child = AdvMat[ name ]
		if IsValid( child ) and child.AdvMatHost == self then return true end
	end
	return false
end

function PANEL:BeginPendingBatch( kind )
	self.SourceBatchID = ( self.SourceBatchID or 0 ) + 1
	return {
		id = self.SourceBatchID,
		kind = kind,
		remaining = 0,
		failed = false,
		slotRemaining = {},
		slotFailed = {},
	}
end

function PANEL:TrackPending( slot, payload, batch, snapshot, remove )
	self.SourcePending = self.SourcePending or {}
	local records = self.SourcePending[ slot ] or {}
	local record = {
		slot = slot,
		payload = table.Copy( payload ),
		signature = AppliedSignature( payload ),
		bodySignature = RuleBodySignature( snapshot ),
		snapshot = CopyRule( snapshot ),
		revision = self.SourceRevision and self.SourceRevision[ slot ] or 0,
		remove = remove == true,
		batch = batch,
	}
	record.timer = "AdvMat.RTXSourceSave." .. tostring( self ) .. "."
		.. tostring( batch.id ) .. "." .. tostring( slot ) .. "." .. tostring( #records + 1 )
	records[ #records + 1 ] = record
	self.SourcePending[ slot ] = records
	batch.remaining = batch.remaining + 1
	batch.slotRemaining[ slot ] = ( batch.slotRemaining[ slot ] or 0 ) + 1
	timer.Create( record.timer, SAVE_CONFIRM_TIMEOUT, 1, function()
		if IsValid( self ) then self:FinishPending( record, false ) end
	end )
	return record
end

function PANEL:FinishPending( record, success )
	if not record or record.done then return end
	record.done = true
	if record.timer then timer.Remove( record.timer ) end

	local slot, batch = record.slot, record.batch
	local records = self.SourcePending[ slot ] or {}
	for i = #records, 1, -1 do
		if records[ i ] == record then table.remove( records, i ) break end
	end
	if #records == 0 then self.SourcePending[ slot ] = nil end

	batch.remaining = math.max( 0, batch.remaining - 1 )
	batch.slotRemaining[ slot ] = math.max( 0,
		( batch.slotRemaining[ slot ] or 1 ) - 1 )
	if not success then
		batch.failed = true
		batch.slotFailed[ slot ] = true
	elseif record.persist == 1 then
		-- Applied, but only on the server's disk once it says so.
		batch.diskRevision = math.max( batch.diskRevision or 0, record.serverRevision or 0 )
	end

	-- A removal spans entity/model/material scopes. Finalize its local slot only
	-- after every acknowledgement, otherwise an earlier clear can make the UI
	-- look complete while a later scope was rejected or rate-limited.
	if batch.slotRemaining[ slot ] == 0 then
		local clearCommittedPreview = false
		if not batch.slotFailed[ slot ] then
			if record.remove then
				self.SourceSaved[ slot ] = nil
				self.SourceHadRule[ slot ] = nil
				self.SourceRuleScope[ slot ] = nil
				local unchanged = ( self.SourceRevision and self.SourceRevision[ slot ] or 0 ) == record.revision
					and RuleBodySignature( self.SourceWorking[ slot ] ) == record.bodySignature
				if unchanged then
					self.SourceWorking[ slot ] = nil
					self.SourceDirty[ slot ] = nil
					self.SourceUndo[ slot ] = {}
					self.SourceLastUndo[ slot ] = nil
					clearCommittedPreview = true
				else
					self.SourceDirty[ slot ] = true
				end
			else
				self.SourceSaved[ slot ] = CopyRule( record.snapshot )
				self.SourceHadRule[ slot ] = true
				self.SourceRuleScope[ slot ] = record.payload.scope
				if ( self.SourceRevision and self.SourceRevision[ slot ] or 0 ) == record.revision
					and RuleBodySignature( self.SourceWorking[ slot ] ) == record.bodySignature then
					self.SourceDirty[ slot ] = nil
					self.SourceUndo[ slot ] = {}
					self.SourceLastUndo[ slot ] = nil
				end
			end
		end
		self.SourcePreviewDirty[ slot ] = true
		-- RuleClear refreshes the resolved rule before this client-side preview is
		-- released. Clear it only after the complete removal batch is confirmed,
		-- and never clear a newer edit made against the same slot.
		if clearCommittedPreview then
			if IsValid( self.Entity ) then
				AdvMat.Client.ClearPreview( self.Entity, slot )
			elseif self.WorldMat then
				AdvMat.Apply.RefreshWorld()
			end
		end
	end

	if batch.remaining == 0 then
		if batch.failed then
			-- A refusal says why; only silence is reported as a missing confirmation.
			self:SetStatus( batch.problem or L( "rtx.source.save_timeout",
				"The server did not confirm every Source change. Unconfirmed edits remain unsaved; retry." ), true )
		elseif self:IsDirty() then
			-- The acknowledged snapshot was saved, but the user changed a control
			-- while it was in flight. Preserve and report that newer working copy.
			self:SetStatus( L( "rtx.source.unsaved",
				"Unsaved Source material changes" ), "warning" )
			surface.PlaySound( "buttons/button15.wav" )
		elseif batch.diskRevision then
			-- Live in the world now; "saved" waits for AdvMat.RulePersisted.
			self.AwaitDisk = { revision = batch.diskRevision, kind = batch.kind }
			self:SetStatus( L( "rtx.source.saving_disk",
				"Source material overrides applied; the server is writing them to disk…" ), "warning" )
		elseif batch.kind == "remove" then
			self:SetStatus( L( "rtx.source.removed", "Source override removed." ) )
			surface.PlaySound( "buttons/button15.wav" )
		else
			self:SetStatus( L( "rtx.source.saved", "Source material overrides saved." ) )
			surface.PlaySound( "buttons/button15.wav" )
		end
	end

	if slot == self.Selected and batch.slotRemaining[ slot ] == 0 then
		self:BuildParamList()
	end
	self:NotifyParentState()
end

function PANEL:OnRuleApplied( rule, info )
	local signature = AppliedSignature( rule )
	if signature == "" then return end
	for _, records in pairs( self.SourcePending ) do
		for _, record in ipairs( records ) do
			if record.signature == signature then
				if istable( info ) then
					-- `revision` on a record is this tab's own edit counter.
					record.persist        = tonumber( info.persist )
					record.serverRevision = tonumber( info.revision )
				end
				self:FinishPending( record, true )
				return
			end
		end
	end
end

--- The server refused one of this tab's saves. Fail its pending record now
--- instead of at the timeout, saying why. For a conflict, adopt the version
--- stored now so that saving again deliberately replaces it.
function PANEL:OnRuleRejected( info )
	if not istable( info ) then return end

	local id   = AdvMat.RuleID( tonumber( info.scope ) or AdvMat.SCOPE.MODEL, info.key, info.index )
	local sent = self.SentTokens and self.SentTokens[ id ]
	if not sent or sent.token ~= info.token then return end

	self.SentTokens[ id ] = nil
	self.SourceTokens = self.SourceTokens or {}
	self.SourceTokens[ id ] = isstring( info.current ) and info.current or ""

	for _, records in pairs( self.SourcePending or {} ) do
		for _, record in ipairs( records ) do
			local payload = record.payload or {}
			local recordID = AdvMat.RuleID( tonumber( payload.scope ) or AdvMat.SCOPE.MODEL,
				payload.key, payload.index )
			if not record.done and recordID == id then
				record.batch.problem = info.conflict
					and L( "rtx.source.conflict",
						"Not saved: somebody else changed this Source material after you loaded it. Save again to replace their change, or reopen the editor to load it." )
					or L( "rtx.source.rejected", "The server refused the Source change: {{reason}}",
						{ reason = tostring( info.reason or "" ) } )
				self:FinishPending( record, false )
				return
			end
		end
	end
end

--- The server has written its database up to `revision`.
function PANEL:OnRulesPersisted( revision )
	local wait = self.AwaitDisk
	if not wait or ( tonumber( revision ) or 0 ) < wait.revision then return end

	self.AwaitDisk = nil
	if self:IsDirty() or self:HasPending() then return end

	if wait.kind == "remove" then
		self:SetStatus( L( "rtx.source.removed", "Source override removed." ) )
	else
		self:SetStatus( L( "rtx.source.saved", "Source material overrides saved." ) )
	end
	surface.PlaySound( "buttons/button15.wav" )
end

function PANEL:RuleAffectsSlot( rule, slot )
	if not istable( rule ) then return true end
	local scope = tonumber( rule.scope ) or AdvMat.SCOPE.MODEL
	if scope == AdvMat.SCOPE.WORLD then
		return self.WorldMat ~= nil
			and AdvMat.NormalizeMaterial( rule.key or "" ) == self.WorldMat
	end
	if self.WorldMat then return false end
	if scope == AdvMat.SCOPE.ENTITY then
		return IsValid( self.Entity )
			and tonumber( rule.key ) == self.Entity:EntIndex()
			and tonumber( rule.index ) == slot
	end
	if scope == AdvMat.SCOPE.MODEL then
		return AdvMat.NormalizeModel( rule.key or "" ) == self.TargetModel
			and tonumber( rule.index ) == slot
	end
	return scope == AdvMat.SCOPE.MATERIAL
		and AdvMat.NormalizeMaterial( rule.key or "" )
			== AdvMat.NormalizeMaterial( self.MaterialBySlot[ slot ] or "" )
end

function PANEL:ReloadCleanSlot( slot )
	if self.SourceDirty[ slot ] or self:HasPending( slot ) then return false end
	self.SourceLoaded[ slot ] = nil
	self.SourceWorking[ slot ] = nil
	self.SourceSaved[ slot ] = nil
	self.SourceHadRule[ slot ] = nil
	self.SourceRuleScope[ slot ] = nil
	self.SourceUndo[ slot ] = {}
	self.SourceLastUndo[ slot ] = nil
	self.SourcePreviewDirty[ slot ] = true
	self:LoadSlot( slot )
	return true
end

function PANEL:OnRulesChanged( rule )
	local selectedChanged = false
	local reapplyWorldPreview = false
	for slot in pairs( self.MaterialBySlot ) do
		if self:RuleAffectsSlot( rule, slot ) then
			if self.WorldMat and self.SourceDirty[ slot ] then
				-- World previews are direct material mutations rather than entries in
				-- Client.Preview. An incoming committed rule therefore overwrites them;
				-- replay the still-dirty working copy after that broadcast settles.
				reapplyWorldPreview = true
			elseif self:ReloadCleanSlot( slot ) then
				selectedChanged = selectedChanged or slot == self.Selected
			end
		end
	end
	if reapplyWorldPreview then self:QueuePreview() end
	if selectedChanged then self:BuildParamList() end
	self:NotifyParentState()
end

function PANEL:BumpRevision( slot )
	self.SourceRevision = self.SourceRevision or {}
	self.SourceRevision[ slot ] = ( self.SourceRevision[ slot ] or 0 ) + 1
	return self.SourceRevision[ slot ]
end

function PANEL:MarkChanged( slot )
	slot = tonumber( slot ) or self.Selected
	if slot == nil then return end
	self.SourceDirty[ slot ] = true
	self:BumpRevision( slot )
	self.SourcePreviewDirty[ slot ] = true
	self:SetStatus( L( "rtx.source.unsaved", "Unsaved Source material changes" ) )
	self:QueuePreview()
	self:NotifyParentState()
end

function PANEL:IsDirty( displayIndex )
	if displayIndex == nil then
		for _, dirty in pairs( self.SourceDirty ) do if dirty then return true end end
		return false
	end
	local group = self.MaterialSlotGroups[ tonumber( displayIndex ) ] or {}
	for _, slot in ipairs( group ) do if self.SourceDirty[ slot ] then return true end end
	return false
end

function PANEL:HasSavedOverride( displayIndex )
	local group = self.MaterialSlotGroups[ tonumber( displayIndex ) ] or {}
	for _, slot in ipairs( group ) do
		self:LoadSlot( slot )
		if self.SourceHadRule[ slot ] then return true end
	end
	return false
end

function PANEL:Canonical( slot )
	local working = self:GetWorking( slot, true )
	return AdvMat.SanitizeParams( working.params ),
		AdvMat.Gen.SanitizeAll( working.gen ), working
end

function PANEL:CurrentScope()
	if self.WorldMat then return AdvMat.SCOPE.WORLD end
	if IsValid( self.ScopeBox ) then
		local _, scope = self.ScopeBox:GetSelected()
		if tonumber( scope ) then return tonumber( scope ) end
	end
	local cv = GetConVar( "advmateditor_scope" )
	return math.Clamp( cv and cv:GetInt() or AdvMat.SCOPE.MODEL,
		AdvMat.SCOPE.ENTITY, AdvMat.SCOPE.MATERIAL )
end

function PANEL:ScopeTargetAvailable( slot, scope )
	scope = tonumber( scope ) or AdvMat.SCOPE.MODEL
	if scope == AdvMat.SCOPE.WORLD then return self.WorldMat ~= nil and self.WorldMat ~= "" end
	if scope == AdvMat.SCOPE.ENTITY then return IsValid( self.Entity ) end
	if scope == AdvMat.SCOPE.MODEL then return self.TargetModel ~= nil and self.TargetModel ~= "" end
	if scope == AdvMat.SCOPE.MATERIAL then
		return AdvMat.NormalizeMaterial( self.MaterialBySlot[ tonumber( slot ) or -1 ] or "" ) ~= ""
	end
	return false
end

function PANEL:ScopeKey( slot, scope )
	scope = scope or self:CurrentScope()
	if scope == AdvMat.SCOPE.WORLD then return self.WorldMat end
	if scope == AdvMat.SCOPE.MODEL then return self.TargetModel end
	if scope == AdvMat.SCOPE.MATERIAL then
		return AdvMat.NormalizeMaterial( self.MaterialBySlot[ slot ] or "" )
	end
	return IsValid( self.Entity ) and self.Entity:EntIndex() or nil
end

function PANEL:RuleFor( slot, scope, key )
	local params, gen, working = self:Canonical( slot )
	scope = scope or AdvMat.SCOPE.ENTITY
	return {
		scope = scope,
		key = key or self:ScopeKey( slot, scope ),
		index = slot,
		mat = working.mat ~= "" and working.mat
			or AdvMat.NormalizeMaterial( self.MaterialBySlot[ slot ] or "" ),
		shader = working.shader,
		params = params,
		gen = gen,
	}
end

function PANEL:QueuePreview()
	local timerName = "AdvMat.RTXSourcePreview." .. tostring( self )
	local now = SysTime()
	if now >= ( self.NextPreview or 0 ) then
		self.NextPreview = now + PREVIEW_DELAY
		timer.Remove( timerName )
		self:PushPreview()
		return
	end
	timer.Create( timerName, self.NextPreview - now, 1, function()
		if not IsValid( self ) then return end
		self.NextPreview = SysTime() + PREVIEW_DELAY
		self:PushPreview()
	end )
end

function PANEL:FlushPreview()
	-- Save must hand off the exact newest working body. If the throttled preview
	-- timer still contains the previous slider value, ExpectSave cannot match it
	-- and the later queued preview would survive indefinitely after the ack.
	timer.Remove( "AdvMat.RTXSourcePreview." .. tostring( self ) )
	self.NextPreview = SysTime() + PREVIEW_DELAY
	self:PushPreview()
end

function PANEL:PushPreview()
	local live = IsValid( self.LiveCheck ) and self.LiveCheck:GetChecked()
	if self.WorldMat then
		local dirty = self.SourceDirty[ 0 ]
		local working = self.SourceWorking[ 0 ]
		if live and dirty and working then
			AdvMat.Apply.ApplyWorld( self:RuleFor( 0, AdvMat.SCOPE.WORLD, self.WorldMat ) )
		elseif not self:HasPending( 0 ) then
			AdvMat.Apply.RefreshWorld()
		end
		return
	end
	if not IsValid( self.Entity ) then return end
	for slot, dirty in pairs( self.SourceDirty ) do
		if dirty then
			local working = self.SourceWorking[ slot ]
			if live and not AdvMat.RuleIsEmpty( working ) then
				AdvMat.Client.SetPreview( self.Entity, slot, self:RuleFor( slot ), true )
			elseif not self:HasPending( slot ) then
				AdvMat.Client.ClearPreview( self.Entity, slot, true )
			end
		end
	end
	AdvMat.Apply.Refresh( self.Entity )
end

-- RTX DModelPanels cannot reliably draw Source's transient procedural
-- materials.  Mirror the useful visual subset into one stable UnlitGeneric
-- material per real Source slot; the world entity still receives the complete
-- rule and remains the authoritative live preview for shading parameters.
function PANEL:GetPreviewMaterial( slot )
	slot = tonumber( slot )
	if slot == nil then return nil end
	local working = self.SourceWorking[ slot ]
	if AdvMat.RuleIsEmpty( working ) then return nil end
	local entry = self.SourceMirrors[ slot ]
	if entry and not self.SourcePreviewDirty[ slot ] then return entry.material end
	local source = AdvMat.Apply.BuildForRule( self:RuleFor( slot ) )
	if not source then return nil end
	local okTexture, texture = pcall( source.GetTexture, source, "$basetexture" )
	if not okTexture or not texture then return nil end
	local params = AdvMat.SanitizeParams( working.params )
	local desired = AdvMat.Apply.DesiredKV( self.MaterialBySlot[ slot ] or "", params ) or {}

	if not entry then
		local name = "advmat_rtx_source_mirror_" .. util.CRC( tostring( self ) .. ":" .. slot )
		local material = CreateMaterial( name, "UnlitGeneric", {
			[ "$basetexture" ] = "color/white", [ "$model" ] = "1", [ "$nolod" ] = "1",
		} )
		if not material then return nil end
		entry = { material = material }
		self.SourceMirrors[ slot ] = entry
	end

	local textureName = texture.GetName and texture:GetName() or tostring( texture )
	local alpha = tonumber( desired[ "$alpha" ] ) or 1
	local colour = AdvMat.StringToVector( desired[ "$color2" ]
		or desired[ "$color" ], Vector( 1, 1, 1 ) )
	local translucent = tobool( desired[ "$translucent" ] ) and 1 or 0
	local alphatest = tobool( desired[ "$alphatest" ] ) and 1 or 0
	local nocull = tobool( desired[ "$nocull" ] ) and 1 or 0
	local signature = textureName .. ":" .. tostring( alpha ) .. ":" .. tostring( colour )
		.. ":" .. translucent .. ":" .. alphatest .. ":" .. nocull
	if entry.signature ~= signature then
		entry.material:SetTexture( "$basetexture", texture )
		entry.material:SetFloat( "$alpha", tonumber( alpha ) or 1 )
		entry.material:SetVector( "$color2", colour or Vector( 1, 1, 1 ) )
		entry.material:SetInt( "$translucent", translucent )
		entry.material:SetInt( "$alphatest", alphatest )
		entry.material:SetInt( "$nocull", nocull )
		entry.material:Recompute()
		entry.signature = signature
	end
	self.SourcePreviewDirty[ slot ] = nil
	return entry.material
end

function PANEL:MakeContext( slot )
	local panel = self
	local baseKV = self:GetBaseKV( slot )
	local baseShader = self:GetActiveShader( slot )
	local targetModel = self.TargetModel ~= "" and self.TargetModel or nil
	local targetPath = AdvMat.NormalizeMaterial( self.MaterialBySlot[ slot ] or "" )
	local targetMask = IsValid( self.Entity ) and AdvMat.Mesh
		and AdvMat.Mesh.BodyMask( self.Entity ) or 0

	local function Host()
		if not IsValid( panel ) or not isfunction( panel.GetWorking ) then return nil end
		return panel
	end

	local function ForgetAutoOwnership( working, key )
		if working._autoParams then
			working._autoParams[ key ] = nil
			if table.IsEmpty( working._autoParams ) then
				working._autoParams = nil
			end
		end
		if key == "$translucent" then
			for _, recipe in pairs( istable( working.gen ) and working.gen or {} ) do
				if istable( recipe ) then recipe.autotranslucent = nil end
			end
		end
	end

	return {
		Get = function( key )
			local host = Host()
			local working = host and host.SourceWorking[ slot ]
			if working and working.params[ key ] ~= nil then return working.params[ key ] end
			if baseKV[ key ] ~= nil then return baseKV[ key ] end
			local def = AdvMat.GetParamDef( host and host:GetActiveShader( slot ) or baseShader, key )
			return def and def.default or ""
		end,
		State = function( key )
			local host = Host()
			local working = host and host.SourceWorking[ slot ]
			return ( working and working.params[ key ] ~= nil ) or false, baseKV[ key ] ~= nil
		end,
		Set = function( key, value )
			local host = Host()
			if not host then return false end
			local working = host:GetWorking( slot, true )
			if working.params[ key ] == value then return true end
			host:RememberUndo( slot )
			ForgetAutoOwnership( working, key )
			working.params[ key ] = value
			host:MarkChanged( slot )
			return true
		end,
		BaseTexture = function()
			local host = Host()
			local working = host and host.SourceWorking[ slot ]
			return working and working.params[ "$basetexture" ]
				or baseKV[ "$basetexture" ] or targetPath
		end,
		Shader = function()
			local host = Host()
			return host and host:GetActiveShader( slot ) or baseShader
		end,
		GetGen = function( key )
			local host = Host()
			local working = host and host.SourceWorking[ slot ]
			return working and working.gen and working.gen[ key ] or nil
		end,
		SetGen = function( key, recipe )
			local host = Host()
			if not host then return false end
			local working = host:GetWorking( slot, true )
			host:RememberUndo( slot )
			working.gen = working.gen or {}
			working.gen[ key ] = recipe
			if table.IsEmpty( working.gen ) then working.gen = nil end
			host:MarkChanged( slot )
			host:BuildParamList()
			return true
		end,
		Target = function()
			local host = Host()
			local working = host and host.SourceWorking[ slot ]
			local function Effective( key )
				if working and working.params and working.params[ key ] ~= nil then
					return working.params[ key ]
				end
				return baseKV[ key ]
			end
			return {
				host = host,
				model = targetModel,
				slot = slot,
				matpath = targetPath,
				mask = targetMask,
				shader = host and host:GetActiveShader( slot ) or baseShader,
				basekv = baseKV,
				src = baseKV[ "$basetexture" ],
				showsalpha = tobool( Effective( "$translucent" ) )
					or tobool( Effective( "$alphatest" ) ),
				-- Use Remix-safe preview rendering without turning an ordinary
				-- Source recipe into an RTX replacement/source-copy recipe.
				rtxrender = true,
			}
		end,
		SetParams = function( set, unset )
			local host = Host()
			if not host then return false end
			local working = host:GetWorking( slot, true )
			local changed = false
			for key, value in pairs( set or {} ) do
				if working.params[ key ] ~= value then changed = true break end
			end
			if not changed then
				for _, key in ipairs( unset or {} ) do
					if working.params[ key ] ~= nil then changed = true break end
				end
			end
			if not changed then return true end
			host:RememberUndo( slot )
			for key, value in pairs( set or {} ) do
				working.params[ key ] = value
				ForgetAutoOwnership( working, key )
			end
			for _, key in ipairs( unset or {} ) do
				working.params[ key ] = nil
				ForgetAutoOwnership( working, key )
			end
			if working._autoParams and table.IsEmpty( working._autoParams ) then
				working._autoParams = nil
			end
			host:MarkChanged( slot )
			host:BuildParamList()
			return true
		end,
		SetAutoParam = function( key, value, wanted, ownerRecipe )
			local host = Host()
			if not host then return false end
			local working = host:GetWorking( slot, true )
			local ownedBefore = ( working._autoParams
				and working._autoParams[ key ] == true )
				or GenOwnsAutoParam( working.gen, key )
			local effective = working.params[ key ]
			if effective == nil then effective = baseKV[ key ] end

			if istable( ownerRecipe ) then
				local marker = wanted and ( ownedBefore or not tobool( effective ) )
					and true or nil
				if ownerRecipe.autotranslucent ~= marker then
					-- The caller may mutate/drop this very recipe immediately after us.
					-- Snapshot before changing its persistent ownership marker; the
					-- following SetGen snapshot is deliberately debounced into the same
					-- user action by RememberUndo.
					host:RememberUndo( slot )
					ownerRecipe.autotranslucent = marker
				end
			end

			local owned = GenOwnsAutoParam( working.gen, key )
			local changed = false

			if owned then
				working._autoParams = working._autoParams or {}
				working._autoParams[ key ] = true
				if working.params[ key ] ~= value then
					host:RememberUndo( slot )
					working.params[ key ] = value
					changed = true
				end
			elseif ownedBefore then
				host:RememberUndo( slot )
				working.params[ key ] = nil
				if working._autoParams then
					working._autoParams[ key ] = nil
					if table.IsEmpty( working._autoParams ) then
						working._autoParams = nil
					end
				end
				changed = true
			end

			if changed then
				host:MarkChanged( slot )
				host:BuildParamList()
			end
			return owned
		end,
	}
end

function PANEL:RememberParamView()
	local slot = self.ParamViewSlot
	if slot == nil or self.ParamViewFiltered then return end
	local state = self.ParamViews[ slot ] or { groups = {} }
	state.groups = state.groups or {}
	for group, category in pairs( self.ParamCats or {} ) do
		if IsValid( category ) and category.GetExpanded then
			state.groups[ group ] = category:GetExpanded() == true
		end
	end
	local bar = IsValid( self.Scroll ) and self.Scroll:GetVBar() or nil
	if IsValid( bar ) and bar.GetScroll then state.scroll = bar:GetScroll() end
	self.ParamViews[ slot ] = state
end

function PANEL:RestoreParamScroll( slot, scroll, build )
	if scroll == nil then return end
	timer.Simple( 0, function()
		if not IsValid( self ) or self.ParamViewBuild ~= build
			or self.ParamViewSlot ~= slot or self.ParamViewFiltered then return end
		self.Scroll:InvalidateLayout( true )
		local bar = self.Scroll:GetVBar()
		if IsValid( bar ) and bar.SetScroll then bar:SetScroll( math.max( 0, scroll ) ) end
	end )
end

function PANEL:BuildParamList()
	if not IsValid( self.Scroll ) then return end
	AdvMat.CloseParamHelp()
	self:RememberParamView()
	self.ParamViewBuild = ( self.ParamViewBuild or 0 ) + 1
	local build = self.ParamViewBuild
	self.ParamCats = {}
	self.ParamViewSlot = nil
	self.ParamViewFiltered = false
	self.Scroll:Clear()

	local slot = self.Selected
	if slot == nil then
		local empty = self.Scroll:Add( "DLabel" )
		empty:Dock( TOP )
		empty:SetTall( AdvMat.RowHeight() * 3 )
		empty:SetText( "  " .. L( "rtx.source.select_material",
			"Select a sub-material on the left to edit its Source parameters." ) )
		empty:SetWrap( true )
		AdvMat.StyleLabel( empty, "AdvMatText", T.TextDim )
		return
	end

	local shader = AdvMat.CanonicalShader( self:GetActiveShader( slot ) )
	local baseKV = self:GetBaseKV( slot )
	local working = self.SourceWorking[ slot ]
	local view = self.ParamViews[ slot ]
	local filter = string.lower( string.Trim( self.Filter:GetValue() or "" ) )
	local showAll = self.ShowAll:GetChecked()
	self.ParamViewSlot = slot
	self.ParamViewFiltered = filter ~= ""

	self.SettingShader = true
	self.ShaderBox:Clear()
	local shaders = AdvMat.GetShaderList()
	if not table.HasValue( shaders, shader ) then table.insert( shaders, 1, shader ) end
	for _, name in ipairs( shaders ) do self.ShaderBox:AddChoice( name ) end
	self.ShaderBox:SetValue( shader )
	self.ShaderBox:SetEnabled( not self.WorldMat )
	self.SettingShader = false

	local material = self.MaterialBySlot[ slot ] or ""
	local warning = ""
	if not AdvMat.VMTExists( material ) then warning = AdvMat.L( "editor.missing_vmt" ) end
	self.Warning:SetText( warning )

	local context = self:MakeContext( slot )
	local buckets, order, seen = {}, {}, {}
	local function Bucket( group )
		if not buckets[ group ] then buckets[ group ] = {}; order[ #order + 1 ] = group end
		return buckets[ group ]
	end
	for _, def in ipairs( AdvMat.GetShaderParams( shader ) ) do
		seen[ def.name ] = true
		local isSet = baseKV[ def.name ] ~= nil
			or ( working and working.params[ def.name ] ~= nil )
		local matches = filter == "" or string.find( def.name, filter, 1, true )
			or string.find( string.lower( def.description or "" ), filter, 1, true )
		if matches and ( showAll or isSet ) then
			table.insert( Bucket( def.group or AdvMat.G.MISC ), def )
		end
	end

	local extras = {}
	for key in pairs( baseKV ) do if not seen[ key ] then extras[ key ] = true end end
	for key in pairs( working and working.params or {} ) do
		if not seen[ key ] then extras[ key ] = true end
	end
	local extraKeys = {}
	for key in pairs( extras ) do extraKeys[ #extraKeys + 1 ] = key end
	table.sort( extraKeys )
	for _, key in ipairs( extraKeys ) do
		if filter == "" or string.find( key, filter, 1, true ) then
			table.insert( Bucket( AdvMat.G.OTHER ), AdvMat.GetParamDef( shader, key ) )
		end
	end
	table.sort( order, function( left, right )
		return AdvMat.GroupOrder( left ) < AdvMat.GroupOrder( right )
	end )

	if #order == 0 then
		local empty = self.Scroll:Add( "DLabel" )
		empty:Dock( TOP )
		empty:SetTall( AdvMat.RowHeight() * 2 )
		empty:SetText( "  " .. L( "rtx.source.empty",
			"No Source parameters are available for this material." ) )
		AdvMat.StyleLabel( empty, "AdvMatText", T.TextDim )
		return
	end

	-- Why no texture row offers Import, said once above all of them.
	if AdvMat.Import then AdvMat.Import.CreateNotice( self.Scroll, self ) end

	for _, group in ipairs( order ) do
		local defs = buckets[ group ]
		local category = self.Scroll:Add( "DCollapsibleCategory" )
		category:Dock( TOP )
		category:DockMargin( 0, 0, 6, 4 )
		category:SetLabel( group .. "  (" .. #defs .. ")" )
		AdvMat.StyleCategory( category )
		self.ParamCats[ group ] = category
		local body = vgui.Create( "DPanel" )
		body.Paint = AdvMat.Fill( T.Panel )
		body:SetTall( 4 )
		category:SetContents( body )
		local function Fill()
			if category.AdvMatFilled then return end
			category.AdvMatFilled = true
			for rowIndex, def in ipairs( defs ) do
				AdvMat.CreateParamRow( body, context, def, rowIndex )
				local recipe = context.GetGen and context.GetGen( def.name )
				if recipe then AdvMat.CreateGenInfoRow( body, context, def, recipe ) end
			end
			AdvMat.SizeRows( body )
			self.Scroll:InvalidateLayout( true )
		end
		category.OnToggle = function( _, expanded ) if expanded then Fill() end end
		local remembered = filter == "" and view and view.groups and view.groups[ group ]
		local hasRemembered = filter == "" and view and view.groups
			and view.groups[ group ] ~= nil
		local expanded = filter ~= "" or ( hasRemembered and remembered
			or not hasRemembered and AdvMat.GroupStartsOpen( group ) )
		category:SetExpanded( expanded )
		if expanded then Fill() end
	end

	local add = self.Scroll:Add( "DButton" )
	add:Dock( TOP )
	add:SetTall( AdvMat.RowHeight() )
	add:DockMargin( 0, 6, 6, 4 )
	add:SetText( L( "editor.add_parameter", "Add a parameter by name..." ) )
	AdvMat.StyleButton( add )
	add.DoClick = function()
		Derma_StringRequest( AdvMat.L( "editor.add_parameter_title" ),
			AdvMat.L( "editor.add_parameter_prompt" ), "$", function( text )
				text = string.lower( string.Trim( text ) )
				local sigil = string.sub( text, 1, 1 )
				if sigil ~= "$" and sigil ~= "%" then return end
				context.Set( text, "1" )
				self:BuildParamList()
			end )
	end
	if filter == "" and view then self:RestoreParamScroll( slot, view.scroll, build ) end
end

function PANEL:BuildRulePayload( slot, remove, scope )
	scope = scope or self:CurrentScope()
	local working = self.SourceWorking[ slot ]
	local params, gen
	if not remove then params, gen = self:Canonical( slot ) end
	local payload = {
		scope = scope,
		key = self:ScopeKey( slot, scope ),
		index = slot,
		mat = working and working.mat ~= "" and working.mat
			or AdvMat.NormalizeMaterial( self.MaterialBySlot[ slot ] or "" ),
		shader = not remove and working and working.shader or nil,
		params = params or {},
		gen = gen,
	}
	return payload
end

function PANEL:SendRulePayload( slot, payload, remove, record )
	local function Transmit()
		if not remove and IsValid( self.Entity ) then
			AdvMat.Client.ExpectSave( self.Entity, slot, payload )
		end

		-- Assume the save lands, so a later save is based on it; a refusal puts
		-- back what the server really holds (OnRuleRejected).
		local id = AdvMat.RuleID( tonumber( payload.scope ) or AdvMat.SCOPE.MODEL,
			payload.key, payload.index )
		local token = remove and "" or AdvMat.RuleToken( payload )
		self.SentTokens = self.SentTokens or {}
		self.SourceTokens = self.SourceTokens or {}
		self.SentTokens[ id ] = { token = token }
		self.SourceTokens[ id ] = token

		net.Start( remove and "AdvMat.RuleClear" or "AdvMat.RuleSet" )
			AdvMat.Net.WriteTable( payload )
		net.SendToServer()
	end

	if not remove and AdvMat.Assets and isfunction( AdvMat.Assets.PrepareRule ) then
		AdvMat.Assets.PrepareRule( payload, function( ok, reason )
			if ok then Transmit() return end
			if IsValid( self ) then
				if record then self:FinishPending( record, false ) end
				self:SetStatus( AdvMat.L( "notify.asset_prepare_failed", {
					reason = tostring( reason or "upload failed" ),
				} ), true )
			end
		end )
		return payload
	end
	Transmit()
	return payload
end

function PANEL:SendRule( slot, remove, scope )
	return self:SendRulePayload( slot,
		self:BuildRulePayload( slot, remove, scope ), remove )
end

--- The version a save to `payload`'s identity is based on: the one loaded
--- with the slot, or this tab's own last save there. An identity that was
--- never captured falls back to what the mirror holds now.
function PANEL:ExpectedToken( payload )
	local id = AdvMat.RuleID( tonumber( payload.scope ) or AdvMat.SCOPE.MODEL,
		payload.key, payload.index )
	local known = self.SourceTokens and self.SourceTokens[ id ]
	if known ~= nil then return known end
	return MirrorToken( id )
end

function PANEL:SaveAll()
	local parent = self.ParentEditor
	if IsValid( parent ) and parent.AdvMatCanWrite == false then
		self:SetStatus( L( "rtx.source.save_denied",
			"Only administrators can save Source material overrides on this server." ), true )
		return false
	end
	if self:HasPending() then
		self:SetStatus( L( "rtx.source.saving",
			"Saving Source material overrides…" ), "warning" )
		return false
	end
	if self:HasOpenOwnedDialog() then
		self:SetStatus( L( "rtx.source.finish_dialog",
			"Finish or cancel the open texture/map dialog before saving Source changes." ), true )
		return false
	end
	local slots = {}
	for slot, dirty in pairs( self.SourceDirty ) do
		if dirty then slots[ #slots + 1 ] = slot end
	end
	table.sort( slots )
	if #slots == 0 then
		self:SetStatus( L( "rtx.source.nothing_save",
			"No Source material changes to save." ) )
		return false
	end

	local target = self:CurrentScope()
	local actions, materialBodies = {}, {}
	for _, slot in ipairs( slots ) do
		local working = self.SourceWorking[ slot ]
		local empty = AdvMat.RuleIsEmpty( working )
		local remove = empty and self.SourceHadRule[ slot ] == true
		local scope = remove and ( self.SourceRuleScope[ slot ] or target ) or target
		if not empty or remove then
			if not self:ScopeTargetAvailable( slot, scope ) then
				self:SetStatus( L( "rtx.source.target_lost",
					"The Source save target is no longer available. Select a valid target or reopen the editor." ), true )
				self:NotifyParentState()
				return false
			end
			local action = { slot = slot, working = working, remove = remove, scope = scope }
			actions[ #actions + 1 ] = action
			if scope == AdvMat.SCOPE.MATERIAL then
				local path = AdvMat.NormalizeMaterial( self.MaterialBySlot[ slot ] or "" )
				local body = remove and "<clear>" or RuleBodySignature( working )
				if materialBodies[ path ] and materialBodies[ path ] ~= body then
					self:SetStatus( L( "rtx.source.material_conflict",
						"Different Source slot edits share this material path. Make them match, or save with the entity/model target." ), true )
					self:NotifyParentState()
					return false
				end
				materialBodies[ path ] = body
			end
		else
			-- A newly-created empty working copy has no server operation. It is safe
			-- to discard this local no-op without calling it a successful save.
			self.SourceDirty[ slot ] = nil
			self.SourceUndo[ slot ] = {}
			self.SourceLastUndo[ slot ] = nil
		end
	end
	if #actions == 0 then
		self:SetStatus( L( "rtx.source.nothing_save",
			"No Source material changes to save." ) )
		self:NotifyParentState()
		return false
	end

	self:FlushPreview()
	local batch = self:BeginPendingBatch( "save" )
	local shadowed, outgoing = nil, {}
	for _, action in ipairs( actions ) do
		local slot, working = action.slot, action.working
		if not action.remove then
			-- Saving a broader model/material rule does not remove an already
			-- loaded, narrower entity rule. Source will keep resolving the narrower
			-- rule, so tell the user instead of making a successful save look reset.
			local from = self.SourceRuleScope[ slot ]
			if from and from ~= target and SCOPE_RANK[ from ]
				and SCOPE_RANK[ target ] and SCOPE_RANK[ from ] > SCOPE_RANK[ target ] then
				shadowed = from
			end
			local payload = self:BuildRulePayload( slot, false, action.scope )
			payload.expect = self:ExpectedToken( payload )
			local record = self:TrackPending( slot, payload, batch, working, false )
			outgoing[ #outgoing + 1 ] = {
				slot = slot, payload = payload, remove = false, record = record,
			}
		else
			local payload = self:BuildRulePayload( slot, true, action.scope )
			payload.expect = self:ExpectedToken( payload )
			local record = self:TrackPending( slot, payload, batch, working, true )
			outgoing[ #outgoing + 1 ] = {
				slot = slot, payload = payload, remove = true, record = record,
			}
		end
	end
	self:SetStatus( L( "rtx.source.saving",
		"Saving Source material overrides…" ), "warning" )
	self:NotifyParentState()
	-- Register the complete batch before the first send: listen servers may echo
	-- RuleApplied synchronously from net.SendToServer.
	for _, item in ipairs( outgoing ) do
		self:SendRulePayload( item.slot, item.payload, item.remove, item.record )
	end
	if shadowed then
		AdvMat.NotifyLocal( AdvMat.L( "notify.shadowed", {
			scope = AdvMat.LText( AdvMat.SCOPE_NAME[ shadowed ] ),
		} ), NOTIFY_HINT, 8 )
	end
	return true
end

function PANEL:UndoSelected()
	local slot = self.Selected
	if slot ~= nil and self:HasPending( slot ) then return false end
	local stack = slot ~= nil and self.SourceUndo[ slot ] or nil
	if not stack or #stack == 0 then return false end
	local previous = table.remove( stack )
	self.SourceWorking[ slot ] = previous ~= false and CopyRule( previous ) or nil
	self:BumpRevision( slot )
	self.SourcePreviewDirty[ slot ] = true
	self.SourceLastUndo[ slot ] = nil
	self.SourceDirty[ slot ] = true
	self:BuildParamList()
	self:QueuePreview()
	self:SetStatus( L( "rtx.source.unsaved", "Unsaved Source material changes" ) )
	self:NotifyParentState()
	return true
end

function PANEL:RevertSelected()
	local slot = self.Selected
	if slot == nil then return false end
	if self:HasPending( slot ) then return false end
	self.SourceWorking[ slot ] = CopyRule( self.SourceSaved[ slot ] )
	self:BumpRevision( slot )
	self.SourcePreviewDirty[ slot ] = true
	self.SourceDirty[ slot ] = nil
	self.SourceUndo[ slot ] = {}
	self.SourceLastUndo[ slot ] = nil
	if IsValid( self.Entity ) then AdvMat.Client.ClearPreview( self.Entity, slot )
	elseif self.WorldMat then AdvMat.Apply.RefreshWorld() end
	self:BuildParamList()
	self:SetStatus( L( "rtx.source.revert", "Revert Source changes" ) )
	self:NotifyParentState()
	return true
end

function PANEL:RemoveSelected()
	local slot = self.Selected
	if slot == nil then return false end
	if self:HasPending() then return false end
	if self:HasOpenOwnedDialog() then
		self:SetStatus( L( "rtx.source.finish_dialog",
			"Finish or cancel the open texture/map dialog before saving Source changes." ), true )
		return false
	end
	local scopes
	if self.WorldMat then
		scopes = { AdvMat.SCOPE.WORLD }
	else
		scopes = { AdvMat.SCOPE.MODEL, AdvMat.SCOPE.MATERIAL }
		-- A remembered target can legitimately disappear while the editor is
		-- open. Never encode that lost entity as key 0 (worldspawn).
		if IsValid( self.Entity ) then table.insert( scopes, 1, AdvMat.SCOPE.ENTITY ) end
	end
	local snapshot = CopyRule( self.SourceWorking[ slot ] )
	self:FlushPreview()
	local batch = self:BeginPendingBatch( "remove" )
	self.SourceDirty[ slot ] = true
	local outgoing = {}
	for _, scope in ipairs( scopes ) do
		local payload = self:BuildRulePayload( slot, true, scope )
		self:TrackPending( slot, payload, batch, snapshot, true )
		outgoing[ #outgoing + 1 ] = payload
	end
	self:SetStatus( L( "rtx.source.removing",
		"Removing Source override…" ), "warning" )
	self:NotifyParentState()
	for _, payload in ipairs( outgoing ) do
		self:SendRulePayload( slot, payload, true )
	end
	return true
end

function PANEL:Cleanup()
	if self.CleanedUp then return end
	self.CleanedUp = true
	timer.Remove( "AdvMat.RTXSourcePreview." .. tostring( self ) )
	for _, records in pairs( self.SourcePending or {} ) do
		for _, record in ipairs( records ) do
			if record.timer then timer.Remove( record.timer ) end
		end
	end
	for _, name in ipairs( { "TexPicker", "TexEditor", "SurfaceDialog", "GenDialog", "ImportHelp" } ) do
		local child = AdvMat[ name ]
		if IsValid( child ) and child.AdvMatHost == self and child.Close then child:Close() end
	end
	if IsValid( self.Entity ) then
		AdvMat.Client.ClearUncommittedPreviews( self.Entity )
	elseif self.WorldMat then
		AdvMat.Apply.RefreshWorld()
	end
	if self.LanguageHookID then
		hook.Remove( "AdvMatLanguageChanged", self.LanguageHookID )
		self.LanguageHookID = nil
	end
	if self.RulesHookID then
		hook.Remove( "AdvMatRulesChanged", self.RulesHookID )
		self.RulesHookID = nil
	end
	if self.AppliedHookID then
		hook.Remove( "AdvMatRuleApplied", self.AppliedHookID )
		self.AppliedHookID = nil
	end
	if self.RejectedHookID then
		hook.Remove( "AdvMatRuleRejected", self.RejectedHookID )
		self.RejectedHookID = nil
	end
	if self.PersistedHookID then
		hook.Remove( "AdvMatRulesPersisted", self.PersistedHookID )
		self.PersistedHookID = nil
	end
	if self.GeneratedHookID then
		hook.Remove( "AdvMatGenerated", self.GeneratedHookID )
		self.GeneratedHookID = nil
	end
	if self.ImportHookID then
		hook.Remove( "AdvMatImportChanged", self.ImportHookID )
		self.ImportHookID = nil
	end
end

function PANEL:OnRemove()
	self:Cleanup()
end

vgui.Register( "AdvMatRTXSourcePanel", PANEL, "DPanel" )
