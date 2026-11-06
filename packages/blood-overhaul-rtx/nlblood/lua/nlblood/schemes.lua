-- Colour schemes. "red" is the blood of humans and most NPCs, "alien" the blood of antlions, zombies,
-- headcrabs and other yellow/green bleeders.
-- A colour is the colour of thin blood; thicker blood is darker, as with real blood.
-- "natural" keeps Blood Overhaul's photographic red, "rainbow" gives every pattern its own hue,
-- "custom" reads the colour pickers in the menu.
local BO = BloodOverhaul

BO.AlienDefault = Color(199, 179, 61)

BO.Schemes = {
	{ id = "realistic", name = "Realistic", red = "natural", alien = BO.AlienDefault },
	{ id = "arterial", name = "Fresh arterial", red = Color(196, 22, 16), alien = BO.AlienDefault },
	{ id = "dark", name = "Dark venous", red = Color(118, 14, 14), alien = Color(150, 138, 42) },
	{ id = "aged", name = "Aged, dried", red = Color(104, 42, 24), alien = Color(128, 116, 54) },
	{ id = "ink", name = "Black ink", red = Color(30, 28, 34), alien = Color(30, 28, 34) },
	{ id = "toxic", name = "Toxic green", red = Color(74, 196, 42), alien = Color(74, 196, 42) },
	{ id = "blue", name = "Blue blood", red = Color(42, 92, 232), alien = Color(42, 92, 232) },
	{ id = "violet", name = "Violet", red = Color(146, 44, 206), alien = Color(146, 44, 206) },
	{ id = "gold", name = "Golden ichor", red = Color(232, 172, 32), alien = Color(232, 172, 32) },
	{ id = "synthetic", name = "Synthetic white", red = Color(236, 236, 228), alien = Color(236, 236, 228) },
	{ id = "rainbow", name = "Rainbow", red = "rainbow", alien = "rainbow" },
	{ id = "custom", name = "Custom colours", red = "custom", alien = "custom" },
}

function BO.GetScheme(id)
	for _, s in ipairs(BO.Schemes) do
		if s.id == id then return s end
	end
	return BO.Schemes[1]
end
