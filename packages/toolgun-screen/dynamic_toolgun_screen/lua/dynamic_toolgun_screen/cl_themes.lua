--[[
	Dynamic Toolgun Screen - colour themes

	Colour roles every theme defines:
		bar1, bar2, bar_text, bar_accent, bar_edge     title bar (gradient top/bottom, text, flag box, bottom edge)
		nav_bg, nav_text, link                         navigation links bar
		hero_text, hero_shadow, sub_text               big text and the line under it
		strip_bg, strip_text, strip_link               status line
		info_bg, info_text, info_div, info_hl          readout panel (info_hl: highlighted text, default accent)
		menu_bg, menu_text, menu_edge                  menu bar
		bg1, bg2, tint                                 gradient background and the tint over pictures
		term_bg, term_fg, term_dim, term_hl            Terminal layout
		accent                                         general highlight

	Name is shown through DTScreen.Localize, so it can be a phrase key ("#theme.graphite") or plain text.

	Original (optional) = { role = colour, ... } replaces those roles while the background is the original
	screen picture, which brings its own status band, green readout panel and menu bar: clear panels let
	them show.
]]

local DTS = DTScreen

local function C( r, g, b, a ) return Color( r, g, b, a or 255 ) end

DTS.RegisterTheme( "winmobile", {
	Name = "#theme.winmobile",
	bar1 = C( 10, 72, 182 ), bar2 = C( 0, 42, 136 ), bar_text = C( 255, 255, 255 ), bar_accent = C( 0, 95, 239 ), bar_edge = C( 120, 132, 165 ),
	nav_bg = C( 245, 245, 245, 228 ), nav_text = C( 0, 0, 0 ), link = C( 0, 0, 238 ),
	hero_text = C( 255, 255, 255 ), hero_shadow = C( 0, 0, 0 ), sub_text = C( 225, 235, 255 ),
	strip_bg = C( 20, 22, 18, 185 ), strip_text = C( 235, 235, 235 ), strip_link = C( 40, 150, 255 ),
	info_bg = C( 228, 233, 218, 205 ), info_text = C( 0, 0, 0 ), info_div = C( 0, 0, 0, 60 ),
	menu_bg = C( 219, 216, 214 ), menu_text = C( 0, 0, 0 ), menu_edge = C( 0, 0, 0 ),
	bg1 = C( 58, 92, 150 ), bg2 = C( 12, 22, 48 ), tint = C( 0, 0, 0, 40 ),
	term_bg = C( 4, 10, 6 ), term_fg = C( 90, 255, 140 ), term_dim = C( 40, 125, 70 ), term_hl = C( 215, 255, 225 ),
	accent = C( 0, 95, 239 ),
	-- the original's own colours, measured from models/weapons/v_toolgun/screen_bg; the status line keeps
	-- light text (the original's black is hard to read on its dark band) and the readouts highlight in white
	Original = {
		bar1 = C( 0, 48, 148 ), bar2 = C( 0, 48, 148 ), bar_edge = C( 0, 16, 49 ),
		nav_bg = C( 0, 0, 0, 0 ), link = C( 0, 0, 255 ),
		strip_bg = C( 0, 0, 0, 0 ), strip_link = C( 100, 185, 255 ),
		info_bg = C( 0, 0, 0, 0 ), info_div = C( 0, 0, 0, 0 ), info_hl = C( 255, 255, 255 ),
		menu_bg = C( 219, 215, 214 ),
		tint = C( 0, 0, 0, 0 ),
	},
} )

DTS.RegisterTheme( "graphite", {
	Name = "#theme.graphite",
	bar1 = C( 56, 58, 64 ), bar2 = C( 30, 31, 35 ), bar_text = C( 240, 240, 240 ), bar_accent = C( 255, 140, 0 ), bar_edge = C( 90, 90, 96 ),
	nav_bg = C( 28, 29, 33, 225 ), nav_text = C( 190, 190, 190 ), link = C( 255, 165, 50 ),
	hero_text = C( 255, 255, 255 ), hero_shadow = C( 0, 0, 0 ), sub_text = C( 255, 195, 125 ),
	strip_bg = C( 12, 12, 14, 215 ), strip_text = C( 220, 220, 220 ), strip_link = C( 255, 165, 50 ),
	info_bg = C( 24, 25, 28, 215 ), info_text = C( 228, 228, 228 ), info_div = C( 255, 255, 255, 40 ),
	menu_bg = C( 44, 46, 51 ), menu_text = C( 245, 245, 245 ), menu_edge = C( 0, 0, 0 ),
	bg1 = C( 62, 64, 72 ), bg2 = C( 18, 19, 22 ), tint = C( 0, 0, 0, 110 ),
	term_bg = C( 10, 10, 12 ), term_fg = C( 255, 170, 60 ), term_dim = C( 125, 85, 35 ), term_hl = C( 255, 232, 200 ),
	accent = C( 255, 140, 0 ),
} )

DTS.RegisterTheme( "phosphor", {
	Name = "#theme.phosphor",
	bar1 = C( 0, 46, 14 ), bar2 = C( 0, 22, 6 ), bar_text = C( 130, 255, 160 ), bar_accent = C( 0, 92, 30 ), bar_edge = C( 0, 130, 45 ),
	nav_bg = C( 0, 20, 6, 225 ), nav_text = C( 90, 200, 115 ), link = C( 160, 255, 180 ),
	hero_text = C( 140, 255, 170 ), hero_shadow = C( 0, 40, 12 ), sub_text = C( 100, 225, 135 ),
	strip_bg = C( 0, 16, 5, 225 ), strip_text = C( 110, 235, 145 ), strip_link = C( 205, 255, 215 ),
	info_bg = C( 0, 14, 4, 225 ), info_text = C( 105, 235, 140 ), info_div = C( 0, 120, 40 ),
	menu_bg = C( 0, 38, 12 ), menu_text = C( 150, 255, 180 ), menu_edge = C( 0, 100, 34 ),
	bg1 = C( 0, 34, 12 ), bg2 = C( 0, 6, 2 ), tint = C( 0, 45, 12, 130 ),
	term_bg = C( 0, 8, 2 ), term_fg = C( 90, 255, 130 ), term_dim = C( 30, 120, 55 ), term_hl = C( 210, 255, 220 ),
	accent = C( 0, 255, 100 ),
} )

DTS.RegisterTheme( "amber", {
	Name = "#theme.amber",
	bar1 = C( 70, 38, 0 ), bar2 = C( 36, 18, 0 ), bar_text = C( 255, 190, 60 ), bar_accent = C( 120, 66, 0 ), bar_edge = C( 150, 90, 10 ),
	nav_bg = C( 24, 12, 0, 225 ), nav_text = C( 210, 140, 40 ), link = C( 255, 205, 110 ),
	hero_text = C( 255, 184, 40 ), hero_shadow = C( 40, 18, 0 ), sub_text = C( 240, 165, 50 ),
	strip_bg = C( 20, 10, 0, 225 ), strip_text = C( 240, 170, 60 ), strip_link = C( 255, 225, 160 ),
	info_bg = C( 18, 9, 0, 225 ), info_text = C( 245, 175, 60 ), info_div = C( 140, 80, 10 ),
	menu_bg = C( 52, 28, 0 ), menu_text = C( 255, 200, 90 ), menu_edge = C( 120, 70, 0 ),
	bg1 = C( 56, 30, 0 ), bg2 = C( 10, 5, 0 ), tint = C( 60, 30, 0, 130 ),
	term_bg = C( 10, 5, 0 ), term_fg = C( 255, 176, 0 ), term_dim = C( 130, 85, 10 ), term_hl = C( 255, 230, 170 ),
	accent = C( 255, 176, 0 ),
} )

DTS.RegisterTheme( "sakura", {
	Name = "#theme.sakura",
	bar1 = C( 242, 125, 165 ), bar2 = C( 208, 82, 132 ), bar_text = C( 255, 255, 255 ), bar_accent = C( 255, 172, 204 ), bar_edge = C( 255, 205, 222 ),
	nav_bg = C( 255, 241, 246, 232 ), nav_text = C( 95, 40, 62 ), link = C( 205, 40, 112 ),
	hero_text = C( 255, 255, 255 ), hero_shadow = C( 125, 30, 72 ), sub_text = C( 255, 222, 236 ),
	strip_bg = C( 120, 38, 80, 190 ), strip_text = C( 255, 236, 245 ), strip_link = C( 255, 192, 222 ),
	info_bg = C( 255, 236, 243, 215 ), info_text = C( 82, 30, 52 ), info_div = C( 205, 40, 112, 70 ),
	menu_bg = C( 250, 216, 229 ), menu_text = C( 92, 30, 60 ), menu_edge = C( 205, 120, 152 ),
	bg1 = C( 250, 180, 206 ), bg2 = C( 150, 62, 112 ), tint = C( 70, 0, 35, 55 ),
	term_bg = C( 30, 6, 16 ), term_fg = C( 255, 152, 200 ), term_dim = C( 140, 60, 100 ), term_hl = C( 255, 232, 242 ),
	accent = C( 232, 60, 132 ),
} )

DTS.RegisterTheme( "sandbox", {
	Name = "#theme.sandbox",
	bar1 = C( 72, 148, 220 ), bar2 = C( 44, 108, 182 ), bar_text = C( 255, 255, 255 ), bar_accent = C( 30, 85, 150 ), bar_edge = C( 150, 195, 235 ),
	nav_bg = C( 236, 242, 248, 232 ), nav_text = C( 40, 52, 66 ), link = C( 20, 110, 200 ),
	hero_text = C( 255, 255, 255 ), hero_shadow = C( 10, 40, 80 ), sub_text = C( 220, 236, 252 ),
	strip_bg = C( 22, 44, 70, 200 ), strip_text = C( 235, 242, 250 ), strip_link = C( 130, 200, 255 ),
	info_bg = C( 238, 243, 248, 215 ), info_text = C( 30, 40, 52 ), info_div = C( 20, 110, 200, 70 ),
	menu_bg = C( 222, 230, 238 ), menu_text = C( 30, 40, 52 ), menu_edge = C( 44, 108, 182 ),
	bg1 = C( 96, 160, 220 ), bg2 = C( 22, 52, 92 ), tint = C( 0, 20, 50, 60 ),
	term_bg = C( 8, 16, 28 ), term_fg = C( 120, 200, 255 ), term_dim = C( 50, 100, 150 ), term_hl = C( 225, 240, 255 ),
	accent = C( 20, 110, 200 ),
} )

--[[---------------------------------------------------------
	Active theme = selected theme + colour overrides (dts_color_*)
-----------------------------------------------------------]]

local function Scale( col, f, a )
	return Color( math.Clamp( col.r * f, 0, 255 ), math.Clamp( col.g * f, 0, 255 ), math.Clamp( col.b * f, 0, 255 ), a or col.a )
end

local function Mix( a, b, t )
	return Color( Lerp( t, a.r, b.r ), Lerp( t, a.g, b.g ), Lerp( t, a.b, b.b ), Lerp( t, a.a or 255, b.a or 255 ) )
end

DTS.ScaleColor = Scale
DTS.MixColor = Mix

-- Keeps the theme's alpha unless the override gives one.
local function Override( str, keepAlpha )
	local col = DTS.ParseColor( str )
	if ( !col ) then return nil end
	if ( keepAlpha and !string.match( str, "^%s*%d+[%s,]+%d+[%s,]+%d+[%s,]+%d+" ) ) then col.a = keepAlpha end
	return col
end

function DTS.BuildTheme()

	local default = DTS.Themes.winmobile
	local base = DTS.Themes[ DTS.GetString( "theme" ) ] or default
	local t = {}
	-- a theme from another addon may leave roles out: those come from the default theme
	for k, v in pairs( default ) do if ( k != "Original" ) then t[ k ] = v end end
	for k, v in pairs( base ) do t[ k ] = v end
	local strip_bg, info_bg = t.strip_bg, t.info_bg

	if ( istable( base.Original ) and DTS.ResolveBackground( DTS.GetLayout() ) == "original" ) then
		for k, v in pairs( base.Original ) do t[ k ] = v end
	end
	t.info_hl = t.info_hl or t.accent

	local bar = Override( DTS.GetString( "color_bar" ) )
	if ( bar ) then
		t.bar1 = Scale( bar, 1.12, 255 )
		t.bar2 = Scale( bar, 0.78, 255 )
		t.bar_accent = Mix( bar, Color( 255, 255, 255 ), 0.25 )
		t.bar_text = DTS.Draw.Contrast( bar )
	end

	local accent = Override( DTS.GetString( "color_accent" ) )
	if ( accent ) then
		t.link, t.strip_link, t.accent, t.info_hl = accent, accent, accent, accent
	end

	local hero = Override( DTS.GetString( "color_hero" ) )
	if ( hero ) then t.hero_text = hero end

	-- an override keeps the theme's own panel alpha, not the clear one used on the original picture
	local strip = Override( DTS.GetString( "color_strip" ), strip_bg.a )
	if ( strip ) then
		t.strip_bg = strip
		t.strip_text = DTS.Draw.Contrast( strip )
	end

	local panel = Override( DTS.GetString( "color_panel" ), info_bg.a )
	if ( panel ) then
		t.info_bg = panel
		t.info_text = DTS.Draw.Contrast( panel )
	end

	local menu = Override( DTS.GetString( "color_menu" ) )
	if ( menu ) then
		t.menu_bg = menu
		t.menu_text = DTS.Draw.Contrast( menu )
	end

	local term = Override( DTS.GetString( "color_term" ) )
	if ( term ) then
		t.term_fg = term
		t.term_dim = Scale( term, 0.5 )
		t.term_hl = Mix( term, Color( 255, 255, 255 ), 0.7 )
	end

	return t

end
