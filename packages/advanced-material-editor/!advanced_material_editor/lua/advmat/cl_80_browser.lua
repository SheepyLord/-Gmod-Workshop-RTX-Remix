--[[---------------------------------------------------------------------------
	Advanced Material Editor - saved override browser

	Lists every persistent rule the server has, so overrides can be inspected
	and removed without having to find the prop they belong to. Also exports
	and imports the whole set as JSON, which is how you move your edits between
	machines or ship them alongside a model addon.
-----------------------------------------------------------------------------]]

AdvMat = AdvMat or {}

local T           = AdvMat.Theme
local EXPORT_FILE = "advmat/export.json"

local function ScopeLabel( rule )
	local s = AdvMat.SCOPE_SHORT[ rule.scope ] or "?"
	if rule.scope == AdvMat.SCOPE.MODEL then
		return s .. " #" .. tostring( rule.index )
	end
	return s
end

function AdvMat.OpenBrowser()
	if IsValid( AdvMat.Browser ) then AdvMat.Browser:Remove() end

	local frame = vgui.Create( "DFrame" )
	AdvMat.Browser = frame
	-- The rule list and detail/actions pane both remain operable at the minimum;
	-- cap it to WindowUX's usable screen area for low-resolution clients.
	frame:SetMinWidth( math.min( math.max( 760, AdvMat.FontSize * 30 ),
		math.max( 1, ScrW() - 24 ) ) )
	frame:SetMinHeight( math.min( 420, math.max( 1, ScrH() - 24 ) ) )
	frame:SetSize( math.min( 980, ScrW() - 80 ), math.min( 620, ScrH() - 80 ) )
	frame:SetTitle( "Saved material overrides" )
	frame:SetSizable( true )
	frame:Center()
	frame:MakePopup()
	AdvMat.StyleFrame( frame )
	if AdvMat.WindowUX then
		AdvMat.WindowUX.SetupFrame( frame, "override_browser" )
	end

	local rowH = AdvMat.RowHeight()

	---------------------------------------------------------------- bottom
	local bottom = vgui.Create( "DPanel", frame )
	bottom:Dock( BOTTOM )
	bottom:SetTall( rowH + 4 )
	bottom:DockMargin( 0, 6, 0, 0 )
	bottom.Paint = AdvMat.NoPaint

	local status = vgui.Create( "DLabel", bottom )
	status:Dock( FILL )
	AdvMat.StyleLabel( status, "AdvMatText", T.TextDim )

	---------------------------------------------------------------- panes
	local divider = vgui.Create( "DHorizontalDivider", frame )
	divider:Dock( FILL )
	divider:SetLeftWidth( 520 )
	divider:SetDividerWidth( 6 )

	local list = vgui.Create( "DListView", divider )
	list:SetMultiSelect( false )
	list:AddColumn( "Scope" ):SetFixedWidth( AdvMat.FontSize * 7 )
	list:AddColumn( "Target" )
	list:AddColumn( "Params" ):SetFixedWidth( AdvMat.FontSize * 8 )
	divider:SetLeft( list )
	AdvMat.StyleListView( list )

	local rightPane = vgui.Create( "DPanel", divider )
	rightPane.Paint = AdvMat.NoPaint
	divider:SetRight( rightPane )

	local detailButtons = vgui.Create( "DPanel", rightPane )
	detailButtons:Dock( BOTTOM )
	detailButtons:SetTall( rowH )
	detailButtons:DockMargin( 0, 6, 0, 0 )
	detailButtons.Paint = AdvMat.NoPaint

	local detail = vgui.Create( "DListView", rightPane )
	detail:Dock( FILL )
	detail:SetMultiSelect( false )
	detail:AddColumn( "Parameter" ):SetFixedWidth( AdvMat.FontSize * 13 )
	detail:AddColumn( "Value" )
	AdvMat.StyleListView( detail )

	---------------------------------------------------------------- state
	local selectedRule

	local function ShowDetail( rule )
		detail:Clear()
		selectedRule = rule
		if not rule then return end

		local n = 0

		if rule.shader then
			n = n + 1
			AdvMat.StyleListLine( detail:AddLine( "(shader)", rule.shader ), n )
		end

		for k, v in SortedPairs( rule.params or {} ) do
			n = n + 1
			AdvMat.StyleListLine( detail:AddLine( k, v ), n )
		end
	end

	local function Populate()
		list:Clear()
		ShowDetail( nil )

		local n = 0
		for id, rule in SortedPairs( AdvMat.Client.Rules ) do
			n = n + 1

			local line = list:AddLine( ScopeLabel( rule ), rule.key, AdvMat.TableCount( rule.params ) )
			line.AdvMatRule = rule
			line:SetTooltip( AdvMat.L( "browser.shader_tip", {
				id = id, shader = rule.shader or AdvMat.L( "common.unchanged" ),
			} ) )
			AdvMat.StyleListLine( line, n )
		end

		status:SetText( n .. " persistent rule(s) on the server." )
	end

	list.OnRowSelected = function( _, _, line ) ShowDetail( line.AdvMatRule ) end

	---------------------------------------------------------------- actions
	-- Widths in characters, so labels keep fitting as the font scales.
	local function AddButton( parent, text, chars, fn, danger )
		local b = vgui.Create( "DButton", parent )
		b:Dock( RIGHT )
		b:SetWide( math.floor( AdvMat.FontSize * chars ) )
		b:DockMargin( 6, 0, 0, 0 )
		b:SetText( text )
		b.DoClick = fn
		AdvMat.StyleButton( b, danger )
		return b
	end

	AddButton( bottom, "Close", 4.5, function() frame:Close() end )
	AddButton( bottom, "Refresh", 5, function() AdvMat.Client.RequestSync() end )

	AddButton( bottom, "Import...", 6, function()
		if not file.Exists( EXPORT_FILE, "DATA" ) then
			AdvMat.NotifyLocal( AdvMat.L( "notify.put_export", { path = EXPORT_FILE } ),
				NOTIFY_ERROR, 6 )
			return
		end

		local tbl = util.JSONToTable( file.Read( EXPORT_FILE, "DATA" ) or "" )
		if not istable( tbl ) or not istable( tbl.rules ) then
			AdvMat.NotifyLocal( "That export file is unreadable.", NOTIFY_ERROR, 5 )
			return
		end

		local queue = {}
		for _, rule in pairs( tbl.rules ) do
			if istable( rule ) and istable( rule.params ) then queue[ #queue + 1 ] = rule end
		end

		-- timer.Create uses a repetition count of zero to mean "forever". An
		-- empty but valid export must therefore stop here rather than starting an
		-- endless 10 Hz stream of empty RuleSet messages.
		if #queue == 0 then
			AdvMat.NotifyLocal( "That export contains no rules.", NOTIFY_HINT, 4 )
			return
		end

		-- Imports may contain edited textures.  Upload and positively acknowledge
		-- each exact PNG before publishing the rule which names it, and serialize
		-- the rules so neither the asset path nor the edit limiter is burst.
		local sent = 0
		local function SendNext()
			local rule = queue[ sent + 1 ]
			if not rule then
				AdvMat.NotifyLocal( "Imported " .. sent .. " rule(s).", NOTIFY_GENERIC, 5 )
				return
			end

			local function Transmit()
				net.Start( "AdvMat.RuleSet" )
					AdvMat.Net.WriteTable( rule )
				net.SendToServer()
				sent = sent + 1
				timer.Simple( 0.12, SendNext )
			end

			if AdvMat.Assets and isfunction( AdvMat.Assets.PrepareRule ) then
				AdvMat.Assets.PrepareRule( rule, function( ok, reason )
					if ok then Transmit() return end
					AdvMat.NotifyLocal( AdvMat.L( "notify.asset_prepare_failed", {
						reason = tostring( reason or "upload failed" ),
					} ), NOTIFY_ERROR, 8 )
				end )
				return
			end
			Transmit()
		end
		SendNext()

		AdvMat.NotifyLocal( "Importing " .. #queue .. " rule(s)...", NOTIFY_GENERIC, 4 )
	end )

	AddButton( bottom, "Export", 5, function()
		file.CreateDir( "advmat" )
		file.Write( EXPORT_FILE, util.TableToJSON( { rules = AdvMat.Client.Rules }, true ) )
		AdvMat.NotifyLocal( "Written to garrysmod/data/" .. EXPORT_FILE, NOTIFY_GENERIC, 6 )
	end )

	AddButton( detailButtons, "Delete this rule", 9, function()
		if not selectedRule then return end

		net.Start( "AdvMat.RuleClear" )
			AdvMat.Net.WriteTable( selectedRule )
		net.SendToServer()

		timer.Simple( 0.3, function() if IsValid( frame ) then Populate() end end )
	end )

	AddButton( detailButtons, "Apply to what I am looking at", 13, function()
		if not selectedRule then return end

		local ent = LocalPlayer():GetEyeTrace().Entity
		if not IsValid( ent ) or not ent:GetModel() then
			AdvMat.NotifyLocal( "Look at a prop first.", NOTIFY_HINT, 4 )
			return
		end

		-- Rebase onto the target's own material for that slot, otherwise the
		-- rule would rebuild from a texture this model does not use.
		local mats = ent:GetMaterials() or {}
		local base = mats[ selectedRule.index + 1 ]

		local payload = {
				scope  = AdvMat.SCOPE.MODEL,
				key    = ent:GetModel(),
				index  = selectedRule.index,
				mat    = base and AdvMat.NormalizeMaterial( base ) or selectedRule.mat,
				shader = selectedRule.shader,
				params = selectedRule.params,
				gen    = selectedRule.gen,
			}
		local function Transmit()
			net.Start( "AdvMat.RuleSet" )
				AdvMat.Net.WriteTable( payload )
			net.SendToServer()
			AdvMat.NotifyLocal( "Applied to " .. ent:GetModel(), NOTIFY_GENERIC, 4 )
		end

		if AdvMat.Assets and isfunction( AdvMat.Assets.PrepareRule ) then
			AdvMat.Assets.PrepareRule( payload, function( ok, reason )
				if ok then Transmit() return end
				AdvMat.NotifyLocal( AdvMat.L( "notify.asset_prepare_failed", {
					reason = tostring( reason or "upload failed" ),
				} ), NOTIFY_ERROR, 8 )
			end )
			return
		end
		Transmit()
	end )

	Populate()

	hook.Add( "AdvMatRulesChanged", frame, function()
		if IsValid( frame ) then Populate() end
	end )

	return frame
end

concommand.Add( "advmat_browser", function() AdvMat.OpenBrowser() end )
