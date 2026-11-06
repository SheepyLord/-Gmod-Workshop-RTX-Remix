--[[
	Dynamic Toolgun Screen - settings panel
	Used by the "Dynamic Toolgun Screen" tool (Tools tab) and by Utilities > Dynamic Toolgun Screen.
	Every text comes from the language files (menu.* phrases); open panels rebuild when the language changes.
]]

local DTS = DTScreen

local function L( key, vars )
	return DTS.L( key, vars )
end

local colFrame = Color( 24, 24, 26 )
local colHint = Color( 90, 90, 90 )

--[[---------------------------------------------------------
	Live preview of the screen
-----------------------------------------------------------]]

local PREVIEW = {}

function PREVIEW:Init()
	self:SetTall( 236 )
end

function PREVIEW:Paint( w, h )

	DTS.PreviewWanted = RealTime()

	local size = math.min( w - 12, h - 12, 256 )
	local x, y = math.floor( ( w - size ) / 2 ), math.floor( ( h - size ) / 2 )

	draw.RoundedBox( 6, x - 5, y - 5, size + 10, size + 10, colFrame )
	DTS.DrawScreenTexture( x, y, size, size )

	if ( !DTS.GetBool( "enabled" ) ) then
		draw.SimpleTextOutlined( L( "menu.preview_off" ), "DermaDefaultBold", w / 2, h / 2, color_white, TEXT_ALIGN_CENTER, TEXT_ALIGN_CENTER, 1, color_black )
	end

	return true

end

vgui.Register( "DTScreenPreview", PREVIEW, "DPanel" )

--[[---------------------------------------------------------
	Helpers
-----------------------------------------------------------]]

local function Section( parent, title, expanded )

	local form = vgui.Create( "DForm", parent )
	form:SetName( title )
	parent:AddItem( form )
	if ( expanded == false ) then form:SetExpanded( false ) end
	return form

end

-- The left column cuts long labels off (translations are often longer than English): hovering a cut
-- label shows its whole text.
local function FullText( label )

	if ( !IsValid( label ) ) then return end
	label:SetMouseInputEnabled( true )

	local base = label.PerformLayout
	label.PerformLayout = function( s, w, h )
		if ( base ) then base( s, w, h ) end
		s:SetTooltip( s:GetTextSize() > w and s:GetText() or false )
	end

end

local function Combo( form, label, setting, choices )

	local combo, text = form:ComboBox( label, "dts_" .. setting )
	FullText( text )
	combo:SetSortItems( false )
	for _, c in ipairs( choices ) do combo:AddChoice( c[ 1 ], c[ 2 ] ) end
	return combo

end

local function Slider( form, label, setting, min, max, decimals )

	local slider = form:NumSlider( label, "dts_" .. setting, min, max, decimals )
	FullText( slider.Label )
	return slider

end

local function Notice( text )
	notification.AddLegacy( text, NOTIFY_GENERIC, 3 )
	surface.PlaySound( "buttons/button15.wav" )
end

-- A help label whose text is produced by fn(), refreshed every `interval` seconds.
-- DForm help labels stretch to their text in their own Think, so that keeps running too.
local function LiveHelp( form, interval, fn )

	local label = form:Help( "" )
	local baseThink = label.Think

	label.Think = function( s )
		if ( RealTime() >= ( s.nextUpdate or 0 ) ) then
			s.nextUpdate = RealTime() + interval
			local text = fn()
			if ( s:GetText() != text ) then
				s:SetText( text )
				s:InvalidateLayout()
			end
		end
		if ( baseThink ) then baseThink( s ) end
	end

	return label

end

-- Ready-made lines. Lines with words use {tr:...} so they stay in the player's language.
local TEMPLATE_PRESETS = {
	{ "menu.preset.tool", "{tool}" },
	{ "menu.preset.tool_category", "{tool_category}" },
	{ "menu.preset.hints", "{hints}" },
	{ "menu.preset.prev_tool", "{tr:nav_back}" },
	{ "menu.preset.next_tool", "{tool_next}" },
	{ "menu.preset.progress", "{tool_progress}" },
	{ "menu.preset.tool_settings", "{tool_settings}" },
	{ "menu.preset.target", "{target}" },
	{ "menu.preset.aim_pos", "{aim_pos}" },
	{ "menu.preset.aim_dist", "{aim_dist}" },
	{ "menu.preset.aim_what", "{aim_what}" },
	{ "menu.preset.slope", "{tr:slope}" },
	{ "menu.preset.ent_class", "{ent_class}" },
	{ "menu.preset.ent_model", "{ent_model}" },
	{ "menu.preset.ent_health", "{tr:hp}" },
	{ "menu.preset.ent_owner", "{tr:owner}" },
	{ "menu.preset.ent_speed", "{ent_speed}" },
	{ "menu.preset.track", "{track}" },
	{ "menu.preset.clock", "{time}" },
	{ "menu.preset.clock_seconds", "{time:%H:%M:%S}" },
	{ "menu.preset.date", "{date}" },
	{ "menu.preset.session", "{session}" },
	{ "menu.preset.speed", "{speed}" },
	{ "menu.preset.pos", "{pos}" },
	{ "menu.preset.heading", "{heading}" },
	{ "menu.preset.health_armor", "{tr:health_armor}" },
	{ "menu.preset.perf", "{tr:perf}" },
	{ "menu.preset.props", "{tr:props}" },
	{ "menu.preset.map", "{map}" },
	{ "menu.preset.players", "{tr:players}" },
	{ "menu.preset.empty", "" },
}

--[[---------------------------------------------------------
	Screen content: one editable template per line of the current layout
-----------------------------------------------------------]]

-- kept on DTScreen so a Lua refresh of this file still finds the panels that are already open
local contentForms = DTS.MenuContentForms or setmetatable( {}, { __mode = "k" } )
DTS.MenuContentForms = contentForms

-- The screen's own context while it refreshes; otherwise (screen off, a tool with its own screen...)
-- a fresh one, since entities in an old context may be gone by now.
local menuCtx, menuCtxAt = nil, 0

local function MenuContext()

	if ( DTS.Ctx and RealTime() - ( DTS.LastRefresh or 0 ) < 0.5 ) then return DTS.Ctx end
	if ( menuCtx and RealTime() - menuCtxAt < 0.2 ) then return menuCtx end

	local ply = LocalPlayer()
	local wep = IsValid( ply ) and ply:GetActiveWeapon()
	menuCtx, menuCtxAt = DTS.BuildContext( IsValid( wep ) and wep:GetClass() == "gmod_tool" and wep or nil ), RealTime()
	return menuCtx

end

local function SlotRow( form, slot )

	local convar = "dts_" .. slot.setting

	local row = vgui.Create( "DPanel", form )
	row:SetTall( 58 )
	row:SetPaintBackground( false )

	local label = vgui.Create( "DLabel", row )
	label:SetText( DTS.Localize( slot.label ) )
	label:SetDark( true )
	label:SetFont( "DermaDefaultBold" )
	label:Dock( TOP )

	local line = vgui.Create( "DPanel", row )
	line:Dock( TOP )
	line:SetTall( 22 )
	line:SetPaintBackground( false )

	local presets = vgui.Create( "DButton", line )
	presets:SetText( "" )
	presets:SetImage( "icon16/text_list_bullets.png" )
	presets:SetWide( 24 )
	presets:Dock( RIGHT )
	presets:SetTooltip( L( "menu.content.presets_tip" ) )

	local reset = vgui.Create( "DButton", line )
	reset:SetText( "" )
	reset:SetImage( "icon16/arrow_undo.png" )
	reset:SetWide( 24 )
	reset:Dock( RIGHT )
	reset:DockMargin( 2, 0, 2, 0 )
	reset:SetTooltip( L( "menu.content.reset_tip", { value = slot.default != "" and slot.default or L( "menu.content.empty" ) } ) )
	reset.DoClick = function() RunConsoleCommand( convar, slot.default or "" ) end

	local entry = vgui.Create( "DTextEntry", line )
	entry:Dock( FILL )
	entry:SetConVar( convar )
	entry:SetUpdateOnType( false )
	entry:SetPlaceholderText( L( "menu.content.placeholder" ) )

	presets.DoClick = function()
		local menu = DermaMenu()
		for _, p in ipairs( TEMPLATE_PRESETS ) do
			menu:AddOption( L( p[ 1 ] ) .. ( p[ 2 ] != "" and ( "      " .. p[ 2 ] ) or "" ), function()
				RunConsoleCommand( convar, p[ 2 ] )
				entry:SetValue( p[ 2 ] )
			end )
		end
		menu:Open()
	end

	-- what the line shows right now, so editing a template gives immediate feedback
	local now = vgui.Create( "DLabel", row )
	now:Dock( TOP )
	now:SetTextColor( colHint )
	now:SetText( "" )
	now.Think = function( s )
		if ( RealTime() < ( s.next or 0 ) ) then return end
		s.next = RealTime() + 0.25
		local ctx = MenuContext()
		local text = entry:IsEditing() and entry:GetValue() or GetConVarString( convar )
		local runs = DTS.EvalTemplate( text, ctx )
		s:SetText( "  " .. L( "menu.content.now", { text = runs and DTS.RunsToString( runs ) or L( "menu.content.hidden_now" ) } ) )
	end

	form:AddItem( row )

end

local function BuildContent( form )

	form:Clear()

	local layout = DTS.GetLayout()
	form:Help( L( "menu.content.help", { layout = DTS.Localize( layout.Name ) } ) )

	for _, slot in ipairs( layout.Slots ) do
		SlotRow( form, slot )
	end

	local reset = form:Button( L( "menu.content.reset_all" ) )
	reset.DoClick = function()
		for _, slot in ipairs( layout.Slots ) do RunConsoleCommand( "dts_" .. slot.setting, slot.default or "" ) end
	end

end

cvars.AddChangeCallback( "dts_layout", function()
	timer.Simple( 0, function()
		for form in pairs( contentForms ) do
			if ( IsValid( form ) ) then BuildContent( form ) end
		end
	end )
end, "DTScreen_Menu" )

--[[---------------------------------------------------------
	Colour overrides
-----------------------------------------------------------]]

local THEME_ROLE = { bar = "bar1", accent = "accent", hero = "hero_text", strip = "strip_bg", panel = "info_bg", menu = "menu_bg", term = "term_fg" }

local function CurrentColor( id )

	local col = DTS.ParseColor( DTS.GetString( "color_" .. id ) )
	if ( col ) then return col, true end

	local theme = DTS.Themes[ DTS.GetString( "theme" ) ] or DTS.Themes.winmobile
	return theme[ THEME_ROLE[ id ] ] or color_white, false

end

local function OpenColorPicker( c )

	local frame = vgui.Create( "DFrame" )
	frame:SetTitle( L( "menu.colors.picker_title", { name = L( "color." .. c.id ) } ) )
	frame:SetSize( 320, 300 )
	frame:Center()
	frame:MakePopup()

	local mixer = vgui.Create( "DColorMixer", frame )
	mixer:Dock( FILL )
	mixer:SetPalette( true )
	mixer:SetAlphaBar( true )
	mixer:SetWangs( true )
	-- a copy: the mixer changes the colour it is given in place (alpha bar), which would change the theme itself
	local start = CurrentColor( c.id )
	mixer:SetColor( Color( start.r, start.g, start.b, start.a or 255 ) )
	mixer.ValueChanged = function( s, col )
		RunConsoleCommand( "dts_color_" .. c.id, DTS.ColorToString( col ) )
	end

	local useTheme = vgui.Create( "DButton", frame )
	useTheme:Dock( BOTTOM )
	useTheme:DockMargin( 0, 6, 0, 0 )
	useTheme:SetText( L( "menu.colors.use_theme" ) )
	useTheme.DoClick = function()
		RunConsoleCommand( "dts_color_" .. c.id, "" )
		frame:Close()
	end

end

local function ColorRow( form, c )

	local row = vgui.Create( "DPanel", form )
	row:SetTall( 22 )
	row:SetPaintBackground( false )

	local themeTag = L( "menu.colors.theme_tag" )

	local swatch = vgui.Create( "DButton", row )
	swatch:SetText( "" )
	swatch:SetWide( 70 )
	swatch:Dock( RIGHT )
	swatch.Paint = function( s, w, h )
		local col, custom = CurrentColor( c.id )
		draw.RoundedBox( 4, 0, 0, w, h, color_black )
		draw.RoundedBox( 4, 1, 1, w - 2, h - 2, Color( col.r, col.g, col.b, 255 ) )
		if ( !custom ) then
			draw.SimpleText( themeTag, "DermaDefault", w / 2, h / 2, DTS.Draw.Contrast( col ), TEXT_ALIGN_CENTER, TEXT_ALIGN_CENTER )
		end
		return true
	end
	swatch.DoClick = function() OpenColorPicker( c ) end
	swatch:SetTooltip( L( "menu.colors.pick" ) )

	local label = vgui.Create( "DLabel", row )
	label:SetText( L( "color." .. c.id ) )
	label:SetDark( true )
	label:Dock( FILL )

	form:AddItem( row )

end

--[[---------------------------------------------------------
	Token reference
-----------------------------------------------------------]]

local function TokenList( form )

	form:Help( L( "menu.tokens.help" ) )

	local list = vgui.Create( "DListView", form )
	list:SetTall( 360 )
	list:SetMultiSelect( false )
	list:AddColumn( L( "menu.tokens.col_token" ) ):SetFixedWidth( 112 )
	list:AddColumn( L( "menu.tokens.col_now" ) )

	for _, name in ipairs( DTS.TokenOrder ) do
		local tok = DTS.Tokens[ name ]
		local line = list:AddLine( "{" .. name .. "}", "" )
		line.Token = tok
		line:SetTooltip( DTS.Localize( tok.category ) .. ": " .. DTS.Localize( tok.desc ) )
	end

	list.DoDoubleClick = function( s, id, line )
		SetClipboardText( line:GetColumnText( 1 ) )
		Notice( L( "menu.tokens.copied", { token = line:GetColumnText( 1 ) } ) )
	end

	list.Think = function( s )
		if ( RealTime() < ( s.next or 0 ) or !s:IsVisible() ) then return end
		s.next = RealTime() + 0.5
		local ctx = MenuContext()
		for _, line in ipairs( s:GetLines() ) do
			local value = DTS.EvalToken( line.Token.name, nil, ctx )
			if ( istable( value ) ) then value = DTS.RunsToString( value ) end
			line:SetColumnText( 2, tostring( value or "" ) )
		end
	end

	form:AddItem( list )

end

--[[---------------------------------------------------------
	The panel
-----------------------------------------------------------]]

local FONTS_UI = { "Tahoma", "Verdana", "Segoe UI", "Arial", "Roboto", "Roboto Condensed", "Coolvetica", "Trebuchet MS", "Consolas", "Microsoft YaHei UI", "Microsoft JhengHei UI", "Meiryo UI", "Malgun Gothic" }
local FONTS_HERO = { "Helvetica", "Roboto Bk", "Impact", "Arial Black", "Coolvetica", "Segoe UI Black", "Tahoma", "Verdana", "Microsoft YaHei UI", "Microsoft JhengHei UI", "Meiryo UI", "Malgun Gothic" }
local FONTS_MONO = { "Consolas", "Lucida Console", "Courier New", "PT Mono", "NSimSun", "MS Gothic" }

-- A box to paste a DTS1:... string into (also dts_import without an argument: the console cuts long lines).
function DTS.OpenImportDialog()
	Derma_StringRequest( L( "menu.adv.import_title" ), L( "menu.adv.import_prompt" ), "", function( text )
		local ok, res = DTS.ImportSettings( text )
		Notice( ok and L( "menu.adv.imported", { n = res } ) or res )
	end, nil, L( "menu.adv.import_ok" ), L( "menu.adv.cancel" ) )
end

-- "Automatic (font of the language)" first, then a fixed list
local function FontChoices( kind, list )

	local out = { { L( "menu.font.auto", { font = DTS.LanguageFont( kind ) } ), "" } }
	for _, f in ipairs( list ) do out[ #out + 1 ] = { f, f } end
	return out

end

local builtPanels = DTS.MenuPanels or setmetatable( {}, { __mode = "k" } )
DTS.MenuPanels = builtPanels

function DTS.BuildPanel( panel )

	builtPanels[ panel ] = true

	panel:Help( L( "menu.intro" ) )

	local preview = vgui.Create( "DTScreenPreview", panel )
	panel:AddItem( preview )

	if ( panel.ToolPresets ) then
		panel:ToolPresets( "dynamic_toolgun_screen", DTS.GetPresetConVars() )
	end

	panel:CheckBox( L( "menu.enable" ), "dts_enabled" )

	-- Language: automatic follows the game (gmod_language)
	local languages = { { L( "menu.language.auto", { name = DTS.LanguageName( DTS.GameLanguage() ) } ), "" } }
	for _, lang in ipairs( DTS.Languages() ) do languages[ #languages + 1 ] = { lang.name, lang.code } end
	Combo( panel, L( "menu.language" ), "language", languages )

	--
	-- Inspect
	--
	local inspect = Section( panel, L( "menu.inspect.title" ) )
	inspect:Help( L( "menu.inspect.help" ) )

	local keyLabel = vgui.Create( "DLabel", inspect )
	keyLabel:SetText( L( "menu.inspect.key" ) )
	keyLabel:SetDark( true )
	FullText( keyLabel )

	local binder = vgui.Create( "DBinder", inspect )
	binder:SetConVar( "dts_inspect_key" )
	binder:SetTall( 24 )
	inspect:AddItem( keyLabel, binder )

	Slider( inspect, L( "menu.inspect.size" ), "inspect_size", 0.2, 0.7, 2 )
	inspect:ControlHelp( L( "menu.inspect.console" ) )
	inspect:CheckBox( L( "menu.inspect.on_top" ), "dts_inspect_on_top" )
	inspect:ControlHelp( L( "menu.inspect.on_top_help" ) )

	--
	-- Layout and look
	--
	local look = Section( panel, L( "menu.look.title" ) )

	local layouts = {}
	for _, id in ipairs( DTS.LayoutOrder ) do layouts[ #layouts + 1 ] = { DTS.Localize( DTS.Layouts[ id ].Name ), id } end
	Combo( look, L( "menu.look.layout" ), "layout", layouts )

	LiveHelp( look, 0.2, function() return DTS.Localize( DTS.GetLayout().Description or "" ) end )

	local themes = {}
	for _, id in ipairs( DTS.ThemeOrder ) do themes[ #themes + 1 ] = { DTS.Localize( DTS.Themes[ id ].Name ), id } end
	Combo( look, L( "menu.look.theme" ), "theme", themes )

	Combo( look, L( "menu.look.background" ), "background", {
		{ L( "menu.bg.auto" ), "auto" },
		{ L( "menu.bg.original" ), "original" },
		{ L( "menu.bg.art" ), "art" },
		{ L( "menu.bg.gradient" ), "gradient" },
		{ L( "menu.bg.camera" ), "camera" },
		{ L( "menu.bg.rear" ), "rear" },
		{ L( "menu.bg.image" ), "image" },
		{ L( "menu.bg.black" ), "black" },
	} )

	local _, imageLabel = look:TextEntry( L( "menu.look.image" ), "dts_bg_image" )
	FullText( imageLabel )
	look:ControlHelp( L( "menu.look.image_help" ) )
	Slider( look, L( "menu.look.dim" ), "bg_dim", 0, 0.9, 2 )
	Slider( look, L( "menu.look.cam_fov" ), "cam_fov", 5, 90, 0 )
	Slider( look, L( "menu.look.cam_fps" ), "cam_fps", 1, 60, 0 )

	Combo( look, L( "menu.look.font" ), "font", FontChoices( "ui", FONTS_UI ) )
	Combo( look, L( "menu.look.font_hero" ), "font_hero", FontChoices( "hero", FONTS_HERO ) )
	Combo( look, L( "menu.look.font_mono" ), "font_mono", FontChoices( "mono", FONTS_MONO ) )

	--
	-- Colours
	--
	local colors = Section( panel, L( "menu.colors.title" ), false )
	colors:Help( L( "menu.colors.help" ) )
	for _, c in ipairs( DTS.ColorOverrides ) do ColorRow( colors, c ) end
	local clear = colors:Button( L( "menu.colors.reset_all" ) )
	clear.DoClick = function()
		for _, c in ipairs( DTS.ColorOverrides ) do RunConsoleCommand( "dts_color_" .. c.id, "" ) end
	end

	--
	-- Big text
	--
	local hero = Section( panel, L( "menu.hero.title" ) )
	Combo( hero, L( "menu.hero.mode" ), "hero_mode", {
		{ L( "menu.hero.scroll" ), "scroll" },
		{ L( "menu.hero.auto" ), "auto" },
		{ L( "menu.hero.fit" ), "fit" },
	} )
	Slider( hero, L( "menu.hero.speed" ), "hero_speed", 20, 600, 0 )
	hero:CheckBox( L( "menu.hero.upper" ), "dts_hero_upper" )

	--
	-- Screen content
	--
	local content = Section( panel, L( "menu.content.title" ) )
	contentForms[ content ] = true
	BuildContent( content )

	--
	-- Clock and units
	--
	local clock = Section( panel, L( "menu.clock.title" ), false )
	Combo( clock, L( "menu.clock.style" ), "clock_24h", {
		{ L( "menu.clock.auto", { language = DTS.LanguageName( DTS.LanguageCode() ) } ), "auto" },
		{ L( "menu.clock.12h" ), "0" },
		{ L( "menu.clock.24h" ), "1" },
	} )
	clock:CheckBox( L( "menu.clock.seconds" ), "dts_clock_seconds" )
	clock:CheckBox( L( "menu.clock.ampm" ), "dts_clock_ampm" )
	clock:CheckBox( L( "menu.clock.blink" ), "dts_clock_blink" )
	Combo( clock, L( "menu.units.label" ), "units", {
		{ L( "menu.units.m" ), "m" },
		{ L( "menu.units.ft" ), "ft" },
		{ L( "menu.units.hu" ), "hu" },
	} )
	Slider( clock, L( "menu.units.decimals" ), "decimals", 0, 3, 0 )

	--
	-- Icons and effects
	--
	local fx = Section( panel, L( "menu.fx.title" ), false )
	fx:CheckBox( L( "menu.fx.speaker" ), "dts_icon_speaker" )
	fx:CheckBox( L( "menu.fx.signal" ), "dts_icon_signal" )
	fx:CheckBox( L( "menu.fx.battery" ), "dts_icon_battery" )
	fx:CheckBox( L( "menu.fx.boot" ), "dts_boot_anim" )
	fx:CheckBox( L( "menu.fx.flash" ), "dts_fire_flash" )
	fx:CheckBox( L( "menu.fx.notify" ), "dts_notifications" )
	Slider( fx, L( "menu.fx.notify_time" ), "notify_time", 0.5, 10, 1 )
	Slider( fx, L( "menu.fx.scanlines" ), "scanlines", 0, 1, 2 )
	fx:CheckBox( L( "menu.fx.vignette" ), "dts_vignette" )
	Slider( fx, L( "menu.fx.backlight" ), "backlight", 0.2, 1, 2 )

	--
	-- HUD mirror
	--
	local mirror = Section( panel, L( "menu.mirror.title" ), false )
	mirror:Help( L( "menu.mirror.help" ) )
	mirror:CheckBox( L( "menu.mirror.enable" ), "dts_mirror" )
	Combo( mirror, L( "menu.mirror.corner" ), "mirror_corner", {
		{ L( "menu.corner.tr" ), "tr" },
		{ L( "menu.corner.br" ), "br" },
		{ L( "menu.corner.bl" ), "bl" },
		{ L( "menu.corner.tl" ), "tl" },
	} )
	Slider( mirror, L( "menu.mirror.size" ), "mirror_size", 96, 768, 0 )
	Slider( mirror, L( "menu.mirror.alpha" ), "mirror_alpha", 30, 255, 0 )

	--
	-- Advanced
	--
	local adv = Section( panel, L( "menu.adv.title" ), false )
	adv:CheckBox( L( "menu.adv.respect" ), "dts_respect_toolscreens" )
	adv:ControlHelp( L( "menu.adv.respect_help" ) )
	Slider( adv, L( "menu.adv.refresh" ), "refresh", 1, 60, 0 )
	Slider( adv, L( "menu.adv.fps" ), "fps", 0, 144, 0 )
	Combo( adv, L( "menu.adv.resolution" ), "resolution", {
		{ L( "menu.res.256" ), "256" },
		{ L( "menu.res.512" ), "512" },
	} )

	adv:Help( L( "menu.adv.binds" ) )

	local copy = adv:Button( L( "menu.adv.copy" ) )
	copy.DoClick = function()
		SetClipboardText( DTS.ExportSettings() )
		Notice( L( "menu.adv.copied" ) )
	end

	local import = adv:Button( L( "menu.adv.import" ) )
	import.DoClick = function() DTS.OpenImportDialog() end

	local reset = adv:Button( L( "menu.adv.reset" ) )
	reset.DoClick = function()
		Derma_Query( L( "menu.adv.reset_question" ), L( "menu.adv.reset_title" ), L( "menu.adv.reset_yes" ), function() DTS.ResetSettings() end, L( "menu.adv.cancel" ) )
	end

	LiveHelp( adv, 1, function()
		local d = DTS.Diagnostics()
		if ( d.conflict ) then
			return L( "menu.adv.diag_conflict", { file = d.conflict } )
		elseif ( d.patched ) then
			local text = L( "menu.adv.diag_ok", { version = d.version, ms = DTS.FormatNumber( d.renderMs, 2 ) } )
			if ( d.lastError ) then text = text .. "\n" .. L( "menu.adv.diag_error", { error = string.sub( tostring( d.lastError ), 1, 120 ) } ) end
			return text
		end
		return L( "menu.adv.diag_wait" )
	end )

	local takeover = adv:Button( L( "menu.adv.takeover" ) )
	takeover:SetTooltip( L( "menu.adv.takeover_tip" ) )
	takeover.DoClick = function()
		DTS.Patch( true )
		Notice( L( "menu.adv.takeover_done" ) )
	end

	--
	-- Tokens
	--
	TokenList( Section( panel, L( "menu.tokens.title" ), false ) )

end

-- A new language rebuilds every open panel in place (the tool's panel and the Utilities one).
hook.Add( "DTScreen_LanguageChanged", "DTScreen_Menu", function()
	timer.Simple( 0, function()
		for panel in pairs( builtPanels ) do
			if ( IsValid( panel ) ) then
				panel:Clear()
				DTS.BuildPanel( panel )
			end
		end
	end )
end )

-- Utilities > Dynamic Toolgun Screen > Settings; both names are phrases registered by cl_i18n.lua
hook.Add( "PopulateToolMenu", "DTScreen_Menu", function()
	spawnmenu.AddToolMenuOption( "Utilities", "dts.menu.category", "dts_settings", "#dts.menu.settings", "", "", function( panel )
		DTS.BuildPanel( panel )
	end )
end )
