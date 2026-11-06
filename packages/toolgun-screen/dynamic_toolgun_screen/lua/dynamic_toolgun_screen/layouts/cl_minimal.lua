--[[
	Minimal layout
	Few, large lines that stay readable at a glance. The big text always shrinks to fit.
]]

local DTS = DTScreen

local LAYOUT = {
	Name = "#layout.minimal.name",
	Description = "#layout.minimal.desc",
	Background = "gradient",
	Slots = {
		{ id = "top_l", label = "#layout.minimal.top_l", default = "{time}" },
		{ id = "top_r", label = "#layout.minimal.top_r", default = "{heading}" },
		{ id = "hero", label = "#layout.minimal.hero", default = "{tool}" },
		{ id = "sub", label = "#layout.minimal.sub", default = "{target}" },
		{ id = "foot_l", label = "#layout.minimal.foot_l", default = "{aim_dist}" },
		{ id = "foot_r", label = "#layout.minimal.foot_r", default = "{track_dist}" },
	}
}

function LAYOUT:Draw( D, ctx, T, slots )

	local ui = DTS.FontFace( "ui" )
	local now = RealTime()

	local corner = { face = ui, size = 20, weight = 800, color = T.hero_text, hl = T.accent, shadow = T.hero_shadow, overflow = "ellipsis" }
	D.Line( slots.top_l, 10, 6, 140, 28, corner )
	corner.align = 2
	corner.size = 17
	D.Line( slots.top_r, 150, 6, 96, 28, corner )

	D.Rect( 10, 37, 236, 2, T.accent )

	D.Line( slots.hero, 8, 56, 240, 84, {
		face = DTS.FontFace( "hero" ), size = 50, weight = 900,
		color = T.hero_text, hl = T.accent, shadow = T.hero_shadow, shadowOffset = 2,
		align = 1, overflow = "fit", minSize = 20, alpha = DTS.ToolChangeAlpha( now )
	} )

	local note = DTS.ActiveNotification( now )
	D.Line( note and note.runs or slots.sub, 8, 146, 240, 30, {
		face = ui, size = 19, weight = 700, color = T.sub_text, hl = T.accent, shadow = T.hero_shadow,
		align = 1, overflow = "marquee", speed = 40, alpha = note and note.alpha or 1
	} )

	D.Rect( 10, 214, 236, 2, T.accent )

	local foot = { face = ui, size = 18, weight = 700, color = T.hero_text, hl = T.accent, shadow = T.hero_shadow, overflow = "ellipsis" }
	D.Line( slots.foot_l, 10, 220, 118, 30, foot )
	foot.align = 2
	D.Line( slots.foot_r, 128, 220, 118, 30, foot )

end

DTS.RegisterLayout( "minimal", LAYOUT )
