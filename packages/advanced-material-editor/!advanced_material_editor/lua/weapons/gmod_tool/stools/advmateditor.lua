--[[---------------------------------------------------------------------------
	Advanced Material Editor - tool gun entry point

	Left click          : open the material editor on whatever you are
	                      pointing at
	Shift + left click  : open it on the map surface you are pointing at
	Right click         : copy the overrides on that entity, or paste them if
	                      you are already holding a copy
	Reload              : open the editor on your own player model
	Shift + reload      : remove every override from the entity you are
	                      pointing at
-----------------------------------------------------------------------------]]

TOOL.Category   = "Render"
TOOL.Name       = "#tool.advmateditor.name"
TOOL.Command    = nil
TOOL.ConfigName = ""

TOOL.ClientConVar[ "scope" ]       = "2" -- AdvMat.SCOPE.MODEL
TOOL.ClientConVar[ "showall" ]     = "1" -- list every parameter the shader supports
TOOL.ClientConVar[ "livepreview" ] = "1"
TOOL.ClientConVar[ "size" ]        = "1" -- 1 Auto, 2 Small, 3 Medium, 4 Large, 5 Maximised
TOOL.ClientConVar[ "playercontrols" ] = "0" -- keep movement keys live while an editor is open

-- icon2 is drawn to the left of the main icon with a "+" between the two,
-- which is how the tool information display shows a modifier key. Garry's Mod
-- has no shift icon of its own, so the addon ships one.
local SHIFT = "advmat/shift.png"

TOOL.Information = {
	{ name = "left"                                       },
	{ name = "left_world",                 icon2 = SHIFT  },
	{ name = "right",       stage = 0                     },
	{ name = "right_paste", stage = 1                     },
	{ name = "reload"                                     },
	{ name = "reload_strip",               icon2 = SHIFT  },
}

if CLIENT then
	local function Phrase( key, fallback )
		return AdvMat.L and AdvMat.L( key ) or fallback
	end
	language.Add( "tool.advmateditor.name", Phrase( "tool.name", "Advanced Material Editor" ) )
	language.Add( "tool.advmateditor.desc", Phrase( "tool.desc", "Edit any VMT parameter of a model's sub-materials, live." ) )
	language.Add( "tool.advmateditor.left", Phrase( "tool.left", "Open the material editor" ) )
	language.Add( "tool.advmateditor.left_world", Phrase( "tool.left_world", "Edit the map surface you are aiming at" ) )
	language.Add( "tool.advmateditor.right", Phrase( "tool.right", "Copy this entity's material overrides" ) )
	language.Add( "tool.advmateditor.right_paste", Phrase( "tool.right_paste", "Paste the copied material overrides" ) )
	language.Add( "tool.advmateditor.reload", Phrase( "tool.reload", "Edit your own player model" ) )
	language.Add( "tool.advmateditor.reload_strip", Phrase( "tool.reload_strip", "Remove every override from this entity" ) )
end

---------------------------------------------------------------------------
-- Helpers
---------------------------------------------------------------------------
local function IsEditable( ent )
	if not IsValid( ent ) then return false end
	if ent:IsWorld() then return false end

	local mdl = ent:GetModel()
	if not mdl or mdl == "" then return false end

	return true
end

--- Shift is the modifier for every secondary action on this tool.
local function ShiftHeld( ply )
	return IsValid( ply ) and ply:KeyDown( IN_SPEED )
end

--- Tell a player's client to open the editor. Pass an entity, or a map
--- material path for world mode.
local function SendOpen( ply, ent, worldMat )
	net.Start( "AdvMat.Open" )
		net.WriteEntity( IsValid( ent ) and ent or NULL )
		net.WriteBool( AdvMat.IsAllowed( ply ) )
		net.WriteString( worldMat or "" )
	net.Send( ply )
end

local function Enabled( ply )
	if GetConVar( "advmat_enabled" ):GetBool() then return true end
	AdvMat.Notify( ply, "The Advanced Material Editor is disabled on this server.", NOTIFY_ERROR )
	return false
end

---------------------------------------------------------------------------
-- Left click: open the editor
---------------------------------------------------------------------------
function TOOL:LeftClick( trace )
	local ply     = self:GetOwner()
	local wantMap = ShiftHeld( ply ) and trace.HitWorld

	if not wantMap and not IsEditable( trace.Entity ) then return false end

	-- LeftClick runs on both realms because the tool gun is predicted. Let the
	-- client report success for the animation, and do the real work on the
	-- server so permissions are checked in one place.
	if CLIENT then return true end
	if not IsValid( ply ) then return false end
	if not Enabled( ply ) then return false end

	if wantMap then
		-- The trace reports the material of the brush face it hit. Displacements
		-- and a few other surface types report a placeholder instead of a real
		-- path, and there is no way to recover the material from those.
		local tex = trace.HitTexture

		if not isstring( tex ) or tex == "" or string.sub( tex, 1, 2 ) == "**" then
			AdvMat.Notify( ply,
				"That surface does not report a material path" ..
				( isstring( tex ) and ( " (" .. tex .. ")" ) or "" ) .. ".", NOTIFY_ERROR )
			return false
		end

		SendOpen( ply, nil, AdvMat.NormalizeMaterial( tex ) )
		return true
	end

	SendOpen( ply, trace.Entity, nil )
	return true
end

---------------------------------------------------------------------------
-- Right click: copy / paste overrides
---------------------------------------------------------------------------
function TOOL:RightClick( trace )
	local ent = trace.Entity
	if not IsEditable( ent ) then return false end
	if CLIENT then return true end

	local ply = self:GetOwner()
	if not IsValid( ply ) then return false end
	if AdvMat.RTXTool and AdvMat.RTXTool.UsesMode( ply ) then
		return AdvMat.RTXTool.RightClick( self, ent, ply )
	end

	local Store = AdvMat.Store

	if self:GetStage() == 0 then
		---------------------------------------------------------- copy
		local clip = {}

		local mats = ent:GetMaterials() or {}
		for i = 1, math.min( #mats, AdvMat.GetMaterialLimit( ent ) ) do
			local idx  = i - 1
			local base = AdvMat.NormalizeMaterial( mats[ i ] )

			local rule =
				   ( Store.EntityRules[ ent:EntIndex() ] or {} )[ idx ]
				or Store.Rules[ AdvMat.RuleID( AdvMat.SCOPE.MODEL, ent:GetModel(), idx ) ]
				or Store.Rules[ AdvMat.RuleID( AdvMat.SCOPE.MATERIAL, base ) ]

			if rule then
				clip[ idx ] = {
					mat    = rule.mat,
					shader = rule.shader,
					params = table.Copy( rule.params ),
					gen    = rule.gen and table.Copy( rule.gen ) or nil,
				}
			end
		end

		if table.IsEmpty( clip ) then
			AdvMat.Notify( ply, "That entity has no material overrides to copy.", NOTIFY_HINT )
			return false
		end

		ply.AdvMatClipboard = clip
		self:SetStage( 1 )
		AdvMat.Notify( ply, "Copied " .. table.Count( clip ) .. " material override(s).", NOTIFY_GENERIC )
		return true
	end

	--------------------------------------------------------------- paste
	local clip = ply.AdvMatClipboard
	if not istable( clip ) or table.IsEmpty( clip ) then
		self:SetStage( 0 )
		return false
	end

	if not AdvMat.IsAllowed( ply ) then
		AdvMat.Notify( ply, "You are not allowed to save material overrides here.", NOTIFY_ERROR )
		return false
	end

	local scope = math.Clamp( ply:GetInfoNum( "advmateditor_scope", AdvMat.SCOPE.MODEL ), 1, 3 )
	local key   = ( scope == AdvMat.SCOPE.MODEL ) and ent:GetModel() or ent

	local n = 0
	for idx, entry in pairs( clip ) do
		local pasteKey = key

		if scope == AdvMat.SCOPE.MATERIAL then
			local mats = ent:GetMaterials() or {}
			pasteKey = mats[ idx + 1 ]
		end

		if pasteKey and Store.Set( scope, pasteKey, idx, entry.mat, entry.shader,
			entry.params, ply, entry.gen ) then
			n = n + 1
		end
	end

	AdvMat.Notify( ply, "Pasted " .. n .. " material override(s).", NOTIFY_GENERIC )
	return true
end

---------------------------------------------------------------------------
-- Reload: strip overrides
---------------------------------------------------------------------------
--- Reload opens the editor on yourself, which is the fastest way to iterate
--- on a player model. Shift + reload keeps the old behaviour of stripping an
--- entity's overrides.
function TOOL:Reload( trace )
	local ply = self:GetOwner()

	if not ShiftHeld( ply ) then
		if CLIENT then return true end
		if not IsValid( ply ) then return false end
		if not Enabled( ply ) then return false end

		SendOpen( ply, ply, nil )
		return true
	end

	local ent = trace.Entity
	if not IsEditable( ent ) then return false end
	if CLIENT then return true end
	if not IsValid( ply ) then return false end

	if not AdvMat.IsAllowed( ply ) then
		AdvMat.Notify( ply, "You are not allowed to change material overrides here.", NOTIFY_ERROR )
		return false
	end

	if AdvMat.RTXTool and AdvMat.RTXTool.UsesMode( ply ) then
		return AdvMat.RTXTool.Strip( ent, ply )
	end

	local Store = AdvMat.Store
	local n     = 0

	-- Entity scope
	for idx in pairs( Store.EntityRules[ ent:EntIndex() ] or {} ) do
		Store.Clear( AdvMat.SCOPE.ENTITY, ent, idx )
		n = n + 1
	end

	-- Model scope
	n = n + Store.ClearModel( ent:GetModel() )

	-- Material scope
	local mats = ent:GetMaterials() or {}
	for i = 1, math.min( #mats, AdvMat.GetMaterialLimit( ent ) ) do
		local id = AdvMat.RuleID( AdvMat.SCOPE.MATERIAL, mats[ i ] )
		if Store.Rules[ id ] then
			Store.Clear( AdvMat.SCOPE.MATERIAL, mats[ i ], 0 )
			n = n + 1
		end
	end

	if n > 0 then
		AdvMat.Notify( ply, "Removed " .. n .. " material override(s).", NOTIFY_GENERIC )
	else
		AdvMat.Notify( ply, "That entity had no overrides.", NOTIFY_HINT )
	end

	return n > 0
end

function TOOL:Holster()
	self:SetStage( 0 )
end

---------------------------------------------------------------------------
-- Tool menu panel
---------------------------------------------------------------------------
function TOOL.BuildCPanel( panel )
    if NATIVELOADER_I18N then NATIVELOADER_I18N.PreparePanel(panel) end
	local L = AdvMat.L
	local languageBox = panel:ComboBox( L( "language.title" ) )
	local languageConVar = GetConVar( "advmat_language" )
	local selectedLanguage = languageConVar and languageConVar:GetString() or "auto"
	for _, code in ipairs( AdvMat.I18N.GetLanguageOptions() ) do
		languageBox:AddChoice( L( "language." .. code ), code, code == selectedLanguage )
	end
	languageBox.OnSelect = function( _, _, _, code )
		RunConsoleCommand( "advmat_language", code )
	end

	local backendBox = panel:ComboBox( L( "rtx.backend" ) )
	local backendConVar = GetConVar( "advmat_backend" )
	local selectedBackend = backendConVar and backendConVar:GetString() or "auto"
	for _, entry in ipairs( {
		{ "auto", L( "rtx.backend_auto" ) },
		{ "vanilla", L( "rtx.backend_vanilla" ) },
		{ "rtx", L( "rtx.backend_rtx" ) },
	} ) do
		backendBox:AddChoice( entry[ 2 ], entry[ 1 ], entry[ 1 ] == selectedBackend )
	end
	backendBox.OnSelect = function( _, _, _, mode ) RunConsoleCommand( "advmat_backend", mode ) end
	panel:ControlHelp( L( "rtx.backend_help" ) )

	panel:Help( L( "tool.help_left" ) )
	panel:Help( L( "tool.help_reload" ) )
	panel:Help( L( "tool.help_world" ) )
	panel:Help( L( "tool.help_strip" ) )
	panel:Help( "" )

	panel:AddControl( "ComboBox", {
		Label   = L( "tool.save_to" ),
		MenuButton = 0,
		Options = {
			[ L( "tool.scope_model_recommended" ) ] = { advmateditor_scope = "2" },
			[ L( "editor.scope_entity" ) ]          = { advmateditor_scope = "1" },
			[ L( "editor.scope_material" ) ]        = { advmateditor_scope = "3" },
		},
	} )

	panel:CheckBox( L( "tool.live_drag" ), "advmateditor_livepreview" )
	panel:ControlHelp( L( "tool.live_help" ) )

	panel:CheckBox( L( "editor.allow_movement" ), "advmateditor_playercontrols" )
	panel:ControlHelp( L( "editor.allow_movement_tip" ) )

	panel:CheckBox( L( "tool.list_all" ), "advmateditor_showall" )
	panel:ControlHelp( L( "tool.list_help" ) )

	panel:Button( L( "tool.browser" ), "advmat_browser" )
	panel:Button( L( "tool.reapply" ), "advmat_refresh" )
	panel:Button( L( "tool.resync" ), "advmat_resync" )
	panel:Button( L( "tool.rebuild" ), "advmat_gen_flush" )

	panel:Help( "" )
	panel:Help( L( "tool.make_help" ) )

	panel:Help( "" )
	panel:Help( L( "tool.storage_help" ) )
end
