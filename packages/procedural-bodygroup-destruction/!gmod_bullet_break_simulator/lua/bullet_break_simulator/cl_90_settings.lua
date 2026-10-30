-- Options category with separate damage, filtering, performance, and diagnostics pages.

BBS = BBS or {}

local TAB_ID = "Options"
local CATEGORY_ID = "ProceduralBodygroupDestruction"
local TEXT_COLOR = Color( 40, 40, 40 )
local ALLOWED_COLOR = Color( 35, 125, 55 )
local BLOCKED_COLOR = Color( 175, 55, 55 )
local SETTINGS_PAGE_ORDER = {
	BBSMainSettings = 1,
	BBSFilterSettings = 2,
	BBSPerformanceSettings = 3,
	BBSDebugSettings = 4,
}
local function L( key, variables )
	return BBS.L and BBS.L( key, variables ) or tostring( key )
end

local function EnforceSettingsPageOrder()
	local menu = spawnmenu.GetToolMenu( TAB_ID ) or {}
	for _, category in ipairs( menu ) do
		if category.ItemName == CATEGORY_ID then
			table.sort( category, function( first, second )
				local firstOrder = SETTINGS_PAGE_ORDER[ first.ItemName ] or 100
				local secondOrder = SETTINGS_PAGE_ORDER[ second.ItemName ] or 100
				if firstOrder ~= secondOrder then return firstOrder < secondOrder end
				return tostring( first.Text or first.ItemName )
					< tostring( second.Text or second.ItemName )
			end )
			return
		end
	end
end

local function AddServerBooleanCheckbox( panel, label, convarName, networkName )
	local checkbox = vgui.Create( "DCheckBoxLabel" )
	checkbox:SetText( label )
	checkbox:SetTextColor( TEXT_COLOR )
	checkbox:SetDark( true )
	checkbox:SizeToContents()
	checkbox.BBSNextSync = 0

	function checkbox:OnChange( checked )
		if self.BBSSyncing then return end
		local player = LocalPlayer()
		if not IsValid( player ) or ( not game.SinglePlayer() and not player:IsAdmin() ) then
			BBS.Log( "%s", L( "permission.admin" ) )
			return
		end

		net.Start( networkName )
			net.WriteBool( checked )
		net.SendToServer()
	end

	function checkbox:Think()
		if self.BBSNextSync > RealTime() then return end
		self.BBSNextSync = RealTime() + 0.25
		local convar = GetConVar( convarName )
		if not convar then return end

		self.BBSSyncing = true
		self:SetChecked( convar:GetBool() )
		self.BBSSyncing = false
	end

	panel:AddItem( checkbox )
end

local function AddServerEnabledCheckbox( panel )
	AddServerBooleanCheckbox( panel, L( "main.enable_addon" ),
		"bbs_enabled", BBS.NET_SET_ENABLED )
	AddServerBooleanCheckbox( panel, L( "main.living_players" ),
		"bbs_damage_living_players", BBS.NET_SET_LIVING_PLAYERS )
	AddServerBooleanCheckbox( panel, L( "main.living_npcs" ),
		"bbs_damage_living_npcs", BBS.NET_SET_LIVING_NPCS )
end

local function AddLabel( panel, text, color )
	local label = vgui.Create( "DLabel" )
	label:SetText( text )
	label:SetTextColor( color or TEXT_COLOR )
	label:SetWrap( true )
	label:SetAutoStretchVertical( true )
	label:SetTall( 18 )
	panel:AddItem( label )
	return label
end

local function AddLanguageSelector( panel )
	local label = AddLabel( panel, L( "language.title" ) )
	label:SetFont( "DermaDefaultBold" )
	local combo = vgui.Create( "DComboBox" )
	local selected = GetConVar( "bbs_language" )
	selected = selected and selected:GetString() or "auto"
	local options = BBS.I18N and BBS.I18N.GetLanguageOptions
		and BBS.I18N.GetLanguageOptions() or { "auto", "en", "zh", "ja", "fr", "ru" }
	for _, code in ipairs( options ) do
		combo:AddChoice( L( "language." .. code ), code, code == selected )
	end
	function combo:OnSelect( _, _, code )
		RunConsoleCommand( "bbs_language", code )
	end
	panel:AddItem( combo )
end

local function NewButtonRow( panel )
	local row = vgui.Create( "DPanel" )
	row:SetTall( 28 )
	row:SetPaintBackground( false )
	panel:AddItem( row )
	return row
end

local function AddRowButton( row, text, width, callback, dock )
	local button = vgui.Create( "DButton", row )
	button:SetText( text )
	button:SetWide( width )
	button:Dock( dock or LEFT )
	button:DockMargin( 0, 0, 4, 0 )
	button.DoClick = callback
	return button
end

local function AddPerformanceRuntimeStatus( panel )
	local label = AddLabel( panel, "" )
	label:SetFont( "DermaDefaultBold" )
	label.BBSNextUpdate = 0

	function label:Think()
		if self.BBSNextUpdate > RealTime() then return end
		self.BBSNextUpdate = RealTime() + 0.5
		local runtime = BBS.IsActiveRTXRuntime and BBS.IsActiveRTXRuntime()
			and L( "performance.runtime_rtx" )
			or L( "performance.runtime_vanilla" )
		self:SetText( L( "performance.runtime", { runtime = runtime } ) )
		self:SizeToContentsY()
	end
end

local function LogFilterResult( action, success, detail )
	if success then
		BBS.Log( "%s: %s", action, tostring( detail or "saved" ) )
	else
		BBS.Log( "%s failed: %s", action, tostring( detail or "unknown error" ) )
	end
end

local function AddModelFilterEditor( panel )
	local modeLabel = AddLabel( panel, L( "filter.model_behavior" ) )
	modeLabel:SetFont( "DermaDefaultBold" )

	local mode = vgui.Create( "DComboBox" )
	mode:AddChoice( L( "filter.blacklist" ), "blacklist" )
	mode:AddChoice( L( "filter.whitelist" ), "whitelist" )
	panel:AddItem( mode )

	local modeHelp = AddLabel( panel, "" )
	local list = vgui.Create( "DListView" )
	list:SetTall( 150 )
	list:SetMultiSelect( false )
	list:AddColumn( L( "filter.models_column" ) )
	panel:AddItem( list )

	local inputRow = NewButtonRow( panel )
	local input = vgui.Create( "DTextEntry", inputRow )
	input:SetPlaceholderText( L( "filter.model_placeholder" ) )
	input:Dock( FILL )
	input:DockMargin( 0, 0, 4, 0 )
	local addButton = vgui.Create( "DButton", inputRow )
	addButton:SetText( L( "common.add" ) )
	addButton:SetWide( 52 )
	addButton:Dock( RIGHT )

	local actionRow = NewButtonRow( panel )
	local removeButton = AddRowButton( actionRow, L( "common.remove_selected" ), 126, function() end )
	local aimedButton = AddRowButton( actionRow, L( "filter.add_aimed" ), 126, function() end, RIGHT )
	local clearButton = vgui.Create( "DButton" )
	clearButton:SetText( L( "filter.clear_models" ) )
	panel:AddItem( clearButton )

	local aimedStatus = AddLabel( panel, L( "filter.aim_help" ) )
	aimedStatus:SetTall( 36 )
	aimedStatus.BBSNextUpdate = 0

	local refresh
	refresh = function()
		local config = BBS.GetDamageFilterConfig()
		mode:SetValue( config.modelMode == "whitelist"
			and L( "filter.whitelist" ) or L( "filter.blacklist" ) )
		modeHelp:SetText( config.modelMode == "whitelist"
			and ( #config.models == 0
				and L( "filter.whitelist_empty" )
				or L( "filter.whitelist_help" ) )
			or L( "filter.blacklist_help" ) )
		modeHelp:SetTextColor( config.modelMode == "whitelist" and #config.models == 0
			and BLOCKED_COLOR or TEXT_COLOR )
		list:Clear()
		for _, modelPath in ipairs( config.models ) do list:AddLine( modelPath ) end
	end

	function mode:OnSelect( _, _, data )
		local success, errorMessage = BBS.SetModelFilterMode( data )
		LogFilterResult( "model list mode", success, errorMessage or data )
		refresh()
	end

	local function AddInputModel()
		local success, detail = BBS.AddModelFilter( input:GetValue() )
		LogFilterResult( "add model", success, detail )
		if success then input:SetText( "" ) end
		refresh()
	end
	addButton.DoClick = AddInputModel
	input.OnEnter = AddInputModel

	function list:OnRowSelected( _, line )
		input:SetText( line:GetValue( 1 ) )
	end

	removeButton.DoClick = function()
		local selected = list:GetSelectedLine()
		local line = selected and list:GetLine( selected ) or nil
		if not line then
			BBS.Log( "%s", L( "filter.select_model_first" ) )
			return
		end
		local success, detail = BBS.RemoveModelFilter( line:GetValue( 1 ) )
		LogFilterResult( "remove model", success, detail )
		refresh()
	end

	aimedButton.DoClick = function()
		local player = LocalPlayer()
		local entity = IsValid( player ) and player:GetEyeTrace().Entity or nil
		if not IsValid( entity ) then
			BBS.Log( "%s", L( "filter.aim_entity_first" ) )
			return
		end
		local success, detail = BBS.AddModelFilter( entity:GetModel() )
		LogFilterResult( "add aimed model", success, detail )
		refresh()
	end

	clearButton.DoClick = function()
		Derma_Query( L( "filter.clear_confirm" ), L( "filter.clear_models" ),
			L( "common.clear" ), function()
				local success, detail = BBS.ClearModelFilters()
				LogFilterResult( "clear model list", success, detail )
				refresh()
			end, L( "common.cancel" ) )
	end

	function aimedStatus:Think()
		if self.BBSNextUpdate > RealTime() then return end
		self.BBSNextUpdate = RealTime() + 0.25
		local player = LocalPlayer()
		local entity = IsValid( player ) and player:GetEyeTrace().Entity or nil
		if not IsValid( entity ) or not entity.GetModel then
			self:SetText( L( "filter.aim_help" ) )
			self:SetTextColor( TEXT_COLOR )
			return
		end
		local allowed, reason, normalized = BBS.IsModelDamageAllowed( entity:GetModel() )
		local reasonKey = {
			[ "invalid model path" ] = "reason.invalid_model_path",
			[ "model is whitelisted" ] = "reason.model_whitelisted",
			[ "model is not whitelisted" ] = "reason.model_not_whitelisted",
			[ "model is blacklisted" ] = "reason.model_blacklisted",
			[ "model is not blacklisted" ] = "reason.model_not_blacklisted",
		}
		self:SetText( L( "filter.aimed_status", {
			model = normalized or L( "filter.no_model" ),
			decision = allowed and L( "filter.allowed" ) or L( "filter.blocked" ),
			reason = L( reasonKey[ reason ] or "reason.invalid_model_path" ),
		} ) )
		self:SetTextColor( allowed and ALLOWED_COLOR or BLOCKED_COLOR )
	end

	refresh()
end

local function AddBodygroupFilterEditor( panel )
	local list = vgui.Create( "DListView" )
	list:SetTall( 130 )
	list:SetMultiSelect( false )
	list:AddColumn( L( "filter.bodygroups_column" ) )
	panel:AddItem( list )

	local inputRow = NewButtonRow( panel )
	local input = vgui.Create( "DTextEntry", inputRow )
	input:SetPlaceholderText( L( "filter.bodygroup_placeholder" ) )
	input:Dock( FILL )
	input:DockMargin( 0, 0, 4, 0 )
	local addButton = vgui.Create( "DButton", inputRow )
	addButton:SetText( L( "common.add" ) )
	addButton:SetWide( 52 )
	addButton:Dock( RIGHT )

	local actionRow = NewButtonRow( panel )
	local removeButton = AddRowButton( actionRow, L( "common.remove_selected" ), 126, function() end )
	local resetButton = AddRowButton( actionRow, L( "common.reset_defaults" ), 112, function() end, RIGHT )

	local refresh = function()
		list:Clear()
		for _, name in ipairs( BBS.GetDamageFilterConfig().bodygroups ) do list:AddLine( name ) end
	end

	local function AddInputBodygroup()
		local success, detail = BBS.AddBodygroupFilter( input:GetValue() )
		LogFilterResult( "exclude bodygroup", success, detail )
		if success then input:SetText( "" ) end
		refresh()
	end
	addButton.DoClick = AddInputBodygroup
	input.OnEnter = AddInputBodygroup

	function list:OnRowSelected( _, line ) input:SetText( line:GetValue( 1 ) ) end
	removeButton.DoClick = function()
		local selected = list:GetSelectedLine()
		local line = selected and list:GetLine( selected ) or nil
		if not line then
			BBS.Log( "%s", L( "filter.select_bodygroup_first" ) )
			return
		end
		local success, detail = BBS.RemoveBodygroupFilter( line:GetValue( 1 ) )
		LogFilterResult( "remove bodygroup exclusion", success, detail )
		refresh()
	end
	resetButton.DoClick = function()
		local success, detail = BBS.ResetBodygroupFilters()
		LogFilterResult( "reset bodygroup exclusions", success, detail )
		refresh()
	end
	refresh()
end

local function AddHideableBodygroupOverrideEditor( panel )
	local list = vgui.Create( "DListView" )
	list:SetTall( 150 )
	list:SetMultiSelect( false )
	list:AddColumn( L( "filter.override_model_column" ) )
	list:AddColumn( L( "filter.override_bodygroup_column" ) )
	list:AddColumn( L( "filter.override_id_column" ) ):SetFixedWidth( 44 )
	panel:AddItem( list )

	local aimedStatus = AddLabel( panel, L( "filter.override_aim_help" ) )
	aimedStatus:SetTall( 36 )
	aimedStatus.BBSNextUpdate = 0
	local bodygroupChoice = vgui.Create( "DComboBox" )
	bodygroupChoice:SetValue( L( "filter.override_select_bodygroup" ) )
	panel:AddItem( bodygroupChoice )

	local actionRow = NewButtonRow( panel )
	local addButton = AddRowButton( actionRow,
		L( "filter.override_add_selected" ), 170, function() end )
	local removeButton = AddRowButton( actionRow,
		L( "common.remove_selected" ), 126, function() end, RIGHT )
	local clearButton = vgui.Create( "DButton" )
	clearButton:SetText( L( "filter.override_clear" ) )
	panel:AddItem( clearButton )

	local function RefreshList()
		list:Clear()
		for _, override in ipairs(
			BBS.GetDamageFilterConfig().hideableBodygroupOverrides or {} ) do
			local line = list:AddLine( override.model,
				override.bodygroup or "<unnamed>", tostring( override.id or "*" ) )
			line.BBSHideableOverride = override
		end
	end

	function bodygroupChoice:OnSelect( _, _, data )
		self.BBSSelectedBodygroup = istable( data ) and data or nil
	end

	function aimedStatus:Think()
		if self.BBSNextUpdate > RealTime() then return end
		self.BBSNextUpdate = RealTime() + 0.25
		local player = LocalPlayer()
		local entity = IsValid( player ) and player:GetEyeTrace().Entity or nil
		if not IsValid( entity ) or not entity.GetModel then
			self:SetText( L( "filter.override_aim_help" ) )
			self:SetTextColor( TEXT_COLOR )
			return
		end
		local model = entity:GetModel() or ""
		local identity = tostring( entity:EntIndex() ) .. "|" .. model
		if bodygroupChoice.BBSAimedIdentity == identity then return end
		bodygroupChoice.BBSAimedIdentity = identity
		bodygroupChoice.BBSSelectedBodygroup = nil
		bodygroupChoice:Clear()
		bodygroupChoice:SetValue( L( "filter.override_select_bodygroup" ) )
		local entries = {}
		for rawKey, group in pairs( entity:GetBodyGroups() or {} ) do
			if istable( group ) then
				local id = tonumber( group.id ) or tonumber( rawKey )
				if id ~= nil then
					entries[ #entries + 1 ] = {
						model = model,
						id = id,
						bodygroup = group.name or ( "bodygroup_" .. id ),
						count = math.max( tonumber( group.num ) or 0,
							entity:GetBodygroupCount( id ) or 0 ),
					}
				end
			end
		end
		table.sort( entries, function( left, right ) return left.id < right.id end )
		for _, entry in ipairs( entries ) do
			bodygroupChoice:AddChoice( string.format( "%d: %s (%d)",
				entry.id, entry.bodygroup, entry.count ), entry )
		end
		self:SetText( model ~= "" and model or L( "filter.no_model" ) )
		self:SetTextColor( #entries > 0 and ALLOWED_COLOR or BLOCKED_COLOR )
	end

	addButton.DoClick = function()
		local selected = bodygroupChoice.BBSSelectedBodygroup
		if not selected then
			BBS.Log( "%s", L( "filter.override_aim_missing" ) )
			return
		end
		local success, detail = BBS.AddHideableBodygroupOverride(
			selected.model, selected.id, selected.bodygroup )
		LogFilterResult( "hideable bodygroup override", success, detail )
		RefreshList()
	end

	removeButton.DoClick = function()
		local selectedLine = list:GetSelectedLine()
		local line = selectedLine and list:GetLine( selectedLine ) or nil
		local override = line and line.BBSHideableOverride or nil
		if not override then
			BBS.Log( "%s", L( "filter.override_remove_first" ) )
			return
		end
		local success, detail = BBS.RemoveHideableBodygroupOverride(
			override.model, override.id, override.bodygroup )
		LogFilterResult( "remove hideable bodygroup override", success, detail )
		RefreshList()
	end

	clearButton.DoClick = function()
		Derma_Query( L( "filter.override_clear_confirm" ),
			L( "filter.override_clear" ), L( "common.clear" ), function()
				local success, detail = BBS.ClearHideableBodygroupOverrides()
				LogFilterResult( "clear hideable bodygroup overrides", success, detail )
				RefreshList()
			end, L( "common.cancel" ) )
	end

	RefreshList()
end

-- Pre-0.17.2 used a dedicated top-level tab. Explicitly remove its hook so
-- Lua auto-refresh cannot recreate the obsolete tab on spawnmenu_reload.
hook.Remove( "AddToolMenuTabs", "BBS.AddToolTab" )

hook.Add( "AddToolMenuCategories", "BBS.AddToolCategories", function()
	spawnmenu.AddToolCategory( TAB_ID, CATEGORY_ID, L( "tab.title" ) )
end )

hook.Add( "PopulateToolMenu", "BBS.AddSettingsMenu", function()
	spawnmenu.AddToolMenuOption( TAB_ID, CATEGORY_ID, "BBSMainSettings",
		L( "menu.damage" ), "", "", function( panel )
            if NATIVELOADER_I18N then NATIVELOADER_I18N.PreparePanel(panel) end
			panel:ClearControls()
			AddLanguageSelector( panel )
			panel:Help( L( "main.intro" ) )
			panel:Button( L( "main.realtime_preset" ), "bbs_realtime_preset" )

			panel:Help( L( "main.damage" ) )
			AddServerEnabledCheckbox( panel )
			panel:Help( L( "main.server_help" ) )
			panel:CheckBox( L( "main.texture_removal" ), "bbs_damage_enabled" )
			panel:CheckBox( L( "main.apply_materials" ),
				"bbs_damage_apply_materials" )
			panel:NumSlider( L( "main.base_radius" ), "bbs_hull_radius", 0.05, 32, 2 )
			panel:NumSlider( L( "main.depth_inside" ), "bbs_hull_inside_distance", 0, 64, 2 )
			panel:NumSlider( L( "main.reach_outside" ), "bbs_hull_outside_distance", 0, 64, 2 )
			panel:NumSlider( L( "main.layer_limit" ),
				"bbs_damage_layer_limit", 0, 16, 0 )
			panel:Help( L( "main.layer_help" ) )

			panel:Help( L( "main.appearance" ) )
			panel:CheckBox( L( "main.scale_damage" ), "bbs_hole_damage_scaling" )
			panel:NumSlider( L( "main.reference_damage" ),
				"bbs_hole_reference_damage", 0.1, 100, 1 )
			panel:NumSlider( L( "main.max_multiplier" ),
				"bbs_hole_max_radius_multiplier", 1, 12, 2 )
			panel:NumSlider( L( "main.base_irregularity" ),
				"bbs_hole_base_irregularity", 0, 0.75, 2 )
			panel:NumSlider( L( "main.extra_irregularity" ),
				"bbs_hole_damage_irregularity", 0, 0.75, 2 )
			panel:NumSlider( L( "main.max_irregularity" ),
				"bbs_hole_max_irregularity", 0, 0.9, 2 )
			panel:Help( L( "main.damage_shape_help" ) )
			panel:NumSlider( L( "main.edge_expansion" ), "bbs_damage_uv_expand_pixels", 0, 24, 1 )
			panel:NumSlider( L( "main.edge_softness" ), "bbs_damage_uv_feather_pixels", 0, 16, 1 )
			panel:NumSlider( L( "main.smoothing_passes" ), "bbs_damage_uv_blur_passes", 0, 8, 0 )
			panel:CheckBox( L( "main.repair_seams" ), "bbs_damage_uv_unwrap_seams" )
			panel:CheckBox( L( "main.force_nocull" ), "bbs_damage_force_nocull" )
			panel:Help( L( "main.nocull_help" ) )
			panel:Help( L( "main.aspect_help" ) )

			panel:Help( L( "main.repair" ) )
			panel:Button( L( "main.clear_damage" ), "bbs_damage_clear" )
		end )

	spawnmenu.AddToolMenuOption( TAB_ID, CATEGORY_ID, "BBSFilterSettings",
		L( "menu.filters" ), "", "", function( panel )
            if NATIVELOADER_I18N then NATIVELOADER_I18N.PreparePanel(panel) end
			panel:ClearControls()
			panel:Help( L( "filter.page_intro" ) )

			-- Explicit overrides are the highest-priority user rule, so keep the
			-- editor first and visible without scrolling through the broader lists.
			panel:Help( L( "main.hideable_overrides" ) )
			panel:Help( L( "main.hideable_override_help" ) )
			AddHideableBodygroupOverrideEditor( panel )

			panel:Help( L( "main.excluded_bodygroups" ) )
			panel:Help( L( "main.bodygroup_help" ) )
			AddBodygroupFilterEditor( panel )

			panel:Help( L( "main.model_scope" ) )
			panel:Help( L( "main.model_scope_help" ) )
			AddModelFilterEditor( panel )

			panel:Help( L( "main.filters_saved", {
				path = BBS.GetDamageFilterPath(),
			} ) )
			panel:Help( L( "main.filters_future" ) )
		end )

	spawnmenu.AddToolMenuOption( TAB_ID, CATEGORY_ID, "BBSPerformanceSettings",
		L( "menu.performance" ), "", "", function( panel )
            if NATIVELOADER_I18N then NATIVELOADER_I18N.PreparePanel(panel) end
			panel:ClearControls()
			panel:Help( L( "performance.intro" ) )
			AddPerformanceRuntimeStatus( panel )

			panel:Help( L( "performance.presets" ) )
			-- Full-width rows remain readable in every supported language and make
			-- the frame-time tradeoff explicit before a user chooses a profile.
			panel:Button( L( "performance.gentle" ),
				"bbs_performance_gentle_preset" )
			panel:Button( L( "performance.balanced" ),
				"bbs_performance_balanced_preset" )
			panel:Button( L( "performance.fast" ),
				"bbs_performance_fast_preset" )
			panel:Button( L( "performance.aggressive" ),
				"bbs_performance_aggressive_preset" )
			panel:Help( L( "performance.preset_help" ) )

			panel:Help( L( "performance.background" ) )
			panel:CheckBox( L( "debug.prewarm" ), "bbs_mesh_prewarm" )
			panel:CheckBox( L( "debug.prewarm_living" ),
				"bbs_mesh_prewarm_living" )
			panel:CheckBox( L( "debug.disk_cache" ),
				"bbs_mesh_disk_cache" )
			panel:NumSlider( L( "performance.io_budget" ),
				"bbs_mesh_cache_io_budget_ms", 0.25, 80, 2 )
			panel:NumSlider( L( "performance.build_budget" ),
				"bbs_mesh_build_budget_ms", 0.5, 120, 2 )
			panel:NumSlider( L( "performance.catchup_budget" ),
				"bbs_mesh_prepare_catchup_ms", 2, 160, 2 )

			panel:Help( L( "performance.per_hit" ) )
			panel:NumSlider( L( "performance.query_budget" ),
				"bbs_mesh_query_budget_ms", 0.25, 80, 2 )
			panel:NumSlider( L( "performance.projection_budget" ),
				"bbs_damage_projection_budget_ms", 0.25, 50, 2 )

			panel:Help( L( "performance.rtx" ) )
			panel:NumSlider( L( "performance.rtx_background" ),
				"bbs_mesh_rtx_background_budget_ms", 1, 120, 2 )
			panel:NumSlider( L( "performance.rtx_catchup" ),
				"bbs_mesh_rtx_catchup_ms", 2, 200, 2 )
			panel:Help( L( "performance.rtx_help" ) )
			panel:Help( L( "performance.live_help" ) )
		end )

	spawnmenu.AddToolMenuOption( TAB_ID, CATEGORY_ID, "BBSDebugSettings",
		L( "menu.debug" ), "", "", function( panel )
            if NATIVELOADER_I18N then NATIVELOADER_I18N.PreparePanel(panel) end
			panel:ClearControls()
			panel:Help( L( "debug.intro" ) )
			panel:Button( L( "debug.preset" ), "bbs_debug_preset" )

			panel:Help( L( "debug.ragdoll_scope" ) )
			AddServerBooleanCheckbox( panel,
				L( "debug.death_only" ),
				"bbs_death_ragdolls_only", BBS.NET_SET_DEATH_ONLY )
			panel:NumSlider( L( "debug.prepare_target" ),
				"bbs_mesh_prepare_target_seconds", 1, 10, 1 )
			panel:Button( L( "debug.clear_disk_cache" ), "bbs_mesh_disk_cache_clear" )
			panel:Button( L( "debug.disk_cache_status" ), "bbs_mesh_disk_cache_status" )

			panel:Help( L( "debug.burst" ) )
			panel:CheckBox( L( "debug.coalesce" ), "bbs_hit_coalesce" )
			panel:NumSlider( L( "debug.burst_window" ),
				"bbs_hit_coalesce_window", 0.01, 0.15, 3 )
			panel:NumSlider( L( "debug.merge_radius" ), "bbs_hit_coalesce_radius", 0.25, 12, 2 )
			panel:NumSlider( L( "debug.max_clusters" ),
				"bbs_hit_coalesce_max_clusters", 1, 12, 0 )
			panel:NumSlider( L( "debug.clusters_frame" ),
				"bbs_hit_dispatch_per_frame", 1, 4, 0 )
			panel:NumSlider( L( "debug.queue_limit" ), "bbs_hit_queue_limit", 4, 128, 0 )

			panel:Help( L( "debug.overlay" ) )
			panel:CheckBox( L( "debug.draw_overlay" ), "bbs_debug_overlay" )
			panel:CheckBox( L( "debug.draw_labels" ), "bbs_debug_labels" )
			panel:CheckBox( L( "debug.through_walls" ), "bbs_debug_through_walls" )
			panel:CheckBox( L( "debug.last_hit_hud" ), "bbs_debug_hud" )
			panel:CheckBox( L( "debug.console" ), "bbs_debug_console" )
			panel:NumSlider( L( "debug.marker_duration" ), "bbs_debug_duration", 0, 120, 1 )
			panel:NumSlider( L( "debug.marker_size" ), "bbs_debug_size", 0.25, 16, 2 )
			panel:NumSlider( L( "debug.retrace_length" ), "bbs_debug_trace_length", 1, 128, 0 )
			panel:NumSlider( L( "debug.max_hits" ), "bbs_debug_max_markers", 1, 256, 0 )

			panel:Help( L( "debug.hull_visual" ) )
			panel:CheckBox( L( "debug.draw_hull" ), "bbs_hull_enabled" )
			panel:NumSlider( L( "debug.hull_segments" ), "bbs_hull_segments", 6, 64, 0 )
			panel:NumSlider( L( "debug.hull_alpha" ), "bbs_hull_fill_alpha", 0, 255, 0 )
			panel:Help( L( "debug.hull_help" ) )

			panel:Help( L( "debug.mesh_internals" ) )
			panel:NumSlider( L( "debug.bone_padding" ), "bbs_mesh_candidate_padding", 0, 8, 1 )
			panel:CheckBox( L( "debug.removable_only" ), "bbs_mesh_restrict_to_hideable" )
			panel:CheckBox( L( "debug.local_bounds" ), "bbs_mesh_local_bounds" )
			panel:CheckBox( L( "debug.full_scan" ), "bbs_mesh_force_full_scan" )

			panel:Help( L( "debug.projection" ) )
			panel:NumSlider( L( "debug.polar_samples" ), "bbs_hole_shape_samples", 8, 64, 0 )
			panel:NumSlider( L( "debug.subdivision" ), "bbs_damage_projection_depth", 0, 8, 0 )
			panel:NumSlider( L( "debug.boundary_tolerance" ), "bbs_damage_projection_tolerance", 0.001, 0.5, 3 )
			panel:NumSlider( L( "debug.max_uv_triangles" ), "bbs_damage_projection_max_triangles", 1024, 16384, 0 )
			panel:CheckBox( L( "debug.angle_bounds" ),
				"bbs_damage_projection_local_bounds" )
			panel:CheckBox( L( "debug.batch_raster" ),
				"bbs_damage_batch_raster" )
			panel:Help( L( "debug.projection_help" ) )

			panel:Help( L( "debug.material" ) )
			panel:CheckBox( L( "debug.rtx" ),
				"bbs_damage_rtx_direct_override" )
			panel:Help( L( "debug.rtx_help" ) )
			panel:CheckBox( L( "debug.texture_inspector" ),
				"bbs_damage_uv_preview" )
			panel:Help( L( "debug.texture_help" ) )
			panel:CheckBox( L( "debug.dump" ), "bbs_damage_dump_debug" )
			panel:CheckBox( L( "debug.validate_copy" ), "bbs_damage_validate_copy" )
			panel:CheckBox( L( "debug.print_vmt" ), "bbs_damage_print_vmt" )
			panel:CheckBox( L( "debug.print_uv" ), "bbs_damage_verbose_uv" )
			panel:NumSlider( L( "debug.uv_limit" ), "bbs_damage_uv_console_limit", 0, 128, 0 )

			panel:Help( L( "debug.performance" ) )
			panel:CheckBox( L( "debug.perf_enable" ), "bbs_perf_enabled" )
			panel:CheckBox( L( "debug.perf_hud" ), "bbs_perf_hud" )
			panel:CheckBox( L( "debug.perf_console" ), "bbs_perf_console" )
			panel:NumSlider( L( "debug.perf_history" ), "bbs_perf_history", 1, 256, 0 )
			panel:NumSlider( L( "debug.perf_stages" ), "bbs_perf_stage_limit", 1, 16, 0 )
			panel:Help( L( "debug.perf_help" ) )
			panel:Button( L( "debug.print_perf" ), "bbs_perf_status" )
			panel:Button( L( "debug.clear_perf" ), "bbs_perf_clear" )

			panel:Help( L( "debug.actions" ) )
			panel:Button( L( "debug.probe_target" ), "bbs_debug_probe" )
			panel:Button( L( "debug.print_last_hit" ), "bbs_debug_dump_last" )
			panel:Button( L( "debug.print_status" ), "bbs_debug_status" )
			panel:Button( L( "debug.print_filters" ), "bbs_filter_status" )
			panel:Button( L( "debug.reload_filters" ), "bbs_filter_reload" )
			panel:Button( L( "debug.clear_markers" ), "bbs_debug_clear" )
			panel:Button( L( "debug.mesh_cache_status" ), "bbs_mesh_cache_status" )
			panel:Button( L( "debug.probe_mesh" ), "bbs_mesh_probe_last" )
			panel:Button( L( "debug.clear_mesh_cache" ), "bbs_mesh_cache_clear" )
			panel:Button( L( "debug.print_uv_result" ), "bbs_damage_dump_last" )
			panel:Button( L( "debug.probe_vmt" ), "bbs_damage_probe_material" )
			panel:Button( L( "debug.uv_status" ), "bbs_damage_status" )
			panel:Button( L( "debug.probe_bodygroups" ), "bbs_damage_probe_bodygroups" )
			panel:Button( L( "debug.clear_transparent" ), "bbs_damage_clear" )
		end )

	-- AddToolMenuOption alphabetizes every category by localized display text.
	-- Apply an explicit semantic order independent of localized display text.
	EnforceSettingsPageOrder()
end )

-- Rebuild once after this layout migration so the removed top-level tab also
-- disappears immediately in an already-running game. Normal startup already
-- creates the menu after these hooks are registered.
local MENU_LAYOUT_FORMAT = 7
if BBS.SettingsMenuLayoutFormat ~= MENU_LAYOUT_FORMAT then
	BBS.SettingsMenuLayoutFormat = MENU_LAYOUT_FORMAT
	timer.Simple( 0, function()
		if IsValid( g_SpawnMenu ) then RunConsoleCommand( "spawnmenu_reload" ) end
	end )
end
