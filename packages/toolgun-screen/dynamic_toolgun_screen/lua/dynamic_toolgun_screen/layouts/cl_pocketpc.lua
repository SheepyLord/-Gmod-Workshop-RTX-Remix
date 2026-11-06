--[[
	Pocket PC layout
	The original screen texture (models/weapons/v_toolgun/screen_bg) is a fake Windows Mobile screen:
	a title bar with a clock and a speaker, "< Back to Counter-Strike" / "Team Fortress 2 >" links,
	"You have not crashed! Click Here to crash!", two columns of readouts and a "File Open Quit" menu.
	This layout keeps that look and turns every one of those parts into a live, configurable line.
	Its parts sit where the original's are, so the "original" background (that texture without its text)
	lines up with them.
]]

local DTS = DTScreen

-- Names, descriptions and line labels are phrase keys; the default lines use {tr:...} so they follow the language.
local LAYOUT = {
	Name = "#layout.pocketpc.name",
	Description = "#layout.pocketpc.desc",
	Background = "original",
	Slots = {
		{ id = "title", label = "#layout.pocketpc.title", default = "{tr:title}" },
		{ id = "clock", label = "#layout.pocketpc.clock", default = "{time}" },
		{ id = "nav_l", label = "#layout.pocketpc.nav_l", default = "{tr:nav_back}" },
		{ id = "nav_r", label = "#layout.pocketpc.nav_r", default = "{tool_next}" },
		{ id = "hero", label = "#layout.pocketpc.hero", default = "{tool}" },
		{ id = "sub", label = "#layout.pocketpc.sub", default = "{track}" },
		{ id = "status", label = "#layout.pocketpc.status", default = "{target}" },
		{ id = "l1", label = "#layout.pocketpc.l1", default = "{aim_pos}" },
		{ id = "l2", label = "#layout.pocketpc.l2", default = "{aim_dist}" },
		{ id = "l3", label = "#layout.pocketpc.l3", default = "{aim_what}" },
		{ id = "r1", label = "#layout.pocketpc.r1", default = "{tr:props}" },
		{ id = "r2", label = "#layout.pocketpc.r2", default = "{tr:perf}" },
		{ id = "r3", label = "#layout.pocketpc.r3", default = "{speed}" },
		{ id = "menu", label = "#layout.pocketpc.menu", default = "{hints}" },
	}
}

local colBlack = Color( 0, 0, 0 )

function LAYOUT:Draw( D, ctx, T, slots )

	local ui = DTS.FontFace( "ui" )
	local now = RealTime()

	--
	-- Title bar: flag, title, status icons, clock
	--
	D.VGradient( 0, 0, 256, 26, T.bar1, T.bar2 )
	D.Rect( 0, 0, 26, 26, T.bar_accent )
	D.Flag( 13, 13, 19, DTS.FlagWave( now ) )
	D.Rect( 26, 0, 1, 26, T.bar_text, 160 )

	local right = 252
	if ( slots.clock ) then
		local w = D.Line( slots.clock, 140, 0, 112, 26, { face = ui, size = 16, weight = 800, color = T.bar_text, hl = T.bar_text, align = 2, overflow = "clip" } )
		right = right - w - 5
	end

	local st = DTS.StatusIcons( ctx )
	if ( st.speaker ) then
		D.Speaker( right - 15, 6, 14, T.bar_text, st.volume, st.muted, st.talking )
		right = right - 18
	end
	if ( st.signal ) then
		D.Signal( right - 12, 7, 12, 12, T.bar_text, st.bars )
		right = right - 16
	end
	if ( st.battery ) then
		-- the device's battery: a plug while it is plugged in, else the charge and its percentage
		if ( st.plugged ) then
			D.Plug( right - 19, 8, 19, 10, T.bar_text )
			right = right - 23
		else
			D.Battery( right - 19, 8, 19, 10, T.bar_text, st.batteryLevel / 100 )
			right = right - 22
			local w = D.Text( DTS.BatteryText( st.batteryLevel ), D.Font( ui, 13, 700 ), right, 13, T.bar_text, 2, 1 )
			right = right - w - 4
		end
	end

	D.Line( slots.title, 31, 0, right - 31, 26, { face = ui, size = 16, weight = 800, color = T.bar_text, hl = T.bar_text, overflow = "ellipsis" } )

	D.Rect( 0, 26, 256, 1, T.bar_edge )
	D.Rect( 0, 27, 256, 1, colBlack, 150 )

	--
	-- Navigation links
	--
	if ( slots.nav_l or slots.nav_r ) then

		D.Rect( 0, 28, 256, 20, T.nav_bg )
		local navFont = D.Font( ui, 13, 500 )
		local style = { face = ui, size = 13, weight = 500, color = T.link, hl = T.link, underlineAll = true, overflow = "ellipsis" }

		if ( slots.nav_l ) then
			D.Text( "<", navFont, 4, 38, T.nav_text, 0, 1 )
			style.align = 0
			D.Line( slots.nav_l, 13, 28, 112, 20, style )
		end

		if ( slots.nav_r ) then
			D.Text( ">", navFont, 252, 38, T.nav_text, 2, 1 )
			style.align = 2
			D.Line( slots.nav_r, 131, 28, 112, 20, style )
		end

	end

	--
	-- Big text (the scrolling tool name of the original) and the line under it
	--
	local mode = DTS.GetString( "hero_mode" )
	local heroStyle = {
		face = DTS.FontFace( "hero" ), size = 56, weight = 900,
		color = T.hero_text, hl = T.accent, shadow = T.hero_shadow, shadowOffset = 3,
		align = 1, gap = 64, speed = DTS.GetFloat( "hero_speed" ), minSize = 24,
		overflow = ( mode == "fit" and "fit" ) or ( mode == "auto" and "marquee" ) or "scroll",
		alpha = DTS.ToolChangeAlpha( now )
	}

	if ( slots.sub ) then
		D.Line( slots.hero, 0, 50, 256, 76, heroStyle )
		D.Line( slots.sub, 6, 127, 244, 19, { face = ui, size = 14, weight = 700, color = T.sub_text, hl = T.hero_text, shadow = T.hero_shadow, align = 1, overflow = "marquee", speed = 35 } )
	else
		D.Line( slots.hero, 0, 58, 256, 80, heroStyle )
	end

	--
	-- Status line ("You have not crashed! Click Here to crash!")
	--
	D.Rect( 0, 148, 256, 22, T.strip_bg )

	local note = DTS.ActiveNotification( now )
	if ( note ) then
		D.Line( note.runs, 4, 148, 248, 22, { face = ui, size = 15, weight = 700, color = T.strip_text, hl = T.strip_link, align = 1, overflow = "marquee", speed = 45, alpha = note.alpha } )
	elseif ( slots.status ) then
		D.Line( slots.status, 4, 148, 248, 22, { face = ui, size = 15, weight = 500, color = T.strip_text, hl = T.strip_link, underline = true, align = 1, overflow = "marquee", speed = 40 } )
	end

	--
	-- Readouts: two columns of three lines
	--
	D.Rect( 0, 170, 256, 60, T.info_bg )
	D.Rect( 128, 174, 1, 52, T.info_div )

	local info = { face = ui, size = 14, weight = 500, color = T.info_text, hl = T.info_hl or T.accent, overflow = "ellipsis" }
	D.Line( slots.l1, 6, 171, 118, 19, info )
	D.Line( slots.l2, 6, 190, 118, 19, info )
	D.Line( slots.l3, 6, 209, 118, 19, info )
	D.Line( slots.r1, 133, 171, 118, 19, info )
	D.Line( slots.r2, 133, 190, 118, 19, info )
	D.Line( slots.r3, 133, 209, 118, 19, info )

	--
	-- Menu bar ("File Open Quit")
	--
	D.Rect( 0, 230, 256, 2, T.menu_edge )
	D.Rect( 0, 232, 256, 24, T.menu_bg )
	D.Line( slots.menu, 5, 233, 246, 22, { face = ui, size = 15, weight = 800, color = T.menu_text, hl = T.accent, overflow = "marquee", speed = 40 } )

end

DTS.RegisterLayout( "pocketpc", LAYOUT )
